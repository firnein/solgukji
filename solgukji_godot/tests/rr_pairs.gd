extends Node
## 라운드로빈 저녁 짝 점검 (11/10 사용자, 11/11 자리 수 4 · 6 · 8 로 일반화) —— 순수 계산(Room.rr_round · rr_plan) + 방 하나(Room._begin_evening)로 확인. 시간 짧음.
## 실행: godot --headless --path . res://tests/rr_pairs.tscn [-- --full]
## ① 한 라운드에 한 자리가 두 번 나오지 않는다 ② 한 바퀴(N-1 라운드)에 살아 있는 두 자리는 정확히 한 번씩 만난다(사람 대 사람 포함)
## ③ 멸망한 자리의 짝이던 산 자리는 떠돌이 군세와 붙고 — 그 횟수가 자리마다 고르다 ④ 같은 입력 · 같은 방 씨앗이면 같은 짝
## ⑤ (11/11) 자리 수 N = 4 · 6 · 8 방: 빈자리만 봇 · 가득 차면 참가 거부 · 20 저녁 상대 분포 · 토너먼트(8강 틀 + 부전승)가 끝까지 간다
## 마지막에 사람 8명인 방의 20 저녁 상대 분포 표를 찍는다.

class FakeSrv:
	func send(_peer: int, _msg: Dictionary) -> void:
		pass


var fails := []


func _ready() -> void:
	for n in Room.SEAT_OPTIONS:
		_pure(n)
	for n in Room.SEAT_OPTIONS:
		_room_table(n)
	_room_dead(8, 4)
	_room_dead(6, 4)
	_room_dead(4, 4)
	_seats_rules()
	# 한 판 전체는 느리다(방 하나 30~160초) —— 기본은 셋(4석 사람 3 · 6석 사람 3 · 8석 사람 2), 인자 --full 이면 사람으로 가득 찬 방 · 혼자인 방까지
	var full_cfgs := [[4, 3], [6, 3], [8, 2]]
	if "--full" in OS.get_cmdline_user_args():
		full_cfgs = [[4, 3], [4, 4], [6, 3], [6, 6], [8, 2], [4, 1]]
	for cfg in full_cfgs:
		_full_room(cfg[0], cfg[1])
	print("FAIL: ", fails if not fails.is_empty() else "없음")
	get_tree().quit(1 if not fails.is_empty() else 0)


func _fail(s: String) -> void:
	if fails.size() < 12:
		fails.append(s)


func _orders(n: int) -> Array:
	var id := range(n)
	var rev := id.duplicate()
	rev.reverse()
	var out := [id, rev]
	var r := RandomNumberGenerator.new()
	r.seed = 77
	for k in 4:
		var o := id.duplicate()
		for i in range(n - 1, 0, -1):
			var j := r.randi() % (i + 1)
			var t = o[i]
			o[i] = o[j]
			o[j] = t
		out.append(o)
	return out


## 순수 계산 —— 자리 배치 여럿 × 사람 수 1~n × 멸망 0~3명
func _pure(n: int) -> void:
	var cases := 0
	var ords := _orders(n)
	for order in ords:
		# 멸망 없는 원 방식 —— 매 라운드 n자리가 한 번씩, 한 바퀴(n-1 라운드)에 모든 쌍이 정확히 한 번
		var seen := {}
		for rd in n - 1:
			var used := {}
			for p in Room.rr_round(order, rd):
				for x in p:
					if used.has(x):
						_fail("[%d석] 라운드 %d 에서 자리 %d 가 두 번" % [n, rd, x])
					used[x] = true
				var key := "%d-%d" % [mini(p[0], p[1]), maxi(p[0], p[1])]
				seen[key] = int(seen.get(key, 0)) + 1
			if used.size() != n:
				_fail("[%d석] 라운드 %d 에 빠진 자리 (%d/%d)" % [n, rd, used.size(), n])
		if seen.size() != n * (n - 1) / 2 or seen.values().any(func(v): return v != 1):
			_fail("[%d석] 한 바퀴에 모든 쌍이 정확히 한 번이 아니다 (%d쌍)" % [n, seen.size()])
		# 사람은 배치의 앞 h 번째 자리들, 멸망은 그중 d 명 (앞에서 · 뒤에서 · 가운데서)
		for h in range(1, n + 1):
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
					_check_plan(n, order, dead)
	print("순수 점검 [%d석]: 자리 배치 %d가지 × 사람 1~%d × 멸망 0~3 = %d 경우 (한 바퀴 %d라운드)" % [n, ords.size(), n, cases, n - 1])


