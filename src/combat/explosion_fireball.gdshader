shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_back;
// The fireball of a destroyed ship (architecture §15.7): unshaded and additive, animated 3D value noise, a blackbody
// ramp from white-blue (about 6 000 K) through yellow and orange (3 000 to 1 500 K) to smoke dark, and a soft fresnel
// edge so the sphere does not read as a sphere. `age` (seconds) drives everything; the sphere's scale is the caller's.

uniform float age = 0.0;
uniform float duration = 1.5;
uniform float intensity = 3.0;
uniform float noise_scale = 2.6;

varying vec3 v_obj;

float hash(vec3 p) {
	p = fract(p * 0.3183099 + vec3(0.1, 0.2, 0.3));
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float vnoise(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	float n000 = hash(i + vec3(0.0, 0.0, 0.0));
	float n100 = hash(i + vec3(1.0, 0.0, 0.0));
	float n010 = hash(i + vec3(0.0, 1.0, 0.0));
	float n110 = hash(i + vec3(1.0, 1.0, 0.0));
	float n001 = hash(i + vec3(0.0, 0.0, 1.0));
	float n101 = hash(i + vec3(1.0, 0.0, 1.0));
	float n011 = hash(i + vec3(0.0, 1.0, 1.0));
	float n111 = hash(i + vec3(1.0, 1.0, 1.0));
	return mix(mix(mix(n000, n100, f.x), mix(n010, n110, f.x), f.y), mix(mix(n001, n101, f.x), mix(n011, n111, f.x), f.y), f.z);
}

// heat 1 = about 6 000 K (white with a blue tint), 0.55 = 3 000 K (yellow-orange), 0.25 = 1 500 K (deep red), 0 = smoke.
vec3 blackbody_ramp(float heat) {
	vec3 smoke = vec3(0.02, 0.018, 0.016);
	vec3 red = vec3(0.9, 0.16, 0.03);
	vec3 orange = vec3(1.0, 0.55, 0.12);
	vec3 white = vec3(1.0, 0.95, 0.85);
	vec3 blue_white = vec3(0.85, 0.92, 1.0);
	vec3 c = mix(smoke, red, smoothstep(0.0, 0.25, heat));
	c = mix(c, orange, smoothstep(0.25, 0.55, heat));
	c = mix(c, white, smoothstep(0.55, 0.85, heat));
	return mix(c, blue_white, smoothstep(0.85, 1.0, heat));
}

void vertex() {
	v_obj = VERTEX;
}

void fragment() {
	float life = clamp(age / duration, 0.0, 1.0);
	vec3 p = v_obj * noise_scale;
	float n = 0.6 * vnoise(p + vec3(0.0, -age * 1.4, 0.0)) + 0.4 * vnoise(p * 2.3 - vec3(age * 0.6, age * 1.1, age * 0.5));
	// Hot core early, cooling with age; the noise makes it patchy and the patches cool at different rates.
	float heat = clamp((1.0 - life) * (0.55 + 0.9 * n) - 0.12 * life, 0.0, 1.0);
	float facing = clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0);
	float edge = pow(facing, 2.4); // soft fresnel edge: bright where we look through the middle of the ball, gone at the rim
	float fade = 1.0 - smoothstep(0.55, 1.0, life);
	float cloud = smoothstep(0.18, 0.7, n + 0.35 * (1.0 - life)); // patchy: gaps where the noise is low
	float alpha = clamp(edge * fade * cloud * 1.3, 0.0, 1.0);
	ALBEDO = blackbody_ramp(heat) * intensity * (0.4 + heat);
	ALPHA = alpha;
}
