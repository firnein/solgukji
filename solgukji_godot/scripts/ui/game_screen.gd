class_name GameScreen
extends Control
## 게임 화면 —— 원본 HTML 의 화면들(징집·조합·편성·전장·계보·순위)을 휴대폰 세로 화면에 옮겼다.
## 위: 날짜·페이즈·전력 한 줄 · 가운데: 페이지(스크롤) · 아래: 탭 5개(징집·조합·편성·전투·기록)
## 상세·선택은 아래에서 올라오는 시트(끌어내리거나 바깥을 누르면 닫힌다) · 전투는 전체 화면.
## 상태는 Run 이 들고, 바뀔 때마다 render() 로 지금 페이지만 다시 그린다. 행동마다 저장한다.
## 행동은 모두 act(명령, 인자) 로 한다 —— 혼자 하면 Run 에 바로, 온라인(online)이면 서버에도 보낸다.
## 스크롤은 TouchScroll 이 맡는다 —— 버튼·카드 위에서 끌어도 목록이 움직인다.
##
## 점검용 인자 (godot ... -- 뒤에):  --gnew=시드 --gplay=페이즈수 --gpage=deploy --gshot=경로.png --after=초 --gsheet=card:c39
## (예전 도감·전투 연출 화면은 --tab=… 을 주면 열린다 —— scenes/main.tscn)

const TABS := [["draw", "징집"], ["forge", "조합"], ["deploy", "편성"], ["war", "전투"], ["more", "기록"]]
const MAX_W := 640.0         # PC 에서 창을 넓혀도 글줄은 이 폭까지만
const TOP_H := 66.0
const TAB_H := 62.0

var run: Run
var page := "draw"
var forge_tag := ""
var forge_tier := 0           # 조합 등급 거르기 (0 = 모두)
var _forge_more := 0
var _open := {}               # 접는 묶음 -> 펼침 여부
var _scroll_keep := {}        # 페이지 -> 스크롤 위치

var _safe: MarginContainer
var _top: Control
var _day_lbl: Label
var _sub_lbl: Label
var _pow_lbl: Label
var _info_lbl: RichTextLabel
var _phase_bar: Control
var _tabs := {}
var _tabbar: Control
var _scroll: ScrollContainer
var _body: MarginContainer
var _fixed: MarginContainer   # 스크롤하지 않는 페이지 (편성 —— 편성판을 고정하고 손패만 스크롤)
var _sheet_mask: ColorRect
var _sheet: PanelContainer
var _sheet_body: VBoxContainer
var _sheet_title: Label
var _sheet_scroll: ScrollContainer
var _sheet_h := 0.0
var _sheet_tw: Tween
var _sheet_drag := -1.0       # 손잡이를 끄는 중이면 누른 y
# 카드 시트 길 —— 상세 · 조합 시트에서 다른 카드로 넘어가면 지나온 카드를 쌓아 두고 '‹ 이전' · 오른쪽 쓸기로 돌아간다 (10/30)
var _route := {}              # 지금 보는 카드 시트 {kind: "card" | "recipe", k}
var _hist: Array = []         # 지나온 카드 시트들
var _routing := false         # 카드 시트를 여는 중 (open_sheet 가 길을 지우지 않게)
var _back_nav := false        # 뒤로 가는 중 (길에 쌓지 않게)
var _back_btn: Button
var _swipe_p := Vector2.INF   # 시트 위에서 누른 곳 (쓸기 판정)
var _sheet_dy := 0.0
var _toast_box: VBoxContainer
var _battle_layer: Control
var _battle: BattleView
var _battle_done: Button
var _report: BattleReport    # 전투 결과표 (끝나고 잠시 뒤 뜬다)
var _battle_res = null
var _title: Control
var deploy: DeployPage
var forge_tree: ForgeTree     # 조합 탭 맨 위 갈무리 트리 (scripts/ui/forge_tree.gd)
var online: Online = null     # 온라인 대전 중이면 있다 (scripts/ui/online.gd)


func _ready() -> void:
	Settings.load_cfg()
	Sfx.music("menu")
	if OS.has_feature("testscene"):       # 테스트 APK (build_test_apk.bat) —— 전투 점검 화면으로 바로
		get_tree().change_scene_to_file.call_deferred("res://scenes/main.tscn")
		return
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
	_safe = MarginContainer.new()
	_safe.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_safe)
	var root := UI.vbox(0)
	_safe.add_child(root)
	root.add_child(_build_top())
	var host := Control.new()
	host.size_flags_vertical = Control.SIZE_EXPAND_FILL
	host.clip_contents = true
	root.add_child(host)
	_scroll = UI.scroll()
	_scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	host.add_child(_scroll)
	_body = MarginContainer.new()
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_body)
	_fixed = MarginContainer.new()
	_fixed.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fixed.visible = false
	host.add_child(_fixed)
	root.add_child(_build_tabbar())
	deploy = DeployPage.new()
	deploy.gs = self
	forge_tree = ForgeTree.new(self)
	_toast_box = UI.vbox(6)
	_toast_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast_box.alignment = BoxContainer.ALIGNMENT_END
	add_child(_toast_box)
	_build_sheet()
	_build_battle()
	_build_title()
	resized.connect(_layout)
	_layout()
	_dev_args()


## 화면 크기·노치 —— 안전 영역 안쪽에 그리고, 넓은 창에서는 글줄 폭을 줄인다
func _layout() -> void:
	var sa := _safe_insets()
	_safe.add_theme_constant_override("margin_top", int(sa.position.y))
	_safe.add_theme_constant_override("margin_bottom", int(sa.size.y))
	_safe.add_theme_constant_override("margin_left", int(sa.position.x))
	_safe.add_theme_constant_override("margin_right", int(sa.size.x))
	var side := maxf(14.0, (size.x - MAX_W) / 2.0)
	for m in [_body, _fixed]:
		m.add_theme_constant_override("margin_left", int(side))
		m.add_theme_constant_override("margin_right", int(side))
		m.add_theme_constant_override("margin_top", 14 if m == _body else 10)
		m.add_theme_constant_override("margin_bottom", 28 if m == _body else 8)
	_toast_box.anchor_left = 0
	_toast_box.anchor_right = 1
	_toast_box.anchor_top = 1
	_toast_box.anchor_bottom = 1
	_toast_box.offset_left = side
	_toast_box.offset_right = -side
	_toast_box.offset_bottom = -(TAB_H + sa.size.y + 12)
	_toast_box.offset_top = _toast_box.offset_bottom - 300
	if _sheet != null and _sheet.visible:
		_fit_sheet(false)
	if _battle_layer != null:
		_battle_layer.offset_top = sa.position.y
		_battle_layer.offset_bottom = -sa.size.y


## 노치·홈 막대를 피할 여백 (논리 좌표) —— position = 왼쪽·위, size = 오른쪽·아래
func _safe_insets() -> Rect2:
	if not OS.has_feature("mobile"):
		return Rect2()
	var win := Vector2(DisplayServer.window_get_size())
	var sa := Rect2(DisplayServer.get_display_safe_area())
	if win.x <= 0 or sa.size.x <= 0:
		return Rect2()
	var k := size.x / win.x
	return Rect2(sa.position.x * k, sa.position.y * k, (win.x - sa.end.x) * k, (win.y - sa.end.y) * k)


## 휴대폰 —— 뒤로 가기는 시트를 닫고, 앱이 가려지거나 꺼질 때 저장한다
func _notification(what: int) -> void:
	match what:
		NOTIFICATION_WM_GO_BACK_REQUEST:
			if _sheet != null and _sheet.visible:
				close_sheet()
			elif _battle_layer != null and _battle_layer.visible:
				_battle.toggle_menu()      # 전투 중에는 메뉴(자동 전투·결과로)를 연다
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

func _build_top() -> Control:
	var bar := PanelContainer.new()
	var sb := UI.flat(Color("#0f1424"), DB.PAL.ink3, 0, 0, 0)
	sb.border_width_bottom = 1
	sb.content_margin_left = 14
	sb.content_margin_right = 6
	sb.content_margin_top = 8
	sb.content_margin_bottom = 6
	bar.add_theme_stylebox_override("panel", sb)
	bar.custom_minimum_size = Vector2(0, TOP_H)
	_top = bar
	var v := UI.vbox(5)
	bar.add_child(v)
	var row := UI.hbox(8)
	v.add_child(row)
	var lv := UI.vbox(0)
	lv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_day_lbl = UI.lbl("", 17, DB.PAL.paper, true)
	_sub_lbl = UI.lbl("", 12, DB.PAL.bamboo)
	_sub_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_sub_lbl.clip_text = true
	lv.add_child(_day_lbl)
	lv.add_child(_sub_lbl)
	row.add_child(lv)
	var rv := UI.vbox(0)
	_pow_lbl = UI.lbl("", 17, DB.PAL.paper, true)
	_pow_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	rv.add_child(_pow_lbl)
	_info_lbl = UI.rich("", 12)
	_info_lbl.autowrap_mode = TextServer.AUTOWRAP_OFF
	_info_lbl.custom_minimum_size = Vector2(150, 0)
	rv.add_child(_info_lbl)
	row.add_child(rv)
	var mb := UI.btn("☰", _menu, "ghost", 44)
	mb.custom_minimum_size = Vector2(44, 44)
	mb.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	mb.add_theme_font_size_override("font_size", 22)
	row.add_child(mb)
	_phase_bar = PhaseBar.new()
	_phase_bar.custom_minimum_size = Vector2(0, 6)
	v.add_child(_phase_bar)
	return bar


func _build_tabbar() -> Control:
	var bar := PanelContainer.new()
	var sb := UI.flat(Color("#0f1424"), DB.PAL.ink3, 0, 0, 0)
	sb.border_width_top = 1
	bar.add_theme_stylebox_override("panel", sb)
	bar.custom_minimum_size = Vector2(0, TAB_H)
	var h := UI.hbox(0)
	bar.add_child(h)
	for t in TABS:
		var tb := TabButton.new()
		tb.key = t[0]
		tb.text = t[1]
		tb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tb.tapped.connect(func(k):
			UI.buzz()
			if k == "more":
				go("rank" if page == "line" or page == "rank" else _open.get("more_page", "rank"))
			elif k == page:
				_scroll_to_top()
			else:
				go(k))
		_tabs[t[0]] = tb
		h.add_child(tb)
	_tabbar = bar
	return bar


