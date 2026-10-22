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
const TEAM := {"A": Color("#3f7fd0"), "B": Color("#c8463c")}
const ST_COL := {"burn": Color("#ff8a3c"), "flood": Color("#4a9ad4"), "confuse": Color("#b57edc"),
	"bleed": Color("#c4564a"), "plague": Color("#7fa86b"), "seal": Color("#9a9a9a")}
const WEAPON := {"창병": "spear", "도적": "sword", "기병": "lance"}
const HAND := {"spear": Vector3(0.16, 0.74, 0.24), "sword": Vector3(0.2, 0.74, 0.22), "lance": Vector3(0.16, 1.62, 0.27)}
const HIDDEN := Transform3D(Basis(Vector3.ZERO, Vector3.ZERO, Vector3.ZERO), Vector3(0, -500, 0))

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
var capes := {}             # 부대 key -> MeshInstance3D
var banners := {}           # 부대 key -> Node3D
var unit_root: Node3D
var fx_root: Node3D
var arrow_mmi: MultiMeshInstance3D
var arrows := []
var orbs := []
var lights := []
var rings := []
var fx_nodes := []
var auras := {}
var _soft: Texture2D
var _pmat := {}
var _duel_t := 0.0
var shake := 0.0
var _hs := PackedFloat32Array()   # 지형 높이 격자 —— 지형을 만들 때 채운다
var _hn := 0
var _hstep := 1.0
var _hhalf := 0.0
var _bufs := {}             # MultiMesh -> 인스턴스 버퍼 (변환 12 + 사용자 4 = 16 float)
var prof := {}              # 점검용 —— 구간별 누적 시간 (마이크로초)
var dbg_nofx := false       # 점검용 —— 파티클을 만들지 않는다
var ult: UltFx
var _cine := 0.0            # 고유기 카메라 연출이 남은 시간 (실시간)
var _cine_back := []        # 연출 전 카메라 [대상, 거리, 높이각]


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
	weapon_mesh = {"spear": Models.spear(), "sword": Models.sword(), "lance": Models.lance()}
	unit_root = Node3D.new()
	add_child(unit_root)
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
	cam.fov = 50
	cam.far = 2000
	add_child(cam)
	cam.current = true
	_update_cam(1.0)


# ───────── 무대 ─────────

## 지형 높이 —— 격자가 있으면 격자에서 보간한다 (노이즈를 매번 다시 계산하지 않는다)
func height(x: float, z: float) -> float:
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
	var psm := ProceduralSkyMaterial.new()
	psm.sky_top_color = Color("#3a5578")
	psm.sky_horizon_color = Color("#d8c4a4")
	psm.ground_horizon_color = Color("#9a8a70")
	psm.ground_bottom_color = Color("#2b2a26")
	psm.sky_curve = 0.12
	psm.sun_angle_max = 25
	sky.sky_material = psm
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 0.95
	env.ssao_enabled = true
	env.ssao_intensity = 1.6
	env.ssao_radius = 1.2
	env.glow_enabled = true
	env.glow_intensity = 0.55
	env.glow_bloom = 0.04
	env.fog_enabled = true
	env.fog_light_color = Color("#9fb0bf")
	env.fog_density = 0.0011
	env.fog_aerial_perspective = 0.6
	env.fog_sky_affect = 0.25
	env.volumetric_fog_enabled = true
	env.volumetric_fog_density = 0.0012
	env.volumetric_fog_albedo = Color("#c8d0d8")
	env.volumetric_fog_length = 220
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.05
	env.adjustment_contrast = 1.1
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.light_color = Color("#ffdcb0")
	sun.light_energy = 1.7
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 240
	sun.shadow_blur = 1.5
	add_child(sun)
	sun.look_at_from_position(Vector3(-45, 78, 62), Vector3.ZERO)


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
			var c := Color(0.24, 0.32, 0.14).lerp(Color(0.40, 0.42, 0.20), n2)
			var n3 := noise.get_noise_2d(x * 3.1 - 40.0, z * 3.1) * 0.5 + 0.5
			var trample := (1.0 - smoothstep(22.0, 58.0, absf(x))) * (1.0 - smoothstep(16.0, 34.0, absf(z))) * clampf(n3 * 1.6 - 0.2, 0, 1)
			c = c.lerp(Color(0.36, 0.30, 0.21), trample * 0.7)
			var slope := 1.0 - nn.y
			c = c.lerp(Color(0.42, 0.41, 0.38), smoothstep(0.18, 0.42, slope))
			c = c.lerp(Color(0.18, 0.26, 0.14), smoothstep(80.0, 200.0, Vector2(x * 0.8, z * 1.5).length()) * 0.5)
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
		_scatter(Models.pine(r2), pines[i])
		_scatter(Models.broadleaf(r2), leafs[i])
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
	for t in 16000:
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
	for c in unit_root.get_children():
		c.queue_free()
	for c in fx_root.get_children():
		c.queue_free()
	squads.clear()
	order.clear()
	entries.clear()
	bodies.clear()
	weapons.clear()
	capes.clear()
	banners.clear()
	auras.clear()
	arrows.clear()
	orbs.clear()
	lights.clear()
	rings.clear()
	fx_nodes.clear()
	ult.clear()
	for i in arrow_mmi.multimesh.instance_count:
		arrow_mmi.multimesh.set_instance_transform(i, HIDDEN)
	clock = 0.0


