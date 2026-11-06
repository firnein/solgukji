extends Node
## 장수별 기여도 —— 실시간 엔진판 (11/7, tests/balance.gd 는 예전 턴 엔진 · 자리 한 번이라 높은 등급 평균이 치우쳤다)
## 실행: godot --headless --path . res://tests/rt_contrib.tscn [-- --tier=5 --trials=12]
## 덱 A = 같은 등급 무작위 8장 + 대상 1장, 덱 B = 같은 8장 + 같은 등급 무작위 1장. 판마다 같은 시드 · 진형이라 카드끼리 짝지어 비교된다.
## 자리를 바꿔 두 번 싸운다. 50% 면 같은 등급 평균만큼 일한다. 결과 user://rt_contrib_<등급>.csv

const FORMS := ["eorin", "hagik", "bongsi", "anwol", "bangwon", "anhaeng", "chuhaeng", "jangsa"]


func _ready() -> void:
	var args := {}
	for s in OS.get_cmdline_user_args():
		var kv := s.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	var tier: int = int(args.get("tier", "5"))
	var trials: int = int(args.get("trials", "12"))
	var ids: Array = DB.by_tier(tier)
	# 판마다 같은 상황: 기준 8장 · 채움 1장 · 진형 · 시드
	var cases := []
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242 + tier
	for i in trials:
		var base := []
		while base.size() < 8:
			var k: String = ids[rng.randi() % ids.size()]
			if not base.any(func(x): return DB.person(x) == DB.person(k)):
				base.append(k)
		var fill: String = ids[rng.randi() % ids.size()]
		cases.append({"base": base, "fill": fill, "fa": FORMS[rng.randi() % FORMS.size()], "fb": FORMS[rng.randi() % FORMS.size()], "seed": rng.randi() % 1000000})
	var rows := []
	for k in ids:
		var w := 0.0
		var n := 0
		for c in cases:
			var base: Array = c.base.filter(func(x): return DB.person(x) != DB.person(k))
			var fill: String = c.fill
			if DB.person(fill) == DB.person(k) or base.any(func(x): return DB.person(x) == DB.person(fill)):
				for x in ids:
					if DB.person(x) != DB.person(k) and not base.any(func(y): return DB.person(y) == DB.person(x)):
						fill = x
						break
			while base.size() < 8:
				for x in ids:
					if DB.person(x) != DB.person(k) and DB.person(x) != DB.person(fill) and not base.any(func(y): return DB.person(y) == DB.person(x)):
						base.append(x)
						break
			var a := DB.auto_place(base + [k], c.fa)
			var b := DB.auto_place(base + [fill], c.fa)
			var r1 := RtBattle.make(c.seed).run(a, c.fa, 100, null, b, c.fa, 100, null, "", "", [], {"A": "smart", "B": "smart"})
			var r2 := RtBattle.make(c.seed).run(b, c.fa, 100, null, a, c.fa, 100, null, "", "", [], {"A": "smart", "B": "smart"})
			w += (1.0 if r1.win else (0.5 if r1.draw else 0.0)) + (1.0 if (not r2.win and not r2.draw) else (0.5 if r2.draw else 0.0))
			n += 2
		rows.append({"k": k, "w": w / n})
	rows.sort_custom(func(x, y): return x.w > y.w)
	var f := FileAccess.open("user://rt_contrib_%d.csv" % tier, FileAccess.WRITE)
	f.store_line("id,name,tag,kiin,win")
	var avg := 0.0
	var kn := 0
	var kw := 0.0
	for r in rows:
		var c: Dictionary = DB.C[r.k]
		f.store_line("%s,%s,%s,%d,%.3f" % [r.k, c.name, c.tag, 1 if DB.is_kiin(r.k) else 0, r.w])
		avg += r.w
		if DB.is_kiin(r.k):
			kn += 1
			kw += r.w
	f.close()
	var line := func(r): return "%s(%s) %.0f%%" % [DB.C[r.k].name, DB.C[r.k].tag, r.w * 100]
	print("━━ %s %d장 · %d판×2 · 평균 %.0f%% (최고 %.0f%% / 최저 %.0f%%)%s" % [DB.TIER[tier].n, rows.size(), trials, avg / rows.size() * 100,
		rows[0].w * 100, rows[-1].w * 100, (" · 기인 %d장 평균 %.0f%%" % [kn, kw / kn * 100]) if kn > 0 else ""])
	print("  상위: ", ", ".join(rows.slice(0, 5).map(line)))
	print("  하위: ", ", ".join(rows.slice(rows.size() - 5).map(line)))
	get_tree().quit()
