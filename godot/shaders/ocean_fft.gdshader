shader_type spatial;
render_mode world_vertex_coords, shadows_disabled, depth_draw_opaque;
/**
 * FFT ocean surface. Lighting model and filtering adapted from 2Retr0/GodotOceanWaves (MIT), which follows the
 * 2019 GDC talk "Wakes, Explosions and Lighting: Interactive Water Simulation in Atlas".
 * Added here: clipmap level cut-outs, turquoise island shallows with shore surf, hull-contact foam.
 */

// Include ownership: common = all, surface = M2a/M2b, foam = M2b/M1.9, shading = M2a.
#include "res://shaders/ocean/common.gdshaderinc"
#include "res://shaders/ocean/surface.gdshaderinc"
#include "res://shaders/ocean/foam.gdshaderinc"
#include "res://shaders/ocean/shading.gdshaderinc"
#include "res://shaders/ocean/caustics.gdshaderinc"

// Planar reflection of the ship (opt-in PoC, scripts/planar_reflection.gd, --planar-reflection=hull|ship). gain 0 = off.
uniform sampler2D planar_tex : filter_linear, hint_default_transparent;
uniform float planar_gain = 0.0;
uniform float planar_distort = 0.03;

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

	float cp = cat_paw_gain > 0.0 ? gust_patch(world_pos.xz, dist) * cat_paw_gain : 0.0; // cat's paws: gust patches (M4c1)
	vec3 gradient = vec3(0.0);
	for (uint i = 0U; i < num_cascades; ++i) {
		vec4 scales = map_scales[i];
		vec3 coords = vec3((UV + cascade_shift[i]) * scales.xy, float(i));
		float ppm = map_size * min(scales.x, scales.y);
		// The 20 m detail cascade has no mips: fade it with distance so it cannot alias into sparkle.
		float fade = (i == 2U) ? (1.0 - smoothstep(25.0, 110.0, dist)) * (1.0 + 3.0 * cp) : 1.0;
		gradient += mix(texture_bicubic(normals, coords), texture(normals, coords), min(1.0, ppm * 0.1)).xyw * vec3(scales.ww * fade, 1.0);
	}
	// Wake channels: ridge slope tilts the normal, turbulence roughens the centre line (both off unless the gains are set).
	vec3 wk = wake_normal_terms(rest_xz);
	gradient.xy += wk.xy;
	gradient.xy += wk.z * wake_turb_gain * 0.25 * vec2(sin(rest_xz.x * 7.0 + TIME * 3.0), cos(rest_xz.y * 6.0 - TIME * 2.5));
	// Toksvig-style filtering: slope variance across the pixel footprint widens the specular lobe instead of aliasing.
	vec2 dgx = dFdx(gradient.xy);
	vec2 dgy = dFdy(gradient.xy);
	float slope_var = clamp(0.5 * (dot(dgx, dgx) + dot(dgy, dgy)), 0.0, 1.0);

	// Island shallows: turquoise water + surf line near the shore.
	float d_isl = island_distance(rest_xz);
	shallow = 1.0 - smoothstep(0.0, shallow_band, d_isl);
	float surf = exp(-max(d_isl, 0.0) * 0.18) * (0.55 + 0.45 * sin(d_isl * 0.7 - TIME * 1.1 + gradient.x * 6.0));
	shore_foam = clamp(surf * (1.0 - smoothstep(-2.0, 0.0, -d_isl)), 0.0, 1.0);

	hull_foam = hull_foam_term(world_pos, rest_xz, gradient);

	float whitecap = whitecap_term(gradient, dist, UV);
	float wake = wake_term(rest_xz, gradient);
	foam_factor = clamp(wake * 0.8 + whitecap * (1.0 - 0.7 * shallow) + shore_foam * 0.9 + hull_foam, 0.0, 1.0);

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
	float caus_w = pow(1.0 - smoothstep(0.0, shallow_band * caustics_wide, d_isl), 1.4);
	float caus = island_caustics(rest_xz, TIME, caus_w);
	shallow_tint *= 1.0 + caustics_gain * caus;
	vec3 base = mix(body, shallow_tint, sh * 0.85);
	ALBEDO = mix(base, foam_color.rgb, foam_factor) * (1.0 - 0.3 * cp);
	float hz = horizon_mix * smoothstep(120.0, 3000.0, dist) * (1.0 - sky_night); // no blend at night: the horizon colour is a lighting colour there, the displayed sky is far darker
	ALBEDO *= (1.0 - hz);
	EMISSION = sky_horizon_color * hz + vec3(1.0, 0.95, 0.8) * caustics_emit * caus * 0.35 + wake_biolum(rest_xz, dist);
	if (debug_mode > 0.5 && debug_mode < 1.5) { ALBEDO = vec3(whitecap, hull_foam, shallow); }
	if (debug_mode > 6.5 && debug_mode < 7.5) { ALBEDO = vec3(0.0); EMISSION = vec3(cp); } // M4c1: cat's paw mask
	if (debug_mode > 2.5 && debug_mode < 6.5) { ALBEDO = vec3(0.0); EMISSION = wake_debug(rest_xz, debug_mode); }

	gradient *= mix(0.015, normal_strength, exp(-dist * 0.0175));
	NORMAL = (VIEW_MATRIX * vec4(normalize(vec3(-gradient.x, 1.0, -gradient.y)), 0.0)).xyz;

	fresnel = mix(pow(1.0 - dot(VIEW, NORMAL), 5.0 * exp(-2.69 * roughness)) / (1.0 + 22.7 * pow(roughness, 1.5)), 1.0, REFLECTANCE);
	if (masked_dbg) { ALBEDO = vec3(1.0, 0.0, 1.0); EMISSION = vec3(1.0, 0.0, 1.0); }
	ROUGHNESS = clamp(sqrt(roughness * roughness + 1.0 * min(slope_var, 0.2)) + foam_factor * 0.25 + wk.z * wake_turb_gain * 0.3, 0.08, 0.9) * (1.0 - 0.5 * cp);
	if (planar_gain > 0.0) {
		// The mirrored camera is built with X negated, so the image is flipped horizontally; the wave normal distorts the lookup.
		vec3 pn = normalize(vec3(-gradient.x, 1.0, -gradient.y));
		vec4 pc = texture(planar_tex, vec2(1.0 - SCREEN_UV.x - pn.x * planar_distort, SCREEN_UV.y - pn.z * planar_distort));
		float pw = clamp(pc.a * clamp(fresnel, 0.0, 1.0) * planar_gain * (1.0 - foam_factor), 0.0, 1.0);
		ALBEDO *= (1.0 - pw);
		EMISSION += pc.rgb * pw;
	}
}

