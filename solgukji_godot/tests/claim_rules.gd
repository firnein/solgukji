extends Node
## 장수 선점제 · 장수 사망룰 점검 (11/12 사용자) —— 실행: godot --headless --path . res://tests/claim_rules.tscn [-- --port=7795]
## ① 가짜 서버로 Room 을 직접 돌린다 (소켓 없음):
##    선점제 켜짐 —— 사람1 이 기인 K 를 조합하면 사람2 의 Run.locked[K] = {by: 사람1} · 사람2 의 조합 명령은 거부되고 까닭 알림(toast) · 사람2 는 K 를 못 얻는다
##    봇 대행(_fill → bot_prepare)도 잠긴 장수를 조합하지 못한다 · 같은 단계에 봇 대행 둘이 차례로 조합하면 뒤 사람은 막힌다
##    선점제 꺼짐 —— 둘 다 조합된다 · 사망룰 n = 3 · 5 · 10 —— 기인 이상 n 명(중복 없음) · 모든 사람 Run.locked 에 dead · 조합 거부 · 소식 한 줄
##    옛 클라이언트(create 에 claim · deaths 없음) —— 선점제 켜짐 · 사망 0 / 이상한 deaths 값 → 0
## ② 실제 WebSocket (--port, 기본 7795): create {claim, deaths: 3} → 시작 → 방 정보 claim · deaths · dead_units(3) · 상태의 run.locked 에 사망 장수 ·
##    사망 장수 조합 명령을 보내면 까닭 알림(toast "사망룰")이 온다

const DEFAULT_PORT := 7795
var fails := []


class FakeSrv:
	var out := []        # [peer, msg]
	func send(peer: int, msg: Dictionary) -> void:
		out.append([peer, msg.duplicate(true)])
	func of(peer: int, t: String) -> Array:
		return out.filter(func(o): return o[0] == peer and o[1].t == t).map(func(o): return o[1])


func _fail(s: String) -> void:
	fails.append(s)
	printerr("FAIL ", s)


func _ready() -> void:
	_headless()
	await _socket()
	print("FAIL: ", fails if not fails.is_empty() else "없음")
	get_tree().quit(1 if not fails.is_empty() else 0)


func _mk(claim, deaths, humans_n := 2, seed_ := 7) -> Array:
	var srv := FakeSrv.new()
	var r := Room.new(srv, "CLAIM", "test", 4, claim, deaths)
	r.rng.seed = seed_
	for i in humans_n:
		r.add_human(i + 1, "사람%d" % (i + 1), "tk%d" % i, false)
	r.start()
	return [r, srv]


## 조합 재료를 넣어 준다 (아이템 필요 없는 장수만 고른다)
static func _feed(run: Run, k: String) -> void:
	var m := Run.mat_count(DB.RECOF[k])
	for q in m:
		run.give(str(q), int(m[q]))


static func _kiins(n: int) -> Array:
	var out := []
	var ks: Array = DB.RECOF.keys().filter(func(k): return DB.is_kiin(str(k)) and Run.need_item(str(k)) == null and not DB.is_foe(str(k)))
	ks.sort()
	for k in ks.slice(0, n):
		out.append(str(k))
	return out


