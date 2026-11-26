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
