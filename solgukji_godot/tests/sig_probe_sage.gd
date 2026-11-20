extends Node
## 1.2 책사 · 술사 개성 점검 —— 담당 31명의 개성 키(고유 특기)가 5급(첫 등장 등급)에서 실제로 발동하나 (횟수만. 밸런스 측정이 아니다)
## 실행: godot --headless --path . res://tests/sig_probe_sage.tscn [-- --n=10 --who=주유,육손]

const SAGES := ["주유", "육손", "방통", "제갈량", "곽가", "서서", "강유", "종회", "마량", "순유", "저수", "제갈각", "황권", "감택", "유엽", "이적", "허유",
	"장각", "좌자", "우길", "관로", "장로", "화타", "남화노선", "길평", "우번", "이의", "오범", "장보", "주건평", "초주"]

func _ready() -> void:
	var args := {}
	for arg in OS.get_cmdline_user_args():
		var kv := arg.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	var n := int(args.get("n", "10"))
	var who: Array = Array(str(args["who"]).split(",")) if args.has("who") else SAGES
	for person in who:
		var cards: Array = DB.C.keys().filter(func(k): return DB.person(k) == person and not DB.is_foe(k))
		cards.sort_custom(func(a, b): return DB.C[a].tier < DB.C[b].tier)
		var ck := ""
		for c in cards:      # 5급 이상 첫 카드, 없으면 가장 높은 카드(그 인물의 첫 등장 등급)
			ck = c
			if DB.C[c].tier >= 5:
				break
		if ck == "":
			continue
		var tier: int = DB.C[ck].tier
		# 상대 · 아군 풀에서 개성 키가 있는 카드는 뺀다 —— 통계에 남의 발동이 섞이지 않게
		var pool := DB.by_tier(tier).filter(func(k): return not DB.is_foe(k) and DB.person(k) != person and not _has_sig(k))
		# --foe=N : 상대를 N급 풀 전체(고유기 · 방진 · 개성 포함)에서 뽑는다 —— 감택 · 주건평 · 서서처럼 상대에 고유기 · 방진이 있어야 발동하는 개성용
		var fpool: Array = DB.by_tier(int(args["foe"])).filter(func(k): return not DB.is_foe(k)) if args.has("foe") else pool
		var sum := {}
		var says := {}
		var badge := {}
		var klen := 0.0
		for i in n:
			var rng := RandomNumberGenerator.new()
			rng.seed = 93100 + i
			var a := [ck] + _pick(pool, rng, 8)
			var b := _pick(fpool, rng, 9)
			var bt := RtBattle.new(93100 + i)
			var r: Dictionary = bt.run(DB.auto_place(a, "eorin"), "eorin", 100, null, DB.auto_place(b, "hagik"), "hagik", 100, null, "", "", [], {"A": "smart", "B": "smart"})
			klen += float(r.len)
			for k in bt.stats:
				if str(k).begins_with("sig_") or str(k) in ["spreads", "cleaves", "confuses", "flows"]:
					sum[k] = int(sum.get(k, 0)) + int(bt.stats[k])
			for e in r.ev:
				if e.get("sig", false):
					var t := str(e.get("t", ""))
					var key := t.substr(t.find("의 ") + 2).split(" ——")[0]
					says[key] = int(says.get(key, 0)) + 1
				for row in e.s:
					for st in row[3]:
						if st in ["taunted", "undying", "marked", "rained", "sigged"]:
							badge[st] = int(badge.get(st, 0)) + 1
		for t in DB.trait_list(ck):
			if t.unique:
				print("  [%s] %s —— %s" % [t.name, t.d, t.mt])
		print("%s %s(%d급) %d판 %.0f초 —— 통계 %s · 말풍선 %s · 딱지 %s" % [person, ck, tier, n, klen / n, sum, says, badge])
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


func _has_sig(ck: String) -> bool:
	var keys: Array = load("res://scripts/sig_rt.gd").KEYS
	for t in DB.trait_list(ck):
		if t.unique:
			var tr: Dictionary = DB.PSV.traits[t.name]
			for k in keys:
				if tr.get("m", {}).has(k) or tr.get("self", {}).has(k):
					return true
	return false
