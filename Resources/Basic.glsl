#version 450 core

layout(local_size_x = 1, local_size_y = 1, local_size_z = 1) in;
layout(rgba8, binding = 0) uniform image2D image;

void main() {
	float x = gl_GlobalInvocationID.x / 800.0;
	float y = gl_GlobalInvocationID.y / 600.0;
	imageStore(image, ivec2(gl_GlobalInvocationID.xy), vec4(x, y, 0, 0));
}