
#version 460
#extension GL_ARB_gpu_shader_int64 : enable
layout(local_size_x = 32, local_size_y = 32, local_size_z = 1) in;
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
layout(location = 15) uniform int max_sub_voxel_iter;

layout(rgba8, binding = 0) uniform image2D image;
layout(r32f, binding = 1) uniform image2D temporal_depth;
layout(binding = 2) uniform usampler3D voxels;
layout(binding = 3) uniform samplerCube skybox;
layout(location = 16) uniform mat4 last_frame_view_matrix;
layout(location = 17) uniform uint frame_count;
layout(location = 18) uniform int use_temporal_depth;
layout(location = 19) uniform vec3 last_position;
layout(location = 20) uniform float ambient_strength;
layout(location = 21) uniform float normal_map_strength;
layout(location = 22) uniform float gloss_strength;
layout(location = 23) uniform float specular_strength;
layout(location = 24) uniform vec3 top_color;
layout(location = 25) uniform vec3 side_color;

#include Hashes.glsl
#include Lighting.glsl
#include Intersections.glsl

void main() {
	// remap coords to ndc range (-1, 1)
	vec2 coords = gl_GlobalInvocationID.xy / resolution;
	coords *= 2.0;
	coords -= 1.0;

	// apply projection transformations for ray dir
	vec3 ray_dir = (view_matrix * proj_matrix * vec4(coords, 1, 0)).xyz;
	vec2 lastuvs = (inverse(last_frame_view_matrix * proj_matrix) * vec4(ray_dir, 0.0)).xy;
	ray_dir = normalize(ray_dir);
	vec3 inv_dir = 1.0 / (ray_dir + vec3(0.0001));

	// ray marching stuff
	float start_offset = 1.0;
	vec3 pos = position + ray_dir * start_offset;
	bool hit = false;

	// vars for default view
	vec3 color = vec3(0.0);
	vec3 normal = vec3(0);
	uint level_cache = 8;

	// debug stuffs
	float total_iterations = 0.0;
	float total_mip_map_iterations = 0.0;
	float total_inner_bit_fetches = 0.0;
	float min_level_reached = 1000;
	int reflections_iters = 0;
	float factor = 1.0;

	// try reprojecting last frame depth into current frame depth as accel structure
	// how????
	// need to get the uv of the current pixel but using the last frame's view matrix
	// last_frame_view_matrix
	// temporal_depth
	//pos += ray_dir * 10;
	
	//imageStore(image, ivec2(gl_GlobalInvocationID.xy), vec4(vec2(gl_GlobalInvocationID.xy) / resolution, 0, 1.0));
	lastuvs += 1;
	lastuvs /= 2;
	ivec2 pixelu = ivec2(lastuvs * resolution);
	//imageStore(image, ivec2(gl_GlobalInvocationID.xy), vec4(pixelu, 0, 1.0));

	vec3 advanced_pos = pos;
	if (lastuvs.x > 0 && lastuvs.y > 0 && lastuvs.x < 1 && lastuvs.y < 1 && use_temporal_depth == 1) {
		// WARNING: This WILL NOT work with reflections because pos would be the reflected pos, making the ray overshoot really far
		float min_depth = 1000;

		int scaler = 2;
		for (int x = -scaler; x < scaler; x++)
		{
			for (int y = -scaler; y < scaler; y++)
			{
				float last_depth = imageLoad(temporal_depth, pixelu + ivec2(x,y) * 2).x;
				min_depth = min(last_depth, min_depth);
			}
		}

		// add margin if we are moving in the direction of the ray
		float margin = clamp(dot(position - last_position, ray_dir), 0, 1);
		advanced_pos += ray_dir * (min_depth - 0.01 - margin - start_offset);

		// (mod(gl_GlobalInvocationID.x, 2) == 1 ^^ mod(gl_GlobalInvocationID.y, 2) == 0) 
		// ((frame_count % 60) < 58))
	}

	pos = advanced_pos;

	// check if the advanced pos's voxel matches up with the actual terrain
	/*
	advanced_pos += ray_dir * 0.001;
	float scale = (use_sub_voxels == 1) ? 0.5 : 1;
	vec3 grid_level_point = floor(pos / scale) * scale;
	vec3 distsaa = intersection(pos, -ray_dir, -inv_dir, grid_level_point, grid_level_point + vec3(scale));
	float close = distsaa.x;
	*/

	// check if there is a discrepency in the closest "real" distance and 


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
				// Find normal using another intersection test
				int min_side_hit = 0;
				int max_side_hit = 0;
				pos += ray_dir * 0.001;
				float scale = (use_sub_voxels == 1) ? 0.25 : 1;
				vec3 grid_level_point = floor(pos / scale) * scale;
				vec2 dists = intersection(pos, -ray_dir, -inv_dir, grid_level_point, grid_level_point + vec3(scale), min_side_hit, max_side_hit);
				normal = get_internal_box_normal(max_side_hit, ray_dir);

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

				color = lighting(pos, normal, ray_dir);

				// dim the block faces if they are facing inside
				vec3 ta = (pos - ray_dir * 0.02);
				if (all(greaterThan(ta, grid_level_point)) && all(lessThan(ta, grid_level_point + vec3(scale)))) {
					color *= 0.3;
				}

				hit = true;
				break;
			}
		}
	}

	// store depth values!!
	float depth = distance(pos, position);

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
	else if (debug_view == 10) {
		color = vec3(log(depth) / 5, 0, 0);
	}

	// store the value in the image that we will blit
	imageStore(image, ivec2(gl_GlobalInvocationID.xy), vec4(color, 1.0));

	if (!hit) {
		depth = 1000.0;
	}

	imageStore(temporal_depth, ivec2(gl_GlobalInvocationID.xy), vec4(depth, 0, 0, 1.0));
}