extends Control
## 11/22 사용자: 전투 중 아군 · 적군이 낸 군략을 위 띠(병력 · 사기) 바로 아래에 나열 —— 발동한 단계는 밝게 + ✓, 무효는 붉게.
##  접힘(기본): 진영마다 「군략 ① ② ③」 작은 칩 한 줄 (전장을 가리지 않게). 누르면 펼침: 단계마다 언제(개전 ~ 12초 …) · 카드 이름 · 상성,
##  늘 켜지는 카드, 맨 아래 단계 설명 한 줄. 적 단계 카드는 그 단계가 열려 뒤집힐 때까지 「?」 (늘 켜짐은 원래 공개라 처음부터 보인다).
##  화면 전용 —— 엔진 사건(fx "tac")만 읽는다. 전투 로직 · 결과는 건드리지 않는다. battle_view 가 setup · on_event 를 부른다.

const Tac := preload("res://scripts/tactics.gd")
const TacUI := preload("res://scripts/ui/tac_ui.gd")
const W := 168.0          # 펼친 판 폭 (세로 화면 360 에서 양쪽 둘 + 가운데 틈)

var view                  # battle_view —— hud.cut(컷인) · hud.decisive_on(결전 띠) 를 본다
var open := false
var plan := {"A": ["", "", ""], "B": ["", "", ""]}
var own := {"A": [], "B": []}
var fired := {"A": [null, null, null], "B": [null, null, null]}      # 단계 사건의 진영 몫 {id, out, x, via}
var _panels := {}


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


## 전투 시작 —— pk = 정책의 plan {A: {p, own}, B: {p, own}} (없으면 빈 사전). log_a = 결과의 단계 기록(아군 몫 —— 내 계획이라 미리 보여도 된다)
func setup(pk, log_a: Array) -> void:
	plan = {"A": ["", "", ""], "B": ["", "", ""]}
	own = {"A": [], "B": []}
	fired = {"A": [null, null, null], "B": [null, null, null]}
	if pk is Dictionary:
		for cp in ["A", "B"]:
			var one = pk.get(cp)
			if one is Dictionary:
				if cp == "A":
					plan[cp] = Tac.norm(one.get("p", []))
				own[cp] = (one.get("own", []) as Array).map(func(x): return str(x)) if one.get("own") is Array else []
	if plan.A == ["", "", ""]:
		for k in mini(log_a.size(), Tac.STAGES):
			var ent = log_a[k]
			if ent is Dictionary:
				plan.A[k] = str(ent.get("id", ""))
	_build()


## 단계 공개 사건
func on_event(e: Dictionary) -> void:
	var k := int(e.get("stage", 0)) - 1
	if k < 0 or k >= Tac.STAGES:
		return
	for cp in ["A", "B"]:
		var ent = e.get(cp)
		if ent is Dictionary:
			fired[cp][k] = ent
	_build()


func _process(_dt: float) -> void:
	var h = view.hud if view != null else null
	var any := false
	for cp in ["A", "B"]:
		if plan[cp] != ["", "", ""] or not (own[cp] as Array).is_empty() or fired[cp].any(func(x): return x != null):
			any = true
	visible = any and (h == null or h.cut == null)      # 컷인 동안은 숨긴다 (단계 공개 카드와 같다)
	var top := 64.0 if (h != null and bool(h.decisive_on)) else 47.0      # 위 띠(0 ~ 45) · 결전 띠 아래
	for cp in _panels:
		var p: Control = _panels[cp]
		if is_instance_valid(p):
			var v: Control = p.get_child(0)
			var ms := v.get_combined_minimum_size()      # 글 크기는 트리에 들어간 뒤에야 잡힌다 —— 매 프레임 맞춘다 (가벼움)
			p.size = Vector2(maxf(ms.x, W if open else 0.0) + 12.0, ms.y + 6.0)
			p.position.y = top
			p.position.x = 6.0 if cp == "A" else size.x - p.size.x - 6.0


func _build() -> void:
	for cp in _panels:
		if is_instance_valid(_panels[cp]):
			_panels[cp].queue_free()
	_panels = {}
	for cp in ["A", "B"]:
		var p := _panel(cp)
		add_child(p)
		_panels[cp] = p


