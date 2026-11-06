class_name AutoGrid
extends Container
## 폭에 맞춰 칸 수를 정하는 격자 —— 칸 하나가 min_w 보다 좁아지지 않는 만큼 칸을 놓고,
## 남는 폭은 칸들이 나눠 가진다 (휴대폰 세로 400 폭이면 카드 두 칸, PC 창을 넓히면 더 많이).
## 한 줄 높이는 그 줄에서 가장 큰 자식의 최소 높이.

var min_w := 168.0
var sep := 8
var max_cols := 0          # 0 이면 제한 없음
var center_last := false   # 11/7 덜 찬 마지막 줄을 가운데로 (전투 아래 장수 카드 5 + 4)


func cols_for(w: float) -> int:
	var n := maxi(1, int(floor((w + sep) / (min_w + sep))))
	if max_cols > 0:
		n = mini(n, max_cols)
	return n


func _kids() -> Array:
	var out := []
	for c in get_children():
		if c is Control and c.visible and not c.top_level:
			out.append(c)
	return out


func _get_minimum_size() -> Vector2:
	var kids := _kids()
	if kids.is_empty():
		return Vector2.ZERO
	var n := cols_for(size.x if size.x > 0 else min_w)
	var h := 0.0
	var i := 0
	while i < kids.size():
		var rh := 0.0
		for j in range(i, mini(i + n, kids.size())):
			rh = maxf(rh, kids[j].get_combined_minimum_size().y)
		h += rh + (sep if i > 0 else 0)
		i += n
	return Vector2(min_w, h)


func _notification(what: int) -> void:
	if what == NOTIFICATION_SORT_CHILDREN:
		var kids := _kids()
		var n := cols_for(size.x)
		var cw := (size.x - sep * (n - 1)) / n
		var y := 0.0
		var i := 0
		while i < kids.size():
			var rh := 0.0
			for j in range(i, mini(i + n, kids.size())):
				rh = maxf(rh, kids[j].get_combined_minimum_size().y)
			var in_row := mini(i + n, kids.size()) - i
			var x0 := (n - in_row) * (cw + sep) / 2.0 if center_last else 0.0
			for j in range(i, mini(i + n, kids.size())):
				fit_child_in_rect(kids[j], Rect2(x0 + (j - i) * (cw + sep), y, cw, rh))
			y += rh + sep
			i += n
	elif what == NOTIFICATION_RESIZED:
		update_minimum_size()