func setup(res: Dictionary) -> void:
	clear()
	for r in res.roster:
		var at := slot_pos(r.camp, res.aForm if r.camp == "A" else res.bForm, r.slot)
		var sq := Squad.new(r, at, rng)
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
			var wk: String = WEAPON.get(sq.tag, "")
			var idx: int = count.get(sq.tag, 0)
			count[sq.tag] = idx + 1
			var widx := -1
			if wk != "":
				widx = wcount.get(wk, 0)
				wcount[wk] = widx + 1
			# [부대, 병사, 병종, 번호, 무기, 무기번호, 장수, 정착(더 이상 안 변함), 기병]
			entries.append([sq, s, sq.tag, idx, wk, widx, gen, false, sq.cls == "cav"])
		if sq.general:
			var cp := MeshInstance3D.new()
			cp.mesh = Models.cape()
			var m := StandardMaterial3D.new()
			m.albedo_color = DB.tier_color(sq.cid)
			m.cull_mode = BaseMaterial3D.CULL_DISABLED
			m.roughness = 0.7
			cp.material_override = m
			unit_root.add_child(cp)
			capes[sq.key] = cp
		banners[sq.key] = _make_banner(sq)
	_bufs.clear()
	for tag in count:
		bodies[tag] = _mm(body_mesh[tag], count[tag])
		_bufs[tag] = _new_buf(count[tag])
	for wk in wcount:
		weapons[wk] = _mm(weapon_mesh[wk], wcount[wk])
		_bufs[wk] = _new_buf(wcount[wk])
	_sync()


func _mm(mesh: Mesh, n: int) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = mesh
	mm.instance_count = n
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.material_override = soldier_mat
	unit_root.add_child(mi)
	return mi


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
		want_t += mv * dt * want_dist * 0.9
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
	if _duel_t <= 0:
		_duel_t = 0.3
		_pair_duels()
	t = pt("짝짓기", t)
	_separate(dt)
	_status_fx()
	ult.step()
	_fx_step()
	t = pt("효과갱신", t)
	_sync()
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


func _separate(dt: float) -> void:
	for i in order.size():
		var a: Squad = order[i]
		if not a.alive:
			continue
		for j in range(i + 1, order.size()):
			var b: Squad = order[j]
			if not b.alive or a.engaged == b or b.engaged == a or a.contact or b.contact:
				continue
			var d := a.pos - b.pos
			if d.length() < 70.0 and d.length() > 0.01:
				var push := d.normalized() * (70.0 - d.length()) * dt * 3.0
				if a.state != "hold": a.pos += push
				if b.state != "hold": b.pos -= push


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


