extends Node
## 갈무리 「모두 조합」(자동 조합) 점검 (11/15 사용자: "자동조합 여러명일 때 프리징") —— 실행: godot --headless --path . res://tests/auto_forge_perf.tscn
## ① 같은 결과: 작은 판(자동 진행한 판 여러 개 × 갈무리 장수 여럿)에서 새 알맹이 ForgeTree.chain 이 예전 방식(아래 _old_chain —— 한도 40 ·
##    나무 전체에서 가장 깊은 것부터)과 같은 차례로 같은 것을 만든다 · 손패도 같다
## ② 완성 순서: 재료 차례(order)를 주면 그 재료의 가지부터 끝낸다 · 「순서대로 모두 조합」은 갈무리 차례(pins)대로 —— 겹치는 재료는 앞 장수가 가져간다
## ③ 빠르기: 카드 500장 이상 · 갈무리 6명에서 화면(GameScreen)째로 모두 조합 —— 예전에는 한 장 조합할 때마다 저장 + 화면 전체 다시 그리기를 해
##    한 번에 0.5 ~ 0.8초(PC · 헤드리스 기준, 휴대폰은 몇 배)씩 멈췄다. 이제 다시 그리기는 조합 묶음마다 한 번 (GameScreen.render 횟수를 센다)
## ④ 판매 확인: 갈무리 재료(ForgeTree.needs_of) —— 팔면 모자라게 되는 재료만 대상

const OLD_CAP := 40
var fails := 0


func _ok(cond: bool, msg: String) -> void:
	print("%s %s" % ["  통과" if cond else "  실패", msg])
	if not cond:
		fails += 1


# ───────── 예전 방식 (6b3beb4 의 forge_tree.gd 를 화면 없이 옮긴 것) ─────────

func _old_node(run: Run, k: String, n: int, depth: int) -> Dictionary:
	var have := run.have(k)
	var nd := {"k": k, "need": n, "have": have, "ok": depth > 0 and have >= n, "kids": []}
	if nd.ok or not DB.RECOF.has(k) or depth >= ForgeTree.MAX_DEPTH:
		return nd
	var want := n - have if depth > 0 else 1
	var m := Run.mat_count(DB.RECOF[k])
	for q in m:
		if DB.C[q].tier <= ForgeTree.BASIC_TIER:
			continue
		nd.kids.append(_old_node(run, q, m[q] * want, depth + 1))
	return nd


func _old_deepest(run: Run, nd: Dictionary, depth: int, best: Array) -> void:
	for c in nd.kids:
		_old_deepest(run, c, depth + 1, best)
	if not nd.ok and run.can_forge(nd.k) and depth > best[1]:
		best[0] = nd.k
		best[1] = depth


func _old_chain(run: Run, root: String) -> Array:
	var made := []
	for _i in OLD_CAP:
		if run.can_forge(root):
			if run.forge(root):
				made.append(root)
			break
		var best := [null, 0]
		_old_deepest(run, _old_node(run, root, 1, 0), 0, best)
		if best[0] == null or not run.forge(best[0]):
			break
		made.append(best[0])
	return made


func _clone(r: Run) -> Run:
	var c := Run.new()
	c.from_dict(r.to_dict().duplicate(true))
	return c


func _big_run(seed_v: int) -> Run:
	var r := Run.new()
	r.new_game(seed_v)
	for k in DB.C:
		if DB.is_foe(k) or DB.is_kiin(k):
			continue
		var t := int(DB.C[k].tier)
		if t <= 2:
			r.inv[k] = 60
		elif t == 3:
			r.inv[k] = 3
	return r


func _roots(n: int) -> Array:
	var roots := []
	for k in DB.by_tier(7):
		if DB.RECOF.has(k) and not DB.is_kiin(k) and roots.size() < n:
			roots.append(k)
	return roots


func _ready() -> void:
	PlayLog.enabled = false
	_same_results()
	_order_rules()
	_needs()
	await _perf()
	print("실패 %d" % fails)
	get_tree().quit(1 if fails > 0 else 0)


