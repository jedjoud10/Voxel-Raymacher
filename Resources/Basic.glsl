
#version 460
#extension GL_ARB_gpu_shader_int64 : enable
layout(local_size_x = 32, local_size_y = 32, local_size_z = 1) in;

// world
layout(binding = 2) uniform usampler3D voxels;
layout(binding = 3) uniform samplerCube skybox;
layout(r32i, binding = 4) uniform iimage3D sparse_helper;
layout(location = 12) uniform vec3 light_dir;

// settings
layout(location = 27) uniform float scale_factor;
layout(location = 1) uniform vec2 resolution;
layout(location = 5) uniform int max_mip_iter;
layout(location = 6) uniform int max_iters;
layout(location = 30) uniform int max_shadow_iters;
layout(location = 7) uniform int map_size;
layout(location = 8) uniform int debug_view;
layout(location = 9) uniform int max_reflections;
layout(location = 10) uniform int use_sub_voxels;
layout(location = 11) uniform float reflection_roughness;
layout(location = 13) uniform int use_octree_ray_caching;
layout(location = 14) uniform int use_prop_aabb_bounds;
layout(location = 15) uniform int max_sub_voxel_iter;
layout(location = 18) uniform int use_temporal_depth;
layout(location = 26) uniform int hold_temporal_values;
layout(location = 28) uniform int use_positional_repro;


// camera
layout(location = 2) uniform mat4 view_matrix;
layout(location = 3) uniform mat4 proj_matrix;
layout(location = 4) uniform vec3 position;
layout(location = 16) uniform mat4 last_frame_view_matrix;
layout(location = 19) uniform vec3 last_position;

// rendering
layout(rgba8, binding = 0) uniform image2D image;
layout(r32f, binding = 1) uniform image2D new_temporal_depth;
layout(binding = 5) uniform sampler2D last_temporal_depth;
layout(location = 17) uniform int frame_count;
layout(location = 20) uniform float ambient_strength;
layout(location = 22) uniform float roughness_strength;
layout(location = 23) uniform float metallic_strength;
layout(location = 21) uniform float normal_map_strength;
layout(location = 24) uniform vec3 top_color;
layout(location = 25) uniform vec3 side_color;


#include Hashes.glsl
#include Lighting.glsl
#include Intersections.glsl
#include Noise.glsl

