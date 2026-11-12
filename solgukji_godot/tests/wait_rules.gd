extends Node
## 11/11 온라인 규칙 점검 —— 가짜 서버로 Room 을 직접 돌린다 (포트 없음 · 헤드리스).
## 실행: godot --headless --path . res://tests/wait_rules.tscn
## ① 점심(토벌)은 1~3일차만 (Room.has_noon · 방 정보 noon) ② 기다리지 않는 사람(끊김 · 봇 대행 · 볼 전투 없음)은 서버가 바로 넘긴다
## ③ 11/12 페이즈 개편: 아침 = 징집 · 조합 · 편성, 점심 · 저녁 = 전투를 다 본 뒤 징집 · 조합만, 저녁 준비 = 편성만 — 토너먼트 저녁 · 멸망한 사람은 안 된다. 이미 계산된 전투는 그대로
## ⑥ 11/12 온라인 전투 보상은 다음 아침(advance)에 지급 (Run.held)
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
	_timer_rules()
	_cmd_rules()
	_hp_rules()
	_reward_rules()
	_mvp_rules()
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


## 11/12 사용자: 토벌이 사라지는 4일차~ 는 준비 60 → 30초 · 대전 준비 30 → 15초 (빠른 · 보통), 점검 모드는 그대로 —— 시작 때 「토벌 종료」 알림이 한 번만
func _timer_rules() -> void:
	# 정적 값 —— 일차(0 = 1일차)마다 단계 길이
	for m in ["fast", "normal"]:
		for d in 7:
			var late := d >= Run.ONLINE_NOON_DAYS
			var want := {"morning": 30.0 if late else 60.0, "noon": 75.0, "evening_prep": 15.0 if late else 30.0, "evening": 100.0}
			for st in want:
				if Room.stage_len(m, st, d) != float(want[st]):
					_fail("%s %d일차 %s 길이 %s (기대 %s)" % [m, d + 1, st, str(Room.stage_len(m, st, d)), str(want[st])])
	for d in 7:
		if Room.stage_len("test", "morning", d) != 1.0 or Room.stage_len("test", "evening_prep", d) != 0.5:
			_fail("점검 모드 타이머가 일차마다 같지 않다 (%d일차)" % (d + 1))
	if Room.cut_text("fast") != "준비 30초 · 대전 준비 15초":
		_fail("cut_text(fast) = %s" % Room.cut_text("fast"))
	if Room.sec_text(60.0) != "1분" or Room.sec_text(15.0) != "15초" or Room.sec_text(0.5) != "0.5초":
		_fail("sec_text")
	# 방을 일차 순서로 돌려 본다 —— 방 정보 stage_len · remain 과 알림
	for m in ["fast", "test"]:
		var srv := FakeSrv.new()
		var r := Room.new(srv, "WT", m)
		r.rng.seed = 21
		r.add_human(1, "사람1", "tk0")
		r.add_human(2, "사람2", "tk1")
		r.start()
		var news_at := []      # 「토벌 종료」 소식이 온 때 [day, phase, stage]
		var seen_n := 0
		var lens := {}      # 일차 -> {단계: 방 정보 stage_len}
		var guard := 0
		while r.day < 5 and guard < 300:
			guard += 1
			for h in r.humans():      # 11/12 최후 1인: 사람이 모두 멸망하면 진짜 방은 끝난다 —— 타이머만 보려고 민심을 채운다 (봇 대행 사람은 일찍 무너진다)
				h.run.hp = Run.HP_MAX
			var inf: Dictionary = r.info(0)
			if not lens.has(r.day):
				lens[r.day] = {}
			if not lens[r.day].has(r.stage):
				lens[r.day][r.stage] = float(inf.stage_len)
			if float(inf.remain) > float(inf.stage_len) + 0.05:
				_fail("remain 이 stage_len 보다 크다 (%s)" % r.stage)
			if bool(inf.noon_end) != (r.day == 3 and r.phase == 0 and r.stage == "morning"):
				_fail("noon_end 방 정보가 4일차 첫 아침에만 참이어야 한다 (day %d phase %d %s = %s)" % [r.day, r.phase, r.stage, str(inf.noon_end)])
			var ne := srv.of(1, "news").filter(func(d): return str(d.list[0].get("band", "")) == "noon_end")
			if ne.size() > seen_n:
				seen_n = ne.size()
				news_at.append([r.day, r.phase, r.stage])
				var it: Dictionary = ne[-1].list[0]
				var line := Room.cut_text(m)
				if not str(it.text).begins_with("토벌 종료") or not str(it.text).contains(line) or str(it.line) != line:
					_fail("토벌 종료 알림 글: %s" % str(it))
				if bool(it.get("hot", false)):
					_fail("토벌 종료 알림에 hot 이 있다 (옛 휴대폰 긴급 띠 오작동)")
				if m == "fast" and not str(it.text).contains("준비 30초 · 대전 준비 15초"):
					_fail("빠른 모드 알림에 30 · 15초가 없다: %s" % str(it.text))
			_ready_all(r)
			for s in r.humans():
				s.ready = true
				s.watched = true
			r.stage_end = 0.0      # 시간이 다 됐다고 보고 넘긴다
			r.tick()
		if news_at != [[3, 0, "morning"]]:
			_fail("[%s] 토벌 종료 알림이 4일차 첫 아침에 정확히 한 번이어야 한다: %s" % [m, str(news_at)])
		# 방의 Run.news 에도 한 번
		var cnt: int = r.seats[0].run.news.filter(func(it): return str(it.get("band", "")) == "noon_end").size()
		if cnt != 1:
			_fail("[%s] Run.news 에 토벌 종료가 %d 번" % [m, cnt])
		# 일차별 방 정보 stage_len
		for d in lens:
			for st in lens[d]:
				if st in ["lobby", "over"]:
					continue
				var want := Room.stage_len(m, str(st), int(d))
				if absf(float(lens[d][st]) - want) > 0.001:
					_fail("[%s] %d일차 %s 방 정보 stage_len %s (기대 %s)" % [m, int(d) + 1, st, str(lens[d][st]), str(want)])
		if m == "fast":
			var l: Dictionary = lens
			if not (l.has(2) and l.has(3)):
				_fail("일차 표본이 모자란다")
			else:
				print("방 정보 stage_len —— 3일차 아침 %s · 대전 준비 %s / 4일차 아침 %s · 대전 준비 %s (토벌 %s → %s)" % [str(l[2].get("morning")), str(l[2].get("evening_prep")), str(l[3].get("morning")), str(l[3].get("evening_prep")), str(l[2].get("noon")), str(l[3].get("noon", "없음"))])
	# 5초 경고 시작 시점 —— 60 · 30초 단계는 10초부터, 15초 단계는 5초부터 (단계의 1/3, 5~10초)
	var on := Online.new()
	var exp := {0.0: 10, 15.0: 5, 30.0: 10, 60.0: 10, 75.0: 10, 24.0: 8}
	for len_ in exp:
		on._stage_len = float(len_)
		if on.warn_sec() != int(exp[len_]):
			_fail("warn_sec(%s) = %d (기대 %d)" % [str(len_), on.warn_sec(), int(exp[len_])])
	on.free()
	print("타이머 점검 끝 — 1~3일차 준비 60 · 대전 준비 30 / 4일차~ 30 · 15, 토벌 종료 알림 한 번, 경고 시점")


