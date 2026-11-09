extends Node
## 난이도 점검 (11/9 사용자: 토벌 · 봇 대전이 여전히 너무 쉽다) —— 실행:
##   godot --headless --path . res://tests/diff_probe.tscn -- --mode=table|quest|pvp [--days=1-7 --games=16 --k=1.0 --kp=1.0 --seed=1]
## 사람 기록(replay_log)이 없을 때의 대역 —— 내 편 = 자동 진행이 일차 끝에 짜는 편성 PV(supply_check 의 '편성 PV')에 k 를 곱한 DB.gen_board 덱(장비 없음).
##   k 는 '사람이 같은 PV 의 gen_board 덱보다 얼마나 센가' —— 1.0d 값에서 사람 기록(첫 토벌 35% · 일차별 60 · 53 · 63 · 39 · 51 · 52 · 49% 남음 · 대전 71 · 63 · 63 · 63 · 50 · 79 · 63%)에 가깝게 맞춰 두고 같은 k 로 바뀐 값을 잰다.
## mode=table  적 구성 표 (토벌 일차별 등급 · 병력 · 병사 수 / 봇 일차 끝 덱 등급)
## mode=quest  일차별 토벌 승률 · 내 남은 병력 · 적 남은 병력 · 길이   (k = 내 PV 배율)
## mode=pvp    일차별 대전 승률 · 남은 병력   (kp = 내 PV 배율, 봇은 일차 끝 PV = 봇 성장 합 × 실력 평균)

## 자동 진행(다 이김)이 일차 끝에 짠 편성 PV (tests/supply_check --win=1)
const MY_END := [81.0, 154.0, 187.0, 237.0, 325.0, 394.0, 417.0]
const STYLES := ["물리", "지략", "균형"]
var men := false
var k0 := 0.75      # 1-1(첫 토벌)만 따로 —— 사람 기록 첫 토벌 35% 남음에 맞춘 값


func _my_pv(d: int, p: int) -> float:
	var prev := 20.0 if d == 0 else float(MY_END[d - 1])
	return prev + (float(MY_END[d]) - prev) * float(p + 1) / 3.0


## 봇 PV —— run.gd advance(페이즈마다 성장) · finish_battle(토벌을 치를 때마다 봇 PV 가 그 토벌 PV × 0.95 보다 낮으면 × 0.94) 를 그대로 (난수는 평균). (d, p) 의 토벌을 치른 뒤
func _bot_pv(d: int, p: int, skill: float) -> float:
	var s := 0.0
	for dd in range(0, d + 1):
		for pp in 3:
			if dd == d and pp > p:
				break
			if not (dd == 0 and pp == 0):
				s += Run.bot_pv_gain(dd, pp) * skill
			if s < float(DB.QUEST_ROSTERS[dd][pp].pv) * 0.95:
				s *= 0.94
	return s


func _tiers(cards: Array) -> String:
	var cnt := {}
	for k in cards:
		if k != null:
			cnt[DB.C[k].tier] = int(cnt.get(DB.C[k].tier, 0)) + 1
	var ks := cnt.keys()
	ks.sort()
	ks.reverse()
	return " ".join(ks.map(func(t): return "%d등급×%d" % [t, cnt[t]]))


func _troops(cards: Array, mul: float) -> float:
	var s := 0.0
	for k in cards:
		if k != null:
			s += float(DB.C[k].tr) * mul
	return s


## 전장에 그려질 병사 수 [내 편, 적] —— replay_log 와 같은 셈 (Squad, 품질 배율 1)
func _men(rs: Dictionary) -> Array:
	var rng := RandomNumberGenerator.new()
	var n := [0, 0]
	for row in rs.get("roster", []):
		var sq := Squad.new(row, Vector2.ZERO, rng, float(rs.get("lay", 1.0)))
		n[0 if row.camp == "A" else 1] += sq.soldiers.size()
	return n


func _left(res: Dictionary, camp: String) -> float:
	var l := 0
	var m := 0
	for u in res.get("roster", []):
		if u.camp == camp:
			l += maxi(0, int(u.left))
			m += int(u.max)
	return float(l) / maxf(1.0, float(m))


