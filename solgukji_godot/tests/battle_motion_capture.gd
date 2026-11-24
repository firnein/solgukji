extends Control
## 같은 엔진 기록의 전장 움직임을 연속 캡처한다. 사건이나 상태를 주입하지 않는다.
func _ready() -> void:
	var args := {}
	for arg in OS.get_cmdline_user_args():
		var kv := arg.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	if not args.has("interactive"):
		get_tree().create_timer(240.0).timeout.connect(func(): get_tree().quit(1))
	PlayLog.enabled = false
	Settings.load_cfg()
	Settings.type2 = true
	Settings.war_painting = true
	Settings.cam_fx = 0
	Settings.ult_fx = int(args.get("ult-fx", "2"))
	Settings.apply()
	Engine.max_fps = 60
	theme = UI.theme()
	var view := BattleView.new()
	view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(view)
	await get_tree().process_frame
	var helper = preload("res://tests/formation_preview.gd").new()
	var a: Array = DB.auto_place(helper._cards(["주유", "육손", "제갈량", "방통", "감녕", "황개", "정보", "조운", "관우"]), "eorin")
	var enemies: Array = ["조조", "하후연", "사마의", "마초", "허저", "곽가", "손권", "여포", "화타"]
	if args.get("scenario", "") == "fire_front":
		enemies = ["조조", "하후연", "전위", "마초", "허저", "황충", "손권", "조인", "서황"]
	var b: Array = DB.auto_place(helper._cards(enemies), "hagik")
	if args.has("starter"):
		var cards: Array = ["spear", "bow", "strat", "schol", "occul", "schem", "horse", "bow", "strat"]
		a = DB.auto_place(cards, "eorin")
		b = DB.auto_place(cards, "hagik")
	if args.has("legend"):
		var decks = preload("res://tests/battle_lab_decks.gd")
		var rng := RandomNumberGenerator.new()
		rng.seed = 5100
		var counts := [0, 0, 0, 0, 9, 0, 0, 0, 0]
		a = DB.auto_place(decks.make_mix(counts, rng), "eorin")
		b = DB.auto_place(decks.make_mix(counts, rng), "hagik")
	helper.free()
	var result := RtBattle.new(5100).run(a, "eorin", 100, null, b, "hagik", 100, null, "", "", [], {"A": "auto", "B": "auto"})
	var spreads: Array = result.ev.filter(func(e): return e.get("fx") == "status" and e.get("st") == "burn" and bool(e.get("spread", false)))
	print("MOTION_SOURCE burn_spreads=", spreads.size(), " events=", result.ev.size(), " replay_hash=", JSON.stringify(result.ev).hash())
	var original_hash: int = JSON.stringify(result.ev).hash()
	var original_events: Array = result.ev.duplicate(true)
	view.play_res(result, "pvp")
	if args.has("notice"):
		var need_a: bool = str(args.notice) != "B"
		var need_b: bool = str(args.notice) != "A"
		while view.hud.cut != null or (need_a and view.hud.ult_notices.A.is_empty()) or (need_b and view.hud.ult_notices.B.is_empty()):
			assert(not view.finished, "The real replay must produce the requested light activation")
			await get_tree().process_frame
		print("MOTION_NOTICES ally=", view.hud.ult_notices.A, " enemy=", view.hud.ult_notices.B, " clock=", view.clock)
	if args.has("interactive"):
		return # 실제 프레임 속도와 카드 선택은 보통 게임 실행으로 직접 확인한다.
	var count := int(args.get("frames", "90"))
	var start := float(args.get("start", "3"))
	var interval := float(args.get("interval", "0.1"))
	if args.has("movie-until"):
		var movie_start := Engine.get_process_frames()
		var transitions: Array = []
		var revision := -1
		var poses := [0, 0, 0, 0]
		var camps := {}
		var max_figures := 0
		while view.clock < float(args["movie-until"]) and not view.finished:
			await get_tree().process_frame
			var painter = view.type2.painting
			max_figures = maxi(max_figures, painter.figure_count)
			for id in painter.figure_count:
				var cell := int(painter._figs[id * painter.FIG_W + 3])
				if cell >= 96:      # 11/24 신화 장수 인형 (셀 96 + 칸 번호, 자세 없는 한 장)
					assert(cell < 128, "Hero cells must stay inside 96..127")
					continue
				if cell >= 32:
					assert(cell < 96, "Action sheet cells must stay inside the two 4 x 8 atlases")
					poses[cell % 4] += 1
					camps["A" if cell < 64 else "B"] = true
			var story = view.hud.story
			if story.revision != revision and not story.current.is_empty():
				revision = story.revision
				transitions.append({"frame": Engine.get_process_frames() - movie_start, "clock": view.clock,
					"caption": story.caption(view.field.squads), "event": story.history[-1].duplicate(true)})
		assert(JSON.stringify(result.ev).hash() == original_hash)
		assert(poses.all(func(n): return n > 0) and camps.size() == 2, "Real replay must exercise ready, windup, attack and hit poses in both camps")
		var audit := {"scenario": args.get("scenario", "default"), "seed": 5100, "roster": result.roster,
			"source_hash": original_hash, "replay_unchanged": true, "pose_samples": poses, "max_figures": max_figures,
			"battle_finished": view.finished, "movie_start_frame": movie_start, "fixed_fps": 60,
			"offline_capture_not_performance_measurement": true, "transitions": transitions}
		var audit_path := "res://../build/battle_delivery_timeline.json"
		var audit_file := FileAccess.open(audit_path, FileAccess.WRITE)
		audit_file.store_string(JSON.stringify(audit, "\t"))
		audit_file.close()
		print("MOTION_MOVIE replay_hash=", original_hash, " clock=", view.clock)
		view.queue_free()
		await get_tree().process_frame
		get_tree().quit()
		return
	var folder := "res://../build/battle_motion_" + str(args.get("tag", "after"))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	var metrics := {"replay_hash": original_hash, "recorded_burn_spreads": spreads.size(), "max_recoil": 0.0, "max_visible_vacancies": 0, "max_fire_paths": 0, "max_figures_and_standards": 0}
	for i in count:
		while view.clock < start + i * interval and not view.finished:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(folder + "/%04d.png" % i)
		var painter = view.type2.painting
		metrics.max_fire_paths = maxi(metrics.max_fire_paths, painter.fire_paths.size())
		metrics.max_figures_and_standards = maxi(metrics.max_figures_and_standards, painter.figure_count)
		var vacancies := 0
		for form in painter.formations.values():
			for id in form.capacity:
				if form.alive[id] != 0:
					metrics.max_recoil = maxf(metrics.max_recoil, form.recoil[id].length())
					if form.visual_ranks[id] - float(form.ranks[id]) > 0.1:
						vacancies += 1
		metrics.max_visible_vacancies = maxi(metrics.max_visible_vacancies, vacancies)
	if JSON.stringify(result.ev).hash() != original_hash:
		for i in result.ev.size():
			if JSON.stringify(result.ev[i]) != JSON.stringify(original_events[i]):
				print("MOTION_REPLAY_DIFF before=", JSON.stringify(original_events[i]), " after=", JSON.stringify(result.ev[i]))
				break
	assert(JSON.stringify(result.ev).hash() == original_hash, "Capture must not change the engine replay")
	if args.has("verify"):
		assert(metrics.max_recoil > 0.0 and metrics.max_visible_vacancies > 0 and metrics.max_fire_paths > 0, "Actual replay must exercise physical impact, replacement and fire propagation")
	var report := FileAccess.open(folder + "/metrics.json", FileAccess.WRITE)
	report.store_string(JSON.stringify(metrics, "\t"))
	report.close()
	print("MOTION_METRICS ", JSON.stringify(metrics))
	print("MOTION_CAPTURE ", folder, " frames=", count, " clock=", view.clock)
	view.queue_free()
	await get_tree().process_frame
	get_tree().quit()
