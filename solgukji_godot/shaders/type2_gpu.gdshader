// 타입2 GPU 병사 (11/6 목표: 휴대폰에서도 품질이 떨어지지 않는 대군) —— 살아 있는 병사의 자리를 정점 셰이더가 계산한다.
// 3D 의 soldier_gpu.gdshader 와 같은 부대 데이터(squad_tex, War3D._gpu_sync)와 같은 대열 식을 2D 지도에 옮겼다.
// CPU 는 부대마다 한 줄만 넘기고, 병사가 쓰러지거나 자리를 옮길 때만 그 인스턴스 값을 고친다 (Type2View.gpu_moved).
// 장수 · 날아가는 병사는 CPU 가 그린다 (Type2View._draw_dots).
// INSTANCE_CUSTOM: r = 부대 줄, g = 자리 (음수 숨김 · 자리 + (전 자리+1)×1024), b = 씨앗, a = 자리 옮기기 시작 시각
//   11/7 쓰러지는 병사도 여기서 (CPU 가 병사마다 그리던 것 —— 병사 만 명이면 쓰러지는 수백 명을 매 프레임 스크립트로 돌렸다):
//   r < 0 이면 쓰러지는 병사 —— r = -(부대 줄 + 1), g = 전장 자리 (x+1500)·3000 + (y+1500) (1px 단위), b = 씨앗, a = 쓰러지는 시각.
//   그 자리에 서 있다가 시각이 되면 넘어지고(0.35초) 뒤로 밀리며(9px) 1.2초 뒤부터 바래 2초에 사라진다 (CPU 가 그리던 것과 같은 식).
// 11/7 흐트러뜨리기 (사용자: 군집 강체 뒤 너무 뭉쳐 보인다) —— 판정 · 부대 자리 · 발자국은 그대로, 보이는 배치만:
//   자리 어긋남을 원반에 고르게(√) · 느린 잡음의 봉우리에서 골짜기로 밀어 틈과 무리를 만든다(clump) · 가장자리 병사가 들쭉날쭉(rag)
//   · 병사마다 옷 밝기 · 서 있을 때 몇은 딴 데를 본다. 걸을 때 · 맞붙어 흐트러질수록(loose) 더 크게
// 11/7 부하 조절 LOD: lod 1 이면 화면에서 병사 간격이 lod_px 보다 좁은(겹쳐 보이는) 부대의 안쪽 병사를 2명당 1명만, 2 면 모든 부대.
//   앞 두 줄 · 맨 뒷줄 · 양 끝 열은 다 그린다 (윤곽 · 전선은 그대로). 계산 · 판정 병사 수는 그대로
shader_type canvas_item;

uniform sampler2D squad_tex : filter_nearest;
uniform sampler2D tag_tex : filter_nearest;      // 11/7 부대 줄 -> 칸 0 (인형 칸 0~1, 병종 크기, 11/12 등급 배율, 장식 단계 0 · 1 · 2) · 칸 1 장식 색 · 칸 2 발광 색
// 11/12 고급 병사 장식 (Type2View._deco_tex) —— 병사 아틀라스와 같은 칸 × 2줄(장식 1 · 2단계). r 금 · g 장식 색 · b 둘레 발광
uniform sampler2D deco_tex : filter_linear;
uniform vec2 center;            // 화면 가운데 전장 자리 (흔들림 포함)
uniform float scl = 1.0;
uniform float tilt = 1.25;
uniform vec2 vsize = vec2(540.0, 800.0);
uniform float spread = 1.35;    // Type2View.T2_SPREAD —— 부대 안 병사 사이를 넓혀 그린다
uniform float fig = 17.0;       // 인형 키 (화면 px)
uniform vec3 team_a : source_color = vec3(0.29, 0.54, 0.91);
uniform vec3 team_b : source_color = vec3(0.93, 0.31, 0.24);
uniform float scatter = 1.0;    // 흐트러짐 세기 (0 이면 흐트러뜨리기 전 배치 —— Type2View.scatter)
uniform float lod = 0.0;        // 0 다 그림 · 1 겹친 부대만 안쪽 2명당 1명 · 2 모든 부대
uniform float lod_px = 4.0;     // 화면 병사 간격이 이보다 좁으면 '겹친 부대'
// 11/9 병사 표시 예산 —— 전투 전체에서 그리는 병사 수 상한(휴대폰 5천 · PC 9천)을 넘으면 모든 부대에서 같은 비율(keep)만 그린다 (씨앗 순 —— 쓰러지는 병사도 같은 기준).
//   줄인 만큼 남은 병사 인형을 키우고(grow, 최대 1.35배) 진영색을 짙게(dark 0~1) 해 대군이 엷어 보이지 않게 한다. 판정 · 병력 · 엔진 위치는 그대로
uniform float keep = 1.0;
uniform float grow = 1.0;
uniform float dark = 0.0;

