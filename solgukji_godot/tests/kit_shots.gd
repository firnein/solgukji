extends Node
## 11/27 장수 키트 Q · W · E · R · P 화면 캡처 + 화면 흐름 점검 —— 창이 있어야 캡처가 된다 (화면 없이 돌리면 흐름만 점검하고 캡처는 건너뛴다):
##   godot --path . --resolution 540x1200 res://tests/kit_shots.tscn -- --out=폴더 [--seed=3] [--play=9] [--card=c177]
## ① 머리띠의 전공 · 편성 칸의 강화 표시   ② 장수 정보창의 Q · W · E · R · P 다섯 줄 (강화 칩 · 강화 버튼 · 전공 부족)
## ③ 강화 선택 시트 → 고르면 전공이 줄고 정보창으로 돌아온다   ④ 가지지 않은 키트 장수는 보기만 (버튼 없음)
## 실패가 있으면 끝에 「실패 N」.

const Kit := preload("res://scripts/kit.gd")

var out := "user://"
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
	r.new_game(int(args.get("seed", "3")))
	for i in int(args.get("play", "9")):
		r.dev_autoplay()
	# 편성 가운데 칸에 키트 장수를 올리고 몇 칸을 미리 강화해 둔다 (Q 둘 · R 하나 · P 둘), 전공은 3 —— W(2) · E(2) · R(3)은 되고 Q(4) · P(4)는 모자라다
	var at := 4
	for i in 9:
		if r.board[i] != null and int(DB.C[r.board[i]].tier) <= int(DB.C[r.board[at]].tier if r.board[at] != null else 99):
			at = i
	r.board[at] = card
	r.kit = Kit.clean({card: {"q": Kit.options(card, "q", []).slice(0, 2), "r": Kit.options(card, "r", []).slice(0, 1), "p": ["amp", "amp"]}})
	r.merit = 3
	r.grain = maxi(r.grain, 12)
	r.auto_draw()      # 기본패를 미리 받아 둔다 —— 화면에 징집 공개 연출이 겹치지 않게
	gs.run = r
	gs.deploy.seg = ""
	gs.go("deploy")
	await _wait(0.6)
	_clean(gs)
	await _wait(0.3)
	ok(gs._merit_box.visible and gs._merit_lbl.text == "3", "머리띠에 전공 3 (보임 %s · 글 %s)" % [str(gs._merit_box.visible), gs._merit_lbl.text])
	ok(gs.kit_on(), "혼자 하기 —— 키트 강화를 쓰는 판")
	await _shot("kit_1_head_deploy")

	# ② 장수 정보창
	gs.card_info(card)
	await _wait(0.9)
	var sec := _find(gs._sheet_body, "KitSection")
	ok(sec != null, "정보창에 「장수 키트」 묶음")
	var badges := _count(gs._sheet_body, func(n): return n is SheetStyle.SlotBadge)
	ok(badges == 5, "칸 딱지 다섯 (Q · W · E · R · P) —— %d" % badges)
	var btns := _buttons(sec)
	var on_n := btns.filter(func(b): return not b.disabled).size()
	ok(btns.size() == 5 and on_n == 3, "강화 버튼 5 · 켜진 것 3 (전공 3: W · E · R) —— %d / %d" % [on_n, btns.size()])
	ok(_find(gs._sheet_body, "SkillsSection") == null and _count(gs._sheet_body, func(n): return n is TraitBoard and n.visible) == 0, "일반 기술 묶음 · 특기판은 그리지 않는다 (Q · W · E 는 키트 줄에)")
	ok(_overflow(gs, sec) == "", "키트 묶음이 시트 폭 안에 있다 %s" % _overflow(gs, sec))
	await _shot("kit_2_card_info")
	gs._sheet_scroll.scroll_vertical = 260
	await _wait(0.4)
	await _shot("kit_2b_card_info_scrolled")

	# ③ 강화 선택 시트 —— W
	gs._kit_pick(card, "w")
	await _wait(0.8)
	var picks := _buttons(gs._sheet_body).filter(func(b): return _has_merit_icon(b))
	ok(picks.size() == Kit.options(card, "w", []).size() and picks.all(func(b): return not b.disabled), "강화 선택 시트 —— 고를 수 있는 강화 %d개 모두 켜짐" % picks.size())
	await _shot("kit_3_pick_sheet")
	var first: String = Kit.options(card, "w", [])[0]
	picks[0].pressed.emit()
	await _wait(0.9)
	ok(r.merit == 1 and Kit.augs_of(r.kit, card, "w") == [first], "고르면 전공 3 → %d · W 에 「%s」" % [r.merit, Kit.AUG[first].n])
	ok(gs._merit_lbl.text == "1", "머리띠 전공도 %s" % gs._merit_lbl.text)
	sec = _find(gs._sheet_body, "KitSection")
	ok(sec != null and _buttons(sec).filter(func(b): return not b.disabled).is_empty(), "정보창으로 돌아온다 —— 남은 전공 1 로는 모든 버튼이 꺼진다")
	# 전공이 모자란 칸의 선택 시트 —— 버튼이 꺼지고 까닭
	gs._kit_pick(card, "q")
	await _wait(0.7)
	var qp := _buttons(gs._sheet_body).filter(func(b): return _has_merit_icon(b))
	ok(not qp.is_empty() and qp.all(func(b): return b.disabled), "전공이 모자란 칸 —— 선택 버튼이 모두 꺼진다")

	# ④ 가지지 않은 키트 장수 —— 보기만
	var other := ""
	for k in DB.C:
		if Kit.on(k) and k != card and r.have(k) <= 0:
			other = k
			break
	gs.card_info(other)
	await _wait(0.9)
	sec = _find(gs._sheet_body, "KitSection")
	ok(sec != null and _buttons(sec).is_empty() and _count(gs._sheet_body, func(n): return n is SheetStyle.SlotBadge) == 5, "가지지 않은 %s —— 다섯 줄은 보이고 강화 버튼은 없다" % DB.C[other].name)
	# 키트가 아닌 장수는 예전 그대로
	var plain := ""
	for k in DB.by_tier(7):
		if not Kit.on(k) and not DB.is_foe(k) and DB.has_ult(k):
			plain = k
			break
	gs.card_info(plain)
	await _wait(0.8)
	ok(_find(gs._sheet_body, "KitSection") == null and _find(gs._sheet_body, "SkillsSection") != null, "키트가 아닌 %s —— 예전 그대로 (일반 기술 묶음 · 키트 묶음 없음)" % DB.C[plain].name)
	# 전투 장수창이 쓰는 기술 목록(_skills_section) —— 키트 장수의 일반기술 줄에 Q · W · E 칸 딱지
	var sb := gs.open_sheet("기술 목록 점검")
	sb.add_child(gs._skills_section(card))
	await _wait(0.6)
	ok(_count(sb, func(n): return n is SheetStyle.SlotBadge) == 3 and _overflow(gs, sb) == "", "기술 목록(전투 장수창) —— Q · W · E 칸 딱지 셋 · 폭 안 %s" % _overflow(gs, sb))
	if args.has("extra"):
		await _shot("kit_x_skill_panel")
	gs.close_sheet()
	print("실패 %d" % fails)
	get_tree().quit(1 if fails > 0 else 0)


func _find(n: Node, nm: String) -> Node:
	if n.name == nm and not n.is_queued_for_deletion():
		return n
	for c in n.get_children():
		var f := _find(c, nm)
		if f != null:
			return f
	return null


func _count(n: Node, pred: Callable) -> int:
	if n.is_queued_for_deletion():
		return 0
	var s := 1 if pred.call(n) else 0
	for c in n.get_children():
		s += _count(c, pred)
	return s


func _buttons(n: Node) -> Array:
	var o := []
	if n == null or n.is_queued_for_deletion():
		return o
	if n is Button and _has_merit_icon(n):
		o.append(n)
	for c in n.get_children():
		o.append_array(_buttons(c))
	return o


## 전공 기호가 든 버튼인가 (강화 · 선택 버튼)
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
