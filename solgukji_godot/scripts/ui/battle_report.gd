class_name BattleReport
extends PanelContainer
## 전투 결과표 —— 덱이 잘 굴렀는지 보는 화면 (롤토체스 피해 집계). 11/1 덱 감상 전투.
## 장수마다 준 피해 · 받은 피해 막대와 격파 · 기술 · 고유기 횟수. 아군 / 적을 바꿔 본다.

var res: Dictionary
var camp := "A"
var _body: VBoxContainer
var _tabs: Control


static func make(r: Dictionary) -> BattleReport:
	var b := BattleReport.new()
	b.res = r
	return b


func _ready() -> void:
	add_theme_stylebox_override("panel", UI.flat(Color(0.06, 0.07, 0.11, 0.94), DB.PAL.ink3, 1, 10, 12))
	mouse_filter = Control.MOUSE_FILTER_STOP
	var v := UI.vbox(8)
	add_child(v)
	var col: Color = DB.PAL.jade if res.win else DB.PAL.seal
	var head := UI.hbox(8)
	head.add_child(UI.lbl("무승부" if res.draw else ("승전" if res.win else "패전"), 20, col, true))
	var sub := UI.lbl("잔존 %d 대 %d · %s" % [res.left, res.eLeft, _len_text()], 13, DB.PAL.bamboo_dim)
	sub.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	head.add_child(sub)
	v.add_child(head)
	_tabs = Control.new()
	v.add_child(_tabs)
	_body = UI.vbox(4)
	v.add_child(_body)
	_fill()


func _len_text() -> String:
	var t: float = res.get("len", 0.0)
	return "%d초" % roundi(t) if t > 0 else "%d턴" % res.turns


func _fill() -> void:
	var nt := UI.segmented([["A", "아군"], ["B", "적군"]], camp, func(k):
		camp = k
		_fill())
	_tabs.replace_by(nt)
	_tabs = nt
	for c in _body.get_children():
		c.queue_free()
	var rows := _rows(camp)
	var top_d := 1.0
	var top_t := 1.0
	for r in rows:
		top_d = maxf(top_d, r.dmg)
		top_t = maxf(top_t, r.taken)
	for r in rows:
		_body.add_child(Row.make(r, top_d, top_t))
	_body.add_child(UI.rich("[color=#%s]■[/color] 준 피해   [color=#c0503f]■[/color] 받은 피해   ·   격파 · 기술 · 고유기" % DB.PAL.gold.to_html(false), 11))


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
			"dmg": float(u.get("dmg", 0)), "taken": maxf(0.0, u.max - final[i][0]), "heal": float(u.get("heal", 0)),
			"kills": int(u.get("kills", 0)), "sk": sk.get(u.key, 0), "ult": ul.get(u.key, 0), "alive": final[i][2] == 1})
	out.sort_custom(func(x, y): return x.dmg > y.dmg)
	return out


class Row extends Control:
	var r: Dictionary
	var top_d: float
	var top_t: float

	static func make(r_: Dictionary, td: float, tt: float) -> Row:
		var o := Row.new()
		o.r = r_
		o.top_d = td
		o.top_t = tt
		o.custom_minimum_size = Vector2(0, 40)
		return o

	func _draw() -> void:
		var P := DB.PAL
		var a := 1.0 if r.alive else 0.5
		Art.draw_face_circle(self, Vector2(18, 20), 16, r.id)
		draw_arc(Vector2(18, 20), 16, 0, TAU, 32, Color(DB.TIER[r.tier].c, a), 2.0)
		if not r.alive:
			draw_circle(Vector2(18, 20), 16, Color(0, 0, 0, 0.5))
		var x0 := 42.0
		var nw := 72.0
		draw_string(DB.font_display, Vector2(x0, 17), r.name, HORIZONTAL_ALIGNMENT_LEFT, nw, 13, Color(P.paper, a))
		draw_string(DB.font_body, Vector2(x0, 33), r.tag, HORIZONTAL_ALIGNMENT_LEFT, nw, 10, P.bamboo_dim)
		var bx := x0 + nw + 4
		var bw := size.x - bx - 96
		_bar(Vector2(bx, 7), bw, r.dmg / top_d, P.gold, Battle.num(r.dmg))
		_bar(Vector2(bx, 23), bw, r.taken / top_t, Color("#c0503f"), Battle.num(r.taken))
		var tx := size.x - 90
		var s := "%d · %d · %d" % [r.kills, r.sk, r.ult]
		draw_string(DB.font_display, Vector2(tx, 25), s, HORIZONTAL_ALIGNMENT_RIGHT, 88, 13, P.paper if r.kills + r.sk + r.ult > 0 else P.bamboo_dim)

	func _bar(p: Vector2, w: float, f: float, col: Color, txt: String) -> void:
		draw_rect(Rect2(p, Vector2(w, 10)), Color(1, 1, 1, 0.06))
		draw_rect(Rect2(p, Vector2(w * clampf(f, 0, 1), 10)), col)
		draw_string(DB.font_body, p + Vector2(3, 9), txt, HORIZONTAL_ALIGNMENT_LEFT, w, 9, Color(1, 1, 1, 0.9))
