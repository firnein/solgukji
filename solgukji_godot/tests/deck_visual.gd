extends Control
## Visual smoke check with representative replay events. --shot saves a portrait preview.
func _ready() -> void:
	get_tree().create_timer(20.0).timeout.connect(func(): get_tree().quit(1))
	PlayLog.enabled = false
	Settings.load_cfg()
	Settings.type2 = true
	Settings.apply()
	theme = UI.theme()
	var view := BattleView.new()
	view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(view)
	await get_tree().process_frame
	var helper = preload("res://tests/inyeon.gd").new()
	var a: Array = DB.auto_place(helper._pick([], 7), "eorin")
	var b: Array = DB.auto_place(helper._pick([], 7), "hagik")
	var result := RtBattle.new(5100).run(a, "eorin", 100, null, b, "hagik", 100, null, "", "", [], {"A": "auto", "B": "auto"})
	helper.free()
	view.play_res(result, "pvp")
	view.speed = 0
	var source: String = view.field.order[0].key
	var target: String = view.field.order[-1].key
	view.field.squads[target].statuses = ["burn", "cut_def"]
	view.hud.deck_event({"fx": "status", "f": target, "st": "burn", "from": source})
	assert(view.hud._deck_links.size() == 1)
	view.hud.deck_event({"fx": "status", "f": target, "st": "burn", "from": source})
	assert(view.hud._deck_links.size() == 1, "Repeated effects must be throttled")
	view.hud.deck_event({"fx": "phys", "a": source, "f": target, "fire": true})
	assert(view.hud._deck_links.size() == 2)
	view.hud.deck_event({"fx": "phys", "a": source, "f": target})
	assert(view.hud._deck_links.size() == 2, "Ordinary hits must not claim a combo")
	view.hud.deck_event({"fx": "status", "f": "missing", "st": "burn"})
	view.speed = 1
	await get_tree().create_timer(0.1).timeout
	view.speed = 0
	if "--shot" in OS.get_cmdline_user_args():
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://../build/deck_visual.png")
	view.hud.reset()
	assert(view.hud._deck_seen.is_empty() and view.hud._deck_links.is_empty())
	# Exercise actual engine events, including the real armor support calculation.
	var engine := RtBattle.new(5100)
	engine._setup(a, "eorin", 100, null, b, "hagik", 100, null, "", "", [], {"A": "manual", "B": "manual"})
	engine._paeup.clear()
	for unit in engine.units:
		unit.m = {}
		unit.caps.clear()
		unit.ts = null
		unit.troops = 100000
		unit.max = 100000
	var attacker = engine.units[0]
	var defender = engine.units[-1]
	engine.inflict(attacker, defender, "burn", 0.05, 3)
	var application: Dictionary = engine.ev[-1]
	assert(application.from == attacker.key and not application.spread)
	view.hud.deck_event(application)
	assert(view.hud._deck_links[-1].a == attacker.key)
	assert(view.hud.floats[-1].text == "화상", "Initial application must not be mislabeled as spreading")
	var kind: String = engine.dmg_kind(attacker)
	defender.shield[kind] = 0.6
	engine._shred(attacker, defender, kind, 0.2, 3, "지원 검사")
	var weaken: Dictionary = engine.ev[-1]
	assert(weaken.from == attacker.key and weaken.st == "shred_" + kind)
	view.hud.deck_event(weaken)
	assert(view.hud._deck_links[-1].a == attacker.key)
	engine.phys_hit(attacker, defender, 1.0, true)
	var helped: Array = engine.ev.filter(func(e): return e.has("assists"))
	assert(not helped.is_empty() and helped[0].assists[0].from == attacker.key and helped[0].assists[0].n > 0.0)
	view.hud.deck_event(helped[0])
	assert(view.hud.floats.any(func(f): return f.text.ends_with("약화 활용")))
	engine._cut(attacker, defender, "atk", 5.0, "공격 약화 검사")
	assert(engine.ev[-1].from == attacker.key and engine.ev[-1].st == "cut_atk")
	view.hud.deck_event(engine.ev[-1])
	assert(view.hud.floats[-1].text == "공깎")
	var replay := result.duplicate(true)
	replay.ev = [helped[0].duplicate(true)]
	assert(Run.flip_res(replay).ev[0].assists[0].from == "B" + attacker.key.substr(1))
	assert(Run.flip_res(Run.flip_res(replay)).ev[0].assists == replay.ev[0].assists)
	view.hud.reset()
	view.hud.deck_event(application)
	var other := application.duplicate()
	other.from = engine.units[1].key
	view.hud.deck_event(other)
	assert(view.hud._deck_links.size() == 2, "Separate contributors must not throttle each other")
	assert(view.hud.floats.size() == 2, "Painting must show the contributing units' notices")
	if Type2View.painting_on():
		view.hud.float_text(attacker.key, "minor", Color.WHITE, 12)
		assert(view.hud.floats.size() == 2, "Ordinary minor text stays suppressed")
	view.hud.deck_event({"fx": "phys", "a": attacker.key, "f": defender.key, "assists": []})
	assert(view.hud._deck_links.size() == 2)
	for i in range(2, 6):
		other.from = engine.units[i].key
		view.hud.deck_event(other)
		assert(view.hud._deck_links.size() <= 3 and view.hud.floats.size() <= 3, "Notices and links must stay bounded")
	view.hud.reset()
	defender.shred[kind].t = 0
	var begin := engine.ev.size()
	engine.phys_hit(attacker, defender, 1.0, true)
	assert(engine.ev.slice(begin).all(func(e): return not e.has("assists")), "Expired armor reduction must not claim support")
	# A weaker burn can supply stronger spreading: distinguish DOT owner, spread
	# contributor, and the burning enemy from which the next jump departs.
	var spreader = engine.units[1]
	spreader.m = {"spread": 0.75}
	engine.inflict(spreader, defender, "burn", 0.01, 3)
	var burn: Dictionary = engine._st_of(defender, "burn")
	assert(burn.by == attacker.key and burn.spread_by == spreader.key)
	var next_target = engine.units[-2]
	engine._spread_burn_to(defender, burn, next_target)
	var spread: Dictionary = engine.ev[-1]
	assert(spread.from == defender.key and spread.contributor == spreader.key and spread.spread)
	view.hud.reset()
	view.hud.deck_event(spread)
	assert(view.hud._deck_links[0].a == defender.key and view.hud._deck_links[0].b == next_target.key)
	assert(view.hud.floats[0].key == spreader.key and view.hud.floats[0].text == "불길 확산")
	replay.ev = [spread]
	var flipped := Run.flip_res(replay)
	assert(flipped.ev[0].from == "A" + defender.key.substr(1) and flipped.ev[0].contributor == "B" + spreader.key.substr(1))
	var blaze_source = engine.units[2]
	blaze_source.m = {"blaze": 0.5}
	next_target.st.clear()
	next_target.line = defender.line
	next_target.pos = defender.pos + Vector2(5, 0)
	begin = engine.ev.size()
	engine._blaze(defender)
	var blaze_events := engine.ev.slice(begin).filter(func(e): return e.get("fx") == "status" and e.get("st") == "burn")
	assert(not blaze_events.is_empty())
	assert(blaze_events.all(func(e): return e.contributor == blaze_source.key and e.from == defender.key), "Blaze must name its passive provider, independently of DOT/spread owners")
	print("PASS deck visuals: source / throttle / ordinary hit / reset / draw")
	print("PASS engine provenance: initial burn / armor source / actual support / independent contributors / expired support / mirrored replay")
	print("PASS spreading provenance: DOT owner / chance provider / propagation origin / blaze provider / mirrored replay")
	view.queue_free()
	await get_tree().process_frame
	get_tree().quit()
