// A textured hull's canopy glass (M4-T30b, Q36): dark, neutral and see-through, with the cabin's dark red glow showing through it
// from outside. The glow follows `settings.cabin_glow_level` and fades out by `settings.cabin_glow_view_m`.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_burley, specular_schlick_ggx;

uniform sampler2D albedo_map : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D orm_map : hint_default_white, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D emissive_map : source_color, hint_default_black, filter_linear_mipmap_anisotropic, repeat_disable;
// How much of the light behind the glass it stops: 1 - the material's transmittance.
uniform float glass_alpha = 0.3;
uniform float glow_energy = 0.12;
uniform float glow_view_m = 150.0;

void fragment() {
	ALBEDO = texture(albedo_map, UV).rgb;
	ALPHA = glass_alpha;
	vec3 orm = texture(orm_map, UV).rgb;
	ROUGHNESS = orm.g;
	METALLIC = orm.b;
	float fade = 1.0 - smoothstep(0.8 * glow_view_m, glow_view_m, length(VERTEX));
	EMISSION = texture(emissive_map, UV).rgb * glow_energy * fade;
}
