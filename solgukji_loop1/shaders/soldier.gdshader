// 병사 인형 —— 정점 색 알파가 1 인 옷감은 세력색으로 칠한다.
// INSTANCE_CUSTOM:
//   r = 진영 + 옷 밝기×0.5   (아군 0~0.5, 적 1~1.5)
//   g = 시신이면 어둡게(0~0.42), 살아 있으면 -공격 진행(0~1)
//   b = 번쩍(피격). 음수면 갑옷 깨짐 (파갑 · 쇄갑, 11/3) —— 쇠붙이가 녹슬고 금 간 색, 옷감도 바랜다
//   a = 걸음 박자(0~1). 서 있으면 2 를 더한다
// 팔다리는 UV.x(부위)와 UV2(축 자리 x, y)로 모델 좌표 Z 축을 돌며 흔든다 (Models · MeshKit.joint).
// 작은 화면에서도 진영이 읽히게 옷감은 세력색으로 아주 살짝 빛나고, 윤곽에 약한 테두리 빛을 준다.
shader_type spatial;
render_mode cull_disabled;

uniform vec3 team_a : source_color = vec3(0.25, 0.5, 0.82);
uniform vec3 team_b : source_color = vec3(0.78, 0.27, 0.23);
uniform float team_glow = 0.05;
uniform vec3 rim_a : source_color = vec3(0.35, 0.75, 1.0);     // 11/4 피아식별 —— 진영 윤곽빛 (soldier_gpu 와 같다)
uniform vec3 rim_b : source_color = vec3(1.0, 0.42, 0.22);
uniform vec3 pulse_col : source_color = vec3(1.0, 0.82, 0.35); // 장수 스킬 펄스 (금빛)
varying float v_pulse;
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
	v_pulse = 0.0;
	if (ic.g < -1.5) {            // 장수 스킬 펄스 (War3D: g = -2 - 세기)
		v_pulse = clamp(-ic.g - 2.0, 0.0, 1.0);
		atk = 0.0;
	}
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
	float brk = clamp(-v_custom.b, 0.0, 1.0);
	float fl = max(v_custom.b, 0.0);
	if (brk > 0.0) {
		// 쇠붙이(옷감이 아닌 곳)는 녹 · 그을음, 금 간 무늬는 모델 좌표로 (병사마다 달라 보이게 옷 밝기로 밀어 준다)
		vec3 rust = vec3(0.30, 0.13, 0.06) * (0.7 + 0.6 * vc.r);
		float crack = step(0.82, fract(sin(dot(floor(UV * 9.0 + v_custom.a * 13.0), vec2(12.9898, 78.233))) * 43758.5453));
		vec3 broken = mix(rust, vec3(0.05), crack * 0.8);
		base = mix(base, broken, brk * (1.0 - COLOR.a) * 0.85);
		base = mix(base, base * vec3(0.72, 0.62, 0.55), brk * COLOR.a * 0.6);     // 옷감도 바래고 그을린다
	}
	base = mix(base, vec3(1.0, 0.92, 0.85), fl);
	ALBEDO = base;
	ROUGHNESS = mix(0.8, mix(0.45, 0.95, brk), step(0.6, vc.b) * (1.0 - COLOR.a));   // 쇠붙이는 조금 반짝인다 (깨지면 윤기가 없다)
	EMISSION = team * team_glow * COLOR.a * clamp(alive, 0.0, 1.0) + vec3(1.0, 0.9, 0.8) * fl * 0.6 + vec3(0.9, 0.35, 0.1) * brk * 0.08 * (0.6 + 0.4 * sin(TIME * 5.0));
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.5);
	float pz = v_pulse;     // 깜빡임 없이 서서히 사라짐 (11/5)
	EMISSION += (mix(rim_a, rim_b, v_custom.r) * 0.55 + pulse_col * pz * 1.4) * fres * clamp(alive, 0.0, 1.0) + pulse_col * pz * 0.25;
	RIM = 0.2 * clamp(alive, 0.0, 1.0);     // 세면 작은 병사가 빛 덩어리로 뭉개진다
	RIM_TINT = 0.3;
}
