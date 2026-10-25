class_name Run
extends RefCounted
## 한 판의 진행 상태 —— 원본 HTML 의 S 와 진행 규칙(4. 상태 · 5. 조합·환전 · 8. 진행)을 옮겼다.
## 화면과 떨어져 있어 헤드리스로 점검할 수 있다. 저장은 to_dict / from_dict (user://save.json).
##
## 원본과 다른 점 —— 전투 결과는 전투를 시작할 때가 아니라 끝날 때 반영한다.
## 전투 중에 고유기·군령을 넣으면 결과가 바뀌기 때문이다. 시작할 때 전투 재료(시드·덱)를
## battle 에 적어 두고, 끝나면 finish_battle(res) 로 보상을 준다. 전투 도중 앱이 꺼지면
## 다음에 열 때 적어 둔 재료와 입력으로 다시 계산해 마무리한다(resolve_pending).

const PHASE_N := ["오전", "오후", "저녁"]
const DAYNAME := ["월", "화", "수", "목", "금", "토", "일"]
const ROUNDNM := ["8강", "4강", "결승"]
const FREE_TIER_CAP := 5      # 무상으로 주는 패의 천장. 초월 이상은 조합으로만 오른다
const STRIKE_MAX := 4         # 토벌 실패 경고 한도 —— 3일차부터 닿으면 멸망
const TRADE_PER_PHASE := 5
const SKILL_LO := 0.98        # 봇 실력 계수
const SKILL_HI := 1.38
const SAVE_PATH := "user://save.json"

var rng := RandomNumberGenerator.new()
var day := 0
var phase := 0
var inv := {}                 # 카드 id -> 장수 (손패)
var bag := {}                 # 아이템 id -> 개수
var board := []               # 9칸 —— 카드 id 또는 null
var equip := []               # 9칸 —— 아이템 id 또는 null
var form := "eorin"
var drawn := false
var picked := false
var granted := false
var quest_done := false
var pvp_done := false
var pending_picks := []       # [{t, n, src}]
var trades := TRADE_PER_PHASE
var strikes := 0
var last_draw := []
var last_item = null
var last_spoil = null         # {n, src} —— 방금 받은 기본패
var tour = null               # 최종 토너먼트
var my_w := 0
var my_l := 0
var news := []                # [{who, unit}]
var bots := []
var over = null               # {win, msg}
var battle = null             # 진행 중인 전투 {kind, p(재료), inputs, ...} —— 끝나면 null
var last_result = null        # 마지막 전투 요약 —— 전투 탭에 다시 보여 준다
var toasts := []              # 화면이 가져가 띄우는 알림 [text, kind]
var pick_queue := []          # 쓰는 중인 선택권 [{t, n}] —— 하나씩 pick(k) 로 받는다 (끄고 켜도 남는다)
var mp := false               # 여럿이 하는 판 —— 봇(bots)은 다른 자리의 거울이라 서버가 채운다


func new_game(seed_value := -1) -> void:
	if seed_value >= 0:
		rng.seed = seed_value
	else:
		rng.randomize()
	day = 0
	phase = 0
	inv = {}
	bag = {}
	board = _nine()
	equip = _nine()
	form = "eorin"
	drawn = false
	picked = false
	granted = false
	quest_done = false
	pvp_done = false
	pending_picks = []
	trades = TRADE_PER_PHASE
	strikes = 0
	last_draw = []
	last_item = null
	last_spoil = null
	tour = null
	my_w = 0
	my_l = 0
	news = []
	over = null
	battle = null
	last_result = null
	bots = []
	for i in DB.D.BOTNAME.size():
		var b: Array = DB.D.BOTNAME[i]
		bots.append({"name": b[0], "epi": b[1], "fac": b[2], "style": DB.D.STYLES[i], "pv": 0.0,
			"w": 0, "l": 0, "strikes": 0, "top": 0, "skill": snappedf(rng.randf_range(SKILL_LO, SKILL_HI), 0.01)})
	give("spear", 3)
	give("horse", 3)
	give("bow", 2)
	give("strat", 2)
	gain_item()


func _nine() -> Array:
	var a := []
	a.resize(9)
	return a


