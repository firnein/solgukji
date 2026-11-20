extends Node
## 1.2 궁병 17 · 도적 17 점검 —— 첫 등장 등급 카드로 몇 판 돌려 개성 행동이 실제로 일어나나 (횟수만. 밸런스 측정이 아니다)
## 실행: godot --headless --path . res://tests/sig_probe_bow.tscn [-- --n=12 --who=황충,감녕 --v]
## 센 값은 sig_rt.gd 의 _f / note_pick (b.stats "sig_<키>"), 말풍선은 그 장수가 낸 sig 사건 수.

const BOW := ["황충", "하후연", "태사자", "손권", "정보", "황개", "서성", "황월영", "엄안", "황조", "진무", "학소", "하제", "마충", "여상", "왕평", "장임"]
const THIEF := ["감녕", "여몽", "위연", "능통", "손상향", "주환", "장연", "정봉", "엄백호", "장패", "장포", "이각", "장만성", "관해", "악진", "장흠", "주창"]
const SHOW := ["seek_gen", "seek_guard", "seek_cav", "seek_back", "amp_far", "amp_still", "amp_come", "amp_open",
	"amp_cav", "amp_same", "amp_allies", "amp_drown", "dr_still", "no_pin", "bleed_on", "slow_on", "morale_on",
	"gauge_on", "kill_gauge", "kite", "hit_run", "spd_aura", "stealth", "ambush", "ignite", "cleave"]


func _ready() -> void:
	var args := {}
	for arg in OS.get_cmdline_user_args():
		var kv := arg.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	var n := int(args.get("n", "12"))
	var names: Array = Array(str(args["who"]).split(",")) if args.has("who") else BOW + THIEF
	for person in names:
		var cards: Array = DB.C.keys().filter(func(k): return DB.person(k) == person and not DB.is_foe(k))
		if cards.is_empty():
			print("%s —— 카드 없음" % person)
			continue
		cards.sort_custom(func(a, b): return DB.C[a].tier < DB.C[b].tier)
		var ck: String = cards[0]      # 첫 등장 등급
		var tier: int = DB.C[ck].tier
		var desc := ""
		for t in DB.trait_list(ck):
			if t.unique:
				desc = "[%s] %s —— %s" % [t.name, t.d, t.mt]
		var pool := DB.by_tier(tier).filter(func(k): return not DB.is_foe(k) and DB.person(k) != person)
		var sum := {}
		var says := 0
		for i in n:
			var rng := RandomNumberGenerator.new()
			rng.seed = 93100 + i
			var a := [ck] + _pick(pool, rng, 8)
			var b := _pick(pool, rng, 9)
			var bt := RtBattle.new(93100 + i)
			var r: Dictionary = bt.run(DB.auto_place(a, "eorin"), "eorin", 100, null, DB.auto_place(b, "hagik"), "hagik", 100, null, "", "", [], {"A": "smart", "B": "smart"})
			var me := _key_of(bt, ck)
			for k in SHOW:
				var sk := "u%s:%s" % [me, k]
				if bt.stats.has(sk):
					sum[k] = int(sum.get(k, 0)) + int(bt.stats[sk])
			for k in ["sig_kite_ticks", "sig_hide_hit"]:      # 판 전체 값 (후퇴 틱 수 · 위장 중 맞은 수)
				if bt.stats.has(k):
					sum[k] = int(sum.get(k, 0)) + int(bt.stats[k])
			for e in r.ev:
				if e.get("sig", false) and str(e.get("f", "")) == me:
					says += 1
		print("%s %s(%d급 %s · 등급들 %s) %d판 —— %s · 말풍선 %d" % [person, ck, tier, DB.C[ck].tag, cards.map(func(k): return DB.C[k].tier), n, sum, says])
		if args.has("v"):
			print("   ", desc)
	get_tree().quit()


func _key_of(bt, ck: String) -> String:
	for u in bt.units:
		if u.camp == "A" and u.c.name == DB.C[ck].name:
			return u.key
	return ""


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
