extends VBoxContainer
## 전투장수창 (11/21 폴리싱) —— 전투 중 메달을 꾹 눌러 연다 (GameScreen.battle_unit_sheet 가 open_sheet · sheet_head 뒤에 이것 하나를 넣는다).
## 사용자: "전투시 꾹 눌러서 나오는 장수정보창도 폴리싱" · "갈무리창 · 상세창 · 전투 장수창은 톤앤매너가 일치" ·
## "전투 장수창은 전투 시에만 일어나는 사건들을 추가 (조합법 같은 건 빼고)" · "우와 신경 많이 썼구나".
##
## 위에서부터 '지금 상황'이 먼저 —— ① 상황판(초상 · 병력 · 사기 · 고유기 기와 남은 시간 · 걸린 상태) ② 이번 전투(준 피해 · 격파 · 치료 · 받은 피해)
## ③ 전장의 개성(고유 특기 개성 문장 · 이번 전투 발동 횟수 · 최근 발동) ④ 전투 기록(이 장수에게 일어난 사건) —— 그 아래 장수 정보
## (능력치 + 전투 버프 · 기질 · 장비 · 고유 능력 · 기술 · 특기 —— 상세창과 같은 부품).
##
## 모양은 장수창 공통 시각 언어(SheetStyle)로 —— 머리(등급 색 바탕 · 등급 리본 · 세력 · 병종)는 GameScreen.sheet_head, 판은 SheetStyle.Plate,
## 섹션 머리는 SheetStyle.section, 칸 · 칩 · 기록 줄은 SheetStyle 의 칸(stat_cells) · 칩 · 정보 행(info_row)과 같은 수치로 그린다.
## 값이 계속 바뀌는 칸(막대 · 숫자 · 기록 줄 · 상태 칩)만 여기서 직접 만든다 —— SheetStyle 부품은 한 번 그리면 끝이라 실시간 갱신이 안 된다.
##
## 갱신: 열어 둔 채 전투가 흐르면 REFRESH 초마다 값만 바꾼다 (글자 · 막대 다시 그리기). 노드는 처음에 한 번 만들고, 기록 줄 · 상태 칩은
## 모아 둔 노드에 글만 바꿔 넣는다. 사건은 전투 기록(res.ev)을 화면이 반영한 곳(BattleView.live_i)까지 이어서 훑는다 (처음 열 때 한 번 처음부터).
## 시트가 숨으면(닫힘) 아무것도 하지 않는다. 전투가 끝나면 결과 명단의 합계로 바꾸고 멈춘다.

const SS := preload("res://scripts/ui/sheet_style.gd")      # 장수창 공통 시각 언어 (SheetStyle)

# ───────── 색 (SheetStyle 단계 위의 전투 전용 몇 가지) ─────────

const C_KILL := Color("#ff9b5a")       # 격파
const C_HEAL := Color("#7fd6a4")       # 치료 (전장 치료 글씨와 같은 초록)
const C_GLOW := Color("#ffd257")       # 고유기 막대 · 개성 발동 (전장 머리 위 글씨와 같은 금)
const TROOP_COL := {"A": [Color("#6fa8ff"), Color("#2f5fb8")], "B": [Color("#ff8a72"), Color("#b5382c")]}      # 병력 막대 (위 띠 병력 막대와 같은 진영색)
const ULT_BAR := [Color("#ffe08a"), Color("#b8801f")]
const CLS_ICON := {"창병": "blade", "도적": "blade_down", "기병": "boot", "궁병": "target", "책사": "news", "유생": "news", "모사": "news", "술사": "swirl"}
const ST_ICON := {"phalanx": "shield", "moved": "up", "seal": "seal", "plague": "swirl", "bleed": "flame"}      # 전장 딱지에 그림이 없는 상태의 기호
const ST_NAME := {"phalanx": "방진", "moved": "분발", "cut_atk": "공격 깎임", "cut_int": "책략 깎임", "cut_def": "방어 깎임", "cut_res": "결계 깎임",
	"shred_phys": "갑옷 약화", "shred_int": "결계 약화"}
const ST_GOOD := ["phalanx", "moved", "undying"]
const HUD_KINDS := ["burn", "flood", "confuse", "taunted", "undying", "cut_def", "cut_res", "cut_atk", "cut_int", "shred_phys", "shred_int"]      # 전장 딱지 그림(Hud._st_icon)이 있는 상태


## 시트 머리 덧칩 —— [아군/적군] 하나 (GameScreen.sheet_head 의 extra). 자리(선봉 …)는 머리 줄이 두 줄로 넘지 않게 상황판 시계 옆에
static func head_extra(bv: BattleView, key: String) -> Array:
	var sq: Squad = bv.field.squads.get(key)
	return [["아군" if sq.camp == "A" else "적군", (War3D.TEAM[sq.camp] as Color).lightened(0.25)]]


## 진형 자리 이름 (선봉 · 중군 …) —— 없으면 ""
static func pos_of(bv: BattleView, key: String) -> String:
	var sq: Squad = bv.field.squads.get(key)
	var fk := str(bv.res.get("aForm" if sq.camp == "A" else "bForm", ""))
	var si := int(key.substr(1))
	if DB.FORM.has(fk) and si >= 0 and si < DB.FORM[fk].slots.size():
		var sl: Dictionary = DB.FORM[fk].slots[si]
		return UI.pos_name(str(sl.line), int(sl.col))
	return ""


static var _hl_re: RegEx

## 글의 수치만 옥색으로 (상세창 _hl 과 같은 규칙) —— 부호가 붙은 수, 단위가 붙은 수
static func hl(text: String) -> String:
	if _hl_re == null:
		_hl_re = RegEx.create_from_string("([+\\-−×]\\s?\\d[\\d,]*(?:\\.\\d+)?\\s?(?:%p|%|턴|초|부대|명)?|\\d[\\d,]*(?:\\.\\d+)?\\s?(?:%p|%|턴|초|부대|명))")
	return _hl_re.sub(text.replace(" / ", " · "), "[color=#8FD4C2]$1[/color]", true)


## 2단 수치 칩 —— 큰 값 아래 작은 글 (상세창 능력 카드 _stat_chip 과 같은 수치 · 질감)
static func val_chip(val: String, label: String, fill := true) -> PanelContainer:
	var pc := PanelContainer.new()
	var sb := UI.flat(SS.WELL, Color(0, 0, 0, 0), 0, UI.R, 0)
	sb.content_margin_left = 7
	sb.content_margin_right = 7
	sb.content_margin_top = 1
	sb.content_margin_bottom = 3
	pc.add_theme_stylebox_override("panel", sb)
	pc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if fill:
		pc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var v := UI.vbox(-3)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if val != "":
		v.add_child(UI.lbl(val, SS.FS_VALUE, SS.VAL, true))
	v.add_child(UI.lbl(label, SS.FS_TAG if val != "" else SS.FS_SUB, SS.DIM if val != "" else SS.TEXT))
	pc.add_child(v)
	return pc


