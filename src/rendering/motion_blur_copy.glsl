#[compute]
#version 450
// Puts the blurred scratch frame back over the colour buffer (the second half of `motion_blur.glsl`).

layout(local_size_x = 16, local_size_y = 16, local_size_z = 1) in;

layout(rgba16f, set = 0, binding = 0) uniform restrict writeonly image2D color_image;
layout(set = 0, binding = 1) uniform sampler2D scratch_tex;

layout(push_constant, std430) uniform Params {
	vec2 size;
	vec2 pad;
} params;

void main() {
	ivec2 pos = ivec2(gl_GlobalInvocationID.xy);
	if (any(greaterThanEqual(vec2(pos), params.size))) {
		return;
	}
	imageStore(color_image, pos, texelFetch(scratch_tex, pos, 0));
}
