extends Control
## 세 정보창을 실제 GameScreen 경로로 확인한다. -- --gnew=71 --kind=detail|forge|battle --tag=before --focus
func _ready() -> void:
	get_tree().create_timer(60.0).timeout.connect(func(): get_tree().quit(1))
	PlayLog.enabled = false
	DB.warm_enabled = false
	var args := {}
	for value in OS.get_cmdline_user_args():
		var pair := value.trim_prefix("--").split("=", true, 1)
		args[pair[0]] = pair[1] if pair.size() > 1 else "1"
	var gs := GameScreen.new()
	gs.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(gs)
	for i in 4:
		await get_tree().process_frame
	var candidates := DB.C.keys().filter(func(k): return DB.RECOF.has(k) and not DB.is_foe(k) and DB.C[k].get("sks", []).size() >= 2)
	candidates.sort_custom(func(a, b): return DB.C[a].tier > DB.C[b].tier if DB.C[a].tier != DB.C[b].tier else a < b)
	var cid: String = candidates[0]
	for k in candidates:
		if DB.person(k) == str(args.get("who", "주유")):
			cid = k
			break
	gs._open["card_skills"] = true
	match str(args.get("kind", "detail")):
		"forge": gs.recipe_sheet(cid)
		"battle":
			var helper = preload("res://tests/formation_preview.gd").new()
			var a: Array = DB.auto_place(helper._cards(["주유", "육손", "제갈량", "방통", "감녕", "황개", "정보", "조운", "관우"]), "eorin")
			var b: Array = DB.auto_place(helper._cards(["조조", "하후연", "사마의", "마초", "허저", "곽가", "손권", "여포", "화타"]), "hagik")
			helper.free()
			if not a.has(cid):
				a[0] = cid
			var result := RtBattle.new(5100).run(a, "eorin", 100, null, b, "hagik", 100, null, "", "", [], {"A": "auto", "B": "auto"})
			gs._battle.visible = true
			gs._battle.play_res(result, "pvp")
			var key := ""
			for unit in gs._battle.field.order:
				if unit.camp == "A" and unit.cid == cid:
					key = unit.key
			if args.has("escape"):
				var exits: Array = result.ev.filter(func(e): return e.has("escape") and str(e.f).begins_with("A"))
				assert(not exits.is_empty(), "The real replay must contain escape events")
				var matching: Array = exits.filter(func(e): return str(e.f) == key)
				var event: Dictionary = matching[0] if not matching.is_empty() else exits[0]
				key = event.f
				cid = gs._battle.field.squads[key].cid
				var index: int = result.ev.find(event)
				while gs._battle.live_i < index or gs._battle.clock < float(event.tm) + BattleView.OPEN_RT + float(args.get("escape_delay", "0.2")):
					await get_tree().process_frame
				print("ACTUAL_ESCAPE ", event.escape, " clock=", gs._battle.clock, " source_tm=", event.tm)
			gs._battle.speed = 0.0
			gs.battle_unit_sheet(key)
		_: gs.card_info(cid)
	for i in 8:
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
	if args.has("focus"):
		for label in gs._sheet.find_children("*", "Label", true, false):
			if label.is_visible_in_tree() and (label.text.begins_with("기술") or label.text == "일반 기술"):
				gs._sheet_scroll.scroll_vertical += int(label.global_position.y - gs._sheet_scroll.global_position.y - 8)
				break
		for i in 3:
			await get_tree().process_frame
			await RenderingServer.frame_post_draw
	var path := "D:/Sol/build/info_%s_%s%s.png" % [args.get("tag", "after"), args.get("kind", "detail"), "_skills" if args.has("focus") else ""]
	get_viewport().get_texture().get_image().save_png(path)
	print("INFO_PREVIEW ", path, " card=", cid, " ", DB.C[cid].name)
	gs._battle.field.ult.clear()
	gs._battle.type2.painting.reset()
	gs.close_sheet()
	for i in 3:
		await get_tree().process_frame
	gs.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	Sfx.music("")
	await get_tree().create_timer(0.7).timeout
	get_tree().quit()
