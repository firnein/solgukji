// 깃발 —— 깃대에서 멀어질수록 크게 펄럭인다. UV.x 0 이 깃대 쪽.
shader_type spatial;
render_mode cull_disabled;

uniform vec3 color : source_color = vec3(0.8, 0.2, 0.2);
uniform float phase = 0.0;

void vertex() {
	float w = UV.x;
	VERTEX.z += sin(TIME * 4.0 + phase + UV.x * 5.0) * 0.18 * w;
	VERTEX.y += sin(TIME * 3.0 + phase + UV.x * 3.0) * 0.05 * w;
}

void fragment() {
	float shade = 0.85 + 0.15 * sin(UV.x * 5.0 + TIME * 4.0 + phase);
	ALBEDO = color * shade;
	ROUGHNESS = 0.9;
}
