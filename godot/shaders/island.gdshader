shader_type spatial;
// Islands, vegetation and lighthouse bodies (M3.11). Same PBR look as the StandardMaterial it replaces, plus a sky-driven
// fill so slopes facing away from the sun / moon never go black at dusk and night. Everything comes from the published
// sky globals (WorldState registers them, sky.gd sets them every frame, see godot/README.md "Sky / atmosphere").
global uniform vec3 sky_horizon_color;
global uniform vec3 sky_zenith_color;
global uniform float sky_night;
global uniform float sky_storminess;

uniform vec3 tint : source_color = vec3(1.0);
uniform bool use_vertex_color = true;
uniform float roughness = 0.95;
uniform float day_fill = 0.14; // hemispheric sky fill in daylight / dusk (adds to the engine ambient)
uniform float night_fill = 0.42; // moonlit blue fill at night
uniform vec3 moon_tint : source_color = vec3(0.16, 0.24, 0.45);

void fragment() {
	vec3 base = use_vertex_color ? COLOR.rgb * tint : tint;
	ALBEDO = base;
	ROUGHNESS = roughness;
	SPECULAR = 0.25;
	vec3 nw = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	float up = nw.y * 0.5 + 0.5;
	vec3 sky = mix(sky_horizon_color, sky_zenith_color, up);
	float night = clamp(sky_night, 0.0, 1.0);
	// Lower hemisphere bounces the sea: slightly teal, so shorelines pick up the water colour.
	vec3 bounce = mix(vec3(0.04, 0.10, 0.12), sky, up);
	vec3 fill_day = bounce * day_fill * (1.0 - 0.5 * clamp(sky_storminess, 0.0, 1.0));
	vec3 fill_night = moon_tint * night_fill * (0.45 + 0.55 * up);
	EMISSION = base * mix(fill_day, fill_night, night);
}
