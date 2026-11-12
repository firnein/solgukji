extends Node
## 사람 플레이 기록 다시 치르기 (11/8 사용자 기록으로 난이도를 다시 맞추려고 만듦)
## 실행: godot --headless --path . res://tests/replay_log.tscn -- --log=기록.jsonl [--k=12 --rows=1 --direct=1 --myth=1.15:1:1]
##   미리 재 볼 값 (없으면 지금 run.gd 값): --late=봇 성장 일차 배율 7개 --skill=하한,상한 --qtr=토벌 병력 배율 7개 --q0=첫 토벌 병력 배율
##     --horde=일차별 잡병 부대 수 7개 --h0=첫 토벌 잡병 부대 수
##   시험: --qprobe=병력 배수들 --qmor=사기 배수들 (토벌) · --probe=봇 PV / 내 PV 들 (대전) · --at=1-1,4-2 그 페이즈만 · --only=quest|pvp|none
##     --check=0 사람 전투 다시 계산 건너뜀 · --men=1 토벌 병사 수 · --rows=1 전투마다
##     --orig=now 기록이 지금 run.gd 값(11/9 2차 이후)으로 남은 것이면 되살리기도 지금 값으로 (OrigRun 은 11/7 값)
## ① 되살리기 —— 기록의 시드로 판을 열고 기록된 명령(징집 · 선택 · 조합 · 편성 …)을 차례로 넣어 사람의 판을 그대로 되살린다.
##    기록에는 장비가 개수만 있어서, 보급까지 기록과 같은 난수로 받게 해 사람이 낀 장비를 찾는다.
##    봇 성장 · 잡병 수 · 토벌 사기 · 병력 배율은 기록 당시 값(OrigRun)으로 돌려 난수 흐름을 맞춘다 (run.gd 값을 바꿔도 되살리기는 그대로).
##    전투마다 내 편성 · 적 편성 · 전투 시드가 기록과 같은지 보고, 같은 시드로 다시 계산한 승패 · 남은 병력을 기록과 견준다.
##    다음 진행(보상 · 봇 벌점)은 기록의 승패로 한다. 어긋난 뒤로는 기록만으로 다시 짠다 (카드 이름 → id, 장비 없음 = 근사).
##    --direct=1 —— 되살리기 없이 모든 전투를 기록만으로 (장비가 결과를 얼마나 바꾸는지 보려고)
## ② 지금 값으로 다시 붙이기 —— 되살린 내 편성(장비 · 진형 · 사기 · 작전 그대로)을 지금 값의 판 k 개에 넣어 같은 페이즈를 치른다:
##    토벌(잡병 · 전투 시드는 새로) 승률 · 남은 병력, 대전(그 페이즈 봇 하나와) 승률, 토너먼트 라운드 승률,
##    페이즈 끝 봇 PV 최고 · 중간과 기록의 내 PV 의 비.

var k_runs := 12
var orig_now := false   # --orig=now 기록이 지금 run.gd 값으로 남은 것이면 (11/9 2차 값 이후 기록) 되살리기도 지금 값으로
var rows := false
var direct := false
var only := "all"       # 지금 값으로 치를 전투 —— all · quest · pvp · none (none 이면 봇 PV 만)
var check := true       # 사람의 전투를 다시 계산해 기록과 견준다 (--check=0 이면 건너뛴다)
var probe: Array = []   # --probe=0.6,0.8,… 대전 시험 —— 봇 PV 를 내 PV 의 이 배수로 두고 사람의 편성과 붙인다
var qprobe: Array = []  # --qprobe=1,1.5,… 토벌 시험 —— 적 병력 배율을 지금 값의 이 배수로
var qmor: Array = [1.0] # --qmor=1,1.3,… 토벌 시험 —— 적 사기를 지금 값의 이 배수로 (200 까지, qprobe 와 엇갈려 모두)
var at: Array = []      # --at=1-1,2-3 그 페이즈 전투만 치른다 (나머지는 봇 벌점만 흘린다)
var men := false        # --men=1 토벌 전장에 그려질 병사 수 (Squad 와 같은 식 —— 탑뷰 GPU 병사, 품질 배율 1)
var name_ids := {}      # "이름|등급|병종" -> [id]
var tour_n := [0, 0, 0]
var tour_w := [0, 0, 0]
var tour_done := false
const WON := {"win": true, "draw": false, "left": 1, "eLeft": 0, "turns": 10, "mvp": null}


