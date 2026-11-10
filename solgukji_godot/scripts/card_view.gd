class_name CardView
extends Control
## 카드 한 장 —— 등급별 테두리, 세력 배지, 병종 아이콘, 초상, 칭호·이름 두 줄. (등급·병력·PV 는 테두리와 상세 정보로 안다)
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
	var tier: int = c.tier
	var tc := DB.tier_color(k)
	var w := size.x
	var h := size.y
	var u := w / 150.0      # 크기에 비례해 글자와 여백을 키운다
	var fw := _frame_w(tier) * u

	# 바탕 —— 등급색을 아래로 옅게 깐다
	var sb := StyleBoxFlat.new()
	sb.bg_color = DB.PAL.ink2.lerp(tc, 0.10 if tier >= 6 else 0.04)
	sb.set_corner_radius_all(int(8 * u))
	if tier >= 6 or selected or _hover:
		var pulse := 0.5 + 0.5 * sin(_t * 2.2)
		sb.shadow_color = Color(DB.PAL.gold if selected else tc, 0.3 + (0.3 * pulse if tier >= 8 else 0.1) + (0.1 if tier >= 7 else 0.0))
		sb.shadow_size = int((5 + (tier - 5) * 2 + (4 * pulse if tier >= 8 else 0)) * u)
	draw_style_box(sb, Rect2(Vector2.ZERO, size))

	# 초상 —— 이름 두 줄 자리만 빼고 카드를 채운다
	var m := fw + 3 * u
	var name_h := 44.0 * u
	var pr := Rect2(m, m, w - m * 2, h - m - name_h)
	var panel := DB.portrait_panel(k)
	if not panel:
		Art.draw_portrait(self, pr, k, _t)
	else:
		draw_rect(pr, DB.fac_color(c.fac).darkened(0.62))
	# 이름 칸 쪽으로 초상이 스며들게
	var fade := 22.0 * u
	draw_polygon(PackedVector2Array([Vector2(pr.position.x, pr.end.y - fade), Vector2(pr.end.x, pr.end.y - fade), pr.end, Vector2(pr.position.x, pr.end.y)]),
		PackedColorArray([Color(DB.PAL.ink2, 0), Color(DB.PAL.ink2, 0), Color(DB.PAL.ink2, 0.9), Color(DB.PAL.ink2, 0.9)]))

	_frame(tier, tc, u)
	# 큰 그림(패널)은 테두리 위 레이어로 —— 깃·무기가 카드 위로 솟는다
	if panel:
		Art.draw_panel_pop(self, pr, k, 34 * u)
		draw_polygon(PackedVector2Array([Vector2(pr.position.x, pr.end.y - fade), Vector2(pr.end.x, pr.end.y - fade), pr.end, Vector2(pr.position.x, pr.end.y)]),
			PackedColorArray([Color(DB.PAL.ink2, 0), Color(DB.PAL.ink2, 0), Color(DB.PAL.ink2, 0.9), Color(DB.PAL.ink2, 0.9)]))
	Art.draw_tier_fx(self, pr, k, _t)

	var fb := DB.font_body
	var fd := DB.font_display
	# 세력 배지 · 병종 아이콘
	var br := 10.5 * u
	if tier > 2:
		var bp := pr.position + Vector2(br + 3 * u, br + 3 * u)
		draw_circle(bp, br, DB.fac_color(c.fac))
		draw_string(fd, bp + Vector2(-br, 4.5 * u), c.fac, HORIZONTAL_ALIGNMENT_CENTER, br * 2, int(12 * u), Color.WHITE)
	var ip := Vector2(pr.end.x - br - 3 * u, pr.position.y + br + 3 * u)
	draw_circle(ip, br, Color(DB.PAL.ink, 0.78))
	draw_texture_rect(DB.ICON[c.tag], Rect2(ip - Vector2(7, 7) * u, Vector2(14, 14) * u), false, DB.PAL.paper)

	# 이름 —— 칭호와 이름을 두 줄로 (백마장군 / 공손찬). 길면 글자를 줄인다
	var nm: String = c.name
	var title := ""
	var sp := nm.rfind(" ")
	if sp > 0:
		title = nm.substr(0, sp)
		nm = nm.substr(sp + 1)
	var col: Color = tc.lightened(0.15) if tier >= 6 else DB.PAL.paper
	var tw := w - m * 2
	var y := h - fw - 9 * u
	var nf := DB.tier_font(tier)
	draw_string(nf, Vector2(m, y), nm, HORIZONTAL_ALIGNMENT_CENTER, tw, _fit(nf, nm, int(18 * u), tw), col)
	if title != "":
		draw_string(fb, Vector2(m, y - 19 * u), title, HORIZONTAL_ALIGNMENT_CENTER, tw, _fit(fb, title, int(12 * u), tw), Color(col, 0.8))


