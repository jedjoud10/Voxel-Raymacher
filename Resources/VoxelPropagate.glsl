#version 460 core

layout(local_size_x = 4, local_size_y = 4, local_size_z = 4) in;
layout(rg32ui, binding = 0, location = 0) uniform uimage3D last_voxels;
layout(rg32ui, binding = 1, location = 1) uniform uimage3D next_voxels;

void main() {

	bool nice = false;

	for (int x = 0; x < 2; x++)
	{
		for (int y = 0; y < 2; y++)
		{
			for (int z = 0; z < 2; z++)
			{
				uvec2 dat = imageLoad(last_voxels, ivec3(gl_GlobalInvocationID * 2) + ivec3(x, y, z)).xy;
				nice = nice || (dat.x > 0.0 || dat.y > 0.0);
			}
		}
	}

	if (nice) {
		imageStore(next_voxels, ivec3(gl_GlobalInvocationID), uvec4(1));
	}
}