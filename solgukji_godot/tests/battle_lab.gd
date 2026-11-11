extends Control
## 전투 실험실 (11/5 사용자: 전투 테스트용 툴) —— PC 에서 양쪽 덱을 골라 관전하거나 여러 판을 돌려 본다.
## 실행: tools/전투실험실.bat  (또는 godot --path solgukji_godot res://tests/battle_lab.tscn)
##   왼쪽 두 열 = 아군(A) · 적군(B) 덱 —— 카드 목록을 두 번 누르면 덱에 넣고, 덱에서 두 번 누르면 뺀다 (9장까지)
##   진형 · 작전 · 사기 · 장비(봇처럼 끼우기) 를 고른다. '무작위' 는 그 등급 9장
##   가운데 = 시드 · 판 수 · 관전 / 시뮬 / 양쪽 바꾸기 · 엔진 수치(점검용 static) · 결과
##   오른쪽 = 실제 게임 전투 화면 (BattleView) —— 직접 지휘 버튼으로 고유기 · 군령도 써 볼 수 있다

const FORMS := ["eorin", "hagik", "bongsi", "anwol", "bangwon", "anhaeng", "chuhaeng", "jangsa"]
const KNOBS := [      # [이름, 객체, 속성, 최소, 최대, 칸]
	["책략 배율 int_mul", "RtBattle", "int_mul", 0.1, 3.0, 0.05],
	["근접 배율 near_mul", "RtBattle", "near_mul", 0.5, 3.0, 0.05],
	["원거리 배율 far_mul", "RtBattle", "far_mul", 0.3, 2.0, 0.05],
	["기병 돌격 cav_charge", "RtBattle", "cav_charge", 0.5, 3.0, 0.05],
	["궁병 사거리 bow_range", "RtBattle", "bow_range", 80.0, 500.0, 5.0],
	["책략 사거리 cast_range", "RtBattle", "cast_range", 80.0, 500.0, 5.0],
	["신화 능력치 myth_power", "Battle", "myth_power", 0.8, 2.0, 0.05],
	["책략 병력 피해 int_troop", "Battle", "int_troop", 0.5, 3.0, 0.05],
]

var side := {}           # "A" / "B" -> {deck: Array, list: ItemList, deck_list: ItemList, form, tac, morale, equip, tier, tag, foe}
var view: BattleView
var _style_btn: OptionButton
var out: RichTextLabel
var seed_box: SpinBox
var seed_rand: CheckBox
var games_box: SpinBox
var _busy := false
var _knob_def := {}


func _ready() -> void:
	var win := get_window()
	win.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	win.size = Vector2i(1700, 1000)
	win.move_to_center()
	theme = UI.theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color("#0d111b")
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var root := HBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.offset_left = 8
	root.offset_top = 8
	root.offset_right = -8
	root.offset_bottom = -8
	root.add_theme_constant_override("separation", 8)
	add_child(root)
	root.add_child(_side_col("A", "아군 (A)"))
	root.add_child(_side_col("B", "적군 (B)"))
	root.add_child(_mid_col())
	var vp := PanelContainer.new()
	vp.custom_minimum_size = Vector2(430, 0)
	root.add_child(vp)
	view = BattleView.new()
	view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vp.add_child(view)
	view.ended.connect(func(res, _inp): _report([res], "관전 결과"))
	await get_tree().process_frame
	Settings.load_cfg()      # 11/6 사용자: 실험실에서 전투 설정(화풍 · 품질)을 바꿀 수 없다 —— 게임 설정을 읽고 가운데 열에서 바꾼다
	# 11/11 사용자: 실험실도 기본 타입2 —— 저장된 설정이 무엇이든 시작은 타입2 (저장하지 않는다. 가운데 열에서 바꾸면 그때 저장)
	Settings.type2 = true
	Settings.sumuk = false
	Settings.dots = false
	if _style_btn != null:
		_style_btn.selected = 2
	view.apply_style()
	Settings.apply()
	Settings.apply_port(view.port)
	_random("A", 7)
	_random("B", 7)
	_dev_args()


