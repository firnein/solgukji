class_name FormationView
extends Control
## 전투 탭의 내 진영 미리 보기 (11/4 사용자: 남는 공간에 지금 배치된 병종을 그린다) ——
## 진형 칸 자리대로 병종 병사 그림(assets/troops_sprite, 첫 칸 = 서 있는 모습) 몇 명 + 장수 얼굴 메달 · 이름. 위쪽이 적 방향.

const COLS := 3
var cards: Array = []        # 9칸 카드 id (null 은 빈칸)
var form := ""
var t := 0.0
var _sprites := {}
var _mat: ShaderMaterial

const SHADER := """
shader_type canvas_item;
uniform vec4 team : source_color = vec4(0.25, 0.45, 0.9, 1.0);
void fragment() {
	// COLOR = 텍스처색 × 정점색 (그림 없는 땅 · 선은 정점색 그대로) —— 그림의 자홍(진영색 자리)만 진영색으로
	vec4 c = COLOR;
	float m = smoothstep(0.18, 0.32, min(c.r, c.b) - c.g) * step(0.3, c.b);
	COLOR.rgb = mix(c.rgb, team.rgb * (0.6 + 0.6 * c.b), m);
}
"""


func setup(board: Array, form_key: String) -> FormationView:
	cards = board
	form = form_key
	return self


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	var sh := Shader.new()
	sh.code = SHADER
	_mat = ShaderMaterial.new()
	_mat.shader = sh
	_mat.set_shader_parameter("team", Color("#4f8be0"))
	material = _mat
	var ov := Medals.new()
	ov.fv = self
	ov.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ov.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ov.use_parent_material = false
	add_child(ov)


func _sprite(tag: String) -> Texture2D:
	if not _sprites.has(tag):
		_sprites[tag] = DB._load_portrait("res://assets/troops_sprite/" + tag)
	return _sprites[tag]


func _process(dt: float) -> void:
	if is_visible_in_tree():
		t += dt
		queue_redraw()
		for ch in get_children():
			ch.queue_redraw()


func _draw() -> void:
	var sz := size
	if sz.x < 10 or sz.y < 10:
		return
	# 땅 —— 어두운 풀빛 그라데이션 + 옅은 줄
	var top := Color("#1d2a22")
	var bot := Color("#121a16")
	draw_polygon(PackedVector2Array([Vector2.ZERO, Vector2(sz.x, 0), sz, Vector2(0, sz.y)]), PackedColorArray([top, top, bot, bot]))
	for i in 6:
		var y := sz.y * (i + 0.5) / 6.0
		draw_line(Vector2(0, y), Vector2(sz.x, y), Color(1, 1, 1, 0.025), 1.0)
	draw_string(DB.font_bold, Vector2(0, 16), "▲ 적", HORIZONTAL_ALIGNMENT_CENTER, sz.x, 11, Color(DB.PAL.seal, 0.8))
	pass      # 11/4 사용자: 병졸 그림은 그리지 않고 장수 원형 얼굴만 (Medals)


## 칸마다 [중심, 카드, 칸 크기, 번호] —— 뒤 줄부터 (앞 줄이 위에 겹치게)
func layout() -> Array:
	var out := []
	if form == "" or not DB.FORM.has(form):
		return out
	var sz := size
	var slots: Array = DB.FORM[form].slots
	var rows := 1
	for s in slots:
		rows = maxi(rows, int(s.row) + 1)
	var cw := sz.x / COLS
	var rh := (sz.y - 26.0) / rows
	var order := range(slots.size())
	order.sort_custom(func(a, b): return int(slots[a].row) < int(slots[b].row))
	for i in order:
		if i >= cards.size() or cards[i] == null:
			continue
		var s: Dictionary = slots[i]
		out.append([Vector2(cw * (int(s.col) + 0.5), 26.0 + rh * (int(s.row) + 0.55)), cards[i], minf(cw, rh), i])
	return out


func _squad(c: Vector2, k: String, cell: float, seed_: int) -> void:
	var tex := _sprite(DB.C[k].tag)
	var fw := 256.0
	var fh := 256.0
	var h := cell * 0.8          # 그림 칸(256px)에서 병사는 가운데 1/3 정도 —— 칸을 크게 잡는다
	var w := h * fw / fh
	if tex:
		var n := 5 if DB.C[k].tier < 6 else 7
		for j in n:
			var row := j / 4
			var col := j % 4
			var off := Vector2((col - 1.5) * w * 0.16 + (row * w * 0.08), row * h * 0.07)
			var bob := sin(t * 2.2 + seed_ * 1.3 + j) * 1.2
			var p := c + off + Vector2(-w / 2.0, -h * 0.62 + bob)
			draw_texture_rect_region(tex, Rect2(p, Vector2(w, h)), Rect2(0, 0, fw, fh))


## 장수 메달 · 이름 —— 병사 무리 위 (병사 셰이더가 메달 테 색을 바꾸지 않게 따로 그린다)
class Medals extends Control:
	var fv: FormationView

	func _draw() -> void:
		for e in fv.layout():
			var c: Vector2 = e[0]
			var k: String = e[1]
			var cell: float = e[2]
			var r := clampf(cell * 0.3, 18.0, 34.0)
			var mc := c + Vector2(0, -8.0)
			draw_circle(mc, r + 3.0, Color(0, 0, 0, 0.55))
			draw_circle(mc, r + 2.0, DB.tier_color(k))
			draw_circle(mc, r + 0.6, Color("#4f8be0"))
			Art.draw_face_circle(self, mc, r, k)
			var nm: String = DB.person(k) if DB.C[k].tier > 2 else DB.C[k].name
			var f: Font = DB.font_bold
			draw_string_outline(f, Vector2(mc.x - 60, mc.y + r + 17), nm, HORIZONTAL_ALIGNMENT_CENTER, 120, 13, 4, Color(0, 0, 0, 0.8))
			draw_string(f, Vector2(mc.x - 60, mc.y + r + 17), nm, HORIZONTAL_ALIGNMENT_CENTER, 120, 13, DB.tier_color(k).lightened(0.3))
