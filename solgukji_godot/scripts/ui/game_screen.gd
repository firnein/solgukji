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
const SkillPanel := preload("res://scripts/ui/skill_panel.gd")
const MinorTriggers := preload("res://scripts/minor_trig.gd")
const UrgentBand := preload("res://scripts/ui/urgent_band.gd")      # 11/10 기인 이상 등용 '긴급' 띠 (class_name 없이)
const DeathBand := preload("res://scripts/ui/death_band.gd")      # 11/12 장수 사망룰 연출 (class_name 없이)
const Ending := preload("res://scripts/ui/ending.gd")      # 11/12 멸망 · 엔딩 연출 + 요약 (class_name 없이) —— show_ending
const SayBubble := preload("res://scripts/ui/say_bubble.gd")      # 11/12 받은 한마디(글 · 이모티콘) 구름 말풍선 (class_name 없이) —— 11/10 EmotePop 을 대신한다
const TacUI := preload("res://scripts/ui/tac_ui.gd")      # 11/15 군략 카드 화면 부품 (class_name 없이)
const BattleUnitCard := preload("res://scripts/ui/battle_unit_card.gd")      # 11/21 전투장수창 본문 (class_name 없이)
const CHANGELOG := preload("res://scripts/game/changelog.gd")   # 11/7 버전 · 업데이트 내역 (class_name 캐시와 무관하게 바로 쓰려고 preload)
## 11/9 첫 판 안내 —— 첫 유저가 조합 방법을 못 찾고 1성 9장으로 전멸했다. 4장, 건너뛰기 가능
const COACH_STEPS := [
	["draw", "1/4  징집", "기본패를 받았다 —— 준비 단계가 열릴 때마다 저절로 들어온다. 맨 윗줄의 같은 패를 모아 조합해 장수로 올린다."],      # 11/25 자동 징집: 누를 버튼 대신 맨 위 기본패 줄(_base_row)을 가리킨다
	["forge", "2/4  조합  —  꼭 알아 둘 것", "같은 장수 · 같은 카드를 모아 조합 탭에서 한 등급 위로 올린다. 1성 9장 그대로는 토벌에서 전멸한다."],
	["deploy", "3/4  편성", "가진 장수를 9칸에 배치한다. 앞줄과 뒷줄 자리를 살피자."],
	["war", "4/4  전투", "출진하면 자동으로 싸운다(조작 없음). 지면 민심이 깎이고, 0 이 되면 멸망한다. 출진 전에 조합부터."],
]
const TABS := [["draw", "징집"], ["forge", "조합"], ["deploy", "편성"], ["war", "전투"], ["more", "기록"]]
const STAT_ICON := 22.0       # 능력치 아이콘(칼 · 방패 · 신발) 크기 —— 14 아래로는 선이 뭉개진다 (11/9)
const MAX_W := 640.0         # PC 에서 창을 넓혀도 글줄은 이 폭까지만
const TOP_H := 68.0          # 11/7 사용자: DAY 네비게이터 축소 (66 → 58). 11/20 상수를 실제 높이에 맞춘다 —— 오른쪽 칸 세 줄(군량 19 + 민심 24 + 플레이타임 17) + 여백 8 = 68, 58 은 한 번도 지켜진 적이 없었다
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
var _grain_box: HBoxContainer      # 11/13 사용자: 머리띠 민심 위 「N명」(편성 병력 합) 자리에 [쌀가마] [군량]
var _grain_lbl: Label
var _grain_shown := -1             # 마지막으로 보인 군량 —— 바뀌면 숫자가 살짝 튄다
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
var _sheet_temper: Label
var _sheet_scroll: ScrollContainer
var _card_tab_bar: MarginContainer
var _sheet_wash: Control           # 11/21 장수창 머리 바탕 (SheetStyle.head_wash) —— sheet_head 가 켠다, open_sheet 가 끈다
var _sheet_meta: MarginContainer  # 11/21 장수창 이름 아래 한 줄 (등급 · 세력 · 병종) 자리
var _card_tabs: HBoxContainer
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
var _swipe_on := false        # 11/20 조작: 이 누름은 쓸기로 판정됐다 (밑의 버튼 누름은 이미 취소했다)
var _sheet_closing := false   # 11/20 조작: 시트가 닫히며 내려가는 중 (0.2초) —— 그 사이 시트의 버튼은 눌리지 않는다
var _sheet_dy := 0.0
var _toast_box: VBoxContainer
var _battle_layer: Control
var _tk_btn: Button = null        # 11/15 머리띠 「군략 3택1」 —— 고를 것이 있을 때만
var _tk_auto := -1                # 3택1 시트를 저절로 연 날 (하루에 한 번)
var _battle: BattleView
var _battle_done: Button
var _report: BattleReport    # 전투 결과표 (끝나고 잠시 뒤 뜬다)
var _report_scrim: ColorRect      # 결과표 뒤 깔개 (11/14)
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
	_toast_box = UI.vbox(UI.SP_S)
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
var _play_sec := 0.0          # 11/11 사용자: 현재 판 플레이 시간 —— 판이 바뀌면 0, 끝나면 멈춘다
var _play_id := ""            # 11/12 판의 이름표(game_id) —— Run 객체로 가리면 온라인은 상태를 받을 때마다 새 Run 이라 0 으로 돌아갔다
var _play_save_t := 0.0       # 몇 초마다 기기에 적는다 (PLAY_PATH)
const PLAY_PATH := "user://play_time.json"      # {판 id: 초} —— 끄고 다시 켜도 이어 센다 (최근 몇 판만)
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
	var near_: Array = _forge_goals(DB.D.RECDEF)
	first.append_array(near_)
	var near_p := {}
	for o in near_:
		near_p[DB.person(o)] = true
	first.append_array(run.bond_goals(near_p, 4))
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
## 11/16 초대 글(서버 주소 + 방 코드)을 복사한 채 게임이 앞으로 오면 온라인 시트를 저절로 연다 —— 맨 위 「초대 받은 방으로 입장」 한 번이면 들어간다.
## 제목 화면에서만 · 같은 글로는 한 번만 (하던 판을 끊지 않는다)
func _check_invite() -> void:
	if _title == null or not is_instance_valid(_title) or not _title.visible or _sheet == null or _sheet.visible:
		return
	if online != null and (online.in_game or not online.room.is_empty()):
		return
	var t := DisplayServer.clipboard_get()
	if t == "" or t == Online.invite_seen or Online.parse_invite(t).is_empty():
		return
	Online.invite_seen = t
	_go_online()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_IN or what == NOTIFICATION_WM_WINDOW_FOCUS_IN:
		_check_invite.call_deferred()
	match what:
		NOTIFICATION_WM_GO_BACK_REQUEST:
			back.call_deferred()      # 알림이 도는 동안에는 자식을 붙이거나 옮길 수 없다 (타이틀 다시 만들기 · 시트를 앞으로)
		NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_WM_CLOSE_REQUEST, NOTIFICATION_APPLICATION_FOCUS_OUT:
			if run != null and online == null:
				run.save()


## 11/20 조작: 뒤로 한 단계 —— Android 뒤로와 Esc 가 같이 부른다. 전엔 뒤로 한 번에 온라인 판을 떠나고(자리는 AI 가 받았다) 타이틀에서는 앱이 바로 꺼졌다
## 순서: 연출 덮개 → 시트(이전 카드 시트가 있으면 그리로, 없으면 닫기 —— ‹ · 쓸기와 같게) → 전투(결과표면 '종료', 아니면 메뉴) →
## 온라인(대기실 · 판)은 나가기 확인 → 혼자 하기는 저장하고 처음 화면 → 타이틀은 2초 안에 두 번 눌러야 종료 (Esc 는 타이틀에서 아무것도 안 한다)
var _back_t := -99999          # 타이틀에서 마지막으로 뒤로를 누른 시각 (ms)
func back(from_key := false) -> void:
	if _sheet == null or _title == null:
		return
	if is_instance_valid(_ending):
		return      # 엔딩 요약은 제 버튼(처음으로 · 다시)으로만 닫는다
	if _death_busy and not _death_idle:
		_death_tap()      # 사망 연출 —— 화면을 누른 것과 같게 (빨리 감기 → 넘기기)
		return
	if _sheet.visible:
		if _sheet_closing:
			return
		if _hist.is_empty():
			close_sheet()
		else:
			go_back()
		return
	if _battle_layer != null and _battle_layer.visible:
		if _battle_done.visible:
			_on_battle_close()      # 결과표가 떠 있으면 [종료 · 다음 전투]와 같다
		else:
			_battle.toggle_menu()      # 전투 중에는 메뉴(자동 전투·결과로)를 연다
		return
	if online != null and (online.in_game or not online.room.is_empty()):
		_confirm_leave()
		return
	if is_instance_valid(_title) and not _title.visible:
		if run != null:
			run.save()
		_title.queue_free()
		_build_title()
		return
	if from_key:
		return
	var now := Time.get_ticks_msec()
	if now - _back_t < 2000:
		get_tree().quit()
		return
	_back_t = now
	move_child(_toast_box, -1)      # 타이틀이 알림 상자를 덮고 있다
	toast("한 번 더 누르면 종료합니다")


## 11/20 조작: 온라인 방 나가기 확인 —— 뒤로 한 번에 떠나지 않게. [계속하기] 왼쪽 · [나가기] 오른쪽 (위험 붉음)
func _confirm_leave() -> void:
	var b := open_sheet("온라인 방에서 나갈까요?")
	var d := UI.lbl("나가면 내 자리는 AI 가 이어받습니다." if online.in_game else "대기실에서 나가 방 목록으로 돌아갑니다.", UI.FS_BODY, DB.PAL.text_dim)
	UI.wrap_text(d)
	b.add_child(d)
	var row := UI.hbox(UI.SP_S)
	var no := UI.btn_ghost("계속하기", close_sheet)
	no.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(no)
	var ok := UI.btn("나가기", func():
		if online == null:
			close_sheet()
		elif online.in_game:
			_leave_from_battle()
		else:
			online.leave_room(), "warn")
	ok.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(ok)
	b.add_child(row)


func _unhandled_key_input(e: InputEvent) -> void:
	if not (e is InputEventKey) or not e.pressed or e.echo:
		return
	if e.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		back(true)
		return
	var ti := _tab_key(e)      # 11/25 사용자: 키보드 단축키 —— 1 · 2 · 3 · 4 로 아래 탭(징집 · 조합 · 편성 · 전투), 5 는 기록
	if ti >= 0 and tab_keys_ok():
		get_viewport().set_input_as_handled()
		_tab_press(TABS[ti][0])


## 숫자 키(윗줄 · 숫자패드) → 탭 번호. 조합 키(Ctrl · Alt · Meta)와 함께면 아니다
func _tab_key(e: InputEventKey) -> int:
	if e.ctrl_pressed or e.alt_pressed or e.meta_pressed:
		return -1
	var kc: int = e.keycode
	var i := -1
	if kc >= KEY_1 and kc <= KEY_9:
		i = kc - KEY_1
	elif kc >= KEY_KP_1 and kc <= KEY_KP_9:
		i = kc - KEY_KP_1
	return i if i < TABS.size() else -1


## 탭 단축키를 받아도 되는가 —— 아래 탭이 보이고 눌리는 때만 (타이틀 · 시트 · 전투 · 엔딩 · 사망 연출 · 완성 연출 위에서는 아니다.
## 전투 중 1 · 2 · 3 은 배속 —— BattleView._unhandled_input 이 받는다. 글 입력 칸은 키를 먼저 먹어 여기까지 오지 않는다)
func tab_keys_ok() -> bool:
	if run == null or _sheet == null or _tabbar == null or not _tabbar.is_visible_in_tree():
		return false
	if _sheet.visible or (is_instance_valid(_title) and _title.visible):
		return false
	if _battle_layer != null and _battle_layer.visible:
		return false
	return not is_instance_valid(_ending) and not _death_busy and not is_instance_valid(_fanfare)


## 아래 탭 하나를 누른 것 (탭 · 단축키 공통)
func _tab_press(k: String) -> void:
	UI.buzz()
	if k == "more":
		go("rank" if page in ["line", "rank", "update"] else _open.get("more_page", "rank"))
	elif k == page:
		_scroll_to_top()
	else:
		go(k)


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
	var row := UI.hbox(UI.SP_S)
	bar.add_child(row)
	# 11/7 사용자: DAY 네비게이터 축소 —— 날짜 · 페이즈를 작은 글씨 한 줄에, 21칸 진행 막대는 그 아래 왼쪽 칸 폭만큼 가늘게(4)
	var lv := UI.vbox(3)
	lv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lv.alignment = BoxContainer.ALIGNMENT_CENTER
	var dl := UI.hbox(UI.SP_S)
	_day_lbl = UI.lbl("", UI.FS_BODY, DB.PAL.paper, true)
	_sub_lbl = UI.lbl("", UI.FS_CAP, DB.PAL.bamboo)
	_sub_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_sub_lbl.clip_text = true
	_sub_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_sub_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_sub_lbl.size_flags_vertical = Control.SIZE_FILL
	dl.add_child(_day_lbl)
	dl.add_child(_sub_lbl)
	_tk_btn = TacUI.head_btn(self)
	dl.add_child(_tk_btn)
	lv.add_child(dl)
	var bl := UI.hbox(UI.SP_S)
	_phase_bar = PhaseBar.new()
	_phase_bar.custom_minimum_size = Vector2(60, 4)
	_phase_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_phase_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bl.add_child(_phase_bar)
	_clock_lbl = UI.lbl("", UI.FS_CAP, DB.PAL.bamboo)      # 온라인 단계 시계 —— 막대 오른쪽 (혼자 하기에선 숨김)
	_clock_lbl.visible = false
	bl.add_child(_clock_lbl)
	lv.add_child(bl)
	row.add_child(lv)
	var rv := UI.vbox(0)
	rv.alignment = BoxContainer.ALIGNMENT_CENTER
	_grain_box = UI.grain("0", UI.FS_BODY, DB.PAL.gold)
	_grain_box.alignment = BoxContainer.ALIGNMENT_END
	_grain_box.mouse_filter = Control.MOUSE_FILTER_STOP
	UI.tap(_grain_box, func():      # 11/20 조작: 누르는 순간이 아니라 탭으로 뗐을 때 (UI.tap)
		if run != null and shop_on():
			_shop_sheet())
	_grain_lbl = _grain_box.get_child(1)
	rv.add_child(_grain_box)
	_hp_gauge = HpGauge.new()      # 11/10 사용자: 민심(체력)이 어디에도 안 보인다 —— 모든 탭의 머리띠 오른쪽에 늘 보인다
	_hp_gauge.tapped.connect(func(): toast("민심은 체력 —— 패배마다 깎이고, 0 이 되면 멸망한다"))
	rv.add_child(_hp_gauge)
	# 11/11 사용자: 현재 플레이타임 —— 11/12 사용자: 민심 바로 아래에 작게 ("플레이타임 0:04", 머리띠 가운데에서 옮김)
	_play_lbl = UI.lbl(play_text(), UI.FS_CAP, DB.PAL.text_dim)
	_play_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_play_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rv.add_child(_play_lbl)
	_info_lbl = UI.rich("", UI.FS_CAP)
	_info_lbl.autowrap_mode = TextServer.AUTOWRAP_OFF
	_info_lbl.custom_minimum_size = Vector2(140, 0)
	rv.add_child(_info_lbl)
	row.add_child(rv)
	# ☰ 과 그 아래 '소식' (11/7 사용자: 징집 페이지 칩 줄에서 머리띠로) —— 소식 수 뱃지, 누르면 전황 소식 시트
	var mv := UI.vbox(2)
	# 11/14 감사 #6 —— 보이는 크기는 그대로(머리띠가 낮다), 누르는 범위는 48 × 48: ☰ 은 위로, 소식은 아래로만 넓혀 서로 겹치지 않게
	var mb := UI.icon_btn("☰", _menu, Vector2(46, 26))
	mb.hit_dir = -1
	mv.add_child(mb)
	_news_btn = UI.btn("소식", _news_sheet, "ghost", 22)
	_news_btn.hit_dir = 1
	_news_btn.custom_minimum_size = Vector2(46, 22)
	_news_btn.add_theme_font_size_override("font_size", UI.FS_CAP)
	# 11/20 UI 다듬기: 올림 · 눌림이 평소와 같은 모양이라 PC 에서 눌리는지 알 수 없었다 —— 여백은 그대로(2), 선만 밝힌다
	var nz := Color(0, 0, 0, 0)
	UI.btn_styles(_news_btn, UI.flat(nz, DB.PAL.ink4, 1, 6, 2), UI.flat(Color(DB.PAL.paper, 0.06), DB.PAL.bamboo_dim, 1, 6, 2),
		UI.flat(Color(DB.PAL.paper, 0.12), DB.PAL.bamboo_dim, 1, 6, 2), UI.flat(nz, Color(DB.PAL.ink4, 0.5), 1, 6, 2))
	_news_btn.add_theme_color_override("font_color", DB.PAL.bamboo)
	_news_btn.add_theme_color_override("font_pressed_color", DB.PAL.paper)
	_news_badge = UI.lbl("", UI.FS_TINY, Color("#1A1508"), true)
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
		tb.tapped.connect(_tab_press)
		tb.hint = str(_tabs.size() + 1) if OS.has_feature("pc") else ""      # PC 는 단축키 숫자를 귀퉁이에 작게
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
	UI.tap(_sheet_mask, close_sheet)      # 11/20 조작: 누르는 순간이 아니라 탭으로 뗐을 때 닫는다 (UI.tap)
	TouchScroll.block(_sheet_mask)
	add_child(_sheet_mask)
	# 11/3 사용자: 장수정보간략창(조합 시트) 위의 빈 공간에 신화 그림 —— 어두운 막 위, 시트 아래. 누르면 막처럼 닫힌다
	_sheet = PanelContainer.new()
	var sb := UI.flat(DB.PAL.ink2, DB.PAL.bamboo_dim, 0, 0, 0)
	sb.corner_radius_top_left = UI.R_SHEET
	sb.corner_radius_top_right = UI.R_SHEET
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
	_sheet_wash = Control.new()      # 11/21 자리만 —— sheet_head 가 등급 색 바탕으로 바꿔 끼운다
	_sheet_wash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sheet_wash.visible = false
	head.add_child(_sheet_wash)
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
	_sheet_meta = MarginContainer.new()      # 11/21 장수창 이름 아래 한 줄 (sheet_head)
	_sheet_meta.add_theme_constant_override("margin_left", 18)
	_sheet_meta.add_theme_constant_override("margin_right", 16)
	_sheet_meta.add_theme_constant_override("margin_bottom", 4)
	_sheet_meta.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sheet_meta.visible = false
	hv.add_child(_sheet_meta)
	_back_btn = UI.btn("‹", go_back, "ghost", UI.BH_S)
	_back_btn.add_theme_font_size_override("font_size", UI.FS_BODY)
	# 11/19 사용자: 뒤로 버튼에 마우스를 올리면 이름이 잘렸다 —— 평소 모양만 여백 6 으로 바꿔 두어, 올렸을 때 · 눌렀을 때는 테마의 넓은 여백이 글자를 밀어냈다
	# 11/20 같은 문제를 한 곳(UI.btn_styles)에서 막는다 —— 모든 상태의 여백을 평소 모양에 맞춘다
	UI.btn_styles(_back_btn, UI.flat(DB.PAL.ink3, DB.PAL.ink4, 1, 8, 6), UI.flat(DB.PAL.ink4, Color(DB.PAL.gold, 0.6), 1, 8, 6), UI.flat(DB.PAL.ink2, Color(DB.PAL.gold, 0.6), 1, 8, 6))
	_back_btn.add_theme_stylebox_override("focus", UI.flat(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, 8, 6))
	_back_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_back_btn.visible = false
	top.add_child(_back_btn)
	_sheet_title = UI.lbl("", UI.FS_TITLE, DB.PAL.paper, true)
	_sheet_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UI.wrap_text(_sheet_title)
	_sheet_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(_sheet_title)
	_sheet_temper = UI.lbl("", UI.FS_CAP, DB.PAL.bamboo)
	_sheet_temper.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_sheet_temper.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_sheet_temper.hide()
	top.add_child(_sheet_temper)
	var x := UI.icon_btn("✕", close_sheet)      # 11/20 올리면 높이가 44 → 48 로 커져 시트 내용이 4 씩 내려앉았다 —— 기호 버튼 공용(여백 0)으로
	x.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(x)
	_card_tab_bar = MarginContainer.new()
	for side in ["left", "right"]:
		_card_tab_bar.add_theme_constant_override("margin_" + side, 16)
	_card_tab_bar.add_theme_constant_override("margin_top", UI.SP_XS)
	_card_tab_bar.add_theme_constant_override("margin_bottom", UI.SP_XS)
	_card_tab_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hv.add_child(_card_tab_bar)
	_card_tabs = UI.hbox(UI.SP_XS)
	_card_tabs.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tab_track := UI.panel(_card_tabs, 0)
	tab_track.add_theme_stylebox_override("panel", SheetStyle.tab_track())      # 11/21 상자 없는 한 줄 탭 —— 아래 가는 선 위에 금 밑줄 (SheetStyle.tab_btn)
	tab_track.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card_tab_bar.add_child(tab_track)
	_card_tab_bar.hide()
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
	_sheet_body = UI.vbox(UI.SP_M)
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
	_sheet_closing = false
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
	# 11/15 성능: 전투 화면(불투명)이 덮는 동안 밑의 머리띠 · 탭 페이지 · 탭 줄은 보이지 않는데도 매 프레임 그려졌다 (그리기 호출 150~200) —— 그동안 숨긴다
	_battle_layer.visibility_changed.connect(func(): _safe.visible = not _battle_layer.visible)
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
	_battle_done = UI.btn("종료", _on_battle_close, "pri", UI.BH_L)      # 11/3 사용자: '결과 정리' → '종료'
	if _battle != null:
		_battle.done_btn = _battle_done      # 11/20 조작: 결과표에서 Enter = 종료 (BattleView 가 이 버튼을 누른다)
	_battle_done.add_theme_font_override("font", DB.title_font(20))
	_battle_done.add_theme_font_size_override("font_size", UI.FS_TITLE)
	_battle_done.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_battle_done.offset_left = -130
	_battle_done.offset_right = 130
	_battle_done.offset_top = 110
	_battle_done.offset_bottom = 110 + UI.BH_L
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
	# 11/14 감사 #6 (01 제목 화면): 아래 절반에 먹빛 그라데이션 깔개 —— 초상 콜라주 위에서도 버튼 · 글자가 읽힌다
	var scrim := TextureRect.new()
	var gt := GradientTexture2D.new()
	gt.fill_from = Vector2(0, 0)
	gt.fill_to = Vector2(0, 1)
	var gr := Gradient.new()
	gr.set_color(0, Color("#0b0f1a", 0.0))
	gr.set_color(1, Color("#0b0f1a", 0.94))
	gr.add_point(0.4, Color("#0b0f1a", 0.78))
	gt.gradient = gr
	gt.width = 4
	gt.height = 64
	scrim.texture = gt
	scrim.stretch_mode = TextureRect.STRETCH_SCALE
	scrim.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scrim.anchor_left = 0
	scrim.anchor_right = 1
	scrim.anchor_top = 0.5
	scrim.anchor_bottom = 1
	_title.add_child(scrim)
	var m := MarginContainer.new()
	m.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var side := maxf(30.0, (size.x - 420.0) / 2.0)
	for s in ["left", "right"]:
		m.add_theme_constant_override("margin_" + s, int(side))
	m.add_theme_constant_override("margin_top", 70)
	m.add_theme_constant_override("margin_bottom", UI.SP_XL + int(_safe_insets().size.y))
	_title.add_child(m)
	var v := UI.vbox(0)
	m.add_child(v)
	# 로고 (11/3 사용자: 한글을 빼고 붓으로 휘갈긴 영문) —— 먹 붓질 띠 위에 금빛 붓글씨 'Solgukji', 오른쪽 위에 붉은 낙관
	var logo := TitleBG.Logo.new()
	logo.custom_minimum_size = Vector2(0, 150)
	v.add_child(logo)
	var ko := UI.lbl("마지막까지 살아남아 천하를 통일하라", UI.FS_LABEL, DB.PAL.bamboo)
	ko.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ko.add_theme_constant_override("outline_size", 5)
	ko.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.75))
	var rg3 := Control.new()
	rg3.custom_minimum_size.y = UI.SP_S
	v.add_child(rg3)
	v.add_child(ko)
	var fill := Control.new()
	fill.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(fill)
	# 버튼 —— 주 버튼 하나(게임 안 주 버튼과 같은 먹금 모양, BH_L) + 보조 버튼(먹빛 바탕 + 얇은 선). 설정 · 버전은 아래 한 줄
	var bv := UI.vbox(UI.SP_M)
	# 11/21 사용자: 이어하기를 「싱글 이어하기」 · 「멀티 이어하기」로 나눠 명시한다 —— 둘 다 늘 보이고, 이을 게 없으면 흐리게 + 이유 한 줄
	var live := Online.live_mark()      # 11/19 끊긴 온라인 대전 —— 그 판으로 바로 돌아간다 (Online.rejoin)
	var has_sv := Run.has_save()
	if _dev_title.has("save"):
		has_sv = bool(_dev_title.save)
	if _dev_title.has("live"):
		live = {"room": "ABCD", "ts": Time.get_unix_time_from_system()} if _dev_title.live else {}
	var sv_sub := "저장된 싱글 판이 없다"
	if has_sv:
		var sr := Run.load_saved()
		sv_sub = "이어 할 수 없는 저장" if sr == null else ("끝난 판 —— 결과 보기" if sr.over != null else sr.when_text())
		if sr == null:
			has_sv = false
	var lv_sub := "진행 중인 온라인 방이 없다"
	if not live.is_empty():
		var ago := int((Time.get_unix_time_from_system() - float(live.get("ts", 0.0))) / 60.0)
		lv_sub = "방 %s · %s" % [str(live.get("room", "")), "방금 전 소식" if ago < 1 else "%d분 전 소식" % ago if ago < 60 else "%d시간 전 소식" % (ago / 60)]
	var live_on := not live.is_empty()
	_title_info = {}
	bv.add_child(_title_btn2("멀티 이어하기", lv_sub, func():
		if online == null:
			online = Online.new()
			online.gs = self
			add_child(online)
		online.rejoin(live), live_on, live_on, "multi"))
	bv.add_child(_title_btn2("싱글 이어하기", sv_sub, _continue, has_sv, has_sv and not live_on, "single"))
	bv.add_child(_title_btn("새 판 시작", _confirm_new if Run.has_save() else _new_game, not has_sv and not live_on))      # 11/14 UI 4단계: 저장된 판이 있으면 확인부터
	bv.add_child(_title_btn("온라인 대전", _go_online, false))
	var low := UI.hbox(UI.SP_S)
	var sb := UI.btn_ghost("설정", _settings_sheet, UI.BH_S)
	# 11/7 버전 · 업데이트 내역 (data/changelog.json)
	var vb := UI.btn_ghost("v%s · 업데이트 내역" % CHANGELOG.version(), _update_sheet, UI.BH_S)
	for x in [sb, vb]:
		x.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		x.add_theme_font_size_override("font_size", UI.FS_BODY)
		x.add_theme_color_override("font_color", DB.PAL.bamboo)
		# 11/20 올리면 ghost 기본(거의 투명)으로 바뀌어 그림 위에서 오히려 글자가 묻혔다 —— 올림 · 눌림도 먹빛 바탕을 지킨다
		UI.btn_styles(x, UI.flat(Color("#0b0f1a", 0.55), UI.HAIR, 1, UI.R, 10), UI.flat(Color(DB.PAL.ink3, 0.8), Color(DB.PAL.paper, 0.28), 1, UI.R, 10),
			UI.flat(Color("#0b0f1a", 0.8), Color(DB.PAL.gold, 0.6), 1, UI.R, 10))
		x.add_theme_color_override("font_hover_color", DB.PAL.paper)
		low.add_child(x)
	var gap := Control.new()
	gap.custom_minimum_size.y = UI.SP_XS
	bv.add_child(gap)
	bv.add_child(low)
	v.add_child(bv)


## 타이틀 버튼 (11/14 감사 #6) —— 주 버튼은 게임 안 주 버튼(UI.btn_primary, 먹금 바탕 + 금 선)과 같은 모양 · 높이 BH_L,
## 나머지는 보조 버튼에 먹빛 반투명 바탕(그림 위에서 읽히게). 글꼴은 제목 글꼴 FS_TITLE
func _title_btn(text: String, cb: Callable, main: bool) -> Button:
	var b := UI.btn_primary(text, cb, UI.BH_L) if main else UI.btn_secondary(text, cb, UI.BH_M)
	if not main:
		# 11/20 눌림만 테마 기본(불투명 남색)이라 누르는 순간 색이 튀었다 —— 같은 먹빛에서 금 선만
		UI.btn_styles(b, UI.flat(Color("#0b0f1a", 0.72), Color(DB.PAL.paper, 0.22), 1, UI.R, 10), UI.flat(Color(DB.PAL.ink3, 0.85), Color(DB.PAL.paper, 0.35), 1, UI.R, 10),
			UI.flat(Color("#0b0f1a", 0.85), Color(DB.PAL.gold, 0.7), 1, UI.R, 10))
	b.add_theme_font_override("font", DB.title_font(UI.FS_TITLE))
	b.add_theme_font_size_override("font_size", UI.FS_TITLE if main else UI.FS_LABEL + 2)
	b.add_theme_color_override("font_color", Color("#f0e6cf"))
	return b


var _dev_title := {}           # 점검용 —— --gtitle=sl : 저장(s) · 대전(l) 있음 (없는 글자는 없음)
var _title_info := {}          # 점검용 —— 이어하기 버튼 상태 {키: [글, 부제, 켜짐]}


## 이어하기 버튼 —— 큰 글 + 부제 한 줄. 이을 게 없으면(on=false) 눌리지 않고 흐리게, 부제가 이유
func _title_btn2(text: String, sub: String, cb: Callable, on: bool, main: bool, key: String) -> Button:
	var b := _title_btn("", cb if on else func(): pass, main and on)
	b.custom_minimum_size.y = maxf(b.custom_minimum_size.y, 64.0)
	b.disabled = not on
	var bx := VBoxContainer.new()
	bx.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bx.alignment = BoxContainer.ALIGNMENT_CENTER
	bx.add_theme_constant_override("separation", 0)
	bx.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var col := Color("#f0e6cf") if on else Color("#f0e6cf", 0.4)
	var l1 := UI.lbl(text, UI.FS_TITLE if (main and on) else UI.FS_LABEL + 2, col)
	l1.add_theme_font_override("font", DB.title_font(UI.FS_TITLE))
	var l2 := UI.lbl(sub, UI.FS_BODY, Color(DB.PAL.bamboo, 1.0 if on else 0.55))
	for l in [l1, l2]:
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bx.add_child(l)
	b.add_child(bx)
	_title_info[key] = [text, sub, on]
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
	_ending_key = ""
	_play_t0 = -1
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


## 새 판 확인 (11/14 UI 4단계) —— 되돌릴 수 없는 행동은 확인 한 번. [취소] 왼쪽 · [새 판 시작] 오른쪽 (위험 붉음)
func _confirm_new() -> void:
	var b := open_sheet("새 판을 시작할까요?")
	var d := UI.lbl("지금 진행 중인 판은 사라지고 되돌릴 수 없습니다.", UI.FS_BODY, DB.PAL.danger)
	UI.wrap_text(d)
	b.add_child(d)
	var row := UI.hbox(UI.SP_S)
	var no := UI.btn_ghost("취소", close_sheet)
	no.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(no)
	var ok := UI.btn("새 판 시작", func():
		Run.delete_save()
		_new_game(), "warn")
	ok.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(ok)
	b.add_child(row)


