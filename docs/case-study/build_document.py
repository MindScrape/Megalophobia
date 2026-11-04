"""Build the Markdown case study and its two-page PDF from the measured fixtures."""
from pathlib import Path
import hashlib
import json
import os
import subprocess
from xml.sax.saxutils import escape
from PIL import Image
from reportlab.pdfgen import canvas
from reportlab.lib.colors import HexColor, white
from reportlab.lib.styles import ParagraphStyle
from reportlab.platypus import Paragraph
from reportlab.lib.utils import ImageReader
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont

ROOT = Path(__file__).resolve().parents[2]
ASSETS = ROOT / 'docs/case-study'
M = json.loads((ASSETS / 'measurements.json').read_text())
S = json.loads((ASSETS / 'snapshot-isolation.json').read_text())
assert S['failed'] == 0
T = M['meshing']['terrain']
P = M['persistence']
REPO = 'https://github.com/MindScrape/Megalophobia'
PDF = ROOT / 'output/pdf/megalophobia-technical-case-study.pdf'
PDF.parent.mkdir(parents=True, exist_ok=True)
SECTIONS = [
    {
        'title': 'Stream terrain with bounded work',
        'body': 'The world loads nearby 16 x 16 x 16 chunks first. Separate frame budgets spread loading and unloading over time; a wider unload radius reduces churn at the boundary. Background rebuilds have an eight-task limit, while player edits receive priority.',
        'image': 'streaming.png',
        'caption': 'Scheduler fixture: 620 manual ticks, radius 4, and an eight-chunk move. The observed limits were one spawn and two unload attempts per tick. Terrain generation was excluded.',
        'tradeoff': 'Budgets bound request counts, not frame time. Failed unload retries are a known correctness issue in the current streamer.',
        'code': [('Streaming', '../scripts/chunk_streamer.gd'), ('Rebuild scheduling', '../scripts/world.gd')],
    },
    {
        'title': 'Reduce geometry before rendering',
        'body': f'Greedy meshing merges adjacent faces with the same block type and orientation. The atlas shader repeats block textures across those larger rectangles. In one procedural chunk, {T["exposed_unit_faces"]:,} exposed unit faces became {T["greedy_quads"]:,} merged quads. Surface shape determines how much can merge.',
        'image': 'meshing.png',
        'caption': 'The isolated solid-chunk comparison uses the same outer surface: 1,536 unit quads versus six merged quads. This is a geometry reduction, not an FPS speedup.',
        'tradeoff': 'Caves and irregular surfaces merge less effectively. Edits currently rebuild the entire affected chunk, including collision.',
        'code': [('Greedy sweeps', '../scripts/chunk.gd'), ('Atlas shader', '../shaders/voxel_atlas.gdshader')],
    },
    {
        'title': 'Keep asynchronous edits consistent',
        'body': 'A request now explicitly copies its own voxels, neighboring voxels, and saved edit data before entering the worker pool. A per-chunk guard rejects duplicate dispatch, and revision checks discard stale mesh results. Repeated edits share one pending rebuild entry.',
        'image': 'concurrency.png',
        'caption': 'A semaphore-controlled worker regression passes all five checks after the copy fix. Separately, injected completions show revision 0 rejected and revision 3 applied after three edits.',
        'tradeoff': 'Snapshot copies add allocation and main-thread work. These checks cover specific interleavings; worker lifecycle and shutdown still need hardening.',
        'code': [('Async mesh path', '../scripts/chunk.gd'), ('Snapshot regression', 'case-study/check_snapshot_isolation.gd')],
    },
    {
        'title': 'Persist changes to a reproducible world',
        'body': f'Fixed seeds regenerate the base terrain. Storage records edited voxel indices and replacement block IDs, then replays them on load. In a three-edit fixture, the saved dictionary occupied {P["delta_file_bytes"]:,} bytes versus {P["full_chunk_variant_bytes"]:,} bytes for the full chunk in the same serialization format. Reconstructed arrays matched exactly.',
        'image': 'persistence.png',
        'caption': 'The storage helpers were exercised directly with temporary files. Normal debug gameplay disables disk saves; release-mode save and failure recovery are separate validation work.',
        'tradeoff': 'Save failures currently clear dirty state, and the edit cache has no eviction policy. Both are tracked in the engineering backlog.',
        'code': [('Chunk storage', '../scripts/chunk_store.gd'), ('Storage fixture', 'case-study/storage_fixture.gd')],
    },
]

