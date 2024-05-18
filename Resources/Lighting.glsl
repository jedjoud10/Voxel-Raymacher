#include Hashes.glsl

// simple lighting calculation for the sky background
vec3 sky(vec3 normal) {
	return texture(skybox, normal).xyz;
}

// simple lighting calculation stuff for when we hit a voxel
vec3 lighting(vec3 pos, vec3 normal, vec3 ray_dir) {
	vec3 small = floor(pos * 16);
	vec3 medium = floor(pos * 4);
	vec3 large = floor(pos * 1);
	vec3 larger = floor(pos * 0.25);

	/*
	vec3 smooth_normal = (-(floor(pos * 4) - (pos * 4) + 0.5) / 0.5);
	smooth_normal = normalize(smooth_normal);
	vec3 internal = floor(pos * 4.0) / 4.0;
	*/
	vec3 rand = (hash33(small)-0.5)*2;
	if (normal.y < 0.5) {
		normal += rand * 0.2;
	}
	normal = normalize(normal);

	// diffuse lighting
	float light = clamp(dot(normal, light_dir), 0, 1) + 0.3;
	vec3 diffuse = (normal.y > 0.5 ? vec3(17, 99, 0) : vec3(48, 36, 0)) / 255.0;
	diffuse *= (length(rand) * 0.4 + 0.6) * light;

	// random colors!!!
	diffuse *= vec3(hash13(larger) * 0.1 + hash13(medium) * 0.2 + 0.7);

	// ambient
	vec3 ambient = sky(ray_dir);

	// gloss
	float gloss = 1 - dot(reflect(ray_dir, normal), normal);
	gloss = clamp(pow(gloss, 3), 0, 1);

	//return gloss;
	//return vec3(light);
	return diffuse + ambient * 0.1f + vec3(gloss * 0.2);
}