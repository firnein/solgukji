extends Control
## 11/19 전투 계산 스레드 점검 —— 실행: godot --path . --resolution 400x800 res://tests/async_sim.tscn
## BattleView.play 가 계산을 스레드에서 돌려도 (1) 화면이 멈추지 않고 (2) 결과가 바로 계산한 것과 글자 하나 다르지 않고 (3) 재생이 시작되는지,
## (4) 계산 도중 온라인 재생(play_res)이 들어오면 그쪽이 이기는지 본다

func _ready() -> void:
	get_tree().create_timer(60.0).timeout.connect(func(): get_tree().quit(1))
	PlayLog.enabled = false
	Settings.load_cfg()
	theme = UI.theme()
	var view := BattleView.new()
	view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(view)
	await get_tree().process_frame
	var helper = preload("res://tests/formation_preview.gd").new()
	var a: Array = DB.auto_place(helper._cards([]), "eorin")
	var b: Array = DB.auto_place(helper._cards([]), "hagik")
	helper.free()
	var bt := {"a": {"cards": a, "form": "eorin", "morale": 100, "equip": null}, "b": {"cards": b, "form": "hagik", "morale": 100, "equip": null},
		"seed": 4242, "title": "점검", "foe": "적", "kind": "pvp", "inputs": []}
	# 바로 계산한 기준
	BattleView.async_sim = false
	view.play(bt)
	var want := JSON.stringify(view.res.ev)
	assert(view.running, "sync play must start at once")
	# 스레드로
	BattleView.async_sim = true
	var t0 := Time.get_ticks_msec()
	view.play(bt)
	assert(view._loading and not view.running, "async play must return while the simulation runs")
	var frames := 0
	var worst := 0
	var last := Time.get_ticks_msec()
	while view._loading:
		await get_tree().process_frame
		frames += 1
		var now := Time.get_ticks_msec()
		worst = maxi(worst, now - last)
		last = now
	await get_tree().process_frame
	assert(view.running and not view._loading, "replay must start after the simulation")
	assert(JSON.stringify(view.res.ev) == want, "threaded result must equal the direct result")
	assert(frames >= 3, "main thread must keep drawing during the simulation")
	assert(view.start_stats(view.field.order[0].key).size() > 0, "start stats must work again after loading")
	print("ASYNC sim %d ms · frames while loading %d · worst frame %d ms" % [Time.get_ticks_msec() - t0, frames, worst])
	# 계산 도중 서버 결과 재생이 들어온다 —— 그 결과가 화면에 남아야 한다
	var other: Dictionary = RtBattle.new(77).run(a, "eorin", 100, null, b, "hagik", 100, null, "", "", [], {"A": "auto", "B": "auto"})
	view.play(bt)
	view.play_res(other, "pvp")
	# 11/20 프레임 수(120) 대신 시간(최대 6초)으로 기다린다 —— 헤드리스는 120프레임이 1초쯤이라 다른 점검과 함께 돌면 계산(2초 남짓)이 끝나기 전에 넘어가 아래 단언이 깨졌다
	var wait_until := Time.get_ticks_msec() + 6000
	while view._loading and Time.get_ticks_msec() < wait_until:
		await get_tree().process_frame
	await get_tree().process_frame
	assert(not view._loading and view.running, "online replay must keep running")
	assert(JSON.stringify(view.res.ev) == JSON.stringify(other.ev), "a late threaded result must not replace the online replay")
	print("PASS async sim: same result / no stall / start stats / online replay wins")
	view.queue_free()
	await get_tree().process_frame
	get_tree().quit()
