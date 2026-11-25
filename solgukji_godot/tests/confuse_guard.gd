extends Node
## 혼란 연쇄 방지 점검 (11/25) —— 실제 온라인 대전 기록의 덱으로 부대마다 혼란 시간 · 혼란에 걸린 횟수 · 일반 기술 횟수를 잰다 (측정 전용)
## 입력: python tools/scripts/real_battles.py <playlog_online 폴더> <출력 json>
## 실행: godot --headless --path . res://tests/confuse_guard.tscn -- --in=C:/.../real.json --mode=old|base|new [--imm_min=6 --imm_mul=2 --res=1] --part=1 --parts=4 --out=C:/.../x.jsonl
##   old  : 예전 엔진 (같은 기술 버프가 쌓이고 · 혼란 내성 없음)
##   base : 같은 기술 버프는 새로 고침만 (11/25 조운 71회 고침) · 혼란 내성 없음
##   new  : 둘 다 켬 (Battle.cf_guard)
## 한 줄 = 한 판: {bi, len, win, draw, u: [[진영, 이름, 등급, 혼란 초, 혼란 걸림, 살아 있던 초(틱으로 셈), 기술 횟수, 남은 병력 비율], …]}
## 요약은 python 으로 (6급 이상 혼란 시간 비율 분포 · 최악 사례 · 혼란 덱 승률)


func _ready() -> void:
	PlayLog.enabled = false
	get_tree().create_timer(7000.0).timeout.connect(func(): get_tree().quit(1))
	var a := {}
	for s in OS.get_cmdline_user_args():
		var kv := s.trim_prefix("--").split("=", true, 1)
		a[kv[0]] = kv[1] if kv.size() > 1 else "1"
	var mode := str(a.get("mode", "new"))
	Battle.buff_src = mode != "old"
	Battle.cf_guard = mode == "new"
	if a.has("imm_min"): Battle.cf_imm_min = float(a.imm_min)      # 내성 수치 비교용
	if a.has("imm_mul"): Battle.cf_imm_mul = float(a.imm_mul)
	if a.has("max_sec"): Battle.cf_max_sec = float(a.max_sec)
	if a.has("res"):      # 등급 저항 배율 (1 = 기본표)
		for t in Battle.cf_tier_res: Battle.cf_tier_res[t] = float(Battle.cf_tier_res[t]) * float(a.res)
	var part := int(a.get("part", "1"))
	var parts := int(a.get("parts", "1"))
	var sw = load("res://tests/real_myth_swap.gd").new()
	for k in DB.C:
		if DB.is_foe(k):
			continue
		var c: Dictionary = DB.C[k]
		var key := JSON.stringify([c.name, int(c.tier), c.tag])
		if not sw.idx.has(key) or DB.C[sw.idx[key]].kind == "retired":
			sw.idx[key] = k
	var rows: Array = JSON.parse_string(FileAccess.get_file_as_string(str(a.get("in", ""))))
	var f := FileAccess.open(str(a.get("out", "user://confuse_guard.jsonl")), FileAccess.WRITE)
	var skipped := 0
	for bi in rows.size():
		if bi % parts != part - 1:
			continue
		var b: Dictionary = rows[bi]
		var me: Dictionary = sw._side(b.me)
		var foe: Dictionary = sw._side(b.foe)
		if me.is_empty() or foe.is_empty():
			skipped += 1
			continue
		var plan := {}
		if not (b.me_plan as Array).is_empty() or not (b.foe_plan as Array).is_empty():
			plan = {"A": {"p": b.me_plan, "own": b.me_own, "perm": []}, "B": {"p": b.foe_plan, "own": [], "perm": []}}
		var bt := CfProbe.new(int(b.seed))
		var r: Dictionary = sw._run_bt(bt, me, foe, plan, false)
		var hits := {}
		var sk := {}
		for e in r.ev:
			var fx = e.get("fx")
			if fx == "status" and e.get("st") == "confuse" and e.has("spread"):
				hits[e.f] = hits.get(e.f, 0) + 1
			elif fx == "skill":
				sk[e.a] = sk.get(e.a, 0) + 1
		var us := []
		for u in bt.units:
			if u.camp != "A" and u.camp != "B":
				continue
			us.append([u.camp, str(u.c.name), int(u.c.tier), snappedf(float(bt.cf_t.get(u.key, 0.0)), 0.1), int(hits.get(u.key, 0)),
				snappedf(float(bt.live_t.get(u.key, 0.0)), 0.1), int(sk.get(u.key, 0)), snappedf(maxf(0.0, u.troops) / maxf(1.0, u.max), 0.01)])
		f.store_line(JSON.stringify({"bi": bi, "len": r.len, "win": bool(r.win), "draw": bool(r.draw), "u": us}))
		bt.units.clear()
	f.close()
	print("CFG done mode=%s part=%d/%d skipped=%d" % [mode, part, parts, skipped])
	get_tree().quit(0)


## 틱마다 혼란 상태인 부대의 시간을 센다 (두 엔진 모드에서 같은 잣대)
class CfProbe extends RtBattle:
	var cf_t := {}
	var live_t := {}
	var _last := -1.0
	func _tick_units() -> Array:      # 한 틱에 여러 번 불린다 —— 시각이 바뀐 첫 번만 센다
		if _tm != _last:
			_last = _tm
			for u in units:
				if u.alive:
					live_t[u.key] = float(live_t.get(u.key, 0.0)) + TICK
					if has_st(u, "confuse"):
						cf_t[u.key] = float(cf_t.get(u.key, 0.0)) + TICK
		return super._tick_units()
