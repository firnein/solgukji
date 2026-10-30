extends Node
## 결정성 점검 —— 실행: godot --headless --path . res://tests/determinism.tscn
##  1) 같은 시드 + 같은 입력이면 사건 기록이 완전히 같다
##  2) 입력을 넣으면 그 행동 번호 앞까지는 입력이 없을 때와 똑같다 (화면이 다시 계산해도 지난 장면이 바뀌지 않는다)
##  3) 적용된 입력 기록(applied)만으로 다시 돌리면 같은 결과가 나온다 (리플레이·서버 검증)

var fails := 0


func _ready() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	var cases := 0
	for i in 30:
		var t: int = [6, 7, 8][i % 3]
		var a := _deck(t, rng)
		var b := _deck(t, rng)
		var seed := rng.randi() % 100000
		var pol := {"A": "manual", "B": "smart"}
		var r0 := _run(a, b, seed, [], pol)
		var r0b := _run(a, b, seed, [], pol)
		_same("같은 입력 두 번", r0.ev, r0b.ev, r0.ev.size())
		# 중간쯤 행동에 군령과 고유기를 넣는다
		var last_an: int = r0.ev[r0.ev.size() - 1].an
		var k := maxi(1, last_an / 3)
		var ult_key := ""
		for row in r0.roster:
			if row.camp == "A" and row.tier >= 6:
				ult_key = row.key
		var inp := [[k, "A", "cmd", "돌격"], [k + 2, "A", "ult", ult_key]]
		var r1 := _run(a, b, seed, inp, pol)
		var prefix := 0
		while prefix < r0.ev.size() and r0.ev[prefix].an < k:
			prefix += 1
		_same("입력 앞부분", r0.ev, r1.ev, prefix)
		var r2 := _run(a, b, seed, r1.applied, pol)
		_same("적용 기록으로 재생", r1.ev, r2.ev, r1.ev.size())
		cases += 1
	print("결정성 점검 %d판 · 실패 %d" % [cases, fails])
	get_tree().quit()


func _deck(t: int, rng: RandomNumberGenerator) -> Array:
	var pool: Array = DB.by_tier(t)
	var d := []
	for i in 9:
		d.append(pool[rng.randi() % pool.size()])
	return d


func _run(a: Array, b: Array, seed: int, inp: Array, pol: Dictionary) -> Dictionary:
	return Battle.new(seed).run(DB.auto_place(a, "eorin"), "eorin", 100, null,
		DB.auto_place(b, "hagik"), "hagik", 100, null, "", "", inp.duplicate(true), pol)


func _same(what: String, x: Array, y: Array, n: int) -> void:
	if x.size() < n or y.size() < n:
		fails += 1
		print("  실패(%s): 길이 %d / %d < %d" % [what, x.size(), y.size(), n])
		return
	for i in n:
		if x[i].t != y[i].t or str(x[i].s) != str(y[i].s):
			fails += 1
			print("  실패(%s): %d번째 사건이 다르다 —— %s / %s" % [what, i, x[i].t, y[i].t])
			return
