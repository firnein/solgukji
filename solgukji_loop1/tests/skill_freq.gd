extends Node
## 일반기 · 고유기 빈도와 몫 —— 실행: godot --headless --path . res://tests/skill_freq.tscn [-- --games=20]
## 같은 등급 무작위 9장끼리. 한 판(초)마다 일반 기술 · 고유기가 몇 번 터지고, 준 피해에서 평타 · 일반 기술 · 고유기가 차지하는 몫.
const FORMS := ["eorin", "hagik", "bongsi", "anwol", "bangwon", "anhaeng", "chuhaeng", "jangsa"]

func _ready() -> void:
	var args := {}
	for s in OS.get_cmdline_user_args():
		var kv := s.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	var games := int(args.get("games", "20"))
	var names := {}
	for k in DB.C:
		for sk in DB.C[k].get("sks", []):
			names[sk.n] = true
	print("등급  판길이  부대당 기술  부대당 고유기  기술/고유기  피해 몫(평타 · 기술 · 고유기)")
	for t in [5, 6, 7, 8, 0]:          # 0 = 실제 판에 가까운 혼합 덱 (신화 1 · 불멸 2 · 초월 3 · 전설 3)
		var pool: Array = DB.by_tier(t) if t > 0 else []
		var rng := RandomNumberGenerator.new()
		rng.seed = 500 + t
		var sk := 0.0
		var ul := 0.0
		var ln := 0.0
		var dm := 0.0
		var sd := 0.0
		var ud := 0.0
		for g in games:
			var a := []
			var b := []
			for i in 9:
				var src: Array = pool if t > 0 else DB.by_tier([8, 7, 7, 6, 6, 6, 5, 5, 5][i])
				a.append(src[rng.randi() % src.size()])
				b.append(src[rng.randi() % src.size()])
			var fa: String = FORMS[rng.randi() % FORMS.size()]
			var fb: String = FORMS[rng.randi() % FORMS.size()]
			var r := RtBattle.make(rng.randi()).run(DB.auto_place(a, fa), fa, 100, null, DB.auto_place(b, fb), fb, 100, null, "", "", [], {"A": "smart", "B": "smart"})
			for e in r.ev:
				if e.get("fx") == "skill" and names.has(e.get("name", "")): sk += 1
				elif e.get("fx") == "ult": ul += 1
			ln += float(r.get("len", 0.0))
			dm += r.stats.dmg
			sd += r.stats.sk_dmg
			ud += r.stats.ult_dmg
		var nu := 18.0 * games
		print("%s  %5.1f초   %5.2f        %5.2f        %5.1f배      %d%% · %d%% · %d%%" % [DB.TIER[t].n if t > 0 else "혼합", ln / games, sk / nu, ul / nu, sk / maxf(1, ul),
			roundi(100 * (dm - sd - ud) / dm), roundi(100 * sd / dm), roundi(100 * ud / dm)])
	get_tree().quit()
