extends Node
## 편성 · 전투 화면 캡처 (11/7 UI 정리) —— 실행: godot --path . --resolution 540x1200 res://tests/ui_shots.tscn -- --out=폴더 [--tag=이름] [--play=9] [--kind=quest|pvp] [--after=6 | --after=2,5,9] [--toasts=1]
## 자동 진행으로 그 페이즈까지 간 판을 편성 화면(맨 위 · 아래로 넘김)과 전투(6초 뒤)로 찍는다. 처음 뜨는 보급 시트는 닫는다.

func _ready() -> void:
	var args := {}
	for s in OS.get_cmdline_user_args():
		var kv := s.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	var out := str(args.get("out", "user://"))
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
	gs._start(str(args.get("kind", "quest")))
	# --after=6 은 전투 6초 뒤 한 장. --after=2,5,9 처럼 쉼표로 여러 시점을 주면 quest_태그_t2.png · _t5 · _t9 로 (11/7 대군 양 끝 점검 —— 카메라 초점 전후를 같이)
	var ats := str(args.get("after", "6")).split(",", false)
	var t := 0.0
	for a in ats:
		await get_tree().create_timer(float(a) - t).timeout
		t = float(a)
		await _shot("%s/%s_%s%s.png" % [out, args.get("kind", "quest"), tag, ("_t%s" % a) if ats.size() > 1 else ""])
	get_tree().quit()


func _shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
