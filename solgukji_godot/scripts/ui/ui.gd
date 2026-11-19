class_name UI
extends RefCounted
## 화면 부품 —— 세로 화면(기준 폭 400) 휴대폰용. 손가락으로 누르기 좋게 버튼은 높이 48 이상. 색은 DB.PAL.
## 스크롤은 UI.scroll() 로 만든다 (TouchScroll 이 버튼 위에서 끌어도 스크롤되게 한다).

## ── 공통 규칙 (11/14 UI 감사 #10) ───────────────────────────────────────────────
## 새 화면 · 고치는 화면은 아래 값만 쓴다. 숫자를 직접 쓰지 말 것 (값은 논리 단위 —— 기준 폭 400, 화면 px 는 약 ×1.8).
# 간격 —— 다섯 단계. 0~3 은 글자 줄을 붙일 때만 그대로 쓴다
const SP_XS := 4
const SP_S := 8
const SP_M := 12
const SP_L := 16
const SP_XL := 24
# 글자 크기 —— 다섯 단계 + 큰 글자. FS_TINY 는 타일 안 배지 · 그림 위 숫자 전용 (본문 · 설명 금지)
const FS_TINY := 10
const FS_CAP := 12       # 캡션 · 보조 숫자 · 머리줄 오른쪽 글씨
const FS_BODY := 14      # 본문 · 설명 · 힌트 · 칩
const FS_LABEL := 16     # 버튼 · 이름 · 강조 줄
const FS_TITLE := 20     # 시트 제목 · 큰 수치
const FS_HEAD := 24      # 화면 머리 · 결과 제목
const FS_DISPLAY := 48   # 엔딩 · 방 코드처럼 한 화면에 하나뿐인 큰 글자
# 버튼 높이 —— 보이는 크기. 누르는 범위는 어느 것이든 HIT(48) 이상 (TouchButton)
const BH_XS := 28        # 타일 아래 · 줄 안의 작은 버튼
const BH_S := 40         # 머리줄 · 칩 · 나눔 · 보조 버튼
const BH_M := 50         # 기본 버튼
const BH_L := 60         # 주 행동 · 두 줄 행동 버튼(act) · 시트 아래 확정
const HIT := 48          # 최소 터치 범위 (가로 · 세로)
const ICON_BTN := Vector2(44, 44)      # ☰ · 닫기 ✕ 같은 기호 버튼의 보이는 크기 (누르는 범위는 HIT)
# 카드 타일 —— 세 가지 (가로 × 세로)
const TILE_S := Vector2(46, 72)        # 손패 · 작은 줄
const TILE_M := Vector2(68, 96)        # 목록 그리드 기본
const TILE_L := Vector2(86, 112)       # 추천 · 조합 목표
# 모서리
const R := 4                      # 모서리 반지름 —— 상자 · 버튼 · 칩 모두 이 크기 (11/9, 알약 · 큰 둥근 모서리 금지)
const R_SHEET := 18               # 아래에서 올라오는 시트의 위 두 모서리만 예외
const BTN_H := BH_M
const HAIR := Color(0.914, 0.89, 0.827, 0.10)      # 구분선(hairline) —— 종이색 10%
const WJ := "⁠"              # 단어 잇기(보이지 않음) —— 붙은 한글 음절 사이에 넣어 단어 중간 줄바꿈을 막는다 (keep_words)


static func theme() -> Theme:
	var P := DB.PAL
	var th := Theme.new()
	th.default_font = DB.font_body
	th.default_font_size = FS_BODY
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
	th.set_font_size("normal_font_size", "RichTextLabel", FS_BODY)
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
	th.set_font_size("font_size", "LineEdit", FS_LABEL)
	th.set_font_size("font_size", "CheckButton", FS_BODY)
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


## 단어 중간 줄바꿈 막기 (11/14 감사 #7) —— Godot(ICU)은 한글을 음절마다 끊을 수 있다고 본다(「모\n든」).
## 붙은 한글 음절 사이에 보이지 않는 단어 잇기(WJ)를 넣어 띄어쓰기 자리에서만 끊기게 한다. 한 단어가 줄보다 길면 그때만 음절에서 끊긴다(WORD_SMART)
static func keep_words(s: String) -> String:
	if s.find(WJ) >= 0:
		return s
	var out := PackedStringArray()
	var n := s.length()
	for i in n:
		out.append(s[i])
		if i + 1 < n and _is_syl(s.unicode_at(i)) and _is_syl(s.unicode_at(i + 1)):
			out.append(WJ)
	return "".join(out)


