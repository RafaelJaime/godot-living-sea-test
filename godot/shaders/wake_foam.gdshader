shader_type spatial;
render_mode world_vertex_coords, unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;
// Flat foam blobs for the ship wake / bow wave. Each vertex is snapped onto the FFT surface so the foam rides the waves.

#define MAX_CASCADES 8
global uniform uint num_cascades;
global uniform sampler2DArray displacements;
global uniform vec4 foam_color : source_color;
uniform vec4 map_scales[MAX_CASCADES];
uniform sampler2D blob_tex : source_color, repeat_disable;
uniform sampler2D noise_tex : source_color, repeat_enable;
uniform float lift = 0.22;
uniform float brightness = 1.0;

varying vec4 vcol;
varying float seed;

vec3 surface_at(vec2 xz) {
	vec3 d = vec3(0.0);
	for (uint i = 0U; i < num_cascades; ++i) {
		vec4 s = map_scales[i];
		d += texture(displacements, vec3(xz * s.xy, float(i))).xyz * s.z;
	}
	return d;
}

void vertex() {
	vec2 p = VERTEX.xz;
	vec3 d = surface_at(p);
	d = surface_at(p - d.xz); // one fixed-point step for the horizontal displacement
	VERTEX.y = d.y + lift;
	vcol = COLOR;
	seed = fract(sin(dot(MODEL_MATRIX[3].xz, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	float blob = texture(blob_tex, UV).a;
	float n = texture(noise_tex, UV * 1.7 + vec2(seed * 7.0, seed * 3.0)).r;
	float a = blob * (0.3 + 0.7 * smoothstep(0.15, 0.7, n));
	ALBEDO = foam_color.rgb * 1.15 * brightness;
	ALPHA = clamp(a * vcol.a, 0.0, 1.0);
}
