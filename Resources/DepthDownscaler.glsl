#version 460
layout(local_size_x = 32, local_size_y = 32, local_size_z = 1) in;
layout(r32f, binding = 0) uniform image2D native_res_depth;
layout(r32f, binding = 1) uniform image2D downscaled_depth;

void main() {
	float od = 10000.0;
	int scaler = 1;
	int factor = 3;
	for (int x = -scaler; x <= scaler; x++)
	{
		for (int y = -scaler; y <= scaler; y++)
		{
			float last_depth = imageLoad(native_res_depth, ivec2(gl_GlobalInvocationID.xy * 2) + ivec2(x, y) * factor).x;
			od = min(last_depth, od);
		}
	}

	
	imageStore(downscaled_depth, ivec2(gl_GlobalInvocationID.xy), vec4(od, 0, 0, 1.0));
}