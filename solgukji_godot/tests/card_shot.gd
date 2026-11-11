extends Control
## CardView 점검 —— 실행: godot --path . res://tests/card_shot.tscn --position 495,1500 -- --shot=경로.png [--w=112 --h=160 --kind=kiin|all]
## 기인(또는 모든 고등급) 카드를 CardView 로 한 줄씩 찍는다 (화면이 있어야 한다)

func _ready() -> void:
	var args := {}
	for s in OS.get_cmdline_user_args():
		var kv := s.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	var w := float(args.get("w", "112"))
	var h := float(args.get("h", "160"))
	var keys := []
	for k in DB.C:
		if DB.is_kiin(k):
			keys.append(k)
	if args.has("who"):
		keys = []
		for k in DB.C:
			if DB.is_kiin(k) and str(args.who).split(",").has(DB.person(k)):
				keys.append(k)
	keys = keys.slice(0, 12)
	var cols := mini(6, keys.size())
	var rows := (keys.size() + 5) / 6
	get_window().size = Vector2i(int(cols * (w + 8) + 8), int(rows * (h + 8) + 8))
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = DB.PAL.ink
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	for i in keys.size():
		var cv := CardView.new().setup(keys[i], Vector2(w, h))
		cv.position = Vector2(8 + (i % 6) * (w + 8), 8 + (i / 6) * (h + 8))
		add_child(cv)
	if args.has("shot"):
		for i in 6:
			await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png(args.shot)
		get_tree().quit()