## 판 안 꼬리표 —— 작은 기호 + 옅은 글 (+ 덧말) (상세창 능력 카드 _abil_tag 와 같은 모양)
static func tag(kind: String, icon: String, col: Color, sub := "") -> HBoxContainer:
	var h := UI.hbox(UI.SP_XS)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	if icon != "":
		var ic := Icons.View.new(icon, col, 10)
		ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(ic)
	h.add_child(UI.lbl(kind, SS.FS_TAG, col))
	if sub != "":
		h.add_child(UI.lbl("· " + sub, SS.FS_TAG, SS.DIM))
	return h


## 실시간 막대 —— SheetStyle.meter 와 같은 바닥(종이색 8%) · 모서리 2 위에, 왼쪽 어둡고 오른쪽 밝은 그라데이션 + 위 한 줄 빛.
## 줄어든 몫은 잔상(붉은 빛)으로 0.35초 머물렀다가 따라 내려온다 (격투 게임 체력 막대처럼). glow(고유기 가득)면 빗금이 흐르고 테가 숨 쉰다.
## 움직일 것이 없으면 _process 를 끈다
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
			if lag <= v + 0.001:      # 새로 줄기 시작할 때만 머문다 (계속 줄 때마다 머물면 잔상이 내려오지 않는다)
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
		var r := Rect2(Vector2.ZERO, size)
		draw_style_box(UI.flat(Color(1, 1, 1, 0.08), Color(0, 0, 0, 0), 0, 2, 0), r)
		var w := size.x * v
		if lag > v:
			draw_rect(Rect2(Vector2(w, 0), Vector2(size.x * (lag - v), size.y)), Color(1.0, 0.55, 0.45, 0.6))
		if w > 0.5:
			var hh := Vector2(0, size.y)
			var p1 := Vector2(w, 0)
			draw_polygon(PackedVector2Array([Vector2.ZERO, p1, p1 + hh, hh]), PackedColorArray([c_lo, c_hi, c_hi, c_lo]))
			draw_line(Vector2(0, 0.5), Vector2(w, 0.5), Color(1, 1, 1, 0.28), 1.0)
			if glow:      # 가득 참 —— 밝은 빗금이 오른쪽으로 흐른다
				var step := 7.0
				var x := -size.y + fmod(_t * 26.0, step)
				while x < w:
					var a := Vector2(x, size.y)
					var b := Vector2(x + size.y, 0)
					if a.x < 0.0:
						a = Vector2(0.0, a.y + a.x)
					if b.x > w:
						b = Vector2(w, b.y + (b.x - w))
					if b.x > a.x:
						draw_line(a, b, Color(1, 1, 1, 0.22), 2.0)
					x += step
		if glow:
			draw_style_box(UI.flat(Color(0, 0, 0, 0), Color(c_hi, 0.45 + 0.35 * sin(_t * 5.0)), 1, 2, 0), r.grow(1.0))
		for i in range(1, ticks):
			var tx := size.x * float(i) / ticks
			draw_line(Vector2(tx, 1), Vector2(tx, size.y - 1), Color(0.075, 0.102, 0.169, 0.6), 1.0)


## 숫자 글자 —— 값이 바뀌면 0.4초쯤 굴러가며 따라간다 (이번 전투 칸). 0 이면 옅게
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
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		size_flags_vertical = Control.SIZE_SHRINK_CENTER
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


## 고유기 남은 횟수 —— 마름모 N개 (섹션 머리의 금 마름모와 같은 꼴 · 남은 것 금 · 쓴 것 빈 테)
class Pips extends Control:
	var total := 3
	var left := 3

	func _init(t: int) -> void:
		total = t
		left = t
		custom_minimum_size = Vector2(t * 10 + 2, 10)
		size_flags_vertical = Control.SIZE_SHRINK_CENTER
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func set_left(n: int) -> void:
		if n != left:
			left = n
			queue_redraw()

	func _draw() -> void:
		for i in total:
			var c := Vector2(5 + i * 10, size.y * 0.5)
			var pts := PackedVector2Array([c + Vector2(0, -4), c + Vector2(4, 0), c + Vector2(0, 4), c + Vector2(-4, 0)])
			if i < left:
				draw_colored_polygon(pts, SS.GOLD_HI)
			else:
				pts.append(pts[0])
				draw_polyline(pts, Color(SS.DIM, 0.8), 1.0, true)


## 상태 알약 —— SheetStyle.chip(soft) 과 같은 면 · 테 위에 점 + 글 (교전 중 · 이동 · 대기 · 패주 · 궤멸 · 전투 종료).
## live 면 점이 숨 쉰다 (전투가 흐르는 동안만 그린다)
class Pill extends Control:
	const FS := 12
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
		custom_minimum_size = Vector2(ceilf(tw) + 26.0, FS + 10.0)
		set_process(live)
		queue_redraw()

	func _process(dt: float) -> void:
		_t += dt
		queue_redraw()

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		draw_style_box(UI.flat(Color(col, 0.16), Color(col, 0.45), 1, UI.R, 0), r)
		var a := (0.55 + 0.45 * sin(_t * 4.0)) if live else 1.0
		var c := Vector2(10, size.y * 0.5)
		if live:
			draw_circle(c, 5.5, Color(col, 0.2 * a))
		draw_circle(c, 3.0, Color(col, a))
		draw_string(DB.font_bold, Vector2(18, size.y * 0.5 + FS * 0.36), text, HORIZONTAL_ALIGNMENT_LEFT, -1, FS, col.lightened(0.3))


## 기호 배지 —— SheetStyle.icon_badge 와 같은 먹 바닥 네모 · 색 테. 상태면 전장 딱지와 같은 그림(Hud._st_icon). 기록 줄을 모아 쓰려고 기호를 바꿀 수 있다
class Badge extends Control:
	var col := Color.WHITE
	var icon := ""
	var st := ""
	var hud = null

	func _init(h, d := 22.0) -> void:
		hud = h
		custom_minimum_size = Vector2(d, d)
		size_flags_vertical = Control.SIZE_SHRINK_CENTER
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func set_mark(c: Color, ic: String, s := "") -> void:
		if c != col or ic != icon or s != st:
			col = c
			icon = ic
			st = s
			queue_redraw()

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		draw_style_box(UI.flat(SS.WELL, Color(col, 0.4), 1, UI.R, 0), r)
		var c := size * 0.5
		if st != "" and hud != null and is_instance_valid(hud) and HUD_KINDS.has(st):
			hud._st_icon(c, st, size.x * 0.24, 1.0, self)
		elif icon != "" or ST_ICON.has(st):
			Icons.draw(self, icon if icon != "" else str(ST_ICON[st]), c, roundf(size.x * 0.58), col.lightened(0.2))
		else:
			draw_circle(c, 3.0, col)