## 기록 당시(11/7 저녁 1.0b) 값 —— 사람의 판과 난수 흐름을 맞추려고 봇 성장 · 토벌 적을 그때대로 돌린다
class OrigRun extends Run:
	const LATE := [1.0, 1.0, 1.0, 0.8, 0.62, 0.6, 0.7]
	const HORDE := [5, 5, 7, 11, 11, 11, 11]
	const MORALE := [0.8, 0.68, 0.62, 0.7, 0.62, 0.6, 0.65]
	const TR := [1.0, 0.95, 0.5, 0.48, 0.46, 0.46, 0.49]
	const SKILL := [1.08, 1.45]
	const PV_MUL := 1.08
	const MYTH := 1.3

	func new_game(seed_value := -1) -> void:
		super.new_game(seed_value)
		var t := RandomNumberGenerator.new()      # 봇 실력은 판을 열자마자 뽑는다 —— 같은 시드로 그때 범위에서 다시 뽑는다
		t.seed = rng.seed
		for b in bots:
			b.skill = snappedf(t.randf_range(SKILL[0], SKILL[1]), 0.01)

	func _bot_pv_gain(d: int, p: int) -> float:
		return (24 + d * 4.7 + (4 if p == 2 else 0)) * float(LATE[clampi(d, 0, 6)])

	## 기록 뒤에 바뀐 봇 덱 짜기를 그때대로 —— 봇 병종 섞기(11/8 새벽) 전, 기인이 전설 칸 풀에 있고 초월 PV 범위가 예전 몸(11/9 set_branch 전)
	static var _old_pools := {}
	static var _old_t6 := []

	func _bot_side(pv: float, style: String) -> Dictionary:
		if _old_pools.is_empty():
			for st in ["물리", "지략", "균형"]:
				_old_pools[st] = {}
				for t in DB.TIER:
					var arr := []
					for k in DB.C:
						if DB.C[k].tier != t or DB.is_foe(k): continue
						if st == "물리" and not DB.PHYS_TAGS.has(DB.C[k].tag): continue
						if st == "지략" and not DB.INT_TAGS.has(DB.C[k].tag): continue
						arr.append(k)
					_old_pools[st][t] = arr
			var pvs := []
			for k in DB._branch_src:
				if DB.C[k].tier == 6 and not DB.is_kiin(k): pvs.append(DB._branch_src[k].pv)
			_old_t6 = [pvs.min(), pvs.max()] if not pvs.is_empty() else [DB.TIER[6].lo, DB.TIER[6].hi]
		var keep := [DB.POOLS, DB.TIER[6].lo, DB.TIER[6].hi, DB.bot_mix]
		DB.POOLS = _old_pools; DB.TIER[6].lo = _old_t6[0]; DB.TIER[6].hi = _old_t6[1]; DB.bot_mix = false
		var out := Run.bot_side(pv * PV_MUL * (MYTH if myth_on_board() else 1.0), style, phase_idx(), rng)
		DB.POOLS = keep[0]; DB.TIER[6].lo = keep[1]; DB.TIER[6].hi = keep[2]; DB.bot_mix = keep[3]
		return out

	func quest_horde_n() -> int:
		return int(HORDE[clampi(day, 0, 6)])

	func quest_morale_mul() -> float:
		return float(MORALE[clampi(day, 0, 6)])

	## 11/9 토벌 적 구성(황건 잡병 y1x · y2x)을 바꾸기 전 모양 —— 첫 토벌 편성의 일반 부대 · 1 · 2 등급 잡병 풀
	const ROSTER_11 := ["c22", "c9", "c6", "c0", "c4", "c1", "c5", "c3", "c2"]
	const HORDE_POOL := {1: ["spear", "rogue", "horse", "bow", "occul"], 2: ["c0", "c1", "c6", "c2", "c3", "c4", "c5", "c9"]}

	func start_quest() -> Dictionary:
		var q = quest_roster()
		if q == null:
			var bt0: Dictionary = super.start_quest()
			bt0.b.tr_mul = float(TR[clampi(day, 0, 6)])
			return bt0
		var src: Array = ROSTER_11 if day == 0 and phase == 0 else q.cards
		var cards := DB.auto_place(src, q.form)
		var form: String = q.form
		var hn := quest_horde_n()
		if hn > 0 and DB.FORM.has(DB.HORDE_PFX + form):
			var lo := 9
			for k in src:
				lo = mini(lo, int(DB.C[k].tier))
			var t := clampi(lo - 2, 1, 7)
			var pool: Array = HORDE_POOL.get(t, ["y%d0" % t, "y%d1" % t, "y%d2" % t, "y%d3" % t, "y%d4" % t])
			var out := []
			for i in hn:
				out.append(pool[rng.randi() % pool.size()])
			var fw: Dictionary = DB.D.FRONT_WANT
			out.sort_custom(func(a, b): return fw[DB.C[a].tag] > fw[DB.C[b].tag])
			cards.append_array(out)
			form = DB.HORDE_PFX + form
		var foe := {"cards": cards, "form": form, "morale": int(int(q.get("morale", 100)) * quest_morale_mul()),
			"equip": [], "tac": recommend_tac(cards)[0], "tr_mul": float(TR[clampi(day, 0, 6)])}
		if not DB.quest_trait(day).is_empty(): foe["trait"] = DB.quest_trait(day)
		battle = {"kind": "quest", "a": _my_side(), "b": foe, "seed": rng.randi() % 1000000,
			"title": "토벌 · %s" % quest_name(), "foe": quest_name(), "pv": quest_pv(), "inputs": []}
		return battle


