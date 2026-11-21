class_name BattleReport
extends PanelContainer
## 전투 결과표 —— 덱이 잘 굴렀는지 보는 화면 (롤토체스 피해 집계). 11/1 덱 감상 전투.
## 장수마다 준 피해 · 받은 피해 막대와 격파 · 기술 · 고유기 횟수. 아군 / 적을 바꿔 본다.
## 11/7 사용자: 토벌 대군(적 20부대)은 표가 화면을 넘쳐 [종료] 버튼이 줄 위에 겹치고 내릴 수도 없었다 ——
##   머리줄 · 아군/적군 탭 · 범례는 고정하고 장수 줄만 스크롤(UI.scroll = 손가락 끌기 TouchScroll).
##   표 높이는 두 진영 중 긴 쪽에 맞추되 max_h(보여 주는 쪽이 화면에 맞춰 준다)를 넘지 않는다 —— 탭을 바꿔도 표 · 버튼이 움직이지 않게.
##   긴 이름('동오덕왕 엄백호')은 … 으로 줄이고, 수치는 막대 오른쪽 제 칸에 (11/14 감사 #9 —— 막대 위에 겹쳐 읽기 어려웠다).

const ROW_H := 58.0       # 마지막 줄: 생존/패주 원인 · 잔존 병력 · 사기
const ROW_SEP := 4.0
const LINE_H := 24.0      # 덱 요약 · 덱 연쇄 한 줄 (어림)

var res: Dictionary
var camp := "A"
var view := "dmg"         # 11/19 기준 —— dmg 피해 · heal 치료 · sup 지원 (직접 피해가 낮은 장수도 제 역할로 찾게)
var _legend: RichTextLabel
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
	var v := UI.vbox(UI.SP_S)
	add_child(v)
	var col: Color = DB.PAL.jade if res.win else DB.PAL.seal
	var head := UI.hbox(UI.SP_S)
	head.add_child(UI.lbl("무승부" if res.draw else ("승전" if res.win else "패전"), UI.FS_TITLE, col, true))
	var sub := UI.lbl("잔존 %d 대 %d · %s" % [res.left, res.eLeft, _len_text()], UI.FS_BODY, DB.PAL.text_dim)
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
	_legend = UI.rich("", UI.FS_CAP)
	v.add_child(_legend)
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
	if cp == "A" and _feats() != "":
		lines += 1
	if not res.get("chains", {}).get(cp, {}).is_empty():
		lines += 1
	return n * ROW_H + maxi(0, n - 1) * ROW_SEP + lines * (LINE_H + ROW_SEP)


func _len_text() -> String:
	var t: float = res.get("view_len", res.get("len", 0.0))      # 11/3 화면 시계(위쪽 0:00)와 같은 시간 —— 엔진 시간은 화면에서 늘려 보여 준다
	if t <= 0:      # 예전 턴 엔진 결과 —— 턴 수 × 기본 한 턴 길이로 어림
		t = float(res.get("turns", 0)) * RtBattle.period_base
	return "%d:%02d" % [int(t) / 60, int(t) % 60]


const DOT_COL := Color("#ff8a3d")      # 지속 피해 몫 (준 피해 막대 안)
const HEAL_COL := Color("#7fd6a4")
const MO_COL := Color("#8fb8ff")
const SUP_COL := Color("#d8c27a")


