shader_type canvas_item;
render_mode unshaded;
uniform vec2 atlas_pixel_size;
varying vec4 tint;
varying float shade;      // 11/22 매복 그늘 (0~1) —— 숲 · 바위 지형을 지나는 우회 · 매복 부대

void vertex() {
	float cell = INSTANCE_CUSTOM.r;
	float phase = INSTANCE_CUSTOM.g;
	float strength = INSTANCE_CUSTOM.b;
	bool cavalry = mod(cell, 8.0) == 1.0;
	float swing = sin(phase) * strength;
	float lower = smoothstep(0.56, 1.0, UV.y);
	float half_side = mix(-1.0, 1.0, smoothstep(0.31, 0.67, UV.x));
	VERTEX.x += swing * (0.009 * (1.0 - lower) + half_side * lower * (cavalry ? 0.055 : 0.05));
	VERTEX.y -= lower * max(0.0, swing * half_side) * (cavalry ? 0.068 : 0.056);
	// Match the legacy mesh's 0.75-pixel inset on each atlas cell.
	vec2 pad = vec2(0.75) * atlas_pixel_size;
	UV = (vec2(mod(cell, 4.0), floor(cell / 4.0)) + UV) * 0.25;
	UV = mix(UV + pad, UV - pad, UV * 4.0 - vec2(mod(cell, 4.0), floor(cell / 4.0)));
	tint = COLOR;
	shade = INSTANCE_CUSTOM.a;
}

void fragment() {
	vec4 c = texture(TEXTURE, UV);
	if (shade > 0.01) {
		// 그늘 속 —— 두 탭 더 섞어 살짝 흐릿하게 (그늘 부대만), 빛을 빼고 푸른 그림자 빛으로 어둡게
		vec2 o = vec2(0.007, 0.009) * shade;      // 아틀라스 칸(0.25)의 3% 남짓 = 인형 키의 1~2px
		c = mix(c, (texture(TEXTURE, UV + o) + texture(TEXTURE, UV - o) + c) / 3.0, shade);
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
