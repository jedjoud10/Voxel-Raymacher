#version 460 core
#extension GL_ARB_gpu_shader_int64 : enable
#include Noise.glsl

layout(local_size_x = 4, local_size_y = 4, local_size_z = 4) in;
layout(rgba32ui, binding = 0, location = 0) uniform uimage3D voxels;

float sdBox(vec3 p, vec3 b)
{
	vec3 q = abs(p) - b;
	return length(max(q, 0.0)) + min(max(q.x, max(q.y, q.z)), 0.0);
}

struct Voxel {
	bool enabled;
	int type;
};

Voxel voxel(vec3 pos) {
	Voxel data = Voxel(false, 0);
	float val = pos.y - 30;
	
	if (pos.x < 33.0) {
		val += sin(pos.z * 0.2)*3;
	}
	
	val += snoise(pos * 0.02 * vec3(1, 0.3, 1)) * 5;
	val += (1-cellular(pos.xz * 0.03).y) * 10 - 20;

	val -= (1 - abs(snoise(pos * 0.02 * vec3(1, 2, 1)))) * 2;

	val += abs(snoise(pos * 0.04 * vec3(1, 3, 1))) * 2;
	
	float boxu = sdBox(pos - vec3(32, 30, 64), vec3(100, 60, 2));
	val = min(val, boxu);

	float a = cellular(pos.xz * 0.1).x;
	if (a > 0.8 && pos.y < 90) {
		val = a * 12;
		val -= pos.y * 0.38;
	}

	data.enabled = val <= 0;

	//data.enabled = -fbmBillow(pos * 0.005, 4, 0.5, 2.0) * 150 + pos.y + 120 <= 0;
	return data;
}

float hash13(vec3 p3)
{
	p3 = fract(p3 * .1031);
	p3 += dot(p3, p3.zyx + 31.32);
	return fract((p3.x + p3.y) * p3.z);
}


void main() {
	uint64_t bitwise_data = uint64_t(0);
	for (int x = 0; x < 4; x++)
	{
		for (int y = 0; y < 4; y++)
		{
			for (int z = 0; z < 4; z++)
			{
				vec3 pos = vec3(gl_GlobalInvocationID) + vec3(x, y, z) / 4.0;
				int block = int(voxel(pos).enabled);

				bitwise_data |= uint64_t(block) << uint64_t(x * 16 + y * 4 + z);
				
			}
		}
	}

	/*
	if (block_out == 1) {
		bitwise_data = packUint2x32(uvec2(0xff00ff, 0x00ff00ff));
	}
	*/

	uvec2 data = unpackUint2x32(bitwise_data);
	imageStore(voxels, ivec3(gl_GlobalInvocationID), uvec4(data, 0, 0));
}