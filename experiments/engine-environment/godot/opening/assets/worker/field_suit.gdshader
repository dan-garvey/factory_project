shader_type spatial;

uniform sampler2D base_albedo : source_color, filter_linear_mipmap;
uniform sampler2D suit_albedo : source_color, filter_linear_mipmap;
uniform sampler2D body_normal_map : hint_normal, filter_linear_mipmap;

void fragment() {
	vec3 original = texture(base_albedo, UV).rgb;
	vec3 alternate = texture(suit_albedo, UV).rgb;
	// The original atlas decides where cloth exists. Its skin, footwear and
	// empty UV margins cannot inherit islands shifted by the alternate image.
	float jacket = smoothstep(0.005, 0.025, original.b - original.g)
		* smoothstep(0.08, 0.14, original.r - original.g)
		* smoothstep(0.08, 0.16, original.r);
	float trousers = smoothstep(0.02, 0.05, original.b - original.r)
		* smoothstep(0.05, 0.10, original.b);
	ALBEDO = mix(original, alternate, max(jacket, trousers));
	ROUGHNESS = 0.8;
	NORMAL_MAP = texture(body_normal_map, UV).rgb;
}
