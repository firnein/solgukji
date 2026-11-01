class_name UI
extends RefCounted
## 화면 부품 —— 세로 화면(기준 폭 400) 휴대폰용. 손가락으로 누르기 좋게 버튼은 높이 48 이상. 색은 DB.PAL.
## 스크롤은 UI.scroll() 로 만든다 (TouchScroll 이 버튼 위에서 끌어도 스크롤되게 한다).

const BTN_H := 50


static func theme() -> Theme:
	var P := DB.PAL
	var th := Theme.new()
	th.default_font = DB.font_body
	th.default_font_size = 15
	th.set_stylebox("panel", "PanelContainer", flat(P.ink2, P.ink3, 1, 8, 12))
	th.set_stylebox("normal", "Button", flat(P.ink3, P.ink4, 1, 8, 10))
	th.set_stylebox("hover", "Button", flat(P.ink4, P.bamboo_dim, 1, 8, 10))
	th.set_stylebox("pressed", "Button", flat(P.bamboo, P.bamboo, 1, 8, 10))
	th.set_stylebox("hover_pressed", "Button", flat(P.bamboo, P.gold, 1, 8, 10))
	th.set_stylebox("disabled", "Button", flat(Color(P.ink3, 0.5), P.ink3, 1, 8, 10))
	th.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	th.set_color("font_color", "Button", P.paper)
	th.set_color("font_hover_color", "Button", P.paper)
	th.set_color("font_pressed_color", "Button", Color("#1A1508"))
	th.set_color("font_hover_pressed_color", "Button", Color("#1A1508"))
	th.set_color("font_disabled_color", "Button", Color(P.paper, 0.35))
	th.set_color("font_color", "Label", P.paper)
	th.set_color("default_color", "RichTextLabel", P.paper)
	th.set_font_size("normal_font_size", "RichTextLabel", 14)
	th.set_font("normal_font", "RichTextLabel", DB.font_body)
	th.set_font("bold_font", "RichTextLabel", DB.font_bold)
	th.set_stylebox("normal", "OptionButton", flat(P.ink3, P.ink4, 1, 8, 10))
	th.set_stylebox("hover", "OptionButton", flat(P.ink4, P.bamboo_dim, 1, 8, 10))
	# 스크롤 막대 —— 손가락으로 잡을 수 있게 굵게
	var grab := flat(P.ink4, P.ink4, 0, 6, 0)
	grab.content_margin_left = 6
	grab.content_margin_right = 6
	th.set_stylebox("grabber", "VScrollBar", grab)
	th.set_stylebox("grabber_highlight", "VScrollBar", flat(P.bamboo_dim, P.bamboo_dim, 0, 6, 0))
	th.set_stylebox("grabber_pressed", "VScrollBar", flat(P.bamboo, P.bamboo, 0, 6, 0))
	th.set_stylebox("scroll", "VScrollBar", flat(Color(P.ink, 0.4), P.ink, 0, 6, 0))
	# 손가락으로 끄니 막대는 가늘게 보여 주기만 한다
	var thin := flat(Color(P.paper, 0.18), Color(P.paper, 0.18), 0, 3, 0)
	thin.content_margin_left = 2
	thin.content_margin_right = 2
	th.set_stylebox("grabber", "VScrollBar", thin)
	th.set_stylebox("scroll", "VScrollBar", StyleBoxEmpty.new())
	var thin_h := thin.duplicate()
	thin_h.content_margin_left = 0
	thin_h.content_margin_right = 0
	thin_h.content_margin_top = 2
	thin_h.content_margin_bottom = 2
	th.set_stylebox("grabber", "HScrollBar", thin_h)
	th.set_stylebox("scroll", "HScrollBar", StyleBoxEmpty.new())
	th.set_stylebox("normal", "LineEdit", flat(P.ink, P.ink4, 1, 8, 10))
	th.set_stylebox("focus", "LineEdit", flat(P.ink, P.bamboo, 1, 8, 10))
	th.set_font_size("font_size", "LineEdit", 16)
	th.set_font_size("font_size", "CheckButton", 15)
	return th


