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


## 손패의 늘 켜지는 카드 id (정렬)
static func own_of(hand: Dictionary) -> Array:
	var own := []
	for id in hand:
		if str(card(str(id)).get("kind", "")) == "passive" and is_on(str(id)):
			own.append(str(id))
	own.sort()
	return own


## 전투에 넘길 짐
static func payload(plan: Array, hand: Dictionary, perm: Dictionary) -> Dictionary:
	return {"p": clean(plan, hand), "own": own_of(hand), "perm": (perm.get("parts", []) as Array).duplicate(true)}


## 11/21 사용자 "다른 유저가 고른 군략과 버프(기병 속도 10%)도 나열" —— 남에게 보여도 되는 군략 상태 (3택1 로 고른 순간 확정이라 늘 공개).
## own = 늘 켜지는 카드 id · perm = 능력치 · 경제 카드 이름(Run.tk_perm.notes —— 병종 단련은 「병종 단련 (궁병)」) · hist = 지난 대전 계획(Run.tk_hist, 앞이 최근).
## 서버 방 정보 seats[].tk(Run.tk_pub) · 군략 현황 화면(tac_ui)이 쓴다. 단계 계획(p)은 여기 없다 —— 고르는 동안은 가린다 (Run.tk_plan_open)
static func pub(hand: Dictionary, perm: Dictionary, hist: Array) -> Dictionary:
	return {"own": own_of(hand), "perm": (perm.get("notes", []) as Array).duplicate(), "hist": hist.duplicate(true)}


## 상시 효과 줄 —— [{src: 출처 카드 이름, text: 효과(수치) 한 줄, kind: "늘" | "영구", n: 겹친 수}]. 같은 영구 카드를 여러 번 고르면 한 줄에 「×n」.
## own · perm 은 pub 과 같은 꼴 (믿지 않는다 —— 모르는 이름도 깨지지 않게 이름만 보인다)
static func buff_rows(own, perm) -> Array:
	var out := []
	for id in (own if own is Array else []):
		var sid := str(id)
		if CARDS.has(sid) or has(sid):
			out.append({"src": sid, "text": desc(sid).trim_prefix("[늘] "), "kind": "늘", "n": 1})
	var order := []
	var cnt := {}
	for nm in (perm if perm is Array else []):
		var s := str(nm)
		if not cnt.has(s):
			order.append(s)
		cnt[s] = int(cnt.get(s, 0)) + 1
	for s in order:
		var base: String = s.get_slice(" (", 0)
		var tag: String = s.get_slice(" (", 1).trim_suffix(")") if s.contains(" (") else ""
		var n := int(cnt[s])
		out.append({"src": base, "text": perm_text(base, tag) + (" ×%d" % n if n > 1 else ""), "kind": "영구", "n": n})
	return out


## 영구 효과 한 줄 —— 카드 설명에서 「(영구 …)」 꼬리를 떼고, 무작위 병종은 뽑힌 병종으로 (「병종 단련 (궁병)」 → 「궁병 공격 +8%」)
static func perm_text(base: String, tag := "") -> String:
	var t := desc(base)
	var cut := t.find(" (영구")
	if cut >= 0:
		t = t.substr(0, cut)
	if tag != "":
		t = t.replace("무작위 병종", tag)
	return t


## 카드가 더한 상성 규칙 {beats, draw_vs} —— 화면 미리보기용 (전투 안 판정 tac_rt._rules 와 같은 표)
static func rules(id: String) -> Dictionary:
	var out := {"beats": [], "draw_vs": []}
	if id == "":
		return out
	for part in card(id).get("fx", []):
		if str(part.get("k", "")) in ["beats", "draw_vs"]:
			out[str(part.k)].append_array(part.get("fams", []))
	return out


## 두 카드의 상성 미리보기 —— a 쪽에서 본 "win" · "lose" · "draw", 어느 한쪽이 비면 "" (무효 · 연환계는 전투 안에서만 본다)
static func preview(a: String, b: String) -> String:
	if a == "" or b == "" or not has(a) or not has(b):
		return ""
	return outcome(fams(a), fams(b), rules(a), rules(b))


## 짐이 비었나 (전투 처리를 아예 켜지 않는다)
static func empty_load(pl) -> bool:
	if not (pl is Dictionary):
		return true
	for id in norm(pl.get("p", [])):
		if id != "":
			return false
	return (pl.get("own", []) as Array).is_empty() and (pl.get("perm", []) as Array).is_empty()


