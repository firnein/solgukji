extends Node
## 실시간 엔진(RtBattle) 시너지 on/off 쌍대 비교 (docs/의견_재미_1110.md 8절 1번)
## 실행: godot --headless --path . res://tests/syn_rt.tscn [-- --tier=5 --pairs=100 --by=fac|tag --focus=6]
## 한 쌍 = 같은 등급 풀에서 뽑은 '몰은 덱'(--focus 장이 같은 세력/병종) 대 '섞은 덱'(무작위 9장).
## 같은 덱 · 같은 시드 · 진영 교대로 시너지 끔/켬을 각각 돌려, 몰은 덱의 승률 차를 본다. save.json 은 건드리지 않는다.

func _ready() -> void:
	var args := {}
	for s in OS.get_cmdline_user_args():
		var kv := s.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	var tier := int(args.get("tier", "5"))
	var pairs := int(args.get("pairs", "100"))
	var by: String = str(args.get("by", "fac"))
	var focus := int(args.get("focus", "6"))
	var pool: Array = DB.by_tier(tier)
	var groups := {}
	for k in pool:
		var g = DB.C[k][by]
		if not groups.has(g): groups[g] = []
		groups[g].append(k)
	var big := groups.keys().filter(func(g): return groups[g].size() >= focus)
	print("── 시너지 on/off · 등급 %d · 풀 %d장 · 기준 %s(%d장 이상 묶음 %d개) · %d쌍 × 진영교대" % [tier, pool.size(), by, focus, big.size(), pairs])
	if big.is_empty():
		print("묶음이 없어 중단")
		get_tree().quit()
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = 1110
	var cases := []
	var used := {}
	for i in pairs:
		var g = big[rng.randi() % big.size()]
		var src: Array = groups[g].duplicate()
		var fo := []
		for j in focus:
			var n := rng.randi() % src.size()
			fo.append(src[n])
			src.remove_at(n)
		var rest: Array = pool.filter(func(k): return not fo.has(k))
		while fo.size() < 9:
			fo.append(rest.pop_at(rng.randi() % rest.size()))
		var mx := []
		var rp: Array = pool.duplicate()
		for j in 9:
			mx.append(rp.pop_at(rng.randi() % rp.size()))
		cases.append({"f": fo, "m": mx, "seed": rng.randi() % 1000000, "g": g})
		used[g] = used.get(g, 0) + 1
	var res := {}
	for mode in [false, true]:
		Battle.synergy_enabled = mode
		var w := 0.0
		for c in cases:
			var a := DB.auto_place(c.f, "eorin")
			var b := DB.auto_place(c.m, "eorin")
			var r1 := RtBattle.make(c.seed).run(a, "eorin", 100, null, b, "eorin", 100, null, "", "", [], {"A": "smart", "B": "smart"})
			var r2 := RtBattle.make(c.seed).run(b, "eorin", 100, null, a, "eorin", 100, null, "", "", [], {"A": "smart", "B": "smart"})
			w += (1.0 if r1.win else (0.5 if r1.draw else 0.0)) + (1.0 if (not r2.win and not r2.draw) else (0.5 if r2.draw else 0.0))
		res[mode] = w / (cases.size() * 2.0) * 100.0
		print("   시너지 %s: 몰은 덱 승률 %.1f%% (%d판)" % ["켬" if mode else "끔", res[mode], cases.size() * 2])
	Battle.synergy_enabled = false
	print("   차이 %+.1f%%p · 묶음 분포 %s" % [res[true] - res[false], str(used)])
	get_tree().quit()