func _ready() -> void:
	var args := {}
	for s in OS.get_cmdline_user_args():
		var kv := s.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	var mode := str(args.get("mode", "table"))
	var games := int(args.get("games", "16"))
	var k := _list(str(args.get("k", "1.0")))
	var kp := _list(str(args.get("kp", "1.0")))
	var seed0 := int(args.get("seed", "1"))
	k0 = float(args.get("k0", "0.75"))
	men = args.has("men")
	# 값 미리 재 보기 (run.gd 값을 덮는다): --qtr=7개 --qmor=7개 --horde=7개 --rdrop=7개 --rfloor=7개
	if args.has("qtr"): Run.QUEST_TR = _list(str(args.qtr))
	if args.has("qmor"): Run.QUEST_MORALE = _list(str(args.qmor))
	if args.has("horde"): Run.QUEST_HORDE = _list(str(args.horde)).map(func(x): return int(x))
	if args.has("rdrop"): Run.QUEST_RABBLE_DROP = _list(str(args.rdrop)).map(func(x): return int(x))
	if args.has("rfloor"): Run.QUEST_RABBLE_FLOOR = _list(str(args.rfloor)).map(func(x): return int(x))
	if args.has("late"): Run.BOT_LATE = _list(str(args.late))
	var dr := str(args.get("days", "1-7")).split("-")
	var d0 := int(dr[0]) - 1
	var d1 := int(dr[dr.size() - 1]) - 1
	var phases := str(args.get("ph", "0,1,2")).split(",")
	match mode:
		"table":
			_table(d0, d1)
		"quest":
			_quest(d0, d1, games, k, seed0, phases)
		"pvp":
			_pvp(d0, d1, games, kp, seed0, phases)
		"tour":
			_tour(games, kp, seed0)
	get_tree().quit()


func _table(d0: int, d1: int) -> void:
	print("── 토벌 적 구성 (우두머리 9칸 + 잡병 · 병력은 QUEST_TR 곱한 뒤) ──")
	var r := Run.new()
	r.new_game(1)
	for d in range(d0, d1 + 1):
		for p in 3:
			r.day = d
			r.phase = p
			var bt := r.start_quest()
			var foe: Dictionary = bt.b
			var cards: Array = foe.cards
			var boss := cards.slice(0, 9)
			var rab := cards.slice(9)
			var tr := float(foe.get("tr_mul", 1.0))
			var mine := DB.gen_board(_my_pv(d, p), "균형", RandomNumberGenerator.new())
			print("%d-%d %-8s 사기 %3d | 우두머리 %s | 잡병 %2d부대 %s | 병력 우두머리 %6.0f 잡병 %6.0f (잡병 %2.0f%%) | 내 PV %.0f 병력 %6.0f" % [d + 1, p + 1, bt.foe, int(foe.morale),
				_tiers(boss.filter(func(x): return x != null)), rab.size(), _tiers(rab), _troops(boss, tr), _troops(rab, tr),
				100.0 * _troops(rab, tr) / maxf(1.0, _troops(cards, tr)), _my_pv(d, p), _troops(mine.cards, 1.0)])
	print("── 봇 대전 상대 덱 (그 일차 끝, 봇 실력 평균 1.25) ──")
	var rr := RandomNumberGenerator.new()
	rr.seed = 5
	for d in range(d0, d1 + 1):
		var pv := _bot_pv(d, 2, 1.25) * Run.BOT_PV_MUL
		var lo := {}
		var hist := {}
		var n := 40
		for st in STYLES:
			for i in n:
				var eb := DB.gen_board(pv, st, rr)
				var mn := 9
				for c in eb.cards:
					mn = mini(mn, int(DB.C[c].tier))
					hist[DB.C[c].tier] = int(hist.get(DB.C[c].tier, 0)) + 1
				lo[mn] = int(lo.get(mn, 0)) + 1
		var hs := hist.keys()
		hs.sort()
		hs.reverse()
		print("%d일 봇 PV %4.0f | 칸 등급 분포(평균 9칸) %s | 최저 등급 %s" % [d + 1, pv, " ".join(hs.map(func(t): return "%d등급 %.1f" % [t, hist[t] / float(n * 3)])), str(lo)])


## --k=0.9,1.2,... 일차마다 배율 (모자라면 마지막 값)
func _list(s: String) -> Array:
	return Array(s.split(",")).map(func(x): return float(x))


func _kd(l: Array, d: int) -> float:
	return float(l[mini(d, l.size() - 1)])


