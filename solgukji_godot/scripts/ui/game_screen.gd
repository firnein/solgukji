class_name GameScreen
extends Control
## 게임 화면 —— 원본 HTML 의 화면들(징집·조합·편성·전장·계보·순위)을 가로 화면에 옮겼다.
## 위: 날짜·페이즈 진행·전력 · 왼쪽: 탭 · 가운데: 페이지(스크롤) · 오른쪽에서 열리는 시트 · 전투는 전체 화면.
## 상태는 Run 이 들고, 바뀔 때마다 render() 로 지금 페이지만 다시 그린다. 행동마다 저장한다.
## 행동은 모두 act(명령, 인자) 로 한다 —— 혼자 하면 Run 에 바로, 온라인(online)이면 서버에도 보낸다.
##
## 점검용 인자 (godot ... -- 뒤에):  --gnew=시드 --gplay=페이즈수 --gpage=deploy --gshot=경로.png --after=초 --gsheet=card:c39
## (예전 도감·전투 연출 화면은 --tab=… 을 주면 열린다 —— scenes/main.tscn)

const PAGES := [["draw", "징집"], ["forge", "조합"], ["deploy", "편성"], ["war", "전투"], ["line", "계보"], ["rank", "순위"]]

var run: Run
var page := "draw"
var forge_tag := ""
var _scroll_keep := {}       # 페이지 -> 스크롤 위치

var _head: HBoxContainer
var _day_lbl: Label
var _phase_bar: Control
var _stat_lbls := {}
var _nav := {}
var _scroll: ScrollContainer
var _body: MarginContainer
var _sheet_mask: ColorRect
var _sheet: PanelContainer
var _sheet_body: VBoxContainer
var _sheet_title: Label
var _sheet_scroll: ScrollContainer
var _toast_box: VBoxContainer
var _battle_layer: Control
var _battle: BattleView
var _battle_done: Button
var _battle_res = null
var _title: Control
var deploy: DeployPage
var online: Online = null     # 온라인 대전 중이면 있다 (scripts/ui/online.gd)


func _ready() -> void:
	Settings.load_cfg()
	var dev := OS.get_cmdline_user_args()
	for a in dev:
		if a.begins_with("--tab"):
			get_tree().change_scene_to_file.call_deferred("res://scenes/main.tscn")
			return
	theme = UI.theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = DB.PAL.ink
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var root := UI.vbox(0)
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	root.add_child(_build_head())
	var mid := UI.hbox(0)
	mid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(mid)
	mid.add_child(_build_nav())
	_scroll = ScrollContainer.new()
	_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	mid.add_child(_scroll)
	_body = MarginContainer.new()
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for s in ["left", "right", "top", "bottom"]:
		_body.add_theme_constant_override("margin_" + s, 18)
	_scroll.add_child(_body)
	deploy = DeployPage.new()
	deploy.gs = self
	_build_sheet()
	_build_battle()
	_toast_box = UI.vbox(6)
	_toast_box.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_toast_box.position.y = 64
	_toast_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast_box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	add_child(_toast_box)
	_build_title()
	_dev_args()


## 휴대폰 —— 뒤로 가기는 시트를 닫고, 앱이 가려지거나 꺼질 때 저장한다
func _notification(what: int) -> void:
	match what:
		NOTIFICATION_WM_GO_BACK_REQUEST:
			if _sheet != null and _sheet.visible:
				close_sheet()
			elif _battle_layer != null and _battle_layer.visible:
				pass                    # 전투 중에는 무시 —— 결과로 넘기려면 오른쪽 '결과로'
			elif _title != null and not _title.visible:
				if online != null:
					online.leave()
				elif run != null:
					run.save()
				_title.queue_free()
				_build_title()
			else:
				get_tree().quit()
		NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_WM_CLOSE_REQUEST, NOTIFICATION_APPLICATION_FOCUS_OUT:
			if run != null and online == null:
				run.save()


# ───────── 뼈대 ─────────

func _build_head() -> Control:
	var bar := PanelContainer.new()
	bar.add_theme_stylebox_override("panel", UI.flat(Color("#0f1424"), DB.PAL.ink3, 0, 0, 8))
	bar.custom_minimum_size = Vector2(0, 58)
	_head = UI.hbox(18)
	bar.add_child(_head)
	var logo := UI.lbl("솔국지", 22, DB.PAL.bamboo, true)
	_head.add_child(logo)
	_day_lbl = UI.lbl("", 16, DB.PAL.paper, true)
	_day_lbl.custom_minimum_size = Vector2(150, 0)
	_head.add_child(_day_lbl)
	_phase_bar = PhaseBar.new()
	_phase_bar.custom_minimum_size = Vector2(250, 0)
	_phase_bar.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_head.add_child(_phase_bar)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_head.add_child(sp)
	for key in ["power", "pv", "rank", "strike"]:
		var v := UI.vbox(0)
		var a := UI.lbl("", 17, DB.PAL.paper, true)
		a.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		var b := UI.lbl({"power": "병력", "pv": "PV", "rank": "순위", "strike": "경고"}[key], 11, DB.PAL.bamboo_dim)
		b.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(a)
		v.add_child(b)
		v.custom_minimum_size = Vector2(70, 0)
		_stat_lbls[key] = a
		_head.add_child(v)
	_head.add_child(UI.btn("☰", _menu, "ghost", 44))
	return bar


func _build_nav() -> Control:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UI.flat(Color("#0f1424"), DB.PAL.ink3, 0, 0, 6))
	p.custom_minimum_size = Vector2(108, 0)
	var v := UI.vbox(6)
	p.add_child(v)
	for pg in PAGES:
		var b := UI.btn(pg[1], func(): go(pg[0]), "", 62)
		b.add_theme_font_override("font", DB.font_display)
		b.add_theme_font_size_override("font_size", 18)
		b.toggle_mode = true
		_nav[pg[0]] = b
		v.add_child(b)
	return p


func _build_sheet() -> void:
	_sheet_mask = ColorRect.new()
	_sheet_mask.color = Color(0, 0, 0, 0.55)
	_sheet_mask.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_sheet_mask.visible = false
	_sheet_mask.gui_input.connect(func(e):
		if e is InputEventMouseButton and e.pressed:
			close_sheet())
	add_child(_sheet_mask)
	_sheet = PanelContainer.new()
	_sheet.add_theme_stylebox_override("panel", UI.flat(DB.PAL.ink2, DB.PAL.bamboo_dim, 1, 0, 14))
	_sheet.set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)
	_sheet.offset_left = -600
	_sheet.visible = false
	add_child(_sheet)
	var v := UI.vbox(10)
	_sheet.add_child(v)
	var top := UI.hbox()
	_sheet_title = UI.lbl("", 20, DB.PAL.paper, true)
	_sheet_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_sheet_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	top.add_child(_sheet_title)
	top.add_child(UI.btn("닫기", close_sheet, "ghost", 44))
	v.add_child(top)
	_sheet_scroll = ScrollContainer.new()
	_sheet_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_sheet_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(_sheet_scroll)
	_sheet_body = UI.vbox(10)
	_sheet_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_sheet_scroll.add_child(_sheet_body)