## 상태 칩의 작은 기호 —— 배지 바닥 없이 그림만
class StIcon extends Control:
	var kind := ""
	var col := Color.WHITE
	var hud = null

	func _init(h) -> void:
		hud = h
		custom_minimum_size = Vector2(13, 13)
		size_flags_vertical = Control.SIZE_SHRINK_CENTER
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var c := size * 0.5
		if hud != null and is_instance_valid(hud) and HUD_KINDS.has(kind):
			hud._st_icon(c, kind, size.x * 0.42, 1.0, self)
		elif ST_ICON.has(kind):
			Icons.draw(self, str(ST_ICON[kind]), c, size.x, col)
		else:
			draw_circle(c, size.x * 0.3, col)


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
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.075, 0.102, 0.169, 0.62))
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
const PRESS := 0.15            # PRESS_T 초 안에 병력 이만큼 넘게 잃으면 '집중 공격'
const PRESS_T := 4.0
const TL_SHOW := 6             # 기록 처음 보이는 줄
const TL_ALL := 30             # '더 보기' 를 누르면

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
var _pos := ""
var _us_max := 0
var _us_init := 0
var _us_sum := 0
var _us_n := 0

# 실시간 칸
var _veil: Veil
var _pill: Pill
var _l_clock: Label
var _l_tr: Label
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
var _chips: Array = []       # 상태 칩 [{pc, sb, ic, l}]
var _n := {}                 # 이번 전투 칸 이름 -> Num
var _l_rank: Label
var _l_share: Label
var _sig_cnt: Label
var _sig_lab: Label
var _sig_last: Label
var _tl_sec: Control
var _tl_plate: SheetStyle.Plate
var _tl_box: VBoxContainer
var _tl_more: Button
var _tl_empty: Label
var _rows: Array = []        # 기록 줄 [{m, hair, badge, t, title, detail, nv, num, nlab}]
var _tl_all := false
var _tl_dirty := true

# 사건 집계 (이 부대 기준)
var _dmg_by := {}            # 부대 key -> 준 피해 (기여 순위)
var _last_hit := {}          # 부대 key -> 마지막으로 친 적 부대 key (격파 몫)
var _kills := 0
var _heal := 0.0
var _taken := 0.0
var _ult_tm: Array = []      # 이 부대 고유기 시각 (엔진 초)
var _sig_n := 0
var _sig_ever := false       # 이번 전투 기록에 이 장수의 개성 사건이 하나라도 있는가 (없으면 늘 켜진 개성)
var _sig_last_txt := ""
var _entries: Array = []     # 기록 {tm, col, icon, st, title, tcol, detail, num, ncol, nlab, …}
var _st_open := {}           # 걸려 있는 상태 -> 그 기록
var _st_last := {}           # 상태 -> 마지막 기록 (풀린 뒤 곧 다시 걸리면 이어 쓴다)
var _prev_st: Array = []     # 화면이 반영한 마지막 사건의 이 부대 상태
var _prev_alive := true
var _crisis_tr := false
var _crisis_mo := false
var _hit_g = null
var _hit_amt := 0.0
var _hit_e = null
var _ult_g = null
var _ult_e = null
var _heal_e = null
var _pr_t0 := -99.0
var _pr_amt := 0.0
var _pr_by := {}
var _pr_e = null


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
	_pos = pos_of(view, key)
	ult = DB.ult_of(k) if int(c.tier) >= 6 or DB.is_kiin(k) else null
	if ult != null:
		temper = Battle.temper_name(c, ult)
		ult_total = Battle.ult_charges_of(c)
	add_theme_constant_override("separation", UI.SP_M)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mouse_filter = Control.MOUSE_FILTER_PASS
	_sig_ever = _find_sig_ever()
	add_child(_build_live())
	add_child(_sect(SS.section("이번 전투", "지금까지"), _build_contrib()))
	var sg := _build_sig()
	if sg != null:
		add_child(sg)
	_tl_sec = SS.section("전투 기록", " ")
	add_child(_sect(_tl_sec, _build_timeline()))
	_build_info()
	_scan_events()
	_refresh(true)
	_us_init = Time.get_ticks_usec() - t0


## 섹션 머리 + 몸 (머리와 몸 사이는 SP_S —— 상세창 섹션과 같은 간격)
func _sect(head: Control, body: Control) -> VBoxContainer:
	var v := UI.vbox(UI.SP_S)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(head)
	v.add_child(body)
	return v


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():      # 점검용 —— --gbsdump=0.6,4,8 : 연 뒤 그 초마다 넘침 · 잘림 · 실시간 값을 글로 찍는다
		if arg.begins_with("--gbsdump"):
			var at := 0.0
			for w in (arg.get_slice("=", 1) if arg.contains("=") else "0.6,4,8").split(","):
				await get_tree().create_timer(maxf(0.05, float(w) - at)).timeout
				at = float(w)
				if is_instance_valid(self):
					dev_dump()


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
	var tc := DB.tier_color(k)
	var card := SS.Plate.new(tc, SS.HERO, str(CLS_ICON.get(str(c.tag), "banner")))
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
	var rv := UI.vbox(4)
	rv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# 줄 1 —— 상태 알약 · 전투 시계
	var r1 := UI.hbox(UI.SP_XS)
	r1.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pill = Pill.new()
	r1.add_child(_pill)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r1.add_child(sp)
	_l_clock = UI.lbl("", SS.FS_SUB, SS.DIM)
	_l_clock.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	r1.add_child(_l_clock)
	rv.add_child(r1)
	# 줄 2 —— 병력 큰 숫자 / 최대 · 비율
	var r2 := UI.hbox(UI.SP_XS)
	r2.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tl := UI.lbl("병력", SS.FS_SUB, SS.DIM)
	tl.size_flags_vertical = Control.SIZE_SHRINK_END
	r2.add_child(tl)
	_l_tr = UI.lbl("0", SS.FS_STAT, SS.TEXT, true)
	r2.add_child(_l_tr)
	var mx := UI.lbl("/ " + Battle.num(sq.max), SS.FS_SUB, SS.DIM)
	mx.size_flags_vertical = Control.SIZE_SHRINK_END
	mx.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	r2.add_child(mx)
	_l_pct = UI.lbl("100%", SS.FS_VALUE, SS.TEXT, true)
	_l_pct.size_flags_vertical = Control.SIZE_SHRINK_END
	r2.add_child(_l_pct)
	rv.add_child(r2)
	var tcs: Array = TROOP_COL[sq.camp]
	_bar_tr = LiveBar.new(tcs[0], tcs[1], 9.0, 4)
	rv.add_child(_bar_tr)
	# 줄 3 —— 사기
	var r3 := UI.hbox(UI.SP_S)
	r3.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ml := UI.lbl("사기", SS.FS_SUB, SS.DIM)
	ml.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	r3.add_child(ml)
	_bar_mo = LiveBar.new(Color("#9fe8bf"), DB.PAL.jade, 5.0, 1)
	r3.add_child(_bar_mo)
	_l_mo = UI.lbl("100", SS.FS_ROW, SS.TEXT, true)
	_l_mo.custom_minimum_size.x = 28
	_l_mo.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	r3.add_child(_l_mo)
	rv.add_child(r3)
	top.add_child(rv)
	v.add_child(top)
	# 고유기 기 —— 이름 · 남은 횟수 · 백분율, 막대, 남은 시간 · 차고 쓰는 때
	if ult != null:
		v.add_child(UI.hair())
		var ub := UI.vbox(4)
		ub.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var uh := UI.hbox(6)
		uh.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var ic := Icons.View.new("burst", SS.GOLD_HI, 13)
		ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		uh.add_child(ic)
		var ul := UI.lbl("고유기", SS.FS_SUB, SS.DIM)
		ul.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		uh.add_child(ul)
		var un := UI.lbl(str(ult.name), SS.FS_ROW, SS.TEXT, true)
		un.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		un.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		un.clip_text = true
		uh.add_child(un)
		_pips = Pips.new(ult_total)
		uh.add_child(_pips)
		_l_ult = UI.lbl("0%", SS.FS_VALUE, SS.GOLD_HI, true)
		_l_ult.custom_minimum_size.x = 44
		_l_ult.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		uh.add_child(_l_ult)
		ub.add_child(uh)
		_bar_ult = LiveBar.new(ULT_BAR[0], ULT_BAR[1], 7.0, 4)
		ub.add_child(_bar_ult)
		_l_ult_sub = UI.lbl("", SS.FS_SUB, SS.DIM)
		_l_ult_sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		ub.add_child(_l_ult_sub)
		v.add_child(ub)
	# 걸린 상태 —— SheetStyle.chip(soft) 결의 칩에 전장 딱지와 같은 기호 (없으면 숨김)
	_st_row = UI.flow(5)
	_st_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_st_row.visible = false
	v.add_child(_st_row)
	card.add_child(v)
	return card


