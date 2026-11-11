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
const WarnEdge := preload("res://scripts/ui/warn_edge.gd")      # 11/10 민심 위험 비네트에 다시 쓴다 (5초 경고와 같은 가장자리 그림, class_name 없이)
const InyeonUI := preload("res://scripts/ui/inyeon_ui.gd")      # 11/11 인연 표시 공용 (디테일창 · 갈무리창 줄, 편성 시트)
const UrgentBand := preload("res://scripts/ui/urgent_band.gd")      # 11/10 기인 이상 등용 '긴급' 띠 (class_name 없이)
const EmotePop := preload("res://scripts/ui/emote_pop.gd")      # 11/10 받은 한마디 이모티콘 팝업 (class_name 없이)
const CHANGELOG := preload("res://scripts/game/changelog.gd")   # 11/7 버전 · 업데이트 내역 (class_name 캐시와 무관하게 바로 쓰려고 preload)
## 11/9 첫 판 안내 —— 첫 유저가 조합 방법을 못 찾고 1성 9장으로 전멸했다. 4장, 건너뛰기 가능
const COACH_STEPS := [
	["draw", "1/4  징집", "매일 장수 카드를 받는다. 여기서 뽑는다."],
	["forge", "2/4  조합  —  꼭 알아 둘 것", "같은 장수 · 같은 카드를 모아 조합 탭에서 한 등급 위로 올린다. 1성 9장 그대로는 토벌에서 전멸한다."],
	["deploy", "3/4  편성", "가진 장수를 9칸에 배치한다. 앞줄과 뒷줄 자리를 살피자."],
	["war", "4/4  전투", "출진하면 자동으로 싸운다(조작 없음). 지면 민심이 깎이고, 0 이 되면 멸망한다. 출진 전에 조합부터."],
]
const TABS := [["draw", "징집"], ["forge", "조합"], ["deploy", "편성"], ["war", "전투"], ["more", "기록"]]
const STAT_ICON := 22.0       # 능력치 아이콘(칼 · 방패 · 신발) 크기 —— 14 아래로는 선이 뭉개진다 (11/9)
const MAX_W := 640.0         # PC 에서 창을 넓혀도 글줄은 이 폭까지만
const TOP_H := 58.0          # 11/7 사용자: DAY 네비게이터 축소 (66 → 58)
const TAB_H := 62.0

var run: Run
var page := "draw"
var forge_tag := ""
var forge_tier := 0           # 조합 등급 거르기 (0 = 모두)
var _open := {}               # 접는 묶음 -> 펼침 여부
var _scroll_keep := {}        # 페이지 -> 스크롤 위치

var _safe: MarginContainer
var _top: Control
var _day_lbl: Label
var _sub_lbl: Label
var _pow_lbl: Label
var _info_lbl: RichTextLabel
var _phase_bar: Control
var _news_btn: Button         # 11/7 ☰ 아래 '소식' (소식 수 뱃지)
var _news_badge: Label
var _clock_lbl: Label         # 온라인 단계 시계 (진행 막대 오른쪽)
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
var _coach: Coach = null          # 11/9 첫 판 안내 말풍선 (scripts/ui/coach.gd)
var _coach_i := -1                # -1 꺼짐 · 0~ 4단계 안내 중 · -2 '조합할 수 있다' 한 줄
var _coach_shown := -9
var online: Online = null     # 온라인 대전 중이면 있다 (scripts/ui/online.gd)


func _ready() -> void:
	Settings.load_cfg()
	if not SHOW_DOTS:
		Settings.dots = false      # 고르는 칸을 숨겼으니 예전에 점묘로 저장했어도 3D 로
	Sfx.music("title")
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
	_warm_start()
	_dev_args()


## 11/10 초상 미리 읽기 —— 처음 조합 탭을 열 때 140여 장의 초상을 한꺼번에 읽어 PC 에서 1초 가까이 멈췄다 (작업현황 60).
## 게임을 켜자마자(타이틀에 있는 동안) 조합 탭에 나오는 장수 · 재료의 그림을 작업 스레드로 조금씩 올려 둔다. 판이 정해지면(render 첫 호출)
## 지금 내가 가진 카드 → 추천 → 조합 순서(조합 탭이 보이는 순서) 로 앞에 끼워 넣는다. DB.warm_portraits 참고
var _warm_run: Run = null
var _play_sec := 0.0          # 11/11 사용자: 현재 판 플레이 시간 (기록 탭 맨 위) —— 판이 바뀌면 0, 끝나면 멈춘다
var _play_run: Run = null
var _play_lbl: Label = null


func _warm_start() -> void:
	if OS.get_cmdline_user_args().has("--nowarm"):
		DB.warm_enabled = false
	var outs: Array = DB.D.RECDEF.map(func(r): return r[0])
	DB.warm_portraits(outs)
	var mats: Array = []
	for o in outs:
		mats.append_array(DB.RECOF.get(o, []))
	DB.warm_portraits(mats)


func _warm_for_run() -> void:
	var first: Array = run.pool().keys()
	first.append_array(_forge_goals(DB.D.RECDEF))
	var rest: Array = DB.D.RECDEF.map(func(r): return r[0])
	rest.sort_custom(func(x, y):
		var a := run.miss_count(x)
		var b := run.miss_count(y)
		if a != b:
			return a < b
		return DB.C[x].tier > DB.C[y].tier)
	DB.warm_portraits(first + rest, true)


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
	sb.content_margin_top = 4
	sb.content_margin_bottom = 4
	bar.add_theme_stylebox_override("panel", sb)
	bar.custom_minimum_size = Vector2(0, TOP_H)
	_top = bar
	var row := UI.hbox(8)
	bar.add_child(row)
	# 11/7 사용자: DAY 네비게이터 축소 —— 날짜 · 페이즈를 작은 글씨 한 줄에, 21칸 진행 막대는 그 아래 왼쪽 칸 폭만큼 가늘게(4)
	var lv := UI.vbox(3)
	lv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lv.alignment = BoxContainer.ALIGNMENT_CENTER
	var dl := UI.hbox(6)
	_day_lbl = UI.lbl("", 14, DB.PAL.paper, true)
	_sub_lbl = UI.lbl("", 12, DB.PAL.bamboo)
	_sub_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_sub_lbl.clip_text = true
	_sub_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_sub_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_sub_lbl.size_flags_vertical = Control.SIZE_FILL
	dl.add_child(_day_lbl)
	dl.add_child(_sub_lbl)
	lv.add_child(dl)
	var bl := UI.hbox(6)
	_phase_bar = PhaseBar.new()
	_phase_bar.custom_minimum_size = Vector2(60, 4)
	_phase_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_phase_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bl.add_child(_phase_bar)
	_clock_lbl = UI.lbl("", 11, DB.PAL.bamboo)      # 온라인 단계 시계 —— 막대 오른쪽 (혼자 하기에선 숨김)
	_clock_lbl.visible = false
	bl.add_child(_clock_lbl)
	lv.add_child(bl)
	row.add_child(lv)
	var rv := UI.vbox(0)
	rv.alignment = BoxContainer.ALIGNMENT_CENTER
	_pow_lbl = UI.lbl("", 15, DB.PAL.paper, true)
	_pow_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	rv.add_child(_pow_lbl)
	_hp_gauge = HpGauge.new()      # 11/10 사용자: 민심(체력)이 어디에도 안 보인다 —— 모든 탭의 머리띠 오른쪽에 늘 보인다
	_hp_gauge.tapped.connect(func(): toast("민심은 체력 —— 패배마다 깎이고, 0 이 되면 멸망한다"))
	rv.add_child(_hp_gauge)
	_info_lbl = UI.rich("", 11)
	_info_lbl.autowrap_mode = TextServer.AUTOWRAP_OFF
	_info_lbl.custom_minimum_size = Vector2(140, 0)
	rv.add_child(_info_lbl)
	row.add_child(rv)
	# ☰ 과 그 아래 '소식' (11/7 사용자: 징집 페이지 칩 줄에서 머리띠로) —— 소식 수 뱃지, 누르면 전황 소식 시트
	var mv := UI.vbox(2)
	var mb := UI.btn("☰", _menu, "ghost", 26)
	mb.custom_minimum_size = Vector2(46, 26)
	mb.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	mb.add_theme_font_size_override("font_size", 20)
	mv.add_child(mb)
	_news_btn = UI.btn("소식", _news_sheet, "ghost", 22)
	_news_btn.custom_minimum_size = Vector2(46, 22)
	_news_btn.add_theme_font_size_override("font_size", 11)
	for st in ["normal", "hover", "pressed", "disabled"]:
		_news_btn.add_theme_stylebox_override(st, UI.flat(Color(0, 0, 0, 0), Color(DB.PAL.ink4, 0.5 if st == "disabled" else 1.0), 1, 6, 2))
	_news_btn.add_theme_color_override("font_color", DB.PAL.bamboo)
	_news_btn.add_theme_color_override("font_pressed_color", DB.PAL.paper)
	_news_badge = UI.lbl("", 9, Color("#1A1508"), true)
	_news_badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_news_badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_news_badge.add_theme_stylebox_override("normal", UI.flat(DB.PAL.seal, DB.PAL.seal, 0, 7, 0))
	_news_badge.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_news_badge.offset_left = -19
	_news_badge.offset_right = -1
	_news_badge.offset_top = -5
	_news_badge.offset_bottom = 9
	_news_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_news_btn.add_child(_news_badge)
	mv.add_child(_news_btn)
	row.add_child(mv)
	# 11/11 사용자: 현재 플레이타임을 머리띠(☰ 이 뜨는 줄)의 가운데에 —— "플레이타임 0:04"
	_play_lbl = UI.lbl(play_text(), 12, DB.PAL.bamboo)
	_play_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_play_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_play_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(_play_lbl)
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
				go("rank" if page in ["line", "rank", "update"] else _open.get("more_page", "rank"))
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
	_tabs.deploy.badge = 0 if r.placed() < 9 and not r.inv.is_empty() and can_form() else -1
	var war_todo := false
	if online == null and r.over == null and r.placed() > 0:
		if r.is_tour_phase():
			war_todo = r.tour == null or r.tour.get("next") == null or r.last_result == null
		else:
			war_todo = not r.quest_done or not r.pvp_done or r.can_next()
	_tabs.war.badge = 0 if war_todo else -1
	for k in _tabs:
		_tabs[k].on = k == page or (k == "more" and page in ["line", "rank", "update"])
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
	_battle.leave_cb = _leave_from_battle      # 11/12 사용자: 전투 메뉴에서 게임 나가기
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
	_battle_done.add_theme_font_override("font", DB.title_font(20))
	_battle_done.add_theme_font_size_override("font_size", 20)
	_battle_done.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_battle_done.offset_left = -130
	_battle_done.offset_right = 130
	_battle_done.offset_top = 110
	_battle_done.offset_bottom = 168
	_battle_done.visible = false
	_battle_layer.add_child(_battle_done)


func _build_title() -> void:
	Sfx.music("title")
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
	# 11/7 버전 · 업데이트 내역 (data/changelog.json)
	var vb := UI.btn("v%s · 업데이트 내역" % CHANGELOG.version(), _update_sheet, "ghost", 36)
	vb.add_theme_font_size_override("font_size", 13)
	vb.add_theme_color_override("font_color", Color("#8d7b5c"))
	bv.add_child(vb)
	v.add_child(bv)


## 타이틀 버튼 —— 주 버튼은 금빛 바탕, 나머지는 먹빛 반투명 + 금테
func _title_btn(text: String, cb: Callable, main: bool) -> Button:
	var b := UI.btn(text, cb, "", 56)
	var bg := Color("#c9952f", 0.92) if main else Color("#0b0f1a", 0.62)
	var bd := Color("#ffd98a") if main else Color("#d9a64b", 0.7)
	b.add_theme_stylebox_override("normal", UI.flat(bg, bd, 1, 10, 10))
	b.add_theme_stylebox_override("hover", UI.flat(bg.lightened(0.08), bd, 1, 10, 10))
	b.add_theme_stylebox_override("pressed", UI.flat(bg.darkened(0.15), bd, 2, 10, 10))
	b.add_theme_font_override("font", DB.title_font(19))
	b.add_theme_font_size_override("font_size", 19)
	b.add_theme_color_override("font_color", Color("#1a1206") if main else Color("#f0e6cf"))
	b.add_theme_color_override("font_hover_color", Color("#1a1206") if main else Color("#ffffff"))
	return b


func _go_online() -> void:
	if online == null:
		online = Online.new()
		online.gs = self
		add_child(online)
	online.connect_sheet(true)      # 접속해 있으면 방 목록을 다시 받는다 (11/9)


func _continue() -> void:
	var r := Run.load_saved()
	if r == null:
		_new_game()
		return
	run = r
	_title.visible = false
	Sfx.music("prep")
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
	Sfx.music("prep")
	close_sheet()
	go("draw")


# ───────── 그리기 ─────────

func go(pg: String) -> void:
	if pg == "more":
		pg = "rank"         # '기록' 탭은 순위 · 계보 화면 (페이지 이름이 아니다)
	if online == null and pg != page:
		PlayLog.page(run, pg)
	if page == "forge" and pg != "forge":
		_open.erase("forge:more")      # 조합 탭을 떠나면 '더 보기' 는 접는다 (다시 올 때 타일을 적게 만든다)
	if page != "deploy":
		_scroll_keep[page] = _scroll.scroll_vertical
	if pg in ["line", "rank", "update"]:
		_open["more_page"] = pg
	if pg == "forge" and not Settings.coach_forge:      # 조합 탭을 직접 열었으면 더는 알릴 필요 없다
		Settings.coach_forge = true
		Settings.save_cfg()
		if _coach_i == -2:
			_coach_clear()
	page = pg
	render(true)


func render(new_page := false) -> void:
	if run == null:
		return
	if run != _warm_run:
		_warm_run = run
		_warm_for_run()
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
		"update": pg = _page_more(_page_update())
	pg.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if fixed:
		_fixed.add_child(pg)
	else:
		_body.add_child(pg)
		var want: int = _scroll_keep.get(page, 0) if new_page else keep
		_restore_scroll.call_deferred(want)
	_flush_toasts()
	_coach_tick()


func _restore_scroll(v: int) -> void:
	await get_tree().process_frame
	_scroll.scroll_vertical = v


## 기록 탭 —— 위에 [순위 | 계보 | 업데이트] 나눔 탭
func _page_more(body: Control) -> Control:
	var v := UI.vbox(16)
	v.add_child(UI.segmented([["rank", "순위"], ["line", "계보"], ["update", "업데이트"]], page, func(k): go(k)))
	v.add_child(body)
	return v


## 업데이트 내역 (11/7) —— data/changelog.json 의 버전별 변경. 제목 화면에선 시트로, 게임 안에선 기록 탭 안 페이지로 같은 내용
func _changelog_body() -> Control:
	var v := UI.vbox(14)
	var vs := CHANGELOG.versions()
	if vs.is_empty():
		v.add_child(UI.hint("업데이트 내역이 없습니다."))
		return v
	for i in vs.size():
		var ver: Dictionary = vs[i]
		var b := UI.vbox(6)
		var head := UI.hbox(8)
		head.add_child(UI.lbl("v%s" % str(ver.get("ver", "?")), 20, DB.PAL.gold, true))
		var d := UI.lbl(str(ver.get("date", "")), 13, DB.PAL.bamboo_dim)
		d.size_flags_vertical = Control.SIZE_SHRINK_END
		head.add_child(d)
		if i == 0:
			var now := UI.lbl("지금 버전", 12, DB.PAL.jade)
			now.size_flags_vertical = Control.SIZE_SHRINK_END
			head.add_child(now)
		b.add_child(head)
		var t := UI.lbl(str(ver.get("title", "")), 15, DB.PAL.paper)
		t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.add_child(t)
		b.add_child(UI.rich(CHANGELOG.bb(ver), 14))
		v.add_child(UI.panel(b))
	return v


func _page_update() -> Control:
	var v := UI.vbox(10)
	v.add_child(_page_head("업데이트 내역", "지금 버전 v%s · 빌드마다 바뀐 것" % CHANGELOG.version()))
	v.add_child(_changelog_body())
	return v


func _update_sheet() -> void:
	var b := open_sheet("업데이트 내역 · v%s" % CHANGELOG.version())
	b.add_child(_changelog_body())


