extends Node
## 특기 수치 전수 덤프 (11/13) —— 플레이어 카드마다 특기 이름 · 레벨 · 화면 수치(mt) · 실제 값 m, 위세 문구.
## 실행: godot --headless --path . res://tests/trait_values.tscn -- --out=D:/x.json   (분석: tools/scripts/trait_value_audit.py)

func _ready() -> void:
	var args := {}
	for s in OS.get_cmdline_user_args():
		var kv := s.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	var out := []
	for k in DB.C.keys():
		if DB.is_foe(k):
			continue
		var c: Dictionary = DB.C[k]
		var ps = DB.passives_of(k)
		var raw := {}
		if ps != null:
			for t in ps.traits:
				raw[t.name] = t.m
			for g in ps.groups:
				var gm := {}
				for key in DB.PSV.traits[g.name].m:
					gm[key] = DB.PSV.traits[g.name].m[key] * (1.0 if key in DB.PSV.flags else g.scale)
				raw["G:" + g.name] = gm
		var tl := []
		for t in DB.trait_list(k):
			tl.append({"name": t.name, "lv": t.lv, "group": t.group, "unique": t.unique, "attr": t.attr, "mt": t.mt})
		out.append({"id": k, "person": DB.person(k), "name": c.name, "tier": c.tier, "kiin": DB.is_kiin(k), "traits": tl, "raw": raw,
			"aura": DB.aura_text(k)})
	var f := FileAccess.open(args.get("out", "user://trait_values.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(out, " "))
	f.close()
	print("cards ", out.size())
	get_tree().quit()
