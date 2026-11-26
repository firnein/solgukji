extends RefCounted
## 장수 키트 Q · W · E · R · P (11/27 사용자)
##   "기존 특기들을 다 배제하고, 고유기를 가진 등급의 일반기술을 q,w,e · 고유기를 r · 고유 특기는 p.
##    쟤가 q 스킬이 발동됐구나, e 가 발동됐구나를 알 수 있어야 함. 군량 외에 제 3의 재화로 q,w,e,r,p 를 선택해서 강화 ——
##    강화된 스킬은 추가효과(추가범위 · 추가데미지 · 대상추가 · 화공 등)를 가진다. 일단은 신화 장수에 대해서만."
##
## 칸(slot)
##   q · w · e = 카드의 일반기술 sks[0] · sks[1] · sks[2]     r = 고유기(DB.ult_of)     p = 고유 특기 (passives.json traits 의 unique: true 한 개)
##   키트 장수(on)는 일반 특기 · 일반 단체 특기를 쓰지 않는다 —— 고유 특기와 그 이름의 단체 효과만 남는다 (DB.passives_of)
##
## 강화 상태 (Run.kit —— 저장 · 서버 전송 · 전투에 그대로 넘긴다)
##   { 카드 id: { "q": ["dmg", "fire"], "r": ["wide"], "p": ["amp", "amp"] } }      칸마다 강화 id 배열 (고른 차례대로, 최대 MAX_LV 개). 빈 칸은 키가 없어도 된다
##   전투에는 정책과 같은 길로: policy["kit"] = {"A": 강화 상태, "B": 강화 상태} (Run.policy_for —— 군략 plan 과 같다)
##
## 전투 사건 (화면이 칸을 알아보는 근거 —— Battle._kit_tag)
##   키트 장수의 기술 사건(fx "skill" —— 카드 기술 sks 를 쓴 것만)에 "slot": "q"|"w"|"e", 고유기 사건(fx "ult" · 예고 "ult_warn" · 인연 합류 "ult_join")에 "slot": "r".
##   함께 "augs": [그 칸의 강화 id …] (없으면 빈 배열). 키트 장수가 아닌 부대의 사건에는 두 필드가 없다
##   고유 특기: 개전 때 키트 장수마다 한 번 fx "passive" 사건에 "slot": "p" · "augs" (a: 그 부대 · name: 고유 특기 이름 · n: 단체 효과를 받은 부대 수, 단체 효과가 없으면 0).
##            개성 말풍선(sig_rt._say —— fx "buff" · "sig": true)에도 "slot": "p" · "augs"
##   결과 roster 의 키트 장수 줄에는 "kit": {칸: [강화 id …]} (다섯 칸 모두, 없으면 빈 배열)
##
## 엔진 쪽 약속 (Battle.mk_unit 이 진영별 강화 상태로 사본을 만든다 —— 카드 사전 DB.C · 특기 캐시는 고치지 않는다)
##   기술 eff.status2 · 고유기 효과 status2 = 두 번째 상태이상 (status 와 같은 꼴). eff.tgt0 · 효과 tgt0 = 「확산」 전의 원래 범위 —— 넓힌 범위에 원래 대상도 더한다
##   바탕 배율(base_sk · base_ult · base_p)은 강화가 없어도 키트 장수 모두에게 —— 일반 특기를 뺀 만큼을 메운다 (tests/kit_measure 로 맞춘다)
##
## class_name 없이 preload 로 쓴다 (낡은 .godot 캐시에서도 이름을 찾게 —— tactics.gd 와 같다):  const Kit := preload("res://scripts/kit.gd")

const SLOTS := ["q", "w", "e", "r", "p"]
const SLOT_N := {"q": "Q", "w": "W", "e": "E", "r": "R", "p": "P"}
const SLOT_KIND := {"q": "일반기술", "w": "일반기술", "e": "일반기술", "r": "고유기", "p": "고유 특기"}
## 칸 색 —— 전투 이펙트 · 딱지 · 화면 글이 모두 이 색을 쓴다 (칸을 색으로 알아본다)
const SLOT_COL := {"q": "#4aa8ff", "w": "#5fd36a", "e": "#b47aff", "r": "#ffd257", "p": "#ff9a4a"}
const MAX_LV := 3
const COST := [2, 3, 4]              # 그 칸의 1 · 2 · 3번째 강화 값 (전공)
const CUR_N := "전공"                # 제 3의 재화 이름 (Run.merit)

