class_name DeployPage
extends RefCounted
## 편성 —— 진형 고르기 · 9칸 편성판 · 손패. 원본 rDeploy · openSlot · openItem.
## 세로 화면: 위에 진형 띠와 편성판, 맨 아래 [보유 | 보급품] 탭. 탭을 열면 그 안만 스크롤한다.
## 11/7 사용자: 탭을 열어도 편성판 칸이 찌그러지지 않게 —— 페이지 전체를 세로 스크롤 상자(PageScroll)에 넣고, 열리면 편성판 높이를
## 닫힌 때 그대로 고정한 채 아래 칸(LOWER_H)만큼 넘치게 한다. 넘친 만큼 페이지가 위로 밀려 올라가(진형 띠가 위로 숨는다) 끌어 내리면 다시 보인다.
## 놓는 법 셋: ① 손패 카드를 길게 눌러 칸으로 끈다 ② 손패 카드를 눌러 고르고 칸을 누른다
## ③ 칸을 눌러 목록에서 고른다. 칸을 길게 눌러 다른 칸으로 끌면 자리를 바꾸고, 아래 목록으로 끌면 내린다.

const InyeonUI := preload("res://scripts/ui/inyeon_ui.gd")      # 11/11 인연 표시 공용

var gs: GameScreen
var _links: Array = []        # 11/11 지금 편성판에서 이어진 인연 (DB.inyeon_links) —— build 때마다 다시 센다
var _link_n := {}             # 인물 -> 그 인물이 든 이어진 인연 수 (칸 모서리 표시의 숫자)
var sel := ""                 # 손패에서 고른 카드 (칸을 누르면 그 자리에 놓는다)
var seg := ""                 # 아래 나눔 탭 —— hand · item. "" = 닫힘 (11/5 사용자: 기본 닫힌 채, 누르면 열림)
const LOWER_H := 168.0        # 열린 아래 칸 높이 (11/5 사용자: 예전 남는 공간 전부 → 절반쯤)
const SEP := 10.0             # 진형 띠 · 편성판 · 아래 칸 사이 간격
var _slide_up := false        # 방금 열었다 —— 올라오는 연출
var _form_scroll := 0         # 진형 띠 가로 스크롤 —— 진형을 골라 다시 그려도 그 자리에 (11/6 사용자)
var _page_scroll := -1        # 탭을 연 채 페이지 세로 스크롤 —— 카드를 놓아 다시 그려도 그 자리에. -1 = 맨 아래 (아래 칸이 다 보이게)