func _quest(d0: int, d1: int, games: int, k: Array, seed0: int, phases: Array) -> void:
	var tot_w := 0.0
	var tot_l := 0.0
	var tot_n := 0
	for d in range(d0, d1 + 1):
		var dw := 0.0
		var dl := 0.0
		var dfl := 0.0
		var dn := 0
		var dlen := 0.0
		var dmen := [0.0, 0.0]
		var dfmax := 0.0
		for ps in phases:
			var p := int(ps)
			var rng := RandomNumberGenerator.new()
			rng.seed = seed0 * 1000 + d * 10 + p
			for i in games:
				var r := Run.new()
				r.new_game(seed0 * 100000 + d * 1000 + p * 100 + i)
				r.day = d
				r.phase = p
				var bt := r.start_quest()
				var eb := DB.gen_board(_my_pv(d, p) * (k0 if d == 0 and p == 0 else _kd(k, d)), STYLES[i % 3], rng)
				var mine := DB.auto_place(eb.cards, eb.form)
				bt.a = {"cards": mine, "form": eb.form, "morale": 100, "equip": [], "tac": Run.recommend_tac(mine)[0]}
				var res := Run.simulate(bt, [], Run.policy_for(bt))
				dw += 1.0 if res.win else (0.5 if res.draw else 0.0)
				dl += _left(res, "A")
				dfl += _left(res, "B")
				dlen += float(res.get("len", 0.0))
				if men:
					var m := _men(res)
					dmen[0] += m[0]
					dmen[1] += m[1]
				for u in res.get("roster", []):
					if u.camp == "B":
						dfmax += float(u.max)
				dn += 1
		print("QUEST %d일 | 승 %3.0f%% | 내 남은 병력 %3.0f%% | 적 남은 %3.0f%% | %4.1f초 | 적 병력 %5.0f | 병사 내 %4.0f 적 %4.0f | n=%d" % [d + 1, dw / dn * 100, dl / dn * 100, dfl / dn * 100, dlen / dn, dfmax / dn, dmen[0] / dn, dmen[1] / dn, dn])
		tot_w += dw
		tot_l += dl
		tot_n += dn
	print("QUEST 평균 | 승 %3.0f%% | 내 남은 병력 %3.0f%%" % [tot_w / maxi(1, tot_n) * 100, tot_l / maxi(1, tot_n) * 100])


func _pvp(d0: int, d1: int, games: int, kp: Array, seed0: int, phases: Array) -> void:
	for d in range(d0, d1 + 1):
		var dw := 0.0
		var dl := 0.0
		var dn := 0
		for ps in phases:
			var p := int(ps)
			var rng := RandomNumberGenerator.new()
			rng.seed = seed0 * 1000 + d * 10 + p
			for i in games:
				var r := Run.new()
				r.new_game(seed0 * 100000 + d * 1000 + p * 100 + i)
				r.day = d
				r.phase = p
				for b in r.bots:
					b.pv = _bot_pv(d, p, b.skill)
				var bt := r.start_pvp()
				var eb := DB.gen_board(_my_pv(d, p) * _kd(kp, d), STYLES[i % 3], rng)
				var mine := DB.auto_place(eb.cards, eb.form)
				bt.a = {"cards": mine, "form": eb.form, "morale": 100, "equip": [], "tac": Run.recommend_tac(mine)[0]}
				var res := Run.simulate(bt, [], Run.policy_for(bt))
				dw += 1.0 if res.win else (0.5 if res.draw else 0.0)
				dl += _left(res, "A")
				dn += 1
		print("PVP %d일 | 승 %3.0f%% | 내 남은 병력 %3.0f%% | n=%d" % [d + 1, dw / dn * 100, dl / dn * 100, dn])


## 토너먼트 어림 —— 7일 끝 편성(사람 대역)이 최고 시드: 1라운드는 가장 약한 봇, 2라운드는 봇 3 · 4위, 결승은 봇 1 · 2위 (init_tour 시드 순서 [0,7,3,4,1,6,2,5] 에 사람이 맨 위일 때. 다른 봇끼리의 승부는 반반)
func _tour(games: int, kp: Array, seed0: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed0
	var rw := [0, 0, 0]
	var rn := [0, 0, 0]
	var champ := 0
	for i in games:
		var r := Run.new()
		r.new_game(seed0 * 100000 + i)
		r.day = 6
		r.phase = 2
		var bl := r.bots.duplicate()
		for b in bl:
			b.pv = _bot_pv(6, 2, b.skill)
		bl.sort_custom(func(a, b): return a.pv > b.pv)
		var eb := DB.gen_board(_my_pv(6, 2) * _kd(kp, 6), STYLES[i % 3], rng)
		var mine := DB.auto_place(eb.cards, eb.form)
		var opp := [bl[6], bl[2 if rng.randf() < 0.5 else 3], bl[0 if rng.randf() < 0.5 else 1]]
		var alive := true
		for rd in 3:
			if not alive:
				break
			var foe: Dictionary = r._bot_side(opp[rd].pv, opp[rd].style)
			var bt := {"a": {"cards": mine, "form": eb.form, "morale": 100, "equip": [], "tac": Run.recommend_tac(mine)[0]},
				"b": foe, "seed": rng.randi() % 1000000, "title": "", "foe": ""}
			var res := Run.simulate(bt, [], Run.policy_for(bt))
			rn[rd] += 1
			if res.win:
				rw[rd] += 1
			else:
				alive = false
		if alive:
			champ += 1
	print("TOUR 우승 %3.0f%% | n=%d" % [champ * 100.0 / games, games])
	print("TOUR 라운드별 %s / %s" % [str(rw), str(rn)])
