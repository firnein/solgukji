extends Node
## 화면(UI) 성능 점검 (11/15 퍼포먼스 최적화) —— 창이 있어야 한다:
##   godot --path . --resolution 720x1280 res://tests/ui_perf.tscn -- [--seed=3] [--play=9,28] [--tag=이름]
## 판(자동 진행 play 단계)마다 탭 · 시트를 열며 잰다 (vsync 끔):
##   짓기 = go()/render()/card_info() 스크립트 시간 (페이지 노드 만들기)
##   첫 프레임 = 그 뒤 첫 프레임(자리 잡기 + 타일 처음 그리기), 둘째 = 그다음 프레임
##   다시 = 같은 페이지 render() 다섯 번 평균 (작은 상태 변화마다 치르는 값) + 그 뒤 첫 프레임
##   가만 = 아무것도 안 할 때 프레임 평균(처리 = process_frame → frame_pre_draw) · 그리기 호출 · 노드 수
## 끝에 그림 캐시 장수 · 텍스처 메모리(MB). 결과는 "UIPERF|" 줄로

var _pf_t := 0
var _proc_us := 0
var _proc_n := 0
var _tag := ""


func _ready() -> void:
	var args := {}
	for s in OS.get_cmdline_user_args():
		var kv := s.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	_tag = str(args.get("tag", "ui"))
	DB.dbg_full = args.has("full")
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	PlayLog.enabled = false
	Run.dev_immortal = true
	Run.delete_save()
	get_tree().process_frame.connect(func(): _pf_t = Time.get_ticks_usec())
	RenderingServer.frame_pre_draw.connect(func():
		if _pf_t > 0:
			_proc_us += Time.get_ticks_usec() - _pf_t
			_proc_n += 1
			_pf_t = 0)
	var gs: GameScreen = load("res://scenes/game.tscn").instantiate()
	add_child(gs)
	await _wait(0.5)
	_mem("제목")
	for ps in str(args.get("play", "9,28")).split(",", false):
		var r := Run.new()
		r.new_game(int(args.get("seed", "3")))
		for i in int(ps):
			r.dev_autoplay()
		r.grain = maxi(r.grain, 30)
		gs.run = r
		gs._title.visible = false
		var who := "p%s" % ps
		for pg in ["draw", "forge", "deploy", "war", "more"]:
			await _page(gs, who, pg)
		# 조합 탭 「더 보기」 까지 펼친 상태
		gs.go("forge")
		await _frames(3)
		var mb := gs._find_btn(gs._body, "더 보기")
		if mb == null:
			for b in _all_buttons(gs._body):
				if b.text.begins_with("더 보기"):
					mb = b
		if mb != null:
			var t0 := Time.get_ticks_usec()
			mb.pressed.emit()
			var worst := 0.0
			var n := 0
			while gs._body.is_inside_tree() and n < 60:
				var f0 := Time.get_ticks_usec()
				await get_tree().process_frame
				worst = maxf(worst, (Time.get_ticks_usec() - f0) / 1000.0)
				n += 1
			print("UIPERF|%s|%s|forge 더 보기|전체 %.1fms|가장 긴 프레임 %.1fms" % [_tag, who, (Time.get_ticks_usec() - t0) / 1000.0, worst])
			await _idle(gs, who, "forge(펼침)")
			await _again(gs, who, "forge(펼침)")
		# 카드 상세 열기 · 닫기
		var k7 := ""
		for k in DB.by_tier(7):
			if DB.inyeon_card(k):
				k7 = k
				break
		for k in [k7, r.pool().keys()[0]]:
			if k == "":
				continue
			var t0 := Time.get_ticks_usec()
			gs.card_info(k)
			var b := (Time.get_ticks_usec() - t0) / 1000.0
			var f1 := await _frame_ms()
			var f2 := await _frame_ms()
			await _wait(0.5)
			t0 = Time.get_ticks_usec()
			gs.close_sheet()
			var c := (Time.get_ticks_usec() - t0) / 1000.0
			var f3 := await _frame_ms()
			await _wait(0.4)
			print("UIPERF|%s|%s|카드 상세 %s|짓기 %.1fms|첫 프레임 %.1fms|둘째 %.1fms|닫기 %.1fms + %.1fms" % [_tag, who, DB.C[k].name, b, f1, f2, c, f3])
		for sh in ["inyeon", "shop", "news", "recipe"]:
			var t0 := Time.get_ticks_usec()
			match sh:
				"inyeon":
					gs.go("deploy")
					await _frames(3)
					t0 = Time.get_ticks_usec()
					gs.deploy.inyeon_sheet()
				"shop": gs._shop_sheet()
				"news": gs._news_sheet()
				"recipe": gs.recipe_sheet(DB.D.RECDEF[DB.D.RECDEF.size() - 1][0])
			var b := (Time.get_ticks_usec() - t0) / 1000.0
			var f1 := await _frame_ms()
			var f2 := await _frame_ms()
			await _wait(0.4)
			gs.close_sheet()
			await _wait(0.4)
			print("UIPERF|%s|%s|시트 %s|짓기 %.1fms|첫 프레임 %.1fms|둘째 %.1fms" % [_tag, who, sh, b, f1, f2])
		_mem(who)
	get_tree().quit()


