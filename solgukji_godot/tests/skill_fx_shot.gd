extends Control
## 11/23 기술 · 잔기술 이펙트 점검 (삽화 화면) —— 실행 (창이 뜬다 · 휴대폰 세로):
##   godot --path . --resolution 719x1280 res://tests/skill_fx_shot.tscn -- [--tier=5] [--seed=5] [--out=폴더] [--mode=styles|live] [--secs=30]
##   styles: 전투가 붙은 뒤 갈래 여섯씩을 적 부대들에 직접 붙이고 0.35초 뒤 찍는다 (out/skillfx_<묶음>.png)
##   live:   그대로 틀어 secs 초 동안 실제로 붙은 기술 · 잔기술 · 빠른 고유기 이펙트를 갈래별로 센다 (SKILLFX|...) + 10초마다 한 장
##           화면 동시 개수 최고치(기술 skill_fx_q · 빠른 고유기)도 적는다
##   lite:   빠른 · 미니 고유기(UltFx.play lite) 열두 종류를 넷씩 —— 기 모으기 한 장(skillfx_lite_charge) + 맞는 순간 묶음마다 (skillfx_lite_<묶음>.png)
##   tiers:  같은 이펙트를 시전 등급만 바꿔(고급 · 희귀 · 전설 · 초월 · 불멸 · 신화) 적 부대 여섯에 —— 기술 slash · fire · 잔기술 pierce · 빠른 고유기 thunder (skillfx_tier_<이름>.png)
## 저장 · 기록을 만들지 않는다 (PlayLog 끔 · 설정 저장 안 함).

var _args := {}
const STYLES := ["fire", "poison", "zone", "water", "bolt", "burst", "flash", "vortex", "curse", "slash", "pierce", "charge",
	"through", "arrows", "firearrows", "rain", "snipe", "shadow", "steal", "heal", "guard", "aura"]


func _ready() -> void:
	for s in OS.get_cmdline_user_args():
		var kv := s.trim_prefix("--").split("=", true, 1)
		_args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	PlayLog.enabled = false
	Settings.load_cfg()
	Settings.type2 = true
	Settings.war_painting = true
	Settings.cam_fx = 0
	Settings.apply()
	theme = UI.theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var view := BattleView.new()
	view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(view)
	await get_tree().process_frame
	Settings.apply_port(view.port)
	var tier := int(_args.get("tier", "5"))
	var sd := int(_args.get("seed", "5"))
	var tags: Array = ["창병", "기병", "궁병", "도적", "술사", "책사", "모사", "유생", "창병"]
	var r := RandomNumberGenerator.new()
	r.seed = sd
	var bt := {"kind": "pvp", "a": _side(tier, tags, r), "b": _side(tier, tags, r), "seed": sd,
		"title": "기술 이펙트 점검", "foe": "적군", "inputs": []}
	view.play(bt, false)
	view._set_speed(1.0)
	var out := str(_args.get("out", "user://"))
	var wp = view.type2.painting if view.type2 != null else null
	if wp == null:
		print("SKILLFX|삽화 화면이 아님")
		get_tree().quit()
		return
	if str(_args.get("mode", "styles")) == "live":
		var secs := float(_args.get("secs", "30"))
		var next_shot := 10.0
		var peak_skill := 0
		var peak_lite := 0
		while view.clock < secs and not view.finished:
			await get_tree().process_frame
			peak_skill = maxi(peak_skill, wp.skill_fx_q.size())
			peak_lite = maxi(peak_lite, wp.ults.filter(func(u): return bool(u.get("lite", false)) and wp.last_clock >= float(u.start)).size())
			if view.clock >= next_shot:
				await RenderingServer.frame_post_draw
				get_viewport().get_texture().get_image().save_png("%s/skillfx_live_%d.png" % [out, int(next_shot)])
				next_shot += 10.0
		print("SKILLFX|live|%.1f초|%s" % [view.clock, JSON.stringify(wp.skill_fx_seen)])
		print("SKILLFX|동시 최고|기술 %d (상한 %d) · 빠른 고유기 %d (상한 %d)" % [peak_skill, wp.MAX_SKILL_FX, peak_lite, wp.MAX_ULTS])
		get_tree().quit()
		return
	if str(_args.get("mode", "styles")) == "lite":
		await _lite_mode(view, wp, out)
		get_tree().quit()
		return
	if str(_args.get("mode", "styles")) == "tiers":
		await _tier_mode(view, wp, out)
		get_tree().quit()
		return
	while view.clock < 7.0:
		await get_tree().process_frame
	var group := 0
	var i := 0
	while i < STYLES.size():
		var a: Squad = null
		var foes: Array = []
		for sq: Squad in view.field.order:
			if not sq.alive:
				continue
			if sq.camp == "A" and a == null:
				a = sq
			elif sq.camp == "B":
				foes.append(sq)
		if a == null or foes.is_empty():
			break
		var names := []
		for j in mini(6, foes.size()):
			if i >= STYLES.size():
				break
			var st: String = STYLES[i]
			var who: Squad = foes[j] if st in ["heal", "guard", "aura"] else a
			wp._add_skill_fx(st, who, [foes[j].key], 1.0, 0.0)
			names.append(st)
			i += 1
		var t0: float = view.clock
		while view.clock < t0 + 0.35:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("%s/skillfx_%d.png" % [out, group])
		print("SKILLFX|묶음 %d|%s" % [group, ",".join(names)])
		group += 1
		while view.clock < t0 + 2.6:
			await get_tree().process_frame
	print("SKILLFX|끝|갈래 %d" % i)
	get_tree().quit()