func _cmd_rules() -> void:
	var a := _room(2, 21)
	var r: Room = a[0]
	var expect := {"morning": [true, true], "noon": [true, false], "evening_prep": [false, true], "evening": [true, false]}      # [징집 · 조합, 편성] (점심 · 저녁은 다 본 뒤)
	var seen := {}
	var guard := 0
	while r.stage != "over" and guard < 80 and r.day < 3:
		guard += 1
		if r.stage in Room.WATCH_STAGES and not r.seats[0].battles.is_empty():
			# 전투를 다 보기 전에는 아무것도 안 된다
			if r.can_cmd(0) or r.info(0).act_draw or r.info(0).act_form:
				_fail("%s 에서 전투를 다 보기 전에 명령을 받는다" % r.stage)
			r.on_ready(1, true)
		if not seen.has(r.stage):
			seen[r.stage] = true
			for i in 2:
				var e: Array = expect[r.stage]
				var inf := r.info(i)
				if r.seats[i].watched or not (r.stage in Room.WATCH_STAGES):
					if bool(inf.act_draw) != e[0] or bool(inf.act_form) != e[1] or (r.cmd_block(i, "forge") == "") != e[0] or (r.cmd_block(i, "place") == "") != e[1]:
						_fail("%s 에서 징집 %s · 편성 %s (기대 %s)" % [r.stage, str(inf.act_draw), str(inf.act_form), str(e)])
					if not bool(inf.act_draw) and str(inf.why_draw) == "" or not bool(inf.act_form) and str(inf.why_form) == "":
						_fail("%s 에서 막힌 이유가 비었다" % r.stage)
		var s: Dictionary = r.seats[0]
		var rr: Run = s.run
		var placed0 := rr.placed()
		var sig0 := JSON.stringify(s.battles)
		r.on_cmd(1, "clear_board", [])
		var form_ok: bool = r.stage in ["morning", "evening_prep"]
		if placed0 > 0 and form_ok != (rr.placed() == 0):
			_fail("%s 에서 clear_board 가 %s" % [r.stage, "먹지 않았다" if form_ok else "먹혔다"])
		if not form_ok and srv_err(a[1], 1) == "":
			_fail("%s 에서 거부 이유를 보내지 않았다" % r.stage)
		srv_err(a[1], 1)
		if JSON.stringify(s.battles) != sig0:
			_fail("%s 에서 명령이 계산된 전투를 바꿨다" % r.stage)
		r.on_cmd(1, "auto_deploy", [])
		var d0 := rr.drawn
		r.on_cmd(1, "do_draw", [])
		if r.stage == "evening_prep" and rr.drawn != d0:
			_fail("저녁 준비에 징집이 먹혔다")
		for h in r.humans():
			h.ready = true
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
	# 11/12 최후 1인: 7일차 저녁은 토너먼트가 아니라 여느 저녁 —— 대전 준비 · 대전 뒤 8일차 아침으로 이어진다
	var c := _room(2, 22)
	var r3: Room = c[0]
	r3.day = 6
	r3.phase = 2
	r3.stage_end = 0.0
	_ready_all(r3)
	r3.tick()      # 아침 → (토벌 없이) 저녁 준비
	if r3.stage != "evening_prep" or r3.tour != null or not r3.can_cmd(0) or r3.seats[0].foe == null:
		_fail("7일차 저녁 준비가 여느 대전 준비가 아니다 (%s)" % r3.stage)
	r3.stage_end = 0.0
	r3.tick()
	if r3.stage != "evening" or r3.tour != null:
		_fail("7일차 저녁이 여느 대전이 아니다 (%s)" % r3.stage)
	for h in r3.humans():
		h.ready = true
		h.watched = true
	r3.stage_end = 0.0
	r3.tick()
	if r3.stage != "morning" or r3.day != 7:
		_fail("7일차 저녁 뒤 8일차 아침으로 이어지지 않는다 (%s · 일차 %d)" % [r3.stage, r3.day + 1])
	print("명령 규칙 점검 끝 — 아침 전부 · 점심/저녁(다 본 뒤) 징집 · 조합 · 저녁 준비 편성만, 멸망 · 끝난 사람 거부, 계산된 전투 불변, 7일차 저녁 뒤 8일차로")


