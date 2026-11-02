class_name MiniTile
extends Control
## 초상 위주의 작은 카드 —— 휴대폰 세로에서 한 줄에 4장. 보유 카드·조합 격자·재료에 쓴다.
## 위: 초상(등급색 테두리 · 세력 점 · 장수 배지) / 아래: 이름. 왼쪽 아래 알약 배지(조합 · -2 · 2/3 …).
## 짧게 누르면 tapped, 끌면 목록이 스크롤된다.

signal tapped(k: String)

var k := ""
var qty := -1
var badge := ""             # 왼쪽 아래 알약 글씨
var badge_col := Color.TRANSPARENT
var lit := false          # 금빛 테두리 (지금 조합 가능)
var up := false             # 오른쪽 위 ▲ —— 지금 조합 가능한 상위 카드의 재료
var dim := false            # 흐리게 (없는 카드)
var _press := Vector2.INF


func setup(id: String, n := -1) -> MiniTile:
	k = id
	qty = n
	custom_minimum_size = Vector2(78, 112)
	mouse_filter = Control.MOUSE_FILTER_PASS
	return self


func _gui_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
		if e.pressed:
			_press = e.position
		else:
			if _press != Vector2.INF and e.position.distance_to(_press) < 14:
				UI.buzz()
				tapped.emit(k)
			_press = Vector2.INF
	elif e is InputEventMouseMotion and _press != Vector2.INF and e.position.distance_to(_press) >= 14:
		_press = Vector2.INF


func _draw() -> void:
	if k == "":
		return
	var c: Dictionary = DB.C[k]
	var tc := DB.tier_color(k)
	var w := size.x
	var h := size.y
	if w < 56:
		_draw_compact(c, tc, w, h)
		return
	var sb := StyleBoxFlat.new()
	sb.bg_color = DB.PAL.ink2
	sb.border_color = DB.PAL.gold if lit else tc.darkened(0.15)
	sb.set_border_width_all(2 if lit else 1)
	sb.border_width_top = 3
	sb.set_corner_radius_all(8)
	if lit:
		sb.shadow_color = Color(DB.PAL.gold, 0.35)
		sb.shadow_size = 4
	draw_style_box(sb, Rect2(Vector2.ZERO, size))
	var pr := Rect2(4, 5, w - 8, h - 27)
	Art.draw_portrait(self, pr, k)
	if c.tier > 2:
		draw_circle(pr.position + Vector2(8, 8), 7, DB.fac_color(c.fac))
		draw_string(DB.font_display, pr.position + Vector2(1, 12), c.fac, HORIZONTAL_ALIGNMENT_CENTER, 14, 9, Color.WHITE)
	var fd := DB.font_display
	var nm: String = c.name
	var fs := 13
	while fs > 9 and fd.get_string_size(nm, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > w - 6:
		fs -= 1
	draw_string(fd, Vector2(3, h - 8), nm, HORIZONTAL_ALIGNMENT_CENTER, w - 6, fs, tc.lightened(0.25) if c.tier >= 3 else DB.PAL.paper)
	if qty > 0:
		var s := "×%d" % qty
		var qw := DB.font_body.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x + 8
		var qr := Rect2(w - qw - 3, 4, qw, 16)
		var qb := StyleBoxFlat.new()
		qb.bg_color = Color(DB.PAL.gold, 0.92)
		qb.set_corner_radius_all(8)
		draw_style_box(qb, qr)
		draw_string(DB.font_body, qr.position + Vector2(0, 12), s, HORIZONTAL_ALIGNMENT_CENTER, qw, 11, Color("#1A1508"))
	if up:
		var ur := Rect2(w - 19, 22 if qty > 0 else 4, 16, 16)
		var ub := StyleBoxFlat.new()
		ub.bg_color = Color(DB.PAL.jade, 0.95)
		ub.set_corner_radius_all(8)
		draw_style_box(ub, ur)
		Icons.draw(self, "up", ur.get_center(), 14, Color.WHITE)
	if badge != "":
		var bw := DB.font_body.get_string_size(badge, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x + 10
		var br := Rect2(4, h - 41, bw, 17)
		var bb := StyleBoxFlat.new()
		bb.bg_color = badge_col if badge_col.a > 0 else Color(DB.PAL.ink, 0.85)
		bb.set_corner_radius_all(8)
		draw_style_box(bb, br)
		draw_string(DB.font_body, br.position + Vector2(0, 13), badge, HORIZONTAL_ALIGNMENT_CENTER, bw, 11, Color.WHITE)
	if dim:
		draw_rect(Rect2(Vector2.ZERO, size), Color(DB.PAL.ink, 0.5))


## 작은 칸 (폭 56 아래 —— 징집 화면 보유 패 8열, 11/2) —— 초상 · 짧은 이름 · 수량 · ▲ 만. 편성 중이면 왼쪽 아래 옥색 점
func _draw_compact(c: Dictionary, tc: Color, w: float, h: float) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = DB.PAL.ink2
	sb.border_color = DB.PAL.gold if lit else tc.darkened(0.1)
	sb.set_border_width_all(1)
	sb.border_width_top = 2
	sb.set_corner_radius_all(5)
	draw_style_box(sb, Rect2(Vector2.ZERO, size))
	var pr := Rect2(2, 3, w - 4, h - 17)
	Art.draw_portrait(self, pr, k)
	var fd := DB.font_display
	var nm: String = DB.person(k) if c.tier > 2 else c.name
	var fs := 10
	while fs > 7 and fd.get_string_size(nm, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > w - 2:
		fs -= 1
	draw_string(fd, Vector2(1, h - 4), nm, HORIZONTAL_ALIGNMENT_CENTER, w - 2, fs, tc.lightened(0.25) if c.tier >= 3 else DB.PAL.paper)
	if qty > 1:
		var s := "%d" % qty
		var qw := DB.font_body.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, 9).x + 6
		var qr := Rect2(w - qw - 1, 1, qw, 12)
		var qb := StyleBoxFlat.new()
		qb.bg_color = Color(DB.PAL.gold, 0.92)
		qb.set_corner_radius_all(6)
		draw_style_box(qb, qr)
		draw_string(DB.font_body, qr.position + Vector2(0, 10), s, HORIZONTAL_ALIGNMENT_CENTER, qw, 9, Color("#1A1508"))
	if up:
		var ur := Rect2(w - 13, 14 if qty > 1 else 1, 12, 12)
		var ub := StyleBoxFlat.new()
		ub.bg_color = Color(DB.PAL.jade, 0.95)
		ub.set_corner_radius_all(6)
		draw_style_box(ub, ur)
		Icons.draw(self, "up", ur.get_center(), 10, Color.WHITE)
	if badge != "":
		draw_circle(Vector2(6, h - 19), 4, Color(DB.PAL.jade, 0.95))
	if dim:
		draw_rect(Rect2(Vector2.ZERO, size), Color(DB.PAL.ink, 0.5))