func _st_name(st: String) -> String:
	return str(ST_NAME.get(st, DB.D.STATUS.get(st, {}).get("n", st)))


func _st_col(st: String) -> Color:
	match st:
		"phalanx": return Color("#6fb0ff")
		"moved": return SS.GOLD
	if HUD_KINDS.has(st):
		return BattleView.Hud._icon_col(BattleView.Hud._icon_of(st))
	return Color(str(DB.D.STATUS.get(st, {}).get("c", "#cccccc")))


## 걸린 상태 칩 —— 칩 노드는 모아 두고 기호 · 이름 · 색만 바꾼다 (상태가 바뀔 때만 불린다)
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
			var sb := UI.flat(Color(col, 0.16), Color(col, 0.45), 1, UI.R, 0)
			sb.content_margin_left = 5
			sb.content_margin_right = 7
			sb.content_margin_top = 2
			sb.content_margin_bottom = 2
			pc.add_theme_stylebox_override("panel", sb)
			pc.mouse_filter = Control.MOUSE_FILTER_IGNORE
			var h := UI.hbox(4)
			h.mouse_filter = Control.MOUSE_FILTER_IGNORE
			var ic := StIcon.new(view.hud)
			h.add_child(ic)
			var l := UI.lbl("", SS.FS_SUB, SS.TEXT)
			l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			h.add_child(l)
			pc.add_child(h)
			_st_row.add_child(pc)
			_chips.append({"pc": pc, "sb": sb, "ic": ic, "l": l})
		var chip: Dictionary = _chips[j]
		chip.pc.visible = true
		chip.sb.bg_color = Color(col, 0.16)
		chip.sb.border_color = Color(col, 0.45)
		var sic: StIcon = chip.ic
		sic.kind = s
		sic.col = col
		sic.queue_redraw()
		chip.l.text = nm
		_fc(chip.l, col.lightened(0.3))
		j += 1
	for x in range(j, _chips.size()):
		_chips[x].pc.visible = false
	_st_row.visible = j > 0


# ───────── 이번 전투 ─────────

## 네 칸 —— SheetStyle.stat_cells 와 같은 먹 판 · 세로 가는 선 · 기호 20 · 큰 숫자(FS_STAT). 두 줄로 (피해 숫자가 일곱 자리까지 들어가게)
func _build_contrib() -> Control:
	var pc := PanelContainer.new()
	var sb := UI.flat(SS.WELL, SS.LINE, 1, UI.R, 0)
	sb.set_content_margin_all(1)
	pc.add_theme_stylebox_override("panel", sb)
	pc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var v := UI.vbox(0)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var items := [["dmg", "준 피해", "blade", SS.GOLD], ["kill", "격파", "target", C_KILL], ["heal", "치료", "heart", C_HEAL], ["taken", "받은 피해", "shield_crack", SS.WARN]]
	for row in 2:
		if row > 0:
			var hm := MarginContainer.new()
			hm.add_theme_constant_override("margin_left", 10)
			hm.add_theme_constant_override("margin_right", 10)
			hm.mouse_filter = Control.MOUSE_FILTER_IGNORE
			hm.add_child(UI.hair())
			v.add_child(hm)
		var h := UI.hbox(0)
		h.mouse_filter = Control.MOUSE_FILTER_IGNORE
		for col_i in 2:
			if col_i > 0:
				var vm := MarginContainer.new()
				vm.add_theme_constant_override("margin_top", 8)
				vm.add_theme_constant_override("margin_bottom", 8)
				vm.mouse_filter = Control.MOUSE_FILTER_IGNORE
				vm.add_child(UI.hair(true))
				h.add_child(vm)
			var it: Array = items[row * 2 + col_i]
			var cell := MarginContainer.new()
			cell.add_theme_constant_override("margin_top", 6)
			cell.add_theme_constant_override("margin_bottom", 6)
			cell.add_theme_constant_override("margin_left", 12)
			cell.add_theme_constant_override("margin_right", 8)
			cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
			var hb := UI.hbox(8)
			hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
			var iv := Icons.View.new(str(it[2]), it[3], 20)
			iv.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			hb.add_child(iv)
			var cvb := UI.vbox(-3)
			cvb.mouse_filter = Control.MOUSE_FILTER_IGNORE
			cvb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			var vr := UI.hbox(5)
			vr.mouse_filter = Control.MOUSE_FILTER_IGNORE
			var n := Num.new(SS.FS_STAT, SS.TEXT, Color(SS.DIM, 0.55))
			_n[it[0]] = n
			vr.add_child(n)
			if it[0] == "dmg":
				_l_rank = UI.lbl("", SS.FS_SUB, SS.GOLD_HI, true)
				_l_rank.size_flags_vertical = Control.SIZE_SHRINK_CENTER
				vr.add_child(_l_rank)
			cvb.add_child(vr)
			var ll := UI.lbl(str(it[1]), SS.FS_TAG, SS.DIM)
			if it[0] == "dmg":
				_l_share = ll
			cvb.add_child(ll)
			hb.add_child(cvb)
			cell.add_child(hb)
			h.add_child(cell)
		v.add_child(h)
	pc.add_child(v)
	return pc


# ───────── 전장의 개성 ─────────

