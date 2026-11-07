extends Node
## 보급량 · 등급 다양성 점검 (11/7 사용자: 정상 플레이에서 장수가 너무 많이 만들어져 초월 · 기인은 버려지고 신화 · 불멸로만 덱이 꾸려진다)
## 실행: godot --headless --path . res://tests/supply_check.tscn [-- --runs=20 --win=1]
##   1) 등급별 조합 비용 —— 기본패 환산(재료를 끝까지 풀어 센 기본패 수)과 PV / 비용
##   2) 보급표대로 다 이겼을 때 일차별 수입 (기본패 환산 누적)
##   3) 자동 진행 —— 일차 끝마다 편성 9칸의 등급 구성 · 그때까지 만든 카드 수(등급별)
##      --win=1 은 전투를 다 이긴 것으로 친다 (잘하는 사람에 가깝게). --econ=0 은 예전 보급(DB.ECON 끔)
##   --botpv=1 (11/8) 일차 끝 봇 PV 표 —— 봇 7명의 최고 · 중간 · 최저와 자동 진행 내 PV (페이즈 끝 = 다음 페이즈 성장 앞)

var cost := {}
var bot_mul := 1.0
var bot_tab := false
var bot_sum := []        # 일차 -> [최고 합, 중간 합, 최저 합, 내 PV 합, 판 수]


func _cost(k: String) -> float:
	if cost.has(k):
		return cost[k]
	var c: Dictionary = DB.C[k]
	var v := 1.0
	if c.tier > 1 and DB.RECOF.has(k):
		v = 0.0
		for m in DB.RECOF[k]:
			var s := str(m)
			if DB.C.has(s):
				v += _cost(s)
	cost[k] = v
	return v


func _kind(k: String) -> String:
	if DB.is_kiin(k):
		return "기인"
	return DB.TIER[DB.C[k].tier].n


