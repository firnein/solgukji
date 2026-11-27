extends Node
## 11/27 사용자 "군략은 제거, 연구는 유지" 점검 —— 실행: godot --headless --path . res://tests/no_tactics.tscn
##  1) 스위치: Run.tac_on 이 꺼져 있다
##  2) 혼자 하기 아침 흐름: 하루가 끝날 때마다 군략 3택1 은 없고 연구 3택1(3장, 연구만)이 나온다. 군략 명령(pick_tac · set_plan · reroll_tac)은 거절
##  3) 군략에만 의미가 있는 연구(Tac.tac_only —— 군략 연구)는 후보에 오르지 않는다 (켜면 오른다 —— 거르는 것이 스위치임을 확인)
##  4) 전투: 짐은 연구 영구 부품뿐(계획 · 늘 카드 없음) · 토벌 우두머리 · 봇 계획 없음 · 결과 사건에 군략 단계(fx "tac") 없음
##  5) 연구 효과는 걸린다: 영구 부품(공격 +) 이 같은 시드에서 피해를 늘린다 · 사기 진작이 시작 사기를 올린다 · 고른 연구가 짐에 실린다
##  6) 옛 저장(군략 3택1 · 계획 · 손패가 남은 것)을 불러도 터지지 않고 군략 3택1 은 버려진다
##  7) 온라인 방: 대전 준비(evening_prep, 군략만 고치는 단계)를 건너뛰고 막힘 없이 날이 넘어간다 · 방 정보에 군략(plan · tk) 없음 · 연구 3택1 이 서버 명령으로 된다

const Tac := preload("res://scripts/tactics.gd")

var fails := 0


class FakeSrv:
	var out := []
	func send(peer: int, msg: Dictionary) -> void:
		out.append([peer, msg.duplicate(true)])


func _ready() -> void:
	Tac.data()
	_ok(not Run.tac_on, "군략 스위치(Run.tac_on)가 꺼져 있다")
	_solo_flow()
	_offer_filter()
	_battle()
	_effects()
	_old_save()
	_room()
	print("군략 꺼짐 점검 —— 실패 %d" % fails)
	get_tree().quit(1 if fails > 0 else 0)


func _ok(cond: bool, what: String) -> void:
	if not cond:
		fails += 1
		print("  실패: ", what)


func _end_day(r: Run) -> void:
	var d0 := r.day
	var guard := 0
	while r.day == d0 and r.over == null and guard < 6:
		guard += 1
		r.quest_done = true
		r.pvp_done = true
		r.advance()


## 2) 혼자 하기 아침 흐름
func _solo_flow() -> void:
	var r := Run.new()
	r.new_game(42)
	var picked := 0
	for d in 5:
		_end_day(r)
		if r.over != null:
			break
		_ok(r.tk_offer.is_empty(), "%d일차 아침: 군략 3택1 이 없다 (%s)" % [r.day + 1, str(r.tk_offer)])
		_ok(r.rs_offer.size() == 3, "%d일차 아침: 연구 3택1 3장 (%d장)" % [r.day + 1, r.rs_offer.size()])
		_ok(r.rs_offer.all(func(id): return Tac.is_res(str(id)) and not Tac.tac_only(str(id))), "%d일차 연구 3택1 은 연구만 · 군략 전용 없음 %s" % [r.day + 1, str(r.rs_offer)])
		_ok(r.command("pick_tac", ["돌격"]) != true, "군략 3택1 고르기 명령은 거절")
		_ok(not r.set_plan(0, "돌격"), "단계 계획 놓기는 거절")
		_ok(r.command("reroll_tac", []) != true, "군략 다시 굴리기는 거절")
		if d % 2 == 0 and not r.rs_offer.is_empty():      # 홀수 날은 안 고르고 넘긴다 —— 하루 끝에 첫 연구가 자동으로 정해진다
			var id := str(r.rs_offer[0])
			_ok(r.command("pick_res", [id]) == true and r.rs_offer.is_empty(), "연구 고르기 (명령) %s" % id)
			picked += 1
	var n := 0
	for k in r.rs_done:
		n += int(r.rs_done[k])
	_ok(n >= picked + 1, "연구 횟수가 쌓인다 (고름 %d · 자동 포함 %d)" % [picked, n])
	_ok(r.tk_hist.is_empty(), "대전 계획 기록 없음")


