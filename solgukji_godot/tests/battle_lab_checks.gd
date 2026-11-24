extends Node
const Decks := preload("res://tests/battle_lab_decks.gd")
const Lab := preload("res://tests/battle_lab.gd")

func _ready() -> void:
	get_tree().create_timer(45.0).timeout.connect(func(): get_tree().quit(1))
	PlayLog.enabled = false
	var rng := RandomNumberGenerator.new()
	var seen := {}
	for preset in Decks.PRESETS:
		for sample in 8:
			rng.seed = 81 + sample
			var a := Decks.make_mix(preset.counts, rng)
			var b := Decks.make_mix(preset.counts, rng, Decks.pv(a))
			assert(a.size() == 9 and b.size() == 9)
			assert(Decks.counts_of(a) == preset.counts and Decks.counts_of(b) == preset.counts)
			assert(a.all(func(k): return not DB.is_foe(k) and DB.C[k].kind != "retired"))
			assert(absf(Decks.pv(a) - Decks.pv(b)) / maxf(Decks.pv(a), Decks.pv(b)) <= 0.1, "Matching must keep similar PV for real mixed-card pools")
			seen[JSON.stringify(a)] = true
	assert(seen.size() > 20, "Repeated mixed presets must provide varied actual generals")
	rng.seed = 13
	var deterministic := Decks.make_mix(Decks.PRESETS[0].counts, rng)
	rng.seed = 13
	assert(Decks.make_mix(Decks.PRESETS[0].counts, rng) == deterministic)
	assert(Decks.make_mix([10, 0, 0, 0, 0, 0, 0, 0, 0], rng).is_empty())
	assert(Decks.make_mix([0, 0, 0, 0, 0, 0, 0, 0, 0], rng).is_empty())
	assert(Decks.make_mix([-1, 0, 0, 0, 0, 0, 0, 0, 0], rng).is_empty())
	var archive := Decks.load_online("user://battle_lab_checks/missing")
	assert(archive.archived and archive.records.size() >= 10)
	var pair := Decks.match_online(archive.records, rng, 0)
	assert(pair.size() == 2)
	assert(archive.records[pair[0]].deck != archive.records[pair[1]].deck)
	assert(Decks.match_online([archive.records[0]], rng).is_empty())
	var reordered: Dictionary = archive.records[0].duplicate(true)
	reordered.deck.reverse()
	assert(Decks.match_online([archive.records[0], reordered], rng).is_empty(), "Changing card order alone must not count as a different army")
	var fixture := "user://battle_lab_checks/import"
	DirAccess.make_dir_recursive_absolute(fixture)
	var file := FileAccess.open(fixture.path_join("sample.jsonl"), FileAccess.WRITE)
	var raw := {"ev": "battle_start", "kind": "pvp", "me": PlayLog.side(deterministic), "foe": PlayLog.side(deterministic), "foe_hidden": true,
		"form": "bongsi", "tac": "균형", "morale": 110, "equip": 2}
	file.store_line(JSON.stringify(raw))
	file.store_line("{unfinished")
	var unknown: Dictionary = raw.duplicate(true)
	unknown.me.cards[0][0] = "missing-card"
	file.store_line(JSON.stringify(unknown))
	file.close()
	file = null
	var imported := Decks.load_online(fixture, false)
	assert(imported.records.size() == 1 and imported.skipped == 2)
	assert(imported.records[0].deck == deterministic and imported.records[0].form == "bongsi" and imported.records[0].morale == 110 and imported.records[0].equip)
	assert(not imported.records[0].has("foe") and not imported.records[0].has("player"))
	print("PASS lab deck data: mixed tier and separate kiin counts / varied generals / seeded generation / similar PV / bounds / real online archive / missing-card rejection / hidden opponent omitted / partial log / no identical-army matches")

	var lab = Lab.new()
	add_child(lab)
	for i in 3:
		await get_tree().process_frame
	assert(lab.side.A.deck.size() == 9 and lab.side.B.deck.size() == 9)
	assert(lab._preset_pick.selected == 0)
	assert(absf(Decks.pv(lab.side.A.deck) - Decks.pv(lab.side.B.deck)) / maxf(Decks.pv(lab.side.A.deck), Decks.pv(lab.side.B.deck)) <= 0.1)
	lab._preset_pick.select(1)
	lab._apply_preset()
	assert(Decks.counts_of(lab.side.A.deck) == Decks.PRESETS[0].counts)
	assert(lab._mix_counts("A") == Decks.PRESETS[0].counts)
	lab.side.A.mix[0].value = 2
	assert(lab.side.A.mix_button.disabled and lab.side.A.mix_total.text.begins_with("10"))
	lab._fill("A")
	assert(lab.side.A.mix[0].value == 2, "Filtering candidates must not discard unapplied mixed-tier edits")
	lab.side.A.mix[0].value = 1
	lab._random_mix("A")
	assert(Decks.counts_of(lab.side.A.deck) == Decks.PRESETS[0].counts)
	var before: Array = lab.side.A.deck.duplicate()
	lab.side.A.deck_list.select(0)
	lab.side.A.list.select(0)
	var replacement: String = lab.side.A.list.get_item_metadata(0)
	lab._replace_selected("A")
	assert(lab.side.A.deck[0] == replacement and lab.side.A.deck.slice(1) == before.slice(1))
	assert(lab._mix_counts("A") == Decks.counts_of(lab.side.A.deck))
	var edited: Array = lab.side.A.deck.duplicate()
	lab._reload_online(fixture)
	lab._preset_pick.select(0)
	lab._apply_preset()
	assert(lab.side.A.deck == edited, "A missing match after folder refresh must preserve the edited army")
	lab._reload_online()
	lab._preset_pick.select(1)
	lab.side.A.morale = 80
	lab.side.A.equip = false
	lab.side.B.morale = 130
	lab.side.B.equip = true
	lab._swap()
	assert(lab.side.A.morale_box.value == 130 and lab.side.A.equip_box.button_pressed)
	assert(lab.side.B.morale_box.value == 80 and not lab.side.B.equip_box.button_pressed)
	lab._apply_preset()
	lab.games_box.value = 1
	await lab._sim()
	assert(lab.out.get_parsed_text().contains("시뮬 1판") and not lab._busy)
	lab.seed_rand.button_pressed = false
	lab._watch()
	while not lab.view.running:
		await get_tree().process_frame
	assert(lab.view.res.roster.size() == 18)
	assert(lab.view.res.roster.any(func(unit): return DB.is_kiin(unit.id)))
	print("PASS lab UI: online mixed default / editable tier counts / over-cap disabled / regenerate / replace one slot / counter sync / swap morale and equipment / simulation / actual mixed replay")
	lab.view.queue_free()
	lab.view = null
	lab.queue_free()
	lab = null
	await get_tree().process_frame
	await get_tree().process_frame
	Sfx.music("")
	await get_tree().create_timer(0.7).timeout
	get_tree().quit()