static var enabled := true           # 끄면 키트 장수가 없다 (예전 그대로 —— 비교 · 점검용)
static var min_tier := 8             # 이 등급 이상만 (11/27 "일단은 신화 장수에 대해서만")

## 강화 표 —— n 이름 · d 설명 · on 붙일 수 있는 칸 종류("sk" 일반기술 · "ult" 고유기 · "p" 고유 특기) · many 같은 칸에 여러 번
const AUG := {
	"dmg": {"n": "강격", "d": "피해 +30%", "d_ult": "피해 +25%", "on": ["sk", "ult"]},
	"wide": {"n": "확산", "d": "대상 범위를 한 단계 넓힌다", "on": ["sk", "ult"]},
	"fire": {"n": "화공", "d": "맞은 적에게 화상 (3초)", "d_ult": "맞은 적에게 화상 (고유기 지속 —— 길게 탄다)", "on": ["sk", "ult"]},
	"slow": {"n": "둔화", "d": "맞은 적의 속도 −25% (3초)", "on": ["sk"]},
	"awe": {"n": "위압", "d": "맞은 적의 사기를 더 꺾는다 (기술 사기 피해 +8)", "d_ult": "둘레 적 전체의 사기를 꺾는다 (고유기 사기 피해 10)", "on": ["sk", "ult"]},
	"quick": {"n": "연마", "d": "충전 비용 −25% (더 자주 쓴다)", "d_ult": "대기 시간 −20%", "on": ["sk", "ult"]},
	"cheer": {"n": "고무", "d": "아군에게 주는 회복 · 강화 +50%", "d_ult": "아군에게 주는 회복 · 강화 +40%, 지속이 한 단계 길어진다", "on": ["sk", "ult"]},
	"amp": {"n": "각성", "d": "고유 특기 효과 +30%", "on": ["p"], "many": true},
}
const DMG_SK := 1.30
const DMG_ULT := 1.25
const BURN := {"k": "burn", "val": 0.12, "dur": 3}
const SLOW := {"amt": -0.25, "dur": 3}
const AWE_SK := 8.0
const AWE_ULT := 10.0
const QUICK_SK := 0.75
const QUICK_ULT := 0.80
const CHEER_SK := 1.50
const CHEER_ULT := 1.40
const P_AMP := 0.30
## 「확산」 —— 대상 지정이 한 단계씩 넓어진다 (없는 것은 더 넓힐 수 없다). 엔진은 넓힌 범위에 원래 범위(tgt0)의 대상도 더한다 ——
## 넓힌 범위가 원래 대상을 놓치는 때가 있다 (최후열 둘 → 뒤쪽 절반은 적이 둘 남으면 하나 · 뒤쪽 절반 → 사거리 안 전체는 사거리 밖 후열을 놓친다)
const WIDE := {"front1": "front3", "front3": "all", "back1": "back2", "back2": "line:후군", "line:후군": "all", "line:선봉+전군": "all", "denseLine": "all"}

