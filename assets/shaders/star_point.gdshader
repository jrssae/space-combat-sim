// A star of the sky (architecture §17.19, M4-T30c): a point that faces the camera, crisp at any resolution. Its disc is
// `radius_rad` across; once that is under `min_radius_px` (1 px, so a star still covers a pixel and does not alias) the footprint
// stays at the floor and the brightness falls by (disc / floor)^2, so a star delivers the same light at every render height (the
// running lights' rule, Q26; the tested copy is StarPointMath). Each instance's basis Z is its direction, so only the camera's
// rotation moves it, never its position; its light (colour times brightness) is the instance's custom data.
// It sits just in front of the far plane and is depth-tested, so a hull hides it, but writes no depth, so the flare and the motion
// blur still read the pixel as open sky.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled, ambient_light_disabled;

uniform float radius_rad = 0.0005;
// The on-screen floor, radius in pixels.
uniform float min_radius_px = 1.0;
// Reversed depth just in front of the far plane (0): behind anything nearer than about 49.95 km with the cameras' 50 km far plane.
const float SKY_DEPTH = 1.0e-9;

varying float dim;
varying vec3 colour;

void vertex() {
	colour = INSTANCE_CUSTOM.rgb;
	vec3 view_dir = normalize(mat3(MODELVIEW_MATRIX) * vec3(0.0, 0.0, 1.0));
	vec4 clip = PROJECTION_MATRIX * vec4(view_dir, 0.0);
	float real_px = radius_rad * abs(PROJECTION_MATRIX[1][1]) * 0.5 * VIEWPORT_SIZE.y;
	float ratio = min(real_px / max(min_radius_px, 0.001), 1.0);
	dim = ratio * ratio;
	vec2 ndc = 2.0 * max(real_px, min_radius_px) * 2.0 * VERTEX.xy / VIEWPORT_SIZE;
	POSITION = vec4(clip.xy + ndc * clip.w, SKY_DEPTH * clip.w, clip.w);
}

void fragment() {
	float r = length(UV * 2.0 - vec2(1.0));
	float falloff = max(1.0 - r * r, 0.0);
	ALBEDO = colour * dim;
	ALPHA = falloff * falloff;
}