# ───────── 카드 ─────────

func give(k: String, n := 1) -> void:
	inv[k] = inv.get(k, 0) + n


func on_board(k: String) -> int:
	return board.count(k)


func have(k: String) -> int:
	return inv.get(k, 0) + on_board(k)


## 손패부터 빼고, 모자라면 편성판에서 내린다 (편성판 카드도 재료로 쓰인다)
func take(k: String, n := 1) -> void:
	var need := n
	var from_inv: int = mini(need, inv.get(k, 0))
	if from_inv > 0:
		inv[k] -= from_inv
		need -= from_inv
		if inv[k] <= 0:
			inv.erase(k)
	for i in 9:
		if need <= 0:
			break
		if board[i] == k:
			board[i] = null
			equip[i] = null
			need -= 1


func pool() -> Dictionary:
	var o := inv.duplicate()
	for k in board:
		if k != null:
			o[k] = o.get(k, 0) + 1
	return o


func my_pv() -> int:
	var s := 0
	var p := pool()
	for k in p:
		s += DB.C[k].pv * p[k]
	return s


func board_power() -> int:
	var s := 0
	for k in board:
		if k != null:
			s += DB.C[k].tr
	return s


func placed() -> int:
	return board.filter(func(k): return k != null).size()


func my_morale() -> int:
	return roundi(minf(130, 100 + my_w * 3 - my_l * 4))


func rank() -> int:
	var mine := my_pv()
	var n := 1
	for b in bots:
		if b.pv > mine:
			n += 1
	return n


func phase_idx() -> int:
	return day * 3 + phase


static func sort_cards(ks: Array) -> Array:
	var order: Array = DB.D.TAGORDER
	var out := ks.duplicate()
	out.sort_custom(func(a, b):
		if DB.C[a].tier != DB.C[b].tier:
			return DB.C[a].tier > DB.C[b].tier
		var ta := order.find(DB.C[a].tag)
		var tb := order.find(DB.C[b].tag)
		if ta != tb:
			return ta < tb
		return DB.C[a].name < DB.C[b].name)
	return out


static func by_tier_tag(t: int, tag: String) -> Array:
	return DB.by_tier(t).filter(func(k): return DB.C[k].tag == tag)


# ───────── 아이템 ─────────

func gain_item() -> String:
	var p := phase_idx()
	var grade := "일반"
	if DB.D.UNIQUE_PHASES.has(p):
		grade = "유니크"           # 정해진 아침에만 확정 지급
	else:
		var tbl: Dictionary = {}
		for d in DB.D.DROP:
			if p <= int(d.upto):
				tbl = d.w
				break
		var tot := 0.0
		for g in tbl:
			tot += tbl[g]
		var r := rng.randf() * tot
		for g in tbl:
			r -= tbl[g]
			if r <= 0:
				grade = g
				break
	var cand: Array = DB.IT.keys().filter(func(k): return DB.IT[k].grade == grade)
	# 보급은 지금 세운 군세에 맞는 물건이 온다. 유니크는 특히 그렇다
	var tags := {}
	for k in board:
		if k != null:
			tags[DB.C[k].tag] = true
	for k in inv:
		if DB.C[k].tier >= 5:
			tags[DB.C[k].tag] = true
	if not tags.is_empty():
		var fit := cand.filter(func(k): return tags.has(DB.IT[k].tag))
		if not fit.is_empty() and (grade == "유니크" or rng.randf() < 0.7):
			cand = fit
	var id: String = cand[rng.randi() % cand.size()]
	bag[id] = bag.get(id, 0) + 1
	last_item = id
	return id


func bag_keys() -> Array:
	var g := ["유니크", "레어", "매직", "일반"]
	var order: Array = DB.D.TAGORDER
	var ks: Array = bag.keys()
	ks.sort_custom(func(a, b):
		var ga := g.find(DB.IT[a].grade)
		var gb := g.find(DB.IT[b].grade)
		if ga != gb:
			return ga < gb
		return order.find(DB.IT[a].tag) < order.find(DB.IT[b].tag))
	return ks


