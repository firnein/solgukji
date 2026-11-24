extends Node
## 11/24 잡기술 발동 조건 점검 —— 실행: godot --headless --path . res://tests/minor_trig.tscn
## 장수마다 조건으로 잡기술이 터지는지 (조건별 발동 수 · 잡기술별 수), 결정적인지
const A := ["조운", "마초", "여포", "손책", "장료", "방덕", "전위", "허저", "태사자"]
const B := ["가후", "화타", "조조", "유비", "장합", "하후돈", "황충", "고순", "서황"]

const CA := ["가후", "서서", "진궁", "법정", "제갈량", "주유", "우길", "장각", "화타"]
const CB := ["순욱", "곽가", "노숙", "사마의", "육손", "방통", "관로", "대교"]

func _ready() -> void:
	var cast := "--caster" in OS.get_cmdline_user_args()
	var ta: Array = CA if cast else A
	var tb: Array = CB if cast else B
	var seeds: Array = [7100, 7101, 7102, 7103, 7104] if cast else [7100, 7101, 7102]
	PlayLog.enabled = false
	var helper = preload("res://tests/formation_preview.gd").new()
	for on in [false, true]:
		RtBattle.minor_trig = on
		var mt := {}
		var mn := {}
		var secs := []
		for seed in seeds:
			var bt := RtBattle.new(seed)
			var res: Dictionary = bt.run(DB.auto_place(helper._cards(ta), "eorin"), "eorin", 100, null, DB.auto_place(helper._cards(tb), "hagik"), "hagik", 100, null, "", "", [], {"A": "auto", "B": "auto"})
			var left := {"A": 0.0, "B": 0.0}
			var mx := {"A": 0.0, "B": 0.0}
			for u in bt.units:
				mx[u.camp] += u.max
				left[u.camp] += maxf(0.0, u.troops) if u.alive else 0.0
			secs.append("%.1f초 %s A%d%% B%d%%" % [bt._tm, res.get("winner", "?"), roundi(100 * left.A / mx.A), roundi(100 * left.B / mx.B)])
			for k in bt.stats:
				if str(k).begins_with("mt_") or k == "rescue":
					mt[k] = int(mt.get(k, 0)) + int(bt.stats[k])
			for e in res.ev:
				if e.has("mn") and e.get("fx", "") != "":
					mn[e.mn] = int(mn.get(e.mn, 0)) + 1
			if on:
				var again := RtBattle.new(seed).run(DB.auto_place(helper._cards(ta), "eorin"), "eorin", 100, null, DB.auto_place(helper._cards(tb), "hagik"), "hagik", 100, null, "", "", [], {"A": "auto", "B": "auto"})
				assert(JSON.stringify(again.ev) == JSON.stringify(res.ev), "minor triggers must stay deterministic")
		print("ON" if on else "OFF", " 잡기술 ", mn, " 전투 초 ", secs)
		if on:
			print("조건별 ", mt)
	helper.free()
	print("PASS minor trig")
	get_tree().quit()
