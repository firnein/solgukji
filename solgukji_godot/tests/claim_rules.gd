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
	_myth_chain()
	_dead_myth()
	_unique_filter()
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


## 신화 M 과 그 재료인 불멸 U (아이템이 필요 없는 U) —— 첫 번째 쌍
static func _pair() -> Array:
	var ms: Array = DB.RECOF.keys().filter(func(k): return int(DB.C[k].tier) >= 8 and not DB.is_foe(str(k)))
	ms.sort()
	for m in ms:
		for x in DB.RECOF[m]:
			if DB.C.has(x) and int(DB.C[x].tier) == 7 and Run.need_item(str(x)) == null:
				return [str(m), str(x)]
	return ["", ""]


## 11/12 ③ 선점제에서 신화를 만들면 하위 불멸의 선점은 어떻게 되나 (사용자 정정: 유지) —— 불멸 U 를 만들면 다른 사람은 U 가 잠기고, 그 U 로 신화 M 을 만들어 U 가 소모돼도 U · M 모두 사람1 선점으로 남아 사람2 는 U 를 못 만든다
func _myth_chain() -> void:
	var pr := _pair()
	var M: String = pr[0]
	var U: String = pr[1]
	var mk := _mk(true, 0)
	var r: Room = mk[0]
	var srv: FakeSrv = mk[1]
	var a: Dictionary = r.seats[0]
	var b: Dictionary = r.seats[1]
	_feed(a.run, U)
	r.on_cmd(1, "forge", [U])
	if a.run.have(U) != 1 or str(r.claims.get(U, "")) != "사람1":
		_fail("체인: 사람1 이 불멸 %s 를 선점하지 못했다 %s" % [U, str(r.claims)])
	if not b.run.locked.has(U) or not b.run.locked[U].has("by"):
		_fail("체인: 불멸 %s 가 사람2 에게 잠기지 않았다" % U)
	print("체인 1) 불멸 %s 선점 후 사람2 locked: %s" % [DB.C[U].name, str(b.run.locked.get(U))])
	# 신화 재료 (불멸은 이미 쥐었으니 나머지 + 유니크)
	var ni = Run.need_item(M)
	for q in DB.RECOF[M]:
		if str(q) != U:
			a.run.give(str(q))
	a.run.bag[ni] = 1
	if not a.run.can_forge(M):
		_fail("체인: 사람1 이 신화 %s 를 못 만든다 (시험 준비 오류)" % M)
	r.on_cmd(1, "forge", [M])
	if a.run.have(M) != 1 or a.run.have(U) != 0:
		_fail("체인: 신화 조합 결과 M=%d U=%d" % [a.run.have(M), a.run.have(U)])
	if str(r.claims.get(M, "")) != "사람1":
		_fail("체인: 신화 %s 선점이 사람1 이 아니다" % M)
	if str(r.claims.get(U, "")) != "사람1":
		_fail("체인: 재료로 쓴 불멸 %s 의 선점이 사람1 에게 남아 있지 않다 (%s)" % [U, str(r.claims)])
	if not b.run.locked.has(U) or str(b.run.locked[U].get("by", "")) != "사람1":
		_fail("체인: 사람2 에게 불멸 %s 가 사람1 선점으로 계속 잠겨 있어야 한다: %s" % [U, str(b.run.locked.get(U))])
	if not b.run.locked.has(M) or str(b.run.locked[M].get("by", "")) != "사람1":
		_fail("체인: 사람2 에게 신화 %s 가 사람1 선점으로 잠기지 않았다" % M)
	if a.run.locked.has(M) or a.run.locked.has(U):
		_fail("체인: 사람1 자신이 잠겼다")
	print("체인 2) 신화 %s 후 선점 %s · 사람2 locked: U=%s M=%s" % [DB.C[M].name, str(r.claims), str(b.run.locked.get(U)), str(b.run.locked.get(M))])
	# 불멸이 소모된 뒤에도 사람2 는 그 불멸을 조합할 수 없다 (명령도 거부 + 까닭 알림)
	_feed(b.run, U)
	if b.run.can_forge(U):
		_fail("체인: 사람2 가 사람1 의 신화 재료가 된 불멸 %s 를 만들 수 있다" % U)
	srv.out.clear()
	r.on_cmd(2, "forge", [U])
	if b.run.have(U) != 0:
		_fail("체인: 사람2 가 불멸 %s 를 조합했다" % U)
	var ts: Array = srv.of(2, "toast")
	if ts.is_empty() or not str(ts[0].text).contains("선점제"):
		_fail("체인: 사람2 의 불멸 조합 거부 알림이 없다")
	# 봇 대행도 못 만든다
	b.acted = false
	r._fill(b)
	if b.run.have(U) != 0:
		_fail("체인: 봇 대행이 잠긴 불멸 %s 를 조합했다" % U)
	for q in DB.RECOF[M]:
		if str(q) != U:
			b.run.give(str(q))
	b.run.bag[ni] = 1
	b.run.myth_made = false
	if b.run.can_forge(M):
		_fail("체인: 사람2 가 선점된 신화 %s 를 만들 수 있다" % M)
	# 불멸을 두 장 만든 경우 —— 한 장이 남았으면 풀지 않는다
	mk = _mk(true, 0)
	r = mk[0]
	a = r.seats[0]
	b = r.seats[1]
	_feed(a.run, U)
	r.on_cmd(1, "forge", [U])
	_feed(a.run, U)
	r.on_cmd(1, "forge", [U])
	if a.run.have(U) != 2:
		_fail("체인(2장): 불멸 두 장 조합 실패 %d" % a.run.have(U))
	for q in DB.RECOF[M]:
		if str(q) != U:
			a.run.give(str(q))
	a.run.bag[ni] = 1
	r.on_cmd(1, "forge", [M])
	if a.run.have(M) != 1 or a.run.have(U) != 1:
		_fail("체인(2장): 신화 조합 결과 M=%d U=%d" % [a.run.have(M), a.run.have(U)])
	if str(r.claims.get(U, "")) != "사람1" or not b.run.locked.has(U):
		_fail("체인(2장): 불멸이 한 장 남았는데 선점이 풀렸다")
	# 선점제 꺼짐이면 아무 기록도 없다
	mk = _mk(false, 0)
	r = mk[0]
	_feed(r.seats[0].run, U)
	r.on_cmd(1, "forge", [U])
	if not r.claims.is_empty():
		_fail("체인: 선점제 꺼짐인데 선점 기록이 있다")
	print("선점 체인 점검 끝")