static func _is_syl(c: int) -> bool:
	return c >= 0xAC00 and c <= 0xD7A3


## 여러 줄 글 —— 줄바꿈은 단어 단위(WORD_SMART) + 한글 단어 중간에서 안 끊기게. Label · RichTextLabel(UI.rich) 둘 다
static func wrap_text(l: Control) -> Control:
	if l is Label or l is Button:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.text = keep_words(l.text)
	elif l is RichTextLabel:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		var t: String = l.get_meta("bb", "")
		if t != "":
			l.clear()
			l.append_text(keep_words(t))
	return l


static func lbl(text: String, fs := FS_BODY, col := Color(0, 0, 0, 0), display := false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", fs)
	if col.a > 0:
		l.add_theme_color_override("font_color", col)
	if display:
		l.add_theme_font_override("font", DB.title_font(fs))      # 11/10 큰 제목만 송명, 작은 글자는 굵은 고딕 (DB.TITLE_BIG)
	return l


## 군량 표기 (11/13) —— [쌀가마 기호] [값]. 글자 「군량」 대신 어디서나 같은 모양 (머리띠 · 상점 가격 · 판매 버튼)
static func grain(text: String, fs := FS_BODY, col := Color(0, 0, 0, 0), display := true) -> HBoxContainer:
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
static func grain_btn(pre: String, text: String, cb: Callable, kind := "", h := BTN_H, fs := FS_LABEL) -> Button:
	var b := btn("", cb, kind, h)
	var row := hbox(SP_S)
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
	var l := lbl(text, FS_BODY, DB.PAL.text_dim)
	wrap_text(l)
	return l


static func rich(bb: String, fs := FS_BODY) -> RichTextLabel:
	var r := RichTextLabel.new()
	r.bbcode_enabled = true
	r.fit_content = true
	r.scroll_active = false
	r.mouse_filter = Control.MOUSE_FILTER_PASS
	r.add_theme_font_size_override("normal_font_size", fs)
	r.add_theme_font_size_override("bold_font_size", fs)
	r.set_meta("bb", bb)
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
	var lt := str(sp.get("loot", ""))      # 11/19 토벌 전리품 장비
	if lt != "" and DB.IT.has(lt):
		s += " · [color=%s]%s[/color]" % [str(DB.D.IGRADE.get(DB.IT[lt].grade, "#ffffff")), DB.IT[lt].name]
	var sg := int(sp.get("streak_g", 0))      # 11/19 연승 · 연패 보너스
	if sg > 0:
		s += " · [color=#%s]%s 군량 +%d[/color]" % [DB.PAL.gold.to_html(false), Run.streak_text(int(sp.get("streak", 0))), sg]
	if bool(sp.get("held", false)):      # 11/12 온라인 —— 전투 보상은 다음 아침(1페이즈)에 지급
		s += " · 아침에 지급"
	return s


## 결과 정리 줄 —— 조각을 "  ·  " 로 잇는다 (BBCode 가능). 기본 글자색은 bamboo
static func result_line(parts: Array) -> RichTextLabel:
	var r := rich("[color=#%s]%s[/color]" % [DB.PAL.bamboo.to_html(false), "  ·  ".join(parts)], FS_BODY)
	wrap_text(r)
	return r


static func eyebrow(text: String) -> Label:
	var l := lbl(text, FS_BODY, DB.PAL.bamboo, true)
	return l


## 버튼 —— kind: "pri"/"gold"(주 행동 —— 화면에 하나) · ""(기본) · "ghost"(테두리만) · "warn"(위험). 높이는 BH_* 중 하나.
## 보이는 높이가 HIT 보다 작아도 누르는 범위는 HIT (TouchButton)
static func btn(text: String, cb: Callable, kind := "", h := BTN_H) -> TouchButton:
	var b := TouchButton.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, h)
	b.add_theme_font_size_override("font_size", FS_LABEL)
	b.pressed.connect(func():
		buzz()
		cb.call())
	var none := Color(0, 0, 0, 0)
	match kind:
		"pri", "gold":      # 주 행동은 금 한 가지 —— 먹금 바탕 + 금 얇은 선 (옥색 바탕은 걷었다 —— 옥색은 수치 강조에만)
			b.add_theme_stylebox_override("normal", flat(DB.PAL.gold.darkened(0.72), Color(DB.PAL.gold, 0.85), 1, R, 10))
			b.add_theme_stylebox_override("hover", flat(DB.PAL.gold.darkened(0.6), DB.PAL.gold, 1, R, 10))
			b.add_theme_stylebox_override("pressed", flat(DB.PAL.gold.darkened(0.8), DB.PAL.gold, 1, R, 10))      # 눌림 = 같은 색 한 단계 어둡게 (다른 색으로 바뀌지 않게)
		"warn":      # 인장 붉음 —— 경고 · 위험
			b.add_theme_stylebox_override("normal", flat(DB.PAL.seal.darkened(0.35), none, 0, R, 10))
			b.add_theme_stylebox_override("hover", flat(DB.PAL.seal.darkened(0.2), none, 0, R, 10))
			b.add_theme_stylebox_override("pressed", flat(DB.PAL.seal.darkened(0.5), none, 0, R, 10))
		"ghost":
			b.add_theme_stylebox_override("normal", flat(none, Color(DB.PAL.paper, 0.16), 1, R, 10))
			b.add_theme_stylebox_override("hover", flat(Color(DB.PAL.paper, 0.05), Color(DB.PAL.paper, 0.28), 1, R, 10))
			b.add_theme_stylebox_override("pressed", flat(Color(DB.PAL.paper, 0.1), Color(DB.PAL.paper, 0.28), 1, R, 10))
	return b