func _xform(sq: Squad, s, gen: bool) -> Array:
	var x: float = s.pos.x * S
	var z: float = s.pos.y * S
	var y := height(x, z)
	var b := Basis(Vector3.UP, -s.yaw)
	var dark := 0.0
	var flash := 0.0
	var dead: bool = not s.alive and s.die_t >= 0 and clock >= s.die_t
	if dead:
		var u := minf(1.0, (clock - s.die_t) / 0.4)
		b = b * Basis(Vector3.RIGHT, s.fall * u * PI * 0.48)
		dark = 0.42 * u
	elif not s.alive and s.die_t < 0:
		return [HIDDEN, Color(), false]
	else:
		if sq.state == "gone":
			return [HIDDEN, Color(), false]
		var cav: bool = sq.tag == "기병"
		y += absf(sin(s.walk * 0.9)) * (0.16 if cav else 0.08)
		if cav:
			b = b * Basis(Vector3.BACK, sin(s.walk * 0.45) * 0.07)
		# 공격하며 앞으로 기울고, 맞으면 뒤로 젖힌다
		var a: float = (clock - s.atk_t0) / Squad.ATTACK_TIME
		if a >= 0 and a <= 1 and not cav:
			b = b * Basis(Vector3.BACK, -0.28 * sin(PI * a))
		var h: float = (clock - s.hit_t) / 0.3
		if h >= 0 and h <= 1:
			b = b * Basis(Vector3.BACK, 0.3 * sin(PI * h))
		if sq.cheer and s.slot % 3 == 0:
			y += maxf(0, sin(clock * 9.0 + s.phase)) * 0.35
		flash = sq.hurt * 0.35
	b = b * Basis.from_scale(Vector3.ONE * (1.25 if gen else s.size))
	var team := 0.0 if sq.camp == "A" else 1.0
	return [Transform3D(b, Vector3(x, y, z)), Color(team, dark, flash, s.tint), not dead]


