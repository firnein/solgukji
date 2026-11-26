extends Node
## 11/27 유니크 보급 새 규칙 점검 —— 실행: godot --headless --path . res://tests/uniq_offer.tscn
## ① 혼자 하기: 보급 때 하나만 보임 · 다시 뽑기 3번(본 것은 다시 안 나옴) · 4번째는 거절 · 고르면 가방에 · 가진 것 · 막힌 것 건너뜀
## ② 옛 저장(uniq_rerolled · 셋이 보이는 offer) 불러오기
## ③ Room 4인(사람 4): 네 사람의 순서가 서로 겹치지 않음(종류 16 이상) · 모자랄 때 겹침 최소 · 종류를 20 으로 늘려도 · 3 으로 줄여도 오류 없음
## ④ 사람 2 + 봇 2: 봇 순서도 사람 몫과 겹치지 않음(종류 16 이상) · 봇 장부가 보급에서 자기 순서의 것을 고른다
## ⑤ 6 · 8 을 보낸 방 만들기 → 4

var fails := []


class FakeSrv:
	var out := []
	func send(peer: int, msg: Dictionary) -> void:
		out.append([peer, msg])


func _fail(s: String) -> void:
	fails.append(s)
	printerr("FAIL ", s)


func _ready() -> void:
	var kinds0 := _kinds()
	print("유니크 종류(신화 재료) %d" % kinds0.size())
	_solo()
	_old_save()
	_room_case("지금 종류", 4, 0)
	_room_case("지금 종류 · 사람 2 + 봇 2", 2, 0)
	# 종류를 20 으로 늘린다 (가짜 유니크를 DB 에 잠깐 넣는다)
	var fake := []
	var i := 0
	while _kinds().size() < 20:
		var id := "zz_uq%d" % i
		DB.IT[id] = {"id": id, "name": "시험 유니크 %d" % i, "grade": "유니크", "tag": "창병", "pri": "atk", "pa": 0.1, "sec": "", "sa": 0.0, "rb": 0.0, "use": "", "slot": "weapon"}
		DB.MYTH_ITEMS[id] = true
		fake.append(id)
		i += 1
	_room_case("종류 20", 4, 0)
	_room_case("종류 20 · 사람 2 + 봇 2", 2, 0)
	_room_case("종류 20 · 사망룰 3", 4, 3)
	for id in fake:
		DB.IT.erase(id)
		DB.MYTH_ITEMS.erase(id)
	# 종류를 3 으로 줄인다
	var saved := DB.MYTH_ITEMS.duplicate()
	var keep: Array = _kinds().slice(0, 3)
	DB.MYTH_ITEMS.clear()
	for k in keep:
		DB.MYTH_ITEMS[k] = true
	_room_case("종류 3", 4, 0)
	DB.MYTH_ITEMS.clear()
	for k in saved:
		DB.MYTH_ITEMS[k] = true
	_seats()
	print("FAIL: ", fails if not fails.is_empty() else "없음")
	get_tree().quit(1 if not fails.is_empty() else 0)


static func _kinds() -> Array:
	return DB.IT.keys().filter(func(k): return DB.IT[k].grade == "유니크" and DB.MYTH_ITEMS.has(k))


## 유니크 보급 아침으로 옮겨 gain_item 을 부른다 (실제 경로)
static func _to_offer(run: Run) -> void:
	var p := int(DB.D.UNIQUE_PHASES[0])
	run.day = p / 3
	run.phase = p % 3
	run.gain_item()


## 이 유니크를 재료로 쓰는 신화 (없으면 "")
static func _myth_of(id: String) -> String:
	for k in DB.C:
		if int(DB.C[k].tier) >= 8 and not DB.is_foe(k) and Run.need_item(k) == id:
			return k
	return ""


