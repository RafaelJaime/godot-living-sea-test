shader_type spatial;
render_mode cull_disabled, depth_draw_opaque;
// Wind-driven cloth for the pinnace sails. The sail is pinned along its top edge (the yard) and at its two lower
// corners (sheets); in between it bulges along the ship's fore/aft axis (billow) and ripples. All maths happens in SHIP
// space (x starboard, y up, z aft) through to_ship/from_ship, so it does not depend on the glTF/mesh orientation.

uniform sampler2D albedo_tex : source_color, repeat_enable, filter_linear_mipmap;
uniform sampler2D normal_tex : hint_normal, repeat_enable, filter_linear_mipmap;
uniform float alpha_cut = 0.5;
uniform mat4 to_ship;
uniform mat4 from_ship;
uniform vec3 bmin;        // sail AABB in ship space
uniform vec3 bmax;
uniform float fill = 0.5; // billow: >0 bulges forward (toward the bow, -z), <0 pressed aft, ~0 slack
uniform float flutter = 0.3; // ripple amplitude 0..1.5
uniform float furl = 0.0;    // 0 deployed .. 1 furled up to the yard
uniform float time = 0.0;
uniform float seed = 0.0;

varying float v_shade;

float disp(vec3 p) {
	float w = max(bmax.x - bmin.x, 0.001);
	float h = max(bmax.y - bmin.y, 0.001);
	float u = clamp((p.x - bmin.x) / w, 0.0, 1.0);
	float v = clamp((p.y - bmin.y) / h, 0.0, 1.0);       // 0 bottom .. 1 top (yard)
	float belly = pow(1.0 - v, 0.65) * pow(sin(3.14159265 * u), 0.8);
	float billow = -fill * h * 0.20 * belly;               // -z is forward
	float t = time;
	float r1 = sin(p.x * 1.9 + p.y * 2.4 + t * (2.0 + 5.0 * flutter) + seed);
	float r2 = sin(p.x * 3.4 - p.y * 1.7 + t * (3.1 + 7.0 * flutter) * 1.31 + seed * 2.3);
	float r3 = sin(p.y * 4.5 + t * (4.0 + 9.0 * flutter) + p.x * 0.7 + seed * 4.1);
	float ripple = (r1 * 0.5 + r2 * 0.35 + r3 * 0.15) * flutter * 0.28 * (1.0 - v) * (0.25 + 0.75 * belly + 0.35 * (1.0 - v));
	// luffing edge: free vertical edges (u near 0/1 away from the corners) snap more.
	float edge = (1.0 - sin(3.14159265 * u)) * (1.0 - v) * flutter * 0.10 * sin(t * (7.0 + 12.0 * flutter) + p.y * 3.0 + seed);
	return billow + ripple + edge;
}

void vertex() {
	vec3 p = (to_ship * vec4(VERTEX, 1.0)).xyz;
	// Furling: pull the sail up toward the yard.
	float top = bmax.y;
	p.y = top - (top - p.y) * (1.0 - 0.92 * furl);
	float d = disp(p) * (1.0 - 0.85 * furl);
	float e = 0.12;
	float dx = (disp(p + vec3(e, 0.0, 0.0)) - disp(p - vec3(e, 0.0, 0.0))) / (2.0 * e);
	float dy = (disp(p + vec3(0.0, e, 0.0)) - disp(p - vec3(0.0, e, 0.0))) / (2.0 * e);
	vec3 n = normalize((to_ship * vec4(NORMAL, 0.0)).xyz);
	float sg = n.z >= 0.0 ? 1.0 : -1.0;
	n = normalize(vec3(n.x - dx * sg, n.y - dy * sg, n.z));
	p.z += d;
	VERTEX = (from_ship * vec4(p, 1.0)).xyz;
	NORMAL = normalize((from_ship * vec4(n, 0.0)).xyz);
	v_shade = d;
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
