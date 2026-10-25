shader_type spatial;
render_mode specular_disabled;

void fragment() {
	vec2 p = UV * 2.0 - vec2(1.0);
	float radius = length(p);
	float angle = atan(p.y, p.x);
	float warp = 0.008 * sin(angle * 5.0 + radius * 11.0)
		+ 0.004 * sin(angle * 13.0 + radius * 23.0);
	float ring = sin((radius + warp) * 96.0);
	float grain = sin(angle * 19.0 + radius * 127.0);
	float color_mix = clamp(0.5 + ring * 0.10 + grain * 0.025, 0.0, 1.0);
	ALBEDO = mix(vec3(0.14, 0.09, 0.05), vec3(0.25, 0.17, 0.09), color_mix);
	ROUGHNESS = 1.0;
}
