extends Node
## 11/12 페이즈 개편 클라이언트 점검 —— 이 장면 안에 서버를 띄우고 게임 화면(GameScreen + Online)이 점검 방(test)을 혼자 돈다.
## 실행: godot --headless --path . res://tests/phase_flow.tscn -- --gonline=ws://127.0.0.1:7794 --gname=시험 --gcreate=test --gstart=1 --gauto
## (포트는 7777 이 아닌 것으로 —— 집 PC 서버와 겹치지 않게)
## ① 아침마다 가운데 띠 「아침이 밝았습니다」 ② 단계별 can_act(draw/form) 가 규칙과 같고, 막힌 행동은 act 가 null 을 돌려준다
## ③ 서버가 넘어갔는데 재생 중이던 전투는 닫힌다(싱크 밀림 건너뛰기) ④ 전투 메뉴에 '게임 나가기' 콜백이 있다

var fails := []
var seen := {}
var bands := 0
var skipped := 0


func _ready() -> void:
	var url := ""
	for s in OS.get_cmdline_user_args():
		if s.begins_with("--gonline="):
			url = s.trim_prefix("--gonline=")
	var server := MatchServer.new()
	server.port = int(url.get_slice(":", 2))
	add_child(server)
	var gs: GameScreen = load("res://scenes/game.tscn").instantiate()
	add_child(gs)
	var t := 0.0
	var last_sno := -1
	var was_playing := false
	while t < 90.0:
		await get_tree().create_timer(0.1).timeout
		t += 0.1
		var on: Online = gs.online
		if on == null or on.room.is_empty() or not on.in_game:
			continue
		var rm: Dictionary = on.room
		var st := str(rm.get("stage", ""))
		if st == "over" or int(rm.get("day", 0)) >= 2:
			break
		bands += gs.band_log.count("아침이 밝았습니다")
		gs.band_log.clear()
		if int(rm.stage_no) != last_sno:
			if was_playing and not (gs.battle_visible() and not gs._battle.finished):
				skipped += 1
			last_sno = int(rm.stage_no)
			seen[st] = int(seen.get(st, 0)) + 1
			var want_form: bool = st in Room.ACT_STAGES
			if on.can_act("form") != want_form:
				fails.append("%s 에서 can_act(form) %s" % [st, str(on.can_act("form"))])
			if not want_form and gs.run != null and gs.act("auto_deploy") != null:
				fails.append("%s 에서 막힌 편성이 실행됐다" % st)
			if st == "evening_prep" and on.can_act("draw"):
				fails.append("저녁 준비에 징집이 열려 있다")
		was_playing = gs.battle_visible() and not gs._battle.finished
	if not gs._battle.leave_cb.is_valid():
		fails.append("전투 메뉴 나가기 콜백이 없다")
	if bands < 2:
		fails.append("아침 띠 %d번" % bands)
	print("단계 %s · 아침 띠 %d번 · 밀린 재생 건너뜀 %d번" % [str(seen), bands, skipped])
	print("FAIL: ", fails if not fails.is_empty() else "없음")
	if gs.online != null:
		gs.online.leave()
	server.queue_free()
	get_tree().quit(1 if not fails.is_empty() else 0)
