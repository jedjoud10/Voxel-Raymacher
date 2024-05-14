#version 460 core
#extension GL_ARB_bindless_texture : enable

layout(local_size_x = 4, local_size_y = 4, local_size_z = 4) in;
layout(rg32ui, binding = 0, location = 0, bindless_image) uniform uimage3D last_voxels;
layout(rg32ui, binding = 1, location = 1, bindless_image) uniform uimage3D next_voxels;

void main() {
	imageLoad(last_voxels, gl_GlobalInvocationID);

	for (int x = 0; x < 2; x++)
	{
		for (int y = 0; y < 2; y++)
		{
			for (int z = 0; z < 2; z++)
			{

			}
		}
	}
}