class_name BattleView
extends Control
## 실시간 3D 전장 —— 판정은 Battle(턴제 엔진)이 끝낸다. 그리기는 War3D 가 맡는다.
## 판정은 Battle(턴제 엔진)이 끝낸다. 이 화면은 그 결과를 시간축에 다시 깔아
## 행동들이 겹쳐 흐르게 재생한다. 근접 부대는 실제로 달려가 맞붙고, 궁병은 화살을 날리고,
## 지략 계열은 불·물·혼란을 퍼뜨린다. 병력이 줄면 병사 인형이 쓰러진다.
##
## 시간 배치: 입장 OPEN 초 → 행동 하나마다 STEP 초씩 어긋나게 시작 → 턴 끝 정산.
## 근접 행동은 부대가 상대에 닿을 때까지 결과 적용을 미룬다. 병력은 이벤트별 증감(델타)으로
## 적용하므로 행동끼리 순서가 뒤섞여도 최종 병력은 엔진과 같다.
##
## 피해 흘려 넣기: 이벤트가 오면 목표 병력(cur)만 바꾸고, 화면 병력(shown)은 그 부대가
## 다음에 피해를 받을 때까지(0.8~3.5초) 꾸준히 따라간다. 그래서 맞붙어 있는 동안 병사가
## 한 명씩 계속 쓰러진다. 병력이 다해 무너지는 패주는 남은 병사가 다 쓰러진 뒤에 표시한다.
## 다음 이벤트가 오기 전에 따라잡으므로 최종 값은 엔진과 같다 (_finish 에서 확인한다).
##
## 화면(휴대폰 세로): 위 띠(제목 · 배속 · [한마디] · [결과로] · ⋯ 메뉴) / 전장 / 아래 독(아군 장수 카드 격자).
## ⋯ 메뉴는 오른쪽에서 열린다 —— 진행(배속 · 결과로 건너뛰기) · 전투 기록 (11/9 정리).
## 온라인 재생(locked)은 서버 결과를 그대로 재생한다 —— '결과로' 로 끝까지 건너뛸 수 있고, 그러면 본 것으로 친다 (11/9 사용자).
## 한마디(say_cb): 온라인이면 위 띠에 [한마디] 가 보이고, 받은 한마디는 전장 왼쪽 위에 작은 줄로 잠시 뜬다 (say_line).
## 3D 는 화면 실제 해상도(× 품질 배율)로 그린다 —— 논리 크기로 그리면 휴대폰에서 흐리다.

const LEVELS := [["초반 · 1일차", 60], ["중반 · 4일차", 300], ["후반 · 6일차", 700], ["신화전", -1]]
const OPEN := 2.2
const OPEN_RT := 0.8        # 실시간 엔진 —— 엔진 0초가 화면 이 시각. 이후는 엔진 시각 그대로 (1배속 = 실제 시간)
const STEP := 0.6
const MELEE_WAIT := 6.0
const PVP_LEN := 52.0       # 대전·토너먼트 목표 길이(초, 1배속) —— 행동 간격을 벌려 맞춘다. 끝맺음까지 50~60초
const QUEST_SPEED := 1.25   # 11/3 사용자: 기본 배속 2배속 → 11/5 1.25배속 (토벌 · 대전 모두) —— 위 띠에서 바꾼다
var pace := 1.0             # 행동 간격 배율 (STEP · 턴 끝 정산에 곱한다)
var target_len := 0.0       # 0 이면 늘리지 않는다

var stage: Control          # 전장 영역
var port: SubViewport
var field: War3D
var hud: Hud
var cards_bar: AutoGrid
var log_box: RichTextLabel
var title_label: Label
var level_pick: OptionButton
var speed_btns := []

var res: Dictionary
var rng := RandomNumberGenerator.new()
var speed := 1.0
var speed_sec := {}       # 배속마다 본 실제 초 (플레이 기록 —— PlayLog)
var clock := 0.0
var running := false
var finished := false
var finish_t := -1.0

var groups := []            # 행동 묶음
var group_of := []          # 이벤트 번호 -> 그 이벤트가 속한 행동 묶음 (치명타 판정에 쓴다)
var gi := 0
var pending := []           # 상대에 닿기를 기다리는 근접 행동
var due := []               # [시각, 이벤트 번호]
var changes := []           # 이벤트별 [[유닛 번호, 병력 증감, 사기 증감], …]
var cur := []               # 유닛별 [병력, 사기] —— 지금까지 적용한 값
var idx_of := {}            # key -> 유닛 번호
var plans := {}             # key -> [[시각, 상대 key], …] —— 부대가 미리 달려갈 상대 순서
var shown := []             # 유닛별 [병력, 사기] —— 화면에 보이는 값. cur 를 향해 흘러간다
var drain := []             # 유닛별 [병력 초당 변화량, 사기 초당 변화량]
var src := []               # 유닛별 마지막 공격자 key (쓰러지는 병사를 고르는 데 쓴다)
var loss_times := []        # 유닛별 병력 손실이 예정된 행동 시각 (정렬)
var rout_wait := {}         # 유닛 번호 -> true —— 병력이 다 흘러간 뒤 무너뜨린다
var fixed_seed := -1         # 0 이상이면 같은 전투를 다시 만든다 (점검용)
var slow_t := 0.0           # 고유기 슬로모션이 남은 시간 (실시간)
const CUT_T := 1.8           # 고유기 컷인 길이 (실시간 초) —— 11/4 1.6 → 0.95, 11/6 사용자: 초상 · 글이 너무 빨리 사라진다 → 1.8 (터지는 순간은 컷인이 걷힌 뒤)
const SLOW := 0.25          # 슬로모션 배속
## 11/3 임팩트 프리즈 —— 큰 한 방이 꽂히는 순간 화면 시간을 거의 멈춘다 (판정 · 결과와 상관없는 연출 시계만).
## Engine.time_scale 을 건드리면 UI 트윈 · 소리까지 멎어 화면 시계(clock)만 늦춘다
var freeze_t := 0.0          # 남은 프리즈 (실시간 초)
var _freeze_cd := 0.0        # 너무 잦지 않게 —— 다음 프리즈까지 (실시간 초)
var _ace_cd := 0.0           # 에이스(불멸 · 신화) 기술 줌인 간격
const FREEZE_SPD := 0.04
const ULT_DELAY := 0.52     # 고유기 발동 뒤 피해가 터지기까지 (전장 시간 —— 슬로모션 중이라 실제로는 약 2.1초, 컷인 1.8초가 걷힌 뒤 맞는 순간을 보여 준다 11/6)
var dbg_nolog := false      # 점검용 —— 전투 기록을 쓰지 않는다
## 전투 중 개입 —— 탭할 때마다 (시드 + 입력 전부)로 처음부터 다시 계산하고, 입력 앞부분은 그대로 둔 채 뒤만 바꾼다
var _p := {}                # 지금 전투의 재료 (덱·진형·시드)
var inputs := []            # 플레이어 입력 [행동 번호, "A", 종류, 값]
var direct := false         # 직접 지휘 —— 고유기 버튼을 보인다. 꺼져 있어도 내 쪽은 영리한 AI 가 쓴다 (11/1 덱 감상 전투)
var _cmd_row: Control
var live_e = null           # 화면에 마지막으로 반영된 사건 —— 게이지·포인트 표시용
var live_i := 0
var _shift := 0.0           # 개입을 바로 보여 주려고 당긴 시간 합
var smooth := true          # false 면 예전처럼 이벤트 순간에 한꺼번에 깎는다 (비교용)
var ambient := {}           # key -> 다음 자유 사격·시전 시각 (궁병·지략 계열)
## 게임 모드 —— 게임 화면(GameScreen)이 덱을 주고 띄운다. 연습용 단계 고르기·새 전투는 숨긴다
signal ended(res: Dictionary, inputs: Array)
signal info_requested(cid: String)      # 11/4 사용자: 아래 장수 칸을 누르면 장수정보간략창
signal unit_requested(key: String)      # 11/6 사용자: 전투 중 꾹 누르면 '전투장수창' (재료 · 갈무리 대신 전투 능력치)
signal inputs_changed(inputs: Array)
signal quick_requested(index: int)      # 11/9 사용자: 전투 중 퀵 메시지 —— 말풍선 목록에서 고른 번호 (quick_list 의 순서)
var quick_list: Array = []              # 미리 적힌 퀵 메시지 글 (게임 화면 · 온라인이 채운다) —— 비어 있으면 말풍선 버튼이 숨는다
var _quick_btn: Button
var _quick_grid: GridContainer
var game_mode := false
var end_clock := 0.0        # 점검용 —— 전투가 끝난 전장 시각(초, 1배속 기준)
var locked := false         # 온라인 1단계 —— 서버가 준 결과를 재생만 한다 (고유기 입력 없음)
var _auto_btn: CheckButton
var _skip_btn: Button        # 결과로 건너뛰기 (⋯ 메뉴) —— 온라인 재생에서도 보인다 (11/9 사용자: 리플레이를 나갈 방법이 없었다)
var _skip_top: Button        # 위 띠의 '결과로' —— 온라인 재생(locked)에서만
var _say_btn: Button         # 위 띠의 '한마디' —— say_cb 가 있을 때(온라인)만
var say_cb := Callable()     # 한마디 시트를 여는 함수 (Online.quick_sheet) —— 게임 화면이 전투를 띄울 때 넣는다
var _say_box: VBoxContainer  # 받은 한마디 줄 (전장 왼쪽 위)
var _dev_row: Control
var _side: Control
var _side_mask: ColorRect
var _box: SubViewportContainer
var _rscale := 1.0         # 3D 해상도 / 논리 크기
var _touches := {}          # 손가락 번호 -> 위치 (두 손가락 확대·회전)
var _pinch := []            # [거리, 각도]
var dots: DotView          # 점묘 전장 (scripts/field/dot_view.gd)
var type2: Type2View       # 타입2 전장 (scripts/field/type2_view.gd)
var spot: ColorRect        # 집중 비네트
var spot_t := 0.0          # 남은 집중 시간 (실시간 초)
var spot_len := 0.0
var spot_sq: Squad = null
const SPOT_SHADER := preload("res://shaders/spotlight.gdshader")
var warn_until := -1.0     # 적 고유기가 터지는 시각 (기 모으는 중) —— 방진 버튼을 깜빡인다
var warn_key := ""
var warn_name := ""         # 경고 띠에 쓰는 적 장수 · 고유기 이름
var _press := []            # 꾹 누르기 [화면 위치, 누른 시각 ms] —— 가만히 LONG_PRESS 초 누르면 — 2D 전장은 그 메달의 전투장수창(unit_requested), 3D 는 그 부대를 따라간다
const LONG_PRESS := 0.45
# 11/4 연출 점검 —— 리듬
const MARCH_SPD := 1.0      # 맞닿기 전(다가오기만 하는 개전 구간) 배속 —— 11/4 저녁 사용자: 1배속인데 배속 돌린 듯 어색하다 → 1.0 (끔)
const LEAD_ON := 0.58       # 병력 비율이 이만큼 넘으면 '우세'
const LEAD_OFF := 0.5
var _met := false           # 양군이 한 번이라도 맞닿았다
var _duels := {}            # 일기토를 띄운 장수 짝 (11/5)
var _duel_cd := 0.0
var _lead := 0              # 1 아군 우세 · -1 적 우세 · 0 미정
var _turns_n := 0           # '전세 역전' 띄운 횟수 (한 판 둘까지)
var _kill_cd := 0.0         # 격파 카메라 당김 간격
var _tac := ""              # 내 작전 (Run.TACS 키) —— 개전 한 줄
const TAC_LINE := {"균형": "작전 『균형』 —— 상대를 보고 돌격 · 방진을 고른다",
	"맹공": "작전 『맹공』 —— 바로 돌격, 돌격 공격 +25%",
	"굳히기": "작전 『굳히기』 —— 방진으로 버티다 배수진 고유기 ×1.6"}



func _ready() -> void:
	rng.randomize()
	var bg := ColorRect.new()
	bg.color = Color("#0b0f1a")
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var col := VBoxContainer.new()
	col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	col.add_theme_constant_override("separation", 0)
	add_child(col)
	col.add_child(_build_top())

	stage = Control.new()
	stage.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stage.clip_contents = true
	stage.gui_input.connect(_flat_input)      # 11/9 2D 전장(타입2 · 점묘)은 3D 상자가 숨어 입력이 이리로 온다 —— 꾹 누르기만 본다
	col.add_child(stage)
	_box = SubViewportContainer.new()
	_box.stretch = false
	_box.mouse_filter = Control.MOUSE_FILTER_STOP
	_box.gui_input.connect(_stage_input)
	apply_style()
	stage.add_child(_box)
	port = SubViewport.new()
	port.own_world_3d = true
	port.msaa_3d = Viewport.MSAA_4X
	port.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA
	port.positional_shadow_atlas_size = 4096
	_box.add_child(port)
	field = War3D.new()
	port.add_child(field)
	# 점묘 전장 (Settings.dots) —— 3D 위에 덮는다. 켜면 3D 는 그리지 않고 계산만 한다
	dots = DotView.new()
	dots.view = self
	dots.field = field
	dots.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	stage.add_child(dots)
	# 타입2 전장 (Settings.type2, 11/3) —— 삼국지11 식. 점묘와 같은 자리에 들어간다
	type2 = Type2View.new()
	type2.view = self
	type2.field = field
	type2.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	stage.add_child(type2)
	# 가장자리를 살짝 어둡게 —— 눈이 가운데 싸움으로 간다
	var vg := GradientTexture2D.new()
	vg.width = 128
	vg.height = 128
	vg.fill = GradientTexture2D.FILL_RADIAL
	vg.fill_from = Vector2(0.5, 0.5)
	vg.fill_to = Vector2(1.08, 0.5)
	var vgr := Gradient.new()
	vgr.offsets = PackedFloat32Array([0.0, 0.62, 1.0])
	vgr.colors = PackedColorArray([Color(0, 0, 0, 0), Color(0, 0, 0, 0.05), Color(0.02, 0.02, 0.05, 0.5)])
	vg.gradient = vgr
	var vig := TextureRect.new()
	vig.texture = vg
	vig.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	vig.stretch_mode = TextureRect.STRETCH_SCALE
	vig.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vig.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	stage.add_child(vig)
	# 11/3 사용자: 에이스 · 신화 기술의 집중 비네트 —— 시전 부대 둘레만 밝고 나머지 전장은 어둡게 (셰이더 한 장, 평소엔 숨김)
	spot = ColorRect.new()
	spot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	spot.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var sm := ShaderMaterial.new()
	sm.shader = SPOT_SHADER
	spot.material = sm
	spot.visible = false
	stage.add_child(spot)
	hud = Hud.new()
	hud.view = self
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	stage.add_child(hud)
	field.ult_flash.connect(hud.flash)
	stage.resized.connect(fit_port)
	# 11/9 사용자: 전투를 보는 중에도 다른 사람의 한마디가 보여야 한다 —— 전장 왼쪽 위에 작은 줄, 4초 뒤 사라진다
	_say_box = UI.vbox(4)
	_say_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_say_box.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_say_box.offset_left = 10
	_say_box.offset_top = 48      # 위 띠 바로 아래의 병력 막대 · 알림(announce) 아래
	_say_box.offset_right = 290
	stage.add_child(_say_box)

	# 아래 독 —— 아군 장수 카드 격자 (금빛이면 눌러 고유기). 11/9 사용자: 군령은 없어진 기능 —— 점수 · 버튼 줄을 뺐다 (_cmd_row 는 빈 줄로 남긴다)
	var dock := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("#0f1424")
	sb.border_color = DB.PAL.ink3
	sb.border_width_top = 1
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	dock.add_theme_stylebox_override("panel", sb)
	col.add_child(dock)
	var dv := VBoxContainer.new()
	dv.add_theme_constant_override("separation", 8)
	dock.add_child(dv)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	dv.add_child(row)
	_cmd_row = row
	row.visible = false
	cards_bar = UI.grid(64, 5)
	cards_bar.max_cols = 5
	cards_bar.center_last = true      # 11/7 9장이면 5 + 4 —— 둘째 줄이 왼쪽으로 쏠리지 않게
	dv.add_child(cards_bar)

	_build_side()


## 위 띠 —— 전투 이름 · 배속 · ⋯ 메뉴
func _build_top() -> Control:
	var bar := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("#0f1424")
	sb.border_color = DB.PAL.ink3
	sb.border_width_bottom = 1
	sb.content_margin_left = 12
	sb.content_margin_right = 4
	sb.content_margin_top = 4
	sb.content_margin_bottom = 4
	bar.add_theme_stylebox_override("panel", sb)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 4)
	bar.add_child(h)
	title_label = Label.new()
	title_label.add_theme_font_override("font", DB.title_font(16))      # 11/10 작은 글자는 굵은 고딕
	title_label.add_theme_font_size_override("font_size", 16)
	title_label.text = "전장"
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title_label.clip_text = true
	title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title_label.size_flags_vertical = Control.SIZE_FILL
	h.add_child(title_label)
	var seg := PanelContainer.new()
	seg.add_theme_stylebox_override("panel", UI.flat(DB.PAL.ink2, Color(0, 0, 0, 0), 0, UI.R, 3))      # 11/9 규칙: 테두리 없는 먹색 면, 고른 배속만 금 얇은 선
	var sp := HBoxContainer.new()
	sp.add_theme_constant_override("separation", 2)
	seg.add_child(sp)
	for s in [0.0, 1.0, 1.25, 2.0]:      # 11/5 사용자: 1 · 1.25 · 2배속 (4배속 뺌)
		sp.add_child(_speed_btn(s, 38, 14))
	h.add_child(seg)
	# 11/9 사용자: 온라인 —— 한마디(미리 적힌 글) · 결과로 건너뛰기 (리플레이를 나갈 방법). 둘 다 온라인에서만 보인다
	_say_btn = _bar_btn("한마디", func():
		UI.buzz()
		if say_cb.is_valid():
			say_cb.call()
		elif not quick_list.is_empty():
			set_side_visible(true))
	_say_btn.visible = false
	h.add_child(_say_btn)
	_skip_top = _bar_btn("결과로 ▶", func():
		UI.buzz()
		skip())
	_skip_top.visible = false
	h.add_child(_skip_top)
	var mb := Button.new()
	mb.text = "⋯"
	mb.custom_minimum_size = Vector2(44, 40)
	mb.add_theme_font_size_override("font_size", 22)
	mb.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	mb.pressed.connect(toggle_menu)
	h.add_child(mb)
	return bar


## 위 띠의 작은 글 버튼 —— 테두리 없는 먹색 면 (11/9 규칙)
func _bar_btn(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 38)
	b.add_theme_font_size_override("font_size", 13)
	b.add_theme_stylebox_override("normal", UI.flat(DB.PAL.ink3, Color(0, 0, 0, 0), 0, UI.R, 8))
	b.add_theme_stylebox_override("hover", UI.flat(DB.PAL.ink4, Color(0, 0, 0, 0), 0, UI.R, 8))
	b.add_theme_stylebox_override("pressed", UI.flat(DB.PAL.ink4, DB.PAL.gold, 1, UI.R, 8))
	b.pressed.connect(cb)
	return b


## 배속 버튼 하나 —— 위 띠와 ⋯ 메뉴가 같은 목록(speed_btns)을 써서 어느 쪽을 눌러도 함께 바뀐다. 고른 것만 금 얇은 선
func _speed_btn(s: float, h: int, fs: int) -> Button:
	var b := Button.new()
	b.text = "❚❚" if s == 0.0 else ("%s×" % str(s) if s != floorf(s) else "%d×" % s)
	b.toggle_mode = true
	b.button_pressed = s == QUEST_SPEED
	b.custom_minimum_size = Vector2(38, h)
	b.add_theme_font_size_override("font_size", fs)
	b.add_theme_stylebox_override("normal", UI.flat(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, UI.R, 4))
	b.add_theme_stylebox_override("hover", UI.flat(DB.PAL.ink3, Color(0, 0, 0, 0), 0, UI.R, 4))
	b.add_theme_stylebox_override("pressed", UI.flat(DB.PAL.ink3, DB.PAL.gold, 1, UI.R, 4))
	b.add_theme_stylebox_override("hover_pressed", UI.flat(DB.PAL.ink4, DB.PAL.gold, 1, UI.R, 4))
	b.add_theme_color_override("font_color", DB.PAL.bamboo)
	b.add_theme_color_override("font_pressed_color", DB.PAL.paper)
	b.add_theme_color_override("font_hover_pressed_color", DB.PAL.paper)
	b.pressed.connect(func():
		UI.buzz()
		_set_speed(s))
	speed_btns.append([b, s])
	return b


## 받은 퀵 메시지 —— 전장 위쪽에 "누구: 글" 한 줄이 3초 떠 있다 흐려진다 (11/9 사용자). say_line 은 같은 것의 옛 이름
func say_line(who: String, text: String) -> void:
	show_quick(who, text)


func show_quick(who: String, text: String) -> void:
	if _say_box == null:
		return
	var pc := PanelContainer.new()
	pc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pc.add_theme_stylebox_override("panel", UI.flat(Color(DB.PAL.ink, 0.82), Color(0, 0, 0, 0), 0, UI.R, 6))
	pc.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	var r := UI.rich("[color=#D9A64B][b]%s[/b][/color]  %s" % [who, text], 13)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.autowrap_mode = TextServer.AUTOWRAP_OFF
	pc.add_child(r)
	_say_box.add_child(pc)
	while _say_box.get_child_count() > 4:
		_say_box.get_child(0).free()
	var tw := pc.create_tween()
	tw.tween_interval(3.0)
	tw.tween_property(pc, "modulate:a", 0.0, 0.5)
	tw.tween_callback(pc.queue_free)


