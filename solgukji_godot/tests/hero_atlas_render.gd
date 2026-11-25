extends Control

const Painting = preload("res://scripts/field/war_painting.gd")
const COLUMNS := 8
const BG := Color("#221c19")

func _ready() -> void:
	RenderingServer.set_default_clear_color(BG)
	var painting := Painting.new()
	add_child(painting)
	painting.batch.show()
	var slots := []
	for map in [painting._hero_cells, painting._immortal_hero_cells]:
		slots.append_array(map.values())
	var viewport_size := get_viewport_rect().size
	var rows := ceili(float(slots.size()) / COLUMNS)
	var cell := viewport_size / Vector2(COLUMNS, rows)
	var h := minf(cell.x, cell.y) * 0.87
	var verified := 0
	var args := OS.get_cmdline_user_args()
	for pose in 4:
		var keys := PackedInt64Array()
		var figures := PackedFloat32Array()
		for i in slots.size():
			var idx: int = slots[i]
			var p := (Vector2(i % COLUMNS + 0.5, i / COLUMNS + 0.91)) * cell
			var style := 12.0 if idx >= painting.IMMORTAL_HERO_OFFSET else 13.0
			figures.append_array(PackedFloat32Array([p.x, p.y, h, painting.HERO_CELL + idx + pose,
				1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.35 if i % 2 == 0 else 0.0, style]))
			keys.append(i)
		painting.batch.update_packed(figures, keys, painting.FIG_W, Color.WHITE, Color.WHITE)
		await RenderingServer.frame_post_draw
		var image := get_viewport().get_texture().get_image()
		var image_cell := Vector2(image.get_size()) / Vector2(COLUMNS, rows)
		for i in slots.size():
			var origin := Vector2(i % COLUMNS, i / COLUMNS) * image_cell
			var changed := 0
			for y in range(int(origin.y + image_cell.y * 0.22), int(origin.y + image_cell.y * 0.83), 2):
				for x in range(int(origin.x + image_cell.x * 0.08), int(origin.x + image_cell.x * 0.92), 2):
					var c := image.get_pixel(x, y)
					changed += int(absf(c.r - BG.r) + absf(c.g - BG.g) + absf(c.b - BG.b) > 0.12)
			if changed >= 15:
				verified += 1
			else:
				printerr("Missing hero render: cell=", slots[i], " pose=", pose, " ink=", changed)
		if not args.is_empty():
			image.save_png(args[0].path_join("hero_atlas_pose_%d.png" % pose))
	print("HERO_ATLAS_GPU|%d/%d" % [verified, slots.size() * 4])
	get_tree().quit(0 if verified == 212 and slots.size() == 53 else 1)