func _new_game() -> void:
	if online != null:
		online.leave()
	run = Run.new()
	run.new_game()
	run.save()
	_ending_key = ""
	_play_t0 = -1
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
	var drew_now := _auto_draw_solo()      # 11/25 자동 징집 (혼자 하기) —— 그리기 전에 받아 두어 이번 화면이 받은 상태로 나온다
	if run != _warm_run:
		_warm_run = run
		_warm_for_run()
	MiniTile.locked = run.locked      # 11/12 온라인 장수 선점제 · 사망룰 —— 잠긴 장수 타일은 회색 + 까닭, 눌리지 않는다 (혼자 하기는 늘 빈 것)
	_render_head()
	_build_tabbar_badges()
	var keep := _scroll.scroll_vertical
	var fixed: bool = page == "deploy" or (page == "draw" and run.over == null) or (page == "war" and run.over == null and online == null)      # 전투 탭 —— 진영 그림이 남는 공간을 채운다 (11/4)      # 징집도 고정 —— 보유 패만 아래에서 스크롤 (11/2)
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
		UI.presize(pg)      # 11/15 성능: 타일을 엉뚱한 크기로 한 번 더 그리지 않게 (UI.presize)
	else:
		_body.add_child(pg)
		UI.presize(pg)
		var want: int = _scroll_keep.get(page, 0) if new_page else keep
		_restore_scroll.call_deferred(want)
	_flush_toasts()
	_draw_reveal_check(drew_now)
	_coach_tick()
	if _play_t0 < 0 and run.over == null:
		_play_t0 = Time.get_ticks_msec()
	_maybe_ending.call_deferred()


func _restore_scroll(v: int) -> void:
	await get_tree().process_frame
	_scroll.scroll_vertical = v


## 기록 탭 —— 위에 [순위 | 계보 | 업데이트] 나눔 탭
func _page_more(body: Control) -> Control:
	var v := UI.vbox(UI.SP_L)
	v.add_child(UI.segmented([["rank", "군웅"], ["line", "계보"], ["update", "업데이트"]], page, func(k): go(k)))
	v.add_child(body)
	return v


## 업데이트 내역 (11/7) —— data/changelog.json 의 버전별 변경. 제목 화면에선 시트로, 게임 안에선 기록 탭 안 페이지로 같은 내용
## 11/20 정리: 맨 위(지금) 판만 펼치고 지난 판은 한 줄(버전 · 날짜 · 제목)로 접는다 —— 누르면 그때 내용을 만든다 (판이 수십 개라 다 만들면 시트가 늦게 열렸다).
## also = 처음부터 함께 펼칠 판 번호 (점검용 --gsheet=update:2)
func _changelog_body(also := -1) -> Control:
	var v := UI.vbox(UI.SP_S)
	var vs := CHANGELOG.versions()
	if vs.is_empty():
		v.add_child(UI.hint("업데이트 내역이 없습니다."))
		return v
	for i in vs.size():
		if i > 0:
			v.add_child(UI.hair())
		var box := UI.vbox(UI.SP_S)
		_changelog_fill(box, vs[i], i == 0, i == 0 or i == also)
		v.add_child(box)
	return v


## 한 판 —— 머리줄(버전 굵게 · 날짜 흐리게 · 제목 · 접힘 표시)을 누르면 접고 편다. 접혀 있으면 묶음 · 항목은 만들지 않는다
func _changelog_fill(box: VBoxContainer, ver: Dictionary, now: bool, open: bool) -> void:
	for c in box.get_children():
		box.remove_child(c)
		c.queue_free()
	var P := DB.PAL
	var head := UI.hbox(UI.SP_S)
	head.custom_minimum_size.y = UI.BH_S
	head.mouse_filter = Control.MOUSE_FILTER_STOP
	head.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var vl := UI.lbl("v%s" % str(ver.get("ver", "?")), UI.FS_TITLE if now else UI.FS_LABEL, P.gold if now else P.paper, true)
	head.add_child(vl)
	var date := str(ver.get("date", ""))
	head.add_child(UI.lbl(date.substr(5).replace("-", ".") if date.length() == 10 else date, UI.FS_CAP, P.text_dim))      # 2026-11-19 → 11.19 (좁은 화면에서 제목 자리를 남긴다)
	var t := UI.lbl(str(ver.get("title", "")), UI.FS_BODY, P.paper if open else P.bamboo)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if open:
		UI.wrap_text(t)      # 펼치면 제목을 끝까지 (여러 줄)
	else:
		t.clip_text = true
		t.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	head.add_child(t)
	if now:
		head.add_child(UI.lbl("지금", UI.FS_CAP, P.jade))
	head.add_child(UI.lbl("▴" if open else "▾", UI.FS_BODY, P.text_dim, true))      # UI.fold 와 같은 표시: ▾ 닫힘 · ▴ 열림
	UI.tap(head, func():
		UI.buzz()
		_changelog_fill(box, ver, now, not open))
	box.add_child(head)
	if not open:
		return
	var body := UI.vbox(UI.SP_M)
	for g in ver.get("groups", []):
		var gb := UI.vbox(UI.SP_XS)
		gb.add_child(UI.lbl(str(g.get("n", "")), UI.FS_CAP, P.gold, true))
		for it in g.get("items", []):
			# 글머리 기호와 본문을 칸으로 나눈다 —— 본문이 줄바꿈돼도 둘째 줄이 기호 아래로 들어가지 않는다
			var row := UI.hbox(UI.SP_XS)
			var dot := UI.lbl("·", UI.FS_BODY, P.bamboo, true)
			dot.custom_minimum_size.x = UI.SP_S
			dot.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			dot.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
			row.add_child(dot)
			var l := UI.lbl(str(it), UI.FS_BODY, P.paper)
			l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			UI.wrap_text(l)
			row.add_child(l)
			gb.add_child(row)
		body.add_child(gb)
	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_bottom", UI.SP_M)
	pad.add_child(body)
	box.add_child(pad)


func _page_update() -> Control:
	var v := UI.vbox(UI.SP_M)
	v.add_child(_page_head("업데이트 내역", "지금 버전 v%s · 빌드마다 바뀐 것" % CHANGELOG.version()))
	v.add_child(_changelog_body())
	return v


func _update_sheet(also := -1) -> void:
	var b := open_sheet("업데이트 내역 · v%s" % CHANGELOG.version())
	b.add_child(_changelog_body(also))


func _render_head() -> void:
	_clock_lbl.visible = false
	if online != null and online.in_game and not online.room.is_empty():
		# 11/9 사용자: 온라인은 머리띠도 방의 시계로 —— "2일차 · 저녁 준비 · 1:20" (혼자 하기의 '월요일 오후'와 어긋나 보였다). 진행 막대는 하루 네 단계.
		# 병사 수(12,900명)는 뺀다 (결정 ⑥ 처럼 전력은 보이지 않는다)
		var st := str(online.room.get("stage", ""))
		_day_lbl.text = online.day_text()      # 11/10 게임 날짜 · 페이즈로 (day_no 는 페이즈 번호 1~21)
		_sub_lbl.text = (("천하 통일" if run.over.win else "멸망") if run.over else online.head_stage_text())
		_phase_bar.n = online.head_steps()      # 11/11 토벌이 없는 날(4일차~)은 세 칸
		_phase_bar.group = online.head_steps()
		_phase_bar.cur = online.head_idx()
	else:
		_day_lbl.text = "DAY %d · %s요일" % [run.day + 1, Run.DAYNAME[run.day % 7]]
		_sub_lbl.text = (("천하 통일" if run.over.win else "멸망") if run.over else Run.PHASE_N[run.phase])
		# 11/12 최후 1인: 7일이 지나도 판이 이어진다 —— 막대는 이번 주(7일 × 3칸)만
		_phase_bar.n = 21
		_phase_bar.group = 3
		_phase_bar.cur = run.phase_idx() % 21
	_phase_bar.queue_redraw()
	_grain_sync()
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
	_tk_head()


## 11/15 군략 3택1 —— 머리띠 버튼을 켜고 끈다. 하루 끝에 새로 오면 시트를 한 번 저절로 연다 (전투 · 다른 시트 위에는 안 띄운다)
func _tk_head() -> void:
	if _tk_btn == null:
		return
	var on: bool = run.over == null and (not run.tk_offer.is_empty() or not run.rs_offer.is_empty())      # 11/22 군략 → 연구 두 단계
	_tk_btn.visible = on
	_tk_btn.text = "군략 3택1" if not run.tk_offer.is_empty() else "연구 3택1"
	if on and _tk_auto != run.day and not sheet_open() and not (_battle_layer != null and _battle_layer.visible):
		_tk_auto = run.day
		(func(): if not sheet_open(): TacUI.offer_sheet(self)).call_deferred()


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


## 머리띠 군량 (11/13) —— 판매 · 상점을 쓰는 판에서만. 값이 바뀌면 숫자가 한 번 튄다 (커졌다 제자리 · 늘면 밝게)
func _grain_sync() -> void:
	_grain_box.visible = shop_on() or gacha_on()
	if not _grain_box.visible:
		_grain_shown = -1
		return
	var g := int(run.grain)
	_grain_lbl.text = str(g)
	if _grain_shown >= 0 and g != _grain_shown:
		_grain_pop(g > _grain_shown)
	_grain_shown = g


func _grain_pop(up: bool) -> void:
	var l := _grain_lbl
	l.pivot_offset = l.size / 2
	var tw := l.create_tween()
	l.modulate = Color(1.5, 1.4, 1.0) if up else Color(1.3, 0.75, 0.7)
	tw.tween_property(l, "scale", Vector2(1.32, 1.32), 0.09).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(l, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(l, "modulate", Color.WHITE, 0.35)


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


## 플레이타임 —— 이 판이 시작된 뒤 켜 둔 시간(판이 끝나면 멈춤, 제목 화면에서는 세지 않는다). 머리띠 민심 아래에 작게 (11/12 사용자)
## 판이 바뀌면(game_id) 그 판의 갈무리도 맞춘다 —— 다른 판의 것이면 비우고 다시 그린다 (ForgeTree.bind)
func _play_tick(dt: float) -> void:
	var id := game_id()
	if id != _play_id:
		_play_store()
		_play_id = id
		_play_sec = float(_play_load().get(id, 0.0))
		if forge_tree != null and forge_tree.bind(id) and run != null:
			render()
	if run != null and run.over == null and (_title == null or not _title.visible):
		_play_sec += dt
		_play_save_t += dt
		if _play_save_t >= 10.0:
			_play_store()
	if _play_lbl != null and is_instance_valid(_play_lbl) and _play_lbl.is_visible_in_tree():
		_play_lbl.text = play_text()


## 판의 이름표 —— Run 의 rng 씨앗 (혼자 하기 · 온라인 모두 판마다 다르고, 저장 · 서버 상태에 함께 실려 온다)
func game_id() -> String:
	return "" if run == null else str(run.rng.seed)


func _play_load() -> Dictionary:
	if not FileAccess.file_exists(PLAY_PATH):
		return {}
	var d = JSON.parse_string(FileAccess.get_file_as_string(PLAY_PATH))
	return d if d is Dictionary else {}


func _play_store() -> void:
	_play_save_t = 0.0
	if _play_id == "" or not PlayLog.enabled:      # 점검 실행(--gnew)은 적지 않는다
		return
	var d := _play_load()
	d.erase(_play_id)
	while d.size() >= 4:      # 최근 판 몇 개만 (오래된 것부터 뺀다 —— 사전은 넣은 순서를 지킨다)
		d.erase(d.keys()[0])
	d[_play_id] = snappedf(_play_sec, 0.1)
	var f := FileAccess.open(PLAY_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(d))


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


## 11/14 감사 #5: 같은 종류(「희귀 보급 —— 황권」 처럼 「——」 앞이 같은) 알림은 한 줄로 묶는다 —— 「희귀 보급 3장 —— 황권 · 이의 · 마량」.
##   한 번에 보이는 알림은 최대 TOAST_MAX 줄 (카드 그리드를 가리지 않게)
const TOAST_MAX := 2
func toast(text: String, kind := "") -> void:
	Sfx.play({"gain": "gain", "bad": "deny", "gold": "gain"}.get(kind, "draw"))
	var cut := text.split(" —— ", true, 1)
	var grp := "%s|%s" % [kind, cut[0]] if cut.size() > 1 else ""
	if grp != "":
		for c in _toast_box.get_children():
			if c.is_queued_for_deletion() or str(c.get_meta("grp", "")) != grp:
				continue
			var items: Array = c.get_meta("items")
			items.append(cut[1])
			var unit := "장" if cut[0].ends_with("보급") else "건"
			(c.get_meta("lbl") as Label).text = UI.keep_words("%s %d%s —— %s" % [cut[0], items.size(), unit, " · ".join(items)])
			_toast_fit.call_deferred(c.get_meta("lbl"))
			_toast_play(c)
			return
	var p := PanelContainer.new()
	var col: Color = {"gold": DB.PAL.gold, "news": DB.PAL.bamboo, "gain": DB.PAL.jade, "bad": DB.PAL.seal}.get(kind, DB.PAL.bamboo_dim)
	var sb := UI.flat(Color("#1b2236", 0.97), Color(col, 0.35), 1, UI.R, 12)      # 11/9: 왼쪽 굵은 색 띠 · 그림자 걷음 —— 얇은 선 하나
	p.add_theme_stylebox_override("panel", sb)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := UI.lbl(text, UI.FS_BODY, DB.PAL.danger if kind == "bad" else DB.PAL.paper)
	UI.wrap_text(l)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.max_lines_visible = 2
	l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	# 11/20 줄바꿈 + 줄임표를 같이 켠 Label 은 최소 높이가 1 이다 (Godot) —— 11/14 부터 알림이 글자 없이 빈 상자(높이 25)로만 떴다.
	# 한 줄 자리를 먼저 잡고, 폭이 정해지면 줄 수(최대 2)만큼 높이를 잡는다 (_toast_fit)
	l.custom_minimum_size.y = UI.FS_BODY + 6.0
	l.resized.connect(_toast_fit.bind(l))
	p.add_child(l)
	p.set_meta("grp", grp)
	p.set_meta("items", [cut[1]] if grp != "" else [])
	p.set_meta("lbl", l)
	_toast_box.add_child(p)
	while _toast_box.get_child_count() > TOAST_MAX:
		_toast_box.get_child(0).free()
	p.modulate.a = 0.0
	_toast_play(p)


## 알림 글의 높이 —— 지금 폭에서 줄 수(최대 2)만큼
func _toast_fit(l) -> void:      # 형을 적지 않는다 —— 미뤄 부른 사이 알림이 지워졌으면 지워진 객체가 온다
	if not is_instance_valid(l) or not (l is Label):
		return
	var lb: Label = l
	if lb.size.x < 40.0:      # 아직 폭이 안 정해졌다
		return
	var brk := TextServer.BREAK_MANDATORY | TextServer.BREAK_WORD_BOUND | TextServer.BREAK_ADAPTIVE
	var f := lb.get_theme_font("font")      # 글꼴로 줄 수만 센다 (Label 의 줄 수 · 줄 높이는 높이가 모자란 동안 믿을 수 없다)
	var n := clampi(roundi(f.get_multiline_string_size(lb.text, HORIZONTAL_ALIGNMENT_LEFT, lb.size.x, UI.FS_BODY, 2, brk).y / maxf(1.0, f.get_height(UI.FS_BODY))), 1, 2)
	var hh: float = n * lb.get_line_height() + (n - 1) * lb.get_theme_constant("line_spacing")
	if absf(lb.custom_minimum_size.y - hh) > 0.5:
		lb.custom_minimum_size.y = hh


## 알림 보이기 → 2.6초 → 사라짐. 묶여서 글이 바뀐 알림은 처음부터 다시 센다
func _toast_play(p: Control) -> void:
	var old: Tween = p.get_meta("tw") if p.has_meta("tw") else null
	if old != null and old.is_valid():
		old.kill()
	var tw := p.create_tween()
	p.set_meta("tw", tw)
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
var band_log: Array = []      # 띄운 띠 글 기록 (점검용 —— tests/phase_flow 가 센다. 바로 떠서 _bands 에 남지 않는 띠도 잡는다)
## over_report —— 전투 결과표를 보는 중에도 바로 띄운다 (온라인 「아침이 밝았습니다」 · 「토벌 종료」)
func band(text: String, col: Color = DB.PAL.gold, sub := "", over_report := false) -> void:
	band_log.append(text)
	_bands.append([text, col, sub, over_report])
	if not _band_busy:
		_next_band()


var _band_node: Control = null
## 전투 화면이 열리면 떠 있던 띠를 감춘다 (남은 띠는 전투가 끝난 뒤)
func _hide_band() -> void:
	if is_instance_valid(_band_node):
		_band_node.visible = false


func _next_band() -> void:
	# 11/6 전투 중에는 띠를 띄우지 않는다 (진형 표시 · 전장을 가렸다) —— 전투가 끝나면 이어서.
	# 11/16 사용자 "멀티 아침이 밝았습니다가 안나옴": 봇과만 하면 내 대전이 늘 마지막이라 결과표가 뜨는 순간 서버가 아침으로 넘어간다 —— 띠가 결과표를 닫을 때까지 밀렸다.
	# 싸움이 끝난 뒤(결과표를 보는 중)에는 전장을 가릴 일이 없으니 바로 띄운다
	# 싸움이 끝난 뒤(결과표를 보는 중)에는 전장을 가릴 일이 없으니 단계 알림(over_report)만 바로 띄운다 —— 보상 띠는 예전처럼 결과표를 닫은 뒤
	var bi := 0
	if not _bands.is_empty() and battle_visible():
		bi = -1
		if _battle != null and _battle.finished:
			for i in _bands.size():
				if bool(_bands[i][3]):
					bi = i
					break
	if _bands.is_empty() or bi < 0:
		_band_busy = false
		return
	_band_busy = true
	var e: Array = _bands.pop_at(bi)
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
	sb.content_margin_left = 14      # 11/20 긴 글이 화면 양끝에 닿거나 넘치지 않게 —— 옆 여백 + 넘치면 …
	sb.content_margin_right = 14
	p.add_theme_stylebox_override("panel", sb)
	p.anchor_left = 0
	p.anchor_right = 1
	p.anchor_top = 0
	p.anchor_bottom = 0
	var v := UI.vbox(2)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := UI.lbl(str(e[0]), UI.FS_TITLE, col.lightened(0.25), true)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_constant_override("outline_size", 5)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	l.clip_text = true
	l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	v.add_child(l)
	if str(e[2]) != "":
		var l2 := UI.lbl(str(e[2]), UI.FS_BODY, DB.PAL.paper)
		l2.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l2.clip_text = true
		l2.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		v.add_child(l2)
	p.add_child(v)
	add_child(p)
	_band_node = p
	var h := p.get_combined_minimum_size().y
	# 11/14 감사 #5: 화면 42% 높이에 떠서 카드 이름을 덮었다 —— 머리띠 바로 아래(위쪽)로
	var y0 := (_top.get_global_rect().end.y - global_position.y + UI.SP_S) if is_instance_valid(_top) else 80.0
	p.offset_left = 0
	p.offset_right = 0
	p.offset_top = y0
	p.offset_bottom = y0 + h
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
		"gacha": Sfx.play("draw" if r != null else "deny")
		"sell", "buy": Sfx.play("gain" if (r != null and not (r is bool and not r)) else "deny")
	if online != null:
		online.send_cmd(m, a)
	changed()
	return r


# ───────── 자동 징집 (11/25 사용자: 준비 단계가 열리면 기본패를 저절로 받고 짧은 공개 연출만) ─────────

## 혼자 하기 —— 새 판 · 다음 페이즈 · 받기 전에 저장된 판을 이어하기에서 render 가 부른다. 받았으면 true.
## 온라인은 서버(Room._auto_draw)가 단계를 열 때 준다 —— 여기서는 받지 않는다
func _auto_draw_solo() -> bool:
	if online != null or run == null or (_title != null and _title.visible):
		return false
	var got := run.auto_draw()
	if got.is_empty():
		return false
	PlayLog.act(run, "do_draw", [], got, true)
	run.save()
	return true


static var _drawfx_key := ""     # 공개 연출을 띄운 단계 (판 시드:일차:페이즈) —— 다시 그리기 · 재접속에 또 뜨지 않게 (앱이 켜져 있는 동안)
static var _drawfx_n := 0        # 그 단계에서 보여 준 장 수 —— 징병으로 더 받으면 더 받은 만큼만 한 번 더


## 받은 기본패가 처음 보이는 순간 한 번 —— fresh: 혼자 하기에서 방금 저절로 받았다
## 온라인은 서버 상태가 와서 '받았다'가 된 때. 앱을 새로 켜고 판 중간(첫 단계 밖)에 다시 들어온 것은 이미 본 징집이라 띄우지 않는다
func _draw_reveal_check(fresh := false) -> void:
	if run == null or not run.drawn or run.last_draw.is_empty() or (_title != null and _title.visible):
		return
	var key := "%s:%d:%d" % [str(run.rng.seed), run.day, run.phase]
	var n: int = run.last_draw.size()
	if key == _drawfx_key and n <= _drawfx_n:
		return
	var grew := key == _drawfx_key
	var from := _drawfx_n if grew else 0
	var show := fresh or grew or (online != null and (_drawfx_key != "" or (run.day == 0 and run.phase == 0)))
	_drawfx_key = key
	_drawfx_n = n
	if show:
		_draw_reveal(run.last_draw.slice(from), grew)


## 공개 연출 —— 머리띠 아래에 기본패 줄 하나 (병종 타일 × 받은 수) 를 1초 남짓 띄운다. 입력은 막지 않는다 (마우스 무시)
func _draw_reveal(cards: Array, more := false) -> void:
	if cards.is_empty():
		return
	Sfx.play("draw")
	var cnt := {}
	for k in cards:
		cnt[str(k)] = int(cnt.get(str(k), 0)) + 1
	var p := PanelContainer.new()
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_theme_stylebox_override("panel", UI.flat(Color("#0d1220", 0.93), Color(DB.PAL.gold, 0.75), 1, UI.R, 8))
	var v := UI.vbox(4)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := UI.lbl(("징병 —— 기본패 %d장 더" if more else "징집 —— 기본패 %d장") % cards.size(), UI.FS_BODY, DB.PAL.gold.lightened(0.2), true)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(l)
	var row := UI.hbox(4)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	for k in Run.sort_cards(cnt.keys()):
		var t := MiniTile.new().setup(str(k), int(cnt[k]))
		t.mouse_filter = Control.MOUSE_FILTER_IGNORE
		t.custom_minimum_size = Vector2(30, HAND_TILE.y)
		t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		t.size_flags_stretch_ratio = 1.0
		row.add_child(t)
	v.add_child(row)
	p.add_child(v)
	add_child(p)
	var y0 := (_top.get_global_rect().end.y - global_position.y + UI.SP_S) if is_instance_valid(_top) else 80.0
	if _band_busy and is_instance_valid(_band_node) and _band_node.visible:      # 「아침이 밝았습니다」 띠가 같은 자리에 떠 있으면 그 아래로
		y0 = _band_node.offset_bottom + UI.SP_S
	var wmax := minf(size.x - 2.0 * UI.SP_M, 60.0 * cnt.size() + 40.0)
	p.position = Vector2((size.x - wmax) / 2.0, y0)
	p.size = Vector2(wmax, 0)
	p.pivot_offset = Vector2(wmax / 2.0, 0)
	p.modulate.a = 0.0
	p.scale = Vector2(1.0, 0.6)
	var tw := p.create_tween()
	tw.tween_property(p, "modulate:a", 1.0, 0.12)
	tw.parallel().tween_property(p, "scale:y", 1.0, 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_interval(0.85)
	tw.tween_property(p, "position:y", y0 - 24.0, 0.25).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(p, "modulate:a", 0.0, 0.25)
	tw.tween_callback(p.queue_free)


## 조용한 행동 (11/15 모두 조합) —— act 와 같은 판정 · 기록 · 서버 전송을 하되 저장 · 다시 그리기 · 소리 · 한 장 연출은 하지 않는다.
## 여러 번 잇달아 부른 뒤 부르는 쪽이 changed() 를 한 번 부른다 (한 장마다 화면 전체를 다시 만들면 수십 번 조합에 몇 초씩 멈췄다)
func act_quiet(m: String, a := []):
	if online != null and not online.can_act(Online.cmd_kind(m)):
		return null
	var r = run.command(m, a.duplicate())
	if online == null:
		PlayLog.act(run, m, a, r)
	if m == "forge" and r:
		if forge_tree.pinned(str(a[0])):
			forge_tree.done(str(a[0]))
		if DB.C[str(a[0])].tier >= 7:
			_forge_fanfare(str(a[0]))
	if online != null:
		online.send_cmd(m, a)
	return r


## 지금 이 행동을 할 수 있는가 —— 안 되면 까닭을 알리고 false (온라인 단계 제한)
func can_act_or_tell(m: String) -> bool:
	if online != null and not online.can_act(Online.cmd_kind(m)):
		Sfx.play("deny")
		toast(online.block_reason(Online.cmd_kind(m)), "bad")
		render()
		return false
	return true


# ───────── 시트 ─────────

## col 을 주면 제목을 그 색 · 큰 글씨로 (카드 시트 —— 등급색 장수 이름)
func open_sheet(title: String, col := Color(0, 0, 0, 0)) -> VBoxContainer:
	# 11/20 조작: 닫히는 0.2초 안에 열면 닫는 트윈이 끝나며 새 시트를 숨겼다 —— 닫는 트윈을 죽이고 처음 여는 것처럼 올린다
	var was := _sheet.visible and not _sheet_closing
	if _sheet_closing:
		if _sheet_tw != null:
			_sheet_tw.kill()
		_sheet_closing = false
	if not _routing:
		_route = {}
		_hist.clear()
	_routing = false
	_update_back()
	if not was:
		Sfx.play("open")
	_sheet_title.text = title
	_sheet_title.custom_minimum_size.x = 0
	_sheet_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_sheet_temper.hide()
	_sheet_full = false
	# 전투 위에서도 시트가 보이게 맨 앞으로 —— 11/7 제목 화면도 (시트보다 나중에 붙어 위를 덮어, 제목의 '설정'이 열려도 안 보였다)
	if (_battle_layer != null and _battle_layer.visible) or (is_instance_valid(_title) and _title.visible):
		move_child(_sheet_mask, -1)
		move_child(_sheet, -1)
	_sheet_title.add_theme_color_override("font_color", col if col.a > 0 else DB.PAL.paper)
	_sheet_title.add_theme_font_size_override("font_size", UI.FS_HEAD if col.a > 0 else UI.FS_TITLE)
	_card_tab_bar.hide()
	_sheet_wash.hide()      # 11/21 장수창 머리 (sheet_head) —— 다른 시트에서는 걷는다
	_sheet_meta.hide()
	for ch in _sheet_meta.get_children():
		_sheet_meta.remove_child(ch)
		ch.queue_free()
	for tab in _card_tabs.get_children():
		_card_tabs.remove_child(tab)
		tab.queue_free()
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


## 11/21 장수창 머리 —— 등급 색 바탕(그라데이션 · 빗금 · 금빛 선) + 이름 아래 [등급 리본 · 세력 · 병종] 한 줄 (SheetStyle).
## 갈무리창 · 상세창 · 전투 장수창이 open_sheet 바로 뒤에 부른다. extra: 덧칩 [[글, 색], …]
func sheet_head(k: String, extra: Array = []) -> void:
	if not DB.C.has(k):
		return
	var head: Control = _sheet_wash.get_parent()
	var nw := SheetStyle.head_wash(DB.tier_color(k))
	head.add_child(nw)
	head.move_child(nw, _sheet_wash.get_index())
	_sheet_wash.queue_free()
	_sheet_wash = nw
	_sheet_meta.add_child(SheetStyle.meta_row(k, extra))
	_sheet_meta.show()


func close_sheet() -> void:
	_route = {}
	_hist.clear()
	if not _sheet.visible:
		return
	_slide_sheet(_sheet_h, 0.2, func():
		_sheet_closing = false
		_sheet_mask.visible = false
		_sheet.visible = false)
	_sheet_closing = true


func sheet_open() -> bool:
	return _sheet.visible


## 11/20 조작: 화면에 눌림이 있는가 —— 누르는 중 · 끄는 중 · 스크롤 중 · 쓸어 닫는 중 (스크롤 · 쓸기는 밑의 누름을 취소해 버튼 상태로는 안 보인다).
## 온라인이 서버 상태를 받아 페이지를 다시 만들 때 본다 (Online._render_soon)
func touch_held() -> bool:
	return Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) or get_viewport().gui_is_dragging() or (_swipe_on and _sheet.visible) or TouchScroll.scrolling()


## 카드 시트로 들어간다 —— 다른 카드 시트를 보던 중이면 그 시트를 길에 쌓는다
func _route_enter(kind: String, k: String) -> void:
	var r := {"kind": kind, "k": k}
	if _back_nav:
		_back_nav = false
	elif _sheet.visible and not _route.is_empty() and (_route.kind != kind or _route.k != k):
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
	elif r.kind == "recipes":      # 11/25 전체 조합법 목록
		recipes_sheet()
	else:
		card_info(r.k, int(r.get("tab", 0)), str(r.get("inyeon", "")))


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
	if (e is InputEventMouseButton or e is InputEventMouseMotion) and e.position.x < -1000.0:
		return      # 누름 취소용 화면 밖 이동 · 떼기 (TouchScroll._cancel_press)
	if _sheet_closing:      # 11/20 조작: 닫히는 중인 시트의 버튼은 눌리지 않는다
		_swipe_p = Vector2.INF
		_swipe_on = false
		if e is InputEventMouseButton and e.pressed and _sheet.get_global_rect().has_point(e.position):
			get_viewport().set_input_as_handled()
		return
	# 11/20 조작: 쓸어 닫으면 손가락 밑의 버튼도 눌렸다(떼는 순간 탭으로) —— 움직이는 중에 쓸기로 판정되면(가로가 닫는 거리의 1/3 을 넘고 세로의 2배 이상)
	# 밑의 누름을 화면 밖 떼기로 취소하고, 진짜 떼기는 삼킨 뒤 닫는다
	if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
		if e.pressed:
			_swipe_on = false
			_swipe_p = e.position if _sheet.get_global_rect().has_point(e.position) and not UI.swipe_blocked_at(_sheet, e.position) else Vector2.INF
		elif _swipe_p != Vector2.INF:
			var d: Vector2 = e.position - _swipe_p
			var was_on := _swipe_on
			_swipe_p = Vector2.INF
			_swipe_on = false
			var ok: bool = d.x > Press.SWIPE_CLOSE and absf(d.y) < d.x * 0.5 and not get_viewport().gui_is_dragging()
			if was_on or ok:
				get_viewport().set_input_as_handled()
				if not was_on:
					TouchScroll._cancel_press()      # 움직임 없이 한 번에 온 쓸기 —— 여기서라도 걷는다
				# 떼기를 삼켰으니 TouchScroll 은 이 떼기를 못 본다 —— 누름 기억을 직접 걷는다 (안 그러면 PC 에서 다음 마우스 이동이 스크롤이 된다)
				TouchScroll.drop_press()
			if ok:
				UI.buzz()
				if _hist.is_empty():
					close_sheet()
				else:
					go_back()
	elif e is InputEventMouseMotion and _swipe_p != Vector2.INF and not _swipe_on:
		var d: Vector2 = e.position - _swipe_p
		if d.x > Press.SWIPE_CLOSE / 3.0 and d.x >= absf(d.y) * 2.0 and not get_viewport().gui_is_dragging():
			_swipe_on = true
			TouchScroll._cancel_press()


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
	b.add_child(UI.btn("새 판 시작", _confirm_new, "warn"))      # 11/14 UI 4단계: 한 번에 지우지 않고 확인 시트
	b.add_child(UI.btn("설정", _settings_sheet, "ghost"))
	if OS.has_feature("pc"):      # 11/5 사용자: 친구들에게 플레이 기록을 받으려고 —— 휴대폰은 앱 폴더라 열 수 없다
		var dir := ProjectSettings.globalize_path(PlayLog.dir).replace("/", "\\")
		b.add_child(UI.btn("플레이 기록 폴더 열기", func():
			DirAccess.make_dir_recursive_absolute(PlayLog.dir)
			OS.shell_open(dir), "ghost"))
		b.add_child(UI.hint("판마다 .jsonl 파일이 하나씩 쌓입니다. 이 파일들을 보내 주세요."))
		# 11/20 폴더 길이 안내 글에 붙어 「C:」 · 「솔/국지」에서 끊겨 세 줄이 됐다 —— 작은 글씨 따로, 글자 단위로 꽉 채워 줄바꿈
		var dl := UI.lbl(dir, UI.FS_CAP, Color(DB.PAL.text_dim, 0.8))
		dl.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
		b.add_child(dl)
	b.add_child(UI.hint("행동할 때마다 자동으로 저장됩니다. 전투 도중 앱을 꺼도 다음에 열면 그 전투를 마무리합니다."))


func _settings_sheet() -> void:
	var b := open_sheet("설정")
	if not Settings.PAINTING_ONLY:      # 11/19 사용자: 삽화 방식만 —— 화풍 선택칸을 숨긴다
		b.add_child(UI.eyebrow("전투 화풍"))
		b.add_child(UI.segmented([["painting", "전쟁 삽화"], ["crowd", "기존 군집"]], "painting" if Settings.war_painting else "crowd", func(key):
			Settings.war_painting = key == "painting"
			Settings.save_cfg()
			_settings_sheet()))
		b.add_child(UI.hint("다음 전투부터 적용됩니다."))
	b.add_child(UI.eyebrow("전투 품질 — 병사 수 · 해상도 · 그림자"))
	var qs := []
	for q in 3:
		qs.append([str(q), Settings.QUALITY_N[q]])
	b.add_child(UI.segmented(qs, str(Settings.quality), func(key):      # 11/14 고르기 줄은 모두 UI.segmented 하나로
		Settings.quality = int(key)
		Settings.apply()
		Settings.save_cfg()
		_settings_sheet()))
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
	b.add_child(UI.eyebrow("고유기 연출"))      # 11/22 사용자: 중후반 고유기 연출이 쉼 없이 나온다
	b.add_child(UI.segmented([["0", "모두"], ["1", "중요한 것만"], ["2", "간단히"]], str(Settings.ult_fx), func(key):
		Settings.ult_fx = int(key)
		Settings.save_cfg()
		if _battle:
			_battle.remark_ults()
		_settings_sheet()))
	b.add_child(UI.hint("중요한 것만: 내 장수의 첫 고유기 · 인연 합동의 첫 번째 · 적 신화의 첫 고유기 · 부대를 무너뜨린 한 방만 크게, 나머지는 멈추지 않고 이름과 효과만."))
	b.add_child(UI.eyebrow("전투 카메라 연출"))      # 11/6 사용자: 불필요한 카메라 무빙 자제
	b.add_child(UI.segmented([["0", "끔"], ["1", "적게"], ["2", "보통"]], str(Settings.cam_fx), func(key):
		Settings.cam_fx = int(key)
		Settings.save_cfg()
		_settings_sheet()))
	b.add_child(UI.hint("적게: 아군 고유기 · 적 신화 고유기 · 장수 격파 때만 다가갑니다. 보통: 첫 격돌 · 모든 고유기에도."))
	b.add_child(UI.eyebrow("전장 확대 · 따라가기"))      # 사용자 "유닛이 작아 답답하다"
	b.add_child(UI.segmented([["1", "켬"], ["0", "끔"]], "1" if Settings.zoom_cam else "0", func(key):
		Settings.zoom_cam = key == "1"
		Settings.save_cfg()
		_settings_sheet()))
	b.add_child(UI.hint("켬: 빈 여백을 줄여 유닛을 키우고, 싸움이 이어져 부대가 줄면 천천히 더 가까이 비춥니다."))
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
	vb.focus_mode = Control.FOCUS_NONE      # 11/20 조작: 누른 버튼에 포커스가 남아 스페이스 · 엔터가 다시 누르지 않게
	vb.text = "누를 때 진동"
	vb.button_pressed = Settings.haptics
	vb.custom_minimum_size = Vector2(0, UI.BH_M)
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
			go("draw"), "ghost", UI.BH_S))


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
	# 11/14 감사 #6-4: 징집 · 전투 단계는 탭 대신 화면 안 주 행동 버튼(「징집하기」 · 「출진」)을 가리킨다 —— 버튼 바로 아래에 뜬다
	# 11/25 자동 징집: 징집은 누를 버튼이 없다 —— 받은 기본패 줄(_base_row)을 가리킨다 (없거나 사라졌으면 탭을 가리킨다)
	var cta: Control = {"draw": _base_row, "war": _war_cta_node}.get(key) if _coach_i >= 0 else null
	var under := false
	if cta != null and is_instance_valid(cta) and cta.is_visible_in_tree() and page == key:
		await get_tree().process_frame
		if _coach_i != _coach_shown or not is_instance_valid(cta):
			return
		var r := cta.get_global_rect()
		aim = Vector2(r.get_center().x, r.end.y)
		under = true
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
		c = Coach.make(str(st[1]), str(st[2]), aim, last, not last, w, under)
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
	b.focus_mode = Control.FOCUS_NONE      # 11/20 조작: 누른 버튼에 포커스가 남지 않게 (TouchButton 과 같게)
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
	v.add_child(UI.lbl(top, UI.FS_BODY, col.lightened(0.2), true))
	v.add_child(UI.lbl("%s · %s" % [it.tag, it.grade], UI.FS_CAP, DB.PAL.text_dim))
	v.add_child(UI.lbl(UI.item_text(id, amp) + ("  · 신화 조합 재료" if it.use == "myth" else ""), UI.FS_CAP, DB.PAL.bamboo))
	# 11/15 사용자: 장착 아이템 글이 잘렸다 —— 이름 · 효과 줄은 … 으로 자르지 않고 줄을 바꾼다. 상자 높이는 글에 맞춰 늘어난다 (병종 · 등급 줄만 한 줄)
	for c in v.get_children():
		c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var kids := v.get_children()
	UI.wrap_text(kids[0])
	kids[1].text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	kids[1].clip_text = true
	UI.wrap_text(kids[2])
	b.add_child(v)
	var fit := func():
		if is_instance_valid(b) and is_instance_valid(v):
			b.custom_minimum_size.y = maxf(74.0, v.get_combined_minimum_size().y + 14.0)
	v.minimum_size_changed.connect(fit)
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
	v.add_child(UI.lbl(title, UI.FS_TITLE, DB.PAL.paper, true))
	if sub != "":
		v.add_child(UI.hint(sub))
	return v


