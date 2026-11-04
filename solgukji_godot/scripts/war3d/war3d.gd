class_name War3D
extends Node3D
## 3D 전장 —— 지형·하늘·빛·안개·숲과 수백 명의 병사 인형, 화살·불길·물보라 같은 효과를 그린다.
## 부대의 움직임(Squad)은 2D 평면 좌표(px)로 계산하고, 여기서 S 배율로 미터 단위 3D 로 옮긴다.
##   2D (x, y) → 3D (x·S, 지형높이, y·S).  아군은 -X 쪽에서 +X 를 바라본다.
## 병사는 병종마다 MultiMesh 하나로 그린다 (GPU 인스턴싱). 시신·피격 번쩍임은 INSTANCE_CUSTOM 으로 넘긴다.

const S := 0.1
const GAP := 240.0      # 양군 선봉 사이 (px)
const RS := 78.0        # 열 간격 (px) —— 부대가 앞뒤로 이어지게
const CS := 118.0       # 좌·중앙·우 간격 (px) —— 옆 부대와 거의 붙은 전열
const TEAM := {"A": Color("#3a6aa6"), "B": Color("#a9443a")}     # 10/31 조금 가라앉힌 진영색
const ST_COL := {"burn": Color("#ff8a3c"), "flood": Color("#4a9ad4"), "confuse": Color("#b57edc"),
	"bleed": Color("#c4564a"), "plague": Color("#7fa86b"), "seal": Color("#9a9a9a"),
	"cut_atk": Color("#e0705a"), "cut_int": Color("#7f8fe0"), "cut_def": Color("#e8a84a"), "cut_res": Color("#c46fd0"),     # 위축 · 산란 · 파갑 · 현혹 (수치 깎기, 솔국지 확장)
	"phalanx": Color("#7fb2e5"), "moved": Color("#f2c46d")}  # 방진 · 분발 (버프)
const WEAPON := {"창병": "spear", "도적": "sword", "기병": "lance"}
const HAND := {"spear": Vector3(0.16, 0.74, 0.24), "sword": Vector3(0.2, 0.74, 0.22), "lance": Vector3(0.16, 1.62, 0.27),
	"g_glaive": Models.G_HAND, "g_saber": Models.G_HAND, "g_lance": Models.G_HAND}
## 무기 든 팔이 도는 어깨 자리 (모델 x, y) —— 손에 쥔 무기도 같은 축으로 함께 돈다
const ARM_PIVOT := {"spear": Models.SHOULDER, "sword": Models.SHOULDER, "lance": Models.R_SHOULDER,
	"g_glaive": Models.R_SHOULDER, "g_saber": Models.R_SHOULDER, "g_lance": Models.R_SHOULDER}
const HIDDEN := Transform3D(Basis(Vector3.ZERO, Vector3.ZERO, Vector3.ZERO), Vector3(0, -500, 0))

signal ult_flash(col: Color)     # 고유기가 터지는 순간 —— 화면 섬광 (BattleView 의 Hud)

var squads := {}
var order: Array = []
var clock := 0.0
var time_scale := 1.0
var active := true
var rng := RandomNumberGenerator.new()
var noise := FastNoiseLite.new()

var cam: Camera3D
var cam_t := Vector3.ZERO
var cam_yaw := 0.0
var cam_pitch := 0.62
var cam_dist := 78.0
var screen_scale := 1.0     # 3D 해상도 / 화면 논리 크기 (BattleView.fit_port)
var portrait := false
var want_t := Vector3.ZERO
var want_yaw := 0.0
var want_pitch := 0.62
var want_dist := 78.0
var cam_rate := 4.0
var _intro := 0.0

var soldier_mat: ShaderMaterial
var body_mesh := {}
var weapon_mesh := {}
var bodies := {}            # 병종 -> MultiMeshInstance3D
var weapons := {}           # 무기 -> MultiMeshInstance3D
var entries := []           # [부대, 병사, 병종, 번호, 무기, 무기번호, 장수인가]
var banners := {}           # 부대 key -> Node3D
var unit_root: Node3D
var fx_root: Node3D
var arrow_mmi: MultiMeshInstance3D
var arrows := []
var orbs := []
var lights := []
var rings := []
var areas := []
var tzones := []            # 실시간 엔진 지형 (res.terrain) —— 숲 · 강 · 언덕. 좌표는 전장 px
var _hills := []            # [중심(세계), 반지름(세계)] —— height() 에 둔덕을 더한다
var terrain_root: Node3D    # 판마다 새로 까는 지형 (나무 · 물길 · 둔덕)
const HILL_H := 2.2         # 둔덕 높이 (세계 단위)             # 기술 범위 표시 [{n: Decal, t0, life}] —— 땅에 깔렸다 사라진다
var _disc_tex: Texture2D
var _band_tex: Texture2D
var fx_nodes := []
var auras := {}
var _soft: Texture2D
var _pmat := {}
var _duel_t := 0.0
var shake := 0.0
var focus_sq: Squad = null    # 비네트 집중 —— 이 부대만 밝게 (BattleView.focus)
var focus_t := 0.0
var _hs := PackedFloat32Array()   # 지형 높이 격자 —— 지형을 만들 때 채운다
var _hn := 0
var _hstep := 1.0
var _hhalf := 0.0
var _bufs := {}             # MultiMesh -> 인스턴스 버퍼 (변환 12 + 사용자 4 = 16 float)
## 11/3 GPU 병사 (사용자: 병사 3~5배) —— 살아 있는 병사는 shaders/soldier_gpu.gdshader 가 부대 값(_sq_tex)으로 그린다.
## CPU 는 장수 · 쓰러지는 병사만 그린다. 점묘 · 타입2 전장(2D)은 병사 위치가 필요해 예전 방식
static var gpu_mode := true
var _gpu := false
var gpu_mmi := []           # GPU 병사 MultiMeshInstance3D (몸 · 무기)
var _sq_img: Image
var _sq_tex: ImageTexture
var _h_tex: ImageTexture
var _gpu_mat: ShaderMaterial
var _flyers := []           # 공중에 뜬 병사 (날아가는 시신) —— _air 가 이것만 돈다
var _entry_of := {}         # 병사 -> entries 한 줄 (GPU: 쓰러진 병사를 CPU 목록에 넣으려고)
var _cpu_list := []         # GPU 모드에서 CPU 가 돌보는 줄 —— 장수 · 아직 넘어지는 중인 시신 · 막 되살아나 숨겨야 할 병사
var _cpu_full := true       # 다음 _sync 는 전체를 한 번 돈다
var prof := {}              # 점검용 —— 구간별 누적 시간 (마이크로초)
var dbg_nofx := false       # 점검용 —— 파티클을 만들지 않는다
var ult: UltFx
var _env: Environment
var _sun: DirectionalLight3D
var _cine := 0.0            # 고유기 카메라 연출이 남은 시간 (실시간)
var _cine_back := []        # 연출 전 카메라 [대상, 거리, 높이각]
var director := true        # 자동 카메라 —— 살아 있는 부대가 화면에 꽉 차게 따라간다
var _manual := 0.0          # 손으로 카메라를 움직인 뒤 자동 카메라가 쉬는 시간 (실시간)
const MANUAL_HOLD := 5.0
var track_mode := false    # 실시간 엔진 전투 —— 부대가 엔진 위치 기록을 따른다 (follow_track)
var _model_q := -1          # 몸통을 구운 품질 단계
# 병사 그림 판 (10/31 사용자: 일러스트 병사) —— assets/troops_sprite/<병종>.png 가 있으면 그 병종 병사는 그림으로 그린다 (장수는 3D)
const SPRITE_DIR := "res://assets/troops_sprite/"
const SPRITE_H := {"기병": 2.75}   # 그림 판 한 변 (세계 단위, 없으면 1.79) —— 발이 판 아래 끝. 그림 한 칸이 이 크기를 덮는다
static var sprites_enabled := false   # 지금 그림은 3D 를 찍은 임시라 끈다 —— 일러스트 그림(prompts/병사_스프라이트)이 오면 true
# 구운 3D 병사 (10/31 사용자: 무료 3D 에셋 —— KayKit CC0) : assets/models/vat/<병종>_mesh.res 가 있으면 그 병종 병사는 이것으로 (그림 판보다 먼저)
const VAT_DIR := "res://assets/models/vat/"
static var vat_enabled := false      # 11/2 사용자: 창병 원래대로 —— 구운 병사(KayKit) 끔, 모든 병종 도형 모델
var vat_mat := {}           # 병종 -> 재질
var vat_mesh := {}          # 병종 -> 메시
var sprite_mat := {}        # 병종 -> 그림 판 재질
var _sprite_quad := {}      # 병종 -> 그림 판
var follow: Squad = null
var flat: DotView = null    # 점묘 전장 —— 있으면 화면 좌표를 이것이 정한다 (3D 는 계산만)
var _cam_attr: CameraAttributesPractical      # 먼 곳 흐림 (고품질만)
const SHOW_BANNERS := false # 부대 깃발 —— 10/31 사용자: 뺀다 (화면이 정신없다)
const AUTO_MARGIN := 0.88   # 11/4 사용자: 압도적인 스케일 —— 멀리서 넓게 (0.88) · # 11/3 사용자: 병사의 바다가 화면을 채우게 바짝 (예전 1.04) —— 자동 카메라가 부대들을 담는 거리에 곱하는 여유 —— 10/31 사용자: 18부대가 화면에 꽉 차게
## 11/4 사용자: 세로 화면에서 대각선 구도는 화면 대부분이 배경 —— 세로일 때는 아군 6시 · 적 12시로 (싸움 줄이 화면 세로를 채운다)
const PORTRAIT_YAW := 0.0
func base_yaw() -> float:
	return PORTRAIT_YAW if portrait else BASE_YAW

const BASE_YAW := -0.7854     # 기본 구도 —— 아군 7시 · 적 1시 대각선 (리그오브레전드 쪽, 10/31 사용자). 0 이면 아군 6시 · 적 12시
const AUTO_MIN := 22.0      # 자동 카메라 최소 거리 (예전 30)
const CORE_SHARE := 0.75     # 자동 카메라가 담는 부대 몫 (가운데에서 가까운 순)
const HOT_SHARE := 0.6       # 싸우는 부대가 이만큼 넘으면 그쪽만 담는다 (뒤에 처진 궁병 · 책사 하나 때문에 멀어지지 않게)
# 멀리 보기 (삼국지13) —— 카메라가 이보다 멀면 간단한 효과만: 불꽃 · 흙먼지 같은 작은 입자, 베기 초승달, 평타 화살을 뺀다.
# 대신 부대 발밑 판이 맞을 때 번쩍이고, 공격 화살표 · 행동 아이콘으로 알린다. 확대하면 자세한 효과가 돌아온다
const OVERVIEW_DIST := 40.0
const SMALL_FX := ["spark", "dust", "haze", "trail"]
var overview := true
var cfx: CombatFx           # 공격 화살표 · 베기 · 궤적 (scripts/war3d/combat_fx.gd)    # 꾹 눌러 고른 부대 —— 카메라가 계속 따라간다 (끌어서 옮기거나 두 번 누르면 풀림)
var squad_rings := {}       # 부대 key -> Decal (발밑 진영색 고리)
var _ring_tex: Texture2D


func _ready() -> void:
	rng.randomize()
	noise.seed = 21
	noise.frequency = 0.01
	noise.fractal_octaves = 4
	_environment()
	_terrain()
	_scenery()
	soldier_mat = ShaderMaterial.new()
	soldier_mat.shader = load("res://shaders/soldier.gdshader")
	soldier_mat.set_shader_parameter("team_a", TEAM.A)
	soldier_mat.set_shader_parameter("team_b", TEAM.B)
	for tag in Squad.CLS:
		body_mesh[tag] = Models.body(tag)
	_load_sprites()
	_load_vat()
	weapon_mesh = {"spear": Models.spear(), "sword": Models.sword(), "lance": Models.lance(),
		"g_glaive": Models.glaive(), "g_saber": Models.saber(), "g_lance": Models.snake_lance()}
	unit_root = Node3D.new()
	add_child(unit_root)
	cfx = CombatFx.new(self)
	add_child(cfx)
	fx_root = Node3D.new()
	add_child(fx_root)
	var am := MultiMesh.new()
	am.transform_format = MultiMesh.TRANSFORM_3D
	am.use_custom_data = true
	am.mesh = Models.arrow()
	am.instance_count = 900
	for i in am.instance_count:
		am.set_instance_transform(i, HIDDEN)
	arrow_mmi = MultiMeshInstance3D.new()
	arrow_mmi.multimesh = am
	arrow_mmi.material_override = soldier_mat
	arrow_mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(arrow_mmi)
	var g := GradientTexture2D.new()
	g.width = 64
	g.height = 64
	g.fill = GradientTexture2D.FILL_RADIAL
	g.fill_from = Vector2(0.5, 0.5)
	g.fill_to = Vector2(1.0, 0.5)
	var gr := Gradient.new()
	gr.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
	g.gradient = gr
	_soft = g
	ult = UltFx.new(self)
	cam = Camera3D.new()
	cam.attributes = _cam_attr          # 품질 설정이 카메라보다 먼저 만들었으면 붙인다
	cam.fov = 50
	cam.far = 2000
	add_child(cam)
	cam.current = true
	_update_cam(1.0)


# ───────── 무대 ─────────

## 지형 높이 —— 격자가 있으면 격자에서 보간한다 (노이즈를 매번 다시 계산하지 않는다)
func height(x: float, z: float) -> float:
	return _base_h(x, z) + _bump(x, z)


## 언덕 둔덕 —— 가운데 HILL_H, 가장자리로 부드럽게
func _bump(x: float, z: float) -> float:
	var h := 0.0
	for hl in _hills:
		var d := Vector2(x, z).distance_to(hl[0])
		if d < hl[1]:
			h = maxf(h, HILL_H * smoothstep(hl[1], hl[1] * 0.45, d))
	return h


func _base_h(x: float, z: float) -> float:
	if _hn == 0:
		return height_exact(x, z)
	var fx := clampf((x + _hhalf) / _hstep, 0.0, _hn - 0.001)
	var fz := clampf((z + _hhalf) / _hstep, 0.0, _hn - 0.001)
	var i := int(fx)
	var j := int(fz)
	var u := fx - i
	var v := fz - j
	var w := _hn + 1
	var a := _hs[j * w + i]
	var b := _hs[j * w + i + 1]
	var c := _hs[(j + 1) * w + i]
	var d := _hs[(j + 1) * w + i + 1]
	return lerpf(lerpf(a, b, u), lerpf(c, d, u), v)


func height_exact(x: float, z: float) -> float:
	var r := Vector2(x * 0.8, z * 1.5).length()
	var hill := smoothstep(68.0, 175.0, r)
	var n := noise.get_noise_2d(x, z) * 0.5 + 0.5
	return noise.get_noise_2d(x * 2.1 + 300.0, z * 2.1) * 0.45 + hill * (6.0 + n * 26.0)


func _environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	# 10/31 사용자: 카툰 느낌을 벗는다 → 실제 하늘 사진(HDRI, Poly Haven CC0 kloofendal_48d_partly_cloudy_puresky). 주변광도 여기서
	var psm := PanoramaSkyMaterial.new()
	psm.panorama = load("res://assets/terrain/sky.hdr")
	psm.energy_multiplier = 0.9
	sky.sky_material = psm
	sky.radiance_size = Sky.RADIANCE_SIZE_256
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.5
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 0.95
	env.tonemap_white = 6.0
	env.ssao_enabled = false        # set_quality 가 켠다 (Forward+ 에서만)
	env.ssao_intensity = 1.6
	env.ssao_radius = 1.2
	env.glow_enabled = true
	env.glow_intensity = 0.32
	env.glow_bloom = 0.04
	env.fog_enabled = true
	env.fog_light_color = Color("#a3a59e")
	env.fog_density = 0.0016
	env.fog_aerial_perspective = 0.35
	env.fog_sky_affect = 0.25
	env.volumetric_fog_enabled = false
	env.volumetric_fog_density = 0.0012
	env.volumetric_fog_albedo = Color("#c8d0d8")
	env.volumetric_fog_length = 220
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.0
	env.adjustment_contrast = 1.04
	env.adjustment_brightness = 1.0
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	_env = env
	var sun := DirectionalLight3D.new()
	_sun = sun
	sun.light_color = Color("#efe2c8")
	sun.light_energy = 1.8
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 240
	sun.shadow_blur = 1.5
	add_child(sun)
	sun.look_at_from_position(Vector3(-45, 78, 62), Vector3.ZERO)
	set_quality(Settings.quality if Settings.quality >= 0 else 2)     # 설정을 안 읽은 점검 화면(main.tscn)은 높음


