extends Node

func card(person: String) -> String:
	var pick := ""
	for k in DB.C:
		if DB.person(k) == person and DB.C[k].kind not in ["foe", "retired"]:
			if pick == "" or DB.C[k].tier > DB.C[pick].tier:
				pick = k
	assert(pick != "")
	return pick

func _ready() -> void:
	for scenario in ["healthy", "morale", "troops", "mixed", "annihilated"]:
		var probe := RtBattle.new(77)
		probe._setup([card("조인")], "eorin", 100, null, [card("조인")], "eorin", 100, null, "", "", [], {"A":"manual", "B":"manual"})
		var subject = probe.units[0]
		subject.m = {}
		subject.caps.clear()
		subject.morale = 0 if scenario in ["morale", "mixed"] else 100
		subject.troops = subject.max * (0.1 if scenario in ["troops", "mixed"] else 1.0)
		if scenario == "annihilated":
			subject.troops = 0
		for i in 100:
			probe._settle(1.0, false)
			if not subject.alive: break
		if scenario == "healthy":
			assert(subject.alive, "Healthy morale and troops must not rout")
		else:
			assert(not subject.alive, scenario)
			var exits := probe.ev.filter(func(e): return e.get("fx") == "rout" and e.get("f") == subject.key)
			assert(exits.size() == 1 and exits[0].rout_cause == scenario, scenario)
	var bt := RtBattle.new(40)
	bt._setup([card("제갈량"), card("조인"), card("장료")], "eorin", 100, null, [card("조인"), card("장료")], "eorin", 100, null, "", "", [], {"A":"manual", "B":"manual"})
	var strategist = bt.units[0]
	var defender = bt.units[1]
	var attacker = bt.units[3]
	attacker.m = {"jolt":10.0}
	defender.m = {}
	defender.morale = 100
	for i in 10:
		bt.phys_hit(attacker, defender, 0.00001, true)
	assert(defender.morale > 99.0, "Negligible losses must not erase morale")
	strategist.gauge = 0
	bt._idle_gauge(strategist, 1.0)
	assert(strategist.gauge > 0, "Waiting rear units must charge")
	strategist.charges = 0
	var gauge: float = strategist.gauge
	bt._idle_gauge(strategist, 1.0)
	assert(strategist.gauge == gauge, "Exhausted ultimate must not charge")
	strategist.pos = Vector2(-1000, 0)
	attacker.pos = Vector2(1000, 0)
	bt.units[4].pos = Vector2(1001, 1)
	var before := JSON.stringify(bt.ev)
	assert(bt._ult_reach_n(strategist, [attacker, bt.units[4]]) == 2, "Ultimate area must work outside basic attack range")
	assert(JSON.stringify(bt.ev) == before, "Target preview must not modify replay events")
	assert(not bt._in_ult and not bt._target_preview)
	defender.morale = 10
	bt.rout(defender, "사기 패주 검사", "morale")
	var exit: Dictionary = bt.ev[-1]
	assert(exit.rout_cause == "morale" and exit.troop_ratio > 0.99)
	bt.rout(bt.units[2], "복합 패주 검사", "mixed")
	var result := bt._result("B", 1)
	# L() snapshots the final state, as a normal battle does before its report.
	var report := BattleReport.make(result)
	var rows := report._rows("A")
	assert(rows.filter(func(r): return r.rout_cause == "morale").size() == 1)
	assert(rows.filter(func(r): return r.rout_cause == "mixed").size() == 1)
	print("PASS rear charge / ultimate reach / morale loss / replay purity / report causes")
	if "--shot" in OS.get_cmdline_user_args():
		report.position = Vector2(12, 12)
		report.size.x = 376
		report.max_h = 740
		add_child(report)
		await get_tree().create_timer(0.5).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://../rear_morale_report.png")
		report.queue_free()
		await get_tree().process_frame
	else:
		report.free()
	get_tree().quit()
