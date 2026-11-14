shader_type spatial;
render_mode world_vertex_coords, shadows_disabled, depth_draw_opaque;
/**
 * FFT ocean surface. Lighting model and filtering adapted from 2Retr0/GodotOceanWaves (MIT), which follows the
 * 2019 GDC talk "Wakes, Explosions and Lighting: Interactive Water Simulation in Atlas".
 * Added here: clipmap level cut-outs, turquoise island shallows with shore surf, hull-contact foam.
 */

#define MAX_CASCADES 8
#define REFLECTANCE  0.02
#define MAX_ISLANDS  10

global uniform vec4 water_color : source_color;
global uniform vec4 foam_color : source_color;

uniform float roughness : hint_range(0.0, 1.0) = 0.4;
uniform float normal_strength : hint_range(0.0, 1.0) = 1.0;
uniform vec3 shallow_color : source_color = vec3(0.05, 0.62, 0.58);
uniform float shallow_band = 55.0;

uniform vec4 islands[MAX_ISLANDS]; // x, z, radius x, radius z (waterline ellipse)
uniform int island_count = 0;
uniform vec4 ship_a = vec4(0.0, 0.0, 1.0, 0.0); // x, z, cos(yaw), sin(yaw)
uniform vec2 ship_half = vec2(11.0, 3.2);       // half length, half beam (m)
#define HULL_BINS 48
uniform float hull_w[HULL_BINS];                // waterline half-width per bin, bow (index 0) .. stern (last)
uniform vec2 hull_z = vec2(-11.0, 11.0);        // local z of bin 0 (bow) and the last bin (stern)
uniform float ship_speed = 6.0;

group_uniforms cascade_data;
uniform vec4 map_scales[MAX_CASCADES]; // uv scale xy, displacement scale, normal scale
global uniform uint num_cascades;
global uniform sampler2DArray displacements;
global uniform sampler2DArray normals : hint_normal;

instance uniform vec4 inner_rect = vec4(1.0, 1.0, -1.0, -1.0);

varying vec2 rest_xz;
varying float wave_height;
varying float foam_factor;
varying float fresnel;
varying float shallow;
varying float shore_foam;
varying float hull_foam;

float island_distance(vec2 p) {
	float d = 1e5;
	for (int i = 0; i < MAX_ISLANDS; i++) {
		if (i >= island_count) break;
		vec4 isl = islands[i];
		vec2 q = (p - isl.xy) / isl.zw;
		d = min(d, (length(q) - 1.0) * 0.5 * (isl.z + isl.w));
	}
	return d;
}

