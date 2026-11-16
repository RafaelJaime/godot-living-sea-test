shader_type sky;
// Procedural sky with day/dusk/night gradient, stars, moon, overcast and a moving fbm cloud layer.
// The sun is drawn here as a simple disc with a warm glow (visible above the horizon, dimmed by cloud cover and storms).

uniform vec3 sky_top : source_color = vec3(0.22, 0.42, 0.75);
uniform vec3 sky_horizon : source_color = vec3(0.8, 0.8, 0.8);
uniform vec3 ground_color : source_color = vec3(0.12, 0.2, 0.3);
uniform vec3 sun_dir = vec3(0.0, 0.3, -1.0);
uniform vec3 moon_dir = vec3(0.0, -0.3, 1.0);
uniform float star_visibility = 0.0;
uniform float cloud_cover = 0.2;
uniform float storminess = 0.0;
uniform float daylight = 1.0;
uniform vec2 cloud_scroll = vec2(0.0);
uniform float flash = 0.0;
uniform float layer_clouds = 1.0; // 0 when the volumetric cloud layer is active
uniform float rainbow = 0.0;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float hash31(vec3 p) {
	p = fract(p * vec3(0.1031, 0.1030, 0.0973));
	p += dot(p, p.yxz + 33.33);
	return fract((p.x + p.y) * p.z);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash21(i), hash21(i + vec2(1, 0)), f.x), mix(hash21(i + vec2(0, 1)), hash21(i + vec2(1, 1)), f.x), f.y);
}

float fbm(vec2 p) {
	float a = 0.5;
	float s = 0.0;
	for (int i = 0; i < 5; i++) {
		s += a * vnoise(p);
		p = p * 2.03 + 11.7;
		a *= 0.5;
	}
	return s;
}

void sky() {
	vec3 d = EYEDIR;
	float h = d.y;
	// Base gradient.
	float t = smoothstep(-0.05, 0.6, h);
	vec3 col = mix(sky_horizon, sky_top, pow(t, 0.7));
	if (h < 0.0) {
		col = mix(sky_horizon, ground_color, smoothstep(0.0, -0.25, h));
	}

	// Stars + moon (night only).
	if (star_visibility > 0.001 && h > -0.02) {
		vec3 p = d * 140.0;
		vec3 id = floor(p);
		float hs = hash31(id);
		if (hs > 0.965) {
			vec3 c = fract(p) - (0.3 + 0.4 * vec3(hash31(id + 7.1), hash31(id + 3.7), hash31(id + 9.3)));
			float star = smoothstep(0.30, 0.0, length(c));
			float tw = 0.65 + 0.35 * sin(TIME * (1.5 + hs * 4.0) + hs * 40.0);
			col += vec3(1.0, 0.95, 0.9) * star * tw * star_visibility * (hs - 0.95) * 40.0 * (1.0 - cloud_cover * 0.9);
		}
		float md = dot(d, normalize(moon_dir));
		float disc = smoothstep(0.99935, 0.9996, md);
		float halo = pow(max(md, 0.0), 220.0) * 0.5 + pow(max(md, 0.0), 24.0) * 0.12;
		col += (vec3(0.85, 0.9, 1.0) * disc * 2.2 + vec3(0.5, 0.6, 0.9) * halo) * star_visibility * (1.0 - cloud_cover * 0.85);
	}

	// Rainbow after a storm: primary bow around the anti-solar point (red outside at 42 deg, violet inside at 40 deg).
	if (rainbow > 0.001 && h > -0.01) {
		float ang = degrees(acos(clamp(dot(d, -normalize(sun_dir)), -1.0, 1.0)));
		float t = (ang - 39.6) / 3.0;
		if (t > 0.0 && t < 1.0) {
			vec3 spec = clamp(vec3(1.5 - abs(t * 4.0 - 3.0), 1.5 - abs(t * 4.0 - 2.0), 1.5 - abs(t * 4.0 - 1.0)), 0.0, 1.0);
			col += spec * sin(t * 3.14159) * rainbow * 0.28 * smoothstep(-0.01, 0.06, h) * (0.35 + 0.65 * daylight);
		}
	}

	// Sun disc and glow.
	{
		vec3 sdn = normalize(sun_dir);
		float sd = dot(d, sdn);
		float disc = smoothstep(0.99955, 0.99975, sd);
		float glow = pow(max(sd, 0.0), 70.0) * 0.55 + pow(max(sd, 0.0), 9.0) * 0.12;
		float vis = smoothstep(-0.03, 0.06, sdn.y) * (1.0 - 0.75 * cloud_cover) * (1.0 - storminess) * step(-0.02, h);
		col += (vec3(1.0, 0.93, 0.78) * disc * 7.0 + vec3(1.0, 0.72, 0.42) * glow) * vis;
	}

	// Clouds on a flat layer.
	if (h > 0.0 && layer_clouds > 0.5) {
		vec2 uv = d.xz / (h + 0.12) * 0.55 + cloud_scroll;
		float n = fbm(uv * 1.3);
		float cover = clamp(cloud_cover, 0.0, 1.0);
		float thresh = 0.78 - cover * 0.45;
		float c = smoothstep(thresh, thresh + 0.22, n);
		c *= smoothstep(0.0, 0.18, h); // fade to the horizon
		float sun_side = pow(max(dot(normalize(d), normalize(sun_dir)), 0.0), 6.0);
		vec3 lit = mix(vec3(0.9, 0.9, 0.92), vec3(1.0, 0.8, 0.6), 0.35) * (0.35 + 0.65 * daylight);
		vec3 dark = mix(vec3(0.5, 0.52, 0.56), vec3(0.12, 0.13, 0.16), storminess) * (0.15 + 0.85 * daylight);
		vec3 ccol = mix(lit, dark, clamp(cover * 0.55 + storminess * 0.7, 0.0, 1.0));
		ccol += sun_side * vec3(1.0, 0.85, 0.6) * 0.5 * (1.0 - storminess) * daylight;
		col = mix(col, ccol, c * (0.55 + 0.45 * cover));
	}
	// Lightning: sky lights up from within the clouds.
	col += vec3(0.7, 0.75, 1.0) * flash * (0.4 + 0.6 * smoothstep(0.0, 0.5, h));
	COLOR = col;
}
