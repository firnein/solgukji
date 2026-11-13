extends Node
## 봇 기준선 —— 봇이 자동으로 한 판을 끝까지 하며 플레이 기록(PlayLog)을 남긴다. 사람 플레이와 같은 형식이라 나란히 비교한다.
## 실행: godot --headless --path . res://tests/play_log_bot.tscn [-- --games=10 --seed=1]
## 결과: user://playlog_bot/*.jsonl → python tools/scripts/analyze_playlog.py 가 '봇 기준선' 으로 함께 읽는다

func _ready() -> void:
	var args := {}
	for s in OS.get_cmdline_user_args():
		var kv := s.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	var games := int(args.get("games", "10"))
	var s0 := int(args.get("seed", "1"))
	PlayLog.dir = "user://playlog_bot"
	Run.dev_log = true
	Run.dev_immortal = not args.has("mortal")      # 11/5 사용자: 봇은 멸망하지 않는다 (--mortal 이면 예전처럼)
	for g in games:
		var r := Run.new()
		r.new_game(s0 + g)
		PlayLog.new_game(r)
		var guard := 0
		while r.over == null and guard < 40:
			r.dev_autoplay()
			guard += 1
		print("판 %d (시드 %d): %s · %d승 %d패" % [g + 1, s0 + g, r.over.msg if r.over else "?", r.my_w, r.my_l])
	print("기록: ", ProjectSettings.globalize_path("user://playlog_bot"))
	get_tree().quit()
