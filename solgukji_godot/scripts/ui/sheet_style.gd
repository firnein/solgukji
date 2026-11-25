class_name SheetStyle
extends RefCounted
## 11/21 장수창 공통 시각 언어 —— 갈무리창(GameScreen.recipe_sheet) · 상세창(card_info) · 전투 장수창(battle_unit_card)이 같은 모양을 쓴다.
## 사용자: "갈무리창과 상세창, 전투 장수창은 톤앤매너가 일치해야 함" —— 머리(이름 · 등급 · 세력), 능력치, 섹션 머리, 정보 행, 칩,
## 판 질감(빗금 · 금빛 그라데이션 —— 1.1j 고유기 카드), 상태 카드, 진행 막대, 버튼 · 탭 결을 여기 한 곳에서 정한다.
## 화면 상태(Run · 시트)에 묶이지 않게 카드 id · 숫자 · 문자열 · Callable 만 받는다. 색은 DB.PAL 위의 '장수창 단계'다 (값은 PAL 과 같은 색).

# ── 글자 크기 단계 —— 장수창 안에서는 이 여섯 단계만 쓴다 ──
const FS_NAME := 24      # 장수 이름 (시트 제목)
const FS_STAT := 22      # 능력치 큰 숫자
const FS_VALUE := 16     # 정보 행의 값 · 카드 이름 · 버튼
const FS_ROW := 14       # 본문 · 섹션 머리 · 상태 카드 제목
const FS_SUB := 12       # 라벨 · 덧말 · 칩
const FS_TAG := 10       # 꼬리표 · 작은 수치 이름

# ── 색 토큰 ──
const GOLD := Color("#D9A64B")         # PAL.gold —— 주 행동 · 고유 · 보상
const GOLD_HI := Color("#F2D08A")      # 금 글자 · 밝은 테
const GOLD_INK := Color("#FFF4DA")     # 금 판 위 글자
const VAL := Color("#8FD4C2")          # 수치 옥색 (_hl 과 같은 색) —— 좋음 · 갖춤
const WARN := Color("#E0806F")         # PAL.danger —— 부족 · 막힘 글자
const TEXT := Color("#E9E3D3")         # PAL.paper
const DIM := Color("#A89574")          # PAL.text_dim —— 라벨 · 덧말
const LABEL := Color("#C6AC7C")        # PAL.bamboo —— 섹션 머리 · 기호
const LINE := Color(0.914, 0.89, 0.827, 0.10)      # UI.HAIR —— 구분선
const PLATE := Color(0.141, 0.180, 0.286, 0.70)    # ink3 70% —— 판 바닥
const WELL := Color(0.075, 0.102, 0.169, 0.55)     # ink 55% —— 칩 · 칸 바닥 (판보다 한 단계 깊게)
const ATK := Color("#ff6b5a")          # 물리 공격 숫자
const ATK_INT := Color("#6fa8ff")      # 책략 공격 숫자

# ── 여백 ──
const PAD := 12
const GAP := 8
const LABEL_W := 78      # 정보 행 라벨 칸 폭 —— 모든 행의 값 왼끝이 맞는다
const NUM_W := 92        # 정보 행 오른쪽 수치 칸 폭

## 판 모양 (Plate.mode)
enum { PLAIN, ACCENT, HERO }


# ───────── 머리 ─────────

## 시트 머리 바탕 —— 등급 색이 왼쪽에서 번지는 그라데이션 + 오른쪽 옅은 빗금 + 아래 금빛 가는 선. 머리 PanelContainer 의 첫 자식으로 깐다
static func head_wash(col: Color) -> Control:
	return Wash.new(col)


