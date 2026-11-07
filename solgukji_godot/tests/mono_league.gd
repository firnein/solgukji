extends Node
## 11/8 병종 몰빵 대 고루 리그전 (docs/역할_재설계_1108.md 9.4-1) —— 실행: godot --headless --path . res://tests/mono_league.tscn
##   [-- --games=8 --tier=7 --decks=창병6,술사6,물리9,책략9,고루 --noshield --guard=창병:0.3,기병:0.15,술사:0.3,책사:0.15]
## 같은 등급 카드로만 짜서 비용을 맞춘다 (budget_mix 처럼 판마다 덱을 새로 뽑고, 같은 시드로 자리를 바꿔 두 번).
## 덱: <병종>6 = 그 병종 6 + 무작위 3 · 물리9 / 책략9 = 그 피해 종류만 · 고루 = 병종마다 1 + 무작위 1 (갑옷 깎기 · 결계 깎기 장수 각 1 먼저) · 고루0 = 고루에서 깎기 장수를 뺀 것
## 결과: 상성표(행 덱의 승률) · 리그 평균 · 상대별 승률 폭(가장 높은 − 가장 낮은)

const DECKS := ["창병6", "기병6", "궁병6", "도적6", "책사6", "모사6", "술사6", "유생6", "물리9", "책략9", "고루", "고루0"]

var pool: Array = []
var by_tag := {}
var phys_sh: Array = []
var int_sh: Array = []


func _ready() -> void:
	var args := {}
	for s in OS.get_cmdline_user_args():
		var kv := s.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	var games := int(args.get("games", "8"))
	var tier := int(args.get("tier", "7"))
	var names: Array = Array(str(args.get("decks", ",".join(DECKS))).split(","))
	if args.has("noshield"):
		Battle.shield_enabled = false
	Battle.guard_over = Battle.guard_arg(str(args.get("guard", "")))
	pool = DB.by_tier(tier).filter(func(k): return not DB.is_kiin(k))
	for k in pool:
		var tg: String = DB.C[k].tag
		if not by_tag.has(tg):
			by_tag[tg] = []
		by_tag[tg].append(k)
		if _phys_shred(k):
			phys_sh.append(k)
		if _int_shred(k):
			int_sh.append(k)
	print("── 리그전 등급 %d (%s) · 막 %s · 판 %d × 자리 2 · 갑옷 깎기 %d명 · 결계 깎기 %d명 %s" % [tier, DB.TIER[tier].n,
		"끔" if not Battle.shield_enabled else ("켬" if Battle.guard_over.is_empty() else str(Battle.guard_over)), games, phys_sh.size(), int_sh.size(),
		"" if names.size() == DECKS.size() else str(names)])
	var w := {}
	for a in names:
		w[a] = {}
	var t0 := Time.get_ticks_msec()
	for i in names.size():
		for j in range(i + 1, names.size()):
			var rng := RandomNumberGenerator.new()
			rng.seed = 700 + i * 31 + j
			var s := 0.0
			for g in games:
				var da := DB.auto_place(_deck(names[i], rng), "eorin")
				var db := DB.auto_place(_deck(names[j], rng), "eorin")
				var sd := rng.randi() % 1000000
				var r1 := RtBattle.make(sd).run(da, "eorin", 100, null, db, "eorin", 100, null, "", "", [], {"A": "smart", "B": "smart"})
				var r2 := RtBattle.make(sd).run(db, "eorin", 100, null, da, "eorin", 100, null, "", "", [], {"A": "smart", "B": "smart"})
				s += (1.0 if r1.win else (0.5 if r1.draw else 0.0)) + (1.0 if (not r2.win and not r2.draw) else (0.5 if r2.draw else 0.0))
			var p := s / (games * 2.0)
			w[names[i]][names[j]] = p
			w[names[j]][names[i]] = 1.0 - p
	var head := "%-6s" % "덱"
	for b in names:
		head += " %5s" % str(b).left(4)
	print(head + "   평균   폭")
	var rows := []
	for a in names:
		var line := "%-6s" % a
		var sum := 0.0
		var lo := 1.0
		var hi := 0.0
		for b in names:
			if a == b:
				line += "     -"
				continue
			var p: float = w[a][b]
			line += " %5d" % roundi(p * 100)
			sum += p
			lo = minf(lo, p)
			hi = maxf(hi, p)
		var avg := sum / (names.size() - 1)
		rows.append([avg, a])
		print(line + "  %4d%%  %3d" % [roundi(avg * 100), roundi((hi - lo) * 100)])
	rows.sort_custom(func(x, y): return x[0] > y[0])
	print("순위: %s   (%.0f초)" % [" > ".join(rows.map(func(x): return "%s %d%%" % [x[1], roundi(x[0] * 100)])), (Time.get_ticks_msec() - t0) / 1000.0])
	get_tree().quit()


func _deck(name_: String, rng: RandomNumberGenerator) -> Array:
	var out := []
	if name_ == "물리9" or name_ == "책략9":
		var src := pool.filter(func(k): return DB.dmg_kind(DB.C[k].tag) == ("phys" if name_ == "물리9" else "int"))
		for i in 9:
			_add(out, src, rng)
	elif name_.begins_with("고루"):
		var no_sh := name_ == "고루0"
		if not no_sh:
			_add(out, phys_sh, rng)
			_add(out, int_sh, rng)
		for tg in DB.D.TAGORDER:
			if out.any(func(x): return DB.C[x].tag == tg):
				continue
			_add(out, by_tag.get(tg, []).filter(func(k): return not no_sh or not (phys_sh.has(k) or int_sh.has(k))), rng)
		while out.size() < 9:
			_add(out, pool.filter(func(k): return not no_sh or not (phys_sh.has(k) or int_sh.has(k))), rng)
	else:
		var tg := name_.trim_suffix("6")
		for i in 6:
			_add(out, by_tag.get(tg, []), rng)
		while out.size() < 9:
			_add(out, pool, rng)
	return out


## 같은 인물은 한 장만 (모자라면 겹쳐도)
func _add(out: Array, src: Array, rng: RandomNumberGenerator) -> void:
	if src.is_empty():
		src = pool
	var cand := src.filter(func(k): return not out.any(func(x): return DB.person(x) == DB.person(k)))
	if cand.is_empty():
		cand = src
	out.append(cand[rng.randi() % cand.size()])


static func _phys_shred(k: String) -> bool:
	var ps = DB.passives_of(k)
	if ps == null:
		return false
	return ps.traits.any(func(t): return t.name != "현혹" and (t.m.has("cut_def") or t.m.has("first_cut") or t.m.has("rush")))


static func _int_shred(k: String) -> bool:
	var ps = DB.passives_of(k)
	if ps == null:
		return false
	return ps.traits.any(func(t): return t.name == "현혹" or t.name == "요언")
