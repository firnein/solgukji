extends RefCounted
## 인연 표시 공용 (11/11) —— 디테일창 · 갈무리창 줄(game_screen)과 편성 시트(deploy_page)가 같이 쓴다. class_name 없이 preload 로 불러 쓴다.
## 인연 = 고유기를 함께 발동하는 장수 조합 (DB.INYEON). 색은 연분홍 한 가지(DB.PAL.yeon), 기호는 맞물린 두 고리(Icons "link").
## 구성원은 초상 타일(MiniTile) —— 가진 장수는 밝게, 없으면 어둡게, 보고 있는 장수 · 편성한 장수는 금테, 갈무리한 장수는 ★.

const TILE := Vector2(60, 88)


## 사람 -> 가장 높은 등급으로 가진 카드 id. ult_only 면 고유기를 쓸 수 있는 카드만 (편성 판정과 같은 기준)
static func owned_map(run: Run, ult_only := false) -> Dictionary:
	var o := {}
	var pool := run.pool()
	for k in pool:
		if ult_only and not DB.inyeon_card(k):
			continue
		var p := DB.person(k)
		if not o.has(p) or DB.C[k].tier > DB.C[o[p]].tier:
			o[p] = k
	return o


## 갈무리(★)한 카드의 인물 {인물: true}
static func pinned_map(pins: Array) -> Dictionary:
	var o := {}
	for k in pins:
		if DB.C.has(k):
			o[DB.person(k)] = true
	return o


## 덱(카드 id 배열)의 인물 {인물: true} —— 고유기를 쓸 수 있는 카드만
static func deck_map(deck: Array) -> Dictionary:
	var o := {}
	for k in deck:
		if DB.inyeon_card(k):
			o[DB.person(k)] = true
	return o


## 인연 규칙 한 줄 (DB.INYEON_RULE)
static func rule_hint() -> Label:
	var l := UI.hint(DB.INYEON_RULE)
	l.add_theme_font_size_override("font_size", 12)
	return l


## 인연 이름 칩 —— 고르면 연분홍 테두리
static func chip(text: String, on: bool, cb: Callable, h := 30) -> Button:
	var P := DB.PAL
	var col: Color = P.yeon
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, h)
	b.add_theme_font_size_override("font_size", 13)
	for cn in ["font_color", "font_hover_color", "font_focus_color", "font_pressed_color"]:
		b.add_theme_color_override(cn, col.lightened(0.3) if on else P.paper)
	var sb := UI.flat(Color(col, 0.16) if on else P.ink3, col if on else Color(0, 0, 0, 0), 1, UI.R, 0)
	sb.content_margin_left = 11
	sb.content_margin_right = 11
	sb.content_margin_top = 3
	sb.content_margin_bottom = 3
	for st in ["normal", "hover", "pressed", "focus"]:
		b.add_theme_stylebox_override(st, sb)
	b.pressed.connect(func():
		UI.buzz()
		cb.call())
	return b


## 누를 수 없는 이름 칩 (갈무리창 한 줄 —— 줄째 눌러 디테일창으로 간다)
static func name_chip(text: String, fs := 12) -> Control:
	var pc := PanelContainer.new()
	var sb := UI.flat(DB.PAL.ink3, Color(0, 0, 0, 0), 0, UI.R, 0)
	sb.content_margin_left = 9
	sb.content_margin_right = 9
	sb.content_margin_top = 2
	sb.content_margin_bottom = 2
	pc.add_theme_stylebox_override("panel", sb)
	pc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := UI.lbl(text, fs, DB.PAL.paper)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pc.add_child(l)
	return pc


## 구성원 타일 하나 —— ctx: {own: {인물: 카드 id}, deck: {인물: true}, pins: {인물: true}, me: 인물, hand: true(가졌는데 편성 안 한 장수에 '손패' 알약)}
static func member_tile(p: String, ctx: Dictionary, on_card: Callable) -> MiniTile:
	var own: String = ctx.get("own", {}).get(p, "")
	var k := own if own != "" else DB.inyeon_card_of_person(p, false)
	var t := MiniTile.new().setup(k, -1)
	t.custom_minimum_size = TILE
	var me: bool = ctx.get("me", "") == p
	var in_deck: bool = ctx.get("deck", {}).has(p)
	t.lit = me or in_deck
	t.dim = own == "" and not me
	if ctx.get("pins", {}).has(p):
		t.set_pin(true, false)
	if ctx.get("hand", false) and own != "" and not in_deck:
		t.badge = "손패"
		t.badge_col = Color(DB.PAL.jade, 0.95)
	t.tapped.connect(func(_id): on_card.call(own if own != "" else k))
	return t


## 인연 하나의 구성원 줄 —— 4~5명이 한 줄 (가운데 맞춤)
static func members_row(nm: String, ctx: Dictionary, on_card: Callable) -> Control:
	var h := UI.hbox(6)
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	for p in DB.inyeon_members(nm):
		h.add_child(member_tile(p, ctx, on_card))
	return h


## 디테일창 · 갈무리창의 '인연' 줄 —— 왼쪽 기호 + 라벨, 오른쪽 인연 이름 칩(흐름). 칩을 누르면 아래에 그 인연의 구성원이 나온다 (처음엔 첫 인연).
## simple(갈무리창)이면 이름 칩만 —— 줄째 on_tap(디테일창으로). 라벨 칸은 _ability_row 와 같은 폭(80)이라 이름 왼끝이 맞는다
static func detail_row(names: Array, ctx: Dictionary, fs: int, simple: bool, on_card: Callable, on_tap := Callable()) -> Control:
	var P := DB.PAL
	var m := MarginContainer.new()
	var vm := 6 if simple else 8
	m.add_theme_constant_override("margin_top", vm)
	m.add_theme_constant_override("margin_bottom", vm)
	if on_tap.is_valid():
		m.mouse_filter = Control.MOUSE_FILTER_STOP
		m.gui_input.connect(func(e):
			if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT and not e.pressed:
				UI.buzz()
				on_tap.call())
	else:
		m.mouse_filter = Control.MOUSE_FILTER_PASS
	var v := UI.vbox(8)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var top := UI.hbox(8)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var lab := HBoxContainer.new()
	lab.add_theme_constant_override("separation", 5)
	lab.custom_minimum_size.x = 80
	lab.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ic := Icons.View.new("link", P.yeon, fs + 2)
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	lab.add_child(ic)
	var kl := UI.lbl("인연", fs - 1, P.bamboo_dim)
	kl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	kl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lab.add_child(kl)
	top.add_child(lab)
	var flow := UI.flow(6)
	flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	flow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(flow)
	v.add_child(top)
	if simple:
		for nm in names:
			flow.add_child(name_chip(nm, fs))
		m.add_child(v)
		return m
	var holder := UI.vbox(6)
	v.add_child(holder)
	var cur := [names[0]]
	var rf := [Callable()]      # 람다가 자기 자신을 부르려면 배열에 담는다 (지역 변수는 값으로 잡힌다)
	rf[0] = func():
		for c in flow.get_children():
			flow.remove_child(c)
			c.queue_free()
		for nm in names:
			var on: bool = nm == cur[0]
			flow.add_child(chip(nm, on, func():
				if cur[0] != nm:
					cur[0] = nm
					rf[0].call()))
		for c in holder.get_children():
			holder.remove_child(c)
			c.queue_free()
		holder.add_child(members_row(cur[0], ctx, on_card))
		holder.add_child(rule_hint())
	rf[0].call()
	m.add_child(v)
	return m
