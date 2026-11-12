// The star on the scaled-space layer (M6-T12, D68): its disc with limb darkening and a corona around it, drawn on a sphere
// `glow_scale` times the disc's radius, each pixel working out its angular distance from the disc's centre. Additive, with the
// same pinned depth as the other bodies (the vertex stage is theirs). SunLook has the same law for the tests.
shader_type spatial;
render_mode unshaded, cull_front, blend_add, depth_draw_always, shadows_disabled, fog_disabled, ambient_light_disabled;

uniform float layer_depth = 1.0e-8;
uniform vec3 colour : source_color = vec3(1.0, 0.8, 0.6);
uniform vec3 corona_colour : source_color = vec3(1.0, 0.7, 0.4);
uniform float glow_scale = 10.0;
uniform float disc_brightness = 2.4;
uniform float corona_strength = 0.25;
uniform float limb_darkening = 0.7;

void vertex() {
	vec4 clip = PROJECTION_MATRIX * (MODELVIEW_MATRIX * vec4(VERTEX, 1.0));
	POSITION = vec4(clip.xy, layer_depth * clip.w, clip.w);
}

void fragment() {
	vec3 centre = (VIEW_MATRIX * MODEL_MATRIX[3]).xyz;
	float distance_to_centre = length(centre);
	vec3 ray = normalize(VERTEX);
	// Distance from the centre in disc radii: the sine of the angle over the sine of the disc's angular radius.
	float x = length(cross(ray, centre / distance_to_centre)) / (length(MODEL_MATRIX[0].xyz) / glow_scale / distance_to_centre);
	if (x >= glow_scale * 0.95) {
		discard;
	}
	float edge = fwidth(x);
	vec3 result;
	float corona = corona_strength * pow(1.0 / max(x, 1.0), 1.6)
			* (1.0 - smoothstep(glow_scale * 0.5, glow_scale * 0.95, x));
	if (x < 1.0 - edge) {
		float mu = sqrt(max(1.0 - x * x, 0.0));
		result = colour * disc_brightness * (1.0 - limb_darkening * (1.0 - mu));
	} else {
		float inside = 1.0 - smoothstep(1.0 - edge, 1.0 + edge, x);
		float rim = 1.0 - limb_darkening;
		result = mix(corona_colour * disc_brightness * corona, colour * disc_brightness * rim, inside);
	}
	ALBEDO = result;
	ALPHA = 1.0;
}
