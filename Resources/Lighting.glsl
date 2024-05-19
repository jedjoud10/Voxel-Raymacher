#include Hashes.glsl

// simple lighting calculation for the sky background
vec3 sky(vec3 normal) {
	return texture(skybox, normal).xyz;
}

// simple lighting calculation stuff for when we hit a voxel
/*
layout(location = 20) uniform float ambient_strength;
layout(location = 21) uniform float normal_map_strength;
layout(location = 22) uniform float gloss_strength;
layout(location = 23) uniform float specular_strength;
layout(location = 24) uniform vec3 top_color;
layout(location = 25) uniform vec3 side_color;
*/

vec3 aces(vec3 x) {
	const float a = 2.51;
	const float b = 0.03;
	const float c = 2.43;
	const float d = 0.59;
	const float e = 0.14;
	return clamp((x * (a * x + b)) / (x * (c * x + d) + e), 0.0, 1.0);
}

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
	//vec3 rand = vec3(hash13(larger) * 0.1 + hash13(medium) * 0.2 + 0.7) * (hash33(small)-0.5)*2;
	//normal += rand * normal_map_strength;
	//normal = normalize(normal);

	vec3 diffuse = normal.y > 0.5 ? top_color : side_color;
	//diffuse *= (hash13(medium) * 0.2 + 0.7) * (hash33(small) - 0.5) * 2;
	diffuse *= (hash13(medium) * 0.2 + 0.8) * (hash33(small) * 0.2 + 0.8);
	
	// diffuse lighting
	float light = clamp(dot(normal, light_dir), 0, 1);

	// ambient
	vec3 ambient = sky(ray_dir);

	// gloss
	float gloss = 1 - dot(reflect(ray_dir, normal), normal);
	gloss = max(pow(gloss, 3), 0);

	// specular
	vec3 hw = normalize(light_dir - ray_dir);
	float specular = pow(max(dot(hw, normal), 0), 20);

	//return gloss;
	//return diffuse;
	//return diffuse + ambient * ambient_strength + vec3(gloss * gloss_strength) + vec3(specular * specular_strength);
	vec3 outpute = 1.4 * diffuse * light + diffuse * ambient * ambient_strength + vec3(gloss * gloss_strength) + vec3(specular * specular_strength);
	return outpute;
}