extends Control
## 첫 화면 —— 카드 도감과 전투 연출 두 탭.
## 점검용 인자 (godot ... -- 뒤에):  --tab=1 --level=2 --pick=c180 --shot=경로.png --after=초

var tabs: TabContainer
var flow: HFlowContainer
var detail: VBoxContainer
var big_card: CardView
var detail_text: RichTextLabel
var battle: BattleView
var _cards := {}
var _sel := ""
var _filter := 0
var _filter_btns := []


func _ready() -> void:
	theme = _make_theme()
	tabs = TabContainer.new()
	tabs.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(tabs)
	var g := _build_gallery()
	g.name = "카드 도감"
	tabs.add_child(g)
	battle = BattleView.new()
	battle.name = "전투 연출"
	tabs.add_child(battle)
	_select("c177")
	_handle_args()


# ───────── 도감 ─────────

func _build_gallery() -> Control:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 0)
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(left)

	var bar := HBoxContainer.new()
	var m := MarginContainer.new()
	for side in ["left", "right", "top"]:
		m.add_theme_constant_override("margin_" + side, 12)
	m.add_child(bar)
	left.add_child(m)
	var group := ButtonGroup.new()
	for t in range(0, 9):
		var b := Button.new()
		b.toggle_mode = true
		b.button_group = group
		b.text = "전체" if t == 0 else DB.TIER[t].n
		if t > 0:
			b.add_theme_color_override("font_color", DB.TIER[t].c.lightened(0.15))
		b.button_pressed = t == 0
		b.pressed.connect(func(): _set_filter(t))
		_filter_btns.append(b)
		bar.add_child(b)

	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var pad := MarginContainer.new()
	pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for side in ["left", "right", "top", "bottom"]:
		pad.add_theme_constant_override("margin_" + side, 14)
	sc.add_child(pad)
	flow = HFlowContainer.new()
	flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	flow.add_theme_constant_override("h_separation", 12)
	flow.add_theme_constant_override("v_separation", 12)
	pad.add_child(flow)
	left.add_child(sc)

	var ids: Array = []
	for t in range(8, 0, -1):
		ids += DB.by_tier(t)
	for k in ids:
		var cv := CardView.new().setup(k)
		cv.picked.connect(_select)
		flow.add_child(cv)
		_cards[k] = cv

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(360, 0)
	detail = VBoxContainer.new()
	detail.add_theme_constant_override("separation", 10)
	panel.add_child(detail)
	var cc := CenterContainer.new()
	big_card = CardView.new()
	cc.add_child(big_card)
	detail.add_child(cc)
	detail_text = RichTextLabel.new()
	detail_text.bbcode_enabled = true
	detail_text.fit_content = false
	detail_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	detail_text.add_theme_font_size_override("normal_font_size", 13)
	detail.add_child(detail_text)
	h.add_child(panel)
	return h


func _set_filter(t: int) -> void:
	_filter = t
	_filter_btns[t].button_pressed = true
	for k in _cards:
		_cards[k].visible = t == 0 or DB.C[k].tier == t


func _select(k: String) -> void:
	if _sel != "" and _cards.has(_sel):
		_cards[_sel].selected = false
	_sel = k
	_cards[k].selected = true
	# 큰 카드는 새로 만든다 —— setup 이 신호를 다시 잇지 않도록
	var parent := big_card.get_parent()
	big_card.queue_free()
	big_card = CardView.new().setup(k, Vector2(240, 342))
	parent.add_child(big_card)
	detail_text.clear()
	detail_text.append_text(_detail_bb(k))


func _bb_card(k: String) -> String:
	return "[color=%s]%s[/color]" % [DB.tier_color(k).to_html(false), DB.C[k].name]


func _detail_bb(k: String) -> String:
	var c: Dictionary = DB.C[k]
	var s := "[font_size=18][b]%s[/b][/font_size]  [color=#8D7B5C]%s · %s · %s[/color]\n" % [
		_bb_card(k), DB.TIER[c.tier].n, c.tag, DB.D.FAC[c.fac].full]
	s += "[color=#C6AC7C]공격 %d · 방어 %d · 책략 %d · 책방 %d · 속도 %d[/color]\n" % [c.atk, c["def"], c["int"], c.res, c.spd]
	s += "[color=#C6AC7C]병력 %s · PV %d[/color]\n\n" % [Battle.num(c.tr), c.pv]
	if c.sk:
		s += "[color=#D9A64B]『%s』[/color] 발동 %d%%\n%s\n" % [c.sk.n, roundi(DB.D.RATE.get(str(c.tier), 0) * 100), DB.skill_desc(c)]
		pass
	var pt := DB.passive_text(k)
	if pt != "":
		s += "[color=#8FD4C2]%s[/color]\n\n" % pt.replace("『", "[b]『").replace("』", "』[/b]")
		s += "\n"
	if DB.RECOF.has(k):
		var mats := []
		for x in DB.RECOF[k]:
			mats.append(_bb_card(x))
		s += "[color=#8D7B5C]조합[/color]  " + " + ".join(mats)
		if c.need != "":
			s += " + [color=#d59700]%s[/color]" % c.need
		s += "\n"
	var used := []
	for out in DB.RECOF:
		if DB.RECOF[out].has(k):
			used.append(_bb_card(out))
	if not used.is_empty():
		s += "[color=#8D7B5C]재료로 쓰임[/color]  " + ", ".join(used.slice(0, 8)) + ("…" if used.size() > 8 else "") + "\n"
	var pb := DB.portrait_base(k)
	var want := ("assets/portraits/%s%s" % [DB.person(k), ["", "", "", "", "", "", "_초월", "_불멸", "_신화"][c.tier]]) if c.tier > 2 else "assets/troops/%s" % c.tag
	s += "\n[color=#5d6a88]초상 파일: %s[/color]" % (("%s (쓰는 그림: %s)" % [want, pb.trim_prefix("res://")]) if pb != "" else "%s (없음 · 플레이스홀더)" % want)
	return s