static func flat(bg: Color, border: Color, bw := 1, rad := 6, pad := 8) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(bw)
	sb.set_corner_radius_all(rad)
	sb.set_content_margin_all(pad)
	return sb


static func lbl(text: String, fs := 15, col := Color(0, 0, 0, 0), display := false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", fs)
	if col.a > 0:
		l.add_theme_color_override("font_color", col)
	if display:
		l.add_theme_font_override("font", DB.font_display)
	return l


static func hint(text: String) -> Label:
	var l := lbl(text, 13, DB.PAL.bamboo_dim.lightened(0.12))
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


static func rich(bb: String, fs := 14) -> RichTextLabel:
	var r := RichTextLabel.new()
	r.bbcode_enabled = true
	r.fit_content = true
	r.scroll_active = false
	r.mouse_filter = Control.MOUSE_FILTER_PASS
	r.add_theme_font_size_override("normal_font_size", fs)
	r.add_theme_font_size_override("bold_font_size", fs)
	r.append_text(bb)
	return r


static func eyebrow(text: String) -> Label:
	var l := lbl(text, 14, DB.PAL.bamboo, true)
	return l


static func btn(text: String, cb: Callable, kind := "", h := BTN_H) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, h)
	b.add_theme_font_size_override("font_size", 16)
	b.pressed.connect(func():
		buzz()
		cb.call())
	match kind:
		"pri":
			b.add_theme_stylebox_override("normal", flat(DB.PAL.jade.darkened(0.25), DB.PAL.jade, 1, 8, 10))
			b.add_theme_stylebox_override("hover", flat(DB.PAL.jade.darkened(0.1), DB.PAL.jade, 1, 8, 10))
		"warn":
			b.add_theme_stylebox_override("normal", flat(DB.PAL.seal.darkened(0.3), DB.PAL.seal, 1, 8, 10))
			b.add_theme_stylebox_override("hover", flat(DB.PAL.seal.darkened(0.15), DB.PAL.seal, 1, 8, 10))
		"gold":
			b.add_theme_stylebox_override("normal", flat(DB.PAL.gold.darkened(0.45), DB.PAL.gold, 1, 8, 10))
			b.add_theme_stylebox_override("hover", flat(DB.PAL.gold.darkened(0.3), DB.PAL.gold, 1, 8, 10))
		"ghost":
			b.add_theme_stylebox_override("normal", flat(Color(0, 0, 0, 0), DB.PAL.ink4, 1, 8, 10))
	return b


## 두 줄 버튼 —— 굵은 제목 + 작은 설명 (징집·전투의 큰 행동 버튼)
static func act(title: String, sub: String, cb: Callable, kind := "", disabled := false) -> Button:
	var b := btn("", cb, kind, 64)
	b.disabled = disabled
	b.custom_minimum_size = Vector2(0, 64)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var v := VBoxContainer.new()
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_theme_constant_override("separation", 0)
	var t := lbl(title, 16, Color(DB.PAL.paper, 0.4 if disabled else 1.0), true)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var s := lbl(sub, 12, Color(DB.PAL.bamboo, 0.4 if disabled else 1.0))
	s.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	s.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	t.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	s.clip_text = true
	t.clip_text = true
	s.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(t)
	v.add_child(s)
	b.add_child(v)
	return b


static func panel(child: Control, pad := 12) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", flat(DB.PAL.ink2, DB.PAL.ink3, 1, 8, pad))
	p.add_child(child)
	return p


## 스크롤 상자 —— 손가락 끌기는 TouchScroll 이 맡는다. horizontal 이면 가로로만
static func scroll(horizontal := false) -> ScrollContainer:
	var sc := ScrollContainer.new()
	if horizontal:
		sc.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	else:
		sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	TouchScroll.add(sc)
	return sc


## 가로로 넘기는 띠 —— 칩·진형처럼 한 줄에 다 안 들어가는 것
static func strip(sep := 8) -> Array:
	var sc := scroll(true)
	var h := hbox(sep)
	sc.add_child(h)
	return [sc, h]


