extends VBoxContainer
## 전투장수창 (11/21 폴리싱) —— 전투 중 메달을 꾹 눌러 연다 (GameScreen.battle_unit_sheet 가 시트 본문에 이것 하나를 넣는다).
## 사용자: "전투시 꾹 눌러서 나오는 장수정보창도 폴리싱" · "전투 시에만 일어나는 사건들을 추가 (조합법 같은 건 빼고)" ·
## "갈무리창 · 상세창 · 전투 장수창은 톤앤매너가 일치" · "우와 신경 많이 썼구나".
##
## 위에서부터 '지금 상황'이 먼저 —— ① 상황판(초상 · 병력 · 사기 · 고유기 기와 남은 시간 · 걸린 상태) ② 이번 전투 기여(준 피해 · 격파 · 치료 · 받은 피해)
## ③ 전장의 개성(고유 특기 개성 문장 · 이번 전투에서 발동한 횟수) ④ 전투 기록(이 장수에게 일어난 사건 타임라인) —— 그 아래에 장수 정보(능력치 · 장비 · 고유기 · 기술 · 특기).
##
## 갱신: 열어 둔 채 전투가 흐르면 REFRESH 초마다 값만 바꾼다 (글자 · 막대 다시 그리기). 노드는 처음에 한 번 만들고,
## 상태 칩은 걸린 상태가 바뀔 때 · 기록 줄은 새 사건이 들 때만 다시 만든다. 사건은 전투 기록(res.ev)을 화면이 반영한 곳(BattleView.live_i)까지
## 이어서 훑는다 (처음 열 때 한 번 처음부터). 시트가 숨으면(닫힘) 아무것도 하지 않는다. 전투가 끝나면 마지막 값(결과 명단의 합계)으로 멈춘다.
##
## 모양은 디테일창 능력 카드(1.1j · 1.1k: 옅은 먹 바탕 + 왼쪽 색 띠, 주인공 카드는 색 그라데이션 · 빗금 · 큰 기호)와 같은 말을 쓴다.
## 색 · 글자 크기 · 패널 질감 · 칩 그리기는 아래 「스타일」 칸에만 모았다 —— 공통 시각 언어(SheetStyle)가 들어오면 이 칸만 바꿔 끼운다.

# ───────── 스타일 (합친 뒤 SheetStyle 로 바꿔 끼울 자리) ─────────

const C_VAL := Color("#8FD4C2")        # 수치 글자 (디테일창 ABIL_VAL · _hl 과 같은 옥색)
const C_GOOD := Color("#7fe0a8")       # 늘어난 값
const C_BAD := Color("#ff7a6a")        # 깎인 값 · 크게 맞음
const C_ULT := Color("#ffd257")        # 고유기 · 개성 발동 (전장 머리 위 글씨와 같은 금)
const C_KILL := Color("#ff9b5a")       # 격파
const C_HEAL := Color("#7fd6a4")       # 치료 (전장 치료 글씨와 같은 초록)
const C_SIG := Color("#e9c27a")        # 전장의 개성
const TROOP_COL := {"A": [Color("#6fa8ff"), Color("#2f5fb8")], "B": [Color("#ff8a72"), Color("#b5382c")]}      # 병력 막대 (위 띠 병력 막대와 같은 진영색)
const ULT_BAR := [Color("#ffe08a"), Color("#b8801f")]
## 고유기 계열(ultimates.json vfx) → 카드 색 · 바탕 기호 —— 디테일창(GameScreen.ULT_COL · ULT_ICON)과 같은 값
const ULT_COL := {"firestorm": Color("#F08A3C"), "thunder": Color("#6FA8F0"), "poison": Color("#8CC455"), "heal": Color("#5FC9A8"),
	"shadow": Color("#A183E0"), "illusion": Color("#D08AE0"), "aura": Color("#E3B454"), "charge": Color("#E8694F"), "slash": Color("#E06A5A"),
	"arrowstorm": Color("#D8C078"), "roar": Color("#F0A848"), "whirlwind": Color("#5EC4CC")}
const ULT_ICON := {"firestorm": "flame", "heal": "heart", "charge": "blade", "slash": "blade", "arrowstorm": "target", "aura": "banner",
	"illusion": "swirl", "whirlwind": "swirl"}
const ST_ICON := {"phalanx": "shield", "moved": "up", "seal": "seal", "plague": "swirl", "bleed": "flame"}      # 전장 딱지에 그림이 없는 상태의 기호
const CLS_ICON := {"창병": "blade", "도적": "blade_down", "기병": "boot", "궁병": "target", "책사": "news", "유생": "news", "모사": "news", "술사": "swirl"}
const TEMPER_ICON := {"맹장": "blade", "수호": "shield", "지략": "news", "저격": "target", "분노": "flame"}


## 섹션 머리 —— 이름(대나무색) · 가는 선 · 오른쪽 옅은 덧말. 섹션 사이 위계는 글자 크기가 아니라 이 줄로 나눈다
static func sect_head(text: String, right := "") -> HBoxContainer:
	var h := UI.hbox(UI.SP_S)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := UI.lbl(text, UI.FS_BODY, DB.PAL.bamboo, true)
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(l)
	var line := UI.hair()
	line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(line)
	var r := UI.lbl(right, UI.FS_TINY, DB.PAL.text_dim)
	r.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	r.name = "Right"
	h.add_child(r)
	return h


## 종류 꼬리표 —— 기호 + 옅은 라벨 (+ 덧말) (디테일창 _abil_tag 와 같은 모양)
static func tag(kind: String, icon: String, col: Color, sub := "") -> HBoxContainer:
	var h := UI.hbox(UI.SP_XS)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	if icon != "":
		var ic := Icons.View.new(icon, col, 10)
		ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(ic)
	h.add_child(UI.lbl(kind, UI.FS_TINY, col))
	if sub != "":
		h.add_child(UI.lbl("· " + sub, UI.FS_TINY, DB.PAL.text_dim))
	return h


## 2단 수치 칩 —— 큰 값 아래 작은 글 (값이 없으면 글만). 디테일창 _stat_chip 과 같은 질감
static func val_chip(val: String, label: String, fill := true) -> PanelContainer:
	var P := DB.PAL
	var pc := PanelContainer.new()
	var sb := UI.flat(Color(P.ink, 0.55), Color(0, 0, 0, 0), 0, UI.R, 0)
	sb.content_margin_left = 7
	sb.content_margin_right = 7
	sb.content_margin_top = 1
	sb.content_margin_bottom = 3
	pc.add_theme_stylebox_override("panel", sb)
	pc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if fill:
		pc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if val == "":
		var tl := UI.lbl(label, UI.FS_CAP, P.paper)
		tl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		pc.add_child(tl)
		return pc
	var v := UI.vbox(-3)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(UI.lbl(val, UI.FS_LABEL, C_VAL, true))
	v.add_child(UI.lbl(label, UI.FS_TINY, P.text_dim))
	pc.add_child(v)
	return pc


## 한 줄 꼬리표 칩 —— 글 + 옥색 값 (고유기 범위 · 수치, 능력치 까닭). st 면 계열 색 면
static func line_chip(label: String, val := "", col := Color(0, 0, 0, 0), icon := "") -> PanelContainer:
	var P := DB.PAL
	var st := col.a > 0
	var pc := PanelContainer.new()
	var sb := UI.flat(Color(col, 0.22) if st else Color(P.ink, 0.55), Color(col, 0.55) if st else Color(0, 0, 0, 0), 1 if st else 0, UI.R, 0)
	sb.content_margin_left = 6
	sb.content_margin_right = 6
	sb.content_margin_top = 2
	sb.content_margin_bottom = 2
	pc.add_theme_stylebox_override("panel", sb)
	pc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var h := UI.hbox(UI.SP_XS)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if icon != "":
		var ic := Icons.View.new(icon, P.bamboo, 9)
		ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(ic)
	h.add_child(UI.lbl(label, UI.FS_TINY, P.paper if st or icon != "" else P.bamboo))
	if val != "":
		h.add_child(UI.lbl(val, UI.FS_TINY, C_VAL, true))
	pc.add_child(h)
	return pc


static var _hl_re: RegEx

## 글의 수치만 옥색으로 (디테일창 _hl 과 같은 규칙) —— 부호가 붙은 수, 단위가 붙은 수
static func hl(text: String) -> String:
	if _hl_re == null:
		_hl_re = RegEx.create_from_string("([+\\-−×]\\s?\\d[\\d,]*(?:\\.\\d+)?\\s?(?:%p|%|턴|초|부대|명)?|\\d[\\d,]*(?:\\.\\d+)?\\s?(?:%p|%|턴|초|부대|명))")
	return _hl_re.sub(text.replace(" / ", " · "), "[color=#8FD4C2]$1[/color]", true)


## 능력 카드 틀 —— 옅은 먹 바탕 + 왼쪽 색 띠. big(주인공 카드)이면 색 그라데이션 · 옅은 빗금 · 오른쪽 아래 큰 기호 (디테일창 AbilCard 와 같은 질감)
class Card extends PanelContainer:
	var col := Color.WHITE
	var big := false
	var icon := ""

	func _init(c: Color, b := false, ic := "", pad := 12) -> void:
		col = c
		big = b
		icon = ic
		var sb := StyleBoxEmpty.new()
		sb.content_margin_left = pad + 2
		sb.content_margin_right = pad
		sb.content_margin_top = 8 if pad >= 12 else 6
		sb.content_margin_bottom = 9 if b else (8 if pad >= 12 else 6)
		add_theme_stylebox_override("panel", sb)
		mouse_filter = Control.MOUSE_FILTER_PASS
		clip_contents = true

	func _draw() -> void:
		var P := DB.PAL
		var r := Rect2(Vector2.ZERO, size)
		draw_style_box(UI.flat(Color(P.ink3, 0.7), Color(0, 0, 0, 0), 0, UI.R, 0), r)
		if big:
			var c0 := Color(col, 0.30)
			var c1 := Color(col, 0.03)
			draw_polygon(PackedVector2Array([Vector2(1, 1), Vector2(size.x - 1, 1), Vector2(size.x - 1, size.y - 1), Vector2(1, size.y - 1)]),
				PackedColorArray([c0, c1, c1, c0]))
			var x := size.x * 0.45
			while x < size.x + size.y:
				draw_line(Vector2(x, 0), Vector2(x - size.y, size.y), Color(col, 0.05), 1.0)
				x += 9.0
			if icon != "":
				Icons.draw(self, icon, Vector2(size.x - 34, size.y - 26), minf(size.y * 0.8, 92.0), Color(col, 0.06))
			draw_style_box(UI.flat(Color(0, 0, 0, 0), Color(col, 0.5), 1, UI.R, 0), r)
		draw_rect(Rect2(0, 0, 3, size.y), col if big else Color(col, 0.85))


