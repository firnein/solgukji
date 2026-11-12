extends Node
## 유닛 판매 · 군량 상점 점검 (11/13 사용자) —— 실행: godot --headless --path . res://tests/shop_rules.tscn [-- --port=7831]
## ⓪ 가격 표 —— 등급별 기본패 환산 값(평균 · 최소~최대) · 판매가(× Run.SELL_RATE) · 상점가. 같은 등급 최고 판매가 < 상점가 (팔고-사기 이득 없음)
## ① 혼자 하기 Run —— 판매(손패 → 편성 순, 군량 +) · 구매(군량 −, 그 등급 장수 하나) · 군량 부족 · 기본패 판매 거부 · 저장(to_dict/from_dict)에 군량
## ② 가짜 서버로 Room —— 판매 켜짐: 아침 판매 · 구매 → 상태의 run.grain · 대전 준비(evening_prep)엔 거부(error) · 군량 부족은 toast 거부
##    판매 꺼짐: 판매 · 구매 모두 toast 거부(「꺼진 방」) · 방 정보 sell false · 옛 클라이언트(sell 없음) 방은 켜짐
## ③ 실제 WebSocket (--port, 기본 7831): create {sell: false} → 시작 → 방 정보 sell false · 판매 명령 → 거부 알림

const DEFAULT_PORT := 7831
var fails := []


class FakeSrv:
	var out := []
	func send(peer: int, msg: Dictionary) -> void:
		out.append([peer, msg.duplicate(true)])
	func of(peer: int, t: String) -> Array:
		return out.filter(func(o): return o[0] == peer and o[1].t == t).map(func(o): return o[1])


func _fail(s: String) -> void:
	fails.append(s)
	printerr("FAIL ", s)


func _ready() -> void:
	_prices()
	_solo()
	_room()
	await _socket()
	print("FAIL: ", fails if not fails.is_empty() else "없음")
	get_tree().quit(1 if not fails.is_empty() else 0)


func _prices() -> void:
	print("| 등급 | 장수 | 기본패 환산 평균 (최소~최대) | 판매가 (최소~최대) | 상점 랜덤권 | 판매/값 |")
	print("|---|---|---|---|---|---|")
	for t in [3, 4, 5, "기인", 6, 7, 8]:
		var ks: Array
		if str(t) == "기인":
			ks = DB.C.keys().filter(func(k): return DB.is_kiin(k) and Run.sellable(k))
		else:
			ks = DB.by_tier(int(t)).filter(func(k): return Run.sellable(k) and not DB.is_kiin(k))
		if ks.is_empty():
			continue
		var vs: Array = ks.map(func(k): return Run.base_value(k))
		var ps: Array = ks.map(func(k): return Run.sell_price(k))
		var avg: float = vs.reduce(func(a, b): return a + b, 0.0) / vs.size()
		var pavg: float = ps.reduce(func(a, b): return a + b, 0.0) / ps.size()
		var name_: String = str(t) if str(t) == "기인" else DB.TIER[int(t)].n
		var shop := "-"
		if typeof(t) == TYPE_INT and int(t) in Run.SHOP_TIERS:
			shop = str(Run.shop_price(int(t)))
			var pk: Array = Run.pickable(int(t)).filter(func(k): return Run.sellable(k))
			var mx: int = pk.map(func(k): return Run.sell_price(k)).max()
			if mx >= Run.shop_price(int(t)):
				_fail("%s 최고 판매가 %d ≥ 상점가 %d (팔고-사기 이득)" % [name_, mx, Run.shop_price(int(t))])
		print("| %s | %d | %.1f (%d~%d) | %.1f (%d~%d) | %s | %.2f |" % [name_, ks.size(), avg, vs.min(), vs.max(), pavg, ps.min(), ps.max(), shop, pavg / avg])
	# 상점에서 산 장수를 재료로 조합해 위 등급을 팔아도 이득이 없어야 한다 —— 어느 장수든 판매가 < 그 값 (상점가는 값 평균 × 1.0 이상)
	for k in DB.C:
		if Run.sellable(k) and Run.sell_price(k) >= Run.base_value(k):
			_fail("%s 판매가가 값 이상" % k)