## 품질 —— 0 낮음: SSAO·볼류메트릭 안개 끔, 그림자 거리 줄임 (모바일 렌더러는 둘 다 지원하지 않는다)
func set_quality(q: int) -> void:
	if _env == null:
		return
	# 모델 분할이 바뀌었으면 몸통을 다시 굽는다 (다음 setup 부터 —— 장수 몸통은 setup 때 굽는다)
	if q != _model_q:
		_model_q = q
		for tag in Squad.CLS:
			body_mesh[tag] = Models.body(tag)
		for bk in body_mesh.keys():
			if str(bk).begins_with("G:"):
				body_mesh.erase(bk)
	_env.ssao_enabled = false        # 11/2 깔끔한 톤: 그늘 잡음 · 깜빡임이 지글거림으로 보여 끈다
	_env.volumetric_fog_enabled = false
	_env.glow_enabled = q >= 1
	# 10/31 후처리 (고품질 · Forward+): 간접광(SSIL) · 진한 그늘 · 먼 곳 흐림 —— 실사 땅 · 나무와 맞춘다
	_env.ssil_enabled = false
	_env.ssil_intensity = 0.7
	_env.ssil_radius = 6.0
	_env.ssao_intensity = 2.2
	_env.ssao_radius = 1.6
	_env.volumetric_fog_density = 0.0018
	if false:      # 먼 곳 흐림도 끈다 (깔끔한 톤)
		if _cam_attr == null:
			_cam_attr = CameraAttributesPractical.new()
			_cam_attr.dof_blur_far_enabled = true
			_cam_attr.dof_blur_far_transition = 60.0
			_cam_attr.dof_blur_amount = 0.05
		if cam:
			cam.attributes = _cam_attr
	else:
		_cam_attr = null
		if cam:
			cam.attributes = null
	_sun.directional_shadow_max_distance = [140.0, 200.0, 240.0][clampi(q, 0, 2)]
	_sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS if q == 0 else DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS


func _terrain() -> void:
	var N := 200
	var size := 640.0
	var step := size / N
	var hs := PackedFloat32Array()
	hs.resize((N + 1) * (N + 1))
	for j in N + 1:
		for i in N + 1:
			hs[j * (N + 1) + i] = height_exact(-size / 2 + i * step, -size / 2 + j * step)
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var cols := PackedColorArray()
	verts.resize(hs.size())
	norms.resize(hs.size())
	cols.resize(hs.size())
	for j in N + 1:
		for i in N + 1:
			var x := -size / 2 + i * step
			var z := -size / 2 + j * step
			var y := hs[j * (N + 1) + i]
			var hl := hs[j * (N + 1) + maxi(i - 1, 0)]
			var hr := hs[j * (N + 1) + mini(i + 1, N)]
			var hd := hs[maxi(j - 1, 0) * (N + 1) + i]
			var hu := hs[mini(j + 1, N) * (N + 1) + i]
			var nn := Vector3(hl - hr, 2 * step, hd - hu).normalized()
			var k := j * (N + 1) + i
			verts[k] = Vector3(x, y, z)
			norms[k] = nn
			var n2 := noise.get_noise_2d(x * 1.7 + 77.0, z * 1.7) * 0.5 + 0.5
			var c := Color(0.33, 0.43, 0.23).lerp(Color(0.40, 0.46, 0.26), n2)       # 11/2 깔끔한 풀빛 (얼룩은 완만하게)
			var n3 := noise.get_noise_2d(x * 3.1 - 40.0, z * 3.1) * 0.5 + 0.5
			var trample := (1.0 - smoothstep(22.0, 58.0, absf(x))) * (1.0 - smoothstep(16.0, 34.0, absf(z))) * clampf(n3 * 1.6 - 0.2, 0, 1)
			c = c.lerp(Color(0.52, 0.47, 0.34), trample * 0.5)
			var slope := 1.0 - nn.y
			c = c.lerp(Color(0.50, 0.49, 0.42), smoothstep(0.18, 0.42, slope) * 0.7)
			c = c.lerp(Color(0.30, 0.40, 0.24), smoothstep(80.0, 200.0, Vector2(x * 0.8, z * 1.5).length()) * 0.5)
			c.a = clampf(trample * 0.9 + smoothstep(0.15, 0.4, slope) + (n3 - 0.55) * 0.6, 0.0, 1.0)     # 실사 지형의 진흙 비율 (terrain.gdshader)
			cols[k] = c
	var idx := PackedInt32Array()
	for j in N:
		for i in N:
			var a := j * (N + 1) + i
			var b := a + 1
			var c := a + N + 1
			var d := c + 1
			idx.append_array([a, b, c, b, d, c])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_COLOR] = cols
	arr[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/terrain.gdshader")
	var tex := NoiseTexture2D.new()
	tex.seamless = true
	tex.width = 256
	tex.height = 256
	tex.generate_mipmaps = true
	var fn := FastNoiseLite.new()
	fn.frequency = 0.03
	fn.fractal_octaves = 4
	tex.noise = fn
	mat.set_shader_parameter("detail", tex)
	for t in ["grass", "mud"]:      # 실사 지형 텍스처 (Poly Haven CC0 —— assets/terrain/출처.txt)
		for part in ["diff", "nor", "rough"]:
			mat.set_shader_parameter("%s_%s" % [t, part], load("res://assets/terrain/%s_%s.jpg" % [t, part]))
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.material_override = mat
	add_child(mi)
	_hs = hs
	_hn = N
	_hstep = step
	_hhalf = size / 2


func _vc_mat() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	m.roughness = 0.92
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


func _scatter(mesh: Mesh, xforms: Array, shadow := true) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.material_override = _vc_mat()
	if not shadow:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


func _place(x: float, z: float, s: float) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * s), Vector3(x, height(x, z) - 0.05, z))


## 전장 밖 —— 숲 덤불, 흩어진 나무, 바위, 풀포기, 먼 산
func _scenery() -> void:
	var r2 := RandomNumberGenerator.new()
	r2.seed = 5
	var outside := func(x: float, z: float) -> bool: return Vector2(x * 0.8, z * 1.5).length() > 72.0
	# 숲 덤불
	var pines := [[], [], []]
	var leafs := [[], [], []]
	for c in 26:
		var a := r2.randf() * TAU
		var d := r2.randf_range(85.0, 230.0)
		var cx := cos(a) * d
		var cz := sin(a) * d * 0.62
		for t in r2.randi_range(12, 30):
			var x := cx + r2.randf_range(-22, 22)
			var z := cz + r2.randf_range(-16, 16)
			if not outside.call(x, z):
				continue
			var xf := _place(x, z, r2.randf_range(0.8, 1.5))
			if r2.randf() < 0.6:
				pines[r2.randi() % 3].append(xf)
			else:
				leafs[r2.randi() % 3].append(xf)
	for t in 90:
		var x := r2.randf_range(-260, 260)
		var z := r2.randf_range(-170, 170)
		if outside.call(x, z):
			leafs[r2.randi() % 3].append(_place(x, z, r2.randf_range(0.7, 1.3)))
	for i in 3:
		# 10/31 실사 나무 판 (구운 그림이 없으면 예전 도형 나무)
		if not _tree_boards(self, "pine", pines[i], r2):
			_scatter(Models.pine(r2), pines[i], false)       # 10/31 나무 그림자 끔 —— 짙은 얼룩이 산만했다
		if not _tree_boards(self, "leaf", leafs[i], r2):
			_scatter(Models.broadleaf(r2), leafs[i], false)
	# 들판 덤불 —— 실사 덤불 그림을 흩어 깐다 (전장 안은 듬성듬성)
	var shrubs := []
	for t in 520:
		var x := r2.randf_range(-300, 300)
		var z := r2.randf_range(-200, 200)
		if outside.call(x, z) or r2.randf() < 0.35:
			shrubs.append(_place(x, z, r2.randf_range(0.7, 1.6)))
	_tree_boards(self, "shrub", shrubs, r2)
	# 바위 —— 전장 안에는 작게
	var rocks := [[], []]
	for t in 160:
		var x := r2.randf_range(-200, 200)
		var z := r2.randf_range(-130, 130)
		var big: bool = outside.call(x, z)
		rocks[t % 2].append(_place(x, z, r2.randf_range(0.8, 3.2) if big else r2.randf_range(0.15, 0.45)))
	for i in 2:
		_scatter(Models.rock(r2), rocks[i])
	# 풀포기
	var tufts := []
	for t in 3000:      # 11/2 잔 풀포기가 멀리서 지글거린다 → 줄임
		var x := r2.randf_range(-140, 140)
		var z := r2.randf_range(-95, 95)
		tufts.append(_place(x, z, r2.randf_range(0.7, 1.7)))
	_scatter(Models.grass(r2), tufts, false)
	# 먼 산 —— 안개에 묻혀 깊이를 준다
	for i in 16:
		var a := TAU * i / 16 + r2.randf_range(-0.12, 0.12)
		var d := r2.randf_range(380, 560)
		var mi := MeshInstance3D.new()
		mi.mesh = Models.mountain(r2, r2.randf_range(100, 170), r2.randf_range(70, 150))
		mi.material_override = _vc_mat()
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.position = Vector3(cos(a) * d, 0, sin(a) * d * 0.8)
		add_child(mi)


# ───────── 부대 배치 ─────────

func slot_pos(camp: String, form: String, slot: int) -> Vector2:
	var s: Dictionary = DB.FORM[form].slots[slot]
	var x: float = GAP / 2 + s.row * RS
	return Vector2(-x if camp == "A" else x, (s.col - 1) * CS)


func clear() -> void:
	for m in gpu_mmi:
		if is_instance_valid(m):
			m.queue_free()
	gpu_mmi.clear()
	_flyers.clear()
	_cpu_list.clear()
	focus_sq = null
	focus_t = 0.0
	for k in slow_marks:
		for x in slow_marks[k]:
			if is_instance_valid(x):
				x.queue_free()
	slow_marks.clear()
	for c in unit_root.get_children():
		c.queue_free()
	for c in fx_root.get_children():
		c.queue_free()
	squads.clear()
	order.clear()
	entries.clear()
	bodies.clear()
	weapons.clear()
	banners.clear()
	squad_rings.clear()
	auras.clear()
	arrows.clear()
	orbs.clear()
	lights.clear()
	rings.clear()
	for a in areas:
		if is_instance_valid(a.n):
			a.n.queue_free()
	areas.clear()
	fx_nodes.clear()
	ult.clear()
	if cfx:
		cfx.clear()
	for i in arrow_mmi.multimesh.instance_count:
		arrow_mmi.multimesh.set_instance_transform(i, HIDDEN)
	clock = 0.0


func setup(res: Dictionary) -> void:
	_swirl()                # 11/3 이감 텍스처를 미리 (처음 걸릴 때 프레임이 튀었다)
	clear()
	_gpu = gpu_mode and not (Settings.dots or Settings.type2)
	Squad.gpu = _gpu
	track_mode = res.get("rt", false)
	_build_terrain(res.get("terrain", []))
	for r in res.roster:
		var at := slot_pos(r.camp, res.aForm if r.camp == "A" else res.bForm, r.slot)
		var sq := Squad.new(r, at, rng)
		if track_mode:
			# 실시간 엔진 —— 진형 자리에서 시작해 엔진 위치를 따른다
			sq.puppet = true
			sq.pgoal = at
			sq.pfwd = Vector2(1, 0) if r.camp == "A" else Vector2(-1, 0)
		else:
			sq.pos = at + (Vector2(-160, 0) if r.camp == "A" else Vector2(160, 0))
			for s in sq.all_figures():
				s.pos = sq.pos + (s.pos - at)
			sq.goal = at
			sq.state = "move"
		squads[r.key] = sq
		order.append(sq)
	# 병종별 인스턴스 수를 세고 자리를 나눈다
	var count := {}
	var wcount := {}
	for sq in order:
		for s in sq.all_figures():
			var gen: bool = s == sq.general
			var wk: String = WEAPON.get(sq.tag, "") if gen or not (sprite_mat.has(sq.tag) or vat_mesh.has(sq.tag) or cube_mode) else ""     # 그림 · 구운 병사는 무기가 몸에 있다 (큐브는 무기 없음)
			var bk: String = sq.tag
			if gen:
				bk = "G:" + sq.tag              # 장수는 군마 탄 전용 모델
				wk = Models.general_weapon(sq.tag)
				if not body_mesh.has(bk):
					body_mesh[bk] = Models.general(sq.tag)
			var idx: int = count.get(bk, 0)
			count[bk] = idx + 1
			var widx := -1
			if wk != "":
				widx = wcount.get(wk, 0)
				wcount[wk] = widx + 1
			# [부대, 병사, 병종, 번호, 무기, 무기번호, 장수, 정착(더 이상 안 변함), 기병]
			entries.append([sq, s, bk, idx, wk, widx, gen, false, sq.cls == "cav" or gen, not gen and vat_mesh.has(sq.tag), false])
		banners[sq.key] = _make_banner(sq)
		squad_rings[sq.key] = _make_ring(sq)
	_bufs.clear()
	for tag in count:
		if vat_mesh.has(tag):
			bodies[tag] = _mm(vat_mesh[tag], count[tag])
			bodies[tag].material_override = vat_mat[tag]
		elif sprite_mat.has(tag):
			bodies[tag] = _mm(_sprite_quad[tag], count[tag])
			bodies[tag].material_override = sprite_mat[tag]
			bodies[tag].cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		elif cube_mode and not tag.begins_with("G:"):
			bodies[tag] = _mm(_cube_mesh(), count[tag])
		else:
			bodies[tag] = _mm(body_mesh[tag], count[tag])
		_bufs[tag] = _new_buf(count[tag])
	for wk in wcount:
		weapons[wk] = _mm(weapon_mesh[wk], wcount[wk])
		_bufs[wk] = _new_buf(wcount[wk])
	_entry_of.clear()
	for e in entries:
		_entry_of[e[1]] = e
	_cpu_full = true
	if _gpu:
		_gpu_build()
	_sync()


## 구운 3D 병사 읽기 —— 메시 · 정점 위치/법선 이미지 · 동작 표(json) · 팔레트
func _load_vat() -> void:
	vat_mat.clear()
	vat_mesh.clear()
	if not vat_enabled:
		return
	var sh := load("res://shaders/soldier_vat.gdshader")
	for tag in Squad.CLS:
		var base: String = VAT_DIR + tag
		if not ResourceLoader.exists(base + "_mesh.res") or not FileAccess.file_exists(base + ".json"):
			continue
		var info = JSON.parse_string(FileAccess.get_file_as_string(base + ".json"))
		var m := ShaderMaterial.new()
		m.shader = sh
		m.set_shader_parameter("vat_pos", ImageTexture.create_from_image(load(base + "_pos.res")))
		m.set_shader_parameter("vat_nrm", ImageTexture.create_from_image(load(base + "_nrm.res")))
		m.set_shader_parameter("palette", load(info.texture))
		m.set_shader_parameter("team_a", TEAM.A)
		m.set_shader_parameter("team_b", TEAM.B)
		m.set_shader_parameter("bright", float(info.get("bright", 1.0)))
		for c in info.clips:
			m.set_shader_parameter("clip_" + c, Vector2(info.clips[c][0], info.clips[c][1]))
		vat_mat[tag] = m
		vat_mesh[tag] = load(base + "_mesh.res")


## 병사 그림 묶음 읽기 —— 있는 병종만 (없으면 그 병종은 3D 모델)
func _load_sprites() -> void:
	sprite_mat.clear()
	if not sprites_enabled:
		return
	var sh := load("res://shaders/soldier_sprite.gdshader")
	for tag in Squad.CLS:
		var path: String = SPRITE_DIR + tag + ".png"
		var tex: Texture2D = null
		if ResourceLoader.exists(path):
			tex = load(path)
		elif FileAccess.file_exists(path):
			var img := Image.load_from_file(path)
			if img:
				img.generate_mipmaps()
				tex = ImageTexture.create_from_image(img)
		if tex == null:
			continue
		var q := QuadMesh.new()
		var side: float = SPRITE_H.get(tag, 1.79)
		q.size = Vector2(side, side)
		q.center_offset = Vector3(0, side * 0.5, 0)
		_sprite_quad[tag] = q
		var m := ShaderMaterial.new()
		m.shader = sh
		m.set_shader_parameter("atlas", tex)
		m.set_shader_parameter("team_a", TEAM.A)
		m.set_shader_parameter("team_b", TEAM.B)
		sprite_mat[tag] = m


