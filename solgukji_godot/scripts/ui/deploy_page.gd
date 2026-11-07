class_name DeployPage
extends RefCounted
## 편성 —— 진형 고르기 · 9칸 편성판 · 손패. 원본 rDeploy · openSlot · openItem.
## 세로 화면: 위에 진형 띠와 편성판을 고정하고, 아래 [손패 | 진형 | 보급품] 만 스크롤한다.
## 놓는 법 셋: ① 손패 카드를 길게 눌러 칸으로 끈다 ② 손패 카드를 눌러 고르고 칸을 누른다
## ③ 칸을 눌러 목록에서 고른다. 칸을 길게 눌러 다른 칸으로 끌면 자리를 바꾸고, 아래 목록으로 끌면 내린다.

var gs: GameScreen
var sel := ""                 # 손패에서 고른 카드 (칸을 누르면 그 자리에 놓는다)
var seg := ""                 # 아래 나눔 탭 —— hand · syn · item. "" = 닫힘 (11/5 사용자: 기본 닫힌 채, 누르면 열림)
const LOWER_H := 168.0
var _slide_up := false        # 방금 열었다 —— 올라오는 연출
var _form_scroll := 0         # 진형 띠 가로 스크롤 —— 진형을 골라 다시 그려도 그 자리에 (11/6 사용자)        # 열린 아래 칸 높이 (11/5 사용자: 예전 남는 공간 전부 → 절반쯤)


