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
// 11/9 사용자 '전투맵은 매판 다양하게' —— 지형 요소를 늘린다 (모두 화면만, 판정과 무관). Type2View._roll_ground 가 전투 시드로 정한다
uniform float river_x = 9999.0;          // 가로지르는 강 (전장 x, 진영 사이를 끊어 흐른다 —— 9999 면 없음)
uniform float river_w = 26.0;            // 강 반폭
uniform vec2 lake = vec2(9999.0);        // 호수 가운데 (전장 좌표, 9999 면 없음)
uniform float lake_r = 120.0;            // 호수 반지름
uniform float farm_amt = 0.0;            // 밭이랑 (0 이면 없음) —— 가운데서 먼 한쪽에 줄무늬 논밭
uniform float farm_side = 9999.0;        // 밭이 놓이는 쪽 (전장 y 문턱, 부호가 쪽)
uniform float forest_bias = 0.0;         // 숲을 한쪽으로 (-1 ~ 1: 0 이면 양옆 같게)
uniform float snow = 0.0;                // 1 이면 눈밭 —— 나무 · 바위 색이 겨울빛
uniform vec3 tree_lo : source_color = vec3(0.20, 0.30, 0.17);
uniform vec3 tree_hi : source_color = vec3(0.32, 0.43, 0.22);
uniform float detail = 1.0;              // 11/7 부하: 0 이면 잡음을 2옥타브로 (대군 전투 —— Type2View.setup 이 정해 전투 내내 같다). 화면 전체 픽셀마다 도는 셰이더라 휴대폰 GPU 몫이 크다

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
	int oct = detail > 0.5 ? 4 : 2;
	for (int i = 0; i < oct; i++) {
		v += a * noise(p);
		p = p * 2.03 + vec2(17.0, 9.0);
		a *= 0.5;
	}
	return detail > 0.5 ? v : v * 1.25;      // 2옥타브 합(0.75)을 4옥타브(0.9375)와 같은 범위로
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
	// 밭이랑 —— 한쪽 들에 줄무늬 (전장 x 방향 이랑, 둑으로 구획)
	if (farm_amt > 0.0 && farm_side < 9000.0) {
		float fs = farm_side > 0.0 ? smoothstep(farm_side, farm_side + 90.0, w.y - mid_y) : smoothstep(-farm_side, -farm_side + 90.0, mid_y - w.y);
		float patch = smoothstep(0.45, 0.55, fbm(ws * 0.0025 + 41.0));
		fs *= patch * farm_amt;
		float row = 0.5 + 0.5 * sin(w.y * 0.5 + 3.0 * sin(w.x * 0.02));
		vec3 fc = mix(vec3(0.46, 0.40, 0.26), vec3(0.58, 0.52, 0.30), row) * (0.94 + 0.1 * n2);
		col = mix(col, fc, fs * 0.8);
		float dyke = 1.0 - smoothstep(3.0, 6.0, abs(mod(w.x + 50.0 * sin(w.y * 0.01), 140.0) - 70.0));
		col = mix(col, vec3(0.40, 0.35, 0.24), fs * dyke * 0.6);
	}
	// 가로지르는 강 —— 진영 사이를 끊어 흐른다 (여울은 얕아 모래빛)
	if (river_x < 9000.0) {
		float rx = river_x + 90.0 * sin(w.y * 0.004 + seed_off.y * 0.013) + 30.0 * sin(w.y * 0.012 + 0.8);
		float rd = abs(w.x - rx);
		float ford = smoothstep(0.55, 0.75, 0.5 + 0.5 * sin(w.y * 0.011 + seed_off.x * 0.02));
		float bank = (1.0 - smoothstep(river_w + 8.0, river_w + 16.0, rd)) * 0.5;
		col = mix(col, vec3(0.50, 0.45, 0.33), bank * 0.7);
		vec3 water = mix(vec3(0.27, 0.43, 0.54), vec3(0.34, 0.50, 0.58), n2);
		vec3 shallow = vec3(0.52, 0.56, 0.52);
		col = mix(col, mix(water, shallow, ford * 0.8), 1.0 - smoothstep(river_w - 3.0, river_w, rd));
		float ripple = 0.5 + 0.5 * sin(w.y * 0.25 + w.x * 0.05 + seed_off.x);
		col = mix(col, col * 1.08, (1.0 - smoothstep(river_w - 6.0, river_w - 2.0, rd)) * ripple * 0.3 * (1.0 - ford));
	}
	// 호수 —— 둥근 물, 둘레는 젖은 흙
	if (lake.x < 9000.0) {
		vec2 lp = ws - lake;
		float ld = length(lp * vec2(1.0, 0.8)) + 18.0 * fbm(lp * 0.02 + 5.0);
		col = mix(col, vec3(0.42, 0.40, 0.30), (1.0 - smoothstep(lake_r, lake_r + 24.0, ld)) * 0.5);
		col = mix(col, mix(vec3(0.25, 0.40, 0.50), vec3(0.31, 0.47, 0.55), n2), 1.0 - smoothstep(lake_r - 4.0, lake_r, ld));
	}
	// 바위 · 덤불
	if (rock_amt > 0.0) {
		vec2 rc = floor(ws / 46.0);
		vec2 rp = (rc + 0.5 + (vec2(hash(rc + 2.1), hash(rc + 4.3)) - 0.5) * 0.7) * 46.0;
		float on = step(1.0 - rock_amt * 0.16, hash(rc + 7.7));
		float rr = 4.0 + 4.0 * hash(rc + 9.1);
		float d = length(ws - rp);
		col = mix(col, col * 0.6, on * (1.0 - smoothstep(rr, rr + 2.0, length(ws - rp - vec2(-2.0, 2.0)))));
		vec3 rk = hash(rc + 5.5) < 0.5 ? mix(vec3(0.52, 0.50, 0.46), vec3(0.70, 0.72, 0.74), snow) : mix(vec3(0.26, 0.36, 0.20), vec3(0.30, 0.34, 0.30), snow);
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
	float side = smoothstep(forest_side, forest_side + 160.0, abs(w.y - mid_y - forest_bias * 180.0));      // 11/9 forest_bias: 숲을 한쪽으로
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
		vec3 leaf = mix(tree_lo, tree_hi, clamp(dot(normalize(ws - tc + 0.001), vec2(0.7, -0.7)) * 0.5 + 0.5, 0.0, 1.0));
		col = mix(col, leaf * (0.9 + 0.2 * hash(cell + 1.7)), t);
	}
	// 가장자리 어둡게
	vec2 q = UV - 0.5;
	col *= 1.0 - dot(q, q) * 0.35;      // 11/6 적이 있는 위쪽이 너무 어두웠다
	COLOR = vec4(col, 1.0);
}
