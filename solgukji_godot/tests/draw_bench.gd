extends Node
## 타일 그리기 값 재기 (11/15 퍼포먼스 최적화) —— 창이 있어야 한다:
##   godot --path . --resolution 720x1280 res://tests/draw_bench.tscn
## 카드 타일(MiniTile · CardTile) 200장을 다시 그리게 해 한 장에 드는 시간(µs)을 재고, 타일이 쓰는 그리기 조각(둥근 상자 · 원 · 글자 · 초상)을
## 따로 200번씩 그려 어느 조각이 비싼지 본다. 결과는 "BENCH|" 줄로

const N := 200
const TN := 30      # 타일은 화면에 다 들어오는 만큼만 (화면 밖 타일은 그리지 않는다)


class Piece extends Control:
	var kind := ""
	var k := ""
	static var sb: StyleBoxFlat = null

	func _draw() -> void:
		var fb: Font = DB.font_body
		for i in N:
			var p := Vector2(4 + (i % 10) * 40, 4 + (i / 10) * 40)
			match kind:
				"상자(새로 만들기)":
					var s := StyleBoxFlat.new()
					s.bg_color = DB.PAL.ink2
					s.border_color = DB.PAL.gold
					s.set_border_width_all(1)
					s.border_width_top = 3
					s.set_corner_radius_all(8)
					draw_style_box(s, Rect2(p, Vector2(36, 36)))
				"상자(하나를 고쳐 쓰기)":
					if sb == null:
						sb = StyleBoxFlat.new()
						sb.set_border_width_all(1)
						sb.border_width_top = 3
						sb.set_corner_radius_all(8)
					sb.bg_color = DB.PAL.ink2
					sb.border_color = DB.PAL.gold
					draw_style_box(sb, Rect2(p, Vector2(36, 36)))
				"네모 둘":
					draw_rect(Rect2(p, Vector2(36, 36)), DB.PAL.gold)
					draw_rect(Rect2(p + Vector2(1, 3), Vector2(34, 32)), DB.PAL.ink2)
				"원":
					draw_circle(p + Vector2(18, 18), 8, DB.PAL.gold)
				"글자":
					draw_string(fb, p + Vector2(0, 14), "장수 이름", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color.WHITE)
				"글자 폭 재기":
					fb.get_string_size("장수 이름", HORIZONTAL_ALIGNMENT_LEFT, -1, 12 - i % 3)
				"초상":
					Art.draw_portrait(self, Rect2(p, Vector2(36, 36)), k)
				"특기 목록":
					DB.trait_list(k)


func _ready() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	var ks: Array = DB.D.RECDEF.map(func(r): return r[0])
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	await _frames(5)
	for kind in ["mini", "mini(재료 표시)", "card"]:
		var g := UI.grid(66 if kind != "card" else 160, 6)
		g.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		root.add_child(g)
		var tiles := []
		for i in TN:
			var k: String = ks[i % ks.size()]
			var t: Control
			if kind == "card":
				t = CardTile.new().setup(k, 2)
			else:
				var m := MiniTile.new().setup(k, 2 if kind != "mini" else -1)
				if kind != "mini":
					m.badge = "-2"
					m.badge_col = Color(DB.PAL.seal, 0.9)
					m.up = true
				t = m
			g.add_child(t)
			tiles.append(t)
		await _frames(6)
		var best := 1e9
		for rep in 6:
			for t in tiles:
				t.queue_redraw()
			var t0 := Time.get_ticks_usec()
			await get_tree().process_frame      # 이 프레임 끝의 그리기 예약 처리(= _draw 스크립트)까지
			await RenderingServer.frame_pre_draw
			best = minf(best, float(Time.get_ticks_usec() - t0))
			await _frames(2)
		print("BENCH|타일 %s|한 장 %.0fµs" % [kind, best / TN])
		g.queue_free()
		await _frames(3)
	for kind in ["상자(새로 만들기)", "상자(하나를 고쳐 쓰기)", "네모 둘", "원", "글자", "글자 폭 재기", "초상", "특기 목록"]:
		var p := Piece.new()
		p.kind = kind
		p.k = ks[0]
		p.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		root.add_child(p)
		await _frames(4)
		var best := 1e9
		for rep in 6:
			p.queue_redraw()
			var t0 := Time.get_ticks_usec()
			await get_tree().process_frame
			await RenderingServer.frame_pre_draw
			best = minf(best, float(Time.get_ticks_usec() - t0))
			await _frames(2)
		print("BENCH|조각 %s|한 번 %.1fµs" % [kind, best / N])
		p.queue_free()
		await _frames(2)
	get_tree().quit()


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame
