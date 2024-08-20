# GPU Voxel Raymarcher
This is a small voxel raymarcher that I started working a few months ago.
The code is very very **VERY** bad so don't expect much, but it works fine for experimentation for now at least. I didn't spend an ounce of effort to make it clean or performant (other than the main optimizations).
I'm in the process of rewriting this project in ``rust-gpu`` so I won't be updating this repo for a while, until I get a proper voxel raymarcher working in the rust version.

Main Controls:
* W/A/S/D to move camera
* Hold left control to slow down
* Camera rotation using mouse
* F5 to toggle fullscreen
* F4 to toggle mouse grabbing
* F3 to capture JPG screenshot
* Stuff can be changed / toggled through the imgui library window

I made a video about this and the main optimizations that I implemented. I wrote these just based on knowing what could slow down the GPU, as I wasn't able to properly profile 
(I'm using opengl and not vulkan)

Video: https://youtu.be/Wzo-LqPfMPE

** WARNING **
I do have to warn you though, since the whole system is using an iterative approach for reflections, in some cases the GPU driver could crash due to long "wait" times. I never had these happen on *my* GPU but just be careful.
I really gotta optimize this lel.

[Depth Reprojection Optimization Blog](https://jedjoud10.github.io/blog/depth-reproj/)

Requirements to run:
* OpenGL 4.6, with support for GL_ARB_gpu_shader_int64
* ~~Sparse Textures Support~~ don't even work on my 780m so I toggled them off in the code


Credits / Tools used:
* [imgui](https://github.com/ocornut/imgui)
* OpenGL and GLSL
* [OpenTK](https://github.com/opentk/opentk)
* [Imgui / OpenTK controller](https://github.com/NogginBops/ImGui.NET_OpenTK_Sample)
