extends Node
const Decks := preload("res://tests/battle_lab_decks.gd")

func _ready() -> void:
	get_tree().create_timer(90.0).timeout.connect(func(): get_tree().quit(1))
	PlayLog.enabled = false
	var definitions := JSON.stringify(DB.ULT)
	var legends: Array = DB.by_tier(5).filter(func(k): return DB.is_mini_ult(k))
	assert(legends.size() == 48)
	for k in legends:
		var u = DB.ult_of(k)
		assert(DB.has_ult(k) and u != null and u.mini and not u.eff.is_empty())
		assert(not DB.inyeon_card(k) and Battle.ult_charges_of(DB.C[k]) == 1)
		assert(u.wait == 12.0 and is_equal_approx(u.wind, 0.6))
		assert(u.eff.size() <= 2)
		for comp in u.eff:
			assert(comp.tgt in ["front1", "back1", "self", "allyLow2"] and not comp.has("exec"))
			assert(float(comp.get("mult", 0.0)) <= 0.8)
			assert(float(comp.get("heal", 0.0)) <= 0.04)
			if comp.has("buff"):
				assert(absf(comp.buff.amt) <= 0.15 and comp.buff.dur == 1)
			if comp.has("status"):
				assert(comp.status.dur == 1)
		var parts := DB.ult_parts(u, 5)
		assert(not parts.hero.is_empty() or not parts.chips.is_empty())
		assert(UI.ult_desc(u, 5).contains("15%") or not u.eff.any(func(c): return c.t == "hit"))
		var pristine := JSON.stringify(u)
		u.eff[0].tgt = "all"
		assert(JSON.stringify(DB.ult_of(k)) == pristine, "A returned mini definition must not mutate cached source data")
	for k in DB.C:
		if DB.is_kiin(k) and DB.has_ult(k):
			assert(not DB.ult_of(k).get("mini", false) and Battle.ult_charges_of(DB.C[k]) == 3)
		elif int(DB.C[k].tier) < 5:
			assert(not DB.has_ult(k))
	assert(Battle.ult_cap_for(5, true) == 0.15 and Battle.ult_cap_for(5, false) == 0.25)
	assert(JSON.stringify(DB.ULT) == definitions)
	print("PASS mini definitions: all 48 legends / individual names and effects / one charge / bounded targets and power / no execution / accurate UI caps / no source mutation / kiin and low tiers preserved")
	var rng := RandomNumberGenerator.new()
	var counts := [0, 0, 0, 0, 9, 0, 0, 0, 0]
	var fired := 0
	var ui_result := {}
	for seed_ in [5100, 5101, 5102, 5103]:
		rng.seed = seed_
		var a := DB.auto_place(Decks.make_mix(counts, rng), "eorin")
		var b := DB.auto_place(Decks.make_mix(counts, rng), "hagik")
		var result := RtBattle.new(seed_).run(a, "eorin", 100, null, b, "hagik", 100, null, "", "", [], {"A": "auto", "B": "auto"})
		var per := {}
		for event in result.ev:
			if event.get("fx") == "ult":
				assert(event.get("mini", false) and not event.has("mates") and not event.has("lead"))
				per[event.a] = int(per.get(event.a, 0)) + 1
				assert(per[event.a] == 1, "Each legend can fire only one mini per battle")
				fired += 1
			if event.get("fx") == "ult_warn":
				assert(event.get("mini", false))
			assert(event.get("fx") not in ["ult_join", "ult_dash", "inyeon_fin", "inyeon_theme"], "Minis must not enter joint ultimates or full charge movement")
		if ui_result.is_empty():
			ui_result = result
		var repeated := RtBattle.new(seed_).run(a, "eorin", 100, null, b, "hagik", 100, null, "", "", [], {"A": "auto", "B": "auto"})
		assert(JSON.stringify(result.ev) == JSON.stringify(repeated.ev))
	assert(fired >= 8)
	var engine := RtBattle.new(19)
	var syn := Battle.fac_syn(legends.slice(0, 3), "eorin")
	var a_unit = engine.mk_unit(legends[0], DB.FORM.eorin.slots[0], "A", 100, 0, null, syn)
	var ally = engine.mk_unit(legends[1], DB.FORM.eorin.slots[1], "A", 100, 1, null, syn)
	var ally2 = engine.mk_unit(legends[2], DB.FORM.eorin.slots[2], "A", 100, 2, null, syn)
	ally.troops = ally.max * 0.5
	ally2.troops = ally2.max * 0.2
	assert(engine.resolve_targets("allyLow2", [], a_unit, [a_unit, ally, ally2]) == [ally2, ally])
	assert(not engine._join_ok(a_unit) and not engine._dash_ult(a_unit))
	engine._ult_by = a_unit
	engine._ult_taken = {}
	assert(engine._ult_clamp(ally, ally.max) <= ally.max * 0.150001)
	engine._ult_by = null
	engine = null
	a_unit = null
	ally = null
	ally2 = null
	print("PASS mini combat: actual gauge activations=", fired, " / one per unit / deterministic replay / no joins or dash / wounded ally targeting / damage cap")
	var helper = preload("res://tests/formation_preview.gd").new()
	var high_a: Array = DB.auto_place(helper._cards(["주유", "육손", "제갈량", "방통", "감녕", "황개", "정보", "조운", "관우"]), "eorin")
	var high_b: Array = DB.auto_place(helper._cards(["조조", "하후연", "사마의", "마초", "허저", "곽가", "손권", "여포", "화타"]), "hagik")
	helper.free()
	Battle.legend_minis_enabled = false
	var old := RtBattle.new(5100).run(high_a, "eorin", 100, null, high_b, "hagik", 100, null, "", "", [], {"A": "auto", "B": "auto"})
	Battle.legend_minis_enabled = true
	var current := RtBattle.new(5100).run(high_a, "eorin", 100, null, high_b, "hagik", 100, null, "", "", [], {"A": "auto", "B": "auto"})
	assert(JSON.stringify(old.ev) == JSON.stringify(current.ev), "Upper-tier and kiin battles must remain identical")
	print("PASS upper-tier regression: enabling legend minis leaves a battle with no ordinary legends unchanged")
	Settings.load_cfg()
	Settings.type2 = true
	Settings.war_painting = true
	Settings.cam_fx = 0
	Settings.apply()
	var view := BattleView.new()
	add_child(view)
	await get_tree().process_frame
	view.play_res(ui_result, "pvp")
	view.speed = 0.0
	view.set_process(false)
	var source := JSON.stringify(ui_result)
	var groups: Array = view.groups.filter(func(g): return g.ult != null)
	assert(not groups.is_empty())
	for mode in [0, 1, 2]:
		Settings.ult_fx = mode
		view.remark_ults()
		assert(groups.all(func(g): return not g.big))
	view.speed = 1.0
	var timing := [view.clock, view.speed, view.freeze_t, view.slow_t, view.field._cine]
	var warn: Dictionary = ui_result.ev.filter(func(e): return e.get("fx") == "ult_warn")[0]
	view._ult_warn(warn)
	assert(view.hud.charges.is_empty())
	view._start_ult(groups[0])
	assert(groups[0].lite and view.hud.cut == null)
	assert(timing == [view.clock, view.speed, view.freeze_t, view.slow_t, view.field._cine])
	var caster: Squad = view.field.squads[groups[0].who]
	assert(view.hud.ult_notices[caster.camp][0].mini and view.hud.ult_notices[caster.camp][0].cid == caster.cid)
	assert(view.hud.ult_notices[caster.camp][0].speech == groups[0].ult.shout)
	view.hud.layout_ult_notices()
	assert(view.hud.ult_notices[caster.camp][0].rect.has_area())
	assert(JSON.stringify(ui_result) == source)
	print("PASS mini presentation: fast in every mode / no large charge banner / no slow pause or camera / actual caster portrait / immutable source replay")
	caster = null
	view.field.ult.clear()
	view.type2.painting.reset()
	view.queue_free()
	view = null
	await get_tree().process_frame
	await get_tree().process_frame
	Sfx.music("")
	await get_tree().create_timer(0.7).timeout
	get_tree().quit()
