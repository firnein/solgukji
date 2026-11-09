class_name Settings
extends RefCounted
## 설정 —— user://settings.cfg. 품질(병사 수·안티에일리어싱·그림자)과 직접 지휘, 소리 크기.
## 모바일은 처음 켤 때 '낮음', PC 는 '높음'으로 시작한다.

const PATH := "user://settings.cfg"
const QUALITY_N := ["낮음", "중간", "높음"]
const FULL_COUNT_DEBUG := true
const COUNT_SCALE := [0.4, 0.65, 1.0]     # 병사 수 배율 (Squad.count_scale)
## 11/9 병사 표시 예산 —— 전투 전체에서 화면에 그리는 병사 수 상한 [PC, 휴대폰]. 넘으면 그만큼만 그리고 남은 인형을 크게 · 짙게 (type2_view.gd). 판정 · 병력은 그대로
const DRAW_BUDGET := [9000, 5000]
const DRAW_GROW_MAX := 1.35     # 예산으로 줄인 비율이 클 때 인형 최대 배율
const SHADOW := [1024, 2048, 4096]
const RES_SCALE := [0.75, 0.9, 1.0]      # 전장 3D 해상도 (화면 실제 픽셀 대비) —— 낮으면 병사가 뿌옇다

static var quality := -1
static var direct := false     # 직접 지휘 —— 켜면 전투 중 고유기 · 군령 버튼이 보인다. 꺼도 AI 가 똑같이 잘 쓴다 (11/1: 덱 감상 전투)
static var haptics := true
static var sfx_vol := 0.8      # 효과음 크기 (0 끔 ~ 1)
static var bgm_vol := 0.5      # 배경 음악 크기
static var dots := false      # 전장 표현 —— 3D(삼국지13식, 11/1 사용자: 기본으로 되돌림) / 점묘(블라인드삼국식 2D)
static var sumuk := false      # 전장 화풍 —— 수묵(삼국지11 시안) 후처리 (10/31)
static var type2 := true       # 전장 표현 '타입2' —— 삼국지11 식 지도판 · 병사 인형 (11/3, scripts/field/type2_view.gd). 11/6 사용자: 기본 전투 화면 (3D · 수묵은 설정에 남긴다)
static var dmg_numbers := 1    # 피해 숫자 —— 0 큰 것만(기술 · 고유기 · 치명타) · 1 모아서 · 2 모두 (11/6 #16)
static var cam_fx := 1         # 전투 카메라 연출 —— 0 끔 · 1 적게(아군 고유기 · 적 신화 고유기 · 장수 격파) · 2 보통(첫 격돌 · 모든 고유기). 11/6 사용자
static var perf_hud := false   # 성능 표시 —— 전투 왼쪽 위에 fps · 계산 병사 · 보이는 인형 · 부하 조절 단계 (휴대폰 실측용, 11/6 목표)
static var tac_info := 1       # 타입2 전황 표시 —— 0 끔 · 1 간단(진형 소개 · 책략 실) · 2 자세히(+ 사거리 · 전술 화살표). 11/6
## 11/9 사용자: 3D 전장(기본 3D · 수묵)은 점검하지 않으므로 설정에서 숨기고 늘 타입2 로 시작한다. 되살리려면 true —— 선택칸이 다시 보이고 저장된 값을 지킨다 (코드 · 점검 인자 --gtype2 · --gsumuk 는 그대로)
const SHOW_3D := false
static var _loaded := false


static func load_cfg() -> void:
	if _loaded:
		return
	_loaded = true
	var cf := ConfigFile.new()
	if cf.load(PATH) == OK:
		quality = int(cf.get_value("gfx", "quality", -1))
		direct = false      # 11/4 직접 지휘 없앰
		haptics = bool(cf.get_value("play", "haptics", true))
		sfx_vol = float(cf.get_value("sound", "sfx", 0.8))
		bgm_vol = float(cf.get_value("sound", "bgm", 0.5))
		sumuk = bool(cf.get_value("gfx", "sumuk", false))
		type2 = bool(cf.get_value("gfx", "type2", true))
		if not cf.has_section_key("gfx", "type2_default"):      # 11/6 한 번은 타입2로 옮긴다 (예전 저장값이 3D 여도). 그 뒤 고른 값은 지킨다
			type2 = true
		tac_info = int(cf.get_value("gfx", "tac_info", 1))
		perf_hud = bool(cf.get_value("gfx", "perf_hud", false))
		cam_fx = int(cf.get_value("gfx", "cam_fx", 1))
		dmg_numbers = int(cf.get_value("gfx", "dmg_numbers", 1))
		if not SHOW_3D:      # 저장된 설정에 3D · 수묵이 켜져 있던 사용자도 타입2 로 (다음 저장 때 파일도 바뀐다)
			type2 = true
			sumuk = false
		dots = false     # 11/3 사용자: 점묘 옵션을 숨겼다 —— 저장값과 상관없이 3D (점검용 --gdots / --dots 로만 켠다)
	if quality < 0:
		quality = 0 if OS.has_feature("mobile") else 2
	apply()


static func save_cfg() -> void:
	var cf := ConfigFile.new()
	cf.set_value("gfx", "quality", quality)
	cf.set_value("play", "direct", direct)
	cf.set_value("play", "haptics", haptics)
	cf.set_value("sound", "sfx", sfx_vol)
	cf.set_value("sound", "bgm", bgm_vol)
	cf.set_value("gfx", "sumuk", sumuk)
	cf.set_value("gfx", "type2", type2)
	cf.set_value("gfx", "type2_default", 2)
	cf.set_value("gfx", "tac_info", tac_info)
	cf.set_value("gfx", "perf_hud", perf_hud)
	cf.set_value("gfx", "cam_fx", cam_fx)
	cf.set_value("gfx", "dmg_numbers", dmg_numbers)
	cf.set_value("gfx", "dots_v2", dots)
	cf.save(PATH)


static func apply() -> void:
	Squad.count_scale = COUNT_SCALE[quality]
	if FULL_COUNT_DEBUG and not OS.has_feature("mobile"):
		Squad.count_scale = 1.0     # 11/3: PC 는 품질과 상관없이 병사를 다 풀어 놓는다. 11/6 사용자: 휴대폰은 디버그 APK 라도 품질대로 (전엔 디버그면 '낮음'이 먹지 않아 후반 프레임 드랍)
	if type2:
		Squad.count_scale = 1.0     # 11/6 목표 '휴대폰에서도 품질이 떨어지지 않는 대군': 타입2 는 병사 수를 품질로 줄이지 않는다 —— 무거우면 부수 연출을 줄인다 (Type2View 부하 조절)


## 전장 뷰포트에 품질을 건다 (BattleView 가 만든 SubViewport)
static func apply_port(port: SubViewport) -> void:
	# 모바일 GPU(타일 방식)는 MSAA 2배가 싸다. FXAA 는 화면 전체를 문질러 병사가 뿌옇게 되므로 쓰지 않는다
	port.msaa_3d = [Viewport.MSAA_2X, Viewport.MSAA_2X, Viewport.MSAA_4X][quality]
	port.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	port.positional_shadow_atlas_size = SHADOW[quality]
	var w := port.get_child(0) as War3D
	if w:
		w.set_quality(quality)
