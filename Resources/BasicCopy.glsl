#version 450 core

layout(local_size_x = 32, local_size_y = 32, local_size_z = 1) in;
layout(rgba8, binding = 0) uniform image2D image;
layout(r32ui, binding = 1) uniform uimage3D voxels[7];
layout(location = 1) uniform vec2 resolution;
layout(location = 2) uniform mat4 view_matrix;
layout(location = 3) uniform mat4 proj_matrix;
layout(location = 4) uniform vec3 position;
layout(location = 5) uniform int selector;
layout(location = 6) uniform int frame_selector;
layout(location = 7) uniform int map_size;

float sdf(vec3 pos) {
	return min(length(pos) - 1, pos.y);
}

// simple lighting based on normal
vec3 lighting(vec3 pos) {
	float size = 0.01;
	vec3 delta_x = vec3(size, 0, 0);
	vec3 delta_y = vec3(0, size, 0);
	vec3 delta_z = vec3(0, 0, size);
	float base = sdf(pos);
	float x = sdf(delta_x + pos);
	float y = sdf(delta_y + pos);
	float z = sdf(delta_z + pos);
	vec3 normal = normalize(vec3(x, y, z));

	float value = fract((floor(pos.x * 10) + floor(pos.z * 10)) * 0.5) * 2.0;
	float value2 = fract((floor(pos.x) + floor(pos.z)) * 0.5) * 2.0;
	value *= value2;

	return vec3(dot(normal, normalize(vec3(1, 1, 0))) * value);
}

vec3 hash32(vec2 p)
{
	vec3 p3 = fract(vec3(p.xyx) * vec3(.1031, .1030, .0973));
	p3 += dot(p3, p3.yxz + 33.33);
	return fract((p3.xxy + p3.yzz) * p3.zyx);
}

/*

/*
		//stepsize = 1.0;
		for (int j = selector; j >= 0; j--) {
			float factorino = pow(2, j);
			//aaa = ivec3();
			uint bruh = imageLoad(voxels[j], aaa).x;
			//stepsize = (j+1) * 3;
			total += 1;

			if (bruh == 0) {
				stepsize = factorino * 1.0;
				//stepsize = (j + 1);
				break;
			}

			if (j == 0 && bruh == 1) {
				a = 1;
				break;
			}
		}
		*/
*/