func _scroll_to_top() -> void:
	var tw := create_tween()
	tw.tween_property(_scroll, "scroll_vertical", 0, 0.25).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func _build_sheet() -> void:
	_sheet_mask = ColorRect.new()
	_sheet_mask.color = Color(0, 0, 0, 0.55)
	_sheet_mask.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_sheet_mask.visible = false
	_sheet_mask.gui_input.connect(func(e):
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			close_sheet())
	TouchScroll.block(_sheet_mask)
	add_child(_sheet_mask)
	_sheet = PanelContainer.new()
	var sb := UI.flat(DB.PAL.ink2, DB.PAL.bamboo_dim, 0, 0, 0)
	sb.corner_radius_top_left = 18
	sb.corner_radius_top_right = 18
	sb.border_width_top = 1
	sb.shadow_color = Color(0, 0, 0, 0.45)
	sb.shadow_size = 18
	_sheet.add_theme_stylebox_override("panel", sb)
	_sheet.visible = false
	_sheet.anchor_left = 0
	_sheet.anchor_right = 1
	_sheet.anchor_top = 1
	_sheet.anchor_bottom = 1
	add_child(_sheet)
	var v := UI.vbox(0)
	_sheet.add_child(v)
	# 손잡이 + 제목 —— 여기를 끌어내리면 닫힌다
	var head := PanelContainer.new()
	head.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	head.mouse_filter = Control.MOUSE_FILTER_STOP
	head.gui_input.connect(_sheet_head_input)
	v.add_child(head)
	var hv := UI.vbox(2)
	hv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(hv)
	var handle := SheetHandle.new()
	handle.custom_minimum_size = Vector2(0, 18)
	handle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hv.add_child(handle)
	var top := UI.hbox()
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tm := MarginContainer.new()
	tm.add_theme_constant_override("margin_left", 18)
	tm.add_theme_constant_override("margin_right", 6)
	tm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tm.add_child(top)
	hv.add_child(tm)
	_back_btn = UI.btn("‹", go_back, "ghost", 40)
	_back_btn.add_theme_font_size_override("font_size", 14)
	_back_btn.add_theme_stylebox_override("normal", UI.flat(DB.PAL.ink3, DB.PAL.ink4, 1, 8, 6))
	_back_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_back_btn.visible = false
	top.add_child(_back_btn)
	_sheet_title = UI.lbl("", 19, DB.PAL.paper, true)
	_sheet_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_sheet_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_sheet_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(_sheet_title)
	var x := UI.btn("✕", close_sheet, "ghost", 44)
	x.custom_minimum_size = Vector2(44, 44)
	x.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	x.add_theme_font_size_override("font_size", 20)
	top.add_child(x)
	_sheet_scroll = UI.scroll()
	_sheet_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(_sheet_scroll)
	var m := MarginContainer.new()
	m.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for s in ["left", "right"]:
		m.add_theme_constant_override("margin_" + s, 16)
	m.add_theme_constant_override("margin_top", 6)
	m.add_theme_constant_override("margin_bottom", 24)
	_sheet_scroll.add_child(m)
	_sheet_body = UI.vbox(12)
	_sheet_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	m.add_child(_sheet_body)


func _sheet_head_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
		if e.pressed:
			_sheet_drag = e.global_position.y
			_sheet_dy = 0.0
		elif _sheet_drag >= 0:
			_sheet_drag = -1.0
			if _sheet_dy > minf(110.0, _sheet_h * 0.3):
				close_sheet()
			else:
				_slide_sheet(0.0, 0.18)
	elif e is InputEventMouseMotion and _sheet_drag >= 0:
		_sheet_dy = maxf(0.0, e.global_position.y - _sheet_drag)
		_put_sheet(_sheet_dy)


## 시트 위치 —— dy 만큼 아래로 내려가 있다
func _put_sheet(dy: float) -> void:
	_sheet.offset_top = -_sheet_h + dy
	_sheet.offset_bottom = dy
	_sheet_mask.color.a = 0.55 * clampf(1.0 - dy / maxf(1.0, _sheet_h), 0, 1)


func _slide_sheet(to: float, dur: float, then := Callable()) -> void:
	if _sheet_tw != null:
		_sheet_tw.kill()
	var from := _sheet.offset_bottom
	_sheet_tw = create_tween()
	_sheet_tw.tween_method(_put_sheet, from, to, dur).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	if then.is_valid():
		_sheet_tw.tween_callback(then)


## 내용 높이에 맞춘다 —— 화면의 88% 를 넘으면 그 안에서 스크롤
func _fit_sheet(animate: bool) -> void:
	await get_tree().process_frame
	if not _sheet.visible:
		return
	var sa := _safe_insets()
	var max_h := (size.y - sa.position.y) * 0.88
	var head_h: float = _sheet.get_child(0).get_child(0).get_combined_minimum_size().y
	var body_h: float = _sheet_scroll.get_child(0).get_combined_minimum_size().y
	_sheet_h = minf(max_h, head_h + body_h + sa.size.y + 4)
	var side := maxf(0.0, (size.x - MAX_W) / 2.0)
	_sheet.offset_left = side
	_sheet.offset_right = -side
	if animate:
		_put_sheet(_sheet_h)
		_slide_sheet(0.0, 0.24)
	elif _sheet_tw == null or not _sheet_tw.is_running():
		_put_sheet(0.0)


func _build_tabbar_badges() -> void:
	if run == null:
		return
	var r := run
	var draw_todo := can_act() and (
		(not r.drawn and r.draws_n() > 0) or (not r.picked and not r.pick_list().is_empty())
		or (not r.granted and not r.grant_list().is_empty()) or r.ticket_left() > 0)
	_tabs.draw.badge = 0 if draw_todo and r.over == null else -1
	var nf := 0
	for rc in DB.D.RECDEF:
		if r.can_forge(rc[0]):
			nf += 1
	_tabs.forge.badge = nf if nf > 0 and can_act() else -1
	_tabs.deploy.badge = 0 if r.placed() < 9 and not r.inv.is_empty() and can_act() else -1
	var war_todo := false
	if online == null and r.over == null and r.placed() > 0:
		if r.is_tour_phase():
			war_todo = r.tour == null or r.tour.get("next") == null or r.last_result == null
		else:
			war_todo = not r.quest_done or not r.pvp_done or r.can_next()
	_tabs.war.badge = 0 if war_todo else -1
	for k in _tabs:
		_tabs[k].on = k == page or (k == "more" and page in ["line", "rank"])
		_tabs[k].queue_redraw()


func _build_battle() -> void:
	_battle_layer = ColorRect.new()
	_battle_layer.color = Color("#0b0f1a")
	_battle_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_battle_layer.visible = false
	TouchScroll.block(_battle_layer)
	add_child(_battle_layer)
	_battle = BattleView.new()
	_battle.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_battle_layer.add_child(_battle)
	_battle.ended.connect(_on_battle_ended)
	_battle.inputs_changed.connect(func(inputs):
		if run.battle != null and online == null:
			run.battle.inputs = inputs.duplicate(true)
			run.save())
	_battle_done = UI.btn("결과 정리  ▶", _on_battle_close, "pri", 58)
	_battle_done.add_theme_font_override("font", DB.font_display)
	_battle_done.add_theme_font_size_override("font_size", 20)
	_battle_done.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_battle_done.offset_left = -130
	_battle_done.offset_right = 130
	_battle_done.offset_top = 110
	_battle_done.offset_bottom = 168
	_battle_done.visible = false
	_battle_layer.add_child(_battle_done)


func _build_title() -> void:
	_title = ColorRect.new()
	_title.color = DB.PAL.ink
	_title.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	TouchScroll.block(_title)
	add_child(_title)
	var m := MarginContainer.new()
	m.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var side := maxf(32.0, (size.x - 420.0) / 2.0)
	for s in ["left", "right"]:
		m.add_theme_constant_override("margin_" + s, int(side))
	m.add_theme_constant_override("margin_bottom", 48)
	_title.add_child(m)
	var v := UI.vbox(12)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	m.add_child(v)
	var t := UI.lbl("솔국지", 76, DB.PAL.bamboo, true)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	var s := UI.lbl("삼국지 랜덤 디펜스\n일주일을 살아남아 천하를 얻어라", 15, DB.PAL.bamboo_dim)
	s.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(s)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 36)
	v.add_child(gap)
	if Run.has_save():
		v.add_child(UI.btn("이어 하기", _continue, "pri", 58))
	v.add_child(UI.btn("새 판 시작", _new_game, "" if Run.has_save() else "pri", 58))
	v.add_child(UI.btn("온라인 대전", _go_online, "gold", 58))
	v.add_child(UI.btn("설정", _settings_sheet, "ghost", 50))


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
	if page != "deploy":
		_scroll_keep[page] = _scroll.scroll_vertical
	if pg in ["line", "rank"]:
		_open["more_page"] = pg
	page = pg
	render(true)


func render(new_page := false) -> void:
	if run == null:
		return
	_render_head()
	_build_tabbar_badges()
	var keep := _scroll.scroll_vertical
	var fixed := page == "deploy"
	_scroll.visible = not fixed
	_fixed.visible = fixed
	for c in _body.get_children():
		c.queue_free()
	for c in _fixed.get_children():
		c.queue_free()
	var pg: Control
	match page:
		"draw": pg = _page_draw()
		"forge": pg = _page_forge()
		"deploy": pg = deploy.build()
		"war": pg = _page_war()
		"line": pg = _page_more(_page_line())
		"rank": pg = _page_more(_page_rank())
	pg.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if fixed:
		_fixed.add_child(pg)
	else:
		_body.add_child(pg)
		var want: int = _scroll_keep.get(page, 0) if new_page else keep
		_restore_scroll.call_deferred(want)
	_flush_toasts()


func _restore_scroll(v: int) -> void:
	await get_tree().process_frame
	_scroll.scroll_vertical = v


