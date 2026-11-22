extends Control
## 상태 딱지(버프 · 디버프) 캡처 (11/22) —— 실행 (창이 뜬다 · 휴대폰 세로):
##   godot --path . --resolution 540x1170 res://tests/status_badge_shot.tscn -- --out=폴더 [--name=badges] [--at=8]
## 한 판을 틀고 at 초에 멈춘 뒤, 부대마다 여러 상태를 걸어 (표시만 —— 판정과 무관) 한 장 저장한다

var _args := {}
const SETS := [
	["cut_atk", "cut_def", "burn"], ["phalanx", "moved"], ["taunted", "confuse"], ["flood", "bleed", "plague", "seal", "cut_res"],
	["undying", "cut_def"], ["cut_int"], ["burn", "flood"], ["moved", "cut_atk", "cut_def", "burn", "confuse"], ["phalanx"],
]


func _ready() -> void:
	for s in OS.get_cmdline_user_args():
		var kv := s.trim_prefix("--").split("=", true, 1)
		_args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	PlayLog.enabled = false
	Settings.load_cfg()
	Settings.type2 = true
	Settings.war_painting = true
	Settings.cam_fx = 0
	Settings.apply()
	theme = UI.theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var view := BattleView.new()
	view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(view)
	await get_tree().process_frame
	Settings.apply_port(view.port)
	var helper = preload("res://tests/inyeon.gd").new()
	var a: Array = DB.auto_place(helper._pick([], 7), "eorin")
	var b: Array = DB.auto_place(helper._pick([], 7), "hagik")
	helper.free()
	var r := RtBattle.new(5100).run(a, "eorin", 100, null, b, "hagik", 100, null, "", "", [], {"A": "auto", "B": "auto"})
	view.play_res(r, "pvp")
	view._set_speed(2.0)
	var at := float(_args.get("at", "8"))
	while view.clock < at and not view.finished:
		await get_tree().process_frame
	view.speed = 0
	var i := 0
	for sq: Squad in view.field.order:
		if sq.alive:
			sq.statuses = SETS[i % SETS.size()].duplicate()
			i += 1
	for k in 6:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var out := str(_args.get("out", "user://"))
	var path := "%s/%s.png" % [out, str(_args.get("name", "badges"))]
	get_viewport().get_texture().get_image().save_png(path)
	print("캡처 ", path)
	get_tree().quit()
