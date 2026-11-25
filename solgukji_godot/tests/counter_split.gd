extends Node
## 11/26 받아치기 연쇄 뒤 선공 불리 분해 (측정 전용) —— tests/counter_check 와 같은 실제 대전 덱 · 같은 인자(--in --min --part --parts --out --keep_join --recruit --cap)
## 받아치기를 켠 판만. 받아치기 묶음(ult_clash)마다 그 순간부터 --win 초(기본 5) 동안을 X 진영(먼저 쓴 쪽) / C 진영(받아친 쪽)으로 나눠 센다:
##   u: 터진 고유기 · j: 인연 합류 · cut: 끊긴 수(그 진영 장수가) · dmg: 준 피해(phys · int) · rt: 무너뜨린 적 부대
## 첫 묶음(판의 첫 고유기)만 따로 f_ 로. 한 판 한 줄 jsonl
var idx := {}


func _ready() -> void:
	PlayLog.enabled = false
	var a := {}
	for s in OS.get_cmdline_user_args():
		var kv := s.trim_prefix("--").split("=", true, 1)
		a[kv[0]] = kv[1] if kv.size() > 1 else "1"
	var part := int(a.get("part", "1"))
	var parts := int(a.get("parts", "1"))
	var mn := float(a.get("min", "5.0"))
	var win := float(a.get("win", "5.0"))
	RtBattle.counter_keep_join = str(a.get("keep_join", "1")) != "0"
	RtBattle.counter_recruit = str(a.get("recruit", "1")) != "0"
	RtBattle.counter_recruit_cap = int(a.get("cap", "0"))
	RtBattle.counter_bind_chain = str(a.get("bind", "0")) != "0"
	RtBattle.counter_gate_time = str(a.get("gate", "1")) != "0"
	RtBattle.counter_on = str(a.get("on", "1")) != "0"
	for k in DB.C:
		if DB.is_foe(k):
			continue
		var c: Dictionary = DB.C[k]
		var key := JSON.stringify([c.name, int(c.tier), c.tag])
		if not idx.has(key) or DB.C[idx[key]].kind == "retired":
			idx[key] = k
	var rows: Array = JSON.parse_string(FileAccess.get_file_as_string(str(a.get("in", ""))))
	var sw = load("res://tests/real_myth_swap.gd").new()
	sw.idx = idx
	var f := FileAccess.open(str(a.get("out", "user://counter_split_%d.jsonl" % part)), FileAccess.WRITE)
	var k := 0
	for bi in rows.size():
		var b: Dictionary = rows[bi]
		var av := (_avg(b.me) + _avg(b.foe)) / 2.0
		if av < mn:
			continue
		k += 1
		if k % parts != part - 1:
			continue
		var me: Dictionary = sw._side(b.me)
		var foe: Dictionary = sw._side(b.foe)
		if me.is_empty() or foe.is_empty():
			continue
		var plan := {}
		if not (b.me_plan as Array).is_empty() or not (b.foe_plan as Array).is_empty():
			plan = {"A": {"p": b.me_plan, "own": b.me_own, "perm": []}, "B": {"p": b.foe_plan, "own": [], "perm": []}}
		for flip in [false, true]:
			var bt := RtBattle.new(int(b.seed))
			var r: Dictionary = sw._run_bt(bt, foe if flip else me, me if flip else foe, plan, flip)
			var aw: float = 0.5 if bool(r.draw) else (1.0 if bool(r.win) else 0.0)
			var first := ""
			for e in r.ev:
				if e.get("fx") == "ult_warn" and not e.get("mini", false):
					first = str(e.a).substr(0, 1)
					break
			var row := {"bi": bi, "flip": flip, "first": first, "fw": -1.0 if first == "" else (aw if first == "A" else 1.0 - aw), "aw": aw,
				"ctr": int(bt.stats.get("ult_counters", 0)), "yj": int(bt.stats.get("inyeon_joint", 0))}
			var tot := {}
			var nclash := 0
			for i in r.ev.size():
				var e: Dictionary = r.ev[i]
				if e.get("fx") != "ult_clash":
					continue
				var xc := str(e.a).substr(0, 1)
				var t0 := float(e.get("tm", 0.0))
				var s := _split(r.ev, i, xc, t0, win)
				for kk in s:
					tot[kk] = float(tot.get(kk, 0.0)) + float(s[kk])
				if nclash == 0 and a.has("dump") and int(a.dump) == bi and not flip:
					for j in range(i - 3, r.ev.size()):
						var q: Dictionary = r.ev[j]
						if float(q.get("tm", 0.0)) > t0 + win:
							break
						if q.get("fx") in ["ult", "ult_warn", "ult_join", "ult_cut", "ult_clash", "rout", "inyeon_fin", "inyeon_theme", "ult_dash"]:
							print("DUMP %.2f %s a=%s f=%s %s wait=%s yeon=%s" % [float(q.get("tm", 0.0)), q.fx, q.get("a", ""), q.get("f", ""), q.get("name", ""), q.get("wait", ""), q.get("inyeon", q.get("lead", ""))])
				if nclash == 0:
					for kk in s:
						row["f_" + kk] = s[kk]
					row["f_first"] = xc == first
				nclash += 1
			for kk in tot:
				row[kk] = tot[kk]
			bt.units.clear()
			f.store_line(JSON.stringify(row))
	f.close()
	get_tree().quit(0)


func _split(ev: Array, i0: int, xc: String, t0: float, win: float) -> Dictionary:
	var s := {"xu": 0, "cu": 0, "xj": 0, "cj": 0, "xcut": 0, "ccut": 0, "xdmg": 0.0, "cdmg": 0.0, "xrt": 0, "crt": 0, "xfin": 0, "cfin": 0}
	for i in range(i0, ev.size()):
		var e: Dictionary = ev[i]
		if float(e.get("tm", 0.0)) > t0 + win:
			break
		var fx = e.get("fx")
		var ac := str(e.get("a", "")).substr(0, 1)
		var side := "x" if ac == xc else "c"
		if fx == "ult" and not e.get("mini", false):
			s[side + "u"] += 1
		elif fx == "ult_join":
			s[side + "j"] += 1
		elif fx == "ult_cut":
			var fc := str(e.get("f", "")).substr(0, 1)
			s[("x" if fc == xc else "c") + "cut"] += 1
		elif fx == "phys" or fx == "int":
			s[side + "dmg"] += float(e.get("n", 0.0))
		elif fx == "rout":
			var fc2 := str(e.get("f", "")).substr(0, 1)
			s[("c" if fc2 == xc else "x") + "rt"] += 1      # 무너진 쪽의 상대가 얻은 것
		elif fx == "inyeon_fin" or fx == "inyeon_theme":
			s[side + "fin"] += 1
	return s


func _avg(s: Dictionary) -> float:
	var t := 0.0
	for c in s.cards:
		t += float(c[1])
	return t / maxf(1.0, float(s.cards.size()))
