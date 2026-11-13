// A planet's surface on the scaled-space layer (M6-T11, D68): the generated maps on the true sphere, lit from the true sun.
// The mesh is only a coarse cover a little larger than the planet; each pixel finds its own point on the sphere, so the
// limb is round from any distance. The depth is T10's: every pixel takes `layer_depth`, behind the whole near world.
// The look follows the show still (docs/design-references.md, "Epsilon III"): relief from the normal map on the lit side
// only, a hard terminator, a near-black night side with no lights, thin wisps lit only where the sun is up.
shader_type spatial;
render_mode unshaded, cull_front, shadows_disabled, fog_disabled, ambient_light_disabled;

uniform float layer_depth = 5.0e-9;
// The mesh's vertices are pushed out by this so its flat faces enclose the sphere (PlanetLook.mesh_inflate).
uniform float mesh_inflate = 1.003;
// Unit vector toward the star in the planet's own frame (PlanetLook.sun_in_body).
uniform vec3 sun_body = vec3(0.0, 1.0, 0.0);
uniform sampler2D albedo_map : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_map : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D wisp_map : hint_default_black, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec3 wisp_tint : source_color = vec3(0.94, 0.89, 0.81);
// How bright full sun on the surface is drawn, against a lit surface's 1.
uniform float sun_strength = 1.5;
// What the night side keeps: near black, but not a hole in the sky.
uniform float night_level = 0.004;
// The terminator's width in the cosine of the sun's height: hard, as in the still.
uniform vec2 terminator = vec2(-0.02, 0.1);

varying vec3 model_position;
varying vec3 model_eye;

void vertex() {
	VERTEX *= mesh_inflate;
	model_position = VERTEX;
	model_eye = (inverse(MODEL_MATRIX) * vec4(CAMERA_POSITION_WORLD, 1.0)).xyz;
	vec4 clip = PROJECTION_MATRIX * (MODELVIEW_MATRIX * vec4(VERTEX, 1.0));
	POSITION = vec4(clip.xy, layer_depth * clip.w, clip.w);
}

// Map coordinates of a unit direction (the manifest's layout: u = 0 at +Z growing east toward +X, v = 0 at the north pole).
vec2 map_uv(vec3 d) {
	return vec2(atan(d.x, d.z) / TAU, 0.5 - asin(clamp(d.y, -1.0, 1.0)) / PI);
}

void fragment() {
	vec3 ray = normalize(model_position - model_eye);
	// The closest approach to the centre, found without subtracting two large numbers (a far planet is a few pixels).
	vec3 closest = model_eye - ray * dot(model_eye, ray);
	float miss = dot(closest, closest) - 1.0;
	// Pixels just off the limb still shade the limb's point, so the 2x2 derivatives below stay continuous.
	vec3 n = normalize(closest - ray * sqrt(max(-miss, 0.0)));

	// The texture lookups take their gradients from whichever of two u's is continuous here: atan's (-0.5 to 0.5, broken
	// at 180 degrees) or its fraction (0 to 1, broken at 0), so neither seam drops to the smallest mip level.
	vec2 uv = map_uv(n);
	vec2 uv_wrapped = vec2(fract(uv.x), uv.y);
	vec2 dx = dFdx(uv);
	vec2 dy = dFdy(uv);
	vec2 dx_wrapped = dFdx(uv_wrapped);
	vec2 dy_wrapped = dFdy(uv_wrapped);
	if (abs(dx_wrapped.x) + abs(dy_wrapped.x) < abs(dx.x) + abs(dy.x)) {
		dx = dx_wrapped;
		dy = dy_wrapped;
	}
	uv.x = fract(uv.x);
	vec3 albedo = textureGrad(albedo_map, uv, dx, dy).rgb;
	vec2 tilt = textureGrad(normal_map, uv, dx, dy).rg * 2.0 - 1.0;
	float wisp = textureGrad(wisp_map, uv, dx, dy).r;

	// The normal map's axes: east, north, up.
	vec3 east = normalize(vec3(n.z, 0.0, -n.x) + vec3(1.0e-6, 0.0, 0.0));
	vec3 north = cross(n, east);
	vec3 bumped = normalize(tilt.x * east + tilt.y * north + sqrt(max(1.0 - dot(tilt, tilt), 0.0)) * n);

	float sun_height = dot(n, sun_body);
	// The relief catches light only where the sun is up, and the terminator stays hard.
	float day = max(dot(bumped, sun_body), 0.0) * smoothstep(terminator.x, terminator.y, sun_height);
	vec3 colour = albedo * (sun_strength * day + night_level);
	colour = mix(colour, wisp_tint * sun_strength * max(sun_height, 0.0), wisp);
	ALBEDO = colour;
	if (miss > 0.0) {
		discard;
	}
}