## 바탕 배율 —— 키트 장수는 일반 특기 · 일반 단체 특기를 쓰지 않아 그만큼 약해진다. 강화가 없어도 늘 곱해 예전 세기에 맞춘다 (11/27 실제 대전 덱으로 맞춤 —— tests/kit_measure)
##   base_sk 일반기술(q · w · e) 피해 배율 · base_ult 고유기(r) 타격 배율 · base_p 고유 특기(p) 수치 배율 (각성과 곱한다)
##   base_sup 기술 · 고유기가 아군에게 주는 회복 · 강화 배율 (기술의 heal · tHeal · allyBuff, 고유기 아군 효과의 heal · morale · buff —— 「고무」와 같은 값들, 지속은 그대로)
## 측정 (실제 온라인 대전 기록 650판 가운데 신화가 든 282판 × 씨앗 4 —— 신화가 든 쪽 1,392 · 한쪽에만 신화가 든 판 864, 키트 끔(예전) 대비):
##   모두 1.0            : 신화 쪽 승률 −1.4%p (한쪽만 −2.2) · 신화 부대 피해 몫 −0.6%p
##   피해 1.10 / 1.25    : 승률 −1.2 / −0.9 (한쪽만 −2.0 / −1.5) · 몫 +0.3 / +1.9 —— 피해 배율은 몫만 움직이고 승률은 거의 못 메운다 (빠진 특기가 주로 사기 · 버팀 · 아군 지원이라)
##   고유 특기 1.5       : 승률 −1.4 (한쪽만 −2.3) · 몫 −0.5 —— 효과 없음 → 1.0 그대로
##   피해 1.07 · 지원 1.0 / 1.3 (+ 유비 인의 분발 보정, Battle.mk_unit) : 승률 −0.7 / +0.4 (한쪽만 −1.2 / +0.7) · 몫 −0.3 / −0.1
##   확정 —— 피해 1.08 · 지원 1.2 · 고유 특기 1.0 (씨앗 8: 신화 쪽 2,784 · 한쪽만 1,728): 승률 73.3 → 73.0% (−0.3%p, 한쪽만 87.6 → 87.0%) · 몫 40.2 → 40.1% (−0.1%p)
##   장수별로는 어긋남이 남는다 (관우 승률 −3.7 · 몫 −3.4, 제갈량 승률 −5.0, 주유 +3.8, 여포 +2.4 …) —— 전체 배율 하나로는 못 맞춘다 (마지막 밸런스 몫)
static var base_sk := 1.08
static var base_ult := 1.08
static var base_p := 1.0
static var base_sup := 1.2


## 키트 장수인가 (지금은 신화) —— 적 전용 카드 · 은퇴 카드는 아니다
static func on(k) -> bool:
	if not enabled or k == null or not DB.C.has(str(k)):
		return false
	var c: Dictionary = DB.C[str(k)]
	if DB.is_foe(str(k)) or str(c.get("kind", "")) == "retired":
		return false
	return int(c.tier) >= min_tier and DB.has_ult(str(k))      # (DB.ult_of 는 부를 때마다 깊은 사본을 만든다 —— 있는지만 묻는다)


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


## 그 칸의 바탕 정의 —— {slot, kind: "sk"|"ult"|"p", name, src(원본 사전 · 고치지 말 것)}. 그 칸이 없으면 빈 사전
static func slot_def(k: String, slot: String) -> Dictionary:
	if not DB.C.has(k):
		return {}
	match slot:
		"q", "w", "e":
			var i: int = ["q", "w", "e"].find(slot)
			var sks: Array = DB.C[k].get("sks", [])
			if i >= sks.size():
				return {}
			return {"slot": slot, "kind": "sk", "name": str(sks[i].n), "src": sks[i]}
		"r":
			var u = DB.ult_of(k)
			if u == null:
				return {}
			return {"slot": slot, "kind": "ult", "name": str(u.name), "src": u}
		"p":
			var pn := p_name(k)
			if pn == "":
				return {}
			return {"slot": slot, "kind": "p", "name": pn, "src": DB.PSV.traits[pn]}
	return {}


## 그 카드의 그 칸에 한 강화 (배열 사본)
static func augs_of(kit, k: String, slot: String) -> Array:
	if not (kit is Dictionary) or not (kit.get(k) is Dictionary):
		return []
	var a = kit[k].get(slot)
	return (a as Array).duplicate() if a is Array else []


static func lv(kit, k: String, slot: String) -> int:
	return augs_of(kit, k, slot).size()


## 다음 강화 값 (전공) —— 더 못 올리면 −1
static func next_cost(have: Array) -> int:
	return int(COST[have.size()]) if have.size() < MAX_LV else -1


## 기술 효과가 적을 때리는가 (피해 배율이 있다)
static func _hits(eff: Dictionary) -> bool:
	return float(eff.get("mult", 0.0)) > 0.0


