class_name BattleReport
extends PanelContainer
## 전투 결과표 —— 덱이 잘 굴렀는지 보는 화면 (롤토체스 피해 집계). 11/1 덱 감상 전투.
## 장수마다 준 피해 · 받은 피해 막대와 격파 · 기술 · 고유기 횟수. 아군 / 적을 바꿔 본다.
## 11/7 사용자: 토벌 대군(적 20부대)은 표가 화면을 넘쳐 [종료] 버튼이 줄 위에 겹치고 내릴 수도 없었다 ——
##   머리줄 · 아군/적군 탭 · 범례는 고정하고 장수 줄만 스크롤(UI.scroll = 손가락 끌기 TouchScroll).
##   표 높이는 두 진영 중 긴 쪽에 맞추되 max_h(보여 주는 쪽이 화면에 맞춰 준다)를 넘지 않는다 —— 탭을 바꿔도 표 · 버튼이 움직이지 않게.
##   긴 이름('동오덕왕 엄백호')은 … 으로 줄이고, 수치는 막대 오른쪽 끝에 테두리 글씨로 (짧은 막대 위에 겹쳐 읽기 어려웠다).

const ROW_H := 40.0
const ROW_SEP := 4.0
const LINE_H := 24.0      # 덱 요약 · 덱 연쇄 한 줄 (어림)

var res: Dictionary
var camp := "A"
var max_h := 700.0        # 표 전체(머리줄 ~ 범례) 최대 높이
var _body: VBoxContainer
var _tabs: Control
var _scroll: ScrollContainer


static func make(r: Dictionary) -> BattleReport:
	var b := BattleReport.new()
	b.res = r
	return b


func _ready() -> void:
	add_theme_stylebox_override("panel", UI.flat(Color(0.06, 0.07, 0.11, 1.0), DB.PAL.ink3, 1, 10, 12))      # 불투명 —— 뒤의 종료 문구가 비쳐 글씨가 겹쳤다
	mouse_filter = Control.MOUSE_FILTER_STOP
	var v := UI.vbox(8)
	add_child(v)
	var col: Color = DB.PAL.jade if res.win else DB.PAL.seal
	var head := UI.hbox(8)
	head.add_child(UI.lbl("무승부" if res.draw else ("승전" if res.win else "패전"), 20, col, true))
	var sub := UI.lbl("잔존 %d 대 %d · %s" % [res.left, res.eLeft, _len_text()], 13, DB.PAL.bamboo_dim)
	sub.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	sub.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	head.add_child(sub)
	v.add_child(head)
	_tabs = Control.new()
	v.add_child(_tabs)
	_scroll = UI.scroll()
	v.add_child(_scroll)
	_body = UI.vbox(int(ROW_SEP))
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_body)
	v.add_child(UI.rich("[color=#%s]■[/color] 준 피해   [color=#c0503f]■[/color] 받은 피해   ·   격파 · 기술 · 고유기   ·   깎기 +피해" % DB.PAL.gold.to_html(false), 11))
	_fill()
	await get_tree().process_frame      # 한 번 자리 잡은 뒤 —— 표 틀(머리줄 · 탭 · 범례 · 여백) 높이를 재고 줄 칸 높이를 정한다
	if not is_inside_tree():
		return
	var chrome := size.y - _scroll.size.y
	var want := maxf(_body.size.y, _est_h("B" if camp == "A" else "A"))      # 지금 진영은 잰 값, 다른 진영은 어림
	_scroll.custom_minimum_size.y = clampf(want, 80.0, maxf(80.0, max_h - chrome))


## 진영의 줄 높이 어림 —— 장수 줄 + 요약 · 연쇄 글줄
func _est_h(cp: String) -> float:
	var n := _rows(cp).size()
	var lines := 0
	if cp == "A" and _deck_summary() != "":
		lines += 2
	if not res.get("chains", {}).get(cp, {}).is_empty():
		lines += 1
	return n * ROW_H + maxi(0, n - 1) * ROW_SEP + lines * (LINE_H + ROW_SEP)


