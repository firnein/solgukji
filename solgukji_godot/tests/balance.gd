extends Node
## 장수 밸런스 점검 —— 실행: godot --headless --path . res://tests/balance.tscn  [-- --trials=40 --ult=0]
##
## 1) 능력치 총합: 같은 등급 안에서 공+방+책+책방+속도 합이 튀는 카드
## 2) 한 칸 기여도: 같은 등급 무작위 8장 + 평가 대상 1장 vs 같은 등급 무작위 9장.
##    모든 카드가 같은 시드의 같은 상황(trials 개)에서 싸우므로 카드끼리 짝지어 비교된다.
## 3) 병종·세력 평균, 4) 등급 사이 격차 (위 등급 9장 vs 아래 등급 9장)

const FORMS := ["eorin", "hagik", "bongsi", "anwol", "bangwon", "anhaeng", "chuhaeng", "jangsa"]
var trials := 40


func _ready() -> void:
	var args := {}
	for s in OS.get_cmdline_user_args():
		var kv := s.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	trials = int(args.get("trials", "40"))
	if args.get("ult", "1") == "0":
		Battle.ults_enabled = false
	for o in str(args.get("off", "")).split(",", false):     # 비교용: --off=passives,counter,fire,water,temper,aura,cut,guard,scheme,virtue
		match o:     # static var 는 문자열 이름(set)으로 못 세우므로 이름별 직접 대입
			"passives": Battle.passives_enabled = false
			"counter": Battle.counter_enabled = false
			"fire": Battle.fire_enabled = false
			"water": Battle.water_enabled = false
			"temper": Battle.temper_enabled = false
			"aura": Battle.aura_enabled = false
			"cut": Battle.cut_enabled = false
			"guard": Battle.guard_enabled = false
			"scheme": Battle.scheme_enabled = false
			"virtue": Battle.virtue_enabled = false
			"minor": Battle.minor_enabled = false
			_: push_warning("--off 에 모르는 이름: " + o)
	var t0 := Time.get_ticks_msec()
	var out := FileAccess.open("res://tests/out_balance.csv", FileAccess.WRITE)
	out.store_line("tier,id,name,tag,fac,stat_sum,stat_z,win_rate")
	var tiers := Array(args.get("tiers", "4,5,6,7,8").split(",")).map(func(x): return int(x))
	for tier in tiers:
		_tier(tier, out)
	if not args.has("nogap"):
		_gaps()
	print("소요 %.1f초" % ((Time.get_ticks_msec() - t0) / 1000.0))
	get_tree().quit()


func _stat_sum(c: Dictionary) -> float:
	return c.atk + c["def"] + c["int"] + c.res + c.spd


func _tier(tier: int, out: FileAccess) -> void:
	var ids: Array = DB.by_tier(tier)
	# 1) 능력치 총합
	var sums := ids.map(func(k): return _stat_sum(DB.C[k]))
	var mean: float = sums.reduce(func(a, b): return a + b) / sums.size()
	var var_ := 0.0
	for s in sums:
		var_ += (s - mean) * (s - mean)
	var sd := sqrt(var_ / sums.size())
	# 2) 한 칸 기여도 —— 상황을 미리 만들어 두고 모든 카드에 똑같이 쓴다
	var rng := RandomNumberGenerator.new()
	rng.seed = 1000 + tier
	var ctx := []
	for t in trials:
		var filler := []
		for i in 8:
			filler.append(ids[rng.randi() % ids.size()])
		var foe := []
		for i in 9:
			foe.append(ids[rng.randi() % ids.size()])
		ctx.append({"filler": filler, "foe": foe, "fa": FORMS[rng.randi() % FORMS.size()],
			"fb": FORMS[rng.randi() % FORMS.size()], "seed": rng.randi() % 100000})
	var rows := []
	for i in ids.size():
		var k: String = ids[i]
		var w := 0.0
		for c in ctx:
			var mine: Array = c.filler + [k]
			var r := Battle.new(c.seed).run(DB.auto_place(mine, c.fa), c.fa, 100, null,
				DB.auto_place(c.foe, c.fb), c.fb, 100, null)
			w += 1.0 if r.win else (0.5 if r.draw else 0.0)
		var wr := w / trials
		var z: float = (sums[i] - mean) / maxf(sd, 0.001)
		rows.append({"k": k, "wr": wr, "z": z, "sum": sums[i]})
		out.store_line("%d,%s,%s,%s,%s,%.0f,%.2f,%.3f" % [tier, k, DB.C[k].name, DB.C[k].tag, DB.C[k].fac, sums[i], z, wr])
	rows.sort_custom(func(a, b): return a.wr > b.wr)
	var wrs := rows.map(func(r): return r.wr)
	var wmean: float = wrs.reduce(func(a, b): return a + b) / wrs.size()
	print("\n━━ %s (%d장) · 능력치 합 평균 %.0f ±%.0f · 기여 승률 평균 %.0f%% (최고 %.0f%% / 최저 %.0f%%)" % [
		DB.TIER[tier].n, ids.size(), mean, sd, wmean * 100, wrs.max() * 100, wrs.min() * 100])
	var line := func(r): return "%s(%s) %.0f%% 능력치z %+.1f" % [DB.C[r.k].name, DB.C[r.k].tag, r.wr * 100, r.z]
	print("  상위: ", ", ".join(rows.slice(0, 4).map(line)))
	print("  하위: ", ", ".join(rows.slice(rows.size() - 4).map(line)))
	var odd := rows.filter(func(r): return absf(r.z) >= 1.8)
	if not odd.is_empty():
		print("  능력치 튐: ", ", ".join(odd.map(func(r): return "%s %+.1fσ" % [DB.C[r.k].name, r.z])))
	for key in ["tag", "fac"]:
		var g := {}
		for r in rows:
			var v: String = DB.C[r.k][key]
			if not g.has(v):
				g[v] = []
			g[v].append(r.wr)
		var parts := []
		for v in g:
			parts.append([v, g[v].reduce(func(a, b): return a + b) / g[v].size(), g[v].size()])
		parts.sort_custom(func(a, b): return a[1] > b[1])
		print("  %s별: " % ("병종" if key == "tag" else "세력"), "  ".join(parts.map(func(p): return "%s %.0f%%(%d)" % [p[0], p[1] * 100, p[2]])))


func _gaps() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	print("\n━━ 등급 격차 (위 등급 9장 vs 아래 등급 9장, %d판)" % trials)
	for t in [5, 6, 7, 8]:
		var hi: Array = DB.by_tier(t)
		var lo: Array = DB.by_tier(t - 1)
		var w := 0.0
		var turns := 0
		for i in trials:
			var a := []
			var b := []
			for j in 9:
				a.append(hi[rng.randi() % hi.size()])
				b.append(lo[rng.randi() % lo.size()])
			var fa: String = FORMS[rng.randi() % FORMS.size()]
			var fb: String = FORMS[rng.randi() % FORMS.size()]
			var r := Battle.new(rng.randi() % 100000).run(DB.auto_place(a, fa), fa, 100, null, DB.auto_place(b, fb), fb, 100, null)
			w += 1.0 if r.win else (0.5 if r.draw else 0.0)
			turns += r.turns
		print("  %s vs %s: 위 등급 승률 %.0f%% · 평균 %.1f턴" % [DB.TIER[t].n, DB.TIER[t - 1].n, w / trials * 100, float(turns) / trials])