## 고유 특기의 개성 —— 띠 판(ACCENT · 금): 꼬리표 · 이름 | 이번 전투 발동 횟수, 개성 문장, 2단 수치 칩, 최근 발동 한 줄
func _build_sig() -> Control:
	var sg = DB.PSV.get("sig", {}).get(DB.person(k))
	var ut: Dictionary = {}
	for t in DB.trait_list(k):
		if t.unique:
			ut = t
			break
	if not (sg is Array and sg.size() >= 2) and ut.is_empty():
		return null
	var card := SS.Plate.new(SS.GOLD, SS.ACCENT, "seal")
	var v := UI.vbox(6)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var hd := UI.hbox(UI.SP_S)
	hd.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var lv := UI.vbox(1)
	lv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lv.add_child(tag("전장의 개성", "seal", SS.GOLD, "고유 특기"))
	var nm := str(ut.name) if not ut.is_empty() else str(sg[0])
	lv.add_child(UI.lbl(nm, SS.FS_VALUE, SS.GOLD_HI, true))
	hd.add_child(lv)
	var cv := UI.vbox(-4)      # 오른쪽 —— 이번 전투 발동 횟수 (늘 켜진 개성이면 '상시')
	cv.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	cv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sig_cnt = UI.lbl("0", SS.FS_STAT, SS.GOLD_HI, true)
	_sig_cnt.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	cv.add_child(_sig_cnt)
	_sig_lab = UI.lbl("이번 전투 발동", SS.FS_TAG, SS.DIM)
	_sig_lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	cv.add_child(_sig_lab)
	hd.add_child(cv)
	v.add_child(hd)
	var line := str(sg[1]) if sg is Array and sg.size() >= 2 else (str(ut.d) as String).get_slice(" —— ", 0)
	var ll := UI.rich(hl(line), SS.FS_SUB)
	ll.add_theme_color_override("default_color", SS.LABEL)
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
	_sig_last = UI.lbl("", SS.FS_TAG, SS.DIM)
	_sig_last.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
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

## 기록 판 —— SheetStyle.info_table 과 같은 판(PLAIN) · 들여 쓴 가는 선, 줄은 정보 행(info_row)과 같은 칸 나눔:
## [배지 · 시각] [사건 이름 / 덧말] [오른쪽 수치 + 그 이름]. 줄 노드는 모아 두고 글만 바꾼다
func _build_timeline() -> Control:
	var v := UI.vbox(UI.SP_S)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tl_plate = SS.Plate.new(SS.GOLD, SS.PLAIN, "", Vector4(0, 2, 0, 2))
	_tl_box = UI.vbox(0)
	_tl_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tl_plate.add_child(_tl_box)
	v.add_child(_tl_plate)
	_tl_empty = UI.lbl("아직 큰 일이 없다 —— 고유기 · 격파 · 크게 맞은 순간 · 걸린 상태가 여기 쌓인다", SS.FS_SUB, SS.DIM)
	UI.wrap_text(_tl_empty)
	v.add_child(_tl_empty)
	_tl_more = SS.quiet_btn(UI.btn_small("", func():
		_tl_all = not _tl_all
		_tl_dirty = true
		_rebuild_timeline()))
	_tl_more.add_theme_font_size_override("font_size", SS.FS_SUB)
	_tl_more.visible = false
	v.add_child(_tl_more)
	return v


func _clock(tm: float) -> String:
	var s := int(BattleView.OPEN_RT + tm)
	return "%d:%02d" % [s / 60, s % 60]


## 기록 한 줄 —— opt: st(상태 키 · 배지 그림) · tcol(이름 색) · detail · num · ncol · nlab
func _add(tm: float, col: Color, icon: String, title: String, opt := {}) -> Dictionary:
	var e := {"tm": tm, "col": col, "icon": icon, "st": str(opt.get("st", "")), "title": title, "tcol": opt.get("tcol", SS.TEXT),
		"detail": str(opt.get("detail", "")), "num": str(opt.get("num", "")), "ncol": opt.get("ncol", SS.VAL), "nlab": str(opt.get("nlab", ""))}
	_entries.append(e)
	_tl_dirty = true
	return e


func _rebuild_timeline() -> void:
	_tl_dirty = false
	var rl: Label = _tl_sec.get_child(_tl_sec.get_child_count() - 1)      # 섹션 머리 오른쪽 글
	rl.text = ("%d건" % _entries.size()) if not _entries.is_empty() else " "
	_tl_empty.visible = _entries.is_empty()
	_tl_plate.visible = not _entries.is_empty()
	var cap := TL_ALL if _tl_all else TL_SHOW
	var n := mini(cap, _entries.size())
	var order := range(_entries.size())
	order.sort_custom(func(x, y): return float(_entries[x].tm) > float(_entries[y].tm) or (is_equal_approx(float(_entries[x].tm), float(_entries[y].tm)) and x > y))
	for j in n:
		var e: Dictionary = _entries[order[j]]      # 최근 것이 위
		if j >= _rows.size():
			_rows.append(_new_row())
		var row: Dictionary = _rows[j]
		row.m.visible = true
		row.hair.visible = j > 0
		var bd: Badge = row.badge
		bd.set_mark(e.col, str(e.icon), str(e.st))
		row.t.text = _clock(float(e.tm))
		row.title.text = UI.keep_words(str(e.title))
		_fc(row.title, e.tcol)
		row.detail.text = UI.keep_words(str(e.detail))
		row.detail.visible = str(e.detail) != ""
		row.nv.visible = str(e.num) != ""
		row.num.text = str(e.num)
		_fc(row.num, e.ncol)
		row.nlab.text = str(e.nlab)
		row.nlab.visible = str(e.nlab) != ""
	for j in range(n, _rows.size()):
		_rows[j].m.visible = false
		_rows[j].hair.visible = false
	var rest := _entries.size() - n
	_tl_more.visible = rest > 0 or _tl_all
	_tl_more.text = "접기 ▴" if _tl_all else "이전 기록 %d건 더 보기 ▾" % rest


