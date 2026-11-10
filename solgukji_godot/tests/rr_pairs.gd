extends Node
## 라운드로빈 저녁 짝 점검 (11/10 사용자) —— 순수 계산(Room.rr_round · rr_plan) + 방 하나(Room._begin_evening)로 확인. 시간 짧음.
## 실행: godot --headless --path . res://tests/rr_pairs.tscn
## ① 한 라운드에 한 자리가 두 번 나오지 않는다 ② 한 바퀴(7라운드)에 살아 있는 두 자리는 정확히 한 번씩 만난다(사람 대 사람 포함)
## ③ 멸망한 자리의 짝이던 산 자리는 떠돌이 군세와 붙고 — 그 횟수가 자리마다 고르다 ④ 같은 입력 · 같은 방 씨앗이면 같은 짝
## 마지막에 사람 8명인 방의 20 저녁 상대 분포 표를 찍는다.

class FakeSrv:
	func send(_peer: int, _msg: Dictionary) -> void:
		pass


var fails := []


func _ready() -> void:
	_pure()
	_room_table()
	_room_dead()
	print("FAIL: ", fails if not fails.is_empty() else "없음")
	get_tree().quit(1 if not fails.is_empty() else 0)


func _fail(s: String) -> void:
	if fails.size() < 12:
		fails.append(s)


func _orders() -> Array:
	var out := [[0, 1, 2, 3, 4, 5, 6, 7], [3, 7, 1, 0, 5, 2, 6, 4]]
	var r := RandomNumberGenerator.new()
	r.seed = 77
	for k in 4:
		var o := [0, 1, 2, 3, 4, 5, 6, 7]
		for i in range(7, 0, -1):
			var j := r.randi() % (i + 1)
			var t = o[i]
			o[i] = o[j]
			o[j] = t
		out.append(o)
	return out


## 순수 계산 —— 자리 배치 여럿 × 사람 수 1~8 × 멸망 0~3명
func _pure() -> void:
	var cases := 0
	var ords := _orders()
	for order in ords:
		# 멸망 없는 원 방식 —— 매 라운드 8자리가 한 번씩, 한 바퀴에 모든 쌍이 정확히 한 번
		var seen := {}
		for rd in 7:
			var used := {}
			for p in Room.rr_round(order, rd):
				for x in p:
					if used.has(x):
						_fail("라운드 %d 에서 자리 %d 가 두 번" % [rd, x])
					used[x] = true
				var key := "%d-%d" % [mini(p[0], p[1]), maxi(p[0], p[1])]
				seen[key] = int(seen.get(key, 0)) + 1
			if used.size() != 8:
				_fail("라운드 %d 에 빠진 자리 (%d/8)" % [rd, used.size()])
		if seen.size() != 28 or seen.values().any(func(v): return v != 1):
			_fail("한 바퀴에 모든 쌍이 정확히 한 번이 아니다 (%d쌍)" % seen.size())
		# 사람은 배치의 앞 h 번째 자리들, 멸망은 그중 d 명 (앞에서 · 뒤에서 · 가운데서)
		for h in range(1, 9):
			var humans: Array = order.slice(0, h)
			for d in range(0, mini(3, h - 1) + 1):
				for variant in 3:
					var dead := []
					for k in d:
						var idx := k if variant == 0 else ((h - 1 - k) if variant == 1 else ((k * 2 + 1) % h))
						dead.append(humans[idx])
					if dead.size() != d or _dup(dead):
						continue
					cases += 1
					_check_plan(order, dead)
	print("순수 점검: 자리 배치 %d가지 × 사람 1~8 × 멸망 0~3 = %d 경우" % [ords.size(), cases])


func _dup(a: Array) -> bool:
	for i in a.size():
		for j in range(i + 1, a.size()):
			if a[i] == a[j]:
				return true
	return false


