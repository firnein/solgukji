class_name UI
extends RefCounted
## 화면 부품 —— 세로 화면(기준 폭 400) 휴대폰용. 손가락으로 누르기 좋게 버튼은 높이 48 이상. 색은 DB.PAL.
## 스크롤은 UI.scroll() 로 만든다 (TouchScroll 이 버튼 위에서 끌어도 스크롤되게 한다).

const BTN_H := 50
const R := 4                      # 모서리 반지름 —— 상자 · 버튼 · 칩 모두 이 크기 (11/9, 알약 · 큰 둥근 모서리 금지)
const HAIR := Color(0.914, 0.89, 0.827, 0.10)      # 구분선(hairline) —— 종이색 10%


static func theme() -> Theme:
	var P := DB.PAL
	var th := Theme.new()
	th.default_font = DB.font_body
	th.default_font_size = 15
	# 11/9 사용자: AI 티를 걷는다 —— 상자는 테두리 없는 먹색 면 + 작은 모서리, 선택 · 눌림에만 금 얇은 선 (작업현황 ㊽ 규칙)
	var none := Color(0, 0, 0, 0)
	th.set_stylebox("panel", "PanelContainer", flat(P.ink2, none, 0, R, 12))
	th.set_stylebox("normal", "Button", flat(P.ink3, none, 0, R, 10))
	th.set_stylebox("hover", "Button", flat(P.ink4, none, 0, R, 10))
	th.set_stylebox("pressed", "Button", flat(P.ink4, P.gold, 1, R, 10))
	th.set_stylebox("hover_pressed", "Button", flat(P.ink4, P.gold, 1, R, 10))
	th.set_stylebox("disabled", "Button", flat(Color(P.ink3, 0.5), none, 0, R, 10))
	th.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	th.set_color("font_color", "Button", P.paper)
	th.set_color("font_hover_color", "Button", P.paper)
	th.set_color("font_pressed_color", "Button", P.paper)
	th.set_color("font_hover_pressed_color", "Button", P.paper)
	th.set_color("font_disabled_color", "Button", Color(P.paper, 0.35))
	th.set_color("font_color", "Label", P.paper)
	th.set_color("default_color", "RichTextLabel", P.paper)
	th.set_font_size("normal_font_size", "RichTextLabel", 14)
	th.set_font("normal_font", "RichTextLabel", DB.font_body)
	th.set_font("bold_font", "RichTextLabel", DB.font_bold)
	th.set_stylebox("normal", "OptionButton", flat(P.ink3, none, 0, R, 10))
	th.set_stylebox("hover", "OptionButton", flat(P.ink4, none, 0, R, 10))
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
	th.set_stylebox("normal", "LineEdit", flat(P.ink3, none, 0, R, 10))      # 11/9 사용자: 온라인 팝업 입력 칸 —— 상자 규칙(먹색 면 · 테두리 없음)으로, 초점만 가는 선
	th.set_stylebox("focus", "LineEdit", flat(P.ink3, P.bamboo_dim, 1, R, 10))
	th.set_font_size("font_size", "LineEdit", 16)
	th.set_font_size("font_size", "CheckButton", 15)
	return th


static func flat(bg: Color, border: Color, bw := 1, rad := 6, pad := 8) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(bw)
	sb.set_corner_radius_all(mini(rad, R))      # 11/9 모서리는 R 까지만 (예전 8 · 10 · 14 알약은 모두 R)
	sb.set_content_margin_all(pad)
	return sb


## 구분선 —— 한 장의 패널 안에서 줄을 나눈다 (상자를 겹치지 않고)
static func hair(vertical := false) -> ColorRect:
	var r := ColorRect.new()
	r.color = HAIR
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if vertical:
		r.custom_minimum_size = Vector2(1, 0)
	else:
		r.custom_minimum_size = Vector2(0, 1)
	return r


