extends Node
## 11/27 사용자: 병종 「술사」를 없앴다 (방식 A —— 장수는 책사 · 유생 · 모사로 옮김, 기본패 occul 삭제, 황건 계 장수는 토벌 적 전용).
## 실행: godot --headless --path . res://tests/occ_removed.tscn [-- --noplay (자동 진행 한 판을 건너뜀)]
## 승률 · 세기는 재지 않는다 —— 동작만 본다:
##  ① 자료 —— 카드(플레이어 · 적) · 장비 · 기본패 · 조합법 · 군략 · 진형 보너스 · 병종 표 어디에도 병종 「술사」 · id occul 이 없다
##  ② 옮긴 장수 19명의 새 병종이 표대로 · 황건 계 6명은 적 전용(조합법 · 키트 없음) · 조합법의 재료 · 결과가 모두 있다
##  ③ 옛 저장(occul 이 든 to_dict)을 불러오면 다른 기본패(모사 schem)로 바뀐다 · 서버가 occul 명령을 받아도 깨지지 않는다
##  ④ 병종 「술사」 · id occul 이 든 옛 전투 결과를 BattleView 로 재생해도 멈추지 않는다 (스크립트 오류는 실행 기록에서 따로 본다)
##  ⑤ 자동 진행 한 판(Run.dev_autoplay, 7일차 끝까지)
const Tac := preload("res://scripts/tactics.gd")


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


## 옮긴 장수 —— 표 (카드 id -> 새 병종)
const MOVED := {
	"c32": "책사", "c107": "책사", "s14": "책사", "c192": "책사", "E12": "책사", "s16": "책사",
	"R13": "유생", "H10": "유생", "H30": "유생", "K18": "유생", "c110": "유생", "c173": "유생",
	"c34": "모사", "c35": "모사", "G11": "모사", "H31": "모사", "K19": "모사", "K20": "모사"}
const FOE_ONLY := ["c107", "s14", "c192", "c32", "H14", "c22"]


func _has_occ(x) -> bool:
	if x is String:
		return x == "술사" or x == "occul"
	if x is Array:
		return x.any(func(y): return _has_occ(y))
	if x is Dictionary:
		for k in x:
			if _has_occ(str(k)) or _has_occ(x[k]):
				return true
	return false


func _ready() -> void:
	PlayLog.enabled = false
	Run.dev_nosave = true
	_data()
	_saves()
	_room()
	await _replay()
	if not OS.get_cmdline_user_args().has("--noplay"):
		_autoplay()
	print("술사 없애기 점검 —— 실패 %d" % fails)
	get_tree().quit(1 if fails > 0 else 0)


# ───────── ① ② 자료 ─────────

