shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

uniform sampler2D albedo_map : source_color, repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D normal_map : hint_normal, repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D arm_map : repeat_enable, filter_linear_mipmap_anisotropic;
uniform float source_extent = 1.3;

varying vec3 world_point;
varying vec3 world_normal;

struct SurfaceSample {
	vec3 color;
	vec3 normal;
	vec2 scalars;
};

vec3 patch_hash(vec2 cell) {
	vec3 p = fract(vec3(cell.xyx) * vec3(0.1031, 0.1030, 0.0973));
	p += dot(p, p.yxz + 33.33);
	return fract((p.xxy + p.yzz) * p.zyx);
}

float broad_noise(vec2 point) {
	vec2 cell = floor(point);
	vec2 t = fract(point);
	t = t * t * (3.0 - 2.0 * t);
	return mix(mix(patch_hash(cell).x, patch_hash(cell + vec2(1.0, 0.0)).x, t.x),
		mix(patch_hash(cell + vec2(0.0, 1.0)).x, patch_hash(cell + vec2(1.0)).x, t.x), t.y);
}

SurfaceSample sample_plane(vec2 point, vec2 dx, vec2 dy, float blend) {
	vec2 uv = point / source_extent;
	vec2 uv_dx = dx / source_extent;
	vec2 uv_dy = dy / source_extent;
	// Both coordinate frames retain the photographed physical extent.
	mat2 turn = mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8));
	vec2 second = turn * uv + vec2(0.37, 0.71);
	vec2 second_dx = turn * uv_dx;
	vec2 second_dy = turn * uv_dy;
	SurfaceSample result;
	vec3 first_normal = textureGrad(normal_map, uv, uv_dx, uv_dy).rgb * 2.0 - 1.0;
	vec3 second_normal = textureGrad(normal_map, second, second_dx, second_dy).rgb * 2.0 - 1.0;
	second_normal.xy = transpose(turn) * second_normal.xy;
	result.normal = normalize(mix(first_normal, second_normal, blend));
	result.color = mix(textureGrad(albedo_map, uv, uv_dx, uv_dy).rgb,
		textureGrad(albedo_map, second, second_dx, second_dy).rgb, blend);
	vec3 mean = textureLod(albedo_map, vec2(0.5), 10.0).rgb;
	float variance_weight = sqrt(blend * blend + (1.0 - blend) * (1.0 - blend));
	result.color = clamp(mean + (result.color - mean) / variance_weight, vec3(0.0), vec3(1.0));
	result.scalars = mix(textureGrad(arm_map, uv, uv_dx, uv_dy).rg,
		textureGrad(arm_map, second, second_dx, second_dy).rg, blend);
	return result;
}

void vertex() {
	world_point = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize(MODEL_NORMAL_MATRIX * NORMAL);
}

void fragment() {
	vec3 base = normalize(world_normal);
	vec3 face_sign = step(vec3(0.0), base) * 2.0 - 1.0;
	vec3 weights = pow(abs(base), vec3(8.0));
	weights /= weights.x + weights.y + weights.z;
	vec3 dx = dFdx(world_point);
	vec3 dy = dFdy(world_point);
	float broad = broad_noise(world_point.xz / 17.0);
	float blend = mix(0.30, 0.70, broad);
	vec3 color = vec3(0.0);
	vec2 scalars = vec2(0.0);
	vec3 detail = vec3(0.0);
	if (weights.x > 0.001) {
		SurfaceSample s = sample_plane(vec2(-world_point.z * face_sign.x, world_point.y),
			vec2(-dx.z * face_sign.x, dx.y), vec2(-dy.z * face_sign.x, dy.y), blend);
		color += s.color * weights.x;
		scalars += s.scalars * weights.x;
		detail += vec3(0.0, s.normal.y, -s.normal.x * face_sign.x) * weights.x / max(s.normal.z, 0.25);
	}
	if (weights.y > 0.001) {
		SurfaceSample s = sample_plane(vec2(world_point.x * face_sign.y, -world_point.z),
			vec2(dx.x * face_sign.y, -dx.z), vec2(dy.x * face_sign.y, -dy.z), blend);
		color += s.color * weights.y;
		scalars += s.scalars * weights.y;
		detail += vec3(s.normal.x * face_sign.y, 0.0, -s.normal.y) * weights.y / max(s.normal.z, 0.25);
	}
	if (weights.z > 0.001) {
		SurfaceSample s = sample_plane(vec2(world_point.x * face_sign.z, world_point.y),
			vec2(dx.x * face_sign.z, dx.y), vec2(dy.x * face_sign.z, dy.y), blend);
		color += s.color * weights.z;
		scalars += s.scalars * weights.z;
		detail += vec3(s.normal.x * face_sign.z, s.normal.y, 0.0) * weights.z / max(s.normal.z, 0.25);
	}
	// A flat source normal leaves the original terrain normal intact on slopes.
	detail -= base * dot(base, detail);
	NORMAL = normalize((VIEW_MATRIX * vec4(normalize(base + detail), 0.0)).xyz);
	vec3 tint = mix(vec3(0.88, 0.94, 0.84), vec3(1.04, 1.01, 0.96), broad);
	ALBEDO = color * COLOR.rgb * tint * mix(0.92, 1.02, broad_noise(world_point.xz / 41.0 + vec2(3.7, 1.2)));
	ROUGHNESS = scalars.y;
	AO = scalars.x;
	AO_LIGHT_AFFECT = 0.0;
	METALLIC = 0.0;
}
