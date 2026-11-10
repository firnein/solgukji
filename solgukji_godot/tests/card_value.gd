extends Node
## 11/10 전투 밸런스 —— 카드 한 칸의 승률 기여 (docs/밸런스_1110.md). 실행(모두 --headless):
##   godot --path . res://tests/card_value.tscn -- --mode=scan --mix=5:9 --target=5 --n=400 --seed=1 [--out=파일.tsv]
##
## mode=scan  : 양쪽이 같은 구성(--mix)의 무작위 덱 —— 판마다 새 덱 · 카드마다 '나온 판 승률(raw)'과, 덱 구성 효과를 걷어 낸
##              선형 승률 모형(ridge)의 β = '이 카드가 한 칸에 들어갔을 때 승률 +%p (등급 평균 0 기준)'를 낸다.
##              --mix=등급:장수,… (등급 숫자 · k = 기인). 예: 5:9 · 7:9 · 8:3,7:6 (신화 3 + 불멸 6) · k:3,5:6 (기인 3 + 전설 6)
##              --target=등급 또는 k : 그 그룹의 카드만 표에 낸다 (생략하면 --mix 의 첫 그룹)
##   같은 --seed · 같은 --n 이면 덱 · 전투 시드가 같다 → 데이터를 바꾼 뒤 같은 인자로 다시 돌리면 전 · 후 짝비교 (카드 수가 같을 때).
## mode=duel  : --a=7:9 --b=6:9 → A 덱(무작위) 대 B 덱의 승률 (등급 격차 · 기인 한 칸 등). 판마다 자리를 번갈아 둔다.
## mode=slot  : --cards=c101,c102 --base=5 --n=24 → 그 카드 하나 + 기준 등급 무작위 8장 대 기준 등급 무작위 9장, 카드끼리 같은 덱 · 시드(짝비교).
## 공통: --form=eorin (기본 어린진, random 이면 무작위 진형) · --off=위세,깎기,… (mono_league 와 같은 이름 일부)

const FORMS := ["eorin", "hagik", "bongsi", "anwol", "bangwon", "anhaeng", "chuhaeng", "jangsa"]
var form_mode := "eorin"
var aura_side := ""      # --auraside=mine → 위세 · 패업을 내 덱(duel 의 a, slot 의 카드 쪽)만 켠다 (효과 크기 = 승률 − 50%)


func _ready() -> void:
	var args := {}
	for s in OS.get_cmdline_user_args():
		var kv := s.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	form_mode = str(args.get("form", "eorin"))
	aura_side = str(args.get("auraside", ""))
	for o in str(args.get("off", "")).split(",", false):
		match o:
			"위세": Battle.aura_enabled = false
			"깎기": Battle.cut_enabled = false
			"철벽": Battle.guard_enabled = false
			"패업": Battle.paeup_enabled = false
			"고유기": Battle.ults_enabled = false
			"특기": Battle.passives_enabled = false
			"상성": Battle.counter_enabled = false
			"막": Battle.shield_enabled = false
			"기인효과": Battle.kiin_matchup_share_enabled = false      # 장합 · 서서 새 효과만
			"잔기술": Battle.minor_enabled = false
			"인덕": Battle.virtue_enabled = false
			_: push_error("모르는 --off: " + o)
	if args.has("myth"):      # --myth=능력치:병력:특기 → 신화 몸값 배율 (mono_league 와 같다)
		var mp := str(args.myth).split(":")
		Battle.myth_power = float(mp[0])
		if mp.size() > 1: Battle.myth_troop = float(mp[1])
		if mp.size() > 2: DB.set_myth_trait(float(mp[2]))
	var t0 := Time.get_ticks_msec()
	match str(args.get("mode", "scan")):
		"scan": _scan(args)
		"duel": _duel(args)
		"slot": _slot(args)
		"mirror": _mirror(args)
	print("끝 (%.0f초)" % ((Time.get_ticks_msec() - t0) / 1000.0))
	get_tree().quit()


func _pool(g: String) -> Array:
	if g == "k":
		var ks: Array = DB.C.keys().filter(func(k): return DB.is_kiin(k) and not DB.is_foe(k))
		ks.sort()
		return ks
	return DB.by_tier(int(g)).filter(func(k): return not DB.is_kiin(k))


func _parse_mix(s: String) -> Array:
	var out := []
	for p in s.split(",", false):
		var kv := p.split(":")
		out.append([kv[0], int(kv[1])])
	return out


## 인물이 겹치지 않게 무작위 덱 (그룹 차례대로)
func _draw(rng: RandomNumberGenerator, mix: Array, pools: Dictionary, exclude := []) -> Array:
	var deck := []
	for g in mix:
		for i in int(g[1]):
			var src: Array = pools[g[0]].filter(func(k): return not deck.any(func(x): return DB.person(x) == DB.person(k)) and not exclude.has(k))
			if src.is_empty():
				src = pools[g[0]]
			deck.append(src[rng.randi() % src.size()])
	return deck


func _form(rng: RandomNumberGenerator) -> String:
	if form_mode == "random":
		return FORMS[rng.randi() % FORMS.size()]
	return form_mode


