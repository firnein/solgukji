extends Node
## 전투 성능 점검 · 병사 배치 캡처 (11/7 병사 배치 · 모바일 성능) —— 실행:
##   godot --path . --resolution 540x1200 res://tests/perf_probe.tscn -- [--kind=quest|pvp] [--play=9] [--seed=3] [--secs=20] [--skip=3]
##     [--gmul=1.5 탑뷰 병사 배율 (game_screen 이 읽는다)] [--tag=이름] [--out=폴더] [--speed=1.25]
##     [--hide=ground,men,under,fx,hud,cpu  층을 숨겨 그 비용을 뺀다] [--lv=N 부하 조절 단계 고정] [--lod=0 병사 수 LOD 끔]
##     [--gscatter=0 흐트러짐 끔 (11/7 아침 배치)] [--mobile=1 휴대폰 문턱으로 (PC 에서 휴대폰 단계 흉내)]
##     [--shots=2,5,9 그 초에 화면을 찍는다 (out/<tag>_t<초>.png)] [--zoom=2.5 가장 빽빽한 부대를 따라 그 배율로 다가간다]
##     [--count=1 병사 수만 찍고 끝 (판 고르기)] [--tierfig=0 11/12 등급별 인형 줄이기 · 고급 병사 장식 끔 (전후 비교)]
## 자동 진행으로 그 페이즈까지 간 판의 전투를 틀고(ui_shots 와 같은 판), skip 초 뒤부터 secs 초 동안 프레임마다 잰다 (vsync 끔 · fps 상한 없음):
##   fps · 프레임 시간(평균 · 상위 5% · 최대) · 처리 시간(process_frame → frame_pre_draw, 프레임 평균 —— 모든 _process 와 엔진 갱신)
##   · 스크립트최대(Performance.TIME_PROCESS = 지난 1초 중 가장 긴 process) · GPU 시간(뷰포트 측정) · 그리기 호출 · 스크립트 구간(War3D.prof)
##   · 계산 병사 · 살아 있는 병사 · 그린 인스턴스 · 쓰러지는 중 · 부하 단계
## 결과는 stdout 한 줄("PERF|" 접두, 표로 모으기 쉽게)과 --out 폴더의 perf_<tag>.txt 로. --secs=0 이면 재지 않는다 (캡처만).
## 11/7 전후 비교용으로 바꾸기 전 코드(Type2View 에 점검 변수가 없다)에서도 돈다 —— 점검 변수는 스크립트에 이름으로 넣는다

const T2_PATH := "res://scripts/field/type2_view.gd"
var _pf_t := 0
var _proc_us := 0
var _proc_n := 0


