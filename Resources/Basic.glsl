﻿#version 450 core

layout(local_size_x = 32, local_size_y = 32, local_size_z = 1) in;
layout(rgba8, binding = 0) uniform image2D image;
layout(r32ui, binding = 1) uniform uimage3D voxels[7];
layout(location = 1) uniform vec2 resolution;
layout(location = 2) uniform mat4 view_matrix;
layout(location = 3) uniform mat4 proj_matrix;
layout(location = 4) uniform vec3 position;
layout(location = 5) uniform int selector;

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

	for (int i = 0; i < 256; i++) {
		pos += ray_dir * stepsize * 0.2;
		
		int a = 0;

		if (pos.y < 20) {
			ray_dir = reflect(ray_dir, vec3(0, 1, 0)) + hash32(coords * 30) * 0.1;
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
			ivec3 aaa = ivec3(floor(mod(vec3(pos), vec3(128, 100000, 128)) / factorino));
			//aaa = ivec3();
			uint bruh = imageLoad(voxels[j], aaa).x;
			//stepsize = (j+1) * 3;
			total += 1;

			if (bruh == 0) {
				stepsize = factorino;
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
				ivec3 aaa = ivec3(floor(mod(vec3(pos), vec3(128, 100000, 128))));
				pos += -ray_dir * 0.03;
				if (imageLoad(voxels[0], aaa).x == 0) {
					break;
				}
			}

			vec3 normal = normalize(floor(pos) - pos + 0.5);
			color = normal * affect;
			//color = vec3(i) / vec3(512.0);
			float value = fract((floor(pos.x * 10) + floor(pos.z * 10) + floor(pos.y * 10)) * 0.5) * 2.0;
			float value2 = fract((floor(pos.x) + floor(pos.z) + floor(pos.y)) * 0.5) * 2.0;
			value *= value2;
			//color *= vec3(value);
			break;
		}

		last_pos = pos;
	}

	if (all(color == vec3(-1))) {
		color = ray_dir;
	}

	//color *= vec3(float(total) / 200.0);
	color *= vec3(float(total) / 200.0);
	//color = i / 64.0;
	//color = imageLoad(voxels[0], ivec3(gl_GlobalInvocationID.xy, 0)).xyz;

	// store the value in the image that we will blit
	imageStore(image, ivec2(gl_GlobalInvocationID.xy), vec4(color, 0));
}