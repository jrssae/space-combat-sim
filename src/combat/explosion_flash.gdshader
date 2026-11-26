// The first flash of an explosion (architecture §15.7, M10-T11): one instance of `ExplosionPool`'s flash multimesh, a quad
// facing the camera, additive, its brightness fading from 1 (custom data r). The soft round glow is the old glow
// texture's ramp (white at the centre, 0.55 at three tenths out, nothing at the rim), made in the shader.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled, ambient_light_disabled;

uniform vec3 tint = vec3(2.4, 1.7, 1.0);

varying float strength;

void vertex() {
	strength = INSTANCE_CUSTOM.r;
	float size = length(MODEL_MATRIX[0].xyz);
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0] * size, INV_VIEW_MATRIX[1] * size, INV_VIEW_MATRIX[2] * size, MODEL_MATRIX[3]);
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
}

void fragment() {
	float r = length(UV * 2.0 - vec2(1.0));
	float g = r < 0.3 ? mix(1.0, 0.55, r / 0.3) : mix(0.55, 0.0, clamp((r - 0.3) / 0.7, 0.0, 1.0));
	ALBEDO = tint * g * g * strength;
}
