extends RefCounted
## 장수 키트 Q · W · E · R · P (11/27 사용자)
##   "기존 특기들을 다 배제하고, 고유기를 가진 등급의 일반기술을 q,w,e · 고유기를 r · 고유 특기는 p.
##    쟤가 q 스킬이 발동됐구나, e 가 발동됐구나를 알 수 있어야 함. 일단은 신화 장수에 대해서만."
##   (저녁) "W · E 기술도 장수별로 고유하게 · 강화를 능력치가 아니라 다양한 효과로(단순 파워업이 아니라) · 강화는 1번씩만, 장수당 1개 많으면 2개
##    · 자리 개념이 아니라 그냥 1~2개를 강화하면 바로 끝남 (QW 관우가 QW 장각을 만났을 때 QE 관우로 바꿔 카운터 치는 것이 아니라,
##      더 늦게 조합되는 WE 장비로 QW 장각을 약화시키는 개념)" + 기술이 1~2초마다 터져 알아볼 수 없다 → Q · W · E 는 재사용 대기(초)로 드물게 · 한 번이 크게
##
## 칸(slot)
##   q · w · e = 일반기술 (data/kit.json 의 그 칸 —— new 가 아니면 카드의 sks[0] · [1] · [2] 를 그대로, 주기만 cd)     r = 고유기(DB.ult_of)     p = 고유 특기 (passives.json traits 의 unique: true 한 개)
##   키트 장수(on)는 일반 특기 · 일반 단체 특기를 쓰지 않는다 —— 고유 특기와 그 이름의 단체 효과만 남는다 (DB.passives_of)
##
## 자료: data/kit.json —— 카드 id → 칸 → {n 이름, cd 재사용 대기(초 · q·w·e), d 하는 일, new, up: {n 강화 이름, d 강화하면 붙는 효과}} + 엔진 필드(cond · mul · sk · fx —— 파일 머리 _설명)
## 강화 상태 (Run.kit): { 카드 id: ["q", "w"] }  강화한 칸 목록 (고른 차례대로, 최대 MAX_UP 칸 · 칸마다 한 번 · 되돌릴 수 없다)
##   옛 형식(칸 → 강화 id 배열)은 norm 이 새 형식으로 바꾼다. 전투에는 정책과 같은 길로: policy["kit"] = {"A": 강화 상태, "B": 강화 상태}
##   (Battle._setup 이 norm 으로 거른 값으로 바꿔 둔다 —— 결과의 policy 에도 남는다)
##
## 전투 (scripts/kit_rt.gd —— 실시간 엔진에서만. 턴 엔진은 키트 기술을 예전 충전 방식으로 쓴다)
##   재사용 대기: 키트 장수의 q · w · e 는 충전 대신 기술마다 다음 사용 시각(Unit.sk_next). 차례에 준비된 기술이 여럿이면 가장 오래 기다린 것 하나.
##     개전 때는 cd 의 절반부터 센다. 봉인이면 못 쓴다 · 도적에게 맞으면 0.3초씩 밀린다. sk.free 인 기술은 닿는 적이 없어 기다리는 차례에도 쓴다
##   사건: 키트 장수의 기술 사건(fx "skill" —— 카드 · 키트 기술을 쓴 것만)에 "slot": "q"|"w"|"e" (고유 동작 기술이면 "act": 동작 이름도),
##     고유기 사건(fx "ult" · 예고 "ult_warn" · 인연 합류 "ult_join")에 "slot": "r", 개전 때 키트 장수마다 한 번 fx "passive" 사건에 "slot": "p",
##     개성 말풍선(sig_rt._say —— fx "buff" · "sig": true)에 "slot": "p". 그 칸을 강화했으면 모두 "up": true. 키트 장수가 아닌 부대의 사건에는 slot 이 없다
##   강화 효과가 실제로 발동하면 "kup": 강화 이름(up.n) —— 따로 사건이 있으면 fx "kup" {a: 그 장수, slot, up: true, kup, f: 대상(있으면)},
##     다시 쓰기(연참 · 난무)는 그 기술 사건에, 되살리기는 fx "heal" 사건에("revive": true), 막아 낸 상태이상은 fx "resist" 사건에 붙는다
##   결과 roster 의 키트 장수 줄에는 "kit": [강화한 칸 …]
##
## 바탕 배율(base_*)은 강화가 없어도 키트 장수 모두에게 —— 일반 특기를 뺀 만큼을 메운다 (tests/kit_measure 로 맞춘다)
##   불멸(스위치 IMMORTAL_ON) · 초월(TRANS_ON) · 기인(KIIN_ON)도 같은 바탕 배율을 쓴다 —— 고유기 수치는 DB.ult_of 가 등급 배율(tier7_scale · tier6_scale)로 이미 줄인다. 등급별로 달라야 하면 마지막 밸런스 때 나눈다
##
## class_name 없이 preload 로 쓴다 (낡은 .godot 캐시에서도 이름을 찾게 —— tactics.gd 와 같다):  const Kit := preload("res://scripts/kit.gd")

