extends Node
## 군략 카드 점검 (11/15 1차) —— 실행: godot --headless --path . res://tests/tac_check.tscn
##  1) 같은 계획 · 같은 시드 두 번 → 사건 기록이 완전히 같다 (서버 계산 · 클라이언트 재생)
##  2) 1차 카드 하나하나를 세 단계에 놓아 돌려 본다 (스크립트 오류 · 단계 사건 셋)
##  3) 상성 표 · 무효 · 계획 규칙 · 3택1 · 저장 왕복
## 밸런스는 재지 않는다 (사용자 방침 —— 마지막에 한 번)

const Tac := preload("res://scripts/tactics.gd")
var fails := 0


func _ready() -> void:
	Tac.data()
	_rules()
	_each_card()
	_twice()
	_effect()
	_run_flow()
	var c := Tac.counts()
	print("군략 점검 —— 넣은 카드 %d · 능력치·경제 %d · 뺀 카드 %d · 실패 %d" % [c.on, c.econ, c.off.size(), fails])
	get_tree().quit()


func _ok(cond: bool, what: String) -> void:
	if not cond:
		fails += 1
		print("  실패: ", what)


func _rules() -> void:
	_ok(Tac.outcome(["정면"], ["기동"]) == "win", "정면 > 기동")
	_ok(Tac.outcome(["정면"], ["수비"]) == "lose", "정면 < 수비")
	_ok(Tac.outcome(["원거리"], ["책략"]) == "win", "원거리 > 책략")
	_ok(Tac.outcome(["책략"], ["수비"]) == "win", "책략 > 수비")
	_ok(Tac.outcome(["정면"], ["정면"]) == "draw", "같은 계열 비김")
	_ok(Tac.outcome([], ["정면"]) == "draw", "계열 없음 비김")
	_ok(Tac.outcome(["기동"], ["원거리"], {"beats": ["원거리"]}) == "draw", "천리행군: 서로 이김 → 비김")
	_ok(Tac.outcome(["수비"], ["기동"], {"draw_vs": ["기동"]}) == "draw", "원진: 기동에게 비김")
	_ok(Tac.outcome(["정면", "기동"], ["수비"]) == "win", "호표기: 유리한 쪽(기동)")
	var hand := {"돌격": 1, "총공격": 1, "함진영": 1, "야습": 1, "연환계": 1, "화공": 1}
	_ok(Tac.plan_block(["돌격", "", ""], hand, 1, "돌격") == "", "기본 카드 겹쳐 놓기")
	_ok(Tac.plan_block(["화공", "", ""], hand, 1, "화공") != "", "고급은 한 번")
	_ok(Tac.plan_block(["총공격", "", ""], hand, 1, "함진영") != "", "전설 한 장")
	_ok(Tac.plan_block(["", "", ""], hand, 1, "야습") != "", "1단계 전용")
	_ok(Tac.plan_block(["", "", ""], hand, 2, "연환계") != "", "연환계 3단계 금지")
	_ok(Tac.plan_block(["", "", ""], hand, 0, "십면매복") != "", "없는 카드")
	var r := RandomNumberGenerator.new()
	r.seed = 5
	for i in 20:
		var o := Tac.offer(["spear", "spear", "spear", "horse", null, null, null, null, null], {"돌격": 1}, 2, r)
		_ok(o.size() == 3 and str(Tac.card(o[2]).get("kind", "")) == "econ", "3택1 = 군략 2 + 경제 1")
		for id in o:
			_ok(not bool(Tac.card(id).get("off", false)), "3택1 에 뺀 카드 %s" % id)


