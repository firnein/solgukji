extends Node
## 군략 영향 · 받아치기 · 예측 점검 (11/25) —— 실행:
##   godot --headless --path . res://tests/tac_impact.tscn -- [--games=60] [--days=0,2,4] [--seed=1] [--out=결과.json]
##   나눠 돌린 뒤 모으기: ... -- --merge=폴더 (그 폴더의 *.json 을 더해 표를 찍는다)
## 규칙 · 수치는 바꾸지 않는다. 덱은 봇과 같은 DB.gen_board(같은 PV ±5%, 무작위 스타일), 시드 고정, 같은 두 덱을 자리 바꿔 두 번.
## 손패는 Tac.sim_hand(날 수), 봇 계획은 Run.bot_plan_load(서버 봇과 같은 식). X = 받아치는 쪽(사람 자리), Y = 봇.
## 덱 한 쌍마다:
##   base  계획 없음 대 없음 · seed 시드만 바꾼 없음 대 없음(판 자체의 운) · solo 한쪽만 봇 계획 · both 둘 다 봇 계획
##   cnt   Y 봇 계획을 다 알고 받아침 · rnd 무작위 · anti 일부러 짐
##   pred  예측한 계열을 받아침 —— p1 지난 대전 계획 반복 · p2 보이는 장수(높은 3명) 쏠림 · p3 덱 전체 쏠림(화면엔 안 보임, 상한)
##   grade 등급별 카드 한 장을 한 단계에만 놓기 (상대 없음)
## 카드별 기여도 모드: ... -- --card=돌격,화공 (또는 --card=all) [--games=40] [--days=0,2,4] [--out=…]
##   카드 하나만 쓴 쪽(단계 전용이 아니면 판마다 1 · 2 · 3단계를 돌아가며, 늘 카드는 own) 승률을
##   계획 없는 같은 판과 비교 —— 상대 없음 · 상대 봇 계획 두 가지. 다른 조건은 돌리지 않는다

const Tac := preload("res://scripts/tactics.gd")
const PV := {0: 100.0, 1: 200.0, 2: 300.0, 3: 430.0, 4: 540.0, 5: 600.0, 6: 600.0}      # 그날 끝 봇 PV 어림 (run.gd bot_pv_gain 주석)
const STYLES := ["물리", "지략", "균형"]

## 모은 수 —— 키는 모두 글 (여러 결과 파일을 JSON 으로 더하려고)
var R := {"S": {}, "stg": {}, "net": {}, "pred": {}, "gr": {}, "card": {}, "reach": [0, 0, 0], "lens": 0.0, "hand": {}, "games": 0, "sec": 0.0}
var t_ms := 0
var cards := []      # --card 모드의 카드 id (비면 보통 모드)


func _ready() -> void:
	var args := {}
	for s in OS.get_cmdline_user_args():
		var kv := s.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	Tac.data()
	if args.has("merge"):
		_merge(str(args.merge))
		_report()
		get_tree().quit()
		return
	var games := int(args.get("games", "60"))
	var days := []
	for d in str(args.get("days", "0,2,4")).split(","):
		days.append(int(d))
	var seed0 := int(args.get("seed", "1"))
	if args.has("card"):
		for id in str(args.card).split(","):
			if id == "all":
				for k in Tac.CARDS:
					var kind := str(Tac.card(k).get("kind", ""))
					if Tac.is_on(k) and (kind == "plan" or kind == "passive") and not cards.has(k):
						cards.append(k)
			elif Tac.has(id) and not cards.has(id):
				cards.append(id)
			else:
				print("  모르는 카드: ", id)
		cards.sort()
	t_ms = Time.get_ticks_msec()
	for d in days:
		var rng := RandomNumberGenerator.new()
		rng.seed = 7000 + seed0 * 100 + d
		for g in games:
			if cards.is_empty():
				_game(d, rng)
			else:
				_card_game(d, g, rng)
		print("  %d일차 %d판 끝 (%.0f초)" % [d + 1, games, (Time.get_ticks_msec() - t_ms) / 1000.0])
	R.games = games * days.size()
	R.sec = (Time.get_ticks_msec() - t_ms) / 1000.0
	if args.has("out"):
		var f := FileAccess.open(str(args.out), FileAccess.WRITE)
		f.store_string(JSON.stringify(R))
		f.close()
	_report()
	get_tree().quit()


