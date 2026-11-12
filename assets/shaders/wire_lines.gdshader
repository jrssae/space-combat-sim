// A hull's feature edges in the target preview (architecture §18.20, M5-T43). Each line is pulled a little toward the
// camera so it wins the depth test against the faces it lies on and loses it against anything in front of them; with the
// preview's orthographic camera the pull does not move it on screen. It writes no depth: the outline pass reads the hull's.
shader_type spatial;
render_mode unshaded, skip_vertex_transform, depth_draw_never, shadows_disabled, fog_disabled, ambient_light_disabled;

uniform vec4 line_color : source_color = vec4(0.55, 1.0, 0.6, 1.0);
// How far a line comes toward the camera, m.
uniform float pull_m = 0.05;

void vertex() {
	VERTEX = (MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	VERTEX.z += pull_m;
}

void fragment() {
	ALBEDO = line_color.rgb;
}
