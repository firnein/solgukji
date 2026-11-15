extends RefCounted
## 군략 카드 규칙 (11/15 1차 —— docs/군략_카드_초안.md)
##
## 표는 data/tactics.json. 여기는 전투 밖 규칙만 —— 계열 · 상성 · 덱 쏠림 · 계획 검사 · 봇 계획 · 3택1 뽑기 · 설명.
## 전투 안 처리는 scripts/tac_rt.gd. class_name 없이 preload 로 쓴다 (낡은 .godot 캐시에서도 이름을 찾게 —— Room 의 RoomLog 와 같은 까닭)
##
## 계획(plan) = 단계 세 칸의 카드 id 배열 ["돌격", "", "방진"] (빈 글 = 없음).
## 전투에 넘기는 짐(payload) = {"p": 계획, "own": 늘 켜지는(passive) 카드 id, "perm": 영구 효과 부품} —— Run._my_side 의 "plan".

const STAGES := 3
const GRADE_N := ["기본", "고급", "희귀", "전설"]
const GRADE_TIER := [1, 3, 4, 5]          # 등급색은 장수 등급색을 빌린다 (DB.TIER)
const FAMS := ["정면", "기동", "수비", "원거리", "책략"]

static var _d := {}
static var CARDS := {}       # id -> 카드 (군략 · 늘 · 즉시)
static var ECON := {}        # id -> 능력치 · 경제 카드
static var RULE := {}
static var FAM := {}


static func data() -> Dictionary:
	if _d.is_empty():
		var f := FileAccess.open("res://data/tactics.json", FileAccess.READ)
		_d = JSON.parse_string(f.get_as_text())
		RULE = _d.rule
		FAM = _d.fam
		for c in _d.cards:
			c["g"] = int(c.g)
			CARDS[str(c.id)] = c
		for c in _d.econ:
			c["g"] = -1
			c["kind"] = "econ"
			c["fam"] = ""
			ECON[str(c.id)] = c
	return _d


static func card(id: String) -> Dictionary:
	data()
	if CARDS.has(id):
		return CARDS[id]
	return ECON.get(id, {})


static func has(id: String) -> bool:
	data()
	return CARDS.has(id) or ECON.has(id)


static func is_on(id: String) -> bool:
	var c := card(id)
	return not c.is_empty() and not bool(c.get("off", false))


## 단계 칸에 놓는 카드인가
static func placeable(id: String) -> bool:
	var c := card(id)
	return not c.is_empty() and str(c.get("kind", "")) == "plan" and not bool(c.get("off", false))


## 계열 목록 —— 계열 없음은 [], 호표기는 둘
static func fams(id: String) -> Array:
	var c := card(id)
	if c.is_empty():
		return []
	var f = c.get("fam", "")
	if f is Array:
		return f
	return [] if str(f) == "" else [str(f)]


## 표시용 계열 한 글 ("정면" · "정면·기동" · "")
static func fam_text(id: String) -> String:
	return "·".join(fams(id))


## a 계열이 b 계열을 이기는가 (표 그대로)
static func beats(a: String, b: String) -> bool:
	data()
	return FAM.has(a) and (FAM[a].beat as Array).has(b)


## 한 단계 상성 —— a 쪽에서 본 "win" · "lose" · "draw".
## fa · fb 는 계열 목록(둘이면 유리한 쪽), xa · xb 는 카드가 더한 규칙 {beats: [...], draw_vs: [...]}
static func outcome(fa: Array, fb: Array, xa := {}, xb := {}) -> String:
	if fa.is_empty() or fb.is_empty():
		return "draw"
	# 둘(호표기)이면 그쪽이 유리한 계열을 고른다 —— 상대의 계열마다 a 의 최선을 구하고, 그 가운데 a 에게 가장 나쁜 것
	var rank := {"lose": 0, "draw": 1, "win": 2}
	var worst := "win"
	for b in fb:
		var mine := "lose"
		for a in fa:
			var o := _one(a, b, xa, xb)
			if rank[o] > rank[mine]:
				mine = o
		if rank[mine] < rank[worst]:
			worst = mine
	return worst


static func _one(a: String, b: String, xa: Dictionary, xb: Dictionary) -> String:
	if a == b:
		return "draw"
	var aw := beats(a, b) or (xa.get("beats", []) as Array).has(b)
	var bw := beats(b, a) or (xb.get("beats", []) as Array).has(a)
	if aw and bw:
		return "draw"
	if aw:
		return "draw" if (xb.get("draw_vs", []) as Array).has(a) else "win"
	if bw:
		return "draw" if (xa.get("draw_vs", []) as Array).has(b) else "lose"
	return "draw"