## 이름 아래 한 줄 —— [등급 리본] [세력 칩] [병종 기호 · 피해 종류]. extra: [[글, 색], …] 덧칩 (전투 장수창의 상태 등)
static func meta_row(k: String, extra: Array = []) -> Control:
	var c: Dictionary = DB.C[k]
	var f := UI.flow(6)
	f.mouse_filter = Control.MOUSE_FILTER_IGNORE
	f.add_child(Ribbon.new(DB.tier_name(k), DB.tier_color(k)))
	var fac := str(c.get("fac", ""))
	if DB.D.FAC.has(fac):
		f.add_child(chip(str(DB.D.FAC[fac].get("full", fac)), DB.fac_color(fac), "dot"))
	var tag := str(c.tag)
	var th := UI.hbox(4)
	th.mouse_filter = Control.MOUSE_FILTER_IGNORE
	th.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if DB.ICON.has(tag):
		var ti := TextureRect.new()
		ti.texture = DB.ICON[tag]
		ti.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		ti.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		ti.custom_minimum_size = Vector2(14, 14)
		ti.modulate = LABEL
		ti.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ti.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		th.add_child(ti)
	th.add_child(UI.lbl(tag, FS_SUB, TEXT))
	var gt := DB.guard_text(tag)
	if gt != "":
		th.add_child(UI.lbl("· " + gt, FS_SUB, DB.kind_col(tag)))
	var tp := PanelContainer.new()
	var sb := UI.flat(WELL, Color(0, 0, 0, 0), 0, UI.R, 0)
	sb.content_margin_left = 7
	sb.content_margin_right = 8
	sb.content_margin_top = 2
	sb.content_margin_bottom = 2
	tp.add_theme_stylebox_override("panel", sb)
	tp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tp.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	tp.add_child(th)
	f.add_child(tp)
	for e in extra:
		f.add_child(chip(str(e[0]), e[1] if e.size() > 1 else LABEL, "soft"))
	return f


## 등급 리본 하나 (meta_row 가 쓴다 · 따로 써도 된다)
static func tier_ribbon(name: String, col: Color) -> Control:
	return Ribbon.new(name, col)


# ───────── 칩 · 머리 · 줄 ─────────

## 칩 —— style: "soft"(색 옅은 면 + 테) · "solid"(색 면 · 먹 글자) · "line"(테만) · "well"(먹 바닥) · "dot"(먹 바닥 + 색 점). icon 은 Icons 이름
static func chip(text: String, col: Color, style := "soft", icon := "") -> PanelContainer:
	var bg := Color(col, 0.16)
	var bd := Color(col, 0.45)
	var fc := col.lightened(0.3)
	match style:
		"solid":
			bg = Color(col.darkened(0.15), 0.95)
			bd = Color(col.lightened(0.25), 0.9)
			fc = Color("#131A2B")
		"line":
			bg = Color(0, 0, 0, 0)
			bd = Color(col, 0.55)
		"well", "dot":
			bg = WELL
			bd = Color(0, 0, 0, 0)
			fc = TEXT
	var pc := PanelContainer.new()
	var sb := UI.flat(bg, bd, 1 if bd.a > 0 else 0, UI.R, 0)
	sb.content_margin_left = 7
	sb.content_margin_right = 7
	sb.content_margin_top = 2
	sb.content_margin_bottom = 2
	pc.add_theme_stylebox_override("panel", sb)
	pc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pc.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var h := UI.hbox(5)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if style == "dot":
		var d := ColorRect.new()
		d.color = col
		d.custom_minimum_size = Vector2(7, 7)
		d.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		d.mouse_filter = Control.MOUSE_FILTER_IGNORE
		h.add_child(d)
	elif icon != "":
		var iv := Icons.View.new(icon, fc, 11)
		iv.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(iv)
	var l := UI.lbl(text, FS_SUB, fc, style == "solid")
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(l)
	pc.add_child(h)
	return pc


## 섹션 머리 —— 금 마름모(또는 기호) · 제목 · 오른쪽으로 사라지는 금빛 선 · 오른쪽 작은 글
static func section(title: String, right := "", icon := "", col := GOLD) -> Control:
	var h := UI.hbox(7)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if icon != "":
		var iv := Icons.View.new(icon, col, 13)
		iv.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(iv)
	else:
		h.add_child(Diamond.new(col))
	var tl := UI.lbl(title, FS_ROW, LABEL, true)
	tl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(tl)
	h.add_child(Rule.new(col))
	if right != "":
		var rl := UI.lbl(right, FS_SUB, DIM)
		rl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		rl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(rl)
	return h


