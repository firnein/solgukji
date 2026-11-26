extends Node
## 11/27 장수 키트 Q · W · E · R · P 화면 캡처 + 화면 흐름 점검 (새 방식 —— 칸마다 고유 강화 하나 · 장수당 2칸 · 되돌릴 수 없다)
## 창이 있어야 캡처가 된다 (화면 없이 돌리면 흐름만 점검하고 캡처는 건너뛴다):
##   godot --path . --resolution 540x1200 res://tests/kit_shots.tscn -- --out=폴더 [--seed=3] [--play=9] [--card=c177]
## ① 편성 화면 강화 줄 —— 칩을 끌어 장수 위에 올린 순간 (놓을 수 있는 장수 밝게 · 나머지 어둡게 · 미리보기)   ② 놓으면 확인 창 → 확인하면 강화
## ③ 장수 정보창 다섯 줄 (강화 효과가 늘 보인다 · 강화됨 · 강화 버튼 · 2칸을 채우면 나머지 흐리게)   ④ 상대 정보 · 군웅 줄의 강화 표시
## 실패가 있으면 끝에 「실패 N」.

const Kit := preload("res://scripts/kit.gd")

var out := "user://"
var fails := 0
var headless := false
var args := {}


func ok(cond: bool, what: String) -> void:
	if not cond:
		fails += 1
	print("%s · %s" % ["통과" if cond else "실패", what])