func build() -> Control:
	var run: Run = gs.run
	var f: Dictionary = DB.FORM[run.form]
	_links = DB.inyeon_links(run.board)
	_link_n = {}
	for l in _links:
		for p in l["in"]:
			_link_n[p] = int(_link_n.get(p, 0)) + 1
	# 11/7 사용자: 페이지 전체가 세로 스크롤 상자 —— 닫힌 때는 꼭 맞아 스크롤이 없고, 열리면 아래 칸만큼 넘친다 (편성판 높이는 아래 fit 이 고정)
	var root := PageScroll.new()
	root.want = _page_scroll
	root.anim = _slide_up
	_slide_up = false
	var v := UI.vbox(int(SEP))
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(v)
	if gs.online != null and not gs.can_form():      # 11/12 페이즈 개편 —— 편성이 막힌 단계면 이유 한 줄 (버튼은 잠근다)
		v.add_child(UI.hint(gs.online.block_reason("form")))

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
		b.add_theme_font_override("font", DB.title_font(14))
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

	# 11/5 사용자: 작전(군령) 고르기 삭제. 11/9 사용자: 진형 우대(FORMBOON) 삭제 —— 진형은 모양(칸)과 칸 선호로만

	# 편성판 —— 화면 위쪽 (손패에서 길게 눌러 끌어 올 수 있게)
	var bp := UI.vbox(6)
	var hd := UI.hbox(6)
	var hl := UI.vbox(0)
	hl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# 11/9 사용자: 진형 우대 삭제 —— 머리는 진형 이름만 (예전 '창병 · 유생 방어 +14%' 효과 줄과 「비늘이 서로를 가린다」 설명 줄 삭제)
	var fnr := UI.hbox(10)
	fnr.add_child(UI.lbl(f.n, 17, DB.PAL.paper, true))
	fnr.add_child(_inyeon_chip())      # 11/11 인연 —— 진형 이름 옆 칩 (이어진 수 · 누르면 시트)
	hl.add_child(fnr)
	hd.add_child(hl)
	var ab := UI.btn("자동 편성", func():
		sel = ""
		gs.act("auto_deploy"), "pri", 40)
	ab.add_theme_font_size_override("font_size", 14)
	ab.disabled = not gs.can_form()
	hd.add_child(ab)
	var cb := UI.btn("해제", func(): gs.act("clear_board"), "ghost", 40)
	cb.add_theme_font_size_override("font_size", 14)
	cb.disabled = not gs.can_form()
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
		_page_scroll = -1      # 열고 닫을 때는 맨 아래부터 (그 자리를 지키는 건 연 채로 다시 그릴 때만)
		gs.render())
	v.add_child(hand)
	if seg != "":
		var sc := UI.scroll()
		sc.custom_minimum_size.y = LOWER_H
		hv.add_child(sc)
		var lower := UI.vbox(6)
		lower.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sc.add_child(lower)
		match seg:
			"hand": _hand(lower, keys)
			"item": _items(lower)
		var pad := Control.new()
		pad.custom_minimum_size = Vector2(0, 12)
		lower.add_child(pad)
		# 11/7 사용자: 아래 칸 높이는 LOWER_H 까지 —— 다만 맨 아래로 밀렸을 때 편성판 격자가 위로 잘리지 않을 만큼만 (= 격자 위에 있는 진형 띠 · 편성판 머리글 높이).
		# 줄바꿈 글줄(효과 · 설명)의 높이는 정렬 때 정해지니 bp 가 정렬될 때마다 다시 잰다 (같은 프레임 안에서 끝나 튀지 않는다). 8 = 편성판 panel 여백, 5 = 격자 v_separation, 6 = hv 간격
		bp.sort_children.connect(func():
			if is_instance_valid(sc) and is_instance_valid(grid):
				var above := sc0.get_combined_minimum_size().y + SEP + 8 + grid.position.y + face.get_combined_minimum_size().y + 5
				sc.custom_minimum_size.y = clampf(above - 6, 112.0, LOWER_H))
	hv.add_child(tabs)          # 탭은 늘 맨 아래 —— 열리면 내용이 그 위에 온다
	# 11/7 사용자: 편성판 높이 고정 —— 열린 때 편성판 최소 높이 = 페이지 높이 − 진형 띠 − 탭 − 간격 둘 = 닫힌 때 편성판이 차지하던 높이.
	# 그래서 열어도 칸 크기 · 비율이 그대로고, 넘친 아래 칸만큼 페이지가 스크롤된다 (닫힌 때는 0 —— EXPAND_FILL 이 남는 공간을 채운다)
	var fit := func():
		if not is_instance_valid(root) or not is_instance_valid(bpp):
			return
		var h := root.size.y - sc0.get_combined_minimum_size().y - tabs.get_combined_minimum_size().y - SEP * 2
		bpp.custom_minimum_size.y = maxf(0.0, h) if seg != "" else 0.0
	root.resized.connect(fit)
	root.get_v_scroll_bar().value_changed.connect(func(_x): _page_scroll = root.want)
	return root


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
	for k in keys:
		var row := HandRow.new()
		row.page = self
		row.k = k
		row.qty = run.inv[k]
		row.on = k == sel
		hv.add_child(row)
	if keys.is_empty():
		hv.add_child(UI.hint("보유한 카드가 없다 — 모두 편성했다."))


# ───────── 인연 (11/11) ─────────

## 칸 i 의 카드가 든 이어진 인연 수 (0 = 없음)
func slot_link_lv(i: int) -> int:
	var k = gs.run.board[i]
	if k == null or not DB.inyeon_card(k):
		return 0
	return int(_link_n.get(DB.person(k), 0))


