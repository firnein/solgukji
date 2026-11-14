class_name TouchButton
extends Button
## 누르는 범위만 넓힌 버튼 (11/14 UI 감사 #6) —— 보이는 크기는 그대로, 손가락이 닿는 범위는 최소 UI.HIT(48 논리).
## 모자란 만큼 위아래(옆) 바깥으로 늘린다. 형제 버튼과 겹치면 나중에 그려지는(위에 있는) 쪽이 이긴다 —— 붙어 있는 줄에서는 hit_dir 로 한쪽만.

var hit := Vector2(UI.HIT, UI.HIT)
var hit_dir := 0      # 0 위아래 고르게 · -1 위로만 · 1 아래로만


func _has_point(p: Vector2) -> bool:
	var gx := maxf(0.0, hit.x - size.x) * 0.5
	var gy := maxf(0.0, hit.y - size.y)
	var top := gy * 0.5 if hit_dir == 0 else (gy if hit_dir < 0 else 0.0)
	return Rect2(Vector2.ZERO, size).grow_individual(gx, top, gx, gy - top).has_point(p)
