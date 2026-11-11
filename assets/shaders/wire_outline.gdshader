// The outline of the hull in the target preview (architecture §18.20, M5-T43): a quad over the whole view that draws a line
// where the depth steps. Rounded hulls (a tank, a drum) have no crease at their outline, so the edge mesh alone leaves them
// open. The step is measured as the bend of the depth across a pixel (left + right - 2 x centre), which is zero on a flat
// face however steep, and only the nearer side of a step is drawn, so the line is one pixel wide.
shader_type spatial;
render_mode unshaded, blend_mix, depth_test_disabled, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled, ambient_light_disabled;

uniform sampler2D depth_map : hint_depth_texture, filter_nearest, repeat_disable;
uniform vec4 line_color : source_color = vec4(0.55, 1.0, 0.6, 1.0);
// A step in depth of at least this is an outline, m.
uniform float step_m = 1.0;

void vertex() {
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}

float view_depth(vec2 uv, mat4 inv_projection) {
	vec4 view = inv_projection * vec4(uv * 2.0 - 1.0, texture(depth_map, uv).r, 1.0);
	return -view.z / view.w;
}

void fragment() {
	vec2 px = 1.0 / VIEWPORT_SIZE;
	float here = view_depth(SCREEN_UV, INV_PROJECTION_MATRIX);
	float across = view_depth(SCREEN_UV - vec2(px.x, 0.0), INV_PROJECTION_MATRIX) + view_depth(SCREEN_UV + vec2(px.x, 0.0), INV_PROJECTION_MATRIX);
	float along = view_depth(SCREEN_UV - vec2(0.0, px.y), INV_PROJECTION_MATRIX) + view_depth(SCREEN_UV + vec2(0.0, px.y), INV_PROJECTION_MATRIX);
	float bend = max(across, along) - 2.0 * here;
	ALBEDO = line_color.rgb;
	ALPHA = step(step_m, bend);
}
