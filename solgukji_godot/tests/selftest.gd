extends Node
## 전투 엔진 자가 점검 —— 원본 조정 탭(runSim)과 같은 구성으로 돌려 승률·턴 수를 본다.

func _ready() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var styles := ["물리", "지략", "균형"]
	for pv in [60, 300, 900]:
		var turns := 0
		var wins := {}
		var n := 60
		for i in n:
			var sa: String = styles[i % 3]
			var sb: String = styles[(i + 1) % 3]
			var a := DB.gen_board(pv, sa, rng)
			var b := DB.gen_board(pv, sb, rng)
			var r := Battle.new(i).run(DB.auto_place(a.cards, a.form), a.form, 100, null,
				DB.auto_place(b.cards, b.form), b.form, 100, null)
			turns += r.turns
			var key := "%s>%s" % [sa, sb]
			wins[key] = wins.get(key, 0) + (1 if r.win else 0)
		print("PV %d  평균 %.1f턴  %s" % [pv, turns / float(n), wins])
	var r2 := Battle.new(1).run(DB.auto_place(DB.by_tier(8).slice(0, 9), "eorin"), "eorin", 100, null,
		DB.auto_place(DB.by_tier(6).slice(0, 9), "hagik"), "hagik", 100, null)
	print("신화9 vs 초월9: win=%s turns=%d events=%d mvp=%s" % [r2.win, r2.turns, r2.ev.size(), r2.mvp])
	var fx := {}
	for e in r2.ev:
		fx[e.get("fx", "-")] = fx.get(e.get("fx", "-"), 0) + 1
	print(fx)
	for e in r2.ev.slice(0, 12):
		print("  ", e.t)
	print("카드 %d · 조합 %d · 아이템 %d · 진형 %d" % [DB.C.size(), DB.RECOF.size(), DB.IT.size(), DB.FORM.size()])
	print("관우(c39) 스킬: ", DB.C["c39"].sk.n, " / ", DB.skill_desc(DB.C["c39"]))
	get_tree().quit()
