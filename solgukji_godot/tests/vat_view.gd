extends Node3D
## 구운 병사 보기 —— 동작별로 한 줄 세워 찍는다 (화면 필요).  -- --tag=창병 --shot=경로.png [--t=초]
## 왼쪽부터: 서 있기 · 걷기(4박자) · 공격(3단계) · 맞음 · 쓰러짐 · 적 진영

func _ready() -> void:
	var a := {}
	for arg in OS.get_cmdline_user_args():
		var kv := arg.trim_prefix("--").split("=", true, 1)
		a[kv[0]] = kv[1] if kv.size() > 1 else ""
	var tag: String = a.get("tag", "창병")
	var w := War3D.new()
	w.vat_enabled = true
	w._load_vat()
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
	mm.mesh = w.vat_mesh[tag]
	mm.instance_count = poses.size()
	for i in poses.size():
		var b := Basis(Vector3.UP, -PI * 0.5 + 0.6)
		mm.set_instance_transform(i, Transform3D(b, Vector3((i - poses.size() / 2.0) * 1.0, 0, 0)))
		mm.set_instance_custom_data(i, poses[i])
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.material_override = w.vat_mat[tag]
	add_child(mi)
	var plane := MeshInstance3D.new()
	plane.mesh = PlaneMesh.new()
	plane.mesh.size = Vector2(30, 10)
	add_child(plane)
	var cam := Camera3D.new()
	add_child(cam)
	cam.look_at_from_position(Vector3(0, 2.2, 7.5), Vector3(0, 0.7, 0))
	cam.fov = 50
	w.free()
	await get_tree().create_timer(float(a.get("t", "0.4"))).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(a.get("shot", "user://vat.png"))
	get_tree().quit()
