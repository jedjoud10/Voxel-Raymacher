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

	vec2 distances = intersection(ray_dir, vec3(-1), vec3(1));
	float t = distances.y - distances.x;
	 
	/*
	if (t > 0.0) {
		color = vec3(distances.x * ray_dir + t * ray_dir);
	}
	*/

	for (int i = 0; i < 128; i++) {
		vec2 distances = intersection(ray_dir, floor(pos), floor(pos) + vec3(1));
		float t = distances.y - distances.x;
		pos += ray_dir * (0.001 + t);

		vec3 grid_point = floor(mod(vec3(pos), vec3(map_size, 100000, map_size)));
		uint v0 = imageLoad(voxels[0], ivec3(grid_point)).x;
		
		if (v0 == 0) {
			vec3 normal = (floor(pos) - pos + 0.5) / 0.5;
			color = normal;
			break;
		}
	}

	if (all(color == vec3(-1))) {
		color = ray_dir;
	}
	
	// store the value in the image that we will blit
	imageStore(image, ivec2(gl_GlobalInvocationID.xy), vec4(color, 0));
}