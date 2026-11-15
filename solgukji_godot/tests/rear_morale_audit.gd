extends Node
## 동일 시드/편성으로 위치별 고유기와 고병력 패주를 비교한다.

func card(person: String, tier := -1) -> String:
	var pick := ""
	for k in DB.C:
		if DB.person(k) == person and DB.C[k].kind not in ["foe", "retired"] and (tier < 0 or DB.C[k].tier == tier):
			if pick == "" or DB.C[k].tier > DB.C[pick].tier:
				pick = k
	assert(pick != "", person)
	return pick

func _ready() -> void:
	var small := RtBattle.new(40)
	var tank := card("조인")
	small._setup([tank], "eorin", 100, null, [tank], "eorin", 100, null, "", "", [], {"A": "manual", "B": "manual"})
	var defender = small.units[0]
	var attacker = small.units[1]
	attacker.m = {"jolt": 10.0}
	defender.m = {}
	var initial: float = defender.troops
	for i in 10:
		small.phys_hit(attacker, defender, 0.00001, true)
	print("TINY_HITS troop_ratio=%.6f morale=%.3f lost=%.1f" % [defender.troops / defender.max, defender.morale, initial - defender.troops])
	var front: Array = [card("관평", 6), card("방덕", 6), card("주태", 6), card("장료", 7), card("허저", 7), card("태사자", 7), card("황충", 7), card("육손", 7), card("순욱", 7)]
	var enemy: Array = [card("관우", 7), card("장비", 7), card("마초", 7), card("장료", 7), card("감녕", 7), card("여몽", 7), card("주유", 7), card("사마의", 7), card("조조", 7)]
	for person in ["제갈량", "조인"]:
		for slot in [1, 7]:
			if "--tank-only" in OS.get_cmdline_user_args() and (person != "조인" or slot != 7):
				continue
			var fired := 0
			var early_dead := 0
			var healthy_rout := 0
			var first := 0.0
			for seed_id in 12:
				var mine: Array = front.duplicate()
				mine[slot] = card(person)
				var bt := RtBattle.new(5100 + seed_id)
				var result := bt.run(mine, "eorin", 100, null, enemy, "hagik", 100, null, "", "", [], {"A": "smart", "B": "smart"})
				var subject = bt.units.filter(func(u): return u.camp == "A" and u.slot == slot)[0]
				if subject.ult_n > 0:
					fired += 1
					for event in result.ev:
						if event.get("fx") == "ult" and event.get("a") == subject.key:
							first += float(event.tm)
							break
				elif not subject.alive:
					early_dead += 1
				if not subject.alive and subject.troops / subject.max > 0.7:
					healthy_rout += 1
					var causes: Array = result.ev.filter(func(e): return e.get("fx") == "rout" and e.get("f") == subject.key)
					print("HEALTHY_ROUT seed=%d morale=%.1f troops=%.1f%% event=%s collapse=%s decisive=%s" % [5100 + seed_id, subject.morale, subject.troops / subject.max * 100, causes[-1].get("t", "") if not causes.is_empty() else "", result.stats.get("collapse_A", "none"), result.ev.any(func(e): return e.get("fx") == "decisive")])
			print("AUDIT %s tier=%d slot=%d fired=%d/12 first=%.1f no_ult_dead=%d healthy_rout=%d" % [person, DB.C[card(person)].tier, slot, fired, first / maxf(1, fired), early_dead, healthy_rout])
	get_tree().quit()