## 병사 → GPU 버퍼. 병종마다 버퍼 하나에 몰아 쓰고 프레임 끝에 한 번만 넘긴다.
## 다 쓰러진 시신과 떠나 버린 병사는 한 번 쓴 뒤로 다시 계산하지 않는다(정착).
func _sync() -> void:
	var bufs := {}
	for k in _bufs:
		bufs[k] = _bufs[k]
	for e in entries:
		var sq: Squad = e[0]
		var s = e[1]
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
			if e[6] and capes.has(sq.key):
				capes[sq.key].visible = false
			continue
		# 그대로 서 있고 동작도 없으면 지난번 값을 그대로 둔다
		var anim: bool = dead or clock - s.atk_t0 < Squad.ATTACK_TIME or clock - s.hit_t < 0.3 or sq.cheer \
			or (s.spawn_t >= 0 and clock - s.spawn_t < 0.5)
		var wang := _weapon_angle(sq, s, wk, not dead) if wk != "" else 0.0
		# 눈에 띄지 않을 만큼만 움직였으면 건너뛴다 (0.5cm · 0.2도)
		if not anim and absf(s.pos.x - s.drawn.x) < 0.05 and absf(s.pos.y - s.drawn.y) < 0.05 \
				and absf(s.yaw - s.drawn.z) < 0.004 and absf(wang - s.drawn_w) < 0.01:
			continue
		s.drawn = Vector3(s.pos.x, s.pos.y, s.yaw)
		s.drawn_w = wang
		var x: float = s.pos.x * S
		var z: float = s.pos.y * S
		var y := height(x, z)
		var b := Basis(Vector3.UP, -s.yaw)
		var dark := 0.0
		var flash := 0.0
		var settle := false
		if dead:
			var u := minf(1.0, (clock - s.die_t) / 0.4)
			b = b * Basis(Vector3.RIGHT, s.fall * u * PI * 0.48)
			dark = 0.42 * u
			settle = u >= 1.0
		else:
			var cav: bool = e[8]
			y += absf(sin(s.walk * 0.9)) * (0.16 if cav else 0.08)
			if cav:
				b = b * Basis(Vector3.BACK, sin(s.walk * 0.45) * 0.07)
			var a: float = (clock - s.atk_t0) / Squad.ATTACK_TIME
			if a >= 0 and a <= 1 and not cav:
				b = b * Basis(Vector3.BACK, -0.28 * sin(PI * a))
			var h: float = (clock - s.hit_t) / 0.3
			if h >= 0 and h <= 1:
				b = b * Basis(Vector3.BACK, 0.3 * sin(PI * h))
				flash = 0.45 * sin(PI * h)          # 맞은 병사만 번쩍인다
			if sq.cheer and s.slot % 3 == 0:
				y += maxf(0, sin(clock * 9.0 + s.phase)) * 0.35
		var sc: float = 1.25 if e[6] else s.size
		b = b * Basis.from_scale(Vector3(sc, sc, sc))
		var p := Vector3(x, y, z)
		var team := 0.0 if sq.camp == "A" else 1.0
		_put(bbuf, o, b, p, team, dark, flash, s.tint)
		bufs[e[2]] = bbuf
		if wk != "":
			var wb: PackedFloat32Array = bufs[wk]
			var hand: Vector3 = HAND[wk]
			if wk != "sword" and not dead and sq.contact:
				hand += Vector3(0.45 * sin(PI * clampf((clock - s.atk_t0) / Squad.ATTACK_TIME, 0, 1)), 0, 0)   # 찌르기
			var wbasis := b * Basis(Vector3.BACK, wang)
			_put(wb, e[5] * 16, wbasis, p + b * hand, team, dark, flash, s.tint)
			bufs[wk] = wb
		if e[6] and capes.has(sq.key):
			capes[sq.key].transform = Transform3D(b, p)
			capes[sq.key].visible = true
		e[7] = settle
	for k in bufs:
		_bufs[k] = bufs[k]
		var mmi: MultiMeshInstance3D = bodies.get(k, weapons.get(k))
		mmi.multimesh.buffer = bufs[k]
	for sq in order:
		var bn: Node3D = banners[sq.key]
		bn.visible = sq.alive and sq.state != "gone"
		if bn.visible:
			var at: Vector2 = sq.general.pos if sq.general and sq.general.alive else sq.pos - sq.fwd * (sq.depth() + 6)
			bn.position = p3(at)
			bn.rotation = Vector3(0, atan2(-sq.fwd.y, sq.fwd.x) + PI, 0)


func _weapon_angle(sq: Squad, s, kind: String, alive: bool) -> float:
	var front: bool = alive and sq.rank_of(s) < 2
	var ready: bool = front and (sq.contact or (sq.engaged != null and sq.pos.distance_to(sq.engaged.pos) < 140.0))
	var a := clampf((clock - s.atk_t0) / Squad.ATTACK_TIME, 0, 1)
	match kind:
		"spear":
			return -1.38 if ready else -0.1
		"sword":
			if sq.contact and front and a < 1.0:
				return lerpf(-2.6, -0.3, a)          # 머리 위에서 내려친다
			return -1.9 if ready else -0.55
		"lance":
			return -1.45 if ready or (sq.moving and sq.engaged != null) else -0.22
	return 0.0


# ───────── 카메라 —— 휠 확대, 오른쪽 끌기 회전, 왼쪽 끌기·WASD 이동, Q/E 회전 ─────────

func _update_cam(dt: float) -> void:
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


func reset_camera() -> void:
	# 입장 연출 —— 아군 뒤 낮은 곳에서 시작해 전장 전체로 물러난다
	cam_t = Vector3(-34, 0, 6)
	cam_yaw = -0.55
	cam_pitch = 0.16
	cam_dist = 24.0
	want_t = Vector3(-4, 0, 0)
	want_yaw = 0.0
	want_pitch = 0.6
	want_dist = 62.0
	cam_rate = 0.9
	_intro = 3.5
	_update_cam(0.0)


