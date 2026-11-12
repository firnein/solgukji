extends Node
## 인연 UI 캡처 (11/11) —— 창이 있어야 한다: godot --path . --resolution 720x1280 --position 495,1500 res://tests/inyeon_shot.tscn -- --out=폴더 [--who=관우] [--deck=유비,관우,장비,조조,주유,제갈량] [--own=여포,공손찬]
## 편성 화면(진형 칸 모서리 표시 · 머리 칩) · 인연 시트 · 디테일창(--who 의 인연 줄) · 갈무리창을 차례로 찍는다.

func _ready() -> void:
	var args := {}
	for s in OS.get_cmdline_user_args():
		var kv := s.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	var out := str(args.get("out", "user://"))
	PlayLog.enabled = false
	Run.dev_immortal = true
	var gs: GameScreen = load("res://scenes/game.tscn").instantiate()
	add_child(gs)
	await get_tree().process_frame
	var r := Run.new()
	r.new_game(3)
	gs.run = r
	gs._title.visible = false
	# 덱 —— 인물 이름 -> 고유기를 쓸 수 있는 카드 (가장 높은 등급)
	var deck := str(args.get("deck", "유비,관우,장비,조조,주유,제갈량,손권")).split(",", false)
	for i in deck.size():
		var k := DB.inyeon_card_of_person(deck[i])
		if k != "":
			r.give(k)
			r.place(i, k)
	for p in str(args.get("own", "여포,공손찬,황충")).split(",", false):      # 손패에만 있는 장수
		var k := DB.inyeon_card_of_person(p, false)
		if k != "":
			r.give(k)
	print("가진 카드: ", r.pool().keys().map(func(k): return DB.C[k].name))
	gs.go("deploy")
	await get_tree().create_timer(0.8).timeout
	gs.close_sheet()
	gs._bands.clear()
	gs._hide_band()
	for c in gs._toast_box.get_children():
		c.queue_free()
	await get_tree().create_timer(0.5).timeout
	await _shot("%s/deploy.png" % out)
	gs.deploy.inyeon_sheet()
	await get_tree().create_timer(0.8).timeout
	await _shot("%s/sheet.png" % out)
	var who := DB.inyeon_card_of_person(str(args.get("who", "관우")))
	gs.card_info(who)
	await get_tree().create_timer(0.8).timeout
	await _shot("%s/detail.png" % out)
	# 11/13 인연 줄(라벨 '인연')을 창 위쪽에 맞춰 한 장 —— 주제 · 인연기 · 규칙 줄 확인용
	var yl := _find_label(gs._sheet_scroll, "인연")
	if yl != null:
		gs._sheet_scroll.scroll_vertical += int(yl.global_position.y - gs._sheet_scroll.global_position.y) - 40
		await get_tree().create_timer(0.4).timeout
		await _shot("%s/detail_inyeon.png" % out)
	gs._sheet_scroll.scroll_vertical = 9999
	await get_tree().create_timer(0.4).timeout
	await _shot("%s/detail_bottom.png" % out)
	# 안 가진 장수의 디테일창 (조합 탭에서 여는 것과 같다) · 갈무리창
	gs.recipe_sheet(who)
	await get_tree().create_timer(0.8).timeout
	await _shot("%s/recipe.png" % out)
	get_tree().quit()


func _find_label(n: Node, text: String) -> Label:
	if n is Label and n.text == text and n.is_visible_in_tree():
		return n
	for c in n.get_children():
		var r := _find_label(c, text)
		if r != null:
			return r
	return null


func _shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
	print("저장 ", path)