const SLOTS := ["q", "w", "e", "r", "p"]
const SLOT_N := {"q": "Q", "w": "W", "e": "E", "r": "R", "p": "P"}
const SLOT_KIND := {"q": "일반기술", "w": "일반기술", "e": "일반기술", "r": "고유기", "p": "고유 특기"}
## 칸 색 —— 전투 이펙트 · 딱지 · 화면 글이 모두 이 색을 쓴다 (칸을 색으로 알아본다)
const SLOT_COL := {"q": "#4aa8ff", "w": "#5fd36a", "e": "#b47aff", "r": "#ffd257", "p": "#ff9a4a"}
const CUR_N := "전공"                # 제 3의 재화 이름 (Run.merit)
const MAX_UP := 2
const UP_COST := [4, 6]              # 그 장수의 1 · 2번째 강화 값 (전공)

static var enabled := true           # 끄면 키트 장수가 없다 (예전 그대로 —— 비교 · 점검용)
static var min_tier := 8             # 이 등급 이상만 (11/27 "일단은 신화 장수에 대해서만")

## ★ 불멸 키트 스위치 (11/27 사용자 "불멸 장수들도 qwer 화 해줘, 적용은 플래그로 on/off —— 나중에 on 하면 한번에 적용되도록, 아직 실 패치는 하지 않을 생각")
##   켜는 곳은 여기 한 군데 —— true 로 바꾸면 불멸(7성 · 적 전용 · 은퇴 제외 · 고유기가 있는 카드 30명)이 한 번에 키트 장수가 된다:
##   Kit.on 이 참 → 기술 Q · W · E(data/kit.json 의 불멸 칸) · 재사용 대기 · 고유기 R · 고유 특기 P · 강화 UI · 전공 · 전투 딱지 · 이펙트가 신화와 같은 길로 따라온다.
##   false 면 불멸 칸 자료를 읽지 않는다 (cell 이 빈 사전) —— 전투 결과 · 화면이 예전 그대로.
##   온라인은 서버와 클라이언트가 같은 값을 써야 한다 (정책 kit 은 양쪽이 Kit.norm 으로 거른다) —— 이 상수를 바꾼 빌드를 서버 · APK · EXE 에 함께 낸다
const IMMORTAL_ON := false
const IMMORTAL_TIER := 7
static var immortal := IMMORTAL_ON   # 점검(tests/kit_engine --immortal)만 바꾼다 —— 게임은 위 상수를 따른다