## 실시간 막대 —— 왼쪽 어둡고 오른쪽 밝은 그라데이션, 위 한 줄 빛. 줄어든 몫은 잔상(붉은 빛)으로 0.35초 머물렀다가 따라 내려온다 (격투 게임 체력 막대처럼).
## glow(고유기 가득)면 빗금이 흐른다. 움직일 것이 없으면 _process 를 끈다
class LiveBar extends Control:
	var c_hi := Color.WHITE
	var c_lo := Color.WHITE
	var v := 1.0
	var lag := 1.0
	var ticks := 4
	var glow := false
	var _hold := 0.0
	var _t := 0.0

	func _init(hi: Color, lo: Color, h: float, tk := 4) -> void:
		c_hi = hi
		c_lo = lo
		ticks = tk
		custom_minimum_size.y = h
		size_flags_horizontal = Control.SIZE_EXPAND_FILL
		size_flags_vertical = Control.SIZE_SHRINK_CENTER
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_process(false)

	func set_value(x: float, snap := false) -> void:
		x = clampf(x, 0.0, 1.0)
		if is_equal_approx(x, v) and not snap:
			return
		if snap:
			lag = x
		elif x < v:
			if lag <= v + 0.001:
				_hold = 0.35
			lag = maxf(lag, v)
		else:
			lag = maxf(lag, x)
		v = x
		_wake()

	func set_colors(hi: Color, lo: Color) -> void:
		if hi != c_hi or lo != c_lo:
			c_hi = hi
			c_lo = lo
			queue_redraw()

	func set_glow(on: bool) -> void:
		if on != glow:
			glow = on
			_wake()

	func _wake() -> void:
		set_process(glow or lag > v + 0.001)
		queue_redraw()

	func _process(dt: float) -> void:
		_t += dt
		if _hold > 0.0:
			_hold -= dt
		elif lag > v:
			lag = maxf(v, lag - dt * maxf(0.18, (lag - v) * 3.0))
		if not glow and lag <= v + 0.001:
			lag = v
			set_process(false)
		queue_redraw()

	func _draw() -> void:
		var P := DB.PAL
		var r := Rect2(Vector2.ZERO, size)
		draw_style_box(UI.flat(Color(P.ink, 0.9), Color(1, 1, 1, 0.07), 1, 2, 0), r)
		var inn := r.grow(-1.0)
		var w := inn.size.x * v
		if lag > v:
			draw_rect(Rect2(inn.position + Vector2(w, 0), Vector2(inn.size.x * (lag - v), inn.size.y)), Color(1.0, 0.55, 0.45, 0.6))
		if w > 0.5:
			var p0 := inn.position
			var p1 := p0 + Vector2(w, 0)
			var hh := Vector2(0, inn.size.y)
			draw_polygon(PackedVector2Array([p0, p1, p1 + hh, p0 + hh]), PackedColorArray([c_lo, c_hi, c_hi, c_lo]))
			draw_line(p0 + Vector2(0, 0.5), p1 + Vector2(0, 0.5), Color(1, 1, 1, 0.28), 1.0)
			if glow:      # 가득 참 —— 밝은 빗금이 오른쪽으로 흐르고 테가 숨 쉰다
				var step := 7.0
				var off := fmod(_t * 26.0, step)
				var x := p0.x - inn.size.y + off
				while x < p1.x:
					var a := Vector2(x, p0.y + inn.size.y)
					var b := Vector2(x + inn.size.y, p0.y)
					if a.x < p0.x:
						a = Vector2(p0.x, a.y - (p0.x - a.x))
					if b.x > p1.x:
						b = Vector2(p1.x, b.y + (b.x - p1.x))
					if b.x > a.x:
						draw_line(a, b, Color(1, 1, 1, 0.22), 2.0)
					x += step
				draw_style_box(UI.flat(Color(0, 0, 0, 0), Color(c_hi, 0.45 + 0.35 * sin(_t * 5.0)), 1, 2, 0), r.grow(1.0))
		for i in range(1, ticks):
			var tx := inn.position.x + inn.size.x * float(i) / ticks
			draw_line(Vector2(tx, inn.position.y + 1), Vector2(tx, inn.end.y - 1), Color(P.ink, 0.6), 1.0)


## 숫자 글자 —— 값이 바뀌면 0.4초쯤 굴러가며 따라간다 (기여 칸). 0 이면 옅게
class Num extends Label:
	var target := 0.0
	var shown := 0.0
	var on_col := Color.WHITE
	var off_col := Color.WHITE

	func _init(fs: int, on: Color, off: Color) -> void:
		on_col = on
		off_col = off
		add_theme_font_size_override("font_size", fs)
		add_theme_font_override("font", DB.title_font(fs))
		horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_process(false)
		_show()

	func set_to(x: float, snap := false) -> void:
		if is_equal_approx(x, target) and not snap:
			return
		target = x
		if snap:
			shown = x
			_show()
		set_process(not snap)

	func _process(dt: float) -> void:
		shown = lerpf(shown, target, minf(1.0, dt * 9.0))
		if absf(target - shown) < 0.5:
			shown = target
			set_process(false)
		_show()

	func _show() -> void:
		text = Battle.num(shown)
		add_theme_color_override("font_color", on_col if roundi(target) != 0 else off_col)


## 고유기 남은 횟수 —— 마름모 N개 (남은 것 금 · 쓴 것 빈 테)
class Pips extends Control:
	var total := 3
	var left := 3

	func _init(t: int) -> void:
		total = t
		left = t
		custom_minimum_size = Vector2(t * 9 + 2, 10)
		size_flags_vertical = Control.SIZE_SHRINK_CENTER
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func set_left(n: int) -> void:
		if n != left:
			left = n
			queue_redraw()

	func _draw() -> void:
		for i in total:
			var c := Vector2(5 + i * 9, size.y * 0.5)
			var pts := PackedVector2Array([c + Vector2(0, -4), c + Vector2(3.5, 0), c + Vector2(0, 4), c + Vector2(-3.5, 0)])
			if i < left:
				draw_colored_polygon(pts, C_ULT)
			else:
				pts.append(pts[0])
				draw_polyline(pts, Color(DB.PAL.bamboo_dim, 0.9), 1.0, true)


## 상태 알약 —— 점 + 글 (교전 중 · 이동 · 대기 · 패주 · 궤멸 · 전투 종료). live 면 점이 숨 쉰다 (전투가 흐르는 동안만 그린다)
class Pill extends Control:
	const FS := 11
	var text := ""
	var col := Color.WHITE
	var live := false
	var _t := 0.0

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		size_flags_vertical = Control.SIZE_SHRINK_CENTER
		set_process(false)

	func set_state(t: String, c: Color, lv: bool) -> void:
		if t == text and c == col and lv == live:
			return
		text = t
		col = c
		live = lv
		var tw: float = DB.font_bold.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, FS).x
		custom_minimum_size = Vector2(tw + 22.0, FS + 8.0)
		set_process(live)
		queue_redraw()

	func _process(dt: float) -> void:
		_t += dt
		queue_redraw()

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		draw_style_box(UI.flat(Color(col, 0.16), Color(col, 0.55), 1, UI.R, 0), r)
		var a := (0.55 + 0.45 * sin(_t * 4.0)) if live else 1.0
		var c := Vector2(9, size.y * 0.5)
		if live:
			draw_circle(c, 5.0, Color(col, 0.18 * a))
		draw_circle(c, 3.0, Color(col, a))
		draw_string(DB.font_bold, Vector2(16, size.y * 0.5 + FS * 0.36), text, HORIZONTAL_ALIGNMENT_LEFT, -1, FS, col.lightened(0.25))


## 상태 기호 한 칸 —— 전장 머리표 딱지와 같은 그림(Hud._st_icon). 전장에 그림이 없는 상태(방진 · 분발 · 출혈 · 역병 · 봉인)는 Icons
class StIcon extends Control:
	const HUD_KINDS := ["burn", "flood", "confuse", "taunted", "undying", "cut_def", "cut_res", "cut_atk", "cut_int", "shred_phys", "shred_int"]
	var kind := ""
	var col := Color.WHITE
	var hud = null

	func _init(k: String, c: Color, h, d := 14.0) -> void:
		kind = k
		col = c
		hud = h
		custom_minimum_size = Vector2(d, d)
		size_flags_vertical = Control.SIZE_SHRINK_CENTER
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var c := size * 0.5
		if hud != null and is_instance_valid(hud) and HUD_KINDS.has(kind):
			hud._st_icon(c, kind, size.x * 0.42, 1.0, self)
			return
		var ic: String = ST_ICON.get(kind, "")
		if ic != "":
			Icons.draw(self, ic, c, size.x, col)
		else:
			draw_circle(c, size.x * 0.3, col)


## 전투 기록 줄들 —— 줄 사이를 잇는 세로선(기록의 '실')을 점 뒤에 긋는다
class Rail extends VBoxContainer:
	var x := 0.0

	func _init(rail_x: float) -> void:
		x = rail_x
		add_theme_constant_override("separation", 7)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		sort_children.connect(queue_redraw)

	func _draw() -> void:
		var n := get_child_count()
		if n < 2:
			return
		var a: Control = get_child(0)
		var b: Control = get_child(n - 1)
		var y0 := a.position.y + 9.0
		var y1 := b.position.y + 9.0
		draw_line(Vector2(x, y0), Vector2(x, y1), Color(DB.PAL.bamboo_dim, 0.35), 1.0)


