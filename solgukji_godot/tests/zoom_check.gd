extends Control
## 전투 화면 확대 · 카메라 점검 (12/예: 사용자 "유닛이 작아 답답하다")
## 실행: godot --path <프로젝트> --resolution 540x1200 res://tests/zoom_check.tscn -- --shots=0.3,10,25 --tag=before [--zoom=0] [--png] [--seed=5100] [--legend]
## 정해진 전투 시각마다 화면 크기 · 배율 · 부대 화면 자리 · 인형 키 · 화면 밖으로 나간 부대 수를 글로 찍는다 (캡처는 --png 일 때만)
func _ready() -> void:
	var args := {}
	for arg in OS.get_cmdline_user_args():
		var kv := arg.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	get_tree().create_timer(240.0).timeout.connect(func(): get_tree().quit(1))
	PlayLog.enabled = false
	Settings.load_cfg()
	Settings.type2 = true
	Settings.war_painting = true
	Settings.cam_fx = int(args.get("cam-fx", "1"))
	Settings.ult_fx = 2
	if args.has("zoom"):
		Settings.zoom_cam = int(args.zoom) != 0
	Settings.apply()
	Engine.max_fps = 60
	if args.has("perf"):      # 프레임 시간 측정 —— 수직동기 끄고 최대 속도 (PC 재현용, 휴대폰 실측 아님)
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		Engine.max_fps = 0
	theme = UI.theme()
	var view := BattleView.new()
	view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(view)
	await get_tree().process_frame
	var helper = preload("res://tests/formation_preview.gd").new()
	var a: Array = DB.auto_place(helper._cards(["주유", "육손", "제갈량", "방통", "감녕", "황개", "정보", "조운", "관우"]), "eorin")
	var b: Array = DB.auto_place(helper._cards(["조조", "하후연", "사마의", "마초", "허저", "곽가", "손권", "여포", "화타"]), "hagik")
	if args.has("legend"):
		var decks = preload("res://tests/battle_lab_decks.gd")
		var rng := RandomNumberGenerator.new()
		rng.seed = 5100
		var counts := [0, 0, 0, 0, 9, 0, 0, 0, 0]
		a = DB.auto_place(decks.make_mix(counts, rng), "eorin")
		b = DB.auto_place(decks.make_mix(counts, rng), "hagik")
	helper.free()
	var result := RtBattle.new(int(args.get("seed", "5100"))).run(a, "eorin", 100, null, b, "hagik", 100, null, "", "", [], {"A": "auto", "B": "auto"})
	view.play_res(result, "pvp")
	if args.has("perf"):
		var frames := []
		var last := Time.get_ticks_usec()
		var t_end := float(args.get("perf"))
		var skip_to := 3.0
		while view.clock < t_end and not view.finished:
			await get_tree().process_frame
			var now := Time.get_ticks_usec()
			if view.clock > skip_to:
				frames.append((now - last) / 1000.0)
			last = now
		var tot := 0.0
		for f in frames:
			tot += f
		frames.sort()
		print("ZOOMPERF %s frames=%d mean_ms=%.2f p95_ms=%.2f max_ms=%.2f clock=%.1f" % [args.get("tag", "x"), frames.size(), tot / maxf(1, frames.size()), frames[int(frames.size() * 0.95)], frames[-1], view.clock])
		get_tree().quit()
		return
	var shots: Array = Array(str(args.get("shots", "0.3,10,25")).split(",", false))
	var folder := "D:/solgukji-main/captures/zoom"
	DirAccess.make_dir_recursive_absolute(folder)
	for st in shots:
		while view.clock < float(st) and not view.finished:
			await get_tree().process_frame
		for i in 3:
			await get_tree().process_frame
		_report(view, str(st), str(args.get("tag", "x")))
		if args.has("png"):
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png("%s/%s_%s_%dx%d.png" % [folder, args.get("tag", "x"), st, int(view.size.x), int(view.size.y)])
		if view.finished:
			break
	get_tree().quit()


func _report(view: BattleView, label: String, tag: String) -> void:
	var t2 = view.type2
	var painter = t2.painting
	var sz: Vector2 = t2.size
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	var alive := 0
	var inside := 0
	var out_px := 0.0
	var widths := []
	var heights := []
	var t2sz: Vector2 = t2.size
	painter._proj_begin()
	for sq: Squad in t2.field.order:
		if not sq.alive or sq.state == "gone":
			continue
		alive += 1
		var c: Vector2 = t2.map(sq.pos)
		var k: float = painter._pk(sq.pos)
		var l := c - Vector2(sq.hw * k, 0.0)
		var r := c + Vector2(sq.hw * k, 0.0)
		var form = painter.formations.get(sq.key)
		var fh: float = painter._figure_height(sq, form) if form != null else 0.0
		var top: float = c.y - fh
		lo = lo.min(Vector2(l.x, top))
		hi = hi.max(Vector2(r.x, c.y + 8.0))
		widths.append(2.0 * sq.hw * k)
		heights.append(fh)
		var over := maxf(maxf(-l.x, r.x - sz.x), maxf(-top, c.y - sz.y))
		if over <= 0.0:
			inside += 1
		else:
			out_px = maxf(out_px, over)
	widths.sort()
	heights.sort()
	var med_w: float = widths[widths.size() / 2] if not widths.is_empty() else 0.0
	var med_h: float = heights[heights.size() / 2] if not heights.is_empty() else 0.0
	var occ_w := (hi.x - lo.x) / sz.x
	var occ_h := (hi.y - lo.y) / sz.y
	print("ZOOM %s t=%s clock=%.1f size=%dx%d scale=%.3f alive=%d inside=%d out_max_px=%.1f squad_w_px=%.0f figure_h_px=%.1f occ_w=%.2f occ_h=%.2f empty_l=%.0f empty_r=%.0f empty_top=%.0f empty_bot=%.0f" % [
		tag, label, view.clock, sz.x, sz.y, t2._scale, alive, inside, out_px, med_w, med_h, occ_w, occ_h, lo.x, sz.x - hi.x, lo.y, sz.y - hi.y])