intro = 'An independent voxel prototype in Godot 4.6 and GDScript. The engineering focus is deciding which work to do, reducing the amount of work, and keeping player edits consistent as background tasks finish.'
method = f'Controlled local fixtures on {M["cpu"]}, Godot {M["godot"]}, debug build. The procedural sample at {tuple(T["chunk_coord"])} took {T["greedy_cpu_median_ms"]:.2f} ms median and {T["greedy_cpu_p95_ms"]:.2f} ms p95 across 30 measured runs after three warmups. This times only the three greedy axis passes and output arrays; it excludes voxel generation, mesh upload, collision, and rendering.'
next_steps = 'Next: empty-mesh handling, reliable unload retries, boundary-face ownership, complete task cleanup, and failed-save recovery. These are tracked with verification criteria in the engineering backlog.'

md = ['# Megalophobia technical case study', '', intro, '', f'[Repository]({REPO}) | [Two-page PDF](../output/pdf/megalophobia-technical-case-study.pdf)', '', '## Demonstrated engineering decisions', '']
for index, section in enumerate(SECTIONS, 1):
    md += [f'### {index} {section["title"]}', '', section['body'], '', f'![{section["title"]}](case-study/{section["image"]})', '', section['caption'], '', f'**Tradeoff:** {section["tradeoff"]}', '', 'Code: ' + ', '.join(f'[{name}]({path})' for name, path in section['code']) + '.', '']
md += ['## Measurements and reproduction', '', method, '', 'These results cover controlled fixtures, not a gameplay frame-time or memory benchmark. The screenshots are instrumented Godot demonstrations generated from those results; the scheduler uses a request-recording world, and revision completion order is injected deliberately.', '', '[Raw measurements](case-study/measurements.json), [snapshot checks](case-study/snapshot-isolation.json), and the [source manifest](case-study/source-manifest.json) identify the evidence. The source fingerprints identify the exact game files used by these fixtures. Regenerating the results after changing terrain or streaming settings will produce a new source manifest and may change the measurements.', '', 'From the repository root, using Godot 4.6.1:', '', '```sh', 'godot --headless --path . --script docs/case-study/check_snapshot_isolation.gd', 'godot --headless --path . --script docs/case-study/measure.gd', 'godot --headless --path . --script docs/case-study/check_review_findings.gd', 'godot --path . --script docs/case-study/capture.gd --resolution 1280x520', 'python3 docs/case-study/build_document.py', '```', '', 'The PDF builder uses ReportLab and Pillow, plus Arial fonts from macOS. Run the measurement step before the graphical capture; storage fixtures use disposable files under `/private/tmp/megalophobia-case-study/`.', '', '## Remaining work', '', next_steps, '', '[Prioritized engineering fixes](engineering-fixes.md)', '']
(ROOT / 'docs/technical-case-study.md').write_text('\n'.join(md))

paths = ['scripts/chunk.gd', 'scripts/chunk_streamer.gd', 'scripts/chunk_store.gd', 'scripts/world.gd', 'scripts/terrain_generator.gd', 'scripts/voxel_constants.gd', 'scripts/player.gd', 'scripts/debug_hud.gd', 'shaders/voxel_atlas.gdshader']
manifest = {'base_commit': os.environ.get('MEGALOPHOBIA_CASE_STUDY_BASE') or subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip(), 'sha256': {p:hashlib.sha256((ROOT / p).read_bytes()).hexdigest() for p in paths}}
(ASSETS / 'source-manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')

for name, filename in [('Arial', 'Arial.ttf'), ('Arial-Bold', 'Arial Bold.ttf'), ('Arial-Italic', 'Arial Italic.ttf')]:
    pdfmetrics.registerFont(TTFont(name, f'/System/Library/Fonts/Supplemental/{filename}'))
INK = HexColor('#132b39')
GREEN = HexColor('#087e68')
MUTED = HexColor('#526875')
WIDTH = 528
STYLES = {
    'body': ParagraphStyle('body', fontName='Arial', fontSize=10.1, leading=13.5, textColor=INK),
    'caption': ParagraphStyle('caption', fontName='Arial', fontSize=8.8, leading=11.5, textColor=MUTED),
    'small': ParagraphStyle('small', fontName='Arial', fontSize=8.8, leading=11.7, textColor=MUTED),
}