func srv_err(srv, peer: int) -> String:
	var es: Array = srv.of(peer, "error")
	srv.out.clear()
	return str(es[-1].msg) if not es.is_empty() else ""


## 11/12 유저전 수훈 연속 소식 —— 같은 기인 이상 장수가 이기며 2 · 3 · 4연속 수훈이면 다음 아침에 방 전체 소식, 3연속부터 hot
func _mvp_rules() -> void:
	var a := _room(2, 31)
	var r: Room = a[0]
	var srv = a[1]
	var hi := ""
	for k in DB.C:
		if Room.is_urgent_unit(str(k)):
			hi = str(k)
			break
	var res := {"win": true, "roster": [{"camp": "A", "id": hi, "dmg": 9000, "kills": 3}, {"camp": "A", "id": "x", "dmg": 10}, {"camp": "B", "id": "y", "dmg": 99999}]}
	var hot_n := []
	for n in 4:
		r._mvp_track(r.seats[0], res, "A", true)
		srv.out.clear()
		r._flush_mvp_news()
		var ns: Array = srv.of(2, "news")
		hot_n.append(-1 if ns.is_empty() else int(ns[0].list[0].get("hot", 0)))
	if hot_n != [-1, 0, 1, 1]:
		_fail("수훈 연속 소식 %s (기대 [-1, 0, 1, 1])" % str(hot_n))
	r._mvp_track(r.seats[0], res, "A", false)      # 지면 끊긴다
	r._mvp_track(r.seats[0], res, "A", true)
	srv.out.clear()
	r._flush_mvp_news()
	if not srv.of(2, "news").is_empty():
		_fail("진 뒤에도 수훈 연속이 이어졌다")
	if Room.side_mvp(res, "B") != "y":
		_fail("side_mvp B")
	print("수훈 연속 소식 점검 끝")


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
	if mp:      # 11/12 온라인 보상은 아침에 —— 정산 직후에는 손패 · 선택권이 그대로, grant_held 가 준다
		if _inv_total(r) != inv0 or _tickets_total(r) != tk0 or r.held.is_empty():
			_fail("일차 %d %s 온라인 보상이 바로 들어왔다" % [d + 1, kind])
		r.grant_held()
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
			if ow.n != base_n + int(DB.D.QUEST_BASE[d]) or ol.n != ow.n or not ow.perf or not ol.perf:      # (패배도 같은 전리품)
				_fail("일차 %d 온라인 대전 전리품 %d (기대 %d)" % [d + 1, ow.n, base_n + int(DB.D.QUEST_BASE[d])])
			# 11/12 사용자: 온라인은 승패 · 성과 차등 없음 —— 졌어도, 잔존 병력이 낮아도 승리와 같은 보상(보너스 포함)
			if int(ow.tk) < int(pw.tk) + 1 or int(ol.tk) != int(ow.tk) or int(ow7.tk) != int(ow.tk):
				_fail("일차 %d 온라인 대전 선택권 %d(보너스 %d) / 패 %d / 잔존0.7 %d / 이전 %d" % [d + 1, ow.tk, ow.bt, ol.tk, ow7.tk, pw.tk])
			var want := Run.quest_bonus(_fake_res(true, 1.0, 0.0), d, true)
			if ow.bonus != int(want.base) or ow.bt != int(want.ticket) or ol.bonus != ow.bonus or ol.bt != ow.bt or ow7.bonus != ow.bonus:
				_fail("일차 %d 온라인 대전 보너스 %d+%d (기대 %d+%d) · 패 %d+%d · 잔존0.7 %d+%d" % [d + 1, ow.bonus, ow.bt, want.base, want.ticket, ol.bonus, ol.bt, ow7.bonus, ow7.bt])
			# 가방이 실제로 그만큼 늘었다 (전리품 + 보너스)
			if int(ow.inv) < int(ow.n) + int(ow.bonus) - 1:
				_fail("일차 %d 온라인 대전 가방이 덜 늘었다 %d (전리품 %d + 보너스 %d)" % [d + 1, ow.inv, ow.n, ow.bonus])
			# 토벌과 같은 크기 —— 같은 일차 토벌 보상(전리품 · 보너스 · 선택권)이 대전 몫 위에 그대로 얹혔다
			if int(ow.n) - base_n != int(qw.n) or int(ow.bonus) != int(qw.bonus) or int(ow.bt) != int(qw.bt):
				_fail("일차 %d 대전이 얹은 몫(%d + 보너스 %d+%d)이 토벌(%d + %d+%d)과 다르다" % [d + 1, int(ow.n) - base_n, ow.bonus, ow.bt, qw.n, qw.bonus, qw.bt])
	print("보상 점검 끝")
