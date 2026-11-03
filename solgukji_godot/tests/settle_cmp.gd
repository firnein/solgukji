extends Node
## 정산 간격 비교 —— 실행: godot --headless --path . res://tests/settle_cmp.tscn [-- --games=30]
## 같은 시드 · 같은 덱을 RtBattle.SETTLE 0.2초(나눠 정산)와 999(턴 끝에만 —— 예전)로 돌려 승패 · 길이 · 패주 수를 비교한다
const FORMS := ["eorin", "hagik", "bongsi", "anwol", "bangwon", "anhaeng", "chuhaeng", "jangsa"]

func _ready() -> void:
	var args := {}
	for s in OS.get_cmdline_user_args():
		var kv := s.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	var games := int(args.get("games", "30"))
	print("등급   A승(예전→0.2)  같은 결과  길이(초)        남은 병력 차")
	for t in [3, 4, 5, 6, 7, 8]:
		var pool: Array = DB.by_tier(t)
		var res := {}
		for st in [999.0, 0.2]:
			RtBattle.SETTLE = st
			var rng := RandomNumberGenerator.new()
			rng.seed = 900 + t
			var out := []
			for g in games:
				var a := []
				var b := []
				for i in 9:
					a.append(pool[rng.randi() % pool.size()])
					b.append(pool[rng.randi() % pool.size()])
				var fa: String = FORMS[rng.randi() % FORMS.size()]
				var fb: String = FORMS[rng.randi() % FORMS.size()]
				var r := RtBattle.make(rng.randi()).run(DB.auto_place(a, fa), fa, 100, null, DB.auto_place(b, fb), fb, 100, null, "", "", [], {"A": "smart", "B": "smart"})
				out.append([r.win, float(r.len), r.left - r.eLeft])
			res[st] = out
		var o: Array = res[999.0]
		var n: Array = res[0.2]
		var wo := 0
		var wn := 0
		var same := 0
		var lo := 0.0
		var ln := 0.0
		for i in games:
			wo += 1 if o[i][0] else 0
			wn += 1 if n[i][0] else 0
			same += 1 if o[i][0] == n[i][0] else 0
			lo += o[i][1]
			ln += n[i][1]
		print("%s   %3d%% → %3d%%     %3d%%     %4.1f → %4.1f" % [DB.TIER[t].n, roundi(100.0 * wo / games), roundi(100.0 * wn / games), roundi(100.0 * same / games), lo / games, ln / games])
	get_tree().quit()
