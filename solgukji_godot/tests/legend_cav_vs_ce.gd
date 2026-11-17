extends Node
## 11/17 사용자 「전설 기병이랑 전설 책사 붙여 볼래?」 —— 5등급(전설) 기병 9 대 책사 9, 진영 바꿔 가며.
## 실행: godot --headless --path . res://tests/legend_cav_vs_ce.tscn [-- --trials=12]
## 장수별 직접 피해(평타 · 잔기술 · 기술 · 고유기 · 반격 · 기타, 초과 피해 제외) + 지속 피해, 고유기 유무로 나눠 본다. 수치는 바꾸지 않는다
const Audit = preload("res://tests/motion5_role_audit.gd")

func _ready() -> void:
	var args := {}
	for arg in OS.get_cmdline_user_args():
		var pair := arg.trim_prefix("--").split("=", true, 1)
		args[pair[0]] = pair[1] if pair.size() > 1 else "1"
	var trials := int(args.get("trials", "12"))
	var pool := DB.by_tier(5).filter(func(k): return not DB.is_foe(k) and not DB.is_kiin(k))
	var cav := pool.filter(func(k): return DB.C[k].tag == "기병")
	var ce := pool.filter(func(k): return DB.C[k].tag == "책사")
	print("POOL 기병 ", cav.size(), ": ", ", ".join(cav.map(func(k): return DB.person(k))))
	print("POOL 책사 ", ce.size(), ": ", ", ".join(ce.map(func(k): return DB.person(k))))
	var helper := Audit.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 91700
	var wins := {"기병": 0, "책사": 0, "draw": 0}
	var per := {}      # 이름 -> 합계
	var lens := []
	for trial in trials:
		var n_side := mini(int(args.get("size", "9")), mini(cav.size(), ce.size()))      # 같은 수끼리 (전설 책사는 5명뿐)
		var a := helper.pick_unique(cav, n_side, rng)
		var b := helper.pick_unique(ce, n_side, rng)
		for mirror in [false, true]:
			var bt := Audit.Probe.new(91700 + trial)
			var side_a := b if mirror else a
			var side_b := a if mirror else b
			var res := bt.run(DB.auto_place(side_a, "eorin"), "eorin", 100, null, DB.auto_place(side_b, "eorin"), "eorin", 100, null, "", "", [], {"A": "auto", "B": "auto"})
			lens.append(res.len)
			var cav_camp := "B" if mirror else "A"
			if res.draw:
				wins.draw += 1
			elif res.win == (cav_camp == "A"):
				wins["기병"] += 1
			else:
				wins["책사"] += 1
			for u in bt.units:
				var r: Dictionary = bt.row(u.key)
				var direct := 0.0
				for k in Audit.DAMAGE:
					direct += float(r[k])
				var nm := DB.person(u.c.id)
				var acc: Dictionary = per.get(nm, {"tag": u.c.tag, "n": 0, "direct": 0.0, "basic": 0.0, "minor": 0.0, "skill": 0.0, "ult": 0.0, "dot": 0.0, "ults": 0, "has_ult": u.ult != null, "alive": 0, "max": 0.0})
				acc.n += 1
				acc.direct += direct
				acc.basic += float(r.basic)
				acc.minor += float(r.minor)
				acc.skill += float(r.skill)
				acc.ult += float(r.ultimate)
				acc.dot += float(u.dot)
				acc.ults += u.ult_n
				acc.alive += 1 if u.alive else 0
				acc.max += u.max
				per[nm] = acc
		print("TRIAL ", trial + 1, "/", trials)
	helper.free()
	var total := float(wins["기병"] + wins["책사"] + wins.draw)
	print("RESULT 기병 승 %d · 책사 승 %d · 무 %d (%d판) · 평균 길이 %.1f초" % [wins["기병"], wins["책사"], wins.draw, total, lens.reduce(func(x, y): return x + y, 0.0) / maxf(1.0, lens.size())])
	var names := per.keys()
	names.sort_custom(func(x, y): return per[x].direct + per[x].dot > per[y].direct + per[y].dot)
	for nm in names:
		var acc: Dictionary = per[nm]
		var n := float(acc.n)
		print("UNIT %s|%s|고유기%s|판 %d|직접 %d|평타 %d|잔기술 %d|기술 %d|고유기피해 %d|지속 %d|고유기횟수 %.2f|생존 %.0f%%" % [nm, acc.tag, "O" if acc.has_ult else "X", acc.n,
			roundi(acc.direct / n), roundi(acc.basic / n), roundi(acc.minor / n), roundi(acc.skill / n), roundi(acc.ult / n), roundi(acc.dot / n), acc.ults / n, 100.0 * acc.alive / n])
	get_tree().quit()
