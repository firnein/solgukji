extends Node
## 기술 쓰임 점검 —— 높은 등급 판 몇 번에서 기술 이름별로 몇 번 터졌는지 (고유 기술이 실제로 쓰이는지)
func _ready() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 9
	var cnt := {}
	var skd := 0.0
	var tot := 0.0
	var sig := {}
	for nm in DB.LINES.skills:
		sig[DB.LINES.skills[nm].n] = true
	for g in 6:
		var x := Run.bot_side(1000, ["물리", "지략", "균형"][g % 3], 15, rng)
		var y := Run.bot_side(1000, ["지략", "균형", "물리"][g % 3], 15, rng)
		var r := RtBattle.make(rng.randi()).run(x.cards, x.form, 100, x.equip, y.cards, y.form, 100, y.equip, "", "", [], {"A": "smart", "B": "smart"})
		skd += r.get("stats", {}).get("sk_dmg", 0.0)
		tot += r.get("stats", {}).get("dmg", 0.0)
		for e in r.ev:
			if e.get("fx") == "skill":
				cnt[e.name] = cnt.get(e.name, 0) + 1
	var a := 0
	var b := 0
	for k in cnt:
		if sig.has(k): a += cnt[k]
		else: b += cnt[k]
	var ks := cnt.keys()
	ks.sort_custom(func(p, q): return cnt[p] > cnt[q])
	print("고유 %d번 · 공용 %d번 · 기술 피해 비율 %.0f%%" % [a, b, skd / maxf(1.0, tot) * 100])
	print(", ".join(ks.map(func(k): return "%s%s %d" % ["★" if sig.has(k) else "", k, cnt[k]])))
	get_tree().quit()
