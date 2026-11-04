// The painted mesh (M4-T27, Q24): a hull's surface drawn as triangles instead of splats, painted and lit the way GDGS paints and lights
// the splats sampled from the same surface (tools/procgen/core/paint_mesh.py, architecture §17.16). Each vertex's UV carries its part's
// panel phase and its material as integers; the panel lines and per-panel tint are Style.shade_panels on the GPU, and the light is
// GDGS's relight factor over the same 8 lights (PaintMeshLights fills the uniforms), applied before the sRGB to linear step as
// GDGS applies it, so a mesh and its splats agree on paint and shading.

#define PHASE_STEPS 97.0

uniform vec3 paint_albedo[32];
uniform float paint_paneled[32];
uniform float panel_size_m = 0.6;
uniform float panel_line_width_m = 0.04;
uniform float panel_line_darkness = 0.55;
uniform float panel_tint_jitter = 0.05;

uniform int light_count = 0;
uniform vec3 light_vectors[8];
uniform vec4 light_colors[8];
uniform vec4 light_params[8];
uniform vec3 light_spot_directions[8];
uniform bool relight_on = true;
uniform float relight_unlit_level = 0.12;
uniform float relight_ambient = 0.3;
uniform float relight_light_gain = 0.6;

varying flat vec3 v_phase;
varying flat float v_material;
varying vec3 v_local_pos;
varying vec3 v_local_normal;
varying vec3 v_world_pos;
varying vec3 v_world_normal;

void vertex() {
	float u = round(UV.x);
	float v = round(UV.y);
	v_phase = vec3(mod(u, PHASE_STEPS), floor(u / PHASE_STEPS), mod(v, PHASE_STEPS)) / PHASE_STEPS * panel_size_m;
	v_material = floor(v / PHASE_STEPS);
	v_local_pos = VERTEX;
	v_local_normal = NORMAL;
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_world_normal = (MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz;
}

float panel_hash(ivec3 c) {
	uint h = uint(c.x) * 73856093u ^ uint(c.y) * 19349663u ^ uint(c.z) * 83492791u;
	h = (h ^ (h >> 13u)) * 0x5BD1E995u;
	h ^= h >> 15u;
	return float(h & 0xFFFFFFu) / 16777216.0;
}

// Style.shade_panels: lines and tint on the lattice projected along the axis nearest the normal, faded to their mean once a panel
// is a few pixels across, so far hulls do not shimmer.
vec3 painted(int m, vec3 local_pos, vec3 local_normal, vec3 phase) {
	vec3 albedo = paint_albedo[m];
	if (paint_paneled[m] < 0.5) {
		return albedo;
	}
	vec3 p = local_pos + phase;
	vec3 n = abs(local_normal);
	int drop = (n.x >= n.y && n.x >= n.z) ? 0 : ((n.y >= n.z) ? 1 : 2);
	vec2 uv = (drop == 0 ? p.yz : (drop == 1 ? p.xz : p.xy)) / panel_size_m;
	vec2 cell = floor(uv);
	vec2 d = min(uv - cell, 1.0 - (uv - cell)) * panel_size_m;
	float edge = min(d.x, d.y);
	float half_width = 0.5 * panel_line_width_m;
	float blur = max(fwidth(edge), 1e-6);
	float line = 1.0 - smoothstep(half_width - blur, half_width + blur, edge);
	float tint = 1.0 + panel_tint_jitter * (2.0 * panel_hash(ivec3(ivec2(cell), drop)) - 1.0);
	float far = clamp(length(fwidth(uv)) * 4.0, 0.0, 1.0);
	float line_share = 2.0 * panel_line_width_m / panel_size_m;
	line = mix(line, line_share, far);
	tint = mix(tint, 1.0, far);
	return albedo * mix(tint, panel_line_darkness, line);
}

float omni_attenuation(float dist, float inv_range, float decay) {
	float nd = dist * inv_range;
	nd *= nd;
	nd *= nd;
	nd = max(1.0 - nd, 0.0);
	nd *= nd;
	return nd * pow(max(dist, 0.0001), -decay);
}

// GDGS's relight_factor with AO and confidence 1, as every generated hull's records have them.
vec3 relight(vec3 world_pos, vec3 world_normal) {
	vec3 direct = vec3(0.0);
	for (int i = 0; i < light_count; i++) {
		vec4 tint = light_colors[i];
		vec4 setup = light_params[i];
		int type = int(tint.a + 0.5);
		vec3 to_light = light_vectors[i];
		float attenuation = 1.0;
		if (type != 0) {
			vec3 relative = light_vectors[i] - world_pos;
			float dist = length(relative);
			if (dist < 1e-6) {
				continue;
			}
			to_light = relative / dist;
			attenuation = omni_attenuation(dist, setup.r, setup.g);
			if (type == 2) {
				float cone_cosine = max(dot(-to_light, light_spot_directions[i]), setup.b);
				float rim = (1.0 - cone_cosine) / max(1e-4, 1.0 - setup.b);
				attenuation *= 1.0 - pow(clamp(rim, 0.0, 1.0), setup.a);
			}
		}
		direct += tint.rgb * attenuation * max(dot(world_normal, to_light), 0.0);
	}
	return vec3(relight_unlit_level) + relight_light_gain * (vec3(relight_ambient) + direct);
}

vec3 srgb_to_linear(vec3 c) {
	c = max(c, vec3(0.0));
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), c));
}

// Varyings are passed in: a custom function may not read them.
vec3 paint_colour(bool front_facing, float material, vec3 local_pos, vec3 local_normal, vec3 phase, vec3 world_pos, vec3 world_normal) {
	int m = clamp(int(material + 0.5), 0, 31);
	vec3 colour = painted(m, local_pos, local_normal, phase);
	if (relight_on) {
		vec3 normal = normalize(world_normal) * (front_facing ? 1.0 : -1.0);
		colour *= relight(world_pos, normal);
	}
	return srgb_to_linear(colour);
}
