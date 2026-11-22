extends Node
## 11/22 전투 길이 · 우회 시간 측정 —— 사용자 "전투가 너무 빨리 끝난다" (목표: 불멸 · 신화 포함 판 30초 이상) · "우회하는 장수가 너무 오래 걸린다"
## 실행: godot --headless --path . res://tests/battle_len.tscn -- [--n=40] [--mix=7:9;8:9;8:3,7:6] [--seed=1]
##   양쪽 같은 구성(--mix, card_value 와 같은 표기)의 무작위 덱, 어린진 대 학익진. 판 길이 중앙값 · 하위 10% · 평균,
##   그리고 우회하는 부대(도적)의 첫 타격 시각 (개전 → 처음 친 때) 과 정면 근접 병종(창병 · 기병)의 첫 타격 시각.
##   --len=0 --flank=1.0 이면 11/22 전 값 (전/후 비교) · --dump 판마다
## 11/22 측정 (40판, 판 길이 중앙값 / 하위 10%, 전 → 후 = Battle.len_dmg {4: .75, 5: .5, 6: .55, 7: .4, 8: .45} · RtBattle.flank_spd 1.8):
##   고급 17.0/12.3 → 16.7/10.4 (표 밖) · 희귀 30.8/13.4 → 31.6/18.3 · 전설 30.5/19.2 → 42.9/29.3 · 초월 39.2/23.1 → 51.6/31.0
##   불멸 27.5/17.8 → 41.8/25.0 · 신화 30.3/21.2 → 44.7/32.4 · 신화3+불멸6 26.8/18.3 → 41.9/24.7 · 신화1+불멸2+전설6 23.5/14.2 → 32.4/19.2
##   도적 첫 타격 (불멸 / 신화) 10.5 → 7.6초 / 10.8 → 8.5초. 짧은 판(하위 10%)은 한쪽이 병력 75~90% 를 남기는 일방전 —— 총붕괴로 끝난다

func _ready() -> void:
	var args := {}
	for s in OS.get_cmdline_user_args():
		var kv := s.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	var n := int(args.get("n", "40"))
	var sd0 := int(args.get("seed", "1"))
	var mixes := str(args.get("mix", "3:9;4:9;5:9;6:9;7:9;8:9;8:3,7:6;k:3,5:6")).split(";", false)
	if args.has("len"):      # --len=6:1,7:0.7,8:0.7 → Battle.len_dmg 덮어쓰기 (전/후 비교) · --len=0 → 끈다
		var d := {}
		for p in str(args.len).split(",", false):
			var kv := p.split(":")
			if kv.size() == 2:
				d[int(kv[0])] = float(kv[1])
		Battle.len_dmg = d
	dump = args.has("dump")
	if args.has("flank"):    # --flank=1.6 → RtBattle.flank_spd
		RtBattle.flank_spd = float(args.flank)
	print("len_dmg %s · flank_spd %.2f" % [Battle.len_dmg, RtBattle.flank_spd])
	var t0 := Time.get_ticks_msec()
	print("구성 | 판 | 중앙값 | 하위10% | 평균 | 30초 미만 | 도적 첫타 | 기병 첫타 | 창병 첫타 | 우회 이동(부대합 초/판)")
	for m in mixes:
		_one(m, n, sd0)
	print("끝 (%.0f초)" % ((Time.get_ticks_msec() - t0) / 1000.0))
	get_tree().quit()


func _pool(g: String) -> Array:
	if g == "k":
		var ks: Array = DB.C.keys().filter(func(k): return DB.is_kiin(k) and not DB.is_foe(k))
		ks.sort()
		return ks
	var p: Array = DB.by_tier(int(g)).filter(func(k): return not DB.is_kiin(k) and not DB.is_foe(k))
	p.sort()
	return p


func _draw(rng: RandomNumberGenerator, mix: Array, pools: Dictionary) -> Array:
	var deck := []
	for g in mix:
		for i in int(g[1]):
			var src: Array = pools[g[0]].filter(func(k): return not deck.any(func(x): return DB.person(x) == DB.person(k)))
			if src.is_empty():
				src = pools[g[0]]
			deck.append(src[rng.randi() % src.size()])
	return deck


