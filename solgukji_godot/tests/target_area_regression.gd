extends Node

class Probe extends RtBattle:
	var hidden_key := ""
	func _hidden(u: Unit) -> bool:
		return u.key == hidden_key or super._hidden(u)

func card(tag: String) -> String:
	for k in DB.by_tier(7):
		if DB.C[k].tag == tag:
			return k
	assert(false, "Missing tag " + tag)
	return ""

func fixture(tag: String) -> Probe:
	var bt := Probe.new(123)
	bt._setup([card(tag)], "eorin", 100, null, [card("창병"), card("창병"), card("창병")], "eorin", 100, null, "", "", [], {"A": "manual", "B": "manual"})
	bt._paeup.clear()
	for i in bt.units.size():
		var u = bt.units[i]
		u.pos = Vector2(i * 100.0, 0)
		u.hw = 10.0
		u.hd = 10.0
		u.fwd = Vector2.RIGHT
		u.st.clear()
	return bt

func _ready() -> void:
	get_tree().create_timer(5.0).timeout.connect(func(): get_tree().quit(1))
	for tag in ["궁병", "책사", "유생", "술사", "모사"]:
		var bt := fixture(tag)
		var me = bt.units[0]
		var close = bt.units[1]
		var mid = bt.units[2]
		var far = bt.units[3]
		close.pos = Vector2(40, 0)
		mid.pos = Vector2(80, 0)
		far.pos = Vector2(5000, 0)
		me.tgt = far
		var foes := [far, mid, close]
		assert(bt.basic_target(me, foes) == [close], tag + ": nearest in range")
		assert(bt.basic_target(me, [me, close]) == [close], "Allies are not attack targets")
		assert(bt._choose(me, foes) == close, "Movement must use the same priority")
		assert(bt._ready_to_hit(me) and me.tgt == close, "Stale out-of-range target must not block attacks")
		assert(bt.resolve_targets("back1", foes, me, []) == [far], "Skill back-line targeting must remain separate")
		bt.hidden_key = close.key
		assert(bt.basic_target(me, foes) == [mid], "Hidden enemy is excluded")
		bt.hidden_key = ""
		close.alive = false
		assert(bt.basic_target(me, foes) == [mid], "Dead enemy is excluded")
		mid.pos = Vector2(3000, 0)
		assert(bt.basic_target(me, foes).is_empty(), "Never fire beyond range")
		assert(not bt._ready_to_hit(me), "Wait when no enemy is in range")
		assert(bt._choose(me, foes) == mid, "Approach closest visible enemy when out of range")
		# Range uses footprint gap, whereas nearest ranking uses center distance.
		close.alive = true
		close.pos = Vector2(bt._reach(me) + 23, 0)
		close.hd = 10.0
		mid.pos = Vector2(bt._reach(me) + 50, 0)
		mid.hd = 100.0
		assert(bt.basic_target(me, foes) == [mid], "A closer center outside range must not displace an eligible footprint")
		close.pos = mid.pos
		close.hd = mid.hd
		assert(bt.basic_target(me, [close, mid]) == [close], "Ties preserve deterministic roster order")
	print("PASS nearest ranged basics: five classes, stale targets, range, death, stealth, movement, ties")

	var bt := fixture("책사")
	var me = bt.units[0]
	var main = bt.units[1]
	var edge_in = bt.units[2]
	var edge_out = bt.units[3]
	var radius := RtBattle.ult_all_r
	main.pos = Vector2(123.25, 45.75)
	edge_in.pos = main.pos + Vector2(radius + 9.5, 0)
	edge_out.pos = main.pos + Vector2(radius + 10.5, 0)
	var foes := [main, edge_in, edge_out]
	me.tgt = main
	bt.ev.append({"fx": "ult", "a": me.key})
	var hit := bt._ult_area(me, main, foes)
	assert(hit.has(main) and hit.has(edge_in) and not hit.has(edge_out), "Preserve the actual footprint-edge hit rule")
	var shape: Dictionary = bt.ev[-1].area[0]
	assert(shape.r == radius and shape.x == main.pos.x and shape.y == main.pos.y, "Recorded circle must have exact judge radius and center")
	me.ult = {"eff": [{"t": "hit", "tgt": "all"}]}
	var before := JSON.stringify(bt.ev)
	bt._in_ult = true
	bt._target_preview = true
	var warn := bt._ult_warn_list(me)
	assert(JSON.stringify(bt.ev) == before, "Warning preview must not mutate earlier events")
	assert(bt._in_ult and bt._target_preview, "Preview must restore its caller flags")
	assert(warn.size() == hit.size() and bt._last_warn_areas[0] == shape)
	var payload: Dictionary = JSON.parse_string(JSON.stringify({"warn": warn, "warn_shapes": bt._last_warn_areas}))
	assert(BattleView.warning_shapes(payload).size() == 1 and BattleView.warning_shapes(payload)[0].r == radius)
	assert(BattleView.warning_shapes({"warn": [{"x": 1, "y": 2, "r": 60}]}).size() == 1, "Old replay compatibility")
	var replay := {"win": true, "draw": false, "left": 10, "eLeft": 5, "aForm": "eorin", "bForm": "hagik", "aSyn": {}, "bSyn": {}, "track": [], "ev": [payload]}
	var flipped := Run.flip_res(replay)
	assert(flipped.ev[0].warn_shapes[0].x == -shape.x and flipped.ev[0].warn_shapes[0].r == radius, "Opponent replay must mirror warning geometry")
	assert(flipped.ev[0].warn[0].x == -warn[0].x)
	assert(replay.ev[0].warn_shapes[0].x == shape.x, "Mirroring must not mutate the original")
	assert(Run.flip_res(flipped).ev == replay.ev, "Warning geometry must survive a double flip")
	print("PASS ultimate geometry: footprint boundary / exact radius / pure preview / JSON / legacy replay / opponent flip")

	var was_type2 := Settings.type2
	var was_painting := Settings.war_painting
	var was_preview := Type2View.formation_preview
	Settings.type2 = true
	Settings.war_painting = true
	Type2View.formation_preview = false
	var flat := Type2View.new()
	flat.size = Vector2(400, 800)
	flat._scale = 0.4
	flat._painting_stretch = 1.7
	flat._painting_origin = Vector2(0.5, 0.5)
	flat._center = Vector2.ZERO
	var outline := flat.area_outline(shape)
	assert(outline.size() == 64)
	for p in outline:
		assert(absf(flat.unmap(p).distance_to(main.pos) - radius) < 0.01, "Every displayed vertex must lie on the actual world boundary")
	var painter = preload("res://scripts/field/war_painting.gd").new()
	painter.v = flat
	var sea := {"center": Vector2(123.25, 45.75), "radius": Battle.SEA_R + Battle.SEA_MARGIN, "start": 0.0, "end": 15.0}
	for time in [0.0, 0.1, 0.42, 10.0]:
		painter.last_clock = time
		for p in painter.fire_sea_outline(sea):
			assert(absf(flat.unmap(p).distance_to(sea.center) - float(sea.radius)) < 0.01, "Fire-sea boundary must match its active radius from the first tick")
	painter.free()
	flat.free()
	Settings.type2 = was_type2
	Settings.war_painting = was_painting
	Type2View.formation_preview = was_preview
	print("PASS projected circle and fire sea: inverse-projected boundary points and constant active radius")
	get_tree().quit()
