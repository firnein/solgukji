extends Node
## UI 감사 보충 캡처 —— 선택권 시트 · 편성 보유 패 열림
func _ready() -> void:
	var out := ""
	for s in OS.get_cmdline_user_args():
		if s.begins_with("--out="):
			out = s.trim_prefix("--out=")
	PlayLog.enabled = false
	Run.dev_immortal = true
	var gs: GameScreen = load("res://scenes/game.tscn").instantiate()
	add_child(gs)
	await get_tree().process_frame
	var r := Run.new()
	r.new_game(3)
	for i in 9:
		r.dev_autoplay()
	gs.run = r
	gs._title.visible = false
	gs.go("draw")
	await get_tree().create_timer(1.0).timeout
	gs.close_sheet()
	gs._bands.clear()
	gs._hide_band()
	for c in gs._toast_box.get_children():
		c.queue_free()
	var t := -1
	for k in r.tickets:
		if int(r.tickets[k]) > 0:
			t = maxi(t, int(k))
	print("선택권 ", r.tickets, " → ", t)
	if t >= 0:
		gs.picker(t)
		await get_tree().create_timer(0.9).timeout
		await _shot(out + "/22_picker_sheet.png")
		gs.close_sheet()
	gs.deploy.seg = "hand"
	gs.go("deploy")
	await get_tree().create_timer(1.0).timeout
	await _shot(out + "/23_deploy_hand_open.png")
	gs.deploy.seg = ""
	gs._confirm_new()      # 11/14 UI 4단계 —— 새 판 확인 시트
	await get_tree().create_timer(0.8).timeout
	await _shot(out + "/24_confirm_new.png")
	get_tree().quit()


func _shot(p: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(p)
	print("저장 ", p)