var paeup_side := ""      # mirror 에서만: 패업을 내 쪽만 켠다
func _fight(da: Array, fa: String, db: Array, fb: String, sd: int, mine := "A") -> float:
	Battle.aura_camp = mine if aura_side == "mine" else ""
	Battle.paeup_camp = mine if paeup_side == "mine" else ""
	var r := RtBattle.make(sd).run(DB.auto_place(da, fa), fa, 100, null, DB.auto_place(db, fb), fb, 100, null, "", "", [], {"A": "smart", "B": "smart"})
	return 1.0 if r.win else (0.5 if r.draw else 0.0)


func _scan(args: Dictionary) -> void:
	var n := int(args.get("n", "400"))
	var seed0 := int(args.get("seed", "1"))
	var mix := _parse_mix(str(args.get("mix", "5:9")))
	var target := str(args.get("target", mix[0][0]))
	var pools := {}
	for g in mix:
		pools[g[0]] = _pool(g[0])
	var tp: Array = _pool(target) if target != "all" else []      # all = 구성의 모든 그룹을 한 모형에 (그룹 평균 차이도 낸다)
	if target == "all":
		for g in mix:
			for k in pools[g[0]]:
				if not tp.has(k):
					tp.append(k)
	var idx := {}
	for i in tp.size():
		idx[tp[i]] = i
	var m := tp.size()
	var cnt := PackedFloat64Array()
	cnt.resize(m)
	var win := PackedFloat64Array()
	win.resize(m)
	var rows := []      # 회귀용 [사전 x(+1 A · −1 B), y]
	var tot := 0.0
	for g in n:
		var rng := RandomNumberGenerator.new()
		rng.seed = seed0 * 1000003 + g
		var da := _draw(rng, mix, pools)
		var db := _draw(rng, mix, pools)
		var fa := _form(rng)
		var fb := _form(rng)
		var sd := rng.randi() % 1000000
		var y := _fight(da, fa, db, fb, sd)      # A 쪽이 이긴 정도
		tot += y
		var x := {}
		for k in da:
			if idx.has(k):
				cnt[idx[k]] += 1
				win[idx[k]] += y
				x[idx[k]] = x.get(idx[k], 0.0) + 1.0
		for k in db:
			if idx.has(k):
				cnt[idx[k]] += 1
				win[idx[k]] += 1.0 - y
				x[idx[k]] = x.get(idx[k], 0.0) - 1.0
		rows.append([x, y])
	# ridge 선형 모형: y − 0.5 = Σ β_j x_j (좌표 하강)
	var beta := PackedFloat64Array()
	beta.resize(m)
	var lam := 2.0
	var resid := PackedFloat64Array()
	for r in rows:
		resid.append(float(r[1]) - 0.5)
	var xsq := PackedFloat64Array()
	xsq.resize(m)
	for r in rows:
		for j in r[0]:
			xsq[j] += float(r[0][j]) * float(r[0][j])
	for it in 60:
		for j in m:
			var num := 0.0
			for i in rows.size():
				var xj = rows[i][0].get(j, 0.0)
				if xj != 0.0:
					num += float(xj) * (resid[i] + float(xj) * beta[j])
			var nb := num / (xsq[j] + lam)
			var d := nb - beta[j]
			if d != 0.0:
				for i in rows.size():
					var xj = rows[i][0].get(j, 0.0)
					if xj != 0.0:
						resid[i] -= float(xj) * d
			beta[j] = nb
	var mean_b := 0.0
	var mean_n := 0.0
	for j in m:
		mean_b += beta[j] * cnt[j]
		mean_n += cnt[j]
	mean_b /= maxf(1.0, mean_n)
	var ss := 0.0
	for i in rows.size():
		ss += resid[i] * resid[i]
	var sigma := sqrt(ss / float(rows.size() - m)) if rows.size() > m * 3 else 0.42      # 표본이 모자라면 한 판 결과의 퍼짐(≈0.42)으로
	var lines := []
	for j in m:
		var k: String = tp[j]
		var raw: float = win[j] / maxf(1.0, cnt[j])
		var se := sigma / sqrt(maxf(1.0, xsq[j] + lam))
		lines.append({"k": k, "n": int(cnt[j]), "raw": raw, "b": (beta[j] - mean_b) * 100.0, "se": se * 100.0})
	lines.sort_custom(func(a, b): return a.b > b.b)
	print("── scan 구성 %s · 표 %s · %d판 · 시드 %d · 모형 잔차 σ %.2f · A 승률 %.1f%%" % [str(args.get("mix", "5:9")), target, n, seed0, sigma, tot / n * 100.0])
	print("id\t이름\t병종\t나옴\t판승률\tβ(%p)\t±se")
	var f: FileAccess = null
	if args.has("out"):
		f = FileAccess.open(str(args.out), FileAccess.WRITE)
		f.store_line("id\tname\ttag\tn\traw\tbeta\tse")
	for l in lines:
		var c: Dictionary = DB.C[l.k]
		print("%s\t%s\t%s\t%d\t%.0f%%\t%+.1f\t%.1f" % [l.k, c.name, c.tag, l.n, l.raw * 100.0, l.b, l.se])
		if f:
			f.store_line("%s\t%s\t%s\t%d\t%.4f\t%.2f\t%.2f" % [l.k, c.name, c.tag, l.n, l.raw, l.b, l.se])
	# 요약: β 의 표준편차(카드 사이 퍼짐) · 병종별 평균
	var sd2 := 0.0
	for l in lines:
		sd2 += l.b * l.b
	var by_tag := {}
	for l in lines:
		var tg: String = DB.C[l.k].tag
		if not by_tag.has(tg):
			by_tag[tg] = []
		by_tag[tg].append(l.b)
	var parts := []
	for tg in by_tag:
		var a: Array = by_tag[tg]
		var s := 0.0
		for v in a:
			s += v
		parts.append("%s %+.1f(%d)" % [tg, s / a.size(), a.size()])
	if target == "all":
		var gm := []
		for g in mix:
			var sg := 0.0
			var ng := 0
			for l in lines:
				if pools[g[0]].has(l.k):
					sg += l.b
					ng += 1
			gm.append("%s그룹 %+.1f(%d장)" % [g[0], sg / maxf(1, ng), ng])
		print("그룹 평균 β: " + "  ".join(gm))
	print("요약: β 표준편차 %.1f%%p · 평균 se %.1f%%p · 병종별 %s" % [sqrt(sd2 / maxf(1, lines.size())), lines.reduce(func(s, l): return s + l.se, 0.0) / maxf(1, lines.size()), "  ".join(parts)])


