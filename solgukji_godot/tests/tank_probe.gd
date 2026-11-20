extends Node
## 11/21 창병 탱커 셋 점검 —— 조인 도발 · 전위 역습 범위 · 주태 불사가 실제로 발동하나 (횟수만. 밸런스 측정이 아니다)
## 실행: godot --headless --path . res://tests/tank_probe.tscn [-- --n=12]

func _ready() -> void:
	var args := {}
	for arg in OS.get_cmdline_user_args():
		var kv := arg.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	var n := int(args.get("n", "12"))
	var keys := ["sig_taunt", "sig_taunt_pull", "sig_counter_all", "sig_counter_all_hits", "sig_undying"]
	for person in ["조인", "전위", "주태"]:
		var cards: Array = DB.C.keys().filter(func(k): return DB.person(k) == person and not DB.is_foe(k))
		for ck in cards:
			var tier: int = DB.C[ck].tier
			for t in DB.trait_list(ck):      # 장수 상세창 고유 특기 설명 (글 · 수치)
				if t.unique:
					print("  [%s] %s —— %s" % [t.name, t.d, t.mt])
			var pool := DB.by_tier(tier).filter(func(k): return not DB.is_foe(k) and DB.person(k) != person)
			var sum := {}
			var badge := {"taunted": 0, "undying": 0}
			for i in n:
				var rng := RandomNumberGenerator.new()
				rng.seed = 92100 + i
				var a := [ck] + _pick(pool, rng, 8)
				var b := _pick(pool, rng, 9)
				var bt := RtBattle.new(92100 + i)
				var r: Dictionary = bt.run(DB.auto_place(a, "eorin"), "eorin", 100, null, DB.auto_place(b, "hagik"), "hagik", 100, null, "", "", [], {"A": "smart", "B": "smart"})
				if args.has("v"): print("   판 %d 길이 %.1f %s" % [i, float(r.len), keys.map(func(k): return int(bt.stats.get(k, 0)))])
				for k in keys:
					sum[k] = int(sum.get(k, 0)) + int(bt.stats.get(k, 0))
				for e in r.ev:      # 화면 상태 목록(사건 스냅숏)에 딱지가 실렸나
					for row in e.s:
						for st in row[3]:
							if badge.has(st):
								badge[st] += 1
			print("%s %s(%d급) %d판 —— %s · 딱지 %s" % [person, ck, tier, n, sum, badge])
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
