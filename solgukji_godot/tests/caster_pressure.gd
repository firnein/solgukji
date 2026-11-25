extends Node

const SYN := {"tag": {}, "troop": 1.0, "morale": 0.0, "atk": 1.0, "spd": 1.0, "caps": {}}
const FRONT := {"row": 0, "col": 2, "line": "선봉", "side": "중앙"}

func _sample(cid: String, pressured: bool) -> Dictionary:
	var b := RtBattle.new(1125)
	var a := b.mk_unit(cid, FRONT, "A", 100, 0, null, SYN)
	var d := b.mk_unit("c177", FRONT, "B", 100, 0, null, SYN)
	a.pos = Vector2.ZERO
	d.pos = Vector2(380, 0)
	b.units.assign([a, d])
	if pressured:
		var blocker := b.mk_unit("c177", FRONT, "B", 100, 1, null, SYN)
		blocker.pos = Vector2(0, a.hw + blocker.hw)
		b.units.append(blocker)
	b.int_hit(a, d, 1.0, 1)
	var damage := d.max - d.troops
	if pressured:
		return {"damage": damage}
	b._tm = 10.0
	b._interrupt_ult(a)
	b._ult_by = a
	return {"damage": damage, "wind": float(b._wind.get(a, b._tm)) - b._tm,
		"cap": b._ult_clamp(d, d.max) / d.max}

func _ready() -> void:
	var ok := true
	var count := 0
	for tier in [7, 8]:
		for cid in DB.by_tier(tier):
			var ult = DB.ult_of(cid)
			if ult == null:
				continue
			var raw: Dictionary = DB.ULT.list[DB.person(cid)]
			var wind := float(raw.get("wind", DB.ULT.get("wind", 2.5)))
			var caster := Battle.is_caster(DB.C[cid])
			ok = ok and is_equal_approx(float(ult.wind), wind + (0.45 if caster else 0.0))
			ok = ok and is_equal_approx(float(ult.get("cap_bonus", 0.0)), 0.07 if caster else 0.0)
			if not caster:
				continue
			var sample := _sample(cid, false)
			var free := float(sample.damage)
			var pinned := float(_sample(cid, true).damage)
			ok = ok and free > pinned and pinned > 0.0
			ok = ok and is_equal_approx(float(sample.wind), float(ult.wind))
			ok = ok and is_equal_approx(float(sample.cap), 0.32 if tier == 7 else 0.37)
			if not (free > pinned and pinned > 0.0):
				printerr("Invalid caster pressure: ", cid, " ", free, " / ", pinned)
			count += 1
			print("CASTER|%d|%s|%s|free=%.0f|pinned=%.0f|wind=%.2f" % [tier, cid, DB.C[cid].tag, free, pinned, ult.wind])
	print("CASTER_PRESSURE|%s|%d" % ["PASS" if ok else "FAIL", count])
	get_tree().quit(0 if ok and count > 0 else 1)