func _check_plan(order: Array, dead: Array) -> void:
	var tag := "(멸망 %s)" % str(dead)
	var meet := {}              # 산 두 자리 쌍 -> 횟수 (한 바퀴)
	var ghost := {}             # 산 자리 -> 떠돌이 군세와 붙은 횟수 (20 저녁)
	var ghost_dead := {}        # 산 자리 -> {멸망 자리: 횟수} (한 바퀴)
	var alive := []
	for s in order:
		if not (s in dead):
			alive.append(s)
	for er in 20:
		var rd := er % 7
		var plan: Array = Room.rr_plan(order, rd, dead)
		if plan != Room.rr_plan(order.duplicate(), rd, dead.duplicate()):
			_fail("같은 입력인데 짝이 다르다 " + tag)
		var used := {}
		for p in plan:
			for x in p:
				if int(x) >= 0:
					if used.has(x):
						_fail("라운드 %d 에서 자리 %d 가 두 번 %s" % [rd, x, tag])
					used[x] = true
					if x in dead:
						_fail("멸망한 자리 %d 가 짝에 있다 %s" % [x, tag])
			if int(p[1]) < 0:
				ghost[p[0]] = int(ghost.get(p[0], 0)) + 1
				if er < 7:
					if not ghost_dead.has(p[0]):
						ghost_dead[p[0]] = {}
					var dd: int = -1 - int(p[1])
					ghost_dead[p[0]][dd] = int(ghost_dead[p[0]].get(dd, 0)) + 1
			elif er < 7:
				var key := "%d-%d" % [mini(p[0], p[1]), maxi(p[0], p[1])]
				meet[key] = int(meet.get(key, 0)) + 1
		for s in alive:      # 살아 있는 자리는 매 라운드 짝이 있다 (쉬지 않는다)
			if not used.has(s):
				_fail("라운드 %d 에서 산 자리 %d 가 쉰다 %s" % [rd, s, tag])
	# 한 바퀴 —— 산 두 자리는 정확히 한 번
	for i in alive.size():
		for j in range(i + 1, alive.size()):
			var key := "%d-%d" % [mini(alive[i], alive[j]), maxi(alive[i], alive[j])]
			if int(meet.get(key, 0)) != 1:
				_fail("%s 가 한 바퀴에 %d번 %s" % [key, int(meet.get(key, 0)), tag])
	# 떠돌이 군세 —— 한 바퀴에 멸망 자리마다 한 번씩, 20 저녁 합이 자리마다 고르다 (차 ≤ 1)
	var lo := 999
	var hi := 0
	for s in alive:
		var c := int(ghost.get(s, 0))
		lo = mini(lo, c)
		hi = maxi(hi, c)
		for dd in dead:
			var got := 0
			if ghost_dead.has(s):
				got = int(ghost_dead[s].get(dd, 0))
			if got != 1:
				_fail("자리 %d 가 한 바퀴에 멸망 %d 의 군세와 %d번 %s" % [s, dd, got, tag])
	if hi - lo > 1:
		_fail("떠돌이 군세 횟수가 고르지 않다 %d~%d %s" % [lo, hi, tag])


