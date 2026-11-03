// 병사 (구운 애니메이션, 10/31 —— KayKit CC0 모델) : 정점 위치 · 법선을 프레임마다 텍스처(VAT)에서 읽는다.
// 가로 = 정점 번호(VERTEX_ID), 세로 = 프레임. 동작마다 [시작 줄, 프레임 수] (tests/bake_vat.gd 가 정한다).
// INSTANCE_CUSTOM 은 soldier.gdshader 와 같다: r 진영 + 옷 밝기 · g 어둡게(+, 쓰러진 정도)/공격 진행(-) · b 번쩍 · a 걸음 박자(+2 서 있음)
// UV2.x 1 = 팔레트 텍스처 색, 0 = 정점 색. COLOR.a 1 = 세력색으로 칠할 곳
shader_type spatial;
render_mode cull_disabled;

uniform sampler2D vat_pos : filter_nearest, repeat_disable;
uniform sampler2D vat_nrm : filter_nearest, repeat_disable;
uniform sampler2D palette : source_color, filter_linear;
uniform vec3 team_a : source_color = vec3(0.25, 0.5, 0.82);
uniform vec3 team_b : source_color = vec3(0.78, 0.27, 0.23);
uniform float bright = 1.0;      // 텍스처 밝기 (어두운 갑옷 인물을 올린다 —— 굽기 표의 bright)
uniform vec2 clip_idle = vec2(0.0, 4.0);
uniform vec2 clip_walk = vec2(4.0, 8.0);
uniform vec2 clip_attack = vec2(12.0, 6.0);
uniform vec2 clip_hit = vec2(18.0, 4.0);
uniform vec2 clip_death = vec2(22.0, 6.0);
uniform vec2 clip_cheer = vec2(28.0, 4.0);

varying vec4 v_custom;

vec3 fetch(sampler2D t, int id, int row) {
	return texelFetch(t, ivec2(id, row), 0).xyz;
}

void vertex() {
	vec4 ic = INSTANCE_CUSTOM;
	float team = step(0.75, ic.r);
	float tint = clamp((ic.r - team) * 2.0, 0.0, 1.0);
	float dark = max(ic.g, 0.0);
	float atk = max(-ic.g, 0.0);
	float moving = step(ic.a, 1.5);
	float ph = fract(ic.a);
	v_custom = vec4(team, dark, ic.b, tint);
	vec2 clip;
	float f;
	bool loop = false;
	if (dark > 0.001) { clip = clip_death; f = clamp(dark / 0.42, 0.0, 1.0) * (clip.y - 1.0); }
	else if (atk > 0.0) { clip = clip_attack; f = atk * (clip.y - 1.0); }
	else if (ic.b > 0.05) { clip = clip_hit; f = clamp(ic.b / 0.45, 0.0, 1.0) * (clip.y - 1.0) * 0.6; }
	else if (moving > 0.5) { clip = clip_walk; f = ph * clip.y; loop = true; }
	else { clip = clip_idle; f = fract(TIME * 0.35 + tint * 7.0) * clip.y; loop = true; }
	float f0 = floor(f);
	float fr = f - f0;
	float f1 = f0 + 1.0;
	if (loop) { f0 = mod(f0, clip.y); f1 = mod(f1, clip.y); }
	else { f1 = min(f1, clip.y - 1.0); }
	int r0 = int(clip.x + f0);
	int r1 = int(clip.x + f1);
	int id = VERTEX_ID;
	VERTEX = mix(fetch(vat_pos, id, r0), fetch(vat_pos, id, r1), fr);
	NORMAL = normalize(mix(fetch(vat_nrm, id, r0), fetch(vat_nrm, id, r1), fr));
}

void fragment() {
	vec3 team = mix(team_a, team_b, v_custom.r);
	vec3 base;
	if (UV2.x > 0.5) {
		base = texture(palette, UV).rgb * bright;
	} else {
		base = pow(COLOR.rgb, vec3(2.2));
	}
	float lum = dot(base, vec3(0.3, 0.59, 0.11));
	vec3 dyed = team * clamp(0.45 + lum * 1.6, 0.0, 1.4) * (0.85 + 0.3 * v_custom.a);
	base = mix(base, dyed, COLOR.a);
	base *= 1.0 - v_custom.g;
	base = mix(base, vec3(1.0, 0.92, 0.85), max(v_custom.b, 0.0));
	ALBEDO = base;
	ROUGHNESS = 0.75;
	EMISSION = team * 0.05 * COLOR.a * (1.0 - v_custom.g * 2.0) + vec3(1.0, 0.9, 0.8) * max(v_custom.b, 0.0) * 0.6;
}