func _dup(a: Array) -> bool:
	for i in a.size():
		for j in range(i + 1, a.size()):
			if a[i] == a[j]:
				return true
	return false


func _check_plan(n: int, order: Array, dead: Array) -> void:
	var tag := "[%d석](멸망 %s)" % [n, str(dead)]
	var cyc := n - 1
	var meet := {}              # 산 두 자리 쌍 -> 횟수 (한 바퀴)
	var ghost := {}             # 산 자리 -> 떠돌이 군세와 붙은 횟수 (20 저녁)
	var ghost_dead := {}        # 산 자리 -> {멸망 자리: 횟수} (한 바퀴)
	var alive := []
	for s in order:
		if not (s in dead):
			alive.append(s)
	for er in 20:
		var rd := er % cyc
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
				if er < cyc:
					if not ghost_dead.has(p[0]):
						ghost_dead[p[0]] = {}
					var dd: int = -1 - int(p[1])
					ghost_dead[p[0]][dd] = int(ghost_dead[p[0]].get(dd, 0)) + 1
			elif er < cyc:
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


## 방 하나 —— 사람 N명 20 저녁: 사람마다 상대별 횟수 표 + 같은 씨앗이면 같은 짝
func _room_table(n: int) -> void:
	var r := _room(n, 4242, n)
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
				_fail("[%d석] 저녁 준비 상대 정보가 짝과 다르다 (%d번째)" % [n, er])
			for pr in [[a, b], [b, a]]:
				if not cnt.has(pr[0].name):
					cnt[pr[0].name] = {}
				cnt[pr[0].name][pr[1].name] = int(cnt[pr[0].name].get(pr[1].name, 0)) + 1
		if r.pairs.size() != n / 2:
			_fail("사람 %d명 방의 짝이 %d 쌍" % [n, r.pairs.size()])
	# 기대 분포 —— 한 바퀴 n-1 저녁씩 돌아, 20 저녁 = 몫 바퀴 + 나머지 라운드 (나머지 개수의 상대가 한 번 더)
	var base := 20 / (n - 1)
	var rem := 20 % (n - 1)
	var want := []
	for i in n - 1:
		want.append(base + (1 if i < rem else 0))
	want.sort()
	print("20 저녁 상대 분포 (사람 %d명 방 — 가로: 상대 · 칸 = 만난 횟수):" % n)
	print("          " + "  ".join(names.map(func(x): return x.substr(0, 3))))
	for nm in names:
		var row := []
		var ks := []
		for m in names:
			var v := int(cnt.get(nm, {}).get(m, 0))
			row.append("." if m == nm else str(v))
			if m != nm:
				ks.append(v)
		ks.sort()
		print("  %s   %s   → %s" % [nm, "    ".join(row), str(ks)])
		if ks != want:
			_fail("[%d석] %s 의 상대 분포가 %s 꼴이 아니다: %s" % [n, nm, str(want), str(ks)])
	# 결정성 —— 같은 씨앗의 방은 같은 짝
	var r2 := _room(n, 4242, n)
	var sig2 := []
	for er in 20:
		r2.day = er / 3
		r2.phase = er % 3
		r2._begin_evening()
		sig2.append(str(r2.pairs))
	if sig != sig2:
		_fail("[%d석] 같은 씨앗인데 두 방의 짝이 다르다" % n)
	var r3 := _room(n, 99, n)
	r3._begin_evening()
	print("결정성 [%d석]: 같은 씨앗 두 방의 20저녁 짝 %s · 다른 씨앗의 첫 저녁 짝은 %s" % [n, "같다" if sig == sig2 else "다르다", "다르다" if str(r3.pairs) != sig[0] else "같다(우연 가능)"])


