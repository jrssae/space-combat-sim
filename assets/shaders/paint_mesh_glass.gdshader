// The painted mesh's see-through surface, the canopy glass (M4-T27): see paint_mesh.gdshaderinc.
shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix, depth_draw_never;

#include "res://assets/shaders/paint_mesh.gdshaderinc"

// How much of the light behind the glass it stops: 1 - the material's transmittance.
uniform float glass_alpha = 0.3;

void fragment() {
	ALBEDO = paint_colour(FRONT_FACING, v_material, v_local_pos, v_local_normal, v_phase, v_world_pos, v_world_normal);
	ALPHA = glass_alpha;
}