## 정보 행 —— [기호 배지 · 라벨] [값 (+ 덧말 tag) / 칩 줄] [오른쪽 머리 수치 + 그 이름] [›].
## opt: value_col · icon_col · tag(값 옆 옅은 글) · num · num_label · sub(수치가 없을 때 오른쪽 옅은 글) · chips(글 배열) · chip_col · tap(Callable)
static func info_row(icon: String, label: String, value: String, opt := {}) -> Control:
	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_left", 10)
	m.add_theme_constant_override("margin_right", 8)
	m.add_theme_constant_override("margin_top", 6)
	m.add_theme_constant_override("margin_bottom", 6)
	var tap: Callable = opt.get("tap", Callable())
	m.mouse_filter = Control.MOUSE_FILTER_STOP if tap.is_valid() else Control.MOUSE_FILTER_PASS
	var h := UI.hbox(GAP)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var lab := UI.hbox(6)
	lab.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lab.custom_minimum_size.x = LABEL_W
	lab.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	lab.add_child(icon_badge(icon, opt.get("icon_col", LABEL)))
	var kl := UI.lbl(label, FS_SUB, DIM)
	kl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	kl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lab.add_child(kl)
	h.add_child(lab)
	var vv := UI.vbox(5)
	vv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vv.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if value != "":
		var vr := UI.hbox(6)
		vr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var vl := UI.lbl(value, FS_VALUE, opt.get("value_col", TEXT), true)
		vl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if str(opt.get("tag", "")) == "":      # 줄임표를 켜면 최소 폭이 0 이 된다 —— 덧말이 없을 때만 (남은 폭을 다 가질 때)
			vl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
			vl.clip_text = true
			vl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		vr.add_child(vl)
		if str(opt.get("tag", "")) != "":
			var tg := UI.lbl(str(opt.tag), FS_TAG, DIM)
			tg.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			tg.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			tg.mouse_filter = Control.MOUSE_FILTER_IGNORE
			vr.add_child(tg)
		vv.add_child(vr)
	var chips: Array = opt.get("chips", [])
	if not chips.is_empty():
		var fl := UI.flow(5)
		fl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		for t in chips:
			fl.add_child(chip(str(t), opt.get("chip_col", LABEL), "soft"))
		vv.add_child(fl)
	h.add_child(vv)
	if str(opt.get("num", "")) != "":
		var nv := UI.vbox(-3)
		nv.mouse_filter = Control.MOUSE_FILTER_IGNORE
		nv.custom_minimum_size.x = NUM_W
		nv.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var nl := UI.lbl(str(opt.num), FS_VALUE, VAL, true)
		nl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		nl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		nv.add_child(nl)
		if str(opt.get("num_label", "")) != "":
			var ll := UI.lbl(str(opt.num_label), FS_TAG, DIM)
			ll.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			ll.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
			ll.clip_text = true
			ll.custom_minimum_size.x = NUM_W
			ll.mouse_filter = Control.MOUSE_FILTER_IGNORE
			nv.add_child(ll)
		h.add_child(nv)
	elif str(opt.get("sub", "")) != "":
		var sl := UI.lbl(str(opt.sub), FS_SUB, DIM)
		sl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		sl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		h.add_child(sl)
	if tap.is_valid():
		h.add_child(chevron())
		UI.tap(m, func():
			UI.buzz()
			tap.call())
	m.add_child(h)
	return m


## 정보 표 —— 행(Control 배열)을 한 장의 판에 담고 사이를 들여 쓴 가는 선으로 나눈다
static func info_table(rows: Array) -> Control:
	var p := Plate.new(GOLD, PLAIN, "", Vector4(0, 2, 0, 2))
	var v := UI.vbox(0)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for i in rows.size():
		if i > 0:
			var hm := MarginContainer.new()
			hm.add_theme_constant_override("margin_left", 10)
			hm.add_theme_constant_override("margin_right", 10)
			hm.mouse_filter = Control.MOUSE_FILTER_IGNORE
			hm.add_child(UI.hair())
			v.add_child(hm)
		v.add_child(rows[i])
	p.add_child(v)
	return p


## 기호 배지 —— 먹 바닥 작은 네모 안의 기호 (정보 행 · 상태 카드 왼쪽)
static func icon_badge(icon: String, col: Color, box := 22.0) -> Control:
	var pc := PanelContainer.new()
	pc.add_theme_stylebox_override("panel", UI.flat(WELL, Color(col, 0.28), 1, UI.R, 0))
	pc.custom_minimum_size = Vector2(box, box)
	pc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pc.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var iv := Icons.View.new(icon, col, roundf(box * 0.58))
	iv.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	iv.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	pc.add_child(iv)
	return pc


