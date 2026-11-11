shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_always, cull_disabled, shadows_disabled;
// A jump vortex's funnel (M6-T19, D69): a shallow funnel of the base colour with small, darker, soft-edged patches and paler
// translucent ones drifting in a spiral along it; the rim fades out. The funnel unfolds from its centre to the rim as it opens.
// Its narrow end looks black from in front, down the funnel, and glows white from the side or behind.
//
// The mesh is a unit grid: UV.x round the funnel, UV.y from the rim (0) to the narrow end (1); the node's scale gives the mouth's
// radius (x, y) and the depth (z, behind the mouth). `swirl_time` is sim time, so a pause freezes the motion.

uniform vec3 colour = vec3(0.045, 0.23, 0.9);
uniform vec3 highlight = vec3(0.38, 0.65, 1.0);
// 0..1: how far the funnel has unfolded from its centre toward the rim.
uniform float growth = 1.0;
uniform float intensity = 1.0;
uniform float swirl_time = 0.0;
// +1 or -1: arrivals turn and drift one way, departures the other.
uniform float spin = 1.0;
// The narrow end's radius and how the depth gathers toward it (1 a cone; higher, a shallow bowl round a deeper throat).
uniform float eye = 0.035;
uniform float throat = 2.6;
// The rim fades from this share of the radius to nothing at the rim.
uniform float rim_fade_from = 0.68;
uniform vec3 base_glow = vec3(1.25, 1.25, 1.35);

varying float v_s;
varying float v_glow;

float profile_r(float s) {
	return eye + (1.0 - eye) * s;
}

float profile_z(float s) {
	return pow(1.0 - s, throat);
}

float hash2(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

// A field of soft-edged, roughly rectangular patches on a spiral grid: `around` cells round the funnel, rows a cell tall in
// log radius, the rows sheared `turns` cells per turn so they lie along spirals, each row slid by its own amount so they do not
// line up. `drift` moves them along the spiral. Returns the patch's cover (0..1) and its random tone in y.
vec2 patches(float u, float r, float around, float turns, float drift, float seed, float fill) {
	float a = u * around;
	float b = log(r) * around / TAU;
	vec2 q = vec2(a + drift, b - turns * u);
	float row = floor(q.y);
	// A row's slide repeats every `turns` rows, so the wrap round the funnel stays seamless.
	q.x += hash2(vec2(mod(row, turns), seed)) * 7.0;
	vec2 cell = floor(q);
	// The wrap round the funnel: a cell past the seam is the same cell as at its start, rows offset by `turns`.
	float lap = floor(cell.x / around);
	vec2 id = vec2(cell.x - lap * around, cell.y + lap * turns) + seed;
	float h1 = hash2(id);
	float h2 = hash2(id + 17.7);
	float h3 = hash2(id + 41.3);
	if (h1 > fill) {
		return vec2(0.0);
	}
	vec2 f = fract(q) - 0.5 - (vec2(h2, h3) - 0.5) * vec2(0.3, 0.3);
	vec2 half_size = vec2(0.3 + 0.18 * h2, 0.1 + 0.1 * h3);
	vec2 d = abs(f) - half_size;
	float sd = length(max(d, 0.0)) + min(max(d.x, d.y), 0.0);
	return vec2(1.0 - smoothstep(-0.2, 0.24, sd), h3);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash2(i), hash2(i + vec2(1.0, 0.0)), f.x), mix(hash2(i + vec2(0.0, 1.0)), hash2(i + vec2(1.0, 1.0)), f.x), f.y);
}

void vertex() {
	float s = 1.0 - UV.y;
	// Unfolding: the part from the centre out to `growth` keeps its final shape, slid forward so its edge stays in the mouth's
	// plane; the rest waits folded at that edge.
	float se = min(s, growth);
	float r = profile_r(se) * smoothstep(0.0, 0.02, growth);
	float a = UV.x * TAU;
	VERTEX = vec3(cos(a) * r, sin(a) * r, profile_z(se) - profile_z(growth));
	v_s = s;
	// The view against the axis (+Z, into the funnel): -1 straight down it from in front, 0 from the side, +1 from behind.
	vec3 mouth = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	vec3 axis = normalize(MODEL_MATRIX[2].xyz);
	vec3 cam = INV_VIEW_MATRIX[3].xyz;
	float t = dot(normalize(cam - mouth + axis * 1e-3), axis);
	v_glow = smoothstep(-0.45, -0.05, t);
}

void fragment() {
	float s = v_s;
	float r = profile_r(s);
	float u = UV.x;
	float t = swirl_time;
	// The layers: a base a little paler than the opener's colour, unevenly washed along the spiral, with fine streaks.
	vec3 base = mix(colour, highlight, 0.22);
	float wash = vnoise(vec2(u * 20.0 - t * 0.3 * spin, log(r) * 5.0 - u * 3.0));
	// Fine feathery streaks along the spiral, the same slant as the patches.
	float sp = log(r) * 64.0 / TAU - 25.0 * u;
	float streak = vnoise(vec2(u * 200.0 - t * 1.5 * spin, sp * 4.0)) * 0.6 + vnoise(vec2(u * 90.0 - t * spin, sp * 2.0)) * 0.4;
	vec3 c = base * (0.65 + 0.45 * wash) * (0.7 + 0.6 * streak);
	// Paler, translucent patches of the base colour, drifting slowly.
	vec2 light = patches(u, r, 64.0, 25.0, -spin * t * 1.1, 3.0, 0.8);
	c = mix(c, mix(highlight, vec3(1.0), 0.15) * 1.05, light.x * (0.25 + 0.3 * light.y));
	// The small dark patches, faster, drifting along the spiral.
	vec2 dark = patches(u, r, 80.0, 32.0, -spin * t * 1.7, 0.0, 0.6);
	c = mix(c, colour * 0.3, dark.x * (0.5 + 0.35 * dark.y));
	// The narrow end: black down the funnel from in front, a white glow from the side or behind.
	float deep = 1.0 - smoothstep(0.04, 0.7, r);
	deep *= deep * (3.0 - 2.0 * deep);
	float glow = 1.0 - smoothstep(0.04, 0.16, r);
	c = mix(c * (1.0 - deep * (1.0 - v_glow)), base_glow, glow * v_glow);
	// The rim fades out raggedly in wisps; the unfolding edge is soft.
	float wisps = vnoise(vec2(u * 70.0, t * 0.5)) * 0.6 + vnoise(vec2(u * 170.0, 3.0 + t * 0.7)) * 0.4;
	float rim = 1.0 - smoothstep(rim_fade_from, 1.0, r + (wisps - 0.5) * 0.18 * smoothstep(rim_fade_from, 1.0, r));
	float edge = 1.0 - smoothstep(growth - 0.08, growth, s);
	float a = rim * edge * smoothstep(0.0, 0.05, growth);
	if (a < 0.004) {
		discard;
	}
	ALBEDO = c * intensity;
	ALPHA = a;
}