## 지금 값의 판 —— 옵션으로 준 값이 있으면 그것으로 (상수를 바꾸기 전에 미리 재 본다)
class EvalRun extends Run:
	static var late: Array = []
	static var skill: Array = []
	static var qtr: Array = []
	static var q0 := -1.0
	static var h0 := -1               # 첫 토벌 잡병 부대 수
	static var horde: Array = []      # 일차별 잡병 부대 수

	func quest_horde_n() -> int:
		if h0 >= 0 and day == 0 and phase == 0:
			return h0
		if not horde.is_empty():
			return int(horde[clampi(day, 0, 6)])
		return super.quest_horde_n()

	func new_game(seed_value := -1) -> void:
		super.new_game(seed_value)
		if skill.size() == 2:
			var t := RandomNumberGenerator.new()
			t.seed = rng.seed
			for b in bots:
				b.skill = snappedf(t.randf_range(float(skill[0]), float(skill[1])), 0.01)

	func _bot_pv_gain(d: int, p: int) -> float:
		if late.is_empty():
			return super._bot_pv_gain(d, p)
		return (24 + d * 4.7 + (4 if p == 2 else 0)) * float(late[clampi(d, 0, 6)])

	func start_quest() -> Dictionary:
		var bt: Dictionary = super.start_quest()
		if not qtr.is_empty():
			bt.b.tr_mul = float(qtr[clampi(day, 0, 6)])
		if q0 > 0.0 and day == 0 and phase == 0:
			bt.b.tr_mul = q0
		return bt