## 누를 수 있다는 표시 —— 오른쪽 끝 옅은 ›
static func chevron() -> Label:
	var l := UI.lbl("›", FS_ROW, Color(DIM, 0.55), true)
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## 알림 한 줄 —— 기호 + 감싸는 글 (조합하면 빠지는 것 같은 주의). bb 는 BBCode 가능
static func note(bb: String, col := WARN, icon := "seal") -> Control:
	var h := UI.hbox(6)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var iv := Icons.View.new(icon, Color(col, 0.9), 13)
	iv.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	var im := MarginContainer.new()
	im.add_theme_constant_override("margin_top", 2)
	im.mouse_filter = Control.MOUSE_FILTER_IGNORE
	im.add_child(iv)
	h.add_child(im)
	var r := UI.rich(bb, FS_SUB)
	r.add_theme_color_override("default_color", col)
	r.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UI.wrap_text(r)
	h.add_child(r)
	return h


# ───────── 능력치 ─────────

## 공격 · 방어 · 속도 세 칸 —— bonus 는 칸마다 덧붙일 글("+40", "" 이면 없음 · 전투의 버프). magic 이면 공격이 푸른색 (책략계)
static func stat_block(atk: float, def: float, spd: float, magic := false, bonus: Array = []) -> Control:
	var ac := ATK_INT if magic else ATK
	var items := [
		{"icon": "blade", "label": "공격", "value": str(int(atk)), "col": ac, "icon_col": ac},
		{"icon": "shield", "label": "방어", "value": str(int(def)), "col": TEXT, "icon_col": LABEL},
		{"icon": "boot", "label": "속도", "value": str(int(spd)), "col": TEXT, "icon_col": LABEL},
	]
	for i in mini(bonus.size(), items.size()):
		items[i]["bonus"] = str(bonus[i])
	return stat_cells(items)


## 능력치 칸 줄 (일반형) —— items: [{icon, label, value, col, icon_col?, bonus?, bonus_col?}]. 칸을 누르면 기호 자리에 이름이 1.5초 뜬다
static func stat_cells(items: Array) -> Control:
	var pc := PanelContainer.new()
	var sb := UI.flat(WELL, LINE, 1, UI.R, 0)
	sb.set_content_margin_all(1)
	pc.add_theme_stylebox_override("panel", sb)
	pc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pc.mouse_filter = Control.MOUSE_FILTER_PASS
	var h := UI.hbox(0)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for i in items.size():
		if i > 0:
			var hm := MarginContainer.new()
			hm.add_theme_constant_override("margin_top", 8)
			hm.add_theme_constant_override("margin_bottom", 8)
			hm.mouse_filter = Control.MOUSE_FILTER_IGNORE
			hm.add_child(UI.hair(true))
			h.add_child(hm)
		h.add_child(_stat_cell(items[i]))
	pc.add_child(h)
	return pc


static func _stat_cell(it: Dictionary) -> Control:
	var col: Color = it.get("col", TEXT)
	var icol: Color = it.get("icon_col", LABEL)
	var cell := MarginContainer.new()
	cell.add_theme_constant_override("margin_top", 5)
	cell.add_theme_constant_override("margin_bottom", 5)
	cell.add_theme_constant_override("margin_left", 2)
	cell.add_theme_constant_override("margin_right", 2)
	cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cell.mouse_filter = Control.MOUSE_FILTER_STOP
	cell.tooltip_text = str(it.get("label", ""))
	var hb := UI.hbox(4)
	hb.alignment = BoxContainer.ALIGNMENT_CENTER
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var iv := Icons.View.new(str(it.icon), icol, 20)
	iv.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hb.add_child(iv)
	var nl := UI.lbl(str(it.get("label", "")), FS_SUB, icol, true)
	nl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	nl.visible = false
	hb.add_child(nl)
	var vl := UI.lbl(str(it.value), FS_STAT, col, true)
	vl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	vl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.add_child(vl)
	if str(it.get("bonus", "")) != "":
		var bl := UI.lbl(str(it.bonus), FS_SUB, it.get("bonus_col", VAL), true)
		bl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		bl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hb.add_child(bl)
	cell.add_child(hb)
	UI.tap(cell, func():
		var gen := int(cell.get_meta("gen", 0)) + 1
		cell.set_meta("gen", gen)
		iv.visible = false
		nl.visible = true
		cell.get_tree().create_timer(1.5).timeout.connect(func():
			if is_instance_valid(cell) and int(cell.get_meta("gen", 0)) == gen:
				iv.visible = true
				nl.visible = false))
	return cell


# ───────── 진행 · 상태 ─────────

## 진행 막대 —— need 가 12 이하면 칸으로 나눈다 (모은 칸 col · 모자란 칸 옅게)
static func meter(got: int, need: int, col := VAL, h := 6.0) -> Control:
	return Meter.new(got, need, col, h)


