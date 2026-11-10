extends Node
## 새 기인 효과 점검 (11/10) —— 실행: godot --headless --path . res://tests/kiin_new.tscn [-- --games=4]
##  교변 장합(K05): 상성이 불리한 공격을 받으면 피해 −KIIN_MATCHUP_DR. 장합 덱 대 창병 덱을 효과 켬 / 끔으로 같은 시드에 돌려,
##    처음으로 갈라지는 사건이 'mu' 표시된 타격이고 피해가 정확히 (1 − DR) 배인지 본다.
##  단복 서서(K13): 받는 피해의 KIIN_SHARE 를 가까운 아군 KIIN_SHARE_N 부대가 나눠 받는다. 처음 갈라지는 사건이 'sh' 표시된 타격이고
##    맞은 부대 n + 분담 sh = 효과 끈 판의 같은 타격 피해(합계 보존) · 그 사건의 전 부대 병력 감소 합이 같은지 본다.
##  두 효과 모두 같은 시드 두 번의 사건 기록이 같은지 본다.
var fails := 0


func _ready() -> void:
	var args := {}
	for s in OS.get_cmdline_user_args():
		var kv := s.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	var games := int(args.get("games", "4"))
	var rng := RandomNumberGenerator.new()
	rng.seed = 5410
	var t5: Array = DB.by_tier(5).filter(func(k): return not DB.is_kiin(k))
	var horse: Array = t5.filter(func(k): return DB.C[k].tag == "기병")
	var spear: Array = t5.filter(func(k): return DB.C[k].tag == "창병")
	print("교변 장합 —— 기병 덱(+장합) 대 창병 덱, 창병이 기병을 이기는 상성 (감쇄 −%d%%)" % roundi(DB.KIIN_MATCHUP_DR * 100.0))
	for g in games:
		var a := ["K05"]
		for i in 8: a.append(horse[rng.randi() % horse.size()])
		var b := []
		for i in 9: b.append(spear[rng.randi() % spear.size()])
		_check_matchup(a, b, rng.randi() % 100000, g % 2 == 1)
	print("단복 서서 —— 무작위 5등급 덱(+서서) 대 무작위 5등급 덱 (분담 %d%% · %d부대)" % [roundi(DB.KIIN_SHARE * 100.0), DB.KIIN_SHARE_N])
	for g in games:
		var a := ["K13"]
		for i in 8: a.append(t5[rng.randi() % t5.size()])
		var b := []
		for i in 9: b.append(t5[rng.randi() % t5.size()])
		_check_share(a, b, rng.randi() % 100000, g % 2 == 1)
	Battle.kiin_matchup_share_enabled = true
	print("새 기인 점검 · 실패 %d" % fails)
	get_tree().quit()


func _run(a: Array, b: Array, seed: int, swap: bool, on: bool) -> Dictionary:
	Battle.kiin_matchup_share_enabled = on
	var f := "eorin"
	var x: Array = b if swap else a
	var y: Array = a if swap else b
	return RtBattle.make(seed).run(DB.auto_place(x, f), f, 100, null, DB.auto_place(y, f), f, 100, null, "", "", [], {"A": "smart", "B": "smart"})


## 처음으로 갈라지는 사건 번호 (없으면 -1)
func _first_diff(x: Array, y: Array) -> int:
	for i in mini(x.size(), y.size()):
		if x[i].t != y[i].t or str(x[i].s) != str(y[i].s):
			return i
	return -1


func _same_twice(a: Array, b: Array, seed: int, swap: bool, tag: String) -> void:
	var r1 := _run(a, b, seed, swap, true)
	var r2 := _run(a, b, seed, swap, true)
	if r1.ev.size() != r2.ev.size() or _first_diff(r1.ev, r2.ev) >= 0:
		fails += 1
		print("  실패(%s): 같은 시드 두 번의 사건 기록이 다르다" % tag)


