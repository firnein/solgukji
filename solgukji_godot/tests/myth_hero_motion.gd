extends Control

const Painting = preload("res://scripts/field/war_painting.gd")

func _ready() -> void:
	PlayLog.enabled = false
	Settings.type2 = true
	Settings.war_painting = true
	Settings.apply()
	var view := BattleView.new()
	view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(view)
	await get_tree().process_frame
	var deck := ["c177", "c186", "c187", "c181", "c178", "c182", "c192", "c194", "c195"]
	var side := {"cards": DB.auto_place(deck, "eorin"), "form": "eorin", "morale": 100, "tac": "균형", "equip": []}
	var enemy := side.duplicate(true)
	enemy.cards = DB.auto_place(["s01", "c163", "c167", "c155", "c156", "c172", "s14", "c175", "c169"], "eorin")
	await view.play({"kind": "pvp", "a": side, "b": enemy, "seed": 5,
		"title": "장수 단독 인형 점검", "foe": "적군", "inputs": []}, false)
	await get_tree().process_frame
	var painting: Painting = view.type2.painting
	var valid := painting != null and painting.hero_ready and painting._hero_poses == 4
	var immortal_cards := DB.by_tier(7)
	if valid:
		valid = not immortal_cards.is_empty()
		for cid in immortal_cards:
			valid = valid and painting._immortal_hero_cells.has(DB.person(cid))
		for cid in DB.by_tier(8):
			var person := DB.person(cid)
			if DB.RECOF.has(cid) and not DB.is_foe(cid):
				valid = valid and painting._hero_cells.has(person)
	var leads := {}
	var solo_count := 0
	if valid:
		painting._proj_begin()
		for sq: Squad in view.field.order:
			if not painting._shows_hero(sq):
				continue
			var form := painting._formation(sq)
			form.contact_limits = []
			var person := DB.person(sq.cid)
			if person == "조조":
				form.hero_hurt_at = painting.visual_time - 0.02
			var before := painting.figure_count
			painting._collect_figures(sq, form)
			var base := before * painting.FIG_W
			var style := int(painting._figs[base + 11]) % 16
			valid = valid and painting.figure_count == before + 1 and painting._figs[base + 3] >= painting.HERO_CELL
			valid = valid and style == (12 if sq.tier == 7 else 13)
			var hud := view.hud
			var half := hud._painted_size(sq) * 0.5
			var foot: Vector2 = painting.get_global_transform_with_canvas() * painting.hero_feet[sq.key]
			var expected := hud.get_global_transform_with_canvas().affine_inverse() * foot + Vector2(0, half.y + 4)
			expected = expected.clamp(Vector2(half.x + 3, 94 + half.y), hud.size - Vector2(half.x + 3, half.y + 3))
			var label: Vector2 = hud._flat_token_pos([[0, sq]], true)[sq.key]
			valid = valid and label.is_equal_approx(expected)
			if person == "조조":
				valid = valid and int(painting._figs[base + 3]) == painting.HERO_CELL + painting._hero_index(sq) + 3
				valid = valid and painting._figs[base + 8] == 0.0
			if person == "장료":
				valid = valid and is_equal_approx(painting._hero_scale[painting._hero_index(sq)], 0.86)
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
	var checked := _check_repeated_hits(painting, view.field.order.back())
	valid = valid and checked == _hero_card_ids().size()
	print("HERO_SOLO_MOTION|%s|solo=%d|immortal=%d" % ["PASS" if valid else "FAIL", solo_count, immortal_cards.size()])
	print("HERO_HIT_SEQUENCE|%d/%d" % [checked, _hero_card_ids().size()])
	view.queue_free()
	await get_tree().process_frame
	for player in Sfx.get_children():
		if player is AudioStreamPlayer:
			player.stop()
	await get_tree().create_timer(0.1).timeout
	get_tree().quit(0 if valid else 1)

func _hero_card_ids() -> Array:
	return DB.C.keys().filter(func(cid): return int(DB.C[cid].tier) in [7, 8] and DB.C[cid].kind != "foe")

func _check_repeated_hits(painting: Painting, source: Squad) -> int:
	var checked := 0
	for cid in _hero_card_ids():
		var card: Dictionary = DB.C[cid]
		var row := {"id": cid, "key": "audit:" + cid, "tag": card.tag, "tier": card.tier, "slot": 0, "camp": "A", "max": card.tr}
		var sq := Squad.new(row, Vector2(-100, 0), RandomNumberGenerator.new())
		if not painting._shows_hero(sq):
			continue
		var form := painting._formation(sq)
		var start := painting.visual_time
		var hit_cell := painting.HERO_CELL + painting._hero_index(sq) + 3
		var stable := true
		for dt in [0.0, 0.08, 0.16, 0.24, 0.34, 0.39]:
			painting.visual_time = start + dt
			if dt > 0.0:
				form.facing_right = not form.facing_right
			if dt < 0.32:
				painting._record_contact(source, sq, 1.5, false)
			var base := painting.figure_count * painting.FIG_W
			painting._collect_figures(sq, form)
			stable = stable and is_equal_approx(form.hero_hurt_at, start)
			stable = stable and (int(painting._figs[base + 3]) == hit_cell) == (dt < painting.HERO_RECOIL_TIME)
			if dt < painting.HERO_RECOIL_TIME:
				stable = stable and (painting._figs[base + 9] > 0.5) == form.hero_hurt_mirror
			stable = stable and painting._figs[base + 8] == 0.0
		if stable:
			checked += 1
		else:
			printerr("Unstable hero hit sequence: ", DB.person(cid), " tier ", card.tier)
	return checked
