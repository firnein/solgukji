extends Node
## 등급 전투력 점검 —— 실행: godot --headless --path . res://tests/tier_power.tscn [-- --games=40]
## 한 부대(높은 등급) 대 여러 부대(낮은 등급)를 같은 병종 무작위로 붙여 이긴 비율을 본다. 자리를 바꿔 두 번.
## 신화 1 대 불멸 1 · 2, 신화 1 대 초월 2 · 3, 불멸 1 대 초월 1 · 2.

func _ready() -> void:
	var args := {}
	for s in OS.get_cmdline_user_args():
		var kv := s.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	var games := int(args.get("games", "40"))
	for m in [[8, 7, 1], [8, 7, 2], [8, 6, 2], [8, 6, 3], [7, 6, 1], [7, 6, 2], [6, 5, 2], [5, 4, 2]]:
		var rng := RandomNumberGenerator.new()
		rng.seed = 31 + m[0] * 10 + m[2]
		var w := 0.0
		for g in games:
			var hi: Array = DB.by_tier(m[0]).filter(func(k): return not DB.is_foe(k))
			var lo: Array = DB.by_tier(m[1]).filter(func(k): return not DB.is_foe(k))
			var a := [hi[rng.randi() % hi.size()]]
			var b := []
			for i in m[2]:
				b.append(lo[rng.randi() % lo.size()])
			var pa := DB.auto_place(a, "eorin")
			var pb := DB.auto_place(b, "eorin")
			var sd := rng.randi() % 1000000
			var r1 := RtBattle.make(sd).run(pa, "eorin", 100, null, pb, "eorin", 100, null, "", "", [], {"A": "smart", "B": "smart"})
			var r2 := RtBattle.make(sd).run(pb, "eorin", 100, null, pa, "eorin", 100, null, "", "", [], {"A": "smart", "B": "smart"})
			w += (1.0 if r1.win else (0.5 if r1.draw else 0.0)) + (1.0 if (not r2.win and not r2.draw) else (0.5 if r2.draw else 0.0))
		print("%s 1 대 %s %d: 높은 쪽 승률 %.0f%%" % [DB.TIER[m[0]].n, DB.TIER[m[1]].n, m[2], w / (games * 2.0) * 100])
	get_tree().quit()