## 기록 탭 —— 위에 [순위 | 계보] 나눔 탭
func _page_more(body: Control) -> Control:
	var v := UI.vbox(16)
	v.add_child(UI.segmented([["rank", "순위"], ["line", "계보"]], page, func(k): go(k)))
	v.add_child(body)
	return v


func _render_head() -> void:
	_day_lbl.text = "DAY %d · %s요일" % [run.day + 1, Run.DAYNAME[run.day]]
	_sub_lbl.text = (("종료" if run.over.win else "멸망") if run.over else Run.PHASE_N[run.phase])
	if online != null:
		_sub_lbl.text += online.clock_text()
	_phase_bar.cur = run.phase_idx()
	_phase_bar.queue_redraw()
	_pow_lbl.text = "%s명" % Battle.num(run.board_power())
	_info_lbl.clear()
	_info_lbl.append_text("[right][color=#C6AC7C]%d PV[/color] · [color=#D9A64B]%d위[/color] · [color=%s]경고 %d/%d[/color][/right]" % [
		run.my_pv(), run.rank(), "#e0806f" if run.strikes >= 2 else "#8D7B5C", run.strikes, Run.STRIKE_MAX])


func toast(text: String, kind := "") -> void:
	Sfx.play({"gain": "gain", "bad": "deny", "gold": "gain"}.get(kind, "draw"))
	var p := PanelContainer.new()
	var col: Color = {"gold": DB.PAL.gold, "news": DB.PAL.bamboo, "gain": DB.PAL.jade, "bad": DB.PAL.seal}.get(kind, DB.PAL.bamboo_dim)
	var sb := UI.flat(Color("#1b2236", 0.97), Color(col, 0.6), 1, 12, 12)
	sb.border_width_left = 4
	sb.border_color = col
	sb.shadow_color = Color(0, 0, 0, 0.4)
	sb.shadow_size = 8
	p.add_theme_stylebox_override("panel", sb)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := UI.lbl(text, 15, col.lightened(0.3))
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(l)
	_toast_box.add_child(p)
	while _toast_box.get_child_count() > 3:
		_toast_box.get_child(0).free()
	p.modulate.a = 0.0
	var tw := p.create_tween()
	tw.tween_property(p, "modulate:a", 1.0, 0.15)
	tw.tween_interval(2.6)
	tw.tween_property(p, "modulate:a", 0.0, 0.35)
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
	match m:
		"forge": Sfx.play("forge" if r else "deny")
		"do_draw", "pick", "random_grant": Sfx.play("draw")
	if online != null:
		online.send_cmd(m, a)
	changed()
	return r


# ───────── 시트 ─────────

## col 을 주면 제목을 그 색 · 큰 글씨로 (카드 시트 —— 등급색 장수 이름)
func open_sheet(title: String, col := Color(0, 0, 0, 0)) -> VBoxContainer:
	var was := _sheet.visible
	if not _routing:
		_route = {}
		_hist.clear()
	_routing = false
	_update_back()
	if not was:
		Sfx.play("open")
	_sheet_title.text = title
	_sheet_title.add_theme_color_override("font_color", col if col.a > 0 else DB.PAL.paper)
	_sheet_title.add_theme_font_size_override("font_size", 24 if col.a > 0 else 19)
	for c in _sheet_body.get_children():
		c.queue_free()
	_sheet_mask.visible = true
	_sheet.visible = true
	_sheet_scroll.scroll_vertical = 0
	if not was:
		_sheet_mask.color.a = 0.0
		_sheet_h = size.y
		_put_sheet(size.y)
	_fit_sheet(not was)
	return _sheet_body


func close_sheet() -> void:
	_route = {}
	_hist.clear()
	if not _sheet.visible:
		return
	_slide_sheet(_sheet_h, 0.2, func():
		_sheet_mask.visible = false
		_sheet.visible = false)


func sheet_open() -> bool:
	return _sheet.visible


## 카드 시트로 들어간다 —— 다른 카드 시트를 보던 중이면 그 시트를 길에 쌓는다
func _route_enter(kind: String, k: String) -> void:
	var r := {"kind": kind, "k": k}
	if _back_nav:
		_back_nav = false
	elif _sheet.visible and not _route.is_empty() and _route != r:
		_hist.append(_route)
		if _hist.size() > 20:
			_hist.pop_front()
	elif not _sheet.visible:
		_hist.clear()
	_route = r
	_routing = true


## 이전 카드 시트로 (‹ 버튼 · 오른쪽 쓸기). 없으면 아무것도 하지 않는다
func go_back() -> void:
	if _hist.is_empty():
		return
	var r: Dictionary = _hist.pop_back()
	_back_nav = true
	if r.kind == "recipe":
		recipe_sheet(r.k)
	else:
		card_info(r.k)


func _update_back() -> void:
	if _back_btn == null:
		return
	_back_btn.visible = not _hist.is_empty()
	if _back_btn.visible:
		var pk: String = _hist[-1].k
		_back_btn.text = "‹ " + (DB.person(pk) if DB.C[pk].tier > 2 else DB.C[pk].name)


## 시트 위 오른쪽 쓸기 —— 이전 카드 시트로
func _input(e: InputEvent) -> void:
	if not _sheet.visible or _hist.is_empty():
		return
	if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
		if e.pressed:
			_swipe_p = e.position if _sheet.get_global_rect().has_point(e.position) else Vector2.INF
		elif _swipe_p != Vector2.INF:
			var d: Vector2 = e.position - _swipe_p
			_swipe_p = Vector2.INF
			if d.x > 90 and absf(d.y) < d.x * 0.5:
				UI.buzz()
				go_back()


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
	b.add_child(UI.eyebrow("전투 품질 — 병사 수 · 해상도 · 그림자"))
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
	b.add_child(UI.eyebrow("전장 표현"))
	b.add_child(UI.segmented([["3d", "3D (삼국지13)"], ["dots", "점묘 (2D)"]], "dots" if Settings.dots else "3d", func(key):
		Settings.dots = key == "dots"
		Settings.save_cfg()
		if _battle:
			_battle.apply_style()
		_settings_sheet()))
	b.add_child(UI.eyebrow("전장 화풍"))
	b.add_child(UI.segmented([["base", "기본"], ["sumuk", "수묵 (삼국지11 시안)"]], "sumuk" if Settings.sumuk else "base", func(key):
		Settings.sumuk = key == "sumuk"
		Settings.save_cfg()
		if _battle:
			_battle.apply_style()
		_settings_sheet()))
	var cb := CheckButton.new()
	cb.text = "직접 지휘 (전투 중 고유기·군령 버튼을 보인다 —— 꺼도 AI 가 알아서 쓴다)"
	cb.button_pressed = Settings.direct
	cb.custom_minimum_size = Vector2(0, 52)
	cb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	cb.toggled.connect(func(on):
		Settings.direct = on
		Settings.save_cfg())
	b.add_child(cb)
	# 소리 크기 —— 끔 · 작게 · 보통 · 크게
	for which in (["sfx", "bgm"] if Sfx.ENABLED else []):
		var cur: float = Settings.sfx_vol if which == "sfx" else Settings.bgm_vol
		var lv := "0" if cur <= 0.001 else ("1" if cur < 0.4 else ("2" if cur < 0.75 else "3"))
		b.add_child(UI.eyebrow("효과음" if which == "sfx" else "배경 음악"))
		b.add_child(UI.segmented([["0", "끔"], ["1", "작게"], ["2", "보통"], ["3", "크게"]], lv, func(key):
			var v: float = [0.0, 0.3, 0.6, 1.0][int(key)]
			if which == "sfx": Settings.sfx_vol = v
			else: Settings.bgm_vol = v
			Settings.save_cfg()
			Sfx.apply_volume()
			Sfx.play("gain")
			_settings_sheet()))
	var vb := CheckButton.new()
	vb.text = "누를 때 진동"
	vb.button_pressed = Settings.haptics
	vb.custom_minimum_size = Vector2(0, 52)
	vb.toggled.connect(func(on):
		Settings.haptics = on
		Settings.save_cfg())
	b.add_child(vb)


# ───────── 카드 · 아이템 부품 ─────────

func tile(k: String, n := -1, on_tap := Callable()) -> CardTile:
	var t := CardTile.new().setup(k, n)
	t.tapped.connect(on_tap if on_tap.is_valid() else func(id): card_info(id))
	return t


## 카드 격자 —— 폭에 맞춰 두 칸(휴대폰) 이상
func tiles() -> AutoGrid:
	return UI.grid(CardTile.SIZE.x, 8)


func item_box(id: String, n := -1, on_tap := Callable(), amp := 1.0) -> Control:
	var it: Dictionary = DB.IT[id]
	var col := UI.item_col(id)
	var b := Button.new()
	b.custom_minimum_size = Vector2(0, 74)
	b.add_theme_stylebox_override("normal", UI.flat(DB.PAL.ink2, col, 1, 8, 8))
	b.add_theme_stylebox_override("hover", UI.flat(DB.PAL.ink3, col, 1, 8, 8))
	b.add_theme_stylebox_override("pressed", UI.flat(DB.PAL.ink3, DB.PAL.gold, 2, 8, 8))
	if on_tap.is_valid():
		b.pressed.connect(func():
			UI.buzz()
			on_tap.call())
	else:
		b.mouse_filter = Control.MOUSE_FILTER_PASS
	var v := UI.vbox(1)
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.offset_left = 10
	v.offset_right = -8
	v.offset_top = 6
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var top := "%s%s" % [it.name, ("  ×%d" % n) if n > 0 else ""]
	v.add_child(UI.lbl(top, 15, col.lightened(0.2), true))
	v.add_child(UI.lbl("%s · %s" % [it.tag, it.grade], 12, DB.PAL.bamboo_dim))
	v.add_child(UI.lbl(UI.item_text(id, amp) + ("  · 신화 조합 재료" if it.use == "myth" else ""), 12, DB.PAL.bamboo))
	for c in v.get_children():
		c.mouse_filter = Control.MOUSE_FILTER_IGNORE
		c.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		c.clip_text = true
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