func _same_results() -> void:
	print("① 예전 방식과 같은 결과")
	var cases := 0
	var forged := 0
	var diff := 0
	var targets: Array = DB.D.RECDEF.map(func(x): return x[0]).filter(func(k): return DB.C[k].tier >= 4 and not DB.is_foe(k))
	for seed_v in [1, 2, 3, 4, 5, 6]:
		var base := Run.new()
		base.new_game(seed_v)
		for i in 4 + seed_v:
			base.dev_autoplay()
			if base.over != null:
				break
		base.over = null
		for k in DB.BASE:      # 기본패를 넉넉히 —— 사슬이 여러 단 이어지게
			base.inv[k] = int(base.inv.get(k, 0)) + 6 + seed_v
		for root in targets:
			if base.have(root) > 0 and DB.is_kiin(root):
				continue
			var a := _clone(base)
			var b := _clone(base)
			var ma := _old_chain(a, root)
			var mb: Array = ForgeTree.chain(b, root, func(k): return b.forge(k), [], OLD_CAP)
			cases += 1
			forged += ma.size()
			if ma != mb or a.inv != b.inv or a.board != b.board:
				diff += 1
				if diff <= 3:
					printerr("  다름 씨앗 %d · %s: 예전 %s / 지금 %s" % [seed_v, DB.C[root].name, str(ma), str(mb)])
	_ok(diff == 0, "작은 판 %d경우(조합 %d번) 모두 예전과 같은 차례 · 같은 손패 (다름 %d)" % [cases, forged, diff])
	_ok(forged > 50, "비교한 조합이 충분하다 (%d번)" % forged)


func _order_rules() -> void:
	print("② 완성 순서")
	var root := ""
	for k in _roots(6):
		var ms: Array = Run.mat_count(DB.RECOF[k]).keys().filter(func(q): return DB.C[q].tier > ForgeTree.BASIC_TIER and DB.RECOF.has(q))
		if ms.size() >= 2:
			root = k
			break
	var mats: Array = Run.mat_count(DB.RECOF[root]).keys().filter(func(q): return DB.C[q].tier > ForgeTree.BASIC_TIER and DB.RECOF.has(q))
	var last: String = mats[mats.size() - 1]
	var r := _big_run(5)
	var order := [last]
	var made: Array = ForgeTree.chain(r, root, func(k): return r.forge(k), order)
	var at := made.find(last)
	var others_before := false
	for i in maxi(at, 0):
		if mats.has(made[i]) and made[i] != last:
			others_before = true
	_ok(at >= 0 and not others_before, "%s: 차례를 [%s] 먼저로 —— 다른 재료(%s)보다 먼저 완성 (%d번째)" % [DB.C[root].name, DB.C[last].name,
		" · ".join(mats.filter(func(q): return q != last).map(func(q): return DB.C[q].name)), at + 1])
	_ok(made.size() > 0 and made[made.size() - 1] == root and r.have(root) == 1, "차례를 바꿔도 끝까지 만든다 (조합 %d번 · %s 보유 %d)" % [made.size(), DB.C[root].name, r.have(root)])
	var r0 := _big_run(5)
	var made0: Array = ForgeTree.chain(r0, root, func(k): return r0.forge(k))
	_ok(made0.size() == made.size(), "차례를 바꿔도 조합 수는 같다 (%d = %d)" % [made0.size(), made.size()])
	_ok(ForgeTree.sorted_mats(["a", "b", "c"], ["c", "x", "a"]) == ["c", "a", "b"], "sorted_mats: 정한 차례 먼저 · 나머지는 조합법 차례")


