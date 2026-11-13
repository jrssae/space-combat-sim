// A camera-facing glow with soft rays (M6-T19), shared by `jump_glow.gdshader` (a vortex's centre flash, a gate's lamps and
// tips) and `transit_flash.gdshader` (a ship's flash at the ring, M6-T22). Sized by the node's (or multimesh instance's) scale;
// the instance colour's alpha is its level, so one multimesh draws many.

uniform vec3 tint = vec3(1.0);
// Per instance, so every jump point shares one flash material (M6-T20).
instance uniform float level = 1.0;
// How strong the rays are against the round core, and how many.
uniform float rays = 0.6;
uniform float ray_count = 12.0;
// Pulled toward the camera by this share of its size, so a lamp on an arm is not cut by the arm.
uniform float lift = 0.5;

varying vec4 v_colour;

void vertex() {
	vec3 centre = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float size = length(MODEL_MATRIX[0].xyz);
	vec4 view = VIEW_MATRIX * vec4(centre, 1.0);
	VERTEX = view.xyz + vec3(VERTEX.xy * size, lift * size);
	v_colour = COLOR;
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float d = length(p);
	float core = exp(-d * d * 18.0) * 1.6 + exp(-d * d * 7.0) * 0.3;
	float ang = atan(p.y, p.x);
	float spikes = pow(abs(cos(ang * ray_count * 0.5)), 24.0) + 0.5 * pow(abs(cos(ang * ray_count * 0.5 + 0.9)), 40.0);
	float ray = spikes * exp(-d * 3.2) * (1.0 - smoothstep(0.7, 1.0, d));
	float glow = (core + rays * ray) * (1.0 - smoothstep(0.6, 1.0, d));
	ALBEDO = tint * v_colour.rgb * glow * level * v_colour.a;
}
