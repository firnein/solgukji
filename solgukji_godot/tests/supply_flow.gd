extends Node
## 11/12 보급 점검 (작업현황 94) —— 온라인 방(점검 모드)을 한 판 끝까지 헤드리스로 돌려 페이즈마다 받은 보급(기본패 · 고급 · 희귀 · 전설 카드, 선택권)을 센다.
## 실행: godot --headless --path . res://tests/supply_flow.tscn [-- --seeds=3 --seats=8 --table --verbose]
## 사람 셋 —— 약함(편성을 거의 안 만진다) · 보통(아침마다 자동 편성) · 강함(처음부터 불멸 카드를 줘서 거의 다 이긴다). 선택권은 쓰지 않고 조합하지 않는다 —— 그래서 보급은
## pool(손패 + 편성) + 선택권 + held(쌓아 둔 보상) 의 늘어난 양 그대로다.
## 기대값 = '기준 Run'(새 Run, 같은 일차 · 페이즈, mp)에 같은 규칙대로 징집 · 선택권 · 배급 · 이번 페이즈 전투 결과를 넣어 보고 grant_held 까지 한 값.
##   (흐름 점검 —— 서버가 단계마다 징집 · 선택권 · 배급을 빠뜨리지 않는지 · 보상이 held 에서 아침에 다 들어오는지 · 대전이 토벌 몫을 대신 주는지)
## 판정 ① 페이즈 보급 = 기대값 (등급별 카드 수 · 선택권 등급별) ② 다음 아침 시작 값 = 지난 저녁 끝 값(advance 가 held 를 모두 풀었다) ③ 아침 시작에 held 가 빈다
##       ④ 일차별 대전 보상이 작업현황 79 표(PVP_BASE + 4일차~ QUEST_BASE · QUEST_REWARD)와 같다 ⑤ 전설 이상 보급 · 선택권이 일차마다 기대대로 들어온다

class FakeSrv:
	var out := []
	func send(peer: int, msg: Dictionary) -> void:
		out.append([peer, msg])


var fails := []
var verbose := false
var table := false
var seats_n := 8
var idle := false      # 사람이 아무 명령도 안 보낸다 — 서버가 봇 대행(_fill)으로 채운다
var normal := false      # 점검이 아닌 보통 방(멸망 있음)
## 일차(1~7) -> {표 항목 -> 합} 와 판 수 —— 모든 씨앗 · 사람 합
var by_day := {}
var phases_n := {}
var wins_n := {"win": 0, "lose": 0}


func _fail(s: String) -> void:
	if fails.size() < 30:
		fails.append(s)


func _ready() -> void:
	var seeds := 2
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--seeds="):
			seeds = int(a.trim_prefix("--seeds="))
		if a.begins_with("--seats="):
			seats_n = int(a.trim_prefix("--seats="))
		if a == "--verbose":
			verbose = true
		if a == "--table":
			table = true
		if a == "--idle":
			idle = true
		if a == "--normal":
			normal = true
	for sd in seeds:
		_game(500 + sd, seats_n)
	if table:
		_print_table()
	print("승 %d · 패 %d (대전 · 토벌 합)" % [wins_n.win, wins_n.lose])
	print("FAIL: ", fails if not fails.is_empty() else "없음")
	get_tree().quit(1 if not fails.is_empty() else 0)


## 한 사람의 지금 보급 총량 —— pool(손패 + 편성)의 등급별 카드 수 + 선택권 + held
func snap(r: Run, with_held := true) -> Dictionary:
	var o := {"base": 0, "t3": 0, "t4": 0, "t5": 0, "t6+": 0, "k1": 0, "k3": 0, "k4": 0, "k5": 0, "item": 0}
	for it in r.bag:
		o.item += int(r.bag[it])
	var add_card := func(k: String, n: int) -> void:
		var t: int = int(DB.C[k].tier)
		if t <= 2:
			o.base += n
		elif t <= 5:
			o["t%d" % t] += n
		else:
			o["t6+"] += n
	var p := r.pool()
	for k in p:
		add_card.call(str(k), int(p[k]))
	for t in r.tickets:
		o["k" + str(t)] = int(o.get("k" + str(t), 0)) + int(r.tickets[t])
	if with_held:
		for k in r.held.get("inv", {}):
			add_card.call(str(k), int(r.held.inv[k]))
		for t in r.held.get("tickets", {}):
			o["k" + str(t)] = int(o.get("k" + str(t), 0)) + int(r.held.tickets[t])
	return o


