extends Node
## 11/27 "강화 시도 페이지 폴리싱" —— 강화 확인 창 · 장수 정보창 키트 줄 캡처 + 흐름 점검
##   godot --path . --resolution 540x1200 res://tests/kup_shots.tscn -- --out=폴더 [--tag=kup2] [--card=c177]
## 첫 강화 · 마지막 칸 강화 · 전공 모자람 · 성공 직후(번쩍) · 정보창으로 돌아온 직후 · 정보창 0/1/2칸. 실패가 있으면 끝에 「실패 N」.

const Kit := preload("res://scripts/kit.gd")

var out := "user://"
var tag := "kup2"
var fails := 0
var headless := false


func ok(cond: bool, what: String) -> void:
	if not cond:
		fails += 1
	print("%s · %s" % ["통과" if cond else "실패", what])


func _ready() -> void:
	var args := {}
	for s in OS.get_cmdline_user_args():
		var kv := s.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	out = str(args.get("out", "user://"))
	tag = str(args.get("tag", "kup2"))
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
	var r := Run.new()
	r.new_game(3)
	for i in 9:
		r.dev_autoplay()
	for i in 9:
		if r.board[i] != null:
			r.board[i] = card
			break
	r.grain = maxi(r.grain, 12)
	r.auto_draw()
	gs.run = r
	gs.deploy.seg = ""
	gs.go("deploy")
	await _wait(0.6)
	_clean(gs)

	# 정보창 0칸 —— 전공 9
	r.kit = {}
	r.merit = 9
	gs.card_info(card)
	await _wait(0.9)
	var sec := _find(gs._sheet_body, "KitSection")
	ok(sec != null and _find(sec, "KitPips") == null and _find(sec, "KitRuleRow") != null, "정보창 머리 —— 강화 칸 현황 줄")
	ok(headless or _bottom(sec) <= gs._sheet_scroll.get_global_rect().end.y + 0.5, "정보창 0칸 —— P 까지 스크롤 없이 (끝 %.0f · 창 %.0f)" % [_bottom(sec), gs._sheet_scroll.get_global_rect().end.y])
	await _shot("info_up0")

	# ① 첫 강화 확인 창 (W)
	gs.kit_confirm(card, "w", true)
	await _wait(0.8)
	var yes := _find(gs._sheet_body, "KitYes") as Button
	var tx := _texts(gs._sheet_body)
	ok(yes != null and not yes.disabled and tx.contains("되돌릴 수 없습니다") and tx.contains("+ " + str(Kit.cell(card, "w").up.n)) and tx.contains("2칸 중 1번째") and tx.contains("남음"), "첫 강화 —— + 강화 이름 · 2칸 중 1번째 · 전공 → 남음")
	ok(_overflow(gs, gs._sheet_body) == "", "확인 창이 시트 폭 안에 %s" % _overflow(gs, gs._sheet_body))
	ok(headless or gs._sheet.get_global_rect().position.y > gs.size.y * 0.3, "시트 높이는 내용만큼 (위 %.0f)" % gs._sheet.get_global_rect().position.y)
	await _shot("1_first")
	# 성공 직후 —— 번쩍 · 「강화됨」
	yes.pressed.emit()
	await _wait(0.16)
	var done := _find(gs._sheet_body, "KitDone") as Control
	ok(done != null and done.modulate.a > 0.5 and r.kit.get(card, []) == ["w"] and r.merit == 5, "누르면 강화 · 「강화됨」 딱지가 붙는다 (전공 %d)" % r.merit)
	await _shot("4_success")
	await _wait(0.6)
	sec = _find(gs._sheet_body, "KitSection")
	var rows := _rows(sec)
	ok(sec != null and rows.filter(func(n): return bool(n.get_meta("kit_up"))).map(func(n): return str(n.get_meta("kit_slot"))) == ["w"], "정보창으로 돌아와 W 줄이 강화됨")
	await _shot("5_back_info")
	await _wait(0.8)
	await _shot("info_up1")

	# ② 마지막 칸 (R) —— 전공 5 < 6 → 모자람
	gs.kit_confirm(card, "r", true)
	await _wait(0.8)
	yes = _find(gs._sheet_body, "KitYes") as Button
	tx = _texts(gs._sheet_body)
	ok(yes != null and yes.disabled and tx.contains("1 모자람") and tx.contains("마지막 칸"), "전공 모자람 —— 버튼 꺼짐 · 「1 모자람」")
	await _shot("3_short")
	r.merit = 8
	gs.kit_confirm(card, "r", true)
	await _wait(0.8)
	yes = _find(gs._sheet_body, "KitYes") as Button
	tx = _texts(gs._sheet_body)
	ok(yes != null and not yes.disabled and tx.contains("마지막 칸") and tx.contains("나머지 3칸은 잠김"), "마지막 칸 —— 「마지막 칸 · 나머지 3칸은 잠김」")
	await _shot("2_last")
	yes.pressed.emit()
	await _wait(1.6)
	sec = _find(gs._sheet_body, "KitSection")
	ok(sec != null and _texts(sec).contains("모두 강화했다") and r.merit == 2, "2칸 채움 —— 정보창 「모두 강화했다」 · 전공 2")
	ok(headless or _bottom(sec) <= gs._sheet_scroll.get_global_rect().end.y + 0.5, "정보창 2칸 —— P 까지 스크롤 없이")
	await _shot("info_up2")
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


func _rows(n: Node) -> Array:
	var o := []
	if n == null or n.is_queued_for_deletion():
		return o
	if n.has_meta("kit_slot"):
		o.append(n)
	for c in n.get_children():
		o.append_array(_rows(c))
	return o


func _bottom(n: Node) -> float:
	var rs := _rows(n)
	return (rs[-1] as Control).get_global_rect().end.y if not rs.is_empty() else INF


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


func _overflow(gs: GameScreen, n: Node) -> String:
	var lim: float = gs._sheet_body.get_global_rect().end.x + 0.5
	var todo := [n]
	while not todo.is_empty():
		var c: Node = todo.pop_back()
		if c is Control and (c as Control).is_visible_in_tree() and (c as Control).get_global_rect().end.x > lim:
			return "(%s %s +%.0f)" % [c.get_class(), c.name, (c as Control).get_global_rect().end.x - lim]
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
	get_viewport().get_texture().get_image().save_png("%s/%s_%s.png" % [out, tag, name])
