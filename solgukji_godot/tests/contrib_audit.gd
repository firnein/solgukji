extends Node
## 11/19 장수 기여 집계 점검 —— 결과창(BattleReport)의 피해 · 지속 · 치료 · 지원 수치가 엔진 기록과 같은 뜻인지.
## 실행: godot --headless --path . res://tests/contrib_audit.tscn [-- --n=12 --print]
##   ① 지속 피해 ⊂ 준 피해 (실제 피해 = dmg − 넘친 몫) ② 치료 = 실제 되살린 병력 (사건의 회복량 합 이하, 초과 회복 없음)
##   ③ 깎기 지원은 그 장수가 실제로 건 갑옷 · 결계 약화가 있을 때만 ④ B 시점 뒤집기 · JSON 왕복에서 같은 인물 · 수치
##   ⑤ 예전 기록(htr 없음)은 '기록 없음' ⑥ FINGER —— 승패 · 잔존 · 사건 지문 (표시용 칸 healer 는 뺀다. 고치기 전 코드와 비교용)

func _ready() -> void:
	var args := {}
	for arg in OS.get_cmdline_user_args():
		var kv := arg.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	var n := int(args.get("n", "12"))
	var fails := 0
	var finger := []
	var totals := {"dot": 0.0, "htr": 0.0, "gain": 0.0, "over": 0.0}
	for i in n:
		var tier: int = [4, 5, 6, 7, 8][i % 5]
		var pool := DB.by_tier(tier).filter(func(k): return not DB.is_foe(k))
		var rng := RandomNumberGenerator.new()
		rng.seed = 91900 + i
		var a := _pick(pool, rng, i == 1)
		var b := _pick(pool, rng, false)
		var res: Dictionary = RtBattle.new(91900 + i).run(DB.auto_place(a, "eorin"), "eorin", 100, null, DB.auto_place(b, "hagik"), "hagik", 100, null, "", "", [], {"A": "auto", "B": "auto"})
		fails += _check(res, i, totals, args.has("print") or i == 1)
		if args.has("shot") and i == 1:
			await _shots(res, str(args.shot))
		finger.append(_finger(res))
	print("FINGER ", hash(JSON.stringify(finger)))
	print("TOTALS ", JSON.stringify(totals))
	if fails == 0:
		print("PASS contrib audit: %d battles —— dot ⊂ dmg · heal ≤ events · shred source · flip · JSON · legacy" % n)
	else:
		print("FAIL contrib audit: ", fails)
	get_tree().quit(1 if fails > 0 else 0)


## 첫 판은 전설 주유 + 유생(치료) 하나를 꼭 넣는다
func _pick(pool: Array, rng: RandomNumberGenerator, fixture: bool) -> Array:
	var out := []
	var people := []
	if fixture:
		for k in pool:
			if DB.person(k) == "주유" and out.is_empty():
				out.append(k)
				people.append("주유")
		for k in pool:
			if DB.C[k].tag == "유생" and not people.has(DB.person(k)):
				out.append(k)
				people.append(DB.person(k))
				break
	var cand := pool.duplicate()
	while out.size() < 9 and not cand.is_empty():
		var k: String = cand.pop_at(rng.randi_range(0, cand.size() - 1))
		if not people.has(DB.person(k)):
			out.append(k)
			people.append(DB.person(k))
	return out


func _finger(res: Dictionary) -> Array:
	var ev := []
	for e in res.ev:
		var o: Dictionary = e.duplicate()
		o.erase("healer")
		ev.append(o)
	return [res.win, res.draw, res.left, res.eLeft, hash(JSON.stringify(ev))]


