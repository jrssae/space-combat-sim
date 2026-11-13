shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_always, cull_disabled, shadows_disabled;
// A jump vortex's funnel (M6-T19, D69): a broad, gently curving, translucent well of the base colour, darker toward its rim and
// its soft throat, combed with fine hair-like streaks along one soft spiral, over soft-edged darker patches and paler
// translucent ones that lie along the same spiral. Everything turns round the axis and drifts along the spiral (out from the
// throat for an arrival, in toward it for a departure). The body reaches the rim of its mouth, at a gate's arms, and ends there
// in a short feathered edge. The funnel unfolds from its base forward to the rim as it opens. A dark circle lies on the base
// itself; from in front it shows down the funnel, from an oblique view the nearer walls hide it (the mesh draws its base first,
// so the walls lie over it). From the side or behind, the base glows white instead.
//
// The mesh is a unit grid: UV.x round the funnel, UV.y from the rim (0) to the centre (1); the node's scale gives the mouth's
// semi-axes (x, y: an ellipse at a gate) and the depth (z, behind the mouth). `swirl_time` is sim time, so a pause freezes it.

uniform vec3 colour = vec3(0.06, 0.38, 0.85);
uniform vec3 highlight = vec3(0.36, 0.75, 1.0);
// 0..1: how far the funnel has unfolded from its centre toward the rim.
uniform float growth = 1.0;
// The opener's overall brightness (an arrival is darker than a departure, as the references are).
uniform float brightness = 1.0;
uniform float swirl_time = 0.0;
// +1 when the pattern travels out toward the rim (an arrival), -1 when it travels in (a departure).
uniform float flow = 1.0;
// The way it turns, in the mesh's own angle: -1 is counter-clockwise seen from in front (an arrival), +1 clockwise (`VortexSwirl`).
uniform float turn = -1.0;
// How tightly the spiral winds: turns round the funnel per e-fold of radius.
uniform float twist = 0.17;
// Turns a second round the axis, and e-folds of radius a second along the spiral.
uniform float spin = 0.02;
uniform float travel = 0.1;
// How much of what is behind shows through the walls.
uniform float body_alpha = 0.72;
// How wide the well is: its walls fall away over about this share of the radius, round a broad, rounded base.
uniform float well = 0.55;
// Where the body's feathered edge sits and how wide it is, shares of the mouth's radius: it is gone by the rim.
uniform float body_edge = 0.965;
uniform float edge_soft = 0.035;
uniform vec3 base_glow = vec3(1.2, 1.2, 1.3);
// The dark circle on the base, a share of the mouth's radius.
uniform float throat_radius = 0.24;

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

// Value noise that repeats every `period` cells in x, so a pattern laid round the funnel closes on itself with no seam.
float pnoise(vec2 p, float period) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float x0 = mod(i.x, period);
	float x1 = mod(i.x + 1.0, period);
	return mix(mix(hash2(vec2(x0, i.y)), hash2(vec2(x1, i.y)), f.x),
			mix(hash2(vec2(x0, i.y + 1.0)), hash2(vec2(x1, i.y + 1.0)), f.x), f.y);
}

// Hair-like streaks along the spiral: `around` strands round the funnel, each `per_fold` cells long per e-fold of radius.
// `px_cells` is how many strands one pixel covers: strands finer than a pixel melt into their mean instead of shimmering.
float hairs(float w, float along, float around, float per_fold, float px_cells) {
	float n = pnoise(vec2(w * around, along * per_fold + around), around);
	return mix(n, 0.5, smoothstep(0.35, 1.1, px_cells * around));
}