## 기록 줄 하나 —— SheetStyle.info_row 의 여백(10 · 8 · 6 · 6) · 칸 사이(GAP) · 배지(22) · 오른쪽 수치 칸 그대로, 글을 바꿀 수 있게 직접 만든다
func _new_row() -> Dictionary:
	var hm := MarginContainer.new()      # 줄 사이 가는 선 (info_table 처럼 양옆 10 들여)
	hm.add_theme_constant_override("margin_left", 10)
	hm.add_theme_constant_override("margin_right", 10)
	hm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hm.add_child(UI.hair())
	_tl_box.add_child(hm)
	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_left", 10)
	m.add_theme_constant_override("margin_right", 10)
	m.add_theme_constant_override("margin_top", 6)
	m.add_theme_constant_override("margin_bottom", 6)
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var h := UI.hbox(SS.GAP)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var lab := UI.hbox(6)
	lab.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lab.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var bd := Badge.new(view.hud)
	lab.add_child(bd)
	var tl := UI.lbl("", SS.FS_SUB, SS.DIM)
	tl.custom_minimum_size.x = 30
	tl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	lab.add_child(tl)
	h.add_child(lab)
	var vv := UI.vbox(1)
	vv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vv.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var ttl := UI.lbl("", SS.FS_ROW, SS.TEXT, true)
	ttl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vv.add_child(ttl)
	var dl := UI.lbl("", SS.FS_SUB, SS.DIM)
	dl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vv.add_child(dl)
	h.add_child(vv)
	var nv := UI.vbox(-3)
	nv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	nv.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var nl := UI.lbl("", SS.FS_VALUE, SS.VAL, true)
	nl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	nv.add_child(nl)
	var nb := UI.lbl("", SS.FS_TAG, SS.DIM)
	nb.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	nv.add_child(nb)
	h.add_child(nv)
	m.add_child(h)
	_tl_box.add_child(m)
	return {"m": m, "hair": hm, "badge": bd, "t": tl, "title": ttl, "detail": dl, "nv": nv, "num": nl, "nlab": nb}


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
					_ult_e.num = Battle.num(_ult_e.dmg)
					_ult_e.nlab = "적 %d부대" % _ult_e.tg.size()
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
						_heal_e = _add(tm, C_HEAL, "heart", ("%s의 치료" % _nm(hk)) if hk != "" else "치료", {"ncol": SS.VAL, "nlab": "병력"})
						_heal_e.by = hk
						_heal_e.n = hn
						_heal_e.tm2 = tm
					_heal_e.num = "+" + Battle.num(_heal_e.n)
					_tl_dirty = true
			"ult":
				if a == key:
					_ult_tm.append(tm)
					_ult_e = _add(tm, C_GLOW, "burst", "고유기 『%s』" % str(e.get("name", "")), {"tcol": SS.GOLD_HI,
						"detail": "인연 합동" if e.has("mates") else ""})
					_ult_e.dmg = 0.0
					_ult_e.tg = {}
					_ult_g = g
			"rout":
				if f == key:
					var why := str(e.get("t", "")).get_slice("의 군세가 ", 1)      # 엔진 문장의 까닭 그대로 ("사기 24에서 끝내 패주했다" · "병력이 다해 무너졌다" …)
					_add(tm, DB.PAL.seal.lightened(0.15), "shield_crack", why if why != "" else "무너졌다", {"tcol": SS.WARN})
				elif str(_last_hit.get(f, "")) == key and f.left(1) != key.left(1):
					_kills += 1
					_add(tm, C_KILL, "target", "%s 격파" % _nm(f), {"detail": "부대를 무너뜨렸다"})
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
				var good := ST_GOOD.has(str(st))
				var x: Dictionary = _st_last.get(st, {})
				if x.is_empty() or tm - float(x.get("end", -99.0)) > 3.0:      # 3초 안에 다시 걸리면 같은 줄을 잇는다 (도발 · 방진이 깜빡여도 줄이 쌓이지 않게)
					var col := _st_col(str(st))
					x = _add(tm, col, "", _st_name(str(st)), {"st": str(st), "tcol": col.lightened(0.3)})
					_st_last[st] = x
				x.detail = "버티는 중" if str(st) == "undying" else ("펼쳤다" if good else "걸려 있다")
				x.num = ""
				x.nlab = ""
				_tl_dirty = true
				_st_open[st] = x
		for st in _prev_st:
			if not sts.has(st) and _st_open.has(st):
				var x: Dictionary = _st_open[st]
				_st_open.erase(st)
				var dur := tm - float(x.tm)
				x.end = tm
				x.detail = "풀렸다"
				x.num = DB.sec_str(dur) if dur >= 1.0 else "잠깐"
				x.ncol = SS.TEXT
				x.nlab = "동안" if dur >= 1.0 else ""
				_tl_dirty = true
		_prev_st = sts.duplicate()
	if alive:
		var tr := float(s[0]) / _mx
		var mo := float(s[1])
		if tr < 0.3 and not _crisis_tr and tr > 0.0:
			_crisis_tr = true
			_add(tm, SS.WARN, "hourglass", "병력이 꺾였다", {"detail": "30% 아래 —— 위태롭다", "num": "%d%%" % roundi(tr * 100.0), "ncol": SS.WARN, "nlab": "남은 병력"})
		elif tr > 0.45:
			_crisis_tr = false
		if mo < 30.0 and not _crisis_mo:
			_crisis_mo = true
			_add(tm, SS.WARN, "banner", "사기가 꺾였다", {"detail": "패주 위기", "num": str(roundi(mo)), "ncol": SS.WARN, "nlab": "사기"})
		elif mo > 45.0:
			_crisis_mo = false
		if not _prev_alive:
			_add(tm, C_HEAL, "up", "다시 일어섰다", {"tcol": SS.VAL})
	_prev_alive = alive


## 크게 맞음 —— 한 행동(같은 묶음)에 병력 BIG_HIT 넘게 잃으면 한 줄 (같은 묶음이 더 치면 그 줄의 수치를 늘린다)
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
		_hit_e = _add(tm, C_GLOW.lerp(SS.WARN, 0.5) if ultg else SS.WARN, "burst" if ultg else "blade", "", {"ncol": SS.WARN, "nlab": "병력"})
	_hit_e.title = "%s의 %s" % [_nm(who), what if what != "" else "일격"]
	_hit_e.detail = "크게 맞았다" + (" · 치명타" if e.get("crit", false) and what == "" else "")
	_hit_e.num = "−" + Battle.num(_hit_amt)
	_tl_dirty = true


## 몰아 맞음 —— 한 방은 작아도 PRESS_T 초 안에 병력 PRESS 넘게 잃으면 '집중 공격' 한 줄 (누구에게 맞았는지 많이 친 순)
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
		_pr_e = _add(tm, SS.WARN.lerp(SS.LABEL, 0.3), "swirl", "집중 공격", {"ncol": SS.WARN})
	var who: Array = _pr_by.keys()
	who.sort_custom(func(x, y): return float(_pr_by[x]) > float(_pr_by[y]))
	_pr_e.detail = " · ".join(who.slice(0, 2).map(func(x): return _nm(str(x))))
	_pr_e.num = "−" + Battle.num(_pr_amt)
	_pr_e.nlab = "%d초 동안" % maxi(1, ceili(tm - _pr_t0))
	_tl_dirty = true


func _sig_event(e: Dictionary, tm: float) -> void:
	_sig_n += 1
	var stx := str(e.get("t", ""))
	var head := stx.get_slice(" —— ", 0)
	var nm := head.substr(head.rfind("의 ") + 2) if head.find("의 ") >= 0 else head
	var tail := stx.get_slice(" —— ", 1) if stx.find(" —— ") >= 0 else ""
	_sig_last_txt = "최근 %s · %s%s" % [_clock(tm), nm, (" —— " + tail) if tail != "" else ""]
	var last: Dictionary = _entries.back() if not _entries.is_empty() else {}
	if str(last.get("kind", "")) == "sig" and str(last.get("nm", "")) == nm and tm - float(last.get("tm2", 0.0)) < 12.0:      # 같은 개성이 잇달아 —— 한 줄에 ×N
		last.cnt += 1
		last.tm2 = tm
		last.num = "×%d" % int(last.cnt)
		_tl_dirty = true
		return
	var x := _add(tm, SS.GOLD, "seal", "『%s』" % nm, {"tcol": SS.GOLD_HI, "detail": tail, "ncol": SS.GOLD_HI})
	x.kind = "sig"
	x.nm = nm
	x.cnt = 1
	x.tm2 = tm


# ───────── 갱신 ─────────

