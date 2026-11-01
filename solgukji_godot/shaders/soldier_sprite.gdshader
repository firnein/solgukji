// 병사 그림 판 (10/31 사용자: 일러스트 병사 스프라이트) —— 병종마다 한 장의 묶음 그림(4 x 2 칸)을 카메라를 향해 세워 그린다.
// 칸: 1 서 있기 · 2 걷기 A · 3 걷기 B · 4 공격 준비 · 5 공격 · 6 맞음 · 7 쓰러짐 · 8 (예비)
// 그림은 오른쪽을 보고 있다. 병사가 카메라 기준 왼쪽을 보면 좌우를 뒤집는다.
// 마젠타(#FF00FF 근처) 부분은 세력색으로 바꾼다 (명암은 남긴다).
// INSTANCE_CUSTOM 은 soldier.gdshader 와 같다: r 진영 + 옷 밝기 · g 어둡게(+)/공격 진행(-) · b 번쩍 · a 걸음 박자(+2 서 있음)
shader_type spatial;
render_mode cull_disabled, depth_prepass_alpha;

uniform sampler2D atlas : source_color, filter_linear_mipmap, repeat_disable;
uniform vec3 team_a : source_color = vec3(0.25, 0.5, 0.82);
uniform vec3 team_b : source_color = vec3(0.78, 0.27, 0.23);
uniform float cols = 4.0;
uniform float rows = 2.0;

varying vec4 v_custom;
varying float v_frame;
varying float v_flip;

void vertex() {
	vec4 ic = INSTANCE_CUSTOM;
	float team = step(0.75, ic.r);
	float tint = clamp((ic.r - team) * 2.0, 0.0, 1.0);
	float dark = max(ic.g, 0.0);
	float atk = max(-ic.g, 0.0);
	float moving = step(ic.a, 1.5);
	float ph = fract(ic.a);
	v_custom = vec4(team, dark, ic.b, tint);
	float f = 0.0;
	if (dark > 0.01) f = 6.0;
	else if (atk > 0.0) f = atk < 0.45 ? 3.0 : 4.0;
	else if (ic.b > 0.25) f = 5.0;
	else if (moving > 0.5) f = ph < 0.5 ? 1.0 : 2.0;
	v_frame = f;
	// 바라보는 쪽 —— 모델 +X 가 카메라 오른쪽이면 그대로, 왼쪽이면 뒤집는다
	vec3 facing = normalize(MODEL_MATRIX[0].xyz);
	v_flip = dot(facing, INV_VIEW_MATRIX[0].xyz) < 0.0 ? 1.0 : 0.0;
	// 세운 판 —— 위는 늘 위, 옆은 카메라 오른쪽. 크기는 인스턴스 배율
	float sc = length(MODEL_MATRIX[1].xyz);
	vec3 right = normalize(vec3(INV_VIEW_MATRIX[0].x, 0.0, INV_VIEW_MATRIX[0].z));
	vec3 wpos = MODEL_MATRIX[3].xyz + right * VERTEX.x * sc + vec3(0.0, 1.0, 0.0) * VERTEX.y * sc;
	if (dark > 0.01) wpos.y -= 0.05;
	VERTEX = (inverse(MODEL_MATRIX) * vec4(wpos, 1.0)).xyz;
	NORMAL = (inverse(MODEL_MATRIX) * vec4(-normalize(INV_VIEW_MATRIX[2].xyz), 0.0)).xyz;
}

void fragment() {
	vec2 uv = UV;
	if (v_flip > 0.5) uv.x = 1.0 - uv.x;
	float fx = mod(v_frame, cols);
	float fy = floor(v_frame / cols);
	vec2 auv = vec2((fx + uv.x) / cols, (fy + uv.y) / rows);
	vec4 c = texture(atlas, auv);
	if (c.a < 0.45) discard;
	vec3 col = c.rgb;
	// 마젠타 → 세력색 (밝기를 살려 곱한다)
	float mag = smoothstep(0.18, 0.4, min(col.r, col.b) - col.g);
	vec3 team = mix(team_a, team_b, v_custom.r) * (0.85 + 0.3 * v_custom.a);
	float lum = max(col.r, col.b);
	col = mix(col, team * lum * 1.35, mag);
	col *= 1.0 - v_custom.g * 1.3;
	col = mix(col, vec3(1.0, 0.92, 0.85), v_custom.b);
	ALBEDO = col;
	ROUGHNESS = 0.9;
	SPECULAR = 0.1;
	EMISSION = team * 0.06 * mag;
}
