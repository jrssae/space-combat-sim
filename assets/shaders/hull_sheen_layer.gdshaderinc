// The sheen layer (M10-T06, D12.2): what makes a hull's skin change with the view, laid over its four maps as the liveries
// are a layer. Nothing is baked: a style names the numbers (`tools/procgen/core/sheen.py`, the manifest's `sheen` entry) and
// `HullSheenMaterial` sets them as these uniforms. Three effects, each off at zero:
//   iridescence: a colour by direction (nine spherical-harmonic coefficients) mixed into the paint towards the rim;
//   pattern: mottling or scales in the hull's own space, which may drift (the Shadows' moving skin; TIME, a visual only);
//   glow: a faint light of the hull's own (the Vorlons' bioluminescence).
// A shader includes this file and calls `sheen_layer` once its paint is worked out. The uniform `sheen` of the hull shaders
// is `settings.hull_sheen`'s clear coat, an older and different thing: this layer's uniforms are `iri_*`, `pattern_*`, `glow_*`.

uniform vec3 iri_sh[9];
uniform float iri_strength = 0.0;
uniform float iri_base = 0.0;
uniform float iri_power = 3.0;
uniform float iri_view = 0.5;
uniform float iri_metal = 0.0;
uniform float pattern_scale_m = 1.0;
uniform float pattern_cells = 0.0;
uniform float pattern_edge = 0.5;
uniform float pattern_cover = 0.5;
uniform float pattern_dark = 0.0;
uniform vec3 pattern_tint = vec3(0.0);
uniform float pattern_iri = 0.0;
uniform float pattern_rough = 0.0;
uniform float pattern_speed_mps = 0.0;
uniform vec3 glow_colour = vec3(0.0);
uniform float glow_energy = 0.0;
uniform float glow_veins = 0.0;
uniform float glow_rim = 0.0;
uniform float glow_pulse_s = 0.0;
uniform float glow_pulse = 0.0;
// The share of `settings.hull_sheen`'s clear coat the skin takes (the including shader applies it).
uniform float coat = 1.0;

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

// Scales: x how far the point is from the seam between its scale and the next (0 on the seam), y a tone of its own scale's.
vec2 sheen_scales(vec3 p) {
	vec3 c = floor(p);
	float nearest = 8.0;
	float second = 8.0;
	float tone = 0.0;
	for (int k = -1; k <= 1; k++) {
		for (int j = -1; j <= 1; j++) {
			for (int i = -1; i <= 1; i++) {
				vec3 cell = c + vec3(float(i), float(j), float(k));
				vec3 h = sheen_hash3(cell);
				float d = length(cell + h - p);
				if (d < nearest) {
					second = nearest;
					nearest = d;
					tone = h.y;
				} else if (d < second) {
					second = d;
				}
			}
		}
	}
	return vec2(second - nearest, tone);
}

// The iridescence's colour towards direction `d` (the hull's frame): the nine coefficients, in `sheen.sh_basis`'s order.
vec3 sheen_iridescence(vec3 d) {
	vec3 c = iri_sh[0] * 0.282095 + iri_sh[1] * (0.488603 * d.y) + iri_sh[2] * (0.488603 * d.z) + iri_sh[3] * (0.488603 * d.x)
			+ iri_sh[4] * (1.092548 * d.x * d.y) + iri_sh[5] * (1.092548 * d.y * d.z) + iri_sh[6] * (0.315392 * (3.0 * d.z * d.z - 1.0))
			+ iri_sh[7] * (1.092548 * d.x * d.z) + iri_sh[8] * (0.546274 * (d.x * d.x - d.y * d.y));
	return max(c, vec3(0.0));
}

// Lays the layer over a surface's paint. `pos`, `normal` and `view` (towards the eye) are in the hull's own frame, so the
// pattern and the colours ride with the hull; `footprint_m` is how much of the hull one pixel covers, so the pattern fades to
// its mean instead of sparkling when a blotch is smaller than a pixel.
void sheen_layer(vec3 pos, vec3 normal, vec3 view, float footprint_m, float time, inout vec3 albedo, inout float metallic,
		inout float roughness, inout vec3 emission) {
	float ink = 0.0;
	float vein = 0.0;
	float tone = 0.5;
	if (pattern_dark + pattern_iri + pattern_rough + glow_veins > 0.0) {
		vec3 p = pos / pattern_scale_m;
		float drift = time * pattern_speed_mps / pattern_scale_m;
		float edge = mix(0.3, 0.03, pattern_edge);
		// Mottling: two noises that drift apart, so the blotches change shape as they move.
		float n = 0.6 * sheen_noise(p + drift * vec3(0.15, 0.1, 1.0)) + 0.4 * sheen_noise(p * 2.1 - drift * vec3(0.6, 0.35, -0.2));
		float level = mix(0.72, 0.28, pattern_cover);
		float blot = smoothstep(level - edge, level + edge, n);
		float blot_vein = 1.0 - smoothstep(0.0, 2.0 * edge + 0.04, abs(n - level));
		float seam = 0.0;
		if (pattern_cells > 0.0) {
			// Scales: each slides along the hull and breathes a little, the seams between them the pattern's ink.
			vec2 s = sheen_scales(p * 1.3 + drift * vec3(0.0, 0.0, 1.0) + 0.25 * sin(drift * 0.7 + p.yzx * 1.7));
			seam = 1.0 - smoothstep(0.0, mix(0.02, 0.3, pattern_cover) + edge * 0.5, s.x);
			tone = s.y;
		}
		ink = mix(blot, seam, pattern_cells);
		vein = mix(blot_vein, seam, pattern_cells);
		float sharp = smoothstep(1.0, 0.25, footprint_m / pattern_scale_m);
		float mean_ink = mix(pattern_cover, 0.3, pattern_cells);
		ink = mix(mean_ink, ink, sharp);
		vein = mix(0.25, vein, sharp);
		tone = mix(0.5, tone, sharp * pattern_cells);
	}
	albedo = mix(albedo, pattern_tint, pattern_dark * ink);
	roughness = clamp(roughness + pattern_rough * (ink + (tone - 0.5) * 0.6), 0.04, 1.0);

	float facing = clamp(dot(normal, view), 0.0, 1.0);
	float rim = pow(1.0 - facing, iri_power);
	if (iri_strength + iri_base > 0.0) {
		vec3 towards = normalize(mix(normal, reflect(-view, normal), iri_view) + vec3(0.0, 1e-4, 0.0));
		float amount = mix(iri_base, iri_strength, rim) * (1.0 - pattern_iri * ink) * (1.0 + (tone - 0.5) * 0.5 * pattern_cells);
		amount = clamp(amount, 0.0, 1.0);
		albedo = mix(albedo, sheen_iridescence(towards), amount);
		metallic = mix(metallic, 1.0, amount * iri_metal);
	}
	if (glow_energy > 0.0) {
		float breath = 1.0;
		if (glow_pulse_s > 0.0) {
			// The breathing runs down the hull as a slow wave.
			breath = 1.0 - glow_pulse * (0.5 + 0.5 * sin(6.2831853 * (time / glow_pulse_s - pos.z / (40.0 * pattern_scale_m))));
		}
		emission += glow_colour * (glow_energy * mix(1.0, vein, glow_veins) * (1.0 + glow_rim * rim) * breath);
	}
}
