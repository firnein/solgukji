extends Control
## 11/24 삽화 병사 인형 점검 —— 병종별 인형 키 · 등급 차등 · 신화 전용 그림 (창이 뜬다 · 휴대폰 세로):
##   godot --path . --resolution 719x1280 res://tests/tier_sprite_shot.tscn -- [--ta=3,4,5,6,7,8,5,7,8] [--tb=5] [--tags=창병,...]
##     [--shots=1.5] [--zoom=1.6] [--fx=0 --fy=0] [--out=폴더] [--tag=이름] [--seed=5] [--tierfx=0 등급 차등 끔(전)]
## 칸마다 그 등급 · 병종 카드를 뽑아 삽화 화면으로 틀고, 부대마다 인형 키를 찍는다:
##   FIGH|진영|병종|등급|열|반폭|인형 키(px)   · 끝에 FIGAVG|병종|평균 키|부대 수
## 그리기만 보는 점검 —— 전투 결과 · 저장은 건드리지 않는다 (PlayLog 끔).

var _args := {}


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
	var wps: Script = load("res://scripts/field/war_painting.gd")
	if _args.has("tierfx") and "tier_fx" in wps:
		wps.set("tier_fx", str(_args.tierfx) != "0")
	var view := BattleView.new()
	view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(view)
	await get_tree().process_frame
	Settings.apply_port(view.port)
	var sd := int(_args.get("seed", "5"))
	var ta: Array = str(_args.get("ta", "3,4,5,6,7,8,5,7,8")).split(",", false)
	var tb: Array = str(_args.get("tb", "5")).split(",", false)
	var tags: Array = str(_args.get("tags", "창병,창병,창병,창병,창병,창병,궁병,궁병,궁병")).split(",", false)
	var tags_b: Array = str(_args.get("tagsb", ",".join(tags))).split(",", false)
	var bt := {"kind": "pvp", "a": _side(ta, tags), "b": _side(tb, tags_b), "seed": sd, "title": "병사 인형 점검", "foe": "적군", "inputs": []}
	view.play(bt, false)
	view._set_speed(1.0)
	var out := str(_args.get("out", "user://"))
	var tag := str(_args.get("tag", "tiersprite"))
	var wp = view.type2.painting if view.type2 != null else null
	if wp == null:
		print("FIGH|삽화 화면이 아님")
		get_tree().quit()
		return
	var zoom := float(_args.get("zoom", "0"))
	var measured := false
	for a in str(_args.get("shots", "1.5")).split(",", false):
		while view.clock < float(a):
			if zoom > 0.0:
				_follow(view, zoom)
			await get_tree().process_frame
		if not measured:
			measured = true
			_measure(view, wp)
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("%s/%s_t%s.png" % [out, tag, str(a).trim_suffix(".0")])
	# --perf=초 —— 찍은 뒤 그 초 동안 프레임 시간 · GPU 시간 · 그리기 호출 평균 (vsync 끔 · fps 상한 없음, --tierfx=0 과 견준다)
	var perf := float(_args.get("perf", "0"))
	if perf > 0.0:
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		Engine.max_fps = 0
		RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
		var frames := 0
		var gpu := 0.0
		var calls := 0
		var t0 := Time.get_ticks_usec()
		while (Time.get_ticks_usec() - t0) / 1e6 < perf:
			await RenderingServer.frame_post_draw
			frames += 1
			gpu += RenderingServer.viewport_get_measured_render_time_gpu(get_viewport().get_viewport_rid())
			calls += int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
		var ms := (Time.get_ticks_usec() - t0) / 1000.0 / maxi(frames, 1)
		print("PERF|tierfx %s|프레임 %.2fms|GPU %.2fms|그리기 호출 %.1f|인형 %d" % [str(_args.get("tierfx", "1")), ms, gpu / maxi(frames, 1), float(calls) / maxi(frames, 1), int(wp.figure_count)])
	get_tree().quit()


## 부대마다 인형 키 —— war_painting._figure_height 를 그대로 부른다 (그리는 값과 같다)
func _measure(view: BattleView, wp) -> void:
	var sums := {}
	for sq: Squad in view.field.order:
		var form = wp.formations.get(sq.key)
		if form == null:
			continue
		var h := 0.0      # 실제로 그린 인형 키 (묶음 배열 _figs 의 키 칸 평균 —— 군기 칸 16/17 은 뺀다)
		var n := 0
		for i in int(wp.figure_count):
			var cell: float = wp._figs[i * wp.FIG_W + 3]
			if wp._fig_sq[i] == sq and (cell < 16.0 or cell >= 18.0):
				h += wp._figs[i * wp.FIG_W + 2]
				n += 1
		if n == 0:
			continue
		h /= n
		var sc: float = wp._pk(form.center)
		var at: Vector2 = wp.get_global_transform_with_canvas() * wp._pm(form.center)      # 부대 가운데 화면(뷰포트) 좌표 (잘라 견주기용)
		print("FIGH|%s|%s|등급 %d|열 %d|반폭 %.0f|원근 %.2f|키 %.1f|키/원근 %.1f|화면 %d,%d" % [sq.camp, sq.tag, sq.tier, form.cols, sq.hw, sc, h, h / sc, int(at.x), int(at.y)])
		var k := sq.tag
		if not sums.has(k):
			sums[k] = [0.0, 0, 0.0]
		sums[k][0] += h
		sums[k][1] += 1
		sums[k][2] += h / sc
	for k in sums:
		print("FIGAVG|%s|키 %.1f|키/원근 %.1f|%d" % [k, sums[k][0] / sums[k][1], sums[k][2] / sums[k][1], sums[k][1]])
	print("FIGDRAW|인형 %d" % int(wp.figure_count))


## 아군 한가운데로 다가간다 (등급 차이를 가까이서)
func _follow(view: BattleView, zoom: float) -> void:
	var t2: Type2View = view.type2
	var c := Vector2.ZERO
	var n := 0
	for sq: Squad in view.field.order:
		if sq.camp == "A" and sq.alive:
			c += sq.pos
			n += 1
	if n > 0:
		t2._focus = {"c": c / n + Vector2(float(_args.get("fx", "0")), float(_args.get("fy", "0"))), "mul": zoom, "until": view.field.clock + 0.5, "pri": 9}


func _side(tiers: Array, tags: Array) -> Dictionary:
	var deck := []
	for i in 9:
		var t := int(tiers[i % tiers.size()])
		var tg := str(tags[i % tags.size()])
		var pool := DB.by_tier(t).filter(func(k): return not DB.is_kiin(k) and DB.C[k].kind != "retired" and not deck.has(k))
		pool.sort()
		var pick := ""
		for k in pool:
			if DB.C[k].tag == tg:
				pick = k
				break
		if pick == "" and not pool.is_empty():
			pick = pool[0]
		if pick != "":
			deck.append(pick)
	var cards := DB.auto_place(deck, "eorin")
	return {"cards": cards, "form": "eorin", "morale": 100, "tac": "균형", "equip": []}
