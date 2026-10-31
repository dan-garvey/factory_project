shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

uniform sampler2D albedo_map : source_color, repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D normal_map : hint_normal, repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D arm_map : repeat_enable, filter_linear_mipmap_anisotropic;
uniform float source_extent = 1.4;
uniform sampler2D stone_albedo_map : source_color, repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D stone_normal_map : hint_normal, repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D stone_arm_map : repeat_enable, filter_linear_mipmap_anisotropic;
uniform float stone_extent = 1.5;

varying vec3 world_point;
varying vec3 world_normal;
varying vec3 meadow_factors;

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

SurfaceSample sample_patch(vec2 uv, vec2 dx, vec2 dy, vec2 vertex) {
	vec3 seed = patch_hash(vertex);
	float quarter = floor(seed.z * 4.0);
	vec2 axis = quarter < 1.0 ? vec2(1.0, 0.0) :
		quarter < 2.0 ? vec2(0.0, 1.0) : quarter < 3.0 ? vec2(-1.0, 0.0) : vec2(0.0, -1.0);
	mat2 turn = mat2(axis, vec2(-axis.y, axis.x));
	vec2 position = turn * uv + seed.xy;
	vec2 uv_dx = turn * dx;
	vec2 uv_dy = turn * dy;
	SurfaceSample result;
	result.normal = textureGrad(normal_map, position, uv_dx, uv_dy).rgb * 2.0 - 1.0;
	result.normal.xy = transpose(turn) * result.normal.xy;
	result.color = textureGrad(albedo_map, position, uv_dx, uv_dy).rgb;
	result.scalars = textureGrad(arm_map, position, uv_dx, uv_dy).rg;
	return result;
}

SurfaceSample sample_plane(vec2 point, vec2 dx, vec2 dy, vec3 mean) {
	vec2 uv = point / source_extent;
	vec2 patch_point = uv * 0.5;
	vec2 skew = vec2(patch_point.x - patch_point.y * 0.5773502692, patch_point.y * 1.1547005384);
	vec2 cell = floor(skew);
	vec2 fraction = fract(skew);
	vec2 a;
	vec2 b;
	vec2 c;
	vec3 weights;
	if (fraction.x + fraction.y < 1.0) {
		a = cell;
		b = cell + vec2(1.0, 0.0);
		c = cell + vec2(0.0, 1.0);
		weights = vec3(1.0 - fraction.x - fraction.y, fraction.x, fraction.y);
	} else {
		a = cell + vec2(1.0);
		b = cell + vec2(0.0, 1.0);
		c = cell + vec2(1.0, 0.0);
		weights = vec3(fraction.x + fraction.y - 1.0, 1.0 - fraction.x, 1.0 - fraction.y);
	}
	// Adjacent triangles share the same patch at each lattice vertex. The
	// photographic scale and derivatives stay unchanged by patch placement.
	weights = weights * weights * weights;
	weights = max(weights - vec3(0.035), vec3(0.0));
	weights /= dot(weights, vec3(1.0));
	vec2 s_dx = dx / source_extent;
	vec2 s_dy = dy / source_extent;
	SurfaceSample result;
	result.color = vec3(0.0);
	result.normal = vec3(0.0);
	result.scalars = vec2(0.0);
	if (weights.x > 0.0) {
		SurfaceSample first = sample_patch(uv, s_dx, s_dy, a);
		result.color += first.color * weights.x;
		result.normal += first.normal * weights.x;
		result.scalars += first.scalars * weights.x;
	}
	if (weights.y > 0.0) {
		SurfaceSample second = sample_patch(uv, s_dx, s_dy, b);
		result.color += second.color * weights.y;
		result.normal += second.normal * weights.y;
		result.scalars += second.scalars * weights.y;
	}
	if (weights.z > 0.0) {
		SurfaceSample third = sample_patch(uv, s_dx, s_dy, c);
		result.color += third.color * weights.z;
		result.normal += third.normal * weights.z;
		result.scalars += third.scalars * weights.z;
	}
	result.normal = normalize(result.normal);
	float variance_weight = sqrt(dot(weights, weights));
	result.color = clamp(mean + (result.color - mean) / variance_weight, vec3(0.0), vec3(1.0));
	return result;
}

SurfaceSample sample_stone_plane(vec2 point, vec2 dx, vec2 dy) {
	vec2 uv = point / stone_extent;
	SurfaceSample result;
	result.color = textureGrad(stone_albedo_map, uv, dx / stone_extent, dy / stone_extent).rgb;
	result.normal = textureGrad(stone_normal_map, uv, dx / stone_extent, dy / stone_extent).rgb * 2.0 - 1.0;
	result.scalars = textureGrad(stone_arm_map, uv, dx / stone_extent, dy / stone_extent).rg;
	return result;
}

void vertex() {
	world_point = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize(MODEL_NORMAL_MATRIX * NORMAL);
	float boundary = broad_noise(world_point.xz / 2.8 + vec2(11.7, -3.9)) - 0.5;
	vec2 drift = vec2(broad_noise(world_point.xz / 23.0 + vec2(7.3, 2.1)),
		broad_noise(world_point.xz / 23.0 + vec2(-4.8, 13.7)));
	vec2 meadow = world_point.xz / 6.5 + drift * 2.0;
	float cover = broad_noise(meadow) * 0.65 + broad_noise(meadow * 2.13 + vec2(3.7, -8.1)) * 0.35;
	float macro_var = mix(0.88, 1.08, broad_noise(world_point.xz / 31.0 + vec2(3.7, 1.2)));
	meadow_factors = vec3(boundary, smoothstep(0.22, 0.78, cover), macro_var);
}

