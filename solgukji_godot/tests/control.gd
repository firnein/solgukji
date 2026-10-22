extends Node
## 조작 효과 점검 —— 실행: godot --headless --path . res://tests/control.tscn [-- --games=150]
## 같은 두 덱을 자리를 바꿔 두 번 붙여 덱·진영 차이를 지우고 정책 차이만 본다.
##   영리 vs 자동 : 잘 조작하는 사람 ≈ 영리한 AI. 목표는 +5~10%p
##   방치 vs 자동 : 아무것도 안 누르는 사람 (고유기·군령 없음)
## 덤으로 한 판에 고유기·군령이 몇 번 쓰였는지 센다.

const FORMS := ["eorin", "hagik", "bongsi", "anwol", "bangwon", "anhaeng", "chuhaeng", "jangsa"]
var games := 150


func _ready() -> void:
	var args := {}
	for s in OS.get_cmdline_user_args():
		var kv := s.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	games = int(args.get("games", "150"))
	for t in [5, 6, 7, 8]:
		var smart := _duel(t, "smart", "auto")
		var idle := _duel(t, "manual", "auto")
		print("%s: 영리 vs 자동 %+.1f%%p (고유기 %.1f · 군령 %.1f /판) · 방치 vs 자동 %+.1f%%p" % [
			DB.TIER[t].n, (smart.w - 0.5) * 100, smart.ult, smart.cmd, (idle.w - 0.5) * 100])
	get_tree().quit()


func _duel(t: int, p1: String, p2: String) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7000 + t
	var pool: Array = DB.by_tier(t)
	var w := 0.0
	var ult := 0
	var cmd := 0
	var share := 0.0
	var blk := 0
	var uh := 0
	for g in games:
		var x := []
		var y := []
		for i in 9:
			x.append(pool[rng.randi() % pool.size()])
			y.append(pool[rng.randi() % pool.size()])
		var fx: String = FORMS[rng.randi() % FORMS.size()]
		var fy: String = FORMS[rng.randi() % FORMS.size()]
		var seed := rng.randi() % 1000000
		# 1판: x 가 p1(A) · 2판: x 가 p1(B)
		var r1 := Battle.new(seed).run(DB.auto_place(x, fx), fx, 100, null, DB.auto_place(y, fy), fy, 100, null, "", "", [], {"A": p1, "B": p2})
		var r2 := Battle.new(seed).run(DB.auto_place(y, fy), fy, 100, null, DB.auto_place(x, fx), fx, 100, null, "", "", [], {"A": p2, "B": p1})
		w += (1.0 if r1.win else (0.5 if r1.draw else 0.0))
		w += (1.0 if (not r2.win and not r2.draw) else (0.5 if r2.draw else 0.0))
		share += (r1.stats.ult_dmg / maxf(1, r1.stats.dmg) + r2.stats.ult_dmg / maxf(1, r2.stats.dmg)) / 2
		blk += r1.stats.blocked + r2.stats.blocked
		uh += r1.stats.ult_hits + r2.stats.ult_hits
		for r in [r1, r2]:
			for e in r.ev:
				if e.get("fx") == "ult" and _camp_of(r, e.a) == ("A" if r == r1 else "B"):
					ult += 1
				if e.get("fx") == "cmd" and e.camp == ("A" if r == r1 else "B"):
					cmd += 1
	print("    [%s vs %s] 고유기 피해 비중 %.0f%% · 고유기 타격 중 방진에 막힌 비율 %.0f%%" % [p1, p2, share / games * 100, 100.0 * blk / maxi(1, uh)])
	return {"w": w / (games * 2), "ult": float(ult) / (games * 2), "cmd": float(cmd) / (games * 2)}


func _camp_of(r: Dictionary, key: String) -> String:
	return key.substr(0, 1)