## 11/15 지휘: 봇 · 토벌 우두머리 손패는 사람과 같은 규칙 —— 기본 3장 + 지난 날 수만큼 3택1(같은 offer, 정해진 씨앗)에서
## 군략 한 장씩(제시된 첫 군략 —— 경제 카드는 고르지 않는다). 그 손패 안에서만 계획을 짠다
static func sim_hand(cards: Array, days: int, sd: int) -> Dictionary:
	data()
	var hand := {}
	for id in RULE.start:
		hand[str(id)] = 1
	var r := RandomNumberGenerator.new()
	r.seed = sd
	for d in maxi(0, days):
		for id in offer(cards, hand, 2, r):
			if str(card(id).get("kind", "")) == "plan" or str(card(id).get("kind", "")) == "passive":
				hand[id] = int(hand.get(id, 0)) + 1
				break
	return hand


## 손패 짐 —— 계획(쏠림 가중 + 30% 무작위) + 늘 켜지는 카드
static func hand_load(cards: Array, hand: Dictionary, r: RandomNumberGenerator) -> Dictionary:
	var own := hand.keys().filter(func(id): return str(card(id).get("kind", "")) == "passive")
	own.sort()
	return {"p": bot_plan(cards, hand.keys(), r, hand), "own": own, "perm": []}


## (옛) 봇 · 토벌 적이 쓸 수 있는 카드 —— 11/15 지휘로 sim_hand 를 쓴다. 점검용으로만 남김 —— 페이즈 번호(p_idx)가 오를수록 높은 등급까지 (사람이 하루 한 장씩 느는 것과 비슷하게)
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
## 11/22 econ = false 면 군략만 (연구는 res_offer 로 따로 —— 아침 군략 3택1 → 연구 3택1). 봇 손패(sim_hand)는 예전 꼴 그대로(같은 씨앗 순서)
static func offer(board: Array, owned: Dictionary, n_tac: int, r: RandomNumberGenerator, econ := true) -> Array:
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
	if not econ:
		return out
	var ek := ECON.keys()
	ek.sort()
	out.append(ek[r.randi() % ek.size()])
	return out


# ───────── 11/22 연구 트리 (tactics.json econ —— br 갈래 · req 앞 단계 · max 횟수(0 = 끝없이, 없으면 1) · cond 덱 조건) ─────────

## 연구 하나를 지금 후보에 올릴 수 있나 —— done = 고른 연구 id -> 횟수 (Run.rs_done)
static func res_ok(id: String, done: Dictionary, tags: Array, facs: Array) -> bool:
	data()
	if not ECON.has(id):
		return false
	var c: Dictionary = ECON[id]
	var mx := int(c.get("max", 1))
	if mx > 0 and int(done.get(id, 0)) >= mx:
		return false
	for q in c.get("req", []):
		if int(done.get(str(q), 0)) <= 0:
			return false
	if c.has("cond"):
		var cd: Dictionary = c.cond
		if cd.has("tag") and tags.count(str(cd.tag)) < 3:
			return false
		if cd.has("fac") and facs.count(str(cd.fac)) < 4:
			return false
	return true


## 연구 3택1 —— 열린 연구 중 n 개 (겹치지 않게). 앞 단계를 고르고 막 열린 다음 단계(req 있음)는 두 배 무게
static func res_offer(board: Array, done: Dictionary, n: int, r: RandomNumberGenerator) -> Array:
	data()
	var tags := deck_tags(board)
	var facs := []
	for k in board:
		if k != null and DB.C.has(str(k)):
			facs.append(str(DB.C[str(k)].fac))
	var cand := []
	var ek := ECON.keys()
	ek.sort()
	for id in ek:
		if res_ok(str(id), done, tags, facs):
			cand.append(str(id))
	var out := []
	for i in n:
		var tot := 0.0
		for id in cand:
			tot += 2.0 if ECON[id].has("req") else 1.0
		if cand.is_empty():
			break
		var roll := r.randf() * tot
		var pick: String = cand[cand.size() - 1]
		for id in cand:
			roll -= 2.0 if ECON[id].has("req") else 1.0
			if roll <= 0.0:
				pick = id
				break
		out.append(pick)
		cand.erase(pick)
	return out


## 이 연구를 고르면 열리는 다음 단계 이름 (카드 덧말)
static func res_next(id: String) -> Array:
	data()
	var out := []
	for k in ECON:
		if (ECON[k].get("req", []) as Array).has(id):
			out.append(str(k))
	out.sort()
	return out


## 연구인가 (econ 목록)
static func is_res(id: String) -> bool:
	data()
	return ECON.has(id)


## 이 카드 계열이 이기는 계열 —— 카드 화면의 「우세」 줄. 11/25 카드가 더한 규칙(천리행군 · 십면매복의 beats)까지 본다
static func strong(id: String) -> Array:
	data()
	var out := []
	var mine := fams(id)
	if mine.is_empty():
		return out
	for f in FAMS:
		if not mine.has(f) and outcome(mine, [f], rules(id), {}) == "win":
			out.append(f)
	return out


