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

const SHOW_DOTS := false     # 설정의 '전장 표현(3D · 점묘)' 고르기 —— 숨김 (11/3)
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
var _sheet_art: TextureRect      # 조합 시트 위 빈 공간의 신화 그림
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
	if not SHOW_DOTS:
		Settings.dots = false      # 고르는 칸을 숨겼으니 예전에 점묘로 저장했어도 3D 로
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
	# 11/3 사용자: 장수정보간략창(조합 시트) 위의 빈 공간에 신화 그림 —— 어두운 막 위, 시트 아래. 누르면 막처럼 닫힌다
	_sheet_art = TextureRect.new()
	_sheet_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_sheet_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_sheet_art.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_sheet_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sheet_art.visible = false
	add_child(_sheet_art)
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
	if _sheet_art.texture != null and _sheet.visible:
		var sa := _safe_insets()
		var top_y := sa.position.y + TOP_H + 8.0      # 위 띠(날짜 · 병력) 아래부터
		var bot_y := size.y - _sheet_h + dy - 12.0
		var side := maxf(16.0, (size.x - MAX_W) / 2.0 + 16.0)
		_sheet_art.position = Vector2(side, top_y)
		_sheet_art.size = Vector2(size.x - side * 2.0, maxf(0.0, bot_y - top_y))
		_sheet_art.visible = bot_y - top_y > 90.0
		_sheet_art.modulate.a = clampf(1.0 - dy / maxf(1.0, _sheet_h), 0, 1)


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
	var max_h := (size.y - sa.position.y) * (0.98 if _sheet_full else 0.88)      # 11/6 사용자: 선택권은 전체 화면처럼 크게
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
	# 11/3 사용자: 창 크기가 자꾸 변한다 —— 좁은 칸의 줄 바꿈 글씨는 폭이 정해지기 전 첫 프레임에 높이를 크게 잡는다.
	# 자리를 잡은 뒤 한 번 더 재서 맞춘다 (미끄러지는 중이면 끝난 높이로)
	for i in 2:
		await get_tree().process_frame
	if not _sheet.visible:
		return
	var body2: float = _sheet_scroll.get_child(0).get_combined_minimum_size().y
	var h2 := minf(max_h, head_h + body2 + sa.size.y + 4)
	if absf(h2 - _sheet_h) > 1.5:
		var dy := _sheet.offset_bottom
		_sheet_h = h2
		_put_sheet(dy)


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
	_battle.info_requested.connect(func(cid):
		if DB.RECOF.has(cid) and not DB.is_foe(cid):
			recipe_sheet(cid)
		else:
			card_info(cid))
	_battle.unit_requested.connect(battle_unit_sheet)
	_battle.inputs_changed.connect(func(inputs):
		if run.battle != null and online == null:
			run.battle.inputs = inputs.duplicate(true)
			run.save())
	_battle_done = UI.btn("종료", _on_battle_close, "pri", 58)      # 11/3 사용자: '결과 정리' → '종료'
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
	# 11/3 사용자: 타이틀을 이쁘게 —— 신화 일러스트가 천천히 넘어가는 배경 · 금빛 로고 + 낙관 · 영문 이름 · 아래쪽 먹빛 버튼
	_title = ColorRect.new()
	_title.color = Color("#0b0f1a")
	_title.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	TouchScroll.block(_title)
	add_child(_title)
	var bg := TitleBG.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_title.add_child(bg)
	var m := MarginContainer.new()
	m.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var side := maxf(30.0, (size.x - 420.0) / 2.0)
	for s in ["left", "right"]:
		m.add_theme_constant_override("margin_" + s, int(side))
	m.add_theme_constant_override("margin_top", 70)
	m.add_theme_constant_override("margin_bottom", 40)
	_title.add_child(m)
	var v := UI.vbox(0)
	m.add_child(v)
	# 로고 (11/3 사용자: 한글을 빼고 붓으로 휘갈긴 영문) —— 먹 붓질 띠 위에 금빛 붓글씨 'Solgukji', 오른쪽 위에 붉은 낙관
	var logo := TitleBG.Logo.new()
	logo.custom_minimum_size = Vector2(0, 150)
	v.add_child(logo)
	var sub := UI.lbl("THREE KINGDOMS · RANDOM DEFENSE", 11, Color("#d9a64b"))
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_constant_override("outline_size", 4)
	sub.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	v.add_child(sub)
	var ko := UI.lbl("일주일을 살아남아 천하를 얻어라", 14, Color("#c6ac7c"))
	ko.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ko.add_theme_constant_override("outline_size", 5)
	ko.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.75))
	var rg3 := Control.new()
	rg3.custom_minimum_size.y = 6
	v.add_child(rg3)
	v.add_child(ko)
	var fill := Control.new()
	fill.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(fill)
	# 버튼 —— 아래쪽, 먹빛 반투명 + 금테
	var bv := UI.vbox(10)
	if Run.has_save():
		bv.add_child(_title_btn("이어 하기", _continue, true))
	bv.add_child(_title_btn("새 판 시작", _new_game, not Run.has_save()))
	bv.add_child(_title_btn("온라인 대전", _go_online, false))
	var sb := UI.btn("설정", _settings_sheet, "ghost", 44)
	sb.add_theme_color_override("font_color", Color("#c6ac7c"))
	bv.add_child(sb)
	v.add_child(bv)


## 타이틀 버튼 —— 주 버튼은 금빛 바탕, 나머지는 먹빛 반투명 + 금테
func _title_btn(text: String, cb: Callable, main: bool) -> Button:
	var b := UI.btn(text, cb, "", 56)
	var bg := Color("#c9952f", 0.92) if main else Color("#0b0f1a", 0.62)
	var bd := Color("#ffd98a") if main else Color("#d9a64b", 0.7)
	b.add_theme_stylebox_override("normal", UI.flat(bg, bd, 1, 10, 10))
	b.add_theme_stylebox_override("hover", UI.flat(bg.lightened(0.08), bd, 1, 10, 10))
	b.add_theme_stylebox_override("pressed", UI.flat(bg.darkened(0.15), bd, 2, 10, 10))
	b.add_theme_font_override("font", DB.font_display)
	b.add_theme_font_size_override("font_size", 19)
	b.add_theme_color_override("font_color", Color("#1a1206") if main else Color("#f0e6cf"))
	b.add_theme_color_override("font_hover_color", Color("#1a1206") if main else Color("#ffffff"))
	return b


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
	PlayLog.ensure(run, "resume")
	if run.battle != null:
		# 전투 도중 꺼졌다 —— 적어 둔 입력으로 마무리한다
		var res := run.resolve_pending()
		PlayLog.note(run, "pending_resolved", {"win": bool(res.win)})
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
	PlayLog.new_game(run)
	forge_tree.clear()          # 11/3 사용자: 이전 판의 갈무리가 남아 있었다
	_title.visible = false
	close_sheet()
	go("draw")


# ───────── 그리기 ─────────

func go(pg: String) -> void:
	if pg == "more":
		pg = "rank"         # '기록' 탭은 순위 · 계보 화면 (페이지 이름이 아니다)
	if online == null and pg != page:
		PlayLog.page(run, pg)
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
	var fixed: bool = page == "deploy" or (page == "draw" and run.over == null) or (page == "war" and run.over == null and online == null and not run.is_tour_phase())      # 전투 탭 —— 진영 그림이 남는 공간을 채운다 (11/4)      # 징집도 고정 —— 보유 패만 아래에서 스크롤 (11/2)
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
	var seen := {}
	for t in run.toasts:
		if seen.has(t[0]):      # 같은 알림이 겹쳐 쌓이면 하나만 (11/4)
			continue
		seen[t[0]] = true
		if t[1] == "gold":      # 11/5 사용자: 보급 도착 같은 알림은 화면 가운데 띠로
			Sfx.play("gain")
			var parts: PackedStringArray = str(t[0]).split(" · ", true, 1)
			band(parts[0], DB.PAL.gold, parts[1] if parts.size() > 1 else "")
		else:
			toast(t[0], t[1])
	run.toasts.clear()
	_auto_unique.call_deferred()


# ───────── 가운데 띠 알림 (11/5 사용자) ─────────
var _bands: Array = []
var _band_busy := false

## 화면 가운데 가로 띠 —— 큰 글씨 한 줄 + 작은 둘째 줄. 여러 개면 차례로
func band(text: String, col: Color = DB.PAL.gold, sub := "") -> void:
	_bands.append([text, col, sub])
	if not _band_busy:
		_next_band()


var _band_node: Control = null
## 전투 화면이 열리면 떠 있던 띠를 감춘다 (남은 띠는 전투가 끝난 뒤)
func _hide_band() -> void:
	if is_instance_valid(_band_node):
		_band_node.visible = false