static func _supports(eff: Dictionary) -> bool:
	return eff.has("heal") or eff.has("tHeal") or eff.has("allyBuff")


## 그 칸에 그 강화를 붙일 수 있는가 (have = 이미 붙인 것)
static func valid(k: String, slot: String, aug: String, have: Array) -> bool:
	var sd := slot_def(k, slot)
	if sd.is_empty() or not AUG.has(aug) or have.size() >= MAX_LV:
		return false
	var a: Dictionary = AUG[aug]
	if not (a.on as Array).has(sd.kind):
		return false
	if have.has(aug) and not bool(a.get("many", false)):
		return false
	match sd.kind:
		"sk":
			var eff: Dictionary = sd.src.eff
			match aug:
				"dmg", "fire", "slow", "awe": return _hits(eff)
				"wide": return WIDE.has(str(eff.get("tgt", "")))
				"cheer": return _supports(eff)
		"ult":
			var effs: Array = sd.src.get("eff", [])
			var hit := false
			var ally := false
			var widen := false
			for e in effs:
				if str(e.get("t", "")) == "hit":
					hit = true
				if str(e.get("t", "")) == "ally":
					ally = true
				if str(e.get("t", "")) in ["hit", "foe"] and WIDE.has(str(e.get("tgt", ""))):
					widen = true
			match aug:
				"dmg", "fire": return hit
				"wide": return widen
				"cheer": return ally
	return true


## 지금 고를 수 있는 강화 id 들 (표의 차례)
static func options(k: String, slot: String, have: Array) -> Array:
	var out := []
	for aug in AUG:
		if valid(k, slot, aug, have):
			out.append(aug)
	return out


## 강화 설명 한 줄 —— 그 칸 종류에 맞는 글
static func aug_text(aug: String, kind: String) -> String:
	var a: Dictionary = AUG.get(aug, {})
	if a.is_empty():
		return ""
	return str(a.get("d_ult", a.d)) if kind == "ult" else str(a.d)


## 믿을 수 없는 강화 상태(옛 저장 · 클라이언트)를 규칙에 맞게 —— 모르는 카드 · 칸 · 강화, 넘치는 수는 버린다
static func clean(kit) -> Dictionary:
	var out := {}
	if not (kit is Dictionary):
		return out
	for k in kit:
		if not on(k) or not (kit[k] is Dictionary):
			continue
		var row := {}
		for slot in SLOTS:
			var have := []
			var src = kit[k].get(slot)
			if src is Array:
				for aug in src:
					if valid(str(k), slot, str(aug), have):
						have.append(str(aug))
			if not have.is_empty():
				row[slot] = have
		if not row.is_empty():
			out[str(k)] = row
	return out


## 전공을 쓴 합 (그 강화 상태를 만드는 데 든 값) —— 환불 · 점검용
static func spent(kit) -> int:
	var n := 0
	var c := clean(kit)
	for k in c:
		for slot in c[k]:
			for i in (c[k][slot] as Array).size():
				n += int(COST[mini(i, COST.size() - 1)])
	return n


# ───────── 전투에 적용 (원본은 고치지 않는다 —— 사본을 돌려준다) ─────────

