#version 460 core
#include Noise.glsl

layout(local_size_x = 32, local_size_y = 32, local_size_z = 1) in;
layout(rgba8, binding = 0, location = 0) uniform imageCube skybox;
layout(location = 1) uniform mat4 proj_view_matrix;
layout(location = 2) uniform int resolution;
layout(location = 3) uniform int side;

void main() {
    // convert coordinates to -1 - 1 coordinates
    vec2 coords = vec2(gl_GlobalInvocationID.xy);
    vec3 ndc = vec3(coords.x / resolution, coords.y / resolution, 1);
    ndc.xy = ndc.xy * 2 - 1;

    // convert the NDC coordinate to a world space normal 
    vec3 normal = normalize((proj_view_matrix * vec4(ndc, 0)).xyz);

    // some very cool lighting calculations
    vec3 light_blue = vec3(191, 230, 255) / 255.0;
    vec3 dark_blue = vec3(99, 194, 255) / 255.0;
    vec3 color = mix(light_blue, dark_blue, normal.y);
    //color = mix(color, vec3(0.1), clamp(-normal.y*30-0.,0,1));

	imageStore(skybox, ivec3(gl_GlobalInvocationID.xy, side), vec4(color, 0.0));
}