shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

uniform sampler2D albedo_map : source_color, filter_linear_mipmap_anisotropic;
uniform sampler2D normal_map : hint_normal, filter_linear_mipmap_anisotropic;

varying vec3 scan_point;
varying vec3 world_point;

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
	world_point = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 stone = texture(albedo_map, UV).rgb;
	float value = dot(stone, vec3(0.24, 0.67, 0.09));
	vec3 host = mix(stone, vec3(value * 0.78, value * 0.83, value * 0.86), 0.58) * 0.86;
	float warp = rock_noise(world_point * 1.8 + vec3(4.0, -2.0, 7.0));
	float layer = sin(dot(world_point, vec3(2.6, 1.9, 1.2)) + (warp - 0.5) * 4.0);
	float vein = 1.0 - smoothstep(0.08, 0.22, abs(layer));
	float fractured = smoothstep(0.38, 0.62,
		rock_noise(world_point * 4.2 + vec3(-6.0, 3.0, 2.0)));
	float raised_stone = smoothstep(0.30, 0.68, scan_point.y);
	float patch = smoothstep(0.54, 0.68, warp) * (0.55 + 0.45 * fractured);
	float copper = max(patch, vein * fractured * 0.25) * raised_stone;
	vec3 mineral = host * vec3(1.38, 0.75, 0.50) + vec3(0.045, 0.019, 0.006);
	ALBEDO = mix(host, mineral, copper * 0.52);
	NORMAL_MAP = texture(normal_map, UV).rgb;
	NORMAL_MAP_DEPTH = 0.76;
	ROUGHNESS = 0.94;
	SPECULAR = 0.24;
}
