// A camera-facing round glow (M6-T19, M7-T23), shared by `jump_glow.gdshader` (a vortex's centre flash, a gate's lamps and
// tips) and `transit_flash.gdshader` (a ship's flash at the ring, M6-T22). Sized by the node's (or multimesh instance's) scale;
// the instance colour's alpha is its level, so one multimesh draws many.

uniform vec3 tint = vec3(1.0);
// Per instance, so every jump point shares one flash material (M6-T20).
instance uniform float level = 1.0;
// A round glow: a core, a wide soft halo and, for a lens's look, a thin ring some way out (M7-T23: the flashes are round; their
// lens flare is `FlashFlare`'s). `rays` adds spikes, 0 by the maintainer's word.
uniform float halo = 0.25;
uniform float ring = 0.0;
uniform float ring_at = 0.45;
uniform float rays = 0.0;
uniform float ray_count = 12.0;
// Pulled toward the camera by this share of its size, so a lamp on an arm is not cut by the arm.
uniform float lift = 0.5;
// A flash that whites out the view at its peak (a gate's, M7-T23): the star is drawn `spread` times smaller inside the quad, and
// above `bloom_from` of its level a flat white bloom of strength `bloom` fills the quad. 0 for every other glow.
uniform float spread = 1.0;
uniform float bloom = 0.0;
uniform float bloom_from = 0.55;

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
	float flood = bloom * smoothstep(bloom_from, 1.0, level) * (1.0 - smoothstep(0.55, 1.0, length(p)));
	p *= spread;
	float d = length(p);
	float core = exp(-d * d * 18.0) * 1.6 + exp(-d * d * 7.0) * 0.3;
	float ang = atan(p.y, p.x);
	float ray = 0.0;
	if (rays > 0.0) {
		float spikes = pow(abs(cos(ang * ray_count * 0.5)), 24.0) + 0.5 * pow(abs(cos(ang * ray_count * 0.5 + 0.9)), 40.0);
		ray = spikes * exp(-d * 3.2) * (1.0 - smoothstep(0.7, 1.0, d));
	}
	float soft = halo * exp(-d * d * 3.0);
	float band = (d - ring_at) / 0.035;
	float lens = ring * exp(-band * band);
	float glow = (core + soft + lens + rays * ray) * (1.0 - smoothstep(0.6, 1.0, d));
	ALBEDO = tint * v_colour.rgb * glow * level * v_colour.a + vec3(flood);
}