## 페이지 머리 —— 큰 제목 + 설명
func _page_head(title: String, sub: String) -> Control:
	var v := UI.vbox(2)
	v.add_child(UI.lbl(title, 22, DB.PAL.paper, true))
	if sub != "":
		v.add_child(UI.hint(sub))
	return v


## 초상 작은 카드 격자 —— 한 줄에 4장
func minis() -> AutoGrid:
	return UI.grid(78, 6)       # 10/30 66 → 78: 한 줄 5장 → 4장, 초상을 크게


func mtile(k: String, n := -1, on_tap := Callable()) -> MiniTile:
	var t := MiniTile.new().setup(k, n)
	t.tapped.connect(on_tap if on_tap.is_valid() else func(id): card_info(id))
	return t


## 지금 조합할 수 있는 상위 카드들의 재료 —— 보유 카드에 ▲ 표시
func _ready_mats() -> Dictionary:
	var out := {}
	for r in DB.D.RECDEF:
		if run.can_forge(r[0]):
			for m in DB.RECOF[r[0]]:
				out[m] = true
	return out


## 조합 카드 하나 (가로 띠용) —— 초상 + 아래 버튼. 되면 바로 조합, 안 되면 재료 시트
func recipe_card(out: String) -> Control:
	var v := UI.vbox(4)
	v.custom_minimum_size = Vector2(86, 0)
	var ok := run.can_forge(out)
	var t := mtile(out, run.pool().get(out, -1), func(id): recipe_sheet(id))
	t.custom_minimum_size = Vector2(86, 112)
	t.lit = ok
	v.add_child(t)
	var miss := run.miss_count(out)
	var b := UI.btn("조합" if ok else ("-%d장" % miss if miss > 0 else "◆필요"), func():
		if ok:
			if act("forge", [out]):
				toast("%s 조합 완료" % DB.C[out].name, "gain")
		else:
			recipe_sheet(out), "pri" if ok else "ghost", 34)
	b.add_theme_font_size_override("font_size", 13)
	v.add_child(b)
	return v


## 조합 시트 —— 제목은 등급색 장수 이름. 결과 카드(특기 칸) · 재료 한 줄(가진 수/필요 수) · 조합 + 상세 버튼 한 줄
func recipe_sheet(out: String) -> void:
	_route_enter("recipe", out)
	var c: Dictionary = DB.C[out]
	var b := open_sheet(c.name, DB.tier_color(out).lightened(0.2))
	var t0 := tile(out, run.pool().get(out, -1))
	t0.custom_minimum_size.y = 84
	b.add_child(t0)
	if c.sk:
		b.add_child(UI.hint("『%s』 %s —— %s" % [c.sk.n, DB.cond_text(c.sk.cond), DB.skill_desc(c)]))
	var row := UI.hbox(6)
	var ml := UI.lbl("재료", 13, DB.PAL.bamboo, true)
	ml.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(ml)
	var m := Run.mat_count(DB.RECOF[out])
	for q in m:
		var got := run.have(q)
		var t := mtile(q, -1)
		t.custom_minimum_size = Vector2(56, 78)
		t.badge = "%d/%d" % [got, m[q]]
		t.badge_col = Color(DB.PAL.jade, 0.9) if got >= m[q] else Color(DB.PAL.seal, 0.9)
		t.dim = got <= 0
		row.add_child(t)
	b.add_child(row)
	var ni = Run.need_item(out)
	if ni != null:
		var have_it: bool = run.bag.get(ni, 0) > 0
		b.add_child(UI.icon_chip("item", "유니크 %s — %s" % [DB.IT[ni].name, "보유" if have_it else "없음 · 후반 보급"], DB.PAL.gold if have_it else DB.PAL.seal, func(): _item_sheet(ni)))
	var ok := run.can_forge(out)
	var br := UI.hbox(6)
	var fb := UI.btn("조합하기" if ok else "재료 부족 %d장" % run.miss_count(out), func():
		if act("forge", [out]):
			toast("%s 조합 완료" % c.name, "gain")
			if _hist.is_empty():
				close_sheet()
			else:
				go_back(), "pri" if ok else "", 44)
	fb.disabled = not ok
	fb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	br.add_child(fb)
	var pn := forge_tree.pinned(out)
	var pb := UI.btn("갈무리 해제" if pn else "갈무리", func():
		forge_tree.toggle(out)
		close_sheet(), "ghost" if pn else "", 44)
	pb.custom_minimum_size.x = 96
	br.add_child(pb)
	var ib := UI.btn("상세", func(): card_info(out), "ghost", 44)
	ib.custom_minimum_size.x = 72
	br.add_child(ib)
	b.add_child(br)


# ───────── 징집 ─────────

func _page_draw() -> Control:
	if run.over:
		return _over_panel()
	var v := UI.vbox(16)
	var n := run.draws_n()
	if run.day == 6:
		v.add_child(UI.panel(UI.rich("[b][color=#D9A64B]결전의 날[/color][/b] — 더 이상 농민을 징집하지 않는다. 명장만이 소환된다.", 14), 10))

	# 할 일 —— 기호 타일 한 줄
	var acts := UI.grid(80, 6)
	if n > 0:
		acts.add_child(UI.tile_act("draw", "징집", "기본패 %d장" % n, func(): act("do_draw"), "pri", run.drawn, not can_act()))
	var pl := run.pick_list()
	if not pl.is_empty():
		acts.add_child(UI.tile_act("pick", "선택권", " ".join(pl.map(func(p): return "%s%d" % [DB.TIER[p.t].n, p.n])), func():
			act("begin_picks", ["phase", -1])
			if not run.ticket_tiers().is_empty():
				picker(run.ticket_tiers()[0]), "", run.picked, not can_act()))
	var rg := run.grant_list()
	if not rg.is_empty():
		acts.add_child(UI.tile_act("grant", "배급", " ".join(rg.map(func(p): return "%s%d" % [DB.TIER[mini_n(Run.FREE_TIER_CAP, int(p.t))].n, p.n])), func():
			for k in act("random_grant"):
				toast("%s 배급 · %s" % [DB.C[k].name, DB.TIER[DB.C[k].tier].n], "gain"), "", run.granted, not can_act()))
	# 선택권 —— 등급마다 타일 하나, 할 일 줄 안에 (11/2 사용자: 따로 줄을 만들면 보유 패가 자꾸 아래로 밀렸다)
	for t in run.ticket_tiers():
		acts.add_child(UI.tile_act("gift", "%s ×%d" % [DB.TIER[t].n, int(run.tickets[str(t)])], "%d종 중 고르기" % DB.by_tier(t).size(),
			func(): picker(t), "gold", false, not can_act()))
	v.add_child(acts)

	# 보급품 · 소식 —— 한 줄 칩
	var chips := UI.hbox(6)
	if run.last_item != null:
		var it: Dictionary = DB.IT[run.last_item]
		var ic := UI.icon_chip("item", "%s · %s" % [it.name, UI.item_text(run.last_item)], UI.item_col(run.last_item), func(): _item_sheet(run.last_item))
		ic.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		ic.size_flags_stretch_ratio = 2.0
		chips.add_child(ic)
	if not run.news.is_empty():
		var nc := UI.icon_chip("news", "소식 %d" % run.news.size(), DB.PAL.bamboo, _news_sheet)
		nc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		chips.add_child(nc)
	if chips.get_child_count() > 0:
		v.add_child(chips)

	# 보유 카드 —— 징집 화면은 징집 · 선택권 · 내 패만 (11/2 사용자 P안: 조합은 조합 탭이 맡는다. 탭 배지 · ▲ 표시가 신호)
	var p := run.pool()
	var tot := 0
	for k in p:
		tot += p[k]
	var mats := _ready_mats()
	var hand := minis()
	for k in Run.sort_cards(p.keys()):
		var t := mtile(k, p[k])
		if run.on_board(k) > 0:
			t.badge = "편성 %d" % run.on_board(k)
			t.badge_col = Color(DB.PAL.ink4, 0.95)
		t.up = mats.has(k)
		hand.add_child(t)
	var hv := UI.vbox(6)
	hv.add_child(UI.head("보유 %d장 · %d PV" % [tot, run.my_pv()], "▲ 지금 조합 재료"))
	hv.add_child(hand if tot > 0 else UI.hint("보유 카드가 없다. 위의 징집부터."))
	v.add_child(hv)
	return v


func mini_n(a: int, b: int) -> int:
	return a if a < b else b


func _news_sheet() -> void:
	var b := open_sheet("전황 소식")
	for nw in run.news:
		b.add_child(UI.rich("[b]%s[/b]가 %s [color=#8D7B5C]%s 등용[/color]" % [nw.who, UI.card_bb(nw.unit), DB.TIER[DB.C[nw.unit].tier].n], 15))


func _item_sheet(id: String) -> void:
	var it: Dictionary = DB.IT[id]
	var b := open_sheet(it.name)
	b.add_child(item_box(id, run.bag.get(id, 0)))
	b.add_child(UI.hint("%s 전용 · %s. 편성 탭에서 칸을 눌러 장착한다.%s" % [it.tag, it.grade, " 신화 장수 조합 재료이기도 하다." if it.use == "myth" else ""]))
	# 유니크 —— 이 아이템으로 만드는 신화 장수 (11/2 사용자). 누르면 조합 시트
	var myth := DB.by_tier(8).filter(func(k): return Run.need_item(k) == id)
	if not myth.is_empty():
		b.add_child(UI.eyebrow("이 아이템이 들어가는 신화 장수 %d" % myth.size()))
		var g := minis()
		for k in myth:
			g.add_child(mtile(k, run.pool().get(k, -1), func(x): recipe_sheet(x)))
		b.add_child(g)
	b.add_child(UI.btn("편성하러 가기", func():
		close_sheet()
		go("deploy"), "pri"))