## 신화 장수는 조합 때 쓴 유니크 아이템을 영구히 장착한다
static func innate_item(k: String):
	var need: String = DB.C[k].need
	return DB.ITEM_BY_NAME.get(need) if need != "" else null


func can_equip(k, item_id) -> bool:
	if k == null or item_id == null:
		return false
	if innate_item(k) != null:
		return false
	return DB.IT[item_id].tag == DB.C[k].tag


func item_of_slot(i: int):
	var k = board[i]
	if k == null:
		return null
	var inn = innate_item(k)
	return inn if inn != null else equip[i]


func equipped_count() -> int:
	return equip.filter(func(e): return e != null).size()


## 가방에서 병종이 맞는 최상 등급을 고른다. 유니크 재료는 장착하지 않고 조합용으로 남긴다
func recommend_items() -> Array:
	var used := {}
	var eq := _nine()
	var order := ["유니크", "레어", "매직", "일반"]
	var slots := []
	for i in 9:
		if board[i] != null and DB.C[board[i]].kind != "myth":
			slots.append(i)
	slots.sort_custom(func(a, b): return DB.C[board[a]].tier > DB.C[board[b]].tier)
	for i in slots:
		var k: String = board[i]
		var cand: Array = bag.keys().filter(func(it): return DB.IT[it].tag == DB.C[k].tag \
			and bag[it] - used.get(it, 0) > 0 and DB.IT[it].use != "myth")
		if cand.is_empty():
			continue
		cand.sort_custom(func(a, b): return order.find(DB.IT[a].grade) < order.find(DB.IT[b].grade))
		eq[i] = cand[0]
		used[cand[0]] = used.get(cand[0], 0) + 1
	return eq


# ───────── 조합 · 환전 ─────────

static func mat_count(mats: Array) -> Dictionary:
	var m := {}
	for x in mats:
		m[x] = m.get(x, 0) + 1
	return m


static func need_item(out: String):
	return innate_item(out)


func can_forge(out: String) -> bool:
	if not DB.RECOF.has(out):
		return false
	var m := mat_count(DB.RECOF[out])
	for k in m:
		if have(k) < m[k]:
			return false
	var ni = need_item(out)
	if ni != null and bag.get(ni, 0) <= 0:
		return false
	return true


func forge(out: String) -> bool:
	if not can_forge(out):
		return false
	var m := mat_count(DB.RECOF[out])
	for k in m:
		take(k, m[k])
	var ni = need_item(out)
	if ni != null:
		bag[ni] -= 1
		if bag[ni] <= 0:
			bag.erase(ni)
	give(out)
	return true


## 재료 부족 수 (아이템 포함)
func miss_count(out: String) -> int:
	var m := mat_count(DB.RECOF.get(out, []))
	var miss := 0
	for q in m:
		miss += maxi(0, m[q] - have(q))
	var ni = need_item(out)
	if ni != null and bag.get(ni, 0) <= 0:
		miss += 1
	return miss


## 연관 조합 —— 지금 손패로 얼마나 가까운지 순으로
func near_recipes(limit := 12) -> Array:
	var out := []
	for r in DB.D.RECDEF:
		var o: String = r[0]
		var m := mat_count(r[1])
		var short := 0
		var tot := 0
		for k in m:
			tot += m[k]
			short += maxi(0, m[k] - have(k))
		if short == tot:
			continue
		var ni = need_item(o)
		out.append({"out": o, "short": short, "tot": tot, "no_item": ni != null and bag.get(ni, 0) <= 0})
	out.sort_custom(func(a, b):
		if a.short != b.short:
			return a.short < b.short
		return DB.C[a.out].tier > DB.C[b.out].tier)
	return out.slice(0, limit)


## 이 카드를 재료로 쓰는 조합들
static func used_in(k: String) -> Array:
	var out := []
	for r in DB.D.RECDEF:
		if r[1].has(k):
			out.append(r[0])
	return out


func tier_stock(t: int) -> Dictionary:
	var p := pool()
	var o := {}
	for k in sort_cards(p.keys()):
		if DB.C[k].tier == t:
			o[k] = p[k]
	return o


