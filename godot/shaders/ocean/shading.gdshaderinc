// Shading: GGX specular, SSS, light(). Owner: M2a (reflection/SSS tuning).
float smith_masking_shadowing(in float cos_theta, in float alpha) {
	float a = cos_theta / (alpha * sqrt(1.0 - cos_theta * cos_theta));
	float a_sq = a * a;
	return a < 1.6 ? (1.0 - 1.259 * a + 0.396 * a_sq) / (3.535 * a + 2.181 * a_sq) : 0.0;
}

float ggx_distribution(in float cos_theta, in float alpha) {
	float a_sq = alpha * alpha;
	float d = 1.0 + (a_sq - 1.0) * cos_theta * cos_theta;
	return a_sq / (PI * d * d);
}

void light() {
	vec3 halfway = normalize(LIGHT + VIEW);
	float dot_nl = max(dot(NORMAL, LIGHT), 2e-5);
	float dot_nv = max(dot(NORMAL, VIEW), 2e-5);

	float light_mask = smith_masking_shadowing(ROUGHNESS, dot_nv);
	float view_mask = smith_masking_shadowing(ROUGHNESS, dot_nl);
	float microfacet_distribution = ggx_distribution(dot(NORMAL, halfway), ROUGHNESS);
	float geometric_attenuation = 1.0 / (1.0 + light_mask + view_mask);
	SPECULAR_LIGHT += min(fresnel * microfacet_distribution * geometric_attenuation / (4.0 * dot_nv + 0.1), 5.0) * LIGHT_COLOR * 0.22 * ATTENUATION; // light colour+energy included (the moon must not glint like the sun); clamped

	const vec3 sss_modifier = vec3(0.9, 1.15, 0.85);
	float sss_height = 1.8 * max(0.0, wave_height + 2.5) * pow(max(dot(LIGHT, -VIEW), 0.0), 4.0) * pow(0.5 - 0.5 * dot(LIGHT, NORMAL), 3.0);
	float sss_near = 0.34 * pow(dot_nv, 2.0);
	float lambertian = 0.16 * dot_nl; // water is not a diffuse surface: keep sunlit faces from turning into pale patches
	vec3 sss_tint = mix(vec3(1.0), vec3(0.6, 1.3, 1.2), shallow);
	DIFFUSE_LIGHT += mix((sss_height + sss_near) * sss_modifier * sss_tint / (1.0 + light_mask) + lambertian, foam_color.rgb, foam_factor) * (1.0 - fresnel) * ATTENUATION * LIGHT_COLOR;
}
