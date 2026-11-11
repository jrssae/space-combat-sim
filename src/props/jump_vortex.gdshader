shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_always, cull_disabled, shadows_disabled;
// A jump vortex's funnel (M6-T19, D69): a broad, gently curving, translucent well of the base colour, darker toward its rim and
// its soft throat, with many small soft-edged darker patches and paler translucent ones drawn out along a spiral and drifting
// along it (out from the throat for an arrival, in toward it for a departure); the rim fades out in wisps. The funnel unfolds
// from its base forward to the rim of its mouth as it opens. Its base looks black from in front, down the funnel, and glows white
// from the side or behind.
//
// The mesh is a unit grid: UV.x round the funnel, UV.y from the rim (0) to the centre (1); the node's scale gives the mouth's
// radius (x, y) and the depth (z, behind the mouth). `swirl_time` is sim time, so a pause freezes the motion.

uniform vec3 colour = vec3(0.045, 0.23, 0.9);
uniform vec3 highlight = vec3(0.38, 0.65, 1.0);
// 0..1: how far the funnel has unfolded from its centre toward the rim.
uniform float growth = 1.0;
// The opener's overall brightness (an arrival is darker than a departure, as the references are).
uniform float brightness = 1.0;
uniform float swirl_time = 0.0;
// +1 for an arrival (the patches spiral out toward the rim), -1 for a departure (they spiral in); both turn the same way.
uniform float flow = 1.0;
// How much of what is behind shows through the walls.
uniform float body_alpha = 0.72;
// How wide the well is: its walls fall away over about this share of the radius, round a broad, rounded base.
uniform float well = 0.55;
// The rim fades from this share of the radius to nothing at the rim.
uniform float rim_fade_from = 0.42;
uniform vec3 base_glow = vec3(1.2, 1.2, 1.3);

varying float v_s;
varying float v_glow;
varying vec2 v_flat;

// Depth behind the mouth (0 at the rim, 1 at the centre) at radius `r`: a rounded base and gently curving walls.
float profile_z(float r) {
	float e = exp(-1.0 / (well * well));
	return (exp(-r * r / (well * well)) - e) / (1.0 - e);
}

float hash2(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash2(i), hash2(i + vec2(1.0, 0.0)), f.x), mix(hash2(i + vec2(0.0, 1.0)), hash2(i + vec2(1.0, 1.0)), f.x), f.y);
}

// Value noise along the funnel at `n` cells round it, the row sheared `m` per turn: blended across the seam at u = 1 so the
// wrap round the funnel shows no line.
float ring_noise(float u, float y0, float n, float m, float drift) {
	float here = vnoise(vec2(u * n + drift, y0 - m * u));
	float wrapped = vnoise(vec2((u - 1.0) * n + drift, y0 - m * (u - 1.0)));
	return mix(here, wrapped, smoothstep(0.85, 1.0, u));
}

// A field of soft-edged, roughly rectangular patches on a spiral grid: `around` cells round the funnel, rows a cell tall in
// log radius, sheared `turns` cells per turn so they lie along spirals, each row slid by its own amount so they do not line up.
// `drift` moves them along the spiral; `blur` widens their edges (more when a cell covers few pixels). Returns the patch's
// cover (0..1) and its random tone in y.
vec2 patches(float u, float r, float around, float turns, float drift, float seed, float fill, float blur) {
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
		return vec2(0.0, h3);
	}
	vec2 f = fract(q) - 0.5 - (vec2(h2, h3) - 0.5) * vec2(0.2, 0.3);
	// Drawn out along the spiral, thin across it.
	vec2 half_size = vec2(0.32 + 0.14 * h2, 0.07 + 0.07 * h3);
	vec2 d = abs(f) - half_size;
	float sd = length(max(d, 0.0)) + min(max(d.x, d.y), 0.0);
	float soft = 0.14 + blur;
	return vec2(1.0 - smoothstep(-soft, soft, sd), h3);
}

void vertex() {
	float s = 1.0 - UV.y;
	// Unfolding: the part from the base out to `growth` is in its final place, so the funnel builds forward from the base to the
	// mouth; the rest waits folded at its edge.
	float se = min(s, growth);
	float a = UV.x * TAU;
	VERTEX = vec3(cos(a) * se, sin(a) * se, profile_z(se));
	v_s = s;
	v_flat = vec2(cos(a), sin(a)) * s;
	// The view against the axis (+Z, into the funnel): -1 straight down it from in front, 0 from the side, +1 from behind.
	vec3 mouth = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	vec3 axis = normalize(MODEL_MATRIX[2].xyz);
	vec3 cam = INV_VIEW_MATRIX[3].xyz;
	float t = dot(normalize(cam - mouth + axis * 1e-3), axis);
	v_glow = smoothstep(-0.45, -0.05, t);
}

