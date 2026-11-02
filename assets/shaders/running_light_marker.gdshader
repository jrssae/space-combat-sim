// A running light (architecture §7.3, M3-T27): a soft additive point that faces the camera, a real size up close and never smaller
// than `min_radius_px` on screen, so it stays a point at several km with no per-frame work on the CPU. It keeps the depth of its
// centre, so the hull depth proxy hides it behind a hull.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled, ambient_light_disabled;

// HDR colour.
uniform vec3 tint = vec3(1.0);
uniform float radius_m = 0.1;
uniform float min_radius_px = 3.0;

void vertex() {
	vec4 clip = PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0);
	float real_px = radius_m * abs(PROJECTION_MATRIX[1][1]) * 0.5 * VIEWPORT_SIZE.y / max(clip.w, 0.001);
	vec2 ndc = 2.0 * max(real_px, min_radius_px) * 2.0 * VERTEX.xy / VIEWPORT_SIZE;
	POSITION = vec4(clip.xy + ndc * clip.w, clip.z, clip.w);
}

void fragment() {
	float r = length(UV * 2.0 - vec2(1.0));
	float falloff = max(1.0 - r * r, 0.0);
	ALBEDO = tint;
	ALPHA = falloff * falloff;
}