static func lbl(text: String, fs := 15, col := Color(0, 0, 0, 0), display := false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", fs)
	if col.a > 0:
		l.add_theme_color_override("font_color", col)
	if display:
		l.add_theme_font_override("font", DB.title_font(fs))      # 11/10 큰 제목만 송명, 작은 글자는 굵은 고딕 (DB.TITLE_BIG)
	return l


## 군량 표기 (11/13) —— [쌀가마 기호] [값]. 글자 「군량」 대신 어디서나 같은 모양 (머리띠 · 상점 가격 · 판매 버튼)
static func grain(text: String, fs := 15, col := Color(0, 0, 0, 0), display := true) -> HBoxContainer:
	var h := hbox(maxi(2, int(fs * 0.2)))
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var c := col if col.a > 0 else DB.PAL.gold
	var ic := Icons.View.new("grain", c, roundf(fs * 1.15))
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(ic)
	var l := lbl(text, fs, c, display)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(l)
	return h


## 군량 기호가 든 버튼 —— 「판매  [쌀가마] +N」. 글자는 버튼 가운데에 (Button.text 는 비우고 위에 얹는다)
static func grain_btn(pre: String, text: String, cb: Callable, kind := "", h := BTN_H, fs := 16) -> Button:
	var b := btn("", cb, kind, h)
	var row := hbox(6)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if pre != "":
		var pl := lbl(pre, fs, DB.PAL.paper)
		pl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		row.add_child(pl)
	row.add_child(grain(text, fs, DB.PAL.gold, false))
	b.add_child(row)
	b.custom_minimum_size.x = maxf(b.custom_minimum_size.x, row.get_combined_minimum_size().x + 20)
	return b


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


## 결과 정리 줄의 기본패 조각 (11/10) —— "기본패 +N", 토벌 성과 보너스가 있으면 금색으로 "(대승 +M)" · 선택권도 늘었으면 "(대승 +M · 선택권 +1)". 보너스는 Run.last_spoil 의 bonus · bonus_ticket · perf_r
static func spoil_bb(sp) -> String:
	var s := "기본패 +%d" % int(sp.n)
	var b := int(sp.get("bonus", 0))
	var t := int(sp.get("bonus_ticket", 0))
	if b > 0 or t > 0:
		var tag := "보너스" if bool(sp.get("flat", false)) else ("대승" if float(sp.get("perf_r", 0.0)) >= Run.QUEST_BONUS_BIG else "선전")
		var inner := "%s +%d" % [tag, b] if b > 0 else tag
		if t > 0:
			inner += " · " + Run.bonus_ticket_text(str(sp.get("src", "")), t)
		s += " [color=#%s](%s)[/color]" % [DB.PAL.gold.to_html(false), inner]
	var ht := int(sp.get("hard_tier", 0))      # 11/12 험지 토벌 돌파 보상
	if ht > 0:
		s += " [color=#%s](험지 돌파 · %s %s +1)[/color]" % [DB.PAL.gold.to_html(false), DB.TIER[ht].n, Run.ticket_noun(ht, true)]
	if bool(sp.get("held", false)):      # 11/12 온라인 —— 전투 보상은 다음 아침(1페이즈)에 지급
		s += " · 아침에 지급"
	return s


## 결과 정리 줄 —— 조각을 "  ·  " 로 잇는다 (BBCode 가능). 기본 글자색은 bamboo
static func result_line(parts: Array) -> RichTextLabel:
	var r := rich("[color=#%s]%s[/color]" % [DB.PAL.bamboo.to_html(false), "  ·  ".join(parts)], 13)
	r.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
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
	var none := Color(0, 0, 0, 0)
	match kind:
		"pri", "gold":      # 주 행동은 금 한 가지 —— 먹금 바탕 + 금 얇은 선 (옥색 바탕은 걷었다 —— 옥색은 수치 강조에만)
			b.add_theme_stylebox_override("normal", flat(DB.PAL.gold.darkened(0.72), Color(DB.PAL.gold, 0.85), 1, R, 10))
			b.add_theme_stylebox_override("hover", flat(DB.PAL.gold.darkened(0.6), DB.PAL.gold, 1, R, 10))
		"warn":      # 인장 붉음 —— 경고 · 위험
			b.add_theme_stylebox_override("normal", flat(DB.PAL.seal.darkened(0.35), none, 0, R, 10))
			b.add_theme_stylebox_override("hover", flat(DB.PAL.seal.darkened(0.2), none, 0, R, 10))
		"ghost":
			b.add_theme_stylebox_override("normal", flat(none, Color(DB.PAL.paper, 0.16), 1, R, 10))
			b.add_theme_stylebox_override("hover", flat(Color(DB.PAL.paper, 0.05), Color(DB.PAL.paper, 0.28), 1, R, 10))
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
	p.add_theme_stylebox_override("panel", flat(DB.PAL.ink2, Color(0, 0, 0, 0), 0, R, pad))
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


## 오른쪽 쓸기(팝업 닫기)를 시작하면 안 되는 자리 —— 슬라이더 · 스크롤바 · 입력칸 위에서 끌면 그 컨트롤이 움직여야 한다 (11/11)
static func swipe_blocked_at(root: Node, pos: Vector2) -> bool:
	if root == null:
		return false
	for c in root.get_children():
		if c is Control and not c.is_visible_in_tree():
			continue
		if c is Slider or c is ScrollBar or c is LineEdit or c is TextEdit or c is SpinBox:
			if c.get_global_rect().has_point(pos):
				return true
		if swipe_blocked_at(c, pos):
			return true
	return false


## 선택지 —— 필터 · 탭에 쓴다. 고른 것은 금 얇은 선, 나머지는 테두리 없는 먹색 (알약 · 색 칠한 칩 아님)
static func chip(text: String, on: bool, cb: Callable, h := 40) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, h)
	b.add_theme_font_size_override("font_size", 14)
	var P := DB.PAL
	var none := Color(0, 0, 0, 0)
	if on:
		b.add_theme_stylebox_override("normal", flat(P.ink3, P.gold, 1, R, 14))
		b.add_theme_stylebox_override("hover", flat(P.ink4, P.gold, 1, R, 14))
		b.add_theme_color_override("font_color", P.paper)
		b.add_theme_color_override("font_hover_color", P.paper)
	else:
		b.add_theme_stylebox_override("normal", flat(P.ink2, none, 0, R, 14))
		b.add_theme_stylebox_override("hover", flat(P.ink3, none, 0, R, 14))
		b.add_theme_color_override("font_color", P.bamboo)
	b.add_theme_stylebox_override("pressed", flat(P.ink4, P.gold, 1, R, 14))
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
	p.add_theme_stylebox_override("panel", flat(P.ink2, Color(0, 0, 0, 0), 0, R, 3))
	var h := hbox(4)
	p.add_child(h)
	for it in items:
		var on: bool = it[0] == cur
		var b := Button.new()
		b.text = it[1]
		b.custom_minimum_size = Vector2(0, 40)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.add_theme_font_size_override("font_size", 15)
		b.add_theme_font_override("font", DB.title_font(15))
		b.add_theme_stylebox_override("normal", flat(P.ink4 if on else Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, 3, 6))
		b.add_theme_stylebox_override("hover", flat(P.ink4 if on else P.ink3, Color(0, 0, 0, 0), 0, 3, 6))
		b.add_theme_stylebox_override("pressed", flat(P.ink4, Color(0, 0, 0, 0), 0, 3, 6))
		b.add_theme_color_override("font_color", P.paper if on else P.bamboo_dim)
		b.add_theme_color_override("font_hover_color", P.paper)
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
	b.add_theme_stylebox_override("normal", flat(P.ink2, Color(0, 0, 0, 0), 0, R, 12))
	b.add_theme_stylebox_override("hover", flat(P.ink3, Color(0, 0, 0, 0), 0, R, 12))
	b.add_theme_stylebox_override("pressed", flat(P.ink3, Color(0, 0, 0, 0), 0, R, 12))
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
## 등급 표시 —— 타일 아래에 등급색 띠 (11/2 등급별 보급 칸)
static func tier_mark(b: Control, t: int) -> void:
	var r := ColorRect.new()
	r.color = DB.TIER[t].c
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	r.offset_top = -4
	r.offset_left = 6
	r.offset_right = -6
	r.offset_bottom = -2
	b.add_child(r)


