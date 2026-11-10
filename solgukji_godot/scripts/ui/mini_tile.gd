class_name MiniTile
extends Control
const TierDeco := preload("res://scripts/ui/tier_deco.gd")      # 11/10 class_name 캐시(.godot)와 무관하게 쓰려고 preload (캐시가 낡으면 "TierDeco not declared" 파스 오류)
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
var drag_data = null        # 있으면 길게 눌러(0.35초) 끌 수 있다 (편성 손패, 11/4)
var mark := ""              # "sel" —— 고른 카드 (금테)
var star := false           # 11/7 갈무리 표시 —— 12시 방향 노란 ★ (갈무리한 장수 · 그 재료)
var ring := false           # 11/7 갈무리 표시 —— 테두리가 빠르게 깜빡이는 금빛 하이라이트 (아직 더 모아야 하는 재료)
var _fx: PinFx = null       # ★ · 깜빡이는 테를 그리는 덧칸
var _held := 0.0
var _dragging := false


func setup(id: String, n := -1) -> MiniTile:
	k = id
	qty = n
	custom_minimum_size = Vector2(66, 96)      # 11/7 사용자: 카드 축소 (78×112 → 66×96, 한 줄 5장)
	mouse_filter = Control.MOUSE_FILTER_PASS
	# 11/9 신화 —— 지나가는 빛줄기 덧칸 (초상 칸 위로. 폭이 56 미만이면 작은 칸의 초상 위치)
	TierDeco.attach_shimmer(self, id, func(sz: Vector2) -> Rect2:
		return Rect2(4, 5, sz.x - 8, sz.y - 27) if sz.x >= 56.0 else Rect2(2, 3, sz.x - 4, sz.y - 17))
	return self


## 11/7 사용자: '갈무리된 재료' 표현 통일 —— 창마다 다르던 금색 · 옥빛 테두리 · "갈무리" 뱃지 대신 카드 12시 방향 노란 ★ 과
## 테두리가 깜빡이는 금빛 하이라이트. 그리기는 작은 덧칸(PinFx)이 맡아 타일 본체(초상)는 매 프레임 다시 그리지 않는다
func set_pin(s: bool, r: bool) -> void:
	star = s
	ring = r
	queue_redraw()      # 11/9 ★ 이 있으면 등급 장식의 윗변 가운데를 비운다
	if not s and not r:
		if _fx != null:
			_fx.queue_free()
			_fx = null
		return
	if _fx == null:
		_fx = PinFx.new()
		add_child(_fx)
	_fx.setup(s, r)


## 갈무리 덧칸 —— 타일 위에 얹혀 ★ 과 깜빡이는 테두리만 그린다. 많은 칸에 얹혀도 가볍게: 점 29개짜리 선 하나 + 별 하나
class PinFx extends Control:
	const BLINK_SEC := 0.6      # 깜빡임 한 주기(초) —— 11/9 사용자: 도는 빛(한 바퀴 10초) 대신 빠른 깜빡임
	const STAR_COL := Color("#FFD94A")
	var star := true
	var ring := true
	var col: Color = DB.PAL.gold
	var _t := 0.0

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	func setup(s: bool, r: bool) -> void:
		star = s
		ring = r
		set_process(r)
		queue_redraw()

	func _process(dt: float) -> void:
		if not is_visible_in_tree():
			return
		_t += dt
		queue_redraw()

	func _draw() -> void:
		var w := size.x
		var h := size.y
		if w < 2.0 or h < 2.0:
			return
		if ring:
			# 11/9 사용자: 도는 빛 대신 빠르게 깜빡이는 금빛 테두리 —— 한 주기 약 0.6초, 진했다(밝은 금빛 · 굵게) 옅어졌다
			var inset := 1.5
			var rad := maxf(1.0, (8.0 if w >= 56.0 else 5.0) - inset)      # 타일의 모서리 반지름(8 · 작은 칸 5)에 맞춘다
			var rect := Rect2(inset, inset, w - inset * 2.0, h - inset * 2.0)
			var corners := [Vector2(rect.end.x - rad, rect.position.y + rad), Vector2(rect.end.x - rad, rect.end.y - rad),
				Vector2(rect.position.x + rad, rect.end.y - rad), Vector2(rect.position.x + rad, rect.position.y + rad)]
			var pts := PackedVector2Array()
			for ci in 4:
				var a0 := -PI / 2.0 + ci * PI / 2.0
				for j in 7:
					pts.append(corners[ci] + Vector2.from_angle(a0 + j * (PI / 2.0) / 6.0) * rad)
			pts.append(pts[0])
			var b := 0.5 - 0.5 * cos(_t * TAU / BLINK_SEC)      # 0 ~ 1
			draw_polyline(pts, Color(col.lightened(0.4 * b), 0.12 + 0.88 * b), 2.0 + 1.5 * b, true)
		if star:
			# 12시 방향 노란 별 —— 테두리 위에 걸치게, 어두운 윤곽선
			var c := Vector2(w / 2.0, 1.0)
			var sp := PackedVector2Array()
			for i in 10:
				sp.append(c + Vector2.from_angle(-PI / 2.0 + i * PI / 5.0) * (7.0 if i % 2 == 0 else 3.0))
			draw_colored_polygon(sp, STAR_COL)
			sp.append(sp[0])
			draw_polyline(sp, Color("#4A3608"), 1.2, true)


func _gui_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
		if e.pressed:
			_press = e.position
			_held = 0.0
			_dragging = false
		else:
			if _press != Vector2.INF and not _dragging and e.position.distance_to(_press) < 14:
				UI.buzz()
				tapped.emit(k)
			_press = Vector2.INF
	elif e is InputEventMouseMotion and _press != Vector2.INF and e.position.distance_to(_press) >= 14:
		_press = Vector2.INF