## ★ 초월 · 기인 키트 스위치 (11/27 사용자 "기인, 초월도 적용해볼래? 불멸처럼 플래그로") —— 불멸 스위치와 서로 독립, 등급마다 따로
##   TRANS_ON: 초월(6성 카드 · 적 전용 · 은퇴 제외 · 고유기가 있는 15명)   KIIN_ON: 기인(kind "kiin" —— 카드 등급은 전설 5, 고유기가 있는 22명)
##   true 로 바꾸면 그 등급이 한 번에 키트 장수가 된다 (data/kit.json 의 그 등급 칸 · 표는 docs/초월기인_키트표.md). false 면 그 칸 자료를 읽지 않는다 —— 예전 그대로.
##   고유기 수치는 DB.ult_of 가 초월 배율(tier6_scale)로 줄인다 (기인도 같다 —— 카드 등급 5 는 tier7_scale 쪽이 아니다)
const TRANS_ON := false
const TRANS_TIER := 6
static var trans := TRANS_ON         # 점검(tests/kit_engine --trans)만 바꾼다
const KIIN_ON := false
static var kiin := KIIN_ON           # 점검(tests/kit_engine --kiin)만 바꾼다

## ★ 강화는 신화만 (11/27 사용자 "qwer 이 적용된 모든 장수는 ui 에 qwer 반영, 단 신화를 제외한 등급에는 강화할 수 없음")
##   불멸 · 초월 · 기인은 스위치를 켜면 키트 장수(Q · W · E · R · P 다섯 줄 · 재사용 대기 · 딱지)가 되지만 강화(전공)는 없다 —— can_up 이 거짓.
##   강화 규칙의 모든 길이 can_up 을 본다: up_block(Run.kit_up · 서버 검증) · up_cost(전공 값) · norm(정책 · 저장 · 상대 강화) · ups_of(화면 표시)
const UP_TIER := 8
static var up_any := false           # 점검(tests/kit_engine --immortal · --trans · --kiin)만 바꾼다 —— 켜면 키트 장수 모두 강화 가능 (그 등급의 강화 엔진 길을 계속 점검)

## 바탕 배율 —— 키트 장수는 일반 특기 · 일반 단체 특기를 쓰지 않아 그만큼 약해지고, 기술은 재사용 대기로 드물어진다. 강화가 없어도 늘 곱해 예전 세기에 맞춘다 (실제 대전 덱 —— tests/kit_measure)
##   base_sk 일반기술(q · w · e) 피해 배율 · base_ult 고유기(r) 타격 배율 · base_p 고유 특기(p) 수치 배율
##   base_sup 기술 · 고유기가 아군에게 주는 회복 · 강화 배율 (기술의 heal · tHeal · allyBuff, 고유기 아군 효과의 heal · morale · buff, 지속은 그대로)
static var base_sk := 1.08
static var base_ult := 1.4           # 11/27 사용자 "고유기를 좀 덜 나가게 · 대신 파급력은 좀 올려" —— 1.08 → 1.4 (아래 ult_gauge · ult_charges · ult_cap_bonus 와 함께)
## 고유기 리듬 (11/27) —— 일반기술 대기(잽 3~4 · 주력 5~6 · 큰 수 8~10 · 결정타 12~14초)보다 드물게, 한 방은 크게
##   ult_gauge 기가 차는 속도 배율 (첫 고유기 12초 안팎 → 16초 안팎) · ult_charges 한 판 최대 횟수 (신화 3 → 2) · ult_cap_bonus 고유기 한 방 상한(Battle.ult_cap)에 더하는 몫
static var ult_gauge := 0.75
static var ult_charges := 2
static var ult_cap_bonus := 0.1
static var base_p := 1.0
static var base_sup := 1.2

static var _data := {}


static func data() -> Dictionary:
	if _data.is_empty():
		var f := FileAccess.open("res://data/kit.json", FileAccess.READ)
		if f != null:
			var d = JSON.parse_string(f.get_as_text())
			if d is Dictionary:
				_data = d
	return _data