func _data() -> void:
	var bad_cards := DB.C.keys().filter(func(k): return str(DB.C[k].tag) == "술사")
	ok(bad_cards.is_empty(), "카드(플레이어 · 적 · 빠진 카드) 병종에 술사 없음 %s" % str(bad_cards))
	ok(not DB.C.has("occul"), "기본패 occul 이 카드에 없다")
	ok(DB.BASE.size() == 7 and not DB.BASE.has("occul"), "기본패 7종 %s" % str(DB.BASE))
	var bad_items := DB.IT.keys().filter(func(k): return str(DB.IT[k].tag) == "술사")
	ok(bad_items.is_empty(), "장비 대상 병종에 술사 없음 %s" % str(bad_items))
	var per := {}
	for k in DB.IT:
		per[DB.IT[k].tag] = int(per.get(DB.IT[k].tag, 0)) + 1
	print("   병종별 장비 수 %s" % str(per))
	for t in DB.D.TAGORDER:
		var w := DB.IT.keys().filter(func(k): return DB.IT[k].tag == t and DB.IT[k].grade == "고대" and DB.item_slot(k) == "weapon").size()
		var a := DB.IT.keys().filter(func(k): return DB.IT[k].tag == t and DB.IT[k].grade == "고대" and DB.item_slot(k) == "armor").size()
		ok(w >= 1 and a >= 1, "%s 고대 무기 %d · 갑옷 %d" % [t, w, a])
	# 병종 표
	ok(DB.D.TAGORDER.size() == 7 and not DB.D.TAGORDER.has("술사"), "TAGORDER 7병종 %s" % str(DB.D.TAGORDER))
	for key in ["AFF", "FRONT_WANT", "TAGSYN", "TAGPATH", "SKILLPOOL"]:
		ok(not (DB.D[key] as Dictionary).has("술사"), "%s 에 술사 칸 없음" % key)
	for f in DB.D.FORMBOON:
		ok(not _has_occ(DB.D.FORMBOON[f].tags) and DB.D.FORMBOON[f].tags.size() == 2, "진형 보너스 %s %s" % [f, str(DB.D.FORMBOON[f].tags)])
	ok(not _has_occ(DB.CLASS_COUNTER.get("win", {})) and not _has_occ(DB.CLASS_COUNTER.get("lose", {})) and not _has_occ(DB.CLASS_COUNTER.get("pair_amt", {})), "병종 상성에 술사 없음")
	for key in ["kind", "armor", "ward", "dmg", "taken", "range", "sup"]:
		ok(not _has_occ(DB.GUARD.get(key, {})), "병종 막 · 배율 %s 에 술사 없음" % key)
	ok(not _has_occ(DB.STAT_ADJ), "병종 능력치 보정에 술사 없음")
	ok(not DB.ICON.has("술사"), "병종 아이콘에 술사 없음")
	ok(not Battle.INT_TAG.has("술사") and not DB.INT_TAGS.has("술사"), "책략계 병종 목록에 술사 없음")
	ok(not Battle.MINOR_TAG.has("술사") and not Battle.MINOR_ACT.has("술사"), "잔기술 표에 술사 없음")
	ok(not Battle.ROLE.keys().any(func(k): return str(k).begins_with("occul")), "병종 역할 배율에 occul_* 없음 %s" % str(Battle.ROLE.keys()))
	ok(not RtBattle.ESCAPE.has("술사") and not RtBattle.SPEED.has("술사") and not RtBattle.FP_SP.has("술사") and not RtBattle.FP_RATIO.has("술사"), "실시간 엔진 병종 표에 술사 없음")
	# 군략
	var tj = JSON.parse_string(FileAccess.get_file_as_string("res://data/tactics.json"))
	ok(not _has_occ(tj), "군략(data/tactics.json) 어디에도 술사 없음")
	var roles = JSON.parse_string(FileAccess.get_file_as_string("res://data/roles.json"))
	ok(not _has_occ(roles.get("dmg", {})) and not _has_occ(roles.get("tough", {})) and not _has_occ(roles.get("tag", {})), "역할 한 줄(roles.json) 병종 표에 술사 없음")
	# 옮긴 장수
	var wrong := []
	for k in MOVED:
		if not DB.C.has(k) or DB.C[k].tag != MOVED[k]:
			wrong.append("%s(%s)" % [k, DB.C[k].tag if DB.C.has(k) else "없음"])
	ok(wrong.is_empty(), "옮긴 장수 %d명 새 병종 표대로 %s" % [MOVED.size(), str(wrong)])
	var foe_bad := []
	for k in FOE_ONLY:
		if not DB.C.has(k) or not DB.is_foe(k) or DB.RECOF.has(k) or DB.by_tier(int(DB.C[k].tier)).has(k):
			foe_bad.append(k)
	ok(foe_bad.is_empty(), "황건 계 장수 6명 적 전용 (조합법 · 등급 목록 없음) %s" % str(foe_bad))
	var kit = JSON.parse_string(FileAccess.get_file_as_string("res://data/kit.json"))
	ok(not kit.has("c192"), "대현량사 장각 c192 는 키트 장수에서 빠졌다")
	var q_foe := 0
	for day in DB.QUEST_ROSTERS:
		for st in day:
			for k in st.cards:
				if FOE_ONLY.has(str(k)): q_foe += 1
	ok(q_foe > 0, "토벌 고정 편성이 황건 계 장수를 적으로 쓴다 (%d칸)" % q_foe)
	# 조합법
	var rec_bad := []
	var thin := []
	for k in DB.RECOF:
		var mats: Array = DB.RECOF[k]
		if not DB.C.has(k) or mats.any(func(x): return not DB.C.has(str(x)) or str(x) == "occul" or FOE_ONLY.has(str(x))):
			rec_bad.append(k)
		if mats.size() < 2:
			thin.append(k)
	ok(rec_bad.is_empty(), "조합법 %d개 —— 재료 · 결과가 모두 있고 occul · 적 전용 재료가 없다 %s" % [DB.RECOF.size(), str(rec_bad)])
	ok(thin.is_empty(), "조합법 재료가 둘 이상 %s" % str(thin))
	# 같은 인물 · 같은 등급 · 같은 병종 카드가 둘 (플레이어)
	var seen := {}
	var dup := []
	for k in DB.C:
		if DB.is_foe(k) or int(DB.C[k].tier) < 3:
			continue
		var key := "%s|%d|%s" % [DB.person(k), int(DB.C[k].tier), DB.C[k].tag]
		if seen.has(key):
			dup.append("%s · %s" % [seen[key], k])
		seen[key] = k
	print("   같은 인물 · 등급 · 병종 겹침 %s" % str(dup))
	# 플레이어가 얻는 길 —— 상점 · 선택권 등급 목록 · 봇 풀
	var pools_bad := []
	for st in DB.POOLS:
		for t in DB.POOLS[st]:
			for k in DB.POOLS[st][t]:
				if FOE_ONLY.has(k) or k == "occul": pools_bad.append(k)
	ok(pools_bad.is_empty(), "봇 덱 풀에 적 전용 · occul 없음 %s" % str(pools_bad))