void main() {
	//return;
	// remap coords to ndc range (-1, 1)
	vec2 coords = gl_GlobalInvocationID.xy / resolution;
	coords *= 2.0;
	coords -= 1.0;

	// apply projection transformations for ray 
	vec4 ray_dir_non_normalized = inverse(proj_matrix) * vec4(coords, -1.0, 1.0);
	ray_dir_non_normalized.w = 0.0;
	ray_dir_non_normalized = inverse(view_matrix) * ray_dir_non_normalized;
	vec3 ray_dir = normalize(ray_dir_non_normalized.xyz);
	vec3 inv_dir = 1.0 / (ray_dir + vec3(0.0001));

	// for positional reprojection
	// start at new position, ray-march towards the current ray dir
	// at each position check if the pos is inside the last frame's cam matrix (repro & check if uvs are valid, store depth in d0)
	//   do this by finding ray dir using last frame pos and current step pos
	// if valid, get depth using last frame's depth texture
	// compare this depth to what would be seen from last frame's camera at that point's depth (store in d0)
	//
	vec3 repr_pos = position + ray_dir;
	vec3 bruhtu = vec3(0.0);
	float pos_reprojected_depth = 0.0;
	int total_steps = 32;

	vec2 test_test_dists = intersection(position, ray_dir, inv_dir, vec3(0), vec3(map_size));
	float step_size = test_test_dists.y / float(total_steps);
	float step_size_offset_factor = 1.0;
	float total_repro_steps_percent_taken = 1.0;

	if (use_positional_repro == 1 && use_temporal_depth == 1) {
		for (int i = 0; i < total_steps; i++)
		{
			vec3 temp_ray_dir = repr_pos - last_position;
			vec4 test_uvs = (proj_matrix * last_frame_view_matrix) * vec4(temp_ray_dir, 0.0);
			test_uvs.xyz /= test_uvs.w;
			vec2 test_uvs2 = test_uvs.xy;
			test_uvs2 += 1;
			test_uvs2 /= 2;

			if (test_uvs2.x > 0 && test_uvs2.y > 0 && test_uvs2.x < 1 && test_uvs2.y < 1 && test_uvs.w > 0) {
				float od = texture(last_temporal_depth, test_uvs2 / scale_factor).x;
				float nd = distance(last_position, repr_pos);
				if (od < nd) {
					float act_act_min_depth = distance(position, repr_pos);
					act_act_min_depth -= step_size * step_size_offset_factor;
					pos_reprojected_depth = act_act_min_depth;
					bruhtu = vec3(od);
					total_repro_steps_percent_taken = float(i) / float(total_steps);
					break;
				}
			}

			repr_pos += ray_dir * step_size;
		}
	}

	vec4 last_uvs_full = (proj_matrix * last_frame_view_matrix) * vec4(ray_dir_non_normalized.xyz, 0.0);
	last_uvs_full.xyz /= last_uvs_full.w;

	// convert the [-1,1] range to [0,1] for texture sampling
	vec2 last_uvs = last_uvs_full.xy;
	last_uvs += 1;
	last_uvs /= 2;

	// ray marching stuff
	vec3 pos = position;
	bool hit = false;

	// vars for default view
	vec3 color = vec3(0.0);
	vec3 normal = vec3(0);
	uint level_cache = uint(1) << (max_mip_iter);

	// debug stuffs
	float total_iterations = 0.0;
	float total_mip_map_iterations = 0.0;
	float total_inner_bit_fetches = 0.0;
	float min_level_reached = 1000;
	int reflections_iters = 0;
	float factor = 1.0;
	
	float min_depth = 100000;
	if (use_temporal_depth == 1) {
		if (use_positional_repro == 1) {
			min_depth = max(pos_reprojected_depth, 0);
			pos += ray_dir * (min_depth - 0.01);
		}
		else {
			if (last_uvs.x > 0 && last_uvs.y > 0 && last_uvs.x < 1 && last_uvs.y < 1 && last_uvs_full.w > 0) {
				int scaler = 2;
				for (int x = -scaler; x <= scaler; x++)
				{
					for (int y = -scaler; y <= scaler; y++)
					{
						float last_depth = texture(last_temporal_depth, (last_uvs + vec2(x, y) * 0.003) / scale_factor).x;
						min_depth = min(last_depth, min_depth);
					}
				}

				pos += ray_dir * (min_depth - 0.01);
			}
		}
	}

	vec3 first_touched_pos = vec3(0);
	for (int i = 0; i < max_iters; i++) {
		bool temp_hit = true;
		total_iterations += 1;
		float voxel_distance = 0.0;

		// we know the map isn't *that* big
		if (any(greaterThan(pos, vec3(map_size))) || any(lessThan(pos, vec3(0)))) {
			break;
		}

		// recursively go through the mip chain
		int max_side_hit_g = 0;
		recurse(pos, ray_dir, inv_dir, temp_hit, voxel_distance, min_level_reached, total_mip_map_iterations, level_cache, max_side_hit_g);

		// gotta add a small offset since we'd be on the very face of the voxel
		vec3 testa = pos;
		pos += ray_dir * max(0.01, voxel_distance);

		// do all of our lighting calculations here
		if (temp_hit) {
			temp_hit = false;

			if (use_sub_voxels == 1) {
				trace_internal(pos, ray_dir, inv_dir, voxel_distance, temp_hit, total_inner_bit_fetches);
			}

			if (temp_hit || use_sub_voxels == 0) {
				// Find normal using another intersection test
				int min_side_hit = 0;
				int max_side_hit = 0;
				//pos += ray_dir * 0.01;
				float scale = (use_sub_voxels == 1) ? 0.25 : 1;

				if (reflections_iters == 0) {
					first_touched_pos = pos;
				}

				vec3 grid_level_point = floor(testa / scale) * scale;
				vec2 dists = intersection(testa + ray_dir, -ray_dir, -inv_dir, grid_level_point, grid_level_point + vec3(scale), min_side_hit, max_side_hit);
				normal = get_internal_box_normal(max_side_hit, ray_dir);

				if (pos.x < 33) {
					if (reflections_iters < max_reflections) {
						ray_dir = reflect(ray_dir, normal);
						ray_dir = normalize(ray_dir);
						inv_dir = 1.0 / (ray_dir + vec3(0.0001));
						level_cache = uint(~0);
						factor /= 2.0;

						pos += ray_dir * 0.01;
						reflections_iters += 1;
						continue;
					}
					else {
						hit = false;
						break;
					}
				}

				float shadowed = 0;
				if (max_shadow_iters > 0) {
					vec3 shadow_pos = pos + light_dir * 0.1;
					vec3 shadow_dir = light_dir;
					vec3 inv_shadow_dir = 1 / (shadow_dir + vec3(0.001));
					float sum = 0;
					float aaaaa = 0;
					float aaaaaa = 0;
					float aaaaaaa = 0;
					for (int i = 0; i < max_shadow_iters; i++) {
						bool temp_hit = true;
						float voxel_distance = 0.0;

						// we know the map isn't *that* big
						if (any(greaterThan(shadow_pos, vec3(map_size))) || any(lessThan(shadow_pos, vec3(0)))) {
							break;
						}

						// recursively go through the mip chain
						int max_side_hit_g = 0;
						recurse(shadow_pos, shadow_dir, inv_shadow_dir, temp_hit, voxel_distance, aaaaaaa, aaaaaa, level_cache, max_side_hit_g);
						
						// gotta add a small offset since we'd be on the very face of the voxel
						shadow_pos += shadow_dir * max(0.001, voxel_distance);
						sum += voxel_distance;

						if (temp_hit && use_sub_voxels == 1) {
							trace_internal(shadow_pos, shadow_dir, inv_shadow_dir, voxel_distance, temp_hit, aaaaa);
						}

						if (temp_hit) {
							shadowed = 1;
							break;
						}
					}
				}
				
				color = lighting(pos, normal, ray_dir, shadowed);
				//color = vec3(dists.y - dists.x);

				// dim the block faces if they are facing inside
				/*
				vec3 ta = (pos - ray_dir * 0.02);
				if (all(greaterThan(ta, grid_level_point)) && all(lessThan(ta, grid_level_point + vec3(scale)))) {
					//color *= 0.3;
				}
				*/

				hit = true;
				break;
			}
		}
	}

	// store depth values!!
	float depth = distance(first_touched_pos, position);

	// ACTUAL GAME VIEW
	if (debug_view == 0) {
		if (!hit) {
			color = texture(skybox, ray_dir).xyz;
		}
		color /= pow(2, max(reflections_iters-1, 0));
		color = aces(color);
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
		color = vec3(total_inner_bit_fetches / float(60));
	}
	else if (debug_view == 5) {
		color = vec3(total_mip_map_iterations / float(128));
	}
	else if (debug_view == 6) {
		color = vec3(float(reflections_iters) / float(max_reflections));
	}
	else if (debug_view == 7) {
		normal = normalize(normal);
		color = normal;		
	}
	else if (debug_view == 8) {
		color = pos;
	}
	else if (debug_view == 9) {
		color = pos - floor(pos);
	}
	else if (debug_view == 10) {
		color = pos * 4 - floor(pos * 4);
	}
	else if (debug_view == 11) {
		color = vec3(log(depth) / 5, 0, 0);
	}
	else if (debug_view == 12) {
		color = vec3(log(bruhtu.x) / 5, 0, 0);
	}
	else if (debug_view == 13) {
		color = vec3(log(min_depth) / 5, 0, 0);
	}
	else if (debug_view == 14) {
		color = vec3(total_repro_steps_percent_taken);
	}

	if (!hit && reflections_iters == 0) {
		depth = 10000;
	}

	imageStore(image, ivec2(gl_GlobalInvocationID.xy), vec4(color, 1.0));
	if (hold_temporal_values == 0) {
		imageStore(new_temporal_depth, ivec2(gl_GlobalInvocationID.xy), vec4(depth, 0, 0, 1.0));
	}
}