## 이 등급이 키트 등급인가 —— min_tier 이상 (신화), 불멸 스위치가 켜졌으면 불멸(IMMORTAL_TIER)도, 초월 스위치가 켜졌으면 초월(TRANS_TIER)도 (기인은 card_on —— 등급이 아니라 카드 성격)
static func tier_on(t: int) -> bool:
	return t >= min_tier or (immortal and t == IMMORTAL_TIER) or (trans and t == TRANS_TIER)


## 이 카드가 키트 등급인가 —— 기인(kind "kiin")은 기인 스위치만 본다 (카드 등급과 무관), 그 밖은 tier_on
static func card_on(k) -> bool:
	if k == null or not DB.C.has(str(k)):
		return false
	var c: Dictionary = DB.C[str(k)]
	if str(c.get("kind", "")) == "kiin":
		return kiin
	return tier_on(int(c.tier))


## 키트 등급 설정을 한 값으로 —— 특기 캐시(DB.passives_of)가 이 값이 바뀌면 비운다 (끔 −1)
static func tier_key() -> int:
	return (min_tier * 8 + (1 if immortal else 0) + (2 if trans else 0) + (4 if kiin else 0)) if enabled else -1


## 키트 장수인가 (신화 —— 불멸 · 초월 · 기인 스위치가 켜졌으면 그 등급도) —— 적 전용 카드 · 은퇴 카드는 아니다
static func on(k) -> bool:
	if not enabled or k == null or not DB.C.has(str(k)):
		return false
	var c: Dictionary = DB.C[str(k)]
	if DB.is_foe(str(k)) or str(c.get("kind", "")) == "retired":
		return false
	return card_on(k) and DB.has_ult(str(k))      # (DB.ult_of 는 부를 때마다 깊은 사본을 만든다 —— 있는지만 묻는다)


## 강화할 수 있는 장수인가 —— 키트 장수이고 신화(UP_TIER 이상 · 기인 kind 는 아님). 불멸 · 초월 · 기인은 키트 장수여도 강화 없음
static func can_up(k) -> bool:
	if not on(k):
		return false
	if up_any:
		return true
	var c: Dictionary = DB.C[str(k)]
	return str(c.get("kind", "")) != "kiin" and int(c.tier) >= UP_TIER


## 고유 특기 이름 (없으면 "")
static func p_name(k: String) -> String:
	var lad = DB.PSV.ladder.get(DB.person(k))
	if lad == null:
		return ""
	var tier := int(DB.C[k].tier)
	for e in lad:
		if tier < int(e[1]) or (e.size() > 2 and tier > int(e[2])):
			continue
		if bool(DB.PSV.traits.get(e[0], {}).get("unique", false)):
			return str(e[0])
	return ""


## 그 장수 그 칸의 자료 —— {n, d, up: {n, d}, cd?, new?, …}. 없으면 빈 사전 (키트 장수가 아니거나 자료가 없다).
## 키트 등급이 아닌 카드(스위치가 꺼졌을 때의 불멸 · 초월 · 기인)의 자료는 없는 것으로 본다 —— 화면 · 기록이 그 칸 이름을 쓰지 않게
static func cell(k, slot: String) -> Dictionary:
	if not card_on(k):
		return {}
	var h = data().get(str(k))
	if not (h is Dictionary) or not (h.get(slot) is Dictionary):
		return {}
	return h[slot]


## 그 칸의 바탕 정의 —— {slot, kind: "sk"|"ult"|"p", name, src(전투가 쓰는 정의 · 고치지 말 것)}. 그 칸이 없으면 빈 사전.
## 이름은 data/kit.json 의 n (없으면 카드 기술 · 고유기 · 고유 특기 이름), src 는 q · w · e 면 skills_of 의 그 칸(바탕 배율이 든 사본)
static func slot_def(k: String, slot: String) -> Dictionary:
	if not DB.C.has(k):
		return {}
	var cl := cell(k, slot)
	match slot:
		"q", "w", "e":
			var i: int = ["q", "w", "e"].find(slot)
			var sks := skills_of(k)
			if i >= sks.size() or sks[i].is_empty():
				return {}
			return {"slot": slot, "kind": "sk", "name": str(sks[i].n), "src": sks[i]}
		"r":
			var u = ult_of(k)
			if u == null:
				return {}
			return {"slot": slot, "kind": "ult", "name": str(cl.get("n", u.name)), "src": u}
		"p":
			var pn := p_name(k)
			if pn == "":
				return {}
			return {"slot": slot, "kind": "p", "name": pn, "src": DB.PSV.traits[pn]}
	return {}