func _headless() -> void:
	var kk := _kiins(3)
	var K: String = kk[0]
	var K2: String = kk[1]
	# 선점제 켜짐 —— 명령으로
	var mk := _mk(true, 0)
	var r: Room = mk[0]
	var srv: FakeSrv = mk[1]
	var a: Dictionary = r.seats[0]
	var b: Dictionary = r.seats[1]
	_feed(a.run, K)
	_feed(b.run, K)
	if not b.run.can_forge(K):
		_fail("재료를 넣었는데 사람2 가 아직 %s 를 못 만든다" % K)
	r.on_cmd(1, "forge", [K])
	if a.run.have(K) != 1:
		_fail("사람1 이 %s 조합 실패" % K)
	if str(r.claims.get(K, "")) != "사람1":
		_fail("선점 기록이 없다: %s" % str(r.claims))
	if not b.run.locked.has(K) or str(b.run.locked[K].get("by", "")) != "사람1":
		_fail("사람2 의 locked 에 %s 가 없다: %s" % [K, str(b.run.locked)])
	if a.run.locked.has(K):
		_fail("먼저 등용한 사람1 자신도 잠겼다")
	if b.run.lock_text(K) != "사람1 세력이 등용":
		_fail("lock_text: %s" % b.run.lock_text(K))
	# 사람2 에게 간 상태(state)에도 locked 가 실려 있다
	var st2: Array = srv.of(2, "state")
	if st2.is_empty() or not (st2[-1].run.get("locked", {}) as Dictionary).has(K):
		_fail("사람2 에게 간 상태에 locked 가 없다")
	srv.out.clear()
	r.on_cmd(2, "forge", [K])
	if b.run.have(K) != 0:
		_fail("사람2 가 선점된 %s 를 조합했다" % K)
	var ts: Array = srv.of(2, "toast")
	if ts.is_empty() or not str(ts[0].text).contains("선점제") or not str(ts[0].text).contains("사람1"):
		_fail("거부 까닭 알림이 없다: %s" % str(ts))
	else:
		print("거부 알림: ", ts[0].text)
	# 봇 대행 —— 사람2 가 아무것도 안 했다면 bot_prepare 가 조합을 하지만 잠긴 K 는 못 만든다
	b.acted = false
	r._fill(b)
	if b.run.have(K) != 0:
		_fail("봇 대행이 잠긴 %s 를 조합했다" % K)
	# 같은 단계에 봇 대행 둘 —— 둘 다 K2 재료가 있으면 앞 사람만
	_feed(a.run, K2)
	_feed(b.run, K2)
	a.acted = false
	r._fill(a)
	r._fill(b)
	if a.run.have(K2) + b.run.have(K2) != 1 or a.run.have(K2) != 1:
		_fail("봇 대행 차례 선점: 사람1 %d · 사람2 %d" % [a.run.have(K2), b.run.have(K2)])
	# 선점제 꺼짐 —— 둘 다
	mk = _mk(false, 0)
	r = mk[0]
	_feed(r.seats[0].run, K)
	_feed(r.seats[1].run, K)
	r.on_cmd(1, "forge", [K])
	r.on_cmd(2, "forge", [K])
	if r.seats[0].run.have(K) != 1 or r.seats[1].run.have(K) != 1 or not r.seats[1].run.locked.is_empty():
		_fail("선점제 꺼짐인데 막혔다")
	if bool(r.info(0).claim):
		_fail("방 정보 claim 이 꺼짐이 아니다")
	# 사망룰
	for n in [3, 5, 10]:
		mk = _mk(true, n, 2, 40 + n)
		r = mk[0]
		srv = mk[1]
		var dd: Array = r.dead_units
		var uniq := {}
		for k in dd:
			uniq[k] = true
			if not Room.is_urgent_unit(k):
				_fail("기인 이상이 아닌 사망 장수 %s" % k)
		if dd.size() != n or uniq.size() != n:
			_fail("사망 %d명이 아니다: %s" % [n, str(dd)])
		for s in r.humans():
			for k in dd:
				if not s.run.locked.has(k) or not s.run.locked[k].has("dead"):
					_fail("%s 의 locked 에 사망 %s 없음" % [s.name, k])
		if (r.info(0).dead_units as Array).size() != n or int(r.info(0).deaths) != n:
			_fail("방 정보 dead_units · deaths")
		if not r.seats[0].run.news.any(func(it): return str(it.get("text", "")).contains("사망")):
			_fail("사망 소식이 없다")
		var dk: String = dd[0]
		r.seats[0].run.myth_made = false
		_feed(r.seats[0].run, dk)
		srv.out.clear()
		r.on_cmd(1, "forge", [dk])
		if r.seats[0].run.have(dk) != 0:
			_fail("사망 장수 %s 가 조합됐다" % dk)
		var t2: Array = srv.of(1, "toast")
		if t2.is_empty() or not str(t2[0].text).contains("사망룰"):
			_fail("사망 거부 알림 없음")
		print("사망 %d명: %s" % [n, " · ".join(dd.map(func(k): return DB.C[k].name))])
	# 옛 클라이언트 · 이상한 값
	var old := Room.new(FakeSrv.new(), "OLD", "test", 4)
	if not old.claim_on or old.death_n != 0:
		_fail("옛 클라이언트 기본값")
	for v in [1, 4, -3, "5", 3.5, null]:
		if Room.valid_deaths(v) != 0:
			_fail("valid_deaths(%s)" % str(v))
	if Room.valid_deaths(5.0) != 5:
		_fail("valid_deaths(5.0)")
	# 혼자 하기 Run 은 잠금이 없다
	var solo := Run.new()
	solo.new_game(3)
	if not solo.locked.is_empty():
		_fail("혼자 하기 locked")
	print("가짜 서버 점검 끝")


