#[compute]
#version 450
// Motion blur for fast turns. Hulls write depth and blur by the velocity buffer; the sky, the star points and anything else
// that writes no depth (depth 0) blur by how far the camera turned since the last frame, which the buffer does not hold for them.
// Under FSR 2.2 Godot writes vectors only for what moved and marks the rest (-1, -1) for the upscaler to work out from depth
// (M7-T46); those pixels blur by the camera's own motion, worked out the same way.

layout(local_size_x = 16, local_size_y = 16, local_size_z = 1) in;

#define MAX_VIEWS 2
#include "godot/scene_data_inc.glsl"

layout(set = 0, binding = 0, std140) uniform SceneDataBlock {
	SceneData data;
	SceneData prev_data;
} scene;

// The blurred frame goes to a scratch image; `motion_blur_copy.glsl` puts it back over the colour buffer.
layout(rgba16f, set = 0, binding = 1) uniform restrict writeonly image2D scratch_image;
layout(set = 0, binding = 2) uniform sampler2D depth_tex;
layout(set = 0, binding = 3) uniform sampler2D velocity_tex;
layout(set = 0, binding = 4) uniform sampler2D color_tex;

layout(push_constant, std430) uniform Params {
	float strength; // fraction of the frame's motion that is smeared (0-1)
	float max_blur_px; // longest smear
	vec2 size; // internal resolution
} params;

const int MAX_SAMPLES = 48;

mat4 to_mat4(mat3x4 m) {
	return transpose(mat4(m[0], m[1], m[2], vec4(0.0, 0.0, 0.0, 1.0)));
}

// Interleaved gradient noise: breaks the sample banding without a texture.
float noise(vec2 p) {
	return fract(52.9829189 * fract(dot(p, vec2(0.06711056, 0.00583715))));
}

// How far this pixel's view ray moved on screen since the last frame, in uv units, for a ray at infinity, without TAA's
// jitter (so a still camera under TAA does not blur the sky). The same sum `sky_velocity.glsl` writes for TAA (M4-T38).
vec2 camera_turn_velocity(vec2 ndc) {
	vec4 near_point = scene.data.inv_projection_matrix * vec4(ndc, 1.0, 1.0);
	vec3 view_dir = normalize(near_point.xyz / near_point.w);
	vec3 world_dir = mat3(to_mat4(scene.data.inv_view_matrix)) * view_dir;
	vec3 prev_view_dir = mat3(to_mat4(scene.prev_data.view_matrix)) * world_dir;
	vec4 prev_clip = scene.prev_data.projection_matrix * vec4(prev_view_dir, 0.0);
	if (prev_clip.w <= 0.0) {
		return vec2(0.0);
	}
	vec2 prev_ndc = prev_clip.xy / prev_clip.w - scene.prev_data.taa_jitter;
	return (prev_ndc - (ndc - scene.data.taa_jitter)) * 0.5;
}

// Godot's mark for "this did not move, work its vector out from depth" (a temporal upscaler's motion pass, M7-T46).
bool is_derived_mark(vec2 velocity) {
	return all(lessThanEqual(velocity, vec2(-1.0)));
}

// The motion vector of a still point at this pixel and depth, from the camera's move since the last frame, in the velocity
// buffer's convention (uv units, last frame's place minus this one's, without the jitter).
vec2 still_point_velocity(vec2 ndc, float depth) {
	vec4 view = scene.data.inv_projection_matrix * vec4(ndc, depth, 1.0);
	vec4 world = to_mat4(scene.data.inv_view_matrix) * vec4(view.xyz / view.w, 1.0);
	vec4 prev_clip = scene.prev_data.projection_matrix * (to_mat4(scene.prev_data.view_matrix) * world);
	if (prev_clip.w <= 0.0) {
		return vec2(0.0);
	}
	vec2 prev_ndc = prev_clip.xy / prev_clip.w - scene.prev_data.taa_jitter;
	return (prev_ndc - (ndc - scene.data.taa_jitter)) * 0.5;
}

void main() {
	ivec2 pos = ivec2(gl_GlobalInvocationID.xy);
	if (any(greaterThanEqual(vec2(pos), params.size))) {
		return;
	}
	vec2 uv = (vec2(pos) + 0.5) / params.size;
	vec4 centre = texelFetch(color_tex, pos, 0);

	float depth = texelFetch(depth_tex, pos, 0).r;
	bool is_sky = depth <= 0.0;
	vec2 velocity = is_sky ? camera_turn_velocity(uv * 2.0 - 1.0) : texelFetch(velocity_tex, pos, 0).rg;
	if (!is_sky && is_derived_mark(velocity)) {
		velocity = still_point_velocity(uv * 2.0 - 1.0, depth);
	}

	// Velocity is where the pixel was last frame; the smear runs both ways round now (a half-open shutter).
	vec2 smear_px = velocity * params.size * params.strength;
	float len_px = length(smear_px);
	if (len_px < 0.75) {
		imageStore(scratch_image, pos, centre);
		return;
	}
	if (len_px > params.max_blur_px) {
		smear_px *= params.max_blur_px / len_px;
		len_px = params.max_blur_px;
	}
	vec2 smear_uv = smear_px / params.size;

	int count = clamp(int(ceil(len_px * 0.5)), 3, MAX_SAMPLES);
	float jitter = noise(vec2(pos)) - 0.5;
	vec3 sum = vec3(0.0);
	for (int i = 0; i < count; i++) {
		float t = (float(i) + 0.5 + jitter) / float(count) - 0.5;
		vec2 sample_uv = uv + smear_uv * t;
		ivec2 sample_pos = ivec2(sample_uv * params.size);
		// A sky pixel never borrows from a hull, or a hull's paint would be dragged across the stars.
		if (is_sky && texelFetch(depth_tex, clamp(sample_pos, ivec2(0), ivec2(params.size) - 1), 0).r > 0.0) {
			sum += centre.rgb;
		} else {
			sum += textureLod(color_tex, sample_uv, 0.0).rgb;
		}
	}
	imageStore(scratch_image, pos, vec4(sum / float(count), centre.a));
}
