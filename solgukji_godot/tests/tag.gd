extends Node
## 병종 점검 —— 실행: godot --headless --path . res://tests/tag.tscn [-- --tiers=3,4,5,6 --games=200 --adj=기병:atk=0.9,def=0.9]
##
## 병종 덱: 그 등급의 그 병종 카드 전부(6장 넘으면 판마다 6장) + 같은 등급 무작위로 9장 → 같은 등급 무작위 덱과 붙인다.
## 병종마다 승률이 50% 안팎이어야 고르다. --adj 는 cards_ext.json stat_adjust 를 그 등급들에 덮어 써 본다.
## 양쪽 영리 AI, 홀수 판은 진영을 바꿔 붙인다.

const FORMS := ["eorin", "hagik", "bongsi", "anwol", "bangwon", "anhaeng", "chuhaeng", "jangsa"]
var games := 200
var rt := false            # --rt: 실시간 엔진
var _turns := 0.0
var _n := 0


func _ready() -> void:
	var args := {}
	for s in OS.get_cmdline_user_args():
		var kv := s.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	games = int(args.get("games", "200"))
	rt = args.has("rt")
	Battle.ults_enabled = not args.has("noult")
	if args.has("nopsv"): Battle.passives_enabled = false
	if args.has("bow"): RtBattle.bow_range = float(args.bow)
	if args.has("cast"): RtBattle.cast_range = float(args.cast)
	if args.has("far"): RtBattle.far_mul = float(args.far)
	if args.has("near"): RtBattle.near_mul = float(args.near)
	if args.has("bank"): RtBattle.melee_bank = float(args.bank)
	if args.has("reach"): RtBattle.melee_reach = float(args.reach)
	if args.has("intm"): RtBattle.int_mul = float(args.intm)
	if args.has("intt"):          # --intt=3:1,4:0.9,… 등급별 책략 배율
		for kv in str(args.intt).split(","):
			RtBattle.int_tier[int(kv.split(":")[0])] = float(kv.split(":")[1])
	if args.has("charge"): RtBattle.cav_charge = float(args.charge)
	if args.has("tmul"):                  # 턴 배율 (Battle.turn_mul) 바꿔 보기
		Battle.auto_turn = false
		Battle.set_turn_mul(float(args.tmul))
	var tiers: Array = Array(str(args.get("tiers", "3,4,5,6")).split(",")).map(func(x): return int(x))
	if args.has("pace"):                  # 턴 길이 바꿔 보기 —— 피해 · 회복 배율 (기본 0.35)
		Battle.pace = float(args.pace)
	if args.has("raw"):
		DB.set_stat_adjust({})
	if args.has("adj"):
		var parts: PackedStringArray = str(args.adj).split(":", true, 1)
		var m := {}
		for kv in parts[1].split(","):
			var p := kv.split("=")
			m[p[0]] = float(p[1])
		var adj: Dictionary = DB.STAT_ADJ.duplicate(true)
		adj[parts[0]] = {}
		for t in tiers:
			adj[parts[0]][str(t)] = m
		DB.set_stat_adjust(adj)
	var only: String = str(args.get("tag", ""))
	var t0 := Time.get_ticks_msec()
	for t in tiers:
		var line := []
		for tag in DB.D.TAGORDER:
			if only != "" and tag != only:
				continue
			var deck: Array = DB.by_tier(t).filter(func(k): return DB.C[k].tag == tag)
			if deck.is_empty():
				continue
			line.append("%s %.0f%%" % [tag, _match(t, deck)])
		print("%s: %s · 평균 %.1f턴" % [DB.TIER[t].n, " · ".join(line), _turns / maxf(1, _n)])
		_turns = 0.0
		_n = 0
	print("소요 %.1f초" % ((Time.get_ticks_msec() - t0) / 1000.0))
	get_tree().quit()


func _match(t: int, core: Array) -> float:
	var rng := RandomNumberGenerator.new()
	rng.seed = 700 + t * 13
	var pool: Array = DB.by_tier(t).filter(func(k): return not core.has(k))
	var all: Array = DB.by_tier(t)
	var w := 0.0
	for i in games:
		var a := core.duplicate()
		while a.size() > 6:
			a.remove_at(rng.randi() % a.size())
		while a.size() < 9:
			a.append(pool[rng.randi() % pool.size()])
		var b := []
		while b.size() < 9:
			b.append(all[rng.randi() % all.size()])
		var fa: String = FORMS[rng.randi() % FORMS.size()]
		var fb: String = FORMS[rng.randi() % FORMS.size()]
		var sd := rng.randi() % 100000
		var flip := i % 2 == 1
		var pa := DB.auto_place(a, fa)
		var pb := DB.auto_place(b, fb)
		var r: Dictionary
		if flip:
			r = (RtBattle.new(sd) if rt else Battle.new(sd)).run(pb, fb, 100, null, pa, fa, 100, null, "", "", [], {"A": "smart", "B": "smart"})
		else:
			r = (RtBattle.new(sd) if rt else Battle.new(sd)).run(pa, fa, 100, null, pb, fb, 100, null, "", "", [], {"A": "smart", "B": "smart"})
		w += 1.0 if (r.win != flip and not r.draw) else (0.5 if r.draw else 0.0)
		_turns += r.turns
		_n += 1
	return w / games * 100
