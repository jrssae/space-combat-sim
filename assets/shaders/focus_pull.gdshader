// The focus pull (architecture §18.21, M5-T44): blurs and dims whatever is drawn under it by sampling a mip of the screen
// with a small ring of taps, so the mip's blocks smooth out.
shader_type canvas_item;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap, repeat_disable;
// Eased pull 0..1 times the setting.
uniform float lod_level = 0.0;
uniform float dim = 0.0;

void fragment() {
	vec2 px = SCREEN_PIXEL_SIZE * exp2(lod_level);
	vec3 sum = textureLod(screen_tex, SCREEN_UV, lod_level).rgb * 0.25;
	for (int i = 0; i < 8; i++) {
		float a = float(i) * 0.785398;
		sum += textureLod(screen_tex, SCREEN_UV + vec2(cos(a), sin(a)) * px * 0.75, lod_level).rgb * 0.09375;
	}
	COLOR = vec4(sum * (1.0 - dim), 1.0);
}
