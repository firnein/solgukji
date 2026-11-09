extends Node
## 11/9 민심(hp) 분포 점검 —— 실행: godot --headless --path . res://tests/hp_dist.tscn -- --runs=60 --seed=100
## 자동 진행(멸망하지 않는 모드 —— 민심은 보상에 영향이 없어 궤적이 같다)으로 판마다 일차별 민심 · 토벌 승률 · 0 이 된 일차를 잰다.

func _ready() -> void:
	var args := {}
	for s in OS.get_cmdline_user_args():
		var kv := s.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	var runs := int(args.get("runs", "60"))
	var s0 := int(args.get("seed", "100"))
	Run.dev_immortal = true
	var finals := []
	var dead_day := {}
	var rows := []
	for n in runs:
		var r := Run.new()
		r.new_game(s0 + n)
		var guard := 0
		var q_t := 0
		var q_l := 0
		var zero_at := -1
		var hp_day := []
		var last_day := 0
		while r.over == null and guard < 40:
			guard += 1
			if r.is_tour_phase():
				break
			var st0 := r.strikes
			var d0 := r.day
			r.dev_autoplay()
			q_t += 1
			if r.strikes > st0: q_l += 1
			if r.hp <= 0 and zero_at < 0:
				zero_at = d0 + 1
			while hp_day.size() <= d0: hp_day.append(0)
			hp_day[d0] = r.hp
		finals.append(r.hp)
		rows.append({"hp": r.hp, "ql": q_l, "qt": q_t, "z": zero_at, "pl": r.my_l})
		if zero_at > 0: dead_day[zero_at] = int(dead_day.get(zero_at, 0)) + 1
		print("REC ", JSON.stringify({"seed": s0 + n, "loss": Run.dev_hp_log, "phases": q_t}))
		Run.dev_hp_log = []
		print("판 %d: hp %d · 토벌 %d/%d 패 · 대전 %d패 · 0도달 %s · 일차말 %s" % [n, r.hp, q_l, q_t, r.my_l, str(zero_at), str(hp_day)])
	finals.sort()
	var sum := 0
	for f in finals: sum += f
	print("== 최종 hp 평균 %.1f · 중앙 %d · 최소 %d · 최대 %d" % [sum / float(runs), finals[runs / 2], finals[0], finals[runs - 1]])
	var dead := 0
	for k in dead_day: dead += dead_day[k]
	print("== 사망 %d / %d (%.0f%%) · 일차별 %s" % [dead, runs, dead * 100.0 / runs, str(dead_day)])
	# 토벌 승률 구간별
	for band in [[0.0, 0.4], [0.4, 0.7], [0.7, 1.01]]:
		var c := 0
		var hs := 0
		var dd := 0
		for x in rows:
			var wr: float = 1.0 - float(x.ql) / maxf(1.0, float(x.qt))
			if wr >= band[0] and wr < band[1]:
				c += 1
				hs += x.hp
				if x.z > 0: dd += 1
		print("== 토벌 승률 %.0f~%.0f%%: %d판 · 평균 hp %.1f · 사망 %d" % [band[0] * 100, minf(band[1], 1.0) * 100, c, hs / maxf(1.0, float(c)), dd])
	get_tree().quit()