func _render_head() -> void:
	_clock_lbl.visible = false
	if online != null and online.in_game and not online.room.is_empty():
		# 11/9 사용자: 온라인은 머리띠도 방의 시계로 —— "2일차 · 저녁 준비 · 1:20" (혼자 하기의 '월요일 오후'와 어긋나 보였다). 진행 막대는 하루 네 단계.
		# 병사 수(12,900명)는 뺀다 (결정 ⑥ 처럼 전력은 보이지 않는다)
		var st := str(online.room.get("stage", ""))
		_day_lbl.text = online.day_text()      # 11/10 게임 날짜 · 페이즈로 (day_no 는 페이즈 번호 1~21)
		_sub_lbl.text = (("종료" if run.over.win else "멸망") if run.over else online.head_stage_text())
		_phase_bar.n = online.head_steps()      # 11/11 토벌이 없는 날(4일차~)은 세 칸
		_phase_bar.group = online.head_steps()
		_phase_bar.cur = online.head_idx()
		_pow_lbl.visible = false
	else:
		_day_lbl.text = "DAY %d · %s요일" % [run.day + 1, Run.DAYNAME[run.day]]
		_sub_lbl.text = (("종료" if run.over.win else "멸망") if run.over else Run.PHASE_N[run.phase])
		_phase_bar.n = 21
		_phase_bar.group = 3
		_phase_bar.cur = run.phase_idx()
		_pow_lbl.visible = true
		_pow_lbl.text = "%s명" % Battle.num(run.board_power())
	_phase_bar.queue_redraw()
	_hp_sync()
	# 11/9 사용자: 상단의 PV · 순위 · 경고 줄은 뺀다 (경고 · 순위는 기록 탭에서 본다)
	_info_lbl.clear()
	_info_lbl.visible = false
	# 소식 버튼 (11/7) —— 소식 수 뱃지, 없으면 흐리게
	# 11/10 사용자: 소식 레드닷이 사라지지 않았다 → 안 읽은 소식 수 (소식 시트를 열면 읽음, 새 소식이 오면 다시 켜진다)
	_news_btn.disabled = run.news.is_empty()
	var unread := _news_unread()
	_news_badge.visible = unread > 0
	_news_badge.text = str(unread)
	_item_band()


## 안 읽은 소식 —— 항목의 id(서버 · 솔로 Run 이 매기는 늘어나는 번호)가 읽은 기준(_news_seen_id)보다 큰 것.
## 판이 바뀌면(새 판 · 이어 하기 → Run 객체가 바뀜 · 온라인 입장/방이 바뀜) 기준을 지금 가장 큰 번호로 다시 잡는다
## (온라인은 서버 상태마다 Run 이 새 객체라 객체가 아니라 방 코드로 비교한다). id 가 없는 옛 항목은 읽은 것으로 본다
var _news_run: Run = null
var _news_room := ""
var _news_seen_id := 0
func _news_max_id() -> int:
	var m := 0
	for nw in run.news:
		m = maxi(m, int(nw.get("id", 0)))
	return m


func _news_unread() -> int:
	var on := online != null and online.in_game and not online.room.is_empty()
	var rc := str(online.room.get("code", "")) if on else ""
	if on:
		if rc != _news_room:
			_news_room = rc
			_news_run = null
			_news_seen_id = _news_max_id()
	elif _news_room != "" or run != _news_run:
		_news_room = ""
		_news_run = run
		_news_seen_id = _news_max_id()
	var n := 0
	for nw in run.news:
		if int(nw.get("id", 0)) > _news_seen_id:
			n += 1
	return n


## 아이템을 얻은 순간 가운데 띠 한 번 (11/7 사용자: 징집 페이지에 늘 자리를 차지하던 '아이템 이름 · 효과' 칩 대신).
## 다시 그릴 때마다 가방을 재 보고, 마지막 아이템이 바뀌었거나 가방이 늘었으면 띠. 새 판 · 이어 하기 · 온라인 입장은 기준만 다시 잡는다
## (온라인은 서버 상태마다 Run 이 새 객체라 객체가 아니라 내용으로 비교한다)
var _item_run: Run = null
var _item_online := false
var _item_seen = null
var _bag_seen := 0
func _item_band() -> void:
	var n := 0
	for id in run.bag:
		n += int(run.bag[id])
	var fresh: bool = run != _item_run and (online == null or not _item_online)
	_item_run = run
	_item_online = online != null
	if not fresh and run.last_item != null and (run.last_item != _item_seen or n > _bag_seen):
		var it: Dictionary = DB.IT[run.last_item]
		band("%s 획득" % it.name, UI.item_col(run.last_item), "%s · %s" % [it.tag, UI.item_text(run.last_item)])
	_item_seen = run.last_item
	_bag_seen = n


## 머리띠 민심 게이지 (11/10) —— 보이는 값 _hp_shown 을 기억해 두었다가 run.hp 가 그보다 낮아지면 한 번 붉게 번쩍이며 줄어든다.
## 전투를 보는 동안(결과 화면이 따로 「민심 −N」 을 보인다) · 온라인에서 서버가 먼저 깎아 보낸 판을 다 보기 전에는 값을 붙잡아 둔다 (미리 알려 주지 않게)
var _hp_gauge: HpGauge
var _hp_shown := -1
var _hp_run: Run = null
var _hp_online := false
var _hp_plan := {}            # 이번 전투 결과 화면에서 보일 「민심 −N」 {prev, loss}
var _hp_fx: Control = null    # 결과 화면의 민심 줄
var _battle_last := true      # 온라인: 지금 보는 전투가 이번 단계의 마지막인지
var _battle_kind := ""
var _dev_hploss := 0          # 점검용 --ghploss
var _bonus_plan := {}         # 이번 전투 결과 화면에서 보일 토벌 성과 보너스 줄 {base, ticket, big} (11/10)
var _bonus_key := ""          # 온라인에서 같은 보너스 알림을 다시 보기마다 반복하지 않게
var _dev_bonus_r := -1.0      # 점검용 --gbonus : 이 잔존 비로 이긴 것으로
func _hp_sync() -> void:
	if _hp_gauge == null or run == null:
		return
	var fresh: bool = _hp_shown < 0 or (run != _hp_run and (online == null or not _hp_online)) or _hp_online != (online != null)
	_hp_run = run
	_hp_online = online != null
	var hp := clampi(run.hp, 0, Run.HP_MAX)
	if fresh or hp > _hp_shown:
		_hp_shown = hp
		_hp_gauge.set_now(hp)
		return
	if hp == _hp_shown or _hp_hold():
		return
	_hp_shown = hp
	_hp_gauge.drop_to(hp)


## 민심 위험 알림 (11/10 사용자: 민심이 얼마 남지 않았을 때 지속적으로 위험하다는 것을 알려줌) ——
## 게이지가 보이는 값(_hp_gauge.value)이 HpGauge.LOW(30) 이하인 동안 어느 탭에서나 화면 가장자리에 아주 옅은 붉은 비네트가 느리게 맥동한다(주기 2초 · 투명도 0.06~0.18),
## 15 이하는 더 짙고 빠르게(1.2초 · 0.10~0.26). 게이지 옆 「위험」 글자는 HpGauge 가 그린다. 입력은 막지 않고 소리는 없다.
## 전투 화면(BattleView) · 타이틀 · 판이 끝난 뒤에는 끈다. 온라인 5초 경고(붉은 가장자리 + 비프)가 켜져 있으면 5초 경고가 우선 —— 위험 비네트는 그동안 끈다
const DANGER_HP := 15.0
var _danger_fx: Control = null
var _danger_t := 0.0


func _process(dt: float) -> void:
	_play_tick(dt)
	_danger_tick(dt)


## 플레이타임 —— 이 판이 시작된 뒤 켜 둔 시간(판이 끝나면 멈춤, 제목 화면에서는 세지 않는다). 머리띠 가운데에 보인다
func _play_tick(dt: float) -> void:
	if run != _play_run:
		_play_run = run
		_play_sec = 0.0
	if run != null and run.over == null and (_title == null or not _title.visible):
		_play_sec += dt
	if _play_lbl != null and is_instance_valid(_play_lbl) and _play_lbl.is_visible_in_tree():
		_play_lbl.text = play_text()


func play_text() -> String:
	var t := int(_play_sec)
	return ("플레이타임 %d:%02d:%02d" % [t / 3600, t / 60 % 60, t % 60]) if t >= 3600 else ("플레이타임 %d:%02d" % [t / 60, t % 60])



func _danger_tick(dt: float) -> void:
	var on := false
	var hp := 100.0
	if _hp_gauge != null and run != null and run.over == null and (_title == null or not _title.visible) and not (_battle_layer != null and _battle_layer.visible):
		hp = _hp_gauge.value
		on = hp <= HpGauge.LOW
	if on and online != null and is_instance_valid(online._warn_fx) and online._warn_fx.visible:
		on = false      # 5초 경고가 우선
	if not on:
		if _danger_fx != null and is_instance_valid(_danger_fx) and _danger_fx.visible:
			_danger_fx.hide_now()
		return
	if _danger_fx == null or not is_instance_valid(_danger_fx):
		_danger_fx = WarnEdge.new()
		add_child(_danger_fx)
	var crit := hp <= DANGER_HP
	_danger_t += dt
	var s := 0.5 + 0.5 * sin(_danger_t * TAU / (1.2 if crit else 2.0))
	_danger_fx.show_soft(lerpf(0.10, 0.26, s) if crit else lerpf(0.06, 0.18, s))


func _hp_hold() -> bool:
	if _battle_layer != null and _battle_layer.visible:
		return true
	return online != null and online.in_game and str(online.room.get("stage", "")) in Room.WATCH_STAGES and not online._seen_all


func toast(text: String, kind := "") -> void:
	Sfx.play({"gain": "gain", "bad": "deny", "gold": "gain"}.get(kind, "draw"))
	var p := PanelContainer.new()
	var col: Color = {"gold": DB.PAL.gold, "news": DB.PAL.bamboo, "gain": DB.PAL.jade, "bad": DB.PAL.seal}.get(kind, DB.PAL.bamboo_dim)
	var sb := UI.flat(Color("#1b2236", 0.97), Color(col, 0.35), 1, UI.R, 12)      # 11/9: 왼쪽 굵은 색 띠 · 그림자 걷음 —— 얇은 선 하나
	p.add_theme_stylebox_override("panel", sb)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := UI.lbl(text, 15, DB.PAL.seal.lightened(0.35) if kind == "bad" else DB.PAL.paper)
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
	sb.border_width_top = 1
	sb.border_width_bottom = 1
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
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
	if online != null and not online.can_act(Online.cmd_kind(m)):      # 11/12 지금 단계에서 안 되는 행동 —— 이유 한 줄 (서버도 거부한다)
		Sfx.play("deny")
		toast(online.block_reason(Online.cmd_kind(m)), "bad")
		render()
		return null
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
	# 전투 위에서도 시트가 보이게 맨 앞으로 —— 11/7 제목 화면도 (시트보다 나중에 붙어 위를 덮어, 제목의 '설정'이 열려도 안 보였다)
	if (_battle_layer != null and _battle_layer.visible) or (is_instance_valid(_title) and _title.visible):
		move_child(_sheet_mask, -1)
		move_child(_sheet, -1)
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


## 시트 위 오른쪽 쓸기 —— 이전 카드 시트가 있으면 그리로, 없으면 시트를 닫는다 (11/11 사용자: 모든 팝업은 왼쪽에서 오른쪽으로 쓸어 닫는다)
func _input(e: InputEvent) -> void:
	if _sheet == null or not _sheet.visible:      # 11/10 화면이 다 만들어지기 전에 입력이 오면 _sheet 가 아직 null
		return
	if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
		if e.pressed:
			_swipe_p = e.position if _sheet.get_global_rect().has_point(e.position) and not UI.swipe_blocked_at(_sheet, e.position) else Vector2.INF
		elif _swipe_p != Vector2.INF:
			var d: Vector2 = e.position - _swipe_p
			_swipe_p = Vector2.INF
			if d.x > 90 and absf(d.y) < d.x * 0.5 and not get_viewport().gui_is_dragging():
				UI.buzz()
				if _hist.is_empty():
					close_sheet()
				else:
					go_back()


func _menu() -> void:
	var b := open_sheet("메뉴")
	if online != null:
		b.add_child(UI.btn("접속 · 방 목록 (다른 방으로)", func(): online.connect_sheet(true), "ghost"))      # 11/9 사용자: 연결된 채로 방을 바꿀 수 있게
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
	if Settings.SHOW_3D:      # 11/9 3D · 수묵 선택은 숨겼다 (Settings.SHOW_3D) —— 늘 타입2
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
		b.add_child(UI.hint("간단: 진형 소개 · 책략 실. 자세히: 사거리 · 진격 화살표까지. 일시정지하면 자세히 보입니다."))
	b.add_child(UI.eyebrow("성능 표시"))      # 11/6 휴대폰 실측용
	b.add_child(UI.segmented([["0", "끔"], ["1", "켬"]], "1" if Settings.perf_hud else "0", func(key):
		Settings.perf_hud = key == "1"
		Settings.save_cfg()
		_settings_sheet()))
	b.add_child(UI.hint("전투 왼쪽 위에 fps · 계산 병사 · 보이는 인형 수 · 부하 조절 단계를 띄웁니다. 타입2 는 품질과 상관없이 병사 수를 그대로 둡니다."))
	# 11/4 사용자: 직접 지휘 개념은 없앤다 —— 전투는 늘 AI 가 고유기를 쓴다
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
	if run != null and online == null:
		b.add_child(UI.btn("첫 판 안내 다시 보기", func():
			Settings.coach_done = false
			Settings.save_cfg()
			_coach_clear()
			_coach_i = 0
			close_sheet()
			go("draw"), "ghost", 44))


# ───────── 첫 판 안내 (11/9) ─────────

func _coach_clear() -> void:
	if _coach != null and is_instance_valid(_coach):
		_coach.queue_free()
	_coach = null
	_coach_shown = -9
	if _coach_i == -2:
		_coach_i = -1


func _coach_tick() -> void:
	if run == null or online != null or _title.visible or run.over != null:
		return
	if _coach_i == -1 and not Settings.coach_done and run.day == 0 and run.my_w + run.my_l == 0 and run.battle == null:
		_coach_i = 0
	elif _coach_i == -1 and not Settings.coach_forge and run.day <= 1 and page != "forge" and can_act() and _tabs.forge.badge > 0:
		_coach_i = -2
	if _coach_i == -1 or _coach_shown == _coach_i:
		return
	_coach_shown = _coach_i
	if _coach != null and is_instance_valid(_coach):
		_coach.queue_free()
	await get_tree().process_frame      # 탭 자리가 잡힌 뒤
	if _coach_i != _coach_shown or _title.visible:
		return
	var key := "forge" if _coach_i == -2 else str(COACH_STEPS[_coach_i][0])
	var tb: Control = _tabs[key]
	var aim := Vector2(tb.global_position.x + tb.size.x / 2.0, _tabbar.global_position.y)
	var w := minf(size.x - 24.0, 340.0)
	var c: Coach
	if _coach_i == -2:
		c = Coach.make("조합할 수 있다", "같은 카드를 모아 한 등급 위 장수로 올릴 수 있다. 조합 탭을 눌러 보자.", aim, true, false, w)
		c.next.connect(func():
			Settings.coach_forge = true
			Settings.save_cfg()
			_coach_clear()
			go("forge"))
	else:
		var st: Array = COACH_STEPS[_coach_i]
		var last := _coach_i == COACH_STEPS.size() - 1
		c = Coach.make(str(st[1]), str(st[2]), aim, last, not last, w)
		c.next.connect(func():
			if last:
				_coach_finish()
				return
			_coach_i += 1
			_coach_clear_node()
			go(str(COACH_STEPS[_coach_i][0])))
		c.skip.connect(_coach_finish)
	_coach = c
	add_child(c)
	move_child(c, _sheet_mask.get_index())      # 설정 · 카드 시트 · 전투 화면은 위로 덮는다


func _coach_clear_node() -> void:
	if _coach != null and is_instance_valid(_coach):
		_coach.queue_free()
	_coach = null


