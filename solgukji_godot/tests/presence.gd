extends Node
## 온라인 존재감 점검 (11/12) —— 가짜 서버로 Room 을 직접 돌려 상태 아이콘 · 상대 예고 · 연승 · 민심 위기 · 설욕전 · 멸망 띠를 확인한다.
## 실행: godot --headless --path . res://tests/presence.tscn

class FakeSrv:
	var out := []        # [peer, msg]
	func send(peer: int, msg: Dictionary) -> void:
		out.append([peer, msg])
	func of(peer: int, t: String) -> Array:
		return out.filter(func(o): return o[0] == peer and o[1].t == t).map(func(o): return o[1])
	func news_text(peer: int) -> Array:
		var a := []
		for m in of(peer, "news"):
			for it in m.list:
				a.append(it)
		return a


func _ready() -> void:
	var fails := []
	var srv := FakeSrv.new()
	var r := Room.new(srv, "PRES", "fast")
	r.add_human(1, "가", "tk1")
	r.add_human(2, "나", "tk2")
	r.add_human(3, "다", "tk3")
	r.start()
	# ① 상태 —— 처음은 대기, 명령 뒤 🔨, 준비 완료 뒤 ✔. 바뀔 때 act_st 가 모두에게
	if str(r.info(0).seats[1].get("st", "")) != "idle":
		fails.append("처음 상태 %s (기대 idle)" % str(r.info(0).seats[1].get("st")))
	if r.info(0).seats[4].has("st"):
		fails.append("봇 줄에 st")
	srv.out.clear()
	r._status_sync()
	r.on_cmd(2, "do_draw", [])
	r._status_sync()
	var sts := srv.of(1, "act_st")
	if sts.is_empty() or str(sts[-1].st[1]) != "busy":
		fails.append("명령 뒤 act_st busy 없음 %s" % str(sts))
	r.on_ready(3, true, r.stage_no)
	srv.out.clear()
	r._status_sync()
	sts = srv.of(1, "act_st")
	if sts.is_empty() or str(sts[-1].st[2]) != "ready":
		fails.append("준비 뒤 ready 아님 %s" % str(sts))
	srv.out.clear()
	r._status_sync()
	if not srv.of(1, "act_st").is_empty():
		fails.append("바뀐 것이 없는데 act_st 를 또 보냈다")
	r.stage = "noon"
	r.seats[0].battles = [{"title": "x"}]
	r.seats[0].watched = false
	if r.seat_status(r.seats[0]) != "quest":
		fails.append("토벌 중 아님")
	r.stage = "evening"
	if r.seat_status(r.seats[0]) != "pvp":
		fails.append("대전 중 아님")
	r.seats[0].battles = []
	r.stage = "morning"
	r.on_ready(3, false, r.stage_no)
	# ② 상대 예고 —— 자리 배치를 고정하고 오늘 밤 사람끼리 짝을 찾는다
	r.rr_order = range(r.seats.size())
	var a := -1
	var b := -1
	for ph in 3:
		r.phase = ph
		for i in 3:
			if r.tonight_foe(i) >= 0:
				a = i
				b = r.tonight_foe(i)
				break
		if a >= 0:
			break
	if a < 0:
		fails.append("사람끼리 오늘 밤 짝을 못 찾았다")
	else:
		if r.tonight_foe(b) != a:
			fails.append("tonight_foe 가 대칭이 아니다")
		var fr: Run = r.seats[a].run
		for m in DB.RECOF.get("c127", []):
			if DB.C.has(str(m)):
				fr.give(str(m), 3)
			elif DB.IT.has(str(m)):
				fr.bag[str(m)] = 2
		srv.out.clear()
		r.on_cmd(r.seats[a].peer, "forge", ["c127"])
		var got_b := srv.news_text(r.seats[b].peer).filter(func(it): return str(it.text).begins_with("오늘 밤 상대"))
		var other := 3 - a - b
		var got_o := srv.news_text(r.seats[other].peer).filter(func(it): return str(it.text).begins_with("오늘 밤 상대"))
		print("상대 예고 ", got_b)
		if got_b.size() != 1 or not got_o.is_empty():
			fails.append("상대 예고 —— 상대 %d건 · 다른 사람 %d건" % [got_b.size(), got_o.size()])
		r.stage = "evening_prep"
		if r.tonight_foe(a) >= 0:
			fails.append("저녁 준비에는 예고하지 않는다")
		r.stage = "morning"
	# ③ 판세 —— 3연승 · 민심 위기(한 번만), 본인 빼고
	for k in 3:
		r._streak_track(r.seats[0], true)
	r.seats[1].run.hp = 25
	srv.out.clear()
	r._flush_presence_news()
	var n2 := srv.news_text(2).map(func(it): return str(it.text))
	var n1 := srv.news_text(1).map(func(it): return str(it.text))
	print("판세 소식 ", n2)
	if not n2.has("가 3연승 중") or n1.has("가 3연승 중"):
		fails.append("연승 소식 %s / 본인 %s" % [str(n2), str(n1)])
	if not n1.has("나 민심 25, 위태롭습니다"):
		fails.append("민심 위기 소식 %s" % str(n1))
	srv.out.clear()
	r._flush_presence_news()
	if not srv.of(2, "news").is_empty():
		fails.append("두 번째 flush 에 또 소식 (연승이 늘지 않았고 위기는 한 번만)")
	# ④ 설욕전
	r._beat_track(r.seats[0], r.seats[1], false, false)      # 가가 나에게 졌다
	if not bool(r._foe_for(r.seats[0], r.seats[1]).get("revenge", false)):
		fails.append("설욕전 표시 없음")
	if bool(r._foe_for(r.seats[1], r.seats[0]).get("revenge", false)):
		fails.append("이긴 쪽에 설욕전")
	r._beat_track(r.seats[0], r.seats[1], true, false)       # 설욕
	if bool(r._foe_for(r.seats[0], r.seats[1]).get("revenge", false)):
		fails.append("설욕한 뒤에도 설욕전")
	# ⑤ 멸망 띠 —— 다른 사람에게 hot + band fall + 남은 군주
	srv.out.clear()
	r.seats[2].dead = true
	r._fallen(r.seats[2])
	var fl := srv.news_text(1)
	print("멸망 ", fl)
	if fl.is_empty() or str(fl[0].get("band", "")) != "fall" or int(fl[0].get("hot", 0)) != 1 or not str(fl[0].text).contains("남은 군주 %d명" % (r.seats.size() - 1)):
		fails.append("멸망 띠 %s" % str(fl))
	if not srv.of(3, "news").is_empty():
		fails.append("멸망한 본인에게 멸망 띠")
	print("FAIL: ", fails if not fails.is_empty() else "없음")
	get_tree().quit(1 if not fails.is_empty() else 0)
