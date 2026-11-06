extends Node
## 제목 화면 설정 점검 (11/7) —— 실행: godot --path . res://tests/title_settings.tscn -- --out=폴더
## 제목 화면의 '설정' 버튼을 실제로 눌러 ① 시트가 맨 위에 보이는지 ② 품질 버튼을 누르면 값이 바뀌고 저장되는지 본다. 캡처 3장.

func _ready() -> void:
	var args := {}
	for s in OS.get_cmdline_user_args():
		var kv := s.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	var out := str(args.get("out", "user://"))
	var gs: GameScreen = load("res://scenes/game.tscn").instantiate()
	add_child(gs)
	await get_tree().create_timer(1.5).timeout
	await _shot(out + "/1_title.png")
	var sb := _find(gs._title, "설정")
	print("제목 설정 버튼: ", sb != null)
	sb.pressed.emit()
	await get_tree().create_timer(0.8).timeout
	var top: Control = null
	for c in gs.get_children():
		if c is Control and c.visible:
			top = c
	print("시트 열림 %s · 맨 위 보이는 노드 %s · 시트가 맨 위 %s" % [gs._sheet.visible, top.name if top else "-", top == gs._sheet])
	await _shot(out + "/2_settings.png")
	var q0 := Settings.quality
	var want := (q0 + 1) % 3
	var qb := _find(gs._sheet_body, Settings.QUALITY_N[want])
	qb.pressed.emit()
	await get_tree().create_timer(0.5).timeout
	var cf := ConfigFile.new()
	cf.load("user://settings.cfg")
	print("품질 %d → %d (원하는 값 %d) · 저장 파일 %s" % [q0, Settings.quality, want, cf.encode_to_text().replace("\n", " ")])
	await _shot(out + "/3_changed.png")
	Settings.quality = q0
	Settings.apply()
	Settings.save_cfg()
	get_tree().quit()


func _find(n: Node, text: String) -> Button:
	if n is Button and n.text == text and n.is_visible_in_tree():
		return n
	for c in n.get_children():
		var r := _find(c, text)
		if r != null:
			return r
	return null


func _shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