## 큐브 병사 (11/3 시험) —— 인형 대신 상자 하나, 무기 없음. 셰이더는 그대로 (UV 0 이라 팔다리 흔들기 없음, 정점 색 흰색 → 전부 세력색)
static var cube_mode := false
var _cube: Mesh = null
func _cube_mesh() -> Mesh:
	if _cube:
		return _cube
	var bm := BoxMesh.new()
	bm.size = Vector3(0.55, 1.5, 0.55)
	var arr := bm.get_mesh_arrays()
	var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	for i in v.size():
		v[i].y += 0.75
	arr[Mesh.ARRAY_VERTEX] = v
	var n := v.size()
	var uv := PackedVector2Array(); uv.resize(n)
	arr[Mesh.ARRAY_TEX_UV] = uv
	arr[Mesh.ARRAY_TEX_UV2] = uv
	var col := PackedColorArray(); col.resize(n); col.fill(Color(0.85, 0.85, 0.85, 1.0))
	arr[Mesh.ARRAY_COLOR] = col
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	am.surface_set_material(0, body_mesh.values()[0].surface_get_material(0) if not body_mesh.is_empty() else null)
	_cube = am
	return am


## GPU 병사 만들기 —— 병종 · 무기마다 MultiMesh 하나, 인스턴스마다 (부대 줄, 자리, 씨앗, 옷 밝기) 만 한 번 적는다
const SQ_COLS := 8
const CORPSE_LIFE := 4.0      # 시신이 누워 있는 시간 (초) —— 그 뒤 CORPSE_SINK 초 동안 가라앉아 사라진다
const CORPSE_SINK := 1.6
var _gidx := {}             # 병사 -> [[MultiMesh, 번호], …] (몸 · 무기)
func _gpu_build() -> void:
	if _gpu_mat == null:
		_gpu_mat = ShaderMaterial.new()
		_gpu_mat.shader = load("res://shaders/soldier_gpu.gdshader")
	_gpu_mat.set_shader_parameter("team_a", TEAM.A)
	_gpu_mat.set_shader_parameter("team_b", TEAM.B)
	# 높이 —— 지형 격자를 그대로 텍스처로 (언덕 포함)
	var hn: int = maxi(_hn, 64)
	var half: float = _hhalf if _hn > 0 else 60.0
	var step: float = (half * 2.0) / hn
	var himg := Image.create(hn + 1, hn + 1, false, Image.FORMAT_RF)
	for j in hn + 1:
		for i in hn + 1:
			himg.set_pixel(i, j, Color(height(-half + i * step, -half + j * step), 0, 0))
	_h_tex = ImageTexture.create_from_image(himg)
	_gpu_mat.set_shader_parameter("height_tex", _h_tex)
	_gpu_mat.set_shader_parameter("h_half", half)
	_gpu_mat.set_shader_parameter("h_size", half * 2.0)
	_sq_img = Image.create(SQ_COLS, maxi(1, order.size()), false, Image.FORMAT_RGBAF)
	_sq_tex = ImageTexture.create_from_image(_sq_img)
	_gpu_mat.set_shader_parameter("squad_tex", _sq_tex)
	# 병종 · 무기별로 모은다
	var groups := {}          # 열쇠 -> [[부대 줄, 병사], …]
	for row in order.size():
		var sq: Squad = order[row]
		var wk: String = "" if cube_mode else WEAPON.get(sq.tag, "")
		for sd in sq.soldiers:
			if not groups.has(sq.tag): groups[sq.tag] = []
			groups[sq.tag].append([row, sd])
			if wk != "":
				if not groups.has("W:" + wk): groups["W:" + wk] = []
				groups["W:" + wk].append([row, sd])
	var big := AABB(Vector3(-120, -20, -120), Vector3(240, 80, 240))
	_gidx.clear()
	for row in order.size():
		var sq0: Squad = order[row]
		sq0.gpos_slow = sq0.pos
		sq0.gfwd_slow = sq0.fwd
		for sd in sq0.soldiers:
			sd.gseed = rng.randf()
			sd.slot_old = -1
			_gidx[sd] = []
	for key in groups:
		var lst: Array = groups[key]
		var weapon: bool = key.begins_with("W:")
		var mesh: Mesh
		var mat: ShaderMaterial = _gpu_mat
		if weapon:
			var wk: String = key.substr(2)
			mesh = weapon_mesh[wk]
			mat = _gpu_mat.duplicate()
			mat.set_shader_parameter("is_weapon", true)
			mat.set_shader_parameter("weapon_kind", {"spear": 0, "sword": 1, "lance": 2}.get(wk, 0))
			mat.set_shader_parameter("hand", HAND[wk])
			mat.set_shader_parameter("pivot", ARM_PIVOT[wk])
		else:
			mesh = _cube_mesh() if cube_mode else body_mesh[key]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_custom_data = true
		mm.mesh = mesh
		mm.instance_count = lst.size()
		var buf := PackedFloat32Array()
		buf.resize(lst.size() * 16)
		for i in lst.size():
			var sd = lst[i][1]
			_put(buf, i * 16, Basis.IDENTITY, Vector3.ZERO, float(lst[i][0]), _gslot(sd), sd.gseed, sd.move_t)
			_gidx[sd].append([mm, i])
		mm.buffer = buf
		mm.custom_aabb = big
		var mi := MultiMeshInstance3D.new()
		mi.multimesh = mm
		mi.material_override = mat
		mi.layers = 2
		mi.custom_aabb = big
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if weapon else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		unit_root.add_child(mi)
		gpu_mmi.append(mi)
	_gpu_sync(0.0)


## 병사 자리 값 —— 숨김 −1, 아니면 지금 자리 + (전 자리 + 1) × 1024 (걸어 나오는 중이면 셰이더가 둘 사이를 잇는다)
static func _gslot(sd) -> float:
	if not sd.alive:
		return -1.0
	return float(sd.slot) + float(sd.slot_old + 1) * 1024.0


## 부대끼리 겹치지 않게 (11/3 사용자: 유닛들이 충돌하지 않고 막 겹쳐져 어색하다) —— 부대마다 대열 반폭 · 반깊이를 재고,
## 이웃 부대가 그 안으로 들어오면 그쪽 축(앞뒤 또는 좌우)으로 대열 간격을 좁힌다. 맞붙은 적은 앞줄이 섞이게 덜 좁힌다.
## 병사가 사라지지 않고 더 빽빽해진다 (군집). 판정 · 부대 위치는 그대로
const SQUEEZE_MIN := 0.42
func _squeeze(dt: float) -> void:
	var k := 1.0 - exp(-dt * 3.0)
	for a in order:
		if not a.alive or a.state == "gone":
			continue
		var hw: float = a.cols * a.sp * 0.5 + 2.0           # 반폭 (좌우)
		var hd: float = a._rk * a.sp * 0.92 * 0.5 + 2.0      # 반깊이 (앞뒤)
		var want := Vector2.ONE
		var rgt: Vector2 = a.right()
		for b in order:
			if b == a or not b.alive or b.state == "gone":
				continue
			var d: Vector2 = b.pos - a.pos
			var dx: float = absf(d.dot(a.fwd))
			var dy: float = absf(d.dot(rgt))
			var bh: float = maxf(b.cols * b.sp * b.gsq.y, b._rk * b.sp * 0.92 * b.gsq.x) * 0.5
			var foe_touch: bool = b.camp != a.camp and (a.engaged == b or b.engaged == a)
			var share := 0.62 if foe_touch else 0.5        # 맞붙은 적과는 조금 겹쳐 섞인다
			if dx > hd + bh or dy > hw + bh:
				continue
			if dy * hd > dx * hw:     # 옆으로 붙었다 → 좌우를 좁힌다
				want.y = minf(want.y, (dy * share) / hw)
			else:                     # 앞뒤로 붙었다 → 깊이를 좁힌다
				want.x = minf(want.x, (dx * share) / hd)
		want = want.clamp(Vector2(SQUEEZE_MIN, SQUEEZE_MIN), Vector2.ONE)
		a.gsq = a.gsq.lerp(want, k)


## 부대 값을 한 줄씩 (부대 수 × 6 칸) —— 매 프레임 이것만 GPU 로
func _gpu_sync(dt: float) -> void:
	if _sq_img == null or _sq_img.get_height() < order.size():
		return
	_squeeze(dt)
	var shove_k := exp(-dt * 5.0)
	var slow_p := 1.0 - exp(-dt * 1.6)       # 늦게 따라오는 위치 · 방향 (뒷줄 · 가장자리 병사가 이쪽에 가깝다)
	var slow_f := 1.0 - exp(-dt * 1.1)
	for row in order.size():
		var sq: Squad = order[row]
		sq.shove_v *= shove_k
		sq.gpos_slow = sq.gpos_slow.lerp(sq.pos, slow_p)
		sq.gfwd_slow = sq.gfwd_slow.lerp(sq.fwd, slow_f).normalized()
		for sd in sq.moved_figs:
			for gi in _gidx.get(sd, []):
				gi[0].set_instance_custom_data(gi[1], Color(row, _gslot(sd), sd.gseed, sd.move_t))
		sq.moved_figs.clear()
		var gone: bool = sq.state == "gone"
		var n_alive: float = 0.0 if gone else float(sq._alive)
		var ready: bool = sq.contact or (sq.engaged != null and sq.pos.distance_to(sq.engaged.pos) < 140.0)
		var flags := (1 if sq.armor_broken else 0) + (2 if sq == focus_sq and focus_t > 0.0 else 0)
		var bfl := clampf(1.0 - (clock - sq.break_t) / 0.3, 0.0, 1.0)
		_sq_img.set_pixel(0, row, Color(sq.pos.x, sq.pos.y, sq.fwd.x, sq.fwd.y))
		sq.gfront = lerpf(sq.gfront, (sq._rk - 1) * sq.sp * 0.5, slow_p)
		_sq_img.set_pixel(1, row, Color(sq.cols, sq.sp, n_alive, sq.gfront))
		_sq_img.set_pixel(2, row, Color(sq.walk_acc, 1.0 if sq.moving else 0.0, 1.0 if sq.contact else 0.0, sq.fade if sq.state == "flee" else 1.0))
		_sq_img.set_pixel(3, row, Color(sq.shove_v, sq.hurt, flags, 1.0 if ready else 0.0))
		_sq_img.set_pixel(4, row, Color(bfl, sq.flee_t if sq.state == "flee" else 0.0, Squad.TIER_SIZE.get(sq.tier, 1.0), 1.0 if sq.cls == "cav" else 0.0))
		_sq_img.set_pixel(5, row, Color(sq.loose, 1.0 if sq.camp == "B" else 0.0, clock, sq.depth()))
		_sq_img.set_pixel(6, row, Color(sq.gpos_slow.x, sq.gpos_slow.y, sq.gfwd_slow.x, sq.gfwd_slow.y))
		_sq_img.set_pixel(7, row, Color(sq.gsq.x, sq.gsq.y, 0.0, 0.0))
	_sq_tex.update(_sq_img)


func _mm(mesh: Mesh, n: int) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = mesh
	mm.instance_count = n
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.material_override = soldier_mat
	mi.layers = 2
	unit_root.add_child(mi)
	return mi


## 발밑 고리 —— 땅에 비추는 진영색 테두리. 멀리서도 아군·적과 부대 덩어리가 읽힌다
func _make_ring(sq: Squad) -> Decal:
	if _ring_tex == null:
		var g := GradientTexture2D.new()
		g.width = 128
		g.height = 128
		g.fill = GradientTexture2D.FILL_RADIAL
		g.fill_from = Vector2(0.5, 0.5)
		g.fill_to = Vector2(1.0, 0.5)
		var gr := Gradient.new()
		gr.offsets = PackedFloat32Array([0.0, 0.8, 0.9, 0.95, 1.0])
		gr.colors = PackedColorArray([Color(1, 1, 1, 0.0), Color(1, 1, 1, 0.03), Color(1, 1, 1, 0.38), Color(1, 1, 1, 0.12), Color(1, 1, 1, 0)])     # 10/30 옅고 가늘게 (화면을 덮었다)
		g.gradient = gr
		_ring_tex = g
	var d := Decal.new()
	d.texture_albedo = _block_tex()
	d.modulate = TEAM[sq.camp].lightened(0.1)
	d.albedo_mix = 0.85
	d.cull_mask = 1
	d.upper_fade = 0.4
	d.lower_fade = 0.4
	d.distance_fade_enabled = false
	unit_root.add_child(d)
	return d


func _make_banner(sq: Squad) -> Node3D:
	var root := Node3D.new()
	var pole := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.035
	cm.bottom_radius = 0.05
	cm.height = 4.4
	cm.radial_segments = 6
	pole.mesh = cm
	pole.position = Vector3(0, 2.2, 0)
	var pm := StandardMaterial3D.new()
	pm.albedo_color = Color(0.3, 0.22, 0.14)
	pole.material_override = pm
	root.add_child(pole)
	var flag := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(1.6, 1.1)
	plane.orientation = PlaneMesh.FACE_Z
	plane.subdivide_width = 10
	flag.mesh = plane
	flag.position = Vector3(0.8, 3.75, 0)
	var fm := ShaderMaterial.new()
	fm.shader = load("res://shaders/flag.gdshader")
	var fc: Color = DB.fac_color(sq.row.fac) if sq.tier > 2 else TEAM[sq.camp].darkened(0.25)
	fm.set_shader_parameter("color", fc)
	fm.set_shader_parameter("phase", rng.randf() * TAU)
	flag.material_override = fm
	root.add_child(flag)
	var lb := Label3D.new()
	lb.text = DB.person(sq.cid).substr(0, 1) if sq.tier > 2 else sq.tag.substr(0, 1)
	lb.font = DB.font_display
	lb.font_size = 96
	lb.pixel_size = 0.0065
	lb.outline_size = 14
	lb.modulate = Color(1, 0.97, 0.9)
	lb.position = Vector3(0.8, 3.75, 0.03)
	root.add_child(lb)
	# 진영 띠 —— 깃대 꼭대기의 작은 술
	var tip := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.09
	sm.height = 0.18
	tip.mesh = sm
	var tm := StandardMaterial3D.new()
	tm.albedo_color = TEAM[sq.camp]
	tm.emission_enabled = true
	tm.emission = TEAM[sq.camp]
	tm.emission_energy_multiplier = 0.6
	tip.material_override = tm
	tip.position = Vector3(0, 4.45, 0)
	if sq.tier >= 6:        # 11/2 초월 위는 깃대 꼭대기 술이 등급색으로 빛난다
		var tcol: Color = DB.TIER[sq.tier].c
		tm.albedo_color = tcol
		tm.emission = tcol
		tm.emission_energy_multiplier = 1.6 + (sq.tier - 6) * 0.8
		tip.scale = Vector3.ONE * (1.6 + (sq.tier - 6) * 0.5)
		root.scale = Vector3.ONE * (1.1 + (sq.tier - 6) * 0.12)
	root.add_child(tip)
	unit_root.add_child(root)
	return root


# ───────── 매 프레임 ─────────

func _process(dt: float) -> void:
	var tp := Time.get_ticks_usec()
	_process_inner(dt)
	pt("[카메라·효과배속]", tp)


