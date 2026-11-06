extends Node
## 실시간 엔진 들여다보기 —— 근접 · 원거리 유닛이 행동한 수와 논 시간 (헤드리스)
## 실행: godot --headless --path . res://tests/rtprobe.tscn [-- --tier=5 --games=40 --bow=250 --cast=220]

func _ready() -> void:
	var args := {}
	for s in OS.get_cmdline_user_args():
		var kv := s.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	if args.has("bow"): RtBattle.bow_range = float(args.bow)
	if args.has("cast"): RtBattle.cast_range = float(args.cast)
	if args.has("far"): RtBattle.far_mul = float(args.far)
	if args.has("near"): RtBattle.near_mul = float(args.near)
	if args.has("bank"): RtBattle.melee_bank = float(args.bank)
	if args.has("reach"): RtBattle.melee_gap = float(args.reach)
	if args.has("intm"): RtBattle.int_mul = float(args.intm)
	if args.has("intt"):          # --intt=3:1,4:0.9,… 등급별 책략 배율
		for kv in str(args.intt).split(","):
			RtBattle.int_tier[int(kv.split(":")[0])] = float(kv.split(":")[1])
	if args.has("charge"): RtBattle.cav_charge = float(args.charge)
	var t := int(args.get("tier", "5"))
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var st := {}
	var nm := 0
	var nr := 0
	var games := int(args.get("games", "40"))
	for i in games:
		var pool: Array = DB.by_tier(t)
		var a := []
		var b := []
		for j in 9:
			a.append(pool[rng.randi() % pool.size()])
			b.append(pool[rng.randi() % pool.size()])
		var bt := RtBattle.new(rng.randi() % 100000)
		var r := bt.run(DB.auto_place(a, "eorin"), "eorin", 100, null, DB.auto_place(b, "hagik"), "hagik", 100, null, "", "", [], {"A": "smart", "B": "smart"})
		for u in bt.units:
			if bt._ranged(u): nr += 1
			else: nm += 1
		for k in ["acts_m", "acts_r", "wait_m", "wait_r", "side", "rear", "idle_d", "idle_near", "idle_mid", "idle_far"]:
			st[k] = st.get(k, 0.0) + float(r.stats.get(k, 0))
	print("근접 %d · 원거리 %d 유닛" % [nm, nr])
	print("유닛당 행동: 근접 %.1f · 원거리 %.1f  /  유닛당 논 시간: 근접 %.1f초 · 원거리 %.1f초" % [st.acts_m / nm, st.acts_r / nr, st.wait_m / nm, st.wait_r / nr])
	print("측면 %.1f · 후방 %.1f /판" % [st.side / games, st.rear / games])
	print("근접이 놀 때 대상까지 평균 %.0f · 120 안 %.1f초 · 120~300 %.1f초 · 300 밖 %.1f초 (유닛당)" % [st.idle_d / maxf(0.01, st.wait_m), st.idle_near / nm, st.idle_mid / nm, st.idle_far / nm])
	get_tree().quit()
