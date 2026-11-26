extends Control
## 실제 카드 탭 → 전장 선택, 상태 요약/펼치기, 이름표 선택 영역을 함께 점검한다.
## --shot: 표시 확인용 상태를 넣은 캡처. 실제 덱의 성능 근거가 아니다.

func frame() -> void:
	var view := get_child(0) as BattleView
	if view != null:
		view.hud.queue_redraw()
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	await get_tree().process_frame
	await RenderingServer.frame_post_draw

func _ready() -> void:
	get_tree().create_timer(35.0).timeout.connect(func(): get_tree().quit(1))
	PlayLog.enabled = false
	Settings.load_cfg()
	Settings.type2 = true
	Settings.war_painting = true
	Settings.cam_fx = 0
	Settings.apply()
	theme = UI.theme()
	var view := BattleView.new()
	view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(view)
	await get_tree().process_frame
	var helper = preload("res://tests/formation_preview.gd").new()
	var a: Array = DB.auto_place(helper._cards(["주유", "황충", "관우", "조운", "전위", "유비", "제갈량", "방통", "장료"]), "eorin")
	var b: Array = DB.auto_place(helper._cards(["조조", "하후연", "사마의", "마초", "허저", "곽가", "손권", "여포", "화타"]), "hagik")
	var starter := "--starter" in OS.get_cmdline_user_args()
	if starter:
		var cards: Array = ["spear", "bow", "strat", "schol", "strat", "schem", "horse", "bow", "strat"]
		a = DB.auto_place(cards, "eorin")
		b = DB.auto_place(cards, "hagik")
	helper.free()
	var result := RtBattle.new(5100).run(a, "eorin", 100, null, b, "hagik", 100, null, "", "", [], {"A": "auto", "B": "auto"})
	var unchanged := JSON.stringify(result)
	view.play_res(result, "pvp")
	while view.clock < (0.25 if starter else 5.0):
		await get_tree().process_frame
	view.speed = 0.0
	view.direct = false
	view.set_process(false) # 표시 경계 검사는 일시정지한 제어기가 병력을 다시 덮어쓰지 않게 한다.
	await frame()
	if starter:
		for unit: Squad in view.field.order:
			assert(unit.max < 10000.0 and is_equal_approx(unit.troops, unit.max))
			assert(is_equal_approx(view.hud._medal_nodes[unit.key].hp_fill, BattleView.Hud.PAINT_HP_WIDTH), "Opening starter units must show a full HP bar, not 1% of a ten-thousand layer")
	var card: BattleView.MiniCard = view.cards_bar.find_children("*", "Control", true, false).filter(func(c): return c is BattleView.MiniCard and c.sq != null and c.sq.alive)[-1]
	var sq := card.sq
	var actual_statuses := sq.statuses.duplicate()
	# 상태가 많거나 부대를 선택해도 이름표 아래 아이콘이 생기지 않는다.
	sq.statuses = ["burn", "cut_def", "confuse", "seal"]
	await frame()
	assert(view.hud._badge_nodes.is_empty() and view.hud._badge_rects.is_empty(), "No battlefield buff/debuff rows may be created")
	assert(view.hud._badge_layer == null or not view.hud._badge_layer.visible)
	var tags := []
	for unit: Squad in view.field.order:
		tags.append([Vector2.ZERO, unit])
	var positions: Dictionary = view.hud._flat_token_pos(tags, true)
	for i in 12:
		tags.append(tags.pop_front())
		var again: Dictionary = view.hud._flat_token_pos(tags, true)
		for key in positions:
			assert(positions[key] == again[key], "Neighbors and drawing order must not displace a nameplate")
	var width: Vector2 = view.hud._painted_size(sq)
	var troops: float = sq.troops
	for maximum in [100.0, 500.0, 900.0, 2500.0, 10000.0, 50000.0, 1000000.0]:
		assert(BattleView.Hud.troop_ratio(maximum, maximum) == 1.0)
		assert(BattleView.Hud.troop_ratio(maximum * 0.5, maximum) == 0.5)
		assert(BattleView.Hud.troop_ratio(0, maximum) == 0.0)
		assert(BattleView.Hud.troop_ratio(-1, maximum) == 0.0)
		assert(BattleView.Hud.troop_ratio(maximum + 1, maximum) == 1.0)
		for scale in [0.5, 1.0, 1.25, 3.0]:
			var grid: Array = BattleView.Hud.troop_grid(maximum, scale)
			var count := 0
			var pixels := {}
			for lines: PackedVector2Array in grid:
				for i in range(0, lines.size(), 2):
					var pixel := roundi((lines[i].x + BattleView.Hud.PAINT_HP_WIDTH * 0.5) * scale)
					assert(not pixels.has(pixel), "Dense grids must never overdraw the same pixel into a black bar")
					pixels[pixel] = true
					count += 1
			assert(count <= roundi(BattleView.Hud.PAINT_HP_WIDTH * scale) - 1, "Grid cost must stay bounded by bar pixels, not maximum HP")
	assert(BattleView.Hud.troop_ratio(1, 0) == 0.0)
	var small_grid: Array = BattleView.Hud.troop_grid(500.0, 1.0)
	var dense_grid: Array = BattleView.Hud.troop_grid(5000.0, 1.0)
	assert(small_grid[0].size() == 8 and dense_grid[1].size() == 8, "500 HP has four 100-unit marks; 5000 HP has four 1000-unit marks")
	assert(small_grid[0][0].x == -12.0 and dense_grid[1][0].x == -12.0, "Tick position must use absolute HP divided by maximum HP")
	assert(BattleView.Hud.PAINT_HP_COLORS.A.b > BattleView.Hud.PAINT_HP_COLORS.A.r and BattleView.Hud.PAINT_HP_COLORS.B.r > BattleView.Hud.PAINT_HP_COLORS.B.b)
	sq.troops = 9.0
	assert(view.hud._painted_size(sq) == width, "Troop digits must not shift the portrait or name")
	sq.troops = troops
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.position = card.size * 0.5
		card._gui_input(event)
	await frame()
	assert(view.hud.highlight_k(sq.key) > 0.0, "Actual card tap must highlight its formation")
	assert(view.hud._medal_nodes[sq.key].selected, "Its battlefield nameplate must share selection")
	assert(view.hud._badge_nodes.is_empty(), "Selection must not restore battlefield status rows")
	assert(view.hud._painted_size(sq) == width and view.hud._flat_token_pos(tags, true) == positions, "Selection must not change label geometry or position")
	for ratio in [1.0, 0.25, 0.5, 0.0, 1.0]:
		var value: float = sq.max * ratio
		sq.troops = value
		view.hud.queue_redraw()
		await frame()
		var selected_node: BattleView.Hud.MedalNode = view.hud._medal_nodes[sq.key]
		assert(card._troops_text() == Battle.num(value), "Selected exact count belongs in the existing bottom card")
		assert(absf(selected_node.hp_fill - ratio * BattleView.Hud.PAINT_HP_WIDTH) <= 0.5 / selected_node.S + 0.001)
		assert(view.hud._painted_size(sq) == width and view.hud._flat_token_pos(tags, true) == positions, "Damage and healing must not move or resize the label")
	sq.troops = troops
	view.hud.queue_redraw()
	await frame()
	for key in view.hud._painted_medals:
		var marker: Dictionary = view.hud._painted_medals[key]
		var label: Rect2 = marker.label
		assert(label.position.x >= 0 and label.end.x <= view.hud.size.x)
		assert(label.position.y >= 94 and label.end.y <= view.hud.size.y)
		var unit: Squad = view.field.squads[key]
		var node: BattleView.Hud.MedalNode = view.hud._medal_nodes[key]
		assert(node.camp == unit.camp, "The nameplate must receive the actual replay camp for its HP palette")
		assert(node.hp_max == unit.max)
		if unit.alive:
			assert(absf(node.hp_fill - BattleView.Hud.troop_ratio(unit.troops, unit.max) * BattleView.Hud.PAINT_HP_WIDTH) <= 0.5 / node.S + 0.001, "HP fill must use current divided by actual maximum troops")
		var name_width := DB.font_bold.get_string_size(node.name_, HORIZONTAL_ALIGNMENT_LEFT, -1, BattleView.Hud.PAINT_NAME_FS).x
		assert(node.w == maxf(BattleView.Hud.PAINT_HP_WIDTH + 8.0, name_width + 6.0), "HP bar width must stay fixed regardless of health, name or grade")
		assert(node.mo == (clampi(roundi(unit.morale / 5.0), 0, 40) if unit.alive else -1), "Compacting must preserve morale")
		assert(not marker.has("portrait") and marker.radius == 0.0, "No field portrait or round medal may remain")
	assert(view.hud._medal_cache.is_empty(), "Removing portraits must also remove their image-baking work")
	# 길어진 이름표의 초상 반대쪽 끝도 탭 대상이어야 한다.
	var saved: Dictionary = view.hud._painted_medals.duplicate(true)
	view.hud._painted_medals.clear()
	view.hud._painted_medals[sq.key] = {"at": Vector2(150, 200), "radius": 13.0, "label": Rect2(95, 184, 110, 32)}
	assert(view.hud.medal_at(Vector2(203, 200)) == sq, "The whole horizontal label must be pickable")
	view.hud._painted_medals = saved
	assert(JSON.stringify(result) == unchanged, "Presentation and selection must not mutate the battle replay")
	if "--shot" in OS.get_cmdline_user_args():
		sq.statuses = actual_statuses
		await frame()
		get_viewport().get_texture().get_image().save_png("res://../build/battle_hp_grid_%s.png" % ("starter" if starter else "heroes"))
	view.hud._hl[sq.key] = view.clock - 1.0
	await frame()
	assert(view.hud._badge_nodes.is_empty())
	view.play_res(result, "pvp")
	view.speed = 0.0
	assert(view.hud._hl.is_empty(), "Selection must clear when the same view starts another battle")
	print("PASS battle readability: full starter HP / actual current-max ratio / fixed-width absolute HP grid / bounded pixel cost / no medals or portrait baking / blue-red camps / card selection / healing / replay immutability / reused view")
	view.queue_free()
	await get_tree().process_frame
	get_tree().quit()
