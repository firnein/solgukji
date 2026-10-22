extends Node
## 밀도 점검 —— 한 전투의 병사 수, 부대 하나가 차지하는 넓이, 전장에서 병사가 덮는 비율을 잰다.
## 실행: godot --headless --path . res://tests/density.tscn

func _ready() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	for lv in [[300, "중반"], [900, "후반"]]:
		var a := DB.gen_board(lv[0], "균형", rng)
		var b := DB.gen_board(lv[0], "물리", rng)
		var res := Battle.new(1).run(DB.auto_place(a.cards, a.form), a.form, 100, null,
			DB.auto_place(b.cards, b.form), b.form, 100, null)
		var w := War3D.new()
		add_child(w)
		w.setup(res)
		var n := 0
		var unit_area := 0.0
		var minp := Vector2(1e9, 1e9)
		var maxp := Vector2(-1e9, -1e9)
		for sq in w.order:
			n += sq.soldiers.size()
			var wid: float = mini(sq.cols, sq.soldiers.size()) * sq.sp * War3D.S
			var dep: float = sq.ranks() * sq.sp * War3D.S
			unit_area += wid * dep
			minp = Vector2(minf(minp.x, sq.home.x), minf(minp.y, sq.home.y))
			maxp = Vector2(maxf(maxp.x, sq.home.x), maxf(maxp.y, sq.home.y))
		var span := (maxp - minp) * War3D.S + Vector2(8, 8)
		print("%s: 부대 %d · 병사 %d명 (부대당 %.0f) · 병사 간격 보병 %.2fm · 부대가 덮는 땅 %.0f㎡ / 진영 전체 %.0f㎡ (%.0f%%)" % [
			lv[1], w.order.size(), n, float(n) / w.order.size(), 6.2 * War3D.S,
			unit_area, span.x * span.y, unit_area / (span.x * span.y) * 100])
		w.queue_free()
	get_tree().quit()