func _ready() -> void:
	var args := {}
	for s in OS.get_cmdline_user_args():
		var kv := s.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	k_runs = int(args.get("k", "12"))
	if args.has("myth"):      # 11/8 신화 배율 능력치:병력:특기 (예전 값 1.15:1:1 과 견주기)
		var mp: PackedStringArray = str(args.myth).split(":")
		Battle.myth_power = float(mp[0])
		if mp.size() > 1: Battle.myth_troop = float(mp[1])
		if mp.size() > 2: DB.set_myth_trait(float(mp[2]))
	rows = args.get("rows", "0") == "1"
	orig_now = str(args.get("orig", "")) == "now"
	direct = args.get("direct", "0") == "1"
	var floats := func(key: String) -> Array:
		return Array(str(args[key]).split(",")).map(func(x): return float(x)) if args.has(key) else []
	EvalRun.late = floats.call("late")
	# 11/12 토너먼트가 없어져 --tmul(라운드별 상대 PV 배율)은 쓰지 않는다
	EvalRun.skill = floats.call("skill")
	EvalRun.qtr = floats.call("qtr")
	EvalRun.q0 = float(args.get("q0", "-1"))
	EvalRun.h0 = int(args.get("h0", "-1"))
	EvalRun.horde = floats.call("horde")
	only = str(args.get("only", "all"))
	check = args.get("check", "1") == "1"
	probe = floats.call("probe")
	qprobe = floats.call("qprobe")
	if args.has("qmor"):
		qmor = floats.call("qmor")
		if qprobe.is_empty():
			qprobe = [1.0]
	men = args.get("men", "0") == "1"
	if args.has("at"):
		at = Array(str(args.at).split(","))
	if men:
		Squad.gpu = true          # 휴대폰 · PC 모두 탑뷰 GPU 병사 (War3D.setup) —— 1.5배, 품질로 줄이지 않는다 (Settings)
		Squad.gpu_mul = 1.5
		Squad.count_scale = 1.0
	for k in DB.C:
		var key := "%s|%d|%s" % [DB.C[k].name, int(DB.C[k].tier), DB.C[k].tag]
		if not name_ids.has(key):
			name_ids[key] = []
		name_ids[key].append(k)
	var fa := FileAccess.open(str(args.get("log", "")), FileAccess.READ)
	if fa == null:
		print("기록을 열 수 없다 —— --log=경로.jsonl")
		get_tree().quit()
		return
	var evs := []
	while not fa.eof_reached():
		var ln := fa.get_line().strip_edges()
		if ln != "":
			evs.append(JSON.parse_string(ln))
	_replay(evs)
	get_tree().quit()


static func _ck(c) -> String:
	return "%s|%d|%s" % [c[0], int(c[1]), c[2]] if c is Array and c.size() >= 3 else "?"


static func _cks(cards: Array) -> String:
	return ",".join(cards.map(func(c): return _ck(c)))


## 결과의 남은 병력 비 —— 기록(PlayLog.battle_end)과 같은 셈
static func _left(res: Dictionary, camp: String) -> float:
	var l := 0
	var m := 0
	for u in res.get("roster", []):
		if u.camp == camp:
			l += maxi(0, int(u.left))
			m += int(u.max)
	return float(l) / maxf(1.0, float(m))


## 기록의 카드 [이름, 등급, 병종] → id (적 쪽이면 적 전용 카드를 먼저)
func _ids(cards: Array, foe: bool) -> Array:
	var out := []
	for c in cards:
		var ids: Array = name_ids.get(_ck(c), [])
		if ids.is_empty():
			print("  카드를 찾지 못했다: %s" % _ck(c))
			continue
		var pref := ids.filter(func(k): return DB.is_foe(k) == foe)
		out.append(pref[0] if not pref.is_empty() else ids[0])
	return out


## 기록만으로 짠 전투 (장비 없음) —— 토벌 병력 배율은 기록 당시 값
func _direct_bt(e: Dictionary) -> Dictionary:
	var tr := 1.0
	if str(e.kind) == "quest":
		tr = float(Run.QUEST_TR[clampi(int(e.day), 0, 6)]) if orig_now else float(OrigRun.TR[clampi(int(e.day), 0, 6)])
	return {"kind": str(e.kind), "seed": int(e.seed), "title": str(e.title), "foe": "", "inputs": [],
		"a": {"cards": _ids(e.me.cards, false), "form": str(e.form), "morale": int(e.morale), "equip": [], "tac": str(e.tac)},
		"b": {"cards": _ids(e.foe.cards, true), "form": str(e.foe_form), "morale": int(e.foe_morale), "equip": [], "tac": str(e.foe_tac), "tr_mul": tr}}


## 되살린 판에서 전투를 연다 (화면과 같은 순서 —— 토너먼트는 다음 라운드로 넘긴 뒤)
func _start(r: Run, kind: String) -> Dictionary:
	match kind:
		"quest":
			return r.start_quest()
		"pvp":
			return r.start_pvp()
		"tour":      # 11/12 토너먼트가 없어졌다 —— 옛 기록의 토너먼트 전투는 대전으로 되살린다
			return r.start_pvp()
	return {}


