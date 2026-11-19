extends Node
## 11/19 기질별로 고유기를 못 쓴 까닭 —— 기가 안 찼나 · 찼는데 못 썼나(조건) · 먼저 쓰러졌나. 사건 기록만 읽는다
## 실행: godot --headless --path . res://tests/temper_probe.tscn [-- --n=30 --tiers=6,7,8]

func _ready() -> void:
	var args := {}
	for arg in OS.get_cmdline_user_args():
		var kv := arg.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	var n := int(args.get("n", "30"))
	var tiers := Array(str(args.get("tiers", "6,7,8")).split(",")).map(func(x): return int(x))
	var agg := {}      # 기질 -> 셈
	var tags := {}     # 맹장 병종 -> [수, 발동]
	for i in n:
		var tier: int = tiers[i % tiers.size()]
		var pool := DB.by_tier(tier).filter(func(k): return not DB.is_foe(k))
		var rng := RandomNumberGenerator.new()
		rng.seed = 55100 + i
		var a := _pick(pool, rng)
		var b := _pick(pool, rng)
		var res: Dictionary = RtBattle.new(55100 + i).run(DB.auto_place(a, "eorin"), "eorin", 100, null, DB.auto_place(b, "hagik"), "hagik", 100, null, "", "", [], {"A": str(args.get("pol", "smart")), "B": str(args.get("pol", "smart"))})
		var end_t := float(res.ev[-1].get("tm", 0.0))
		for j in res.roster.size():
			var r: Dictionary = res.roster[j]
			var ul = DB.ult_of(str(r.id))
			if ul == null or not DB.C.has(str(r.id)):
				continue
			var tp := Battle.temper_name(DB.C[str(r.id)], ul)
			var c0 := int(res.ev[0].s[j][5])
			var full_t := -1.0
			var dead_t := -1.0
			var fired := false
			var full_secs := 0.0
			var last_t := 0.0
			var last_full := false
			for e in res.ev:
				var s: Array = e.s[j]
				var t := float(e.get("tm", 0.0))
				if last_full:
					full_secs += t - last_t
				last_t = t
				last_full = int(s[4]) >= 100 and int(s[2]) == 1
				if full_t < 0.0 and int(s[4]) >= 100:
					full_t = t
				if int(s[5]) < c0:
					fired = true
				if dead_t < 0.0 and int(s[2]) != 1:
					dead_t = t
			var g: Dictionary = agg.get(tp, {"n": 0, "fired": 0, "never_full": 0, "full_no_fire": 0, "dead_before_full": 0, "full_t": 0.0, "full_secs": 0.0, "dead_t": 0.0, "dead_n": 0})
			g.n += 1
			if fired:
				g.fired += 1
			elif full_t >= 0.0:
				g.full_no_fire += 1
				g.full_secs += full_secs
			elif dead_t >= 0.0:
				g.dead_before_full += 1
			else:
				g.never_full += 1
			if full_t >= 0.0:
				g.full_t += full_t
			if dead_t >= 0.0:
				g.dead_t += dead_t / maxf(end_t, 1.0)
				g.dead_n += 1
			agg[tp] = g
			if tp == "맹장":
				var tg: Array = tags.get(str(r.tag), [0, 0])
				tg[0] += 1
				tg[1] += 1 if fired else 0
				tags[str(r.tag)] = tg
	print("기질 | 수 | 발동 | 찼는데 못 씀(찬 채 평균 초) | 차기 전 쓰러짐 | 끝까지 안 참 | 가득 찬 평균 시각 | 쓰러진 비율 · 판 진행의 몇 %에서")
	for tp in agg:
		var g: Dictionary = agg[tp]
		var full_n: int = g.n - g.never_full - g.dead_before_full
		print("%s | %d | %d%% | %d%% (%.1f초) | %d%% | %d%% | %.1f초 | %d%% · %d%%" % [tp, g.n, 100 * g.fired / g.n, 100 * g.full_no_fire / g.n, g.full_secs / maxf(1, g.full_no_fire), 100 * g.dead_before_full / g.n, 100 * g.never_full / g.n, g.full_t / maxf(1, full_n), 100 * g.dead_n / g.n, int(100 * g.dead_t / maxf(1, g.dead_n))])
	print("맹장 병종별 [수, 발동]: ", tags)
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
