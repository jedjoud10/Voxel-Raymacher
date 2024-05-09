#version 450 core

layout(local_size_x = 32, local_size_y = 32, local_size_z = 1) in;
layout(rgba8, binding = 0) uniform image2D image;
layout(r32ui, binding = 1) uniform uimage3D voxels[4];
layout(location = 1) uniform vec2 resolution;
layout(location = 2) uniform mat4 view_matrix;
layout(location = 3) uniform mat4 proj_matrix;
layout(location = 4) uniform vec3 position;

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
	vec3 color = vec3(0.2);
	/*
	float f = 1.0;
	for (int i = 0; i < 128; i++) {
		float dist = sdf(pos) * f;
		pos += ray_dir * dist;

		vec3 c = vec3(20, 0, 0);
		float r = length(pos - c);
		if (r < 14.0) {
			ray_dir += ((normalize(pos - c)) / r);
			ray_dir = normalize(ray_dir);
			f = 0.2;
		}

		if (dist < 0.02) {
			//color = vec3(i / 128.0);
			color = lighting(pos);
			break;
		}
	}
	*/

	//color = imageLoad(voxels, ivec3(gl_GlobalInvocationID.xy, 0)).xyz;
	float stepsize = 1.0;
	int total = 0;

	for (int i = 0; i < 512; i++) {
		pos += ray_dir * stepsize * 0.2;

		/*
		int a = 0;
		
		for (int j = 0; j >= 0; j--) {
			float factorino = pow(2, j);
			uint bruh = imageLoad(voxels[j], ivec3(round(pos / factorino))).x;
			//stepsize = j+1;
			total += 1;

			if (bruh == 0) {
				break;
			}

			if (j == 0 && bruh == 1) {
				a = 1;
				break;
			}
		}



		if (a == 1 && all(greaterThan(pos, vec3(0))) && all(lessThan(pos, vec3(64)))) {
			//color = vec3(lodmoment / 4.0);
			color = fract(pos - 0.5);
			break;
		}
		*/

		if (imageLoad(voxels[0], ivec3(pos)).x == 1) {
			color = fract(pos-0.5);
			break;
		}

		if (pos.y < 0.0) {
			float value = fract((floor(pos.x * 10) + floor(pos.z * 10)) * 0.5) * 2.0;
			float value2 = fract((floor(pos.x) + floor(pos.z)) * 0.5) * 2.0;
			value *= value2;
			color = vec3(value) * pos;
			break;
		}
	}

	//color *= vec3(float(total) / 400.0);


	// store the value in the image that we will blit
	imageStore(image, ivec2(gl_GlobalInvocationID.xy), vec4(color, 0));
}