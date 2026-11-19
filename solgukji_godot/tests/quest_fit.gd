extends Node
## 토벌 난이도 맞추기 (11/19 사용자: 고정 난이도로 두고 온라인 기록으로 값을 맞춘다) —— 실행:
##   godot --headless --path . res://tests/quest_fit.tscn -- --logs=<playlog_online 폴더> [--muls=0.6,0.8,1,1.2] [--seeds=3] [--days=3] [--only=2_]
## 온라인 기록의 토벌 battle_start 마다 그때 플레이어 덱(장수 이름 · 진형 · 작전 · 사기)을 그대로 세우고, 같은 날짜 · 시간대 · 험지 여부의 토벌 상대와
## 적 병력 배율(tr_mul) 후보마다 시드 몇 개로 다시 싸운다. 장비 · 군략은 기록에 없어 뺀다 (플레이어가 조금 약하게 나온다).
## 출력: 시점 · 일반/험지 · 표본 수 · 실제 승률(기록) · 배율마다 재현 승률 —— "FIT|" 줄

func _ready() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--") and "=" in a:
			args[a.substr(2, a.find("=") - 2)] = a.substr(a.find("=") + 1)
	var muls: Array = Array(str(args.get("muls", "0.6,0.7,0.8,0.9,1.0,1.15,1.3")).split(",")).map(func(x): return float(x))
	var seeds := int(args.get("seeds", "3"))
	var max_day := int(args.get("days", "3"))
	var by_name := {}
	for id in DB.C:
		by_name[str(DB.C[id].name)] = id
	var samples := []      # [day, phase, hard, side, win]
	var skipped := 0
	var dir := DirAccess.open(str(args.get("logs", "")))
	for f in dir.get_files():
		if not f.ends_with(".jsonl"):
			continue
		var fa := FileAccess.open(str(args.logs).path_join(f), FileAccess.READ)
		var st = null
		while not fa.eof_reached():
			var ln := fa.get_line()
			if ln == "":
				continue
			var e = JSON.parse_string(ln)
			if not (e is Dictionary):
				continue
			if e.get("ev") == "battle_start" and e.get("kind") == "quest" and int(e.day) < max_day:
				st = e
			elif e.get("ev") == "battle_end" and e.get("kind") == "quest" and st != null:
				var ids := []
				var ok := true
				for c in st.me.cards:
					if not by_name.has(str(c[0])):
						ok = false
						break
					ids.append(by_name[str(c[0])])
				if ok and not ids.is_empty():
					var form: String = str(st.get("form", "eorin"))
					var side := {"cards": DB.auto_place(ids, form), "form": form, "morale": int(st.get("morale", 100)), "equip": [], "tac": str(st.get("tac", "균형"))}
					var hard: bool = "험지" in str(st.get("title", ""))
					samples.append([int(st.day), int(st.phase), hard, side, bool(e.win)])
				else:
					skipped += 1
				st = null
	print("표본 %d (이름을 못 찾아 뺀 것 %d)" % [samples.size(), skipped])
	var groups := {}
	for s in samples:
		var k := "%d_%d_%s" % [s[0], s[1], "험지" if s[2] else "일반"]
		if not groups.has(k):
			groups[k] = []
		groups[k].append(s)
	var keys := groups.keys()
	keys.sort()
	for k in keys:
		if args.has("only") and not str(k).begins_with(str(args.only)):      # --only=2_ —— 그 시점만
			continue
		var g: Array = groups[k]
		var real := 0
		for s in g:
			real += 1 if s[4] else 0
		var out := []
		for m in muls:
			var w := 0
			var n := 0
			for s in g:
				for sd in seeds:
					var r := Run.new()
					r.new_game(7000 + sd)
					r.mp = true
					r.day = s[0]
					r.phase = s[1]
					r.quest_hard = s[2]
					var bt := r.start_quest()
					bt.a = (s[3] as Dictionary).duplicate(true)
					bt.b["tr_mul"] = float(bt.b.get("tr_mul", 1.0)) * float(m)
					bt.seed = 1000 + sd * 7919 + n
					var res := Run.simulate(bt, [], Run.policy_for(bt))
					w += 1 if res.win else 0
					n += 1
			out.append("×%.2f %d%%" % [m, roundi(100.0 * w / maxf(1, n))])
		print("FIT|%s|표본 %d|실제 %d%%|%s" % [k, g.size(), roundi(100.0 * real / g.size()), " · ".join(out)])
	get_tree().quit()