func _len_text() -> String:
	var t: float = res.get("view_len", res.get("len", 0.0))      # 11/3 화면 시계(위쪽 0:00)와 같은 시간 —— 엔진 시간은 화면에서 늘려 보여 준다
	if t <= 0:
		return "%d턴" % res.turns
	return "%d:%02d" % [int(t) / 60, int(t) % 60]


func _fill() -> void:
	var nt := UI.segmented([["A", "아군"], ["B", "적군"]], camp, func(k):
		camp = k
		_fill())
	_tabs.replace_by(nt)
	_tabs = nt
	_scroll.scroll_vertical = 0      # 탭을 바꾸면 맨 위부터
	for c in _body.get_children():
		c.queue_free()
	if camp == "A":      # 11/6 #16 덱 설계 요약 —— "내 덱의 무엇이 통했는지" 한 줄 (데일리 진행의 확인 순간)
		var ds := _deck_summary()
		if ds != "":
			_body.add_child(UI.rich(ds, 13))
	var ch: Dictionary = res.get("chains", {}).get(camp, {})
	if not ch.is_empty():
		var names := ch.keys()
		names.sort_custom(func(x, y): return ch[x] > ch[y])
		var parts := []
		for k in names.slice(0, 5):
			parts.append("[b]%s[/b] ×%d" % [k, int(ch[k])])
		_body.add_child(UI.rich("[color=#%s]덱 연쇄[/color]  %s" % [("ffd257" if camp == "A" else "ff7a66"), "   ".join(parts)], 13))
	var rows := _rows(camp)
	var top_d := 1.0
	var top_t := 1.0
	for r in rows:
		top_d = maxf(top_d, r.dmg)
		top_t = maxf(top_t, r.taken)
	for r in rows:
		_body.add_child(Row.make(r, top_d, top_t))


## 점검용 —— 줄 칸을 그 위치로 내린다 (tests/ui_shots --rscroll)
func scroll_to(y: int) -> void:
	_scroll.scroll_vertical = y


## 내 덱 설계 요약 —— 위세(살았는지) · 가장 많이 터진 연쇄 · 고유기 횟수 · 격파 수
func _deck_summary() -> String:
	var final: Array = res.ev[res.ev.size() - 1].s
	var auras := []
	var ults := 0
	var kills := 0
	for e in res.ev:
		if e.get("fx") == "ult" and str(e.get("a", "")).begins_with("A"):
			ults += 1
	for i in res.roster.size():
		var u: Dictionary = res.roster[i]
		if u.camp != "A":
			continue
		kills += int(u.get("kills", 0))
		if DB.AURA.has(u.id):
			auras.append("[color=#%s]『%s』[/color]%s" % [DB.tier_color(u.id).to_html(false), DB.AURA[u.id].n, "" if final[i][2] == 1 else "(무너짐)"])
	var parts := []
	if not auras.is_empty():
		parts.append("위세 " + " ".join(auras.slice(0, 3)))
	var ch: Dictionary = res.get("chains", {}).get("A", {})
	if not ch.is_empty():
		var best := ""
		for k in ch:
			if best == "" or int(ch[k]) > int(ch[best]):
				best = k
		parts.append("연쇄 [b]%s[/b] ×%d" % [best, int(ch[best])])
	if ults > 0:
		parts.append("고유기 %d회" % ults)
	if kills > 0:
		parts.append("격파 %d" % kills)
	if parts.is_empty():
		return ""
	return "[color=#ffd257]내 덱[/color]  " + "  ·  ".join(parts)


## 진영의 장수들 —— 준 피해 순. 받은 피해는 처음 병력 − 남은 병력, 기술 · 고유기는 사건 기록에서 센다
func _rows(cp: String) -> Array:
	var final: Array = res.ev[res.ev.size() - 1].s
	var sk := {}
	var ul := {}
	for e in res.ev:
		var fx = e.get("fx")
		if fx == "skill":
			sk[e.a] = sk.get(e.a, 0) + 1
		elif fx == "ult":
			ul[e.a] = ul.get(e.a, 0) + 1
	var out := []
	for i in res.roster.size():
		var u: Dictionary = res.roster[i]
		if u.camp != cp:
			continue
		out.append({"id": u.id, "name": u.name, "tier": u.tier, "tag": u.tag,
			"dmg": float(u.get("dmg", 0)), "taken": float(u.taken) if u.has("taken") else maxf(0.0, u.max - final[i][0]), "heal": float(u.get("heal", 0)),
			"kills": int(u.get("kills", 0)), "gain": float(u.get("gain", 0)), "sk": sk.get(u.key, 0), "ult": ul.get(u.key, 0), "alive": final[i][2] == 1})
	out.sort_custom(func(x, y): return x.dmg > y.dmg)
	return out