## 카드마다 —— 계획 세 칸 모두(못 놓는 칸은 비운다)에 놓고 상대는 기본 계획
func _each_card() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var a := _deck(6, rng)
	var b := _deck(6, rng)
	var n := 0
	for id in Tac.CARDS:
		if not Tac.is_on(id) or str(Tac.card(id).kind) == "econ":
			continue
		var c := Tac.card(id)
		var pl: Dictionary
		if str(c.kind) == "passive":
			pl = {"p": ["돌격", "방진", "우회"], "own": [id], "perm": []}
		else:
			var hand := {id: 3}
			pl = {"p": Tac.clean([id, id, id], hand), "own": [], "perm": []}
			if bool(c.get("link", false)):
				pl.p = [id, "돌격", "방진"]
		var r := _run(a, b, 1000 + n, {"A": pl, "B": {"p": ["방진", "돌격", "우회"]}})
		var st: int = r.ev.filter(func(e): return e.get("fx") == "tac").size()
		_ok(r.has("tac"), "%s: 결과에 tac 없음" % id)
		_ok(st >= 1, "%s: 단계 사건 없음" % id)
		n += 1
	# 영구 효과 부품 (능력치 카드)
	for e in Tac.ECON.values():
		for part in e.fx:
			if str(part.k) == "perm":
				var pp: Dictionary = part.part.duplicate()
				if not pp.has("who"):
					pp["who"] = ["창병"]
				var r2 := _run(a, b, 3000 + n, {"A": {"p": ["", "", ""], "own": [], "perm": [pp]}, "B": {}})
				_ok(r2.has("tac"), "%s: 영구 효과" % e.id)
				n += 1
	print("  카드별 전투 %d판" % n)


## 같은 계획 두 번 → 같은 결과 (무작위 계획 20판)
func _twice() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var all := Tac.CARDS.keys().filter(func(id): return Tac.placeable(id))
	all.sort()
	for i in 20:
		var t: int = [5, 6, 7][i % 3]
		var a := _deck(t, rng)
		var b := _deck(t, rng)
		var hand := {}
		for id in all:
			hand[id] = 1
		var pa := Tac.bot_plan(a, all, rng, hand)
		var pb := Tac.bot_plan(b, all, rng, hand)
		var own := ["창림", "약탈", "의론"] if i % 2 == 0 else ["수군", "태평도"]
		var tp := {"A": {"p": pa, "own": own, "perm": [{"k": "atk", "v": 0.08, "who": ["궁병"]}]}, "B": {"p": pb, "own": [], "perm": []}}
		var sd := rng.randi() % 100000
		var r0 := _run(a, b, sd, tp)
		var r1 := _run(a, b, sd, tp.duplicate(true))
		var same: bool = r0.ev.size() == r1.ev.size() and r0.win == r1.win
		if same:
			for j in r0.ev.size():
				if str(r0.ev[j].t) != str(r1.ev[j].t) or str(r0.ev[j].s) != str(r1.ev[j].s):
					same = false
					print("  어긋남 %d번 사건: %s / %s" % [j, r0.ev[j].t, r1.ev[j].t])
					break
		_ok(same, "같은 계획 두 번 %d판 (%s 대 %s)" % [i, str(pa), str(pb)])
		_ok(str(r0.tac) == str(r1.tac), "단계 기록 같음 %d판" % i)
	print("  같은 계획 두 번 20판")


## 효과가 실제로 걸리는가 —— 같은 시드에서 1단계 총공격(공격 +40%)을 놓으면 처음 10초 동안 아군이 준 피해가 는다
func _effect() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 23
	var more := 0
	for i in 5:
		var a := _deck(6, rng)
		var b := _deck(6, rng)
		var sd := rng.randi() % 100000
		var r0 := _run(a, b, sd, {"A": {"p": ["", "", ""], "own": ["태평도"]}, "B": {}})
		var r1 := _run(a, b, sd, {"A": {"p": ["총공격", "", ""], "own": ["태평도"]}, "B": {}})
		if _dealt(r1, 10.0) > _dealt(r0, 10.0):
			more += 1
	_ok(more >= 4, "총공격이 피해를 늘린다 (%d/5)" % more)


func _dealt(r: Dictionary, until: float) -> float:
	var n := 0.0
	for e in r.ev:
		if float(e.get("tm", 0.0)) > until:
			break
		if (e.get("fx") == "phys" or e.get("fx") == "int") and str(e.get("a", "")).begins_with("A"):
			n += float(e.get("n", 0.0))
	return n