void fragment() {
	float r = v_s;
	float rp = max(r, 0.04);
	float u = UV.x;
	float t = swirl_time;
	// How many funnel radii one pixel covers: patches smaller than a few pixels melt into their mean tone instead of aliasing.
	float px = length(fwidth(v_flat));
	// Base tone: the opener's colour leaning a little to its highlight, its weakest channel cut so it stays deep (the
	// tonemapper otherwise pulls blue toward violet); dark navy at the throat and the rim, brightest over a band in the middle.
	vec3 base = mix(colour, highlight, 0.15);
	base -= vec3(min(base.r, min(base.g, base.b))) * 0.85;
	float band = smoothstep(0.1, 0.45, r) * (1.0 - 0.7 * smoothstep(0.55, 0.95, r));
	float wash = ring_noise(u, log(rp) * 4.0, 9.0, 2.0 * flow, -t * 0.25);
	float level = (0.08 + 0.92 * band * band) * (0.25 + 1.3 * wash * wash);
	// Fine feathery streaks along the spiral, low in contrast.
	float sp = log(rp) * 90.0 / TAU;
	float streak = ring_noise(u, sp * 3.0, 260.0, 105.0 * flow, -t * 1.4) * 0.6
			+ ring_noise(u, sp * 1.5, 120.0, 52.5 * flow, -t) * 0.4;
	float streak_k = 1.0 - smoothstep(0.004, 0.02, px / rp);
	vec3 c = base * level * (1.0 + 0.35 * (streak - 0.5) * streak_k);
	// Paler, translucent patches of the base colour, drifting slowly along the spiral.
	float around_l = 44.0;
	float cell_l = TAU * rp / around_l;
	float blur_l = 0.6 * px / cell_l;
	vec2 light = patches(u, rp, around_l, 17.0 * flow, -t * 0.8, 3.0, 0.8, blur_l);
	float keep_l = 1.0 - smoothstep(0.4, 1.2, px / cell_l);
	vec3 pale = mix(base, highlight, 0.45) * level * 1.6;
	c = mix(c, pale, mix(0.8 * 0.3, light.x, keep_l) * (0.4 + 0.35 * light.y));
	// The small darker patches, faster, drifting along the spiral.
	float around_d = 120.0;
	float cell_d = TAU * rp / around_d;
	float blur_d = 0.6 * px / cell_d;
	vec2 dark = patches(u, rp, around_d, 47.0 * flow, -t * 1.7, 0.0, 0.6, blur_d);
	float keep_d = 1.0 - smoothstep(0.4, 1.2, px / cell_d);
	c = mix(c, c * 0.45, mix(0.6 * 0.3, dark.x, keep_d) * (0.45 + 0.35 * dark.y));
	// The base: a soft black smudge down the funnel from in front, a white glow on the base alone from the side or behind.
	float deep = 1.0 - smoothstep(0.02, 0.5, r);
	deep *= deep * (3.0 - 2.0 * deep);
	float glow = 1.0 - smoothstep(0.0, 0.17, r);
	c = mix(c * (1.0 - deep * (1.0 - v_glow)), base_glow, glow * v_glow);
	// The rim fades out raggedly in wisps; the unfolding edge is soft.
	float wisps = ring_noise(u, t * 0.5, 70.0, 0.0, 0.0) * 0.6 + ring_noise(u, 3.0 + t * 0.7, 170.0, 0.0, 0.0) * 0.4;
	float rim = 1.0 - smoothstep(rim_fade_from, 1.0, r + (wisps - 0.5) * 0.2 * smoothstep(rim_fade_from, 1.0, r));
	float edge = 1.0 - smoothstep(growth - 0.08, growth, r);
	// Translucent walls; the base is opaque, black from in front and its glow from behind.
	float solid = max(glow * v_glow, deep * (1.0 - v_glow));
	float a = rim * edge * smoothstep(0.0, 0.05, growth) * mix(body_alpha, 1.0, solid);
	if (a < 0.004) {
		discard;
	}
	ALBEDO = c * brightness;
	ALPHA = a;
}
