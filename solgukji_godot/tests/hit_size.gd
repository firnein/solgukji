extends Node
## 11/19 병종별 한 대 크기 —— 그림 화면은 대상 최대 병력의 12% 넘는 타격만 숫자를 띄운다 (Hud.damage). 그 문턱을 넘는 타격이 얼마나 되나
func _ready() -> void:
	var by := {}
	for tier in [5, 7]:
		var pool := DB.by_tier(tier).filter(func(k): return not DB.is_foe(k))
		for i in 8:
			var rng := RandomNumberGenerator.new()
			rng.seed = 4400 + i
			var a := []
			var b := []
			for j in 9:
				a.append(pool[rng.randi() % pool.size()])
				b.append(pool[rng.randi() % pool.size()])
			var r: Dictionary = RtBattle.new(4400 + i).run(DB.auto_place(a, "eorin"), "eorin", 100, null, DB.auto_place(b, "hagik"), "hagik", 100, null, "", "", [], {"A": "smart", "B": "smart"})
			var mx := {}
			var tg := {}
			for u in r.roster:
				mx[str(u.key)] = float(u.max)
				tg[str(u.key)] = str(u.tag)
			for e in r.ev:
				if e.get("fx") in ["phys", "int"] and e.has("n") and e.has("f") and tg.has(str(e.get("a", ""))) and mx.has(str(e.f)):
					var k := "%d급 %s%s" % [tier, tg[str(e.a)], "(돌격)" if e.get("painted_charge", "") == "hit" else ""]
					var v: Array = by.get(k, [0, 0, 0.0])
					v[0] += 1
					var q := float(e.n) / float(mx[str(e.f)])
					if q >= 0.12:
						v[1] += 1
					v[2] += q
					by[k] = v
	var ks := by.keys()
	ks.sort()
	for k in ks:
		var v: Array = by[k]
		print("%s 타격 %d · 12%% 넘는 것 %d%% · 한 대 평균 %.1f%%" % [k, v[0], 100 * v[1] / v[0], 100.0 * v[2] / v[0]])
	get_tree().quit()
