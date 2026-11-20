extends Node
## 11/20 병종 밸런스 기준선 (대전만) —— 판마다 한 줄씩 파일로 남기고 집계는 밖에서 (tools 쪽 파이썬, 보고서 참고). 엔진 · 데이터는 건드리지 않는다.
## 실행: godot --headless --path . res://tests/class_base.tscn -- --mode=value --tiers=3,4,5,6,7,8 --n=20 --seed=1120 --shard=0 --nshard=5 --out=C:/.../value_0.csv
##   mode=value : <병종>6(그 병종 6 + 같은 등급 무작위 3) 대 같은 등급 무작위 9 —— 병종 하나의 가치
##   mode=pair  : <병종>6 대 <병종>6 (병종 28쌍) —— 상성
##   mode=mix   : 같은 등급 무작위 9 대 무작위 9 —— 병종 수에 대한 승률 회귀용
##   mode=info  : 등급마다 병종별 인물 수만 찍는다
##   n = (등급 · 병종 또는 쌍)마다 덱 뽑기 수 —— 덱 하나를 같은 시드로 자리를 바꿔 두 판 (mix 는 등급마다 덱 쌍 수)
##   덱 · 전투 시드는 일(job)마다 seed · 모드 · 등급 · 병종 · 순번으로 정해져 shard 나누기와 상관없이 같다 (조정 뒤 같은 인자로 짝비교)
##   진형은 양쪽 어린진(eorin), 양쪽 smart AI. 같은 인물은 한 덱에 한 장만, 기인 제외.
## 줄: G,모드,등급,덱A,덱B,순번,자리(0/1),전투시드,A점수(1/0.5/0),길이초,A병종수(TAGORDER 순 8개 ;),B병종수

const TAGS := ["창병", "기병", "궁병", "도적", "책사", "술사", "유생", "모사"]
var pools := {}      # 등급 → [pool, by_tag]


