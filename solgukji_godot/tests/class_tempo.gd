extends Node
## 11/19 병종별 전투 속도감 —— 몰빵 덱(그 병종 6 + 무작위 3)으로 ① 같은 덱끼리(거울) ② 고루 덱 상대.
## 판 길이 · 첫 부대가 무너지는 시각 · 무너짐 간격 · 그 병종의 피해 몰림(공격자마다 가장 많이 때린 적 한 부대에 들어간 몫) · 그 병종의 격파 수
## 실행: godot --headless --path . res://tests/class_tempo.tscn [-- --n=10 --tier=7]

const TAGS := ["창병", "기병", "궁병", "도적", "책사", "술사", "모사", "유생"]
const MIX := ["창병", "창병", "기병", "궁병", "궁병", "도적", "책사", "유생", "모사"]

func _ready() -> void:
	var args := {}
	for arg in OS.get_cmdline_user_args():
		var kv := arg.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	var n := int(args.get("n", "10"))
	var tier := int(args.get("tier", "7"))
	var pool := DB.by_tier(tier).filter(func(k): return not DB.is_foe(k) and not DB.is_kiin(k))
	print("등급 %d · %d판씩 —— 판 길이 / 첫 타격 / 첫 무너짐 / 무너짐 간격 / 피해 몰림 / 이 병종 격파(판당)" % [tier, n])
	var vs := int(args.get("vs", "0"))      # --vs=4 → 그 등급 고루 덱 상대만 (높은 등급 몰빵 덱이 낮은 등급을 잡는 속도)
	var low_pool := DB.by_tier(vs).filter(func(k): return not DB.is_foe(k) and not DB.is_kiin(k)) if vs > 0 else []
	for mode in (["하위 상대"] if vs > 0 else ["거울", "고루 상대"]):
		print("[%s]" % mode)
		for tg in TAGS:
			var agg := {"len": 0.0, "first": 0.0, "first_n": 0, "gap": 0.0, "gap_n": 0, "focus": 0.0, "focus_n": 0, "kills": 0, "hit": 0.0}
			for i in n:
				var rng := RandomNumberGenerator.new()
				rng.seed = 88100 + i * 31 + TAGS.find(tg)
				var a := _mono(pool, tg, rng)
				if args.has("hi"):      # --hi=2 → 높은 등급 그 병종 N장 + 나머지는 낮은 등급 고루 (섞인 덱)
					var lo := _mix(low_pool, rng)
					a = []
					agg["hi_t"] = tier
					for q in int(args.hi):
						a.append(_by_tags(pool, [tg], rng)[0])
					for q in range(int(args.hi), 9):
						a.append(lo[q])
				var b := _mono(pool, tg, rng) if mode == "거울" else _mix(low_pool if vs > 0 else pool, rng)
				var r: Dictionary = RtBattle.new(88100 + i).run(DB.auto_place(a, "eorin"), "eorin", 100, null, DB.auto_place(b, "hagik"), "hagik", 100, null, "", "", [], {"A": "smart", "B": "smart"})
				_read(r, tg, agg, mode == "거울")
			print("  %-3s %5.1f초 / %4.1f초 / %5.1f초 / %4.1f초 / %3d%% / %.1f" % [tg, agg.len / n, agg.hit / n, agg.first / maxf(1, agg.first_n), agg.gap / maxf(1, agg.gap_n), int(100 * agg.focus / maxf(1, agg.focus_n)), float(agg.kills) / n], "  한 부대로 적 한 부대 깎는 데 %.0f초" % ((float(agg.get("foe_hp", 0.0)) / n) / maxf(1.0, float(agg.get("dps", 0.0)) / maxf(1, int(agg.get("dps_n", 0))))))
	get_tree().quit()


func _read(r: Dictionary, tg: String, agg: Dictionary, both: bool) -> void:
	agg.len += float(r.len)
	var tag_of := {}
	for u in r.roster:
		tag_of[str(u.key)] = str(u.tag)
	var foe_hp := 0.0
	var foe_n := 0
	for u in r.roster:
		if str(u.tag) == tg and (both or str(u.camp) == "A") and (not agg.has("hi_t") or int(u.tier) == int(agg.hi_t)):
			agg.kills += int(u.get("kills", 0))
			agg["dps"] = float(agg.get("dps", 0.0)) + (float(u.dmg) - float(u.get("over", 0.0))) / maxf(1.0, float(r.len))
			agg["dps_n"] = int(agg.get("dps_n", 0)) + 1
		if str(u.camp) == "B":
			foe_hp += float(u.max)
			foe_n += 1
	agg["foe_hp"] = float(agg.get("foe_hp", 0.0)) + foe_hp / maxf(1, foe_n)
	var hit_t := -1.0
	var prev: Array = r.ev[0].s
	var falls := []
	var to := {}      # 공격자 -> {대상: 피해}
	for e in r.ev:
		if e.get("fx") in ["phys", "int"] and e.has("a") and e.has("f") and e.has("n"):
			if hit_t < 0.0 and float(e.n) > 0.0 and not e.has("ult"):
				hit_t = float(e.get("tm", 0.0))
				agg.hit += hit_t
			var ak := str(e.a)
			if tag_of.get(ak, "") == tg and (both or ak[0] == "A"):
				var d: Dictionary = to.get(ak, {})
				d[str(e.f)] = float(d.get(str(e.f), 0.0)) + float(e.n)
				to[ak] = d
		for j in e.s.size():
			if int(prev[j][2]) == 1 and int(e.s[j][2]) != 1:
				if falls.is_empty():
					var ft: Dictionary = agg.get("ftag", {})
					var nm := "%s←%s" % [str(r.roster[j].tag), tag_of.get(str(r.roster[j].get("killer", "")), "?")]
					ft[str(r.roster[j].tag)] = int(ft.get(str(r.roster[j].tag), 0)) + 1
					agg["ftag"] = ft
					agg["charges"] = int(agg.get("charges", 0)) + int(r.stats.get("charges", 0))
				falls.append(float(e.get("tm", 0.0)))
		prev = e.s
	if not falls.is_empty():
		agg.first += falls[0]
		agg.first_n += 1
		for k in range(1, falls.size()):
			agg.gap += falls[k] - falls[k - 1]
			agg.gap_n += 1
	for ak in to:
		var tot := 0.0
		var top := 0.0
		for f in to[ak]:
			tot += to[ak][f]
			top = maxf(top, to[ak][f])
		if tot > 0.0:
			agg.focus += top / tot
			agg.focus_n += 1


func _mono(pool: Array, tg: String, rng: RandomNumberGenerator) -> Array:
	var tags := []
	for i in 6: tags.append(tg)
	for i in 3: tags.append(MIX[rng.randi_range(0, MIX.size() - 1)])
	return _by_tags(pool, tags, rng)


func _mix(pool: Array, rng: RandomNumberGenerator) -> Array:
	return _by_tags(pool, MIX, rng)


func _by_tags(pool: Array, tags: Array, rng: RandomNumberGenerator) -> Array:
	var out := []
	var people := []
	for tg in tags:
		var c := pool.filter(func(k): return DB.C[k].tag == tg and not people.has(DB.person(k)))
		if c.is_empty():
			c = pool.filter(func(k): return DB.C[k].tag == tg)
		if c.is_empty():
			c = pool
		var k: String = c[rng.randi_range(0, c.size() - 1)]
		out.append(k)
		people.append(DB.person(k))
	return out