func _fill() -> void:
	var nt := UI.hbox(UI.SP_S)
	var cs := UI.segmented([["A", "아군"], ["B", "적군"]], camp, func(k):
		camp = k
		_fill())
	cs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nt.add_child(cs)
	var vs := UI.segmented([["dmg", "피해"], ["heal", "치료"], ["sup", "지원"]], view, func(k):
		view = k
		_fill())
	vs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nt.add_child(vs)
	for c in _tabs.get_children():      # 11/19 replace_by 는 옛 노드의 자식을 새 노드로 옮겨 탭이 겹쳐 쌓였다 —— 틀은 두고 안만 바꾼다
		c.queue_free()
	nt.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_tabs.add_child(nt)
	_tabs.custom_minimum_size.y = UI.BH_S + 8
	_scroll.scroll_vertical = 0      # 탭을 바꾸면 맨 위부터
	for c in _body.get_children():
		c.queue_free()
	if camp == "A":      # 11/6 #16 덱 설계 요약 —— "내 덱의 무엇이 통했는지" 한 줄 (데일리 진행의 확인 순간)
		var ds := _deck_summary()
		if ds != "":
			_body.add_child(UI.wrap_text(UI.rich(ds, UI.FS_BODY)))      # 11/20 폴리싱: 요약 줄이 단어 중간에서 끊겼다 (「반 / 격」) —— 띄어쓰기 자리에서만
		var ft := _feats()
		if ft != "":
			_body.add_child(UI.wrap_text(UI.rich(ft, UI.FS_BODY)))
	var ch: Dictionary = res.get("chains", {}).get(camp, {})
	if not ch.is_empty():
		var names := ch.keys()
		names.sort_custom(func(x, y): return ch[x] > ch[y])
		var parts := []
		for k in names.slice(0, 5):
			parts.append("[b]%s[/b] ×%d" % [k, int(ch[k])])
		_body.add_child(UI.wrap_text(UI.rich("[color=#%s]덱 연쇄[/color]  %s" % [("ffd257" if camp == "A" else "ff7a66"), "   ".join(parts)], UI.FS_BODY)))
	var rows := _rows(camp)
	var k1: String = {"dmg": "dmg", "heal": "htr", "sup": "gain"}[view]
	var k2: String = {"dmg": "taken", "heal": "hmo", "sup": "mdmg"}[view]
	if view != "dmg":      # 역할 기준이면 그 기여 순 (같으면 원래 피해 순)
		rows.sort_custom(func(x, y): return x[k1] > y[k1] if x[k1] != y[k1] else (x[k2] > y[k2] if x[k2] != y[k2] else x.dmg > y.dmg))
	var top_d := 1.0
	var top_t := 1.0
	for r in rows:
		top_d = maxf(top_d, r[k1])
		top_t = maxf(top_t, r[k2])
	for r in rows:
		_body.add_child(Row.make(r, top_d, top_t, view))
	var P := DB.PAL
	var lg: Array = {"dmg": [[P.gold, "준 피해"], [DOT_COL, "지속"], [P.seal.lightened(0.05), "받은 피해"]],
		"heal": [[HEAL_COL, "병력 회복"], [MO_COL, "사기 회복"]],
		"sup": [[SUP_COL, "깎기로 늘린 아군 피해"], [P.seal.lightened(0.35), "사기 피해"]]}[view]
	var parts := []
	for it in lg:
		parts.append("[color=#%s]■[/color] %s" % [it[0].to_html(false), it[1]])
	_legend.text = "   ".join(parts) + "   ·   격파 · 기술 · 고유기"


## 11/19 실제 활약 요약 (아군, 최대 3) —— 기록에 있는 수치로만. 없으면 그 문구를 뺀다 (반사실 인과는 쓰지 않는다)
func _feats() -> String:
	var rows := _rows("A")
	var out := []
	var best := func(k: String):
		var b = null
		for r in rows:
			if float(r[k]) > 0.0 and (b == null or float(r[k]) > float(b[k])):
				b = r
		return b
	var d = best.call("dot")
	if d != null:
		out.append("[b]%s[/b] 지속 피해 %s" % [d.name, Battle.num(d.dot)])
	var h = best.call("htr")
	if h != null:
		out.append("[b]%s[/b] 병력 %s 회복" % [h.name, Battle.num(h.htr)])
	var g = best.call("gain")
	if g != null:
		out.append("[b]%s[/b] 깎기로 아군 피해 +%s" % [g.name, Battle.num(g.gain)])
	if out.is_empty():
		return ""
	return "[color=#%s]활약[/color]  " % HEAL_COL.to_html(false) + "  ·  ".join(out.slice(0, 3))


## 점검용 —— 줄 칸을 그 위치로 내린다 (tests/ui_shots --rscroll)
func scroll_to(y: int) -> void:
	_scroll.scroll_vertical = y