func _build_battle() -> void:
	_battle_layer = Control.new()
	_battle_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_battle_layer.visible = false
	add_child(_battle_layer)
	_battle = BattleView.new()
	_battle.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_battle_layer.add_child(_battle)
	_battle.ended.connect(_on_battle_ended)
	_battle.inputs_changed.connect(func(inputs):
		if run.battle != null and online == null:
			run.battle.inputs = inputs.duplicate(true)
			run.save())
	_battle_done = UI.btn("결과 정리  ▶", _on_battle_close, "pri", 60)
	_battle_done.add_theme_font_override("font", DB.font_display)
	_battle_done.add_theme_font_size_override("font_size", 20)
	_battle_done.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_battle_done.custom_minimum_size = Vector2(260, 60)
	_battle_done.offset_left = -130 - 165
	_battle_done.offset_right = 130 - 165
	_battle_done.offset_top = -170
	_battle_done.offset_bottom = -110
	_battle_done.visible = false
	_battle_layer.add_child(_battle_done)


func _build_title() -> void:
	_title = ColorRect.new()
	_title.color = DB.PAL.ink
	_title.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_title)
	var c := CenterContainer.new()
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_title.add_child(c)
	var v := UI.vbox(14)
	v.custom_minimum_size = Vector2(380, 0)
	c.add_child(v)
	var t := UI.lbl("솔국지", 72, DB.PAL.bamboo, true)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	var s := UI.lbl("삼국지 랜덤 디펜스 · 일주일을 살아남아 천하를 얻어라", 15, DB.PAL.bamboo_dim)
	s.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(s)
	v.add_child(Control.new())
	if Run.has_save():
		v.add_child(UI.btn("이어 하기", _continue, "pri", 60))
	v.add_child(UI.btn("새 판 시작", _new_game, "" if Run.has_save() else "pri", 60))
	v.add_child(UI.btn("온라인 대전 — 방 만들기 · 들어가기", _go_online, "gold", 60))
	v.add_child(UI.btn("설정", _settings_sheet, "ghost", 52))


func _go_online() -> void:
	if online == null:
		online = Online.new()
		online.gs = self
		add_child(online)
	online.connect_sheet()


func _continue() -> void:
	var r := Run.load_saved()
	if r == null:
		_new_game()
		return
	run = r
	_title.visible = false
	if run.battle != null:
		# 전투 도중 꺼졌다 —— 적어 둔 입력으로 마무리한다
		var res := run.resolve_pending()
		run.save()
		toast("지난 전투를 마무리했습니다 — %s" % ("승리" if res.win else "패배"), "news")
		go("war")
		return
	go("draw")


func _new_game() -> void:
	if online != null:
		online.leave()
	run = Run.new()
	run.new_game()
	run.save()
	_title.visible = false
	close_sheet()
	go("draw")


# ───────── 그리기 ─────────

func go(pg: String) -> void:
	if _scroll.get_v_scroll_bar():
		_scroll_keep[page] = _scroll.scroll_vertical
	page = pg
	render(true)


func render(new_page := false) -> void:
	if run == null:
		return
	_render_head()
	for k in _nav:
		_nav[k].button_pressed = k == page
	var keep := _scroll.scroll_vertical
	for c in _body.get_children():
		c.queue_free()
	var pg: Control
	match page:
		"draw": pg = _page_draw()
		"forge": pg = _page_forge()
		"deploy": pg = deploy.build()
		"war": pg = _page_war()
		"line": pg = _page_line()
		"rank": pg = _page_rank()
	pg.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_child(pg)
	var want: int = _scroll_keep.get(page, 0) if new_page else keep
	_restore_scroll.call_deferred(want)
	_flush_toasts()


func _restore_scroll(v: int) -> void:
	await get_tree().process_frame
	_scroll.scroll_vertical = v


func _render_head() -> void:
	_day_lbl.text = "DAY %d %s요일 · %s" % [run.day + 1, Run.DAYNAME[run.day],
		("종료" if run.over.win else "멸망") if run.over else Run.PHASE_N[run.phase]]
	if online != null:
		_day_lbl.text += online.clock_text()
	_phase_bar.cur = run.phase_idx()
	_phase_bar.queue_redraw()
	_stat_lbls.power.text = Battle.num(run.board_power())
	_stat_lbls.pv.text = str(run.my_pv())
	_stat_lbls.rank.text = "%d위" % run.rank()
	_stat_lbls.strike.text = "%d/%d" % [run.strikes, Run.STRIKE_MAX]
	_stat_lbls.strike.add_theme_color_override("font_color", DB.PAL.seal if run.strikes >= 2 else DB.PAL.paper)


func toast(text: String, kind := "") -> void:
	var p := PanelContainer.new()
	var col: Color = {"gold": DB.PAL.gold, "news": DB.PAL.bamboo, "gain": DB.PAL.jade, "bad": DB.PAL.seal}.get(kind, DB.PAL.bamboo_dim)
	p.add_theme_stylebox_override("panel", UI.flat(Color(DB.PAL.ink, 0.94), col, 1, 8, 10))
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := UI.lbl(text, 15, col.lightened(0.25))
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	p.add_child(l)
	_toast_box.add_child(p)
	while _toast_box.get_child_count() > 4:
		_toast_box.get_child(0).free()
	var tw := p.create_tween()
	tw.tween_interval(2.8)
	tw.tween_property(p, "modulate:a", 0.0, 0.4)
	tw.tween_callback(p.queue_free)


func _flush_toasts() -> void:
	for t in run.toasts:
		toast(t[0], t[1])
	run.toasts.clear()


func changed() -> void:
	if online == null:
		run.save()
	render()


## 행동 —— Run 의 명령(Run.COMMANDS)을 실행하고 저장·다시 그린다. 온라인이면 서버에도 보낸다
## (서버가 같은 명령을 판정해 상태를 돌려보낸다 —— 난수 상태가 같아 결과도 같다)
func act(m: String, a := []):
	var r = run.command(m, a.duplicate())
	if online != null:
		online.send_cmd(m, a)
	changed()
	return r


# ───────── 시트 ─────────

func open_sheet(title: String) -> VBoxContainer:
	_sheet_title.text = title
	for c in _sheet_body.get_children():
		c.queue_free()
	_sheet_mask.visible = true
	_sheet.visible = true
	_sheet_scroll.scroll_vertical = 0
	return _sheet_body


func close_sheet() -> void:
	_sheet_mask.visible = false
	_sheet.visible = false


