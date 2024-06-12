#version 460 core

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;
layout(location = 1) uniform int side;
layout(rgba8, binding = 0, location = 0) uniform imageCube skybox;

void main() {
	imageStore(skybox, ivec3(gl_GlobalInvocationID.xy, side), vec4(1));
}