extends Node
## 11/11 온라인 규칙 점검 —— 가짜 서버로 Room 을 직접 돌린다 (포트 없음 · 헤드리스).
## 실행: godot --headless --path . res://tests/wait_rules.tscn
## ① 점심(토벌)은 1~3일차만 (Room.has_noon · 방 정보 noon) ② 기다리지 않는 사람(끊김 · 봇 대행 · 볼 전투 없음)은 서버가 바로 넘긴다
## ③ 기다리는 동안(점심 · 저녁) 징집 · 조합 · 편성 명령을 받는다 — 토너먼트 저녁 · 멸망한 사람은 안 된다. 이미 계산된 전투는 그대로
## ④ 민심: 온라인 대전 패배 ×1.0 (혼자 하기 ×0.6) ⑤ 4일차~ 온라인 대전은 그날 토벌 보상을 얹어 준다 (표를 찍는다)

class FakeSrv:
	var out := []
	func send(peer: int, msg: Dictionary) -> void:
		out.append([peer, msg])
	func of(peer: int, t: String) -> Array:
		return out.filter(func(o): return o[0] == peer and o[1].t == t).map(func(o): return o[1])


var fails := []


func _fail(s: String) -> void:
	if fails.size() < 20:
		fails.append(s)


func _ready() -> void:
	_stages_and_ready()
	_cmd_rules()
	_hp_rules()
	_reward_rules()
	print("FAIL: ", fails if not fails.is_empty() else "없음")
	get_tree().quit(1 if not fails.is_empty() else 0)


func _room(n: int, seed_: int) -> Array:
	var srv := FakeSrv.new()
	var r := Room.new(srv, "WR", "test")      # 점검 모드는 멸망하지 않는다 (민심이 바닥나도 계속) — 타이머는 stage_end 로 직접 넘긴다
	r.rng.seed = seed_
	for i in n:
		r.add_human(i + 1, "사람%d" % (i + 1), "tk%d" % i)
	r.start()
	return [r, srv]


## 아침 · 준비 단계를 누른 것처럼 모두 끝낸다 (행동 한 번 + 준비)
func _ready_all(r: Room) -> void:
	for s in r.humans():
		if s.peer >= 0 and not s.dead:
			s.acted = true
			s.ready = true