## 일반기술 한 개에 바탕 배율 · 강화를 입힌 사본 (키트 장수의 전투 수치 —— 강화가 없어도 바탕 배율은 든다. 화면도 이 사본의 수치를 보이면 엔진과 같다).
## 엔진 쪽 약속: eff.status2 = 두 번째 상태이상 (status 와 같은 꼴 —— 이미 다른 상태이상이 있는 기술에 화공을 붙일 때) · eff.tgt0 = 확산 전의 원래 범위
static func apply_skill(sk: Dictionary, augs: Array) -> Dictionary:
	var out: Dictionary = sk.duplicate(true)
	var eff: Dictionary = out.eff
	if base_sk != 1.0 and _hits(eff):
		eff["mult"] = float(eff.mult) * base_sk
	if base_sup != 1.0:
		_sup_skill(eff, base_sup)
	for aug in augs:
		match str(aug):
			"dmg":
				eff["mult"] = float(eff.get("mult", 0.0)) * DMG_SK
			"wide":
				if WIDE.has(str(eff.get("tgt", ""))):
					if not eff.has("tgt0"):
						eff["tgt0"] = str(eff.tgt)
					eff["tgt"] = WIDE[str(eff.tgt)]
			"fire":
				if not eff.has("status"):
					eff["status"] = BURN.duplicate()
				elif str(eff.status.get("k", "")) == "burn":
					eff.status["val"] = float(eff.status.val) * 1.5
				else:
					eff["status2"] = BURN.duplicate()
			"slow":
				var key := "foeSpd" if eff.has("foeSpd") else "spd"
				if eff.has(key):
					eff[key]["amt"] = float(eff[key].amt) + SLOW.amt * 0.6
				else:
					eff[key] = SLOW.duplicate()
			"awe":
				eff["morale"] = float(eff.get("morale", 0.0)) + AWE_SK
			"quick":
				out["cost"] = float(out.get("cost", 1.0)) * QUICK_SK
			"cheer":
				_sup_skill(eff, CHEER_SK)
	return out


## 기술이 아군에게 주는 회복 · 강화에 배율 (사기 회복 heal · 병력 치료 tHeal · 아군 강화 allyBuff)
static func _sup_skill(eff: Dictionary, x: float) -> void:
	if eff.has("heal"):
		eff["heal"] = float(eff.heal) * x
	if eff.has("tHeal"):
		eff["tHeal"] = float(eff.tHeal) * x
	if eff.has("allyBuff"):
		eff.allyBuff["amt"] = float(eff.allyBuff.amt) * x


## 고유기의 아군 효과(t "ally")에 배율 —— 병력 회복 heal · 사기 morale · 강화 buff
static func _sup_ult(effs: Array, x: float) -> void:
	for e in effs:
		if str(e.get("t", "")) != "ally":
			continue
		if e.has("heal"):
			e["heal"] = float(e.heal) * x
		if e.has("morale"):
			e["morale"] = float(e.morale) * x
		if e.has("buff"):
			e.buff["amt"] = float(e.buff.amt) * x


## 고유기에 바탕 배율 · 강화를 입힌 사본 (apply_skill 과 같다 —— 강화가 없어도 바탕 배율은 든다)
static func apply_ult(ult: Dictionary, augs: Array) -> Dictionary:
	var out: Dictionary = ult.duplicate(true)
	var effs: Array = out.get("eff", [])
	if base_ult != 1.0:
		for e in effs:
			if str(e.get("t", "")) == "hit":
				e["mult"] = float(e.get("mult", 0.0)) * base_ult
	if base_sup != 1.0:
		_sup_ult(effs, base_sup)
	for aug in augs:
		match str(aug):
			"dmg":
				for e in effs:
					if str(e.get("t", "")) == "hit":
						e["mult"] = float(e.get("mult", 0.0)) * DMG_ULT
			"wide":
				for e in effs:
					if str(e.get("t", "")) in ["hit", "foe"] and WIDE.has(str(e.get("tgt", ""))):
						if not e.has("tgt0"):
							e["tgt0"] = str(e.tgt)
						e["tgt"] = WIDE[str(e.tgt)]
			"fire":
				for e in effs:
					if str(e.get("t", "")) != "hit":
						continue
					if not e.has("status"):
						e["status"] = BURN.duplicate()
					elif str(e.status.get("k", "")) == "burn":
						e.status["val"] = float(e.status.val) * 1.5
					else:
						e["status2"] = BURN.duplicate()
			"awe":
				effs.append({"t": "foe", "tgt": "all", "morale": AWE_ULT})
			"quick":
				out["wait"] = float(out.get("wait", 10.0)) * QUICK_ULT
			"cheer":
				_sup_ult(effs, CHEER_ULT)
				for e in effs:
					if str(e.get("t", "")) == "ally" and e.has("buff"):
						e.buff["dur"] = float(e.buff.get("dur", 2.0)) + 1.0
	out["eff"] = effs
	return out


