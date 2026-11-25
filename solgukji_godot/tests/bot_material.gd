extends Node

func _ready() -> void:
	var days := []
	for day in 7:
		days.append({"pv": [], "immortal": 0, "myth": 0, "gear": 0, "pool": []})
	var valid := true
	for sample in 28:
		var b := {"name": "bot", "style": "균형", "material": true, "pv": 0.0}
		for phase in 21:
			var side := Run.bot_side_of(b, 4800 + sample, phase)
			var save := b.duplicate(true)
			if Run.bot_side_of(save, 4800 + sample, phase).cards != side.cards:
				printerr("Bot changed cards twice in one phase: ", sample, "/", phase)
				valid = false
			# JSON 경계를 지난 뒤 다음 단계에도 같은 재료와 난수 상태가 유지된다.
			if phase == 7:
				var round_trip: Dictionary = JSON.parse_string(JSON.stringify(save))
				var consistent: bool = Run.bot_side_of(round_trip, 4800 + sample, phase + 1).cards == Run.bot_side_of(save, 4800 + sample, phase + 1).cards
				if not consistent:
					printerr("Bot save differs after loading at sample ", sample)
				valid = valid and consistent
			if phase % 3 != 2:
				continue
			var cards: Array = side.cards.filter(func(k): return DB.C.has(k))
			var d: Dictionary = days[phase / 3]
			d.pv.append(cards.reduce(func(pv, k): return pv + int(DB.C[k].pv), 0))
			d.immortal += int(cards.any(func(k): return DB.C[k].tier == 7))
			d.myth += int(cards.any(func(k): return DB.C[k].tier == 8))
			d.pool.append(int(b.pv))      # 가방까지 (사람 기록 phase_end my_pv 와 같은 셈)
			d.gear += side.equip.filter(func(x): return x != null).size()      # 11/25 장비를 낀 칸 수 (사람 2~4일차 4.3 · 5.9 · 6.9 · 7.0)
			if cards.filter(func(k): return DB.C[k].tier == 8).size() > 1:
				printerr("Bot has multiple myth cards: ", sample, "/", phase)
				valid = false
	for i in days.size():
		var d: Dictionary = days[i]
		d.pv.sort()
		d.pool.sort()
		print("MATERIAL|day=%d|median_pv=%d|immortal=%d/28|myth=%d/28|gear=%.1f|pool=%d" % [i + 1, (d.pv[13] + d.pv[14]) / 2, d.immortal, d.myth, d.gear / 28.0, (d.pool[13] + d.pool[14]) / 2])
	valid = valid and days[0].myth == 0 and days[2].myth > 0 and days[2].myth < 28 and days[5].immortal > 0 and days[6].myth > 0
	print("MATERIAL|", "PASS" if valid else "FAIL")
	get_tree().quit(0 if valid else 1)