func _team(cp: String) -> Color:
	return Color("#a9c8f0") if cp == "A" else Color("#f0aaa2")      # 위 띠 사기 머리말과 같은 진영색


func _panel(cp: String) -> Control:
	var P := DB.PAL
	var b := TouchButton.new()
	b.mouse_filter = Control.MOUSE_FILTER_STOP
	var sb := UI.flat(Color(P.ink, 0.78), Color(_team(cp), 0.55), 1, UI.R, 4)
	sb.content_margin_left = 6
	sb.content_margin_right = 6
	for st in ["normal", "hover", "pressed", "focus"]:
		b.add_theme_stylebox_override(st, sb)
	var v := UI.vbox(2)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.position = Vector2(6, 3)
	# 머리 줄 —— 「아군 군략」 + 단계 칩 셋 + 늘 켜짐 수 + ▾ / ▴
	var hd := UI.hbox(3)
	hd.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hd.add_child(_l(("아군" if cp == "A" else "적") + " 군략", UI.FS_TINY, _team(cp)))
	for k in Tac.STAGES:
		hd.add_child(_chip(cp, k))
	var on: Array = own[cp]
	if not on.is_empty():
		hd.add_child(_l("늘%d" % on.size(), UI.FS_TINY, P.jade))
	hd.add_child(_l("▴" if open else "▾", UI.FS_TINY, P.text_dim))
	v.add_child(hd)
	if open:
		for k in Tac.STAGES:
			v.add_child(_row(cp, k))
		for id in on:
			var r := _l("늘 · %s" % id, UI.FS_TINY, P.jade)
			v.add_child(r)
		if cp == "A":
			v.add_child(_l("단계가 열릴 때 양쪽 카드 공개 ·\n효과는 그 단계 동안", UI.FS_TINY, P.text_dim))
	b.add_child(v)
	b.pressed.connect(func():
		UI.buzz()
		open = not open
		_build())
	return b


## 머리 줄 칩 —— 단계 번호. 발동 전: 옅은 테 · 발동: 진영색 채움 · 무효: 붉은 채움
func _chip(cp: String, k: int) -> Control:
	var P := DB.PAL
	var ent = fired[cp][k]
	var pc := PanelContainer.new()
	pc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pc.custom_minimum_size = Vector2(15, 15)
	var bg := Color(0, 0, 0, 0)
	var bd: Color = Color(P.paper, 0.3)
	var fg: Color = P.text_dim
	if ent != null:
		if bool(ent.get("x", false)):
			bg = Color(P.danger, 0.55)
			bd = P.danger
		elif str(ent.get("id", "")) != "":
			bg = Color(_team(cp), 0.45)
			bd = _team(cp)
		fg = P.paper
	var sb := UI.flat(bg, bd, 1, 2, 0)
	pc.add_theme_stylebox_override("panel", sb)
	var l := _l(str(k + 1), UI.FS_TINY, fg)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pc.add_child(l)
	return pc


## 펼친 단계 줄 —— 「1 개전~12초  돌격 ✓ 우세」. 적 쪽 미공개는 「?」
func _row(cp: String, k: int) -> Control:
	var P := DB.PAL
	var h := UI.hbox(4)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(_l("%d %s" % [k + 1, TacUI.stage_span(k)], UI.FS_TINY, P.text_dim))
	var ent = fired[cp][k]
	var nm := ""
	var col: Color = P.text_dim
	if ent != null:
		nm = str(ent.get("id", ""))
		if nm == "":
			nm = "없음"
		elif bool(ent.get("x", false)):
			nm += " ✕무효"
			col = P.danger
		else:
			if str(ent.get("via", "")) != "":
				nm += "←" + str(ent.via)
			nm += " ✓"
			col = P.gold if str(ent.get("out", "")) == "win" else P.paper
			var o := str(ent.get("out", ""))
			if o == "win":
				nm += " 우세"
			elif o == "lose":
				nm += " 열세"
	else:
		nm = plan[cp][k] if cp == "A" else "?"
		if nm == "":
			nm = "없음"
	var nl := _l(nm, UI.FS_TINY, col)
	h.add_child(nl)
	return h


func _l(t: String, fs: int, c: Color) -> Label:
	var l := UI.lbl(t, fs, c)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	l.add_theme_constant_override("outline_size", 3)
	return l