# ───────── 강화 상태 ─────────

## 강화한 칸 목록 (사본). 옛 형식이 들어와도 칸 목록으로 읽는다. 강화할 수 없는 장수(can_up 거짓 —— 신화가 아님)는 늘 빈 배열
static func ups_of(kit, k) -> Array:
	if not (kit is Dictionary) or not can_up(k):
		return []
	var v = kit.get(str(k))
	var out := []
	if v is Array:
		for s in v:
			if SLOTS.has(str(s)) and not out.has(str(s)):
				out.append(str(s))
	elif v is Dictionary:
		for s in SLOTS:
			if v.get(s) is Array and not (v[s] as Array).is_empty():
				out.append(s)
	return out.slice(0, MAX_UP)


static func is_up(kit, k, slot: String) -> bool:
	return ups_of(kit, k).has(slot)


## 그 장수의 다음 강화 값 (전공) —— 더 강화할 수 없으면 −1
static func up_cost(kit, k) -> int:
	if not can_up(k):
		return -1
	var n := ups_of(kit, k).size()
	return int(UP_COST[n]) if n < MAX_UP else -1


## 그 칸을 강화할 수 없는 까닭 ("" = 할 수 있다 —— 전공 · 보유 여부는 Run 이 본다)
static func up_block(kit, k, slot: String) -> String:
	if not on(k):
		return "키트 장수가 아니다"
	if not can_up(k):
		return "강화는 신화 장수만 할 수 있다"
	if cell(k, slot).is_empty():
		return "없는 칸이다"
	var have := ups_of(kit, k)
	if have.has(slot):
		return "이미 강화한 칸이다"
	if have.size() >= MAX_UP:
		return "이 장수는 %d칸을 모두 강화했다" % MAX_UP
	return ""


## 믿을 수 없는 강화 상태(옛 저장 · 옛 형식 · 클라이언트)를 새 형식으로 —— 모르는 카드 · 칸은 버리고 장수당 MAX_UP 칸까지
static func norm(kit) -> Dictionary:
	var out := {}
	if not (kit is Dictionary):
		return out
	for k in kit:
		if not can_up(k):      # 키트 장수가 아니거나 신화가 아니면 (불멸 · 초월 · 기인) 버린다
			continue
		var have := []
		for s in ups_of(kit, k):
			if not cell(k, s).is_empty():
				have.append(s)
		if not have.is_empty():
			out[str(k)] = have
	return out


# ───────── 전투에 적용 (원본은 고치지 않는다 —— 사본을 돌려준다) ─────────

## 기술 효과가 적을 때리는가 (피해 배율이 있다)
static func _hits(eff: Dictionary) -> bool:
	return float(eff.get("mult", 0.0)) > 0.0


