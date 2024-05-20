
/*
for (int d = 0; d < 3; d++) {
	bool sign = sign(inv_dir[d]) == 1.0;
	float bmin = vertices[int(sign)][d];
	float bmax = vertices[int(!sign)][d];

	float dmin = (bmin - position[d]) * inv_dir[d];
	float dmax = (bmax - position[d]) * inv_dir[d];

	tmin = max(dmin, tmin);
	tmax = min(dmax, tmax);
}
*/
// 3d cube vs ray intersection that allows us to calculate closest distance to face of cube
// https://tavianator.com/2022/ray_box_boundary.html :3
vec2 intersection(vec3 pos, vec3 dir, vec3 inv_dir, vec3 smol, vec3 beig) {
	float tmin = 0.0, tmax = 1000000.0;
	for (int d = 0; d < 3; d++) {
		float t1 = (smol[d] - pos[d]) * inv_dir[d];
		float t2 = (beig[d] - pos[d]) * inv_dir[d];

		tmin = max(tmin, min(t1, t2));
		tmax = min(tmax, max(t1, t2));
	}

	return vec2(tmin, tmax);
}

// same one but with directions
vec2 intersection(vec3 pos, vec3 dir, vec3 inv_dir, vec3 smol, vec3 beig, inout int max_dir, inout int min_dir) {
	float tmin = 0.0, tmax = 1000000.0;
	for (int d = 0; d < 3; d++) {
		float t1 = (smol[d] - pos[d]) * inv_dir[d];
		float t2 = (beig[d] - pos[d]) * inv_dir[d];

		float aaa = min(t1, t2);
		float eee = max(t1, t2);
		if (aaa > tmin) {
			tmin = aaa;
			max_dir = d;
		}

		if (eee < tmax) {
			tmax = eee;
			min_dir = d;
		}
	}

	return vec2(tmin, tmax);
}

// fetches the 64 bit 4x4x4 sub-voxel volume for one voxel
uint64_t get_binary_data(vec3 pos) {
	ivec3 tex_point = ivec3(floor(pos));
	return packUint2x32(texelFetch(voxels, tex_point, 0).xy);
	//return packUint2x32(imageLoad(voxels[0], tex_point).xy);
}

// check if the sub-voxel at one position is set to true
bool check_inner_bits(vec3 pos, uint64_t bits) {
	uvec3 internal = uvec3(floor(pos * 4) - floor(pos) * 4);
	uint index = internal.x * 16 + internal.y * 4 + internal.z;
	return (bits & (uint64_t(1) << index)) != uint64_t(0);
}

// given a hit side of a box (internally) get the normal
vec3 get_internal_box_normal(int side, vec3 ray_dir) {
	if (side == 0) {
		return vec3(ray_dir.x > 0.0 ? -1.0 : 1.0, 0, 0);
	}
	else if (side == 1) {
		return vec3(0, ray_dir.y > 0.0 ? -1.0 : 1.0, 0);
	}
	else if (side == 2) {
		return vec3(0, 0, ray_dir.z > 0.0 ? -1.0 : 1.0);
	}

	return vec3(0);
}

