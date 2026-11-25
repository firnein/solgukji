class_name CardTile
extends Control
## 작은 카드 —— 손패·조합·선택권 목록에 쓴다. 왼쪽 초상(오른쪽 위 병종 기호), 등급색 띠, 등급색 이름, 특기 칸(이름+레벨).
## 등급은 이름 색과 띠로 알 수 있어 따로 적지 않는다. 병력 · PV 는 상세에서.
## 탭하면 tapped. drag_data 를 주면 길게 눌러(0.35초) 끌 수 있다 —— 짧게 끌면 목록이 스크롤된다.

signal tapped(k: String)

const SIZE := Vector2(160, 76)     # 11/7 사용자: 카드 축소 —— 특기 칸 두 줄(33 + 18×2 + 3)이 들어가는 최소 높이가 76
const HOLD := Press.HOLD_DRAG      # 11/20 조작: 꾹 눌러 끌기 시간은 Press 한 벌 (0.35)

var k := ""
var qty := -1
var note := ""              # 아래 줄 대신 쓸 짧은 글 (예: "선호 · 공격 +22%")
var note_col := Color.TRANSPARENT
var mark := ""              # "pref" · "bad" · "on" (편성 중) · "sel" (골랐다) · "dim"
var drag_data = null        # 있으면 길게 눌러 끌 수 있다
var _pr := Press.new()       # 11/20 조작: 누름 판정은 Press 한 벌 (탭 취소 10px · 범위 밖 떼기 무효)
var _dragging := false
var _down_fx := false        # 11/20 조작: 꾹 누르는 동안의 눌림 모양 (살짝 어둡게)
var _fx: MiniTile.PinFx = null   # 11/7 갈무리 표시 덧칸 (★ · 깜빡이는 테) —— MiniTile 과 같은 표현


func setup(id: String, n := -1, sz := SIZE) -> CardTile:
	k = id
	qty = n
	custom_minimum_size = sz
	size = sz
	mouse_filter = Control.MOUSE_FILTER_PASS
	return self


## 11/7 갈무리 표시 —— 12시 방향 노란 ★(star) · 테두리가 깜빡이는 금빛 하이라이트(ring). MiniTile.set_pin 과 같다
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
	match _pr.feed(self, e):
		Press.DOWN:
			_dragging = false
			set_process(drag_data != null)      # 꾹 누르기를 재는 동안만 (끝나면 _process 가 스스로 끈다)
		Press.TAP:
			_set_down(false)
			if not _dragging:
				if qty <= 0 and MiniTile.locked.has(k):
					MiniTile.deny(k)      # 11/25 잠긴 장수 —— MiniTile 과 같게 거절 + 까닭 알림
					return
				UI.buzz()      # 11/20 조작: 탭 소리 · 진동 (MiniTile 과 같게)
				tapped.emit(k)
		Press.CANCEL:
			_set_down(false)       # 끌었다 —— 스크롤에 맡긴다


## 11/20 조작: 눌림 모양 —— 꾹 누르는 동안 제 그림만 살짝 어둡게 (덧칸 ★ 은 그대로)
func _set_down(on: bool) -> void:
	if _down_fx != on:
		_down_fx = on
		self_modulate = Color(0.78, 0.78, 0.78) if on else Color.WHITE


## 11/15 성능 —— MiniTile 과 같다: _process 는 누르고 있는 동안만 · 화면 밖이면 그리지 않고 화면에 들어오면 그린다 (UI.off_screen)
var _skipped := false


func _ready() -> void:
	set_process(false)
	set_notify_transform(true)
	var vp := get_viewport()
	if vp != null and not vp.size_changed.is_connected(_wake):
		vp.size_changed.connect(_wake)


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSFORM_CHANGED and _skipped:
		_wake()


func _wake() -> void:
	if _skipped and is_inside_tree() and not UI.off_screen(self):
		_skipped = false
		queue_redraw()


func _process(_dt: float) -> void:
	if drag_data == null or not _pr.held() or _dragging:
		set_process(false)
		_set_down(false)
		return
	if not _down_fx and Time.get_ticks_msec() - _pr.t0 >= 70:      # 쓸기 시작의 짧은 누름에는 깜빡이지 않게
		_set_down(true)
	if _pr.long_due(Press.HOLD_DRAG):
		_dragging = true
		_pr.reset()
		_set_down(false)
		UI.buzz(15)      # 11/20 조작: 끌기 시작 진동은 편성판 칸과 같은 값
		var pv := CardTile.new().setup(k, -1)
		pv.modulate = Color(1, 1, 1, 0.85)
		var holder := Control.new()
		holder.add_child(pv)
		pv.position = Vector2(-SIZE.x / 2, -SIZE.y)      # 11/20 조작: 미리 보기를 손가락 위쪽으로 (가려지지 않게 반 칸 올림)
		force_drag(drag_data, holder)


