extends Node
## 11/19 행동 간격 규칙(RtBattle.spd_rule) 전/후 비교 —— 같은 덱 묶음 · 같은 시드로 예전 식(false)과 새 식(true)을 돌려
## 판마다 · 부대마다 한 줄씩 파일로 남긴다 (집계는 밖에서). 엔진은 건드리지 않는다.
## 실행: godot --headless --path . res://tests/spd_balance.tscn -- --nt=10 --nm=40 --nr=30 --shard=0 --out=C:/.../spd_balance_0.csv
##   nt = 등급(3~8)마다 덱 쌍 수 · nm = 등급 섞은(4~8) 덱 쌍 수 · nr = 거울 대전 덱 수 (시드 둘씩)
##   덱 쌍은 진영을 바꿔 두 번 돌린다. 줄 머리: C = 카드, G = 판, U = 부대

func _ready() -> void:
	var args := {}
	for arg in OS.get_cmdline_user_args():
		var kv := arg.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	var nt := int(args.get("nt", "4"))
	var nm := int(args.get("nm", "8"))
	var nr := int(args.get("nr", "8"))
	var shard := int(args.get("shard", "0"))
	var pol := str(args.get("pol", "smart"))
	var out_path := str(args.get("out", "user://spd_balance_%d.csv" % shard))
	var f := FileAccess.open(out_path, FileAccess.WRITE)
	if f == null:
		push_error("파일을 못 연다: " + out_path)
		get_tree().quit(1)
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261119 + shard * 7919
	var forms := ["eorin", "hagik", "bongsi", "anwol"]
	if shard == 0:
		for k in DB.C:
			if not DB.is_foe(k):
				f.store_line("C,%s,%d,%s,%s" % [k, int(DB.C[k].tier), DB.C[k].tag, str(DB.C[k].spd)])
	# 덱 묶음을 먼저 다 만든다 —— 두 규칙이 똑같은 묶음을 쓴다
	var jobs := []      # [모드, 덱 a, 덱 b, 진형 a, 진형 b, 시드]
	for t in [3, 4, 5, 6, 7, 8]:
		for i in nt:
			jobs.append(["t%d" % t, _deck(t, rng), _deck(t, rng), forms[rng.randi() % 4], forms[rng.randi() % 4], rng.randi() % 100000])
	for i in nm:
		jobs.append(["mix", _deck(0, rng), _deck(0, rng), forms[rng.randi() % 4], forms[rng.randi() % 4], rng.randi() % 100000])
	for i in nr:
		var d := _deck([4, 5, 6, 7, 8, 0][i % 6], rng)
		var fm: String = forms[rng.randi() % 4]
		jobs.append(["mirror", d, d, fm, fm, rng.randi() % 100000])
	var gid := shard * 1000000
	var t_all := Time.get_ticks_msec()
	for rule in [false, true]:
		RtBattle.spd_rule = rule
		for ji in jobs.size():
			var jb: Array = jobs[ji]
			for swap in 2:
				var mirror: bool = jb[0] == "mirror"
				var da: Array = jb[1] if swap == 0 or mirror else jb[2]
				var db: Array = jb[2] if swap == 0 or mirror else jb[1]
				var fa: String = jb[3] if swap == 0 or mirror else jb[4]
				var fb: String = jb[4] if swap == 0 or mirror else jb[3]
				var seed: int = int(jb[5]) + (swap if mirror else 0)      # 거울은 시드를 바꿔 두 판, 나머지는 같은 시드로 진영만 바꾼다
				var r: Dictionary = RtBattle.make(seed).run(DB.auto_place(da, fa), fa, 100, null, DB.auto_place(db, fb), fb, 100, null, "", "", [], {"A": pol, "B": pol})
				gid += 1
				var ults := 0
				var timeout := 0
				for e in r.ev:
					if e.get("fx") == "ult":
						ults += 1
					elif e.get("c") == "div" and str(e.get("t", "")).begins_with("해가 기운다"):
						timeout = 1
				var w := "D" if bool(r.draw) else ("A" if bool(r.win) else "B")
				f.store_line("G,%d,%d,%s,%d,%d,%d,%s,%s,%d,%d,%d,%s,%s" % [gid, 1 if rule else 0, jb[0], shard * 100000 + ji, swap, seed, str(r.len), w, ults, timeout, int(r.turns), fa, fb])
				for row in r.roster:
					f.store_line("U,%d,%s,%s,%d,%s,%s,%d,%d,%d,%d,%d,%d,%d,%d,%s" % [gid, row.camp, row.id, int(row.tier), row.tag, str(DB.C[row.id].spd),
						int(row.max), int(row.dmg), int(row.dot), int(row.heal), int(row.kills), int(row.left), 1 if bool(row.alive) else 0, int(row.taken), str(row.line)])
			if ji % 20 == 19:
				f.flush()
	RtBattle.spd_rule = true      # 기본값으로 되돌린다
	f.close()
	print("SPD_BALANCE shard=%d games=%d sec=%.1f out=%s" % [shard, gid - shard * 1000000, (Time.get_ticks_msec() - t_all) / 1000.0, out_path])
	get_tree().quit()


func _deck(t: int, rng: RandomNumberGenerator) -> Array:
	var d := []
	for i in 9:
		var tt: int = t if t > 0 else [4, 5, 6, 7, 8][rng.randi() % 5]
		var pool: Array = DB.by_tier(tt)
		d.append(pool[rng.randi() % pool.size()])
	return d