## 기록 줄의 점 —— 계열 색 원 안에 기호
class Dot extends Control:
	var col := Color.WHITE
	var icon := ""
	var st := ""
	var hud = null

	func _init(c: Color, ic: String, s := "", h = null) -> void:
		col = c
		icon = ic
		st = s
		hud = h
		custom_minimum_size = Vector2(18, 18)
		size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var c := Vector2(9, 9)
		draw_circle(c, 8.5, DB.PAL.ink2)
		draw_circle(c, 8.0, Color(col, 0.22))
		draw_arc(c, 8.0, 0, TAU, 28, Color(col, 0.85), 1.2, true)
		if st != "" and hud != null and is_instance_valid(hud) and StIcon.HUD_KINDS.has(st):
			hud._st_icon(c, st, 4.6, 1.0, self)
		elif icon != "" or ST_ICON.has(st):
			Icons.draw(self, icon if icon != "" else str(ST_ICON[st]), c, 11.0, col.lightened(0.35))
		elif st != "":
			draw_circle(c, 3.0, col.lightened(0.35))


## 초상 위 막 —— 패주 · 궤멸하면 어둡게 덮고 붉은 도장
class Veil extends Control:
	var word := ""

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	func set_word(w: String) -> void:
		if w != word:
			word = w
			queue_redraw()

	func _draw() -> void:
		if word == "":
			return
		draw_rect(Rect2(Vector2.ZERO, size), Color(DB.PAL.ink, 0.62))
		var fs := 18
		var f: Font = DB.title_font(fs)
		var tw: float = f.get_string_size(word, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_set_transform(size * 0.5, -0.21)
		var box := Rect2(Vector2(-tw * 0.5 - 7, -fs * 0.5 - 5), Vector2(tw + 14, fs + 10))
		draw_style_box(UI.flat(Color(DB.PAL.seal, 0.18), Color(DB.PAL.seal.lightened(0.15), 0.95), 2, 2, 0), box)
		draw_string(f, Vector2(-tw * 0.5, fs * 0.36), word, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, DB.PAL.seal.lightened(0.3))
		draw_set_transform(Vector2.ZERO)


# ───────── 본체 ─────────

const REFRESH := 0.2           # 값 갱신 간격 (초)
const BIG_HIT := 0.10          # 한 행동에 병력의 이만큼 넘게 잃으면 '크게 맞았다'
const BIG_HEAL := 0.05         # 이만큼 넘게 받으면 '치료받았다'
const TL_SHOW := 6             # 기록 처음 보이는 줄
const TL_ALL := 30             # '더 보기' 를 누르면
const ST_NAME := {"phalanx": "방진", "moved": "분발", "cut_atk": "공격 깎임", "cut_int": "책략 깎임", "cut_def": "방어 깎임", "cut_res": "결계 깎임",
	"shred_phys": "갑옷 약화", "shred_int": "결계 약화"}
const ST_GOOD := ["phalanx", "moved", "undying"]

var gs: GameScreen
var view: BattleView
var key := ""
var k := ""
var c: Dictionary
var sq: Squad
var ki := -1
var ult = null
var temper := ""
var ult_total := 0
var _res = null
var _scan := 0
var _ended := false
var _t := 0.0
var _mx := 1.0
var _us_max := 0
var _us_init := 0
var _us_sum := 0
var _us_n := 0

# 실시간 칸
var _veil: Veil
var _pill: Pill
var _l_tr: Label
var _l_trmax: Label
var _l_pct: Label
var _bar_tr: LiveBar
var _bar_mo: LiveBar
var _l_mo: Label
var _bar_ult: LiveBar
var _l_ult: Label
var _l_ult_sub: Label
var _pips: Pips
var _st_row: HFlowContainer
var _st_key := "?"
var _n := {}                 # 기여 칸 이름 -> Num
var _l_rank: Label
var _sig_cnt: Label
var _sig_lab: Label
var _sig_last: RichTextLabel
var _tl: Rail
var _tl_head: HBoxContainer
var _tl_more: Button
var _tl_all := false
var _tl_dirty := true

# 사건 집계 (이 부대 기준)
var _dmg_by := {}            # 부대 key -> 준 피해 (기여 순위)
var _last_hit := {}          # 부대 key -> 마지막으로 친 부대 key (격파 몫)
var _kills := 0
var _heal := 0.0
var _taken := 0.0
var _ult_tm: Array = []      # 이 부대 고유기 시각 (엔진 초)
var _sig_n := 0
var _sig_ever := false       # 이번 전투 기록에 이 장수의 개성 사건이 하나라도 있는가 (없으면 늘 켜진 개성)
var _sig_last_bb := ""
var _entries: Array = []     # 기록 {tm, bb, col, icon, st, …}
var _st_open := {}           # 걸려 있는 상태 -> 그 기록
var _st_last := {}           # 상태 -> 마지막 기록 (풀린 뒤 곧 다시 걸리면 이어 쓴다)
var _prev_st: Array = []
var _prev_alive := true
var _crisis_tr := false
var _crisis_mo := false
var _hit_g = null
var _hit_amt := 0.0
var _hit_e = null
var _ult_g = null
var _ult_e = null
var _heal_e = null


func _init(screen: GameScreen, bv: BattleView, unit_key: String) -> void:
	var t0 := Time.get_ticks_usec()
	gs = screen
	view = bv
	key = unit_key
	sq = view.field.squads.get(key)
	k = sq.cid
	c = DB.C[k]
	_res = view.res
	ki = int(view.idx_of.get(key, -1))
	_mx = maxf(1.0, sq.max)
	ult = DB.ult_of(k) if int(c.tier) >= 6 or DB.is_kiin(k) else null
	if ult != null:
		temper = Battle.temper_name(c, ult)
		ult_total = int(Battle.ULT_CHARGES.get(int(c.tier), 1))
	add_theme_constant_override("separation", UI.SP_M)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mouse_filter = Control.MOUSE_FILTER_PASS
	_sig_ever = _find_sig_ever()
	add_child(_build_live())
	add_child(sect_head("이번 전투", "지금까지"))
	add_child(_build_contrib())
	var sg := _build_sig()
	if sg != null:
		add_child(sg)
	_tl_head = sect_head("전투 기록")
	add_child(_tl_head)
	add_child(_build_timeline())
	add_child(sect_head("장수 정보", "전투 시작 기준"))
	_build_info()
	_scan_events()
	_refresh(true)
	_us_init = Time.get_ticks_usec() - t0


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():      # 점검용 —— --gbsdump=0.6,4,8 : 연 뒤 그 초마다 넘침 · 잘림 · 실시간 값을 글로 찍는다
		if arg.begins_with("--gbsdump"):
			var at := 0.0
			for w in (arg.get_slice("=", 1) if arg.contains("=") else "0.6,4,8").split(","):
				await get_tree().create_timer(maxf(0.05, float(w) - at)).timeout
				at = float(w)
				if is_instance_valid(self):
					dev_dump()


func dev_dump() -> void:
	var body := get_global_rect()
	var bad := []
	var stack: Array = [self]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for ch in n.get_children():
			stack.append(ch)
		if not (n is Control) or not (n as Control).is_visible_in_tree():
			continue
		var cr := (n as Control).get_global_rect()
		if cr.position.x < body.position.x - 0.5 or cr.end.x > body.end.x + 0.5:
			bad.append("넘침 %s %s" % [n.get_class(), str(cr)])
		if n is Label and (n as Label).clip_text:
			var l := n as Label
			var fs := l.get_theme_font_size("font_size")
			var tw := l.get_theme_font("font").get_string_size(l.text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			if tw > l.size.x + 0.5:
				bad.append("잘림 「%s」 %.0f > %.0f" % [l.text, tw, l.size.x])
	print("bsdump %s · 몸 %s · 병력 %s(%s) · 사기 %s · 기 %s 「%s」 · 기여 %s/%d/%s/%s · 개성 %s · 기록 %d건 · 문제 %d" % [key, str(body.size),
		_l_tr.text, _l_pct.text, _l_mo.text, _l_ult.text if _l_ult else "-", _l_ult_sub.text.replace(UI.WJ, "") if _l_ult_sub else "",
		Battle.num(_dmg_by.get(key, 0.0)), _kills, Battle.num(_heal), Battle.num(_taken), _sig_cnt.text if _sig_cnt else "-", _entries.size(), bad.size()])
	print("  열기 %.1fms · 갱신 %d번 · 평균 %.2fms · 최대 %.2fms · 끝 %s" % [_us_init / 1000.0, _us_n, _us_sum / 1000.0 / maxf(1.0, _us_n), _us_max / 1000.0, str(_ended)])
	for b in bad.slice(0, 12):
		print("  ", b)
	for e in _entries.slice(maxi(0, _entries.size() - 4)):
		print("  기록 %s %s" % [_clock(float(e.tm)), str(e.bb)])


func _process(dt: float) -> void:
	if _ended or not is_visible_in_tree():
		return
	_t += dt
	if _t < REFRESH:
		return
	_t = 0.0
	var t0 := Time.get_ticks_usec()
	_refresh(false)
	var us := Time.get_ticks_usec() - t0      # 점검용 —— 갱신 한 번에 드는 시간 (dev_dump 가 찍는다)
	_us_max = maxi(_us_max, us)
	_us_sum += us
	_us_n += 1


# ───────── 상황판 ─────────

func _build_live() -> Control:
	var P := DB.PAL
	var tc := DB.tier_color(k)
	var card := Card.new(tc, true, str(CLS_ICON.get(str(c.tag), "banner")))
	var v := UI.vbox(UI.SP_S)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var top := UI.hbox(UI.SP_M)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var pw := Control.new()      # 초상 + 패주 막
	pw.custom_minimum_size = Vector2(70, 98)
	pw.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	pw.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var cv := CardView.new().setup(k, Vector2(70, 98))
	cv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pw.add_child(cv)
	_veil = Veil.new()
	pw.add_child(_veil)
	top.add_child(pw)
	var rv := UI.vbox(3)
	rv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# 줄 1 —— 진영 칩 · 등급 · 병종 · 자리 · 상태 알약
	var r1 := UI.hbox(UI.SP_XS)
	r1.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tcol: Color = War3D.TEAM[sq.camp]
	var cc := PanelContainer.new()
	var csb := UI.flat(Color(tcol, 0.85), Color(tcol.lightened(0.35), 0.9), 1, UI.R, 0)
	csb.content_margin_left = 5
	csb.content_margin_right = 5
	cc.add_theme_stylebox_override("panel", csb)
	cc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cc.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	cc.add_child(UI.lbl("아군" if sq.camp == "A" else "적군", UI.FS_TINY, P.paper, true))
	r1.add_child(cc)
	var meta := UI.lbl("%s · %s%s" % [DB.tier_name(k), c.tag, (" · " + _pos_name()) if _pos_name() != "" else ""], UI.FS_CAP, P.bamboo)
	meta.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	meta.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	meta.clip_text = true
	r1.add_child(meta)
	_pill = Pill.new()
	r1.add_child(_pill)
	rv.add_child(r1)
	# 줄 2 —— 병력 큰 숫자 / 최대 · 비율
	var r2 := UI.hbox(UI.SP_XS)
	r2.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tl := UI.lbl("병력", UI.FS_TINY, P.text_dim)
	tl.size_flags_vertical = Control.SIZE_SHRINK_END
	r2.add_child(tl)
	_l_tr = UI.lbl("0", UI.FS_HEAD, P.paper, true)
	r2.add_child(_l_tr)
	_l_trmax = UI.lbl("/ " + Battle.num(sq.max), UI.FS_CAP, P.text_dim)
	_l_trmax.size_flags_vertical = Control.SIZE_SHRINK_END
	_l_trmax.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	r2.add_child(_l_trmax)
	_l_pct = UI.lbl("100%", UI.FS_LABEL, P.paper, true)
	_l_pct.size_flags_vertical = Control.SIZE_SHRINK_END
	r2.add_child(_l_pct)
	rv.add_child(r2)
	var tcs: Array = TROOP_COL[sq.camp]
	_bar_tr = LiveBar.new(tcs[0], tcs[1], 10.0, 4)
	rv.add_child(_bar_tr)
	# 줄 3 —— 사기
	var r3 := UI.hbox(UI.SP_S)
	r3.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ml := UI.lbl("사기", UI.FS_TINY, P.text_dim)
	ml.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	r3.add_child(ml)
	_bar_mo = LiveBar.new(C_GOOD, P.jade, 6.0, 1)
	r3.add_child(_bar_mo)
	_l_mo = UI.lbl("100", UI.FS_CAP, P.paper, true)
	_l_mo.custom_minimum_size.x = 26
	_l_mo.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	r3.add_child(_l_mo)
	var mwrap := MarginContainer.new()
	mwrap.add_theme_constant_override("margin_top", 3)
	mwrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mwrap.add_child(r3)
	rv.add_child(mwrap)
	top.add_child(rv)
	v.add_child(top)
	# 고유기 기 —— 이름 · 남은 횟수 · 백분율, 막대, 남은 시간 · 차고 쓰는 때
	if ult != null:
		v.add_child(UI.hair())
		var ub := UI.vbox(3)
		ub.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var uh := UI.hbox(UI.SP_XS)
		uh.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var ic := Icons.View.new("burst", C_ULT, 12)
		ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		uh.add_child(ic)
		uh.add_child(UI.lbl("고유기", UI.FS_TINY, P.text_dim))
		var un := UI.lbl("『%s』" % str(ult.name), UI.FS_CAP, P.paper, true)
		un.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		un.clip_text = true
		uh.add_child(un)
		_pips = Pips.new(ult_total)
		uh.add_child(_pips)
		_l_ult = UI.lbl("0%", UI.FS_LABEL, C_ULT, true)
		_l_ult.custom_minimum_size.x = 44
		_l_ult.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		uh.add_child(_l_ult)
		ub.add_child(uh)
		_bar_ult = LiveBar.new(ULT_BAR[0], ULT_BAR[1], 8.0, 4)
		ub.add_child(_bar_ult)
		_l_ult_sub = UI.lbl("", UI.FS_TINY, P.text_dim)
		_l_ult_sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		ub.add_child(_l_ult_sub)
		v.add_child(ub)
	# 걸린 상태 —— 전장 딱지와 같은 기호 + 이름 칩 (없으면 숨김)
	_st_row = UI.flow(UI.SP_XS)
	_st_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_st_row.visible = false
	v.add_child(_st_row)
	card.add_child(v)
	return card


func _pos_name() -> String:
	var fk := str(view.res.get("aForm" if sq.camp == "A" else "bForm", ""))
	var si := int(key.substr(1))
	if DB.FORM.has(fk) and si >= 0 and si < DB.FORM[fk].slots.size():
		var sl: Dictionary = DB.FORM[fk].slots[si]
		return UI.pos_name(str(sl.line), int(sl.col))
	return ""


func _st_name(st: String) -> String:
	return str(ST_NAME.get(st, DB.D.STATUS.get(st, {}).get("n", st)))


func _st_col(st: String) -> Color:
	match st:
		"phalanx": return Color("#6fb0ff")
		"moved": return DB.PAL.gold
	if StIcon.HUD_KINDS.has(st):
		return BattleView.Hud._icon_col(BattleView.Hud._icon_of(st))
	return Color(str(DB.D.STATUS.get(st, {}).get("c", "#cccccc")))


## 걸린 상태 칩 —— 칩 노드는 모아 두고(_chips) 기호 · 이름 · 색만 바꾼다 (상태가 바뀔 때만 불린다)
var _chips: Array = []       # [{pc, sb, ic, l}]
func _rebuild_status(sts: Array) -> void:
	var seen := {}
	var j := 0
	for st in sts:
		var s := str(st)
		var nm := _st_name(s)
		if seen.has(nm):
			continue
		seen[nm] = true
		var col := _st_col(s)
		if j >= _chips.size():
			var pc := PanelContainer.new()
			var sb := UI.flat(Color(col, 0.14), Color(col, 0.5), 1, UI.R, 0)
			sb.content_margin_left = 4
			sb.content_margin_right = 7
			sb.content_margin_top = 1
			sb.content_margin_bottom = 1
			pc.add_theme_stylebox_override("panel", sb)
			pc.mouse_filter = Control.MOUSE_FILTER_IGNORE
			var h := UI.hbox(3)
			h.mouse_filter = Control.MOUSE_FILTER_IGNORE
			var ic := StIcon.new(s, col, view.hud)
			h.add_child(ic)
			var l := UI.lbl("", UI.FS_TINY, DB.PAL.paper)
			l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			h.add_child(l)
			pc.add_child(h)
			_st_row.add_child(pc)
			_chips.append({"pc": pc, "sb": sb, "ic": ic, "l": l})
		var chip: Dictionary = _chips[j]
		chip.pc.visible = true
		chip.sb.bg_color = Color(col, 0.14)
		chip.sb.border_color = Color(col, 0.5)
		var sic: StIcon = chip.ic
		sic.kind = s
		sic.col = col
		sic.queue_redraw()
		chip.l.text = nm
		_fc(chip.l, col.lightened(0.3) if ST_GOOD.has(s) else DB.PAL.paper)
		j += 1
	for x in range(j, _chips.size()):
		_chips[x].pc.visible = false
	_st_row.visible = j > 0


# ───────── 이번 전투 기여 ─────────

func _build_contrib() -> Control:
	var P := DB.PAL
	var g := GridContainer.new()
	g.columns = 4
	g.add_theme_constant_override("h_separation", UI.SP_XS)
	g.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	g.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for it in [["dmg", "준 피해", "blade", P.gold], ["kill", "격파", "target", C_KILL], ["heal", "치료", "heart", C_HEAL], ["taken", "받은 피해", "shield_crack", C_BAD]]:
		var pc := PanelContainer.new()
		var sb := UI.flat(Color(P.ink3, 0.7), Color(0, 0, 0, 0), 0, UI.R, 0)
		sb.content_margin_left = 8
		sb.content_margin_right = 6
		sb.content_margin_top = 5
		sb.content_margin_bottom = 6
		pc.add_theme_stylebox_override("panel", sb)
		pc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		pc.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var v := UI.vbox(0)
		v.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var h := UI.hbox(3)
		h.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var ic := Icons.View.new(str(it[2]), Color(it[3] as Color, 0.9), 10)
		ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(ic)
		h.add_child(UI.lbl(str(it[1]), UI.FS_TINY, P.text_dim))
		v.add_child(h)
		var n := Num.new(UI.FS_LABEL, P.paper, Color(P.text_dim, 0.6))
		n.clip_text = true
		_n[it[0]] = n
		v.add_child(n)
		if it[0] == "dmg":
			_l_rank = UI.lbl("", UI.FS_TINY, P.gold)
			v.add_child(_l_rank)
		else:
			var sp := UI.lbl(" ", UI.FS_TINY, P.text_dim)
			sp.name = "Sub"
			v.add_child(sp)
		pc.add_child(v)
		g.add_child(pc)
	return g


# ───────── 전장의 개성 ─────────

func _build_sig() -> Control:
	var P := DB.PAL
	var sg = DB.PSV.get("sig", {}).get(DB.person(k))
	var ut: Dictionary = {}
	for t in DB.trait_list(k):
		if t.unique:
			ut = t
			break
	if not (sg is Array and sg.size() >= 2) and ut.is_empty():
		return null
	var card := Card.new(C_SIG, false, "")
	var v := UI.vbox(5)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var hd := UI.hbox(UI.SP_S)
	hd.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var lv := UI.vbox(0)
	lv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lv.add_child(tag("전장의 개성", "seal", C_SIG, "고유 특기"))
	var nm := str(ut.name) if not ut.is_empty() else str(sg[0])
	lv.add_child(UI.lbl(nm, UI.FS_LABEL, P.gold, true))
	hd.add_child(lv)
	var cv := UI.vbox(-4)      # 오른쪽 —— 발동 횟수 (늘 켜진 개성이면 '상시')
	cv.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	cv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sig_cnt = UI.lbl("0", UI.FS_TITLE, C_ULT, true)
	_sig_cnt.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	cv.add_child(_sig_cnt)
	_sig_lab = UI.lbl("이번 전투 발동", UI.FS_TINY, P.text_dim)
	_sig_lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	cv.add_child(_sig_lab)
	hd.add_child(cv)
	v.add_child(hd)
	var line := str(sg[1]) if sg is Array and sg.size() >= 2 else (str(ut.d) as String).get_slice(" —— ", 0)
	var ll := UI.rich(hl(line), UI.FS_CAP)
	ll.add_theme_color_override("default_color", P.bamboo)
	ll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UI.wrap_text(ll)
	v.add_child(ll)
	if not ut.is_empty() and not (ut.ml as Array).is_empty():
		var f := UI.flow(6)
		f.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var chips: Array = (ut.ml as Array).map(DB.mod_chip)
		for ch in chips:
			f.add_child(val_chip(str(ch[0]), str(ch[1]), chips.size() > 1))
		v.add_child(f)
	_sig_last = UI.rich("", UI.FS_TINY)
	_sig_last.add_theme_color_override("default_color", P.text_dim)
	_sig_last.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_sig_last.visible = false
	v.add_child(_sig_last)
	card.add_child(v)
	return card


## 이번 전투 기록에 이 장수의 개성 사건이 있는가 —— 없으면 '늘 켜진 개성'(수치만 바뀌는 특기)으로 보고 횟수 대신 '상시'
func _find_sig_ever() -> bool:
	for e in view.res.get("ev", []):
		if e.get("sig", false) and _sig_who(e) == key:
			return true
	return false


func _sig_who(e: Dictionary) -> String:
	if e.has("healer"):
		return str(e.healer)
	if str(e.get("fx", "")) == "debuff":
		return str(e.get("a", e.get("f", "")))
	return str(e.get("f", ""))


# ───────── 전투 기록 ─────────

func _build_timeline() -> Control:
	var card := Card.new(DB.PAL.bamboo_dim, false, "")
	var v := UI.vbox(UI.SP_S)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tl = Rail.new(36.0 + 6.0 + 9.0)
	v.add_child(_tl)
	_tl_more = UI.btn_small("", func():
		_tl_all = not _tl_all
		_tl_dirty = true
		_rebuild_timeline(), "ghost")
	_tl_more.add_theme_font_size_override("font_size", UI.FS_CAP)
	_tl_more.visible = false
	v.add_child(_tl_more)
	card.add_child(v)
	return card


func _clock(tm: float) -> String:
	var s := int(BattleView.OPEN_RT + tm)
	return "%d:%02d" % [s / 60, s % 60]


func _add(tm: float, bb: String, col: Color, icon: String, st := "") -> Dictionary:
	var e := {"tm": tm, "bb": bb, "col": col, "icon": icon, "st": st}
	_entries.append(e)
	_tl_dirty = true
	return e


## 기록 줄 다시 채우기 —— 줄 노드는 한 번 만들어 두고(_rows) 글 · 시각 · 점만 바꾼다. 바뀐 줄의 글만 다시 읽힌다 (전투 중 새 사건마다 불린다)
var _rows: Array = []        # [{h, t, dot, r}]
var _tl_empty: Label = null
func _rebuild_timeline() -> void:
	_tl_dirty = false
	var P := DB.PAL
	var rl: Label = _tl_head.get_node("Right")
	rl.text = ("%d건" % _entries.size()) if not _entries.is_empty() else ""
	if _tl_empty == null:
		_tl_empty = UI.lbl("아직 큰 일이 없다 —— 고유기 · 격파 · 크게 맞은 순간 · 걸린 상태가 여기 쌓인다", UI.FS_CAP, P.text_dim)
		UI.wrap_text(_tl_empty)
		_tl.add_child(_tl_empty)
	_tl_empty.visible = _entries.is_empty()
	var cap := TL_ALL if _tl_all else TL_SHOW
	var n := mini(cap, _entries.size())
	var order := range(_entries.size())
	order.sort_custom(func(x, y): return float(_entries[x].tm) > float(_entries[y].tm) or (is_equal_approx(float(_entries[x].tm), float(_entries[y].tm)) and x > y))
	for j in n:
		var e: Dictionary = _entries[order[j]]      # 최근 것이 위
		if j >= _rows.size():
			_rows.append(_new_row())
		var row: Dictionary = _rows[j]
		row.h.visible = true
		row.t.text = _clock(float(e.tm))
		var dot: Dot = row.dot
		if dot.col != e.col or dot.icon != str(e.icon) or dot.st != str(e.st):
			dot.col = e.col
			dot.icon = str(e.icon)
			dot.st = str(e.st)
			dot.queue_redraw()
		var r: RichTextLabel = row.r
		if str(r.get_meta("bb", "")) != str(e.bb):
			r.set_meta("bb", str(e.bb))
			r.clear()
			r.append_text(UI.keep_words(str(e.bb)))
	for j in range(n, _rows.size()):
		_rows[j].h.visible = false
	var rest := _entries.size() - n
	_tl_more.visible = rest > 0 or _tl_all
	_tl_more.text = "접기" if _tl_all else "이전 기록 %d건 더 보기" % rest


func _new_row() -> Dictionary:
	var P := DB.PAL
	var h := UI.hbox(6)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tl := UI.lbl("", UI.FS_TINY, P.text_dim)
	tl.custom_minimum_size = Vector2(36, 18)
	tl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	tl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	tl.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	h.add_child(tl)
	var dot := Dot.new(Color.WHITE, "", "", view.hud)
	h.add_child(dot)
	var r := UI.rich("", UI.FS_CAP)
	r.add_theme_color_override("default_color", P.paper)
	r.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var rm := MarginContainer.new()      # 점(18) 가운데와 첫 줄을 맞춘다
	rm.add_theme_constant_override("margin_top", 1)
	rm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rm.add_child(r)
	h.add_child(rm)
	_tl.add_child(h)
	return {"h": h, "t": tl, "dot": dot, "r": r}


# ───────── 사건 훑기 ─────────

func _nm(k2: String) -> String:
	var q: Squad = view.field.squads.get(k2) if view.field != null else null
	if q != null:
		return DB.person(q.cid) if q.tier > 2 else str(q.row.name)
	return k2


## 화면이 반영한 곳까지 사건을 이어서 훑는다 (전투가 끝났으면 끝까지)
func _scan_events() -> void:
	var ev: Array = view.res.get("ev", [])
	if ki < 0 or ev.is_empty():
		return
	var upto: int = (ev.size() - 1) if view.finished else mini(view.live_i, ev.size() - 1)
	var groups: Array = view.group_of
	while _scan <= upto:
		var i := _scan
		_scan += 1
		var e: Dictionary = ev[i]
		var fx := str(e.get("fx", ""))
		var a := str(e.get("a", ""))
		var f := str(e.get("f", ""))
		var tm := float(e.get("tm", 0.0))
		var g = groups[i] if i < groups.size() else null
		match fx:
			"phys", "int":
				var n := float(e.get("n", 0.0))
				var fi := int(view.idx_of.get(f, -1))
				if fi >= 0 and i > 0:      # 넘친 몫은 빼고 (결과표와 같은 '실제 피해')
					n = minf(n, float(ev[i - 1].s[fi][0]))
				_dmg_by[a] = float(_dmg_by.get(a, 0.0)) + n
				if a != "" and f != "" and a.left(1) != f.left(1):
					_last_hit[f] = a
				if a == key and _ult_e != null and g != null and is_same(g, _ult_g):
					_ult_e.dmg += n
					_ult_e.tg[f] = true
					_ult_e.bb = _ult_bb(_ult_e)
					_tl_dirty = true
				if f == key:
					_taken += n
					_big_hit(g, a, n, tm, e)
					_press(a, n, tm)
			"tick":
				if f == key:
					_taken += float(e.get("n", 0.0))
			"heal":
				var hn := float(e.get("n", 0.0))
				var hk := str(e.get("healer", a))
				if hk == key and hn > 0.0:
					_heal += hn
				if f == key and hn >= _mx * BIG_HEAL and hk != key:
					if _heal_e != null and str(_heal_e.by) == hk and tm - float(_heal_e.tm2) < 4.0:
						_heal_e.n += hn
						_heal_e.tm2 = tm
					else:
						_heal_e = _add(tm, "", C_HEAL, "heart")
						_heal_e.by = hk
						_heal_e.n = hn
						_heal_e.tm2 = tm
					_heal_e.bb = "%s치료받았다 [color=#7fd6a4]+%s[/color]" % [("[b]%s[/b]의 " % _nm(hk)) if hk != "" else "", Battle.num(_heal_e.n)]
					_tl_dirty = true
			"ult":
				if a == key:
					_ult_tm.append(tm)
					_ult_e = _add(tm, "", C_ULT, "burst")
					_ult_e.name = str(e.get("name", ""))
					_ult_e.dmg = 0.0
					_ult_e.tg = {}
					_ult_e.joint = e.has("mates")
					_ult_e.bb = _ult_bb(_ult_e)
					_ult_g = g
			"rout":
				if f == key:
					var why := str(e.get("t", "")).get_slice("의 군세가 ", 1)      # 엔진 문장의 까닭 그대로 ("사기 24에서 끝내 패주했다" · "병력이 다해 무너졌다" …)
					if why == "":
						why = "무너졌다"
					_add(tm, "[color=#E0806F][b]%s[/b][/color]" % hl(why), DB.PAL.seal.lightened(0.15), "shield_crack")
				elif str(_last_hit.get(f, "")) == key and f.left(1) != key.left(1):
					_kills += 1
					_add(tm, "격파 —— [b]%s[/b] 부대를 무너뜨렸다" % _nm(f), C_KILL, "target")
		if e.get("sig", false) and _sig_who(e) == key:
			_sig_event(e, tm)
		_track_self(e, tm)


## 이 부대의 상태 · 병력 · 사기 변화 —— 걸렸다 풀린 상태(구간), 위기 문턱, 다시 일어섬
func _track_self(e: Dictionary, tm: float) -> void:
	var s: Array = e.s[ki]
	var alive: bool = int(s[2]) == 1
	var sts: Array = s[3]
	if sts != _prev_st:
		for st in sts:
			if not _prev_st.has(st) and not _st_open.has(st):
				var nm := _st_name(str(st))
				var good := ST_GOOD.has(str(st))
				var x: Dictionary = _st_last.get(st, {})
				if x.is_empty() or tm - float(x.get("end", -99.0)) > 3.0:      # 3초 안에 다시 걸리면 같은 줄을 잇는다 (도발 · 방진이 깜빡이며 줄이 쌓이지 않게)
					x = _add(tm, "", _st_col(str(st)), "", str(st))
					x.nm = nm
					_st_last[st] = x
				x.bb = ("[b]%s[/b]" % nm) + (" —— 버티는 중" if str(st) == "undying" else (" 펼침" if good else "에 걸렸다"))
				_tl_dirty = true
				_st_open[st] = x
		for st in _prev_st:
			if not sts.has(st) and _st_open.has(st):
				var x: Dictionary = _st_open[st]
				_st_open.erase(st)
				var dur := tm - float(x.tm)
				x.end = tm
				x.bb = "[b]%s[/b] [color=#8FD4C2]%s[/color]%s" % [x.nm, DB.sec_str(dur) if dur >= 1.0 else "잠깐", " 동안" if dur >= 1.0 else ""]
				_tl_dirty = true
		_prev_st = sts.duplicate()
	if alive:
		var tr := float(s[0]) / _mx
		var mo := float(s[1])
		if tr < 0.3 and not _crisis_tr and tr > 0.0:
			_crisis_tr = true
			_add(tm, "병력 [color=#E0806F]%d%%[/color] —— 위태롭다" % roundi(tr * 100.0), DB.PAL.danger, "hourglass")
		elif tr > 0.45:
			_crisis_tr = false
		if mo < 30.0 and not _crisis_mo:
			_crisis_mo = true
			_add(tm, "사기 [color=#E0806F]%d[/color] —— 패주 위기" % roundi(mo), DB.PAL.danger, "banner")
		elif mo > 45.0:
			_crisis_mo = false
		if not _prev_alive:
			_add(tm, "[color=#7fd6a4][b]다시 일어섰다[/b][/color]", C_HEAL, "up")
	_prev_alive = alive


## 몰아 맞음 —— 한 방은 작아도 PRESS_T 초 안에 병력 PRESS 넘게 잃으면 '집중 공격' 한 줄 (누구에게 맞았는지 많이 친 순)
const PRESS := 0.15
const PRESS_T := 4.0
var _pr_t0 := -99.0
var _pr_amt := 0.0
var _pr_by := {}
var _pr_e = null
func _press(a: String, n: float, tm: float) -> void:
	if _hit_amt >= _mx * BIG_HIT:      # 이미 '크게 맞았다' 줄로 적힌 한 방은 세지 않는다
		return
	if tm - _pr_t0 > PRESS_T:
		_pr_t0 = tm
		_pr_amt = 0.0
		_pr_by = {}
		_pr_e = null
	_pr_amt += n
	_pr_by[a] = float(_pr_by.get(a, 0.0)) + n
	if _pr_amt < _mx * PRESS:
		return
	if _pr_e == null:
		_pr_e = _add(tm, "", C_BAD.lerp(DB.PAL.bamboo, 0.25), "swirl")
	var who: Array = _pr_by.keys()
	who.sort_custom(func(x, y): return float(_pr_by[x]) > float(_pr_by[y]))
	_pr_e.bb = "집중 공격 —— %d초 동안 [color=#ff7a6a]−%s[/color]  [color=#A89574]%s[/color]" % [maxi(1, ceili(tm - _pr_t0)), Battle.num(_pr_amt),
		" · ".join(who.slice(0, 2).map(func(x): return _nm(str(x))))]
	_tl_dirty = true


func _big_hit(g, a: String, n: float, tm: float, e: Dictionary) -> void:
	if g == null or not is_same(g, _hit_g):
		_hit_g = g
		_hit_amt = 0.0
		_hit_e = null
	_hit_amt += n
	if _hit_amt < _mx * BIG_HIT:
		return
	var who := str(g.who) if g != null and str(g.who) != "" else a
	var what := ""
	var ultg: bool = g != null and g.ult != null
	if ultg:
		what = "고유기 『%s』" % str(g.ult.get("name", ""))
	elif g != null and str(g.skill) != "":
		what = "『%s』" % str(g.skill)
	elif e.has("mn"):
		what = "『%s』" % str(e.mn)
	if _hit_e == null:
		_hit_e = _add(tm, "", C_ULT.lerp(C_BAD, 0.5) if ultg else C_BAD, "burst" if ultg else "blade")
	_hit_e.bb = "[b]%s[/b]의 %s[color=#ff7a6a]−%s[/color]%s" % [_nm(who), (what + " ") if what != "" else "공격 ", Battle.num(_hit_amt),
		"  [color=#ffd257]치명타[/color]" if e.get("crit", false) and what == "" else ""]
	_tl_dirty = true


func _ult_bb(x: Dictionary) -> String:
	var s := "[color=#ffd257][b]%s고유기 『%s』[/b][/color]" % ["인연 합동 " if x.joint else "", str(x.name)]
	if x.dmg > 0.0:
		s += " —— 적 %d부대 · [color=#8FD4C2]%s[/color]" % [x.tg.size(), Battle.num(x.dmg)]
	return s


func _sig_event(e: Dictionary, tm: float) -> void:
	_sig_n += 1
	var stx := str(e.get("t", ""))
	var head := stx.get_slice(" —— ", 0)
	var nm := head.substr(head.rfind("의 ") + 2) if head.find("의 ") >= 0 else head
	var tail := stx.get_slice(" —— ", 1) if stx.find(" —— ") >= 0 else ""
	_sig_last_bb = "최근 [color=#E9E3D3]%s[/color]%s" % [_clock(tm), (" · " + hl(tail)) if tail != "" else ""]
	var last: Dictionary = _entries.back() if not _entries.is_empty() else {}
	if str(last.get("kind", "")) == "sig" and str(last.get("nm", "")) == nm and tm - float(last.get("tm2", 0.0)) < 12.0:
		last.cnt += 1
		last.tm2 = tm
		last.bb = _sig_bb(nm, tail, int(last.cnt))
		_tl_dirty = true
		return
	var x := _add(tm, _sig_bb(nm, tail, 1), C_SIG, "seal")
	x.kind = "sig"
	x.nm = nm
	x.cnt = 1
	x.tm2 = tm


func _sig_bb(nm: String, tail: String, cnt: int) -> String:
	return "[color=#e9c27a][b]『%s』[/b][/color]%s%s" % [nm, (" —— " + hl(tail)) if tail != "" else "", ("  [color=#A89574]×%d[/color]" % cnt) if cnt > 1 else ""]


# ───────── 갱신 ─────────

func _refresh(first: bool) -> void:
	var P := DB.PAL
	if not is_instance_valid(view) or view.field == null or view.field.squads.get(key) != sq:
		_freeze()
		return
	if not is_same(view.res, _res):      # 직접 지휘로 다시 계산했다 —— 앞부분은 같다 (같은 시드 · 입력). 길이만 본다
		_res = view.res
		if _scan > view.res.get("ev", []).size():
			_scan = view.res.get("ev", []).size()
	_scan_events()
	var done: bool = view.finished
	# 병력 · 사기
	var tr := sq.troops
	_l_tr.text = Battle.num(tr)
	var ratio := clampf(tr / _mx, 0.0, 1.0)
	_l_pct.text = "%d%%" % roundi(ratio * 100.0)
	_fc(_l_pct, P.paper if ratio >= 0.5 else (P.gold if ratio >= 0.3 else P.danger))
	_bar_tr.set_value(ratio, first)
	var mo := sq.morale
	_l_mo.text = str(roundi(mo))
	_fc(_l_mo, P.paper if mo >= 50.0 else (P.gold if mo >= 30.0 else P.danger))
	_bar_mo.set_value(mo / 100.0, first)
	if mo >= 60.0:
		_bar_mo.set_colors(C_GOOD, P.jade)
	elif mo >= 30.0:
		_bar_mo.set_colors(Color("#f0cf7a"), Color("#a07a2e"))
	else:
		_bar_mo.set_colors(Color("#ff8a72"), P.seal)
	# 상태 알약 · 초상 막
	var word := ""
	if not sq.alive:
		word = "궤멸" if sq.troops <= 0.5 else "패주"
	_veil.set_word(word)
	if done:
		var win: bool = view.res.get("win", false)
		var draw: bool = view.res.get("draw", false)
		var mine := (sq.camp == "A") == win
		_pill.set_state("전투 종료 · " + ("무승부" if draw else ("승전" if mine else "패전")), C_ULT if (mine and not draw) else P.bamboo, false)
	elif word != "":
		_pill.set_state(word, P.danger if word == "패주" else P.seal.lightened(0.2), false)
	elif sq.contact:
		_pill.set_state("교전 중", Color("#ff8a5a"), true)
	elif sq.moving:
		_pill.set_state("이동 중", P.bamboo, true)
	else:
		_pill.set_state("대기", P.text_dim, true)
	# 걸린 상태 칩 —— 바뀔 때만 다시
	var sts: Array = _prev_st if sq.alive else []
	var skey := ",".join(PackedStringArray(sts.map(func(x): return str(x))))
	if skey != _st_key:
		_st_key = skey
		_rebuild_status(sts)
	# 고유기
	if ult != null:
		_refresh_ult(done)
	# 기여
	var dmg := float(_dmg_by.get(key, 0.0))
	var kills := _kills
	var heal := _heal
	var taken := _taken
	if done and ki >= 0 and ki < view.res.get("roster", []).size():      # 끝나면 결과표와 같은 합계로
		var u: Dictionary = view.res.roster[ki]
		dmg = maxf(0.0, float(u.get("dmg", dmg)) - float(u.get("over", 0.0)))
		kills = int(u.get("kills", kills))
		if u.has("htr"):
			heal = float(u.htr)
		if u.has("taken"):
			taken = float(u.taken)
	_n.dmg.set_to(dmg, first)
	_n.kill.set_to(kills, first)
	_n.heal.set_to(heal, first)
	_n.taken.set_to(taken, first)
	if dmg > 0.0:
		var rank := 1
		for kk in _dmg_by:
			if str(kk).left(1) == key.left(1) and kk != key and float(_dmg_by[kk]) > dmg:
				rank += 1
		var tot := 0.0
		for kk in _dmg_by:
			if str(kk).left(1) == key.left(1):
				tot += float(_dmg_by[kk])
		_l_rank.text = "%s %d위 · %d%%" % ["아군" if sq.camp == "A" else "적군", rank, roundi(dmg / maxf(1.0, tot) * 100.0)]
		_fc(_l_rank, P.gold if rank == 1 else P.text_dim)
	else:
		_l_rank.text = " "
	# 개성
	if _sig_cnt != null:
		if _sig_n > 0 or _sig_ever:
			_sig_cnt.text = "×%d" % _sig_n if _sig_n > 0 else "—"
			_fc(_sig_cnt, C_ULT if _sig_n > 0 else Color(P.text_dim, 0.7))
			_sig_lab.text = "이번 전투 발동" if _sig_n > 0 else "아직 발동 전"
		else:
			_sig_cnt.text = "상시"
			_fc(_sig_cnt, P.bamboo)
			_sig_lab.text = "늘 켜진 개성"
		if _sig_last_bb != "" and _sig_last.get_meta("bb", "") != _sig_last_bb:
			_sig_last.clear()
			_sig_last.append_text(_sig_last_bb)
			_sig_last.set_meta("bb", _sig_last_bb)
			_sig_last.visible = true
	if _tl_dirty:
		_rebuild_timeline()
	if done:
		_ended = true
		set_process(false)


func _refresh_ult(done: bool) -> void:
	var P := DB.PAL
	var lv: Array = view.unit_live(key)
	var gauge := clampf(float(lv[0]), 0.0, 100.0)
	var left := int(lv[1]) if view.live_e != null else ult_total
	var winding: bool = lv[2]
	_pips.set_left(left)
	_bar_ult.set_value(gauge / 100.0)
	var td: PackedStringArray = str(Battle.TEMPER_DESC.get(temper, "")).split(". ")
	var fill_txt := td[0] if td.size() > 0 else ""
	var use_txt := td[1].trim_suffix(".") if td.size() > 1 else ""
	var now := maxf(0.0, view.clock - BattleView.OPEN_RT) if view.end_clock <= 0.0 else maxf(0.0, view.end_clock - BattleView.OPEN_RT)
	var tw := 1.0
	if Battle.temper_enabled and Battle.TEMPER.has(temper):
		tw = float(Battle.TEMPER[temper].wait)
	var wait := float(ult.get("wait", 14.0)) * tw
	var ready_at := wait if _ult_tm.is_empty() else float(_ult_tm.back()) + wait * float(Battle.reult_temper.get(temper, Battle.reult_wait))
	var sub := ""
	var glow := false
	var pct := "%d%%" % roundi(gauge)
	var sealed: bool = _prev_st.has("seal")
	if done:
		sub = "전투가 끝났다 —— %d번 썼다" % _ult_tm.size() if not _ult_tm.is_empty() else "전투가 끝났다 —— 쓰지 못했다"
	elif not sq.alive:
		sub = "쓰러져 더는 쓸 수 없다"
		pct = "—"
	elif left <= 0:
		sub = "%d번 다 썼다" % ult_total
		pct = "끝"
	elif sealed:
		sub = "봉인되어 지금은 쓸 수 없다"
	elif winding:
		sub = "기를 모으는 중 —— 곧 터진다"
		glow = true
		pct = "발동"
	elif now < ready_at:
		sub = "%d초 뒤부터 쓸 수 있다%s" % [ceili(ready_at - now), (" · " + fill_txt) if fill_txt != "" else ""]
	elif gauge >= 100.0:
		sub = "가득 찼다%s" % ((" —— " + use_txt) if use_txt != "" else "")
		glow = true
	else:
		sub = fill_txt if fill_txt != "" else "기가 차면 쓴다"
	_bar_ult.set_glow(glow)
	_l_ult.text = pct
	_fc(_l_ult, C_ULT if left > 0 and sq.alive else P.text_dim)
	_l_ult_sub.text = UI.keep_words(sub)
	_fc(_l_ult_sub, C_ULT.lerp(P.paper, 0.4) if glow else P.text_dim)


## 글자색 —— 같은 색이면 건너뛴다 (0.2초마다 덮어쓰면 테마 알림이 계속 난다)
func _fc(l: Label, col: Color) -> void:
	if l.get_meta("fc", Color(0, 0, 0, 0)) != col:
		l.set_meta("fc", col)
		l.add_theme_color_override("font_color", col)


## 다른 전투로 넘어갔거나 전장이 사라졌다 —— 마지막 모습 그대로 멈춘다
func _freeze() -> void:
	_ended = true
	set_process(false)
	if _pill != null:
		_pill.set_state("전투 끝", DB.PAL.bamboo, false)
	if _bar_ult != null:
		_bar_ult.set_glow(false)


# ───────── 장수 정보 (전투 시작 기준) ─────────

func _build_info() -> void:
	var ss: Dictionary = view.start_stats(key)
	add_child(_build_stats(ss))
	add_child(_build_gear(ss))
	if ult != null:
		add_child(_ult_card())
	# 고유 특기는 위 '전장의 개성' 카드가 맡는다 (개성 문장 · 수치 칩 · 발동 횟수)
	if DB.AURA.has(k):
		var al := DB.aura_list(k)
		var chips := []
		for gr in al.groups:
			for it in gr.items:
				chips.append([it[1], "%s %s" % [gr.who, it[0]]])
		add_child(_abil_card("기인" if DB.is_kiin(k) else "위세", "banner", str(DB.AURA[k].n), str(al.text), chips, DB.tier_color(k)))
		if DB.AURA[k].has("paeup"):
			var pa: Dictionary = DB.AURA[k].paeup
			var pc := []
			if str(pa.cond) != "none":
				var cw: String = str(pa.get("what", "화상을 거는 장수" if str(pa.cond) == "burn" else "상태이상을 거는 장수"))
				pc.append(["%d명 이상" % int(pa.need), "아군에 %s (자신 외)" % cw])
			add_child(_abil_card("패업", "crown", str(pa.n), str(pa.get("d", "")), pc, DB.PAL.bamboo))
	var sk := _build_skills()
	if sk != null:
		add_child(sk)
	var tr := _build_traits()
	if tr != null:
		add_child(tr)


## 공격 · 방어 · 속도 —— 큰 숫자 = 기본, 옆 작은 숫자 = 늘어난 만큼(초록) · 깎인 만큼(빨강). 아래 꼬리표 = 늘어난 까닭
func _build_stats(ss: Dictionary) -> Control:
	var P := DB.PAL
	var v := UI.vbox(UI.SP_XS)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var g := GridContainer.new()
	g.columns = 3
	g.add_theme_constant_override("h_separation", UI.SP_XS)
	g.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	g.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for pair in [["blade", "공격", "atk"], ["shield", "방어", "def"], ["boot", "속도", "spd"]]:
		var base: float = float(c[pair[2]])
		var got: float = float(ss[pair[2]][1]) if ss.has(pair[2]) else base
		var raw: float = float(ss[pair[2]][2]) if ss.has(pair[2]) else base
		var d := roundi(raw - base)
		var cutv := roundi(raw - got)
		var col: Color = (Color("#6fa8ff") if DB.INT_TAGS.has(c.tag) else Color("#ff6b5a")) if pair[2] == "atk" else P.bamboo_dim.lightened(0.15)
		var pc := PanelContainer.new()
		var sb := UI.flat(Color(P.ink3, 0.7), Color(0, 0, 0, 0), 0, UI.R, 0)
		sb.content_margin_left = 8
		sb.content_margin_right = 6
		sb.content_margin_top = 4
		sb.content_margin_bottom = 5
		pc.add_theme_stylebox_override("panel", sb)
		pc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		pc.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var cv := UI.vbox(-2)
		cv.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var hh := UI.hbox(3)
		hh.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var ic := Icons.View.new(str(pair[0]), col, 11)
		ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		hh.add_child(ic)
		hh.add_child(UI.lbl(str(pair[1]) if not (pair[2] == "atk" and DB.INT_TAGS.has(c.tag)) else "책략", UI.FS_TINY, P.text_dim))
		cv.add_child(hh)
		var bb := "[font_size=%d][b]%d[/b][/font_size]" % [UI.FS_TITLE, roundi(base)]
		if d != 0:
			bb += " [color=%s][font_size=%d]%s%d[/font_size][/color]" % ["#7fe0a8" if d > 0 else "#ff7a6a", UI.FS_CAP, "+" if d > 0 else "−", absi(d)]
		if cutv > 0:
			bb += " [color=#ff7a6a][font_size=%d]−%d[/font_size][/color]" % [UI.FS_CAP, cutv]
		var r := UI.rich(bb, UI.FS_CAP, false)
		r.autowrap_mode = TextServer.AUTOWRAP_OFF
		r.add_theme_color_override("default_color", P.paper)
		r.add_theme_font_override("bold_font", DB.title_font(UI.FS_TITLE))
		cv.add_child(r)
		pc.add_child(cv)
		g.add_child(pc)
	v.add_child(g)
	if ss.is_empty():
		var hn := UI.lbl("온라인 재생은 버프 수치를 계산하지 않는다 —— 기본 수치만", UI.FS_TINY, P.text_dim)
		UI.wrap_text(hn)
		v.add_child(hn)
		return v
	var f := UI.flow(UI.SP_XS)
	f.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var lm: Dictionary = DB.D.LINE.get(ss.line, {})
	if not lm.is_empty():
		f.add_child(line_chip("%s 공격" % ss.line, "×%.2f" % float(lm["int"] if Battle.is_caster(c) else lm.atk)))
		f.add_child(line_chip("방어", "×%.2f" % float(lm["def"])))
	var z := DB.aff_of(c.tag, ss.line, ss.side)
	if z != "":
		f.add_child(line_chip("자리 " + ("선호" if z == "pref" else "어색"), "", C_GOOD if z == "pref" else C_BAD))
	f.add_child(line_chip("단체 특기 · 위세 · 사기", "", Color(0, 0, 0, 0), "up"))
	v.add_child(f)
	return v


## 장비 —— 무기 · 갑옷 한 줄씩 (이름 · 등급 · 효과). 빈 칸은 「없음」
func _build_gear(ss: Dictionary) -> Control:
	var P := DB.PAL
	var gear := [ss.get("item"), ss.get("item2")]
	if ss.is_empty():
		for r in view.res.get("roster", []):
			if str(r.get("key", "")) == key:
				gear = [r.get("item"), r.get("item2")]
				break
	var card := Card.new(P.bamboo_dim, false, "", 10)
	var v := UI.vbox(0)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for si in 2:
		if si > 0:
			v.add_child(UI.hair())
		var sl: String = ["weapon", "armor"][si]
		var iid = gear[si]
		var m := MarginContainer.new()
		m.add_theme_constant_override("margin_top", 5)
		m.add_theme_constant_override("margin_bottom", 5)
		m.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var h := UI.hbox(UI.SP_S)
		h.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var ic := Icons.View.new("blade" if si == 0 else "shield", P.bamboo_dim, 12)
		ic.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		h.add_child(ic)
		var sll := UI.lbl(DB.ISLOT_NAME[sl], UI.FS_TINY, P.text_dim)
		sll.custom_minimum_size.x = 26
		sll.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		h.add_child(sll)
		if iid != null and DB.IT.has(iid):
			var it: Dictionary = DB.IT[iid]
			var r := UI.rich("[color=#%s][b]%s[/b][/color] [color=#A89574][font_size=%d]%s[/font_size][/color]\n%s" % [
				UI.item_col(iid).lightened(0.2).to_html(false), it.name, UI.FS_TINY, it.grade, hl(UI.item_text(iid))], UI.FS_CAP)
			r.add_theme_color_override("default_color", P.bamboo)
			r.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			h.add_child(r)
		else:
			var l := UI.lbl("없음", UI.FS_CAP, Color(P.text_dim, 0.7))
			l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			h.add_child(l)
		m.add_child(h)
		v.add_child(m)
	card.add_child(v)
	return card


## 고유기 카드 —— 계열 색 주인공 카드: 꼬리표(고유기 · N초부터 · N회) · 이름 · 외침 | 큰 숫자, 아래 꼬리표 줄, 맨 아래 기질
func _ult_card() -> Control:
	var P := DB.PAL
	var vfx := str(ult.get("vfx", ""))
	var col: Color = ULT_COL.get(vfx, DB.tier_color(k))
	var parts := DB.ult_parts(ult, int(c.tier))
	var card := Card.new(col, true, str(ULT_ICON.get(vfx, "burst")))
	var v := UI.vbox(6)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var top := UI.hbox(UI.SP_S)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var left := UI.vbox(0)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	left.add_child(tag("고유기", "burst", col.lightened(0.3), "%d초부터 · %d회" % [roundi(float(ult.wait)), ult_total]))
	var nl := UI.lbl(str(ult.name), UI.FS_TITLE, P.paper, true)
	UI.wrap_text(nl)
	left.add_child(nl)
	if str(ult.get("shout", "")) != "":
		var shl := UI.lbl("“%s”" % str(ult.shout), UI.FS_TINY, P.text_dim)
		UI.wrap_text(shl)
		left.add_child(shl)
	top.add_child(left)
	if not parts.hero.is_empty():
		var hv := UI.vbox(-5)
		hv.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		hv.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var a := UI.lbl(str(parts.hero.v), UI.FS_HEAD + 2, col.lightened(0.45), true)
		a.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		hv.add_child(a)
		var b := UI.lbl(str(parts.hero.l), UI.FS_TINY, P.bamboo)
		b.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		hv.add_child(b)
		top.add_child(hv)
	v.add_child(top)
	if not parts.chips.is_empty():
		var f := UI.flow(6)
		f.mouse_filter = Control.MOUSE_FILTER_IGNORE
		for ch in parts.chips:
			var kind := str(ch.get("k", ""))
			f.add_child(line_chip(str(ch.l), str(ch.get("v", "")), col if kind == "st" else Color(0, 0, 0, 0), "target" if kind == "tgt" else ""))
		v.add_child(f)
	if temper != "":      # 기질 —— 차는 때 · 쓰는 때 (실시간 기 막대 아래 글과 같은 말)
		var td: PackedStringArray = str(Battle.TEMPER_DESC.get(temper, "")).split(". ")
		var th := UI.hbox(UI.SP_XS)
		th.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var ti := Icons.View.new(str(TEMPER_ICON.get(temper, "pick")), P.bamboo, 11)
		ti.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		th.add_child(ti)
		var tr := UI.rich("[color=#A89574]기질[/color] [b]%s[/b]  [color=#A89574]차는 때[/color] %s%s" % [temper, td[0] if td.size() > 0 else "",
			("  [color=#A89574]쓰는 때[/color] " + td[1].trim_suffix(".")) if td.size() > 1 else ""], UI.FS_TINY)
		tr.add_theme_color_override("default_color", P.bamboo)
		tr.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		th.add_child(tr)
		v.add_child(UI.hair())
		v.add_child(th)
	card.add_child(v)
	return card


## 능력 카드 (위세 · 기인 · 패업) —— 꼬리표 · 이름 · 글, 아래 2단 수치 칩
func _abil_card(kind: String, icon: String, nm: String, line: String, chips: Array, col: Color) -> Control:
	var P := DB.PAL
	var card := Card.new(col, false, "")
	var v := UI.vbox(5)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var hd := UI.hbox(UI.SP_S)
	hd.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var nl := UI.lbl(nm, UI.FS_LABEL, P.paper, true)
	nl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UI.wrap_text(nl)
	hd.add_child(nl)
	hd.add_child(tag(kind, icon, P.text_dim))
	v.add_child(hd)
	if line != "":
		var ll := UI.rich(hl(line), UI.FS_CAP)
		ll.add_theme_color_override("default_color", P.bamboo)
		ll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		UI.wrap_text(ll)
		v.add_child(ll)
	if not chips.is_empty():
		var f := UI.flow(6)
		f.mouse_filter = Control.MOUSE_FILTER_IGNORE
		for ch in chips:
			f.add_child(val_chip(str(ch[0]), str(ch[1]), chips.size() > 1))
		v.add_child(f)
	card.add_child(v)
	return card


## 기술 —— 자주 쓰는 기술(잔기술) + 일반 기술: 이름 · 나오는 때, 아래 효과 (한 장의 패널, 줄 사이 가는 선)
func _build_skills() -> Control:
	var P := DB.PAL
	var rows := []
	var mk := Battle.minor_kind(k)
	if mk != "":
		rows.append([str(Battle.minor_def(mk).n), GameScreen.minor_when(k), GameScreen.minor_desc(k, false), "잔기술"])
	for x in c.get("sks", []):
		rows.append([str(x.n), DB.sk_when(x, c), DB.skill_desc(c, x), "기술"])
	if rows.is_empty():
		return null
	var card := Card.new(P.bamboo_dim, false, "", 10)
	var v := UI.vbox(0)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for i in rows.size():
		if i > 0:
			v.add_child(UI.hair())
		var rw: Array = rows[i]
		var m := MarginContainer.new()
		m.add_theme_constant_override("margin_top", 6)
		m.add_theme_constant_override("margin_bottom", 6)
		m.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var rv := UI.vbox(2)
		rv.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var h := UI.hbox(UI.SP_S)
		h.mouse_filter = Control.MOUSE_FILTER_IGNORE
		h.add_child(UI.lbl("『%s』" % rw[0], UI.FS_CAP + 1, P.gold, true))
		var wl := UI.lbl(str(rw[1]), UI.FS_TINY, P.text_dim)
		wl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		wl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		UI.wrap_text(wl)
		h.add_child(wl)
		rv.add_child(h)
		var d := UI.rich(hl(str(rw[2])), UI.FS_TINY + 1)
		d.add_theme_color_override("default_color", P.bamboo)
		d.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		rv.add_child(d)
		m.add_child(rv)
		v.add_child(m)
	if c.get("sks", []).size() >= 2:
		v.add_child(UI.hair())
		var nt := UI.lbl(DB.SK_SHARE_NOTE, UI.FS_TINY, P.text_dim)
		UI.wrap_text(nt)
		var nm := MarginContainer.new()
		nm.add_theme_constant_override("margin_top", 5)
		nm.mouse_filter = Control.MOUSE_FILTER_IGNORE
		nm.add_child(nt)
		v.add_child(nm)
	card.add_child(v)
	return card


## 특기 —— 고유 특기는 위(전장의 개성)에. 나머지는 두 칸 격자: 이름 · 레벨, 아래 수치 (전투 중엔 무엇이 켜져 있는지만 훑으면 된다)
func _build_traits() -> Control:
	var P := DB.PAL
	var tl := DB.trait_list(k).filter(func(x): return not x.unique)
	if tl.is_empty():
		return null
	var v := UI.vbox(UI.SP_XS)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(sect_head("특기", "%d개" % tl.size()))
	var g := GridContainer.new()
	g.columns = 2
	g.add_theme_constant_override("h_separation", UI.SP_XS)
	g.add_theme_constant_override("v_separation", UI.SP_XS)
	g.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	g.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for t in tl:
		var col: Color = (DB.TRAIT_COL.get(str(t.attr) if str(t.attr) != "" else ("단체" if t.group else ""), DB.TRAIT_COL[""]) as Color).lightened(0.25)
		var pc := Card.new(col, false, "", 8)
		pc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var cv := UI.vbox(1)
		cv.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var h := UI.hbox(UI.SP_XS)
		h.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var nl := UI.lbl(str(t.name), UI.FS_CAP, P.paper, true)
		nl.clip_text = true
		nl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(nl)
		h.add_child(UI.lbl(str(t.lv), UI.FS_CAP, P.gold, true))
		cv.add_child(h)
		var mt := str(t.mt) if str(t.mt) != "" else (str(t.d) as String).get_slice(" —— ", 0)
		var r := UI.rich(hl(mt), UI.FS_TINY)
		r.add_theme_color_override("default_color", P.bamboo)
		r.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cv.add_child(r)
		pc.add_child(cv)
		g.add_child(pc)
	v.add_child(g)
	return v
