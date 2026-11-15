extends RefCounted
## 군략 카드 화면 부품 (11/15 1차 —— docs/군략_카드_초안.md)
##  편성 화면 「군략 1 · 2 · 3단계」 칸 줄 · 손패 시트 · 하루 끝 3택1 시트 · 머리띠 다시 열기 버튼 · 계열 기호 ·
##  전투 탭 우두머리 계획 줄 · 대전 상대 최근 계열 줄 · 전투 화면 단계 공개 연출.
## 11/14 UI 규칙: UI 상수(SP_* · FS_* · BH_* · R) · 색은 DB.PAL(강조 금 하나) · 계열은 작은 기호 + 옅은 라벨 · 터치 48 · 빈 상태 UI.empty · 확인 한 번.
## class_name 없이 preload 로 쓴다 (낡은 .godot 캐시에서도 이름을 찾게)

const Tac := preload("res://scripts/tactics.gd")
const MATCH_HINT := "상성 —— 정면 ▸ 기동 · 원거리 / 기동 ▸ 수비 · 책략 / 수비 ▸ 정면 · 원거리 / 원거리 ▸ 기동 · 책략 / 책략 ▸ 정면 · 수비. 이기면 공격 +15%, 지면 효과 절반"
const OUT_TEXT := {"win": "상성 우세 —— 공격 +15%", "lose": "상성 열세 —— 효과 절반", "draw": "상성 비김"}


## 계열 기호 —— 정면 ▲ · 기동 » · 수비 ■(방패) · 원거리 ◎ · 책략 ◆. 계열 없음은 작은 빈 원
class Glyph extends Control:
	var fam := ""
	var col := Color.WHITE

	func _init(f := "", c := Color.WHITE, d := 14.0) -> void:
		fam = f
		col = c
		custom_minimum_size = Vector2(d, d)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var s := minf(size.x, size.y)
		var c := size / 2.0
		var r := s * 0.42
		var w := maxf(1.4, s / 9.0)
		match fam:
			"정면":
				var p := PackedVector2Array([c + Vector2(0, -r), c + Vector2(r * 0.95, r * 0.8), c + Vector2(-r * 0.95, r * 0.8)])
				draw_colored_polygon(p, col)
			"기동":
				for dx in [-r * 0.55, r * 0.25]:
					draw_polyline(PackedVector2Array([c + Vector2(dx - r * 0.3, -r * 0.75), c + Vector2(dx + r * 0.4, 0), c + Vector2(dx - r * 0.3, r * 0.75)]), col, w)
			"수비":
				draw_polyline(PackedVector2Array([c + Vector2(-r * 0.8, -r * 0.8), c + Vector2(r * 0.8, -r * 0.8), c + Vector2(r * 0.8, r * 0.1),
					c + Vector2(0, r), c + Vector2(-r * 0.8, r * 0.1), c + Vector2(-r * 0.8, -r * 0.8)]), col, w)
			"원거리":
				draw_arc(c, r * 0.85, 0, TAU, 20, col, w)
				draw_circle(c, r * 0.3, col)
			"책략":
				draw_colored_polygon(PackedVector2Array([c + Vector2(0, -r), c + Vector2(r * 0.75, 0), c + Vector2(0, r), c + Vector2(-r * 0.75, 0)]), col)
			_:
				draw_arc(c, r * 0.45, 0, TAU, 14, Color(col, 0.7), w * 0.8)


## 계열 묶음 —— 기호 + 옅은 라벨 ("정면"). 둘(호표기)이면 둘 다
static func fam_tag(id: String, fs := UI.FS_CAP) -> HBoxContainer:
	var h := UI.hbox(3)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fs_l := Tac.fams(id)
	if fs_l.is_empty():
		fs_l = [""]
	for f in fs_l:
		var g := Glyph.new(f, DB.PAL.bamboo, fs + 1)
		g.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(g)
	var l := UI.lbl(Tac.fam_text(id) if Tac.fam_text(id) != "" else "계열 없음", fs, DB.PAL.text_dim)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(l)
	return h


