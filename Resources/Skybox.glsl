#version 460 core
#include Noise.glsl

layout(local_size_x = 32, local_size_y = 32, local_size_z = 1) in;
layout(rgba8, binding = 0, location = 0) uniform imageCube skybox;
layout(location = 1) uniform mat4 proj_view_matrix;
layout(location = 2) uniform int resolution;
layout(location = 3) uniform int side;
layout(location = 4) uniform float time;
layout(location = 5) uniform vec3 sun;


void main() {
    // convert coordinates to -1 - 1 coordinates
    vec2 coords = vec2(gl_GlobalInvocationID.xy);
    vec3 ndc = vec3(coords.x / resolution, coords.y / resolution, 1);
    ndc.xy = ndc.xy * 2 - 1;

    // convert the NDC coordinate to a world space normal 
    vec3 normal = normalize((proj_view_matrix * vec4(ndc, 0)).xyz);
    normal.z *= -1;

    // some very cool lighting calculations
    vec3 b1 = vec3(191, 230, 255) / 255.0;
    vec3 b2 = vec3(99, 194, 255) / 255.0;
    vec3 b3 = vec3(19, 65, 138) / 255.0;
    
    /*
    vec3 b1 = vec3(82, 19, 171) / 255.0;
    vec3 b2 = vec3(194, 83, 39) / 255.0;
    vec3 b3 = vec3(194, 80, 39) / 255.0;
    */
    vec3 color = mix(b1, b2, normal.y + snoise(normal * 4) * 0.1);
    color = mix(color, b3, clamp(normal.y * 0.8 - 0.85 + snoise(normal * 5 - vec3(1,0,1) * time * 1) * 0.05, 0, 1));
    color += mix(-snoise(normal * 3.0 * vec3(1, 0, 1) + time * 1.2), 0, clamp(1-normal.y, 0, 1)) * 0.05;
    
    float bruh = dot(normal, normalize(sun));
    color += vec3(pow(max(bruh-0.1, 0), 16));

    //color = mix(color, vec3(0.1), clamp(-normal.y*30-0.,0,1));

	imageStore(skybox, ivec3(gl_GlobalInvocationID.xy, side), vec4(color, 0.0));
}