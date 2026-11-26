// A hull whose painted bands are recoloured per ship (M10-T53, Q86: the Asimov liners' liveries). The four maps as the standard hull
// material draws them, the hull's shared detail tile where it has one, and the bands, baked in the default livery's colour
// (`band_base`), repainted in the ship's livery (0, the default, leaves the paint as baked). A texel counts as band paint by how
// close its hue is to the baked band's, so patches and wear on the bands keep their shade in every livery.
// A piece with `bar_radius` set (the liner's turning band, Q95) also gets the ship's bars drawn on its white: so many round the
// axis, in the livery's colour, in no atlas, so ships with six and with eight share one.
// `skin_variant` carries both: the livery's index in `band_colours` plus MAX_LIVERIES times the ship's place in `bar_counts`.
// `BandTintMaterial` makes the material for every surface whose manifest entry has a `band_tint`.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

const int MAX_LIVERIES = 8;
const int MAX_BAR_COUNTS = 4;
const vec3 LUMA = vec3(0.2126, 0.7152, 0.0722);

uniform sampler2D albedo_map : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D normal_map : hint_normal, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D orm_map : hint_default_white, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D emissive_map : source_color, hint_default_black, filter_linear_mipmap_anisotropic, repeat_disable;
uniform float emission_energy = 1.0;
// `settings.hull_sheen`: a clear coat over the paint (MeshAssets sets both).
uniform float sheen = 0.0;
uniform float sheen_roughness = 0.35;

// The shared detail tile (D72), repeated every `detail_tile_m` on all three axes of the piece; 0: the hull has none.
uniform sampler2D detail_albedo_map : source_color, hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D detail_normal_map : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float detail_tile_m = 0.0;
uniform float detail_sharpness = 4.0;

// The band colour the atlas was baked in and every livery's, linear.
uniform vec3 band_base = vec3(0.03, 0.35, 0.04);
uniform vec3 band_colours[MAX_LIVERIES];
uniform int band_count = 1;

// The bars: the sphere they lie on (radius about the piece's origin, 0 for a piece without bars), their span along its axis (z),
// half a bar's width, the white they are painted over and the counts a ship may have.
uniform float bar_radius = 0.0;
uniform vec2 bar_span = vec2(0.0);
uniform float bar_half_m = 12.0;
uniform vec3 band_white = vec3(0.65);
uniform int bar_counts[MAX_BAR_COUNTS];
uniform int bar_count_choices = 0;

// The ship's livery and bar count (`BandTintMaterial.variant` packs them from the ship's name).
instance uniform float skin_variant = 0.0;

varying vec3 v_pos;
varying vec3 v_nrm;

void vertex() {
	v_pos = VERTEX;
	v_nrm = NORMAL;
}

// The paint with its band texels repainted in livery `index`, their brightness kept.
vec3 tinted(vec3 paint, int index) {
	if (index <= 0 || index >= min(band_count, MAX_LIVERIES)) {
		return paint;
	}
	float base_lum = max(dot(band_base, LUMA), 1e-4);
	float lum = max(dot(paint, LUMA), 1e-5);
	vec3 hue = paint / lum;
	vec3 base_hue = band_base / base_lum;
	float like = 1.0 - smoothstep(0.25, 0.7, length(hue - base_hue) / length(base_hue - vec3(1.0)));
	float chroma = max(paint.r, max(paint.g, paint.b)) - min(paint.r, min(paint.g, paint.b));
	float base_chroma = max(band_base.r, max(band_base.g, band_base.b)) - min(band_base.r, min(band_base.g, band_base.b));
	float mask = like * smoothstep(0.15 * base_chroma, 0.4 * base_chroma, chroma);
	vec3 target = band_colours[index] * (lum / base_lum);
	return mix(paint, target, mask);
}

// The paint with the ship's bars over the band's white, the paint's shade kept under them.
vec3 barred(vec3 paint, int livery, int choice) {
	// Wide enough below the sphere for the far meshes' flatter facets; the clamps stand above it.
	float off = length(v_pos) - bar_radius;
	if (bar_count_choices < 1 || v_pos.z < bar_span.x || v_pos.z > bar_span.y || off < -3.0 || off > 0.5) {
		return paint;
	}
	float sector = TAU / float(max(bar_counts[clamp(choice, 0, min(bar_count_choices, MAX_BAR_COUNTS) - 1)], 1));
	float across = abs(mod(atan(v_pos.y, v_pos.x) + 0.5 * sector, sector) - 0.5 * sector) * length(v_pos.xy);
	float soft = max(fwidth(across), 1e-4);
	float on = 1.0 - smoothstep(bar_half_m - soft, bar_half_m + soft, across);
	vec3 colour = band_colours[clamp(livery, 0, max(min(band_count, MAX_LIVERIES), 1) - 1)];
	return mix(paint, colour * (dot(paint, LUMA) / max(dot(band_white, LUMA), 1e-4)), on);
}

void fragment() {
	vec3 n_obj = normalize(v_nrm);
	vec3 orm = texture(orm_map, UV).rgb;
	int variant = int(round(skin_variant));
	int livery = variant % MAX_LIVERIES;
	vec3 paint = tinted(texture(albedo_map, UV).rgb, livery);
	if (bar_radius > 0.0) {
		paint = barred(paint, livery, variant / MAX_LIVERIES);
	}
	vec2 nm = texture(normal_map, UV).rg * 2.0 - 1.0;
	vec3 n = normalize(TANGENT * nm.x + BINORMAL * nm.y + NORMAL * sqrt(max(0.0, 1.0 - dot(nm, nm))));
	if (detail_tile_m > 0.0) {
		// The tile from the piece's three sides, weighted by which the surface faces, as the standard material's detail layer does.
		vec3 w = pow(abs(n_obj), vec3(detail_sharpness));
		w /= max(w.x + w.y + w.z, 1e-5);
		vec3 q = v_pos / detail_tile_m;
		vec4 tile = texture(detail_albedo_map, q.zy) * w.x + texture(detail_albedo_map, q.xz) * w.y + texture(detail_albedo_map, q.xy) * w.z;
		vec2 sx = texture(detail_normal_map, q.zy).rg * 2.0 - 1.0;
		vec2 sy = texture(detail_normal_map, q.xz).rg * 2.0 - 1.0;
		vec2 sz = texture(detail_normal_map, q.xy).rg * 2.0 - 1.0;
		vec3 tilt = w.x * vec3(0.0, -sx.y, sx.x) + w.y * vec3(sy.x, 0.0, -sy.y) + w.z * vec3(sz.x, -sz.y, 0.0);
		paint = mix(paint, paint * tile.rgb, tile.a);
		vec3 tilt_view = mat3(VIEW_MATRIX) * (MODEL_NORMAL_MATRIX * (tilt * tile.a));
		n = normalize(n + tilt_view - n * dot(tilt_view, n));
	}
	// The clear coat on painted skin only, as the hulls' other shaders have it.
	float on_paint = (1.0 - smoothstep(0.62, 0.78, orm.b)) * clamp((0.85 - orm.g) / 0.35, 0.0, 1.0);
	NORMAL = n;
	ALBEDO = paint;
	AO = orm.r;
	ROUGHNESS = orm.g;
	METALLIC = orm.b;
	SPECULAR = 0.5;
	EMISSION = texture(emissive_map, UV).rgb * emission_energy;
	CLEARCOAT = sheen * on_paint;
	CLEARCOAT_ROUGHNESS = clamp(sheen_roughness + (orm.g - 0.5), 0.1, 1.0);
}