func _menu() -> void:
	var b := open_sheet("메뉴")
	if online != null:
		b.add_child(UI.btn("온라인 방에서 나가기 (자리는 AI 가 이어받는다)", func():
			online.leave()
			close_sheet()
			_title.queue_free()
			_build_title(), "warn"))
		b.add_child(UI.btn("설정", _settings_sheet, "ghost"))
		return
	b.add_child(UI.btn("저장하고 처음 화면으로", func():
		run.save()
		close_sheet()
		_title.queue_free()
		_build_title()))
	b.add_child(UI.btn("새 판 시작 (지금 판은 사라집니다)", func():
		Run.delete_save()
		_new_game(), "warn"))
	b.add_child(UI.btn("설정", _settings_sheet, "ghost"))
	b.add_child(UI.hint("행동할 때마다 자동으로 저장됩니다. 전투 도중 앱을 꺼도 다음에 열면 그 전투를 마무리합니다."))


func _settings_sheet() -> void:
	var b := open_sheet("설정")
	b.add_child(UI.eyebrow("전투 품질 — 병사 수 · 안티에일리어싱 · 그림자"))
	var row := UI.hbox()
	for q in 3:
		var bt := UI.btn(Settings.QUALITY_N[q], func():
			Settings.quality = q
			Settings.apply()
			Settings.save_cfg()
			_settings_sheet(), "pri" if Settings.quality == q else "")
		bt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(bt)
	b.add_child(row)
	b.add_child(UI.hint("병사 수 %d%% · 휴대폰은 '낮음'부터 시작합니다. 다음 전투부터 적용됩니다." % roundi(Settings.COUNT_SCALE[Settings.quality] * 100)))
	var cb := CheckButton.new()
	cb.text = "자동 전투로 시작 (고유기·군령을 AI 가 쓴다)"
	cb.button_pressed = Settings.auto_battle
	cb.custom_minimum_size = Vector2(0, 48)
	cb.toggled.connect(func(on):
		Settings.auto_battle = on
		Settings.save_cfg())
	b.add_child(cb)


# ───────── 카드 · 아이템 부품 ─────────

func tile(k: String, n := -1, on_tap := Callable()) -> CardTile:
	var t := CardTile.new().setup(k, n)
	t.tapped.connect(on_tap if on_tap.is_valid() else func(id): card_info(id))
	return t


func item_box(id: String, n := -1, on_tap := Callable(), amp := 1.0) -> Control:
	var it: Dictionary = DB.IT[id]
	var col := UI.item_col(id)
	var b := Button.new()
	b.custom_minimum_size = Vector2(230, 70)
	b.add_theme_stylebox_override("normal", UI.flat(DB.PAL.ink2, col, 1, 6, 8))
	b.add_theme_stylebox_override("hover", UI.flat(DB.PAL.ink3, col, 1, 6, 8))
	b.add_theme_stylebox_override("pressed", UI.flat(DB.PAL.ink3, DB.PAL.gold, 2, 6, 8))
	if on_tap.is_valid():
		b.pressed.connect(on_tap)
	else:
		b.mouse_filter = Control.MOUSE_FILTER_PASS
	var v := UI.vbox(1)
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.offset_left = 10
	v.offset_top = 6
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var top := "%s%s" % [it.name, ("  ×%d" % n) if n > 0 else ""]
	v.add_child(UI.lbl(top, 15, col.lightened(0.2), true))
	v.add_child(UI.lbl("%s · %s" % [it.tag, it.grade], 12, DB.PAL.bamboo_dim))
	v.add_child(UI.lbl(UI.item_text(id, amp) + ("  · 신화 조합 재료" if it.use == "myth" else ""), 12, DB.PAL.bamboo))
	for c in v.get_children():
		c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(v)
	return b


## 재료 한 줄 —— 이름(가진 수/필요 수). 부족하면 붉게
func mats_bb(out: String) -> String:
	var m := Run.mat_count(DB.RECOF.get(out, []))
	var parts := []
	for k in m:
		var got := run.have(k)
		var ok: bool = got >= m[k]
		parts.append("[color=%s]%s%s(%d)[/color]" % [("#8fd4c2" if ok else "#e0806f"), DB.C[k].name,
			("×%d" % m[k]) if m[k] > 1 else "", got])
	var ni = Run.need_item(out)
	if ni != null:
		parts.append("[color=%s]＋%s(%d)[/color]" % ["#d59700" if run.bag.get(ni, 0) > 0 else "#e0806f", DB.IT[ni].name, run.bag.get(ni, 0)])
	return " + ".join(parts)


## 조합 한 줄 —— 결과 카드 · 재료 · 조합 버튼
func recipe_row(out: String, sub := "") -> Control:
	var h := UI.hbox(12)
	var t := tile(out, run.pool().get(out, -1))
	h.add_child(t)
	var v := UI.vbox(4)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_child(UI.rich(mats_bb(out), 14))
	var c: Dictionary = DB.C[out]
	if sub != "":
		v.add_child(UI.hint(sub))
	elif c.sk:
		v.add_child(UI.hint("『%s』 %s" % [c.sk.n, DB.skill_desc(c)]))
	h.add_child(v)
	var ok := run.can_forge(out)
	var b := UI.btn("조합" if ok else "부족 %d" % run.miss_count(out), func():
		if act("forge", [out]):
			toast("%s 조합 완료" % c.name, "gain"), "pri" if ok else "", 48)
	b.disabled = not ok
	b.custom_minimum_size = Vector2(110, 48)
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(b)
	return UI.panel(h, 8)


# ───────── 징집 ─────────

