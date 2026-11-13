extends Node
## 전투 사건 흐름 —— 실행: godot --headless --path . res://tests/ev_timeline.tscn -- --snap=편성.json --day=5
## 실제 덱으로 그날 토벌 한 판: 초마다 평타 · 기술 · 고유기 · 패주 · 군령 · 연쇄가 몇 번 났는지, 그리고 한 판 길이 · 결말
func _ready() -> void:
	var args := {}
	for s in OS.get_cmdline_user_args():
		var kv := s.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	var snaps: Array = JSON.parse_string(FileAccess.open(str(args.snap), FileAccess.READ).get_as_text())
	var day := int(args.get("day", "5")) - 1
	var n := 0
	for s in snaps:
		if int(s.d) != day or int(s.p) != 1:
			continue
		n += 1
		if n > 3: break
		var q: Dictionary = DB.QUEST_ROSTERS[int(s.d)][int(s.p)]
		var foe := DB.auto_place(q.cards, q.form)
		var bt := {"a": s.a, "b": {"cards": foe, "form": q.form, "morale": int(q.get("morale", 100)), "equip": [], "tac": Run.recommend_tac(foe)[0]}, "seed": 77 + n, "title": "", "foe": ""}
		var r := Run.simulate(bt, [], Run.policy_for(bt))
		var bins := {}
		var kinds := {}
		var last_tm := 0.0
		for e in r.ev:
			var fx: String = str(e.get("fx", ""))
			if fx == "": continue
			var tm := float(e.get("tm", 0.0))
			last_tm = maxf(last_tm, tm)
			var b := int(tm / 5.0) * 5
			if not bins.has(b): bins[b] = {}
			bins[b][fx] = bins[b].get(fx, 0) + 1
			kinds[fx] = kinds.get(fx, 0) + 1
		print("== %d일차 토벌 %s · %s · %.0f초 · 잔존 %d:%d" % [day + 1, q.name, "승" if r.win else "패", r.get("len", 0), r.left, r.eLeft])
		print("  전체: ", kinds)
		var ks := bins.keys(); ks.sort()
		for b in ks:
			var d: Dictionary = bins[b]
			print("  %2d~%2ds  평타 %3d · 기술 %2d · 고유기 %d · 패주 %d · 군령 %d · 상태 %d" % [b, b + 5, int(d.get("phys", 0)) + int(d.get("int", 0)), int(d.get("skill", 0)), int(d.get("ult", 0)), int(d.get("rout", 0)), int(d.get("cmd", 0)), int(d.get("status", 0))])
	get_tree().quit()