func trade(from: String, want: String) -> bool:
	if trades <= 0 or DB.C[from].tier != DB.C[want].tier or have(from) < 1:
		return false
	take(from)
	give(want)
	trades -= 1
	return true


# ───────── 편성 ─────────

func place(i: int, k: String) -> void:
	if i < 0 or i > 8 or inv.get(k, 0) <= 0:
		return
	var prev = board[i]
	board[i] = null
	if prev != null:
		give(prev)
	take(k)
	board[i] = k
	if equip[i] != null and not can_equip(k, equip[i]):
		equip[i] = null


func unplace(i: int) -> void:
	if i < 0 or i > 8:
		return
	if board[i] != null:
		give(board[i])
	board[i] = null
	equip[i] = null


func swap(i: int, j: int) -> void:
	if i < 0 or i > 8 or j < 0 or j > 8:
		return
	var k = board[i]
	board[i] = board[j]
	board[j] = k
	var e = equip[i]
	equip[i] = equip[j]
	equip[j] = e


## 병력 큰 순으로 9장을 골라 진형에 앉히고 아이템을 붙인다
func auto_deploy() -> void:
	var all := []
	for k in inv:
		for i in inv[k]:
			all.append(k)
	for k in board:
		if k != null:
			all.append(k)
	all.sort_custom(func(a, b): return DB.C[a].tr > DB.C[b].tr)
	inv = {}
	for k in all.slice(9):
		give(k)
	board = DB.auto_place(all.slice(0, 9), form)
	equip = recommend_items()


func clear_board() -> void:
	for i in 9:
		unplace(i)


## 진형을 바꾸면 같은 칸 번호에 그대로 둔다 (원본과 같다)
func set_form(f: String) -> void:
	if DB.FORM.has(f):
		form = f


## 아이템 장착 —— id 가 null 이면 해제
func set_equip(i: int, id) -> void:
	if i < 0 or i > 8 or board[i] == null:
		return
	if id == null:
		equip[i] = null
		return
	var used := 0
	for j in 9:
		if j != i and equip[j] == id:
			used += 1
	if can_equip(board[i], id) and bag.get(id, 0) - used > 0:
		equip[i] = id


# ───────── 징집 ─────────

func draws_n() -> int:
	return int(DB.D.DRAWS[day])


func do_draw() -> Array:
	if drawn:
		return []
	var got := []
	for i in draws_n():
		var k: String = DB.BASE[rng.randi() % DB.BASE.size()]
		give(k)
		got.append(k)
	last_draw = got
	drawn = true
	return got


func pick_list() -> Array:
	var l: Array
	if day == 6:
		l = [{"t": 6, "n": 1}] if phase == 0 else ([{"t": 5, "n": 1}] if phase == 1 else [{"t": 6, "n": 1}, {"t": 4, "n": 2}])
	else:
		l = DB.D.PICKS[day]
	return l.map(func(p): return {"t": mini(FREE_TIER_CAP, int(p.t)), "n": int(p.n)})


func random_grant() -> Array:
	if granted:
		return []
	var got := []
	for p in DB.D.RANDOM_GRANT[day]:
		var t := mini(FREE_TIER_CAP, int(p.t))
		var src: Array = DB.by_tier(t).filter(func(x): return DB.C[x].tier < 8)
		for i in int(p.n):
			var k: String = src[rng.randi() % src.size()]
			give(k)
			got.append(k)
	granted = true
	return got


func grant_list() -> Array:
	return DB.D.RANDOM_GRANT[day]


# ───────── 진행 ─────────

func _bot_pv_gain(d: int, p: int) -> float:
	return 22 + d * 4 + (4 if p == 2 else 0)


## 봇 등용 소식 —— 실제로 편성 가능한 최고 등급이 올라갔을 때만 알린다
func bot_news() -> Array:
	var out := []
	for b in bots:
		var bb := DB.gen_board(b.pv, b.style, rng)
		var top := 0
		for k in bb.cards:
			top = maxi(top, DB.C[k].tier)
		if top < 6 or top <= b.top:
			continue
		b.top = top
		var pl: Array = DB.POOLS[b.style].get(top, []).filter(func(k): return DB.C[k].tier < 8)
		if pl.is_empty():
			continue
		out.append({"who": b.name, "unit": pl[rng.randi() % pl.size()]})
	return out


