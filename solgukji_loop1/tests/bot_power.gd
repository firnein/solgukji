extends Node
## 봇 세기 점검 —— 실행: godot --headless --path . res://tests/bot_power.tscn [-- --games=40 --mul=1.0]
## 새 봇(장비 · 작전) 대 예전 봇(장비 없음 · 영리) —— 같은 PV, 자리 바꿔 두 번. 보급 시점마다 새 봇 승률.

func _ready() -> void:
	var args := {}
	for s in OS.get_cmdline_user_args():
		var kv := s.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	var games := int(args.get("games", "40"))
	var mul := float(args.get("mul", "1.0"))
	var styles := ["물리", "지략", "균형"]
	for p in [1, 4, 8, 12, 16]:
		var d: int = p / 3
		var pv: float = DB.D.QPV[d][p % 3]
		var rng := RandomNumberGenerator.new()
		rng.seed = 77 + p
		var w := 0.0
		for g in games:
			var st: String = styles[rng.randi() % 3]
			var st2: String = styles[rng.randi() % 3]
			var nb := Run.bot_side(pv * mul, st, p, rng)
			var eb := DB.gen_board(pv, st2, rng)
			var ob := {"cards": DB.auto_place(eb.cards, eb.form), "form": eb.form}
			var seed := rng.randi() % 1000000
			var np: String = Run.TACS[nb.tac].pol
			var r1 := RtBattle.make(seed).run(nb.cards, nb.form, 100, nb.equip, ob.cards, ob.form, 100, null, "", "", [], {"A": np, "B": "smart"})
			var r2 := RtBattle.make(seed).run(ob.cards, ob.form, 100, null, nb.cards, nb.form, 100, nb.equip, "", "", [], {"A": "smart", "B": np})
			w += (1.0 if r1.win else (0.5 if r1.draw else 0.0)) + (1.0 if (not r2.win and not r2.draw) else (0.5 if r2.draw else 0.0))
		print("보급 %d (%d일차) PV %d: 새 봇 승률 %.0f%%" % [p, d + 1, pv, w / (games * 2.0) * 100])
	get_tree().quit()