func _solo() -> void:
	for sd in 20:
		var run := Run.new()
		run.new_game(300 + sd)
		_to_offer(run)
		if run.uniq_offer.size() != 1:
			_fail("혼자 %d: 보이는 것이 %d개" % [sd, run.uniq_offer.size()])
			continue
		if run.uniq_rerolls != 3:
			_fail("혼자 %d: 다시 뽑기 %d" % [sd, run.uniq_rerolls])
		var seen := [run.uniq_offer[0]]
		for t in 3:
			if not run.can_reroll_unique() or not run.reroll_unique():
				_fail("혼자 %d: %d번째 다시 뽑기 실패" % [sd, t + 1])
				break
			if run.uniq_offer.size() != 1 or seen.has(run.uniq_offer[0]):
				_fail("혼자 %d: 본 것이 다시 나옴 %s / %s" % [sd, str(run.uniq_offer), str(seen)])
			seen.append(run.uniq_offer[0])
		if run.uniq_rerolls != 0 or run.can_reroll_unique() or run.reroll_unique():
			_fail("혼자 %d: 4번째 다시 뽑기가 열려 있다" % sd)
		var last: String = run.uniq_offer[0]
		if not run.pick_unique(last) or int(run.bag.get(last, 0)) != 1 or not run.uniq_offer.is_empty():
			_fail("혼자 %d: 고르기 실패" % sd)
		if run.pick_unique(last) or run.reroll_unique():
			_fail("혼자 %d: 고른 뒤에도 보급이 열려 있다" % sd)
	# 가진 것 · 막힌 것 건너뛰기
	var kinds := _kinds()
	if kinds.size() >= 4:
		var run := Run.new()
		run.new_game(77)
		run.uniq_deck = kinds.slice(0, 4)
		run.bag[kinds[1]] = 1      # 가진 것
		var m := _myth_of(kinds[2])
		if m != "":
			run.locked = {m: {"by": "누군가"}}      # 막힌 것 (선점)
		_to_offer(run)
		var shown := [run.uniq_offer[0]]
		while run.reroll_unique():
			shown.append(run.uniq_offer[0])
		if shown[0] != kinds[0] or shown.has(kinds[1]) or (m != "" and shown.has(kinds[2])) or shown.size() != 4:
			_fail("건너뛰기: %s (순서 %s)" % [str(shown), str(kinds.slice(0, 4))])
		if shown.size() >= 2 and shown[1] != (kinds[3] if m != "" else kinds[2]):
			_fail("건너뛰기: 순서의 다음 것이 아니다 %s" % str(shown))
		# 열린 보급이 막히면 다음 것으로 (다시 뽑기 수는 그대로)
		var r2 := Run.new()
		r2.new_game(78)
		r2.uniq_deck = kinds.slice(0, 4)
		_to_offer(r2)
		var m0 := _myth_of(kinds[0])
		r2.locked = {m0: {"dead": 1}}
		if not r2.prune_unique_offer() or r2.uniq_offer != [kinds[1]] or r2.uniq_rerolls != 3:
			_fail("열린 보급 막힘: %s 남은 %d" % [str(r2.uniq_offer), r2.uniq_rerolls])
	print("① 혼자 하기 끝")


func _old_save() -> void:
	var kinds := _kinds()
	var run := Run.new()
	run.new_game(5)
	var d := run.to_dict()
	for k in ["uniq_rerolls", "uniq_deck", "uniq_seen", "uniq_avoid"]:
		d.erase(k)
	d.uniq_offer = kinds.slice(0, 3)
	d.uniq_rerolled = false
	d = JSON.parse_string(JSON.stringify(d))
	var r := Run.new()
	r.from_dict(d)
	if r.uniq_offer != [kinds[0]] or r.uniq_rerolls != 3:
		_fail("옛 저장: %s 남은 %d" % [str(r.uniq_offer), r.uniq_rerolls])
	if not r.reroll_unique() or r.uniq_offer != [kinds[1]] or not r.reroll_unique() or r.uniq_offer != [kinds[2]]:
		_fail("옛 저장: 남은 둘이 순서대로 나오지 않는다 %s" % str(r.uniq_offer))
	if not r.reroll_unique() or kinds.slice(0, 3).has(r.uniq_offer[0]):
		_fail("옛 저장: 셋을 다 본 뒤 새것이 나오지 않는다 %s" % str(r.uniq_offer))
	d.uniq_rerolled = true
	var r2 := Run.new()
	r2.from_dict(d)
	if r2.uniq_offer != [kinds[0]] or r2.uniq_rerolls != 0 or r2.reroll_unique() or not r2.pick_unique(kinds[0]):
		_fail("옛 저장(다시 뽑기 씀): %s 남은 %d" % [str(r2.uniq_offer), r2.uniq_rerolls])
	# 새 저장은 그대로 되살아난다
	var r3 := Run.new()
	r3.new_game(6)
	_to_offer(r3)
	r3.reroll_unique()
	var r4 := Run.new()
	r4.from_dict(JSON.parse_string(JSON.stringify(r3.to_dict())))
	if r4.uniq_offer != r3.uniq_offer or r4.uniq_rerolls != 2 or r4.uniq_seen != r3.uniq_seen or r4.uniq_deck != r3.uniq_deck:
		_fail("새 저장 되살리기: %s %d" % [str(r4.uniq_offer), r4.uniq_rerolls])
	print("② 옛 저장 끝")


