extends Node
## 고유기 간격 점검 —— 실행: godot --headless --path . res://tests/ult_gap.tscn [-- --pv=1000 --games=10]
func _ready() -> void:
	var args := {}
	for s in OS.get_cmdline_user_args():
		var kv := s.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	var pv := float(args.get("pv", "1000"))
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var tot := 0
	var mingap := 99.0
	var styles := ["물리", "지략", "균형"]
	for g in int(args.get("games", "10")):
		var x := Run.bot_side(pv, styles[g % 3], 15, rng)
		var y := Run.bot_side(pv, styles[(g + 1) % 3], 15, rng)
		var r := RtBattle.make(rng.randi()).run(x.cards, x.form, 100, x.equip, y.cards, y.form, 100, y.equip, "", "", [], {"A": "smart", "B": "smart"})
		var ts := []
		for e in r.ev:
			if e.get("fx") == "ult":
				ts.append(snappedf(float(e.get("tm", 0.0)), 0.1))
		for i in range(1, ts.size()):
			mingap = minf(mingap, ts[i] - ts[i - 1])
		tot += ts.size()
		print("%d초 · 고유기 %d번 %s" % [r.len, ts.size(), str(ts)])
	print("평균 %.1f번 · 최소 간격 %.1f초" % [tot / float(int(args.get("games", "10"))), mingap])
	get_tree().quit()
