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

vec3 hash32(vec2 p)
{
	vec3 p3 = fract(vec3(p.xyx) * vec3(.1031, .1030, .0973));
	p3 += dot(p3, p3.yxz + 33.33);
	return fract((p3.xxy + p3.yzz) * p3.zyx);
}



vec2 intersection(vec3 dir, vec3 smol, vec3 beig) {
	float tmin = 0.0, tmax = 1000000.0;
	vec3 dir_inv = 1.0 / dir;

	for (int d = 0; d < 3; d++) {
		float t1 = (smol[d] - position[d]) * dir_inv[d];
		float t2 = (beig[d] - position[d]) * dir_inv[d];

		tmin = max(tmin, min(t1, t2));
		tmax = min(tmax, max(t1, t2));
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

void main() {
	// checkerboard rendering
	if ((mod(gl_GlobalInvocationID.x, 2) == 1 ^^ mod(gl_GlobalInvocationID.y, 2) == 0) ^^ (frame_selector == 0)) {
		return;
	}

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

	// debug stuff to view mip map iterations
	float total_iterations = 0.0;
	float total_mip_map_iterations = 0.0;

	for (int i = 0; i < 64; i++) {
		total_iterations += 1;
		float voxel_distance = 0.0;

		// recursively iterate through the mip maps (starting at the highest level)
		// check each level for big empty spaces that we can skip over
		for (int j = selector; j >= 0; j--) {
			// use the mip maps themselves as an acceleration structure
			float scale_factor = pow(2, j);
			vec3 grid_level_point = floor(pos / scale_factor) * scale_factor;

			// calcualte temporary distance ot the end of the current cell for the current mipmap
			vec2 distances = intersection(ray_dir, grid_level_point, grid_level_point + vec3(scale_factor));
			float t_voxel_distance = distances.y - distances.x;

			// modulo scale for repeating the maps
			vec3 modulo_scale = vec3(map_size / scale_factor, 100000, map_size / scale_factor);
			ivec3 tex_point = ivec3(floor(mod(pos / scale_factor, modulo_scale)));
			
			total_mip_map_iterations += 1;
			if (imageLoad(voxels[j], tex_point).x == 0) {
				voxel_distance = t_voxel_distance;
				break;
			}
		}

		// gotta add a small offset since we'd be on the very face of the voxel
		pos += ray_dir * (0.001 + voxel_distance);
		
		// lel
		if (voxel_distance == 0) {
			vec3 normal = -(floor(pos) - pos + 0.5) / 0.5;

			ivec3 tex_point = ivec3(floor(mod(pos, vec3(map_size, 100000, map_size))));
			if (imageLoad(voxels[0], tex_point + ivec3(0, 1, 0)).x == 0 && normal.y > 0.707) {
				color = vec3(1);
			}

			break;
		}
	}

	/*
	if (all(color == vec3(-1))) {
		color = ray_dir;
	}
	*/

	//color = vec3(total_iterations / 64.0);
	//color = vec3(total_mip_map_iterations / (64.0 * selector));
	
	// store the value in the image that we will blit
	imageStore(image, ivec2(gl_GlobalInvocationID.xy), vec4(color, 0));
}