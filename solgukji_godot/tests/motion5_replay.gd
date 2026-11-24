extends Control
## Reproducible desktop diagnostic, not evidence of Android frame performance.
## -- --hide-painting --secs=15 --skip=3 --fps=0
const Formation = preload("res://scripts/field/painted_formation.gd")

func validate_formation(sq: Squad) -> void:
	var form = Formation.new(sq)
	assert(form.count == form.capacity)
	var front := -1
	var behind := -1
	for id in form.capacity:
		if form.ranks[id] == 0 and front < 0:
			front = id
		elif front >= 0 and id % form.cols == front % form.cols and form.ranks[id] == 1:
			behind = id
	assert(front >= 0 and behind >= 0)
	form.remove_soldier(front)
	assert(form.count == form.capacity - 1 and form.ranks[behind] == 0, "Rear rank must fill the front gap")
	form.restore_soldiers(form.capacity, sq)
	assert(form.count == form.capacity and form.opacity[front] == 0.0, "Restored soldier enters from the rear")
	var before: PackedVector2Array = form.feet.duplicate()
	form.step(sq, 0.0)
	assert(form.feet == before, "Paused formation must not move")
	form.step(sq, 0.016)
	assert(form.opacity[front] > 0.0, "Restored soldier must fade into the rear rank")
	print("PASS motion.5 formation: casualties / front replacement / restoration / pause")

func stats(values: Array) -> Dictionary:
	if values.is_empty():
		return {"frames": 0}
	var sorted := values.duplicate()
	sorted.sort()
	var total := 0.0
	var slow := 0
	var long := 0
	for value in values:
		total += float(value)
		if value > 33.333:
			slow += 1
		if value >= 100.0:
			long += 1
	return {"frames": values.size(), "fps": values.size() * 1000.0 / total,
		"mean_ms": total / values.size(), "p50_ms": sorted[ceili((sorted.size() - 1) * 0.50)],
		"p95_ms": sorted[ceili((sorted.size() - 1) * 0.95)], "p99_ms": sorted[ceili((sorted.size() - 1) * 0.99)],
		"max_ms": sorted[-1], "over_33ms_pct": slow * 100.0 / values.size(), "long_100ms": long}

