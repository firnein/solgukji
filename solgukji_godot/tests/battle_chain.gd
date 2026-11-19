extends Control
## 11/19 전투를 연달아 볼 때 프레임 · 노드 · 객체 수가 쌓이는지 (온라인은 한 판에 30전투 넘게 본다)
## godot --path . res://tests/battle_chain.tscn -- --n=12 --secs=5

func _ready() -> void:
	var args := {}
	for arg in OS.get_cmdline_user_args():
		var kv := arg.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	PlayLog.enabled = false
	Settings.load_cfg()
	Settings.apply()
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	theme = UI.theme()
	var view := BattleView.new()
	view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(view)
	await get_tree().process_frame
	var helper = preload("res://tests/formation_preview.gd").new()
	var a: Array = DB.auto_place(helper._cards([]), "eorin")
	var b: Array = DB.auto_place(helper._cards([]), "hagik")
	helper.free()
	var secs := float(args.get("secs", "5"))
	for i in int(args.get("n", "12")):
		var res := RtBattle.new(5100 + (i if args.has("vary") else 0)).run(a, "eorin", 100, null, b, "hagik", 100, null, "", "", [], {"A": "auto", "B": "auto"})
		view.play_res(res, "pvp")
		var left: int = view.type2._areas.size()      # 지난 전투에서 넘어온 범위 표시 (0 이어야 한다)
		view.speed = 2.0
		if args.has("full"):      # 실제처럼 끝까지 본다 (8배속) —— 재는 것은 처음 secs 초
			view.speed = 8.0
		await get_tree().create_timer(1.0).timeout
		var pf0: Dictionary = view.field.prof.duplicate()
		var t0 := Time.get_ticks_usec()
		var last := t0
		var n := 0
		var worst := 0.0
		while Time.get_ticks_usec() - t0 < int(secs * 1e6):
			await get_tree().process_frame
			var now := Time.get_ticks_usec()
			worst = maxf(worst, (now - last) / 1000.0)
			last = now
			n += 1
		print("전투 %2d · 평균 %.2fms · 최대 %.1f · 노드 %d · 객체 %d · 그리기 %d · 메모리 %.0fMB · 텍스처 %.0fMB" % [i + 1, secs * 1000.0 / n, worst,
			int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)), int(Performance.get_monitor(Performance.OBJECT_COUNT)),
			int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
			Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0, Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED) / 1048576.0])
		var parts := []
		for k in view.field.prof:
			if k != "_frames":
				parts.append([k, (view.field.prof[k] - pf0.get(k, 0)) / 1000.0 / n])
		parts.sort_custom(func(x, y): return x[1] > y[1])
		if args.has("full"):
			var guard := Time.get_ticks_msec()
			while not view.finished and Time.get_ticks_msec() - guard < 20000:
				await get_tree().process_frame
		print("   넘어온 범위 %d · 전투 길이 %.0f초" % [left, view.clock])
		if not args.has("quiet"):
			print("   " + " · ".join(parts.slice(0, 8).map(func(x): return "%s %.2f" % [x[0], x[1]])))
	get_tree().quit()