## 그 장수의 일반기술 셋(q · w · e) —— 전투가 쓰는 사본 [{n, eff, cond, cd, slot, free?}]. 칸에 sk 가 있으면 그 새 기술, 없으면 카드의 그 차례 기술(mul 배 · cond 덮어쓰기).
## 바탕 배율(base_sk · base_sup)이 들어 있다. 화면도 이 사본의 수치를 보이면 엔진과 같다
static func skills_of(k: String) -> Array:
	var out := []
	if not DB.C.has(k):
		return out
	var sks: Array = DB.C[k].get("sks", [])
	for i in 3:
		var slot: String = SLOTS[i]
		var cl := cell(k, slot)
		var sk := {}
		if cl.get("sk") is Dictionary:
			var src: Dictionary = cl.sk
			sk = {"n": str(cl.get("n", "")), "eff": (src.get("eff", {}) as Dictionary).duplicate(true), "cond": str(src.get("cond", "always")), "psv": null, "cost": 1.0}
			if bool(src.get("free", false)):
				sk["free"] = true
			if src.has("start"):
				sk["start"] = float(src.start)
		elif i < sks.size():
			sk = (sks[i] as Dictionary).duplicate(true)
			if cl.has("n"):
				sk["n"] = str(cl.n)
			if cl.has("cond"):
				sk["cond"] = str(cl.cond)
			if cl.has("mul") and _hits(sk.eff):
				sk.eff["mult"] = float(sk.eff.mult) * float(cl.mul)
			if cl.has("sup"):
				_sup_skill(sk.eff, float(cl.sup))
			if cl.get("eff") is Dictionary:      # 카드 기술의 효과 값 덮어쓰기 (그 키만)
				for key in cl.eff:
					sk.eff[key] = (cl.eff[key] as Dictionary).duplicate(true) if cl.eff[key] is Dictionary else cl.eff[key]
		else:
			break
		sk["slot"] = slot
		sk["cd"] = float(cl.get("cd", 8.0))
		out.append(apply_skill(sk))
	return out


## 일반기술 한 개에 바탕 배율을 입힌 사본 (둘째 인자는 옛 강화 목록 —— 쓰지 않는다)
static func apply_skill(sk: Dictionary, _augs := []) -> Dictionary:
	var out: Dictionary = sk.duplicate(true)
	var eff: Dictionary = out.eff
	if base_sk != 1.0 and _hits(eff):
		eff["mult"] = float(eff.mult) * base_sk
	if base_sup != 1.0:
		_sup_skill(eff, base_sup)
	return out


## 기술이 아군에게 주는 회복 · 강화에 배율 (사기 회복 heal · 병력 치료 tHeal · 아군 강화 allyBuff)
static func _sup_skill(eff: Dictionary, x: float) -> void:
	if eff.has("heal"):
		eff["heal"] = float(eff.heal) * x
	if eff.has("tHeal"):
		eff["tHeal"] = float(eff.tHeal) * x
	if eff.has("allyBuff"):
		eff.allyBuff["amt"] = float(eff.allyBuff.amt) * x


## 고유기에 바탕 배율을 입힌 사본 (둘째 인자는 옛 강화 목록 —— 쓰지 않는다)
static func apply_ult(ult: Dictionary, _augs := []) -> Dictionary:
	var out: Dictionary = ult.duplicate(true)
	var effs: Array = out.get("eff", [])
	for e in effs:
		var t := str(e.get("t", ""))
		if t == "hit" and base_ult != 1.0:
			e["mult"] = float(e.get("mult", 0.0)) * base_ult
		elif t == "ally" and base_sup != 1.0:
			if e.has("heal"):
				e["heal"] = float(e.heal) * base_sup
			if e.has("morale"):
				e["morale"] = float(e.morale) * base_sup
			if e.has("buff"):
				e.buff["amt"] = float(e.buff.amt) * base_sup
	return out


## 그 장수의 고유기 —— 전투가 쓰는 사본 (바탕 배율 + 그 장수 r 칸의 mul: 타격 배율과 아군 효과(회복 · 사기 · 강화)에 곱한다). 고유기가 없으면 null
static func ult_of(k: String):
	var u = DB.ult_of(k)
	if u == null:
		return null
	var out := apply_ult(u)
	var x := float(cell(k, "r").get("mul", 1.0))
	if x != 1.0:
		for e in out.get("eff", []):
			var t := str(e.get("t", ""))
			if t == "hit":
				e["mult"] = float(e.get("mult", 0.0)) * x
			elif t == "ally":
				if e.has("heal"):
					e["heal"] = float(e.heal) * x
				if e.has("morale"):
					e["morale"] = float(e.morale) * x
				if e.has("buff"):
					e.buff["amt"] = float(e.buff.amt) * x
	return out


