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
	float warp = rock_noise(scan_point * 1.7 + vec3(4.0, -2.0, 7.0));
	float layer = sin(dot(scan_point, vec3(3.2, 2.4, 1.4)) + (warp - 0.5) * 4.0);
	float seam = 1.0 - smoothstep(0.22, 0.58, abs(layer));
	float fractured = smoothstep(0.24, 0.55,
		rock_noise(scan_point * 7.5 + vec3(-6.0, 3.0, 2.0)));
	float raised_stone = smoothstep(0.12, 0.38, scan_point.y);
	float copper = seam * fractured * raised_stone;
	vec3 mineral = stone * vec3(1.25, 0.72, 0.50) + vec3(0.13, 0.015, 0.005);
	ALBEDO = mix(stone, mineral, copper * 0.92);
	NORMAL_MAP = texture(normal_map, UV).rgb;
	NORMAL_MAP_DEPTH = 0.76;
	ROUGHNESS = 0.94;
	SPECULAR = 0.24;
}
