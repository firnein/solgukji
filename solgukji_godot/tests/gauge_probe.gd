extends Node
## 11/19 고유기 게이지 진단 —— 기가 빠지는 원인(사건 종류 · 때린 병종)과 전투 초반 게이지. 판정은 건드리지 않고 사건 기록만 읽는다.
## 실행: godot --headless --path . res://tests/gauge_probe.tscn [-- --n=10 --tiers=6,7,8]

func _ready() -> void:
	var args := {}
	for arg in OS.get_cmdline_user_args():
		var kv := arg.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	var n := int(args.get("n", "10"))
	var tiers := Array(str(args.get("tiers", "6,7,8")).split(",")).map(func(x): return int(x))
	var drops := {}        # 원인 -> [횟수, 합]
	var victims := {}      # 맞은 병종 -> 도적에게 깎인 합
	var first := []        # 첫 사건 시각 · 그때 게이지 최대
	var full_early := 0
	var units_n := 0
	var guard := {}        # 도적 대책 —— 창병이 붙잡은 횟수 · 호위로 돌아선 횟수
	for i in n:
		var tier: int = tiers[i % tiers.size()]
		var pool := DB.by_tier(tier).filter(func(k): return not DB.is_foe(k))
		var rng := RandomNumberGenerator.new()
		rng.seed = 33100 + i
		var a := _pick(pool, rng)
		var b := _pick(pool, rng)
		var res: Dictionary = RtBattle.new(33100 + i).run(DB.auto_place(a, "eorin"), "eorin", 100, null, DB.auto_place(b, "hagik"), "hagik", 100, null, "", "", [], {"A": "auto", "B": "auto"})
		var tag_of := {}
		var key_i := {}
		for j in res.roster.size():
			tag_of[str(res.roster[j].key)] = str(res.roster[j].tag)
			key_i[str(res.roster[j].key)] = j
		var prev: Array = res.ev[0].s
		var first_hit_t := -1.0
		for e in res.ev:
			if first_hit_t < 0.0 and args.has("pre") and e.get("fx") in ["status", "debuff", "skill", "buff"]:
				print("      pre #%d t=%.2f %s %s a=%s f=%s %s" % [i, float(e.tm), e.get("fx"), e.get("st", e.get("name", "")), e.get("a", ""), e.get("f", ""), str(e.t).left(40)])
			if first_hit_t < 0.0 and e.get("fx") in ["phys", "int"]:
				first_hit_t = float(e.get("tm", e.get("t", 0.0)))
				var g := 0
				for s in e.s:
					g = maxi(g, int(s[4]))
				first.append([snappedf(first_hit_t, 0.1), g])
				for jj in e.s.size():
					if int(e.s[jj][4]) >= 60:
						var r: Dictionary = res.roster[jj]
						var ul = DB.ult_of(str(r.id))
						print("    #%d t=%.1f %s(%s 등급%d) 기 %d  기질 %s  turn_mul %.2f" % [i, first_hit_t, r.name, r.tag, r.tier, e.s[jj][4], str(ul.get("temper", "?")) if ul != null else "-", Battle.turn_mul])
					if int(e.s[jj][4]) >= 100:
						full_early += 1
			for j in e.s.size():
				var g0 := int(prev[j][4])
				var g1 := int(e.s[j][4])
				if g1 < g0 and int(e.s[j][5]) == int(prev[j][5]):      # 줄었는데 횟수는 그대로 —— 고유기를 쓴 게 아니다
					var who := str(e.get("a", ""))
					var cause := str(e.get("fx", "?"))
					if cause in ["phys", "int"] and tag_of.has(who) and who[0] != res.roster[j].key[0]:
						cause = "맞음:" + tag_of[who]
						if tag_of[who] == "도적":
							victims[str(res.roster[j].tag)] = int(victims.get(str(res.roster[j].tag), 0)) + (g0 - g1)
					elif cause == "skill" or cause == "sk":
						cause = "기술:" + str(e.get("name", ""))
					var d: Array = drops.get(cause, [0, 0])
					d[0] += 1
					d[1] += g0 - g1
					drops[cause] = d
			prev = e.s
		for k in ["rogue_held", "escort"]:
			guard[k] = int(guard.get(k, 0)) + int(res.stats.get(k, 0))
		for r in res.roster:
			if DB.ult_of(str(r.id)) != null:
				units_n += 1
	var keys := drops.keys()
	keys.sort_custom(func(x, y): return drops[x][1] > drops[y][1])
	print("게이지가 준 원인 (고유기 사용 제외) —— %d판 · 고유기 장수 %d" % [n, units_n])
	for k in keys.slice(0, 15):
		print("  %-20s %5d번  합 %6d" % [k, drops[k][0], drops[k][1]])
	print("도적에게 깎인 게이지 (맞은 병종별): ", victims)
	print("첫 타격 시각 · 그때 가장 높은 게이지: ", first)
	print("첫 타격 때 이미 가득 찬 장수 수: ", full_early)
	print("도적 대책 (창병 붙잡음 · 호위 후보): ", guard)
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
