class_name Settings
extends RefCounted
## 설정 —— user://settings.cfg. 품질(병사 수·안티에일리어싱·그림자)과 직접 지휘, 소리 크기.
## 모바일은 처음 켤 때 '낮음', PC 는 '높음'으로 시작한다.

const PATH := "user://settings.cfg"
const QUALITY_N := ["낮음", "중간", "높음"]
const FULL_COUNT_DEBUG := true
const COUNT_SCALE := [0.4, 0.65, 1.0]     # 병사 수 배율 (Squad.count_scale)
const SHADOW := [1024, 2048, 4096]
const RES_SCALE := [0.75, 0.9, 1.0]      # 전장 3D 해상도 (화면 실제 픽셀 대비) —— 낮으면 병사가 뿌옇다

static var quality := -1
static var direct := false     # 직접 지휘 —— 켜면 전투 중 고유기 · 군령 버튼이 보인다. 꺼도 AI 가 똑같이 잘 쓴다 (11/1: 덱 감상 전투)
static var haptics := true
static var sfx_vol := 0.8      # 효과음 크기 (0 끔 ~ 1)
static var bgm_vol := 0.5      # 배경 음악 크기
static var dots := false      # 전장 표현 —— 3D(삼국지13식, 11/1 사용자: 기본으로 되돌림) / 점묘(블라인드삼국식 2D)
static var sumuk := false      # 전장 화풍 —— 수묵(삼국지11 시안) 후처리 (10/31)
static var type2 := false      # 전장 표현 '타입2' —— 삼국지11 식 지도판 · 병사 인형 · 성씨 깃발 (11/3, scripts/field/type2_view.gd)
static var cam_fx := 1         # 전투 카메라 연출 —— 0 끔 · 1 적게(아군 고유기 · 적 신화 고유기 · 장수 격파) · 2 보통(첫 격돌 · 모든 고유기). 11/6 사용자
static var tac_info := 1       # 타입2 전황 표시 —— 0 끔 · 1 간단(진형 소개 · 우대 금테 · 책략 실) · 2 자세히(+ 사거리 · 전술 화살표). 11/6
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
		type2 = bool(cf.get_value("gfx", "type2", false))
		tac_info = int(cf.get_value("gfx", "tac_info", 1))
		cam_fx = int(cf.get_value("gfx", "cam_fx", 1))
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
	cf.set_value("gfx", "tac_info", tac_info)
	cf.set_value("gfx", "cam_fx", cam_fx)
	cf.set_value("gfx", "dots_v2", dots)
	cf.save(PATH)


static func apply() -> void:
	Squad.count_scale = COUNT_SCALE[quality]
	if FULL_COUNT_DEBUG and not OS.has_feature("mobile"):
		Squad.count_scale = 1.0     # 11/3: PC 는 품질과 상관없이 병사를 다 풀어 놓는다. 11/6 사용자: 휴대폰은 디버그 APK 라도 품질대로 (전엔 디버그면 '낮음'이 먹지 않아 후반 프레임 드랍)


## 전장 뷰포트에 품질을 건다 (BattleView 가 만든 SubViewport)
static func apply_port(port: SubViewport) -> void:
	# 모바일 GPU(타일 방식)는 MSAA 2배가 싸다. FXAA 는 화면 전체를 문질러 병사가 뿌옇게 되므로 쓰지 않는다
	port.msaa_3d = [Viewport.MSAA_2X, Viewport.MSAA_2X, Viewport.MSAA_4X][quality]
	port.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	port.positional_shadow_atlas_size = SHADOW[quality]
	var w := port.get_child(0) as War3D
	if w:
		w.set_quality(quality)
