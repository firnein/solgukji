extends Node
## 11/19 "속도 100 = 초당 1번 공격" 실험 —— 등급별 같은 덱 묶음으로 지금 식과 새 식의 전투 길이 · 고유기 횟수를 견준다
## godot --headless --path . res://tests/spd_rule.tscn -- --n=20

func _ready() -> void:
	var n := 20
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--n="):
			n = int(arg.substr(4))
	for t in [3, 4, 5, 6, 7, 8]:
		var row := []
		for rule in [false, true]:
			RtBattle.spd_rule = rule
			var rng := RandomNumberGenerator.new()
			rng.seed = 7700 + t
			var ln := 0.0
			var ults := 0
			var draws := 0
			for g in n:
				var pool: Array = DB.by_tier(t)
				var a := []
				var b := []
				for i in 9:
					a.append(pool[rng.randi() % pool.size()])
					b.append(pool[rng.randi() % pool.size()])
				var r: Dictionary = RtBattle.new(9000 + g).run(DB.auto_place(a, "eorin"), "eorin", 100, null, DB.auto_place(b, "hagik"), "hagik", 100, null, "", "", [], {"A": "auto", "B": "auto"})
				ln += float(r.len)
				draws += 1 if bool(r.get("draw", false)) else 0
				for e in r.ev:
					if e.get("fx") == "ult":
						ults += 1
			row.append("%s 길이 %.1f초 · 고유기 %.1f회 · 무승부 %d" % ["새 식" if rule else "지금", ln / n, float(ults) / n, draws])
		print("등급 %d | %s | %s" % [t, row[0], row[1]])
	RtBattle.spd_rule = false
	get_tree().quit()