# ───────── 테마 ─────────

func _make_theme() -> Theme:
	var P := DB.PAL
	var th := Theme.new()
	th.default_font = DB.font_body
	th.default_font_size = 14
	th.set_stylebox("panel", "PanelContainer", _flat(P.ink2, P.ink3, 1, 0, 14))
	th.set_stylebox("normal", "Button", _flat(P.ink3, P.ink4))
	th.set_stylebox("hover", "Button", _flat(P.ink4, P.bamboo_dim))
	th.set_stylebox("pressed", "Button", _flat(P.bamboo, P.bamboo))
	th.set_stylebox("hover_pressed", "Button", _flat(P.bamboo, P.gold))
	th.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	th.set_color("font_color", "Button", P.paper)
	th.set_color("font_hover_color", "Button", P.paper)
	th.set_color("font_pressed_color", "Button", Color("#1A1508"))
	th.set_color("font_hover_pressed_color", "Button", Color("#1A1508"))
	th.set_stylebox("normal", "OptionButton", _flat(P.ink3, P.ink4))
	th.set_stylebox("hover", "OptionButton", _flat(P.ink4, P.bamboo_dim))
	th.set_color("font_color", "Label", P.paper)
	th.set_color("default_color", "RichTextLabel", P.paper)
	th.set_stylebox("panel", "TabContainer", _flat(P.ink, P.ink, 0, 0, 0))
	th.set_stylebox("tab_selected", "TabContainer", _flat(P.ink2, P.bamboo, 0, 0, 10))
	th.set_stylebox("tab_unselected", "TabContainer", _flat(P.ink, P.ink, 0, 0, 10))
	th.set_stylebox("tab_hovered", "TabContainer", _flat(P.ink3, P.ink3, 0, 0, 10))
	th.set_color("font_selected_color", "TabContainer", P.bamboo)
	th.set_color("font_unselected_color", "TabContainer", P.bamboo_dim)
	th.set_color("font_hovered_color", "TabContainer", P.paper)
	th.set_font("font", "TabContainer", DB.font_display)
	th.set_font_size("font_size", "TabContainer", 16)
	th.set_stylebox("tabbar_background", "TabContainer", _flat(Color("#0f1424"), P.ink3, 0, 0, 0))
	return th


# ───────── 점검용 인자 ─────────

