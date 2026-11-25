extends Node
## 11/25 고유기 받아치기 점검 —— 실제 온라인 대전 기록의 후반 덱 쌍으로 RtBattle.counter_on 끔 / 켬을 비교한다 (측정 전용, 기록은 읽기만)
## 입력: 기록 정리본 JSON —— python tools/scripts/real_battles.py <playlog_online 폴더> <출력 json>
## 실행: godot --headless --path . res://tests/counter_check.tscn -- --in=C:/.../real_battles.json [--min=5.0] [--part=1 --parts=4] [--out=C:/.../x.jsonl]
## 평균 등급(양쪽 카드 평균)이 --min 이상인 판만. 판마다 기록 그대로(내 쪽 A)와 진영을 뒤집은 것, 각각 끔 · 켬 —— 한 줄씩 jsonl 로 적는다:
##   first: 첫 (미니 아닌) 고유기 기 모으기를 시작한 진영 · fw: 그 진영이 이겼나(1 · 0.5 · 0) · cuts: 끊김 · ults: 터진 고유기 · tm: 전투 길이 · ctr: 받아치기 묶음 수
## 끝나면 끔 / 켬 요약을 찍는다 (parts 로 나눴으면 python 으로 합친다)
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
	var f := FileAccess.open(str(a.get("out", "user://counter_check_%d.jsonl" % part)), FileAccess.WRITE)
	var sum := {false: [0, 0.0, 0, 0, 0.0, 0, 0.0], true: [0, 0.0, 0, 0, 0.0, 0, 0.0]}      # 판 · 첫 고유기 진영 승 · 끊김 · 고유기 · 길이 · 받아치기 · A 승
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
			for on in [false, true]:
				RtBattle.counter_on = on
				var bt := RtBattle.new(int(b.seed))
				var r: Dictionary = sw._run_bt(bt, foe if flip else me, me if flip else foe, plan, flip)
				var first := ""
				var ults := 0
				var tm := 0.0
				for e in r.ev:
					tm = maxf(tm, float(e.get("tm", 0.0)))
					var fx = e.get("fx")
					if fx == "ult_warn" and first == "" and not e.get("mini", false):
						first = str(e.a).substr(0, 1)
					elif fx == "ult" and not e.get("mini", false):
						ults += 1
				var aw: float = 0.5 if bool(r.draw) else (1.0 if bool(r.win) else 0.0)
				var fw: float = -1.0 if first == "" else (aw if first == "A" else 1.0 - aw)
				var cuts := int(bt.stats.get("ult_cuts", 0))
				var ctr := int(bt.stats.get("ult_counters", 0))
				bt.units.clear()
				f.store_line(JSON.stringify({"bi": bi, "av": snappedf(av, 0.01), "flip": flip, "on": on, "first": first, "fw": fw, "aw": aw, "cuts": cuts, "ults": ults, "tm": tm, "ctr": ctr,
					"cu": int(bt.stats.get("counter_units", 0)), "nocut": int(bt.stats.get("counter_nocut", 0)), "last": int(bt.stats.get("counter_last", 0))}))
				var s: Array = sum[on]
				s[0] += 1
				s[1] += maxf(fw, 0.0) if fw >= 0.0 else 0.5
				s[2] += cuts
				s[3] += ults
				s[4] += tm
				s[5] += ctr
				s[6] += aw
	f.close()
	RtBattle.counter_on = true
	for on in [false, true]:
		var s: Array = sum[on]
		var n := maxi(1, s[0])
		print("ZGL_CTR %s 판 %d · 첫 고유기 진영 승률 %.1f%% · A 승률 %.1f%% · 끊김 %.2f · 고유기 %.1f · 길이 %.1f초 · 받아치기 %.2f" % ["켬" if on else "끔", s[0], 100.0 * s[1] / n, 100.0 * s[6] / n, float(s[2]) / n, float(s[3]) / n, s[4] / n, float(s[5]) / n])
	get_tree().quit(0)


func _avg(s: Dictionary) -> float:
	var t := 0.0
	for c in s.cards:
		t += float(c[1])
	return t / maxf(1.0, float(s.cards.size()))
