extends Node
## 11/12 최후 1인 판 길이 점검 —— 실행: godot --headless --path . res://tests/last_one.tscn [-- --rooms=6 --humans=2 --seats=4 --mode=normal]
## 서버 없이 Room 을 직접 돌린다(가짜 서버). 사람 자리는 모두 아무것도 하지 않는 사람 —— 단계마다 봇이 대신 준비한다(Run.bot_prepare, 실제 '자리 비움'과 같다).
## 방마다: 끝난 일차 · 천하 통일한 자리 · 자리마다 멸망한 일차와 순위 · 8일차 아침 민심. 확인: 판이 끝나는가(최후 1인) · 순위가 매겨지는가.
## 밸런스 측정용이 아니라 판 길이 확인용 (사람 대역이 봇 대행이라 실제 사람보다 약하다)

class FakeSrv:
	func send(_peer: int, _msg: Dictionary) -> void:
		pass


func _ready() -> void:
	var args := {}
	for s in OS.get_cmdline_user_args():
		var kv := s.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	var rooms := int(args.get("rooms", "6"))
	var hn := int(args.get("humans", "2"))
	var seats_n := int(args.get("seats", "4"))
	var mode := str(args.get("mode", "normal"))
	var fails := []
	var days := []
	var hum_end := []      # 사람 자리의 멸망(또는 끝) 일차
	for n in rooms:
		var r := Room.new(FakeSrv.new(), "LO%d" % n, mode, seats_n)
		r.rng.seed = 500 + n
		for i in hn:
			r.add_human(i + 1, "사람%d" % (i + 1), "tk%d" % i)
		r.start()
		var fall_day := {}
		var hp8 := {}
		var guard := 0
		while r.stage != "over" and guard < 600:
			guard += 1
			r.stage_end = 0.0
			r.tick()
			for s in r.seats:
				if s.dead and not fall_day.has(s.name):
					fall_day[s.name] = r.day + 1
			if r.day == 7 and hp8.is_empty():
				for s in r.seats:
					hp8[s.name] = r._hp_of(s)
		if r.stage != "over":
			fails.append("방 %d: %d번 넘겨도 끝나지 않았다 (%d일차)" % [n, guard, r.day + 1])
			continue
		var alive := r.seats.filter(func(s): return not s.dead)
		if mode == "test" and (r.winner == "" or alive.size() != 1):
			fails.append("방 %d: 최후 1인이 아니다 (남은 %d · winner %s)" % [n, alive.size(), r.winner])
		for s in r.seats:
			if s.human and (s.run.over == null or not s.run.over.has("rank")):
				fails.append("방 %d: %s 의 over 에 rank 가 없다" % [n, s.name])
			if s.human:
				hum_end.append(int(fall_day.get(s.name, r.day + 1)))
			if not s.has("rank") and (s.dead or alive.size() <= 1):
				fails.append("방 %d: %s 에 순위가 없다" % [n, s.name])
		days.append(r.day + 1)
		var line := []
		for s in r.seats:
			line.append("%s%s %s위(%s)" % [s.name, "" if s.human else "[봇]", str(s.get("rank", "-")), ("%d일 멸망" % fall_day[s.name]) if fall_day.has(s.name) else "생존"])
		print("방 %d: %d일차에 끝 · 천하 통일 %s · %s · 8일차 아침 민심 %s" % [n, r.day + 1, r.winner if r.winner != "" else "(없음)", " / ".join(line), str(hp8)])
	var avg := 0.0
	for d in days:
		avg += d
	var havg := 0.0
	for d in hum_end:
		havg += d
	print("판 %d개 · 끝난 일차 %s · 평균 %.1f일 · 사람 자리가 끝난 평균 %.1f일" % [days.size(), str(days), avg / maxf(1, days.size()), havg / maxf(1, hum_end.size())])
	print("FAIL: ", fails if not fails.is_empty() else "없음")
	get_tree().quit(1 if not fails.is_empty() else 0)
