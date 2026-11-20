shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_always, cull_disabled, shadows_disabled;
// Everywhere but over a gate's hull (M8-T17: the gate writes `Jumpgate.HULL_STENCIL`; its pass is jump_vortex_over_gate).
stencil_mode read, compare_not_equal, 64;
#include "res://src/props/jump_vortex.gdshaderinc"
