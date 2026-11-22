extends Control
## 상태 딱지 비용 점검 (11/22) —— 실행:
##   godot [--headless] --path . --resolution 540x1170 res://tests/badge_perf.tscn -- [--badges=1] [--secs=8] [--at=4]
## 한 판을 틀고 at 초부터 secs 초 동안, 매 프레임 부대마다 여러 상태를 걸어 (표시만) 잰다:
##   처리(process_frame → frame_pre_draw: _process + _draw) · 렌더 CPU(frame_pre_draw → frame_post_draw) · 그리기 호출 —— "BADGE|" 한 줄
var _args := {}
var _view: BattleView
var _on := true
const SETS := [
	["cut_atk", "cut_def", "burn"], ["phalanx", "moved"], ["taunted", "confuse"], ["flood", "bleed", "plague", "seal", "cut_res"],
	["undying", "cut_def"], ["cut_int"], ["burn", "flood"], ["moved", "cut_atk", "cut_def", "burn", "confuse"], ["phalanx"],
]
var _t0 := 0
var _proc := 0.0
var _rend := 0.0


func _ready() -> void:
	for s in OS.get_cmdline_user_args():
		var kv := s.trim_prefix("--").split("=", true, 1)
		_args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	_on = str(_args.get("badges", "1")) == "1"
	process_priority = 1000      # 전투 화면 _process 뒤에 상태를 덮어쓴다
	PlayLog.enabled = false
	Settings.load_cfg()
	Settings.type2 = true
	Settings.war_painting = true
	Settings.cam_fx = 0
	Settings.apply()
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_view = BattleView.new()
	_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_view)
	await get_tree().process_frame
	Settings.apply_port(_view.port)
	var helper = preload("res://tests/inyeon.gd").new()
	var a: Array = DB.auto_place(helper._pick([], 7), "eorin")
	var b: Array = DB.auto_place(helper._pick([], 7), "hagik")
	helper.free()
	var r := RtBattle.new(5100).run(a, "eorin", 100, null, b, "hagik", 100, null, "", "", [], {"A": "auto", "B": "auto"})
	_view.play_res(r, "pvp")
	var at := float(_args.get("at", "4"))
	while _view.clock < at and not _view.finished:
		await get_tree().process_frame
	get_tree().process_frame.connect(func(): _t0 = Time.get_ticks_usec())
	RenderingServer.frame_pre_draw.connect(func():
		_proc += Time.get_ticks_usec() - _t0
		_t0 = Time.get_ticks_usec())
	RenderingServer.frame_post_draw.connect(func(): _rend += Time.get_ticks_usec() - _t0)
	var secs := float(_args.get("secs", "8"))
	await get_tree().process_frame
	_proc = 0.0
	_rend = 0.0
	var t_end := Time.get_ticks_usec() + int(secs * 1e6)
	var calls := 0.0
	var tproc := 0.0
	var hud0 := float(_view.field.prof.get("머리표", 0))
	var n := 0
	while Time.get_ticks_usec() < t_end and not _view.finished:
		await get_tree().process_frame
		calls += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
		tproc += Performance.get_monitor(Performance.TIME_PROCESS) * 1e6
		n += 1
	n = maxi(1, n)
	var hud_us := (float(_view.field.prof.get("머리표", 0)) - hud0) / n
	print("BADGE|badges=%s|frames=%d|proc_us=%.0f|time_process_us=%.0f|hud_draw_us=%.0f|render_cpu_us=%.0f|draw_calls=%.0f|fps=%.0f" % [str(_on), n, _proc / n, tproc / n, hud_us, _rend / n, calls / n, n / secs])
	get_tree().quit()


func _process(_d: float) -> void:
	if _view == null or _view.field == null or not _on:
		return
	var i := 0
	for sq: Squad in _view.field.order:
		if sq.alive:
			sq.statuses = SETS[i % SETS.size()].duplicate()
			i += 1
