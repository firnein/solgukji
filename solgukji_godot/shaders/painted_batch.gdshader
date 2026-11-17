shader_type canvas_item;
render_mode unshaded;
uniform vec2 atlas_pixel_size;
varying vec4 tint;

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
}

void fragment() {
	COLOR = texture(TEXTURE, UV) * tint;
}
