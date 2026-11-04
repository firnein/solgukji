// GPU 병사 (11/3 사용자: 병사 3~5배) —— 살아 있는 병사의 자리 · 걸음 · 공격 · 무기를 정점 셰이더에서 계산한다.
// CPU 는 부대마다 값 몇 개(squad_tex 한 줄)만 넘긴다. 병사마다 GDScript 로 위치를 계산 · 버퍼에 쓰던 것(병사 수에 비례)이 없어진다.
// 쓰러지는 병사 · 장수는 예전처럼 CPU 가 그린다 (soldier.gdshader).
//
// INSTANCE_CUSTOM: r = 부대 줄 번호, g = 대열 자리(slot), b = 씨앗(0~1), a = 옷 밝기(0~1). 인스턴스 변환은 항등.
// squad_tex (RGBAF, 가로 6 · 세로 부대 수) —— Squad · War3D._gpu_sync 와 같은 순서:
//   0: pos.x, pos.y (전장 px), fwd.x, fwd.y
//   1: cols, sp, 살아 있는 수, 앞줄 오프셋((줄수-1)·sp·0.5)
//   2: 걸음 누적, 움직임(0/1), 맞닿음(0/1), 사라짐(fade)
//   3: 떠밀기(+ 뒤로 · − 앞으로, px), 움찔(hurt), 표식(1 파갑 · 2 집중), 무기 겨눔(0/1)
//   4: 파갑 번쩍(0~1), 패주 시간(초, 0 이면 아님), 몸집 배율, 기병(0/1)
//   5: 흐트러짐(loose), 진영(0 아군 · 1 적), 시계(초), 대열 깊이(px)
//   6: 늦게 따라오는 위치 x, y · 방향 x, y (병사마다 섞는다 —— 대열이 휘고 늘어진다)
//   7: 대열 압축 앞뒤, 좌우 (War3D._squeeze —— 옆 부대와 겹치지 않게), 병종 색상 돌림(라디안), 움직임 섞기(0~1, Squad.move_s)
// INSTANCE_CUSTOM (11/3 개정): r = 부대 줄, g = 자리 (음수 숨김 · 자리 + (전 자리+1)×1024), b = 씨앗, a = 자리 옮기기 시작 시각
shader_type spatial;
render_mode cull_disabled;

uniform sampler2D squad_tex : filter_nearest;
uniform sampler2D height_tex : filter_linear, repeat_disable;
uniform float h_half = 30.0;        // 높이 격자 반폭 (월드 m)
uniform float h_size = 60.0;
uniform vec3 team_a : source_color = vec3(0.25, 0.5, 0.82);
uniform vec3 team_b : source_color = vec3(0.78, 0.27, 0.23);
uniform float team_glow = 0.05;
// 무기 판 —— is_weapon 이면 손에 쥔 무기 (몸과 같은 자리 · 같은 팔 각)
uniform bool is_weapon = false;
uniform int weapon_kind = 0;        // 0 창 · 1 칼 · 2 기병창
uniform vec3 hand = vec3(0.16, 0.74, 0.24);
uniform vec2 pivot = vec2(0.0, 1.0);
// VAT 모드 (11/4 저녁 —— Quaternius 말 등 구운 모델): 팔다리 부위 회전 대신 프레임마다 정점 위치 · 법선을 텍스처에서 읽는다
// (tests/bake_vat.gd —— 가로 정점 번호, 세로 프레임). 동작 [시작 줄, 프레임 수]
uniform bool use_vat = false;
uniform sampler2D vat_pos : filter_nearest, repeat_disable;
uniform sampler2D vat_nrm : filter_nearest, repeat_disable;
uniform vec2 clip_idle = vec2(0.0, 6.0);
uniform vec2 clip_walk = vec2(6.0, 8.0);
uniform vec2 clip_attack = vec2(14.0, 6.0);
uniform vec2 clip_hit = vec2(20.0, 4.0);
uniform vec2 clip_death = vec2(24.0, 6.0);
uniform vec2 clip_cheer = vec2(30.0, 6.0);