func _ready() -> void:
	var args := {}
	for arg in OS.get_cmdline_user_args():
		var kv := arg.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	get_tree().create_timer(180.0).timeout.connect(func(): get_tree().quit(1))
	PlayLog.enabled = false
	Settings.load_cfg()
	Settings.type2 = true
	Settings.war_painting = true
	Settings.quality = 1
	Settings.cam_fx = 0
	Settings.ult_fx = int(args.get("ult-fx", "1"))
	Settings.apply()
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = int(args.get("fps", "0"))
	if args.has("lv"):      # 11/19 부하 단계 고정 (삽화 · HUD 갱신 주기 확인)
		Type2View.force_lv = int(args.lv)
	preload("res://scripts/field/war_painting.gd").batch_rendering = not args.has("legacy-painting")
	preload("res://scripts/field/war_painting.gd").action_frames_on = not args.has("no-action-art")
	preload("res://scripts/field/war_painting.gd").keep_dicts = args.has("validate-only")      # 11/19 점검만 사전 목록 (측정은 실제 게임처럼 묶음 배열만)
	theme = UI.theme()
	var view := BattleView.new()
	view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(view)
	await get_tree().process_frame
	var helper = preload("res://tests/formation_preview.gd").new()
	var names_a: Array = Array(str(args.get("a", "")).split(",", false))
	var names_b: Array = Array(str(args.get("b", "")).split(",", false))
	var a: Array = DB.auto_place(helper._cards(names_a), "eorin")
	var b: Array = DB.auto_place(helper._cards(names_b), "hagik")
	helper.free()
	var result := RtBattle.new(int(args.get("seed", "5100"))).run(a, "eorin", 100, null, b, "hagik", 100, null, "", "", [], {"A": "auto", "B": "auto"})
	view.play_res(result, "pvp")
	view.speed = 1.0
	var painter: Control = view.type2.painting
	for unit: Squad in view.field.order:
		validate_formation(unit)
	# A compact formation must still step, brace and refill its front.
	var compact: Squad = view.field.order[-1]
	var old_hw := compact.hw
	var old_hd := compact.hd0
	compact.hw = 30.0
	compact.hd0 = 18.0
	validate_formation(compact)
	var small = Formation.new(compact)
	assert(small.capacity <= 8)
	var was_puppet := compact.puppet
	var was_contact := compact.contact
	var old_pos := compact.pos
	compact.puppet = false
	compact.contact = true
	compact.pos += Vector2(15, 0)
	for frame in 20:
		small.step(compact, 0.016)
	assert(small.contact_weight > 0.5 and small.gait[0] > 0.0)
	small.contact_limits = [{"normal": Vector2.RIGHT, "edge": small.center.x + 8.0}]
	small.step(compact, 0.016)
	for id in small.capacity:
		assert(small.feet[id].x <= float(small.contact_limits[0].edge) + 0.001)
	var contact_pose: PackedVector2Array = small.feet.duplicate()
	small.step(compact, 0.0)
	assert(small.feet == contact_pose, "Contact separation must freeze while paused")
	compact.puppet = was_puppet
	compact.contact = was_contact
	compact.pos = old_pos
	compact.hw = old_hw
	compact.hd0 = old_hd
	var source: Squad = view.field.order[0]
	var target: Squad = view.field.order[-1]
	painter.prepare_attack(source.key, [target.key], "volley")
	assert(not painter.volleys.is_empty(), "Volley event must reach the formation renderer")
	var shot: Dictionary = painter.volleys[-1]
	var first_arrival := float(shot.start) + 0.12 + float(shot.flight)
	assert(painter.volley_progress(shot, 0, first_arrival) == 1.0)
	assert(painter.volley_progress(shot, int(shot.count) - 1, first_arrival) < 1.0)
	assert(painter.volley_progress(shot, int(shot.count) - 1, float(shot.end)) > 0.999)
	assert(painter.volley_progress(shot, 1, float(shot.start) + 0.13) == 0.0)

	painter.play_event({"fx": "phys", "a": source.key, "f": target.key, "n": 10, "painted_charge": "hit"}, null, [{"key": target.key, "troops": target.max * 0.5}])
	assert(painter.charges.has(target.key) and not painter.contacts.is_empty() and not painter.bodies.is_empty())
	assert(painter.bodies.size() <= painter.MAX_BODIES and painter.contacts.size() <= painter.MAX_CONTACTS)
	painter.reset()
	assert(painter.formations.is_empty() and painter.bodies.is_empty() and painter.contacts.is_empty() and painter.volleys.is_empty())
	var capacity := 0
	for sq: Squad in view.field.order:
		capacity += painter._formation(sq).capacity
	print("PASS motion.5 event delivery: volley / impact / casualty / effect limits / reset")
	if args.has("move-audit"):      # 11/17 이동 어색함 점검 —— 화면 부대(Squad)와 삽화 대열(form)의 움직임을 프레임마다 재 본다
		var secs := float(args.get("move-audit", "30"))
		var prev := {}
		var m := {"frames": 0, "moving": 0.0, "crab": 0.0, "back": 0.0, "stopgo": 0, "jerk": 0, "spin": 0, "head_flip": 0, "turn_in_place": 0.0}
		var worst := {}
		var last_move := {}
		var last_turn := {}
		while view.clock < secs and not view.finished:
			await get_tree().process_frame
			var dt: float = get_process_delta_time() * view.speed if view.speed > 0 else 0.0
			if dt <= 0.0005:
				continue
			m.frames += 1
			for sq: Squad in view.field.order:
				if not sq.alive or sq.state == "gone":
					continue
				var form = painter.formations.get(sq.key)
				if form == null:
					continue
				var cur := {"p": form.center, "h": form.heading, "mv": sq.moving}
				if prev.has(sq.key):
					var pv: Dictionary = prev[sq.key]
					var vel: Vector2 = (cur.p - pv.p) / dt
					var spd := vel.length()
					var pspd: float = pv.get("spd", spd)
					cur["spd"] = spd
					var dh := absf(angle_difference(float(pv.h), float(cur.h)))
					var scr: Vector2 = painter.v.map(cur.p) - painter.v.map(pv.p)
					if absf(scr.x) / dt > 12.0 and absf(scr.x) > scr.length() * 0.35:      # 화면 가로로 움직이는데 그림이 반대를 본다 = 문워크
						m.side_move = float(m.get("side_move", 0.0)) + dt
						var looks_right: bool = form.facing_right
						if looks_right != (scr.x > 0.0):
							m.moonwalk = float(m.get("moonwalk", 0.0)) + dt
							var mk := "moonwalk_" + ("contact" if sq.contact else "free")
							m[mk] = float(m.get(mk, 0.0)) + dt
					if spd > 15.0:
						m.moving += dt
						var off := absf(angle_difference(vel.angle(), float(cur.h)))
						if off > deg_to_rad(60) and off < deg_to_rad(120):
							m.crab += dt
							var ctx := ("contact" if sq.contact else ("near" if sq.ptgt != null and sq.pos.distance_to(sq.ptgt.pos) < 140.0 else "free"))
							var kk := "crab_" + ctx + "_" + sq.cls
							m[kk] = float(m.get(kk, 0.0)) + dt
							var ek := "eng_off_" + ctx      # 엔진 자체도 옆으로 가나 (기록된 엔진 방향 vs 엔진 이동)
							var eng_off := absf(angle_difference(vel.angle(), sq.pfwd.angle()))
							if eng_off > deg_to_rad(60) and eng_off < deg_to_rad(120):
								m[ek] = float(m.get(ek, 0.0)) + dt
							worst[sq.key + ":crab"] = float(worst.get(sq.key + ":crab", 0.0)) + dt
						elif off >= deg_to_rad(120):
							m.back += dt
							worst[sq.key + ":back"] = float(worst.get(sq.key + ":back", 0.0)) + dt
					elif dh / dt > 1.0:
						m.turn_in_place += dt
					if absf(spd - pspd) / dt > 900.0:
						m.jerk += 1
						worst[sq.key + ":jerk"] = int(worst.get(sq.key + ":jerk", 0)) + 1
					if dh / dt > 4.0:
						m.spin += 1
					var sgn := signf(angle_difference(float(pv.h), float(cur.h)))
					if dh > 0.0005:      # 눈에 보이는 떨림 —— 한쪽으로 5도 넘게 돌았다가 0.6초 안에 반대로 5도 넘게
						var lt: Array = last_turn.get(sq.key, [sgn, view.clock, 0.0, 0.0, -10.0])
						if int(lt[0]) == int(sgn):
							lt[2] = float(lt[2]) + dh
						else:
							if float(lt[2]) > 0.087 and float(lt[3]) > 0.087 and view.clock - float(lt[4]) < 0.6:
								m.head_flip += 1
								if args.has("flip-log"):
									print("FLIP ", sq.key, " t=", snappedf(view.clock, 0.01), " seg=", snappedf(rad_to_deg(float(lt[2])), 0.1), "/", snappedf(rad_to_deg(float(lt[3])), 0.1))
								var fk := "flip_" + ("march" if form.get("marching") else ("contact" if sq.contact else "face")) + ("_moving" if float(cur.get("spd", 0.0)) > 15.0 else "_still")
								m[fk] = int(m.get(fk, 0)) + 1
								worst[sq.key + ":flip"] = int(worst.get(sq.key + ":flip", 0)) + 1
							lt = [sgn, view.clock, dh, float(lt[2]), view.clock]
						lt[1] = view.clock
						last_turn[sq.key] = lt
					if bool(pv.mv) != bool(cur.mv):
						if last_move.has(sq.key) and view.clock - float(last_move[sq.key]) < 0.5:
							m.stopgo += 1
							worst[sq.key + ":stopgo"] = int(worst.get(sq.key + ":stopgo", 0)) + 1
						last_move[sq.key] = view.clock
				if args.has("trace") and sq.key == str(args.get("trace")):
					print("TR t=", snappedf(view.clock, 0.01), " h=", snappedf(rad_to_deg(form.heading), 0.1), " md=", snappedf(rad_to_deg(form.march_dir.angle()), 0.1) if form.march_dir != Vector2.ZERO else "-", " pf=", snappedf(rad_to_deg(sq.pfwd.angle()), 0.1), " mar=", form.marching, " c=", form.center.round())
				prev[sq.key] = cur
		var ws := worst.keys()
		ws.sort_custom(func(x, y): return float(worst[x]) > float(worst[y]))
		var top := {}
		for k in ws.slice(0, 12):
			top[k] = snappedf(float(worst[k]), 0.01)
		for k in m:
			m[k] = snappedf(float(m[k]), 0.01) if m[k] is float else m[k]
		print("MOVE_AUDIT ", JSON.stringify(m))
		print("MOVE_WORST ", JSON.stringify(top))
		get_tree().quit()
		return
	if args.has("ult-inject"):      # 화면 확인용 —— 고유기 이펙트를 직접 넣어 0.15 · 0.45 · 0.8초에 찍는다 (판정과 무관)
		while view.clock < 8.0:
			await get_tree().process_frame
		var caster: Squad = view.field.order[0]
		var foes := []
		for q: Squad in view.field.order:
			if q.camp != caster.camp and q.alive and foes.size() < 3:
				foes.append(q.key)
		var kind := str(args.get("ult-inject"))
		painter.add_ult(kind, caster.key, foes, [], UltFx.new(view.field)._col(kind), "impact")
		var t0: float = view.clock
		for k in 3:
			while view.clock - t0 < [0.15, 0.45, 0.8][k]:
				await get_tree().process_frame
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png("res://../build/inject_%s_%d.png" % [kind, k])
		print("INJECT_SHOTS ", kind)
		get_tree().quit()
		return
	if args.has("ult-shots"):      # 11/17 고유기 이펙트 확인 —— 맞는 순간 뒤 0.15 · 0.45 · 0.8초에 한 장씩 (최대 n 개 고유기)
		var want := int(args.get("ult-shots", "6"))
		var only := str(args.get("ult-kind", ""))
		var phase := str(args.get("ult-phase", "impact"))
		var done := {}
		var taken := 0
		while taken < want * 3 and not view.finished and view.clock < 90.0:
			await get_tree().process_frame
			for e: Dictionary in painter.ults:
				if e.phase != phase or (only != "" and e.vfx != only):
					continue
				var age: float = view.clock - float(e.start)
				var id := "%s_%.2f" % [e.vfx, float(e.start)]
				var step: int = done.get(id, 0)
				if step < 3 and age >= ([0.08, 0.2, 0.5] if e.vfx == "arrowstorm" else [0.15, 0.45, 0.8])[step]:
					done[id] = step + 1
					taken += 1
					await RenderingServer.frame_post_draw
					get_viewport().get_texture().get_image().save_png("res://../build/ult_%02d_%s_%s_%d.png" % [taken, e.vfx, e.phase, step])
					print("ULT_SHOT ", id, " step ", step)
					if args.has("ult-debug"):
						print("  a=", e.a, " from=", e.from, " scr=", painter.v.map(e.from), " unit=", painter._px(e.from, 80.0), " tex=", painter.v._spr("flame_02"), " vis=", painter.top_effects.is_visible_in_tree(), " z=", painter.top_effects.z_index)
						for h in e.hits:
							var near := ""
							for q: Squad in view.field.order:
								if q.pos.distance_to(h.at) < 5.0: near = q.key + "/" + q.camp
							print("  hit ", h.at, " -> ", painter.v.map(h.at), " ", near)
					break
		print("ULT_SHOTS %d" % taken)
		get_tree().quit()
		return
	if args.has("num-count"):      # 11/19 피해 숫자가 병종별로 몇 번 떴나 (그림 화면 · 맞은 부대 병종 기준) —— 창병 숫자가 안 뜨던 것 확인
		var seen := {}
		var by := {}
		while not view.finished and view.clock < float(args.get("num-count")):
			for f in view.hud.floats:
				var fid := "%s|%.4f" % [f.key, float(f.get("born", 0.0))]
				if f.get("num", false) and not seen.has(fid):
					seen[fid] = true
					var sq = view.field.squads.get(f.key)
					var tg: String = sq.row.get("tag", "?") if sq != null else "?"
					by[tg] = int(by.get(tg, 0)) + 1
			await get_tree().process_frame
		print("NUM_COUNT painting=%s %s" % [Type2View.painting_on(), by])
		get_tree().quit()
		return
	if args.has("float-shot"):      # 11/19 전투 중 알림 확인 —— 그 기호(heal · burn …)의 알림이 처음 뜬 뒤 0.3초에 한 장
		var want := str(args.get("float-shot"))
		while not view.finished and not view.hud.floats.any(func(f): return str(f.get("icon", "")) == want):
			await get_tree().process_frame
		await get_tree().create_timer(0.3).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://../build/float_%s.png" % want)
		print("FLOAT_SHOT ", want, " at ", view.clock, " found=", not view.finished)
		get_tree().quit()
		return
	if args.has("validate-only"):
		while view.clock < float(args.get("capture-at", "0")) and not view.finished:
			await get_tree().process_frame
		view.speed = 0.0
		await RenderingServer.frame_post_draw
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		if painter.batch_rendering:
			assert(painter.batch.soldiers.multimesh.visible_instance_count == painter.visible_soldiers.size())
			assert(painter.batch.shadows.multimesh.visible_instance_count == painter.visible_soldiers.size())
			assert(painter.walk_meshes.is_empty(), "GPU walk animation must not allocate CPU pose meshes")
			for i in painter.visible_soldiers.size():
				var figure: Dictionary = painter.visible_soldiers[i]
				assert(painter.batch.buffer[i * 16 + 12] == float(figure.cell))
				assert(is_equal_approx(painter.batch.buffer[i * 16 + 13], float(figure.stride)))
				assert(is_equal_approx(painter.batch.buffer[i * 16 + 14], float(figure.gait)))
				assert(is_equal_approx(painter.batch.buffer[i * 16 + 3], float(figure.p.x)))
				if int(figure.cell) in [16, 17]:
					assert(painter.batch.shadow_buffer[i * 12 + 11] == 0.0, "Standards must not cast a soldier shadow")
				elif painter.action_frames_ready and painter.action_frames_on:
					var cell := int(figure.cell)
					assert(cell >= 32 and cell < 96)
					assert(((cell - 32) % 32) / 4 == painter.TAGS.find(figure.sq.tag), "Each role must use its own four action frames")
					assert((cell < 64) == (figure.sq.camp == "A"), "Both armies must use the correct action sheet")
					assert(painter.batch.shadow_buffer[i * 12 + 11] > 0.0 or float(figure.fade) <= 0.0, "Animated soldiers must retain their grounded shadow")
			print("PASS batched renderer: all figures / depth order / atlas cell / no CPU pose cache")
		if args.has("shot"):
			get_viewport().get_texture().get_image().save_png("res://../build/motion5_renderer_%s.png" % str(args.get("tag", "smoke")))
		if args.has("contact-audit"):
			var crowded := []
			for i in painter.visible_soldiers.size():
				var one: Dictionary = painter.visible_soldiers[i]
				for j in range(i + 1, painter.visible_soldiers.size()):
					var two: Dictionary = painter.visible_soldiers[j]
					if int(one.cell) in [16, 17] or int(two.cell) in [16, 17]:
						continue      # 군기는 병사 발 간격 검사 대상이 아니다
					if one.sq.camp == two.sq.camp or not one.sq.alive or not two.sq.alive:
						continue
					var separation: float = one.p.distance_to(two.p) / minf(one.h, two.h)
					if separation < 0.2:
						crowded.append({"a": one.sq.key, "b": two.sq.key, "separation": separation})
			print("CONTACT_AUDIT ", JSON.stringify({"clock": view.clock, "figures": painter.visible_soldiers.size(), "near_opposing_feet": crowded}))
		view.queue_free()
		await get_tree().process_frame
		get_tree().quit()
		return
	var hidden := args.has("hide-painting")
	if hidden:
		painter.hide()
	# 진단 —— 층별로 끄고 그리기 호출 · 프레임을 비교한다 (게임 옵션 아님)
	if args.has("hide-hud"):
		view.hud.hide()
	if args.has("hide-ground"):
		view.type2._ground_view.hide()
	if args.has("hide-dock"):
		view.cards_bar.hide()
	var skip := float(args.get("skip", "3"))
	var duration := float(args.get("secs", "15"))
	var start := Time.get_ticks_usec()
	while (Time.get_ticks_usec() - start) / 1e6 < skip:
		await get_tree().process_frame
	var prof0: Dictionary = view.field.prof.duplicate()
	var prof_last: Dictionary = prof0.duplicate()
	var phase_cpu := {"march": {}, "contact": {}, "ultimate": {}}
	var last := Time.get_ticks_usec()
	var end := last + int(duration * 1e6)
	var frames := []
	var phases := {"march": [], "contact": [], "ultimate": []}
	var stages := {"opening": [], "clash": [], "late": []}
	var sample_start_clock: float = view.clock
	var max_figures := 0
	var max_meshes := 0
	var max_bodies := 0
	var draw_calls := 0.0
	var upd0: int = painter.paint_updates
	var lv_hist := {}
	var slow_frames: Array = []
	while Time.get_ticks_usec() < end and not view.finished:
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		var frame_ms := (now - last) / 1000.0
		last = now
		frames.append(frame_ms)
		var phase := "march"
		if view.hud.cut != null or not view.hud.fins.is_empty():
			phase = "ultimate"
		elif view.field.order.any(func(sq): return sq.alive and sq.contact):
			phase = "contact"
		phases[phase].append(frame_ms)
		var stage := "opening" if view.clock < 5.0 else ("clash" if view.clock < 15.0 else "late")
		stages[stage].append(frame_ms)
		if frame_ms > 33.333:
			slow_frames.append({"clock": view.clock, "ms": frame_ms, "phase": phase, "stage": stage,
				"ultimates": painter.ults.size(), "figures": painter.figure_count, "draw_calls": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)})
		if args.has("phase-cpu"):      # 구간(행군 · 교전 · 고유기)별 CPU 몫 —— 프레임마다 prof 차이를 모은다 (측정 자체가 조금 무겁다)
			var cur: Dictionary = view.field.prof
			var acc: Dictionary = phase_cpu[phase]
			for k in cur:
				acc[k] = int(acc.get(k, 0)) + int(cur[k]) - int(prof_last.get(k, 0))
			prof_last = cur.duplicate()
		max_figures = maxi(max_figures, painter.figure_count)
		max_meshes = maxi(max_meshes, painter.walk_meshes.size())
		max_bodies = maxi(max_bodies, painter.bodies.size())
		draw_calls += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
		var lvk := str(view.type2.load_lv)
		lv_hist[lvk] = int(lv_hist.get(lvk, 0)) + 1
	var report := {"platform": OS.get_name(), "engine": Engine.get_version_info().string,
		"android_device_measurement": OS.get_name() == "Android", "renderer": RenderingServer.get_current_rendering_method(),
		"adapter": RenderingServer.get_video_adapter_name(), "window": str(get_viewport_rect().size),
		"quality": Settings.quality, "vsync": false, "fps_cap": Engine.max_fps, "seed": 5100,
		"batch_rendering": painter.batch_rendering, "hidden_painting": hidden, "warmup_seconds": skip, "sample_seconds": duration, "total": stats(frames),
		"phases": {}, "max_figures": max_figures, "max_bodies": max_bodies, "max_walk_meshes": max_meshes,
		"mean_draw_calls": draw_calls / maxf(1.0, frames.size()),
		"paint_updates_per_sec": (painter.paint_updates - upd0) / maxf(0.001, (last - (end - int(duration * 1e6))) / 1e6), "load_lv_frames": lv_hist, "initial_formation_capacity": capacity}
	report["ult_fx"] = Settings.ult_fx
	report["slow_frames"] = slow_frames
	report["game_clock_start"] = sample_start_clock
	report["game_clock_end"] = view.clock
	report["battle_finished"] = view.finished
	report["stages"] = {}
	for stage in stages:
		report.stages[stage] = stats(stages[stage])
	for phase in phases:
		report.phases[phase] = stats(phases[phase])
	# 구간별 CPU 시간 (프레임당 평균 ms) —— 측정 구간만 (준비 구간은 빼려고 아래 prof0 를 뺀다)
	var cpu := {}
	var nf := maxf(1.0, float(view.field.prof.get("_frames", 0) - prof0.get("_frames", 0)))
	for k in view.field.prof:
		if k != "_frames":
			cpu[k] = snappedf((float(view.field.prof[k]) - float(prof0.get(k, 0))) / 1000.0 / nf, 0.001)
	report["cpu_ms_per_frame"] = cpu
	if args.has("phase-cpu"):
		var pc := {}
		for ph in phase_cpu:
			var n := maxf(1.0, float(phases[ph].size()))
			var row := {}
			for k in phase_cpu[ph]:
				if k != "_frames":
					row[k] = snappedf(float(phase_cpu[ph][k]) / 1000.0 / n, 0.001)
			pc[ph] = row
		report["phase_cpu_ms"] = pc
	var name_ := "hidden" if hidden else "full"
	var path := "res://../build/motion5_profile_%s.json" % str(args.get("tag", name_))
	var f := FileAccess.open(path, FileAccess.WRITE)
	assert(f != null)
	f.store_string(JSON.stringify(report, "\t"))
	f.close()
	print("PROFILE ", JSON.stringify(report))
	view.queue_free()
	await get_tree().process_frame
	get_tree().quit()
