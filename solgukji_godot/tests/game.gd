extends Node
## 진행 점검 —— 실행: godot --headless --path . res://tests/game.tscn [-- --runs=20]
## 사람 대신 Run.dev_autoplay 의 단순한 규칙으로 한 판을 끝까지 돈다 (징집 → 선택권 → 조합 → 자동 편성 →
## 토벌 → 대전 → 다음 페이즈 … → 토너먼트). 페이즈마다 저장했다가 다시 읽어 이어 간다.


func _ready() -> void:
	var args := {}
	for s in OS.get_cmdline_user_args():
		var kv := s.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	var runs := int(args.get("runs", "20"))
	var wins := 0
	var phases := 0
	for n in runs:
		var r := Run.new()
		r.new_game(100 + n)
		var guard := 0
		while r.over == null and guard < 40:
			guard += 1
			r.dev_autoplay()
			var d: Dictionary = JSON.parse_string(JSON.stringify(r.to_dict(), "", false, true))
			var r2 := Run.new()
			r2.from_dict(d)
			r = r2
		if r.over.win:
			wins += 1
		phases += r.day * 3 + r.phase
		print("판 %d: %s · %s · %d일차 %s · PV %d · %d승 %d패 · 경고 %d" % [n, "우승" if r.over.win else "탈락",
			r.over.msg, r.day + 1, Run.PHASE_N[r.phase], r.my_pv(), r.my_w, r.my_l, r.strikes])
	print("우승 %d / %d · 평균 도달 페이즈 %.1f" % [wins, runs, phases / float(runs)])
	get_tree().quit()
