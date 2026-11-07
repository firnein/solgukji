extends Node
## 11/8 갑옷 · 결계 · 깎기 · 토벌 성질 · 봇 덱 섞기 점검 (docs/역할_재설계_1108.md 9.1) —— 실행: godot --headless --path . res://tests/guard_check.tscn
## 판정이 설계대로 붙는지만 본다 (승률은 tests/mono_league · tests/guard_grid):
##  1) 병종 막 · 피해 종류 · 카드 한 줄   2) 토벌 성질 —— 우두머리 9부대는 바꿔 쓰고 잡병은 병종 기본
##  3) 깎기 —— 파갑(갑옷) · 현혹 · 요언(결계) 사건이 나고 한 대상에 종류별 하나   4) 봇 덱 —— 같은 병종 3장까지 · 물리 · 책략 각 3장 이상 · 성향 쏠림

var fails := 0


func _ok(cond: bool, what: String) -> void:
	if not cond:
		fails += 1
	print("%s %s" % ["통과" if cond else "실패", what])


func _ready() -> void:
	# 1) 병종 막 · 피해 종류
	var want := {"창병": [0.3, 0.0, "phys"], "기병": [0.15, 0.0, "phys"], "궁병": [0.0, 0.0, "phys"], "도적": [0.0, 0.0, "phys"],
		"책사": [0.0, 0.15, "int"], "모사": [0.0, 0.0, "int"], "술사": [0.0, 0.3, "int"], "유생": [0.0, 0.0, "int"]}
	for tg in want:
		var g := DB.guard_of(tg)
		_ok(is_equal_approx(g.phys, want[tg][0]) and is_equal_approx(g["int"], want[tg][1]) and DB.dmg_kind(tg) == want[tg][2],
			"%s 막 %s · %s" % [tg, g, DB.guard_text(tg)])
	# 2) 토벌 성질 —— 6일차(섞임 60): 선봉 · 전군 줄은 갑옷, 중군 · 후군 줄은 결계. 잡병(9번 칸부터)은 병종 기본
	for day in 7:
		print("   %d일차 성질 %s %s" % [day + 1, DB.quest_trait(day), DB.trait_text(DB.quest_trait(day))])
	var q: Dictionary = DB.QUEST_ROSTERS[5][0]
	var cards := DB.auto_place(q.cards, q.form)
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	cards.append_array(DB.horde_rabble(q.cards, 6, rng))
	var form: String = DB.HORDE_PFX + q.form
	Battle.side_trait = {"A": {}, "B": DB.quest_trait(5)}
	var bt: Battle = RtBattle.make(1)
	bt._setup(cards.slice(0, 9), q.form, 100, null, cards, form, 100, null, "", "", [], {"A": "smart", "B": "smart"})
	Battle.side_trait = {"A": {}, "B": {}}
	var boss_ok := true
	var rab_ok := true
	var a_ok := true
	for u in bt.units:
		if u.camp == "A":
			a_ok = a_ok and u.shield == DB.guard_of(u.c.tag)
		elif u.slot < 9:
			var front: bool = u.line in ["선봉", "전군"]
			boss_ok = boss_ok and is_equal_approx(u.shield.phys, 0.6 if front else 0.0) and is_equal_approx(u.shield["int"], 0.0 if front else 0.6)
		else:
			rab_ok = rab_ok and u.shield == DB.guard_of(u.c.tag)
	_ok(boss_ok, "6일차 우두머리 9부대 —— 앞 갑옷 60 · 뒤 결계 60")
	_ok(rab_ok, "6일차 잡병 —— 병종 기본")
	_ok(a_ok, "아군 —— 성질 없음 (병종 기본)")
	# 3) 깎기 사건 —— 깎기 특기 장수 3 + 무작위 6 대 창병 · 술사 6 + 무작위 3
	for t in [5, 7]:
		var pool: Array = DB.by_tier(t).filter(func(k): return not DB.is_kiin(k))
		var phys_sh := pool.filter(func(k): return _has_key(k, ["cut_def", "first_cut", "rush"], ["현혹"]))
		var int_sh := pool.filter(func(k): return _has_trait(k, ["현혹", "요언"]))
		var spear := pool.filter(func(k): return DB.C[k].tag == "창병")
		var occul := pool.filter(func(k): return DB.C[k].tag == "술사")
		print("   등급 %d —— 갑옷 깎기 %d명 · 결계 깎기 %d명 (%s)" % [t, phys_sh.size(), int_sh.size(), " ".join(int_sh.map(func(k): return DB.C[k].name))])
		if phys_sh.is_empty() or spear.is_empty() or occul.is_empty():
			continue
		var n_phys := 0
		var n_int := 0
		var n_shreds := 0
		var multi := false
		for g in 6:
			var a := []
			for i in 3: a.append((phys_sh if i < 2 or int_sh.is_empty() else int_sh)[rng.randi() % (phys_sh if i < 2 or int_sh.is_empty() else int_sh).size()])
			for i in 6: a.append(pool[rng.randi() % pool.size()])
			var b := []
			for i in 3: b.append(spear[rng.randi() % spear.size()])
			for i in 3: b.append(occul[rng.randi() % occul.size()])
			for i in 3: b.append(pool[rng.randi() % pool.size()])
			var r := RtBattle.make(rng.randi() % 100000).run(DB.auto_place(a, "eorin"), "eorin", 100, null, DB.auto_place(b, "eorin"), "eorin", 100, null,
				"", "", [], {"A": "smart", "B": "smart"})
			for e in r.ev:
				match str(e.get("st", "")):
					"shred_phys": n_phys += 1
					"shred_int": n_int += 1
			n_shreds += int(r.stats.shreds)
		_ok(n_phys > 0, "등급 %d 갑옷 깎기 사건 %d · 걸린 수 %d" % [t, n_phys, n_shreds])
		if not int_sh.is_empty():
			_ok(n_int > 0, "등급 %d 결계 깎기 사건 %d" % [t, n_int])
	# 깎기 규칙 —— 같은 값 · 다른 출처는 무시, 같은 출처는 턴만, 더 크면 바꿔 끼움
	var b2: Battle = Battle.new(3)
	var p5: Array = DB.by_tier(5)
	b2._setup(p5.slice(0, 9), "eorin", 100, null, p5.slice(9, 18), "eorin", 100, null, "", "", [], {"A": "smart", "B": "smart"})
	var x: Battle.Unit = b2.units[0]
	var y: Battle.Unit = b2.units[1]
	var d: Battle.Unit = b2.units[9]
	d.shred.phys = {"v": 0.0, "t": 0, "by": ""}
	b2._shred(x, d, "phys", 0.1, 3, "점검")
	b2._shred(y, d, "phys", 0.1, 3, "점검")
	var r1: bool = d.shred.phys.by == x.key
	d.shred.phys.t = 1
	b2._shred(x, d, "phys", 0.05, 3, "점검")
	var r2: bool = d.shred.phys.t == 3 and is_equal_approx(d.shred.phys.v, 0.1)
	b2._shred(y, d, "phys", 0.15, 2, "점검")
	var r3: bool = d.shred.phys.by == y.key and is_equal_approx(d.shred.phys.v, 0.15) and d.shred.phys.t == 2
	d.shield.phys = 0.3
	var r4: bool = is_equal_approx(b2._shield(d, "phys"), 0.15)
	b2._shred_tick()
	b2._shred_tick()
	var r5: bool = is_equal_approx(b2._shield(d, "phys"), 0.3)
	_ok(r1 and r2 and r3 and r4 and r5, "깎기 규칙 (먼저 건 것 유지 %s · 같은 출처 턴만 %s · 더 크면 교체 %s · 막 %s · 턴 끝 %s)" % [r1, r2, r3, r4, r5])
	# 4) 봇 덱 섞기
	var bad := 0
	var ratio := {"물리": [0, 0], "지략": [0, 0], "균형": [0, 0]}
	for i in 300:
		var style: String = ["물리", "지략", "균형"][i % 3]
		var eb := DB.gen_board([300, 1200, 4000, 9000, 20000][i % 5], style, rng)
		var cnt := {}
		var ph := 0
		for k in eb.cards:
			cnt[DB.C[k].tag] = int(cnt.get(DB.C[k].tag, 0)) + 1
			ph += 1 if DB.dmg_kind(DB.C[k].tag) == "phys" else 0
		if cnt.values().max() > 3 or ph < 3 or 9 - ph < 3:
			bad += 1
		ratio[style][0] += ph
		ratio[style][1] += 9 - ph
	_ok(bad == 0, "봇 덱 300개 —— 규칙 어긴 덱 %d · 물리:책략 평균 물리 %.1f:%.1f · 지략 %.1f:%.1f · 균형 %.1f:%.1f" % [bad,
		ratio["물리"][0] / 100.0, ratio["물리"][1] / 100.0, ratio["지략"][0] / 100.0, ratio["지략"][1] / 100.0, ratio["균형"][0] / 100.0, ratio["균형"][1] / 100.0])
	print("갑옷 · 결계 점검 실패 %d" % fails)
	get_tree().quit()


func _has_key(k: String, keys: Array, skip: Array) -> bool:
	var ps = DB.passives_of(k)
	if ps == null:
		return false
	for t in ps.traits:
		if skip.has(t.name):
			continue
		for key in keys:
			if t.m.has(key):
				return true
	return false


func _has_trait(k: String, names: Array) -> bool:
	var ps = DB.passives_of(k)
	if ps == null:
		return false
	return ps.traits.any(func(t): return names.has(t.name))