func build() -> Control:
	var run: Run = gs.run
	var v := UI.vbox(10)
	var f: Dictionary = DB.FORM[run.form]

	# 진형 —— 가로로 넘기는 띠. 11/7 사용자: 이름만 (미니 격자를 붙이니 칩 폭이 모자라 레이아웃이 무너졌다). 효과 줄은 아래 편성판 머리에 한 줄
	var st := UI.strip(6)
	for key in DB.FORM:
		var fm: Dictionary = DB.FORM[key]
		if fm.get("foe", false):      # 토벌 적 전용 대군 진형
			continue
		var on: bool = key == run.form
		var b := Button.new()
		b.text = fm.n
		b.custom_minimum_size = Vector2(76, 40)
		b.add_theme_font_override("font", DB.font_display)
		b.add_theme_font_size_override("font_size", 14)
		for cn in ["font_color", "font_hover_color", "font_focus_color"]:
			b.add_theme_color_override(cn, DB.PAL.gold if on else DB.PAL.paper)
		b.add_theme_color_override("font_pressed_color", DB.PAL.gold)
		b.add_theme_stylebox_override("normal", UI.flat(DB.PAL.ink3 if on else DB.PAL.ink2, DB.PAL.gold if on else DB.PAL.ink4, 2 if on else 1, 10, 8))
		b.add_theme_stylebox_override("hover", UI.flat(DB.PAL.ink3, DB.PAL.gold if on else DB.PAL.bamboo_dim, 2 if on else 1, 10, 8))
		b.add_theme_stylebox_override("pressed", UI.flat(DB.PAL.ink4, DB.PAL.gold, 2, 10, 8))
		b.pressed.connect(func():
			UI.buzz()
			gs.act("set_form", [key]))
		st[1].add_child(b)
	v.add_child(st[0])
	var sc0: ScrollContainer = st[0]
	sc0.get_h_scroll_bar().value_changed.connect(func(x): _form_scroll = int(x))
	(func():
		if is_instance_valid(sc0):
			sc0.scroll_horizontal = _form_scroll).call_deferred()

	# 11/5 사용자: 작전(군령) 고르기 삭제. 진형 우대 띠도 삭제 (우대 칸 옥빛 강조만 남김)

	# 편성판 —— 화면 위쪽에 고정 (손패에서 길게 눌러 끌어 올 수 있게)
	var syn := Battle.fac_syn(run.board, run.form)
	var bp := UI.vbox(6)
	var hd := UI.hbox(6)
	var hl := UI.vbox(0)
	hl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# 11/5 사용자: '어린진 · 9/9칸' 대신 '어린진 / 진형 우대 효과'
	var bn0 = DB.D.FORMBOON.get(run.form)
	var eff_txt := ("%s %s +%d%%" % [" · ".join(bn0.tags), DB.D.STATNM.get(bn0.stat, "스킬 발동"), roundi(float(bn0.v) * 100)]) if bn0 else ""
	# 11/5 사용자 2차: '방원진' / '효과 (설명)' 두 줄
	# 11/5 사용자 3차: 세 줄 —— 진형 이름 / 효과 / 설명(옛 이야기를 들려주는 듯한 명조 기울임)
	hl.add_child(UI.lbl(f.n, 17, DB.PAL.paper, true))
	# 11/7 UI 정리: 효과 · 설명 줄은 줄바꿈 —— 한 줄로 두면 최소 폭이 커져 9:20 휴대폰(논리 폭 400)에서 편성판이 오른쪽으로 넘쳐 '해제' · 우익 칸이 잘렸다
	var effl := UI.lbl(eff_txt, 12, Color("#E8C25A"), true)
	effl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hl.add_child(effl)
	if bn0:
		var lore := UI.lbl("「%s」" % bn0.d, 12, Color("#C6AC7C"))
		lore.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		lore.add_theme_font_override("font", _lore_font())
		hl.add_child(lore)
	hd.add_child(hl)
	var ab := UI.btn("자동 편성", func():
		sel = ""
		gs.act("auto_deploy"), "pri", 40)
	ab.add_theme_font_size_override("font_size", 14)
	hd.add_child(ab)
	var cb := UI.btn("해제", func(): gs.act("clear_board"), "ghost", 40)
	cb.add_theme_font_size_override("font_size", 14)
	hd.add_child(cb)
	bp.add_child(hd)
	var grid := GridContainer.new()
	grid.columns = 1 + DB.FORM_COLS      # 11/6 진형 4행 5열
	grid.add_theme_constant_override("h_separation", 5)
	grid.add_theme_constant_override("v_separation", 5)
	var face := UI.lbl("▲적", 11, DB.PAL.seal)
	face.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	grid.add_child(face)
	for col in ["좌익", "좌", "중앙", "우", "우익"]:
		var cl := UI.lbl(col, 11, DB.PAL.bamboo_dim)
		cl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(cl)
	for ri in f.grid.size():
		var ll := UI.lbl(DB.D.LINES[ri], 12, DB.PAL.bamboo, true)
		ll.custom_minimum_size = Vector2(28, 0)
		ll.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
		ll.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		ll.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		ll.size_flags_vertical = Control.SIZE_FILL
		grid.add_child(ll)
		for si in f.grid[ri]:
			var box := SlotBox.new()
			box.page = self
			box.slot = si
			box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			box.size_flags_vertical = Control.SIZE_EXPAND_FILL
			grid.add_child(box)
	grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	bp.add_child(grid)
	var bpp := UI.panel(bp, 8)
	bpp.size_flags_vertical = Control.SIZE_EXPAND_FILL      # 11/5 사용자: 아래 탭을 닫아 생긴 공간만큼 칸을 크게
	bp.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(bpp)

	# 아래 —— [보유 | 보급품] 나눔 탭, 그 안만 스크롤. 칸을 여기로 끌면 내린다
	var keys := Run.sort_cards(run.inv.keys())
	var n_items := 0
	for id in run.bag:
		n_items += run.bag[id]
	# 11/5 사용자: 기본 닫힌 채 —— 탭을 누르면 열리고, 열린 탭을 다시 누르면 닫힌다. 열려도 높이는 LOWER_H (예전의 절반쯤)
	var hand := HandDrop.new()
	hand.page = self
	hand.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	var hv := UI.vbox(6)
	hand.add_child(hv)
	# 11/5 사용자: '손패' → '보유', 진형 탭 버튼 제거 (진형 설명은 위 편성판 머리에 있다)
	var tabs := UI.segmented([["hand", "보유 %d" % keys.size()], ["item", "보급품 %d" % n_items]], seg, func(k):
		var was := seg
		seg = "" if seg == k else k
		_slide_up = was == "" and seg != ""
		gs.render())
	v.add_child(hand)
	if seg == "":
		hv.add_child(tabs)      # 닫힘 —— 탭만 맨 아래에
		return v
	var sc := UI.scroll()
	sc.custom_minimum_size.y = LOWER_H
	hv.add_child(sc)
	hv.add_child(tabs)          # 열림 —— 탭은 그대로 맨 아래, 내용이 그 위로 올라온다
	if _slide_up:
		_slide_up = false
		sc.custom_minimum_size.y = 0
		sc.create_tween().tween_property(sc, "custom_minimum_size:y", LOWER_H, 0.18).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	var lower := UI.vbox(6)
	lower.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(lower)
	match seg:
		"hand": _hand(lower, keys)
		"syn": _syn(lower, syn)
		"item": _items(lower)
	var pad := Control.new()
	pad.custom_minimum_size = Vector2(0, 12)
	lower.add_child(pad)
	return v


