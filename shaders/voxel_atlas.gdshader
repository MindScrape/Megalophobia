shader_type spatial;
render_mode cull_back;

uniform sampler2D atlas_texture : source_color, filter_nearest, repeat_enable;
uniform vec2 atlas_grid = vec2(16.0, 16.0);

void fragment() {
	vec2 tile_size = 1.0 / atlas_grid;

	vec2 repeated_uv = fract(UV);
	vec2 tile_coord = COLOR.rg * 255.0;

	vec2 atlas_uv = tile_coord * tile_size + repeated_uv * tile_size;

	ALBEDO = texture(atlas_texture, atlas_uv).rgb;
}
