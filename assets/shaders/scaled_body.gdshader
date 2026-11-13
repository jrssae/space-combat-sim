// A far body's stand-in on the scaled-space layer (M6-T10, D68): a small sphere near the camera that covers the same angle as
// the real one. Its depth is not its own: every pixel takes `layer_depth`, a reversed depth just in front of the far plane,
// so the whole near world draws over it and the sky and the star points stay behind it; nearer bodies get the larger value.
// The placeholder look: a star glows flat, a planet is lit from the true sun direction with a plain day and night side.
// M6-T11 and T12 replace the look and keep the vertex stage.
shader_type spatial;
render_mode unshaded, cull_back, shadows_disabled, fog_disabled, ambient_light_disabled;

uniform float layer_depth = 5.0e-9;
uniform vec3 colour : source_color = vec3(0.6, 0.45, 0.35);
// Unit vector toward the star, world axes.
uniform vec3 sun_direction = vec3(0.0, 1.0, 0.0);
// 1 for a body that shines by itself (the star): no day and night side.
uniform float glows = 0.0;
uniform float brightness = 1.0;
// What the night side keeps, so the disc still hides the stars visibly.
uniform float night_level = 0.01;

varying vec3 world_normal;

void vertex() {
	world_normal = normalize(mat3(MODEL_MATRIX) * NORMAL);
	vec4 clip = PROJECTION_MATRIX * (MODELVIEW_MATRIX * vec4(VERTEX, 1.0));
	POSITION = vec4(clip.xy, layer_depth * clip.w, clip.w);
}

void fragment() {
	float day = max(dot(normalize(world_normal), sun_direction), 0.0);
	ALBEDO = colour * brightness * mix(max(day, night_level), 1.0, glows);
}