## 내 덱 설계 요약 —— 위세(살았는지) · 가장 많이 터진 연쇄 · 고유기 횟수 · 격파 수
func _deck_summary() -> String:
	var final: Array = res.ev[res.ev.size() - 1].s
	var auras := []
	var ults := 0
	var joint := 0      # 11/11 인연 합동 고유기 (대표 사건에 mates)
	var kills := 0
	for e in res.ev:
		if e.get("fx") == "ult" and str(e.get("a", "")).begins_with("A"):
			ults += 1
			if e.has("mates"):
				joint += 1
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
		parts.append("고유기 %d회" % ults + (" (인연 합동 %d)" % joint if joint > 0 else ""))
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
	var exits := {}
	for e in res.ev:
		var fx = e.get("fx")
		if fx == "skill":
			sk[e.a] = sk.get(e.a, 0) + 1
		elif fx == "ult":
			ul[e.a] = ul.get(e.a, 0) + 1
		elif fx == "rout":
			exits[str(e.f)] = e
	var out := []
	for i in res.roster.size():
		var u: Dictionary = res.roster[i]
		if u.camp != cp:
			continue
		var exit: Dictionary = exits.get(str(u.key), {})
		var cause := str(exit.get("rout_cause", ""))
		if cause == "" and not exit.is_empty():      # 이전 버전의 재생 결과도 읽는다
			var text := str(exit.get("t", ""))
			cause = "morale" if text.contains("끝내 패주") else ("annihilated" if text.contains("병력이 다해") else ("troops" if text.contains("병력이 꺾여") else "effect"))
		out.append({"id": u.id, "name": u.name, "tier": u.tier, "tag": u.tag,
			"rout_cause": cause, "remaining": float(exit.get("troop_ratio", float(final[i][0]) / maxf(1.0, float(u.max)))),
			"morale": float(exit.get("morale", final[i][1])), "gauge": int(final[i][4]) if final[i].size() > 4 else 0,
			"has_ult": DB.ult_of(str(u.id)) != null,
			"dmg": maxf(0.0, float(u.get("dmg", 0)) - float(u.get("over", 0))), "dot": float(u.get("dot", 0)),
			"htr": float(u.get("htr", 0)), "hmo": float(u.get("hmo", 0)), "mdmg": float(u.get("mdmg", 0)), "rec": u.has("htr"), "taken": float(u.taken) if u.has("taken") else maxf(0.0, u.max - final[i][0]), "heal": float(u.get("heal", 0)),
			"kills": int(u.get("kills", 0)), "gain": float(u.get("gain", 0)), "sk": sk.get(u.key, 0), "ult": ul.get(u.key, 0), "alive": final[i][2] == 1})
	out.sort_custom(func(x, y): return x.dmg > y.dmg)
	return out


