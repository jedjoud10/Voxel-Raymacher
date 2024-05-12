#version 460
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
layout(location = 8) uniform int debug_selector;
layout(location = 9) uniform int max_iters;
//shared vec3 shared_pos[32][32];

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

// recrusviely go through the mip chain
void recurse(vec3 pos, vec3 ray_dir, inout bool hit, inout float voxel_distance) {
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
			break;
		}
	}
}

// hehehehe shadow mapping...
bool shadow(vec3 pos, inout vec3 last) {
	vec3 sun_dir = normalize(vec3(1, 1, 1));
	pos += sun_dir * 0.1;

	for (int i = 0; i < 32; i++) {
		if (any(greaterThan(pos, vec3(map_size))) || any(lessThan(pos, vec3(0)))) {
			return false;
		}
		
		bool hit = true;
		float distance = 0.0;

		recurse(pos, sun_dir, hit, distance);
		pos += sun_dir * (0.001 + distance);
		last = pos;

		if (hit) {
			return true;
		}
	}

	return false;
}

// simple lighting calculation stuff for when we hit a voxel
vec3 lighting(vec3 pos, vec3 normal) {
	vec3 internal = floor(pos * 8.0) / 8.0;
	vec3 color = vec3(1);

	//uvec2 test_id = gl_LocalInvocationID.xy;
	//shared_pos[test_id.x][test_id.y] = pos;

	//memoryBarrierShared();
	//groupMemoryBarrier();
	//barrier();

	//vec3 derFdX = shared_pos[test_id.x + 1][test_id.y + 0] - shared_pos[test_id.x + 0][test_id.y + 0];
	//vec3 derFdY = shared_pos[test_id.x + 0][test_id.y + 1] - shared_pos[test_id.x + 0][test_id.y + 0];
	
	// check if the texel above us is empty
	ivec3 tex_point = ivec3(floor(mod(pos, vec3(map_size, 100000, map_size))));
	if (imageLoad(voxels[0], tex_point + ivec3(0, 1, 0)).x == 0 && normal.y > 0.900f) {
		color = vec3(17, 99, 0);
	}
	else {
		color = vec3(48, 36, 0);
	}

	/*
	vec3 last = pos;
	if (shadow(pos, last)) {
		color *= 0.2;
	}
	*/

	float randomized = clamp(10.0 / distance(pos, position), 0.0, 0.6);
	return color * (hash13(internal * 2.43531f) * randomized + (1 - randomized)) / 255.0;
}

// simple lighting calculation for the sky background
vec3 sky(vec3 normal) {
	// Get up component of vector and remap to 0 - 1 range
	float up = normal.y * 0.5 + 0.5;

	// Define color mapping values
	const vec3 dark_blue = pow(vec3(0.137,0.263,0.463) * 0.5, vec3(2.2));
	const vec3 light_blue = pow(vec3(0.533,0.733,0.857), vec3(2.2));
	const vec3 orange = pow(vec3(247.0, 134.0, 64.0) / 255.0, vec3(2.2));

	// Do some color mapping (day color)
	vec3 day_color = mix(light_blue, dark_blue, max(up, 0.0));

	// Do some color mapping (sunset color)
	vec3 sunset_color = mix(orange, light_blue, max(up, 0.2));

	return sunset_color;
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
		recurse(pos, ray_dir, hit, voxel_distance);

		// gotta add a small offset since we'd be on the very face of the voxel
		pos += ray_dir * (0.001 + voxel_distance);
		
		// do all of our lighting calculations here
		if (hit) {
			normal = (-(floor(pos) - pos + 0.5) / 0.5);
			act_color = lighting(pos, normal);
			break;
		}
	}

	if (debug_selector == 0) {
		color = act_color;
	}
	else if (debug_selector == 1) {
		color = normal * affect;
	}
	else if (debug_selector == 2) {
		color = vec3(total_iterations / float(max_iters));
		hit = true;
	}
	else if (debug_selector == 3) {
		color = vec3(total_mip_map_iterations / (float(max_iters) * selector));
		hit = true;
	}

	if (!hit) {
		color = sky(ray_dir) * affect;
	}

	//color = vec3(gl_LocalInvocationID.xy, 0) / vec3(32);
	// store the value in the image that we will blit
	imageStore(image, ivec2(gl_GlobalInvocationID.xy), vec4(color, 0));
}