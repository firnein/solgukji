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
	helper.free()
	var result := RtBattle.new(5100).run(a, "eorin", 100, null, b, "hagik", 100, null, "", "", [], {"A": "auto", "B": "auto"})
	var unchanged := JSON.stringify(result)
	view.play_res(result, "pvp")
	while view.clock < 5.0:
		await get_tree().process_frame
	view.speed = 0.0
	view.direct = false
	view.set_process(false) # 표시 경계 검사는 일시정지한 제어기가 병력을 다시 덮어쓰지 않게 한다.
	await frame()
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
	for value in [0.0, 1.0, 9999.0, 10000.0, 10001.0, 19999.0, 20000.0, 38000.0, 40000.0, 39999.0, 100001.0]:
		var state := BattleView.Hud.troop_layers(value)
		var represented := maxf(0.0, state.x - 1.0) * 10000.0 + state.y * 10000.0
		assert(absf(represented - value) < 0.01, "Layer and fill must preserve actual troop strength across damage and recovery")
		assert(state.y >= 0.0 and state.y <= 1.0)
	assert(BattleView.Hud.troop_layers(38000.0).is_equal_approx(Vector2(4, 0.8)))
	assert(BattleView.Hud.troop_layers(-1.0) == Vector2.ZERO)
	# 만 명 경계 직전의 위층 색이 경계를 넘은 뒤의 아래층 색이다.
	for boundary in [10000.0, 20000.0, 40000.0, 100000.0]:
		var before := BattleView.Hud.troop_layers(boundary - 1.0)
		var after := BattleView.Hud.troop_layers(boundary)
		assert(before.x == after.x and after.y == 1.0, "At an exact layer boundary, the same front color must finish filling")
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
	for value in [41000.0, 40000.0, 39999.0, 38000.0, 39999.0, 40000.0]:
		sq.troops = value
		view.hud.queue_redraw()
		await frame()
		var selected_node: BattleView.Hud.MedalNode = view.hud._medal_nodes[sq.key]
		assert(card._troops_text() == Battle.num(value), "Selected exact count belongs in the existing bottom card")
		assert(selected_node.troop_layer == int(BattleView.Hud.troop_layers(value).x))
		assert(view.hud._painted_size(sq) == width and view.hud._flat_token_pos(tags, true) == positions, "Losing and recovering a layer must not move the label")
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
		var troop_state := BattleView.Hud.troop_layers(unit.troops)
		assert(node.troop_layer == (int(troop_state.x) if unit.alive else -1), "Both armies must use absolute troop layers")
		if unit.alive:
			assert(absf(node.troop_fill - troop_state.y * (node.w - 11.0)) <= 0.5 / node.S + 0.001, "Bar loss must follow actual displayed casualties within half a screen pixel")
		assert(node.w == maxf(32.0, DB.font_bold.get_string_size(node.name_, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x + 10.0), "Field labels must fit only the name, with no number reserve or large minimum width")
		assert(node.mo == (clampi(roundi(unit.morale / 5.0), 0, 40) if unit.alive else -1), "Compacting must preserve morale")
		var portrait: Rect2 = marker.get("portrait", Rect2())
		var portrait_expected := view.hud.highlight_k(key) > 0.0 or unit == view.field.follow or bool(unit.row.get("boss", false))
		assert(portrait.has_area() == portrait_expected, "Only selected units and the commander may show field portraits")
	# 길어진 이름표의 초상 반대쪽 끝도 탭 대상이어야 한다.
	var saved: Dictionary = view.hud._painted_medals.duplicate(true)
	view.hud._painted_medals.clear()
	view.hud._painted_medals[sq.key] = {"at": Vector2(150, 200), "radius": 13.0, "label": Rect2(95, 184, 110, 32)}
	assert(view.hud.medal_at(Vector2(203, 200)) == sq, "The whole horizontal label must be pickable")
	view.hud._painted_medals[sq.key].portrait = Rect2(65, 184, 24, 24)
	assert(view.hud.medal_at(Vector2(67, 186)) == sq, "The selected portrait must also be pickable")
	view.hud._painted_medals = saved
	assert(JSON.stringify(result) == unchanged, "Presentation and selection must not mutate the battle replay")
	if "--shot" in OS.get_cmdline_user_args():
		sq.statuses = actual_statuses
		await frame()
		get_viewport().get_texture().get_image().save_png("res://../build/battle_compact_layers_selected.png")
	view.hud._hl[sq.key] = view.clock - 1.0
	await frame()
	assert(view.hud._badge_nodes.is_empty())
	view.play_res(result, "pvp")
	view.speed = 0.0
	assert(view.hud._hl.is_empty(), "Selection must clear when the same view starts another battle")
	print("PASS battle readability: anchored nameplates / compact overlapping bars / no number reserve or ticks / card tap / absolute troop layers / boundaries and recovery / exact numbers in selected bottom card / morale / full label picking / replay immutability / reused view")
	view.queue_free()
	await get_tree().process_frame
	get_tree().quit()
