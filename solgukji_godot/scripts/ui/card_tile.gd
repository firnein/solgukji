class_name CardTile
extends Control
## 작은 카드 —— 손패·조합·선택권 목록에 쓴다. 왼쪽 초상, 등급색 띠, 이름, 병종·등급, 장수.
## 탭하면 tapped. drag_data 를 주면 길게 눌러(0.35초) 끌 수 있다 —— 짧게 끌면 목록이 스크롤된다.

signal tapped(k: String)

const SIZE := Vector2(176, 78)
const HOLD := 0.35

var k := ""
var qty := -1
var note := ""              # 아래 줄 대신 쓸 짧은 글 (예: "선호 · 공격 +22%")
var note_col := Color.TRANSPARENT
var mark := ""              # "pref" · "bad" · "on" (편성 중) · "sel" (골랐다) · "dim"
var drag_data = null        # 있으면 길게 눌러 끌 수 있다
var _press := Vector2.INF
var _held := 0.0
var _dragging := false


func setup(id: String, n := -1, sz := SIZE) -> CardTile:
	k = id
	qty = n
	custom_minimum_size = sz
	size = sz
	mouse_filter = Control.MOUSE_FILTER_PASS
	return self


func _gui_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
		if e.pressed:
			_press = e.position
			_held = 0.0
			_dragging = false
		else:
			if _press != Vector2.INF and not _dragging and e.position.distance_to(_press) < 14:
				tapped.emit(k)
			_press = Vector2.INF
	elif e is InputEventMouseMotion and _press != Vector2.INF:
		if e.position.distance_to(_press) >= 14:
			_press = Vector2.INF       # 끌었다 —— 스크롤에 맡긴다


func _process(dt: float) -> void:
	if drag_data == null or _press == Vector2.INF or _dragging:
		return
	_held += dt
	if _held >= HOLD:
		_dragging = true
		_press = Vector2.INF
		var pv := CardTile.new().setup(k, -1)
		pv.modulate = Color(1, 1, 1, 0.85)
		var holder := Control.new()
		holder.add_child(pv)
		pv.position = -SIZE / 2
		force_drag(drag_data, holder)


func _draw() -> void:
	if k == "":
		return
	var c: Dictionary = DB.C[k]
	var tc := DB.tier_color(k)
	var w := size.x
	var h := size.y
	var bg: Color = DB.PAL.ink2
	var border: Color = DB.PAL.ink4
	match mark:
		"pref":
			border = DB.PAL.jade
		"bad":
			border = DB.PAL.seal
		"on":
			bg = DB.PAL.ink3
		"sel":
			border = DB.PAL.gold
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(2 if mark in ["pref", "bad", "sel"] else 1)
	sb.border_width_left = 5
	sb.set_corner_radius_all(6)
	draw_style_box(sb, Rect2(Vector2.ZERO, size))
	draw_rect(Rect2(0, 0, 5, h), tc)
	# 초상
	var pr := Rect2(8, 5, h * 0.78, h - 10)
	Art.draw_portrait(self, pr, k)
	if c.tier > 2:
		draw_circle(pr.position + Vector2(9, 9), 8, DB.fac_color(c.fac))
		draw_string(DB.font_display, pr.position + Vector2(1, 13), c.fac, HORIZONTAL_ALIGNMENT_CENTER, 16, 10, Color.WHITE)
	var x := pr.end.x + 7
	var tw := w - x - 6
	var fd := DB.font_display
	var fb := DB.font_body
	var fs := 15
	while fs > 10 and fd.get_string_size(c.name, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > tw - (22 if qty > 0 else 0):
		fs -= 1
	draw_string(fd, Vector2(x, 24), c.name, HORIZONTAL_ALIGNMENT_LEFT, tw, fs, tc.lightened(0.2) if c.tier >= 3 else DB.PAL.paper)
	draw_texture_rect(DB.ICON[c.tag], Rect2(x, 33, 13, 13), false, DB.PAL.bamboo)
	draw_string(fb, Vector2(x + 16, 45), "%s · %s" % [c.tag, DB.TIER[c.tier].n], HORIZONTAL_ALIGNMENT_LEFT, tw - 16, 12, DB.PAL.bamboo)
	if note != "":
		draw_string(fb, Vector2(x, 66), note, HORIZONTAL_ALIGNMENT_LEFT, tw, 11, note_col if note_col.a > 0 else DB.PAL.bamboo_dim)
	else:
		draw_string(fb, Vector2(x, 66), "병력 %s · %d PV" % [Battle.num(c.tr), c.pv], HORIZONTAL_ALIGNMENT_LEFT, tw, 11, DB.PAL.bamboo_dim)
	if qty > 0:
		var qr := Rect2(w - 28, 5, 23, 19)
		draw_rect(qr, Color(DB.PAL.gold, 0.9))
		draw_string(fb, qr.position + Vector2(0, 15), str(qty), HORIZONTAL_ALIGNMENT_CENTER, qr.size.x, 13, Color("#1A1508"))
	if mark == "dim":
		draw_rect(Rect2(Vector2.ZERO, size), Color(DB.PAL.ink, 0.55))