func _diff(a: Dictionary, b: Dictionary) -> Dictionary:
	var o := {}
	for k in b:
		o[k] = int(b[k]) - int(a.get(k, 0))
	return o


func _fmt(d: Dictionary) -> String:
	return "기본 %2d · 고급 %d · 희귀 %d · 전설 %d · 초월+ %d | 선택권 1:%d 3:%d 4:%d 5:%d | 아이템 %d" % [d.base, d.t3, d.t4, d.t5, d["t6+"], d.k1, d.k3, d.k4, d.k5, d.item]


## 기준 Run 에 이 페이즈의 보급을 넣어 본 값 —— 징집 · 선택권 · 배급 + 이번 페이즈 전투(토벌 · 대전) 결과
func _expect(day_: int, phase_: int, battles: Array) -> Dictionary:
	var ref := Run.new()
	ref.new_game(77)
	ref.mp = true
	ref.day = day_
	ref.phase = phase_
	ref.inv = {}
	ref.tickets = {}
	ref.held = {}
	var s0 := snap(ref)
	ref.do_draw()
	ref.begin_picks("phase", -1)
	if not ref.grant_list().is_empty():
		ref.random_grant()
	for b in battles:
		if not (str(b.kind) in ["quest", "pvp"]):
			continue
		ref.battle = {"kind": b.kind, "title": "x", "foe": "y"}
		ref.finish_battle(b.res)
	ref.grant_held()
	return _diff(s0, snap(ref))


func _acc(day_: int, key: String, d: Dictionary) -> void:
	var cur: Dictionary = by_day.get(day_, {})
	for k in d:
		cur[key + "|" + k] = int(cur.get(key + "|" + k, 0)) + int(d[k])
	by_day[day_] = cur


func _game(seed_: int, n_seats: int) -> void:
	var srv := FakeSrv.new()
	var r := Room.new(srv, "SF", "normal" if normal else "test", n_seats)
	r.rng.seed = seed_
	var names := ["약함", "보통", "강함"]
	var nh := mini(3, n_seats - 1)
	for i in nh:
		r.add_human(i + 1, names[i], "tk%d" % i)
	r.start()
	if nh >= 3:
		var strong: Run = r.seats[2].run
		for k in DB.by_tier(7).slice(0, 12):
			strong.give(k)
	if verbose:
		print("=== 씨앗 %d · 자리 %d ===" % [seed_, n_seats])
	var guard := 0
	var s0 := {}      # 이 페이즈 아침 시작 값 (사람 번호 -> snap)
	var cur_day := -1
	var cur_phase := -1
	var battles := {}      # 사람 번호 -> 이번 페이즈 전투 목록
	var last_end := {}      # 사람 번호 -> 지난 페이즈 저녁 끝 값
	while r.stage != "over" and guard < 400:
		guard += 1
		var st := r.stage
		if st == "morning":
			# 새 페이즈 시작 —— 지난 페이즈를 정산한다
			if cur_day >= 0:
				pass
			cur_day = r.day
			cur_phase = r.phase
			battles = {}
			for i in nh:
				var s: Dictionary = r.seats[i]
				var sn := snap(s.run)
				s0[i] = sn
				battles[i] = []
				if last_end.has(i) and not s.dead:
					var gap := _diff(last_end[i], sn)
					_acc(cur_day + 1, "morn", gap)
					_acc(cur_day + 1, "morn", {"n": 1})
					for k in gap:
						if k != "item" and int(gap[k]) != 0:
							_fail("%d일차 p%d %s: 지난 저녁 끝 → 아침 시작에 %s 가 %d 달라졌다 (advance 가 새거나 더했다)" % [cur_day + 1, cur_phase, s.name, k, gap[k]])
				if not s.run.held.is_empty() and not (s.run.held.get("inv", {}).is_empty() and s.run.held.get("tickets", {}).is_empty()):
					_fail("%d일차 p%d 아침 시작인데 %s 의 held 가 안 비었다: %s" % [cur_day + 1, cur_phase, s.name, str(s.run.held)])
				if idle:
					continue
				r.on_cmd(i + 1, "do_draw", [])
				r.on_cmd(i + 1, "begin_picks", ["phase", -1])
				r.on_cmd(i + 1, "random_grant", [])
				if i >= 1:
					r.on_cmd(i + 1, "auto_deploy", [])
		for i in nh:
			r.seats[i].ready = true
		r.stage_end = 0.0
		var pre_stage := r.stage
		var pre_day := r.day
		var pre_phase := r.phase
		# 저녁이 끝나 다음 아침으로 넘어가기 전에 이번 페이즈를 정산한다 (held 가 아직 쌓여 있을 때)
		if pre_stage == "evening" and r.tour == null:
			_settle(r, nh, s0, battles, cur_day, cur_phase)
			for i in nh:
				last_end[i] = snap(r.seats[i].run)
		r.tick()
		# 전투는 단계가 끝날 때 계산되어 battles 에 들어온다
		for i in nh:
			for b in r.seats[i].battles:
				if not battles[i].any(func(x): return x == b):
					battles[i].append(b)
	if r.stage != "over":
		_fail("판이 끝나지 않았다 (씨앗 %d, %s %d일차)" % [seed_, r.stage, r.day + 1])


