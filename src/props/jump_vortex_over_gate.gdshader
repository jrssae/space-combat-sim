shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_always, cull_disabled, shadows_disabled;
// The funnel's second pass, over a gate's hull alone (M8-T17, the shot reviewer: the arms showed through the translucent walls):
// where the wall lies in front of the hull it draws as it does against empty space, so no arm shows through it.
stencil_mode read, compare_equal, 64;
#define OVER_GATE
#include "res://src/props/jump_vortex.gdshaderinc"
