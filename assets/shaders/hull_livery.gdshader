// A textured hull with its wing's livery (M4-T30b, Q35; architecture §17.18): the shared maps (albedo, normal, ORM, emissive) as
// the standard material draws them, and over them the wing's colours, pattern and the ship's number, chosen per instance. The
// pattern table and the number fields come from the manifest's `livery` section (`MeshAssets`); a ship gives only its colours,
// its pattern, its number fields and its number, so every wing's ships share this one material and instance.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

const int MAX_STRIPES = 48;
const int MAX_PATTERNS = 12;
const int MAX_FIELDS = 8;

uniform sampler2D albedo_map : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D normal_map : hint_normal, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D orm_map : hint_default_white, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D emissive_map : source_color, hint_default_black, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D digit_map : hint_default_black, filter_linear_mipmap, repeat_disable;
uniform float emission_energy = 1.0;
// `settings.hull_sheen`: a clear coat over the paint (MeshAssets sets both).
uniform float sheen = 0.0;
uniform float sheen_roughness = 0.35;
// The hull paint the base map was painted with (linear): paint is darkened as the base is (panel lines, grime, streaks).
uniform vec3 hull_paint = vec3(0.35);

// Each stripe: axis (w 1: |x|), range (lo, hi, slot, zone bits), facing (xyz, w minimum cosine).
uniform vec4 stripe_axis[MAX_STRIPES];
uniform vec4 stripe_range[MAX_STRIPES];
uniform vec4 stripe_facing[MAX_STRIPES];
// Each pattern's first stripe and count.
uniform vec2 pattern_span[MAX_PATTERNS];
// Each number field: centre (w height), right (w stroke weight), up (w zone bits), facing; the centre's y is taken on the point's side.
uniform vec4 field_centre[MAX_FIELDS];
uniform vec4 field_right[MAX_FIELDS];
uniform vec4 field_up[MAX_FIELDS];
uniform vec4 field_facing[MAX_FIELDS];
// The digit atlas: ten cells of cell_units (x, y) glyph units, the glyph's size, the advance, and the distance range.
uniform vec4 digit_layout = vec4(6.0, 8.0, 5.4, 1.5);
uniform vec2 glyph_size = vec2(4.0, 6.0);

instance uniform vec4 livery_primary = vec4(0.3, 0.3, 0.3, 1.0);
instance uniform vec4 livery_secondary = vec4(0.3, 0.3, 0.3, 1.0);
instance uniform vec4 livery_number_colour = vec4(0.8, 0.8, 0.8, 1.0);
instance uniform int livery_pattern = 0;
instance uniform int livery_fields = 0;
instance uniform int livery_number = 0;

varying vec3 v_obj_pos;
varying vec3 v_obj_normal;
varying flat int v_zone;

void vertex() {
	v_obj_pos = VERTEX;
	v_obj_normal = NORMAL;
	v_zone = int(round(COLOR.r * 255.0));
}

// How much of one band [lo, hi) of coordinate c covers this pixel, smoothed over `w`, the coordinate's change across a pixel.
float band(float c, float w, float lo, float hi) {
	return clamp((c - lo) / w + 0.5, 0.0, 1.0) * clamp((hi - c) / w + 0.5, 0.0, 1.0);
}

// How much of a two-digit number covers this point of a field, in the field's glyph units (y up, centred). The gradients come
// from the caller, taken outside any per-pixel branch, so the digit atlas's mipmap choice is defined on every pixel.
float number_cover(vec2 u, vec2 du_dx, vec2 du_dy, int number, float weight) {
	float advance = digit_layout.z;
	float width = advance + glyph_size.x;
	float half_stroke = 0.5 * weight;
	float aa = max(length(abs(du_dx) + abs(du_dy)), 1e-4);
	vec2 to_uv = vec2(1.0 / (10.0 * digit_layout.x), -1.0 / digit_layout.y);
	vec2 margin = 0.5 * (digit_layout.xy - glyph_size);
	float cover = 0.0;
	for (int k = 0; k < 2; k++) {
		int digit = k == 0 ? (number / 10) % 10 : number % 10;
		vec2 cell = u - vec2(-0.5 * width + float(k) * advance, -0.5 * glyph_size.y) + margin;
		float inside = step(0.0, cell.x) * step(0.0, cell.y) * step(cell.x, digit_layout.x) * step(cell.y, digit_layout.y);
		vec2 clamped = clamp(cell, vec2(0.0), digit_layout.xy);
		vec2 uv = vec2((float(digit) * digit_layout.x + clamped.x) / (10.0 * digit_layout.x), 1.0 - clamped.y / digit_layout.y);
		float distance = (1.0 - textureGrad(digit_map, uv, du_dx * to_uv, du_dy * to_uv).r) * digit_layout.w;
		cover = max(cover, inside * clamp((half_stroke - distance) / aa + 0.5, 0.0, 1.0));
	}
	return cover;
}

