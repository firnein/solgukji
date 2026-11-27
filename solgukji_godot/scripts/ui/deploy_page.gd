class_name DeployPage
extends RefCounted
## 편성 —— 진형 고르기 · 9칸 편성판 · 손패. 원본 rDeploy · openSlot · openItem.
## 세로 화면: 위에 진형 띠와 편성판, 맨 아래 [보유 | 보급품] 탭. 탭을 열면 그 안만 스크롤한다.
## 11/14 UI 감사 #8: 페이지는 스크롤하지 않는다 —— 진형 띠 · 편성판 머리줄(자동 편성 · 해제)은 늘 제자리. 탭을 열면 편성판 칸을
## 작게(SlotBox.compact —— 초상 · 이름만) 그리고 남는 높이를 모두 아래 목록(보유 카드 격자)에 준다.
## 놓는 법 셋: ① 손패 카드를 길게 눌러 칸으로 끈다 ② 손패 카드를 눌러 고르고 칸을 누른다
## ③ 칸을 눌러 목록에서 고른다. 칸을 길게 눌러 다른 칸으로 끌면 자리를 바꾸고, 아래 목록으로 끌면 내린다.

const InyeonUI := preload("res://scripts/ui/inyeon_ui.gd")      # 11/11 인연 표시 공용
const TacUI := preload("res://scripts/ui/tac_ui.gd")      # 11/15 군략 카드 —— 편성판 아래 「군략 1 · 2 · 3단계」 칸 줄
const Kit := preload("res://scripts/kit.gd")      # 11/27 장수 키트 —— 편성판 아래 강화 줄 (칩을 끌어 장수 위에)

var gs: GameScreen
var _links: Array = []        # 11/11 지금 편성판에서 이어진 인연 (DB.inyeon_links) —— build 때마다 다시 센다
var _link_n := {}             # 인물 -> 그 인물이 든 이어진 인연 수 (칸 모서리 표시의 숫자)
var sel := ""                 # 손패에서 고른 카드 (칸을 누르면 그 자리에 놓는다)
var seg := ""                 # 아래 나눔 탭 —— hand · item. "" = 닫힘 (11/5 사용자: 기본 닫힌 채, 누르면 열림)
const SEP := 10.0             # 진형 띠 · 편성판 · 아래 칸 사이 간격
var _slide_up := false        # 방금 열었다 —— 올라오는 연출
var _form_scroll := 0         # 진형 띠 가로 스크롤 —— 진형을 골라 다시 그려도 그 자리에 (11/6 사용자)
const MIN_LOWER_H := 150.0    # 열린 아래 목록의 최소 높이 (남는 높이는 모두 목록에)
const HARD_CHIP := Vector2(84, UI.BH_S)      # 험지 토벌 칩 —— 켜도 꺼도 같은 크기 (11/15 칸 밀림)
const HAND_TILE := Vector2(56, 80)     # 보유 카드 격자 한 칸 (최소 —— 남는 폭은 나눠 가진다)