## 선택권 —— 그 등급 선택권으로 한 장씩 고른다. 그 등급을 다 쓰면 닫는다
func picker(t: int) -> void:
	var left := int(run.tickets.get(str(t), 0))
	if left <= 0 or not can_act():
		close_sheet()
		return
	var b := open_sheet("%s 선택권 — 남은 %d회" % [DB.TIER[t].n, left])
	b.add_child(UI.hint("%d종 중에서 고른다.%s" % [DB.by_tier(t).size(), " 무상으로 받는 패의 천장이다. 초월부터는 조합으로만 오른다." if t >= Run.FREE_TIER_CAP else ""]))
	for tag in DB.D.TAGORDER:
		var ks := Run.by_tier_tag(t, tag)
		if ks.is_empty():
			continue
		b.add_child(UI.eyebrow("%s %d종" % [tag, ks.size()]))
		var f := tiles()
		for k in ks:
			var c: Dictionary = DB.C[k]
			var tl := tile(k, run.pool().get(k, -1), func(id):
				if act("pick", [id]):
					toast("%s 획득 · %s" % [DB.C[id].name, DB.TIER[DB.C[id].tier].n], "gain")
				picker(t))
			tl.note = "공%d 방%d%s 속%d" % [c.atk, c["def"], (" 책%d" % c["int"]) if c["int"] > 0 else "", c.spd]
			f.add_child(tl)
		b.add_child(f)


## 지금 손댈 수 있는가 —— 온라인은 준비 시간에만
func can_act() -> bool:
	return online == null or online.can_act()


# ───────── 카드 상세 ─────────

func card_info(k: String) -> void:
	_route_enter("card", k)
	var c: Dictionary = DB.C[k]
	var p := run.pool()
	var b := open_sheet(c.name, DB.tier_color(k).lightened(0.2))
	var top := UI.hbox(14)
	var big := CardView.new().setup(k, Vector2(132, 188))
	big.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	top.add_child(big)
	# 초상 오른쪽 —— 능력치 (등급 · 병종 · 세력 · PV · 병력은 테두리색 · 기호로 안다)
	var st := UI.vbox(6)
	st.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var sg := GridContainer.new()
	sg.columns = 4
	sg.add_theme_constant_override("h_separation", 6)
	sg.add_theme_constant_override("v_separation", 6)
	# 공격은 하나로 —— 책략이 더 높은 장수는 책략 값을 파랑으로, 아니면 물리 공격을 빨강으로
	var magic: bool = c["int"] > c.atk
	for pair in [["공격", c["int"] if magic else c.atk], ["방어", c["def"]], ["책방", c.res], ["속도", c.spd]]:
		var sv := UI.stat(str(int(pair[1])), pair[0])
		if pair[0] == "공격":
			(sv.get_child(0) as Label).add_theme_color_override("font_color", Color("#6fa8ff") if magic else Color("#ff6b5a"))
			(sv.get_child(1) as Label).text = "책략 공격" if magic else "물리 공격"
		var sp := UI.panel(sv, 2)
		sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sg.add_child(sp)
	sg.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	st.add_child(sg)
	# 특기판 —— 모든 특기 칸, 가진 것만 계열 색
	st.add_child(TraitBoard.new().setup(k))
	var uc = UI.unique_chips(k)
	if uc != null:
		var uh := UI.hbox(6)
		var ul := UI.lbl("고유", 12, Color("#e8c25a"), true)
		ul.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		uh.add_child(ul)
		uc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		uh.add_child(uc)
		st.add_child(uh)
	var gap := Control.new()
	gap.custom_minimum_size.y = 2
	st.add_child(gap)
	st.add_child(UI.rich("[b][color=%s]보유 %d장[/color][/b]" % ["#8fd4c2" if p.get(k, 0) > 0 else "#e0806f", p.get(k, 0)], 14))
	top.add_child(st)
	b.add_child(top)
	# 고유 특기 —— 접지 않고 바로 보인다 (이름 · 수치)
	for t in DB.trait_list(k):
		if t.unique:
			var ub := "[color=#FFD76E][b]%s[/b][/color]" % t.name
			if t.mt != "":
				ub += "\n[color=#8FD4C2]%s[/color]" % t.mt
			b.add_child(UI.panel(UI.rich(ub, 14), 8))
	if not c.get("sks", []).is_empty():
		var sl := []
		for x in c.sks:
			sl.append("[color=#D9A64B]『%s』[/color]  [color=#8D7B5C]%s[/color]\n%s" % [x.n, DB.cond_text(x.cond), DB.skill_desc(c, x)])
		b.add_child(UI.rich("\n".join(sl), 13))
	var u = DB.ult_of(k) if c.tier >= 6 else null
	if u != null:
		b.add_child(UI.rich("[color=#ffd76e][b]고유기 『%s』[/b][/color]  “%s”\n%s" % [u.name, u.shout, UI.ult_desc(u)], 14))
	var tl := DB.trait_list(k)
	if not tl.is_empty():
		# 왼쪽 칸 = 특기 이름+레벨, 오른쪽 = 설명(—— 에서 줄바꿈)과 그 아래 수치. 오른쪽 칸 왼끝이 맞는다
		var tg := _info_grid()
		for t in tl.filter(func(x): return not x.unique):
			var body := "[color=#C6AC7C]%s[/color]%s" % [(t.d as String).replace(" —— ", "\n"), ("\n[color=#8FD4C2]%s[/color]" % t.mt) if t.mt != "" else ""]
			_info_row(tg, "[color=#8FD4C2][b]%s[/b][/color][color=#D9A64B]%d[/color]%s" % [t.name, t.lv, "\n[color=#8D7B5C]단체[/color]" if t.group else ""], body)
		b.add_child(_fold_sec("card_traits", "특기 설명", tg))
	var ag := _info_grid()
	_info_row(ag, "[color=#8fd4c2]선호[/color]", "%s\n[color=#C6AC7C]%s[/color]" % [UI.aff_zones(c.tag, "pref"), UI.aff_desc(c.tag, "pref")])
	_info_row(ag, "[color=#e0806f]어색[/color]", "%s\n[color=#C6AC7C]%s[/color]" % [UI.aff_zones(c.tag, "bad"), UI.aff_desc(c.tag, "bad")])
	b.add_child(_fold_sec("card_aff", "선호 대열", ag))

	b.add_child(UI.eyebrow("이 카드를 만드는 법"))
	if DB.RECOF.has(k):
		b.add_child(_up_row(k))
	else:
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


## 접는 칸 —— 머리줄을 누르면 열고 닫는다. 기본은 닫힘, 연 상태는 _open[key] 에 남아 다른 카드에서도 이어진다
func _fold_sec(key: String, title: String, body: Control) -> Control:
	var v := UI.vbox(6)
	var hb := Button.new()
	hb.flat = true
	hb.alignment = HORIZONTAL_ALIGNMENT_LEFT
	hb.custom_minimum_size.y = 36
	hb.add_theme_font_override("font", DB.font_display)
	hb.add_theme_font_size_override("font_size", 14)
	hb.add_theme_color_override("font_color", DB.PAL.bamboo)
	var upd := func():
		var on: bool = _open.get(key, false)
		hb.text = ("▾ " if on else "▸ ") + title
		body.visible = on
	hb.pressed.connect(func():
		UI.buzz()
		_open[key] = not _open.get(key, false)
		upd.call())
	upd.call()
	v.add_child(hb)
	v.add_child(body)
	return v


## 상세 시트의 두 칸 표 —— 왼쪽 머리말, 오른쪽 내용 (오른쪽 줄들의 왼끝이 맞는다)
func _info_grid() -> GridContainer:
	var g := GridContainer.new()
	g.columns = 2
	g.add_theme_constant_override("h_separation", 10)
	g.add_theme_constant_override("v_separation", 8)
	return g


func _info_row(g: GridContainer, head: String, body: String) -> void:
	var h := UI.rich(head, 14)
	h.autowrap_mode = TextServer.AUTOWRAP_OFF
	h.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	g.add_child(h)
	var r := UI.rich(body, 13)
	r.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	g.add_child(r)


## 상세 시트의 조합 줄 —— 재료 칩을 누르면 그 카드 상세로 넘어간다
func _up_row(out: String) -> Control:
	var v := UI.vbox(8)
	var h := UI.hbox(10)
	var t := tile(out, run.pool().get(out, -1))
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(t)
	if run.can_forge(out):
		var me := _sheet_title.text
		var fb := UI.btn("조합", func():
			if act("forge", [out]):
				toast("%s 조합 완료" % DB.C[out].name, "gain")
				# 지금 보던 카드 상세를 다시 연다 (지나온 길은 그대로)
				if _route.get("kind", "") == "card":
					_back_nav = true
					card_info(_route.k)
					return
				for kk in DB.C:
					if DB.C[kk].name == me:
						card_info(kk)
						return
				close_sheet(), "pri", 48)
		fb.custom_minimum_size = Vector2(84, 48)
		fb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(fb)
	# 갈무리 —— 보유하지 않은 장수도 디테일창에서 바로 (11/2 사용자)
	var pn := forge_tree.pinned(out)
	var pb := UI.btn("갈무리 해제" if pn else "갈무리", func():
		forge_tree.toggle(out)
		_back_nav = true
		card_info(_route.get("k", out)), "ghost" if pn else "", 48)
	pb.custom_minimum_size = Vector2(96, 48)
	pb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(pb)
	v.add_child(h)
	var chips := UI.flow(6)
	var m := Run.mat_count(DB.RECOF[out])
	for q in m:
		var got := run.have(q)
		var ok: bool = got >= m[q]
		var cb := UI.btn("%s %s %d/%d" % ["✔" if ok else "✘", DB.C[q].name, got, m[q]], func(): card_info(q), "", 40)
		cb.add_theme_color_override("font_color", Color("#8fd4c2") if ok else Color("#e0806f"))
		cb.add_theme_font_size_override("font_size", 14)
		chips.add_child(cb)
	var ni = Run.need_item(out)
	if ni != null:
		var ok: bool = run.bag.get(ni, 0) > 0
		chips.add_child(UI.lbl("%s ◆%s %d/1" % ["✔" if ok else "✘", DB.IT[ni].name, run.bag.get(ni, 0)], 14, Color("#d59700") if ok else Color("#e0806f")))
	v.add_child(chips)
	return UI.panel(v, 10)


# ───────── 조합 ─────────

func _toggle(key: String, default := false) -> void:
	_open[key] = not _open.get(key, default)
	render()