## 멸망이 낀 방 —— 사람 hn명 중 1 · 2명 멸망: 산 사람은 매 저녁 상대가 있고(사람 · 봇 · 떠돌이 군세), 산 사람끼리는 한 바퀴에 한 번씩
func _room_dead(n: int, hn: int) -> void:
	var cyc := n - 1
	for dead_n in [1, 2]:
		var r := _room(hn, 31 + dead_n, n)
		for k in dead_n:
			r.seats[k].dead = true
		var hh := {}       # 산 사람 쌍(순서 있음) -> 한 바퀴 안 횟수
		var ghost_foes := 0
		for er in 20:
			r.day = er / 3
			r.phase = er % 3
			r._begin_evening()
			for i in range(dead_n, hn):
				var s: Dictionary = r.seats[i]
				if s.foe == null:
					_fail("[%d석] 멸망 %d명 방 %d번째 저녁에 산 사람 %s 의 상대가 없다" % [n, dead_n, er, s.name])
					continue
				if s.foe.epi == "떠돌이 군세":
					ghost_foes += 1
				if er < cyc and s.foe.human:
					var k := "%s-%s" % [s.name, s.foe.name]
					hh[k] = int(hh.get(k, 0)) + 1
			for k in dead_n:
				if r.seats[k].foe != null:
					_fail("멸망한 사람에게 상대가 정해졌다")
		var alive_h: int = hn - dead_n
		var want: int = alive_h * (alive_h - 1)
		if hh.size() != want or hh.values().any(func(v): return v != 1):
			_fail("[%d석] 멸망 %d명 방 —— 산 사람끼리 한 바퀴 횟수 이상 %s" % [n, dead_n, str(hh)])
		print("멸망 %d명 방(%d석 · 사람 %d): 산 사람끼리 짝 %d칸(한 바퀴 한 번씩) · 20 저녁 중 떠돌이 군세와 붙은 건수 %d" % [dead_n, n, hn, hh.size(), ghost_foes])
		# 대전 계산도 한 번 돌려 본다 (떠돌이 군세와의 싸움이 되는지)
		r.stage_end = 0.0
		r._end_prep()
		for i in range(dead_n, hn):
			if r.seats[i].battles.is_empty() and r.seats[i].foe != null and r.seats[i].foe.epi != "사람":
				_fail("[%d석] 멸망 %d명 방 —— 봇 상대가 있는데 전투가 없다 (%s)" % [n, dead_n, r.seats[i].name])


## 자리 수 규칙 (11/11) —— 허용 값 · 없거나 이상하면 8 · 가득 차면 참가 거부 · 빈자리만 봇 · info.max
func _seats_rules() -> void:
	for kv in [[4, 4], [6, 6], [8, 8], [4.0, 4], [2, 8], [5, 8], [10, 8], [0, 8], [-4, 8], [null, 8], ["4", 8], [4.5, 8], [true, 8]]:
		if Room.valid_seats(kv[0]) != kv[1]:
			_fail("valid_seats(%s) = %d (기대 %d)" % [str(kv[0]), Room.valid_seats(kv[0]), kv[1]])
	for n in Room.SEAT_OPTIONS:
		var r := Room.new(FakeSrv.new(), "SEAT", "test", n)
		if r.max_seats != n or r.info(-1).get("max") != n:
			_fail("[%d석] 방 정보의 max 가 %s" % [n, str(r.info(-1).get("max"))])
		for i in n:
			if r.add_human(i + 1, "참가%d" % i, "t%d" % i) < 0:
				_fail("[%d석] %d번째 사람이 거부됐다" % [n, i + 1])
		if r.add_human(99, "넘침", "tx") != -1:
			_fail("[%d석] 가득 찼는데 참가가 됐다" % n)
		r.start()
		if r.seats.size() != n or r.seats.any(func(s): return not s.human):
			_fail("[%d석] 사람으로 가득한 방에 봇이 섞였다" % n)
		if r.add_human(98, "시작뒤", "ty") != -1:
			_fail("[%d석] 시작한 방에 참가가 됐다" % n)
	var d := Room.new(FakeSrv.new(), "DEF", "test")
	if d.max_seats != 8 or d.info(-1).max != 8:
		_fail("기본 자리 수가 8 이 아니다")
	var bad := Room.new(FakeSrv.new(), "BAD", "test", 5)
	if bad.max_seats != 8:
		_fail("이상한 자리 수(5)가 8 로 가지 않았다")
	print("자리 수 규칙: 허용 4 · 6 · 8, 이상하면 8, 가득 차면 참가 거부 · 시작한 방 거부 점검 끝")