func _ready() -> void:
	var args := {}
	for s in OS.get_cmdline_user_args():
		var kv := s.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	var out := str(args.get("out", "user://"))
	var tag := str(args.get("tag", "%s_p%s" % [args.get("kind", "quest"), args.get("play", "9")]))
	var secs := float(args.get("secs", "20"))
	var skip := float(args.get("skip", "3"))
	var shots: Array = []
	for a in str(args.get("shots", "")).split(",", false):
		shots.append(float(a))
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	PlayLog.enabled = false
	Run.dev_immortal = true
	var t2s: Script = load(T2_PATH)
	if args.has("lv"):
		t2s.set("force_lv", int(args.lv))
	if args.has("lod"):
		t2s.set("lod_on", args.lod != "0")
	if args.has("gscatter"):
		t2s.set("scatter", float(args.gscatter))
	if args.has("budget"):
		t2s.set("budget_on", args.budget != "0")
	if args.has("tierfig"):
		t2s.set("tier_fig", args.tierfig != "0")
	if args.has("mobile"):
		t2s.set("mobile_test", args.mobile != "0")
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
	await get_tree().create_timer(0.4).timeout
	gs.close_sheet()
	for c in gs._toast_box.get_children():
		c.queue_free()
	await get_tree().create_timer(0.3).timeout
	gs._start(str(args.get("kind", "quest")))
	await get_tree().process_frame
	var bv: BattleView = gs._battle
	if args.has("speed"):
		bv._set_speed(float(args.speed))
	var t2: Type2View = bv.type2
	var field: War3D = bv.field
	var t_start := Time.get_ticks_usec()
	for h in str(args.get("hide", "")).split(",", false):
		match h:
			"ground": t2._ground.visible = false
			"men": if t2._gmm: t2._gmm.visible = false
			"cpu": t2._mm.visible = false
			"under": t2._under.visible = false
			"fx":
				if t2._fx_layer: t2._fx_layer.visible = false
				if t2._fx_add: t2._fx_add.visible = false
				if t2._label_layer: t2._label_layer.visible = false
			"hud": bv.hud.visible = false
	var men := 0
	for sq: Squad in field.order:
		men += sq.soldiers.size()
	if args.has("count"):
		var tiers := {}
		for sq: Squad in field.order:
			tiers[sq.tier] = int(tiers.get(sq.tier, 0)) + 1
		print("COUNT|%s|병사 %d|부대 %d|단계 %d|등급별 부대 %s" % [tag, men, field.order.size(), t2.load_lv, str(tiers)])
		get_tree().quit()
		return
	# 가장 빽빽한 부대 (면적당 병사) —— --zoom 이 따라간다
	var dense: Squad = null
	var best := -1.0
	for sq: Squad in field.order:
		var k := sq.soldiers.size() / maxf(1.0, sq.hw * sq.hd0)
		if k > best:
			best = k
			dense = sq
	var zoom := float(args.get("zoom", "0"))
	if not shots.is_empty():
		var tag_s := "%s%s" % [tag, ("_z%s" % args.zoom) if zoom > 0.0 else ""]
		for at in shots:
			while (Time.get_ticks_usec() - t_start) / 1e6 < at:
				_follow(t2, field, dense, zoom)
				await get_tree().process_frame
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png("%s/%s_t%s.png" % [out, tag_s, str(at).trim_suffix(".0")])
		var info := "SHOT|%s|병사 %d|빽빽한 부대 %s (%s · %d명 · 반폭 %.0f · 반깊이 %.0f · 간격 %.1f/%.1f)" % [tag_s, men, dense.key, dense.row.get("name", "?"),
			dense.soldiers.size(), dense.hw, dense.hd0, dense.sp, dense.spr]
		print(info)
		if secs <= 0.0:
			get_tree().quit()
			return
	var rid := get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(rid, true)
	get_tree().process_frame.connect(_on_pf)
	RenderingServer.frame_pre_draw.connect(_on_pre_draw)
	while (Time.get_ticks_usec() - t_start) / 1e6 < skip:
		_follow(t2, field, dense, zoom)
		await get_tree().process_frame
	var prof0 := field.prof.duplicate()
	var frames0: int = field.prof.get("_frames", 0)
	_proc_us = 0
	_proc_n = 0
	var dts := PackedFloat32Array()
	var proc_sum := 0.0
	var gpu_sum := 0.0
	var rcpu_sum := 0.0
	var calls_sum := 0.0
	var prims_sum := 0.0
	var figs_sum := 0.0
	var dying_sum := 0.0
	var alive_sum := 0.0
	var lv_sum := 0.0
	var lv_max := 0
	var n := 0
	var t_end := Time.get_ticks_usec() + int(secs * 1e6)
	while Time.get_ticks_usec() < t_end:
		_follow(t2, field, dense, zoom)
		await get_tree().process_frame
		var dt := get_process_delta_time()
		dts.append(dt)
		proc_sum += Performance.get_monitor(Performance.TIME_PROCESS)
		gpu_sum += RenderingServer.viewport_get_measured_render_time_gpu(rid)
		rcpu_sum += RenderingServer.viewport_get_measured_render_time_cpu(rid)
		calls_sum += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
		prims_sum += Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
		var shown = t2.get("gpu_shown")
		figs_sum += t2.drawn_figs + (int(shown) if shown != null else t2.gpu_count)
		var dy := 0
		for k in t2._dying:
			dy += t2._dying[k].size()
		dying_sum += dy
		var al := 0
		for sq: Squad in field.order:
			al += sq._alive
		alive_sum += al
		lv_sum += t2.load_lv
		lv_max = maxi(lv_max, t2.load_lv)
		n += 1
	var frames: int = field.prof.get("_frames", 0) - frames0
	var sorted := dts.duplicate()
	sorted.sort()
	var tot := 0.0
	for d in dts:
		tot += d
	var p95: float = sorted[int(floor(sorted.size() * 0.95))] if sorted.size() > 0 else 0.0
	var mx: float = sorted[sorted.size() - 1] if sorted.size() > 0 else 0.0
	var fps := n / maxf(tot, 0.001)
	# 스크립트 구간 (프레임당 ms) —— War3D.pt 가 모은 것
	var secs_txt := []
	var keys := field.prof.keys()
	keys.sort()
	for k in keys:
		if k == "_frames":
			continue
		var us: float = float(field.prof[k]) - float(prof0.get(k, 0))
		var ms := us / 1000.0 / maxf(1.0, frames)
		if ms >= 0.02:
			secs_txt.append("%s %.2f" % [k, ms])
	var lod = t2s.get("lod_on")
	# '처리' 는 프레임마다 process_frame → frame_pre_draw (모든 _process · 엔진 갱신, 그리기 전까지)의 평균. '스크립트최대' 는 TIME_PROCESS(지난 1초 최대)의 평균
	var line := "PERF|%s|병사 %d|산 %.0f|그린 %.0f|쓰러짐 %.0f|fps %.1f|프레임 %.2fms|상위5%% %.2fms|최대 %.2fms|처리 %.2fms|스크립트최대 %.2fms|GPU %.2fms|렌더CPU %.2fms|호출 %.0f|기본도형 %.0fk|단계 평균 %.2f 최대 %d|배율 %s|LOD %s|숨김 %s" % [
		tag, men, alive_sum / n, figs_sum / n, dying_sum / n, fps, tot / n * 1000.0, p95 * 1000.0, mx * 1000.0,
		_proc_us / 1000.0 / maxf(1.0, _proc_n), proc_sum / n * 1000.0, gpu_sum / n, rcpu_sum / n, calls_sum / n, prims_sum / n / 1000.0, lv_sum / n, lv_max,
		args.get("gmul", "1.5"), "-" if lod == null else ("켬" if lod else "끔"), args.get("hide", "-")]
	print(line)
	print("  구간(ms/프레임): " + " · ".join(secs_txt))
	var f := FileAccess.open("%s/perf_%s.txt" % [out, tag], FileAccess.WRITE)
	if f:
		f.store_line(line)
		f.store_line("  구간(ms/프레임): " + " · ".join(secs_txt))
	get_tree().quit()


## --zoom —— 빽빽한 부대를 따라 다가간다 (카메라 초점을 매 프레임 그 부대 자리로)
func _follow(t2: Type2View, field: War3D, sq: Squad, zoom: float) -> void:
	if zoom <= 0.0 or sq == null or sq.state == "gone":
		return
	t2._focus = {"c": sq.pos, "mul": zoom, "until": field.clock + 1.0, "pri": 9}
	t2._want_scale = clampf(t2._base_scale * zoom, 0.3, 4.0)
	t2._want_center = sq.pos


## 처리 시간 —— process_frame(모든 _process 직전) → frame_pre_draw(그리기 직전)
func _on_pf() -> void:
	_pf_t = Time.get_ticks_usec()


func _on_pre_draw() -> void:
	if _pf_t > 0:
		_proc_us += Time.get_ticks_usec() - _pf_t
		_proc_n += 1
		_pf_t = 0