func _needs() -> void:
	print("④ 갈무리 재료 (판매 확인)")
	var root: String = _roots(1)[0]
	var r := Run.new()
	r.new_game(7)
	r.inv = {}
	var nd: Dictionary = ForgeTree.needs_of(r, [root])
	var m := Run.mat_count(DB.RECOF[root])
	var all := true
	for q in m:
		if not nd.has(q) or int(nd[q].need) < int(m[q]) or str(nd[q].root) != root:
			all = false
	_ok(all, "%s 의 직접 재료 %d종이 모두 필요 목록에 (아래 재료까지 %d종)" % [DB.C[root].name, m.size(), nd.size()])
	var q0: String = m.keys()[0]
	r.inv[q0] = int(m[q0]) + 2
	var nd2: Dictionary = ForgeTree.needs_of(r, [root])
	_ok(r.have(q0) - 1 >= int(nd2[q0].need), "넉넉히 가진 재료(%s %d장 · 필요 %d)는 팔아도 모자라지 않는다 —— 확인 대상 아님" % [DB.C[q0].name, r.have(q0), int(nd2[q0].need)])


func _perf() -> void:
	print("③ 빠르기 (화면째)")
	Run.delete_save()
	var gs: GameScreen = load("res://scenes/game.tscn").instantiate()
	add_child(gs)
	await get_tree().create_timer(0.3).timeout
	var r := _big_run(5)
	var cards := 0
	for k in r.inv:
		cards += int(r.inv[k])
	gs.run = r
	if is_instance_valid(gs._title):
		gs._title.visible = false
	var roots := _roots(6)
	gs.forge_tree.pins = roots.duplicate()
	gs.forge_tree.morder = {}
	gs.go("forge")
	await get_tree().process_frame
	# 알맹이만 (화면 없이) —— 같은 판을 복사해 여섯 장수를 잇달아
	var pure := _clone(r)
	var t0 := Time.get_ticks_usec()
	var pure_n := 0
	for root in roots:
		pure_n += ForgeTree.chain(pure, root, func(k): return pure.forge(k)).size()
	var pure_ms := (Time.get_ticks_usec() - t0) / 1000.0
	_ok(pure_ms < 150.0, "알맹이: 카드 %d장 · 갈무리 %d명 · 조합 %d번에 %.1f ms (150 ms 안)" % [cards, roots.size(), pure_n, pure_ms])
	# 화면째 —— 한 장수씩 「모두 조합」
	var worst := 0.0
	var total := 0.0
	var steps := 0
	for root in roots.slice(0, 3):
		var before := r._card_count()
		var t1 := Time.get_ticks_usec()
		gs.forge_tree.forge_chain(root)
		var ms := (Time.get_ticks_usec() - t1) / 1000.0
		worst = maxf(worst, ms)
		total += ms
		steps += 1
		print("    모두 조합 %s: %.0f ms · 보유 %d · 카드 %d → %d" % [DB.C[root].name, ms, r.have(root), before, r._card_count()])
	_ok(worst < 300.0, "「모두 조합」 한 번 가장 느린 것 %.0f ms (300 ms 안 —— 예전 496 ~ 834 ms)" % worst)
	# 남은 셋은 「순서대로 모두 조합」 한 번에
	var t2 := Time.get_ticks_usec()
	gs.forge_tree.forge_all()
	var all_ms := (Time.get_ticks_usec() - t2) / 1000.0
	var got := 0
	for root in roots:
		got += r.have(root)
	_ok(all_ms < 400.0, "「순서대로 모두 조합」(남은 %d명) %.0f ms (400 ms 안)" % [roots.size() - 3, all_ms])
	print("    완성 %d / %d명 · 남은 갈무리 %d" % [got, roots.size(), gs.forge_tree.pins.size()])
	_ok(got >= 3 and got == roots.size() - gs.forge_tree.pins.size(), "여섯 가운데 %d명 완성 (재료가 닿는 만큼) · 완성한 장수는 갈무리에서 빠졌다" % got)
	_ok(r.to_dict().inv == pure.to_dict().inv, "화면째 결과 = 알맹이 결과 (같은 손패)")
	gs.forge_tree.clear()
	await get_tree().process_frame
