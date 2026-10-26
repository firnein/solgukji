extends Node3D
## 점검용 —— 장수·병사 모델을 한 줄로 세워 찍는다.  -- --shot=경로.png [--t=초 (애니메이션 시각)] [--walk] [--atk=0.5]

func _ready() -> void:
	var a := {}
	for arg in OS.get_cmdline_user_args():
		var kv := arg.trim_prefix("--").split("=", true, 1)
		a[kv[0]] = kv[1] if kv.size() > 1 else ""
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/soldier.gdshader")
	mat.set_shader_parameter("team_a", War3D.TEAM.A)
	mat.set_shader_parameter("team_b", War3D.TEAM.B)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color("#6f8a5a")
	env.environment.ambient_light_color = Color(0.7, 0.7, 0.75)
	env.environment.ambient_light_energy = 0.8
	add_child(env)
	var sun := DirectionalLight3D.new()
	add_child(sun)
	sun.look_at_from_position(Vector3(4, 8, 6), Vector3.ZERO)
	var list := [["G:창병", Models.general("창병"), "g_glaive"], ["G:도적", Models.general("도적"), "g_saber"], ["G:기병", Models.general("기병"), "g_lance"],
		["G:궁병", Models.general("궁병"), ""], ["G:책사", Models.general("책사"), ""],
		["창병", Models.body("창병"), "spear"], ["도적", Models.body("도적"), "sword"], ["궁병", Models.body("궁병"), ""], ["기병", Models.body("기병"), "lance"], ["책사", Models.body("책사"), ""]]
	var wm := {"spear": Models.spear(), "sword": Models.sword(), "lance": Models.lance(), "g_glaive": Models.glaive(), "g_saber": Models.saber(), "g_lance": Models.snake_lance()}
	var walk := a.has("walk")
	var atk := float(a.get("atk", "0"))
	var ph := float(a.get("ph", "0.25"))
	for i in list.size():
		var it: Array = list[i]
		var gen: bool = it[0].begins_with("G:")
		var x := (i % 5) * 2.6 - 5.2
		var z := 0.0 if gen else 3.2
		var sc := 1.3 if gen else 1.0
		var b := Basis(Vector3.UP, -PI * 0.5 + 0.5) * Basis.from_scale(Vector3.ONE * sc)   # 카메라 쪽 비스듬히
		var custom := Color(0.25, -atk, 0, ph + (0.0 if walk else 2.0))
		_inst(it[1], Transform3D(b, Vector3(x, 0, z)), mat, custom)
		if it[2] != "":
			var hand: Vector3 = War3D.HAND[it[2]]
			var piv: Vector2 = War3D.ARM_PIVOT[it[2]]
			var arm := 1.3 * sin(PI * atk)
			var hd := Vector2(hand.x - piv.x, hand.y - piv.y).rotated(arm)
			hand = Vector3(piv.x + hd.x, piv.y + hd.y, hand.z)
			var wang := -1.45 if it[2].ends_with("lance") or it[2] == "spear" else -0.55
			_inst(wm[it[2]], Transform3D(b * Basis(Vector3.BACK, wang + arm * 0.5), Vector3(x, 0, z) + b * hand), mat, custom)
	var cam := Camera3D.new()
	add_child(cam)
	cam.look_at_from_position(Vector3(0, 4.2, 10.5), Vector3(0, 1.0, 1.6))
	cam.fov = 45
	await get_tree().create_timer(float(a.get("t", "0.3"))).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(a.get("shot", "user://models.png"))
	get_tree().quit()


func _inst(mesh: Mesh, xf: Transform3D, mat: Material, custom: Color) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = mesh
	mm.instance_count = 1
	mm.set_instance_transform(0, xf)
	mm.set_instance_custom_data(0, custom)
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.material_override = mat
	add_child(mi)
