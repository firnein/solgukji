extends Node
## 등급별 · 기질별 고유기 발동률 (11/7) —— 같은 등급 무작위 9장끼리, 고유기가 있는 부대 가운데 한 번이라도 터뜨린 비율 · 첫 발동 시각
## 실행: godot --headless --path . res://tests/ult_rate.tscn -- --tiers=6,7,8 --games=30

func _ready() -> void:
	var args := {}
	for s in OS.get_cmdline_user_args():
		var kv := s.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	var games := int(args.get("games", "30"))
	var tiers := Array(str(args.get("tiers", "6,7,8")).split(",")).map(func(x): return int(x))
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	for t in tiers:
		var have := 0
		var fired := 0
		var n_ult := 0
		var first_t := 0.0
		var len_sum := 0.0
		var tp := {}      # 기질 -> [보유, 발동, 첫 발동 합]
		for i in games:
			var pool: Array = DB.by_tier(t)
			var a := []
			var b := []
			for j in 9:
				a.append(pool[rng.randi() % pool.size()])
				b.append(pool[rng.randi() % pool.size()])
			var bt := RtBattle.new(rng.randi() % 100000)
			var r := bt.run(DB.auto_place(a, "eorin"), "eorin", 100, null, DB.auto_place(b, "hagik"), "hagik", 100, null, "", "", [], {"A": "smart", "B": "smart"})
			len_sum += float(r.len)
			var cnt := {}
			var ft := {}
			for e in r.ev:
				if e.get("fx") == "ult":
					var k: String = str(e.get("a", ""))
					cnt[k] = int(cnt.get(k, 0)) + 1
					if not ft.has(k):
						ft[k] = float(e.get("tm", 0.0))
			for u in bt.units:
				if u.ult != null:
					have += 1
					var tk: String = u.temper if u.temper != "" else "(없음)"
					if not tp.has(tk):
						tp[tk] = [0, 0, 0.0]
					tp[tk][0] += 1
					if cnt.has(u.key):
						fired += 1
						n_ult += int(cnt[u.key])
						first_t += float(ft[u.key])
						tp[tk][1] += 1
						tp[tk][2] += float(ft[u.key])
		print("등급 %d (%d판): 전투 %.1f초 · 고유기 보유 부대 %d 중 발동 %d (%.0f%%) · 발동 부대당 %.2f번 · 첫 발동 평균 %.1f초" % [
			t, games, len_sum / games, have, fired, 100.0 * fired / maxf(1, have), float(n_ult) / maxf(1, fired), first_t / maxf(1, fired)])
		var parts := []
		for tk in tp:
			parts.append("%s %d명 발동 %.0f%% 첫 %.1f초" % [tk, tp[tk][0], 100.0 * tp[tk][1] / maxf(1, tp[tk][0]), tp[tk][2] / maxf(1, tp[tk][1])])
		print("   기질별: " + " · ".join(parts))
	get_tree().quit()
