// 실사 나무 판 (10/31) —— 구운 나무 그림(assets/trees)을 위는 위로 세운 채 카메라를 향해 돌린다. 아래 가운데가 밑동.
// 그림자 대신 그림에 구운 명암을 쓰고, 꼭대기만 바람에 살짝 흔든다. COLOR(인스턴스 색) 로 그루마다 색을 조금 바꾼다.
shader_type spatial;
render_mode unshaded, cull_disabled, depth_prepass_alpha;

uniform sampler2D tex : source_color, filter_linear_mipmap, repeat_disable;
uniform float light = 0.82;          // 그림 밝기 (전장 조명과 맞춘다)

varying vec4 v_tint;

void vertex() {
	v_tint = INSTANCE_CUSTOM;
	float sc = length(MODEL_MATRIX[1].xyz);
	vec3 right = normalize(vec3(INV_VIEW_MATRIX[0].x, 0.0, INV_VIEW_MATRIX[0].z));
	vec3 origin = MODEL_MATRIX[3].xyz;
	float sway = sin(TIME * 0.9 + origin.x * 0.3 + origin.z * 0.2) * 0.035 * (1.0 - UV.y);
	vec3 wpos = origin + right * (VERTEX.x + sway * sc) * sc + vec3(0.0, 1.0, 0.0) * VERTEX.y * sc;
	VERTEX = (inverse(MODEL_MATRIX) * vec4(wpos, 1.0)).xyz;
}

void fragment() {
	vec4 c = texture(tex, UV);
	if (c.a < 0.5) discard;
	ALBEDO = c.rgb * light * v_tint.rgb;
	ALPHA = 1.0;
}
