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
var ghost := false          # 유령 카드 —— 아직 없는 조합 결과 (점선 테두리 · 반투명 초상 · 오른쪽 위 +). 징집 화면 보유 격자에 재료 옆으로 끼운다 (11/2)
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
	if ghost:
		_draw_ghost(c, tc, w, h)
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


## 유령 카드 —— 없는 카드라는 걸 한눈에: 바탕 없이 점선 테두리, 초상은 옅게, 이름 앞에 +.
## 지금 조합되면(lit) 금빛 점선 + 아래 「조합」 알약, 아니면 「-N」 알약
func _draw_ghost(c: Dictionary, tc: Color, w: float, h: float) -> void:
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(DB.PAL.ink2, 0.35)
	bg.set_corner_radius_all(8)
	if lit:
		bg.shadow_color = Color(DB.PAL.gold, 0.25)
		bg.shadow_size = 5
	draw_style_box(bg, Rect2(Vector2.ZERO, size))
	var pr := Rect2(4, 5, w - 8, h - 27)
	Art.draw_portrait(self, pr, k)
	draw_rect(pr, Color(DB.PAL.ink, 0.25 if lit else 0.55))
	var lc: Color = DB.PAL.gold if lit else Color(tc, 0.75)
	var r := Rect2(1, 1, w - 2, h - 2)
	for seg in [[r.position, Vector2(r.end.x, r.position.y)], [Vector2(r.end.x, r.position.y), r.end],
			[r.end, Vector2(r.position.x, r.end.y)], [Vector2(r.position.x, r.end.y), r.position]]:
		draw_dashed_line(seg[0], seg[1], lc, 2.0 if lit else 1.5, 6.0)
	var fd := DB.font_display
	var nm: String = "+ " + c.name
	var fs := 13
	while fs > 9 and fd.get_string_size(nm, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > w - 6:
		fs -= 1
	draw_string(fd, Vector2(3, h - 8), nm, HORIZONTAL_ALIGNMENT_CENTER, w - 6, fs, Color(tc.lightened(0.25), 0.9) if c.tier >= 3 else Color(DB.PAL.paper, 0.8))
	if badge != "":
		var bw := DB.font_body.get_string_size(badge, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x + 12
		var br := Rect2((w - bw) / 2, h - 46, bw, 18)
		var bb := StyleBoxFlat.new()
		bb.bg_color = badge_col if badge_col.a > 0 else Color(DB.PAL.ink, 0.85)
		bb.set_corner_radius_all(9)
		draw_style_box(bb, br)
		draw_string(DB.font_body, br.position + Vector2(0, 13), badge, HORIZONTAL_ALIGNMENT_CENTER, bw, 11, Color.WHITE)