func build() -> Control:
	_gear_rows = -1
	_boxes = {}
	var run: Run = gs.run
	var f: Dictionary = DB.FORM[run.form]
	_links = DB.inyeon_links(run.board)
	_link_n = {}
	for l in _links:
		for p in l["in"]:
			_link_n[p] = int(_link_n.get(p, 0)) + 1
	var open := seg != ""
	# 11/14 UI 감사 #8: 「보유」를 열면 페이지가 위로 밀려 진형 고르기 · 자동 편성이 화면 밖으로 사라지고 보유 목록은 두 줄만 보였다 ——
	# 이제 페이지는 스크롤하지 않는다. 진형 띠 · 편성판 머리줄은 늘 제자리, 열리면 편성판 칸을 줄이고(SlotBox.compact) 남는 높이를 모두 아래 목록에 준다
	var v := UI.vbox(int(SEP))
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.size_flags_vertical = Control.SIZE_EXPAND_FILL
	if gs.online != null and not gs.can_form():      # 11/12 페이즈 개편 —— 편성이 막힌 단계면 이유 한 줄 (버튼은 잠근다)
		v.add_child(UI.hint(gs.online.block_reason("form")))

	# 진형 —— 가로로 넘기는 띠. 11/7 사용자: 이름만 (미니 격자를 붙이니 칩 폭이 모자라 레이아웃이 무너졌다). 효과 줄은 아래 편성판 머리에 한 줄
	var st := UI.strip(UI.SP_S)
	for key in DB.FORM:
		var fm: Dictionary = DB.FORM[key]
		if fm.get("foe", false):      # 토벌 적 전용 대군 진형
			continue
		var on: bool = key == run.form
		var b := TouchButton.new()
		b.hit.x = 0.0
		b.text = fm.n
		# 11/14 UI 4단계 (감사 07-4): 이름만으로는 모양을 몰랐다 —— 진형 칸 모양(mask)을 작은 점 그림 아이콘으로 이름 왼쪽에.
		# 11/7 에 미니 격자를 뺀 까닭(칩 폭이 모자라 레이아웃이 무너짐)을 피해 버튼 icon 으로 —— 버튼이 제 폭을 재고, 띠는 가로로 넘긴다
		b.icon = form_glyph(fm.get("mask", []), on)
		b.add_theme_constant_override("h_separation", 6)
		b.custom_minimum_size = Vector2(76, UI.BH_S)
		b.add_theme_font_override("font", DB.title_font(UI.FS_BODY))
		b.add_theme_font_size_override("font_size", UI.FS_BODY)
		for cn in ["font_color", "font_hover_color", "font_focus_color"]:
			b.add_theme_color_override(cn, DB.PAL.gold if on else DB.PAL.paper)
		b.add_theme_color_override("font_pressed_color", DB.PAL.gold)
		b.add_theme_stylebox_override("normal", UI.flat(DB.PAL.ink3 if on else DB.PAL.ink2, DB.PAL.gold if on else DB.PAL.ink4, 2 if on else 1, UI.R, 8))
		b.add_theme_stylebox_override("hover", UI.flat(DB.PAL.ink3, DB.PAL.gold if on else DB.PAL.bamboo_dim, 2 if on else 1, UI.R, 8))
		b.add_theme_stylebox_override("pressed", UI.flat(DB.PAL.ink4, DB.PAL.gold, 2, UI.R, 8))
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
	var bp := UI.vbox(UI.SP_S)
	var hd := UI.hbox(UI.SP_S)
	var hl := UI.vbox(0)
	hl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# 11/9 사용자: 진형 우대 삭제 —— 머리는 진형 이름만 (예전 '창병 · 유생 방어 +14%' 효과 줄과 「비늘이 서로를 가린다」 설명 줄 삭제)
	var fnr := UI.hbox(UI.SP_S)
	var fl := UI.lbl(f.n, UI.FS_LABEL, DB.PAL.paper, true)
	fl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	fnr.add_child(fl)
	fnr.add_child(_inyeon_chip())      # 11/11 인연 —— 진형 이름 옆 칩 (이어진 수 · 누르면 시트)
	if run.quest_open() and gs.can_form():      # 11/13 사용자: 험지 토벌이 눈에 안 띈다(전투 탭 아래 옅은 버튼뿐) —— 편성 화면 진형 이름 옆 칩
		fnr.add_child(_hard_chip())
	hl.add_child(fnr)
	hd.add_child(hl)
	var ab := UI.btn("자동 편성", func():
		sel = ""
		gs.act("auto_deploy"), "pri", UI.BH_S)
	ab.add_theme_font_size_override("font_size", UI.FS_BODY)
	ab.disabled = not gs.can_form()
	hd.add_child(ab)
	var cb := UI.btn("해제", func(): gs.act("clear_board"), "ghost", UI.BH_S)
	cb.add_theme_font_size_override("font_size", UI.FS_BODY)
	cb.disabled = not gs.can_form() or run.placed() == 0
	hd.add_child(cb)
	bp.add_child(hd)
	if str(f.get("full", "")) != "" and not open:
		bp.add_child(UI.lbl("%s 5칸" % f.full, UI.FS_CAP, DB.PAL.text_dim))
	var grid := GridContainer.new()
	grid.columns = 1 + DB.FORM_COLS      # 11/6 진형 4행 5열
	grid.add_theme_constant_override("h_separation", 5)
	grid.add_theme_constant_override("v_separation", UI.SP_XS if open else 5)
	if not open:      # 열린 때는 칸 이름 줄(좌익 · 좌 …)을 접어 아래 목록에 높이를 준다
		var face := UI.lbl("▲적", UI.FS_CAP, DB.PAL.danger)
		face.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		grid.add_child(face)
		for col in ["좌익", "좌", "중앙", "우", "우익"]:
			var cl := UI.lbl(col, UI.FS_CAP, DB.PAL.text_dim)
			cl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			cl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			grid.add_child(cl)
	for ri in f.grid.size():
		var ll := UI.lbl(DB.D.LINES[ri], UI.FS_CAP, DB.PAL.bamboo, true)
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
			box.compact = open
			box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			box.size_flags_vertical = Control.SIZE_EXPAND_FILL
			grid.add_child(box)
			if si >= 0:
				_boxes[si] = box
	grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	bp.add_child(grid)
	var bpp := UI.panel(bp, UI.SP_S)
	bpp.size_flags_vertical = Control.SIZE_FILL if open else Control.SIZE_EXPAND_FILL      # 11/5 사용자: 아래 탭을 닫아 생긴 공간만큼 칸을 크게
	bp.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(bpp)
	if Run.tac_on:      # 11/27 군략이 꺼지면 「군략 1 · 2 · 3단계」 칸 줄도 없다
		v.add_child(TacUI.plan_row(gs))      # 11/15 군략 —— 칸을 누르면 손패 시트

	# 아래 —— [보유 | 보급품] 나눔 탭, 그 안만 스크롤. 칸을 여기로 끌면 내린다
	var keys := Run.sort_cards(run.inv.keys())
	var n_items := 0
	for id in run.bag:
		n_items += run.bag[id]
	# 11/5 사용자: 기본 닫힌 채 —— 탭을 누르면 열리고, 열린 탭을 다시 누르면 닫힌다
	var hand := HandDrop.new()
	hand.page = self
	hand.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	var hv := UI.vbox(UI.SP_S)
	hand.add_child(hv)
	# 11/5 사용자: '손패' → '보유', 진형 탭 버튼 제거. 11/14 감사 #8-5: 닫힌 탭이 비활성처럼 보였다 —— 펼침 화살표(▴ 열기 · ▾ 닫기)
	var arrow := func(k: String) -> String: return " ▾" if seg == k else " ▴"
	var tabs := UI.segmented([["hand", "보유 %d%s" % [keys.size(), arrow.call("hand")]], ["item", "보급품 %d%s" % [n_items, arrow.call("item")]]], seg, func(k):
		var was := seg
		seg = "" if seg == k else k
		_slide_up = was == "" and seg != ""
		gs.render())
	v.add_child(hand)
	if open:
		hand.size_flags_vertical = Control.SIZE_EXPAND_FILL
		hv.size_flags_vertical = Control.SIZE_EXPAND_FILL
		var sc := UI.scroll()
		sc.custom_minimum_size.y = MIN_LOWER_H
		sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
		hv.add_child(sc)
		var lower := UI.vbox(UI.SP_S)
		lower.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sc.add_child(lower)
		match seg:
			"hand": _hand(lower, keys)
			"item": _items(lower)
		var pad := Control.new()
		pad.custom_minimum_size = Vector2(0, UI.SP_M)
		lower.add_child(pad)
		if _slide_up:      # 방금 열었다 —— 목록이 살짝 아래에서 떠오른다 (자리는 그대로라 칸 · 머리줄은 움직이지 않는다)
			_slide_up = false
			lower.modulate.a = 0.0
			(func():
				if is_instance_valid(lower) and lower.is_inside_tree():
					lower.create_tween().tween_property(lower, "modulate:a", 1.0, 0.18)
				elif is_instance_valid(lower):
					lower.modulate.a = 1.0).call_deferred()
	hv.add_child(tabs)          # 탭은 늘 맨 아래 —— 열리면 내용이 그 위에 온다
	return v