func _stages_and_ready() -> void:
	var a := _room(2, 11)
	var r: Room = a[0]
	var srv: FakeSrv = a[1]
	# 1일차 아침 → (모두 준비) → 점심
	_ready_all(r)
	r.tick()
	if r.stage != "noon" or not r.info(0).noon:
		_fail("1일차 아침 뒤가 점심이 아니다 (%s)" % r.stage)
	# 점심: 전투가 있어 아직 준비 아님 → 시간이 남아 있으면 기다린다
	if r.seats.any(func(s): return s.human and s.ready):
		_fail("점심 시작에 이미 준비다")
	r.tick()
	if r.stage != "noon":
		_fail("준비 안 한 사람이 있는데 점심이 넘어갔다")
	# 둘 다 전투를 보고 준비(준비 메시지의 단계 번호가 맞아야 한다) → 시간이 남아도 넘어간다
	r.on_ready(1, true, r.stage_no)
	r.tick()
	if r.stage != "noon":
		_fail("한 명만 준비인데 넘어갔다")
	r.on_ready(2, true, r.stage_no)
	r.tick()
	if r.stage != "evening_prep":
		_fail("모두 준비인데 저녁 준비로 안 갔다 (%s)" % r.stage)
	# 끊긴 사람은 기다리지 않는다 —— 저녁(대전)에서 한 명이 끊겼다
	_ready_all(r)
	r.tick()
	if r.stage != "evening":
		_fail("저녁 준비 뒤가 저녁이 아니다 (%s)" % r.stage)
	r.remove_peer(2)
	r.on_ready(1, true, r.stage_no)
	r.tick()
	if r.stage != "morning":
		_fail("끊긴 사람을 기다리다 저녁이 안 끝났다 (%s)" % r.stage)
	# (a) 끊긴 채로 아침이 끝나면 봇이 대신한다 —— 점심에 돌아와도(auto) 전투를 다 보기를 기다리지 않는다. 지금은 사람2 가 끊겨 있다
	r.seats[0].acted = true
	r.seats[0].ready = true
	r.stage_end = Room.now() + 100.0
	r.tick()
	if r.stage != "noon":
		_fail("끊긴 사람이 있는 아침이 점심으로 안 넘어갔다 (%s)" % r.stage)
	r.reattach(5, "tk1")
	if not bool(r.seats[1].get("auto", false)) or bool(r.seats[0].get("auto", false)):
		_fail("봇 대행 표시 auto 가 틀리다: %s / %s" % [str(r.seats[0].get("auto")), str(r.seats[1].get("auto"))])
	r.stage_end = Room.now() + 100.0
	r.on_ready(1, true, r.stage_no)
	r.tick()
	if r.stage != "evening_prep":
		_fail("봇이 대신한 사람이 돌아와도 점심을 붙잡는다 (%s)" % r.stage)
	# (b) 접속해 있지만 이 아침 내내 아무 행동도 없던 사람 —— 시간이 끝나 봇이 대신하면 이어지는 점심에서 기다리지 않는다
	_ready_all(r)
	r.tick()      # 저녁 준비 → 저녁
	r.on_ready(1, true, r.stage_no)
	r.on_ready(5, true, r.stage_no)      # 사람2 는 5번 연결로 돌아왔다
	r.tick()      # 저녁 → 다음 날 아침 (day 0 · phase 2)
	if r.stage != "morning":
		_fail("저녁이 안 끝났다 (%s)" % r.stage)
	r.seats[0].acted = true
	r.seats[0].ready = true
	r.seats[1].acted = false
	r.seats[1].ready = false
	r.stage_end = 0.0
	r.tick()
	if r.stage != "noon" or not bool(r.seats[1].get("auto", false)):
		_fail("행동 없던 사람이 봇 대행(auto)으로 안 쳐졌다 (%s)" % r.stage)
	r.stage_end = Room.now() + 100.0
	r.on_ready(1, true, r.stage_no)
	r.tick()
	if r.stage != "evening_prep":
		_fail("행동 없던(봇 대행) 사람 때문에 점심이 안 넘어갔다 (%s)" % r.stage)
	# 한 페이즈를 지나 3일차 마지막 페이즈 다음(day 3)부터 점심이 없다
	var guard := 0
	while r.day < 3 and guard < 100:
		guard += 1
		_ready_all(r)
		for s in r.humans():
			s.ready = true
		r.stage_end = 0.0
		r.tick()
	if r.day != 3 or r.stage != "morning" or r.info(0).noon:
		_fail("4일차 아침에 닿지 못했다 (day %d · %s · noon %s)" % [r.day, r.stage, str(r.info(0).get("noon"))])
	# 4일차 아침 → 곧바로 저녁 준비 (점심 없음 · 토벌 전투 없음 · 상대는 정해진다)
	srv.out.clear()
	r.stage_end = 0.0
	r.tick()
	if r.stage != "evening_prep":
		_fail("4일차 아침 뒤가 저녁 준비가 아니다 (%s)" % r.stage)
	if r.seats[0].foe == null or not r.seats[0].battles.is_empty():
		_fail("4일차 저녁 준비 — 상대가 없거나 토벌 전투가 있다 (foe %s · 전투 %d · 멸망 %s · 일차 %d)" % [str(r.seats[0].foe), r.seats[0].battles.size(), str(r.seats[0].dead), r.day])
	if not srv.of(1, "battles").is_empty():
		_fail("4일차에 토벌 battles 가 갔다")
	# 저녁: 전투가 있고, 둘 다 준비해야 넘어간다
	r.stage_end = 0.0
	r.tick()
	if r.stage != "evening":
		_fail("저녁 준비 뒤가 저녁이 아니다")
	if r.seats[0].battles.is_empty():
		_fail("4일차 저녁 전투 없음")
	# 볼 전투가 없는 사람(멸망)은 저녁 시작에 이미 준비로 친다
	var b := _room(2, 12)
	var r2: Room = b[0]
	r2.seats[1].dead = true
	r2.seats[1].run.over = {"win": false, "msg": "시험"}
	_ready_all(r2)
	r2.tick()      # 아침 → 점심 (1일차: 사람1 만 토벌)
	if not r2.seats[1].ready or not r2.seats[1].watched or r2.seats[0].ready:
		_fail("볼 전투가 없는 멸망한 사람이 점심에 자동 준비가 아니다 / 있는 사람은 준비가 아니어야 한다")
	r2.on_ready(1, true, r2.stage_no)
	r2.tick()
	if r2.stage != "evening_prep":
		_fail("멸망한 사람 때문에 점심이 안 끝났다 (%s)" % r2.stage)
	print("단계 · 준비 점검 끝 — 점심은 1~3일차만, 끊김 · 자리 비움 · 볼 전투 없음은 기다리지 않는다")


