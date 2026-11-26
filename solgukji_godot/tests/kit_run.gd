extends Node
## 11/27 장수 키트 Q · W · E · R · P —— 재화 「전공」 · 강화 명령 · 전투로 넘기기 점검 (화면 없이):
##   godot --headless --path . res://tests/kit_run.tscn
## 새 방식 (11/27 저녁): 칸마다 고유 강화 하나 · 장수당 최대 2칸 · 되돌릴 수 없다 · 값은 그 장수의 1 · 2번째 강화마다 4 → 6
## ① 적립: 대전 +2 (승패 무관) · 토벌 승리 +1 · 토벌 패배 0, 온라인은 held 에 쌓였다가 다음 아침에
## ② 강화 명령 kit_up [카드, 칸] 의 성공과 거절 까닭 (모르는 카드 · 가지지 않은 장수 · 키트 아님 · 없는 칸 · 전공 부족 · 이미 강화한 칸 · 2칸 상한)
## ③ 저장 · 전송 왕복, 옛 저장(키 없음), 옛 형식 저장(칸 → 강화 배열)의 변환, 이상한 저장
## ④ 전투 재료: Run.policy_for 의 kit, Room 사람끼리 대전의 양쪽(뒤집힌 쪽 포함) · 그림자 대전 · 봇 대전
## ⑤ 서버 명령 단계 (아침 됨 · 대전 준비 안 됨) · 방 정보 kit · 기록 줄
## ⑥ 상대의 강화가 보인다: 방 정보 자리 줄의 kit (핵심 장수의 강화한 칸) · 오늘 상대 정보

const Kit := preload("res://scripts/kit.gd")


class FakeSrv:
	var sent := []
	func send(peer, msg) -> void:
		sent.append([peer, msg])
	func room_closed(_code) -> void:
		pass


var fails := 0


func ok(cond: bool, what: String) -> void:
	if not cond:
		fails += 1
	print("%s · %s" % ["통과" if cond else "실패", what])


## 실제 전투 한 판을 돌려 결과를 얻고 승패만 바꿔 정산한다 (정산이 보는 다른 값은 진짜 결과 그대로)
func _fight(r: Run, bt: Dictionary, win: bool) -> void:
	var res := Run.simulate(bt, [], Run.policy_for(bt))
	res.win = win
	res.draw = false
	r.finish_battle(res)


func _solo(seed_: int) -> Run:
	var r := Run.new()
	r.new_game(seed_)
	r.bot_prepare()
	return r


