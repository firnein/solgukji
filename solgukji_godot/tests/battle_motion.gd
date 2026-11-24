extends Control
const Formation = preload("res://scripts/field/painted_formation.gd")

func _ready() -> void:
	get_tree().create_timer(40.0).timeout.connect(func(): get_tree().quit(1))
	PlayLog.enabled = false
	Settings.load_cfg()
	Settings.type2 = true
	Settings.war_painting = true
	Settings.ult_fx = 1
	Settings.cam_fx = 0
	Settings.apply()
	var view := BattleView.new()
	view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(view)
	await get_tree().process_frame
	var helper = preload("res://tests/formation_preview.gd").new()
	var a: Array = DB.auto_place(helper._cards(["주유", "육손", "제갈량", "방통", "감녕", "황개", "정보", "조운", "관우"]), "eorin")
	var b: Array = DB.auto_place(helper._cards(["조조", "하후연", "사마의", "마초", "허저", "곽가", "손권", "여포", "화타"]), "hagik")
	helper.free()
	var result := RtBattle.new(5100).run(a, "eorin", 100, null, b, "hagik", 100, null, "", "", [], {"A": "auto", "B": "auto"})
	var unchanged := JSON.stringify(result)
	view.play_res(result, "pvp")
	view.speed = 0.0
	var unit: Squad = view.field.order.filter(func(q): return q.tag == "창병")[0]
	unit.puppet = false
	unit.pos = Vector2.ZERO
	unit.fwd = Vector2.RIGHT
	unit.hw = 80.0
	unit.hd0 = 60.0
	unit.contact = false
	var form = Formation.new(unit)
	var front := 0
	var behind: int = form.cols
	form.remove_soldier(front)
	assert(form.ranks[behind] == 0 and form.visual_ranks[behind] == 1.0)
	for i in 12:
		form.step(unit, 0.016)
	assert(form.visual_ranks[behind] == 1.0, "The front gap must remain visible before a replacement steps in")
	for i in 30:
		form.step(unit, 0.016)
	assert(form.visual_ranks[behind] > 0.0 and form.visual_ranks[behind] < 1.0, "The rear soldier must walk between ranks")
	for i in 40:
		form.step(unit, 0.016)
	assert(is_zero_approx(form.visual_ranks[behind]), "The rear soldier must eventually fill the gap")
	print("PASS physical ranks: visible vacancy / delayed replacement / walking into front")

	form = Formation.new(unit)
	front = form.cols / 2
	var rear: int = (form.rows - 1) * form.cols + front
	var center: Vector2 = form.center
	form.receive_impact(center + Vector2.RIGHT * unit.hd0, Vector2.LEFT, 1.8)
	var paused: PackedVector2Array = form.feet.duplicate()
	form.step(unit, 0.0)
	assert(form.feet == paused and form.motion_clock == 0.0, "Pausing must freeze impact and replacement time")
	form.step(unit, 0.016)
	assert(form.recoil[front].length() > 0.0 and form.recoil[rear].length() == 0.0, "A hit must reach the front before the rear")
	for i in 20:
		form.step(unit, 0.016)
	assert(form.recoil[rear].length() > 0.0, "Impact must propagate into the rear ranks")
	for i in 160:
		form.step(unit, 0.016)
	assert(form.recoil[front].length() < 0.05 and form.recoil[rear].length() < 0.05, "The formation must settle after impact")
	assert(form.center == center and unit.pos == Vector2.ZERO, "Impact must not move the simulated unit center")
	form.contact_limits = [{"normal": Vector2.RIGHT, "edge": 10.0}]
	form.receive_impact(Vector2(-80, 0), Vector2.RIGHT, 2.0)
	for i in 45:
		form.step(unit, 0.016)
		for id in form.capacity:
			assert(form.feet[id].x <= 10.001, "Impact must respect the opposing formation's contact boundary")
	print("PASS physical impact: delayed wave / spring recovery / pause / unchanged center / contact boundary")

	var painter = view.type2.painting
	painter.reset()
	var burns: Array = result.ev.filter(func(e): return e.get("fx") == "status" and e.get("st") == "burn")
	var spreads: Array = burns.filter(func(e): return bool(e.get("spread", false)))
	assert(not spreads.is_empty())
	var initial: Dictionary = burns.filter(func(e): return not bool(e.get("spread", false)))[0]
	painter.play_event(initial, null)
	assert(painter.fire_paths.is_empty(), "Initial ignition must not pretend to spread between units")
	var event: Dictionary = spreads[0]
	painter.play_event(event, null)
	assert(painter.fire_paths.size() == 1)
	assert(painter.fire_paths[0].a == event.from and painter.fire_paths[0].b == event.f, "Fire must follow the real propagation origin, independently of its passive provider")
	var burning: Squad = view.field.squads[event.f]
	burning.statuses = ["burn"]
	painter.visual_time = 1.0
	var sites: PackedVector2Array = painter.burn_sites(burning)
	assert(not sites.is_empty())
	var burning_form = painter.formations[burning.key]
	for point in sites:
		var id: int = burning_form.feet.find(point)
		assert(id >= 0 and burning_form.alive[id] != 0, "Flames must sit on living formation members")
	for e in spreads:
		painter.play_event(e, null)
		assert(painter.fire_paths.size() <= painter.MAX_FIRE_PATHS)
	var path_count: int = painter.fire_paths.size()
	painter.play_event({"fx": "phys", "a": event.from, "f": event.f, "fire": true}, null)
	assert(painter.fire_paths.size() == path_count, "Fire-assisted damage must not create a fake spread")
	painter.play_event({"fx": "status", "st": "burn", "f": event.f, "from": "missing", "spread": true}, null)
	assert(painter.fire_paths.size() == path_count, "Unknown origins must not create guessed routes")
	var hitter: Squad = view.field.order.filter(func(q): return q.camp != burning.camp)[0]
	painter.play_event({"fx": "phys", "a": hitter.key, "f": burning.key, "n": 100, "painted_charge": "hit"}, null, [{"key": burning.key, "troops": burning.max * 0.5}])
	assert(not painter.bodies.is_empty() and painter.bodies.all(func(body): return not body.flying), "Charge casualties must fall on the ground")
	view.field.ult.play("firestorm", hitter.key, [burning.key], [], 0.05, true)
	assert(bool(painter.ults[-1].lite) and painter.ults[-1].phase == "charge", "Light ultimates must reach the light renderer")
	view.field.ult._impact_flat("firestorm", hitter.key, [burning.key], [], Color.ORANGE, true)
	assert(bool(painter.ults[-1].lite) and painter.ults[-1].hits[0].spots.is_empty(), "Light impact must not create full per-unit fire clusters")
	assert(float(painter.ults[-1].end) - float(painter.ults[-1].start) <= 0.451)
	painter.add_ult("firestorm", hitter.key, [burning.key], [], Color.ORANGE, "impact")
	assert(not bool(painter.ults[-1].lite) and painter.ults[-1].hits[0].spots.size() == 7, "Important ultimates must retain their full effect")
	var joined: Array = view.groups.filter(func(g): return g.ult != null and g.ult.has("lead"))
	assert(not joined.is_empty())
	view._start_ult(joined[0])
	assert(joined[0].lite and painter.ults[-1].lite, "Linked generals must use the light path too")
	var fin_count: int = view.hud.fins.size()
	view._fin_show({"a": hitter.key}, {"foes": [burning.key], "allies": []}, "fire", Color.ORANGE, "인연기")
	assert(view.hud.fins.size() == fin_count and painter.ults[-1].lite, "The follow-up must not queue a large banner or repeated full effects")
	var number_count: int = view.hud.floats.size()
	view.hud.damage(burning.key, 0.0, "phys", true)
	assert(view.hud.floats.size() == number_count, "Zero damage must not cover formations")
	assert(JSON.stringify(result) == unchanged, "Motion and propagation displays must leave the replay intact")
	painter.reset()
	assert(painter.fire_paths.is_empty() and painter.burn_fronts.is_empty())
	print("PASS physical fire: real engine events / actual spread origin / living formation sites / effect budget / no inferred spread / reset / replay immutability")
	print("PASS ultimate emphasis: light charge and impact / short lifetime / no repeated fire clusters / full important ultimate retained")
	form = null
	unit = null
	burning = null
	burning_form = null
	hitter = null
	painter = null
	view.queue_free()
	view = null
	await get_tree().process_frame
	await get_tree().process_frame
	Sfx.music("")
	await get_tree().create_timer(0.7).timeout
	get_tree().quit()