func _process_inner(dt: float) -> void:
	if _intro > 0:
		_intro -= dt
		if _intro <= 0:
			cam_rate = 4.0
	if _cine > 0:
		_cine -= dt
		if _cine <= 0 and not _cine_back.is_empty():
			want_t = _cine_back[0]
			want_dist = _cine_back[1]
			want_pitch = _cine_back[2]
			if _cine_back.size() > 3:
				want_yaw = _cine_back[3]
			cam_rate = 2.5
	if active:
		var mv := Vector3.ZERO
		var fw := Vector3(cos(want_yaw), 0, sin(want_yaw))
		var rt := Vector3(-sin(want_yaw), 0, cos(want_yaw))
		if Input.is_key_pressed(KEY_W): mv += fw
		if Input.is_key_pressed(KEY_S): mv -= fw
		if Input.is_key_pressed(KEY_D): mv += rt
		if Input.is_key_pressed(KEY_A): mv -= rt
		if Input.is_key_pressed(KEY_Q): want_yaw -= dt * 1.2
		if Input.is_key_pressed(KEY_E): want_yaw += dt * 1.2
		if mv != Vector3.ZERO or Input.is_key_pressed(KEY_Q) or Input.is_key_pressed(KEY_E):
			_manual = MANUAL_HOLD
		want_t += mv * dt * want_dist * 0.9
	if follow != null:
		if follow.state == "gone" or not follow.alive and follow.state != "flee":
			follow = null
		elif _cine <= 0:
			var fp := p3(follow.pos)
			want_t = Vector3(fp.x, 0, fp.z)
			_manual = MANUAL_HOLD
	if _manual > 0:
		_manual -= dt
	elif director and _intro <= 0 and _cine <= 0 and not order.is_empty() and Engine.get_process_frames() % 3 == 0:
		_auto_frame()       # 세 프레임에 한 번 —— 카메라는 어차피 천천히 따라간다
	_update_cam(dt)
	for n in fx_nodes:
		if is_instance_valid(n[0]):
			n[0].speed_scale = time_scale
	for k in auras:
		auras[k].speed_scale = time_scale


func pt(key: String, t0: int) -> int:
	var now := Time.get_ticks_usec()
	prof[key] = prof.get(key, 0) + now - t0
	return now


func step(dt: float) -> void:
	prof["_frames"] = prof.get("_frames", 0) + 1
	var t := Time.get_ticks_usec()
	for sq in order:
		sq.update(dt, clock)
	t = pt("부대갱신", t)
	for sq in order:
		if sq.impact:
			sq.impact = false
			_on_impact(sq)
		# 맞닿은 줄에서는 쉬지 않고 쇠붙이가 부딪치고 흙먼지가 인다
		if sq.contact and sq.engaged and sq.alive:
			if rng.randf() < dt * 3.5:
				_contact_fx(sq, sq.engaged, rng.randf() < 0.3)
			if rng.randf() < dt * 0.9:
				_particles(p3(sq.engaged.pos + sq.axis * sq.engaged.depth() * 0.5 + Vector2(-sq.axis.y, sq.axis.x) * rng.randf_range(-40, 40), 0.5), "haze", Color("#b09a74"))
	t = pt("효과생성", t)
	_duel_t -= dt
	if _duel_t <= 0 and not _gpu:
		_duel_t = 0.3
		_pair_duels()
	t = pt("짝짓기", t)
	_shove()
	_air(dt)
	if Engine.get_process_frames() % 2 == 0 and not _gpu:
		_crowd()
	t = pt("밀치기", t)
	_separate(dt)
	_status_fx()
	ult.step()
	_fx_step()
	cfx.step()
	t = pt("효과갱신", t)
	if _gpu:
		_gpu_sync(dt)
	if flat == null:
		_sync()              # 점묘 전장이면 3D 병사 인스턴스를 맞출 필요가 없다
	pt("동기화", t)


## 일대일 짝짓기 —— 맞닿은 두 부대의 앞줄 병사마다 가장 가까운 적 앞줄 병사를 붙인다
func _pair_duels() -> void:
	for sq in order:
		var fronts := []
		for s in sq.soldiers:
			if s.alive and sq.contact and sq.rank_of(s) < Squad.DUEL_RANKS:
				fronts.append(s)
			elif s.duel != null:
				s.duel = null
		if fronts.is_empty() or sq.engaged == null:
			continue
		var foes := []
		for s in sq.engaged.soldiers:
			if s.alive and sq.engaged.rank_of(s) < Squad.DUEL_RANKS + 1:
				foes.append(s)
		if foes.is_empty():
			continue
		for s in fronts:
			if s.duel != null and s.duel.alive and s.pos.distance_squared_to(s.duel.pos) < 400.0:
				continue
			var best = null
			var bd := 1e12
			for f in foes:
				var d: float = s.pos.distance_squared_to(f.pos)
				if d < bd:
					bd = d
					best = f
			s.duel = best
			if best.duel == null:
				best.duel = s


## 맞붙은 곳의 병사끼리 겹치지 않게 —— 격자 칸(6px)에 나눠 담고 이웃 칸만 본다. 적·아군 가리지 않는다
const CROWD_R := 4.6
func _crowd() -> void:
	var cells := {}
	var list := []
	for sq in order:
		if not sq.alive or not (sq.contact or sq.loose > 0.3):
			continue
		for s in sq.soldiers:
			if s.alive and s.air <= 0.0:
				var c := Vector2i(floori(s.pos.x / 6.0), floori(s.pos.y / 6.0))
				if cells.has(c):
					cells[c].append(s)
				else:
					cells[c] = [s]
				list.append([s, c])
	for it in list:
		var s = it[0]
		var c: Vector2i = it[1]
		for dx in [-1, 0, 1]:
			for dy in [-1, 0, 1]:
				var cl = cells.get(c + Vector2i(dx, dy))
				if cl == null:
					continue
				for o in cl:
					if o == s:
						continue
					var d: Vector2 = s.pos - o.pos
					var l := d.length()
					if l < CROWD_R and l > 0.001:
						var push: Vector2 = d / l * (CROWD_R - l) * 0.5
						s.pos += push
						o.pos -= push


## 진형 충돌의 무게감 (11/3 사용자) —— 맞닿은 두 부대가 1초 남짓마다 서로 떠민다. 병력이 많은(이기는) 쪽 앞줄은 앞으로 쏠리고,
## 지는 쪽 앞 세 줄은 뒤로 크게 밀려 대열이 찌그러졌다가 제자리로 걸어 돌아온다 —— 전선 전체가 출렁인다.
## 화면 연출만 (병사 자리) —— 판정 · 부대 위치(엔진 track)는 그대로다
const SHOVE_GAP := Vector2(0.8, 1.3)     # 떠밀기 간격 (초)
const SHOVE_PUSH := 16.0                  # 지는 쪽 앞줄이 밀리는 거리 (px, 병사 간격 약 8)
func _shove() -> void:
	for sq in order:
		var e: Squad = sq.engaged
		if not (sq.alive and sq.contact and e != null and e.alive):
			continue
		if e.engaged == sq and sq.key > e.key:
			continue        # 서로 붙은 짝은 key 가 작은 쪽이 맡는다
		if clock < sq.shove_t:
			continue
		sq.shove_t = clock + rng.randf_range(SHOVE_GAP.x, SHOVE_GAP.y)
		var r: float = sq.troops / maxf(1.0, sq.troops + e.troops)        # 0.5 위면 sq 가 민다
		var tier_w: float = 1.0 + 0.25 * (sq.tier - e.tier)                # 높은 등급은 더 세게 민다
		var win: Squad = sq if r * tier_w >= 0.5 else e
		var lose: Squad = e if win == sq else sq
		var dir: Vector2 = (lose.pos - win.pos).normalized()               # 이기는 쪽 → 지는 쪽
		var force: float = SHOVE_PUSH * clampf(0.7 + absf(r - 0.5) * 2.0, 0.7, 1.6)
		if _gpu:
			lose.shove_v = force
			win.shove_v = -force * 0.35
			lose.hurt = maxf(lose.hurt, 0.6)
		for s2 in ([] if _gpu else lose.soldiers):
			if not s2.alive or s2.air > 0.0:
				continue
			var rk: int = lose.rank_of(s2)
			if rk > 2:
				continue
			s2.pos += dir * force * (1.0 - rk * 0.28) * rng.randf_range(0.7, 1.2)
			s2.hit_t = clock + rng.randf() * 0.12          # 움찔
		for s2 in ([] if _gpu else win.soldiers):
			if not s2.alive or s2.air > 0.0 or win.rank_of(s2) > 1:
				continue
			s2.pos += dir * force * 0.35 * rng.randf_range(0.6, 1.1)
			s2.atk_t0 = clock - rng.randf() * 0.1          # 앞줄이 한꺼번에 내지른다
		var mid: Vector2 = lose.pos + (win.pos - lose.pos).normalized() * lose.depth() * 0.5
		if not overview and rng.randf() < 0.6:
			_particles(p3(mid, 0.4), "dust", Color("#b9a27a"))
		shake = maxf(shake, 0.06 if overview else 0.12)


## 고유기에 맞아 날아간 병사 —— 포물선으로 떴다가 떨어진다
func _air(dt: float) -> void:
	if _flyers.is_empty():
		return
	var keep := []
	for s in _flyers:
		if s.air > 0.0 or s.vy > 0.0:
			s.vy -= 22.0 * dt
			s.air = maxf(0.0, s.air + s.vy * dt)
			s.pos += s.kb * dt
			s.kb *= exp(-dt * 1.5)
			s.spin += s.fall * dt * 7.0
			if s.air <= 0.0 and s.vy < 0.0:
				s.vy = 0.0
				s.kb = Vector2.ZERO
				s.spin = 0.0
				s.hit_t = clock
			else:
				keep.append(s)
	_flyers = keep


## 무쌍 (10/31 사용자: 진삼국무쌍처럼 기술을 쓰면 펑펑 쓰러지는 통쾌함) —— 방금 쓰러지기로 정해진 병사들을
## 친 쪽에서 멀어지는 방향으로 한꺼번에 날린다. power 1 이 기술, 1.6 이 고유기
func blast(key: String, from_key: String, power: float) -> void:
	var sq: Squad = squads.get(key)
	if sq == null:
		return
	var f: Squad = squads.get(from_key)
	var from: Vector2 = f.pos if f and f != sq else sq.pos + sq.fwd * 40.0
	var n := 0
	for s in sq.soldiers:
		if s.alive or s.air > 0.0 or s.die_t < clock - 0.02:
			continue
		var d: Vector2 = s.pos - from
		var dir := d.normalized() if d.length() > 0.1 else Vector2.from_angle(rng.randf() * TAU)
		dir = dir.rotated(rng.randf_range(-0.7, 0.7))
		s.vy = (5.0 + rng.randf() * 7.0) * minf(power, 2.4)          # 높이는 적당히, 날아가는 거리를 키운다
		s.air = 0.01
		s.kb = dir * (50.0 + rng.randf() * 110.0) * power
		s.fall = 1.0 if rng.randf() < 0.5 else -1.0
		s.die_t = clock                # 날아가며 바로 쓰러진다
		_flyers.append(s)
		n += 1
	if n >= 3:
		shake = maxf(shake, clampf(0.08 * n / 10.0, 0.05, 0.4) * power)
		for o in sq.soldiers:          # 살아남은 병사도 움찔
			if o.alive and o.pos.distance_to(from) < 160.0 and rng.randf() < 0.4:
				o.hit_t = clock + rng.randf() * 0.2
	# 에이스 · 고유기 (power ≥ 2.5) —— 흙먼지 · 섬광 (11/3 사용자 2차: 날아갔다 돌아오는 게 이상하다 → 산 병사는 날리지 않는다)
	if power >= 2.5 and n >= 3:
		var c: Vector2 = sq.pos - sq.fwd * sq.depth() * 0.3
		_particles(p3(c, 0.5), "dust", Color("#c8b088"))
		_light(p3(c, 3.0), Color(1.0, 0.8, 0.5), 6.0, 0.3)


## 고유기 충격 —— 중심에서 가까운 병사를 공중으로 날린다. power 1 이면 몇 m 뜬다
func launch(key: String, center: Vector2, radius: float, power: float) -> void:
	var sq: Squad = squads.get(key)
	if sq == null:
		return
	for s in sq.soldiers:
		var d: Vector2 = s.pos - center
		var l := d.length()
		if l > radius or s.air > 0.0 or s.alive or s.die_t < clock - 0.6:
			continue        # 이미 다 넘어진 시신은 화면에서 다시 그리지 않으므로 날리지 않는다        # 11/3 사용자: 죽는 병사만 날아간다 (산 병사가 날아갔다 돌아오면 이상하다)
		var f := (1.0 - l / radius) * power * rng.randf_range(0.6, 1.2)
		if f < 0.15:
			continue
		s.vy = 4.0 + 9.0 * minf(f, 1.8)
		s.air = 0.01
		s.kb = (d / maxf(l, 0.1)).rotated(rng.randf_range(-0.5, 0.5)) * (40.0 + 140.0 * f)
		s.hit_t = clock
		_flyers.append(s)
		s.fall = 1.0 if rng.randf() < 0.5 else -1.0


func _separate(dt: float) -> void:
	if track_mode:
		return               # 엔진이 이미 겹치지 않게 놓았다
	for i in order.size():
		var a: Squad = order[i]
		if not a.alive:
			continue
		for j in range(i + 1, order.size()):
			var b: Squad = order[j]
			if not b.alive or a.engaged == b or b.engaged == a:
				continue
			# 10/30 —— 싸우는 중이어도 맞붙은 짝이 아니면 서로 겹치지 않게 민다 (부대가 한 덩어리로 섞이던 것)
			var fighting := a.contact or b.contact
			var rad := 62.0 if fighting else 70.0
			var d := a.pos - b.pos
			if d.length() < rad and d.length() > 0.01:
				var push := d.normalized() * (rad - d.length()) * dt * (1.8 if fighting else 3.0)
				if a.state != "hold": a.pos = a.keep_in(a.pos + push)
				if b.state != "hold": b.pos = b.keep_in(b.pos - push)


func p3(p: Vector2, lift := 0.0) -> Vector3:
	var x := p.x * S
	var z := p.y * S
	return Vector3(x, height(x, z) + lift, z)


func _new_buf(n: int) -> PackedFloat32Array:
	var b := PackedFloat32Array()
	b.resize(n * 16)
	return b


static func _put(buf: PackedFloat32Array, o: int, b: Basis, p: Vector3, c0: float, c1: float, c2: float, c3: float) -> void:
	buf[o] = b.x.x
	buf[o + 1] = b.y.x
	buf[o + 2] = b.z.x
	buf[o + 3] = p.x
	buf[o + 4] = b.x.y
	buf[o + 5] = b.y.y
	buf[o + 6] = b.z.y
	buf[o + 7] = p.y
	buf[o + 8] = b.x.z
	buf[o + 9] = b.y.z
	buf[o + 10] = b.z.z
	buf[o + 11] = p.z
	buf[o + 12] = c0
	buf[o + 13] = c1
	buf[o + 14] = c2
	buf[o + 15] = c3


static func _hide(buf: PackedFloat32Array, o: int) -> void:
	for i in 12:
		buf[o + i] = 0.0
	buf[o + 7] = -500.0


