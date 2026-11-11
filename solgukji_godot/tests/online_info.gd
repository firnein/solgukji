extends Node
## 기록 탭의 다른 유저 정보 점검 (11/11 사용자: 다른 유저의 민심 · 핵심 유닛을 본다) —— 가짜 서버로 Room 을 직접 돌린다. TCP 포트를 쓰지 않는다.
## 실행: godot --headless --path . res://tests/online_info.tscn
## ① 서버 줄: 시작 뒤 사람 자리마다 hp(정수) · key(배열), 봇 자리에는 둘 다 없다. 시작 전(대기실)에는 둘 다 없다
## ② key 는 기초불신(기인 · 초월 · 불멸 · 신화) id 만 · 손패 + 편성판 모두 · 높은 등급 순 · 중복 없음. 전설(기인 아님) · 일반 카드는 없다
## ③ 새는 것이 없다: 줄의 키는 허용 목록 안에서만 (병사 수 · 덱 · 아이템 · 토큰 없음) · 메시지 크기
## ④ 핵심 유닛이 바뀌는 명령(조합) 뒤에는 다른 사람에게도 새 room 이 간다
## ⑤ 클라이언트 도우미 Online.peer_rows: 옛 서버 줄(hp · key 없음) → hp −1 · has_key false (화면에는 「—」), 엉뚱한 key 는 걸러진다, 나는 내 값으로, 봇은 빠진다

const ALLOWED := ["name", "human", "online", "ready", "dead", "pv", "foe", "hp", "key"]      # pv 는 이전부터 있던 키 (화면은 쓰지 않는다 —— 결정 ⑥)

class FakeSrv:
	var out := []        # [peer, msg]
	func send(peer: int, msg: Dictionary) -> void:
		out.append([peer, msg.duplicate(true)])
	func of(peer: int, t: String) -> Array:
		return out.filter(func(o): return o[0] == peer and o[1].t == t).map(func(o): return o[1])