## ⋯ 메뉴 —— 오른쪽에서 열린다. 진행(배속 · 결과로 건너뛰기) · 전투 기록. 점검 화면(main.gd)에서만 단계 고르기 · 새 전투 줄 (game_mode 가 아닐 때)
## 11/9 사용자: 전투 기록실 정리 —— 묶음마다 머리말 + 구분선(hairline), 글자 크기 13 으로 통일, 상자는 테두리 없는 먹색 면
func _build_side() -> void:
	_side_mask = ColorRect.new()
	_side_mask.color = Color(0, 0, 0, 0.45)
	_side_mask.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_side_mask.visible = false
	_side_mask.gui_input.connect(func(e):
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			set_side_visible(false))
	TouchScroll.block(_side_mask)
	add_child(_side_mask)
	var panel := PanelContainer.new()
	var psb := UI.flat(DB.PAL.ink2, Color(0, 0, 0, 0), 0, 0, 14)      # 테두리 · 둥근 모서리 없이 (11/9 규칙)
	panel.add_theme_stylebox_override("panel", psb)
	panel.anchor_left = 1
	panel.anchor_right = 1
	panel.anchor_top = 0
	panel.anchor_bottom = 1
	panel.visible = false
	add_child(panel)
	_side = panel
	_fit_side()
	resized.connect(_fit_side)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	panel.add_child(v)
	var top := HBoxContainer.new()
	var tl := UI.lbl("전투 메뉴", 18, DB.PAL.paper, true)
	tl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	top.add_child(tl)
	var x := UI.btn("✕", func(): set_side_visible(false), "ghost", 44)
	x.custom_minimum_size = Vector2(44, 44)
	x.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	top.add_child(x)
	v.add_child(top)
	v.add_child(UI.hair())

	# 점검 화면(전투 실험실)에서만 —— 단계 고르기 · 새 전투. 게임에서는 play · play_res 가 숨긴다
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	level_pick = OptionButton.new()
	for l in LEVELS:
		level_pick.add_item(l[0])
	level_pick.selected = 2
	level_pick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	level_pick.custom_minimum_size = Vector2(0, 44)
	row.add_child(level_pick)
	var nb := UI.btn("새 전투", func():
		set_side_visible(false)
		new_battle(), "", 44)
	row.add_child(nb)
	v.add_child(row)
	_dev_row = row

	# 진행 —— 배속(위 띠와 함께 바뀐다) · 결과로 건너뛰기
	v.add_child(UI.eyebrow("진행"))
	var spd := HBoxContainer.new()
	spd.add_theme_constant_override("separation", 4)
	for sv in [0.0, 1.0, 1.25, 2.0]:
		var sb2 := _speed_btn(sv, 42, 14)
		sb2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		spd.add_child(sb2)
	v.add_child(spd)
	var auto_btn := CheckButton.new()
	auto_btn.text = "직접 지휘 (고유기 버튼)"
	auto_btn.button_pressed = direct
	auto_btn.custom_minimum_size = Vector2(0, 44)
	auto_btn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	auto_btn.toggled.connect(set_direct)
	_auto_btn = auto_btn
	auto_btn.visible = false      # 11/4 사용자: 직접 지휘 개념은 없앤다
	v.add_child(auto_btn)
	_skip_btn = UI.btn("결과로 건너뛰기", func():
		set_side_visible(false)
		skip(), "ghost", 44)
	v.add_child(_skip_btn)
	var hint := UI.lbl("두 손가락 확대·회전 · 한 손가락 이동 · 장수 칸을 꾹 누르면 전투 능력치", 11, DB.PAL.bamboo_dim)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(hint)
	v.add_child(UI.hair())

	# 말풍선 —— 퀵 메시지 (quick_list 가 있을 때만). 누르면 2열 목록이 펴지고, 고르면 quick_requested 가 나간다
	_quick_btn = UI.btn("말풍선", func():
		_quick_grid.visible = not _quick_grid.visible, "ghost", 44)
	v.add_child(_quick_btn)
	_quick_grid = GridContainer.new()
	_quick_grid.columns = 2
	_quick_grid.add_theme_constant_override("h_separation", 4)
	_quick_grid.add_theme_constant_override("v_separation", 4)
	_quick_grid.visible = false
	v.add_child(_quick_grid)
	v.add_child(UI.hair())

	# 전투 기록 —— 먹색 면 상자 안에서 스크롤, 글자 13
	v.add_child(UI.eyebrow("전투 기록"))
	var lp := PanelContainer.new()
	lp.add_theme_stylebox_override("panel", UI.flat(DB.PAL.ink, Color(0, 0, 0, 0), 0, UI.R, 8))
	lp.size_flags_vertical = Control.SIZE_EXPAND_FILL
	log_box = RichTextLabel.new()
	log_box.bbcode_enabled = true
	log_box.scroll_following = true
	log_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	log_box.add_theme_font_size_override("normal_font_size", 13)
	log_box.add_theme_font_size_override("bold_font_size", 13)
	log_box.add_theme_constant_override("line_separation", 3)
	TouchScroll.add(log_box)
	lp.add_child(log_box)
	v.add_child(lp)


## 퀵 메시지 버튼 · 목록을 quick_list 에 맞춘다 (전투를 띄울 때마다)
func _refresh_quick() -> void:
	if quick_list.is_empty() and "--gquick" in OS.get_cmdline_user_args():      # 점검용 —— 퀵 메시지 목록 모양 보기
		quick_list = ["잘 싸웠다", "한 판 더", "좋은 수다", "방심했다", "대단하군", "다음엔 이긴다"]
	var has := not quick_list.is_empty()
	_quick_btn.visible = has
	_quick_grid.visible = false
	for c in _quick_grid.get_children():
		c.queue_free()
	for i in quick_list.size():
		var b := UI.btn(str(quick_list[i]), func():
			set_side_visible(false)
			quick_requested.emit(i), "ghost", 40)
		b.add_theme_font_size_override("font_size", 13)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_quick_grid.add_child(b)
	_say_btn.visible = say_cb.is_valid() or has


func _fit_side() -> void:
	if _side == null:
		return
	var w := minf(340.0, size.x * 0.86)
	_side.offset_left = -w
	_side.offset_right = 0


func toggle_menu() -> void:
	set_side_visible(not _side.visible)


## 3D 해상도 맞추기 —— 화면 실제 픽셀(× 품질 배율)로 그리고 논리 크기로 줄여 보인다
func fit_port() -> void:
	if stage == null or stage.size.x < 2 or stage.size.y < 2:
		return
	var win := get_tree().root.get_final_transform().get_scale().x
	var q: float = Settings.RES_SCALE[clampi(Settings.quality, 0, 2)]
	_rscale = clampf(win * q, 0.75, 3.0)
	var px := Vector2i(int(stage.size.x * _rscale), int(stage.size.y * _rscale))
	port.size = px
	_box.size = Vector2(px)
	_box.scale = Vector2.ONE / _rscale
	field.screen_scale = _rscale
	field.set_portrait(stage.size.x < stage.size.y)


func _set_speed(s: float) -> void:
	speed = s
	for p in speed_btns:
		p[0].button_pressed = p[1] == s


func _unhandled_input(e: InputEvent) -> void:
	if is_visible_in_tree() and e is InputEventKey and e.pressed and e.keycode == KEY_SPACE:
		_set_speed(QUEST_SPEED if speed == 0.0 else 0.0)


# ───────── 카메라 ─────────

func fit_camera() -> void:
	field.reset_camera()


func focus(sq: Squad) -> void:
	field.focus(sq)


func _stage_input(e: InputEvent) -> void:
	# 두 손가락: 벌리면 확대, 돌리면 회전. 그동안 한 손가락 끌기(이동)는 막는다
	if e is InputEventScreenTouch:
		if e.pressed:
			_touches[e.index] = e.position
			if e.double_tap:
				field.auto_camera()
				hud.announce("자동 카메라", DB.PAL.bamboo)
		else:
			_touches.erase(e.index)
		if _touches.size() >= 2:
			_press = []
		_pinch = []
		return
	if e is InputEventScreenDrag:
		_touches[e.index] = e.position
		if _touches.size() >= 2:
			var ps: Array = _touches.values()
			var d: Vector2 = ps[1] - ps[0]
			var now := [d.length(), d.angle()]
			if not _pinch.is_empty() and now[0] > 1.0:
				field.pinch(_pinch[0] / now[0], wrapf(now[1] - _pinch[1], -PI, PI))
			_pinch = now
		return
	# 두 번 누르기 —— 자동 카메라로 돌아간다
	if e is InputEventMouseButton and e.pressed and e.double_click and e.button_index == MOUSE_BUTTON_LEFT:
		field.auto_camera()
		hud.announce("자동 카메라", DB.PAL.bamboo)
		return
	_track_press(e)
	if e is InputEventMagnifyGesture:
		field.pinch(1.0 / e.factor, 0.0)
		return
	if e is InputEventMouseMotion and _touches.size() >= 2:
		return
	field.camera_input(e)


