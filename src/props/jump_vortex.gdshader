shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_always, cull_disabled, shadows_disabled;
// A jump vortex's funnel (M6-T19, D69): a broad, gently curving, translucent well of the base colour, darker toward its rim and
// its soft throat, covered in short pale feathers along one soft spiral (M7-T23, the maintainer's GIF), over soft-edged darker
// patches and fine hair-like streaks that lie along the same spiral. Everything turns round the axis and drifts along the spiral (out from the
// throat for an arrival, in toward it for a departure). The body reaches the rim of its mouth, at a gate's arms, and ends there
// in a wide soft fade broken up along the streaks. The funnel unfolds from its base forward to the rim as it opens. A dark circle lies on the base
// itself; from in front it shows down the funnel, from an oblique view the nearer walls hide it (the mesh draws its base first,
// so the walls lie over it). From the side or behind, the base glows white instead.
//
// The mesh is a unit grid: UV.x round the funnel, UV.y from the rim (0) to the centre (1); the node's scale gives the mouth's
// semi-axes (x, y: an ellipse at a gate) and the depth (z, behind the mouth).
//
// Detail by distance (M6-T20): one material serves every point of a direction; each point's own values are instance uniforms.
// Its layers (hairs finest first, patches and wisps, the cloud octaves) carry weights from `VortexLod`; a fading layer blends
// toward its mean and a layer at weight 0 is not computed, so a far point draws a soft disc of the base colour cheaply.

uniform vec3 colour = vec3(0.06, 0.38, 0.85);
uniform vec3 highlight = vec3(0.36, 0.75, 1.0);
// Per point: x how far the funnel has unfolded from its centre toward the rim (0..1); y the base's view, 0 looking down the
// funnel from in front, 1 from the side or behind; z sim time for the swirl (a pause freezes it); w the dark eye's radius on the
// base, a share of the mouth's radius (it opens with the funnel).
instance uniform vec4 vortex_state = vec4(1.0, 0.0, 0.0, 0.24);
// Per point, the layers' weights (`VortexLod`): finest, fine and broad hairs, patches and wisps; then the fine and coarse cloud.
instance uniform vec4 vortex_lod_a = vec4(1.0);
instance uniform vec4 vortex_lod_b = vec4(1.0);
// The opener's overall brightness (an arrival is darker than a departure, as the references are).
uniform float brightness = 1.0;
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
// The rim's fade, shares of the mouth's radius: from `rim_from` it thins out toward `rim_to` (past the rim, so a faint edge
// still reaches the arms), its edge broken up along the streaks by `rim_feather`. Matched to the still's edge (round 6).
uniform float rim_from = 0.69;
uniform float rim_to = 1.08;
uniform float rim_feather = 0.3;
uniform vec3 base_glow = vec3(1.2, 1.2, 1.3);
// The settled dark eye's radius (a share of the mouth's), and how far the soft darkening round it reaches when it is that size.
uniform float throat_radius = 0.24;
uniform float eye_reach = 0.5;
// How dark the darker patches are, how bright the feathers and how strong the hair streaks.
uniform float dark_depth = 0.55;
uniform float feather_gain = 1.0;
uniform float hair_gain = 0.45;
// The patch layers' mean effect, for blending them out: the dark patches' mean darkening and the feathers' mean cover.
const float DARK_MEAN = 0.89;
const float FEATHER_MEAN = 0.12;

