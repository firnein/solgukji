extends Node
## 11/14 같은 병종끼리 전투 길이 —— 실행: godot --headless --path . res://tests/spear_len.tscn [-- --games=6 --tier=7 --seed=900 --mirror=1.0]
## 덱 = 그 병종 6 + 무작위 2 (8부대) 거울전, 섞음 = 무작위 8. 창병끼리 판이 늘어지는지 본다 (class_guard.engage.spear_mirror)

const KINDS := ["창병", "기병", "궁병", "섞음"]


func _ready() -> void:
	var args := {}
	for s in OS.get_cmdline_user_args():
		var kv := s.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	var games := int(args.get("games", "6"))
	var tier := int(args.get("tier", "7"))
	var seed0 := int(args.get("seed", "900"))
	if args.has("mirror"):      # --mirror=1.0 → 창병끼리 배율 덮어쓰기 (끄고 비교)
		Battle.tune_over["engage"] = {"spear_mirror": float(args.mirror)}
	var pool: Array = DB.by_tier(tier).filter(func(k): return not DB.is_kiin(k))
	print("창병끼리 배율 %.2f · 등급 %d · %d판" % [Battle.engage_v("spear_mirror", 1.0), tier, games])
	for kind in KINDS:
		var rng := RandomNumberGenerator.new()
		rng.seed = seed0 + KINDS.find(kind) * 37
		var tot := 0.0
		var mx := 0.0
		var lens := []
		for g in games:
			var da := DB.auto_place(_deck(kind, pool, rng), "eorin")
			var db := DB.auto_place(_deck(kind, pool, rng), "eorin")
			var r := RtBattle.make(rng.randi() % 1000000).run(da, "eorin", 100, null, db, "eorin", 100, null, "", "", [], {"A": "smart", "B": "smart"})
			var ln := float(r.get("len", 0.0))
			tot += ln
			mx = maxf(mx, ln)
			lens.append("%.0f" % ln)
		print("%s  평균 %.1f초 · 최대 %.1f초  (%s)" % [kind, tot / games, mx, " ".join(lens)])
	get_tree().quit()


## 그 병종 6 + 무작위 2 (섞음은 무작위 8)
func _deck(kind: String, pool: Array, rng: RandomNumberGenerator) -> Array:
	var out := []
	var same := pool.filter(func(k): return DB.C[k].tag == kind)
	for i in (0 if kind == "섞음" else 6):
		_add(out, same, pool, rng)
	while out.size() < 8:
		_add(out, pool, pool, rng)
	return out


## 같은 인물은 한 장만
func _add(out: Array, src: Array, pool: Array, rng: RandomNumberGenerator) -> void:
	var cand := src.filter(func(k): return not out.any(func(x): return DB.person(x) == DB.person(k)))
	if cand.is_empty():
		cand = pool.filter(func(k): return not out.any(func(x): return DB.person(x) == DB.person(k)))
	out.append(cand[rng.randi() % cand.size()])