## 진형 이름 옆 칩 —— 기호 + '인연' (+ 이어진 인연 수). 이어진 게 없으면 옅게. 누르면 인연 시트
func _inyeon_chip() -> Control:
	var P := DB.PAL
	var n := _links.size()
	var on := n > 0
	var b := Button.new()
	b.text = "인연 %d" % n if on else "인연"
	b.custom_minimum_size = Vector2(0, 28)
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	b.add_theme_font_size_override("font_size", 13)
	var fc: Color = P.yeon.lightened(0.3) if on else P.bamboo_dim
	for cn in ["font_color", "font_hover_color", "font_focus_color", "font_pressed_color"]:
		b.add_theme_color_override(cn, fc)
	var sb := UI.flat(Color(P.yeon, 0.16) if on else P.ink2, Color(P.yeon, 0.9) if on else P.ink4, 1, UI.R, 0)
	sb.content_margin_left = 27      # 왼쪽에 기호 자리
	sb.content_margin_right = 10
	sb.content_margin_top = 3
	sb.content_margin_bottom = 3
	for st in ["normal", "hover", "pressed", "focus"]:
		b.add_theme_stylebox_override(st, sb)
	var ic := Icons.View.new("link", fc, 16)
	ic.position = Vector2(8, 6)
	b.add_child(ic)
	b.pressed.connect(func():
		UI.buzz()
		inyeon_sheet())
	return b


## 인연 시트 —— 이어진 인연마다 한 장: 이름 · 합동 인원(n/3) + 구성원 타일(편성한 장수 금테 · 손패에 있는 장수 '손패' · 없는 장수 어둡게).
## 그 아래 '이어질 인연' —— 한 명만 편성돼 있고 손패에 짝이 있는 인연 (손패 장수를 편성하면 이어진다). 맨 밑에 규칙 한 줄
func inyeon_sheet() -> void:
	var run: Run = gs.run
	var P := DB.PAL
	var b := gs.open_sheet("인연", P.yeon.lightened(0.15))
	var ctx := {"own": InyeonUI.owned_map(run, true), "deck": InyeonUI.deck_map(run.board), "pins": InyeonUI.pinned_map(gs.forge_tree.pins), "hand": true}
	var on_card := func(k: String): gs.card_info(k)
	var rows := _links.duplicate()
	rows.sort_custom(func(x, y): return x["in"].size() > y["in"].size())      # 많이 이어진 인연부터 (같으면 json 순서 그대로)
	for l in rows:
		b.add_child(_inyeon_block(l["n"], l["in"].size(), ctx, on_card))
	# 이어질 인연 —— 덱에 한 명, 손패에 짝(들)
	var near := []
	var dk: Dictionary = ctx.deck
	var own: Dictionary = ctx.own
	for nm in DB.INYEON:
		var inn := 0
		var hand := 0
		for p in DB.inyeon_members(nm):
			if dk.has(p):
				inn += 1
			elif own.has(p):
				hand += 1
		if inn == 1 and hand > 0:
			near.append([nm, hand])
	near.sort_custom(func(x, y): return x[1] > y[1])
	if not near.is_empty():
		b.add_child(UI.eyebrow("이어질 인연"))
		for e in near.slice(0, 4):
			b.add_child(_inyeon_block(e[0], 1, ctx, on_card))
	if rows.is_empty() and near.is_empty():
		b.add_child(UI.hint("편성한 장수 중 같은 인연이 둘 이상이면 여기에 나온다."))
	var rh := InyeonUI.rule_hint()
	b.add_child(rh)


