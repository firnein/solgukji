extends Node
## 11/22 특별한 특기(전장 행동을 바꾸는 개성) 점검 —— 그 카드 한 장 + 같은 등급 무작위 8 대 같은 등급 무작위 9.
## 카드의 생존 시간 · 준 피해 · 쓰러뜨림 · 승률 · 발동 횟수를 낸다. --off 면 새 특별 특기(sig_rt special_on)를 끈 채 (같은 시드 → 전 · 후 짝비교)
## 실행: godot --headless --path . res://tests/sig_special.tscn -- --cards=c150,E08 --n=40 [--off]

func _ready() -> void:
	var args := {}
	for arg in OS.get_cmdline_user_args():
		var kv := arg.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	var n := int(args.get("n", "40"))
	var SR = load("res://scripts/sig_rt.gd")
	SR.special_on = not args.has("off")
	SR.say_on = false
	for ck in str(args.get("cards", "c150")).split(","):
		var tier: int = DB.C[ck].tier
		var mine := []      # 그 카드의 특별 특기만 켠다 (덱의 다른 장수 특별 특기는 끈다 —— 이 카드 하나의 효과)
		var sgp = DB.PSV.get("sig", {}).get(DB.person(ck))
		if sgp != null:
			for k in (sgp[2] as Dictionary):
				if k in SR.SPECIAL_KEYS:
					mine.append(k)
		SR.special_only = mine if not mine.is_empty() else ["_none"]
		var kiin: bool = DB.is_kiin(ck)
		var pool: Array = DB.by_tier(tier if not kiin else 6).filter(func(k): return not DB.is_foe(k) and not DB.is_kiin(k) and DB.person(k) != DB.person(ck))
		var surv := 0.0
		var alive_n := 0
		var dmg := 0.0
		var kills := 0
		var win := 0.0
		var len_sum := 0.0
		var sig := {}
		for i in n:
			var rng := RandomNumberGenerator.new()
			rng.seed = 7700 + i
			var a := [ck] + _pick(pool, rng, 8)
			var b := _pick(pool, rng, 9)
			var bt := RtBattle.new(7700 + i)
			var r: Dictionary = bt.run(DB.auto_place(a, "eorin"), "eorin", 100, null, DB.auto_place(b, "hagik"), "hagik", 100, null, "", "", [], {"A": "smart", "B": "smart"})
			var idx := -1
			for j in bt.units.size():
				if bt.units[j].c.id == ck and bt.units[j].camp == "A":
					idx = j
			var u = bt.units[idx]
			var end_t: float = float(r.ev[-1].tm) if not r.ev.is_empty() else 0.0
			var dt := end_t
			for e in r.ev:
				if int(e.s[idx][2]) == 0:
					dt = float(e.tm)
					break
			surv += dt
			len_sum += end_t
			if u.alive:
				alive_n += 1
			dmg += u.dmg
			kills += u.kills
			win += 1.0 if r.win else (0.5 if r.draw else 0.0)
			for k in bt.stats:
				if str(k).begins_with("sig_") and (mine.any(func(x): return str(k).contains(x)) or str(k).contains("sp_dr") or str(k).contains("_hit")):
					sig[k] = int(sig.get(k, 0)) + int(bt.stats[k])
		print("%s %s(%d급 %s) %d판 %s —— 생존 %.1f초 / 판 %.1f초 · 끝까지 생존 %d%% · 준 피해 %.0f · 쓰러뜨림 %.2f · 승률 %.0f%%" % [DB.C[ck].name, ck, tier, DB.C[ck].tag, n, "끔" if args.has("off") else "켬",
			surv / n, len_sum / n, 100 * alive_n / n, dmg / n, float(kills) / n, 100.0 * win / n])
		print("    ", sig)
	get_tree().quit()


func _pick(pool: Array, rng: RandomNumberGenerator, cnt: int) -> Array:
	var out := []
	var people := []
	var cand := pool.duplicate()
	while out.size() < cnt and not cand.is_empty():
		var k: String = cand.pop_at(rng.randi_range(0, cand.size() - 1))
		if not people.has(DB.person(k)):
			out.append(k)
			people.append(DB.person(k))
	return out