func advance() -> void:
	phase += 1
	if phase > 2:
		phase = 0
		day += 1
	drawn = false
	picked = false
	granted = false
	quest_done = false
	pvp_done = false
	last_result = null
	trades = TRADE_PER_PHASE
	last_draw = []
	last_spoil = null
	if day > 6:
		over = {"win": true, "msg": "일주일을 살아남았다"}
		day = 6
		return
	var it := gain_item()
	if DB.IT[it].grade == "유니크":
		toasts.append(["%s 유니크 보급 도착 · %s" % [DB.IT[it].name, DB.IT[it].tag], "gold"])
	if mp:
		return
	for b in bots:
		b.pv += _bot_pv_gain(day, phase) * b.skill * rng.randf_range(0.9, 1.1)
	for n in bot_news():
		news.push_front(n)
		toasts.append(["%s가 %s을(를) 등용했습니다" % [n.who, DB.C[n.unit].name], "news"])
	news = news.slice(0, 12)


func is_tour_phase() -> bool:
	return day == 6 and phase == 2


func can_next() -> bool:
	return over == null and battle == null and not is_tour_phase() and quest_done and pvp_done


# ───────── 전투 —— 시작에 재료를 적고, 끝에 보상 ─────────

func _my_side() -> Dictionary:
	return {"cards": board.duplicate(), "form": form, "morale": my_morale(), "equip": equip.duplicate()}


func _bot_side(pv: float, style: String) -> Dictionary:
	var eb := DB.gen_board(pv, style, rng)
	return {"cards": DB.auto_place(eb.cards, eb.form), "form": eb.form, "morale": 100, "equip": null}


func quest_name() -> String:
	return DB.D.QUESTS[day][phase]


func quest_pv() -> int:
	return int(DB.D.QPV[day][phase])


func start_quest() -> Dictionary:
	var pv := quest_pv()
	var styles := ["물리", "지략", "균형"]
	var foe := _bot_side(pv, styles[rng.randi() % 3])
	battle = {"kind": "quest", "a": _my_side(), "b": foe, "seed": rng.randi() % 1000000,
		"title": "토벌 · %s" % quest_name(), "foe": quest_name(), "pv": pv, "inputs": [], "foe_ai": "auto"}
	return battle


func start_pvp() -> Dictionary:
	var bi := rng.randi() % bots.size()
	var b: Dictionary = bots[bi]
	battle = {"kind": "pvp", "a": _my_side(), "b": _bot_side(b.pv, b.style), "seed": rng.randi() % 1000000,
		"title": "대전 · %s" % b.name, "foe": b.name, "bot": bi, "inputs": []}
	return battle


func start_tour() -> Dictionary:
	if tour == null:
		init_tour()
	var m: Dictionary = tour.res[tour.round][tour.my_match]
	var foe: Dictionary = m.b if m.a.me else m.a
	var y := _tour_board(foe)
	battle = {"kind": "tour", "a": _my_side(), "b": y, "seed": rng.randi() % 1000000,
		"title": "%s · %s" % [ROUNDNM[tour.round], foe.name], "foe": foe.name, "inputs": []}
	return battle


## 상대 AI —— 대전·토너먼트 상대는 영리(비동기 상대 AI), 토벌의 적은 자동
static func policy_for(bt: Dictionary, mine: String) -> Dictionary:
	if bt.has("pol"):
		return bt.pol
	return {"A": mine, "B": bt.get("foe_ai", "smart")}


## 진영 뒤집기 —— 사람끼리 대전은 한 번만 계산하고, B 쪽 사람에게는 A·B 를 바꾼 결과를 준다
## (화면은 늘 A 가 나). 부대 키 "A3"↔"B3", camp·c·pts·정책·승패·잔존을 바꾸고 기록의 "적 " 을 뗀다.
static func flip_res(res: Dictionary) -> Dictionary:
	var out: Dictionary = _flip(res)
	out.win = not res.win and not res.draw
	out.left = res.eLeft
	out.eLeft = res.left
	out.aForm = res.bForm
	out.bForm = res.aForm
	out.aSyn = _flip(res.bSyn)
	out.bSyn = _flip(res.aSyn)
	out.mvp = null
	return out