## 인연 한 장 —— 머리(이름 · n/3) + 구성원 줄
func _inyeon_block(nm: String, n: int, ctx: Dictionary, on_card: Callable) -> Control:
	var P := DB.PAL
	var v := UI.vbox(8)
	var hd := UI.hbox(8)
	var ic := Icons.View.new("link", P.yeon, 18)
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hd.add_child(ic)
	var nl := UI.lbl(nm, 16, P.yeon.lightened(0.25), true)
	nl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hd.add_child(nl)
	var lv := mini(n, DB.INYEON_MAX)
	var cl := UI.lbl("%d/%d" % [lv, DB.INYEON_MAX], 15, P.gold if lv >= DB.INYEON_MAX else P.bamboo, true)
	hd.add_child(cl)
	v.add_child(hd)
	v.add_child(InyeonUI.members_row(nm, ctx, on_card))
	return UI.panel(v, 10)


func hand_tap(k: String) -> void:
	if sel == k:
		gs.card_info(k)
	else:
		sel = k
		gs.render()


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
	if not gs.can_form():
		gs.toast(gs.online.block_reason("form") if gs.online != null else "지금은 편성할 수 없다", "bad")
		return
	if sel != "" and gs.run.inv.get(sel, 0) > 0:
		var k := sel
		if gs.run.inv.get(k, 0) <= 1:
			sel = ""
		gs.act("place", [i, k])
		return
	slot_sheet(i)