func _hand(hv: VBoxContainer, keys: Array) -> void:
	var run: Run = gs.run
	if sel != "":
		var sh := UI.hbox(UI.SP_S)
		var sl := UI.rich("[color=#D9A64B][b]%s[/b] 을(를) 골랐다 — 놓을 칸을 누른다[/color]" % DB.C[sel].name, UI.FS_BODY)
		sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		sh.add_child(sl)
		sh.add_child(UI.btn("취소", func():
			sel = ""
			gs.render(), "ghost", UI.BH_S))
		hv.add_child(sh)

	# 11/5 사용자: 손패는 높은 등급부터 (Run.sort_cards). 누르면 고르고, 고른 카드를 다시 누르면 상세. 길게 눌러 칸으로 끈다.
	# 11/14 감사 #8: 한 줄에 하나씩(높이 50) 두면 열어도 두세 장만 보였다 —— 작은 카드 격자(한 줄 6장 안팎)로
	var gr := UI.grid(HAND_TILE.x, UI.SP_XS + 2)
	for k in keys:
		var t := gs.mtile(k, run.inv[k] if run.inv[k] > 1 else -1, func(id): hand_tap(id))      # 수량은 둘 이상일 때만
		t.custom_minimum_size = HAND_TILE
		t.drag_data = {"card": k, "from": -1}
		if k == sel:
			t.mark = "sel"
		gr.add_child(t)
	hv.add_child(gr)
	if keys.is_empty():
		hv.add_child(UI.hint("보유한 카드가 없다 — 모두 편성했다."))


# ───────── 인연 (11/11) ─────────

## 칸 i 의 카드가 든 이어진 인연 수 (0 = 없음)
## 11/20 편성판에서 아이템을 가장 많이 낀 칸의 아이템 수 (1 · 2) —— 모든 칸이 같은 줄 수를 잡아 초상 · 이름 높이가 맞는다. build() 마다 다시 센다
var _gear_rows := -1
func gear_rows() -> int:
	if _gear_rows < 0:
		_gear_rows = 1
		var run: Run = gs.run
		for i in run.board.size():
			if run.board[i] != null and run.gear_of_slot(i).filter(func(x): return x != null).size() >= 2:
				_gear_rows = 2
				break
	return _gear_rows


func slot_link_lv(i: int) -> int:
	var k = gs.run.board[i]
	if k == null or not DB.inyeon_card(k):
		return 0
	return int(_link_n.get(DB.person(k), 0))