// Soft-edged, roughly rectangular patches lying along the spiral: `around` columns round the funnel, `per_fold` rows per
// e-fold of radius, each column slid by its own amount so they do not line up in rings. Returns the cover (0..1) and the
// patch's own random tone.
vec2 patches(float w, float along, float around, float per_fold, float seed, float fill, float blur) {
	vec2 q = vec2(w * around, along * per_fold);
	float column = mod(floor(q.x), around);
	q.y += hash2(vec2(column, seed)) * 9.0;
	vec2 id = vec2(column, floor(q.y)) + seed;
	float h1 = hash2(id);
	float h2 = hash2(id + 17.7);
	float h3 = hash2(id + 41.3);
	if (h1 > fill) {
		return vec2(0.0, h3);
	}
	vec2 f = fract(q) - 0.5 - (vec2(h2, h3) - 0.5) * vec2(0.2, 0.2);
	vec2 half_size = vec2(0.2 + 0.12 * h2, 0.26 + 0.14 * h3);
	vec2 d = abs(f) - half_size;
	float sd = length(max(d, 0.0)) + min(max(d.x, d.y), 0.0);
	float soft = 0.2 + blur;
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
	// The look's bands and smudge are laid out a little inside the rim, so the body darkens toward its edge.
	float look_r = r / 1.14;
	float u = UV.x;
	float t = swirl_time;
	// How many funnel radii one pixel covers, and how many turns round the funnel that is here.
	float px = length(fwidth(v_flat));
	float px_turns = px / (TAU * rp);
	// The spiral everything lies along: `w` counts turns across it, `along` e-folds of radius down it. One spiral serves both
	// directions: going out along it turns one way, going in the other.
	float lr = log(rp);
	float w = u - turn * flow * twist * lr - turn * spin * t;
	float along = lr - flow * travel * t;
	// Base tone: the opener's colour leaning a little to its highlight, its weakest channel cut so it stays deep (the
	// tonemapper otherwise pulls blue toward violet); dark at the throat and the rim, brightest over a band in the middle,
	// in broad uneven clouds.
	vec3 base = mix(colour, highlight, 0.15);
	base -= vec3(min(base.r, min(base.g, base.b))) * 0.92;
	float band = smoothstep(0.12, 0.5, look_r) * (1.0 - 0.45 * smoothstep(0.55, 0.85, look_r));
	float cloud = pnoise(vec2(w * 6.0, along * 2.2), 6.0) * 0.6 + pnoise(vec2(w * 14.0, along * 4.5 + 5.0), 14.0) * 0.4;
	float level = (0.1 + 0.9 * band) * (0.45 + 0.9 * cloud);
	vec3 c = base * level;
	// The darker patches, soft-edged and roughly rectangular, lying along the spiral.
	float around_d = 30.0;
	vec2 dark = patches(w, along, around_d, 5.0, 0.0, 0.55, 0.5 * px_turns * around_d);
	c *= 1.0 - (0.35 + 0.25 * dark.y) * dark.x;
	// Paler, translucent patches of the base colour, longer, a little slower.
	float around_l = 22.0;
	vec2 light = patches(w + 0.37, along + flow * travel * t * 0.3, around_l, 3.0, 3.0, 0.5, 0.5 * px_turns * around_l);
	vec3 pale = mix(base, highlight, 0.35) * (0.25 + level);
	c = mix(c, pale, (0.35 + 0.25 * light.y) * light.x);
	// Fine hair-like streaks combed along the spiral, three widths; the finest carry the most light.
	float broad = hairs(w, along, 120.0, 11.0, px_turns);
	float fine = hairs(w, along + 3.0, 300.0, 18.0, px_turns);
	float finest = hairs(w, along + 11.0, 600.0, 28.0, px_turns);
	float strands = smoothstep(0.52, 0.86, 0.2 * broad + 0.45 * fine + 0.35 * finest + 0.2 * (cloud - 0.5));
	float combed = 0.7 + 0.6 * (0.4 * broad + 0.6 * fine);
	c = c * combed + mix(base, highlight, 0.42) * strands * (0.12 + 0.95 * band) * (0.4 + cloud);
	// The base: a soft black smudge down the funnel from in front, a white glow on the base alone from the side or behind.
	float deep = 1.0 - smoothstep(0.05, 0.7, look_r);
	deep *= deep * (3.0 - 2.0 * deep);
	// The dark circle on the base itself, soft-edged.
	float throat = 1.0 - smoothstep(0.55 * throat_radius, throat_radius, r);
	deep = max(deep * 0.55, throat);
	float glow = 1.0 - smoothstep(0.0, 0.17, look_r);
	c = mix(c * (1.0 - deep * (1.0 - v_glow)), base_glow, glow * v_glow);
	// The body ends at the rim in a short edge feathered along the streaks; the unfolding edge is soft.
	float feather = (0.6 * broad + 0.4 * fine - 0.5) * edge_soft;
	float rim = 1.0 - smoothstep(body_edge - edge_soft, body_edge + 0.5 * edge_soft, r + feather);
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
