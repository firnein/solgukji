extends Control
## 인연 합동 고유기 연출 캡처 (11/11) —— 실행 (창이 뜬다 · 휴대폰 세로 719x1280):
##   godot --path . --resolution 719x1280 --position 495,1500 res://tests/inyeon_shot.tscn -- [--out=폴더] [--seed=5] [--who=유비,관우,장비] [--full=유비,관우,장비]
## tests/inyeon.gd 의 Forced 엔진으로 정한 인물의 게이지를 처음부터 채워 한 판을 돌린 뒤, 그 결과를 BattleView(타입2)로 틀고
## ① 합류 줄이 둘 다 보일 때 ② 컷인(짝 초상 · 인연 글)이 자리 잡았을 때 ③ 컷인이 미끄러져 들어올 때 화면을 저장한다 (inyeon_1_join / _2_cut / _3_slide .png).

var _args := {}


func _ready() -> void:
	for s in OS.get_cmdline_user_args():
		var kv := s.trim_prefix("--").split("=", true, 1)
		_args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	PlayLog.enabled = false
	Settings.load_cfg()
	Settings.type2 = true
	Settings.cam_fx = 0
	Settings.apply()
	theme = UI.theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var view := BattleView.new()
	view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(view)
	await get_tree().process_frame
	Settings.apply_port(view.port)
	var T = preload("res://tests/inyeon.gd")
	var who: Array = str(_args.get("who", "유비,관우,장비")).split(",", false)
	var full: Array = str(_args.get("full", ",".join(who))).split(",", false)
	var sd := int(_args.get("seed", "5"))
	var helper = T.new()
	var a: Array = helper._pick(who)
	var b: Array = helper._pick([], 7)
	var ca := DB.auto_place(a, "eorin")
	var cb := DB.auto_place(b, "hagik")
	var bt = T.Forced.new(sd)
	bt.full = full
	var r: Dictionary = bt.run(ca, "eorin", 100, null, cb, "hagik", 100, null, "", "", [], {"A": "auto", "B": "auto"})
	print("합류 %d · 터짐 %d" % [r.ev.filter(func(e): return e.get("fx") == "ult_join").size(), r.ev.filter(func(e): return e.get("fx") == "ult").size()])
	view.play_res(r, "pvp", {"a": ca, "fa": "eorin", "ma": 100, "ea": null, "b": cb, "fb": "hagik", "mb": 100, "eb": null, "seed": sd,
		"title": "인연 점검", "foe": "적군", "policy": {"A": "auto", "B": "auto"}})
	var out := str(_args.get("out", "user://"))
	var got := [false, false, false]
	var t_end := Time.get_ticks_msec() + 90000
	while Time.get_ticks_msec() < t_end and not (got[0] and got[1] and got[2]):
		await get_tree().process_frame
		var nj := 0
		for k in view.hud.charges:
			if str(view.hud.charges[k].get("inyeon", "")) != "":
				nj += 1
		var cut = view.hud.cut
		if not got[0] and nj >= 2:
			await get_tree().create_timer(0.35).timeout
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png("%s/inyeon_1_join.png" % out)
			got[0] = true
		elif not got[2] and cut != null and not cut.mates.is_empty() and cut.t >= 0.2 and cut.t < 0.5:
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png("%s/inyeon_3_slide.png" % out)
			got[2] = true
		elif not got[1] and cut != null and not cut.mates.is_empty() and cut.t >= 0.75:
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png("%s/inyeon_2_cut.png" % out)
			got[1] = true
	print("캡처 %s" % str(got))
	get_tree().quit()