## 글자색 —— 같은 색이면 건너뛴다 (0.2초마다 덮어쓰면 테마 알림이 계속 난다)
func _fc(l: Label, col: Color) -> void:
	if l.get_meta("fc", Color(0, 0, 0, 0)) != col:
		l.set_meta("fc", col)
		l.add_theme_color_override("font_color", col)


func _refresh(first: bool) -> void:
	var P := DB.PAL
	if not is_instance_valid(view) or view.field == null or view.field.squads.get(key) != sq:
		_freeze()
		return
	if not is_same(view.res, _res):      # 직접 지휘로 다시 계산했다 —— 앞부분은 같다 (같은 시드 · 입력). 길이만 본다
		_res = view.res
		_scan = mini(_scan, view.res.get("ev", []).size())
	_scan_events()
	var done: bool = view.finished
	_l_clock.text = ("%s · 전투 %s" % [_pos, view.clock_text()]) if _pos != "" else "전투 " + view.clock_text()
	# 병력 · 사기
	var tr := sq.troops
	_l_tr.text = Battle.num(tr)
	var ratio := clampf(tr / _mx, 0.0, 1.0)
	_l_pct.text = "%d%%" % roundi(ratio * 100.0)
	_fc(_l_pct, SS.TEXT if ratio >= 0.5 else (SS.GOLD_HI if ratio >= 0.3 else SS.WARN))
	_bar_tr.set_value(ratio, first)
	var mo := sq.morale
	_l_mo.text = str(roundi(mo))
	_fc(_l_mo, SS.TEXT if mo >= 50.0 else (SS.GOLD_HI if mo >= 30.0 else SS.WARN))
	_bar_mo.set_value(mo / 100.0, first)
	if mo >= 60.0:
		_bar_mo.set_colors(Color("#9fe8bf"), P.jade)
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
		_pill.set_state("전투 종료 · " + ("무승부" if draw else ("승전" if mine else "패전")), SS.GOLD_HI if (mine and not draw) else SS.LABEL, false)
	elif word != "":
		_pill.set_state(word, SS.WARN, false)
	elif sq.contact:
		_pill.set_state("교전 중", Color("#ff8a5a"), true)
	elif sq.moving:
		_pill.set_state("이동 중", SS.LABEL, true)
	else:
		_pill.set_state("대기", SS.DIM, true)
	# 걸린 상태 칩 —— 화면이 반영한 마지막 사건의 상태 (늦게 풀린 고유기 묶음이 옛 상태를 덮어쓴 메달보다 정확). 바뀔 때만 다시
	var sts: Array = _prev_st if sq.alive else []
	var skey := ",".join(PackedStringArray(sts.map(func(x): return str(x))))
	if skey != _st_key:
		_st_key = skey
		_rebuild_status(sts)
	if ult != null:
		_refresh_ult(done)
	# 이번 전투
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
		var tot := 0.0
		for kk in _dmg_by:
			if str(kk).left(1) == key.left(1):
				tot += float(_dmg_by[kk])
				if kk != key and float(_dmg_by[kk]) > dmg:
					rank += 1
		_l_rank.text = "%d위" % rank
		_fc(_l_rank, SS.GOLD_HI if rank == 1 else SS.DIM)
		_l_share.text = "준 피해 · %s의 %d%%" % ["아군" if sq.camp == "A" else "적군", roundi(dmg / maxf(1.0, tot) * 100.0)]
	else:
		_l_rank.text = ""
		_l_share.text = "준 피해"
	# 개성
	if _sig_cnt != null:
		if _sig_n > 0 or _sig_ever:
			_sig_cnt.text = ("×%d" % _sig_n) if _sig_n > 0 else "—"
			_fc(_sig_cnt, SS.GOLD_HI if _sig_n > 0 else Color(SS.DIM, 0.7))
			_sig_lab.text = "이번 전투 발동" if _sig_n > 0 else "아직 발동 전"
		else:
			_sig_cnt.text = "상시"
			_fc(_sig_cnt, SS.LABEL)
			_sig_lab.text = "늘 켜진 개성"
		if _sig_last_txt != "":
			_sig_last.text = UI.keep_words(_sig_last_txt)
			_sig_last.visible = true
	if _tl_dirty:
		_rebuild_timeline()
	if done:
		_ended = true
		set_process(false)


## 고유기 —— 기 · 남은 횟수 · 남은 시간. 시각은 화면 시계(엔진 0초 = OPEN_RT)로, 대기 = 장수 대기 × 기질 배율 (재사용은 × reult 배율, RtBattle.can_ult · _reult_ok 와 같은 식)
func _refresh_ult(done: bool) -> void:
	var lv: Array = view.unit_live(key)
	var gauge := clampf(float(lv[0]), 0.0, 100.0)
	var left := int(lv[1]) if view.live_e != null else ult_total
	var winding: bool = lv[2]
	_pips.set_left(left)
	_bar_ult.set_value(gauge / 100.0)
	var td: PackedStringArray = str(Battle.TEMPER_DESC.get(temper, "")).split(". ")
	var fill_txt := td[0] if td.size() > 0 else ""
	var use_txt := td[1].trim_suffix(".") if td.size() > 1 else ""
	var now := maxf(0.0, (view.end_clock if view.end_clock > 0.0 else view.clock) - BattleView.OPEN_RT)
	var tw := 1.0
	if Battle.temper_enabled and Battle.TEMPER.has(temper):
		tw = float(Battle.TEMPER[temper].wait)
	var wait := float(ult.get("wait", 14.0)) * tw
	var ready_at := wait if _ult_tm.is_empty() else float(_ult_tm.back()) + wait * float(Battle.reult_temper.get(temper, Battle.reult_wait))
	var sub := ""
	var glow := false
	var pct := "%d%%" % roundi(gauge)
	if not sq.alive:
		pct = "—"
	if done:
		sub = ("전투가 끝났다 —— %d번 썼다" % _ult_tm.size()) if not _ult_tm.is_empty() else "전투가 끝났다 —— 쓰지 못했다"
	elif not sq.alive:
		sub = "쓰러져 더는 쓸 수 없다"
	elif left <= 0:
		sub = "%d번 다 썼다" % ult_total
		pct = "끝"
	elif _prev_st.has("seal"):
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
	_fc(_l_ult, SS.GOLD_HI if left > 0 and sq.alive else SS.DIM)
	_l_ult_sub.text = UI.keep_words(sub)
	_fc(_l_ult_sub, SS.GOLD_HI if glow else SS.DIM)


## 다른 전투로 넘어갔거나 전장이 사라졌다 —— 마지막 모습 그대로 멈춘다
func _freeze() -> void:
	_ended = true
	set_process(false)
	if _pill != null:
		_pill.set_state("전투 끝", SS.LABEL, false)
	if _bar_ult != null:
		_bar_ult.set_glow(false)


# ───────── 장수 정보 (전투 시작 기준) —— 상세창과 같은 부품 ─────────

