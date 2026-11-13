// A far prop as a point (M6-T15, `FarProp`): the far ship dot's rule (`far_ship_dot.gdshader`, M4-T11) on one quad. Its
// footprint is `radius_m` seen from where the quad is (the prop shrunk toward the eye, so the angle is the true one), never under
// `min_radius_px`; under that it keeps the floor and dims by the square, so what it covers stays continuous. `fade` is the
// cross-fade with the mesh. Alpha-blended and depth-tested at its centre, so a nearer hull hides it. A far planet's dot
// (`ScaledSpace`) takes the layer's pinned depth instead.
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled, ambient_light_disabled;

uniform vec3 paint = vec3(0.2); // linear
uniform float radius_m = 1.0;
uniform float fade = 1.0;
uniform float min_radius_px = 1.0;
// Above 0, the scaled-space layer's pinned depth (a far planet's dot, M6-T10's slab) instead of the quad's own.
uniform float layer_depth = 0.0;

varying float dim;

void vertex() {
	vec4 clip = PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0);
	float real_px = radius_m * abs(PROJECTION_MATRIX[1][1]) * 0.5 * VIEWPORT_SIZE.y / max(clip.w, 0.001);
	float ratio = min(real_px / max(min_radius_px, 0.001), 1.0);
	dim = ratio * ratio * fade;
	vec2 ndc = 2.0 * max(real_px, min_radius_px) * 2.0 * VERTEX.xy / VIEWPORT_SIZE;
	POSITION = vec4(clip.xy + ndc * clip.w, layer_depth > 0.0 ? layer_depth * clip.w : clip.z, clip.w);
}

void fragment() {
	float r = length(UV * 2.0 - vec2(1.0));
	ALBEDO = paint;
	ALPHA = max(1.0 - r * r, 0.0) * dim;
}
