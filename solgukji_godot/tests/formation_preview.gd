extends Control
## Opt-in formation concept. --baseline renders the current crowd with identical inputs.
func _cards(names: Array) -> Array:
	var cards := []
	for person in names:
		var found := ""
		for tier in [7, 8, 6, 5]:
			for key in DB.by_tier(tier):
				if DB.person(key) == person:
					found = key
					break
			if found != "":
				break
		assert(found != "", "Missing sample commander: " + str(person))
		cards.append(found)
	for key in DB.by_tier(7):
		if cards.size() >= 9:
			break
		if not cards.has(key):
			cards.append(key)
	return cards

func _ready() -> void:
	PlayLog.enabled = false
	Settings.load_cfg()
	Settings.type2 = true
	Settings.war_painting = "--painting" in OS.get_cmdline_user_args()
	Settings.cam_fx = 0
	Settings.apply()
	Type2View.formation_preview = not Settings.war_painting and not "--baseline" in OS.get_cmdline_user_args()
	theme = UI.theme()
	var view := BattleView.new()
	view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(view)
	await get_tree().process_frame
	var mixed := "--mixed" in OS.get_cmdline_user_args()
	var a: Array = DB.auto_place(_cards(["주유", "황충", "관우", "조운", "전위", "유비", "제갈량", "방통", "장료"] if mixed else []), "eorin")
	var b: Array = DB.auto_place(_cards(["조조", "하후연", "사마의", "마초", "허저", "곽가", "손권", "여포", "화타"] if mixed else []), "hagik")
	var result := RtBattle.new(5100).run(a, "eorin", 100, null, b, "hagik", 100, null, "", "", [], {"A": "auto", "B": "auto"})
	if Settings.war_painting:
		Settings.war_painting = false
		var old_result := RtBattle.new(5100).run(a, "eorin", 100, null, b, "hagik", 100, null, "", "", [], {"A": "auto", "B": "auto"})
		Settings.war_painting = true
		assert(JSON.stringify(result.ev) == JSON.stringify(old_result.ev), "Painting must not change battle events")
		assert(result.left == old_result.left and result.eLeft == old_result.eLeft)
	view.play_res(result, "pvp")
	if Settings.war_painting:
		for sq: Squad in view.field.order:
			for at in [sq.pos, sq.pos + sq.fwd * sq.hd0, sq.pos + sq.right() * sq.hw]:
				assert(view.type2.unmap(view.type2.map(at)).distance_to(at) < 0.01, "Projection and ground picking must agree")
		var near: Squad = view.field.order[0]
		var far: Squad = view.field.order[-1]
		assert(view.type2.depth_scale(near.pos) > view.type2.depth_scale(far.pos), "Near figures should be larger")
		var min_y := INF
		var max_y := -INF
		for point in view.type2._painting_points:
			var y: float = view.type2.map(point).y
			min_y = minf(min_y, y)
			max_y = maxf(max_y, y)
		assert(absf(min_y - 90.0) < 0.1 and absf(max_y - (view.type2.size.y - 30.0)) < 0.1, "Use the full vertical battlefield between HUD and roster")
		for sq: Squad in view.field.order:
			var on_screen: Vector2 = view.type2.map(sq.pos)
			assert(on_screen.x >= 15 and on_screen.x <= view.type2.size.x - 15, "Initial formations must fit horizontally")
			assert(on_screen.y >= 90 and on_screen.y <= view.type2.size.y - 25, "Initial formations must clear the HUD")
	var label := Label.new()
	label.text = "CURRENT" if not Type2View.formation_preview else "FORMATION STUDY / 01"
	if Settings.war_painting:
		label.text = "WAR PAINTING / PLAYABLE"
	label.position = Vector2(12, 6)
	label.add_theme_font_size_override("font_size", 12)
	add_child(label)
	var out := "baseline" if not Type2View.formation_preview else "formation"
	if Settings.war_painting:
		out = "painting_oblique"
	if mixed:
		out += "_mixed"
	var done := {}
	while not view.finished:
		await get_tree().process_frame
		for moment in [0.5, 8.0, 25.0]:
			if view.clock >= moment and not done.has(moment):
				await RenderingServer.frame_post_draw
				get_viewport().get_texture().get_image().save_png("res://../build/%s_%s.png" % [out, int(moment)])
				done[moment] = true
		if done.size() == 3 and not "--full" in OS.get_cmdline_user_args():
			break
	if Settings.war_painting:
		var painter: Control = view.type2.painting
		assert(painter != null and painter.cells.size() == 16)
		view.speed = 0
		await get_tree().process_frame
		await get_tree().process_frame
		var paused := JSON.stringify(painter.ratios)
		var fixed_scale: float = view.type2._scale
		var fixed_center: Vector2 = view.type2._center
		for i in 4:
			await get_tree().process_frame
		assert(paused == JSON.stringify(painter.ratios), "Paused formations must not lose troops")
		view.type2._fit()
		assert(is_equal_approx(fixed_scale, view.type2._scale) and fixed_center.is_equal_approx(view.type2._center), "The camera must not zoom into surviving formations")
		# Reuse the same BattleView, as the actual game does when a new battle opens.
		for mode in [false, true]:
			Settings.war_painting = mode
			view.play_res(result.duplicate(true), "pvp")
			view.speed = 0
			await get_tree().process_frame
			assert(view.type2.painting.visible == mode, "Style must switch on a reused view")
			assert(view.type2._mm.visible != mode, "The two renderers must not overlap")
	print("PASS formation preview capture ", out)
	view.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	get_tree().quit()
