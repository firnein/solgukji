class_name Run
extends RefCounted
## 한 판의 진행 상태 —— 원본 HTML 의 S 와 진행 규칙(4. 상태 · 5. 조합(환전은 뺐다) · 8. 진행)을 옮겼다.
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
const SKILL_LO := 1.15        # 봇 실력 계수 (11/2 난이도 상승: 0.98 ~ 1.38 → 1.08 ~ 1.45, 11/9 폭을 좁혀 1.15 ~ 1.35 —— 평균은 거의 그대로, 너무 센 봇을 줄인다)
const SKILL_HI := 1.35
const SAVE_PATH := "user://save.json"

var rng := RandomNumberGenerator.new()
var day := 0
var phase := 0
var inv := {}                 # 카드 id -> 장수 (손패)
var bag := {}                 # 아이템 id -> 개수
var board := []               # 9칸 —— 카드 id 또는 null
var equip := []               # 9칸 —— 아이템 id 또는 null
var form := "eorin"
var tac := "균형"            # 작전 —— 전투 전에 고른다. 전투 중 AI 가 이 방침으로 고유기 · 군령을 쓴다 (11/1)
var drawn := false
var picked := false
var granted := false
var quest_done := false
var pvp_done := false
var tickets := {}             # 선택권 —— 등급("4") -> 남은 장수. 등급마다 따로 쓴다 (끄고 켜도 남는다)
var strikes := 0              # 토벌 실패 횟수 (기록용 —— 11/9 멸망 조건은 민심(hp)으로)
## 11/9 사용자: 패배 보상을 깎지 말고 유저 HP 를 깎자 —— 지기 시작하면 보급이 줄어 뒤집을 수가 없었다.
## 민심 100 에서 시작, 토벌 · 대전에 지면 일차별 피해(크게 질수록 더) 만큼 깎이고 0 이면 멸망. 보상은 이겼을 때와 같다
const HP_MAX := 100
## 11/9 조정 (tests/hp_dist · 오토 90판 + 승률별 모의): 처음 [10..22] 는 능숙한 사람(토벌 80% · 대전 70%)도 44% 가 멸망, 오토는 3~4일차에 전멸이었다.
## [4,5,7,9,11,13,15] 로 —— 능숙 ≈ 57 깎임(생존), 보통(65/55%) ≈ 38% 멸망, 토벌 35% 이하는 5~6일차 멸망, 1~2일차 패배는 3~5 로 가볍다
const HP_QUEST := [4, 5, 7, 9, 11, 13, 15]      # 토벌 패배 기본 피해 (일차별) —— 적 남은 병력 비에 따라 ×0.6 ~ 1.0
const HP_PVP_MUL := 0.6                              # 대전 패배는 토벌의 0.6배
var hp := HP_MAX
## 점검용 —— 11/9 이전 사람 기록(패배 보상 감액 규칙)을 되살릴 때(tests/replay_log) 켠다. 보상이 달라지면 되살린 덱이 기록과 달라져 난이도 측정이 틀어진다
static var legacy_rewards := false
static var dev_hp_log := []      # 11/9 점검용 —— 패배마다 [일차, 종류, 기본 피해, 적 남은 비, 무승부] (tests/hp_dist)
var last_hp_loss := 0         # 방금 전투에서 깎인 민심 (결과 화면용)
var last_draw := []
var last_item = null
var uniq_offer := []          # 유니크 보급 —— 고를 수 있는 신화 재료 (고르면 비운다)
var myth_made := false        # 신화를 이미 만들었다 (한 판에 하나)
var kiin_made: Array = []     # 만든 기인 (11/3 —— 한 판에 각 1장)
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
	tac = "균형"
	drawn = false
	picked = false
	granted = false
	quest_done = false
	pvp_done = false
	tickets = {}
	strikes = 0
	hp = HP_MAX
	last_hp_loss = 0
	last_draw = []
	last_item = null
	uniq_offer = []
	myth_made = false
	kiin_made = []
	last_spoil = null
	tour = null
	my_w = 0
	my_l = 0
	news = []
	over = null
	battle = null
	last_result = null
	bots = []
	var bot_names := DB.gen_bot_names(rng.seed, DB.D.BOTNAME.size())      # 11/10 봇 이름은 판마다 랜덤 (DB.gen_bot_names)
	for i in DB.D.BOTNAME.size():
		var b: Array = DB.D.BOTNAME[i]
		bots.append({"name": bot_names[i], "epi": b[1], "fac": b[2], "style": DB.D.STYLES[i], "pv": 0.0,
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


## 선택권 · 배급으로 받을 수 있는 카드 —— 기인은 조합으로만 (11/3 사용자: 전설 선택권에 기인이 나오지 않게)
static func pickable(t: int, tag := "") -> Array:
	return DB.by_tier(t).filter(func(k): return not DB.is_kiin(k) and (tag == "" or DB.C[k].tag == tag))


# ───────── 아이템 ─────────

func gain_item() -> String:
	var p := phase_idx()
	var grade := "일반"
	if DB.D.UNIQUE_PHASES.any(func(x): return int(x) == p):      # JSON 숫자는 실수라 has(p) 는 늘 거짓이었다 (11/2)
		grade = "유니크"           # 정해진 아침에만 확정 지급 (11/2 사용자: 1 · 3 · 5일차 아침 → 11/5 2 · 4 · 6일차 아침, DB.ECON)
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
	if grade == "유니크":
		cand = cand.filter(func(k): return DB.MYTH_ITEMS.has(k))      # 11/3 플레이어가 만들 수 있는 신화(12명)의 재료만
		_offer_unique(cand)
		return ""
	# 보급은 지금 세운 군세에 맞는 물건이 온다
	var tags := {}
	for k in board:
		if k != null:
			tags[DB.C[k].tag] = true
	for k in inv:
		if DB.C[k].tier >= 5:
			tags[DB.C[k].tag] = true
	if not tags.is_empty():
		var fit := cand.filter(func(k): return tags.has(DB.IT[k].tag))
		if not fit.is_empty() and rng.randf() < 0.7:
			cand = fit
	var id: String = cand[rng.randi() % cand.size()]
	bag[id] = bag.get(id, 0) + 1
	last_item = id
	return id


## 유니크 보급 (2 · 4 · 6일차 아침) —— 신화 재료 셋 중 하나를 고른다 (11/2 사용자).
## 군세와 상관없이 무작위 셋, 가방에 이미 있는 것은 빼고. 신화는 한 판에 하나뿐이라
## 일찍 받은 것으로 빨리 만들지, 3 · 5일차 보급을 기다릴지가 선택이 된다
func _offer_unique(cand: Array) -> void:
	# 11/4 사용자: 가진 유니크는 나오지 않게 —— 가방에 있는 것 + 신화 조합에 써서 장수에게 붙은 것(가진 신화의 재료)
	var owned := {}
	for k in bag:
		owned[k] = true
	for k in pool():
		var inn = innate_item(k)
		if inn != null:
			owned[inn] = true
	cand = cand.filter(func(k): return not owned.has(k))
	var out := []
	while out.size() < 3 and not cand.is_empty():
		out.append(cand.pop_at(rng.randi() % cand.size()))
	uniq_offer = out
	if not out.is_empty():
		toasts.append(["아이템 보급 도착 · %d개 중 하나를 고르시오" % out.size(), "gold"])


## 유니크 보급에서 하나를 고른다
func pick_unique(id: String) -> bool:
	if not uniq_offer.has(id):
		return false
	bag[id] = bag.get(id, 0) + 1
	last_item = id
	uniq_offer = []
	return true


## 신화는 한 판에 하나만 (11/2 사용자 —— 원랜디 초월처럼). 이미 만들었거나 가지고 있으면 더 못 만든다
func has_myth() -> bool:
	if myth_made:
		return true
	for k in inv:
		if DB.C[k].tier >= 8:
			return true
	for k in board:
		if k != null and DB.C[k].tier >= 8:
			return true
	return false


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


## 가방에서 병종이 맞는 최상 등급을 고른다. 유니크 재료는 신화를 아직 만들 수 있을 때만 조합용으로 남긴다
## (11/3 사용자: 자동 편성이 상위 아이템을 끼우지 않는다 —— 신화는 한 판에 하나라, 만든 뒤 남은 유니크는 늘 가방에 묵었다)
func recommend_items() -> Array:
	var used := {}
	var eq := _nine()
	var order := ["유니크", "레어", "매직", "일반"]
	var keep_uniq := false      # 11/4 사용자: 자동 배치에 유니크를 먼저 끼운다 (끼워도 가방에 남아 신화 조합에 쓸 수 있다 —— 조합하면 그 칸은 비운다)
	var slots := []
	for i in 9:
		if board[i] != null and innate_item(board[i]) == null:
			slots.append(i)
	slots.sort_custom(func(a, b):
		if DB.C[board[a]].tier != DB.C[board[b]].tier:
			return DB.C[board[a]].tier > DB.C[board[b]].tier
		return DB.C[board[a]].pv > DB.C[board[b]].pv)
	for i in slots:
		var k: String = board[i]
		var cand: Array = bag.keys().filter(func(it): return DB.IT[it].tag == DB.C[k].tag \
			and bag[it] - used.get(it, 0) > 0 and not (keep_uniq and DB.IT[it].use == "myth"))
		if cand.is_empty():
			continue
		cand.sort_custom(func(a, b):
			var ga := order.find(DB.IT[a].grade)
			var gb := order.find(DB.IT[b].grade)
			if ga != gb:
				return ga < gb
			return DB.IT[a].pa + DB.IT[a].sa > DB.IT[b].pa + DB.IT[b].sa)
		eq[i] = cand[0]
		used[cand[0]] = used.get(cand[0], 0) + 1
	return eq


# ───────── 조합 ─────────

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
	if DB.C[out].tier >= 8 and has_myth():
		return false
	if DB.is_kiin(out) and (kiin_made.has(out) or have(out) > 0):      # 기인은 한 판에 각 1장
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
		var left := int(bag.get(ni, 0))      # 조합에 쓴 유니크를 끼고 있던 칸은 비운다 (가방 수보다 많이 끼지 않게)
		for i in 9:
			if equip[i] == ni:
				if left > 0:
					left -= 1
				else:
					equip[i] = null
	if DB.C[out].tier >= 8:
		myth_made = true
	if DB.is_kiin(out):
		kiin_made.append(out)
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


## 추천 목표 (11/5 사용자: 플레이에 도움이 되게) —— 점수 = 덱이 얻는 전력 − 모자란 재료를 구하는 수고 + 줄기 · 병종 맞춤
##   덱 이득: 결과 전력값(pv). 편성이 꽉 찼으면 가장 약한 편성 장수 대신 들어간다고 보고 그만큼 뺀다.
##            편성에 앉은 카드가 재료로 빠지면(남는 장이 없으면) 그 전력도 뺀다 (같은 인물의 승급은 빼지 않는다).
##   수고: 모자란 재료마다 —— 기본 1 · 고급 3 · 희귀 6 · 전설 12(무작위 보급뿐) · 그 위는 만들어야 해서 20,
##         그 등급 선택권이 있으면 고를 수 있어 1/3, 지금 바로 조합되는 재료면 2. 유니크가 없으면 40 (2 · 4 · 6일차 보급뿐)
##   맞춤: 편성 장수와 같은 인물(승급) +18 · 편성에 많은 병종 +6 (11/9 진형 우대 병종 +4 는 삭제)
##   빼는 것: 이미 만들 수 있는 것(따로 띄운다) · 같은 인물을 이미 그 등급 이상으로 가진 것 · 만든 기인 ·
##            신화를 가졌으면 신화 · 가진 최고 등급보다 한 단계 넘게 낮은 것 · 수고가 GOAL_EFFORT 를 넘는 것
const GOAL_EFFORT := 14.0
const GOAL_MISS := {1: 1.0, 3: 3.0, 4: 6.0, 5: 12.0}


func goal_effort(out: String) -> float:
	var m := mat_count(DB.RECOF.get(out, []))
	var e := 0.0
	for q in m:
		var short: int = int(m[q]) - have(q)
		if short <= 0 or not DB.C.has(q):
			continue
		var t: int = DB.C[q].tier
		var per: float = GOAL_MISS.get(t, 20.0)
		if int(tickets.get(str(mini(FREE_TIER_CAP, t)), 0)) >= short and not (LEGEND_RANDOM and t == 5):
			per /= 3.0
		if DB.RECOF.has(q) and can_forge(q):
			per = minf(per, 2.0)
		e += per * short
	var ni = need_item(out)
	if ni != null and bag.get(ni, 0) <= 0:
		e += 40.0
	return e


func goal_score(out: String) -> float:
	var c: Dictionary = DB.C[out]
	var gain := float(c.pv)
	var placed_ := board.filter(func(k): return k != null)
	var p := DB.person(out)
	var upgrade := placed_.any(func(k): return DB.person(k) == p)
	if placed_.size() >= 9 and not upgrade:
		var weakest := 1 << 30
		for k in placed_:
			weakest = mini(weakest, int(DB.C[k].pv))
		gain -= weakest
	var m := mat_count(DB.RECOF.get(out, []))
	for q in m:
		if DB.C.has(q) and on_board(q) > 0 and DB.person(q) != p:
			var spare := int(inv.get(q, 0))
			var from_board := mini(on_board(q), maxi(0, m[q] - spare))
			gain -= float(DB.C[q].pv) * from_board
	var fit := 0.0
	if upgrade:
		fit += 18.0
	var tc := {}
	for k in placed_:
		tc[DB.C[k].tag] = int(tc.get(DB.C[k].tag, 0)) + 1
	if int(tc.get(c.tag, 0)) >= 2:
		fit += 6.0
	return gain + fit - goal_effort(out) * 6.0


func forge_goals(keys: Array, limit := 4, max_effort := GOAL_EFFORT) -> Array:
	var top := 3
	for k in pool():
		if DB.C[k].tier >= 3:
			top = maxi(top, DB.C[k].tier)
	var min_t := maxi(3, top - 1)      # 11/4 사용자: 가진 최고 등급보다 한 단계 넘게 낮은 등급은 빼고
	var cand := []
	for out in keys:
		if not DB.RECOF.has(out) or DB.is_foe(out) or can_forge(out) or DB.C[out].tier < min_t:
			continue
		if DB.C[out].tier >= 8 and has_myth():
			continue
		if DB.is_kiin(out) and (kiin_made.has(out) or have(out) > 0):
			continue
		var p := DB.person(out)
		var t: int = DB.C[out].tier
		if pool().keys().any(func(k): return DB.C[k].tier >= t and DB.C[k].tier >= 3 and DB.person(k) == p):
			continue
		if goal_effort(out) > max_effort:
			continue
		cand.append([goal_score(out), out])
	cand.sort_custom(func(a, b): return a[0] > b[0])
	var out_ := []
	var seen := {}
	for c in cand:
		var p := DB.person(c[1])
		if seen.has(p):
			continue
		seen[p] = true
		out_.append(c[1])
		if out_.size() >= limit:
			break
	return out_


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


# ───────── 편성 ─────────

## 같은 인물이 이미 앉은 칸 (i 는 빼고) —— 없으면 -1. 11/3 솔국지 확장: 같은 인물은 한 부대만 (등급이 달라도)
func dup_slot(i: int, k: String) -> int:
	for j in 9:
		if j != i and board[j] != null and DB.person(board[j]) == DB.person(k) and DB.C[k].tier >= 3:
			return j
	return -1


func place(i: int, k: String) -> void:
	if i < 0 or i > 8 or inv.get(k, 0) <= 0:
		return
	var dj := dup_slot(i, k)      # 같은 인물이 다른 칸에 있으면 그 카드를 손패로 돌리고 이 칸에 앉힌다
	if dj >= 0:
		unplace(dj)
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
	var pick9 := []
	var seen := {}
	for k in all:                      # 같은 인물은 한 부대만 (병졸 · 기본패는 여럿 가능)
		var p: String = DB.person(k) if DB.C[k].tier >= 3 else ""
		if pick9.size() < 9 and (p == "" or not seen.has(p)):
			pick9.append(k)
			if p != "": seen[p] = true
		else:
			give(k)
	board = DB.auto_place(pick9, form)
	equip = recommend_items()


func clear_board() -> void:
	for i in 9:
		unplace(i)


## 작전 —— 정책 문자열 (Battle tac:<고유기>:<군령>) 과 설명. 셋이 서로 물고 물리게 맞췄다 (11/1 측정, ±5%p)
const TACS := {
	"균형": {"pol": "tac:영리:영리", "d": "상대를 보고 돌격 · 방진을 고르고, 고유기는 값어치 있을 때 쓴다"},
	"맹공": {"pol": "tac:즉시:공세", "d": "바로 돌격, 돌격 공격 +25% · 고유기는 차면 바로"},      # 11/9 사용자: 군령은 사라졌다 —— 문구에서 뺌
	"굳히기": {"pol": "tac:위기:수비", "d": "돌격 없이 방진 · 재정비로 버틴다 · 고유기는 꺾일 때까지 아껴 배수진 위력 ×1.6"},
}


## 덱에 맞는 작전 —— 물리(공격 ≥ 지력) 장수가 많으면 맹공, 지략 장수가 많으면 굳히기 (11/1 tests/tac_fit 측정:
## 기병 · 창병 · 궁병 · 도적 덱은 맹공 +4~15%p, 책사 · 모사 · 술사 · 유생 덱은 맹공 -4~-11 · 굳히기 +2~11%p). [작전, 물리 수, 지략 수]
static func recommend_tac(cards: Array) -> Array:
	var ph := 0
	var it := 0
	for k in cards:
		if k == null or not DB.C.has(k):
			continue
		if DB.PHYS_TAGS.has(DB.C[k].tag):      # 11/6 #15 책략 능력치 통합 —— 성향은 병종으로
			ph += 1
		else:
			it += 1
	var t := "균형"
	if ph >= it + 3:
		t = "맹공"
	elif it >= ph + 3:
		t = "굳히기"
	return [t, ph, it]


func set_tac(t: String) -> void:
	if TACS.has(t):
		tac = t


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
	if day == 6 and DB.ECON_ON:
		l = DB.DAY7_PICKS[phase]      # 11/7 보급 줄임 (DB.ECON 주석)
	elif day == 6:
		l = [{"t": 6, "n": 1}] if phase == 0 else ([{"t": 5, "n": 1}] if phase == 1 else [{"t": 6, "n": 1}, {"t": 4, "n": 2}])
	else:
		l = DB.D.PICKS[day]
	return no_empty_tier(l.map(func(p): return {"t": mini(FREE_TIER_CAP, int(p.t)), "n": int(p.n)}))


## 11/3 일반 등급 삭제 —— 원본 표(PICKS · QUEST_REWARD)의 일반 선택권은 일반 둘 = 고급 하나, 남는 일반 하나 = 기본 둘로 바꾼다
## (고급 = 기본 넷, 예전 일반 ≈ 기본 둘 반)
static func no_empty_tier(l: Array) -> Array:
	var out := []
	for p in l:
		var t := int(p.t)
		var n := int(p.n)
		if DB.PLAY_TIERS.has(t):
			out.append({"t": t, "n": n})
			continue
		if n >= 2:
			out.append({"t": DB.next_tier(t), "n": n / 2})
		if n % 2 == 1:
			out.append({"t": 1, "n": 2})
	var merged := {}
	for p in out:
		merged[p.t] = merged.get(p.t, 0) + p.n
	var keys := merged.keys()
	keys.sort()
	keys.reverse()
	return keys.map(func(t): return {"t": t, "n": merged[t]})


func random_grant() -> Array:
	if granted:
		return []
	var got := []
	for p in DB.D.RANDOM_GRANT[day]:
		var t := mini(FREE_TIER_CAP, int(p.t))
		var src: Array = pickable(t).filter(func(x): return DB.C[x].tier < 8)
		if src.is_empty():
			continue
		for i in int(p.n):
			var k: String = src[rng.randi() % src.size()]
			give(k)
			got.append(k)
	granted = true
	return got


func grant_list() -> Array:
	return DB.D.RANDOM_GRANT[day]


# ───────── 진행 ─────────

## 봇 성장 (페이즈마다) —— 11/4 사용자: 대전이 거의 늘 이긴다 → 봇을 더 강하게. 예전 22 + 일차×4 (+저녁 4) 의 약 1.6~1.75배
## (2일차 저녁 봇 약 180 → 약 310 PV, 7일차 끝 약 890 → 약 1,570 PV, 실력 계수 평균 1.27 기준). 서버(room.gd)도 이것을 쓴다
static func bot_pv_gain(d: int, p: int) -> float:
	return (24 + d * 4.7 + (4 if p == 2 else 0)) * BOT_LATE[clampi(d, 0, 6)]      # 11/6 밸런스: 자동 진행 기준 2일차 대전 승률 13% · 3일차 0% → 약 0.85배


## 11/7 4일차부터 보급을 줄인 만큼 봇 성장도 줄인다 —— 일차 끝 봇 PV 가 예전의 0.94 · 0.86 · 0.80 · 0.78 배
## (자동 진행 편성 PV 가 새 보급에서 예전의 0.95 · 0.86 · 0.77 · 0.77 배, tests/supply_check --econ=new)
## 11/9 사용자: 봇 대전도 너무 쉽다 —— tests/replay_log(11/8 사람 기록, k=8)로 일차마다 봇 PV / 내 편성 PV 를 0.9 ~ 1.15 에 맞춘다.
##   대전 승률 1~7일 71 · 63 · 58 · 79 · 54 · 71 · 81% (예전 값 78 · 14 · 14 · 11 · 14 · 56 · 46% —— 그때는 되살리기가 1-1 에서 어긋나 장비 없는 덱)
## 11/9 2차 사용자: 봇 대전도 여전히 쉽다 —— 일차별 값을 올려 4 · 5일차 이후 봇 덱이 전설 8~9 · 초월 1~2 (예전 전설 7~8 · 기본 아래 칸 1~2). 봇은 토벌 때마다 PV ×0.94(run.gd finish_battle)라 값이 누적된다
##   diff_probe 대역 대전 승률 예전 55 · 50 · 67 · 77 · 52 · 65 · 50% → 55~63 · 50~63 · 65~73 · 55~60 · 35~42 · 55~65 · 35~42% (판 수 적어 ±10%p), 토너먼트 우승 33 → 28%
## 11/9 첫 유저 기록(user_log_1109, 우승 · 대전 승률 2일차 이후 83~100% · 봇 최고 PV / 내 PV 가 0.65 → 0.35 로 내려앉음): 사용자 "지더라도 올려라".
##   replay_log --orig=now 로 그날 끝 봇 최고 PV / 기록의 내 PV 0.94 · 0.79 · 0.66 · 0.56 · 0.52 · 0.50 · 0.48 (예전 0.93 · 0.65 · 0.59 · 0.53 · 0.37 · 0.39 · 0.35),
##   그 사람 덱의 대전 승률 50 · 38 · 58 · 46 · 50 · 17 · 13% (예전 50 · 58 · 71 · 83 · 100 · 100 · 100%), 토너먼트 우승 100% → 0%.
##   6~7일차 · 토너먼트가 급락하는 건 봇 덱에 초월이 들어오는 계단(봇 PV ×1.08 ×1.3 이 약 700 을 넘으면) —— 초월 한 칸 값의 문제, 마지막 밸런스 때
static var BOT_LATE := [1.65, 0.8, 1.0, 0.85, 0.95, 0.9, 0.85]


func _bot_pv_gain(d: int, p: int) -> float:
	return bot_pv_gain(d, p)


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
	# 11/9 사용자: 기본 징집을 못 했어도 사라지지 않아야 한다 —— 페이즈를 넘길 때 안 뽑은 공짜 징집은 그 자리에서 뽑아 준다
	if not drawn and draws_n() > 0 and not legacy_rewards:
		do_draw()
		toasts.append(["안 뽑은 기본 징집 %d장을 받았다" % last_draw.size(), "gain"])
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
	last_draw = []
	last_spoil = null
	if day > 6:
		over = {"win": true, "msg": "일주일을 살아남았다"}
		day = 6
		return
	if hp <= 0 and not dev_immortal:      # 11/9 민심이 바닥났으면 (finish_battle 에서 이미 끝났어야 한다)
		over = {"win": false, "msg": "민심이 바닥났다 —— 세력이 멸망했다"}
		return
	gain_item()
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
	return {"cards": board.duplicate(), "form": form, "morale": my_morale(), "equip": equip.duplicate(), "tac": tac}


func _bot_side(pv: float, style: String) -> Dictionary:
	return bot_side(pv * BOT_PV_MUL * (MYTH_BOT_PV if myth_on_board() else 1.0), style, phase_idx(), rng)


## 봇 · 토벌 적 군세 —— 11/2 사용자: 너무 허접하다 → 장비를 끼우고(그 때 보급 등급으로, 사람보다 조금 많이) 덱에 맞는 작전을 쓴다
const BOT_PV_MUL := 1.08
const QUEST_PV_MUL := 1.05      # 11/6 밸런스: 3일차 토벌 병력비 0.43 → 1.2 에서 내림
## 11/9 사용자: 첫날 아침 봇 대전은 늘 조합 안 된 1등급 병사뿐이었다 —— 봇 PV 가 0 에서 시작해서. 첫 대전만 바닥을 둔다 (약 9칸 중 4칸이 3등급, 이후는 성장 그대로)
const BOT_OPEN_PV := 32.0
static func bot_side(pv: float, style: String, p_idx: int, r: RandomNumberGenerator) -> Dictionary:
	if p_idx <= 0:
		pv = maxf(pv, BOT_OPEN_PV)
	var eb := DB.gen_board(pv, style, r)
	var cards := DB.auto_place(eb.cards, eb.form)
	return {"cards": cards, "form": eb.form, "morale": 100, "equip": bot_equip(cards, p_idx, r), "tac": recommend_tac(cards)[0]}


## 높은 등급 장수부터 (보급 수 + 2)개까지, 그 때의 보급 등급표로 병종이 맞는 장비를 끼운다
static func bot_equip(cards: Array, p_idx: int, r: RandomNumberGenerator) -> Array:
	var eq := []
	eq.resize(cards.size())
	var tbl: Dictionary = {}
	for d in DB.D.DROP:
		if p_idx <= int(d.upto):
			tbl = d.w
			break
	var slots := []
	for i in cards.size():
		if cards[i] != null and innate_item(cards[i]) == null:
			slots.append(i)
	slots.sort_custom(func(a, b): return DB.C[cards[a]].tier > DB.C[cards[b]].tier)
	var n := mini(slots.size(), p_idx + 2)
	for j in n:
		var i: int = slots[j]
		var tot := 0.0
		for g in tbl:
			tot += tbl[g]
		var x := r.randf() * tot
		var grade := "일반"
		for g in tbl:
			x -= tbl[g]
			if x <= 0:
				grade = g
				break
		var tag: String = DB.C[cards[i]].tag
		var cand: Array = DB.IT.keys().filter(func(k): return DB.IT[k].grade == grade and DB.IT[k].tag == tag and DB.IT[k].use != "myth")
		if not cand.is_empty():
			eq[i] = cand[r.randi() % cand.size()]
	return eq


## 토벌 고정 편성 (황건적 소탕, 11/2) —— 없으면 null (예전처럼 PV 로 무작위)
func quest_roster():
	if DB.QUEST_ROSTERS.is_empty():
		return null
	return DB.QUEST_ROSTERS[day][phase]


## 11/3 수입을 약 70% 로 줄이며 (DB.ECON) 토벌 황건 편성은 예전 수입에 맞춘 그대로라 —— 적 사기로 낮춘다 (사기는 모든 능력치에, 70 → 0.88배)
static var QUEST_MORALE := [0.8, 0.68, 0.62, 0.7, 0.62, 0.6, 0.65]
## 11/6 밸런스: 토벌 고정 편성 병력 배율 —— 3일차부터 병력이 두 배 넘게 뛰어(자동 진행 병력비 0.44, 승률 18%) 일차마다 줄인다
## 11/7 4일차부터 보급을 줄인 만큼(편성 PV 0.95 · 0.86 · 0.77 · 0.77 배) 4~7일차를 낮춘다 —— 예전 0.5 · 0.52 · 0.55 · 0.6
## 11/9 사용자: 토벌이 여전히 너무 쉽다 —— 적이 황건 잡병으로 바뀐 뒤 tests/replay_log(11/8 사람 기록, 1-2 까지 되살린 덱)로 다시:
##   남은 병력 첫 토벌 35% · 1~7일 60 · 52 · 62 · 41 · 52 · 54 · 50% (기준 첫 토벌 30~60 · 그 뒤 40~65), 병사 최대 8.4천
## 11/9 첫 유저 기록: 5~7일차 토벌이 내 병력 87~98% 남기고 끝난다(적 7등급 부대 병력 2,820 vs 내 7등급 48,551). 병력 ×8 · 사기 ×2.5 로도 71% 남음 —— 배율 자체를 1 근처로.
##   replay_log --orig=now --qtr 로 그 사람 덱 기준 토벌 승 · 남은 병력: 첫 토벌 100 · 60% / 1~7일 100 · 45% · 65 · 40 · 60 · 25 · 55 · 40 · 50 · 35 · 50 · 40 · 50 · 40% 어림 (예전 2일차 이후 75 · 46 → 100 · 96%)
##   0.6 → 0.9 사이에서 승률이 90% → 10% 로 꺾인다 (6 · 7일차) —— 병력이 같아지면 적 7등급 아홉이 내 전설을 녹인다
static var QUEST_TR := [0.25, 0.85, 1.1, 1.3, 3.0, 0.75, 0.42]
## 11/9 2차: 잡병을 질로 올리면서(DROP · FLOOR) 총 병력이 늘지 않게 3~7일차를 낮춤 (적 병력 총합이 예전의 +10% 안).
##   diff_probe 대역(자동 진행 편성 PV × 일차별 사람 배율)으로 토벌 남은 병력 첫 토벌 21% · 1~7일 51 · 37 · 40 · 31 · 43 · 44 · 33% (예전 대역 68 · 53 · 57 · 46 · 47 · 45 · 40)
## 11/7 사용자: 황건적은 물량이 많았다 —— 진형이 4행 5열(20칸)로 늘어난 만큼 토벌 적은 우두머리 9부대 + 잡병 부대로 몰려온다.
## 잡병은 우두머리 편성의 가장 낮은 등급보다 두 등급 아래 (DB.horde_rabble) —— 내 장수가 쓸어 버리는 맛. 일차마다 늘어 4일차부터 20칸을 다 채운다
## (자동 진행 12판: 7 · 9 부대였을 때 2 · 3일차 토벌 승이 28/36 → 22/36 · 12/33 → 8/30 으로 떨어져 5 · 7 로)
static var QUEST_HORDE := [5, 5, 7, 11, 11, 11, 11]
## 11/9 사용자: 후반에도 낮은 등급 잡병이 20칸 중 11칸을 채워 의미 없이 쓸려 나간다 (잡병 병력이 적 전체의 4~9%) ——
## 잡병 등급 = 우두머리 가장 낮은 등급 − DROP, 단 일차별 FLOOR 아래로는 안 내려간다 (DB.horde_rabble). 일차가 오를수록 3 → 5 등급 황건 · 황천 정예
static var QUEST_RABBLE_DROP := [1, 1, 1, 1, 1, 1, 1]
static var QUEST_RABBLE_FLOOR := [2, 3, 4, 4, 5, 5, 5]      # 11/9 첫 유저 기록: 5일차 토벌은 병력 ×2.4 로도 내 병력 65~84% 남음(적 4~6등급이 내 7~8등급을 못 깎는다) —— 잡병 바닥을 5로
static var horde_enabled := true      # 점검용 —— 끄면 예전 9부대
func quest_horde_n() -> int:
	return int(QUEST_HORDE[clampi(day, 0, 6)]) if horde_enabled else 0


func quest_morale_mul() -> float:
	return float(QUEST_MORALE[clampi(day, 0, 6)]) if DB.ECON_ON else 1.0      # 11/4 사용자: 토벌은 내 패와 상관없이 고정


## 11/4 사용자: 신화를 만들면 대전이 너무 쉬워진다 —— 신화가 편성에 있으면 대전 봇 PV 를 올린다 (토벌은 고정)
const MYTH_BOT_PV := 1.3

func myth_on_board() -> bool:
	return board.any(func(k): return k != null and DB.C[k].tier >= 8)


func quest_name() -> String:
	var q = quest_roster()
	return q.name if q != null else DB.D.QUESTS[day][phase]


func quest_pv() -> int:
	var q = quest_roster()
	return int(q.pv) if q != null else int(DB.D.QPV[day][phase] * QUEST_PV_MUL)


func start_quest() -> Dictionary:
	var pv := quest_pv()
	var q = quest_roster()
	var foe: Dictionary
	if q != null:
		# 정해진 황건 편성 —— 장비 없이, 덱에 맞는 작전 (11/2 사용자: 토벌이 너무 어려워졌다)
		var cards := DB.auto_place(q.cards, q.form)
		var eq: Array = q.get("equip", [])
		var form: String = q.form
		var hn := quest_horde_n()
		if hn > 0 and DB.FORM.has(DB.HORDE_PFX + form):
			cards.append_array(DB.horde_rabble(q.cards, hn, rng, int(QUEST_RABBLE_DROP[clampi(day, 0, 6)]), int(QUEST_RABBLE_FLOOR[clampi(day, 0, 6)])))      # 대군 진형 9 번 칸부터 —— 우두머리 자리는 그대로
			form = DB.HORDE_PFX + form
			if not eq.is_empty():
				eq = eq.duplicate()
				eq.resize(cards.size())
		foe = {"cards": cards, "form": form, "morale": int(int(q.get("morale", 100)) * quest_morale_mul()),
			"equip": eq, "tac": recommend_tac(cards)[0], "tr_mul": float(QUEST_TR[clampi(day, 0, 6)])}      # 장비는 맞출 때 auto_place 자리 그대로 (같은 순서라 자리가 같다)
	else:
		var styles := ["물리", "지략", "균형"]
		foe = _bot_side(pv, styles[rng.randi() % 3])
	if not DB.quest_trait(day).is_empty(): foe["trait"] = DB.quest_trait(day)      # 11/8 토벌 우두머리 성질 (docs/역할_재설계_1108.md 7.3) —— 비면 넣지 않는다
	battle = {"kind": "quest", "a": _my_side(), "b": foe, "seed": rng.randi() % 1000000,
		"title": "토벌 · %s" % quest_name(), "foe": quest_name(), "pv": pv, "inputs": []}
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


## 정책 —— 각 진영이 고른 작전 (없으면 영리). foe_ai 가 있으면 적은 그것 (11/2 부터 토벌 적도 작전을 쓴다)
static func policy_for(bt: Dictionary) -> Dictionary:
	if bt.has("pol"):
		return bt.pol
	return {"A": side_pol(bt.a), "B": bt.get("foe_ai", side_pol(bt.b))}


static func side_pol(side: Dictionary) -> String:
	return TACS.get(side.get("tac", ""), {}).get("pol", "smart")


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
	if res.has("track"):          # 실시간 엔진 위치 —— 좌우를 바꾼다 (x → -x, 방향각 a → π - a)
		out.track = res.track.map(func(fr): return [fr[0], fr[1].map(func(p): return [-p[0], p[1], snappedf(wrapf(PI - float(p[2]), -PI, PI), 0.01), p[3], p[4]])])
		out.terrain = res.get("terrain", []).map(func(z): var o: Dictionary = z.duplicate(); o.x = -int(z.x); return o)
		for e in out.ev:
			for sh in e.get("area", []):     # 기술 범위도 좌우를 바꾼다
				sh.x = -sh.x
				if sh.has("x2"):
					sh.x2 = -sh.x2
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
	Battle.tr_mul = {"A": float(bt.a.get("tr_mul", 1.0)), "B": float(bt.b.get("tr_mul", 1.0))}
	Battle.side_trait = {"A": bt.a.get("trait", {}), "B": bt.b.get("trait", {})}      # 11/8 토벌 우두머리 성질
	var r := RtBattle.make(bt.seed).run(bt.a.cards, bt.a.form, bt.a.morale, bt.a.equip,
		bt.b.cards, bt.b.form, bt.b.morale, bt.b.equip, bt.title, bt.foe, inputs, policy)
	Battle.tr_mul = {"A": 1.0, "B": 1.0}
	Battle.side_trait = {"A": {}, "B": {}}
	return r


## 전투가 끝났다 —— 보상·경고·토너먼트 진행
## 11/9 패배 → 민심 피해. 크게 질수록(적이 많이 남을수록) 더: base × (0.6 + 0.4 × 적 남은 비). 무승부는 절반. 0 이면 멸망
## 피해량만 따로 —— _hp_hit 와 화면(결과 화면의 「민심 −N」 연출, 전투가 끝나고 결과를 정리하기 전에 미리 보여 준다)이 같은 식을 쓴다
static func hp_dmg(res: Dictionary, base: float) -> int:
	var foe_left := 0.0
	var mx := 0
	var left := 0
	for u in res.get("roster", []):
		if u.camp == "B":
			mx += int(u.max)
			left += maxi(0, int(u.left))
	if mx > 0:
		foe_left = clampf(float(left) / float(mx), 0.0, 1.0)
	return maxi(1, int(round(base * (0.6 + 0.4 * foe_left) * (0.5 if res.get("draw", false) else 1.0))))


## 이 전투 결과(아직 finish_battle 전)로 민심이 얼마나 깎일지 —— 이기면 · 토너먼트면 0 (화면 전용, 상태는 건드리지 않는다)
func hp_preview(bt: Dictionary, res: Dictionary) -> int:
	if res.get("win", false):
		return 0
	match str(bt.get("kind", "")):
		"quest": return hp_dmg(res, float(HP_QUEST[clampi(day, 0, 6)]))
		"pvp": return hp_dmg(res, float(HP_QUEST[clampi(day, 0, 6)]) * HP_PVP_MUL)
	return 0


func _hp_hit(res: Dictionary, base: float, what: String) -> void:
	var dmg := hp_dmg(res, base)
	var foe_left := 0.0
	var mx := 0
	var left := 0
	for u in res.get("roster", []):
		if u.camp == "B":
			mx += int(u.max)
			left += maxi(0, int(u.left))
	if mx > 0:
		foe_left = clampf(float(left) / float(mx), 0.0, 1.0)
	hp = maxi(0, hp - dmg)
	last_hp_loss = dmg
	if dev_log or dev_immortal:
		dev_hp_log.append([day, what.begins_with("대전"), base, foe_left, res.get("draw", false)])
	# 11/10 사용자: 민심은 결과 화면의 「민심 −N」 연출 · 머리띠 게이지가 보여 준다 —— 글 알림은 걷었다
	if hp <= 0 and not dev_immortal:
		over = {"win": false, "msg": "%s 패배 —— 민심이 바닥나 세력이 멸망했다" % what}


func finish_battle(res: Dictionary) -> void:
	if battle == null:
		return
	var bt: Dictionary = battle
	battle = null
	last_result = {"title": bt.title, "win": res.win, "draw": res.draw, "left": res.left, "eLeft": res.eLeft,
		"turns": res.turns, "mvp": res.mvp.name if res.mvp else "", "kind": bt.kind}
	if res.win and bt.kind in ["quest", "pvp"]:      # 11/3 전투 밖 기인 —— 편성에 있으면 이길 때마다
		if board.has(DB.kiin_card("ticket")):          # 거상 미축: 그날 보급 등급 선택권 +1
			add_ticket(pick_list()[0].t if not pick_list().is_empty() else 3, 1)
			toasts.append(["거상 미축의 재물 —— 선택권 +1", "gold"])
		if board.has(DB.kiin_card("heal_cut")):        # 흑산 장연: 약탈 —— 기본패 +2
			for i in 2:
				give(DB.BASE[rng.randi() % DB.BASE.size()])
			toasts.append(["흑산 장연의 약탈 —— 기본패 +2", "gold"])
	last_hp_loss = 0
	match bt.kind:
		"quest":
			quest_done = true
			# 11/9 사용자: 져도 보상은 그대로 (예전엔 기본패 절반 · 선택권 한 등급 아래) —— 대신 민심을 깎는다
			if legacy_rewards and not res.win:
				var top := 0
				for p in DB.D.QUEST_REWARD[day]:
					top = maxi(top, int(p.t))
				if top > 0:
					add_ticket(top - 1, 1, true)
				var nl := int(ceil(int(DB.D.QUEST_BASE[day]) / 2.0))
				for i in nl:
					give(DB.BASE[rng.randi() % DB.BASE.size()])
				last_spoil = {"n": nl, "src": "토벌 패배 · " + quest_name()}
			else:
				for p in no_empty_tier(DB.D.QUEST_REWARD[day]):
					add_ticket(int(p.t), int(p.n), true)      # 11/6 #6 전투 보상의 희귀는 랜덤권
				var n := int(DB.D.QUEST_BASE[day])
				for i in n:
					give(DB.BASE[rng.randi() % DB.BASE.size()])
				last_spoil = {"n": n, "src": ("토벌 · " if res.win else "토벌 패배 · ") + quest_name()}
			if not res.win:
				strikes += 1       # 기록용
				_hp_hit(res, float(HP_QUEST[clampi(day, 0, 6)]), quest_name())
			if not mp:
				for b in bots:
					if b.pv < bt.pv * 0.95 * rng.randf_range(0.92, 1.08):
						b.strikes += 1
						b.pv *= 0.94
		"pvp":
			pvp_done = true
			var nb := int(DB.D.PVP_BASE.win if (res.win or not legacy_rewards) else DB.D.PVP_BASE.lose)      # 11/9 져도 이긴 만큼 (예전 lose 4)
			for i in nb:
				give(DB.BASE[rng.randi() % DB.BASE.size()])
			last_spoil = {"n": nb, "src": "대전 · " + bt.foe}
			var b = bots[bt.bot] if bt.has("bot") else null      # 여럿이 하는 판은 서버가 상대 전적을 센다
			add_ticket((4 if day >= 3 else 3) - (1 if legacy_rewards and not res.win else 0), 1, true)      # 11/6 #6 대전 보상의 희귀는 랜덤권 —— 11/9 승패 같게
			if res.win:
				my_w += 1
				if b: b.l += 1
			else:
				my_l += 1
				if b: b.w += 1
				_hp_hit(res, float(HP_QUEST[clampi(day, 0, 6)]) * HP_PVP_MUL, "대전 · " + str(bt.foe))
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
	var res := simulate(battle, inputs, policy_for(battle))
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
	var r := RtBattle.make(rng.randi() % 1000000).run(x.cards, x.form, x.morale, x.equip, y.cards, y.form, y.morale, y.equip)
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

## 이번 페이즈 선택권을 받는다 —— 등급별 선택권(tickets)에 더한다. src 는 예전 명령 모양을 지키려고 남겨 둠
func begin_picks(src: String, _i := -1) -> void:
	if src != "phase" or picked:
		return
	picked = true
	for p in pick_list():
		add_ticket(int(p.t), int(p.n))


## 11/5 사용자: 전설 보급은 고르지 않고 무작위 —— 전설 선택권이 들어오면 바로 무작위 전설로 (기인 제외). 받은 카드는 last_legend · 알림
const LEGEND_RANDOM := true
var last_legend: Array = []


## random: 11/6 사용자 #6 —— 전투 보상(토벌 · 대전)의 희귀는 고르지 않고 무작위 '희귀 랜덤권'. 징집 선택권의 희귀는 고르는 채로
func add_ticket(t: int, n: int, random := false) -> void:
	var tt := mini(FREE_TIER_CAP, t)
	if (LEGEND_RANDOM and tt == 5) or (random and tt == 4):
		var src: Array = pickable(tt)
		for i in n:
			var k: String = src[rng.randi() % src.size()]
			give(k)
			last_legend.append(k)
			toasts.append(["%s 보급 —— %s" % [DB.TIER[tt].n, DB.C[k].name], "gain"])
		return
	if not DB.PLAY_TIERS.has(mini(FREE_TIER_CAP, t)):      # 일반 선택권 → 고급 · 기본 (어디서 들어오든)
		for p in no_empty_tier([{"t": mini(FREE_TIER_CAP, t), "n": n}]):
			add_ticket(p.t, p.n)
		return
	var key := str(mini(FREE_TIER_CAP, t))
	tickets[key] = int(tickets.get(key, 0)) + n


## 선택권이 남은 등급 —— 높은 등급 먼저
func ticket_tiers() -> Array:
	var ts: Array = tickets.keys().map(func(x): return int(x)).filter(func(t): return int(tickets[str(t)]) > 0)
	ts.sort()
	ts.reverse()
	return ts


func ticket_left() -> int:
	var n := 0
	for k in tickets:
		n += int(tickets[k])
	return n


## 선택권 하나 —— 그 카드 등급의 선택권을 쓴다
func pick(k: String) -> bool:
	if not DB.C.has(k) or DB.is_kiin(k) or DB.is_foe(k):
		return false
	var key := str(DB.C[k].tier)
	if int(tickets.get(key, 0)) <= 0:
		return false
	give(k)
	tickets[key] = int(tickets[key]) - 1
	if tickets[key] <= 0:
		tickets.erase(key)
	return true


## 서버가 받아 주는 명령 —— 이름 -> 인자 수
const COMMANDS := {"do_draw": 0, "random_grant": 0, "begin_picks": 2, "pick": 1, "forge": 1, "pick_unique": 1,
	"place": 2, "unplace": 1, "swap": 2, "set_form": 1, "set_tac": 1, "auto_deploy": 0, "clear_board": 0, "set_equip": 2}


func command(m: String, a: Array):
	if not COMMANDS.has(m) or a.size() != COMMANDS[m]:
		return null
	for j in a.size():
		if a[j] is float:
			a[j] = int(a[j])      # JSON 숫자는 float 로 온다 —— 칸 번호 등
	return callv(m, a)


# ───────── 저장 ─────────

const _KEYS := ["day", "phase", "inv", "bag", "board", "equip", "form", "tac", "drawn", "picked", "granted",
	"quest_done", "pvp_done", "tickets", "strikes", "hp", "last_hp_loss", "last_draw", "last_item", "uniq_offer", "myth_made", "kiin_made", "last_spoil",
	"tour", "my_w", "my_l", "news", "bots", "over", "battle", "last_result", "mp"]


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
	for k in ["day", "phase", "strikes", "my_w", "my_l", "hp", "last_hp_loss"]:
		set(k, int(get(k)))
	if not d.has("hp"):      # 예전 저장 —— 경고 수를 민심으로 어림
		hp = maxi(1, HP_MAX - strikes * 20)
	if not d.has("tickets"):
		tickets = {}
		for p in d.get("pending_picks", []) + d.get("pick_queue", []):     # 예전 저장 —— 줄 선 선택권을 등급별로
			add_ticket(int(p.t), int(p.n))
	for k in tickets:
		tickets[k] = int(tickets[k])
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
	# 11/3 일반 등급 삭제 전 저장 —— 가진 일반 카드는 같은 병종 기본패 둘로, 일반 선택권은 바꿔 준다
	for k in r.inv.keys():
		if DB.C.has(k) and DB.C[k].tier == 2:
			var n := int(r.inv[k])
			r.inv.erase(k)
			var base: String = DB.BASE.filter(func(b): return DB.C[b].tag == DB.C[k].tag)[0]
			r.inv[base] = int(r.inv.get(base, 0)) + n * 2
	# 11/5 신화 명단 정리 —— 빠진 신화(장비 · 조운 · 손책, 적 전용)는 같은 인물의 불멸로 돌려주고 신화를 다시 만들 수 있게
	for k in r.inv.keys() + r.board.filter(func(x): return x != null):
		if DB.C.has(k) and DB.C[k].tier == 8 and DB.C[k].kind == "retired":
			var imm: Array = DB.by_tier(7).filter(func(x): return DB.person(x) == DB.person(k))
			if r.inv.has(k):
				var n8 := int(r.inv[k])
				r.inv.erase(k)
				if not imm.is_empty():
					r.give(imm[0], n8)
			for i in r.board.size():
				if r.board[i] == k:
					r.board[i] = imm[0] if not imm.is_empty() else null
			r.myth_made = false
	# 11/5 이름값 구간 정리 —— 빠진 희귀(전설이 있는 인물의 희귀판)는 희귀 선택권으로, 빠진 초월(희귀 구간으로 내린 인물)은
	# 같은 인물의 희귀 + 전설 보급 둘로 (초월 = 제 희귀 + 전설 2 였다)
	for k in r.inv.keys() + r.board.filter(func(x): return x != null):
		if not DB.C.has(k) or DB.C[k].kind != "retired" or not (DB.C[k].tier == 4 or DB.C[k].tier == 6):
			continue
		var nk := int(r.inv.get(k, 0)) + r.board.count(k)
		r.inv.erase(k)
		for i in r.board.size():
			if r.board[i] == k:
				r.board[i] = null
		if DB.C[k].tier == 4:
			r.add_ticket(4, nk)
		else:
			var rare: Array = DB.by_tier(4).filter(func(x): return DB.person(x) == DB.person(k))
			if not rare.is_empty():
				r.give(rare[0], nk)
			r.add_ticket(5, 2 * nk)
	# 11/5 고급 명단 정리 —— 명단에서 빠진 고급(적 전용)은 같은 병종 기본패 넷으로 (고급 = 기본패 4장)
	for k in r.inv.keys():
		if DB.C.has(k) and DB.C[k].tier == 3 and DB.C[k].kind == "retired":
			var n3 := int(r.inv[k])
			r.inv.erase(k)
			var b3: String = DB.BASE.filter(func(b): return DB.C[b].tag == DB.C[k].tag)[0]
			r.inv[b3] = int(r.inv.get(b3, 0)) + n3 * 4
	for i in r.board.size():
		if r.board[i] != null and (DB.C[r.board[i]].tier == 2 or DB.C[r.board[i]].kind == "retired"):
			r.board[i] = null
	if int(r.tickets.get("2", 0)) > 0:
		var n2 := int(r.tickets["2"])
		r.tickets.erase("2")
		for p in no_empty_tier([{"t": 2, "n": n2}]):
			r.add_ticket(p.t, p.n)
	return r


static func delete_save() -> void:
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(SAVE_PATH)


# ───────── 점검용 —— 사람 대신 단순한 규칙으로 한 페이즈를 진행한다 (tests/game.gd · --gplay) ─────────

static var dev_snap_on := false
static var dev_snap: Array = []

func dev_autoplay() -> void:
	if over != null:
		return
	bot_prepare()
	if is_tour_phase():
		if tour == null:
			init_tour()
		while over == null:
			_dev_fight(start_tour())
			if over == null:
				tour_advance()
		return
	var q := start_quest()
	if dev_snap_on:      # 점검용 —— 토벌 직전 내 편성 (tests/quest_tune --snap)
		dev_snap.append({"d": day, "p": phase, "a": q.a.duplicate(true)})
	_dev_fight(q)
	if over != null:
		return
	_dev_spend()
	_dev_fight(start_pvp())
	if dev_log: PlayLog.phase_end(self)
	advance()
	if dev_log and over != null: PlayLog.over(self)


## 봇 플레이 —— 사람 대신 이 판의 자산으로 한 단계를 준비한다: 징집 · 선택권 · 배급 · 유니크 보급 · 조합 · 편성.
## 점검용 자동 진행(dev_autoplay)과 온라인 방(room.gd)의 무응답 플레이어 대행이 같이 쓴다 (11/7 멀티플레이).
## full 이 false 면 '행동은 했지만 끝내지 못한' 사람 몫만 채운다 —— 공짜 징집 · 배급과 빈 편성판. 선택권 · 조합은 그대로 둔다
func bot_prepare(full := true) -> void:
	if not drawn and draws_n() > 0:
		do_draw()
	if not picked:
		begin_picks("phase")
	if not granted and not grant_list().is_empty():
		random_grant()
	if not full:
		if placed() == 0:
			auto_deploy()
		return
	if not uniq_offer.is_empty():
		# 11/3 신화에 가장 가까운 유니크를 고른다 (예전엔 첫 번째 —— 신화를 한 번도 못 만들었다)
		var bu: String = uniq_offer[0]
		var bs := 999
		for id in uniq_offer:
			for k in DB.C:
				if DB.C[k].tier >= 8 and not DB.is_foe(k) and need_item(k) == id:
					var s := _chain_miss(k)
					if s < bs:
						bs = s
						bu = id
		pick_unique(bu)
	_dev_spend()


static var dev_immortal := false   # 점검용 —— 자동 진행(--gplay · 봇 기준선)은 멸망하지 않는다 (11/5 사용자). 경고는 그대로 쌓인다
static var dev_log := false      # 점검용 —— 봇 자동 진행도 플레이 기록(PlayLog)에 남긴다 (사람 플레이와 비교할 기준선, tests/play_log_bot)


func _dev_fight(bt: Dictionary) -> void:
	if dev_log: PlayLog.battle_start(self, bt)
	var res := simulate(bt, [], policy_for(bt))
	if dev_log: PlayLog.battle_end(self, bt, res, 0.0, [], {})
	finish_battle(res)
	if dev_log: PlayLog.after_battle(self)


## 점검용 —— 신화 줄기(신화 · 그 불멸 · 그 전설)까지 모자란 재료 수
func _chain_miss(m: String) -> int:
	var n := miss_count(m)
	for x in DB.RECOF.get(m, []):
		if DB.C.has(str(x)) and have(str(x)) <= 0 and DB.RECOF.has(str(x)):
			n += miss_count(str(x))
	return n


## 점검용 —— 가방의 유니크로 만들 신화와 그 아래 줄기 재료 (선택권에서 먼저 고른다)
func _dev_chain() -> Dictionary:
	var out := {}
	if has_myth():
		return out
	for k in DB.C:
		if DB.C[k].tier >= 8 and not DB.is_foe(k) and need_item(k) != null and bag.has(need_item(k)):
			for x in DB.RECOF.get(k, []):
				out[str(x)] = true
				for y in DB.RECOF.get(str(x), []):
					out[str(y)] = true
	return out


func _dev_spend() -> void:
	var chain := _dev_chain()
	while ticket_left() > 0:
		# 조합에 가장 가까워지는 카드를 고른다 (11/2: 줄기 재편 뒤 아무 카드나 고르면 전설을 못 만든다 —— 사람처럼 노리고 고른다)
		var pl: Array = pickable(ticket_tiers()[0])
		var best := []
		var best_s := 999
		for k in pl:
			var sc := 99
			for o in used_in(k):
				if DB.C[o].tier < 8:
					sc = mini(sc, miss_count(o))
			if chain.has(k) and have(k) <= 0:
				sc -= 2
			if sc < best_s:
				best_s = sc
				best = [k]
			elif sc == best_s:
				best.append(k)
		pick(best[rng.randi() % best.size()])
	var made := true
	while made:
		made = false
		for t in range(8, 1, -1):
			for k in DB.by_tier(t):
				if can_forge(k):
					forge(k)
					made = true
	auto_deploy()
