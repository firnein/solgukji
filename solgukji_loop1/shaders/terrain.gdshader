// 지형 —— 10/31 사용자: 카툰 · 로우폴리 느낌을 벗는다 → 실사 텍스처 (Poly Haven CC0: 풀밭 aerial_grass_rock · 진흙 brown_mud_leaves_01)
// 정점 색 rgb 는 땅빛을 아주 조금 물들이는 데만, 정점 알파는 진흙 비율(밟힌 곳 · 비탈)로 쓴다.
// 반복 무늬가 드러나지 않게 크기가 다른 두 배율로 겹쳐 그리고, 큰 잡음으로 진흙 경계를 흩뜨린다.
shader_type spatial;

uniform sampler2D detail : repeat_enable, filter_linear_mipmap;
uniform sampler2D grass_diff : source_color, repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D grass_nor : hint_normal, repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D grass_rough : hint_roughness_g, repeat_enable, filter_linear_mipmap;
uniform sampler2D mud_diff : source_color, repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D mud_nor : hint_normal, repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D mud_rough : hint_roughness_g, repeat_enable, filter_linear_mipmap;
uniform float tile = 7.0;            // 텍스처 한 장이 덮는 세계 단위 (병사 키 약 1.4)
uniform bool realistic = false;      // 11/2 사용자: 실사 텍스처가 깨지고 지글거린다 → 기본은 깔끔한 정점 색 지형
varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

vec2 uv2_of(vec2 uv) {
	return mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8)) * uv * 0.31 + vec2(0.17, 0.43);
}

// 같은 함수에 성격이 다른 텍스처(색 · 노멀 · 거칠기)를 넘길 수 없어 셋으로 나눈다
vec4 dual(sampler2D t, vec2 uv) { return mix(texture(t, uv), texture(t, uv2_of(uv)), 0.38); }
vec4 dual_n(sampler2D t, vec2 uv) { return mix(texture(t, uv), texture(t, uv2_of(uv)), 0.38); }
vec4 dual_r(sampler2D t, vec2 uv) { return mix(texture(t, uv), texture(t, uv2_of(uv)), 0.38); }

void fragment() {
	float fine = texture(detail, wpos.xz * 0.09).r;
	float broad = texture(detail, wpos.xz * 0.012 + vec2(0.37, 0.11)).r;
	if (!realistic) {
		// 깔끔한 톤 —— 잔무늬(fine) 없이 아주 큰 얼룩만 살짝. 멀리서 반짝이며 지글거리지 않게
		ALBEDO = pow(COLOR.rgb, vec3(2.2)) * (0.92 + 0.16 * broad);
		ROUGHNESS = 1.0;
		SPECULAR = 0.15;
	} else {
		vec2 uv = wpos.xz / tile;
		float w = clamp(COLOR.a + (broad - 0.5) * 0.7 + (fine - 0.5) * 0.25, 0.0, 1.0);
		w = smoothstep(0.25, 0.75, w);
		vec3 g = dual(grass_diff, uv).rgb;
		vec3 m = dual(mud_diff, uv * 1.3).rgb;
		vec3 tint = mix(vec3(1.0), pow(COLOR.rgb, vec3(2.2)) / vec3(0.075, 0.085, 0.045), 0.12);
		ALBEDO = mix(g * vec3(0.86, 0.95, 0.72), m, w) * tint * (0.55 + 0.22 * broad);      // 밝기를 낮추고 풀빛을 조금 살린다
		NORMAL_MAP = mix(dual_n(grass_nor, uv).rgb, dual_n(mud_nor, uv * 1.3).rgb, w);
		NORMAL_MAP_DEPTH = 1.2;
		ROUGHNESS = mix(dual_r(grass_rough, uv).g, dual_r(mud_rough, uv * 1.3).g, w);
		SPECULAR = 0.3;
	}
}
