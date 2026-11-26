extends Node2D
## One depth-ordered instance stream for all living soldiers. Walk deformation
## uses the old 7x7 shape with continuous poses on the GPU, without per-soldier draws.
var atlas: Texture2D
var action_blue: Texture2D
var action_red: Texture2D
var myth_blue: Texture2D       # 11/24 신화 부대 전용 시트 (동작 시트와 같은 4×8 배치 · 인형을 MYTH_FIT 배로 줄여 위에 장식 자리)
var myth_red: Texture2D
var hero_atlas: Texture2D      # 11/24 신화 장수 인형 시트 (tools/scripts/make_myth_heroes.py · data/myth_heroes.json) —— 셀 HERO_CELL + 칸 번호
var hero_grid := Vector2(4, 3)
var immortal_hero_atlas: Texture2D
var immortal_hero_grid := Vector2(14, 12)
var transcendent_hero_atlas: Texture2D
var transcendent_hero_grid := Vector2(12, 5)
var soldiers: MultiMeshInstance2D
var shadows: MultiMeshInstance2D
var capacity := 0
var buffer := PackedFloat32Array()
var shadow_buffer := PackedFloat32Array()

func _ready() -> void:
	shadows = MultiMeshInstance2D.new()
	shadows.multimesh = MultiMesh.new()
	shadows.multimesh.transform_format = MultiMesh.TRANSFORM_2D
	shadows.multimesh.use_colors = true
	shadows.multimesh.mesh = _circle()
	add_child(shadows)
	soldiers = MultiMeshInstance2D.new()
	soldiers.multimesh = MultiMesh.new()
	soldiers.multimesh.transform_format = MultiMesh.TRANSFORM_2D
	soldiers.multimesh.use_colors = true
	soldiers.multimesh.use_custom_data = true
	soldiers.multimesh.mesh = _grid()
	soldiers.texture = atlas
	soldiers.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	var material_ := ShaderMaterial.new()
	material_.shader = preload("res://shaders/painted_batch.gdshader")
	material_.set_shader_parameter("idle_atlas", atlas)
	material_.set_shader_parameter("atlas_pixel_size", Vector2.ONE / atlas.get_size())
	if action_blue != null and action_red != null:
		material_.set_shader_parameter("action_blue", action_blue)
		material_.set_shader_parameter("action_red", action_red)
		material_.set_shader_parameter("action_blue_pixel_size", Vector2.ONE / action_blue.get_size())
		material_.set_shader_parameter("action_red_pixel_size", Vector2.ONE / action_red.get_size())
		if myth_blue != null and myth_red != null and myth_blue.get_size() == action_blue.get_size() and myth_red.get_size() == action_red.get_size():
			material_.set_shader_parameter("myth_blue", myth_blue)
			material_.set_shader_parameter("myth_red", myth_red)
			material_.set_shader_parameter("has_myth", true)
	if hero_atlas != null:
		material_.set_shader_parameter("hero_atlas", hero_atlas)
		material_.set_shader_parameter("hero_grid", hero_grid)
		material_.set_shader_parameter("hero_pixel_size", Vector2.ONE / hero_atlas.get_size())
		material_.set_shader_parameter("has_hero", true)
	if immortal_hero_atlas != null:
		material_.set_shader_parameter("immortal_hero_atlas", immortal_hero_atlas)
		material_.set_shader_parameter("immortal_hero_grid", immortal_hero_grid)
		material_.set_shader_parameter("immortal_hero_pixel_size", Vector2.ONE / immortal_hero_atlas.get_size())
		material_.set_shader_parameter("has_immortal_hero", true)
	if transcendent_hero_atlas != null:
		material_.set_shader_parameter("transcendent_hero_atlas", transcendent_hero_atlas)
		material_.set_shader_parameter("transcendent_hero_grid", transcendent_hero_grid)
		material_.set_shader_parameter("transcendent_hero_pixel_size", Vector2.ONE / transcendent_hero_atlas.get_size())
		material_.set_shader_parameter("has_transcendent_hero", true)
	soldiers.material = material_
	add_child(soldiers)

func _grid() -> ArrayMesh:
	var vertices := PackedVector2Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	for row in 7:
		for col in 7:
			var uv := Vector2(col, row) / 6.0
			vertices.append(uv - Vector2(0.5, 0.97))
			uvs.append(uv)
			if row < 6 and col < 6:
				var at := row * 7 + col
				indices.append_array([at, at + 7, at + 1, at + 1, at + 7, at + 8])
	return _mesh(vertices, indices, uvs)

