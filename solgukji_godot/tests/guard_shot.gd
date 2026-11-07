extends Node
## 11/8 카드 디테일 '물리 피해 · 갑옷 30%' 줄 · 전투 탭 토벌 성질 줄 캡처 —— 실행 (창이 뜬다):
##   godot --path . --resolution 540x1200 res://tests/guard_shot.tscn -- --out=폴더 [--card=카드id] [--play=3]
## card_<id>.png (카드 디테일) · war_quest.png (--play 만큼 자동 진행한 판의 전투 탭 —— 2일차부터 토벌 성질 줄이 보인다)

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
	r.new_game(int(args.get("seed", "3")))
	for i in int(args.get("play", "3")):
		r.dev_autoplay()
	gs.run = r
	gs._title.visible = false
	gs.go("war")
	await get_tree().create_timer(0.6).timeout
	gs.close_sheet()
	gs._bands.clear()
	gs._hide_band()
	for c in gs._toast_box.get_children():
		c.queue_free()
	await get_tree().create_timer(0.8).timeout
	await _shot("%s/war_quest.png" % out)
	print("전투 탭: %d일차 성질 %s" % [r.day + 1, DB.trait_text(DB.quest_trait(r.day))])
	var cards: Array = str(args.get("card", "")).split(",", false)
	if cards.is_empty():
		for tg in ["창병", "술사", "궁병"]:      # 그 병종의 전설 한 장씩
			cards.append(DB.by_tier(5).filter(func(k): return DB.C[k].tag == tg and not DB.is_kiin(k))[0])
	for k in cards:
		gs.card_info(k)
		await get_tree().create_timer(0.9).timeout
		await _shot("%s/card_%s.png" % [out, k])
		print("카드 %s (%s · %s): %s" % [k, DB.C[k].name, DB.C[k].tag, DB.guard_text(DB.C[k].tag)])
		gs.close_sheet()
		await get_tree().create_timer(0.4).timeout
	get_tree().quit()


func _shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