## 그 장수의 고유 특기 배율 —— 바탕 배율 × 그 장수 p 칸의 mul
static func p_mul_of(k) -> float:
	return base_p * float(cell(k, "p").get("mul", 1.0))


## 전투가 고유 특기에 곱하는 값 —— 바탕 배율. 주인에게 붙는 수치(p_scales 가 참인 키)와 단체 효과 세기(scale · fscale)에 곱한다 (인자는 옛 강화 목록 —— 쓰지 않는다)
static func p_mul(_augs := []) -> float:
	return base_p


## 그 고유 특기 키에 배율을 곱하는가 —— 켜고 끄는 깃발(익수 · 화선 · 연격 …)과 행동 키(표적 고르기 · 버티는 문턱 · 초 —— 글 없이 행동만 바꾸는 개성 키)는 그대로 둔다.
## 수치로 적는 키(치명 · 피해 + · 사기 · 저항 …)만 곱한다
static func p_scales(key: String) -> bool:
	if not (DB.PSV.flags as Array).has(key):
		return true      # 등급 배율을 받는 보통 수치
	var sig = load("res://scripts/sig_rt.gd")
	if not (sig.KEYS as Array).has(key):
		return false     # 원래 깃발 (passives.json flags —— 켬/끔 · 정수 값)
	var lab = DB.SIG_LABEL.get(key, sig.LABELS_SCHOLAR.get(key))
	return lab is Array and lab.size() > 1 and str(lab[1]) != ""      # 수치로 적는 개성 키만


## 고유 특기 수치 사전에 배율을 입힌 사본 (화면 설명용 —— 전투와 같은 값)
static func p_apply(m: Dictionary, _augs := []) -> Dictionary:
	var out: Dictionary = m.duplicate()
	var x := p_mul()
	if x != 1.0:
		for key in out:
			if p_scales(str(key)):
				out[key] = float(out[key]) * x
	return out


# ───────── 옛 이름 (11/27 낮의 '목록에서 골라 쌓는 강화') —— 걷어 냈다. 화면 · Run 이 새 함수(cell · ups_of · is_up · up_cost · up_block · norm)로 옮기면 지운다 ─────────
## 그동안 옛 호출이 스크립트 오류 없이 돌게 이름만 남긴다: 강화 표는 비었고(AUG), 붙일 수 있는 강화는 없으며(options · valid), 옛 형식 상태는 norm 이 새 형식으로 바꾼다
const MAX_LV := 1
const COST := UP_COST
const AUG := {}


## (옛) 그 칸의 강화 —— 강화한 칸이면 ["up"], 아니면 빈 배열
static func augs_of(kit, k: String, slot: String) -> Array:
	return ["up"] if is_up(kit, k, slot) else []


static func lv(kit, k: String, slot: String) -> int:
	return 1 if is_up(kit, k, slot) else 0


## (옛) 다음 강화 값 —— 옛 방식으로는 더 강화할 수 없다
static func next_cost(_have: Array) -> int:
	return -1


static func valid(_k: String, _slot: String, _aug: String, _have: Array) -> bool:
	return false


static func options(_k: String, _slot: String, _have: Array) -> Array:
	return []


static func aug_text(_aug: String, _kind: String) -> String:
	return ""


## (옛) 강화 상태 검증 —— 새 형식으로 (norm)
static func clean(kit) -> Dictionary:
	return norm(kit)


## 전공을 쓴 합 (그 강화 상태를 만드는 데 든 값) —— 환불 · 점검용
static func spent(kit) -> int:
	var n := 0
	var c := norm(kit)
	for k in c:
		for i in (c[k] as Array).size():
			n += int(UP_COST[mini(i, UP_COST.size() - 1)])
	return n


static func p_scale(_augs: Array) -> float:
	return 1.0
