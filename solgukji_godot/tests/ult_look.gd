extends Control
## 11/19 고유기 이펙트 모양 점검 —— 지정한 장수들의 고유기가 맞는 순간(0.55초 뒤)을 한 장씩 찍는다
## godot --path . res://tests/ult_look.tscn -- --a=주유,육손,정보 --b=황개,방통,동탁 --out=../captures/ult

func _ready() -> void:
	var args := {}
	for arg in OS.get_cmdline_user_args():
		var kv := arg.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	PlayLog.enabled = false
	Settings.load_cfg()
	Settings.apply()
	theme = UI.theme()
	var view := BattleView.new()
	view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(view)
	await get_tree().process_frame
	var helper = preload("res://tests/formation_preview.gd").new()
	var a: Array = DB.auto_place(helper._cards(Array(str(args.get("a", "")).split(",", false))), "eorin")
	var b: Array = DB.auto_place(helper._cards(Array(str(args.get("b", "")).split(",", false))), "hagik")
	helper.free()
	var res := RtBattle.new(int(args.get("seed", "5100"))).run(a, "eorin", 100, null, b, "hagik", 100, null, "", "", [], {"A": "auto", "B": "auto"})
	view.play_res(res, "pvp")
	view.speed = 1.0
	var painter = view.type2.painting
	var done := {}
	if args.has("start"):      # 전투 시작 화면 (진형 글씨가 없는지)
		await get_tree().create_timer(1.2).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("%s_start.png" % str(args.get("out", "res://../captures/ult")))
	var t0 := Time.get_ticks_msec()
	var at := float(args.get("at", "0.55"))
	while Time.get_ticks_msec() - t0 < int(float(args.get("secs", "70")) * 1000.0) and not view.finished:
		await get_tree().process_frame
		var cutn := str(args.get("cut", ""))      # --cut=장비 —— 그 장수의 컷인(외침이 다 나온 뒤)을 찍는다
		if cutn != "" and view.hud.cut != null and str(view.hud.cut.who).contains(cutn) and float(view.hud.cut.t) > 1.0 and not done.has("cut"):
			done["cut"] = true
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png("%s_cut_%s.png" % [str(args.get("out", "res://../captures/ult")), cutn])
			print("컷인 찍음 ", view.hud.cut.who)
			if args.has("cutonly"):
				get_tree().quit()
				return
		for e: Dictionary in painter.ults:
			if e.phase != "impact" or e.hits.is_empty():
				continue
			var sq = view.field.squads.get(e.a)
			if sq == null:
				continue
			var who: String = DB.person(sq.cid)
			if done.has(who) or view.field.clock - float(e.start) < at or view.hud.cut != null:
				continue
			done[who] = true
			await RenderingServer.frame_post_draw
			var img := get_viewport().get_texture().get_image()
			img.save_png("%s_%s.png" % [str(args.get("out", "res://../captures/ult")), who])
			print("찍음 ", who, " ", e.vfx, " ", e.get("style", ""), " sd ", e.get("sd", 0))
	print("끝 ", done.keys())
	get_tree().quit()