## 진행 칸 —— 비활성 버튼 대신. [라벨 · 모음/전체 · 오른쪽 note] 아래 진행 막대. need ≤ 0 이면 막대 없이 글만 (막힘 사유)
static func need_block(label: String, got: int, need: int, note_text := "", col := WARN, height := 50.0) -> Control:
	var pc := PanelContainer.new()
	var sb := UI.flat(WELL, Color(col, 0.30), 1, UI.R, 0)
	sb.content_margin_left = 11
	sb.content_margin_right = 11
	sb.content_margin_top = 6
	sb.content_margin_bottom = 7
	pc.add_theme_stylebox_override("panel", sb)
	pc.custom_minimum_size.y = height
	pc.mouse_filter = Control.MOUSE_FILTER_PASS
	var v := UI.vbox(5)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	var hd := UI.hbox(6)
	hd.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ll := UI.lbl(label, FS_SUB if need > 0 else FS_ROW, DIM if need > 0 else col.lightened(0.1), need <= 0)
	ll.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if need <= 0:      # 막힘 사유 글은 길 수 있다 —— 줄임표 (켜면 최소 폭이 0 이라 진행 칸의 짧은 라벨에는 쓰지 않는다)
		ll.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		ll.clip_text = true
		ll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hd.add_child(ll)
	if need > 0:
		var nl := UI.lbl("%d / %d" % [got, need], FS_VALUE, TEXT, true)
		nl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		nl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hd.add_child(nl)
	if note_text != "":
		var tl := UI.lbl(note_text, FS_SUB, col, true)
		tl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		hd.add_child(tl)
	v.add_child(hd)
	if need > 0:
		v.add_child(Meter.new(got, need, VAL, 5.0, Color(col, 0.22)))
	pc.add_child(v)
	return pc


## 상태 → 색. ok · used(보유) 금 · open(지금 받을 수 있음) 밝은 금 · reroll 금 · wait(날짜를 기다림) 대나무 · gone · lock(이번 판엔 없음) 붉은 글
static func state_col(state: String) -> Color:
	match state:
		"ok", "used", "reroll":
			return GOLD
		"open":
			return GOLD_HI
		"wait":
			return LABEL
		"gone", "lock":
			return WARN
	return DIM


## 상태 카드 —— [그림 배지] [제목 / 한 줄] [알약] [›]. open 이면 주인공 판(그라데이션 · 빗금), 나머지는 왼쪽 색 띠 판.
## thumb: 배지 안에 넣을 그림(없으면 icon 기호). 경고 한 줄 대신 상태에 맞는 모양으로 (유니크 재료 · 신화 한 장 규칙 등)
static func status_card(thumb: Control, icon: String, title: String, line: String, state: String, pill := "", on_tap := Callable()) -> Control:
	var col := state_col(state)
	var dead: bool = state == "gone" or state == "lock"
	var card := Plate.new(col if not dead else Color(WARN, 0.75), HERO if state == "open" else ACCENT, "", Vector4(12, 8, 10, 8))
	var h := UI.hbox(10)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bx := PanelContainer.new()
	bx.add_theme_stylebox_override("panel", UI.flat(WELL, Color(col, 0.45 if not dead else 0.25), 1, UI.R, 0))
	bx.custom_minimum_size = Vector2(38, 38)
	bx.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bx.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if thumb != null:
		thumb.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		thumb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		thumb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if dead:
			thumb.modulate = Color(1, 1, 1, 0.45)
		bx.add_child(thumb)
	else:
		var iv := Icons.View.new(icon, col, 20)
		iv.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		iv.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		bx.add_child(iv)
	h.add_child(bx)
	var v := UI.vbox(1)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var tl := UI.lbl(title, FS_ROW, col.lightened(0.15) if not dead else WARN, true)
	tl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UI.wrap_text(tl)
	v.add_child(tl)
	if line != "":
		var ll := UI.lbl(line, FS_SUB, DIM)
		ll.mouse_filter = Control.MOUSE_FILTER_IGNORE
		UI.wrap_text(ll)
		v.add_child(ll)
	h.add_child(v)
	if pill != "":
		h.add_child(chip(pill, col, "solid" if state == "open" else "line"))
	if on_tap.is_valid():
		h.add_child(chevron())
		card.mouse_filter = Control.MOUSE_FILTER_STOP
		UI.tap(card, func():
			UI.buzz()
			on_tap.call())
	card.add_child(h)
	return card