func _cmd_rules() -> void:
	var a := _room(2, 21)
	var r: Room = a[0]
	var expect := {"morning": true, "noon": true, "evening_prep": true, "evening": true}
	var seen := {}
	var guard := 0
	while r.stage != "over" and guard < 80 and r.day < 3:
		guard += 1
		if not seen.has(r.stage):
			seen[r.stage] = true
			for i in 2:
				if r.can_cmd(i) != expect[r.stage] or r.info(i).act != expect[r.stage]:
					_fail("%s 에서 can_cmd 가 %s" % [r.stage, str(r.can_cmd(i))])
		if r.stage == "noon" or r.stage == "evening":
			# 기다리는 동안 명령 —— 이미 계산된 전투는 그대로, 편성은 바뀐다
			var s: Dictionary = r.seats[0]
			var sig0 := JSON.stringify(s.battles)
			var rr: Run = s.run
			var placed0 := rr.placed()
			r.on_cmd(1, "clear_board", [])
			if rr.placed() != 0 and placed0 != 0:
				_fail("%s 에서 clear_board 가 먹지 않았다" % r.stage)
			if JSON.stringify(s.battles) != sig0:
				_fail("%s 에서 명령이 계산된 전투를 바꿨다" % r.stage)
			r.on_cmd(1, "auto_deploy", [])
			if rr.placed() == 0 and not rr.inv.is_empty():
				_fail("%s 에서 auto_deploy 가 먹지 않았다" % r.stage)
			if rr.placed() > 0 and not s.acted:
				_fail("%s 명령이 acted 를 올리지 않았다" % r.stage)
		for s in r.humans():
			s.ready = true
		r.stage_end = 0.0
		r.tick()
	# 멸망한 사람 · 끝난 사람 · 시작 전은 안 된다
	r.seats[0].dead = true
	if r.can_cmd(0):
		_fail("멸망한 사람이 명령을 받는다")
	r.seats[0].dead = false
	r.seats[1].run.over = {"win": false, "msg": "x"}
	if r.can_cmd(1):
		_fail("끝난 사람이 명령을 받는다")
	r.seats[1].run.over = null
	if r.can_cmd(9) or r.can_cmd(-1) or r.can_cmd(2):      # 2 = 봇 자리
		_fail("없는 자리 · 봇 자리가 명령을 받는다")
	# 토너먼트 저녁은 잠긴다 (라운드마다 그 순간 편성으로 다시 계산하므로) · 토너먼트 저녁 준비는 열려 있다
	var c := _room(2, 22)
	var r3: Room = c[0]
	r3.day = 6
	r3.phase = 2
	r3.stage_end = 0.0
	_ready_all(r3)
	r3.tick()      # 아침 → (토벌 없이) 저녁 준비 (토너먼트)
	if r3.stage != "evening_prep" or r3.tour == null or not r3.can_cmd(0):
		_fail("토너먼트 저녁 준비가 열려 있지 않다 (%s)" % r3.stage)
	r3.stage_end = 0.0
	r3.tick()
	if r3.stage != "evening" or r3.can_cmd(0) or r3.info(0).act:
		_fail("토너먼트 저녁이 잠겨 있지 않다 (%s)" % r3.stage)
	r3.on_cmd(1, "clear_board", [])
	if r3.seats[0].run.placed() == 0:
		_fail("토너먼트 저녁에 clear_board 가 먹혔다")
	print("명령 규칙 점검 끝 — 준비 단계 · 점심 · 저녁 허용, 토너먼트 저녁 · 멸망 · 끝난 사람 거부, 계산된 전투 불변")