func _side(t: int, tags: Array, r: RandomNumberGenerator) -> Dictionary:
	var pool := DB.by_tier(t).filter(func(k): return not DB.is_kiin(k) and DB.C[k].kind != "retired")
	pool.shuffle()
	var deck := []
	for tg in tags:
		for k in pool:
			if DB.C[k].tag == tg and not deck.has(k):
				deck.append(k)
				break
	for k in pool:
		if deck.size() >= 9:
			break
		if not deck.has(k):
			deck.append(k)
	var cards := DB.auto_place(deck.slice(0, 9), "eorin")
	return {"cards": cards, "form": "eorin", "morale": 100, "tac": "균형", "equip": []}


const LITE_VFX := ["firestorm", "thunder", "slash", "shadow", "poison", "illusion", "aura", "heal", "roar", "whirlwind", "charge", "arrowstorm"]
func _alive(view, camp: String) -> Array:
	return view.field.order.filter(func(sq): return sq.alive and sq.camp == camp)


func _wait(view, secs: float) -> void:
	var t0: float = view.clock
	while view.clock < t0 + secs:
		await get_tree().process_frame


func _shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)


## 빠른 고유기 —— 실제 경로(UltFx.play lite → WarPainting.add_ult lite)로 넷씩
func _lite_mode(view, wp, out: String) -> void:
	while view.clock < 7.0:
		await get_tree().process_frame
	var i := 0
	var group := 0
	while i < LITE_VFX.size():
		var mine := _alive(view, "A")
		var foes := _alive(view, "B")
		if mine.is_empty() or foes.is_empty():
			break
		var names := []
		for j in mini(4, mini(mine.size(), foes.size())):
			if i >= LITE_VFX.size():
				break
			var vfx: String = LITE_VFX[i]
			var allies := [mine[(j + 1) % mine.size()].key, mine[(j + 2) % mine.size()].key] if vfx in ["heal", "aura"] else []
			view.field.ult.play(vfx, mine[j].key, [foes[j].key], allies, BattleView.ULT_DELAY, true)
			names.append(vfx)
			i += 1
		if group == 0:
			await _wait(view, 0.3)
			await _shot("%s/skillfx_lite_charge.png" % out)
			await _wait(view, BattleView.ULT_DELAY - 0.3 + 0.35)
		else:
			await _wait(view, BattleView.ULT_DELAY + 0.35)
		await _shot("%s/skillfx_lite_%d.png" % [out, group])
		print("SKILLFX|빠른 고유기 묶음 %d|%s" % [group, ",".join(names)])
		group += 1
		await _wait(view, 2.2)
	print("SKILLFX|빠른 고유기 끝|%d종" % i)


## 등급 차등 —— 시전 부대의 tier 를 잠깐 바꿔 붙인다 (화면 연출만 —— 붙이는 순간 등급을 읽는다)
func _tier_mode(view, wp, out: String) -> void:
	while view.clock < 7.0:
		await get_tree().process_frame
	var tiers := [3, 4, 5, 6, 7, 8]
	var tnames := ["고급", "희귀", "전설", "초월", "불멸", "신화"]
	for what in ["slash", "fire", "minor:pierce", "lite:thunder"]:
		var mine := _alive(view, "A")
		var foes := _alive(view, "B")
		if mine.is_empty() or foes.is_empty():
			break
		var a: Squad = mine[0]
		var keep: int = a.tier
		var labels := []
		for j in mini(6, foes.size()):
			a.tier = tiers[j]
			var d: Squad = foes[j]
			if what.begins_with("lite:"):
				wp.add_ult(what.trim_prefix("lite:"), a.key, [d.key], [], Color("#a8d8ff"), "impact", true)
			elif what.begins_with("minor:"):
				wp._add_skill_fx(what.trim_prefix("minor:"), a, [d.key], wp.MINOR_FX_SC, 0.0, true)
			else:
				wp._add_skill_fx(what, a, [d.key], wp.SKILL_FX_SC, 0.0)
			var lb := Label.new()
			lb.text = tnames[j]
			lb.add_theme_color_override("font_color", Color.WHITE)
			lb.add_theme_color_override("font_outline_color", Color.BLACK)
			lb.add_theme_constant_override("outline_size", 6)
			lb.position = wp.global_position + view.type2.map(d.pos) + Vector2(-16, -46)
			add_child(lb)
			labels.append(lb)
		a.tier = keep
		await _wait(view, float(_args.get("at", "0.3")))
		await _shot("%s/skillfx_tier_%s.png" % [out, what.replace(":", "_")])
		print("SKILLFX|등급 %s" % what)
		for lb in labels:
			lb.queue_free()
		await _wait(view, 2.2)

