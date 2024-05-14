#version 460 core
#extension GL_ARB_bindless_texture : enable
#include Noise.glsl

layout(local_size_x = 4, local_size_y = 4, local_size_z = 4) in;
layout(rg32ui, binding = 0, location = 0, bindless_image) uniform uimage3D voxels;

void main() {
	vec3 pos = vec3(gl_GlobalInvocationID);
	float val = pos.y - 30;
	val += snoise(pos * 0.01 * vec3(1, 2, 1)) * 20;
	val += (1 - abs(snoise(pos * 0.02 * vec3(1, 0, 1)))) * 60 * clamp(snoise(pos * 0.001), 0, 1);
	val -= pow(cellular(pos.xz * 0.04).x + 0.1, 4) * 40;
	val = min(val, pos.y - 32);
	val = max(val, pos.y - 50);
	val -= (1-abs(snoise(pos * 0.02 * vec3(1, 2, 1)))) * 20;
}