## 나눠 돌린 결과 파일들을 더한다
func _merge(dir: String) -> void:
	for fn in DirAccess.get_files_at(dir):
		if not fn.ends_with(".json"):
			continue
		var o = JSON.parse_string(FileAccess.get_file_as_string(dir.path_join(fn)))
		if not (o is Dictionary):
			continue
		for k in ["stg", "net", "pred", "gr", "hand", "card"]:
			for kk in o.get(k, {}):
				_acc(k, kk, o[k][kk])
		for kk in o.S:
			if not R.S.has(kk):
				R.S[kk] = {"n": 0.0, "w": 0.0, "flip": 0.0}
			for f in ["n", "w", "flip"]:
				R.S[kk][f] += float(o.S[kk][f])
		for i in 3:
			R.reach[i] += float(o.reach[i])
		R.lens += float(o.lens)
		R.games += int(o.games)
		R.sec = maxf(float(R.sec), float(o.sec))


func _acc(k: String, kk, vals: Array) -> void:
	var key := str(kk)
	if not R[k].has(key):
		var z := []
		z.resize(vals.size())
		z.fill(0.0)
		R[k][key] = z
	for i in vals.size():
		R[k][key][i] += float(vals[i])


func _side(pv: float, rng: RandomNumberGenerator, d: int) -> Dictionary:
	var st: String = STYLES[rng.randi() % STYLES.size()]
	var eb := DB.gen_board(pv, st, rng)
	var cards := DB.auto_place(eb.cards, eb.form)
	var bsd := rng.randi() % 1000000
	var p_idx := d * 3 + 2
	var hsd := DB.mix_seed(bsd, 0, 19)
	return {"cards": cards, "form": eb.form, "bsd": bsd, "hsd": hsd, "p_idx": p_idx,
		"hand": Tac.sim_hand(cards, d, hsd),
		"load": Run.bot_plan_load(cards, p_idx, DB.mix_seed(bsd, p_idx, 13), hsd)}


## 한 판 (A 자리 = a)
func _run(a: Dictionary, b: Dictionary, sd: int, pa, pb) -> Dictionary:
	var tp := {"A": pa, "B": pb}
	return RtBattle.make(sd).run(a.cards, a.form, 100, null, b.cards, b.form, 100, null, "", "", [], {"A": "smart", "B": "smart", "plan": tp})


static func _sc(r: Dictionary) -> float:
	return 1.0 if r.win else (0.5 if r.draw else 0.0)


## 자리 바꿔 두 번 —— [X 점수(A 자리), X 점수(B 자리), 결과1, 결과2]
func _pair(x: Dictionary, y: Dictionary, sd: int, px, py) -> Array:
	var r1 := _run(x, y, sd, px, py)
	var r2 := _run(y, x, sd, py, px)
	return [_sc(r1), 1.0 - _sc(r2), r1, r2]


func _add(key: String, pr: Array, base = null) -> void:
	var S: Dictionary = R.S
	if not S.has(key):
		S[key] = {"n": 0.0, "w": 0.0, "flip": 0.0}
	S[key].n += 2
	S[key].w += float(pr[0]) + float(pr[1])
	if base != null:
		for i in 2:
			if not is_equal_approx(float(pr[i]), float(base[i])):
				S[key].flip += 1


## 둘 다 계획이 있는 판 —— 단계 상성 기록 (A 자리 시점)
func _stages(pr: Array) -> void:
	for r in [pr[2], pr[3]]:
		var lg: Array = (r.get("tac", {}) as Dictionary).get("log", [])
		var w := 0
		var l := 0
		for e in lg:
			var o := str(e.A.out)
			if o == "win":
				w += 1
			elif o == "lose":
				l += 1
		var s := _sc(r)
		_acc("stg", w, [1, s])
		_acc("net", w - l, [1, s])