## 되살린 전투가 기록과 같은가 —— 다르면 무엇이 다른지
func _diff(bt: Dictionary, e: Dictionary) -> String:
	if int(bt.seed) != int(e.seed):
		return "전투 시드 %d / 기록 %d" % [bt.seed, int(e.seed)]
	var me := PlayLog.side(bt.a.cards)
	var foe := PlayLog.side(bt.b.cards)
	if _cks(me.cards) != _cks(e.me.cards):
		return "내 편성"
	if _cks(foe.cards) != _cks(e.foe.cards):
		return "적 편성"
	if str(bt.a.form) != str(e.form) or int(bt.a.morale) != int(e.morale) or str(bt.a.get("tac", "")) != str(e.tac):
		return "진형 · 사기 · 작전"
	var eq_a: int = bt.a.equip.filter(func(x): return x != null).size()
	var eq_b: int = (bt.b.equip if bt.b.equip else []).filter(func(x): return x != null).size()
	if eq_a != int(e.equip) or eq_b != int(e.foe_equip):
		return "장비 수 %d · %d / 기록 %d · %d" % [eq_a, eq_b, int(e.equip), int(e.foe_equip)]
	if int(bt.b.morale) != int(e.foe_morale) or str(bt.b.form) != str(e.foe_form):
		return "적 사기 · 진형"
	return ""


static func _copy_side(x: Run, r: Run) -> void:
	x.board = r.board.duplicate()
	x.equip = r.equip.duplicate()
	x.form = r.form
	x.tac = r.tac
	x.my_w = r.my_w
	x.my_l = r.my_l
	x.inv = r.inv.duplicate()


static func _bump(d: Dictionary, key: String, v: float) -> void:
	d[key] = float(d.get(key, 0.0)) + v


static func _rec(q: Dictionary, key: String, rs: Dictionary, b: Dictionary) -> void:
	if not q.has(key):
		q[key] = {}
	_bump(q[key], "n", 1.0)
	_bump(q[key], "w", 1.0 if rs.win else 0.0)
	_bump(q[key], "l", _left(rs, "A"))
	_bump(q[key], "fl", _left(rs, "B"))
	_bump(q[key], "pv", float(PlayLog.side(b.b.cards).pv) / maxf(1.0, float(PlayLog.side(b.a.cards).pv)))
	_bump(q[key], "len", float(rs.get("len", 0.0)))


## 전장에 그려질 병사 수 [내 편, 적] —— 화면(War3D.setup)과 같이 결과의 부대마다 Squad 를 만들어 센다
static func _men(rs: Dictionary) -> Array:
	var rng := RandomNumberGenerator.new()
	var n := [0, 0]
	for row in rs.get("roster", []):
		var sq := Squad.new(row, Vector2.ZERO, rng, float(rs.get("lay", 1.0)))
		n[0 if row.camp == "A" else 1] += sq.soldiers.size()
	return n


## ② 지금 값의 판 k 개에 사람의 편성을 넣어 같은 전투를 치른다 (봇 벌점이 같게 흐르도록 토벌은 치르지 않아도 끝낸다)
func _eval(xs: Array, r: Run, e: Dictionary, tag: String, q: Dictionary) -> void:
	var kd := str(e.kind)
	var dk := str(int(e.day) + 1)
	if kd == "tour":
		if tour_done or not (only == "all" or only == "pvp") or (not at.is_empty() and not at.has(tag)):
			return
		tour_done = true
	if kd == "pvp" and not probe.is_empty() and (at.is_empty() or at.has(tag)):
		_probe_pvp(r, e, q)
	for x in xs:
		_copy_side(x, r)
		if kd == "tour":      # 11/12 토너먼트가 없어졌다 —— 옛 기록의 토너먼트는 건너뛴다
			continue
		var b: Dictionary = x.start_quest() if kd == "quest" else x.start_pvp()
		if not (only == "all" or only == kd) or (not at.is_empty() and not at.has(tag)):
			x.finish_battle(WON)
			continue
		var muls: Array = []
		for m in (qprobe if kd == "quest" and not qprobe.is_empty() else [1.0]):
			for mo in (qmor if kd == "quest" else [1.0]):
				muls.append([float(m), float(mo)])
		var rs := {}
		for mm in muls:
			var bb: Dictionary = b
			var key := kd
			if kd == "quest" and not qprobe.is_empty():
				bb = b.duplicate(true)
				bb.b.tr_mul = float(b.b.get("tr_mul", 1.0)) * mm[0]
				bb.b.morale = mini(200, roundi(float(b.b.morale) * mm[1]))
				key = _qkey(mm[0], mm[1])
			rs = Run.simulate(bb, [], Run.policy_for(bb))
			var mn := _men(rs) if men and kd == "quest" else []
			for kk in [tag + key, dk + key]:
				_rec(q, kk, rs, bb)
				if not mn.is_empty():
					_bump(q[kk], "ma", float(mn[0]))
					_bump(q[kk], "mb", float(mn[1]))
					q[kk]["mx"] = maxf(float(q[kk].get("mx", 0.0)), float(mn[0] + mn[1]))
		x.finish_battle(rs)