func _page_forge() -> Control:
	var v := UI.vbox(14)
	v.add_child(UI.lbl("조합", 22, DB.PAL.paper, true))
	v.add_child(forge_tree.build())
	# 거르기 —— 병종 · 등급 (가로로 넘기는 칩 두 줄)
	var st := UI.strip(6)
	for t in [""] + DB.D.TAGORDER:
		var n: int = DB.D.RECDEF.filter(func(r): return run.can_forge(r[0]) and (t == "" or DB.C[r[0]].tag == t)).size()
		st[1].add_child(UI.chip(("전체" if t == "" else t) + (" %d" % n if n > 0 else ""), forge_tag == t, func():
			forge_tag = t
			_forge_more = 0
			render(), 36))
	v.add_child(st[0])
	var st2 := UI.strip(6)
	for t in [0, 2, 3, 4, 5, 6, 7, 8]:
		st2[1].add_child(UI.chip("모든 등급" if t == 0 else DB.TIER[t].n, forge_tier == t, func():
			forge_tier = t
			_forge_more = 0
			render(), 36))
	v.add_child(st2[0])
	var lst: Array = DB.D.RECDEF.filter(func(r): return (forge_tag == "" or DB.C[r[0]].tag == forge_tag) and (forge_tier == 0 or DB.C[r[0]].tier == forge_tier))
	# 지금 되는 것 —— 가로 띠, 버튼 한 번에 조합
	var ready: Array = lst.filter(func(r): return run.can_forge(r[0]))
	ready.sort_custom(func(x, y): return DB.C[x[0]].tier > DB.C[y[0]].tier)
	if not ready.is_empty():
		var sec := UI.vbox(6)
		sec.add_child(UI.head("지금 조합 가능 %d" % ready.size(), "버튼 한 번에 조합 ›"))
		var rs := UI.strip(8)
		for r in ready:
			rs[1].add_child(recipe_card(r[0]))
		sec.add_child(rs[0])
		v.add_child(sec)
	# 나머지 —— 가까운 순 (모자란 장수 적은 것 먼저, 같으면 높은 등급)
	lst = lst.filter(func(r): return not run.can_forge(r[0]))
	lst.sort_custom(func(x, y):
		var a := run.miss_count(x[0])
		var b2 := run.miss_count(y[0])
		if a != b2:
			return a < b2
		return DB.C[x[0]].tier > DB.C[y[0]].tier)
	var show_n := 40 + _forge_more
	var g := minis()
	for i in mini_n(show_n, lst.size()):
		var out: String = lst[i][0]
		var t := mtile(out, run.pool().get(out, -1), func(id): recipe_sheet(id))
		var miss := run.miss_count(out)
		t.lit = run.can_forge(out)
		if t.lit:
			t.badge = "조합"
			t.badge_col = Color(DB.PAL.jade, 0.95)
		elif miss > 0:
			t.badge = "-%d" % miss
			t.badge_col = Color(DB.PAL.seal, 0.9) if miss <= 1 else Color(DB.PAL.ink, 0.85)
		else:
			t.badge = "◆"
			t.badge_col = Color(DB.PAL.gold.darkened(0.3), 0.95)
		g.add_child(t)
	var sec2 := UI.vbox(6)
	sec2.add_child(UI.head(("나머지 %d — 가까운 순" if not ready.is_empty() else "조합법 %d — 가까운 순") % lst.size(), "-n 모자람 · ◆ 유니크"))
	sec2.add_child(g if not lst.is_empty() else UI.hint("이 조건의 조합법이 없다."))
	if lst.size() > show_n:
		sec2.add_child(UI.btn("더 보기 (%d개 남음)" % (lst.size() - show_n), func():
			_forge_more += 40
			render(), "ghost", 46))
	v.add_child(sec2)
	return v


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
		v.add_child(_page_head("최종 토너먼트 · %s" % Run.ROUNDNM[run.tour.round],
			"상대 %s · %d PV · 내 전력 %d PV — 지면 그대로 끝난다." % [foe.name, foe.pv, run.my_pv()]))
		if run.last_result != null and run.tour.next != null:
			v.add_child(_result_panel())
			v.add_child(UI.btn("%s 진출" % Run.ROUNDNM[run.tour.round + 1], func():
				run.tour_advance()
				changed(), "pri", 60))
		else:
			v.add_child(UI.act("출진" if placed > 0 else "편성이 비어 있다", "%d/9칸 · %s명" % [placed, Battle.num(run.board_power())],
				func(): _start("tour"), "warn", placed == 0))
		v.add_child(_bracket())
	else:
		v.add_child(_page_head("%s요일 %s" % [Run.DAYNAME[run.day], Run.PHASE_N[run.phase]],
			"토벌과 임의 세력 대전을 한 번씩 치른다. 토벌 실패는 경고로 쌓인다 — 현재 %d/%d회." % [run.strikes, Run.STRIKE_MAX]))
		v.add_child(UI.act("① 토벌 완료" if run.quest_done else "① 토벌 — %s" % run.quest_name(),
			"다음은 대전이다" if run.quest_done else "적 %d PV · 승리 시 기본패 %d장 · 실패 시 경고" % [run.quest_pv(), DB.D.QUEST_BASE[run.day]],
			func(): _start("quest"), "warn", run.quest_done or placed == 0))
		v.add_child(UI.act("② 대전 완료" if run.pvp_done else "② 대전 — 임의 세력",
			"토벌을 먼저 끝내야 열린다" if not run.quest_done else "승리 시 기본패 %d장 · 패배해도 %d장" % [DB.D.PVP_BASE.win, DB.D.PVP_BASE.lose],
			func(): _start("pvp"), "pri", run.pvp_done or placed == 0 or not run.quest_done))
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
	v.add_child(UI.hint("전투는 자동으로 흘러간다 —— 고유기 · 군령은 AI 가 알아서 쓴다. 덱과 배치가 승부를 가른다. 두 손가락으로 확대·회전, 한 손가락으로 이동. 직접 지휘는 설정 또는 전투 중 ⋯ 메뉴에서 켠다."))
	return v


func _result_panel() -> Control:
	var r: Dictionary = run.last_result
	var col := "#8fd4c2" if r.win else "#e0806f"
	var s := "[font_size=19][b][color=%s]%s[/color][/b][/font_size]  %s\n잔존 %d부대 대 %d부대 · %d턴" % [
		col, "무승부" if r.draw else ("승리" if r.win else "패배"), r.title, r.left, r.eLeft, r.turns]
	if r.mvp != "":
		s += " · 수훈갑 %s" % r.mvp
	if run.last_spoil != null:
		s += "\n[color=#C6AC7C]기본패 %d장 획득[/color]" % run.last_spoil.n
	if run.ticket_left() > 0:
		s += "\n[color=#D9A64B]선택권 %d장 — 징집 탭에서[/color]" % run.ticket_left()
	return UI.panel(UI.rich(s, 15), 14)


func _bracket() -> Control:
	var v := UI.vbox(10)
	var t: Dictionary = run.tour
	for r in 3:
		var ms = t.res[r]
		if ms == null:
			continue
		var rv := UI.vbox(2)
		rv.add_child(UI.lbl(Run.ROUNDNM[r], 14, DB.PAL.bamboo, true))
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
			rv.add_child(UI.rich("%s%s  대  %s%s" % ["[bgcolor=#33405F]" if cur else "", nm.call(m.a), nm.call(m.b), "[/bgcolor]" if cur else ""], 14))
		v.add_child(rv)
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
	_hide_report()
	_battle_layer.visible = true
	Settings.apply_port(_battle.port)
	_battle.play(bt, Settings.direct)


## 온라인 —— 서버가 계산한 결과를 재생만 한다
func show_battle(res: Dictionary, last: bool, kind := "") -> void:
	close_sheet()
	_battle_res = null
	_battle_done.visible = false
	_hide_report()
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
	UI.buzz(30)
	await get_tree().create_timer(1.4).timeout      # 승전 · 패전 도장을 먼저 보이고
	if not _battle_layer.visible or not is_same(_battle.res, res):     # 같은 전투인지 —— 내용 비교(!=)는 큰 결과에 느리다
		return
	_show_report(res)
	_battle_done.visible = true


## 결과표 —— 화면 가운데, 아래에 [결과 정리] 버튼
func _show_report(res: Dictionary) -> void:
	_hide_report()
	_report = BattleReport.make(res)
	var w := minf(size.x - 24.0, 460.0)
	_report.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_report.offset_left = -w / 2
	_report.offset_right = w / 2
	_report.offset_top = 96
	_battle_layer.add_child(_report)
	_battle_layer.move_child(_battle_done, -1)
	_battle_done.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_battle_done.offset_left = -130
	_battle_done.offset_right = 130
	_battle_done.offset_top = -150
	_battle_done.offset_bottom = -92