func _check(res: Dictionary, i: int, totals: Dictionary, show: bool) -> int:
	var bad := 0
	var heal_ev := {"A": 0.0, "B": 0.0}
	var shred_from := {}
	for e in res.ev:
		if e.get("fx") == "heal" and e.has("n"):
			heal_ev[str(e.f)[0]] += float(e.n)
		if e.get("fx") == "debuff" and str(e.get("st", "")).begins_with("shred_"):
			shred_from[str(e.get("from", ""))] = true
		if e.has("healer") and str(e.healer)[0] != str(e.f)[0]:
			print("  #%d 치료 출처가 다른 진영 %s → %s" % [i, e.healer, e.f])
			bad += 1
	var htr := {"A": 0.0, "B": 0.0}
	for u in res.roster:
		var real := float(u.dmg) - float(u.over)
		if float(u.dot) > real + 1.0:
			print("  #%d %s 지속 %d > 실제 피해 %d" % [i, u.name, u.dot, real])
			bad += 1
		if float(u.gain) > 0.0 and not shred_from.has(str(u.key)):
			print("  #%d %s 깎기 지원 %d —— 건 약화 사건이 없다" % [i, u.name, u.gain])
			bad += 1
		htr[u.camp] += float(u.htr)
		totals.dot += float(u.dot)
		totals.htr += float(u.htr)
		totals.gain += float(u.gain)
		totals.over += float(u.over)
	for cp in htr:
		if htr[cp] > heal_ev[cp] + 1.0 * res.roster.size():
			print("  #%d %s 치료 합 %d > 회복 사건 합 %d" % [i, cp, htr[cp], heal_ev[cp]])
			bad += 1
	# 결과창 줄 —— B 시점 뒤집기 · JSON 왕복에서 같은 값
	var rep := BattleReport.make(res)
	assert(rep != null and rep._rows("A").size() > 0)
	var flip := BattleReport.make(Run.flip_res(res))
	var js := BattleReport.make(JSON.parse_string(JSON.stringify(res)))
	var keys := ["name", "dmg", "dot", "htr", "hmo", "gain", "mdmg", "kills"]
	for pair in [[rep._rows("A"), flip._rows("B")], [rep._rows("B"), flip._rows("A")], [rep._rows("A"), js._rows("A")]]:
		for j in pair[0].size():
			for k in keys:
				if str(pair[0][j][k]) != str(pair[1][j][k]) and not (pair[0][j][k] is float and absf(float(pair[0][j][k]) - float(pair[1][j][k])) < 0.01):
					print("  #%d 결과창 불일치 %s %s: %s ≠ %s" % [i, pair[0][j].name, k, pair[0][j][k], pair[1][j][k]])
					bad += 1
	# 예전 기록 —— htr 칸이 없으면 '기록 없음' (0 과 구분)
	var old: Dictionary = res.duplicate(true)
	for u in old.roster:
		u.erase("htr")
		u.erase("hmo")
		u.erase("over")
	for r in BattleReport.make(old)._rows("A"):
		if r.rec:
			bad += 1
	rep.free()
	flip.free()
	js.free()
	if show:
		var rows := BattleReport.make(res)
		print("  #%d %s  승=%s  잔존 %d:%d" % [i, "피해 · 지속 · 치료(병력/사기) · 깎기 지원 · 사기 피해", res.win, res.left, res.eLeft])
		for r in rows._rows("A"):
			print("    %-8s %-3s 피해 %6d  지속 %5d  치료 %5d/%3d  지원 %5d  사기 %4d" % [r.name, r.tag, r.dmg, r.dot, r.htr, r.hmo, r.gain, r.mdmg])
		print("    활약: ", rows._feats())
		rows.free()
	return bad


## 결과창 세 기준 캡처 (--shot=폴더, 창 400x860)
func _shots(res: Dictionary, out: String) -> void:
	DirAccess.make_dir_recursive_absolute(out)
	var rep := BattleReport.make(res)
	rep.position = Vector2(12, 12)
	rep.size.x = 376
	rep.max_h = 820
	add_child(rep)
	for v in ["dmg", "heal", "sup"]:
		rep.view = v
		rep._fill()
		await get_tree().create_timer(0.4).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("%s/report_%s.png" % [out, v])
	rep.queue_free()
	await get_tree().process_frame