void fragment() {
	vec4 base = texture(albedo_map, UV);
	vec3 colour = base.rgb;
	// Only per-instance values decide which paths run (the same for every pixel of a quad), so every derivative and every sample
	// below is taken on all of them; the zone, the facing and the paint mask are multiplied in instead of branched on.
	if (livery_pattern > 0 || (livery_fields != 0 && livery_number > 0)) {
		vec3 p = v_obj_pos;
		vec3 face = normalize(cross(dFdx(p), dFdy(p)));
		face = dot(face, v_obj_normal) < 0.0 ? -face : face;
		int zone_bit = v_zone > 0 ? 1 << v_zone : 0;
		vec3 paint = vec3(0.0);  // premultiplied by coverage
		float coverage = 0.0;
		if (livery_pattern > 0 && livery_pattern < MAX_PATTERNS) {
			vec2 span = pattern_span[livery_pattern];
			int first = int(span.x);
			int last = min(first + int(span.y), MAX_STRIPES);
			for (int i = first; i < last; i++) {
				vec4 range = stripe_range[i];
				vec4 axis = stripe_axis[i];
				vec3 q = vec3(axis.w > 0.5 ? abs(p.x) : p.x, p.y, p.z);
				float c = dot(q, axis.xyz);
				float w = max(fwidth(c), 1e-5);
				float on = ((int(range.w) & zone_bit) != 0 && dot(face, stripe_facing[i].xyz) >= stripe_facing[i].w) ? 1.0 : 0.0;
				float cover = on * band(c, w, range.x, range.y);
				vec3 slot_colour = range.z > 1.5 ? livery_secondary.rgb : livery_primary.rgb;
				paint = paint * (1.0 - cover) + slot_colour * cover;
				coverage = cover + coverage * (1.0 - cover);
			}
		}
		if (livery_number > 0) {
			for (int f = 0; f < MAX_FIELDS; f++) {
				if ((livery_fields & (1 << f)) == 0) {
					continue;
				}
				vec3 centre = field_centre[f].xyz;
				centre.y *= p.y < 0.0 ? -1.0 : 1.0;
				vec3 d = p - centre;
				vec2 u = vec2(dot(d, field_right[f].xyz), dot(d, field_up[f].xyz)) / field_centre[f].w * glyph_size.y;
				vec2 du_dx = dFdx(u);
				vec2 du_dy = dFdy(u);
				float on = ((int(field_up[f].w) & zone_bit) != 0 && dot(face, field_facing[f].xyz) >= 0.5) ? 1.0 : 0.0;
				float cover = on * number_cover(u, du_dx, du_dy, livery_number, field_right[f].w);
				paint = paint * (1.0 - cover) + livery_number_colour.rgb * cover;
				coverage = cover + coverage * (1.0 - cover);
			}
		}
		float wear = clamp(dot(base.rgb, vec3(1.0)) / max(dot(hull_paint, vec3(1.0)), 1e-4), 0.0, 1.4);
		// `paint` is premultiplied by `coverage`; the albedo's alpha keeps it off chips, markings and unpainted materials.
		colour = base.rgb * (1.0 - coverage * base.a) + paint * wear * base.a;
	}
	ALBEDO = colour;
	NORMAL_MAP = texture(normal_map, UV).rgb;
	vec3 orm = texture(orm_map, UV).rgb;
	AO = orm.r;
	ROUGHNESS = orm.g;
	METALLIC = orm.b;
	SPECULAR = 0.35;  // matte paint (Q34: less gloss)
	// The clear coat is on the paint only, and as worn as the paint under it (M7-T17): none on bare metal, duller on grime and
	// wear, its sharpness following each plate's roughness, so it never lies over the hull as one even plastic shell.
	float on_paint = (1.0 - smoothstep(0.62, 0.78, orm.b)) * clamp((0.85 - orm.g) / 0.35, 0.0, 1.0);
	CLEARCOAT = sheen * on_paint;
	CLEARCOAT_ROUGHNESS = clamp(sheen_roughness + (orm.g - 0.5), 0.1, 1.0);
	EMISSION = texture(emissive_map, UV).rgb * emission_energy;
}