## 초상 작은 카드 격자 —— 한 줄에 4장
## 징집 화면의 작은 카드 (11/2 사용자: UI 크기를 줄여 한 줄 5장)
const SMALL := UI.TILE_M
const HAND_TILE := UI.TILE_S     # 보유 패 8열 (11/2 · 11/4 높이 62 → 72)

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
func recipe_card(out: String, sz := UI.TILE_L) -> Control:
	var v := UI.vbox(UI.SP_XS)
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
			recipe_sheet(out), "pri" if ok else "ghost", UI.BH_S if sz.y >= 112 else UI.BH_XS)
	b.add_theme_font_size_override("font_size", UI.FS_BODY)
	v.add_child(b)
	return v


## 조합 시트 —— 제목은 등급색 장수 이름. 결과 카드(특기 칸) · 재료 한 줄(가진 수/필요 수) · 조합 + 상세 버튼 한 줄
func recipe_sheet(out: String) -> void:
	if not DB.RECOF.has(out):      # 조합법이 없는 카드(기본패 · 황건 전설 등)는 디테일창으로
		card_info(out)
		return
	_route_enter("recipe", out)
	var c: Dictionary = DB.C[out]
	var ult = DB.ult_of(out) if DB.has_ult(out) else null
	var temper := Battle.temper_name(c, ult) if ult != null else ""
	var b := open_sheet(str(c.name), DB.tier_color(out).lightened(0.2))
	if temper != "":
		_sheet_title.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		_sheet_title.custom_minimum_size.x = minf(220.0, _sheet_title.get_theme_font("font").get_string_size(str(c.name), HORIZONTAL_ALIGNMENT_LEFT, -1, _sheet_title.get_theme_font_size("font_size")).x + 2.0)
		_sheet_temper.text = temper
		_sheet_temper.show()
	sheet_head(out)      # 11/21 이름 아래 등급 리본 · 세력 · 병종 + 등급 색 머리 바탕 (SheetStyle —— 상세창 · 전투 장수창과 같은 머리)
	var pg := _forge_progress(out)
	var mv := UI.vbox(UI.SP_S)
	var actions := UI.hbox(UI.SP_S)
	var progress := UI.vbox(2)
	progress.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	progress.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	progress.add_child(UI.lbl("조합 재료 %d/%d" % [pg.x, pg.y], UI.FS_CAP, DB.PAL.bamboo, true))
	progress.add_child(SheetStyle.meter(pg.x, pg.y))
	progress.add_child(UI.lbl("%d장 부족" % (pg.y - pg.x) if pg.x < pg.y else "재료 갖춤", UI.FS_CAP, DB.PAL.text_dim))
	actions.add_child(progress)
	var pin := _pin_btn(out, func():
		var scroll_y := _sheet_scroll.scroll_vertical
		_back_nav = true
		recipe_sheet(out)
		_restore_sheet_scroll.call_deferred(scroll_y))
	SheetStyle.quiet_btn(pin) if forge_tree.pinned(out) else SheetStyle.sub_btn(pin)
	actions.add_child(pin)
	var detail := UI.btn("상세  ›", func(): card_info(out), "", UI.BH_M)
	SheetStyle.sub_btn(detail)
	detail.custom_minimum_size.x = 104
	actions.add_child(detail)
	mv.add_child(actions)
	var materials := UI.flow(4)
	var m := Run.mat_count(DB.RECOF[out])
	for q in m:
		var got := mini(run.have(q), int(m[q]))
		materials.add_child(SheetStyle.chip("%s %d/%d" % [DB.person(q), got, m[q]], DB.PAL.jade if got >= int(m[q]) else DB.PAL.bamboo, "soft"))
	var ni = Run.need_item(out)
	if ni != null:
		var got_item := mini(int(run.bag.get(ni, 0)), 1)
		materials.add_child(SheetStyle.chip("%s %d/1" % [DB.IT[ni].name, got_item], DB.PAL.jade if got_item > 0 else DB.PAL.bamboo, "soft"))
	mv.add_child(materials)
	b.add_child(mv)
	if run.can_forge(out):
		var forge := UI.btn("조합하기", func():
			if act("forge", [out]):
				toast("%s 조합 완료" % c.name, "gain")
				if _hist.is_empty():
					close_sheet()
				else:
					go_back(), "", UI.BH_M)
		SheetStyle.main_btn(forge)
		forge.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.add_child(forge)
	var tp := UI.hbox(UI.SP_M)
	var cv := CardView.new().setup(out, Vector2(96, 136))
	cv.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	cv.mouse_filter = Control.MOUSE_FILTER_STOP          # 11/3 사용자: 초상을 누르면 디테일창
	UI.tap(cv, func():      # 11/20 조작: '떼기'만 보던 것을 탭 판정으로 (UI.tap)
		UI.buzz()
		card_info(out))
	tp.add_child(cv)      # 11/20 역할은 큰 카드 초상 위에 (CardView.show_role)
	var rv := UI.vbox(2)
	rv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rv.add_child(SheetStyle.stat_block(c.atk, c["def"], c.spd, DB.INT_TAGS.has(c.tag)))
	var traits := TraitBoard.new()
	traits.fixed = true
	rv.add_child(traits.setup(out))
	rv.add_child(_compact_ability_summary(out))
	tp.add_child(rv)
	b.add_child(tp)      # 11/20 시트와 같은 색 상자(여백 10)에 싸여 초상만 10 들여 쓴 것처럼 보였다 —— 상자를 걷어 디테일창과 같은 왼끝
	var pv := run.forge_preview(out)      # 11/19 조합하면 편성에서 빠지는 것 —— 실제로 빠질 때만 (손패 여분으로 되면 아무것도 안 띄운다)
	if not pv.board_lost.is_empty():
		var lost := []
		for k in pv.board_lost:
			lost.append(DB.person(k))
		var parts := ["출전 %s 소모" % ", ".join(lost)]
		if int(pv.gear_lost) > 0:
			parts.append("장비 %d 해제" % pv.gear_lost)
		if not pv.bonds_lost.is_empty():
			parts.append("인연 「%s」 끊김" % "」「".join(pv.bonds_lost))
		if not pv.roles_lost.is_empty():
			parts.append("%s 역할 없어짐" % ", ".join(pv.roles_lost))
		mv.add_child(SheetStyle.note("조합하면 —— " + " · ".join(parts)))
	var reason := _forge_block_reason(out)
	if reason != "":
		b.add_child(UI.hint(reason))


func _compact_ability_summary(k: String) -> Control:
	var box := UI.vbox(2)
	var abilities := _ability_items(k)
	for kind in ["고유기", "고유 특기", "위세", "기인", "패업"]:
		for it in abilities:
			if it.kind != kind:
				continue
			var headline := _abil_headline(k, kind)
			var category := ""
			var source := str(headline[1]) if not headline.is_empty() else str(it.effect)
			for word in ["사기", "피해", "공격", "방어", "속도", "회복", "치료", "화상", "혼란", "기절", "보호", "저항"]:
				if source.contains(word):
					category = word
					break
			var line := UI.hbox(5)
			line.add_child(UI.lbl(kind, UI.FS_CAP, DB.PAL.gold))
			var name_label := UI.lbl(str(it.name), UI.FS_CAP, DB.PAL.paper, true)
			name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
			name_label.clip_text = true
			line.add_child(name_label)
			if category != "":
				var category_icons := {"사기": "banner", "피해": "burst", "공격": "blade", "방어": "shield", "속도": "boot", "회복": "heart", "치료": "heart", "화상": "flame", "혼란": "swirl", "기절": "burst", "보호": "shield", "저항": "shield"}
				var category_line := UI.hbox(3)
				var icon := Icons.View.new(str(category_icons.get(category, "burst")), ABIL_VAL, 12)
				icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
				category_line.add_child(icon)
				category_line.add_child(UI.lbl(category, UI.FS_CAP, ABIL_VAL))
				line.add_child(category_line)
			box.add_child(line)
	return box


## 재료 진행은 재료 목록에 표시하고 행동과 조합 제한만 이 줄에 둔다.
func _forge_actions(k: String, on_forged: Callable, on_pin: Callable) -> Control:
	var c: Dictionary = DB.C[k]
	var ok := run.can_forge(k)
	var br := UI.hbox(UI.SP_S)
	if ok:
		var fb := UI.btn("조합하기", func():
			if act("forge", [k]):
				toast("%s 조합 완료" % c.name, "gain")
				on_forged.call(), "", UI.BH_M)
		SheetStyle.main_btn(fb)
		fb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		br.add_child(fb)
	var pb := _pin_btn(k, on_pin)
	if forge_tree.pinned(k):
		SheetStyle.quiet_btn(pb)
	else:
		SheetStyle.sub_btn(pb)
	pb.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	br.add_child(pb)
	var reason := _forge_block_reason(k)
	if reason != "":
		var actions := UI.vbox(UI.SP_XS)
		actions.add_child(br)
		actions.add_child(UI.hint(reason))
		return actions
	return br


## 조합이 막힌 사유 (재료 말고) —— 없으면 "" (can_forge 의 재료 밖 조건과 같은 순서)
func _forge_block_reason(k: String) -> String:
	var lock_t := run.lock_text(k)      # 11/12 선점 · 사망으로 잠긴 장수
	if lock_t != "":
		return lock_t + " — 등용 불가"
	if int(DB.C[k].tier) >= 8 and run.has_myth():
		return "신화는 한 판에 하나"
	if DB.is_kiin(k) and (run.kiin_made.has(k) or run.have(k) > 0):
		return "기인은 한 판에 한 장"
	return ""


## 11/21 조합 진행 —— (모은 장 수, 필요한 장 수). 유니크 재료도 한 장으로 센다 (Run.miss_count 와 같은 셈: 필요 − 모음 = 부족)
func _forge_progress(out: String) -> Vector2i:
	var m := Run.mat_count(DB.RECOF.get(out, []))
	var got := 0
	var need := 0
	for q in m:
		need += int(m[q])
		got += mini(run.have(q), int(m[q]))
	var ni = Run.need_item(out)
	if ni != null:
		need += 1
		if int(run.bag.get(ni, 0)) > 0:
			got += 1
	return Vector2i(got, need)


## 능력의 머리 수치 [값, 그 이름] —— 원천 구조에서 (고유기 DB.ult_parts 의 hero · 고유 특기 ml 첫 칸 · 위세 aura_list 첫 칸 · 패업 조건). 없으면 []
func _abil_headline(k: String, kind: String) -> Array:
	var c: Dictionary = DB.C[k]
	match kind:
		"고유기":
			var u = DB.ult_of(k)
			if u != null:
				var parts := DB.ult_parts(u, int(c.tier))
				if not parts.hero.is_empty():
					return [str(parts.hero.v), str(parts.hero.l)]
		"고유 특기":
			for t in DB.trait_list(k):
				if t.unique and not (t.ml as Array).is_empty():
					var ch: Array = DB.mod_chip((t.ml as Array)[0])
					return [str(ch[0]), str(ch[1])]
		"위세", "기인":
			var al := DB.aura_list(k)
			for g in al.groups:
				for e in g.items:
					return [str(e[1]), "%s %s" % [g.who, e[0]]]
		"패업":
			if DB.AURA.has(k) and DB.AURA[k].has("paeup"):
				var pa: Dictionary = DB.AURA[k].paeup
				if str(pa.cond) != "none":
					return ["%d명 이상" % int(pa.need), "발동 조건"]
	return []


## 11/21 재료 줄의 유니크 칸 —— 그림 · 이름 · n/1 배지 (가방에 있으면 금 테, 없으면 흐리게). 누르면 아이템 시트
func _uniq_tile(ni: String) -> Control:
	var P := DB.PAL
	var n := int(run.bag.get(ni, 0))
	var have := n > 0
	var pc := PanelContainer.new()
	pc.custom_minimum_size = Vector2(56, 78)
	pc.add_theme_stylebox_override("panel", UI.flat(Color(P.ink3, 0.85) if have else Color(P.ink, 0.6), Color(P.gold, 0.85) if have else Color(P.gold, 0.28), 1, UI.R, 3))
	pc.mouse_filter = Control.MOUSE_FILTER_STOP
	var v := UI.vbox(2)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var art := ItemArt.View.new(ni, 34)
	art.custom_minimum_size = Vector2(34, 34)
	art.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if not have:
		art.modulate = Color(1, 1, 1, 0.45)
	v.add_child(art)
	var nl := UI.lbl(str(DB.IT[ni].name), UI.FS_TINY, P.gold if have else P.text_dim, true)
	nl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	nl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	nl.clip_text = true
	nl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(nl)
	var bd := SheetStyle.chip("%d/1" % mini(n, 1), SheetStyle.VAL if have else SheetStyle.WARN, "soft")
	bd.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(bd)
	pc.add_child(v)
	UI.tap(pc, func():
		UI.buzz()
		_item_sheet(ni))
	return pc


## 11/21 신화 상태 카드 (갈무리창 · 상세창 조합 탭) —— 신화를 이미 얻었으면(한 판에 하나) 그 카드, 아니면 유니크 재료 상태 (_unique_state). 해당 없으면 null
func _myth_status_card(out: String) -> Control:
	var owned: bool = int(run.pool().get(out, 0)) > 0
	if int(DB.C[out].tier) >= 8 and run.has_myth() and not owned:
		return SheetStyle.status_card(null, "crown", "신화는 한 판에 하나", "이미 신화를 얻어 이 장수는 조합할 수 없다", "lock")
	var ni = Run.need_item(out)
	if ni == null:
		return null
	var st := _unique_state(out, str(ni))
	var th := ItemArt.View.new(str(ni), 30)
	th.custom_minimum_size = Vector2(30, 30)
	return SheetStyle.status_card(th, "item", "유니크 %s" % DB.IT[ni].name, str(st.line), str(st.state), str(st.pill), st.tap)


## 11/21 유니크 재료 상태 —— 지금 규칙으로 말한다: 유니크는 DB.D.UNIQUE_PHASES 의 아침 아이템 보급(지금 2일차 오전 한 번)에서 셋 중 하나를 고르고 다시 뽑기 한 번.
## 상점 뽑기 · 토벌 장비 · 일반 보급에는 나오지 않는다 (Run.gain_item · gain_item_grade · _gacha_pick). 잠긴 신화(선점 · 사망)의 유니크는 보급에서 빠진다 (blocked_uniques).
## 예전 줄 「없음 · 2 · 4 · 6일차 아이템 보급」은 11/9(6일차) · 11/11(4일차) 보급이 없어진 뒤로 틀렸고, 지난 보급 · 열린 보급 · 다시 뽑기를 가리지 않았다.
## {state: used|ok|lock|open|reroll|wait|gone, line, pill, tap}
func _unique_state(out: String, ni: String) -> Dictionary:
	var see := func(): _item_sheet(ni)
	var open_offer := func():
		if can_act() and not run.uniq_offer.is_empty():
			_unique_sheet()
		else:
			_item_sheet(ni)
	if int(run.pool().get(out, 0)) > 0 and int(DB.C[out].tier) >= 8:
		return {"state": "used", "line": "조합 때 이 장수에게 영구 장착됐다", "pill": "장착", "tap": see}
	if int(run.bag.get(ni, 0)) > 0:
		return {"state": "ok", "line": "조합하면 이 장수에게 영구 장착된다", "pill": "보유", "tap": see}
	if run.blocked_uniques().has(ni):
		return {"state": "lock", "line": "신화가 잠겨(선점 · 사망) 보급에 나오지 않는다", "pill": "얻을 수 없음", "tap": see}
	if run.uniq_offer.has(ni):
		return {"state": "open", "line": "지금 아이템 보급에 있다 · 셋 중 하나만 받는다", "pill": "받으러", "tap": open_offer}
	if not run.uniq_offer.is_empty():
		if not run.uniq_rerolled:
			return {"state": "reroll", "line": "지금 보급 셋엔 없다 · 다시 뽑기 1번 남음", "pill": "보급 열기", "tap": open_offer}
		return {"state": "gone", "line": "보급 셋에 없고 다시 뽑기도 썼다", "pill": "이번 판 없음", "tap": see}
	var nx := _next_unique_phase()
	if nx >= 0:
		return {"state": "wait", "line": "%s 아이템 보급에서 셋 중 하나 · 다시 뽑기 1번" % _phase_label(nx), "pill": _phase_label(nx), "tap": see}
	return {"state": "gone", "line": "유니크 보급(%s)이 지났다 · 상점 · 토벌엔 없다" % _unique_days_text(), "pill": "이번 판 없음", "tap": see}


## 아직 오지 않은 가장 가까운 유니크 보급 페이즈 (없으면 -1) —— 페이즈 번호 = 일차×3 + (오전 0 · 오후 1 · 저녁 2), 보급은 그 페이즈 시작에 온다
func _next_unique_phase() -> int:
	var best := -1
	for x in DB.D.UNIQUE_PHASES:
		var p := int(x)
		if p > run.phase_idx() and (best < 0 or p < best):
			best = p
	return best


## 페이즈 번호 → "2일차 오전"
func _phase_label(p: int) -> String:
	return "%d일차 %s" % [floori(p / 3.0) + 1, Run.PHASE_N[p % 3]]


## 유니크 보급 날짜 전부 —— "2일차 오전" (여럿이면 " · ")
func _unique_days_text() -> String:
	var ps: Array = DB.D.UNIQUE_PHASES.map(func(x): return int(x))
	ps.sort()
	return " · ".join(ps.map(func(p): return _phase_label(p)))


# ───────── 징집 ─────────

func _page_draw() -> Control:
	if run.over:
		return _over_panel()
	var v := UI.vbox(UI.SP_S)
	var n := run.draws_n()
	# 11/15 사용자: "징집에서 내 기본카드는 항상 가장 위 같은 위치에" —— 기본패 8종 줄을 페이지 맨 위(머리띠 바로 아래)에 둔다.
	# 예전에는 큰 「징집하기」 카드 · 할 일 줄 · 추천 묶음(열림 · 닫힘 · 인연 줄) 아래라 그 높이에 따라 오르내렸다. 줄은 아래에서 채운다 (base_slot)
	var base_slot := UI.vbox(0)
	v.add_child(base_slot)
	if online != null and not can_act():      # 11/12 페이즈 개편 —— 징집 · 조합이 막힌 단계면 이유 한 줄 (버튼은 잠긴다)
		v.add_child(UI.hint(online.block_reason("draw")))
	if run.day > Run.HP_LATE_START:      # 11/25 4일차부터 패배 민심 피해가 매일 커진다 (Run.hp_late_mul) —— 11/25 UX: 칸 대신 작은 한 줄 (보유 장수 자리를 깎지 않게)
		v.add_child(UI.rich("[color=#D9A64B]%d일차 난세[/color] [color=#A89574]· 패배 민심 피해 ×%s[/color]" % [run.day + 1, str(snappedf(Run.hp_late_mul(run.day), 0.01))], UI.FS_CAP))

	# 할 일 —— 기호 타일 한 줄 (11/7 사용자: 세로로 너무 컸다 —— 기호 · 제목을 옆으로 나란히 높이 34, 한 줄 최대 5칸)
	# 11/14 UI 다듬기 2단계 (감사 #2 · #6-1): 오늘 징집을 아직 안 했으면 할 일 줄 위에 큰 주 행동 카드 「징집하기」 —— 코치 말풍선(1/4)이 이것을 가리킨다.
	#   징집을 마치면 예전처럼 할 일 줄의 작은 완료 칸(✓ 징집)으로 줄어든다
	# 11/25 UX: 징집은 준비 단계가 시작될 때 자동으로 받는다 —— 큰 「징집하기」 카드는 뺐다. 아직 못 받은 상태(옛 서버 등)면 할 일 줄의 작은 칸으로 받는다
	_draw_cta_node = null
	var acts := UI.grid(70, 4)
	if n > 0 and not run.drawn:
		acts.add_child(UI.tile_act("draw", "징집 %d" % n, "", func(): act("do_draw"), "pri", false, not can_act()))
	# 11/2 사용자: 타일 아래 설명 글(기본패 14장 · 11종 중 고르기)은 빼고 낮게. 선택권은 타일 하나 —— 고르다 닫아도 「일반 ×2」 같은 타일이 따로 생기지 않고 같은 타일로 다시 연다
	if shop_on() or gacha_on():      # 11/13 사용자: 상점은 기본패 징집 바로 다음 칸 (군량 값은 머리띠 민심 위에 늘 보인다 —— 징집 탭 머리의 「군량 N [상점]」 줄은 걷었다)
		acts.add_child(UI.tile_act("grain", "상점", "", _shop_sheet, "gold" if run.grain >= Run.GACHA_PRICE else ""))
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
			if not run.picked:      # 11/17 이미 받았으면 다시 보내지 않는다 (서버 기록에 헛명령이 쌓였다)
				act("begin_picks", ["phase", -1])
			if not rnd:
				picker(tt), "gold", false, not can_act())
		tb.add_theme_color_override("font_color", DB.TIER[tt].c)
		for l in tb.find_children("*", "Label", true, false):      # 11/22 사용자: 10장 넘으면 「희귀 1」 로 잘려 보였다 —— 수는 자르지 않는다
			l.clip_text = false
			l.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
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
	if acts.get_child_count() > 0:
		v.add_child(acts)
	# 11/25 UX: 추천 조합(_goal_block)은 조합 탭의 목표 보드로 옮겼다 —— 징집 탭은 받은 것 · 가진 장수가 주인공

	# 11/7 사용자: '아이템 이름 · 효과' 칩은 획득 순간 가운데 띠(_item_band)로, '소식 N' 칩은 머리띠 ☰ 아래 버튼으로 —— 칩 줄은 없다

	# 보유 카드만 (11/2 사용자) —— 등급별로 열 수를 달리한다: 초월 위 4열 · 일반~전설 6열 (남은 높이에서 스크롤), 기본 병졸 8종은 맨 아랫줄 8열 고정
	var p := run.pool()
	var mats := _ready_mats()
	var hand_tile := func(k: String, n: int, h: float) -> MiniTile:
		var t := mtile(k, n)
		t.custom_minimum_size = Vector2(30, h)
		if n > 0 and shop_on() and Run.sellable(k):      # 11/13 꾹 누르면 판매
			t.on_hold = _sell_sheet
		if run.on_board(k) > 0:
			t.badge = "편성 %d" % run.on_board(k) if h >= 90 else "편성"
			t.badge_quiet = true
			t.badge_col = Color(DB.PAL.ink4, 0.95)
		t.up = mats.has(k)
		t.dim = n <= 0
		return t
	var hv := UI.vbox(UI.SP_S)
	hv.size_flags_vertical = Control.SIZE_EXPAND_FILL
	# 11/7 사용자: "보유 N장 · PV" · "▲ 지금 조합 재료" 머리줄은 뺐다 (타일의 ▲ 표시는 그대로)
	var hs := UI.scroll()
	hs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var inner := UI.vbox(UI.SP_S)
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
	if by.keys().all(func(x): return x is int and x <= 1):      # 11/14 감사 #2: 장수(일반 위)가 하나도 없으면 빈 상태 카드
		inner.add_child(_draw_empty())
	# 전설 6열 96 · 희귀 6열 80 · 고급 · 일반 7열 72 —— 지금처럼 등급마다 한 묶음 (기인은 위 [초월 | 기인] 줄로 올라갔다. 폭 56 아래는 작은 칸 그리기)
	# 11/20 전설 칸 높이 84 → 96 (지휘 결정 —— 한 화면에 들어가는 줄 수가 줄어드는 것은 감수)
	for grp in [[[5], 6, 96.0], [[4], 6, 80.0], [[3, 2], 7, 72.0]]:
		var g := UI.grid(30, 6)
		g.max_cols = grp[1]
		for t in grp[0]:
			for k in by.get(t, []):
				g.add_child(hand_tile.call(k, p[k], grp[2]))
		if g.get_child_count() > 0:
			# 11/14 UI 4단계: 묶음이 줄 간격으로만 나뉘어 어디서 등급이 바뀌는지 안 보였다 —— 작은 등급 머리글 (등급색 글자 + 장 수, 높이 한 줄)
			var tn: Array = []
			var cnt := 0
			for t in grp[0]:
				if by.has(t):
					tn.append(DB.TIER[t].n)
					cnt += by[t].size()
			var hl := UI.lbl("%s  %d" % [" · ".join(tn), cnt], UI.FS_CAP, DB.TIER[grp[0][0]].c.lightened(0.2), true)
			inner.add_child(hl)
			inner.add_child(g)
		else:
			g.free()
	hs.add_child(inner)
	var base := UI.grid(30, 4)      # 11/6 사용자: 기본병 8종은 맨 윗줄에 (조합 재료의 출발점이라 먼저 본다) —— 11/15 페이지 맨 위 고정 자리로
	base.max_cols = 8
	for k in Run.sort_cards(DB.BASE.duplicate()):
		base.add_child(hand_tile.call(k, int(p.get(k, 0)), HAND_TILE.y))
	base_slot.add_child(base)
	_base_row = base
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
	var b := UI.btn("", func(): _toggle("draw_fold"), "ghost", UI.BH_XS)
	var hb := UI.hbox(UI.SP_S)
	hb.alignment = BoxContainer.ALIGNMENT_CENTER
	hb.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var items := [["완성된 장수 펼치기 ▾" if fold else "완성된 장수 접기 ▴", DB.PAL.bamboo]]
	for c in counts:
		if c[2] > 0:
			items.append(["%s %d" % [c[0], c[2]], c[1]])
	for it in items:
		var l := UI.lbl(it[0], UI.FS_CAP, it[1])
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
	var h := UI.hbox(UI.SP_S)
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
	v.add_child(UI.rich("[b][color=%s]%s[/color][/b] [color=#A89574]%d[/color]" % [col.to_html(false), sp[1], n], UI.FS_CAP))
	var g := UI.grid(sp[2], 5)
	for k in ks:
		g.add_child(hand_tile.call(k, int(p[k]), sp[3]))
	v.add_child(g)
	pc.add_child(v)
	return pc


## 11/25 큰 「징집하기」 카드(_draw_cta)는 자동 징집으로 뺐다 —— _draw_cta_node 는 첫 판 안내가 묻는 자리라 null 로 남긴다
var _base_row: Control = null      # 징집 탭 맨 위 기본패 줄 (점검 · 캡처 · 첫 판 안내가 자리를 잰다)
var _draw_cta_node: Control = null


