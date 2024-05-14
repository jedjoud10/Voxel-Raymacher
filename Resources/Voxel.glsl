#version 460 core
#extension GL_ARB_gpu_shader_int64 : enable
#include Noise.glsl

layout(local_size_x = 4, local_size_y = 4, local_size_z = 4) in;
layout(rg32ui, binding = 0, location = 0) uniform uimage3D voxels;

bool density(vec3 pos) {
	float val = pos.y - 30;
	val += snoise(pos * 0.01 * vec3(1, 2, 1)) * 20;
	val += (1 - abs(snoise(pos * 0.02 * vec3(1, 0, 1)))) * 60 * clamp(snoise(pos * 0.001), 0, 1);
	val -= pow(cellular(pos.xz * 0.04).x + 0.1, 4) * 40;
	val = min(val, pos.y - 32);
	val = max(val, pos.y - 50);
	val -= (1 - abs(snoise(pos * 0.02 * vec3(1, 2, 1)))) * 20;
	val += abs(snoise(pos * 0.04 * vec3(1, 3, 1))) * 10;

	int amogus = 1 - clamp(int(round(val)), 0, 1);
	return amogus == 1;
}

void main() {
	uint64_t bitwise_data = uint64_t(0);
	int block_out = int(density(vec3(gl_GlobalInvocationID)));
	for (int x = 0; x < 4; x++)
	{
		for (int y = 0; y < 4; y++)
		{
			for (int z = 0; z < 4; z++)
			{
				vec3 pos = vec3(gl_GlobalInvocationID) + vec3(x, y, z) / 4.0;
				int block = int(density(pos));
				bitwise_data |= uint64_t(block) << uint64_t(x * 16 + y * 4 + z);
			}
		}
	}	

	uvec2 data = unpackUint2x32(bitwise_data);
	imageStore(voxels, ivec3(gl_GlobalInvocationID), uvec4(data, 0, 0));
}