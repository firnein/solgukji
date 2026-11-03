extends Node
## 병종 역할 점검 —— 실행: godot --headless --path . res://tests/tag_role.tscn [-- --games=40 --tiers=4,5,6,7,8]
## 같은 등급 무작위 9장끼리 붙여, 병종마다 한 부대가 실제로 한 일을 모은다 (팀 평균 = 1.00):
##   피해 = 준 병력 피해 · 사기 = 준 사기 피해 · 치료 = 아군 치료 몫 · 격파 = 무너뜨린 적 · 생존 = 끝까지 살아남은 비율 · 잔존 = 남은 병력 / 최대
##   선열 = 선봉·전군에 선 비율. 병종 하나를 3장 넣은 덱의 승률(대 무작위)도 함께.

const FORMS := ["eorin", "hagik", "bongsi", "anwol", "bangwon", "anhaeng", "chuhaeng", "jangsa"]

func _ready() -> void:
	var args := {}
	for s in OS.get_cmdline_user_args():
		var kv := s.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	var games := int(args.get("games", "40"))
	var tiers: Array = Array(str(args.get("tiers", "4,5,6,7,8")).split(",")).map(func(x): return int(x))
	var tags: Array = DB.D.TAGORDER
	for t in tiers:
		var pool: Array = DB.by_tier(t).filter(func(k): return not DB.is_foe(k))
		var acc := {}
		for tg in tags:
			acc[tg] = {"n": 0, "dmg": 0.0, "mdmg": 0.0, "heal": 0.0, "kills": 0.0, "alive": 0.0, "left": 0.0, "front": 0.0, "w": 0.0, "wn": 0}
		var rng := RandomNumberGenerator.new()
		rng.seed = 1000 + t
		for g in games:
			var a := []
			var b := []
			for i in 9:
				a.append(pool[rng.randi() % pool.size()])
				b.append(pool[rng.randi() % pool.size()])
			var fa: String = FORMS[rng.randi() % FORMS.size()]
			var fb: String = FORMS[rng.randi() % FORMS.size()]
			var r := RtBattle.make(rng.randi()).run(DB.auto_place(a, fa), fa, 100, null, DB.auto_place(b, fb), fb, 100, null, "", "", [], {"A": "smart", "B": "smart"})
			for cp in ["A", "B"]:
				var mine: Array = r.roster.filter(func(x): return x.camp == cp)
				var avg := {"dmg": 0.0, "mdmg": 0.0, "heal": 0.0, "kills": 0.0}
				for x in mine:
					for key in avg: avg[key] += float(x[key]) / mine.size()
				for x in mine:
					var e: Dictionary = acc[x.tag]
					e.n += 1
					for key in avg:
						e[key] += float(x[key]) / maxf(0.001, avg[key]) if avg[key] > 0 else 1.0
					e.alive += 1.0 if x.alive else 0.0
					e.left += float(x.left) / maxf(1.0, float(x.max))
					e.front += 1.0 if x.line in ["선봉", "전군"] else 0.0
		# 병종 3장 + 무작위 6장 대 무작위 9장
		for tg in tags:
			var mine_pool: Array = pool.filter(func(k): return DB.C[k].tag == tg)
			if mine_pool.is_empty(): continue
			var rng2 := RandomNumberGenerator.new()
			rng2.seed = 77 + t
			for g in games:
				var a := []
				for i in 3: a.append(mine_pool[rng2.randi() % mine_pool.size()])
				var b := []
				for i in 6: a.append(pool[rng2.randi() % pool.size()])
				for i in 9: b.append(pool[rng2.randi() % pool.size()])
				var fa: String = FORMS[rng2.randi() % FORMS.size()]
				var fb: String = FORMS[rng2.randi() % FORMS.size()]
				var sd := rng2.randi()
				var r := RtBattle.make(sd).run(DB.auto_place(a, fa), fa, 100, null, DB.auto_place(b, fb), fb, 100, null, "", "", [], {"A": "smart", "B": "smart"})
				acc[tg].w += 1.0 if r.win else (0.5 if r.draw else 0.0)
				acc[tg].wn += 1
		print("== 등급 %d (%s) %d판 ==   피해  사기  치료  격파  생존  잔존  선열  3장승률" % [t, DB.TIER[t].n, games])
		for tg in tags:
			var e: Dictionary = acc[tg]
			if e.n == 0: continue
			print("%s  %5.2f %5.2f %5.2f %5.2f  %3d%%  %3d%%  %3d%%   %3d%%" % [tg, e.dmg / e.n, e.mdmg / e.n, e.heal / e.n, e.kills / e.n,
				roundi(100 * e.alive / e.n), roundi(100 * e.left / e.n), roundi(100 * e.front / e.n), roundi(100 * e.w / maxf(1, e.wn))])
	get_tree().quit()
