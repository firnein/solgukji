shader_type canvas_item;
render_mode unshaded;
uniform vec2 atlas_pixel_size;
uniform sampler2D idle_atlas : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2D action_blue : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2D action_red : source_color, filter_linear_mipmap, repeat_disable;
uniform vec2 action_blue_pixel_size;
uniform vec2 action_red_pixel_size;
// 11/24 신화 부대 전용 시트 (동작 시트와 같은 4×8 배치 · 인형은 칸의 MYTH_FIT 배 —— 위 · 옆에 배기 · 깃털 · 광배 자리)
uniform sampler2D myth_blue : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2D myth_red : source_color, filter_linear_mipmap, repeat_disable;
uniform bool has_myth = false;
// 신화는 셀 96부터, 불멸은 셀 144부터.
// 진영은 모양 값(style)의 16 자리 (16 이상 = 적군) —— 진영색 테두리 기운으로 가른다
uniform sampler2D hero_atlas : source_color, filter_linear_mipmap, repeat_disable;
uniform vec2 hero_grid = vec2(4.0, 3.0);
uniform vec2 hero_pixel_size;
uniform bool has_hero = false;
uniform sampler2D immortal_hero_atlas : source_color, filter_linear_mipmap, repeat_disable;
uniform vec2 immortal_hero_grid;
uniform vec2 immortal_hero_pixel_size;
uniform bool has_immortal_hero = false;
const vec3 HERO_ALLY = vec3(0.36, 0.7, 1.0);
const vec3 HERO_ENEMY = vec3(1.0, 0.34, 0.2);
varying float hero;       // 1 = 장수 인형
varying float immortal_hero;
varying float enemy;      // 장수 인형이 적군
const float MYTH_FIT = 0.8;      // painted_batch.gd MYTH_FIT · tools/scripts/make_myth_troops.py FIT 와 같게
varying vec4 tint;
varying float shade;      // 11/22 매복 그늘 (0~1) —— 숲 · 바위 지형을 지나는 우회 · 매복 부대
varying float standard;
varying float flag_phase;
varying float action_army;
// 11/24 병사 단계 (0 잡병 · 1 정병 · 2 정예 · 3 근위 · 4 철위 · 5 신병) —— 셀 번호 칸의 128 배 자리 (style = 단계 + 신화면 8)
varying float grade;
varying float myth;
varying vec2 cell_uv;     // 칸 안 좌표 (0~1) —— 기운이 칸 가장자리에서 잘려 보이지 않게
const vec3 RIM_SILVER = vec3(0.9, 0.94, 1.0);
const vec3 RIM_GOLD = vec3(1.0, 0.83, 0.38);
const vec3 OUTLINE = vec3(0.07, 0.05, 0.04);

// top 을 bottom 위에 겹친다 (곧은 알파)
vec4 over(vec4 top, vec4 bottom) {
	float a = top.a + bottom.a * (1.0 - top.a);
	return vec4((top.rgb * top.a + bottom.rgb * bottom.a * (1.0 - top.a)) / max(a, 0.001), a);
}

