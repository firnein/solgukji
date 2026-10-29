extends Node
## 전투 길이 점검 —— 실행: godot --headless --path . res://tests/turns.tscn [-- --games=150 --pace=0.4 --troop=22 --intTroop=12 --morale=0.029]
##
## 같은 등급 무작위 9장끼리, 그리고 한 등급 차이(위 9장 vs 아래 9장)로 싸워 턴 수와 끝난 방식을 센다.
## --troop 등은 DB.K 계수를 이번 실행에서만 바꿔 본다 (데이터는 그대로).
## 정책은 대전과 같게 양쪽 영리(smart).

const FORMS := ["eorin", "hagik", "bongsi", "anwol", "bangwon", "anhaeng", "chuhaeng", "jangsa"]
var games := 150
var pol := "smart"
var mirror := false        # --mirror: 같은 판을 진영만 바꿔 한 번 더 —— A 쪽 승률이 50% 에서 벗어나면 진영 치우침


func _ready() -> void:
	var args := {}
	for s in OS.get_cmdline_user_args():
		var kv := s.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	games = int(args.get("games", "150"))
	if args.has("tmul"):                  # 턴 배율 (Battle.turn_mul) 바꿔 보기
		Battle.auto_turn = false
		Battle.set_turn_mul(float(args.tmul))
	for k in ["troop", "intTroop", "morale", "regen", "hit50", "hit25", "routSlope", "routMin", "routSame", "cap"]:
		if args.has(k):
			DB.K[k] = float(args[k])
	if args.has("pace"):
		Battle.pace = float(args.pace)
	print("턴 배율 %s · pace %s · K: troop %s · intTroop %s · morale %s" % [Battle.turn_mul, Battle.pace, DB.K.troop, DB.K.intTroop, DB.K.morale])
	pol = str(args.get("pol", "smart"))
	mirror = args.has("mirror")
	var t0 := Time.get_ticks_msec()
	print("━━ 같은 등급 (%d판)" % games)
	for t in [3, 4, 5, 6, 7, 8]:
		_run(t, t)
	print("━━ 한 등급 차이 (위 vs 아래)")
	for t in [5, 6, 7, 8]:
		_run(t, t - 1)
	print("소요 %.1f초" % ((Time.get_ticks_msec() - t0) / 1000.0))
	get_tree().quit()


func _run(ta: int, tb: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 500 + ta * 10 + tb
	var hi: Array = DB.by_tier(ta)
	var lo: Array = DB.by_tier(tb)
	var turns := []
	var w := 0.0
	var capped := 0
	var routs := 0
	var deaths := 0
	for i in games:
		var a := []
		var b := []
		for j in 9:
			a.append(hi[rng.randi() % hi.size()])
			b.append(lo[rng.randi() % lo.size()])
		var fa: String = FORMS[rng.randi() % FORMS.size()]
		var fb: String = FORMS[rng.randi() % FORMS.size()]
		var sd := rng.randi() % 100000
		if mirror and i % 2 == 1:
			var tmp := a
			a = b
			b = tmp
			var tf := fa
			fa = fb
			fb = tf
		var r := Battle.new(sd).run(DB.auto_place(a, fa), fa, 100, null, DB.auto_place(b, fb), fb, 100, null,
			"", "", [], {"A": pol, "B": pol})
		turns.append(r.turns)
		w += 1.0 if r.win else (0.5 if r.draw else 0.0)
		if r.turns >= roundi(DB.K.cap * Battle.turn_mul): capped += 1
		for e in r.ev:
			if e.get("fx") == "rout":
				if str(e.t).contains("패주"): routs += 1
				else: deaths += 1
	turns.sort()
	var mean: float = turns.reduce(func(x, y): return x + y) / float(turns.size())
	print("  %s vs %s: 평균 %.1f턴 (중앙 %d · 10%% %d · 90%% %d) · 시간 끝 %d판 · A 승률 %.0f%% · 무너짐 병력 %d / 패주 %d" % [
		DB.TIER[ta].n, DB.TIER[tb].n, mean, turns[turns.size() / 2], turns[turns.size() / 10], turns[turns.size() * 9 / 10],
		capped, w / games * 100, deaths, routs])
