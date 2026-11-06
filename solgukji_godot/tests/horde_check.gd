extends Node
## 토벌 대군 점검 (11/7) —— 실행: godot --headless --path . res://tests/horde_check.tscn [-- --games=30 --mul=1.0 --trb=1.0]
## 단계마다 원본 QPV × mul 무작위 덱이 황건 편성을 이기는 비율 · 전투 길이 · 남은 병력을 대군(잡병 추가) 끔 / 켬으로 견준다.
## 게임과 같게 일차 사기 배율(Run.QUEST_MORALE) · 병력 배율(Run.QUEST_TR) 을 쓴다. trb 는 대군일 때 적 병력 배율에 더 곱한다.

func _ready() -> void:
	var args := {}
	for s in OS.get_cmdline_user_args():
		var kv := s.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	var games := int(args.get("games", "30"))
	var mul := float(args.get("mul", "1.0"))
	var trb := float(args.get("trb", "1.0"))
	var styles := ["물리", "지략", "균형"]
	var sum := [0.0, 0.0]
	for d in DB.QUEST_ROSTERS.size():
		for p in 3:
			var q: Dictionary = DB.QUEST_ROSTERS[d][p]
			var row := []
			for horde in [false, true]:
				var rng := RandomNumberGenerator.new()
				rng.seed = 7000 + d * 10 + p
				var w := 0.0
				var ln := 0.0
				var left := 0.0
				for i in games:
					var eb := DB.gen_board(DB.D.QPV[d][p] * mul, styles[i % 3], rng)
					var mine := DB.auto_place(eb.cards, eb.form)
					var foe := DB.auto_place(q.cards, q.form)
					var form: String = q.form
					var tr := float(Run.QUEST_TR[d])
					if horde:
						foe.append_array(DB.horde_rabble(q.cards, int(Run.QUEST_HORDE[d]), rng))
						form = DB.HORDE_PFX + form
						tr *= trb
					var bt := {"a": {"cards": mine, "form": eb.form, "morale": 100, "equip": [], "tac": Run.recommend_tac(mine)[0]},
						"b": {"cards": foe, "form": form, "morale": int(int(q.get("morale", 100)) * float(Run.QUEST_MORALE[d])), "equip": [],
							"tac": Run.recommend_tac(foe)[0], "tr_mul": tr},
						"seed": rng.randi() % 1000000, "title": "", "foe": ""}
					var r := Run.simulate(bt, [], Run.policy_for(bt))
					w += 1.0 if r.win else (0.5 if r.draw else 0.0)
					ln += float(r.get("len", 0.0))
					left += float(r.left)
				row.append("%s 승 %3.0f%% · %4.1f초 · 남은 병력 %.0f" % ["대군" if horde else "예전", w / games * 100, ln / games, left / games])
				sum[1 if horde else 0] += w / games
			print("%d-%d %-10s | %s | %s" % [d + 1, p + 1, q.name, row[0], row[1]])
	var n := DB.QUEST_ROSTERS.size() * 3
	print("평균 승률  예전 %.0f%% · 대군 %.0f%%" % [sum[0] / n * 100, sum[1] / n * 100])
	get_tree().quit()