## 폭에 맞춰 칸 수를 정하는 격자 —— 카드·아이템 목록 (휴대폰 세로는 두 칸)
static func grid(min_w := 168.0, sep := 8) -> AutoGrid:
	var g := AutoGrid.new()
	g.min_w = min_w
	g.sep = sep
	return g


## 짧은 진동 —— 휴대폰에서 누를 때 손끝 반응
static func buzz(ms := 8) -> void:
	Sfx.play("tap")
	if Settings.haptics and OS.has_feature("mobile"):
		Input.vibrate_handheld(ms)


## 알약 모양 선택지 —— 필터·탭에 쓴다
static func chip(text: String, on: bool, cb: Callable, h := 40) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, h)
	b.add_theme_font_size_override("font_size", 14)
	var P := DB.PAL
	var r := int(h / 2)
	if on:
		b.add_theme_stylebox_override("normal", flat(P.bamboo, P.bamboo, 1, r, 14))
		b.add_theme_stylebox_override("hover", flat(P.bamboo, P.gold, 1, r, 14))
		b.add_theme_color_override("font_color", Color("#1A1508"))
		b.add_theme_color_override("font_hover_color", Color("#1A1508"))
	else:
		b.add_theme_stylebox_override("normal", flat(P.ink2, P.ink4, 1, r, 14))
		b.add_theme_stylebox_override("hover", flat(P.ink3, P.bamboo_dim, 1, r, 14))
	b.add_theme_stylebox_override("pressed", flat(P.ink4, P.bamboo, 1, r, 14))
	for st in ["normal", "hover", "pressed"]:
		var sb: StyleBoxFlat = b.get_theme_stylebox(st)
		sb.content_margin_top = 4
		sb.content_margin_bottom = 4
	b.pressed.connect(func():
		buzz()
		cb.call())
	return b


## 분할 탭 —— [계보 | 순위] 처럼 한 줄을 나눠 고른다
static func segmented(items: Array, cur: String, cb: Callable) -> Control:
	var P := DB.PAL
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", flat(P.ink2, P.ink3, 1, 12, 4))
	var h := hbox(4)
	p.add_child(h)
	for it in items:
		var on: bool = it[0] == cur
		var b := Button.new()
		b.text = it[1]
		b.custom_minimum_size = Vector2(0, 40)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.add_theme_font_size_override("font_size", 15)
		b.add_theme_font_override("font", DB.font_display)
		b.add_theme_stylebox_override("normal", flat(P.ink4 if on else Color(0, 0, 0, 0), P.ink4 if on else Color(0, 0, 0, 0), 0, 9, 6))
		b.add_theme_stylebox_override("hover", flat(P.ink4 if on else P.ink3, P.ink4, 0, 9, 6))
		b.add_theme_stylebox_override("pressed", flat(P.ink4, P.ink4, 0, 9, 6))
		b.add_theme_color_override("font_color", P.paper if on else P.bamboo_dim)
		b.add_theme_color_override("font_pressed_color", P.paper)
		var key: String = it[0]
		b.pressed.connect(func():
			buzz()
			cb.call(key))
		h.add_child(b)
	return p


## 접는 묶음 —— 머리줄을 누르면 펼치고 접는다. open 이면 body 를 붙인다 (닫혀 있으면 body 를 만들지 않아도 된다)
static func fold(title: String, sub: String, open: bool, cb: Callable) -> Button:
	var P := DB.PAL
	var b := Button.new()
	b.custom_minimum_size = Vector2(0, 52)
	b.add_theme_stylebox_override("normal", flat(P.ink2, P.ink3, 1, 10, 12))
	b.add_theme_stylebox_override("hover", flat(P.ink3, P.ink4, 1, 10, 12))
	b.add_theme_stylebox_override("pressed", flat(P.ink3, P.bamboo_dim, 1, 10, 12))
	b.pressed.connect(func():
		buzz()
		cb.call())
	var h := hbox(8)
	h.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	h.offset_left = 14
	h.offset_right = -14
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var t := lbl(title, 16, P.paper, true)
	t.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	t.size_flags_vertical = Control.SIZE_FILL
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(t)
	var s := lbl(sub, 13, P.bamboo)
	s.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	s.size_flags_vertical = Control.SIZE_FILL
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	s.clip_text = true
	s.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(s)
	var ar := lbl("−" if open else "+", 20, P.bamboo_dim, true)
	ar.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	ar.size_flags_vertical = Control.SIZE_FILL
	ar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(ar)
	b.add_child(h)
	return b


