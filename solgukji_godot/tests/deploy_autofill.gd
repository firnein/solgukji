extends Node
## 빈 편성 채우기 점검 (11/27) —— 실행: godot --headless --path . res://tests/deploy_autofill.tscn
##  1) 사람이 놓은 칸은 그대로  2) 빈 칸이 강한 순(등급 → 병력)으로 채워진다  3) 남는 손패는 가장 약한 것들
##  4) 같은 인물은 한 부대만  5) 판이 꽉 찼거나 비었으면 아무것도 안 한다  6) 대행(bot_prepare(false))도 채운다

var fails := 0


func _ok(cond: bool, what: String) -> void:
	print(("  통과: " if cond else "  실패: "), what)
	if not cond:
		fails += 1


## 등급 t 에서 인물이 겹치지 않게 n 장 (used 에 인물을 적는다)
func _cards(t: int, n: int, used: Dictionary) -> Array:
	var out := []
	for k in DB.by_tier(t):
		if out.size() >= n:
			break
		if DB.is_foe(k) or used.has(DB.person(k)):
			continue
		used[DB.person(k)] = true
		out.append(k)
	return out


func _ready() -> void:
	var r := Run.new()
	r.new_game(7, false)
	var used := {}
	var weak := _cards(1, 6, used)
	var mid := _cards(3, 4, used)
	var strong := _cards(5, 3, used)
	var all: Array = weak + mid + strong
	for k in all:
		r.give(k)
	# 사람이 약한 카드 둘을 놓았다
	r.place(4, weak[0])
	r.place(8, weak[1])
	var n := r.fill_empty()
	_ok(r.board[4] == weak[0] and r.board[8] == weak[1], "사람이 놓은 칸 그대로 (%s · %s)" % [r.board[4], r.board[8]])
	_ok(n == 7 and r.placed() == 9, "빈 칸 7 채움 (채움 %d · 판 %d)" % [n, r.placed()])
	for k in strong + mid:
		_ok(r.board.has(k), "강한 카드 편성됨 %s (등급 %d)" % [k, DB.C[k].tier])
	var left := []
	for k in r.inv:
		for i in int(r.inv[k]):
			left.append(k)
	_ok(not left.is_empty() and left.all(func(k): return DB.C[k].tier == 1), "남은 손패는 모두 1등급 (시작 손패 포함 %d장)" % left.size())
	var on := r.board.filter(func(k): return k != null and not k in [weak[0], weak[1]])
	var worst_on := 99
	for k in on:
		worst_on = mini(worst_on, DB.C[k].tier)
	_ok(on.size() == 7 and left.all(func(k): return not Run.stronger(k, on.reduce(func(a, b): return b if Run.stronger(a, b) else a))), "채운 카드가 남은 카드보다 모두 강하다")
	# 꽉 찬 판 —— 아무것도 안 한다
	var before := r.board.duplicate()
	_ok(r.fill_empty() == 0 and r.board == before, "꽉 찬 판은 그대로")
	# 빈 판 —— fill_empty 는 하지 않는다 (auto_deploy 몫)
	var r2 := Run.new()
	r2.new_game(8, false)
	for k in all:
		r2.give(k)
	_ok(r2.fill_empty() == 0 and r2.placed() == 0, "빈 판은 fill_empty 가 손대지 않는다")
	# 같은 인물 —— 이미 앉은 인물의 다른 카드는 고르지 않는다
	var r3 := Run.new()
	r3.new_game(9, false)
	var dupk := ""
	var dupk2 := ""
	for a in DB.C:
		if DB.C[a].tier < 3 or DB.is_foe(a):
			continue
		for b in DB.C:
			if b != a and DB.C[b].tier > DB.C[a].tier and DB.person(b) == DB.person(a) and not DB.is_foe(b):
				dupk = a
				dupk2 = b
				break
		if dupk != "":
			break
	if dupk != "":
		r3.give(dupk)
		r3.give(dupk2)
		r3.give(weak[2])
		r3.place(0, dupk)
		r3.fill_empty()
		_ok(not r3.board.has(dupk2) and r3.board.has(weak[2]), "같은 인물(%s)의 더 센 카드 %s 는 넣지 않는다" % [DB.person(dupk), dupk2])
	else:
		print("  (같은 인물 두 등급 카드 없음 —— 건너뜀)")
	# 대행 —— 행동은 했지만 못 끝낸 사람 (bot_prepare(false))
	var r4 := Run.new()
	r4.new_game(10, false)
	for k in all:
		r4.give(k)
	r4.place(0, weak[0])
	r4.drawn = true
	r4.picked = true
	r4.granted = true
	r4.bot_prepare(false)
	_ok(r4.board[0] == weak[0] and r4.placed() == 9, "대행(bot_prepare(false))도 빈 칸을 채운다 (판 %d)" % r4.placed())
	print("빈 편성 채우기 점검 —— 실패 %d" % fails)
	get_tree().quit(1 if fails > 0 else 0)
