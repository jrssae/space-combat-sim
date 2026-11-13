shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, depth_test_disabled, cull_disabled, shadows_disabled, skip_vertex_transform;
// A ship's white flash at a jump vortex's black ring (M6-T22): the vortex's own glow, drawn over the funnel's base it sits on so a
// camera close by sees it whole rather than cut by the curving base.
#include "res://src/props/jump_glow.gdshaderinc"