## 고유기 카메라 —— 장수 쪽으로 다가갔다가 끝나면 원래 자리로 돌아간다
func cinematic(sq: Squad, dur: float) -> void:
	if _cine <= 0:
		_cine_back = [want_t, want_dist, want_pitch]
	_cine = dur
	var p := p3(sq.pos)
	want_t = want_t.lerp(Vector3(p.x, 0, p.z), 0.65)
	want_dist = minf(want_dist, 34.0)
	want_pitch = clampf(want_pitch - 0.12, 0.3, 1.2)
	cam_rate = 3.0


func focus(sq: Squad) -> void:
	want_t = p3(sq.pos)
	want_dist = minf(want_dist, 30.0)
	cam_rate = 4.0


func camera_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.pressed:
		if e.button_index == MOUSE_BUTTON_WHEEL_UP:
			want_dist = clampf(want_dist * 0.88, 8.0, 170.0)
			cam_rate = 4.0
		elif e.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			want_dist = clampf(want_dist / 0.88, 8.0, 170.0)
			cam_rate = 4.0
	elif e is InputEventMouseMotion:
		if e.button_mask & MOUSE_BUTTON_MASK_RIGHT:
			want_yaw += e.relative.x * 0.006
			want_pitch = clampf(want_pitch + e.relative.y * 0.004, 0.12, 1.42)
			cam_rate = 6.0
		elif e.button_mask & (MOUSE_BUTTON_MASK_LEFT | MOUSE_BUTTON_MASK_MIDDLE):
			var fw := Vector3(cos(want_yaw), 0, sin(want_yaw))
			var rt := Vector3(-sin(want_yaw), 0, cos(want_yaw))
			want_t += (-rt * e.relative.x + fw * e.relative.y) * want_dist * 0.0017
			cam_rate = 8.0


func to_screen(p: Vector2, lift: float) -> Vector2:
	var w := p3(p, lift)
	if cam.is_position_behind(w):
		return Vector2(-99999, -99999)
	return cam.unproject_position(w)


## 머리표 투명도 —— 가까이 볼 때 멀리 있는 부대의 표가 지평선에 쌓이지 않게 흐린다
func label_alpha(p: Vector2) -> float:
	var d := cam.position.distance_to(p3(p))
	return 1.0 - smoothstep(cam_dist * 1.5 + 10.0, cam_dist * 2.2 + 25.0, d)


# ───────── 명령 (연출 감독이 부른다) ─────────

func order_melee(akey: String, dkey: String) -> void:
	var a: Squad = squads.get(akey)
	var d: Squad = squads.get(dkey)
	if a == null or d == null or not a.alive or not d.alive:
		return
	_assign(a, d)


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
				_assign(sq, tgt)
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


func volley(akey: String, dkeys: Array, light := false) -> void:
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
		for i in mini(8 if light else 22, shooters.size() + 6):
			var p0 := p3(shooters[rng.randi() % shooters.size()].pos, 1.5)
			var tp: Vector2 = targets[rng.randi() % targets.size()].pos if not targets.is_empty() else d.pos
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


func clash(akey: String, dkey: String) -> void:
	var a: Squad = squads.get(akey)
	var d: Squad = squads.get(dkey)
	if a == null or d == null:
		return
	var dir := (a.pos - d.pos).normalized()
	var p := p3(d.pos + dir * d.depth() * 0.5 + Vector2(0, rng.randf_range(-20, 20)), 1.1)
	_particles(p, "spark", Color("#fff2b0"))
	if rng.randf() < 0.5:
		_particles(p + Vector3(0, -0.9, 0), "dust", Color("#a89270"))


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


func _status_fx() -> void:
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
		mm.set_instance_transform(i, Transform3D(Basis.looking_at(dir, Vector3.UP), p))
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