func _page_draw() -> Control:
	if run.over:
		return _over_panel()
	var v := UI.vbox(18)
	var n := run.draws_n()
	v.add_child(UI.rich("[font_size=20][b]%s[/b][/font_size]   [color=#8D7B5C]%s[/color]" % [
		"결전의 날" if run.day == 6 else "징집과 배급",
		"더 이상 농민을 징집하지 않는다. 명장만이 소환된다." if run.day == 6 else "뽑기 %d장으로 기본패를 얻고, 선택권으로 상위 카드를 지정한다." % n]))
	var acts := UI.flow(10)
	if n > 0:
		acts.add_child(UI.act("징집 완료" if run.drawn else "기본패 %d장" % n, "8종 균등", func(): act("do_draw"), "pri", run.drawn or not can_act()))
	var pl := run.pick_list()
	if not pl.is_empty():
		acts.add_child(UI.act("선택권 완료" if run.picked else "선택권 사용",
			" ".join(pl.map(func(p): return "%s×%d" % [DB.TIER[p.t].n, p.n])), func():
			act("begin_picks", ["phase", -1])
			picker(), "", run.picked or not can_act()))
	var rg := run.grant_list()
	if not rg.is_empty():
		acts.add_child(UI.act("무작위 배급 완료" if run.granted else "무작위 배급",
			" ".join(rg.map(func(p): return "%s×%d" % [DB.TIER[mini(Run.FREE_TIER_CAP, int(p.t))].n, p.n])) + " 무작위", func():
			for k in act("random_grant"):
				toast("%s 배급 · %s" % [DB.C[k].name, DB.TIER[DB.C[k].tier].n], "gain"), "", run.granted or not can_act()))
	for i in run.pending_picks.size():
		var p: Dictionary = run.pending_picks[i]
		acts.add_child(UI.act("%s ×%d" % [DB.TIER[mini(Run.FREE_TIER_CAP, p.t)].n, p.n], str(p.src).split(" · ")[0] + " 보상", func():
			act("begin_picks", ["pending", i])
			picker(), "warn", not can_act()))
	if not run.pick_queue.is_empty():
		var left := 0
		for q in run.pick_queue:
			left += int(q.n)
		acts.add_child(UI.act("선택권 이어서", "%d회 남음" % left, picker, "gold", not can_act()))
	v.add_child(acts)
	if run.last_spoil != null:
		v.add_child(UI.hint("방금 받은 기본패 %d장 — %s" % [run.last_spoil.n, run.last_spoil.src]))

	var info := UI.hbox(24)
	if not run.news.is_empty():
		var nv := UI.vbox(4)
		for nw in run.news.slice(0, 5):
			nv.add_child(UI.rich("[b]%s[/b]가 %s [color=#8D7B5C]%s 등용[/color]" % [nw.who, UI.card_bb(nw.unit), DB.TIER[DB.C[nw.unit].tier].n]))
		nv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.add_child(UI.sect("전황 소식", UI.panel(nv)))
	if run.last_item != null:
		info.add_child(UI.sect("이번 페이즈 보급품", item_box(run.last_item)))
	if info.get_child_count() > 0:
		v.add_child(info)

	if not run.last_draw.is_empty():
		var cnt := {}
		for k in run.last_draw:
			cnt[k] = cnt.get(k, 0) + 1
		var f := UI.flow()
		for k in Run.sort_cards(cnt.keys()):
			f.add_child(tile(k, cnt[k]))
		v.add_child(UI.sect("방금 징집한 %d장" % run.last_draw.size(), f))

	var p := run.pool()
	var tot := 0
	for k in p:
		tot += p[k]
	var hand := UI.flow()
	for k in Run.sort_cards(p.keys()):
		var t := tile(k, p[k])
		if run.on_board(k) > 0:
			t.mark = "on"
			t.note = "편성 %d · 손패 %d" % [run.on_board(k), run.inv.get(k, 0)]
		hand.add_child(t)
	var hv := UI.vbox(6)
	hv.add_child(hand if tot > 0 else UI.hint("보유 카드가 없다."))
	hv.add_child(UI.hint("카드를 누르면 능력과 그 카드가 쓰이는 상위 조합을 볼 수 있다."))
	v.add_child(UI.sect("보유 카드 — %d장 · %d PV" % [tot, run.my_pv()], hv))

	var near := run.near_recipes(10)
	var rv := UI.vbox(6)
	for r in near:
		var sub := "%d장 부족" % r.short if r.short > 0 else ("유니크 %s 필요 — 후반 보급" % DB.C[r.out].need if r.no_item else "")
		rv.add_child(recipe_row(r.out, sub))
	if near.is_empty():
		rv.add_child(UI.hint("먼저 기본패를 모으자."))
	v.add_child(UI.sect("연관 조합 — 지금 손패에서 이어지는 길", rv))
	return v


## 선택권 —— Run.pick_queue 맨 앞 선택권에서 한 장씩 고른다. 다 쓰면 닫는다
func picker() -> void:
	if run.pick_queue.is_empty() or not can_act():
		close_sheet()
		return
	var p: Dictionary = run.pick_queue[0]
	var t := int(p.t)
	var left := 0
	for x in run.pick_queue:
		left += int(x.n)
	var b := open_sheet("%s 선택권 — 남은 %d회" % [DB.TIER[t].n, left])
	b.add_child(UI.hint("%d종 중에서 고른다.%s" % [DB.by_tier(t).size(), " 무상으로 받는 패의 천장이다. 초월부터는 조합으로만 오른다." if t >= Run.FREE_TIER_CAP else ""]))
	for tag in DB.D.TAGORDER:
		var ks := Run.by_tier_tag(t, tag)
		if ks.is_empty():
			continue
		b.add_child(UI.eyebrow("%s %d종" % [tag, ks.size()]))
		var f := UI.flow()
		for k in ks:
			var c: Dictionary = DB.C[k]
			var tl := tile(k, run.pool().get(k, -1), func(id):
				if act("pick", [id]):
					toast("%s 획득 · %s" % [DB.C[id].name, DB.TIER[DB.C[id].tier].n], "gain")
				picker())
			tl.note = "공%d 방%d%s 속%d" % [c.atk, c["def"], (" 책%d" % c["int"]) if c["int"] > 0 else "", c.spd]
			f.add_child(tl)
		b.add_child(f)


## 지금 손댈 수 있는가 —— 온라인은 준비 시간에만
func can_act() -> bool:
	return online == null or online.can_act()


# ───────── 카드 상세 ─────────

func card_info(k: String) -> void:
	var c: Dictionary = DB.C[k]
	var p := run.pool()
	var b := open_sheet(c.name)
	var top := UI.hbox(14)
	var big := CardView.new().setup(k, Vector2(170, 242))
	top.add_child(big)
	var st := UI.vbox(6)
	st.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	st.add_child(UI.rich("[color=%s]%s[/color] · %s · %s · %d PV · %s명\n[b][color=%s]보유 %d장[/color][/b]" % [
		DB.tier_color(k).to_html(false), DB.TIER[c.tier].n, c.tag, DB.D.FAC[c.fac].full, c.pv, Battle.num(c.tr),
		"#8fd4c2" if p.get(k, 0) > 0 else "#e0806f", p.get(k, 0)]))
	var sr := UI.hbox(4)
	for pair in [["공격", c.atk], ["방어", c["def"]], ["책략", c["int"]], ["책방", c.res], ["속도", c.spd]]:
		if pair[0] == "책략" and pair[1] <= 0:
			continue
		sr.add_child(UI.stat(str(int(pair[1])), pair[0]))
	st.add_child(UI.panel(sr, 6))
	if c.sk:
		st.add_child(UI.rich("[color=#D9A64B]『%s』[/color] 발동 %d%%\n%s" % [c.sk.n, roundi(DB.D.RATE.get(str(c.tier), 0) * 100), DB.skill_desc(c)], 13))
	top.add_child(st)
	b.add_child(top)
	var u = DB.ult_of(k) if c.tier >= 7 else null
	if u != null:
		b.add_child(UI.rich("[color=#ffd76e][b]고유기 『%s』[/b][/color]  “%s”\n%s" % [u.name, u.shout, UI.ult_desc(u)], 13))
	var pt := DB.passive_text(k)
	if pt != "":
		b.add_child(UI.rich("[color=#8FD4C2]%s[/color]" % pt, 13))
	var a: Dictionary = DB.D.AFF[c.tag]
	b.add_child(UI.rich("[color=#8D7B5C]%s —[/color] [color=#8fd4c2]선호 %s[/color] %s · [color=#e0806f]어색 %s[/color] %s" % [
		a.why, UI.aff_zones(c.tag, "pref"), UI.aff_desc(c.tag, "pref"), UI.aff_zones(c.tag, "bad"), UI.aff_desc(c.tag, "bad")], 13))

	if DB.RECOF.has(k):
		b.add_child(UI.eyebrow("이 카드를 만드는 법"))
		b.add_child(_up_row(k))
	else:
		b.add_child(UI.eyebrow("이 카드를 만드는 법"))
		b.add_child(UI.hint("기본패 — 조합할 수 없고 징집으로만 얻는다."))
	var one := []
	var far := {}
	for o in Run.used_in(k):
		if DB.C[o].tier == c.tier + 1:
			one.append(o)
		else:
			far[DB.C[o].tier] = far.get(DB.C[o].tier, 0) + 1
	one.sort_custom(func(x, y): return run.miss_count(x) < run.miss_count(y))
	var can_n := one.filter(func(x): return run.can_forge(x)).size()
	b.add_child(UI.eyebrow("한 단계 위 · %s %d종%s" % [DB.TIER[mini(8, c.tier + 1)].n, one.size(), " — %d종 지금 조합 가능" % can_n if can_n > 0 else ""]))
	if one.is_empty():
		b.add_child(UI.hint("최종 등급이라 위가 없다." if c.tier == 8 else "이 카드를 재료로 쓰는 %s 조합이 없다 — 편성 전용이다." % DB.TIER[c.tier + 1].n))
	for o in one:
		b.add_child(_up_row(o))
	if not far.is_empty():
		var parts := []
		for t in far:
			parts.append("%s %d종" % [DB.TIER[t].n, far[t]])
		b.add_child(UI.hint("그 밖에 " + " · ".join(parts) + "에도 재료로 쓰인다."))