func _all_buttons(n: Node) -> Array:
	var out := []
	for c in n.get_children():
		if c is Button:
			out.append(c)
		out.append_array(_all_buttons(c))
	return out


func _page(gs: GameScreen, who: String, pg: String) -> void:
	var t0 := Time.get_ticks_usec()
	gs.go(pg)
	var b := (Time.get_ticks_usec() - t0) / 1000.0
	var f1 := await _frame_ms()
	var f2 := await _frame_ms()
	await _wait(0.4)
	gs.close_sheet()
	gs._bands.clear()
	gs._hide_band()
	for c in gs._toast_box.get_children():
		c.queue_free()
	await _wait(0.5)
	print("UIPERF|%s|%s|%s|짓기 %.1fms|첫 프레임 %.1fms|둘째 %.1fms" % [_tag, who, pg, b, f1, f2])
	await _again(gs, who, pg)
	await _idle(gs, who, pg)


func _again(gs: GameScreen, who: String, pg: String) -> void:
	var sum := 0.0
	var fsum := 0.0
	for i in 5:
		var t0 := Time.get_ticks_usec()
		gs.render()
		sum += (Time.get_ticks_usec() - t0) / 1000.0
		fsum += await _frame_ms()
		await _frames(2)
	print("UIPERF|%s|%s|%s 다시|짓기 %.1fms|첫 프레임 %.1fms" % [_tag, who, pg, sum / 5.0, fsum / 5.0])


func _idle(_gs: GameScreen, who: String, pg: String) -> void:
	await _frames(5)
	_proc_us = 0
	_proc_n = 0
	var t0 := Time.get_ticks_usec()
	var n := 0
	var calls := 0.0
	while n < 150:
		await get_tree().process_frame
		calls += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
		n += 1
	var ms := (Time.get_ticks_usec() - t0) / 1000.0 / n
	print("UIPERF|%s|%s|%s 가만|프레임 %.3fms|처리 %.3fms|호출 %.0f|노드 %d" % [_tag, who, pg, ms, _proc_us / 1000.0 / maxf(1.0, _proc_n),
		calls / n, int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))])


func _mem(who: String) -> void:
	print("UIPERF|%s|%s|메모리|그림 캐시 %d장|텍스처 %.1fMB|비디오 %.1fMB|정적 %.1fMB|노드 %d" % [_tag, who, DB.prof_cache_size(),
		Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED) / 1048576.0, Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0,
		Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0, int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))])
	# 텍스처를 크기별로 모아 본다 (무엇이 메모리를 먹는지) —— 큰 것부터 여덟 묶음
	var by := {}
	var seen := {}
	for key in DB._portrait_cache:
		var t: Texture2D = DB._portrait_cache[key]
		if t == null or seen.has(t):
			continue
		seen[t] = true
		var name_: String = str(key).trim_suffix("#s").get_file()
		var kind := "반쪽" if str(key).ends_with("#s") and not DB._portrait_cache.has(str(key).trim_suffix("#s")) else ("얼굴" if str(key).contains("/faces/") else ("신화·장면" if name_.ends_with("_신화") or name_.ends_with("_장면") else ("원본" if str(key).contains("/portraits/") else "그 밖")))
		if str(key).ends_with("#s") and DB._portrait_cache.get(str(key).trim_suffix("#s")) != t:
			kind = "반쪽"
		if not by.has(kind):
			by[kind] = [0, 0.0]
		by[kind][0] += 1
		by[kind][1] += t.get_width() * t.get_height() * 4.0 * (1.333 if maxi(t.get_width(), t.get_height()) > 96 else 1.0)
	var parts := []
	for k in by:
		parts.append("%s %d장 %.0fMB" % [k, by[k][0], by[k][1] / 1048576.0])
	print("UIPERF|%s|%s|초상 캐시|%s" % [_tag, who, " · ".join(parts)])


## 다음 프레임 하나가 끝날 때까지(그리기 포함) 걸린 ms
func _frame_ms() -> float:
	var t0 := Time.get_ticks_usec()
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	return (Time.get_ticks_usec() - t0) / 1000.0


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _wait(s: float) -> void:
	await get_tree().create_timer(s).timeout