varying float v_s;
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
float hairs(float w, float along, float around, float per_fold, float px_cells, float weight) {
	if (weight <= 0.0) {
		return 0.5;
	}
	float n = pnoise(vec2(w * around, along * per_fold + around), around);
	return mix(0.5, mix(n, 0.5, smoothstep(0.35, 1.1, px_cells * around)), weight);
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

// Feathers: short pale tongues lying along the spiral, widest near the head and drawn out to a point down the tail, `around`
// columns round the funnel and `per_fold` rows per e-fold of radius, each column slid so they do not line up in rings.
float feathers(float w, float along, float around, float per_fold, float seed, float blur) {
	vec2 q = vec2(w * around, along * per_fold);
	float column = mod(floor(q.x), around);
	q.y += hash2(vec2(column, seed)) * 7.0;
	vec2 id = vec2(column, floor(q.y)) + seed;
	float h1 = hash2(id);
	float h2 = hash2(id + 23.9);
	if (h2 > 0.8) {
		return 0.0;
	}
	vec2 f = fract(q);
	float body = smoothstep(0.0, 0.3, f.y) * (1.0 - smoothstep(0.62, 1.0, f.y));
	float width = (0.1 + 0.14 * h2) * (0.35 + f.y) + blur;
	float x = (f.x - 0.5 - (h1 - 0.5) * 0.45) / width;
	return exp(-x * x) * body * (0.35 + 0.65 * h1);
}

void vertex() {
	float s = 1.0 - UV.y;
	// Unfolding: the part from the base out to `growth` is in its final place, so the funnel builds forward from the base to the
	// mouth; the rest waits folded at its edge.
	float se = min(s, vortex_state.x);
	float a = UV.x * TAU;
	VERTEX = vec3(cos(a) * se, sin(a) * se, profile_z(se));
	v_s = s;
	v_flat = vec2(cos(a), sin(a)) * s;
}

void fragment() {
	float r = v_s;
	float rp = max(r, 0.04);
	// The look's bands and smudge are laid out a little inside the rim, so the body darkens toward its edge.
	float u = UV.x;
	float growth = vortex_state.x;
	// While it unfolds the look is laid out over what has unfolded, so a small disc or a first ring is as blue as the open funnel.
	float look_r = r / (1.14 * max(growth, 0.05));
	float v_glow = vortex_state.y;
	float t = vortex_state.z;
	float w_patches = vortex_lod_a.w;
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
	float coarse = vortex_lod_b.y > 0.0 ? mix(0.5, pnoise(vec2(w * 6.0, along * 2.2), 6.0), vortex_lod_b.y) : 0.5;
	float fine_cloud = vortex_lod_b.x > 0.0 ? mix(0.5, pnoise(vec2(w * 14.0, along * 4.5 + 5.0), 14.0), vortex_lod_b.x) : 0.5;
	float cloud = coarse * 0.6 + fine_cloud * 0.4;
	float level = (0.1 + 0.9 * band) * (0.45 + 0.9 * cloud);
	vec3 c = base * level;
	// The darker patches, soft-edged and roughly rectangular, lying along the spiral.
	float darken = DARK_MEAN;
	float pale_cover = FEATHER_MEAN;
	if (w_patches > 0.0) {
		float around_d = 30.0;
		vec2 dark = patches(w, along, around_d, 5.0, 0.0, 0.55, 0.5 * px_turns * around_d);
		darken = mix(DARK_MEAN, 1.0 - dark_depth * (0.6 + 0.4 * dark.y) * dark.x, w_patches);
		// The feathers, two sizes, the smaller a little slower so they slide past each other.
		// A slow sideways wander keeps the columns from reading as spokes.
		float wander = (cloud - 0.5) * 0.035;
		float big = feathers(w + 0.37 + wander, along, 38.0, 5.0, 3.0, px_turns * 38.0);
		float small = feathers(w + 0.11 - wander, along + flow * travel * t * 0.3, 62.0, 8.5, 7.0, px_turns * 62.0);
		pale_cover = mix(FEATHER_MEAN, max(big, 0.7 * small), w_patches);
	}
	c *= darken;
	vec3 pale = mix(base, highlight, 0.5) * (0.45 + level) * feather_gain;
	c = mix(c, pale, pale_cover * (0.25 + 0.75 * band));
	// Fine hair-like streaks combed along the spiral, three widths; the finest carry the most light.
	float broad = hairs(w, along, 120.0, 11.0, px_turns, vortex_lod_a.z);
	float fine = hairs(w, along + 3.0, 300.0, 18.0, px_turns, vortex_lod_a.y);
	float finest = hairs(w, along + 11.0, 600.0, 28.0, px_turns, vortex_lod_a.x);
	float strands = smoothstep(0.52, 0.86, 0.2 * broad + 0.45 * fine + 0.35 * finest + 0.2 * (cloud - 0.5));
	float combed = 0.7 + 0.6 * (0.4 * broad + 0.6 * fine);
	c = c * combed + mix(base, highlight, 0.42) * strands * (0.12 + 0.95 * band) * (0.4 + cloud) * hair_gain;
	// The base: a soft black smudge down the funnel from in front, a white glow on the base alone from the side or behind.
	float eye = max(vortex_state.w, 1e-3);
	float deep = 1.0 - smoothstep(0.05, eye_reach * clamp(eye / (max(growth, 0.05) * throat_radius), 0.5, 1.5), look_r);
	deep *= deep * (3.0 - 2.0 * deep);
	// The dark circle on the base itself, soft-edged.
	float throat = 1.0 - smoothstep(0.55 * eye, eye, r);
	deep = max(deep * 0.55, throat);
	float glow = 1.0 - smoothstep(0.0, 0.17, look_r);
	c = mix(c * (1.0 - deep * (1.0 - v_glow)), base_glow, glow * v_glow);
	// The body thins out toward the rim in a wide soft fade whose edge follows the streaks, as wisps; the unfolding edge is soft.
	// Wisps: coarse strands drawn out along the spiral, wide enough to stay visible from afar where the hairs melt into their mean.
	float wisp = 0.5;
	if (w_patches > 0.0) {
		float strand = smoothstep(0.25, 0.75, pnoise(vec2(w * 48.0, along * 7.0 + 2.0), 48.0)) * 0.75 + (0.6 * broad + 0.4 * fine) * 0.25;
		wisp = mix(0.5, strand, w_patches);
	}
	float feather = (wisp - 0.5) * rim_feather * smoothstep(rim_from, 1.0, r);
	float rim = 1.0 - smoothstep(rim_from, rim_to, r + feather);
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