void vertex() {
	float style = floor(INSTANCE_CUSTOM.a);
	float cell = INSTANCE_CUSTOM.r;
	immortal_hero = (has_immortal_hero && cell >= 144.0) ? 1.0 : 0.0;
	hero = (immortal_hero > 0.5 || (has_hero && cell >= 96.0 && cell < 144.0)) ? 1.0 : 0.0;
	enemy = style >= 16.0 ? 1.0 : 0.0;
	grade = mod(style, 8.0);
	myth = (has_myth && hero < 0.5 && mod(style, 16.0) >= 8.0 && cell >= 32.0) ? 1.0 : 0.0;
	standard = cell >= 16.0 && cell < 18.0 ? cell - 15.0 : 0.0;
	action_army = hero > 0.5 ? 0.0 : (cell >= 64.0 ? 2.0 : (cell >= 32.0 ? 1.0 : 0.0));
	flag_phase = INSTANCE_CUSTOM.g;
	float phase = INSTANCE_CUSTOM.g;
	float strength = INSTANCE_CUSTOM.b;
	float action_cell = mod(cell - 32.0, 32.0);
	bool cavalry = hero > 0.5 ? false : (action_army > 0.5 ? floor(action_cell / 4.0) == 1.0 : mod(cell, 8.0) == 1.0);
	float swing = sin(phase) * strength;
	// 신화 시트는 인형이 칸의 MYTH_FIT 배 (발 기준) —— 다리 구역 · 흔들림 폭을 같은 비율로
	float fit = myth > 0.5 ? MYTH_FIT : 1.0;
	float lower = smoothstep(0.97 - 0.41 * fit, 1.0, UV.y);
	float half_side = mix(-1.0, 1.0, smoothstep(0.5 - 0.19 * fit, 0.5 + 0.17 * fit, UV.x));
	VERTEX.x += swing * fit * (0.009 * (1.0 - lower) + half_side * lower * (cavalry ? 0.055 : 0.05));
	VERTEX.y -= lower * max(0.0, swing * half_side) * (cavalry ? 0.068 : 0.056) * fit;
	cell_uv = UV;
	// Match the legacy mesh's 0.75-pixel inset on each atlas cell.
	vec2 pad = vec2(0.75) * atlas_pixel_size;
	if (hero > 0.5) {
		float hc = cell - (immortal_hero > 0.5 ? 144.0 : 96.0);
		vec2 grid = immortal_hero > 0.5 ? immortal_hero_grid : hero_grid;
		vec2 pixel = immortal_hero > 0.5 ? immortal_hero_pixel_size : hero_pixel_size;
		vec2 h_origin = vec2(mod(hc, grid.x), floor(hc / grid.x));
		UV = (h_origin + UV) / grid;
		UV = mix(UV + pixel * 0.75, UV - pixel * 0.75, UV * grid - h_origin);
	} else if (action_army > 0.5) {
		vec2 action_px = action_army < 1.5 ? action_blue_pixel_size : action_red_pixel_size;
		vec2 grid = vec2(4.0, 8.0);
		vec2 origin = vec2(mod(action_cell, 4.0), floor(action_cell / 4.0));
		UV = (origin + UV) / grid;
		UV = mix(UV + action_px * 0.75, UV - action_px * 0.75, UV * grid - origin);
	} else if (standard < 0.5) {
		UV = (vec2(mod(cell, 4.0), floor(cell / 4.0)) + UV) * 0.25;
		UV = mix(UV + pad, UV - pad, UV * 4.0 - vec2(mod(cell, 4.0), floor(cell / 4.0)));
	}
	tint = COLOR;
	shade = fract(INSTANCE_CUSTOM.a) * 2.0;
}

vec4 sprite_sample(vec2 at) {
	if (immortal_hero > 0.5) { return texture(immortal_hero_atlas, at); }
	if (hero > 0.5) { return texture(hero_atlas, at); }
	if (action_army > 1.5) { return myth > 0.5 ? texture(myth_red, at) : texture(action_red, at); }
	if (action_army > 0.5) { return myth > 0.5 ? texture(myth_blue, at) : texture(action_blue, at); }
	return texture(idle_atlas, at);
}

// 갈래 안에서 읽는 판 —— 미분을 밖에서 재 넘긴다 (흐림은 미분을 키워 밉맵 한 장으로)
vec4 sprite_grad(vec2 at, vec2 dx, vec2 dy) {
	if (immortal_hero > 0.5) { return textureGrad(immortal_hero_atlas, at, dx, dy); }
	if (hero > 0.5) { return textureGrad(hero_atlas, at, dx, dy); }
	if (action_army > 1.5) { return myth > 0.5 ? textureGrad(myth_red, at, dx, dy) : textureGrad(action_red, at, dx, dy); }
	if (action_army > 0.5) { return myth > 0.5 ? textureGrad(myth_blue, at, dx, dy) : textureGrad(action_blue, at, dx, dy); }
	return textureGrad(idle_atlas, at, dx, dy);
}

