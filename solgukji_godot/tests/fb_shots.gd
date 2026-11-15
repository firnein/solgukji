extends Node
## 11/15 사용자 피드백(편성 · 징집 · 갈무리) 화면 캡처 + 자리 점검 —— 창이 있어야 한다:
##   godot --path . --resolution 720x1280 res://tests/fb_shots.tscn -- --out=폴더 [--seed=3] [--play=9]
## ① 편성: 험지 토벌 칩을 켜고 끌 때 칸 자리가 그대로인지 (칸 사각형을 비교해 「칸 밀림 없음 / 있음」 출력) · 장착 아이템 글 · 선호 자리 ✓ (닫힘 · 작은 칸)
## ② 징집: 기본패 줄의 y 가 「징집하기」 카드 · 추천 열림 · 추천 닫힘 · 빈 판에서 같은지 (「기본패 줄 고정 / 움직임」 출력)
## ③ 조합: 갈무리 머리줄 · 완성 순서 시트 · 조합 시트 / 디테일창의 갈무리 버튼 자리 · 갈무리 재료 판매 확인
## 실패(자리 움직임)가 있으면 끝에 「실패 N」.

var out := "user://"
var fails := 0


func _ready() -> void:
	var args := {}
	for s in OS.get_cmdline_user_args():
		var kv := s.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	out = str(args.get("out", "user://"))
	PlayLog.enabled = false
	Run.dev_immortal = true
	Run.delete_save()
	var gs: GameScreen = load("res://scenes/game.tscn").instantiate()
	add_child(gs)
	await _wait(1.2)
	gs._new_game()
	await _wait(0.4)
	gs._coach_finish()
	gs.forge_tree.clear()

	# ── ② 징집 (빈 판 —— 「징집하기」 큰 카드 + 빈 상태)
	var ys := {}
	gs.go("draw")
	await _wait(0.5)
	_clean(gs)
	await _wait(0.3)
	ys["첫날(징집 전 · 빈 판)"] = _base_y(gs)
	await _shot("draw_1_day1_cta_empty")

	# 중반 판
	var r := Run.new()
	r.new_game(int(args.get("seed", "3")))
	for i in int(args.get("play", "9")):
		r.dev_autoplay()
	r.grain = maxi(r.grain, 30)
	gs.run = r
	gs.forge_tree.clear()
	r.drawn = false
	gs._open["draw:rec_fold"] = false
	gs.go("draw")
	await _wait(0.5)
	_clean(gs)
	await _wait(0.3)
	ys["중반(징집 전 · 추천 열림)"] = _base_y(gs)
	await _shot("draw_2_mid_cta_rec_open")
	r.drawn = true
	gs.render()
	await _wait(0.4)
	ys["중반(징집 뒤 · 추천 열림)"] = _base_y(gs)
	await _shot("draw_3_mid_done_rec_open")
	gs._open["draw:rec_fold"] = true
	gs.render()
	await _wait(0.4)
	ys["중반(징집 뒤 · 추천 닫힘)"] = _base_y(gs)
	await _shot("draw_4_mid_done_rec_fold")
	gs._open["draw:rec_fold"] = false
	var y0 = ys.values()[0]
	var same := true
	for k in ys:
		print("  기본패 줄 y %s : %s" % [k, str(ys[k])])
		if absf(float(ys[k]) - float(y0)) > 0.5:
			same = false
	print("기본패 줄 고정" if same else "기본패 줄 움직임")
	if not same:
		fails += 1

	# ── ① 편성
	_gear_up(r)
	r.quest_done = false
	r.quest_hard = false
	for fk in DB.FORM:      # 머리줄이 가장 긴 경우로 —— 「○○ 5칸」 글이 붙는 진형
		if str(DB.FORM[fk].get("full", "")) != "" and not DB.FORM[fk].get("foe", false):
			r.form = fk
			break
	r.auto_deploy()
	_gear_up(r)
	gs.deploy.seg = ""
	gs.go("deploy")
	await _wait(0.6)
	_clean(gs)
	await _wait(0.3)
	var a := _slot_rects(gs)
	await _shot("deploy_1_hard_off")
	print("  험지 칩 보임: ", r.quest_open() and gs.can_form())
	gs.act("set_quest_hard", [true])
	await _wait(0.5)
	_clean(gs)
	await _wait(0.2)
	var b := _slot_rects(gs)
	await _shot("deploy_2_hard_on")
	var moved := a.size() != b.size()
	for i in mini(a.size(), b.size()):
		if (a[i] as Rect2).position.distance_to((b[i] as Rect2).position) > 0.5 or (a[i] as Rect2).size.distance_to((b[i] as Rect2).size) > 0.5:
			moved = true
			print("  칸 %d: %s → %s" % [i, str(a[i]), str(b[i])])
	print("칸 밀림 있음" if moved else "칸 밀림 없음 (칸 %d개 · 머리줄 버튼 자리 같음)" % a.size())
	if moved:
		fails += 1
	gs.act("set_quest_hard", [false])
	# 작은 칸 (보유 열림) · 보급품
	gs.deploy.seg = "hand"
	gs.render()
	await _wait(0.5)
	_clean(gs)
	await _shot("deploy_3_compact_hand")
	gs.deploy.seg = "item"
	gs.render()
	await _wait(0.5)
	await _shot("deploy_4_items_tab")
	gs.deploy.seg = ""
	gs.render()
	await _wait(0.3)
	var si := _slot_with_gear(r)
	if si >= 0:
		gs.deploy.slot_sheet(si)
		await _wait(0.8)
		await _shot("deploy_5_slot_sheet")
		gs.deploy.item_sheet(si)
		await _wait(0.8)
		await _shot("deploy_6_item_sheet")
		gs.close_sheet()
		await _wait(0.4)

	# ── ③ 조합 · 갈무리
	var roots := []
	for k in DB.by_tier(7) + DB.by_tier(6):
		if DB.RECOF.has(k) and not DB.is_kiin(k) and r.have(k) <= 0 and roots.size() < 3 and gs.forge_tree.order_mats(k).size() >= 2:
			roots.append(k)
	gs.forge_tree.pins = roots.duplicate()
	gs.go("forge")
	await _wait(0.8)
	_clean(gs)
	await _shot("forge_1_pins_header")
	gs.forge_tree.order_sheet()
	await _wait(0.8)
	await _shot("forge_2_order_sheet")
	gs.forge_tree.move_pin(roots[2], -1)
	gs.forge_tree.move_mat(roots[0], gs.forge_tree.order_mats(roots[0])[1], -1)
	gs.render()
	gs.forge_tree.order_sheet()
	await _wait(0.6)
	await _shot("forge_3_order_sheet_moved")
	gs.close_sheet()
	await _wait(0.4)
	_clean(gs)
	await _shot("forge_4_pins_after_reorder")
	gs.recipe_sheet(roots[0])
	await _wait(0.8)
	await _shot("forge_5_recipe_sheet_pin_top")
	gs.card_info(roots[0])
	await _wait(0.8)
	await _shot("forge_6_card_detail_pin_top")
	gs.close_sheet()
	await _wait(0.4)
	# 갈무리 재료 판매 —— 한 번 더 묻는 시트
	var mat := ""
	var nd: Dictionary = ForgeTree.needs_of(r, gs.forge_tree.pins)
	for q in nd:
		if Run.sellable(q) and DB.C[q].tier == 3:
			mat = q
			break
	if mat != "":
		r.inv[mat] = 1
		print("  판매 점검 재료: %s → 갈무리 %s" % [DB.C[mat].name, DB.C[gs._sell_pin_target(mat)].name if gs._sell_pin_target(mat) != "" else "(없음)"])
		gs._sell_sheet(mat)
		await _wait(0.8)
		await _shot("sell_1_sheet_pin_note")
		gs._sell_pin_confirm(mat, gs._sell_pin_target(mat))
		await _wait(0.8)
		await _shot("sell_2_pin_confirm")
		gs.close_sheet()
	gs.forge_tree.clear()
	print("실패 %d" % fails)
	get_tree().quit()


