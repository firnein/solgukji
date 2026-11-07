class_name CardTile
extends Control
## 작은 카드 —— 손패·조합·선택권 목록에 쓴다. 왼쪽 초상(오른쪽 위 병종 기호), 등급색 띠, 등급색 이름, 특기 칸(이름+레벨).
## 등급은 이름 색과 띠로 알 수 있어 따로 적지 않는다. 병력 · PV 는 상세에서.
## 탭하면 tapped. drag_data 를 주면 길게 눌러(0.35초) 끌 수 있다 —— 짧게 끌면 목록이 스크롤된다.

signal tapped(k: String)

const SIZE := Vector2(168, 78)
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
var _fx: MiniTile.PinFx = null   # 11/7 갈무리 표시 덧칸 (★ · 도는 테) —— MiniTile 과 같은 표현


func setup(id: String, n := -1, sz := SIZE) -> CardTile:
	k = id
	qty = n
	custom_minimum_size = sz
	size = sz
	mouse_filter = Control.MOUSE_FILTER_PASS
	return self


## 11/7 갈무리 표시 —— 12시 방향 노란 ★(star) · 테두리를 도는 금빛 하이라이트(ring). MiniTile.set_pin 과 같다
func set_pin(s: bool, r: bool) -> void:
	if not s and not r:
		if _fx != null:
			_fx.queue_free()
			_fx = null
		return
	if _fx == null:
		_fx = MiniTile.PinFx.new()
		add_child(_fx)
	_fx.setup(s, r)


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
	# 병종 기호 —— 초상 오른쪽 위
	var tcen := Vector2(pr.end.x - 8, pr.position.y + 8)
	draw_circle(tcen, 8.5, Color(DB.PAL.ink, 0.85))
	draw_texture_rect(DB.ICON[c.tag], Rect2(tcen - Vector2(5.5, 5.5), Vector2(11, 11)), false, DB.PAL.paper)
	var x := pr.end.x + 7
	var tw := w - x - 6
	var fd := DB.tier_font(c.tier)
	var fb := DB.font_body
	var fs := 18
	while fs > 11 and fd.get_string_size(c.name, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > tw - (26 if qty > 0 else 0):
		fs -= 1
	draw_string(fd, Vector2(x, 25), c.name, HORIZONTAL_ALIGNMENT_LEFT, tw, fs, tc.lightened(0.15) if c.tier >= 3 else tc)
	if note != "":
		draw_string(fb, Vector2(x, h - 12), note, HORIZONTAL_ALIGNMENT_LEFT, tw, 11, note_col if note_col.a > 0 else DB.PAL.bamboo_dim)
		draw_traits(self, k, Rect2(x, 33, tw, 18))
	else:
		draw_traits(self, k, Rect2(x, 33, tw, h - 37))
	if qty > 0:
		var qr := Rect2(w - 28, 5, 23, 19)
		draw_rect(qr, Color(DB.PAL.gold, 0.9))
		draw_string(fb, qr.position + Vector2(0, 15), str(qty), HORIZONTAL_ALIGNMENT_CENTER, qr.size.x, 13, Color("#1A1508"))
	if mark == "dim":
		draw_rect(Rect2(Vector2.ZERO, size), Color(DB.PAL.ink, 0.55))


## 특기 칸 —— 네모 안에 이름 + 레벨(금색), 계열 색(DB.trait_col). 칸이 모자라면 마지막에 +n
static func draw_traits(ci: CanvasItem, id: String, r: Rect2, fs := 11) -> void:
	var ts := DB.trait_list(id)
	var fb := DB.font_body
	var ch := fs + 7.0
	var gap := 3.0
	var p := r.position
	for i in ts.size():
		var t: Dictionary = ts[i]
		var lvs := "" if t.unique else str(t.lv)       # 11/3 사용자: 고유 특기에는 레벨을 적지 않는다
		var nw := fb.get_string_size(t.name, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var lw := fb.get_string_size(lvs, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var cw := nw + lw + 9
		if p.x + cw > r.end.x and p.x > r.position.x:
			p = Vector2(r.position.x, p.y + ch + gap)
		if p.y + ch > r.end.y:
			var more := "+%d" % (ts.size() - i)
			var q := Vector2(r.end.x - fb.get_string_size(more, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x, p.y - gap - 5)
			ci.draw_string(fb, q, more, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, DB.PAL.bamboo)
			return
		var sb := StyleBoxFlat.new()
		var tc := DB.trait_col(t)
		sb.bg_color = Color("#6b5212") if t.unique else tc.darkened(0.55)
		sb.border_color = Color("#e8c25a") if t.unique else tc
		sb.set_border_width_all(1)
		sb.set_corner_radius_all(3)
		ci.draw_style_box(sb, Rect2(p, Vector2(cw, ch)))
		ci.draw_string(fb, p + Vector2(4, ch - 5), t.name, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, DB.PAL.paper)
		ci.draw_string(fb, p + Vector2(5 + nw, ch - 5), lvs, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, DB.PAL.gold)
		p.x += cw + gap