# ───────── ③ 옛 저장 · 서버 명령 ─────────

func _saves() -> void:
	var r := Run.new()
	r.new_game(11)
	r.inv["occul"] = 3
	r.inv["schem"] = 1
	r.board[0] = "occul"
	r.held = {"inv": {"occul": 2}, "tickets": {}}
	r.last_draw = ["occul", "spear"]
	r.last_spoil = {"n": 2, "src": "토벌"}
	if not r.bots.is_empty():
		r.bots[0]["army"] = ["occul", "spear", "spear", "bow", "bow", "horse", "horse", "strat", "schol"]
	var d = JSON.parse_string(JSON.stringify(r.to_dict(), "", false, true))
	ok(_has_occ(d.inv), "(시험 전제) 옛 저장에 occul 이 있다")
	var b := Run.new()
	b.from_dict(d)
	ok(not b.inv.has("occul") and int(b.inv.get("schem", 0)) == 4, "손패 occul 3 → 모사 기본패 (schem %d)" % int(b.inv.get("schem", 0)))
	ok(b.board[0] == "schem", "편성 칸 occul → schem (%s)" % str(b.board[0]))
	ok(int(b.held.inv.get("schem", 0)) == 2 and not b.held.inv.has("occul"), "쌓아 둔 보상 occul → schem")
	ok(not b.last_draw.has("occul"), "방금 받은 기본패 목록에서 바뀜 %s" % str(b.last_draw))
	if not b.bots.is_empty():
		ok(not (b.bots[0].army as Array).has("occul"), "봇 군세 occul → schem")
	ok(not _has_occ(b.to_dict().inv) and not _has_occ(b.to_dict().board), "다시 저장해도 occul 없음")
	# 진행 중이던 전투 · 봇 장부(forge_state) 안의 occul
	var r2 := Run.new()
	r2.new_game(12)
	var q := r2.start_quest()
	q.a.cards[0] = "occul"
	var d2 := r2.to_dict()
	d2.battle = q
	var b2 := Run.new()
	b2.from_dict(JSON.parse_string(JSON.stringify(d2, "", false, true)))
	ok(b2.battle != null and not (b2.battle.a.cards as Array).has("occul"), "진행 중 전투 재료의 occul → schem")