func _solo() -> void:
	var r := Run.new()
	r.new_game(11)
	var k: String = Run.pickable(4)[0]
	r.give(k, 2)
	r.place(0, k)
	if r.sell("spear"):
		_fail("기본패가 팔렸다")
	var g0 := r.grain
	if not r.sell(k):
		_fail("희귀 판매 실패")
	if r.grain != g0 + Run.sell_price(k) or r.on_board(k) != 1 or int(r.inv.get(k, 0)) != 0:
		_fail("판매 후 상태: 군량 %d · 편성 %d · 손패 %d" % [r.grain, r.on_board(k), int(r.inv.get(k, 0))])
	if not r.sell(k) or r.on_board(k) != 0 or r.have(k) != 0:
		_fail("편성에 올린 마지막 장을 팔지 못했다")
	if r.sell(k):
		_fail("없는 장수가 팔렸다")
	r.grain = Run.shop_price(5) - 1
	if r.buy(5) != null or r.grain != Run.shop_price(5) - 1:
		_fail("군량이 모자란데 전설 랜덤권을 샀다")
	if r.buy(6) != null:
		_fail("초월 랜덤권을 샀다")
	r.grain = Run.shop_price(5)
	var n0 := r._card_count()
	var got = r.buy(5)
	if got == null or DB.C[got].tier != 5 or DB.is_kiin(got) or r.grain != 0 or r._card_count() != n0 + 1:
		_fail("전설 랜덤권 구매: %s · 군량 %d" % [str(got), r.grain])
	r.grain = 37
	var d: Dictionary = JSON.parse_string(JSON.stringify(r.to_dict(), "", false, true))
	var r2 := Run.new()
	r2.from_dict(d)
	if r2.grain != 37 or typeof(r2.grain) != TYPE_INT or not r2.sell_on:
		_fail("저장 · 불러오기 군량 %s" % str(r2.grain))
	d.erase("grain")
	d.erase("sell_on")
	var r3 := Run.new()
	r3.from_dict(d)
	if r3.grain != 0 or not r3.sell_on:
		_fail("옛 저장: 군량 %d · 판매 %s" % [r3.grain, r3.sell_on])
	print("혼자 하기: 판매 · 구매 · 저장 확인 (전설 랜덤권 → %s)" % DB.C[got].name if got != null else "")


func _mk(sell, seed_ := 5) -> Array:
	var srv := FakeSrv.new()
	var r: Room
	if sell == null:
		r = Room.new(srv, "SHOP", "test", 4, true, 0)      # 옛 클라이언트 —— sell 없음
	else:
		r = Room.new(srv, "SHOP", "test", 4, true, 0, sell)
	r.rng.seed = seed_
	r.add_human(1, "사람1", "tk1", false)
	r.add_human(2, "사람2", "tk2", false)
	r.start()
	return [r, srv]


