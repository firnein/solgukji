extends Node
## 방 메시지 점검 —— 가짜 서버로 Room 을 직접 돌려 params · news · say · room.quick · hp 를 확인 (11/9 사용자).
## 실행: godot --headless --path . res://tests/room_msgs.tscn

class FakeSrv:
	var out := []        # [peer, msg]
	func send(peer: int, msg: Dictionary) -> void:
		out.append([peer, msg])
	func of(peer: int, t: String) -> Array:
		return out.filter(func(o): return o[0] == peer and o[1].t == t).map(func(o): return o[1])


func _ready() -> void:
	var fails := []
	var srv := FakeSrv.new()
	var r := Room.new(srv, "TEST", "test")
	r.add_human(1, "가", "tk1")
	r.add_human(2, "나", "tk2")
	var inf: Dictionary = r.info(0)
	if inf.get("quick", []) != Room.QUICK_MSGS:
		fails.append("room.quick 없음")
	r.start()
	if not r.info(0).seats[0].has("hp") or r.info(0).seats[1].has("hp"):
		fails.append("hp 는 내 자리에만")
	# 아침 → 점심 : 토벌 battles 에 params
	srv.out.clear()
	r.stage_end = 0.0
	r.tick()
	var bl := srv.of(1, "battles")
	if bl.is_empty():
		fails.append("점심 battles 없음 (stage=%s)" % r.stage)
	else:
		var e: Dictionary = bl[0].list[0]
		for k in ["a", "fa", "ma", "ea", "b", "fb", "mb", "eb", "seed", "title", "foe", "policy", "tra", "trb", "tb"]:
			if not e.params.has(k):
				fails.append("params.%s 없음" % k)
		print("quest params 크기 ", JSON.stringify(e.params).length(), " 자 · title=", e.params.title, " foe=", e.params.foe)
	# 저녁 : 사람끼리 대전 뒤집힘
	r.stage_end = 0.0
	r.tick()                 # noon → evening_prep
	r.stage_end = 0.0
	srv.out.clear()
	r.tick()                 # evening_prep → evening
	var b1 := srv.of(1, "battles")
	var b2 := srv.of(2, "battles")
	if not b1.is_empty() and not b2.is_empty():
		var p1: Dictionary = b1[0].list[0].params
		var p2: Dictionary = b2[0].list[0].params
		if p1.a != p2.b or p1.b != p2.a or p1.seed != p2.seed or p1.policy.A != p2.policy.B:
			fails.append("뒤집힌 params 불일치")
		print("pvp foe ", p1.foe, " / ", p2.foe, " title ", p2.title)
	else:
		print("이번 저녁은 사람끼리 짝 아님 (봇 대전)")
	# 한마디
	srv.out.clear()
	r.on_say(1, 0)
	r.on_say(1, 1)          # 2초 안 — 무시
	r.on_say(2, 99)         # 범위 밖 — 무시
	r.on_say(2, 7)
	var says := srv.of(1, "say")
	if says.size() != 2 or says[0].text != "잘 부탁합니다" or says[1].text != "GG" or says[1].who != "나":
		fails.append("say 결과 %s" % str(says))
	if srv.of(2, "say").size() != 2:
		fails.append("say 는 모두에게")
	# 재접속 · 떠남 소식
	srv.out.clear()
	r.remove_peer(2)
	r.reattach(3, "tk2")
	var nw := srv.of(1, "news")
	if nw.is_empty():
		fails.append("재접속 소식 없음")
	else:
		print("news ", nw[0])
	srv.out.clear()
	r.on_leave(3)
	if srv.of(1, "news").is_empty() or r.seats[1].token != "" or r.seat_of(3) != -1:
		fails.append("떠남 처리")
	# 멸망 소식
	srv.out.clear()
	r._fallen(r.seats[1])
	if srv.of(1, "news").is_empty():
		fails.append("멸망 소식 없음")
	# 봇 등용 소식 (여러 번 진행해 보면 나올 때까지)
	var got := 0
	for i in 12:
		for s in r.seats:
			if not s.human:
				s.bot.pv += 60.0
		got += r._bot_news().size()
	print("봇 등용 소식 ", got, "건")
	if got == 0:
		fails.append("봇 등용 소식 0건")
	print("FAIL: ", fails if not fails.is_empty() else "없음")
	get_tree().quit(1 if not fails.is_empty() else 0)