func _check_matchup(a: Array, b: Array, seed: int, swap: bool) -> void:
	var on := _run(a, b, seed, swap, true)
	var off := _run(a, b, seed, swap, false)
	var mu_hits := 0
	for e in on.ev:
		if e.has("mu"): mu_hits += 1
	var i := _first_diff(on.ev, off.ev)
	var line := "  시드 %d%s 감쇄 타격 %d번 (효과 켠 판 %d사건)" % [seed, " (자리 바꿈)" if swap else "", mu_hits, on.ev.size()]
	if i < 0:
		fails += 1
		print(line + " —— 실패: 켠 판과 끈 판이 같다 (감쇄가 한 번도 안 일어남)")
		return
	var eo: Dictionary = on.ev[i]
	var ef: Dictionary = off.ev[i]
	if not eo.has("mu") or eo.get("a", "") != ef.get("a", "") or eo.get("f", "") != ef.get("f", ""):
		fails += 1
		print(line + " —— 실패: 갈라지는 사건 %d 이 감쇄 표시된 같은 타격이 아니다 (%s / %s)" % [i, eo.t, ef.t])
		return
	var want: float = float(ef.n) * (1.0 - DB.KIIN_MATCHUP_DR)
	var ok: bool = absf(float(eo.n) - want) <= 1.0
	if not ok:
		fails += 1
	print("%s —— 첫 감쇄 %d번 사건: 끈 판 %d → 켠 판 %d (기대 %.1f) %s" % [line, i, int(ef.n), int(eo.n), want, "ok" if ok else "실패"])
	_same_twice(a, b, seed, swap, "교변")


func _check_share(a: Array, b: Array, seed: int, swap: bool) -> void:
	var on := _run(a, b, seed, swap, true)
	var off := _run(a, b, seed, swap, false)
	var sh_hits := 0
	for e in on.ev:
		if e.has("sh"): sh_hits += 1
	var i := _first_diff(on.ev, off.ev)
	var line := "  시드 %d%s 분담 타격 %d번 (효과 켠 판 %d사건)" % [seed, " (자리 바꿈)" if swap else "", sh_hits, on.ev.size()]
	if i < 0:
		fails += 1
		print(line + " —— 실패: 켠 판과 끈 판이 같다 (분담이 한 번도 안 일어남)")
		return
	var eo: Dictionary = on.ev[i]
	var ef: Dictionary = off.ev[i]
	if not eo.has("sh") and eo.t == ef.t and str(eo.get("n", 0)) == str(ef.get("n", 0)):
		# 타격보다 먼저 지속 피해(화상 · 출혈) 분담이 일어난 판 —— 사건 스냅샷의 전 부대 병력 합이 같으면 합계 보존
		var tot_on := _total(eo)
		var tot_off := _total(ef)
		var ok_dot: bool = absi(tot_on - tot_off) <= eo.s.size()
		if not ok_dot:
			fails += 1
		print("%s —— 지속 피해 분담이 먼저 갈라짐(%d번 사건) · 전 부대 병력 합 켠 %d / 끈 %d %s" % [line, i, tot_on, tot_off, "ok" if ok_dot else "실패"])
		_same_twice(a, b, seed, swap, "서서")
		return
	if not eo.has("sh") or eo.get("a", "") != ef.get("a", "") or eo.get("f", "") != ef.get("f", ""):
		fails += 1
		print(line + " —— 실패: 갈라지는 사건 %d 이 분담 표시된 같은 타격이 아니다 (%s / %s)" % [i, eo.t, ef.t])
		return
	var drop_on := _drop(on.ev, i)
	var drop_off := _drop(off.ev, i)
	var sh_n: int = (eo.sh_to as Array).size()
	var camp_ok := true
	for k in eo.sh_to:
		if str(k)[0] != str(eo.f)[0] or k == eo.f:
			camp_ok = false
	# 사건 스냅샷은 병력을 반올림해 보여 주므로 분담 부대 수만큼의 오차는 허용
	var conserve: bool = absf(float(eo.n) + float(eo.sh) - float(ef.n)) <= 0.5 and absi(drop_on - drop_off) <= sh_n
	var ok: bool = conserve and camp_ok and sh_n >= 1 and sh_n <= DB.KIIN_SHARE_N
	if not ok:
		fails += 1
	print("%s —— 첫 분담 %d번 사건: 원래 피해 %d = 맞은 부대 %d + 분담 %d(%d부대 %s) · 병력 감소 합 켠 %d / 끈 %d %s" % [line, i, int(ef.n), int(eo.n), int(eo.sh), sh_n, ",".join(eo.sh_to), drop_on, drop_off, "ok" if ok else "실패"])
	_same_twice(a, b, seed, swap, "서서")


## 사건 i 직전 → 직후 전 부대 병력 감소 합 (스냅샷 s 의 첫 칸)
func _drop(ev: Array, i: int) -> int:
	var tot := 0
	for k in ev[i].s.size():
		tot += int(ev[i - 1].s[k][0]) - int(ev[i].s[k][0])
	return tot


## 사건 스냅샷의 전 부대 병력 합
func _total(e: Dictionary) -> int:
	var tot := 0
	for r in e.s:
		tot += int(r[0])
	return tot
