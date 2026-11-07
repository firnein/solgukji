extends Node
## 편성 · 전투 화면 캡처 (11/7 UI 정리) —— 실행: godot --path . --resolution 540x1200 res://tests/ui_shots.tscn -- --out=폴더 [--tag=이름] [--play=9] [--kind=quest|pvp] [--after=6 | --after=2,5,9] [--toasts=1]
##   [--when=charge | charge_foe] 고유기 기 모으기(charge_foe 는 적 것)가 시작되는 순간을 기다렸다가 +0.05 · 0.9 · 1.7 · 2.6초에 찍는다 (quest_태그_c005.png …) —— 시점을 미리 알 수 없어서 (11/7 기 모으기 연출)
##   [--direct=1] 직접 지휘로 (적 고유기 예고 · 군령 줄까지)   [--style=3d] 타입2 대신 3D 전장으로 (저장된 설정과 상관없이)
## 자동 진행으로 그 페이즈까지 간 판을 편성 화면(맨 위 · 아래로 넘김)과 전투(6초 뒤)로 찍는다. 처음 뜨는 보급 시트는 닫는다.

func _ready() -> void:
	var args := {}
	for s in OS.get_cmdline_user_args():
		var kv := s.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	var out := str(args.get("out", "user://"))
	if str(args.get("style", "")) == "3d":
		Settings.type2 = false
	var tag := str(args.get("tag", "%dx%d" % [get_window().size.x, get_window().size.y]))
	PlayLog.enabled = false
	Run.dev_immortal = true
	var gs: GameScreen = load("res://scenes/game.tscn").instantiate()
	add_child(gs)
	await get_tree().process_frame
	var r := Run.new()
	r.new_game(int(args.get("seed", "3")))
	for i in int(args.get("play", "9")):
		r.dev_autoplay()
	gs.run = r
	gs._title.visible = false
	gs.go("deploy")
	await get_tree().create_timer(0.6).timeout
	gs.close_sheet()
	if not args.has("toasts"):      # --toasts=1 이면 알림(보급 도착 등)을 지우지 않고 그대로 찍는다 (11/7 알림 자리 점검)
		for c in gs._toast_box.get_children():
			c.queue_free()
	await get_tree().create_timer(0.6).timeout
	var y := 0
	for i in 4:
		gs._scroll.scroll_vertical = y
		await get_tree().create_timer(0.3).timeout
		await _shot("%s/deploy%d_%s.png" % [out, i, tag])
		if gs._scroll.scroll_vertical < y:
			break
		y += int(gs._scroll.size.y * 0.8)
	var kind := str(args.get("kind", "quest"))
	gs._start(kind)
	if args.has("direct"):      # 게임 화면의 set_direct 는 11/4 이후 늘 끈다 —— 점검 화면(main.gd)처럼 플래그를 바로 켠다
		gs._battle.direct = true
		if gs._battle._cmd_row:
			gs._battle._cmd_row.visible = true
	var t := 0.0
	var when := str(args.get("when", ""))
	if when == "charge" or when == "charge_foe":
		var t0 := Time.get_ticks_msec()
		while not _charging(gs._battle, when == "charge_foe") and Time.get_ticks_msec() - t0 < 80000:
			await get_tree().process_frame
		var base := Time.get_ticks_msec()
		for d in [0.05, 0.9, 1.7, 2.6]:
			var left: float = float(d) - (Time.get_ticks_msec() - base) / 1000.0
			if left > 0.0:
				await get_tree().create_timer(left).timeout
			await _shot("%s/%s_%s_c%s.png" % [out, kind, tag, str(d).replace(".", "")])
		t = (Time.get_ticks_msec() - t0) / 1000.0
	# --after=6 은 전투 6초 뒤 한 장. --after=2,5,9 처럼 쉼표로 여러 시점을 주면 quest_태그_t2.png · _t5 · _t9 로 (11/7 대군 양 끝 점검 —— 카메라 초점 전후를 같이)
	var ats := str(args.get("after", "6")).split(",", false)
	for a in ats:
		await get_tree().create_timer(maxf(0.01, float(a) - t)).timeout
		t = maxf(t, float(a))
		await _shot("%s/%s_%s%s.png" % [out, kind, tag, ("_t%s" % a) if ats.size() > 1 else ""])
	get_tree().quit()


## 고유기 기 모으기 중인가 —— HUD 의 charges(11/7) · 예전 안내문("기를 모은다") · 적 예고 어느 것이든. foe 면 적 것만 (--when=charge_foe)
func _charging(bv, foe := false) -> bool:
	if bv == null or bv.hud == null:
		return false
	if foe:
		return bv.warn_until > bv.clock
	var ch = bv.hud.get("charges")
	if ch is Dictionary and not ch.is_empty():
		return true
	if bv.hud.ann != null and "기를 모은다" in str(bv.hud.ann.text):
		return true
	return bv.warn_until > bv.clock


func _shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