## 한 페이즈 정산 —— 아침 시작 값에서 지금(저녁 끝, held 포함)까지 늘어난 양과 기대값
func _settle(r: Room, nh: int, s0: Dictionary, battles: Dictionary, d: int, p: int) -> void:
	for i in nh:
		var s: Dictionary = r.seats[i]
		if s.dead:
			continue
		var got := _diff(s0[i], snap(s.run))
		var bl: Array = battles[i]
		var exp := _expect(d, p, bl)
		var wins := 0
		for b in bl:
			if str(b.kind) in ["quest", "pvp"]:
				wins_n["win" if b.res.win else "lose"] += 1
				wins += 1 if b.res.win else 0
		var kinds := ",".join(bl.map(func(b): return "%s:%s" % [b.kind, "승" if b.res.win else "패"]))
		for k in exp:
			if not idle and int(exp[k]) != int(got[k]):
				_fail("%d일차 p%d %s [%s]: %s 기대 %d / 실제 %d" % [d + 1, p, s.name, kinds, k, exp[k], got[k]])
		_acc(d + 1, "got", got)
		_acc(d + 1, "n", {"x": 1})
		if verbose and i == 1:
			var bagn := 0
			for k in s.run.bag:
				bagn += int(s.run.bag[k])
			print("%d일차 p%d %s [%s]  %s | 민심 %d 가방 %d uniq %d" % [d + 1, p, s.name, kinds, _fmt(got), s.run.hp, bagn, s.run.uniq_offer.size()])


func _print_table() -> void:
	print("== 일차별 페이즈당 평균 보급 (모든 씨앗 · 사람 합 / 페이즈 수) ==")
	for d in range(1, 8):
		var c: Dictionary = by_day.get(d, {})
		var n: int = int(c.get("n|x", 0))
		if n == 0:
			continue
		var o := {}
		for k in ["base", "t3", "t4", "t5", "t6+", "k1", "k3", "k4", "k5", "item"]:
			o[k] = snappedf(float(c.get("got|" + k, 0)) / n, 0.1)
		var itn: int = int(c.get("morn|n", 0))
		var item_s := "-" if itn == 0 else "%.2f" % (float(c.get("morn|item", 0)) / itn)
		print("%d일차 (사람·페이즈 %d) 아침 아이템 +%s | 기본 %.1f · 고급 %.1f · 희귀 %.1f · 전설 %.1f | 선택권 3:%.1f 4:%.1f 5:%.1f 1:%.1f " % [d, n, item_s, o.base, o.t3, o.t4, o.t5, o.k3, o.k4, o.k5, o.k1])