## 진형 점 그림 (11/14) —— mask(줄마다 "X." 문자열, 위가 적 쪽)를 칸 3px · 틈 1px 그림으로. 고른 진형은 금, 나머지는 대나무색
static var _glyphs := {}
static func form_glyph(mask: Array, on: bool) -> Texture2D:
	var key := "%s|%s" % ["/".join(mask), on]
	if _glyphs.has(key):
		return _glyphs[key]
	var cell := 4
	var gap := 1
	var cols := 4
	var rows := maxi(1, mask.size())
	var img := Image.create(cols * (cell + gap) - gap, rows * (cell + gap) - gap, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var col: Color = DB.PAL.gold if on else DB.PAL.bamboo
	for ri in mask.size():
		var row := str(mask[ri])
		var off := (cols - row.length()) / 2.0      # 3칸 줄은 가운데로
		for ci in row.length():
			var c: Color = col if row[ci] == "X" else Color(col, 0.18)
			var x := int(round((ci + off) * (cell + gap)))
			img.fill_rect(Rect2i(x, ri * (cell + gap), cell, cell), c)
	var t := ImageTexture.create_from_image(img)
	_glyphs[key] = t
	return t


## 진형 이름 옆 칩 —— 오늘 토벌을 험지로 (누를 때마다 보통 ↔ 험지). 꺼져 있어도 금테로 눈에 띄게, 켜지면 붉게 채운다. 누르면 무엇이 달라지는지 알림 한 줄
func _hard_chip() -> Control:
	var P := DB.PAL
	var run: Run = gs.run
	var on := run.quest_hard
	var b := TouchButton.new()
	# 11/15 사용자: "험지 토벌 활성화시 칸 밀림" —— 켜면 글이 「험지 토벌 ✕1.5」로 바뀌어 칩이 넓어지고(머리줄이 길어진다) 본문 글꼴에 없는 ✕ 는
	# 대체 글꼴로 그려져 줄 높이까지 달라질 수 있었다 → 머리줄이 커지면서 아래 편성판 칸이 밀렸다. 켜도 꺼도 글 · 폭 · 높이를 똑같이 (HARD_CHIP),
	# 배율은 누를 때 알림 한 줄에. 켜짐은 붉게 채운 바탕으로 알린다
	b.text = "험지 토벌"
	b.custom_minimum_size = HARD_CHIP      # 11/14 감사 #8-3 머리줄 버튼 높이 40 통일
	b.clip_text = true
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	b.add_theme_font_size_override("font_size", UI.FS_BODY)
	var fc: Color = P.paper if on else P.gold
	for cn in ["font_color", "font_hover_color", "font_focus_color", "font_pressed_color"]:
		b.add_theme_color_override(cn, fc)
	var sb := UI.flat(Color(P.seal, 0.55) if on else Color(P.gold, 0.10), P.seal.lightened(0.25) if on else P.gold, 1, UI.R, 0)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 3
	sb.content_margin_bottom = 3
	for st in ["normal", "hover", "pressed", "focus"]:
		b.add_theme_stylebox_override(st, sb)
	b.pressed.connect(func():
		UI.buzz()
		gs.act("set_quest_hard", [not on])
		if on:
			gs.toast("보통 토벌로 되돌렸다")
		else:
			gs.toast("험지 토벌 — 적 병력 ×%s · 이기면 %s +1" % [str(Run.QUEST_HARD_TR), run.quest_hard_reward_text()], "gold"))
	return b


## 진형 이름 옆 칩 —— 기호 + '인연' (+ 이어진 인연 수). 이어진 게 없으면 옅게. 누르면 인연 시트
func _inyeon_chip() -> Control:
	var P := DB.PAL
	var n := _links.size()
	var on := n > 0
	var b := TouchButton.new()
	b.text = "인연 %d" % n if on else "인연"
	b.custom_minimum_size = Vector2(0, UI.BH_S)      # 11/14 감사 #8-3 머리줄 버튼 높이 40 통일
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	b.add_theme_font_size_override("font_size", UI.FS_BODY)
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
	ic.position = Vector2(8, (UI.BH_S - 16) / 2.0)
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
		b.add_child(UI.empty("link", "맺어진 인연이 없다", "편성한 장수 중 같은 인연이 둘 이상이면 여기에 나온다. 카드 상세의 인연 칸에서 짝을 볼 수 있다."))      # 11/14 UI 4단계: 빈 상태 공용 부품
	var rh := InyeonUI.rule_hint()
	b.add_child(rh)


## 인연 한 장 —— 머리(이름 · n/3) + 구성원 줄
func _inyeon_block(nm: String, n: int, ctx: Dictionary, on_card: Callable) -> Control:
	var P := DB.PAL
	var v := UI.vbox(UI.SP_S)
	var hd := UI.hbox(UI.SP_S)
	var ic := Icons.View.new("link", P.yeon, 18)
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hd.add_child(ic)
	var nl := UI.lbl(nm, UI.FS_LABEL, P.yeon.lightened(0.25), true)
	nl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hd.add_child(nl)
	var lv := mini(n, DB.INYEON_MAX)
	var cl := UI.lbl("%d/%d" % [lv, DB.INYEON_MAX], UI.FS_BODY, P.gold if lv >= DB.INYEON_MAX else P.bamboo, true)
	hd.add_child(cl)
	v.add_child(hd)
	v.add_child(InyeonUI.members_row(nm, ctx, on_card))
	var fh := InyeonUI.fin_hint(nm)
	if fh != null:
		v.add_child(fh)
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
	var cols := {"유니크": 1, "고대": 2, "레어": 2, "매직": 3, "일반": 3}
	for g in DB.IGRADE_ORDER:
		var ids: Array = bk.filter(func(x): return DB.IT[x].grade == g)
		if ids.is_empty():
			continue
		var n := 0
		for id in ids:
			n += run.bag[id]
		v.add_child(UI.lbl("%s %d" % [g, n], UI.FS_CAP, Color(DB.D.IGRADE[g]).lightened(0.2), true))
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
	var mid := g == "레어" or g == "고대"
	var b := PanelContainer.new()
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.add_theme_stylebox_override("panel", UI.flat(DB.PAL.ink2, col, 2 if big else 1, 8, 6))
	b.mouse_filter = Control.MOUSE_FILTER_STOP
	var ipr := Press.new()      # 11/20 조작: '떼기'만 보던 처리기 —— 보급품 목록을 쓸면 스크롤 시작 순간 아이템 시트가 열렸다
	b.gui_input.connect(func(e):
		if ipr.feed(b, e) == Press.TAP:
			UI.buzz()
			gs._item_sheet(id))      # 누르면 아이템 시트 (유니크는 들어가는 신화 장수)
	var h := UI.hbox(UI.SP_S)
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
	var nl := UI.lbl("%s%s" % [it.name, ("  ×%d" % n) if n > 1 else ""], UI.FS_LABEL if big else (UI.FS_BODY if mid else UI.FS_CAP), col.lightened(0.2), true)
	UI.wrap_text(nl)      # 11/15 사용자: 이름이 … 으로 잘렸다 (3열 칸) —— 자르지 않고 줄을 바꾼다 (×N 이 다음 줄로)
	tv.add_child(nl)
	var et := UI.item_text(id)
	if big:
		et += "  · 신화 조합 재료" if it.use == "myth" else ""
		for k in DB.by_tier(8).filter(func(x): return Run.need_item(x) == id):
			et += "\n→ %s" % DB.C[k].name
	else:
		et = et.replace(" · ", "\n")
	var el := UI.lbl(et, UI.FS_BODY if big else UI.FS_CAP, DB.PAL.bamboo)
	UI.wrap_text(el)     # 효과를 자르지 않는다
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
	var sr := UI.hbox(UI.SP_XS)
	sr.alignment = BoxContainer.ALIGNMENT_CENTER
	var _ico := func(icon: String, col: Color, tip: String) -> Control:
		var iv := Icons.View.new(icon, col, 20.0)
		iv.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		iv.mouse_filter = Control.MOUSE_FILTER_PASS
		iv.tooltip_text = tip
		return iv
	var _num := func(t: String, col: Color) -> Control:
		var l := UI.lbl(t, UI.FS_BODY, col, true)
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
		var chip := UI.lbl(("▲ " if z == "pref" else "▼ ") + t, UI.FS_CAP, col.lightened(0.25), true)
		var pc := PanelContainer.new()
		pc.add_theme_stylebox_override("panel", UI.flat(DB.PAL.ink3, Color(0, 0, 0, 0), 0, UI.R, 4))      # 11/9 색 테두리 칩 → 먹색 칩 (선호 옥 · 어색 인장은 글자색으로만)
		pc.add_child(chip)
		zr.add_child(pc)
	b.add_child(zr)
	if cur != null:
		var cv := UI.vbox(UI.SP_S)
		cv.add_child(gs.tile(cur))
		if gs.kit_on() and Kit.on(cur):      # 11/27 강화한 칸 요약 —— 칸의 글자 표시(Q · W …)가 무엇인지 (터치에서는 여기서 본다 · 위 카드를 누르면 정보창의 다섯 줄)
			var ks = gs.kit_summary(str(cur), Kit.ups_of(run.kit, cur), true)
			if ks != null:
				cv.add_child(ks)
		var inn = Run.innate_item(cur)
		var gear := run.gear_of_slot(i)      # 11/13 아이템 칸 둘 —— [무기, 갑옷]
		var gv := UI.vbox(UI.SP_XS)      # 11/15 사용자: 장착 아이템 글이 잘렸다 —— 옆으로 둘(반 폭 · 잘림) 대신 한 줄에 하나씩 (폭 전체)
		for si in 2:
			var sl: String = ["weapon", "armor"][si]
			var it = gear[si]
			var ib := UI.btn("%s: %s%s" % [DB.ISLOT_NAME[sl], DB.IT[it].name if it != null else "비어 있음", " 🔒" if it != null and it == inn else ""], func(): item_sheet(i), "", UI.BH_S)
			ib.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			ib.disabled = it != null and it == inn      # 신화의 유니크는 뗄 수 없다
			if it != null:
				ib.add_theme_color_override("font_color", UI.item_col(it).lightened(0.25))
				ib.add_theme_color_override("font_disabled_color", UI.item_col(it).lightened(0.1))
			gv.add_child(ib)
		cv.add_child(gv)
		var iv := UI.hbox(UI.SP_S)
		var ub := UI.btn("내리기", func():
			gs.close_sheet()
			gs.act("unplace", [i]), "ghost", UI.BH_S)
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
		if j != i:
			for e in [run.equip[j], run.equip2[j]]:
				if e != null:
					used[e] = used.get(e, 0) + 1
	var b := gs.open_sheet("%s 아이템" % DB.C[k].name)
	b.add_child(UI.hint("%s 전용 아이템만 장착할 수 있다 · 무기 1칸 · 갑옷 1칸" % DB.C[k].tag))
	var inn = Run.innate_item(k)
	var order: Array = DB.IGRADE_ORDER
	for si in 2:
		var sl: String = ["weapon", "armor"][si]
		var cur = [run.equip[i], run.equip2[i]][si]
		b.add_child(UI.eyebrow(DB.ISLOT_NAME[sl]))
		if inn != null and DB.item_slot(inn) == sl:
			b.add_child(gs.item_box(inn))
			b.add_child(UI.hint("🔒 신화 장수의 전용 아이템 —— 뗄 수 없다."))
			continue
		if cur != null:
			var hr := UI.hbox(UI.SP_S)
			var cb := gs.item_box(cur)
			cb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			hr.add_child(cb)
			hr.add_child(UI.btn("해제", func():
				gs.close_sheet()
				gs.act("unequip", [i, sl]), "ghost", UI.BH_S))
			b.add_child(hr)
		var cand: Array = run.bag.keys().filter(func(id): return id != cur and DB.item_slot(id) == sl and run.can_equip(k, id) and run.bag[id] - used.get(id, 0) > 0)
		cand.sort_custom(func(x, y):
			var gx := order.find(DB.IT[x].grade)
			var gy := order.find(DB.IT[y].grade)
			if gx != gy:
				return gx < gy
			return DB.IT[x].pa + DB.IT[x].sa > DB.IT[y].pa + DB.IT[y].sa)
		if cand.is_empty():
			if cur == null:
				b.add_child(UI.hint("장착할 수 있는 %s %s가 없다." % [DB.C[k].tag, DB.ISLOT_NAME[sl]] if sl == "weapon" else "장착할 수 있는 %s %s이 없다." % [DB.C[k].tag, DB.ISLOT_NAME[sl]]))
			continue
		var f := UI.grid(170, 8)
		for id in cand:
			f.add_child(gs.item_box(id, run.bag[id] - used.get(id, 0), func():
				gs.close_sheet()
				gs.act("set_equip", [i, id])))
		b.add_child(f)


# ───────── 장수 키트 (11/27) ─────────
## 11/27 사용자: "그 드래그로 하려던 건 유닛 편성만 하려던 거고 스킬 강화는 기존 시안대로 유지" —— 편성판 아래 강화 줄(칩을 끌어 장수 위에)은 걷었다.
## 강화는 장수 정보창의 다섯 줄(GameScreen._kit_row · kit_confirm)에서. 편성 칸에는 강화한 칸 글자와 마우스 도움말만

var _boxes := {}              # 편성 칸 번호 -> SlotBox (build 때마다 다시)


## 편성 칸 도움말 (마우스를 올렸을 때) —— 키트 장수의 강화한 칸 · 아직 고를 수 있는 칸
func kit_slot_tip(i: int) -> String:
	var run: Run = gs.run
	var k = run.board[i] if i >= 0 and i < run.board.size() else null
	if k == null or not Kit.can_up(k) or not gs.kit_on():      # 강화는 신화만 —— 다른 키트 장수(불멸 · 초월 · 기인)는 도움말 없음
		return ""
	var ups := Kit.ups_of(run.kit, k)
	var lines := [str(DB.C[k].name)]
	for sl in ups:
		var tx := UI.kit_text(k, str(sl))
		if not tx.is_empty():
			lines.append("%s 강화됨 · %s —— %s" % [str(Kit.SLOT_N[str(sl)]), str(tx.up_n), str(tx.up_d)])
	if ups.size() >= Kit.MAX_UP:
		lines.append("%d칸을 모두 강화했다" % Kit.MAX_UP)
	else:
		var rest := []
		for sl in Kit.SLOTS:
			if not ups.has(sl) and not Kit.cell(k, sl).is_empty():
				rest.append("%s %s" % [str(Kit.SLOT_N[sl]), str(Kit.cell(k, sl).get("up", {}).get("n", ""))])
		lines.append("강화할 수 있는 칸 (%s %d · 장수 정보에서): %s" % [Kit.CUR_N, Kit.up_cost(run.kit, k), " · ".join(rest)])
	return "\n".join(lines)


## 편성판 한 칸 —— 누르면 칸 시트(또는 고른 카드를 놓는다), 길게 누르면 끌어서 옮기기·내리기
class SlotBox extends Control:
	const SZ := Vector2(60, 84)      # 11/6 진형 5열 —— 좁고 높게 (초상 위 · 글 아래). 11/7 66 → 60: 줄 이름 28 + 칸 5개 + 간격 · 여백이 논리 폭 400 을 넘어 9:20 휴대폰에서 편성판이 오른쪽으로 넘쳤다 (넓으면 칸은 늘어난다)
	const SZ_COMPACT := Vector2(48, 54)      # 11/14 감사 #8 —— 아래 목록을 연 때: 초상 · 이름만 (병력 · 아이템은 닫힌 때와 칸 시트에서)
	var page: DeployPage
	var slot := -1
	var compact := false
	var _pr := Press.new()       # 11/20 조작: 누름 판정은 Press 한 벌
	var _dragging := false
	var _down_fx := false        # 11/20 조작: 꾹 누르는 동안의 눌림 모양 (살짝 어둡게)
	var _drop_fx: DropFx = null  # 11/20 조작: 끄는 동안 놓을 수 있는 칸의 옅은 금 테

	var pref := false      # 11/15 이 칸의 장수가 제 병종의 선호 자리에 섰다 (DB.aff_of == "pref") —— 1시 방향 ✓ 표시

	func _ready() -> void:
		custom_minimum_size = SZ_COMPACT if compact else SZ
		mouse_filter = Control.MOUSE_FILTER_STOP if slot >= 0 else Control.MOUSE_FILTER_IGNORE
		if slot >= 0:
			var run: Run = page.gs.run
			var k = run.board[slot]
			if k != null:
				var s: Dictionary = DB.FORM[run.form].slots[slot]
				pref = DB.aff_of(DB.C[k].tag, s.line, s.side) == "pref"
			if pref:
				add_child(PrefBadge.new())

	func _gui_input(e: InputEvent) -> void:
		if slot < 0:
			return
		# 11/27 사용자: "편성 화면에서 드래그를 통해 되도록 (은근 PC 플레이 니즈가 있음)" —— 마우스는 누른 채 움직이면 바로 끈다 (터치는 그대로 꾹 눌러서)
		if not _dragging and Press.mouse_drag(e, _pr.down) and page.gs.run.board[slot] != null:
			accept_event()
			_start_drag()
			return
		var at := _pr.down
		match _pr.feed(self, e):
			Press.DOWN:
				_dragging = false
			Press.TAP:
				_set_down(false)
				if _dragging:
					return
				UI.buzz()
				# 11/11 인연 표시를 누르면 인연 시트 (11/20 조작: 28×16 표시의 누르는 범위를 6 → 10 으로 넓힘 · 누른 자리로 판정)
				if page.slot_link_lv(slot) > 0 and _yeon_rect().grow(10).has_point(at):
					page.inyeon_sheet()
				else:
					page.tap_slot(slot)
			Press.CANCEL:
				_set_down(false)        # 길게 누르기 전에 움직였다 —— 탭도 끌기도 아니다

	## 11/20 조작: 눌림 모양 —— 꾹 누르는 동안 제 그림만 살짝 어둡게
	func _set_down(on: bool) -> void:
		if _down_fx != on:
			_down_fx = on
			self_modulate = Color(0.78, 0.78, 0.78) if on else Color.WHITE

	func _process(_dt: float) -> void:
		if not _pr.held() or _dragging:
			if _down_fx:
				_set_down(false)
			return
		if not _down_fx and page.gs.run.board[slot] != null and Time.get_ticks_msec() - _pr.t0 >= 70:
			_set_down(true)
		if _pr.long_due(Press.HOLD_DRAG):
			_start_drag()

	func _start_drag() -> void:
		var k = page.gs.run.board[slot]
		_pr.reset()
		_set_down(false)
		if k == null:
			return
		_dragging = true
		UI.buzz(15)
		var pv := CardTile.new().setup(k)
		pv.modulate = Color(1, 1, 1, 0.85)
		var holder := Control.new()
		holder.add_child(pv)
		pv.position = Vector2(-CardTile.SIZE.x / 2, -CardTile.SIZE.y)      # 11/20 조작: 미리 보기를 손가락 위쪽으로 (가려지지 않게 반 칸 올림)
		force_drag({"card": k, "from": slot}, holder)

	## 11/20 조작: 끌기 피드백 —— 카드를 끄는 동안 놓을 수 있는 칸에 옅은 금 테 (끝나면 걷는다)
	func _notification(what: int) -> void:
		if what == NOTIFICATION_DRAG_BEGIN:
			var d = get_viewport().gui_get_drag_data()
			if _drop_fx == null and _can_drop_data(Vector2.ZERO, d):
				_drop_fx = DropFx.new()
				_drop_fx.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
				_drop_fx.mouse_filter = Control.MOUSE_FILTER_IGNORE
				_drop_fx.own = d.get("from", -1) == slot
				add_child(_drop_fx)
		elif what == NOTIFICATION_DRAG_END:
			if _drop_fx != null:
				_drop_fx.queue_free()
				_drop_fx = null

	## 마우스를 올렸을 때(PC) —— 키트 장수면 강화한 칸 · 고를 수 있는 칸
	func _get_tooltip(_at: Vector2) -> String:
		return page.kit_slot_tip(slot) if slot >= 0 else ""

	class DropFx extends Control:
		var own := false      # 끌려 나온 제 칸 —— 테 대신 옅게 비운 모양
		func _draw() -> void:
			var r := Rect2(Vector2.ZERO, size)
			if own:
				draw_rect(r.grow(-2), Color(DB.PAL.ink, 0.45))
				return
			draw_style_box(UI.flat(Color(DB.PAL.gold, 0.08), Color(DB.PAL.gold, 0.55), 2, 8, 0), r)

	## 11/11 인연 표시 자리 —— 칸 오른쪽 위 (초상 모서리)
	func _yeon_rect() -> Rect2:
		if pref:      # 11/15 오른쪽 위 모서리는 선호 자리 ✓ —— 인연 표시는 그 왼쪽으로
			return Rect2(maxf(1.0, size.x - 31.0 - PrefBadge.W), 3.0, 28.0, 16.0)
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
			var py := size.y * (0.42 if compact else 0.5) + 6
			draw_string(DB.title_font(24), Vector2(0, py), "＋", HORIZONTAL_ALIGNMENT_CENTER, size.x, 24, Color(DB.PAL.bamboo_dim, 0.7))
			var pn := UI.pos_name(s.line, s.col)
			var pfs := UI.fit_fs(fb, pn, UI.FS_TINY if compact else UI.FS_CAP, UI.FS_TINY, size.x - 4)
			draw_string(fb, Vector2(2, size.y - (5 if compact else 7)), pn, HORIZONTAL_ALIGNMENT_CENTER, size.x - 4, pfs, DB.PAL.text_dim)
			return
		var c: Dictionary = DB.C[k]
		if compact:      # 11/14 감사 #8 —— 아래 목록을 연 때: 초상 / 이름 (아이템은 초상 아래 두 점)
			_draw_compact(k, c, run)
			_draw_yeon(page.slot_link_lv(slot))
			_draw_kit(k, run, 10.0)
			return
		if size.x < 120:      # 11/6 5열 —— 좁은 칸: 초상 / 이름 / 병종 · 병력 / 아이템 / 진형 버프
			_draw_narrow(k, c, z, run)
			_draw_yeon(page.slot_link_lv(slot))
			_draw_kit(k, run)
			return
		# 11/5 사용자: 칸을 크게 —— [초상] 이름 / 병종 / 병력, 그 아래 아이템(가운데)
		var ith := 15.0                             # 아이템 줄
		var ph := size.y - 10 - ith
		var pr := Rect2(5, 5, minf(ph * 0.75, size.x * 0.42), ph)
		Art.draw_portrait(self, pr, k)
		var x := pr.end.x + 6
		var tw := size.x - x - 4
		var nm: String = DB.person(k) if c.tier > 2 else c.name
		var fs := UI.FS_LABEL if size.y >= 96 else UI.FS_BODY
		var tf := DB.tier_font(c.tier, fs)
		fs = UI.fit_fs(tf, nm, fs, UI.FS_TINY, tw)
		var ty := pr.position.y + minf(ph * 0.3, 22.0)
		var gap := clampf(ph * 0.26, 13.0, 20.0)
		draw_string(tf, Vector2(x, ty), nm, HORIZONTAL_ALIGNMENT_LEFT, tw, fs, DB.tier_color(k).lightened(0.2))
		draw_string(fb, Vector2(x, ty + gap), c.tag, HORIZONTAL_ALIGNMENT_LEFT, tw, UI.FS_CAP, _aff_col(z, DB.PAL.bamboo))
		draw_string(fb, Vector2(x, ty + gap * 2), Battle.num(c.tr) + "명", HORIZONTAL_ALIGNMENT_LEFT, tw, UI.FS_CAP, DB.PAL.text_dim)
		_draw_gear(run, size.y - 6, UI.FS_CAP)
		_draw_yeon(page.slot_link_lv(slot))
		_draw_kit(k, run)

	## 11/27 장수 키트 강화 표시 —— 강화한 칸의 글자(Q · W …)를 칸 색 네모로 칸 왼쪽 위에서 아래로 (MiniTile.draw_kit —— 타일과 같은 딱지).
	## 오른쪽 위는 인연 · 선호 자리 표시가 써서 왼쪽 세로줄로 (좁은 칸에서도 겹치지 않는다). 강화가 없으면 아무것도 그리지 않는다
	func _draw_kit(k: String, run: Run, box := 13.0) -> void:
		var ups := Run.Kit.ups_of(run.kit, k)
		if not ups.is_empty():
			MiniTile.draw_kit(self, ups, Vector2(4.0, 6.0 if box > 11.0 else 4.0), box, true, 2.0 if box > 11.0 else 1.0)

	## 자리 선호 · 어색에 따른 글자색 (옥 · 붉음 —— 글자용 danger)
	static func _aff_col(z: String, base: Color) -> Color:
		return DB.PAL.jade.lightened(0.15) if z == "pref" else (DB.PAL.danger if z == "bad" else base)

	## 이름 —— 칭호 없이 인물 이름 (병졸 카드는 카드 이름)
	static func _short(k: String, c: Dictionary) -> String:
		return DB.person(k) if c.tier > 2 else c.name

	func _draw_narrow(k: String, c: Dictionary, z: String, run: Run) -> void:
		var fb := DB.font_body
		var gear: Array = run.gear_of_slot(slot).filter(func(x): return x != null)
		# 11/20 폴리싱: 아이템 수(0 · 1 · 2)에 따라 초상 높이가 달라 같은 줄 칸끼리 초상 · 이름 높이가 12px 씩 어긋났다 —— 칸이 넉넉하면(104 이상) 모든 칸이 같은 줄 수(편성판에서 가장 많이 낀 칸 기준, DeployPage.gear_rows)를 잡는다
		var rows: int = page.gear_rows() if size.y >= 104.0 else maxi(1, gear.size())      # 11/15 아이템마다 한 줄 (둘이면 두 줄)
		var ith := GEAR_LH * rows
		var txt_h := 29.0
		# 11/20 역할 칩 —— 초상 위에 얹으면 턱이 가려 글 영역에 한 줄로: 초상 / 역할 / 이름 / 병종 · 병력 (다른 타일과 같은 "이름 바로 위". 이름 아래에 두는 안과 캡처로 견줘 골랐다)
		# 넣고도 초상이 30 이상일 때만, 병졸 칸도 같은 자리를 비워 높이를 맞춘다. 칩 + 병력을 한 줄로 합치는 안은 칸 폭 60 에 들어가지 않는다 (칩 37 + "8,500" 25 > 55)
		var role_row := size.y - 8 - ith - txt_h - ROLE_LH >= 30.0
		if role_row:
			txt_h += ROLE_LH
		var ph := maxf(16.0, size.y - 8 - ith - txt_h)
		var pw := minf(size.x - 8, ph * 1.05)
		var pr := Rect2((size.x - pw) / 2, 4, pw, ph)
		Art.draw_portrait(self, pr, k)
		var nm := _short(k, c)
		var tf := DB.tier_font(c.tier, UI.FS_BODY)
		var fs := UI.fit_fs(tf, nm, UI.FS_BODY, UI.FS_TINY, size.x - 6)
		var y := pr.end.y + 14      # 11/20 13 → 14: 이름 윗머리가 초상 아랫변에 닿았다
		if role_row:
			CardTile.draw_role_chip(self, k, Vector2(3, pr.end.y + 2), UI.FS_TINY, size.x - 6, true)
			y += ROLE_LH
		draw_string(tf, Vector2(3, y), nm, HORIZONTAL_ALIGNMENT_CENTER, size.x - 6, fs, DB.tier_color(k).lightened(0.2))
		var info := "%s %s" % [c.tag, Battle.num(c.tr)]
		var ifs := UI.fit_fs(fb, info, UI.FS_CAP, UI.FS_TINY, size.x - 4)
		draw_string(fb, Vector2(2, y + 13), info, HORIZONTAL_ALIGNMENT_CENTER, size.x - 4, ifs, _aff_col(z, DB.PAL.text_dim))
		if gear.is_empty():
			_draw_gear(run, size.y - 5, UI.FS_TINY)      # 빈 칸 둘 (테만 있는 네모)
		else:
			_draw_gear_rows(gear, size.y - 5 - GEAR_LH * (rows - gear.size()))      # 11/20 하나뿐이면 윗줄에 (글 덩어리가 이어지게)

	## 11/15 사용자: "편성 장착 아이템 텍스트 짤림" —— 좁은 칸에서는 양 끝 네모 사이 한 줄에 「이름+1」을 넣느라 다섯 글자 이름이 … 으로 잘렸다.
	## 아이템마다 한 줄씩 칸 폭 전체에 (무기 위 · 갑옷 아래, 등급색). 그래도 넘치면 글씨를 한 단계씩 줄이고(8 까지) 마지막에만 …
	const GEAR_LH := 12.0
	const ROLE_LH := 17.0      # 역할 칩 한 줄 (칩 15 + 틈 2)
	func _draw_gear_rows(gear: Array, bottom: float) -> void:
		var w := size.x - 4.0
		var y := bottom - GEAR_LH * (gear.size() - 1)
		for it in gear:
			var nm := str(DB.IT[it].name)
			var fs := UI.fit_fs(DB.font_body, nm, UI.FS_TINY, 8, w)
			draw_string(DB.font_body, Vector2(2, y), UI.ellipsize(DB.font_body, nm, fs, w), HORIZONTAL_ALIGNMENT_CENTER, w, fs, UI.item_col(it).lightened(0.15))
			y += GEAR_LH

	## 작게 (아래 목록을 연 때) —— 초상이 칸을 채우고 아래에 이름 한 줄. 아이템은 초상 아래 모서리 두 점
	func _draw_compact(k: String, c: Dictionary, run: Run) -> void:
		var nh := float(UI.FS_CAP) + 4.0
		var pr := Rect2(3, 3, size.x - 6, maxf(12.0, size.y - 6 - nh))
		Art.draw_portrait(self, pr, k)
		var nm := _short(k, c)
		var tf := DB.tier_font(c.tier, UI.FS_CAP)
		var fs := UI.fit_fs(tf, nm, UI.FS_CAP, UI.FS_TINY, size.x - 4)
		draw_string(tf, Vector2(2, size.y - 5), nm, HORIZONTAL_ALIGNMENT_CENTER, size.x - 4, fs, DB.tier_color(k).lightened(0.2))
		var g := run.gear_of_slot(slot)
		for si in 2:
			if g[si] == null:
				continue
			var q := Rect2(pr.position.x + 2.0 if si == 0 else pr.end.x - 9.0, pr.end.y - 9.0, 7, 7)
			draw_rect(q.grow(1), Color(DB.PAL.ink, 0.8))
			draw_rect(q, UI.item_col(g[si]))


	## 11/13 아이템 줄 —— 칸이 둘(무기 · 갑옷): 양 끝에 등급색 네모 둘(빈 칸은 테만), 가운데에 이름(무기 먼저, 둘이면 뒤에 +1).
	## 11/14 감사 #8: 「빈 슬롯」 글자는 뺐다 (빈 칸은 테만 있는 네모로 안다) · 이름은 칸에 맞춰 … 으로 줄인다
	func _draw_gear(run: Run, y: float, fs: int) -> void:
		var g := run.gear_of_slot(slot)
		var n := (1 if g[0] != null else 0) + (1 if g[1] != null else 0)
		var it = g[0] if g[0] != null else g[1]
		var pip := 6.0
		if it != null:
			var tw := size.x - 8 - pip * 2
			var full := str(DB.IT[it].name) + ((" · " + str(DB.IT[g[1]].name)) if n == 2 else "")      # 11/15 「+1」 대신 두 이름 모두 —— 넘치면 글씨를 줄이고 마지막에만 …
			var gfs := UI.fit_fs(DB.font_body, full, fs, 8, tw)
			var itxt := UI.ellipsize(DB.font_body, full, gfs, tw)
			draw_string(DB.font_body, Vector2(4 + pip, y), itxt, HORIZONTAL_ALIGNMENT_CENTER, tw, gfs, UI.item_col(it))
		for si in 2:
			var r := Rect2(3.0 if si == 0 else size.x - 3.0 - pip, y - pip, pip, pip)
			if g[si] != null:
				draw_rect(r, UI.item_col(g[si]))
			else:
				draw_rect(r, Color(DB.PAL.bamboo_dim, 0.5), false, 1.0)


## 선호 자리 표시 (11/15 사용자: "병종이 선호 위치에 있다면 카드 1시 방향에 v자 체크 모양이나 활성화 되었다는 이펙트") ——
## 칸 오른쪽 위 모서리에 옥빛 동그라미 ✓, 그 뒤로 은은하게 숨 쉬는 빛. 칸 본체(초상)는 다시 그리지 않게 작은 덧칸으로 (빛은 modulate 만 바꾼다)
class PrefBadge extends Control:
	const W := 18.0

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		anchor_left = 1.0
		anchor_right = 1.0
		offset_left = -W - 1.0
		offset_right = -1.0
		offset_top = 1.0
		offset_bottom = W + 1.0
		var glow := Control.new()
		glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
		glow.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		glow.draw.connect(func():
			var c := glow.size / 2.0
			for i in 4:
				glow.draw_circle(c, W * 0.5 + 2.0 + i * 2.0, Color(DB.PAL.jade.lightened(0.3), 0.20 - i * 0.04)))
		add_child(glow)
		var mark := Control.new()
		mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
		mark.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		mark.draw.connect(func():
			var c := mark.size / 2.0
			mark.draw_circle(c, W * 0.5, Color("#0E1A16"))
			mark.draw_circle(c, W * 0.5 - 1.5, DB.PAL.jade.lightened(0.1))
			var a := c + Vector2(-4.0, 0.2)
			var m := c + Vector2(-1.2, 3.2)
			var e := c + Vector2(4.4, -3.4)
			mark.draw_polyline(PackedVector2Array([a, m, e]), Color("#0E1A16"), 2.2, true))
		add_child(mark)
		glow.ready.connect(func():
			var tw := glow.create_tween().set_loops()
			tw.tween_property(glow, "modulate:a", 0.25, 0.9).set_trans(Tween.TRANS_SINE)
			tw.tween_property(glow, "modulate:a", 1.0, 0.9).set_trans(Tween.TRANS_SINE))


## 손패 상자 —— 칸에서 끌어 오면 내린다
class HandDrop extends PanelContainer:
	var page: DeployPage

	func _can_drop_data(_p: Vector2, data) -> bool:
		return data is Dictionary and data.has("from") and data.from >= 0

	func _drop_data(_p: Vector2, data) -> void:
		page.drop_hand(data)