func drop(i: int, data: Dictionary) -> void:
	if not gs.can_form():
		gs.toast(gs.online.block_reason("form") if gs.online != null else "지금은 편성할 수 없다", "bad")
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
	# 11/9 사용자: 텍스트가 너무 많다 —— 공격 · 방어 · 피격 글자를 칼 · 방패 · 과녁 기호로 (능력치 줄과 같은 기호 · 색)
	var sr := UI.hbox(5)
	sr.alignment = BoxContainer.ALIGNMENT_CENTER
	var _ico := func(icon: String, col: Color, tip: String) -> Control:
		var iv := Icons.View.new(icon, col, 20.0)
		iv.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		iv.mouse_filter = Control.MOUSE_FILTER_PASS
		iv.tooltip_text = tip
		return iv
	var _num := func(t: String, col: Color) -> Control:
		var l := UI.lbl(t, 15, col, true)
		l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		return l
	sr.add_child(_ico.call("blade", Color("#ff6b5a"), "공격"))
	sr.add_child(_num.call("%d%%" % roundi(ln.atk * 100), DB.PAL.paper))
	sr.add_child(_num.call("(책략 %d%%)" % roundi(ln["int"] * 100), Color("#6fa8ff")))
	var sp := Control.new()
	sp.custom_minimum_size.x = 8
	sr.add_child(sp)
	sr.add_child(_ico.call("shield", DB.PAL.bamboo.lightened(0.15), "방어"))
	sr.add_child(_num.call("%d%%" % roundi(ln["def"] * 100), DB.PAL.paper))
	var sp2 := Control.new()
	sp2.custom_minimum_size.x = 8
	sr.add_child(sp2)
	sr.add_child(_ico.call("target", DB.PAL.bamboo.lightened(0.15), "피격 순위"))
	sr.add_child(_num.call("%d순위" % int(ln.pri), DB.PAL.paper))
	b.add_child(sr)
	var zr := UI.flow(5)
	for t in DB.D.TAGORDER:
		var z := DB.aff_of(t, line, s.side)
		if z == "":
			continue
		var col := DB.PAL.jade if z == "pref" else DB.PAL.seal
		var chip := UI.lbl(("▲ " if z == "pref" else "▼ ") + t, 12, col.lightened(0.25), true)
		var pc := PanelContainer.new()
		pc.add_theme_stylebox_override("panel", UI.flat(DB.PAL.ink3, Color(0, 0, 0, 0), 0, UI.R, 4))      # 11/9 색 테두리 칩 → 먹색 칩 (선호 옥 · 어색 인장은 글자색으로만)
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
					if page.slot_link_lv(slot) > 0 and _yeon_rect().grow(6).has_point(e.position):      # 11/11 인연 표시를 누르면 인연 시트
						page.inyeon_sheet()
					else:
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

	## 11/11 인연 표시 자리 —— 칸 오른쪽 위 (초상 모서리)
	func _yeon_rect() -> Rect2:
		return Rect2(size.x - 31.0, 3.0, 28.0, 16.0)

	## 이어진 인연이 있는 카드에 작은 표시 —— 맞물린 고리 + 그 카드가 든 이어진 인연 수
	func _draw_yeon(lv: int) -> void:
		if lv <= 0:
			return
		var r := _yeon_rect()
		var sb := UI.flat(Color(DB.PAL.yeon, 0.96), Color(0, 0, 0, 0), 0, UI.R, 0)
		draw_style_box(sb, r)
		Icons.draw(self, "link", r.position + Vector2(9, 8), 13, Color("#2A1018"))
		draw_string(DB.font_bold, r.position + Vector2(15, 12.5), str(lv), HORIZONTAL_ALIGNMENT_LEFT, 11, 12, Color("#2A1018"))

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
		# 11/9 사용자: 진형 우대(금빛 바탕 · 테 · '방어+14%' 리본) 삭제 —— 테 색은 자리 선호(옥빛) · 어색(붉음)뿐
		var sb := UI.flat(bg, border, 2, 8, 0)
		if s.line == "선봉":
			sb.border_width_top = 4
		draw_style_box(sb, r)
		var fb := DB.font_body
		if k == null:
			draw_string(DB.title_font(24), Vector2(0, size.y * 0.5 + 6), "＋", HORIZONTAL_ALIGNMENT_CENTER, size.x, 24, Color(DB.PAL.bamboo_dim, 0.7))
			draw_string(fb, Vector2(0, size.y - 7), UI.pos_name(s.line, s.col), HORIZONTAL_ALIGNMENT_CENTER, size.x, 11, DB.PAL.bamboo_dim)
			return
		var c: Dictionary = DB.C[k]
		if size.x < 120:      # 11/6 5열 —— 좁은 칸: 초상 / 이름 / 병종 · 병력 / 아이템 / 진형 버프
			_draw_narrow(k, c, z, run)
			_draw_yeon(page.slot_link_lv(slot))
			return
		# 11/5 사용자: 칸을 크게 —— [초상] 이름 / 병종 / 병력, 그 아래 아이템(가운데)
		var ith := 15.0                             # 아이템 줄
		var ph := size.y - 10 - ith
		var pr := Rect2(5, 5, minf(ph * 0.75, size.x * 0.42), ph)
		Art.draw_portrait(self, pr, k)
		var x := pr.end.x + 6
		var tw := size.x - x - 4
		var nm: String = DB.person(k) if c.tier > 2 else c.name
		var fs := 16 if size.y >= 96 else 14
		var tf := DB.tier_font(c.tier, fs)
		while fs > 10 and tf.get_string_size(nm, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > tw:
			fs -= 1
		var ty := pr.position.y + minf(ph * 0.3, 22.0)
		var gap := clampf(ph * 0.26, 13.0, 20.0)
		draw_string(tf, Vector2(x, ty), nm, HORIZONTAL_ALIGNMENT_LEFT, tw, fs, DB.tier_color(k).lightened(0.2))
		draw_string(fb, Vector2(x, ty + gap), c.tag, HORIZONTAL_ALIGNMENT_LEFT, tw, 12, DB.PAL.jade if z == "pref" else (DB.PAL.seal if z == "bad" else DB.PAL.bamboo))
		draw_string(fb, Vector2(x, ty + gap * 2), Battle.num(c.tr) + "명", HORIZONTAL_ALIGNMENT_LEFT, tw, 12, DB.PAL.bamboo_dim)
		var it = run.item_of_slot(slot)
		var itxt: String = "빈 슬롯" if it == null else DB.IT[it].name + (" 🔒" if Run.innate_item(k) != null else "")
		draw_string(fb, Vector2(4, size.y - 6), itxt, HORIZONTAL_ALIGNMENT_CENTER, size.x - 8, 11, UI.item_col(it) if it != null else Color(DB.PAL.bamboo_dim, 0.6))
		_draw_yeon(page.slot_link_lv(slot))


	func _draw_narrow(k: String, c: Dictionary, z: String, run: Run) -> void:
		var fb := DB.font_body
		var ith := 12.0
		var txt_h := 25.0
		var ph := maxf(16.0, size.y - 8 - ith - txt_h)
		var pw := minf(size.x - 8, ph * 1.05)
		var pr := Rect2((size.x - pw) / 2, 4, pw, ph)
		Art.draw_portrait(self, pr, k)
		var nm: String = DB.person(k) if c.tier > 2 else c.name
		var tf := DB.tier_font(c.tier, 13)
		var fs := 13
		while fs > 9 and tf.get_string_size(nm, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > size.x - 6:
			fs -= 1
		var y := pr.end.y + 12
		draw_string(tf, Vector2(3, y), nm, HORIZONTAL_ALIGNMENT_CENTER, size.x - 6, fs, DB.tier_color(k).lightened(0.2))
		var info := "%s %s" % [c.tag, Battle.num(c.tr)]
		draw_string(fb, Vector2(2, y + 12), info, HORIZONTAL_ALIGNMENT_CENTER, size.x - 4, 10, DB.PAL.jade if z == "pref" else (DB.PAL.seal if z == "bad" else DB.PAL.bamboo_dim))
		var it = run.item_of_slot(slot)
		var itxt: String = "빈 슬롯" if it == null else DB.IT[it].name
		draw_string(fb, Vector2(2, size.y - 5), itxt, HORIZONTAL_ALIGNMENT_CENTER, size.x - 4, 9, UI.item_col(it) if it != null else Color(DB.PAL.bamboo_dim, 0.6))


## 손패 한 줄 (11/5) —— [초상] 이름(등급색) / 병종 · 등급 · 병력, ×수. 누르면 page.hand_tap, 길게 눌러 끈다
class HandRow extends PanelContainer:
	var page: DeployPage
	var k := ""
	var qty := 1
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


## 페이지 세로 스크롤 상자 (11/7) —— 레이아웃이 끝나는 바로 그때(SORT_CHILDREN 뒤) 스크롤을 맞춰, 다시 그려도 한 프레임도 튀지 않는다.
## (call_deferred 로 맞추면 스크롤 범위가 아직 안 잡혀 0 으로 잘린다.) 세로 막대는 숨긴다 —— 보이면 그 폭만큼 편성판이 좁아져 칸 폭이 바뀐다.
## want: 맞출 자리 (-1 = 맨 아래) · 사용자가 끌면 그 자리를 따라간다 · anim: 열리는 연출 —— 0 에서 맨 아래로 0.18초
class PageScroll extends ScrollContainer:
	var want := -1
	var anim := false
	var _t := -1.0            # 연출 진행 (0~1). -1 = 연출 없음 · 끝남
	var _mine := false        # 지금 바꾸는 건 내 쪽 (사용자 끌기가 아니다)

	func _init() -> void:
		horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
		TouchScroll.add(self)
		get_v_scroll_bar().value_changed.connect(func(x):
			if not _mine:
				want = int(x))

	func _notification(what: int) -> void:
		if what != NOTIFICATION_SORT_CHILDREN:
			return
		if anim:
			anim = false
			_t = 0.0              # 연출이 시작되기 전(같은 프레임의 다음 정렬)에도 0 에 붙들어 둔다 —— 아니면 맨 아래로 튀었다가 연출이 시작된다
			_put(0)
			var tw := create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
			tw.tween_method(_step, 0.0, 1.0, 0.18)
			tw.tween_callback(func(): _t = -1.0)
			return
		if _t >= 0.0:
			_step(_t)             # 연출 중에 레이아웃이 바뀌어도 그 비율 자리에
			return
		_put(_max() if want < 0 else mini(want, _max()))

	func _step(t: float) -> void:
		_t = t
		_put(int(roundf(t * _max())))

	func _put(y: int) -> void:
		_mine = true
		scroll_vertical = y
		_mine = false

	func _max() -> int:
		var b := get_v_scroll_bar()
		return int(maxf(0.0, b.max_value - b.page))
