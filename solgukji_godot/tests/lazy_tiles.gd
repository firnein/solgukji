extends Node
## 화면 밖 타일 건너뛰기 점검 (11/15 성능 —— UI.off_screen) —— 창이 있어야 한다: godot --path . --resolution 720x1280 res://tests/lazy_tiles.tscn [-- --out=폴더]
## 조합 탭을 다 펼치고 스크롤(건너뛰기 · 조금씩) · 창 크기 바꾸기 · 징집 탭 뒤에 「화면 안인데 안 그려짐」 이 0 이어야 한다 (LAZY| 줄). --out 을 주면 장면마다 찍는다

var out := ""


func _tiles(n: Node, acc: Array) -> void:
	for c in n.get_children():
		if c is MiniTile or c is CardTile:
			acc.append(c)
		_tiles(c, acc)


func _check(tag: String, root: Node) -> void:
	var acc := []
	_tiles(root, acc)
	var bad := 0
	var skipped := 0
	var seen := 0
	for t in acc:
		if not t.is_visible_in_tree():
			continue
		var on: bool = t.get_viewport_rect().intersects(t.get_global_rect())
		if t._skipped:
			skipped += 1
			if on:
				bad += 1
		elif on:
			seen += 1
	print("LAZY|%s|타일 %d|화면 안 그려짐 %d|건너뜀 %d|화면 안인데 안 그려짐 %d" % [tag, acc.size(), seen, skipped, bad])
	await RenderingServer.frame_post_draw
	if out != "":
		get_viewport().get_texture().get_image().save_png("%s/lazy_%s.png" % [out, tag])


func _ready() -> void:
	for s in OS.get_cmdline_user_args():
		if s.begins_with("--out="):
			out = s.trim_prefix("--out=")
	PlayLog.enabled = false
	Run.dev_immortal = true
	var gs: GameScreen = load("res://scenes/game.tscn").instantiate()
	add_child(gs)
	await get_tree().create_timer(0.5).timeout
	var r := Run.new()
	r.new_game(3)
	for i in 28:
		r.dev_autoplay()
	gs.run = r
	gs._title.visible = false
	gs.go("forge")
	await get_tree().create_timer(0.4).timeout
	gs._open["forge:more"] = true
	gs.render()
	await get_tree().create_timer(0.4).timeout
	gs.close_sheet()
	gs._bands.clear()
	gs._hide_band()
	for c in gs._toast_box.get_children():
		c.queue_free()
	await get_tree().create_timer(0.6).timeout
	await _check("forge_top", gs._body)
	for y in [300, 900, 1500, 99999]:
		gs._scroll.scroll_vertical = y
		await get_tree().process_frame
		await get_tree().process_frame
		await _check("forge_y%d" % y, gs._body)
	# 한 프레임에 조금씩 (손가락 스크롤처럼)
	gs._scroll.scroll_vertical = 0
	await get_tree().process_frame
	for i in 60:
		gs._scroll.scroll_vertical += 37
		await get_tree().process_frame
	await get_tree().process_frame
	await _check("forge_drag", gs._body)
	# 시트 (카드 상세 —— 아래에서 올라오는 시트 안의 재료 타일) : 올라오는 동안 화면에 들어온 타일이 그려져야 한다
	gs.card_info(str(r.pool().keys()[0]))
	await get_tree().create_timer(0.8).timeout
	await _check("sheet", gs._sheet_body)
	gs._sheet_scroll.scroll_vertical = 9999
	await get_tree().process_frame
	await get_tree().process_frame
	await _check("sheet_bottom", gs._sheet_body)
	gs.close_sheet()
	await get_tree().create_timer(0.5).timeout
	# 창 크기
	gs._scroll.scroll_vertical = 0
	await get_tree().process_frame
	get_window().size = Vector2i(720, 1500)
	await get_tree().create_timer(0.5).timeout
	await _check("resize", gs._body)
	gs.go("draw")
	await get_tree().create_timer(0.5).timeout
	await _check("draw", gs._fixed)
	get_tree().quit()