## 상세 시트의 조합 줄 —— 재료 칩을 누르면 그 카드 상세로 넘어간다
func _up_row(out: String) -> Control:
	var v := UI.vbox(6)
	var h := UI.hbox(10)
	var t := tile(out, run.pool().get(out, -1))
	h.add_child(t)
	var chips := UI.flow(6)
	chips.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var m := Run.mat_count(DB.RECOF[out])
	for q in m:
		var got := run.have(q)
		var ok: bool = got >= m[q]
		var cb := UI.btn("%s %s %d/%d" % ["✔" if ok else "✘", DB.C[q].name, got, m[q]], func(): card_info(q), "", 40)
		cb.add_theme_color_override("font_color", Color("#8fd4c2") if ok else Color("#e0806f"))
		cb.add_theme_font_size_override("font_size", 13)
		chips.add_child(cb)
	var ni = Run.need_item(out)
	if ni != null:
		var ok: bool = run.bag.get(ni, 0) > 0
		chips.add_child(UI.lbl("%s ◆%s %d/1" % ["✔" if ok else "✘", DB.IT[ni].name, run.bag.get(ni, 0)], 13, Color("#d59700") if ok else Color("#e0806f")))
	h.add_child(chips)
	v.add_child(h)
	if run.can_forge(out):
		var me := _sheet_title.text
		v.add_child(UI.btn("조합", func():
			if act("forge", [out]):
				toast("%s 조합 완료" % DB.C[out].name, "gain")
				# 지금 보던 카드 상세를 다시 연다
				for kk in DB.C:
					if DB.C[kk].name == me:
						card_info(kk)
						return
				close_sheet(), "pri", 46))
	return UI.panel(v, 8)


# ───────── 조합 ─────────

func _page_forge() -> Control:
	var v := UI.vbox(16)
	var chips := UI.flow(6)
	for t in [""] + DB.D.TAGORDER:
		var b := UI.btn("전체" if t == "" else t, func():
			forge_tag = t
			render(), "pri" if forge_tag == t else "", 44)
		b.custom_minimum_size = Vector2(72, 44)
		chips.add_child(b)
	v.add_child(UI.sect("조합 — 전체 %d개" % DB.D.RECDEF.size(), chips))
	v.add_child(UI.hint("편성판 카드도 재료로 쓰인다. 신화 장수는 유니크 아이템이 함께 필요하다."))
	var ready: Array = DB.D.RECDEF.filter(func(r): return run.can_forge(r[0]) and (forge_tag == "" or DB.C[r[0]].tag == forge_tag))
	ready.sort_custom(func(x, y): return DB.C[x[0]].tier > DB.C[y[0]].tier)
	if not ready.is_empty():
		var nv := UI.vbox(6)
		for r in ready:
			nv.add_child(recipe_row(r[0]))
		v.add_child(UI.sect("지금 조합 가능 — %d개" % ready.size(), nv))
	for t in range(8, 1, -1):
		var lst: Array = DB.D.RECDEF.filter(func(r): return DB.C[r[0]].tier == t and (forge_tag == "" or DB.C[r[0]].tag == forge_tag))
		if lst.is_empty():
			continue
		lst.sort_custom(func(x, y):
			var a := run.can_forge(x[0])
			var b2 := run.can_forge(y[0])
			if a != b2:
				return a
			return run.miss_count(x[0]) < run.miss_count(y[0]))
		var rv := UI.vbox(6)
		for r in lst:
			rv.add_child(recipe_row(r[0]))
		v.add_child(UI.sect("%s · %d~%d PV · %d종" % [DB.TIER[t].n, DB.TIER[t].lo, DB.TIER[t].hi, lst.size()], rv))

	# 환전
	var tv := UI.vbox(8)
	tv.add_child(UI.hint("같은 등급 안에서 1대1로 바꾼다. 계보를 갈아타는 유일한 통로다."))
	var f := UI.flow()
	var p := run.pool()
	for t in [2, 3, 4, 5, 6, 7]:
		for k in run.tier_stock(t):
			var tl := tile(k, p[k], func(id): trade_sheet(id))
			tl.note = "눌러서 바꾸기"
			tl.note_col = DB.PAL.gold
			f.add_child(tl)
	if run.trades <= 0:
		tv.add_child(UI.hint("이번 페이즈 환전을 모두 썼다."))
	elif f.get_child_count() == 0:
		tv.add_child(UI.hint("바꿀 카드가 없다."))
	else:
		tv.add_child(f)
	v.add_child(UI.sect("환전 — 이번 페이즈 %d회 남음" % run.trades, UI.panel(tv)))
	return v


func trade_sheet(from: String) -> void:
	var t: int = DB.C[from].tier
	var b := open_sheet("%s 환전 — 남은 %d회" % [DB.C[from].name, run.trades])
	b.add_child(UI.hint("같은 %s 등급 안에서 바꾼다." % DB.TIER[t].n))
	for tag in DB.D.TAGORDER:
		var ks := Run.by_tier_tag(t, tag).filter(func(x): return x != from)
		if ks.is_empty():
			continue
		b.add_child(UI.eyebrow(tag))
		var f := UI.flow()
		for k in ks:
			var c: Dictionary = DB.C[k]
			var tl := tile(k, -1, func(id):
				if act("trade", [from, id]):
					toast("%s → %s" % [DB.C[from].name, DB.C[id].name], "gain")
					close_sheet())
			tl.note = "공%d 방%d%s" % [c.atk, c["def"], (" 책%d" % c["int"]) if c["int"] > 0 else ""]
			f.add_child(tl)
		b.add_child(f)