## 점검용 —— --gauto=watch|sim  --gshot=경로 --after=초
func _dev_args() -> void:
	var a := {}
	for x in OS.get_cmdline_user_args():
		var kv := x.trim_prefix("--").split("=", true, 1)
		a[kv[0]] = kv[1] if kv.size() > 1 else "1"
	if a.has("games"): games_box.value = int(a.games)
	match a.get("gauto", ""):
		"watch": _watch()
		"sim": _sim()
	if a.has("gshot"):
		await get_tree().create_timer(float(a.get("after", "3"))).timeout
		get_viewport().get_texture().get_image().save_png(a.gshot)
		get_tree().quit()


# ───────── 덱 열 ─────────

func _side_col(cp: String, title: String) -> Control:
	var s := {"deck": [], "form": "eorin", "tac": "균형", "morale": 100, "equip": true, "tier": 0, "tag": "", "foe": cp == "B"}
	side[cp] = s
	var v := VBoxContainer.new()
	v.custom_minimum_size = Vector2(290, 0)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 4)
	var h := Label.new()
	h.text = title
	h.add_theme_color_override("font_color", Color("#d8b56a") if cp == "A" else Color("#e07a6a"))
	h.add_theme_font_size_override("font_size", 18)
	v.add_child(h)
	# 거르기
	var fr := HBoxContainer.new()
	var tier := OptionButton.new()
	tier.add_item("모든 등급", 0)
	tier.add_item("기인", 99)      # 11/11 사용자: 실험실에 기인이 안 보인다 —— 기인은 등급이 전설로 같아 목록에 섞여 있었다. 따로 거르기
	for t in range(8, 0, -1):
		if DB.TIER.has(t):
			tier.add_item(DB.TIER[t].n, t)
	tier.item_selected.connect(func(i): s.tier = tier.get_item_id(i); _fill(cp))
	fr.add_child(tier)
	var tag := OptionButton.new()
	tag.add_item("모든 병종")
	for tg in DB.D.TAGORDER:
		tag.add_item(tg)
	tag.item_selected.connect(func(i): s.tag = "" if i == 0 else tag.get_item_text(i); _fill(cp))
	fr.add_child(tag)
	var foe := CheckBox.new()
	foe.text = "적 전용"
	foe.button_pressed = s.foe
	foe.toggled.connect(func(on): s.foe = on; _fill(cp))
	fr.add_child(foe)
	v.add_child(fr)
	var search := LineEdit.new()
	search.placeholder_text = "이름 찾기"
	search.text_changed.connect(func(_t): _fill(cp))
	s["search"] = search
	v.add_child(search)
	var list := ItemList.new()
	list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	list.item_activated.connect(func(i): _add(cp, str(list.get_item_metadata(i))))
	s["list"] = list
	v.add_child(list)
	var dl := Label.new()
	dl.text = "덱 (두 번 누르면 뺀다)"
	v.add_child(dl)
	var deck := ItemList.new()
	deck.custom_minimum_size = Vector2(0, 230)
	deck.item_activated.connect(func(i): s.deck.remove_at(i); _fill_deck(cp))
	s["deck_list"] = deck
	v.add_child(deck)
	var sum := Label.new()
	sum.add_theme_font_size_override("font_size", 12)
	s["sum"] = sum
	v.add_child(sum)
	# 진형 · 작전 · 사기 · 장비
	var r1 := HBoxContainer.new()
	var fo := OptionButton.new()
	for f in FORMS:
		fo.add_item(DB.FORM[f].n if DB.FORM.has(f) else f)
	fo.item_selected.connect(func(i): s.form = FORMS[i])
	s["form_btn"] = fo
	r1.add_child(fo)
	var ta := OptionButton.new()
	for t in Run.TACS:
		ta.add_item(t)
	ta.item_selected.connect(func(i): s.tac = ta.get_item_text(i))
	s["tac_btn"] = ta
	r1.add_child(ta)
	v.add_child(r1)
	var r2 := HBoxContainer.new()
	var ml := Label.new()
	ml.text = "사기"
	r2.add_child(ml)
	var mo := SpinBox.new()
	mo.min_value = 10
	mo.max_value = 150
	mo.value = 100
	mo.value_changed.connect(func(x): s.morale = int(x))
	r2.add_child(mo)
	var eq := CheckBox.new()
	eq.text = "장비"
	eq.button_pressed = true
	eq.toggled.connect(func(on): s.equip = on)
	r2.add_child(eq)
	v.add_child(r2)
	var r3 := HFlowContainer.new()
	for t in [8, 7, 6, 5, 4, 3]:
		var b := Button.new()
		b.text = "무작위 " + DB.TIER[t].n
		b.add_theme_font_size_override("font_size", 11)
		b.pressed.connect(func(): _random(cp, t))
		r3.add_child(b)
	var bk := Button.new()
	bk.text = "무작위 기인"
	bk.add_theme_font_size_override("font_size", 11)
	bk.pressed.connect(func(): _random_kiin(cp))
	r3.add_child(bk)
	v.add_child(r3)
	var r4 := HBoxContainer.new()
	var rec := Button.new()
	rec.text = "덱에 맞는 작전"
	rec.pressed.connect(func(): _set_tac(cp, Run.recommend_tac(s.deck)[0]))
	r4.add_child(rec)
	var clr := Button.new()
	clr.text = "비우기"
	clr.pressed.connect(func(): s.deck.clear(); _fill_deck(cp))
	r4.add_child(clr)
	v.add_child(r4)
	_fill.call_deferred(cp)
	return v


