#[compute]
#version 460
/**
 * Local addition (not in the upstream addon): one box-filter downsample step of the normal/foam map.
 * Dispatched per cascade for each mip level after fft_unpack; src = level L-1, dst = level L (rgba16f image2D views of one
 * array layer and one mip). Slopes are linear, so averaging them is the correct filter; foam averages the same way.
 */

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(rgba16f, set = 0, binding = 0) restrict readonly uniform image2D src_level;
layout(rgba16f, set = 0, binding = 1) restrict writeonly uniform image2D dst_level;

void main() {
	ivec2 dst_size = imageSize(dst_level);
	ivec2 id = ivec2(gl_GlobalInvocationID.xy);
	if (id.x >= dst_size.x || id.y >= dst_size.y) { return; }
	ivec2 s = id * 2;
	vec4 v = imageLoad(src_level, s) + imageLoad(src_level, s + ivec2(1, 0))
		+ imageLoad(src_level, s + ivec2(0, 1)) + imageLoad(src_level, s + ivec2(1, 1));
	imageStore(dst_level, id, v * 0.25);
}