## 꾹 누르기 기록 —— 왼쪽 버튼(손가락)을 누른 자리 · 시각. 14px 넘게 움직이면 취소
func _track_press(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
		_press = [e.position, Time.get_ticks_msec()] if e.pressed and _touches.size() < 2 else []
	elif e is InputEventMouseMotion and not _press.is_empty() and e.position.distance_to(_press[0]) > 14:
		_press = []


## 2D 전장(field.flat)에서 오는 입력 —— 카메라는 없고(자동 맞춤) 꾹 누르기로 메달의 전투장수창만 연다 (11/9 사용자)
func _flat_input(e: InputEvent) -> void:
	if field != null and field.flat != null:
		_track_press(e)


# ───────── 전투 준비 ─────────

func new_battle() -> void:
	if fixed_seed >= 0:
		rng.seed = fixed_seed
	var lv: int = level_pick.selected
	var pv: int = LEVELS[lv][1]
	var styles := ["물리", "지략", "균형"]
	var a: Dictionary
	var b: Dictionary
	if pv < 0:
		var myth: Array = _shuffled(DB.by_tier(8))
		var imm: Array = _shuffled(DB.by_tier(7))
		a = {"cards": myth.slice(0, 5) + imm.slice(0, 4), "form": ["eorin", "hagik", "bongsi", "anwol"][rng.randi() % 4]}
		b = DB.gen_board(1200, styles[rng.randi() % 3], rng)
	else:
		a = DB.gen_board(pv, styles[rng.randi() % 3], rng)
		b = DB.gen_board(pv * rng.randf_range(0.85, 1.1), styles[rng.randi() % 3], rng)
	var foe: Array = DB.D.BOTNAME[rng.randi() % DB.D.BOTNAME.size()]
	var quest: String = DB.D.QUESTS[clampi(lv * 2, 0, 6)][rng.randi() % 3]
	var title := "대전 · %s" % foe[0] if rng.randf() < 0.5 else "토벌 · %s" % quest
	_p = {"a": DB.auto_place(a.cards, a.form), "fa": a.form, "b": DB.auto_place(b.cards, b.form), "fb": b.form,
		"seed": fixed_seed if fixed_seed >= 0 else rng.randi() % 1000000, "title": title, "foe": foe[0],
		"policy": {"A": "smart", "B": "smart"}}
	inputs = []
	res = _simulate()
	_begin()


## 전투장수창용 —— 같은 재료로 엔진을 '준비'만 시켜(유닛 · 단체 특기 · 전투 시작 효과) 시작 능력치를 잰다. 재생에는 손대지 않는다.
## {atk: [기본, 실제], def, spd, line, side, item} · 재료가 없으면(온라인 재생) 빈 사전
func start_stats(key: String) -> Dictionary:
	if _p.is_empty() or not _p.has("a"):
		return {}
	Battle.tr_mul = {"A": float(_p.get("tra", 1.0)), "B": float(_p.get("trb", 1.0))}
	Battle.side_trait = {"A": {}, "B": _p.get("tb", {})}      # 11/8 토벌 우두머리 성질
	var tm := Battle.turn_mul
	var bt: Battle = RtBattle.make(_p.seed)
	bt._setup(_p.a, _p.fa, _p.get("ma", 100), _p.get("ea"), _p.b, _p.fb, _p.get("mb", 100), _p.get("eb"),
		_p.title, _p.foe, [], _p.policy)
	Battle.tr_mul = {"A": 1.0, "B": 1.0}
	Battle.side_trait = {"A": {}, "B": {}}
	Battle.turn_mul = tm      # 준비가 정적 턴 배율을 다시 정한다 —— 같은 값이지만 되돌려 둔다
	var out := {}
	for u in bt.units:
		if u.key == key:
			var cut: Dictionary = u.cut.duplicate()
			var full := {}
			for st in ["atk", "def", "spd"]:
				full[st] = bt.eff(u, st)
			u.cut = {}      # 깎임(위축 · 파갑 …)을 빼고 한 번 더 —— 늘어난 몫과 깎인 몫을 따로 보여 준다
			for st in ["atk", "def", "spd"]:
				out[st] = [float(u.c[st]), full[st], bt.eff(u, st)]      # [기본, 실제, 깎임 전]
			u.cut = cut
			out["line"] = u.line
			out["side"] = u.side
			out["item"] = u.item
			out["tr"] = u.max
			break
	return out


func _simulate() -> Dictionary:
	Battle.tr_mul = {"A": float(_p.get("tra", 1.0)), "B": float(_p.get("trb", 1.0))}
	Battle.side_trait = {"A": {}, "B": _p.get("tb", {})}      # 11/8 토벌 우두머리 성질 (직접 지휘 다시 계산도 같은 값 —— Run.simulate 와 같다)
	var r: Dictionary = RtBattle.make(_p.seed).run(_p.a, _p.fa, _p.get("ma", 100), _p.get("ea"), _p.b, _p.fb, _p.get("mb", 100), _p.get("eb"),
		_p.title, _p.foe, inputs.duplicate(true), _p.policy)
	Battle.tr_mul = {"A": 1.0, "B": 1.0}
	Battle.side_trait = {"A": {}, "B": {}}
	return r


## 게임에서 부른다 —— bt 는 Run.battle (a·b 진영 {cards, form, morale, equip}, seed, title, foe, inputs)
func play(bt: Dictionary, direct_ := false) -> void:
	end_clock = 0.0
	speed_sec = {}
	game_mode = true
	locked = false
	_skip_btn.visible = true
	_skip_top.visible = false
	_refresh_quick()
	_auto_btn.disabled = false
	_auto_btn.text = "직접 지휘 (고유기 버튼)"
	_auto_btn.set_pressed_no_signal(direct_)
	_dev_row.visible = false
	set_direct(direct_)
	_p = {"a": bt.a.cards, "fa": bt.a.form, "ma": bt.a.morale, "ea": bt.a.equip,
		"b": bt.b.cards, "fb": bt.b.form, "mb": bt.b.morale, "eb": bt.b.equip,
		"seed": bt.seed, "title": bt.title, "foe": bt.foe,
		"policy": Run.policy_for(bt), "tra": float(bt.a.get("tr_mul", 1.0)), "trb": float(bt.b.get("tr_mul", 1.0)), "tb": bt.b.get("trait", {})}
	inputs = bt.get("inputs", []).duplicate(true)
	res = _simulate()
	_pace_for(str(bt.get("kind", "")))
	_tac = str(bt.a.get("tac", ""))
	_begin()
	_set_speed(QUEST_SPEED)


## 온라인 —— 서버가 계산한 결과(사람끼리 대전이면 내 쪽이 A 가 되게 뒤집은 것)를 그대로 재생한다.
## 11/9 사용자: 재생 중 전투장수창의 버프 수치가 비어 있었다(_p 가 빈 사전) —— 서버가 결과에 실은 재료(res.bp: 양쪽 편성 · 장비 · 진형 · 사기 · 병력 배율 · 작전)로
## _p 를 혼자 할 때(play)와 같은 꼴로 채운다. start_stats 가 그것으로 같은 엔진을 '준비'만 시켜 같은 수치를 낸다. 재생 자체는 서버 결과 그대로
## params(선택) —— 서버가 전투마다 실은 재료. 평평한 꼴 {a, fa, ma, ea, b, fb, mb, eb, seed, title, foe, policy, tra, trb, tb}(play 가 _p 에 넣는 것과 같다)
## 이거나 res.bp 같은 {a:{cards,form,morale,equip}, b:{…}, seed, pol} 꼴 둘 다 받는다. 없으면 res.bp, 그것도 없으면 빈 재료(전투장수창 버프 수치만 빈다)
func play_res(r: Dictionary, kind := "", params := {}) -> void:
	end_clock = 0.0
	speed_sec = {}
	game_mode = true
	locked = true
	_skip_btn.visible = true       # 11/9 사용자: 리플레이를 나갈 방법 —— 결과로 건너뛰면 본 것으로 친다
	_skip_top.visible = true
	_refresh_quick()
	_dev_row.visible = false
	_auto_btn.disabled = true
	_auto_btn.text = "온라인 1단계 — 양쪽 모두 자동 전투"
	set_direct(false)
	_p = {}
	var bp = params if not params.is_empty() else r.get("bp")
	if bp is Dictionary and bp.get("a") is Array and bp.has("fa") and bp.has("seed"):
		_p = bp.duplicate()
		_p.title = str(_p.get("title", r.get("title", "")))
		_p.foe = str(_p.get("foe", r.get("foe", "")))
		_p.policy = _p.get("policy", {"A": "smart", "B": "smart"})
	elif bp is Dictionary and bp.has("a") and bp.has("b"):
		var pa: Dictionary = bp.a
		var pb: Dictionary = bp.b
		_p = {"a": pa.get("cards", []), "fa": str(pa.get("form", "eorin")), "ma": float(pa.get("morale", 100)), "ea": pa.get("equip"),
			"b": pb.get("cards", []), "fb": str(pb.get("form", "eorin")), "mb": float(pb.get("morale", 100)), "eb": pb.get("equip"),
			"seed": int(bp.get("seed", 0)), "title": str(r.get("title", "")), "foe": str(r.get("foe", "")),
			"policy": bp.get("pol", {"A": "smart", "B": "smart"}), "tra": float(pa.get("tr_mul", 1.0)), "trb": float(pb.get("tr_mul", 1.0)), "tb": pb.get("trait", {})}
	inputs = []
	res = r
	_pace_for(kind)
	_tac = ""
	_begin()
	_set_speed(QUEST_SPEED)


## 모든 전투를 1배속 기준 50~60초에 맞춘다 (토벌은 2배속으로 보니 25~30초)
func _pace_for(_kind: String) -> void:
	target_len = PVP_LEN


## 전장 화풍 —— 수묵(삼국지11 시안)이면 3D 화면 위에 먹선 · 종이 후처리를 입힌다 (Settings.sumuk)
func apply_style() -> void:
	if dots:
		var t2: bool = Settings.type2 and type2 != null
		var flat_on: bool = Settings.dots or t2
		if field._gpu and flat_on and not t2:
			flat_on = false           # GPU 병사로 시작한 전투는 병사 위치를 CPU 가 모른다 —— 점묘는 다음 전투부터 (11/4 점검). 타입2 는 GPU 병사를 직접 그린다 (11/6)
		dots.visible = flat_on and not t2
		if type2:
			type2.visible = t2
		field.flat = (type2 if t2 else dots) if flat_on else null
		port.render_target_update_mode = SubViewport.UPDATE_DISABLED if flat_on else SubViewport.UPDATE_ALWAYS
		_box.visible = not flat_on
	if Settings.sumuk and not Settings.type2:
		var m := ShaderMaterial.new()
		m.shader = load("res://shaders/sumuk.gdshader")
		_box.material = m
	else:
		_box.material = null


## 실시간 엔진의 결과인가 (위치 기록 track 이 있다)
func _rt() -> bool:
	return res.get("rt", false)


func set_side_visible(on: bool) -> void:
	_side.visible = on
	_side_mask.visible = on


## 입력 반영 —— 처음부터 다시 계산하고 뒷부분 시간표만 갈아 끼운다. 입력이 실제로 먹혔는지 돌려준다
func _resim() -> bool:
	var before: int = res.applied.size()
	res = _simulate()
	_build_timeline(true)
	if gi < groups.size() and groups[gi].t > clock and not _rt():
		var d: float = groups[gi].t - clock
		_shift += d
		for j in range(gi, groups.size()):
			groups[j].t -= d
	return res.applied.size() > before


## 입력을 걸 행동 번호 —— 바로 앞 사건이 그 번호의 입력 판정 뒤에 나왔다면 다음 번호로
func _input_an() -> int:
	var i := _next_idx()
	var prev: Dictionary = res.ev[maxi(0, i - 1)]
	return prev.an + 1 if prev.get("bd", false) else res.ev[i].an


func _next_idx() -> int:
	return groups[gi].ev[0] if gi < groups.size() else -1


## 다음 행동 직전의 엔진 상태 (입력이 걸리는 시점)
func _engine_state():
	var i := _next_idx()
	if i < 0 or not running or finished:
		return null
	return res.ev[maxi(0, i - 1)]


func unit_live(key: String) -> Array:
	if live_e == null or not idx_of.has(key):
		return [0, 0]
	var s: Array = live_e.s[idx_of[key]]
	return [s[4], s[5]]


func ult_ready(key: String) -> bool:
	var e = _engine_state()
	if e == null or not idx_of.has(key):
		return false
	var s: Array = e.s[idx_of[key]]
	return s[2] == 1 and s[4] >= 100 and s[5] > 0 and not s[3].has("seal")


func cmd_points() -> float:
	var e = _engine_state()
	return e.pts[0] if e != null else 0.0


func request_ult(key: String) -> void:
	if locked:
		hud.float_text(key, "온라인 대전은 자동 전투", Color("#9aa3b8"), 12)
		return
	if not ult_ready(key):
		hud.float_text(key, "아직 준비 중", Color("#9aa3b8"), 12)
		return
	inputs.append([_input_an(), "A", "ult", key])
	if not _resim():
		inputs.pop_back()
		hud.float_text(key, "잠시 뒤에 —— 앞 고유기 직후", Color("#9aa3b8"), 12)
	else:
		inputs_changed.emit(inputs)


func request_cmd(name_: String) -> void:
	if locked:
		return
	if cmd_points() < Battle.CMD_COST:
		return
	inputs.append([_input_an(), "A", "cmd", name_])
	if not _resim():
		inputs.pop_back()
	else:
		inputs_changed.emit(inputs)


## 직접 지휘 켜기 · 끄기 —— 버튼만 보이고 숨긴다. 내 쪽 AI(영리)는 그대로 돌고, 누르면 그보다 먼저 쓴다
func set_direct(on: bool) -> void:
	direct = false and on and not locked      # 11/4 직접 지휘 없음 (점검 화면 main.gd 만 battle.direct 를 직접 켠다)
	if _cmd_row:
		_cmd_row.visible = direct


## 전투 난수로 섞는다 —— 같은 시드면 같은 신화전이 나오도록 (Array.shuffle 은 전역 난수를 쓴다)
func _shuffled(a: Array) -> Array:
	var out := a.duplicate()
	for i in range(out.size() - 1, 0, -1):
		var j := rng.randi() % (i + 1)
		var t = out[i]
		out[i] = out[j]
		out[j] = t
	return out


func _begin() -> void:
	set_side_visible(false)
	fit_port()
	field.setup(res)
	fit_camera()
	apply_style()
	if Settings.type2 and type2:
		type2.setup()
	elif Settings.dots:
		dots.setup()
	hud.reset()
	# 11/6 컷인 초상을 처음 그릴 때 큰 그림을 불러오느라 프레임이 튀었다 —— 고유기가 있는 장수 그림을 미리 읽어 둔다
	hud.prewarm.clear()
	hud.prewarm_txt.clear()
	for q in field.order:
		if DB.C.has(q.cid) and (q.tier >= 6 or DB.is_kiin(q.cid)):
			for tx in [DB.portrait(q.cid), DB.face_tex(q.cid), DB.myth_art(q.cid)]:
				if tx != null:
					hud.prewarm.append(tx)      # 첫 그리기 때 안 보이게 한 번 찍어 그래픽카드에 미리 올린다 (컷인 첫 프레임 10ms)
			var ud = DB.ult_of(q.cid)
			if ud != null:      # 컷인 큰 글씨도 —— 처음 쓰는 크기 · 글자는 그 자리에서 글리프를 만든다
				hud.prewarm_txt.append(["『%s』" % ud.name, "“%s”" % str(ud.get("shout", "")), _ult_short(ud, q.tier) if ud.has("eff") else "", str(q.row.name)])
	log_box.clear()
	title_label.text = res.title
	for c in cards_bar.get_children():
		c.queue_free()
	var mine: Array = field.order.filter(func(s): return s.camp == "A")
	mine.sort_custom(func(x, y): return x.row.slot < y.row.slot)
	for sq in mine:
		var mc := MiniCard.new()
		mc.sq = sq
		mc.view = self
		cards_bar.add_child(mc)
	_shift = 0.0
	warn_until = -1.0
	_met = false
	_lead = 0
	_turns_n = 0
	_kill_cd = 0.0
	live_e = res.ev[0]
	live_i = 0
	_build_timeline()
	clock = 0.0
	gi = 0
	pending.clear()
	due.clear()
	finished = false
	finish_t = -1.0
	running = true
	Sfx.music("battle")
	Sfx.play("drums")      # 11/4 사용자: 함성(shout)은 비명처럼 들려 전투에서 뺀다
	# 지형 (실시간 엔진) —— 이번 판에 무엇이 깔렸고 무슨 효과인지 한 줄로
	var tz: Array = res.get("terrain", [])
	var tline := ""
	if not tz.is_empty():
		var parts := []
		if tz.any(func(z): return z.k == "river"): parts.append("강(이동 느림 · 받는 피해 +)")
		if tz.any(func(z): return z.k == "forest"): parts.append("숲(화살 막음 · 화공 번짐)")
		if tz.any(func(z): return z.k == "hill"): parts.append("언덕(사거리 · 내려치기 +)")
		tline = "지형 —— " + " · ".join(parts)
	# 11/4 연출 점검: 내가 고른 작전이 전투에서 어떻게 작용하는지 보이지 않았다 —— 개전에 한 줄, 지형은 2초 뒤
	# 11/5 사용자: 작전 · 군령 표시를 뺀다 (개전 작전 한 줄 삭제)
	if tline != "":
		hud.announce(tline, Color("#c9d6a3"))
	# 명세 4단계: 전투 시작에 내 덱의 핵심(위세 · 기인)을 한 줄로 —— 데일리 진행에서 "내 덱 설계가 통했는지" 확인하는 출발점
	var core := []
	for sq: Squad in field.order:
		if sq.camp != "A" or not DB.C.has(sq.cid):
			continue
		if DB.AURA.has(sq.cid):
			core.append("%s『%s』" % ["기인 " if DB.is_kiin(sq.cid) else "", DB.AURA[sq.cid].n])
	if not core.is_empty():
		var line := "내 덱 —— " + " · ".join(core.slice(0, 4))
		get_tree().create_timer(1.3).timeout.connect(func():
			if running and not finished:
				hud.announce(line, DB.PAL.gold))
	# 11/9 패업 —— 개전에 발동 · 불발을 가운데 띠 한 줄로 (엔진 기록 res.paeup: 진영 · 이름 · 발동 · 조건 장수 수)
	var pl := []
	for pp in res.get("paeup", []):
		pl.append("%s 패업『%s』 %s (%d/%d)" % ["아군" if str(pp.camp).begins_with("A") else "적", pp.n, "발동" if pp.on else "불발", int(pp.have), int(pp.need)])
	if not pl.is_empty():
		var pline := " · ".join(pl)
		var pon: bool = res.paeup.any(func(pp): return pp.on)
		get_tree().create_timer(2.6).timeout.connect(func():
			if running and not finished:
				hud.announce(pline, Color("#ff9ab4") if pon else DB.PAL.bamboo))
	log_box.append_text("[color=#8D7B5C]아군 %s · 적 %s[/color]\n" % [_form_txt(res.aForm, res.aSyn), _form_txt(res.bForm, res.bSyn)])


func _form_txt(form: String, syn: Dictionary) -> String:
	var parts := []
	for x in syn.list:
		parts.append("%s%d" % [x.fac, x.n])
	for x in syn.tagList:
		parts.append("%s%d" % [x.tag, x.n])
	return DB.FORM[form].n + (" (" + " ".join(parts) + ")" if not parts.is_empty() else "")


## 엔진 이벤트 → 행동 묶음 + 시작 시각 + 이벤트별 병력·사기 증감
func _build_timeline(rebuild := false) -> void:
	var ev: Array = res.ev
	idx_of.clear()
	for i in res.roster.size():
		idx_of[res.roster[i].key] = i
	var base: Array = ev[0].s
	if not rebuild:
		cur = []
		for u in base:
			cur.append([float(u[0]), float(u[1])])
	changes = []
	var prev := base
	for e in ev:
		var ch := []
		for u in e.s.size():
			var dt: float = e.s[u][0] - prev[u][0]
			var dm: float = e.s[u][1] - prev[u][1]
			if dt != 0 or dm != 0:
				ch.append([u, dt, dm])
		changes.append(ch)
		prev = e.s

	groups = []
	group_of = []
	var g = null
	for i in ev.size():
		var e: Dictionary = ev[i]
		if g == null or g.ai != e.ai:
			g = {"ai": e.ai, "ph": e.ph, "who": e.who, "ev": [], "targets": [], "skill": "",
				"kind": "misc", "st": "", "phys": false, "int": false, "t": 0.0, "wait": 0.0,
				"ult": null, "foes": [], "allies": [], "min_t": 0.0}
			groups.append(g)
		g.ev.append(i)
		group_of.append(g)
		var fx: String = e.get("fx", "")
		if fx == "ult":
			g.ult = e
		elif fx == "skill":
			g.skill = e.name
		elif (fx == "phys" or fx == "int") and e.get("a") == g.who:
			if not g.targets.has(e.f):
				g.targets.append(e.f)
			g[fx] = true
		elif fx == "status" and g.st == "" and e.f != g.who:
			g.st = e.st
		# 고유기 이펙트를 뿌릴 곳 —— 적과 아군을 나눠 모은다
		var fk: String = e.get("f", "")
		if fk != "" and g.who != "" and (fk != g.who or fx == "heal"):
			var side: Array = g.foes if fk.substr(0, 1) != g.who.substr(0, 1) else g.allies
			if not side.has(fk):
				side.append(fk)
	if not rebuild:
		# 목표 길이에 맞춰 행동 간격을 벌리거나 좁힌다 (0.12~7배 —— 짧은 판은 늘리고, 긴 판은 행동을 촘촘히)
		# 턴 배율(Battle.turn_mul) 뒤로 같은 등급끼리 15턴 안팎 · 행동 약 270번이라 0.2배 근처가 된다
		var sched := 0.0
		for gr in groups if not _rt() else []:
			if gr.ph == "end":
				sched += 0.45
			elif gr.who != "":
				sched += STEP
		pace = clampf((target_len - OPEN) / maxf(1.0, sched), 0.12, 7.0) if target_len > 0 and not _rt() else 1.0
	var t := OPEN
	for gr in groups:
		if gr.who != "" and field.squads.has(gr.who):
			var cls: String = field.squads[gr.who].cls
			if gr.phys and (cls == "melee" or cls == "cav"):
				gr.kind = "melee"
			elif gr.phys and cls == "ranged":
				gr.kind = "volley"
			elif gr.phys or gr.int:
				gr.kind = "spell"
		if _rt():
			gr.t = OPEN_RT + float(ev[gr.ev[0]].get("tm", 0.0))
		elif gr.ph == "end":
			gr.t = t + 0.15 * pace
			t += 0.45 * pace
		elif gr.who == "":
			gr.t = t
		else:
			gr.t = t
			t += STEP * pace
	# 유닛별 손실 예정 시각 —— 흘려 넣는 기간을 정한다
	loss_times = []
	for u in res.roster.size():
		loss_times.append([])
	for gr in groups:
		for i in gr.ev:
			for ch in changes[i]:
				if ch[1] < 0 and not loss_times[ch[0]].has(gr.t):
					loss_times[ch[0]].append(gr.t)
	for lt in loss_times:
		lt.sort()
	if not rebuild:
		shown = []
		drain = []
		src = []
		for c in cur:
			shown.append(c.duplicate())
			drain.append([0.0, 0.0])
			src.append("")
		rout_wait.clear()
		ambient.clear()
		for sq in field.order:
			ambient[sq.key] = OPEN + rng.randf_range(0.5, 2.5)
	else:
		for gr in groups:
			gr.t -= _shift
	plans.clear()
	for gr in groups:
		if gr.kind in ["melee", "volley", "spell"] and not gr.targets.is_empty():
			if not plans.has(gr.who):
				plans[gr.who] = []
			plans[gr.who].append([gr.t, gr.targets[0]])


# ───────── 재생 ─────────

func _process(dt: float) -> void:
	var tv := Time.get_ticks_usec()
	if not _press.is_empty() and Time.get_ticks_msec() - _press[1] >= LONG_PRESS * 1000:
		var pp: Vector2 = _press[0]
		_press = []
		if field and field.flat != null:      # 2D 전장 —— 그려진 메달 자리에서 고른다. 아군 · 적군 모두 전투장수창 (11/9 사용자)
			var mq: Squad = hud.medal_at(pp)
			if mq and DB.C.has(mq.cid):
				UI.buzz(30)
				unit_requested.emit(mq.key)
		else:
			var sq := field.squad_at(pp) if field else null
			if sq:
				field.follow_squad(sq)
				UI.buzz(30)
				hud.announce("%s 따라가기" % sq.row.name, DB.PAL.gold)
	_process_inner(dt)
	if field:
		field.pt("[화면전체]", tv)


func _process_inner(dt: float) -> void:
	if not running:
		return
	var sk := str(speed)
	speed_sec[sk] = float(speed_sec.get(sk, 0.0)) + dt
	if slow_t > 0:
		slow_t -= dt
	_freeze_cd -= dt
	# 11/5 사용자: 일기토 문구는 뺀다 (아무 효과가 없는데 기대하게 된다)
	_ace_cd -= dt
	_kill_cd -= dt
	_spot_step(dt)
	var spd := speed * (SLOW if slow_t > 0 else 1.0)
	if freeze_t > 0:
		freeze_t -= dt
		spd *= FREEZE_SPD
	# 11/4 개전 대기 —— 맞닿기 전까지는 빠르게 흘린다 (대열 칸을 키운 뒤 다가오기만 하는 3초가 길었다)
	if not _met:
		if field.order.any(func(q): return q.contact):
			_met = true
			_first_clash()
		elif clock > 0.3 and speed > 0:
			spd *= MARCH_SPD
	field.time_scale = spd
	field.active = is_visible_in_tree()
	var d := dt * spd
	clock += d
	field.clock = clock
	var t0 := Time.get_ticks_usec()
	if _rt():
		field.follow_track(res.track, clock - OPEN_RT)
	else:
		field.direct(plans)
	_ambient_fire()
	t0 = field.pt("지휘", t0)
	field.step(d)
	t0 = Time.get_ticks_usec()
	while gi < groups.size() and groups[gi].t <= clock:
		# 고유기 컷인은 한 번에 하나 —— 앞 연출이 끝날 때까지 다음 고유기는 기다린다
		if groups[gi].ult != null and (slow_t > 0 or hud.cut != null):
			break
		_start_group(groups[gi])
		gi += 1
	for g in pending.duplicate():
		if clock >= g.min_t and (field.arrived(g.who) or clock >= g.wait):
			pending.erase(g)
			_release(g, clock)
	t0 = field.pt("감독·묶음", t0)
	while not due.is_empty() and due[0][0] <= clock:
		_apply(due.pop_front()[1])
	t0 = field.pt("감독·사건", t0)
	_drain_step(d)
	t0 = field.pt("감독·흘림", t0)
	_lead_step()
	field.pt("감독", t0)
	if not finished and gi >= groups.size() and pending.is_empty() and due.is_empty() and not _draining():
		if finish_t < 0:
			finish_t = clock + 1.0
		elif clock >= finish_t:
			_finish()
	var t2v = field.flat if field.flat != null and field.flat.get("load_lv") != null else null
	if t2v == null or int(t2v.load_lv) < 2 or Engine.get_process_frames() % 2 == 0:
		hud.queue_redraw()      # 11/6 부하 조절 2단계면 HUD 를 30Hz 로


## 전환점 (11/4 연출 점검) —— 화면에 보이는 병력 비율이 뒤집히는 순간 "전세 역전!" (한 판 둘까지)
func _lead_step() -> void:
	if finished or clock < 3.0:
		return
	var tA := 0.0
	var tB := 0.0
	for u in shown.size():
		if cur[u][0] > 0.0:
			if res.roster[u].camp == "A": tA += shown[u][0]
			else: tB += shown[u][0]
	if tA + tB <= 0.0:
		return
	var r := tA / (tA + tB)
	var now := 1 if r >= LEAD_ON else (-1 if r <= 1.0 - LEAD_ON else 0)
	if now == 0 or now == _lead:
		return
	var was := _lead
	_lead = now
	if was == 0 or _turns_n >= 2:
		return
	_turns_n += 1
	if now == 1:
		hud.announce("전세 역전!", Color("#ffd257"))
		hud.flash(Color(1.0, 0.85, 0.4))
		Sfx.play("horn", 2.0)
	else:
		hud.announce("전세가 기운다…", Color("#ff7a66"))
		Sfx.play("rout", -4.0)
	impact(0.12, 0.8)


## 궁병·지략 계열은 제 차례 사이에도 쉬지 않고 쏘고 던진다 (피해는 엔진 이벤트 때만 들어간다)
func _ambient_fire() -> void:
	if finished:
		return
	for sq in field.order:
		if not sq.alive or sq.state == "flee" or (sq.cls != "ranged" and sq.cls != "caster"):
			continue
		if clock < ambient.get(sq.key, 0.0):
			continue
		ambient[sq.key] = clock + rng.randf_range(2.2, 3.6)      # 11/4 저녁 북적임으로 1.4~2.4 까지 줄였다가 번쩍거림으로 되돌림
		var p: Array = plans.get(sq.key, [])
		if p.is_empty() or not field.squads.has(p[0][1]) or not field.squads[p[0][1]].alive:
			continue
		if sq.cls == "ranged":
			field.volley(sq.key, [p[0][1]], true)
			Sfx.play("arrow", -7.0)      # 자유 사격은 작게
		else:
			field.cast(sq.key, [p[0][1]], "", true)


## 고유기 기 모으기 예고 —— 맞을 곳을 붉게(적) · 푸르게(아군) 깔고, 적이면 크게 알리고 방진 버튼을 깜빡인다
func _ult_warn(e: Dictionary) -> void:
	var mine: bool = str(e.a).begins_with("A")
	var wait: float = e.get("wait", 2.5)
	var col := Color("#6fb0ff") if mine else Color("#ff4a3a")
	for w in e.get("warn", []):
		field.area_mark({"k": "circle", "x": w.x, "y": w.y, "r": w.r}, col, wait + 0.3)
	if field.squads.has(e.a):
		field.skill_fx(e.a)
	var who: String = res.roster[idx_of[e.a]].name if idx_of.has(e.a) else ""
	# 11/7 사용자: "기를 모은다 —— 2.5초" 글 대신 작은 장수 이름 · 붓글씨 기술명 · 차오르는 고리 · 「운기」 (Hud.charge_start —— 아군은 늘, 적은 직접 지휘 때만 보인다)
	hud.charge_start(e.a, who, e.name, wait, mine)
	if not mine:
		warn_until = clock + wait
		warn_key = e.a
		if direct:
			UI.buzz(40)
		warn_name = "%s 『%s』" % [who, e.name]


func _ult_cut(e: Dictionary) -> void:
	var f: String = e.get("f", "")
	if f == warn_key:
		warn_until = -1.0
	hud.charge_end(f)      # 기 모으기 표시도 걷는다
	# 11/2 사용자: 맞받아치기 · 끊었다 같은 큰 글씨는 이상하다 → 띄우지 않는다
	if field.squads.has(f):
		field.squads[f].hurt = 1.0
	slow_t = maxf(slow_t, 0.6)


## 기술 · 고유기 범위를 땅에 깐다 (실시간 엔진이 사건에 area 를 적는다)
func _show_areas(g: Dictionary) -> void:
	for i in g.ev:
		var e: Dictionary = res.ev[i]
		if e.has("area"):
			var col: Color = Color("#ffd257") if e.get("fx") == "ult" else (Color("#6fb0ff") if str(e.get("a", "A")).begins_with("A") else Color("#ff6a5a"))
			for sh in e.area:
				field.area_mark(sh, col, 1.4 if e.get("fx") == "ult" else 1.0)


func _start_group(g: Dictionary) -> void:
	_show_areas(g)
	for i in g.ev:
		var e: Dictionary = res.ev[i]
		match e.get("fx", ""):
			"ult_warn":
				_ult_warn(e)
			"ult_cut":
				_ult_cut(e)
	if g.ult != null and field.squads.has(g.who):
		_start_ult(g)
		return
	if g.skill != "":
		field.skill_fx(g.who)
		var asq: Squad = field.squads.get(g.who)
		# 11/4 연출 점검: 5일차 한 판에 기술 현판 45~89장 —— 현판은 초월 이상과 진영 상위 둘(hud._emph)만, 나머지는 작은 글씨
		var star: bool = asq != null and (asq.tier >= 6 or hud._emph.get(g.who, 0) > 0)
		if star:
			hud.skill_banner(g.who, g.skill)
		else:
			hud.float_text(g.who, g.skill, Color("#e8d6a8"), 11)
		field.skill_hit_fx(g.targets, g.kind == "spell")
		# 11/3 에이스(불멸 · 신화) 장수 기술 —— 카메라가 잠깐 다가간다 (6초에 한 번까지, 직접 보고 있는 부대가 없을 때)
		# 11/4 고유기 없는 초반(2일차)에도 '내 장수' 순간이 있도록 —— 진영 1등 장수도
		if asq and (asq.tier >= 7 or hud._emph.get(g.who, 0) == 1) and _ace_cd <= 0 and speed > 0 and field.follow == null:
			_ace_cd = 6.0
			field.cinematic(asq, 1.1)
			spotlight(asq, 0.75)
	match g.kind:
		"melee":
			if _rt():
				field.clash(g.who, g.targets[0], g.skill != "")       # 실시간 엔진은 맞닿았을 때만 친다 —— 이미 붙어 있다
				_release(g, clock)
			else:
				field.order_melee(g.who, g.targets[0])
				g.wait = clock + MELEE_WAIT
				pending.append(g)
		"volley":
			field.volley(g.who, g.targets, false, g.skill != "")
			Sfx.play("arrow", 2.0 if g.skill != "" else 0.0)      # 11/4 사용자: 궁병 화살 소리 (시위 + 쉭, tools/scripts/make_arrow_sfx.py)
			_release(g, clock + 0.72)
		"spell":
			field.cast(g.who, g.targets, g.st)
			_release(g, clock + 0.6)
		_:
			_release(g, clock)


## 집중 비네트 (11/3 사용자) —— 0.12초에 어두워져 잠깐 머물고 0.3초에 걸쳐 걷힌다. 시전 부대 병사는 그동안 밝게(War3D.focus_sq)
## 첫 격돌 (11/5 사용자: 초중반이 허전하다) —— 양군이 처음 맞닿는 순간 띠 · 짧은 멈춤 · 흔들림 · 북
func _first_clash() -> void:
	if finished or not is_visible_in_tree():
		return
	hud.announce("선봉 격돌!", Color("#ffd28a"))
	impact(0.12, 1.4)
	Sfx.play("drums")      # 11/5 사용자: 함성은 불쾌하다 —— 소리 파일까지 뺐다
	for q in field.order:
		if q.contact and q.engaged != null:
			field.clash(q.key, q.engaged.key, true)


## 일기토 —— 장수(고급 이상)끼리 맞붙고 두 장수가 가까우면 한 번 이름을 띄우고 짧게 비춘다. 짝마다 한 번, 한 판 셋까지, 6초 간격
func _duel_step() -> void:
	if not _met or finished or _duel_cd > 0.0 or _duels.size() >= 3 or freeze_t > 0.0 or hud.cut != null:
		return
	for q in field.order:
		var e: Squad = q.engaged
		if q.camp != "A" or not q.contact or e == null or not e.alive or q.general == null or e.general == null:
			continue
		if not q.general.alive or not e.general.alive or maxi(q.tier, e.tier) < 4:
			continue
		var k: String = q.key + "|" + e.key
		if _duels.has(k) or q.general.pos.distance_to(e.general.pos) > 60.0:
			continue
		_duels[k] = true
		_duel_cd = 6.0
		hud.announce("일기토 —— %s  대  %s" % [DB.person(q.cid), DB.person(e.cid)], Color("#ffe6a8"))
		spotlight(q if q.tier >= e.tier else e, 1.4)
		impact(0.1, 0.9)
		Sfx.play("swing", 2.0, 0.1)
		Sfx.play("clash", 3.0)
		return


func spotlight(sq: Squad, dur: float) -> void:
	spot_sq = sq
	spot_len = dur
	spot_t = dur
	field.focus_sq = sq
	field.focus_t = dur


func _spot_step(dt: float) -> void:
	if spot == null:
		return
	if spot_t <= 0.0 or spot_sq == null:
		spot.visible = false
		field.focus_t = 0.0
		return
	spot_t -= dt
	field.focus_t = spot_t
	var el := spot_len - spot_t
	var a := clampf(el / 0.12, 0, 1) * clampf(spot_t / 0.3, 0, 1)
	var p := field.to_screen(spot_sq.pos, 1.0)
	var sz := spot.size
	if sz.x < 1 or p.x < -9999:
		spot.visible = false
		return
	spot.visible = true
	var m: ShaderMaterial = spot.material
	m.set_shader_parameter("center", p / sz)
	m.set_shader_parameter("aspect", sz.x / sz.y)
	m.set_shader_parameter("radius", 0.2)
	m.set_shader_parameter("strength", 0.62 * a)
	m.set_shader_parameter("glow", DB.TIER[spot_sq.tier].c if spot_sq.tier >= 6 else Color(1, 0.85, 0.5))


## 임팩트 프리즈 + 카메라 흔들림 (11/3). dur 실시간 초, kick 흔들림 세기
func impact(dur: float, kick: float) -> void:
	if _freeze_cd > 0 or speed <= 0:
		return
	freeze_t = dur
	_freeze_cd = dur + 0.25
	field.shake = maxf(field.shake, kick)
	hud.flash(Color(1, 0.92, 0.75))        # 꽂히는 순간 화면이 하얗게 번쩍


## 휘두르는 소리 —— 실제 시간으로 세 번 (슬로모션과 상관없이)
func _swing_sounds() -> void:
	for i in 3:
		get_tree().create_timer(0.05 + i * 0.3).timeout.connect(func(): Sfx.play("swing", 2.0, 0.1))      # 칼 · 창 휘두르는 소리 (11/4 Still North Media 녹음)
	get_tree().create_timer(0.95).timeout.connect(func(): Sfx.play("crit_%d" % (1 + randi() % 4), 4.0))


## 고유기 —— 슬로모션 + 화면 가운데 초상 컷인 + 카메라가 다가간 뒤 대형 이펙트와 함께 터진다
func _start_ult(g: Dictionary) -> void:
	var sq: Squad = field.squads[g.who]
	var u: Dictionary = g.ult
	hud.charge_end(g.who)      # 기 모으기 표시는 컷인이 뜨면 걷는다
	if speed > 0:
		slow_t = 2.8      # 11/4 휘두르기 · 날리기까지 슬로모션 (11/6 컷인이 길어져 2.0 → 2.8)
	var ud = DB.ult_of(sq.cid) if DB.C.has(sq.cid) else null      # 효과 문구는 카드의 고유기 정의에서 (사건 쪽 사전에는 eff 가 없다)
	var desc := _ult_short(ud, sq.tier) if ud != null and ud.has("eff") else ""
	hud.ult_cutin(sq, u.name, u.shout, u.get("crisis", false), desc)
	# 11/4 사용자: 숄더뷰로 다가가 장수가 무기를 크게 휘두르고(효과 · 소리), 적이 날아간 뒤 원래 카메라로
	field.cinematic(sq, 3.0, true)
	get_tree().create_timer(CUT_T * 0.7).timeout.connect(func():
		if is_instance_valid(sq):
			field.flourish(sq, 1.3)
			_swing_sounds())
	spotlight(sq, 1.3)
	field.ult.play(u.vfx, g.who, g.foes, g.allies, ULT_DELAY)
	g.min_t = clock + ULT_DELAY
	if g.phys and (sq.cls == "melee" or sq.cls == "cav") and not g.targets.is_empty() and not _rt():
		field.order_melee(g.who, g.targets[0])
		g.wait = clock + MELEE_WAIT
		pending.append(g)
	else:
		_release(g, clock + ULT_DELAY)


## 컷인 아래 한 줄 효과 —— 대상 설명은 빼고 수치만: "피해 423% · 사기 −2 · 화상" (11/6 사용자)
func _ult_short(u: Dictionary, tier: int) -> String:
	var tm := Battle.turn_mul_for(tier) if tier > 0 else 1.0
	var parts := []
	for comp in u.eff:
		var s := ""
		match str(comp.get("t", "")):
			"hit":
				s = "피해 %d%%" % roundi(float(comp.mult) * tm * 100)
				if comp.has("morale"):
					s += " · 사기 −%d" % roundi(float(comp.morale) * Battle.burst())
				if comp.has("status"):
					s += " · " + str(DB.D.STATUS.get(comp.status.k, {}).get("n", comp.status.k))
				if comp.has("exec"):
					s += " · 즉사"
			"ally":
				if comp.has("heal"):
					s = "아군 병력 +%.0f%%" % (float(comp.heal) * Battle.burst() * 100)
				elif comp.has("buff"):
					s = "아군 %s %+d%%" % [DB.D.STATNM.get(comp.buff.stat, comp.buff.stat), roundi(float(comp.buff.amt) * 100)]
				elif comp.has("morale"):
					s = "아군 사기 +%d" % roundi(float(comp.morale) * Battle.burst())
			"foe":
				if comp.has("status"):
					s = str(DB.D.STATUS.get(comp.status.k, {}).get("n", comp.status.k))
				elif comp.has("buff"):
					s = "적 %s %+d%%" % [DB.D.STATNM.get(comp.buff.stat, comp.buff.stat), roundi(float(comp.buff.amt) * 100)]
				elif comp.has("morale"):
					s = "적 사기 −%d" % roundi(float(comp.morale) * Battle.burst())
		if s != "" and not parts.has(s):
			parts.append(s)
	return " · ".join(parts)


func _release(g: Dictionary, t0: float) -> void:
	var k := 0
	for i in g.ev:
		due.append([t0 + k * 0.06, i])
		k += 1
	due.sort_custom(func(a, b): return a[0] < b[0] or (a[0] == b[0] and a[1] < b[1]))


func _apply(i: int, quiet := false) -> void:
	var e: Dictionary = res.ev[i]
	# 11/2 고유기 묶음은 늦게 풀려 사건이 순서를 건너뛴다 —— 게이지 표시는 가장 늦은 사건만 (예전 사건으로 되돌아가면 막대가 요동쳤다)
	if i >= live_i:
		live_i = i
		live_e = e
	_log(e)
	var from: String = e.get("a", e.get("who", ""))
	for ch in changes[i]:
		var u: int = ch[0]
		cur[u][0] += ch[1]
		cur[u][1] += ch[2]
		if from != "":
			src[u] = from
		if quiet or not smooth:
			_snap(u)
		else:
			_retarget(u)
		field.squads[res.roster[u].key].statuses = e.s[u][3]
	var f: String = e.get("f", "")
	if f != "" and idx_of.has(f):
		field.squads[f].statuses = e.s[idx_of[f]][3]
	if quiet:
		if e.get("fx") == "rout":
			_snap(idx_of[f])
			field.rout(f)
		return
	_damage_number(i, e, f)
	_sound(e)
	# 무쌍 —— 기술 · 고유기 타격은 병력을 바로 깎고 쓰러질 병사들을 한꺼번에 날린다
	var gq: Dictionary = group_of[i]
	if (e.get("fx") == "phys" or e.get("fx") == "int") and (gq.skill != "" or gq.ult != null) and idx_of.has(f) and smooth:
		_snap(idx_of[f])
		# 11/3 사용자: 에이스 장수의 무쌍만이 전장을 지배하도록 —— 날리기 · 프리즈 · 흔들림을 예전의 약 3배로 (일반 장수 기술은 그대로)
		var ace: bool = field.squads.has(gq.who) and field.squads[gq.who].tier >= 7
		field.blast(f, from, 4.5 if gq.ult != null else (3.0 if ace else 1.0))
		if gq.ult != null:
			impact(0.24, 1.5)
		elif ace:
			impact(0.15, 1.0)
	if e.has("mn") and field.squads.has(e.get("a", "")):      # 잔기술 (11/5) —— 쓴 부대 위에 이름 + 종류별 이펙트 (War3D.minor_fx)
		hud.float_text(e.a, e.mn, Color("#b9a0ff") if e.fx == "int" else Color("#f0d79a"), 12, true)      # 11/6 #16 B등급: 부대마다 하나만
		if smooth:
			field.minor_fx(str(e.get("mk", "")), e.a, f)
	match e.get("fx", ""):
		"phys":
			if field.squads.has(e.a) and field.squads[e.a].cls != "ranged":
				field.clash(e.a, f, e.get("crit", false) or e.has("mn") or group_of[i].skill != "" or group_of[i].ult != null)
			# 11/2 불멸 · 신화는 평타에도 적 병사가 튕겨 나간다 (압도적인 파괴력) —— 무거운 소리와 함께
			if smooth and field.squads.has(e.a) and field.squads[e.a].tier >= 7 and gq.skill == "" and gq.ult == null and idx_of.has(f):
				_snap(idx_of[f])
				field.blast(f, e.a, 0.5 if field.squads[e.a].tier == 7 else 0.8)
				Sfx.play("crit")
			if e.get("dir", "") == "후방":       # 실시간 엔진 —— 뒤에서 친 타격만 (측면은 잦아서 띄우지 않는다, 10/31)
				hud.float_text(f, "후방!", Color("#ff5e3a"), 11)
		"heal":
			field.heal_fx(f)
		"rout":
			var u: int = idx_of[f]
			if smooth and cur[u][0] <= 0 and shown[u][0] > 0.5:
				# 병력이 다해 무너진다 —— 남은 병사가 0.9초에 걸쳐 다 쓰러진 뒤 무너뜨린다
				rout_wait[u] = true
				drain[u][0] = maxf(drain[u][0], shown[u][0] / 0.9)
			else:
				_do_rout(u)
		"dodge":
			hud.float_text(f, "회피", Color.WHITE, 12)
		"resist", "passive":
			pass          # 저항 · 단체 특기 —— 글씨를 띄우지 않는다 (화면을 덮었다)
		"chain":
			hud.chain(e)
			if e.camp == "A" and e.n >= 3:
				Sfx.play("horn", -6.0 + minf(6.0, float(e.n)))      # 11/4 횟수가 쌓일수록 크게
			if e.get("a", "") != "" and field.squads.has(e.a):
				field.squads[e.a].glow = 1.0
		"cmd":
			var col: Color = {"돌격": Color("#ff8a4a"), "방진": Color("#6fb0ff"), "재정비": Color("#8FD4C2")}.get(e.name, Color.WHITE)
			# 11/5 사용자: 군령 알림 글은 뺀다 (진영 빛만)
			field.cmd_fx(e.camp, col)
		"status", "cleanse", "debuff":
			pass          # 상태이상 · 해제 · 수치 깎기 —— 머리표 배지로 보인다
		"collapse":       # 11/4 총붕괴 —— 큰 띠 · 섬광 · 뿔나팔, 카메라가 뒤로 물러나 무너지는 전장을 담는다
			var mine: bool = e.camp == "A"
			hud.announce("아군 총붕괴!" if mine else "적군 총붕괴!", Color("#ff7a66") if mine else Color("#ffd257"))
			hud.flash(Color(0.9, 0.3, 0.2) if mine else Color(1.0, 0.85, 0.4))
			impact(0.2, 1.2)
			field.pull_back(2.5)
		"decisive":
			hud.announce("결전 —— 양군의 사기가 흔들린다", Color("#e8d6a8"))


## 소리 —— 사건 종류마다 (Sfx 가 잦은 소리는 건너뛴다)
func _sound(e: Dictionary) -> void:
	match e.get("fx", ""):
		"phys":      # 11/4 사용자: 병장기 소리 —— 칼 소리와 병장기 부딪침을 섞는다
			Sfx.play("crit" if e.get("crit", false) else "hit")
			Sfx.play("clash", -2.0, 0.1)
		"int": pass      # 11/4 사용자: '기공포' 같은 소리 —— RPG 효과음 팩의 마법 소리(magic · skill)를 전투에서 뺀다 (책략은 화면 효과로)
		"skill": if e.get("kind", "") == "phys": Sfx.play("crit")      # 11/4 사용자: 물리 기술은 '기공포' 같은 마법 소리 대신 병장기 소리
		"ult":
			Sfx.play("horn", -2.0)      # 고유기 —— 마법 소리(ult.wav) 대신 뿔나팔 + 병장기
			Sfx.play("crit", 2.0)
		"rout":
			Sfx.play("rout")
		"collapse":
			Sfx.play("horn", 3.0)
			Sfx.play("rout", 2.0)
		"heal": Sfx.play("heal")
		"cmd":
			Sfx.play("horn")
		"debuff": Sfx.play("debuff")
		"status", "tick":
			match str(e.get("st", "")):
				"burn": Sfx.play("burn")
				"flood": Sfx.play("splash")
				"confuse": Sfx.play("confuse")


func _exit_tree() -> void:
	Sfx.music("menu")


## 피해 숫자 —— 스킬·고유기로 들어간 타격은 치명타로 크게 찍는다 (수치는 엔진 그대로)
func _damage_number(i: int, e: Dictionary, f: String) -> void:
	var fx: String = e.get("fx", "")
	if f == "" or not e.has("n"):
		return
	var n: float = e.n
	match fx:
		"phys", "int":
			var k: String = "fire" if e.get("fire", false) else ("water" if e.get("water", false) else fx)
			# 11/4 연출 점검: 평타 치명타마다 큰 숫자가 찍혀 겹쳐 쌓였다 —— 크게 찍는 것은 기술 · 고유기 · 불멸 이상의 치명타만
			var gq: Dictionary = group_of[i]
			var big: bool = gq.skill != "" or gq.ult != null or (field.squads.has(gq.who) and field.squads[gq.who].tier >= 7)
			if Settings.dmg_numbers == 0 and not big and not e.get("crit", false):      # 11/6 #16 C등급(평타)은 '큰 것만' 에서 숨긴다
				return
			hud.damage(f, n, k, e.get("crit", false) and big, Settings.dmg_numbers == 2)     # 불타는(화공) · 잠긴(수공) 적을 더 세게 친 타격
		"heal":
			hud.damage(f, n, "heal", false)
		"tick":
			hud.damage(f, n, "tick", false)


func _snap(u: int) -> void:
	shown[u] = cur[u].duplicate()
	drain[u] = [0.0, 0.0]
	field.apply(res.roster[u].key, shown[u][0], shown[u][1], src[u])


## 목표가 바뀌면 흘려 넣는 속도를 다시 잰다 —— 다음 손실 예정까지 다 따라잡도록
func _retarget(u: int) -> void:
	var gap: float = shown[u][0] - cur[u][0]
	if gap > 0:
		var next := -1.0
		for t in loss_times[u]:
			if t > clock + 0.05:
				next = t
				break
		var span := clampf(next - clock if next > 0 else 1.6 * pace, 0.8, 3.5 * pace)     # 대전을 늘린 만큼 흘려 넣는 창도 늘린다
		drain[u][0] = gap / span
	else:
		drain[u][0] = -gap / 0.5            # 회복은 빠르게
	drain[u][1] = absf(shown[u][1] - cur[u][1]) / 0.6


func _drain_step(dt: float) -> void:
	for u in shown.size():
		var moved := false
		if absf(cur[u][0] - shown[u][0]) > 0.01:
			shown[u][0] = move_toward(shown[u][0], cur[u][0], maxf(drain[u][0], 1.0) * dt)
			moved = true
		if absf(cur[u][1] - shown[u][1]) > 0.01:
			shown[u][1] = move_toward(shown[u][1], cur[u][1], maxf(drain[u][1], 5.0) * dt)
			moved = true
		if moved:
			field.apply(res.roster[u].key, shown[u][0], shown[u][1], src[u])
		if rout_wait.has(u) and absf(cur[u][0] - shown[u][0]) < 0.5:
			rout_wait.erase(u)
			_do_rout(u)


func _draining() -> bool:
	if not rout_wait.is_empty():
		return true
	for u in shown.size():
		if absf(cur[u][0] - shown[u][0]) > 0.5:
			return true
	return false


func _do_rout(u: int) -> void:
	var key: String = res.roster[u].key
	_snap(u)
	var sq: Squad = field.squads.get(key)
	hud.float_text(key, "궤멸" if sq and sq.troops <= 0 else "패주!", Color("#ff6b57"), 16)
	# 11/4 격파 연출 —— 적 장수가 무너지면 메달이 깨지며 "격파!", 카메라가 그쪽으로 잠깐 당겨진다 (4초에 한 번)
	if sq and sq.camp == "B" and not finished and sq.tier >= 3:      # 병졸 부대는 메달 연출 없이 (큰 검은 원만 남았다)
		hud.kill_mark(sq)
		impact(0.1, 0.5)
		if _kill_cd <= 0 and speed > 0 and field.follow == null and sq.tier >= 3 and field._cine <= 0:
			_kill_cd = 4.0
			field.cinematic(sq, 0.7)
	field.rout(key)


func _log(e: Dictionary) -> void:
	if dbg_nolog:
		return
	if e.c == "div":
		if e.t != "":
			log_box.append_text("[color=#C6AC7C]%s[/color]\n" % e.t)
		return
	if e.get("fx") == "ult":
		log_box.append_text("[color=#5d6a88]%s[/color] [color=#ffd76e][b]%s[/b][/color]\n" % [clock_text(), e.t])
		return
	var col: String = {"A": "#E9E3D3", "B": "#E9A79E", "sk": "#D9A64B", "mo": "#C9A2FF", "hl": "#8FD4C2",
		"st": "#E8A06A", "rt": "#FF6B57"}.get(e.c, "#E9E3D3")
	log_box.append_text("[color=#5d6a88]%s[/color] [color=%s]%s[/color]\n" % [clock_text(), col, e.t])


func clock_text() -> String:
	var s := int(end_clock if end_clock > 0.0 else clock)      # 11/3 끝난 뒤에는 시계를 멈춘다 (결과표 시간과 달랐다)
	return "%d:%02d" % [s / 60, s % 60]


## 결과로 —— 남은 행동을 연출 없이 한꺼번에 적용한다.
## 온라인 재생(locked)도 된다 (11/9 사용자: 리플레이를 나갈 방법이 없었다) —— 끝나면 ended 가 나가 결과표 · [종료] 가 뜨고, 닫으면 본 것으로 친다 (Online.watch_next)
func skip() -> void:
	if not running or finished:
		return
	var rest := []
	for d in due:
		rest.append(d[1])
	for g in pending:
		rest.append_array(g.ev)
	for j in range(gi, groups.size()):
		rest.append_array(groups[j].ev)
	rest.sort()
	due.clear()
	pending.clear()
	gi = groups.size()
	for u in shown.size():
		_snap(u)
	for u in rout_wait.keys():
		field.rout(res.roster[u].key)
	rout_wait.clear()
	for i in rest:
		_apply(i, true)
	_finish()


func _finish() -> void:
	finished = true
	# 흘려 넣은 결과가 엔진의 최종 병력과 같은지 확인한다
	var final: Array = res.ev[res.ev.size() - 1].s
	for u in shown.size():
		if absf(shown[u][0] - final[u][0]) > 1.0:
			push_warning("병력 불일치 %s: 화면 %.0f / 엔진 %d" % [res.roster[u].name, shown[u][0], final[u][0]])
	if not res.draw:
		field.celebrate("A" if res.win else "B")
	var txt := "무승부" if res.draw else ("승전" if res.win else "패전")
	var col: Color = DB.PAL.jade if res.win else DB.PAL.seal
	var sub := "잔존 %d부대 대 %d부대 · %s" % [res.left, res.eLeft, clock_text()]
	if res.mvp:
		sub += "\n수훈갑  %s  · 격파 %d" % [res.mvp.name, res.mvp.kills]
	hud.stamp(txt, sub, col)
	Sfx.play("lose" if res.draw or not res.win else "win")
	end_clock = clock
	ended.emit(res, inputs)
	log_box.append_text("\n[color=%s][b]%s[/b][/color] — %s\n" % [col.to_html(false), txt, sub.replace("\n", " · ")])


# ───────── 화면 위 표시 (전장 확대와 상관없이 같은 크기) ─────────

class Hud extends Control:
	var view: BattleView
	var floats := []
	var stamp_info = null
	var stamp_t := 0.0

	func reset() -> void:
		if _medal_cache.size() > 600:      # 11/9 구운 메달은 (장수 · 진영 · 등급색 · 크기 · 배율)이 키라 전투를 넘어 써도 된다 —— 너무 쌓였을 때만 비운다
			_medal_cache.clear()
		floats.clear()
		stamp_info = null
		chains_fx.clear()
		kills.clear()
		chain_pop = null
		charges.clear()

	## 격파 (11/4) —— 무너진 적 장수 자리에 메달이 크게 찍혔다가 금이 가며 떨어진다
	var kills := []

	func kill_mark(sq: Squad) -> void:
		kills.append({"p": sq.pos, "cid": sq.cid, "name": DB.person(sq.cid) if sq.tier > 2 else sq.row.name,
			"tier": sq.tier, "t0": view.clock, "r": randf_range(-0.5, 0.5)})

	func _draw_kills() -> void:
		const LIFE := 1.1
		var keep := []
		for k in kills:
			var t: float = view.clock - k.t0
			if t > LIFE:
				continue
			keep.append(k)
			var p := _to_screen(k.p, 6.0)
			if p.x < -9999:
				continue
			var u := t / LIFE
			var a := clampf(t / 0.08, 0, 1) * clampf((LIFE - t) / 0.3, 0, 1)
			var sc := lerpf(1.6, 1.0, ease(clampf(t / 0.18, 0, 1), 0.4))
			var r := 22.0 if k.tier >= 3 else 14.0
			var drop := ease(clampf((t - 0.5) / 0.6, 0, 1), 2.0) * 26.0
			draw_set_transform(p + Vector2(0, -30 + drop), lerpf(0.0, k.r, ease(clampf((t - 0.5) / 0.6, 0, 1), 2.0)), Vector2.ONE * sc)
			draw_circle(Vector2.ZERO, r + 3.0, Color(0, 0, 0, 0.6 * a))
			draw_circle(Vector2.ZERO, r + 2.0, Color(DB.tier_color(k.cid), a))
			draw_circle(Vector2.ZERO, r + 0.6, Color(War3D.TEAM.B, a))
			if k.tier >= 3:
				Art.draw_face_circle(self, Vector2.ZERO, r, k.cid, a)
			else:
				draw_circle(Vector2.ZERO, r, Color(0.3, 0.1, 0.08, a))
			draw_circle(Vector2.ZERO, r, Color(0.25, 0.02, 0.0, 0.12 * a + 0.45 * u * u))      # 떨어지며 어두워진다
			# 금 —— 비스듬한 꺾인 선, 0.25초 뒤에 간다
			if t > 0.25:
				var ca := clampf((t - 0.25) / 0.1, 0, 1) * a
				var pts := PackedVector2Array([Vector2(-r * 0.55, -r * 0.9), Vector2(-r * 0.1, -r * 0.2), Vector2(-r * 0.35, r * 0.15), Vector2(r * 0.25, r * 0.95)])
				draw_polyline(pts, Color(0.05, 0.02, 0.0, ca), 3.0)
				draw_polyline(pts, Color(1.0, 0.9, 0.7, ca), 1.2)
			draw_set_transform(Vector2.ZERO)
			var fd := DB.font_display
			var tp := p + Vector2(-80, -30 - r * sc - 12 - u * 10)
			draw_string_outline(fd, tp, "격파!", HORIZONTAL_ALIGNMENT_CENTER, 160, 20, 6, Color(0, 0, 0, a))
			draw_string(fd, tp, "격파!", HORIZONTAL_ALIGNMENT_CENTER, 160, 20, Color("#ffd257", a))
		kills = keep

	## 아군 연쇄 큰 알림 (11/4) —— 화면 위 가운데에 "연쇄 ×n" 이 쾅 찍힌다 (3회부터)
	var chain_pop = null

	func _draw_chain_pop() -> void:
		if chain_pop == null:
			return
		var t: float = view.clock - chain_pop.t0
		if t > 1.1:
			chain_pop = null
			return
		var a := clampf(t / 0.06, 0, 1) * clampf((1.1 - t) / 0.3, 0, 1)
		var sc := lerpf(2.2, 1.0, ease(clampf(t / 0.16, 0, 1), 0.35))
		var n: int = chain_pop.n
		var txt := "%s 연쇄 ×%d" % [chain_pop.name, n]
		var fs := 22 + mini(n, 10)
		var fd := DB.font_display
		draw_set_transform(Vector2(size.x / 2, 112), 0, Vector2.ONE * sc)
		draw_string_outline(fd, Vector2(-200, 0), txt, HORIZONTAL_ALIGNMENT_CENTER, 400, fs, 8, Color(0.2, 0.08, 0, a))
		draw_string(fd, Vector2(-200, 0), txt, HORIZONTAL_ALIGNMENT_CENTER, 400, fs, Color("#ffd257").lerp(Color.WHITE, 0.3 * (1.0 - clampf(t / 0.3, 0, 1))) * Color(1, 1, 1, a))
		draw_set_transform(Vector2.ZERO)

	var ann = null
	var _flash := Color(0, 0, 0, 0)
	var _flash_t := 9.0

	## 고유기 섬광 —— 화면 전체가 그 빛으로 번쩍였다가 0.35초에 걸쳐 걷힌다
	var _flash_k := 1.0
	func flash(col: Color, big := false) -> void:
		_flash = col
		_flash_t = 0.0
		_flash_k = (0.5 if big else 0.22) if view.field.flat != null else 1.0      # 11/6 타입2: 번쩍임을 옅은 물듦으로. 고유기 폭발(big)은 세게 (명세 3단계)

	func announce(text: String, col: Color) -> void:
		ann = {"text": text, "col": col, "t": 0.0}

	## 기술 현판 —— 부대 머리 위에 1.4초. 진영색 띠 + 금테 + 큰 기술명 (삼국지13 전법 발동)
	var banners_sk := []

	func skill_banner(key: String, nm: String) -> void:
		var sq: Squad = view.field.squads.get(key)
		if sq == null:
			return
		banners_sk = banners_sk.filter(func(b): return b.key != key)
		banners_sk.append({"key": key, "name": nm, "t0": view.clock, "camp": sq.camp})

	func _draw_skill_banners() -> void:
		var keep := []
		for b in banners_sk:
			var t: float = view.clock - b.t0
			if t > 1.0:
				continue
			keep.append(b)
			var sq: Squad = view.field.squads.get(b.key)
			if sq == null:
				continue
			var p := _to_screen(sq.pos, 7.5)
			if p.x < -9999:
				continue
			# 10/31 사용자: 작고 짧게 (글씨 17 → 12, 1.4초 → 1.0초)
			var a := clampf(t / 0.08, 0, 1) * clampf((1.0 - t) / 0.25, 0, 1)
			var sc := lerpf(1.25, 1.0, ease(clampf(t / 0.14, 0, 1), 0.4))
			var fs := 15          # 11/3 사용자: 기술명이 안 읽힌다 (12 → 15, 외곽선 두껍게)
			var fd := DB.title_font(fs)      # 11/10 작은 글자는 굵은 고딕
			var tw := fd.get_string_size(b.name, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			var w := tw + 24.0
			var h := 23.0
			draw_set_transform(p + Vector2(0, -34 - t * 8), 0, Vector2.ONE * sc)
			var box := Rect2(Vector2(-w / 2, -h / 2), Vector2(w, h))
			var sb := StyleBoxFlat.new()
			sb.bg_color = Color(0.06, 0.05, 0.04, 0.88 * a)
			sb.border_color = Color("#d9a64b", a)
			sb.set_border_width_all(1)
			sb.set_corner_radius_all(3)
			draw_style_box(sb, box)
			var team: Color = War3D.TEAM[b.camp]
			draw_rect(Rect2(box.position + Vector2(2, 2), Vector2(4, h - 4)), Color(team.lightened(0.2), a))
			draw_rect(Rect2(box.end - Vector2(6, h - 2), Vector2(4, h - 4)), Color(team.lightened(0.2), a))
			draw_string_outline(fd, Vector2(-w / 2, 5.5), b.name, HORIZONTAL_ALIGNMENT_CENTER, w, fs, 5, Color(0, 0, 0, a))
			draw_string(fd, Vector2(-w / 2, 5.5), b.name, HORIZONTAL_ALIGNMENT_CENTER, w, fs, Color("#ffe6a8", a))
			draw_set_transform(Vector2.ZERO)
		banners_sk = keep

	func float_text(key: String, text: String, col: Color, fs: int, replace := false) -> void:
		var sq: Squad = view.field.squads.get(key)
		if sq == null:
			return
		if replace:
			floats = floats.filter(func(f): return f.key != key or f.get("num", false))
		var n := 0
		for f in floats:
			if f.key == key and view.clock - f.t0 < 0.8:
				n += 1
		floats.append({"key": key, "p": sq.pos, "text": text, "col": col, "fs": fs, "t0": view.clock, "n": n})

	const SMALL_HIT := 0.06          # 이보다 작은 타격은 모아서 띄운다 (부대 최대 병력 대비) —— 11/4 0.04 → 0.06 (숫자가 겹쳐 쌓였다)
	const SMALL_HIT_FAR := 0.1       # 멀리 볼 때 (War3D.overview) —— 큰 타격만
	var _small := {}                 # 부대 key + 종류 -> 아직 띄우지 않은 피해 합

	## 피해 숫자 —— 적이 입은 피해는 흰색, 아군이 입은 피해는 붉은색, 책략은 보랏빛, 회복은 초록.
	## 치명타는 금빛으로 크게 찍혔다가 자리를 잡고 "치명타!" 가 붙는다.
	func damage(key: String, amount: float, kind: String, crit: bool, every := false) -> void:
		var sq: Squad = view.field.squads.get(key)
		if sq == null:
			return
		var mine: bool = sq.camp == "A"
		var col: Color
		var fs := 14                     # 10/31 작게(15 → 11) → 11/3 사용자: 군단 사이에서 안 읽힌다 → 14 + 두꺼운 외곽선 (작은 타격은 그대로 모아서 띄운다)
		var text := "-" + Battle.num(amount)
		match kind:
			"phys":
				col = Color("#ff8a78") if mine else Color("#fff1dc")
			"int":
				col = Color("#e3a2ff") if mine else Color("#d8c4ff")
			"fire":
				col = Color("#ff7a2e") if mine else Color("#ffa040")
				fs = 15
			"water":
				col = Color("#3fa0ff") if mine else Color("#7cc4ff")
				fs = 15
			"heal":
				col = Color("#8FD4C2")
				text = "+" + Battle.num(amount)
				fs = 13
			_:
				col = Color("#ffb070")
				fs = 12
		if crit:
			col = Color("#ffd257") if not mine else Color("#ff6a4a")
			fs = 22
		if not crit:
			for f in floats:
				if f.key == key and f.get("num", false) and not f.crit and f.kind == kind and view.clock - f.t0 < 0.9 and view.clock - f.get("born", f.t0) < 1.6:      # 11/6 계속 맞는 부대 위 숫자가 몇 초씩 안 사라지고 커지기만 했다
					f.amount += amount
					f.text = ("+" if kind == "heal" else "-") + Battle.num(f.amount)
					f.t0 = view.clock - 0.05
					f.pop = view.clock
					f.p = sq.pos
					return
			# 작은 타격(부대 병력의 SMALL_HIT 아래)은 바로 띄우지 않고 모았다가 넘치면 한 번에
			var sk: String = key + kind
			var acc: float = _small.get(sk, 0.0) + amount
			var thr: float = (SMALL_HIT_FAR if view.field.overview else SMALL_HIT) * (0.0 if every else 1.0)
			if kind == "tick":
				thr *= 2.0      # 11/4 화상 · 침수 지속 피해 "-64" 가 부대마다 동시에 떠서 화면을 덮었다 —— 더 모아서
			if acc < sq.max * thr:
				_small[sk] = acc
				return
			_small.erase(sk)
			amount = acc
			text = ("+" if kind == "heal" else "-") + Battle.num(amount)
		var n := 0
		for f in floats:
			if f.key == key and view.clock - f.t0 < 0.6:
				n += 1
		floats.append({"key": key, "p": sq.pos, "text": text, "col": col, "fs": fs, "t0": view.clock, "kind": kind, "amount": amount,
			"pop": view.clock, "n": n % 3, "jx": randf_range(-22, 22), "crit": crit, "num": true, "born": view.clock})

	var cut = null           # 고유기 컷인 {k, name, shout, camp, col, t}
	var _brush := PackedVector2Array()

	func ult_cutin(sq: Squad, nm: String, shout: String, crisis := false, desc := "") -> void:
		cut = {"k": sq.cid, "who": sq.row.name, "name": nm, "shout": shout, "camp": sq.camp, "crisis": crisis,
			"col": DB.tier_color(sq.cid), "t": 0.0, "desc": desc}
		# 붓질 띠의 거친 가장자리 —— 매번 조금씩 다르게
		_brush = PackedVector2Array()
		var r := RandomNumberGenerator.new()
		r.randomize()
		for i in 25:
			_brush.append(Vector2(i / 24.0, r.randf_range(-0.09, 0.09)))

	func stamp(text: String, sub: String, col: Color) -> void:
		stamp_info = {"text": text, "sub": sub, "col": col}
		stamp_t = 0.0

	func _to_screen(p: Vector2, lift := 3.3) -> Vector2:
		var q: Vector2 = view.field.to_screen(p, lift)
		if absf(q.x) > 6000.0 or absf(q.y) > 6000.0:
			return Vector2(-99999, -99999)      # 카메라 바로 옆 · 뒤 —— 아주 큰 좌표는 다각형 분할을 깨뜨린다 (11/3)
		return q

	func _process(dt: float) -> void:
		if stamp_info:
			stamp_t += dt
		if cut:
			cut.t += dt
			if cut.t > CUT_T:
				cut = null
		_flash_t += dt
		if ann:
			ann.t += dt
			if ann.t > 1.8:
				ann = null

	## 덱 연쇄 띠 —— 아군은 왼쪽(금빛) · 적은 오른쪽(붉게), 진영마다 최근 셋. 횟수가 클수록 크게 (11/1 덱 감상 전투)
	var chains_fx := []

	func chain(e: Dictionary) -> void:
		chains_fx = chains_fx.filter(func(c): return not (c.camp == e.camp and c.name == e.name))
		chains_fx.append({"camp": e.camp, "name": e.name, "n": e.n, "t0": view.clock})
		if e.camp == "A" and int(e.n) >= 3:
			chain_pop = {"name": e.name, "n": int(e.n), "t0": view.clock}
			if int(e.n) >= 5:
				flash(Color(1.0, 0.85, 0.4))
		var mine := chains_fx.filter(func(c): return c.camp == e.camp)
		if mine.size() > 3:
			chains_fx.erase(mine[0])

	func _draw_chains() -> void:
		const LIFE := 2.6
		chains_fx = chains_fx.filter(func(c): return view.clock - c.t0 < LIFE)
		var row := {"A": 0, "B": 0}
		for c in chains_fx:
			var t: float = view.clock - c.t0
			var a := clampf(t / 0.15, 0, 1) * clampf((LIFE - t) / 0.5, 0, 1)
			var mine: bool = c.camp == "A"
			var big := 1.0 + minf(0.5, c.n / 30.0)
			var fs := int((15 if mine else 12) * big)
			var txt := "%s ×%d" % [c.name, c.n]
			var cfd := DB.title_font(fs)
			var tw := cfd.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + 22
			var h := fs + 12.0
			var slide := (1.0 - ease(clampf(t / 0.25, 0, 1), 0.3)) * 40.0
			var x := 10.0 - slide if mine else size.x - 10.0 - tw + slide
			var y: float = 124.0 + row[c.camp] * (h + 6)
			row[c.camp] += 1
			var col := Color("#ffd257") if mine else Color("#ff7a66")
			var sb := StyleBoxFlat.new()
			sb.bg_color = Color(0.08, 0.06, 0.02, 0.8 * a) if mine else Color(0.1, 0.03, 0.03, 0.7 * a)
			sb.border_color = Color(col, a * (0.6 + 0.4 * sin(t * 10.0) if t < 0.8 else 0.7))
			sb.set_border_width_all(2 if mine else 1)
			sb.set_corner_radius_all(6)
			draw_style_box(sb, Rect2(x, y, tw, h))
			_text(cfd, Vector2(x + 11, y + h * 0.5 + fs * 0.36), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(col.lightened(0.2), a))
			if mine and t < 0.6:
				_text(DB.font_body, Vector2(x + tw + 6, y + h * 0.5 + 4), "연쇄!", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(col, a * (1.0 - t / 0.6)))

	var prewarm: Array = []
	var prewarm_txt: Array = []

	func _draw() -> void:
		var t0 := Time.get_ticks_usec()
		if not prewarm.is_empty():
			for tx in prewarm:
				draw_texture_rect(tx, Rect2(0, 0, 2, 2), false, Color(1, 1, 1, 0.003))
			prewarm.clear()
		if not prewarm_txt.is_empty():
			var fd := DB.font_display
			var inv := Color(1, 1, 1, 0.003)
			for e in prewarm_txt:
				for twk in [0.92, 0.56]:      # 세로 · 가로 화면의 컷인 글씨 폭 (_draw_cut 과 같은 맞춤)
					var tw: float = size.x * twk
					var tfs := 64
					while tfs > 30 and fd.get_string_size(e[0], HORIZONTAL_ALIGNMENT_LEFT, -1, tfs).x > tw:
						tfs -= 2
					draw_string_outline(fd, Vector2(-9999, -9999), e[0], HORIZONTAL_ALIGNMENT_LEFT, -1, tfs, 12, inv)
					draw_string(fd, Vector2(-9999, -9999), e[0], HORIZONTAL_ALIGNMENT_LEFT, -1, tfs, inv)
				for fs in [20, 24]:
					draw_string(fd, Vector2(-9999, -9999), e[1], HORIZONTAL_ALIGNMENT_LEFT, -1, fs, inv)
				draw_string(fd, Vector2(-9999, -9999), e[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 22, inv)      # 11/7 기 모으기 표시의 기술명
				draw_string(fd, Vector2(-9999, -9999), CHARGE_WORD + "기", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, inv)
				draw_string(DB.font_bold, Vector2(-9999, -9999), e[2], HORIZONTAL_ALIGNMENT_LEFT, -1, 15, inv)
				draw_string(DB.font_body, Vector2(-9999, -9999), e[3], HORIZONTAL_ALIGNMENT_LEFT, -1, 15, inv)
			prewarm_txt.clear()
		_draw_all()
		_draw_kills()
		_draw_chains()
		_draw_chain_pop()
		_draw_charges()
		_draw_threats()
		view.field.pt("머리표", t0)

	## 11/6 #16 A등급 위험 신호 —— 화면 오른쪽 위 고정 칸: 적 고유기 준비(이름) · 아군 장수 병력 30% 아래(이름). 카메라 · 메달과 무관하게 늘 같은 자리
	var _threat_seen := {}
	func _draw_threats() -> void:
		var items := []
		for sq: Squad in view.field.order:
			if not sq.alive or sq.tier < 3:
				continue
			var nm: String = DB.person(sq.cid) if DB.C.has(sq.cid) else sq.row.name
			if sq.camp == "B" and sq.tier >= 6:
				var lv := view.unit_live(sq.key)
				if lv[1] > 0 and lv[0] >= 100.0:
					if not _threat_seen.has("u" + sq.key):
						_threat_seen["u" + sq.key] = view.clock
					if view.clock - float(_threat_seen["u" + sq.key]) < 3.0:
						items.append(["적 고유기 준비 · %s" % nm, Color("#ff6a4a")])
				else:
					_threat_seen.erase("u" + sq.key)
			if sq.camp == "A" and sq.troops / sq.max < 0.3 and sq.troops > 0:
				if not _threat_seen.has("h" + sq.key):
					_threat_seen["h" + sq.key] = view.clock
				if view.clock - float(_threat_seen["h" + sq.key]) < 3.0:
					items.append(["%s 위태롭다" % nm, Color("#ffb070")])
		var y := 104.0
		var fd := DB.title_font(13)      # 11/10 작은 글자는 굵은 고딕
		for it in items.slice(0, 3):
			var w: float = fd.get_string_size(it[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x + 22.0
			var r := Rect2(size.x - w - 10.0, y, w, 22.0)
			var sb := StyleBoxFlat.new()
			sb.bg_color = Color(0.06, 0.05, 0.04, 0.85)
			sb.border_color = Color(it[1], 0.5 + 0.5 * sin(view.clock * 8.0))
			sb.set_border_width_all(1)
			sb.set_corner_radius_all(4)
			draw_style_box(sb, r)
			draw_string(fd, r.position + Vector2(11, 16), it[0], HORIZONTAL_ALIGNMENT_LEFT, w - 22.0, 13, it[1])
			y += 26.0

	## 고유기 기 모으기 표시 (11/7 사용자: "○○ 『기술명』 기를 모은다 —— 2.5초" 글이 밋밋하다) —— 화면 위 가운데에
	## 작은 장수 이름 / 붓글씨(font_display) 『기술명』 / 왼쪽에 차오르는 금빛 고리(남은 초 대신, 안에 "기") / 오른쪽에 진영색 「운기」 낙관.
	## 아군은 늘, 적은 직접 지휘 때만 (방진으로 받으라는 신호 —— 붉은 테가 깜빡인다). 고리는 전장 시계로 wait 초에 걸쳐 차고, 다 차면 잠깐 번쩍인다.
	## 문구 후보: 운기(運氣) · 기합 · 천지가 숨을 멈춘다 · 일촉즉발 · 필살 —— 짧고 고리 옆에 붙기 좋은 「운기」 로. 전장 메달 둘레에도 같은 고리 (_token · _medal)
	const CHARGE_WORD := "운기"
	const CHARGE_HOLD := 0.35      # 다 찬 뒤 머무는 시간 (전장 초)
	var charges := {}              # 부대 key -> {who, name, t0, wait, mine}
	var _charge_rows := 0          # 지금 보이는 줄 수 —— 안내문(ann)을 그 아래로 내린다

	func charge_start(key: String, who: String, nm: String, wait: float, mine: bool) -> void:
		charges[key] = {"who": who, "name": nm, "t0": view.clock, "wait": maxf(wait, 0.1), "mine": mine}

	func charge_end(key: String) -> void:
		charges.erase(key)

	## 차오른 비율 0~1. 모으는 중이 아니면 -1
	func charge_k(key: String) -> float:
		if not charges.has(key):
			return -1.0
		var c: Dictionary = charges[key]
		return clampf((view.clock - c.t0) / c.wait, 0.0, 1.0)

	func _draw_charges() -> void:
		var fb := DB.font_bold
		var y := 62.0
		_charge_rows = 0
		for key in charges.keys():
			var c: Dictionary = charges[key]
			var t: float = view.clock - c.t0
			if t > c.wait + CHARGE_HOLD:
				charges.erase(key)
				continue
			if (not c.mine and not view.direct) or _charge_rows >= 2:
				continue
			var u := clampf(t / c.wait, 0.0, 1.0)
			var a := clampf(t / 0.12, 0, 1) * clampf((c.wait + CHARGE_HOLD - t) / 0.25, 0, 1)
			var title := "『%s』" % c.name
			var tfs := 22
			while tfs > 14 and DB.title_font(tfs).get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, tfs).x > size.x - 140.0:
				tfs -= 1
			var tf := DB.title_font(tfs)      # 11/10 18 미만으로 줄면 굵은 고딕
			var tw := tf.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, tfs).x
			var R := 11.0
			var bw := DB.font_bold.get_string_size(CHARGE_WORD, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x + 12.0
			var total := R * 2.0 + 9.0 + tw + 9.0 + bw
			var x0 := (size.x - total) / 2.0
			var tx := x0 + R * 2.0 + 9.0
			var cy := y + 26.0
			# 받침 —— 옅은 먹. 적은 붉은 테가 깜빡인다 (방진!)
			var sb := StyleBoxFlat.new()
			sb.bg_color = Color(0.03, 0.03, 0.05, 0.55 * a)
			sb.set_corner_radius_all(8)
			if c.mine:
				sb.border_color = Color(MEDAL_TEAM.A, 0.35 * a)
				sb.set_border_width_all(1)
			else:
				var pulse := 0.5 + 0.5 * sin(view.clock * 12.0)
				sb.border_color = Color(Color(1.0, 0.35, 0.25).lerp(Color.WHITE, pulse * 0.4), a)
				sb.set_border_width_all(2)
			draw_style_box(sb, Rect2(x0 - 12.0, y, total + 24.0, 42.0))
			# 장수 이름 —— 작게, 기술명 위
			var who: String = c.who if c.mine else "적 · " + c.who
			draw_string_outline(fb, Vector2(tx, y + 12.0), who, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, 4, Color(0, 0, 0, 0.8 * a))
			draw_string(fb, Vector2(tx, y + 12.0), who, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color("#9cc8ff" if c.mine else "#ffb3a6", a))
			# 기술명 —— 붓글씨. 다 차면 금빛으로
			var tcol := Color("#eaf3ff") if c.mine else Color("#ffe0d8")
			if u >= 1.0:
				tcol = tcol.lerp(Color("#ffd257"), 0.6)
			draw_string_outline(tf, Vector2(tx, y + 35.0), title, HORIZONTAL_ALIGNMENT_LEFT, -1, tfs, 6, Color(0, 0, 0, 0.9 * a))
			draw_string(tf, Vector2(tx, y + 35.0), title, HORIZONTAL_ALIGNMENT_LEFT, -1, tfs, Color(tcol, a))
			# 고리 —— 금빛이 시계 방향으로 찬다. 안에 "기". 다 차면 번쩍
			var rc := Vector2(x0 + R, cy)
			draw_circle(rc, R + 3.5, Color(0, 0, 0, 0.5 * a))
			draw_arc(rc, R, 0.0, TAU, 40, Color(1, 1, 1, 0.18 * a), 3.0)
			if u > 0.0:
				var gc := Color("#ffd257") if u < 1.0 else Color("#ffd257").lerp(Color.WHITE, 0.5 + 0.5 * sin(view.clock * 25.0))
				draw_arc(rc, R, -PI / 2.0, -PI / 2.0 + TAU * u, 40, Color(gc, a), 3.5)
			if u >= 1.0:
				draw_circle(rc, R - 2.0, Color(1.0, 0.9, 0.5, 0.35 * a))
			draw_string(fb, Vector2(rc.x - R, cy + 4.0), "기",HORIZONTAL_ALIGNMENT_CENTER, R * 2.0, 11, Color("#ffe6a8", a))
			# 「운기」 낙관 —— 기술명 오른쪽, 진영색 바탕
			var bb := Rect2(Vector2(tx + tw + 9.0, cy - 9.0), Vector2(bw, 18.0))
			draw_rect(bb, Color(Color("#2f6fd0") if c.mine else Color("#c8463c"), 0.9 * a))
			draw_string(fb, bb.position + Vector2(0, 13.5), CHARGE_WORD, HORIZONTAL_ALIGNMENT_CENTER, bw, 11, Color(DB.PAL.paper, a))
			y += 46.0
			_charge_rows += 1

	## 강조 순위 —— 진영마다 그 전투에 나온 장수 가운데 등급(같으면 PV) 상위 둘만 1 · 2 (11/3 사용자: 등급마다 크게 하니
	## 고등급이 뭉치면 다 같이 커서 오히려 안 보였다 —— 상대적으로 높은 장수만 눈에 띄게). 나머지 0
	var _emph := {}

	func _rank_emph() -> void:
		_emph.clear()
		for cp in ["A", "B"]:
			var gs := []
			for k in view.field.squads:
				var q: Squad = view.field.squads[k]
				if q.camp == cp and q.tier >= 3:
					gs.append(q)
			gs.sort_custom(func(x, y):
				if x.tier != y.tier:
					return x.tier > y.tier
				return int(DB.C[x.cid].pv) > int(DB.C[y.cid].pv))
			for i in mini(2, gs.size()):
				_emph[gs[i].key] = i + 1

	## 메달 지름 —— 병졸 14 · 장수 22 · 강조 2등 26 · 1등 30
	func _medal_d(sq: Squad) -> float:
		if sq.tier <= 2:
			return 14.0
		return {1: 30.0, 2: 26.0}.get(_emph.get(sq.key, 0), 22.0)

	## 둥근 메달 —— 등급은 테 색으로, 크기 · 빛 · 장식은 강조 1 · 2등만. 고유기가 차면 순위와 상관없이 번쩍. 병졸은 병종 기호만
	func _medal(pc: Vector2, rr: float, sq: Squad, a: float, ult_ready: bool) -> void:
		var team: Color = War3D.TEAM[sq.camp]
		var tc: Color = DB.tier_color(sq.cid)
		var t := sq.tier
		var em: int = _emph.get(sq.key, 0)
		var clk: float = view.clock
		var tring: Color = MEDAL_TEAM[sq.camp]
		var fl: float = 1.35 if view.field.flat != null else 1.0      # 11/6 타입2는 메달이 작아 테 · 가시를 키운다
		if sq.camp == "B":      # 적 —— 둘레의 가시 넷 (색을 못 가려도 모양으로)
			_spikes(pc, rr + (2.0 if t <= 2 else 4.5 * fl), (3.5 if t <= 2 else 5.5) * fl, tring, a)
		var hl := highlight_k(sq.key)      # 11/6 #11 아래 프로필을 누른 부대 —— 흰 고리가 퍼진다
		if hl > 0.0:
			var ph := fposmod(clk * 1.6, 1.0)
			draw_arc(pc, rr + 6.0 + ph * 14.0, 0, TAU, 40, Color(1, 1, 1, hl * (1.0 - ph) * a), 2.5)
			draw_arc(pc, rr + 5.0, 0, TAU, 40, Color(1, 1, 0.85, 0.9 * hl * a), 2.0)
		if t <= 2:      # 병졸 —— 진영색 작은 원 + 병종 기호
			draw_circle(pc, rr + 2.5, Color(0, 0, 0, 0.5 * a))
			draw_circle(pc, rr + 1.8, Color(tring, a))
			draw_circle(pc, rr, Color(team.darkened(0.35), a))
			var ic: Texture2D = DB.ICON.get(DB.C[sq.cid].tag)
			if ic:
				var s2 := rr * 1.3
				draw_texture_rect(ic, Rect2(pc - Vector2(s2, s2) / 2.0, Vector2(s2, s2)), false, Color(DB.PAL.paper, 0.9 * a))
			draw_arc(pc, rr, 0, TAU, 24, Color(team.lightened(0.3), a), 1.2)
			_guard_mark(pc, rr, sq, a)
			return
		# 빛 —— 1등만 (신화는 더 강하게), 고유기가 찬 장수는 누구든 번쩍
		var glow := 0.0
		if em == 1:
			glow = 0.36 + 0.14 * sin(clk * 3.0) if t >= 8 else 0.24 + 0.1 * sin(clk * 2.4)
		if ult_ready:
			glow += 0.3 + 0.25 * sin(clk * 10.0)
		if glow > 0.0:
			for i in 3:
				draw_circle(pc, rr + 4.0 + i * 3.0, Color(tc, glow * a / (i + 1.5)))
		# 11/5 사용자: 메달만으로 피아식별 —— 바깥 굵은 테 = 진영색(아군 파랑 · 적 빨강), 그 안 가는 테 = 등급색, 적은 가시 넷.
		# (예전엔 바깥 테가 등급색이라 전설 빨강 · 초월 하늘색이 진영색과 섞였고, 진영색은 안쪽 0.6px 뿐이었다)
		var ring := 3.0 if em == 1 else (2.5 if em == 2 else 2.0)
		draw_circle(pc, rr + ring + 4.0 * fl, Color(0, 0, 0, 0.55 * a))
		draw_circle(pc, rr + ring + 3.2 * fl, Color(tring, a))                                    # 진영색 굵은 테
		draw_circle(pc, rr + ring, Color(Color("#ffd257") if t >= 8 else tc, a))            # 등급색 가는 테 (신화는 금)
		if em > 0:
			draw_arc(pc, rr + ring + 4.6, 0, TAU, 40, Color(tc.lightened(0.3), 0.8 * a), 1.0)      # 강조 —— 두 겹
		var ck := charge_k(sq.key)      # 11/7 기 모으는 중 —— 테 바깥에 금빛 고리가 찬다
		if ck >= 0.0:
			var cr := rr + ring + 4.0 * fl + 4.0
			draw_arc(pc, cr, 0.0, TAU, 40, Color(0, 0, 0, 0.45 * a), 4.0)
			if ck > 0.0:
				draw_arc(pc, cr, -PI / 2.0, -PI / 2.0 + TAU * ck, 40, Color("#ffd257", a), 2.5)
		draw_circle(pc, rr + 0.6, Color(0, 0, 0, 0.5 * a))
		Art.draw_face_circle(self, pc, rr, sq.cid)
		var top := pc + Vector2(0, -rr - ring - 4.5)
		if DB.is_kiin(sq.cid):
			_gem(top, 3.0, DB.KIIN_COL, a)          # 기인 표시는 늘 (작은 마름모)
		elif em == 1:
			_horn(top, 5.0, Color("#ffd257") if t >= 8 else tc, a)
			if t >= 8:      # 신화 —— 둘레를 도는 빛 조각
				for i in 3:
					var ang := clk * 1.6 + TAU * i / 3.0
					var q := pc + Vector2(cos(ang), sin(ang)) * (rr + ring + 3.0)
					draw_circle(q, 2.0, Color(1.0, 0.92, 0.6, 0.9 * a))
					draw_circle(q, 3.6, Color(1.0, 0.85, 0.4, 0.3 * a))
		elif em == 2:
			_horn(top, 4.0, tc, a)
		_guard_mark(pc, rr, sq, a)

	## 11/9 적 갑옷(방패) · 결계(소용돌이) 표지 —— 메달 오른쪽 아래. 깎인 동안(상태 cut_def · cut_res)은 붉은 테 + 금 간 선. 아군 · 막 없는 부대는 없다
	func _guard_mark(pc: Vector2, rr: float, sq: Squad, a: float) -> void:
		if sq.camp != "B" or not sq.alive:
			return
		var sh: Array = sq.row.get("sh", [0.0, 0.0])
		var ward: bool = float(sh[0]) <= 0.0 and float(sh[1]) > 0.0
		if float(sh[0]) <= 0.0 and not ward:
			return
		var broken: bool = sq.statuses.has("cut_res" if ward else "cut_def")
		var s := maxf(4.0, rr * 0.42)
		var c := pc + Vector2(rr * 0.78, rr * 0.78)
		var base := Color("#6fa8ff") if ward else Color("#d8c27a")
		var rim := Color("#ff5a4a") if broken else base
		draw_circle(c, s + 2.0, Color(0, 0, 0, 0.6 * a))
		if ward:
			draw_circle(c, s + 1.0, Color(0.05, 0.08, 0.16, 0.92 * a))
			for i in 2:      # 소용돌이 —— 반지름이 커지는 두 호
				var r0 := s * (0.35 + 0.35 * i)
				draw_arc(c, r0, i * PI, i * PI + PI * 1.5, 12, Color(rim, a), 1.4)
		else:
			var pts := PackedVector2Array([c + Vector2(-s, -s * 0.85), c + Vector2(s, -s * 0.85), c + Vector2(s, s * 0.05), c + Vector2(0, s * 1.1), c + Vector2(-s, s * 0.05)])
			draw_colored_polygon(pts, Color(0.12, 0.1, 0.06, 0.92 * a))
			pts.append(pts[0])
			draw_polyline(pts, Color(rim, a), 1.4)
		if broken:      # 금 —— 대각선 지그재그
			draw_polyline(PackedVector2Array([c + Vector2(-s * 0.2, -s * 0.9), c + Vector2(s * 0.15, -s * 0.2), c + Vector2(-s * 0.15, s * 0.1), c + Vector2(s * 0.2, s * 0.9)]), Color(1, 0.9, 0.85, a), 1.3)

	## 화면 밖(카메라 뒤 −99999 등) 좌표면 다각형 분할이 실패해 오류가 쏟아진다 (11/3) —— 그리지 않는다
	func _on_screen(p: Vector2) -> bool:
		return absf(p.x) < 8000.0 and absf(p.y) < 8000.0

	## 메달 진영색 —— 3D 진영색(TEAM)보다 밝게: 작은 테에서도 파랑 · 빨강이 또렷하게
	const MEDAL_TEAM := {"A": Color("#3d8bff"), "B": Color("#ff4a3d")}

	## 11/6 #11 아래 프로필을 누른 부대 강조 —— 2초 동안 1 → 0
	var _hl := {}
	func highlight(key: String, dur := 2.0) -> void:
		_hl[key] = view.clock + dur
	func highlight_k(key: String) -> float:
		if not _hl.has(key):
			return 0.0
		var left: float = float(_hl[key]) - view.clock
		if left <= 0.0:
			_hl.erase(key)
			return 0.0
		return clampf(left / 0.6, 0.0, 1.0)

	## 적 메달 가시 —— 비스듬한 네 방향 (위 · 아래의 등급 장식과 겹치지 않게)
	func _spikes(pc: Vector2, r0: float, len_: float, col: Color, a: float) -> void:
		if not _on_screen(pc):
			return
		for i in 4:
			var ang := PI / 4.0 + i * PI / 2.0
			var d := Vector2(cos(ang), sin(ang))
			var n := Vector2(-d.y, d.x)
			var base := pc + d * (r0 - 1.0)
			var pts := PackedVector2Array([base + n * 3.2, pc + d * (r0 + len_), base - n * 3.2])
			draw_colored_polygon(pts, Color(col, a))
			draw_polyline(pts, Color(0, 0, 0, 0.55 * a), 1.0)

	func _gem(p: Vector2, s: float, col: Color, a: float) -> void:
		if not _on_screen(p) or s < 0.5:
			return
		draw_colored_polygon(PackedVector2Array([p + Vector2(0, -s), p + Vector2(s, 0), p + Vector2(0, s), p + Vector2(-s, 0)]), Color(col, a))
		draw_polyline(PackedVector2Array([p + Vector2(0, -s), p + Vector2(s, 0), p + Vector2(0, s), p + Vector2(-s, 0), p + Vector2(0, -s)]), Color(0, 0, 0, 0.6 * a), 1.0)

	func _horn(p: Vector2, s: float, col: Color, a: float) -> void:
		if not _on_screen(p) or s < 0.5:
			return
		var pts := PackedVector2Array([p + Vector2(-s, s * 0.4), p + Vector2(-s * 0.45, -s * 0.5), p + Vector2(0, s * 0.1), p + Vector2(s * 0.45, -s * 0.5), p + Vector2(s, s * 0.4)])
		draw_colored_polygon(pts, Color(col, a))
		draw_polyline(pts + PackedVector2Array([pts[0]]), Color(0, 0, 0, 0.6 * a), 1.0)

	## 점묘 전장의 장수 토큰 —— 둥근 초상 + 진영색 테 + 병력 숫자 (블라인드삼국식)
	var _tok_sb: StyleBoxFlat = null
	var _medal_cache := {}

	## 큰 그림을 작게 줄인다 —— 한 번에 쌍선형으로 줄이면 픽셀을 건너뛰어 계단 · 지글거림이 생긴다 (11/8 사용자: 메달 밉맵 깨짐).
	## 절반씩 두 배 가까이까지 줄인 뒤 란초스로 마무리 (구울 때 한 번뿐이라 비용 · 메모리 증가 없음)
	static func _shrink(img: Image, n: int) -> void:
		while img.get_width() >= n * 4:
			img.resize(img.get_width() / 2, img.get_height() / 2, Image.INTERPOLATE_BILINEAR)
		img.resize(n, n, Image.INTERPOLATE_LANCZOS)

	## 11/9 사용자: 전투 메달이 또 뿌옇다 (세 번째) —— 원인: 메달을 논리 px(r=15 → 48px)로 구워 두고 그대로 찍었는데, 휴대폰은 논리 폭 400 을
	## 실제 화면 720~1080px 로 늘려 그린다(stretch canvas_items, 배율 1.8~2.7) → 구운 그림이 업스케일로 뭉개졌다 (글씨 · 호 · 다각형은 화면 해상도로 그려져 또렷해서 메달만 도드라졌다).
	## 3D · 수묵 전장은 메달을 `_medal`(벡터 + 밉맵 얼굴)로 그려 멀쩡했는데, 3D 를 숨기고 타입2 가 기본이 되면서(Settings.SHOW_3D) 구운 길이 드러났다.
	## 규칙: 구운 그림은 **화면 픽셀 크기**(논리 크기 × 화면 배율)로 굽고, 찍을 때는 논리 크기 = 굽는 크기 ÷ 배율 + 화면 픽셀에 맞춰 놓는다 (1:1). 화면 배율이 바뀌면(창 크기 · 회전) 다시 굽는다.
	var _bake_s := 1.0

	## 지금 화면 배율 —— 논리 좌표 1 이 화면 몇 px 인가. 0.25 단위로 맞추고 0.5 ~ 3 안 (PC 가로 창은 1 미만 —— 줄여 그릴 때도 1:1 로 굽는다)
	func _px_scale() -> float:
		var sc := get_viewport().get_final_transform().get_scale().x
		return clampf(snappedf(sc, 0.25), 0.5, 3.0)

	## 메달 그림 두 장 —— [틀(검은 테 + 진영 고리 + 등급 고리 + 아군▲ · 적▼, 가운데는 비어 있다), 얼굴(원)]. 틀을 먼저 찍고 얼굴을 그 위에 찍는다.
	## 틀은 (진영 · 등급색 · 크기)마다, 얼굴은 장수마다 한 번씩만 굽는다 —— 화면 배율로 굽느라 커진 비용(한 장 약 8ms → 25장이면 첫 프레임이 멈춘다)을 나눠 줄인다.
	## 얼굴은 안쪽 가장자리 반 픽셀을 틀의 안쪽 가장자리 부드러운 구멍이 덮는다 (한 장으로 굽던 때와 같은 모습). S = 화면 배율(위 11/9)
	## 한 프레임에 굽는 시간 상한(마이크로초) —— 넘으면 아직 안 구워진 메달은 다음 프레임에 (처음 한 번 몇 프레임 늦게 뜰 뿐 멈추지 않는다). 구운 그림은 전투를 넘어 쓴다
	const BAKE_US := 6000
	var _bake_frame := -1
	var _bake_us := 0

	func _frame_key(sq: Squad, r: float, S: float) -> String:
		return "F%s%s%s@%s" % [sq.camp, DB.tier_color(sq.cid).to_html(false), str(r), str(S)]

	func _face_key(sq: Squad, r: float, S: float) -> String:
		return "f%s%s%s@%s%s" % [sq.camp, sq.cid, str(r), str(S), sq.tag if sq.tier <= 2 else ""]      # 바탕이 진영색이라 진영도 키에 (11/9)

	func _medal_tex(sq: Squad, r: float, S := 1.0) -> Array:
		var fid := Engine.get_process_frames()
		if fid != _bake_frame:
			_bake_frame = fid
			_bake_us = 0
		if _bake_us > BAKE_US and not (_medal_cache.has(_frame_key(sq, r, S)) and _medal_cache.has(_face_key(sq, r, S))):
			return []
		var t0 := Time.get_ticks_usec()
		var out := [_medal_frame(sq, r, S), _medal_face(sq, r, S)]
		_bake_us += Time.get_ticks_usec() - t0
		return out

	func _medal_frame(sq: Squad, r: float, S: float) -> Texture2D:
		var tcol: Color = DB.tier_color(sq.cid)
		var key := _frame_key(sq, r, S)
		if _medal_cache.has(key):
			return _medal_cache[key]
		var rp := r * S      # 얼굴 반지름 (화면 px) —— 아래 거리 · 두께는 모두 화면 px
		var n := int(ceil((r + 9.0) * S * 2.0))
		n += n % 2      # 가운데가 화면 픽셀 모서리에 오게 짝수
		var R := n / 2.0
		var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
		img.fill(Color(0, 0, 0, 0))
		var ring: Color = TOK_TEAM[sq.camp]
		var c := Vector2(R, R)
		var tri := PackedVector2Array([c + Vector2(-5, -rp - 3 * S) * Vector2(S, 1), c + Vector2(5, -rp - 3 * S) * Vector2(S, 1), c + Vector2(0, -rp - 9 * S)]) if sq.camp == "A" else PackedVector2Array([c + Vector2(-5, rp + 3 * S) * Vector2(S, 1), c + Vector2(5, rp + 3 * S) * Vector2(S, 1), c + Vector2(0, rp + 9 * S)])
		var ty0 := minf(tri[0].y, tri[2].y) - 1.0
		var ty1 := maxf(tri[0].y, tri[2].y) + 1.0
		var ro := rp + 5.5 * S      # 가장 바깥(검은 테) 반지름
		for y in n:
			var dy := y + 0.5 - R
			var in_ty := y + 0.5 >= ty0 and y + 0.5 <= ty1
			if absf(dy) > ro and not in_ty:
				continue
			var hw := sqrt(maxf(ro * ro - dy * dy, 0.0))      # 이 줄에서 바깥 원이 차지하는 가로 반폭
			if in_ty:
				hw = maxf(hw, 5.0 * S + 1.0)
			var x0 := maxi(0, int(floor(R - hw)) - 1)
			var x1 := mini(n - 1, int(ceil(R + hw)) + 1)
			for x in range(x0, x1 + 1):
				var q := Vector2(x + 0.5, y + 0.5)
				var d := q.distance_to(c)
				var in_tri := in_ty and Geometry2D.is_point_in_polygon(q, tri)
				if d > ro and not in_tri:
					continue
				if d < rp - 1.0 and not in_tri:      # 얼굴이 덮는 안쪽 —— 비워 둔다
					continue
				var col := Color(0, 0, 0, 0)
				if d <= rp + 5.5 * S:
					col = Color(0, 0, 0, 0.7 * clampf(rp + 5.5 * S - d, 0, 1))
				if d <= rp + 4.5 * S:
					col = col.blend(Color(ring, clampf(rp + 4.5 * S - d, 0, 1)))
				if d <= rp + 1.7 * S:
					col = col.blend(Color(tcol, clampf(rp + 1.7 * S - d, 0, 1)))
				if d < rp + 0.5:      # 안쪽 가장자리 —— 얼굴과 부드럽게 이어지는 반 픽셀
					col.a *= clampf(d - (rp - 0.5), 0.0, 1.0)
				if in_tri:
					col = col.blend(ring)
				if col.a > 0.0:
					img.set_pixel(x, y, col)
		var t := ImageTexture.create_from_image(img)
		_medal_cache[key] = t
		return t

	## 둥근 얼굴 —— 장수 얼굴(없으면 병종 기호)을 원 모양으로. 크기 (2 · 올림(rp) + 2) 짝수, 가운데가 틀과 같은 자리
	func _medal_face(sq: Squad, r: float, S: float) -> Texture2D:
		var key := _face_key(sq, r, S)
		if _medal_cache.has(key):
			return _medal_cache[key]
		var rp := r * S
		var m := 2 * int(ceil(rp)) + 2
		var half := m / 2.0
		var k: String = sq.cid
		var ft := DB.face_tex(k)
		var tex: Texture2D = ft if ft else DB.portrait(k)
		var crop: Image = null
		if tex != null:
			var src: Image = tex.get_image()
			if src != null:
				if src.is_compressed():
					src.decompress()
				var face := Rect2(Vector2.ZERO, tex.get_size()) if ft else DB.portrait_face(k)
				var fr := Rect2i(face).intersection(Rect2i(Vector2i.ZERO, src.get_size()))
				if fr.size.x > 0 and fr.size.y > 0:
					crop = src.get_region(fr)
					crop.convert(Image.FORMAT_RGBA8)
					_shrink(crop, int(round(rp * 2.0)))
		var disc := Image.create(m, m, false, Image.FORMAT_RGBA8)
		if crop != null:
			disc.fill(TOK_BG[sq.camp])
			var o := Vector2i(int(round(half - crop.get_width() / 2.0)), int(round(half - crop.get_height() / 2.0)))
			disc.blend_rect(crop, Rect2i(Vector2i.ZERO, crop.get_size()), o)
		else:
			disc.fill(TOK_BG[sq.camp].lightened(0.08))
			if DB.ICON.get(sq.tag) != null:
				var ikey := "i%s@%s" % [sq.tag, str(rp)]      # 병종 기호는 같은 병종끼리 한 번만 줄이고 색을 입힌다
				if not _medal_cache.has(ikey):
					var ic0: Image = (DB.ICON[sq.tag] as Texture2D).get_image()
					if ic0.is_compressed():
						ic0.decompress()
					ic0.convert(Image.FORMAT_RGBA8)
					_shrink(ic0, int(round(rp * 1.1)))
					for iy in ic0.get_height():
						for ix in ic0.get_width():
							ic0.set_pixel(ix, iy, Color(DB.PAL.paper, ic0.get_pixel(ix, iy).a * 0.85))
					_medal_cache[ikey] = ic0
				var ic: Image = _medal_cache[ikey]
				disc.blend_rect(ic, Rect2i(Vector2i.ZERO, ic.get_size()), Vector2i(int(round(half - ic.get_width() / 2.0)), int(round(half - ic.get_height() / 2.0))))
		var out := Image.create(m, m, false, Image.FORMAT_RGBA8)
		out.fill(Color(0, 0, 0, 0))
		var _mm := _medal_mask(m, rp)
		out.blit_rect_mask(disc, _medal_mask(m, rp), Rect2i(0, 0, m, m), Vector2i.ZERO)
		var t := ImageTexture.create_from_image(out)
		_medal_cache[key] = t
		return t

	## 얼굴 원 모양 마스크 (반지름 rp + 0.5 안쪽만) —— 가장자리는 틀의 부드러운 구멍이 덮는다
	func _medal_mask(m: int, rp: float) -> Image:
		var key := "m%d_%s" % [m, str(rp)]
		if _medal_cache.has(key):
			return _medal_cache[key]
		var mk := Image.create(m, m, false, Image.FORMAT_RGBA8)
		mk.fill(Color(0, 0, 0, 0))
		var h := m / 2.0
		for y in m:
			for x in m:
				if Vector2(x + 0.5 - h, y + 0.5 - h).length() <= rp + 0.5:
					mk.set_pixel(x, y, Color(1, 1, 1, 1))
		_medal_cache[key] = mk
		return mk
	const TOK_TEAM := {"A": Color("#2f86ff"), "B": Color("#ff3b30")}
	## 타입2 메달 얼굴 반지름(논리 px) —— 등급마다: 병졸 11 · 일반 12.5 · 희귀 13.5 · 영웅 14.5 · 전설 16 · 기인 17.5 · 신화 19 (11/9 사용자)
	const TOK_R := {1: 11.0, 2: 11.0, 3: 12.5, 4: 13.5, 5: 14.5, 6: 16.0, 7: 17.5, 8: 19.0}
	## 메달 얼굴 뒤 바탕 —— 진영색을 어둡게 (11/9 사용자: 아군 · 적군 바탕색 구분). 그림이 비치는 초상 · 병종 기호 뒤에서도 피아가 보인다
	const TOK_BG := {"A": Color("#17315e"), "B": Color("#5a1713")}
	func _token(sq: Squad, p: Vector2) -> void:
		if sq.state == "gone":
			return
		var a: float = sq.fade
		var r: float = TOK_R.get(clampi(sq.tier, 1, 8), 15.0)      # 11/9 사용자: 메달 크기가 등급을 따르지 않았다 (7등급 전까지 전부 15) —— 등급마다 한 단씩
		# 11/6 사용자: 메달 피아식별 —— 바깥 굵은 진영 고리(아군 파랑 · 적 빨강, 채도 높게) + 안쪽 가는 등급 고리 + 검은 테
		var ring: Color = TOK_TEAM[sq.camp]
		if sq.hurt > 0.05:
			ring = ring.lerp(Color(1, 1, 1), sq.hurt * 0.6)
		# 11/6 목표(휴대폰 대군): 메달은 전투 시작 때 그림 한 장으로 구워 두고 매 프레임 한 번만 찍는다 (원 · 고리 · 얼굴 다각형 · 뿔을 매번 그리던 것이 프레임당 약 2ms)
		var S := _px_scale()      # 11/9 화면 배율에 맞춰 굽고 1:1 로 찍는다 (위 _bake_s 설명)
		if not is_equal_approx(S, _bake_s):
			_medal_cache.clear()
			_bake_s = S
		var mts := _medal_tex(sq, r, S)
		for mt in mts:      # 틀 → 얼굴 (둘 다 가운데가 p)
			var msz := Vector2(mt.get_size()) / S      # 논리 크기 = 구운 화면 px ÷ 배율
			var mpos := ((p * S - Vector2(mt.get_size()) * 0.5).round()) / S      # 화면 픽셀 칸에 맞춘다 —— 반 픽셀 걸치면 또 번진다
			draw_texture_rect(mt, Rect2(mpos, msz), false, Color(1, 1, 1, a))
		var ck := charge_k(sq.key)      # 11/7 기 모으는 중 —— 메달 바깥에 금빛 고리가 찬다 (위 HUD 고리와 같은 박자)
		if ck >= 0.0:
			draw_arc(p, r + 10.0, 0.0, TAU, 36, Color(0, 0, 0, 0.45 * a), 4.0)
			if ck > 0.0:
				draw_arc(p, r + 10.0, -PI / 2.0, -PI / 2.0 + TAU * ck, 36, Color("#ffd257", a), 2.5)
		if sq.hurt > 0.05:      # 맞을 때만 고리를 흰빛으로 덧그린다
			draw_arc(p, r + 2.6, 0, TAU, 24, Color(1, 1, 1, sq.hurt * 0.6 * a), 3.0)
		_guard_mark(p, r, sq, a)      # 11/9 적 갑옷 · 결계 표지
		if not sq.alive:
			draw_circle(p, r, Color(0, 0, 0, 0.6))
		# 병력 —— 5.3K 처럼
		var n: float = sq.troops
		var txt := ("%.1fK" % (n / 1000.0)) if n >= 1000 else str(roundi(n))
		var fb: Font = DB.font_bold
		var tw := fb.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x + 10
		var br := Rect2(p + Vector2(-tw / 2, r + (9 if sq.camp == "B" else 5)), Vector2(tw, 14))
		if _tok_sb == null:      # 11/6 메달마다 매 프레임 StyleBoxFlat 을 새로 만들었다 —— 하나를 고쳐 쓴다
			_tok_sb = StyleBoxFlat.new()
			_tok_sb.set_border_width_all(1)
			_tok_sb.set_corner_radius_all(3)
		_tok_sb.bg_color = Color(ring.darkened(0.62), 0.92 * a)      # 병력 띠도 진영색 바탕
		_tok_sb.border_color = Color(ring, 0.9 * a)
		draw_style_box(_tok_sb, br)
		draw_string(fb, br.position + Vector2(0, 11), txt, HORIZONTAL_ALIGNMENT_CENTER, tw, 10, Color(0.92, 0.95, 1.0, a))
		var since: float = view.clock - sq.act_t
		if since < CombatFx.ATTACK_HOLD and sq.alive:
			_act_icon(p + Vector2(r + 4, -r + 2), sq.act_kind, a)

	## 2D 전장 메달 자리 —— 가까이 붙은 메달끼리 살짝 밀어낸다 (11/6 점검: 근접전에서 메달이 겹쳐 얼굴 · 병력이 가려졌다).
	## 화면에만 적용, 최대 22px, 부드럽게 따라간다 (튀지 않게)
	var _tok_off := {}
	const TOK_GAP := 38.0
	func _flat_token_pos(tags: Array) -> Dictionary:
		var base := {}
		var want := {}
		var keys := []
		for t in tags:
			var sq: Squad = t[1]
			var p: Vector2 = view.field.to_screen(sq.pos, 0.0)
			base[sq.key] = p
			want[sq.key] = p
			keys.append(sq.key)
		for _it in 4:
			for i in keys.size():
				for j in range(i + 1, keys.size()):
					var a: Vector2 = want[keys[i]]
					var b: Vector2 = want[keys[j]]
					var d := b - a
					var l := d.length()
					if l < TOK_GAP:
						var dir := d / l if l > 0.01 else Vector2(1, 0).rotated(i * 1.3)
						var push := dir * (TOK_GAP - l) * 0.5
						want[keys[i]] = a - push
						want[keys[j]] = b + push
		var out := {}
		for k in keys:
			var off: Vector2 = (want[k] - base[k]).limit_length(22.0)
			_tok_off[k] = (_tok_off.get(k, Vector2.ZERO) as Vector2).lerp(off, 0.15)
			out[k] = base[k] + _tok_off[k]
		return out

	## 2D 전장에서 화면 위치 sp 에 있는 메달(부대) —— 그리는 자리(밀어낸 _tok_off 까지)와 같은 곳에서 고른다 (11/9 꾹 누르기 → 전투장수창).
	## 선택 반경은 메달 반지름 + MEDAL_PICK_PAD, 겹치면 더 가까운 쪽(같으면 화면 아래 = 위에 그려진 쪽). 빈 곳이면 null
	const MEDAL_PICK_PAD := 13.0
	func medal_at(sp: Vector2) -> Squad:
		var best: Squad = null
		var bd := INF
		var by := -INF
		for sq in view.field.order:
			if sq.state == "gone" or sq.fade < 0.2:
				continue
			var p: Vector2 = view.field.to_screen(sq.pos, 0.0) + (_tok_off.get(sq.key, Vector2.ZERO) as Vector2)
			var d := p.distance_to(sp)
			if d > (15.0 if sq.tier < 7 else 17.0) + MEDAL_PICK_PAD:
				continue
			if d < bd - 0.5 or (absf(d - bd) <= 0.5 and p.y > by):
				bd = d
				by = p.y
				best = sq
		return best

	## 2D 전장 글씨 자리 —— 처음 뜰 때 이미 떠 있는 글씨와 겹치면 위로 한 칸씩 (정해진 뒤에는 그대로)
	func _settle_dy(f: Dictionary, p: Vector2, w: float, h: float) -> float:
		if f.has("dy"):
			return f.dy
		var dy := 0.0
		for _k in 5:
			var r := Rect2(p + Vector2(-w / 2, -h + dy), Vector2(w, h))
			var hit := false
			for o in floats:
				if not is_same(o, f) and o.has("rect") and (o.rect as Rect2).intersects(r):
					hit = true
					break
			if not hit:
				break
			dy -= h * 0.9
		f.dy = dy
		return dy

	## 행동 아이콘 —— 주황 동그라미 위에 흰 그림
	func _act_icon(c: Vector2, kind: String, a: float) -> void:
		var bg: Color = {"melee": Color("#e0662f"), "shoot": Color("#d8a531"), "cast": Color("#8f63d1")}.get(kind, Color("#888"))
		draw_set_transform(c, 0.0, Vector2(0.72, 0.72))       # 이름표에 맞춰 작게
		c = Vector2.ZERO
		draw_circle(c, 8.5, Color(0, 0, 0, 0.6 * a))
		draw_circle(c, 7.5, Color(bg, a))
		var wc := Color(1, 1, 1, a)
		match kind:
			"melee":       # 엇갈린 두 칼
				draw_line(c + Vector2(-4.5, 4.5), c + Vector2(4.5, -4.5), wc, 1.8)
				draw_line(c + Vector2(4.5, 4.5), c + Vector2(-4.5, -4.5), wc, 1.8)
				draw_line(c + Vector2(-5.5, 1.5), c + Vector2(-1.5, 5.5), wc, 1.4)
				draw_line(c + Vector2(5.5, 1.5), c + Vector2(1.5, 5.5), wc, 1.4)
			"shoot":       # 활과 화살
				draw_arc(c + Vector2(-2.5, 0), 5.0, -1.2, 1.2, 8, wc, 1.5)
				draw_line(c + Vector2(-0.5, -4.7), c + Vector2(-0.5, 4.7), wc, 0.8)
				draw_line(c + Vector2(-3.0, 0), c + Vector2(5.0, 0), wc, 1.4)
				draw_line(c + Vector2(5.0, 0), c + Vector2(2.5, -2.0), wc, 1.4)
				draw_line(c + Vector2(5.0, 0), c + Vector2(2.5, 2.0), wc, 1.4)
			_:             # 별
				var pts := PackedVector2Array()
				for i in 10:
					var r := 5.0 if i % 2 == 0 else 2.2
					var t := -PI / 2 + i * PI / 5
					pts.append(c + Vector2(cos(t), sin(t)) * r)
				if _on_screen(c):
					draw_colored_polygon(pts, wc)
		draw_set_transform(Vector2.ZERO)

	func _draw_all() -> void:
		var fb := DB.font_body
		var fd := DB.font_display
		# 부대 머리표 —— 진영색 알약 이름표 + 병력 막대(+ 사기·고유기 가는 줄). 아래쪽(가까운) 부대부터 놓고,
		# 겹치면 한 번 비켜 보고 그래도 겹치면 이름을 빼고 막대만 남긴다.
		var tags := []
		for sq in view.field.order:
			if sq.state != "gone":
				var sp := _to_screen(sq.pos, 5.0)
				if sp.x > -9999 and view.field.label_alpha(sq.pos) > 0.02:
					tags.append([sp, sq])
		if view.field.flat != null:      # 11/6 내려다보는 지도: 화면 아래(가까운) 부대가 위에 오도록 —— 위에서부터 그린다
			tags.sort_custom(func(x, y): return x[0].y < y[0].y)
		else:
			tags.sort_custom(func(x, y): return x[0].y > y[0].y)
		var placed: Array[Rect2] = []
		var fbo: Font = DB.font_bold
		var tok_pos := {}
		_rank_emph()
		for t in tags:
			var p: Vector2 = t[0]
			var sq: Squad = t[1]
			if view.field.flat != null:
				if tok_pos.is_empty():
					tok_pos = _flat_token_pos(tags)
				_token(sq, tok_pos.get(sq.key, view.field.to_screen(sq.pos, 0.0)))
				continue
			var a: float = sq.fade * view.field.label_alpha(sq.pos)
			var myth: bool = sq.tier >= 8
			var art := true      # 11/3 모든 부대에 둥근 메달 —— 장수는 얼굴, 병졸은 병종 기호 (작게)
			var team: Color = War3D.TEAM[sq.camp]
			var nm: String = DB.person(sq.cid) if sq.tier > 2 else sq.row.name
			# 10/31 사용자: 이름표를 줄인다 —— 글씨 9 · 알약 높이 13 · 초상 16 (신화 19)
			var fs := 9
			var nw := fbo.get_string_size(nm, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			var w := clampf(nw + 16, 34, 58)
			var ps := _medal_d(sq) + 2.0      # 11/3 사용자: 등급마다 크기 · 테 · 빛 차등 (_medal_d · _medal)
			var r := Rect2(p - Vector2(w / 2, 17), Vector2(w, 22))
			# 10/31 사용자: 평소에는 작은 초상 + 병력 막대만. 이름 · 사기 · 게이지 · 상태는 따라가는(꾹 누른) 부대와 고유기가 찬 부대만
			var lvq := view.unit_live(sq.key)
			var detail: bool = sq == view.field.follow or (sq.tier >= 6 and lvq[1] > 0 and lvq[0] >= 100)
			if not detail:
				w = 30.0
				ps = _medal_d(sq)
				r = Rect2(p - Vector2(w / 2, 4), Vector2(w, 9))
			if art:
				r = Rect2(r.position - Vector2(ps + 3, 0), r.size + Vector2(ps + 3, 0))     # 초상 자리까지 겹침 판정
			var full := detail
			for i in (3 if detail else 0):
				var hit := false
				for q in placed:
					if q.intersects(r):
						hit = true
						break
				if not hit:
					break
				if i == 0:
					r.position.y -= 11
				else:
					full = false          # 비켜도 겹친다 —— 막대만
					r = Rect2(p - Vector2(w / 2, 3), Vector2(w, 7))
			placed.append(r)
			if art:
				r = Rect2(r.position + Vector2(ps + 3, 0), r.size - Vector2(ps + 3, 0))    # 이름표 · 막대는 초상 오른쪽에
			var bar_y := r.position.y + (15.0 if full else 0.0)
			if full:
				# 알약 이름표 —— 어두운 바탕, 왼쪽에 진영색 점, 등급색 이름
				var pill := Rect2(r.position.x, r.position.y, w, 13)
				var sb := StyleBoxFlat.new()
				sb.bg_color = Color(0.04, 0.05, 0.09, 0.72 * a)
				sb.border_color = Color(DB.tier_color(sq.cid), 0.8 * a) if sq.tier >= 5 else Color(team, 0.5 * a)
				sb.set_border_width_all(1)
				sb.set_corner_radius_all(7)
				draw_style_box(sb, pill)
				draw_circle(pill.position + Vector2(6, 6.5), 2.4, Color(team.lightened(0.25), a))
				var nc: Color = DB.tier_color(sq.cid).lightened(0.35) if sq.tier >= 3 else Color(0.92, 0.9, 0.85)
				draw_string(fbo, pill.position + Vector2(10, 10), nm, HORIZONTAL_ALIGNMENT_CENTER, w - 13, fs, Color(nc, a))
				# 지금 하는 일 —— 친 뒤 잠깐 이름표 오른쪽 끝에 칼(근접) · 활(사격) · 별(책략)
				var since: float = view.clock - sq.act_t
				if since < CombatFx.ATTACK_HOLD and sq.alive:
					_act_icon(pill.position + Vector2(w + 7, 6.5), sq.act_kind, a * (1.0 - since / CombatFx.ATTACK_HOLD * 0.6))
			# 11/4 저녁 사용자: 전장에는 메달 초상만 —— 병력 · 사기 · 고유기 막대는 뜻이 불분명해 그리지 않는다 (아래 장수 칸에 있다).
			# br 은 행동 아이콘 · 상태 배지 자리 기준으로만 쓴다
			var br := Rect2(r.position.x + 3, bar_y, w - 6, 3)
			if not full and sq.alive and view.clock - sq.act_t < CombatFx.ATTACK_HOLD:
				_act_icon(Vector2(br.position.x + 6, br.position.y + 1.5), sq.act_kind, a * (1.0 - (view.clock - sq.act_t) / CombatFx.ATTACK_HOLD * 0.6))
			var x := br.position.x + (br.size.x + 5 if full else 14.0)
			# 상태 —— 색 동그라미에 첫 글자 (방 · 감 · 화 …)
			for st in (sq.statuses.slice(0, 2) if full else []):          # 상태는 둘까지만, 자세히 볼 때만 (10/31)
				var sd: Dictionary = DB.D.STATUS[st]
				var sc := Vector2(x + 4, br.position.y + 2)
				draw_circle(sc, 4.5, Color(0, 0, 0, 0.7 * a))
				draw_circle(sc, 3.8, Color(sd.c, a))
				draw_string(DB.font_bold, sc + Vector2(-5, 2.6), sd.n.left(1), HORIZONTAL_ALIGNMENT_CENTER, 10, 6, Color(0.08, 0.06, 0.04, a))
				x += 9
			# 초상 —— 이름표 왼쪽. 테두리는 등급색 (신화는 조금 크게)
			if art and a > 0.5:
				var pr := Rect2(r.position + Vector2(-ps - 3, (11.0 if full else 1.5) - ps * 0.5), Vector2(ps, ps))
				var pc := pr.get_center()
				_medal(pc, ps * 0.5, sq, a, lvq[1] > 0 and lvq[0] >= 100)
				if not sq.alive:
					draw_circle(pc, ps * 0.5, Color(0, 0, 0, 0.6))
		# 떠오르는 글씨
		var keep := []
		for f in floats:
			var life := 1.6 if f.get("crit", false) else 1.3
			var u: float = (view.clock - f.t0) / life
			if u >= 1.0:
				continue
			keep.append(f)
			var col: Color = f.col
			col.a = 1.0 - maxf(0, u - 0.55) / 0.45
			if f.get("num", false):
				_draw_number(f, u, col)
				continue
			var p := _to_screen(f.p, 6.5) + Vector2(0, -20 - f.n * 16 - u * 26)
			if view.field.flat != null:      # 2D 전장 —— 메달 밀어낸 만큼 따라가고, 겹치면 위로
				p += _tok_off.get(f.key, Vector2.ZERO)
				var tw: float = fd.get_string_size(f.text, HORIZONTAL_ALIGNMENT_LEFT, -1, f.fs).x + 6.0
				p.y += _settle_dy(f, p + Vector2(0, u * 26), tw, f.fs * 1.2)
				f.rect = Rect2(p + Vector2(-tw / 2, -f.fs * 1.2), Vector2(tw, f.fs * 1.2))
			draw_string_outline(fd, p - Vector2(80, -2), f.text, HORIZONTAL_ALIGNMENT_CENTER, 160, f.fs, 10, Color(0, 0, 0, col.a * 0.35))
			draw_string_outline(fd, p - Vector2(80, 0), f.text, HORIZONTAL_ALIGNMENT_CENTER, 160, f.fs, 6, Color(0, 0, 0, col.a))
			draw_string(fd, p - Vector2(80, 0), f.text, HORIZONTAL_ALIGNMENT_CENTER, 160, f.fs, col)
		floats = keep
		_draw_skill_banners()
		if _flash_t < 0.35:
			var fa := (1.0 - _flash_t / 0.35)
			draw_rect(Rect2(Vector2.ZERO, size), Color(_flash.lerp(Color.WHITE, 0.55 * _flash_k), 0.55 * fa * fa * _flash_k))
		if Settings.perf_hud:      # 11/6 휴대폰 실측용 성능 표시
			var men := 0
			for q in view.field.order:
				men += q.soldiers.size()
			var t2 = view.field.flat
			var figs: int = (int(t2.drawn_figs) * (1 if t2.gpu_count > 0 else Type2View.PACK) + int(t2.gpu_count)) if t2 != null and t2.get("drawn_figs") != null else men
			var lv: int = int(t2.load_lv) if t2 != null and t2.get("load_lv") != null else 0
			var pt := "fps %d · 계산 %d · 보이는 %d · 조절 %d" % [Engine.get_frames_per_second(), men, figs, lv]
			draw_string_outline(DB.font_bold, Vector2(8, 66), pt, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, 4, Color(0, 0, 0, 0.9))
			draw_string(DB.font_bold, Vector2(8, 66), pt, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("#9fe8b8"))
		# 위쪽 —— 시계와 세력 균형
		var tA := 0.0
		var tB := 0.0
		for sq in view.field.order:
			if sq.alive:
				if sq.camp == "A": tA += sq.troops
				else: tB += sq.troops
		var bw := clampf(size.x - 190, 120, 420)
		var bx := (size.x - bw) / 2
		var ratio := 0.5 if tA + tB <= 0 else tA / (tA + tB)
		draw_rect(Rect2(bx - 2, 12, bw + 4, 12), Color(0, 0, 0, 0.55))
		draw_rect(Rect2(bx, 14, bw * ratio, 8), War3D.TEAM.A)
		draw_rect(Rect2(bx + bw * ratio, 14, bw * (1 - ratio), 8), War3D.TEAM.B)
		_text(fb, Vector2(bx - 98, 23), "아군 " + Battle.num(tA), HORIZONTAL_ALIGNMENT_RIGHT, 92, 13, Color("#a9c8f0"))
		_text(fb, Vector2(bx + bw + 6, 23), Battle.num(tB) + " 적", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("#f0aaa2"))
		_text(DB.title_font(16), Vector2(bx, 46), view.clock_text(), HORIZONTAL_ALIGNMENT_CENTER, bw, 16, DB.PAL.paper)
		if view.speed == 0.0:
			_text(fd, Vector2(0, size.y / 2), "일 시 정 지", HORIZONTAL_ALIGNMENT_CENTER, size.x, 26, DB.PAL.bamboo)
		if ann:
			var aa: float = clampf(ann.t / 0.15, 0, 1) * clampf((1.8 - ann.t) / 0.4, 0, 1)
			var ac: Color = ann.col
			var afs := 20
			while afs > 12 and DB.font_display.get_string_size(ann.text, HORIZONTAL_ALIGNMENT_LEFT, -1, afs).x > size.x - 24:
				afs -= 1         # 세로 화면에서 폭을 넘지 않게
			_text(DB.font_display, Vector2(0, 84 + 46 * _charge_rows), ann.text, HORIZONTAL_ALIGNMENT_CENTER, size.x, afs, Color(ac, aa))      # 11/7 기 모으기 표시가 있으면 그 아래
		if cut:
			_draw_cut()
		# 결과 낙관
		if stamp_info:
			var u := clampf(stamp_t / 0.25, 0, 1)
			var sc := lerpf(2.0, 1.0, ease(u, 0.4))
			var c := size / 2 + Vector2(0, -30)
			draw_set_transform(c, deg_to_rad(-6), Vector2.ONE * sc)
			var box := Rect2(Vector2(-90, -62), Vector2(180, 124))
			var sb := StyleBoxFlat.new()
			sb.bg_color = Color(0.05, 0.06, 0.1, 0.75 * u)
			sb.border_color = Color(stamp_info.col, u)
			sb.set_border_width_all(5)
			sb.set_corner_radius_all(14)
			draw_style_box(sb, box)
			draw_string(fd, Vector2(-90, 18), stamp_info.text, HORIZONTAL_ALIGNMENT_CENTER, 180, 50, Color(stamp_info.col.lightened(0.25), u))
			draw_set_transform(Vector2.ZERO)
			var y := c.y + 92
			for line in stamp_info.sub.split("\n"):
				_text(fb, Vector2(0, y), line, HORIZONTAL_ALIGNMENT_CENTER, size.x, 15, Color(DB.PAL.paper, u))
				y += 22

	func _draw_number(f: Dictionary, u: float, col: Color) -> void:
		var base := _to_screen(f.p, 4.0)
		if base.x < -9999:
			return
		var flat: bool = view.field.flat != null
		if flat:      # 11/6 타입2 · 점묘: 숫자가 초상 메달을 덮었다 —— 메달 위로 띄우고 조금 크게
			base = view.field.to_screen(f.p, 0.0) + (_tok_off.get(f.key, Vector2.ZERO) as Vector2) + Vector2(0, -24)
		var fd := DB.font_display
		var crit: bool = f.crit
		var t: float = view.clock - f.t0
		var p := base + Vector2(f.jx * (0.6 if flat else 1.0), -f.n * (19 if flat else 16) - ease(u, 0.5) * (34 if crit else 24))
		if flat:
			var tw: float = DB.font_bold.get_string_size(f.text, HORIZONTAL_ALIGNMENT_LEFT, -1, f.fs).x * 1.18 + 6.0
			var th: float = f.fs * 1.25
			var p0 := base + Vector2(f.jx * 0.6, -f.n * 19)
			p.y += _settle_dy(f, p0, tw, th)
			f.rect = Rect2(p + Vector2(-tw / 2, -th), Vector2(tw, th))
		var sc := 1.0
		if crit:
			sc = lerpf(1.9, 1.0, ease(clampf(t / 0.14, 0, 1), 0.4))       # 쾅 찍혔다가 자리를 잡는다
			p += Vector2(randf_range(-2, 2), randf_range(-2, 2)) * clampf(1.0 - t / 0.25, 0, 1)
		else:
			sc = lerpf(1.35, 1.0, ease(clampf((view.clock - f.pop) / 0.12, 0, 1), 0.4))   # 합쳐질 때마다 톡 튄다
		draw_set_transform(p, 0, Vector2.ONE * sc * (1.18 if flat else 1.0))
		var w := 160.0
		var nf: Font = fd if crit else DB.font_bold
		draw_string_outline(nf, Vector2(-w / 2, 2), f.text, HORIZONTAL_ALIGNMENT_CENTER, w, f.fs, 12 if crit else 10, Color(0, 0, 0, col.a * 0.35))     # 번진 그림자
		draw_string_outline(nf, Vector2(-w / 2, 0), f.text, HORIZONTAL_ALIGNMENT_CENTER, w, f.fs, 7 if crit else 6, Color(0.03, 0.02, 0.01, col.a))
		draw_string(nf, Vector2(-w / 2, 0), f.text, HORIZONTAL_ALIGNMENT_CENTER, w, f.fs, col)
		if crit:
			var lc := Color(1, 0.95, 0.8, col.a)
			draw_string_outline(DB.font_bold, Vector2(-w / 2, -f.fs - 2), "치명타!", HORIZONTAL_ALIGNMENT_CENTER, w, 12, 5, Color(0.35, 0.03, 0, col.a))
			draw_string(DB.font_bold, Vector2(-w / 2, -f.fs - 2), "치명타!", HORIZONTAL_ALIGNMENT_CENTER, w, 12, lc)
		draw_set_transform(Vector2.ZERO)

	## 고유기 컷인 —— 어두워진 화면, 비스듬한 먹띠, 미끄러져 들어오는 초상, 도장처럼 박히는 기술명, 외침
	func _draw_cut() -> void:
		var t: float = cut.t
		var fade := clampf(t / 0.12, 0, 1) * clampf((CUT_T - t) / 0.25, 0, 1)
		if fade <= 0.01:
			return
		var foe: bool = cut.camp == "B"
		var col: Color = cut.col
		var accent: Color = Color("#c8463c") if foe else Color("#d9a64b")
		var sz := size
		var tall := sz.x < sz.y
		# 어둡게 + 가장자리 비네트
		draw_rect(Rect2(Vector2.ZERO, sz), Color(0, 0, 0, 0.5 * fade))
		for i in 6:
			var a := 0.08 * fade * (6 - i) / 6.0
			draw_rect(Rect2(Vector2.ZERO, sz).grow(-i * 22.0), Color(0, 0, 0, a), false, 22.0)
		# 집중선 —— 화면 가운데로 모이는 가는 선
		var c := sz / 2
		var by := c.y + (sz.y * 0.12 if tall else 0.0)     # 먹띠 가운데 높이
		var r := RandomNumberGenerator.new()
		r.seed = int(t * 20.0)
		for i in 46:
			var ang := r.randf() * TAU
			var dir := Vector2.from_angle(ang)
			var a0 := sz.length() * 0.6
			var a1 := r.randf_range(0.28, 0.42) * sz.length()
			draw_line(c + dir * a0, c + dir * a1, Color(1, 1, 1, 0.13 * fade), r.randf_range(1.0, 3.0))
		# 먹띠 —— 비스듬히 화면을 가로지른다
		var band_h := 170.0
		var slide := ease(clampf(t / 0.22, 0, 1), 0.3)
		var sx := (1.0 - slide) * (sz.x if foe else -sz.x)
		var tilt := -0.12 if not foe else 0.12
		var poly := PackedVector2Array()
		for p in _brush:
			poly.append(Vector2(sx + p.x * (sz.x + 200) - 100, by - band_h / 2 + p.y * band_h + (p.x - 0.5) * sz.x * tilt))
		for i in range(_brush.size() - 1, -1, -1):
			var p: Vector2 = _brush[i]
			poly.append(Vector2(sx + p.x * (sz.x + 200) - 100, by + band_h / 2 - p.y * band_h * 0.7 + (p.x - 0.5) * sz.x * tilt))
		draw_colored_polygon(poly, Color(0.06, 0.05, 0.07, 0.92 * fade))
		draw_polyline(poly.slice(0, _brush.size()), Color(accent, 0.9 * fade), 3.0)
		# 초상 —— 띠보다 크게, 옆에서 미끄러져 들어온다
		var ph := minf(sz.y * (0.42 if tall else 0.66), 460.0) if DB.myth_art(cut.k) else minf(sz.y * (0.36 if tall else 0.62), 400.0)
		var pw := ph * 0.78
		var pin := ease(clampf((t - 0.05) / 0.25, 0, 1), 0.25)
		var px: float
		var pr: Rect2
		if tall:
			px = lerpf(-pw - 40, (sz.x - pw) / 2, pin) if not foe else lerpf(sz.x + 40, (sz.x - pw) / 2, pin)
			pr = Rect2(px, by - band_h / 2 - ph + 24, pw, ph)
		else:
			px = lerpf(-pw - 40, sz.x * 0.14, pin) if not foe else lerpf(sz.x + 40, sz.x * 0.86 - pw, pin)
			pr = Rect2(px, c.y - ph * 0.55, pw, ph)
		if pin > 0.02:
			draw_rect(pr.grow(8), Color(col, 0.35 * fade))
			draw_rect(pr.grow(3), Color(0, 0, 0, 0.9 * fade))
		if pin > 0.02:
			Art.draw_portrait(self, pr, cut.k, t, "ult")      # 고유기 컷인 —— 고유기용 (신화 그림, 없으면 얼굴)
			if fade < 1.0:
				draw_rect(pr, Color(0, 0, 0, (1.0 - fade) * 0.7))
			draw_rect(pr, Color(col, fade), false, 3.0)
		# 기술명 —— 크게 찍혔다가 자리를 잡는다
		var fd := DB.font_display
		var nt := clampf((t - 0.22) / 0.16, 0, 1)
		if nt > 0:
			var sc := lerpf(1.9, 1.0, ease(nt, 0.35))
			var shake := Vector2(randf_range(-3, 3), randf_range(-3, 3)) * (1.0 - nt)
			var tx := sz.x * 0.04 if tall else (sz.x * 0.36 if not foe else sz.x * 0.08)
			var tw := sz.x * (0.92 if tall else 0.56)
			var title: String = "『%s』" % cut.name
			var tfs := 64
			while tfs > 30 and fd.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, tfs).x > tw:
				tfs -= 2
			draw_set_transform(Vector2(tx + tw / 2, by + 26) + shake, tilt * 0.5, Vector2.ONE * sc)
			draw_string_outline(fd, Vector2(-tw / 2, 0), title, HORIZONTAL_ALIGNMENT_CENTER, tw, tfs, 12, Color(0, 0, 0, fade))
			draw_string(fd, Vector2(-tw / 2, 0), title, HORIZONTAL_ALIGNMENT_CENTER, tw, tfs, Color(accent.lightened(0.35), fade * nt))
			draw_set_transform(Vector2.ZERO)
			# 외침 —— 한 글자씩 나온다
			var shout: String = "“%s”" % cut.shout
			var shown := shout.substr(0, int(clampf((t - 0.3) / 0.55, 0, 1) * shout.length()))
			_text(fd, Vector2(tx, by - 40 if tall else by - 52), shown, HORIZONTAL_ALIGNMENT_CENTER, tw, 20 if tall else 24, Color(1, 0.95, 0.88, fade))
			if cut.crisis:      # 위기에 쓴 고유기 —— 위력이 오른다
				_text(fd, Vector2(tx, pr.position.y - 10 if tall else by - 92), "배수진", HORIZONTAL_ALIGNMENT_CENTER, tw, 22, Color(1, 0.35, 0.25, fade * nt))
			# 장수 이름 낙관
			var who: String = cut.who
			var wsz := DB.font_body.get_string_size(who, HORIZONTAL_ALIGNMENT_LEFT, -1, 15)
			var wb := Rect2(Vector2(tx + tw / 2 - wsz.x / 2 - 10, by + 50), Vector2(wsz.x + 20, 26))
			draw_rect(wb, Color(accent, 0.85 * fade))
			draw_string(DB.font_body, wb.position + Vector2(10, 19), who, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(1, 1, 1, fade))
			# 11/6 사용자: 고유기명 아래 효과 —— "적 전체 피해 320% · 화상"
			var desc: String = cut.get("desc", "")
			if desc != "":
				var dfs := 15
				while dfs > 11 and DB.font_bold.get_string_size(desc, HORIZONTAL_ALIGNMENT_LEFT, -1, dfs).x > tw:
					dfs -= 1
				var dy := wb.end.y + 22
				draw_string_outline(DB.font_bold, Vector2(tx, dy), desc, HORIZONTAL_ALIGNMENT_CENTER, tw, dfs, 6, Color(0, 0, 0, 0.85 * fade))
				draw_string(DB.font_bold, Vector2(tx, dy), desc, HORIZONTAL_ALIGNMENT_CENTER, tw, dfs, Color("#ffe6a8", fade * nt))

	func _text(f: Font, p: Vector2, s: String, al: int, w: float, fs: int, col: Color) -> void:
		draw_string_outline(f, p, s, al, w, fs, 5, Color(0, 0, 0, 0.8 * col.a))
		draw_string(f, p, s, al, w, fs, col)


## 아래 띠의 아군 부대 카드 —— 누르면 그 부대로 카메라가 간다
class MiniCard extends Control:
	var sq: Squad
	var view: BattleView

	## 11/7 카드 높이 —— 막대 세 줄에 글자(병 · 사 · 기)를 붙이느라 58 → 64 (넓은 카드는 병종 줄이 있어 70). 아래 독 두 줄이면 12px 자란다
	const H_SMALL := 64.0
	const H_WIDE := 70.0
	## 막대 색 —— 병력 파랑(위 세력 띠와 같은 진영색) · 사기 옥색 · 고유기 금색(전투장수창 『고유기』 #ffd76e 계열).
	## 11/7 사용자: 사기 · 고유기가 둘 다 금색이라 어느 막대가 무엇인지 안 보였다
	const MORALE_COL := Color("#6fd6a6")
	const ULT_COL := Color("#d9a64b")
	const ULT_FULL := Color("#ffd76e")

	func _ready() -> void:
		custom_minimum_size = Vector2(64, H_SMALL)
		mouse_filter = Control.MOUSE_FILTER_STOP
		tooltip_text = sq.row.name

	func _notification(what: int) -> void:
		if what == NOTIFICATION_RESIZED:      # 폭이 정해진 뒤 그 칸 모양(좁은 · 넓은)에 맞는 높이로 —— 격자가 한 번 더 자리를 잡는다
			var want := H_WIDE if size.x >= 90 else H_SMALL
			if custom_minimum_size.y != want:
				custom_minimum_size.y = want

	var _last := []

	func _process_card() -> void:
		var lv := view.unit_live(sq.key)
		var ready := view.ult_ready(sq.key)
		var now := [int(sq.troops / sq.max * 200), int(sq.morale), sq.glow > 0.05, sq.hurt > 0.05, sq.alive, sq.troops <= 0, lv[0], lv[1], ready]
		if now != _last or ready or _waiting(lv):
			_last = now
			queue_redraw()

	## 11/6 #14 게이지는 찼는데 차례(대기 · 간격 · 조건)를 기다리는 중 —— 「준비」 가 깜빡인다
	func _waiting(lv: Array) -> bool:
		return sq.tier >= 6 and lv[1] > 0 and lv[0] >= 100.0 and not view.direct and sq.alive

	var _down_ms := -1
	var _long_fired := false

	## 11/6 #11: 한 번 누르면 전장의 그 부대를 강조(카메라는 움직이지 않음), 길게 누르면 디테일창
	func _gui_input(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
			if e.pressed:
				_down_ms = Time.get_ticks_msec()
				_long_fired = false
			else:
				if _down_ms >= 0 and not _long_fired:
					if view.direct and view.ult_ready(sq.key):
						UI.buzz(20)
						view.request_ult(sq.key)
					else:
						UI.buzz()
						view.hud.highlight(sq.key)
						if view.field.flat == null:
							view.focus(sq)
				_down_ms = -1

	func _process(_dt: float) -> void:
		if _down_ms >= 0 and not _long_fired and Time.get_ticks_msec() - _down_ms >= BattleView.LONG_PRESS * 1000:
			_long_fired = true
			if DB.C.has(sq.cid):
				UI.buzz(30)
				view.unit_requested.emit(sq.key)
		_process_card()

	func _draw() -> void:
		var t0 := Time.get_ticks_usec()
		_draw_card()
		view.field.pt("아래카드", t0)

	## 넓은 카드 (폭 90 이상 —— 가로 · PC 창) —— 초상 · 이름 · 병종 · 병력, 아래에 글자 붙은 막대 세 줄
	func _draw_card() -> void:
		if size.x < 90:
			_draw_small()
			return
		var tc := DB.tier_color(sq.cid)
		var sb := StyleBoxFlat.new()
		sb.bg_color = DB.PAL.ink2
		sb.set_corner_radius_all(6)
		var danger: bool = sq.alive and sq.troops > 0 and sq.troops / sq.max < 0.3      # 11/6 #16 위험 신호
		sb.set_border_width_all(3 if sq.glow > 0.05 or sq.hurt > 0.05 or danger else 2)      # 11/6 사용자: 프로필 테두리를 더 구별되게 (등급색 2px)
		sb.border_color = DB.PAL.gold if sq.glow > 0.05 else (Color("#ff6a4d") if (sq.hurt > 0.05 or danger) else tc)
		draw_style_box(sb, Rect2(Vector2.ZERO, size))
		Art.draw_portrait(self, Rect2(4, 4, 34, 38), sq.cid, 0.0, "ult" if view.direct and view.ult_ready(sq.key) else "face")
		var fb := DB.font_body
		var nm: String = DB.person(sq.cid) if sq.tier > 2 else sq.row.name
		draw_string(DB.title_font(12), Vector2(41, 17), nm, HORIZONTAL_ALIGNMENT_LEFT, 52, 12, tc.lightened(0.2))      # 11/10 작은 이름은 굵은 고딕
		draw_string(fb, Vector2(41, 29), sq.tag, HORIZONTAL_ALIGNMENT_LEFT, 52, 10, DB.PAL.bamboo_dim)
		var state: String = "%d명" % sq.alive_count() if sq.alive else ("궤멸" if sq.troops <= 0 else "패주")
		draw_string(fb, Vector2(41, 41), state, HORIZONTAL_ALIGNMENT_LEFT, 52, 10, DB.PAL.bamboo if sq.alive else Color("#ff6b57"))
		_bar_rows(4.0, 44.0, size.x - 8.0, 8.0, 8)
		if view.direct and view.ult_ready(sq.key):       # 직접 지휘일 때만 '눌러라' 금테
			var pulse := 0.5 + 0.5 * sin(view.clock * 9.0)
			var rb := StyleBoxFlat.new()
			rb.draw_center = false
			rb.border_color = Color("#ffd257").lerp(Color.WHITE, pulse * 0.5)
			rb.set_border_width_all(3)
			rb.set_corner_radius_all(6)
			rb.shadow_color = Color("#ffd257", 0.5 * pulse)
			rb.shadow_size = 6
			draw_style_box(rb, Rect2(Vector2.ZERO, size))
			_glow_text("고유기!")
		if not sq.alive:
			draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.55))

	## 작은 카드 (휴대폰 세로 —— 폭 약 73) —— 초상 · 이름 · 병력, 아래에 글자 붙은 막대 세 줄.
	## 11/7 사용자: 고유기 남은 횟수 구슬이 이름 옆(위 오른쪽)에 떠서 세 글자 이름과 겹쳤다 → 기 막대 끝으로 (이름 줄과 다른 줄이라 어떤 길이에도 안 겹친다)
	func _draw_small() -> void:
		var tc := DB.tier_color(sq.cid)
		var w := size.x
		var ready := view.direct and view.ult_ready(sq.key)
		var sb := StyleBoxFlat.new()
		sb.bg_color = DB.PAL.ink2
		sb.set_corner_radius_all(6)
		var danger: bool = sq.alive and sq.troops > 0 and sq.troops / sq.max < 0.3      # 11/6 #16 위험 신호
		sb.set_border_width_all(2 if sq.glow > 0.05 or sq.hurt > 0.05 or danger else 1)
		sb.border_color = DB.PAL.gold if sq.glow > 0.05 else (Color("#ff6a4d") if (sq.hurt > 0.05 or danger) else tc)
		draw_style_box(sb, Rect2(Vector2.ZERO, size))
		var bar_y := 39.0
		var pr := Rect2(3, 3, minf(26, w * 0.36), bar_y - 5)
		Art.draw_portrait(self, pr, sq.cid, 0.0, "ult" if ready else "face")
		var x := pr.end.x + 3
		var tw := w - x - 2
		var nm: String = DB.person(sq.cid) if sq.tier > 2 else sq.row.name
		var fs := 12
		var nmf := DB.title_font(fs)      # 11/10 작은 이름은 굵은 고딕 (폭 계산도 같은 글꼴로)
		while fs > 9 and nmf.get_string_size(nm, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > tw:
			fs -= 1
		draw_string(nmf, Vector2(x, 16), nm, HORIZONTAL_ALIGNMENT_LEFT, tw, fs, tc.lightened(0.2))
		var state: String = "%d명" % sq.alive_count() if sq.alive else ("궤멸" if sq.troops <= 0 else "패주")
		draw_string(DB.font_body, Vector2(x, 30), state, HORIZONTAL_ALIGNMENT_LEFT, tw, 10, DB.PAL.bamboo if sq.alive else Color("#ff6b57"))
		_bar_rows(3.0, bar_y, w - 6.0, 8.0, 8)
		if ready:
			var pulse := 0.5 + 0.5 * sin(view.clock * 9.0)
			var rb := StyleBoxFlat.new()
			rb.draw_center = true
			rb.bg_color = Color("#ffd257", 0.10 + 0.08 * pulse)
			rb.border_color = Color("#ffd257").lerp(Color.WHITE, pulse * 0.5)
			rb.set_border_width_all(3)
			rb.set_corner_radius_all(6)
			draw_style_box(rb, Rect2(Vector2.ZERO, size))
			draw_string_outline(DB.title_font(13), Vector2(0, 50), "고유기", HORIZONTAL_ALIGNMENT_CENTER, w, 13, 4, Color(0, 0, 0, 0.9))
			draw_string(DB.title_font(13), Vector2(0, 50), "고유기", HORIZONTAL_ALIGNMENT_CENTER, w, 13, Color("#ffd257"))
		if not sq.alive:
			draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.55))

	## 막대 세 줄 (11/7 사용자: 막대 뜻을 한눈에) —— 줄마다 왼쪽에 글자(병 · 사 · 기), 굵기 병력 5 · 사기 2 · 고유기 3, 색은 파랑 · 옥색 · 금색.
	## 고유기 줄 끝에 남은 횟수 구슬(최대 3, 11/7 재사용) —— 차례를 기다리는 중이면 막대 자리에 「준비」 가 깜빡인다 (11/6 #14).
	## x0 · y0 왼쪽 위, bw 전체 폭, pitch 줄 간격, lfs 글자 크기
	func _bar_rows(x0: float, y0: float, bw: float, pitch: float, lfs: int) -> void:
		var fb := DB.font_bold
		var bx := x0 + lfs + 3.0
		var bw2 := bw - (lfs + 3.0)
		var y := y0
		# 병력 —— 굵게 · 진영 파랑
		draw_string(fb, Vector2(x0, y + pitch - 2.0), "병", HORIZONTAL_ALIGNMENT_LEFT, -1, lfs, Color("#9cc4ff"))
		draw_rect(Rect2(bx, y + 2.0, bw2, 5), DB.PAL.ink)
		draw_rect(Rect2(bx, y + 2.0, bw2 * clampf(sq.troops / sq.max, 0, 1), 5), War3D.TEAM.A)
		# 사기 —— 가늘게 · 옥색. 100 이 가득 (예전 /200 이라 평소에 반만 차 보였다), 넘치면 밝게, 30 아래면 붉게 (11/4)
		y += pitch
		var mc: Color = Color("#ff6b57") if sq.morale < 30 else (Color("#c2f7df") if sq.morale > 100 else MORALE_COL)
		draw_string(fb, Vector2(x0, y + pitch - 2.0), "사", HORIZONTAL_ALIGNMENT_LEFT, -1, lfs, MORALE_COL)
		draw_rect(Rect2(bx, y + 3.0, bw2, 2), DB.PAL.ink)
		draw_rect(Rect2(bx, y + 3.0, bw2 * clampf(sq.morale / 100.0, 0, 1), 2), mc)
		# 고유기 —— 금색 · 끝에 남은 횟수 구슬 (6급 이상 · 기인만. 횟수가 다 떨어지면 회색)
		y += pitch
		if sq.tier >= 6 or DB.is_kiin(sq.cid):
			var lv := view.unit_live(sq.key)
			var n: int = lv[1]
			draw_string(fb, Vector2(x0, y + pitch - 2.0), "기", HORIZONTAL_ALIGNMENT_LEFT, -1, lfs, ULT_FULL if n > 0 else Color("#777"))
			var gw := bw2 - (n * 7.0 + 3.0 if n > 0 else 0.0)
			if _waiting(lv):
				var pb := StyleBoxFlat.new()
				pb.bg_color = Color("#d9a64b", 0.6 + 0.3 * sin(view.clock * 6.0))
				pb.set_corner_radius_all(3)
				draw_style_box(pb, Rect2(bx, y, gw, pitch))
				draw_string(fb, Vector2(bx, y + pitch - 1.5), "준비", HORIZONTAL_ALIGNMENT_CENTER, gw, lfs, Color("#1A1508"))
			else:
				draw_rect(Rect2(bx, y + 2.5, gw, 3), DB.PAL.ink)
				var gc: Color = (ULT_FULL if lv[0] >= 100.0 else ULT_COL) if n > 0 else Color("#555")
				draw_rect(Rect2(bx, y + 2.5, gw * clampf(lv[0] / 100.0, 0, 1), 3), gc)
			for i in n:
				var c := Vector2(bx + gw + 6.0 + i * 7.0, y + 4.0)
				draw_circle(c, 3.2, Color(0, 0, 0, 0.7))
				draw_circle(c, 2.4, Color("#ffd257"))

	func _glow_text(t: String) -> void:
		draw_string_outline(DB.title_font(13), Vector2(0, -4), t, HORIZONTAL_ALIGNMENT_CENTER, size.x, 13, 4, Color(0, 0, 0, 0.9))
		draw_string(DB.title_font(13), Vector2(0, -4), t, HORIZONTAL_ALIGNMENT_CENTER, size.x, 13, Color("#ffd257"))