## 방 하나 —— 사람 8명 20 저녁: 사람마다 상대별 횟수 표 + 같은 씨앗이면 같은 짝
func _room_table() -> void:
	var r := _room(8, 4242)
	var names: Array = r.seats.map(func(s): return s.name)
	var cnt := {}      # 이름 -> {상대: 횟수}
	var sig := []
	for er in 20:
		r.day = er / 3
		r.phase = er % 3
		r._begin_evening()
		sig.append(str(r.pairs))
		for p in r.pairs:
			var a: Dictionary = r.seats[p[0]]
			var b: Dictionary = r.seats[p[1]]
			if a.foe == null or b.foe == null or a.foe.name != b.name or b.foe.name != a.name:
				_fail("저녁 준비 상대 정보가 짝과 다르다 (%d번째)" % er)
			for pr in [[a, b], [b, a]]:
				if not cnt.has(pr[0].name):
					cnt[pr[0].name] = {}
				cnt[pr[0].name][pr[1].name] = int(cnt[pr[0].name].get(pr[1].name, 0)) + 1
		if r.pairs.size() != 4:
			_fail("사람 8명 방의 짝이 %d 쌍" % r.pairs.size())
	print("20 저녁 상대 분포 (사람 8명 방 — 가로: 상대 · 칸 = 만난 횟수):")
	print("          " + "  ".join(names.map(func(n): return n.substr(0, 3))))
	for n in names:
		var row := []
		var ks := []
		for m in names:
			var v := int(cnt.get(n, {}).get(m, 0))
			row.append("." if m == n else str(v))
			if m != n:
				ks.append(v)
		ks.sort()
		print("  %s   %s   → %s" % [n, "    ".join(row), str(ks)])
		if ks != [2, 3, 3, 3, 3, 3, 3]:
			_fail("%s 의 상대 분포가 3·3·3·3·3·3·2 꼴이 아니다: %s" % [n, str(ks)])
	# 결정성 —— 같은 씨앗의 방은 같은 짝
	var r2 := _room(8, 4242)
	var sig2 := []
	for er in 20:
		r2.day = er / 3
		r2.phase = er % 3
		r2._begin_evening()
		sig2.append(str(r2.pairs))
	if sig != sig2:
		_fail("같은 씨앗인데 두 방의 짝이 다르다")
	var r3 := _room(8, 99)
	r3._begin_evening()
	print("결정성: 같은 씨앗 두 방의 20저녁 짝 %s · 다른 씨앗의 첫 저녁 짝은 %s" % ["같다" if sig == sig2 else "다르다", "다르다" if str(r3.pairs) != sig[0] else "같다(우연 가능)"])


## 멸망이 낀 방 —— 사람 4명 중 1 · 2명 멸망: 산 사람은 매 저녁 상대가 있고(사람 · 봇 · 떠돌이 군세), 산 사람끼리는 한 바퀴에 한 번씩
func _room_dead() -> void:
	for dead_n in [1, 2]:
		var r := _room(4, 31 + dead_n)
		for k in dead_n:
			r.seats[k].dead = true
		var hh := {}       # 산 사람 쌍(순서 있음) -> 한 바퀴 안 횟수
		var ghost_foes := 0
		for er in 20:
			r.day = er / 3
			r.phase = er % 3
			r._begin_evening()
			for i in range(dead_n, 4):
				var s: Dictionary = r.seats[i]
				if s.foe == null:
					_fail("멸망 %d명 방 %d번째 저녁에 산 사람 %s 의 상대가 없다" % [dead_n, er, s.name])
					continue
				if s.foe.epi == "떠돌이 군세":
					ghost_foes += 1
				if er < 7 and s.foe.human:
					var k := "%s-%s" % [s.name, s.foe.name]
					hh[k] = int(hh.get(k, 0)) + 1
			for k in dead_n:
				if r.seats[k].foe != null:
					_fail("멸망한 사람에게 상대가 정해졌다")
		var alive_h: int = 4 - dead_n
		var want: int = alive_h * (alive_h - 1)
		if hh.size() != want or hh.values().any(func(v): return v != 1):
			_fail("멸망 %d명 방 —— 산 사람끼리 한 바퀴 횟수 이상 %s" % [dead_n, str(hh)])
		print("멸망 %d명 방(사람 4): 산 사람끼리 짝 %d칸(한 바퀴 한 번씩) · 20 저녁 중 떠돌이 군세와 붙은 건수 %d" % [dead_n, hh.size(), ghost_foes])
		# 대전 계산도 한 번 돌려 본다 (떠돌이 군세와의 싸움이 되는지)
		r.stage_end = 0.0
		r._end_prep()
		for i in range(dead_n, 4):
			if r.seats[i].battles.is_empty() and r.seats[i].foe != null and r.seats[i].foe.epi != "사람":
				_fail("멸망 %d명 방 —— 봇 상대가 있는데 전투가 없다 (%s)" % [dead_n, r.seats[i].name])


func _room(humans_n: int, seed_: int) -> Room:
	var r := Room.new(FakeSrv.new(), "RR", "test")
	r.rng.seed = seed_
	for i in humans_n:
		r.add_human(i + 1, "사람%d" % (i + 1), "tk%d" % i)
	r.start()
	return r