## 장수가 아직 없을 때의 빈 상태 카드 (11/14 감사 #2) —— 기호 + 두 줄 설명 (+ 징집을 마쳤으면 조합 탭으로 가는 버튼)
func _draw_empty() -> Control:
	var gb: Button = null
	if run.drawn:
		gb = UI.btn_secondary("조합하러 가기", func(): go("forge"), UI.BH_S)
	return UI.empty("draw", "아직 장수가 없다", "징집으로 기본패를 모으고, 같은 카드를 맞춰 조합 탭에서 장수로 올린다.", gb)


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
		b.add_child(UI.empty("news", "아직 소식이 없다", "다른 세력이 장수를 등용하거나 무너지면 여기에 쌓인다."))      # 11/14 UI 4단계: 빈 상태 공용 부품
	var react: bool = online != null and online.in_game and int(online.room.get("emote_n", 0)) > 0      # 11/12 온라인 —— 소식 줄마다 반응(폭소 · 놀람 · 좋아요)을 한 번에
	for nw in run.news:
		var line: RichTextLabel
		if not DB.C.has(str(nw.get("unit", ""))):      # 11/9 온라인 소식 —— 서버가 글로 보낸 소식 (멸망 · 퇴장 등). 장수가 있으면 아래 등용 줄
			var who := str(nw.get("who", ""))
			var tx := str(nw.get("text", ""))
			if tx.begins_with(who):
				who = ""
			line = UI.rich(("[b]%s[/b] " % who if who != "" else "") + tx + _news_when(nw), UI.FS_BODY)
		else:
			line = UI.rich("[b]%s[/b]가 %s [color=#A89574]%s 등용[/color]%s" % [nw.who, UI.card_bb(nw.unit), DB.tier_name(nw.unit), _news_when(nw)], UI.FS_BODY)
		if not react:
			b.add_child(line)
			continue
		var h := UI.hbox(UI.SP_XS)
		line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(line)
		h.add_child(online.react_row(28.0))
		b.add_child(h)


## 소식 옆의 시점 —— 「(3일차 아침)」 옅은 글씨. 옛 항목(when 없음)은 없다 (11/10)
func _news_when(nw: Dictionary) -> String:
	var w := str(nw.get("when", ""))
	return " [color=#A89574](%s)[/color]" % w if w != "" else ""


func _item_sheet(id: String) -> void:
	var it: Dictionary = DB.IT[id]
	var b := open_sheet(it.name)
	b.add_child(item_box(id, run.bag.get(id, 0)))
	b.add_child(UI.hint("%s 전용 %s · %s. 편성 탭에서 칸을 눌러 장착한다.%s" % [it.tag, DB.ISLOT_NAME[DB.item_slot(id)], it.grade, " 신화 장수 조합 재료이기도 하다." if it.use == "myth" else ""]))
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
	var row := UI.hbox(UI.SP_XS)
	var sa := _safe_insets()
	var head_h: float = _sheet.get_child(0).get_child(0).get_combined_minimum_size().y
	row.custom_minimum_size.y = maxf(300.0, (size.y - sa.position.y) * 0.98 - head_h - sa.size.y - 34.0)      # 시트 머리 · 본문 여백(6 + 24)을 뺀 나머지
	for id in run.uniq_offer:
		var iid: String = id
		var it: Dictionary = DB.IT[iid]
		var col := UI.vbox(UI.SP_XS)
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var ih := UI.hbox(UI.SP_XS)
		var th := ItemArt.View.new(iid, 30)
		th.custom_minimum_size = Vector2(30, 30)
		ih.add_child(th)
		var nl := UI.lbl(it.name, UI.FS_CAP, DB.PAL.gold, true)
		UI.wrap_text(nl)
		nl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		nl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		ih.add_child(nl)
		col.add_child(ih)
		col.add_child(_kv_grid(UI.item_text(iid), 10))
		for k in DB.by_tier(8).filter(func(x): return Run.need_item(x) == iid):
			var kk: String = k
			var art := _art_crop(kk, Vector2(120, 120), false)      # 11/3 사용자: 보급 창은 기본 장수 그림 (신화 그림은 갈무리 창에만)
			art.mouse_filter = Control.MOUSE_FILTER_STOP
			UI.tap(art, func():      # 11/20 조작: 탭 판정 (UI.tap)
				UI.buzz()
				recipe_sheet(kk))      # 11/3 사용자: 디테일이 아니라 간략창으로
			col.add_child(art)
			var gn := UI.lbl(DB.C[kk].name, UI.FS_CAP, DB.tier_color(kk), true)
			UI.wrap_text(gn)
			gn.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			col.add_child(gn)
			# 11/7 사용자: 이 재료로 만드는 장수의 병종 —— 기호 + 이름
			var tr := UI.hbox(UI.SP_XS)
			tr.alignment = BoxContainer.ALIGNMENT_CENTER
			var ti := TextureRect.new()
			ti.texture = DB.ICON.get(DB.C[kk].tag)
			ti.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			ti.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			ti.custom_minimum_size = Vector2(14, 14)
			ti.modulate = DB.PAL.bamboo
			tr.add_child(ti)
			tr.add_child(UI.lbl("%s · %s" % [DB.C[kk].tag, DB.tier_name(kk)], UI.FS_CAP, DB.PAL.bamboo))
			col.add_child(tr)
			var tb := TraitBoard.new()
			tb.fixed = true
			col.add_child(tb.setup(kk, 3))
			_ability_rows(col, kk, 10, true, true, ["패업"])      # 고유 특기 · 위세 · 고유기 + 기질 —— 디테일창과 같은 칸 (좁은 세로 칸). 패업은 뺀다 (11/9)
		var sp := Control.new()
		sp.size_flags_vertical = Control.SIZE_EXPAND_FILL
		col.add_child(sp)
		col.add_child(UI.btn("받기", func(): _confirm_unique(iid), "pri", UI.BH_S))
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
				toast("바꿀 아이템이 없다"), "ghost", UI.BH_S))


func _confirm_unique(iid: String) -> void:
	var scroll_y := _sheet_scroll.scroll_vertical
	var b := open_sheet("아이템을 받을까요?", DB.PAL.gold)
	b.add_child(UI.lbl(str(DB.IT[iid].name), UI.FS_TITLE, DB.PAL.paper, true))
	b.add_child(UI.hint("확정하면 이번 보급에서 다른 아이템을 고를 수 없습니다."))
	var row := UI.hbox(UI.SP_S)
	var cancel := UI.btn("취소", func():
		_unique_sheet()
		_restore_sheet_scroll.call_deferred(scroll_y), "ghost")
	var accept := UI.btn("받기 확정", func():
		if act("pick_unique", [iid]):
			Sfx.play("gain")
			close_sheet(), "pri")
	for button in [cancel, accept]:
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(button)
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
	b.add_child(UI.lbl("한 장을 누르면 바로 받는다", UI.FS_CAP, DB.PAL.text_dim))      # 11/14 UI 4단계: 누르면 무엇이 되는지 한 줄
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
	# 11/25 UX: 판단 근거 —— 갈무리 목표(★)와 추천 목표의 재료 가운데 이 등급에서 고를 수 있고 아직 모자란 것을 맨 위 한 묶음으로, 타일 아래 "○○ 재료"
	# (기록: 선택권 창에 머무는 시간 중앙 12초 · 상위 10% 39초 —— 40명 안팎을 얼굴 · 이름만으로 훑었다)
	var why := {}      # 카드 -> [[목표 인물 이름, 갈무리인가] …]
	var note := func(target: String, pinned_: bool) -> void:
		var seen_k := {}
		var w2 := func(nd: Dictionary, f: Callable) -> void:
			for c in nd.get("kids", []):
				if c.has("k") and not c.ok and not seen_k.has(c.k):
					seen_k[c.k] = true
					if not why.has(c.k):
						why[c.k] = []
					why[c.k].append([DB.person(target), pinned_])
				f.call(c, f)
		w2.call(forge_tree._node(target, 1, 0, target, "", true), w2)
	for pk in pins:
		note.call(pk, true)
	var rec: Array = _forge_goals(DB.D.RECDEF)
	var seen_p := {}
	for o in rec:
		seen_p[DB.person(o)] = true
	rec += run.bond_goals(seen_p, 6)
	for o in rec:
		if not pins.has(o):
			note.call(o, false)
	var top_ks := []
	for tag in DB.D.TAGORDER:
		for k in Run.pickable(t, tag):
			if why.has(k):
				top_ks.append(k)
	top_ks.sort_custom(func(x, y):      # 갈무리 재료 먼저 · 여러 목표에 쓰이는 것 먼저 (같으면 원래 차례)
		var px: bool = why[x].any(func(e): return e[1])
		var py: bool = why[y].any(func(e): return e[1])
		if px != py:
			return px
		return why[x].size() > why[y].size())
	if not top_ks.is_empty():
		var tcols := 5 if t <= 4 else 4
		var ttw := floorf((full - gap * (tcols - 1)) / tcols)
		var tth := ttw * (1.3 if t <= 4 else 1.42)
		var sec := UI.vbox(UI.SP_XS)
		sec.add_child(UI.eyebrow("목표의 재료" if top_ks.size() <= tcols else "목표의 재료 · %d장 중 %d" % [top_ks.size(), tcols]))
		var tg := GridContainer.new()
		tg.columns = tcols
		tg.add_theme_constant_override("h_separation", int(gap))
		tg.add_theme_constant_override("v_separation", int(gap))
		for k in top_ks.slice(0, tcols):      # 한 줄만 (갈무리 재료 먼저 · 남는 칸은 추천 재료) —— 나머지는 아래 병종 줄에서 ★ 로 보인다
			var cv := UI.vbox(1)
			cv.add_child(make_tile.call(k, ttw, tth))
			var ws: Array = why[k]
			var pinned_any: bool = ws.any(func(e): return e[1])
			var first: Array = ws.filter(func(e): return e[1])[0] if pinned_any else ws[0]
			var cl := UI.lbl(("%s 재료" % first[0]) + (" +%d" % (ws.size() - 1) if ws.size() > 1 else ""), UI.FS_TINY, DB.PAL.gold.lightened(0.15) if pinned_any else DB.PAL.bamboo)
			cl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			cl.custom_minimum_size.x = ttw
			cl.clip_text = true
			cv.add_child(cl)
			tg.add_child(cv)
		sec.add_child(tg)
		b.add_child(UI.panel(sec, 8))
	var avail_h: float = vp.y * 0.98 - 120.0 - (0.0 if top_ks.is_empty() else 138.0)      # 시트 머리 · 아래 여백 (· 위 재료 묶음 한 줄)
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
			# 11/14 UI 4단계: 기호만으로는 처음 보는 사람이 병종을 모른다 —— 기호 아래 병종 이름 (작은 글자)
			var iv := UI.vbox(2)
			iv.alignment = BoxContainer.ALIGNMENT_CENTER
			iv.custom_minimum_size = Vector2(icon_w, th)
			var ic := TextureRect.new()
			ic.texture = DB.ICON.get(tag)
			ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			ic.custom_minimum_size = Vector2(icon_w, 20)
			ic.modulate = Color(DB.PAL.bamboo, 0.85)
			iv.add_child(ic)
			var il := UI.lbl(str(tag), UI.FS_TINY, DB.PAL.text_dim)
			il.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			iv.add_child(il)
			row.add_child(iv)
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
		var jump := UI.hbox(UI.SP_XS)
		for tag in DB.D.TAGORDER:
			var ks := Run.pickable(t, tag)
			if ks.is_empty():
				continue
			var grp := UI.vbox(UI.SP_S)
			grp.add_child(UI.eyebrow("%s %d" % [tag, ks.size()]))
			var g := GridContainer.new()
			g.columns = cols
			g.add_theme_constant_override("h_separation", int(gap))
			g.add_theme_constant_override("v_separation", 8)
			for k in ks:
				g.add_child(make_tile.call(k, tw, th))
			grp.add_child(g)
			groups[tag] = grp
			var jb := TouchButton.new()
			jb.hit.x = 0.0
			jb.custom_minimum_size = Vector2(0, UI.BH_S)
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


# ───────── 유닛 판매 · 군량 상점 (11/13) ─────────

## 판매 · 상점을 쓰는 판인가 —— 혼자 하기는 늘, 온라인은 방 옵션(방 정보 sell —— 옛 서버는 없어 숨긴다)
func shop_on() -> bool:
	if run == null or not run.sell_on:
		return false
	return online == null or bool(online.room.get("sell", false))


## 군량으로 아이템을 뽑을 수 있는 판인가 (11/13) —— 혼자 하기는 늘, 온라인은 서버가 뽑기를 아는 판(방 정보 gacha —— 옛 서버는 없어 숨긴다)
func gacha_on() -> bool:
	if run == null:
		return false
	return online == null or bool(online.room.get("gacha", false))


## 상점 시트 —— 아이템 뽑기(1회 · 10회 · 천장) + 기본 · 고급 · 희귀 · 전설 랜덤권 + 준비 중인 칸. got: 방금 뽑은 아이템 id 들 (결과를 맨 위에)
func _shop_sheet(got := []) -> void:
	var b := open_sheet("군량 상점")
	var have := UI.hbox(UI.SP_S)
	have.add_child(UI.lbl("가진 군량", UI.FS_BODY, DB.PAL.text_dim))
	have.add_child(UI.grain(str(run.grain), UI.FS_LABEL))
	var inc := UI.lbl("페이즈마다 +%d" % Run.GRAIN_PER_PHASE, UI.FS_CAP, DB.PAL.text_dim)
	inc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inc.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	have.add_child(inc)
	b.add_child(have)
	if not can_act():
		b.add_child(UI.hint(online.block_reason("draw") if online != null else ""))
	if gacha_on():
		_gacha_block(b, got)
	if not shop_on():
		_shop_soon(b)
		return
	b.add_child(UI.eyebrow("장수 랜덤권"))
	for t in Run.SHOP_TIERS:
		var tt: int = t
		var price := Run.shop_price(tt)
		var row := UI.hbox(UI.SP_S)
		var nm := UI.lbl("%s 랜덤권" % DB.TIER[tt].n, UI.FS_LABEL, DB.TIER[tt].c, true)
		nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(nm)
		var bb := _buy_btn("구매", price, func():
			if act("buy", [tt]) != null:
				_shop_sheet(), false)
		bb.custom_minimum_size.x = maxf(bb.custom_minimum_size.x, 120)
		row.add_child(bb)
		b.add_child(UI.panel(row, 8))
	_shop_soon(b)


## 아이템 뽑기 칸 (11/13) —— 결과 · 설명 · 천장 · [1회] [10회] · 확률
func _gacha_block(b: VBoxContainer, got: Array) -> void:
	b.add_child(UI.eyebrow("아이템 뽑기"))
	if not got.is_empty():
		var order: Array = DB.IGRADE_ORDER
		var ids: Array = got.duplicate()
		ids.sort_custom(func(x, y): return order.find(DB.IT[x].grade) < order.find(DB.IT[y].grade))
		var top_g: String = DB.IT[ids[0]].grade
		b.add_child(UI.lbl("뽑은 아이템 %d개%s" % [ids.size(), " —— 고대 등급!" if top_g == "고대" else ""], UI.FS_BODY, Color(DB.D.IGRADE[top_g]).lightened(0.25), true))
		var f := UI.grid(170, 6)
		for id in ids:
			f.add_child(item_box(id))
		b.add_child(f)
	var v := UI.vbox(UI.SP_S)
	var left := maxi(1, Run.GACHA_PITY - int(run.gacha_pity))
	v.add_child(UI.rich("[color=#%s][b]고대 확정까지 %d번[/b][/color]" % [Color(DB.D.IGRADE["고대"]).lightened(0.2).to_html(false), left], UI.FS_BODY))
	var row := UI.hbox(UI.SP_S)
	var short := []
	for n in [1, Run.GACHA_TEN]:
		var nn: int = n
		var cost := Run.gacha_cost(nn)
		var gb := _buy_btn("%d회 뽑기" % nn, cost, func():
			var r = act("gacha", [nn])
			if r != null:
				_shop_sheet(r)
				_gacha_fx(r), nn == 1)      # 11/20 금색 주 버튼은 「1회 뽑기」 하나만
		gb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(gb)
		if run.grain < cost:
			short.append("%d회는 군량 %d 더 필요" % [nn, cost - run.grain])
	v.add_child(row)
	if not short.is_empty():
		v.add_child(UI.lbl(" · ".join(short), UI.FS_CAP, DB.PAL.text_dim))
	var tot := 0.0
	for g in Run.GACHA_W:
		tot += float(Run.GACHA_W[g])
	var odds := []
	for g in DB.IGRADE_ORDER:
		if Run.GACHA_W.has(g):
			odds.append("%s %d%%" % [g, roundi(float(Run.GACHA_W[g]) / tot * 100)])
	v.add_child(UI.hint(" · ".join(odds)))
	b.add_child(UI.panel(v, 8))


## 상점 구매 버튼 (11/14 감사 #4) —— 어디서나 같은 모양: 주 버튼 안에 [글자 · 쌀가마 값]. 군량이 모자라거나 지금 못 사면 흐린 비활성
##   (예전엔 살 수 있는 쪽만 금 테두리 · 못 사는 쪽은 남색이라 [1회][10회]가 고르기 토글처럼 보였다)
## 11/20 UI 다듬기 2차: 금색 주 버튼이 한 화면에 다섯(1회 · 10회 · 구매 넷)이라 위계가 없었다 —— main 인 것(1회 뽑기)만 금, 나머지는 보조(먹색 면 + 얇은 선). 값의 금색 쌀가마는 그대로
func _buy_btn(pre: String, cost: int, cb: Callable, main := true) -> Button:
	var b := UI.grain_btn(pre, str(cost), cb, "pri" if main else "", UI.BH_M)
	if not main:
		UI.btn_styles(b, UI.flat(DB.PAL.ink3, Color(DB.PAL.paper, 0.22), 1, UI.R, 10), UI.flat(DB.PAL.ink4, Color(DB.PAL.paper, 0.35), 1, UI.R, 10), UI.flat(DB.PAL.ink4, DB.PAL.gold, 1, UI.R, 10))
	b.disabled = run.grain < cost or not can_act()
	if b.disabled:      # 비활성 —— 버튼 모양(먹 바탕 + 얇은 선)은 남기고 안의 글자 · 값만 흐리게
		b.add_theme_stylebox_override("disabled", UI.flat(DB.PAL.ink2, Color(DB.PAL.paper, 0.16), 1, UI.R, 10))
		b.get_child(b.get_child_count() - 1).modulate.a = 0.4
	return b


## 고대 아이템을 뽑았다 (11/13) —— 가운데 띠 「고대 아이템 획득」 + 이름 · 번쩍임 · 완성 소리. 온라인에서는 서버가 다른 사람에게 속보를 보낸다 (Room · UrgentBand "item")
func _gacha_fx(got: Array) -> void:
	var anc: Array = got.filter(func(id): return DB.IT.has(id) and str(DB.IT[id].grade) == "고대")
	if anc.is_empty():
		return
	var col := Color(DB.D.IGRADE["고대"]).lightened(0.15)
	Sfx.play("forge", 2.0)
	band("고대 아이템 획득", col, " · ".join(anc.map(func(id): return str(DB.IT[id].name))))


## 군량으로 열릴 다른 쓰임새 —— 아직 없는 칸을 잠긴 채로 보여 준다 (11/13 사용자: 추후 군량을 통한 다른 시스템 도입을 암시하는 UI)
func _shop_soon(b: VBoxContainer) -> void:
	b.add_child(UI.eyebrow("준비 중"))
	var row := UI.hbox(UI.SP_S)
	for nm in ["진형 강화", "군령", "???"]:
		var pc := PanelContainer.new()
		pc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		pc.add_theme_stylebox_override("panel", UI.flat(DB.PAL.ink2, Color(DB.PAL.bamboo_dim, 0.5), 1, UI.R, 8))
		var v := UI.vbox(2)
		var l1 := UI.lbl("🔒 " + nm, UI.FS_BODY, DB.PAL.text_dim, true)
		l1.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(l1)
		var l2 := UI.lbl("군량으로 열립니다", UI.FS_CAP, Color(DB.PAL.text_dim, 0.7))
		l2.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(l2)
		pc.add_child(v)
		pc.modulate = Color(1, 1, 1, 0.75)
		row.add_child(pc)
	b.add_child(row)


## 꾹 누른 보유 카드 —— 판매 한 줄 시트
## 11/15 사용자: 판매할 때 갈무리된 재료면 한 번 더 알린다 —— k 가 갈무리 장수(또는 그 재료 · 아래 재료까지)이고 팔면 필요한 수보다 모자라게 되면
## 그 갈무리 장수 이름 (차례가 가장 앞인 것), 아니면 "". 넉넉히 가진 재료(팔아도 필요한 수가 남는다)는 묻지 않는다
func _sell_pin_target(k: String) -> String:
	if forge_tree.pins.is_empty():
		return ""
	if forge_tree.pinned(k):
		return k
	var nd: Dictionary = ForgeTree.needs_of(run, forge_tree.pins)
	if nd.has(k) and run.have(k) - 1 < int(nd[k].need):
		return str(nd[k].root)
	return ""


## 갈무리 재료 판매 —— 한 번 더 묻는 시트
func _sell_pin_confirm(k: String, target: String) -> void:
	var b := open_sheet("갈무리 재료 판매", DB.PAL.danger)
	var own := target == k
	var wl := UI.rich("[color=#E9E3D3][b]%s[/b][/color]%s — 갈무리한 [color=#D9A64B][b]%s[/b][/color]%s. 팔면 조합이 그만큼 멀어진다. 그래도 팔까?" % [
		DB.C[k].name, "" if own else " (보유 %d장)" % run.have(k), DB.C[target].name, " 장수다" if own else "의 재료다"], UI.FS_LABEL)
	UI.wrap_text(wl)
	b.add_child(wl)
	var tr := UI.hbox(UI.SP_M)
	tr.alignment = BoxContainer.ALIGNMENT_CENTER
	var t1 := mtile(k, run.have(k))
	t1.custom_minimum_size = Vector2(56, 78)
	tr.add_child(t1)
	if not own:
		var ar := UI.lbl("→", UI.FS_TITLE, DB.PAL.bamboo)
		ar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		tr.add_child(ar)
		var t2 := mtile(target, -1)
		t2.custom_minimum_size = Vector2(56, 78)
		t2.set_pin(true, false)
		tr.add_child(t2)
	b.add_child(tr)
	var sb := UI.grain_btn("그래도 판매", "+%d" % Run.sell_price(k), func():
		close_sheet()
		act("sell", [k]), "warn", UI.BH_M)
	sb.disabled = not can_act()
	b.add_child(sb)
	b.add_child(UI.btn("팔지 않는다", func(): close_sheet(), "ghost"))


func _sell_sheet(k: String) -> void:
	if not DB.C.has(k) or run.have(k) <= 0:
		return
	var pin_t := _sell_pin_target(k)
	var b := open_sheet(DB.C[k].name, DB.tier_color(k).lightened(0.2))
	var only_board: bool = int(run.inv.get(k, 0)) <= 0
	var hr := UI.hbox(UI.SP_S)
	hr.add_child(UI.lbl("%s · 보유 %d장%s · 지금" % [DB.tier_name(k), run.have(k), " (편성 %d)" % run.on_board(k) if run.on_board(k) > 0 else ""], UI.FS_BODY, DB.PAL.text_dim))
	hr.add_child(UI.grain(str(run.grain), UI.FS_BODY, DB.PAL.gold, false))
	b.add_child(hr)
	var rare := int(DB.C[k].tier) >= 5 or DB.is_kiin(k)
	if only_board:
		b.add_child(UI.hint("편성에 올린 장수다 —— 팔면 편성에서 빠진다."))
	if rare:
		var wl := UI.lbl("%s 장수다 —— 팔면 되돌릴 수 없다." % DB.tier_name(k), UI.FS_BODY, DB.PAL.danger)
		UI.wrap_text(wl)
		b.add_child(wl)
	if pin_t != "":
		var pl := UI.lbl("★ 갈무리한 %s%s." % [DB.C[pin_t].name, " 장수다" if pin_t == k else "의 재료다"], UI.FS_BODY, DB.PAL.gold)
		UI.wrap_text(pl)
		b.add_child(pl)
	var sb := UI.grain_btn("판매", "+%d" % Run.sell_price(k), func():
		if pin_t != "":      # 갈무리 재료 —— 한 번 더 묻는다
			_sell_pin_confirm(k, pin_t)
			return
		close_sheet()
		act("sell", [k]), "warn" if (only_board or rare or pin_t != "") else "pri", UI.BH_M)
	sb.disabled = not can_act()
	sb.modulate.a = 0.5 if sb.disabled else 1.0
	b.add_child(sb)
	if not can_act() and online != null:
		b.add_child(UI.hint(online.block_reason("draw")))
	b.add_child(UI.btn("장수 정보", func(): card_info(k), "ghost"))


## 판매 전에 확인을 받을 장수 (11/14 감사 #3) —— 전설 이상 · 기인 · 손패에 없고 편성에만 있는 장수
func _sell_needs_confirm(k: String) -> bool:
	return int(DB.C[k].tier) >= 5 or DB.is_kiin(k) or (int(run.inv.get(k, 0)) <= 0 and run.on_board(k) > 0)


## 장수 정보창의 [판매] —— 확인이 필요한 장수(_sell_needs_confirm)는 판매 시트로. 갈무리 재료는 바로 '한 번 더' 확인 시트로 (11/15)
func _sell(k: String) -> void:
	var pin_t := _sell_pin_target(k)
	if pin_t != "" and not _sell_needs_confirm(k):
		_sell_pin_confirm(k, pin_t)
		return
	if _sell_needs_confirm(k):
		_sell_sheet(k)
		return
	act("sell", [k])
	if run.have(k) > 0:
		card_info(k)
	else:
		close_sheet()


## 지금 편성할 수 있는가 —— 온라인은 act_form (아침 · 저녁 준비)
func can_form() -> bool:
	return online == null or online.can_act("form")


# ───────── 카드 상세 ─────────

func card_info(k: String, tab := -1, inyeon_name := "") -> void:
	if tab < 0:
		tab = 0
		if _route.get("kind") == "card" and _route.get("k") == k:
			tab = int(_route.get("tab", 0))
			inyeon_name = str(_route.get("inyeon", ""))
	_route_enter("card", k)
	_route["inyeon"] = inyeon_name
	var c: Dictionary = DB.C[k]
	var p := run.pool()
	var b := open_sheet(c.name, DB.tier_color(k).lightened(0.2))
	var ult0 = DB.ult_of(k) if DB.has_ult(k) else null
	var temper := Battle.temper_name(c, ult0) if ult0 != null else ""
	if temper != "":
		_sheet_title.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		_sheet_title.custom_minimum_size.x = minf(220.0, _sheet_title.get_theme_font("font").get_string_size(str(c.name), HORIZONTAL_ALIGNMENT_LEFT, -1, _sheet_title.get_theme_font_size("font_size")).x + 2.0)
		_sheet_temper.text = temper
		_sheet_temper.show()
	sheet_head(k)      # 11/21 이름 아래 등급 리본 · 세력 · 병종 · 피해 종류 + 등급 색 머리 바탕 (갈무리창 · 전투 장수창과 같은 머리, SheetStyle)
	if DB.RECOF.has(k) and not DB.is_foe(k):
		var action_row := UI.hbox(UI.SP_S)
		var pg := _forge_progress(k)
		var progress := UI.vbox(2)
		progress.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		progress.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		progress.add_child(UI.lbl("조합 재료 %d/%d" % [pg.x, pg.y], UI.FS_CAP, DB.PAL.bamboo, true))
		progress.add_child(SheetStyle.meter(pg.x, pg.y))
		progress.add_child(UI.lbl("%d장 부족" % (pg.y - pg.x) if pg.x < pg.y else "재료 갖춤", UI.FS_CAP, DB.PAL.text_dim))
		action_row.add_child(progress)
		var reopen := func():
			_back_nav = true
			card_info(k)
		var pin := _pin_btn(k, reopen)
		SheetStyle.quiet_btn(pin) if forge_tree.pinned(k) else SheetStyle.sub_btn(pin)
		action_row.add_child(pin)
		var recipe_button := UI.btn("조합  ›", func(): recipe_sheet(k), "", UI.BH_M)
		SheetStyle.sub_btn(recipe_button)
		recipe_button.custom_minimum_size.x = 104
		action_row.add_child(recipe_button)
		b.add_child(action_row)
	var top := UI.hbox(UI.SP_M)
	var big := CardView.new().setup(k, Vector2(96, 136))
	big.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	top.add_child(big)      # 11/20 역할은 큰 카드 초상 위에 (CardView.show_role)
	# 초상 오른쪽 (11/3 사용자: 초상과 높이를 맞춘다) —— 능력치 다섯 칸 · 특기판 · 접힌 고유 특기 · 위세 · 고유기
	var st := UI.vbox(2)
	st.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	st.add_child(SheetStyle.stat_block(c.atk, c["def"], c.spd, DB.INT_TAGS.has(c.tag)))      # 11/21 갈무리창과 같은 능력치 판
	# 11/8 피해 종류 한 줄("물리 피해 · 갑옷 30%")은 11/21 머리 한 줄(병종 칩 뒤 · SheetStyle.meta_row)로 옮겼다
	# 11/20 사용자: 디테일창의 특기 열고 닫기를 없앤다(가진 특기만 고정). 그 자리에 넣었던 장수 열전은 같은 날 사용자 뜻으로 다시 뺐다
	var tbd := TraitBoard.new()
	tbd.fixed = true
	st.add_child(tbd.setup(k))
	# 11/9 사용자: 초상 옆 빈 공간 정리 —— 오른쪽에는 능력치 · 특기판 · 기질 띠(좁은 모양)를 쌓고, 고유 특기 · 위세 · 패업 · 고유기는 아래 폭 전체 카드 격자로
	st.add_child(_compact_ability_summary(k))
	top.add_child(st)
	b.add_child(top)
	var ab := UI.vbox(UI.SP_S)
	_ability_cards(ab, k)
	var ability := UI.vbox(UI.SP_M)
	b.add_child(ability)
	if ab.get_child_count() > 0:      # 11/21 섹션 머리 —— 갈무리창 「고유 능력」 표와 같은 이름 · 같은 금 마름모
		ab.add_child(SheetStyle.section("고유 능력"))
		ab.move_child(ab.get_child(ab.get_child_count() - 1), 0)
	ability.add_child(ab)
	ab.visible = ab.get_child_count() > 0
	var skills := _skills_section(k)
	if skills != null:
		ability.add_child(skills)
	var folds := UI.vbox(0)          # 11/3 사용자: 접힌 기술 · 특기 · 선호 대열 사이를 좁힌다
	ability.add_child(folds)
	var tl := DB.trait_list(k)
	var tn := tl.filter(func(x): return not x.unique)      # 고유 특기는 위 능력 카드에
	if not tn.is_empty():
		# 11/20 사용자: "특기 아이콘화" —— 글 줄 나열 대신 계열 기호 칸 격자 + 고른 특기 설명 한 칸 (_trait_icons)
		var tv := UI.vbox(UI.SP_S)      # 11/9 사용자: 특기 펼치기 버튼 제거 —— 늘 펼쳐 둔다
		tv.add_child(SheetStyle.section("특기", "%d개" % tn.size()))      # 11/21 장수창 공통 섹션 머리
		tv.add_child(_trait_icons(tn))
		var tm := MarginContainer.new()
		tm.add_theme_constant_override("margin_top", 8)
		tm.add_theme_constant_override("margin_left", 0)      # 11/20 머리말 왼끝을 다른 묶음(기술 · 선호 대열 · 장수 조합법)과 맞춘다 (4 → 0)
		tm.add_theme_constant_override("margin_bottom", 8)
		tm.add_child(tv)
		folds.add_child(tm)
	var ag := _info_grid()
	_info_row(ag, "[color=#8fd4c2]선호[/color]", "%s\n[color=#C6AC7C]%s[/color]" % [UI.aff_zones(c.tag, "pref"), UI.aff_desc(c.tag, "pref")])
	_info_row(ag, "[color=#e0806f]어색[/color]", "%s\n[color=#C6AC7C]%s[/color]" % [UI.aff_zones(c.tag, "bad"), UI.aff_desc(c.tag, "bad")])
	folds.add_child(_fold_sec("card_aff", "선호 대열", ag))

	var inyeon := UI.vbox(UI.SP_M)
	_card_inyeon(inyeon, k)
	b.add_child(inyeon)
	var recipe := UI.vbox(UI.SP_M)
	b.add_child(recipe)
	# 보유 중이면 한 단계 위(이 카드로 만드는 것)를 먼저, 아니면 만드는 법을 먼저 (11/2 사용자)
	var owned: bool = run.pool().get(k, 0) > 0
	var make_sec := UI.vbox(UI.SP_M)
	var up_sec := UI.vbox(UI.SP_M)
	make_sec.add_child(SheetStyle.section("장수 조합법"))
	if DB.RECOF.has(k):
		make_sec.add_child(_up_row(k))
		var msc := _myth_status_card(k)      # 11/21 갈무리창과 같은 유니크 재료 · 신화 한 장 상태 카드
		if msc != null:
			make_sec.add_child(msc)
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
		pass      # 11/20 사용자: 기인 안내 칸("같은 기인은 한 판에 한 장 …")은 뺀다
	elif own.is_empty() and ts.is_empty() and c.tier >= 3:
		up_sec.add_child(SheetStyle.section("최종 단계"))
		up_sec.add_child(UI.hint("이 장수는 더 올라가는 길이 없고 다른 조합의 재료로도 쓰이지 않는다 — 완성형."))
	if not own.is_empty():
		up_sec.add_child(SheetStyle.section("승급", "같은 인물의 %s" % " · ".join(own.map(func(o): return DB.TIER[DB.C[o].tier].n))))
		for o in own:
			up_sec.add_child(_up_row(o))
	for t in ts:
		var lst_: Array = by_t[t]
		lst_.sort_custom(func(x, y): return run.miss_count(x) < run.miss_count(y))
		var can_n := lst_.filter(func(x): return run.can_forge(x)).size()
		up_sec.add_child(SheetStyle.section("%s 조합 재료" % DB.TIER[t].n, "%d종%s" % [lst_.size(), " · %d종 지금 가능" % can_n if can_n > 0 else ""]))
		for o in lst_.slice(0, 4):
			up_sec.add_child(_up_row(o))
		if lst_.size() > 4:
			up_sec.add_child(UI.hint("그 밖에 %d종 더 (조합 탭에서 %s 등급으로 거르면 모두 보인다)" % [lst_.size() - 4, DB.TIER[t].n]))

	for sec in ([up_sec, make_sec] if owned else [make_sec, up_sec]):
		if sec.get_child_count() > 0:
			recipe.add_child(sec)
	# 11/13 유닛 판매 —— 11/14 감사 #3: 초상 바로 아래 전체 폭 버튼이 상세창에서 가장 눈에 띄었다 (불멸을 실수로 팔 위험).
	#   맨 아래 머리선 뒤 한 줄로 내리고 작은 보조 버튼으로. 전설 이상 · 기인 · 편성에만 있는 장수는 확인 시트(_sell_sheet)를 거친다
	if shop_on() and Run.sellable(k) and int(p.get(k, 0)) > 0:
		recipe.add_child(UI.hair())
		var sr := UI.hbox(UI.SP_S)
		var sl := UI.lbl("보유 %d장 · 팔면 군량을 받는다" % int(p.get(k, 0)), UI.FS_CAP, DB.PAL.text_dim)
		sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		sr.add_child(sl)
		var sb := UI.grain_btn("판매", "+%d" % Run.sell_price(k), func(): _sell(k), "ghost", UI.BH_S, UI.FS_BODY)
		sb.disabled = not can_act()
		sb.modulate.a = 0.5 if sb.disabled else 1.0
		# 11/20 올리면 붉은 선이 종이색으로 바뀌었다 —— 올림 · 눌림도 인장 붉은 선
		UI.btn_styles(sb, UI.flat(Color(0, 0, 0, 0), Color(DB.PAL.seal, 0.55), 1, UI.R, 10), UI.flat(Color(DB.PAL.seal, 0.10), Color(DB.PAL.seal, 0.8), 1, UI.R, 10),
			UI.flat(Color(DB.PAL.seal, 0.18), Color(DB.PAL.seal, 0.8), 1, UI.R, 10))
		sb.custom_minimum_size.x = maxf(sb.custom_minimum_size.x, 128)
		sr.add_child(sb)
		recipe.add_child(sr)
	_build_card_tabs([ability, inyeon, recipe], tab)


