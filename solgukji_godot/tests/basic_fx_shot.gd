extends Control
## 기본 행동 연출 캡처 · 점검 (11/11) —— 실행 (창이 뜬다 · 휴대폰 세로 719x1280):
##   godot --path . --resolution 719x1280 --position 495,1500 res://tests/basic_fx_shot.tscn -- --tier=3 [--tierb=3] [--seed=5] [--fx=0 연출 끔(전)] [--out=폴더]
##     [--shots=5,8,11 그 전장 시각(초)에 화면을 찍는다] [--tags=창병,기병,궁병,도적,술사 덱 병종 순서] [--stat=1 연출 수 · 그리기 시간 통계]
## 양쪽 9장을 그 등급에서 병종이 고루 섞이게 뽑아 BattleView(타입2)로 틀고, 지정한 전장 시각마다 화면을 저장한다 (out/fx<켬|끔>_t<등급>_<초>.png).

var _args := {}


func _ready() -> void:
	for s in OS.get_cmdline_user_args():
		var kv := s.trim_prefix("--").split("=", true, 1)
		_args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	PlayLog.enabled = false
	Settings.load_cfg()
	Settings.type2 = true
	Settings.cam_fx = 0       # 카메라가 움직이면 전후 비교가 어긋난다
	Settings.apply()
	theme = UI.theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var view := BattleView.new()
	view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(view)
	await get_tree().process_frame
	Settings.apply_port(view.port)
	Type2View.basic_fx = str(_args.get("fx", "1")) != "0"
	var tier := int(_args.get("tier", "3"))
	var tierb := int(_args.get("tierb", str(tier)))
	var sd := int(_args.get("seed", "5"))
	var tags: Array = str(_args.get("tags", "창병,기병,궁병,도적,술사,창병,기병,궁병,책사")).split(",", false)
	var r := RandomNumberGenerator.new()
	r.seed = sd
	var bt := {"kind": "pvp", "a": _side(tier, tags, r), "b": _side(tierb, tags, r), "seed": sd,
		"title": "연출 점검", "foe": "적군", "inputs": []}
	view.play(bt, false)
	view._set_speed(1.0)
	var out := str(_args.get("out", "user://"))
	if _args.has("gallery"):
		await _gallery(view, out)
		get_tree().quit()
		return
	var shots: Array = []
	for a in str(_args.get("shots", "6,9,12")).split(",", false):
		shots.append(float(a))
	var stat := _args.has("stat")
	var n_frames := 0
	var live_max := 0
	var cost_max := 0
	var draw_us := 0
	var tag := "fx%s_t%d" % ["켬" if Type2View.basic_fx else "끔", tier]
	for at in shots:
		while view.clock < at:
			await get_tree().process_frame
			if stat and view.type2 != null:
				n_frames += 1
				live_max = maxi(live_max, view.type2.bfx._list.size())
				cost_max = maxi(cost_max, view.type2.bfx._cost)
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("%s/%s_%s.png" % [out, tag, str(at).trim_suffix(".0")])
	if stat and view.type2 != null:
		print("STAT|%s|프레임 %d|동시 연출 최대 %d|동시 낱개 최대 %d|상한 %d" % [tag, n_frames, live_max, cost_max, BasicFx.CAP[0]])
	get_tree().quit()


const BasicFx := preload("res://scripts/field/basic_fx.gd")


func _side(t: int, tags: Array, r: RandomNumberGenerator) -> Dictionary:
	var pool := DB.by_tier(t).filter(func(k): return not DB.is_kiin(k) and DB.C[k].kind != "retired")
	pool.shuffle()
	var deck := []
	for tg in tags:
		for k in pool:
			if DB.C[k].tag == tg and not deck.has(k):
				deck.append(k)
				break
	for k in pool:      # 모자라면 아무거나
		if deck.size() >= 9:
			break
		if not deck.has(k):
			deck.append(k)
	var cards := DB.auto_place(deck.slice(0, 9), "eorin")
	return {"cards": cards, "form": "eorin", "morale": 100, "tac": "균형", "equip": []}


# ───────── 갤러리 (--gallery=1) —— 병종 · 연출 종류(행) × 등급 1~8(열) 한 장으로 ─────────
# 전투를 멈추고(배속 0) 빈 땅에 가짜 부대(Stub) 한 쌍을 놓아 BasicFx 를 직접 부른다. 전장 시각은 손으로 흘린다.

class Stub extends RefCounted:
	var key := ""
	var alive := true
	var tag := "창병"
	var tier := 1
	var cls := "melee"
	var pos := Vector2.ZERO
	var fwd := Vector2.RIGHT
	var hw := 24.0
	func hd() -> float:
		return 14.0
	func right() -> Vector2:
		return Vector2(-fwd.y, fwd.x)
	func edge(_dir: Vector2) -> float:
		return 10.0


func _inv(t2: Type2View, s: Vector2) -> Vector2:
	var d := Vector2(-(s.y - t2.size.y * 0.5) / (t2._scale * Type2View.TILT), (s.x - t2.size.x * 0.5) / t2._scale)
	return t2._center + t2._jit + d