static func tile_act(icon: String, title: String, sub: String, cb: Callable, kind := "", done := false, disabled := false) -> Button:
	var P := DB.PAL
	var low := sub == ""      # 11/7 사용자: 설명 글이 없으면 기호 · 제목을 옆으로 나란히 한 줄 (징집 페이지 선택권 묶음이 세로로 너무 컸다 —— 46 → 34)
	var b := btn("", cb, kind, 58 if not low else 34)      # 11/2 사용자: 80 → 58
	b.disabled = disabled or done
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if done:
		b.add_theme_stylebox_override("disabled", flat(Color(P.ink2, 0.6), Color(0, 0, 0, 0), 0, R, 6))
	var v: BoxContainer
	if low:
		v = hbox(3)
	else:
		v = vbox(1)
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.offset_left = 6 if low else 4
	v.offset_right = -4
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var a := 0.45 if b.disabled else 1.0
	var ic := Icons.View.new("check" if done else icon, Color(P.jade if done else (P.gold if kind == "gold" else P.paper), a), 16 if low else 18)
	ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	v.add_child(ic)
	for pair in [[title, 13, P.paper, true], [sub, 10, P.bamboo, false]]:
		if pair[0] == "":
			continue
		var l := lbl(pair[0], pair[1], Color(pair[2], a), pair[3])
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		l.clip_text = true
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if low:
			l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			l.size_flags_vertical = Control.SIZE_FILL
			l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		v.add_child(l)
	b.add_child(v)
	return b