func _hide_report() -> void:
	if _report:
		_report.queue_free()
		_report = null


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
	tbl.add_theme_constant_override("h_separation", 18)
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
	var tc := CenterContainer.new()
	tc.add_child(tbl)
	v.add_child(UI.sect("등급", UI.panel(tc)))
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
	v.add_child(UI.sect("계보 진행도", UI.panel(prog)))

	var lv0 := UI.vbox(8)
	for tag in DB.D.TAGORDER:
		var key: String = "line:" + tag
		var open: bool = _open.get(key, false)
		var cnt := [6, 7, 8].map(func(t): return Run.by_tier_tag(t, tag).size())
		var own_n := 0
		for k in p:
			if DB.C[k].tag == tag:
				own_n += 1
		lv0.add_child(UI.fold(tag, "보유 %d종 · 초월 %d 불멸 %d 신화 %d" % [own_n, cnt[0], cnt[1], cnt[2]], open, func(): _toggle(key)))
		if not open:
			continue
		var lv := UI.vbox(8)
		for t in range(8, 0, -1):
			var ks := Run.by_tier_tag(t, tag)
			if ks.is_empty():
				continue
			lv.add_child(UI.lbl(DB.TIER[t].n, 14, DB.TIER[t].c, true))
			var f := UI.flow(6)
			for k in ks:
				var c: Dictionary = DB.C[k]
				var has: bool = p.get(k, 0) > 0
				var b := UI.btn("%s%s%s" % [c.name, "★" if c.kind == "myth" else "", (" ×%d" % p[k]) if has else ""], func(): card_info(k), "", 42)
				b.add_theme_font_size_override("font_size", 14)
				b.add_theme_color_override("font_color", DB.tier_color(k) if has else Color(DB.PAL.paper, 0.55))
				if has:
					b.add_theme_stylebox_override("normal", UI.flat(DB.PAL.ink3, DB.tier_color(k), 1, 8, 10))
				f.add_child(b)
			lv.add_child(f)
		lv0.add_child(UI.panel(lv))
	v.add_child(UI.sect("병종 계보 — 눌러서 펼친다", lv0))

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
	mv.add_child(UI.hint("모든 신화는 유니크 아이템을 함께 소모하며, 그 아이템은 완성된 장수에게 영구히 장착된다. 불멸을 거치지 않는 경로도 있다. 이름을 누르면 상세."))
	for key in g:
		var pv := UI.vbox(8)
		pv.add_child(UI.lbl("%s — %d종" % [key, g[key].size()], 15, DB.PAL.bamboo, true))
		for k in g[key]:
			var r := UI.rich("[url=%s]%s[/url]  [color=#8D7B5C]%s · %d PV[/color]\n%s" % [k, UI.card_bb(k), DB.C[k].tag, DB.C[k].pv, mats_bb(k)], 14)
			r.meta_clicked.connect(func(m): card_info(str(m)))
			pv.add_child(r)
		mv.add_child(UI.panel(pv, 12))
	v.add_child(UI.sect("신화 %d종 — 경로 %d갈래" % [DB.by_tier(8).size(), g.size()], mv))
	return v


# ───────── 순위 ─────────

func _standings() -> Control:
	var rows := [{"name": "나", "epi": "%d승 %d패%s" % [run.my_w, run.my_l, (" · 경고 %d" % run.strikes) if run.strikes else ""],
		"fac": "촉", "pv": run.my_pv(), "me": true, "dead": run.over != null and not run.over.win}]
	for b in run.bots:
		rows.append({"name": b.name, "epi": b.epi, "fac": b.fac, "pv": roundi(b.pv), "me": false, "dead": false})
	rows.sort_custom(func(a, b): return a.pv > b.pv)
	var v := UI.vbox(6)
	for i in rows.size():
		var r: Dictionary = rows[i]
		var h := UI.hbox(12)
		var nl := UI.lbl(str(i + 1), 20, DB.PAL.gold if r.me else DB.PAL.bamboo_dim, true)
		nl.custom_minimum_size = Vector2(22, 0)
		nl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		h.add_child(nl)
		var fl := UI.lbl(r.fac, 14, Color.WHITE, true)
		fl.add_theme_stylebox_override("normal", UI.flat(DB.fac_color(r.fac), DB.fac_color(r.fac), 0, 4, 4))
		fl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(fl)
		var nv := UI.vbox(0)
		nv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		nv.add_child(UI.lbl(r.name, 16, DB.PAL.gold if r.me else DB.PAL.paper, true))
		var el := UI.lbl(r.epi, 12, DB.PAL.bamboo_dim)
		el.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		el.clip_text = true
		nv.add_child(el)
		h.add_child(nv)
		var pl := UI.lbl("멸망" if r.dead else "%d PV" % r.pv, 16, DB.PAL.seal if r.dead else DB.PAL.bamboo, true)
		pl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(pl)
		var pnl := UI.panel(h, 10)
		if r.me:
			pnl.add_theme_stylebox_override("panel", UI.flat(DB.PAL.ink3, DB.PAL.gold, 1, 8, 10))
		v.add_child(pnl)
	return v


func _page_rank() -> Control:
	var v := UI.vbox(16)
	var sr := UI.grid(80, 4)
	sr.add_child(UI.stat("%d위" % run.rank(), "8인 중"))
	sr.add_child(UI.stat(str(run.my_pv()), "내 전력"))
	sr.add_child(UI.stat("%d승 %d패" % [run.my_w, run.my_l], "전적"))
	sr.add_child(UI.stat("%d / %d" % [run.strikes, Run.STRIKE_MAX], "경고"))
	v.add_child(UI.sect("군웅 할거 · %s요일 %s" % [Run.DAYNAME[run.day], Run.PHASE_N[run.phase]], UI.panel(sr)))
	v.add_child(UI.sect("순위", _standings()))
	var bv := UI.vbox(6)
	var bs: Array = run.bots.duplicate()
	bs.sort_custom(func(a, b): return a.pv > b.pv)
	for b in bs:
		bv.add_child(UI.rich("[b]%s[/b]  [color=#8D7B5C]%s 편중 · %s%s[/color]" % [b.name, b.style, DB.FORM[DB.STYLE_FORM[b.style]].n,
			(" · 토벌 실패 %d" % b.strikes) if b.strikes else ""]))
	bv.add_child(UI.hint("모든 토벌 실패가 경고로 쌓이며, 3일차부터 한도에 닿으면 멸망한다. 봇 세력은 멸망하지 않고 전력 손실로만 대가를 치른다."))
	v.add_child(UI.sect("세력 성향", UI.panel(bv)))
	return v


func _over_panel() -> Control:
	var v := UI.vbox(16)
	var o: Dictionary = run.over
	var pv := UI.vbox(8)
	var t := UI.lbl("우승" if o.win else "멸망", 48, DB.PAL.jade if o.win else DB.PAL.seal, true)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pv.add_child(t)
	var m := UI.lbl(o.msg, 16, DB.PAL.paper)
	m.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	m.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	pv.add_child(m)
	var s := UI.lbl("최종 %s명 · %d PV · %d승 %d패" % [Battle.num(run.board_power()), run.my_pv(), run.my_w, run.my_l], 15, DB.PAL.bamboo)
	s.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	s.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
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
	if a.has("gopen"):
		for key in str(a.gopen).split(","):
			_open[key] = true
		render()
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
		# 쉼표로 여러 시트를 차례로 열 수 있다 (카드 시트 길 점검: --gsheet=card:c39,recipe:c11)
		var parts: PackedStringArray = str(a.gsheet).split(",")
		for pi in range(parts.size() - 1):
			var kv0: PackedStringArray = parts[pi].split(":")
			if kv0[0] == "card": card_info(kv0[1])
			elif kv0[0] == "recipe": recipe_sheet(kv0[1])
		var kv: PackedStringArray = parts[parts.size() - 1].split(":")
		match kv[0]:
			"card": card_info(kv[1])
			"recipe": recipe_sheet(kv[1])
			"item": _item_sheet(kv[1])
			"slot": deploy.slot_sheet(int(kv[1]))
			"menu": _menu()
			"settings": _settings_sheet()
			"pick":
				act("begin_picks", ["phase", -1])
				if not run.ticket_tiers().is_empty():
					picker(run.ticket_tiers()[0])
			"online": _go_online()
	if a.has("gtitle"):
		_title.visible = true
	if a.has("gdots"):          # 점검용 —— 전장 표현 (1 점묘 · 0 3D, 저장하지 않는다)
		Settings.dots = a.gdots != "0"
	if a.has("gsumuk"):          # 점검용 —— 수묵 화풍으로 (저장하지 않는다)
		Settings.sumuk = a.gsumuk != "0"
		if _battle:
			_battle.apply_style()
	if a.has("gbattle"):
		await get_tree().process_frame
		_start(a.gbattle)
		if a.has("speed"):
			_battle._set_speed(float(a.speed))
		if a.has("gmenu"):
			_battle.toggle_menu()
		if a.has("gcam"):       # 점검용 카메라 —— 거리:높이각
			var cv: PackedStringArray = str(a.gcam).split(":")
			await get_tree().create_timer(4.0).timeout
			_battle.field.focus(_battle.field.order[0])
			_battle.field.want_dist = float(cv[0])
			if cv.size() > 1:
				_battle.field.want_pitch = float(cv[1])
		if a.has("gclose"):
			# 끝나면 1초 뒤 결과 정리를 누른 것처럼 —— 저장·보상 흐름 점검
			await _battle.ended
			await get_tree().create_timer(1.0).timeout
			_on_battle_close()
			print("전투 정리: %s · 길이 %.1f초(배율 %.2f) · 토벌 %s · 대전 %s · 경고 %d · 선택권 %d · 저장 %s" % [run.last_result.title, _battle.end_clock, _battle.pace,
				run.quest_done, run.pvp_done, run.strikes, run.ticket_left(), Run.has_save()])
	if a.has("gtouch"):
		await _touch_test()
		get_tree().quit()
		return
	if a.has("gshot"):
		await get_tree().create_timer(float(a.get("after", "1.0"))).timeout
		if a.has("scroll"):
			_scroll.scroll_vertical = int(a.scroll)
			await get_tree().process_frame
		# --frames=N --every=초 —— 연속 장면을 경로_0.png, 경로_1.png … 로
		var nf := int(a.get("frames", "1"))
		for i in nf:
			if i > 0:
				await get_tree().create_timer(float(a.get("every", "0.5"))).timeout
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(a.gshot if nf == 1 else str(a.gshot).replace(".png", "_%d.png" % i))
		get_tree().quit()