## 카드 한 장 (손패 · 3택1) —— 위 등급색 선 · 이름 · 계열 · 등급 · 한 줄 효과. sel 이면 금테. note 는 못 놓는 까닭 같은 덧말(옅게)
static func card_btn(id: String, cb: Callable, sel := false, note := "", tall := false) -> TouchButton:
	var P := DB.PAL
	var b := TouchButton.new()
	b.custom_minimum_size = Vector2(0, 176 if tall else (112 if note != "" else 100))      # 글이 짧아(효과 한 줄) 높이를 정해 둔다 —— 줄바꿈 글의 최소 크기는 폭이 잡히기 전에 커서 못 믿는다
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var gc := Tac.grade_col(id)
	var sb := UI.flat(P.ink3 if sel else P.ink2, P.gold if sel else P.ink4, 2 if sel else 1, UI.R, 0)
	sb.border_width_top = 3
	sb.border_color = P.gold if sel else gc
	for st in ["normal", "hover", "pressed", "focus", "disabled"]:
		b.add_theme_stylebox_override(st, sb)
	var v := UI.vbox(2)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.offset_left = UI.SP_S
	v.offset_right = -UI.SP_S
	v.offset_top = UI.SP_S
	v.offset_bottom = -UI.SP_XS
	var hd := UI.hbox(UI.SP_S)
	hd.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var nl := UI.lbl(id, UI.FS_LABEL, P.gold if sel else P.paper, true)
	nl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	nl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nl.clip_text = true
	hd.add_child(nl)
	var econ := str(Tac.card(id).get("kind", "")) == "econ"
	var gl := UI.lbl("" if econ else Tac.grade_name(id), UI.FS_CAP, gc.lightened(0.15))
	gl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	gl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hd.add_child(gl)
	v.add_child(hd)
	if not econ:
		v.add_child(fam_tag(id))
	else:
		var el := UI.lbl("능력치 · 경제", UI.FS_CAP, gc.lightened(0.2))
		el.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_child(el)
	var dl := UI.lbl(Tac.desc(id) + (("\n" + note) if note != "" else ""), UI.FS_CAP, P.text_dim)
	dl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UI.wrap_text(dl)
	dl.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(dl)
	b.add_child(v)
	b.clip_contents = true
	b.pressed.connect(func():
		UI.buzz()
		cb.call())
	return b


# ───────── 편성 화면 —— 「군략 1 · 2 · 3단계」 ─────────

## 한 줄 —— 머리 「군략」 + 세 칸. 칸을 누르면 손패 시트
static func plan_row(gs) -> Control:
	var P := DB.PAL
	var run: Run = gs.run
	var h := UI.hbox(UI.SP_XS)
	var hl := UI.lbl("군략", UI.FS_BODY, P.bamboo, true)
	hl.custom_minimum_size = Vector2(34, 0)
	hl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(hl)
	var plan := Tac.norm(run.tk_plan)
	for i in Tac.STAGES:
		h.add_child(_slot(gs, i, plan[i]))
	return h


static func _slot(gs, i: int, id: String) -> TouchButton:
	var P := DB.PAL
	var b := TouchButton.new()
	b.custom_minimum_size = Vector2(0, UI.HIT)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var on := id != ""
	var sb := UI.flat(P.ink2 if on else Color(0, 0, 0, 0), Color(Tac.grade_col(id), 0.9) if on else Color(P.paper, 0.16), 1, UI.R, 0)
	for st in ["normal", "hover", "pressed", "focus", "disabled"]:
		b.add_theme_stylebox_override(st, sb)
	var v := UI.vbox(0)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.offset_left = 6
	v.offset_right = -4
	var top := UI.hbox(3)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var nl := UI.lbl("%d단계" % (i + 1), UI.FS_TINY, P.text_dim)
	nl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(nl)
	if on:
		for f in (Tac.fams(id) if not Tac.fams(id).is_empty() else [""]):
			var g := Glyph.new(f, P.bamboo, 10)
			g.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			top.add_child(g)
	v.add_child(top)
	var cl := UI.lbl(id if on else "비었음 +", UI.FS_BODY, P.paper if on else P.text_dim, on)
	cl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cl.clip_text = true
	cl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	v.add_child(cl)
	b.add_child(v)
	b.pressed.connect(func():
		UI.buzz()
		hand_sheet(gs, i))
	return b