## Run —— 기본 3장 · 계획 · 하루 끝 3택1 · 고르기 · 저장 왕복 · 토벌 우두머리 계획
func _run_flow() -> void:
	var run := Run.new()
	run.new_game(42)
	_ok(run.tk_hand.size() == 3, "처음 손패 3장")
	_ok(run.set_plan(0, "돌격") and run.set_plan(1, "돌격") and run.set_plan(2, "방진"), "계획 놓기")
	_ok(not run.set_plan(1, "화공"), "없는 카드 놓기 거절")
	_ok(run.quest_plan().size() == 3, "우두머리 계획")
	_ok(run.quest_plan() == run.quest_plan(), "우두머리 계획이 그날 고정")
	var bc: Array = ["spear", "horse", "bow"]      # 봇 손패 —— 사람과 같은 규칙 (첫날은 기본 3장뿐, 날마다 한 장)
	var h0 := Tac.sim_hand(bc, 0, 9)
	var h4 := Tac.sim_hand(bc, 4, 9)
	_ok(h0.size() == 3 and h4.size() == 7, "봇 손패 3 → 4일 뒤 7 (%d · %d)" % [h0.size(), h4.size()])
	var bp := Run.bot_plan_load(bc, 0, 5, 9)
	_ok((bp.p as Array).all(func(id): return id == "" or h0.has(id)), "첫날 봇 계획은 기본 카드만")
	for i in 3:
		run.quest_done = true
		run.pvp_done = true
		run.advance()
	_ok(run.tk_offer.size() == 3, "하루 끝 3택1 (%d장)" % run.tk_offer.size())
	var pick := str(run.tk_offer[0])
	var d := run.to_dict()
	var r2 := Run.new()
	r2.from_dict(JSON.parse_string(JSON.stringify(d)))
	_ok(r2.tk_offer == run.tk_offer and r2.tk_plan == run.tk_plan and r2.tk_hand.size() == run.tk_hand.size(), "저장 왕복")
	_ok(r2.command("pick_tac", [pick]) == true, "3택1 고르기 (명령)")
	_ok(r2.tk_offer.is_empty(), "고른 뒤 비움")
	# 옛 저장 (키 없음) —— 기본 3장
	var old := d.duplicate(true)
	for k in ["tk_hand", "tk_plan", "tk_offer", "tk_hist", "tk_perm", "tk_more", "tk_reroll", "tk_draw", "tk_rolls"]:
		old.erase(k)
	var r3 := Run.new()
	r3.from_dict(old)
	_ok(r3.tk_hand.size() == 3 and r3.tk_plan == ["", "", ""], "옛 저장 기본값")
	# 경제 카드 모두
	for id in Tac.ECON:
		var r4 := Run.new()
		r4.new_game(3)
		r4.tk_offer = [id]
		_ok(r4.pick_tac(id), "경제 카드 %s" % id)
	# 토벌 · 대전 한 판씩 (계획이 짐으로 들어간다)
	run.auto_deploy()
	var q := run.start_quest()
	_ok(Run.policy_for(q).has("plan"), "토벌 정책에 계획")
	var res := Run.simulate(q, [], Run.policy_for(q))
	_ok(res.has("tac") and (res.tac.log as Array).size() >= 1, "토벌 결과에 단계 기록")
	run.finish_battle(res)
	var pv := run.start_pvp()
	var res2 := Run.simulate(pv, [], Run.policy_for(pv))
	run.finish_battle(res2)
	_ok(run.tk_hist.size() == 1, "대전 계획 기록")
	var fl := Run.flip_res(res2)
	_ok(str(fl.tac.log[0].A) == str(res2.tac.log[0].B), "뒤집기 —— 단계 기록 진영도")


func _deck(t: int, rng: RandomNumberGenerator) -> Array:
	var pool: Array = DB.by_tier(t)
	var d := []
	for i in 9:
		d.append(pool[rng.randi() % pool.size()])
	return d


func _run(a: Array, b: Array, sd: int, tp: Dictionary) -> Dictionary:
	return RtBattle.make(sd).run(DB.auto_place(a, "eorin"), "eorin", 100, null,
		DB.auto_place(b, "hagik"), "hagik", 100, null, "", "", [], {"A": "smart", "B": "smart", "plan": tp})
