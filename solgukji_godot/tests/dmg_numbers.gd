extends Node
## 11/25 삽화 피해 숫자 —— 고유기 타격은 모으기 문턱(12%) · 1.5초 막기 없이 늘 뜨고, 그리지 않는 기여 알림(deck)은 숫자를 막지 않는다.
## 실행: godot --headless --path . res://tests/dmg_numbers.tscn
const Decks := preload("res://tests/battle_lab_decks.gd")

func _ready() -> void:
	get_tree().create_timer(90.0).timeout.connect(func(): get_tree().quit(1))
	PlayLog.enabled = false
	var fails := []
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	var counts := [0, 0, 0, 0, 9, 0, 0, 0, 0]
	var a := DB.auto_place(Decks.make_mix(counts, rng), "eorin")
	var b := DB.auto_place(Decks.make_mix(counts, rng), "hagik")
	var res := RtBattle.new(77).run(a, "eorin", 100, null, b, "hagik", 100, null, "", "", [], {"A": "auto", "B": "auto"})
	Settings.load_cfg()
	Settings.type2 = true
	Settings.war_painting = true
	Settings.dmg_numbers = 1
	Settings.cam_fx = 0
	Settings.apply()
	var view := BattleView.new()
	add_child(view)
	await get_tree().process_frame
	view.play_res(res, "pvp")
	view.speed = 0.0
	view.set_process(false)
	var hud = view.hud
	var key: String = view.field.squads.keys()[0]
	var sq: Squad = view.field.squads[key]
	var nums := func() -> int: return hud.floats.filter(func(f): return f.key == key and f.get("num", false)).size()
	# ① 작은 고유기 타격(최대 병력의 3%)도 바로 뜬다
	hud.floats.clear()
	hud._small.clear()
	hud.damage(key, sq.max * 0.03, "int", false, false, true)
	if nums.call() != 1:
		fails.append("작은 고유기 타격에 숫자가 없다")
	# ② 같은 부대에 방금 숫자가 떠 있어도 고유기 타격은 뜬다 (합쳐지거나 새로)
	var before: float = hud.floats.filter(func(f): return f.get("num", false)).map(func(f): return f.amount).reduce(func(x, y): return x + y, 0.0)
	hud.damage(key, sq.max * 0.2, "fire", true, false, true)
	var after: float = hud.floats.filter(func(f): return f.get("num", false)).map(func(f): return f.amount).reduce(func(x, y): return x + y, 0.0)
	if after - before < sq.max * 0.2 - 1.0:
		fails.append("숫자가 떠 있는 부대에 고유기 치명타 숫자가 없다")
	# ③ 그리지 않는 기여 알림(deck)만 있으면 12% 넘는 평타 · 기술 타격이 막히지 않는다
	hud.floats.clear()
	hud._small.clear()
	hud.float_text(key, "혼란 —— 차례 날림", Color.WHITE, 12, true, true, "")
	if not hud.floats.any(func(f): return f.get("deck", false)):
		fails.append("기여 알림이 deck 으로 들어가지 않았다 (시험 전제)")
	hud.damage(key, sq.max * 0.13, "int", false)
	if nums.call() != 1:
		fails.append("보이지 않는 기여 알림이 숫자를 막았다")
	# ④ 평타 · 기술 작은 타격은 여전히 모은다 (12% 문턱 그대로)
	hud.floats.clear()
	hud._small.clear()
	hud.damage(key, sq.max * 0.05, "phys", false)
	if nums.call() != 0:
		fails.append("작은 평타에 바로 숫자가 떴다 (모으기가 사라짐)")
	hud.damage(key, sq.max * 0.08, "phys", false)
	if nums.call() != 1:
		fails.append("모은 평타가 12% 를 넘었는데 숫자가 없다")
	# ⑤ 보이는 숫자가 1.5초 안에 있으면 평타는 여전히 막는다
	hud.damage(key, sq.max * 0.2, "phys", false)
	if nums.call() != 1:
		fails.append("1.5초 막기가 사라졌다")
	# ⑥ 실제 전투 사건 —— 고유기 묶음 타격은 _damage_number 가 ult 로 넘긴다
	var ult_hits := 0
	hud.floats.clear()
	hud._small.clear()
	for i in res.ev.size():
		var e: Dictionary = res.ev[i]
		if view.group_of[i].ult != null and str(e.get("fx", "")) in ["phys", "int"] and float(e.get("n", 0.0)) > 0.0 and not e.has("kin_by"):
			var tk := str(e.get("f", ""))
			if not view.field.squads.has(tk):
				continue
			var c0: int = hud.floats.filter(func(f): return f.key == tk and f.get("num", false)).size()
			var a0: float = hud.floats.filter(func(f): return f.key == tk and f.get("num", false)).map(func(f): return f.amount).reduce(func(x, y): return x + y, 0.0)
			view._damage_number(i, e, tk)
			var c1: int = hud.floats.filter(func(f): return f.key == tk and f.get("num", false)).size()
			var a1: float = hud.floats.filter(func(f): return f.key == tk and f.get("num", false)).map(func(f): return f.amount).reduce(func(x, y): return x + y, 0.0)
			ult_hits += 1
			if c1 <= c0 and a1 <= a0:
				fails.append("고유기 타격 사건 %d 에 숫자가 없다" % i)
	print("DMG_NUM|고유기 타격 사건 %d 개 모두 숫자 확인" % ult_hits)
	if ult_hits == 0:
		fails.append("이 판에 고유기 타격이 없다 (시험 덱을 바꿀 것)")
	print("FAIL: " + (" / ".join(fails) if not fails.is_empty() else "없음"))
	view.field.ult.clear()
	view.type2.painting.reset()
	view.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	Sfx.music("")
	await get_tree().create_timer(0.5).timeout
	get_tree().quit(0 if fails.is_empty() else 1)
