class_name Settings
extends RefCounted
## 설정 —— user://settings.cfg. 품질(병사 수·안티에일리어싱·그림자)과 자동 전투.
## 모바일은 처음 켤 때 '낮음', PC 는 '높음'으로 시작한다.

const PATH := "user://settings.cfg"
const QUALITY_N := ["낮음", "중간", "높음"]
const COUNT_SCALE := [0.4, 0.65, 1.0]     # 병사 수 배율 (Squad.count_scale)
const SHADOW := [1024, 2048, 4096]
const RES_SCALE := [0.6, 0.8, 1.0]       # 전장 3D 해상도 (화면 실제 픽셀 대비)

static var quality := -1
static var auto_battle := false
static var haptics := true
static var _loaded := false


static func load_cfg() -> void:
	if _loaded:
		return
	_loaded = true
	var cf := ConfigFile.new()
	if cf.load(PATH) == OK:
		quality = int(cf.get_value("gfx", "quality", -1))
		auto_battle = bool(cf.get_value("play", "auto_battle", false))
		haptics = bool(cf.get_value("play", "haptics", true))
	if quality < 0:
		quality = 0 if OS.has_feature("mobile") else 2
	apply()


static func save_cfg() -> void:
	var cf := ConfigFile.new()
	cf.set_value("gfx", "quality", quality)
	cf.set_value("play", "auto_battle", auto_battle)
	cf.set_value("play", "haptics", haptics)
	cf.save(PATH)


static func apply() -> void:
	Squad.count_scale = COUNT_SCALE[quality]


## 전장 뷰포트에 품질을 건다 (BattleView 가 만든 SubViewport)
static func apply_port(port: SubViewport) -> void:
	port.msaa_3d = [Viewport.MSAA_DISABLED, Viewport.MSAA_2X, Viewport.MSAA_4X][quality]
	port.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA     # 싸다 —— 끄면 낮음에서 풀잎이 검은 점으로 깜빡인다
	port.positional_shadow_atlas_size = SHADOW[quality]
	var w := port.get_child(0) as War3D
	if w:
		w.set_quality(quality)
