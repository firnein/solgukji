extends Control
## 썸네일 점검 —— 실행: godot --path . res://tests/faces.tscn [-- --shot=경로.png --kind=face|card|ult --from=0]
## 인물마다 한 칸씩 그려 찍는다 (화면이 있어야 한다 —— --headless 로는 그림이 안 나온다).

var keys := []
var kind := "face"


func _ready() -> void:
	var args := {}
	for s in OS.get_cmdline_user_args():
		var kv := s.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	kind = str(args.get("kind", "face"))
	var seen := {}
	for k in DB.C:
		if DB.C[k].tier >= 3 and not seen.has(DB.person(k)):
			seen[DB.person(k)] = true
			keys.append(k)
	keys = keys.slice(int(args.get("from", "0")), int(args.get("from", "0")) + 48)
	get_window().size = Vector2i(8 * 92 + 8, 6 * 112 + 8)
	set_anchors_preset(Control.PRESET_FULL_RECT)
	queue_redraw()
	if args.has("shot"):
		for i in 4:
			await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png(args.shot)
		get_tree().quit()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), DB.PAL.ink)
	for i in keys.size():
		var p := Vector2(8 + (i % 8) * 92, 8 + (i / 8) * 112)
		var r := Rect2(p, Vector2(84, 84))
		Art.draw_portrait(self, r, keys[i], 0.0, kind)
		draw_rect(r, DB.tier_color(keys[i]), false, 1.0)
		draw_string(DB.font_body, p + Vector2(0, 100), DB.person(keys[i]), HORIZONTAL_ALIGNMENT_CENTER, 84, 12, DB.PAL.paper)
