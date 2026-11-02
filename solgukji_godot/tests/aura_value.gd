extends Node
## 위세의 값 —— 같은 카드 9장끼리 붙이고 한쪽만 위세를 켠다. 실행: godot --headless --path . res://tests/aura_value.tscn [-- --games=30]
## 초월 9장 · 초월 3 + 전설 6 · 신화 1 + 전설 8 편성에서 위세를 켠 쪽의 승률

func _ready() -> void:
	var args := {}
	for s in OS.get_cmdline_user_args():
		var kv := s.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	var games := int(args.get("games", "30"))
	for mix in [[6, 9, 5, 0], [6, 3, 5, 6], [8, 1, 5, 8]]:
		var rng := RandomNumberGenerator.new()
		rng.seed = 77 + mix[1]
		var w := 0.0
		for g in games:
			var hi: Array = DB.by_tier(mix[0])
			var lo: Array = DB.by_tier(mix[2])
			var cards := []
			for i in mix[1]:
				cards.append(hi[rng.randi() % hi.size()])
			for i in mix[3]:
				cards.append(lo[rng.randi() % lo.size()])
			var pl := DB.auto_place(cards, "eorin")
			var sd := rng.randi() % 1000000
			Battle.aura_camp = "A"
			var r1 := RtBattle.make(sd).run(pl, "eorin", 100, null, pl, "eorin", 100, null, "", "", [], {"A": "smart", "B": "smart"})
			Battle.aura_camp = "B"
			var r2 := RtBattle.make(sd).run(pl, "eorin", 100, null, pl, "eorin", 100, null, "", "", [], {"A": "smart", "B": "smart"})
			w += (1.0 if r1.win else (0.5 if r1.draw else 0.0)) + (1.0 if (not r2.win and not r2.draw) else (0.5 if r2.draw else 0.0))
		Battle.aura_camp = ""
		print("%s %d + %s %d: 위세 켠 쪽 승률 %.0f%%" % [DB.TIER[mix[0]].n, mix[1], DB.TIER[mix[2]].n, mix[3], w / (games * 2.0) * 100])
	get_tree().quit()
