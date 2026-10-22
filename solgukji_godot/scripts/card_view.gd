class_name CardView
extends Control
## 카드 한 장 —— 등급색 테두리, 세력 배지, 병종 아이콘, 초상, 이름, 병력·PV.
## 초월 이상은 테두리가 빛나고, 불멸은 문양, 신화는 금박이 반짝인다.

signal picked(k: String)

var k := ""
var selected := false:
	set(v):
		selected = v
		queue_redraw()
var _t := 0.0
var _hover := false


func setup(id: String, sz := Vector2(150, 214)) -> CardView:
	k = id
	custom_minimum_size = sz
	size = sz
	pivot_offset = sz / 2
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_process(DB.C[k].tier >= 6)
	mouse_entered.connect(func(): _set_hover(true))
	mouse_exited.connect(func(): _set_hover(false))
	return self


func _set_hover(v: bool) -> void:
	_hover = v
	var tw := create_tween()
	tw.tween_property(self, "scale", Vector2.ONE * (1.04 if v else 1.0), 0.12)
	z_index = 1 if v else 0
	queue_redraw()


func _gui_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
		picked.emit(k)


func _process(d: float) -> void:
	if not is_visible_in_tree():
		return
	_t += d
	queue_redraw()


func _draw() -> void:
	if k == "":
		return
	var c: Dictionary = DB.C[k]
	var tc := DB.tier_color(k)
	var w := size.x
	var h := size.y
	var u := w / 150.0      # 크기에 비례해 글자와 여백을 키운다

	var sb := StyleBoxFlat.new()
	sb.bg_color = DB.PAL.ink2
	sb.set_corner_radius_all(int(8 * u))
	sb.border_color = DB.PAL.gold if selected else tc
	sb.set_border_width_all(int((3 if c.tier >= 6 or selected else 2) * u))
	if c.tier >= 6 or selected or _hover:
		var pulse := 0.5 + 0.5 * sin(_t * 2.2)
		sb.shadow_color = Color(sb.border_color, 0.25 + (0.25 * pulse if c.tier >= 8 else 0.1))
		sb.shadow_size = int((6 + (4 * pulse if c.tier >= 8 else 0)) * u)
	draw_style_box(sb, Rect2(Vector2.ZERO, size))
	if c.tier >= 8:
		var inner := StyleBoxFlat.new()
		inner.draw_center = false
		inner.border_color = Color(tc, 0.45)
		inner.set_border_width_all(1)
		inner.set_corner_radius_all(int(6 * u))
		draw_style_box(inner, Rect2(Vector2(4, 4) * u, size - Vector2(8, 8) * u))

	var m := 7.0 * u
	var pr := Rect2(m, m, w - m * 2, h * 0.60)
	Art.draw_portrait(self, pr, k, _t)
	Art.draw_tier_fx(self, pr, k, _t)

	var fb := DB.font_body
	var fd := DB.font_display
	# 등급 띠
	var bh := 17.0 * u
	draw_rect(Rect2(pr.position.x, pr.end.y - bh, pr.size.x, bh), Color(DB.PAL.ink, 0.72))
	draw_string(fb, Vector2(pr.position.x + 6 * u, pr.end.y - 4.5 * u), DB.TIER[c.tier].n,
		HORIZONTAL_ALIGNMENT_LEFT, -1, int(11 * u), tc)
	if c.sk:
		draw_string(fb, Vector2(pr.position.x, pr.end.y - 4.5 * u), c.sk.n,
			HORIZONTAL_ALIGNMENT_RIGHT, pr.size.x - 6 * u, int(10 * u), Color(DB.PAL.bamboo, 0.9))

	# 세력 배지 · 병종 아이콘
	var br := 10.5 * u
	if c.tier > 2:
		var bp := pr.position + Vector2(br + 3 * u, br + 3 * u)
		draw_circle(bp, br, DB.fac_color(c.fac))
		draw_string(fd, bp + Vector2(-br, 4.5 * u), c.fac, HORIZONTAL_ALIGNMENT_CENTER, br * 2, int(12 * u), Color.WHITE)
	var ip := Vector2(pr.end.x - br - 3 * u, pr.position.y + br + 3 * u)
	draw_circle(ip, br, Color(DB.PAL.ink, 0.78))
	draw_texture_rect(DB.ICON[c.tag], Rect2(ip - Vector2(7, 7) * u, Vector2(14, 14) * u), false, DB.PAL.paper)

	# 이름 —— 길면 글자를 줄인다
	var fs := int(15 * u)
	while fs > 9 and fd.get_string_size(c.name, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > w - m * 2:
		fs -= 1
	var y := pr.end.y + 21 * u
	draw_string(fd, Vector2(m, y), c.name, HORIZONTAL_ALIGNMENT_CENTER, w - m * 2, fs,
		tc.lightened(0.15) if c.tier >= 6 else DB.PAL.paper)
	y += 16 * u
	var sub := "%s · %s" % [c.tag, DB.D.FAC[c.fac].full]
	draw_string(fb, Vector2(m, y), sub, HORIZONTAL_ALIGNMENT_CENTER, w - m * 2, int(10.5 * u), DB.PAL.bamboo_dim)
	# 병력 · PV
	y = h - 9 * u
	draw_line(Vector2(m, y - 15 * u), Vector2(w - m, y - 15 * u), DB.PAL.ink3, 1.0)
	draw_string(fb, Vector2(m, y), "병력 " + Battle.num(c.tr), HORIZONTAL_ALIGNMENT_LEFT, -1, int(10.5 * u), DB.PAL.bamboo)
	draw_string(fb, Vector2(m, y), "PV %d" % c.pv, HORIZONTAL_ALIGNMENT_RIGHT, w - m * 2, int(10.5 * u), DB.PAL.bamboo)
