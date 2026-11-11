extends Control
## 사기 표시 캡처 (11/11) —— 실행 (창이 뜬다 · 휴대폰 세로 719x1280):
##   godot --path . --resolution 719x1280 --position 495,1500 res://tests/morale_shot.tscn -- [--out=폴더] [--seed=3] [--am=40] [--bm=100] [--tier=5] [--speed=2] [--style=type2|3d] [--max=120] [--flash=1] [--mirror=1] [--minlen=50]
## 한 판을 돌려 BattleView 로 틀고, 위 사기 게이지 · 「동요」 딱지 · 「사기 붕괴」 글 · 「결전」 띠가 처음 보이는 순간마다 저장한다
## (morale_0_gauge / _1_shaky / _2_rout / _3_decisive .png). 아군 사기를 낮게(--am) 주면 사기 패주가 잘 난다. 결전은 45초 넘게 가는 판(--am=100 --bm=100)에서.

var _args := {}


func _ready() -> void:
	for s in OS.get_cmdline_user_args():
		var kv := s.trim_prefix("--").split("=", true, 1)
		_args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	PlayLog.enabled = false
	Settings.load_cfg()
	Settings.type2 = str(_args.get("style", "type2")) == "type2"
	Settings.cam_fx = 0
	Settings.apply()
	theme = UI.theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var view := BattleView.new()
	view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(view)
	await get_tree().process_frame
	Settings.apply_port(view.port)
	var tier := int(_args.get("tier", "5"))
	var sd := int(_args.get("seed", "3"))
	var am := float(_args.get("am", "40"))
	var bm := float(_args.get("bm", "100"))
	var a := _deck(tier, 0)
	var b := _deck(tier, 9)
	var ca := DB.auto_place(a, "eorin")
	var cb := DB.auto_place(b, "hagik")
	if str(_args.get("mirror", "0")) == "1":
		cb = DB.auto_place(a, "hagik")
	var minlen := float(_args.get("minlen", "0"))      # 이 길이(초) 이상 가는 판이 나올 때까지 시드를 올린다 (결전 점검)
	var r: Dictionary = {}
	for i in 40:
		var bt := RtBattle.new(sd)
		r = bt.run(ca, "eorin", am, null, cb, "hagik", bm, null, "", "", [], {"A": "auto", "B": "auto"})
		if float(r.get("len", 0)) >= minlen:
			break
		sd += 1
	print("seed ", sd)
	var kinds := {}
	for e in r.ev:
		kinds[e.get("fx", "")] = int(kinds.get(e.get("fx", ""), 0)) + 1
	print("판 길이 %.1f초 · 사기 패주 %d · 결전 %d · 승 %s" % [float(r.get("len", 0)), r.ev.filter(func(e): return e.get("fx") == "rout" and str(e.t).contains("끝내 패주")).size(),
		int(kinds.get("decisive", 0)), str(r.get("win"))])
	view.play_res(r, "pvp", {"a": ca, "fa": "eorin", "ma": am, "ea": null, "b": cb, "fb": "hagik", "mb": bm, "eb": null, "seed": sd,
		"title": "사기 점검", "foe": "적군", "policy": {"A": "auto", "B": "auto"}})
	view._set_speed(float(_args.get("speed", "2")))
	var out := str(_args.get("out", "user://"))
	var got := {}
	var t_end := Time.get_ticks_msec() + int(float(_args.get("max", "120")) * 1000)
	while Time.get_ticks_msec() < t_end and not view.finished and got.size() < 4:
		await get_tree().process_frame
		var shot := ""
		if not got.has("0_gauge") and view.clock > 6.0:
			shot = "0_gauge"
		elif not got.has("1_shaky") and view.field.order.any(func(q): return q.camp == "A" and BattleView.Hud.shaky(q)):
			shot = "1_shaky"
		elif not got.has("2_rout") and view.hud.mrout != null and view.hud.mrout.age >= 0.35:
			shot = "2_rout"
		elif not got.has("3_decisive") and view.hud.decisive_on and view.hud.decisive_age >= (0.2 if str(_args.get("flash", "0")) == "1" else 2.0):
			shot = "3_decisive"
		if shot != "":
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png("%s/morale_%s.png" % [out, shot])
			got[shot] = true
			print("캡처 ", shot, " clock=%.1f" % view.clock)
	print("캡처 %s" % str(got.keys()))
	get_tree().quit()


## 그 등급 무작위 9장 (서로 다른 인물)
func _deck(tier: int, skip: int) -> Array:
	var out := []
	var used := []
	var pool: Array = DB.by_tier(tier)
	for i in range(skip, pool.size()):
		var k: String = pool[i]
		if not used.has(DB.person(k)):
			out.append(k)
			used.append(DB.person(k))
		if out.size() >= 9:
			break
	return out
