
#version 460
#extension GL_ARB_gpu_shader_int64 : enable
layout(local_size_x = 32, local_size_y = 32, local_size_z = 1) in;
layout(rgba8, binding = 0, location = 0) uniform image2D image;
layout(location = 1) uniform vec2 resolution;
layout(location = 2) uniform mat4 view_matrix;
layout(location = 3) uniform mat4 proj_matrix;
layout(location = 4) uniform vec3 position;
layout(location = 5) uniform int max_mip_iter;
layout(location = 6) uniform int max_iters;
layout(location = 7) uniform int map_size;
layout(location = 8) uniform int debug_view;
layout(location = 9) uniform int max_reflections;
layout(location = 10) uniform int use_sub_voxels;
layout(location = 11) uniform float reflection_roughness;
layout(location = 12) uniform vec3 light_dir;
layout(location = 13) uniform int use_octree_ray_caching;
layout(location = 14) uniform int use_prop_aabb_bounds;
layout(rg32ui, binding = 1) uniform uimage3D voxels[7];
layout(binding = 2) uniform samplerCube skybox;

#include Hashes.glsl
#include Lighting.glsl

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
	return packUint2x32(imageLoad(voxels[0], tex_point).xy);
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
		uvec2 data = imageLoad(voxels[j], tex_point).xy;
		if (j > 0 && use_prop_aabb_bounds == 1) {
			uint mint = data.x;
			uint mauint = data.y;
			uvec3 last_min = uvec3(mint & 0x3FF, (mint >> 10) & 0x3FF, (mint >> 20) & 0x3FF);
			uvec3 last_max = uvec3(mauint & 0x3FF, (mauint >> 10) & 0x3FF, (mauint >> 20) & 0x3FF);
			vec2 bounds_distances = intersection(pos, ray_dir, inv_dir, vec3(last_min), vec3(last_max+1));
			
			// check if we hit the aabb
			float bounds_closest_dist = bounds_distances.x;
			if (bounds_distances.y > bounds_distances.x) {
				// check if we're outside the aabb 
				if (bounds_distances.x > 0) {
					voxel_distance = bounds_closest_dist;
					min_level_reached += 1;
					hit = false;
					break;
				}
			}
			else {
				// if we didn't hit the aabb then we don't need to iterate all the lower levels, skip the whole node lel
				voxel_distance = inside_node_closest_dist;
				min_level_reached += 1;
				hit = false;
				break;
			}
		}

		// skip over big areas!!!
		// FIXME: For some reason on my iGPU all(data == uvec2(0)) doesn't compile :3
		if (data.x == 0 && data.y == 0) {
			// calculate child offset relative to parent
			/*
			vec3 center = grid_level_point;
			vec3 child_max = grid_level_point + vec3(scale_factor);
			vec3 center = (child_min + child_max) / 2;
			*/
			vec3 center = grid_level_point + vec3(scale_factor) * 0.5;

			// get parent node center
			vec3 parent_center = floor(pos / (scale_factor * 2)) * scale_factor * 2 + vec3(scale_factor);
			/*
			vec3 parent_max = parent_min + vec3(scale_factor * 2);
			vec3 parent_center = (parent_min + parent_max) / 2;
			*/

			// get local offset dir
			vec3 local_offset_dir = parent_center - center;
			//normal += local_offset_dir;

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
			//min_level_reached = min(min_level_reached, j);

			break;
		}
	}
}

