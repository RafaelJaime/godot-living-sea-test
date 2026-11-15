// Shared defines, uniforms, varyings. Owner: all ocean milestones (additions append here).
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
uniform sampler2D wake_tex : filter_linear, repeat_disable;
uniform vec2 wake_origin = vec2(1.0e6);
uniform float horizon_mix = 1.0;    // M2a.6: far water blends to the sky horizon colour (0 = off, 1 = full) beyond ~0.12..3 km
global uniform vec3 sky_horizon_color;
global uniform float sky_night;
uniform float wake_turb_gain = 1.0;  // G channel: extra roughness + fine normal noise in the turbulent centre line (0 = off)
uniform float wake_ridge_gain = 1.0; // B channel: Kelvin ridge slope added to the normal (0 = off)
uniform float wake_size = 320.0;
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
global uniform sampler2DArray normals : hint_normal, filter_linear_mipmap, repeat_enable;

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

