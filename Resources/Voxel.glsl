#version 460 core
#extension GL_ARB_gpu_shader_int64 : enable
#include Noise.glsl

layout(local_size_x = 4, local_size_y = 4, local_size_z = 4) in;
layout(rg32ui, binding = 0, location = 0) uniform uimage3D voxels;

float sdBox(vec3 p, vec3 b)
{
	vec3 q = abs(p) - b;
	return length(max(q, 0.0)) + min(max(q.x, max(q.y, q.z)), 0.0);
}

bool density(vec3 pos) {
	float val = pos.y - 30;
	
	/*
	if (pos.x < 33.0) {
		val += sin(pos.z * 0.2)*3;
	}
	*/
	val += snoise(pos * 0.02 * vec3(1, 0.3, 1)) * 10;
	val += (1-cellular(pos.xz * 0.03).y) * 20;
	val += snoise(pos * 0.04 * vec3(1, 4, 1)) * 15 * clamp(snoise(pos * 0.01) * 10, 0, 1);
	val = min(val-10, pos.y - 32);
	val += snoise(pos * 0.3) * 0.2;
	val += clamp(snoise(pos * 0.01) * 30 - 10, 0, 15) * 3;
	
	//val = max(val, pos.y - 50);
	//val -= (1 - abs(snoise(pos * 0.02 * vec3(1, 2, 1)))) * 20;
	//val += abs(snoise(pos * 0.04 * vec3(1, 3, 1))) * 10;
	//val = min(val, pos.y - 60);
	
	/*
	float boxu = sdBox(pos - vec3(32, 30, 64), vec3(10, 6, 2));
	val = min(val, boxu);
	*/

	return val <= 0;
}

float hash13(vec3 p3)
{
	p3 = fract(p3 * .1031);
	p3 += dot(p3, p3.zyx + 31.32);
	return fract((p3.x + p3.y) * p3.z);
}


void main() {
	uint64_t bitwise_data = uint64_t(0);
	//int block_out = int(density(vec3(gl_GlobalInvocationID)));
	for (int x = 0; x < 4; x++)
	{
		for (int y = 0; y < 4; y++)
		{
			for (int z = 0; z < 4; z++)
			{
				vec3 pos = vec3(gl_GlobalInvocationID) + vec3(x, y, z) / 4.0;
				int block = int(density(pos));

				bitwise_data |= uint64_t(block) << uint64_t(x * 16 + y * 4 + z);
				
				/*
				bitwise_data |= uint64_t(block_out) << uint64_t(x * 16 + y * 4 + z);
				if (hash13(pos) > 0.5) {
				}
				*/
			}
		}
	}	

	uvec2 data = unpackUint2x32(bitwise_data);
	imageStore(voxels, ivec3(gl_GlobalInvocationID), uvec4(data, 0, 0));
}