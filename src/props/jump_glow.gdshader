shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, skip_vertex_transform;
// A camera-facing glow with soft rays (M6-T19): a jump vortex's centre flash, and a jumpgate's lamps and inner tips as they
// light up. The glow itself is in `jump_glow.gdshaderinc`.
#include "res://src/props/jump_glow.gdshaderinc"