// trace WITHIN the voxel!!! (I love bitwise ops)
void trace_internal(inout vec3 pos, vec3 ray_dir, vec3 inv_dir, inout float voxel_distance, inout bool hit, inout float bit_fetches) {
	uint64_t inner_bits = get_binary_data(pos);
	vec3 min_pos = floor(pos);
	vec3 max_pos = ceil(pos);

	//vec3 intputu = floor(pos * 4) - floor(pos) * 4;
	for (int i = 0; i < 6; i++) {
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

void main() {
	// remap coords to ndc range (-1, 1)
	vec2 coords = gl_GlobalInvocationID.xy / resolution;
	coords *= 2.0;
	coords -= 1.0;

	// apply projection transformations for ray dir
	vec3 ray_dir = (view_matrix * proj_matrix * vec4(coords, 1, 0)).xyz;
	ray_dir = normalize(ray_dir);
	vec3 inv_dir = 1.0 / (ray_dir + vec3(0.0001));

	// ray marching stuff
	vec3 pos = position;
	bool hit = false;

	// vars for default view
	vec3 color = vec3(0.0);
	vec3 normal = vec3(0);
	uint level_cache = 8;

	// debug stuffs
	float total_iterations = 0.0;
	float total_mip_map_iterations = 0.0;
	float total_inner_bit_fetches = 0.0;
	float min_level_reached = 0;
	int reflections_iters = 0;
	float factor = 1.0;

	for (int i = 0; i < max_iters; i++) {
		bool temp_hit = true;
		total_iterations += 1;
		float voxel_distance = 0.0;

		// we know the map isn't *that* big
		if (any(greaterThan(pos, vec3(map_size))) || any(lessThan(pos, vec3(0)))) {
			break;
		}

		// recursively go through the mip chain
		recurse(pos, ray_dir, inv_dir, temp_hit, voxel_distance, min_level_reached, level_cache);

		// gotta add a small offset since we'd be on the very face of the voxel
		pos += ray_dir * max(0.001, voxel_distance);

		// do all of our lighting calculations here
		if (temp_hit) {
			temp_hit = false;

			if (use_sub_voxels == 1) {
				trace_internal(pos, ray_dir, inv_dir, voxel_distance, temp_hit, total_inner_bit_fetches);
			}

			if (temp_hit || use_sub_voxels == 0) {
				/*
				if (pos.x < 33) {
					if (reflections_iters < max_reflections) {
						//ray_dir = refract(ray_dir, normal, 1.4);
						ray_dir = reflect(ray_dir, normal);
						ray_dir += (hash32(coords * 31.5143 * vec2(12.3241, 2.341)) - 0.5) * reflection_roughness;
						ray_dir = normalize(ray_dir);
						inv_dir = 1.0 / (ray_dir + vec3(0.0001));
						level_cache = 0;
						factor /= 2.0;

						pos += ray_dir * 0.01;
						reflections_iters += 1;
						continue;
					}
					else {
						color = sky(ray_dir);
						hit = true;
						break;
					}
				}
				*/

				// Find normal using another intersection test
				int min_side_hit = 0;
				int max_side_hit = 0;
				pos += ray_dir * 0.01;
				float scale = (use_sub_voxels == 1) ? 0.25 : 1;
				vec3 grid_level_point = floor(pos / scale) * scale;
				intersection(pos, -ray_dir, -inv_dir, grid_level_point, grid_level_point + vec3(scale), min_side_hit, max_side_hit);
				normal = get_internal_box_normal(max_side_hit, ray_dir);

				color = lighting(pos, normal, ray_dir);
				hit = true;
				break;
			}
		}
	}

	// ACTUAL GAME VIEW
	if (debug_view == 0) {
		if (!hit) {
			color = sky(ray_dir);
		}
		color /= pow(2, max(reflections_iters-1, 0));
		//color *= pow((1 - factor), 0.5) * 0.4 + 0.6;
	}

	else if (debug_view == 1) {
		int min_dir = 0;
		int max_dir = 0;
		vec2 dists = intersection(pos, ray_dir, inv_dir, vec3(0), vec3(10), min_dir, max_dir);
		//color = get_internal_box_normal(max_dir, ray_dir);
		if (dists.y > dists.x && dists.x > 0) {
			color = vec3(dists.x);
		}
		else {
			color = vec3(0.1);
		}
		//color = vec3(dists.y - dists.x);
	}
	else if (debug_view == 2) {
		color = vec3(total_iterations / float(max_iters));
	}
	else if (debug_view == 3) {
		color = vec3(min_level_reached / float(100));
	}
	else if (debug_view == 4) {
		color = vec3(total_inner_bit_fetches / float(60));
	}
	else if (debug_view == 5) {
		color = vec3(float(reflections_iters) / float(max_reflections));
	}
	else if (debug_view == 6) {
		normal = normalize(normal);
		color = normal;		
	}
	else if (debug_view == 7) {
		color = pos;
	}
	else if (debug_view == 8) {
		color = pos - floor(pos);
	}
	else if (debug_view == 9) {
		color = pos * 4 - floor(pos * 4);
	}

	// store the value in the image that we will blit
	imageStore(image, ivec2(gl_GlobalInvocationID.xy), vec4(color, 0));
}