func _fake_res(win: bool, my_left: float, foe_left: float) -> Dictionary:
	return {"win": win, "draw": false, "left": 1, "eLeft": 1, "turns": 10, "mvp": null,
		"roster": [{"camp": "A", "max": 1000, "left": int(1000.0 * my_left)}, {"camp": "B", "max": 1000, "left": int(1000.0 * foe_left)}]}


func _hp_rules() -> void:
	var solo := Run.new()
	solo.new_game(5)
	var on := Run.new()
	on.new_game(5)
	on.mp = true
	if not is_equal_approx(solo.pvp_mul(), Run.HP_PVP_MUL) or not is_equal_approx(on.pvp_mul(), Run.HP_PVP_MUL_ONLINE) or not is_equal_approx(Run.HP_PVP_MUL_ONLINE, 1.0) or not is_equal_approx(Run.HP_PVP_MUL, 0.6):
		_fail("pvp_mul 값이 이상하다")
	for d in [0, 3, 6]:
		solo.day = d
		on.day = d
		var res := _fake_res(false, 0.1, 0.6)
		var ps: int = solo.hp_preview({"kind": "pvp"}, res)
		var po: int = on.hp_preview({"kind": "pvp"}, res)
		var pq: int = on.hp_preview({"kind": "quest"}, res)
		if po != pq or ps >= po:
			_fail("일차 %d 대전 패배 민심: 혼자 %d · 온라인 %d · 온라인 토벌 %d (온라인 대전 = 토벌, 혼자는 더 적어야)" % [d + 1, ps, po, pq])
		# 실제 finish_battle 도 같은 값을 깎는다
		on.hp = 100
		on.battle = {"kind": "pvp", "title": "대전 · x", "foe": "x", "pv": 1}
		on.finish_battle(res)
		if 100 - on.hp != po or on.last_hp_loss != po:
			_fail("일차 %d finish_battle 민심 %d (preview %d)" % [d + 1, 100 - on.hp, po])
	print("민심 점검 끝 — 온라인 대전 패배 ×%.1f(= 토벌) · 혼자 하기 ×%.1f" % [Run.HP_PVP_MUL_ONLINE, Run.HP_PVP_MUL])


func _tickets_total(r: Run) -> int:
	var n := 0
	for k in r.tickets:
		n += int(r.tickets[k])
	return n


func _inv_total(r: Run) -> int:
	var n := 0
	for k in r.inv:
		n += int(r.inv[k])
	return n


## 한 번 치르고 {전리품 수(last_spoil.n), 선택권 늘어난 수, 보너스, 보너스 선택권, 가방 늘어난 수}
func _fight(d: int, kind: String, mp: bool, win: bool, left: float) -> Dictionary:
	var r := Run.new()
	r.new_game(100 + d)
	r.mp = mp
	r.day = d
	var inv0 := _inv_total(r)
	var tk0 := _tickets_total(r)
	r.battle = {"kind": kind, "title": "%s · x" % kind, "foe": "x", "pv": 1}
	r.finish_battle(_fake_res(win, left, 0.0 if win else 0.5))
	var sp: Dictionary = r.last_spoil if r.last_spoil != null else {}
	return {"n": int(sp.get("n", 0)), "tk": _tickets_total(r) - tk0 + r.last_legend.size(),      # 4등급 랜덤권은 선택권이 아니라 그 자리에서 카드로 들어온다(last_legend)
	 "bonus": int(sp.get("bonus", 0)), "bt": int(sp.get("bonus_ticket", 0)),
		"inv": _inv_total(r) - inv0, "perf": sp.has("perf_r"), "sp": sp}


