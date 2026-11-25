extends Node
## 온라인 봇 전투력 맞추기 (11/19 사용자: 유저봇 전투력도 온라인 대전의 유저 플레이를 기반으로) —— 실행:
##   godot --headless --path . res://tests/bot_fit.tscn -- --logs=<playlog_online 폴더> [--muls=0.8,1,1.2] [--seeds=2]
## 온라인 기록의 사람 대 봇 대전(battle_start · foe_human 아님 · 그림자 · 유랑군 제외)마다 그때 사람 덱(장수 이름 · 진형 · 작전 · 사기)을 세우고,
## 그때 봇 전력(foe.pv)에 배율 후보를 곱한 봇 군세(Run.bot_side —— 진형으로 봇 성향을 되짚는다)와 시드 몇 개로 다시 싸운다.
## 사람 장비 · 군략은 기록에 없어 뺀다. 출력: 일차 · 표본 · 실제 사람 승률 · 배율마다 재현 사람 승률 —— "BOT|" 줄

func _ready() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--") and "=" in a:
			args[a.substr(2, a.find("=") - 2)] = a.substr(a.find("=") + 1)
	var muls: Array = Array(str(args.get("muls", "0.8,1.0,1.2,1.4,1.6")).split(",")).map(func(x): return float(x))
	var seeds := int(args.get("seeds", "2"))
	var material := str(args.get("material", "0")) == "1"      # 11/25 유저봇(재료 봇) —— 배율 대신 사람과 같은 보급으로 자란 봇 (Run._bot_material_grow), 시드마다 한 봇을 21단계 키워 둔다
	var mats := {}
	Run.bot_human_econ = str(args.get("old", "0")) != "1"
	var since := str(args.get("since", ""))      # 이 이름(날짜) 이후 기록만
	var by_name := {}
	for id in DB.C:
		by_name[str(DB.C[id].name)] = id
	var form_style := {}
	for st in DB.STYLE_FORM:
		form_style[DB.STYLE_FORM[st]] = st
	var samples := []      # [day, phase, side, foe_pv, style, win]
	var dir := DirAccess.open(str(args.get("logs", "")))
	for f in dir.get_files():
		if not f.ends_with(".jsonl") or f < since:
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
			if e.get("ev") == "battle_start" and e.get("kind") == "pvp" and not bool(e.get("foe_human", false)) \
					and e.has("foe") and not ("그림자" in str(e.get("foe_name", "")) or "유랑군" in str(e.get("foe_name", ""))):
				st = e
			elif e.get("ev") == "battle_end" and st != null:
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
					samples.append([int(st.day), int(st.phase), side, float(st.foe.pv), str(form_style.get(str(st.get("foe_form", "eorin")), "균형")), bool(e.win)])
				st = null
	print("표본 %d" % samples.size())
	var groups := {}
	for s in samples:
		var k := mini(int(s[0]), 6)
		if not groups.has(k):
			groups[k] = []
		groups[k].append(s)
	var keys := groups.keys()
	keys.sort()
	for k in keys:
		var g: Array = groups[k]
		var real := 0
		for s in g:
			real += 1 if s[5] else 0
		var out := []
		for m in muls:
			var w := 0
			var n := 0
			for s in g:
				for sd in seeds:
					var r := RandomNumberGenerator.new()
					r.seed = 9000 + sd * 31 + n
					var p_idx := int(s[0]) * 3 + int(s[1])
					var foe := {}
					if material:
						var key := "%s|%d" % [s[4], sd]
						if not mats.has(key):
							var b := {"name": "봇%d" % sd, "style": str(s[4]), "material": true, "pv": 0.0, "forge_sell": true}
							var snaps := []
							for p in 21:
								snaps.append(Run.bot_side_of(b, 7700 + sd * 13, p))
							mats[key] = snaps
						foe = (mats[key][mini(p_idx, 20)] as Dictionary).duplicate(true)
					else:
						foe = Run.bot_side(float(s[3]) * float(m), str(s[4]), p_idx, r)
					var bt := {"kind": "pvp", "a": (s[2] as Dictionary).duplicate(true), "b": foe, "seed": 2000 + sd * 7919 + n, "title": "점검", "foe": "봇", "inputs": []}
					var res := Run.simulate(bt, [], Run.policy_for(bt))
					w += 1 if res.win else 0
					n += 1
			out.append("×%.2f %d%%" % [m, roundi(100.0 * w / maxf(1, n))])
		print("BOT|%d일|표본 %d|실제 %d%%|%s" % [k + 1, g.size(), roundi(100.0 * real / g.size()), " · ".join(out)])
	get_tree().quit()