void vertex() {
	UV = VERTEX.xz;
	rest_xz = VERTEX.xz;
	float distance_factor = min(exp(-(length(VERTEX.xz - CAMERA_POSITION_WORLD.xz) - 150.0) * 0.007), 1.0);
	vec3 displacement = vec3(0.0);
	for (uint i = 0U; i < num_cascades; ++i) {
		vec4 scales = map_scales[i];
		displacement += texture(displacements, vec3(UV * scales.xy, float(i))).xyz * scales.z;
	}
	VERTEX += displacement * distance_factor;
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

void fragment() {
	if (rest_xz.x > inner_rect.x && rest_xz.x < inner_rect.z && rest_xz.y > inner_rect.y && rest_xz.y < inner_rect.w) {
		discard;
	}
	vec3 world_pos = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float dist = length(world_pos - CAMERA_POSITION_WORLD);
	float map_size = float(textureSize(normals, 0).x);

	vec3 gradient = vec3(0.0);
	for (uint i = 0U; i < num_cascades; ++i) {
		vec4 scales = map_scales[i];
		vec3 coords = vec3(UV * scales.xy, float(i));
		float ppm = map_size * min(scales.x, scales.y);
		gradient += mix(texture_bicubic(normals, coords), texture(normals, coords), min(1.0, ppm * 0.1)).xyw * vec3(scales.ww, 1.0);
	}

	// Island shallows: turquoise water + surf line near the shore.
	float d_isl = island_distance(rest_xz);
	shallow = 1.0 - smoothstep(0.0, shallow_band, d_isl);
	float surf = exp(-max(d_isl, 0.0) * 0.18) * (0.55 + 0.45 * sin(d_isl * 0.7 - TIME * 1.1 + gradient.x * 6.0));
	shore_foam = clamp(surf * (1.0 - smoothstep(-2.0, 0.0, -d_isl)), 0.0, 1.0);

	// Hull contact foam: thin, broken band hugging the baked waterline outline (width profile along the hull).
	vec2 rel = rest_xz - ship_a.xy;
	float lx = dot(rel, vec2(ship_a.z, -ship_a.w)); // ship right (+x local)
	float lz = dot(rel, vec2(ship_a.w, ship_a.z));  // ship back (+z local)
	float u = clamp((lz - hull_z.x) / (hull_z.y - hull_z.x), 0.0, 1.0) * float(HULL_BINS - 1);
	int i0 = int(floor(u));
	int i1 = min(i0 + 1, HULL_BINS - 1);
	float hw = mix(hull_w[i0], hull_w[i1], fract(u));
	// Distance to the outline (outside > 0); past the bow/stern tips measure to the end point.
	float over = max(max(hull_z.x - lz, lz - hull_z.y), 0.0);
	float d = length(vec2(max(abs(lx) - hw, 0.0), over)) + min(abs(lx) - hw, 0.0) * 0.0;
	float speed_k = clamp(ship_speed / 7.0, 0.0, 1.3);
	float bow_k = 1.0 - smoothstep(0.0, 0.45, u / float(HULL_BINS - 1)); // 1 at the bow, 0 amidships/stern
	float band_out = 0.28 + 0.9 * bow_k * speed_k;                      // wider only at the bow when fast
	float inside = 1.0 - smoothstep(-0.25, 0.05, d - 0.0) * 0.0;
	float band = smoothstep(-0.35, 0.0, d) * (1.0 - smoothstep(0.05, band_out, d));
	float lace = sin(lz * 3.3 + TIME * 2.6 + gradient.y * 11.0) * sin(lx * 4.1 - TIME * 2.0 + gradient.x * 10.0);
	float broken = smoothstep(-0.15, 0.55, lace + 0.25 + 0.5 * bow_k * speed_k);
	hull_foam = band * broken * (0.30 + 0.55 * speed_k * (0.4 + 0.6 * bow_k));

	float whitecap = smoothstep(0.0, 1.0, gradient.z * 0.75) * exp(-dist * 0.0035);
	foam_factor = clamp(whitecap * (1.0 - 0.7 * shallow) + shore_foam * 0.9 + hull_foam, 0.0, 1.0);

	vec3 deep = water_color.rgb;
	vec3 base = mix(deep, shallow_color * 0.55, shallow * 0.9);
	ALBEDO = mix(base, foam_color.rgb, foam_factor);

	gradient *= mix(0.015, normal_strength, exp(-dist * 0.0175));
	NORMAL = (VIEW_MATRIX * vec4(normalize(vec3(-gradient.x, 1.0, -gradient.y)), 0.0)).xyz;

	fresnel = mix(pow(1.0 - dot(VIEW, NORMAL), 5.0 * exp(-2.69 * roughness)) / (1.0 + 22.7 * pow(roughness, 1.5)), 1.0, REFLECTANCE);
	ROUGHNESS = (1.0 - fresnel) * foam_factor + 0.4;
}

float smith_masking_shadowing(in float cos_theta, in float alpha) {
	float a = cos_theta / (alpha * sqrt(1.0 - cos_theta * cos_theta));
	float a_sq = a * a;
	return a < 1.6 ? (1.0 - 1.259 * a + 0.396 * a_sq) / (3.535 * a + 2.181 * a_sq) : 0.0;
}

float ggx_distribution(in float cos_theta, in float alpha) {
	float a_sq = alpha * alpha;
	float d = 1.0 + (a_sq - 1.0) * cos_theta * cos_theta;
	return a_sq / (PI * d * d);
}

void light() {
	vec3 halfway = normalize(LIGHT + VIEW);
	float dot_nl = max(dot(NORMAL, LIGHT), 2e-5);
	float dot_nv = max(dot(NORMAL, VIEW), 2e-5);

	float light_mask = smith_masking_shadowing(roughness, dot_nv);
	float view_mask = smith_masking_shadowing(roughness, dot_nl);
	float microfacet_distribution = ggx_distribution(dot(NORMAL, halfway), roughness);
	float geometric_attenuation = 1.0 / (1.0 + light_mask + view_mask);
	SPECULAR_LIGHT += fresnel * microfacet_distribution * geometric_attenuation / (4.0 * dot_nv + 0.1) * ATTENUATION;

	const vec3 sss_modifier = vec3(0.9, 1.15, 0.85);
	float sss_height = 1.0 * max(0.0, wave_height + 2.5) * pow(max(dot(LIGHT, -VIEW), 0.0), 4.0) * pow(0.5 - 0.5 * dot(LIGHT, NORMAL), 3.0);
	float sss_near = 0.5 * pow(dot_nv, 2.0);
	float lambertian = 0.5 * dot_nl;
	vec3 sss_tint = mix(vec3(1.0), vec3(0.6, 1.3, 1.2), shallow);
	DIFFUSE_LIGHT += mix((sss_height + sss_near) * sss_modifier * sss_tint / (1.0 + light_mask) + lambertian, foam_color.rgb, foam_factor) * (1.0 - fresnel) * ATTENUATION * LIGHT_COLOR;
}