const float S = 0.1;
const float ATTACK_TIME = 0.35;
const float ATK_LEN = 0.6;          // 공격 한 번 (힘 모으기 → 내지르기 → 돌아오기)

varying vec4 v_custom;     // r 진영, g 0, b 번쩍(음수 = 갑옷 깨짐), a 옷 밝기

vec4 sq(float row, int col) {
	return texelFetch(squad_tex, ivec2(col, int(row)), 0);
}

float hash(float n) { return fract(sin(n * 91.3458) * 47453.5453); }

vec2 rot(vec2 v, float a) {
	float c = cos(a);
	float s = sin(a);
	return vec2(c * v.x - s * v.y, s * v.x + c * v.y);
}

void vertex() {
	vec4 ic = INSTANCE_CUSTOM;
	float row = ic.r;
	float seed = ic.b;
	vec4 t0 = sq(row, 0);
	vec4 t1 = sq(row, 1);
	vec4 t2 = sq(row, 2);
	vec4 t3 = sq(row, 3);
	vec4 t4 = sq(row, 4);
	vec4 t5 = sq(row, 5);
	vec4 t6 = sq(row, 6);
	vec2 squeeze = sq(row, 7).xy;        // 대열 압축 (앞뒤, 좌우) —— 옆 부대와 겹치지 않게
	float clock = t5.z;
	// 자리 —— 음수면 쓰러졌다(숨김). 아니면 지금 자리 + (전 자리 + 1) × 1024, 걸어 나오는 중이면 두 자리 사이를 잇는다
	float g = ic.g;
	bool hide = g < 0.0 || t1.z <= 0.0 || seed > t2.w;      // 패주로 사라질 때는 씨앗 순으로 하나씩
	g = max(g, 0.0);
	float old1 = floor(g / 1024.0);
	float slot = g - old1 * 1024.0;
	float move_k = old1 > 0.0 ? smoothstep(0.0, 1.0, clamp((clock - ic.a) / 0.8, 0.0, 1.0)) : 1.0;
	float slot0 = old1 > 0.0 ? old1 - 1.0 : slot;
	float cols = max(t1.x, 1.0);
	float sp = t1.y;
	float rk = floor(slot / cols);
	float rk0 = floor(slot0 / cols);
	float half_c = (cols - 1.0) * 0.5;
	float rows = max(1.0, t5.w / max(sp, 0.01));
	// 병사마다 반응이 다르다 —— 뒷줄 · 가장자리일수록 늦게 따라온다 (돌 때 대열이 휘고, 움직이면 늘어지고, 멈추면 모인다)
	float edge = abs(slot - rk * cols - half_c) / max(half_c, 1.0);
	float lag = clamp(1.0 - (rk / rows) * 0.35 - edge * 0.12 - hash(seed * 12.7) * 0.15, 0.45, 1.0);      // 11/4 뒷줄이 덜 처지게 (대열이 길게 늘어졌다)
	vec2 pos = mix(t6.xy, t0.xy, lag);
	vec2 fwd = normalize(mix(t6.zw, t0.zw, lag) + vec2(1e-5, 0.0));
	vec2 rgt = vec2(-fwd.y, fwd.x);
	vec2 front = pos + fwd * t1.w * squeeze.x;
	// 대열 자리 —— 줄이 곧지 않게 물결치고(낮은 주파수), 자리마다 크게 어긋난다
	vec2 jit = rot(vec2(1.0, 0.0), hash(seed * 7.1) * 6.2831) * hash(seed * 3.3) * sp * 0.75 * min(squeeze.x, squeeze.y);
	float c = slot - rk * cols;
	float c0 = slot0 - rk0 * cols;
	vec2 l1 = vec2(-(rk * sp * 0.92), (c - half_c + mod(rk, 2.0) * 0.5) * sp);
	vec2 l0 = vec2(-(rk0 * sp * 0.92), (c0 - half_c + mod(rk0, 2.0) * 0.5) * sp);
	vec2 lc = mix(l0, l1, move_k) * squeeze;
	lc.x += sin(lc.y * 0.09 + row * 1.7 + clock * 0.35) * sp * 0.9;       // 줄이 물결친다
	lc.y += sin(lc.x * 0.11 + row * 2.3) * sp * 0.5;
	vec2 p = front + fwd * lc.x + rgt * lc.y + jit;
	bool contact = t2.z > 0.5;
	bool fighting = contact && rk < 2.0;
	bool pressing = contact && !fighting;
	float loose = t5.x;
	bool moving0 = t2.y > 0.5;
	// 군중 —— 늘 조금씩 움직인다. 걸을 때는 앞뒤로 처지고, 싸울 때는 크게 흔들린다
	float wt = clock * (fighting ? 1.3 : 0.5) + seed * 40.0;
	float wamp = (fighting ? 1.1 + 1.4 * loose : (moving0 ? 0.6 : 0.5)) * mix(0.5, 1.0, min(squeeze.x, squeeze.y));      // 11/4 저녁 북적임: 더 크게 움직인다
	vec2 wander = vec2(sin(wt * 1.7 + seed * 13.0) + 0.5 * sin(wt * 0.6 + seed * 3.0), cos(wt * 1.3 + seed * 29.0)) * sp * wamp;
	p += wander;
	if (moving0) p -= fwd * hash(seed * 15.3) * sp * 1.6 * (0.4 + rk / rows);      // 걸음이 느린 병사는 처진다
	if (contact && rk < 3.0) p += fwd * sp * (1.0 - rk * 0.3) * (0.4 + loose * 1.2) * (0.6 + 0.8 * hash(seed * 21.1));  // 앞줄이 불룩하게 밀고 들어간다
	// 11/4 저녁 북적임 —— 앞 세 줄의 4할은 대열을 벗어나 전선에서 뒤엉켜 싸운다 (제자리를 느리게 돌며 적 쪽으로 더 깊이)
	float brawl = hash(seed * 23.9);
	if (contact && rk < 3.0 && brawl < 0.4) {
		float ba = brawl * 15.7 + clock * (0.5 + brawl) * (hash(seed * 27.1) - 0.5);
		p += rot(vec2(1.0, 0.0), ba) * sp * (1.0 + 2.0 * hash(seed * 29.3)) + fwd * sp * (0.8 + 1.4 * hash(seed * 31.7));
	}
	// 공격 (11/3 사용자: 물리 유닛이 어색하다) —— 앞 세 줄이 제 박자로: 뒤로 젖혀 힘을 모았다가(windup) 몸을 던져 내지르고(strike) 천천히 돌아온다
	bool fighting3 = contact && rk < 3.0;
	float period = (0.9 + hash(seed * 5.7) * 1.0) * (1.0 + rk * 0.35);
	float uu = mod(clock + seed * 17.0, period) / ATK_LEN;
	float wu = 0.0;      // 힘 모으기 0~1
	float sk = 0.0;      // 내지르기 0~1
	if (fighting3 && uu < 1.0) {
		wu = smoothstep(0.0, 0.42, uu) * (1.0 - smoothstep(0.42, 0.52, uu));
		sk = smoothstep(0.42, 0.56, uu) * (1.0 - smoothstep(0.68, 1.0, uu));
	}
	float atk = sk;
	if (fighting3) p += fwd * (sp * 0.5 * (1.0 - rk * 0.3) - 2.0 * wu + 7.0 * sk);
	if (pressing && !fighting3) p += fwd * sp * min(rk - 2.0, 3.0) * 0.6 * loose;          // 뒷줄이 빈자리로 밀고 든다
	// 떠밀기 —— 앞 세 줄 (지는 쪽 +, 이기는 쪽 −)
	if (rk <= 2.0) p -= fwd * t3.x * (1.0 - rk * 0.28) * (0.75 + 0.5 * hash(seed * 2.9));
	// 피격 —— 맞는 동안 앞 두 줄에서 몇 명씩 번갈아: 뒤로 젖혀지며 한 발 물러나고 팔이 흔들린다
	float hslot = floor(clock * 3.0 + hash(seed * 4.1) * 7.0);
	float hit_ph = fract(clock * 3.0 + hash(seed * 4.1) * 7.0);
	float hurt = step(0.5, t3.y) * step(rk, 1.5) * step(0.78, hash(seed * 4.1 + hslot)) * pow(1.0 - hit_ph, 2.0);
	p -= fwd * 5.0 * hurt;
	p += rgt * (hash(seed * 4.7 + hslot) - 0.5) * 4.0 * hurt;
	// 패주 —— 흩어지며 달아난다
	float flee = t4.y;
	vec2 look = rot(fwd, sin(clock * 0.7 + seed * 50.0) * (fighting ? 0.45 : 0.22) + (hash(seed * 31.0) - 0.5) * 0.35);
	if (flee > 0.0) {
		p += rot(vec2(1.0, 0.0), hash(seed * 9.7) * 6.2831) * flee * 18.0;
	}
	// 걸음
	bool moving = moving0 || flee > 0.0 || move_k < 1.0;
	float walk = (t2.x + (move_k < 1.0 ? clock * 6.0 : 0.0)) * (0.8 + 0.4 * hash(seed * 6.1)) + seed * 6.2831;
	float mv = moving ? 1.0 : 0.0;
	float ph = walk * 0.9;
	float cav = t4.w;
	vec3 wp = vec3(p.x * S, 0.0, p.y * S);
	vec2 huv = (wp.xz + h_half) / h_size;
	wp.y = texture(height_tex, huv).r + abs(sin(ph)) * (cav > 0.5 ? 0.16 : 0.08) * mv + 0.07 * sk;
	float size = t4.z * (0.92 + 0.16 * hash(seed * 8.3));

	// 팔다리 흔들기 (soldier.gdshader 와 같은 부위 규칙). 무기는 팔(4) 과 같이 돈다
	vec3 v = VERTEX;
	vec3 nrm = NORMAL;
	if (use_vat && !is_weapon) {
		// 구운 동작: 앞줄 싸움은 공격(서 있기와 섞어 들어가고 나온다) · 움직이면 달리기(걸음 박자) · 아니면 서 있기
		// 11/4 저녁 사용자 "번쩍번쩍": 맞을 때마다 맞기 동작으로 뚝 바뀌고 공격이 뚝 끊겨 수백 명이 깜빡였다 —— 맞기 동작은 안 쓰고(몸 젖힘만), 공격은 섞는다
		int id = VERTEX_ID;
		// 서 있기 (바탕)
		float fi = fract(clock * 0.3 + seed * 3.0) * clip_idle.y;
		float i0 = floor(fi);
		float i1 = mod(i0 + 1.0, clip_idle.y);
		v = mix(texelFetch(vat_pos, ivec2(id, int(clip_idle.x + i0)), 0).xyz, texelFetch(vat_pos, ivec2(id, int(clip_idle.x + i1)), 0).xyz, fi - i0);
		nrm = mix(texelFetch(vat_nrm, ivec2(id, int(clip_idle.x + i0)), 0).xyz, texelFetch(vat_nrm, ivec2(id, int(clip_idle.x + i1)), 0).xyz, fi - i0);
		// 공격 (앞줄, 들어가고 나올 때 섞는다)
		if (fighting3 && uu < 1.0) {
			float fa = uu * (clip_attack.y - 1.0);
			float a0 = floor(fa);
			float a1 = min(a0 + 1.0, clip_attack.y - 1.0);
			float wa = smoothstep(0.0, 0.15, uu) * (1.0 - smoothstep(0.82, 1.0, uu));
			v = mix(v, mix(texelFetch(vat_pos, ivec2(id, int(clip_attack.x + a0)), 0).xyz, texelFetch(vat_pos, ivec2(id, int(clip_attack.x + a1)), 0).xyz, fa - a0), wa);
			nrm = mix(nrm, mix(texelFetch(vat_nrm, ivec2(id, int(clip_attack.x + a0)), 0).xyz, texelFetch(vat_nrm, ivec2(id, int(clip_attack.x + a1)), 0).xyz, fa - a0), wa);
		}
		// 걷기 · 달리기 —— 부대의 움직임 값(0~1, 부드럽게 변한다)만큼 섞는다. 멈추고 서는 순간 자세가 뚝 바뀌지 않게
		float mv_s = max(sq(row, 7).w, flee > 0.0 ? 1.0 : 0.0);
		if (mv_s > 0.001) {
			float fw2 = fract(ph / 6.2831) * clip_walk.y;
			float w0 = floor(fw2);
			float w1 = mod(w0 + 1.0, clip_walk.y);
			v = mix(v, mix(texelFetch(vat_pos, ivec2(id, int(clip_walk.x + w0)), 0).xyz, texelFetch(vat_pos, ivec2(id, int(clip_walk.x + w1)), 0).xyz, fw2 - w0), mv_s);
			nrm = mix(nrm, mix(texelFetch(vat_nrm, ivec2(id, int(clip_walk.x + w0)), 0).xyz, texelFetch(vat_nrm, ivec2(id, int(clip_walk.x + w1)), 0).xyz, fw2 - w0), mv_s);
		}
		nrm = normalize(nrm);
	} else {
	// 팔 —— 힘 모을 때 뒤로, 내지를 때 크게 앞으로, 맞으면 휘청
	float arm = -1.0 * wu + 1.7 * sk - 0.8 * hurt;
	bool ready = fighting3 || (t3.w > 0.5 && rk < 3.0);
	if (is_weapon) {
		float wang = 0.0;
		vec2 hd = rot(hand.xy - pivot, arm);
		vec3 h3 = vec3(pivot + hd, hand.z);
		if (weapon_kind == 1) {
			// 칼 —— 머리 위로 치켜들었다가 내려벤다
			wang = (ready ? -1.9 : -0.55) - 0.8 * wu + 1.7 * sk;
		} else {
			// 창 · 기병창 —— 겨눈 채 뒤로 당겼다가 쭉 찌른다
			wang = ready ? (weapon_kind == 0 ? -1.38 : -1.45) : (weapon_kind == 0 ? -0.1 : -0.22);
			h3.x += -0.25 * wu + 0.75 * sk;
		}
		float a = wang + arm * 0.5;
		v.xy = rot(v.xy, a);
		nrm.xy = rot(nrm.xy, a);
		v += h3;
	} else {
		float part = floor(UV.x + 0.5);
		if (part > 0.5) {
			float idle = sin(TIME * 1.7 + seed * 40.0) * 0.06;
			float sw = sin(ph);
			float a = 0.0;
			if (part < 1.5) a = sw * 0.6 * mv + 0.35 * sk;            // 내지를 때 앞발을 내딛는다
			else if (part < 2.5) a = -sw * 0.6 * mv - 0.25 * sk;
			else if (part < 3.5) a = -sw * 0.4 * mv + idle + 0.5 * wu - 0.4 * sk + 0.9 * hurt;   // 다른 팔은 반대로
			else if (part < 4.5) a = arm + idle * 0.5;
			else if (part < 5.5) a = sw * 0.75 * mv;
			else if (part < 6.5) a = -sw * 0.75 * mv;
			else a = sw * 0.4 * mv - idle;
			vec2 d = v.xy - UV2;
			v.xy = UV2 + rot(d, a);
			nrm.xy = rot(nrm.xy, a);
		}
	}
	}
	// 몸 전체 —— 내지를 때 앞으로 숙이고, 힘 모을 때 젖히고, 맞으면 뒤로 꺾인다 (무기도 같이). 기병은 작게
	float tilt = (0.12 * wu - 0.34 * sk + 0.55 * hurt) * (cav > 0.5 ? 0.35 : 1.0);
	v.xy = rot(v.xy, tilt);
	nrm.xy = rot(nrm.xy, tilt);
	// 몸 방향(yaw) · 크기 · 자리 —— 모델 앞은 +X (CPU 의 Basis(UP, -yaw) 와 같다)
	v *= size;
	vec3 o = vec3(look.x * v.x - look.y * v.z, v.y, look.y * v.x + look.x * v.z);
	vec3 on = vec3(look.x * nrm.x - look.y * nrm.z, nrm.y, look.y * nrm.x + look.x * nrm.z);
	VERTEX = hide ? vec3(0.0, -500.0, 0.0) : o + wp;
	NORMAL = on;
	// 번쩍 —— 맞으면 흰빛, 파갑이 터진 순간 · 집중(주인공 부대)도 밝게, 파갑 상태는 음수(녹슨 갑옷)
	float flash = hurt * (use_vat ? 0.12 : 0.35);      // 11/4 저녁: 구운 병사는 몸이 커서 하얀 번쩍임이 눈에 띄었다
	float flags = t3.z;
	float bflash = t4.x;
	if (bflash > 0.0) flash = max(flash, 0.18 * bflash);
	else if (mod(flags, 4.0) >= 2.0) flash = max(flash, 0.28 + 0.12 * sin(TIME * 14.0));
	else if (mod(flags, 2.0) >= 1.0 && flash <= 0.0) flash = -0.7;
	v_custom = vec4(t5.y, sq(row, 7).z, flash, hash(seed * 11.0));
}

