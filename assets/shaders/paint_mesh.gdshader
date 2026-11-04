// The painted mesh's opaque surface (M4-T27): see paint_mesh.gdshaderinc.
shader_type spatial;
render_mode unshaded, cull_back, depth_draw_opaque;

#include "res://assets/shaders/paint_mesh.gdshaderinc"

void fragment() {
	ALBEDO = paint_colour(FRONT_FACING, v_material, v_local_pos, v_local_normal, v_phase, v_world_pos, v_world_normal);
}