var dump := false
func _one(ms: String, n: int, sd0: int) -> void:
	var mix := []
	var pools := {}
	for p in ms.split(",", false):
		var kv := p.split(":")
		mix.append([kv[0], int(kv[1])])
		pools[kv[0]] = _pool(kv[0])
	var lens := []
	var frun := 0.0      # 우회 길목으로 돈 시간 (부대 합, 판당)
	var fell := 0
	var dps := 0.0
	var ultp := 0.0
	var dmgp := 0.0
	var routed := 0
	var rout_left := 0.0
	var lose_left := 0.0
	var fl := {"도적": [], "기병": [], "창병": []}
	for i in n:
		var rng := RandomNumberGenerator.new()
		rng.seed = sd0 * 100003 + i * 7919 + absi(ms.hash()) % 1000
		var a := _draw(rng, mix, pools)
		var b := _draw(rng, mix, pools)
		var r: Dictionary = RtBattle.make(sd0 * 1000 + i).run(DB.auto_place(a, "eorin"), "eorin", 100, null, DB.auto_place(b, "hagik"), "hagik", 100, null, "", "", [], {"A": "smart", "B": "smart"})
		lens.append(float(r.len))
		frun += float(r.stats.get("flank_run_t", 0.0))
		var tk := 0.0
		var mx := 0.0
		for u in r.roster:
			tk += float(u.taken)
			mx += float(u.max)
		dps += tk / mx / maxf(1.0, float(r.len)) * 100.0
		ultp += float(r.stats.get("ult_dmg", 0.0)) / maxf(1.0, tk)
		dmgp += float(r.stats.get("dmg", 0.0)) / maxf(1.0, tk)
		if dump:      # --dump → 판마다 길이 · 이긴 쪽 / 진 쪽 남은 병력 · 패주 수 · 첫 쓰러짐 시각
			var wl := [0.0, 0.0]
			var rn := 0
			for u in r.roster:
				wl[0 if str(u.camp) == ("A" if r.win else "B") else 1] += maxf(0.0, float(u.left)) / maxf(1.0, float(u.max)) / 9.0
				if not bool(u.alive) and float(u.left) > 0.0:
					rn += 1
			var ft := -1.0
			for e in r.ev:
				if e.get("fx") == "rout" or e.get("fx") == "fall":
					ft = float(e.get("tm", 0.0))
					break
			print("    판 %d  %.1f초  이긴 쪽 %d%% / 진 쪽 %d%%  패주 %d  첫 무너짐 %.1f초  붕괴 %s" % [i, float(r.len), roundi(wl[0] * 100), roundi(wl[1] * 100), rn, ft, str(r.stats.get("collapse_A", r.stats.get("collapse_B", "-")))])
		for u in r.roster:      # 끝날 때 쓰러진(alive false) 부대 —— 병력이 남은 채면 패주
			if not bool(u.alive):
				fell += 1
				if float(u.left) > 0.0:
					routed += 1
					rout_left += float(u.left) / maxf(1.0, float(u.max))
			if str(u.camp) == ("B" if r.win else "A"):
				lose_left += float(u.left) / maxf(1.0, float(u.max)) / 9.0
		var first := {}
		for e in r.ev:
			if e.get("fx") in ["phys", "int"] and e.has("a") and e.has("n") and not e.has("ult") and not first.has(str(e.a)):
				first[str(e.a)] = float(e.get("tm", 0.0))
		for u in r.roster:
			var k := str(u.key)
			if first.has(k) and fl.has(str(u.tag)):
				fl[str(u.tag)].append(first[k])
	lens.sort()
	var under := lens.filter(func(x): return x < 30.0).size()
	var avg := 0.0
	for x in lens:
		avg += x
	print("%s | %d | %.1f | %.1f | %.1f | %d%% | %s | %s | %s | %.1f" % [ms, n, _q(lens, 0.5), _q(lens, 0.1), avg / n, roundi(100.0 * under / n), _med(fl["도적"]), _med(fl["기병"]), _med(fl["창병"]), frun / n])
	print("    받은 피해 초당 총병력의 %.2f%% · 직접 피해(stats.dmg) 몫 %d%% · 고유기 몫 %d%%" % [dps / n, roundi(100.0 * dmgp / n), roundi(100.0 * ultp / n)])
	print("    쓰러진 부대 판당 %.1f · 그중 패주(병력 남김) %d%% · 패주 때 남은 병력 평균 %d%% · 진 쪽 남은 병력 %d%%" % [float(fell) / n, roundi(100.0 * routed / maxf(1, fell)), roundi(100.0 * rout_left / maxf(1, routed)), roundi(100.0 * lose_left / n)])


func _q(a: Array, q: float) -> float:
	if a.is_empty():
		return 0.0
	return float(a[clampi(int(floor(q * (a.size() - 1) + 0.5)), 0, a.size() - 1)])


func _med(a: Array) -> String:
	if a.is_empty():
		return "-"
	a.sort()
	return "%.1f초(%d)" % [_q(a, 0.5), a.size()]
