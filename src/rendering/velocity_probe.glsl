#[compute]
#version 450
// Reads the velocity buffer and the depth at a few pixels, so a test or the console can check the motion vectors the frame
// carries (M4-T38).

layout(local_size_x = 64, local_size_y = 1, local_size_z = 1) in;

layout(set = 0, binding = 0) uniform sampler2D velocity_tex;
layout(set = 0, binding = 1) uniform sampler2D depth_tex;
layout(set = 0, binding = 2, std430) restrict readonly buffer Points {
	ivec2 points[];
};
layout(set = 0, binding = 3, std430) restrict writeonly buffer Samples {
	vec4 samples[];
};

layout(push_constant, std430) uniform Params {
	ivec2 size;
	int count;
	int pad;
} params;

void main() {
	int i = int(gl_GlobalInvocationID.x);
	if (i >= params.count) {
		return;
	}
	ivec2 p = clamp(points[i], ivec2(0), params.size - 1);
	samples[i] = vec4(texelFetch(velocity_tex, p, 0).rg, texelFetch(depth_tex, p, 0).r, 1.0);
}
