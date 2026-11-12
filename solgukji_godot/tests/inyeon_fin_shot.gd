extends Control
## 인연기 연출 캡처 (11/12) —— 실행 (창이 뜬다 · 휴대폰 세로 719x1280):
##   godot --path . --resolution 719x1280 --position 495,1500 res://tests/inyeon_fin_shot.tscn -- [--out=폴더] [--seed=5] [--who=주유,제갈량,황개]
## tests/inyeon.gd 의 Forced 엔진으로 게이지를 채워 한 판을 돌리고, BattleView 에서 「인연기 『…』」 띠가 뜬 순간을 저장한다 (fin_<who>_1 / _2 .png).

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
	var who: Array = str(_args.get("who", "주유,제갈량,황개")).split(",", false)
	var sd := int(_args.get("seed", "5"))
	var helper = T.new()
	var a: Array = helper._pick(who)
	var b: Array = helper._pick([], 7)
	var ca := DB.auto_place(a, "eorin")
	var cb := DB.auto_place(b, "hagik")
	var bt = T.Forced.new(sd)
	bt.full = who
	var r: Dictionary = bt.run(ca, "eorin", 100, null, cb, "hagik", 100, null, "", "", [], {"A": "auto", "B": "auto"})
	print("인연기 사건 %d" % r.ev.filter(func(e): return e.get("fx") == "inyeon_fin").size())
	view.play_res(r, "pvp", {"a": ca, "fa": "eorin", "ma": 100, "ea": null, "b": cb, "fb": "hagik", "mb": 100, "eb": null, "seed": sd,
		"title": "인연기 점검", "foe": "적군", "policy": {"A": "auto", "B": "auto"}})
	var out := str(_args.get("out", "user://"))
	var at := [["1", 0.2], ["2", 0.7]]
	var got := {}
	var t_end := Time.get_ticks_msec() + 60000
	while Time.get_ticks_msec() < t_end and got.size() < at.size():
		await get_tree().process_frame
		var ann = view.hud.ann
		if ann == null or not str(ann.text).begins_with("인연기"):
			continue
		for e in at:
			if not got.has(e[0]) and float(ann.t) >= e[1]:
				await RenderingServer.frame_post_draw
				get_viewport().get_texture().get_image().save_png("%s/fin_%s_%s.png" % [out, who[0], e[0]])
				got[e[0]] = true
				print("캡처 ", e[0], " ", ann.text, " clock=", view.clock)
				break
	print("캡처 %s" % str(got.keys()))
	get_tree().quit()
