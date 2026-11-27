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
	# 11/27 사용자 "군략은 제거, 연구는 유지" —— 게임에서는 꺼져 있어야 한다 (꺼진 흐름은 tests/no_tactics).
	# 아래는 스위치를 다시 켰을 때 잠든 군략 엔진이 그대로 도는지만 본다 (점검 동안만 켠다)
	_ok(not Run.tac_on, "군략 스위치(Run.tac_on)가 꺼져 있다")
	Run.tac_on = true
	_rules()
	_each_card()
	_twice()
	_effect()
	_run_flow()
	Run.tac_on = false
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
	# 11/25 카드 상성 줄 · 받아치기 배치 · 연구 단계
	_ok(not Tac.weak("원진").has("기동") and Tac.weak("원진").has("책략"), "원진 열세 줄에 기동이 없다 (비김)")
	_ok(not Tac.weak("천리행군").has("원거리") and not Tac.strong("천리행군").has("원거리"), "천리행군: 원거리와 서로 이김 → 비김 (열세 줄에서 빠진다)")
	_ok(Tac.strong("십면매복").has("정면") and not Tac.weak("십면매복").has("기동"), "십면매복: 정면 우세 · 기동 비김")
	var ch := {"돌격": 1, "방진": 1, "우회": 1, "일제 사격": 1, "화공": 1, "총공격": 1, "제갈연노": 1}
	var cp := Tac.counter_plan(["돌격", "돌격", "돌격"], ch, ["방진", "우회", "화공"])
	_ok(Tac.preview(cp[0], "방진") == "win" and Tac.preview(cp[1], "우회") == "win" and Tac.preview(cp[2], "화공") == "win", "받아치기: 세 단계 모두 우세 %s" % str(cp))
	var legends := 0
	for k in 3:
		_ok(Tac.plan_block(cp, ch, k, cp[k]) == "", "받아치기 결과가 규칙 안 (%d단계 %s)" % [k + 1, cp[k]])
		if cp[k] != "" and int(Tac.card(cp[k]).g) == 3:
			legends += 1
	_ok(legends <= 1, "받아치기: 전설 한 장")
	_ok(Tac.counter_plan(["우회", "", ""], ch, ["방진", "", ""]) == ["우회", "", ""], "받아치기: 이미 이기는 칸 · 모르는 단계는 그대로")
	_ok(Tac.counter_plan(["돌격", "", ""], {"돌격": 1}, ["방진", "", ""]) == ["돌격", "", ""], "받아치기: 이길 카드가 없으면 그대로")
	_ok(Tac.res_level("명마") == 0 and Tac.res_level("양마 번식") == 1 and Tac.res_level("서량 마구") == 2, "연구 단계 초급 · 중급 · 고급")
	_ok(Tac.res_chain("양마 번식") == ["명마", "양마 번식", "서량 마구"], "연구 갈래 줄")
	_ok(Tac.grade_name("서량 마구").begins_with("고급 연구") and Tac.grade_col("명마") != Tac.grade_col("서량 마구"), "연구 단계 이름 · 색")
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
	# 11/22 군략 → 연구 두 단계 (아침마다)
	_ok(run.tk_offer.all(func(id): return not Tac.is_res(str(id))), "군략 3택1 에 연구 없음")
	_ok(run.rs_offer.size() == 3 and run.rs_offer.all(func(id): return Tac.is_res(str(id))), "연구 3택1 (%d장)" % run.rs_offer.size())
	_ok(r2.rs_offer == run.rs_offer, "연구 저장 왕복")
	var rp := str(r2.rs_offer[0])
	_ok(r2.command("pick_res", [rp]) == true and r2.rs_offer.is_empty() and int(r2.rs_done.get(rp, 0)) == 1, "연구 고르기 (명령)")
	_ok(not r2.pick_res(rp), "고른 뒤 다시 못 고름")
	var day0 := r2.day
	for i in 3:
		r2.quest_done = true
		r2.pvp_done = true
		r2.advance()
	_ok(r2.day == day0 + 1 and r2.tk_offer.size() == 3 and r2.rs_offer.size() == 3, "다음 아침 다시 두 3택1")
	# 연구 트리 —— 앞 단계를 골라야 다음 단계가 후보
	_ok(not Tac.res_ok("양마 번식", {}, [], []) and Tac.res_ok("양마 번식", {"명마": 1}, [], []), "트리 앞 단계")
	_ok(not Tac.res_ok("양마 번식", {"명마": 1, "양마 번식": 1}, [], []), "트리 단계는 한 번")
	_ok(Tac.res_ok("명마", {"명마": 5}, [], []), "뿌리 연구는 여러 번")
	_ok(not Tac.res_ok("둔전", {}, [], ["위", "위", "위"]) and Tac.res_ok("둔전", {}, [], ["위", "위", "위", "위"]), "둔전 위 4장")
	# 옛 저장 —— 연구 키 없음: 영구 효과 이름으로 고른 연구 어림 · 3택1 에 남은 경제 카드도 고를 수 있다
	var od := d.duplicate(true)
	od.erase("rs_offer")
	od.erase("rs_done")
	od["tk_perm"] = {"notes": ["명마", "병종 단련 (궁병)"], "parts": []}
	od["tk_offer"] = ["돌격 나팔", "강궁"]
	var r5 := Run.new()
	r5.from_dict(JSON.parse_string(JSON.stringify(od)))
	_ok(r5.rs_offer.is_empty() and int(r5.rs_done.get("명마", 0)) == 1 and int(r5.rs_done.get("병종 단련", 0)) == 1, "옛 저장 연구 어림")
	_ok(r5.pick_tac("강궁") and int(r5.rs_done.get("강궁", 0)) == 1, "옛 3택1 의 경제 카드 → 연구로 셈")
	# 옛 저장 (키 없음) —— 기본 3장
	var old := d.duplicate(true)
	for k in ["tk_hand", "tk_plan", "tk_offer", "tk_hist", "tk_perm", "tk_more", "tk_reroll", "tk_draw", "tk_rolls", "rs_offer", "rs_done"]:
		old.erase(k)
	var r3 := Run.new()
	r3.from_dict(old)
	_ok(r3.tk_hand.size() == 3 and r3.tk_plan == ["돌격", "방진", "우회"], "옛 저장 기본값")      # 11/19 기본 계획은 돌격 · 방진 · 우회로 채워 둔다
	# 경제 카드 모두
	for id in Tac.ECON:
		var r4 := Run.new()
		r4.new_game(3)
		r4.rs_offer = [id]
		_ok(r4.pick_res(id), "연구 %s" % id)
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