# ───────── 전투 ─────────

func _page_war() -> Control:
	if online != null:
		return online.war_page()
	if run.over:
		return _over_panel()
	var v := UI.vbox(16)
	var placed := run.placed()
	if run.is_tour_phase():
		if run.tour == null:
			run.init_tour()
			run.save()
		var foe := run.tour_foe()
		v.add_child(UI.panel(UI.rich("[font_size=20][b]최종 토너먼트 · %s — %s[/b][/font_size]\n[color=#8D7B5C]지면 그대로 끝난다. 상대 %d PV · 내 전력 %d PV[/color]" % [
			Run.ROUNDNM[run.tour.round], foe.name, foe.pv, run.my_pv()])))
		v.add_child(_bracket())
		if run.last_result != null and run.tour.next != null:
			v.add_child(_result_panel())
			v.add_child(UI.btn("%s 진출" % Run.ROUNDNM[run.tour.round + 1], func():
				run.tour_advance()
				changed(), "pri", 60))
		else:
			v.add_child(UI.act("출진" if placed > 0 else "편성이 비어 있다", "%d/9칸 · %s명" % [placed, Battle.num(run.board_power())],
				func(): _start("tour"), "warn", placed == 0))
	else:
		v.add_child(UI.panel(UI.rich("[font_size=20][b]%s요일 %s — 이 페이즈의 두 전투[/b][/font_size]\n토벌과 임의 세력 대전을 각각 한 번 치른다. [color=#e0806f]토벌 실패는 어느 페이즈든 경고로 쌓인다[/color] — 현재 %d/%d회." % [
			Run.DAYNAME[run.day], Run.PHASE_N[run.phase], run.strikes, Run.STRIKE_MAX])))
		var row := UI.hbox(12)
		var q := UI.act("① 토벌 완료" if run.quest_done else "① 토벌 — %s" % run.quest_name(),
			"다음은 대전이다" if run.quest_done else "적 전력 %d PV · 승리 시 기본패 %d장 · 실패 시 경고" % [run.quest_pv(), DB.D.QUEST_BASE[run.day]],
			func(): _start("quest"), "warn", run.quest_done or placed == 0)
		q.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(q)
		var pv := UI.act("② 대전 완료" if run.pvp_done else "② 대전 — 임의 세력",
			"토벌을 먼저 끝내야 열린다" if not run.quest_done else "승리 시 기본패 %d장 · 패배해도 %d장" % [DB.D.PVP_BASE.win, DB.D.PVP_BASE.lose],
			func(): _start("pvp"), "pri", run.pvp_done or placed == 0 or not run.quest_done)
		pv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(pv)
		v.add_child(row)
		if placed == 0:
			v.add_child(UI.btn("편성이 비어 있다 — 편성하러 가기", func(): go("deploy"), "gold"))
		if run.last_result != null:
			v.add_child(_result_panel())
		if run.can_next():
			var nxt: String = "%s요일 오전" % Run.DAYNAME[mini(6, run.day + 1)] if run.phase == 2 else Run.PHASE_N[run.phase + 1]
			v.add_child(UI.act("다음 페이즈로", nxt, func():
				run.advance()
				run.save()
				go("draw"), "pri"))
	var cb := CheckButton.new()
	cb.text = "자동 전투로 시작 (고유기·군령을 AI 가 쓴다 · 전투 중에도 바꿀 수 있다)"
	cb.button_pressed = Settings.auto_battle
	cb.custom_minimum_size = Vector2(0, 48)
	cb.toggled.connect(func(on):
		Settings.auto_battle = on
		Settings.save_cfg())
	v.add_child(cb)
	v.add_child(UI.hint("전투 중에는 아래 장수 카드가 금빛이면 눌러 고유기, 왼쪽 아래 군령(돌격·방진·재정비)은 포인트 2. 두 손가락으로 확대·회전, 한 손가락으로 이동."))
	return v


func _result_panel() -> Control:
	var r: Dictionary = run.last_result
	var col := "#8fd4c2" if r.win else "#e0806f"
	var s := "[font_size=18][b][color=%s]%s[/color][/b][/font_size]  %s — 잔존 %d부대 대 %d부대 · %d턴" % [
		col, "무승부" if r.draw else ("승리" if r.win else "패배"), r.title, r.left, r.eLeft, r.turns]
	if r.mvp != "":
		s += " · 수훈갑 %s" % r.mvp
	if run.last_spoil != null:
		s += "\n[color=#C6AC7C]기본패 %d장 획득[/color]" % run.last_spoil.n
	if not run.pending_picks.is_empty():
		s += "  [color=#D9A64B]· 받을 선택권 %d개 — 징집 화면에서[/color]" % run.pending_picks.size()
	return UI.panel(UI.rich(s))


func _bracket() -> Control:
	var v := UI.vbox(6)
	var t: Dictionary = run.tour
	for r in 3:
		var ms = t.res[r]
		if ms == null:
			continue
		var parts := []
		for i in ms.size():
			var m: Dictionary = ms[i]
			var nm := func(pl):
				var s: String = pl.name
				if m.w == pl.name:
					s = "[color=#8fd4c2][b]%s[/b][/color]" % s
				elif m.w != null:
					s = "[color=#5d6a88]%s[/color]" % s
				if pl.me:
					s = "[u]%s[/u]" % s
				return s
			var cur: bool = r == t.round and i == t.my_match and m.w == null
			parts.append("%s%s 대 %s%s" % ["[bgcolor=#33405F]" if cur else "", nm.call(m.a), nm.call(m.b), "[/bgcolor]" if cur else ""])
		v.add_child(UI.rich("[color=#C6AC7C][b]%s[/b][/color]   %s" % [Run.ROUNDNM[r], "    ".join(parts)]))
	v.add_child(UI.hint("전력 순위로 시딩한다. 다른 대진도 같은 전투 엔진으로 진행된다."))
	return UI.sect("대진표 — %s 진행 중" % Run.ROUNDNM[t.round], UI.panel(v))


func _start(kind: String) -> void:
	if run.placed() == 0 or run.battle != null:
		return
	var bt: Dictionary
	match kind:
		"quest": bt = run.start_quest()
		"pvp": bt = run.start_pvp()
		"tour": bt = run.start_tour()
	run.save()
	close_sheet()
	_battle_res = null
	_battle_done.visible = false
	_battle_layer.visible = true
	Settings.apply_port(_battle.port)
	_battle.play(bt, Settings.auto_battle)


## 온라인 —— 서버가 계산한 결과를 재생만 한다
func show_battle(res: Dictionary, last: bool, kind := "") -> void:
	close_sheet()
	_battle_res = null
	_battle_done.visible = false
	_battle_done.text = "결과 정리  ▶" if last else "다음 전투  ▶"
	_battle_layer.visible = true
	Settings.apply_port(_battle.port)
	_battle.play_res(res, kind)


func hide_battle() -> void:
	_battle_layer.visible = false


func battle_visible() -> bool:
	return _battle_layer.visible


