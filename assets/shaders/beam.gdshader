// A beam's tube (M10-T12, `BeamDraw`): bright where the tube faces the eye and soft at its edges, in the instance's HDR colour;
// the colour's alpha fades a pulse out. Added light only: it hides nothing behind it and casts no shadow.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

void fragment() {
	float facing = abs(dot(normalize(NORMAL), normalize(VIEW)));
	ALBEDO = COLOR.rgb * pow(facing, 1.5) * COLOR.a;
}
