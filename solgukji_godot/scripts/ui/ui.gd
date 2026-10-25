class_name UI
extends RefCounted
## 화면 부품 —— 손가락으로 누르기 좋게 버튼은 높이 48 이상. 색은 DB.PAL.

const BTN_H := 52


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
	var l := lbl(text, 13, DB.PAL.bamboo_dim)
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
	b.pressed.connect(cb)
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
	b.custom_minimum_size = Vector2(220, 64)
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
					s += " · 사기 -%d" % roundi(comp.morale)
				if comp.has("status"):
					s += " · %s" % DB.D.STATUS.get(comp.status.k, {}).get("n", comp.status.k)
				parts.append(s)
			"ally":
				var s := tg
				if comp.has("heal"):
					s += " 병력 회복 %d%%" % roundi(comp.heal * 100)
				if comp.has("morale"):
					s += " 사기 +%d" % roundi(comp.morale)
				if comp.has("buff"):
					s += " %s %+d%%" % [DB.D.STATNM.get(comp.buff.stat, comp.buff.stat), roundi(comp.buff.amt * 100)]
				if comp.has("cleanse"):
					s += " 상태 해제"
				parts.append(s)
			"foe":
				var s := tg
				if comp.has("morale"):
					s += " 사기 -%d" % roundi(comp.morale)
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
