extends Node
## 11/19 사용자: 창병(조인 · 전위)이 붙어만 있고 숫자도 안 뜨고, 둘러싸여 사기로 패주한다 —— 그 장수 한 부대를 따라간다
## 실행: godot --headless --path . res://tests/spear_trace.tscn [-- --who=조인 --n=6 --log]

func _ready() -> void:
	var args := {}
	for arg in OS.get_cmdline_user_args():
		var kv := arg.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	var who := str(args.get("who", "조인"))
	var n := int(args.get("n", "6"))
	var cards := DB.C.keys().filter(func(k): return DB.person(k) == who and not DB.is_foe(k))
	cards.sort_custom(func(x, y): return DB.C[x].tier > DB.C[y].tier)
	print(who, " 카드: ", cards.map(func(k): return "%s %s %d급" % [k, DB.C[k].tag, DB.C[k].tier]))
	var k0: String = cards[0]
	var tier: int = DB.C[k0].tier
	var pool := DB.by_tier(tier).filter(func(k): return not DB.is_foe(k) and DB.person(k) != who)
	var tot := {}
	for i in n:
		var rng := RandomNumberGenerator.new()
		rng.seed = 99100 + i
		var a := [k0]
		var b := []
		var cand := pool.duplicate()
		var people := [who]
		while a.size() < 9:
			var k: String = cand[rng.randi_range(0, cand.size() - 1)]
			if not people.has(DB.person(k)):
				a.append(k); people.append(DB.person(k))
		people = []
		while b.size() < 9:
			var k: String = pool[rng.randi_range(0, pool.size() - 1)]
			if not people.has(DB.person(k)):
				b.append(k); people.append(DB.person(k))
		var bt := RtBattle.new(99100 + i)
		var r: Dictionary = bt.run(DB.auto_place(a, "eorin"), "eorin", 100, null, DB.auto_place(b, "hagik"), "hagik", 100, null, "", "", [], {"A": "smart", "B": "smart"})
		var me := -1
		for j in r.roster.size():
			if str(r.roster[j].id) == k0 and str(r.roster[j].camp) == "A":
				me = j
		var key := str(r.roster[me].key)
		var tag_of := {}
		for rr in r.roster:
			tag_of[str(rr.key)] = str(rr.tag)
		var s := {"len": float(r.len), "hits": 0, "dmg": 0.0, "hits_cnt": 0, "taken": 0.0, "taken_n": 0, "mloss": 0.0, "end": "생존", "end_t": float(r.len), "tr_end": 0.0, "mo_end": 0.0, "acts": 0, "foes_max": 0, "counter": 0, "small": 0}
		var prev: Array = r.ev[0].s[me]
		var first_hit := -1.0
		for e in r.ev:
			var fx = e.get("fx", "")
			if fx in ["phys", "int"] and str(e.get("a", "")) == key:
				s.hits += 1
				s.dmg += float(e.get("n", 0.0))
				if e.get("counter", false) or e.get("ctr", false): s.counter += 1
				if float(e.get("n", 0.0)) < 0.005 * float(r.roster[me].max): s.small += 1
				if first_hit < 0.0: first_hit = float(e.tm)
			if fx in ["phys", "int"] and str(e.get("f", "")) == key:
				s.taken += float(e.get("n", 0.0))
				s.taken_n += 1
			var cur: Array = e.s[me]
			if float(cur[1]) < float(prev[1]):
				s.mloss += float(prev[1]) - float(cur[1])
				var why := str(fx)
				if fx in ["phys", "int"]:
					why = ("맞음:" + str(tag_of.get(str(e.get("a", "")), "?"))) if str(e.get("f", "")) == key else ("남이 맞음:" + str(e.get("f", "")).left(1))
				elif fx == "":
					why = "?" + str(e.t).left(14)
				var mc: Dictionary = tot.get("mcause", {})
				mc[why] = float(mc.get(why, 0.0)) + float(prev[1]) - float(cur[1])
				tot["mcause"] = mc
			if int(prev[2]) == 1 and int(cur[2]) != 1:
				s.end = "패주" if float(cur[0]) > 0.0 else "전멸"
				s.end_t = float(e.tm)
				s.tr_end = float(cur[0]) / float(r.roster[me].max)
				s.mo_end = float(cur[1])
			prev = cur
			if args.has("log") and i == 0 and (str(e.get("a", "")) == key or str(e.get("f", "")) == key) and float(e.tm) < 20.0:
				print("    t=%.1f %s %s → %s n=%s 병력 %d%% 사기 %d %s" % [float(e.tm), fx, e.get("a", ""), e.get("f", ""), e.get("n", ""), int(100 * float(cur[0]) / float(r.roster[me].max)), int(cur[1]), str(e.t).left(50)])
		var u: Dictionary = r.roster[me]
		print("#%d %s(%s %d급 %s) 판 %.0f초 · 첫 타격 %.1f초 · 타격 %d번(초당 %.2f, 작은 것 %d) · 준 피해 %d(최대 병력의 %d%%) · 받은 타격 %d번 %d · 사기 잃음 %d · %s %.1f초 (병력 %d%% · 사기 %d)" % [i, u.name, u.tag, u.tier, u.line, s.len, first_hit, s.hits, s.hits / maxf(1.0, s.end_t), s.small, s.dmg, int(100 * s.dmg / float(u.max)), s.taken_n, s.taken, s.mloss, s.end, s.end_t, int(100 * s.tr_end), s.mo_end])
	var mc: Dictionary = tot.get("mcause", {})
	var ks := mc.keys()
	ks.sort_custom(func(x, y): return mc[x] > mc[y])
	print("사기를 잃은 까닭 (합): ", ks.slice(0, 12).map(func(k): return "%s %d" % [k, mc[k]]))
	get_tree().quit()