## 병사 → GPU 버퍼. 병종마다 버퍼 하나에 몰아 쓰고 프레임 끝에 한 번만 넘긴다.
## 다 쓰러진 시신과 떠나 버린 병사는 한 번 쓴 뒤로 다시 계산하지 않는다(정착).
## 사용자 값 4 개는 soldier.gdshader 머리말 참고 (진영+옷 밝기 · 어둡게/공격 · 번쩍 · 걸음 박자)
var _sync_half := 0
func _sync() -> void:
	_sync_half = 1 - _sync_half
	var bufs := {}
	for k in _bufs:
		bufs[k] = _bufs[k]
	var lst: Array = entries
	if _gpu and not _cpu_full:
		for sq0 in order:
			for f in sq0.changed_figs:
				var ce = _entry_of.get(f)
				if ce != null and not _cpu_list.has(ce):
					_cpu_list.append(ce)
			sq0.changed_figs.clear()
		lst = _cpu_list
	for e in lst:
		var sq: Squad = e[0]
		var s = e[1]
		if _gpu and not e[6] and s.alive:
			if not e[10]:          # 살아 있는 병사는 GPU 가 그린다 —— CPU 쪽은 한 번 숨겨 둔다
				var hb0: PackedFloat32Array = bufs[e[2]]
				_hide(hb0, e[3] * 16)
				bufs[e[2]] = hb0
				if e[4] != "":
					var wb0: PackedFloat32Array = bufs[e[4]]
					_hide(wb0, e[5] * 16)
					bufs[e[4]] = wb0
				e[10] = true
				e[7] = false
				s.drawn = Vector3(1e9, 0, 0)
			continue
		e[10] = false
		if e[7]:
			if s.alive and sq.state != "gone":
				e[7] = false            # 보충병으로 되살아났다
			else:
				continue
		var bbuf: PackedFloat32Array = bufs[e[2]]
		var o: int = e[3] * 16
		var wk: String = e[4]
		var dead: bool = not s.alive and s.die_t >= 0 and clock >= s.die_t
		var hidden: bool = (not s.alive and s.die_t < 0) or (not dead and sq.state == "gone")
		if hidden:
			_hide(bbuf, o)
			bufs[e[2]] = bbuf
			if wk != "":
				var hb: PackedFloat32Array = bufs[wk]
				_hide(hb, e[5] * 16)
				bufs[wk] = hb
			e[7] = sq.state == "gone"
			continue
		var walking: bool = s.walk != s.walk_drawn
		s.walk_drawn = s.walk
		var broken: bool = not dead and sq.armor_broken      # 11/3 파갑 · 쇄갑 —— 갑옷이 녹슬고 금 간 색으로
		var bflash: float = 0.0 if dead else clampf(1.0 - (clock - sq.break_t) / 0.3, 0.0, 1.0)      # 파갑이 터진 순간 (짧고 옅게)
		var spot: bool = not dead and sq == focus_sq and focus_t > 0.0                               # 비네트 집중 부대
		# 그대로 서 있고 동작도 없으면 지난번 값을 그대로 둔다
		var anim: bool = dead or clock - s.atk_t0 < Squad.ATTACK_TIME or clock - s.hit_t < 0.3 or sq.cheer \
			or (s.spawn_t >= 0 and clock - s.spawn_t < 0.5) or s.air > 0.0 or walking != s.drawn_mv or broken != s.drawn_br or bflash > 0.0 or spot
		# 11/3 병사 2,000명 —— 동작 없이 자리만 옮기는 병사는 두 조로 나눠 한 프레임씩 번갈아 쓴다 (동기화 시간 절반)
		if not anim and (e[3] & 1) != _sync_half:
			continue
		var wang := _weapon_angle(sq, s, wk, not dead) if wk != "" else 0.0
		# 눈에 띄지 않을 만큼만 움직였으면 건너뛴다 (0.5cm · 0.2도)
		if not anim and absf(s.pos.x - s.drawn.x) < 0.05 and absf(s.pos.y - s.drawn.y) < 0.05 \
				and absf(s.yaw - s.drawn.z) < 0.004 and absf(wang - s.drawn_w) < 0.01:
			continue
		s.drawn = Vector3(s.pos.x, s.pos.y, s.yaw)
		s.drawn_w = wang
		s.drawn_mv = walking
		s.drawn_br = broken
		var x: float = s.pos.x * S
		var z: float = s.pos.y * S
		var y: float = height(x, z) + s.air
		var b := Basis(Vector3.UP, -s.yaw)
		var g := 0.0                # 시신이면 어둡게(+), 살아 있으면 공격 진행(-)
		var flash := 0.0
		var settle := false
		var atk := 0.0
		var baked: bool = e[9]           # 구운 병사는 넘어지기 · 몸 기울이기가 동작에 들어 있다
		if dead:
			var u := minf(1.0, (clock - s.die_t) / 0.4)
			if not baked:
				b = b * Basis(Vector3.RIGHT, s.fall * u * PI * 0.48)
			g = 0.42 * u
			# 11/4 사용자: 시신이 사라지게 —— CORPSE_LIFE 초 뒤 땅으로 가라앉아 없어진다 (병사 5,000명이면 시신이 땅을 덮었다)
			var sink := clampf((clock - s.die_t - CORPSE_LIFE) / CORPSE_SINK, 0.0, 1.0) if s.air <= 0.0 else 0.0
			y -= sink * 1.6
			g += 0.25 * sink
			if sink >= 1.0:
				_hide(bbuf, o)
				bufs[e[2]] = bbuf
				if wk != "":
					var hb2: PackedFloat32Array = bufs[wk]
					_hide(hb2, e[5] * 16)
					bufs[wk] = hb2
				e[7] = true
				continue
		else:
			var cav: bool = e[8]
			y += absf(sin(s.walk * 0.9)) * (0.16 if cav else 0.08)
			if cav:
				b = b * Basis(Vector3.BACK, sin(s.walk * 0.45) * 0.07)
			var a: float = (clock - s.atk_t0) / Squad.ATTACK_TIME
			if a >= 0 and a <= 1:
				atk = a
				if not cav and not baked:
					b = b * Basis(Vector3.BACK, -0.28 * sin(PI * a))
			var h: float = (clock - s.hit_t) / 0.3
			if h >= 0 and h <= 1:
				if not baked:
					b = b * Basis(Vector3.BACK, 0.3 * sin(PI * h))
				flash = 0.45 * sin(PI * h)          # 맞은 병사만 번쩍인다
			if sq.cheer and s.slot % 3 == 0:
				y += maxf(0, sin(clock * 9.0 + s.phase)) * 0.35
			g = -atk
		if s.air > 0.0:
			b = b * Basis(Vector3.BACK, s.spin)     # 날아가며 뒤집힌다
		var sc: float = Squad.GEN_SIZE.get(sq.tier, 1.3) if e[6] else s.size
		if e[6] and clock < sq.flourish_t:      # 11/4 고유기 —— 휘두르는 동안 장수가 커지고 떠올라 병사 위로 보인다
			var fu := clampf((sq.flourish_t - clock) / 0.25, 0.0, 1.0) * clampf(1.0 - (sq.flourish_t - clock - 1.05) / 0.25, 0.0, 1.0)
			sc *= 1.0 + 0.3 * fu
			y += 0.25 * fu
			b = b * Basis(Vector3.UP, sin(clock * 9.0) * 0.6 * fu)
		b = b * Basis.from_scale(Vector3(sc, sc, sc))
		var p := Vector3(x, y, z)
		var r0: float = (0.0 if sq.camp == "A" else 1.0) + s.tint * 0.5
		var step_ph: float = fposmod(s.walk * 0.9 / TAU, 1.0) + (0.0 if walking else 2.0)
		if bflash > 0.0:
			flash = maxf(flash, 0.4 * bflash)
		elif spot:
			flash = maxf(flash, 0.28 + 0.12 * sin(clock * 14.0))       # 주인공 부대만 밝게
		elif broken and flash <= 0.0:
			flash = -0.7          # 셰이더: b < 0 이면 갑옷 깨짐
		_put(bbuf, o, b, p, r0, g, flash, step_ph)
		bufs[e[2]] = bbuf
		if wk != "":
			var wb: PackedFloat32Array = bufs[wk]
			var hand: Vector3 = HAND[wk]
			# 팔이 어깨를 축으로 돌면 손과 무기도 같이 돈다 (셰이더의 4 번 부위와 같은 각)
			var arm := 1.3 * sin(PI * atk)
			var piv: Vector2 = ARM_PIVOT[wk]
			var hd := Vector2(hand.x - piv.x, hand.y - piv.y).rotated(arm)
			hand = Vector3(piv.x + hd.x, piv.y + hd.y, hand.z)
			if (wk == "spear" or wk == "lance" or wk == "g_lance") and not dead and sq.contact:
				hand += Vector3(0.45 * sin(PI * atk), 0, 0)   # 찌르기
			var wbasis := b * Basis(Vector3.BACK, wang + arm * 0.5)
			_put(wb, e[5] * 16, wbasis, p + b * hand, r0, g, flash, step_ph)
			bufs[wk] = wb
		e[7] = settle
	if _gpu:
		# 장수는 늘, 시신은 다 넘어질 때까지만, 숨긴 산 병사는 빼고
		_cpu_list = lst.filter(func(e): return (e[6] and not e[7]) or (not e[1].alive and not e[7]))
		_cpu_full = false
		if lst == entries:
			for sq0 in order:
				sq0.changed_figs.clear()
	for k in bufs:
		_bufs[k] = bufs[k]
		var mmi: MultiMeshInstance3D = bodies.get(k, weapons.get(k))
		mmi.multimesh.buffer = bufs[k]
	for sq in order:
		var bn: Node3D = banners[sq.key]
		bn.visible = SHOW_BANNERS and sq.alive and sq.state != "gone"
		if bn.visible:
			var at: Vector2 = sq.general.pos if sq.general and sq.general.alive else sq.pos - sq.fwd * (sq.depth() + 6)
			bn.position = p3(at)
			bn.rotation = Vector3(0, atan2(-sq.fwd.y, sq.fwd.x) + PI, 0)
		var rg: Decal = squad_rings[sq.key]
		rg.visible = bn.visible
		if rg.visible:
			var w: float = (sq.cols * sq.sp + 10.0) * S
			var dp: float = (sq.depth() + 10.0) * S
			rg.size = Vector3(dp, 3.0, w)
			rg.position = p3(sq.pos - sq.fwd * sq.depth() * 0.5)
			rg.rotation = Vector3(0, atan2(-sq.fwd.y, sq.fwd.x), 0)
			# 맞으면 번쩍 —— 멀리 볼 때 '맞고 있다' 를 판 하나로 알린다
			var base_c: Color = TEAM[sq.camp].lightened(0.1)
			rg.modulate = Color(base_c.lerp(Color(1, 0.95, 0.85), clampf(sq.hurt, 0, 1) * 0.75), 0.85 + 0.15 * maxf(sq.glow, sq.hurt))


func _weapon_angle(sq: Squad, s, kind: String, alive: bool) -> float:
	if alive and s == sq.general and clock < sq.flourish_t:      # 고유기 —— 크게 휘두른다 (돌리고 · 내려치고)
		var u := sq.flourish_t - clock
		return sin(u * 15.0) * 2.4 - 0.9
	var front: bool = alive and (s == sq.general or sq.rank_of(s) < 2)
	var ready: bool = front and (sq.contact or (sq.engaged != null and sq.pos.distance_to(sq.engaged.pos) < 140.0))
	var a := clampf((clock - s.atk_t0) / Squad.ATTACK_TIME, 0, 1)
	match kind:
		"spear":
			return -1.38 if ready else -0.1
		"sword", "g_saber", "g_glaive":
			if sq.contact and front and a < 1.0:
				return lerpf(-2.6, -0.3, a)          # 머리 위에서 내려친다
			return -1.9 if ready else -0.55
		"lance", "g_lance":
			return -1.45 if ready or (sq.moving and sq.engaged != null) else -0.22
	return 0.0


# ───────── 카메라 —— 휠 확대, 오른쪽 끌기 회전, 왼쪽 끌기·WASD 이동, Q/E 회전 ─────────

func _update_cam(dt: float) -> void:
	if _cam_attr:
		_cam_attr.dof_blur_far_distance = cam_dist * 1.25 + 10.0       # 초점은 전투 쪽, 그 너머 산 · 숲만 흐리게
	overview = cam_dist > OVERVIEW_DIST and _cine <= 0
	var k := 1.0 - exp(-dt * cam_rate)
	cam_t = cam_t.lerp(want_t, k)
	cam_yaw = lerp_angle(cam_yaw, want_yaw, k)
	cam_pitch = lerpf(cam_pitch, want_pitch, k)
	cam_dist = lerpf(cam_dist, want_dist, k)
	var off := Vector3(-cos(cam_pitch) * cos(cam_yaw), sin(cam_pitch), -cos(cam_pitch) * sin(cam_yaw)) * cam_dist
	var tgt := Vector3(cam_t.x, height(cam_t.x, cam_t.z) + 1.0, cam_t.z)
	cam.position = tgt + off
	cam.look_at(tgt)
	if shake > 0.01:
		cam.position += Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * shake * 0.35
		shake = maxf(0, shake - dt * 1.6)


## 자동 카메라 —— 살아 있는 부대를 모두 화면 안에 담는 가장 가까운 거리를 찾는다.
## 후보 거리마다 부대 가장자리 점을 직접 투영해 보고(원근 포함), 위아래 가운데를 맞춘다.
## 다 담으려면 너무 멀어지면(FAR_OK 넘게) 싸우는 부대(맞닿았거나 상대에게 달려가는)만 담는다 —— 뒤에 선 예비대는 화면 밖으로.
## 위쪽은 세력 막대·시계가 있어 조금 더 비운다.
const FAR_OK := 34.0       # 10/30 46 → 34: 멀어지면 싸우는 부대만 담는다 (교전 지점을 더 가까이)
func _auto_frame() -> void:
	var fw := Vector2(cos(want_yaw), sin(want_yaw))
	var rt := Vector2(-sin(want_yaw), cos(want_yaw))
	var all := PackedVector2Array()
	var hot := PackedVector2Array()
	# 11/3 사용자: 병사의 바다가 화면을 채우게 —— 맨 끝에 처진 부대까지 다 담지 않고, 가운데에 몰린 부대 75% 만 담는다
	var live: Array = order.filter(func(q): return q.alive and q.state != "gone")
	if live.is_empty():
		return
	var cen := Vector2.ZERO
	for sq in live:
		cen += sq.pos
	cen /= live.size()
	live.sort_custom(func(a, b): return a.pos.distance_squared_to(cen) < b.pos.distance_squared_to(cen))
	live = live.slice(0, maxi(4, ceili(live.size() * CORE_SHARE)))
	for sq in live:
		var p: Vector2 = sq.pos * S
		var r := maxf(sq.depth(), sq.cols * sq.sp) * S * 0.5 + 0.8
		var busy: bool = sq.contact or (sq.engaged != null and sq.moving)
		for o in [rt * r, -rt * r, fw * r, -fw * r]:
			all.append(p + o)
			if busy:
				hot.append(p + o)
	if all.is_empty():
		return
	var vp := get_viewport().get_visible_rect().size
	var aspect := vp.x / maxf(vp.y, 1.0)
	var th := tan(deg_to_rad(cam.fov) / 2)
	var tv := th
	if cam.keep_aspect == Camera3D.KEEP_WIDTH:
		tv = th / aspect
	else:
		th = tv * aspect
	# 11/3 싸움이 한창이면 맞붙은 곳만 바짝 담는다 (뒤에 처진 부대는 화면 끝에 걸쳐도 된다). 개전 · 행군 중엔 전장 전체
	var hot_on := hot.size() >= all.size() * HOT_SHARE and hot.size() >= 16
	var res := _fit(hot if hot_on else all, fw, rt, th, tv)
	var nd := maxf(AUTO_MIN, res[0] * AUTO_MARGIN)
	# 조금씩 바뀌는 것은 무시한다 —— 화면이 출렁이지 않게 (넓어질 때는 바로, 좁아질 때는 10% 넘게 줄 때만)
	if nd > want_dist or nd < want_dist * 0.9:
		want_dist = nd
	var nt := Vector3(res[1].x, 0, res[1].y)
	if nt.distance_to(want_t) > want_dist * 0.06:
		want_t = nt
	cam_rate = 0.7


## 점들을 다 담는 [거리, 대상]
func _fit(pts: PackedVector2Array, fw: Vector2, rt: Vector2, th: float, tv: float) -> Array:
	const TOP := 0.62       # 화면 위 끝 (1 이 끝) —— 머리띠·머리표 자리
	const BOT := -0.9
	const SIDE := 1.0        # 세로 화면은 폭이 좁다 —— 양옆 부대 끝이 화면 끝에 닿게
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for p in pts:
		lo = Vector2(minf(lo.x, p.x), minf(lo.y, p.y))
		hi = Vector2(maxf(hi.x, p.x), maxf(hi.y, p.y))
	var tgt := (lo + hi) / 2
	var d := clampf(want_dist * 0.85, 18.0, 110.0)    # 지난 거리 근처부터 찾는다 (계산을 줄인다)
	for _i in 30:
		# 세로 가운데 맞춤 —— 두 번 고쳐 잡는다
		for _j in 2:
			var e := _ndc_range(pts, tgt, d, fw, rt, th, tv)
			if e.x < -8.0:
				break           # 카메라 뒤로 넘어간 점이 있다 —— 더 물러나야 한다
			var want_mid := (TOP + BOT) / 2
			var mid := (e.z + e.w) / 2
			tgt += fw * (mid - want_mid) * d * tv / maxf(sin(want_pitch), 0.3)
		var e2 := _ndc_range(pts, tgt, d, fw, rt, th, tv)
		if e2.x >= -SIDE and e2.y <= SIDE and e2.w <= TOP and e2.z >= BOT:
			break
		d *= 1.07
		if d > 110.0:
			d = 110.0
			break
	return [d, tgt]