func _handle_args() -> void:
	var a := {}
	for s in OS.get_cmdline_user_args():
		var kv := s.trim_prefix("--").split("=", true, 1)
		a[kv[0]] = kv[1] if kv.size() > 1 else "1"
	if a.has("pick"):
		_select(a.pick)
	if a.has("filter"):
		_set_filter(int(a.filter))
	if a.has("tab"):
		tabs.current_tab = int(a.tab)
	elif OS.has_feature("testscene"):     # 테스트 APK 는 연습 전투 탭으로 연다
		tabs.current_tab = 1
	if a.has("level"):
		battle.level_pick.selected = int(a.level)
	if a.has("seed"):
		battle.fixed_seed = int(a.seed)
	if a.has("auto"):
		battle.auto_on = true
	if tabs.current_tab == 1:
		await get_tree().process_frame
		battle.new_battle()
		if a.has("speed"):
			battle._set_speed(float(a.speed))
		if a.has("near"):
			# 점검용 가까운 시점 —— 적 선봉 쪽을 낮게 본다
			var w: War3D = battle.field
			w.want_t = Vector3(float(a.get("nx", "0")), 0, 0)
			w.want_dist = float(a.near)
			w.director = false
			w.want_pitch = 0.32
			w.want_yaw = float(a.get("yaw", "0.4"))
			w.cam_rate = 3.0
	if a.has("tap"):
		# 점검용 —— "초:명령" 을 쉼표로. 명령은 돌격·방진·재정비·ult(준비된 첫 장수)
		for item in str(a.tap).split(","):
			var kv: PackedStringArray = item.split(":")
			_tap_later(float(kv[0]), kv[1])
	if a.has("ultlist"):
		# 점검용 —— 이 전투에서 고유기가 언제 누구에게서 터지는지
		for g in battle.groups:
			if g.ult != null:
				print("t=%.1f %s 『%s』 %s · 적 %d · 아군 %d" % [g.t, g.who, g.ult.name, g.ult.vfx, g.foes.size(), g.allies.size()])
		get_tree().quit()
	if a.has("novsync"):
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	if a.has("nofx"):
		battle.field.dbg_nofx = true
	if a.has("nolog"):
		battle.dbg_nolog = true
	if a.has("nosmooth"):
		battle.smooth = false
	if a.has("lumps"):
		# 점검용 —— 병사가 얼마나 몰려서 쓰러지는지 0.25초 단위로 센다
		var buckets := {}
		var prev := -1
		var t0 := Time.get_ticks_msec()
		while not battle.finished and Time.get_ticks_msec() - t0 < int(a.lumps) * 1000:
			await get_tree().process_frame
			var alive := 0
			for sq in battle.field.order:
				for s in sq.soldiers:
					if s.alive or s.die_t > battle.clock:
						alive += 1
			if prev >= 0 and alive < prev:
				var b := int(battle.clock / 0.25)
				buckets[b] = buckets.get(b, 0) + prev - alive
			prev = alive
		var total := 0
		var burst := 0
		var mx := 0
		for b in buckets:
			total += buckets[b]
			mx = maxi(mx, buckets[b])
			if buckets[b] >= 12:
				burst += buckets[b]
		var span := maxf(1.0, battle.clock / 0.25)
		print("전사 %d명 · 0.25초 최대 %d명 · 12명 이상 몰린 비율 %.0f%% · 전사가 있는 구간 %.0f%%" % [
			total, mx, 100.0 * burst / maxi(1, total), 100.0 * buckets.size() / span])
		get_tree().quit()
	if a.has("probe"):
		# 점검용 —— 부대 중심과 병사 무리 중심이 얼마나 벌어지는지 0.5초마다 찍는다
		for i in int(a.probe):
			await get_tree().create_timer(0.5).timeout
			var worst := ""
			var wd := 0.0
			for sq in battle.field.order:
				var c := Vector2.ZERO
				var n := 0
				for s in sq.soldiers:
					if s.alive:
						c += s.pos
						n += 1
				if n == 0 or sq.state == "gone":
					continue
				var d: float = (c / n).distance_to(sq.pos)
				if d > wd:
					wd = d
					worst = "%s %s %s contact=%s" % [sq.row.name, sq.state, sq.cls, sq.contact]
			var pf: Dictionary = battle.field.prof
			var fr: int = maxi(1, pf.get("_frames", 1))
			var parts := []
			var sum := 0.0
			for k in pf:
				if k != "_frames":
					parts.append("%s %.2f" % [k, pf[k] / 1000.0 / fr])
					sum += pf[k] / 1000.0 / fr
			print("t=%.1f fps=%d 스크립트 %.1fms (잰 구간 합 %.2f: %s) 그리기호출 %d 병사 %d" % [battle.clock, Engine.get_frames_per_second(),
				Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0, sum, ", ".join(parts),
				Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), battle.field.entries.size()])
			battle.field.prof.clear()
		get_tree().quit()
	if a.has("shot"):
		await get_tree().create_timer(float(a.get("after", "1.5"))).timeout
		# --frames=N --every=초 를 주면 연속 장면을 shot_0.png, shot_1.png … 로 남긴다
		var n := int(a.get("frames", "1"))
		for i in n:
			if i > 0:
				await get_tree().create_timer(float(a.get("every", "0.4"))).timeout
			await RenderingServer.frame_post_draw
			var path: String = a.shot if n == 1 else a.shot.replace(".png", "_%d.png" % i)
			get_viewport().get_texture().get_image().save_png(path)
		get_tree().quit()


func _tap_later(sec: float, what: String) -> void:
	while battle.clock < sec:
		await get_tree().process_frame
	if what == "ult":
		for sq in battle.field.order:
			if sq.camp == "A" and battle.ult_ready(sq.key):
				battle.request_ult(sq.key)
				print("탭 %.1f초: %s 고유기 → 적용된 입력 %d개" % [battle.clock, sq.row.name, battle.res.applied.size()])
				return
		print("탭 %.1f초: 준비된 고유기 없음" % battle.clock)
	else:
		var p := battle.cmd_points()
		battle.request_cmd(what)
		print("탭 %.1f초: 군령 %s (포인트 %.0f) → 적용된 입력 %d개" % [battle.clock, what, p, battle.res.applied.size()])


func _flat(bg: Color, border: Color, bw := 1, rad := 6, pad := 8) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(bw)
	sb.set_corner_radius_all(rad)
	sb.set_content_margin_all(pad)
	return sb