func _on_battle_ended(res: Dictionary, _inputs: Array) -> void:
	_battle_res = res
	_battle_done.visible = true


func _on_battle_close() -> void:
	if online != null:
		_battle_res = null
		online.watch_next()
		return
	if _battle_res == null:
		return
	run.finish_battle(_battle_res)
	_battle_res = null
	run.save()
	_battle_layer.visible = false
	if run.last_spoil != null and run.last_result.kind != "tour":
		toast("기본패 %d장 획득 — %s" % [run.last_spoil.n, run.last_spoil.src], "gain")
	go("war")


# ───────── 계보 ─────────

func _page_line() -> Control:
	var v := UI.vbox(16)
	var p := run.pool()
	var tbl := GridContainer.new()
	tbl.columns = 5
	tbl.add_theme_constant_override("h_separation", 26)
	tbl.add_theme_constant_override("v_separation", 4)
	for hd in ["등급", "PV", "병력", "종수", "보유"]:
		tbl.add_child(UI.lbl(hd, 13, DB.PAL.bamboo_dim))
	for t in range(1, 9):
		var owned := DB.by_tier(t).filter(func(k): return p.has(k)).size()
		tbl.add_child(UI.lbl(DB.TIER[t].n, 15, DB.TIER[t].c, true))
		tbl.add_child(UI.lbl("%d~%d" % [DB.TIER[t].lo, DB.TIER[t].hi], 14))
		tbl.add_child(UI.lbl(Battle.num(DB.C[DB.by_tier(t)[0]].tr), 14))
		tbl.add_child(UI.lbl(str(DB.by_tier(t).size()), 14))
		tbl.add_child(UI.lbl(str(owned) if owned else "—", 14, DB.PAL.jade if owned else DB.PAL.bamboo_dim))
	var top := UI.hbox(24)
	top.add_child(UI.sect("등급", UI.panel(tbl)))
	var prog := UI.vbox(4)
	for tag in DB.D.TAGORDER:
		var own: Array = p.keys().filter(func(k): return DB.C[k].tag == tag)
		var top_t := 0
		for k in own:
			top_t = maxi(top_t, DB.C[k].tier)
		var best := ""
		for k in own:
			if DB.C[k].tier == top_t and (best == "" or p[k] > p[best]):
				best = k
		var s := "[color=#C6AC7C]%s[/color]  " % tag
		for t in range(1, 9):
			s += "[color=%s]■[/color]" % (DB.TIER[t].c.to_html(false) if t <= top_t else "33405F")
		s += "  %s" % (UI.card_bb(best) if best != "" else "—")
		prog.add_child(UI.rich(s, 15))
	prog.add_child(UI.hint("여덟 칸이 기본부터 신화까지 — 칸이 비면 아직 그 등급에 닿지 못했다."))
	var pp := UI.sect("계보 진행도", UI.panel(prog))
	pp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(pp)
	v.add_child(top)

	for tag in DB.D.TAGORDER:
		var lv := UI.vbox(6)
		for t in range(8, 0, -1):
			var ks := Run.by_tier_tag(t, tag)
			if ks.is_empty():
				continue
			var row := UI.hbox(8)
			var tl := UI.lbl(DB.TIER[t].n, 14, DB.TIER[t].c, true)
			tl.custom_minimum_size = Vector2(44, 0)
			row.add_child(tl)
			var f := UI.flow(6)
			f.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			for k in ks:
				var c: Dictionary = DB.C[k]
				var has: bool = p.get(k, 0) > 0
				var b := UI.btn("%s%s%s" % [c.name, "★" if c.kind == "myth" else "", (" ×%d" % p[k]) if has else ""], func(): card_info(k), "", 40)
				b.add_theme_font_size_override("font_size", 13)
				b.add_theme_color_override("font_color", DB.tier_color(k) if has else Color(DB.PAL.paper, 0.55))
				if has:
					b.add_theme_stylebox_override("normal", UI.flat(DB.PAL.ink3, DB.tier_color(k), 1, 6, 8))
				f.add_child(b)
			row.add_child(f)
			lv.add_child(row)
		var cnt := [6, 7, 8].map(func(t): return Run.by_tier_tag(t, tag).size())
		v.add_child(UI.sect("%s 계보 · 초월 %d 불멸 %d 신화 %d" % [tag, cnt[0], cnt[1], cnt[2]], UI.panel(lv)))

	# 신화 —— 재료 등급 구성으로 묶은 경로
	var g := {}
	for k in DB.by_tier(8):
		var ts: Array = DB.RECOF[k].map(func(x): return DB.C[x].tier)
		ts.sort()
		ts.reverse()
		var key := " + ".join(ts.map(func(t): return DB.TIER[t].n))
		if not g.has(key):
			g[key] = []
		g[key].append(k)
	var mv := UI.vbox(10)
	mv.add_child(UI.hint("모든 신화는 유니크 아이템을 함께 소모하며, 그 아이템은 완성된 장수에게 영구히 장착된다. 불멸을 거치지 않는 경로도 있다."))
	for key in g:
		var pv := UI.vbox(4)
		pv.add_child(UI.lbl("%s — %d종" % [key, g[key].size()], 15, DB.PAL.bamboo, true))
		for k in g[key]:
			var ni = Run.need_item(k)
			var r := UI.rich("[url=%s]%s[/url]  [color=#8D7B5C]%s · %d PV[/color]   %s" % [k, UI.card_bb(k), DB.C[k].tag, DB.C[k].pv, mats_bb(k)], 14)
			r.meta_clicked.connect(func(m): card_info(str(m)))
			pv.add_child(r)
		mv.add_child(UI.panel(pv, 10))
	v.add_child(UI.sect("신화 %d종 — 경로 %d갈래" % [DB.by_tier(8).size(), g.size()], mv))
	return v


# ───────── 순위 ─────────

func _standings() -> Control:
	var rows := [{"name": "나", "epi": "%d승 %d패%s" % [run.my_w, run.my_l, (" · 경고 %d" % run.strikes) if run.strikes else ""],
		"fac": "촉", "pv": run.my_pv(), "me": true, "dead": run.over != null and not run.over.win}]
	for b in run.bots:
		rows.append({"name": b.name, "epi": b.epi, "fac": b.fac, "pv": roundi(b.pv), "me": false, "dead": false})
	rows.sort_custom(func(a, b): return a.pv > b.pv)
	var v := UI.vbox(4)
	for i in rows.size():
		var r: Dictionary = rows[i]
		var h := UI.hbox(12)
		h.add_child(UI.lbl(str(i + 1), 20, DB.PAL.gold if r.me else DB.PAL.bamboo_dim, true))
		var fl := UI.lbl(r.fac, 14, Color.WHITE, true)
		fl.add_theme_stylebox_override("normal", UI.flat(DB.fac_color(r.fac), DB.fac_color(r.fac), 0, 4, 4))
		h.add_child(fl)
		var nv := UI.vbox(0)
		nv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		nv.add_child(UI.lbl(r.name, 16, DB.PAL.gold if r.me else DB.PAL.paper, true))
		nv.add_child(UI.lbl(r.epi, 12, DB.PAL.bamboo_dim))
		h.add_child(nv)
		h.add_child(UI.lbl("멸망" if r.dead else "%d PV" % r.pv, 16, DB.PAL.seal if r.dead else DB.PAL.bamboo, true))
		var pnl := UI.panel(h, 8)
		if r.me:
			pnl.add_theme_stylebox_override("panel", UI.flat(DB.PAL.ink3, DB.PAL.gold, 1, 8, 8))
		v.add_child(pnl)
	return v


