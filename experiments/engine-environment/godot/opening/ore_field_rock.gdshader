shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

uniform sampler2D albedo_map : source_color, filter_linear_mipmap_anisotropic;
uniform sampler2D normal_map : hint_normal, filter_linear_mipmap_anisotropic;
uniform float copper_threshold = 0.59;
uniform vec3 host_tint : source_color = vec3(0.78, 0.78, 0.77);
uniform vec3 copper_tint : source_color = vec3(0.96, 0.86, 0.78);

varying vec3 rock_point;
varying vec3 rock_normal;

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
	rock_point = VERTEX;
	rock_normal = NORMAL;
}

void fragment() {
	vec3 scan = texture(albedo_map, UV).rgb;
	float broad = rock_noise(rock_point * vec3(2.0, 1.7, 2.0) + vec3(7.4, 1.2, -3.6));
	float fractures = rock_noise(rock_point * 6.2 + vec3(-2.8, 3.7, 5.1));
	float surface_exposure = smoothstep(-0.2, 0.7, rock_normal.y);
	float ore = smoothstep(copper_threshold - 0.11, copper_threshold + 0.11,
		broad * 0.72 + fractures * 0.28 + surface_exposure * 0.06);
	float value = dot(scan, vec3(0.299, 0.587, 0.114));
	vec3 host = vec3(value) * host_tint;
	vec3 copper = scan * copper_tint;
	ALBEDO = mix(host, copper, ore);
	NORMAL_MAP = texture(normal_map, UV).rgb;
	NORMAL_MAP_DEPTH = 0.82;
	ROUGHNESS = 0.94;
	SPECULAR = 0.22;
}
