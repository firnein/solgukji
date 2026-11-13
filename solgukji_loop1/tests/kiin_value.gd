extends Node
## 기인 값어치 —— 실행: godot --headless --path . res://tests/kiin_value.tscn [-- --games=20 --base=5]
## 같은 무작위 base 등급 8장에 기인 1장을 넣은 덱 대 그 자리에 base 등급 무작위 1장을 넣은 덱. 자리를 바꿔 두 번.
## 기인은 능력치가 전설 ×0.85 라 기능이 없으면 40% 안팎 —— 50~60% 면 한 자리 값을 한다
const FORMS := ["eorin", "hagik", "bongsi", "anwol", "bangwon", "anhaeng", "chuhaeng", "jangsa"]

func _ready() -> void:
	var args := {}
	for s in OS.get_cmdline_user_args():
		var kv := s.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	var games := int(args.get("games", "20"))
	var base_t := int(args.get("base", "5"))
	var pool: Array = DB.by_tier(base_t).filter(func(k): return not DB.is_kiin(k))
	var ks: Array = DB.C.keys().filter(func(k): return DB.is_kiin(k))
	ks.sort()
	var out := []
	for k in ks:
		var rng := RandomNumberGenerator.new()
		rng.seed = 4242
		var w := 0.0
		for g in games:
			var a := []
			for i in 8: a.append(pool[rng.randi() % pool.size()])
			var b := a.duplicate()
			a.append(k)
			b.append(pool[rng.randi() % pool.size()])
			var f: String = FORMS[rng.randi() % FORMS.size()]
			var sd := rng.randi()
			var r1 := RtBattle.make(sd).run(DB.auto_place(a, f), f, 100, null, DB.auto_place(b, f), f, 100, null, "", "", [], {"A": "smart", "B": "smart"})
			var r2 := RtBattle.make(sd).run(DB.auto_place(b, f), f, 100, null, DB.auto_place(a, f), f, 100, null, "", "", [], {"A": "smart", "B": "smart"})
			w += (1.0 if r1.win else (0.5 if r1.draw else 0.0)) + (0.0 if r2.win else (0.5 if r2.draw else 1.0))
		out.append([DB.C[k].name, w / (2.0 * games)])
	out.sort_custom(func(x, y): return x[1] > y[1])
	print("기인 값어치 (등급 %d 덱 · %d판 × 2)" % [base_t, games])
	for o in out:
		print("  %-10s %3d%%" % [o[0], roundi(o[1] * 100)])
	get_tree().quit()
