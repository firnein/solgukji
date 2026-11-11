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
	if args.has("online"):      # 11/11 --online=4000 : 온라인 방 7일 민심 — 토벌 1~3일차만 · 대전 패배 ×1.0 (전: 토벌 매 페이즈 · 대전 ×0.6) —— 아래 _mock_online
		_mock_online(int(args.online), s0)
		get_tree().quit()
		return
	if args.has("mock"):      # 11/10 --mock=4000 : 승률별 모의만 (자동 진행 없이 몇 초) —— 아래 _mock
		_mock(int(args.mock), s0)
		get_tree().quit()
		return
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
	_bonus_table(Run.dev_bonus_log)
	get_tree().quit()


## 11/10 토벌 성과 보너스 —— 일차별 토벌 수 · 이김 · 대승 · 평균 r · 이긴 판의 평균 보너스 기본패 · 선택권 · 기본 보상(기본패) 대비 %
## 행: [일차, 이김, r, 보너스 기본패, 보너스 선택권, 그날 기본패]. 오토는 대부분 지니 이긴 판이 적다(표본 주의)
static func _bonus_table(log: Array) -> void:
	print("== 토벌 보너스 (오토 진행 · 이긴 판만 보너스) 일차 | 토벌 | 이김 | 대승 | 이긴 판 평균 r | 이긴 판 평균 기본패 +n | 선택권 합 | 토벌 전체 기본패 대비")
	var tb := 0
	var tt := 0
	var tbase := 0
	for d in 7:
		var n := 0
		var w := 0
		var big := 0
		var rs := 0.0
		var bs := 0
		var ts := 0
		var base := 0
		for x in log:
			if int(x[0]) != d:
				continue
			n += 1
			base += int(x[5])
			if x[1]:
				w += 1
				rs += float(x[2])
				bs += int(x[3])
				ts += int(x[4])
				if float(x[2]) >= Run.QUEST_BONUS_BIG:
					big += 1
		tb += bs
		tt += ts
		tbase += base
		if n > 0:
			print("   %d일차 | %d | %d | %d | %.2f | %.2f | %d | +%.1f%%" % [d + 1, n, w, big, rs / maxf(1.0, float(w)), bs / maxf(1.0, float(w)), ts, bs * 100.0 / maxf(1.0, float(base))])
	print("   합계 : 보너스 기본패 %d · 선택권 %d · 토벌 기본패 합 %d (+%.1f%%)" % [tb, tt, tbase, tb * 100.0 / maxf(1.0, float(tbase))])


## 승률별 모의 (11/10) —— 일차마다 (토벌 · 대전) × (3번, 7일차는 2번). 지면 적 남은 비를 정규분포(평균 fm · 편차 0.14)에서 뽑아 Run.hp_dmg_f 로 깎는다
## 사람의 기록(tests/logs/user_1109.jsonl)에서 진 판의 적 남은 비는 0.52~0.77, 오토 진 판은 0.85~0.99 —— 그래서 능숙 0.55 · 보통 0.65 · 약함 0.85
## 승률이 같아도 잘하는 사람은 아슬하게 진다는 가정이다
func _mock(n: int, seed0: int) -> void:
	var profiles := [["능숙(토벌 80% · 대전 70%)", 0.8, 0.7, 0.55], ["보통(65% · 55%)", 0.65, 0.55, 0.65], ["약함(35% · 35%)", 0.35, 0.35, 0.85]]
	print("== HP_QUEST %s · 적 남은 비 계수 %.2f + %.2f × 비 · 대전 ×%.1f" % [str(Run.HP_QUEST), Run.HP_FOE_MIN, Run.HP_FOE_MUL, Run.HP_PVP_MUL])
	for p in profiles:
		var rng := RandomNumberGenerator.new()
		rng.seed = seed0
		var dead := 0
		var dead_day := {}
		var fin := 0.0
		var day_end := []
		var day_cnt := []
		for d in 7:
			day_end.append(0.0)
			day_cnt.append(0)
		for i in n:
			var hp := 100
			var z := -1
			for d in 7:
				for ph in (3 if d < 6 else 2):
					for kind in [0, 1]:
						if rng.randf() < (p[1] if kind == 0 else p[2]):
							continue
						var f := clampf(rng.randfn(p[3], 0.14), 0.05, 1.0)
						hp = maxi(0, hp - Run.hp_dmg_f(float(Run.HP_QUEST[d]) * (1.0 if kind == 0 else Run.HP_PVP_MUL), f, false))
						if hp <= 0 and z < 0:
							z = d + 1
					if z > 0:
						break
				day_end[d] += hp      # 멸망한 판은 그 뒤 일차도 0 으로 센다
				day_cnt[d] += 1
				if z > 0:
					for d2 in range(d + 1, 7):
						day_cnt[d2] += 1
					break
			if z > 0:
				dead += 1
				dead_day[z] = int(dead_day.get(z, 0)) + 1
			fin += hp
		var de := []
		for d in 7:
			de.append(roundi(day_end[d] / maxf(1.0, float(day_cnt[d]))))
		print("%s : 멸망 %.0f%% · 최종 평균 %.1f · 일차말 %s · 멸망일 %s" % [p[0], dead * 100.0 / n, fin / n, str(de), str(dead_day)])