func _coach_finish() -> void:
	Settings.coach_done = true
	Settings.coach_forge = true      # 조합은 방금 알렸다
	Settings.save_cfg()
	_coach_i = -1
	_coach_clear()


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
	return UI.grid(66, 6)       # 10/30 66 → 78 (한 줄 4장) · 11/7 사용자: 카드 축소 —— 다시 한 줄 5장 (칸 66×96)


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
func recipe_sheet(out: String) -> void:
	if not DB.RECOF.has(out):      # 조합법이 없는 카드(기본패 · 황건 전설 등)는 디테일창으로
		card_info(out)
		return
	_route_enter("recipe", out)
	var c: Dictionary = DB.C[out]
	var b := open_sheet(c.name, DB.tier_color(out).lightened(0.2))
	# 11/3 사용자: 이름은 제목과 겹치니 빼고, 일반 기술도 뺀다.
	# 11/9 사용자: 시트를 더 크게 —— 큰 초상 + 능력치 · 특기판, 그 아래 고유 특기 · 위세 · 패업 · 고유기 · 기질을 디테일창과 같은 색 띠 칸으로 이름만 (설명은 디테일창에서)
	var tp := UI.hbox(12)
	var cv := CardView.new().setup(out, Vector2(112, 160))
	cv.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	cv.mouse_filter = Control.MOUSE_FILTER_STOP          # 11/3 사용자: 초상을 누르면 디테일창
	cv.gui_input.connect(func(e):
		if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT and not e.pressed:
			UI.buzz()
			card_info(out))
	tp.add_child(cv)
	var rv := UI.vbox(6)
	rv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rv.add_child(_stat_row(c))
	rv.add_child(TraitBoard.new().setup(out))
	var chips := _ability_items(out)
	var iy := _inyeon_item(out)      # 11/11 인연 —— 이름 칩만 한 줄 (구성원은 디테일창에서)
	if not iy.is_empty():
		chips.append(iy)
	var ult = DB.ult_of(out) if c.tier >= 6 or DB.is_kiin(out) else null
	var open_detail := func(): card_info(out)      # 줄을 누르면 디테일창
	if ult != null:      # 11/9 사용자: 초상 옆 빈 공간 정리 —— 기질은 오른쪽(능력치 · 특기판 아래), 나머지는 아래 폭 전체 한 장 패널
		var ti := _temper_item(c, ult)
		if not ti.is_empty():
			rv.add_child(UI.hair())
			rv.add_child(_ability_panel([ti], 12, false, true, open_detail, false))
	tp.add_child(rv)
	b.add_child(UI.panel(tp, 10))
	if not chips.is_empty():
		b.add_child(_ability_panel(chips, 12, false, true, open_detail))
		b.add_child(UI.hint("자세한 설명은 상세(디테일창)에서 보세요"))
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
	var v := UI.vbox(8)
	var n := run.draws_n()
	if online != null and not can_act():      # 11/12 페이즈 개편 —— 징집 · 조합이 막힌 단계면 이유 한 줄 (버튼은 잠긴다)
		v.add_child(UI.hint(online.block_reason("draw")))
	if run.day == 6:
		v.add_child(UI.panel(UI.rich("[b][color=#D9A64B]결전의 날[/color][/b] — 더 이상 농민을 징집하지 않는다. 명장만이 소환된다.", 14), 10))

	# 할 일 —— 기호 타일 한 줄 (11/7 사용자: 세로로 너무 컸다 —— 기호 · 제목을 옆으로 나란히 높이 34, 한 줄 최대 5칸)
	var acts := UI.grid(70, 4)
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

	# 11/7 사용자: '아이템 이름 · 효과' 칩은 획득 순간 가운데 띠(_item_band)로, '소식 N' 칩은 머리띠 ☰ 아래 버튼으로 —— 칩 줄은 없다

	# 보유 카드만 (11/2 사용자) —— 등급별로 열 수를 달리한다: 초월 위 4열 · 일반~전설 6열 (남은 높이에서 스크롤), 기본 병졸 8종은 맨 아랫줄 8열 고정
	var p := run.pool()
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
	# 11/7 사용자: "보유 N장 · PV" · "▲ 지금 조합 재료" 머리줄은 뺐다 (타일의 ▲ 표시는 그대로)
	var hs := UI.scroll()
	hs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var inner := UI.vbox(6)
	inner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inner.size_flags_vertical = Control.SIZE_EXPAND_FILL
	inner.alignment = BoxContainer.ALIGNMENT_BEGIN    # 11/6 사용자: 기본병 줄이 맨 위로 갔으니 위에서부터 채운다
	var keys: Array = Run.sort_cards(p.keys())
	# 11/4 사용자: 등급마다 줄을 나눈다. 11/5 · 11/6 사용자: 등급이 높을수록 크게. 11/7 사용자: 장수 카드 전반 축소
	# 11/7 사용자: 등급 줄 —— 맨 위 한 줄 [신화 | 불멸], 그 아래 [초월 | 기인], 그 아래 전설은 별도 공간, 희귀 · 고급 · 일반은 지금처럼.
	#   신화 · 불멸 · 초월 · 기인은 더 이상 재료가 아닌 '완성된 장수' 라 「완성된 장수 접기」로 숨긴다 (_open.draw_fold —— 다시 그려도 유지).
	#   목표: 전설 · 희귀 같은 재료로 어떤 상위패를 노릴 수 있는지 빠르게 보이게 (65a490f 가 조합 페이지에 잘못 넣었던 등급 묶음을 가진 카드로 옮겼다)
	var by := {}      # 등급(1~8) · "기인" -> 가진 카드 (sort_cards 순서 —— 병종 · 이름)
	for k in keys:
		var key = "기인" if DB.is_kiin(k) else int(DB.C[k].tier)
		if not by.has(key):
			by[key] = []
		by[key].append(k)
	_hand_done(inner, by, p, hand_tile)
	# 전설 6열 84 · 희귀 6열 80 · 고급 · 일반 7열 72 —— 지금처럼 등급마다 한 묶음 (기인은 위 [초월 | 기인] 줄로 올라갔다. 폭 56 아래는 작은 칸 그리기)
	for grp in [[[5], 6, 84.0], [[4], 6, 80.0], [[3, 2], 7, 72.0]]:
		var g := UI.grid(30, 6)
		g.max_cols = grp[1]
		for t in grp[0]:
			for k in by.get(t, []):
				g.add_child(hand_tile.call(k, p[k], grp[2]))
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


## 징집 보유 목록의 '완성된 장수' (11/7 사용자) —— [신화 | 불멸] · [초월 | 기인] 두 줄과 「완성된 장수 접기」.
## 65a490f 가 조합 페이지에 만든 등급 묶음(_forge_group)을 조합법 대신 가진 카드로 옮겼다 —— 카드 뜻은 그대로 (×N · 편성 · ▲ 지금 조합 재료 · 누르면 디테일).
## 줄마다 [등급, 이름, 칸 최소 폭, 칸 높이, 금테] 둘. 신화는 금테 · 조금 큰 칸(86×112 —— 불멸 74×100), 초월 · 기인도 74×100 (11/9 불멸과 같게, 칭호 붙은 이름이 한 줄에 드는 폭)
const DONE_ROWS := [[[8, "신화", 86.0, 112.0, true], [7, "불멸", 74.0, 100.0, false]], [[6, "초월", 74.0, 100.0, false], ["기인", "기인", 74.0, 100.0, false]]]      # 11/9 초월 · 기인 칸을 불멸 줄과 같게 (아래 등급처럼 보이지 않게)

func _hand_done(inner: VBoxContainer, by: Dictionary, p: Dictionary, hand_tile: Callable) -> void:
	var counts := []      # [이름, 색, 장수]
	var total := 0
	for row in DONE_ROWS:
		for sp in row:
			var n := 0
			for k in by.get(sp[0], []):
				n += int(p[k])
			counts.append([sp[1], _done_col(sp[0]), n])
			total += n
	if total == 0:
		return
	var fold: bool = _open.get("draw_fold", false)      # 접은 상태를 _open.draw_fold 에 남긴다 (다시 그려도 유지 · 점검 --gopen=draw_fold)
	inner.add_child(_done_toggle(fold, counts))
	if fold:
		return
	var sa := _safe_insets()
	var w := minf(size.x - sa.position.x - sa.size.x - 28.0, MAX_W)      # 보유 목록 폭 (_layout 의 좌우 여백 14)
	for row in DONE_ROWS:
		var r := _done_row(row, by, p, hand_tile, w)
		if r != null:
			inner.add_child(r)


func _done_col(key) -> Color:
	return DB.KIIN_COL if key is String else DB.TIER[key].c


## 「완성된 장수 접기 ▴ · 펼치기 ▾」 —— 옆에 등급별 장수 수를 등급색으로 (접어도 무엇을 숨겼는지 보인다)
func _done_toggle(fold: bool, counts: Array) -> Button:
	var b := UI.btn("", func(): _toggle("draw_fold"), "ghost", 28)
	var hb := UI.hbox(8)
	hb.alignment = BoxContainer.ALIGNMENT_CENTER
	hb.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var items := [["완성된 장수 펼치기 ▾" if fold else "완성된 장수 접기 ▴", DB.PAL.bamboo]]
	for c in counts:
		if c[2] > 0:
			items.append(["%s %d" % [c[0], c[2]], c[1]])
	for it in items:
		var l := UI.lbl(it[0], 12, it[1])
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		l.size_flags_vertical = Control.SIZE_FILL
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hb.add_child(l)
	b.add_child(hb)
	return b


## 등급 줄 한 줄 —— 한 등급이 비면 다른 등급이 폭을 다 쓰고, 둘 다 비면 그리지 않는다.
## 둘 다 있으면 줄 수가 가장 적게 열을 나눈다: 왼쪽은 제 카드가 들어갈 폭만, 오른쪽이 나머지 폭 (신화는 한 판에 한 장 —— 반 폭으로 나누면 반이 빈다)
func _done_row(row: Array, by: Dictionary, p: Dictionary, hand_tile: Callable, w: float) -> Control:
	var a: Array = by.get(row[0][0], [])
	var b: Array = by.get(row[1][0], [])
	if a.is_empty() and b.is_empty():
		return null
	var h := UI.hbox(6)
	if a.is_empty() or b.is_empty():
		var one := _done_group(row[0] if b.is_empty() else row[1], a if b.is_empty() else b, p, hand_tile)
		one.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(one)
		return h
	var need := func(c: int, cw: float) -> float: return c * cw + (c - 1) * 5.0 + 10.0      # 칸 c 개 + 사이 5 + 상자 안 여백 5 × 2
	var ca := 1
	for nr in range(1, maxi(a.size(), b.size()) + 1):      # 줄 수 nr 로 둘 다 들어가는 가장 작은 nr
		ca = ceili(a.size() / float(nr))
		if need.call(ca, row[0][2]) + 6.0 + need.call(ceili(b.size() / float(nr)), row[1][2]) <= w:
			break
	var left := _done_group(row[0], a, p, hand_tile)
	left.custom_minimum_size.x = need.call(ca, row[0][2])
	h.add_child(left)
	var right := _done_group(row[1], b, p, hand_tile)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(right)
	return h


## 등급 줄의 한 칸 —— 머리줄(등급 이름 · 장수 수) + 칸 안에서 줄을 바꾸는 격자 (반 폭에 카드가 많아도 옆으로 넘기지 않고 한눈에). 신화는 금테
func _done_group(sp: Array, ks: Array, p: Dictionary, hand_tile: Callable) -> PanelContainer:
	var col := _done_col(sp[0])
	var pc := PanelContainer.new()
	pc.add_theme_stylebox_override("panel", UI.flat(DB.PAL.ink2, Color(DB.PAL.gold, 0.9) if sp[4] else Color(col, 0.45), 2 if sp[4] else 1, 8, 5))
	var v := UI.vbox(3)
	var n := 0
	for k in ks:
		n += int(p[k])
	v.add_child(UI.rich("[b][color=%s]%s[/color][/b] [color=#8D7B5C]%d[/color]" % [col.to_html(false), sp[1], n], 11))
	var g := UI.grid(sp[2], 5)
	for k in ks:
		g.add_child(hand_tile.call(k, int(p[k]), sp[3]))
	v.add_child(g)
	pc.add_child(v)
	return pc


var _hand_scroll: ScrollContainer
var _hand_scroll_y := 0       # 다시 그려도 보유 패 스크롤 자리를 지킨다


func _restore_hand_scroll(y: int) -> void:
	await get_tree().process_frame
	if is_instance_valid(_hand_scroll):
		_hand_scroll.scroll_vertical = y


func mini_n(a: int, b: int) -> int:
	return a if a < b else b


func _news_sheet() -> void:
	_news_seen_id = maxi(_news_seen_id, _news_max_id())      # 연 순간 읽음 처리 (11/10)
	_render_head()
	var b := open_sheet("전황 소식")
	if run.news.is_empty():
		b.add_child(UI.hint("아직 소식이 없다 —— 다른 세력이 장수를 등용하면 여기에 쌓인다."))
	for nw in run.news:
		if not DB.C.has(str(nw.get("unit", ""))):      # 11/9 온라인 소식 —— 서버가 글로 보낸 소식 (멸망 · 퇴장 등). 장수가 있으면 아래 등용 줄
			var who := str(nw.get("who", ""))
			var tx := str(nw.get("text", ""))
			if tx.begins_with(who):
				who = ""
			b.add_child(UI.rich(("[b]%s[/b] " % who if who != "" else "") + tx + _news_when(nw), 15))
			continue
		b.add_child(UI.rich("[b]%s[/b]가 %s [color=#8D7B5C]%s 등용[/color]%s" % [nw.who, UI.card_bb(nw.unit), DB.tier_name(nw.unit), _news_when(nw)], 15))


## 소식 옆의 시점 —— 「(3일차 아침)」 옅은 글씨. 옛 항목(when 없음)은 없다 (11/10)
func _news_when(nw: Dictionary) -> String:
	var w := str(nw.get("when", ""))
	return " [color=#8D7B5C](%s)[/color]" % w if w != "" else ""


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
	# 11/7 사용자: 팝업을 화면 높이 88% 까지 키우고(_fit_sheet 의 상한) 장수의 병종 · 고유기 · 기질도 함께
	# 11/9 사용자: '받기' 까지 스크롤 없이 한눈에 —— 시트를 선택권처럼 98% 로, 그림 150 → 120, 패업 줄은 뺀다 (그림을 누르면 간략창에서 본다)
	_sheet_full = true
	var row := UI.hbox(5)
	var sa := _safe_insets()
	var head_h: float = _sheet.get_child(0).get_child(0).get_combined_minimum_size().y
	row.custom_minimum_size.y = maxf(300.0, (size.y - sa.position.y) * 0.98 - head_h - sa.size.y - 34.0)      # 시트 머리 · 본문 여백(6 + 24)을 뺀 나머지
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
			var art := _art_crop(kk, Vector2(120, 120), false)      # 11/3 사용자: 보급 창은 기본 장수 그림 (신화 그림은 갈무리 창에만)
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
			# 11/7 사용자: 이 재료로 만드는 장수의 병종 —— 기호 + 이름
			var tr := UI.hbox(4)
			tr.alignment = BoxContainer.ALIGNMENT_CENTER
			var ti := TextureRect.new()
			ti.texture = DB.ICON.get(DB.C[kk].tag)
			ti.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			ti.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			ti.custom_minimum_size = Vector2(14, 14)
			ti.modulate = DB.PAL.bamboo
			tr.add_child(ti)
			tr.add_child(UI.lbl("%s · %s" % [DB.C[kk].tag, DB.tier_name(kk)], 11, DB.PAL.bamboo))
			col.add_child(tr)
			var tb := TraitBoard.new()
			tb.fixed = true
			col.add_child(tb.setup(kk, 3))
			_ability_rows(col, kk, 10, true, true, ["패업"])      # 고유 특기 · 위세 · 고유기 + 기질 —— 디테일창과 같은 칸 (좁은 세로 칸). 패업은 뺀다 (11/9)
		var sp := Control.new()
		sp.size_flags_vertical = Control.SIZE_EXPAND_FILL
		col.add_child(sp)
		col.add_child(UI.btn("받기", func():
			if act("pick_unique", [iid]):      # 11/7 사용자: 아래 알림("○○ 획득 · 아이템 보급")은 뺐다 —— 가운데 띠(_item_band)만. 얻는 소리는 남긴다
				Sfx.play("gain")
			close_sheet(), "pri", 38))
		var pc := UI.panel(col, 5)
		pc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		pc.size_flags_stretch_ratio = 1.0
		pc.custom_minimum_size.x = 0
		pc.clip_contents = true
		row.add_child(pc)
	b.add_child(row)
	# 11/11 사용자: 유니크 보급은 한 번 다시 뽑을 수 있다 (셋 모두 바뀜 · 앞에 나온 것은 안 나옴)
	if not run.uniq_rerolled:
		b.add_child(UI.btn("다시 뽑기 (한 번) —— 셋 모두 바뀐다", func():
			if act("reroll_unique", []):
				Sfx.play("open")
				_unique_sheet()
			else:
				toast("바꿀 아이템이 없다"), "ghost", 40))


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
	# 갈무리 장수의 재료(아래 재료까지) —— 갈무리 트리와 같은 계산으로 '아직 모자람(true) / 다 모음(false)'
	# 11/7 사용자 점검: 재료를 뽑아 필요한 수를 채운 뒤에도 '재료' 배지가 그대로였다 → 다 모은 재료는 '확보'
	var mats := {}
	var walk := func(nd: Dictionary, f: Callable) -> void:
		for c in nd.get("kids", []):
			if c.has("k"):
				var short: bool = not c.ok
				mats[c.k] = bool(mats.get(c.k, false)) or short
			f.call(c, f)
	for pk in pins:
		walk.call(forge_tree._node(pk, 1, 0, pk, "", true), walk)
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
		# 11/7 사용자: 갈무리 표현 통일 —— 갈무리한 장수 · 아직 모자란 재료는 12시 ★ + 테두리를 도는 금빛, 다 모은 재료는 ★ 만 (뱃지 글은 뺀다)
		if pins.has(k):
			tl.set_pin(true, true)
		elif mats.has(k):
			tl.set_pin(true, bool(mats[k]))
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
		# 고급 · 희귀 —— 병종 한 줄씩(왼쪽 병종 기호), 8병종이 한 화면에. 11/7 사용자: 고급도 희귀와 같은 칸 크기 (여섯 칸 · 높이는 희귀 줄 수 기준)
		var cols := 6
		var icon_w := 26.0
		var tw := floorf((full - icon_w - gap * cols) / cols)
		var nrow := 0
		for tag in DB.D.TAGORDER:
			var n4 := Run.pickable(4, tag).size()
			nrow += maxi(1, ceili(n4 / float(cols))) if n4 > 0 else 0
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
		b.add_child(UI.hint("위 병종 단추를 누르면 그 묶음으로 갑니다. 길게 누르면 디테일창. 갈무리한 장수와 그 재료(아래 재료까지)는 ★ · 테두리를 도는 금빛, 다 모은 재료는 ★ 만."))
	if was_open:
		_restore_sheet_scroll.call_deferred(_pick_scroll)


