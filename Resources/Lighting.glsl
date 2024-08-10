#include Hashes.glsl

// simple lighting calculation stuff for when we hit a voxel
/*
layout(location = 20) uniform float ambient_strength;
layout(location = 21) uniform float normal_map_strength;
layout(location = 22) uniform float gloss_strength;
layout(location = 23) uniform float specular_strength;
layout(location = 24) uniform vec3 top_color;
layout(location = 25) uniform vec3 side_color;
*/

#define PI 3.1415926538

// Literally the whole implementation is stolen from
// https://www.youtube.com/watch?v=RRE-F57fbXw&ab_channel=VictorGordan
// and https://learnopengl.com/PBR/Lighting

// Normal distribution function
// GGX/Trowbridge-reitz model
float ndf(float roughness, vec3 n, vec3 h) {
	float a = roughness * roughness;
	float a2 = a * a;

	float n_dot_h = max(dot(n, h), 0.0);	
	float n_dot_h2 = n_dot_h * n_dot_h;	

	float semi_denom = n_dot_h2 * (a2 - 1.0) + 1.0;
	float denom = PI * semi_denom * semi_denom;
	return a2 / denom;
}

// Schlick/GGX model
float g1(float k, vec3 n, vec3 x) {
	float num = max(dot(n, x), 0);
	float denom = num * (1 - k) + k;
	return num / denom;
}

// Smith model
float gsf(float roughness, vec3 n, vec3 v, vec3 l) {
	float r = (roughness + 1.0);
    float k = (r*r) / 8.0;
	return g1(k, n, v) * g1(k, n, l);
}

// Fresnel function
vec3 fresnel(vec3 f0, vec3 h, vec3 v) {
	float cosTheta = max(dot(h, v), 0.0);
    return f0 + (1.0 - f0) * pow (1.0 - cosTheta, 5.0);
}

// Fresnel function with roughness
vec3 fresnelRoughness(vec3 f0, vec3 v, vec3 x, float roughness) {
	float cosTheta = clamp(1.0 - max(dot(v, x), 0), 0, 1);
	return f0 + (max(vec3(1.0 - roughness), f0) - f0) * pow(cosTheta, 5.0);
}

// Cook-torrence model for specular
vec3 specular(vec3 f0, float roughness, vec3 v, vec3 l, vec3 n, vec3 h) {
	vec3 num = ndf(roughness, n, h) * gsf(roughness, n, v, l) * fresnel(f0, h, v);
	float denom = 4 * max(dot(v, n), 0.0) * max(dot(l, n), 0.0) + 0.0001;
	return num;
}

// Sun data struct
struct SunData {
	vec3 backward;
	vec3 color;
};

// Camera data struct
struct CameraData {
	vec3 view;
	vec3 half_view;
	vec3 position;
};

// Surface data struct 
struct SurfaceData {
	vec3 diffuse;
	vec3 normal;
	vec3 position;
	float roughness;
	float metallic;
	float visibility;
	vec3 f0;
};

// Bidirectional reflectance distribution function, aka PBRRRR
vec3 brdf(
	SurfaceData surface,
	CameraData camera,
	SunData light,
	float shadowed
) {
	// Calculate kS and kD
	vec3 ks = fresnelRoughness(surface.f0, camera.half_view, camera.view, surface.roughness);
	vec3 kd = (1 - ks) * (1 - surface.metallic);
	
	vec3 specular = specular(surface.f0, surface.roughness, camera.view, light.backward, surface.normal, camera.half_view);
	vec3 brdf = kd * (surface.diffuse) + specular + fresnel(surface.f0, camera.half_view, camera.view);
	vec3 lighting = vec3(max(dot(light.backward, surface.normal), 0.0)) * (1 - shadowed);
	brdf *= lighting * light.color;

	// Diffuse Irradiance IBL
	//vec3 irradiance = texture(samplerCube(ibl_diffuse_map, ibl_diffuse_map_sampler), surface.normal).xyz;
	vec3 ambient = texture(skybox, surface.normal).xyz * surface.visibility;
	// + vec3(clamp(dot(reflect(camera.view, surface.normal), camera.view), 0, 1)) * 0.04
	return brdf + ambient * ambient_strength;
}

// https://gamedev.stackexchange.com/questions/92015/optimized-linear-to-srgb-glsl
// Converts a color from linear light gamma to sRGB gamma
vec3 from_linear(vec3 linearRGB)
{
    bvec3 cutoff = lessThan(linearRGB, vec3(0.0031308));
    vec3 higher = vec3(1.055)*pow(linearRGB, vec3(1.0/2.4)) - vec3(0.055);
    vec3 lower = linearRGB * vec3(12.92);
    return mix(higher, lower, cutoff);
}

vec3 aces(vec3 x) {
	const float a = 2.51;
	const float b = 0.03;
	const float c = 2.43;
	const float d = 0.59;
	const float e = 0.14;
	return clamp((x * (a * x + b)) / (x * (c * x + d) + e), 0.0, 1.0);
}

vec3 lighting(vec3 pos, vec3 normal, vec3 ray_dir, float shadowed) {
	normal = normalize(normal);
	vec3 albedo = vec3(0.7);
	albedo = normal.y > 0.5 ? pow(top_color, vec3(2.2)) : pow(side_color, vec3(2.2));

	float roughness = 0.4 * roughness_strength;
	float metallic = 0.2 * metallic_strength;
	float visibility = 1;	

	// Create the data structs
	vec3 f0 = mix(vec3(0.04), albedo, metallic);
	SunData sun = SunData(light_dir, vec3(1));
	SurfaceData surface = SurfaceData(albedo, normal, pos, roughness, metallic, visibility, f0);
	vec3 view = normalize(position - pos);
	CameraData camera = CameraData(view, normalize(view + light_dir), position);
	vec3 color = brdf(surface, camera, sun, shadowed);

	return aces(color);
}