func _game(d: int, rng: RandomNumberGenerator) -> void:
	var pv: float = PV.get(d, 540.0)
	var x := _side(pv, rng, d)
	var y := _side(pv * rng.randf_range(0.95, 1.05), rng, d)
	var sd := rng.randi() % 1000000
	_acc("hand", "%d일차" % (d + 1), [x.hand.size(), 1])
	var none := {}
	# 계획 없음 · 시드만 바꿈
	var b0 := _pair(x, y, sd, none, none)
	_add("base", b0)
	for r in [b0[2], b0[3]]:
		var ln := float(r.get("len", 0.0))
		var L := RtBattle.BATTLE_SEC / 3.0
		R.reach[0] += 1
		R.lens += ln
		R.reach[1] += 1 if ln >= L else 0
		R.reach[2] += 1 if ln >= L * 2.0 else 0
	_add("seed", _pair(x, y, sd + 7777, none, none), b0)
	# 한쪽만 —— X 만 · Y 만 (계획 가진 쪽 점수로 모은다)
	var s1 := _pair(x, y, sd, x.load, none)
	_add("solo", s1, b0)
	var s2 := _pair(x, y, sd, none, y.load)
	_add("solo", [1.0 - s2[0], 1.0 - s2[1]], [1.0 - b0[0], 1.0 - b0[1]])
	# 둘 다 봇 계획
	var bb := _pair(x, y, sd, x.load, y.load)
	_add("both", bb, b0)
	_stages(bb)
	# Y 계획을 안다 —— 받아침 · 무작위 · 일부러 짐
	var yp: Array = y.load.p
	var own: Array = x.load.own
	for k in ["cnt", "rnd", "anti"]:
		var p: Array
		match k:
			"cnt": p = _best(x.hand, yp, 1)
			"anti": p = _best(x.hand, yp, -1)
			_: p = _rand_plan(x.hand, rng)
		var pr := _pair(x, y, sd, {"p": p, "own": own, "perm": []}, y.load)
		_add(k, pr, bb)
		_stages(pr)
	# 예측 —— p1 지난 대전 계획 반복 · p2 보이는 장수(높은 3명) 쏠림 · p3 덱 전체 쏠림
	var guesses := {}
	if d > 0:
		var pi0: int = y.p_idx - 3
		var prev: Dictionary = Run.bot_plan_load(y.cards, pi0, DB.mix_seed(y.bsd, pi0, 13), y.hsd)
		guesses["p1"] = []
		for id in prev.p:
			var fs := Tac.fams(str(id))
			guesses.p1.append(fs[0] if not fs.is_empty() else "")
	var f2 := _top_fam(Room.featured_cards(y.cards))
	guesses["p2"] = [f2, f2, f2]
	var f3 := _top_fam(y.cards)
	guesses["p3"] = [f3, f3, f3]
	for k in guesses:
		var hit := 0
		for i in Tac.STAGES:
			if str(guesses[k][i]) != "" and Tac.fams(str(yp[i])).has(str(guesses[k][i])):
				hit += 1
		_acc("pred", k, [hit, Tac.STAGES])
		# 예측한 계열을 받아치는 계획 —— 진짜 Y 계획과 붙인다
		var tgt := []
		for f in guesses[k]:
			tgt.append(_fam_card(str(f)))
		var pp := _best(x.hand, tgt, 1)
		var pr := _pair(x, y, sd, {"p": pp, "own": own, "perm": []}, y.load)
		_add("pred_" + k, pr, bb)
	# 무작위 계열 맞히기 기준 (다섯 가운데 하나) · 계열 없는 봇 카드 비율
	var rh := 0
	var nofam := 0
	for i in Tac.STAGES:
		if Tac.fams(str(yp[i])).has(Tac.FAMS[rng.randi() % Tac.FAMS.size()]):
			rh += 1
		if Tac.fams(str(yp[i])).is_empty():
			nofam += 1
	_acc("pred", "rnd", [rh, Tac.STAGES])
	_acc("pred", "nofam", [nofam, Tac.STAGES])
	# 등급별 카드 한 장 (한 단계, 상대 없음)
	for g in 4:
		var id := _grade_card(g, rng)
		var st := _stage_for(id, rng)
		var p := ["", "", ""]
		p[st] = id
		var pr := _pair(x, y, sd, {"p": p, "own": [], "perm": []}, none)
		var fl := 0
		for i in 2:
			if not is_equal_approx(float(pr[i]), float(b0[i])):
				fl += 1
		_acc("gr", g, [2, float(pr[0]) + float(pr[1]), fl])


