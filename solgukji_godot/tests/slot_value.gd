extends Node
## 한 칸의 값 —— 실행: godot --headless --path . res://tests/slot_value.tscn [-- --games=20 --base=7 --myth=1 --cand=6]
## (11/7 사용자: 초월 · 기인이 버려지고 신화 · 불멸로만 덱이 꾸려진다)
## 덱 A = 신화 myth 장 + base 등급 무작위 (8 − myth) 장 + 후보 1장, 덱 B = 같은 덱에서 후보 자리에 base 등급 무작위 1장.
## 후보마다 A 의 승률을 낸다. 50% 면 그 후보가 base 한 장만큼 일한다. 자리를 바꿔 두 번.
## --cand=6 (초월) · kiin (기인) · 5 (전설) · all (등급 평균만)
const FORMS := ["eorin", "hagik", "bongsi", "anwol", "bangwon", "anhaeng", "chuhaeng", "jangsa"]


func _ready() -> void:
	var args := {}
	for s in OS.get_cmdline_user_args():
		var kv := s.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	var games := int(args.get("games", "20"))
	var base_t := int(args.get("base", "7"))
	var myth_n := int(args.get("myth", "1"))
	var cand := str(args.get("cand", "all"))
	var pool: Array = DB.by_tier(base_t).filter(func(k): return not DB.is_kiin(k) and not DB.is_foe(k))
	var myth: Array = DB.by_tier(8).filter(func(k): return not DB.is_foe(k))
	var groups := {}
	if cand == "all":
		groups = {"초월": DB.by_tier(6), "기인": DB.C.keys().filter(func(k): return DB.is_kiin(k)), "전설": DB.by_tier(5).filter(func(k): return not DB.is_kiin(k))}
	elif cand == "kiin":
		for k in DB.C.keys().filter(func(k): return DB.is_kiin(k)):
			groups[DB.C[k].name] = [k]
	else:
		for k in DB.by_tier(int(cand)).filter(func(k): return not DB.is_kiin(k) and not DB.is_foe(k)):
			groups[DB.C[k].name] = [k]
	var out := []
	for g in groups:
		var ks: Array = groups[g].filter(func(k): return not DB.is_foe(k))
		var rng := RandomNumberGenerator.new()
		rng.seed = 4242 + base_t * 7 + myth_n
		var w := 0.0
		for i in games:
			var a := []
			for j in myth_n: a.append(myth[rng.randi() % myth.size()])
			while a.size() < 8: a.append(pool[rng.randi() % pool.size()])
			var b := a.duplicate()
			a.append(ks[rng.randi() % ks.size()])
			b.append(pool[rng.randi() % pool.size()])
			var f: String = FORMS[rng.randi() % FORMS.size()]
			var sd := rng.randi()
			var r1 := RtBattle.make(sd).run(DB.auto_place(a, f), f, 100, null, DB.auto_place(b, f), f, 100, null, "", "", [], {"A": "smart", "B": "smart"})
			var r2 := RtBattle.make(sd).run(DB.auto_place(b, f), f, 100, null, DB.auto_place(a, f), f, 100, null, "", "", [], {"A": "smart", "B": "smart"})
			w += (1.0 if r1.win else (0.5 if r1.draw else 0.0)) + (0.0 if r2.win else (0.5 if r2.draw else 1.0))
		out.append([g, w / (2.0 * games)])
	out.sort_custom(func(x, y): return x[1] > y[1])
	var avg := 0.0
	for o in out: avg += o[1]
	print("한 칸의 값 (신화 %d + %s 덱, 후보 %s, %d판 × 2) 평균 %d%%" % [myth_n, DB.TIER[base_t].n, cand, games, roundi(avg / out.size() * 100)])
	for o in out:
		print("  %-12s %3d%%" % [o[0], roundi(o[1] * 100)])
	get_tree().quit()