## 버튼 종류별 이름 —— 새 코드는 btn(…, kind, h) 대신 이것들로
static func btn_primary(text: String, cb: Callable, h := BH_M) -> Button:
	return btn(text, cb, "pri", h)


static func btn_secondary(text: String, cb: Callable, h := BH_M) -> Button:
	return btn(text, cb, "", h)


static func btn_ghost(text: String, cb: Callable, h := BH_M) -> Button:
	return btn(text, cb, "ghost", h)


## 작은 버튼 —— 머리줄 · 줄 안 (보이는 높이 BH_S, 누르는 범위 HIT)
static func btn_small(text: String, cb: Callable, kind := "") -> Button:
	var b := btn(text, cb, kind, BH_S)
	b.add_theme_font_size_override("font_size", FS_BODY)
	return b


## 기호 버튼 —— ☰ · ✕ 처럼 글자 하나. 바탕 없이 보이는 크기 vis, 누르는 범위는 HIT × HIT
static func icon_btn(glyph: String, cb: Callable, vis := ICON_BTN, fs := FS_TITLE) -> TouchButton:
	var b := btn(glyph, cb, "ghost", int(vis.y))
	b.custom_minimum_size = vis
	b.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	b.add_theme_font_size_override("font_size", fs)
	return b


## 빈 상태 카드 (11/14 UI 4단계) —— 기호 + 제목 + 한두 줄 설명 (+ 다음 행동 버튼). 징집 첫날 · 소식 · 인연처럼 "아무것도 없다"를 한 모양으로
static func empty(icon: String, title: String, desc: String, action: Button = null) -> PanelContainer:
	var v := vbox(SP_S)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	var ic := Icons.View.new(icon, Color(DB.PAL.bamboo, 0.8), 32)
	ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(ic)
	var t := lbl(title, FS_LABEL, DB.PAL.paper, true)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	if desc != "":
		var d := hint(desc)
		d.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(d)
	if action != null:
		action.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		action.custom_minimum_size.x = maxf(action.custom_minimum_size.x, 160)
		v.add_child(action)
	var pc := panel(v, SP_XL)
	pc.custom_minimum_size.y = 160
	return pc


## 두 줄 버튼 —— 굵은 제목 + 작은 설명 (징집·전투의 큰 행동 버튼)
static func act(title: String, sub: String, cb: Callable, kind := "", disabled := false) -> Button:
	var b := btn("", cb, kind, BH_L)
	b.disabled = disabled
	b.custom_minimum_size = Vector2(0, BH_L)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var v := VBoxContainer.new()
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_theme_constant_override("separation", 0)
	var t := lbl(title, FS_LABEL, Color(DB.PAL.paper, 0.4 if disabled else 1.0), true)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var s := lbl(sub, FS_CAP, Color(DB.PAL.bamboo, 0.4 if disabled else 1.0))
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
static func strip(sep := SP_S) -> Array:
	var sc := scroll(true)
	var h := hbox(sep)
	sc.add_child(h)
	return [sc, h]


