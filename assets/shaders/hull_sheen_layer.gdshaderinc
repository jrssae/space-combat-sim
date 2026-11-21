// The sheen layer (M10-T06, D12.2): what makes a hull's skin change with the view, laid over its four maps as the liveries
// are a layer. Nothing is baked: a style names the numbers (`tools/procgen/core/sheen.py`, the manifest's `sheen` entry) and
// `HullSheenMaterial` sets them as these uniforms. Its effects, each off at zero:
//   iridescence: a colour by direction (nine spherical-harmonic coefficients) mixed into the paint towards the rim, which may
//     shift in slow waves along the hull;
//   pattern: mottling, spots or cells in the hull's own space. Mottling and spots may swell and fade as a squid's skin does;
//     cells may drift, their seams may stand up as ridges, and each cell between the ridges may be a pool of glossy liquid,
//     its surface drawn up at its edges and dished in its middle (the Shadows');
//   glow: a faint light of the hull's own (the Vorlons' bioluminescence);
//   variant: a second colouring of the same hull (the red-based Vorlons), chosen per ship by the including shader.
// Everything that moves reads TIME: a visual only, gameplay never sees it.
// A shader includes this file, fills a `SheenSurface` with its paint and calls `sheen_layer`. The uniform `sheen` of the hull
// shaders is `settings.hull_sheen`'s clear coat, an older and different thing: this layer's uniforms are the ones below.

uniform vec3 iri_sh[9];
uniform float iri_strength = 0.0;
uniform float iri_base = 0.0;
uniform float iri_power = 3.0;
uniform float iri_view = 0.5;
uniform float iri_metal = 0.0;
uniform float iri_wave = 0.0;
uniform float iri_wave_s = 0.0;
uniform float pattern_scale_m = 1.0;
uniform float pattern_cells = 0.0;
uniform float pattern_edge = 0.5;
uniform float pattern_cover = 0.5;
uniform float pattern_dark = 0.0;
uniform vec3 pattern_tint = vec3(0.0);
uniform float pattern_iri = 0.0;
uniform float pattern_rough = 0.0;
uniform float pattern_speed_mps = 0.0;
uniform float pattern_spots = 0.0;
uniform float pattern_pulse = 0.0;
uniform float pattern_pulse_s = 0.0;
uniform float pattern_relief = 0.0;
uniform float liquid = 0.0;
uniform float liquid_flow_mps = 0.0;
uniform float liquid_dish = 0.0;
uniform vec3 liquid_tint = vec3(0.0);
uniform vec3 glow_colour = vec3(0.0);
uniform float glow_energy = 0.0;
uniform float glow_veins = 0.0;
uniform float glow_rim = 0.0;
uniform float glow_pulse_s = 0.0;
uniform float glow_pulse = 0.0;
// The share of `settings.hull_sheen`'s clear coat the skin takes (the including shader applies it).
uniform float coat = 1.0;
// The variant's colouring: what the warm paint's brightness is multiplied by, its iridescence and its glow; `variant_all` makes
// every hull of the material the variant (look sheets).
uniform vec3 variant_tint = vec3(1.0);
uniform vec3 variant_sh[9];
uniform vec3 variant_glow = vec3(0.0);
uniform float variant_all = 0.0;

// What the layer works on: the surface as the maps give it, changed in place. `tilt` is how the layer leans the normal, in the
// hull's own frame; `coat` and `coat_roughness` a clear coat of the layer's own (the liquid's).
struct SheenSurface {
	vec3 albedo;
	float metallic;
	float roughness;
	float specular;
	vec3 emission;
	vec3 tilt;
	float coat;
	float coat_roughness;
};

vec3 sheen_hash3(vec3 c) {
	vec3 q = vec3(dot(c, vec3(127.1, 311.7, 74.7)), dot(c, vec3(269.5, 183.3, 246.1)), dot(c, vec3(113.5, 271.9, 124.6)));
	return fract(sin(q) * 43758.5453);
}

// Smooth noise, 0 to 1, one lattice cell a unit.
float sheen_noise(vec3 p) {
	vec3 c = floor(p);
	vec3 f = p - c;
	f = f * f * (3.0 - 2.0 * f);
	float n000 = sheen_hash3(c).x;
	float n100 = sheen_hash3(c + vec3(1.0, 0.0, 0.0)).x;
	float n010 = sheen_hash3(c + vec3(0.0, 1.0, 0.0)).x;
	float n110 = sheen_hash3(c + vec3(1.0, 1.0, 0.0)).x;
	float n001 = sheen_hash3(c + vec3(0.0, 0.0, 1.0)).x;
	float n101 = sheen_hash3(c + vec3(1.0, 0.0, 1.0)).x;
	float n011 = sheen_hash3(c + vec3(0.0, 1.0, 1.0)).x;
	float n111 = sheen_hash3(c + vec3(1.0, 1.0, 1.0)).x;
	return mix(mix(mix(n000, n100, f.x), mix(n010, n110, f.x), f.y), mix(mix(n001, n101, f.x), mix(n011, n111, f.x), f.y), f.z);
}