func _reward_rules() -> void:
	print("== 일차별 보상 (잔존 100%·승리 / 70%·승리 / 패배) —— 전리품 기본패 n · 선택권 장 · 성과 보너스(기본패 + 선택권)")
	print("   일차 | 토벌(승 r=1.0) | 토벌(승 r=0.7) | 토벌(패) | 대전 이전(승·패) | 대전 이후 온라인(승 r=1.0) | (승 r=0.7) | (패)")
	for d in 7:
		var qw := _fight(d, "quest", true, true, 1.0)
		var qw7 := _fight(d, "quest", true, true, 0.7)
		var ql := _fight(d, "quest", true, false, 0.2)
		var pw := _fight(d, "pvp", false, true, 1.0)      # 혼자 하기(= 이전 온라인과 같은 대전 보상)
		var pl := _fight(d, "pvp", false, false, 0.2)
		var ow := _fight(d, "pvp", true, true, 1.0)
		var ow7 := _fight(d, "pvp", true, true, 0.7)
		var ol := _fight(d, "pvp", true, false, 0.2)
		var f := func(x: Dictionary) -> String:
			return "%d장+선%d(보너스 %d+%d)" % [int(x.n) + int(x.bonus), int(x.tk) + int(x.bt), int(x.bonus), int(x.bt)]
		print("   %d | %s | %s | %s | %s · %s | %s | %s | %s" % [d + 1, f.call(qw), f.call(qw7), f.call(ql), f.call(pw), f.call(pl), f.call(ow), f.call(ow7), f.call(ol)])
		# 규칙 확인 —— 대전 보상 이전: 5장 + 선택권 1. 이후(4일차~): 이전 + 토벌과 같은 전리품 · 선택권 · 성과 보너스
		var base_n := int(DB.D.PVP_BASE.win)
		if int(pw.n) != base_n or int(pl.n) != base_n or pw.perf or pl.perf:
			_fail("일차 %d 혼자 하기 대전 보상이 바뀌었다 (n %d / %d)" % [d + 1, pw.n, pl.n])
		if d < Run.ONLINE_NOON_DAYS:
			if ow.n != base_n or ol.n != base_n or ow.perf or ow.bonus != 0:
				_fail("일차 %d(1~3일차) 온라인 대전 보상이 바뀌었다" % [d + 1])
		else:
			if ow.n != base_n + int(DB.D.QUEST_BASE[d]) or ol.n != ow.n or not ow.perf or not ol.perf:
				_fail("일차 %d 온라인 대전 전리품 %d (기대 %d)" % [d + 1, ow.n, base_n + int(DB.D.QUEST_BASE[d])])
			if int(ow.tk) < int(pw.tk) + 1 or int(ol.tk) != int(ow.tk) - int(ow.bt):
				_fail("일차 %d 온라인 대전 선택권 %d(보너스 %d) / 패 %d / 이전 %d" % [d + 1, ow.tk, ow.bt, ol.tk, pw.tk])
			# 성과 보너스 = 토벌과 같은 함수 · 패배는 보너스 없음
			var want := Run.quest_bonus(_fake_res(true, 1.0, 0.0), d)
			if ow.bonus != int(want.base) or ow.bt != int(want.ticket) or ol.bonus != 0 or ol.bt != 0:
				_fail("일차 %d 온라인 대전 보너스 %d+%d (기대 %d+%d) · 패 %d+%d" % [d + 1, ow.bonus, ow.bt, want.base, want.ticket, ol.bonus, ol.bt])
			# 가방이 실제로 그만큼 늘었다 (전리품 + 보너스)
			if int(ow.inv) < int(ow.n) + int(ow.bonus) - 1:
				_fail("일차 %d 온라인 대전 가방이 덜 늘었다 %d (전리품 %d + 보너스 %d)" % [d + 1, ow.inv, ow.n, ow.bonus])
			# 토벌과 같은 크기 —— 같은 일차 토벌 보상(전리품 · 보너스 · 선택권)이 대전 몫 위에 그대로 얹혔다
			if int(ow.n) - base_n != int(qw.n) or int(ow.bonus) != int(qw.bonus) or int(ow.bt) != int(qw.bt):
				_fail("일차 %d 대전이 얹은 몫(%d + 보너스 %d+%d)이 토벌(%d + %d+%d)과 다르다" % [d + 1, int(ow.n) - base_n, ow.bonus, ow.bt, qw.n, qw.bonus, qw.bt])
	print("보상 점검 끝")