## 기호 행동 타일 —— 위에 그림, 아래 두 줄(제목 · 설명). 끝낸 일은 ✔ 로 흐리게
static func tile_act(icon: String, title: String, sub: String, cb: Callable, kind := "", done := false, disabled := false) -> Button:
	var P := DB.PAL
	var b := btn("", cb, kind, 80)
	b.disabled = disabled or done
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if done:
		b.add_theme_stylebox_override("disabled", flat(Color(P.ink2, 0.6), P.ink3, 1, 10, 6))
	var v := vbox(1)
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.offset_left = 4
	v.offset_right = -4
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var a := 0.45 if b.disabled else 1.0
	var ic := Icons.View.new("check" if done else icon, Color(P.jade if done else (P.gold if kind == "gold" else P.paper), a), 24)
	ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(ic)
	for pair in [[title, 14, P.paper, true], [sub, 11, P.bamboo, false]]:
		var l := lbl(pair[0], pair[1], Color(pair[2], a), pair[3])
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		l.clip_text = true
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_child(l)
	b.add_child(v)
	return b


## 기호 칩 —— 한 줄 요약 (보급품 · 소식). 누르면 자세히
static func icon_chip(icon: String, text: String, col: Color, cb: Callable) -> Button:
	var P := DB.PAL
	var b := Button.new()
	b.custom_minimum_size = Vector2(0, 44)
	b.add_theme_stylebox_override("normal", flat(P.ink2, Color(col, 0.55), 1, 22, 0))
	b.add_theme_stylebox_override("hover", flat(P.ink3, col, 1, 22, 0))
	b.add_theme_stylebox_override("pressed", flat(P.ink4, col, 1, 22, 0))
	b.pressed.connect(func():
		buzz()
		cb.call())
	var h := hbox(6)
	h.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	h.offset_left = 10
	h.offset_right = -12
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ic := Icons.View.new(icon, col, 20)
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(ic)
	var l := lbl(text, 13, col.lightened(0.25))
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.size_flags_vertical = Control.SIZE_FILL
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	l.clip_text = true
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(l)
	b.add_child(h)
	return b


## 머리줄 —— 왼쪽 제목, 오른쪽 작은 글씨
static func head(title: String, right := "") -> HBoxContainer:
	var h := hbox(8)
	var t := eyebrow(title)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(t)
	if right != "":
		var r := lbl(right, 12, DB.PAL.bamboo_dim)
		r.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		r.size_flags_vertical = Control.SIZE_FILL
		h.add_child(r)
	return h


static func vbox(sep := 8) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", sep)
	return v


static func hbox(sep := 8) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", sep)
	return h


static func flow(sep := 8) -> HFlowContainer:
	var f := HFlowContainer.new()
	f.add_theme_constant_override("h_separation", sep)
	f.add_theme_constant_override("v_separation", sep)
	return f


## 한 덩어리 —— 머리말 + 내용
static func sect(title: String, body: Control) -> VBoxContainer:
	var v := vbox(6)
	if title != "":
		v.add_child(eyebrow(title))
	v.add_child(body)
	return v


static func stat(value: String, label: String) -> VBoxContainer:
	var v := vbox(0)
	var a := lbl(value, 20, DB.PAL.paper, true)
	a.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var b := lbl(label, 12, DB.PAL.bamboo_dim)
	b.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(a)
	v.add_child(b)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return v


