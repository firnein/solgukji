extends Node3D
## 임시 병사 그림 굽기 —— 지금 3D 병사 모델을 옆에서 여덟 동작으로 찍어 4 x 2 묶음 그림(병종별 PNG)을 만든다.
## 일러스트 병사 그림(prompts/병사_스프라이트)이 오기 전 그림 판 연출을 시험하려는 것. 세력색 부분은 마젠타로 찍는다.
## 실행 (화면 필요): godot --path . res://tests/bake_sprites.tscn [-- --out=res://assets/troops_sprite/ --tags=창병,궁병]
## 칸: 1 서 있기 · 2 걷기 A · 3 걷기 B · 4 공격 준비 · 5 공격 · 6 맞음 · 7 쓰러짐 · 8 서 있기(예비)

const CELL := 256
const TAGS := ["창병", "도적", "기병", "궁병", "책사", "유생", "술사", "모사"]


func _ready() -> void:
	var a := {}
	for arg in OS.get_cmdline_user_args():
		var kv := arg.trim_prefix("--").split("=", true, 1)
		a[kv[0]] = kv[1] if kv.size() > 1 else ""
	var out: String = a.get("out", "res://assets/troops_sprite/")
	var tags: Array = Array(str(a.get("tags", ",".join(TAGS))).split(","))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out))
	var vp := SubViewport.new()
	vp.size = Vector2i(CELL, CELL)
	vp.transparent_bg = true
	vp.own_world_3d = true
	vp.msaa_3d = Viewport.MSAA_8X
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)
	var root := Node3D.new()
	vp.add_child(root)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_CLEAR_COLOR
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.75, 0.75, 0.8)
	env.environment.ambient_light_energy = 0.9
	root.add_child(env)
	var sun := DirectionalLight3D.new()
	root.add_child(sun)
	sun.look_at_from_position(Vector3(2, 6, 7), Vector3.ZERO)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	root.add_child(cam)
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/soldier.gdshader")
	mat.set_shader_parameter("team_a", Color(1, 0, 1))
	mat.set_shader_parameter("team_glow", 0.0)
	var weapons := {"spear": Models.spear(), "sword": Models.sword(), "lance": Models.lance()}
	for tag in tags:
		var cav: bool = tag == "기병"
		var body := Models.body(tag)
		var wk: String = War3D.WEAPON.get(tag, "")
		var h := 2.7 if cav else 1.75
		cam.size = h * 1.02
		cam.look_at_from_position(Vector3(0.1 if not cav else 0.0, h * 0.5, 10), Vector3(0.1 if not cav else 0.0, h * 0.5, 0))
		var atlas := Image.create(CELL * 4, CELL * 2, false, Image.FORMAT_RGBA8)
		for f in 8:
			for c in root.get_children():
				if c is MultiMeshInstance3D:
					c.queue_free()
			var b := Basis()
			var custom := Color(0.25, 0, 0, 2.25)
			var atk := 0.0
			match f:
				1: custom.a = 0.25
				2: custom.a = 0.75
				3: atk = 0.25
				4: atk = 0.6
				5: b = Basis(Vector3.BACK, 0.3)
				6: b = Basis(Vector3.BACK, PI * 0.47)
			custom.g = -atk
			_inst(root, body, Transform3D(b, Vector3.ZERO), mat, custom)
			if wk != "":
				var hand: Vector3 = War3D.HAND[wk]
				var piv: Vector2 = War3D.ARM_PIVOT[wk]
				var arm := 1.3 * sin(PI * atk)
				var hd := Vector2(hand.x - piv.x, hand.y - piv.y).rotated(arm)
				hand = Vector3(piv.x + hd.x, piv.y + hd.y, hand.z)
				var wang := -1.45 if wk == "lance" or wk == "spear" else -0.55
				_inst(root, weapons[wk], Transform3D(b * Basis(Vector3.BACK, wang + arm * 0.5), b * hand), mat, custom)
			await get_tree().process_frame
			await RenderingServer.frame_post_draw
			var img := vp.get_texture().get_image()
			img.convert(Image.FORMAT_RGBA8)
			atlas.blit_rect(img, Rect2i(0, 0, CELL, CELL), Vector2i((f % 4) * CELL, (f / 4) * CELL))
		atlas.save_png(ProjectSettings.globalize_path(out + tag + ".png"))
		print("구움 ", tag)
	get_tree().quit()


func _inst(parent: Node, mesh: Mesh, xf: Transform3D, mat: Material, custom: Color) -> void:
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
	parent.add_child(mi)
