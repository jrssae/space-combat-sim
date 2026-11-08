// A far death as a point flash (architecture §17.14, M4-T23): one instance of the world's `FarFlashes` multimesh, facing the
// camera. Its footprint is the flash's real angular size, never under `min_radius_px` (1 px); under that it keeps the floor
// and dims by the inverse square, as a running light and a far dot do, so the light it delivers falls with distance as light
// does (`ExplosionLod.on_screen` is the same maths). The instance's custom data holds its colour times its brightness now (rgb,
// linear) and its radius in metres (a). Additive; it keeps the depth of its centre, so nearer hulls hide it.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled, ambient_light_disabled;

// The on-screen floor, radius in pixels.
uniform float min_radius_px = 1.0;

varying vec3 light;
varying float dim;

void vertex() {
	light = INSTANCE_CUSTOM.rgb;
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
	ALBEDO = light * dim * falloff;
}