## 손패 시트 —— i 단계에 놓을 카드. 놓인 칸이면 위에 「지금 카드 · 비우기」. 못 놓는 카드는 까닭을 옅게. 늘 켜진 카드 · 영구 효과는 아래에
static func hand_sheet(gs, i: int) -> void:
	var P := DB.PAL
	var run: Run = gs.run
	var b: VBoxContainer = gs.open_sheet("군략 %d단계" % (i + 1))
	var plan := Tac.norm(run.tk_plan)
	var cur: String = plan[i]
	var done := func(id: String):
		gs.act("set_plan", [i, id])
		gs.close_sheet()
	if cur != "":
		b.add_child(UI.eyebrow("지금 놓인 카드"))
		var cr := UI.hbox(UI.SP_S)
		cr.add_child(card_btn(cur, func(): gs.toast(Tac.desc(cur)), true))
		var cb := UI.btn("비우기", func(): done.call(""), "ghost", UI.BH_M)
		cb.custom_minimum_size.x = 84
		cb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		cr.add_child(cb)
		b.add_child(cr)
	var ids: Array = run.tk_hand.keys().filter(func(id): return Tac.placeable(str(id)) and str(id) != cur)
	ids.sort_custom(func(x, y):
		var gx := int(Tac.card(x).g)
		var gy := int(Tac.card(y).g)
		return gx > gy if gx != gy else str(x) < str(y))
	b.add_child(UI.eyebrow("손패 —— 누르면 %d단계에 놓는다" % (i + 1) if cur == "" else "손패 —— 누르면 바꾼다"))
	if ids.is_empty():
		b.add_child(UI.empty("draw", "놓을 군략이 없다", "하루가 끝날 때 3택1 로 군략이 는다."))
	var gd := GridContainer.new()
	gd.columns = 2
	gd.add_theme_constant_override("h_separation", UI.SP_S)
	gd.add_theme_constant_override("v_separation", UI.SP_S)
	for id in ids:
		var why := Tac.plan_block(plan, run.tk_hand, i, str(id))
		var n := int(run.tk_hand[id])
		var note := why if why != "" else ("%d장" % n if n > 1 else "")
		var cbtn := card_btn(str(id), func(): done.call(str(id)), false, note)
		if why != "":
			cbtn.modulate.a = 0.45
			cbtn.disabled = true
		gd.add_child(cbtn)
	b.add_child(gd)
	var own: Array = run.tk_hand.keys().filter(func(id): return str(Tac.card(str(id)).get("kind", "")) == "passive")
	var notes: Array = run.tk_perm.get("notes", [])
	if not own.is_empty() or not notes.is_empty():
		b.add_child(UI.eyebrow("늘 켜짐"))
		var tx := []
		for id in own:
			tx.append("%s —— %s" % [id, Tac.desc(str(id)).trim_prefix("[늘] ")])
		if not notes.is_empty():
			tx.append("영구 —— " + " · ".join(notes))
		b.add_child(UI.hint("\n".join(tx)))
	b.add_child(UI.hint(MATCH_HINT))
	b.add_child(UI.hint("기본 카드는 여러 단계에 겹쳐 놓을 수 있다 · 고급 이상은 전투당 한 번 · 전설은 한 장. 계획은 토벌 · 대전 모두에 쓴다."))


# ───────── 3택1 ─────────

## 머리띠 버튼 —— 고를 3택1 이 있을 때만 보인다. 누르면 3택1 시트
static func head_btn(gs) -> TouchButton:
	var P := DB.PAL
	var b := TouchButton.new()
	b.text = "군략 3택1"
	b.hit = Vector2(UI.HIT, UI.HIT)
	b.custom_minimum_size = Vector2(0, 20)
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	b.add_theme_font_size_override("font_size", UI.FS_TINY)
	for cn in ["font_color", "font_hover_color", "font_focus_color", "font_pressed_color"]:
		b.add_theme_color_override(cn, P.gold)
	var sb := UI.flat(Color(P.gold, 0.12), P.gold, 1, UI.R, 0)
	sb.content_margin_left = 6
	sb.content_margin_right = 6
	for st in ["normal", "hover", "pressed", "focus"]:
		b.add_theme_stylebox_override(st, sb)
	b.visible = false
	b.pressed.connect(func():
		UI.buzz()
		offer_sheet(gs))
	return b