## 3) 군략 전용 연구는 후보에서 빠진다 —— 켜면 오른다
func _offer_filter() -> void:
	var only := Tac.ECON.keys().filter(func(id): return Tac.tac_only(str(id)))
	_ok(only == ["군략 연구"], "군략 전용 연구 목록 %s" % str(only))
	var board := ["spear", "horse", "bow", null, null, null, null, null, null]
	var seen_off := false
	var seen_on := false
	for s in 300:
		var g := RandomNumberGenerator.new()
		g.seed = s
		for id in Tac.res_offer(board, {}, 3, g):
			if Tac.tac_only(str(id)):
				seen_off = true
		Run.tac_on = true
		g.seed = s
		for id in Tac.res_offer(board, {}, 3, g):
			if Tac.tac_only(str(id)):
				seen_on = true
		Run.tac_on = false
	_ok(not seen_off, "꺼짐: 군략 연구가 후보에 오르지 않는다")
	_ok(seen_on, "켜짐 대조: 군략 연구가 후보에 오른다 (거르는 것이 스위치)")


## 4) 전투 —— 짐 · 우두머리 · 결과
func _battle() -> void:
	var r := Run.new()
	r.new_game(7)
	r.rs_offer = ["명마"]
	_ok(r.pick_res("명마"), "연구 명마")
	r.rs_offer = ["사기 진작"]
	_ok(r.pick_res("사기 진작"), "연구 사기 진작")
	var ld := r.tac_load()
	_ok(ld.get("p") == ["", "", ""] and (ld.get("own", []) as Array).is_empty(), "짐에 계획 · 늘 카드 없음 %s" % str(ld))
	var parts: Array = ld.get("perm", [])
	_ok(parts.size() == 1 and str(parts[0].k) == "spd" and parts[0].get("who") == ["기병"], "짐에 연구 영구 부품 (명마) %s" % str(parts))
	_ok(r.my_morale() == 110, "사기 진작 —— 시작 사기 110 (%d)" % r.my_morale())
	r.auto_deploy()
	var q := r.start_quest()
	if q is Dictionary and not q.is_empty():
		_ok((q.b.get("plan", {}) as Dictionary).is_empty(), "토벌 우두머리 계획 없음")
		var res := Run.simulate(q, [], Run.policy_for(q))
		_ok(res.ev.filter(func(e): return e.get("fx") == "tac").is_empty(), "토벌 결과에 군략 단계 사건 없음")
		if res.get("tac") is Dictionary:
			for en in res.tac.get("log", []):
				_ok(str(en.A.id) == "" and str(en.B.id) == "", "토벌 단계 기록에 카드 없음")
		r.finish_battle(res)
	else:
		_ok(false, "토벌을 열지 못했다")
	var pv := r.start_pvp()
	if pv is Dictionary and not pv.is_empty():
		var bp: Dictionary = pv.b.get("plan", {})
		_ok(Tac.empty_load(bp), "봇 상대 계획 없음 %s" % str(bp))
		var res2 := Run.simulate(pv, [], Run.policy_for(pv))
		_ok(res2.ev.filter(func(e): return e.get("fx") == "tac").is_empty(), "대전 결과에 군략 단계 사건 없음")
		r.finish_battle(res2)
		_ok(r.tk_hist.is_empty(), "대전 뒤 계획 기록 없음")
	# 연구가 없는 판은 군략 처리 자체가 켜지지 않는다 (예전 전투와 같다)
	var r0 := Run.new()
	r0.new_game(9)
	_ok(Tac.empty_load(r0.tac_load()), "연구 없는 짐은 비었다")
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var a := _deck(6, rng)
	var b := _deck(6, rng)
	var e0 := _run(a, b, 77, {"A": r0.tac_load(), "B": {}})
	_ok(not e0.has("tac"), "연구 없는 전투는 군략 처리 없음")


## 5) 연구 효과가 실제로 걸린다 —— 같은 시드에서 영구 공격 + 가 처음 10초 피해를 늘린다
func _effects() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 23
	var more := 0
	for i in 5:
		var a := _deck(6, rng)
		var b := _deck(6, rng)
		var sd := rng.randi() % 100000
		var base := {"p": ["", "", ""], "own": [], "perm": [{"k": "def", "v": 0.0001, "who": ["없는병종"]}]}
		var up := {"p": ["", "", ""], "own": [], "perm": [{"k": "atk", "v": 0.4}]}
		var r0 := _run(a, b, sd, {"A": base, "B": {}})
		var r1 := _run(a, b, sd, {"A": up, "B": {}})
		_ok(r1.ev.filter(func(e): return e.get("fx") == "tac").is_empty(), "영구 부품만 있는 전투에 단계 사건 없음")
		if _dealt(r1, 10.0) > _dealt(r0, 10.0):
			more += 1
	_ok(more >= 4, "연구 영구 공격 + 가 피해를 늘린다 (%d/5)" % more)