## 덱 쏠림 배율 —— 효과 × (0.7 + 0.6 × 그 계열 쏠림 병종 비율). 계열 없음은 1. 둘이면 큰 쪽
static func bias(fs: Array, tags: Array) -> float:
	data()
	if fs.is_empty() or tags.is_empty():
		return 1.0
	var r := 0.0
	for f in fs:
		if not FAM.has(f):
			continue
		var n := 0
		for t in tags:
			if (FAM[f].tags as Array).has(t):
				n += 1
		r = maxf(r, float(n) / float(tags.size()))
	return float(RULE.bias_lo) + float(RULE.bias_span) * r


## 덱의 병종 목록 (빈 칸 · 모르는 id 는 빼고)
static func deck_tags(cards: Array) -> Array:
	var out := []
	for k in cards:
		if k != null and DB.C.has(str(k)):
			out.append(str(DB.C[str(k)].tag))
	return out


## 그 계열 쏠림 비율 (0 ~ 1)
static func fam_ratio(f: String, tags: Array) -> float:
	data()
	if not FAM.has(f) or tags.is_empty():
		return 0.0
	return float(tags.filter(func(t): return (FAM[f].tags as Array).has(t)).size()) / float(tags.size())


## 계획을 늘 세 칸으로 (옛 저장 · 짧은 배열 · null)
static func norm(plan) -> Array:
	var out := ["", "", ""]
	if plan is Array:
		for i in mini(STAGES, plan.size()):
			out[i] = "" if plan[i] == null else str(plan[i])
	return out


## i 칸에 id 를 놓을 수 있나 —— 까닭 한 줄 ("" 이면 된다). hand = id -> 가진 수
## 기본 카드는 여러 단계에 겹쳐 놓을 수 있고, 고급 이상은 전투당 한 번(가진 수만큼), 전설은 전투당 한 장. 단계 전용 · 연환계(3단계 금지)
static func plan_block(plan: Array, hand: Dictionary, i: int, id: String) -> String:
	if i < 0 or i >= STAGES:
		return "칸이 없다"
	if id == "":
		return ""
	if not placeable(id):
		return "단계에 놓는 카드가 아니다"
	if int(hand.get(id, 0)) <= 0:
		return "가지지 않은 카드다"
	var c := card(id)
	if c.has("stage") and int(c.stage) != i + 1:
		return "%d단계 전용이다" % int(c.stage)
	if bool(c.get("link", false)) and i == STAGES - 1:
		return "연환계는 3단계에 놓을 수 없다"
	var g := int(c.g)
	if g == 0:
		return ""
	var used := 0
	var legend := 0
	for j in STAGES:
		if j == i or plan[j] == "":
			continue
		if plan[j] == id:
			used += 1
		if int(card(plan[j]).get("g", 0)) == 3:
			legend += 1
	if used >= int(hand.get(id, 0)):
		return "고급 이상은 전투당 한 번"
	if g == 3 and legend > 0:
		return "전설은 전투당 한 장"
	return ""


## 계획 정리 —— 못 놓는 칸은 비운다 (손패가 바뀌었거나 옛 저장)
static func clean(plan: Array, hand: Dictionary) -> Array:
	var out := ["", "", ""]
	var p := norm(plan)
	for i in STAGES:
		if p[i] != "" and plan_block(out, hand, i, p[i]) == "":
			out[i] = p[i]
	return out


## 전투에 넘길 짐
static func payload(plan: Array, hand: Dictionary, perm: Dictionary) -> Dictionary:
	var own := []
	for id in hand:
		if str(card(str(id)).get("kind", "")) == "passive" and is_on(str(id)):
			own.append(str(id))
	own.sort()
	return {"p": clean(plan, hand), "own": own, "perm": (perm.get("parts", []) as Array).duplicate(true)}


## 짐이 비었나 (전투 처리를 아예 켜지 않는다)
static func empty_load(pl) -> bool:
	if not (pl is Dictionary):
		return true
	for id in norm(pl.get("p", [])):
		if id != "":
			return false
	return (pl.get("own", []) as Array).is_empty() and (pl.get("perm", []) as Array).is_empty()


