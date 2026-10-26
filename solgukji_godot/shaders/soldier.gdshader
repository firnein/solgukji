// 병사 인형 —— 정점 색 알파가 1 인 옷감은 세력색으로 칠한다.
// INSTANCE_CUSTOM: r = 진영(0 아군, 1 적), g = 어둡게(시신), b = 번쩍(피격), a = 병사마다 다른 옷 밝기
// 작은 화면에서도 진영이 읽히게 옷감은 세력색으로 은은히 빛나고, 윤곽에 테두리 빛을 준다.
shader_type spatial;
render_mode cull_disabled;

uniform vec3 team_a : source_color = vec3(0.25, 0.5, 0.82);
uniform vec3 team_b : source_color = vec3(0.78, 0.27, 0.23);
uniform float team_glow = 0.16;
varying vec4 v_custom;

void vertex() {
	v_custom = INSTANCE_CUSTOM;
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
