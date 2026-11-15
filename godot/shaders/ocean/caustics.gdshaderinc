// Island caustics (M2d). Owner: M2d only. Two scrolling procedural cell (Voronoi edge) patterns multiplied together, applied to the
// shallow tint in ocean_fft.gdshader as: shallow_tint *= 1 + caustics_gain * island_caustics(...). Zero in deep water (weighted by
// pow(shallow, 1.4)), zero at night and when the sun is below the horizon.
global uniform vec3 sky_sun_dir; // direction towards the sun (world), published by sky.gd
uniform float caustics_gain = 0.0; // 0 = off

vec2 caustic_hash(vec2 p) {
	p = vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)));
	return fract(sin(p) * 43758.5453);
}

// Brightness of the web of cell edges: 1 on the edges, 0 inside the cells.
float caustic_cells(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	float d1 = 8.0;
	float d2 = 8.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 g = vec2(float(x), float(y));
			vec2 o = caustic_hash(i + g);
			float d = length(g + o - f);
			if (d < d1) { d2 = d1; d1 = d; } else if (d < d2) { d2 = d; }
		}
	}
	return pow(clamp(1.0 - (d2 - d1) * 2.6, 0.0, 1.0), 3.0);
}

float island_caustics(vec2 xz, float t, float shallow_w) {
	if (caustics_gain <= 0.0 || shallow_w <= 0.0) { return 0.0; }
	float sun = clamp(sky_sun_dir.y * 2.5, 0.0, 1.0);
	if (sun <= 0.0) { return 0.0; }
	float a = caustic_cells(xz * 0.9 + vec2(t * 0.08, t * 0.05));
	float b = caustic_cells(xz * 1.35 + vec2(-t * 0.06, t * 0.09) + vec2(17.0, 31.0));
	return a * b * 2.2 * shallow_w * sun * (1.0 - sky_night);
}