void main() {
	if ((mod(gl_GlobalInvocationID.x, 2) == 1 ^^ mod(gl_GlobalInvocationID.y, 2) == 0) ^^ (frame_selector == 0)) {
		return;
	}

	for (int k = 0; k < 64; k++)
	{
		grid_point = ivec3(floor(mod(vec3(pos), vec3(map_size, 100000, map_size))));
		pos += -ray_dir * 0.01;
		if (imageLoad(voxels[0], ivec3(grid_point)).x == 1) {
			break;
		}
	}

	/*
	* 
	* 
			for (int k = 0; k < 16; k++)
			{
				ivec3 aaa = ivec3(floor(mod(vec3(pos), vec3(map_size, 100000, map_size))));
				pos += -ray_dir * 0.03;
				if (imageLoad(voxels[0], aaa).x == 0) {
					break;
				}
			}
	

		if (pos.y < 40.0) {
			ray_dir = reflect(ray_dir, vec3(0, 1, 0));
			//ray_dir = refract(ray_dir, vec3(0, 1, 0), 1.0);
			//ray_dir += hash32(coords * 31.5143 + pos.x + pos.z) * 0.2;
			ray_dir = normalize(ray_dir);
			affect = vec3(0.3);
		}

vec3 c = vec3(80, 80, 0);
float r = length(pos - c);
if (r < 50.0) {
	ray_dir += ((normalize(pos - c)) / (pow(r, 3) * 0.04));
	ray_dir = normalize(ray_dir);
}

	*/

	/*
	float shadow = 1.00;
			/*
			vec3 light_dir = normalize(vec3(1, 1, 1));
			vec3 shadow_pos = pos + light_dir * 0.1;
			for (int k = 0; k < 32; k++)
			{
				ivec3 aaa = ivec3(floor(mod(vec3(shadow_pos), vec3(map_size, 100000, map_size))));
				shadow_pos += light_dir * 0.4;
				if (imageLoad(voxels[0], aaa).x == 1) {
					shadow = 0.3;
					//shadow = k;
					break;
				}
			}
			*/

	vec3 normal = (floor(pos) - pos + 0.5) / 0.5;
	color = affect * normal * shadow;

	/*
	float value = fract((floor(pos.x * 10) + floor(pos.z * 10) + floor(pos.y * 10)) * 0.5) * 2.0;
	float value2 = fract((floor(pos.x) + floor(pos.z) + floor(pos.y)) * 0.5) * 2.0;
	value *= value2;
	color *= vec3(value);
	*/

	
	*/

	// remap coords to ndc range (-1, 1)
	vec2 coords = gl_GlobalInvocationID.xy / resolution;
	coords *= 2.0;
	coords -= 1.0;

	// apply projection transformations for ray dir
	vec3 ray_dir = (view_matrix * proj_matrix * vec4(coords, 1, 0)).xyz;
	ray_dir = normalize(ray_dir);

	// ray marching stuff
	vec3 pos = position;
	vec3 color = vec3(-1.0);
	
	/*
	float f = 1.0;
	for (int i = 0; i < 512; i++) {
		float dist = sdf(pos) * f;
		pos += ray_dir * dist;

		vec3 c = vec3(20, 0, 0);
		float r = length(pos - c);
		if (r < 14.0) {
			ray_dir += ((normalize(pos - c)) / pow(r, 4));
			ray_dir = normalize(ray_dir);
			f = 0.3;
		}

		if (dist < 0.02) {
			//color = vec3(i / 128.0);
			color = clamp(lighting(pos), 0, 1);
			break;
		}
	}

	if (all(color == vec3(-1))) {
		color = ray_dir;
	}
	*/

	//color = imageLoad(voxels, ivec3(gl_GlobalInvocationID.xy, 0)).xyz;
	float stepsize = 1.0;
	int total = 0;
	vec3 last_pos = vec3(0);
	vec3 affect = vec3(1);

	for (int i = 0; i < 128; i++) {
		pos += ray_dir * stepsize * 0.2;
		
		int a = 0;

		if (pos.y < 10.0) {
			ray_dir = reflect(ray_dir, vec3(0, 1, 0)) + hash32(coords * 31.5143 + pos.x + pos.z) * 0.2;
			ray_dir = normalize(ray_dir);
			affect = vec3(0.3);
		}

		vec3 c = vec3(80, 80, 0);
		float r = length(pos - c);
		if (r < 50.0) {
			ray_dir += ((normalize(pos - c)) / (pow(r, 3) * 0.04));
			ray_dir = normalize(ray_dir);
			//return;
			//f = 0.3;
		}
		
		//stepsize = 1.0;
		for (int j = selector; j >= 0; j--) {
			float factorino = pow(2, j);
			ivec3 aaa = ivec3(floor(mod(vec3(pos), vec3(map_size, 100000, map_size)) / factorino));
			//aaa = ivec3();
			uint bruh = imageLoad(voxels[j], aaa).x;
			//stepsize = (j+1) * 3;
			total += 1;

			if (bruh == 0) {
				stepsize = factorino * 1.0;
				//stepsize = (j + 1);
				break;
			}

			if (j == 0 && bruh == 1) {
				a = 1;
				break;
			}
		}

		//  && all(greaterThan(pos, vec3(0))) && all(lessThan(pos, vec3(128)))
		if (a == 1) {
			//color = vec3(lodmoment / 4.0);
			for (int k = 0; k < 16; k++)
			{
				ivec3 aaa = ivec3(floor(mod(vec3(pos), vec3(map_size, 100000, map_size))));
				pos += -ray_dir * 0.03;
				if (imageLoad(voxels[0], aaa).x == 0) {
					break;
				}
			}

			float shadow = 1.00;
			vec3 light_dir = normalize(vec3(1, 1, 1));
			vec3 shadow_pos = pos + light_dir * 0.1;
			for (int k = 0; k < 32; k++)
			{
				ivec3 aaa = ivec3(floor(mod(vec3(shadow_pos), vec3(map_size, 100000, map_size))));
				shadow_pos += light_dir * 0.4;
				if (imageLoad(voxels[0], aaa).x == 1) {
					shadow = 0.3;
					//shadow = k;
					break;
				}
			}

			vec3 normal = (floor(pos) - pos + 0.5) / 0.5;
			color = affect * normal * shadow;

			/*
			ivec3 aaa2 = ivec3(floor(mod(vec3(pos), vec3(map_size, 100000, map_size)))) + ivec3(0, 1, 0);
			if (normal.y > 0.8 && imageLoad(voxels[0], aaa2).x == 0) {
				color *= 0.2;
			}
			*/

			//color = normalize(round(normal)) * affect;

			/*
			if (shadow > 0) {
				//color *= shadow / 32.0;
			}
			*/

			//color = vec3(i) / vec3(512.0);
			float value = fract((floor(pos.x * 10) + floor(pos.z * 10) + floor(pos.y * 10)) * 0.5) * 2.0;
			float value2 = fract((floor(pos.x) + floor(pos.z) + floor(pos.y)) * 0.5) * 2.0;
			value *= value2;
			//color *= vec3(value);
			break;
		}

		last_pos = pos;
	}

	/*
	if (all(color == vec3(-1))) {
		color = ray_dir * affect;
	}
	*/

	//color *= vec3(float(total) / 200.0);
	//color *= vec3(float(total) / 200.0);
	//color = i / 64.0;
	//color = imageLoad(voxels[0], ivec3(gl_GlobalInvocationID.xy, 0)).xyz;

	// store the value in the image that we will blit
	imageStore(image, ivec2(gl_GlobalInvocationID.xy), vec4(color, 0));
}

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
layout(rg32ui, binding = 1) uniform uimage3D voxels[7];
layout(binding = 2) uniform samplerCube skybox;

