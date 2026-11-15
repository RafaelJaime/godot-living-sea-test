// Foam terms. Owner: foam / wake milestones (M2b, M1.9).
// Hull contact foam: thin, broken band hugging the waterline outline. With a hull volume baked (hull_volume_on) the outline
// is read from the hull cross-section table at the fragment's height in the SHIP's frame (hull_inv = full pose), so it
// follows heel and pitch; otherwise the yaw-only baked width profile is used.
float hull_foam_term(vec3 world_pos, vec2 rxz, vec3 gradient) {
	vec2 rel = rxz - ship_a.xy;
	float lx = dot(rel, vec2(ship_a.z, -ship_a.w)); // ship right (+x local)
	float lz = dot(rel, vec2(ship_a.w, ship_a.z));  // ship back (+z local)
	float u = clamp((lz - hull_z.x) / (hull_z.y - hull_z.x), 0.0, 1.0) * float(HULL_BINS - 1);
	int i0 = int(floor(u));
	int i1 = min(i0 + 1, HULL_BINS - 1);
	float hw = mix(hull_w[i0], hull_w[i1], fract(u));
	if (hull_volume_on) {
		vec3 hp = (hull_inv * vec4(world_pos, 1.0)).xyz;
		vec2 huv = vec2((hp.z - hull_dims.x) / (hull_dims.y - hull_dims.x), (hp.y - hull_dims.z) / (hull_dims.w - hull_dims.z));
		if (huv.x > 0.0 && huv.x < 1.0 && huv.y > 0.0 && huv.y < 1.0) {
			float hwt = texture(hull_tex, huv).r;
			if (hwt > 0.3) {
				lx = hp.x;
				lz = hp.z;
				hw = hwt;
				u = clamp((lz - hull_z.x) / (hull_z.y - hull_z.x), 0.0, 1.0) * float(HULL_BINS - 1);
			}
		}
	}
	// Distance to the outline (outside > 0); past the bow/stern tips measure to the end point.
	float over = max(max(hull_z.x - lz, lz - hull_z.y), 0.0);
	float sd = abs(lx) - hw; // signed: < 0 inside the hull outline
	float d = over > 0.0 ? length(vec2(max(sd, 0.0), over)) : sd;
	float speed_k = clamp(ship_speed / 7.0, 0.0, 1.3);
	float bow_k = 1.0 - smoothstep(0.0, 0.45, u / float(HULL_BINS - 1)); // 1 at the bow, 0 amidships/stern
	float band_out = 0.28 + 0.9 * bow_k * speed_k;                      // wider only at the bow when fast
	float band = smoothstep(-0.02, 0.06, d) * (1.0 - smoothstep(0.1, band_out, d)); // strictly OUTSIDE the outline
	float lace = sin(lz * 3.3 + TIME * 2.6 + gradient.y * 11.0) * sin(lx * 4.1 - TIME * 2.0 + gradient.x * 10.0);
	float broken = smoothstep(-0.15, 0.55, lace + 0.25 + 0.5 * bow_k * speed_k);
	return hull_foam_gain * band * broken * (0.30 + 0.55 * speed_k * (0.4 + 0.6 * bow_k));

}

float whitecap_term(vec3 gradient, float dist, vec2 uv) {
	float lace_n = fract(sin(dot(floor((uv + vec2(TIME * 0.03)) * 3.0), vec2(12.9, 78.2))) * 43758.5) * 0.5 + 0.5 * abs(sin(gradient.x * 55.0) * cos(gradient.y * 47.0));
	return smoothstep(0.0, 1.0, gradient.z * 0.75) * smoothstep(0.18, 0.7, lace_n + gradient.z * 0.45) * exp(-dist * 0.0035);
}

// Advected wake foam: lacy (broken up by fine slopes), stronger where fresh.
float wake_term(vec2 rxz, vec3 gradient) {
	vec2 wuv = (rxz - wake_origin) / wake_size;
	float wake = 0.0;
	if (wuv.x > 0.0 && wuv.x < 1.0 && wuv.y > 0.0 && wuv.y < 1.0) {
		wake = texture(wake_tex, wuv).r;
		float edge = smoothstep(0.0, 0.04, min(min(wuv.x, 1.0 - wuv.x), min(wuv.y, 1.0 - wuv.y)));
		float lace_w = 0.5 + 0.5 * sin(rxz.x * 0.9 + gradient.x * 18.0) * cos(rxz.y * 1.1 + gradient.y * 16.0);
		wake = smoothstep(0.22, 0.7, wake + (lace_w - 0.5) * 0.5) * min(wake * 1.6, 1.0) * edge;
	}
	return wake;
}

// Night bioluminescence (M4b2.2): faint cyan-green sparks scattered over the whole wake (foam R and turbulence G, so hull foam, Kelvin
// arms and the centre line), each cell twinkling on its own clock, plus a very low base glow so the spark field has a body.
// Scaled by `sky_biolum` (0 by day, in storms and under thick cloud). Returns an emission colour; zero outside the wake window.
float bl_hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

vec3 wake_biolum(vec2 rxz, float dist) {
	vec2 wuv = (rxz - wake_origin) / wake_size;
	if (sky_biolum <= 0.001 || wuv.x < 0.02 || wuv.x > 0.98 || wuv.y < 0.02 || wuv.y > 0.98) { return vec3(0.0); }
	vec3 w = texture(wake_tex, wuv).rgb;
	float amount = clamp(max(w.r * 0.9, w.g), 0.0, 1.0);
	if (amount < 0.05) { return vec3(0.0); }
	float cell = 0.16 + dist * 0.0035; // cells grow with distance so sparks stay about 2-4 px
	vec2 g = rxz / cell;
	vec2 id = floor(g);
	vec2 f = fract(g) - 0.5;
	float h = bl_hash(id);
	vec2 jitter = (vec2(bl_hash(id + 7.7), bl_hash(id + 3.3)) - 0.5) * 0.5;
	float dot_m = smoothstep(0.32, 0.0, length(f - jitter));
	float tw = 0.5 + 0.5 * sin(TIME * (2.0 + h * 6.0) + h * 40.0);
	float spark = step(0.7, h) * dot_m * tw * tw * tw;
	vec3 col = vec3(0.05, 0.55, 0.62);
	return col * (spark * amount * 1.5 + 0.035 * amount) * sky_biolum * biolum_gain;
}

// Debug (debug_mode 3 = R foam, G turbulence, B ridge as colour; 4 = R only; 5 = G only; 6 = B only; B maps +-0.5 m to 0..1).
vec3 wake_debug(vec2 rxz, float mode) {
	vec2 wuv = (rxz - wake_origin) / wake_size;
	vec3 w = vec3(0.0, 0.0, 0.0);
	if (wuv.x > 0.0 && wuv.x < 1.0 && wuv.y > 0.0 && wuv.y < 1.0) {
		w = texture(wake_tex, wuv).rgb;
	}
	float ridge = w.b + 0.5;
	if (mode > 5.5) { return vec3(ridge); }
	if (mode > 4.5) { return vec3(w.g); }
	if (mode > 3.5) { return vec3(w.r); }
	return vec3(w.r, w.g, ridge);
}

// Wake normal terms (M2b.8): returns (slope.x, slope.y, turbulence). Slope comes from central differences of the signed ridge
// height (B), turbulence is G. Zero outside the window or when both gains are 0.
vec3 wake_normal_terms(vec2 rxz) {
	vec2 wuv = (rxz - wake_origin) / wake_size;
	if ((wake_turb_gain + wake_ridge_gain) <= 0.0 || wuv.x < 0.02 || wuv.x > 0.98 || wuv.y < 0.02 || wuv.y > 0.98) { return vec3(0.0); }
	vec2 px = vec2(1.0) / vec2(textureSize(wake_tex, 0));
	float bx = texture(wake_tex, wuv + vec2(px.x, 0.0)).b - texture(wake_tex, wuv - vec2(px.x, 0.0)).b;
	float by = texture(wake_tex, wuv + vec2(0.0, px.y)).b - texture(wake_tex, wuv - vec2(0.0, px.y)).b;
	float texel_m = wake_size * px.x;
	return vec3(vec2(bx, by) / (2.0 * texel_m) * wake_ridge_gain, texture(wake_tex, wuv).g);
}