func _hand(hv: VBoxContainer, keys: Array) -> void:
	var run: Run = gs.run
	if sel != "":
		var sh := UI.hbox(8)
		var sl := UI.rich("[color=#D9A64B][b]%s[/b] 을(를) 골랐다 — 놓을 칸을 누른다[/color]" % DB.C[sel].name, 14)
		sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		sh.add_child(sl)
		sh.add_child(UI.btn("취소", func():
			sel = ""
			gs.render(), "ghost", 40))
		hv.add_child(sh)

	# 11/5 사용자: 손패는 목록으로, 높은 등급부터 (Run.sort_cards). 줄을 누르면 고르고, 고른 줄을 다시 누르면 상세. 길게 눌러 칸으로 끈다
	var bn = DB.D.FORMBOON.get(run.form)
	for k in keys:
		var row := HandRow.new()
		row.page = self
		row.k = k
		row.qty = run.inv[k]
		row.boon = bn != null and bn.tags.has(DB.C[k].tag)
		row.on = k == sel
		hv.add_child(row)
	if keys.is_empty():
		hv.add_child(UI.hint("보유한 카드가 없다 — 모두 편성했다."))


## 진형 설명 글꼴 —— 나눔명조를 기울인다 (기울임 글꼴 파일이 없어 FontVariation 의 기울기로)
static var _lore: FontVariation = null
static func _lore_font() -> Font:
	if _lore == null:
		_lore = FontVariation.new()
		_lore.base_font = DB.font_display
		_lore.variation_transform = Transform2D(Vector2(1, 0), Vector2(0.22, 1), Vector2.ZERO)
	return _lore


func hand_tap(k: String) -> void:
	if sel == k:
		gs.card_info(k)
	else:
		sel = k
		gs.render()


## 진형 탭 —— 진형 우대(이 진형에서 힘을 받는 병종)와 선호 · 어색 칸 설명. 세력 · 병종 시너지는 10/30 에 없앴다
func _syn(v: VBoxContainer, _syn_unused: Dictionary) -> void:
	var run: Run = gs.run
	var f: Dictionary = DB.FORM[run.form]
	var tcnt := {}
	for k in run.board:
		if k != null:
			tcnt[DB.C[k].tag] = tcnt.get(DB.C[k].tag, 0) + 1
	var bn = DB.D.FORMBOON.get(run.form)
	var bn_n := 0
	if bn:
		for t in bn.tags:
			bn_n += tcnt.get(t, 0)
	var boon := UI.rich("[b][color=#C6AC7C]%s[/color][/b] — %s\n%s에게 %s +%d%%  [color=%s]현재 %d명 해당[/color]" % [
		f.n, bn.d if bn else "", " · ".join(bn.tags) if bn else "", DB.D.STATNM.get(bn.stat, "스킬 발동률") if bn else "",
		roundi(bn.v * 100) if bn else 0, "#8fd4c2" if bn_n else "#e0806f", bn_n], 14)
	v.add_child(UI.sect("진형 우대", UI.panel(boon)))
	v.add_child(UI.rich("[color=#8fd4c2]■[/color] 선호  [color=#e0806f]■[/color] 어색", 13))