#include Hashes.glsl
#include Lighting.glsl

// 3d cube vs ray intersection that allows us to calculate closest distance to face of cube
vec2 intersection(vec3 pos, vec3 dir, vec3 inv_dir, vec3 smol, vec3 beig, inout int max_dir, inout int min_dir) {
	float tmin = 0.0, tmax = 1000000.0;
	inv_dir = 1.0 / dir;
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
void recurse(vec3 pos, vec3 ray_dir, vec3 inv_dir, inout bool hit, inout float voxel_distance, inout float min_level_reached, inout vec3 normal) {
	// recursively iterate through the mip maps (starting at the highest level)
	// check each level for big empty spaces that we can skip over
	for (int j = max_mip_iter; j >= 0; j--) {
		// use the mip maps themselves as an acceleration structure
		float scale_factor = pow(2, j);
		vec3 grid_level_point = floor(pos / scale_factor) * scale_factor;

		// calculate temporary distance to the end of the current cell for the current mipmap
		int a = 0;
		int b = 0;
		vec2 distances = intersection(pos, ray_dir, inv_dir, grid_level_point, grid_level_point + vec3(scale_factor), a, b);
		float t_voxel_distance = distances.y - distances.x;
		ivec3 tex_point = ivec3(floor(pos));

		if (imageLoad(voxels[j], tex_point).x == 0) {
			voxel_distance = t_voxel_distance;
			hit = false;
			min_level_reached = min(min_level_reached, j);

			int min_side_hit = 0;
			int max_side_hit = 0;
			intersection(pos, ray_dir, inv_dir, grid_level_point, grid_level_point + vec3(scale_factor), min_side_hit, max_side_hit);
			normal = get_internal_box_normal(max_side_hit, ray_dir);

			break;
		}
	}
}

// trace WITHIN the voxel!!! (I love bitwise ops)
void trace_internal(inout vec3 pos, vec3 ray_dir, vec3 inv_dir, inout float voxel_distance, inout bool hit, inout vec3 normal, inout float bit_fetches) {
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
			// TODO: Find a way to avoid an intersection thingy here
			//pos = clamp(pos, grid_level_point + 0.1, vec3(0.24));
			intersection(pos, -ray_dir, -inv_dir, grid_level_point, grid_level_point + vec3(0.25), min_side_hit, max_side_hit);

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
		recurse(pos, ray_dir, inv_dir, temp_hit, voxel_distance, min_level_reached, normal);

		// gotta add a small offset since we'd be on the very face of the voxel
		pos += ray_dir * max(0.001, voxel_distance);

		// do all of our lighting calculations here
		if (temp_hit) {
			temp_hit = false;

			if (use_sub_voxels == 1) {
				trace_internal(pos, ray_dir, inv_dir, voxel_distance, temp_hit, normal, total_inner_bit_fetches);
			}

			if (temp_hit || use_sub_voxels == 0) {
				if (pos.x < 33) {
					if (reflections_iters < max_reflections) {
						//ray_dir = refract(ray_dir, normal, 1.4);
						ray_dir = reflect(ray_dir, normal);
						ray_dir += (hash32(coords * 31.5143 * vec2(12.3241, 2.341)) - 0.5) * reflection_roughness;
						ray_dir = normalize(ray_dir);
						inv_dir = 1.0 / (ray_dir + vec3(0.0001));

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

		color *= pow((1 - factor), 3) * 0.4 + 0.6;
	}

	else if (debug_view == 1) {
		int min_dir = 0;
		int max_dir = 0;
		vec2 dists = intersection(pos, ray_dir, inv_dir, vec3(0), vec3(map_size), min_dir, max_dir);
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