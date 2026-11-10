class_name CardView
extends Control
const TierDeco := preload("res://scripts/ui/tier_deco.gd")      # 11/10 class_name 캐시(.godot)와 무관하게 쓰려고 preload (캐시가 낡으면 "TierDeco not declared" 파스 오류)
## 카드 한 장 —— 등급별 테두리, 세력 배지, 병종 아이콘, 초상, 칭호·이름 두 줄. (등급·병력·PV 는 테두리와 상세 정보로 안다)
## 기인 · 초월 · 불멸 · 신화는 등급 장식(TierDeco)이 붙고, 신화는 빛줄기가 지나간다 (11/9 —— 움직이는 것은 Shimmer 덧칸 하나, 카드 본체는 다시 그리지 않는다).

signal picked(k: String)

var k := ""
var selected := false:
	set(v):
		selected = v
		queue_redraw()
var _hover := false


func setup(id: String, sz := Vector2(150, 214)) -> CardView:
	k = id
	custom_minimum_size = sz
	size = sz
	pivot_offset = sz / 2
	mouse_filter = Control.MOUSE_FILTER_STOP
	TierDeco.attach_shimmer(self, k, _portrait_rect, true)
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


## 초상 칸 (이름 두 줄 자리만 빼고 카드를 채운다) —— _draw 와 빛줄기 덧칸이 같이 쓴다
func _portrait_rect(sz: Vector2) -> Rect2:
	var u := sz.x / 150.0
	var m := _frame_w(DB.C[k].tier) * u + 3 * u
	return Rect2(m, m, sz.x - m * 2, sz.y - m - 44.0 * u)


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
	if tier >= 6 or selected or _hover or DB.is_kiin(k):
		sb.shadow_color = Color(DB.PAL.gold if selected else tc, 0.3 + (0.15 if tier >= 8 else 0.1) + (0.1 if tier >= 7 else 0.0))
		sb.shadow_size = int((5 + (tier - 5) * 2 + (2 if tier >= 8 else 0)) * u)
	draw_style_box(sb, Rect2(Vector2.ZERO, size))

	# 초상 —— 이름 두 줄 자리만 빼고 카드를 채운다
	var m := fw + 3 * u
	var pr := _portrait_rect(size)
	var panel := DB.portrait_panel(k)
	if not panel:
		Art.draw_portrait(self, pr, k)
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
	Art.draw_tier_fx(self, pr, k)

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
## 고급: 테만 · 희귀: 안쪽 가는 선 · 전설: + 네 귀 네모 · 기인 · 초월 · 불멸 · 신화: 등급 장식 (TierDeco —— 규칙은 거기)
func _frame(tier: int, tc: Color, u: float) -> void:
	var fw := _frame_w(tier) * u
	var r := Rect2(Vector2.ZERO, size)
	var rk := TierDeco.rank(k)
	var main := DB.PAL.gold if selected else (tc if tier > 2 else DB.PAL.ink3.lightened(0.25))
	var sb := StyleBoxFlat.new()
	sb.draw_center = false
	sb.border_color = main
	sb.set_border_width_all(int(ceil(fw)))
	sb.set_corner_radius_all(int(8 * u))
	draw_style_box(sb, r)
	if rk != TierDeco.NONE:
		TierDeco.draw(self, r, k, TierDeco.FULL, 8.0 * u, ceilf(fw), u, true)
		return
	if tier >= 4:
		var inner := StyleBoxFlat.new()
		inner.draw_center = false
		inner.border_color = Color(tc.lightened(0.3), 0.35)
		inner.set_border_width_all(maxi(1, int(u)))
		inner.set_corner_radius_all(int(5 * u))
		draw_style_box(inner, r.grow(-(fw + u)))
	if tier == 5:
		var q := 3.5 * u
		for cx in [fw + 3 * u, size.x - fw - 3 * u]:
			for cy in [fw + 3 * u, size.y - fw - 3 * u]:
				draw_rect(Rect2(Vector2(cx, cy) - Vector2(q, q) / 2, Vector2(q, q)), tc.lightened(0.3))