## 11/15 성능: 막 붙인 페이지(c)에 부모 MarginContainer 가 줄 자리를 미리 준다.
## 컨테이너는 트리에 들어온 순서(위 → 아래)로 자리 잡기를 예약하는데, 붙인 부모의 자리 잡기는 그 맨 뒤에 온다 —— 그래서 페이지 안 격자들이
## 먼저 엉뚱한 폭(자기 최소 폭)으로 칸을 나누고 타일이 그 크기로 한 번 그려진 다음, 부모가 제 폭을 주면 다시 나누고 다시 그렸다 (페이지를 새로 짓는 프레임마다 타일을 두 번).
## 붙이자마자 폭을 정해 주면 위에서 아래로 한 번에 맞는다. 부모가 나중에 주는 자리와 같은 값이라 화면은 달라지지 않는다
static func presize(c: Control) -> void:
	var p := c.get_parent() as MarginContainer
	if p == null or p.size.x <= 0.0:
		return
	var l := p.get_theme_constant("margin_left")
	var t := p.get_theme_constant("margin_top")
	var w := p.size.x - l - p.get_theme_constant("margin_right")
	var h := p.size.y - t - p.get_theme_constant("margin_bottom")
	if w <= 0.0:
		return
	var in_scroll := p.get_parent() is ScrollContainer      # 스크롤 안의 내용은 높이가 내용만큼 —— 폭만 맞춘다
	c.position = Vector2(l, t)
	c.size = Vector2(w, c.get_combined_minimum_size().y if in_scroll else maxf(h, c.get_combined_minimum_size().y))


## 11/15 성능: 이 칸이 화면(뷰포트) 밖에 통째로 나가 있는가 —— 카드 타일은 화면 밖이면 그리지 않고(스크롤 아래 150장을 페이지를 지을 때마다 그렸다),
## 자리가 바뀌어(스크롤 · 시트가 올라옴 · 자리 잡기) 화면에 들어오면 그때 그린다 (MiniTile · CardTile 의 _draw · _notification). 여유 96px
static func off_screen(c: Control) -> bool:
	return not c.get_viewport_rect().grow(96.0).intersects(c.get_global_rect())


## 폭에 맞춰 칸 수를 정하는 격자 —— 카드·아이템 목록 (휴대폰 세로는 두 칸)
static func grid(min_w := 168.0, sep := SP_S) -> AutoGrid:
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
static func chip(text: String, on: bool, cb: Callable, h := BH_S) -> Button:
	var b := TouchButton.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, h)
	b.add_theme_font_size_override("font_size", FS_BODY)
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