static func _flip(v):
	match typeof(v):
		TYPE_DICTIONARY:
			var o := {}
			for k in v:
				var nk = k
				if k is String and (k == "A" or k == "B"):
					nk = "B" if k == "A" else "A"
				if k == "pts" and v[k] is Array:
					o[nk] = [v[k][1], v[k][0]]
				elif (k == "camp" or k == "c") and v[k] is String and (v[k] == "A" or v[k] == "B"):
					o[nk] = "B" if v[k] == "A" else "A"
				elif k == "t" and v[k] is String:
					o[nk] = v[k].replace("적 ", "")
				else:
					o[nk] = _flip(v[k])
			return o
		TYPE_ARRAY:
			return v.map(func(x): return _flip(x))
		TYPE_STRING:
			if v.length() >= 2 and (v[0] == "A" or v[0] == "B") and v.substr(1).is_valid_int():
				return ("B" if v[0] == "A" else "A") + v.substr(1)
			return v
	return v


## 전투 계산 —— 화면(BattleView)과 같은 식. 입력과 정책을 받는다
static func simulate(bt: Dictionary, inputs: Array, policy: Dictionary) -> Dictionary:
	return Battle.new(bt.seed).run(bt.a.cards, bt.a.form, bt.a.morale, bt.a.equip,
		bt.b.cards, bt.b.form, bt.b.morale, bt.b.equip, bt.title, bt.foe, inputs, policy)


## 전투가 끝났다 —— 보상·경고·토너먼트 진행
func finish_battle(res: Dictionary) -> void:
	if battle == null:
		return
	var bt: Dictionary = battle
	battle = null
	last_result = {"title": bt.title, "win": res.win, "draw": res.draw, "left": res.left, "eLeft": res.eLeft,
		"turns": res.turns, "mvp": res.mvp.name if res.mvp else "", "kind": bt.kind}
	match bt.kind:
		"quest":
			quest_done = true
			if res.win:
				for p in DB.D.QUEST_REWARD[day]:
					pending_picks.append({"t": int(p.t), "n": int(p.n), "src": "토벌 · " + quest_name()})
				var n := int(DB.D.QUEST_BASE[day])
				for i in n:
					give(DB.BASE[rng.randi() % DB.BASE.size()])
				last_spoil = {"n": n, "src": "토벌 · " + quest_name()}
			else:
				strikes += 1       # 어느 페이즈든 토벌 실패는 경고로 쌓인다
				if strikes >= STRIKE_MAX and day >= 2:
					over = {"win": false, "msg": "%s 실패 — %d번의 패배로 세력이 멸망했다" % [quest_name(), STRIKE_MAX]}
			if not mp:
				for b in bots:
					if b.pv < bt.pv * 0.95 * rng.randf_range(0.92, 1.08):
						b.strikes += 1
						b.pv *= 0.94
		"pvp":
			pvp_done = true
			var nb := int(DB.D.PVP_BASE.win if res.win else DB.D.PVP_BASE.lose)
			for i in nb:
				give(DB.BASE[rng.randi() % DB.BASE.size()])
			last_spoil = {"n": nb, "src": "대전 · " + bt.foe}
			var b = bots[bt.bot] if bt.has("bot") else null      # 여럿이 하는 판은 서버가 상대 전적을 센다
			if res.win:
				my_w += 1
				if b: b.l += 1
				pending_picks.append({"t": 4 if day >= 3 else 3, "n": 1, "src": "대전 승리 · " + bt.foe})
			else:
				my_l += 1
				if b: b.w += 1
				pending_picks.append({"t": 3 if day >= 3 else 2, "n": 1, "src": "대전 패배 · " + bt.foe})
		"tour":
			var r: int = tour.round
			var ms: Array = tour.res[r]
			var m: Dictionary = ms[tour.my_match]
			var me: Dictionary = m.a if m.a.me else m.b
			var foe: Dictionary = m.b if m.a.me else m.a
			m.w = me.name if res.win else foe.name
			if not res.win:
				over = {"win": false, "msg": "%s에서 %s에게 패했다 — 최종 %s" % [ROUNDNM[r], foe.name, tour_rank()]}
			elif r == 2:
				over = {"win": true, "msg": "%s을(를) 꺾고 천하를 얻었다" % foe.name}
			else:
				my_w += 1
				var nxt := []
				for x in ms:
					nxt.append(x.a if x.w == x.a.name else x.b)
				tour.next = nxt