func _room_case(title: String, humans_n: int, deaths: int) -> void:
	var K := _kinds().size()
	for sd in 10:
		var r := Room.new(FakeSrv.new(), "UQ", "test", 4, true, deaths)
		r.rng.seed = 900 + sd
		for i in humans_n:
			r.add_human(i + 1, "사람%d" % (i + 1), "tk%d" % i, false)
		r.start()
		if r.seats.size() != 4:
			_fail("%s: 자리 %d" % [title, r.seats.size()])
		var blocked: Dictionary = r.humans()[0].run.blocked_uniques()
		var avail := K - blocked.size()
		var per := mini(4, avail)
		var decks := []
		for s in r.humans():
			decks.append(s.run.uniq_deck)
		var bot_decks := []
		for s in r.seats:
			if not s.human:
				bot_decks.append(s.bot.get("uniq_deck", []))
		var cnt := {}
		for dk in decks + bot_decks:
			if dk.size() != per:
				_fail("%s %d: 순서 길이 %d (기대 %d)" % [title, sd, dk.size(), per])
			var u := {}
			for k in dk:
				u[k] = true
				cnt[k] = int(cnt.get(k, 0)) + 1
				if blocked.has(k):
					_fail("%s %d: 막힌 것이 순서에 %s" % [title, sd, k])
			if u.size() != dk.size():
				_fail("%s %d: 한 사람 순서 안에 겹침 %s" % [title, sd, str(dk)])
		# 사람끼리 겹침 —— 종류가 넉넉하면 0, 모자라면 한 종류가 ceil(자리 몫 / 종류) 번 넘게 쓰이지 않는다
		var hc := {}
		for dk in decks:
			for k in dk:
				hc[k] = int(hc.get(k, 0)) + 1
		var hmax := 0
		for k in hc:
			hmax = maxi(hmax, hc[k])
		var lim := ceili(float(humans_n * per) / float(maxi(1, avail)))
		if hmax > lim:
			_fail("%s %d: 사람끼리 한 종류가 %d번 (한도 %d)" % [title, sd, hmax, lim])
		if avail >= 16 and hmax > 1:
			_fail("%s %d: 종류가 넉넉한데 사람끼리 겹친다" % [title, sd])
		var allmax := 0
		for k in cnt:
			allmax = maxi(allmax, cnt[k])
		if allmax > ceili(float(4 * per) / float(maxi(1, avail))):
			_fail("%s %d: 봇 포함 한 종류가 %d번" % [title, sd, allmax])
		# 첫 칸(처음 보이는 것)은 종류가 자리 수 이상이면 서로 다르다
		if avail >= 4:
			var firsts := {}
			for dk in decks + bot_decks:
				firsts[dk[0]] = true
			if firsts.size() != decks.size() + bot_decks.size():
				_fail("%s %d: 처음 보이는 것이 겹친다" % [title, sd])
		# 실제 보급 —— 자기 순서대로 보인다 (막힌 것 · 가진 것이 없으면 4개 모두 자기 몫)
		for s in r.humans():
			var run: Run = s.run
			_to_offer(run)
			if per == 0:
				if not run.uniq_offer.is_empty():
					_fail("%s %d: 종류가 없는데 보급이 열린다" % [title, sd])
				continue
			var shown := [run.uniq_offer[0]]
			while run.reroll_unique():
				shown.append(run.uniq_offer[0])
			if shown.slice(0, per) != run.uniq_deck.slice(0, per):
				_fail("%s %d: 보인 것 %s ≠ 순서 %s" % [title, sd, str(shown), str(run.uniq_deck)])
			if shown.size() != mini(4, avail):
				_fail("%s %d: 본 수 %d" % [title, sd, shown.size()])
		# 봇 장부 —— 보급 아침까지 자라면 자기 순서의 것을 하나 가진다
		for s in r.seats:
			if s.human or bot_decks.is_empty() or per == 0:
				continue
			Run.bot_grow(s.bot, int(r.rng.seed), int(DB.D.UNIQUE_PHASES[0]))
			var bag: Dictionary = s.bot.forge_state.bag
			var got := bag.keys().filter(func(k): return DB.IT.has(k) and DB.IT[k].grade == "유니크")
			if got.size() != 1 or not s.bot.uniq_deck.has(got[0]):
				_fail("%s %d: 봇 %s 유니크 %s / 순서 %s" % [title, sd, s.name, str(got), str(s.bot.uniq_deck)])
	print("③ 방 %s (종류 %d · 사람 %d) 끝" % [title, K, humans_n])


func _seats() -> void:
	for v in [6, 8, 6.0, 8.0, 3, "8", null, 4]:
		if Room.valid_seats(v) != 4:
			_fail("valid_seats(%s) = %d" % [str(v), Room.valid_seats(v)])
	for n in [6, 8]:
		var r := Room.new(FakeSrv.new(), "S%d" % n, "test", n)
		if r.max_seats != 4:
			_fail("%d명 방 만들기 → %d" % [n, r.max_seats])
		r.add_human(1, "사람1", "tk", false)
		r.start()
		if r.seats.size() != 4:
			_fail("%d명 방 시작 자리 %d" % [n, r.seats.size()])
	print("⑤ 6 · 8인 → 4 끝")
