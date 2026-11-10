extends Control
## 등급 장식 점검 (11/9 기인 · 초월 · 불멸 · 신화 프로필) —— 실행:
##   godot --path . --resolution 720x1280 res://tests/tier_deco.tscn -- --shot=경로.png [--mode=mix|tile|big|perf] [--n=24] [--secs=4] [--key=t8|t5|t7|t6|kiin]
## mix : 일반 전설 · 기인 · 초월 · 불멸 · 신화를 줄마다 — MiniTile(66×96 · 표시 붙은 것) · 작은 칸(폭 48) · CardTile · CardView
## big : 큰 CardView(디테일창 크기) 다섯 장
## perf: 신화 MiniTile 을 --n 장 깔고 --secs 초 동안 FPS · 프레임 시간을 잰다 (점검용 — 화면 밖 처리 안 함도 확인)

var _ids := {}


func _pick(key: String, n: int) -> Array:
	var out := []
	var all := []
	for k in DB.C:
		if DB.is_foe(k):
			continue
		var kk: String = "kiin" if DB.is_kiin(k) else ("t%d" % DB.C[k].tier)
		if kk == key:
			all.append(k)
	all.sort()
	for k in all:      # 그림이 있는 것을 먼저
		if DB.portrait(k) != null and out.size() < n:
			out.append(k)
	for k in all:
		if not out.has(k) and out.size() < n:
			out.append(k)
	return out


func _ready() -> void:
	var args := {}
	for s in OS.get_cmdline_user_args():
		var kv := s.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	var bg := ColorRect.new()
	bg.color = DB.PAL.ink
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var mode := str(args.get("mode", "mix"))
	for key in ["t5", "kiin", "t6", "t7", "t8"]:
		_ids[key] = _pick(key, 3)
		print(key, " ", _ids[key])
	var sc := ScrollContainer.new()
	sc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(sc)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 6)
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_top", 10)
	pad.add_theme_constant_override("margin_left", 4)
	pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(pad)
	pad.add_child(root)
	match mode:
		"big":
			var row := HFlowContainer.new()
			row.add_theme_constant_override("h_separation", 8)
			row.add_theme_constant_override("v_separation", 8)
			root.add_child(row)
			for key in ["t5", "kiin", "t6", "t7", "t8"]:
				row.add_child(CardView.new().setup(_ids[key][0], Vector2(132, 188)))
			for key in ["kiin", "t6", "t7", "t8"]:
				row.add_child(CardView.new().setup(_ids[key][1], Vector2(112, 160)))
		"perf":
			var g := GridContainer.new()
			g.columns = 5
			root.add_child(g)
			var ks: Array = _pick(str(args.get("key", "t8")), 20)
			for i in int(args.get("n", "24")):
				var t := MiniTile.new().setup(ks[i % ks.size()], 2 if i % 3 == 0 else -1)
				g.add_child(t)
			if args.has("noshim"):      # 빛줄기 덧칸을 뺀 기준값
				for sh in g.find_children("Shimmer", "", true, false):
					sh.free()
			_measure(float(args.get("secs", "4")))
			return
		_:
			for key in ["t5", "kiin", "t6", "t7", "t8"]:
				var row := HBoxContainer.new()
				row.add_theme_constant_override("separation", 4)
				root.add_child(row)
				var ids: Array = _ids[key]
				if mode == "tile":
					row.add_child(CardTile.new().setup(ids[0], 2))
					var ct2 := CardTile.new().setup(ids[1], -1)
					ct2.set_pin(true, false)
					row.add_child(ct2)
					continue
				var a := MiniTile.new().setup(ids[0], 2)
				a.up = true
				a.badge = "조합"
				row.add_child(a)
				var b := MiniTile.new().setup(ids[1], -1)
				b.set_pin(true, false)
				row.add_child(b)
				var c := MiniTile.new().setup(ids[2], -1)
				c.lit = true
				row.add_child(c)
				var d := MiniTile.new().setup(ids[0], 3)
				d.custom_minimum_size = Vector2(48, 70)
				d.up = true
				row.add_child(d)
				var e := MiniTile.new().setup(ids[1], -1)
				e.custom_minimum_size = Vector2(48, 70)
				row.add_child(e)
				var cv := CardView.new().setup(ids[1], Vector2(75, 107))
				row.add_child(cv)
	if args.has("shot"):
		await get_tree().create_timer(float(args.get("after", "1.0"))).timeout
		var nb := int(args.get("burst", "1"))      # --burst=N --every=초 : 연속 N장 (빛줄기가 지나가는 모습)
		for i in nb:
			if i > 0:
				await get_tree().create_timer(float(args.get("every", "0.15"))).timeout
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(str(args.shot) if nb == 1 else str(args.shot).replace(".png", "_%d.png" % i))
		get_tree().quit()


func _measure(secs: float) -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)      # 한계까지 돌려서 처리 시간을 본다 (--key=t5 면 일반 카드로 기준값)
	await get_tree().create_timer(1.5).timeout
	var t0 := Time.get_ticks_msec()
	var frames := 0
	var worst := 0.0
	var slow := []
	var last := Time.get_ticks_usec()
	while Time.get_ticks_msec() - t0 < secs * 1000.0:
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		var ft := (now - last) / 1000.0
		worst = maxf(worst, ft)
		if ft > 8.0:
			slow.append("%.1f초 %.0fms" % [(Time.get_ticks_msec() - t0) / 1000.0, ft])
		last = now
		frames += 1
	var el := (Time.get_ticks_msec() - t0) / 1000.0
	print("느린 프레임(8ms 넘음) %d개: %s" % [slow.size(), str(slow.slice(0, 12))])
	var proc := Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
	print("PERF 프레임 %d · %.1f초 · 평균 FPS %.1f · 엔진 FPS %d · 최장 프레임 %.1fms · process %.2fms · 그리기 호출 %d" % [frames, el, frames / el, int(Engine.get_frames_per_second()),
		worst, proc, int(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME))])
	get_tree().quit()
