extends Node
## 군집 강체 점검 (11/7) —— 실행: godot --headless --path . res://tests/rigid_check.tscn [-- --tiers=4,6,8 --games=12]
## 풀고 난 뒤 남은 겹침(1px 넘게 파고든 쌍 수 · 최대 깊이), 앞이 막힌 시간, 진형 바깥 측면으로 돈 시간, 측면 · 후방 타격, 전투 길이를 등급별로 센다.

func _ready() -> void:
	var args := {}
	for s in OS.get_cmdline_user_args():
		var kv := s.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	var games := int(args.get("games", "12"))
	var tiers := Array(str(args.get("tiers", "4,6,8")).split(",")).map(func(x): return int(x))
	RtBattle.rigid_probe = true
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for t in tiers:
		var st := {"pen_n": 0, "pen_max": 0.0, "block_t": 0.0, "flank_t": 0.0, "side": 0, "rear": 0, "len": 0.0, "ticks": 0, "wait_m": 0.0, "acts_m": 0, "nm": 0}
		for i in games:
			var pool: Array = DB.by_tier(t)
			var a := []
			var b := []
			for j in 9:
				a.append(pool[rng.randi() % pool.size()])
				b.append(pool[rng.randi() % pool.size()])
			var bt := RtBattle.new(rng.randi() % 100000)
			var r := bt.run(DB.auto_place(a, "eorin"), "eorin", 100, null, DB.auto_place(b, "hagik"), "hagik", 100, null, "", "", [], {"A": "smart", "B": "smart"})
			for k in ["pen_n", "block_t", "flank_t", "side", "rear", "wait_m", "acts_m"]:
				st[k] += r.stats.get(k, 0)
			st.pen_max = maxf(st.pen_max, float(r.stats.get("pen_max", 0.0)))
			st.len += float(r.len)
			st.ticks += int(round(float(r.len) / RtBattle.TICK))
			for u in bt.units:
				if not bt._ranged(u):
					st.nm += 1
		var g := float(games)
		print("등급 %d (%d판): 전투 %.1f초 · 남은 겹침 쌍 틱당 %.3f (최대 %.1fpx) · 막힌 시간 판당 %.1f초 · 측면으로 돈 시간 판당 %.1f초 · 측면 %.1f · 후방 %.1f /판 · 근접 유닛당 논 시간 %.1f초 · 행동 %.1f" % [
			t, games, st.len / g, float(st.pen_n) / maxf(1.0, st.ticks), st.pen_max, st.block_t / g, st.flank_t / g, st.side / g, st.rear / g, st.wait_m / maxf(1, st.nm), float(st.acts_m) / maxf(1, st.nm)])
	get_tree().quit()
