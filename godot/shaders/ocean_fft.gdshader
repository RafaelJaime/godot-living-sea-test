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
uniform float hull_foam_gain = 1.0;
uniform float debug_mode = 0.0;
uniform bool hull_volume_on = false;
uniform mat4 hull_inv;                          // world -> ship pivot space (full pose: yaw, pitch, roll, heave)
uniform sampler2D hull_tex : filter_linear, repeat_disable; // W(z, y) = max |x| of the hull cross-section
uniform vec4 hull_dims = vec4(-1.0, 1.0, -1.0, 1.0);        // z0, z1, y0, y1 of the table (pivot space)

group_uniforms cascade_data;
uniform vec2 cascade_shift[MAX_CASCADES]; // world offset (rebase shifts) modulo each cascade tile, metres: tile sizes are free
uniform vec4 map_scales[MAX_CASCADES]; // uv scale xy, displacement scale, normal scale
global uniform uint num_cascades;
global uniform sampler2DArray displacements;
global uniform sampler2DArray normals : hint_normal;

instance uniform float lod_bias = 0.0; // coarser rings sit slightly below finer ones (rings overlap, no holes -> no seam cracks)

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

void fragment() {
	bool masked_dbg = false;
	vec3 world_pos = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float dist = length(world_pos - CAMERA_POSITION_WORLD);
	if (hull_volume_on) {
		// No water inside the hull / over the deck: discard fragments inside the hull's cross-section.
		vec3 hp = (hull_inv * vec4(world_pos, 1.0)).xyz;
		vec2 huv = vec2((hp.z - hull_dims.x) / (hull_dims.y - hull_dims.x), (hp.y - hull_dims.z) / (hull_dims.w - hull_dims.z));
		if (huv.x > 0.0 && huv.x < 1.0 && huv.y > 0.0 && huv.y < 1.0) {
			float hw = texture(hull_tex, huv).r;
			if (hw > 0.3 && abs(hp.x) < hw - 0.06) {
				if (debug_mode > 1.5) { masked_dbg = true; } else { discard; }
			}
		}
	}
	float map_size = float(textureSize(normals, 0).x);

	vec3 gradient = vec3(0.0);
	for (uint i = 0U; i < num_cascades; ++i) {
		vec4 scales = map_scales[i];
		vec3 coords = vec3((UV + cascade_shift[i]) * scales.xy, float(i));
		float ppm = map_size * min(scales.x, scales.y);
		// The 20 m detail cascade has no mips: fade it with distance so it cannot alias into sparkle.
		float fade = (i == 2U) ? (1.0 - smoothstep(25.0, 110.0, dist)) : 1.0;
		gradient += mix(texture_bicubic(normals, coords), texture(normals, coords), min(1.0, ppm * 0.1)).xyw * vec3(scales.ww * fade, 1.0);
	}
	// Toksvig-style filtering: slope variance across the pixel footprint widens the specular lobe instead of aliasing.
	vec2 dgx = dFdx(gradient.xy);
	vec2 dgy = dFdy(gradient.xy);
	float slope_var = clamp(0.5 * (dot(dgx, dgx) + dot(dgy, dgy)), 0.0, 1.0);

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
	float sd = abs(lx) - hw; // signed: < 0 inside the hull outline
	float d = over > 0.0 ? length(vec2(max(sd, 0.0), over)) : sd;
	float speed_k = clamp(ship_speed / 7.0, 0.0, 1.3);
	float bow_k = 1.0 - smoothstep(0.0, 0.45, u / float(HULL_BINS - 1)); // 1 at the bow, 0 amidships/stern
	float band_out = 0.28 + 0.9 * bow_k * speed_k;                      // wider only at the bow when fast
	float band = smoothstep(-0.02, 0.06, d) * (1.0 - smoothstep(0.1, band_out, d)); // strictly OUTSIDE the outline
	float lace = sin(lz * 3.3 + TIME * 2.6 + gradient.y * 11.0) * sin(lx * 4.1 - TIME * 2.0 + gradient.x * 10.0);
	float broken = smoothstep(-0.15, 0.55, lace + 0.25 + 0.5 * bow_k * speed_k);
	hull_foam = hull_foam_gain * band * broken * (0.30 + 0.55 * speed_k * (0.4 + 0.6 * bow_k));

	// Lacy foam: the accumulated foam is broken up by the fine slope field so it reads as patches and strands, not blobs.
	float lace_n = fract(sin(dot(floor((UV + vec2(TIME * 0.03)) * 3.0), vec2(12.9, 78.2))) * 43758.5) * 0.5 + 0.5 * abs(sin(gradient.x * 55.0) * cos(gradient.y * 47.0));
	float whitecap = smoothstep(0.0, 1.0, gradient.z * 0.75) * smoothstep(0.18, 0.7, lace_n + gradient.z * 0.45) * exp(-dist * 0.0035);
	foam_factor = clamp(whitecap * (1.0 - 0.7 * shallow) + shore_foam * 0.9 + hull_foam, 0.0, 1.0);

	// Own water colour: absorption body + teal scattering that grows toward wave crests (independent of the sky IBL).
	// Height sampled per fragment (the per-vertex varying differs between overlapping LOD rings -> visible patches).
	float frag_h = 0.0;
	for (uint i = 0U; i < num_cascades; ++i) {
		frag_h += texture(displacements, vec3((UV + cascade_shift[i]) * map_scales[i].xy, float(i))).y * map_scales[i].z;
	}
	float crest01 = smoothstep(-0.6, 1.4, frag_h);
	vec3 deep = water_color.rgb;
	vec3 scatter = vec3(0.04, 0.32, 0.42);
	vec3 body = mix(deep, scatter, crest01 * 0.4);
	float sh = pow(shallow, 1.4);
	vec3 shallow_tint = shallow_color * (0.5 + 0.35 * sh);
	vec3 base = mix(body, shallow_tint, sh * 0.85);
	ALBEDO = mix(base, foam_color.rgb, foam_factor);
	if (debug_mode > 0.5 && debug_mode < 1.5) { ALBEDO = vec3(whitecap, hull_foam, shallow); }

	gradient *= mix(0.015, normal_strength, exp(-dist * 0.0175));
	NORMAL = (VIEW_MATRIX * vec4(normalize(vec3(-gradient.x, 1.0, -gradient.y)), 0.0)).xyz;

	fresnel = mix(pow(1.0 - dot(VIEW, NORMAL), 5.0 * exp(-2.69 * roughness)) / (1.0 + 22.7 * pow(roughness, 1.5)), 1.0, REFLECTANCE);
	if (masked_dbg) { ALBEDO = vec3(1.0, 0.0, 1.0); EMISSION = vec3(1.0, 0.0, 1.0); }
	ROUGHNESS = clamp(sqrt(roughness * roughness + 1.0 * min(slope_var, 0.2)) + foam_factor * 0.25, 0.08, 0.9);
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

	float light_mask = smith_masking_shadowing(ROUGHNESS, dot_nv);
	float view_mask = smith_masking_shadowing(ROUGHNESS, dot_nl);
	float microfacet_distribution = ggx_distribution(dot(NORMAL, halfway), ROUGHNESS);
	float geometric_attenuation = 1.0 / (1.0 + light_mask + view_mask);
	SPECULAR_LIGHT += min(fresnel * microfacet_distribution * geometric_attenuation / (4.0 * dot_nv + 0.1), 5.0) * LIGHT_COLOR * 0.22 * ATTENUATION; // light colour+energy included (the moon must not glint like the sun); clamped

	const vec3 sss_modifier = vec3(0.9, 1.15, 0.85);
	float sss_height = 1.0 * max(0.0, wave_height + 2.5) * pow(max(dot(LIGHT, -VIEW), 0.0), 4.0) * pow(0.5 - 0.5 * dot(LIGHT, NORMAL), 3.0);
	float sss_near = 0.34 * pow(dot_nv, 2.0);
	float lambertian = 0.16 * dot_nl; // water is not a diffuse surface: keep sunlit faces from turning into pale patches
	vec3 sss_tint = mix(vec3(1.0), vec3(0.6, 1.3, 1.2), shallow);
	DIFFUSE_LIGHT += mix((sss_height + sss_near) * sss_modifier * sss_tint / (1.0 + light_mask) + lambertian, foam_color.rgb, foam_factor) * (1.0 - fresnel) * ATTENUATION * LIGHT_COLOR;
}