## 11/12 ① 하위 불멸이 사망하면 그 신화도 등용 불가 (locked dead · 방 정보 dead_myth · 소식 글 · 조합 거부)
func _dead_myth() -> void:
	var pr := _pair()
	var M: String = pr[0]
	var U: String = pr[1]
	if Room.myth_over(U) != M:
		_fail("myth_over(%s) = %s, %s 여야 한다" % [U, Room.myth_over(U), M])
	if Room.myth_over(M) != "" or Room.myth_over("c1") != "":
		_fail("myth_over 가 불멸이 아닌 것에도 답한다")
	var found := false
	for sd in range(1, 40):      # 사망 10명 중 불멸이 든 방을 찾는다
		var mk := _mk(true, 10, 2, sd)
		var r: Room = mk[0]
		var dms: Array = r.dead_myths()
		if dms.is_empty():
			continue
		found = true
		for m in dms:
			if not r.seats[0].run.locked.has(m) or not r.seats[0].run.locked[m].has("dead"):
				_fail("하위 불멸 사망 신화 %s 가 잠기지 않았다" % m)
			if not (m in (r.info(0).dead_myth as Array)):
				_fail("방 정보 dead_myth 에 %s 없음" % m)
			if (m in r.dead_units):
				_fail("명단에 든 신화 %s 가 dead_myth 에도 있다" % m)
		var nw: String = str(r.seats[0].run.news[0].get("text", ""))
		if not nw.contains("신화"):
			_fail("사망 소식에 신화가 없다: %s" % nw)
		# 그 신화는 재료를 다 줘도 못 만든다
		var m0: String = dms[0]
		_feed(r.seats[0].run, m0)
		r.seats[0].run.bag[Run.need_item(m0)] = 1
		r.seats[0].run.myth_made = false
		if r.seats[0].run.can_forge(m0):
			_fail("사망 불멸의 신화 %s 를 만들 수 있다" % m0)
		print("사망 %d명 중 하위 불멸 사망 → 신화 %s · 소식: %s" % [r.dead_units.size(), " · ".join(dms.map(func(k): return DB.C[k].name)), nw])
		break
	if not found:
		_fail("사망 10명에 불멸이 든 방을 못 찾았다")
	# 직접 정한 사망 명단 [U]
	var mk2 := _mk(true, 0)
	var r2: Room = mk2[0]
	r2.dead_units = [U]
	r2._sync_locks()
	if not r2.seats[0].run.locked.has(M) or not r2.seats[1].run.locked.has(U):
		_fail("직접 사망 U: M · U 모두 잠겨야 한다 %s" % str(r2.seats[0].run.locked))
	r2.dead_units = [U, M]
	if r2.dead_myths() != []:
		_fail("명단에 든 신화는 dead_myth 에서 빠져야 한다")


