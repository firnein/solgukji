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
const SKILL_LO := 1.08        # 봇 실력 계수 (11/2 난이도 상승: 0.98 ~ 1.38 → 1.08 ~ 1.45)
const SKILL_HI := 1.45
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
var strikes := 0
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
	if DB.D.UNIQUE_PHASES.any(func(x): return int(x) == p):      # JSON 숫자는 실수라 has(p) 는 늘 거짓이었다 (11/2)
		grade = "유니크"           # 정해진 아침에만 확정 지급 (11/2 사용자: 1 · 3 · 5일차 아침)
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


## 유니크 보급 (1 · 3 · 5일차 아침) —— 신화 재료 셋 중 하나를 고른다 (11/2 사용자).
## 군세와 상관없이 무작위 셋, 가방에 이미 있는 것은 빼고. 신화는 한 판에 하나뿐이라
## 일찍 받은 것으로 빨리 만들지, 3 · 5일차 보급을 기다릴지가 선택이 된다
func _offer_unique(cand: Array) -> void:
	cand = cand.filter(func(k): return not bag.has(k))
	var out := []
	while out.size() < 3 and not cand.is_empty():
		out.append(cand.pop_at(rng.randi() % cand.size()))
	uniq_offer = out
	if not out.is_empty():
		toasts.append(["유니크 보급 도착 · 신화 재료 %d개 중 하나를 고르시오" % out.size(), "gold"])


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


## 작전 —— 정책 문자열 (Battle tac:<고유기>:<군령>) 과 설명. 셋이 서로 물고 물리게 맞췄다 (11/1 측정, ±5%p)
const TACS := {
	"균형": {"pol": "tac:영리:영리", "d": "상대를 보고 돌격 · 방진을 고르고, 고유기는 값어치 있을 때 쓴다"},
	"맹공": {"pol": "tac:즉시:공세", "d": "군령 포인트를 들고 시작해 바로 돌격, 돌격 공격 +25% · 고유기는 차면 바로"},
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
		if DB.C[k].atk >= DB.C[k]["int"]:
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
	if day == 6:
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
	last_draw = []
	last_spoil = null
	if day > 6:
		over = {"win": true, "msg": "일주일을 살아남았다"}
		day = 6
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
	return bot_side(pv * BOT_PV_MUL, style, phase_idx(), rng)


## 봇 · 토벌 적 군세 —— 11/2 사용자: 너무 허접하다 → 장비를 끼우고(그 때 보급 등급으로, 사람보다 조금 많이) 덱에 맞는 작전을 쓴다
const BOT_PV_MUL := 1.08
const QUEST_PV_MUL := 1.2
static func bot_side(pv: float, style: String, p_idx: int, r: RandomNumberGenerator) -> Dictionary:
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
		foe = {"cards": cards, "form": q.form, "morale": int(q.get("morale", 100)),
			"equip": eq, "tac": recommend_tac(cards)[0]}      # 장비는 맞출 때 auto_place 자리 그대로 (같은 순서라 자리가 같다)
	else:
		var styles := ["물리", "지략", "균형"]
		foe = _bot_side(pv, styles[rng.randi() % 3])
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
	return RtBattle.make(bt.seed).run(bt.a.cards, bt.a.form, bt.a.morale, bt.a.equip,
		bt.b.cards, bt.b.form, bt.b.morale, bt.b.equip, bt.title, bt.foe, inputs, policy)


## 전투가 끝났다 —— 보상·경고·토너먼트 진행
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
	match bt.kind:
		"quest":
			quest_done = true
			if res.win:
				for p in no_empty_tier(DB.D.QUEST_REWARD[day]):
					add_ticket(int(p.t), int(p.n))
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
				add_ticket(4 if day >= 3 else 3, 1)
			else:
				my_l += 1
				if b: b.w += 1
				add_ticket(3 if day >= 3 else 2, 1)
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


func add_ticket(t: int, n: int) -> void:
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
	if not DB.C.has(k):
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
	"quest_done", "pvp_done", "tickets", "strikes", "last_draw", "last_item", "uniq_offer", "myth_made", "kiin_made", "last_spoil",
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
	for k in ["day", "phase", "strikes", "my_w", "my_l"]:
		set(k, int(get(k)))
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
	for i in r.board.size():
		if r.board[i] != null and DB.C[r.board[i]].tier == 2:
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

func dev_autoplay() -> void:
	if over != null:
		return
	if not drawn and draws_n() > 0:
		do_draw()
	if not picked:
		begin_picks("phase")
	if not granted and not grant_list().is_empty():
		random_grant()
	if not uniq_offer.is_empty():
		pick_unique(uniq_offer[0])
	_dev_spend()
	if is_tour_phase():
		if tour == null:
			init_tour()
		while over == null:
			var bt := start_tour()
			finish_battle(simulate(bt, [], policy_for(bt)))
			if over == null:
				tour_advance()
		return
	var q := start_quest()
	finish_battle(simulate(q, [], policy_for(q)))
	if over != null:
		return
	_dev_spend()
	var p := start_pvp()
	finish_battle(simulate(p, [], policy_for(p)))
	advance()


func _dev_spend() -> void:
	while ticket_left() > 0:
		# 조합에 가장 가까워지는 카드를 고른다 (11/2: 줄기 재편 뒤 아무 카드나 고르면 전설을 못 만든다 —— 사람처럼 노리고 고른다)
		var pl: Array = DB.by_tier(ticket_tiers()[0])
		var best := []
		var best_s := 999
		for k in pl:
			var sc := 99
			for o in used_in(k):
				if DB.C[o].tier < 8:
					sc = mini(sc, miss_count(o))
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
