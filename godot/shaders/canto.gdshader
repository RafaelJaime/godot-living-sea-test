shader_type spatial;
// Canto sun billboard: additive (black = transparent), unlit, fog-immune, never writes depth.
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, fog_disabled;

uniform sampler2D canto_tex : source_color, filter_linear_mipmap, repeat_disable;
uniform float glow = 1.5;

void fragment() {
	vec3 c = texture(canto_tex, UV).rgb;
	ALBEDO = c * glow;
	ALPHA = 1.0;
}
