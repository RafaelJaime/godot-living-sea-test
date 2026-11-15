// Surface: vertex displacement and normal-map sampling helpers. Owner: M2a (normal mips) / M2b (wake ridge normals).
void vertex() {
	UV = VERTEX.xz;
	rest_xz = VERTEX.xz;
	float distance_factor = min(exp(-(length(VERTEX.xz - CAMERA_POSITION_WORLD.xz) - 150.0) * 0.007), 1.0);
	vec3 displacement = vec3(0.0);
	for (uint i = 0U; i < num_cascades; ++i) {
		vec4 scales = map_scales[i];
		displacement += texture(displacements, vec3((UV + cascade_shift[i]) * scales.xy, float(i))).xyz * scales.z;
	}
	VERTEX += displacement * distance_factor;
	VERTEX.y -= lod_bias;
	wave_height = displacement.y;
}

vec4 cubic_weights(float a) {
	float a2 = a * a;
	float a3 = a2 * a;
	float w0 = -a3 + a2 * 3.0 - a * 3.0 + 1.0;
	float w1 = a3 * 3.0 - a2 * 6.0 + 4.0;
	float w2 = -a3 * 3.0 + a2 * 3.0 + a * 3.0 + 1.0;
	float w3 = a3;
	return vec4(w0, w1, w2, w3) / 6.0;
}

vec4 texture_bicubic(in sampler2DArray sampler, in vec3 uvw) {
	vec2 dims = vec2(textureSize(sampler, 0).xy);
	vec2 dims_inv = 1.0 / dims;
	uvw.xy = uvw.xy * dims + 0.5;
	vec2 fuv = fract(uvw.xy);
	vec4 wx = cubic_weights(fuv.x);
	vec4 wy = cubic_weights(fuv.y);
	vec4 g = vec4(wx.xz + wx.yw, wy.xz + wy.yw);
	vec4 h = (vec4(wx.yw, wy.yw) / g + vec2(-1.5, 0.5).xyxy + floor(uvw.xy).xxyy) * dims_inv.xxyy;
	vec2 w = g.xz / (g.xz + g.yw);
	return mix(
		mix(texture(sampler, vec3(h.yw, uvw.z)), texture(sampler, vec3(h.xw, uvw.z)), w.x),
		mix(texture(sampler, vec3(h.yz, uvw.z)), texture(sampler, vec3(h.xz, uvw.z)), w.x), w.y);
}


// Cat's paws (M4c1): darker, glassier ripple patches where WindField's gust factor exceeds 1. The texel holds the raw gust noise
// n = texel * 2 - 1; the factor is rebuilt exactly like WindField.gust_factor() (shallow lulls, sharp gusts). gust_win is
// (origin x, origin z, size x, size z) in world metres and already follows the advection between texture refreshes.
global uniform sampler2D gust_tex : filter_linear, repeat_disable;
global uniform vec4 gust_win;
global uniform float gust_amp;
uniform float cat_paw_gain = 1.5; // 0 = off; default is the subtle look approved with captures, --catpaw=<gain> overrides

float gust_patch(vec2 world_xz, float dist) {
	vec2 uv = (world_xz - gust_win.xy) / gust_win.zw;
	vec2 edge = smoothstep(vec2(0.0), vec2(0.08), uv) * (1.0 - smoothstep(vec2(0.92), vec2(1.0), uv));
	float n = texture(gust_tex, uv).r * 2.0 - 1.0;
	float g = 1.0 + gust_amp * (n > 0.0 ? n * 1.6 : n * 0.9);
	float w = smoothstep(0.12, 0.6, g - 1.0); // only the stronger gusts (~25 % of the water), full strength at factor 1.6
	return w * edge.x * edge.y * (1.0 - smoothstep(250.0, 700.0, dist));
}