// recrusviely go through the mip chain
void recurse(vec3 pos, vec3 ray_dir, vec3 inv_dir, inout bool hit, inout float voxel_distance, inout float min_level_reached, inout uint level_cache) {
	// recursively iterate through the mip maps (starting at the highest level)
	// TODO: don't start iterating at the highest level if we know what direction the ray is going and what the current child history is
	// basically, we can avoid fetching the low-res textures if we are being smart

	// check each level for big empty spaces that we can skip over

	// if bit set to 1, means that we can skip the level
	// must find the index of the first bit set to 0 (which corresponds to level)
	// level 0: 512*512*512
	// level 1: 256*256*256
	// level 2: 128*128*128
	int inv_start_level = min(findLSB(level_cache), max_mip_iter);

	if (use_octree_ray_caching == 0) {
		inv_start_level = max_mip_iter;
	}

	for (int j = inv_start_level; j >= 0; j--) {
		// use the mip maps themselves as an acceleration structure
		float scale_factor = pow(2, j);
		vec3 grid_level_point = floor(pos / scale_factor) * scale_factor;
		vec3 bounds_min = grid_level_point;
		vec3 bounds_max = bounds_min + vec3(scale_factor);

		// calculate temporary distance to the end of the current cell for the current mipmap
		vec2 distances = intersection(pos, ray_dir, inv_dir, bounds_min, bounds_max);
		float inside_node_closest_dist = distances.y;

		// instead of using the bounds directly, use the propagated aabb for tighter culling
		ivec3 tex_point = ivec3(floor(pos / scale_factor));


		// I LOVE SPARSE TEXTURES!!!!
		int page_size = 16;

		// pos means full
		// neg means empty
		int sparse_code = imageLoad(sparse_helper, tex_point / page_size).x;
		if (sparse_code == 4096) {
			voxel_distance = inside_node_closest_dist;
			hit = false;
			return;
		}
		/*
		if (sparse_code == -4096) {
			voxel_distance = inside_node_closest_dist;
			hit = false;
			return;
		}
		else if (sparse_code == 4096) {
			voxel_distance = 10000;
			hit = true;
			min_level_reached = 0.0;
			return;
		}
		*/


		//uvec2 data = imageLoad(voxels[j], tex_point).xy
		uvec2 data = texelFetch(voxels, tex_point, j).xy;
		if (j > 0 && use_prop_aabb_bounds == 1) {
			uint mint = data.x;
			uint mauint = data.y;
			uvec3 last_min = uvec3(mint & 0x3FF, (mint >> 10) & 0x3FF, (mint >> 20) & 0x3FF);
			uvec3 last_max = uvec3(mauint & 0x3FF, (mauint >> 10) & 0x3FF, (mauint >> 20) & 0x3FF);
			vec2 bounds_distances = intersection(pos, ray_dir, inv_dir, vec3(last_min), vec3(last_max + 1));

			// check if we hit the aabb
			float bounds_closest_dist = bounds_distances.x;
			if (bounds_distances.y > bounds_distances.x) {
				// check if we're outside the aabb 
				if (bounds_distances.x > 0) {
					voxel_distance = bounds_closest_dist;
					hit = false;
					return;
				}
			}
			else {
				// if we didn't hit the aabb then we don't need to iterate all the lower levels, skip the whole node lel
				voxel_distance = inside_node_closest_dist;
				hit = false;
				return;
			}
		}

		// skip over big areas!!!
		// FIXME: For some reason on my iGPU all(data == uvec2(0)) doesn't compile :3
		if (data.x == 0 && data.y == 0) {
			// calculate child offset relative to parent
			vec3 center = grid_level_point + vec3(scale_factor) * 0.5;

			// get parent node center
			vec3 parent_center = floor(pos / (scale_factor * 2)) * scale_factor * 2 + vec3(scale_factor);

			// get local offset dir
			vec3 local_offset_dir = parent_center - center;

			// if dot product between ray_dir and child offset local to parent is negative it means that the next time we iterate we can start at the current level instead of the highest level
			uint bwuh = uint(1) << uint(j);
			if (dot(local_offset_dir, ray_dir) < 0.0) {
				level_cache |= bwuh;
			}
			else {
				level_cache &= ~bwuh;
			}

			voxel_distance = inside_node_closest_dist;
			hit = false;
			min_level_reached = min(min_level_reached, j);

			return;
		}
	}
}

// trace WITHIN the voxel!!! (I love bitwise ops)
void trace_internal(inout vec3 pos, vec3 ray_dir, vec3 inv_dir, inout float voxel_distance, inout bool hit, inout float bit_fetches) {
	uint64_t inner_bits = get_binary_data(pos);
	vec3 min_pos = floor(pos);
	vec3 max_pos = ceil(pos);

	//vec3 intputu = floor(pos * 4) - floor(pos) * 4;
	for (int i = 0; i < max_sub_voxel_iter; i++) {
		vec3 grid_level_point = floor(pos / 0.25) * 0.25;
		bit_fetches += 1.0;
		int min_side_hit = 0;
		int max_side_hit = 0;
		vec2 distances = intersection(pos, ray_dir, inv_dir, grid_level_point, grid_level_point + vec3(0.25), min_side_hit, max_side_hit);
		voxel_distance = distances.y - distances.x;

		if (check_inner_bits(pos, inner_bits)) {
			hit = true;
			return;
		}

		pos += ray_dir * max(0.001, voxel_distance);
		if (any(greaterThanEqual(pos, max_pos)) || any(lessThanEqual(pos, min_pos))) {
			break;
		}
	}

	/*
	vec3 outputu = floor(pos * 4) - floor(pos) * 4;

	if (outputu.x == intputu.x && outputu.y == intputu.y) {
		bit_fetches += 1.0;
	}
	*/

	hit = false;
}