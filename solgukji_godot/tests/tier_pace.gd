extends Node
## 11/19 등급별 전투가 왜 빨리/늦게 끝나나 —— 카드 능력치 평균 · 턴 배율 · 피해 구성(고유기 · 기술 · 나머지) · 판 길이
## 실행: godot --headless --path . res://tests/tier_pace.tscn [-- --n=20 --tiers=6,7,8]

func _ready() -> void:
	var args := {}
	for arg in OS.get_cmdline_user_args():
		var kv := arg.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	var n := int(args.get("n", "20"))
	Battle.atk_up = float(args.get("atk", str(Battle.atk_up)))
	Battle.collapse_hold_mul = float(args.get("hold", str(Battle.collapse_hold_mul)))
	Battle.decisive_full_mul = float(args.get("dec", str(Battle.decisive_full_mul)))
	for tier in Array(str(args.get("tiers", "6,7,8")).split(",")).map(func(x): return int(x)):
		var pool := DB.by_tier(tier).filter(func(k): return not DB.is_foe(k))
		var st := {"troops": 0.0, "atk": 0.0, "def": 0.0, "int": 0.0, "spd": 0.0}
		var tags := {}
		for k in pool:
			for s in st:
				st[s] += float(DB.C[k].get(s, 0.0))
			tags[DB.C[k].tag] = int(tags.get(DB.C[k].tag, 0)) + 1
		for s in st:
			st[s] = snappedf(st[s] / pool.size(), 0.1)
		var len_sum := 0.0
		var dmg := 0.0
		var ult := 0.0
		var sk := 0.0
		var hp := 0.0
		var ult_n := 0
		var heal := 0.0
		var lens := []
		var routs := [0, 0]   # 패주한 부대 · 그중 병력 50% 이상 남긴 채
		var by_tag := {}      # 병종 -> [부대 수, 준 피해, 병력 합]
		for i in n:
			var rng := RandomNumberGenerator.new()
			rng.seed = 77100 + i
			var a := _mix(pool, rng) if args.has("mix") else _pick(pool, rng)
			var b := _mix(pool, rng) if args.has("mix") else _pick(pool, rng)
			var bt := RtBattle.new(77100 + i)
			var r: Dictionary = bt.run(DB.auto_place(a, "eorin"), "eorin", 100, null, DB.auto_place(b, "hagik"), "hagik", 100, null, "", "", [], {"A": "smart", "B": "smart"})
			len_sum += float(r.len)
			lens.append(float(r.len))
			dmg += float(r.stats.dmg)
			ult += float(r.stats.ult_dmg)
			sk += float(r.stats.get("sk_dmg", 0.0))
			for u in bt.units:
				hp += u.max
				if not u.alive and u.troops > 0.0:
					routs[0] += 1
					if u.troops >= u.max * 0.5: routs[1] += 1
				var bt_: Array = by_tag.get(u.c.tag, [0, 0.0, 0.0])
				bt_[0] += 1
				heal += u.htr
				bt_[1] += u.dmg
				bt_[2] += u.max
				by_tag[u.c.tag] = bt_
			for e in r.ev:
				if e.get("fx") == "ult":
					ult_n += 1
		print("등급 %d · 턴 배율 %.2f · 카드 %d장 평균 %s · 병종 %s" % [tier, Battle.turn_mul_for(tier), pool.size(), st, tags])
		print("   판 %.1f초 · 총 병력 %d · 받은 피해 %d (초당 %.0f = 총 병력의 %.1f%%/초) · 고유기 %d%% (%.1f번) · 기술 %d%% · 나머지 %d%%" % [len_sum / n, hp / n, dmg / n, dmg / len_sum, 100.0 * dmg / len_sum / (hp / n), 100.0 * ult / dmg, float(ult_n) / n, 100.0 * sk / dmg, 100.0 * (dmg - ult - sk) / dmg])
		lens.sort()
		print("   판 길이 최대 %.0f초 · 90%% %.0f초 · 60초 넘은 판 %d/%d" % [lens[-1], lens[int(lens.size() * 0.9)], lens.filter(func(x): return x >= 60.0).size(), n])
		print("   패주 %d부대 중 병력 절반 이상 남은 채 %d (판당 %.2f)" % [routs[0], routs[1], float(routs[1]) / n])
		print("   치료 %d (받은 피해의 %d%%) · 치료 카드 유생 비율 %.0f%%" % [heal / n, 100.0 * heal / dmg, 100.0 * float(by_tag.get("유생", [0])[0]) / (18.0 * n)])
		var line := "   병종별 (부대 수 · 피해 몫 · 부대당 초당 피해 ÷ 평균 병력 %): "
		for tg in by_tag:
			var v: Array = by_tag[tg]
			line += "%s %d · %d%% · %.2f  " % [tg, v[0], 100.0 * v[1] / dmg, 100.0 * v[1] / v[0] / (len_sum / n * n) / (hp / n / 18.0) * n / n]
		print(line)
	get_tree().quit()

func _pick(pool: Array, rng: RandomNumberGenerator) -> Array:
	var out := []
	var people := []
	var cand := pool.duplicate()
	while out.size() < 9 and not cand.is_empty():
		var k: String = cand.pop_at(rng.randi_range(0, cand.size() - 1))
		if not people.has(DB.person(k)):
			out.append(k)
			people.append(DB.person(k))
	return out


## 병종 구성을 등급마다 같게 —— 창2 기1 궁2 도1 책1 유1 모1 (그 병종 카드가 없으면 남은 카드에서)
func _mix(pool: Array, rng: RandomNumberGenerator) -> Array:
	var out := []
	var people := []
	for tg in ["창병", "창병", "기병", "궁병", "궁병", "도적", "책사", "유생", "모사"]:
		var c := pool.filter(func(k): return DB.C[k].tag == tg and not people.has(DB.person(k)))
		if c.is_empty():
			c = pool.filter(func(k): return not people.has(DB.person(k)))
		var k: String = c[rng.randi_range(0, c.size() - 1)]
		out.append(k)
		people.append(DB.person(k))
	return out
