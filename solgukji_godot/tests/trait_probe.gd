extends Node
## 특기 작동 점검 —— 실행: godot --headless --path . res://tests/trait_probe.tscn [-- --games=30]
## 등급마다 무작위 9장끼리 실시간 전투(RtBattle, 양쪽 영리)를 돌리며, 장수에 붙은 특기 효과 키(u.m)가
## 전투 중 실제로 읽혔는지(Battle.mv 가 0 이 아닌 값으로 불렸는지) 센다. 붙었는데 한 번도 안 읽힌 키 = 작동하지 않는 특기.


func _ready() -> void:
	var args := {}
	for s in OS.get_cmdline_user_args():
		var kv := s.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	var games := int(args.get("games", "30"))
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	Battle.probe_on = true
	var held := {}       # 키 -> 붙은 장수 수
	var who := {}        # 키 -> 예시 장수 이름
	for t in [3, 4, 5, 6, 7, 8]:
		var pool: Array = DB.by_tier(t).filter(func(k): return not DB.is_foe(k))
		if t == 8:
			pool += DB.by_tier(7).filter(func(k): return not DB.is_foe(k))
		for g in games:
			var sides := []
			for s in 2:
				var cs := []
				var seen := {}
				var sh := pool.duplicate()
				for i in sh.size():
					var j := rng.randi() % sh.size()
					var tmp = sh[i]; sh[i] = sh[j]; sh[j] = tmp
				for k in sh:
					if cs.size() >= 9: break
					if seen.has(DB.person(k)): continue
					seen[DB.person(k)] = true
					cs.append(k)
				sides.append(DB.auto_place(cs, "eorin"))
			var b := RtBattle.make(rng.randi() % 1000000)
			b.run(sides[0], "eorin", 100, null, sides[1], "eorin", 100, null, "", "", [], {"A": "smart", "B": "smart"})
			for u in b.units:
				for k in u.m:
					if float(u.m[k]) != 0.0:
						held[k] = int(held.get(k, 0)) + 1
						if not who.has(k): who[k] = u.c.name
	var dead := []
	var lines := []
	var ks := held.keys()
	ks.sort()
	for k in ks:
		var n := int(Battle.probe.get(k, 0))
		lines.append("%s 붙음 %d · 읽힘 %d%s" % [k, held[k], n, "  ← 작동 안 함 (%s)" % who[k] if n == 0 else ""])
		if n == 0: dead.append(k)
	for l in lines: print(l)
	print("특기 효과 키 %d개 중 작동 안 함 %d개: %s" % [ks.size(), dead.size(), ", ".join(dead)])
	get_tree().quit()
