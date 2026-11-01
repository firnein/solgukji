shader_type canvas_item;
// 수묵 화풍 시안 (10/31 —— 삼국지11 쪽) : 전장 3D 화면(SubViewportContainer) 위에 입힌다.
// ① 밝기 경계에 먹선 ② 색을 줄이고 바랜 종이색으로 ③ 계조를 조금 끊어 붓칠처럼 ④ 종이 결 · 가장자리 번짐

uniform float strength : hint_range(0.0, 1.0) = 1.0;   // 0 이면 원래 화면
uniform float ink : hint_range(0.0, 2.0) = 1.0;         // 먹선 진하기
uniform vec3 paper = vec3(0.93, 0.88, 0.76);            // 종이색
uniform vec3 ink_col = vec3(0.10, 0.09, 0.08);

float lum(vec3 c) { return dot(c, vec3(0.299, 0.587, 0.114)); }

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), u.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), u.x), u.y);
}

void fragment() {
	vec4 src = texture(TEXTURE, UV);
	vec2 px = TEXTURE_PIXEL_SIZE * 2.0;
	// 먹선 —— 밝기 소벨
	float tl = lum(texture(TEXTURE, UV + px * vec2(-1, -1)).rgb);
	float t = lum(texture(TEXTURE, UV + px * vec2(0, -1)).rgb);
	float tr = lum(texture(TEXTURE, UV + px * vec2(1, -1)).rgb);
	float l = lum(texture(TEXTURE, UV + px * vec2(-1, 0)).rgb);
	float r = lum(texture(TEXTURE, UV + px * vec2(1, 0)).rgb);
	float bl = lum(texture(TEXTURE, UV + px * vec2(-1, 1)).rgb);
	float b = lum(texture(TEXTURE, UV + px * vec2(0, 1)).rgb);
	float br = lum(texture(TEXTURE, UV + px * vec2(1, 1)).rgb);
	float gx = -tl - 2.0 * l - bl + tr + 2.0 * r + br;
	float gy = -tl - 2.0 * t - tr + bl + 2.0 * b + br;
	float edge = smoothstep(0.30, 0.75, length(vec2(gx, gy)) * ink);
	// 색 —— 채도를 크게 줄이고 계조를 끊어 종이에 얹는다 (진영색 빨강 · 파랑은 조금 남긴다)
	float y = lum(src.rgb);
	float yq = floor(y * 5.0 + 0.5) / 5.0;
	y = mix(y, yq, 0.45);
	vec3 grey = vec3(y);
	float sat = max(src.r, max(src.g, src.b)) - min(src.r, min(src.g, src.b));
	vec3 tint = mix(grey, src.rgb, clamp(0.25 + sat * 1.6, 0.0, 0.9));     // 진한 색(진영색 · 불길)은 남긴다
	vec3 washed = mix(ink_col, paper, smoothstep(0.02, 0.95, y)) * mix(vec3(1.0), tint / max(y, 0.05), clamp(0.3 + sat * 1.5, 0.0, 0.85));
	// 종이 결 · 번짐
	vec2 sp = UV / TEXTURE_PIXEL_SIZE;
	float grain = noise(sp * 0.35) * 0.5 + noise(sp * 0.08) * 0.5;
	washed *= 0.93 + grain * 0.1;
	vec3 col = mix(washed, ink_col, edge * 0.85);
	// 가장자리 —— 종이가 비치듯 밝게 바랜다
	float vig = smoothstep(0.35, 0.75, distance(UV, vec2(0.5)));
	col = mix(col, paper, vig * 0.45);
	COLOR = vec4(mix(src.rgb, col, strength), src.a);
}
