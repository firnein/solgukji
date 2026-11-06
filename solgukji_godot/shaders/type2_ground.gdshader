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
// 11/7 사용자 '전투 지형에 약간의 랜덤성' —— 화면만 (지형 효과는 11/2 에 판정에서 뺐다). 전투마다 Type2View.setup 이 정한다
uniform vec2 seed_off = vec2(0.0);       // 얼룩 · 숲 무늬 자리
uniform vec3 grass_lo : source_color = vec3(0.36, 0.45, 0.27);
uniform vec3 grass_hi : source_color = vec3(0.47, 0.55, 0.31);
uniform float forest_amt = 0.5;          // 숲 문턱 (낮을수록 숲이 많다)
uniform float forest_side = 260.0;       // 가운데서 이만큼 떨어진 곳부터 숲
uniform float soil_amt = 0.0;            // 흙 · 마른 땅 얼룩
uniform float road_y = 9999.0;           // 옆길 (전장 y, 9999 면 없음)
uniform float creek_y = 9999.0;          // 개울 (전장 y, 9999 면 없음)
uniform float rock_amt = 0.0;            // 바위 · 덤불 흩뿌림

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
	vec2 ws = w + seed_off;
	float n = fbm(ws * 0.004);
	float n2 = fbm(ws * 0.022 + 7.0);
	vec3 col = mix(grass_lo, grass_hi, n);
	col *= 0.93 + 0.14 * n2;
	// 마른 흙 얼룩
	float soil = smoothstep(0.62 - soil_amt * 0.25, 0.72 - soil_amt * 0.25, fbm(ws * 0.0028 + 13.0));
	col = mix(col, vec3(0.55, 0.49, 0.35) * (0.94 + 0.12 * n2), soil * 0.55);
	// 옆길 —— 진영 시작선 바깥 옆으로 굽어 지나간다
	if (road_y < 9000.0) {
		float ry = road_y + 60.0 * sin(w.x * 0.004 + seed_off.x * 0.01) + 20.0 * sin(w.x * 0.013);
		float rd = abs(w.y - ry);
		col = mix(col, vec3(0.50, 0.44, 0.32), (1.0 - smoothstep(12.0, 16.0, rd)) * 0.45);
		col = mix(col, vec3(0.62, 0.55, 0.41), (1.0 - smoothstep(7.0, 11.0, rd)) * 0.7);
	}
	// 개울 —— 옅은 물줄기와 둑
	if (creek_y < 9000.0) {
		float cy = creek_y + 80.0 * sin(w.x * 0.0035 + seed_off.y * 0.01) + 25.0 * sin(w.x * 0.011 + 1.7);
		float cd = abs(w.y - cy);
		col = mix(col, col * 0.78, (1.0 - smoothstep(16.0, 22.0, cd)) * 0.5);
		col = mix(col, vec3(0.30, 0.46, 0.55) + 0.06 * n2, 1.0 - smoothstep(9.0, 12.0, cd));
	}
	// 바위 · 덤불
	if (rock_amt > 0.0) {
		vec2 rc = floor(ws / 46.0);
		vec2 rp = (rc + 0.5 + (vec2(hash(rc + 2.1), hash(rc + 4.3)) - 0.5) * 0.7) * 46.0;
		float on = step(1.0 - rock_amt * 0.16, hash(rc + 7.7));
		float rr = 4.0 + 4.0 * hash(rc + 9.1);
		float d = length(ws - rp);
		col = mix(col, col * 0.6, on * (1.0 - smoothstep(rr, rr + 2.0, length(ws - rp - vec2(-2.0, 2.0)))));
		vec3 rk = hash(rc + 5.5) < 0.5 ? vec3(0.52, 0.50, 0.46) : vec3(0.26, 0.36, 0.20);
		col = mix(col, rk * (0.9 + 0.2 * hash(rc)), on * (1.0 - smoothstep(rr - 1.0, rr, d)));
	}
	// 11/6 사용자: 바닥 타일링(육각 · 길 · 흙밭)은 판정과 무관해 뺀다 —— 의미 있는 선만: 양 진영 시작선(진지선)과 가운데 경계
	float da = abs(w.x - camp_a);
	float db = abs(w.x - camp_b);
	col = mix(col, vec3(0.30, 0.42, 0.62), (1.0 - smoothstep(2.0, 5.0, da)) * 0.45);
	col = mix(col, vec3(0.66, 0.32, 0.28), (1.0 - smoothstep(2.0, 5.0, db)) * 0.45);
	float dm = abs(w.x - (camp_a + camp_b) * 0.5);
	col = mix(col, col * 0.86, (1.0 - smoothstep(1.0, 2.5, dm)) * 0.6);
	// 숲 —— 양옆에만, 나무 덩이 (칸마다 하나, 그림자는 화면 오른쪽 아래로)
	float side = smoothstep(forest_side, forest_side + 160.0, abs(w.y - mid_y));
	float fz = smoothstep(forest_amt, forest_amt + 0.1, fbm(ws * 0.003 + 31.0)) * side;
	if (fz > 0.01) {
		float cs = 20.0;
		vec2 cell = floor(ws / cs);
		vec2 o = (vec2(hash(cell), hash(cell + 3.1)) - 0.5) * 6.0;
		vec2 tc = (cell + 0.5) * cs + o;
		float tr = 7.0 + 2.0 * hash(cell + 5.7);
		float keep = step(hash(cell + 9.3), fz * 1.1);
		vec2 sd = ws - (tc + vec2(-2.5, 2.5));         // 그림자 (전장 -x = 화면 아래, +y = 화면 오른쪽)
		col = mix(col, col * 0.62, keep * (1.0 - smoothstep(tr - 1.0, tr + 1.0, length(sd))));
		float td = length(ws - tc);
		float t = keep * (1.0 - smoothstep(tr - 1.0, tr, td));
		vec3 leaf = mix(vec3(0.20, 0.30, 0.17), vec3(0.32, 0.43, 0.22), clamp(dot(normalize(ws - tc + 0.001), vec2(0.7, -0.7)) * 0.5 + 0.5, 0.0, 1.0));
		col = mix(col, leaf * (0.9 + 0.2 * hash(cell + 1.7)), t);
	}
	// 가장자리 어둡게
	vec2 q = UV - 0.5;
	col *= 1.0 - dot(q, q) * 0.35;      // 11/6 적이 있는 위쪽이 너무 어두웠다
	COLOR = vec4(col, 1.0);
}