# ───────── 버튼 · 탭 결 ─────────

## 주 행동 —— 금빛 그라데이션 판 + 옅은 빗금 + 윗선 광택 + 금 테 (화면에 하나). UI.btn 으로 만든 버튼에 입힌다
static func main_btn(b: Button) -> Button:
	var none := Color(0, 0, 0, 0)
	var vm := _vm(b)
	var n := _sb(none, Color(GOLD, 0.95), vm)
	var hv := _sb(Color(1, 1, 1, 0.05), GOLD_HI, vm)
	var pr := _sb(Color(0, 0, 0, 0.22), GOLD_HI, vm)
	var ds := _sb(none, Color(GOLD, 0.30), vm)
	UI.btn_styles(b, n, hv, pr, ds)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	for k in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(k, GOLD_INK)
	b.add_theme_color_override("font_disabled_color", Color(GOLD_INK, 0.4))
	b.add_theme_font_override("font", DB.font_bold)
	var g := Gloss.new(GOLD)
	b.add_child(g)
	return b


## 보조 행동 —— 먹 판 + 금 옅은 테 · 금 글자
static func sub_btn(b: Button) -> Button:
	var vm := _vm(b)
	UI.btn_styles(b, _sb(Color("#242E49"), Color(GOLD, 0.42), vm), _sb(Color("#33405F"), Color(GOLD, 0.7), vm), _sb(Color("#1B2338"), GOLD, vm))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	for k in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(k, GOLD_HI)
	return b


## 조용한 행동 —— 테만 (상세 · 해제 같은 곁 행동)
static func quiet_btn(b: Button) -> Button:
	var vm := _vm(b)
	var none := Color(0, 0, 0, 0)
	UI.btn_styles(b, _sb(none, Color(TEXT, 0.18), vm), _sb(Color(TEXT, 0.05), Color(TEXT, 0.3), vm), _sb(Color(TEXT, 0.1), Color(TEXT, 0.3), vm))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	for k in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(k, TEXT)
	return b


## 탭 단추 결 —— 평소 글자만, 고르면 금 밑줄 2 + 옅은 금 바닥. 탭 줄 바탕은 tab_track()
static func tab_btn(b: Button) -> Button:
	var none := Color(0, 0, 0, 0)
	var n := UI.flat(Color("#202c43"), Color("#536079"), 1, UI.R, 8)
	var hv := UI.flat(Color("#30405a"), Color("#8592a9"), 1, UI.R, 8)
	var on := UI.flat(Color("#51452f"), GOLD, 1, UI.R, 8)
	UI.btn_styles(b, n, hv, on)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.add_theme_color_override("font_color", TEXT)
	b.add_theme_color_override("font_hover_color", TEXT)
	b.add_theme_color_override("font_pressed_color", GOLD_HI)
	b.add_theme_color_override("font_hover_pressed_color", GOLD_HI)
	b.add_theme_font_override("font", DB.font_bold)
	return b


## 탭 줄 바탕 —— 아래 가는 선 하나 (상자 없음)
static func tab_track() -> StyleBoxFlat:
	var sb := UI.flat(Color(0, 0, 0, 0), LINE, 0, 0, 0)
	sb.border_width_bottom = 1
	return sb


static func _vm(b: Button) -> int:
	if b.has_theme_stylebox_override("normal"):
		return int(b.get_theme_stylebox("normal").content_margin_top)
	return 10


static func _sb(bg: Color, border: Color, vm: int) -> StyleBoxFlat:
	var sb := UI.flat(bg, border, 1, UI.R, 10)
	sb.content_margin_top = vm
	sb.content_margin_bottom = vm
	return sb


# ───────── 그리는 부품 ─────────

