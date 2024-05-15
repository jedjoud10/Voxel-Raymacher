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
layout(rg32ui, binding = 1) uniform uimage3D voxels[7];
layout(binding = 2) uniform samplerCube skybox;

#include Hashes.glsl
#include Lighting.glsl

// 3d cube vs ray intersection that allows us to calculate closest distance to face of cube
vec2 intersection(vec3 pos, vec3 dir, vec3 smol, vec3 beig, inout int max_dir, inout int min_dir) {
	float tmin = 0.0, tmax = 1000000.0;
	vec3 dir_inv = 1.0 / (dir + vec3(0.001));

	for (int d = 0; d < 3; d++) {
		float t1 = (smol[d] - pos[d]) * dir_inv[d];
		float t2 = (beig[d] - pos[d]) * dir_inv[d];

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

	/*
	for (int d = 0; d < 3; d++) {
		bool sign = sign(dir_inv[d]) == 1.0;
		float bmin = vertices[int(sign)][d];
		float bmax = vertices[int(!sign)][d];

		float dmin = (bmin - position[d]) * dir_inv[d];
		float dmax = (bmax - position[d]) * dir_inv[d];

		tmin = max(dmin, tmin);
		tmax = min(dmax, tmax);
	}
	*/

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
void recurse(vec3 pos, vec3 ray_dir, inout bool hit, inout float voxel_distance, inout float min_level_reached, inout vec3 normal) {
	// recursively iterate through the mip maps (starting at the highest level)
	// check each level for big empty spaces that we can skip over
	for (int j = max_mip_iter; j >= 0; j--) {
		// use the mip maps themselves as an acceleration structure
		float scale_factor = pow(2, j);
		vec3 grid_level_point = floor(pos / scale_factor) * scale_factor;

		// calculate temporary distance to the end of the current cell for the current mipmap
		int a = 0;
		int b = 0;
		vec2 distances = intersection(pos, ray_dir, grid_level_point, grid_level_point + vec3(scale_factor), a, b);
		float t_voxel_distance = distances.y - distances.x;

		// modulo scale for repeating the maps
		vec3 modulo_scale = vec3(map_size / scale_factor, 100000, map_size / scale_factor);
		ivec3 tex_point = ivec3(floor(mod(pos / scale_factor, modulo_scale)));

		if (imageLoad(voxels[j], tex_point).x == 0) {
			voxel_distance = t_voxel_distance;
			hit = false;
			min_level_reached = min(min_level_reached, j);

			int min_side_hit = 0;
			int max_side_hit = 0;
			intersection(pos, ray_dir, grid_level_point, grid_level_point + vec3(scale_factor), min_side_hit, max_side_hit);
			normal = get_internal_box_normal(max_side_hit, ray_dir);

			break;
		}
	}
}

// trace WITHIN the voxel!!! (I love bitwise ops)
void trace_internal(inout vec3 pos, vec3 ray_dir, inout float voxel_distance, inout bool hit, inout vec3 normal, inout float bit_fetches) {
	uint64_t inner_bits = get_binary_data(pos);
	vec3 min_pos = floor(pos);
	vec3 max_pos = ceil(pos);

	for (int i = 0; i < 6; i++) {
		vec3 grid_level_point = floor(pos / 0.25) * 0.25;
		bit_fetches += 1.0;
		int min_side_hit = 0;
		int max_side_hit = 0;
		vec2 distances = intersection(pos, ray_dir, grid_level_point, grid_level_point + vec3(0.25), min_side_hit, max_side_hit);
		voxel_distance = distances.y - distances.x;

		if (check_inner_bits(pos, inner_bits)) {
			// TODO: Find a way to avoid an intersection thingy here
			//pos = clamp(pos, grid_level_point + 0.1, vec3(0.24));
			intersection(pos, -ray_dir, grid_level_point, grid_level_point + vec3(0.25), min_side_hit, max_side_hit);

			// TODO: Fix weird normals on sub voxel faces
			normal = get_internal_box_normal(max_side_hit, ray_dir);
			hit = true;
			return;
		}

		pos += ray_dir * max(0.001, voxel_distance);
		if (any(greaterThanEqual(pos, max_pos)) || any(lessThanEqual(pos, min_pos))) {
			break;
		}
	}

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

	// ray marching stuff
	vec3 pos = position;
	bool hit = false;

	// vars for default view
	vec3 color = vec3(0.0);
	vec3 normal = vec3(0);

	// debug stuffs
	float total_iterations = 0.0;
	float total_mip_map_iterations = 0.0;
	float total_inner_bit_fetches = 0.0;
	float min_level_reached = 1000;
	int reflections_iters = 0;

	for (int i = 0; i < max_iters; i++) {
		bool temp_hit = true;
		total_iterations += 1;
		float voxel_distance = 0.0;

		// we know the map isn't *that* big
		if (any(greaterThan(pos, vec3(map_size))) || any(lessThan(pos, vec3(0)))) {
			break;
		}

		// recursively go through the mip chain
		recurse(pos, ray_dir, temp_hit, voxel_distance, min_level_reached, normal);

		// gotta add a small offset since we'd be on the very face of the voxel
		pos += ray_dir * (0.001 + voxel_distance);
		
		// do all of our lighting calculations here
		if (temp_hit) {
			temp_hit = false;

			if (use_sub_voxels == 1) {
				trace_internal(pos, ray_dir, voxel_distance, temp_hit, normal, total_inner_bit_fetches);
			}

			if (temp_hit || use_sub_voxels == 0) {
				if (pos.x < 33) {
					if (reflections_iters < max_reflections) {
						//ray_dir = refract(ray_dir, normal, 1.4);
						ray_dir = reflect(ray_dir, normal);
						ray_dir += (hash32(coords * 31.5143 * vec2(12.3241, 2.341)) - 0.5) * reflection_roughness;
						ray_dir = normalize(ray_dir);

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

				color = lighting(pos, normal, ray_dir);
				hit = true;
				break;
			}
		}
	}

	// ACTUAL GAME VIEW
	if (debug_view == 0) {	
		float factor = float(reflections_iters) / float(max(max_reflections, 1));

		if (!hit) {
			color = sky(ray_dir);
		}

		color *= (1 - factor) * 0.2 + 0.8;
	}
	
	else if (debug_view == 1) {
		int min_dir = 0;
		int max_dir = 0;
		vec2 dists = intersection(pos, ray_dir, vec3(0), vec3(map_size), min_dir, max_dir);
		color = get_internal_box_normal(max_dir, ray_dir);
	}
	else if (debug_view == 2) {
		color = vec3(total_iterations / float(max_iters));
	}
	else if (debug_view == 3) {
		color = vec3(min_level_reached / float(max_mip_iter));
	}
	else if (debug_view == 4) {
		color = vec3(total_inner_bit_fetches / float(20));
	}
	else if (debug_view == 5) {
		color = vec3(float(reflections_iters) / float(max_reflections));
	}
	else if (debug_view == 6) {
		color = normal;
	}

	// store the value in the image that we will blit
	imageStore(image, ivec2(gl_GlobalInvocationID.xy), vec4(color, 0));
}