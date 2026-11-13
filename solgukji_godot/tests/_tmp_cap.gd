extends Node
## 임시 점검 —— 턴 상한 · 등급 차이 승률 (끝나면 지운다)

var rng := RandomNumberGenerator.new()


func _ready() -> void:
	rng.seed = 991
	var cap := roundi(DB.K.cap * Battle.turn_mul)
	print("K.cap %s · turn_mul %s → 턴 상한 %d" % [DB.K.cap, Battle.turn_mul, cap])
	print("━━ 신화 vs 신화 4판 (상한 넘김 확인)")
	var hi: Array = DB.by_tier(8)
	for i in 4:
		var a := _deck(hi)
		var b := _deck(hi)
		var r := RtBattle.new(rng.randi() % 100000).run(DB.auto_place(a, "eorin"), "eorin", 100, null,
			DB.auto_place(b, "eorin"), "eorin", 100, null, "", "", [], {"A": "smart", "B": "smart"})
		print("  %d: turns %d · len %.1f초 · win %s · draw %s" % [i + 1, r.turns, r.get("len", 0.0), r.win, r.draw])
	print("━━ 한 등급 차이 (위 등급 9장 vs 아래 등급 9장, mirror 없음, 20판씩)")
	for pair in [[5, 4], [6, 5], [7, 6], [8, 7]]:
		var up: Array = DB.by_tier(pair[0])
		var lo: Array = DB.by_tier(pair[1])
		var w := 0
		var capn := 0
		for i in 20:
			var a := _deck(up)
			var b := _deck(lo)
			var r := RtBattle.new(rng.randi() % 100000).run(DB.auto_place(a, "eorin"), "eorin", 100, null,
				DB.auto_place(b, "eorin"), "eorin", 100, null, "", "", [], {"A": "smart", "B": "smart"})
			if r.win: w += 1
			if r.turns >= cap: capn += 1
		print("  %s vs %s: 위 등급 승률 %d%% · 시간 끝 %d/20" % [DB.TIER[pair[0]].n, DB.TIER[pair[1]].n, w * 5, capn])
	get_tree().quit()


func _deck(pool: Array) -> Array:
	var a := []
	for j in 9:
		a.append(pool[rng.randi() % pool.size()])
	return a