func _restore_sheet_scroll(y: int) -> void:
	await get_tree().process_frame
	if _sheet.visible:
		_sheet_scroll.scroll_vertical = y


## 지금 징집 · 조합할 수 있는가 —— 온라인은 서버의 방 정보 act_draw (11/12 페이즈 개편: 아침 · 전투를 다 본 뒤 기다리는 동안)
func can_act() -> bool:
	return online == null or online.can_act("draw")


## 지금 편성할 수 있는가 —— 온라인은 act_form (아침 · 저녁 준비)
func can_form() -> bool:
	return online == null or online.can_act("form")


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
	var gt := DB.guard_text(c.tag)      # 11/8 피해 종류 · 병종 갑옷 · 결계 한 줄 ("물리 피해 · 갑옷 30%")
	var rc := DB.role_chip(k)      # 11/9 대표 역할 칩 (기인) + 피해 종류 한 줄
	if gt != "" or not rc.is_empty():
		var gh := UI.hbox(6)
		if not rc.is_empty():      # 역할 칩의 색 칠한 상자는 걷고 글자만 (11/9)
			gh.add_child(UI.lbl("역할", 12, DB.PAL.bamboo_dim))
			gh.add_child(UI.lbl(str(rc.t), 12, DB.PAL.paper, true))
		if gt != "":
			gh.add_child(UI.lbl(gt, 12, DB.kind_col(c.tag)))
		st.add_child(gh)
	st.add_child(TraitBoard.new().setup(k))
	# 11/9 사용자: 초상 옆 빈 공간 정리 —— 오른쪽에는 능력치 · 특기판 · 기질 띠(좁은 모양)를 쌓고, 고유 특기 · 위세 · 패업 · 고유기는 아래 폭 전체 카드 격자로
	var ult0 = DB.ult_of(k) if c.tier >= 6 or DB.is_kiin(k) else null
	if ult0 != null:
		var tb0 := _temper_box(c, ult0, 11, true)
		if tb0 != null:
			st.add_child(tb0)
	top.add_child(st)
	b.add_child(top)
	var ab := UI.vbox(6)
	_ability_rows(ab, k, 12, false, false, [], true)
	b.add_child(ab)
	var folds := UI.vbox(0)          # 11/3 사용자: 접힌 기술 · 특기 · 선호 대열 사이를 좁힌다
	b.add_child(folds)
	# 기술 —— 접힌 칸 하나에 기술마다 효과 · 수치 표
	# 11/5 사용자: 잔기술을 따로 부르지 않는다 —— 자주 쓰는 기술로 기술 목록 맨 앞에 (발동: "평타 3번에 한 번")
	var mk := Battle.minor_kind(k)
	if not c.get("sks", []).is_empty() or mk != "":
		var sk_items := []
		if mk != "":
			sk_items.append(_kv_box("[color=#D9A64B][b]『%s』[/b][/color]" % Battle.minor_def(mk).n, "평타 %d번에 한 번" % int(Battle.minor_def(mk).every), minor_desc(k, false), DB.PAL.bamboo_dim, 13))
		for x in c.get("sks", []):
			sk_items.append(_kv_box("[color=#D9A64B][b]『%s』[/b][/color]" % x.n, DB.sk_when(x), DB.skill_desc(c, x), DB.PAL.bamboo_dim, 13))
		folds.add_child(_fold_sec("card_skills", "기술 %d" % (c.get("sks", []).size() + (1 if mk != "" else 0)), _kv_stack(sk_items)))
	var tl := DB.trait_list(k)
	if not tl.is_empty():
		# 왼쪽 칸 = 특기 이름+레벨, 오른쪽 = 설명(—— 에서 줄바꿈)과 그 아래 수치. 오른쪽 칸 왼끝이 맞는다
		var tg := _info_grid()
		for t in tl.filter(func(x): return not x.unique):
			var body := "[color=#C6AC7C]%s[/color]%s" % [(t.d as String).replace(" —— ", "\n"), ("\n[color=#8FD4C2]%s[/color]" % t.mt) if t.mt != "" else ""]
			_info_row(tg, "[b]%s[/b][color=#D9A64B]%d[/color]%s" % [t.name, t.lv, "\n[color=#8D7B5C]단체[/color]" if t.group else ""], body)
		var tv := UI.vbox(6)      # 11/9 사용자: 특기 펼치기 버튼 제거 —— 늘 펼쳐 둔다
		tv.add_child(UI.eyebrow("특기 %d" % tl.filter(func(x): return not x.unique).size()))
		tv.add_child(tg)
		var tm := MarginContainer.new()
		tm.add_theme_constant_override("margin_top", 8)
		tm.add_theme_constant_override("margin_left", 4)
		tm.add_theme_constant_override("margin_bottom", 8)
		tm.add_child(tv)
		folds.add_child(tm)
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
	hb.add_theme_font_override("font", DB.title_font(14))
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


## 능력치 한 줄 —— 칼 공격 · 방패 방어 · 신발 속도 (11/9 글자 라벨 → 심볼 아이콘, 사용자: 텍스트가 너무 많다). 책략계는 공격을 푸른색으로 (원거리 · 범위)
func _stat_row(c: Dictionary) -> Control:
	var magic: bool = DB.INT_TAGS.has(c.tag)
	var g := UI.hbox(0)      # 11/9 칸마다 테두리 상자 대신 가는 세로선으로 나눈다 (UI 절제 · 정돈)
	g.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var i := 0
	for pair in [["blade", "공격", c.atk, true, Color("#6fa8ff") if magic else Color("#ff6b5a")], ["shield", "방어", c["def"], false, null], ["boot", "속도", c.spd, false, null]]:
		if i > 0:
			g.add_child(UI.hair(true))
		i += 1
		var a := UI.lbl(str(int(pair[2])), 18, pair[4] if pair[3] else DB.PAL.paper, true)
		a.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		a.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		g.add_child(_stat_cell(pair[0], pair[1], pair[4] if pair[3] else DB.PAL.bamboo_dim.lightened(0.15), a))
	return g


## 능력치 한 칸 —— 아이콘 + 숫자. 아이콘이 처음이어도 알 수 있게 누르면(PC 는 올려 두면) 이름이 잠깐 뜬다 (칼 = 공격 · 방패 = 방어 · 신발 = 속도)
func _stat_cell(icon: String, nm: String, col: Color, num: Control) -> PanelContainer:
	var h := UI.hbox(5)
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	var iv := Icons.View.new(icon, col, STAT_ICON)
	iv.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var nl := UI.lbl(nm, 13, col, true)
	nl.custom_minimum_size.x = STAT_ICON
	nl.visible = false
	h.add_child(iv)
	h.add_child(nl)
	h.add_child(num)
	var pc := UI.panel(h, 4)
	pc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pc.tooltip_text = nm
	pc.gui_input.connect(func(e):
		if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT and not e.pressed:
			var gen := int(pc.get_meta("gen", 0)) + 1
			pc.set_meta("gen", gen)
			iv.visible = false
			nl.visible = true
			get_tree().create_timer(1.5).timeout.connect(func():
				if is_instance_valid(pc) and int(pc.get_meta("gen", 0)) == gen:
					iv.visible = true
					nl.visible = false))
	return pc


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
	for pair in [["blade", "공격", "atk"], ["shield", "방어", "def"], ["boot", "속도", "spd"]]:
		var base: float = float(c[pair[2]])
		var got: float = ss[pair[2]][1] if ss.has(pair[2]) else base
		var raw: float = ss[pair[2]][2] if ss.has(pair[2]) else base
		var d := roundi(raw - base)          # 버프로 늘어난 만큼 (초록)
		var cutv := roundi(raw - got)        # 적 효과로 깎인 만큼 (빨강)
		var bb := "[center][b][font_size=18]%d[/font_size][/b]" % roundi(base)
		if d != 0:
			bb += " [color=%s][font_size=13]%s%d[/font_size][/color]" % ["#7fe0a8" if d > 0 else "#ff7a6a", "+" if d > 0 else "−", absi(d)]
		if cutv > 0:
			bb += " [color=#ff7a6a][font_size=13]−%d[/font_size][/color]" % cutv
		bb += "[/center]"
		var a := UI.rich(bb, 13)
		a.fit_content = true
		a.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		g.add_child(_stat_cell(pair[0], pair[1], (Color("#6fa8ff") if DB.INT_TAGS.has(c.tag) else Color("#ff6b5a")) if pair[2] == "atk" else DB.PAL.bamboo_dim.lightened(0.15), a))
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
		if ss.item:
			why.append("보급품 %s" % DB.IT[ss.item].name)
		right.add_child(UI.rich("[color=#7fe0a8]＋늘어난 값[/color] [color=#8D7B5C]%s · 단체 특기 · 위세 · 사기[/color]  [color=#ff7a6a]−깎인 값[/color] [color=#8D7B5C]적 효과 (전투 시작 기준)[/color]" % " · ".join(why), 11))
	top.add_child(right)
	b.add_child(top)
	# 고유 특기 · 위세 · 고유기 + 기질 —— 디테일창과 같은 칸 (11/7 사용자)
	_ability_rows(b, k, 13)
	# 기술 (자주 쓰는 기술 + 일반 기술)
	var mk := Battle.minor_kind(k)
	var bsk := []
	if mk != "":
		bsk.append(_kv_box("[color=#D9A64B][b]『%s』[/b][/color]" % Battle.minor_def(mk).n, "평타 %d번에 한 번" % int(Battle.minor_def(mk).every), minor_desc(k, false), DB.PAL.bamboo_dim, 13))
	for x in c.get("sks", []):
		bsk.append(_kv_box("[color=#D9A64B][b]『%s』[/b][/color]" % x.n, DB.sk_when(x), DB.skill_desc(c, x), DB.PAL.bamboo_dim, 13))
	if not bsk.is_empty():
		b.add_child(_kv_stack(bsk))
	# 특기 —— 이름 · 레벨 · 수치 한 줄씩 (고유 특기는 위 칸에)
	var tl := DB.trait_list(k).filter(func(x): return not x.unique)
	if not tl.is_empty():
		var tg := _info_grid()
		for t in tl:
			_info_row(tg, "[b]%s[/b][color=#D9A64B]%d[/color]" % [t.name, int(t.lv)],
				"[color=#8FD4C2]%s[/color]" % (t.mt if t.mt != "" else (t.d as String).get_slice(" —— ", 0)))
		b.add_child(UI.eyebrow("특기 %d" % tl.size()))
		b.add_child(tg)


## 11/7 고유기 기질 (사용자: 플레이어가 알 수 있게) —— 기호(Icons). 11/9 색은 걷었다
const TEMPER_ICON := {"맹장": "blade", "수호": "shield", "지략": "news", "저격": "target", "분노": "flame"}
## 고유 특기 · 위세(기인) · 패업 · 고유기 줄의 기호 —— 11/9 사용자: 종류를 색 카드가 아니라 작은 기호 + 옅은 라벨로 (작업현황 ㊽)
const ABILITY_ICON := {"고유 특기": "seal", "위세": "banner", "기인": "banner", "패업": "crown", "고유기": "burst"}


## 고유 특기 · 위세(기인) · 패업 · 고유기 항목을 차례로 모은다 —— {kind, name, effect, icon, sub, gold} (디테일창 · 갈무리창이 같이 쓴다)
func _ability_items(k: String) -> Array:
	var c: Dictionary = DB.C[k]
	var out := []
	for t in DB.trait_list(k):
		if t.unique:
			out.append({"kind": "고유 특기", "name": t.name, "effect": t.mt if t.mt != "" else (t.d as String).get_slice(" —— ", 0), "icon": ABILITY_ICON["고유 특기"], "sub": "", "gold": true})
	if DB.AURA.has(k):
		var kiin: bool = DB.is_kiin(k)
		var kd := "기인" if kiin else "위세"
		out.append({"kind": kd, "name": DB.AURA[k].n, "effect": DB.aura_effect(k), "icon": ABILITY_ICON[kd], "sub": ""})
	if DB.AURA.has(k) and DB.AURA[k].has("paeup"):      # 11/9 패업 —— 이름 · 조건 · 효과 (판정은 Battle._paeup_setup)
		var pa: Dictionary = DB.AURA[k].paeup
		var cw: String = str(pa.get("what", "화상을 거는 장수" if str(pa.cond) == "burn" else "상태이상을 거는 장수"))
		var pe: String = str(pa.get("d", "")) if str(pa.cond) == "none" else "아군에 %s 자신 외 %d명 이상이면 —— %s" % [cw, int(pa.need), str(pa.get("d", ""))]      # 조건 없는 패업은 설명만 (11/9)
		out.append({"kind": "패업", "name": str(pa.n), "effect": pe, "icon": ABILITY_ICON["패업"], "sub": ""})
	var u = DB.ult_of(k) if c.tier >= 6 or DB.is_kiin(k) else null
	if u != null:
		out.append({"kind": "고유기", "name": u.name, "effect": UI.ult_desc(u, c.tier), "icon": ABILITY_ICON["고유기"], "sub": "%d초부터" % roundi(u.wait)})
	return out


## 고유 특기 · 위세(기인) · 패업 · 고유기 (+ 기질) —— 디테일창 · 전투장수창 · 보급 팝업이 같은 모양.
## 11/9 사용자: 색 카드 나열이 'AI 티' —— 한 장의 패널 안에서 얇은 구분선으로 줄을 나눈다. narrow(휴대폰 세로 보급 팝업)면 줄 안을 위아래로 쌓는다
func _ability_rows(into: Container, k: String, fs := 12, narrow := false, with_temper := true, skip: Array = [], with_inyeon := false) -> void:
	var c: Dictionary = DB.C[k]
	var its := _ability_items(k).filter(func(it): return not skip.has(str(it.get("kind", ""))))      # skip: 뺄 종류 (보급 팝업은 패업, 11/9)
	var u = DB.ult_of(k) if c.tier >= 6 or DB.is_kiin(k) else null
	if u != null and with_temper:
		var ti := _temper_item(c, u)
		if not ti.is_empty():
			its.append(ti)
	if with_inyeon:      # 11/11 인연 —— 맨 아래 줄 (디테일창)
		var iy := _inyeon_item(k)
		if not iy.is_empty():
			its.append(iy)
	if not its.is_empty():
		into.add_child(_ability_panel(its, fs, narrow))


## 11/11 인연 줄 항목 —— 이 카드의 인물이 속한 인연들 (없으면 {}). _ability_row 가 칩 + 구성원 타일로 그린다
func _inyeon_item(k: String) -> Dictionary:
	var names: Array = DB.inyeon_of(k)
	if names.is_empty():
		return {}
	return {"kind": "인연", "inyeon": names, "k": k, "name": "", "effect": "", "icon": "link", "sub": ""}


## 인연 구성원 타일의 상태 —— 가진 장수(갈무리창 · 디테일창 기준: 손패 + 편성판) · 갈무리한 장수 · 지금 보는 장수
func _inyeon_ctx(k: String) -> Dictionary:
	return {"own": InyeonUI.owned_map(run), "pins": InyeonUI.pinned_map(forge_tree.pins), "me": DB.person(k)}


