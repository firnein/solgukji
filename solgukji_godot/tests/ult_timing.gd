extends Node
## 고유기 시각 점검 —— 실행: godot --headless --path . res://tests/ult_timing.tscn -- --snap=편성.json [--days=3,4,5,6]
## 자동 진행이 짠 실제 덱(tests/game --snap)으로 그날 토벌을 치러, 장수마다 첫 고유기 시각(초) · 판당 횟수 · 고유기 피해 몫을 모은다.
## 너무 일찍(10초 안) · 자주 터지는 장수를 찾는다
func _ready() -> void:
	var args := {}
	for s in OS.get_cmdline_user_args():
		var kv := s.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	var days: Array = Array(str(args.get("days", "3,4,5,6")).split(",")).map(func(x): return int(x) - 1)
	var snaps: Array = JSON.parse_string(FileAccess.open(str(args.snap), FileAccess.READ).get_as_text())
	var per := {}     # 카드 이름 -> {n, first(합), early, ults, dmg, tot}
	var games := 0
	var lens := 0.0
	var ultd := 0.0
	var alld := 0.0
	for s in snaps:
		if not days.has(int(s.d)):
			continue
		var q: Dictionary = DB.QUEST_ROSTERS[int(s.d)][int(s.p)]
		var foe := DB.auto_place(q.cards, q.form)
		var bt := {"a": s.a, "b": {"cards": foe, "form": q.form, "morale": int(q.get("morale", 100)), "equip": [], "tac": Run.recommend_tac(foe)[0]},
			"seed": 1000 + games, "title": "", "foe": ""}
		var r := Run.simulate(bt, [], Run.policy_for(bt))
		games += 1
		lens += float(r.get("len", 0))
		ultd += r.stats.ult_dmg
		alld += r.stats.dmg
		var seen := {}
		for e in r.ev:
			if e.get("fx") != "ult":
				continue
			var key: String = e.a
			var ro: Dictionary = r.roster.filter(func(x): return x.key == key)[0]
			var nm: String = ro.name + ("" if ro.camp == "A" else "(적)")
			if not per.has(nm):
				per[nm] = {"n": 0, "first": 0.0, "early": 0, "ults": 0, "tier": ro.tier, "tag": ro.tag}
			per[nm].ults += 1
			if not seen.has(key):
				seen[key] = true
				per[nm].n += 1
				per[nm].first += float(e.tm)
				if float(e.tm) < 10.0: per[nm].early += 1
	print("판 %d · 평균 길이 %.1f초 · 고유기 피해 몫 %d%%" % [games, lens / games, roundi(100 * ultd / maxf(1, alld))])
	var ks := per.keys()
	ks.sort_custom(func(a, b): return per[a].first / per[a].n < per[b].first / per[b].n)
	print("이름 · 등급 · 병종 · 쓴 판 · 첫 고유기 평균(초) · 10초 안 · 판당 횟수")
	for k in ks.slice(0, 25):
		var p: Dictionary = per[k]
		if p.n < 3: continue
		print("%s · %d · %s · %d · %.1f · %d · %.1f" % [k, p.tier, p.tag, p.n, p.first / p.n, p.early, float(p.ults) / p.n])
	get_tree().quit()
