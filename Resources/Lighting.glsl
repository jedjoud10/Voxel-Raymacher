#include Hashes.glsl

// simple lighting calculation for the sky background
vec3 sky(vec3 normal) {
	return texture(skybox, normal).xyz;
}

// simple lighting calculation stuff for when we hit a voxel
vec3 lighting(vec3 pos, vec3 normal, vec3 ray_dir) {
	vec3 small = floor(pos * 4);
	vec3 smooth_normal = (-(floor(pos * 4) - (pos * 4) + 0.5) / 0.5);
	smooth_normal = normalize(smooth_normal);
	vec3 internal = floor(pos * 4.0) / 4.0;
	vec3 light_dir = normalize(vec3(1, 1, 1));

	float light = clamp(dot(normal, light_dir), 0, 1) + 0.3;
	vec3 color = vec3(1);
	color = (normal.y > 0.5 ? vec3(17, 99, 0) : vec3(48, 36, 0));

	//return vec3(pow(dot(reflect(ray_dir, normal), light_dir), 10));
	//return (color / 255.0) * (hash13(small) * 0.3 + 0.7);
	return sky(normal);
	//return (color / 255.0) * light;
}