func _fit(f: Font, s: String, fs: int, wmax: float) -> int:
	while fs > 8 and f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > wmax:
		fs -= 1
	return fs


## 등급별 테두리 두께 —— 일반 2 · 고급~전설 3 · 초월 4 · 불멸 5 · 신화 6
func _frame_w(tier: int) -> float:
	return 2.0 if tier <= 2 else (3.0 if tier <= 5 else float(tier - 2))


## 등급 테두리 —— 테두리만 보고 등급을 알 수 있게 단계마다 장식을 더한다
## 고급: 테만 · 희귀: 안쪽 가는 선 · 전설: + 네 귀 네모 · 초월: 굵은 꺾쇠 + 빛 · 불멸: 겹테 + 귀 마름모 · 신화: 금테 + 위쪽 문장 + 테를 도는 빛
func _frame(tier: int, tc: Color, u: float) -> void:
	var fw := _frame_w(tier) * u
	var r := Rect2(Vector2.ZERO, size)
	var main := DB.PAL.gold if selected else (tc if tier > 2 else DB.PAL.ink3.lightened(0.25))
	var sb := StyleBoxFlat.new()
	sb.draw_center = false
	sb.border_color = main
	sb.set_border_width_all(int(ceil(fw)))
	sb.set_corner_radius_all(int(8 * u))
	draw_style_box(sb, r)
	if tier >= 4:
		var inner := StyleBoxFlat.new()
		inner.draw_center = false
		inner.border_color = Color(tc.lightened(0.3), 0.55 if tier >= 7 else 0.35)
		inner.set_border_width_all(maxi(1, int(u * (1.5 if tier >= 7 else 1.0))))
		inner.set_corner_radius_all(int(5 * u))
		var g := fw + (2.5 if tier >= 7 else 1.0) * u
		draw_style_box(inner, r.grow(-g))
	if tier == 5:
		var q := 3.5 * u
		for cx in [fw + 3 * u, size.x - fw - 3 * u]:
			for cy in [fw + 3 * u, size.y - fw - 3 * u]:
				draw_rect(Rect2(Vector2(cx, cy) - Vector2(q, q) / 2, Vector2(q, q)), tc.lightened(0.3))
	if tier >= 6:
		# 네 귀 꺾쇠 —— 테 안쪽에 굵게
		var L := (16.0 + (tier - 6) * 5.0) * u
		var o := fw * 0.5
		var lc := Color.WHITE.lerp(tc, 0.35)
		var lw := maxf(2.0, 3.0 * u)
		for cx in [o, size.x - o]:
			for cy in [o, size.y - o]:
				var sx := 1.0 if cx < size.x / 2 else -1.0
				var sy := 1.0 if cy < size.y / 2 else -1.0
				var p := Vector2(cx, cy) + Vector2(sx, sy) * (fw * 0.5 + 3 * u)
				draw_line(p, p + Vector2(sx * L, 0), lc, lw)
				draw_line(p, p + Vector2(0, sy * L), lc, lw)
				if tier >= 7:
					var d := 4.0 * u
					var q := Vector2(cx, cy)
					draw_colored_polygon(PackedVector2Array([q + Vector2(0, -d), q + Vector2(d, 0), q + Vector2(0, d), q + Vector2(-d, 0)]), lc)
	if tier >= 8:
		# 위쪽 가운데 문장 —— 금 마름모 + 보석
		var cpos := Vector2(size.x / 2, fw * 0.5)
		var d := 7.0 * u
		draw_colored_polygon(PackedVector2Array([cpos + Vector2(0, -d), cpos + Vector2(d * 1.6, 0), cpos + Vector2(0, d), cpos + Vector2(-d * 1.6, 0)]), tc)
		draw_circle(cpos, 2.6 * u, Color("#ff5a4a"))
		# 테를 따라 도는 빛
		var per := (size.x + size.y) * 2.0
		var pos := fmod(_t * 120.0 * u, per)
		var pt := _along(pos, fw * 0.5)
		draw_circle(pt, 3.2 * u, Color(1, 0.97, 0.85, 0.9))
		draw_circle(pt, 6.0 * u, Color(1, 0.9, 0.6, 0.3))


## 테두리를 따라 거리 d 만큼 간 점 (왼쪽 위에서 시계 방향)
func _along(d: float, o: float) -> Vector2:
	var w := size.x - o * 2
	var h := size.y - o * 2
	if d < w:
		return Vector2(o + d, o)
	d -= w
	if d < h:
		return Vector2(o + w, o + d)
	d -= h
	if d < w:
		return Vector2(o + w - d, o + h)
	d -= w
	return Vector2(o, o + h - minf(d, h))