func _cards(cp: String) -> Array:
	var s: Dictionary = side[cp]
	var q: String = s.search.text.strip_edges()
	var ks := DB.C.keys().filter(func(k):
		var c: Dictionary = DB.C[k]
		if c.kind == "retired": return false
		if DB.is_foe(k) and not s.foe: return false
		if s.tier == 99:
			if c.kind != "kiin": return false
		elif s.tier > 0 and (c.tier != s.tier or c.kind == "kiin"): return false
		if s.tag != "" and c.tag != s.tag: return false
		if q != "" and not c.name.contains(q): return false
		return true)
	ks.sort_custom(func(a, b):
		var ka: bool = DB.C[a].kind == "kiin"
		var kb: bool = DB.C[b].kind == "kiin"
		if ka != kb: return ka      # 기인은 맨 위
		if DB.C[a].tier != DB.C[b].tier: return DB.C[a].tier > DB.C[b].tier
		return DB.C[a].name < DB.C[b].name)
	return ks


func _label(k: String) -> String:
	var c: Dictionary = DB.C[k]
	return "[%s] %s · %s%s" % [DB.tier_name(k), c.name, c.tag, "  (적)" if DB.is_foe(k) else ""]


func _fill(cp: String) -> void:
	var list: ItemList = side[cp].list
	list.clear()
	for k in _cards(cp):
		var i := list.add_item(_label(k))
		list.set_item_metadata(i, k)
		list.set_item_custom_fg_color(i, DB.tier_color(k))
	_fill_deck(cp)


func _fill_deck(cp: String) -> void:
	var s: Dictionary = side[cp]
	var dl: ItemList = s.deck_list
	dl.clear()
	var tr := 0
	var pv := 0
	for k in s.deck:
		var i := dl.add_item(_label(k))
		dl.set_item_custom_fg_color(i, DB.tier_color(k))
		tr += int(DB.C[k].tr)
		pv += int(DB.C[k].pv)
	s.sum.text = "%d장 · 병력 %s · 전력 %d · 추천 작전 %s" % [s.deck.size(), _num(tr), pv, Run.recommend_tac(s.deck)[0]]


func _add(cp: String, k: String) -> void:
	var s: Dictionary = side[cp]
	if s.deck.size() >= 9:
		_say("덱은 9장까지")
		return
	s.deck.append(k)
	_fill_deck(cp)


## 11/11 기인 9장 무작위 (기인 카드가 9장보다 적으면 그만큼)
func _random_kiin(cp: String) -> void:
	var s: Dictionary = side[cp]
	var pool := DB.C.keys().filter(func(k): return DB.is_kiin(k))
	pool.shuffle()
	s.deck = pool.slice(0, 9)
	_fill_deck(cp)
	_set_tac(cp, Run.recommend_tac(s.deck)[0])


func _random(cp: String, t: int) -> void:
	var s: Dictionary = side[cp]
	var pool := DB.by_tier(t).filter(func(k): return not DB.is_kiin(k) and DB.C[k].kind != "retired")
	pool.shuffle()
	s.deck = pool.slice(0, 9)
	_fill_deck(cp)
	_set_tac(cp, Run.recommend_tac(s.deck)[0])


