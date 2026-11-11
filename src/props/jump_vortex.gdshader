shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;
// A jumpgate's vortex (M6-T14, D69): streaky, feathered light spiralling in to a dark eye on a funnel of unit radius.
// UV.x runs round the funnel, UV.y from the ragged rim (0) to the eye (1). The colours come from the gate's hardpoints:
// blue for an arrival, orange to golden yellow for a departure. `swirl_time` is sim time, so a pause freezes the swirl.

uniform vec3 colour = vec3(0.045, 0.23, 0.9);
uniform vec3 highlight = vec3(0.38, 0.65, 1.0);
uniform float level = 1.0;
uniform float intensity = 2.5;
uniform float swirl_time = 0.0;
// +1 or -1: arrivals turn one way, departures the other.
uniform float spin = 1.0;
uniform float arms = 5.0;
uniform float twist = 3.0;

float hash(vec3 p) {
	p = fract(p * 0.3183099 + vec3(0.1, 0.2, 0.3));
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float vnoise(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	float n000 = hash(i);
	float n100 = hash(i + vec3(1.0, 0.0, 0.0));
	float n010 = hash(i + vec3(0.0, 1.0, 0.0));
	float n110 = hash(i + vec3(1.0, 1.0, 0.0));
	float n001 = hash(i + vec3(0.0, 0.0, 1.0));
	float n101 = hash(i + vec3(1.0, 0.0, 1.0));
	float n011 = hash(i + vec3(0.0, 1.0, 1.0));
	float n111 = hash(i + vec3(1.0, 1.0, 1.0));
	return mix(mix(mix(n000, n100, f.x), mix(n010, n110, f.x), f.y), mix(mix(n001, n101, f.x), mix(n011, n111, f.x), f.y), f.z);
}

void fragment() {
	float a = UV.x * TAU;
	float v = UV.y;
	// Noise sampled on a circle so it wraps round the funnel with no seam.
	vec3 ring = vec3(cos(a) * 2.5, sin(a) * 2.5, v * 5.0 - swirl_time * 0.4 * spin);
	float n = vnoise(ring) * 0.6 + vnoise(ring * 2.3) * 0.4;
	float s = UV.x * arms + v * twist * (1.0 + v) - swirl_time * 0.35 * spin + n * 0.8;
	float streak = pow(0.5 + 0.5 * sin(TAU * s), 5.0);
	float fine = pow(0.5 + 0.5 * sin(TAU * (s * 3.0 + n)), 8.0);
	// A soft, ragged rim and a dark eye.
	float rim = smoothstep(0.0, 0.18 + 0.12 * n, v);
	float eye = 1.0 - smoothstep(0.7, 0.98, v);
	float glow = (0.25 + 0.9 * streak + 0.5 * fine) * rim * eye;
	vec3 c = mix(colour, highlight, clamp(streak * 0.8 + fine * 0.6, 0.0, 1.0));
	ALBEDO = c * glow * intensity * level;
}
