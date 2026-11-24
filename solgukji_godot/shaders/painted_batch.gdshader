shader_type canvas_item;
render_mode unshaded;
uniform vec2 atlas_pixel_size;
uniform sampler2D idle_atlas : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2D action_blue : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2D action_red : source_color, filter_linear_mipmap, repeat_disable;
uniform vec2 action_blue_pixel_size;
uniform vec2 action_red_pixel_size;
varying vec4 tint;
varying float shade;      // 11/22 매복 그늘 (0~1) —— 숲 · 바위 지형을 지나는 우회 · 매복 부대
varying float standard;
varying float flag_phase;
varying float action_army;

void vertex() {
	float cell = INSTANCE_CUSTOM.r;
	standard = cell >= 16.0 && cell < 18.0 ? cell - 15.0 : 0.0;
	action_army = cell >= 64.0 ? 2.0 : (cell >= 32.0 ? 1.0 : 0.0);
	flag_phase = INSTANCE_CUSTOM.g;
	float phase = INSTANCE_CUSTOM.g;
	float strength = INSTANCE_CUSTOM.b;
	float action_cell = mod(cell - 32.0, 32.0);
	bool cavalry = action_army > 0.5 ? floor(action_cell / 4.0) == 1.0 : mod(cell, 8.0) == 1.0;
	float swing = sin(phase) * strength;
	float lower = smoothstep(0.56, 1.0, UV.y);
	float half_side = mix(-1.0, 1.0, smoothstep(0.31, 0.67, UV.x));
	VERTEX.x += swing * (0.009 * (1.0 - lower) + half_side * lower * (cavalry ? 0.055 : 0.05));
	VERTEX.y -= lower * max(0.0, swing * half_side) * (cavalry ? 0.068 : 0.056);
	// Match the legacy mesh's 0.75-pixel inset on each atlas cell.
	vec2 pad = vec2(0.75) * atlas_pixel_size;
	if (action_army > 0.5) {
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
	shade = INSTANCE_CUSTOM.a;
}

vec4 sprite_sample(vec2 at) {
	if (action_army > 1.5) { return texture(action_red, at); }
	if (action_army > 0.5) { return texture(action_blue, at); }
	return texture(idle_atlas, at);
}

void fragment() {
	vec4 c = sprite_sample(UV);
	if (standard > 0.5) {
		float pole = (1.0 - smoothstep(0.016, 0.03, abs(UV.x - 0.42))) * step(0.09, UV.y) * step(UV.y, 0.98);
		float flutter = sin(flag_phase - UV.x * 9.0) * 0.025 * smoothstep(0.43, 0.92, UV.x);
		float y = UV.y + flutter;
		float top = 0.12 + (UV.x - 0.44) * 0.16;
		float bottom = 0.48 - (UV.x - 0.44) * 0.09;
		float cloth = step(0.44, UV.x) * step(UV.x, 0.94) * step(top, y) * step(y, bottom);
		float edge = cloth * (step(y, top + 0.025) + step(bottom - 0.025, y) + step(0.91, UV.x));
		vec3 flag_color = standard < 1.5 ? vec3(0.19, 0.37, 0.59) : vec3(0.64, 0.20, 0.13);
		float stripe = cloth * step(abs(UV.x - 0.65) + abs(y - 0.31), 0.085);
		vec3 flag_rgb = mix(flag_color, vec3(0.88, 0.75, 0.48), clamp(edge + stripe, 0.0, 1.0));
		c = vec4(mix(vec3(0.23, 0.17, 0.10), flag_rgb, cloth), max(pole, cloth));
	}
	if (shade > 0.01) {
		// 그늘 속 —— 두 탭 더 섞어 살짝 흐릿하게 (그늘 부대만), 빛을 빼고 푸른 그림자 빛으로 어둡게
		vec2 o = vec2(0.007, 0.009) * shade;      // 아틀라스 칸(0.25)의 3% 남짓 = 인형 키의 1~2px
		if (standard < 0.5) {
			c = mix(c, (sprite_sample(UV + o) + sprite_sample(UV - o) + c) / 3.0, shade);
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
