extends Control
## 인연 합동 고유기 연출 캡처 (11/11) —— 실행 (창이 뜬다 · 휴대폰 세로 719x1280):
##   godot --path . --resolution 719x1280 --position 495,1500 res://tests/inyeon_cut_shot.tscn -- [--out=폴더] [--seed=5] [--who=유비,관우,장비] [--full=유비,관우,장비]
## tests/inyeon.gd 의 Forced 엔진으로 정한 인물의 게이지를 처음부터 채워 한 판을 돌린 뒤, 그 결과를 BattleView(타입2)로 틀고
## 합류 칩 · 컷인(대표 → 짝 A → 짝 B → 슉) 순서대로 화면을 저장한다 (inyeon_1_chip_a / _2_chip_ab / _3_lead / _4_a_dash / _5_a_land_b_dash / _6_both / _7_surge .png).

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
	# 11/11 연출 순서 캡처 —— 기 모으는 중 합류 칩(A 칩 · A+B 칩) → 컷인(대표 · 짝 A 날아듦 · 짝 B 날아듦 · 둘 다 선 뒤 · 슉)
	# 컷인 시각(cut.t)은 실시간 초. 합류 칩은 합류 줄 시계(전장 시계) 기준
	var cut_at := [["3_lead", 0.30], ["4_a_dash", 0.50], ["5_a_land_b_dash", 0.72], ["6_both", 1.05], ["7_surge", 1.55]]
	var got := {}
	var t_end := Time.get_ticks_msec() + 90000
	while Time.get_ticks_msec() < t_end and got.size() < 8:
		await get_tree().process_frame
		var jt := []
		for k in view.hud.charges:
			if str(view.hud.charges[k].get("inyeon", "")) != "":
				jt.append(view.clock - float(view.hud.charges[k].t0))
		var cut = view.hud.cut
		var shot := ""
		if cut != null and not cut.mates.is_empty():
			for e in cut_at:
				if not got.has(e[0]) and cut.t >= e[1]:
					shot = e[0]
					break
		elif cut == null:
			if not got.has("0_chip_dash") and jt.size() == 1 and jt[0] >= 0.13:
				shot = "0_chip_dash"
			elif not got.has("1_chip_a") and jt.size() == 1 and jt[0] >= 0.42:
				shot = "1_chip_a"
			elif not got.has("2_chip_ab") and jt.size() >= 2 and jt[jt.size() - 1] >= 0.38:
				shot = "2_chip_ab"
		if shot != "":
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png("%s/inyeon_%s.png" % [out, shot])
			got[shot] = true
			print("캡처 ", shot, " cut.t=", cut.t if cut != null else -1.0)
	print("캡처 %s" % str(got.keys()))
	get_tree().quit()