## --card 모드 한 판 —— 카드마다 [판, 점수(상대 없음), 다름, 점수(상대 봇 계획), 다름]. 비교는 같은 판의 계획 없는 X
func _card_game(d: int, g: int, rng: RandomNumberGenerator) -> void:
	var pv: float = PV.get(d, 540.0)
	var x := _side(pv, rng, d)
	var y := _side(pv * rng.randf_range(0.95, 1.05), rng, d)
	var sd := rng.randi() % 1000000
	var none := {}
	var b0 := _pair(x, y, sd, none, none)
	var b1 := _pair(x, y, sd, none, y.load)
	_add("cbase", b0)
	_add("cbase_bot", b1)
	for r in [b0[2], b0[3]]:
		var ln := float(r.get("len", 0.0))
		R.reach[0] += 1
		R.lens += ln
		R.reach[1] += 1 if ln >= RtBattle.BATTLE_SEC / 3.0 else 0
		R.reach[2] += 1 if ln >= RtBattle.BATTLE_SEC / 1.5 else 0
	for id in cards:
		var c := Tac.card(str(id))
		var ld := {"p": ["", "", ""], "own": [], "perm": []}
		if str(c.get("kind", "")) == "passive":
			ld.own = [str(id)]
		else:
			var st: int = int(c.stage) - 1 if c.has("stage") else g % 3
			if bool(c.get("link", false)) and st == 2:
				st = 0
			ld.p[st] = str(id)
		var p0 := _pair(x, y, sd, ld, none)
		var p1 := _pair(x, y, sd, ld, y.load)
		var f0 := 0
		var f1 := 0
		for i in 2:
			f0 += 0 if is_equal_approx(float(p0[i]), float(b0[i])) else 1
			f1 += 0 if is_equal_approx(float(p1[i]), float(b1[i])) else 1
		_acc("card", id, [2, float(p0[0]) + float(p0[1]), f0, float(p1[0]) + float(p1[1]), f1])


## 카드 묶음(덱 · 보이는 장수)의 쏠림이 가장 큰 계열
static func _top_fam(cards: Array) -> String:
	var tags := Tac.deck_tags(cards)
	var best := ""
	var bv := -1.0
	for f in Tac.FAMS:
		var v := Tac.fam_ratio(f, tags)
		if v > bv:
			bv = v
			best = f
	return best


## 그 계열의 첫 카드 (예측 표적용 —— 계열만 본다)
static func _fam_card(f: String) -> String:
	if f == "":
		return ""
	for id in Tac.CARDS:
		if Tac.placeable(id) and Tac.fams(id) == [f] and not Tac.card(id).has("cond"):
			return id
	return ""


## hand 로 tgt 에 맞서는 계획 (모든 조합) —— sign 1 이면 우세 - 열세 최대, -1 이면 최소. 같으면 등급 합 큰 쪽
static func _best(hand: Dictionary, tgt: Array, sign: int) -> Array:
	var ids := hand.keys().filter(func(id): return Tac.placeable(str(id)))
	ids.sort()
	ids.push_front("")
	var best := ["", "", ""]
	var bv := -INF
	for a in ids:
		for b in ids:
			for c in ids:
				var p := [str(a), str(b), str(c)]
				if Tac.clean(p, hand) != p:
					continue
				var w := 0
				var l := 0
				var gs := 0
				for i in 3:
					var o := Tac.preview(p[i], str(tgt[i])) if p[i] != "" and str(tgt[i]) != "" else "draw"
					if o == "win":
						w += 1
					elif o == "lose":
						l += 1
					if p[i] != "":
						gs += int(Tac.card(p[i]).g) + 1
				var v := float(sign * (w - l)) * 100.0 + float(gs)
				if v > bv:
					bv = v
					best = p
	return best


## 손패에서 단계마다 놓을 수 있는 카드를 고르게 무작위로
static func _rand_plan(hand: Dictionary, rng: RandomNumberGenerator) -> Array:
	var ids := hand.keys().filter(func(id): return Tac.placeable(str(id)))
	ids.sort()
	var p := ["", "", ""]
	for i in 3:
		var ok := ids.filter(func(id): return Tac.plan_block(p, hand, i, str(id)) == "")
		if not ok.is_empty():
			p[i] = str(ok[rng.randi() % ok.size()])
	return p


## 등급 g 카드 하나 (켜진 · 놓는 · 조건 없는 · 연환계 아닌)
static func _grade_card(g: int, rng: RandomNumberGenerator) -> String:
	var pool := []
	for id in Tac.CARDS:
		var c: Dictionary = Tac.CARDS[id]
		if Tac.placeable(id) and int(c.g) == g and not c.has("cond") and not bool(c.get("link", false)):
			pool.append(id)
	pool.sort()
	return str(pool[rng.randi() % pool.size()])


static func _stage_for(id: String, rng: RandomNumberGenerator) -> int:
	var c := Tac.card(id)
	if c.has("stage"):
		return int(c.stage) - 1
	return rng.randi() % 3


static func _pct(a, n) -> String:
	return "%.1f%%" % (100.0 * float(a) / float(n)) if float(n) > 0 else "-"