func _ready() -> void:
	for s in OS.get_cmdline_user_args():
		var kv := s.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	out = str(args.get("out", "user://"))
	headless = DisplayServer.get_name() == "headless"
	PlayLog.enabled = false
	Run.dev_immortal = true
	Run.dev_nosave = true
	var gs: GameScreen = load("res://scenes/game.tscn").instantiate()
	add_child(gs)
	await _wait(1.2)
	gs._new_game()
	await _wait(0.4)
	gs._coach_finish()
	gs.forge_tree.clear()

	var card := str(args.get("card", "c177"))
	var card2 := ""      # 편성에 올릴 둘째 키트 장수 (2칸을 다 채운 장수)
	for k in DB.C:
		if Kit.on(k) and k != card:
			card2 = k
			break
	var r := Run.new()
	r.new_game(int(args.get("seed", "3")))
	for i in int(args.get("play", "9")):
		r.dev_autoplay()
	# 편성에 키트 장수 둘 —— card 는 Q 하나만 강화(둘째 값 6), card2 는 2칸을 다 채웠다. 전공 7
	var slots := []
	for i in 9:
		if r.board[i] != null:
			slots.append(i)
	slots.sort_custom(func(a, b): return int(DB.C[r.board[a]].tier) < int(DB.C[r.board[b]].tier))
	r.board[slots[0]] = card
	r.board[slots[1]] = card2
	r.kit = Kit.norm({card: ["q"], card2: ["w", "p"]})
	r.merit = 7
	r.grain = maxi(r.grain, 12)
	r.auto_draw()      # 기본패를 미리 받아 둔다 —— 화면에 징집 공개 연출이 겹치지 않게
	gs.run = r
	gs.deploy.seg = ""
	gs.go("deploy")
	await _wait(0.6)
	_clean(gs)
	await _wait(0.3)
	ok(gs._merit_box.visible and gs._merit_lbl.text == "7" and gs.kit_on(), "머리띠에 전공 7 (보임 %s · 글 %s)" % [str(gs._merit_box.visible), gs._merit_lbl.text])

	# ── ① 편성 화면 강화 줄 · 칩 끌기
	var dp: DeployPage = gs.deploy
	var row := _find(gs, "KitRow")
	var chips := _all(row, func(n): return n is DeployPage.KitChip)
	ok(row != null and chips.size() == 5 and chips.map(func(c): return c.kslot) == Kit.SLOTS, "편성 화면 강화 줄 —— 칩 다섯 (Q · W · E · R · P)")
	ok(chips.filter(func(c): return c.usable).map(func(c): return c.kslot) == ["w", "e", "r", "p"], "Q 칩은 흐리게 (놓을 장수가 없다 —— %s 는 Q 를 이미 강화 · %s 는 2칸을 다 채움)" % [DB.person(card), DB.person(card2)])
	var i1: int = r.board.find(card)
	var i2: int = r.board.find(card2)
	var i3 := -1      # 키트가 아닌 장수가 선 칸
	for i in 9:
		if r.board[i] != null and not Kit.on(r.board[i]):
			i3 = i
			break
	ok(dp.kit_drop_block(i1, "w") == "" and dp.kit_drop_block(i1, "q").contains("이미 강화") and dp.kit_drop_block(i2, "e").contains("모두 강화") and dp.kit_drop_block(i3, "w").contains("신화"),
		"놓을 수 있나 —— %s W 됨 · Q 「%s」 · %s 「%s」 · 키트 아님 「%s」" % [DB.person(card), dp.kit_drop_block(i1, "q"), DB.person(card2), dp.kit_drop_block(i2, "e"), dp.kit_drop_block(i3, "w")])
	r.merit = 5
	ok(dp.kit_drop_block(i1, "w").contains("부족"), "전공이 모자라면 —— 「%s」" % dp.kit_drop_block(i1, "w"))
	r.merit = 7
	ok(chips[1]._get_tooltip(Vector2.ZERO).contains(str(Kit.cell(card, "w").up.n)) and dp.kit_slot_tip(i1).contains("강화됨") and dp.kit_slot_tip(i2).contains("모두 강화") and dp.kit_slot_tip(i3) == "",
		"마우스 도움말 —— 칩: 장수마다 기술 → 강화 이름 · 칸: 강화한 칸 / 고를 수 있는 칸")
	# 끌기 자료 —— 칩이 주는 것 · 칸이 받는 것
	var b1: DeployPage.SlotBox = dp._boxes[i1]
	var b2: DeployPage.SlotBox = dp._boxes[i2]
	var b3: DeployPage.SlotBox = dp._boxes[i3]
	ok(b1._can_drop_data(Vector2.ZERO, {"kit": "w"}) and not b1._can_drop_data(Vector2.ZERO, {"kit": "q"}) and not b2._can_drop_data(Vector2.ZERO, {"kit": "w"}) and not b3._can_drop_data(Vector2.ZERO, {"kit": "w"}),
		"칸이 받는 끌기 —— 놓을 수 있는 장수만")
	ok(b1._can_drop_data(Vector2.ZERO, {"card": card2, "from": i2}), "카드 끌기(자리 바꾸기)는 예전 그대로 받는다")
	# 끄는 중의 화면 (점검용 —— 진짜 끌기 없이 덧층을 켠다): W 칩을 끌어 관우 위에
	var layer: DeployPage.KitDragLayer = dp.kit_drag_start("w", true)
	await _wait(0.2)
	var fx := _all(gs, func(n): return n is DeployPage.SlotBox.KitFx)
	ok(fx.size() == dp._boxes.size() and fx.filter(func(n): return n.ok).size() == 1 and b1._kit_fx != null and b1._kit_fx.ok, "끄는 동안 —— 놓을 수 있는 칸 1개만 밝게, 나머지 %d칸은 어둡게" % (fx.size() - 1))
	layer.point(b1.get_global_rect().get_center())
	await _wait(0.3)
	var bal := layer._balloon
	var bt := _texts(bal)
	ok(bal != null and bt.contains(str(Kit.cell(card, "w").n)) and bt.contains(str(Kit.cell(card, "w").up.n)) and bt.contains(str(Kit.cell(card, "w").up.d).substr(0, 6)) and _has_merit_icon(bal),
		"장수 위에 올리면 미리보기 —— 기술 이름 → 강화 이름 · 효과 · 값")
	ok(bal != null and bal.get_global_rect().position.x >= 0.0 and bal.get_global_rect().end.x <= gs.size.x + 0.5 and not bal.get_global_rect().intersects(b1.get_global_rect()), "미리보기가 화면 안 · 그 칸을 가리지 않는다 %s" % (str(bal.get_global_rect()) if bal != null else ""))
	await _shot("kit2_1_drag_hover")
	layer.point(b2.get_global_rect().get_center())
	await _wait(0.3)
	bal = layer._balloon
	ok(bal != null and _texts(bal).contains("이미 강화") and not _has_merit_icon(bal), "못 놓는 장수 위 —— 까닭 (%s 는 W 를 이미 강화)" % DB.person(card2))
	await _shot("kit2_1b_drag_blocked")
	layer.point(b3.get_global_rect().get_center())
	await _wait(0.2)
	ok(_texts(layer._balloon).contains("신화"), "키트가 아닌 장수 위 —— 까닭")
	layer.point(Vector2(-50, -50))
	await _wait(0.1)
	ok(layer._balloon == null, "칸 밖 —— 미리보기 없음")
	layer.finish()
	await _wait(0.2)
	ok(_all(gs, func(n): return n is DeployPage.SlotBox.KitFx).is_empty() and not is_instance_valid(dp._kit_layer), "끌기가 끝나면 칸 표시 · 덧층이 걷힌다")
	# 놓았다 → 확인 창 → 「그대로 둔다」
	b1._drop_data(Vector2.ZERO, {"kit": "w"})
	await _wait(0.8)
	var yes0 := _find(gs._sheet_body, "KitYes") as Button
	ok(gs.sheet_open() and yes0 != null and not yes0.disabled and _texts(gs._sheet_body).contains("되돌릴 수 없습니다"), "놓으면 확인 창")
	for bb in _all(gs._sheet_body, func(n): return n is Button and (n as Button).text == "그대로 둔다"):
		(bb as Button).pressed.emit()
	await _wait(0.5)
	ok(r.kit[card] == ["q"] and r.merit == 7, "「그대로 둔다」 —— 아무것도 바뀌지 않는다")
	# 진짜 끌기 —— 입력 사건으로 (마우스): W 칩을 누른 채 관우 칸까지 움직이고 뗀다
	await _real_drag(gs, chips[1], b1, false)
	ok(gs.sheet_open() and _find(gs._sheet_body, "KitYes") != null and _texts(gs._sheet_body).contains(str(Kit.cell(card, "w").up.n)), "진짜 끌기(마우스) —— W 칩을 관우 위에 놓으면 확인 창")
	gs.close_sheet()
	await _wait(0.5)
	# 진짜 끌기 (터치) —— 못 놓는 장수(여포 · W 이미 강화) 위에서 떼면 확인 창 없이 까닭 알림
	for c in gs._toast_box.get_children():
		c.queue_free()
	await _wait(0.1)
	await _real_drag(gs, chips[1], b2, true)
	ok(not gs.sheet_open() and _texts(gs._toast_box).contains("이미 강화"), "진짜 끌기(터치) —— 못 놓는 장수 위에서 떼면 창은 안 뜨고 까닭 알림 「%s」" % _texts(gs._toast_box).strip_edges().get_slice("
", 0))
	await _real_drag(gs, chips[2], b1, true)
	ok(gs.sheet_open() and _texts(gs._sheet_body).contains(str(Kit.cell(card, "e").up.n)), "진짜 끌기(터치) —— E 칩을 관우 위에 놓으면 확인 창")
	gs.close_sheet()
	await _wait(0.5)
	# 칩을 누르면(끌지 않고) 그 칸 시트 —— 입력 사건으로 눌렀다 뗀다
	await _real_tap(gs, chips[3])
	ok(gs.sheet_open() and _texts(gs._sheet_body).contains(str(Kit.cell(card, "r").up.n)), "칩을 누르면(끌지 않고) 그 칸 시트가 열린다 (R)")
	gs.close_sheet()
	await _wait(0.5)
	# 칩을 누르면(끌지 않고) 그 칸 시트
	dp.kit_chip_sheet("w")
	await _wait(0.7)
	var cs := _texts(gs._sheet_body)
	ok(cs.contains(DB.person(card)) and cs.contains(DB.person(card2)) and cs.contains("강화됨") and _buttons(gs._sheet_body).size() == 1, "칩을 누르면 그 칸 시트 —— 장수마다 강화 효과 · %s 는 [강화] · %s 는 강화됨" % [DB.person(card), DB.person(card2)])
	ok(_overflow(gs, gs._sheet_body) == "", "칩 시트가 시트 폭 안에 있다 %s" % _overflow(gs, gs._sheet_body))
	if args.has("extra"):
		await _shot("kit2_x_chip_sheet")
	gs.close_sheet()
	await _wait(0.4)

	# ── ③ 장수 정보창
	gs.card_info(card)
	await _wait(0.9)
	var sec := _find(gs._sheet_body, "KitSection")
	ok(sec != null, "정보창에 「장수 키트」 묶음")
	ok(_count(sec, func(n): return n is SheetStyle.SlotBadge) == 5, "칸 딱지 다섯 (Q · W · E · R · P)")
	var rows := _rows(sec)
	ok(rows.size() == 5 and rows.filter(func(n): return bool(n.get_meta("kit_up"))).map(func(n): return str(n.get_meta("kit_slot"))) == ["q"], "다섯 줄 · 강화됨은 Q 하나")
	var texts := _texts(sec)
	var all_up := Kit.SLOTS.all(func(sl): return texts.contains(str(Kit.cell(card, sl).up.n)) and texts.contains(str(Kit.cell(card, sl).n)))
	ok(all_up, "다섯 줄 모두 기술 이름 · 강화 이름이 보인다 (강화 전에도)")
	var btns := _buttons(sec)
	ok(btns.size() == 4 and btns.all(func(b): return not b.disabled), "강화 버튼 4 (안 한 칸마다) · 전공 7 ≥ 둘째 값 6 이라 모두 켜짐 —— %d" % btns.size())
	ok(_find(gs._sheet_body, "SkillsSection") == null and _count(gs._sheet_body, func(n): return n is TraitBoard and n.visible) == 0, "일반 기술 묶음 · 특기판은 그리지 않는다")
	ok(_overflow(gs, sec) == "", "키트 묶음이 시트 폭 안에 있다 %s" % _overflow(gs, sec))
	await _shot("kit2_3_card_info")
	gs._sheet_scroll.scroll_vertical = 330
	await _wait(0.4)
	await _shot("kit2_3b_card_info_scrolled")

	# 정보창의 [강화] → 확인 창 → 「그대로 둔다」 는 정보창으로
	btns[0].pressed.emit()      # W
	await _wait(0.8)
	var yes := _find(gs._sheet_body, "KitYes") as Button
	ok(yes != null and not yes.disabled and _texts(gs._sheet_body).contains("되돌릴 수 없습니다") and _texts(gs._sheet_body).contains(str(Kit.cell(card, "w").up.n)), "정보창 [강화] → 확인 창 (강화 이름 · 되돌릴 수 없습니다)")
	ok(_overflow(gs, gs._sheet_body) == "", "확인 창이 시트 폭 안에 있다 %s" % _overflow(gs, gs._sheet_body))
	await _shot("kit2_2_confirm")
	yes.pressed.emit()
	await _wait(0.9)
	ok(r.kit[card] == ["q", "w"] and r.merit == 1, "확인 → W 강화 · 전공 7 → %d · %s" % [r.merit, str(r.kit[card])])
	sec = _find(gs._sheet_body, "KitSection")
	ok(sec != null and _buttons(sec).is_empty() and _texts(sec).contains("모두 강화했다"), "정보창으로 돌아온다 —— 2칸을 채워 버튼이 없고 「모두 강화했다」")
	ok(_rows(sec).filter(func(n): return bool(n.get_meta("kit_up"))).size() == 2, "강화됨 두 줄")
	await _shot("kit2_3c_card_info_full")

	# 가지지 않은 키트 장수 —— 보기만
	var other := ""
	for k in DB.C:
		if Kit.on(k) and r.have(k) <= 0:
			other = k
			break
	gs.card_info(other)
	await _wait(0.9)
	sec = _find(gs._sheet_body, "KitSection")
	ok(sec != null and _buttons(sec).is_empty() and _rows(sec).size() == 5 and _find(sec, "KitRule") == null, "가지지 않은 %s —— 다섯 줄 · 강화 효과는 보이고 버튼은 없다" % DB.C[other].name)
	# 키트가 아닌 장수는 예전 그대로
	var plain := ""
	for k in DB.by_tier(7):
		if not Kit.on(k) and not DB.is_foe(k) and DB.has_ult(k):
			plain = k
			break
	gs.card_info(plain)
	await _wait(0.8)
	ok(_find(gs._sheet_body, "KitSection") == null and _find(gs._sheet_body, "SkillsSection") != null, "키트가 아닌 %s —— 예전 그대로 (일반 기술 묶음 · 키트 묶음 없음)" % DB.C[plain].name)
	gs.close_sheet()
	await _wait(0.4)
	# ── ② 끌어 놓기 → 확인 → 강화 (새로 맞춘 상태에서: 전공 6 · E 를 놓는다)
	r.kit = Kit.norm({card: ["q"], card2: ["w", "p"]})
	r.merit = 6
	gs.render()
	await _wait(0.5)
	(dp._boxes[r.board.find(card)] as DeployPage.SlotBox)._drop_data(Vector2.ZERO, {"kit": "e"})
	await _wait(0.8)
	var yes2 := _find(gs._sheet_body, "KitYes") as Button
	ok(yes2 != null and not yes2.disabled, "E 칩을 놓았다 —— 확인 창")
	if yes2 != null:
		yes2.pressed.emit()
	await _wait(0.9)
	ok(r.kit[card] == ["q", "e"] and r.merit == 0, "확인 → E 강화 · 전공 6 → %d · %s" % [r.merit, str(r.kit.get(card))])
	await _wait(0.4)
	ok(not gs.sheet_open() or gs._sheet_closing, "편성 화면에서 한 강화는 확인 뒤 시트가 닫힌다")
	var chips2 := _all(_find(gs, "KitRow"), func(n): return n is DeployPage.KitChip)
	ok(chips2.size() == 5 and chips2.all(func(c): return not c.usable), "두 장수 모두 2칸을 채웠다 —— 칩이 모두 흐리다")
	# 키트 장수가 편성에 없으면 접힌 한 줄
	for i in 9:
		if r.board[i] != null and Kit.on(r.board[i]):
			r.board[i] = null
	gs.render()
	await _wait(0.5)
	var row2 := _find(gs, "KitRow")
	ok(row2 != null and _all(row2, func(n): return n is DeployPage.KitChip).is_empty() and _has_merit_icon(row2), "키트 장수가 편성에 없으면 접힌 한 줄 (전공만)")
	if args.has("extra"):
		_clean(gs)
		await _wait(0.3)
		await _shot("kit2_x_row_folded")
	print("실패 %d" % fails)
	get_tree().quit(1 if fails > 0 else 0)


func _find(n: Node, nm: String) -> Node:
	if n == null:
		return null
	if n.name == nm and not n.is_queued_for_deletion():
		return n
	for c in n.get_children():
		var f := _find(c, nm)
		if f != null:
			return f
	return null


func _count(n: Node, pred: Callable) -> int:
	if n == null or n.is_queued_for_deletion():
		return 0
	var s := 1 if pred.call(n) else 0
	for c in n.get_children():
		s += _count(c, pred)
	return s


## 묶음 안에서 조건에 맞는 노드들 (화면 차례대로)
func _all(n: Node, pred: Callable) -> Array:
	var o := []
	if n == null or n.is_queued_for_deletion():
		return o
	if pred.call(n):
		o.append(n)
	for c in n.get_children():
		o.append_array(_all(c, pred))
	return o


## 묶음 안의 키트 줄 (kit_slot 메타가 붙은 판) —— 화면 차례대로
func _rows(n: Node) -> Array:
	var o := []
	if n == null or n.is_queued_for_deletion():
		return o
	if n.has_meta("kit_slot"):
		o.append(n)
	for c in n.get_children():
		o.append_array(_rows(c))
	return o


## 묶음 안의 글을 모두 이어 붙인다 (Label · RichTextLabel · 단어 잇기 문자는 뺀다)
func _texts(n: Node) -> String:
	if n == null or n.is_queued_for_deletion():
		return ""
	var s := ""
	if n is Label:
		s += (n as Label).text + "\n"
	elif n is RichTextLabel:
		s += (n as RichTextLabel).get_parsed_text() + "\n"
	for c in n.get_children():
		s += _texts(c)
	return s.replace(UI.WJ, "")


## 전공 기호가 든 버튼들 (강화 버튼)
func _buttons(n: Node) -> Array:
	var o := []
	if n == null or n.is_queued_for_deletion():
		return o
	if n is Button and _has_merit_icon(n):
		o.append(n)
	for c in n.get_children():
		o.append_array(_buttons(c))
	return o


func _has_merit_icon(n: Node) -> bool:
	if n is Icons.View and (n as Icons.View).icon == "merit":
		return true
	for c in n.get_children():
		if _has_merit_icon(c):
			return true
	return false


## 묶음 안에서 시트 오른쪽 끝을 넘는 것이 있으면 그 이름 · 넘친 폭
func _overflow(gs: GameScreen, n: Node) -> String:
	if n == null:
		return ""
	var lim: float = gs._sheet_body.get_global_rect().end.x + 0.5
	var todo := [n]
	while not todo.is_empty():
		var c: Node = todo.pop_back()
		if c is Control and (c as Control).is_visible_in_tree() and (c as Control).get_global_rect().end.x > lim:
			return "(%s +%.0f)" % [c.get_class(), (c as Control).get_global_rect().end.x - lim]
		todo.append_array(c.get_children())
	return ""


## 진짜 입력 사건으로 끈다 —— from 가운데를 누르고 to 가운데까지 움직인 뒤 뗀다. 끄는 도중(to 위)에 덧층 · 풍선 · 칸 표시가 켜졌는지도 본다
var _drag_seen := {}
func _real_drag(gs: GameScreen, from: Control, to: Control, touch: bool) -> void:
	var xf := get_viewport().get_final_transform()      # 화면 좌표 → 창 좌표 (입력 사건은 창 좌표로 넣는다)
	var a: Vector2 = xf * from.get_global_rect().get_center()
	var b: Vector2 = xf * to.get_global_rect().get_center()
	_send(a, true, touch, Vector2.ZERO)
	await _wait(0.05)
	var prev := a
	for i in 9:
		var p := a.lerp(b, float(i + 1) / 9.0)
		_send(p, null, touch, p - prev)
		prev = p
		await _wait(0.03)
	await _wait(0.15)
	var dp: DeployPage = gs.deploy
	_drag_seen = {"dragging": get_viewport().gui_is_dragging(), "layer": is_instance_valid(dp._kit_layer),
		"balloon": is_instance_valid(dp._kit_layer) and is_instance_valid(dp._kit_layer._balloon), "fx": _all(gs, func(n): return n is DeployPage.SlotBox.KitFx).size()}
	ok(_drag_seen.dragging and _drag_seen.layer and _drag_seen.balloon and _drag_seen.fx == dp._boxes.size(), "  끄는 중(%s) —— 끌기 %s · 덧층 %s · 풍선 %s · 칸 표시 %d" % ["터치" if touch else "마우스", str(_drag_seen.dragging), str(_drag_seen.layer), str(_drag_seen.balloon), int(_drag_seen.fx)])
	_send(b, false, touch, Vector2.ZERO)
	await _wait(0.7)


func _real_tap(_gs: GameScreen, on: Control) -> void:
	var p: Vector2 = get_viewport().get_final_transform() * on.get_global_rect().get_center()
	_send(p, true, false, Vector2.ZERO)
	await _wait(0.08)
	_send(p, false, false, Vector2.ZERO)
	await _wait(0.7)


## 입력 사건 하나 —— pressed: true 누름 · false 뗌 · null 움직임. touch 면 화면 터치 사건 (마우스로 바뀌어 들어간다)
func _send(p: Vector2, pressed, touch: bool, rel: Vector2) -> void:
	if touch:
		if pressed == null:
			var d := InputEventScreenDrag.new()
			d.index = 0
			d.position = p
			d.relative = rel
			Input.parse_input_event(d)
		else:
			var t := InputEventScreenTouch.new()
			t.index = 0
			t.position = p
			t.pressed = pressed
			Input.parse_input_event(t)
		return
	if pressed == null:
		var m := InputEventMouseMotion.new()
		m.position = p
		m.global_position = p
		m.relative = rel
		m.button_mask = MOUSE_BUTTON_MASK_LEFT
		Input.parse_input_event(m)
	else:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_LEFT
		e.pressed = pressed
		e.position = p
		e.global_position = p
		e.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
		Input.parse_input_event(e)


func _clean(gs: GameScreen) -> void:
	gs.close_sheet()
	gs._bands.clear()
	gs._hide_band()
	for c in gs._toast_box.get_children():
		c.queue_free()


func _wait(s: float) -> void:
	await get_tree().create_timer(s).timeout


func _shot(name: String) -> void:
	if headless:
		return
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [out, name])
