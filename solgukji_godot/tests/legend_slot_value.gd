extends Node
## 11/17 D안 —— 실제 덱(전설 8명 + 1)에서 같은 후열 자리에 병종이 다른 전설을 바꿔 끼워, 팀 승률 · 그 장수의 피해 · 생존을 비교한다.
## 실행: godot --headless --path . res://tests/legend_slot_value.tscn [-- --trials=8 --list]
## 같은 시드 · 같은 아군 8명 · 같은 적 9명 · 진영 교체. 수치는 바꾸지 않는다
const Audit = preload("res://tests/motion5_role_audit.gd")
const BACK := ["책사", "궁병", "모사", "유생"]

func _ready() -> void:
	var args := {}
	for arg in OS.get_cmdline_user_args():
		var pair := arg.trim_prefix("--").split("=", true, 1)
		args[pair[0]] = pair[1] if pair.size() > 1 else "1"
	var pool := DB.by_tier(5).filter(func(k): return not DB.is_foe(k) and not DB.is_kiin(k))
	var by_tag := {}
	for k in pool:
		var tg: String = DB.C[k].tag
		by_tag[tg] = by_tag.get(tg, []) + [k]
	for tg in by_tag:
		print("POOL ", tg, " ", by_tag[tg].size(), ": ", ", ".join(by_tag[tg].map(func(k): return DB.person(k))))
	if args.has("list"):
		get_tree().quit()
		return
	var all_tags := args.has("all")      # --all: 모든 병종을 끼우고 자동 배치(병종 제자리)로 비교
	var candidates := pool if all_tags else pool.filter(func(k): return BACK.has(DB.C[k].tag))
	var excluded: Array = [] if all_tags else candidates.map(func(k): return DB.person(k))
	var front_pool := pool.filter(func(k): return not excluded.has(DB.person(k)))
	var trials := int(args.get("trials", "8"))
	var slot := int(args.get("slot", "7"))
	var helper := Audit.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 92100
	var acc := {}
	var n_runs := 0
	for trial in trials:
		var base := helper.pick_unique(front_pool, 8, rng)
		var enemy := helper.pick_unique(pool, 9, rng)
		for key in candidates:
			if enemy.any(func(e): return DB.person(e) == DB.person(key)):
				continue
			if all_tags and base.any(func(e): return DB.person(e) == DB.person(key)):
				continue
			var deck := base.duplicate()
			deck.insert(slot, key)
			if all_tags:
				deck = DB.auto_place(deck, "eorin")
			for mirror in [false, true]:
				var bt := Audit.Probe.new(92100 + trial)
				var res := bt.run(enemy if mirror else deck, "eorin", 100, null, deck if mirror else enemy, "eorin", 100, null, "", "", [], {"A": "auto", "B": "auto"})
				n_runs += 1
				var camp := "B" if mirror else "A"
				var won: bool = (not res.win and not res.draw) if mirror else (res.win and not res.draw)
				var me = null
				for u in bt.units:
					if u.camp == camp and (u.c.id == key if all_tags else u.slot == slot):
						me = u
				var r: Dictionary = bt.row(me.key)
				var direct := 0.0
				for k in Audit.DAMAGE:
					direct += float(r[k])
				var nm := DB.person(key)
				var a: Dictionary = acc.get(nm, {"tag": DB.C[key].tag, "n": 0, "win": 0, "direct": 0.0, "dot": 0.0, "alive": 0, "life": 0.0, "len": 0.0, "acts": 0})
				a.n += 1
				a.win += 1 if won else 0
				a.direct += direct
				a.dot += float(me.dot)
				a.alive += 1 if me.alive else 0
				a.len += float(res.len)
				a.acts += int(r.actions)
				acc[nm] = a
		print("TRIAL ", trial + 1, "/", trials)
	helper.free()
	var tag_sum := {}
	var names := acc.keys()
	names.sort_custom(func(x, y): return float(acc[x].win) / acc[x].n > float(acc[y].win) / acc[y].n)
	for nm in names:
		var a: Dictionary = acc[nm]
		var n := float(a.n)
		print("UNIT %s|%s|판 %d|팀승률 %.0f%%|직접 %d|지속 %d|합 %d|행동 %.1f|생존 %.0f%%" % [nm, a.tag, a.n, 100.0 * a.win / n, roundi(a.direct / n), roundi(a.dot / n), roundi((a.direct + a.dot) / n), a.acts / n, 100.0 * a.alive / n])
		var t: Dictionary = tag_sum.get(a.tag, {"n": 0, "win": 0, "dmg": 0.0, "alive": 0})
		t.n += a.n
		t.win += a.win
		t.dmg += a.direct + a.dot
		t.alive += a.alive
		tag_sum[a.tag] = t
	for tg in tag_sum:
		var t: Dictionary = tag_sum[tg]
		print("TAG %s|판 %d|팀승률 %.0f%%|피해 %d|생존 %.0f%%" % [tg, t.n, 100.0 * t.win / t.n, roundi(t.dmg / t.n), 100.0 * t.alive / t.n])
	print("RUNS ", n_runs)
	get_tree().quit()