## 봇 · 토벌 적이 쓸 수 있는 카드 —— 페이즈 번호(p_idx)가 오를수록 높은 등급까지 (사람이 하루 한 장씩 느는 것과 비슷하게)
static func bot_pool(p_idx: int) -> Array:
	data()
	var top := 0 if p_idx < 2 else (1 if p_idx < 7 else (2 if p_idx < 13 else 3))
	var out := []
	for id in CARDS:
		var c: Dictionary = CARDS[id]
		if placeable(id) and not c.has("cond") and int(c.g) <= top:
			out.append(id)
	out.sort()
	return out


## 봇 계획 —— 덱 쏠림이 큰 계열 카드를 고를 확률을 높이고, 30% 는 무작위. 규칙(전투당 한 번 · 전설 한 장 · 단계 전용)은 사람과 같다
## pool = 고를 수 있는 카드 id (봇은 bot_pool, 대행하는 사람은 제 손패) · hand = 가진 수 (없으면 모두 1)
static func bot_plan(cards: Array, pool: Array, r: RandomNumberGenerator, hand := {}) -> Array:
	pool = pool.filter(func(id): return placeable(id))
	pool.sort()
	hand = hand.duplicate()
	if hand.is_empty():
		for id in pool:
			hand[id] = 1
	var tags := deck_tags(cards)
	var plan := ["", "", ""]
	for i in STAGES:
		var ok := pool.filter(func(id): return plan_block(plan, hand, i, id) == "")
		if ok.is_empty():
			continue
		if r.randf() >= float(RULE.random_bot):
			var w := []
			var tot := 0.0
			for id in ok:
				var fs := fams(id)
				var x := 0.15
				for f in fs:
					x = maxf(x, 0.15 + fam_ratio(f, tags) * fam_ratio(f, tags) * 4.0)
				w.append(x)
				tot += x
			var roll := r.randf() * tot
			for j in ok.size():
				roll -= w[j]
				if roll <= 0.0:
					plan[i] = ok[j]
					break
			if plan[i] == "":
				plan[i] = ok[ok.size() - 1]
		else:
			plan[i] = ok[r.randi() % ok.size()]
	return plan


## 3택1 뽑기 —— 군략 n_tac 장(등급 확률 · 병종 · 세력 조건) + 능력치 · 경제 1장. owned = 이미 가진 군략(고급 이상은 다시 안 나온다)
static func offer(board: Array, owned: Dictionary, n_tac: int, r: RandomNumberGenerator) -> Array:
	data()
	var tags := deck_tags(board)
	var facs := []
	for k in board:
		if k != null and DB.C.has(str(k)):
			facs.append(str(DB.C[str(k)].fac))
	var pool := {1: [], 2: [], 3: []}
	for id in CARDS:
		var c: Dictionary = CARDS[id]
		if bool(c.get("off", false)) or int(c.g) <= 0 or int(owned.get(id, 0)) > 0:
			continue
		if c.has("cond"):
			var cd: Dictionary = c.cond
			if cd.has("tag") and tags.count(str(cd.tag)) < 3:
				continue
			if cd.has("fac") and facs.count(str(cd.fac)) < 4:
				continue
		pool[int(c.g)].append(id)
	for g in pool:
		pool[g].sort()
	var out := []
	var w: Array = RULE.offer_w
	for n in n_tac:
		var cand := []
		var tot := 0.0
		for g in [1, 2, 3]:
			var left: Array = pool[g].filter(func(id): return not out.has(id))
			if not left.is_empty():
				cand.append([g, left])
				tot += float(w[g])
		if cand.is_empty():
			break
		var roll := r.randf() * tot
		var pick: Array = cand[cand.size() - 1][1]
		for e in cand:
			roll -= float(w[e[0]])
			if roll <= 0.0:
				pick = e[1]
				break
		out.append(pick[r.randi() % pick.size()])
	var ek := ECON.keys()
	ek.sort()
	out.append(ek[r.randi() % ek.size()])
	return out


## 한 줄 설명
static func desc(id: String) -> String:
	return str(card(id).get("d", ""))


## 등급 이름 · 색
static func grade_name(id: String) -> String:
	var g := int(card(id).get("g", -1))
	return "능력치 · 경제" if g < 0 else GRADE_N[g]


static func grade_col(id: String) -> Color:
	var g := int(card(id).get("g", -1))
	if g < 0:
		return DB.PAL.jade
	return DB.TIER[GRADE_TIER[g]].c


## 1차에 넣은 카드 수 · 뺀 카드 (작업현황 · 점검용)
static func counts() -> Dictionary:
	data()
	var on := 0
	var off := []
	for id in CARDS:
		if bool(CARDS[id].get("off", false)):
			off.append(id)
		else:
			on += 1
	return {"on": on, "econ": ECON.size(), "off": off}
