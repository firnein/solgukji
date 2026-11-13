extends Node
## glb 들여다보기 —— godot --headless --path . res://tests/glb_info.tscn -- --glb=res://assets_src/quaternius/Horse.glb
func _ready() -> void:
	var a := {}
	for s in OS.get_cmdline_user_args():
		var kv := s.trim_prefix("--").split("=", true, 1)
		a[kv[0]] = kv[1] if kv.size() > 1 else "1"
	var ch: Node3D = (load(str(a.glb)) as PackedScene).instantiate()
	add_child(ch)
	for sk in ch.find_children("*", "Skeleton3D", true, false):
		print("뼈 %d: " % sk.get_bone_count(), range(sk.get_bone_count()).map(func(i): return sk.get_bone_name(i)))
	for mi in ch.find_children("*", "MeshInstance3D", true, false):
		var m: Mesh = mi.mesh
		var tri := 0
		for s in m.get_surface_count():
			var arr := m.surface_get_arrays(s)
			tri += (arr[Mesh.ARRAY_INDEX].size() if arr[Mesh.ARRAY_INDEX] else arr[Mesh.ARRAY_VERTEX].size()) / 3
			var mat = mi.get_active_material(s)
			print("  면 %d 재질: %s 텍스처: %s" % [s, mat.resource_name if mat else "-", (mat.albedo_texture != null) if mat is BaseMaterial3D else "?"])
		print("메시 %s (부모 %s): 면 %d 삼각형 %d aabb %s" % [mi.name, mi.get_parent().name, m.get_surface_count(), tri, mi.get_aabb()])
	for ap in ch.find_children("*", "AnimationPlayer", true, false):
		for n in ap.get_animation_list():
			print("동작 %s %.2fs" % [n, ap.get_animation(n).length])
	get_tree().quit()
