// A far ship as a point (architecture §17.10, M4-T11): one instance of the world's `FarDots` multimesh, facing the camera. Its
// footprint is the hull's real angular size, never under `min_radius_px` (1 px); under that it keeps the floor and dims by the
// inverse square, as a running light does (§7.3), so a far hull fades instead of staying a fixed blob. The instance's custom
// data holds its paint (rgb, linear) and its hull radius in metres (a). Alpha-blended; it keeps the depth of its centre, so
// nearer hulls hide it.
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled, ambient_light_disabled;

// The on-screen floor, radius in pixels.
uniform float min_radius_px = 1.0;

varying vec3 paint;
varying float dim;

void vertex() {
	paint = INSTANCE_CUSTOM.rgb;
	vec4 clip = PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0);
	float real_px = INSTANCE_CUSTOM.a * abs(PROJECTION_MATRIX[1][1]) * 0.5 * VIEWPORT_SIZE.y / max(clip.w, 0.001);
	float ratio = min(real_px / max(min_radius_px, 0.001), 1.0);
	dim = ratio * ratio;
	vec2 ndc = 2.0 * max(real_px, min_radius_px) * 2.0 * VERTEX.xy / VIEWPORT_SIZE;
	POSITION = vec4(clip.xy + ndc * clip.w, clip.z, clip.w);
}

void fragment() {
	float r = length(UV * 2.0 - vec2(1.0));
	float falloff = max(1.0 - r * r, 0.0);
	ALBEDO = paint;
	ALPHA = falloff * dim;
}