class Row extends Control:
	const NAME_W := 84.0      # 이름 칸 —— 넘치면 … (11/7: '동오덕왕 엄백호' 가 막대 밑으로 들어갔다)
	const NUM_W := 46.0       # 11/14 감사 #9: 수치는 막대 위에 겹치지 않게 막대 오른쪽 제 칸에
	const CNT_W := 60.0       # 오른쪽 격파 · 기술 · 고유기 칸
	var r: Dictionary
	var top_d: float
	var top_t: float
	var mode := "dmg"

	static func make(r_: Dictionary, td: float, tt: float, mode_ := "dmg") -> Row:
		var o := Row.new()
		o.r = r_
		o.mode = mode_
		o.top_d = td
		o.top_t = tt
		o.custom_minimum_size = Vector2(0, ROW_H)
		o.mouse_filter = Control.MOUSE_FILTER_IGNORE
		return o

	func _draw() -> void:
		var P := DB.PAL
		var a := 1.0 if r.alive else 0.75      # 11/20 폴리싱 2차: 0.5 → 0.75 —— 전멸한 줄의 이름이 바탕에 묻혔다 (패전이면 표 전체가 흐렸다). 살아 있는 줄보다는 한 단계 흐리게
		var cy := ROW_H / 2.0
		Art.draw_face_circle(self, Vector2(17, cy), 15, r.id)
		draw_arc(Vector2(17, cy), 15, 0, TAU, 32, Color(DB.TIER[int(r.tier)].c, a), 2.0)
		if not r.alive:
			draw_circle(Vector2(17, cy), 15, Color(0, 0, 0, 0.5))
		var x0 := 38.0
		var tf := DB.title_font(UI.FS_BODY)
		draw_string(tf, Vector2(x0, 17), UI.ellipsize(tf, r.name, UI.FS_BODY, NAME_W), HORIZONTAL_ALIGNMENT_LEFT, NAME_W, UI.FS_BODY, Color(P.paper, a))
		draw_string(DB.font_body, Vector2(x0, 33), r.tag, HORIZONTAL_ALIGNMENT_LEFT, NAME_W, UI.FS_CAP, P.text_dim)
		var bx := x0 + NAME_W + UI.SP_XS
		var bw := maxf(20.0, size.x - bx - NUM_W - CNT_W - UI.SP_S)
		var sub := ""      # 셈 아래 제 줄 (11/19 기준마다 고정 자리 —— 막대 옆 빈자리가 있을 때만 보이던 것을 없앴다)
		var sub_col: Color = P.text_dim
		if mode == "heal":
			if not r.get("rec", true):      # 예전 기록 —— 회복 칸이 없었다 (0 과 다르다)
				draw_string(DB.font_body, Vector2(bx, 22), "기록 없음", HORIZONTAL_ALIGNMENT_LEFT, bw, UI.FS_CAP, P.text_dim)
			else:
				_bar(Vector2(bx, 8), bw, r.htr / top_d, BattleReport.HEAL_COL, Battle.num(r.htr))
				_bar(Vector2(bx, 24), bw, r.hmo / top_t, BattleReport.MO_COL, str(roundi(r.hmo)))
		elif mode == "sup":
			_bar(Vector2(bx, 8), bw, r.gain / top_d, BattleReport.SUP_COL, Battle.num(r.gain))
			_bar(Vector2(bx, 24), bw, r.mdmg / top_t, P.seal.lightened(0.35), str(roundi(r.mdmg)))
		else:
			_bar(Vector2(bx, 8), bw, r.dmg / top_d, P.gold, Battle.num(r.dmg))
			if r.dot > 0.0:      # 11/9 지속 피해(건 장수에게 기록)는 준 피해 안에 들어 있다 —— 막대 안 몫으로 (두 번 더하지 않는다)
				draw_rect(Rect2(Vector2(bx, 8), Vector2(bw * clampf(minf(r.dot, r.dmg) / top_d, 0, 1), 8)), BattleReport.DOT_COL)
				sub = "지속 " + Battle.num(r.dot)
				sub_col = BattleReport.DOT_COL
			_bar(Vector2(bx, 24), bw, r.taken / top_t, P.seal.lightened(0.05), Battle.num(r.taken))
		var cx := size.x - CNT_W
		var s := "%d · %d · %d" % [r.kills, r.sk, r.ult]
		draw_string(DB.title_font(UI.FS_BODY), Vector2(cx, 17 if sub != "" else 25), s, HORIZONTAL_ALIGNMENT_RIGHT, CNT_W, UI.FS_BODY, P.paper if r.kills + r.sk + r.ult > 0 else P.text_dim)
		if sub != "":
			draw_string(DB.font_body, Vector2(cx, 33), UI.ellipsize(DB.font_body, sub, UI.FS_TINY, CNT_W), HORIZONTAL_ALIGNMENT_RIGHT, CNT_W, UI.FS_TINY, Color(sub_col, a))
		var labels := {"morale": "사기 패주", "troops": "병력 패주", "mixed": "사기·병력 패주", "annihilated": "병력 소진", "effect": "효과로 이탈"}
		var status: String = "생존" if r.alive else str(labels.get(r.get("rout_cause", ""), "패주"))
		status += " · 병력 %d%% · 사기 %d" % [roundi(float(r.remaining) * 100.0), maxi(0, roundi(float(r.morale)))]
		if r.has_ult and r.ult == 0:
			status += " · 고유기 미발동"
		# 11/20 폴리싱 2차: 상태 줄(작은 글씨 10)은 text_dim 이라 읽기 어려웠다 —— 살아 있는 줄 bamboo, 전멸한 줄은 그보다 한 단계 흐리게
		var col: Color = P.seal.lightened(0.35) if r.get("rout_cause", "") in ["morale", "mixed"] else (P.bamboo if r.alive else Color(P.bamboo, 0.8))
		# 11/20 폴리싱: 상태 줄을 이름 칸(x0)에 맞춘다 —— 왼쪽 끝(6)에서 시작해 얼굴 동그라미 아랫단에 닿았고, 이름 · 병종 줄과 왼쪽이 어긋났다
		var status_w := size.x - x0 - 6.0
		var status_fs := UI.fit_fs(DB.font_body, status, UI.FS_TINY, 9, status_w)
		draw_string(DB.font_body, Vector2(x0, ROW_H - 6), status, HORIZONTAL_ALIGNMENT_LEFT, status_w, status_fs, col)

	## 막대 + 오른쪽 제 칸의 수치 (막대 색과 같은 계열)
	func _bar(p: Vector2, w: float, f: float, col: Color, txt: String) -> void:
		draw_rect(Rect2(p, Vector2(w, 8)), Color(1, 1, 1, 0.06))
		draw_rect(Rect2(p, Vector2(w * clampf(f, 0, 1), 8)), col)
		var fs := UI.fit_fs(DB.font_body, txt, UI.FS_CAP, UI.FS_TINY, NUM_W - 4)
		draw_string(DB.font_body, Vector2(p.x + w + 4, p.y + 9), txt, HORIZONTAL_ALIGNMENT_RIGHT, NUM_W - 4, fs, col.lightened(0.35))
