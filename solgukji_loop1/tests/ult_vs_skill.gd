extends Node
## 고유기 대 일반 기술 —— 카드마다 고유기 한 방(가장 큰 타격 배율 × 그 등급 전투의 turn_mul —— 고유기 피해에 곱해진다)이 일반 기술 한 방보다 센지. 실행: godot --headless --path . res://tests/ult_vs_skill.tscn
func _ready() -> void:
	var bad := []
	var n := 0
	var ratio := []
	for k in DB.C:
		if DB.is_foe(k) or DB.C[k].tier < 6:
			continue
		var u = DB.ult_of(k)
		if u == null:
			continue
		var um := 0.0
		for comp in u.eff:
			if comp.get("t") == "hit":
				um = maxf(um, float(comp.get("mult", 0.0)) * Battle.turn_mul_for(DB.C[k].tier))
		var sm := 0.0
		for sk in DB.C[k].get("sks", []):
			sm = maxf(sm, float(sk.eff.get("mult", 0.0)))
		if um <= 0 or sm <= 0:
			continue
		n += 1
		ratio.append(um / sm)
		if um <= sm:
			bad.append("%s(%d) 고유기 %d%% ≤ 기술 %d%%" % [DB.C[k].name, DB.C[k].tier, roundi(um * 100), roundi(sm * 100)])
	ratio.sort()
	print("비교 %d장 · 고유기가 약하거나 같은 카드 %d장 · 비율 최소 %.2f 중앙 %.2f" % [n, bad.size(), ratio[0], ratio[ratio.size() / 2]])
	for b in bad.slice(0, 12):
		print("  ", b)
	get_tree().quit()
