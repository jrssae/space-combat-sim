// The hull in the target preview (architecture §18.20, M5-T43), drawn in the panel's ground colour only to fill the depth
// buffer, so the lines on its far side fail the depth test. Both sides of every face count: a single-sided panel hides too.
shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled, fog_disabled, ambient_light_disabled;

uniform vec4 ground : source_color = vec4(0.012, 0.06, 0.035, 1.0);

void fragment() {
	ALBEDO = ground.rgb;
}
