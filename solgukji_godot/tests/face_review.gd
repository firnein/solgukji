extends Control
## 등급 얼굴 메달 점검 (11/15) —— 등급 그림을 쓰는 카드마다 [카드 그림 | 얼굴 메달] 을 나란히 찍는다 (화면이 있어야 한다)
##   godot --path . res://tests/face_review.tscn --position 495,1500 -- --out=폴더 [--dump=1]
## --dump=1 이면 그림 없이 「카드 키 · 등급 · 쓰는 그림」 목록만 찍는다 (tools/scripts/tier_faces.py 가 어떤 그림의 얼굴을 만들지 볼 때)

const CW := 150.0
const CH := 150.0
const COLS := 8
var _groups := {}      # 접미사 -> [카드 키]


func _ready() -> void:
	var args := {}
	for s in OS.get_cmdline_user_args():
		var kv := s.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	var seen := {}
	for k in DB.C:
		var c: Dictionary = DB.C[k]
		if c.tier <= 2 or DB.is_foe(k):
			continue
		var base := DB.portrait_base(k).get_file()
		if not base.contains("_") or seen.has(base):
			continue
		seen[base] = true
		var suf := base.get_slice("_", 1)
		if not _groups.has(suf):
			_groups[suf] = []
		_groups[suf].append(k)
		if args.has("dump"):
			print("FACE\t%s\t%d\t%s" % [k, c.tier, base])
	if args.has("dump"):
		get_tree().quit()
		return
	var out := str(args.get("out", "user://"))
	for suf in _groups:
		var keys: Array = _groups[suf]
		keys.sort_custom(func(a, b): return DB.person(a) < DB.person(b))
		var vp := SubViewport.new()      # 창 크기 · 늘이기 설정과 관계없이 제 크기로 찍는다
		vp.size = Vector2i(int(COLS * CW), int(((keys.size() + COLS - 1) / COLS) * CH))
		vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		add_child(vp)
		var sheet := Sheet.new()
		sheet.keys = keys
		sheet.size = Vector2(vp.size)
		vp.add_child(sheet)
		for i in 4:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		vp.get_texture().get_image().save_png("%s/face_review_%s.png" % [out, suf])
		print("저장 ", suf, " ", keys.size())
		vp.queue_free()
	get_tree().quit()


class Sheet extends Control:
	var keys: Array = []

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), DB.PAL.ink)
		for i in keys.size():
			var k: String = keys[i]
			var o := Vector2((i % COLS) * CW, (i / COLS) * CH)
			Art.draw_portrait(self, Rect2(o + Vector2(4, 4), Vector2(66, 122)), k, 0.0, "card")
			Art.draw_face_circle(self, o + Vector2(110, 44), 36.0, k)
			Art.draw_face_circle(self, o + Vector2(110, 104), 16.0, k)
			draw_string(DB.font_bold, o + Vector2(4, 144), DB.person(k), HORIZONTAL_ALIGNMENT_LEFT, CW - 8, 15, Color.WHITE)
