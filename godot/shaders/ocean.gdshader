shader_type spatial;
render_mode depth_draw_opaque, cull_back;

// Wave parameters are pushed from waves.gd (single source of truth, mirrored on the CPU).
uniform vec4 wave_data[6];   // xy = direction, z = k, w = steepness
uniform float wave_phase[6]; // omega*t - k*dot(d, world_offset), wrapped to [0, TAU)
uniform vec2 tile_offset;    // world offset mod 1000 (keeps detail textures seamless across rebases)
uniform vec2 detail_scroll;

uniform vec3 deep_color : source_color = vec3(0.012, 0.115, 0.18);
uniform vec3 shallow_color : source_color = vec3(0.04, 0.42, 0.45);
uniform vec3 foam_color : source_color = vec3(0.92, 0.96, 1.0);
uniform float foam_threshold = 0.19;
uniform float normal_strength = 0.22;
uniform sampler2D detail_normal : hint_normal, repeat_enable, filter_linear_mipmap;

instance uniform vec4 inner_rect = vec4(1.0, 1.0, -1.0, -1.0); // finer clipmap level footprint (minx, minz, maxx, maxz)

varying vec3 v_rest;
varying vec3 v_normal;
varying float v_height;
varying float v_crest;

void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_rest = wp;
	float dist = length(wp.xz - CAMERA_POSITION_WORLD.xz);
	vec3 disp = vec3(0.0);
	vec3 n = vec3(0.0, 1.0, 0.0);
	float crest = 0.0;
	for (int i = 0; i < 6; i++) {
		vec2 d = wave_data[i].xy;
		float k = wave_data[i].z;
		float lam = 6.2831853 / k;
		float fade = 1.0 - smoothstep(lam * 25.0, lam * 90.0, dist); // avoid aliasing of short waves far away
		float q = wave_data[i].w * fade;
		float f = k * dot(d, wp.xz) - wave_phase[i];
		float a = q / k;
		float c = cos(f);
		float s = sin(f);
		disp += vec3(d.x * a * c, a * s, d.y * a * c);
		n.x -= d.x * q * c;
		n.z -= d.y * q * c;
		crest += q * s;
	}
	VERTEX += disp; // MODEL_MATRIX is translation only, so object-space == world-space offsets
	v_normal = normalize(n);
	v_height = disp.y;
	v_crest = crest;
}

void fragment() {
	if (v_rest.x > inner_rect.x && v_rest.x < inner_rect.z && v_rest.z > inner_rect.y && v_rest.z < inner_rect.w) {
		discard;
	}
	vec3 world_pos = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float dist = length(world_pos - CAMERA_POSITION_WORLD);

	vec2 p = v_rest.xz + tile_offset;
	vec3 n1 = texture(detail_normal, p / 40.0 + detail_scroll).xyz * 2.0 - 1.0;
	vec3 n2 = texture(detail_normal, p / 8.0 - detail_scroll * 3.0).xyz * 2.0 - 1.0;
	float detail_fade = 1.0 - smoothstep(60.0, 600.0, dist);
	vec2 dn = (n1.xy * 0.6 + n2.xy * 0.4) * normal_strength * detail_fade;
	vec3 N = normalize(vec3(v_normal.x + dn.x, v_normal.y, v_normal.z + dn.y));
	NORMAL = normalize((VIEW_MATRIX * vec4(N, 0.0)).xyz);

	float h01 = smoothstep(-0.9, 1.3, v_height);
	vec3 col = mix(deep_color, shallow_color, h01 * 0.75);

	float foam_noise = texture(detail_normal, p / 14.0 + detail_scroll * 2.0).x;
	float foam = smoothstep(foam_threshold, foam_threshold + 0.14, v_crest + (foam_noise - 0.5) * 0.12);
	foam *= 1.0 - smoothstep(150.0, 900.0, dist);

	ALBEDO = mix(col, foam_color, foam);
	EMISSION = col * 0.06 * (1.0 - foam);
	ROUGHNESS = clamp(mix(0.07, 0.75, foam) + smoothstep(200.0, 2500.0, dist) * 0.25, 0.0, 1.0);
	SPECULAR = 0.55;
	METALLIC = 0.0;
}