## 땅 위 점들을 (대상, 거리)의 카메라로 투영한 화면 범위 —— x 최소·최대, y 최소·최대 (-1~1)
func _ndc_range(pts: PackedVector2Array, tgt: Vector2, d: float, fw: Vector2, rt: Vector2, th: float, tv: float) -> Vector4:
	var cp := cos(want_pitch)
	var spt := sin(want_pitch)
	var h0 := height(tgt.x, tgt.y) + 1.0
	var eye := Vector3(tgt.x - fw.x * cp * d, h0 + spt * d, tgt.y - fw.y * cp * d)
	var f := Vector3(fw.x * cp, -spt, fw.y * cp)           # 카메라 앞
	var r := Vector3(rt.x, 0, rt.y)                        # 카메라 오른쪽
	var u := r.cross(f)                                    # 카메라 위
	var e := Vector4(INF, -INF, INF, -INF)
	for p in pts:
		var v := Vector3(p.x, h0 - 1.0, p.y) - eye
		var z := v.dot(f)
		if z < 0.5:
			return Vector4(-9, 9, -9, 9)
		var x := v.dot(r) / z / th
		var y := v.dot(u) / z / tv
		e = Vector4(minf(e.x, x), maxf(e.y, x), minf(e.z, y), maxf(e.w, y))
	return e


## 자동 카메라로 돌아간다 (두 번 누르기 · 카메라 맞춤)
func auto_camera() -> void:
	follow = null
	_manual = 0.0
	director = true


func reset_camera() -> void:
	# 입장 연출 —— 아군 뒤 낮은 곳에서 시작해 전장 전체로 물러난다
	cam_t = Vector3(-34, 0, 6)
	cam_yaw = base_yaw() - 0.55
	cam_pitch = 0.16
	cam_dist = 24.0
	want_t = Vector3(-4, 0, 0)
	want_yaw = base_yaw()
	want_pitch = 0.92 if portrait else 0.8     # 11/4 더 높이서 내려다본다 (0.78 · 0.68) · 10/31 0.88 높이서 → 11/3 조금 눕혀 군단이 겹쳐 두꺼워 보이게
	want_dist = 88.0 if portrait else 100.0      # 11/4 사용자: 멀리 · 높이서 (62 · 70 에서)
	want_dist = want_dist      # 11/3 입장 끝 거리도 당김 (예전 78 · 86)
	cam_rate = 0.9
	_intro = 3.5
	_manual = 0.0
	_update_cam(0.0)


## 고유기 카메라 —— 장수 쪽으로 다가갔다가 끝나면 원래 자리로 돌아간다
func cinematic(sq: Squad, dur: float, shoulder := false) -> void:
	if _cine <= 0:
		_cine_back = [want_t, want_dist, want_pitch, want_yaw]
	_cine = dur
	if shoulder:
		# 11/4 사용자: 고유기는 장수 어깨 너머로 —— 장수 바로 뒤 · 조금 옆에서 적 쪽을 본다
		var gp: Vector2 = sq.general.pos if sq.general and sq.general.alive else sq.pos
		var p := p3(gp)
		want_t = Vector3(p.x, 0, p.z) + Vector3(sq.fwd.x, 0, sq.fwd.y) * 2.5
		want_yaw = sq.fwd.angle() + 0.42
		want_dist = 15.0
		want_pitch = 0.36
		cam_rate = 6.0
		return
	var p := p3(sq.pos)
	want_t = want_t.lerp(Vector3(p.x, 0, p.z), 0.65)
	want_dist = minf(want_dist, 52.0)
	want_pitch = clampf(want_pitch - 0.08, 0.3, 1.2)
	cam_rate = 3.0


## 고유기 무기 휘두르기 —— dur 초 동안 장수 무기가 크게 돌고 불꽃 · 빛이 튄다
func flourish(sq: Squad, dur: float) -> void:
	sq.flourish_t = clock + dur
	var gp: Vector2 = sq.general.pos if sq.general and sq.general.alive else sq.pos
	var c := p3(gp, 1.6)
	_light(c, Color(1.0, 0.85, 0.5), 7.0, dur)
	for i in 3:
		var a := TAU * i / 3.0
		_particles(c + Vector3(cos(a), 0.3 * i, sin(a)) * 0.8, "spark", Color("#fff2b0"))
	_particles(p3(gp, 0.3), "dust", Color("#c8b088"))


## 꾹 누른 부대를 계속 따라간다
func follow_squad(sq: Squad) -> void:
	follow = sq
	focus(sq)
	want_dist = minf(want_dist, 40.0)


## 화면 좌표(논리)에서 가장 가까운 살아 있는 부대 —— 없으면 null
func squad_at(sp: Vector2, reach := 70.0) -> Squad:
	var best: Squad = null
	var bd := reach
	for sq in order:
		if not sq.alive:
			continue
		var d := to_screen(sq.pos, 0.8).distance_to(sp)
		if d < bd:
			bd = d
			best = sq
	return best


func focus(sq: Squad) -> void:
	want_t = p3(sq.pos)
	want_dist = minf(want_dist, 44.0)
	cam_rate = 4.0
	_manual = MANUAL_HOLD


func camera_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.pressed:
		if e.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			_manual = MANUAL_HOLD
		if e.button_index == MOUSE_BUTTON_WHEEL_UP:
			want_dist = clampf(want_dist * 0.88, 8.0, 170.0)
			cam_rate = 4.0
		elif e.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			want_dist = clampf(want_dist / 0.88, 8.0, 170.0)
			cam_rate = 4.0
	elif e is InputEventMouseMotion:
		var rel: Vector2 = e.relative / screen_scale       # 3D 해상도 배율을 걷어 내고 논리 좌표로
		if e.button_mask != 0 and rel.length() > 0.5:
			_manual = MANUAL_HOLD
		if e.button_mask & MOUSE_BUTTON_MASK_RIGHT:
			want_yaw += rel.x * 0.006
			want_pitch = clampf(want_pitch + rel.y * 0.004, 0.12, 1.42)
			cam_rate = 6.0
		elif e.button_mask & (MOUSE_BUTTON_MASK_LEFT | MOUSE_BUTTON_MASK_MIDDLE):
			if rel.length() > 0.5:
				follow = null            # 손으로 옮기면 따라가기를 푼다
			var fw := Vector3(cos(want_yaw), 0, sin(want_yaw))
			var rt := Vector3(-sin(want_yaw), 0, cos(want_yaw))
			want_t += (-rt * rel.x + fw * rel.y) * want_dist * 0.0017 * (1.6 if portrait else 1.0)
			cam_rate = 8.0


## 두 손가락 —— ratio 는 거리 배율(1 보다 작으면 다가간다), turn 은 회전 (라디안)
func pinch(ratio: float, turn: float) -> void:
	want_dist = clampf(want_dist * ratio, 8.0, 170.0)
	want_yaw -= turn
	cam_rate = 6.0
	_manual = MANUAL_HOLD


func to_screen(p: Vector2, lift: float) -> Vector2:
	if flat:
		return flat.map(p) + Vector2(0, -lift * 2.2)
	var w := p3(p, lift)
	if cam.is_position_behind(w):
		return Vector2(-99999, -99999)
	return cam.unproject_position(w) / screen_scale


## 세로 화면 —— 세로 화각을 좁혀 원근 왜곡을 줄인다. 양 날개는 자동 카메라가 거리로 맞춘다
func set_portrait(on: bool) -> void:
	if on != portrait and _cine <= 0:
		want_pitch = 0.92 if on else 0.8
	portrait = on
	if _cine <= 0:
		want_yaw = base_yaw()
	cam.keep_aspect = Camera3D.KEEP_HEIGHT
	cam.fov = 62.0 if on else 50.0


## 머리표 투명도 —— 가까이 볼 때 멀리 있는 부대의 표가 지평선에 쌓이지 않게 흐린다
func label_alpha(p: Vector2) -> float:
	if flat:
		return 1.0
	var d := cam.position.distance_to(p3(p))
	return 1.0 - smoothstep(cam_dist * 1.5 + 10.0, cam_dist * 2.2 + 25.0, d)


# ───────── 명령 (연출 감독이 부른다) ─────────

func order_melee(akey: String, dkey: String) -> void:
	var a: Squad = squads.get(akey)
	var d: Squad = squads.get(dkey)
	if a == null or d == null or not a.alive or not d.alive:
		return
	_assign(a, _lane_target(a, d))


## 전선 (10/30 삼국지13 연출) —— 보병은 엔진이 고른 상대가 멀면 전장을 가로질러 달려가지 않고 앞의 가장 가까운 적과 맞붙는다.
## 이미 맞닿아 싸우는 중이면 그 상대를 놓지 않는다. 기병은 그대로 (먼 적을 우회해 친다). 피해 숫자는 엔진이 정한 상대에 뜬다
func _lane_target(a: Squad, d: Squad) -> Squad:
	if a.cls == "cav":
		return d
	if a.contact and a.engaged != null and a.engaged.alive:
		return a.engaged
	var near: Squad = null
	var nd := 1e12
	for o in order:
		if o.alive and o.camp != a.camp and o.state != "flee" and o.state != "gone":
			var dd: float = a.pos.distance_to(o.pos)
			if dd < nd:
				nd = dd
				near = o
	if near != null and a.pos.distance_to(d.pos) > nd + 100.0:
		return near
	return d


## 상대 배정 —— 같은 상대에 이미 붙은 아군 수만큼 옆으로 비켜 선다
func _assign(a: Squad, d: Squad) -> void:
	if a.engaged == d:
		return
	var n := 0
	for o in order:
		if o != a and o.engaged == d and o.camp == a.camp:
			n += 1
	a.set_target(d, [0.0, -40.0, 40.0, -75.0, 75.0][mini(n, 4)])


## 실시간 지휘 —— 엔진이 정한 각 부대의 공격 순서(plans)를 미리 내다보고 상대를 정한다.
## 행동 차례가 오기 전부터 상대에게 달려가 붙어 있으므로 턴을 기다리는 모습이 사라진다.
## plans: key -> [[시각, 상대 key], …] (시각 순)
func direct(plans: Dictionary) -> void:
	for sq in order:
		if not sq.alive or sq.state == "flee" or sq.state == "gone":
			continue
		var plan: Array = plans.get(sq.key, [])
		# 이미 지나갔고 뒤에 다른 상대가 있으면 넘긴다. 죽은 상대도 넘긴다.
		while not plan.is_empty():
			var t: Squad = squads.get(plan[0][1])
			var stale: bool = plan.size() > 1 and plan[0][0] < clock - 0.5
			if t == null or not t.alive or stale:
				plan.pop_front()
			else:
				break
		var tgt: Squad = squads.get(plan[0][1]) if not plan.is_empty() else null
		if sq.cls == "melee" or sq.cls == "cav":
			if tgt:
				_assign(sq, _lane_target(sq, tgt))
			elif sq.engaged == null:
				# 할 일이 없으면 우리 편을 치는 적에게 붙는다
				var foe := _attacker_of_side(sq)
				if foe:
					_assign(sq, foe)
		else:
			sq.face_to = tgt.pos if tgt else null
		# 근접으로 맞고 있는데 상대가 없으면 그 적을 바라본다
		if sq.engaged == null:
			for o in order:
				if o.alive and o.engaged == sq and o.contact:
					sq.face_to = o.pos
					break


## 지형 깔기 —— 숲은 나무 무리 + 짙은 땅, 강은 물길 + 진흙 둑, 언덕은 둔덕 (height 에도 더한다)
func _build_terrain(zones: Array) -> void:
	if terrain_root == null:
		terrain_root = Node3D.new()
		add_child(terrain_root)
	for c in terrain_root.get_children():
		c.queue_free()
	tzones = zones
	_hills = []
	for z in zones:
		if z.k == "hill":
			_hills.append([Vector2(z.x, z.y) * S, float(z.r) * S])
	var r2 := RandomNumberGenerator.new()
	r2.seed = hash(str(zones))
	var pines := []
	var leafs := []
	for z in zones:
		match z.k:
			"forest":
				var c := Vector2(z.x, z.y)
				var rr := float(z.r)
				_ground_disc(c, rr * 1.05, Color(0.16, 0.24, 0.11), 0.75)
				for t in int(rr / 4.0):
					var a := r2.randf() * TAU
					var d := sqrt(r2.randf()) * rr * 0.9
					var p := (c + Vector2(cos(a), sin(a)) * d) * S
					var xf := Transform3D(Basis(Vector3.UP, r2.randf() * TAU).scaled(Vector3.ONE * r2.randf_range(0.4, 0.7)), Vector3(p.x, height(p.x, p.y) - 0.05, p.y))
					(pines if r2.randf() < 0.55 else leafs).append(xf)
			"river":
				_river(float(z.x), float(z.w))
			"hill":
				_hill_mesh(Vector2(z.x, z.y) * S, float(z.r) * S)
	if not pines.is_empty() and not _tree_boards(terrain_root, "pine", pines, r2):
		_scatter_in(terrain_root, Models.pine(r2), pines)
	if not leafs.is_empty() and not _tree_boards(terrain_root, "leaf", leafs, r2):
		_scatter_in(terrain_root, Models.broadleaf(r2), leafs)


## 부대 발밑 판 —— 둥근 모서리 사각형, 안은 옅게 차고 테두리는 진하게 (10/31 사용자: 부대가 덩어리로 보이게)
var _block: Texture2D
func _block_tex() -> Texture2D:
	if _block:
		return _block
	var n := 128
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	for y in n:
		for x in n:
			var q := Vector2(absf(x - n / 2.0 + 0.5), absf(y - n / 2.0 + 0.5)) / (n / 2.0)
			var c := Vector2(maxf(q.x - 0.78, 0.0), maxf(q.y - 0.78, 0.0))
			var d := c.length() + minf(maxf(q.x - 0.78, q.y - 0.78), 0.0) - 0.16      # 둥근 사각형까지의 거리 (안이면 음수)
			var a := 0.0
			if d < 0.0:
				a = 0.22 + 0.7 * clampf(1.0 + d / 0.07, 0, 1)
			elif d < 0.03:
				a = 0.9 * (1.0 - d / 0.03)
			img.set_pixel(x, y, Color(1, 1, 1, a))
	_block = ImageTexture.create_from_image(img)
	return _block


# ───────── 실사 나무 판 (10/31 사용자: 카툰 · 로우폴리 느낌을 벗는다) ─────────
## Poly Haven CC0 나무 · 덤불을 구운 그림(tests/bake_trees.tscn → assets/trees)을 세운 판으로 깐다
const TREE_SET := {"pine": ["pine_sapling_small", "fir_sapling"], "leaf": ["jacaranda_tree"], "shrub": ["shrub_03", "shrub_04"]}
const TREE_H := {"pine": 8.0, "leaf": 5.6, "shrub": 0.8}     # 배율 1 일 때 세계 높이 (예전 도형 나무와 같게)
var _tree_info = null
var _tree_mat := {}


## xforms(자리 · 배율)마다 그 종류의 그림 하나를 골라 판으로 세운다. 그림이 없으면 false
const PHOTO_TREES := false      # 11/2 사용자: 실사 그림 판이 깨져 보인다 → 도형 나무 (깔끔한 톤)
func _tree_boards(parent: Node3D, kind: String, xforms: Array, r: RandomNumberGenerator) -> bool:
	if _tree_info == null:
		_tree_info = {}
		if FileAccess.file_exists("res://assets/trees/trees.json"):
			_tree_info = JSON.parse_string(FileAccess.get_file_as_string("res://assets/trees/trees.json"))
	if not PHOTO_TREES:
		return false
	var names: Array = TREE_SET[kind].filter(func(n): return _tree_info.has(n) and ResourceLoader.exists("res://assets/trees/%s.png" % n))
	if names.is_empty():
		return false
	var groups := {}
	for xf in xforms:
		var n: String = names[r.randi() % names.size()]
		if not groups.has(n):
			groups[n] = []
		groups[n].append(xf)
	for n in groups:
		var info: Dictionary = _tree_info[n]
		var side: float = info.side
		if not _tree_mat.has(n):
			var m := ShaderMaterial.new()
			m.shader = load("res://shaders/tree_billboard.gdshader")
			m.set_shader_parameter("tex", load("res://assets/trees/%s.png" % n))
			_tree_mat[n] = m
		var q := QuadMesh.new()
		q.size = Vector2(side, side)
		q.center_offset = Vector3(0, side * 0.5, 0)
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_custom_data = true
		mm.mesh = q
		var list: Array = groups[n]
		mm.instance_count = list.size()
		for i in list.size():
			var xf: Transform3D = list[i]
			var k: float = TREE_H[kind] * xf.basis.x.length() / float(info.h)
			mm.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3.ONE * k), xf.origin))
			var g := r.randf_range(0.82, 1.06)
			mm.set_instance_custom_data(i, Color(g * r.randf_range(0.95, 1.05), g, g * r.randf_range(0.9, 1.02), 1))
		var mi := MultiMeshInstance3D.new()
		mi.multimesh = mm
		mi.material_override = _tree_mat[n]
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(mi)
	return true