func _process(dt: float) -> void:
	if drag_data == null or _press == Vector2.INF or _dragging:
		return
	_held += dt
	if _held >= CardTile.HOLD:
		_dragging = true
		_press = Vector2.INF
		var pv := MiniTile.new().setup(k, -1)
		pv.size = size
		pv.modulate = Color(1, 1, 1, 0.85)
		var holder := Control.new()
		holder.add_child(pv)
		pv.position = -size / 2
		force_drag(drag_data, holder)


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
	var rk := TierDeco.rank(k)      # 11/9 기인 · 초월 · 불멸 · 신화 —— 등급 장식 (TierDeco)
	var sb := StyleBoxFlat.new()
	sb.bg_color = DB.PAL.ink2
	var on := lit or mark == "sel"
	sb.border_color = DB.PAL.gold if on else (tc if rk != TierDeco.NONE else tc.darkened(0.15))
	var bwv := 2 if (on or rk >= TierDeco.CHO) else 1
	sb.set_border_width_all(bwv)
	sb.border_width_top = 3
	sb.set_corner_radius_all(8)
	if on:
		sb.shadow_color = Color(DB.PAL.gold, 0.35)
		sb.shadow_size = 4
	draw_style_box(sb, Rect2(Vector2.ZERO, size))
	var pr := Rect2(4, 5, w - 8, h - 27)
	Art.draw_portrait(self, pr, k)
	if rk != TierDeco.NONE:
		TierDeco.draw(self, Rect2(Vector2.ZERO, size), k, TierDeco.MINI, 8.0, float(bwv), 1.0, not star)
	if c.tier > 2:
		draw_circle(pr.position + Vector2(8, 8), 7, DB.fac_color(c.fac))
		draw_string(DB.title_font(9), pr.position + Vector2(1, 12), c.fac, HORIZONTAL_ALIGNMENT_CENTER, 14, 9, Color.WHITE)
	_tag_icon(c, pr.end - Vector2(10, 10), 8.0)      # 11/6 사용자: 그림에 병종 심볼
	CardTile.draw_role_chip(self, k, Vector2(pr.position.x + 2, pr.end.y - 15), 10)      # 11/9 대표 역할 칩
	var fd := DB.tier_font(c.tier, 13)
	var nm: String = c.name
	var fs := 13
	while fs > 9 and fd.get_string_size(nm, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > w - 6:
		fs -= 1
	draw_string(fd, Vector2(3, h - 8), nm, HORIZONTAL_ALIGNMENT_CENTER, w - 6, fs, tc.lightened(0.15) if c.tier >= 3 else tc)
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
## 병종 심볼 —— 그림 오른쪽 아래 먹색 원 안에 (11/6 사용자)
func _tag_icon(c: Dictionary, p: Vector2, r: float) -> void:
	var ic: Texture2D = DB.ICON.get(c.tag)
	if ic == null:
		return
	draw_circle(p, r + 1.5, DB.kind_col(c.tag))      # 11/9 피해 종류 —— 테두리 색 (물리 주황 · 책략 파랑)
	draw_circle(p, r, Color(DB.PAL.ink, 0.92))
	var s := r * 1.5
	draw_texture_rect(ic, Rect2(p - Vector2(s, s) / 2.0, Vector2(s, s)), false, DB.PAL.paper)


func _draw_compact(c: Dictionary, tc: Color, w: float, h: float) -> void:
	var rk := TierDeco.rank(k)
	var sb := StyleBoxFlat.new()
	sb.bg_color = DB.PAL.ink2
	sb.border_color = DB.PAL.gold if lit else (tc if rk != TierDeco.NONE else tc.darkened(0.1))
	sb.set_border_width_all(1)
	sb.border_width_top = 2
	sb.set_corner_radius_all(5)
	draw_style_box(sb, Rect2(Vector2.ZERO, size))
	var pr := Rect2(2, 3, w - 4, h - 17)
	Art.draw_portrait(self, pr, k)
	if rk != TierDeco.NONE:
		TierDeco.draw(self, Rect2(Vector2.ZERO, size), k, TierDeco.TINY, 5.0, 1.0, 1.0, not star)
	_tag_icon(c, pr.end - Vector2(7, 7), 6.0)
	var fd := DB.tier_font(c.tier, 10)
	# 11/3 사용자: 칭호를 떼고 "손권" 만 보이면 다른 카드(벽안 손권)로 오해한다 —— 칭호까지 보이고, 안 들어가면 칭호를 이름 위 작은 줄로
	var nm: String = c.name
	var nc := tc.lightened(0.15) if c.tier >= 3 else tc
	var fs := 10
	while fs > 8 and fd.get_string_size(nm, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > w - 2:
		fs -= 1
	if c.tier > 2 and nm.contains(" ") and fd.get_string_size(nm, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > w - 2:
		var per := DB.person(k)
		var title := nm.substr(0, nm.length() - per.length()).strip_edges()
		var ts := 8
		while ts > 6 and DB.font_body.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, ts).x > w - 2:
			ts -= 1
		draw_rect(Rect2(1, h - 25, w - 2, 10), Color(DB.PAL.ink2, 0.8))
		draw_string(DB.font_body, Vector2(1, h - 17), title, HORIZONTAL_ALIGNMENT_CENTER, w - 2, ts, Color(nc, 0.85))
		nm = per
		fs = 10
		while fs > 7 and fd.get_string_size(nm, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > w - 2:
			fs -= 1
	draw_string(fd, Vector2(1, h - 4), nm, HORIZONTAL_ALIGNMENT_CENTER, w - 2, fs, nc)
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