func _ready() -> void:
	var args := {}
	for s in OS.get_cmdline_user_args():
		var kv := s.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	var runs: int = int(args.get("runs", "12"))
	var force_win: bool = args.get("win", "0") == "1"
	if args.get("econ", "") == "new":      # 11/7 새 보급표 후보 —— 4일차부터 전설 · 희귀 배급을 줄인다 (db.gd ECON 에 넣기 전 측정)
		DB.D.PICKS = [[{"t": 2, "n": 2}], [{"t": 3, "n": 1}, {"t": 1, "n": 1}], [{"t": 3, "n": 2}, {"t": 2, "n": 1}], [{"t": 4, "n": 1}, {"t": 3, "n": 1}],
			[{"t": 4, "n": 1}], [{"t": 4, "n": 1}], [{"t": 4, "n": 1}]]
		DB.D.QUEST_REWARD = [[{"t": 3, "n": 2}], [{"t": 4, "n": 1}], [{"t": 4, "n": 1}], [{"t": 4, "n": 1}], [{"t": 5, "n": 1}], [{"t": 5, "n": 1}], [{"t": 5, "n": 1}]]
		DB.D.RANDOM_GRANT = [[], [], [{"t": 4, "n": 1}], [], [], [], []]
	bot_tab = args.get("botpv", "0") == "1"
	for d in 7:
		bot_sum.append([0.0, 0.0, 0.0, 0.0, 0])
	if args.has("botmul"):      # 봇 성장 배율 (4일차부터) —— 점검용, 페이즈마다 는 몫에 곱한다
		bot_mul = float(args.botmul)
	if args.has("save"):      # --save=경로 —— 저장 파일의 보유 패(손패 + 편성) 비용 합 · 등급 구성 (사람 플레이가 수입을 얼마나 장수로 바꿨는지)
		var sv = JSON.parse_string(FileAccess.open(str(args.save), FileAccess.READ).get_as_text())
		var pool := {}
		for k in sv.inv:
			pool[k] = int(pool.get(k, 0)) + int(sv.inv[k])
		for k in sv.board:
			if k != null:
				pool[k] = int(pool.get(k, 0)) + 1
		var tot := 0.0
		var tiers := {}
		for k in pool:
			tot += _cost(k) * int(pool[k])
			tiers[_kind(k)] = int(tiers.get(_kind(k), 0)) + int(pool[k])
		print("저장 %d일차 %d페이즈 · 보유 비용 %d · %s" % [int(sv.day) + 1, int(sv.phase) + 1, tot, tiers])
		get_tree().quit()
		return

	# 1) 등급별 비용
	var by := {}
	for k in DB.C:
		if DB.is_foe(k) or DB.C[k].tier < 3:
			continue
		var g := _kind(k)
		if not by.has(g):
			by[g] = []
		by[g].append([_cost(k), float(DB.C[k].pv)])
	print("── 등급별 조합 비용 (기본패 환산) ──")
	var tier_cost := {}
	for g in ["고급", "희귀", "전설", "기인", "초월", "불멸", "신화"]:
		if not by.has(g):
			continue
		var cs: Array = by[g].map(func(x): return x[0])
		var pv: Array = by[g].map(func(x): return x[1])
		var ac: float = cs.reduce(func(a, b): return a + b, 0.0) / cs.size()
		var ap: float = pv.reduce(func(a, b): return a + b, 0.0) / pv.size()
		tier_cost[g] = ac
		print("%s %2d장 · 비용 %5.1f (%d~%d) · PV %5.1f · PV/비용 %.2f" % [g, cs.size(), ac, cs.min(), cs.max(), ap, ap / ac])

	# 2) 보급표 수입 (다 이겼을 때)
	print("── 보급표 수입 (모두 이김, 기본패 환산 누적) ──")
	var tc := {1: 1.0, 3: tier_cost["고급"], 4: tier_cost["희귀"], 5: tier_cost["전설"], 6: tier_cost["초월"]}
	var r0 := Run.new()
	r0.new_game(1)
	var cum := 0.0
	var line := []
	for d in 7:
		r0.day = d
		var inc := 0.0
		for p in 3:
			r0.phase = p
			inc += float(DB.D.DRAWS[d]) + float(DB.D.QUEST_BASE[d]) + float(DB.D.PVP_BASE.win)
			for x in r0.pick_list():
				inc += float(x.n) * tc.get(int(x.t), 1.0)
			for x in Run.no_empty_tier(DB.D.QUEST_REWARD[d]):
				inc += float(x.n) * tc.get(mini(5, int(x.t)), 1.0)
			inc += tc[4] if d >= 3 else tc[3]
			for x in DB.D.RANDOM_GRANT[d]:
				inc += float(x.n) * tc.get(mini(5, int(x.t)), 1.0)
		cum += inc
		line.append("%d일 +%d (누적 %d)" % [d + 1, inc, cum])
	print(" · ".join(line))
	print("덱 9칸 비용: 전설 9 = %d · 초월 9 = %d · 불멸 9 = %d · 신화1+불멸8 = %d" % [tier_cost["전설"] * 9, tier_cost["초월"] * 9,
		tier_cost["불멸"] * 9, tier_cost["신화"] + tier_cost["불멸"] * 8])

	# 3) 자동 진행
	print("── 자동 진행 %d판 (%s) —— 일차 끝 편성 등급 평균 · 만든 카드 누적 평균 ──" % [runs, "다 이김" if force_win else "실제 전투"])
	Run.dev_immortal = true
	var names := ["신화", "불멸", "초월", "기인", "전설", "희귀", "고급", "기본"]
	var board_sum := []      # 일차 -> {등급: 합}
	var made_sum := []
	var stat := []           # 일차 -> [토벌 승, 토벌 판, 대전 승, 대전 판, 편성 PV 합, 보유 비용 합]
	for d in 7:
		board_sum.append({})
		made_sum.append({})
		stat.append([0, 0, 0, 0, 0.0, 0.0])
	for n in runs:
		var r := Run.new()
		r.new_game(500 + n)
		var made := {}
		var guard := 0
		while r.over == null and guard < 40:
			guard += 1
			var d0 := r.day
			var before := r.pool().duplicate()
			var st0 := r.strikes
			var w0 := r.my_w
			var l0 := r.my_l
			var tour := r.is_tour_phase()
			var bpv := r.bots.map(func(b): return float(b.pv))
			_phase(r, force_win)
			if r.day >= 3 and bot_mul != 1.0:
				for i in r.bots.size():
					r.bots[i].pv = bpv[i] + (float(r.bots[i].pv) - bpv[i]) * bot_mul
			if not tour:
				stat[d0][1] += 1
				stat[d0][0] += 1 if r.strikes == st0 else 0
				stat[d0][3] += (r.my_w - w0) + (r.my_l - l0)
				stat[d0][2] += r.my_w - w0
			# 이번 페이즈에 새로 생긴 카드 = 조합 결과 (선택권 · 배급은 고급 · 희귀 · 전설뿐이라 초월 위 · 기인은 모두 조합)
			var after := r.pool()
			for k in after:
				var dn: int = int(after[k]) - int(before.get(k, 0))
				if dn > 0 and (DB.C[k].tier >= 6 or DB.is_kiin(k)):
					made[_kind(k)] = int(made.get(_kind(k), 0)) + dn
			if r.day != d0 or r.over != null:
				for g in made:
					made_sum[d0][g] = float(made_sum[d0].get(g, 0.0)) + made[g]
				for k in r.board:
					if k != null:
						board_sum[d0][_kind(k)] = float(board_sum[d0].get(_kind(k), 0.0)) + 1.0
						stat[d0][4] += float(DB.C[k].pv)
				var pc := r.pool()
				for k in pc:
					stat[d0][5] += _cost(k) * int(pc[k])
	for d in 7:
		var bl := []
		var ml := []
		for g in names:
			if board_sum[d].has(g):
				bl.append("%s %.1f" % [g, board_sum[d][g] / runs])
			if made_sum[d].has(g):
				ml.append("%s %.1f" % [g, made_sum[d][g] / runs])
		var sd: Array = stat[d]
		print("%d일 끝 | 토벌 %d/%d · 대전 %d/%d · 편성 PV %d · 보유 비용 %d | 편성: %s | 만든 누적: %s" % [d + 1, sd[0], sd[1], sd[2], sd[3],
			sd[4] / runs, sd[5] / runs, " ".join(bl), " ".join(ml)])
	if bot_tab:
		print("── 일차 끝 봇 PV (봇 7명 최고 · 중간 · 최저, 판 평균) · 자동 진행 내 PV ──")
		for d in 7:
			var b: Array = bot_sum[d]
			if b[4] > 0:
				var n := float(b[4])
				print("%d일 끝 | 봇 최고 %4d · 중간 %4d · 최저 %4d | 내 PV %4d (최고/내 %.2f · 중간/내 %.2f)" % [d + 1, b[0] / n, b[1] / n, b[2] / n,
					b[3] / n, b[0] / maxf(1.0, b[3]), b[1] / maxf(1.0, b[3])])
	get_tree().quit()


