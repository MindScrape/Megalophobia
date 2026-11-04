# Megalophobia engineering fixes

Priorities for making the prototype reliable and its technical case study defensible. P1 items affect correctness or cleanup; P2 items improve performance, usability, or observability. This list describes the source used by the case-study fixtures.

## Fixed

- [x] **Isolate worker inputs.** `generate_mesh_async()` now duplicates its own voxel array, each neighboring voxel array, and the pending edit dictionary before dispatch. Previously, assignment shared those mutable inputs with the main thread. A semaphore-controlled regression check reproduced all three failures before the fix and passes afterward. See [chunk.gd](../scripts/chunk.gd) and [the check](case-study/check_snapshot_isolation.gd).

## Fix before relying on correctness or performance claims

1. **P1 - Handle chunks with no geometry.** `_compute_mesh_data()` calls `add_surface_from_arrays()` even when the vertex array is empty. Air and fully enclosed chunks can hit this path; the earlier capture run logged invalid empty-surface errors. Return an empty mesh and no collision shape without submitting a surface. Verify air-only and fully enclosed chunks finish rebuilding without engine errors. [Code](../scripts/chunk.gd)

2. **P1 - Retry busy unloads and recheck their distance.** `unload_chunk()` declines to free a chunk with an active worker, but the streamer has already removed the request. It is only reconsidered after another player chunk change. The review fixture reproduces an out-of-range chunk staying loaded after its worker finishes while the player stands still. Queued requests also need a fresh distance check when the player turns back. Return a result, retry busy chunks, and discard requests that have become nearby. [Streamer](../scripts/chunk_streamer.gd), [world](../scripts/world.gd), [reproduction](case-study/check_review_findings.gd)

3. **P1 - Emit each boundary face from its owning chunk.** The greedy sweep can emit a neighboring chunk's solid face when the local cell is air. A completely empty chunk next to stone currently generates one merged quad for that neighbor, which can duplicate the neighbor's own boundary face. Restrict emission to faces whose solid voxel belongs to this chunk. Verify adjacent solid/air chunks have exactly one shared-boundary surface. [Code](../scripts/chunk.gd), [reproduction](case-study/check_review_findings.gd)

4. **P1 - Complete the worker lifecycle and investigate shutdown.** Each dispatch overwrites `_mesh_task_id`, while the only explicit wait is for the latest task when the node exits. Track and collect every submitted task, stop new dispatches during shutdown, and drain deferred application before freeing dependent objects. A previous capture process reported a `recursive_mutex` exception on shutdown; its root cause is not yet established. Verify repeated edit/unload/exit cycles without hangs, leaked tasks, or shutdown exceptions. [Code](../scripts/chunk.gd)

5. **P1 - Keep failed saves dirty.** `_save_to_disk()` reports no result, and `flush()` clears the dirty flag even if opening the file failed. Return success or an error, retain dirty data on failure, and use a temporary file plus atomic replacement. Validate a release build, including a failed write and subsequent retry. Debug gameplay intentionally skips disk saving; the case-study fixture only exercises the serialization helpers. [Code](../scripts/chunk_store.gd)

## Improve after the correctness work

6. **P2 - Avoid repeated surface-noise calculations.** Voxel generation recomputes the same surface height for every Y cell in a column. Calculate it once per X/Z column, then profile generation separately from meshing, collision creation, and main-thread application. Verify generated block IDs remain identical. [Generator](../scripts/terrain_generator.gd), [chunk loop](../scripts/chunk.gd)

7. **P2 - Bound retained data and priority work.** The edit cache has no eviction policy, and priority tasks bypass the background concurrency limit. Add counters and explicit policies for cache growth and priority dispatch under sustained edits. Measure latency and memory before choosing limits. [Storage](../scripts/chunk_store.gd), [scheduler](../scripts/world.gd)

8. **P2 - Finish mouse capture and texture checks.** Escape releases the mouse with no way to recapture it, and the UV helpers contain an unresolved orientation note. Add a deliberate recapture action and verify the top, bottom, and all side faces using an asymmetric test texture. [Player](../scripts/player.gd), [UV helpers](../scripts/chunk.gd)

## Evidence for the case study

The controlled fixtures currently measure geometry counts, a greedy-meshing CPU sample, scheduler request budgets, revision rejection, and a three-edit serialization round trip. They do not establish gameplay frame time, peak memory, or broad thread safety. After the P1 work, capture a fixed camera route and report frame-time percentiles, generation/mesh/collision timings, loaded chunks, outstanding tasks, and memory with the same seed and settings.

The source manifest records exact file hashes. Regenerate the fixtures when the source or world settings change so the case study stays aligned with the code.
