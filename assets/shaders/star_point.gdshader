// A star of the sky (architecture §17.19, M4-T30c): a point that faces the camera, crisp at any resolution. Its disc is
// `radius_rad` across; once that is under `min_radius_px` (1 px, so a star still covers a pixel and does not alias) the footprint
// stays at the floor and the brightness falls by (disc / floor)^2, so a star delivers the same light at every render height (the
// running lights' rule, Q26). It is drawn as a soft round point, a Gaussian SOFTNESS of its footprint wide, so its light holds
// and its brightest pixel barely changes as it crosses pixels (the tested copy is StarPointMath). Each instance's basis Z is its
// direction, so only the camera's rotation moves it; its light (colour times brightness) is the instance's custom data.
// The nebula dims the stars behind it (Q42): the panorama's alpha in the star's direction is the gas's opacity.
// It sits just in front of the far plane and is depth-tested, so a hull hides it, but writes no depth, so the flare and the motion
// blur still read the pixel as open sky.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled, ambient_light_disabled;

uniform float radius_rad = 0.0005;
// The on-screen floor, radius in pixels.
uniform float min_radius_px = 1.0;
// The nebula panorama; its alpha is the gas's opacity over the stars.
uniform sampler2D nebula : hint_default_transparent, filter_linear_mipmap, repeat_enable;
uniform bool nebula_occludes = false;
// Reversed depth just in front of the far plane (0): behind anything nearer than about 49.95 km with the cameras' 50 km far plane.
const float SKY_DEPTH = 1.0e-9;
const float SOFTNESS = 0.7;
const float KERNEL_SIGMAS = 3.0;
const float PROFILE_AREA = 1.0471975512;

varying vec3 colour;
varying float half_px;
varying float sigma_px;

void vertex() {
	vec3 direction = normalize(MODEL_MATRIX[2].xyz);
	float transmission = 1.0;
	if (nebula_occludes) {
		vec2 uv = vec2(atan(-direction.x, direction.z) / TAU + 0.5, 0.5 - asin(clamp(direction.y, -1.0, 1.0)) / PI);
		transmission = 1.0 - textureLod(nebula, uv, 3.0).a;
	}
	vec3 view_dir = normalize(mat3(MODELVIEW_MATRIX) * vec3(0.0, 0.0, 1.0));
	vec4 clip = PROJECTION_MATRIX * vec4(view_dir, 0.0);
	float real_px = radius_rad * abs(PROJECTION_MATRIX[1][1]) * 0.5 * VIEWPORT_SIZE.y;
	float ratio = min(real_px / max(min_radius_px, 0.001), 1.0);
	float footprint = max(real_px, min_radius_px);
	sigma_px = SOFTNESS * footprint;
	half_px = KERNEL_SIGMAS * sigma_px;
	float kept = 1.0 - exp(-0.5 * KERNEL_SIGMAS * KERNEL_SIGMAS);
	// The light it delivers (brightness, the floor's dimming, the gas in front) over the kernel's area.
	colour = INSTANCE_CUSTOM.rgb * ratio * ratio * transmission * PROFILE_AREA * footprint * footprint / (TAU * sigma_px * sigma_px * kept);
	vec2 ndc = 2.0 * half_px * 2.0 * VERTEX.xy / VIEWPORT_SIZE;
	POSITION = vec4(clip.xy + ndc * clip.w, SKY_DEPTH * clip.w, clip.w);
}

void fragment() {
	float r = length(UV * 2.0 - vec2(1.0)) * half_px;
	ALBEDO = colour;
	ALPHA = r > half_px ? 0.0 : exp(-0.5 * r * r / (sigma_px * sigma_px));
}
