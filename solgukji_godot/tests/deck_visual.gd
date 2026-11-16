extends Control
## Visual smoke check with representative replay events. --shot saves a portrait preview.
func _ready() -> void:
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
	print("PASS deck visuals: source / throttle / ordinary hit / reset / draw")
	get_tree().quit()
