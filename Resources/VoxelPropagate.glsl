#version 460 core
#extension GL_ARB_sparse_texture2 : enable
layout(local_size_x = 4, local_size_y = 4, local_size_z = 4) in;
layout(rgba32ui, binding = 0, location = 0) uniform uimage3D last_voxels;
layout(rgba32ui, binding = 1, location = 1) uniform uimage3D next_voxels;
layout(r32i, binding = 2, location = 2) uniform iimage3D sparse_helper;
layout(location = 3) uniform int propagate_bounds;
layout(location = 4) uniform int page_size;

void main() {
	bool store_any = false;
	uvec3 bounds_min = uvec3(100000);
	uvec3 bounds_max = uvec3(0);
	
	for (int x = 0; x < 2; x++)
	{
		for (int y = 0; y < 2; y++)
		{
			for (int z = 0; z < 2; z++)
			{
				ivec3 pos = ivec3(gl_GlobalInvocationID * 2) + ivec3(x, y, z);
				/*
				uvec4 dataa = uvec4(0);
				int code = sparseImageLoadARB(last_voxels, pos, dataa);
				uvec2 data = dataa.xy;
				*/
				uvec2 data = imageLoad(last_voxels, pos).xy;
				bool has_matter = (data.x > 0.0 || data.y > 0.0);
				bool invis = false;

				if (propagate_bounds == 1) {
					invis = (data.x == 0 && data.y == 0);
				}
				else {
					invis = (data.x == 0 && data.y == 0) || (data.x == 0xffffffff && data.y == 0xffffffff);
				}

				if (has_matter) {
					store_any = true;
					

					if (propagate_bounds == 1) {
						// convert the data (stored as bounds compared to mini-voxels)
						// propagate these bounds to the current bounds
						uint mint = data.x;
						uint mauint = data.y;
						uvec3 last_min = uvec3(mint & 0x3FF, (mint >> 10) & 0x3FF, (mint >> 20) & 0x3FF);
						uvec3 last_max = uvec3(mauint & 0x3FF, (mauint >> 10) & 0x3FF, (mauint >> 20) & 0x3FF);
						bounds_min = min(bounds_min, last_min);
						bounds_max = max(bounds_max, last_max);
					}
					else {
						// if we're the first level to be propagated, make sure to store the min max bounds of the high res level
						// that way we can propagate the bound data up 
						uvec3 position = uvec3(gl_GlobalInvocationID * 2) + uvec3(x, y, z);
						bounds_min = min(bounds_min, position);
						bounds_max = max(bounds_max, position);
					}
				}
				else {
					
				}

				if (invis) {
					imageAtomicAdd(sparse_helper, pos / page_size, 1);
				}
			}
		}
	}

	if (store_any) {
		// convert the bounds back to uints
		uint minimum = bounds_min.x | bounds_min.y << 10 | bounds_min.z << 20;
		uint maximum = bounds_max.x | bounds_max.y << 10 | bounds_max.z << 20;
		imageStore(next_voxels, ivec3(gl_GlobalInvocationID), uvec4(minimum, maximum, 0, 0));
	}
}