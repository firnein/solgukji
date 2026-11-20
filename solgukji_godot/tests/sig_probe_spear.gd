extends Node
## 1.2 창병 18명 점검 —— 첫 등장 등급에서 몇 판 돌려 개성 행동이 실제로 발동하는지 횟수로 (밸런스 측정이 아니다)
## 실행: godot --headless --path . res://tests/sig_probe_spear.tscn [-- --n=10 --nosay --who=관우]
## --nosay: 말풍선 없이 횟수만 (같은 판을 말풍선 유무로 비교 · 전 점검). 숫자 = 판 전체 합 (sig_ 횟수 · 눈에 보이는 말풍선 수)

const PEOPLE := ["고순", "방덕", "관우", "관평", "장비", "허저", "서황", "하후돈", "우금", "이전", "문빙", "고람", "관흥", "왕쌍", "주연", "기령", "능조", "요화"]

func _ready() -> void:
	var args := {}
	for arg in OS.get_cmdline_user_args():
		var kv := arg.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	var n := int(args.get("n", "10"))
	load("res://scripts/sig_rt.gd").say_on = not args.has("nosay")
	var bad := 0
	for person in PEOPLE:
		if args.has("who") and str(args.who) != person:
			continue
		var cards: Array = DB.C.keys().filter(func(k): return DB.person(k) == person and not DB.is_foe(k))
		cards.sort_custom(func(x, y): return DB.C[x].tier < DB.C[y].tier)
		if cards.is_empty():
			print("%s —— 카드 없음" % person)
			continue
		var ck: String = cards[0]
		var tier: int = DB.C[ck].tier
		for t in DB.trait_list(ck):
			if t.unique:
				var txt := "%s %s" % [t.d, t.mt]
				print("  [%s] %s —— %s" % [t.name, t.d, t.mt])
				if txt.contains("턴"):
					print("  !! 턴 표현 남음")
					bad += 1
		var pool := DB.by_tier(tier).filter(func(k): return not DB.is_foe(k) and DB.person(k) != person)
		var foe_pool := pool
		if person == "주연":      # 화계 차단은 불이 나야 보인다 —— 적을 책략 · 술사 쪽으로
			foe_pool = pool.filter(func(k): return DB.C[k].tag in ["책사", "술사", "모사"])
		var sum := {}
		var says := 0
		var len_sum := 0.0
		for i in n:
			var rng := RandomNumberGenerator.new()
			rng.seed = 12000 + i
			var a := [ck] + _pick(pool, rng, 8)
			var b := _pick(foe_pool, rng, 9)
			var bt := RtBattle.new(12000 + i)
			var r: Dictionary = bt.run(DB.auto_place(a, "eorin"), "eorin", 100, null, DB.auto_place(b, "hagik"), "hagik", 100, null, "", "", [], {"A": "smart", "B": "smart"})
			len_sum += float(r.len)
			var mine := ""      # 이 장수 부대의 키 (A 진영)
			for u in bt.units:
				if u.camp == "A" and u.c == DB.C[ck]:
					mine = u.key
			for k in bt.stats:
				if str(k).begins_with("su_%s_" % mine) and int(bt.stats[k]) > 0:
					var kk := str(k).trim_prefix("su_%s_" % mine)
					sum[kk] = int(sum.get(kk, 0)) + int(bt.stats[k])
			for e in r.ev:
				if e.get("sig", false) and str(e.get("t", "")).contains(person + "의"):
					says += 1
		print("%s %s(%d급) %d판 평균 %.0f초 —— 발동 %s · 말풍선 %d" % [person, ck, tier, n, len_sum / n, sum, says])
	if bad > 0:
		print("턴 표현 %d건" % bad)
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