func _scatter_in(parent: Node3D, mesh: Mesh, xforms: Array) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.material_override = _vc_mat()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF      # 전장 안 나무는 그림자 없이 (바닥이 얼룩져 산만했다)
	parent.add_child(mi)


## 땅에 색을 깐다 (데칼 —— 둔덕 위에도 붙는다)
func _ground_disc(c: Vector2, r: float, col: Color, a: float) -> void:
	if _disc_tex == null:
		_disc_tex = _grad_tex(GradientTexture2D.FILL_RADIAL, Vector2(0.5, 0.5), Vector2(1.0, 0.5))
	var g := GradientTexture2D.new()
	g.fill = GradientTexture2D.FILL_RADIAL
	g.fill_from = Vector2(0.5, 0.5)
	g.fill_to = Vector2(1.0, 0.5)
	var gr := Gradient.new()
	gr.offsets = PackedFloat32Array([0.0, 0.7, 1.0])
	gr.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.8), Color(1, 1, 1, 0)])
	g.gradient = gr
	var d := Decal.new()
	d.texture_albedo = g
	d.modulate = Color(col, a)
	d.position = p3(c)
	d.size = Vector3(r * 2 * S, 30, r * 2 * S)
	d.upper_fade = 0.3
	d.lower_fade = 0.3
	terrain_root.add_child(d)


## 강 —— 전장을 위아래로 가로지르는 물길 (x 중심 · 반폭 w, px)
func _river(x: float, w: float) -> void:
	var bank := Decal.new()
	var g := GradientTexture2D.new()
	g.fill = GradientTexture2D.FILL_LINEAR
	g.fill_from = Vector2(0, 0.5)
	g.fill_to = Vector2(1, 0.5)
	var gr := Gradient.new()
	gr.offsets = PackedFloat32Array([0.0, 0.25, 0.75, 1.0])
	gr.colors = PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, 0.9), Color(1, 1, 1, 0.9), Color(1, 1, 1, 0)])
	g.gradient = gr
	bank.texture_albedo = g
	bank.modulate = Color(0.33, 0.27, 0.18, 0.9)
	bank.position = p3(Vector2(x, 0))
	bank.size = Vector3(w * 2.8 * S, 30, 80)
	terrain_root.add_child(bank)
	var pm := PlaneMesh.new()
	pm.size = Vector2(w * 2 * S, 80)
	var mi := MeshInstance3D.new()
	mi.mesh = pm
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.20, 0.45, 0.62, 0.82)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.roughness = 0.25
	m.metallic = 0.0
	m.emission_enabled = true
	m.emission = Color(0.10, 0.26, 0.38)
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = Vector3(x * S, height(x * S, 0) + 0.12, 0)
	terrain_root.add_child(mi)


## 언덕 —— 둥근 둔덕 (height 의 _bump 와 같은 모양). 땅보다 조금 밝은 풀색
func _hill_mesh(c: Vector2, r: float) -> void:
	var rings := 10
	var segs := 36
	var verts := PackedVector3Array()
	var cols := PackedColorArray()
	for i in rings + 1:
		var rr := r * float(i) / rings
		for j in segs:
			var a := TAU * j / segs
			var x := c.x + cos(a) * rr
			var z := c.y + sin(a) * rr
			verts.append(Vector3(x, height(x, z) + 0.02, z))
			var u := _bump(x, z) / HILL_H
			cols.append(Color(0.29, 0.31, 0.19).lerp(Color(0.43, 0.41, 0.28), u))       # 10/31 흙빛으로
	var idx := PackedInt32Array()
	for i in rings:
		for j in segs:
			var a := i * segs + j
			var b := i * segs + (j + 1) % segs
			var cc := (i + 1) * segs + j
			var d := (i + 1) * segs + (j + 1) % segs
			idx.append_array([a, cc, b, b, cc, d])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_COLOR] = cols
	arr[Mesh.ARRAY_INDEX] = idx
	var st := SurfaceTool.new()
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	st.create_from(m, 0)
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = _vc_mat()
	terrain_root.add_child(mi)


## 실시간 엔진 —— 위치 기록 track([[시각, [[x, y, 방향각, 대상 번호, 맞닿음] × 유닛]], …])을 t 초에 맞춰 잇는다.
## order 는 roster 순서와 같다
func follow_track(track: Array, t: float) -> void:
	if track.is_empty():
		return
	var lo := 0
	var hi := track.size() - 1
	while lo < hi:
		var mid := (lo + hi + 1) / 2
		if float(track[mid][0]) <= t:
			lo = mid
		else:
			hi = mid - 1
	var a: Array = track[lo]
	var b: Array = track[mini(lo + 1, track.size() - 1)]
	var span: float = float(b[0]) - float(a[0])
	var u := clampf((t - float(a[0])) / span, 0.0, 1.0) if span > 0.0 else 0.0
	for i in mini(order.size(), a[1].size()):
		var sq: Squad = order[i]
		if not sq.puppet:
			continue
		var fa: Array = a[1][i]
		var fb: Array = b[1][i]
		sq.pgoal = Vector2(fa[0], fa[1]).lerp(Vector2(fb[0], fb[1]), u)
		sq.pfwd = Vector2.from_angle(lerp_angle(float(fa[2]), float(fb[2]), u))
		var ti := int(fa[3])
		sq.ptgt = order[ti] if ti >= 0 and ti < order.size() else null
		sq.ptouch = int(fa[4]) == 1
		if sq.ptgt == null:
			sq.face_to = null


func _attacker_of_side(sq: Squad) -> Squad:
	var best: Squad = null
	var bd := 1e9
	for o in order:
		if o.camp == sq.camp or not o.alive or o.state != "move" or o.engaged == null:
			continue
		var d: float = o.pos.distance_to(sq.pos)
		if d < bd and d < 320.0:
			bd = d
			best = o
	return best


func arrived(akey: String) -> bool:
	var a: Squad = squads.get(akey)
	if a == null or not a.alive or a.engaged == null:
		return true
	return a.contact


func _on_impact(sq: Squad) -> void:
	var d := sq.engaged
	if d == null:
		return
	if sq.cls == "cav":
		d.stagger(clock, rng)
		shake = maxf(shake, clampf(40.0 / cam.position.distance_to(p3(sq.pos)), 0.1, 0.6))
		_contact_fx(sq, d, true)
		_particles(p3(sq.pos, 0.3), "dust", Color("#a89270"))
	else:
		_contact_fx(sq, d, false)


func _contact_fx(a: Squad, d: Squad, dust: bool) -> void:
	var p := p3(d.pos + a.axis * d.depth() * 0.5 + Vector2(-a.axis.y, a.axis.x) * rng.randf_range(-30, 30), 1.1)
	_particles(p, "spark", Color("#fff2b0"))
	if dust:
		_particles(p + Vector3(0, -0.9, 0), "dust", Color("#a89270"))


func volley(akey: String, dkeys: Array, light := false, emph := false) -> void:
	var a: Squad = squads.get(akey)
	if a == null:
		return
	var shooters := a.soldiers.filter(func(s): return s.alive)
	if shooters.is_empty():
		return
	for dk in dkeys:
		var d: Squad = squads.get(dk)
		if d == null:
			continue
		var targets := d.soldiers.filter(func(s): return s.alive)
		if emph:
			cfx.trace(a, d, "shoot", Color(1.0, 0.86, 0.45))
		elif not light:
			cfx.acted(a, d, "shoot")
		var nshot := 6 if light else (18 if emph else 10)
		if overview and not emph:
			nshot = 0 if light else 3       # 멀리 볼 때 평타 화살은 거의 안 날린다 (공격 화살표가 알린다)
		for i in mini(nshot, shooters.size() + 6):       # 평타 화살은 적게
			var p0 := p3(a.fig_pos(shooters[rng.randi() % shooters.size()]), 1.5)
			var tp: Vector2 = d.fig_pos(targets[rng.randi() % targets.size()]) if not targets.is_empty() else d.pos
			var p1 := p3(tp + Vector2(rng.randf_range(-8, 8), rng.randf_range(-8, 8)), 0.1)
			var dist := p0.distance_to(p1)
			arrows.append({"p0": p0, "p1": p1, "t0": clock + rng.randf() * 0.2, "dur": 0.55 + dist / 75.0,
				"h": 2.5 + dist * 0.2, "puff": not light and i % 5 == 0})


func cast(akey: String, dkeys: Array, st: String, light := false) -> void:
	var a: Squad = squads.get(akey)
	if a == null:
		return
	var col: Color = ST_COL.get(st, Color("#c9a2ff"))
	if not light:
		a.glow = 1.0
		_particles(p3(a.pos, 1.6), "magic", col)
		_light(p3(a.pos, 3.0), col, 2.5, 0.6)
	for dk in dkeys:
		var d: Squad = squads.get(dk)
		if d == null:
			continue
		if not light:
			cfx.acted(a, d, "cast")          # 책략은 띠 없이 (이름표 아이콘 · 공격 화살표만)
		for i in 1 if light else 2:
			var orb := MeshInstance3D.new()
			var sm := SphereMesh.new()
			sm.radius = 0.22
			sm.height = 0.44
			orb.mesh = sm
			orb.material_override = _glow_mat(col)
			orb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			if not light:
				var ol := OmniLight3D.new()
				ol.light_color = col
				ol.light_energy = 1.6
				ol.omni_range = 6
				orb.add_child(ol)
			fx_root.add_child(orb)
			var p0 := p3(a.pos + Vector2(rng.randf_range(-15, 15), 0), 2.0)
			var p1 := p3(d.pos + Vector2(rng.randf_range(-20, 20), rng.randf_range(-15, 15)), 0.8)
			orb.position = p0
			orbs.append({"n": orb, "p0": p0, "p1": p1, "t0": clock + i * 0.1, "dur": 0.45 + p0.distance_to(p1) / 90.0,
				"st": "" if light else st, "col": col, "light": light})


## 근접 타격 —— emph(기술 · 고유기 · 치명타)일 때만 베기 · 불꽃. 평타는 공격 화살표 · 아이콘만 (10/31 사용자: 산만하다)
func clash(akey: String, dkey: String, emph := false) -> void:
	var a: Squad = squads.get(akey)
	var d: Squad = squads.get(dkey)
	if a == null or d == null:
		return
	if not emph:
		cfx.acted(a, d, "melee")
		return
	cfx.slash(a, d)
	var dir := (a.pos - d.pos).normalized()
	var p := p3(d.pos + dir * d.depth() * 0.5 + Vector2(0, rng.randf_range(-20, 20)), 1.1)
	_particles(p, "spark", Color("#fff2b0"))


func apply(key: String, troops: float, morale: float, from_key: String) -> void:
	var sq: Squad = squads.get(key)
	if sq == null:
		return
	var from := sq.pos + sq.fwd * 40
	var f: Squad = squads.get(from_key)
	if f and f != sq:
		from = f.pos
	if absf(troops - sq.troops) > 0.5:
		sq.set_troops(troops, from, clock, rng)
	sq.morale = morale


## 군령 —— 그 진영 부대마다 발밑에 고리가 퍼진다
func cmd_fx(camp: String, col: Color) -> void:
	for sq in order:
		if sq.alive and sq.camp == camp:
			_ring(p3(sq.pos, 0.15), col, 0.8)


func heal_fx(key: String) -> void:
	var sq: Squad = squads.get(key)
	if sq:
		_particles(p3(sq.pos, 0.6), "heal", Color("#8FD4C2"))


func skill_fx(key: String) -> void:
	var sq: Squad = squads.get(key)
	if sq == null:
		return
	sq.glow = 1.0
	_ring(p3(sq.pos, 0.15), DB.PAL.gold, 0.8)
	_light(p3(sq.pos, 2.5), DB.PAL.gold, 2.0, 0.7)


## 기술이 떨어지는 곳 —— 맞는 부대마다 땅에 번지는 고리 · 빛 (물리는 금빛 흙먼지, 책략은 보랏빛)
func skill_hit_fx(keys: Array, magic: bool) -> void:
	var col := Color("#b57edc") if magic else Color("#ffcf6a")
	for k in keys:
		var t: Squad = squads.get(k)
		if t == null or not t.alive:
			continue
		_ring(p3(t.pos, 0.2), col, 1.0)
		_light(p3(t.pos, 3.0), col, 2.4, 0.6)
		if not dbg_nofx:
			_particles(p3(t.pos, 0.6), "magic" if magic else "dust", col)


func rout(key: String) -> void:
	var sq: Squad = squads.get(key)
	if sq == null or not sq.alive:
		return
	sq.rout(clock, rng)
	_particles(p3(sq.pos, 0.3), "dust", Color("#9c8a6c"))
	for o in order:
		if o.engaged == sq:
			o.set_target(null, 0)
			o.state = "hold"


func celebrate(camp: String) -> void:
	for sq in order:
		if sq.camp == camp and sq.alive:
			sq.cheer = true
			sq.set_target(null, 0)
			sq.state = "hold"
		elif sq.alive:
			sq.rout(clock, rng)


# ───────── 효과 ─────────