def paragraph(c, text, y, style='body'):
    para = Paragraph(escape(text), STYLES[style])
    _, height = para.wrap(WIDTH, 1000)
    para.drawOn(c, 42, y - height)
    return y - height


def footer(c, page):
    c.setStrokeColor(HexColor('#d6e2e7'))
    c.line(42, 46, 570, 46)
    c.setFont('Arial', 8)
    c.setFillColor(MUTED)
    c.drawString(42, 31, 'MEGALOPHOBIA  |  LOCAL PROTOTYPE  |  CONTROLLED FIXTURES')
    c.drawRightString(570, 31, f'{page} / 2')


def section(c, index, entry, y):
    c.setFillColor(GREEN)
    c.roundRect(42, y - 19, 20, 20, 3, fill=1, stroke=0)
    c.setFillColor(white)
    c.setFont('Arial-Bold', 10)
    c.drawCentredString(52, y - 13, str(index))
    c.setFillColor(INK)
    c.setFont('Arial-Bold', 14)
    c.drawString(72, y - 14, entry['title'])
    y = paragraph(c, entry['body'], y - 30) - 10
    with Image.open(ASSETS / entry['image']) as image:
        scale = image.width / 1280
        cropped = image.crop((0, int(96 * scale), image.width, int(426 * scale)))
        height = WIDTH * cropped.height / cropped.width
        c.drawImage(ImageReader(cropped), 42, y - height, width=WIDTH, height=height)
    y = paragraph(c, entry['caption'], y - height - 8, 'caption') - 18
    return y


c = canvas.Canvas(str(PDF), pagesize=(612, 792))
c.setTitle('Megalophobia technical case study')
c.setAuthor('Megalophobia')
c.setSubject('Voxel streaming, greedy meshing, asynchronous edit correctness, and incremental persistence')
c.setFillColor(GREEN)
c.setFont('Arial-Bold', 9)
c.drawString(42, 752, 'TECHNICAL CASE STUDY  /  NOVEMBER 2026')
c.setFillColor(INK)
c.setFont('Arial-Bold', 30)
c.drawString(42, 719, 'Megalophobia')
c.setFont('Arial', 14)
c.drawString(42, 695, 'Engineering a procedural voxel world')
c.setFillColor(GREEN)
c.setFont('Arial', 9)
c.drawString(42, 676, REPO)
c.linkURL(REPO, (42, 673, 330, 686), relative=0)
y = paragraph(c, intro, 657) - 19
y = section(c, 1, SECTIONS[0], y)
y = section(c, 2, SECTIONS[1], y)
y = paragraph(c, 'Source hashes, raw results, and reproduction commands accompany this study in docs/technical-case-study.md. Measurements cover controlled fixtures rather than gameplay frame time.', y, 'small')
assert y >= 54, ('Page 1 overflow', y)
footer(c, 1)
c.showPage()
c.setFillColor(GREEN)
c.setFont('Arial-Bold', 9)
c.drawString(42, 752, 'MEGALOPHOBIA  /  CORRECTNESS AND PERSISTENCE')
c.setFillColor(INK)
c.setFont('Arial-Bold', 25)
c.drawString(42, 719, 'Keep edits consistent')
y = paragraph(c, 'The prototype separates worker input isolation, stale-result rejection, and change storage. Each protection has a focused, repeatable check.', 695) - 18
y = section(c, 3, SECTIONS[2], y)
y = section(c, 4, SECTIONS[3], y)
summary = f'Greedy CPU sample: {T["greedy_cpu_median_ms"]:.2f} ms median, {T["greedy_cpu_p95_ms"]:.2f} ms p95; 30 runs after 3 warmups on {M["cpu"]}, Godot 4.6.1 debug. Axis passes only, excluding generation, upload, collision, and rendering.'
y = paragraph(c, summary, y, 'small') - 7
y = paragraph(c, next_steps, y, 'small')
assert y >= 54, ('Page 2 overflow', y)
footer(c, 2)
c.save()
print(f'Built {PDF} (2 pages). Last content baseline: {y:.1f} pt.')
