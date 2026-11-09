extends Node
## 진행 점검 —— 실행: godot --headless --path . res://tests/game.tscn [-- --runs=20] [--noshield]
## 사람 대신 Run.dev_autoplay 의 단순한 규칙으로 한 판을 끝까지 돈다 (징집 → 선택권 → 조합 → 자동 편성 →
## 토벌 → 대전 → 다음 페이즈 … → 토너먼트). 페이즈마다 저장했다가 다시 읽어 이어 간다.


func _ready() -> void:
	var args := {}
	for s in OS.get_cmdline_user_args():
		var kv := s.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	var runs := int(args.get("runs", "20"))
	Run.dev_snap_on = args.has("snap")      # --snap=경로.json —— 토벌 직전 편성을 모은다 (quest_tune --snap 이 기준 덱으로 쓴다)
	if args.has("oldquest"):        # 토벌 고정 편성(황건적) 대신 예전 무작위 —— 비교용
		DB.QUEST_ROSTERS = []
	if args.has("nohorde"):         # 11/7 토벌 대군(잡병 추가) 끄기 —— 비교용
		Run.horde_enabled = false
	if args.has("noshield"):        # 11/8 갑옷 · 결계 · 깎기 · 토벌 성질 · 봇 덱 섞기 끄기 —— 비교용
		Battle.shield_enabled = false
		DB.bot_mix = false
	var qtry := {}                # "일차-단계" -> [도전, 실패]
	var wins := 0
	var phases := 0
	for n in runs:
		var r := Run.new()
		r.new_game(100 + n)
		var guard := 0
		var myth_at := ""
		while r.over == null and guard < 40:
			guard += 1
			var qk := "%d-%d" % [r.day + 1, r.phase + 1]
			var st0 := r.strikes
			var done0 := r.quest_done
			r.dev_autoplay()
			if not done0 and (r.quest_done or r.strikes > st0 or r.day * 3 + r.phase != 0):
				var e: Array = qtry.get(qk, [0, 0])
				e[0] += 1
				if r.strikes > st0: e[1] += 1
				qtry[qk] = e
			if r.myth_made and myth_at == "":
				myth_at = "%d일차 %s" % [r.day + 1, Run.PHASE_N[r.phase]]
			var d: Dictionary = JSON.parse_string(JSON.stringify(r.to_dict(), "", false, true))
			var r2 := Run.new()
			r2.from_dict(d)
			r = r2
		if r.over.win:
			wins += 1
		phases += r.day * 3 + r.phase
		print("판 %d: %s · %s · %d일차 %s · PV %d · %d승 %d패 · 경고 %d · 민심 %d · 신화 %s" % [n, "우승" if r.over.win else "탈락",
			r.over.msg, r.day + 1, Run.PHASE_N[r.phase], r.my_pv(), r.my_w, r.my_l, r.strikes, r.hp, myth_at if myth_at != "" else "없음"])
	print("우승 %d / %d · 평균 도달 페이즈 %.1f" % [wins, runs, phases / float(runs)])
	if args.has("snap"):
		var sf := FileAccess.open(str(args.snap), FileAccess.WRITE)
		sf.store_string(JSON.stringify(Run.dev_snap))
		sf.close()
		print("편성 %d개 저장: %s" % [Run.dev_snap.size(), args.snap])
	var ks := qtry.keys()
	ks.sort_custom(func(a, b): return int(a.split("-")[0]) * 3 + int(a.split("-")[1]) < int(b.split("-")[0]) * 3 + int(b.split("-")[1]))
	var line := []
	for k in ks:
		line.append("%s %d/%d" % [k, qtry[k][0] - qtry[k][1], qtry[k][0]])
	print("토벌 승/도전: " + " · ".join(line))
	get_tree().quit()
