shader_type spatial;
render_mode cull_disabled, depth_draw_opaque;
// Sail mesh skinned to the SIMULATED cloth grid (sail_cloth.gd + cloth_solver.gd).
// dtex is a COLS x ROWS RGBAF texture, one texel per simulated node: rgb = displacement of the node (ship space) from its
// rest position minus the mesh's own baked belly, a = rest x of the node (gives the per-row outline of the sail).
// Every vertex finds its (u, v) in the sail outline, samples the displacement with a Catmull-Rom spline and moves by it;
// the lighting normal comes from the spline surface. All maths in SHIP space (x starboard, y up, z aft) via to_ship / from_ship.

uniform sampler2D albedo_tex : source_color, repeat_enable, filter_linear_mipmap;
uniform sampler2D normal_tex : hint_normal, repeat_enable, filter_linear_mipmap;
uniform sampler2D dtex : filter_nearest, repeat_disable;
uniform float alpha_cut = 0.5;
uniform mat4 to_ship;
uniform mat4 from_ship;
uniform float ytop = 10.0;
uniform float hgt = 4.0;
uniform float z0 = 0.0;
uniform float furl = 0.0; // 0 deployed .. 1 furled up to the yard
uniform float brace = 0.0; // yard brace angle about the vertical axis through mast_pos (rad): the bones already rotated the sail mesh
uniform vec3 mast_pos = vec3(0.0); // ship space

const int C = 12;
const int R = 10;

vec4 node(int i, int j) {
	return texelFetch(dtex, ivec2(clamp(i, 0, C - 1), clamp(j, 0, R - 1)), 0);
}

vec3 cr(vec3 p0, vec3 p1, vec3 p2, vec3 p3, float t) {
	return 0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t * t + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t * t * t);
}

vec3 disp(float u, float v) {
	float gx = clamp(u, 0.0, 1.0) * float(C - 1);
	float gy = clamp(v, 0.0, 1.0) * float(R - 1);
	int i0 = min(int(floor(gx)), C - 2);
	int j0 = min(int(floor(gy)), R - 2);
	float tx = gx - float(i0);
	float ty = gy - float(j0);
	vec3 rows_[4];
	for (int k = 0; k < 4; k++) {
		int j = j0 - 1 + k;
		rows_[k] = cr(node(i0 - 1, j).rgb, node(i0, j).rgb, node(i0 + 1, j).rgb, node(i0 + 2, j).rgb, tx);
	}
	return cr(rows_[0], rows_[1], rows_[2], rows_[3], ty);
}

// Outline of the sail at height fraction v: x range from the rest-x channel of the first / last column.
vec2 outline(float v) {
	float gy = clamp(v, 0.0, 1.0) * float(R - 1);
	int j0 = min(int(floor(gy)), R - 2);
	float f = gy - float(j0);
	float xl = mix(node(0, j0).a, node(0, j0 + 1).a, f);
	float xr = mix(node(C - 1, j0).a, node(C - 1, j0 + 1).a, f);
	return vec2(xl, xr);
}

vec3 surface(float u, float v) {
	vec2 o = outline(v);
	return vec3(mix(o.x, o.y, clamp(u, 0.0, 1.0)), ytop - clamp(v, 0.0, 1.0) * hgt, z0) + disp(u, v);
}

vec3 rot_y(vec3 v, float a) {
	float c = cos(a);
	float sn = sin(a);
	return vec3(v.x * c + v.z * sn, v.y, -v.x * sn + v.z * c);
}

void vertex() {
	vec3 ps = (to_ship * vec4(VERTEX, 1.0)).xyz;
	// Work in the sail's own (unbraced) frame, where the simulated grid lives, then rotate the result back.
	vec3 p = rot_y(ps - mast_pos, -brace) + mast_pos;
	float v = clamp((ytop - p.y) / hgt, 0.0, 1.0);
	vec2 o = outline(v);
	float u = clamp((p.x - o.x) / max(o.y - o.x, 0.1), 0.0, 1.0);
	p += disp(u, v);
	// normal of the simulated surface, on the same side as the mesh normal
	float eu = 0.5 / float(C - 1);
	float ev = 0.5 / float(R - 1);
	vec3 su = surface(min(u + eu, 1.0), v) - surface(max(u - eu, 0.0), v);
	vec3 sv = surface(u, min(v + ev, 1.0)) - surface(u, max(v - ev, 0.0));
	vec3 n = cross(su, sv);
	vec3 n0 = rot_y((to_ship * vec4(NORMAL, 0.0)).xyz, -brace);
	n = length(n) > 1e-6 ? normalize(n) : normalize(n0);
	if (dot(n, n0) < 0.0) {
		n = -n;
	}
	// Furling: pull the sail up toward the yard.
	p.y = ytop - (ytop - p.y) * (1.0 - 0.92 * furl);
	p = rot_y(p - mast_pos, brace) + mast_pos;
	n = rot_y(n, brace);
	VERTEX = (from_ship * vec4(p, 1.0)).xyz;
	NORMAL = normalize((from_ship * vec4(n, 0.0)).xyz);
}

void fragment() {
	vec4 a = texture(albedo_tex, UV);
	if (a.a < alpha_cut) {
		discard;
	}
	ALBEDO = a.rgb;
	NORMAL_MAP = texture(normal_tex, UV).xyz;
	NORMAL_MAP_DEPTH = 1.0;
	ROUGHNESS = 0.92;
	SPECULAR = 0.15;
	BACKLIGHT = a.rgb * 0.45; // sails glow a little when the sun is behind them
}