func _ready() -> void:
	var args := {}
	for s in OS.get_cmdline_user_args():
		var kv := s.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	var mode := str(args.get("mode", "value"))
	var n := int(args.get("n", "10"))
	var seed0 := int(args.get("seed", "1120"))
	var shard := int(args.get("shard", "0"))
	var nshard := int(args.get("nshard", "1"))
	var tiers: Array = Array(str(args.get("tiers", "3,4,5,6,7,8")).split(",")).map(func(x): return int(x))
	if mode == "info":
		for t in tiers:
			_use(t)
			var line := "등급 %d %s 카드 %d :" % [t, DB.TIER[t].n, pools[t][0].size()]
			for tg in TAGS:
				var persons := {}
				for k in pools[t][1].get(tg, []):
					persons[DB.person(k)] = true
				line += " %s %d" % [tg, persons.size()]
			print(line)
			var sp := "   평균 spd:"
			for tg in TAGS:
				var ks: Array = pools[t][1].get(tg, [])
				var s := 0.0
				for k in ks:
					s += float(DB.C[k].spd)
				sp += " %s %.0f" % [tg, s / maxf(1, ks.size())]
			print(sp)
			for st in ["tr", "atk", "def", "int", "res"]:
				var sl := "   평균 %s:" % st
				for tg in TAGS:
					var ks2: Array = pools[t][1].get(tg, [])
					var s2 := 0.0
					for k in ks2:
						s2 += float(DB.C[k].get(st, 0))
					sl += " %s %.0f" % [tg, s2 / maxf(1, ks2.size())]
				print(sl)
			if pools[t][0].size() <= 20:      # 작은 등급은 카드 이름까지
				print("   " + " · ".join(pools[t][0].map(func(k): return "%s %s" % [DB.C[k].tag, DB.C[k].name])))
		get_tree().quit()
		return
	var out_path := str(args.get("out", "user://class_base_%s_%d.csv" % [mode, shard]))
	var f := FileAccess.open(out_path, FileAccess.WRITE)
	if f == null:
		push_error("파일을 못 연다: " + out_path)
		get_tree().quit(1)
		return
	# 일 목록 —— [등급, 덱A 이름, 덱B 이름, 순번, 고유 번호]
	var jobs := []
	for t in tiers:
		if mode == "value":
			for ti in TAGS.size():
				for i in n:
					jobs.append([t, TAGS[ti] + "6", "무작위", i, t * 1000000 + 1 * 100000 + ti * 1000 + i])
		elif mode == "pair":
			for a in TAGS.size():
				for b in range(a + 1, TAGS.size()):
					for i in n:
						jobs.append([t, TAGS[a] + "6", TAGS[b] + "6", i, t * 1000000 + 2 * 100000 + (a * 8 + b) * 1000 + i])
		else:
			for i in n:
				jobs.append([t, "무작위", "무작위", i, t * 1000000 + 3 * 100000 + i])
	var t0 := Time.get_ticks_msec()
	var games := 0
	for ji in jobs.size():
		if ji % nshard != shard:
			continue
		var jb: Array = jobs[ji]
		var t: int = jb[0]
		_use(t)
		var rng := RandomNumberGenerator.new()
		rng.seed = seed0 * 7919 + int(jb[4])
		var a := _deck(t, str(jb[1]), rng)
		var b := _deck(t, str(jb[2]), rng)
		var sd := rng.randi() % 1000000
		var da := DB.auto_place(a, "eorin")
		var db := DB.auto_place(b, "eorin")
		var ca := _counts(a)
		var cb := _counts(b)
		for swap in 2:
			var r: Dictionary
			if swap == 0:
				r = RtBattle.make(sd).run(da, "eorin", 100, null, db, "eorin", 100, null, "", "", [], {"A": "smart", "B": "smart"})
			else:
				r = RtBattle.make(sd).run(db, "eorin", 100, null, da, "eorin", 100, null, "", "", [], {"A": "smart", "B": "smart"})
			var sa := 0.5 if bool(r.draw) else (1.0 if bool(r.win) else 0.0)
			if swap == 1:
				sa = 1.0 - sa      # 덱A 기준 점수
			f.store_line("G,%s,%d,%s,%s,%d,%d,%d,%s,%.1f,%s,%s" % [mode, t, jb[1], jb[2], jb[3], swap, sd, str(sa), float(r.get("len", 0.0)), ca, cb])
			games += 1
		if games % 40 == 0:
			f.flush()
	f.close()
	print("CLASS_BASE mode=%s shard=%d/%d games=%d sec=%.1f out=%s" % [mode, shard, nshard, games, (Time.get_ticks_msec() - t0) / 1000.0, out_path])
	get_tree().quit()


func _use(t: int) -> void:
	if pools.has(t):
		return
	var pl := DB.by_tier(t).filter(func(k): return not DB.is_kiin(k))
	var bt := {}
	for k in pl:
		var tg: String = DB.C[k].tag
		if not bt.has(tg):
			bt[tg] = []
		bt[tg].append(k)
	pools[t] = [pl, bt]


## <병종>6 = 그 병종 6 (인물이 모자라면 다른 병종으로 채움) + 무작위 3 · 무작위 = 무작위 9 —— 같은 인물 한 장만
func _deck(t: int, name_: String, rng: RandomNumberGenerator) -> Array:
	var pool: Array = pools[t][0]
	var out := []
	if name_ != "무작위":
		var tg := name_.left(name_.length() - 1)
		for i in int(name_.right(1)):
			_add(out, pools[t][1].get(tg, []), pool, rng)
	while out.size() < 9:
		_add(out, pool, pool, rng)
	return out


func _add(out: Array, src: Array, pool: Array, rng: RandomNumberGenerator) -> void:
	var cand := src.filter(func(k): return not out.any(func(x): return DB.person(x) == DB.person(k)))
	if cand.is_empty():
		cand = pool.filter(func(k): return not out.any(func(x): return DB.person(x) == DB.person(k)))
	if cand.is_empty():
		cand = pool
	out.append(cand[rng.randi() % cand.size()])


func _counts(d: Array) -> String:
	var c := []
	for tg in TAGS:
		c.append(str(d.filter(func(k): return DB.C[k].tag == tg).size()))
	return ";".join(c)
