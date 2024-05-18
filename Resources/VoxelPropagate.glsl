#version 460 core

layout(local_size_x = 4, local_size_y = 4, local_size_z = 4) in;
layout(rg32ui, binding = 0, location = 0) uniform uimage3D last_voxels;
layout(rg32ui, binding = 1, location = 1) uniform uimage3D next_voxels;
layout(location = 2) uniform int propagate_bounds;

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
				uvec2 data = imageLoad(last_voxels, ivec3(gl_GlobalInvocationID * 2) + ivec3(x, y, z)).xy;
				bool has_matter = (data.x > 0.0 || data.y > 0.0);
				store_any = store_any || has_matter;

				if (has_matter) {
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