## 이 카드 계열을 이기는 계열 —— 「열세」 줄 (둘인 카드는 한쪽이 막아 주는 계열을 뺀다).
## 11/25 카드가 더한 규칙(원진 · 정공법 … 의 draw_vs)으로 비기는 계열도 뺀다 —— 예전엔 원진에도 「열세 기동」이 떴다
static func weak(id: String) -> Array:
	data()
	var mine := fams(id)
	var out := []
	for f in FAMS:
		if mine.has(f) or mine.is_empty():
			continue
		if outcome(mine, [f], rules(id), {}) == "lose":
			out.append(f)
	return out


## 11/25 받아치기 배치 —— 상대 단계 카드(공개 · 봇 · 우두머리 계획, 가렸으면 지난 대전 같은 단계)를 보고 내 손패에서 상성으로 이기는 카드를 단계마다 놓는다.
## foe = 단계 셋의 상대 카드 id (모르면 ""). 이미 이기는 칸은 그대로, 이길 카드가 없으면 지는 칸만 비기는 카드로 바꾼다(없으면 그대로).
## 규칙(전투당 한 번 · 전설 한 장 · 단계 전용)은 plan_block 으로 —— 앞 단계부터 차례로 정한다. 같은 결과면 등급이 높은 카드, 같은 등급이면 이름 순
static func counter_plan(plan: Array, hand: Dictionary, foe: Array) -> Array:
	var out := norm(plan)
	var f := norm(foe)
	var rank := {"lose": 0, "": 1, "draw": 1, "win": 2}
	for i in STAGES:
		var fid := str(f[i])
		if fid == "" or not has(fid) or fams(fid).is_empty():
			continue
		var cur := str(out[i])
		var now := preview(cur, fid) if cur != "" else ""
		if now == "win":
			continue
		var best := ""
		var best_r := int(rank[now])
		var best_g := -1
		var ids: Array = hand.keys()
		ids.sort()
		for id in ids:
			var sid := str(id)
			if sid == cur or plan_block(out, hand, i, sid) != "":
				continue
			var r := int(rank[preview(sid, fid)])
			var g := int(card(sid).get("g", 0))
			if r > best_r or (r == best_r and best != "" and g > best_g):
				best = sid
				best_r = r
				best_g = g
		if best != "" and best_r > int(rank[now]):
			out[i] = best
	return out


## 11/25 연구 단계 —— 앞 단계(req) 깊이: 0 초급 · 1 중급 · 2 이상 고급. 사용자 "연구 연계는 초급 → 중급 → 고급 식으로 다른 색상으로 표기"
const RES_LV_N := ["초급", "중급", "고급"]
const RES_LV_C := [Color("#5FAE8C"), Color("#5E9BE6"), Color("#B57BE8")]      # 청록 → 청 → 자. 군략 등급색(회 · 주황 · 보라 · 빨강)과 따로 읽히게 밝은 쪽으로
static func res_level(id: String) -> int:
	data()
	var d := 0
	var cur := id
	while ECON.has(cur) and not (ECON[cur].get("req", []) as Array).is_empty() and d < 4:
		cur = str(ECON[cur].req[0])
		d += 1
	return mini(d, RES_LV_N.size() - 1)


static func res_col(id: String) -> Color:
	return RES_LV_C[res_level(id)]


## 이 연구가 든 갈래 줄 —— 맨 앞 단계부터 끝까지 (명마 → 양마 번식 → 서량 마구). 이어진 단계가 없으면 [id]
static func res_chain(id: String) -> Array:
	data()
	if not ECON.has(id):
		return [id]
	var root := id
	var guard := 0
	while not (ECON[root].get("req", []) as Array).is_empty() and guard < 6:
		root = str(ECON[root].req[0])
		guard += 1
	var out := [root]
	var cur := root
	while guard < 12:
		var nx := res_next(cur)
		if nx.is_empty():
			break
		cur = str(nx[0])
		out.append(cur)
		guard += 1
	return out


## 한 줄 설명
static func desc(id: String) -> String:
	return str(card(id).get("d", ""))


## 등급 이름 · 색
static func grade_name(id: String) -> String:
	var g := int(card(id).get("g", -1))
	return ("%s 연구 · %s" % [RES_LV_N[res_level(id)], str(card(id).get("br", ""))] if is_res(id) else "능력치 · 경제") if g < 0 else GRADE_N[g]


static func grade_col(id: String) -> Color:
	var g := int(card(id).get("g", -1))
	if g < 0:
		return res_col(id) if is_res(id) else DB.PAL.jade
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