func _base_y(gs: GameScreen) -> float:
	return gs._base_row.global_position.y if is_instance_valid(gs._base_row) else -1.0


func _slot_rects(gs: GameScreen) -> Array:
	var o := []
	_collect(gs._fixed, o)
	return o


func _collect(n: Node, o: Array) -> void:
	if n is DeployPage.SlotBox or (n is Button and (n as Button).text in ["자동 편성", "해제"]):
		o.append((n as Control).get_global_rect())
	for c in n.get_children():
		_collect(c, o)


## 편성한 장수에게 아이템을 끼운다 (무기 · 갑옷 —— 이름이 긴 것부터)
func _gear_up(r: Run) -> void:
	for id in DB.IT:
		if DB.IT[id].grade != "유니크":
			r.bag[id] = 1
	for i in 9:
		var k = r.board[i]
		if k == null:
			continue
		for id in DB.IT:
			if DB.IT[id].grade == "유니크" or not r.can_equip(k, id) or str(DB.IT[id].name).length() < 5:
				continue
			var used := false
			for j in 9:
				if r.equip[j] == id or r.equip2[j] == id:
					used = true
			if used:
				continue
			if DB.item_slot(id) == "weapon" and r.equip[i] == null:
				r.equip[i] = id
			elif DB.item_slot(id) == "armor" and r.equip2[i] == null and i % 2 == 0:
				r.equip2[i] = id


func _slot_with_gear(r: Run) -> int:
	for i in 9:
		if r.board[i] != null and r.equip[i] != null and r.equip2[i] != null:
			return i
	for i in 9:
		if r.board[i] != null and r.equip[i] != null:
			return i
	return -1


func _clean(gs: GameScreen) -> void:
	gs.close_sheet()
	gs._bands.clear()
	gs._hide_band()
	for c in gs._toast_box.get_children():
		c.queue_free()


func _wait(s: float) -> void:
	await get_tree().create_timer(s).timeout


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [out, name])
	print("저장 ", name)
