extends Node
## 11/22 전투 지표 기록 점검 —— 실행: godot --headless --path . res://tests/log_metrics.tscn
## 불멸 9장끼리 한 판을 돌려 PlayLog.battle_end_data 의 장수별 새 칸(id · items · kind · dot · blk · over · gain · ult · ult_tm · sk · sig · out_tm)이
## 채워지는지 본다. 파일은 쓰지 않는다 (사용자 저장 · 플레이 기록을 건드리지 않는다).

func _ready() -> void:
	var fails := []
	var pool: Array = DB.by_tier(7)
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	var tot := {"ult": 0, "sk": 0, "sig": 0, "blk": 0, "dot": 0, "out": 0, "items": 0}
	for g in 3:
		var a := []
		var b := []
		for i in 9:
			a.append(pool[rng.randi() % pool.size()])
			b.append(pool[rng.randi() % pool.size()])
		var eq := []      # 아군 9칸 모두 무기 하나 (장비 이름 칸 점검)
		for i in 9:
			eq.append([DB.IT.keys()[g], null])
		var res := RtBattle.make(rng.randi()).run(DB.auto_place(a, "eorin"), "eorin", 100, eq, DB.auto_place(b, "hagik"), "hagik", 100, null, "", "", [], {"A": "smart", "B": "smart"})
		var d := PlayLog.battle_end_data(null, res, 0.0, [], {})
		var units: Array = d.units
		if units.size() != 18:
			fails.append("부대 수 %d" % units.size())
		for u in units:
			for k in ["id", "items", "kind", "dot", "blk", "over", "gain", "ult", "ult_tm", "sk", "sig", "out_tm"]:
				if not u.has(k):
					fails.append("%s 칸 없음 (%s)" % [k, u.name])
			if str(u.id) == "" or not DB.C.has(str(u.id)):
				fails.append("카드 번호 %s (%s)" % [u.id, u.name])
			if u.ult != (u.ult_tm as Array).size():
				fails.append("고유기 횟수 · 시각 수 다름 (%s)" % u.name)
			if bool(u.alive) and float(u.out_tm) >= 0.0:
				fails.append("살았는데 무너진 시각 (%s)" % u.name)
			tot.ult += int(u.ult)
			tot.sk += int(u.sk)
			tot.sig += int(u.sig)
			tot.blk += int(u.blk)
			tot.dot += int(u.dot)
			tot.out += 1 if float(u.out_tm) >= 0.0 else 0
			tot.items += (u.items as Array).size()
		var ult_sum := 0
		for u in units:
			if u.camp == "A":
				ult_sum += int(u.ult)
		if ult_sum != int(d.ult_fired):
			fails.append("판 %d 아군 고유기 합 %d ≠ ult_fired %d" % [g, ult_sum, d.ult_fired])
		if g == 0:
			for u in units.slice(0, 3):
				print("예: ", JSON.stringify(u))
	for k in ["ult", "sk", "blk", "out", "items"]:
		if int(tot[k]) <= 0:
			fails.append("세 판 합 %s = 0" % k)
	print("전투 지표 점검 —— 합 %s · 실패 %d" % [JSON.stringify(tot), fails.size()])
	for f in fails.slice(0, 10):
		print("FAIL: ", f)
	get_tree().quit()