func _circle() -> ArrayMesh:
	var vertices := PackedVector2Array([Vector2.ZERO])
	var indices := PackedInt32Array()
	for i in 17:
		vertices.append(Vector2.from_angle(TAU * i / 16.0))
		if i > 0:
			indices.append_array([0, i, i + 1])
	return _mesh(vertices, indices, PackedVector2Array())

func _mesh(vertices: PackedVector2Array, indices: PackedInt32Array, uv: PackedVector2Array) -> ArrayMesh:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_INDEX] = indices
	if not uv.is_empty():
		arrays[Mesh.ARRAY_TEX_UV] = uv
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, Mesh.ARRAY_FLAG_USE_2D_VERTICES)
	return mesh

const HURT_TINT := Color("#fff3df")      # 11/18 인형마다 문자열을 다시 읽던 것을 한 번만

func update_figures(figures: Array, ally: Color, enemy: Color) -> void:
	var count := figures.size()
	if count > capacity:
		capacity = maxi(64, capacity)
		while capacity < count:
			capacity *= 2
		soldiers.multimesh.instance_count = capacity
		shadows.multimesh.instance_count = capacity
		buffer.resize(capacity * 16)
		shadow_buffer.resize(capacity * 12)
	soldiers.multimesh.visible_instance_count = count
	shadows.multimesh.visible_instance_count = count
	for i in count:
		var f: Dictionary = figures[i]
		var h: float = f.h
		var p: Vector2 = f.p
		var cell_id := int(f.cell)
		var cavalry := ((cell_id - 32) % 32) / 4 == 1 if cell_id >= 32 else cell_id % 8 == 1
		var lift := pow(absf(sin(float(f.stride))), 3.0) * float(f.gait) * h * (0.027 if cavalry else 0.009)
		var c := cos(float(f.tilt))
		var s := sin(float(f.tilt))
		var sx := -h if f.mirror else h
		var b := i * 16
		buffer[b] = c * sx
		buffer[b + 1] = -s * h
		buffer[b + 2] = 0
		buffer[b + 3] = p.x
		buffer[b + 4] = s * sx
		buffer[b + 5] = c * h
		buffer[b + 6] = 0
		buffer[b + 7] = p.y - lift
		var cloth := Color.WHITE if int(f.cell) >= 16 else (ally if int(f.cell) < 8 else enemy)
		var tint := cloth if float(f.hurt) <= 0.0 else cloth.lerp(HURT_TINT, float(f.hurt) * 0.75)
		buffer[b + 8] = tint.r
		buffer[b + 9] = tint.g
		buffer[b + 10] = tint.b
		buffer[b + 11] = f.fade
		buffer[b + 12] = f.cell
		# Continuous poses retain small walking motion and avoid 12-pose stepping.
		buffer[b + 13] = f.stride
		buffer[b + 14] = f.gait
		buffer[b + 15] = 0
		var sh := i * 12
		shadow_buffer[sh] = h * 0.19
		shadow_buffer[sh + 1] = 0
		shadow_buffer[sh + 2] = 0
		shadow_buffer[sh + 3] = p.x
		shadow_buffer[sh + 4] = 0
		shadow_buffer[sh + 5] = h * 0.19 * 0.32
		shadow_buffer[sh + 6] = 0
		shadow_buffer[sh + 7] = p.y
		shadow_buffer[sh + 8] = 0.1
		shadow_buffer[sh + 9] = 0.08
		shadow_buffer[sh + 10] = 0.05
		shadow_buffer[sh + 11] = 0.0 if cell_id in [16, 17] else 0.25 * float(f.fade)
	if capacity > 0:
		soldiers.multimesh.buffer = buffer
		shadows.multimesh.buffer = shadow_buffer


## 11/24 신화 시트 인형은 칸의 MYTH_FIT 배 (tools/scripts/make_myth_troops.py FIT) —— 칸을 1 / MYTH_FIT 배로 그려 몸 크기를 맞춘다
const MYTH_FIT := 0.8
## 11/24 신화 장수 인형 —— 셀 96 + 칸 번호 (병사 동작 시트 32~95 다음). 모양 값 16 이상 = 적군 장수 (발밑 원 · 셰이더 테두리 기운을 진영색으로)
const HERO_CELL := 96.0
const HERO_ENEMY := 16.0
const HERO_RING_ALLY := Color(0.3, 0.62, 1.0)
const HERO_RING_ENEMY := Color(1.0, 0.32, 0.2)

