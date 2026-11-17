extends Node
## 기병 돌격은 근접·주행·창벽·수몰·반격·고유기 조건을 독립적으로 확인한다.
func setup_battle(tag: String) -> RtBattle:
	var helper = preload("res://tests/target_area_regression.gd").new()
	var battle := RtBattle.new(123)
	battle._setup([helper.card("기병")], "eorin", 100, null, [helper.card(tag)], "eorin", 100, null, "", "", [], {"A": "manual", "B": "manual"})
	helper.free()
	battle._paeup.clear()
	for i in battle.units.size():
		var unit = battle.units[i]
		unit.m = {}
		unit.caps.clear()
		unit.ts = null
		unit.hw = 10
		unit.hd = 10
		unit.pos = Vector2(i * 20, 0)
		unit.fwd = Vector2.RIGHT if i == 0 else Vector2.LEFT
		unit.max = 1000000
		unit.troops = 1000000
		unit.st.clear()
	return battle

func strike(battle: RtBattle) -> Dictionary:
	var a = battle.units[0]
	var d = battle.units[1]
	var begin := battle.ev.size()
	battle.phys_hit(a, d, 1.0, true)
	var hits := battle.ev.slice(begin).filter(func(e): return e.get("fx") == "phys" and e.get("a") == a.key and e.get("f") == d.key)
	assert(not hits.is_empty())
	return hits[0]

func _ready() -> void:
	get_tree().create_timer(10.0).timeout.connect(func(): get_tree().quit(1))
	var battle := setup_battle("궁병")
	var a = battle.units[0]
	a.ran = RtBattle.CHARGE_RUN + 1
	assert(strike(battle).get("painted_charge") == "hit")
	assert(a.ran == 0.0 and strike(battle).get("painted_charge", "") == "")
	var blocked := setup_battle("창병")
	blocked.units[0].ran = RtBattle.CHARGE_RUN + 1
	assert(strike(blocked).get("painted_charge") == "brace")
	assert(int(blocked.stats.get("charges", 0)) == 0)
	blocked.units[1].fwd = Vector2.UP
	blocked.units[0].ran = RtBattle.CHARGE_RUN + 1
	assert(strike(blocked).get("painted_charge") == "hit", "Spear wall only blocks its front")
	for condition in ["flood", "far", "counter", "ultimate", "short_run"]:
		battle = setup_battle("궁병")
		a = battle.units[0]
		a.ran = RtBattle.CHARGE_RUN + 1
		match condition:
			"flood": a.st.append({"k": "flood", "val": 1.0, "dur": 1})
			"far": battle.units[1].pos = Vector2(1000, 0)
			"counter": a.countering = true
			"ultimate": battle._in_ult = true
			"short_run": a.ran = RtBattle.CHARGE_RUN - 1
		assert(strike(battle).get("painted_charge", "") == "", condition)
		if condition == "counter":
			assert(a.ran > RtBattle.CHARGE_RUN, "A counter does not consume the next charge")
	print("PASS cavalry: run threshold / one-shot consumption / spear front vs side / flood / far / counter / ultimate")
	get_tree().quit()
