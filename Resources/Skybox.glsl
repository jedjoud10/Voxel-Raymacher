#version 460 core
#include Noise.glsl

layout(local_size_x = 32, local_size_y = 32, local_size_z = 1) in;
layout(rgba8, binding = 0, location = 0) uniform imageCube skybox;
layout(location = 1) uniform mat4 proj_view_matrix;
layout(location = 2) uniform int resolution;
layout(location = 3) uniform int side;

void main() {
    // Convert coordinates to -1 - 1 coordinates
    vec2 coords = vec2(gl_GlobalInvocationID.xy);
    vec3 ndc = vec3(coords.x / resolution, coords.y / resolution, 1);
    ndc.xy = ndc.xy * 2 - 1;

    // Convert the NDC coordinate to a world space normal 
    vec3 normal = normalize((proj_view_matrix * vec4(ndc, 0)).xyz);

	imageStore(skybox, ivec3(gl_GlobalInvocationID.xy, side), vec4(normal, 0.0));
}