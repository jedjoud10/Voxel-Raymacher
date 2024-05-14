#version 460
#extension GL_ARB_gpu_shader_int64 : enable

layout(local_size_x = 32, local_size_y = 32, local_size_z = 1) in;
layout(rgba8, binding = 0, location = 0) uniform image2D image;
layout(location = 1) uniform vec2 resolution;
layout(location = 2) uniform mat4 view_matrix;
layout(location = 3) uniform mat4 proj_matrix;
layout(location = 4) uniform vec3 position;
layout(location = 5) uniform int selector;
layout(location = 6) uniform int frame_selector;
layout(location = 7) uniform int map_size;
layout(location = 8) uniform int debug_selector;
layout(location = 9) uniform int max_iters;
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
vec2 intersection(vec3 pos, vec3 dir, vec3 smol, vec3 beig) {
	float tmin = 0.0, tmax = 1000000.0;
	vec3 dir_inv = 1.0 / (dir + vec3(0.001));

	for (int d = 0; d < 3; d++) {
		float t1 = (smol[d] - pos[d]) * dir_inv[d];
		float t2 = (beig[d] - pos[d]) * dir_inv[d];

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

// simple lighting calculation for the sky background
vec3 sky(vec3 normal) {
	return vec3(0.2);
}

// recrusviely go through the mip chain
void recurse(vec3 pos, vec3 ray_dir, inout bool hit, inout float voxel_distance, inout float min_level_reached) {
	// recursively iterate through the mip maps (starting at the highest level)
	// check each level for big empty spaces that we can skip over
	for (int j = selector; j >= 0; j--) {
		// use the mip maps themselves as an acceleration structure
		float scale_factor = pow(2, j);
		vec3 grid_level_point = floor(pos / scale_factor) * scale_factor;

		// calculate temporary distance to the end of the current cell for the current mipmap
		vec2 distances = intersection(pos, ray_dir, grid_level_point, grid_level_point + vec3(scale_factor));
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

// hehehehe shadow mapping...
// start from map edge
// go towards -ve sun dir
// check if pos is diff 
bool shadow(vec3 pix_pos, inout vec3 last) {
	vec3 sun_dir = normalize(vec3(1, 1, 1));
	vec2 dists = intersection(pix_pos, sun_dir, vec3(0), vec3(map_size));
	vec3 proj_map_edge = pix_pos + dists.y * sun_dir;
	proj_map_edge -= sun_dir * 0.3;
	float d1 = distance(proj_map_edge, pix_pos);

	vec3 f_pos = proj_map_edge;
	float afgfg = 0.0;
	for (int i = 0; i < 8; i++) {
		if (any(greaterThan(f_pos, vec3(map_size))) || any(lessThan(f_pos, vec3(0)))) {
			return false;
		}
		
		bool hit = true;
		float v_distance = 0.0;

		recurse(f_pos, -sun_dir, hit, v_distance, afgfg);
		f_pos -= sun_dir * (0.001 + v_distance);
		last = f_pos;
		float d2 = distance(proj_map_edge, f_pos);

		if (d2 > d1) {
			return true;
		}
	}

	return false;
}

float at(vec3 pos) {
	ivec3 tex_point = ivec3(floor(mod(pos, vec3(map_size, 100000, map_size))));
	return imageLoad(voxels[0], tex_point).x == 0 ? 1.0 : 0.0;
}

uvec2 tam(vec3 pos) {
	ivec3 tex_point = ivec3(floor(mod(pos, vec3(map_size, 100000, map_size))));
	return imageLoad(voxels[0], tex_point).xy;
}

bool check_inner_bits(vec3 pos, uint64_t bits) {
	//pos += 0.5;
	ivec3 internal = ivec3(floor(pos * 4) - floor(pos) * 4);
	uint index = internal.x * 4 * 4 + internal.y * 4 + internal.z;
	return (bits & (1 << index)) != 0;
}

vec3 block_normal(vec3 pos, vec3 normal) {
	float epsilon = 0.1;
	float posx = at(pos + vec3(epsilon, 0, 0));
	float posy = at(pos + vec3(0, epsilon, 0));
	float posz = at(pos + vec3(0, 0, epsilon));
	float nposx = at(pos - vec3(epsilon, 0, 0));
	float nposy = at(pos - vec3(0, epsilon, 0));
	float nposz = at(pos - vec3(0, 0, epsilon));
	return vec3(posx-nposx, posy-nposy, posz-nposz);
}

// simple lighting calculation stuff for when we hit a voxel
vec3 lighting(inout vec3 pos, vec3 normal, vec3 ray_dir, inout float voxel_distance, inout bool hit) {
	vec3 internal = floor(pos * 8.0) / 8.0;
	vec3 color = vec3(1);
	normal = block_normal(pos, normal);

	vec3 light_dir = normalize(vec3(1, 1, 1));
	float light = clamp(dot(normal, light_dir), 0, 1) + 0.3;
	color = (normal.y > 0.5 ? vec3(17, 99, 0) : vec3(48, 36, 0));

	uvec2 inner = tam(pos);
	uint64_t inner_bits = packUint2x32(inner);
	vec3 min_pos = floor(pos);
	vec3 max_pos = ceil(pos);

	//return check_inner_bits(pos, inner_bits) ? vec3(1.0) : vec3(0.0);

	for (int i = 0; i < 6; i++) {
		vec3 grid_level_point = floor(pos / 0.25) * 0.25;
		vec2 distances = intersection(pos, ray_dir, grid_level_point, grid_level_point + vec3(0.25));
		voxel_distance = distances.y - distances.x;

		if (check_inner_bits(pos, inner_bits)) {
			hit = true;
			ivec3 internal2 = ivec3(floor(pos * 4) - floor(pos) * 4);
			return vec3(internal2 * hash13(min_pos)) / 4.0;
		}

		if (grid_level_point) {
			break;
		}

		pos += ray_dir * (0.001 + voxel_distance);
	}

	hit = false;
	return vec3(0);

	//return vec3( / 1000.0, 0);
	//return (color / 255.0) * light * 2.0;
}

void main() {
	// checkerboard rendering
	if ((mod(gl_GlobalInvocationID.x, 2) == 1 ^^ mod(gl_GlobalInvocationID.y, 2) == 0) ^^ (frame_selector == 0)) {
		//return;
	}



	// remap coords to ndc range (-1, 1)
	vec2 coords = gl_GlobalInvocationID.xy / resolution;
	coords *= 2.0;
	coords -= 1.0;

	// apply projection transformations for ray dir
	vec3 ray_dir = (view_matrix * proj_matrix * vec4(coords, 1, 0)).xyz;
	ray_dir = normalize(ray_dir);
	//ray_dir = floor(ray_dir * 100) / 100.0;

	// ray marching stuff
	vec3 pos = position;
	vec3 act_color = vec3(0);
	vec3 color = vec3(-1.0);
	bool reflected = false;
	float affect = 1.0;
	vec3 normal = vec3(0);
	bool hit = true;
	bool warp = false;
	bool alr_warped = false;

	// debug stuff to view mip map iterations
	float total_iterations = 0.0;
	float total_mip_map_iterations = 0.0;
	float min_level_reached = 1000;

	for (int i = 0; i < max_iters; i++) {
		hit = true;
		total_iterations += 1;
		float voxel_distance = 0.0;

		// we know the map isn't *that* big
		if (any(greaterThan(pos, vec3(map_size))) || any(lessThan(pos, vec3(0)))) {
			hit = false;
			break;
		}

		// recursively go through the mip chain
		recurse(pos, ray_dir, hit, voxel_distance, min_level_reached);

		// gotta add a small offset since we'd be on the very face of the voxel
		pos += ray_dir * (0.001 + voxel_distance);
		
		// do all of our lighting calculations here
		if (hit) {
			bool int_hit = false;
			normal = (-(floor(pos) - pos + 0.5) / 0.5);
			act_color = lighting(pos, normal, ray_dir, voxel_distance, int_hit);

			if (int_hit) {
				break;
			}
		}
	}

	// ACTUAL GAME VIEW
	if (debug_selector == 0) {
		color = act_color;
	
		if (!hit) {
			color = sky(ray_dir) * affect;
		}
	}
	
	else if (debug_selector == 1) {
		vec2 dists = intersection(pos, ray_dir, vec3(0), vec3(map_size));
		color = (dists.y * ray_dir + pos) / vec3(map_size);
		
		//color = normal * affect;
	}
	else if (debug_selector == 2) {
		color = vec3(total_iterations / float(max_iters));
		hit = true;
	}
	else if (debug_selector == 3) {
		//color = vec3(total_mip_map_iterations / (float(max_iters) * selector));
		color = vec3(min_level_reached / float(selector));
		hit = true;
	}



	//color = vec3(gl_LocalInvocationID.xy, 0) / vec3(32);
	// store the value in the image that we will blit
	//imageStore(image, ivec2(gl_GlobalInvocationID.xy), vec4(vec2(gl_GlobalInvocationID.xy) / 800.0, abs(sin(gl_GlobalInvocationID.x)), 0));
	imageStore(image, ivec2(gl_GlobalInvocationID.xy), vec4(color, 0));
}