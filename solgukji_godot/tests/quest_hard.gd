extends Node
## 험지 토벌 점검 (11/12 사용자) —— 실행: godot --headless --path . res://tests/quest_hard.tscn
## 고르기(set_quest_hard) · 적 병력/사기 배율 · 제목 · 이기면 한 등급 높은 선택권 · 페이즈가 넘어가면 꺼짐 · 저장 왕복 · 온라인 4일차~ 는 못 고름

var fails := []


func _fail(s: String) -> void:
	fails.append(s)
	printerr("FAIL ", s)


func _mk(seed_: int) -> Run:
	var r := Run.new()
	r.new_game(seed_)
	r.bot_prepare()
	return r


func _ready() -> void:
	# ① 보통 ↔ 험지 —— 같은 시드로 적 배율만 다르다
	var a := _mk(101)
	var b := _mk(101)
	if not b.quest_open(): _fail("첫 아침에 quest_open 이 아니다")
	if b.command("set_quest_hard", [true]) != true or not b.quest_hard: _fail("set_quest_hard 가 안 먹는다")
	var d: Dictionary = JSON.parse_string(JSON.stringify(b.to_dict(), "", false, true))
	var b2 := Run.new()
	b2.from_dict(d)
	if not b2.quest_hard: _fail("저장 왕복 뒤 quest_hard 가 사라졌다")
	var qa := a.start_quest()
	var qb := b.start_quest()
	if qa.has("hard") or not qb.get("hard", false): _fail("battle.hard 표시가 틀렸다")
	if not str(qb.title).ends_with("(험지)") or str(qa.title).contains("험지"): _fail("제목: %s / %s" % [qa.title, qb.title])
	var ta := float(qa.b.get("tr_mul", 1.0))
	var tb := float(qb.b.get("tr_mul", 1.0))
	if not is_equal_approx(tb, ta * Run.QUEST_HARD_TR): _fail("병력 배율 %s → %s" % [ta, tb])
	if int(qb.b.morale) <= int(qa.b.morale): _fail("사기 %s → %s" % [qa.b.morale, qb.b.morale])
	print("보통: 병력배율 %.2f 사기 %d / 험지: 병력배율 %.2f 사기 %d" % [ta, qa.b.morale, tb, qb.b.morale])
	if b.command("set_quest_hard", [false]) != false: _fail("전투 중에도 난이도가 바뀐다")
	# ② 결과 —— 이기면 hard_tier 선택권, 지면 없음
	for pair in [[a, qa, "보통"], [b, qb, "험지"]]:
		var r: Run = pair[0]
		var res := Run.simulate(pair[1], [], Run.policy_for(pair[1]))
		var hp0 := r.hp
		r.finish_battle(res)
		var ht := int(r.last_spoil.get("hard_tier", 0))
		print("%s: 승 %s · 내 잔존 %.2f · 민심 %d → %d · hard_tier %d · %s" % [pair[2], res.win, Run.my_left_ratio(res), hp0, r.hp, ht, UI.spoil_bb(r.last_spoil)])
		if pair[2] == "보통" and ht != 0: _fail("보통 토벌에 험지 보상")
		if pair[2] == "험지" and res.win and ht != r.quest_hard_tier(): _fail("험지 승리인데 보상 등급 %d" % ht)
		if pair[2] == "험지" and not res.win and ht != 0: _fail("험지 패배인데 보상")
		if r.command("set_quest_hard", [true]) != false: _fail("토벌 뒤에도 고를 수 있다")
	# ②-2 이긴 것으로 —— 보상 경로 (자동 편성 덱은 첫 토벌을 자주 진다)
	var w := _mk(104)
	w.set_quest_hard(true)
	var qw := w.start_quest()
	var rw := Run.simulate(qw, [], Run.policy_for(qw))
	rw.win = true
	rw.draw = false
	var n0: int = w.pool().values().reduce(func(x, y): return x + y, 0) + w.tickets.values().reduce(func(x, y): return x + y, 0)
	w.finish_battle(rw)
	var n1: int = w.pool().values().reduce(func(x, y): return x + y, 0) + w.tickets.values().reduce(func(x, y): return x + y, 0)
	print("험지 승리(강제): hard_tier %d · 패+선택권 %d → %d · %s" % [int(w.last_spoil.get("hard_tier", 0)), n0, n1, UI.spoil_bb(w.last_spoil)])
	if int(w.last_spoil.get("hard_tier", 0)) != w.quest_hard_tier(): _fail("험지 승리 보상 등급이 없다")
	# ③ 여러 시드 —— 험지 승률 · 잔존 (참고 출력)
	var wn := [0, 0]
	var lf := [0.0, 0.0]
	var n := 12
	for i in n:
		for h in 2:
			var r := _mk(200 + i)
			r.set_quest_hard(h == 1)
			var q := r.start_quest()
			var res := Run.simulate(q, [], Run.policy_for(q))
			wn[h] += 1 if res.win else 0
			lf[h] += Run.my_left_ratio(res)
	print("첫 토벌 %d판 —— 보통 승 %d · 잔존 %.2f / 험지 승 %d · 잔존 %.2f" % [n, wn[0], lf[0] / n, wn[1], lf[1] / n])
	# ④ 다음 페이즈로 넘어가면 꺼진다
	var c := _mk(102)
	c.set_quest_hard(true)
	c.dev_autoplay()
	if c.quest_hard: _fail("페이즈가 넘어갔는데 quest_hard 가 켜져 있다 (day %d phase %d)" % [c.day, c.phase])
	# ⑤ 온라인 4일차~ (토벌 없음) 는 못 고른다
	var m := _mk(103)
	m.mp = true
	m.day = Run.ONLINE_NOON_DAYS
	if m.quest_open() or m.set_quest_hard(true): _fail("온라인 토벌 없는 일차에 고를 수 있다")
	if not ("set_quest_hard" in Room.FORM_CMDS): _fail("Room.FORM_CMDS 에 없다")
	print("FAIL: ", fails if not fails.is_empty() else "없음")
	get_tree().quit(1 if not fails.is_empty() else 0)