void fragment() {
	vec3 base = normalize(world_normal);
	vec3 face_sign = step(vec3(0.0), base) * 2.0 - 1.0;
	float exposure = 1.0 - abs(base.y);
	vec3 weights;
	float stone_weight = 0.0;
	if (exposure < 0.14) {
		weights = vec3(0.0, 1.0, 0.0);
	} else {
		weights = pow(abs(base), vec3(8.0));
		weights /= weights.x + weights.y + weights.z;
		stone_weight = smoothstep(0.18, 0.43,
			exposure + meadow_factors.x * 0.50 * smoothstep(0.08, 0.22, exposure));
	}
	vec3 dx = dFdx(world_point);
	vec3 dy = dFdy(world_point);
	vec3 mean = textureLod(albedo_map, vec2(0.5), 10.0).rgb;
	vec3 color = vec3(0.0);
	vec2 scalars = vec2(0.0);
	vec3 detail = vec3(0.0);
	vec3 stone_color = vec3(0.0);
	vec2 stone_scalars = vec2(0.0);
	vec3 stone_detail = vec3(0.0);
	if (weights.x > 0.001) {
		vec2 point = vec2(-world_point.z * face_sign.x, world_point.y);
		vec2 point_dx = vec2(-dx.z * face_sign.x, dx.y);
		vec2 point_dy = vec2(-dy.z * face_sign.x, dy.y);
		SurfaceSample s = sample_plane(point, point_dx, point_dy, mean);
		color += s.color * weights.x;
		scalars += s.scalars * weights.x;
		detail += vec3(0.0, s.normal.y, -s.normal.x * face_sign.x) * weights.x / max(s.normal.z, 0.25);
		if (stone_weight > 0.001) {
			SurfaceSample rock = sample_stone_plane(point, point_dx, point_dy);
			stone_color += rock.color * weights.x;
			stone_scalars += rock.scalars * weights.x;
			stone_detail += vec3(0.0, rock.normal.y, -rock.normal.x * face_sign.x) * weights.x / max(rock.normal.z, 0.25);
		}
	}
	if (weights.y > 0.001) {
		vec2 point = vec2(world_point.x * face_sign.y, -world_point.z);
		vec2 point_dx = vec2(dx.x * face_sign.y, -dx.z);
		vec2 point_dy = vec2(dy.x * face_sign.y, -dy.z);
		SurfaceSample s = sample_plane(point, point_dx, point_dy, mean);
		color += s.color * weights.y;
		scalars += s.scalars * weights.y;
		detail += vec3(s.normal.x * face_sign.y, 0.0, -s.normal.y) * weights.y / max(s.normal.z, 0.25);
		if (stone_weight > 0.001) {
			SurfaceSample rock = sample_stone_plane(point, point_dx, point_dy);
			stone_color += rock.color * weights.y;
			stone_scalars += rock.scalars * weights.y;
			stone_detail += vec3(rock.normal.x * face_sign.y, 0.0, -rock.normal.y) * weights.y / max(rock.normal.z, 0.25);
		}
	}
	if (weights.z > 0.001) {
		vec2 point = vec2(world_point.x * face_sign.z, world_point.y);
		vec2 point_dx = vec2(dx.x * face_sign.z, dx.y);
		vec2 point_dy = vec2(dy.x * face_sign.z, dy.y);
		SurfaceSample s = sample_plane(point, point_dx, point_dy, mean);
		color += s.color * weights.z;
		scalars += s.scalars * weights.z;
		detail += vec3(s.normal.x * face_sign.z, s.normal.y, 0.0) * weights.z / max(s.normal.z, 0.25);
		if (stone_weight > 0.001) {
			SurfaceSample rock = sample_stone_plane(point, point_dx, point_dy);
			stone_color += rock.color * weights.z;
			stone_scalars += rock.scalars * weights.z;
			stone_detail += vec3(rock.normal.x * face_sign.z, rock.normal.y, 0.0) * weights.z / max(rock.normal.z, 0.25);
		}
	}
	// A flat source normal leaves the original terrain normal intact on slopes.
	detail = mix(detail, stone_detail, stone_weight);
	detail -= base * dot(base, detail);
	NORMAL = normalize((VIEW_MATRIX * vec4(normalize(base + detail), 0.0)).xyz);
	// Keep the photograph's brightness detail without its saturated lawn cast.
	float luminance = dot(color, vec3(0.2126, 0.7152, 0.0722));
	vec3 meadow_base = mix(vec3(luminance), color, 0.62);
	vec3 tint = mix(vec3(0.80, 0.84, 0.77), vec3(1.10, 1.03, 0.88), meadow_factors.y);
	vec3 meadow_color = meadow_base * tint * meadow_factors.z;
	ALBEDO = COLOR.rgb * mix(meadow_color, stone_color, stone_weight);
	ROUGHNESS = mix(scalars.y, stone_scalars.y, stone_weight);
	AO = mix(scalars.x, stone_scalars.x, stone_weight);
	AO_LIGHT_AFFECT = 0.0;
	METALLIC = 0.0;
}
