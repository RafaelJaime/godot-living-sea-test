shader_type spatial;
render_mode unshaded, cull_disabled, fog_disabled;
// Far mountain ring (M3.11): coloured from the published sky globals so the silhouette is the same haze as the horizon at
// dawn, day, dusk and night instead of a baked blue that clashes with an orange sunset.
// Vertex colour: r = height along the ridge (0 base .. 1 crest), g = how near the layer is (0 far .. 1 near).
global uniform vec3 sky_fog_color;
global uniform vec3 sky_zenith_color;
global uniform float sky_night;

void fragment() {
	float t = COLOR.r;
	float near = COLOR.g;
	// sky_fog_color is a lighting colour: the displayed night horizon is far darker, hence the night factor.
	float lum = mix(0.82, 0.10, clamp(sky_night, 0.0, 1.0));
	vec3 haze = sky_fog_color * lum;
	vec3 deep = mix(haze, sky_zenith_color * lum, 0.30) * (0.80 - 0.10 * near);
	ALBEDO = mix(haze, deep, smoothstep(0.0, 1.0, t) * (0.45 + 0.40 * near));
}
