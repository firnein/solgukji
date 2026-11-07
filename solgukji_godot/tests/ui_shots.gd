extends Node
## 편성 · 전투 탭 · 전투 · 결과창 캡처 (11/7 UI 정리) —— 실행: godot --path . --resolution 540x1200 res://tests/ui_shots.tscn -- --out=폴더 [--tag=이름] [--seed=3] [--play=9] [--page=deploy|war] [--open=war:fx] [--done=quest|pvp] [--shots=4] [--kind=quest|pvp] [--after=6 | --after=2,5,9] [--toasts=1] [--battle=0] [--report=1] [--speed=8] [--camp=B] [--rscroll=300,900]
## 자동 진행으로 그 페이즈까지 간 판을 페이지 화면(맨 위 · 아래로 넘김, --page=war 면 전투 탭)과 전투(6초 뒤)로 찍는다. 처음 뜨는 보급 시트 · 띠는 닫는다.
## --battle=0 이면 페이지만 찍고 끝낸다 (시드를 바꿔 가며 전투 탭 군단 효과 점검).
## --report=1 이면 전투를 --speed 배속으로 끝까지 돌리고 결과창(끝나고 1.4초 뒤에 뜬다)을 report_종류_태그.png 로 찍는다 (11/7 결과창 정리) ——
##   --rscroll=300,900 은 결과창 내용을 그 위치로 내려서 한 장씩 더(_s300 …), --camp=B 는 적군 탭으로 바꿔 한 장 더(_B).

func _ready() -> void:
	var args := {}
	for s in OS.get_cmdline_user_args():
		var kv := s.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	var out := str(args.get("out", "user://"))
	var tag := str(args.get("tag", "%dx%d" % [get_window().size.x, get_window().size.y]))
	var pg := str(args.get("page", "deploy"))
	PlayLog.enabled = false
	Run.dev_immortal = true
	var gs: GameScreen = load("res://scenes/game.tscn").instantiate()
	add_child(gs)
	await get_tree().process_frame
	var r := Run.new()
	r.new_game(int(args.get("seed", "3")))
	for i in int(args.get("play", "9")):
		r.dev_autoplay()
	if args.has("done"):      # --done=quest | pvp —— 이 페이즈의 토벌(과 대전)을 자동으로 치른 뒤 (전투 탭 '완료' 표시 · 결과 칸 점검, 11/7)
		r._dev_fight(r.start_quest())
		if str(args.done) == "pvp" and r.over == null:
			r._dev_fight(r.start_pvp())
	gs.run = r
	gs._title.visible = false
	for key in str(args.get("open", "")).split(",", false):      # --open=war:fx —— 접는 묶음을 펼친 채로 (전투 탭 군단 효과 표)
		gs._open[key] = true
	gs.go(pg)
	await get_tree().create_timer(0.6).timeout
	gs.close_sheet()
	gs._bands.clear()      # 보급 도착 · 선택권 띠도 걷는다 —— 페이지 가운데를 가린다
	gs._hide_band()
	if not args.has("toasts"):      # --toasts=1 이면 알림(보급 도착 등)을 지우지 않고 그대로 찍는다 (11/7 알림 자리 점검)
		for c in gs._toast_box.get_children():
			c.queue_free()
	await get_tree().create_timer(0.6).timeout
	var sc: ScrollContainer = gs._scroll
	if not sc.visible and gs._fixed.get_child_count() > 0 and gs._fixed.get_child(0) is ScrollContainer:
		sc = gs._fixed.get_child(0)      # 고정 페이지(전투 탭)는 페이지 안에 제 스크롤을 둔다 (11/7)
	var y := 0
	for i in int(args.get("shots", "4")):
		sc.scroll_vertical = y
		await get_tree().create_timer(0.3).timeout
		await _shot("%s/%s%d_%s.png" % [out, pg, i, tag])
		var vb := sc.get_v_scroll_bar()
		print("캡처 %s%d: 스크롤 %d (내용 %d · 창 %d)" % [pg, i, sc.scroll_vertical, int(vb.max_value), int(vb.page)])
		if sc.scroll_vertical < y:
			break
		y += int(sc.size.y * 0.8)
	if str(args.get("battle", "1")) == "0":
		get_tree().quit()
		return
	var kind := str(args.get("kind", "quest"))
	gs._start(kind)
	if args.has("report"):
		# 결과창 —— 빠르게 끝까지 돌리고(화면 배속만 올린다, 결과는 엔진이 이미 계산한 것) 결과창이 뜬 뒤 찍는다
		gs._battle._set_speed(float(args.get("speed", "8")))
		await gs._battle.ended
		await get_tree().create_timer(2.4).timeout
		await _shot("%s/report_%s_%s.png" % [out, kind, tag])
		for sy in str(args.get("rscroll", "")).split(",", false):
			if gs._report != null and gs._report.has_method("scroll_to"):
				gs._report.scroll_to(int(sy))
				await get_tree().process_frame
				await _shot("%s/report_%s_%s_s%s.png" % [out, kind, tag, sy])
		if args.has("camp") and gs._report != null:
			gs._report.camp = str(args.camp)
			gs._report._fill()
			await get_tree().process_frame
			await _shot("%s/report_%s_%s_%s.png" % [out, kind, tag, args.camp])
		get_tree().quit()
		return
	# --after=6 은 전투 6초 뒤 한 장. --after=2,5,9 처럼 쉼표로 여러 시점을 주면 quest_태그_t2.png · _t5 · _t9 로 (11/7 대군 양 끝 점검 —— 카메라 초점 전후를 같이)
	var ats := str(args.get("after", "6")).split(",", false)
	var t := 0.0
	for a in ats:
		await get_tree().create_timer(float(a) - t).timeout
		t = float(a)
		await _shot("%s/%s_%s%s.png" % [out, kind, tag, ("_t%s" % a) if ats.size() > 1 else ""])
	get_tree().quit()


func _shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