func _room() -> void:
	var k: String = Run.pickable(4)[0]
	# 옛 클라이언트 방 —— 켜짐
	var mk := _mk(null)
	if not mk[0].sell_on or not mk[0].seats[0].run.sell_on or not bool(mk[0].info(0).get("sell", false)):
		_fail("옛 클라이언트 방이 판매 꺼짐")
	mk = _mk("이상한 값")
	if not mk[0].sell_on:
		_fail("이상한 sell 값인데 꺼짐")
	# 켜짐
	mk = _mk(true)
	var r: Room = mk[0]
	var srv: FakeSrv = mk[1]
	var a: Dictionary = r.seats[0]
	a.run.give(k, 1)
	if r.stage != "morning":
		_fail("시작 단계가 아침이 아니다: %s" % r.stage)
	r.on_cmd(1, "sell", [k])
	var price := Run.sell_price(k)
	if a.run.grain != price or a.run.have(k) != 0:
		_fail("아침 판매: 군량 %d (기대 %d) · 남은 %d" % [a.run.grain, price, a.run.have(k)])
	var st: Array = srv.of(1, "state")
	if st.is_empty() or int(st[-1].run.get("grain", -1)) != price:
		_fail("상태에 군량이 없다")
	if not a.run.toasts.is_empty():
		_fail("서버 쪽 판매 알림이 남았다: %s" % str(a.run.toasts))
	srv.out.clear()
	r.on_cmd(1, "buy", [3])
	if price < Run.shop_price(3):
		var ts: Array = srv.of(1, "toast")
		if ts.is_empty() or not str(ts[0].text).contains("군량이 모자랍니다"):
			_fail("군량 부족 거부 알림 없음: %s" % str(ts))
		else:
			print("군량 부족 거부: ", ts[0].text)
	a.run.grain = Run.shop_price(4)
	var n0: int = a.run._card_count()
	r.on_cmd(1, "buy", ["4"])      # 글자 인자 —— 거부
	if a.run._card_count() != n0:
		_fail("글자 등급으로 샀다")
	r.on_cmd(1, "buy", [4.0])      # JSON 숫자(float)
	if a.run.grain != 0 or a.run._card_count() != n0 + 1:
		_fail("희귀 랜덤권 구매 실패: 군량 %d" % a.run.grain)
	# 대전 준비 —— 징집 · 조합 계열이라 거부
	a.run.give(k, 1)
	r._stage("evening_prep")
	srv.out.clear()
	r.on_cmd(1, "sell", [k])
	var er: Array = srv.of(1, "error")
	if a.run.have(k) != 1 or er.is_empty():
		_fail("대전 준비 중 판매가 됐다")
	else:
		print("대전 준비 거부: ", er[0].msg)
	# 꺼짐
	mk = _mk(false)
	r = mk[0]
	srv = mk[1]
	a = r.seats[0]
	if a.run.sell_on or bool(r.info(0).get("sell", true)):
		_fail("판매 꺼짐 방 정보 · Run.sell_on")
	a.run.give(k, 1)
	a.run.grain = 999
	r.on_cmd(1, "sell", [k])
	r.on_cmd(1, "buy", [5])
	var ts2: Array = srv.of(1, "toast")
	if a.run.have(k) != 1 or a.run.grain != 999 or ts2.size() < 2 or not str(ts2[0].text).contains("꺼진 방"):
		_fail("판매 꺼짐인데 됐다 / 알림 %s" % str(ts2))
	else:
		print("판매 꺼짐 거부: ", ts2[0].text, " / ", ts2[1].text)
	# 봇 대행은 팔지도 사지도 않는다
	var b: Dictionary = r.seats[1]
	b.run.grain = 999
	b.acted = false
	r._fill(b)
	if b.run.grain != 999:
		_fail("봇 대행이 군량을 썼다")


func _socket() -> void:
	var port := DEFAULT_PORT
	for s in OS.get_cmdline_user_args():
		var kv := s.trim_prefix("--").split("=", true, 1)
		if kv[0] == "port" and kv.size() > 1:
			port = int(kv[1])
	var server := MatchServer.new()
	server.port = port
	add_child(server)
	var c := NetClient.new()
	c.player = "판매점검"
	c.token = ""
	add_child(c)
	var got := []
	c.message.connect(func(d): got.append(d))
	c.connect_to("ws://127.0.0.1:%d" % port)
	var t0 := Time.get_ticks_msec()
	var step := 0
	while Time.get_ticks_msec() - t0 < 20000:
		await get_tree().process_frame
		if step == 0 and got.any(func(d): return d.t == "hello"):
			c.send({"t": "create", "mode": "test", "max": 4, "sell": false})
			step = 1
		elif step == 1 and got.any(func(d): return d.t == "room"):
			c.send({"t": "start"})
			step = 2
		elif step == 2:
			var sts: Array = got.filter(func(d): return d.t == "state")
			if not sts.is_empty():
				if bool(sts[0].room.get("sell", true)) or bool(sts[0].run.get("sell_on", true)):
					_fail("소켓: 방 정보 sell %s · run.sell_on %s" % [str(sts[0].room.get("sell")), str(sts[0].run.get("sell_on"))])
				c.send({"t": "cmd", "m": "sell", "a": [Run.pickable(3)[0]]})
				step = 3
		elif step == 3:
			var ts: Array = got.filter(func(d): return d.t == "toast" and str(d.text).contains("꺼진 방"))
			if not ts.is_empty():
				print("소켓: 거부 알림 ", ts[0].text)
				step = 4
				break
	if step != 4:
		_fail("소켓 점검이 %d 단계에서 멈췄다" % step)
	c.close()
	server.tcp.stop()
	server.queue_free()