## 분할 탭 —— [계보 | 순위] 처럼 한 줄을 나눠 고른다. 고르기 · 나눔 · 켜고 끄기 줄은 모두 이것 하나 (11/14 감사 #10)
## 모양: 어두운 바탕 트랙(가는 테두리 —— 먹 바탕 · 시트 위 어디서나 보이게) + 고른 칸만 ink4 채움 + 금 아래선.
## cur 가 어느 칸과도 같지 않으면 아무 칸도 고르지 않은 상태 (편성 보유/보급품 닫힘)
static func segmented(items: Array, cur: String, cb: Callable) -> Control:
	var P := DB.PAL
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", flat(Color(P.ink, 0.75), HAIR, 1, R, 3))
	var h := hbox(SP_XS)
	p.add_child(h)
	var none := Color(0, 0, 0, 0)
	for it in items:
		var on: bool = it[0] == cur
		var b := TouchButton.new()
		b.text = it[1]
		b.custom_minimum_size = Vector2(0, BH_S)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.add_theme_font_size_override("font_size", FS_BODY)
		b.add_theme_font_override("font", DB.title_font(FS_BODY))
		var sel := flat(P.ink4, P.gold, 0, R, 6)
		sel.border_width_bottom = 2
		b.add_theme_stylebox_override("normal", sel if on else flat(none, none, 0, R, 6))
		b.add_theme_stylebox_override("hover", sel if on else flat(P.ink3, none, 0, R, 6))
		b.add_theme_stylebox_override("pressed", sel)
		b.add_theme_stylebox_override("hover_pressed", sel)
		b.add_theme_color_override("font_color", P.paper if on else P.text_dim)
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
	b.custom_minimum_size = Vector2(0, BH_M)
	b.add_theme_stylebox_override("normal", flat(P.ink2, Color(0, 0, 0, 0), 0, R, 12))
	b.add_theme_stylebox_override("hover", flat(P.ink3, Color(0, 0, 0, 0), 0, R, 12))
	b.add_theme_stylebox_override("pressed", flat(P.ink3, Color(0, 0, 0, 0), 0, R, 12))
	b.pressed.connect(func():
		buzz()
		cb.call())
	var h := hbox(SP_S)
	h.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	h.offset_left = 14
	h.offset_right = -14
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var t := lbl(title, FS_LABEL, P.paper, true)
	t.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	t.size_flags_vertical = Control.SIZE_FILL
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(t)
	var s := lbl(sub, FS_BODY, P.bamboo)
	s.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	s.size_flags_vertical = Control.SIZE_FILL
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	s.clip_text = true
	s.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(s)
	var ar := lbl("▴" if open else "▾", FS_BODY, P.text_dim, true)      # 11/14 UI 4단계: 접힘 표시 통일 —— ▾ 닫힘 · ▴ 열림
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
	var b := btn("", cb, kind, BH_L if not low else BH_S)      # 11/2 사용자: 80 → 58
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
	for pair in [[title, FS_BODY, P.paper, true], [sub, FS_CAP, P.bamboo, false]]:
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
	var b := TouchButton.new()
	b.custom_minimum_size = Vector2(0, BH_S)
	b.add_theme_stylebox_override("normal", flat(P.ink2, Color(0, 0, 0, 0), 0, R, 0))
	b.add_theme_stylebox_override("hover", flat(P.ink3, Color(0, 0, 0, 0), 0, R, 0))
	b.add_theme_stylebox_override("pressed", flat(P.ink4, Color(0, 0, 0, 0), 0, R, 0))
	b.pressed.connect(func():
		buzz()
		cb.call())
	var h := hbox(SP_S)
	h.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	h.offset_left = 10
	h.offset_right = -12
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ic := Icons.View.new(icon, col, 20)
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(ic)
	var l := lbl(text, FS_BODY, col.lightened(0.25))
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
	var h := hbox(SP_S)
	var t := eyebrow(title)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(t)
	if right != "":
		var r := lbl(right, FS_CAP, DB.PAL.text_dim)
		r.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		r.size_flags_vertical = Control.SIZE_FILL
		h.add_child(r)
	return h


static func vbox(sep := SP_S) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", sep)
	return v


static func hbox(sep := SP_S) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", sep)
	return h


static func flow(sep := SP_S) -> HFlowContainer:
	var f := HFlowContainer.new()
	f.add_theme_constant_override("h_separation", sep)
	f.add_theme_constant_override("v_separation", sep)
	return f


## 한 덩어리 —— 머리말 + 내용
static func sect(title: String, body: Control) -> VBoxContainer:
	var v := vbox(SP_S)
	if title != "":
		v.add_child(eyebrow(title))
	v.add_child(body)
	return v


static func stat(value: String, label: String) -> VBoxContainer:
	var v := vbox(0)
	var a := lbl(value, FS_TITLE, DB.PAL.paper, true)
	a.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var b := lbl(label, FS_CAP, DB.PAL.text_dim)
	b.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(a)
	v.add_child(b)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return v


## 금색(고유) 특기 칸 —— 인물마다 하나, 금빛 바탕 · 금 테두리 · 이름 + 레벨. 없으면 null
static func unique_chips(k: String, fs := FS_BODY):
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


## 그려 넣는 글자(draw_string) 크기 —— start 에서 줄여 w 에 들어가는 크기. 아무리 줄여도 lo(보통 FS_TINY) 아래로는 내리지 않는다 (11/14 감사 #10)
static func fit_fs(f: Font, s: String, start: int, lo: int, w: float) -> int:
	var fs := start
	while fs > lo and f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > w:
		fs -= 1
	return fs


## 폭 w 에 들어가게 뒤를 … 으로 줄인 글자 (draw_string 은 넘쳐도 자르지 않는다)
static func ellipsize(f: Font, s: String, fs: int, w: float) -> String:
	if f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x <= w:
		return s
	var t := s
	while t.length() > 1 and f.get_string_size(t + "…", HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > w:
		t = t.substr(0, t.length() - 1)
	return t + "…"


static func pos_name(line: String, col: int) -> String:
	return ["좌익 ", "좌", "", "우", "우익 "][clampi(col, 0, 4)] + line      # 11/6 5열
