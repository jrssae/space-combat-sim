// A hull with a sheen layer (M10-T06, D12.2): the Vorlons' and the Shadows' organic skins and the semi-organic hulls'. The four
// maps as the standard hull material draws them, the hull's shared detail tile where it has one (the hexagonal plating of the
// Minbari and the Interstellar Alliance, laid in the piece's own space), and over them the sheen layer
// (`hull_sheen_layer.gdshaderinc`). `HullSheenMaterial` makes it for every surface whose manifest entry has a `sheen`.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

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

#include "res://assets/shaders/hull_sheen_layer.gdshaderinc"

// 1 on a ship of its style's second colouring (the red-based Vorlons): `HullSheenMaterial.variant_for` picks it per ship.
instance uniform float skin_variant = 0.0;

varying vec3 v_pos;
varying vec3 v_nrm;

void vertex() {
	v_pos = VERTEX;
	v_nrm = NORMAL;
}

void fragment() {
	vec3 n_obj = normalize(v_nrm);
	vec3 orm = texture(orm_map, UV).rgb;
	vec3 paint = texture(albedo_map, UV).rgb;
	vec2 nm = texture(normal_map, UV).rg * 2.0 - 1.0;
	vec3 n = normalize(TANGENT * nm.x + BINORMAL * nm.y + NORMAL * sqrt(max(0.0, 1.0 - dot(nm, nm))));
	if (detail_tile_m > 0.0) {
		// The tile from the piece's three sides, weighted by which the surface faces: it multiplies the paint where its alpha
		// says so and tilts the normal, as the standard material's detail layer does.
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
	SheenSurface skin = SheenSurface(paint, orm.b, orm.g, 0.5, texture(emissive_map, UV).rgb * emission_energy, vec3(0.0),
			sheen * coat * on_paint, clamp(sheen_roughness + (orm.g - 0.5), 0.1, 1.0));
	// The view from the fragment, in the hull's own frame, so the layer rides with the hull whichever way it is turned.
	vec3 view_obj = normalize((inverse(MODEL_MATRIX) * (INV_VIEW_MATRIX * vec4(VIEW, 0.0))).xyz);
	float footprint_m = max(length(dFdx(v_pos)), length(dFdy(v_pos)));
	sheen_layer(v_pos, n_obj, view_obj, footprint_m, TIME, skin_variant, skin);

	// The layer's lean on the normal (a scale's rim, the liquid's ripples), from the hull's frame into the view's.
	vec3 lean = mat3(VIEW_MATRIX) * (MODEL_NORMAL_MATRIX * skin.tilt);
	NORMAL = normalize(n + lean - n * dot(lean, n));
	ALBEDO = skin.albedo;
	AO = orm.r;
	ROUGHNESS = skin.roughness;
	METALLIC = skin.metallic;
	SPECULAR = skin.specular;
	EMISSION = skin.emission;
	CLEARCOAT = skin.coat;
	CLEARCOAT_ROUGHNESS = skin.coat_roughness;
}