func _socket() -> void:
	var port := DEFAULT_PORT
	for s in OS.get_cmdline_user_args():
		var kv := s.trim_prefix("--").split("=", true, 1)
		if kv[0] == "port" and kv.size() > 1:
			port = int(kv[1])
	var server := MatchServer.new()
	server.port = port
	add_child(server)
	var cs := []
	var got := [[], []]
	for i in 2:
		var c := NetClient.new()
		c.player = "소켓%d" % i
		c.token = ""
		add_child(c)
		cs.append(c)
		var ii := i
		c.message.connect(func(d): got[ii].append(d))
		c.connect_to("ws://127.0.0.1:%d" % port)
	var t0 := Time.get_ticks_msec()
	var step := 0
	var code := ""
	while Time.get_ticks_msec() - t0 < 20000:
		await get_tree().process_frame
		if step == 0 and got[0].any(func(d): return d.t == "hello") and got[1].any(func(d): return d.t == "hello"):
			cs[0].send({"t": "create", "mode": "test", "max": 4, "claim": true, "deaths": 3})
			step = 1
		elif step == 1:
			for d in got[0]:
				if d.t == "room":
					code = str(d.room.code)
			if code != "":
				cs[1].send({"t": "join", "code": code})
				step = 2
		elif step == 2 and got[0].any(func(d): return d.t == "room" and (d.room.seats as Array).size() == 2):
			cs[0].send({"t": "start"})
			step = 3
		elif step == 3:
			var sts: Array = got[1].filter(func(d): return d.t == "state")
			if not sts.is_empty():
				var st: Dictionary = sts[0]
				var dead: Array = st.room.get("dead_units", [])
				if dead.size() != 3 or not bool(st.room.get("claim", false)) or int(st.room.get("deaths", 0)) != 3:
					_fail("소켓: 방 정보 규칙 %s" % str([st.room.get("claim"), st.room.get("deaths"), dead]))
				for k in dead:
					if not (st.run.get("locked", {}) as Dictionary).has(k):
						_fail("소켓: 상태 locked 에 %s 없음" % k)
				print("소켓: 사망 장수 ", dead)
				if not dead.is_empty():
					cs[1].send({"t": "cmd", "m": "forge", "a": [dead[0]]})
				step = 4
		elif step == 4:
			var ts: Array = got[1].filter(func(d): return d.t == "toast" and str(d.text).contains("사망룰"))
			if not ts.is_empty():
				print("소켓: 거부 알림 ", ts[0].text)
				step = 5
				break
	if step != 5:
		_fail("소켓 점검이 %d 단계에서 멈췄다" % step)
	for c in cs:
		c.close()
	server.tcp.stop()
	server.queue_free()
