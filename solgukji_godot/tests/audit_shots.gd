extends Node
## UI 감사용 화면 한 바퀴 캡처 —— 창이 있어야 한다:
##   godot --path . --resolution 720x1280 res://tests/audit_shots.tscn -- --out=폴더 [--seed=3] [--play=9]
## 제목 · 설정 · 새 판(띠 · 안내 말풍선) · 중반 판 다섯 탭 · 카드 상세 · 인연 · 상점 · 소식 · 전투 · 결과창 · 엔딩 · 온라인 시트를 차례로 찍는다.

var out := "user://"


func _ready() -> void:
	var args := {}
	for s in OS.get_cmdline_user_args():
		var kv := s.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	out = str(args.get("out", "user://"))
	PlayLog.enabled = false
	Run.dev_immortal = true
	Run.delete_save()
	var gs: GameScreen = load("res://scenes/game.tscn").instantiate()
	add_child(gs)
	await _wait(1.8)
	await _shot("01_title")
	gs._settings_sheet()
	await _wait(0.8)
	await _shot("02_settings")
	gs.close_sheet()
	await _wait(0.5)
	# 새 판 —— 띠 · 안내 말풍선
	gs._new_game()
	await _wait(0.35)
	await _shot("03_newgame_band")
	await _wait(2.5)
	await _shot("04_draw_day1_coach")
	gs._coach_finish()
	gs.go("forge")
	await _wait(0.8)
	await _shot("05_forge_day1")
	# 중반 판
	var r := Run.new()
	r.new_game(int(args.get("seed", "3")))
	for i in int(args.get("play", "9")):
		r.dev_autoplay()
	r.grain = maxi(r.grain, 30)
	gs.run = r
	gs.go("draw")
	await _wait(0.4)
	await _shot("06_mid_band_toast")
	await _wait(0.4)
	_clean(gs)
	await _wait(0.6)
	await _shot("07_draw_mid")
	gs.go("forge")
	await _wait(0.8)
	_clean(gs)
	await _shot("08_forge_mid")
	gs.go("deploy")
	await _wait(0.8)
	_clean(gs)
	await _shot("09_deploy_mid")
	gs.go("war")
	await _wait(0.8)
	_clean(gs)
	await _shot("10_war_mid")
	gs.go("more")
	await _wait(0.8)
	_clean(gs)
	await _shot("11_more_mid")
	# 카드 상세 (불멸 · 인연 카드)
	var k7 := ""
	for k in DB.by_tier(7):
		if DB.inyeon_card(k):
			k7 = k
			break
	if k7 == "":
		k7 = DB.by_tier(7)[0]
	r.give(k7)
	gs.card_info(k7)
	await _wait(0.8)
	await _shot("12_card_detail_t7")
	gs._sheet_scroll.scroll_vertical = 9999
	await _wait(0.4)
	await _shot("13_card_detail_t7_bottom")
	gs.close_sheet()
	gs.go("deploy")
	await _wait(0.5)
	gs.deploy.inyeon_sheet()
	await _wait(0.8)
	await _shot("14_inyeon_sheet")
	gs.close_sheet()
	await _wait(0.4)
	gs._shop_sheet()
	await _wait(0.8)
	await _shot("15_shop")
	gs.close_sheet()
	await _wait(0.4)
	gs._news_sheet()
	await _wait(0.8)
	await _shot("16_news")
	gs.close_sheet()
	await _wait(0.4)
	# 전투
	gs.go("war")
	await _wait(0.4)
	gs._start("quest")
	await _wait(6.0)
	await _shot("17_battle_mid")
	gs._battle._set_speed(8.0)
	await gs._battle.ended
	await _wait(2.6)
	await _shot("18_battle_report")
	# 엔딩 (멸망)
	gs._hide_report()
	gs.hide_battle()
	await _wait(0.4)
	r.over = {"win": false, "msg": "세력이 무너졌습니다", "rank": 5}
	gs.show_ending(gs.ending_info())
	await _wait(1.6)
	await _shot("19_ending_anim")
	await _wait(3.0)
	await _shot("20_ending_summary")
	gs._ending_close()
	r.over = null
	# 온라인 (접속 시트만 —— 서버에는 붙지 않는다)
	gs._title.visible = true
	gs._go_online()
	await _wait(0.8)
	await _shot("21_online_connect")
	get_tree().quit()


func _clean(gs: GameScreen) -> void:
	gs.close_sheet()
	gs._bands.clear()
	gs._hide_band()
	for c in gs._toast_box.get_children():
		c.queue_free()


func _wait(s: float) -> void:
	await get_tree().create_timer(s).timeout


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [out, name])
	print("저장 ", name)