class Row extends Control:
	const NAME_W := 92.0      # 이름 칸 —— 넘치면 … (11/7: '동오덕왕 엄백호' 가 막대 밑으로 들어갔다)
	const CNT_W := 74.0       # 오른쪽 격파 · 기술 · 고유기 칸
	var r: Dictionary
	var top_d: float
	var top_t: float

	static func make(r_: Dictionary, td: float, tt: float) -> Row:
		var o := Row.new()
		o.r = r_
		o.top_d = td
		o.top_t = tt
		o.custom_minimum_size = Vector2(0, ROW_H)
		o.mouse_filter = Control.MOUSE_FILTER_IGNORE
		return o

	func _draw() -> void:
		var P := DB.PAL
		var a := 1.0 if r.alive else 0.5
		Art.draw_face_circle(self, Vector2(18, 20), 16, r.id)
		draw_arc(Vector2(18, 20), 16, 0, TAU, 32, Color(DB.TIER[r.tier].c, a), 2.0)
		if not r.alive:
			draw_circle(Vector2(18, 20), 16, Color(0, 0, 0, 0.5))
		var x0 := 42.0
		draw_string(DB.font_display, Vector2(x0, 17), _fit(DB.font_display, r.name, 13, NAME_W), HORIZONTAL_ALIGNMENT_LEFT, NAME_W, 13, Color(P.paper, a))
		draw_string(DB.font_body, Vector2(x0, 33), r.tag, HORIZONTAL_ALIGNMENT_LEFT, NAME_W, 10, P.bamboo_dim)
		var bx := x0 + NAME_W + 6
		var bw := size.x - bx - CNT_W - 8
		_bar(Vector2(bx, 7), bw, r.dmg / top_d, P.gold, Battle.num(r.dmg))
		_bar(Vector2(bx, 23), bw, r.taken / top_t, Color("#c0503f"), Battle.num(r.taken))
		if r.get("gain", 0.0) > 0.0:      # 11/9 역할 기여 —— 이 장수의 깎기로 아군이 더 넣은 피해 (엔진 기록 gain)
			draw_string(DB.font_body, Vector2(size.x - CNT_W, 12), "깎기 +" + Battle.num(r.gain), HORIZONTAL_ALIGNMENT_RIGHT, CNT_W, 10, Color("#d8c27a", a))
		var s := "%d · %d · %d" % [r.kills, r.sk, r.ult]
		draw_string(DB.font_display, Vector2(size.x - CNT_W, 25), s, HORIZONTAL_ALIGNMENT_RIGHT, CNT_W, 13, P.paper if r.kills + r.sk + r.ult > 0 else P.bamboo_dim)

	## 칸에 들어가게 뒤를 … 으로
	static func _fit(f: Font, s: String, fs: int, w: float) -> String:
		if f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x <= w:
			return s
		var t := s
		while t.length() > 1 and f.get_string_size(t + "…", HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > w:
			t = t.substr(0, t.length() - 1)
		return t + "…"

	func _bar(p: Vector2, w: float, f: float, col: Color, txt: String) -> void:
		draw_rect(Rect2(p, Vector2(w, 10)), Color(1, 1, 1, 0.06))
		draw_rect(Rect2(p, Vector2(w * clampf(f, 0, 1), 10)), col)
		draw_string_outline(DB.font_body, p + Vector2(0, 9), txt, HORIZONTAL_ALIGNMENT_RIGHT, w - 3, 9, 3, Color(0, 0, 0, 0.8))
		draw_string(DB.font_body, p + Vector2(0, 9), txt, HORIZONTAL_ALIGNMENT_RIGHT, w - 3, 9, Color(1, 1, 1, 0.92))