## 판 —— PLAIN(먹 바닥) · ACCENT(왼쪽 색 띠) · HERO(색 그라데이션 · 오른쪽 옅은 빗금 · 반쯤 잘린 큰 기호 · 색 테). 1.1j 고유기 카드와 같은 수치
class Plate extends PanelContainer:
	var col := Color.WHITE
	var mode := 0
	var icon := ""

	## pad = (왼, 위, 오른, 아래). x 가 음수면 모양 기본값 (띠가 있으면 왼 14 · 위 8 · 오른 12 · 아래 8, 주인공은 아래 9)
	func _init(c := Color("#D9A64B"), m := 0, ic := "", pad := Vector4(-1, -1, -1, -1)) -> void:
		col = c
		mode = m
		icon = ic
		var sb := StyleBoxEmpty.new()
		if pad.x < 0:
			pad = Vector4(14 if m != 0 else 12, 8, 12, 9 if m == 2 else 8)
		sb.content_margin_left = pad.x
		sb.content_margin_top = pad.y
		sb.content_margin_right = pad.z
		sb.content_margin_bottom = pad.w
		add_theme_stylebox_override("panel", sb)
		mouse_filter = Control.MOUSE_FILTER_PASS
		clip_contents = true

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		draw_style_box(UI.flat(Color(0.141, 0.180, 0.286, 0.70), Color(0, 0, 0, 0), 0, UI.R, 0), r)
		if mode == 2:
			var c0 := Color(col, 0.30)
			var c1 := Color(col, 0.03)
			draw_polygon(PackedVector2Array([Vector2(1, 1), Vector2(size.x - 1, 1), Vector2(size.x - 1, size.y - 1), Vector2(1, size.y - 1)]),
				PackedColorArray([c0, c1, c1, c0]))
			var x := size.x * 0.45      # 오른쪽 절반에 옅은 빗금
			while x < size.x + size.y:
				draw_line(Vector2(x, 0), Vector2(x - size.y, size.y), Color(col, 0.05), 1.0)
				x += 9.0
			if icon != "":
				Icons.draw(self, icon, Vector2(size.x - 34, size.y - 26), minf(size.y * 0.8, 92.0), Color(col, 0.06))      # 오른쪽 아래로 반쯤 잘린 큰 기호
			draw_style_box(UI.flat(Color(0, 0, 0, 0), Color(col, 0.5), 1, UI.R, 0), r)
		if mode != 0:
			draw_rect(Rect2(0, 0, 3, size.y), col if mode == 2 else Color(col, 0.85))


## 시트 머리 바탕 (head_wash)
class Wash extends Control:
	const RAD := 18.0      # 시트 위 모서리 (UI.R_SHEET)
	var col := Color.WHITE

	func _init(c: Color) -> void:
		col = c
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var w := size.x
		var h := size.y
		if w < RAD * 2 or h < RAD:
			return
		var pts := PackedVector2Array()
		pts.append(Vector2(0, h))
		for i in 7:
			var a := PI + (PI * 0.5) * i / 6.0
			pts.append(Vector2(RAD, RAD) + Vector2(cos(a), sin(a)) * RAD)
		for i in 7:
			var a := PI * 1.5 + (PI * 0.5) * i / 6.0
			pts.append(Vector2(w - RAD, RAD) + Vector2(cos(a), sin(a)) * RAD)
		pts.append(Vector2(w, h))
		var cols := PackedColorArray()
		var c0 := Color(col, 0.20)
		var c1 := Color(col, 0.0)
		for p in pts:
			var t := clampf(p.x / (w * 0.8), 0.0, 1.0)
			var tv := clampf(p.y / h, 0.0, 1.0)
			cols.append(c0.lerp(c1, t).lerp(Color(col, 0.0), tv * 0.35))
		draw_polygon(pts, cols)
		# 오른쪽 40% 옅은 빗금 (위 모서리 둥근 자리는 피한다)
		var x0 := w * 0.6
		var xs := x0
		var span := h - RAD
		while xs < w + span:
			var ta := maxf(0.0, xs - (w - 1.0))
			var tb := minf(span, xs - x0)
			if tb > ta:
				draw_line(Vector2(xs - ta, RAD + ta), Vector2(xs - tb, RAD + tb), Color(col, 0.06), 1.0)
			xs += 9.0
		# 아래 금빛 가는 선 —— 가운데 왼쪽이 가장 밝고 양 끝으로 사라진다
		var y := h - 0.5
		draw_polyline_colors(PackedVector2Array([Vector2(16, y), Vector2(w * 0.3, y), Vector2(w - 16, y)]),
			PackedColorArray([Color(0.851, 0.651, 0.294, 0.0), Color(0.851, 0.651, 0.294, 0.45), Color(0.851, 0.651, 0.294, 0.0)]), 1.0)