// 색상 돌리기 (YIQ) —— 11/4 병종마다 진영색을 조금 다르게 (적이 다 같은 붉은색이라 부대가 구분되지 않았다)
vec3 hue_rot(vec3 c, float a) {
	vec3 yiq = vec3(dot(c, vec3(0.299, 0.587, 0.114)), dot(c, vec3(0.596, -0.274, -0.322)), dot(c, vec3(0.211, -0.523, 0.312)));
	float ca = cos(a);
	float sa = sin(a);
	yiq.yz = vec2(ca * yiq.y - sa * yiq.z, sa * yiq.y + ca * yiq.z);
	return clamp(vec3(yiq.x + 0.956 * yiq.y + 0.621 * yiq.z, yiq.x - 0.272 * yiq.y - 0.647 * yiq.z, yiq.x - 1.106 * yiq.y + 1.703 * yiq.z), 0.0, 1.0);
}

void fragment() {
	vec3 team = hue_rot(mix(team_a, team_b, v_custom.r), v_custom.g);
	vec3 vc = pow(COLOR.rgb, vec3(2.2));
	vec3 base = mix(vc, vc * team, COLOR.a);
	base *= mix(1.0, 0.82 + 0.36 * v_custom.a, COLOR.a);
	float brk = clamp(-v_custom.b, 0.0, 1.0);
	float fl = max(v_custom.b, 0.0);
	if (brk > 0.0) {
		vec3 rust = vec3(0.30, 0.13, 0.06) * (0.7 + 0.6 * vc.r);
		float crack = step(0.82, fract(sin(dot(floor(UV * 9.0 + v_custom.a * 13.0), vec2(12.9898, 78.233))) * 43758.5453));
		vec3 broken = mix(rust, vec3(0.05), crack * 0.8);
		base = mix(base, broken, brk * (1.0 - COLOR.a) * 0.85);
		base = mix(base, base * vec3(0.72, 0.62, 0.55), brk * COLOR.a * 0.6);
	}
	base = mix(base, vec3(1.0, 0.92, 0.85), fl);
	ALBEDO = base;
	ROUGHNESS = mix(0.8, mix(0.45, 0.95, brk), step(0.6, vc.b) * (1.0 - COLOR.a));
	EMISSION = team * team_glow * COLOR.a + vec3(1.0, 0.9, 0.8) * fl * 0.6;
	RIM = 0.2;
	RIM_TINT = 0.3;
}
