class_name DeployPage
extends RefCounted
## 편성 —— 진형 고르기 · 9칸 편성판 · 손패. 원본 rDeploy · openSlot · openItem.
## 놓는 법 셋: ① 손패 카드를 길게 눌러 칸으로 끈다 ② 손패 카드를 눌러 고르고 칸을 누른다
## ③ 칸을 눌러 목록에서 고른다. 칸끼리 끌면 자리를 바꾸고, 칸을 손패 쪽으로 끌면 내린다.

var gs: GameScreen
var sel := ""                 # 손패에서 고른 카드 (칸을 누르면 그 자리에 놓는다)


func build() -> Control:
	var run: Run = gs.run
	var v := UI.vbox(16)
	var f: Dictionary = DB.FORM[run.form]

	# 진형
	var forms := UI.flow(8)
	for key in DB.FORM:
		var fm: Dictionary = DB.FORM[key]
		var b := Button.new()
		b.custom_minimum_size = Vector2(132, 74)
		b.toggle_mode = true
		b.button_pressed = key == run.form
		b.add_theme_stylebox_override("pressed", UI.flat(DB.PAL.ink3, DB.PAL.gold, 2, 8, 10))
		b.add_theme_stylebox_override("hover_pressed", UI.flat(DB.PAL.ink3, DB.PAL.gold, 2, 8, 10))
		b.pressed.connect(func(): gs.act("set_form", [key]))
		var mini := FormMini.new()
		mini.mask = fm.mask
		mini.set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)
		mini.offset_left = -40
		mini.offset_right = -8
		mini.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(mini)
		var tl := UI.lbl(fm.n, 16, DB.PAL.paper, true)
		tl.position = Vector2(10, 12)
		tl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(tl)
		var sl := UI.lbl(fm.sil, 12, DB.PAL.bamboo_dim)
		sl.position = Vector2(10, 42)
		sl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(sl)
		forms.add_child(b)
	v.add_child(UI.sect("진형 — 3열 4행 · 9칸", forms))

	# 편성판 + 손패
	var two := UI.hbox(18)
	var bv := UI.vbox(6)
	var face := UI.lbl("▲ 적 진영", 13, DB.PAL.seal)
	face.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bv.add_child(face)
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	grid.add_child(Control.new())
	for col in ["좌", "중앙", "우"]:
		var cl := UI.lbl(col, 12, DB.PAL.bamboo_dim)
		cl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		grid.add_child(cl)
	for ri in f.grid.size():
		var ll := UI.lbl(DB.D.LINES[ri], 14, DB.PAL.bamboo, true)
		ll.custom_minimum_size = Vector2(44, 0)
		ll.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		grid.add_child(ll)
		for si in f.grid[ri]:
			var box := SlotBox.new()
			box.page = self
			box.slot = si
			grid.add_child(box)
	bv.add_child(grid)
	bv.add_child(UI.rich("[color=#8fd4c2]■[/color] 선호  [color=#e0806f]■[/color] 어색 — 물리 공격은 최전열부터 닿는다", 12))
	var btns := UI.hbox()
	var ab := UI.btn("자동 편성 + 장착", func():
		sel = ""
		gs.act("auto_deploy"), "pri")
	ab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btns.add_child(ab)
	var cb := UI.btn("전부 해제", func(): gs.act("clear_board"), "ghost")
	cb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btns.add_child(cb)
	bv.add_child(btns)
	two.add_child(bv)

	var hand := HandDrop.new()
	hand.page = self
	hand.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hand.add_theme_stylebox_override("panel", UI.flat(Color(DB.PAL.ink2, 0.6), DB.PAL.ink3, 1, 8, 10))
	var hv := UI.vbox(8)
	hand.add_child(hv)
	var keys := Run.sort_cards(run.inv.keys())
	hv.add_child(UI.eyebrow("손패 — %d종 · 길게 눌러 칸으로 끌거나, 눌러 고른 뒤 칸을 누른다" % keys.size()))
	if sel != "":
		hv.add_child(UI.rich("[color=#D9A64B]%s 을(를) 골랐다 — 놓을 칸을 누른다[/color]" % DB.C[sel].name, 13))
	var fl := UI.flow(8)
	for k in keys:
		var t := gs.tile(k, run.inv[k], func(id):
			if sel == id:
				gs.card_info(id)
			else:
				sel = id
				gs.render())
		t.drag_data = {"card": k, "from": -1}
		if k == sel:
			t.mark = "sel"
		fl.add_child(t)
	if keys.is_empty():
		hv.add_child(UI.hint("손패가 비었다 — 모두 편성했다."))
	hv.add_child(fl)
	two.add_child(hand)
	v.add_child(two)

	# 시너지 · 진형 우대 · 전력
	var syn := Battle.fac_syn(run.board, run.form)
	var row := UI.hbox(16)
	var fv := UI.vbox(4)
	var fc := UI.hbox(8)
	var cnt := {}
	for k in run.board:
		if k != null:
			cnt[DB.C[k].fac] = cnt.get(DB.C[k].fac, 0) + 1
	for fac in DB.D.FAC:
		var n: int = cnt.get(fac, 0)
		fc.add_child(UI.lbl("%s %d" % [fac, n], 15, DB.fac_color(fac) if n else Color(DB.PAL.paper, 0.3), true))
	fv.add_child(fc)
	for s in syn.list:
		var sd: Dictionary = DB.D.SYN[s.fac]
		fv.add_child(UI.rich("[b]%s[/b] %d명 · %s %s" % [DB.D.FAC[s.fac].full, s.n, sd.d, ("+%d" % s.v) if sd.stat == "morale" else "+%d%%" % roundi(s.v * 100)], 13))
	if syn.list.is_empty():
		fv.add_child(UI.hint("같은 세력 3명부터 시너지가 붙는다. 3·4·5명에서 단계가 오른다."))
	var p1 := UI.sect("세력 시너지", UI.panel(fv))
	p1.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(p1)
	var tv := UI.vbox(4)
	var tcnt := {}
	for k in run.board:
		if k != null:
			tcnt[DB.C[k].tag] = tcnt.get(DB.C[k].tag, 0) + 1
	for t in DB.D.TAGORDER:
		var n: int = tcnt.get(t, 0)
		if n == 0:
			continue
		var s: Dictionary = DB.D.TAGSYN[t]
		var e = syn.tag.get(t)
		tv.add_child(UI.rich("[b]%s[/b] %d명 · %s%s" % [t, n, ("%s +%d%%" % [s.d, roundi(e.v * 100)]) if e else "2명부터",
			("  [color=#D9A64B]「%s」 %s[/color]" % [s.cap, s.capd]) if n >= 5 else "  [color=#5d6a88]다섯이면 「%s」[/color]" % s.cap], 13))
	if tcnt.is_empty():
		tv.add_child(UI.hint("같은 병종 두 명부터 시너지가 붙는다."))
	var p2 := UI.sect("병종 시너지 — 2·3·4·5명", UI.panel(tv))
	p2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(p2)
	v.add_child(row)

	var bn = DB.D.FORMBOON.get(run.form)
	var bn_n := 0
	if bn:
		for t in bn.tags:
			bn_n += tcnt.get(t, 0)
	var row2 := UI.hbox(16)
	var boon := UI.rich("[b][color=#C6AC7C]%s[/color][/b] — %s\n%s에게 %s +%d%%  [color=%s]현재 %d명 해당[/color]" % [
		f.n, bn.d if bn else "", " · ".join(bn.tags) if bn else "", DB.D.STATNM.get(bn.stat, "스킬 발동률") if bn else "",
		roundi(bn.v * 100) if bn else 0, "#8fd4c2" if bn_n else "#e0806f", bn_n], 13)
	var p3 := UI.sect("진형 우대", UI.panel(boon))
	p3.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row2.add_child(p3)
	var sr := UI.hbox()
	sr.add_child(UI.stat(Battle.num(roundi(run.board_power() * syn.troop)), "총 병력"))
	sr.add_child(UI.stat("%d/9" % run.placed(), "배치"))
	sr.add_child(UI.stat(str(mini(200, run.my_morale() + int(syn.morale))), "시작 사기"))
	sr.add_child(UI.stat(str(run.equipped_count()), "장착"))
	var p4 := UI.sect("편성 전력", UI.panel(sr))
	p4.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row2.add_child(p4)
	v.add_child(row2)

	var bk := run.bag_keys()
	var iv := UI.flow(8)
	for id in bk:
		iv.add_child(gs.item_box(id, run.bag[id]))
	var tot := 0
	for id in run.bag:
		tot += run.bag[id]
	var ib := UI.vbox(6)
	ib.add_child(iv if not bk.is_empty() else UI.hint("보급품이 없다. 페이즈가 넘어가면 하나씩 지급된다."))
	ib.add_child(UI.hint("칸을 눌러 장착한다. 유니크는 신화 장수 조합에 쓰이며, 조합 시 그 장수에게 영구히 장착된다."))
	v.add_child(UI.sect("보급품 — %d개" % tot, ib))
	return v


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
	b.add_child(UI.rich("[color=#8fd4c2]선호[/color] %s\n[color=#e0806f]어색[/color] %s" % [", ".join(pref) if pref else "없음", ", ".join(bad) if bad else "없음"], 13))
	if cur != null:
		var c: Dictionary = DB.C[cur]
		var cv := UI.vbox(8)
		var top := UI.hbox(10)
		top.add_child(gs.tile(cur))
		var inn = Run.innate_item(cur)
		var it = run.item_of_slot(i)
		var iv := UI.vbox(6)
		iv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if inn != null:
			iv.add_child(UI.hint("🔒 %s 내장 — 탈착할 수 없다 · 효과 ×%s" % [DB.IT[inn].name, Battle.MYTH_AMP]))
		else:
			iv.add_child(UI.btn("아이템: %s" % DB.IT[it].name if it != null else "아이템 장착", func(): item_sheet(i)))
		iv.add_child(UI.btn("내리기", func():
			gs.close_sheet()
			gs.act("unplace", [i]), "ghost"))
		top.add_child(iv)
		cv.add_child(top)
		if c.sk:
			cv.add_child(UI.hint("『%s』 %s" % [c.sk.n, DB.skill_desc(c)]))
		b.add_child(UI.panel(cv, 10))
	var keys := Run.sort_cards(run.inv.keys())
	if keys.is_empty():
		b.add_child(UI.hint("배치할 카드가 없다."))
		return
	b.add_child(UI.eyebrow("손패에서 고르기"))
	var f := UI.flow(8)
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
	var f := UI.flow(8)
	for id in cand:
		f.add_child(gs.item_box(id, run.bag[id] - used.get(id, 0), func():
			gs.close_sheet()
			gs.act("set_equip", [i, id])))
	b.add_child(f)