## 11/5 사용자: 보급품은 등급별로 나열, 높은 등급일수록 크게 (징집창처럼) —— 유니크 한 줄에 하나(효과 전부, 줄바꿈), 레어 둘, 매직 · 일반 셋
func _items(v: VBoxContainer) -> void:
	var run: Run = gs.run
	var bk := run.bag_keys()
	if bk.is_empty():
		v.add_child(UI.hint("보급품이 없다. 페이즈가 넘어가면 하나씩 지급된다."))
		return
	var cols := {"유니크": 1, "레어": 2, "매직": 3, "일반": 3}
	for g in ["유니크", "레어", "매직", "일반"]:
		var ids: Array = bk.filter(func(x): return DB.IT[x].grade == g)
		if ids.is_empty():
			continue
		var n := 0
		for id in ids:
			n += run.bag[id]
		v.add_child(UI.lbl("%s %d" % [g, n], 12, Color(DB.D.IGRADE[g]).lightened(0.2), true))
		var gr := GridContainer.new()
		gr.columns = cols[g]
		gr.add_theme_constant_override("h_separation", 6)
		gr.add_theme_constant_override("v_separation", 6)
		for id in ids:
			gr.add_child(_item_card(id, run.bag[id], g))
		v.add_child(gr)


func _item_card(id: String, n: int, g: String) -> Control:
	var it: Dictionary = DB.IT[id]
	var col := UI.item_col(id)
	var big := g == "유니크"
	var mid := g == "레어"
	var b := PanelContainer.new()
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.add_theme_stylebox_override("panel", UI.flat(DB.PAL.ink2, col, 2 if big else 1, 8, 6))
	b.mouse_filter = Control.MOUSE_FILTER_STOP
	b.gui_input.connect(func(e):
		if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT and not e.pressed:
			UI.buzz()
			gs._item_sheet(id))      # 누르면 아이템 시트 (유니크는 들어가는 신화 장수)
	var h := UI.hbox(8)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ts := 56 if big else (36 if mid else 26)
	var th := ItemArt.View.new(id, ts)
	th.custom_minimum_size = Vector2(ts, ts)
	th.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	th.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(th)
	var tv := UI.vbox(1)
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tv.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	tv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var nl := UI.lbl("%s%s" % [it.name, ("  ×%d" % n) if n > 1 else ""], 16 if big else (13 if mid else 12), col.lightened(0.2), true)
	nl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	nl.clip_text = true
	tv.add_child(nl)
	var et := UI.item_text(id)
	if big:
		et += "  · 신화 조합 재료" if it.use == "myth" else ""
		for k in DB.by_tier(8).filter(func(x): return Run.need_item(x) == id):
			et += "\n→ %s" % DB.C[k].name
	else:
		et = et.replace(" · ", "\n")
	var el := UI.lbl(et, 13 if big else 11, DB.PAL.bamboo)
	el.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART     # 효과를 자르지 않는다
	tv.add_child(el)
	for c in tv.get_children():
		c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(tv)
	b.add_child(h)
	return b



## 칸 누름 —— 고른 카드가 있으면 놓고, 없으면 칸 시트
func tap_slot(i: int) -> void:
	if not gs.can_act():
		gs.toast("지금은 편성할 수 없다 — 다음 준비 시간에", "bad")
		return
	if sel != "" and gs.run.inv.get(sel, 0) > 0:
		var k := sel
		if gs.run.inv.get(k, 0) <= 1:
			sel = ""
		gs.act("place", [i, k])
		return
	slot_sheet(i)


func drop(i: int, data: Dictionary) -> void:
	if not gs.can_act():
		return
	if data.from < 0:
		if sel == data.card and gs.run.inv.get(sel, 0) <= 1:
			sel = ""
		gs.act("place", [i, data.card])
	elif data.from != i:
		gs.act("swap", [data.from, i])


func drop_hand(data: Dictionary) -> void:
	if data.from >= 0:
		gs.act("unplace", [data.from])


