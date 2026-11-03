extends Node
## 카드 전체 표 —— 실행: godot --headless --path . res://tests/dump_cards.tscn -- --out=D:/Sol/x.tsv
## 플레이어가 얻는 카드만: 등급 · 병종 · 이름 · 능력치 · 조합 재료 · 기술 · 고유기 · 위세 · 특기

func _ready() -> void:
	var args := {}
	for s in OS.get_cmdline_user_args():
		var kv := s.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	var ids: Array = DB.C.keys().filter(func(k): return not DB.is_foe(k))
	ids.sort_custom(func(a, b):
		if DB.C[a].tier != DB.C[b].tier: return DB.C[a].tier < DB.C[b].tier
		if DB.C[a].tag != DB.C[b].tag: return DB.C[a].tag < DB.C[b].tag
		return a < b)
	var rows := ["id\t등급\t병종\t세력\t이름\t공\t방\t책\t책방\t속\t병력\tpv\t재료\t기술\t고유기\t위세\t특기"]
	for k in ids:
		var c: Dictionary = DB.C[k]
		var rec: Array = DB.RECOF.get(k, [])
		var mats := []
		for m in rec:
			var s := str(m)
			if DB.C.has(s):
				mats.append(DB.C[s].name + "(" + str(DB.C[s].tier) + ")")
			elif DB.IT.has(s):
				mats.append("[" + DB.IT[s].name + "]")
			else:
				mats.append(s)
		var sks := []
		for sk in c.get("sks", []):
			sks.append("%s{%s,c%.1f}" % [sk.n, sk.cond, sk.cost])
		var u = DB.ult_of(k) if c.tier >= 6 else null
		var tr := []
		for t in DB.trait_list(k):
			tr.append("%s%d%s%s" % [t.name, t.lv, "G" if t.group else "", "*" if t.unique else ""])
		rows.append("\t".join([k, DB.TIER[c.tier].n, c.tag, c.fac, c.name, c.atk, c.def, c["int"], c.res, c.spd, c.tr, c.pv,
			" + ".join(mats), " / ".join(sks), (u.name if u != null else ""), DB.aura_text(k), ", ".join(tr)]))
	var f := FileAccess.open(args.get("out", "D:/Sol/cards_dump.tsv"), FileAccess.WRITE)
	f.store_string("\n".join(rows))
	f.close()
	print("rows ", rows.size() - 1)
	get_tree().quit()