func _report() -> void:
	var S: Dictionary = R.S
	print("\n== 군략 영향 점검 —— 덱 %d쌍 · 걸린 시간 %.0f초 ==" % [int(R.games), float(R.sec)])
	var hk: Array = R.hand.keys()
	hk.sort()
	for k in hk:
		print("손패 %s 평균 %.1f장" % [k, R.hand[k][0] / R.hand[k][1]])
	print("전투 길이 평균 %.1f초 · 2단계(%.0f초~) 닿음 %s · 3단계(%.0f초~) 닿음 %s" % [R.lens / R.reach[0], RtBattle.BATTLE_SEC / 3.0, _pct(R.reach[1], R.reach[0]), RtBattle.BATTLE_SEC / 1.5, _pct(R.reach[2], R.reach[0])])
	var nm := {"base": "계획 없음 대 없음 (X 승률)", "seed": "시드만 바꿈 —— base 와 승패 다름", "solo": "한쪽만 봇 계획 —— 계획 쪽 승률",
		"both": "둘 다 봇 계획 —— X 승률", "cnt": "Y 계획을 알고 받아침", "rnd": "무작위 계획", "anti": "일부러 지는 계획",
		"pred_p1": "예측 받아치기 —— 지난 대전 반복", "pred_p2": "예측 받아치기 —— 보이는 장수 3명 쏠림", "pred_p3": "예측 받아치기 —— 덱 전체 쏠림(안 보임)"}
	print("\n조건 | X 승률 | 비교 대상과 승패 다름 | 판")
	for k in ["base", "seed", "solo", "both", "cnt", "rnd", "anti", "pred_p1", "pred_p2", "pred_p3"]:
		if not S.has(k):
			continue
		var e: Dictionary = S[k]
		var cmp := "base" if k in ["seed", "solo", "both"] else ("both" if k != "base" else "")
		print("%s | %s | %s | %d" % [nm[k], _pct(e.w, e.n), (_pct(e.flip, e.n) + " (대 " + cmp + ")") if cmp != "" else "-", int(e.n)])
	for t in [["stg", "이긴 단계 수"], ["net", "우세 - 열세"]]:
		print("\n%s | A 승률 | 판" % t[1])
		var ks: Array = R[t[0]].keys()
		ks.sort_custom(func(a, b): return int(a) < int(b))
		for k in ks:
			print("%s | %s | %d" % [k, _pct(R[t[0]][k][1], R[t[0]][k][0]), int(R[t[0]][k][0])])
	print("\n예측기 | 단계 계열 적중 | 단계 수")
	var pn := {"p1": "지난 대전 계획 반복 (2일차~)", "p2": "보이는 장수 3명 쏠림 최다 계열", "p3": "덱 전체 쏠림 최다 계열 (화면엔 안 보임)", "rnd": "무작위 계열", "nofam": "(참고) 봇 카드가 계열 없음"}
	for k in ["p1", "p2", "p3", "rnd", "nofam"]:
		if R.pred.has(k):
			print("%s | %s | %d" % [pn[k], _pct(R.pred[k][0], R.pred[k][1]), int(R.pred[k][1])])
	if S.has("base"):
		print("\n등급 (카드 한 장 · 한 단계, 상대 없음) | X 승률 (base %s) | base 와 승패 다름 | 판" % _pct(S.base.w, S.base.n))
	for g in 4:
		if R.gr.has(str(g)):
			var e: Array = R.gr[str(g)]
			print("%s | %s | %s | %d" % [Tac.GRADE_N[g], _pct(e[1], e[0]), _pct(e[2], e[0]), int(e[0])])
	if not R.card.is_empty() and S.has("cbase"):
		var w0: float = S.cbase.w / S.cbase.n
		var w1: float = S.cbase_bot.w / S.cbase_bot.n
		print("\n카드 (한 단계 · 늘 카드는 own) | 등급 | 상대 없음 승률 (차이) | 다름 | 상대 봇 계획 승률 (차이) | 다름 | 판")
		print("(계획 없는 X 승률 —— 상대 없음 %.1f%% · 상대 봇 계획 %.1f%%)" % [w0 * 100.0, w1 * 100.0])
		var ks: Array = R.card.keys()
		ks.sort_custom(func(a, b): return R.card[a][1] / R.card[a][0] > R.card[b][1] / R.card[b][0])
		for k in ks:
			var e: Array = R.card[k]
			print("%s | %s | %s (%+.1f) | %s | %s (%+.1f) | %s | %d" % [k, Tac.grade_name(str(k)), _pct(e[1], e[0]), (e[1] / e[0] - w0) * 100.0, _pct(e[2], e[0]),
				_pct(e[3], e[0]), (e[3] / e[0] - w1) * 100.0, _pct(e[4], e[0]), int(e[0])])