## 11/11 온라인 방 7일 민심 —— 같은 모의(일차마다 토벌 · 대전 × 3번, 7일차는 2번 + 토너먼트는 민심 없음)를 두 규칙으로:
## 전 = 토벌 매 페이즈(20번) + 대전 패배 ×HP_PVP_MUL(0.6) / 후 = 토벌 1~3일차만(9번) + 대전 패배 ×HP_PVP_MUL_ONLINE(1.0).
## 대전 승률은 상대 구성에 따라 —— 봇전 85% · 사람전 60% · 혼합(8석 중 사람 4 = 상대 7 중 사람 3 · 봇 4) 74%. 토벌 승률 · 진 판의 적 남은 비는 _mock 의 능숙 / 보통 / 약함과 같다.
## 출력: 기대 총 민심 손실(멸망 뒤에도 계속 깎는다고 치고 0 밑으로 안 막음 · 100 기준) · 멸망 % · 최종 민심 평균
func _mock_online(n: int, seed0: int) -> void:
	var skill := [["능숙(토벌 80% · 적 남은 비 0.55)", 0.8, 0.55], ["보통(토벌 65% · 0.65)", 0.65, 0.65], ["약함(토벌 35% · 0.85)", 0.35, 0.85]]
	var mixes := [["봇전 85%", 0.85], ["혼합 74%", 0.74], ["사람전 60%", 0.60]]
	print("== 온라인 7일 민심 모의 (%d판씩) · HP_QUEST %s · 전: 토벌 20번 · 대전 ×%.1f / 후: 토벌 9번 · 대전 ×%.1f" % [n, str(Run.HP_QUEST), Run.HP_PVP_MUL, Run.HP_PVP_MUL_ONLINE])
	for sk in skill:
		for mx in mixes:
			var line := "%s · 대전 %s :" % [sk[0], mx[0]]
			for rule in [0, 1]:
				var rng := RandomNumberGenerator.new()
				rng.seed = seed0
				var loss_sum := 0.0
				var q_loss := 0.0
				var p_loss := 0.0
				var dead := 0
				var fin := 0.0
				for i in n:
					var hp := 100
					var loss := 0
					var ql := 0
					var pl := 0
					var z := false
					for d in 7:
						for ph in (3 if d < 6 else 2):
							if rule == 0 or d < Run.ONLINE_NOON_DAYS:
								if rng.randf() >= sk[1]:
									var dq := Run.hp_dmg_f(float(Run.HP_QUEST[d]), clampf(rng.randfn(sk[2], 0.14), 0.05, 1.0), false)
									loss += dq
									ql += dq
									hp = maxi(0, hp - dq)
							if rng.randf() >= mx[1]:
								var dp := Run.hp_dmg_f(float(Run.HP_QUEST[d]) * (Run.HP_PVP_MUL if rule == 0 else Run.HP_PVP_MUL_ONLINE), clampf(rng.randfn(sk[2], 0.14), 0.05, 1.0), false)
								loss += dp
								pl += dp
								hp = maxi(0, hp - dp)
							if hp <= 0:
								z = true
					loss_sum += loss
					q_loss += ql
					p_loss += pl
					fin += hp
					if z:
						dead += 1
				line += "  %s 총 손실 %.1f(토벌 %.1f + 대전 %.1f) · 멸망 %.0f%% · 최종 %.1f" % ["전" if rule == 0 else "후", loss_sum / n, q_loss / n, p_loss / n, dead * 100.0 / n, fin / n]
				if rule == 0:
					line += "  →"
			print(line)