## 기질 한 줄 항목 —— 규칙 배정이든 수동 지정이든 Battle.temper_name 이 실제 기질을 준다 (11/7). 없으면 {}
func _temper_item(c: Dictionary, u: Dictionary) -> Dictionary:
	var t := Battle.temper_name(c, u)
	if t == "":
		return {}
	var ss: PackedStringArray = str(Battle.TEMPER_DESC.get(t, "")).split(". ")
	var eff := []
	for pair in [["차는 때", ss[0] if ss.size() > 0 else ""], ["쓰는 때", ss[1] if ss.size() > 1 else ""]]:
		if pair[1] != "":
			eff.append("[color=#8D7B5C]%s[/color]  %s" % [pair[0], pair[1]])
	return {"kind": "기질", "name": t, "effect": "
".join(eff), "raw": true, "icon": TEMPER_ICON.get(t, "pick"), "sub": ""}


## 능력 패널 —— 줄 사이는 hairline. simple 이면 이름만 한 줄씩 (갈무리창), on_tap 이 있으면 줄을 눌러 호출. bg=false 면 바탕 없이 줄만
func _ability_panel(items: Array, fs := 12, narrow := false, simple := false, on_tap := Callable(), bg := true) -> Control:
	var outer := PanelContainer.new()
	# 11/9 사용자: 능력 패널에 아주 옅은 바탕을 준다 (시트 바탕과 구분선만으로는 밋밋했다)
	outer.add_theme_stylebox_override("panel", UI.flat(Color(DB.PAL.ink3, 0.55) if bg else Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, UI.R, 4 if bg else 0))
	outer.mouse_filter = Control.MOUSE_FILTER_PASS
	var col := UI.vbox(0)
	for i in items.size():
		if i > 0:
			col.add_child(UI.hair())
		col.add_child(_ability_row(items[i], fs, narrow, simple, on_tap))
	outer.add_child(col)
	return outer


## 능력 한 줄 —— 왼쪽 기호 + 옅은 라벨, 이름(크고 종이색 · 고유 특기만 금), 아래 효과(한 단계 작고 옅게, 수치만 옥색)
func _ability_row(it: Dictionary, fs: int, narrow: bool, simple: bool, on_tap: Callable) -> Control:
	var P := DB.PAL
	if it.has("inyeon"):      # 11/11 인연 줄 —— 이름 칩 + (디테일창) 구성원 타일
		var me: String = DB.person(str(it.k))
		return InyeonUI.detail_row(it.inyeon, _inyeon_ctx(str(it.k)), fs, simple, func(card: String):
			if DB.person(card) != me:
				card_info(card), on_tap)
	var m := MarginContainer.new()
	var vm := 6 if simple else 8
	m.add_theme_constant_override("margin_top", vm)
	m.add_theme_constant_override("margin_bottom", vm)
	if on_tap.is_valid():
		m.mouse_filter = Control.MOUSE_FILTER_STOP
		m.gui_input.connect(func(e):
			if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT and not e.pressed:
				UI.buzz()
				on_tap.call())
	else:
		m.mouse_filter = Control.MOUSE_FILTER_PASS
	var ic := Icons.View.new(str(it.icon), P.bamboo_dim, fs + 2)
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var kl := UI.lbl(str(it.kind), fs - 1, P.bamboo_dim)
	kl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var nl := UI.lbl(str(it.name), fs + (2 if simple else 3), P.gold if it.get("gold", false) else P.paper, true)
	nl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	nl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var sl: Label = null
	if str(it.get("sub", "")) != "":
		sl = UI.lbl(str(it.sub), fs - 2, P.bamboo_dim)
		sl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var eff: RichTextLabel = null
	if not simple and str(it.get("effect", "")) != "":
		eff = UI.rich(str(it.effect) if it.get("raw", false) else _hl(str(it.effect)), fs - 1)
		eff.add_theme_color_override("default_color", P.bamboo)
		eff.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if narrow and not simple:
		var v := UI.vbox(3)
		var hd := UI.hbox(5)
		hd.add_child(ic)
		hd.add_child(kl)
		var sp := Control.new()
		sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hd.add_child(sp)
		if sl != null:
			hd.add_child(sl)
		v.add_child(hd)
		v.add_child(nl)
		if eff != null:
			v.add_child(eff)
		m.add_child(v)
		return m
	var lab := HBoxContainer.new()      # 라벨 칸 —— 모든 줄의 이름 왼끝이 맞는다
	lab.add_theme_constant_override("separation", 5)
	lab.custom_minimum_size.x = 80
	lab.add_child(ic)
	lab.add_child(kl)
	var lm := MarginContainer.new()
	lm.add_theme_constant_override("margin_top", 3)
	lm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lm.add_child(lab)
	var h := UI.hbox(8)
	lm.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	h.add_child(lm)
	var rv := UI.vbox(2)
	rv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var nr := UI.hbox(6)
	nr.add_child(nl)
	if sl != null:
		sl.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		nr.add_child(sl)
	rv.add_child(nr)
	if eff != null:
		rv.add_child(eff)
	h.add_child(rv)
	m.add_child(h)
	return m


static var _hl_re: RegEx

## 효과 글의 수치만 옥색으로 —— "아군 사기 +7 공격 +40% · 피해 706%" 의 +7 · +40% · 706% 를 [color=#8FD4C2] 로 (칸 안에서 '효과 · 수치'가 읽히게).
## 부호가 붙은 수, 단위(% · 턴 · 초 · 부대 · 명)가 붙은 수만 —— "후열 2체" 같은 대상 수는 그대로
func _hl(text: String) -> String:
	if _hl_re == null:
		_hl_re = RegEx.create_from_string("([+\\-−×]\\s?\\d[\\d,]*(?:\\.\\d+)?\\s?(?:%p|%|턴|초|부대|명)?|\\d[\\d,]*(?:\\.\\d+)?\\s?(?:%p|%|턴|초|부대|명))")
	return _hl_re.sub(text.replace(" / ", " · "), "[color=#8FD4C2]$1[/color]", true)


## 기질 설명 —— 구분선 아래 기호 · 라벨 · 이름, 그 아래 두 줄 (차는 때 · 쓰는 때). 디테일창의 초상 옆 칸 (상자 없음)
func _temper_box(c: Dictionary, u: Dictionary, fs := 11, _narrow := false) -> Control:
	var ti := _temper_item(c, u)
	if ti.is_empty():
		return null
	var P := DB.PAL
	var v := UI.vbox(4)
	v.add_child(UI.hair())
	var hd := UI.hbox(5)
	var ic := Icons.View.new(str(ti.icon), P.bamboo_dim, fs + 4)
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hd.add_child(ic)
	var kl := UI.lbl("기질", fs, P.bamboo_dim)
	kl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hd.add_child(kl)
	hd.add_child(UI.lbl(str(ti.name), fs + 3, P.paper, true))
	v.add_child(hd)
	var eff := UI.rich(str(ti.effect), fs)
	eff.add_theme_color_override("default_color", P.bamboo)
	eff.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_child(eff)
	return v


## 효과 · 수치 표 상자 (11/3 사용자: '효과, 수치' 식으로 이쁘게) —— 머리줄(이름 · 부제) 아래 두 칸 표.
## body 는 "아군 책략 +10% / 적 책략방어 −10%" 처럼 ' · ' · ' / ' 로 나뉜 글 —— 끝의 수치를 오른쪽 칸으로 뗀다
func _kv_box(head_bb: String, sub: String, body: String, _col: Color, fs := 12) -> Control:
	var v := UI.vbox(3)
	var h := UI.rich(head_bb + ("  [color=#8D7B5C][font_size=%d]%s[/font_size][/color]" % [fs - 1, sub] if sub != "" else ""), fs + 1)
	h.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_child(h)
	v.add_child(_kv_grid(body, fs))
	return v


## 효과 · 수치 표 여럿을 한 장 패널에 —— 사이는 hairline (11/9: 기술마다 따로 상자를 두지 않는다)
func _kv_stack(items: Array) -> Control:
	var pc := PanelContainer.new()
	pc.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	var col := UI.vbox(0)
	for i in items.size():
		if i > 0:
			col.add_child(UI.hair())
		var m := MarginContainer.new()
		m.add_theme_constant_override("margin_top", 8)
		m.add_theme_constant_override("margin_bottom", 8)
		m.add_child(items[i])
		col.add_child(m)
	pc.add_child(col)
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


const KIIN_T := 9      # 기인 칸 —— 등급 거르기 · 계보 줄 (등급 수 바깥의 자리)

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


const FORGE_STEP := 18      # 「더 보기」 로 프레임마다 덧붙이는 타일 수
const FORGE_FIRST := 36      # 조합 탭 '나머지' 에 처음 만드는 타일 수 (11/10 —— 더 보기 전)


func _page_forge() -> Control:
	var v := UI.vbox(14)
	v.add_child(forge_tree.build())
	# 거르기 —— 병종 · 등급을 기호 · 색 칸 한 줄씩 (11/2 사용자: 글씨를 줄여 공간 확보)
	var row1 := HBoxContainer.new()
	row1.add_theme_constant_override("separation", 4)
	var can_now := {}      # 11/10 지금 되는 조합 —— 칸마다 191번씩 다시 묻지 않고 한 번만 (조합 탭 열 때 걸리는 시간)
	for r in DB.D.RECDEF:
		if run.can_forge(r[0]):
			can_now[r[0]] = true
	for t in [""] + DB.D.TAGORDER:
		var n: int = DB.D.RECDEF.filter(func(r): return can_now.has(r[0]) and (t == "" or DB.C[r[0]].tag == t)).size()
		row1.add_child(_filter_chip("all" if t == "" else "", DB.ICON.get(t) if t != "" else null, str(n) if n > 0 else "", DB.PAL.paper, forge_tag == t, func():
			forge_tag = t
			_open.erase("forge:more")
			render()))
	v.add_child(row1)
	var row2 := HBoxContainer.new()
	row2.add_theme_constant_override("separation", 4)
	for t in [0, 3, 4, 5, KIIN_T, 6, 7, 8]:        # 11/3 일반 없음 · 기인(9)은 전설 옆
		var tn: String = "all" if t == 0 else ("기" if t == KIIN_T else DB.TIER[t].n.left(1))
		row2.add_child(_filter_chip(tn, null, "", DB.PAL.paper if t == 0 else (DB.KIIN_COL if t == KIIN_T else DB.TIER[t].c), forge_tier == t, func():
			forge_tier = t
			_open.erase("forge:more")
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
	var ready: Array = lst.filter(func(r): return can_now.has(r[0]))
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
	lst = lst.filter(func(r): return not can_now.has(r[0]) and not rec.has(r[0]))
	var miss_of := {}      # 11/10 모자란 수를 비교할 때마다 다시 세지 않고 한 번만 (정렬이 약 10ms 걸렸다)
	for r in lst:
		miss_of[r[0]] = run.miss_count(r[0])
	lst.sort_custom(func(x, y):
		var a: int = miss_of[x[0]]
		var b2: int = miss_of[y[0]]
		if a != b2:
			return a < b2
		return DB.C[x[0]].tier > DB.C[y[0]].tier)
	# 11/7 사용자: 조합 페이즈의 나머지는 모두 펼쳐 둔다 —— 11/3 의 '가까운 16개 + 더 보기' 를 걷었다.
	# 11/10 사용자: 처음 조합 탭을 열면 프레임이 떨어진다 → 타일 200개를 한 번에 만들고 그리는 일(글꼴 · 그림 처음 쓰기)이 크다. 가까운 순 처음 36장만 만들고
	# 나머지는 「더 보기」 로 (거르기를 바꾸거나 다른 탭에 다녀오면 다시 접힌다. 먼저 볼 줄 —— 갈무리 · 추천 · 지금 조합 가능 —— 은 그대로 다 보인다)
	var more_open: bool = _open.get("forge:more", false)
	var shown_n: int = lst.size() if (more_open or lst.size() < FORGE_FIRST + 12) else FORGE_FIRST      # 몇 장 안 남으면 단추 없이 다 보인다
	var g := minis()
	for r in lst.slice(0, shown_n):
		g.add_child(_forge_tile(r[0]))
	var sec2 := UI.vbox(6)
	sec2.add_child(UI.head(("나머지 %d" if not ready.is_empty() else "조합법 %d") % lst.size(), ""))
	sec2.add_child(g if not lst.is_empty() else UI.hint("이 조건의 조합법이 없다."))
	if shown_n < lst.size():
		var rest: Array = lst.slice(shown_n)
		var mb := UI.btn("더 보기  (+%d)" % rest.size(), func(): pass, "ghost", 40)
		mb.pressed.connect(func(): _forge_more(g, mb, rest))
		sec2.add_child(mb)
	v.add_child(sec2)
	return v


## 조합 탭 '나머지' 타일 한 장 —— 지금 조합 가능이면 옥색 '조합', 아니면 모자란 수 (-1 붉음 · -2 이상 먹색) · 재료 다 있고 아이템만 없으면 ◆
func _forge_tile(out: String) -> MiniTile:
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
	return t


## 「더 보기」 —— 남은 타일을 한 번에 만들면 그 프레임이 멈칫하므로(약 150장) 프레임마다 FORGE_STEP 장씩 격자에 덧붙인다. 상태(_open)는 이 탭에 있는 동안만 (go 가 지운다)
func _forge_more(g: Control, btn: Button, rest: Array) -> void:
	_open["forge:more"] = true
	btn.queue_free()
	var i := 0
	while i < rest.size():
		if not is_instance_valid(g) or not g.is_inside_tree() or page != "forge":
			return      # 그 사이 페이지가 다시 그려졌다 —— 새 페이지가 이미 다 펼쳐져 있다
		for j in range(i, mini(i + FORGE_STEP, rest.size())):
			g.add_child(_forge_tile(rest[j][0]))
		i += FORGE_STEP
		await get_tree().process_frame


## 거르기 칸 —— 글씨 대신 기호(병종) · 색(등급). 고르면 밝은 테두리, 오른쪽 위 작은 숫자 = 지금 조합 가능 수
func _filter_chip(txt: String, icon, cnt: String, col: Color, on: bool, cb: Callable) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(0, 34)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var tier_col: bool = icon == null and txt != "all"
	for st in ["normal", "hover", "pressed"]:      # 11/9: 등급색 덩어리 칩 → 먹색 칩 + 등급색 글자, 고른 것만 금 얇은 선
		b.add_theme_stylebox_override(st, UI.flat(DB.PAL.ink3 if on else DB.PAL.ink2, DB.PAL.gold if on else Color(0, 0, 0, 0), 1 if on else 0, UI.R, 0))
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
		b.add_theme_color_override("font_color", col.lightened(0.15) if tier_col else DB.PAL.paper)
		b.add_theme_color_override("font_hover_color", col.lightened(0.3) if tier_col else DB.PAL.paper)
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
			# 11/7 사용자: 큰 두 줄 버튼(UI.act) 대신 토벌 · 대전과 같은 한 줄 '출진 · 9/9칸 · 76,500명'
			v.add_child(_war_btn("출진" if placed > 0 else "편성이 비어 있다", ("%d/9칸 · %s명" % [placed, Battle.num(run.board_power())]) if placed > 0 else "",
				false, placed == 0, func(): _start("tour"), "warn"))
		v.add_child(_bracket())
	else:
		# 11/4 사용자: 토벌 · 대전을 한 줄에, 설명 글은 빼고, 남는 공간에 지금 배치된 진영을 그린다
		# 11/7 사용자: '목요일 오전' 글은 머리띠에 이미 있어 뺀다. 큰 두 줄 버튼(UI.act 64) 은 한 줄(46)로, 끝난 것은 완료 표시만 작게
		var row := UI.hbox(8)
		row.add_child(_war_btn("① 토벌", run.quest_name(), run.quest_done, placed == 0, func(): _start("quest"), "pri"))
		row.add_child(_war_btn("② 대전", "임의 세력" if run.quest_done else "토벌 뒤", run.pvp_done, placed == 0 or not run.quest_done, func(): _start("pvp"), "pri"))
		v.add_child(row)
		var qt := DB.quest_trait(run.day)      # 11/8 토벌 우두머리 성질 —— 그날 아침부터 미리 보인다 (docs/역할_재설계_1108.md 7.3)
		if not qt.is_empty() and not run.quest_done and Battle.shield_enabled:
			v.add_child(UI.hint("오늘 토벌 우두머리 —— %s" % DB.trait_text(qt)))
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
			if run.quest_horde_n() > 0:
				pv.add_child(UI.hint("그 밖에 황건 잡병 %d부대가 몰려온다" % run.quest_horde_n()))
			v.add_child(UI.panel(pv, 10))
		if placed == 0:
			v.add_child(UI.btn("편성이 비어 있다 — 편성하러 가기", func(): go("deploy"), "gold"))
		if run.last_result != null:
			v.add_child(_result_panel())
		if run.can_next():
			# 11/7 사용자: '금요일 오전' 같은 다음 페이즈 이름은 빼고 한 줄 버튼으로
			v.add_child(UI.btn("다음 페이즈로  ▶", func():
				PlayLog.phase_end(run)
				run.advance()
				run.save()
				if run.over != null:
					PlayLog.over(run)
				go("draw"), "pri", 50))
	if not run.is_tour_phase() and placed > 0:
		# 11/7 사용자: 군단 효과는 그림 밖 칩 흐름(접으면 6개 + '+N 더', 펼치면 2열 표)으로 —— 효과가 많은 덱도 줄바꿈될 뿐 메달 줄을 누르지 않는다
		var fx := FormationView.effects_box(run.board, run.form, _open.get("war:fx", false), func(): _toggle("war:fx"), func(k): card_info(k))
		if fx != null:
			v.add_child(fx)
		var fv := FormationView.new().setup(run.board, run.form)
		fv.on_medal = func(k): card_info(k)      # 11/5 사용자: 메달을 누르면 장수 상세
		fv.size_flags_vertical = Control.SIZE_EXPAND_FILL
		var fp := UI.panel(fv, 0)
		fp.size_flags_vertical = Control.SIZE_EXPAND_FILL
		v.size_flags_vertical = Control.SIZE_EXPAND_FILL
		v.add_child(fp)
	if not run.is_tour_phase():
		# 11/7: 전투 탭은 고정 페이지(render 의 fixed —— 진영 그림이 남는 공간을 채운다)라 내용이 길면(점괘 · 펼친 효과 표) 아래가 잘리고
		# 내릴 수도 없었다 —— 탭 안에 제 스크롤을 둔다. 짧으면 안쪽 VBox 가 창을 채우고(진영 그림이 남는 공간), 길면 손가락으로 내린다
		var sc := UI.scroll()
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		v.size_flags_vertical = Control.SIZE_EXPAND_FILL
		sc.add_child(v)
		return sc
	return v


## 전투 탭 행동 버튼 (11/7 사용자) —— 한 줄 '① 토벌 · 백파적'. 끝났으면 작은 '✓ 토벌 완료' 표시만(누를 수 없다), 못 하면 흐리게
func _war_btn(title: String, sub: String, done: bool, disabled: bool, cb: Callable, kind: String) -> Button:
	var P := DB.PAL
	if done:
		var d := UI.btn("✓ %s 완료" % title.substr(2), func(): pass, "", 34)
		d.disabled = true
		d.add_theme_font_size_override("font_size", 13)
		d.add_theme_color_override("font_disabled_color", Color(P.jade, 0.9))
		d.add_theme_stylebox_override("disabled", UI.flat(Color(P.jade, 0.08), Color(P.jade, 0.4), 1, 17, 0))
		var sb: StyleBoxFlat = d.get_theme_stylebox("disabled")
		sb.content_margin_left = 12
		sb.content_margin_right = 12
		return d
	var b := UI.btn("%s · %s" % [title, sub] if sub != "" else title, cb, kind, 46)
	b.disabled = disabled
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.add_theme_font_size_override("font_size", 15)
	b.add_theme_font_override("font", DB.title_font(15))
	b.clip_text = true
	b.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	return b


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
	var parts := ["잔존 %d : %d" % [r.left, r.eLeft]]      # 11/9: 색 칩 줄 → 한 줄 글 (구분점)
	if r.mvp != "":
		parts.append("수훈 %s" % r.mvp)
	if run.last_spoil != null:
		parts.append(UI.spoil_bb(run.last_spoil))      # 11/10 토벌 성과 보너스는 금색 "(대승 +M)"
	if run.ticket_left() > 0:
		parts.append("선택권 %d" % run.ticket_left())
	if not r.win and run.last_hp_loss > 0:      # 11/10 연출은 지나가니 깎인 만큼은 결과 줄에도 남긴다 (온라인 결과 칸과 같은 글)
		parts.append("민심 −%d" % run.last_hp_loss)
	v.add_child(UI.result_line(parts))
	if not r.win and str(r.get("why", "")) != "":      # 11/9 패배 사유 (민심 깎인 양은 위 결과 줄에 이미 있다)
		v.add_child(UI.hair())
		var wl := UI.lbl(str(r.why), 13, DB.PAL.paper)
		wl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.add_child(wl)
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
	var bye: Array = t.get("bye", []) if t.round == 0 else []
	if not bye.is_empty():      # 11/11 8명 미만인 온라인 방 —— 상위 시드는 8강을 건너뛴다
		v.add_child(UI.hint("부전승 (4강 직행) — %s" % " · ".join(bye)))
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
	if "say_cb" in _battle:
		_battle.say_cb = Callable()
	_battle.play(bt, false)


## 온라인 —— 서버가 계산한 결과를 재생만 한다. params 는 내 쪽이 A 가 되게 맞춘 전투 재료 —— BattleView 가 전투장수창의 버프 수치를 재는 데 쓴다 (11/9)
func show_battle(res: Dictionary, last: bool, kind := "", params := {}) -> void:
	close_sheet()
	_battle_res = null
	_battle_done.visible = false
	_hide_report()
	_battle_done.text = "결과 정리  ▶" if last else "다음 전투  ▶"
	_battle_last = last
	_battle_kind = kind
	_battle_layer.visible = true
	_hide_band()
	Settings.apply_port(_battle.port)
	if "say_cb" in _battle:      # 11/9 사용자: 전투를 보는 중에도 한마디 —— BattleView 위 띠의 [한마디] 가 이 시트를 연다
		_battle.say_cb = online.quick_sheet if online != null else Callable()
	# play_res(res, kind, params) —— 세 번째 인자(재료)는 BattleView 쪽이 받게 되면 넘긴다 (인자 수를 보고)
	var nargs := 2
	for m in _battle.get_method_list():
		if m.name == "play_res":
			nargs = m.args.size()
	if nargs >= 3:
		_battle.callv("play_res", [res, kind, params])
	else:
		_battle.play_res(res, kind)


## 11/12 사용자: 전투 메뉴의 '게임 나가기' —— 온라인은 방을 나가고(자리는 AI 가 이어받는다), 혼자 하기는 저장하고 처음 화면으로
## (진행 중인 전투는 Run.battle 로 남아 이어하기 때 resolve_pending 이 마무리한다)
func _leave_from_battle() -> void:
	hide_battle()
	close_sheet()
	if online != null:
		online.leave()
	elif run != null:
		run.save()
	if _title != null:
		_title.queue_free()
	_build_title()


func hide_battle() -> void:
	_battle_layer.visible = false
	_resume_bands()


func _resume_bands() -> void:
	if not _band_busy and not _bands.is_empty():
		_next_band.call_deferred()
	if not _urgent_busy and not _urgents.is_empty():
		_next_urgent.call_deferred()


# ───────── 긴급 등용 띠 (11/10 사용자) —— 다른 사람이 기인 이상 장수를 등용했을 때. 여러 개면 하나씩 ─────────
var _urgents: Array = []
var _urgent_busy := false

func urgent(who: String, unit: String, tail := "") -> void:      # tail —— 11/12 유저전 수훈 연속 문구 (UrgentBand.tail)
	_urgents.append([who, unit, tail])
	if not _urgent_busy:
		_next_urgent()


func _next_urgent() -> void:
	if _urgents.is_empty() or battle_visible():      # 전투 화면 위에는 띄우지 않는다 (전장을 가렸다) —— 전투가 끝나면 이어서
		_urgent_busy = false
		return
	_urgent_busy = true
	var e: Array = _urgents.pop_front()
	var b: Control = UrgentBand.play(self, str(e[0]), str(e[1]), str(e[2]) if e.size() > 2 else "")
	b.done.connect(_next_urgent)


# ───────── 한마디 이모티콘 팝업 (11/10 사용자) —— 보낸 사람 이름 + 큰 기호가 1.5초. 대기실 · 아침 · 저녁 준비 · 전투 보는 중 어디서나 (EmotePop) ─────────
var _emote_layer: Control = null

func emote_pop(who: String, k: int) -> void:
	if _emote_layer == null or not is_instance_valid(_emote_layer):
		_emote_layer = EmotePop.new()
		add_child(_emote_layer)
	_emote_layer.add(who, k)


func battle_visible() -> bool:
	return _battle_layer.visible


## 11/9 패배 사유 —— 결과 로스터(등급 · 병력)로 어림한다. 의미 있는 것 두 줄까지 (병력 → 등급 → 낮은 등급 비율 → 빈 칸). 판정과 무관한 안내 글
func _why_lost(res: Dictionary) -> String:
	var n_a := 0.0
	var n_b := 0.0
	var t_a := 0.0
	var t_b := 0.0
	var c_a := 0
	var c_b := 0
	var low := 0
	var b_left := 0.0
	for u in res.get("roster", []):
		if u.camp == "A":
			n_a += float(u.max)
			t_a += float(u.tier)
			c_a += 1
			if int(u.tier) <= 2:
				low += 1
		else:
			n_b += float(u.max)
			t_b += float(u.tier)
			c_b += 1
			b_left += maxf(0.0, float(u.left))
	var out: Array = []
	if n_b > n_a * 1.15 and n_a > 0:
		out.append("적 병력 %s명 대 아군 %s명 —— 머릿수에서 밀렸다." % [Battle.num(int(n_b)), Battle.num(int(n_a))])
	if c_a > 0 and c_b > 0 and t_b / c_b - t_a / c_a >= 0.5:
		out.append("적 평균 %.1f등급 대 내 %.1f등급 —— 조합 탭에서 등급을 올리자." % [t_b / c_b, t_a / c_a])
	if c_a > 0 and low >= 3 and low * 3 >= c_a:
		out.append("%s · %s 카드가 %d/%d장 —— 같은 카드를 모아 조합하면 강해진다." % [DB.TIER[1].n, DB.TIER[2].n, low, c_a])
	if c_a < 9:
		out.append("편성 %d칸만 채웠다 —— 9칸을 모두 채우자." % c_a)
	if out.is_empty():
		var pct := roundi(b_left / maxf(1.0, n_b) * 100.0)      # 적이 남긴 병력 비율 —— 60% 이상이면 완패
		if pct >= 60:
			out.append("적이 병력 %d%% 를 남긴 완패 —— 등급보다 조합 · 편성 구성을 다시 확인하자." % pct)
		else:
			out.append("아깝게 졌다(적 %d%% 남음) —— 편성 탭에서 앞줄 · 뒷줄 배치를 바꿔 보자." % pct)
	return "
".join(out.slice(0, 2))


func _on_battle_ended(res: Dictionary, _inputs: Array) -> void:
	if _dev_bonus_r >= 0.0:      # 점검 전용 —— 온라인은 재생이 결과를 다시 계산하니 여기서 서버가 준 것(dev_fake_room)과 같게 고친다
		_dev_force_bonus(res)
	_battle_res = res
	if not res.win:
		res["why"] = _why_lost(res)      # 11/9 패배 사유 —— 결과표 · 전투 탭 결과에 한두 줄
	_plan_hp_fx(res)
	_plan_bonus_fx(res)
	if online != null:
		online.replay_ended()      # 11/11 전투를 다 보면 준비 완료 자동 (결과표를 닫기를 기다리지 않는다)
	UI.buzz(30)
	await get_tree().create_timer(1.4).timeout      # 승전 · 패전 도장을 먼저 보이고
	if not _battle_layer.visible or not is_same(_battle.res, res):     # 같은 전투인지 —— 내용 비교(!=)는 큰 결과에 느리다
		return
	_show_report(res)
	_battle_done.visible = true


## 결과표 —— 화면 가운데, 아래에 [종료] 버튼.
## 11/7 사용자: 토벌 대군(적 20부대)은 표가 화면 아래로 넘쳐 내릴 수도 없었다 —— 표 높이를 위 시계 아래(REPORT_TOP)부터
## 아래 장수 칸 · 버튼 위(REPORT_BOT)까지로 묶고, 그 안에서 장수 줄만 스크롤한다(BattleReport.max_h). 버튼은 표 바로 아래 고정
const REPORT_TOP := 110.0      # 위 띠 · 병력 막대 · 시계(0:29) 아래 (논리 좌표 —— 400×889 기준)
const REPORT_BOT := 236.0      # 아래 장수 칸(≈135) + [종료] 버튼(56) + 틈
func _show_report(res: Dictionary) -> void:
	var plan := _hp_plan
	var bplan := _bonus_plan
	_hp_plan = {}
	_bonus_plan = {}
	_hide_report()
	if _battle and _battle.end_clock > 0:
		res["view_len"] = _battle.end_clock
	_report = BattleReport.make(res)
	var w := minf(size.x - 24.0, 460.0)
	var fx_h := (HP_FX_H + 6.0) if (not plan.is_empty() or not bplan.is_empty()) else 0.0      # 민심 줄(패배) · 보너스 줄(승리)이 들어갈 자리만큼 표를 줄인다
	_report.max_h = maxf(240.0, _battle_layer.size.y - REPORT_TOP - REPORT_BOT - fx_h)
	_report.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_report.offset_left = -w / 2
	_report.offset_right = w / 2
	_report.offset_top = REPORT_TOP
	_battle_layer.add_child(_report)
	_battle_layer.move_child(_battle_done, -1)
	_battle_done.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_battle_done.offset_left = -130
	_battle_done.offset_right = 130
	_battle_done.offset_top = -(REPORT_BOT - 10.0)      # 11/3 사용자: 아래 장수 칸을 덮지 않게 위로 —— 결과표가 자리 잡으면 그 바로 아래로
	_battle_done.offset_bottom = _battle_done.offset_top + 56.0
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame      # 표가 두 진영 중 긴 쪽에 맞춰 높이를 정한 뒤(BattleReport._ready 의 한 프레임)
	if _report == null or not is_instance_valid(_report):
		return
	if not plan.is_empty():
		_place_hp_fx(plan, _report.position.y + _report.size.y + 6.0)
	elif not bplan.is_empty():
		_place_bonus_fx(bplan, _report.position.y + _report.size.y + 6.0)
	var top := _report.get_global_rect().end.y + 10.0 - _battle_layer.get_global_rect().end.y + fx_h
	_battle_done.offset_top = minf(top, -(REPORT_BOT - 10.0))
	_battle_done.offset_bottom = _battle_done.offset_top + 56.0


func _hide_report() -> void:
	if _report:
		_report.queue_free()
		_report = null
	if is_instance_valid(_hp_fx):
		_hp_fx.queue_free()
	_hp_fx = null


# ───────── 민심 −N 연출 (11/10) ─────────
## 패배(무승부 포함)로 민심이 깎이는 판은 결과표 바로 아래 한 줄에 「민심 −N」 도장이 쾅 찍히고 막대 · 숫자가 줄어든다 (약 1.6초, 입력은 막지 않는다).
## 혼자 하기는 결과를 정리하기 전이라 Run.hp_preview 로 미리 계산한 값(finish_battle 의 _hp_hit 와 같은 식), 온라인은 서버가 이미 깎아 보낸 값(_hp_shown → run.hp, 이번 단계 마지막 전투에서만)
const HP_FX_H := 46.0
func _plan_hp_fx(res: Dictionary) -> void:
	_hp_plan = {}
	var prev := -1
	var loss := 0
	if online == null:
		if run != null and run.battle != null:
			prev = run.hp
			loss = run.hp_preview(run.battle, res)
	elif _battle_last and _battle_kind in ["quest", "pvp"] and _hp_shown >= 0:
		prev = _hp_shown
		loss = _hp_shown - clampi(run.hp, 0, Run.HP_MAX)
	if _dev_hploss > 0 and online == null and run != null:      # 점검용 --ghploss : 판정과 상관없이 이만큼 깎인 것으로
		prev = run.hp
		loss = _dev_hploss
	if prev >= 0 and loss > 0:
		_hp_plan = {"prev": prev, "loss": loss}


func _place_hp_fx(plan: Dictionary, top: float) -> void:
	var w := minf(size.x - 24.0, 460.0)
	var fx := HpLossFx.new()
	fx.setup(int(plan.prev), int(plan.loss))
	fx.set_anchors_preset(Control.PRESET_CENTER_TOP)
	fx.offset_left = -w / 2
	fx.offset_right = w / 2
	fx.offset_top = top
	fx.offset_bottom = top + HP_FX_H
	_battle_layer.add_child(fx)
	_hp_fx = fx


# ───────── 토벌 성과 보너스 (11/10) ─────────
## 이긴 토벌의 잔존 병력 비가 높으면 기본패(대승이면 선택권까지)를 더 받는다 —— 결과표 아래 같은 자리(패배의 민심 줄과 겹치지 않는다)에 금색 한 줄.
## 혼자 하기는 결과를 정리하기 전이라 Run.quest_bonus 로 미리 계산(finish_battle 이 같은 함수를 쓴다), 온라인은 서버가 계산해 mirror 한 run.last_spoil.
## 알림(가운데 띠)은 혼자 하기는 finish_battle 의 gold 알림, 온라인은 서버 알림이 단계 끝에야 가니 여기서 한 번만 직접 (서버는 mp 일 때 알림을 안 보낸다)
func _plan_bonus_fx(res: Dictionary) -> void:
	_bonus_plan = {}
	if run == null or not res.get("win", false) or res.get("draw", false):
		return
	var base := 0
	var tk := 0
	var r := 0.0
	if online == null:
		if run.battle == null or str(run.battle.get("kind", "")) != "quest" or Run.legacy_rewards:
			return
		var b := Run.quest_bonus(res, run.day)
		base = int(b.base)
		tk = int(b.ticket)
		r = float(b.r)
	else:
		# 11/11 온라인 4일차~ 는 토벌이 없고 대전이 토벌 보상(+ 성과 보너스)을 준다 —— 서버가 last_spoil 에 perf_r 를 싣는다
		if not (_battle_kind in ["quest", "pvp"]) or not _battle_last or run.last_spoil == null or not run.last_spoil.has("perf_r"):
			return
		base = int(run.last_spoil.get("bonus", 0))
		tk = int(run.last_spoil.get("bonus_ticket", 0))
		r = float(run.last_spoil.get("perf_r", 0.0))
	if base <= 0 and tk <= 0:
		return
	var big := r >= Run.QUEST_BONUS_BIG
	_bonus_plan = {"base": base, "ticket": tk, "big": big, "what": "대전" if (online != null and _battle_kind == "pvp") else "토벌"}
	if online != null:
		var key := "%d:%d:%d:%d" % [run.day, run.phase, base, tk]
		if key != _bonus_key:
			_bonus_key = key
			var parts: PackedStringArray = Run.quest_bonus_text(base, tk, big, "대전" if _battle_kind == "pvp" else "토벌").split(" · ", true, 1)
			band(parts[0], DB.PAL.gold, parts[1] if parts.size() > 1 else "")


func _place_bonus_fx(plan: Dictionary, top: float) -> void:
	var w := minf(size.x - 24.0, 460.0)
	var fx := BonusFx.new()
	fx.setup(int(plan.base), int(plan.ticket), bool(plan.big), str(plan.get("what", "토벌")))
	fx.set_anchors_preset(Control.PRESET_CENTER_TOP)
	fx.offset_left = -w / 2
	fx.offset_right = w / 2
	fx.offset_top = top
	fx.offset_bottom = top + HP_FX_H
	_battle_layer.add_child(fx)
	_hp_fx = fx      # 민심 줄과 같은 자리 · 같이 걷는다 (_hide_report)


## 점검용 --gbonus=0.85 —— 이 잔존 비로 이긴 것으로 결과를 고친다(내 편 병력 비 · 적 전멸). --gbattle 이 없으면 토벌을 바로 시작(--speed 8). 끝까지 보려면 --gclose
func _dev_force_bonus(res: Dictionary) -> void:
	res["win"] = true
	res["draw"] = false
	var left := 0
	for u in res.get("roster", []):
		if u.camp == "A":
			u["left"] = int(round(float(u.max) * _dev_bonus_r))
			u["alive"] = int(u.left) > 0
			left += int(u.left)
		else:
			u["left"] = 0
			u["alive"] = false
	res["left"] = left
	res["eLeft"] = 0


## 점검용 --ghploss=N (전투 없이) —— 빈 전투 화면에 민심 줄만 띄우고, 끝나면 결과를 정리한 것처럼 메인으로 돌아가 머리띠가 줄어드는 모습을 본다
func _dev_hp_demo(loss: int) -> void:
	await get_tree().create_timer(0.8).timeout
	var prev := run.hp
	_battle_layer.visible = true
	_place_hp_fx({"prev": prev, "loss": loss}, 300.0)
	await get_tree().create_timer(2.6).timeout
	run.hp = maxi(0, prev - loss)
	run.last_hp_loss = loss
	_hide_report()
	_battle_layer.visible = false
	go("war")


func _on_battle_close() -> void:
	if online != null:
		_battle_res = null
		online.watch_next()
		return
	if _battle_res == null:
		return
	PlayLog.battle_end(run, run.battle, _battle_res, _battle.end_clock, _battle.inputs, _battle.speed_sec)
	var hp0 := run.hp
	var why := str(_battle_res.get("why", ""))
	run.finish_battle(_battle_res)
	if why != "" and run.last_result != null:
		run.last_result["why"] = why
	if _dev_hploss > 0:      # 점검용 --ghploss : 연출한 만큼만 깎인 것으로 맞춘다
		run.hp = maxi(0, hp0 - _dev_hploss)
		run.last_hp_loss = _dev_hploss
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
	var rows := [{"name": "나", "epi": "%d승 %d패 · 민심 %d" % [run.my_w, run.my_l, run.hp],
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
		# 11/5 사용자: 봇 플레이어의 세력 표기 · PV 는 순위에서 뺀다. 11/9 사용자: 내 줄의 '촉' 칩도 뺀다
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
	sr.add_child(UI.stat("%d위" % run.rank(), "%d인 중" % (run.bots.size() + 1)))      # 11/11 온라인은 방 자리 수(4 · 6 · 8)만큼 — 혼자 하기는 봇 7명 = 8인
	sr.add_child(UI.stat(str(run.my_pv()), "내 전력"))
	sr.add_child(UI.stat("%d승 %d패" % [run.my_w, run.my_l], "전적"))
	sr.add_child(UI.stat("%d" % run.hp, "민심"))      # 11/9 경고 → 민심 (패배마다 깎이고 0 이면 멸망)
	v.add_child(UI.sect("군웅 할거 · %s요일 %s" % [Run.DAYNAME[run.day], Run.PHASE_N[run.phase]], UI.panel(sr)))
	if online != null and online.in_game and not online.room.is_empty():
		v.add_child(online.peers_section())      # 11/11 사용자: 다른 유저의 민심 · 핵심 유닛(기인 · 초월 · 불멸 · 신화)
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
			deploy.seg = str(a.gseg)      # 점검용 —— 편성 아래 칸 (hand · item)
		go(a.get("gpage", "draw"))
	if a.has("ggive") and run != null:      # 점검용 —— --ggive=c177,c160:2,K01 : 카드를 손패에 쥐여 준다 (징집 등급 줄 점검, 11/7 · 저장하지 않는다)
		for s in str(a.ggive).split(",", false):
			var kn := s.split(":")
			if DB.C.has(kn[0]):
				run.give(kn[0], int(kn[1]) if kn.size() > 1 else 1)
		render()
	if a.has("gnewsadd") and run != null:      # 점검용 —— 첫 그리기 뒤에 새 소식 N 건이 온 것처럼 (안 읽은 소식 뱃지 · 소식 시트의 시점 글, 11/10 · 저장하지 않는다)
		for ni in int(a.gnewsadd):
			run.news_seq += 1
			run.news.push_front({"who": "관우팬%d" % ni, "unit": ["c177", "K12", "L12"][ni % 3], "id": run.news_seq, "when": run.when_text()})
		run.news.push_front({"who": "솔", "unit": "", "text": "방을 떠났다 — 자리는 봇이 이어받는다", "id": run.news_seq + 1, "when": "3일차 아침"})
		run.news_seq += 1
		render()
	if a.has("ghp") and run != null:      # 점검용 —— --ghp=25 : 민심을 이 값으로 두고 시작 (머리띠 게이지 색 점검, 11/10)
		run.hp = clampi(int(a.ghp), 0, Run.HP_MAX)
		_hp_shown = run.hp
		_hp_gauge.set_now(run.hp)
	if a.has("ghploss") and run != null:      # 점검용 —— --ghploss=15 : 패배로 민심이 15 깎인 연출. --gbattle 이 있으면 그 전투 결과 화면에서, 없으면 빈 화면에서 바로
		_dev_hploss = int(a.ghploss)
		if not a.has("gbattle"):
			_dev_hp_demo(_dev_hploss)
	if a.has("gbonus") and run != null:      # 점검용 —— --gbonus=0.85 : 잔존 85% 로 이긴 토벌의 결과 연출 (토벌을 바로 시작 · 8배속)
		_dev_bonus_r = clampf(float(a.gbonus), 0.0, 1.0)
		if not a.has("gbattle") and not a.has("gsheet"):      # --gsheet=onwar:noon 과 함께면 온라인 재생이 그 전투를 보인다
			a["gbattle"] = "quest"
			a["speed"] = a.get("speed", "8")
	if a.has("gopen"):
		for key in str(a.gopen).split(","):
			_open[key] = true
		render()
	if a.has("gonline"):
		# 점검용 온라인 —— --gonline=ws://… --gname=이름 (--gcreate=fast|normal|test [--gmax=4|6|8] --gstart=사람수 | --gjoin=방장이름) --gauto
		_go_online()
		online.net.player = str(a.get("gname", "시험"))
		online.net.token = ""      # 같은 PC 의 창들이 net.cfg 를 같이 쓴다 —— 시험 창은 새 토큰
		online.net.consent_ver = NetClient.CONSENT_VER      # 점검 창은 기록에 동의한 것으로 (메모리만 —— net.cfg 에는 남기지 않는다)
		online.dev_auto = a.has("gauto")
		online.net.connect_to(str(a.gonline))
		await online.net.opened
		if a.has("gcreate"):
			online.net.send({"t": "create", "mode": a.gcreate, "max": int(a.get("gmax", "8"))})      # 11/11 --gmax=4|6|8 총 인원
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
	if a.has("gpin"):
		# 점검용 —— --gpin=c186,c150 : 갈무리한 것처럼 (선택권 창의 갈무리 ★ · 재료 표시 점검). 파일에 저장하지 않는다 (다른 점검과 공유되는 user://)
		for k in str(a.gpin).split(","):
			if DB.RECOF.has(k) and not forge_tree.pins.has(k):
				forge_tree.pins.push_front(k)
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
			"unique":      # 점검용 —— 보급 팝업을 억지로 연다 (--gsheet=unique:i81+i72+i89, 비우면 신화 재료 앞 셋)
				var ids: Array = Array(kv[1].split("+")) if kv.size() > 1 and kv[1] != "" else DB.MYTH_ITEMS.keys().slice(0, 3)
				run.uniq_offer = ids
				_unique_sheet()
			"pick":      # 점검용 —— --gsheet=pick:등급 (선택권을 2장 쥐여 주고 연다)
				run.tickets[kv[1]] = maxi(2, int(run.tickets.get(kv[1], 0)))
				picker(int(kv[1]))
			"pickfx": _pick_fx(kv[1], 2, "전설")      # 점검용 —— 선택권 고른 연출
			"itemfx":      # 점검용 —— 아이템을 하나 얻고 가운데 띠가 뜨는지 (11/7, 저장하지 않는다)
				run.gain_item()
				render()
			"news": _news_sheet()      # 점검용 —— 전황 소식 시트 (읽음 처리 포함)
			"settings": _settings_sheet()
			"online": _go_online()      # 점검용 —— 온라인 대전 접속 팝업 (11/9)
			"oncreate":      # 점검용 —— 접속 없이 방 만들기 시트 (총 인원 고르기, 11/11)
				if online == null:
					online = Online.new()
					online.gs = self
					add_child(online)
				online.dev_sheet = true
				online._pick_max = Room.valid_seats(int(a.get("gseats", "8")))      # --gseats=4 면 4명이 골라진 모양
				online.connect_sheet()
			"onwar":      # 점검용 —— 서버 없이 온라인 전투 탭 (--gsheet=onwar:noon | morning | evening_prep | evening, 11/9)
				if online == null:
					online = Online.new()
					online.gs = self
					add_child(online)
				online.dev_max = int(a.get("gseats", "8"))      # 11/11 --gseats=4 : 가짜 방의 총 인원 (kv[1] = lobby 면 대기실)
				online.dev_fake_room(kv[1] if kv.size() > 1 and kv[1] != "" else "noon", float(kv[2]) if kv.size() > 2 else 75.0)
				if kv.size() > 3 and kv[3] == "ready":      # 점검용 —— '준비 완료'를 누른 것처럼 (5초 경고가 안 울려야 한다)
					online.send_ready(true)
				if kv.size() > 3 and kv[3] == "hot":      # 점검용 —— 다른 사람이 기인 이상을 등용했다는 서버 알림이 온 것처럼 (긴급 띠 · 소식 뱃지 · 시점 글)
					online._on_msg({"t": "news", "list": [{"text": "장수214가 신산 제갈량을 등용했습니다", "kind": "news", "who": "장수214", "unit": "c187", "id": 7, "when": "1일차 아침", "hot": 1}]})
			"pick":
				act("begin_picks", ["phase", -1])
				if not run.ticket_tiers().is_empty():
					picker(run.ticket_tiers()[0])
			"online": _go_online()
	if a.has("gemote"):      # 점검용 —— --gemote=3 (받은 이모티콘 팝업 + 한마디 시트) · 3,4,5 (여러 개) · cmp (8종 비교 그림). --gsheet=onwar:morning:75:hot 과 함께 쓰면 긴급 띠와의 자리 점검
		if online == null:
			online = Online.new()
			online.gs = self
			add_child(online)
			online.dev_fake_room("morning")
		online.dev_emote(str(a.gemote))
	if a.has("gtake"):      # 점검용 —— 열린 보급 팝업(--gsheet=unique)의 첫 '받기' 를 누른 것처럼. 앞서 뜬 알림 · 띠는 걷고 누른다 (11/7 받기 뒤 아래 알림 없이 가운데 띠만 뜨는지)
		await get_tree().create_timer(0.4).timeout
		for c in _toast_box.get_children():
			c.queue_free()
		_bands.clear()
		if is_instance_valid(_band_node):
			_band_node.queue_free()
		_band_busy = false
		var tb := _find_btn(_sheet, "받기")
		if tb != null:
			tb.pressed.emit()
	if a.has("gtitle"):
		_title.visible = true
	if a.has("gdots"):          # 점검용 —— 전장 표현 (1 점묘 · 0 3D, 저장하지 않는다)
		Settings.dots = a.gdots != "0"
	if a.has("gatlas"):         # 점검용 —— 탑뷰 병사 인형 아틀라스를 그림 파일로 (--gatlas=경로.png)
		var tv := Type2View.new()
		var at: Texture2D = tv._make_atlas()
		var im: Image = at.get_image()
		im.resize(im.get_width() * 4, im.get_height() * 4, Image.INTERPOLATE_NEAREST)
		im.save_png(str(a.gatlas))
		tv.free()
		get_tree().quit()
		return
	if a.has("gmul"):           # 점검용 —— 탑뷰 병사 배율 (기본 1.5)
		War3D.gpu_mul_t2 = float(a.gmul)
	if a.has("gpintest"):       # 점검용 —— --gpintest=장수id : 갈무리한 뒤 그 재료를 선택권으로 뽑고(실제 타일 탭) 화면이 바로 갱신되는지
		await get_tree().process_frame
		await _pin_pick_test(str(a.gpintest))
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
		if a.has("gultfx"):     # 점검용 —— --gultfx=firestorm : 3초 뒤 아군 첫 부대가 그 고유기 연출을 적 셋에게
			await get_tree().create_timer(3.0).timeout
			var fa := _battle.field.order.filter(func(q): return q.camp == "A" and q.alive)
			var fb := _battle.field.order.filter(func(q): return q.camp == "B" and q.alive)
			if not fa.is_empty() and not fb.is_empty():
				fb.sort_custom(func(x, y): return x.pos.distance_to(fa[0].pos) < y.pos.distance_to(fa[0].pos))      # 실제 고유기처럼 가까운 적
				_battle.field.ult.play(str(a.gultfx), fa[0].key, fb.slice(0, 3).map(func(q): return q.key), fa.map(func(q): return q.key), 0.4)
		if a.has("gunit"):      # 점검용 —— --gunit=A0 : 3초 뒤 전투장수창 (ult 면 고유기가 있는 아군 첫 부대)
			await get_tree().create_timer(3.0).timeout
			var uk := str(a.gunit)
			if uk == "ult":
				for q in _battle.field.order:
					if q.camp == "A" and DB.C.has(q.cid) and (DB.C[q.cid].tier >= 6 or DB.is_kiin(q.cid)):      # 기인은 전설 등급 값이지만 고유기가 있다
						uk = q.key
						break
			battle_unit_sheet(uk)
		if a.has("glong"):      # 점검용 —— 전장 메달 꾹 누르기 입력 시뮬레이션 (11/9): --glong=A0 (부대 key) · soldier(병졸 첫 부대) · cid:y(카드 id 앞머리) · --glongat=dx,dy (메달에서 비껴 누르기)
			await get_tree().create_timer(float(a.get("glongwait", "3.0"))).timeout
			var lk := str(a.glong)
			var lsq: Squad = _battle.field.squads.get(lk)
			if lk == "soldier":
				for q in _battle.field.order:
					if q.tier <= 2 and q.alive:
						lsq = q
						break
			elif lk.begins_with("cid:"):      # --glong=cid:y —— 카드 id 가 y 로 시작하는 첫 부대 (토벌 잡병)
				for q in _battle.field.order:
					if str(q.cid).begins_with(lk.substr(4)) and q.alive:
						lsq = q
						break
			if lsq == null:
				print("glong: 부대 %s 없음" % lk)
			else:
				var off := Vector2.ZERO
				if a.has("glongat"):
					var oc: PackedStringArray = str(a.glongat).split(",")
					off = Vector2(float(oc[0]), float(oc[1]))
				var lp: Vector2 = _battle.field.to_screen(lsq.pos, 0.0) + (_battle.hud._tok_off.get(lsq.key, Vector2.ZERO) as Vector2) + off
				var lg: Vector2 = _battle.stage.get_global_rect().position + lp
				var lxf := get_tree().root.get_final_transform()
				var lm := InputEventMouseButton.new()
				lm.button_index = MOUSE_BUTTON_LEFT
				lm.pressed = true
				lm.position = lxf * lg
				lm.global_position = lm.position
				Input.parse_input_event(lm)
				await get_tree().create_timer(0.8).timeout
				var lu := InputEventMouseButton.new()
				lu.button_index = MOUSE_BUTTON_LEFT
				lu.pressed = false
				lu.position = lm.position
				lu.global_position = lm.position
				Input.parse_input_event(lu)
				print("glong: %s(%s · %s) 메달 %s 눌렀다 · 시트 %s" % [lsq.key, lsq.row.name, lsq.camp, str(lp), _sheet.visible])
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
	if a.has("gnotify"):      # 점검용 —— 긴급 등용 띠를 오프라인으로 (--gnotify=카드id,카드id… --gnwho=유저이름,… 쉼표로 여럿이면 대기열, 11/10)
		var nws := str(a.get("gnwho", "관우팬")).split(",")
		var ni := 0
		for nk in str(a.gnotify).split(","):
			urgent(nws[ni % nws.size()], nk)
			ni += 1
	if a.has("gtouch"):
		await _touch_test()
		get_tree().quit()
		return
	if a.has("gswipeclose"):
		await _swipe_close_test()
		get_tree().quit()
		return
	if a.has("gshot"):
		await get_tree().create_timer(float(a.get("after", "1.0"))).timeout
		if a.has("gquiet"):      # 점검용 —— 찍기 전에 시트 · 띠 · 알림을 걷는다 (tests/ui_shots 처럼, 11/7)
			close_sheet()
			_bands.clear()
			_hide_band()
			for c in _toast_box.get_children():
				c.queue_free()
			await get_tree().create_timer(0.4).timeout
		if a.has("gnoband"):      # 점검용 —— 시트는 둔 채 가운데 띠 · 알림만 걷는다 (--gsheet 와 함께, 11/9)
			_bands.clear()
			_hide_band()
			for c in _toast_box.get_children():
				c.queue_free()
			await get_tree().create_timer(0.5).timeout
		if a.has("scroll"):
			_scroll.scroll_vertical = int(a.scroll)
			await get_tree().process_frame
		if a.has("ghand") and is_instance_valid(_hand_scroll):      # 점검용 —— 징집 보유 목록을 이 위치까지 내린다 (큰 수면 맨 아래, 11/7)
			_hand_scroll.scroll_vertical = int(a.ghand)
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


func _tiles_of(root: Node, k: String, out: Array) -> void:
	for c in root.get_children():
		if c is MiniTile and c.k == k and c.is_inside_tree():
			out.append(c)
		_tiles_of(c, k, out)


func _pin_report(tag: String, root_k: String, m: String) -> void:
	var sheet_t := []
	_tiles_of(_sheet_body, m, sheet_t)
	var all_t := []
	_tiles_of(self, m, all_t)
	var page_t := all_t.filter(func(x): return not _sheet_body.is_ancestor_of(x))
	var nd := forge_tree._node(root_k, 1, 0, root_k, "", true)
	var kid_have := -1
	for c in nd.kids:
		if c.get("k", "") == m:
			kid_have = int(c.have)
	print("PINTEST %s | 보유 %d | 선택권 타일 %s | 화면 보유 타일 %s | 갈무리 트리 재료 보유 %d · 조합 가능 %s" % [tag, run.have(m),
		str(sheet_t.map(func(x): return "%d/%s" % [x.qty, x.badge])), str(page_t.map(func(x): return x.qty)), kid_have, str(run.can_forge(root_k))])


func _pin_pick_test(root_k: String) -> void:
	if root_k == "auto":      # 재료에 희귀(선택권으로 뽑을 수 있는) 장수가 든 전설 하나
		for rk in DB.RECOF:
			if DB.C[rk].tier == 5 and DB.RECOF[rk].any(func(q): return DB.C[str(q)].tier == 4 and Run.pickable(4).has(str(q))):
				root_k = rk
				break
	if not forge_tree.pinned(root_k):
		forge_tree.toggle(root_k)
	var m := ""
	for q in DB.RECOF.get(root_k, []):
		var tq: int = DB.C[str(q)].tier
		if tq <= 4 and Run.pickable(tq).has(str(q)):
			m = str(q)
			break
	if m == "":
		print("PINTEST 재료 중 선택권으로 뽑을 수 있는 것이 없다: ", DB.RECOF.get(root_k, []))
		return
	var t: int = DB.C[m].tier
	print("PINTEST 갈무리 %s(%s) · 재료 %s(%s, %s 선택권) · 재료 목록 %s" % [DB.C[root_k].name, root_k, DB.C[m].name, m, DB.TIER[t].n, str(DB.RECOF[root_k])])
	go("draw")
	run.tickets[str(t)] = 2
	picker(t)
	await get_tree().process_frame
	_pin_report("뽑기 전", root_k, m)
	var ts := []
	_tiles_of(_sheet_body, m, ts)
	if ts.is_empty():
		print("PINTEST 선택권 창에서 재료 타일을 못 찾았다")
		return
	ts[0].tapped.emit(m)      # 실제 탭과 같은 길 (on_pick)
	await get_tree().process_frame
	await get_tree().process_frame
	_pin_report("뽑은 뒤", root_k, m)


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


## 팝업 쓸어 닫기 점검 (--gswipeclose) —— 11/11 사용자: 모든 팝업은 왼쪽에서 오른쪽으로 쓸면 닫힌다
## 시트: 이전 시트가 없으면 닫힘 · 있으면 이전 시트로 · 왼쪽으로 쓸면 그대로 · 슬라이더 위에서 시작하면 닫히지 않음
func _swipe_close_test() -> void:
	var ok := true
	await get_tree().create_timer(0.5).timeout
	var kk: String = DB.C.keys().filter(func(x): return DB.C[x].tier >= 6 and DB.C[x].kind != "retired")[0]
	card_info(kk)
	await get_tree().create_timer(0.5).timeout
	var opened := _sheet.visible
	var sp := _sheet.get_global_rect().position + Vector2(_sheet.size.x * 0.25, _sheet.size.y * 0.5)
	await _swipe(sp, Vector2(-220, 8))
	await get_tree().create_timer(0.4).timeout
	print("⑧a 왼쪽으로 쓸기: 시트 그대로 %s" % _sheet.visible)
	ok = ok and opened and _sheet.visible
	await _swipe(sp, Vector2(220, 8))
	await get_tree().create_timer(0.5).timeout
	print("⑧b 오른쪽으로 쓸기: 닫힘 %s" % (not _sheet.visible))
	ok = ok and not _sheet.visible
	print("쓸어 닫기 점검 %s" % ("통과" if ok else "실패"))


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
	var n := 21           # 칸 수 —— 혼자 하기 21(7일 × 3), 온라인은 하루 네 단계 4 (11/9)
	var group := 3        # 이만큼마다 넓은 틈 (하루)

	func _draw() -> void:
		var gap := 1.5      # 11/7 머리띠 축소 —— 막대가 왼쪽 칸 폭(≈180)만 쓰니 틈을 줄인다 (2 · 6 → 1.5 · 4)
		var dgap := 4.0
		var ngroups := maxi(1, n / maxi(1, group))
		var w := (size.x - gap * (n - 1) - (dgap - gap) * (ngroups - 1)) / n
		var x := 0.0
		for i in n:
			var col: Color = DB.PAL.gold if i == cur else (DB.PAL.bamboo_dim if i < cur else DB.PAL.ink3)
			var r := Rect2(x, 0, w, size.y)
			draw_rect(r, col)
			x += w + (dgap if i % group == group - 1 else gap)


## 머리띠 민심 게이지 (11/10) —— 하트 · "민심" · 숫자 + 가는 막대. 평소 종이색 + 금 한 가지, 30 이하만 인장 붉음(맥동은 약하게),
## 60 안팎은 변화 없음. 줄어들 때만 한 번 붉게 번쩍이고 잃은 몫이 붉은 꼬리로 줄어든다. 누르면 tapped (한 줄 설명)
class HpGauge extends Control:
	signal tapped
	const LOW := 30.0
	const DANGER := 15.0     # 11/10 이 이하는 「위험」 이 더 짙고 빠르게
	var value := 100.0       # 보이는 값 (줄어드는 중이면 중간 값)
	var trail := 100.0       # 잃은 몫을 보이는 꼬리 (value 이상)
	var flash := 0.0
	var _t := 0.0
	var _from := 100.0
	var _to := 100.0
	var _tw: Tween
	var _press := Vector2.INF

	func _init() -> void:
		custom_minimum_size = Vector2(92, 24)
		mouse_filter = Control.MOUSE_FILTER_STOP

	func _process(dt: float) -> void:
		_t += dt
		if value <= LOW:
			queue_redraw()      # 낮을 때만 천천히 맥동

	func _gui_input(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
			if e.pressed:
				_press = e.position
			else:
				if _press != Vector2.INF and Rect2(Vector2.ZERO, size).has_point(e.position):
					tapped.emit()
				_press = Vector2.INF

	## 위험일 때 「위험」 글자 자리 —— 숫자와 겹치지 않게 조금 넓힌다 (온라인은 병력 줄이 없어 칸이 좁다)
	func _fit(target: float) -> void:
		custom_minimum_size = Vector2(112.0 if target <= LOW else 92.0, 24)

	func set_now(v: float) -> void:
		_fit(v)
		if _tw != null:
			_tw.kill()
		value = v
		trail = v
		flash = 0.0
		queue_redraw()

	func drop_to(v: float) -> void:
		_fit(v)
		if _tw != null:
			_tw.kill()
		_from = value
		_to = v
		trail = value
		flash = 1.0
		_tw = create_tween()
		_tw.tween_method(_step, 0.0, 1.0, 1.4)

	func _step(u: float) -> void:
		flash = pow(1.0 - clampf(u / 0.75, 0.0, 1.0), 1.5)
		value = lerpf(_from, _to, ease(clampf((u - 0.1) / 0.5, 0.0, 1.0), 0.4))
		trail = lerpf(_from, _to, clampf((u - 0.35) / 0.55, 0.0, 1.0))
		if u >= 1.0:
			value = _to
			trail = _to
			flash = 0.0
		queue_redraw()

	func _draw() -> void:
		var P := DB.PAL
		var v := clampf(value, 0.0, 100.0)
		var low := v <= LOW
		var hot: Color = P.seal.lightened(0.3)
		var txt: Color = (hot if low else P.paper).lerp(hot, flash)
		var bar: Color = (P.seal if low else P.gold).lerp(hot, flash)
		if low:
			var pulse := 0.84 + 0.16 * sin(_t * TAU / 2.8)
			txt.a = pulse
			bar.a = pulse
		Icons.draw(self, "heart", Vector2(8, 9), 15, txt)
		draw_string(DB.font_bold, Vector2(19, 13), "민심", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, P.bamboo_dim.lerp(hot, flash * 0.8))
		draw_string(DB.font_bold, Vector2(0, 14), str(int(round(v))), HORIZONTAL_ALIGNMENT_RIGHT, size.x, 15, txt)
		if low:      # 11/10 사용자: 민심이 얼마 안 남았으면 계속 위험하다고 알린다 —— 「위험」 인장 붉음. 15 이하는 더 짙고(바탕 알) 빠르게(1초)
			var crit := v <= DANGER
			var wp := 0.5 + 0.5 * sin(_t * TAU / (1.0 if crit else 2.0))
			var wa := lerpf(0.75, 1.0, wp) if crit else lerpf(0.55, 0.95, wp)
			var wx := 47.0
			if crit:
				var pill := StyleBoxFlat.new()
				pill.bg_color = Color(P.seal.darkened(0.45), lerpf(0.55, 0.85, wp))
				pill.border_color = Color(hot, wa)
				pill.set_border_width_all(1)
				pill.set_corner_radius_all(3)
				draw_style_box(pill, Rect2(wx - 4, 1, 30, 15))
			draw_string(DB.font_bold, Vector2(wx, 13), "위험", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(hot.lightened(0.15) if crit else hot, wa))
		var by := size.y - 4.0
		draw_rect(Rect2(0, by, size.x, 3), P.ink3)
		if trail > v:
			draw_rect(Rect2(size.x * v / 100.0, by, size.x * (trail - v) / 100.0, 3), Color(hot, 0.9))
		draw_rect(Rect2(0, by, size.x * v / 100.0, 3), bar)


## 결과 화면의 민심 줄 (11/10) —— 「민심 −N」 도장이 쾅(확대 → 제자리 + 작은 흔들림), 막대와 숫자가 이전 값에서 줄어든다. 입력은 막지 않는다
class HpLossFx extends Control:
	const DUR := 1.6
	var prev := 100
	var loss := 0
	var now := 0
	var _t := 0.0
	var _slam := false

	func setup(p: int, l: int) -> void:
		prev = p
		loss = l
		now = maxi(0, p - l)
		custom_minimum_size = Vector2(0, 46)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _process(dt: float) -> void:
		_t += dt
		if _t >= 0.14 and not _slam:
			_slam = true
			Sfx.play("deny")
		queue_redraw()
		if _t > DUR + 0.2:
			set_process(false)

	func _draw() -> void:
		var P := DB.PAL
		var hot: Color = P.seal.lightened(0.3)
		var a := clampf(_t / 0.12, 0.0, 1.0)
		var w := size.x
		var h := size.y
		draw_rect(Rect2(0, 0, w, h), Color(0.058, 0.078, 0.14, 0.94 * a))
		var hit := clampf((_t - 0.14) / 0.2, 0.0, 1.0)
		if hit > 0.0 and hit < 1.0:
			draw_rect(Rect2(0, 0, w, h), Color(P.seal, 0.3 * (1.0 - hit)))      # 찍히는 순간 한 번 붉게
		var u := clampf((_t - 0.3) / 1.0, 0.0, 1.0)
		var e := ease(u, 0.4)
		var cur := lerpf(float(prev), float(now), e)
		var tr := lerpf(float(prev), float(now), clampf((_t - 0.7) / 0.8, 0.0, 1.0))
		var txt: Color = P.paper.lerp(hot, e)
		Icons.draw(self, "heart", Vector2(24, h / 2), 18, Color(txt, a))
		draw_string(DB.font_bold, Vector2(40, h / 2 + 5), "민심", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(P.bamboo, a))
		var bx := 80.0
		var bw := w - bx - 132.0
		var by := h / 2 - 4.0
		draw_rect(Rect2(bx, by, bw, 8), Color(P.ink3, a))
		if tr > cur:
			draw_rect(Rect2(bx + bw * cur / 100.0, by, bw * (tr - cur) / 100.0, 8), Color(hot, 0.9 * a))
		var fill: Color = P.gold.lerp(P.seal, e) if now <= 30 else P.gold
		draw_rect(Rect2(bx, by, bw * cur / 100.0, 8), Color(fill, a))
		draw_string(DB.font_bold, Vector2(bx + bw + 6, h / 2 + 7), str(int(round(cur))), HORIZONTAL_ALIGNMENT_RIGHT, 38, 20, Color(txt, a))
		# 도장 —— 오른쪽 끝, 쾅 찍히고 잠깐 흔들린다
		var s := clampf(_t / 0.14, 0.0, 1.0)
		var sc := lerpf(2.6, 1.0, ease(s, 0.4))
		var st := _t - 0.14
		var shake := Vector2.ZERO
		if st > 0.0 and st < 0.32:
			var k := 1.0 - st / 0.32
			shake = Vector2(sin(st * 95.0) * 5.0, cos(st * 70.0) * 3.0) * k
		var c := Vector2(w - 12.0 - 34.0, h / 2) + shake
		draw_set_transform(c, deg_to_rad(-5.0), Vector2.ONE * sc)
		var box := Rect2(Vector2(-34, -16), Vector2(68, 32))
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(P.seal.darkened(0.55), 0.55 * s)
		sb.border_color = Color(hot, s)
		sb.set_border_width_all(2)
		sb.set_corner_radius_all(UI.R)
		draw_style_box(sb, box)
		draw_string(DB.font_bold, Vector2(-34, 8), "−%d" % loss, HORIZONTAL_ALIGNMENT_CENTER, 68, 22, Color(hot, s))
		draw_set_transform(Vector2.ZERO)


## 결과 화면의 토벌 성과 보너스 줄 (11/10) —— 금색 한 줄: 왼쪽 「토벌 대승!」(송명) · 오른쪽 「기본패 +M · 선택권 +1」. 금빛이 한 번 쓸고 지나간다(약 0.8초). 입력은 막지 않는다
class BonusFx extends Control:
	const DUR := 1.3
	var base := 0
	var ticket := 0
	var big := true
	var what := "토벌"      # 11/11 온라인 4일차~ 는 대전이 토벌 보상을 대신 준다 → "대전"
	var _t := 0.0
	var _chime := false

	func setup(b: int, t: int, is_big: bool, w := "토벌") -> void:
		base = b
		ticket = t
		big = is_big
		what = w
		custom_minimum_size = Vector2(0, 46)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _process(dt: float) -> void:
		_t += dt
		if _t >= 0.12 and not _chime:
			_chime = true
			Sfx.play("gain")
		queue_redraw()
		if _t > DUR + 0.2:
			set_process(false)

	func _draw() -> void:
		var P := DB.PAL
		var a := clampf(_t / 0.14, 0.0, 1.0)
		var w := size.x
		var h := size.y
		draw_rect(Rect2(0, 0, w, h), Color(0.058, 0.078, 0.14, 0.94 * a))
		draw_rect(Rect2(0, 0, w, 1), Color(P.gold, 0.8 * a))
		draw_rect(Rect2(0, h - 1, w, 1), Color(P.gold, 0.8 * a))
		var head := (what + " 대승!") if big else (what + " 선전!")
		var f: Font = DB.title_font(20)
		draw_string(f, Vector2(16, h / 2 + 8), head, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(P.gold.lightened(0.2), a))
		var parts := []
		if base > 0:
			parts.append("기본패 +%d" % base)
		if ticket > 0:
			parts.append("%s 선택권 +%d" % [DB.TIER[Run.QUEST_BONUS_TICKET_TIER].n, ticket])
		draw_string(DB.font_bold, Vector2(0, h / 2 + 6), "  ·  ".join(parts), HORIZONTAL_ALIGNMENT_RIGHT, w - 16.0, 16, Color(P.paper, a))
		# 금빛이 한 번 쓸고 지나간다 (왼쪽 → 오른쪽, 기운 띠)
		var u := clampf((_t - 0.1) / 0.8, 0.0, 1.0)
		if u > 0.0 and u < 1.0:
			var x := lerpf(-60.0, w + 20.0, ease(u, -1.6))
			var al := 0.30 * sin(u * PI)
			var pts := PackedVector2Array([Vector2(x, 0), Vector2(x + 34, 0), Vector2(x + 14, h), Vector2(x - 20, h)])
			draw_colored_polygon(pts, Color(P.gold.lightened(0.35), al))


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
		draw_string(DB.title_font(13) if on else DB.font_body, Vector2(0, size.y - 8), text, HORIZONTAL_ALIGNMENT_CENTER, size.x, 13, DB.PAL.paper if on else col)
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