func _ready() -> void:
	PlayLog.enabled = false
	Run.dev_immortal = true
	var myths: Array = DB.C.keys().filter(func(k): return Kit.on(k))
	myths.sort()
	ok(myths.size() >= 2, "키트 장수(신화) %d명 —— %s" % [myths.size(), " · ".join(myths.map(func(k): return str(DB.C[k].name)))])
	if myths.size() < 2:
		get_tree().quit(1)
		return
	var no_cell: Array = myths.filter(func(k): return Kit.SLOTS.any(func(sl): return Kit.cell(k, sl).is_empty() or str(Kit.cell(k, sl).get("up", {}).get("n", "")) == ""))
	ok(no_cell.is_empty(), "키트 장수 모두 다섯 칸의 글 · 강화 글이 있다 (data/kit.json) %s" % str(no_cell))
	var ma: String = myths[0]
	var mb: String = myths[1]
	var plain := ""      # 키트가 아닌 장수 (불멸)
	for k in DB.by_tier(7):
		if not Kit.on(k) and not DB.is_foe(k):
			plain = k
			break

	# ── ① 적립 (혼자 하기 —— 바로 들어온다)
	var s0 := _solo(11)
	ok(s0.merit == 0 and s0.kit.is_empty(), "새 판 —— 전공 0 · 강화 없음")
	_fight(s0, s0.start_quest(), true)
	ok(s0.merit == Run.MERIT_QUEST_WIN and int(s0.last_spoil.get("merit", 0)) == Run.MERIT_QUEST_WIN, "토벌 승리 +%d (전공 %d)" % [Run.MERIT_QUEST_WIN, s0.merit])
	ok(UI.spoil_bb(s0.last_spoil).contains("%s +%d" % [Kit.CUR_N, Run.MERIT_QUEST_WIN]), "보상 글에 「전공 +N」")
	_fight(s0, s0.start_pvp(), false)
	ok(s0.merit == Run.MERIT_QUEST_WIN + Run.MERIT_PVP and int(s0.last_spoil.get("merit", 0)) == Run.MERIT_PVP, "대전 패배도 +%d (전공 %d)" % [Run.MERIT_PVP, s0.merit])
	var s1 := _solo(12)
	_fight(s1, s1.start_quest(), false)
	ok(s1.merit == 0 and not s1.last_spoil.has("merit") and not UI.spoil_bb(s1.last_spoil).contains(Kit.CUR_N), "토벌 패배는 0 (전공 %d · 보상 글에도 없다)" % s1.merit)
	_fight(s1, s1.start_pvp(), true)
	ok(s1.merit == Run.MERIT_PVP, "대전 승리 +%d (전공 %d)" % [Run.MERIT_PVP, s1.merit])

	# ── ① 적립 (온라인 —— 다음 아침에)
	var m0 := _solo(13)
	m0.mp = true
	_fight(m0, m0.start_quest(), true)
	ok(m0.merit == 0 and int(m0.held.get("merit", 0)) == Run.MERIT_QUEST_WIN and bool(m0.last_spoil.get("held", false)), "온라인 토벌 승리 —— 바로 주지 않고 held 에 (전공 %d · held %s)" % [m0.merit, str(m0.held.get("merit"))])
	var bt_m := {"kind": "pvp", "a": m0._my_side(), "b": m0._bot_side_of(m0.bots[0]), "seed": 5, "title": "대전 · 점검", "foe": "점검", "inputs": []}
	m0.battle = bt_m
	_fight(m0, bt_m, false)
	ok(m0.merit == 0 and int(m0.held.get("merit", 0)) == Run.MERIT_QUEST_WIN + Run.MERIT_PVP, "온라인 대전 —— held 에 더 쌓인다 (held %s)" % str(m0.held.get("merit")))
	var wire := Run.new()
	wire.from_dict(JSON.parse_string(JSON.stringify(m0.to_dict())))
	ok(int(wire.held.get("merit", 0)) == Run.MERIT_QUEST_WIN + Run.MERIT_PVP and wire.merit == 0, "전송 뒤에도 held 의 전공 그대로")
	m0.toasts.clear()
	m0.advance()
	ok(m0.merit == Run.MERIT_QUEST_WIN + Run.MERIT_PVP and m0.held.is_empty(), "다음 아침 지급 (전공 %d)" % m0.merit)
	ok(m0.toasts.any(func(t): return str(t[0]).contains("%s +%d" % [Kit.CUR_N, Run.MERIT_QUEST_WIN + Run.MERIT_PVP])), "아침 알림에 「전공 +N」")

	# ── ② 강화 명령 (새 방식)
	var c1 := int(Kit.UP_COST[0])
	var c2 := int(Kit.UP_COST[1])
	ok(Kit.MAX_UP == 2 and c1 == 4 and c2 == 6, "규칙 —— 장수당 %d칸 · 값 %d → %d" % [Kit.MAX_UP, c1, c2])
	var r := _solo(14)
	r.give(ma)
	r.merit = 100
	ok(r.kit_block("no_such_card", "q") != "" and r.command("kit_up", ["no_such_card", "q"]) == false, "모르는 카드 —— %s" % r.kit_block("no_such_card", "q"))
	ok(r.kit_block(mb, "q").contains("가지고 있지"), "가지지 않은 장수 —— %s" % r.kit_block(mb, "q"))
	if plain != "":
		r.give(plain)
		ok(r.kit_block(plain, "q").contains("키트"), "키트 아님(%s) —— %s" % [DB.C[plain].name, r.kit_block(plain, "q")])
	ok(r.kit_block(ma, "x").contains("없는 칸"), "없는 칸 —— %s" % r.kit_block(ma, "x"))
	ok(r.merit == 100 and r.kit.is_empty(), "거절된 명령은 전공 · 상태를 바꾸지 않는다")
	r.merit = c1 - 1
	ok(r.kit_block(ma, "q").contains("부족") and r.command("kit_up", [ma, "q"]) == false and r.merit == c1 - 1, "전공 부족 —— %s" % r.kit_block(ma, "q"))
	r.merit = 20
	ok(r.kit_cost(ma) == c1, "첫 강화 값 %d" % c1)
	ok(r.command("kit_up", [ma, "q"]) == true and r.merit == 20 - c1 and r.kit == {ma: ["q"]}, "첫 강화 성공 —— 전공 −%d (남은 %d) · %s" % [c1, r.merit, str(r.kit)])
	ok(r.kit_block(ma, "q").contains("이미 강화") and r.command("kit_up", [ma, "q"]) == false and r.merit == 20 - c1, "이미 강화한 칸 —— %s" % r.kit_block(ma, "q"))
	ok(r.kit_cost(ma) == c2, "둘째 강화 값 %d" % c2)
	r.merit = c2 - 1
	ok(r.kit_block(ma, "p").contains("부족") and r.command("kit_up", [ma, "p"]) == false, "둘째 강화 전공 부족 —— %s" % r.kit_block(ma, "p"))
	r.merit = 20
	ok(r.command("kit_up", [ma, "p"]) == true and r.merit == 20 - c2 and r.kit == {ma: ["q", "p"]}, "둘째 강화 성공 —— 전공 −%d (남은 %d) · %s" % [c2, r.merit, str(r.kit)])
	ok(r.kit_cost(ma) == -1 and r.kit_block(ma, "w").contains("모두 강화") and r.command("kit_up", [ma, "w"]) == false and r.merit == 20 - c2 and r.kit[ma].size() == 2, "2칸 상한 —— %s" % r.kit_block(ma, "w"))
	ok(r.command("kit_up", [ma]) == null and r.command("kit_up", [ma, "q", "dmg"]) == null, "인자 수가 다르면 명령 자체가 거절 (옛 3인자 포함)")
	ok(PlayLog.kit_spent(r.kit) == c1 + c2, "쓴 전공 합 %d" % PlayLog.kit_spent(r.kit))

	# ── ③ 저장 왕복 · 옛 저장 · 옛 형식 · 이상한 저장
	var back := Run.new()
	back.from_dict(JSON.parse_string(JSON.stringify(r.to_dict())))
	ok(back.merit == r.merit and back.kit == r.kit and back.merit is int, "저장 · 전송 왕복 —— 전공 %d · 강화 %s" % [back.merit, str(back.kit)])
	var d_old := r.to_dict()
	d_old.erase("merit")
	d_old.erase("kit")
	var legacy := Run.new()
	legacy.merit = 9
	legacy.kit = {ma: ["q"]}
	legacy.from_dict(JSON.parse_string(JSON.stringify(d_old)))
	ok(legacy.merit == 0 and legacy.kit.is_empty(), "옛 저장(키 없음) —— 전공 0 · 강화 없음")
	var d_v1 := r.to_dict()
	d_v1["kit"] = {ma: {"q": ["dmg", "fire"], "p": ["amp", "amp"]}, mb: {"r": ["wide"]}}
	var v1 := Run.new()
	v1.from_dict(JSON.parse_string(JSON.stringify(d_v1)))
	ok(v1.kit == {ma: ["q", "p"], mb: ["r"]}, "옛 형식 저장(칸 → 강화 배열)은 강화한 칸 목록으로 —— %s" % str(v1.kit))
	var d_bad := r.to_dict()
	d_bad["kit"] = {ma: ["q", "w", "e", "r"], mb: ["z", "q", "q"], "no_such_card": ["q"], "x": 3}
	if plain != "":
		d_bad["kit"][plain] = ["q"]
	d_bad["merit"] = "많이"
	var bad := Run.new()
	bad.from_dict(JSON.parse_string(JSON.stringify(d_bad)))
	ok(bad.kit == {ma: ["q", "w"], mb: ["q"]} and bad.merit == 0, "이상한 저장은 규칙에 맞게 (2칸까지 · 모르는 카드 · 칸 · 겹친 칸 · 키트 아닌 장수를 버린다) —— %s" % str(bad.kit))

	# ── ④ 전투 재료 (혼자 하기)
	r.board[4] = ma
	var side := r._my_side()
	ok(side.get("kit") == {ma: ["q", "p"]}, "_my_side 의 kit = 편성한 장수의 강화한 칸")
	(side.kit[ma] as Array).append("zzz")
	ok(r.kit[ma] == ["q", "p"], "전투 재료의 kit 은 사본 (고쳐도 Run.kit 은 그대로)")
	var q := r.start_quest()
	var pol := Run.policy_for(q)
	ok(pol.get("kit") is Dictionary and pol.kit.A == {ma: ["q", "p"]} and pol.kit.B.is_empty(), "토벌 —— policy.kit.A = 내 강화 · B 는 빈 것 (적은 강화 없음)")
	r.battle = null
	var bp := r.start_pvp()
	ok(Run.policy_for(bp).kit.B.is_empty(), "봇 대전 —— 봇은 강화 없음")
	r.battle = null
	r.board[4] = null
	r.give(ma)
	ok(r._my_side().kit.is_empty() and not Run.policy_for(r.start_quest()).has("kit"), "편성하지 않은 장수의 강화는 넘기지 않는다 · 강화가 없으면 policy 에 kit 키 없음")
	r.battle = null
	var none := _solo(15)
	ok(not Run.policy_for(none.start_quest()).has("kit"), "강화 없는 판 —— 정책은 예전 그대로 (kit 키 없음)")

	# ── ④ 전투 재료 (Room —— 사람끼리 · 그림자 · 봇) ⑤ 서버 명령
	var srv := FakeSrv.new()
	var room := Room.new(srv, "KIT", "test", 4)
	room.add_human(1, "가", "t1", false)
	room.add_human(2, "나", "t2", false)
	room.start()
	ok(bool(room.info(0).get("kit", false)), "방 정보 kit = true")
	var x: Dictionary = room.seats[0]
	var y: Dictionary = room.seats[1]
	var rx: Run = x.run
	var ry: Run = y.run
	for pair in [[rx, ma], [ry, mb]]:
		var rr: Run = pair[0]
		rr.bot_prepare()
		rr.board[4] = pair[1]
		rr.merit = 10
	ok(room.stage == "morning" and room.cmd_block(0, "kit_up") == "", "아침(준비) 단계 —— kit_up 을 받는다")
	room.on_cmd(1, "kit_up", [ma, "w"])
	room.on_cmd(2, "kit_up", [mb, "q"])
	room.on_cmd(2, "kit_up", [mb, "r"])
	ok(rx.kit == {ma: ["w"]} and rx.merit == 10 - c1, "서버 명령 —— 가: %s W 「%s」 · 전공 %d" % [DB.C[ma].name, Kit.cell(ma, "w").up.n, rx.merit])
	ok(ry.kit == {mb: ["q", "r"]} and ry.merit == 10 - c1 - c2, "서버 명령 —— 나: %s Q 「%s」 + R 「%s」 · 전공 %d" % [DB.C[mb].name, Kit.cell(mb, "q").up.n, Kit.cell(mb, "r").up.n, ry.merit])
	srv.sent.clear()
	room.on_cmd(1, "kit_up", [ma, "w"])
	ok(rx.merit == 10 - c1 and srv.sent.any(func(m): return m[0] == 1 and m[1].get("t") == "toast" and str(m[1].get("text", "")).contains("이미 강화")), "서버 —— 이미 강화한 칸은 까닭을 알림으로 돌려보낸다")
	srv.sent.clear()
	room.on_cmd(1, "kit_up", [ma, 3])
	ok(rx.merit == 10 - c1 and srv.sent.any(func(m): return m[0] == 1 and m[1].get("t") == "toast" and str(m[1].get("text", "")).contains("잘못된")), "서버 —— 글이 아닌 인자는 거절")
	srv.sent.clear()
	room.on_cmd(1, "kit_up", [ma, "w", "dmg"])
	ok(rx.kit == {ma: ["w"]} and srv.sent.any(func(m): return m[0] == 1 and m[1].get("t") == "toast"), "서버 —— 옛 3인자 명령(옛 클라이언트)은 거절")
	var st: Dictionary = {}
	for m in srv.sent:
		if m[0] == 1 and m[1].get("t") == "state":
			st = m[1]
	ok(st.get("run") is Dictionary and int(st.run.get("merit", -1)) == 10 - c1 and st.run.get("kit") == rx.kit, "상태 전송에 전공 · 강화가 실린다")
	# 사람끼리 대전 —— x 는 A 그대로, y 는 뒤집힌 재료
	room._pvp_humans(x, y)
	var px: Dictionary = x.battles[-1].params.policy
	var py: Dictionary = y.battles[-1].params.policy
	var kx := {ma: ["w"]}
	var ky := {mb: ["q", "r"]}
	ok(px.get("kit") is Dictionary and px.kit.A == kx and px.kit.B == ky, "사람끼리 대전 · A 자리 재료 —— policy.kit.A = 내(가) 강화 · B = 상대(나) 강화")
	ok(py.get("kit") is Dictionary and py.kit.A == ky and py.kit.B == kx, "사람끼리 대전 · 뒤집힌(B) 자리 재료 —— policy.kit.A = 내(나) 강화 · B = 상대(가) 강화")
	ok(int(rx.held.get("merit", 0)) == Run.MERIT_PVP and int(ry.held.get("merit", 0)) == Run.MERIT_PVP and rx.merit == 10 - c1, "방 대전 —— 양쪽 전공 +%d 는 다음 아침에 (held)" % Run.MERIT_PVP)
	# 그림자 대전 —— 원본(나)의 강화가 따라간다
	room._pvp_shadow(x, y, {"name": "나의 그림자"})
	var ps: Dictionary = x.battles[-1].params.policy
	ok(ps.get("kit") is Dictionary and ps.kit.A == kx and ps.kit.B == ky, "그림자 대전 —— 그림자(B)에 원본의 강화가 따라간다")
	ok(int(ry.held.get("merit", 0)) == Run.MERIT_PVP, "그림자의 원본은 전공을 받지 않는다")
	# 봇 대전 —— 봇은 강화 없음
	var bot_seat: Dictionary = {}
	for s in room.seats:
		if not s.human:
			bot_seat = s
			break
	room._pvp_bot(x, bot_seat)
	var pb: Dictionary = x.battles[-1].params.policy
	ok(pb.kit.A == kx and pb.kit.B.is_empty(), "봇 대전 —— 봇(B)은 강화 없음")
	# 대전 준비 단계에는 안 된다
	room.stage = "evening_prep"
	ok(room.cmd_block(0, "kit_up") != "", "대전 준비 단계 —— kit_up 거절 (%s)" % room.cmd_block(0, "kit_up"))
	rx.merit = 20
	room.on_cmd(1, "kit_up", [ma, "p"])
	ok(rx.kit == kx and rx.merit == 20, "대전 준비 단계의 명령은 상태를 바꾸지 않는다")
	room.stage = "noon"
	x.watched = false
	ok(room.cmd_block(0, "kit_up") != "", "토벌 단계 · 전투를 다 보기 전 —— 거절")
	x.watched = true
	ok(room.cmd_block(0, "kit_up") == "", "토벌 단계 · 전투를 다 본 뒤 —— 된다 (징집 · 조합과 같다)")
	rx.merit = 10 - c1

	# ── ⑤ 기록 줄
	var ad := PlayLog.act_data("kit_up", [ma, "w"], true, rx)
	ok(ad.get("ok") == true and ad.get("slot") == "w" and ad.get("up") == str(Kit.cell(ma, "w").up.n) and int(ad.get("cost", 0)) == c1 and ad.get("ups") == ["w"] and int(ad.get("merit", -1)) == rx.merit, "act 기록 —— %s" % JSON.stringify(ad))
	var ad2 := PlayLog.act_data("kit_up", [ma, "w"], false, rx)
	ok(ad2.get("ok") == false and not ad2.has("cost"), "거절된 강화의 act 기록 —— ok:false")
	var rd := PlayLog.reward_data(rx)
	ok(int(rd.get("merit", -1)) == rx.merit and int(rd.get("merit_gain", 0)) == Run.MERIT_PVP and int(rd.get("merit_held", 0)) > 0, "reward 기록 —— merit %s · merit_gain %s · merit_held %s" % [str(rd.get("merit")), str(rd.get("merit_gain")), str(rd.get("merit_held"))])
	var pe := PlayLog.phase_end_data(ry)
	ok(pe.get("kit") == ky and int(pe.get("kit_spent", 0)) == c1 + c2, "phase_end 기록 —— merit · kit · kit_spent %s" % str(pe.get("kit_spent")))
	var bsd := PlayLog.battle_start_data({"kind": "pvp", "title": "t", "seed": 1, "a": rx._my_side(), "b": ry._my_side()})
	ok(bsd.get("kit") == kx and bsd.get("foe_kit") == ky, "battle_start 기록 —— kit · foe_kit")
	print("키트 재화 · 강화 점검 —— 실패 %d" % fails)
	get_tree().quit(1 if fails > 0 else 0)
