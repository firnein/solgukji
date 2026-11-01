extends Node3D
## 실사 나무 굽기 (10/31 사용자: 카툰 · 로우폴리 느낌을 벗는다) —— Poly Haven CC0 나무 · 덤불(assets_src/polyhaven)은 한 그루가
## 수십만 폴리곤이라 수백 그루를 깔 수 없다. 옆에서(조금 위에서) 한 번 렌더링해 투명 그림으로 굽고, 전장은 그 그림을 세운 판으로 그린다.
## 실행 (화면 필요): godot --path . res://tests/bake_trees.tscn
## 결과: assets/trees/<이름>.png (512 x 512, 아래 가운데가 밑동) · trees.json (이름 -> 실제 높이 m, 너비/높이)

const SRC := "res://assets_src/polyhaven/"
const OUT := "res://assets/trees/"
const NAMES := ["pine_sapling_small", "fir_sapling", "jacaranda_tree", "shrub_03", "shrub_04"]
const SIZE := 512


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var vp := SubViewport.new()
	vp.size = Vector2i(SIZE, SIZE)
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
	env.environment.ambient_light_color = Color(0.72, 0.74, 0.7)
	env.environment.ambient_light_energy = 0.7
	env.environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	root.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.light_energy = 1.6
	sun.light_color = Color("#f2e6cf")
	root.add_child(sun)
	sun.look_at_from_position(Vector3(3, 6, 5), Vector3.ZERO)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	root.add_child(cam)
	var info := {}
	for n in NAMES:
		var path := "%s%s/%s_1k.gltf" % [SRC, n, n]
		var ps: PackedScene = load(path)
		if ps == null:
			push_warning("못 읽음 " + path)
			continue
		var m: Node3D = ps.instantiate()
		root.add_child(m)
		await get_tree().process_frame
		var box := AABB()
		var first := true
		for mi in m.find_children("*", "MeshInstance3D", true, false):
			var b: AABB = mi.global_transform * mi.get_aabb()
			box = b if first else box.merge(b)
			first = false
		var h := box.size.y
		var w := maxf(box.size.x, box.size.z)
		var side := maxf(h, w) * 1.04
		cam.size = side
		var c := box.get_center()
		# 조금 위(약 20°)에서 내려다본 옆모습 —— 전장 카메라 기울기와 맞춘다. 밑동이 그림 아래 가운데
		var look := Vector3(c.x, box.position.y + side * 0.5, c.z)
		cam.look_at_from_position(look + Vector3(0, sin(0.35), cos(0.35)) * 50.0, look)
		await get_tree().process_frame
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var img := vp.get_texture().get_image()
		img.convert(Image.FORMAT_RGBA8)
		img.save_png(ProjectSettings.globalize_path(OUT + n + ".png"))
		info[n] = {"h": snappedf(h, 0.01), "side": snappedf(side, 0.01)}
		print("구움 %s: 높이 %.2f m · 판 %.2f" % [n, h, side])
		m.queue_free()
		await get_tree().process_frame
	var f := FileAccess.open(OUT + "trees.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(info, "\t"))
	get_tree().quit()
