extends Node
## 11/23 기술 발동 조건별 실제 발동 —— 실제 덱 모양(토벌형 · 대회형 · 불멸 · 전설 후반, 인연 맞춤) 60판에서 기술 하나가 한 판에 몇 번 터지나 · 한 번도 안 터진 비율 · 모사 사기 깎기.
## 실행: godot --headless --path . res://tests/skill_fire.tscn [-- --old (예전 기술 고르기)]
const SHAPES := [[8, 7, 7, 7, 6, 5, 5, 5, 5], [8, 7, 7, 7, 7, 7, 6, 5, 5], [7, 7, 6, 6, 6, 5, 5, 5, 5], [6, 6, 5, 5, 5, 5, 4, 4, 4]]
func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a == "--old": Battle.sk_rotate = false
		if a == "--shared": Battle.sk_split = false
	var myths: Array = DB.by_tier(8).filter(func(k): return not DB.is_foe(k) and not DB.is_kiin(k))
	var have := {}
	var fired := {}
	var zero := {}
	var lens := 0.0
	var msk := 0
	var mdm := 0.0
	var mun := 0
	var tot_sk := 0
	var dead_sk := 0
	var all_sk := 0
	var n := 60
	for i in n:
		var rng := RandomNumberGenerator.new()
		rng.seed = 81000 + i
		var sh: Array = SHAPES[i % SHAPES.size()]
		var a := _deck(sh, myths, rng)
		var b := _deck(sh, myths, rng)
		var bt := RtBattle.new(81000 + i)
		var r: Dictionary = bt.run(DB.auto_place(a, "eorin"), "eorin", 100, null, DB.auto_place(b, "eorin"), "eorin", 100, null, "", "", [], {"A": "smart", "B": "smart"})
		lens += float(r.len)
		var cnt := {}
		for e in r.ev:
			if e.get("fx") == "skill":
				var kk: String = str(e.a) + "|" + str(e.name)
				cnt[kk] = int(cnt.get(kk, 0)) + 1
				tot_sk += 1
		for u in bt.units:
			if u.c.tag == "모사":
				mun += 1
				mdm += u.mdmg
				for kk in cnt:
					if kk.begins_with(u.key + "|"): msk += int(cnt[kk])
			for sk in u.c.get("sks", []):
				var c := str(sk.get("cond", "always")).split("|")[0].split(":")[0]
				var f := int(cnt.get(u.key + "|" + str(sk.n), 0))
				have[c] = int(have.get(c, 0)) + 1
				fired[c] = int(fired.get(c, 0)) + f
				all_sk += 1
				if f == 0:
					zero[c] = int(zero.get(c, 0)) + 1
					dead_sk += 1
	print("판 평균 %.1f초 · 기술 발동 판당 %.1f번 · 한 번도 안 터진 기술 %d%%" % [lens / n, float(tot_sk) / n, 100 * dead_sk / all_sk])
	print("모사 부대 한 판 기술 %.2f번 · 사기 깎기 %.1f" % [float(msk) / mun, mdm / mun])
	var ks := have.keys()
	ks.sort()
	for c in ks:
		print("%-12s 기술 %4d개 · 한 판 평균 %.2f번 · 한 번도 안 터짐 %d%%" % [c, have[c], float(fired[c]) / have[c], 100 * int(zero.get(c, 0)) / have[c]])
	get_tree().quit()

func _deck(shape: Array, myths: Array, rng: RandomNumberGenerator) -> Array:
	var tags: Array = DB._mix_tags("균형", rng)
	var out := []
	if int(shape[0]) == 8:
		var m: String = myths[rng.randi_range(0, myths.size() - 1)]
		out.append(m)
		tags.erase(DB.C[m].tag)
	for j in range(out.size(), shape.size()):
		out.append(DB._army_pick(int(shape[j]), str(tags[j - (1 if int(shape[0]) == 8 else 0)]) if j < tags.size() + 1 else "", out, rng.randi(), "균형"))
	return out