## 전투 도중 꺼졌던 판 —— 적어 둔 입력으로 다시 계산해 마무리한다 (남은 부분은 자동 전투)
func resolve_pending() -> Dictionary:
	if battle == null:
		return {}
	var inputs: Array = battle.inputs.duplicate(true)
	var res := simulate(battle, inputs, policy_for(battle, "auto"))
	finish_battle(res)
	return res


# ───────── 8인 토너먼트 ─────────

func init_tour() -> void:
	var ps := [{"me": true, "name": "나", "pv": my_pv(), "style": "균형"}]
	for b in bots:
		ps.append({"me": false, "name": b.name, "pv": roundi(b.pv), "style": b.style})
	ps.sort_custom(func(a, b): return a.pv > b.pv)
	var seed_order := [0, 7, 3, 4, 1, 6, 2, 5]
	var lst := []
	for i in seed_order:
		lst.append(ps[i])
	tour = {"round": 0, "list": lst, "res": [null, null, null], "my_match": -1, "next": null}
	_prep_round()


func _tour_board(pl: Dictionary) -> Dictionary:
	if pl.me:
		return _my_side()
	return _bot_side(pl.pv, pl.style)


func _sim_match(a: Dictionary, b: Dictionary) -> String:
	var x := _tour_board(a)
	var y := _tour_board(b)
	var r := Battle.new(rng.randi() % 1000000).run(x.cards, x.form, x.morale, x.equip, y.cards, y.form, y.morale, y.equip)
	return a.name if r.win else b.name


func _prep_round() -> void:
	var L: Array = tour.list
	var mi := -1
	for i in L.size():
		if L[i].me:
			mi = i
	tour.my_match = mi / 2 if mi >= 0 else -1
	var ms := []
	for m in L.size() / 2:
		var a: Dictionary = L[m * 2]
		var b: Dictionary = L[m * 2 + 1]
		ms.append({"a": a, "b": b, "w": null if m == tour.my_match else _sim_match(a, b)})
	tour.res[tour.round] = ms


func tour_rank() -> String:
	return ["5~8위", "3~4위", "2위"][tour.round]


func tour_advance() -> void:
	tour.list = tour.next
	tour.next = null
	tour.round += 1
	last_result = null
	_prep_round()


func tour_foe() -> Dictionary:
	if tour == null:
		return {}
	var m: Dictionary = tour.res[tour.round][tour.my_match]
	return m.b if m.a.me else m.a


# ───────── 선택권 ─────────

## 선택권을 꺼낸다 —— src "phase"(이번 페이즈 선택권) 또는 "pending"(전투 보상 i 번째)
func begin_picks(src: String, i := -1) -> void:
	if src == "phase":
		if picked:
			return
		picked = true
		pick_queue.append_array(pick_list())
	elif src == "pending" and i >= 0 and i < pending_picks.size():
		var p: Dictionary = pending_picks.pop_at(i)
		pick_queue.append({"t": mini(FREE_TIER_CAP, int(p.t)), "n": int(p.n)})


## 선택권 하나 —— 맨 앞 선택권의 등급 카드만 받는다
func pick(k: String) -> bool:
	if pick_queue.is_empty() or not DB.C.has(k) or DB.C[k].tier != int(pick_queue[0].t):
		return false
	give(k)
	pick_queue[0].n = int(pick_queue[0].n) - 1
	if pick_queue[0].n <= 0:
		pick_queue.pop_front()
	return true