func _build_card_tabs(panels: Array[Control], selected: int) -> void:
	var titles := ["능력", "인연", "조합"]
	var group := ButtonGroup.new()
	for i in panels.size():
		var button := UI.btn(titles[i], func():
			if int(_route.get("tab", -1)) == i:
				return
			_route["tab"] = i
			for j in panels.size():
				panels[j].visible = j == i
			_sheet_scroll.scroll_vertical = 0
			_fit_sheet(false), "", UI.HIT)
		button.toggle_mode = true
		button.button_group = group
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.press_fx = false
		SheetStyle.tab_btn(button)      # 11/21 장수창 공통 결 —— 글자만, 고르면 금 밑줄 + 옅은 금 바닥
		_card_tabs.add_child(button)
		button.set_pressed_no_signal(i == selected)
		panels[i].visible = i == selected
	_card_tab_bar.show()
	_route["tab"] = selected


## 갈무리 버튼 (11/15 —— 조합 시트 · 디테일창 맨 위) —— ★ 갈무리 / ★ 갈무리 해제. 높이 50, 누른 뒤 after
func _pin_btn(k: String, after: Callable) -> Button:
	var pn := forge_tree.pinned(k)
	var pb := UI.btn("★ 갈무리 해제" if pn else "★ 갈무리", func():
		forge_tree.toggle(k)
		after.call(), "ghost" if pn else "", UI.BH_M)
	if not pn and forge_tree.is_dead(k):      # 11/22 사망한 장수는 갈무리 불가
		pb.text = "사망 —— 갈무리 불가"
		pb.disabled = true
	pb.custom_minimum_size.x = 120 if pn else 104
	pb.add_theme_color_override("font_color", DB.PAL.gold.lightened(0.15) if not pn else DB.PAL.paper)
	return pb


## 접는 칸 —— 머리줄을 누르면 열고 닫는다. 기본은 닫힘, 연 상태는 _open[key] 에 남아 다른 카드에서도 이어진다
func _fold_sec(key: String, title: String, body: Control) -> Control:
	var v := UI.vbox(UI.SP_S)
	var hb := TouchButton.new()
	# 11/20 UI 다듬기: 테마 여백(10) 때문에 「기술 2 ▾」가 옆 머리말(「특기 4」 · 「장수 조합법」)보다 10 들어가 있었다 —— 여백 없는 빈 모양으로 왼끝을 맞추고, 올리면 글자만 밝힌다
	var hb_sb := StyleBoxEmpty.new()
	hb_sb.set_content_margin_all(0)
	UI.btn_styles(hb, hb_sb)
	hb.custom_minimum_size.y = UI.BH_XS
	# 11/21 머리줄 글자 대신 장수창 공통 섹션 머리(금 마름모 · 제목 · 사라지는 금빛 선) + 오른쪽 '펼치기 ▾ / 접기 ▴' (SheetStyle.section)
	var slot := MarginContainer.new()
	slot.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.add_child(slot)
	var upd := func():
		var on: bool = _open.get(key, false)
		for ch in slot.get_children():
			slot.remove_child(ch)
			ch.queue_free()
		slot.add_child(SheetStyle.section(title, "접기 ▴" if on else "펼치기 ▾"))      # 11/14 UI 4단계: 접힘 표시는 앱 전체 ▾(닫힘) · ▴(열림) 하나로
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
		var a := UI.lbl(str(int(pair[2])), UI.FS_TITLE, pair[4] if pair[3] else DB.PAL.paper, true)
		a.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		a.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		g.add_child(_stat_cell(pair[0], pair[1], pair[4] if pair[3] else DB.PAL.bamboo_dim.lightened(0.15), a))
	return g


## 능력치 한 칸 —— 아이콘 + 숫자. 아이콘이 처음이어도 알 수 있게 누르면(PC 는 올려 두면) 이름이 잠깐 뜬다 (칼 = 공격 · 방패 = 방어 · 신발 = 속도)
func _stat_cell(icon: String, nm: String, col: Color, num: Control) -> PanelContainer:
	var h := UI.hbox(UI.SP_XS)
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	var iv := Icons.View.new(icon, col, STAT_ICON)
	iv.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var nl := UI.lbl(nm, UI.FS_BODY, col, true)
	nl.custom_minimum_size.x = STAT_ICON
	nl.visible = false
	h.add_child(iv)
	h.add_child(nl)
	h.add_child(num)
	var pc := UI.panel(h, 4)
	pc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pc.tooltip_text = nm
	UI.tap(pc, func():      # 11/20 조작: 탭 판정 (UI.tap)
		var gen := int(pc.get_meta("gen", 0)) + 1
		pc.set_meta("gen", gen)
		iv.visible = false
		nl.visible = true
		get_tree().create_timer(1.5).timeout.connect(func():
			if is_instance_valid(pc) and int(pc.get_meta("gen", 0)) == gen:
				iv.visible = true
				nl.visible = false))
	return pc


## 전투장수창 (11/6 사용자) —— 전투 중 꾹 눌러 연다. 11/21 폴리싱: 지금 상황(병력 · 사기 · 고유기 기 · 걸린 상태) · 이번 전투 기여 · 전장의 개성 ·
## 이 장수에게 일어난 사건 기록이 위, 장수 정보(능력치 · 장비 · 고유기 · 기술 · 특기)가 아래. 열어 둔 채 전투가 흐르면 값이 바뀐다 —— scripts/ui/battle_unit_card.gd
func battle_unit_sheet(key: String) -> void:
	var sq: Squad = _battle.field.squads.get(key) if _battle and _battle.field else null
	if sq == null or not DB.C.has(sq.cid):
		return
	var b := open_sheet(DB.C[sq.cid].name, DB.tier_color(sq.cid).lightened(0.2))
	sheet_head(sq.cid, BattleUnitCard.head_extra(_battle, key))      # 갈무리창 · 상세창과 같은 머리 + [아군/적군] [자리] 덧칩
	b.add_child(BattleUnitCard.new(self, _battle, key))


## 11/7 고유기 기질 (사용자: 플레이어가 알 수 있게) —— 기호(Icons). 11/9 색은 걷었다
const TEMPER_ICON := {"맹장": "blade", "수호": "shield", "지략": "news", "저격": "target", "분노": "flame"}
## 고유 특기 · 위세(기인) · 패업 · 고유기 줄의 기호 —— 11/9 사용자: 종류를 색 카드가 아니라 작은 기호 + 옅은 라벨로 (작업현황 ㊽)
const ABILITY_ICON := {"고유 특기": "seal", "위세": "banner", "기인": "banner", "패업": "crown", "고유기": "burst"}


## 11/19 사용자: 디테일창 · 갈무리창은 초상 이미지 바로 아래에 역할 —— 초상과 역할 칩을 세로로 묶는다 (역할이 없는 카드는 초상 그대로)
func _with_role(portrait: Control, k: String) -> Control:
	if DB.role_chip(k).is_empty():
		return portrait
	var v := UI.vbox(UI.SP_XS)
	v.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	v.add_child(portrait)
	var chip := RoleChip.new(k)
	chip.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(chip)
	return v


## 11/19 장수 역할 칩 (디테일창 · 갈무리창) —— 카드에 그리는 것(CardTile.draw_role_chip)과 같은 칩(모서리 UI.R)을 한 줄 컨트롤로
class RoleChip extends Control:
	const FS := 12
	var k := ""
	func _init(id: String) -> void:
		k = id
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var rc := DB.role_chip(id)
		var tw: float = DB.font_bold.get_string_size(str(rc.get("t", "")), HORIZONTAL_ALIGNMENT_LEFT, -1, FS).x
		custom_minimum_size = Vector2(FS + tw + 11.0, FS + 5.0)
	func _draw() -> void:
		CardTile.draw_role_chip(self, k, Vector2.ZERO, FS)


## 고유 특기 · 위세(기인) · 패업 · 고유기 항목을 차례로 모은다 —— {kind, name, effect, icon, sub, gold} (디테일창 · 갈무리창이 같이 쓴다)
func _ability_items(k: String) -> Array:
	var c: Dictionary = DB.C[k]
	var out := []
	for t in DB.trait_list(k):
		if t.unique:
			var eff: String = t.mt if t.mt != "" else (t.d as String).get_slice(" —— ", 0)
			# 11/19 장수 개성(passives.json sig) 문장을 수치 앞에 —— 표적 고르기 같은 행동은 수치가 없어 문장이 없으면 무엇을 하는지 알 수 없다
			var sg = DB.PSV.get("sig", {}).get(DB.person(k))
			if sg is Array and sg.size() >= 2 and str(sg[1]) != "" and not eff.contains(str(sg[1])):
				eff = str(sg[1]) + " · " + eff
			out.append({"kind": "고유 특기", "name": t.name, "effect": eff, "icon": ABILITY_ICON["고유 특기"], "sub": "", "gold": true})
	if DB.AURA.has(k):
		var kiin: bool = DB.is_kiin(k)
		var kd := "기인" if kiin else "위세"
		out.append({"kind": kd, "name": DB.AURA[k].n, "effect": DB.aura_effect(k), "icon": ABILITY_ICON[kd], "sub": ""})
	if DB.AURA.has(k) and DB.AURA[k].has("paeup"):      # 11/9 패업 —— 이름 · 조건 · 효과 (판정은 Battle._paeup_setup)
		var pa: Dictionary = DB.AURA[k].paeup
		var cw: String = str(pa.get("what", "화상을 거는 장수" if str(pa.cond) == "burn" else "상태이상을 거는 장수"))
		var pe: String = str(pa.get("d", "")) if str(pa.cond) == "none" else "아군에 %s 자신 외 %d명 이상이면 —— %s" % [cw, int(pa.need), str(pa.get("d", ""))]      # 조건 없는 패업은 설명만 (11/9)
		out.append({"kind": "패업", "name": str(pa.n), "effect": pe, "icon": ABILITY_ICON["패업"], "sub": ""})
	var u = DB.ult_of(k) if DB.has_ult(k) else null
	if u != null:
		out.append({"kind": "고유기", "name": u.name, "effect": UI.ult_desc(u, c.tier), "icon": ABILITY_ICON["고유기"], "sub": DB.ult_when(u)})
	return out


## 고유 특기 · 위세(기인) · 패업 · 고유기 (+ 기질) —— 디테일창 · 전투장수창 · 보급 팝업이 같은 모양.
## 11/9 사용자: 색 카드 나열이 'AI 티' —— 한 장의 패널 안에서 얇은 구분선으로 줄을 나눈다. narrow(휴대폰 세로 보급 팝업)면 줄 안을 위아래로 쌓는다
func _ability_rows(into: Container, k: String, fs := 12, narrow := false, with_temper := true, skip: Array = [], with_inyeon := false) -> void:
	var c: Dictionary = DB.C[k]
	var its := _ability_items(k).filter(func(it): return not skip.has(str(it.get("kind", ""))))      # skip: 뺄 종류 (보급 팝업은 패업, 11/9)
	var u = DB.ult_of(k) if DB.has_ult(k) else null
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
			eff.append("[color=#A89574]%s[/color]  %s" % [pair[0], pair[1]])
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
		UI.tap(m, func():      # 11/20 조작: 탭 판정 (UI.tap)
			UI.buzz()
			on_tap.call())
	else:
		m.mouse_filter = Control.MOUSE_FILTER_PASS
	var ic := Icons.View.new(str(it.icon), P.bamboo_dim, fs + 2)
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var kl := UI.lbl(str(it.kind), fs - 1, P.text_dim)
	kl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var nl := UI.lbl(str(it.name), fs + (2 if simple else 3), P.gold if it.get("gold", false) else P.paper, true)
	UI.wrap_text(nl)
	nl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var sl: Label = null
	if str(it.get("sub", "")) != "":
		sl = UI.lbl(str(it.sub), fs - 2, P.text_dim)
		sl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var eff: RichTextLabel = null
	if not simple and str(it.get("effect", "")) != "":
		eff = UI.rich(str(it.effect) if it.get("raw", false) else _hl(str(it.effect)), fs - 1)
		eff.add_theme_color_override("default_color", P.bamboo)
		eff.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		UI.wrap_text(eff)      # 11/20 「세/기」처럼 단어 가운데서 줄이 바뀌었다
	if narrow and not simple:
		var v := UI.vbox(3)
		var hd := UI.hbox(UI.SP_XS)
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
	var h := UI.hbox(UI.SP_S)
	lm.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	h.add_child(lm)
	var rv := UI.vbox(2)
	rv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var nr := UI.hbox(UI.SP_S)
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


# ───────── 11/20 디테일창 능력 카드 · 특기 아이콘 ─────────
## 사용자: "왜 맨날 UI가 나열식이야" —— 같은 정보를 위계와 덩어리로. 고유기가 주인공(계열 색 띠 카드 · 큰 숫자 하나 · 꼬리표),
## 고유 특기 · 위세(기인) · 패업은 왼쪽 색 띠 카드(이름 + 개성 문장 + 2단 수치 칩), 인연도 같은 카드 틀.
## 수치는 문장을 다시 쪼개지 않고 원천의 구조(DB.ult_parts · trait_list 의 ml · DB.aura_list)에서 받는다.
## 갈무리창 · 전투장수창 · 보급 팝업은 예전 줄 모양(_ability_rows) 그대로

## 고유기 계열(ultimates.json vfx) → 카드 색 · 바탕 기호
const ULT_COL := {"firestorm": Color("#F08A3C"), "thunder": Color("#6FA8F0"), "poison": Color("#8CC455"), "heal": Color("#5FC9A8"),
	"shadow": Color("#A183E0"), "illusion": Color("#D08AE0"), "aura": Color("#E3B454"), "charge": Color("#E8694F"), "slash": Color("#E06A5A"),
	"arrowstorm": Color("#D8C078"), "roar": Color("#F0A848"), "whirlwind": Color("#5EC4CC")}
const ULT_ICON := {"firestorm": "flame", "heal": "heart", "charge": "blade", "slash": "blade", "arrowstorm": "target", "aura": "banner",
	"illusion": "swirl", "whirlwind": "swirl"}
const ABIL_VAL := Color("#8FD4C2")      # 수치 글자 (_hl 과 같은 옥색)
const ABIL_NUM := UI.FS_HEAD + 2       # 고유기의 큰 숫자 —— 이 패널에서 하나뿐인 큰 글자
const ABIL_ULT_COLOR := Color("#E87963")
const ABIL_TRAIT_COLOR := Color("#D9A64B")
const ABIL_AURA_COLOR := Color("#6DADCF")
const ABIL_PAEUP_COLOR := Color("#B48AD8")


func _ability_cards(into: Container, k: String) -> void:
	var c: Dictionary = DB.C[k]
	var P := DB.PAL
	var u = DB.ult_of(k) if DB.has_ult(k) else null
	if u != null:
		into.add_child(_ult_card(k, u))
	var lead: bool = u == null      # 고유기가 없는 등급(3~5급)은 고유 특기가 주인공
	for t in DB.trait_list(k):
		if not t.unique:
			continue
		var chips: Array = (t.ml as Array).map(DB.mod_chip)
		var d0: String = (t.d as String).get_slice(" —— ", 0)
		var sg = DB.PSV.get("sig", {}).get(DB.person(k))      # 장수 개성 문장 (passives.json sig) —— 없으면 특기 설명
		var line := str(sg[1]) if sg is Array and sg.size() >= 2 else ""
		if line == "":
			line = d0
		elif chips.is_empty() and not d0.contains(line):
			line += " · " + d0
		into.add_child(_abil_card("고유 특기", str(t.name), line, chips, ABIL_TRAIT_COLOR, lead))
		lead = false
	if DB.AURA.has(k):
		var al := DB.aura_list(k)
		var chips := []
		for g in al.groups:
			for e in g.items:
				chips.append([e[1], "%s %s" % [g.who, e[0]]])
		into.add_child(_abil_card("기인" if DB.is_kiin(k) else "위세", str(DB.AURA[k].n), str(al.text), chips, ABIL_AURA_COLOR))
		if DB.AURA[k].has("paeup"):      # 패업 —— 조건 · 효과 글 (판정은 Battle._paeup_setup)
			var pa: Dictionary = DB.AURA[k].paeup
			var pc := []
			if str(pa.cond) != "none":
				var cw: String = str(pa.get("what", "화상을 거는 장수" if str(pa.cond) == "burn" else "상태이상을 거는 장수"))
				pc.append(["%d명 이상" % int(pa.need), "아군에 %s (자신 외)" % cw])
			into.add_child(_abil_card("패업", str(pa.n), str(pa.get("d", "")), pc, ABIL_PAEUP_COLOR))


func _card_inyeon(into: Container, k: String) -> void:
	var iy := _inyeon_item(k)
	if iy.is_empty():
		into.add_child(UI.hint("등록된 인연이 없습니다."))
		return
	var me: String = DB.person(k)
	var ic := AbilCard.new(DB.PAL.yeon)
	var route := _route
	ic.add_child(InyeonUI.detail_row(iy.inyeon, _inyeon_ctx(k), 12, false, func(card: String):
		if DB.person(card) != me:
			card_info(card), Callable(), str(route.inyeon), func(name: String): route["inyeon"] = name))
	into.add_child(ic)


## 고유기 카드 —— 머리(고유기 · N초부터) · 이름(제목 글꼴) · 외침 | 큰 숫자 + 그 글, 아래 꼬리표 줄 (범위 · 상태 · 나머지 수치 · 상한)
func _ult_card(k: String, u: Dictionary) -> Control:
	var P := DB.PAL
	var vfx := str(u.get("vfx", ""))
	var col: Color = ABIL_ULT_COLOR
	var parts := DB.ult_parts(u, int(DB.C[k].tier))
	var card := AbilCard.new(col, true, str(ULT_ICON.get(vfx, "burst")))
	var v := UI.vbox(6)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var top := UI.hbox(UI.SP_S)
	var left := UI.vbox(0)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_child(_abil_tag("미니 고유기" if u.get("mini", false) else "고유기", col.lightened(0.3), DB.ult_when(u)))
	var nl := UI.lbl(str(u.name), UI.FS_TITLE, P.paper, true)
	UI.wrap_text(nl)
	left.add_child(nl)
	if str(u.get("shout", "")) != "":
		var sl := UI.lbl("“%s”" % str(u.shout), UI.FS_TINY, P.text_dim)
		UI.wrap_text(sl)
		left.add_child(sl)
	top.add_child(left)
	if not parts.hero.is_empty():
		var hv := UI.vbox(-5)
		hv.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var a := UI.lbl(str(parts.hero.v), ABIL_NUM, col.lightened(0.45), true)
		a.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		var b := UI.lbl(str(parts.hero.l), UI.FS_TINY, P.bamboo)
		UI.wrap_text(b)
		b.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		hv.add_child(a)
		hv.add_child(b)
		top.add_child(hv)
	v.add_child(top)
	if not parts.chips.is_empty():
		var f := UI.flow(6)
		f.mouse_filter = Control.MOUSE_FILTER_IGNORE
		for ch in parts.chips:
			f.add_child(_tag_chip(ch, col))
		v.add_child(f)
	card.add_child(v)
	return card


## 능력 카드 (고유 특기 · 위세 · 기인 · 패업) —— 이름 + 개성 문장 + 오른쪽 끝 종류 꼬리표, 아래 수치 칩 줄. chips: [[값, 글] …] (값이 "" 면 글 칩).
## lead = 이 장수의 주인공 카드 (고유기가 없을 때의 고유 특기) —— 이름을 제목 크기로, 바탕에 그라데이션
func _abil_card(kind: String, name: String, line: String, chips: Array, col: Color, lead := false) -> Control:
	var P := DB.PAL
	var card := AbilCard.new(col, true, str(ABILITY_ICON.get(kind, "")))
	var v := UI.vbox(6)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var hd := UI.hbox(UI.SP_S)
	var nl := UI.lbl(name, UI.FS_TITLE if lead else UI.FS_LABEL, P.gold if kind == "고유 특기" else P.paper, true)
	UI.wrap_text(nl)
	nl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nl.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	hd.add_child(nl)
	var ll: RichTextLabel = null
	if line != "":
		ll = UI.rich(_hl(line), UI.FS_CAP)
		ll.add_theme_color_override("default_color", P.bamboo)
		ll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		UI.wrap_text(ll)
	hd.add_child(_abil_tag(kind, col.lightened(0.3)))
	v.add_child(hd)
	if ll != null:
		v.add_child(ll)
	if not chips.is_empty():
		var f := UI.flow(6)
		f.mouse_filter = Control.MOUSE_FILTER_IGNORE
		for ch in chips:
			f.add_child(_stat_chip(str(ch[0]), str(ch[1]), chips.size() > 1))
		v.add_child(f)
	card.add_child(v)
	return card


## 종류 꼬리표 —— 기호 + "고유 특기" (+ 옅은 덧말 "13초부터")
func _abil_tag(kind: String, col: Color, sub := "") -> Control:
	var h := UI.hbox(UI.SP_XS)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	var ic := Icons.View.new(str(ABILITY_ICON.get(kind, "pick")), col, 10)
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(ic)
	h.add_child(UI.lbl(kind, UI.FS_TINY, col))
	if sub != "":
		h.add_child(UI.lbl("· " + sub, UI.FS_TINY, DB.PAL.text_dim))
	return h


## 2단 수치 칩 —— 큰 값("+21%") 아래 작은 글("거는 상태이상 세기"). 줄을 고르게 채운다 (한 줄 2~3개, 넘치면 다음 줄). 값이 없으면 글만
func _stat_chip(val: String, label: String, fill := true) -> Control:
	var P := DB.PAL
	var pc := PanelContainer.new()
	var sb := UI.flat(Color(P.ink, 0.55), Color(0, 0, 0, 0), 0, UI.R, 0)
	sb.content_margin_left = 7
	sb.content_margin_right = 7
	sb.content_margin_top = 1
	sb.content_margin_bottom = 3
	pc.add_theme_stylebox_override("panel", sb)
	pc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if fill:      # 혼자인 칩은 제 폭만 (온 폭으로 늘어나면 칩이 아니라 줄처럼 보인다)
		pc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	else:
		pc.custom_minimum_size.x = 96
	if val == "":
		var tl := UI.lbl(label, UI.FS_CAP, P.paper)
		if label.length() > 16:
			UI.wrap_text(tl)
			tl.custom_minimum_size.x = 130
		tl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		pc.add_child(tl)
		return pc
	var v := UI.vbox(-3)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(UI.lbl(val, UI.FS_LABEL, ABIL_VAL, true))      # 11/20 사용자: 글자를 줄여 카드 높이 목표(고유기 120 · 나머지 80)에 맞춘다
	var caption := UI.lbl(label, UI.FS_TINY, P.text_dim)
	if label.length() > 16:
		UI.wrap_text(caption)
		caption.custom_minimum_size.x = 100
	v.add_child(caption)
	pc.add_child(v)
	return pc


## 고유기 꼬리표 —— 한 줄 칩. 범위(과녁 기호) · 상태(계열 색 면) · 수치(글 + 옥색 값) · 상한(옅게)
func _tag_chip(ch: Dictionary, col: Color) -> Control:
	var P := DB.PAL
	var kind := str(ch.get("k", ""))
	var st: bool = kind == "st"
	var pc := PanelContainer.new()
	var sb := UI.flat(Color(col, 0.22) if st else Color(P.ink, 0.55), Color(col, 0.55) if st else Color(0, 0, 0, 0), 1 if st else 0, UI.R, 0)
	sb.content_margin_left = 6
	sb.content_margin_right = 6
	sb.content_margin_top = 2
	sb.content_margin_bottom = 2
	pc.add_theme_stylebox_override("panel", sb)
	pc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var h := UI.hbox(UI.SP_XS)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if kind == "tgt":
		var ic := Icons.View.new("target", P.bamboo, 9)
		ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(ic)
	var caption := UI.lbl(str(ch.l), UI.FS_TINY, P.paper if st or kind == "tgt" else (P.text_dim if kind == "cap" else P.bamboo))
	if str(ch.l).length() > 20:
		UI.wrap_text(caption)
		caption.custom_minimum_size.x = 130
	h.add_child(caption)
	if str(ch.get("v", "")) != "":
		h.add_child(UI.lbl(str(ch.v), UI.FS_TINY, P.text_dim if kind == "cap" else ABIL_VAL, true))
	pc.add_child(h)
	return pc


## 능력 카드 틀 —— 옅은 먹 바탕 + 왼쪽 색 띠. big(주인공 카드)이면 색 그라데이션 · 옅은 빗금 · 오른쪽에 큰 기호를 깐다
## 11/21 그리는 법은 장수창 공통 판(SheetStyle.Plate)으로 옮겼다 —— 띠 판(ACCENT) · 주인공 판(HERO), 수치는 그대로
class AbilCard extends SheetStyle.Plate:
	var big := false

	func _init(c: Color, b := false, ic := "") -> void:
		super(c, SheetStyle.HERO if b else SheetStyle.ACCENT, ic)
		big = b


## 11/20 사용자: "특기 아이콘화" —— 특기 글 목록(특기 수만큼 세로 줄) 대신 아이콘 칸 격자 + 고른 특기 설명 한 칸. 처음에는 첫 특기
func _trait_icons(tl: Array) -> Control:
	var P := DB.PAL
	var v := UI.vbox(UI.SP_S)
	var grid := TraitIcons.new(tl)
	v.add_child(grid)
	var box := PanelContainer.new()
	box.add_theme_stylebox_override("panel", UI.flat(Color(P.ink3, 0.55), Color(0, 0, 0, 0), 0, UI.R, 10))
	box.mouse_filter = Control.MOUSE_FILTER_PASS
	box.custom_minimum_size.y = 70      # 설명 두 줄 높이 —— 칸을 바꿔 눌러도 아래가 덜 출렁인다
	v.add_child(box)
	var pick := func(i: int):
		for ch in box.get_children():
			box.remove_child(ch)
			ch.queue_free()
		var t: Dictionary = tl[i]
		var cat := TraitIcons.cat_of(t)
		var col: Color = (DB.TRAIT_COL.get(cat, DB.TRAIT_COL[""]) as Color).lightened(0.35)
		var bv := UI.vbox(3)
		var hd := UI.hbox(UI.SP_XS)
		hd.add_child(UI.lbl(str(t.name), UI.FS_LABEL, P.paper, true))
		hd.add_child(UI.lbl(str(t.lv), UI.FS_LABEL, P.gold, true))
		var sp := Control.new()
		sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hd.add_child(sp)
		var cn: String = TraitIcons.NAME.get(cat, "")
		if t.group and cat != "단체":
			cn = (cn + " · " if cn != "" else "") + "단체"
		if cn != "":
			var cl := UI.lbl(cn, UI.FS_CAP, col)
			cl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			hd.add_child(cl)
		bv.add_child(hd)
		var d := UI.rich(str(t.d).replace(" —— ", "\n"), UI.FS_CAP)
		d.add_theme_color_override("default_color", P.bamboo)
		UI.wrap_text(d)
		bv.add_child(d)
		if str(t.mt) != "":
			var mv := UI.rich(_hl(str(t.mt)), UI.FS_CAP)
			mv.add_theme_color_override("default_color", P.text_dim)
			UI.wrap_text(mv)
			bv.add_child(mv)
		box.add_child(bv)
	grid.on_pick = pick
	pick.call(0)
	return v