## 3택1 시트 —— 카드 세 장(군략 연구면 넷) 가로. 누르면 고르고, 아래 「이 카드로」 확인 한 번. 기책이 있으면 다시 굴리기
static func offer_sheet(gs, sel := "") -> void:
	var P := DB.PAL
	var run: Run = gs.run
	var b: VBoxContainer = gs.open_sheet("군략 3택1")
	if run.tk_offer.is_empty():
		b.add_child(UI.empty("draw", "고를 카드가 없다", "하루가 끝날 때마다 군략 2장 + 능력치 · 경제 1장이 온다."))
		return
	b.add_child(UI.hint("하루를 마친 보상 —— 하나를 고른다. 군략은 손패로, 능력치 · 경제는 바로 또는 영구로."))
	var row := UI.hbox(UI.SP_S)
	for id in run.tk_offer:
		var sid := str(id)
		row.add_child(card_btn(sid, func(): offer_sheet(gs, sid), sid == sel, "", true))
	b.add_child(row)
	var ok := UI.btn("「%s」 고르기" % sel if sel != "" else "카드를 눌러 고른다", func():
		if sel == "":
			return
		var r = gs.act("pick_tac", [sel])
		gs.close_sheet()
		if r:
			gs.toast("군략 「%s」" % sel, "gold"), "pri", UI.BH_L)
	ok.disabled = sel == ""
	b.add_child(ok)
	var hb := UI.hbox(UI.SP_S)
	if run.tk_reroll > 0:
		var rb := UI.btn("다시 굴리기 (%d)" % run.tk_reroll, func():
			gs.act("reroll_tac")
			offer_sheet(gs), "ghost", UI.BH_M)
		rb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hb.add_child(rb)
	var lb := UI.btn("나중에", func(): gs.close_sheet(), "ghost", UI.BH_M)
	lb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(lb)
	b.add_child(hb)
	b.add_child(UI.hint("나중에 고르면 머리띠의 「군략 3택1」 로 다시 연다. 다음 날까지 안 고르면 첫 카드를 받는다."))


# ───────── 전투 탭 · 대전 상대 ─────────

## 우두머리 계획 줄 —— 「군략」 + 단계마다 기호 · 카드 이름. 누르면 효과 한 줄 (cb_toast)
static func plan_chips(plan: Array, cb_toast: Callable) -> HBoxContainer:
	var P := DB.PAL
	var h := UI.hbox(UI.SP_XS)
	var hl := UI.lbl("군략", UI.FS_CAP, P.text_dim)
	hl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(hl)
	var p := Tac.norm(plan)
	for i in Tac.STAGES:
		var id: String = p[i]
		var b := TouchButton.new()
		b.custom_minimum_size = Vector2(0, UI.BH_XS)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var sb := UI.flat(P.ink2, P.ink4, 1, UI.R, 0)
		for st in ["normal", "hover", "pressed", "focus"]:
			b.add_theme_stylebox_override(st, sb)
		var r := UI.hbox(3)
		r.mouse_filter = Control.MOUSE_FILTER_IGNORE
		r.alignment = BoxContainer.ALIGNMENT_CENTER
		r.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		var nl := UI.lbl("%d" % (i + 1), UI.FS_TINY, P.text_dim)
		nl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		nl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		r.add_child(nl)
		var fs := Tac.fams(id) if id != "" else []
		for f in (fs if not fs.is_empty() else [""]):
			var g := Glyph.new(f, P.bamboo, 11)
			g.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			r.add_child(g)
		var cl := UI.lbl(id if id != "" else "없음", UI.FS_CAP, P.paper if id != "" else P.text_dim)
		cl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		r.add_child(cl)
		b.add_child(r)
		b.pressed.connect(func():
			if id != "":
				cb_toast.call("%s —— %s" % [id, Tac.desc(id)]))
		h.add_child(b)
	return h


## 대전 상대가 최근 두 판에 쓴 카드 계열 —— 「최근 군략」 판마다 기호 셋. 기록이 없으면 null
static func hist_line(hist) -> Control:
	if not (hist is Array) or hist.is_empty():
		return null
	var P := DB.PAL
	var h := UI.hbox(UI.SP_S)
	var hl := UI.lbl("최근 군략", UI.FS_CAP, P.text_dim)
	hl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(hl)
	for gi in mini(2, hist.size()):
		var game = hist[gi]
		if not (game is Array):
			continue
		var gb := UI.hbox(2)
		var names := []
		for f in game:
			var g := Glyph.new(str(f).split("·")[0], P.bamboo, 12)
			g.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			gb.add_child(g)
			names.append(str(f) if str(f) != "" else "—")
		var tl := UI.lbl(" ".join(names), UI.FS_CAP, P.text_dim)
		tl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		gb.add_child(tl)
		h.add_child(gb)
		if gi == 0 and hist.size() > 1:
			h.add_child(UI.lbl("/", UI.FS_CAP, Color(P.paper, 0.25)))
	return h