varying vec4 tint;
varying float atlas_x;
varying float deco;
varying vec3 acc_c;
varying vec3 glow_c;

vec4 sq(float row, int col) {
	return texelFetch(squad_tex, ivec2(col, int(row)), 0);
}

float hash(float n) { return fract(sin(n * 91.3458) * 47453.5453); }
float hash2(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }

// 값 잡음 (0~1, 부드럽게) —— 대열 안 뭉침 · 틈 무늬
float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash2(i), hash2(i + vec2(1.0, 0.0)), u.x), mix(hash2(i + vec2(0.0, 1.0)), hash2(i + vec2(1.0, 1.0)), u.x), u.y);
}

vec2 rot(vec2 v, float a) {
	float c = cos(a);
	float s = sin(a);
	return vec2(c * v.x - s * v.y, s * v.x + c * v.y);
}

void vertex() {
	vec4 ic = INSTANCE_CUSTOM;
	float row = ic.r;
	bool dying = row < -0.5;
	if (dying) row = -row - 1.0;
	float seed = ic.b;
	vec4 t0 = sq(row, 0);
	vec4 t1 = sq(row, 1);
	vec4 t2 = sq(row, 2);
	vec4 t3 = sq(row, 3);
	vec4 t4 = sq(row, 4);
	vec4 t5 = sq(row, 5);
	float clock = t5.z;
	float camp = t5.y;
	float flip = camp > 0.5 ? -1.0 : 1.0;
	vec2 sp2;
	float h;
	float rotz = 0.0;        // 인형 기울기 (쓰러짐 · 내지르기)
	float alpha = 1.0;
	float shade = 1.0;
	bool hide = t1.z <= 0.0;
	if (dying) {
		// 쓰러지는 병사 —— 죽은 자리에 고정, 시각이 되면 넘어진다. 부대가 사라졌으면(gone, 9.w) 같이 사라진다
		float u = clock - ic.a;
		hide = sq(row, 9).w > 0.5 || u > 2.0 || seed > keep;
		float xi = floor(ic.g / 3000.0);
		vec2 p = vec2(xi - 1500.0, ic.g - xi * 3000.0 - 1500.0);
		vec2 fwd0 = normalize(t0.zw + vec2(1e-5, 0.0));
		float uu = clamp(u / 0.3, 0.0, 1.0);
		p -= fwd0 * 9.0 * (1.0 - pow(1.0 - uu, 2.5));      // 맞아 쓰러지며 뒤로 밀린다 (ease 0.4)
		p = t0.xy + (p - t0.xy) * spread;
		vec2 d = p - center;
		sp2 = vsize * 0.5 + vec2(d.y, -d.x * tilt) * scl;
		float dep = 0.82 + 0.18 * clamp(sp2.y / max(vsize.y, 1.0), 0.0, 1.0);
		h = fig * grow * t4.z * (0.92 + 0.16 * hash(seed * 8.3)) * dep * max(texelFetch(tag_tex, ivec2(0, int(row)), 0).g, 0.5) * max(texelFetch(tag_tex, ivec2(0, int(row)), 0).b, 1.0);
		float fall = hash(seed * 11.9) < 0.5 ? 1.0 : -1.0;
		rotz = fall * clamp(u / 0.35, 0.0, 1.0) * 3.14159 * 0.5 * (u > 0.0 ? 1.0 : 0.0);
		shade = u > 0.0 ? 0.55 : 1.0;
		alpha = clamp(1.0 - (u - 1.2) / 0.8, 0.0, 1.0);
	} else {
		vec4 t6 = sq(row, 6);
		vec2 squeeze = sq(row, 7).xy;
		float g = ic.g;
		hide = hide || g < 0.0 || seed > t2.w || seed > keep;
		g = max(g, 0.0);
		float old1 = floor(g / 1024.0);
		float slot = g - old1 * 1024.0;
		float move_k = old1 > 0.0 ? smoothstep(0.0, 1.0, clamp((clock - ic.a) / 0.8, 0.0, 1.0)) : 1.0;
		float slot0 = old1 > 0.0 ? old1 - 1.0 : slot;
		float cols = max(t1.x, 1.0);
		float sp = t1.y;
		float spr = sq(row, 9).z;      // 11/7 강체: 줄 간격 (가로 간격과 따로, 발자국 깊이를 채운다)
		if (spr <= 0.0) spr = sp;
		float rk = floor(slot / cols);
		float rk0 = floor(slot0 / cols);
		float half_c = (cols - 1.0) * 0.5;
		float rows = max(1.0, t5.w / max(spr, 0.01));
		float c = slot - rk * cols;
		float c0 = slot0 - rk0 * cols;
		// 부하 조절 LOD —— 겹쳐 보이는 부대는 안쪽 병사를 2명당 1명만. 고르는 병사는 씨앗으로 정한다
		// (자리 번호로 고르면 앞줄이 비어 뒷사람이 한 칸씩 걸어 나올 때마다 보이는 병사가 바뀌어 깜빡였다)
		if (lod >= 1.5 || (lod >= 0.5 && sp * scl < lod_px)) {
			bool inner = rk >= 2.0 && rk < rows - 1.5 && c >= 1.0 && c <= cols - 2.0;
			if (inner && hash(seed * 71.3) < 0.5) hide = true;
		}
		float edge = abs(c - half_c) / max(half_c, 1.0);
		float lag = clamp(1.0 - (rk / rows) * 0.12 - edge * 0.05 - hash(seed * 12.7) * 0.06, 0.8, 1.0);      // 11/7 강체: 뒷줄 지연을 작게 —— 대열이 발자국 밖으로 늘어지지 않는다
		vec2 pos = mix(t6.xy, t0.xy, lag);
		vec2 fwd = normalize(mix(t6.zw, t0.zw, lag) + vec2(1e-5, 0.0));
		vec2 rgt = vec2(-fwd.y, fwd.x);
		vec2 front = pos + fwd * t1.w * squeeze.x;
		// 자리 어긋남 —— 원반에 고르게 (√: 예전엔 가운데로 몰렸다), 흐트러뜨리면 조금 더 멀리
		vec2 jit = rot(vec2(1.0, 0.0), hash(seed * 7.1) * 6.2831) * sqrt(hash(seed * 3.3)) * sp * (0.75 + 0.2 * scatter) * min(squeeze.x, squeeze.y);
		vec2 l1 = vec2(-((rk + 0.5) * spr), (c - half_c + mod(rk, 2.0) * 0.5) * sp);
		vec2 l0 = vec2(-((rk0 + 0.5) * spr), (c0 - half_c + mod(rk0, 2.0) * 0.5) * sp);
		vec2 lc = mix(l0, l1, move_k) * squeeze;
		lc.x += sin(lc.y * 0.09 + row * 1.7 + clock * 0.35) * sp * 0.9;
		lc.y += sin(lc.x * 0.11 + row * 2.3) * sp * 0.5;
		bool contact = t2.z > 0.5;
		bool moving0 = t2.y > 0.5;
		float loose = t5.x;
		// 뭉침과 틈 —— 느린 잡음(부대마다 다른 무늬)의 봉우리에서 골짜기로 병사를 민다: 봉우리 자리는 비어 땅이 보이고 골짜기에 무리가 진다.
		// 걸을 때 · 맞붙어 흐트러질수록(loose) 더 크게. 잡음은 대열 자리(lc)로 재므로 자리를 옮기는 병사는 부드럽게 따라간다
		vec2 nq = lc / (sp * 6.0) + vec2(row * 3.1, row * 7.7);
		float n0 = vnoise(nq);
		vec2 grad = vec2(vnoise(nq + vec2(0.3, 0.0)) - n0, vnoise(nq + vec2(0.0, 0.3)) - n0) / 0.3;
		vec2 clump = -grad * sp * 2.0 * scatter * (moving0 ? 1.2 : 1.0) * (1.0 + 0.6 * loose);
		// 발자국 밖으로는 조금만 (옆 부대와 겹쳐 보이지 않게) —— 가장자리는 아래 rag 가 들쭉날쭉하게 한다
		vec2 q0 = lc + clump;
		float hwf = (half_c + 0.75) * sp;
		q0 = clamp(q0, vec2(-t5.w - sp * 0.6, -hwf - sp * 0.6), vec2(sp * 0.6, hwf + sp * 0.6));
		clump = q0 - lc;
		// 가장자리 —— 양 끝 열 · 맨 뒷줄은 몇 명씩 밖으로 비어져 나오고(맞붙으면 옆으로 더 번진다), 맞붙기 전 앞줄은 몇이 한 발 앞에 선다.
		// 병력이 줄어 맨 뒷줄이 바뀌거나 맞붙기 시작할 때 튀지 않게 부드럽게
		float rkf = mix(rk0, rk, move_k);
		float lastk = smoothstep(rows - 2.0, rows - 1.0, rkf + 0.5);
		float sidek = step(cols - 1.0, c + 0.5) + step(c, 0.5);
		vec2 rag = vec2(-lastk * hash(seed * 43.7) * spr * 1.1, (c < 0.5 ? -1.0 : 1.0) * sidek * hash(seed * 47.3) * sp * (1.1 + 0.8 * loose));
		rag.x += (1.0 - smoothstep(0.0, 1.0, rkf)) * (1.0 - smoothstep(0.0, 0.3, loose)) * step(0.5, hash(seed * 53.9)) * hash(seed * 57.1) * sp * 0.8;
		vec2 p = front + fwd * (lc.x + clump.x + rag.x * scatter) + rgt * (lc.y + clump.y + rag.y * scatter) + jit;
		bool fighting = contact && rk < 2.0;
		float wt = clock * (fighting ? 1.3 : 0.5) + seed * 40.0;
		float wamp = (fighting ? 1.1 + 1.4 * loose : (moving0 ? 0.6 : 0.5)) * mix(0.5, 1.0, min(squeeze.x, squeeze.y));
		p += vec2(sin(wt * 1.7 + seed * 13.0) + 0.5 * sin(wt * 0.6 + seed * 3.0), cos(wt * 1.3 + seed * 29.0)) * sp * wamp;
		if (moving0) p -= fwd * hash(seed * 15.3) * sp * 0.9 * (0.4 + rk / rows);
		if (contact && rk < 3.0) p += fwd * sp * (1.0 - rk * 0.3) * (0.4 + loose * 1.2) * (0.6 + 0.8 * hash(seed * 21.1));
		float brawl = hash(seed * 23.9);
		if (contact && rk < 3.0 && brawl < 0.4) {
			float ba = brawl * 15.7 + clock * (0.5 + brawl) * (hash(seed * 27.1) - 0.5);
			p += rot(vec2(1.0, 0.0), ba) * sp * (1.0 + 2.0 * hash(seed * 29.3)) + fwd * sp * (0.8 + 1.4 * hash(seed * 31.7));
		}
		bool fighting3 = contact && rk < 3.0;
		float period = (0.9 + hash(seed * 5.7) * 1.0) * (1.0 + rk * 0.35);
		float uu = mod(clock + seed * 17.0, period) / 0.6;
		float wu = 0.0;
		float sk = 0.0;
		if (fighting3 && uu < 1.0) {
			wu = smoothstep(0.0, 0.42, uu) * (1.0 - smoothstep(0.42, 0.52, uu));
			sk = smoothstep(0.42, 0.56, uu) * (1.0 - smoothstep(0.68, 1.0, uu));
		}
		if (fighting3) p += fwd * (sp * 0.5 * (1.0 - rk * 0.3) - 2.0 * wu + 7.0 * sk);
		if (rk <= 2.0) p -= fwd * t3.x * (1.0 - rk * 0.28) * (0.75 + 0.5 * hash(seed * 2.9));
		float hslot = floor(clock * 3.0 + hash(seed * 4.1) * 7.0);
		float hit_ph = fract(clock * 3.0 + hash(seed * 4.1) * 7.0);
		float hurt = step(0.5, t3.y) * step(rk, 1.5) * step(0.78, hash(seed * 4.1 + hslot)) * pow(1.0 - hit_ph, 2.0);
		p -= fwd * 5.0 * hurt;
		vec4 t8 = sq(row, 8);
		vec4 t9 = sq(row, 9);
		if (t9.x > 0.5 && t4.y <= 0.0) {
			vec2 fn = t8.zw;
			float sd = dot(p - t8.xy, fn);
			float lim = t9.y * (0.35 + 0.9 * hash(seed * 23.3));
			if (sd > lim) {
				float over = sd - lim;
				p -= fn * over * 0.92;
				p += vec2(-fn.y, fn.x) * (hash(seed * 24.7) - 0.5) * min(over, sp * 3.0) * 0.6;
			}
		}
		float flee = t4.y;
		if (flee > 0.0) p += rot(vec2(1.0, 0.0), hash(seed * 9.7) * 6.2831) * flee * 18.0;
		// 11/7 사용자 "하나하나가 살아 움직이듯" —— 병사마다 제 박자로
		float walk0 = t2.x * (0.8 + 0.4 * hash(seed * 6.1)) + seed * 6.2831;
		if (moving0) p += rgt * sin(walk0 * 0.45) * sp * 0.35;                    // 걸을 때 좌우로 흔들리며 간다 (발 맞추지 않는다)
		if (!contact && !moving0) {                                              // 서 있을 때 —— 가끔 한두 걸음 자리를 고쳐 선다
			float shuf = floor(clock * 0.35 + hash(seed * 33.1) * 9.0);
			vec2 to = rot(vec2(1.0, 0.0), hash(seed + shuf * 1.37) * 6.2831) * sp * 0.6 * step(0.55, hash(seed * 3.9 + shuf));
			p += to * smoothstep(0.0, 0.4, fract(clock * 0.35 + hash(seed * 33.1) * 9.0));
		}
		if (fighting3) {                                                         // 맞붙은 앞줄 —— 짝을 지어 밀고 빠지고, 옆으로 피한다
			float duel = clock * (1.6 + hash(seed * 41.3) * 1.4) + seed * 50.0;
			p += fwd * sin(duel) * sp * 0.9 * (1.0 - rk * 0.25);
			p += rgt * sin(duel * 0.7 + seed * 9.0) * sp * 0.7;
		}
		if (contact && rk >= 3.0) p += rgt * sin(clock * 2.1 + seed * 31.0) * sp * 0.35;    // 뒷줄은 앞을 보려 들썩인다
		// 2D 지도로 —— 부대 한가운데(t0.xy)에서 spread 만큼 넓히고 Type2View.map 과 같은 식으로 화면 px
		p = t0.xy + (p - t0.xy) * spread;
		vec2 d = p - center;
		sp2 = vsize * 0.5 + vec2(d.y, -d.x * tilt) * scl;
		// 걸음 —— 위아래로 살짝
		bool moving = moving0 || flee > 0.0 || move_k < 1.0;
		float walk = (t2.x + (move_k < 1.0 ? clock * 6.0 : 0.0)) * (0.8 + 0.4 * hash(seed * 6.1)) + seed * 6.2831;
		sp2.y -= abs(sin(walk * 0.9)) * 2.4 * (moving ? 1.0 : 0.0);           // 걸음 —— 위아래로 (11/7 1.4 → 2.4)
		if (fighting3) sp2.y -= abs(sin(clock * 5.0 + seed * 17.0)) * 1.6;        // 싸우는 병사는 들썩인다
		float dep = 0.82 + 0.18 * clamp(sp2.y / max(vsize.y, 1.0), 0.0, 1.0);      // 화면 위(먼) 병사는 작게
		h = fig * grow * t4.z * (0.92 + 0.16 * hash(seed * 8.3)) * dep;
		h *= max(texelFetch(tag_tex, ivec2(0, int(row)), 0).g, 0.5);      // 병종 크기 (기병 크게)
		h *= max(texelFetch(tag_tex, ivec2(0, int(row)), 0).b, 1.0);      // 11/12 등급 배율 —— 높은 등급은 인형을 덜 그리는 대신 크게
		if (fighting3 && hash(seed * 51.7 + floor(clock * 0.8 + seed * 3.0)) < 0.18) flip = -flip;      // 난전에선 가끔 옆 · 뒤를 돌아본다
		if (!contact && !moving0 && hash(seed * 61.3) < 0.07 * scatter) flip = -flip;                 // 서 있을 땐 몇이 딴 데를 본다
		rotz = (camp > 0.5 ? 0.45 : -0.45) * sk + (moving ? sin(walk * 0.9) * 0.08 : 0.0) + hurt * (camp > 0.5 ? -0.5 : 0.5);      // 내지르면 앞으로, 걸으면 좌우로, 맞으면 뒤로 젖힌다
	}
	vec2 lv = rot(VERTEX * vec2(h * flip, -h), rotz);      // 11/12 QuadMesh 는 2D 에서 위아래가 뒤집힌다 (인형이 물구나무였다) —— -h 로 바로 세운다
	VERTEX = hide ? vec2(-99999.0) : sp2 + lv + vec2(0.0, -h * 0.5);
	vec3 team = camp > 0.5 ? team_b : team_a;
	if (mod(t3.z, 2.0) >= 1.0) team = mix(team, vec3(0.48, 0.29, 0.16), 0.35);      // 파갑 —— 녹슨 빛
	team = mix(vec3(dot(team, vec3(0.3, 0.59, 0.11))), team, 1.0 + 0.3 * dark) * (1.0 - 0.2 * dark);      // 많이 줄였을수록 진영색을 짙게 (채도 +30% · 밝기 -20% 까지)
	float row_shade = 1.0 - 0.06 * mod(row, 3.0);
	float man_shade = 1.0 - (0.16 * hash(seed * 9.9) - 0.08) * scatter;      // 병사마다 옷 밝기 (무리가 한 덩어리로 보이지 않게)
	tint = vec4(team * row_shade * man_shade * shade, (dying ? 1.0 : t2.w) * alpha);
	vec4 tg0 = texelFetch(tag_tex, ivec2(0, int(row)), 0);
	atlas_x = tg0.r;
	deco = tg0.a;
	acc_c = texelFetch(tag_tex, ivec2(1, int(row)), 0).rgb;
	glow_c = texelFetch(tag_tex, ivec2(2, int(row)), 0).rgb * (0.85 + 0.3 * sin(clock * 3.0 + seed * 6.2831));      // 발광은 병사마다 느리게 일렁인다
	if (deco > 0.5) tint.rgb = mix(tint.rgb, tint.rgb * 0.82, 0.5 * (deco - 0.5));      // 고급 병사 갑옷은 조금 짙게 (금 · 깃발이 돋보이게)
}

void fragment() {
	vec2 uv = vec2(UV.x / 9.0 + atlas_x, UV.y);
	vec4 t = texture(TEXTURE, uv);
	vec4 c = t * tint;
	if (deco > 0.5) {
		// 11/12 고급 병사 —— 금(투구 · 띠 · 테두리 · 깃대) · 장식 색(깃털 · 깃발) · 둘레 발광. 진영색을 곱하지 않는다
		vec3 d = texture(deco_tex, vec2(uv.x, (clamp(UV.y, 0.012, 0.988) + floor(deco + 0.5) - 1.0) * 0.5)).rgb;      // 두 줄 경계에서 옆 줄이 번지지 않게
		vec3 gold = vec3(1.0, 0.80, 0.30) * (0.8 + 0.25 * UV.y);
		float acc = max(d.r, d.g);
		vec3 ac = d.g >= d.r ? acc_c : gold;
		if (t.a > 0.5) {
			c.rgb = mix(c.rgb, ac, acc);
		} else if (acc > 0.05) {
			c = vec4(ac, acc * tint.a);
		} else if (d.b > 0.0) {
			c = vec4(glow_c * 1.15, d.b * 0.3 * tint.a);
		}
	}
	COLOR = c;
}