## 특기 아이콘 격자 —— 칸 = 계열 색 원(단체는 네모 테) 안에 계열 기호, 오른쪽 아래 레벨, 아래 이름. 칸을 누르면 on_pick(i)
class TraitIcons extends Control:
	const ICON := {"물리": "blade", "책략": "news", "도트": "flame", "공깎": "blade_down", "책략깎": "scroll_down", "방깎": "shield_crack",
		"둔화": "hourglass", "혼란": "swirl", "사기": "banner", "철벽": "shield", "인덕": "heart", "": "pick", "단체": "group"}
	const NAME := {"물리": "물리 피해", "책략": "책략 피해", "도트": "지속 피해", "공깎": "공격 깎기", "책략깎": "책략 깎기", "방깎": "방어 깎기",
		"둔화": "둔화", "혼란": "혼란", "사기": "사기", "철벽": "철벽", "인덕": "인덕", "": "", "단체": "단체"}
	const COLS := 6
	const CH := 60.0       # 칸 높이
	const GAP := 4.0
	const DIA := 34.0      # 기호 원 지름

	var items: Array = []
	var sel := 0
	var on_pick := Callable()
	var _pr := Press.new()

	func _init(its: Array) -> void:
		items = its
		mouse_filter = Control.MOUSE_FILTER_STOP
		var rows := ceili(items.size() / float(COLS))
		custom_minimum_size = Vector2(0, rows * CH + maxi(0, rows - 1) * GAP)

	## 칸의 계열 —— 계열 없는 단체 특기는 "단체"
	static func cat_of(t: Dictionary) -> String:
		return "단체" if str(t.attr) == "" and t.group else str(t.attr)

	func _cell(i: int) -> Rect2:
		var cw := (size.x - GAP * (COLS - 1)) / COLS
		return Rect2((cw + GAP) * (i % COLS), (CH + GAP) * (i / COLS), cw, CH)

	func _gui_input(e: InputEvent) -> void:
		if _pr.feed(self, e) != Press.TAP:
			return
		for i in items.size():
			if _cell(i).has_point((e as InputEventMouseButton).position):
				if i != sel:
					sel = i
					UI.buzz()
					queue_redraw()
					if on_pick.is_valid():
						on_pick.call(i)
				accept_event()
				return

	func _draw() -> void:
		var P := DB.PAL
		var fb := DB.font_body
		for i in items.size():
			var t: Dictionary = items[i]
			var r := _cell(i)
			var on: bool = i == sel
			var col: Color = DB.TRAIT_COL.get(cat_of(t), DB.TRAIT_COL[""])
			if on:
				draw_style_box(UI.flat(Color(P.ink4, 0.9), Color(col.lightened(0.3), 0.9), 1, UI.R, 0), r)
			var c := Vector2(r.position.x + r.size.x * 0.5, r.position.y + 5 + DIA * 0.5)
			if t.group:      # 단체 —— 네모 테 (개인은 원)
				draw_style_box(UI.flat(Color(col, 0.30), col.lightened(0.15), 2, UI.R, 0), Rect2(c - Vector2(DIA, DIA) * 0.5, Vector2(DIA, DIA)))
			else:
				draw_circle(c, DIA * 0.5, Color(col, 0.30))
				draw_arc(c, DIA * 0.5, 0, TAU, 40, col.lightened(0.15), 1.5, true)
			Icons.draw(self, str(ICON.get(cat_of(t), "pick")), c, 20.0, col.lightened(0.55))
			var bc := c + Vector2(DIA * 0.5 - 3, DIA * 0.5 - 4)      # 레벨 —— 오른쪽 아래 먹색 원 안 금 숫자
			draw_circle(bc, 7.5, P.ink)
			draw_arc(bc, 7.5, 0, TAU, 20, Color(P.gold, 0.7), 1.0, true)
			var lv := str(t.lv)
			var lw := DB.font_bold.get_string_size(lv, HORIZONTAL_ALIGNMENT_LEFT, -1, UI.FS_TINY).x
			draw_string(DB.font_bold, bc + Vector2(-lw * 0.5, UI.FS_TINY * 0.36), lv, HORIZONTAL_ALIGNMENT_LEFT, -1, UI.FS_TINY, P.gold)
			var nm := str(t.name)
			var f := UI.fit_fs(fb, nm, UI.FS_CAP - 1, 8, r.size.x - 2)
			draw_string(fb, Vector2(r.position.x, r.position.y + CH - 5), nm, HORIZONTAL_ALIGNMENT_CENTER, r.size.x, f, P.paper if on else P.bamboo)


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
	var v := UI.vbox(UI.SP_XS)
	v.add_child(UI.hair())
	var hd := UI.hbox(UI.SP_XS)
	var ic := Icons.View.new(str(ti.icon), P.bamboo_dim, fs + 4)
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hd.add_child(ic)
	var kl := UI.lbl("기질", fs, P.text_dim)
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
	var h := UI.rich(head_bb + ("  [color=#A89574][font_size=%d]%s[/font_size][/color]" % [fs - 1, sub] if sub != "" else ""), fs + 1)
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
		UI.wrap_text(l)
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
		_num_re = RegEx.create_from_string("((?:약 )?[+\\-−×]?\\s?\\d[\\d,]*(?:\\.\\d+)?\\s?(?:%p|%|턴|초|부대|명)?)\\s*$")
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


## 잔기술이 나오는 간격 —— "공격 3번에 한 번 · 약 3.5초마다"
## 11/19 사용자: 턴제의 흔적 · 단위 없는 숫자를 걷는다 —— '평타 3번에 한 번' 에 그 장수의 속도로 몇 초마다인지 덧붙인다 (행동 간격 DB.act_sec)
static func minor_when(k: String) -> String:
	var n := Battle.minor_every(k)      # 11/23 병종 리듬
	var c: Dictionary = DB.C[k]
	if RtBattle.minor_trig:
		var def: Array = MinorTriggers.STORY.get(Battle.minor_kind(k), MinorTriggers.CLASS.get(c.tag, ["every", 0.0, n]))
		var cd: float = float(def[1]) if def.size() >= 2 else MinorTriggers.CD
		var p = def[2] if def.size() >= 3 else null
		var key := str(def[0])
		if key == "every":
			n = int(p) if p != null else n
		else:
			var condition: String = MINOR_WHEN.get(key, "조건을 만족한 공격")
			if key == "hit_n": condition = "피격 %d회 후 공격" % int(p)
			if key == "ally_low": condition = "아군 병력 %d%% 이하에서 공격" % roundi(float(p) * 100)
			return "%s · 재사용 %s" % [condition, DB.sec_str(cd)]
	return "공격 %d번에 한 번 · %s마다" % [n, DB.sec_str(n * DB.act_sec(float(c.tier), float(c.spd)))]

const MINOR_WHEN := {
	"contact_new": "새 적과 맞붙은 뒤 공격", "solo": "주변 적이 하나일 때 공격", "surround": "적 셋 이상에게 둘러싸여 공격",
	"impact": "돌격 적중 뒤 공격", "foe_low_morale": "대상 사기 60 미만", "multi_touch": "적 둘 이상과 맞붙어 공격",
	"kill": "적 격파 뒤 공격", "bigger": "자신보다 병력이 많은 적 공격", "engaged": "다른 아군과 교전 중인 적 공격",
	"half": "병력이 절반 아래로 떨어진 뒤 공격", "flank": "적 측면·후방 공격", "outnumbered": "주변에서 적이 우세할 때 공격",
	"outnumber": "주변에서 아군이 우세할 때 공격", "ran": "긴 거리를 이동한 뒤 공격", "rammed": "적 돌격에 맞은 뒤 공격",
	"ally_hit": "주변 아군이 맞은 뒤 공격", "big_hit": "큰 피해를 받은 뒤 공격", "long_melee": "5초 이상 근접전 후 공격",
	"lord_hit": "아군 주장이 맞은 뒤 공격", "unwatched": "적에게 노려지지 않을 때 공격", "far": "최대 사거리 부근의 적 공격",
	"foe_wind": "고유기 준비 중인 적 공격", "timer": "공격 시 발동", "morale_behind": "아군 평균 사기가 낮을 때 공격",
	"losing": "아군 전체 병력이 열세일 때 공격", "hit": "피격 뒤 공격", "melee_hit": "근접 공격에 맞은 뒤 공격",
	"clustered": "적 둘 이상이 뭉쳤을 때 공격", "foe_status": "지속 피해 상태인 적 공격", "ally_down": "아군이 쓰러진 뒤 공격",
	"deep": "아군 원거리를 위협하는 적 공격", "ally_morale_low": "아군 사기 80 미만에서 공격", "ally_status": "지속 피해 상태인 아군이 있을 때 공격",
	"camp_kill": "아군이 적을 격파하거나 대상 사기 60 미만", "volley": "사거리 안에 적 둘 이상",
}

func _skill_entry(id: String, title: String, kind: String, damage: String, when: String, effect: String) -> Dictionary:
	var condition := []
	var period := ""
	for part in when.split(" · "):
		if part.ends_with("마다") or part.begins_with("재사용 "):
			period = part.trim_suffix("마다")
		else:
			condition.append(part)
	var short_when := " · ".join(condition).strip_edges()
	return {"id": id, "name": title, "kind": kind, "damage": damage, "period": period, "condition": short_when,
		"when": when, "effect": effect, "effect_bb": _hl(effect)}

func _skill_entries(k: String) -> Array:
	var c: Dictionary = DB.C[k]
	var items := []
	var mk := Battle.minor_kind(k)
	if mk != "":
		var m: Dictionary = Battle.minor_def(mk)
		items.append(_skill_entry("minor", m.n, "minor", str(m.get("kind", "int" if DB.INT_TAGS.has(c.tag) else "phys")), minor_when(k), minor_desc(k, false)))
	for i in c.get("sks", []).size():
		var sk: Dictionary = c.sks[i]
		items.append(_skill_entry("skill:%d" % i, sk.n, "skill", str(sk.eff.get("kind", "support")), DB.sk_when(sk, c), DB.skill_desc(c, sk)))
	var escape := SkillPanel.escape_spec(k)
	if not escape.is_empty():
		items.append(_skill_entry("escape", escape.name, "escape", "support", "근접 적에게 붙잡히면 · 재사용 %s" % DB.sec_str(escape.cd), escape.effect))
	return items

func _skills_section(k: String, compact := false, live := false) -> Control:
	var items := _skill_entries(k)
	if items.is_empty():
		return null
	var box := UI.vbox(6)
	box.name = "SkillsSection"
	box.add_child(SheetStyle.section("일반 기술", "%d종%s" % [items.size(), " · 누르면 상세" if compact else ""]))
	var panel = SkillPanel.new().setup(items, compact)
	if compact:
		panel.mouse_filter = Control.MOUSE_FILTER_STOP
		UI.tap(panel, func(): card_info(k))
	if live:
		panel.enable_runtime()
	box.add_child(panel)
	if DB.C[k].get("sks", []).size() >= 2:
		var note := UI.lbl("각 기술은 따로 준비하고, 한 번에 하나씩 발동", 11, SheetStyle.DIM)
		UI.wrap_text(note)
		box.add_child(note)
	return box


## 잔기술 설명 (Battle.MINOR · minor_kind) —— "공격 3번에 한 번 · 약 3.5초마다 · 책략 피해 ×0.90 · 화상"
static func minor_desc(k: String, with_every := true) -> String:
	var mk := Battle.minor_kind(k)
	var m: Dictionary = Battle.minor_def(mk)
	var phys: bool = (m.kind == "phys") if m.has("kind") else DB.C[k]["int"] <= DB.C[k].atk
	var parts := [minor_when(k)] if with_every else []
	var act := Battle.minor_act_text(k)      # 11/23 병종 잔기술이 하는 일
	var rally: bool = Battle.minor_act_enabled and str(Battle.MINOR_ACT.get(DB.C[k].tag, {}).get("act", "")) == "rally"
	parts.append("%s피해 ×%.2f" % ["가장 뒤쪽 적에게 " if m.get("back", false) or str(Battle.MINOR_ACT.get(DB.C[k].tag, {}).get("act", "")) == "steal" else "", float(m.mult)])
	if act != "":
		parts.append(act)
	if m.has("st"):
		parts.append("%s %s" % [DB.D.STATUS[m.st[0]].n, DB.sec_text(int(m.st[2]), DB.C[k].tier)])
	if m.has("extra"):
		parts.append("한 번 더 ×%.1f" % float(m.extra))
	if m.has("self"):
		parts.append("자신 %s %+d%%(%s)" % [DB.D.STATNM.get(m.self.stat, m.self.stat), roundi(float(m.self.amt) * 100), DB.sec_text(int(m.self.dur), DB.C[k].tier)])
	if m.has("foe"):
		parts.append("맞은 적 %s %+d%%(%s)" % [DB.D.STATNM.get(m.foe.stat, m.foe.stat), roundi(float(m.foe.amt) * 100), DB.sec_text(int(m.foe.dur), DB.C[k].tier)])
	if m.has("morale"):
		parts.append("적 사기 −%d" % int(m.morale))
	if rally:
		pass
	elif m.has("mend") and m.has("cheer"):
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
	var h := UI.rich(head, UI.FS_BODY)
	h.autowrap_mode = TextServer.AUTOWRAP_OFF
	h.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	g.add_child(h)
	var r := UI.rich(body, UI.FS_BODY)
	r.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	g.add_child(r)


## 상세 시트의 조합 줄 —— 재료 칩을 누르면 그 카드 상세로 넘어간다
func _up_row(out: String) -> Control:
	var v := UI.vbox(UI.SP_S)
	var h := UI.hbox(UI.SP_S)
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
				close_sheet(), "pri", UI.BH_M)
		SheetStyle.main_btn(fb)      # 11/21 장수창 공통 결 —— 주 행동은 금 판
		fb.custom_minimum_size = Vector2(64, 48)
		fb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(fb)
	# 갈무리 —— 보유하지 않은 장수도 디테일창에서 바로 (11/2 사용자)
	var pn := forge_tree.pinned(out)
	var pb := UI.btn("갈무리 해제" if pn else "갈무리", func():
		forge_tree.toggle(out)
		_back_nav = true
		card_info(_route.get("k", out)), "ghost" if pn else "", UI.BH_M)
	if pn:      # 11/21 장수창 공통 결 —— 갈무리는 금 테 보조, 해제는 테만
		SheetStyle.quiet_btn(pb)
	else:
		SheetStyle.sub_btn(pb)
	if not pn and forge_tree.is_dead(out):      # 11/22 사망한 장수는 갈무리 불가
		pb.text = "사망"
		pb.disabled = true
	pb.custom_minimum_size = Vector2(72, 48)
	pb.add_theme_font_size_override("font_size", UI.FS_BODY)
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
		var cb := UI.btn("%s %d/%d" % [qn, got, m[q]], func(): card_info(q), "", UI.BH_S)      # 기호 없이 색으로 (4열에 이름이 잘렸다)
		# 11/14 UI 4단계 (감사 10-6): 모자란 재료가 모두 붉어 오류처럼 보였다 —— 모자람은 중립(얇은 선 · 종이색), 갖춤만 옥색. 수량 n/m 이 상태를 말한다
		var cb_c: Color = Color("#8fd4c2") if ok else Color(DB.PAL.paper, 0.16)
		UI.btn_styles(cb, UI.flat(DB.PAL.ink2, cb_c, 1, UI.R, 2), UI.flat(DB.PAL.ink3, cb_c, 1, UI.R, 2), UI.flat(DB.PAL.ink4, cb_c, 1, UI.R, 2))      # 11/20 올림 · 눌림은 바탕만 한 단계 밝게
		cb.add_theme_color_override("font_color", Color("#8fd4c2") if ok else DB.PAL.paper)
		cb.add_theme_font_size_override("font_size", UI.FS_CAP)
		cb.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		cb.clip_text = true
		cb.custom_minimum_size.x = 40
		chips.add_child(cb)
	var ni = Run.need_item(out)
	if ni != null:
		var ok: bool = run.bag.get(ni, 0) > 0
		# 유니크 재료도 재료 칸처럼 (11/3 —— 글씨가 칸 밖으로 삐져나왔다). 누르면 아이템 시트
		var ib := UI.btn("◆%s %d/1" % [DB.IT[ni].name, run.bag.get(ni, 0)], func(): _item_sheet(ni), "", UI.BH_S)
		var icol := Color("#d59700") if ok else DB.PAL.paper
		var ib_c := Color(icol, 0.8 if ok else 0.16)
		UI.btn_styles(ib, UI.flat(DB.PAL.ink2, ib_c, 1, UI.R, 2), UI.flat(DB.PAL.ink3, ib_c, 1, UI.R, 2), UI.flat(DB.PAL.ink4, ib_c, 1, UI.R, 2))
		ib.add_theme_color_override("font_color", icol)
		ib.add_theme_font_size_override("font_size", UI.FS_CAP)
		ib.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		ib.clip_text = true
		ib.custom_minimum_size.x = 40
		chips.add_child(ib)
	v.add_child(chips)
	# 11/21 모은 장 수 막대 —— 갈무리창 행동 줄 · 재료 섹션과 같은 셈 (_forge_progress), 판은 장수창 공통 판 (지금 조합되면 옥색 띠)
	var pg := _forge_progress(out)
	var mr := UI.hbox(UI.SP_S)
	var mt := SheetStyle.meter(pg.x, pg.y, SheetStyle.VAL, 4.0)
	mt.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	mr.add_child(mt)
	mr.add_child(UI.lbl("%d장 부족" % (pg.y - pg.x) if pg.x < pg.y else "장수 재료 갖춤",
		UI.FS_CAP, DB.PAL.danger if pg.x < pg.y else SheetStyle.VAL, true))
	v.add_child(mr)
	var pl := SheetStyle.Plate.new(SheetStyle.VAL, SheetStyle.ACCENT if run.can_forge(out) else SheetStyle.PLAIN, "", Vector4(10, 10, 10, 10))
	pl.add_child(v)
	return pl


# ───────── 조합 ─────────

func _toggle(key: String, default := false) -> void:
	_open[key] = not _open.get(key, default)
	render()


const KIIN_T := 9      # 기인 칸 —— 등급 거르기 · 계보 줄 (등급 수 바깥의 자리)

## 추천 목표 —— 점수는 Run.forge_goals (덱이 얻는 전력 − 모자란 재료를 구하는 수고 + 줄기 · 병종 맞춤, 11/5 사용자: 플레이에 도움이 되게)
## 11/13 사용자: 추천 조합칸 한 줄을 둘로 —— 왼쪽 「가장 가까운」(신화 아이템 길이 맨 앞 + 이 함수) · 오른쪽 「인연」(Run.bond_goals)
func _forge_goals(lst: Array) -> Array:
	var out_: Array = run.myth_item_goals().slice(0, 1)      # 11/5 사용자: 신화 아이템(유니크)을 가졌으면 그 신화 장수가 맨 앞 (재료가 몇 장 모자라든)
	var seen := {}
	for o in out_:
		seen[DB.person(o)] = true
	for o in run.forge_goals(lst.map(func(r): return r[0]), 4):
		if not seen.has(DB.person(o)):
			seen[DB.person(o)] = true
			out_.append(o)
	return out_


const GOAL_TILE := UI.TILE_L


## 추천 한 줄 —— 전체 폭 가로 띠 (넘치면 가로로 민다). caption: 타일 아래 짧은 글 (없으면 "")
func _goal_strip(rec: Array, caption: Callable, col: Color) -> Control:
	var gs_ := UI.strip(8)
	for out in rec:
		var gv := UI.vbox(2)
		gv.custom_minimum_size = Vector2(GOAL_TILE.x, 0)
		var gt := mtile(out, run.pool().get(out, -1), func(id): recipe_sheet(id))
		gt.custom_minimum_size = GOAL_TILE
		gt.badge = "-%d" % run.miss_count(out) if run.miss_count(out) > 0 else "조합"
		gt.badge_col = Color(col, 0.9)
		gv.add_child(gt)      # 11/5 사용자: 아래에 모자란 장수 이름은 쓰지 않는다
		var cap: String = caption.call(out)
		if cap == "":
			cap = " "      # 11/25 아래 ★ 칸이 옆 타일과 같은 높이에 오게 빈 줄을 둔다
		if cap != "":
			var cl := UI.lbl(cap, UI.FS_CAP, col)
			cl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			cl.custom_minimum_size = Vector2(GOAL_TILE.x, 0)
			gv.add_child(cl)
		# 11/25 UX: 추천에서 한 번에 갈무리 —— 타일은 조합법 시트, 아래 ★ 칸은 바로 갈무리 / 해제 (갈무리하면 위 목표 보드에 재료 나무로 올라간다)
		var pn := forge_tree.pinned(out)
		if pn:
			gt.set_pin(true, true)
		if pn or not forge_tree.is_dead(out):
			var pb := UI.btn("★ 해제" if pn else "★ 갈무리", func():
				forge_tree.toggle(out)
				render(), "ghost", UI.BH_XS)
			pb.add_theme_font_size_override("font_size", UI.FS_CAP)
			pb.add_theme_color_override("font_color", DB.PAL.text_dim if pn else DB.PAL.gold.lightened(0.15))
			var pb_n := UI.flat(Color(0, 0, 0, 0), Color(DB.PAL.gold, 0.22 if pn else 0.5), 1, UI.R, 4)
			pb_n.content_margin_top = 3
			pb_n.content_margin_bottom = 3
			UI.btn_styles(pb, pb_n, UI.flat(DB.PAL.ink3, Color(DB.PAL.gold, 0.6), 1, UI.R, 4), UI.flat(DB.PAL.ink4, DB.PAL.gold, 1, UI.R, 4))
			gv.add_child(pb)
		gs_[1].add_child(gv)
	return gs_[0]


## 11/13 사용자 "너무 좁다" —— 추천 조합을 조합 탭에서 징집 탭으로 옮겼다. [추천 닫기 / 추천 열기] 아래
##   「추천 조합 (가까운)」 전체 폭 한 줄 —— 신화 아이템(유니크)으로 가는 신화 장수가 맨 앞 + 덱 이득 − 수고 (_forge_goals)
##   「추천 조합 (인연)」 전체 폭 한 줄 —— 가진 장수와 인연이 많이 겹치는 순 (Run.bond_goals, 위 줄 인물은 빼고). 후보가 없으면 줄째 숨긴다
##   접은 상태는 _open["draw:rec_fold"] (세션 동안 유지). 빈 안내 문구는 두지 않는다. 둘 다 비면 null
func _goal_block() -> Control:
	var near_all := _forge_goals(DB.D.RECDEF)
	if near_all.is_empty():      # 수고 한도 안에 아무것도 없다 —— 가장 가까운 목표 하나는 보인다
		near_all = run.forge_goals(DB.D.RECDEF.map(func(r): return r[0]), 1, 1e9)
	var seen_p := {}
	for o in near_all:
		seen_p[DB.person(o)] = true
	var bond_all := run.bond_goals(seen_p, 6)
	if near_all.is_empty() and bond_all.is_empty():
		return null
	var fold: bool = _open.get("draw:rec_fold", false)
	var gsec := UI.vbox(UI.SP_S)
	var tb := UI.btn("추천 목표 열기 ▾" if fold else "추천 목표 닫기 ▴", func(): _toggle("draw:rec_fold"), "ghost", UI.BH_XS)
	tb.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	# 11/20 UI 다듬기: 높이 28 로 만들었지만 글자 16 + 여백 10 이라 실제로는 42 —— 다른 접기 버튼(군단 효과 「펼치기 ▾」 · 「완성된 장수 접기 ▴」)과 같은 작은 글씨 · 대나무색 · 낮은 여백으로
	tb.add_theme_font_size_override("font_size", UI.FS_CAP)
	tb.add_theme_color_override("font_color", DB.PAL.bamboo)
	var tb_n := UI.flat(Color(0, 0, 0, 0), Color(DB.PAL.paper, 0.16), 1, UI.R, 10)
	tb_n.content_margin_top = 3
	tb_n.content_margin_bottom = 3
	UI.btn_styles(tb, tb_n, UI.flat(DB.PAL.ink3, Color(DB.PAL.paper, 0.28), 1, UI.R, 10), UI.flat(DB.PAL.ink4, DB.PAL.gold, 1, UI.R, 10))
	gsec.add_child(tb)
	if fold:
		return gsec
	if not near_all.is_empty():
		gsec.add_child(UI.eyebrow("재료가 거의 모인 조합"))
		gsec.add_child(_goal_strip(near_all, func(o): return run.goal_reason(o), DB.PAL.seal))      # 11/19 이유 한 마디 (유니크 · 승급 · 역할 보강 · 인연)
	if not bond_all.is_empty():
		var owned := run.owned_persons()
		gsec.add_child(UI.eyebrow("인연 추천 조합"))
		gsec.add_child(_goal_strip(bond_all, func(o): return "인연 %d명" % Run.bond_links(o, owned), DB.PAL.yeon))      # 가진 장수 가운데 같은 인연으로 이어진 수
	return gsec


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
	# 11/25 UX: 조합 탭 = 목표 보드. 위에서부터 ① 갈무리 목표(재료 나무 · 진행 · 모두 조합) ② 추천 목표(누르면 조합법 · ★ 로 바로 갈무리)
	# ③ 지금 조합 가능 ④ 「전체 조합법」 버튼(거르기 · 195개 목록은 시트 안으로 —— 예전에는 이 목록이 탭의 58% 를 차지했다).
	# 실제 기록: 조합의 71% 가 갈무리 → 모두 조합에서 나온다 (1.2 버전 온라인 31자리)
	var v := UI.vbox(UI.SP_L)
	var top := UI.vbox(UI.SP_S)
	var hd := UI.hbox(UI.SP_S)
	var hl := UI.lbl("갈무리 %d/%d" % [forge_tree.pins.size(), ForgeTree.MAX_PINS], UI.FS_LABEL, DB.PAL.gold, true)
	hl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hd.add_child(hl)
	var ab := UI.btn("전체 조합법 %d  ›" % DB.D.RECDEF.size(), func(): recipes_sheet(), "ghost", UI.BH_S)
	ab.add_theme_font_size_override("font_size", UI.FS_BODY)
	hd.add_child(ab)
	top.add_child(hd)
	if forge_tree.pins.is_empty():
		top.add_child(UI.hint("노릴 장수를 ★ 갈무리하면 재료 진행과 「모두 조합」이 여기에 모인다."))
	else:
		top.add_child(forge_tree.build())
	v.add_child(top)
	var gb := _goal_block()
	if gb != null:
		v.add_child(gb)
	var can_now := {}      # 11/10 지금 되는 조합 —— 한 번만 묻는다
	for r in DB.D.RECDEF:
		if run.can_forge(r[0]):
			can_now[r[0]] = true
	var ready: Array = DB.D.RECDEF.filter(func(r): return can_now.has(r[0]))
	var goal_mat := {}      # 갈무리 목표와 그 재료(아래 재료까지) —— 지금 조합 가능 줄에서 앞에 선다
	var gwalk := func(nd: Dictionary, f: Callable) -> void:
		for c in nd.get("kids", []):
			if c.has("k"):
				goal_mat[c.k] = true
			f.call(c, f)
	for pk in forge_tree.pins:
		goal_mat[pk] = true
		gwalk.call(forge_tree._node(pk, 1, 0, pk, "", true), gwalk)
	ready.sort_custom(func(x, y):
		var gx: bool = goal_mat.has(x[0])
		var gy: bool = goal_mat.has(y[0])
		if gx != gy:
			return gx
		return DB.C[x[0]].tier > DB.C[y[0]].tier)
	if not ready.is_empty():
		var sec := UI.vbox(UI.SP_S)
		var rs := UI.strip(8)
		var head := UI.head("지금 조합 가능 %d" % ready.size(), "옆으로 더 보기  ›")
		var more_hint := head.get_child(1) as Label
		more_hint.hide()
		var range_bar: HScrollBar = rs[0].get_h_scroll_bar()
		range_bar.changed.connect(func():
			more_hint.visible = range_bar.max_value > range_bar.page)
		sec.add_child(head)
		for r in ready:
			var rc := recipe_card(r[0])
			if goal_mat.has(r[0]):      # 갈무리 목표로 가는 조합 —— ★
				for mt in rc.find_children("*", "MiniTile", true, false):
					mt.set_pin(true, false)
			rs[1].add_child(rc)
		sec.add_child(rs[0])
		v.add_child(sec)
	return v


## 전체 조합법 시트 (11/25 UX) —— 병종 · 등급 거르기 + 가까운 순 목록. 조합 탭에 늘 펼쳐 있던 것을 버튼 뒤로
func recipes_sheet() -> void:
	var again: bool = _sheet.visible and _route.get("kind", "") == "recipes"      # 거르기를 바꿔 다시 그린다 —— 스크롤 자리를 지킨다
	var keep: int = _sheet_scroll.scroll_vertical if again else (int(_open.get("recipes:y", 0)) if _back_nav else 0)
	_route_enter("recipes", "")
	var b := open_sheet("전체 조합법")
	_sheet_full = true
	var can_now := {}
	for r in DB.D.RECDEF:
		if run.can_forge(r[0]):
			can_now[r[0]] = true
	var row1 := HBoxContainer.new()
	row1.add_theme_constant_override("separation", 4)
	for t in [""] + DB.D.TAGORDER:
		var n: int = DB.D.RECDEF.filter(func(r): return can_now.has(r[0]) and (t == "" or DB.C[r[0]].tag == t)).size()
		row1.add_child(_filter_chip("all" if t == "" else "", DB.ICON.get(t) if t != "" else null, str(n) if n > 0 else "", DB.PAL.paper, forge_tag == t, func():
			forge_tag = t
			_open.erase("forge:more")
			recipes_sheet()))
	b.add_child(row1)
	var row2 := HBoxContainer.new()
	row2.add_theme_constant_override("separation", 4)
	for t in [0, 3, 4, 5, KIIN_T, 6, 7, 8]:        # 11/3 일반 없음 · 기인(9)은 전설 옆
		var tn: String = "all" if t == 0 else ("기인" if t == KIIN_T else DB.TIER[t].n)
		row2.add_child(_filter_chip(tn, null, "", DB.PAL.paper if t == 0 else (DB.KIIN_COL if t == KIIN_T else DB.TIER[t].c), forge_tier == t, func():
			forge_tier = t
			_open.erase("forge:more")
			recipes_sheet()))
	b.add_child(row2)
	var lst: Array = DB.D.RECDEF.filter(func(r): return (forge_tag == "" or DB.C[r[0]].tag == forge_tag) and _tier_match(r[0], forge_tier))
	var miss_of := {}
	for r in lst:
		miss_of[r[0]] = 0 if can_now.has(r[0]) else maxi(1, run.miss_count(r[0]))
	lst.sort_custom(func(x, y):      # 되는 것 먼저 → 모자란 장수 적은 순 → 높은 등급
		var a: int = miss_of[x[0]]
		var b2: int = miss_of[y[0]]
		if a != b2:
			return a < b2
		return DB.C[x[0]].tier > DB.C[y[0]].tier)
	var more_open: bool = _open.get("forge:more", false)
	var shown_n: int = lst.size() if (more_open or lst.size() < FORGE_FIRST + 12) else FORGE_FIRST
	var g := minis()
	for r in lst.slice(0, shown_n):
		var ft := _forge_tile(r[0])
		ft.tapped.connect(func(_id): _open["recipes:y"] = _sheet_scroll.scroll_vertical, CONNECT_REFERENCE_COUNTED)      # 조합법을 보고 돌아올 자리
		g.add_child(ft)
	b.add_child(UI.head("조합법 %d" % lst.size(), "−N: 부족한 장수 · ◆: 아이템"))
	b.add_child(g if not lst.is_empty() else UI.hint("이 조건의 조합법이 없다."))
	if shown_n < lst.size():
		var rest: Array = lst.slice(shown_n)
		var mb := UI.btn("더 보기  (+%d)" % rest.size(), func(): pass, "ghost", UI.BH_S)
		mb.pressed.connect(func(): _forge_more(g, mb, rest))
		b.add_child(mb)
	if keep > 0:
		_restore_sheet_scroll.call_deferred(keep)


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
		if not is_instance_valid(g) or not g.is_inside_tree():
			return      # 그 사이 시트가 다시 그려졌다 —— 새 목록이 이미 다 펼쳐져 있다
		for j in range(i, mini(i + FORGE_STEP, rest.size())):
			g.add_child(_forge_tile(rest[j][0]))
		i += FORGE_STEP
		await get_tree().process_frame