func _ready() -> void:
	var fails := []
	var srv := FakeSrv.new()
	var r := Room.new(srv, "INFO", "test")
	r.add_human(1, "가", "tk1")
	r.add_human(2, "나", "tk2")
	r.add_human(3, "다", "tk3")
	# ① 대기실 —— 아직 Run 이 없다
	for row in r.info(0).seats:
		if row.has("hp") or row.has("key"):
			fails.append("대기실 줄에 hp · key 가 있다")
	r.start()
	var seats: Array = r.info(0).seats
	for k in seats.size():
		var row: Dictionary = seats[k]
		if row.human:
			if not (row.get("hp") is int) or int(row.hp) != int(r.seats[k].run.hp):
				fails.append("사람 자리 %d 에 hp 정수가 없다: %s" % [k, str(row.get("hp"))])
			if not (row.get("key") is Array):
				fails.append("사람 자리 %d 에 key 배열이 없다" % k)
		elif row.has("hp") or row.has("key"):
			fails.append("봇 자리 %d 에 hp · key 가 있다" % k)
	# ② 핵심 유닛 —— 자리 1 에 여러 등급을 쥐여 준다 (손패 + 편성판). 시작 패는 기초불신이 아니다
	var want := {8: [], 7: [], 6: [], 5: []}      # 5 = 기인
	var legend := ""
	var plain := ""
	for kk in DB.C:
		var c: Dictionary = DB.C[kk]
		if DB.is_foe(kk):
			continue
		var t := int(c.tier)
		if DB.is_kiin(kk):
			if want[5].size() < 2:
				want[5].append(kk)
		elif t >= 6 and t <= 8:
			if want[t].size() < 2:
				want[t].append(kk)
		elif t == 5 and legend == "":
			legend = kk
		elif t == 3 and plain == "":
			plain = kk
	var give_ids := []
	for t in [8, 7, 6, 5]:
		give_ids.append_array(want[t])
	var r1: Run = r.seats[1].run
	for kk in give_ids + [legend, plain]:
		r1.give(kk)
	var placed: String = want[7][0]      # 편성판에 앉힌 것도 가진 것이다
	r1.place(0, placed)
	r1.give(want[8][0])          # 같은 카드 두 장 —— 한 번만
	r1.hp = 37
	var info0: Dictionary = r.info(0)
	var key1: Array = info0.seats[1].key
	var ordered := []
	for t in [8, 7, 6, 5]:
		var part: Array = want[t].duplicate()
		part.sort()
		ordered.append_array(part)
	if key1 != ordered:
		fails.append("자리 1 의 key 가 다르다: %s / 기대 %s" % [str(key1), str(ordered)])
	for kk in key1:
		if not Room.is_urgent_unit(str(kk)):
			fails.append("key 에 기초불신이 아닌 카드: " + str(kk))
	if key1.has(legend) or key1.has(plain):
		fails.append("전설 · 일반 카드가 key 에 있다")
	if int(info0.seats[1].hp) != 37:
		fails.append("hp 가 갱신되지 않았다")
	if not info0.seats[0].key.is_empty() or not info0.seats[2].key.is_empty():
		fails.append("다른 자리의 key 가 비어 있지 않다: %s" % str(info0.seats[0].key))
	# ③ 새는 것 없음 · 크기
	for i in 3:
		for row in r.info(i).seats:
			for key in row:
				if not (key in ALLOWED):
					fails.append("줄에 허용되지 않은 키: " + str(key))
		var js := JSON.stringify(r.info(i))
		for secret in ["tk1", "tk2", "tk3", "troops", "soldier", "inv", "bag"]:
			if js.contains("\"%s" % secret):
				fails.append("info 에 %s 가 있다" % secret)
	var rowjs := JSON.stringify(r.info(1).seats[1])
	print("자리 줄(핵심 유닛 %d장) %d 바이트 · room 전체 %d 바이트 · %s" % [key1.size(), rowjs.length(), JSON.stringify(r.info(0)).length(), rowjs])
	# ④ 조합 —— 핵심 유닛이 바뀐 명령 뒤에는 모두에게 새 상태가 간다
	var forged := false
	for pk in ["c127", "K12", "c150", "L12"]:
		if not DB.C.has(pk):
			continue
		var fr: Run = r.seats[0].run
		for m in DB.RECOF.get(pk, []):
			if DB.C.has(str(m)):
				fr.give(str(m), 3)
			elif DB.IT.has(str(m)):
				fr.bag[str(m)] = 2
		srv.out.clear()
		r.on_cmd(1, "forge", [pk])
		if not fr.have(pk) > 0:
			continue
		forged = true
		var seen2 := srv.of(2, "state")
		var seen3 := srv.of(3, "state")
		if seen2.is_empty() or seen3.is_empty():
			fails.append("조합 뒤 다른 사람에게 새 상태가 가지 않았다 (%s)" % pk)
		else:
			var k2: Array = seen2[seen2.size() - 1].room.seats[0].key
			if not k2.has(pk):
				fails.append("다른 사람이 받은 자리 0 의 key 에 %s 가 없다: %s" % [pk, str(k2)])
			else:
				print("조합 %s 뒤 다른 사람이 받은 key: %s" % [pk, str(k2)])
		# 핵심 유닛이 안 바뀌는 명령은 다른 사람에게 보내지 않는다
		srv.out.clear()
		r.on_cmd(1, "auto_deploy", [])
		if not srv.of(2, "state").is_empty():
			fails.append("핵심 유닛이 안 바뀌었는데 다른 사람에게 상태를 보냈다")
		break
	if not forged:
		fails.append("조합을 시험하지 못했다 (재료 부족)")
	# ⑤ 클라이언트 도우미
	var room_new := {"you": 1, "seats": [
		{"name": "가", "human": true, "online": true, "dead": false, "hp": 80, "key": ["c177", want[8][0], "KILL", plain, want[8][0], 7]},
		{"name": "나", "human": true, "online": true, "dead": false, "hp": 10, "key": []},
		{"name": "봇1", "human": false, "online": false, "dead": false},
		{"name": "다", "human": true, "online": false, "dead": true, "hp": 0, "key": want[6]}]}
	var rows := Online.peer_rows(room_new, 55, [want[7][0], want[5][0]])
	if rows.size() != 3:
		fails.append("군웅 줄 수 %d (사람 3)" % rows.size())
	else:
		if not rows[0].me or rows[0].name != "나" or int(rows[0].hp) != 55 or rows[0].key != [want[7][0], want[5][0]]:
			fails.append("내 줄이 맨 위 · 내 값이어야 한다: %s" % str(rows[0]))
		if int(rows[1].hp) != 80 or rows[1].key.has("KILL") or rows[1].key.has(plain) or rows[1].key.count(want[8][0]) != 1:
			fails.append("엉뚱한 key 가 걸러지지 않았다: %s" % str(rows[1]))
		if not rows[2].dead or int(rows[2].hp) != 0 or rows[2].key != want[6] or rows[2].online:
			fails.append("멸망 줄: %s" % str(rows[2]))
	var room_old := {"you": 0, "seats": [
		{"name": "가", "human": true, "online": true, "dead": false, "ready": false, "pv": 5, "foe": ""},
		{"name": "나", "human": true, "online": true, "dead": false, "ready": false, "pv": 5, "foe": ""},
		{"name": "봇", "human": false, "online": false, "dead": false, "ready": true, "pv": 5, "foe": ""}]}
	var old_rows := Online.peer_rows(room_old, 90, [])
	if old_rows.size() != 2 or int(old_rows[1].hp) != -1 or old_rows[1].has_key or not old_rows[1].key.is_empty():
		fails.append("옛 서버 줄이 −1 · has_key false 가 아니다: %s" % str(old_rows))
	if int(old_rows[0].hp) != 90 or not old_rows[0].has_key:
		fails.append("옛 서버여도 내 줄은 내 값이어야 한다: %s" % str(old_rows[0]))
	var weird := Online.peer_rows({"you": -1, "seats": [{"name": "x", "human": true, "hp": "abc", "key": "zzz"}, 5, {"human": true, "hp": 250, "key": null}]}, 0, [])
	if weird.size() != 2 or int(weird[0].hp) != -1 or weird[0].has_key or int(weird[1].hp) != Run.HP_MAX:
		fails.append("깨진 줄 처리: %s" % str(weird))
	print("FAIL: ", fails if not fails.is_empty() else "없음")
	get_tree().quit(1 if not fails.is_empty() else 0)
