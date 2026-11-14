shader_type spatial;
render_mode world_vertex_coords, unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;
// Foam ribbon laid on the FFT surface: streaky lace stretched along the ship's path, decaying with age.
// COLOR.a = age fade (1 young .. 0 old), COLOR.r = |across| position (0 centre .. 1 edge), UV.y = distance along path (m).

#define MAX_CASCADES 8
global uniform uint num_cascades;
global uniform sampler2DArray displacements;
global uniform vec4 foam_color : source_color;
uniform vec2 cascade_shift[MAX_CASCADES]; // world offset (rebase shifts) modulo each cascade tile, metres: tile sizes are free
uniform vec4 map_scales[MAX_CASCADES];
uniform sampler2D noise_tex : source_color, repeat_enable, filter_linear_mipmap;
uniform float lift = 0.2;
uniform float strength = 1.0;
uniform float streak_stretch = 0.045; // lower = longer streaks along the path
uniform float lace_scale = 0.9;

varying float v_fade;
varying float v_edge;
varying float v_along;

vec3 surface_at(vec2 xz) {
	vec3 d = vec3(0.0);
	for (uint i = 0U; i < num_cascades; ++i) {
		vec4 s = map_scales[i];
		d += texture(displacements, vec3((xz + cascade_shift[i]) * s.xy, float(i))).xyz * s.z;
	}
	return d;
}

void vertex() {
	vec3 d = surface_at(VERTEX.xz);
	d = surface_at(VERTEX.xz - d.xz);
	VERTEX.y = d.y + lift;
	v_fade = COLOR.a;
	v_edge = COLOR.r;
	v_along = UV.y;
}

void fragment() {
	float across = UV.x * 2.0 - 1.0;
	// Long thin streaks along the path + fine lace across them.
	vec2 p = vec2(across * 2.2, v_along * streak_stretch);
	float streaks = texture(noise_tex, p).r;
	float lace = texture(noise_tex, vec2(across * lace_scale * 2.0 + 3.1, v_along * lace_scale * 0.12) + vec2(0.0, TIME * 0.01)).r;
	float body = smoothstep(0.35, 0.8, streaks * 0.65 + lace * 0.45);
	float edge = 1.0 - smoothstep(0.55, 1.0, abs(across) + (lace - 0.5) * 0.35);
	float core = 1.0 - 0.45 * abs(across);
	float a = body * edge * core * v_fade * strength;
	// Older foam breaks up into lace: raise the threshold as it fades.
	a *= smoothstep(0.0, 0.35, v_fade * 1.3 + (streaks - 0.5) * 0.9);
	ALBEDO = foam_color.rgb * 1.15;
	ALPHA = clamp(a, 0.0, 0.92);
}