func _set_tac(cp: String, t: String) -> void:
	side[cp].tac = t
	var b: OptionButton = side[cp].tac_btn
	for i in b.item_count:
		if b.get_item_text(i) == t:
			b.select(i)


# ───────── 가운데 ─────────

func _mid_col() -> Control:
	var v := VBoxContainer.new()
	v.custom_minimum_size = Vector2(420, 0)
	v.add_theme_constant_override("separation", 6)
	var h := Label.new()
	h.text = "전투 실험실"
	h.add_theme_color_override("font_color", Color("#d8b56a"))
	h.add_theme_font_size_override("font_size", 20)
	v.add_child(h)
	var r := HBoxContainer.new()
	var sl := Label.new()
	sl.text = "시드"
	r.add_child(sl)
	seed_box = SpinBox.new()
	seed_box.max_value = 999999
	seed_box.value = 1
	r.add_child(seed_box)
	seed_rand = CheckBox.new()
	seed_rand.text = "관전마다 새 시드"
	seed_rand.button_pressed = true
	r.add_child(seed_rand)
	v.add_child(r)
	# 전장 화풍 · 품질 (게임 설정과 같은 파일에 저장 —— 3D ↔ 2D 는 다음 관전부터)
	var rs := HBoxContainer.new()
	var stl := Label.new()
	stl.text = "화풍"
	rs.add_child(stl)
	var style := OptionButton.new()
	_style_btn = style
	for nm in ["기본 3D", "수묵", "타입2 (삼국지11)", "점묘 (2D)"]:
		style.add_item(nm)
	style.selected = 2 if Settings.type2 else (1 if Settings.sumuk else (3 if Settings.dots else 0))
	style.item_selected.connect(func(i):
		Settings.sumuk = i == 1
		Settings.type2 = i == 2
		Settings.dots = i == 3
		Settings.save_cfg()
		view.apply_style())
	rs.add_child(style)
	var ql := Label.new()
	ql.text = "  품질"
	rs.add_child(ql)
	var qual := OptionButton.new()
	for nm in Settings.QUALITY_N:
		qual.add_item(nm)
	qual.selected = clampi(Settings.quality, 0, 2)
	qual.item_selected.connect(func(i):
		Settings.quality = i
		Settings.apply()
		Settings.apply_port(view.port)
		Settings.save_cfg())
	rs.add_child(qual)
	var hint := Label.new()
	hint.text = "  (3D↔2D 는 다음 관전부터)"
	hint.add_theme_color_override("font_color", Color("#8a8f9a"))
	rs.add_child(hint)
	v.add_child(rs)
	var r2 := HBoxContainer.new()
	var watch := Button.new()
	watch.text = "관전 ▶"
	watch.pressed.connect(_watch)
	r2.add_child(watch)
	var gl := Label.new()
	gl.text = "  판 수"
	r2.add_child(gl)
	games_box = SpinBox.new()
	games_box.min_value = 1
	games_box.max_value = 1000
	games_box.value = 50
	r2.add_child(games_box)
	var sim := Button.new()
	sim.text = "시뮬 돌리기"
	sim.pressed.connect(_sim)
	r2.add_child(sim)
	var sw := Button.new()
	sw.text = "A ↔ B"
	sw.pressed.connect(_swap)
	r2.add_child(sw)
	v.add_child(r2)
	# 엔진 수치
	var kp := VBoxContainer.new()
	var kl := Label.new()
	kl.text = "엔진 수치 (이 창에서만 —— 게임에는 그대로)"
	kl.add_theme_font_size_override("font_size", 12)
	kl.add_theme_color_override("font_color", Color("#8b93a6"))
	kp.add_child(kl)
	var grid := GridContainer.new()
	grid.columns = 2
	for kn in KNOBS:
		var cur := float(_kget(kn[2]))
		_knob_def[kn[2]] = cur
		var l := Label.new()
		l.text = kn[0]
		l.add_theme_font_size_override("font_size", 12)
		grid.add_child(l)
		var sb := SpinBox.new()
		sb.min_value = kn[3]
		sb.max_value = kn[4]
		sb.step = kn[5]
		sb.value = cur
		sb.value_changed.connect(func(x): _kset(kn[2], x))
		grid.add_child(sb)
	kp.add_child(grid)
	var tg := HBoxContainer.new()
	for t in [["병종 역할", "tag_roles"], ["고유기", "ults_enabled"], ["특기", "passives_enabled"], ["위세", "aura_enabled"]]:
		var c := CheckBox.new()
		c.text = t[0]
		c.button_pressed = bool(_kget(t[1]))
		c.add_theme_font_size_override("font_size", 12)
		c.toggled.connect(func(on): _kset(t[1], on))
		tg.add_child(c)
	kp.add_child(tg)
	v.add_child(kp)
	out = RichTextLabel.new()
	out.bbcode_enabled = true
	out.selection_enabled = true
	out.size_flags_vertical = Control.SIZE_EXPAND_FILL
	out.add_theme_font_size_override("normal_font_size", 13)
	out.add_theme_font_size_override("bold_font_size", 13)
	v.add_child(out)
	var cp := Button.new()
	cp.text = "결과 복사"
	cp.pressed.connect(func(): DisplayServer.clipboard_set(out.get_parsed_text()); _say("복사했다"))
	v.add_child(cp)
	return v