## 6) 옛 저장 —— 군략 3택1 · 계획 · 손패 · 지난 대전이 남아 있어도
func _old_save() -> void:
	var r := Run.new()
	r.new_game(5)
	var d := r.to_dict()
	d["tk_offer"] = ["화공", "돌격 나팔", "연환계"]
	d["tk_plan"] = ["총공격", "화공", "방진"]
	d["tk_hand"] = {"돌격": 2, "화공": 1, "없는카드": 1}
	d["tk_hist"] = [["돌격", "방진", "우회"]]
	d["rs_offer"] = ["명마", "강궁", "철갑"]
	var r2 := Run.new()
	r2.from_dict(JSON.parse_string(JSON.stringify(d)))
	_ok(r2.tk_offer.is_empty(), "옛 저장의 군략 3택1 은 버린다")
	_ok(r2.rs_offer == ["명마", "강궁", "철갑"], "옛 저장의 연구 3택1 은 그대로")
	var ld := r2.tac_load()
	_ok(ld.get("p") == ["", "", ""] and (ld.get("own", []) as Array).is_empty(), "옛 저장 계획은 전투에 안 간다")
	_ok(r2.pick_res("강궁") and int(r2.rs_done.get("강궁", 0)) == 1, "옛 저장에서 연구 고르기")


## 7) 온라인 방 —— 대전 준비 없이 날이 넘어간다
func _room() -> void:
	_ok(Room.stage_len("fast", "evening_prep", 0) == 0.0 and Room.stage_len("normal", "evening_prep", 5) == 0.0, "대전 준비 길이 0")
	var srv := FakeSrv.new()
	var r := Room.new(srv, "NOTC", "test")
	r.rng.seed = 20261127
	for k in 2:
		r.add_human(k + 1, "시험%d" % k, "tk%d" % k)
	r.start()
	var stages := {}
	var guard := 0
	var res_picks := 0
	var seen_no := -1
	while r.stage != "over" and r.day < 4 and guard < 400:
		guard += 1
		stages[r.stage] = int(stages.get(r.stage, 0)) + 1
		var inf: Dictionary = r.info(0)
		_ok(not bool(inf.get("prep", false)), "방 정보 prep 꺼짐")
		for row in inf.seats:
			if row.has("plan") or row.has("tk"):
				_ok(false, "방 정보 자리 줄에 군략(plan · tk)이 있다 %s" % str(row.keys()))
				break
		if r.stage == "morning" and r.stage_no != seen_no:
			seen_no = r.stage_no
			for s in r.humans():
				var rr: Run = s.run
				if s.dead or rr == null:
					continue
				_ok(rr.tk_offer.is_empty(), "%d일차 %s: 서버 Run 에 군략 3택1 없음" % [r.day + 1, s.name])
				if not rr.rs_offer.is_empty():
					var id := str(rr.rs_offer[0])
					r.on_cmd(s.peer, "pick_res", [id])
					_ok(rr.rs_offer.is_empty() and int(rr.rs_done.get(id, 0)) >= 1, "%d일차 %s: 서버 명령으로 연구 %s" % [r.day + 1, s.name, id])
					res_picks += 1
		for s in r.humans():
			if s.peer >= 0 and r.stage in Room.ACT_STAGES and not s.dead:
				r.on_cmd(s.peer, "begin_picks", ["phase", -1])
				r.on_cmd(s.peer, "auto_deploy", [])
			s.ready = true
		r.stage_end = 0.0
		r.tick()
	_ok(guard < 400, "방이 멈추지 않고 진행 (%d번)" % guard)
	_ok(r.day >= 4 or r.stage == "over", "4일차까지 넘어감 (day %d · %s)" % [r.day, r.stage])
	_ok(not stages.has("evening_prep"), "대전 준비 단계를 건너뛴다 %s" % str(stages))
	_ok(stages.has("evening"), "대전 단계는 있다 %s" % str(stages))
	_ok(res_picks >= 4, "온라인 연구 3택1 을 아침마다 (%d번)" % res_picks)
	for m in srv.out:
		if str(m[1].get("t", "")) == "error":
			_ok(false, "서버 오류 메시지 %s" % str(m[1]))
			break


func _deck(t: int, rng: RandomNumberGenerator) -> Array:
	var pool: Array = DB.by_tier(t)
	var d := []
	for i in 9:
		d.append(pool[rng.randi() % pool.size()])
	return d


func _run(a: Array, b: Array, sd: int, tp: Dictionary) -> Dictionary:
	return RtBattle.make(sd).run(DB.auto_place(a, "eorin"), "eorin", 100, null,
		DB.auto_place(b, "hagik"), "hagik", 100, null, "", "", [], {"A": "smart", "B": "smart", "plan": tp})


func _dealt(r: Dictionary, until: float) -> float:
	var n := 0.0
	for e in r.ev:
		if float(e.get("tm", 0.0)) > until:
			break
		if (e.get("fx") == "phys" or e.get("fx") == "int") and str(e.get("a", "")).begins_with("A"):
			n += float(e.get("n", 0.0))
	return n
