// A running light (architecture §7.3, M3-T27, M4-T28): a soft additive point that faces the camera. Up close it has its real size.
// Once that shrinks under `min_radius_px` (1 px, so a point still covers a pixel and does not alias) the footprint stays at the floor and
// the brightness falls with the inverse square of distance, so the light matches what the real disc would deliver and a far light is a
// faint point, not a globe (space has no atmosphere to scatter it). All in the vertex shader, no per-frame work on the CPU. It keeps
// the depth of its centre, so the hull depth proxy hides it behind a hull.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled, ambient_light_disabled;

// HDR colour.
uniform vec3 tint = vec3(1.0);
// AI ships draw their three markers as one multimesh (M4-T11): each instance's colour is its custom data, not `tint`.
uniform bool use_instance_tint = false;
uniform float radius_m = 0.1;
// The on-screen floor, radius in pixels (settings.running_light_min_px).
uniform float min_radius_px = 1.0;

// 1 while the real disc is at least the floor, else (real / floor)^2. The tested copy is RunningLightDimming.brightness_factor.
varying float dim;
varying vec3 colour;

void vertex() {
	colour = use_instance_tint ? INSTANCE_CUSTOM.rgb : tint;
	vec4 clip = PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0);
	float real_px = radius_m * abs(PROJECTION_MATRIX[1][1]) * 0.5 * VIEWPORT_SIZE.y / max(clip.w, 0.001);
	float ratio = min(real_px / max(min_radius_px, 0.001), 1.0);
	dim = ratio * ratio;
	vec2 ndc = 2.0 * max(real_px, min_radius_px) * 2.0 * VERTEX.xy / VIEWPORT_SIZE;
	POSITION = vec4(clip.xy + ndc * clip.w, clip.z, clip.w);
}

void fragment() {
	float r = length(UV * 2.0 - vec2(1.0));
	float falloff = max(1.0 - r * r, 0.0);
	ALBEDO = colour * dim;
	ALPHA = falloff * falloff;
}