static func _qkey(m: float, mo: float) -> String:
	return "quest x%.2f" % m if is_equal_approx(mo, 1.0) else "quest x%.2f m%.2f" % [m, mo]


## 대전 시험 —— 봇 PV 를 내 PV 의 몇 배로 두면 사람의 편성이 얼마나 이기는지 (봇 편성은 게임과 같은 Run.bot_side, 성향은 돌려 가며)
func _probe_pvp(r: Run, e: Dictionary, q: Dictionary) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(e.seed)
	var styles: Array = DB.D.STYLES
	var me: Dictionary = r._my_side()
	for m in probe:
		for j in k_runs:
			var pv := float(r.my_pv()) * float(m) * Run.BOT_PV_MUL * (Run.MYTH_BOT_PV if r.myth_on_board() else 1.0)
			var foe := Run.bot_side(pv, str(styles[j % styles.size()]), r.phase_idx(), rng)
			var b := {"kind": "pvp", "a": me, "b": foe, "seed": rng.randi() % 1000000, "title": "", "foe": "", "inputs": []}
			var rs: Dictionary = Run.simulate(b, [], Run.policy_for(b))
			_rec(q, "%spvp r%.2f" % [int(e.day) + 1, m], rs, b)


func _replay(evs: Array) -> void:
	Run.dev_immortal = true
	Run.legacy_rewards = true      # 11/9 이전 규칙(패배 보상 감액)으로 남은 기록 —— 되살린 덱이 기록과 같게
	var t0 := Time.get_ticks_msec()
	var sd := -1
	for e in evs:
		if str(e.ev) == "start":
			sd = str(e.seed).to_int()
			break
	var r: Run = Run.new() if orig_now else OrigRun.new()
	r.new_game(sd)
	var xs := []
	for i in k_runs:
		var x := EvalRun.new()
		x.new_game(90000 + i)
		xs.append(x)
	var desync := ""
	var bt := {}
	var approx := false
	var n_bt := 0
	var same_win := 0
	var ldiff := []
	var q := {}       # "일차-페이즈종류" · "일차종류" -> 집계 (지금 값)
	var lg := {}      # 기록 집계
	var botpv := []   # [일차, 페이즈, 내 PV, 봇 최고 평균, 봇 중간 평균, 기록 봇 최고, 기록 봇 중간]
	for e in evs:
		var tag := "%d-%d" % [int(e.day) + 1, int(e.phase) + 1]
		match str(e.ev):
			"resume":
				if desync == "":
					desync = "%s 이어 하기 (난수 상태는 저장하지 않는다)" % tag
			"act":
				var a: Array = (e.a as Array).duplicate()
				var res = r.command(str(e.m), a)
				if desync == "" and e.has("got"):
					var got: Array = (res if res is Array else []).map(func(k): return PlayLog.card(k))
					if _cks(got) != _cks(e.got):
						desync = "%s %s 결과" % [tag, e.m]
				if desync == "" and e.has("ok") and bool(res) != bool(e.ok):
					desync = "%s %s %s 성공 여부" % [tag, e.m, str(e.a)]
			"page":
				pass      # (옛 토너먼트 대진 짜기 —— 11/12 없어졌다)
			"battle_start":
				bt = _start(r, str(e.kind))
				approx = direct
				if desync == "" and not direct:
					var df := _diff(bt, e)
					if df != "":
						desync = "%s %s %s" % [tag, e.kind, df]
				if desync != "" or direct:
					bt = _direct_bt(e)
					approx = true
				_eval(xs, r, e, tag, q)      # ② 지금 값으로 (토너먼트는 첫 라운드에서 끝까지)
			"battle_end":
				if bt.is_empty():
					continue
				var l0 := float(e.left_ratio)
				var fin: Dictionary = WON.duplicate()
				if check:
					var res: Dictionary = Run.simulate(bt, [], Run.policy_for(bt))
					var l1 := _left(res, "A")
					n_bt += 1
					same_win += 1 if bool(res.win) == bool(e.win) else 0
					ldiff.append(absf(l1 - l0))
					if rows:
						print("  %s %-5s | 기록 %s 남은 %3.0f%% 적 %3.0f%% | 다시 %s 남은 %3.0f%% 적 %3.0f%%%s" % [tag, e.kind,
							"승" if e.win else "패", l0 * 100, float(e.foe_left_ratio) * 100, "승" if res.win else "패", l1 * 100,
							_left(res, "B") * 100, " (근사)" if approx else ""])
					fin = res.duplicate()
				var kd := str(e.kind)
				if kd != "tour":
					for key in [tag + kd, str(int(e.day) + 1) + kd]:
						if not lg.has(key):
							lg[key] = {}
						_bump(lg[key], "n", 1.0)
						_bump(lg[key], "w", 1.0 if e.win else 0.0)
						_bump(lg[key], "l", l0)
				fin.win = bool(e.win)      # 다음 진행은 기록의 승패로
				fin.draw = bool(e.draw)
				r.finish_battle(fin)
				bt = {}
			"phase_end":
				if desync == "" and r.my_pv() != int(e.my_pv):
					desync = "%s 페이즈 끝 내 PV %d / 기록 %d" % [tag, r.my_pv(), int(e.my_pv)]
				var mx := 0.0
				var md := 0.0
				for x in xs:
					var pv: Array = x.bots.map(func(b): return float(b.pv))
					pv.sort()
					mx += pv[pv.size() - 1]
					md += pv[pv.size() / 2]
				mx /= maxf(1.0, xs.size())
				md /= maxf(1.0, xs.size())
				var lb: Array = (e.bot_pv as Array).map(func(v): return float(v))
				lb.sort()
				botpv.append([int(e.day), int(e.phase), float(e.my_pv), mx, md, lb[lb.size() - 1], lb[lb.size() / 2]])
				for x in xs:
					x.advance()
				r.advance()
	# ── 출력 ──
	ldiff.sort()
	var lsum := 0.0
	for v in ldiff:
		lsum += v
	print("① 되살리기 —— 시드 %d · 전투 %d · %s" % [sd, n_bt, ("어긋남: " + desync) if desync != "" else ("기록만으로 (장비 없음)" if direct else "끝까지 기록과 같음")])
	if not ldiff.is_empty():
		print("   승패 같음 %d/%d · 남은 병력 차 평균 %.1f%%p · 가운데 %.1f%%p · 최대 %.1f%%p" % [same_win, n_bt, lsum / ldiff.size() * 100,
			ldiff[ldiff.size() / 2] * 100, ldiff[ldiff.size() - 1] * 100])
	print("② 지금 값 k=%d %s" % [k_runs, _opt_str()])
	var fq: Dictionary = q.get("1-1quest", {})
	if not fq.is_empty():
		print("   첫 토벌(1일 오전) 승 %.0f%% · 남은 병력 %.0f%% · 적 남은 %.0f%% (기록 %s)" % [fq.w / fq.n * 100, fq.l / fq.n * 100, fq.fl / fq.n * 100,
			"승" if float(lg.get("1-1quest", {}).get("w", 0.0)) > 0 else "패"])
	print("   일차 | 토벌 승 · 남은 · 적 남은 (기록 남은) | 대전 승 · 남은 · 적PV/내PV (기록 승) | 그날 끝 내 PV · 봇 최고 · 중간 (내 PV 비) [기록 비]")
	for d in range(1, 8):
		var a: Dictionary = q.get("%dquest" % d, {})
		var b: Dictionary = q.get("%dpvp" % d, {})
		var la: Dictionary = lg.get("%dquest" % d, {})
		var lp: Dictionary = lg.get("%dpvp" % d, {})
		var bp := []
		for row in botpv:
			if row[0] == d - 1:
				bp = row      # 그날 마지막 페이즈 끝
		var s := "   %d일 |" % d
		if not a.is_empty():
			s += " 토벌 %3.0f%% · %3.0f%% · %3.0f%% (%3.0f%%) %2.0f초 |" % [a.w / a.n * 100, a.l / a.n * 100, a.fl / a.n * 100,
				float(la.get("l", 0.0)) / maxf(1.0, float(la.get("n", 0.0))) * 100, a.len / a.n]
			if a.has("ma"):
				s += " 병사 %d+%d 최대 %d |" % [a.ma / a.n, a.mb / a.n, a.mx]
		if not b.is_empty():
			s += " 대전 %3.0f%% · %3.0f%% · %.2f (%.0f%%) |" % [b.w / b.n * 100, b.l / b.n * 100, b.pv / b.n,
				float(lp.get("w", 0.0)) / maxf(1.0, float(lp.get("n", 0.0))) * 100]
		if not bp.is_empty():
			s += " %d-%d 내 %d · 봇 최고 %d (%.2f) · 중간 %d (%.2f) [%.2f · %.2f]" % [bp[0] + 1, bp[1] + 1, bp[2], bp[3], bp[3] / bp[2],
				bp[4], bp[4] / bp[2], bp[5] / bp[2], bp[6] / bp[2]]
		print(s)
	if tour_n[0] > 0:
		print("   토너먼트 8강 %d/%d · 4강 %d/%d · 결승 %d/%d (우승 %.0f%%)" % [tour_w[0], tour_n[0], tour_w[1], tour_n[1], tour_w[2], tour_n[2],
			float(tour_w[2]) / k_runs * 100])
	if not qprobe.is_empty():
		print("   토벌 시험 —— 적 병력 배율 = 지금 값 × %s · 사기 × %s · 칸: 승률 / 남은 병력" % [str(qprobe), str(qmor)])
		var dks := ["1-1", "1-2", "1-3", "2", "3", "4", "5", "6", "7"]
		if not at.is_empty():
			dks = at.duplicate()
		for dk in dks:
			var s := "   %-3s |" % dk
			for m in qprobe:
				for mo in qmor:
					var v: Dictionary = q.get(dk + _qkey(m, mo), {})
					if v.is_empty():
						continue
					s += " ×%.2f%s %3.0f%% / %3.0f%% %2.0f초 |" % [m, "" if is_equal_approx(mo, 1.0) else " 사기×%.2f" % mo, v.w / v.n * 100, v.l / v.n * 100, v.len / v.n]
					if v.has("ma"):
						s += " 병사 %d+%d 최대 %d |" % [v.ma / v.n, v.mb / v.n, v.mx]
			print(s)
	if not probe.is_empty():
		print("   대전 시험 —— 봇 PV = 내 PV × %s (게임처럼 ×%.2f, 신화면 ×%.1f 더) · 칸: 승률 / 남은 병력 · 적PV/내 편성 PV" % [str(probe), Run.BOT_PV_MUL, Run.MYTH_BOT_PV])
		for d in range(1, 8):
			var s := "   %d일 |" % d
			for m in probe:
				var v: Dictionary = q.get("%dpvp r%.2f" % [d, m], {})
				if not v.is_empty():
					s += " ×%.2f %3.0f%% / %3.0f%% · %.2f |" % [m, v.w / v.n * 100, v.l / v.n * 100, v.pv / v.n]
			print(s)
	if rows:
		var ks: Array = q.keys().filter(func(key): return str(key).contains("-"))
		ks.sort()
		for key in ks:
			var v: Dictionary = q[key]
			print("   %s 승 %3.0f%% · 남은 %3.0f%% · 적 남은 %3.0f%%" % [key, v.w / v.n * 100, v.l / v.n * 100, v.fl / v.n * 100])
	print("   걸린 시간 %.1f초" % ((Time.get_ticks_msec() - t0) / 1000.0))


func _opt_str() -> String:
	var s := []
	if not EvalRun.late.is_empty():
		s.append("late=" + str(EvalRun.late))
	if not EvalRun.skill.is_empty():
		s.append("skill=" + str(EvalRun.skill))
	if not EvalRun.qtr.is_empty():
		s.append("qtr=" + str(EvalRun.qtr))
	if EvalRun.q0 > 0:
		s.append("q0=%.2f" % EvalRun.q0)
	if EvalRun.h0 >= 0:
		s.append("h0=%d" % EvalRun.h0)
	if not EvalRun.horde.is_empty():
		s.append("horde=" + str(EvalRun.horde))
	return "(run.gd 그대로)" if s.is_empty() else " ".join(s)