func _gallery(view: BattleView, out: String) -> void:
	var t2: Type2View = view.type2
	Type2View.force_lv = 0      # 부하 단계가 연출 세기를 깎지 않게 고정
	view._set_speed(0.0)
	await get_tree().create_timer(0.6).timeout
	t2._want_scale = float(_args.get("zs", "0.5"))      # 실제 휴대폰 전투 배율(0.4~0.7)과 확대 배율(1.0+) 둘 다 보려고 --zs 로 바꾼다
	t2._scale = t2._want_scale
	var c0: Vector2 = t2._center
	var base0: float = view.clock
	var s0: float = t2._want_scale
	t2._focus = {}
	if t2._gmm:
		t2._gmm.visible = false
	t2._mm.visible = false
	view.hud.visible = false
	var rows := [["기병", "contact", 0.3], ["기병", "hit", 0.3], ["창병", "hit", 0.25], ["창병", "contact", 0.25], ["도적", "hit", 0.25],
		["궁병", "volley", 0.45], ["술사", "cast", 0.4]]
	var tiers := [1, 2, 3, 4, 5, 6, 7, 8]
	var cell := Vector2i(104, 104)
	var sc := int(_args.get("up", "3"))
	var board := Image.create(cell.x * tiers.size(), cell.y * rows.size(), false, Image.FORMAT_RGBA8)
	var ult := str(_args.get("ult", "0")) == "1"
	for ri in rows.size():
		for ti in tiers.size():
			var row: Array = rows[ri]
			view.clock = base0      # 전장 시각을 처음으로 되돌리고 한 프레임 기다려 field.clock 이 따라오게 한다 (안 그러면 연출 시작 시각이 어긋난다)
			view.field.clock = base0
			await get_tree().process_frame
			t2.bfx.clear()
			t2._center = c0
			t2._want_center = c0
			t2._scale = s0
			t2._want_scale = s0
			if ult:
				t2.bfx.hold(5.0)
			var ctr := Vector2(t2.size.x * 0.5, t2.size.y * 0.5)
			var a := Stub.new()
			var d := Stub.new()
			a.key = "g%d_%d" % [ri, ti]
			d.key = "h%d_%d" % [ri, ti]
			a.tag = row[0]
			a.tier = tiers[ti]
			d.tier = 3
			a.cls = {"기병": "cav", "창병": "melee", "도적": "melee", "궁병": "ranged", "술사": "caster"}[row[0]]
			var span := 36.0 if row[1] in ["hit", "contact"] else 84.0
			a.pos = _inv(t2, ctr + Vector2(-span * 0.5, 0))
			d.pos = _inv(t2, ctr + Vector2(span * 0.5, 0))
			a.fwd = (d.pos - a.pos).normalized()
			d.fwd = -a.fwd
			var before: int = t2.bfx._list.size()
			match row[1]:
				"hit":
					t2.bfx.melee_hit(a, d, false)
				"contact":
					t2.bfx.contact(a, d, d.pos - a.fwd * 4.0)
				"volley":
					t2.bfx.volley(a, d, false, false)
				"cast":
					t2.bfx.cast(a, d, Color("#c9a2ff"), false)
			var life := 0.5
			if ti == 4:
				print("GAL|%s %s|추가 %d|load_lv %d|ult %s|fn %d|size %s" % [row[0], row[1], t2.bfx._list.size() - before, t2.load_lv, str(t2.bfx.ult_on()), t2.bfx._fn, str(t2.size)])
			if t2.bfx._list.size() > before:
				life = float(t2.bfx._list[before].life)
			if row[1] == "volley" and t2.bfx._list.size() > before:
				var ee: Dictionary = t2.bfx._list[before]
				print("ARROW|tier %d|n %d|fl %.2f|life %.2f|sz %.2f|p %s q %s|map p %s q %s" % [tiers[ti], ee.n, ee.fl, ee.life, ee.sz, str(ee.p), str(ee.q), str(t2.map(ee.p)), str(t2.map(ee.q))])
			var target: float = view.clock + life * float(row[2])
			var t0: float = view.clock
			while view.clock < target:      # 배속 0 이라 view.clock 이 안 간다 —— 손으로 흘린다
				view.clock = minf(target, view.clock + 1.0 / 60.0)
				t2._center = c0
				t2._want_center = c0
				t2._scale = s0
				t2._want_scale = s0
				await get_tree().process_frame
			await RenderingServer.frame_post_draw
			var im := get_viewport().get_texture().get_image()
			im.convert(Image.FORMAT_RGBA8)
			var k := Vector2(im.get_size()) / get_viewport().get_visible_rect().size
			var gc: Vector2 = (t2.get_global_rect().position + ctr) * k
			var reg := im.get_region(Rect2i(int(gc.x) - cell.x / 2, int(gc.y) - cell.y / 2, cell.x, cell.y))
			board.blit_rect(reg, Rect2i(0, 0, cell.x, cell.y), Vector2i(cell.x * ti, cell.y * ri))
			view.clock = t0
			t2.bfx.clear()
	board.resize(board.get_width() * sc, board.get_height() * sc, Image.INTERPOLATE_LANCZOS)
	board.save_png("%s/gallery_zs%s%s.png" % [out, str(_args.get("zs", "0.5")), "_ult" if ult else ""])
