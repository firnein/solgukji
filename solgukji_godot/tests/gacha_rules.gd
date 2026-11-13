extends Node
## 군량 지급 · 아이템 뽑기 · 아이템 칸 둘 · 고대 등급 · 진형 재수정 · 험지 보상 점검 (11/13 사용자) —— 실행: godot --headless --path . res://tests/gacha_rules.tscn
## (a) 고대 아이템 16개 (병종마다 무기 · 갑옷)  (b) 페이즈마다 군량  (c) 뽑기 값 · 10연 보장 · 천장 · 유니크 없음 · 저장 왕복
## (d) 무기 · 갑옷 두 칸 장착 · 해제 · 전투로 넘기기 · 능력치  (e) 진형: 9칸 · 줄당 4칸까지 · 봉시 선봉 3 이상 · 방원 선봉 1 이하 · 줄 구성이 서로 다르다  (f) 험지 보상은 전설이 아니다

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
	# (a) 고대 아이템
	var anc: Array = DB.IT.keys().filter(func(k): return DB.IT[k].grade == "고대")
	if anc.size() != 16: _fail("고대 아이템 %d개 (16)" % anc.size())
	for tag in DB.D.TAGORDER:
		for sl in ["weapon", "armor"]:
			if anc.filter(func(k): return DB.IT[k].tag == tag and DB.item_slot(k) == sl).size() != 1:
				_fail("%s 고대 %s 가 하나가 아니다" % [tag, sl])
	if DB.IGRADE_ORDER.find("고대") != 1 or not DB.D.IGRADE.has("고대"): _fail("고대 등급 순서 · 색")
	for k in DB.IT:
		if DB.item_slot(k) == "": _fail("칸 없는 아이템 %s" % k)
	print("(a) 고대 %d개 · 예: %s (%s)" % [anc.size(), DB.IT[anc[0]].name, UI.item_text(anc[0])])

	# (b) 페이즈마다 군량
	var r := _mk(11)
	var g0 := r.grain
	r.dev_autoplay()
	print("(b) 군량 %d → %d (한 페이즈)" % [g0, r.grain])
	if r.grain - g0 != Run.GRAIN_PER_PHASE: _fail("페이즈 군량 +%d (지금 %+d)" % [Run.GRAIN_PER_PHASE, r.grain - g0])

	# (c) 뽑기
	var g := _mk(12)
	g.grain = 0
	if g.command("gacha", [1]) != null or g.gacha_block(1) == "": _fail("군량 없이 뽑힌다")
	if g.gacha_block(3) == "": _fail("3번 뽑기가 된다")
	g.grain = Run.gacha_cost(1)
	var one = g.command("gacha", [1])
	if not (one is Array) or one.size() != 1 or g.grain != 0: _fail("1회 뽑기: %s · 남은 군량 %d" % [str(one), g.grain])
	var order: Array = DB.IGRADE_ORDER
	var hist := {}
	var first_anc := -1
	var pulls := 1
	var max_gap := 0
	var gap := 1
	g.grain = Run.gacha_cost(10) * 40
	for i in 40:
		var bag0: int = g.bag.values().reduce(func(a, b): return a + b, 0)
		var got = g.command("gacha", [10])
		if not (got is Array) or got.size() != 10:
			_fail("10회 뽑기 결과 %s" % str(got))
			break
		if g.bag.values().reduce(func(a, b): return a + b, 0) - bag0 != 10: _fail("가방에 10개가 안 들어왔다")
		if not got.any(func(id): return order.find(DB.IT[id].grade) <= order.find("레어")): _fail("10회에 레어 이상이 없다")
		for id in got:
			var gr: String = DB.IT[id].grade
			hist[gr] = int(hist.get(gr, 0)) + 1
			pulls += 1
			gap += 1
			if gr == "유니크": _fail("뽑기에서 유니크 %s" % id)
			if gr == "고대":
				if first_anc < 0: first_anc = pulls
				max_gap = maxi(max_gap, gap)
				gap = 0
	if g.grain != 0: _fail("10회 값: 남은 군량 %d" % g.grain)
	if max_gap > Run.GACHA_PITY or gap > Run.GACHA_PITY: _fail("천장 %d 를 넘겼다 (가장 긴 간격 %d)" % [Run.GACHA_PITY, maxi(max_gap, gap)])
	if int(hist.get("고대", 0)) < 400 / Run.GACHA_PITY: _fail("400번에 고대 %d개" % int(hist.get("고대", 0)))
	if g.gacha_pity < 0 or g.gacha_pity >= Run.GACHA_PITY: _fail("천장 수 %d" % g.gacha_pity)
	print("(c) 401번: %s · 첫 고대 %d번째 · 고대 사이 가장 긴 간격 %d (천장 %d) · 지금 천장 수 %d" % [str(hist), first_anc, max_gap, Run.GACHA_PITY, g.gacha_pity])
	var d: Dictionary = JSON.parse_string(JSON.stringify(g.to_dict(), "", false, true))
	var g2 := Run.new()
	g2.from_dict(d)
	if g2.gacha_pity != g.gacha_pity or g2.last_gacha.size() != 10 or g2.equip2.size() != 9: _fail("저장 왕복: 천장 %d · 결과 %d · 갑옷 칸 %d" % [g2.gacha_pity, g2.last_gacha.size(), g2.equip2.size()])
	var old := d.duplicate(true)
	old.erase("equip2")
	var g3 := Run.new()
	g3.from_dict(old)
	if g3.equip2.size() != 9: _fail("예전 저장에 갑옷 칸이 안 생긴다")

	# (d) 두 칸 장착
	var e := _mk(13)
	var si := -1
	for i in 9:
		if e.board[i] != null and Run.innate_item(e.board[i]) == null:
			si = i
			break
	var tag: String = DB.C[e.board[si]].tag
	var w: String = anc.filter(func(k): return DB.IT[k].tag == tag and DB.item_slot(k) == "weapon")[0]
	var a: String = anc.filter(func(k): return DB.IT[k].tag == tag and DB.item_slot(k) == "armor")[0]
	e.equip = e._nine()
	e.equip2 = e._nine()
	e.bag = {w: 1, a: 1}
	e.command("set_equip", [si, a])
	e.command("set_equip", [si, w])
	if e.equip[si] != w or e.equip2[si] != a: _fail("두 칸 장착: %s / %s" % [str(e.equip[si]), str(e.equip2[si])])
	if e.equipped_count() != 2 or e.gear_of_slot(si) != [w, a]: _fail("gear_of_slot %s" % str(e.gear_of_slot(si)))
	var other := -1
	for i in 9:
		if i != si and e.board[i] != null and DB.C[e.board[i]].tag == tag:
			other = i
	if other >= 0:
		e.command("set_equip", [other, w])
		if e.equip[other] == w: _fail("한 개뿐인 아이템이 두 칸에 끼워진다")
	var pairs := e.gear_pairs()
	if pairs[si] != [w, a]: _fail("gear_pairs %s" % str(pairs[si]))
	var bt: Battle = RtBattle.make(1)
	var cid: String = e.board[si]
	if bt._gear(cid, [w, a]) != [w, a] or bt._gear(cid, a) != [null, a] or bt._gear(cid, w) != [w, null] or bt._gear(cid, null) != [null, null]: _fail("Battle._gear")
	var q := e.start_quest()
	var res := Run.simulate(q, [], Run.policy_for(q))
	var mine: Array = res.roster.filter(func(u): return u.camp == "A" and int(u.slot) == si)
	if mine.is_empty() or mine[0].item != w or mine[0].get("item2") != a: _fail("전투 명단의 장비 %s" % (str([mine[0].item, mine[0].get("item2")]) if not mine.is_empty() else "-"))
	e.battle = null
	e.command("unequip", [si, "weapon"])
	if e.equip[si] != null or e.equip2[si] != a: _fail("무기만 해제")
	e.command("set_equip", [si, null])
	if e.equipped_count() != 0: _fail("모두 해제")
	e.bag = {w: 1, a: 1}
	var gear := e.recommend_gear()
	if not (w in gear[0]) or not (a in gear[1]): _fail("자동 장착이 두 칸을 채우지 않는다")
	print("(d) %s · 무기 %s · 갑옷 %s" % [DB.C[cid].name, DB.IT[w].name, DB.IT[a].name])

	# (e) 진형
	var txt := []
	for fk in DB.FORM45:
		var n := 0
		var rows := []
		for row in DB.FORM45[fk]:
			var c: int = str(row).count("X")
			if c > 4: _fail("%s: 한 줄 %d칸" % [fk, c])
			if str(row) != str(row).reverse(): _fail("%s: 좌우 비대칭 줄 %s" % [fk, row])
			rows.append(c)
			n += c
		if n != 9: _fail("%s: %d칸" % [fk, n])
		txt.append("%s %s" % [DB.FORM[fk].n, "·".join(rows.map(func(x): return str(x)))])
	var front := func(fk: String) -> int: return DB.FORM[fk].slots.filter(func(s): return s.line == "선봉").size()
	if front.call("bongsi") < 3: _fail("봉시진 선봉 %d (3 이상)" % front.call("bongsi"))
	if front.call("bangwon") > 1: _fail("방원진 선봉 %d (1 이하)" % front.call("bangwon"))
	var shapes := {}
	for fk in DB.FORM45:
		var key := "·".join(DB.FORM45[fk].map(func(x): return str(str(x).count("X"))))
		if shapes.has(key): _fail("%s 와 %s 의 줄 구성이 같다 (%s)" % [fk, shapes[key], key])
		shapes[key] = fk
	print("(e) " + " / ".join(txt))

	# (f) 험지 보상
	var h := _mk(14)
	var tiers := []
	for dd in 7:
		h.day = dd
		tiers.append(h.quest_hard_tier())
		if h.quest_hard_tier() >= 5: _fail("%d일차 험지 보상이 전설" % (dd + 1))
		if h.quest_hard_tier() > Run.quest_top_tier(dd): _fail("%d일차 험지 보상이 토벌 보상보다 높다" % (dd + 1))
	print("(f) 험지 보상 등급(1~7일차) %s · 토벌 최고 %s" % [str(tiers), str(range(7).map(func(x): return Run.quest_top_tier(x)))])

	print("FAIL: ", fails if not fails.is_empty() else "없음")
	get_tree().quit(1 if not fails.is_empty() else 0)