## 서버가 받아 주는 명령 —— 이름 -> 인자 수
const COMMANDS := {"do_draw": 0, "random_grant": 0, "begin_picks": 2, "pick": 1, "forge": 1, "trade": 2,
	"place": 2, "unplace": 1, "swap": 2, "set_form": 1, "auto_deploy": 0, "clear_board": 0, "set_equip": 2}


func command(m: String, a: Array):
	if not COMMANDS.has(m) or a.size() != COMMANDS[m]:
		return null
	for j in a.size():
		if a[j] is float:
			a[j] = int(a[j])      # JSON 숫자는 float 로 온다 —— 칸 번호 등
	return callv(m, a)


# ───────── 저장 ─────────

const _KEYS := ["day", "phase", "inv", "bag", "board", "equip", "form", "drawn", "picked", "granted",
	"quest_done", "pvp_done", "pending_picks", "trades", "strikes", "last_draw", "last_item", "last_spoil",
	"tour", "my_w", "my_l", "news", "bots", "over", "battle", "last_result", "pick_queue", "mp"]


func to_dict() -> Dictionary:
	var d := {"v": 1, "rng_seed": str(rng.seed), "rng_state": str(rng.state)}
	for k in _KEYS:
		d[k] = get(k)
	return d


func from_dict(d: Dictionary) -> void:
	for k in _KEYS:
		if d.has(k):
			set(k, d[k])
	rng.seed = int(d.get("rng_seed", "0"))
	rng.state = int(d.get("rng_state", "0"))
	# JSON 은 숫자를 float 로 돌려준다 —— 개수·번호는 int 로 되돌린다
	for dict in [inv, bag]:
		for k in dict:
			dict[k] = int(dict[k])
	for k in ["day", "phase", "trades", "strikes", "my_w", "my_l"]:
		set(k, int(get(k)))
	for p in pending_picks + pick_queue:
		p.t = int(p.t)
		p.n = int(p.n)
	for b in bots:
		for k in ["w", "l", "strikes", "top"]:
			b[k] = int(b[k])
	if battle != null:
		battle.seed = int(battle.seed)
		if battle.has("bot"):
			battle.bot = int(battle.bot)
		for inp in battle.inputs:
			inp[0] = int(inp[0])
	if tour != null:
		tour.round = int(tour.round)
		tour.my_match = int(tour.my_match)


func save() -> void:
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(to_dict(), "", false, true))     # 키 순서 그대로 · 실수를 다 살린다 —— 아니면 불러온 판이 갈라진다


static func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)


static func load_saved() -> Run:
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return null
	var d = JSON.parse_string(f.get_as_text())
	if typeof(d) != TYPE_DICTIONARY:
		return null
	var r := Run.new()
	r.from_dict(d)
	return r


static func delete_save() -> void:
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(SAVE_PATH)


# ───────── 점검용 —— 사람 대신 단순한 규칙으로 한 페이즈를 진행한다 (tests/game.gd · --gplay) ─────────

func dev_autoplay() -> void:
	if over != null:
		return
	if not drawn and draws_n() > 0:
		do_draw()
	if not picked:
		begin_picks("phase")
	if not granted and not grant_list().is_empty():
		random_grant()
	_dev_spend()
	if is_tour_phase():
		if tour == null:
			init_tour()
		while over == null:
			var bt := start_tour()
			finish_battle(simulate(bt, [], policy_for(bt, "auto")))
			if over == null:
				tour_advance()
		return
	var q := start_quest()
	finish_battle(simulate(q, [], policy_for(q, "auto")))
	if over != null:
		return
	_dev_spend()
	var p := start_pvp()
	finish_battle(simulate(p, [], policy_for(p, "auto")))
	advance()


func _dev_spend() -> void:
	while not pending_picks.is_empty():
		begin_picks("pending", 0)
	while not pick_queue.is_empty():
		var pl: Array = DB.by_tier(int(pick_queue[0].t))
		pl.sort_custom(func(a, b): return DB.C[a].tr > DB.C[b].tr)
		pick(pl[rng.randi() % mini(6, pl.size())])
	var made := true
	while made:
		made = false
		for t in range(8, 1, -1):
			for k in DB.by_tier(t):
				if can_forge(k):
					forge(k)
					made = true
	auto_deploy()
