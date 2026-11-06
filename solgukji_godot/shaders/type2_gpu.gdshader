// 타입2 GPU 병사 (11/6 목표: 휴대폰에서도 품질이 떨어지지 않는 대군) —— 살아 있는 병사의 자리를 정점 셰이더가 계산한다.
// 3D 의 soldier_gpu.gdshader 와 같은 부대 데이터(squad_tex, War3D._gpu_sync)와 같은 대열 식을 2D 지도에 옮겼다.
// CPU 는 부대마다 한 줄만 넘기고, 병사가 쓰러지거나 자리를 옮길 때만 그 인스턴스 값을 고친다 (Type2View.gpu_moved).
// 쓰러지는 병사 · 장수는 CPU 가 그린다 (Type2View._draw_dots).
// INSTANCE_CUSTOM: r = 부대 줄, g = 자리 (음수 숨김 · 자리 + (전 자리+1)×1024), b = 씨앗, a = 자리 옮기기 시작 시각
shader_type canvas_item;

uniform sampler2D squad_tex : filter_nearest;
uniform sampler2D tag_tex : filter_nearest;      // 11/7 부대 줄 -> 병종 인형 칸 (아틀라스 9칸 중, 0~1)
uniform vec2 center;            // 화면 가운데 전장 자리 (흔들림 포함)
uniform float scl = 1.0;
uniform float tilt = 1.25;
uniform vec2 vsize = vec2(540.0, 800.0);
uniform float spread = 1.35;    // Type2View.T2_SPREAD —— 부대 안 병사 사이를 넓혀 그린다
uniform float fig = 17.0;       // 인형 키 (화면 px)
uniform vec3 team_a : source_color = vec3(0.29, 0.54, 0.91);
uniform vec3 team_b : source_color = vec3(0.93, 0.31, 0.24);

varying vec4 tint;
varying float atlas_x;

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
	vec2 squeeze = sq(row, 7).xy;
	float clock = t5.z;
	float g = ic.g;
	bool hide = g < 0.0 || t1.z <= 0.0 || seed > t2.w;
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
	float edge = abs(slot - rk * cols - half_c) / max(half_c, 1.0);
	float lag = clamp(1.0 - (rk / rows) * 0.12 - edge * 0.05 - hash(seed * 12.7) * 0.06, 0.8, 1.0);      // 11/7 강체: 뒷줄 지연을 작게 —— 대열이 발자국 밖으로 늘어지지 않는다
	vec2 pos = mix(t6.xy, t0.xy, lag);
	vec2 fwd = normalize(mix(t6.zw, t0.zw, lag) + vec2(1e-5, 0.0));
	vec2 rgt = vec2(-fwd.y, fwd.x);
	vec2 front = pos + fwd * t1.w * squeeze.x;
	vec2 jit = rot(vec2(1.0, 0.0), hash(seed * 7.1) * 6.2831) * hash(seed * 3.3) * sp * 0.75 * min(squeeze.x, squeeze.y);
	float c = slot - rk * cols;
	float c0 = slot0 - rk0 * cols;
	vec2 l1 = vec2(-((rk + 0.5) * spr), (c - half_c + mod(rk, 2.0) * 0.5) * sp);
	vec2 l0 = vec2(-((rk0 + 0.5) * spr), (c0 - half_c + mod(rk0, 2.0) * 0.5) * sp);
	vec2 lc = mix(l0, l1, move_k) * squeeze;
	lc.x += sin(lc.y * 0.09 + row * 1.7 + clock * 0.35) * sp * 0.9;
	lc.y += sin(lc.x * 0.11 + row * 2.3) * sp * 0.5;
	vec2 p = front + fwd * lc.x + rgt * lc.y + jit;
	bool contact = t2.z > 0.5;
	bool fighting = contact && rk < 2.0;
	float loose = t5.x;
	bool moving0 = t2.y > 0.5;
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
	vec2 sp2 = vsize * 0.5 + vec2(d.y, -d.x * tilt) * scl;
	// 걸음 —— 위아래로 살짝
	bool moving = moving0 || flee > 0.0 || move_k < 1.0;
	float walk = (t2.x + (move_k < 1.0 ? clock * 6.0 : 0.0)) * (0.8 + 0.4 * hash(seed * 6.1)) + seed * 6.2831;
	sp2.y -= abs(sin(walk * 0.9)) * 2.4 * (moving ? 1.0 : 0.0);           // 걸음 —— 위아래로 (11/7 1.4 → 2.4)
	if (fighting3) sp2.y -= abs(sin(clock * 5.0 + seed * 17.0)) * 1.6;        // 싸우는 병사는 들썩인다
	float dep = 0.82 + 0.18 * clamp(sp2.y / max(vsize.y, 1.0), 0.0, 1.0);      // 화면 위(먼) 병사는 작게
	float h = fig * t4.z * (0.92 + 0.16 * hash(seed * 8.3)) * dep;
	h *= max(texelFetch(tag_tex, ivec2(0, int(row)), 0).g, 0.5);      // 병종 크기 (기병 크게)
	float camp = t5.y;
	float flip = camp > 0.5 ? -1.0 : 1.0;
	if (fighting3 && hash(seed * 51.7 + floor(clock * 0.8 + seed * 3.0)) < 0.18) flip = -flip;      // 난전에선 가끔 옆 · 뒤를 돌아본다
	float lean = (camp > 0.5 ? 0.45 : -0.45) * sk + (moving ? sin(walk * 0.9) * 0.08 : 0.0) + hurt * (camp > 0.5 ? -0.5 : 0.5);      // 내지르면 앞으로, 걸으면 좌우로, 맞으면 뒤로 젖힌다
	vec2 lv = rot(VERTEX * vec2(h * flip, h), lean);
	VERTEX = hide ? vec2(-99999.0) : sp2 + lv + vec2(0.0, -h * 0.5);
	vec3 team = camp > 0.5 ? team_b : team_a;
	if (mod(t3.z, 2.0) >= 1.0) team = mix(team, vec3(0.48, 0.29, 0.16), 0.35);      // 파갑 —— 녹슨 빛
	float row_shade = 1.0 - 0.06 * mod(row, 3.0);
	tint = vec4(team * row_shade, t2.w);
	atlas_x = texelFetch(tag_tex, ivec2(0, int(row)), 0).r;
}

void fragment() {
	vec4 t = texture(TEXTURE, vec2(UV.x / 9.0 + atlas_x, UV.y));
	COLOR = t * tint;
}