## 손가락 점검 (--gtouch) —— 버튼 위에서 끌면 스크롤만 되고 버튼은 눌리지 않는지, 그냥 누르면 눌리는지
func _touch_test() -> void:
	var ok := true
	await get_tree().create_timer(0.5).timeout
	go("forge")
	await get_tree().create_timer(0.3).timeout
	var fb: Button = _find_btn(_body, "조합")
	var before := run.pool().duplicate()
	var y0 := _scroll.scroll_vertical
	var p := fb.get_global_rect().get_center()
	await _swipe(p, Vector2(0, -260))
	await get_tree().create_timer(0.6).timeout
	var moved := _scroll.scroll_vertical - y0
	var same := run.pool() == before
	print("① 조합 버튼 위에서 위로 끌기: 스크롤 %+d · 조합 안 됨 %s" % [moved, same])
	ok = ok and moved > 200 and same
	# 그냥 누르면 눌린다
	_scroll.scroll_vertical = 0
	await get_tree().create_timer(0.3).timeout
	fb = _find_btn(_body, "조합")
	await _swipe(fb.get_global_rect().get_center(), Vector2.ZERO)
	await get_tree().create_timer(0.3).timeout
	var forged := run.pool() != before
	print("② 조합 버튼 탭: 조합됨 %s" % forged)
	ok = ok and forged
	# 가로 칩 띠 —— 옆으로 끌면 띠만 움직이고 칩은 안 눌린다
	await get_tree().create_timer(0.3).timeout
	_scroll.scroll_vertical = 0
	await get_tree().process_frame
	var chip: Button = _find_btn(_body, "기병")
	var strip: ScrollContainer = chip.get_parent().get_parent()
	var tag0 := forge_tag
	await _swipe(chip.get_global_rect().get_center(), Vector2(-150, 6))
	await get_tree().create_timer(0.5).timeout
	print("③ 칩 띠 옆으로 끌기: 띠 %d · 세로 %d · 필터 그대로 %s" % [strip.scroll_horizontal, _scroll.scroll_vertical, forge_tag == tag0])
	ok = ok and strip.scroll_horizontal > 60 and forge_tag == tag0 and _scroll.scroll_vertical < 20
	# 칩 띠 위에서 세로로 끌면 페이지가 스크롤된다
	chip = _find_btn(_body, "궁병")
	await _swipe(chip.get_global_rect().get_center(), Vector2(4, -200))
	await get_tree().create_timer(0.5).timeout
	print("④ 칩 띠 위에서 세로로 끌기: 페이지 %d" % _scroll.scroll_vertical)
	ok = ok and _scroll.scroll_vertical > 120
	# 시트 —— 시트 안 카드 위에서 끌면 시트만 스크롤, 뒤 페이지는 그대로
	go("draw")
	await get_tree().create_timer(0.3).timeout
	var k: String = run.pool().keys()[0]
	card_info(k)
	await get_tree().create_timer(0.6).timeout
	var page_y := _scroll.scroll_vertical
	var t: Control = _find_tile(_sheet_body)
	var sp := t.get_global_rect().get_center() if t != null else _sheet.get_global_rect().get_center()
	await _swipe(sp, Vector2(0, -240))
	await get_tree().create_timer(0.5).timeout
	print("⑤ 시트 안에서 끌기: 시트 %d · 뒤 페이지 그대로 %s · 시트 열림 %s · 제목 %s" % [_sheet_scroll.scroll_vertical, _scroll.scroll_vertical == page_y, _sheet.visible, _sheet_title.text])
	ok = ok and _sheet_scroll.scroll_vertical > 100 and _scroll.scroll_vertical == page_y and _sheet_title.text == DB.C[k].name
	# 손잡이를 끌어내리면 닫힌다
	var hp := _sheet.get_global_rect().position + Vector2(_sheet.size.x / 2, 12)
	await _swipe(hp, Vector2(0, 260))
	await get_tree().create_timer(0.5).timeout
	print("⑥ 손잡이 끌어내리기: 시트 닫힘 %s" % (not _sheet.visible))
	ok = ok and not _sheet.visible
	# 편성 —— 손패 카드 위에서 끌면 손패만 스크롤, 카드는 골라지지 않는다
	go("deploy")
	await get_tree().create_timer(0.4).timeout
	var ht: Control = _find_tile(_fixed)
	var hs: ScrollContainer = ht.get_parent().get_parent().get_parent()
	await _swipe(ht.get_global_rect().get_center(), Vector2(0, -150))
	await get_tree().create_timer(0.5).timeout
	print("⑦ 편성 손패 끌기: 손패 %d · 고른 카드 없음 %s" % [hs.scroll_vertical, deploy.sel == ""])
	ok = ok and hs.scroll_vertical > 60 and deploy.sel == ""
	print("손가락 점검 %s" % ("통과" if ok else "실패"))


func _swipe(from: Vector2, d: Vector2) -> void:
	var xf := get_tree().root.get_final_transform()
	var steps := 12 if d != Vector2.ZERO else 0
	var t := InputEventScreenTouch.new()
	t.index = 0
	t.pressed = true
	t.position = xf * from
	Input.parse_input_event(t)
	await get_tree().process_frame
	await get_tree().process_frame
	var last := from
	for i in steps:
		var p := from + d * float(i + 1) / steps
		var dr := InputEventScreenDrag.new()
		dr.index = 0
		dr.position = xf * p
		dr.relative = xf.basis_xform(p - last)
		last = p
		Input.parse_input_event(dr)
		await get_tree().process_frame
	var u := InputEventScreenTouch.new()
	u.index = 0
	u.pressed = false
	u.position = xf * last
	Input.parse_input_event(u)
	await get_tree().process_frame
	await get_tree().process_frame


func _find_btn(n: Node, text: String) -> Button:
	for c in n.get_children():
		if c is Button and c.text.begins_with(text) and c.is_visible_in_tree() and not c.disabled:
			return c
		var r := _find_btn(c, text)
		if r != null:
			return r
	return null


func _find_tile(n: Node) -> Control:
	for c in n.get_children():
		if c is CardTile and c.is_visible_in_tree():
			return c
		var r := _find_tile(c)
		if r != null:
			return r
	return null


## 머리띠의 21칸 진행 막대 —— 하루 세 칸씩 묶는다
class PhaseBar extends Control:
	var cur := 0

	func _draw() -> void:
		var n := 21
		var gap := 2.0
		var dgap := 6.0
		var w := (size.x - gap * (n - 1) - (dgap - gap) * 6) / n
		var x := 0.0
		for i in n:
			var col: Color = DB.PAL.gold if i == cur else (DB.PAL.bamboo_dim if i < cur else DB.PAL.ink3)
			var r := Rect2(x, 0, w, size.y)
			draw_rect(r, col)
			x += w + (dgap if i % 3 == 2 else gap)


## 아래 탭 하나 —— 그림 + 이름, 할 일이 있으면 빨간 점(badge 0) 또는 숫자
class TabButton extends Control:
	signal tapped(key: String)
	var key := ""
	var text := ""
	var on := false
	var badge := -1
	var _press := Vector2.INF

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		custom_minimum_size = Vector2(56, 56)

	func _gui_input(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
			if e.pressed:
				_press = e.position
			else:
				if _press != Vector2.INF and Rect2(Vector2.ZERO, size).has_point(e.position):
					tapped.emit(key)
				_press = Vector2.INF

	func _draw() -> void:
		var col: Color = DB.PAL.gold if on else DB.PAL.bamboo_dim
		var c := Vector2(size.x / 2, 22)
		if on:
			draw_rect(Rect2(c.x - 26, 1, 52, 3), DB.PAL.gold)
			var pill := StyleBoxFlat.new()
			pill.bg_color = Color(DB.PAL.gold, 0.14)
			pill.set_corner_radius_all(14)
			draw_style_box(pill, Rect2(c.x - 28, 8, 56, 28))
		_icon(c, col)
		draw_string(DB.font_display if on else DB.font_body, Vector2(0, size.y - 8), text, HORIZONTAL_ALIGNMENT_CENTER, size.x, 13, DB.PAL.paper if on else col)
		if badge >= 0:
			var bp := c + Vector2(15, -10)
			if badge == 0:
				draw_circle(bp, 4.5, DB.PAL.seal)
			else:
				var s := str(badge) if badge < 100 else "99+"
				var w := maxf(18.0, DB.font_body.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x + 8)
				var sb := StyleBoxFlat.new()
				sb.bg_color = DB.PAL.seal
				sb.set_corner_radius_all(9)
				draw_style_box(sb, Rect2(bp.x - 4, bp.y - 9, w, 18))
				draw_string(DB.font_body, Vector2(bp.x - 4, bp.y + 4), s, HORIZONTAL_ALIGNMENT_CENTER, w, 11, Color.WHITE)

	func _icon(c: Vector2, col: Color) -> void:
		match key:
			"draw":      # 겹친 카드 두 장
				draw_set_transform(c + Vector2(-3, 1), -0.22)
				draw_rect(Rect2(-6, -9, 12, 17), col, false, 2.0)
				draw_set_transform(c + Vector2(4, 0), 0.18)
				draw_rect(Rect2(-6, -9, 12, 17), DB.PAL.ink if not on else Color("#2a2a22"))
				draw_rect(Rect2(-6, -9, 12, 17), col, false, 2.0)
				draw_set_transform(Vector2.ZERO)
			"forge":     # 망치
				draw_set_transform(c, -0.7)
				draw_rect(Rect2(-1.5, -4, 3, 16), col)
				draw_rect(Rect2(-8, -10, 16, 7), col)
				draw_set_transform(Vector2.ZERO)
			"deploy":    # 3×3 진형 점
				for i in 3:
					for j in 3:
						var on_dot := not (i == 1 and j == 0)
						var p := c + Vector2((i - 1) * 7.5, (j - 1) * 7.5)
						if on_dot:
							draw_rect(Rect2(p - Vector2(2.6, 2.6), Vector2(5.2, 5.2)), col)
						else:
							draw_rect(Rect2(p - Vector2(2.6, 2.6), Vector2(5.2, 5.2)), col, false, 1.2)
			"war":       # 엇갈린 칼 두 자루
				for sgn in [-1.0, 1.0]:
					var a := c + Vector2(-9 * sgn, 9)
					var b := c + Vector2(9 * sgn, -9)
					draw_line(a, b, col, 2.4)
					var mid := a.lerp(b, 0.28)
					var perp := Vector2(1, sgn).normalized() * 4.5
					draw_line(mid - perp, mid + perp, col, 2.4)
			"more":      # 막대 그래프
				for i in 3:
					var hgt: float = [9.0, 16.0, 12.0][i]
					draw_rect(Rect2(c.x - 9 + i * 7, c.y + 9 - hgt, 5, hgt), col)


## 시트 손잡이 —— 가운데 짧은 막대
class SheetHandle extends Control:
	func _draw() -> void:
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(DB.PAL.paper, 0.25)
		sb.set_corner_radius_all(3)
		draw_style_box(sb, Rect2(size.x / 2 - 20, 8, 40, 5))
