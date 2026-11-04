class_name DeployPage
extends RefCounted
## 편성 —— 진형 고르기 · 9칸 편성판 · 손패. 원본 rDeploy · openSlot · openItem.
## 세로 화면: 위에 진형 띠와 편성판을 고정하고, 아래 [손패 | 진형 | 보급품] 만 스크롤한다.
## 놓는 법 셋: ① 손패 카드를 길게 눌러 칸으로 끈다 ② 손패 카드를 눌러 고르고 칸을 누른다
## ③ 칸을 눌러 목록에서 고른다. 칸을 길게 눌러 다른 칸으로 끌면 자리를 바꾸고, 아래 목록으로 끌면 내린다.

var gs: GameScreen
var sel := ""                 # 손패에서 고른 카드 (칸을 누르면 그 자리에 놓는다)
var seg := "hand"             # 아래 나눔 탭 —— hand · syn · item


func build() -> Control:
	var run: Run = gs.run
	var v := UI.vbox(10)
	var f: Dictionary = DB.FORM[run.form]

	# 진형 —— 가로로 넘기는 띠
	var st := UI.strip(6)
	for key in DB.FORM:
		var fm: Dictionary = DB.FORM[key]
		var on: bool = key == run.form
		var b := Button.new()
		b.custom_minimum_size = Vector2(92, 40)
		b.add_theme_stylebox_override("normal", UI.flat(DB.PAL.ink3 if on else DB.PAL.ink2, DB.PAL.gold if on else DB.PAL.ink4, 2 if on else 1, 10, 8))
		b.add_theme_stylebox_override("hover", UI.flat(DB.PAL.ink3, DB.PAL.gold if on else DB.PAL.bamboo_dim, 2 if on else 1, 10, 8))
		b.add_theme_stylebox_override("pressed", UI.flat(DB.PAL.ink4, DB.PAL.gold, 2, 10, 8))
		b.pressed.connect(func():
			UI.buzz()
			gs.act("set_form", [key]))
		var mini := FormMini.new()
		mini.mask = fm.mask
		mini.set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)
		mini.offset_left = -34
		mini.offset_right = -6
		mini.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(mini)
		var tl := UI.lbl(fm.n, 14, DB.PAL.gold if on else DB.PAL.paper, true)
		tl.position = Vector2(9, 10)
		tl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(tl)
		st[1].add_child(b)
	v.add_child(st[0])

	# 작전 —— 전투는 자동, 이 방침대로 AI 가 고유기 · 군령을 쓴다
	var tv := UI.vbox(2)
	var rec := Run.recommend_tac(run.board)
	tv.add_child(UI.segmented(Run.TACS.keys().map(func(k): return [k, ("작전 " + k) + (" ★" if k == rec[0] else "")]), run.tac, func(k):
		gs.act("set_tac", [k])))
	v.add_child(tv)      # 11/4 사용자: 징집 · 조합처럼 설명 글은 빼고 공간 확보 (★ = 덱에 맞는 추천)

	# 편성판 —— 화면 위쪽에 고정 (손패에서 길게 눌러 끌어 올 수 있게)
	var syn := Battle.fac_syn(run.board, run.form)
	var bp := UI.vbox(6)
	var hd := UI.hbox(6)
	var hl := UI.vbox(0)
	hl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hl.add_child(UI.lbl("%s  ·  %d/9칸" % [f.n, run.placed()], 16, DB.PAL.paper, true))
	hl.add_child(UI.lbl("%s명 · 사기 %d · 장착 %d" % [Battle.num(roundi(run.board_power() * syn.troop)), mini(200, run.my_morale() + int(syn.morale)), run.equipped_count()], 12, DB.PAL.bamboo))
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
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 5)
	grid.add_theme_constant_override("v_separation", 5)
	var face := UI.lbl("▲적", 11, DB.PAL.seal)
	face.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	grid.add_child(face)
	for col in ["좌", "중앙", "우"]:
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
			grid.add_child(box)
	bp.add_child(grid)
	v.add_child(UI.panel(bp, 8))

	# 아래 —— [손패 | 진형 | 보급품] 나눔 탭, 그 안만 스크롤. 칸을 여기로 끌면 내린다
	var keys := Run.sort_cards(run.inv.keys())
	var n_items := 0
	for id in run.bag:
		n_items += run.bag[id]
	v.add_child(UI.segmented([["hand", "손패 %d" % keys.size()], ["syn", "진형"], ["item", "보급품 %d" % n_items]], seg, func(k):
		seg = k
		gs.render()))
	var hand := HandDrop.new()
	hand.page = self
	hand.size_flags_vertical = Control.SIZE_EXPAND_FILL
	hand.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	var sc := UI.scroll()
	hand.add_child(sc)
	var lower := UI.vbox(10)
	lower.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(lower)
	v.add_child(hand)
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

	var fl := UI.grid(56, 5)      # 11/4 사용자: 징집 페이지처럼 한 줄 6칸 작은 칸 격자
	fl.max_cols = 6
	for k in keys:
		var t := gs.mtile(k, run.inv[k], func(id):
			if sel == id:
				gs.card_info(id)
			else:
				sel = id
				gs.render())
		t.drag_data = {"card": k, "from": -1}
		t.custom_minimum_size = Vector2(56, 84)
		if k == sel:
			t.mark = "sel"
		fl.add_child(t)
	if keys.is_empty():
		hv.add_child(UI.hint("손패가 비었다 — 모두 편성했다."))
	hv.add_child(fl)


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