// The cell `p` lies in, of cells scattered one a unit: x the distance to its own cell's middle, y to the next nearest's;
// `own` three numbers of its own cell's, `to_middle` the way to its middle.
vec2 sheen_cells(vec3 p, out vec3 own, out vec3 to_middle) {
	vec3 c = floor(p);
	float nearest = 8.0;
	float second = 8.0;
	own = vec3(0.0);
	to_middle = vec3(0.0);
	for (int k = -1; k <= 1; k++) {
		for (int j = -1; j <= 1; j++) {
			for (int i = -1; i <= 1; i++) {
				vec3 cell = c + vec3(float(i), float(j), float(k));
				vec3 h = sheen_hash3(cell);
				vec3 offset = cell + h - p;
				float d = length(offset);
				if (d < nearest) {
					second = nearest;
					nearest = d;
					own = h;
					to_middle = offset;
				} else if (d < second) {
					second = d;
				}
			}
		}
	}
	return vec2(nearest, second);
}

// Lays the layer over a surface. `pos`, `normal` and `view` (towards the eye) are in the hull's own frame, so the pattern and
// the colours ride with the hull; `footprint_m` is how much of the hull one pixel covers, so the pattern fades to its mean
// instead of sparkling when a blotch is smaller than a pixel; `variant` is 1 on a ship of the second colouring.
void sheen_layer(vec3 pos, vec3 normal, vec3 view, float footprint_m, float time, float ship_variant, inout SheenSurface s) {
	float variant = max(ship_variant, variant_all);
	if (variant > 0.0) {
		// Only the warm paint turns: a Vorlon's blue petals stay blue on a red hull.
		float warm = smoothstep(0.0, 0.1, max(s.albedo.r, s.albedo.g) - s.albedo.b);
		s.albedo = mix(s.albedo, variant_tint * dot(s.albedo, vec3(0.2126, 0.7152, 0.0722)), variant * warm);
	}
	float ink = 0.0;
	float vein = 0.0;
	float tone = 0.5;
	float pool = 0.0;
	vec3 p = pos / pattern_scale_m;
	if (pattern_dark + pattern_iri + pattern_rough + glow_veins + liquid > 0.0) {
		float drift = time * pattern_speed_mps / pattern_scale_m;
		float edge = mix(0.3, 0.03, pattern_edge);
		// Mottling: two noises that drift apart, so the blotches change shape as they move.
		float n = 0.6 * sheen_noise(p + drift * vec3(0.15, 0.1, 1.0)) + 0.4 * sheen_noise(p * 2.1 - drift * vec3(0.6, 0.35, -0.2));
		float level = mix(0.72, 0.28, pattern_cover);
		if (pattern_pulse > 0.0 && pattern_pulse_s > 0.0) {
			// Each patch of skin swells and shrinks its blotches on its own slow beat, as a cuttlefish's chromatophores do.
			level -= 0.1 * pattern_pulse * sin(6.2831853 * (time / pattern_pulse_s + 2.0 * sheen_noise(p * 0.23 + 7.3)));
		}
		float blot = smoothstep(level - edge, level + edge, n);
		float blot_vein = 1.0 - smoothstep(0.0, 2.0 * edge + 0.04, abs(n - level));
		if (pattern_spots > 0.0) {
			// Spots: soft dots between the blotches, each opening and closing in its own time.
			vec3 own, to_middle;
			vec2 d = sheen_cells(p * 2.6, own, to_middle);
			float open = 0.5 + 0.5 * sin(6.2831853 * (own.z + time * (0.6 + 0.8 * own.y) / max(pattern_pulse_s, 1.0)));
			float radius = 0.42 * mix(1.0, open, pattern_pulse) * step(0.35, own.x);
			blot = max(blot, pattern_spots * (1.0 - smoothstep(0.45 * radius, radius + 1e-4, d.x)));
		}
		float seam = 0.0;
		if (pattern_cells > 0.0) {
			// Cells: each slides along the hull and breathes a little; the seams between them are the pattern's ink.
			vec3 own, to_middle;
			vec2 d = sheen_cells(p * 1.3 + drift * vec3(0.0, 0.0, 1.0) + 0.25 * sin(drift * 0.7 + p.yzx * 1.7), own, to_middle);
			float width = mix(0.02, 0.3, pattern_cover) + edge * 0.5;
			float from_seam = d.y - d.x;
			seam = 1.0 - smoothstep(0.0, width, from_seam);
			tone = own.y;
			// The seam is a ridge: its flank falls away towards the cell's middle. Beyond it the cell's surface goes on falling,
			// more and more gently, to a flat middle: a pool drawn up where it meets the ridge.
			vec3 inward = to_middle - normal * dot(to_middle, normal);
			float flank = sin(3.14159265 * clamp(from_seam / width, 0.0, 1.0));
			float dish = (1.0 - smoothstep(width, width + 0.45, from_seam)) * smoothstep(0.5 * width, width, from_seam);
			s.tilt += pattern_cells * (pattern_relief * flank + liquid_dish * 0.45 * dish) * inward / max(length(inward), 1e-4);
		}
		ink = mix(blot, seam, pattern_cells);
		vein = mix(blot_vein, seam, pattern_cells);
		float sharp = smoothstep(1.0, 0.25, footprint_m / pattern_scale_m);
		float mean_ink = mix(pattern_cover, 0.3, pattern_cells);
		ink = mix(mean_ink, ink, sharp);
		vein = mix(0.25, vein, sharp);
		tone = mix(0.5, tone, sharp * pattern_cells);
		s.tilt *= sharp;
		pool = pattern_cells * (1.0 - ink);
	}
	s.albedo = mix(s.albedo, pattern_tint, pattern_dark * ink);
	s.roughness = clamp(s.roughness + pattern_rough * (ink + (tone - 0.5) * 0.6), 0.04, 1.0);
	// A seam between cells is dull as well as dark: with its shine left on, a web of ridges glints over a black hull.
	s.specular *= 1.0 - pattern_dark * ink * pattern_cells;

	float facing = clamp(dot(normal, view), 0.0, 1.0);
	float rim = pow(1.0 - facing, iri_power);
	if (iri_strength + iri_base > 0.0) {
		vec3 towards = normalize(mix(normal, reflect(-view, normal), iri_view) + vec3(0.0, 1e-4, 0.0));
		if (iri_wave > 0.0 && iri_wave_s > 0.0) {
			// The colours shift in slow waves that wander over the hull.
			float a = 6.2831853 * (time / iri_wave_s + 1.5 * sheen_noise(p * 0.17 + 3.1));
			towards = normalize(towards + 0.7 * iri_wave * vec3(sin(a), sin(a + 2.094), sin(a + 4.189)));
		}
		float amount = mix(iri_base, iri_strength, rim) * (1.0 - pattern_iri * ink) * (1.0 + (tone - 0.5) * 0.5 * pattern_cells);
		amount = clamp(amount, 0.0, 1.0);
		// The colour towards that direction: nine spherical harmonics (`sheen.sh_basis`'s order) times the coefficients.
		vec3 d = towards;
		float basis[9] = float[9](0.282095, 0.488603 * d.y, 0.488603 * d.z, 0.488603 * d.x, 1.092548 * d.x * d.y, 1.092548 * d.y * d.z,
				0.315392 * (3.0 * d.z * d.z - 1.0), 1.092548 * d.x * d.z, 0.546274 * (d.x * d.x - d.y * d.y));
		vec3 first = vec3(0.0);
		vec3 second = vec3(0.0);
		for (int i = 0; i < 9; i++) {
			first += iri_sh[i] * basis[i];
			second += variant_sh[i] * basis[i];
		}
		vec3 colour = max(mix(first, second, variant), vec3(0.0));
		s.albedo = mix(s.albedo, colour, amount);
		s.metallic = mix(s.metallic, 1.0, amount * iri_metal);
	}
	if (liquid > 0.0) {
		// Each cell is a pool of liquid: smooth, wet, and slowly rippling along the hull.
		float wet = liquid * pool;
		float run = time * liquid_flow_mps / pattern_scale_m;
		vec3 q = p * 6.0;
		vec3 ripple = vec3(sin(q.y * 1.7 + q.z * 2.3 - run * 9.0), sin(q.z * 1.9 + q.x * 2.1 - run * 7.0), sin(q.x * 2.3 + q.y * 1.3 + run * 8.0));
		ripple += 0.6 * sin(q.zxy * 3.1 + run * vec3(13.0, -11.0, 15.0));
		s.tilt += wet * 0.05 * (ripple - normal * dot(ripple, normal));
		s.albedo = mix(s.albedo, liquid_tint, wet);
		s.metallic = mix(s.metallic, 0.0, wet);
		s.roughness = mix(s.roughness, 0.1, wet);
		s.specular = mix(s.specular, 1.0, wet);
		s.coat = max(s.coat, wet);
		s.coat_roughness = mix(s.coat_roughness, 0.04, wet);
	}
	if (glow_energy > 0.0) {
		float breath = 1.0;
		if (glow_pulse_s > 0.0) {
			// The breathing runs down the hull as a slow wave.
			breath = 1.0 - glow_pulse * (0.5 + 0.5 * sin(6.2831853 * (time / glow_pulse_s - pos.z / (40.0 * pattern_scale_m))));
		}
		vec3 light = mix(glow_colour, variant_glow, variant);
		s.emission += light * (glow_energy * mix(1.0, vein, glow_veins) * (1.0 + glow_rim * rim) * breath);
	}
}
