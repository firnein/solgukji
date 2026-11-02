extends Node
## 토벌 고정 편성 점검 —— 실행: godot --headless --path . res://tests/quest_check.tscn [-- --games=60 --mul=1.0]
## 단계마다 '그 단계에 맞는 플레이어' = 원본 QPV × mul 의 무작위 덱(장비 없음, 덱에 맞는 작전)이 황건 편성을 몇 % 이기는지.
## 11/2: 자동 진행(tests/game)은 덱 운영이 서툴러 기준으로 쓰기 어렵다 —— 이 값을 70~80% 로 맞춘다.

func _ready() -> void:
	var args := {}
	for s in OS.get_cmdline_user_args():
		var kv := s.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	var games := int(args.get("games", "60"))
	var mul := float(args.get("mul", "1.0"))
	var styles := ["물리", "지략", "균형"]
	var line := []
	for d in DB.QUEST_ROSTERS.size():
		for p in 3:
			var q: Dictionary = DB.QUEST_ROSTERS[d][p]
			var rng := RandomNumberGenerator.new()
			rng.seed = 7000 + d * 10 + p
			var w := 0.0
			for i in games:
				var eb := DB.gen_board(DB.D.QPV[d][p] * mul, styles[i % 3], rng)
				var mine := DB.auto_place(eb.cards, eb.form)
				var foe := DB.auto_place(q.cards, q.form)
				var bt := {"a": {"cards": mine, "form": eb.form, "morale": 100, "equip": [], "tac": Run.recommend_tac(mine)[0]},
					"b": {"cards": foe, "form": q.form, "morale": 100, "equip": [], "tac": Run.recommend_tac(foe)[0]},
					"seed": rng.randi() % 1000000, "title": "", "foe": ""}
				var r := Run.simulate(bt, [], Run.policy_for(bt))
				w += 1.0 if r.win else (0.5 if r.draw else 0.0)
			line.append("%d-%d %s %.0f%%" % [d + 1, p + 1, q.name, w / games * 100])
			print(line[-1])
	get_tree().quit()
