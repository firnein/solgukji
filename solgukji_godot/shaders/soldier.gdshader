// 병사 인형 —— 정점 색 알파가 1 인 옷감은 세력색으로 칠한다.
// INSTANCE_CUSTOM:
//   r = 진영 + 옷 밝기×0.5   (아군 0~0.5, 적 1~1.5)
//   g = 시신이면 어둡게(0~0.42), 살아 있으면 -공격 진행(0~1)
//   b = 번쩍(피격)
//   a = 걸음 박자(0~1). 서 있으면 2 를 더한다
// 팔다리는 UV.x(부위)와 UV2(축 자리 x, y)로 모델 좌표 Z 축을 돌며 흔든다 (Models · MeshKit.joint).
// 작은 화면에서도 진영이 읽히게 옷감은 세력색으로 은은히 빛나고, 윤곽에 테두리 빛을 준다.
shader_type spatial;
render_mode cull_disabled;

uniform vec3 team_a : source_color = vec3(0.25, 0.5, 0.82);
uniform vec3 team_b : source_color = vec3(0.78, 0.27, 0.23);
uniform float team_glow = 0.16;
varying vec4 v_custom;     // r 진영, g 어둡게, b 번쩍, a 옷 밝기

vec2 rot(vec2 v, float a) {
	float c = cos(a);
	float s = sin(a);
	return vec2(c * v.x - s * v.y, s * v.x + c * v.y);
}

void vertex() {
	vec4 ic = INSTANCE_CUSTOM;
	float team = step(0.75, ic.r);
	float tint = clamp((ic.r - team) * 2.0, 0.0, 1.0);
	float dark = max(ic.g, 0.0);
	float atk = max(-ic.g, 0.0);
	float mv = step(ic.a, 1.5);
	float ph = fract(ic.a) * 6.2831853;
	v_custom = vec4(team, dark, ic.b, tint);
	float part = floor(UV.x + 0.5);
	if (part > 0.5 && dark <= 0.0) {
		float idle = sin(TIME * 1.7 + tint * 40.0) * 0.06;
		float sw = sin(ph);
		float a = 0.0;
		if (part < 1.5) a = sw * 0.6 * mv;
		else if (part < 2.5) a = -sw * 0.6 * mv;
		else if (part < 3.5) a = -sw * 0.4 * mv + idle;
		else if (part < 4.5) a = 1.3 * sin(3.14159265 * atk) + idle * 0.5;    // 찌르기·내려치기
		else if (part < 5.5) a = sw * 0.75 * mv;
		else if (part < 6.5) a = -sw * 0.75 * mv;
		else a = sw * 0.4 * mv - idle;
		vec2 d = VERTEX.xy - UV2;
		VERTEX.xy = UV2 + rot(d, a);
		NORMAL.xy = rot(NORMAL.xy, a);
	}
}

void fragment() {
	vec3 team = mix(team_a, team_b, v_custom.r);
	vec3 vc = pow(COLOR.rgb, vec3(2.2));    // 정점 색은 sRGB 로 적었다
	vec3 base = mix(vc, vc * team, COLOR.a);
	base *= mix(1.0, 0.82 + 0.36 * v_custom.a, COLOR.a);   // 같은 부대라도 옷 색이 조금씩 다르다
	float alive = 1.0 - v_custom.g * 2.0;
	base *= 1.0 - v_custom.g;
	base = mix(base, vec3(1.0, 0.92, 0.85), v_custom.b);
	ALBEDO = base;
	ROUGHNESS = mix(0.8, 0.45, step(0.6, vc.b) * (1.0 - COLOR.a));   // 쇠붙이는 조금 반짝인다
	EMISSION = team * team_glow * COLOR.a * clamp(alive, 0.0, 1.0) + vec3(1.0, 0.9, 0.8) * v_custom.b * 0.6;
	RIM = 0.6 * clamp(alive, 0.0, 1.0);
	RIM_TINT = 0.55;
}