## 일차 마지막 페이즈 끝 (다음 페이즈 성장 앞) 봇 PV 를 적는다
func _note_bots(r: Run) -> void:
	if r.phase != 2 and not (r.day == 6 and r.phase == 1):
		return
	var pv: Array = r.bots.map(func(b): return float(b.pv))
	pv.sort()
	var row: Array = bot_sum[r.day]
	row[0] += pv[pv.size() - 1]
	row[1] += pv[pv.size() / 2]
	row[2] += pv[0]
	row[3] += float(r.my_pv())
	row[4] += 1


## Run.dev_autoplay 와 같은 한 페이즈 —— force_win 이면 전투 결과를 이긴 것으로
func _phase(r: Run, force_win: bool) -> void:
	if not force_win:
		if bot_tab and not r.is_tour_phase() and r.over == null:
			# dev_autoplay 와 같은 순서 —— 봇 PV 를 advance(성장) 앞에서 적으려고 풀어 쓴다
			r.bot_prepare()
			r._dev_fight(r.start_quest())
			if r.over == null:
				r._dev_spend()
				r._dev_fight(r.start_pvp())
				_note_bots(r)
				r.advance()
			return
		r.dev_autoplay()
		return
	if not r.drawn and r.draws_n() > 0:
		r.do_draw()
	if not r.picked:
		r.begin_picks("phase")
	if not r.granted and not r.grant_list().is_empty():
		r.random_grant()
	if not r.uniq_offer.is_empty():
		r.pick_unique(r.uniq_offer[0])
	r._dev_spend()
	if r.is_tour_phase():
		r.over = {"win": true, "msg": ""}
		return
	r.start_quest()
	r.finish_battle(_won())
	r._dev_spend()
	r.start_pvp()
	r.finish_battle(_won())
	if bot_tab:
		_note_bots(r)
	r.advance()


func _won() -> Dictionary:
	return {"win": true, "draw": false, "left": 1, "eLeft": 0, "turns": 10, "mvp": null}
