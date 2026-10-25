extends Node
## 조작 효과 점검 —— 실행: godot --headless --path . res://tests/control.tscn [-- --games=150]
## 같은 두 덱을 자리를 바꿔 두 번 붙여 덱·진영 차이를 지우고 정책 차이만 본다.
##   영리 vs 자동 : 잘 조작하는 사람 ≈ 영리한 AI. 목표는 +5~10%p
##   방치 vs 자동 : 아무것도 안 누르는 사람 (고유기·군령 없음)
## 덤으로 한 판에 고유기·군령이 몇 번 쓰였는지 센다.
## --tactics=1 : 덱 주인이 고르는 전술(tac:<고유기>:<군령>) 9가지를 섞인 덱에서 영리·자동 상대로 잰다.
## --mixed=1 : 같은 등급 덱 대신 등급이 섞인 덱(전설~신화, 같은 PV 예산)끼리 붙인다. 실제 후반 덱에 가깝다.

const FORMS := ["eorin", "hagik", "bongsi", "anwol", "bangwon", "anhaeng", "chuhaeng", "jangsa"]
const MIXED_PV := [700, 900, 1100, 1300]     # 전설 9장 ≈ 350 · 불멸 9장 ≈ 1090 · 신화 9장 ≈ 1430
var games := 150


func _ready() -> void:
	var args := {}
	for s in OS.get_cmdline_user_args():
		var kv := s.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	games = int(args.get("games", "150"))
	if args.has("breach"):
		Battle.breach = float(args.breach)
	if args.has("links"):
		Battle.cmd_links = args.links != "0"
	if args.has("amp"):
		Battle.crisis_amp = float(args.amp)
	if args.has("p1"):     # 두 정책을 직접 붙인다 (섞인 덱) —— 예: --p1=tac:즉시:공세 --p2=tac:즉시:수비
		var pv := int(args.get("pv", "1000"))
		var r := _duel(pv, args.p1, args.get("p2", "smart"), true)
		print("PV %d %s vs %s: %+.1f%%p" % [pv, args.p1, args.get("p2", "smart"), (r.w - 0.5) * 100])
		get_tree().quit()
		return
	if args.get("tactics", "0") != "0":
		var pv := int(args.get("pv", "1000"))
		for u in ["즉시", "영리", "위기"]:
			for c in ["공세", "영리", "수비"]:
				var p := "tac:%s:%s" % [u, c]
				var vs := _duel(pv, p, "smart", true)
				var va := _duel(pv, p, "auto", true)
				print("PV %d %s: vs 영리 %+.1f%%p · vs 자동 %+.1f%%p (고유기 %.1f · 군령 %.1f /판)" % [
					pv, p, (vs.w - 0.5) * 100, (va.w - 0.5) * 100, vs.ult, vs.cmd])
		get_tree().quit()
		return
	if args.get("mixed", "0") != "0":
		for pv in MIXED_PV:
			var smart := _duel(pv, "smart", "auto", true)
			var idle := _duel(pv, "manual", "auto", true)
			print("PV %d (%s): 영리 vs 자동 %+.1f%%p (고유기 %.1f · 군령 %.1f /판) · 방치 vs 자동 %+.1f%%p" % [
				pv, smart.mix, (smart.w - 0.5) * 100, smart.ult, smart.cmd, (idle.w - 0.5) * 100])
		get_tree().quit()
		return
	for t in [5, 6, 7, 8]:
		var smart := _duel(t, "smart", "auto")
		var idle := _duel(t, "manual", "auto")
		print("%s: 영리 vs 자동 %+.1f%%p (고유기 %.1f · 군령 %.1f /판) · 방치 vs 자동 %+.1f%%p" % [
			DB.TIER[t].n, (smart.w - 0.5) * 100, smart.ult, smart.cmd, (idle.w - 0.5) * 100])
	get_tree().quit()


func _duel(t: int, p1: String, p2: String, mixed := false) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7000 + t
	var pool: Array = [] if mixed else DB.by_tier(t)
	var tc := {}
	var w := 0.0
	var ult := 0
	var cmd := 0
	var share := 0.0
	var blk := 0
	var uh := 0
	for g in games:
		var x := []
		var y := []
		if mixed:
			x = _mixed_deck(t, rng)
			y = _mixed_deck(t * rng.randf_range(0.95, 1.05), rng)
			for k in x + y:
				tc[DB.C[k].tier] = tc.get(DB.C[k].tier, 0) + 1
		else:
			for i in 9:
				x.append(pool[rng.randi() % pool.size()])
				y.append(pool[rng.randi() % pool.size()])
		var fx: String = FORMS[rng.randi() % FORMS.size()]
		var fy: String = FORMS[rng.randi() % FORMS.size()]
		var seed := rng.randi() % 1000000
		# 1판: x 가 p1(A) · 2판: x 가 p1(B)
		var r1 := Battle.new(seed).run(DB.auto_place(x, fx), fx, 100, null, DB.auto_place(y, fy), fy, 100, null, "", "", [], {"A": p1, "B": p2})
		var r2 := Battle.new(seed).run(DB.auto_place(y, fy), fy, 100, null, DB.auto_place(x, fx), fx, 100, null, "", "", [], {"A": p2, "B": p1})
		w += (1.0 if r1.win else (0.5 if r1.draw else 0.0))
		w += (1.0 if (not r2.win and not r2.draw) else (0.5 if r2.draw else 0.0))
		share += (r1.stats.ult_dmg / maxf(1, r1.stats.dmg) + r2.stats.ult_dmg / maxf(1, r2.stats.dmg)) / 2
		blk += r1.stats.blocked + r2.stats.blocked
		uh += r1.stats.ult_hits + r2.stats.ult_hits
		for r in [r1, r2]:
			for e in r.ev:
				if e.get("fx") == "ult" and _camp_of(r, e.a) == ("A" if r == r1 else "B"):
					ult += 1
				if e.get("fx") == "cmd" and e.camp == ("A" if r == r1 else "B"):
					cmd += 1
	print("    [%s vs %s] 고유기 피해 비중 %.0f%% · 고유기 타격 중 방진에 막힌 비율 %.0f%%" % [p1, p2, share / games * 100, 100.0 * blk / maxi(1, uh)])
	var mix := []
	for k in [5, 6, 7, 8]:
		mix.append("%s %.1f" % [DB.TIER[k].n, tc.get(k, 0) / (games * 2.0)])
	return {"w": w / (games * 2), "ult": float(ult) / (games * 2), "cmd": float(cmd) / (games * 2), "mix": " · ".join(mix)}


## 전설 9장에서 시작해, 무작위 자리를 한 등급씩 올리며 PV 예산을 쓴다 → 등급이 고르게 섞인다.
func _mixed_deck(pv: float, rng: RandomNumberGenerator) -> Array:
	var mid := func(t): return (DB.TIER[t].lo + DB.TIER[t].hi) / 2.0
	var tiers := []
	tiers.resize(9)
	tiers.fill(5)
	var spent: float = mid.call(5) * 9
	while true:
		var ok := []
		for i in 9:
			if tiers[i] < 8 and spent + mid.call(tiers[i] + 1) - mid.call(tiers[i]) <= pv:
				ok.append(i)
		if ok.is_empty():
			break
		var i: int = ok[rng.randi() % ok.size()]
		spent += mid.call(tiers[i] + 1) - mid.call(tiers[i])
		tiers[i] += 1
	var out := []
	for t in tiers:
		var src: Array = DB.by_tier(t)
		out.append(src[rng.randi() % src.size()])
	return out


func _camp_of(r: Dictionary, key: String) -> String:
	return key.substr(0, 1)
