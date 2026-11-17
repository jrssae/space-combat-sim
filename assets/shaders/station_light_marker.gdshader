// The station's small lights (M7-T18): beacons, navigation lights and bay lamps, each a soft additive point facing the camera at its
// place on the hull. Up close it has its real size; once that shrinks under the pixel floor (at 1080p, scaled with the view) it keeps
// the floor and its brightness falls with the inverse square of distance (a running light's rule, RunningLightDimming), so the pattern
// reads at a few km to tens of km and is gone past that: below `cull_peak` it is not drawn. It keeps its centre's depth, so the hull hides it.
// Per instance: the colour as linear light before `gain` (rgb) and the radius on the hull in metres (a).
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled, ambient_light_disabled;

uniform float min_radius_px = 2.0;
// Peak brightness under which the point is dropped (RunningLightDimming.CULL_PEAK).
uniform float cull_peak = 0.01;
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
	dim = ratio * ratio;
	float peak = dim * gain * max(colour.r, max(colour.g, colour.b));
	vec2 ndc = 2.0 * max(real_px, floor_px) * 2.0 * VERTEX.xy / VIEWPORT_SIZE;
	if (peak < cull_peak) {
		ndc = vec2(0.0);  // too faint to light a pixel: collapse it
	}
	POSITION = vec4(clip.xy + ndc * clip.w, clip.z, clip.w);
}

void fragment() {
	float r = length(UV * 2.0 - vec2(1.0));
	float core = max(1.0 - r * r, 0.0);
	ALBEDO = colour * dim * gain;
	ALPHA = core * core;
}
