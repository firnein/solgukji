extends Node2D
## One depth-ordered instance stream for all living soldiers. Walk deformation
## uses the old 7x7 shape with continuous poses on the GPU, without per-soldier draws.
var atlas: Texture2D
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
	material_.set_shader_parameter("atlas_pixel_size", Vector2.ONE / atlas.get_size())
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
		var lift := pow(absf(sin(float(f.stride))), 3.0) * float(f.gait) * h * (0.027 if int(f.cell) % 8 == 1 else 0.009)
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
		var cloth := ally if int(f.cell) < 8 else enemy
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
		shadow_buffer[sh + 11] = 0.25 * float(f.fade)
	if capacity > 0:
		soldiers.multimesh.buffer = buffer
		shadows.multimesh.buffer = shadow_buffer