func _draw() -> void:
	if k == "":
		return
	if UI.off_screen(self):
		_skipped = true
		return
	_skipped = false
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
		draw_string(DB.title_font(UI.FS_TINY), pr.position + Vector2(1, 13), c.fac, HORIZONTAL_ALIGNMENT_CENTER, 16, UI.FS_TINY, Color.WHITE)
	# 병종 기호 —— 초상 오른쪽 위
	var tcen := Vector2(pr.end.x - 8, pr.position.y + 8)
	draw_circle(tcen, 9.5, DB.kind_col(c.tag))      # 11/9 피해 종류 —— 병종 기호 테두리 (물리 주황 · 책략 파랑)
	draw_circle(tcen, 8.5, Color(DB.PAL.ink, 0.92))
	draw_texture_rect(DB.ICON[c.tag], Rect2(tcen - Vector2(5.5, 5.5), Vector2(11, 11)), false, DB.PAL.paper)
	draw_role_chip(self, k, Vector2(pr.position.x, pr.end.y - 15), UI.FS_TINY, pr.size.x, true)      # 11/19 장수 역할 칩 (11/20 fill: 초상 폭 전체)
	var x := pr.end.x + 7
	var tw := w - x - 6
	var fb := DB.font_body
	var fs := 18
	# 11/20 폴리싱: 수량이 각진 금색 네모에 숫자만("2") —— 작은 타일의 ×N 과 달랐고 두 자리 수는 23px 칸에 꽉 찼다. "×N" · 폭은 글자에 맞춤 · 모서리 R
	var qs := "×%d" % qty
	var qw := maxf(23.0, fb.get_string_size(qs, HORIZONTAL_ALIGNMENT_LEFT, -1, UI.FS_CAP).x + 8.0) if qty > 0 else 0.0
	while fs > 11 and DB.tier_font(c.tier, fs).get_string_size(c.name, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > tw - (qw + 3.0 if qty > 0 else 0.0):
		fs -= 1
	var fd := DB.tier_font(c.tier, fs)      # 11/10 줄어든 크기(18 미만)에서는 고급 · 희귀도 굵은 고딕
	draw_string(fd, Vector2(x, 25), c.name, HORIZONTAL_ALIGNMENT_LEFT, tw, fs, tc.lightened(0.15) if c.tier >= 3 else tc)
	if note != "":
		draw_string(fb, Vector2(x, h - 12), UI.ellipsize(fb, note, UI.FS_CAP, tw), HORIZONTAL_ALIGNMENT_LEFT, tw, UI.FS_CAP, note_col if note_col.a > 0 else DB.PAL.text_dim)
		draw_traits(self, k, Rect2(x, 33, tw, 18))
	else:
		draw_traits(self, k, Rect2(x, 33, tw, h - 37))
	if qty > 0:
		var qr := Rect2(w - 5 - qw, 5, qw, 19)
		draw_style_box(UI.flat(Color(DB.PAL.gold, 0.92), Color(0, 0, 0, 0), 0, UI.R, 0), qr)
		draw_string(fb, qr.position + Vector2(0, 14.5), qs, HORIZONTAL_ALIGNMENT_CENTER, qr.size.x, UI.FS_CAP, Color("#1A1508"))
	if mark == "dim":
		draw_rect(Rect2(Vector2.ZERO, size), Color(DB.PAL.ink, 0.55))
	var mk := MiniTile.mark_of(k, qty)      # 11/25 잠김(선점 · 사망) · 재료 선점 —— MiniTile 과 같은 회색 + 띠 (상세창 조합 줄)
	if not mk.is_empty():
		MiniTile.draw_mark(self, mk, Rect2(Vector2.ZERO, size))


## 특기 칸 —— 네모 안에 이름 + 레벨(금색), 먹색 (11/9 계열 색 걷음). 칸이 모자라면 마지막에 +n
## 11/20 폴리싱: ① +n 이 마지막 줄 끝 칸 위에 겹쳐 찍혔다("와룡" 위에 "+3") —— 마지막 줄에서는 +n 자리를 남기고, 모자라면 그 칸부터 +n 으로 넘긴다
## ② 고유 특기 칸은 금빛을 옅게 깐 면(탁한 황갈색)이라 눈에 띄지 않았다 —— 금 테 + 금 글자
static func draw_traits(ci: CanvasItem, id: String, r: Rect2, fs := UI.FS_CAP) -> void:
	var ts := DB.trait_list(id)
	var fb := DB.font_body
	var ch := fs + 6.0      # 11/14 글자 11 → FS_CAP(12): 칸 높이는 예전 그대로 18 (카드 높이 76 에 두 줄)
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
		var more_y := p.y - gap - 5.0      # +n 은 앞줄 끝에 (이 줄이 칸 밖일 때)
		var over := p.y + ch > r.end.y
		if not over and i < ts.size() - 1 and p.x > r.position.x and p.y + ch * 2.0 + gap > r.end.y:
			# 마지막 줄 —— 이 칸을 그리면 뒤에 +n 을 적을 자리가 없다 (그러면 다음 칸도 못 들어간다): 이 칸부터 +n
			var mw := fb.get_string_size("+%d" % (ts.size() - i - 1), HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			if p.x + cw + gap + mw > r.end.x:
				over = true
				more_y = p.y + ch - 5.0
		if over:
			var more := "+%d" % (ts.size() - i)
			var q := Vector2(r.end.x - fb.get_string_size(more, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x, more_y)
			ci.draw_string(fb, q, more, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, DB.PAL.bamboo)
			return
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(DB.PAL.gold, 0.16) if t.unique else DB.PAL.ink4      # 11/9 색 칩 → 먹색 면 (고유 특기만 금빛)
		if t.unique:
			sb.border_color = Color(DB.PAL.gold, 0.7)
			sb.set_border_width_all(1)
		sb.set_corner_radius_all(2)
		ci.draw_style_box(sb, Rect2(p, Vector2(cw, ch)))
		ci.draw_string(fb, p + Vector2(4, ch - 5), t.name, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, DB.PAL.gold.lightened(0.25) if t.unique else DB.PAL.paper)
		ci.draw_string(fb, p + Vector2(5 + nw, ch - 5), lvs, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, DB.PAL.gold)
		p.x += cw + gap


## 11/19 장수 역할 칩 (DB.role_chip) —— 갈래 색 칩에 기호 + 글 ("아군 보호"). p 는 칩 왼쪽 위, max_w 가 있으면 그 폭에 맞춘다
## 11/20 폴리싱: ① 좁은 타일에서 글씨가 8px 까지 줄어 읽기 어려웠다 —— 띄어쓰기를 빼고, 한 단계(9)까지만 줄이고, 그래도 넘치면 기호를 뗀다(갈래는 색으로 안다). 8 은 마지막 수단
## ② fill 이면 칩이 max_w 를 꽉 채우고 내용은 가운데 —— 작은 타일마다 칩 폭 · 높이가 달라 격자가 들쭉날쭉했다. 높이는 글씨가 줄어도 처음 크기 그대로
## ③ 모서리는 규칙 R (11/9 알약 금지)
static func draw_role_chip(ci: CanvasItem, id: String, p: Vector2, fs := 10, max_w := 0.0, fill := false) -> float:
	var rc := DB.role_chip(id)
	if rc.is_empty():
		return 0.0
	var fb := DB.font_bold
	var t: String = rc.t
	var ch := fs + 5.0
	var side := 1.5 if fill else 4.5      # 내용 양옆 여백 (fill 은 가운데 정렬이라 최소만)
	var gap := 2.0
	var icon := true
	var ic := float(fs)
	var tw := fb.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	if max_w > 0.0 and ic + gap + tw + side * 2.0 > max_w:
		t = t.replace(" ", "")
		var lo := maxi(8, fs - 1)
		var done := false
		for pass_icon in [true, false]:
			for f in range(fs, lo - 1, -1):
				tw = fb.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, f).x
				if (f + gap if pass_icon else 0.0) + tw + side * 2.0 <= max_w:
					fs = f
					icon = pass_icon
					done = true
					break
			if done:
				break
		if not done:      # 그래도 넘친다 —— 기호 없이 8
			fs = 8
			icon = false
			tw = fb.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		ic = float(fs)
	var inner := (ic + gap if icon else 0.0) + tw
	var cw := max_w if fill and max_w > 0.0 else inner + side * 2.0
	var col: Color = rc.col
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(col.darkened(0.25), 0.94)
	sb.border_color = Color(col.lightened(0.45), 0.9)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(mini(UI.R, int(ch * 0.5)))
	ci.draw_style_box(sb, Rect2(p, Vector2(cw, ch)))
	var x := p.x + (cw - inner) * 0.5
	var white := Color(1.0, 0.97, 0.9)
	if icon:
		var icc := Vector2(x + ic * 0.5, p.y + ch * 0.5)
		if str(rc.icon) == "plus":      # 회복 —— 굵은 십자
			var a := ic * 0.36
			var b := ic * 0.13
			ci.draw_rect(Rect2(icc - Vector2(a, b), Vector2(a * 2.0, b * 2.0)), white)
			ci.draw_rect(Rect2(icc - Vector2(b, a), Vector2(b * 2.0, a * 2.0)), white)
		else:
			Icons.draw(ci, str(rc.icon), icc, ic * 0.95, white)
		x += ic + gap
	ci.draw_string(fb, Vector2(x, p.y + ch * 0.5 + fs * 0.36), t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, white)
	return cw