func _page_rank() -> Control:
	var v := UI.vbox(16)
	var sr := UI.hbox()
	sr.add_child(UI.stat("%d위" % run.rank(), "8인 중"))
	sr.add_child(UI.stat(str(run.my_pv()), "내 전력"))
	sr.add_child(UI.stat("%d승 %d패" % [run.my_w, run.my_l], "전적"))
	sr.add_child(UI.stat("%d / %d" % [run.strikes, Run.STRIKE_MAX], "토벌 실패 경고"))
	v.add_child(UI.sect("군웅 할거 · %s요일 %s" % [Run.DAYNAME[run.day], Run.PHASE_N[run.phase]], UI.panel(sr)))
	var two := UI.hbox(20)
	var st := UI.sect("순위", _standings())
	st.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	two.add_child(st)
	var bv := UI.vbox(6)
	var bs: Array = run.bots.duplicate()
	bs.sort_custom(func(a, b): return a.pv > b.pv)
	for b in bs:
		bv.add_child(UI.rich("[b]%s[/b]  [color=#8D7B5C]%s 편중 · %s%s[/color]" % [b.name, b.style, DB.FORM[DB.STYLE_FORM[b.style]].n,
			(" · 토벌 실패 %d" % b.strikes) if b.strikes else ""]))
	bv.add_child(UI.hint("모든 토벌 실패가 경고로 쌓이며, 3일차부터 한도에 닿으면 멸망한다. 봇 세력은 멸망하지 않고 전력 손실로만 대가를 치른다."))
	var sp := UI.sect("세력 성향", UI.panel(bv))
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	two.add_child(sp)
	v.add_child(two)
	return v


func _over_panel() -> Control:
	var v := UI.vbox(16)
	var o: Dictionary = run.over
	var pv := UI.vbox(8)
	var t := UI.lbl("우승" if o.win else "멸망", 44, DB.PAL.jade if o.win else DB.PAL.seal, true)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pv.add_child(t)
	var m := UI.lbl(o.msg, 16, DB.PAL.paper)
	m.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pv.add_child(m)
	var s := UI.lbl("최종 %s명 · %d PV · %d승 %d패" % [Battle.num(run.board_power()), run.my_pv(), run.my_w, run.my_l], 15, DB.PAL.bamboo)
	s.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pv.add_child(s)
	v.add_child(UI.panel(pv, 24))
	v.add_child(_standings())
	if online != null:
		v.add_child(UI.btn("처음 화면으로", func():
			online.leave()
			_title.queue_free()
			_build_title(), "pri", 60))
		return v
	v.add_child(UI.btn("새 판 시작", func():
		Run.delete_save()
		_new_game(), "pri", 60))
	return v


# ───────── 점검용 ─────────

func _dev_args() -> void:
	var a := {}
	for s in OS.get_cmdline_user_args():
		var kv := s.trim_prefix("--").split("=", true, 1)
		a[kv[0]] = kv[1] if kv.size() > 1 else "1"
	if a.has("gq"):
		Settings.quality = int(a.gq)
		Settings.apply()
	if a.has("gnew"):
		run = Run.new()
		run.new_game(int(a.gnew))
		for i in int(a.get("gplay", "0")):
			run.dev_autoplay()
		_title.visible = false
		go(a.get("gpage", "draw"))
	if a.has("gonline"):
		# 점검용 온라인 —— --gonline=ws://… --gname=이름 (--gcreate=fast|normal|test --gstart=사람수 | --gjoin=방장이름) --gauto
		_go_online()
		online.net.player = str(a.get("gname", "시험"))
		online.net.token = ""      # 같은 PC 의 창들이 net.cfg 를 같이 쓴다 —— 시험 창은 새 토큰
		online.dev_auto = a.has("gauto")
		online.net.connect_to(str(a.gonline))
		await online.net.opened
		if a.has("gcreate"):
			online.net.send({"t": "create", "mode": a.gcreate})
			if a.has("gstart"):
				while online.room.is_empty() or online.room.seats.size() < int(a.gstart):
					await online.net.message
				online.net.send({"t": "start"})
		elif a.has("gjoin"):
			# --gjoin=방장이름 —— 그 사람이 만든 방이 보일 때까지 목록을 다시 받는다
			var want: String = str(a.gjoin)
			var code := ""
			while code == "":
				await get_tree().create_timer(0.5).timeout
				online.net.send({"t": "list"})
				await online.net.message
				for r in online.rooms:
					if r.host == want or want == "1":
						code = r.code
			online.net.send({"t": "join", "code": code})
	if a.has("gsheet"):
		var kv: PackedStringArray = str(a.gsheet).split(":")
		match kv[0]:
			"card": card_info(kv[1])
			"slot": deploy.slot_sheet(int(kv[1]))
			"menu": _menu()
			"settings": _settings_sheet()
	if a.has("gbattle"):
		await get_tree().process_frame
		_start(a.gbattle)
		if a.has("speed"):
			_battle._set_speed(float(a.speed))
		if a.has("gclose"):
			# 끝나면 1초 뒤 결과 정리를 누른 것처럼 —— 저장·보상 흐름 점검
			await _battle.ended
			await get_tree().create_timer(1.0).timeout
			_on_battle_close()
			print("전투 정리: %s · 길이 %.1f초(배율 %.2f) · 토벌 %s · 대전 %s · 경고 %d · 선택권 %d · 저장 %s" % [run.last_result.title, _battle.end_clock, _battle.pace,
				run.quest_done, run.pvp_done, run.strikes, run.pending_picks.size(), Run.has_save()])
	if a.has("gshot"):
		await get_tree().create_timer(float(a.get("after", "1.0"))).timeout
		if a.has("scroll"):
			_scroll.scroll_vertical = int(a.scroll)
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(a.gshot)
		get_tree().quit()


## 머리띠의 21칸 진행 막대
class PhaseBar extends Control:
	var cur := 0

	func _draw() -> void:
		var n := 21
		var gap := 3.0
		var w := (size.x - gap * (n - 1)) / n
		var y := size.y * 0.5 - 5
		for i in n:
			var col: Color = DB.PAL.gold if i == cur else (DB.PAL.bamboo_dim if i < cur else DB.PAL.ink4)
			draw_rect(Rect2(i * (w + gap), y, w, 10), col)
			if i % 3 == 2 and i < n - 1:
				draw_rect(Rect2(i * (w + gap) + w + 0.5, y - 4, 2, 18), DB.PAL.ink3)
