extends Node
func _desc(k) -> String:
	if DB.C.has(k):
		return "%s(%s t%d%s)" % [k, DB.C[k].name, DB.C[k].tier, " kiin" if DB.is_kiin(k) else ""]
	return str(k)
func _ready() -> void:
	var out := []
	for k in DB.RECOF:
		if int(DB.C[k].tier) >= 8:
			out.append("%s %s t%d foe=%s mats=%s need=%s" % [k, DB.C[k].name, DB.C[k].tier, DB.is_foe(k), str(DB.RECOF[k].map(func(m): return _desc(m))), str(Run.need_item(k))])
	out.sort()
	print("\n".join(out))
	print("--- ladder keys sample: ", DB.D.keys())
	get_tree().quit()
