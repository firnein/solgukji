// 집중 비네트 (11/3) —— 에이스 · 신화 기술 때 시전 부대 둘레만 밝게 남기고 나머지 전장을 어둡게.
// 화면 전체 사각 하나 · 텍스처 읽기 없음 (화면을 다시 읽지 않아 휴대폰에서도 가볍다). 둘레에 등급색 빛무리.
shader_type canvas_item;

uniform vec2 center = vec2(0.5);
uniform float aspect = 0.5;
uniform float radius = 0.2;
uniform float strength = 0.0;
uniform vec4 glow : source_color = vec4(1.0, 0.85, 0.5, 1.0);

void fragment() {
	vec2 d = (UV - center) * vec2(aspect, 1.0);
	float r = length(d) / max(radius, 0.001);
	float dark = smoothstep(0.75, 1.9, r);                 // 둘레 밖으로 갈수록 어둡게
	float halo = exp(-pow((r - 0.85) / 0.22, 2.0)) * 0.35;  // 경계에 빛무리
	vec3 col = mix(glow.rgb * 0.9, vec3(0.0, 0.0, 0.03), dark);
	COLOR = vec4(col, (dark * 0.85 + halo) * strength);
}
