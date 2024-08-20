# GPU Voxel Raymarcher
This is a small voxel raymarcher that I started working a few months ago.
The code is very very **VERY** bad so don't expect much, but it works fine for experimentation for now at least.
I'm in the process of rewriting this project in ``rust-gpu`` so I won't be updating this repo for a while, until I get a proper voxel raymarcher working in the rust version

I made a video about this and the main optimizations that I implemented
(implemented just based on knowing what could slow down the GPU, wasn't able to profile as I'm using opengl and not vulkan)
Video: https://youtu.be/Wzo-LqPfMPE

[Depth Reprojection Optimization Blog](https://jedjoud10.github.io/blog/depth-reproj/)