## 고유 특기 배율 (각성 한 번에 +30%) —— 강화 몫만. 전투가 실제로 곱하는 값은 p_mul (바탕 배율 포함)
static func p_scale(augs: Array) -> float:
	var n := 0
	for aug in augs:
		if str(aug) == "amp":
			n += 1
	return 1.0 + P_AMP * n


## 전투가 고유 특기에 곱하는 값 —— 바탕 배율 × 각성. 주인에게 붙는 수치(p_scales 가 참인 키)와 단체 효과 세기(scale · fscale)에 곱한다
static func p_mul(augs: Array) -> float:
	return base_p * p_scale(augs)


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
static func p_apply(m: Dictionary, augs: Array) -> Dictionary:
	var out: Dictionary = m.duplicate()
	var x := p_mul(augs)
	if x != 1.0:
		for key in out:
			if p_scales(str(key)):
				out[key] = float(out[key]) * x
	return out


# ═════════ 새 방식 (11/27 저녁 사용자) ═════════
## "W · E 기술도 장수별로 고유하게 · 강화를 능력치가 아니라 다양한 효과로(단순 파워업이 아니라) · 강화는 1번씩만, 장수당 1개 많으면 2개
##  · 자리 개념이 아니라 그냥 1~2개를 강화하면 바로 끝남 (QW 관우가 QW 장각을 만났을 때 QE 관우로 바꿔 카운터 치는 것이 아니라,
##    더 늦게 조합되는 WE 장비로 QW 장각을 약화시키는 개념) · 편성 화면에서 드래그로 되도록"
## 자료: data/kit.json —— 카드 id → 칸 → {n 이름, cd 재사용 대기(초 · q·w·e), d 하는 일, new, up: {n 강화 이름, d 강화하면 붙는 효과}} (+ 엔진이 쓰는 필드)
## 강화 상태(새 형식 —— Run.kit): { 카드 id: ["q", "w"] }  강화한 칸 목록 (고른 차례대로, 최대 MAX_UP 칸 · 칸마다 한 번 · 되돌릴 수 없다)
##   옛 형식(칸 → 강화 id 배열)은 norm 이 새 형식으로 바꾼다. 전투에는 그대로 policy["kit"] = {"A": 강화 상태, "B": 강화 상태}
## 전투 사건: 키트 장수의 기술 · 고유기 · 고유 특기 사건에 "slot", 그 칸이 강화돼 있으면 "up": true.
##   강화 효과가 실제로 발동한 사건(다시 쓰기 · 밀어내기 · 끊기 …)에는 "kup": 강화 이름 —— 화면이 그 이름을 칸 색으로 띄운다
const MAX_UP := 2
const UP_COST := [4, 6]              # 그 장수의 1 · 2번째 강화 값 (전공)

static var _data := {}


static func data() -> Dictionary:
	if _data.is_empty():
		var f := FileAccess.open("res://data/kit.json", FileAccess.READ)
		if f != null:
			var d = JSON.parse_string(f.get_as_text())
			if d is Dictionary:
				_data = d
	return _data


## 그 장수 그 칸의 자료 —— {n, d, up: {n, d}, cd?, new?, …}. 없으면 빈 사전 (키트 장수가 아니거나 자료가 없다)
static func cell(k, slot: String) -> Dictionary:
	var h = data().get(str(k))
	if not (h is Dictionary) or not (h.get(slot) is Dictionary):
		return {}
	return h[slot]


## 강화한 칸 목록 (사본). 옛 형식이 들어와도 칸 목록으로 읽는다
static func ups_of(kit, k) -> Array:
	if not (kit is Dictionary):
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
	var n := ups_of(kit, k).size()
	return int(UP_COST[n]) if n < MAX_UP else -1


## 그 칸을 강화할 수 없는 까닭 ("" = 할 수 있다 —— 전공 · 보유 여부는 Run 이 본다)
static func up_block(kit, k, slot: String) -> String:
	if not on(k):
		return "키트 장수가 아니다"
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
		if not on(k):
			continue
		var have := []
		for s in ups_of(kit, k):
			if not cell(k, s).is_empty():
				have.append(s)
		if not have.is_empty():
			out[str(k)] = have
	return out
