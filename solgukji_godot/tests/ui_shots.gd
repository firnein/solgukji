extends Node
## 편성 · 전투 탭 · 전투 · 결과창 캡처 (11/7 UI 정리) —— 실행: godot --path . --resolution 540x1200 res://tests/ui_shots.tscn -- --out=폴더 [--tag=이름] [--seed=3] [--play=9] [--page=deploy|war] [--seg=hand|syn|item] [--wait=초] [--open=hand|item | --open=war:fx] [--done=quest|pvp] [--shots=4] [--kind=quest|pvp] [--after=6 | --after=2,5,9] [--toasts=1] [--battle=0] [--report=1] [--speed=8] [--camp=B] [--rscroll=300,900]
## 자동 진행으로 그 페이즈까지 간 판을 페이지 화면(맨 위 · 아래로 넘김, --page=war 면 전투 탭)과 전투(6초 뒤)로 찍는다. 처음 뜨는 보급 시트 · 띠는 닫는다.
## --seg 는 편성 아래 탭을 연 채로, --wait 는 띠가 사라진 뒤 찍는다. --open=hand|item 은 편성 페이지를 찍은 뒤 그 탭을 눌러 여는 연출(6장 + 열린 상태)을, 그 밖의 --open=키 는 접는 묶음(_open)을 펼친 채로 찍는다.
## --battle=0 이면 페이지만 찍고 끝낸다 (시드를 바꿔 가며 전투 탭 군단 효과 점검).
## --report=1 이면 전투를 --speed 배속으로 끝까지 돌리고 결과창(끝나고 1.4초 뒤에 뜬다)을 report_종류_태그.png 로 찍는다 (11/7 결과창 정리) ——
##   --rscroll=300,900 은 결과창 내용을 그 위치로 내려서 한 장씩 더(_s300 …), --camp=B 는 적군 탭으로 바꿔 한 장 더(_B).
##   [--when=charge | charge_foe] 고유기 기 모으기(charge_foe 는 적 것)가 시작되는 순간을 기다렸다가 +0.05 · 0.9 · 1.7 · 2.6초에 찍는다 (quest_태그_c005.png …) —— 시점을 미리 알 수 없어서 (11/7 기 모으기 연출)
##   [--direct=1] 직접 지휘로 (적 고유기 예고 · 군령 줄까지)   [--style=3d] 타입2 대신 3D 전장으로 (저장된 설정과 상관없이)

func _ready() -> void:
	var args := {}
	for s in OS.get_cmdline_user_args():
		var kv := s.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	var out := str(args.get("out", "user://"))
	if str(args.get("style", "")) == "3d":
		Settings.type2 = false
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
	if args.has("seg"):      # --seg=hand|syn|item —— 편성 아래 탭을 연 채로 찍는다 (11/7 편성판 찌그러짐 점검). 열린 탭이 편성판을 밀지 않는지 본다
		gs.deploy.seg = str(args.seg)
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
	if args.has("wait"):      # --wait=초 —— 보급 선택권 띠(2초쯤 떠 있다)가 사라진 뒤 찍으려면 1.5 쯤 (11/7 편성 레이아웃 점검)
		await get_tree().create_timer(float(args.wait)).timeout
	var sc: ScrollContainer = gs._scroll
	if pg != "deploy" and not sc.visible and gs._fixed.get_child_count() > 0 and gs._fixed.get_child(0) is ScrollContainer:
		sc = gs._fixed.get_child(0)      # 고정 페이지(전투 탭)는 페이지 안에 제 스크롤을 둔다 (11/7). 편성은 제 연출(--seg · --open)대로 두려고 뺀다
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
	if str(args.get("open", "")) in ["hand", "item"]:      # --open=hand|item —— 닫힌 채 찍은 뒤 탭을 눌러 여는 연출을 0.05초 간격 6장(deploy_open0~5_태그.png), 이어서 다 열린 상태 한 장(deploy_opened_태그.png) (11/7 편성판 고정 점검)
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
	if str(args.get("battle", "1")) == "0":
		get_tree().quit()
		return
	var kind := str(args.get("kind", "quest"))
	gs._start(kind)
	if args.has("direct"):      # 게임 화면의 set_direct 는 11/4 이후 늘 끈다 —— 점검 화면(main.gd)처럼 플래그를 바로 켠다
		gs._battle.direct = true
		if gs._battle._cmd_row:
			gs._battle._cmd_row.visible = true
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