void fragment() {
	vec2 du = dFdx(UV);
	vec2 dv = dFdy(UV);
	vec4 c = sprite_sample(UV);
	if (standard > 0.5) {
		float pole = (1.0 - smoothstep(0.016, 0.03, abs(UV.x - 0.42))) * step(0.09, UV.y) * step(UV.y, 0.98);
		float flutter = sin(flag_phase - UV.x * 9.0) * 0.025 * smoothstep(0.43, 0.92, UV.x);
		float y = UV.y + flutter;
		float top = 0.12 + (UV.x - 0.44) * 0.16;
		float bottom = 0.48 - (UV.x - 0.44) * 0.09;
		float cloth = step(0.44, UV.x) * step(UV.x, 0.94) * step(top, y) * step(y, bottom);
		// 11/24 근위 이상 —— 금테를 두껍게 · 밝게, 깃대 끝 금 창날 / 철위 이상 —— 깃발 아래 금 술 두 가닥
		float trim = 0.025 + 0.012 * max(grade - 2.0, 0.0);
		float edge = cloth * (step(y, top + trim) + step(bottom - trim, y) + step(0.94 - trim * 1.2, UV.x));
		vec3 flag_color = standard < 1.5 ? vec3(0.19, 0.37, 0.59) : vec3(0.64, 0.20, 0.13);
		if (grade > 4.5) {
			flag_color = standard < 1.5 ? vec3(0.13, 0.32, 0.78) : vec3(0.78, 0.12, 0.08);
		}
		vec3 gold = grade > 2.5 ? vec3(1.0, 0.84, 0.4) : vec3(0.88, 0.75, 0.48);
		float stripe = cloth * step(abs(UV.x - 0.65) + abs(y - 0.31), 0.085);
		vec3 flag_rgb = mix(flag_color, gold, clamp(edge + stripe, 0.0, 1.0));
		vec3 pole_rgb = grade > 3.5 ? vec3(0.12, 0.06, 0.05) : vec3(0.23, 0.17, 0.10);
		c = vec4(mix(pole_rgb, flag_rgb, cloth), max(pole, cloth));
		if (grade > 2.5) {
			float finial = step(abs(UV.x - 0.42) * 2.4 + abs(UV.y - 0.055), 0.05);
			c = mix(c, vec4(gold * 1.08, 1.0), finial);
		}
		if (grade > 3.5) {
			float tail = 0.0;
			for (int k = 0; k < 2; k++) {
				float x0 = 0.56 + 0.16 * float(k);
				float b0 = 0.48 - (x0 - 0.44) * 0.09;
				float ty = UV.y - b0;
				float tx = x0 + sin(flag_phase * 1.3 - ty * 18.0 + float(k)) * 0.03 * ty * 6.0;
				tail = max(tail, step(0.0, ty) * step(ty, 0.17 + 0.04 * float(k)) * (1.0 - smoothstep(0.012, 0.022, abs(UV.x - tx))));
			}
			c = mix(c, vec4(gold, 1.0), tail * (1.0 - cloth));
		}
	} else if (hero > 0.5 && shade <= 0.01) {
		// 11/24 신화 장수 인형 —— 위에서 받는 금빛 테두리 · 먹 외곽선 · 바깥에 진영색 기운 (아군 청 · 적군 적, 숨 쉬듯)
		vec3 side_c = enemy > 0.5 ? HERO_ENEMY : HERO_ALLY;
		vec3 rim = grade < 4.5 ? RIM_SILVER : RIM_GOLD;
		float a_up = sprite_grad(UV - dv * 1.1, du, dv).a;
		c.rgb = mix(c.rgb, rim * 1.1, clamp(c.a * (1.0 - a_up) * 0.55, 0.0, 1.0));
		float a_near = sprite_grad(UV, du * 2.5, dv * 2.5).a;
		float ink = (1.0 - c.a) * smoothstep(0.04, 0.32, a_near) * 0.85;
		float a_blur = sprite_grad(UV, du * 6.0, dv * 6.0).a;
		float halo = (1.0 - c.a) * smoothstep(0.02, 0.4, a_blur);
		halo *= smoothstep(0.0, 0.06, cell_uv.x) * (1.0 - smoothstep(0.94, 1.0, cell_uv.x)) * smoothstep(0.0, 0.06, cell_uv.y);
		float pulse = 0.85 + 0.15 * sin(TIME * 3.0 + flag_phase * 0.15);
		c = over(c, over(vec4(OUTLINE, ink), vec4(mix(rim, side_c, 0.35), halo * 0.82 * pulse)));
	} else if (grade > 1.5 && shade <= 0.01) {
		// 11/24 정예 이상 —— 모래빛 바닥에서 또렷하게: 진한 옷 빛 · 먹 외곽선 · 위에서 받는 가는 테두리 빛 (정예 은 · 근위부터 금)
		// 근위부터 외곽선 밖에 등급색 기운 (초월 하늘 · 불멸 주황 · 신화 금). 탭은 정예 3 · 근위 이상 4 번 (미분은 갈래 밖에서 잰 것)
		float k = grade < 2.5 ? 0.25 : (grade < 3.5 ? 0.55 : (grade < 4.5 ? 0.8 : 1.0));
		if (myth < 0.5) {
			// 옷 빛을 진하게 · 진영색 쪽으로 · 가운데 톤을 눌러 옻칠한 듯 묵직하게 (바랜 잡병과 반대)
			float l1 = dot(c.rgb, vec3(0.3, 0.59, 0.11));
			c.rgb = clamp(mix(vec3(l1), c.rgb, 1.15 + 0.2 * k), 0.0, 1.0);
			if (action_army > 0.5) {
				vec3 fac = action_army > 1.5 ? vec3(0.95, 0.3, 0.2) : vec3(0.32, 0.52, 1.0);
				c.rgb = mix(c.rgb, clamp(l1 * fac * 1.55, 0.0, 1.0), 0.12 + 0.18 * k);
			}
			c.rgb = pow(c.rgb, vec3(1.0 + 0.3 * k));
			// 위에서 받는 가는 테두리 빛 (화면 1px 위가 비면 가장자리)
			float a_up = sprite_grad(UV - dv * 1.1, du, dv).a;
			float rim = c.a * (1.0 - a_up);
			c.rgb = mix(c.rgb, (grade < 2.5 ? RIM_SILVER : RIM_GOLD) * 1.1, clamp(rim * (0.3 + 0.35 * k), 0.0, 1.0));
		}
		// 먹 외곽선 —— 미분을 2.5 배로 넘긴 흐린 알파(1~2px 부푼 실루엣)
		float a_near = sprite_grad(UV, du * 2.5, dv * 2.5).a;
		float ink = (1.0 - c.a) * smoothstep(0.04, 0.32, a_near) * (0.45 + 0.35 * k);
		vec4 under = vec4(OUTLINE, ink);
		if (grade > 2.5) {
			// 근위 · 철위 · 신병 —— 둘레 기운 (밉맵 흐림 한 번: 미분 6 배 = 2.6 단계 흐린 알파)
			float a_blur = sprite_grad(UV, du * 6.0, dv * 6.0).a;
			float halo = (1.0 - c.a) * smoothstep(0.02, 0.4, a_blur);
			halo *= smoothstep(0.0, 0.1, cell_uv.x) * (1.0 - smoothstep(0.9, 1.0, cell_uv.x)) * smoothstep(0.0, 0.08, cell_uv.y);
			vec3 glow = grade > 4.5 ? vec3(1.0, 0.9, 0.5) : (grade > 3.5 ? vec3(1.0, 0.52, 0.12) : vec3(0.3, 0.8, 1.0));
			float pulse = 0.8 + 0.2 * sin(TIME * 3.2 + flag_phase * 0.15);
			under = over(under, vec4(glow, halo * (grade > 4.5 ? 0.45 : (grade > 3.5 ? 0.55 : 0.4)) * pulse));
		}
		c = over(c, under);
	} else if (grade < 0.5) {
		// 11/24 잡병 (희귀 아래) —— 옷 빛을 조금 바래게
		float l0 = dot(c.rgb, vec3(0.3, 0.59, 0.11));
		c.rgb = mix(c.rgb, vec3(l0) * vec3(1.03, 0.98, 0.9), 0.4) * 0.95;
	}
	if (shade > 0.01) {
		// 그늘 속 —— 두 탭 더 섞어 살짝 흐릿하게 (그늘 부대만), 빛을 빼고 푸른 그림자 빛으로 어둡게
		vec2 o = vec2(0.007, 0.009) * shade;      // 아틀라스 칸(0.25)의 3% 남짓 = 인형 키의 1~2px
		if (standard < 0.5) {
			c = mix(c, (sprite_grad(UV + o, du, dv) + sprite_grad(UV - o, du, dv) + c) / 3.0, shade);
		}
		c *= tint;
		float l = dot(c.rgb, vec3(0.3, 0.59, 0.11));
		c.rgb = mix(c.rgb, vec3(l) * vec3(0.62, 0.72, 0.70), shade * 0.65) * (1.0 - 0.3 * shade);
		COLOR = c;
	} else {
		COLOR = c * tint;
		if (shade < -0.01) {      // 숲에서 막 나온 부대 —— 짧게 밝게 번쩍 (등장)
			COLOR.rgb = mix(COLOR.rgb, vec3(1.0, 0.94, 0.78), -shade * 0.55);
		}
	}
}