## 거르기 칸 —— 글씨 대신 기호(병종) · 색(등급). 고르면 밝은 테두리, 오른쪽 위 작은 숫자 = 지금 조합 가능 수
func _filter_chip(txt: String, icon, cnt: String, col: Color, on: bool, cb: Callable) -> Button:
	var b := TouchButton.new()
	b.hit.x = 0.0
	b.custom_minimum_size = Vector2(0, UI.BH_S)      # 11/14 감사 #10: 34 → 칩 높이 BH_S 로 (누르는 범위는 TouchButton 이 HIT 까지)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var tier_col: bool = icon == null and txt != "all"
	# 11/9: 등급색 덩어리 칩 → 먹색 칩 + 등급색 글자, 고른 것만 금 얇은 선
	# 11/20 올림 · 눌림이 평소와 같은 모양이라 PC 에서 반응이 없었다 —— 한 단계 밝게 (여백 0 그대로)
	var fc_b: Color = DB.PAL.gold if on else Color(0, 0, 0, 0)
	UI.btn_styles(b, UI.flat(DB.PAL.ink3 if on else DB.PAL.ink2, fc_b, 1 if on else 0, UI.R, 0), UI.flat(DB.PAL.ink4 if on else DB.PAL.ink3, fc_b, 1 if on else 0, UI.R, 0),
		UI.flat(DB.PAL.ink4, DB.PAL.gold, 1, UI.R, 0))
	if icon != null:
		b.icon = icon
		b.expand_icon = false
		b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		b.add_theme_constant_override("icon_max_width", 16)      # 병종 기호 SVG 가 크게 구워져 있다
		b.add_theme_color_override("icon_normal_color", DB.PAL.paper if on else DB.PAL.bamboo)
	else:
		b.text = "전체" if txt == "all" else txt
		b.add_theme_font_size_override("font_size", UI.FS_BODY)
		b.clip_text = true
		b.add_theme_color_override("font_color", col.lightened(0.15) if tier_col else DB.PAL.paper)
		b.add_theme_color_override("font_hover_color", col.lightened(0.3) if tier_col else DB.PAL.paper)
	if cnt != "":
		var l := UI.lbl(cnt, UI.FS_CAP, DB.PAL.gold, true)
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
	var v := UI.vbox(UI.SP_L)
	var placed := run.placed()
	if true:      # 11/12 최후 1인 —— 옛 최종 토너먼트 화면(대진표)은 없어졌다
		# 11/4 사용자: 토벌 · 대전을 한 줄에, 설명 글은 빼고, 남는 공간에 지금 배치된 진영을 그린다
		# 11/7 사용자: '목요일 오전' 글은 머리띠에 이미 있어 뺀다. 큰 두 줄 버튼(UI.act 64) 은 한 줄(46)로, 끝난 것은 완료 표시만 작게
		# 11/14 UI 다듬기 2단계 (감사 #1): 출진은 화면에 하나뿐인 큰 주 버튼(BH_L), 험지는 그 아래 켜고 끄는 줄(보조 모양). 끝난 전투는 작은 완료 표시
		# 11/20 사용자: 토벌 완료 · 출진 대전을 한 줄에 —— 끝난 것(왼쪽 작은 '✓ 토벌') · 잠긴 것(오른쪽 작은 '② 대전')은 글자 폭만, 출진 버튼이 남은 폭
		var dr := UI.hbox(UI.SP_S)
		if run.quest_done:
			if run.pvp_done:
				dr.add_child(_war_btn("① 토벌", "", true, false, func(): pass, ""))
				dr.add_child(_war_btn("② 대전", "", true, false, func(): pass, ""))
			else:
				dr.add_child(_war_btn("① 토벌", "", true, false, func(): pass, "", false))
				dr.add_child(_war_cta("출진  ·  대전", "임의 세력과 맞붙는다", placed == 0, func(): _start("pvp")))
			v.add_child(dr)
		else:
			dr.add_child(_war_cta("출진  ·  토벌", run.quest_name() + ("  ·  험지" if run.quest_hard else ""), placed == 0, func(): _start("quest")))
			dr.add_child(_war_btn("② 대전", "토벌 뒤 열림", false, true, func(): pass, "", false))
			v.add_child(dr)
			if run.quest_open():
				v.add_child(quest_hard_btn())
		if not run.quest_done:      # 11/8 토벌 우두머리 성질 · 11/15 군략 계획 —— 그날 아침부터 미리 보인다
			v.add_child(boss_panel())
		# 11/3 기인 점복 관로 —— 편성에 있으면 이번 토벌의 적 편성을 미리 본다
		var qr = run.quest_roster()
		if qr != null and not run.quest_done and run.board.has(DB.kiin_card("wind_slow")):
			var pv := UI.vbox(UI.SP_S)
			pv.add_child(UI.rich("[b][color=%s]점괘[/color][/b]  관로가 이번 토벌의 적진을 내다본다" % DB.KIIN_COL.to_html(false), UI.FS_BODY))
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
				go("draw"), "pri", UI.BH_M))
	if placed > 0:
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
		# 11/14 UI 4단계: 아래 진영 그림이 편성 탭과 무엇이 다른지(보기만 하는 곳) 몰랐다 —— 머리줄 「출진 진영」 + 오른쪽 「편성 바꾸기 ›」
		var fh := UI.hbox(UI.SP_S)
		var ft := UI.eyebrow("출진 진영")
		ft.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		ft.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		fh.add_child(ft)
		var fb := UI.btn_ghost("편성 바꾸기 ›", func(): go("deploy"), UI.BH_XS)
		fb.add_theme_font_size_override("font_size", UI.FS_CAP)
		# 11/20 올리면 여백 10 짜리 ghost 상자로 바뀌어 글자가 왼쪽으로 20 밀리고 머리줄이 높아졌다 —— 글자만 밝힌다 (여백 좌우 4)
		var fb_n := StyleBoxEmpty.new()
		fb_n.set_content_margin_all(0)
		fb_n.content_margin_left = 4
		fb_n.content_margin_right = 0
		UI.btn_styles(fb, fb_n)
		fb.add_theme_color_override("font_color", DB.PAL.gold)
		fb.add_theme_color_override("font_hover_color", DB.PAL.gold.lightened(0.3))
		fb.add_theme_color_override("font_pressed_color", DB.PAL.paper)
		fh.add_child(fb)
		v.add_child(fh)
		v.add_child(fp)
	if true:
		# 11/7: 전투 탭은 고정 페이지(render 의 fixed —— 진영 그림이 남는 공간을 채운다)라 내용이 길면(점괘 · 펼친 효과 표) 아래가 잘리고
		# 내릴 수도 없었다 —— 탭 안에 제 스크롤을 둔다. 짧으면 안쪽 VBox 가 창을 채우고(진영 그림이 남는 공간), 길면 손가락으로 내린다
		var sc := UI.scroll()
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		v.size_flags_vertical = Control.SIZE_EXPAND_FILL
		sc.add_child(v)
		return sc
	return v


## 전투 탭 출진 버튼 (11/14 감사 #1) —— 두 줄 큰 주 버튼. 코치 말풍선(4/4)이 이것을 가리킨다
var _war_cta_node: Control = null
func _war_cta(title: String, sub: String, disabled: bool, cb: Callable) -> Button:
	var b := UI.act(title, sub, cb, "pri", disabled)
	b.custom_minimum_size.y = UI.BH_L
	_war_cta_node = b
	return b


## 오늘 토벌 우두머리 패널 —— 11/8 성질(docs/역할_재설계_1108.md 7.3) + 11/15 그날 고정 군략 계획(받아치는 퍼즐 —— 칩을 누르면 효과 한 줄).
## 11/14 UI 4단계: 기호 + 금빛 굵은 머리 + 종이색 본문 한 패널. 혼자 하기 전투 탭 · 온라인 준비 단계(Online.war_page)가 같이 쓴다
func boss_panel() -> Control:
	var v := UI.vbox(UI.SP_S)
	var qt := DB.quest_trait(run.day)
	var tt := DB.trait_text(qt) if Battle.shield_enabled else DB.trait_text({"x": qt.get("x", "")})
	var qh := UI.hbox(UI.SP_S)
	var qi := Icons.View.new("burst", DB.PAL.gold, 18)
	qi.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	qh.add_child(qi)
	var ql := UI.head("오늘 토벌 우두머리", "총대장을 베면 승리")
	ql.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	qh.add_child(ql)
	v.add_child(qh)
	var traits := UI.rich(tt, UI.FS_BODY)
	UI.wrap_text(traits)
	v.add_child(traits)
	if Run.tac_on:
		v.add_child(TacUI.boss_rows(self))      # 11/21 계획 칩 + 우두머리 늘 켜짐 + 「군략 현황 ›」
	return UI.panel(v, 10)


## 11/12 험지 토벌 고르기 —— 누를 때마다 보통 ↔ 험지 (혼자 하기 전투 탭 · 온라인 준비 단계가 같이 쓴다)
## 11/14 감사 #1: 금색 전체 폭 버튼이 출진보다 눈에 띄었다 —— 보조 상자 + 오른쪽 켜고 끄기 스위치 한 줄. 글자는 줄바꿈(최소 폭 0)
func quest_hard_btn() -> Control:
	var P := DB.PAL
	var on := run.quest_hard
	var box := PanelContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_stylebox_override("panel", UI.flat(P.ink2, Color(P.seal, 0.7) if on else UI.HAIR, 1, UI.R, UI.SP_M))
	var row := UI.hbox(UI.SP_M)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tv := UI.vbox(2)
	tv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tv.add_child(UI.lbl("험지 토벌" + ("  ·  켜짐" if on else ""), UI.FS_LABEL, P.danger if on else P.paper, true))
	var sub := UI.lbl("적 병력 ×%s · 이기면 %s +1" % [str(Run.QUEST_HARD_TR), run.quest_hard_reward_text()], UI.FS_CAP, P.text_dim)
	UI.wrap_text(sub)
	tv.add_child(sub)
	for c in tv.get_children():
		c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(tv)
	var sw := Control.new()      # 스위치 —— 네모 트랙(모서리 UI.R) + 손잡이. 켜지면 인장 붉음 · 손잡이 오른쪽
	sw.custom_minimum_size = Vector2(44, 24)
	sw.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	sw.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sw.draw.connect(func():
		sw.draw_style_box(UI.flat(P.seal.darkened(0.2) if on else P.ink, Color(P.seal, 0.9) if on else Color(P.paper, 0.25), 1, UI.R, 0), Rect2(Vector2.ZERO, sw.size))
		var k := Rect2(Vector2(sw.size.x - 21.0 if on else 3.0, 3.0), Vector2(18, 18))
		sw.draw_style_box(UI.flat(P.paper if on else P.bamboo, Color(0, 0, 0, 0), 0, 3, 0), k))
	row.add_child(sw)
	box.add_child(row)
	var hit := TouchButton.new()      # 상자 전체가 누르는 곳 (PanelContainer 가 자식을 겹쳐 채운다)
	hit.flat = true
	for st in ["normal", "hover", "pressed", "hover_pressed", "focus", "disabled"]:
		hit.add_theme_stylebox_override(st, StyleBoxEmpty.new())
	hit.pressed.connect(func():
		UI.buzz()
		act("set_quest_hard", [not on]))
	box.add_child(hit)
	return box


## 끝난 전투 · 잠긴 전투 표시 (11/7 사용자) —— 끝났으면 작은 '✓ 토벌 완료'(누를 수 없다), 잠겼으면 흐린 작은 줄
## 11/20 사용자: 출진 버튼과 한 줄 —— fill 이 false 면 글자 폭만 차지하는 작은 표시(끝남 '✓ 토벌' · 잠김 '② 대전' + 작은 설명 두 줄), 버튼과 세로 가운데
func _war_btn(title: String, sub: String, done: bool, disabled: bool, cb: Callable, kind: String, fill := true) -> Control:
	var P := DB.PAL
	if done:
		var d := UI.btn("✓ %s 완료" % title.substr(2) if fill else "✓ %s" % title.substr(2), func(): pass, "", UI.BH_S)
		d.disabled = true
		d.size_flags_horizontal = Control.SIZE_EXPAND_FILL if fill else Control.SIZE_SHRINK_BEGIN
		d.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		d.add_theme_font_size_override("font_size", UI.FS_BODY)
		d.add_theme_color_override("font_disabled_color", Color(P.jade, 0.9))
		d.add_theme_stylebox_override("disabled", UI.flat(Color(P.jade, 0.08), Color(P.jade, 0.4), 1, UI.R, 0))
		var sb: StyleBoxFlat = d.get_theme_stylebox("disabled")
		sb.content_margin_left = 12
		sb.content_margin_right = 12
		return d
	if disabled and not fill:
		var pc := PanelContainer.new()
		var psb := UI.flat(Color(P.ink2, 0.45), Color(P.paper, 0.1), 1, UI.R, 0)
		psb.content_margin_left = 12
		psb.content_margin_right = 12
		psb.content_margin_top = 4
		psb.content_margin_bottom = 4
		pc.add_theme_stylebox_override("panel", psb)
		pc.custom_minimum_size.y = UI.BH_S
		pc.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		pc.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var lv := UI.vbox(0)
		lv.alignment = BoxContainer.ALIGNMENT_CENTER
		lv.mouse_filter = Control.MOUSE_FILTER_IGNORE
		for pair in [[title, UI.FS_BODY], [sub, UI.FS_TINY]]:
			if pair[0] == "":
				continue
			var ll := UI.lbl(pair[0], pair[1], P.text_dim)
			ll.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			ll.mouse_filter = Control.MOUSE_FILTER_IGNORE
			lv.add_child(ll)
		pc.add_child(lv)
		return pc
	var b := UI.btn("%s  —  %s" % [title, sub] if sub != "" else title, cb, kind, UI.BH_S)
	b.disabled = disabled
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.add_theme_font_size_override("font_size", UI.FS_BODY)
	b.add_theme_color_override("font_disabled_color", P.text_dim)
	b.add_theme_stylebox_override("disabled", UI.flat(Color(P.ink2, 0.45), Color(0, 0, 0, 0), 0, UI.R, 10))
	b.clip_text = true
	b.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	return b


func _result_panel() -> Control:
	# 11/4 사용자: 레이아웃 정리 —— 왼쪽 큰 결과 글자, 오른쪽 전투 이름, 아래 한 줄에 잔존 · 수훈 · 보상 칩
	var r: Dictionary = run.last_result
	var col := DB.PAL.bamboo if r.draw else (Color("#8fd4c2") if r.win else DB.PAL.danger)
	var v := UI.vbox(UI.SP_S)
	var h := UI.hbox(UI.SP_S)
	var marker := ColorRect.new()
	marker.color = col
	marker.custom_minimum_size = Vector2(3, UI.FS_HEAD)
	marker.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(marker)
	var big := UI.lbl("무승부" if r.draw else ("승리" if r.win else "패배"), UI.FS_HEAD, col, true)
	big.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(big)
	var tl := UI.lbl(str(r.title), UI.FS_BODY, DB.PAL.bamboo)
	tl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	UI.wrap_text(tl)
	tl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(tl)
	v.add_child(h)
	# 11/20 사용자 "정리": 점으로 이은 한 줄(좁으면 "민심 / −2" 로 끊겼다) → 값 · 이름 칸 한 줄 (UI.result_stats)
	var items := [["잔존", "%d : %d" % [r.left, r.eLeft]]]
	if r.mvp != "":
		items.append(["수훈", DB.person_of_name(str(r.mvp))])
	if run.last_spoil != null:
		items.append(["기본패", "+%d" % int(run.last_spoil.n), DB.PAL.gold])
	if run.ticket_left() > 0:
		items.append(["선택권", str(run.ticket_left())])
	if not r.win and run.last_hp_loss > 0:      # 11/10 연출은 지나가니 깎인 만큼은 결과 칸에도 남긴다
		items.append(["민심", "−%d" % run.last_hp_loss, DB.PAL.danger])
	v.add_child(UI.hair())
	v.add_child(UI.result_stats(items, UI.spoil_note(run.last_spoil)))
	return UI.panel(v, 12)


func _start(kind: String) -> void:
	if run.placed() == 0 or run.battle != null:
		return
	var bt: Dictionary
	match kind:
		"quest": bt = run.start_quest()
		"pvp": bt = run.start_pvp()
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
	await _battle.play(bt, false)      # 11/19 전투 계산은 스레드에서 —— 끝나면 재생이 시작된다 (BattleView._simulate_async)


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
	_battle.process_mode = Node.PROCESS_MODE_INHERIT      # 11/17 hide_battle 이 멈춰 둔 재생을 다시 (다시 보기)
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
	# 11/17 온라인에서 다 안 본 전투를 닫거나(전투 창 닫기 · 다음 단계로 넘어감) 숨기면 재생을 멈춘다 —— 전엔 숨기기만 해서
	# 다음 아침(징집) 뒤에서 전투가 끝까지 돌며 효과음 · 승패 음악 · 결과 처리를 냈다 (4APT 토요일 아침)
	if online != null and _battle != null and not _battle.finished:
		_battle.process_mode = Node.PROCESS_MODE_DISABLED
		Sfx.music("prep")
	_resume_bands()
	_maybe_ending.call_deferred()


func _resume_bands() -> void:
	if not _band_busy and not _bands.is_empty():
		_next_band.call_deferred()
	if not _urgent_busy and not _urgents.is_empty():
		_next_urgent.call_deferred()


# ───────── 긴급 등용 띠 (11/10 사용자) —— 다른 사람이 기인 이상 장수를 등용했을 때. 여러 개면 하나씩 ─────────
var _urgents: Array = []
var _urgent_busy := false

func urgent(who: String, unit: String, tail := "", kind := "") -> void:      # tail —— 11/12 유저전 수훈 연속 문구 (UrgentBand.tail) · kind "fall" = 멸망 띠 (장수 없음)
	_urgents.append([who, unit, tail, kind])
	if not _urgent_busy:
		_next_urgent()


func _next_urgent() -> void:
	if _urgents.is_empty() or battle_visible():      # 전투 화면 위에는 띄우지 않는다 (전장을 가렸다) —— 전투가 끝나면 이어서
		_urgent_busy = false
		return
	_urgent_busy = true
	var e: Array = _urgents.pop_front()
	var b: Control = UrgentBand.play(self, str(e[0]), str(e[1]), str(e[2]) if e.size() > 2 else "", str(e[3]) if e.size() > 3 else "")
	b.done.connect(_next_urgent)


# ───────── 장수 사망 연출 (11/12 사용자: 온라인 장수 사망룰) —— 1일차 첫 아침, 사망 장수마다 하나씩 (DeathBand) ─────────
## 11/12 사용자: 한 장 약 1.15초 · 끝나기 0.4초 전에 다음 카드가 겹쳐 들어온다 (10명 약 8초) · 화면을 누르면 3배속, 두 번 누르면 나머지 건너뜀 ·
## 불멸이 죽으면 그 상위 신화 카드가 위에 같이 얹혀 함께 찢어진다 (Room.myth_over). 알림은 끝나고 한 번만.
const DEATH_FAST := 3.0      # 한 번 누르면 이 배속으로
var _deaths: Array = []      # 아직 시작 안 한 사망 장수
var _death_busy := false
var _death_idle := false     # 대기열이 비어 다음 카드를 기다리는 중 (남은 연출은 끝나가는 중) —— 새로 오면 바로 시작
var _death_live: Array = []  # 화면에 떠 있는 연출 노드
var _death_spd := 1.0
var _death_names: Array = [] # 이번 연속 연출에서 보여 준 이름 (끝 알림용)
var _death_total := 0

func death_card(unit: String) -> void:
	_deaths.append(unit)
	_death_total += 1
	if not _death_busy or _death_idle:
		_death_busy = true
		_death_idle = false
		_next_death.call_deferred()      # 같은 프레임에 여러 명이 오면 모두 모인 뒤 시작 (안내 글 · 명단 묶기)


func _next_death() -> void:
	if _deaths.is_empty():
		_death_idle = true
		if _death_live.is_empty():
			_death_end()
		return
	_death_busy = true
	var k: String = _deaths.pop_front()
	var m := Room.myth_over(k)
	if m != "" and _deaths.has(m):      # 같은 명단에 그 신화도 있으면 한 번에 (불멸 카드에 얹어)
		_deaths.erase(m)
	if m != "":
		_death_names.append("%s · %s" % [DB.C[k].name, DB.C[m].name])
	else:
		_death_names.append(str(DB.C[k].name))
	var b: Control = DeathBand.play(self, k, m, _death_spd, _death_total > 1)
	_death_live.append(b)
	b.next.connect(_next_death)
	b.tapped.connect(_death_tap)
	b.done.connect(func():
		_death_live.erase(b)
		if _deaths.is_empty() and _death_live.is_empty():
			_death_end())


## 누름 —— 첫 번째는 빠르게, 두 번째는 나머지를 건너뛴다
func _death_tap() -> void:
	if _death_spd < DEATH_FAST:
		_death_spd = DEATH_FAST
		for b in _death_live:
			if is_instance_valid(b):
				b.spd = DEATH_FAST
		return
	_deaths.clear()
	for b in _death_live.duplicate():
		if is_instance_valid(b):
			b.finish()


func _death_end() -> void:
	_death_busy = false
	_death_idle = false
	_death_spd = 1.0
	var names := _death_names
	_death_names = []
	_death_total = 0
	if names.is_empty():
		return
	if names.size() == 1:
		toast("%s 사망 —— 이번 판 등용 불가" % names[0], "bad")
	else:
		toast("장수 %d명 사망 —— 이번 판 등용 불가 (전황 소식에서 확인)" % names.size(), "bad")


# ───────── 한마디 구름 말풍선 (11/10 이모티콘 팝업 → 11/12 사용자: 글도 같은 구름으로, 보낸 사람의 유저 칸 옆에) —— 어디서나 (SayBubble) ─────────
var _emote_layer: Control = null

## text = 한마디 글("" 이면 이모티콘 k) · anchor = 보낸 사람의 유저 칸(화면에 보이면 그 옆, 아니면 위쪽 가운데)
func say_pop(who: String, text: String, k := -1, anchor: Control = null) -> void:
	if _emote_layer == null or not is_instance_valid(_emote_layer):
		_emote_layer = SayBubble.new()
		add_child(_emote_layer)
	_emote_layer.add(who, text, k, anchor)


func emote_pop(who: String, k: int) -> void:
	say_pop(who, "", k)


func battle_visible() -> bool:
	return _battle_layer.visible


func _on_battle_ended(res: Dictionary, _inputs: Array) -> void:
	if _dev_bonus_r >= 0.0:      # 점검 전용 —— 온라인은 재생이 결과를 다시 계산하니 여기서 서버가 준 것(dev_fake_room)과 같게 고친다
		_dev_force_bonus(res)
	_battle_res = res
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
var _view_t0 := -1      # 점검용 --gviewtime: 전투 화면을 연 실제 시각 (ms)
func _show_report(res: Dictionary) -> void:
	if _view_t0 >= 0:
		var nu := (res.get("ev", []) as Array).filter(func(e): return e.get("fx") == "ult").size()
		var nb := 0
		for g in _battle.groups:
			if g.ult != null and bool(g.get("big", true)) and not (g.ult as Dictionary).has("lead"):
				nb += 1
		print("VIEWTIME|재생 %.1f초 · 고유기 %d (큰 연출 %d) · 연출 설정 %d" % [(Time.get_ticks_msec() - _view_t0) / 1000.0, nu, nb, Settings.ult_fx])
		for g in _battle.groups:
			if g.ult != null:
				var sq = _battle.field.squads.get(g.who)
				print("  ULT|%5.1f %s %s 등급%d %s%s" % [float(g.t), g.who, sq.row.name if sq else "?", int(sq.tier) if sq else 0,
					"크게" if bool(g.get("big", true)) and not (g.ult as Dictionary).has("lead") else "가볍게",
					" (인연 합류)" if (g.ult as Dictionary).has("lead") else (" (인연 대표)" if not (g.ult.get("mates", []) as Array).is_empty() else "")])
		get_tree().quit()
	var plan := _hp_plan
	var bplan := _bonus_plan
	_hp_plan = {}
	_bonus_plan = {}
	_hide_report()
	if _battle and _battle.end_clock > 0:
		res["view_len"] = _battle.end_clock
	_report = BattleReport.make(res)
	# 11/14 감사 #9: 결과표 뒤로 전투 HUD(병력 막대 · 시계 · 아래 장수 칸)가 비쳐 보였다 —— 깔개로 어둡게 (누름은 막지 않는다: 위 띠 메뉴는 그대로)
	_report_scrim = ColorRect.new()
	_report_scrim.color = Color(DB.PAL.ink, 0.78)
	_report_scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_report_scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_battle_layer.add_child(_report_scrim)
	var w := minf(size.x - UI.SP_L * 2.0, 460.0)
	var fx_h := (HP_FX_H + 6.0) if (not plan.is_empty() or not bplan.is_empty()) else 0.0      # 민심 줄(패배) · 보너스 줄(승리)이 들어갈 자리만큼 표를 줄인다
	_report.max_h = maxf(240.0, _battle_layer.size.y - REPORT_TOP - REPORT_BOT - fx_h)
	_report.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_report.offset_left = -w / 2
	_report.offset_right = w / 2
	_report.offset_top = REPORT_TOP
	_battle_layer.add_child(_report)
	_battle_layer.move_child(_battle_done, -1)
	_battle_done.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_battle_done.offset_left = -w / 2      # 11/14 감사 #9: 버튼 폭 = 결과표 폭
	_battle_done.offset_right = w / 2
	_battle_done.offset_top = -(REPORT_BOT - 10.0)      # 11/3 사용자: 아래 장수 칸을 덮지 않게 위로 —— 결과표가 자리 잡으면 그 바로 아래로
	_battle_done.offset_bottom = _battle_done.offset_top + UI.BH_L
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame      # 표가 두 진영 중 긴 쪽에 맞춰 높이를 정한 뒤(BattleReport._ready 의 한 프레임)
	if _report == null or not is_instance_valid(_report):
		return
	if not plan.is_empty():
		_place_hp_fx(plan, _report.position.y + _report.size.y + 6.0)
	elif not bplan.is_empty():
		_place_bonus_fx(bplan, _report.position.y + _report.size.y + 6.0)
	var top := _report.get_global_rect().end.y + UI.SP_M - _battle_layer.get_global_rect().end.y + fx_h
	_battle_done.offset_top = minf(top, -(REPORT_BOT - 10.0))
	_battle_done.offset_bottom = _battle_done.offset_top + UI.BH_L


func _hide_report() -> void:
	if _report:
		_report.queue_free()
		_report = null
	if is_instance_valid(_report_scrim):
		_report_scrim.queue_free()
	_report_scrim = null
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
	var w := minf(size.x - UI.SP_L * 2.0, 460.0)
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
	if run == null:
		return
	if online == null and (not res.get("win", false) or res.get("draw", false)):      # 11/12 온라인은 승패와 상관없이 보너스가 나간다
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
	_bonus_plan = {"base": base, "ticket": tk, "big": big, "what": "대전" if (online != null and _battle_kind == "pvp") else "토벌", "flat": online != null}
	if online != null:
		var key := "%d:%d:%d:%d" % [run.day, run.phase, base, tk]
		if key != _bonus_key:
			_bonus_key = key
			var parts: PackedStringArray = Run.quest_bonus_text(base, tk, big, "대전" if _battle_kind == "pvp" else "토벌", true).split(" · ", true, 1)
			band(parts[0], DB.PAL.gold, parts[1] if parts.size() > 1 else "")


func _place_bonus_fx(plan: Dictionary, top: float) -> void:
	var w := minf(size.x - UI.SP_L * 2.0, 460.0)
	var fx := BonusFx.new()
	fx.setup(int(plan.base), int(plan.ticket), bool(plan.big), str(plan.get("what", "토벌")), bool(plan.get("flat", false)))
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
	run.finish_battle(_battle_res)
	if _dev_hploss > 0:      # 점검용 --ghploss : 연출한 만큼만 깎인 것으로 맞춘다
		run.hp = maxi(0, hp0 - _dev_hploss)
		run.last_hp_loss = _dev_hploss
	_battle_res = null
	run.save()
	PlayLog.after_battle(run)
	_battle_layer.visible = false
	_resume_bands()
	if run.last_spoil != null:
		toast("기본패 %d장 획득 — %s" % [run.last_spoil.n, run.last_spoil.src], "gain")
	go("war")


# ───────── 계보 ─────────

func _page_line() -> Control:
	# 11/3 사용자: 계보는 '조합 목록'(병종별 장수) 하나만 —— 등급표 · 진행도 · 신화 경로는 뺐다
	var v := UI.vbox(UI.SP_L)
	var p := run.pool()
	var lv0 := UI.vbox(UI.SP_S)
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
		var lv := UI.vbox(UI.SP_S)
		var rows_t := [8, 7, 6, KIIN_T, 5, 4, 3, 1]
		for t in rows_t:
			var ks: Array = Run.by_tier_tag(5 if t == KIIN_T else t, tag).filter(func(k): return DB.is_kiin(k) == (t == KIIN_T))
			if ks.is_empty():
				continue
			lv.add_child(UI.lbl("기인" if t == KIIN_T else DB.TIER[t].n, UI.FS_BODY, DB.KIIN_COL if t == KIIN_T else DB.TIER[t].c, true))
			var f := UI.flow(6)
			for k in ks:
				var c: Dictionary = DB.C[k]
				var has: bool = p.get(k, 0) > 0
				var b := UI.btn("%s%s%s" % [c.name, "★" if c.kind == "myth" else "", (" ×%d" % p[k]) if has else ""], func(): recipe_sheet(k) if DB.RECOF.has(k) else card_info(k), "", UI.BH_S)
				b.add_theme_font_size_override("font_size", UI.FS_BODY)
				b.add_theme_color_override("font_color", DB.tier_color(k) if has else Color(DB.PAL.paper, 0.55))
				if has:      # 11/20 올리면 등급색 테두리가 사라졌다 —— 올림 · 눌림도 테두리를 지킨다
					UI.btn_styles(b, UI.flat(DB.PAL.ink3, DB.tier_color(k), 1, 8, 10), UI.flat(DB.PAL.ink4, DB.tier_color(k), 1, 8, 10), UI.flat(DB.PAL.ink4, DB.PAL.gold, 1, 8, 10))
				f.add_child(b)
			lv.add_child(f)
		lv0.add_child(UI.panel(lv))
	v.add_child(UI.sect("조합 목록", lv0))
	return v


# ───────── 순위 ─────────

func _standings() -> Control:
	var rows := [{"name": "나", "epi": "%d승 %d패 · 민심 %d" % [run.my_w, run.my_l, run.hp],
		"fac": "촉", "pv": run.my_pv(), "me": true, "dead": run.over != null and not run.over.win}]
	for b in run.bots:      # 11/12 사용자: 봇의 칭호("전력 1위 사냥꾼" 등)는 뺀다 —— 전적만. 온라인 사람 자리는 서버가 적은 "사람 · 접속 끊김 …" 그대로
		var epi := str(b.epi) if str(b.epi).begins_with("사람") else "%d승 %d패" % [int(b.get("w", 0)), int(b.get("l", 0))]
		if not str(b.epi).begins_with("사람") and b.has("hp"):
			epi += " · 민심 %d" % int(b.hp)      # 11/12 최후 1인 —— 봇도 민심이 있다
		rows.append({"name": b.name, "epi": epi, "fac": b.fac, "pv": roundi(b.pv), "me": false, "dead": bool(b.get("dead", false))})
	rows.sort_custom(func(a, b): return a.pv > b.pv if a.dead == b.dead else b.dead)      # 남은 세력이 위, 멸망한 세력은 아래
	var v := UI.vbox(UI.SP_S)
	for i in rows.size():
		var r: Dictionary = rows[i]
		var h := UI.hbox(UI.SP_M)
		var nl := UI.lbl(str(i + 1), UI.FS_TITLE, DB.PAL.gold if r.me else DB.PAL.text_dim, true)
		nl.custom_minimum_size = Vector2(22, 0)
		nl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		h.add_child(nl)
		# 11/5 사용자: 봇 플레이어의 세력 표기 · PV 는 순위에서 뺀다. 11/9 사용자: 내 줄의 '촉' 칩도 뺀다
		var nv := UI.vbox(0)
		nv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		nv.add_child(UI.lbl(r.name, UI.FS_LABEL, DB.PAL.gold if r.me else DB.PAL.paper, true))
		var el := UI.lbl(r.epi, UI.FS_CAP, DB.PAL.text_dim)
		el.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		el.clip_text = true
		nv.add_child(el)
		h.add_child(nv)
		if r.me or r.dead:
			var pl := UI.lbl("멸망" if r.dead else "%d PV" % r.pv, UI.FS_LABEL, DB.PAL.danger if r.dead else DB.PAL.bamboo, true)
			pl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			h.add_child(pl)
		var pnl := UI.panel(h, 10)
		if r.me:
			pnl.add_theme_stylebox_override("panel", UI.flat(DB.PAL.ink3, DB.PAL.gold, 1, 8, 10))
		v.add_child(pnl)
	return v


