shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

uniform sampler2D albedo_map : source_color, filter_linear_mipmap_anisotropic;
uniform sampler2D normal_map : hint_normal, filter_linear_mipmap_anisotropic;

varying vec3 scan_point;

float hash_cell(vec3 point) {
	point = fract(point * 0.1031);
	point += dot(point, point.yxz + 33.33);
	return fract((point.x + point.y) * point.z);
}

float rock_noise(vec3 point) {
	vec3 cell = floor(point);
	vec3 fraction = fract(point);
	fraction = fraction * fraction * (3.0 - 2.0 * fraction);
	float lower = mix(mix(hash_cell(cell), hash_cell(cell + vec3(1.0, 0.0, 0.0)), fraction.x),
		mix(hash_cell(cell + vec3(0.0, 1.0, 0.0)), hash_cell(cell + vec3(1.0, 1.0, 0.0)), fraction.x), fraction.y);
	float upper = mix(mix(hash_cell(cell + vec3(0.0, 0.0, 1.0)), hash_cell(cell + vec3(1.0, 0.0, 1.0)), fraction.x),
		mix(hash_cell(cell + vec3(0.0, 1.0, 1.0)), hash_cell(cell + vec3(1.0, 1.0, 1.0)), fraction.x), fraction.y);
	return mix(lower, upper, fraction.z);
}

void vertex() {
	scan_point = VERTEX;
}

void fragment() {
	vec3 stone = texture(albedo_map, UV).rgb;
	float value = dot(stone, vec3(0.24, 0.67, 0.09));
	vec3 host = mix(stone, vec3(value * 0.81, value * 0.86, value * 0.89), 0.82) * 0.88;
	float warp = rock_noise(scan_point * 1.7 + vec3(4.0, -2.0, 7.0));
	float layer = sin(dot(scan_point, vec3(3.2, 2.4, 1.4)) + (warp - 0.5) * 4.0);
	float seam = 1.0 - smoothstep(0.08, 0.25, abs(layer));
	float fractured = smoothstep(0.38, 0.62,
		rock_noise(scan_point * 7.5 + vec3(-6.0, 3.0, 2.0)));
	float raised_stone = smoothstep(0.48, 0.78, scan_point.y);
	float copper = seam * fractured * raised_stone;
	vec3 mineral = host * vec3(1.45, 0.75, 0.47) + vec3(0.075, 0.014, 0.006);
	ALBEDO = mix(host, mineral, copper * 0.72);
	NORMAL_MAP = texture(normal_map, UV).rgb;
	NORMAL_MAP_DEPTH = 0.76;
	ROUGHNESS = 0.94;
	SPECULAR = 0.24;
}
