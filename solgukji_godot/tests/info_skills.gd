extends Control
const Skills := preload("res://scripts/ui/skill_panel.gd")

func settle() -> void:
	for i in 4:
		await get_tree().process_frame

func _ready() -> void:
	theme = UI.theme()
	get_tree().create_timer(90.0).timeout.connect(func(): get_tree().quit(1))
	PlayLog.enabled = false
	DB.warm_enabled = false
	var gs := GameScreen.new()
	gs.run = Run.new()
	gs.run.new_game(71)
	var hero := ""
	var blink := ""
	for k in DB.C:
		if DB.is_foe(k):
			continue
		if DB.person(k) == "주유" and int(DB.C[k].tier) == 8:
			hero = k
		if Skills.escape_spec(k).get("name") == "선술":
			blink = k
	assert(hero != "" and blink != "")
	var source := JSON.stringify(DB.C[hero])
	var items := gs._skill_entries(hero)
	assert(items.size() == DB.C[hero].sks.size() + 2)
	for i in DB.C[hero].sks.size():
		var entry: Dictionary = items.filter(func(e): return e.id == "skill:%d" % i)[0]
		assert(entry.effect == DB.skill_desc(DB.C[hero], DB.C[hero].sks[i]))
		assert(entry.when == DB.sk_when(DB.C[hero].sks[i], DB.C[hero]))
	assert(items[-1].id == "escape" and items[-1].name == RtBattle.ESCAPE[DB.C[hero].tag].n)
	assert(Skills.escape_spec(blink).cd == preload("res://scripts/sig_rt.gd").BLINK_CD)
	for k in ["strat", "schem", "schol"]:
		assert(Skills.escape_spec(k).cd == RtBattle.ESCAPE_CD)
	assert(Skills.escape_spec("spear").is_empty())
	for def in GameScreen.MinorTriggers.STORY.values() + GameScreen.MinorTriggers.CLASS.values():
		assert(def[0] in ["every", "hit_n", "ally_low"] or GameScreen.MINOR_WHEN.has(def[0]), "Every actual minor trigger needs an accurate UI condition")
	assert(gs.minor_when(hero).contains("재사용") and not gs.minor_when(hero).contains("공격 4번"))
	assert(JSON.stringify(DB.C[hero]) == source)
	var legacy := {"fx": "buff", "f": "A0", "sig": true, "t": "주유의 화공 폭발 —— 붙은 적을 떼어 냈다"}
	var spec := Skills.escape_spec(hero)
	assert(Skills.escape_event(legacy, "A0", spec).approx)
	assert(Skills.escape_event(legacy, "B0", spec).is_empty())
	assert(Skills.escape_event({"fx": "skill", "f": "A0", "t": legacy.t}, "A0", spec).is_empty())
	print("PASS info data: full effects and conditions preserved / all trigger definitions described / four class escapes and blink / correct cooldowns / legacy record discrimination / no source mutation")

	for width in [320, 400, 520]:
		var host := VBoxContainer.new()
		host.size = Vector2(width, 1600)
		add_child(host)
		var same_items: Array = items.filter(func(e): return e.kind != "escape")
		var modern = Skills.new().setup(same_items)
		host.add_child(modern)
		var old_rows := []
		for entry in same_items:
			old_rows.append(gs._kv_box(entry.name, entry.when, entry.effect, DB.PAL.bamboo_dim, 13))
		var previous := gs._kv_stack(old_rows)
		host.add_child(previous)
		var compact = Skills.new().setup(items, true)
		host.add_child(compact)
		var expanded = Skills.new().setup(items)
		host.add_child(expanded)
		await settle()
		var after: float = modern.get_combined_minimum_size().y
		var before: float = previous.get_combined_minimum_size().y
		print("INFO_DENSITY width=", width, " before=", before, " after=", after)
		assert(after < before, "The same skills must take less vertical space without reducing the full text font")
		assert(compact.get_combined_minimum_size().y < expanded.get_combined_minimum_size().y)
		for control in modern.find_children("*", "Control", true, false):
			if control.is_visible_in_tree():
				assert(control.global_position.x + control.size.x <= modern.global_position.x + modern.size.x + 1.0, "Skill rows must not overflow narrow sheets")
		host.queue_free()
		await settle()

	var panel = Skills.new().setup(items)
	panel.size.x = 360
	add_child(panel)
	panel.enable_runtime()
	assert(panel.rows.escape.status.text == "조건 대기")
	panel.update_runtime({}, 0.0, false, false)
	assert(panel.rows.escape.status.text == "전투 불가" and not panel.rows.escape.progress.visible)
	panel.update_runtime({}, 0.0, true, false)
	assert(panel.rows.escape.status.text == "조건 대기" and panel.rows.escape.progress.visible)
	var states := {"escape": {"tm": 10.0, "n": 1, "cd": 8.0, "approx": false}}
	panel.update_runtime(states, 10.3, true, false)
	assert(panel.rows.escape.status.text == "방금 발동" and panel.rows.escape.root.pulse > 0.0)
	panel.update_runtime(states, 12.5, true, false)
	assert(panel.rows.escape.status.text == "재사용 5.5초")
	var paused: String = panel.rows.escape.status.text
	panel.update_runtime(states, 12.5, true, false)
	assert(panel.rows.escape.status.text == paused)
	panel.update_runtime(states, 18.0, true, false)
	assert(panel.rows.escape.status.text == "조건 대기")
	panel.update_runtime(states, 19.0, false, false)
	assert(panel.rows.escape.status.text == "전투 불가" and not panel.rows.escape.progress.visible)
	panel.update_runtime(states, 19.0, true, true)
	assert(panel.rows.escape.status.text == "전투 종료")
	panel.queue_free()
	print("PASS info layout: compact at 320/400/520 px / bounded rows / source text retained / escape flash, count and exact cooldown / pause, death and finish")

	var helper = preload("res://tests/formation_preview.gd").new()
	var a: Array = DB.auto_place(helper._cards(["주유", "육손", "제갈량", "방통", "감녕", "황개", "정보", "조운", "관우"]), "eorin")
	var b: Array = DB.auto_place(helper._cards(["조조", "하후연", "사마의", "마초", "허저", "곽가", "손권", "여포", "화타"]), "hagik")
	helper.free()
	var result := RtBattle.new(5100).run(a, "eorin", 100, null, b, "hagik", 100, null, "", "", [], {"A": "auto", "B": "auto"})
	var events: Array = result.ev.filter(func(e): return e.has("escape"))
	assert(not events.is_empty())
	var event: Dictionary = events[0]
	var index: int = result.ev.find(event)
	var unchanged := JSON.stringify(result)
	var view := BattleView.new()
	add_child(view)
	await settle()
	view.play_res(result, "pvp")
	view.speed = 0.0
	view.set_process(false)
	view.live_i = index - 1
	view.clock = BattleView.OPEN_RT + float(event.tm) - 0.01
	var info = GameScreen.BattleUnitCard.new(gs, view, event.f)
	add_child(info)
	await settle()
	assert(info._skill_runtime.is_empty(), "An unplayed escape must not appear early")
	view.live_i = index
	view.clock = BattleView.OPEN_RT + float(event.tm) + 2.0
	info._refresh(false)
	assert(info._skill_runtime.escape.n == 1 and not info._skill_runtime.escape.approx)
	assert(info._skills.rows.escape.status.text == "재사용 %.1f초" % (float(event.escape_cd) - 2.0))
	info._refresh(false)
	assert(info._skill_runtime.escape.n == 1, "Repeated refresh must not count the same event twice")
	assert(JSON.stringify(result) == unchanged)
	print("PASS info replay: actual engine escape metadata / only played events / one activation count / exact remaining time / no replay mutation")
	info.queue_free()
	view.field.ult.clear()
	view.type2.painting.reset()
	view.queue_free()
	gs.free()
	await settle()
	Sfx.music("")
	await get_tree().create_timer(0.7).timeout
	get_tree().quit()