## 한 판 전체 —— 점검 모드 방(자리 n · 사람 hn)을 끝(over)까지 직접 돌린다. 빈자리만 봇 · 20 저녁 · 토너먼트 라운드 수 · 모두 끝에 닿는가
func _full_room(n: int, hn: int) -> void:
	var r := _room(hn, 777 + n * 10 + hn, n)
	var bots_n := r.seats.filter(func(s): return not s.human).size()
	if r.seats.size() != n or bots_n != n - hn:
		_fail("[%d석 · 사람 %d] 봇 %d (기대 %d), 자리 %d" % [n, hn, bots_n, n - hn, r.seats.size()])
	var names: Array = r.seats.map(func(s): return s.name)
	if names.size() != _uniq(names).size():
		_fail("[%d석] 이름이 겹친다 %s" % [n, str(names)])
	var evenings := 0
	var tour_rounds := []
	var guard := 0
	var t0 := Time.get_ticks_msec()
	var phases := []      # 페이즈마다 본 단계 순서 (11/11: 점심은 1~3일차만)
	var last_no := -1
	while r.stage != "over" and guard < 400:
		guard += 1
		if r.stage == "evening_prep" and r.tour == null:
			evenings += 1
		if r.stage == "evening" and r.tour != null:
			tour_rounds.append([r.tour.round, r.tour.res[r.tour.round].size()])
		if r.stage_no != last_no:
			last_no = r.stage_no
			if r.stage == "morning":
				phases.append({"day": r.day, "stages": []})
			if not phases.is_empty():
				phases[phases.size() - 1].stages.append(r.stage)
			if r.info(0).get("noon") != Room.has_noon(r.day):
				_fail("[%d석] 방 정보 noon 이 일차 %d 와 다르다" % [n, r.day])
		r.stage_end = 0.0
		r.tick()
	if r.stage != "over":
		_fail("[%d석 · 사람 %d] 끝나지 않았다 (stage=%s 단계 %d)" % [n, hn, r.stage, guard])
		return
	if evenings != 20:
		_fail("[%d석 · 사람 %d] 대전 준비 %d번 (기대 20)" % [n, hn, evenings])
	# 11/11 단계 순서 —— 1~3일차(페이즈 0~8): 준비 · 토벌 · 대전 준비 · 대전 / 4일차~(9~19): 준비 · 대전 준비 · 대전 / 21번째(토너먼트): 준비 · 대전 준비 · 대전 × 라운드
	var noons := 0
	for k in phases.size():
		var st: Array = phases[k].stages
		var want_st := ["morning", "noon", "evening_prep", "evening"] if k < 9 else ["morning", "evening_prep", "evening"]
		if k == 20:
			want_st = ["morning", "evening_prep"]
			for tr in tour_rounds.size():
				want_st.append("evening")
		if st != want_st:
			_fail("[%d석 · 사람 %d] %d번째 페이즈 단계 %s (기대 %s)" % [n, hn, k + 1, str(st), str(want_st)])
		noons += st.count("noon")
	if phases.size() != 21 or noons != 9:
		_fail("[%d석 · 사람 %d] 페이즈 %d개 · 점심 %d번 (기대 21 · 9)" % [n, hn, phases.size(), noons])
	# 토너먼트 —— 8명: 8강 4 · 4강 2 · 결승 1 / 6명: 8강 2 · 4강 2 · 결승 1 / 4명: 4강 2 · 결승 1
	var want := [[0, 4], [1, 2], [2, 1]] if n == 8 else ([[0, 2], [1, 2], [2, 1]] if n == 6 else [[1, 2], [2, 1]])
	# 사람이 모두 일찍 떨어지면 끝까지 다 안 볼 수도 있다 (점검 모드는 멸망하지 않으니 토너먼트 패배만) —— 라운드가 계속 이어지는지 본다
	if tour_rounds.size() != want.size() or str(tour_rounds) != str(want):
		_fail("[%d석 · 사람 %d] 토너먼트 라운드 %s (기대 %s)" % [n, hn, str(tour_rounds), str(want)])
	for s in r.humans():
		if s.run.over == null:
			_fail("[%d석] %s 의 끝(over)이 없다" % [n, s.name])
	var champs := r.humans().filter(func(s): return s.run.over != null and s.run.over.win).size()
	if phases.size() == 21:
		print("  단계 순서: 1~9번째 페이즈 %s · 10~20번째 %s · 21번째 %s" % [str(phases[0].stages), str(phases[9].stages), str(phases[20].stages)])
	print("한 판 [%d석 · 사람 %d · 봇 %d]: 저녁 %d · 토너먼트 %s · 우승 사람 %d · %.1f초" % [n, hn, bots_n, evenings, str(tour_rounds), champs, (Time.get_ticks_msec() - t0) / 1000.0])
	if champs > 1:
		_fail("[%d석] 우승한 사람이 %d명" % [n, champs])
	# 순위 글 —— 탈락한 사람의 순위가 인원에 맞는다
	for s in r.humans():
		if not s.run.over.win and str(s.run.over.msg).contains("최종") and n == 6 and str(s.run.over.msg).contains("5~8위"):
			_fail("[6석] 8강 탈락 순위 글이 5~8위 (5~6위여야)")


func _uniq(a: Array) -> Array:
	var out := []
	for x in a:
		if not out.has(x):
			out.append(x)
	return out


func _room(humans_n: int, seed_: int, n_seats := 8) -> Room:
	var r := Room.new(FakeSrv.new(), "RR", "test", n_seats)
	r.rng.seed = seed_
	for i in humans_n:
		r.add_human(i + 1, "사람%d" % (i + 1), "tk%d" % i)
	r.start()
	return r
