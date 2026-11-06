#[compute]
#version 450
// Writes the camera's turn into the velocity buffer where nothing opaque was drawn (depth 0), so TAA reprojects the sky, the
// star points and the far dots instead of blending them with the wrong place (M4-T38). Godot leaves those pixels at zero.

layout(local_size_x = 16, local_size_y = 16, local_size_z = 1) in;

#define MAX_VIEWS 2
#include "godot/scene_data_inc.glsl"

layout(set = 0, binding = 0, std140) uniform SceneDataBlock {
	SceneData data;
	SceneData prev_data;
} scene;

layout(rg16f, set = 0, binding = 1) uniform restrict image2D velocity_image;
layout(set = 0, binding = 2) uniform sampler2D depth_tex;

layout(push_constant, std430) uniform Params {
	vec2 size;
	vec2 pad;
} params;

mat4 to_mat4(mat3x4 m) {
	return transpose(mat4(m[0], m[1], m[2], vec4(0.0, 0.0, 0.0, 1.0)));
}

// Where this pixel's view ray at infinity was last frame, minus where it is now, in uv units, without the TAA jitter
// (Godot's motion vector convention). The same sum as `motion_blur.glsl`'s.
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

void main() {
	ivec2 pos = ivec2(gl_GlobalInvocationID.xy);
	if (any(greaterThanEqual(vec2(pos), params.size))) {
		return;
	}
	if (texelFetch(depth_tex, pos, 0).r > 0.0) {
		return;
	}
	vec2 uv = (vec2(pos) + 0.5) / params.size;
	imageStore(velocity_image, pos, vec4(camera_turn_velocity(uv * 2.0 - 1.0), 0.0, 0.0));
}