## 엔진 static 수치 읽기 · 쓰기 (클래스의 get/set 은 못 부른다)
func _kget(k: String):
	match k:
		"int_mul": return RtBattle.int_mul
		"near_mul": return RtBattle.near_mul
		"far_mul": return RtBattle.far_mul
		"cav_charge": return RtBattle.cav_charge
		"bow_range": return RtBattle.bow_range
		"cast_range": return RtBattle.cast_range
		"myth_power": return Battle.myth_power
		"int_troop": return Battle.int_troop
		"tag_roles": return Battle.tag_roles
		"ults_enabled": return Battle.ults_enabled
		"passives_enabled": return Battle.passives_enabled
		"aura_enabled": return Battle.aura_enabled
	return 0.0


func _kset(k: String, v) -> void:
	match k:
		"int_mul": RtBattle.int_mul = v
		"near_mul": RtBattle.near_mul = v
		"far_mul": RtBattle.far_mul = v
		"cav_charge": RtBattle.cav_charge = v
		"bow_range": RtBattle.bow_range = v
		"cast_range": RtBattle.cast_range = v
		"myth_power": Battle.myth_power = v
		"int_troop": Battle.int_troop = v
		"tag_roles": Battle.tag_roles = v
		"ults_enabled": Battle.ults_enabled = v
		"passives_enabled": Battle.passives_enabled = v
		"aura_enabled": Battle.aura_enabled = v


func _say(t: String) -> void:
	out.append_text("\n[color=#8b93a6]%s[/color]" % t)


func _num(n) -> String:
	var s := str(int(n))
	var o := ""
	while s.length() > 3:
		o = "," + s.substr(s.length() - 3) + o
		s = s.substr(0, s.length() - 3)
	return s + o


func _side_dict(cp: String, r: RandomNumberGenerator) -> Dictionary:
	var s: Dictionary = side[cp]
	var cards := DB.auto_place(s.deck, s.form)
	return {"cards": cards, "form": s.form, "morale": s.morale, "tac": s.tac,
		"equip": Run.bot_equip(cards, _p_idx(s.deck), r) if s.equip else []}


## 장비 등급 —— 덱의 가장 높은 등급에 맞는 시점(페이즈 번호)의 보급표로 끼운다
func _p_idx(deck: Array) -> int:
	var t := 1
	for k in deck: t = maxi(t, int(DB.C[k].tier))
	return {8: 18, 7: 17, 6: 14, 5: 10, 4: 6, 3: 3}.get(t, 1)


func _bt(sd: int) -> Dictionary:
	var r := RandomNumberGenerator.new()
	r.seed = sd
	return {"kind": "pvp", "a": _side_dict("A", r), "b": _side_dict("B", r), "seed": sd,
		"title": "실험 · 시드 %d" % sd, "foe": "적군", "inputs": []}


func _ok() -> bool:
	if side.A.deck.is_empty() or side.B.deck.is_empty():
		_say("양쪽 덱에 한 장 이상 넣어야 한다")
		return false
	return true


func _watch() -> void:
	if not _ok(): return
	if seed_rand.button_pressed:
		seed_box.value = randi() % 1000000
	var bt := _bt(int(seed_box.value))
	out.text = "관전 중 —— 시드 %d" % int(seed_box.value)
	view.play(bt, false)


