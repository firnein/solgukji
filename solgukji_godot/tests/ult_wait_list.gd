extends Node
## 고유기 대기 시간 표 —— 실행: godot --headless --path . res://tests/ult_wait_list.tscn
func _ready() -> void:
	var rows := []
	for k in DB.C:
		if DB.is_foe(k) or not (DB.C[k].tier >= 6 or DB.is_kiin(k)):
			continue
		var u = DB.ult_of(k)
		if u == null: continue
		rows.append([u.wait, DB.C[k].name, u.name, DB.ult_score(u)])
	rows.sort()
	for r in rows:
		print("%4.1f초  %s 『%s』 점수 %.1f" % r)
	get_tree().quit()
