extends Node
## 편성 · 전투 화면 캡처 (11/7 UI 정리) —— 실행: godot --path . --resolution 540x1200 res://tests/ui_shots.tscn -- --out=폴더 [--tag=이름] [--play=9] [--kind=quest|pvp] [--after=6 | --after=2,5,9] [--toasts=1] [--seg=hand|syn|item] [--wait=초] [--open=hand|item]
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
	if args.has("seg"):      # --seg=hand|syn|item —— 편성 아래 탭을 연 채로 찍는다 (11/7 편성판 찌그러짐 점검). 열린 탭이 편성판을 밀지 않는지 본다
		gs.deploy.seg = str(args.seg)
	gs.go("deploy")
	await get_tree().create_timer(0.6).timeout
	gs.close_sheet()
	if not args.has("toasts"):      # --toasts=1 이면 알림(보급 도착 등)을 지우지 않고 그대로 찍는다 (11/7 알림 자리 점검)
		for c in gs._toast_box.get_children():
			c.queue_free()
	await get_tree().create_timer(0.6).timeout
	if args.has("wait"):      # --wait=초 —— 보급 선택권 띠(2초쯤 떠 있다)가 사라진 뒤 찍으려면 1.5 쯤 (11/7 편성 레이아웃 점검)
		await get_tree().create_timer(float(args.wait)).timeout
	var y := 0
	for i in 4:
		gs._scroll.scroll_vertical = y
		await get_tree().create_timer(0.3).timeout
		await _shot("%s/deploy%d_%s.png" % [out, i, tag])
		if gs._scroll.scroll_vertical < y:
			break
		y += int(gs._scroll.size.y * 0.8)
	if args.has("open"):      # --open=hand|item —— 닫힌 채 찍은 뒤 탭을 눌러 여는 연출을 0.05초 간격 6장(deploy_open0~5_태그.png), 이어서 다 열린 상태 한 장(deploy_opened_태그.png) (11/7 편성판 고정 점검)
		var want := "보유" if str(args.open) == "hand" else "보급품"
		for b in gs._fixed.find_children("*", "Button", true, false):
			if b.text.begins_with(want):
				b.pressed.emit()
				break
		for i in 6:
			await get_tree().create_timer(0.05).timeout
			await _shot("%s/deploy_open%d_%s.png" % [out, i, tag])
		await get_tree().create_timer(0.5).timeout
		await _shot("%s/deploy_opened_%s.png" % [out, tag])
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
