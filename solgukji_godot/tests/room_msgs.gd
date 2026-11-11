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
	if not r.info(0).seats[0].has("hp") or not r.info(0).seats[1].has("hp"):      # 11/11 사용자: 다른 사람의 민심도 기록 탭에 보인다 (tests/online_info 가 자세히)
		fails.append("hp 는 사람 자리마다")
	# 11/10 긴급 등용 —— 기인 이상(기인 · 초월 · 불멸 · 신화)만 hot, 전설(5, 기인 아님) 이하는 아님. 본인에게는 안 간다. 소식에 id · when
	for kv in [["K12", true], ["c127", true], ["L12", true], ["c177", true], ["c150", true], ["c140", true], ["c3", false]]:
		if DB.C.has(kv[0]) and Room.is_urgent_unit(kv[0]) != kv[1]:
			fails.append("is_urgent_unit(%s) 가 %s 여야 한다 (등급 %d)" % [kv[0], str(kv[1]), DB.C[kv[0]].tier])
	for k5 in DB.C:
		if DB.C[k5].tier == 5 and not DB.is_kiin(k5) and not DB.is_foe(k5) and Room.is_urgent_unit(k5):
			fails.append("전설(5)이 긴급: " + k5)
			break
	for pick_k in ["c127", "K12"]:
		var fr: Run = r.seats[0].run
		for m in DB.RECOF.get(pick_k, []):
			if DB.C.has(str(m)):
				fr.give(str(m), 3)
			elif DB.IT.has(str(m)):
				fr.bag[str(m)] = 2
		srv.out.clear()
		r.on_cmd(1, "forge", [pick_k])
		if not fr.inv.has(pick_k):
			print("(조합 재료를 맞추지 못해 on_cmd 경로는 건너뜀: %s)" % pick_k)
			continue
		var hot := srv.of(2, "news")
		if hot.is_empty() or not hot[0].list[0].has("hot") or not hot[0].list[0].has("id") or not hot[0].list[0].has("when"):
			fails.append("긴급 등용 알림이 다른 사람에게 가지 않았다 (%s): %s" % [pick_k, str(hot)])
		else:
			print("긴급 등용 알림 ", hot[0].list[0])
		if not srv.of(1, "news").is_empty():
			fails.append("등용한 본인에게도 소식이 갔다")
		var n0: Array = r.seats[1].run.news
		if n0.is_empty() or not n0[0].has("id") or not n0[0].has("when"):
			fails.append("상대 Run.news 에 id · when 없음")
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
	# 한마디 이모티콘 (11/10) —— 번호만 · 범위 밖 거부 · 글과 같은 2초 간격 · 모두에게 · 옛 클라이언트용 종류 분리
	if r.info(0).get("emote_n", 0) != Room.EMOTE_N or Room.EMOTE_N != Icons.EMOTES.size() or Icons.EMOTE_NAMES.size() != Icons.EMOTES.size():
		fails.append("emote_n(%s) · Room.EMOTE_N(%d) · Icons.EMOTES(%d) 불일치" % [str(r.info(0).get("emote_n", 0)), Room.EMOTE_N, Icons.EMOTES.size()])
	srv.out.clear()
	for s0 in r.seats:
		s0.say_t = -100.0
	r.on_emote(1, 3)
	r.on_emote(1, 4)         # 2초 안 — 무시
	var em := srv.of(1, "emote")
	if em.size() != 1 or int(em[0].i) != 3 or em[0].who != "가" or srv.of(2, "emote").size() != 1:
		fails.append("emote 결과(모두에게 1개) %s" % str(em))
	if not srv.of(1, "say").is_empty():
		fails.append("emote 가 say 로 갔다")
	srv.out.clear()
	r.on_say(1, 0)           # 방금 emote 를 보냈으니 글도 2초 안 — 간격을 공유
	if not srv.of(1, "say").is_empty():
		fails.append("emote 직후 say 가 간격 제한을 건너뛰었다")
	for bad in [-1, Room.EMOTE_N, 99]:
		for s0 in r.seats:
			s0.say_t = -100.0
		srv.out.clear()
		r.on_emote(2, bad)
		if not srv.of(1, "emote").is_empty():
			fails.append("범위 밖 이모티콘 %d 가 통과" % bad)
	for s0 in r.seats:
		s0.say_t = -100.0
	srv.out.clear()
	r.on_emote(2, Room.EMOTE_N - 1)          # 범위 밖이 간격을 먹지 않았다 + 마지막 번호는 통과
	if srv.of(1, "emote").size() != 1:
		fails.append("마지막 번호 이모티콘 거부")
	srv.out.clear()
	r.on_emote(77, 0)        # 방에 없는 연결 — 무시
	if not srv.out.is_empty():
		fails.append("방 밖 연결의 emote 가 통과")
	for s0 in r.seats:
		s0.say_t = -100.0
	# 재접속 · 떠남 소식
	srv.out.clear()
	r.remove_peer(2)
	r.reattach(3, "tk2")
	var nw := srv.of(1, "news")
	if nw.is_empty():
		fails.append("재접속 소식 없음")
	else:
		print("news ", nw[0])
		if not nw[0].list[0].has("id") or not nw[0].list[0].has("when"):
			fails.append("소식에 id · when 없음")
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