func _build_info() -> void:
	var ss: Dictionary = view.start_stats(key)
	var iv := UI.vbox(UI.SP_S)
	iv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	iv.add_child(SS.section("장수 정보", "전투 시작 기준"))
	iv.add_child(_build_stats(ss))
	if ult != null:
		var tb = gs._temper_box(c, ult, 11, true)
		if tb != null:
			iv.add_child(tb)
	iv.add_child(_build_gear(ss))
	add_child(iv)
	# 고유 능력 —— 상세창 능력 카드 그대로 (고유기 주인공 판 · 위세 · 패업). 고유 특기는 위 '전장의 개성' 판이 맡는다
	var ab := UI.vbox(UI.SP_S)
	ab.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if ult != null:
		ab.add_child(gs._ult_card(k, ult))
	if DB.AURA.has(k):
		var al := DB.aura_list(k)
		var chips := []
		for gr in al.groups:
			for it in gr.items:
				chips.append([it[1], "%s %s" % [gr.who, it[0]]])
		ab.add_child(gs._abil_card("기인" if DB.is_kiin(k) else "위세", str(DB.AURA[k].n), str(al.text), chips, DB.tier_color(k)))
		if DB.AURA[k].has("paeup"):
			var pa: Dictionary = DB.AURA[k].paeup
			var pc := []
			if str(pa.cond) != "none":
				var cw: String = str(pa.get("what", "화상을 거는 장수" if str(pa.cond) == "burn" else "상태이상을 거는 장수"))
				pc.append(["%d명 이상" % int(pa.need), "아군에 %s (자신 외)" % cw])
			ab.add_child(gs._abil_card("패업", str(pa.n), str(pa.get("d", "")), pc, DB.PAL.bamboo))
	if ab.get_child_count() > 0:
		ab.add_child(SS.section("고유 능력"))
		ab.move_child(ab.get_child(ab.get_child_count() - 1), 0)
		add_child(ab)
	# 기술 —— 상세창과 같은 효과 · 수치 표 (자주 쓰는 기술 + 일반 기술)
	var mk := Battle.minor_kind(k)
	var sk_items := []
	if mk != "":
		sk_items.append(gs._kv_box("[color=#D9A64B][b]『%s』[/b][/color]" % Battle.minor_def(mk).n, GameScreen.minor_when(k), GameScreen.minor_desc(k, false), DB.PAL.bamboo_dim, 13))
	for x in c.get("sks", []):
		sk_items.append(gs._kv_box("[color=#D9A64B][b]『%s』[/b][/color]" % x.n, DB.sk_when(x, c), DB.skill_desc(c, x), DB.PAL.bamboo_dim, 13))
	if c.get("sks", []).size() >= 2:
		sk_items.append(UI.rich("[color=#A89574]%s[/color]" % DB.SK_SHARE_NOTE, UI.FS_CAP))
	if not sk_items.is_empty():
		var sp := SS.Plate.new(SS.GOLD, SS.PLAIN, "", Vector4(12, 0, 12, 0))
		sp.add_child(gs._kv_stack(sk_items))
		add_child(_sect(SS.section("기술", "%d개" % (c.get("sks", []).size() + (1 if mk != "" else 0))), sp))
	# 특기 —— 상세창과 같은 계열 기호 칸 격자 + 고른 특기 설명 (고유 특기는 위)
	var tn := DB.trait_list(k).filter(func(x): return not x.unique)
	if not tn.is_empty():
		add_child(_sect(SS.section("특기", "%d개" % tn.size()), gs._trait_icons(tn)))


## 공격 · 방어 · 속도 —— SheetStyle 능력치 칸 그대로, 큰 숫자 = 기본 · 옆 작은 글 = 이 전투에서 실제로 달라진 만큼(버프 − 적 깎기).
## 아래 칩 = 달라진 까닭 (진형 자리 배율 · 자리 선호 · 그 밖)
func _build_stats(ss: Dictionary) -> Control:
	var v := UI.vbox(6)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var magic: bool = DB.INT_TAGS.has(c.tag)
	var ac := SS.ATK_INT if magic else SS.ATK
	var items := []
	for pair in [["blade", "책략" if magic else "공격", "atk"], ["shield", "방어", "def"], ["boot", "속도", "spd"]]:
		var base: float = float(c[pair[2]])
		var got: float = float(ss[pair[2]][1]) if ss.has(pair[2]) else base
		var d := roundi(got - base)
		var it := {"icon": pair[0], "label": pair[1], "value": str(roundi(base)), "col": ac if pair[2] == "atk" else SS.TEXT, "icon_col": ac if pair[2] == "atk" else SS.LABEL}
		if d != 0:
			it["bonus"] = ("+%d" % d) if d > 0 else ("−%d" % absi(d))
			it["bonus_col"] = SS.VAL if d > 0 else SS.WARN
		items.append(it)
	v.add_child(SS.stat_cells(items))
	if ss.is_empty():
		v.add_child(SS.note("온라인 재생은 버프 수치를 계산하지 않는다 —— 기본 수치만", SS.DIM, "news"))
		return v
	var f := UI.flow(5)
	f.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var lm: Dictionary = DB.D.LINE.get(ss.line, {})
	if not lm.is_empty():
		f.add_child(SS.chip("%s 공격 ×%.2f · 방어 ×%.2f" % [ss.line, float(lm["int"] if Battle.is_caster(c) else lm.atk), float(lm["def"])], SS.LABEL, "well"))
	var z := DB.aff_of(c.tag, ss.line, ss.side)
	if z != "":
		f.add_child(SS.chip("자리 " + ("선호" if z == "pref" else "어색"), SS.VAL if z == "pref" else SS.WARN, "soft"))
	f.add_child(SS.chip("단체 특기 · 위세 · 사기", SS.LABEL, "well", "up"))
	v.add_child(f)
	return v


## 장비 —— SheetStyle 정보 표: 무기 · 갑옷 한 줄씩 (이름 · 등급, 효과는 칩). 빈 칸은 「없음」
func _build_gear(ss: Dictionary) -> Control:
	var gear := [ss.get("item"), ss.get("item2")]
	if ss.is_empty():
		for r in view.res.get("roster", []):
			if str(r.get("key", "")) == key:
				gear = [r.get("item"), r.get("item2")]
				break
	var rows := []
	for si in 2:
		var sl: String = ["weapon", "armor"][si]
		var iid = gear[si]
		var icon := "blade" if si == 0 else "shield"
		if iid != null and DB.IT.has(iid):
			var it: Dictionary = DB.IT[iid]
			var col := UI.item_col(iid).lightened(0.2)
			var parts := Array(UI.item_text(iid).replace(" / ", " · ").split(" · ", false))
			rows.append(SS.info_row(icon, DB.ISLOT_NAME[sl], str(it.name), {"value_col": col, "icon_col": col, "tag": str(it.grade), "chips": parts, "chip_col": SS.VAL}))
		else:
			rows.append(SS.info_row(icon, DB.ISLOT_NAME[sl], "없음", {"value_col": Color(SS.DIM, 0.7)}))
	return SS.info_table(rows)


# ───────── 점검 ─────────

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
		if n is Label and (n as Label).clip_text and (n as Label).text_overrun_behavior == TextServer.OVERRUN_NO_TRIMMING:
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
		print("  기록 %s %s · %s · %s %s" % [_clock(float(e.tm)), str(e.title), str(e.detail), str(e.num), str(e.nlab)])