## 기호 칩 —— 한 줄 요약 (보급품 · 소식). 누르면 자세히
static func icon_chip(icon: String, text: String, col: Color, cb: Callable) -> Button:
	var P := DB.PAL
	var b := Button.new()
	b.custom_minimum_size = Vector2(0, 36)
	b.add_theme_stylebox_override("normal", flat(P.ink2, Color(0, 0, 0, 0), 0, R, 0))
	b.add_theme_stylebox_override("hover", flat(P.ink3, Color(0, 0, 0, 0), 0, R, 0))
	b.add_theme_stylebox_override("pressed", flat(P.ink4, Color(0, 0, 0, 0), 0, R, 0))
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
		var r := rich("[color=#FFF3D0]%s[/color]" % t.name, fs)       # 11/3 사용자: 고유 특기에는 레벨을 적지 않는다
		r.autowrap_mode = TextServer.AUTOWRAP_OFF
		var pc := PanelContainer.new()
		pc.add_theme_stylebox_override("panel", flat(Color(DB.PAL.gold, 0.16), DB.PAL.gold, 1, R, 4))
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


## 고유기 한 줄 설명 —— 효과 수치로 만든다. tier 를 주면 타격은 그 등급 전투의 배율(turn_mul)을 곱한 실제 값으로
## (고유기 피해에는 turn_mul 이 곱해진다 —— 일반 기술 수치와 나란히 비교되게, 11/3)
static func ult_desc(u: Dictionary, tier := 0) -> String:
	var tm := Battle.turn_mul_for(tier) if tier > 0 else 1.0
	var parts := []
	var cap := float(Battle.ult_cap.get(clampi(tier, 6, 8), 0.0)) if tier > 0 else 0.0      # 11/7 한 방 상한 —— 한 부대가 이번 고유기에 잃는 병력은 최대 병력의 이만큼까지 (한 번만 적는다)
	for comp in u.eff:
		var tg := DB.tgt_name(str(comp.get("tgt", "")))
		if str(comp.get("tgt", "")) == "all" and comp.t != "ally":      # 11/7 고유기의 '적 전체' 는 전장 전체가 아니라 노리는 적 둘레 (RtBattle.ult_all_r)
			tg = "노리는 적 둘레 전체"
		match comp.t:
			"hit":
				var s := "%s 피해 %d%%" % [tg, roundi(comp.mult * tm * 100)]
				if cap > 0.0:
					s += " (한 부대 최대 병력의 %d%%까지)" % roundi(cap * 100)
					cap = 0.0
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
	return ["좌익 ", "좌", "", "우", "우익 "][clampi(col, 0, 4)] + line      # 11/6 5열
