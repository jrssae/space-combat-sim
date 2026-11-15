// The station's small lights (M7-T18): beacons, navigation lights and bay lamps, each a soft additive point facing the camera at its
// place on the hull. Up close it has its real size; once that shrinks under the pixel floor (at 1080p, scaled with the view) it keeps
// the floor and fades only a little, so the pattern still reads at 10 km. It keeps its centre's depth, so the hull hides it.
// Per instance: the colour as linear light before `gain` (rgb) and the radius on the hull in metres (a).
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled, ambient_light_disabled;

uniform float min_radius_px = 3.0;
uniform float far_dim = 0.85;
uniform float gain = 4.0;

varying float dim;
varying vec3 colour;

void vertex() {
	colour = INSTANCE_CUSTOM.rgb;
	float radius = INSTANCE_CUSTOM.a * length(MODEL_MATRIX[0].xyz);
	vec4 clip = PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0);
	float real_px = radius * abs(PROJECTION_MATRIX[1][1]) * 0.5 * VIEWPORT_SIZE.y / max(clip.w, 0.001);
	float floor_px = min_radius_px * VIEWPORT_SIZE.y / 1080.0;
	float ratio = min(real_px / max(floor_px, 0.001), 1.0);
	dim = max(ratio * ratio, far_dim);
	vec2 ndc = 2.0 * max(real_px, floor_px) * 2.0 * VERTEX.xy / VIEWPORT_SIZE;
	POSITION = vec4(clip.xy + ndc * clip.w, clip.z, clip.w);
}

void fragment() {
	float r = length(UV * 2.0 - vec2(1.0));
	float core = max(1.0 - r * r, 0.0);
	ALBEDO = colour * dim * gain;
	ALPHA = core * core;
}