## 11/12 ② 사망 · 선점으로 잠긴 신화의 유니크 재료는 유니크 보급 3택 · 다시 뽑기에 나오지 않는다 (여러 시드, 방 안 Run 의 locked 로)
func _unique_filter() -> void:
	var pr := _pair()
	var M: String = pr[0]
	var mi: String = str(Run.need_item(M))
	var seen_free := false
	for sd in 30:
		var run := Run.new()
		run.new_game(500 + sd)
		_unique_offer(run)
		if run.uniq_offer.has(mi):
			seen_free = true
	if not seen_free:
		_fail("잠금이 없을 때 %s 의 유니크 %s 가 한 번도 안 나온다 (표본 오류)" % [M, mi])
	var bad := 0
	var n_off := 0
	for sd in 60:
		var run := Run.new()
		run.new_game(500 + sd)
		run.locked = {M: {"dead": 1}}
		_unique_offer(run)
		n_off += run.uniq_offer.size()
		if run.uniq_offer.has(mi):
			bad += 1
		if run.reroll_unique() and run.uniq_offer.has(mi):
			bad += 1
		# 선점으로 잠긴 신화도 같다
		var run2 := Run.new()
		run2.new_game(500 + sd)
		run2.locked = {M: {"by": "누군가"}}
		_unique_offer(run2)
		if run2.uniq_offer.has(mi):
			bad += 1
		if run2.reroll_unique() and run2.uniq_offer.has(mi):
			bad += 1
	if bad > 0:
		_fail("잠긴 신화 %s 의 유니크 %s 가 %d 번 나왔다" % [M, mi, bad])
	# 신화를 전부 잠그면 보급이 비어 있다 (오류 없이)
	var run3 := Run.new()
	run3.new_game(1)
	for m in DB.RECOF.keys().filter(func(k): return int(DB.C[k].tier) >= 8 and not DB.is_foe(str(k))):
		run3.locked[str(m)] = {"dead": 1}
	_unique_offer(run3)
	if not run3.uniq_offer.is_empty() or run3.reroll_unique():
		_fail("신화를 모두 잠갔는데 유니크 보급이 나온다")
	# 열려 있는 보급 중에 신화가 선점되면 갈아 끼운다
	var run4 := Run.new()
	run4.new_game(9)
	_unique_offer(run4)
	var shown: Array = run4.uniq_offer.duplicate()
	var victim := ""
	for m in DB.RECOF.keys():
		if int(DB.C[m].tier) >= 8 and not DB.is_foe(str(m)) and shown.has(Run.need_item(str(m))):
			victim = str(m)
			break
	run4.locked = {victim: {"by": "누군가"}}
	if not run4.prune_unique_offer() or run4.uniq_offer.has(Run.need_item(victim)) or run4.uniq_offer.size() != 3:
		_fail("열린 유니크 보급 갈아 끼우기: %s" % str(run4.uniq_offer))
	# 방에서 사람2 가 선점당한 신화는 사람2 의 보급에서 빠진다
	var mk := _mk(true, 0)
	var r: Room = mk[0]
	r.claims[M] = "사람1"
	r._sync_locks()
	if not r.seats[1].run.blocked_uniques().has(mi) or r.seats[0].run.blocked_uniques().has(mi):
		_fail("방: 선점 신화의 유니크가 사람2 에게만 막혀야 한다")
	print("유니크 보급 거르기 점검 끝 (보급 %d개 표본, 막힌 신화 %s 유니크 %s)" % [n_off, DB.C[M].name, mi])


## 유니크 보급 상태로 만든다 (UNIQUE_PHASES 아침과 같은 호출)
static func _unique_offer(run: Run) -> void:
	run.uniq_offer = []
	run.uniq_rerolled = false
	var cand: Array = DB.IT.keys().filter(func(k): return DB.IT[k].grade == "유니크" and DB.MYTH_ITEMS.has(k))
	run._offer_unique(cand)


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