func _glow_mat(col: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = col
	m.emission_enabled = true
	m.emission = col
	m.emission_energy_multiplier = 2.2
	return m


func _pmaterial(add: bool) -> StandardMaterial3D:
	if _pmat.has(add):
		return _pmat[add]
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD if add else BaseMaterial3D.BLEND_MODE_MIX
	m.albedo_texture = _soft
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.disable_receive_shadows = true
	_pmat[add] = m
	return m


## 파티클 한 번 터뜨리기 —— 종류별 설정표
func _particles(pos: Vector3, kind: String, col: Color, loop := false) -> CPUParticles3D:
	if overview and not loop and SMALL_FX.has(kind):
		return null              # 멀리 볼 때는 작은 입자를 뺀다
	var cfg := {
		"fire": [28, 0.9, 2.0, 5.0, 25.0, Vector3(0, 2.5, 0), 0.5, 1.1, true, 1.4],
		"smoke": [10, 2.2, 0.8, 1.6, 20.0, Vector3(0, 0.6, 0), 1.2, 2.4, false, 1.4],
		"spark": [10, 0.35, 4.0, 8.0, 70.0, Vector3(0, -9, 0), 0.07, 0.14, true, 0.4],
		"dust": [6, 1.4, 0.5, 1.4, 90.0, Vector3(0, 0.3, 0), 0.9, 1.8, false, 1.0],
		"splash": [22, 0.8, 3.0, 6.0, 35.0, Vector3(0, -9, 0), 0.05, 0.1, false, 1.0],
		"mist": [10, 2.2, 0.2, 0.7, 90.0, Vector3(0, 0.15, 0), 1.6, 2.8, false, 2.2],
		"heal": [16, 1.3, 1.0, 2.2, 20.0, Vector3.ZERO, 0.14, 0.28, true, 2.2],
		"magic": [16, 0.55, 2.0, 4.0, 180.0, Vector3.ZERO, 0.07, 0.16, true, 0.5],
		"drop": [6, 0.5, 0.5, 1.5, 30.0, Vector3(0, -9, 0), 0.08, 0.14, false, 1.8],
		"haze": [4, 3.2, 0.3, 0.9, 80.0, Vector3(0, 0.25, 0), 3.0, 5.5, false, 2.5],
		"ember": [30, 2.4, 1.5, 4.5, 50.0, Vector3(0, 1.2, 0), 0.05, 0.11, true, 3.0],
		"trail": [5, 1.4, 0.3, 1.0, 70.0, Vector3(0, 0.4, 0), 1.0, 1.8, true, 1.6],
	}
	var c: Array = cfg[kind]
	var p := CPUParticles3D.new()
	if dbg_nofx:
		p.emitting = false
		fx_root.add_child(p)
		fx_nodes.append([p, clock + 0.1])
		return p
	var q := QuadMesh.new()
	q.size = Vector2.ONE
	q.material = _pmaterial(c[8])
	p.mesh = q
	p.amount = c[0]
	p.lifetime = c[1]
	p.one_shot = not loop
	p.explosiveness = 0.0 if loop else 0.85
	p.direction = Vector3.UP
	p.spread = c[4]
	p.initial_velocity_min = c[2]
	p.initial_velocity_max = c[3]
	p.gravity = c[5]
	p.scale_amount_min = c[6]
	p.scale_amount_max = c[7]
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = c[9]
	var g := Gradient.new()
	match kind:
		"fire":
			g.colors = PackedColorArray([Color("#ffe08a"), Color(col, 0.9), Color("#c0301e", 0.5), Color(0.2, 0, 0, 0)])
			g.offsets = PackedFloat32Array([0, 0.25, 0.6, 1])
		"haze":
			g.colors = PackedColorArray([Color(col, 0.0), Color(col, 0.2), Color(col, 0)])
			g.offsets = PackedFloat32Array([0, 0.3, 1])
		"smoke", "dust", "mist":
			g.colors = PackedColorArray([Color(col, 0.0), Color(col, 0.42), Color(col, 0)])
			g.offsets = PackedFloat32Array([0, 0.2, 1])
		_:
			g.colors = PackedColorArray([Color(col.lightened(0.3), 1), Color(col, 0)])
	p.color_ramp = g
	var curve := Curve.new()
	if kind in ["smoke", "dust", "mist", "haze"]:
		curve.add_point(Vector2(0, 0.5))
		curve.add_point(Vector2(1, 1.3))
	else:
		curve.add_point(Vector2(0, 1.0))
		curve.add_point(Vector2(1, 0.3))
	p.scale_amount_curve = curve
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.speed_scale = time_scale
	fx_root.add_child(p)
	p.position = pos
	p.emitting = true
	if not loop:
		fx_nodes.append([p, clock + c[1] + 0.3])
	return p


func _light(pos: Vector3, col: Color, energy: float, life: float) -> void:
	var l := OmniLight3D.new()
	l.light_color = col
	l.light_energy = energy
	l.omni_range = 10
	l.position = pos
	fx_root.add_child(l)
	lights.append({"n": l, "t0": clock, "life": life, "e": energy})


func _ring(pos: Vector3, col: Color, life: float) -> void:
	var r := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 2.6
	tm.outer_radius = 2.85
	tm.rings = 24
	tm.ring_segments = 4
	r.mesh = tm
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.albedo_color = col
	r.material_override = m
	r.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	r.position = pos
	r.scale = Vector3(1, 0.2, 1)
	fx_root.add_child(r)
	rings.append({"n": r, "t0": clock, "life": life, "m": m, "col": col})


## 기술 범위 —— 엔진이 사건에 적은 모양(원 · 띠)을 땅에 잠깐 깐다. shape 좌표는 전장 px
func area_mark(shape: Dictionary, col: Color, life := 1.1) -> void:
	if flat:
		flat.add_area(shape, col, life)      # 점묘 전장은 2D 로 그린다
		return
	if _disc_tex == null:
		_disc_tex = _grad_tex(GradientTexture2D.FILL_RADIAL, Vector2(0.5, 0.5), Vector2(1.0, 0.5))
		_band_tex = _grad_tex(GradientTexture2D.FILL_LINEAR, Vector2(0.5, 0.0), Vector2(0.5, 1.0), true)
	var d := Decal.new()
	d.modulate = Color(col, 0.0)
	d.albedo_mix = 1.0
	d.upper_fade = 0.3
	d.lower_fade = 0.3
	d.distance_fade_enabled = false
	if shape.k == "line":
		var a := Vector2(shape.x, shape.y)
		var b := Vector2(shape.x2, shape.y2)
		var mid := p3((a + b) / 2)
		d.texture_albedo = _band_tex
		d.position = mid
		d.size = Vector3(a.distance_to(b) * S, 30, float(shape.w) * 2 * S)
		d.rotation.y = -(b - a).angle()
	else:
		d.texture_albedo = _disc_tex
		d.position = p3(Vector2(shape.x, shape.y))
		var r: float = float(shape.r) * 2 * S
		d.size = Vector3(r, 30, r)
	fx_root.add_child(d)
	areas.append({"n": d, "t0": clock, "life": life, "peak": 0.45 if shape.get("r", 0) >= 200 else 0.7})


func _grad_tex(fill: int, from: Vector2, to: Vector2, band := false) -> GradientTexture2D:
	var g := GradientTexture2D.new()
	g.width = 128
	g.height = 128
	g.fill = fill
	g.fill_from = from
	g.fill_to = to
	var gr := Gradient.new()
	if band:      # 띠 —— 가운데 옅게 차고 양 가장자리가 밝다
		gr.offsets = PackedFloat32Array([0.0, 0.06, 0.14, 0.5, 0.86, 0.94, 1.0])
		gr.colors = PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, 0.9), Color(1, 1, 1, 0.22), Color(1, 1, 1, 0.16), Color(1, 1, 1, 0.22), Color(1, 1, 1, 0.9), Color(1, 1, 1, 0)])
	else:         # 원 —— 안은 옅게, 테두리는 밝게
		gr.offsets = PackedFloat32Array([0.0, 0.8, 0.92, 0.97, 1.0])
		gr.colors = PackedColorArray([Color(1, 1, 1, 0.14), Color(1, 1, 1, 0.24), Color(1, 1, 1, 0.95), Color(1, 1, 1, 0.5), Color(1, 1, 1, 0)])
	g.gradient = gr
	return g


func _burst(p: Vector3, st: String, col: Color) -> void:
	match st:
		"burn":
			_particles(p, "fire", col)
			_particles(p + Vector3(0, 1.5, 0), "smoke", Color("#3a3530"))
			_light(p + Vector3(0, 1.5, 0), Color("#ff9a4a"), 4.0, 1.0)
		"flood":
			_particles(p, "splash", Color("#3d86c6"))
			_ring(p + Vector3(0, -0.6, 0), col, 0.9)
		"plague":
			_particles(p, "mist", col)
		_:
			_particles(p, "magic", col)
			_light(p, col, 2.5, 0.5)


## 11/3 이감 (둔화 · 수몰) —— 발 묶인 부대 발밑에 물빛 소용돌이가 돈다. 파갑 —— 갑옷 깨짐 표시 켜기
var slow_marks := {}          # 부대 key -> [소용돌이 Decal, 마법진 Decal, 물방울 입자]
var _swirl_tex: Texture2D = null
func _slow_marks() -> void:
	for sq in order:
		var br: bool = sq.alive and sq.statuses.has("cut_def")
		if br and not sq.armor_broken:
			sq.break_t = clock        # 파갑 —— 병사가 잠깐 옅게 번쩍만 (11/3 사용자 2차: 기믹 티를 내지 않는다)
		sq.armor_broken = br
		var on: bool = sq.alive and sq.state != "gone" and sq.statuses.has("flood")
		var m: Array = slow_marks.get(sq.key, [])
		if on and m.is_empty():
			m = [_slow_decal(_swirl(), 0.0)]
			slow_marks[sq.key] = m
		if m.is_empty():
			continue
		if not on:
			for x in m:
				if is_instance_valid(x): x.queue_free()
			slow_marks.erase(sq.key)
			continue
		# 11/3 사용자 2차: 발밑 장식이 전장을 지저분하게 만든다 —— 부대 발밑 크기로 작고 옅게, 발광 없이
		var r: float = (maxf(sq.cols * sq.sp, sq.depth()) * 0.9 + 6.0) * S
		var d0: Decal = m[0]
		d0.size = Vector3(r, 4.0, r)
		d0.position = p3(sq.pos - sq.fwd * sq.depth() * 0.5)
		d0.rotation.y = fposmod(clock * 0.8, TAU)
		d0.modulate.a = 0.2


func _slow_decal(tex: Texture2D, energy: float) -> Decal:
	var d := Decal.new()
	d.texture_albedo = tex
	if energy > 0.0:
		d.texture_emission = _premul(tex)      # 발광은 알파로 가려지지 않는다 —— 투명한 곳은 검게 (안 그러면 흰 사각판이 깔린다)
		d.emission_energy = energy
	d.modulate = Color("#58b4ff")
	d.albedo_mix = 1.0
	d.upper_fade = 0.3
	d.lower_fade = 0.3
	d.cull_mask = 1
	unit_root.add_child(d)
	return d


## 파갑 —— 부대 병사가 0.5초 동안 강하게 번쩍(주황 → 흰빛)하고, 갑옷 파편이 튀고, 고리 · 빛이 터진다
var on_break := Callable()     # BattleView 가 "파갑!" 글자를 띄운다
func _armor_break(sq: Squad) -> void:
	sq.break_t = clock
	var c := p3(sq.pos - sq.fwd * sq.depth() * 0.5, 1.2)
	var em := _particles(c, "magic", Color("#ffb347"))
	em.amount = 28
	em.emission_sphere_radius = maxf(3.0, sq.cols * sq.sp * S * 0.5)
	_ring(c, Color("#ffb347"), 0.6)
	_light(c + Vector3(0, 2, 0), Color("#ffa040"), 5.0, 0.4)
	if on_break.is_valid():
		on_break.call(sq.key)


var _premul_cache := {}
func _premul(tex: Texture2D) -> Texture2D:
	if _premul_cache.has(tex):
		return _premul_cache[tex]
	var img := tex.get_image()
	img.convert(Image.FORMAT_RGBA8)
	for y in img.get_height():
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			img.set_pixel(x, y, Color(c.r * c.a, c.g * c.a, c.b * c.a, 1.0))
	var t := ImageTexture.create_from_image(img)
	_premul_cache[tex] = t
	return t


## 바깥 마법진 —— 두 겹 고리 + 그 사이 눈금(룬 자리) 열둘
var _rune_tex: Texture2D = null
func _rune() -> Texture2D:
	if _rune_tex:
		return _rune_tex
	var n := 128
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	for y in n:
		for x in n:
			var v := Vector2(x + 0.5 - n / 2.0, y + 0.5 - n / 2.0) / (n / 2.0)
			var r := v.length()
			var ang := atan2(v.y, v.x)
			var a := exp(-pow((r - 0.95) / 0.025, 2.0)) + exp(-pow((r - 0.78) / 0.02, 2.0)) * 0.9
			if r > 0.8 and r < 0.93:
				var tick := absf(fposmod(ang * 12.0 / TAU, 1.0) - 0.5)
				a += clampf((0.08 - tick) * 14.0, 0.0, 1.0) * 0.9
			img.set_pixel(x, y, Color(1, 1, 1, clampf(a, 0.0, 1.0)))
	_rune_tex = ImageTexture.create_from_image(img)
	return _rune_tex


## 소용돌이 무늬 —— 바깥 고리 + 안쪽으로 감기는 팔 셋
func _swirl() -> Texture2D:
	if _swirl_tex:
		return _swirl_tex
	var n := 128
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	for y in n:
		for x in n:
			var v := Vector2(x + 0.5 - n / 2.0, y + 0.5 - n / 2.0) / (n / 2.0)
			var r := v.length()
			if r > 1.0:
				img.set_pixel(x, y, Color(1, 1, 1, 0))
				continue
			var ang := atan2(v.y, v.x)
			var arm := pow(0.5 + 0.5 * cos(3.0 * ang + r * 9.0), 6.0)
			var ring := exp(-pow((r - 0.9) / 0.05, 2.0))
			var a := clampf(arm * smoothstep(0.1, 0.5, r) * (1.0 - r) * 1.6 + ring * 0.9 + 0.12 * (1.0 - r), 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, a))
	_swirl_tex = ImageTexture.create_from_image(img)
	return _swirl_tex


func _status_fx() -> void:
	_slow_marks()
	var live := {}
	for sq in order:
		if not sq.alive:
			continue
		for st in sq.statuses:
			var key: String = sq.key + "|" + st
			live[key] = true
			if not auras.has(key):
				var kind: String = {"burn": "fire", "plague": "mist", "flood": "splash", "bleed": "drop"}.get(st, "magic")
				var em := _particles(p3(sq.pos, 0.6), kind, ST_COL[st], true)
				em.amount = 10 if kind == "fire" else 6
				em.emission_sphere_radius = 2.6
				auras[key] = em
			auras[key].position = p3(sq.pos, 0.6)
	# 11/2 초월 · 불멸 · 신화 부대는 등급색 기운을 두른다 (신화일수록 크고 짙게)
	for sq in order:
		if not sq.alive or sq.tier < 6:
			continue
		var key: String = sq.key + "|tier"
		live[key] = true
		if not auras.has(key):
			var em := _particles(p3(sq.pos, 0.3), "magic", DB.TIER[sq.tier].c, true)
			em.amount = [8, 14, 24][sq.tier - 6]
			em.emission_sphere_radius = [3.2, 4.2, 5.4][sq.tier - 6]
			auras[key] = em
		auras[key].position = p3(sq.pos, 0.3)
	for key in auras.keys():
		if not live.has(key):
			auras[key].queue_free()
			auras.erase(key)


func _fx_step() -> void:
	# 화살
	var mm := arrow_mmi.multimesh
	var keep := []
	for a in arrows:
		var u: float = (clock - a.t0) / a.dur
		if u >= 1.0:
			if a.puff:
				_particles(a.p1, "dust", Color("#9c8a6c"))
			continue
		keep.append(a)
	arrows = keep
	for i in mm.instance_count:
		if i >= arrows.size():
			mm.set_instance_transform(i, HIDDEN)
			continue
		var a: Dictionary = arrows[i]
		var u: float = (clock - a.t0) / a.dur
		if u < 0:
			mm.set_instance_transform(i, HIDDEN)
			continue
		var p := _arc(a, u)
		var q := _arc(a, minf(1.0, u + 0.02))
		var dir := (q - p).normalized()
		mm.set_instance_transform(i, Transform3D(Basis.looking_at(dir, Vector3.UP).scaled(Vector3.ONE * 2.2), p))     # 10/31 화살을 크게 (멀리서도 보이게)
		mm.set_instance_custom_data(i, Color(0, 0, 0, 0))
	# 책략 구슬
	var ok := []
	for o in orbs:
		var u: float = (clock - o.t0) / o.dur
		if u >= 1.0:
			if o.light:
				_particles(o.p1, "magic", o.col)
			else:
				_burst(o.p1, o.st, o.col)
			o.n.queue_free()
			continue
		o.n.position = o.p0.lerp(o.p1, maxf(0, u)) + Vector3(0, sin(maxf(0, u) * PI) * 3.0, 0)
		ok.append(o)
	orbs = ok
	# 빛·고리
	var lk := []
	for l in lights:
		var u: float = (clock - l.t0) / l.life
		if u >= 1.0:
			l.n.queue_free()
			continue
		l.n.light_energy = l.e * (1.0 - u) * (0.85 + 0.15 * sin(clock * 30.0))
		lk.append(l)
	lights = lk
	var ak := []
	for a in areas:
		var au: float = (clock - a.t0) / a.life
		if au >= 1.0:
			a.n.queue_free()
			continue
		a.n.modulate.a = (minf(1.0, au * 5.0) if au < 0.6 else (1.0 - au) / 0.4) * a.peak
		ak.append(a)
	areas = ak
	var rk := []
	for r in rings:
		var u: float = (clock - r.t0) / r.life
		if u >= 1.0:
			r.n.queue_free()
			continue
		var s := lerpf(0.4, 1.7, u)
		r.n.scale = Vector3(s, 0.2, s)
		r.m.albedo_color = Color(r.col, 1.0 - u)
		rk.append(r)
	rings = rk
	var fk := []
	for n in fx_nodes:
		if clock >= n[1]:
			if is_instance_valid(n[0]):
				n[0].queue_free()
			continue
		fk.append(n)
	fx_nodes = fk


func _arc(a: Dictionary, u: float) -> Vector3:
	return a.p0.lerp(a.p1, u) + Vector3(0, a.h * 4.0 * u * (1.0 - u), 0)