func _next_band() -> void:
	if _bands.is_empty() or battle_visible():      # 11/6 전투 중에는 띠를 띄우지 않는다 (진형 표시 · 전장을 가렸다) —— 전투가 끝나면 이어서
		_band_busy = false
		return
	_band_busy = true
	var e: Array = _bands.pop_front()
	var col: Color = e[1]
	var p := PanelContainer.new()
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("#0d1220", 0.9)
	sb.border_color = Color(col, 0.85)
	sb.border_width_top = 2
	sb.border_width_bottom = 2
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	sb.shadow_color = Color(col, 0.25)
	sb.shadow_size = 14
	p.add_theme_stylebox_override("panel", sb)
	p.anchor_left = 0
	p.anchor_right = 1
	p.anchor_top = 0.42
	p.anchor_bottom = 0.42
	var v := UI.vbox(2)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := UI.lbl(str(e[0]), 22, col.lightened(0.25), true)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_constant_override("outline_size", 5)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	v.add_child(l)
	if str(e[2]) != "":
		var l2 := UI.lbl(str(e[2]), 14, DB.PAL.paper)
		l2.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(l2)
	p.add_child(v)
	add_child(p)
	_band_node = p
	var h := p.get_combined_minimum_size().y
	p.offset_left = 0
	p.offset_right = 0
	p.offset_top = -h / 2.0
	p.offset_bottom = h / 2.0
	p.pivot_offset = Vector2(size.x / 2.0, h / 2.0)
	p.scale = Vector2(1.0, 0.05)
	p.modulate.a = 0.0
	l.modulate.a = 0.0
	var tw := p.create_tween()
	tw.tween_property(p, "modulate:a", 1.0, 0.1)
	tw.parallel().tween_property(p, "scale:y", 1.0, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(l, "modulate:a", 1.0, 0.12)
	tw.tween_interval(1.5)
	tw.tween_property(p, "modulate:a", 0.0, 0.3)
	tw.tween_callback(func():
		p.queue_free()
		_next_band())


## 아이템 보급이 오면 고르기 창을 바로 연다 (11/5 사용자) —— 전투 · 다른 창 중이면 끝난 뒤 다음 그리기 때
var _uniq_seen := ""
func _auto_unique() -> void:
	if run == null or run.uniq_offer.is_empty():
		_uniq_seen = ""
		return
	var key := str(run.uniq_offer)
	if key == _uniq_seen or battle_visible() or _sheet.visible or not can_act() or (_title != null and _title.visible):
		return
	_uniq_seen = key
	_unique_sheet()


## 선택권으로 고른 순간 (11/5 사용자: 썼다는 느낌) —— 고른 카드가 가운데서 튀어 올랐다가 위로 빨려 들어가고, 띠로 이름 · 남은 수
func _pick_fx(id: String, left: int, tier_name: String) -> void:
	UI.buzz(25)
	Sfx.play("gain")
	var tc := DB.tier_color(id)
	var cv := CardView.new().setup(id, Vector2(132, 188))
	cv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cv.size = Vector2(132, 188)
	cv.pivot_offset = cv.size / 2.0
	cv.position = Vector2(size.x / 2.0 - 66, size.y * 0.42 - 60 - 188)      # 가운데 띠 바로 위
	cv.scale = Vector2(0.3, 0.3)
	add_child(cv)
	var glow := ColorRect.new()
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	glow.color = Color(tc, 0.0)
	glow.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(glow)
	move_child(glow, cv.get_index())
	var gt := glow.create_tween()
	gt.tween_property(glow, "color:a", 0.22, 0.06)
	gt.tween_property(glow, "color:a", 0.0, 0.35)
	gt.tween_callback(glow.queue_free)
	var tw := cv.create_tween()
	tw.tween_property(cv, "scale", Vector2(1.12, 1.12), 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(cv, "scale", Vector2.ONE, 0.1)
	tw.tween_interval(0.55)
	tw.tween_property(cv, "position:y", cv.position.y - 140, 0.3).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(cv, "scale", Vector2(0.35, 0.35), 0.3).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(cv, "modulate:a", 0.0, 0.3)
	tw.tween_callback(cv.queue_free)
	band("%s 획득" % DB.C[id].name, tc, ("%s 선택권 남은 %d회" % [tier_name, left]) if left > 0 else ("%s 선택권 모두 사용" % tier_name))


func changed() -> void:
	if online == null:
		run.save()
	render()


## 행동 —— Run 의 명령(Run.COMMANDS)을 실행하고 저장·다시 그린다. 온라인이면 서버에도 보낸다
## (서버가 같은 명령을 판정해 상태를 돌려보낸다 —— 난수 상태가 같아 결과도 같다)
func act(m: String, a := []):
	var r = run.command(m, a.duplicate())
	if online == null:
		PlayLog.act(run, m, a, r)
	match m:
		"forge":
			Sfx.play("forge" if r else "deny")
			if r and forge_tree.pinned(str(a[0])):      # 11/3 사용자: 갈무리한 장수를 완성하면 갈무리에서 뺀다
				forge_tree.done(str(a[0]))
			if r and DB.C[str(a[0])].tier >= 7:        # 11/3 사용자: 히든(불멸) 이상 완성 연출
				_forge_fanfare(str(a[0]))
			elif r and not _forge_quiet:               # 11/6 #17 조합 연출 —— 재료가 모여 하나로 (모두 조합은 forge_tree 가 묶어서)
				ForgeFx.play_one(self, str(a[0]), DB.RECOF.get(str(a[0]), []))
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
	_sheet_full = false
	if _battle_layer != null and _battle_layer.visible:      # 전투 위에서도 시트가 보이게 맨 앞으로
		move_child(_sheet_mask, -1)
		move_child(_sheet_art, -1)
		move_child(_sheet, -1)
	_sheet_title.add_theme_color_override("font_color", col if col.a > 0 else DB.PAL.paper)
	_sheet_title.add_theme_font_size_override("font_size", 24 if col.a > 0 else 19)
	for c in _sheet_body.get_children():
		c.queue_free()
	_sheet_art.texture = null
	_sheet_art.visible = false
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
		_sheet_art.visible = false
		_sheet_art.texture = null
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
	if OS.has_feature("pc"):      # 11/5 사용자: 친구들에게 플레이 기록을 받으려고 —— 휴대폰은 앱 폴더라 열 수 없다
		var dir := ProjectSettings.globalize_path(PlayLog.dir).replace("/", "\\")
		b.add_child(UI.btn("플레이 기록 폴더 열기", func():
			DirAccess.make_dir_recursive_absolute(PlayLog.dir)
			OS.shell_open(dir), "ghost"))
		b.add_child(UI.hint("판마다 .jsonl 파일이 하나씩 쌓입니다. 이 파일들을 보내 주세요.\n%s" % dir))
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
	if SHOW_DOTS:      # 11/3 사용자: 점묘 방식 옵션은 숨긴다 (점검용 --gdots 는 그대로)
		b.add_child(UI.eyebrow("전장 표현"))
		b.add_child(UI.segmented([["3d", "3D (삼국지13)"], ["dots", "점묘 (2D)"]], "dots" if Settings.dots else "3d", func(key):
			Settings.dots = key == "dots"
			Settings.save_cfg()
			if _battle:
				_battle.apply_style()
			_settings_sheet()))
	b.add_child(UI.eyebrow("전장 화풍"))
	var style_now := "type2" if Settings.type2 else ("sumuk" if Settings.sumuk else "base")
	b.add_child(UI.segmented([["base", "기본 3D"], ["sumuk", "수묵"], ["type2", "타입2 (삼국지11)"]], style_now, func(key):
		Settings.sumuk = key == "sumuk"
		Settings.type2 = key == "type2"
		Settings.apply()
		Settings.save_cfg()
		if _battle:
			_battle.apply_style()
		_settings_sheet()))
	b.add_child(UI.eyebrow("피해 숫자"))      # 11/6 #16 정보 계층 —— 평타 숫자는 소음이 되기 쉽다
	b.add_child(UI.segmented([["0", "큰 것만"], ["1", "모아서"], ["2", "모두"]], str(Settings.dmg_numbers), func(key):
		Settings.dmg_numbers = int(key)
		Settings.save_cfg()
		_settings_sheet()))
	b.add_child(UI.hint("큰 것만: 기술 · 고유기 · 치명타 숫자만. 모아서: 작은 타격은 합쳐서. 모두: 전부."))
	b.add_child(UI.eyebrow("전투 카메라 연출"))      # 11/6 사용자: 불필요한 카메라 무빙 자제
	b.add_child(UI.segmented([["0", "끔"], ["1", "적게"], ["2", "보통"]], str(Settings.cam_fx), func(key):
		Settings.cam_fx = int(key)
		Settings.save_cfg()
		_settings_sheet()))
	b.add_child(UI.hint("적게: 아군 고유기 · 적 신화 고유기 · 장수 격파 때만 다가갑니다. 보통: 첫 격돌 · 모든 고유기에도."))
	if Settings.type2:      # 11/6 타입2 전황 표시 단계 (일시정지하면 늘 자세히)
		b.add_child(UI.eyebrow("전황 표시 (타입2)"))
		b.add_child(UI.segmented([["0", "끔"], ["1", "간단"], ["2", "자세히"]], str(Settings.tac_info), func(key):
			Settings.tac_info = int(key)
			Settings.save_cfg()
			_settings_sheet()))
		b.add_child(UI.hint("간단: 진형 소개 · 진형 우대 금테 · 책략 실. 자세히: 사거리 · 진격 화살표까지. 일시정지하면 자세히 보입니다."))
	b.add_child(UI.eyebrow("성능 표시"))      # 11/6 휴대폰 실측용
	b.add_child(UI.segmented([["0", "끔"], ["1", "켬"]], "1" if Settings.perf_hud else "0", func(key):
		Settings.perf_hud = key == "1"
		Settings.save_cfg()
		_settings_sheet()))
	b.add_child(UI.hint("전투 왼쪽 위에 fps · 계산 병사 · 보이는 인형 수 · 부하 조절 단계를 띄웁니다. 타입2 는 품질과 상관없이 병사 수를 그대로 둡니다."))
	# 11/4 사용자: 직접 지휘 개념은 없앤다 —— 전투는 늘 AI 가 고유기 · 군령을 쓴다
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
	if it.grade == "유니크":      # 11/2 썸네일 (assets/items/<이름>.png 이 있으면 그 그림)
		var th := ItemArt.View.new(id, 60)
		th.position = Vector2(7, 7)
		th.size = Vector2(60, 60)
		b.add_child(th)
		v.offset_left = 76
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
## 징집 화면의 작은 카드 (11/2 사용자: UI 크기를 줄여 한 줄 5장)
const SMALL := Vector2(68, 96)
const HAND_TILE := Vector2(46, 72)     # 보유 패 8열 (11/2 · 11/4 높이 62 → 72)

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
func recipe_card(out: String, sz := Vector2(86, 112)) -> Control:
	var v := UI.vbox(4)
	v.custom_minimum_size = Vector2(sz.x, 0)
	var ok := run.can_forge(out)
	var t := mtile(out, run.pool().get(out, -1), func(id): recipe_sheet(id))
	t.custom_minimum_size = sz
	t.lit = ok
	v.add_child(t)
	var miss := run.miss_count(out)
	var b := UI.btn("조합" if ok else ("-%d장" % miss if miss > 0 else "◆필요"), func():
		if ok:
			if act("forge", [out]):
				toast("%s 조합 완료" % DB.C[out].name, "gain")
		else:
			recipe_sheet(out), "pri" if ok else "ghost", 34 if sz.y >= 112 else 28)
	b.add_theme_font_size_override("font_size", 13)
	v.add_child(b)
	return v


## 조합 시트 —— 제목은 등급색 장수 이름. 결과 카드(특기 칸) · 재료 한 줄(가진 수/필요 수) · 조합 + 상세 버튼 한 줄
## 디테일창의 신화 그림 —— 시트가 화면의 최대 높이까지 차도록 그림 높이를 늘린다 (남는 공간이 없으면 감춘다)
func _fill_art(ar: TextureRect) -> void:
	await get_tree().process_frame
	if not is_instance_valid(ar):
		return
	var sa := _safe_insets()
	var max_h := (size.y - sa.position.y) * 0.88
	var head_h: float = _sheet.get_child(0).get_child(0).get_combined_minimum_size().y
	var body_h: float = _sheet_scroll.get_child(0).get_combined_minimum_size().y
	ar.custom_minimum_size.y = maxf(0.0, ar.custom_minimum_size.y + max_h - head_h - body_h - sa.size.y - 8)
	if ar.custom_minimum_size.y < 90.0:      # 남는 공간이 거의 없으면 그리지 않는다
		ar.visible = false
		return
	_fit_sheet(false)
	# 11/3 사용자: 딱 맞게 —— 한 번 더 재서 스크롤이 생길 만큼 넘쳤으면 그만큼 줄인다
	for i in 3:
		await get_tree().process_frame
	if not is_instance_valid(ar):
		return
	var over: float = _sheet_scroll.get_child(0).get_combined_minimum_size().y - _sheet_scroll.size.y
	if over > 0.5:
		ar.custom_minimum_size.y = maxf(0.0, ar.custom_minimum_size.y - over - 2)
		if ar.custom_minimum_size.y < 90.0:
			ar.visible = false
			return
	# 얼굴이 있는 위쪽을 기준으로 자른다 (가운데로 자르면 신화 컷의 얼굴이 잘렸다)
	await get_tree().process_frame
	if not is_instance_valid(ar) or ar.size.x <= 0 or not ar.get_meta("crop", false):
		return
	var src: Texture2D = ar.get_meta("art")
	var ts := src.get_size()
	var rh := minf(ts.y, ts.x * ar.custom_minimum_size.y / ar.size.x)
	var rw := ts.x if rh < ts.y else ts.y * ar.size.x / ar.custom_minimum_size.y
	var at := AtlasTexture.new()
	at.atlas = src
	at.region = Rect2((ts.x - rw) / 2.0, clampf(ts.y * 0.04, 0.0, ts.y - rh), rw, rh)
	ar.texture = at
	ar.stretch_mode = TextureRect.STRETCH_SCALE


func recipe_sheet(out: String) -> void:
	_route_enter("recipe", out)
	var c: Dictionary = DB.C[out]
	var b := open_sheet(c.name, DB.tier_color(out).lightened(0.2))
	_sheet_art.texture = DB.myth_art(out)      # 그 인물의 신화 그림이 있으면 시트 위 빈 공간에 (_put_sheet 가 자리를 잡는다)
	# 11/3 사용자: 이름은 제목과 겹치니 빼고, 일반 기술도 뺀다 —— 초상 오른쪽에 특기판 · 고유 특기 · 위세
	var tp := UI.hbox(10)
	var cv := CardView.new().setup(out, Vector2(72, 102))
	cv.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	cv.mouse_filter = Control.MOUSE_FILTER_STOP          # 11/3 사용자: 초상을 누르면 디테일창
	cv.gui_input.connect(func(e):
		if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT and not e.pressed:
			UI.buzz()
			card_info(out))
	tp.add_child(cv)
	var rv := UI.vbox(5)
	rv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rv.add_child(TraitBoard.new().setup(out))
	for t in DB.trait_list(out):
		if t.unique:
			rv.add_child(UI.rich("[b][color=#e8c25a]고유 특기[/color] [color=#FFD76E]『%s』[/color][/b]
[color=#8FD4C2]%s[/color]" % [t.name, t.mt], 12))
	if DB.AURA.has(out):
		rv.add_child(UI.rich("[b][color=%s]%s[/color] 『%s』[/b]
[color=#8FD4C2]%s[/color]" % [DB.tier_color(out).to_html(false), "기인" if DB.is_kiin(out) else "위세", DB.AURA[out].n, DB.aura_effect(out)], 12))
	tp.add_child(rv)
	b.add_child(UI.panel(tp, 8))
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
		b.add_child(UI.icon_chip("item", "유니크 %s — %s" % [DB.IT[ni].name, "보유" if have_it else "없음 · 2 · 4 · 6일차 아이템 보급"], DB.PAL.gold if have_it else DB.PAL.seal, func(): _item_sheet(ni)))
	if c.tier >= 8 and run.has_myth():
		b.add_child(UI.hint("신화 장수는 한 판에 하나뿐이다 — 이미 신화를 얻었다"))
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
	var v := UI.vbox(12)
	var n := run.draws_n()
	if run.day == 6:
		v.add_child(UI.panel(UI.rich("[b][color=#D9A64B]결전의 날[/color][/b] — 더 이상 농민을 징집하지 않는다. 명장만이 소환된다.", 14), 10))

	# 할 일 —— 기호 타일 한 줄
	var acts := UI.grid(68, 6)
	# 11/2 사용자: 타일 아래 설명 글(기본패 14장 · 11종 중 고르기)은 빼고 낮게. 선택권은 타일 하나 —— 고르다 닫아도 「일반 ×2」 같은 타일이 따로 생기지 않고 같은 타일로 다시 연다
	if n > 0:
		acts.add_child(UI.tile_act("draw", "징집", "", func(): act("do_draw"), "pri", run.drawn, not can_act()))
	# 11/2 사용자: 보급(선택권)을 하나로 합치지 말고 등급별 칸으로. 고르지 않고 닫으면 수는 줄지 않는다 (고른 만큼만 줄어든다)
	var pl := run.pick_list()
	var per_t := {}
	for k in run.tickets:
		per_t[int(k)] = int(per_t.get(int(k), 0)) + int(run.tickets[k])
	if not run.picked:
		for p in pl:
			per_t[int(p.t)] = int(per_t.get(int(p.t), 0)) + int(p.n)
	var tks := per_t.keys().filter(func(t): return per_t[t] > 0)
	tks.sort()
	tks.reverse()
	for t in tks:
		var tt: int = t
		var rnd := Run.LEGEND_RANDOM and tt == 5      # 11/5 사용자: 전설 보급은 무작위 —— 누르면 바로 받는다 (고르는 창 없음)
		var tb := UI.tile_act("grant" if rnd else "pick", "%s %d" % [DB.TIER[tt].n, per_t[tt]], "", func():
			act("begin_picks", ["phase", -1])
			if not rnd:
				picker(tt), "gold", false, not can_act())
		tb.add_theme_color_override("font_color", DB.TIER[tt].c)
		UI.tier_mark(tb, tt)
		acts.add_child(tb)
	if tks.is_empty() and not pl.is_empty():
		acts.add_child(UI.tile_act("pick", "선택권", "", func(): pass, "", true, true))
	if not run.uniq_offer.is_empty():
		var ub := UI.tile_act("item", "보급", "", _unique_sheet, "gold", false, not can_act())
		UI.tier_mark(ub, 8)
		acts.add_child(ub)
	var rg := run.grant_list()
	if not rg.is_empty():
		acts.add_child(UI.tile_act("grant", "배급", "", func():
			for k in act("random_grant"):
				toast("%s 배급 · %s" % [DB.C[k].name, DB.tier_name(k)], "gain"), "", run.granted, not can_act()))
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

	# 보유 카드만 (11/2 사용자) —— 등급별로 열 수를 달리한다: 초월 위 4열 · 일반~전설 6열 (남은 높이에서 스크롤), 기본 병졸 8종은 맨 아랫줄 8열 고정
	var p := run.pool()
	var tot := 0
	for k in p:
		tot += p[k]
	var mats := _ready_mats()
	var hand_tile := func(k: String, n: int, h: float) -> MiniTile:
		var t := mtile(k, n)
		t.custom_minimum_size = Vector2(30, h)
		if run.on_board(k) > 0:
			t.badge = "편성 %d" % run.on_board(k) if h >= 90 else "편성"
			t.badge_col = Color(DB.PAL.ink4, 0.95)
		t.up = mats.has(k)
		t.dim = n <= 0
		return t
	var hv := UI.vbox(6)
	hv.size_flags_vertical = Control.SIZE_EXPAND_FILL
	hv.add_child(UI.head("보유 %d장 · %d PV" % [tot, run.my_pv()], "▲ 지금 조합 재료"))
	var hs := UI.scroll()
	hs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var inner := UI.vbox(6)
	inner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inner.size_flags_vertical = Control.SIZE_EXPAND_FILL
	inner.alignment = BoxContainer.ALIGNMENT_BEGIN    # 11/6 사용자: 기본병 줄이 맨 위로 갔으니 위에서부터 채운다
	var keys: Array = Run.sort_cards(p.keys())
	# 11/4 사용자: 등급마다 줄을 나눈다 [등급 아래, 위, 열, 칸 높이]
	# 11/5 사용자: 전설 · 초월 · 불멸 · 신화가 같은 칸 크기를 쓰지 말 것 —— 등급이 높을수록 크게 (신화 2열 · 불멸 3열 · 초월 4열 · 전설 5열)
	# 11/6 사용자: 신화 · 불멸은 한 줄을 같이 쓰고(같은 묶음), 전설보다 조금 크게 한 줄에 넷 · 초월은 전설과 같은 다섯 줄에 조금 크게
	for grp in [[7, 9, 4, 136.0], [6, 6, 5, 120.0], [5, 5, 5, 114.0], [4, 4, 6, 96.0], [2, 3, 6, 90.0]]:
		var g := UI.grid(30, 6)
		g.max_cols = grp[2]
		for k in keys:
			if DB.C[k].tier >= grp[0] and DB.C[k].tier <= grp[1]:
				g.add_child(hand_tile.call(k, p[k], grp[3]))
		if g.get_child_count() > 0:
			inner.add_child(g)
	if inner.get_child_count() == 0:
		inner.add_child(UI.hint("장수가 아직 없다. 기본 병졸을 조합하거나 선택권으로."))
	hs.add_child(inner)
	var base := UI.grid(30, 4)      # 11/6 사용자: 기본병 8종은 맨 윗줄에 (조합 재료의 출발점이라 먼저 본다)
	base.max_cols = 8
	for k in Run.sort_cards(DB.BASE.duplicate()):
		base.add_child(hand_tile.call(k, int(p.get(k, 0)), HAND_TILE.y))
	hv.add_child(base)
	hv.add_child(hs)
	_hand_scroll = hs
	_restore_hand_scroll.call_deferred(_hand_scroll_y)
	hs.get_v_scroll_bar().value_changed.connect(func(y): _hand_scroll_y = int(y))
	v.add_child(hv)
	return v


var _hand_scroll: ScrollContainer
var _hand_scroll_y := 0       # 다시 그려도 보유 패 스크롤 자리를 지킨다


func _restore_hand_scroll(y: int) -> void:
	await get_tree().process_frame
	if is_instance_valid(_hand_scroll):
		_hand_scroll.scroll_vertical = y


func mini_n(a: int, b: int) -> int:
	return a if a < b else b


func _news_sheet() -> void:
	var b := open_sheet("전황 소식")
	for nw in run.news:
		b.add_child(UI.rich("[b]%s[/b]가 %s [color=#8D7B5C]%s 등용[/color]" % [nw.who, UI.card_bb(nw.unit), DB.tier_name(nw.unit)], 15))


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


## 유니크 보급 —— 신화 재료 셋 중 하나 (11/2 사용자). 각 재료로 만드는 신화 장수와 그 위세를 함께 보인다
func _unique_sheet() -> void:
	if run.uniq_offer.is_empty() or not can_act():
		close_sheet()
		return
	var b := open_sheet("아이템 보급")
	# 11/3 사용자: 스크롤 없이 가로 세 칸, 칸은 위아래로 길게 —— [아이템] [아이템 능력치] [장수(신화 그림)], 수치는 '효과 · 수치' 줄
	var row := UI.hbox(5)
	for id in run.uniq_offer:
		var iid: String = id
		var it: Dictionary = DB.IT[iid]
		var col := UI.vbox(4)
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var ih := UI.hbox(4)
		var th := ItemArt.View.new(iid, 30)
		th.custom_minimum_size = Vector2(30, 30)
		ih.add_child(th)
		var nl := UI.lbl(it.name, 12, DB.PAL.gold, true)
		nl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		nl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		nl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		ih.add_child(nl)
		col.add_child(ih)
		col.add_child(_kv_grid(UI.item_text(iid), 10))
		for k in DB.by_tier(8).filter(func(x): return Run.need_item(x) == iid):
			var kk: String = k
			var art := _art_crop(kk, Vector2(120, 150), false)      # 11/3 사용자: 보급 창은 기본 장수 그림 (신화 그림은 갈무리 창에만)
			art.mouse_filter = Control.MOUSE_FILTER_STOP
			art.gui_input.connect(func(e):
				if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT and not e.pressed:
					UI.buzz()
					recipe_sheet(kk))      # 11/3 사용자: 디테일이 아니라 간략창으로
			col.add_child(art)
			var gn := UI.lbl(DB.C[kk].name, 12, DB.tier_color(kk), true)
			gn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			gn.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			col.add_child(gn)
			var tb := TraitBoard.new()
			tb.fixed = true
			col.add_child(tb.setup(kk, 3))
			for t in DB.trait_list(kk):
				if t.unique:
					col.add_child(UI.rich("[b][color=#e8c25a]고유 특기[/color] [color=#FFD76E]『%s』[/color][/b]" % t.name, 10))
					col.add_child(_kv_grid(t.mt, 10))
			if DB.AURA.has(kk):
				col.add_child(UI.rich("[b][color=%s]위세[/color] 『%s』[/b]" % [DB.tier_color(kk).to_html(false), DB.AURA[kk].n], 10))
				col.add_child(_kv_grid(DB.aura_effect(kk), 10))
		var sp := Control.new()
		sp.size_flags_vertical = Control.SIZE_EXPAND_FILL
		col.add_child(sp)
		col.add_child(UI.btn("받기", func():
			if act("pick_unique", [iid]):
				toast("%s 획득 · 아이템 보급" % it.name, "gain")
			close_sheet(), "pri", 38))
		var pc := UI.panel(col, 5)
		pc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		pc.size_flags_stretch_ratio = 1.0
		pc.custom_minimum_size.x = 0
		pc.clip_contents = true
		row.add_child(pc)
	b.add_child(row)


## 그림을 상자 비율로 —— 얼굴이 있는 위쪽 기준으로 자른다 (myth 면 신화 그림, 없으면 기본 초상)
func _art_crop(k: String, box: Vector2, myth := true) -> TextureRect:
	var src: Texture2D = DB.myth_art(k) if myth else null
	if src == null:
		src = DB.portrait(k)
	var tr := TextureRect.new()
	tr.custom_minimum_size = Vector2(0, box.y)          # 폭은 칸에 맞춘다 (최소 폭이 있으면 셋째 칸이 화면 밖으로 밀렸다)
	tr.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	tr.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	tr.clip_contents = true
	if src == null:
		return tr
	var at := AtlasTexture.new()
	at.atlas = src
	if not myth or DB.myth_art(k) == null:
		# 기본 초상(투명 바탕) —— 그려진 영역만 잘라 상자 안에 비율 그대로 꽉 (그림마다 여백이 달라 크기가 들쭉날쭉했다)
		var ur := DB.portrait_used(k)
		at.region = ur if ur.has_area() else Rect2(Vector2.ZERO, src.get_size())
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.texture = at
		return tr
	var ts := src.get_size()
	var rh := minf(ts.y, ts.x * box.y / box.x)
	var rw := ts.x if rh < ts.y else ts.y * box.x / box.y
	at.region = Rect2((ts.x - rw) / 2.0, clampf(ts.y * 0.04, 0.0, ts.y - rh), rw, rh)
	tr.texture = at
	return tr


## 선택권 —— 그 등급 선택권으로 한 장씩 고른다. 그 등급을 다 쓰면 닫는다
var _forge_quiet := false     # 모두 조합 중 —— 한 장마다 연출하지 않고 끝에 묶어서 (ForgeFx.play_chain)
var _pick_last := ""          # 방금 고른 카드 —— 다시 그려도 금테로 남긴다 (11/6 #3)
var _pick_scroll := 0
var _sheet_full := false      # 시트를 화면 높이 거의 끝까지 (선택권)


## 선택권 화면 (11/6 #4: 8병종을 한 화면에 —— 열 = 병종, 행 = 그 병종 장수. #2: 갈무리 장수 · 그 재료 표시. #3: 고른 뒤 스크롤 · 금테 유지)
func picker(t: int) -> void:
	var left := int(run.tickets.get(str(t), 0))
	if left <= 0 or not can_act():
		close_sheet()
		return
	var was_open := _sheet.visible
	var b := open_sheet("%s 선택권 — 남은 %d회" % [DB.TIER[t].n, left])
	_sheet_full = true      # 11/6 사용자 2차: 타일이 너무 작다 → 전체 화면 높이 · 큰 타일 · 병종 묶음
	var vp := get_viewport_rect().size
	var full: float = (_sheet.size.x if _sheet.size.x > 100 else vp.x) - 36
	var gap := 6.0
	# 갈무리 장수의 재료 —— 직접 재료뿐 아니라 그 아래 재료(재료의 재료)까지 (11/6 사용자)
	var pins: Array = forge_tree.pins
	var mats := {}
	var stack: Array = []
	for pk in pins:
		stack.append_array(DB.RECOF.get(pk, []))
	while not stack.is_empty():
		var m := str(stack.pop_back())
		if mats.has(m):
			continue
		mats[m] = true
		stack.append_array(DB.RECOF.get(m, []))
	var on_pick := func(id):
		_pick_scroll = _sheet_scroll.scroll_vertical
		if act("pick", [id]):
			var left2 := int(run.tickets.get(str(t), 0))
			_pick_fx(id, left2, DB.TIER[t].n)
			if left2 > 0:
				picker(t)
			else:
				close_sheet()
				_hand_scroll_y = 0
				render()
		else:
			picker(t)
	var make_tile := func(k: String, w: float, h: float) -> Control:
		var tl := mtile(k, run.pool().get(k, -1), on_pick)
		tl.custom_minimum_size = Vector2(w, h)
		if pins.has(k):
			tl.badge = "갈무리"
			tl.badge_col = Color(DB.PAL.gold, 0.95)
		elif mats.has(k):
			tl.badge = "재료"
			tl.badge_col = Color(DB.PAL.jade, 0.95)
		return tl      # 11/6 사용자: 마지막으로 뽑은 장수에 금띠가 남던 것은 뺀다
	var avail_h: float = vp.y * 0.98 - 120.0      # 시트 머리 · 아래 여백
	if t <= 2:
		# 기본 —— 두 줄에 넷씩: 위 물리(창 · 기 · 궁 · 도), 아래 책략(책 · 유 · 술 · 모). 병종 글자는 빼서 자리를 넓힌다
		var tw := floorf((full - gap * 3) / 4)
		for row in [DB.PHYS_TAGS, DB.INT_TAGS]:
			var g := GridContainer.new()
			g.columns = 4
			g.add_theme_constant_override("h_separation", int(gap))
			g.add_theme_constant_override("v_separation", int(gap))
			for tag in row:
				for k in Run.pickable(t, tag):
					g.add_child(make_tile.call(k, tw, tw * 1.35))
			b.add_child(g)
	elif t <= 4:
		# 고급 · 희귀 —— 병종 한 줄씩(왼쪽 병종 기호), 8병종이 한 화면에. 고급은 넷, 희귀는 여섯 칸
		var cols := 4 if t == 3 else 6
		var icon_w := 26.0
		var tw := floorf((full - icon_w - gap * cols) / cols)
		var nrow := 0
		for tag in DB.D.TAGORDER:
			nrow += maxi(1, ceili(Run.pickable(t, tag).size() / float(cols))) if not Run.pickable(t, tag).is_empty() else 0
		var th := clampf((avail_h - gap * nrow) / maxf(1, nrow), 64.0, tw * 1.5)
		for tag in DB.D.TAGORDER:
			var ks := Run.pickable(t, tag)
			if ks.is_empty():
				continue
			var row := UI.hbox(int(gap))
			var ic := TextureRect.new()
			ic.texture = DB.ICON.get(tag)
			ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			ic.custom_minimum_size = Vector2(icon_w, th)
			ic.modulate = Color(DB.PAL.bamboo, 0.85)
			row.add_child(ic)
			var g := GridContainer.new()
			g.columns = cols
			g.add_theme_constant_override("h_separation", int(gap))
			g.add_theme_constant_override("v_separation", int(gap))
			for k in ks:
				g.add_child(make_tile.call(k, tw, th))
			row.add_child(g)
			b.add_child(row)
	else:
		# 전설 이상 —— 넷씩 큰 타일, 병종 묶음 + 위 8병종 바로 가기
		var cols := 4
		var tw := floorf((full - gap * (cols - 1)) / cols)
		var th := tw * 1.42
		var groups := {}
		var jump := UI.hbox(4)
		for tag in DB.D.TAGORDER:
			var ks := Run.pickable(t, tag)
			if ks.is_empty():
				continue
			var grp := UI.vbox(6)
			grp.add_child(UI.eyebrow("%s %d" % [tag, ks.size()]))
			var g := GridContainer.new()
			g.columns = cols
			g.add_theme_constant_override("h_separation", int(gap))
			g.add_theme_constant_override("v_separation", 8)
			for k in ks:
				g.add_child(make_tile.call(k, tw, th))
			grp.add_child(g)
			groups[tag] = grp
			var jb := Button.new()
			jb.custom_minimum_size = Vector2(0, 36)
			jb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			jb.icon = DB.ICON.get(tag)
			jb.expand_icon = true
			jb.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
			jb.tooltip_text = tag
			jb.add_theme_stylebox_override("normal", UI.flat(DB.PAL.ink2, DB.PAL.ink4, 1, 8, 4))
			jb.add_theme_stylebox_override("hover", UI.flat(DB.PAL.ink3, DB.PAL.bamboo_dim, 1, 8, 4))
			jb.add_theme_stylebox_override("pressed", UI.flat(DB.PAL.ink4, DB.PAL.gold, 1, 8, 4))
			jb.pressed.connect(func():
				UI.buzz()
				var gp: Control = groups[tag]
				_sheet_scroll.scroll_vertical = int(gp.position.y))
			jump.add_child(jb)
		b.add_child(jump)
		for tag in groups:
			b.add_child(groups[tag])
		b.add_child(UI.hint("위 병종 단추를 누르면 그 묶음으로 갑니다. 길게 누르면 디테일창. 갈무리한 장수는 금색, 그 재료(아래 재료까지)는 옥빛."))
	if was_open:
		_restore_sheet_scroll.call_deferred(_pick_scroll)


func _restore_sheet_scroll(y: int) -> void:
	await get_tree().process_frame
	if _sheet.visible:
		_sheet_scroll.scroll_vertical = y


## 지금 손댈 수 있는가 —— 온라인은 준비 시간에만
func can_act() -> bool:
	return online == null or online.can_act()


# ───────── 카드 상세 ─────────

func card_info(k: String) -> void:
	_route_enter("card", k)
	var c: Dictionary = DB.C[k]
	var p := run.pool()
	var b := open_sheet(c.name, DB.tier_color(k).lightened(0.2))
	var top := UI.hbox(12)
	var big := CardView.new().setup(k, Vector2(132, 188))
	big.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	top.add_child(big)
	# 초상 오른쪽 (11/3 사용자: 초상과 높이를 맞춘다) —— 능력치 다섯 칸 · 특기판 · 접힌 고유 특기 · 위세 · 고유기
	var st := UI.vbox(6)
	st.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	st.custom_minimum_size.y = 188
	st.add_child(_stat_row(c))
	st.add_child(TraitBoard.new().setup(k))
	for t in DB.trait_list(k):
		if t.unique:
			st.add_child(_fold_kv("card_uq", "[b][color=#e8c25a]고유 특기[/color] [color=#FFD76E]『%s』[/color][/b]" % t.name, "", t.mt, Color("#e8c25a")))
	if DB.AURA.has(k):
		st.add_child(_fold_kv("card_aura", "[b][color=%s]%s[/color] 『%s』[/b]" % [DB.tier_color(k).to_html(false), "기인" if DB.is_kiin(k) else "위세", DB.AURA[k].n], "", DB.aura_effect(k), DB.tier_color(k)))
	var u = DB.ult_of(k) if c.tier >= 6 or DB.is_kiin(k) else null
	if u != null:
		st.add_child(_fold_kv("card_ult", "[b][color=#ffd76e]고유기[/color] 『%s』[/b]" % u.name, "%d초부터" % roundi(u.wait), UI.ult_desc(u, c.tier), Color("#ffd76e")))
	top.add_child(st)
	b.add_child(top)
	var folds := UI.vbox(0)          # 11/3 사용자: 접힌 기술 · 특기 · 선호 대열 사이를 좁힌다
	b.add_child(folds)
	# 기술 —— 접힌 칸 하나에 기술마다 효과 · 수치 표
	# 11/5 사용자: 잔기술을 따로 부르지 않는다 —— 자주 쓰는 기술로 기술 목록 맨 앞에 (발동: "평타 3번에 한 번")
	var mk := Battle.minor_kind(k)
	if not c.get("sks", []).is_empty() or mk != "":
		var sk_v := UI.vbox(6)
		if mk != "":
			sk_v.add_child(_kv_box("[color=#D9A64B][b]『%s』[/b][/color]" % Battle.minor_def(mk).n, "평타 %d번에 한 번" % int(Battle.minor_def(mk).every), minor_desc(k, false), DB.PAL.bamboo_dim, 13))
		for x in c.get("sks", []):
			sk_v.add_child(_kv_box("[color=#D9A64B][b]『%s』[/b][/color]" % x.n, DB.sk_when(x), DB.skill_desc(c, x), DB.PAL.bamboo_dim, 13))
		folds.add_child(_fold_sec("card_skills", "기술 %d" % (c.get("sks", []).size() + (1 if mk != "" else 0)), sk_v))
	var tl := DB.trait_list(k)
	if not tl.is_empty():
		# 왼쪽 칸 = 특기 이름+레벨, 오른쪽 = 설명(—— 에서 줄바꿈)과 그 아래 수치. 오른쪽 칸 왼끝이 맞는다
		var tg := _info_grid()
		for t in tl.filter(func(x): return not x.unique):
			var body := "[color=#C6AC7C]%s[/color]%s" % [(t.d as String).replace(" —— ", "\n"), ("\n[color=#8FD4C2]%s[/color]" % t.mt) if t.mt != "" else ""]
			_info_row(tg, "[color=#8FD4C2][b]%s[/b][/color][color=#D9A64B]%d[/color]%s" % [t.name, t.lv, "\n[color=#8D7B5C]단체[/color]" if t.group else ""], body)
		folds.add_child(_fold_sec("card_traits", "특기 %d" % tl.filter(func(x): return not x.unique).size(), tg))
	var ag := _info_grid()
	_info_row(ag, "[color=#8fd4c2]선호[/color]", "%s\n[color=#C6AC7C]%s[/color]" % [UI.aff_zones(c.tag, "pref"), UI.aff_desc(c.tag, "pref")])
	_info_row(ag, "[color=#e0806f]어색[/color]", "%s\n[color=#C6AC7C]%s[/color]" % [UI.aff_zones(c.tag, "bad"), UI.aff_desc(c.tag, "bad")])
	folds.add_child(_fold_sec("card_aff", "선호 대열", ag))

	# 보유 중이면 한 단계 위(이 카드로 만드는 것)를 먼저, 아니면 만드는 법을 먼저 (11/2 사용자)
	var owned: bool = run.pool().get(k, 0) > 0
	var make_sec := UI.vbox(10)
	var up_sec := UI.vbox(10)
	make_sec.add_child(UI.eyebrow("장수 조합법"))
	if DB.RECOF.has(k):
		make_sec.add_child(_up_row(k))
	else:
		make_sec.add_child(UI.hint("기본패 — 조합할 수 없고 징집으로만 얻는다."))
	# 11/6 사용자 #1 "전설에서 상위 조합이 안 나온다": 예전엔 바로 위 등급 조합이 있어야만 보였다 (초월 재료가 아닌 전설 23명은 불멸 · 신화 재료인데도 빈칸)
	# → ① 같은 인물의 다음 칭호판(승급)을 먼저, ② 재료로 쓰이는 조합을 등급별로 모두 (등급마다 4종까지, 모자란 수 적은 순)
	var own := []
	var by_t := {}
	var person_ := DB.person(k)
	for o in Run.used_in(k):
		if DB.person(o) == person_ and DB.C[o].tier > c.tier:
			own.append(o)
		else:
			if not by_t.has(DB.C[o].tier):
				by_t[DB.C[o].tier] = []
			by_t[DB.C[o].tier].append(o)
	own.sort_custom(func(x, y): return DB.C[x].tier < DB.C[y].tier)
	var ts := by_t.keys()
	ts.sort()
	if DB.is_kiin(k):
		up_sec.add_child(UI.eyebrow("기인"))
		up_sec.add_child(UI.hint("같은 기인은 한 판에 한 장. 다른 기인은 여러 장 둘 수 있다. 다른 조합의 재료로 쓰이지 않는다."))
	elif own.is_empty() and ts.is_empty() and c.tier >= 3:
		up_sec.add_child(UI.eyebrow("최종 단계"))
		up_sec.add_child(UI.hint("이 장수는 더 올라가는 길이 없고 다른 조합의 재료로도 쓰이지 않는다 — 완성형."))
	if not own.is_empty():
		up_sec.add_child(UI.eyebrow("승급 · 같은 인물의 %s" % " · ".join(own.map(func(o): return DB.TIER[DB.C[o].tier].n))))
		for o in own:
			up_sec.add_child(_up_row(o))
	for t in ts:
		var lst_: Array = by_t[t]
		lst_.sort_custom(func(x, y): return run.miss_count(x) < run.miss_count(y))
		var can_n := lst_.filter(func(x): return run.can_forge(x)).size()
		up_sec.add_child(UI.eyebrow("%s 조합 재료 · %d종%s" % [DB.TIER[t].n, lst_.size(), " — %d종 지금 조합 가능" % can_n if can_n > 0 else ""]))
		for o in lst_.slice(0, 4):
			up_sec.add_child(_up_row(o))
		if lst_.size() > 4:
			up_sec.add_child(UI.hint("그 밖에 %d종 더 (조합 탭에서 %s 등급으로 거르면 모두 보인다)" % [lst_.size() - 4, DB.TIER[t].n]))

	for sec in ([up_sec, make_sec] if owned else [make_sec, up_sec]):
		if sec.get_child_count() > 0:
			b.add_child(sec)


## 접는 칸 —— 머리줄을 누르면 열고 닫는다. 기본은 닫힘, 연 상태는 _open[key] 에 남아 다른 카드에서도 이어진다
func _fold_sec(key: String, title: String, body: Control) -> Control:
	var v := UI.vbox(6)
	var hb := Button.new()
	hb.flat = true
	hb.alignment = HORIZONTAL_ALIGNMENT_LEFT
	hb.custom_minimum_size.y = 30
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


## 능력치 한 줄 —— 공 · 방 · 속 (11/6 #15 책략 · 책략방어 통합). 책략계는 공격을 푸른색으로 (원거리 · 범위)
func _stat_row(c: Dictionary) -> Control:
	var magic: bool = DB.INT_TAGS.has(c.tag)
	var g := GridContainer.new()
	g.columns = 3
	g.add_theme_constant_override("h_separation", 4)
	g.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for pair in [["공격", c.atk, true, Color("#6fa8ff") if magic else Color("#ff6b5a")], ["방어", c["def"], false, null], ["속도", c.spd, false, null]]:
		var v := UI.vbox(0)
		var a := UI.lbl(str(int(pair[1])), 16, pair[3] if pair[2] else DB.PAL.paper, true)
		a.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		var l := UI.lbl(pair[0], 10, DB.PAL.bamboo_dim)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(a)
		v.add_child(l)
		var pc := UI.panel(v, 2)
		pc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		g.add_child(pc)
	return g


## 전투장수창 (11/6 사용자) —— 전투 중 꾹 눌러 연다. 이미 만든 장수라 재료 · 갈무리는 빼고 전투 요소만:
## 병력 · 사기 · 상태, 공격 · 방어 · 속도 = 기본 수치 + (버프로 늘어난 만큼, 다른 색), 기술 · 고유기 · 특기
func battle_unit_sheet(key: String) -> void:
	var sq: Squad = _battle.field.squads.get(key) if _battle and _battle.field else null
	if sq == null or not DB.C.has(sq.cid):
		return
	var k: String = sq.cid
	var c: Dictionary = DB.C[k]
	var tc := DB.tier_color(k)
	var b := open_sheet(c.name, tc.lightened(0.2))
	var ss: Dictionary = _battle.start_stats(key)
	var top := UI.hbox(12)
	var big := CardView.new().setup(k, Vector2(96, 136))
	big.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	top.add_child(big)
	var right := UI.vbox(6)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var camp := "아군" if sq.camp == "A" else "적군"
	var pos := ""
	var fk := str(_battle.res.get("aForm" if sq.camp == "A" else "bForm", ""))
	var si := int(key.substr(1))
	if DB.FORM.has(fk) and si >= 0 and si < DB.FORM[fk].slots.size():
		var sl: Dictionary = DB.FORM[fk].slots[si]
		pos = UI.pos_name(str(sl.line), int(sl.col))
	right.add_child(UI.rich("[color=%s][b]%s[/b][/color]  [color=#C6AC7C]%s · %s%s[/color]" % [
		War3D.TEAM[sq.camp].lightened(0.3).to_html(false), camp, DB.tier_name(k), c.tag, (" · " + pos) if pos != "" else ""], 13))
	var state := ("%s / %s명" % [Battle.num(sq.troops), Battle.num(sq.max)]) if sq.alive else ("궤멸" if sq.troops <= 0 else "패주")
	right.add_child(UI.rich("[color=#8D7B5C]병력[/color] [b]%s[/b]   [color=#8D7B5C]사기[/color] [b]%d[/b]" % [state, roundi(sq.morale)], 14))
	if not sq.statuses.is_empty():
		var names := []
		for st in sq.statuses:
			names.append(str(DB.D.STATUS.get(st, {}).get("n", st)))
		right.add_child(UI.rich("[color=#8D7B5C]상태[/color] [color=#ff9a7a]%s[/color]" % " · ".join(names), 13))
	# 공격 · 방어 · 속도 —— 큰 숫자 = 기본, 옆 작은 숫자 = 버프로 늘어난 값(더한 결과가 아니라 늘어난 만큼만)
	var g := GridContainer.new()
	g.columns = 3
	g.add_theme_constant_override("h_separation", 4)
	g.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for pair in [["공격", "atk"], ["방어", "def"], ["속도", "spd"]]:
		var base: float = float(c[pair[1]])
		var got: float = ss[pair[1]][1] if ss.has(pair[1]) else base
		var raw: float = ss[pair[1]][2] if ss.has(pair[1]) else base
		var d := roundi(raw - base)          # 버프로 늘어난 만큼 (초록)
		var cutv := roundi(raw - got)        # 적 효과로 깎인 만큼 (빨강)
		var v := UI.vbox(0)
		var bb := "[center][b][font_size=17]%d[/font_size][/b]" % roundi(base)
		if d != 0:
			bb += " [color=%s][font_size=13]%s%d[/font_size][/color]" % ["#7fe0a8" if d > 0 else "#ff7a6a", "+" if d > 0 else "−", absi(d)]
		if cutv > 0:
			bb += " [color=#ff7a6a][font_size=13]−%d[/font_size][/color]" % cutv
		bb += "[/center]"
		var a := UI.rich(bb, 13)
		a.fit_content = true
		var l := UI.lbl(pair[0], 10, DB.PAL.bamboo_dim)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(a)
		v.add_child(l)
		var pc := UI.panel(v, 2)
		pc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		g.add_child(pc)
	right.add_child(g)
	if ss.is_empty():
		right.add_child(UI.hint("온라인 재생은 버프 수치를 계산하지 않는다 —— 기본 수치만."))
	else:
		var why := []
		var lm: Dictionary = DB.D.LINE.get(ss.line, {})
		if not lm.is_empty():
			why.append("%s 공격 ×%.2f · 방어 ×%.2f" % [ss.line, float(lm["int"] if Battle.is_caster(c) else lm.atk), float(lm["def"])])
		var z := DB.aff_of(c.tag, ss.line, ss.side)
		if z != "":
			why.append("자리 %s" % ("선호" if z == "pref" else "어색"))
		if ss.boon:
			why.append("진형 우대 %s +%d%%" % [DB.D.STATNM.get(ss.boon.stat, ss.boon.stat), roundi(float(ss.boon.v) * 100)])
		if ss.item:
			why.append("보급품 %s" % DB.IT[ss.item].name)
		right.add_child(UI.rich("[color=#7fe0a8]＋늘어난 값[/color] [color=#8D7B5C]%s · 단체 특기 · 위세 · 사기[/color]  [color=#ff7a6a]−깎인 값[/color] [color=#8D7B5C]적 효과 (전투 시작 기준)[/color]" % " · ".join(why), 11))
	top.add_child(right)
	b.add_child(top)
	# 고유기
	var u = DB.ult_of(k) if c.tier >= 6 or DB.is_kiin(k) else null
	if u != null:
		b.add_child(_kv_box("[b][color=#ffd76e]고유기[/color] 『%s』[/b]" % u.name, "%d초부터" % roundi(u.wait), UI.ult_desc(u, c.tier), Color("#ffd76e"), 13))
	# 기술 (자주 쓰는 기술 + 일반 기술)
	var mk := Battle.minor_kind(k)
	if mk != "":
		b.add_child(_kv_box("[color=#D9A64B][b]『%s』[/b][/color]" % Battle.minor_def(mk).n, "평타 %d번에 한 번" % int(Battle.minor_def(mk).every), minor_desc(k, false), DB.PAL.bamboo_dim, 13))
	for x in c.get("sks", []):
		b.add_child(_kv_box("[color=#D9A64B][b]『%s』[/b][/color]" % x.n, DB.sk_when(x), DB.skill_desc(c, x), DB.PAL.bamboo_dim, 13))
	# 특기 —— 이름 · 레벨 · 수치 한 줄씩
	var tl := DB.trait_list(k)
	if not tl.is_empty():
		var tg := _info_grid()
		for t in tl:
			_info_row(tg, "[color=%s][b]%s[/b][/color][color=#D9A64B]%s[/color]" % ["#FFD76E" if t.unique else "#8FD4C2", t.name, "" if t.unique else str(t.lv)],
				"[color=#8FD4C2]%s[/color]" % (t.mt if t.mt != "" else (t.d as String).get_slice(" —— ", 0)))
		b.add_child(UI.eyebrow("특기 %d" % tl.size()))
		b.add_child(tg)
	if DB.AURA.has(k):
		b.add_child(_kv_box("[b][color=%s]%s[/color] 『%s』[/b]" % [tc.to_html(false), "기인" if DB.is_kiin(k) else "위세", DB.AURA[k].n], "", DB.aura_effect(k), tc, 13))


## 접히는 효과 · 수치 상자 —— 머리줄(이름)을 누르면 표가 열린다. 기본은 접힘, 연 상태는 _open[key] 로 다른 카드에서도 이어진다
func _fold_kv(key: String, head_bb: String, sub: String, body: String, col: Color) -> Control:
	var box := _kv_box(head_bb, sub, body, col, 12)
	var v: VBoxContainer = box.get_child(0)
	var head: RichTextLabel = v.get_child(0)
	var grid: Control = v.get_child(1)
	var arrow := UI.lbl("", 15, DB.PAL.bamboo)
	var hr := UI.hbox(4)
	v.remove_child(head)
	hr.add_child(head)
	arrow.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hr.add_child(arrow)
	v.add_child(hr)
	v.move_child(hr, 0)
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var upd := func():
		var on: bool = _open.get(key, false)
		grid.visible = on
		arrow.text = "▾" if on else "▸"
	box.mouse_filter = Control.MOUSE_FILTER_STOP
	box.gui_input.connect(func(e):
		if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT and not e.pressed:
			UI.buzz()
			_open[key] = not _open.get(key, false)
			upd.call())
	upd.call()
	return box


## 효과 · 수치 표 상자 (11/3 사용자: '효과, 수치' 식으로 이쁘게) —— 머리줄(이름 · 부제) 아래 두 칸 표.
## body 는 "아군 책략 +10% / 적 책략방어 −10%" 처럼 ' · ' · ' / ' 로 나뉜 글 —— 끝의 수치를 오른쪽 칸으로 뗀다
func _kv_box(head_bb: String, sub: String, body: String, col: Color, fs := 12) -> PanelContainer:
	var pc := PanelContainer.new()
	var sb := UI.flat(DB.PAL.ink2, col, 0, 4, 6)
	sb.border_width_left = 3
	sb.content_margin_left = 9
	sb.content_margin_right = 8
	pc.add_theme_stylebox_override("panel", sb)
	var v := UI.vbox(3)
	var h := UI.rich(head_bb + ("  [color=#8D7B5C][font_size=%d]%s[/font_size][/color]" % [fs - 1, sub] if sub != "" else ""), fs + 1)
	h.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_child(h)
	v.add_child(_kv_grid(body, fs))
	pc.add_child(v)
	return pc


## 효과 · 수치 두 칸 표 —— 왼쪽 효과(줄 바꿈), 오른쪽 수치(오른쪽 맞춤)
func _kv_grid(body: String, fs := 12) -> GridContainer:
	var g := GridContainer.new()
	g.columns = 2
	g.add_theme_constant_override("h_separation", 8)
	g.add_theme_constant_override("v_separation", 1)
	g.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for kv in _kv_split(body):
		var l := UI.lbl(kv[0], fs, DB.PAL.bamboo)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		g.add_child(l)
		var r := UI.lbl(kv[1], fs, Color("#8FD4C2"), true)
		r.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		r.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		g.add_child(r)
	return g


static var _num_re: RegEx

## "적 전체에 책략 319%" → ["적 전체에 책략", "319%"], 끝에 수치가 없으면 ["대상 혼란", ""]
func _kv_split(text: String) -> Array:
	if _num_re == null:
		_num_re = RegEx.create_from_string("([+\\-−×]?\\s?\\d[\\d,]*(?:\\.\\d+)?\\s?(?:%p|%|턴|초|부대|명)?)\\s*$")
	var out := []
	for part in text.replace(" / ", " · ").replace("\n", " · ").split(" · "):
		var s := part.strip_edges()
		if s == "":
			continue
		var m := _num_re.search(s)
		if m and m.get_start() > 0:
			out.append([s.substr(0, m.get_start()).strip_edges(), m.get_string(1).replace(" ", "")])
		else:
			out.append([s, ""])
	return out


## 잔기술 설명 (Battle.MINOR · minor_kind) —— "평타 3번에 한 번 · 책략 피해 ×0.90 · 화상"
static func minor_desc(k: String, with_every := true) -> String:
	var mk := Battle.minor_kind(k)
	var m: Dictionary = Battle.minor_def(mk)
	var phys: bool = (m.kind == "phys") if m.has("kind") else DB.C[k]["int"] <= DB.C[k].atk
	var parts := ["평타 %d번에 한 번" % int(m.every)] if with_every else []
	parts.append("%s피해 ×%.2f" % ["적 후열에 " if m.get("back", false) else "", float(m.mult)])
	if m.has("st"):
		parts.append("%s %d턴" % [DB.D.STATUS[m.st[0]].n, int(m.st[2])])
	if m.has("extra"):
		parts.append("한 번 더 ×%.1f" % float(m.extra))
	if m.has("self"):
		parts.append("자신 %s %+d%%(%d턴)" % [DB.D.STATNM.get(m.self.stat, m.self.stat), roundi(float(m.self.amt) * 100), int(m.self.dur)])
	if m.has("foe"):
		parts.append("맞은 적 %s %+d%%(%d턴)" % [DB.D.STATNM.get(m.foe.stat, m.foe.stat), roundi(float(m.foe.amt) * 100), int(m.foe.dur)])
	if m.has("morale"):
		parts.append("적 사기 −%d" % int(m.morale))
	if m.has("mend") and m.has("cheer"):
		parts.append("가장 지친 아군 병력 +%s%% · 사기 +%d" % [str(snappedf(float(m.mend) * 100, 0.1)), int(m.cheer)])
	elif m.has("mend"):
		parts.append("가장 지친 아군 병력 +%s%%" % str(snappedf(float(m.mend) * 100, 0.1)))
	elif m.has("cheer"):
		parts.append("가장 지친 아군 사기 +%d" % int(m.cheer))
	return " · ".join(parts)


## 왼쪽에 색 띠가 있는 상자 —— 디테일창의 위세 · 고유기 · 고유 특기 · 기술 (11/3)
func _bar_box(bb: String, col: Color, fs := 13) -> PanelContainer:
	var pc := PanelContainer.new()
	var sb := UI.flat(DB.PAL.ink2, col, 0, 4, 6)
	sb.border_width_left = 3
	sb.content_margin_left = 9
	pc.add_theme_stylebox_override("panel", sb)
	var r := UI.rich(bb, fs)
	r.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pc.add_child(r)
	return pc


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
				for kk in DB.C:      # 이름이 같은 카드가 여러 등급에 있을 수 있다 (11/4 전설 이름만) —— 플레이어 카드만
					if DB.C[kk].name == me and not DB.is_foe(kk):
						card_info(kk)
						return
				close_sheet(), "pri", 48)
		fb.custom_minimum_size = Vector2(64, 48)
		fb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(fb)
	# 갈무리 —— 보유하지 않은 장수도 디테일창에서 바로 (11/2 사용자)
	var pn := forge_tree.pinned(out)
	var pb := UI.btn("갈무리 해제" if pn else "갈무리", func():
		forge_tree.toggle(out)
		_back_nav = true
		card_info(_route.get("k", out)), "ghost" if pn else "", 48)
	pb.custom_minimum_size = Vector2(72, 48)
	pb.add_theme_font_size_override("font_size", 14)
	pb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(pb)
	v.add_child(h)
	var chips := UI.grid(40, 6)     # 재료 4열 —— 재료가 4개면 한 줄 (11/2 사용자)
	chips.max_cols = 4
	var m := Run.mat_count(DB.RECOF[out])
	for q in m:
		var got := run.have(q)
		var ok: bool = got >= m[q]
		var qn: String = DB.person(q) if DB.C[q].tier > 2 else DB.C[q].name
		var cb := UI.btn("%s %d/%d" % [qn, got, m[q]], func(): card_info(q), "", 40)      # 기호 없이 색으로 (4열에 이름이 잘렸다)
		for st in ["normal", "hover", "pressed"]:
			cb.add_theme_stylebox_override(st, UI.flat(DB.PAL.ink2, Color("#8fd4c2") if ok else Color("#e0806f", 0.6), 1, 8, 2))
		cb.add_theme_color_override("font_color", Color("#8fd4c2") if ok else Color("#e0806f"))
		cb.add_theme_font_size_override("font_size", 12)
		cb.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		cb.clip_text = true
		cb.custom_minimum_size.x = 40
		chips.add_child(cb)
	var ni = Run.need_item(out)
	if ni != null:
		var ok: bool = run.bag.get(ni, 0) > 0
		# 유니크 재료도 재료 칸처럼 (11/3 —— 글씨가 칸 밖으로 삐져나왔다). 누르면 아이템 시트
		var ib := UI.btn("◆%s %d/1" % [DB.IT[ni].name, run.bag.get(ni, 0)], func(): _item_sheet(ni), "", 40)
		var icol := Color("#d59700") if ok else Color("#e0806f")
		for st in ["normal", "hover", "pressed"]:
			ib.add_theme_stylebox_override(st, UI.flat(DB.PAL.ink2, Color(icol, 0.8), 1, 8, 2))
		ib.add_theme_color_override("font_color", icol)
		ib.add_theme_font_size_override("font_size", 12)
		ib.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		ib.clip_text = true
		ib.custom_minimum_size.x = 40
		chips.add_child(ib)
	v.add_child(chips)
	return UI.panel(v, 10)


# ───────── 조합 ─────────

func _toggle(key: String, default := false) -> void:
	_open[key] = not _open.get(key, default)
	render()


const KIIN_T := 9      # 등급 거르기의 기인 칸

## 추천 목표 —— 점수는 Run.forge_goals (덱이 얻는 전력 − 모자란 재료를 구하는 수고 + 줄기 · 병종 맞춤, 11/5 사용자: 플레이에 도움이 되게)
func _forge_goals(lst: Array) -> Array:
	var cand: Array = run.forge_goals(lst.map(func(r): return r[0]), 4).map(func(k): return [0, k])
	var out_ := []
	var seen := {}
	# 11/5 사용자: 신화 장수가 없는데 신화 아이템(유니크)을 가지고 있으면 추천 1번은 그 신화 장수 (재료가 몇 장 모자라든)
	if not run.has_myth():
		for k in DB.by_tier(8):
			var it = Run.need_item(k)
			if it != null and run.bag.get(it, 0) > 0 and DB.RECOF.has(k) and not DB.is_foe(k) and (forge_tag == "" or DB.C[k].tag == forge_tag):
				out_.append(k)
				seen[DB.person(k)] = true
				break
	for c in cand:
		var p := DB.person(c[1])
		if seen.has(p):
			continue
		seen[p] = true
		out_.append(c[1])
		if out_.size() >= 4:
			break
	return out_


## 히든(불멸) 이상 완성 연출 (scripts/ui/forge_fanfare.gd). 모두 조합으로 여러 장이 잇달아 나오면 가장 높은 것 하나만
var _fanfare: ForgeFanfare = null
func _forge_fanfare(k: String) -> void:
	if is_instance_valid(_fanfare):
		if DB.C[_fanfare.k].tier >= DB.C[k].tier:
			return
		_fanfare.queue_free()
	_fanfare = ForgeFanfare.new()
	_fanfare.k = k
	add_child(_fanfare)


## 같은 인물의 이 등급 이상 카드를 이미 가지고 있는가 (손패 · 편성 모두)
func _owns_person_at(out: String) -> bool:
	var p := DB.person(out)
	var t: int = DB.C[out].tier
	for k in run.pool():
		if DB.C[k].tier >= t and DB.C[k].tier >= 3 and DB.person(k) == p:
			return true
	return false


## 모자란 재료 이름 (짧게)
func _missing(out: String) -> Array:
	var need := Run.mat_count(DB.RECOF[out])
	var miss := []
	for m in need:
		var lack: int = int(need[m]) - (run.have(str(m)) if DB.C.has(str(m)) else 0)
		if lack > 0 and DB.C.has(str(m)):
			miss.append(DB.person(str(m)) + ("×%d" % lack if lack > 1 else ""))
	var ni = Run.need_item(out)
	if ni != null and run.bag.get(ni, 0) <= 0:
		miss.append(DB.IT[ni].name)
	return miss

func _tier_match(k: String, t: int) -> bool:
	if t == 0:
		return true
	if t == KIIN_T:
		return DB.is_kiin(k)
	return DB.C[k].tier == t and not DB.is_kiin(k)


func _page_forge() -> Control:
	var v := UI.vbox(14)
	v.add_child(forge_tree.build())
	# 거르기 —— 병종 · 등급을 기호 · 색 칸 한 줄씩 (11/2 사용자: 글씨를 줄여 공간 확보)
	var row1 := HBoxContainer.new()
	row1.add_theme_constant_override("separation", 4)
	for t in [""] + DB.D.TAGORDER:
		var n: int = DB.D.RECDEF.filter(func(r): return run.can_forge(r[0]) and (t == "" or DB.C[r[0]].tag == t)).size()
		row1.add_child(_filter_chip("all" if t == "" else "", DB.ICON.get(t) if t != "" else null, str(n) if n > 0 else "", DB.PAL.paper, forge_tag == t, func():
			forge_tag = t
			_forge_more = 0
			render()))
	v.add_child(row1)
	var row2 := HBoxContainer.new()
	row2.add_theme_constant_override("separation", 4)
	for t in [0, 3, 4, 5, KIIN_T, 6, 7, 8]:        # 11/3 일반 없음 · 기인(9)은 전설 옆
		var tn: String = "all" if t == 0 else ("기" if t == KIIN_T else DB.TIER[t].n.left(1))
		row2.add_child(_filter_chip(tn, null, "", DB.PAL.paper if t == 0 else (DB.KIIN_COL if t == KIIN_T else DB.TIER[t].c), forge_tier == t, func():
			forge_tier = t
			_forge_more = 0
			render()))
	v.add_child(row2)
	var lst: Array = DB.D.RECDEF.filter(func(r): return (forge_tag == "" or DB.C[r[0]].tag == forge_tag) and _tier_match(r[0], forge_tier))
	# 11/3 추천 목표 —— 조합식이 170개가 넘어 무엇을 노릴지 고르기 어렵다: 재료가 1~2장 모자란 것 가운데 높은 등급 · 가진 재료가 많은 것 4개 (인물 하나씩)
	# 11/6 사용자 #8 "추천 목표가 안 나오는 경우가 많다": 필터를 거친 목록만 넘겨 비었다 → 전체로 계산하고 필터에 걸린 것은 수만 알린다
	var rec_all := _forge_goals(DB.D.RECDEF)
	var rec: Array = rec_all.filter(func(o): return (forge_tag == "" or DB.C[o].tag == forge_tag) and _tier_match(o, forge_tier))
	var hidden_n := rec_all.size() - rec.size()
	var far_goal := false
	if rec_all.is_empty():      # 수고 한도 안에 아무것도 없다 —— 가장 가까운 목표 하나는 보인다
		rec_all = run.forge_goals(DB.D.RECDEF.map(func(r): return r[0]), 1, 1e9)
		rec = rec_all.filter(func(o): return (forge_tag == "" or DB.C[o].tag == forge_tag) and _tier_match(o, forge_tier))
		hidden_n = rec_all.size() - rec.size()
		far_goal = not rec.is_empty()
	if not rec.is_empty() or hidden_n > 0:
		var gsec := UI.vbox(6)
		gsec.add_child(UI.head("추천 목표" if not far_goal else "가장 가까운 목표", ("필터에 숨은 추천 %d" % hidden_n) if hidden_n > 0 else ""))
		var gs_ := UI.strip(8)
		for out in rec:
			var gv := UI.vbox(3)
			gv.custom_minimum_size = Vector2(86, 0)
			var gt := mtile(out, run.pool().get(out, -1), func(id): recipe_sheet(id))
			gt.custom_minimum_size = Vector2(86, 112)
			gt.badge = "-%d" % run.miss_count(out) if run.miss_count(out) > 0 else "조합"
			gt.badge_col = Color(DB.PAL.seal, 0.9)
			gv.add_child(gt)      # 11/5 사용자: 아래에 모자란 장수 이름은 쓰지 않는다
			gs_[1].add_child(gv)
		if not rec.is_empty():
			gsec.add_child(gs_[0])
		if rec.is_empty() and hidden_n > 0:
			gsec.add_child(UI.hint("지금 필터(병종 · 등급)에 맞는 추천이 없습니다. 필터를 '모두'로 두면 %d개가 보입니다." % hidden_n))
		v.add_child(gsec)
	# 지금 되는 것 —— 가로 띠, 버튼 한 번에 조합
	var ready: Array = lst.filter(func(r): return run.can_forge(r[0]))
	ready.sort_custom(func(x, y): return DB.C[x[0]].tier > DB.C[y[0]].tier)
	if not ready.is_empty():
		var sec := UI.vbox(6)
		sec.add_child(UI.head("지금 조합 가능 %d" % ready.size(), ""))
		var rs := UI.strip(8)
		for r in ready:
			rs[1].add_child(recipe_card(r[0]))
		sec.add_child(rs[0])
		v.add_child(sec)
	# 나머지 —— 가까운 순 (모자란 장수 적은 것 먼저, 같으면 높은 등급)
	lst = lst.filter(func(r): return not run.can_forge(r[0]) and not rec.has(r[0]))
	lst.sort_custom(func(x, y):
		var a := run.miss_count(x[0])
		var b2 := run.miss_count(y[0])
		if a != b2:
			return a < b2
		return DB.C[x[0]].tier > DB.C[y[0]].tier)
	var show_n := 16 + _forge_more      # 11/3 처음엔 가까운 16개만 (나머지는 더 보기)
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
	sec2.add_child(UI.head(("나머지 %d" if not ready.is_empty() else "조합법 %d") % lst.size(), ""))
	sec2.add_child(g if not lst.is_empty() else UI.hint("이 조건의 조합법이 없다."))
	if lst.size() > show_n:
		sec2.add_child(UI.btn("더 보기 (%d개 남음)" % (lst.size() - show_n), func():
			_forge_more += 40
			render(), "ghost", 46))
	v.add_child(sec2)
	return v


## 거르기 칸 —— 글씨 대신 기호(병종) · 색(등급). 고르면 밝은 테두리, 오른쪽 위 작은 숫자 = 지금 조합 가능 수
func _filter_chip(txt: String, icon, cnt: String, col: Color, on: bool, cb: Callable) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(0, 34)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var tier_col: bool = icon == null and txt != "all"
	var bg: Color = Color(col, 0.85) if tier_col else (DB.PAL.ink3 if on else DB.PAL.ink2)
	var bd: Color = DB.PAL.paper if on else (Color(col, 0.0) if tier_col else DB.PAL.ink4)
	for st in ["normal", "hover", "pressed"]:
		var sb := UI.flat(bg, bd, 2 if on else 1, 8, 0)
		if tier_col and not on:
			sb.bg_color = Color(col, 0.4)
		b.add_theme_stylebox_override(st, sb)
	if icon != null:
		b.icon = icon
		b.expand_icon = false
		b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		b.add_theme_constant_override("icon_max_width", 16)      # 병종 기호 SVG 가 크게 구워져 있다
		b.add_theme_color_override("icon_normal_color", DB.PAL.paper if on else DB.PAL.bamboo)
	else:
		b.text = "전체" if txt == "all" else txt
		b.add_theme_font_size_override("font_size", 12)
		b.clip_text = true
		b.add_theme_color_override("font_color", Color("#1A1508") if tier_col and on else DB.PAL.paper)
	if cnt != "":
		var l := UI.lbl(cnt, 10, DB.PAL.gold, true)
		l.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
		l.offset_left = -12
		l.offset_top = 1
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(l)
	b.pressed.connect(func():
		UI.buzz()
		cb.call())
	return b


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
		# 11/4 사용자: 토벌 · 대전을 한 줄에, 설명 글은 빼고, 남는 공간에 지금 배치된 진영을 그린다
		v.add_child(UI.lbl("%s요일 %s" % [Run.DAYNAME[run.day], Run.PHASE_N[run.phase]], 20, DB.PAL.paper, true))
		var row := UI.hbox(8)
		var qa := UI.act("토벌 완료" if run.quest_done else "① 토벌", "" if run.quest_done else run.quest_name(),
			func(): _start("quest"), "warn", run.quest_done or placed == 0)
		qa.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(qa)
		var pa := UI.act("대전 완료" if run.pvp_done else "② 대전", "" if run.pvp_done else ("임의 세력" if run.quest_done else "토벌 뒤"),
			func(): _start("pvp"), "pri", run.pvp_done or placed == 0 or not run.quest_done)
		pa.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(pa)
		v.add_child(row)
		# 11/3 기인 점복 관로 —— 편성에 있으면 이번 토벌의 적 편성을 미리 본다
		var qr = run.quest_roster()
		if qr != null and not run.quest_done and run.board.has(DB.kiin_card("wind_slow")):
			var pv := UI.vbox(6)
			pv.add_child(UI.rich("[b][color=%s]점괘[/color][/b]  관로가 이번 토벌의 적진을 내다본다" % DB.KIIN_COL.to_html(false), 13))
			var qg := minis()
			var qs: Array = qr.cards.duplicate()
			qs.sort_custom(func(x, y): return DB.C[x].tier > DB.C[y].tier)
			for k in qs:
				qg.add_child(mtile(k, -1, func(id): card_info(id)))
			pv.add_child(qg)
			v.add_child(UI.panel(pv, 10))
		if placed == 0:
			v.add_child(UI.btn("편성이 비어 있다 — 편성하러 가기", func(): go("deploy"), "gold"))
		if run.last_result != null:
			v.add_child(_result_panel())
		if run.can_next():
			var nxt: String = "%s요일 오전" % Run.DAYNAME[mini(6, run.day + 1)] if run.phase == 2 else Run.PHASE_N[run.phase + 1]
			v.add_child(UI.act("다음 페이즈로", nxt, func():
				PlayLog.phase_end(run)
				run.advance()
				run.save()
				if run.over != null:
					PlayLog.over(run)
				go("draw"), "pri"))
	if not run.is_tour_phase() and placed > 0:
		var fv := FormationView.new().setup(run.board, run.form)
		fv.on_medal = func(k): card_info(k)      # 11/5 사용자: 메달을 누르면 장수 상세
		fv.custom_minimum_size.y = 180
		fv.size_flags_vertical = Control.SIZE_EXPAND_FILL
		var fp := UI.panel(fv, 0)
		fp.size_flags_vertical = Control.SIZE_EXPAND_FILL
		v.size_flags_vertical = Control.SIZE_EXPAND_FILL
		v.add_child(fp)
	return v


func _result_panel() -> Control:
	# 11/4 사용자: 레이아웃 정리 —— 왼쪽 큰 결과 글자, 오른쪽 전투 이름, 아래 한 줄에 잔존 · 수훈 · 보상 칩
	var r: Dictionary = run.last_result
	var col := Color("#8fd4c2") if r.win else Color("#e0806f")
	var v := UI.vbox(8)
	var h := UI.hbox(10)
	var big := UI.lbl("무승부" if r.draw else ("승리" if r.win else "패배"), 24, col, true)
	big.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(big)
	var tl := UI.lbl(str(r.title), 14, DB.PAL.bamboo)
	tl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(tl)
	v.add_child(h)
	var chips := UI.flow(6)
	var add := func(txt: String, c: Color):
		var pc := PanelContainer.new()
		pc.add_theme_stylebox_override("panel", UI.flat(Color(c, 0.14), Color(c, 0.6), 1, 10, 5))
		pc.add_child(UI.lbl(txt, 12, c.lightened(0.2), true))
		chips.add_child(pc)
	add.call("잔존 %d : %d" % [r.left, r.eLeft], DB.PAL.bamboo)
	if r.mvp != "":
		add.call("수훈 %s" % r.mvp, DB.PAL.gold)
	if run.last_spoil != null:
		add.call("기본패 +%d" % run.last_spoil.n, DB.PAL.jade)
	if run.ticket_left() > 0:
		add.call("선택권 %d" % run.ticket_left(), Color("#d9a64b"))
	v.add_child(chips)
	return UI.panel(v, 12)


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
	PlayLog.battle_start(run, bt)
	close_sheet()
	_battle_res = null
	_battle_done.visible = false
	_hide_report()
	_battle_layer.visible = true
	_hide_band()
	Settings.apply_port(_battle.port)
	_battle.play(bt, false)


## 온라인 —— 서버가 계산한 결과를 재생만 한다
func show_battle(res: Dictionary, last: bool, kind := "") -> void:
	close_sheet()
	_battle_res = null
	_battle_done.visible = false
	_hide_report()
	_battle_done.text = "결과 정리  ▶" if last else "다음 전투  ▶"
	_battle_layer.visible = true
	_hide_band()
	Settings.apply_port(_battle.port)
	_battle.play_res(res, kind)


func hide_battle() -> void:
	_battle_layer.visible = false
	_resume_bands()


func _resume_bands() -> void:
	if not _band_busy and not _bands.is_empty():
		_next_band.call_deferred()


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
	if _battle and _battle.end_clock > 0:
		res["view_len"] = _battle.end_clock
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
	_battle_done.offset_top = -250      # 11/3 사용자: 아래 장수 칸을 덮지 않게 위로 —— 결과표가 자리 잡으면 그 바로 아래로
	_battle_done.offset_bottom = -192
	await get_tree().process_frame
	await get_tree().process_frame
	if _report == null or not is_instance_valid(_report):
		return
	var top := _report.get_global_rect().end.y + 10.0 - _battle_layer.get_global_rect().end.y
	_battle_done.offset_top = minf(top, -228.0)
	_battle_done.offset_bottom = _battle_done.offset_top + 58.0


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
	PlayLog.battle_end(run, run.battle, _battle_res, _battle.end_clock, _battle.inputs, _battle.speed_sec)
	run.finish_battle(_battle_res)
	_battle_res = null
	run.save()
	PlayLog.after_battle(run)
	_battle_layer.visible = false
	_resume_bands()
	if run.last_spoil != null and run.last_result.kind != "tour":
		toast("기본패 %d장 획득 — %s" % [run.last_spoil.n, run.last_spoil.src], "gain")
	go("war")


# ───────── 계보 ─────────

func _page_line() -> Control:
	# 11/3 사용자: 계보는 '조합 목록'(병종별 장수) 하나만 —— 등급표 · 진행도 · 신화 경로는 뺐다
	var v := UI.vbox(16)
	var p := run.pool()
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
		var rows_t := [8, 7, 6, KIIN_T, 5, 4, 3, 1]
		for t in rows_t:
			var ks: Array = Run.by_tier_tag(5 if t == KIIN_T else t, tag).filter(func(k): return DB.is_kiin(k) == (t == KIIN_T))
			if ks.is_empty():
				continue
			lv.add_child(UI.lbl("기인" if t == KIIN_T else DB.TIER[t].n, 14, DB.KIIN_COL if t == KIIN_T else DB.TIER[t].c, true))
			var f := UI.flow(6)
			for k in ks:
				var c: Dictionary = DB.C[k]
				var has: bool = p.get(k, 0) > 0
				var b := UI.btn("%s%s%s" % [c.name, "★" if c.kind == "myth" else "", (" ×%d" % p[k]) if has else ""], func(): recipe_sheet(k) if DB.RECOF.has(k) else card_info(k), "", 42)
				b.add_theme_font_size_override("font_size", 14)
				b.add_theme_color_override("font_color", DB.tier_color(k) if has else Color(DB.PAL.paper, 0.55))
				if has:
					b.add_theme_stylebox_override("normal", UI.flat(DB.PAL.ink3, DB.tier_color(k), 1, 8, 10))
				f.add_child(b)
			lv.add_child(f)
		lv0.add_child(UI.panel(lv))
	v.add_child(UI.sect("조합 목록", lv0))
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
		if r.me:      # 11/5 사용자: 봇 플레이어의 세력 표기 · PV 는 순위에서 뺀다
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
		if r.me or r.dead:
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
	if a.has("gcube"):       # 점검용 —— 큐브 병사
		War3D.cube_mode = a.gcube != "0"
	if a.has("gdens"):       # 점검용 —— 병사 밀도 (Squad.DENSITY)
		Squad.DENSITY = float(a.gdens)
	if a.has("gq"):
		Settings.quality = int(a.gq)
		Settings.apply()
	if a.has("gnew"):
		PlayLog.enabled = false        # 점검 실행은 플레이 기록에 섞지 않는다
		Run.dev_immortal = true        # 11/5 사용자: 자동 진행은 멸망하지 않는다
		run = Run.new()
		run.new_game(int(a.gnew))
		for i in int(a.get("gplay", "0")):
			run.dev_autoplay()
		_title.visible = false
		if a.has("gseg"):
			deploy.seg = str(a.gseg)      # 점검용 —— 편성 아래 칸 (hand · syn · item)
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
			"uniq": _unique_sheet()
			"pick":      # 점검용 —— --gsheet=pick:등급 (선택권을 2장 쥐여 주고 연다)
				run.tickets[kv[1]] = maxi(2, int(run.tickets.get(kv[1], 0)))
				picker(int(kv[1]))
			"pickfx": _pick_fx(kv[1], 2, "전설")      # 점검용 —— 선택권 고른 연출
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
	if a.has("gmul"):           # 점검용 —— 탑뷰 병사 배율 (기본 1.5)
		War3D.gpu_mul_t2 = float(a.gmul)
	if a.has("gperf"):          # 점검용 —— 성능 표시 켜기 (저장하지 않는다)
		Settings.perf_hud = a.gperf != "0"
	if a.has("gtype2"):          # 점검용 —— 타입2 전장 (저장하지 않는다)
		Settings.type2 = a.gtype2 != "0"
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
		if a.has("gunit"):      # 점검용 —— --gunit=A0 : 3초 뒤 전투장수창
			await get_tree().create_timer(3.0).timeout
			battle_unit_sheet(str(a.gunit))
		if a.has("gcam"):       # 점검용 카메라 —— 거리:높이각
			var cv: PackedStringArray = str(a.gcam).split(":")
			await get_tree().create_timer(4.0).timeout
			var fsq: Squad = _battle.field.order[0]
			for q in _battle.field.order:      # --gtag=기병 —— 그 병종 부대를 본다
				if q.tag == str(a.get("gtag", "")):
					fsq = q
					break
			_battle.field.follow_squad(fsq)
			_battle.field.want_dist = float(cv[0])
			if cv.size() > 1:
				_battle.field.want_pitch = float(cv[1])
		if a.has("gpause"):      # 점검용 —— 이 초 뒤 일시정지
			get_tree().create_timer(float(a.gpause)).timeout.connect(func(): _battle._set_speed(0.0))
		if a.has("gstill"):      # 점검용 —— 자동 카메라를 멈춘다 (프레임 간 차이로 깜빡임 찾기)
			await get_tree().create_timer(float(a.gstill)).timeout
			_battle.field.director = false
			_battle.field.follow = null
			_battle.field._manual = 1e9
		if a.has("gclose"):
			# 끝나면 1초 뒤 결과 정리를 누른 것처럼 —— 저장·보상 흐름 점검
			await _battle.ended
			await get_tree().create_timer(1.0).timeout
			_on_battle_close()
			print("전투 정리: %s · 길이 %.1f초(배율 %.2f) · 토벌 %s · 대전 %s · 경고 %d · 선택권 %d · 저장 %s" % [run.last_result.title, _battle.end_clock, _battle.pace,
				run.quest_done, run.pvp_done, run.strikes, run.ticket_left(), Run.has_save()])
	if a.has("gfps"):        # --gfps=초 --gbattle=… —— vsync 끄고 전투 중 평균 · 최저 fps (11/3 연출 부하 점검)
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		await get_tree().create_timer(2.0).timeout
		var fr := 0
		var worst := 0.0
		var t0 := Time.get_ticks_usec()
		var last := t0
		while Time.get_ticks_usec() - t0 < int(float(a.gfps) * 1e6):
			await get_tree().process_frame
			var now := Time.get_ticks_usec()
			var ftm := (now - last) / 1000.0
			var pf_now: Dictionary = _battle.field.prof.duplicate() if _battle and _battle.field else {}
			if ftm > 16.0:      # 점검 —— 느린 프레임이 언제인지 (전투 시계) · 그 프레임에 무거웠던 구간
				var dl := []
				for kk in pf_now:
					if kk != "_frames":
						dl.append([kk, (pf_now[kk] - _pf_prev.get(kk, 0)) / 1000.0])
				dl.sort_custom(func(x, y): return x[1] > y[1])
				print("  느린 프레임 %.1fms · 전투 %.2f초 · %s · 컷인 %s" % [ftm, _battle.clock if _battle else -1.0, " ".join(dl.slice(0, 3).map(func(x): return "%s %.1f" % [x[0], x[1]])), str(_battle.hud.cut != null)])
			_pf_prev = pf_now
			worst = maxf(worst, ftm)
			last = now
			fr += 1
		var men := 0
		if _battle and _battle.field:
			for sq in _battle.field.order:
				men += sq.soldiers.size()
		if _battle and _battle.field:
			var pf: Dictionary = _battle.field.prof
			var nfr: int = maxi(1, pf.get("_frames", 1))
			var parts := []
			for k in pf:
				if k != "_frames":
					parts.append([k, pf[k] / 1000.0 / nfr])
			parts.sort_custom(func(x, y): return x[1] > y[1])
			print("  프레임당 ms: " + " · ".join(parts.slice(0, 9).map(func(x): return "%s %.2f" % [x[0], x[1]])))
		print("병사 %d명 · fps 평균 %.0f · 가장 느린 프레임 %.1fms (%d프레임)" % [men, fr / ((Time.get_ticks_usec() - t0) / 1e6), worst, fr])
		get_tree().quit()
		return
	if a.has("gforgefx"):      # --gforgefx=c11,c12,c94 —— 조합 연출 (여럿이면 모두 조합 셔플)
		var ks: Array = Array(str(a.gforgefx).split(","))
		if ks.size() == 1:
			ForgeFx.play_one(self, ks[0], DB.RECOF.get(ks[0], []))
		else:
			ForgeFx.play_chain(self, ks)
	if a.has("gfanfare"):      # --gfanfare=c177 —— 불멸 · 신화 완성 연출만 띄워 본다
		_forge_fanfare(str(a.gfanfare))
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


var _pf_prev := {}


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