# ───────── 전투 화면 —— 단계 공개 ─────────

## 단계 시작 사건(fx "tac") 하나 —— 위 띠 아래에 양쪽 카드가 뒤집혀 나오고 상성 한 줄, 1.2초 머물다 사라진다. A 가 나(뒤집은 결과도 A 가 나)
static func reveal(e: Dictionary, width: float) -> Control:
	var P := DB.PAL
	var root := Control.new()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.size = Vector2(width, 84)
	var cw := minf(156.0, (width - 72.0) / 2.0)
	var ea: Dictionary = e.get("A", {})
	var eb: Dictionary = e.get("B", {})
	var ca := _rv_card(ea, cw, War3D.TEAM.A)
	var cb := _rv_card(eb, cw, War3D.TEAM.B)
	ca.position = Vector2(width / 2.0 - 30.0 - cw, 0)
	cb.position = Vector2(width / 2.0 + 30.0, 0)
	root.add_child(ca)
	root.add_child(cb)
	var vs := UI.lbl("%d단계" % int(e.get("stage", 1)), UI.FS_CAP, P.paper, true)
	vs.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vs.position = Vector2(width / 2.0 - 30.0, 16)
	vs.size = Vector2(60, 20)
	root.add_child(vs)
	var out := str(ea.get("out", "draw"))
	var ol := UI.lbl(OUT_TEXT.get(out, ""), UI.FS_BODY, P.gold if out == "win" else (P.danger if out == "lose" else P.paper), true)
	ol.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ol.position = Vector2(0, 58)
	ol.size = Vector2(width, 22)
	ol.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	ol.add_theme_constant_override("outline_size", 4)
	root.add_child(ol)
	ol.modulate.a = 0.0
	# 뒤집기 —— 가로 크기 0 → 1 (A 먼저, B 0.1초 뒤), 1.2초 머문 뒤 0.25초에 사라진다
	for c in [ca, cb]:
		c.pivot_offset = Vector2(cw / 2.0, 26)
		c.scale = Vector2(0.0, 1.0)
	var delay := 1.1 if int(e.get("stage", 1)) == 1 else 0.0      # 1단계는 시작 진형 이름 띠(가운데 1초 남짓)가 걷힌 뒤에
	root.modulate.a = 0.0
	(func():
		if not is_instance_valid(root):
			return
		var t := root.create_tween()
		t.tween_interval(delay)
		t.tween_property(root, "modulate:a", 1.0, 0.06)
		t.tween_property(ca, "scale", Vector2.ONE, 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		t.tween_property(cb, "scale", Vector2.ONE, 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		t.tween_property(ol, "modulate:a", 1.0, 0.12)
		t.tween_interval(1.2)
		t.tween_property(root, "modulate:a", 0.0, 0.25)
		t.tween_callback(root.queue_free)).call_deferred()
	return root


static func _rv_card(ent: Dictionary, w: float, team: Color) -> Control:
	var P := DB.PAL
	var id := str(ent.get("id", ""))
	var pc := PanelContainer.new()
	pc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pc.size = Vector2(w, 52)
	pc.custom_minimum_size = Vector2(w, 52)
	var sb := UI.flat(Color(P.ink, 0.92), Color(team, 0.9), 1, UI.R, 6)
	sb.border_width_left = 3
	if id != "":
		sb.border_width_top = 2
		sb.border_color = Color(team, 0.9)
	pc.add_theme_stylebox_override("panel", sb)
	var v := UI.vbox(1)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var nm := id if id != "" else "군략 없음"
	if bool(ent.get("x", false)):
		nm += " (무효)"
	elif str(ent.get("via", "")) != "":
		nm = "%s ← %s" % [nm, ent.via]
	var nl := UI.lbl(nm, UI.FS_LABEL if nm.length() <= 7 else UI.FS_BODY, P.paper if id != "" else P.text_dim, true)
	nl.clip_text = true
	nl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	nl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(nl)
	if id != "":
		var h := UI.hbox(3)
		h.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var fam := str(ent.get("fam", ""))
		var g := Glyph.new(fam.split("·")[0], P.bamboo, 12)
		g.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(g)
		var fl := UI.lbl(fam if fam != "" else "계열 없음", UI.FS_CAP, P.text_dim)
		fl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		h.add_child(fl)
		v.add_child(h)
	pc.add_child(v)
	return pc
