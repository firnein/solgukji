extends Control
## 인연기 연출 강화 캡처 (11/15, 모음 · 터짐 · 연쇄 · 이름 띠) —— 실행 (창이 뜬다 · 휴대폰 세로 719x1280):
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
	var at := [[0.25, "a_gather"], [0.52, "b_burst"], [0.75, "c_chain"], [1.1, "d_band"]]
	var got := {}
	var t_end := Time.get_ticks_msec() + 90000
	while Time.get_ticks_msec() < t_end and got.size() < at.size():
		await get_tree().process_frame
		if view.hud.fins.is_empty():
			continue
		var f = view.hud.fins[0]
		for e in at:
			if not got.has(e[1]) and float(f.t) >= e[0]:
				await RenderingServer.frame_post_draw
				get_viewport().get_texture().get_image().save_png("%s/fx_%s_%s.png" % [out, f.kind, e[1]])
				got[e[1]] = true
				print("캡처 ", e[1], " ", f.kind, " t=", f.t, " mates=", f.mkeys.size(), " tgt=", f.tgt.size(), " total=", f.total, " g=", f.g, " n=", view.hud.fins.size())
				break
	print("캡처 %s" % str(got.keys()))
	get_tree().quit()