## 편성판 한 칸
class SlotBox extends Control:
	const SZ := Vector2(176, 96)
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
				if _press != Vector2.INF and not _dragging:
					page.tap_slot(slot)
				_press = Vector2.INF
		elif e is InputEventMouseMotion and _press != Vector2.INF and e.position.distance_to(_press) >= 14:
			_start_drag()

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
			draw_string(DB.font_display, Vector2(0, size.y * 0.5 + 10), "＋", HORIZONTAL_ALIGNMENT_CENTER, size.x, 28, Color(DB.PAL.bamboo_dim, 0.7))
			draw_string(fb, Vector2(0, size.y - 8), UI.pos_name(s.line, s.col), HORIZONTAL_ALIGNMENT_CENTER, size.x, 11, DB.PAL.bamboo_dim)
			return
		var c: Dictionary = DB.C[k]
		var pr := Rect2(6, 6, 58, size.y - 12)
		Art.draw_portrait(self, pr, k)
		var x := pr.end.x + 7
		var tw := size.x - x - 5
		var fs := 15
		while fs > 10 and DB.font_display.get_string_size(c.name, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > tw:
			fs -= 1
		draw_string(DB.font_display, Vector2(x, 24), c.name, HORIZONTAL_ALIGNMENT_LEFT, tw, fs, DB.tier_color(k).lightened(0.2))
		var tag_line: String = c.tag + ((" · " + ("선호" if z == "pref" else "어색")) if z != "" else "")
		draw_string(fb, Vector2(x, 43), tag_line, HORIZONTAL_ALIGNMENT_LEFT, tw, 12, DB.PAL.jade if z == "pref" else (DB.PAL.seal if z == "bad" else DB.PAL.bamboo))
		draw_string(fb, Vector2(x, 61), Battle.num(c.tr) + "명", HORIZONTAL_ALIGNMENT_LEFT, tw, 12, DB.PAL.bamboo_dim)
		var it = run.item_of_slot(slot)
		var itxt: String = "빈 슬롯" if it == null else DB.IT[it].name + (" 🔒" if Run.innate_item(k) != null else "")
		draw_string(fb, Vector2(x, 82), itxt, HORIZONTAL_ALIGNMENT_LEFT, tw, 11, UI.item_col(it) if it != null else Color(DB.PAL.bamboo_dim, 0.6))


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
		var cs := 7.0
		var gap := 2.0
		var oy := (size.y - (cs * 4 + gap * 3)) / 2
		for ri in mask.size():
			var row: String = mask[ri]
			for ci in row.length():
				var on := row[ci] == "X"
				draw_rect(Rect2(ci * (cs + gap), oy + ri * (cs + gap), cs, cs), DB.PAL.bamboo if on else Color(DB.PAL.ink4, 0.6))
