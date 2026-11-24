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
	# 실제 인연 편성에서 단독 발동은 첫 발동/격파/설정과 무관하게 빠르게,
	# 실제 합동의 대표는 기존 큰 연출을 유지한다.
	var bonded_people := {}
	for camp in ["A", "B"]:
		var cards := []
		for sq: Squad in view.field.order:
			if sq.camp == camp:
				cards.append(sq.cid)
		for link in DB.inyeon_links(cards):
			for person in link["in"]:
				bonded_people[camp + person] = true
	var solos: Array = view.groups.filter(func(g): return g.ult != null and not g.ult.has("lead") and g.ult.get("mates", []).is_empty() and bonded_people.has(view.field.squads[g.who].camp + DB.person(view.field.squads[g.who].cid)))
	var joint_heads: Array = view.groups.filter(func(g): return g.ult != null and not g.ult.get("mates", []).is_empty())
	assert(not solos.is_empty() and not joint_heads.is_empty())
	var all_units: Array = view.field.order
	view.field.order = [view.field.squads[solos[0].who]]
	Settings.ult_fx = 0
	view.remark_ults()
	assert(solos[0].big, "A possible database bond without a partner in the deck must not force the fast path")
	view.field.order = all_units
	for mode in [0, 1, 2]:
		Settings.ult_fx = mode
		view.remark_ults()
		assert(solos.all(func(g): return not g.big), "Solo activations with a deck bond must always be fast, even in all-large mode")
		assert(joint_heads[0].big == (mode != 2), "The first actual joint activation must retain its full cinematic unless all-fast is selected")
	Settings.ult_fx = 1
	view.remark_ults()
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
	var joined_camp: String = view.field.squads[joined[0].who].camp
	assert(view.hud.ult_notices[joined_camp].size() == 1, "A linked general's light ultimate must announce its activation")
	view.hud.ult_notices.A.clear()
	view.hud.ult_notices.B.clear()
	view.speed = 1.0
	var solo_timing := [view.clock, view.speed, view.slow_t, view.freeze_t, view.field._cine]
	view._start_ult(solos[0])
	assert(solos[0].lite and view.hud.cut == null)
	assert(solo_timing == [view.clock, view.speed, view.slow_t, view.freeze_t, view.field._cine], "The actual bonded solo event must take the fast path under default settings")
	view.hud.ult_notices.A.clear()
	view.hud.ult_notices.B.clear()
	Settings.ult_fx = 2
	view.remark_ults()
	var timing := [view.clock, view.speed, view.slow_t, view.freeze_t, view.field._cine]
	for camp in ["A", "B"]:
		var regular: Array = view.groups.filter(func(g): return g.ult != null and not g.ult.has("lead") and view.field.squads[g.who].camp == camp)
		assert(not regular.is_empty())
		var light: Dictionary = regular[0].duplicate(true)
		assert(not light.big, "The real classifier must select the fast path")
		view._start_ult(light)
		assert(view.hud.ult_notices[camp].size() == 1)
		assert(view.hud.ult_notices[camp][0].skill == light.ult.name)
		assert(view.hud.ult_notices[camp][0].cid == view.field.squads[light.who].cid, "The portrait must identify the actual caster")
		assert(view.hud.ult_notice_rect(camp).encloses(view.hud.ult_notice_portrait_rect(camp)))
		assert(timing == [view.clock, view.speed, view.slow_t, view.freeze_t, view.field._cine], "A light activation must not slow, pause or move the camera")
	assert(view.hud.ult_notice_rect("A").end.x < view.hud.size.x * 0.5)
	assert(view.hud.ult_notice_rect("B").position.x > view.hud.size.x * 0.5)
	view.speed = 0.0
	view.hud._tick_ult_notices(view.hud.ULT_NOTICE_LIFE + 0.01)
	assert(view.hud.ult_notices.A.is_empty() and view.hud.ult_notices.B.is_empty(), "Notices must expire in real HUD time, independently of battle speed")
	for i in 30:
		view.hud.ult_notice(hitter, "고유기")
	assert(view.hud.ult_notices[hitter.camp].size() == view.hud.ULT_NOTICE_LIMIT, "Burst activations must have bounded UI cost")
	var fin_count: int = view.hud.fins.size()
	view._fin_show({"a": hitter.key}, {"foes": [burning.key], "allies": []}, "fire", Color.ORANGE, "인연기")
	assert(view.hud.fins.size() == fin_count and painter.ults[-1].lite, "The follow-up must not queue a large banner or repeated full effects")
	var number_count: int = view.hud.floats.size()
	view.hud.damage(burning.key, 0.0, "phys", true)
	assert(view.hud.floats.size() == number_count, "Zero damage must not cover formations")
	assert(JSON.stringify(result) == unchanged, "Motion and propagation displays must leave the replay intact")
	view.speed = 1.0
	var rout_timing := [view.clock, view.speed, view.slow_t, view.freeze_t, view.field._cine]
	var defeated: Squad = view.field.order.filter(func(q): return q.camp == "B" and q.alive)[0]
	view._do_rout(view.idx_of[defeated.key], true)
	assert(rout_timing == [view.clock, view.speed, view.slow_t, view.freeze_t, view.field._cine], "Even a fast ultimate's defeat must not add a pause or camera move")
	var delayed: Squad = view.field.order.filter(func(q): return q.camp == "B" and q.alive)[0]
	var delayed_index: int = view.idx_of[delayed.key]
	view.cur[delayed_index][0] = 0.0
	view.shown[delayed_index][0] = 1.0
	view.rout_wait[delayed_index] = true
	view._drain_step(1.0)
	assert(not view.rout_wait.has(delayed_index))
	assert(rout_timing == [view.clock, view.speed, view.slow_t, view.freeze_t, view.field._cine], "A delayed defeat must retain the fast flag until the final soldier falls")
	painter.reset()
	assert(painter.fire_paths.is_empty() and painter.burn_fronts.is_empty())
	view.hud.reset()
	assert(view.hud.ult_notices.A.is_empty() and view.hud.ult_notices.B.is_empty())
	print("PASS physical fire: real engine events / actual spread origin / living formation sites / effect budget / no inferred spread / reset / replay immutability")
	print("PASS ultimate emphasis: light charge and impact / short lifetime / no repeated fire clusters / full important ultimate retained")
	print("PASS light activation notices: real regular and linked events / ally left enemy right / unchanged clock speed slow pause camera / real-time expiry / bounded queue / reset")
	print("PASS bonded solo ultimates: real replay classification in all modes / full joint retained / correct portrait and side / no defeat pause or camera")
	form = null
	unit = null
	burning = null
	burning_form = null
	hitter = null
	all_units = []
	defeated = null
	delayed = null
	painter = null
	view.queue_free()
	view = null
	await get_tree().process_frame
	await get_tree().process_frame
	Sfx.music("")
	await get_tree().create_timer(0.7).timeout
	get_tree().quit()