func _room() -> void:
	var srv := FakeSrv.new()
	var rm := Room.new(srv, "OCC", "test", 4)
	rm.add_human(1, "가", "t1", false)
	rm.start()
	var run: Run = rm.seats[0].run
	run.inv["schem"] = 1
	var before := run.board.duplicate()
	var done := false
	rm.on_cmd(1, "place", [0, "occul"])
	done = true
	ok(done, "서버가 occul 이 든 place 명령을 받아도 멈추지 않는다")
	ok(run.board[0] == "schem" or run.board == before, "occul 명령은 모사 기본패로 읽거나 거절된다 (칸 0: %s)" % str(run.board[0]))
	rm.on_cmd(1, "sell", ["occul"])
	ok(not run.inv.has("occul"), "판매 명령의 occul 도 손패에 occul 을 만들지 않는다")


# ───────── ④ 옛 전투 결과 재생 ─────────

func _replay() -> void:
	var a := DB.auto_place(["spear", "horse", "bow", "rogue", "strat", "schol", "schem", "E12", "c110"], "eorin")
	var b := DB.auto_place(["spear", "horse", "bow", "rogue", "strat", "schol", "schem", "H31", "R13"], "hagik")
	var res := RtBattle.new(5).run(a, "eorin", 100, null, b, "hagik", 100, null, "옛 결과", "적", [], {"A": "auto", "B": "auto"})
	ok(res.roster.size() == 18, "(시험 전제) 결과 18부대")
	# 옛 서버 결과처럼 —— 책략 장수 몇을 병종 「술사」로, 기본패 하나를 occul 로
	var n := 0
	for row in res.roster:
		if str(row.tag) in ["모사", "유생"] and n < 4:
			row.tag = "술사"
			n += 1
		if str(row.id) == "schem" and str(row.key).begins_with("A"):
			row.id = "occul"
			row.name = "술사"
	if res.get("mvp") is Dictionary:
		res.mvp.id = "occul"
	var params := {"a": a.map(func(x): return "occul" if x == "schem" else x), "fa": "eorin", "ma": 100, "ea": null,
		"b": b, "fb": "hagik", "mb": 100, "eb": null, "seed": 5, "title": "옛 결과", "foe": "적", "policy": {"A": "auto", "B": "auto"}}
	Settings.load_cfg()
	Settings.type2 = true
	Settings.war_painting = true
	Settings.apply()
	var view := BattleView.new()
	add_child(view)
	await get_tree().process_frame
	view.play_res(res, "pvp", params)
	view._set_speed(BattleView.SPEEDS[BattleView.SPEEDS.size() - 1])
	var t0 := Time.get_ticks_msec()
	while not view.finished and Time.get_ticks_msec() - t0 < 25000:
		await get_tree().process_frame
	ok(not res.roster.any(func(r): return str(r.tag) == "술사" or str(r.id) == "occul"), "재생 전에 옛 병종 · id 를 바꿔 읽는다")
	ok(view.clock > 1.0, "옛 결과 재생이 흘렀다 (시계 %.1f초 · 끝 %s)" % [view.clock, str(view.finished)])
	var ss: Dictionary = view.start_stats(str(res.roster[0].key))
	ok(ss is Dictionary, "전투장수창 시작 능력치가 옛 재료(occul)로도 잡힌다")
	view.queue_free()
	await get_tree().process_frame


# ───────── ⑤ 자동 진행 한 판 ─────────

func _autoplay() -> void:
	Run.dev_immortal = true
	var r := Run.new()
	r.new_game(2711)
	var guard := 0
	while r.over == null and r.day < 7 and guard < 40:
		r.dev_autoplay()
		guard += 1
	ok(r.day >= 7 or r.over != null, "자동 진행 한 판 —— %d일차 %d페이즈까지 (%d번)" % [r.day + 1, r.phase, guard])
	var occ_seen := _has_occ(r.inv) or _has_occ(r.board)
	for bt in r.bots:
		occ_seen = occ_seen or _has_occ(bt.get("army", []))
	ok(not occ_seen, "자동 진행 판의 손패 · 편성 · 봇 군세에 occul 없음")
	Run.dev_immortal = false
