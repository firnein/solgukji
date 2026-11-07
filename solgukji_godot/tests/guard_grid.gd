extends Node
## 11/8 갑옷 · 결계 수치 격자 (docs/역할_재설계_1108.md 9.4-2) —— 실행: godot --headless --path . res://tests/guard_grid.tscn
##   [-- --games=20 --tier=7 --cells=off,15:15,30:30,45:45]
## 칸 a:w = 창병 갑옷 a% · 술사 결계 w% (기병 · 책사는 그 절반, 나머지 병종 0). off = 막 · 깎기를 끈 지금 판정.
## 칸마다 병종 3장 + 무작위 6장 덱 대 무작위 9장 덱의 승률 (tag_role 과 같은 방식) —— 칸 사이에 같은 시드를 써서 차이만 보이게 한다.
## 기준 (9.1 통과 기준): 병종 3장 덱 승률이 모두 40~62% 안

const FORMS := ["eorin", "hagik", "bongsi", "anwol", "bangwon", "anhaeng", "chuhaeng", "jangsa"]


func _ready() -> void:
	var args := {}
	for s in OS.get_cmdline_user_args():
		var kv := s.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	var games := int(args.get("games", "20"))
	var tier := int(args.get("tier", "7"))
	var cells: Array = Array(str(args.get("cells", "off,15:15,30:30,45:45")).split(","))
	var pool: Array = DB.by_tier(tier).filter(func(k): return not DB.is_foe(k))
	var tags: Array = DB.D.TAGORDER
	var head := "%-7s" % "칸"
	for tg in tags:
		head += " %4s" % str(tg).left(2)
	print("── 등급 %d (%s) 병종 3장 덱 승률 · 병종마다 %d판" % [tier, DB.TIER[tier].n, games])
	print(head + "   폭  최저-최고")
	for cell in cells:
		var t0 := Time.get_ticks_msec()
		if cell == "off":
			Battle.shield_enabled = false
			Battle.guard_over = {}
		else:
			var p: PackedStringArray = str(cell).split(":")
			var a := float(p[0]) / 100.0
			var w := float(p[1]) / 100.0 if p.size() > 1 else a
			Battle.shield_enabled = true
			Battle.guard_over = {"창병": a, "기병": a / 2.0, "술사": w, "책사": w / 2.0}
		var line := "%-7s" % ("끔" if cell == "off" else str(cell))
		var lo := 1.0
		var hi := 0.0
		var lo_t := ""
		var hi_t := ""
		for ti in tags.size():
			var tg: String = tags[ti]
			var mine: Array = pool.filter(func(k): return DB.C[k].tag == tg)
			if mine.is_empty():
				line += "    -"
				continue
			var rng := RandomNumberGenerator.new()
			rng.seed = 77 + tier * 10 + ti
			var s := 0.0
			for g in games:
				var a := []
				for i in 3: a.append(mine[rng.randi() % mine.size()])
				for i in 6: a.append(pool[rng.randi() % pool.size()])
				var b := []
				for i in 9: b.append(pool[rng.randi() % pool.size()])
				var fa: String = FORMS[rng.randi() % FORMS.size()]
				var fb: String = FORMS[rng.randi() % FORMS.size()]
				var r := RtBattle.make(rng.randi()).run(DB.auto_place(a, fa), fa, 100, null, DB.auto_place(b, fb), fb, 100, null, "", "", [], {"A": "smart", "B": "smart"})
				s += 1.0 if r.win else (0.5 if r.draw else 0.0)
			var p := s / games
			line += " %4d" % roundi(p * 100)
			if p < lo:
				lo = p
				lo_t = tg
			if p > hi:
				hi = p
				hi_t = tg
		print(line + "  %3d  %s %d - %s %d  (%.0f초)" % [roundi((hi - lo) * 100), lo_t, roundi(lo * 100), hi_t, roundi(hi * 100), (Time.get_ticks_msec() - t0) / 1000.0])
	Battle.shield_enabled = true
	Battle.guard_over = {}
	get_tree().quit()
