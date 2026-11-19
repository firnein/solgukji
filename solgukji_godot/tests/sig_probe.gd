extends Node
## 11/19 장수 개성 점검 —— 개성 키가 실제로 발동하나 (사건 · 판정 횟수), 끄고 켠 판 길이 · 승률.
## 실행: godot --headless --path . res://tests/sig_probe.tscn [-- --n=24 --tiers=3,4,5,6,7,8 --off]

func _ready() -> void:
	var args := {}
	for arg in OS.get_cmdline_user_args():
		var kv := arg.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	var n := int(args.get("n", "24"))
	Battle.sig_enabled = not args.has("off")
	var says := {}
	var have := {}
	for tier in Array(str(args.get("tiers", "3,4,5,6,7,8")).split(",")).map(func(x): return int(x)):
		var pool := DB.by_tier(tier).filter(func(k): return not DB.is_foe(k))
		var len_sum := 0.0
		for i in n:
			var rng := RandomNumberGenerator.new()
			rng.seed = 91100 + i
			var a := _pick(pool, rng)
			var b := _pick(pool, rng)
			var bt := RtBattle.new(91100 + i)
			var r: Dictionary = bt.run(DB.auto_place(a, "eorin"), "eorin", 100, null, DB.auto_place(b, "hagik"), "hagik", 100, null, "", "", [], {"A": "smart", "B": "smart"})
			len_sum += float(r.len)
			for u in bt.units:
				for k in u.m:
					if k in load("res://scripts/sig_rt.gd").KEYS:
						have[k] = int(have.get(k, 0)) + 1
			for e in r.ev:
				if e.get("sig", false) or str(e.get("t", "")).contains("의 십면매복") or str(e.get("t", "")).contains("의 양보"):
					var t := str(e.get("t", ""))
					var key := t.substr(t.find("의 ") + 2).split(" ——")[0]
					says[key] = int(says.get(key, 0)) + 1
		print("등급 %d · 판 %.1f초" % [tier, len_sum / n])
	print("개성 키를 가진 부대 (키: 부대 수): ", have)
	print("눈에 보이는 발동 (말풍선 사건): ", says)
	get_tree().quit()


func _pick(pool: Array, rng: RandomNumberGenerator) -> Array:
	var out := []
	var people := []
	var cand := pool.duplicate()
	while out.size() < 9 and not cand.is_empty():
		var k: String = cand.pop_at(rng.randi_range(0, cand.size() - 1))
		if not people.has(DB.person(k)):
			out.append(k)
			people.append(DB.person(k))
	return out
