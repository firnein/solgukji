extends Node3D
## GPU VAT 병종(기병) 보기 —— 구운 말을 동작별로 한 줄 세워 찍는다 (화면 필요). -- --tag=기병 --shot=경로.png
## 옛 soldier_vat 셰이더로 보여 준다 (같은 VAT 배치). 왼쪽부터: 서 있기 · 달리기 4박자 · 공격 3단계 · 맞음 · 쓰러짐 · 적

func _ready() -> void:
	var a := {}
	for arg in OS.get_cmdline_user_args():
		var kv := arg.trim_prefix("--").split("=", true, 1)
		a[kv[0]] = kv[1] if kv.size() > 1 else ""
	var tag: String = a.get("tag", "기병")
	var base := "res://assets/models/vat/" + tag
	var info = JSON.parse_string(FileAccess.get_file_as_string(base + ".json"))
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/soldier_vat.gdshader")
	m.set_shader_parameter("vat_pos", ImageTexture.create_from_image(load(base + "_pos.res")))
	m.set_shader_parameter("vat_nrm", ImageTexture.create_from_image(load(base + "_nrm.res")))
	var white := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	white.fill(Color.WHITE)
	m.set_shader_parameter("palette", ImageTexture.create_from_image(white))
	m.set_shader_parameter("team_a", War3D.TEAM.A)
	m.set_shader_parameter("team_b", War3D.TEAM.B)
	for c in info.clips:
		m.set_shader_parameter("clip_" + c, Vector2(info.clips[c][0], info.clips[c][1]))
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color("#6f8a5a")
	env.environment.ambient_light_color = Color(0.7, 0.7, 0.75)
	env.environment.ambient_light_energy = 0.8
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.shadow_enabled = true
	add_child(sun)
	sun.look_at_from_position(Vector3(4, 8, 6), Vector3.ZERO)
	var poses := [Color(0.25, 0, 0, 2.0), Color(0.25, 0, 0, 0.0), Color(0.25, 0, 0, 0.25), Color(0.25, 0, 0, 0.5), Color(0.25, 0, 0, 0.75),
		Color(0.25, -0.2, 0, 2.0), Color(0.25, -0.5, 0, 2.0), Color(0.25, -0.85, 0, 2.0), Color(0.25, 0, 0.45, 2.0), Color(0.25, 0.42, 0, 2.0), Color(1.25, 0, 0, 2.0)]
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = load(base + "_mesh.res")
	mm.instance_count = poses.size()
	for i in poses.size():
		var b := Basis(Vector3.UP, -PI * 0.5 + float(a.get("yaw", "0.6")))
		mm.set_instance_transform(i, Transform3D(b, Vector3((i - poses.size() / 2.0) * 2.0, 0, 0)))
		mm.set_instance_custom_data(i, poses[i])
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.material_override = m
	add_child(mi)
	var plane := MeshInstance3D.new()
	plane.mesh = PlaneMesh.new()
	plane.mesh.size = Vector2(40, 12)
	add_child(plane)
	var cam := Camera3D.new()
	add_child(cam)
	cam.look_at_from_position(Vector3(0, 3.2, 12.0), Vector3(0, 1.0, 0))
	cam.fov = 55
	await get_tree().create_timer(float(a.get("t", "0.4"))).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(a.get("shot", "user://vat.png"))
	get_tree().quit()
