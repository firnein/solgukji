extends Control
## Reproducible desktop diagnostic, not evidence of Android frame performance.
## -- --hide-painting --secs=15 --skip=3 --fps=0
const Formation = preload("res://scripts/field/painted_formation.gd")

func validate_formation(sq: Squad) -> void:
	var form = Formation.new(sq)
	assert(form.count == form.capacity)
	var front := -1
	var behind := -1
	for id in form.capacity:
		if form.ranks[id] == 0 and front < 0:
			front = id
		elif front >= 0 and id % form.cols == front % form.cols and form.ranks[id] == 1:
			behind = id
	assert(front >= 0 and behind >= 0)
	form.remove_soldier(front)
	assert(form.count == form.capacity - 1 and form.ranks[behind] == 0, "Rear rank must fill the front gap")
	form.restore_soldiers(form.capacity, sq)
	assert(form.count == form.capacity and form.opacity[front] == 0.0, "Restored soldier enters from the rear")
	var before: PackedVector2Array = form.feet.duplicate()
	form.step(sq, 0.0)
	assert(form.feet == before, "Paused formation must not move")
	form.step(sq, 0.016)
	assert(form.opacity[front] > 0.0, "Restored soldier must fade into the rear rank")
	print("PASS motion.5 formation: casualties / front replacement / restoration / pause")

func stats(values: Array) -> Dictionary:
	if values.is_empty():
		return {"frames": 0}
	var sorted := values.duplicate()
	sorted.sort()
	var total := 0.0
	var slow := 0
	for value in values:
		total += float(value)
		if value > 33.333:
			slow += 1
	return {"frames": values.size(), "fps": values.size() * 1000.0 / total,
		"mean_ms": total / values.size(), "p50_ms": sorted[ceili((sorted.size() - 1) * 0.50)],
		"p95_ms": sorted[ceili((sorted.size() - 1) * 0.95)], "p99_ms": sorted[ceili((sorted.size() - 1) * 0.99)],
		"max_ms": sorted[-1], "over_33ms_pct": slow * 100.0 / values.size()}

func _ready() -> void:
	var args := {}
	for arg in OS.get_cmdline_user_args():
		var kv := arg.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	get_tree().create_timer(90.0).timeout.connect(func(): get_tree().quit(1))
	PlayLog.enabled = false
	Settings.load_cfg()
	Settings.type2 = true
	Settings.war_painting = true
	Settings.quality = 1
	Settings.cam_fx = 0
	Settings.apply()
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = int(args.get("fps", "0"))
	theme = UI.theme()
	var view := BattleView.new()
	view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(view)
	await get_tree().process_frame
	var helper = preload("res://tests/formation_preview.gd").new()
	var a: Array = DB.auto_place(helper._cards([]), "eorin")
	var b: Array = DB.auto_place(helper._cards([]), "hagik")
	helper.free()
	var result := RtBattle.new(5100).run(a, "eorin", 100, null, b, "hagik", 100, null, "", "", [], {"A": "auto", "B": "auto"})
	view.play_res(result, "pvp")
	view.speed = 1.0
	var painter: Control = view.type2.painting
	validate_formation(view.field.order[0])
	var source: Squad = view.field.order[0]
	var target: Squad = view.field.order[-1]
	painter.prepare_attack(source.key, [target.key], "volley")
	assert(not painter.volleys.is_empty(), "Volley event must reach the formation renderer")
	painter.play_event({"fx": "phys", "a": source.key, "f": target.key, "n": 10, "painted_charge": "hit"}, null, [{"key": target.key, "troops": target.max * 0.5}])
	assert(painter.charges.has(target.key) and not painter.contacts.is_empty() and not painter.bodies.is_empty())
	assert(painter.bodies.size() <= painter.MAX_BODIES and painter.contacts.size() <= painter.MAX_CONTACTS)
	painter.reset()
	assert(painter.formations.is_empty() and painter.bodies.is_empty() and painter.contacts.is_empty() and painter.volleys.is_empty())
	var capacity := 0
	for sq: Squad in view.field.order:
		capacity += painter._formation(sq).capacity
	print("PASS motion.5 event delivery: volley / impact / casualty / effect limits / reset")
	if args.has("validate-only"):
		await RenderingServer.frame_post_draw
		if args.has("shot"):
			get_viewport().get_texture().get_image().save_png("res://../build/motion5_renderer_smoke.png")
		view.queue_free()
		await get_tree().process_frame
		get_tree().quit()
		return
	var hidden := args.has("hide-painting")
	if hidden:
		painter.hide()
	var skip := float(args.get("skip", "3"))
	var duration := float(args.get("secs", "15"))
	var start := Time.get_ticks_usec()
	while (Time.get_ticks_usec() - start) / 1e6 < skip:
		await get_tree().process_frame
	var last := Time.get_ticks_usec()
	var end := last + int(duration * 1e6)
	var frames := []
	var phases := {"march": [], "contact": [], "ultimate": []}
	var max_figures := 0
	var max_meshes := 0
	var max_bodies := 0
	var draw_calls := 0.0
	while Time.get_ticks_usec() < end and not view.finished:
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		var frame_ms := (now - last) / 1000.0
		last = now
		frames.append(frame_ms)
		var phase := "march"
		if view.hud.cut != null or not view.hud.fins.is_empty():
			phase = "ultimate"
		elif view.field.order.any(func(sq): return sq.alive and sq.contact):
			phase = "contact"
		phases[phase].append(frame_ms)
		max_figures = maxi(max_figures, painter.visible_soldiers.size())
		max_meshes = maxi(max_meshes, painter.walk_meshes.size())
		max_bodies = maxi(max_bodies, painter.bodies.size())
		draw_calls += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
	var report := {"platform": OS.get_name(), "engine": Engine.get_version_info().string,
		"android_device_measurement": OS.get_name() == "Android", "renderer": RenderingServer.get_current_rendering_method(),
		"adapter": RenderingServer.get_video_adapter_name(), "window": str(get_viewport_rect().size),
		"quality": Settings.quality, "vsync": false, "fps_cap": Engine.max_fps, "seed": 5100,
		"hidden_painting": hidden, "warmup_seconds": skip, "sample_seconds": duration, "total": stats(frames),
		"phases": {}, "max_figures": max_figures, "max_bodies": max_bodies, "max_walk_meshes": max_meshes,
		"mean_draw_calls": draw_calls / maxf(1.0, frames.size()), "initial_formation_capacity": capacity}
	for phase in phases:
		report.phases[phase] = stats(phases[phase])
	var name_ := "hidden" if hidden else "full"
	var path := "res://../build/motion5_profile_%s.json" % str(args.get("tag", name_))
	var f := FileAccess.open(path, FileAccess.WRITE)
	assert(f != null)
	f.store_string(JSON.stringify(report, "\t"))
	f.close()
	print("PROFILE ", JSON.stringify(report))
	view.queue_free()
	await get_tree().process_frame
	get_tree().quit()
