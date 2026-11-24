extends Node
## 11/24 사용자: 「고급과 희귀가 전투에서 역할이 있는지」 —— 실제 덱 모양(sec_pace 와 같음)에서 등급별 병력 · 피해 · 받은 피해 · 생존 몫,
## 그리고 A 쪽 고급 · 희귀(3 · 4등급)를 빼고 싸웠을 때 승률 (빼기 전 50% 근처와 비교)
## 실행: godot --headless --path . res://tests/tier_role.tscn [-- --n=40]
const SHAPES := {"초반": [4, 4, 3, 3, 3, 3, 3, 3, 3], "중반": [5, 5, 5, 4, 4, 4, 4, 3, 3]}
const TN := {1: "기본", 2: "일반", 3: "고급", 4: "희귀", 5: "전설", 6: "초월", 7: "불멸", 8: "신화"}
func _ready() -> void:
	var n := 40
	for x in OS.get_cmdline_user_args():
		if x.begins_with("--n="): n = int(x.substr(4))
	for nm in SHAPES:
		var sh: Array = SHAPES[nm]
		var agg := {}
		var w_base := 0.0
		var w_drop := 0.0
		for i in n:
			var rng := RandomNumberGenerator.new(); rng.seed = 77000 + i
			var a := _deck(sh, rng); var b := _deck(sh, rng)
			var r: Dictionary = RtBattle.new(77000 + i).run(DB.auto_place(a, "eorin"), "eorin", 100, null, DB.auto_place(b, "eorin"), "eorin", 100, null, "", "", [], {"A": "smart", "B": "smart"})
			w_base += 1.0 if r.win else (0.5 if r.draw else 0.0)
			for u in r.roster:
				var t := int(u.tier)
				if not agg.has(t): agg[t] = {"n": 0, "max": 0.0, "dmg": 0.0, "taken": 0.0, "alive": 0, "heal": 0.0}
				var g: Dictionary = agg[t]
				g.n += 1; g.max += float(u.max); g.dmg += float(u.dmg); g.taken += float(u.taken); g.heal += float(u.heal)
				if u.alive: g.alive += 1
			var drop_t: Array = [3] if nm == "중반" else [3, 4]
			var a2 := a.filter(func(k): return not (int(DB.C[k].tier) in drop_t))
			var r2: Dictionary = RtBattle.new(77000 + i).run(DB.auto_place(a2, "eorin"), "eorin", 100, null, DB.auto_place(b, "eorin"), "eorin", 100, null, "", "", [], {"A": "smart", "B": "smart"})
			w_drop += 1.0 if r2.win else (0.5 if r2.draw else 0.0)
		var tot := {"max": 0.0, "dmg": 0.0, "taken": 0.0}
		for t in agg:
			for k in tot: tot[k] += agg[t][k]
		print("== %s (%d판) —— A 승률 그대로 %.0f%% · A 의 고급(중반) · 고급+희귀(초반)를 빼면 %.0f%%" % [nm, n, w_base / n * 100.0, w_drop / n * 100.0])
		var ks := agg.keys(); ks.sort()
		for t in ks:
			var g: Dictionary = agg[t]
			print("  %s %d부대 · 병력 몫 %.0f%% · 준 피해 몫 %.0f%% · 받은 피해 몫 %.0f%% · 끝까지 생존 %.0f%% · 치료 %.0f/부대" % [TN.get(t, str(t)), g.n,
				g.max / tot.max * 100.0, g.dmg / tot.dmg * 100.0, g.taken / tot.taken * 100.0, float(g.alive) / g.n * 100.0, g.heal / g.n])
	# 기술 · 특기 · 고유기 —— 등급별 카드 평균
	for t in [3, 4, 5, 6]:
		var ks2: Array = DB.by_tier(t).filter(func(k): return not DB.is_foe(k))
		var sk := 0.0; var ps := 0.0; var ul := 0
		for k in ks2:
			var c = DB.C[k]
			sk += (c.get("skills", []) as Array).size() if c is Dictionary else 0
			ps += (c.get("passives", c.get("psv", [])) as Array).size() if c is Dictionary else 0
		print("  %s 카드 %d장 · 기술 평균 %.1f · 특기 평균 %.1f" % [TN[t], ks2.size(), sk / maxf(1, ks2.size()), ps / maxf(1, ks2.size())])
	get_tree().quit()
func _deck(shape: Array, rng: RandomNumberGenerator) -> Array:
	var tags: Array = DB._mix_tags("균형", rng)
	var out := []
	for j in shape.size():
		out.append(DB._army_pick(int(shape[j]), str(tags[j]) if j < tags.size() else "", out, rng.randi(), "균형"))
	return out
