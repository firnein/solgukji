// 지형 —— 정점 색(풀·흙·바위)에 월드 좌표 잡음 두 겹을 곱해 결을 낸다.
shader_type spatial;

uniform sampler2D detail : repeat_enable, filter_linear_mipmap;
varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float fine = texture(detail, wpos.xz * 0.09).r;
	float broad = texture(detail, wpos.xz * 0.012 + vec2(0.37, 0.11)).r;
	ALBEDO = pow(COLOR.rgb, vec3(2.2)) * (0.74 + 0.5 * fine) * (0.82 + 0.36 * broad);
	ROUGHNESS = 0.96;
}