func slot_sheet(i: int) -> void:
	# 11/4 사용자: 편성 페이지처럼 정리 —— 제목 '좌 · 전군 배치', 칸 능력 한 줄, 선호 · 어색은 병종 칩, 설명 글 · 기술 글 뺌, 손패는 6칸 작은 격자
	var run: Run = gs.run
	var s: Dictionary = DB.FORM[run.form].slots[i]
	var line: String = s.line
	var ln: Dictionary = DB.D.LINE[line]
	var cur = run.board[i]
	var side: String = ["좌익", "좌", "중앙", "우", "우익"][clampi(int(s.col), 0, 4)]
	var b := gs.open_sheet("%s · %s 배치" % [side, line])
	b.add_child(UI.rich("[color=#8D7B5C]공격[/color] %d%% (책략계 %d%%)   [color=#8D7B5C]방어[/color] %d%%   [color=#8D7B5C]피격[/color] %d순위" % [
		roundi(ln.atk * 100), roundi(ln["int"] * 100), roundi(ln["def"] * 100), ln.pri], 13))
	var zr := UI.flow(5)
	for t in DB.D.TAGORDER:
		var z := DB.aff_of(t, line, s.side)
		if z == "":
			continue
		var col := DB.PAL.jade if z == "pref" else DB.PAL.seal
		var chip := UI.lbl(("▲ " if z == "pref" else "▼ ") + t, 12, col.lightened(0.25), true)
		var pc := PanelContainer.new()
		pc.add_theme_stylebox_override("panel", UI.flat(Color(col, 0.18), col, 1, 10, 4))
		pc.add_child(chip)
		zr.add_child(pc)
	b.add_child(zr)
	if cur != null:
		var cv := UI.vbox(8)
		cv.add_child(gs.tile(cur))
		var inn = Run.innate_item(cur)
		var it = run.item_of_slot(i)
		var iv := UI.hbox(8)
		if inn != null:
			iv.add_child(UI.hint("🔒 %s 내장" % DB.IT[inn].name))
		else:
			var ib := UI.btn("아이템: %s" % DB.IT[it].name if it != null else "아이템 장착", func(): item_sheet(i), "", 42)
			ib.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			iv.add_child(ib)
		var ub := UI.btn("내리기", func():
			gs.close_sheet()
			gs.act("unplace", [i]), "ghost", 42)
		ub.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		iv.add_child(ub)
		cv.add_child(iv)
		b.add_child(UI.panel(cv, 8))
	var keys := Run.sort_cards(run.inv.keys())
	if keys.is_empty():
		return
	b.add_child(UI.eyebrow("손패"))
	var f := UI.grid(56, 5)
	f.max_cols = 6
	for k in keys:
		var t := gs.mtile(k, run.inv[k], func(id):
			gs.close_sheet()
			gs.act("place", [i, id]))
		t.custom_minimum_size = Vector2(56, 84)
		var z := DB.aff_of(DB.C[k].tag, line, s.side)
		if z != "":
			t.badge = "▲" if z == "pref" else "▼"
			t.badge_col = Color(DB.PAL.jade, 0.95) if z == "pref" else Color(DB.PAL.seal, 0.95)
		f.add_child(t)
	b.add_child(f)


func item_sheet(i: int) -> void:
	var run: Run = gs.run
	var k: String = run.board[i]
	var used := {}
	for j in 9:
		if j != i and run.equip[j] != null:
			used[run.equip[j]] = used.get(run.equip[j], 0) + 1
	var cand: Array = run.bag.keys().filter(func(id): return run.can_equip(k, id) and run.bag[id] - used.get(id, 0) > 0)
	var b := gs.open_sheet("%s 아이템" % DB.C[k].name)
	b.add_child(UI.hint("%s 전용 아이템만 장착할 수 있다 · 슬롯 1칸" % DB.C[k].tag))
	if run.equip[i] != null:
		b.add_child(UI.btn("해제", func():
			gs.close_sheet()
			gs.act("set_equip", [i, null]), "ghost"))
	if cand.is_empty():
		b.add_child(UI.hint("장착할 수 있는 %s 아이템이 없다." % DB.C[k].tag))
		return
	var f := UI.grid(170, 8)
	for id in cand:
		f.add_child(gs.item_box(id, run.bag[id] - used.get(id, 0), func():
			gs.close_sheet()
			gs.act("set_equip", [i, id])))
	b.add_child(f)


