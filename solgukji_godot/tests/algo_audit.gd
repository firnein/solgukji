extends Node
## 11/19 전투 알고리즘 감사 —— 실행: godot --headless --path . res://tests/algo_audit.tscn -- --n=12 --tag=이름
## 같은 덱 · 시드 묶음으로 엔진(RtBattle)을 돌려 이동 품질(옆걸음 · 뒷걸음 · 갈지자 · 막혀 선 시간 · 놀고 있는 시간)과
## 결과 지표(진영 치우침 · 전투 길이 · 병종별 생존)를 한 줄 요약으로 낸다. 알고리즘을 고치기 전 · 후를 같은 묶음으로 견준다.
## 덱마다 진영을 바꿔 두 번 돌린다 (A 쪽 승률이 50% 에서 벗어나면 자리 치우침).

func _ready() -> void:
	var args := {}
	for arg in OS.get_cmdline_user_args():
		var kv := arg.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	var n := int(args.get("n", "12"))
	RtBattle.algo_probe = true
	RtBattle.algo_v2 = str(args.get("v2", "1")) != "0"      # --v2=0 이면 예전 이동 알고리즘 (전후 비교)
	RtBattle.algo_bits = int(args.get("bits", str(RtBattle.algo_bits)))
	RtBattle.fair_order = str(args.get("fair", "1")) != "0"      # --fair=0 이면 예전 처리 순서 (A 진영 먼저)
	RtBattle.fair_debug = int(args.get("fairdbg", "0"))
	for off in str(args.get("off", "")).split(",", false):      # 치우침 원인 가르기 —— 기능을 끄고 진영 승률을 본다
		match off:
			"ults": Battle.ults_enabled = false
			"passives": Battle.passives_enabled = false
			"aura": Battle.aura_enabled = false
			"inyeon": Battle.inyeon_enabled = false
			"fire": Battle.fire_enabled = false
			"water": Battle.water_enabled = false
			"cut": Battle.cut_enabled = false
			"guard": Battle.guard_enabled = false
			"scheme": Battle.scheme_enabled = false
			"virtue": Battle.virtue_enabled = false
			"temper": Battle.temper_enabled = false
			"minor": Battle.minor_enabled = false
			"paeup": Battle.paeup_enabled = false
			"counter": Battle.counter_enabled = false
			"shield": Battle.shield_enabled = false
			_: push_error("모르는 스위치: " + off)
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261119 + int(args.get("shard", "0")) * 7919      # --shard=N 으로 다른 덱 묶음 (여러 프로세스로 나눠 돌린다)
	var forms := ["eorin", "hagik", "bongsi", "anwol"]
	var sum := {}
	var games := 0
	var a_wins := 0
	var draws := 0
	var len_sum := 0.0
	var timeouts := 0
	var tag_n := {}
	var tag_live := {}
	var tag_dmg := {}
	var usec := 0
	var sig := 0
	for i in n:
		var t: int = [4, 5, 6, 7, 8, 0][i % 6]      # 0 = 등급 섞음
		var a := _deck(t, rng)
		var b := _deck(t, rng)
		var fa: String = forms[rng.randi() % forms.size()]
		var fb: String = forms[rng.randi() % forms.size()]
		var seed := rng.randi() % 100000
		if args.has("mirror"):      # 거울 대전 —— 같은 덱 · 같은 진형끼리 (진영 치우침만 잰다. 시드를 바꿔 두 판)
			b = a
			fb = fa
		for swap in 2:
			if args.has("mirror"):
				seed += 1
			var da := a if swap == 0 else b
			var db := b if swap == 0 else a
			var ffa := fa if swap == 0 else fb
			var ffb := fb if swap == 0 else fa
			var t0 := Time.get_ticks_usec()
			var r: Dictionary = RtBattle.make(seed).run(DB.auto_place(da, ffa), ffa, 100, null, DB.auto_place(db, ffb), ffb, 100, null, "", "", [], {"A": "smart", "B": "smart"})
			usec += Time.get_ticks_usec() - t0
			games += 1
			if r.draw:
				draws += 1
			elif r.win:
				a_wins += 1
			len_sum += float(r.len)
			sig = hash([sig, r.win, r.len, r.ev.size()])
			var st: Dictionary = r.stats
			for k in st:
				if str(k).begins_with("ap_") or str(k).begins_with("us_") or k in ["wait_m", "wait_r", "acts_m", "acts_r", "idle_near", "idle_mid", "idle_far"]:
					sum[k] = float(sum.get(k, 0.0)) + float(st[k])
			for row in r.roster:
				tag_n[row.tag] = int(tag_n.get(row.tag, 0)) + 1
				tag_live[row.tag] = float(tag_live.get(row.tag, 0.0)) + float(row.left) / maxf(1.0, float(row.max))
				tag_dmg[row.tag] = float(tag_dmg.get(row.tag, 0.0)) + float(row.dmg)
	var mv := float(sum.get("ap_move_m", 0.0)) + float(sum.get("ap_move_r", 0.0))
	var out := {
		"a_wins": a_wins, "games": games, "a_win_pct": snappedf(100.0 * a_wins / maxf(1, games - draws), 0.1), "draws": draws,
		"len_avg": snappedf(len_sum / games, 0.01), "sim_ms_per_game": snappedf(usec / 1000.0 / games, 0.1),
		"first_touch_avg": snappedf(float(sum.get("ap_first_touch", 0.0)) / games, 0.01),
		"move_s_per_game": snappedf(mv / games, 0.1),
		"crab_pct": snappedf(100.0 * float(sum.get("ap_crab", 0.0)) / maxf(0.001, mv), 0.1),
		"back_pct": snappedf(100.0 * float(sum.get("ap_back", 0.0)) / maxf(0.001, mv), 0.1),
		"zig_per_game": snappedf(float(sum.get("ap_zig", 0.0)) / games, 0.1),
		"turn_deg_per_move_s": snappedf(rad_to_deg(float(sum.get("ap_turn_sum", 0.0))) / maxf(0.001, mv), 0.1),
		"dist_per_game": snappedf(float(sum.get("ap_dist", 0.0)) / games, 1.0),
		"blocked_m_s": snappedf(float(sum.get("ap_blocked_m", 0.0)) / games, 0.1),
		"blocked_r_s": snappedf(float(sum.get("ap_blocked_r", 0.0)) / games, 0.1),
		"wait_m_pct": snappedf(100.0 * float(sum.get("wait_m", 0.0)) / maxf(0.001, float(sum.get("ap_t_m", 0.0))), 0.1),
		"wait_r_pct": snappedf(100.0 * float(sum.get("wait_r", 0.0)) / maxf(0.001, float(sum.get("ap_t_r", 0.0))), 0.1),
		"idle_near_s": snappedf(float(sum.get("idle_near", 0.0)) / games, 0.1),
		"idle_mid_s": snappedf(float(sum.get("idle_mid", 0.0)) / games, 0.1),
		"idle_far_s": snappedf(float(sum.get("idle_far", 0.0)) / games, 0.1),
		"acts_m": snappedf(float(sum.get("acts_m", 0.0)) / games, 0.1), "acts_r": snappedf(float(sum.get("acts_r", 0.0)) / games, 0.1),
		"sig": sig,
		"ms_move": snappedf(float(sum.get("us_move", 0.0)) / 1000.0 / games, 0.1), "ms_solve": snappedf(float(sum.get("us_solve", 0.0)) / 1000.0 / games, 0.1),
		"ms_act_one": snappedf(float(sum.get("us_act_one", 0.0)) / 1000.0 / games, 0.1),
		"ms_act": snappedf(float(sum.get("us_act", 0.0)) / 1000.0 / games, 0.1), "ms_settle": snappedf(float(sum.get("us_settle", 0.0)) / 1000.0 / games, 0.1),
	}
	var tags := {}
	for tg in tag_n:
		tags[tg] = [snappedf(100.0 * float(tag_live[tg]) / tag_n[tg], 0.1), roundi(float(tag_dmg[tg]) / tag_n[tg])]
	out["tag_live_pct_dmg"] = tags
	print("ALGO_AUDIT ", JSON.stringify(out))
	var f := FileAccess.open("res://../build/algo_audit_%s.json" % str(args.get("tag", "run")), FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(out, "\t"))
		f.close()
	RtBattle.algo_probe = false
	get_tree().quit()


func _deck(t: int, rng: RandomNumberGenerator) -> Array:
	var d := []
	for i in 9:
		var tt: int = t if t > 0 else [4, 5, 6, 7, 8][rng.randi() % 5]
		var pool: Array = DB.by_tier(tt)
		d.append(pool[rng.randi() % pool.size()])
	return d