func _items(v: VBoxContainer) -> void:
	var run: Run = gs.run
	var bk := run.bag_keys()
	var iv := UI.grid(170, 8)
	for id in bk:
		iv.add_child(gs.item_box(id, run.bag[id], func(): gs._item_sheet(id)))      # 누르면 아이템 시트 (유니크는 들어가는 신화 장수)
	v.add_child(iv if not bk.is_empty() else UI.hint("보급품이 없다. 페이즈가 넘어가면 하나씩 지급된다."))



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
	var run: Run = gs.run
	var s: Dictionary = DB.FORM[run.form].slots[i]
	var line: String = s.line
	var ln: Dictionary = DB.D.LINE[line]
	var cur = run.board[i]
	var b := gs.open_sheet("%s 배치" % UI.pos_name(line, s.col))
	b.add_child(UI.hint("%s · %s — 공격 %d%% · 방어 %d%% · 책략 %d%% · 피격 %d순위" % [line, s.side, roundi(ln.atk * 100), roundi(ln["def"] * 100), roundi(ln["int"] * 100), ln.pri]))
	var pref := []
	var bad := []
	for t in DB.D.TAGORDER:
		var z := DB.aff_of(t, line, s.side)
		if z == "pref":
			pref.append("%s(%s)" % [t, UI.aff_desc(t, "pref")])
		elif z == "bad":
			bad.append("%s(%s)" % [t, UI.aff_desc(t, "bad")])
	b.add_child(UI.rich("[color=#8fd4c2]선호[/color] %s\n[color=#e0806f]어색[/color] %s" % [", ".join(pref) if pref else "없음", ", ".join(bad) if bad else "없음"], 14))
	if cur != null:
		var c: Dictionary = DB.C[cur]
		var cv := UI.vbox(8)
		cv.add_child(gs.tile(cur))
		var inn = Run.innate_item(cur)
		var it = run.item_of_slot(i)
		var iv := UI.hbox(8)
		if inn != null:
			iv.add_child(UI.hint("🔒 %s 내장 — 탈착할 수 없다 · 효과 ×%s" % [DB.IT[inn].name, Battle.MYTH_AMP]))
		else:
			var ib := UI.btn("아이템: %s" % DB.IT[it].name if it != null else "아이템 장착", func(): item_sheet(i), "", 46)
			ib.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			iv.add_child(ib)
		var ub := UI.btn("내리기", func():
			gs.close_sheet()
			gs.act("unplace", [i]), "ghost", 46)
		ub.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		iv.add_child(ub)
		cv.add_child(iv)
		if c.sk:
			cv.add_child(UI.hint("『%s』 %s —— %s" % [c.sk.n, DB.sk_when(c.sk), DB.skill_desc(c)]))
		b.add_child(UI.panel(cv, 10))
	var keys := Run.sort_cards(run.inv.keys())
	if keys.is_empty():
		b.add_child(UI.hint("배치할 카드가 없다."))
		return
	b.add_child(UI.eyebrow("손패에서 고르기"))
	var f := gs.tiles()
	for k in keys:
		var t := gs.tile(k, run.inv[k], func(id):
			gs.close_sheet()
			gs.act("place", [i, id]))
		var z := DB.aff_of(DB.C[k].tag, line, s.side)
		if z != "":
			t.mark = z
			t.note = "%s · %s" % ["선호" if z == "pref" else "어색", UI.aff_desc(DB.C[k].tag, z)]
			t.note_col = DB.PAL.jade if z == "pref" else DB.PAL.seal
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
	const SZ := Vector2(92, 72)
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
		var sb := UI.flat(bg, border, 2, 8, 0)
		if s.line == "선봉":
			sb.border_width_top = 4
		draw_style_box(sb, r)
		var fb := DB.font_body
		if k == null:
			draw_string(DB.font_display, Vector2(0, size.y * 0.5 + 6), "＋", HORIZONTAL_ALIGNMENT_CENTER, size.x, 24, Color(DB.PAL.bamboo_dim, 0.7))
			draw_string(fb, Vector2(0, size.y - 7), UI.pos_name(s.line, s.col), HORIZONTAL_ALIGNMENT_CENTER, size.x, 11, DB.PAL.bamboo_dim)
			return
		var c: Dictionary = DB.C[k]
		var ph := size.y - 22
		var pr := Rect2(5, 5, minf(ph * 0.75, size.x * 0.4), ph)
		Art.draw_portrait(self, pr, k)
		var x := pr.end.x + 5
		var tw := size.x - x - 4
		var nm: String = DB.person(k) if c.tier > 2 else c.name
		var fs := 14
		var tf := DB.tier_font(c.tier)
		while fs > 10 and tf.get_string_size(nm, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > tw:
			fs -= 1
		draw_string(tf, Vector2(x, 19), nm, HORIZONTAL_ALIGNMENT_LEFT, tw, fs, DB.tier_color(k).lightened(0.2))
		draw_string(fb, Vector2(x, 34), c.tag, HORIZONTAL_ALIGNMENT_LEFT, tw, 11, DB.PAL.jade if z == "pref" else (DB.PAL.seal if z == "bad" else DB.PAL.bamboo))
		draw_string(fb, Vector2(x, 47), Battle.num(c.tr), HORIZONTAL_ALIGNMENT_LEFT, tw, 11, DB.PAL.bamboo_dim)
		var it = run.item_of_slot(slot)
		var itxt: String = "빈 슬롯" if it == null else DB.IT[it].name + (" 🔒" if Run.innate_item(k) != null else "")
		draw_string(fb, Vector2(5, size.y - 5), itxt, HORIZONTAL_ALIGNMENT_LEFT, size.x - 10, 10, UI.item_col(it) if it != null else Color(DB.PAL.bamboo_dim, 0.6))


## 손패 상자 —— 칸에서 끌어 오면 내린다
class HandDrop extends PanelContainer:
	var page: DeployPage

	func _can_drop_data(_p: Vector2, data) -> bool:
		return data is Dictionary and data.has("from") and data.from >= 0

	func _drop_data(_p: Vector2, data) -> void:
		page.drop_hand(data)


## 진형 미리보기 —— 4행 3열 점
class FormMini extends Control:
	var mask: Array = []

	func _draw() -> void:
		var cs := 6.0
		var gap := 2.0
		var oy := (size.y - (cs * 4 + gap * 3)) / 2
		for ri in mask.size():
			var row: String = mask[ri]
			for ci in row.length():
				var on := row[ci] == "X"
				draw_rect(Rect2(ci * (cs + gap), oy + ri * (cs + gap), cs, cs), DB.PAL.bamboo if on else Color(DB.PAL.ink4, 0.6))
