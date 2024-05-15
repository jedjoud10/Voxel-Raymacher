﻿#version 460
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
layout(rg32ui, binding = 1, location = 10) uniform uimage3D voxels[7];

vec3 hash32(vec2 p)
{
	vec3 p3 = fract(vec3(p.xyx) * vec3(.1031, .1030, .0973));
	p3 += dot(p3, p3.yxz + 33.33);
	return fract((p3.xxy + p3.yzz) * p3.zyx);
}
float hash12(vec2 p)
{
	vec3 p3 = fract(vec3(p.xyx) * .1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}
float hash13(vec3 p3)
{
	p3 = fract(p3 * .1031);
	p3 += dot(p3, p3.zyx + 31.32);
	return fract((p3.x + p3.y) * p3.z);
}

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

// simple lighting calculation for the sky background
vec3 sky(vec3 normal) {
	return vec3(0.2);
}

// recrusviely go through the mip chain
void recurse(vec3 pos, vec3 ray_dir, inout bool hit, inout float voxel_distance, inout float min_level_reached) {
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
			break;
		}
	}
}

// fetches the 64 bit 4x4x4 sub-voxel volume for one voxel
uint64_t get_binary_data(vec3 pos) {
	ivec3 tex_point = ivec3(floor(mod(pos, vec3(map_size, 100000, map_size))));
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

// simple lighting calculation stuff for when we hit a voxel
vec3 lighting(vec3 pos, vec3 normal, vec3 ray_dir) {
	vec3 smooth_normal = (-(floor(pos * 4) - (pos * 4) + 0.5) / 0.5);
	smooth_normal = normalize(smooth_normal);
	vec3 internal = floor(pos * 4.0) / 4.0;
	vec3 light_dir = normalize(vec3(1, 1, 1));
	
	float light = clamp(dot(normal, light_dir), 0, 1) + 0.3;
	vec3 color = vec3(1);
	color = (normal.y > 0.5 ? vec3(17, 99, 0) : vec3(48, 36, 0));

	//return vec3(pow(dot(reflect(ray_dir, normal), light_dir), 10));
	return (color / 255.0) * light;
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
	vec3 color = vec3(-1.0);
	vec3 normal = vec3(0);

	// const settings
	int max_reflections = 1;

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
			hit = false;
			break;
		}

		// recursively go through the mip chain
		recurse(pos, ray_dir, temp_hit, voxel_distance, min_level_reached);

		// gotta add a small offset since we'd be on the very face of the voxel
		pos += ray_dir * (0.001 + voxel_distance);
		
		// do all of our lighting calculations here
		if (temp_hit) {
			temp_hit = false;
			trace_internal(pos, ray_dir, voxel_distance, temp_hit, normal, total_inner_bit_fetches);

			if (temp_hit) {
				/*
				if (pos.y < 33) {
					if (reflections_iters < max_reflections) {
						ray_dir = reflect(ray_dir, vec3(0, 1, 0));
						reflections_iters += 1;
						continue;
					}
				}
				*/

				color = lighting(pos, normal, ray_dir);
				hit = true;
				break;
			}
		}
	}

	// ACTUAL GAME VIEW
	if (debug_view == 0) {	
		/*
		if (!hit) {
			color = sky(ray_dir);
		}
		*/
	}
	
	else if (debug_view == 1) {
		int min_dir = 0;
		int max_dir = 0;
		vec2 dists = intersection(pos, ray_dir, vec3(0), vec3(map_size), min_dir, max_dir);
		
		if (max_dir == 0) {
			color = vec3(1, 0, 0);
		}
		else if (max_dir == 1) {
			color = vec3(0, 1, 0);
		}
		else if (max_dir == 2) {
			color = vec3(0, 0, 1);
		}
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