func _sim() -> void:
	if _busy or not _ok(): return
	_busy = true
	var n := int(games_box.value)
	var s0 := int(seed_box.value)
	var res := []
	var t0 := Time.get_ticks_msec()
	for i in n:
		var bt := _bt(s0 + i)
		res.append(Run.simulate(bt, [], Run.policy_for(bt)))
		if i % 5 == 4:
			out.text = "시뮬 %d / %d …" % [i + 1, n]
			await get_tree().process_frame
	_report(res, "시뮬 %d판 (시드 %d~%d, %.1f초)" % [n, s0, s0 + n - 1, (Time.get_ticks_msec() - t0) / 1000.0])
	_busy = false


func _swap() -> void:
	var a: Dictionary = side.A
	var b: Dictionary = side.B
	for key in ["deck", "form", "tac", "morale", "equip"]:
		var x = a[key]
		a[key] = b[key]
		b[key] = x
	for cp in ["A", "B"]:
		_fill_deck(cp)
		_set_tac(cp, side[cp].tac)
		side[cp].form_btn.select(FORMS.find(side[cp].form))


func _report(rs: Array, title: String) -> void:
	var n := rs.size()
	var w := 0
	var d := 0
	var turns := 0.0
	var left := {"A": 0.0, "B": 0.0}
	var units := {}        # 키 "A3" -> 모음
	for r in rs:
		if r.win: w += 1
		elif r.draw: d += 1
		turns += float(r.turns)
		var tot := {"A": [0.0, 0.0], "B": [0.0, 0.0]}
		for u in r.roster:
			tot[u.camp][0] += maxf(0.0, float(u.left))
			tot[u.camp][1] += float(u.max)
			var e: Dictionary = units.get(u.key, {"name": u.name, "tier": u.tier, "tag": u.tag, "camp": u.camp, "line": u.line,
				"dmg": 0.0, "taken": 0.0, "heal": 0.0, "kills": 0.0, "mdmg": 0.0, "alive": 0.0})
			e.dmg += u.dmg; e.taken += u.get("taken", 0); e.heal += u.heal; e.kills += u.kills; e.mdmg += u.mdmg
			e.alive += 1.0 if u.alive else 0.0
			units[u.key] = e
		for cp in ["A", "B"]:
			left[cp] += tot[cp][0] / maxf(1.0, tot[cp][1])
	var t := "[b]%s[/b]\n" % title
	t += "아군 승률 [b]%d%%[/b] (%d승 %d무 %d패) · 평균 길이 %.1f턴\n" % [roundi(100.0 * w / n), w, d, n - w - d, turns / n]
	t += "평균 잔존 병력 —— 아군 %d%% · 적군 %d%%\n\n" % [roundi(100 * left.A / n), roundi(100 * left.B / n)]
	for cp in ["A", "B"]:
		var ks := units.keys().filter(func(k): return units[k].camp == cp)
		var sum_dmg := 0.0
		for k in ks: sum_dmg += units[k].dmg
		ks.sort_custom(func(a, b): return units[a].dmg > units[b].dmg)
		t += "[color=%s][b]%s[/b][/color]\n" % ["#d8b56a" if cp == "A" else "#e07a6a", "아군" if cp == "A" else "적군"]
		t += "[table=8][cell][b]장수[/b][/cell][cell][b]병종[/b][/cell][cell][b]자리[/b][/cell][cell][b]준 피해[/b][/cell][cell][b]몫[/b][/cell][cell][b]받은 피해[/b][/cell][cell][b]격파[/b][/cell][cell][b]생존[/b][/cell]"
		for k in ks:
			var e: Dictionary = units[k]
			t += "[cell][color=#%s]%s[/color]  [/cell][cell]%s  [/cell][cell]%s  [/cell][cell]%s  [/cell][cell]%d%%  [/cell][cell]%s  [/cell][cell]%.1f  [/cell][cell]%d%%[/cell]" % [
				DB.TIER[int(e.tier)].c.to_html(false), e.name, e.tag, e.line, _num(e.dmg / n), roundi(100 * e.dmg / maxf(1, sum_dmg)),
				_num(e.taken / n), e.kills / n, roundi(100 * e.alive / n)]
		t += "[/table]\n\n"
	out.text = t