## 편성판 한 칸 —— 누르면 칸 시트(또는 고른 카드를 놓는다), 길게 누르면 끌어서 옮기기·내리기
class SlotBox extends Control:
	const SZ := Vector2(60, 84)      # 11/6 진형 5열 —— 좁고 높게 (초상 위 · 글 아래). 11/7 66 → 60: 줄 이름 28 + 칸 5개 + 간격 · 여백이 논리 폭 400 을 넘어 9:20 휴대폰에서 편성판이 오른쪽으로 넘쳤다 (넓으면 칸은 늘어난다)
	var page: DeployPage
	var slot := -1
	var _press := Vector2.INF
	var _held := 0.0
	var _dragging := false

	func _ready() -> void:
		custom_minimum_size = SZ
		mouse_filter = Control.MOUSE_FILTER_STOP if slot >= 0 else Control.MOUSE_FILTER_IGNORE

	func _gui_input(e: InputEvent) -> void:
		if slot < 0:
			return
		if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
			if e.pressed:
				_press = e.position
				_held = 0.0
				_dragging = false
			else:
				if _press != Vector2.INF and not _dragging and e.position.distance_to(_press) < 14:
					UI.buzz()
					page.tap_slot(slot)
				_press = Vector2.INF
		elif e is InputEventMouseMotion and _press != Vector2.INF and e.position.distance_to(_press) >= 14:
			_press = Vector2.INF        # 길게 누르기 전에 움직였다 —— 탭도 끌기도 아니다

	func _process(dt: float) -> void:
		if _press == Vector2.INF or _dragging:
			return
		_held += dt
		if _held >= CardTile.HOLD:
			_start_drag()

	func _start_drag() -> void:
		var k = page.gs.run.board[slot]
		_press = Vector2.INF
		if k == null:
			return
		_dragging = true
		UI.buzz(15)
		var pv := CardTile.new().setup(k)
		pv.modulate = Color(1, 1, 1, 0.85)
		var holder := Control.new()
		holder.add_child(pv)
		pv.position = -CardTile.SIZE / 2
		force_drag({"card": k, "from": slot}, holder)

	func _can_drop_data(_p: Vector2, data) -> bool:
		return slot >= 0 and data is Dictionary and data.has("card")

	func _drop_data(_p: Vector2, data) -> void:
		page.drop(slot, data)

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		if slot < 0:
			draw_rect(r.grow(-6), Color(DB.PAL.ink2, 0.25))
			return
		var run: Run = page.gs.run
		var s: Dictionary = DB.FORM[run.form].slots[slot]
		var k = run.board[slot]
		var border: Color = DB.PAL.ink4
		var bg: Color = DB.PAL.ink2
		var z := ""
		if k != null:
			z = DB.aff_of(DB.C[k].tag, s.line, s.side)
			border = DB.PAL.jade if z == "pref" else (DB.PAL.seal if z == "bad" else DB.tier_color(k).darkened(0.2))
			bg = DB.PAL.ink3
		elif page.sel != "":
			var z2 := DB.aff_of(DB.C[page.sel].tag, s.line, s.side)
			border = DB.PAL.jade if z2 == "pref" else (DB.PAL.seal if z2 == "bad" else DB.PAL.gold)
		# 11/5 사용자: 진형 우대(FORMBOON —— 어린진이면 창병 · 유생 방어 +14%) 받는 장수를 눈에 띄게. 자리 선호(선봉 · 중군)와는 다르다
		var bn = DB.D.FORMBOON.get(run.form)
		var boon: bool = k != null and bn != null and bn.tags.has(DB.C[k].tag)
		if boon:
			bg = DB.PAL.ink3.lerp(DB.PAL.gold, 0.16)
			border = DB.PAL.gold
		var sb := UI.flat(bg, border, 3 if boon else 2, 8, 0)
		if boon:
			sb.shadow_color = Color(DB.PAL.gold, 0.55)
			sb.shadow_size = 6
		if s.line == "선봉":
			sb.border_width_top = 4
		draw_style_box(sb, r)
		var fb := DB.font_body
		if k == null:
			draw_string(DB.font_display, Vector2(0, size.y * 0.5 + 6), "＋", HORIZONTAL_ALIGNMENT_CENTER, size.x, 24, Color(DB.PAL.bamboo_dim, 0.7))
			draw_string(fb, Vector2(0, size.y - 7), UI.pos_name(s.line, s.col), HORIZONTAL_ALIGNMENT_CENTER, size.x, 11, DB.PAL.bamboo_dim)
			return
		var c: Dictionary = DB.C[k]
		if size.x < 120:      # 11/6 5열 —— 좁은 칸: 초상 / 이름 / 병종 · 병력 / 아이템 / 진형 버프
			_draw_narrow(k, c, z, boon, bn, run)
			return
		# 11/5 사용자: 칸을 크게 —— [초상] 이름 / 병종 / 병력, 그 아래 아이템(가운데), 맨 아래 진형 버프 설명
		var bot := 15.0 if boon else 0.0           # 진형 버프 줄
		var ith := 15.0                             # 아이템 줄
		var ph := size.y - 10 - ith - bot
		var pr := Rect2(5, 5, minf(ph * 0.75, size.x * 0.42), ph)
		Art.draw_portrait(self, pr, k)
		var x := pr.end.x + 6
		var tw := size.x - x - 4
		var nm: String = DB.person(k) if c.tier > 2 else c.name
		var fs := 16 if size.y >= 96 else 14
		var tf := DB.tier_font(c.tier)
		while fs > 10 and tf.get_string_size(nm, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > tw:
			fs -= 1
		var ty := pr.position.y + minf(ph * 0.3, 22.0)
		var gap := clampf(ph * 0.26, 13.0, 20.0)
		draw_string(tf, Vector2(x, ty), nm, HORIZONTAL_ALIGNMENT_LEFT, tw, fs, DB.tier_color(k).lightened(0.2))
		draw_string(fb, Vector2(x, ty + gap), c.tag, HORIZONTAL_ALIGNMENT_LEFT, tw, 12, DB.PAL.jade if z == "pref" else (DB.PAL.seal if z == "bad" else DB.PAL.bamboo))
		draw_string(fb, Vector2(x, ty + gap * 2), Battle.num(c.tr) + "명", HORIZONTAL_ALIGNMENT_LEFT, tw, 12, DB.PAL.bamboo_dim)
		var it = run.item_of_slot(slot)
		var itxt: String = "빈 슬롯" if it == null else DB.IT[it].name + (" 🔒" if Run.innate_item(k) != null else "")
		draw_string(fb, Vector2(4, size.y - 6 - bot), itxt, HORIZONTAL_ALIGNMENT_CENTER, size.x - 8, 11, UI.item_col(it) if it != null else Color(DB.PAL.bamboo_dim, 0.6))
		if boon:      # 맨 아래 진형 버프 —— 금빛 띠 (이름을 가리지 않는다)
			var rr := Rect2(3, size.y - bot - 2, size.x - 6, bot - 1)
			draw_style_box(UI.flat(Color(DB.PAL.gold, 0.9), DB.PAL.gold, 0, 5, 0), rr)
			var txt := "%s %s +%d%%" % [DB.FORM[run.form].n, DB.D.STATNM.get(bn.stat, "스킬 발동"), roundi(float(bn.v) * 100)]
			draw_string(DB.font_bold, rr.position + Vector2(0, 11), txt, HORIZONTAL_ALIGNMENT_CENTER, rr.size.x, 10, Color("#1A1508"))


	func _draw_narrow(k: String, c: Dictionary, z: String, boon: bool, bn, run: Run) -> void:
		var fb := DB.font_body
		var bot := 13.0 if boon else 0.0
		var ith := 12.0
		var txt_h := 25.0
		var ph := maxf(16.0, size.y - 8 - ith - bot - txt_h)
		var pw := minf(size.x - 8, ph * 1.05)
		var pr := Rect2((size.x - pw) / 2, 4, pw, ph)
		Art.draw_portrait(self, pr, k)
		var nm: String = DB.person(k) if c.tier > 2 else c.name
		var tf := DB.tier_font(c.tier)
		var fs := 13
		while fs > 9 and tf.get_string_size(nm, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > size.x - 6:
			fs -= 1
		var y := pr.end.y + 12
		draw_string(tf, Vector2(3, y), nm, HORIZONTAL_ALIGNMENT_CENTER, size.x - 6, fs, DB.tier_color(k).lightened(0.2))
		var info := "%s %s" % [c.tag, Battle.num(c.tr)]
		draw_string(fb, Vector2(2, y + 12), info, HORIZONTAL_ALIGNMENT_CENTER, size.x - 4, 10, DB.PAL.jade if z == "pref" else (DB.PAL.seal if z == "bad" else DB.PAL.bamboo_dim))
		var it = run.item_of_slot(slot)
		var itxt: String = "빈 슬롯" if it == null else DB.IT[it].name
		draw_string(fb, Vector2(2, size.y - 5 - bot), itxt, HORIZONTAL_ALIGNMENT_CENTER, size.x - 4, 9, UI.item_col(it) if it != null else Color(DB.PAL.bamboo_dim, 0.6))
		if boon:
			var rr := Rect2(2, size.y - bot - 2, size.x - 4, bot)
			draw_style_box(UI.flat(Color(DB.PAL.gold, 0.9), DB.PAL.gold, 0, 4, 0), rr)
			var bt := "%s +%d%%" % [DB.D.STATNM.get(bn.stat, "발동"), roundi(float(bn.v) * 100)]
			draw_string(DB.font_bold, rr.position + Vector2(0, 10), bt, HORIZONTAL_ALIGNMENT_CENTER, rr.size.x, 9, Color("#1A1508"))


## 손패 한 줄 (11/5) —— [초상] 이름(등급색) / 병종 · 등급 · 병력, 진형 우대면 금빛 칩, ×수. 누르면 page.hand_tap, 길게 눌러 끈다
class HandRow extends PanelContainer:
	var page: DeployPage
	var k := ""
	var qty := 1
	var boon := false
	var on := false
	var _press := Vector2.INF
	var _held := 0.0
	var _dragging := false

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		custom_minimum_size.y = 50
		var tc := DB.tier_color(k)
		add_theme_stylebox_override("panel", UI.flat(DB.PAL.ink3 if on else DB.PAL.ink2, DB.PAL.gold if on else tc.darkened(0.3), 2 if on else 1, 8, 4))
		var h := UI.hbox(8)
		h.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var t := MiniTile.new().setup(k, -1)
		t.custom_minimum_size = Vector2(34, 44)
		t.mouse_filter = Control.MOUSE_FILTER_IGNORE
		h.add_child(t)
		var c: Dictionary = DB.C[k]
		var tv := UI.vbox(0)
		tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tv.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		tv.add_child(UI.lbl(c.name, 14, tc.lightened(0.2), true))
		tv.add_child(UI.lbl("%s · %s · %s명" % [c.tag, DB.tier_name(k), Battle.num(c.tr)], 11, DB.PAL.bamboo))
		h.add_child(tv)
		if boon:
			var bn: Dictionary = DB.D.FORMBOON[page.gs.run.form]
			var pc := PanelContainer.new()
			pc.add_theme_stylebox_override("panel", UI.flat(DB.PAL.gold, DB.PAL.gold, 0, 7, 3))
			pc.add_child(UI.lbl("%s+%d%%" % [DB.D.STATNM.get(bn.stat, "발동"), roundi(float(bn.v) * 100)], 10, Color("#1A1508"), true))
			pc.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			pc.mouse_filter = Control.MOUSE_FILTER_IGNORE
			h.add_child(pc)
		if qty > 1:
			var q := UI.lbl("×%d" % qty, 13, DB.PAL.gold, true)
			q.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			q.mouse_filter = Control.MOUSE_FILTER_IGNORE
			h.add_child(q)
		for ch in [tv] + tv.get_children():
			ch.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(h)

	func _gui_input(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
			if e.pressed:
				_press = e.position
				_held = 0.0
				_dragging = false
			else:
				if _press != Vector2.INF and not _dragging and e.position.distance_to(_press) < 14:
					UI.buzz()
					page.hand_tap(k)
				_press = Vector2.INF
		elif e is InputEventMouseMotion and _press != Vector2.INF and e.position.distance_to(_press) >= 14:
			_press = Vector2.INF

	func _process(dt: float) -> void:
		if _press == Vector2.INF or _dragging:
			return
		_held += dt
		if _held >= CardTile.HOLD:
			_dragging = true
			_press = Vector2.INF
			var pv := MiniTile.new().setup(k, -1)
			pv.size = Vector2(56, 84)
			pv.modulate = Color(1, 1, 1, 0.85)
			var holder := Control.new()
			holder.add_child(pv)
			pv.position = -pv.size / 2
			force_drag({"card": k, "from": -1}, holder)


## 손패 상자 —— 칸에서 끌어 오면 내린다
class HandDrop extends PanelContainer:
	var page: DeployPage

	func _can_drop_data(_p: Vector2, data) -> bool:
		return data is Dictionary and data.has("from") and data.from >= 0

	func _drop_data(_p: Vector2, data) -> void:
		page.drop_hand(data)