func _duel(args: Dictionary) -> void:
	var n := int(args.get("n", "40"))
	var seed0 := int(args.get("seed", "1"))
	var ma := _parse_mix(str(args.get("a", "7:9")))
	var mb := _parse_mix(str(args.get("b", "6:9")))
	var pools := {}
	for g in ma + mb:
		pools[g[0]] = _pool(g[0])
	var w := 0.0
	for g in n:
		var rng := RandomNumberGenerator.new()
		rng.seed = seed0 * 1000003 + g
		var da := _draw(rng, ma, pools)
		var db := _draw(rng, mb, pools)
		var fa := _form(rng)
		var fb := _form(rng)
		var sd := rng.randi() % 1000000
		if g % 2 == 0:
			w += _fight(da, fa, db, fb, sd, "A")
		else:
			w += 1.0 - _fight(db, fb, da, fa, sd, "B")
	var se := sqrt(w / n * (1.0 - w / n) / n) * 100.0
	print("duel %s 대 %s : %.1f%% (±%.1f · %d판 · 시드 %d)" % [str(args.get("a", "7:9")), str(args.get("b", "6:9")), w / n * 100.0, se, n, seed0])


func _slot(args: Dictionary) -> void:
	var n := int(args.get("n", "24"))
	var ks: Array = str(args.get("cards", "")).split(",", false)
	var base := str(args.get("base", "5"))
	var pools := {base: _pool(base)}
	var out := []
	for k in ks:
		var w := 0.0
		for g in n:
			var rng := RandomNumberGenerator.new()
			rng.seed = int(args.get("seed", "1")) * 1000003 + g
			var da := _draw(rng, [[base, 8]], pools, [k])
			var db := _draw(rng, [[base, 9]], pools)
			var fa := _form(rng)
			var fb := _form(rng)
			var sd := rng.randi() % 1000000
			da.append(k)
			if g % 2 == 0:
				w += _fight(da, fa, db, fb, sd, "A")
			else:
				w += 1.0 - _fight(db, fb, da, fa, sd, "B")
		out.append([k, w / n])
		print("slot %s %s(%s) : %.0f%% (%d판)" % [k, DB.C[k].name, DB.C[k].tag, w / n * 100.0, n])


## mode=mirror: 카드 하나 + 기준 등급 8장(판마다 무작위) 덱을 양쪽에 똑같이 놓고, 패업만 내 쪽에 켠다 → 승률 − 50% = 그 카드 패업의 효과 크기.
## --cards=c177,c181 --base=7 --n=120 (판마다 자리를 번갈아 두어 자리 유불리를 지운다)
func _mirror(args: Dictionary) -> void:
	paeup_side = "mine"
	var n := int(args.get("n", "120"))
	var ks: Array = str(args.get("cards", "")).split(",", false)
	var base := str(args.get("base", "7"))
	var pools := {base: _pool(base)}
	for k in ks:
		var w := 0.0
		for g in n:
			var rng := RandomNumberGenerator.new()
			rng.seed = int(args.get("seed", "1")) * 1000003 + g
			var da := _draw(rng, [[base, 8]], pools, [k])
			da.append(k)
			var f := _form(rng)
			var sd := rng.randi() % 1000000
			if g % 2 == 0:
				w += _fight(da, f, da.duplicate(), f, sd, "A")
			else:
				w += 1.0 - _fight(da.duplicate(), f, da, f, sd, "B")
		var se := sqrt(0.25 / n) * 100.0
		print("mirror %s %s(%s) 패업 효과 %+.1f%%p (±%.1f · %d판)" % [k, DB.C[k].name, DB.C[k].tag, (w / n - 0.5) * 100.0, se, n])