## 등급 리본 —— 색 그라데이션 띠 + 오른쪽 제비꼬리 + 왼쪽 밝은 선
class Ribbon extends Control:
	var text := ""
	var col := Color.WHITE

	func _init(t: String, c: Color) -> void:
		text = t
		col = c
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var tw := DB.font_bold.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
		custom_minimum_size = Vector2(ceilf(tw) + 24, 22)

	func _draw() -> void:
		var w := size.x
		var h := size.y
		var pts := PackedVector2Array([Vector2(0, 0), Vector2(w, 0), Vector2(w - 7, h * 0.5), Vector2(w, h), Vector2(0, h)])
		var a := Color(col.darkened(0.45), 0.95)
		var b := Color(col.darkened(0.72), 0.85)
		draw_polygon(pts, PackedColorArray([a, b, b, b, a]))
		draw_line(Vector2(2, 0.5), Vector2(w - 1, 0.5), Color(col.lightened(0.3), 0.55), 1.0)
		draw_rect(Rect2(0, 0, 2, h), col.lightened(0.15))
		draw_string(DB.font_bold, Vector2(8, h * 0.5 + 12 * 0.36), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, col.lightened(0.35))


## 섹션 머리의 금 마름모
class Diamond extends Control:
	var col := Color.WHITE

	func _init(c: Color) -> void:
		col = c
		custom_minimum_size = Vector2(9, 9)
		size_flags_vertical = Control.SIZE_SHRINK_CENTER
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var c := size * 0.5
		draw_colored_polygon(PackedVector2Array([c + Vector2(0, -4), c + Vector2(4, 0), c + Vector2(0, 4), c + Vector2(-4, 0)]), col)


## 섹션 머리의 사라지는 금빛 선
class Rule extends Control:
	var col := Color.WHITE

	func _init(c: Color) -> void:
		col = c
		size_flags_horizontal = Control.SIZE_EXPAND_FILL
		size_flags_vertical = Control.SIZE_SHRINK_CENTER
		custom_minimum_size = Vector2(12, 3)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var y := size.y * 0.5
		draw_polyline_colors(PackedVector2Array([Vector2(0, y), Vector2(size.x, y)]), PackedColorArray([Color(col, 0.4), Color(col, 0.0)]), 1.0)


## 진행 막대 (meter · need_block)
class Meter extends Control:
	var got := 0
	var need := 1
	var col := Color.WHITE
	var track := Color(1, 1, 1, 0.08)

	func _init(g: int, n: int, c: Color, h := 6.0, tr := Color(1, 1, 1, 0.08)) -> void:
		got = g
		need = n
		col = c
		track = tr
		custom_minimum_size = Vector2(0, h)
		size_flags_horizontal = Control.SIZE_EXPAND_FILL
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var n := maxi(need, 1)
		var g := clampi(got, 0, n)
		if n <= 12:
			var gap := 3.0
			var sw := (size.x - gap * (n - 1)) / n
			for i in n:
				var r := Rect2(i * (sw + gap), 0, sw, size.y)
				draw_style_box(UI.flat(col if i < g else track, Color(0, 0, 0, 0), 0, 2, 0), r)
		else:
			draw_style_box(UI.flat(track, Color(0, 0, 0, 0), 0, 2, 0), Rect2(Vector2.ZERO, size))
			if g > 0:
				draw_style_box(UI.flat(col, Color(0, 0, 0, 0), 0, 2, 0), Rect2(0, 0, size.x * g / float(n), size.y))


## 주 행동 버튼 뒤의 금빛 판 (main_btn) —— 부모(버튼)보다 먼저 그린다
class Gloss extends Control:
	var col := Color.WHITE

	func _init(c: Color) -> void:
		col = c
		show_behind_parent = true
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	func _draw() -> void:
		var w := size.x
		var h := size.y
		var top := Color(col, 0.50)
		var bot := Color(col.darkened(0.35), 0.30)
		draw_polygon(PackedVector2Array([Vector2(1, 1), Vector2(w - 1, 1), Vector2(w - 1, h - 1), Vector2(1, h - 1)]), PackedColorArray([top, top, bot, bot]))
		var x0 := w * 0.55      # 오른쪽 절반에 옅은 빗금 —— (xs, 0) 에서 왼쪽 아래로, 판 안에서만
		var xs := x0
		while xs < w + h:
			var ta := maxf(0.0, xs - (w - 1.0))
			var tb := minf(h, xs - x0)
			if tb > ta:
				draw_line(Vector2(xs - ta, ta), Vector2(xs - tb, tb), Color(1, 0.95, 0.8, 0.07), 1.0)
			xs += 8.0
		draw_line(Vector2(3, 1.5), Vector2(w - 3, 1.5), Color(1, 0.93, 0.75, 0.35), 1.0)
