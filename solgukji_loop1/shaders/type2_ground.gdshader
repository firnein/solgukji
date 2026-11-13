shader_type canvas_item;
// 타입2 전장 바닥 (11/6) —— 삼국지11 식 채색 지도. 화면 px 를 전장 좌표로 되돌려(Type2View.map 의 역) 그린다.
// 풀빛 얼룩 · 흙밭 · 굽은 길 · 양옆 숲(나무 덩이) · 옅은 육각 격자 · 가장자리 어둡게. CPU 는 매 프레임 uniform 만 넘긴다.

uniform vec2 center;          // 화면 가운데에 오는 전장 자리
uniform float scl = 1.0;      // 전장 px → 화면 px
uniform float tilt = 0.62;    // 세로 눌림
uniform vec2 vsize = vec2(540.0, 800.0);
uniform float mid_y = 0.0;    // 전장 가운데 (가로) —— 숲은 여기서 먼 양옆에만
uniform float hex = 34.0;
uniform float camp_a = -300.0;   // 아군 시작선 (전장 x)
uniform float camp_b = 300.0;    // 적 시작선

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}
float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += a * noise(p);
		p = p * 2.03 + vec2(17.0, 9.0);
		a *= 0.5;
	}
	return v;
}
float hexdist(vec2 p) {
	p = abs(p);
	return max(dot(p, vec2(0.8660254, 0.5)), p.y);
}

void fragment() {
	vec2 px = UV * vsize;
	vec2 w = center + vec2(-(px.y - vsize.y * 0.5) / (scl * tilt), (px.x - vsize.x * 0.5) / scl);
	// 풀빛 —— 큰 얼룩 + 잔 얼룩 (차분한 톤)
	float n = fbm(w * 0.004);
	float n2 = fbm(w * 0.022 + 7.0);
	vec3 col = mix(vec3(0.36, 0.45, 0.27), vec3(0.47, 0.55, 0.31), n);
	col *= 0.93 + 0.14 * n2;
	// 11/6 사용자: 바닥 타일링(육각 · 길 · 흙밭)은 판정과 무관해 뺀다 —— 의미 있는 선만: 양 진영 시작선(진지선)과 가운데 경계
	float da = abs(w.x - camp_a);
	float db = abs(w.x - camp_b);
	col = mix(col, vec3(0.30, 0.42, 0.62), (1.0 - smoothstep(2.0, 5.0, da)) * 0.45);
	col = mix(col, vec3(0.66, 0.32, 0.28), (1.0 - smoothstep(2.0, 5.0, db)) * 0.45);
	float dm = abs(w.x - (camp_a + camp_b) * 0.5);
	col = mix(col, col * 0.86, (1.0 - smoothstep(1.0, 2.5, dm)) * 0.6);
	// 숲 —— 양옆에만, 나무 덩이 (칸마다 하나, 그림자는 화면 오른쪽 아래로)
	float side = smoothstep(260.0, 420.0, abs(w.y - mid_y));
	float fz = smoothstep(0.5, 0.6, fbm(w * 0.003 + 31.0)) * side;
	if (fz > 0.01) {
		float cs = 20.0;
		vec2 cell = floor(w / cs);
		vec2 o = (vec2(hash(cell), hash(cell + 3.1)) - 0.5) * 6.0;
		vec2 tc = (cell + 0.5) * cs + o;
		float tr = 7.0 + 2.0 * hash(cell + 5.7);
		float keep = step(hash(cell + 9.3), fz * 1.1);
		vec2 sd = w - (tc + vec2(-2.5, 2.5));         // 그림자 (전장 -x = 화면 아래, +y = 화면 오른쪽)
		col = mix(col, col * 0.62, keep * (1.0 - smoothstep(tr - 1.0, tr + 1.0, length(sd))));
		float td = length(w - tc);
		float t = keep * (1.0 - smoothstep(tr - 1.0, tr, td));
		vec3 leaf = mix(vec3(0.20, 0.30, 0.17), vec3(0.32, 0.43, 0.22), clamp(dot(normalize(w - tc + 0.001), vec2(0.7, -0.7)) * 0.5 + 0.5, 0.0, 1.0));
		col = mix(col, leaf * (0.9 + 0.2 * hash(cell + 1.7)), t);
	}
	// 가장자리 어둡게
	vec2 q = UV - 0.5;
	col *= 1.0 - dot(q, q) * 0.35;      // 11/6 적이 있는 위쪽이 너무 어두웠다
	COLOR = vec4(col, 1.0);
}