## 금색(고유) 특기 칸 —— 인물마다 하나, 금빛 바탕 · 금 테두리 · 이름 + 레벨. 없으면 null
static func unique_chips(k: String, fs := 13):
	var ts := DB.trait_list(k).filter(func(t): return t.unique)
	if ts.is_empty():
		return null
	var f := flow(4)
	for t in ts:
		var r := rich("[color=#FFF3D0]%s[/color][color=#FFD76E]%d[/color]" % [t.name, t.lv], fs)
		r.autowrap_mode = TextServer.AUTOWRAP_OFF
		var pc := PanelContainer.new()
		pc.add_theme_stylebox_override("panel", flat(Color("#6b5212"), Color("#f0cf6a"), 2, 4, 4))
		pc.mouse_filter = Control.MOUSE_FILTER_PASS
		pc.add_child(r)
		f.add_child(pc)
	return f


static func card_bb(k: String) -> String:
	return "[color=%s]%s[/color]" % [DB.tier_color(k).to_html(false), DB.C[k].name]


static func item_col(id: String) -> Color:
	return Color(DB.D.IGRADE[DB.IT[id].grade])


static func item_text(id: String, amp := 1.0) -> String:
	var it: Dictionary = DB.IT[id]
	var s := "%s +%d%%" % [DB.D.STATNM[it.pri], roundi(it.pa * amp * 100)]
	if it.sa > 0:
		s += " · %s +%d%%" % [DB.D.STATNM[it.sec], roundi(it.sa * amp * 100)]
	if it.rb > 0:
		s += " · 발동 +%d%%p" % roundi(it.rb * amp)
	return s


## 고유기 한 줄 설명 —— 효과 수치로 만든다
static func ult_desc(u: Dictionary) -> String:
	var parts := []
	for comp in u.eff:
		var tg := DB.tgt_name(str(comp.get("tgt", "")))
		match comp.t:
			"hit":
				var s := "%s %s %d%%" % [tg, "물리" if comp.kind == "phys" else "책략", roundi(comp.mult * 100)]
				if comp.has("exec"):
					s += " · 병력 %d%% 이하 즉사" % roundi(comp.exec * 100)
				if comp.has("morale"):
					s += " · 사기 -%d" % roundi(comp.morale * Battle.burst())
				if comp.has("status"):
					s += " · %s" % DB.D.STATUS.get(comp.status.k, {}).get("n", comp.status.k)
				parts.append(s)
			"ally":
				var s := tg
				if comp.has("heal"):
					s += " 병력 회복 %.1f%%" % (comp.heal * Battle.burst() * 100)
				if comp.has("morale"):
					s += " 사기 +%d" % roundi(comp.morale * Battle.burst())
				if comp.has("buff"):
					s += " %s %+d%%" % [DB.D.STATNM.get(comp.buff.stat, comp.buff.stat), roundi(comp.buff.amt * 100)]
				if comp.has("cleanse"):
					s += " 상태 해제"
				parts.append(s)
			"foe":
				var s := tg
				if comp.has("morale"):
					s += " 사기 -%d" % roundi(comp.morale * Battle.burst())
				if comp.has("buff"):
					s += " %s %+d%%" % [DB.D.STATNM.get(comp.buff.stat, comp.buff.stat), roundi(comp.buff.amt * 100)]
				if comp.has("status"):
					s += " %s" % DB.D.STATUS.get(comp.status.k, {}).get("n", comp.status.k)
				parts.append(s)
	return " · ".join(parts)


static func aff_desc(tag: String, which: String) -> String:
	var a: Dictionary = DB.D.AFF[tag]
	var src: Dictionary = a.b if which == "pref" else a.p
	var out := []
	for s in src:
		if s == "pierce":
			out.append("적 후열 직접 타격")
			continue
		var v := roundi((src[s] - 1.0) * 100)
		out.append("%s %s%d%%" % [DB.D.STATNM.get(s, s), "+" if v > 0 else "", v])
	return " · ".join(out)


static func aff_zones(tag: String, which: String) -> String:
	var a: Dictionary = DB.D.AFF[tag]
	if which == "pref":
		return " · ".join(a.pref.map(func(z): return "%s %s" % [z[0], z[1]]))
	return "%s %s" % [a.bad[0], a.bad[1]]


static func pos_name(line: String, col: int) -> String:
	return ("좌" if col == 0 else "우" if col == 2 else "") + line