func _page_rank() -> Control:
	var v := UI.vbox(UI.SP_L)
	if online != null and online.in_game and not online.room.is_empty():
		v.add_child(online.peers_section())      # 11/11 사용자: 다른 유저의 민심 · 핵심 유닛(기인 · 초월 · 불멸 · 신화)
	else:
		v.add_child(_peers_solo())      # 11/12 사용자: 혼자 하기에서도 봇의 핵심 유닛 · 민심을 기록 탭에
	return v


## 혼자 하기의 「군웅」 —— 온라인 Online.peers_section 과 같은 칸: 나(민심 게이지 · 핵심 유닛) + 봇마다 (전력 높은 순)
func _peers_solo() -> Control:
	var v := UI.vbox(UI.SP_S)
	var keys := Room.key_cards(run)
	v.add_child(Online.peer_row(self, {"name": "나", "me": true, "online": true, "dead": run.over != null and not run.over.win,
		"hp": run.hp, "key": keys if not keys.is_empty() else Room.featured_cards(run.board), "has_key": true,
		"plan": run.tk_plan if Run.tac_on else []}))
	var bs: Array = run.bots.duplicate()
	bs.sort_custom(func(a, b): return a.pv > b.pv)
	for b in bs:
		v.add_child(Online.peer_row(self, bot_row(run, b)))
	return UI.sect("군웅 현황", v)


## 봇 한 줄 (Online.peer_row 의 줄) —— 11/12 최후 1인: 봇도 민심이 있다(멸망하는 세력) —— 민심 게이지 + 전적. 민심을 주지 않는 옛 서버의 봇만 글(전적)로. 핵심 유닛은 bot_key
static func bot_row(r: Run, b: Dictionary) -> Dictionary:
	var note := "%d승 %d패" % [int(b.get("w", 0)), int(b.get("l", 0))]
	if int(b.get("strikes", 0)) > 0:
		note += " · 토벌 실패 %d" % int(b.strikes)
	var keys := bot_key(r, b)
	# 11/25 사용자 "유저봇 군략도 ? 히든": 단계 계획은 사람처럼 가린다 —— 혼자 하기는 늘 빈 계획, 온라인은 서버 거울이 대전 단계에만 채운다 (Room._mirror)
	var plan: Array = b.get("plan", []) if r.mp and b.get("plan") is Array else []
	var own: Array = b.get("own", []) if b.get("own") is Array else []      # 11/21 늘 켜지는 군략 (온라인은 서버 거울) —— 늘 공개
	if Run.tac_on and not r.mp and not bool(b.get("dead", false)):
		own = (r._bot_side_of(b.duplicate(true)).get("plan", {}) as Dictionary).get("own", [])
	return {"name": str(b.name), "me": false, "online": true, "dead": bool(b.get("dead", false)), "bot": true, "note": note,
		"hp": clampi(int(b.hp), 0, Run.HP_MAX) if b.has("hp") else -1,
		"key": keys if not keys.is_empty() else Room.featured_cards(b.get("army", [])), "has_key": true, "plan": plan, "own": own,
		"hist": b.get("tk_hist") if b.get("tk_hist") is Array else []}      # 지난 대전 계획 (이미 뒤집힌 카드)


## 봇의 핵심 유닛 (11/12 사용자) —— 11/12 부터 봇 군세는 봇마다 한 번 만들어 자라는 것(b.army, Run.bot_grow)이라 그 군세의 기인 이상(Room.is_urgent_unit)을 높은 등급부터 보인다.
## 군세를 주지 않는 옛 서버만 예전 방식: 지금 전력 · 성향으로 한 번 뽑아 본 예시 —— 판 · 요일 · 페이즈 · 봇 이름으로 정한 따로 된 씨앗이라 Run 의 rng 를 건드리지 않고, 같은 때에는 늘 같다
static var _bot_key_cache := {}
static func bot_key(r: Run, b: Dictionary) -> Array:
	# 11/12 군세가 유지된다(봇마다 한 번 만들어 자란다) —— 서버 · 혼자 하기가 군세를 주면 실제 군세의 기인 이상을 그대로 보인다. 군세가 없는 옛 서버만 아래 예시
	var army: Array = b.get("army", [])
	if army.size() == 9:
		var real := []
		for k in army:
			if DB.C.has(k) and Room.is_urgent_unit(str(k)) and not real.has(str(k)):
				real.append(str(k))
		real.sort_custom(func(x, y):
			var rx := Room.key_rank(x)
			var ry := Room.key_rank(y)
			return rx > ry if rx != ry else x < y)
		return real
	var pv := float(b.get("pv", 0.0)) * Run.BOT_PV_MUL
	if r.phase_idx() <= 0:
		pv = maxf(pv, Run.BOT_OPEN_PV)
	var ck := "%s|%s|%d|%d|%d" % [str(r.rng.seed), str(b.name), r.day, r.phase, roundi(pv)]
	if _bot_key_cache.has(ck):
		return _bot_key_cache[ck]
	var rg := RandomNumberGenerator.new()
	rg.seed = hash(ck)
	var eb := DB.gen_board(pv, str(b.get("style", "균형")), rg)
	var out := []
	for k in eb.cards:
		if Room.is_urgent_unit(str(k)) and not out.has(str(k)):
			out.append(str(k))
	out.sort_custom(func(x, y):
		var rx := Room.key_rank(x)
		var ry := Room.key_rank(y)
		return rx > ry if rx != ry else x < y)
	if _bot_key_cache.size() > 64:
		_bot_key_cache.clear()
	_bot_key_cache[ck] = out
	return out


# ───────── 멸망 · 엔딩 연출 (11/12 사용자: "최종 멸망 이후에 엔딩씬이 없다") ─────────
## 판 끝 처리(run.over —— 혼자 하기 · 온라인 모두)를 받는 얇은 접점. 규칙(멸망 · 승리 판정)은 Run · Room 이 정하고 여기선 보여 주기만 한다.
## info = {win: bool, rank: int|String, by: String(멸망시킨 상대 이름, 없으면 ""), by_human: bool, days: int, w: int, l: int,
##         deck: Array(카드 id, 높은 등급 순), playtime: int(초)} + 고를 것 {name, glyph, msg, lord, again_text, watch}
## 다른 사람의 멸망은 기존 멸망 띠(urgent "fall") 그대로 —— 이 함수는 내 판이 끝났을 때만.
var _ending: Control = null
var _ending_key := ""          # 이미 보여 준 엔딩 (같은 판에서 두 번 띄우지 않는다 —— 온라인은 상태마다 Run 을 새로 만든다)
var _play_t0 := -1             # 이번 판을 시작(또는 이어 하기)한 시각 (ms) —— 엔딩의 플레이 시간

func show_ending(info: Dictionary) -> void:
	if is_instance_valid(_ending):
		_ending.queue_free()
	close_sheet()
	_bands.clear()
	_hide_band()
	_ending = Ending.play(self, info, self)
	_ending.home.connect(func():
		_ending_close()
		if online != null:
			online.leave()
		elif run != null:
			run.save()
		if _title != null:
			_title.queue_free()
		_build_title())
	_ending.again.connect(func():
		_ending_close()
		if online != null and _solo_unfinished():
			online.leave()
			_continue()      # 온라인에서 끝났는데 이어 하던 혼자 하기 판이 있으면 덮어쓰지 않고 이어 한다
			return
		if online == null:
			Run.delete_save()
		_new_game())
	_ending.watch.connect(func():
		_ending_close()
		Sfx.music("prep")
		render())


func _ending_close() -> void:
	if is_instance_valid(_ending):
		_ending.queue_free()
	_ending = null


func _solo_unfinished() -> bool:
	if not Run.has_save():
		return false
	var r := Run.load_saved()
	return r != null and r.over == null


## 판이 막 끝났으면 엔딩을 띄운다 (render · 전투 화면을 닫을 때 부른다). 전투를 보는 중 · 제목 화면 · 이미 띄운 판이면 건너뛴다
func _maybe_ending() -> void:
	if run == null or run.over == null or battle_visible() or is_instance_valid(_ending):
		return
	if _title != null and is_instance_valid(_title) and _title.visible:
		return
	if online != null and (online._await_battles or not online.watch.is_empty()):
		return      # 온라인 —— 이번 단계 전투를 다 본 뒤에 (11/16 전투 목록이 아직 안 온 동안에도 기다린다)
	var key := "%s|%s|%s" % [str(online.room.get("code", "")) if online != null else "solo", str(run.over.get("win", false)), str(run.over.get("msg", ""))]
	if key == _ending_key:
		return
	_ending_key = key
	show_ending(ending_info())


## 지금 Run(과 온라인 방 정보)으로 엔딩 info 를 만든다
func ending_info() -> Dictionary:
	var o: Dictionary = run.over if run.over != null else {"win": false, "msg": ""}
	var win := bool(o.get("win", false))
	var by := str(o.get("by", ""))
	var by_human := bool(o.get("by_human", false))
	var lr = run.last_result
	if by == "" and not win and lr is Dictionary and not bool(lr.get("win", true)) and str(lr.get("kind", "")) != "quest":
		var parts := str(lr.get("title", "")).split(" · ", false, 1)      # "대전 · 상대" · "8강 · 상대"
		if parts.size() > 1:
			by = parts[1]
	var me_name := "나"
	var rank = o.get("rank", 0)
	if online != null and not online.room.is_empty():
		var my: Dictionary = online.me()
		me_name = str(my.get("name", "나"))
		var alive := 0
		for st in online.room.get("seats", []):
			if st is Dictionary and str(st.get("name", "")) == by and by != "":
				by_human = by_human or bool(st.get("human", false))
			if st is Dictionary and not bool(st.get("dead", false)) and str(st.get("name", "")) != me_name:
				alive += 1
		if not (rank is String) and int(rank) <= 0:
			rank = 1 if win else alive + 1
	elif not (rank is String) and int(rank) <= 0:
		if win:
			rank = 1
		else:      # (옛 토너먼트 순위는 11/12 최후 1인으로 없어졌다 —— Run.over.rank 가 늘 있다)
			rank = 1 + run.bots.filter(func(b): return not bool(b.get("dead", false))).size()
	var deck: Array = []
	for k in run.board:
		if k != null and DB.C.has(str(k)) and not deck.has(str(k)):
			deck.append(str(k))
	deck.sort_custom(func(a, b): return DB.C[a].tier > DB.C[b].tier if DB.C[a].tier != DB.C[b].tier else a < b)
	var pt := 0 if _play_t0 < 0 else int((Time.get_ticks_msec() - _play_t0) / 1000)
	_play_t0 = -1
	var info := {"win": win, "rank": rank, "by": by, "by_human": by_human, "days": mini(run.day + 1, 99), "w": run.my_w, "l": run.my_l,
		"deck": deck, "playtime": pt, "name": me_name, "msg": str(o.get("msg", "")), "glyph": "蜀"}
	if online != null:
		info["watch"] = not win and str(online.room.get("stage", "")) != "over"
		if _solo_unfinished():
			info["again_text"] = "혼자 하기 이어 하기"
		else:
			info["again_text"] = "혼자 하기"
		if me_name != "":
			info["glyph"] = me_name.substr(0, 1)
	return info


func _over_panel() -> Control:
	var v := UI.vbox(UI.SP_L)
	var o: Dictionary = run.over
	var pv := UI.vbox(UI.SP_S)
	var t := UI.lbl("천하 통일" if o.win else "멸망", UI.FS_DISPLAY, DB.PAL.jade if o.win else DB.PAL.danger, true)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pv.add_child(t)
	var m := UI.lbl(o.msg, UI.FS_LABEL, DB.PAL.paper)
	m.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UI.wrap_text(m)
	pv.add_child(m)
	var rk := ("최종 %d위 / %d · " % [int(o.rank), int(o.get("of", run.bots.size() + 1))]) if o.has("rank") else ""      # 11/12 최후 1인 순위
	var s := UI.lbl("%s%d일차 · 최종 %s명 · %d PV · %d승 %d패" % [rk, run.day + 1, Battle.num(run.board_power()), run.my_pv(), run.my_w, run.my_l], UI.FS_BODY, DB.PAL.bamboo)
	s.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UI.wrap_text(s)
	pv.add_child(s)
	v.add_child(UI.panel(pv, 24))
	v.add_child(_standings())
	if online != null:
		v.add_child(UI.btn("처음 화면으로", func():
			online.leave()
			_title.queue_free()
			_build_title(), "pri", UI.BH_L))
		return v
	v.add_child(UI.btn("새 판 시작", func():
		Run.delete_save()
		_new_game(), "pri", UI.BH_L))
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
	for dk in a:      # 11/20 점검 인자(--g…)가 하나라도 있으면 사용자 저장(save.json · pins.json)을 쓰지 않는다
		if str(dk).begins_with("g"):
			Run.dev_nosave = true
			break
	if a.has("gtitle"):      # 점검용 —— --gtitle=sl | s | l | n : 타이틀 이어하기 버튼을 저장 · 대전 있음/없음으로 꾸며 보이고 상태를 찍는다 (11/21)
		_dev_title = {"save": "s" in a.gtitle, "live": "l" in a.gtitle}
		_build_title()
		for k in _title_info:
			print("TITLE ", k, " 글=", _title_info[k][0], " 부제=", _title_info[k][1], " 켜짐=", _title_info[k][2])
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
	if a.has("ghard") and run != null:      # 점검용 —— --ghard : 험지 토벌을 고른 채로 (11/13 글자 밀림 점검 · 저장하지 않는다)
		run.quest_hard = true
		render()
	if a.has("ggrain") and run != null:      # 점검용 —— --ggrain=40 : 군량 (11/13 · 저장하지 않는다)
		run.grain = int(a.ggrain)
		render()
	if a.has("glock") and run != null:      # 점검용 —— --glock=K01:정지,K07:dead : 장수 선점제 · 사망룰로 잠긴 장수 (11/12 · 저장하지 않는다). --gdeath=K07 은 사망 연출
		for s_ in str(a.glock).split(",", false):
			var kv_ := s_.split(":")
			if DB.C.has(kv_[0]):
				run.locked[kv_[0]] = {"dead": 1} if kv_.size() < 2 or kv_[1] == "dead" else {"by": kv_[1]}
		if a.has("gftier"):
			forge_tier = int(a.gftier)      # 조합 탭 등급 거르기 (9 = 기인)
		render()
	if a.has("gending"):      # 점검용 —— --gending=lose | win | lose_user : 멸망 · 엔딩 연출을 바로 띄운다 (11/12 · 저장하지 않는다). --gnew 와 함께 쓰면 그 판의 편성 · 전적
		if run == null:
			PlayLog.enabled = false
			run = Run.new()
			run.new_game(7)
		_title.visible = false
		var inf := ending_info()
		inf.win = str(a.gending) == "win"
		inf.by = "조조팬" if str(a.gending) == "lose_user" else ("원소" if str(a.gending) == "lose" else "")
		inf.by_human = str(a.gending) == "lose_user"
		inf.rank = 1 if inf.win else 5
		inf.days = 7 if inf.win else 5
		inf.playtime = 1834
		if (inf.deck as Array).size() < 3:
			var hi := DB.C.keys().filter(func(k): return int(DB.C[k].tier) >= 6 and DB.portrait(k) != null)
			hi.sort_custom(func(x, y): return DB.C[x].tier > DB.C[y].tier if DB.C[x].tier != DB.C[y].tier else x < y)
			inf.deck = hi.slice(0, 9)
		inf.w = maxi(int(inf.w), 9)
		inf.l = maxi(int(inf.l), 4)
		if a.has("gendwatch"):      # 점검용 —— 온라인 요약처럼 관전 버튼 · 긴 문구 (버튼이 화면 안에 남는지)
			inf["watch"] = true
			inf["msg"] = "대전 · 조조팬 패배 —— 민심이 바닥나 세력이 멸망했다"
			inf["again_text"] = "혼자 하기 이어 하기"
		_ending_key = "dev"
		show_ending(inf)
	if a.has("gdeath"):
		for k_ in str(a.gdeath).split(",", false):
			if DB.C.has(k_):
				death_card(k_)
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
	if a.has("gdraw") and run != null and not run.drawn:      # 점검용 —— 이번 준비 단계의 징집을 이미 받은 상태로 (11/25 자동 징집 시안)
		run.do_draw()
		render()
	if a.has("gopen"):
		for key in str(a.gopen).split(","):
			_open[key] = true
		render()
	if a.has("grejoin"):      # 점검용 —— 타이틀의 「대전으로 돌아가기」를 누른 것처럼 (--grejoin=기다릴 초, 11/19). 결과를 한 줄 찍는다
		var live := Online.live_mark()
		print("REJOIN 표시 ", live)
		if not live.is_empty():
			if online == null:
				online = Online.new()
				online.gs = self
				add_child(online)
			online.rejoin(live)
			await get_tree().create_timer(float(a.grejoin)).timeout
			print("REJOIN 결과 in_game=", online.in_game, " 방 ", online.room.get("code", ""), " 일차 ", run.day if run else -1, " 표시 남음 ", not Online.live_mark().is_empty())
	if a.has("gonline"):
		# 점검용 온라인 —— --gonline=ws://… --gname=이름 (--gcreate=fast|normal|test [--gmax=4|6|8] --gstart=사람수 | --gjoin=방장이름) --gauto
		_go_online()
		online.net.player = str(a.get("gname", "시험"))
		online.net.token = ""      # 같은 PC 의 창들이 net.cfg 를 같이 쓴다 —— 시험 창은 새 토큰
		online.net.consent_ver = NetClient.CONSENT_VER      # 점검 창은 기록에 동의한 것으로 (메모리만 —— net.cfg 에는 남기지 않는다)
		online.dev_auto = a.has("gauto")
		online.net.connect_to(str(a.gonline))
		await online.net.opened
		if a.has("gdrop"):      # 11/24 점검: 전투를 보는 중 --gdrop 초 뒤 연결을 끊는다 (단계마다 한 번) —— 재접속 뒤 같은 전투를 다시 트는지 · 준비가 남는지
			_dev_drop_loop(float(a.gdrop))
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
		render()
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
			"update": _update_sheet(int(kv[1]) if kv.size() > 1 else -1)      # 11/20 업데이트 내역 시트 (--gsheet=update:2 = 앞에서 셋째 판도 펼친 채)
			"uniq": _unique_sheet()
			"shop": _shop_sheet()      # 11/13 군량 상점 (--ggrain=40 과 함께)
			"tacoffer":      # 11/15 군략 3택1 (--gsheet=tacoffer:카드 = 고른 채로). 11/25 3택1 이 비었으면 새로 편다 (저장하지 않는다)
				if run.tk_offer.is_empty():
					run.tk_new_offer()
				TacUI.offer_sheet(self, kv[1] if kv.size() > 1 else "")
			"tacres":      # 11/25 연구 3택1 (--gsheet=tacres:명마+강궁 = 그 연구를 고른 뒤 —— 갈래 줄 ✓ · 중급이 후보에 오르는지)
				for rid in (kv[1].split("+") if kv.size() > 1 and kv[1] != "" else []):
					run.rs_done[rid] = int(run.rs_done.get(rid, 0)) + 1
				run.tk_new_offer()
				TacUI.res_sheet(self, kv[2] if kv.size() > 2 else "")
			"tachand": TacUI.hand_sheet(self, int(kv[1]))      # 11/15 군략 손패 시트 (단계 0 · 1 · 2)
			"tacstat": TacUI.status_sheet(self)      # 11/25 군략 현황 시트 (--gsheet=tacstat —— 봇 계획이 가려지는지)
			"gacha":      # 11/13 아이템 뽑기 결과 (--ggrain=80 --gsheet=gacha:10) · gacha:pity 는 천장 직전에서 한 번(고대 연출)
				if kv.size() > 1 and kv[1] == "pity":
					run.gacha_pity = Run.GACHA_PITY - 1
				var gr = run.command("gacha", [int(kv[1]) if kv.size() > 1 and kv[1] != "pity" else (1 if kv.size() > 1 else 10)])
				_shop_sheet(gr if gr is Array else [])
				_gacha_fx(gr if gr is Array else [])
			"urgent_item":      # 11/13 고대 아이템 속보 띠 (--gsheet=urgent_item)
				urgent("이한솔국지", "", "고대 환두대도", "item")
			"sell": _sell_sheet(kv[1])      # 11/13 보유 카드 꾹 누르기 판매 시트
			"recipes": recipes_sheet()      # 11/25 전체 조합법 시트
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
				if kv.size() > 3 and kv[3] == "noonend":      # 점검용 —— 11/12 4일차 첫 아침에 서버가 보내는 「토벌 종료」 소식이 온 것처럼 (가운데 띠 + 소식 줄)
					online._on_msg({"t": "news", "list": [{"text": "토벌 종료 —— 이제부터 %s" % Room.cut_text("fast"), "kind": "news", "who": "천명", "id": 9, "line": Room.cut_text("fast"), "band": "noon_end", "when": "4일차 준비"}]})
				if kv.size() > 3 and kv[3] in ["presence", "fall"]:      # 점검용 —— 11/12 존재감: 상태 아이콘 · 설욕전 · 한마디 말풍선(유저 칸 옆) / fall = 멸망 띠
					var sts := ["idle", "busy", "ready", "pvp"]
					var ss: Array = online.room.seats
					online._on_msg({"t": "act_st", "st": ss.map(func(x): return sts[ss.find(x) % 4] if x.human else "")})
					if online.room.get("foe") is Dictionary:
						online.room.foe["revenge"] = true
						render()
					await get_tree().create_timer(0.3).timeout
					online._on_msg({"t": "say", "who": "장수214", "text": "다음엔 이깁니다"})
					online._on_msg({"t": "emote", "who": str(ss[0].name), "i": 1})
					if kv[3] == "fall":
						online._on_msg({"t": "news", "list": [{"text": "장수377의 나라가 무너졌습니다 —— 남은 군주 7명", "kind": "news", "who": "장수377", "id": 8, "line": "남은 군주 7명", "band": "fall", "hot": 1}]})
			"pick":
				if not run.picked:
					act("begin_picks", ["phase", -1])
				if not run.ticket_tiers().is_empty():
					picker(run.ticket_tiers()[0])
			"online": _go_online()
	if a.has("gtac") and run != null:      # 점검용 —— 11/21 군략 현황: --gtac=board (현황 시트) · hand:1 (손패 시트 2단계) · war (전투 탭). 가짜 손패 · 다른 자리 군략을 채운다 (저장하지 않는다)
		TacUI.dev_fill(self)
		var tv: PackedStringArray = str(a.gtac).split(":")
		match tv[0]:
			"board": TacUI.status_sheet(self)
			"hand": TacUI.hand_sheet(self, int(tv[1]) if tv.size() > 1 else 0)
			"war": go("war")
			"rank": go("rank")
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
			await get_tree().process_frame
			var confirm := _find_btn(_sheet, "받기 확정")
			if confirm != null:
				confirm.pressed.emit()
	if a.has("gtitle"):
		_title.visible = true
	if a.has("gdots") and not Settings.PAINTING_ONLY:          # 점검용 —— 전장 표현 (1 점묘 · 0 3D, 저장하지 않는다)
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
	if a.has("gtype2") and not Settings.PAINTING_ONLY:          # 점검용 —— 타입2 전장 (저장하지 않는다)
		Settings.type2 = a.gtype2 != "0"
	if a.has("gsumuk") and not Settings.PAINTING_ONLY:          # 점검용 —— 수묵 화풍으로 (저장하지 않는다)
		Settings.sumuk = a.gsumuk != "0"
		if _battle:
			_battle.apply_style()
	if a.has("gbattle"):
		await get_tree().process_frame
		if a.has("gultfx"):      # 점검용 —— 고유기 연출 설정을 저장하지 않고 이번만 (0 모두 · 1 중요한 것만 · 2 간단히)
			Settings.ult_fx = int(a.gultfx)
		_view_t0 = Time.get_ticks_msec() if a.has("gviewtime") else -1      # 점검용 —— 결과표가 뜰 때까지 실제 시간 (11/22 고유기 연출 나누기)
		await _start(a.gbattle)
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
					if q.camp == "A" and DB.has_ult(q.cid):      # 기인은 전설 등급 값이지만 고유기가 있다
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
		# 11/19 컷인 중 · 평소를 갈라 잰다 (고유기마다 끊기는지) + 뷰포트 GPU · CPU 렌더 시간
		var by_cut := {false: PackedFloat32Array(), true: PackedFloat32Array()}
		var vrid := get_viewport().get_viewport_rid()
		RenderingServer.viewport_set_measure_render_time(vrid, true)
		var gpu_sum := 0.0
		var rcpu_sum := 0.0
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
			by_cut[_battle != null and _battle.hud != null and _battle.hud.cut != null].append(ftm)
			gpu_sum += RenderingServer.viewport_get_measured_render_time_gpu(vrid)
			rcpu_sum += RenderingServer.viewport_get_measured_render_time_cpu(vrid)
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
		for ck in [false, true]:
			var arr: PackedFloat32Array = by_cut[ck]
			if arr.is_empty():
				continue
			arr.sort()
			var sm := 0.0
			for x in arr:
				sm += x
			print("  %s %d프레임 · 평균 %.2fms · p95 %.2f · p99 %.2f · 최대 %.1f" % ["컷인 중" if ck else "평소", arr.size(), sm / arr.size(),
				arr[int((arr.size() - 1) * 0.95)], arr[int((arr.size() - 1) * 0.99)], arr[-1]])
		print("  렌더 GPU %.2fms · 렌더 CPU %.2fms (프레임 평균) · 창 %s" % [gpu_sum / maxi(1, fr), rcpu_sum / maxi(1, fr), str(get_window().size)])
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
		if a.has("gsscroll"):      # 점검용 —— 열린 시트를 이 위치까지 내린다 (긴 시트의 아래쪽: 온라인 방 목록 · 디테일창 조합법, 11/20)
			_sheet_scroll.scroll_vertical = int(a.gsscroll)
			await get_tree().process_frame
		if a.has("ghand") and is_instance_valid(_hand_scroll):      # 점검용 —— 징집 보유 목록을 이 위치까지 내린다 (큰 수면 맨 아래, 11/7)
			_hand_scroll.scroll_vertical = int(a.ghand)
			await get_tree().process_frame
		if a.has("ghover"):      # 점검용 —— --ghover=x,y (논리 좌표) : 그 자리에 마우스를 올린 모양으로 찍는다. x,y,p 면 누른 채로 (11/20 버튼 올림 · 눌림 모양 점검)
			# 그 자리의 버튼 크기를 평소 → 올림(→ 눌림) 순서로 한 줄 찍는다 (크기가 바뀌면 줄이 밀린다는 뜻)
			var hp_: PackedStringArray = str(a.ghover).split(",")
			var hpos := Vector2(float(hp_[0]), float(hp_[1]))
			var hb_: Button = _btn_at(self, hpos)
			var hlog := "ghover %s 「%s」 평소 %s" % [str(hpos), hb_.text if hb_ != null else "(버튼 없음)", str(hb_.size) if hb_ != null else "-"]
			var mm := InputEventMouseMotion.new()
			mm.position = hpos
			mm.global_position = hpos
			get_viewport().push_input(mm, true)
			for i in 4:
				await get_tree().process_frame
			if hb_ != null:
				hlog += " · 올림 %s(상태 %d)" % [str(hb_.size), hb_.get_draw_mode()]
			if hp_.size() > 2:
				var mb_ := InputEventMouseButton.new()
				mb_.button_index = MOUSE_BUTTON_LEFT
				mb_.pressed = true
				mb_.position = hpos
				mb_.global_position = hpos
				get_viewport().push_input(mb_, true)
				for i in 12:      # TouchButton 눌림 줄어듦(0.05초)이 끝난 뒤
					await get_tree().process_frame
				if hb_ != null:
					hlog += " · 눌림 %s(상태 %d · 배율 %.2f)" % [str(hb_.size), hb_.get_draw_mode(), hb_.scale.x]
			print(hlog)
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


## 점검용 —— 그 자리(논리 좌표)에서 맨 위에 그려지는 보이는 버튼 (--ghover)
func _btn_at(n: Node, pos: Vector2) -> Button:
	var cs := n.get_children()
	for i in range(cs.size() - 1, -1, -1):
		var c: Node = cs[i]
		if c is CanvasItem and not c.visible:
			continue
		var r := _btn_at(c, pos)
		if r != null:
			return r
		if c is Button and c.get_global_rect().has_point(pos):
			return c
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

	## 11/20 조작: 보이는 높이는 24 —— 누르는 범위는 UI.HIT 까지 아래로만 넓힌다 (위는 군량 표시가 붙어 있고, 아래 플레이타임 글은 입력을 안 받는다)
	func _has_point(p: Vector2) -> bool:
		return Rect2(Vector2.ZERO, size).grow_individual(0, 0, 0, maxf(0.0, UI.HIT - size.y)).has_point(p)

	func _gui_input(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
			if e.pressed:
				_press = e.position
			else:
				if _press != Vector2.INF and e.position.distance_to(_press) <= Press.TAP_SLOP and _has_point(e.position):
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
	var flat := false      # 11/12 온라인 —— 승패 · 성과 차등 없는 보너스 (「대승!」 대신 「보너스」)
	var _t := 0.0
	var _chime := false

	func setup(b: int, t: int, is_big: bool, w := "토벌", is_flat := false) -> void:
		base = b
		ticket = t
		big = is_big
		what = w
		flat = is_flat
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
		var head := (what + " 보너스") if flat else ((what + " 대승!") if big else (what + " 선전!"))
		var f: Font = DB.title_font(20)
		draw_string(f, Vector2(16, h / 2 + 8), head, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(P.gold.lightened(0.2), a))
		var parts := []
		if base > 0:
			parts.append("기본패 +%d" % base)
		if ticket > 0:
			parts.append(Run.bonus_ticket_text(what, ticket))
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
	var hint := ""      # 키보드 단축키 글자 (PC 만 —— 왼쪽 위 귀퉁이에 작게)
	var _press := Vector2.INF
	var _selected := UI.flat(Color(DB.PAL.gold, 0.10), Color(DB.PAL.gold, 0.26), 1, 4, 0)
	var _pressed := UI.flat(DB.PAL.ink3, Color.TRANSPARENT, 0, 4, 0)

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		custom_minimum_size = Vector2(56, 56)

	func _gui_input(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
			if e.pressed:
				_press = e.position
			else:
				var tapped_inside := _press != Vector2.INF and Rect2(Vector2.ZERO, size).has_point(e.position)
				_press = Vector2.INF
				if tapped_inside:
					tapped.emit(key)
			queue_redraw()

	func _draw() -> void:
		var col: Color = DB.PAL.gold if on else DB.PAL.text_dim
		var c := Vector2(size.x / 2, 22)
		if on or _press != Vector2.INF:
			draw_style_box(_pressed if _press != Vector2.INF else _selected, Rect2(5, 4, size.x - 10, size.y - 8))
		_icon(c, col)
		draw_string(DB.title_font(13) if on else DB.font_body, Vector2(0, size.y - 8), text, HORIZONTAL_ALIGNMENT_CENTER, size.x, 13, DB.PAL.paper if on else col)
		if hint != "":
			draw_string(DB.font_body, Vector2(10, 17), hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(col, 0.55))
		if badge >= 0:
			var bp := c + Vector2(15, -10)
			if badge == 0:
				draw_circle(bp, 5, DB.PAL.ink)
				draw_circle(bp, 3.5, DB.PAL.danger)
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


func _dev_drop_loop(sec: float) -> void:
	var done := {}
	while is_inside_tree():
		await get_tree().create_timer(0.25).timeout
		var sno := int(online.room.get("stage_no", -1))
		if done.has(sno) or not battle_visible() or _battle.finished:
			continue
		done[sno] = true
		await get_tree().create_timer(sec).timeout
		print("DROP| 단계 %d —— 연결을 끊는다" % sno)
		online.net.close()
