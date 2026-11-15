extends Control
## 병사 단계(잡병 → 신병) 보기 캡처 (11/15) —— 실행 (창이 뜬다 · 휴대폰 세로 720x1280):
##   godot --path . --resolution 720x1280 res://tests/grade_shot.tscn -- [--ta=3,4,5,6,7,8,3,5,7 아군 칸마다 등급] [--tb=3 적 등급(하나면 모두)] [--seed=5]
##     [--shots=1.5,6,10 그 전장 시각(초)에 찍는다] [--tag=이름] [--out=폴더] [--grade=0 단계 표현 끔(전)] [--quality=0|1|2] [--tags=창병,창병,... 병종 순서]
##     [--zoom=1.6 아군 가운데로 다가가 찍는다]
## 칸마다 그 등급의 카드를 뽑아 BattleView(타입2)로 틀고, 부대마다 정해진 단계(Type2View.grade_of)를 한 줄로 찍는다 ("GRADE|" 접두).
## 그리기만 보는 점검 —— 전투 결과는 건드리지 않는다.

var _args := {}


func _ready() -> void:
	for s in OS.get_cmdline_user_args():
		var kv := s.trim_prefix("--").split("=", true, 1)
		_args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	PlayLog.enabled = false
	Settings.load_cfg()
	Settings.type2 = true
	Settings.cam_fx = 0
	if _args.has("quality"):
		Settings.quality = int(_args.quality)
	Settings.apply()
	theme = UI.theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var t2s: Script = load("res://scripts/field/type2_view.gd")
	if _args.has("grade"):
		t2s.set("grade_on", str(_args.grade) != "0")
	var view := BattleView.new()
	view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(view)
	await get_tree().process_frame
	Settings.apply_port(view.port)
	var sd := int(_args.get("seed", "5"))
	var ta: Array = str(_args.get("ta", "3,4,5,6,7,8,3,5,7")).split(",", false)
	var tb: Array = str(_args.get("tb", "3")).split(",", false)
	var tags: Array = str(_args.get("tags", "창병,창병,창병,창병,창병,창병,기병,궁병,도적")).split(",", false)
	var r := RandomNumberGenerator.new()
	r.seed = sd
	var bt := {"kind": "pvp", "a": _side(ta, tags), "b": _side(tb, tags), "seed": sd, "title": "병사 단계 점검", "foe": "적군", "inputs": []}
	view.play(bt, false)
	view._set_speed(1.0)
	var out := str(_args.get("out", "user://"))
	var tag := str(_args.get("tag", "grade"))
	var t2: Type2View = view.type2
	if t2.has_method("grade_of"):
		for sq: Squad in view.field.order:
			var g: int = t2.grade_of(sq)
			print("GRADE|%s|%s|등급 %d|병력 %d|단계 %d %s" % [sq.key, sq.row.get("name", "?"), sq.tier, int(sq.max), g, str(t2s.get("GRADE")[g][0])])
	var zoom := float(_args.get("zoom", "0"))
	for a in str(_args.get("shots", "1.5,6,10")).split(",", false):
		while view.clock < float(a):
			if zoom > 0.0:
				_follow(view, zoom)
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("%s/%s_t%s.png" % [out, tag, str(a).trim_suffix(".0")])
	get_tree().quit()


## 아군 한가운데로 다가간다 (단계별 차이를 가까이서)
func _follow(view: BattleView, zoom: float) -> void:
	var t2: Type2View = view.type2
	var c := Vector2.ZERO
	var n := 0
	for sq: Squad in view.field.order:
		if sq.camp == "A" and sq.alive:
			c += sq.pos
			n += 1
	if n > 0:
		t2._focus = {"c": c / n + Vector2(float(_args.get("fx", "0")), float(_args.get("fy", "0"))), "mul": zoom, "until": view.field.clock + 0.5, "pri": 9}


func _side(tiers: Array, tags: Array) -> Dictionary:
	var deck := []
	for i in 9:
		var t := int(tiers[i % tiers.size()])
		var tg := str(tags[i % tags.size()])
		var pool := DB.by_tier(t).filter(func(k): return not DB.is_kiin(k) and DB.C[k].kind != "retired" and not deck.has(k))
		pool.sort()
		var pick := ""
		for k in pool:
			if DB.C[k].tag == tg:
				pick = k
				break
		if pick == "" and not pool.is_empty():
			pick = pool[0]
		if pick != "":
			deck.append(pick)
	var cards := DB.auto_place(deck, "eorin")
	return {"cards": cards, "form": "eorin", "morale": 100, "tac": "균형", "equip": []}
