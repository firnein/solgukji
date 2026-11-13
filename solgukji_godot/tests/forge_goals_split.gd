extends Node
## 추천 조합칸 한 줄을 둘로(가장 가까운 · 인연) 나누기 점검 (11/13 사용자) —— 실행: godot --headless --path . res://tests/forge_goals_split.tscn
## Run.myth_item_goals: 신화 아이템(유니크)을 가졌을 때만 그 신화 장수 (왼쪽 「가장 가까운」 맨 앞에 끼어든다)
## 「인연」 Run.bond_goals: ① 신화 아이템 길은 넣지 않는다 ② 가진 장수와 겹치는 수가 많은 순, 겹침 0 은 빼고 ③ 왼쪽 인물(exclude)은 빠진다 ④ 인물 중복 없음
##   ⑤ 가진 장수가 없으면(1일차처럼 아무와도 안 겹치면) 빈 목록

var fails := []


func _fail(s: String) -> void:
	fails.append(s)
	printerr("FAIL ", s)


func _card_of(p: String) -> String:
	var best := ""
	for k in DB.C:
		if DB.person(k) == p and not DB.is_foe(k) and (best == "" or DB.C[k].tier < DB.C[best].tier):
			best = k
	return best


func _ready() -> void:
	var r := Run.new()
	r.new_game(31)
	r.inv = {}
	r.board = []
	r.board.resize(9)
	r.bag = {}
	# 인연 하나의 장수 셋을 손패에
	var nm: String = DB.INYEON.keys()[0]
	var members: Array = DB.INYEON[nm]
	for p in members.slice(0, 3):
		var k := _card_of(p)
		if k != "":
			r.inv[k] = 1
	var owned := r.owned_persons()
	var g := r.bond_goals({}, 4)
	print("인연 「%s」 · 추천: %s" % [nm, str(g.map(func(o): return "%s(%d)" % [o, Run.bond_links(o, owned)]))])
	if g.is_empty():
		_fail("인연 장수 셋을 가졌는데 둘째 칸 추천이 비었다")
	var last := 1 << 30
	var seen := {}
	for o in g:
		var n: int = Run.bond_links(o, owned)
		if n <= 0:
			_fail("가진 장수와 겹치는 인연이 없는 %s 가 추천됐다" % o)
		if n > last:
			_fail("인연 많은 순이 아니다: %s" % str(g))
		last = n
		if seen.has(DB.person(o)):
			_fail("인물 중복 %s" % o)
		seen[DB.person(o)] = true
	if not g.is_empty():
		var ex := {DB.person(g[0]): true}
		if r.bond_goals(ex, 4).any(func(o): return DB.person(o) == DB.person(g[0])):
			_fail("첫 칸 인물을 빼지 않았다")
	# 신화 아이템 길
	var myth := ""
	for k in DB.by_tier(8):
		if Run.need_item(k) != null and DB.RECOF.has(k) and not DB.is_foe(k):
			myth = k
			break
	if myth == "":
		_fail("신화 아이템이 있는 신화 장수를 못 찾았다")
	else:
		if not r.myth_item_goals().is_empty():
			_fail("신화 아이템이 없는데 「신화」 칸이 찼다")
		r.bag[Run.need_item(myth)] = 1
		var m := r.myth_item_goals()
		print("신화 아이템 %s → 신화 칸: %s" % [DB.IT[Run.need_item(myth)].name, str(m)])
		if not m.has(myth):
			_fail("신화 아이템을 가졌는데 「신화」 칸에 %s 가 없다: %s" % [myth, str(m)])
		if r.bond_goals({}, 4).has(myth):
			_fail("「인연」 칸에 신화 아이템 길이 섞였다")
	# 가진 장수가 없으면 빈 목록 (먼 목표로 채우지 않는다)
	var r0 := Run.new()
	r0.new_game(31)
	r0.inv = {}
	r0.board = []
	r0.board.resize(9)
	r0.bag = {}
	if not r0.bond_goals({}, 4).is_empty():
		_fail("가진 장수가 없는데 인연 추천이 찼다: %s" % str(r0.bond_goals({}, 4)))
	print("FAIL: ", fails if not fails.is_empty() else "없음")
	get_tree().quit(1 if not fails.is_empty() else 0)