## 11/19 묶음 배열판 (war_painting._figs) —— keys 정렬 순서(아래 16비트 = 인형 번호)로 버퍼를 채운다. 값 · 식은 update_figures 와 같다
func update_packed(figs: PackedFloat32Array, keys: PackedInt64Array, w: int, ally: Color, enemy: Color) -> void:
	var count := keys.size()
	if count > capacity:
		capacity = maxi(64, capacity)
		while capacity < count:
			capacity *= 2
		soldiers.multimesh.instance_count = capacity
		shadows.multimesh.instance_count = capacity
		buffer.resize(capacity * 16)
		shadow_buffer.resize(capacity * 12)
	soldiers.multimesh.visible_instance_count = count
	shadows.multimesh.visible_instance_count = count
	for i in count:
		var f := int(keys[i] & 0xFFFF) * w
		var px := figs[f]
		var py := figs[f + 1]
		var h := figs[f + 2]
		var cell := figs[f + 3]
		var fade := figs[f + 4]
		var tilt := figs[f + 5]
		var gait := figs[f + 6]
		var stride := figs[f + 7]
		var hurt := figs[f + 8]
		var sn := absf(sin(stride))
		var cell_id := int(cell)
		var hero := cell >= HERO_CELL
		var cavalry := ((cell_id - 32) % 32) / 4 == 1 if cell_id >= 32 else cell_id % 8 == 1
		var lift := sn * sn * sn * gait * h * (0.012 if hero else (0.027 if cavalry else 0.009))
		var c := cos(tilt)
		var s := sin(tilt)
		var style := figs[f + 11] if w > 11 else 0.0
		var hq := h / MYTH_FIT if style >= 8.0 and cell >= 32.0 and not hero else h      # 신화 시트 —— 장식 자리만큼 칸을 키운다 (몸 · 그림자 · 들썩임은 h 그대로)
		var sx := -hq if figs[f + 9] > 0.5 else hq
		var b := i * 16
		buffer[b] = c * sx
		buffer[b + 1] = -s * hq
		buffer[b + 2] = 0
		buffer[b + 3] = px
		buffer[b + 4] = s * sx
		buffer[b + 5] = c * hq
		buffer[b + 6] = 0
		buffer[b + 7] = py - lift
		var cloth := Color.WHITE if cell >= 16.0 else (ally if cell < 8.0 else enemy)
		var tint := cloth if hurt <= 0.0 else cloth.lerp(HURT_TINT, hurt * 0.75)
		buffer[b + 8] = tint.r
		buffer[b + 9] = tint.g
		buffer[b + 10] = tint.b
		buffer[b + 11] = fade
		buffer[b + 12] = cell
		buffer[b + 13] = stride
		buffer[b + 14] = gait
		buffer[b + 15] = style + (clampf(figs[f + 10], 0.0, 1.0) * 0.5 if w > 10 else 0.0)
		var sh := i * 12
		var r := h * (0.17 if hero else 0.19)
		shadow_buffer[sh] = r
		shadow_buffer[sh + 1] = 0
		shadow_buffer[sh + 2] = 0
		shadow_buffer[sh + 3] = px
		shadow_buffer[sh + 4] = 0
		shadow_buffer[sh + 5] = r * 0.32
		shadow_buffer[sh + 6] = 0
		shadow_buffer[sh + 7] = py
		if hero:      # 장수 발밑 —— 그림자 대신 진영색 원 (같은 묶음)
			var ring := HERO_RING_ENEMY if style >= HERO_ENEMY else HERO_RING_ALLY
			shadow_buffer[sh + 8] = ring.r
			shadow_buffer[sh + 9] = ring.g
			shadow_buffer[sh + 10] = ring.b
			shadow_buffer[sh + 11] = 0.5 * fade
			continue
		shadow_buffer[sh + 8] = 0.1
		shadow_buffer[sh + 9] = 0.08
		shadow_buffer[sh + 10] = 0.05
		shadow_buffer[sh + 11] = 0.0 if cell_id in [16, 17] else 0.25 * fade
	if capacity > 0:
		soldiers.multimesh.buffer = buffer
		shadows.multimesh.buffer = shadow_buffer
