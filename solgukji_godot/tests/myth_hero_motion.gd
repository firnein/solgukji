extends Control

const Painting = preload("res://scripts/field/war_painting.gd")

func _ready() -> void:
	PlayLog.enabled = false
	Settings.type2 = true
	Settings.war_painting = true
	Settings.apply()
	var view := BattleView.new()
	add_child(view)
	await get_tree().process_frame
	var deck := ["c177", "c186", "c187", "c181", "c178", "c190", "c192", "c194", "c195"]
	var side := {"cards": DB.auto_place(deck, "eorin"), "form": "eorin", "morale": 100, "tac": "균형", "equip": []}
	var enemy := side.duplicate(true)
	enemy.cards = DB.auto_place(["s01", "c163", "c167", "c155", "c156", "c172", "s14", "c175", "c169"], "eorin")
	await view.play({"kind": "pvp", "a": side, "b": enemy, "seed": 5,
		"title": "장수 단독 인형 점검", "foe": "적군", "inputs": []}, false)
	await get_tree().process_frame
	var painting: Painting = view.type2.painting
	var valid := painting != null and painting.hero_ready and painting._hero_poses == 4 and painting._hero_cells.size() == 12
	var immortal_cards := DB.by_tier(7)
	if valid:
		valid = not immortal_cards.is_empty()
		for cid in immortal_cards:
			valid = valid and painting._immortal_hero_cells.has(DB.person(cid))
		for cid in DB.by_tier(8):
			var person := DB.person(cid)
			valid = valid and (painting._hero_cells.has(person) or painting._immortal_hero_cells.has(person))
	var leads := {}
	var solo_count := 0
	if valid:
		painting._proj_begin()
		for sq: Squad in view.field.order:
			if not painting._shows_hero(sq):
				continue
			var form := painting._formation(sq)
			form.contact_limits = []
			var before := painting.figure_count
			painting._collect_figures(sq, form)
			var base := before * painting.FIG_W
			var style := int(painting._figs[base + 11]) % 16
			valid = valid and painting.figure_count == before + 1 and painting._figs[base + 3] >= painting.HERO_CELL
			valid = valid and style == (12 if sq.tier == 7 else 13)
			solo_count += 1
			leads[sq.tier] = sq
	for lead: Squad in leads.values():
		var body_count := painting.bodies.size()
		painting._sync_troops([{"key": lead.key, "troops": 0}], null, lead, 2.0, false)
		var fall: Dictionary = painting._hero_falls.get(lead.key, {})
		valid = valid and not fall.is_empty() and painting.has_unsettled_casualties()
		valid = valid and painting.bodies.size() == body_count
		if not fall.is_empty():
			valid = valid and is_equal_approx(float(fall.start), painting.visual_time)
			painting._collect_hero_fall(lead, fall)
			var hit_cell := int(painting._figs[(painting.figure_count - 1) * painting.FIG_W + 3])
			valid = valid and hit_cell == painting.HERO_CELL + painting._hero_index(lead) + 3
		painting.sync_quiet([{"key": lead.key, "troops": lead.max}])
		valid = valid and painting._hero_falls.is_empty()
	valid = valid and solo_count == 18 and leads.size() == 2
	print("HERO_SOLO_MOTION|%s|solo=%d|immortal=%d" % ["PASS" if valid else "FAIL", solo_count, immortal_cards.size()])
	view.queue_free()
	await get_tree().process_frame
	for player in Sfx.get_children():
		if player is AudioStreamPlayer:
			player.stop()
	await get_tree().create_timer(0.1).timeout
	get_tree().quit(0 if valid else 1)
