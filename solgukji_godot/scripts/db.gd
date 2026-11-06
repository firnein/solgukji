extends Node
## 게임 데이터 —— data/game.json 은 HTML 프로토타입에서 tools/scripts/extract.py 로 뽑은 것이다.
## 원본의 상수 이름(CARDDEF, FORM, AFF …)을 그대로 따라 이식 대조가 쉽도록 했다.

const PAL := {
	"ink": Color("#131A2B"), "ink2": Color("#1B2338"), "ink3": Color("#242E49"), "ink4": Color("#33405F"),
	"paper": Color("#E9E3D3"), "bamboo": Color("#C6AC7C"), "bamboo_dim": Color("#8D7B5C"),
	"seal": Color("#BE4A3C"), "jade": Color("#4F9080"), "gold": Color("#D9A64B"),
}

var D: Dictionary
var K: Dictionary
var C := {}              # 카드 id -> 카드
var IT := {}             # 아이템 id -> 아이템
var ITEM_BY_NAME := {}
var RECOF := {}          # 결과 id -> 재료 배열
var TIER := {}           # 등급(int) -> {n, c, lo, hi}
var FORM := {}           # 진형 -> {n, sil, mask, slots, grid}
var BASE: Array = []     # 기본패 8종
var KIIN_BY_KEY := {}         # 기인 기능 키 -> 카드 id
var MYTH_ITEMS := {}          # 플레이어가 만들 수 있는 신화의 유니크 재료 id
var PLAY_TIERS: Array = []   # 플레이어가 얻을 수 있는 등급 (11/3 일반 등급 삭제 —— 1 · 3 · 4 · …)
var LINES := {}          # data/lines.json —— 인물 줄기 새 카드 · 조합 · 고유 기술
const UNIQUE_MUL := 0.75   # 유니크 아이템 능력치 배율 (11/2 하향)
var AURA := {}           # data/myth_aura.json —— 신화 위세 (살아 있는 동안 아군·적 전체 배율)
var POOLS := {}          # 성향 -> 등급 -> 카드 id 배열
var ICON := {}           # 병종 -> Texture2D (흰색, modulate 로 칠한다)

var font_display: Font
var font_body: Font
var font_bold: Font
var STAT_ADJ := {}      # 능력치 보정 (set_stat_adjust)
const TIER_ART := false  # 초월 · 불멸 · 신화 전용 그림(<인물>_신화.png 등)을 쓸까 —— 10/30 사용자: 지금은 모든 등급이 기본 그림 (true 로 바꾸면 export_presets.cfg 의 exclude_filter 에서 *_초월 · *_불멸 · *_신화 도 빼야 APK 에 들어간다)
var _BASE := {}         # 보정 전 원본 능력치

var _portrait_cache := {}
var _portrait_used := {}     # 배경이 투명한 그림 -> 실제로 그려진 영역 (Rect2)
var _portrait_panel := {}    # 패널째 잘린 그림(그려진 영역이 거의 꽉 찬 사각형) —— 칸을 꽉 채워 그린다
var _portrait_face := {}     # 그림 -> 얼굴 자리 (그림 속 정사각형 Rect2) —— 전투용 썸네일 (10/30)
var _portrait_pick := {}     # 카드 key -> 실제로 쓰는 그림 경로 (등급 그림이 없으면 기본 그림)
var ULT: Dictionary          # data/ultimates.json —— 불멸·신화 고유기
var PSV: Dictionary          # data/passives.json —— 개인·단체 특기
var CLASS_COUNTER: Dictionary # 병종 상성 (data/cards_ext.json)
var SKILL_COND: Dictionary   # 일반 기술 발동 조건 (data/cards_ext.json skill_cond)
var QUEST_ROSTERS: Array = []  # 토벌 고정 편성 —— 황건적 소탕 [일차][단계] (data/cards_ext.json quest_rosters, 11/2)

const PHYS_TAGS := ["창병", "기병", "궁병", "도적"]
const INT_TAGS := ["책사", "유생", "술사", "모사"]
const STYLE_FORM := {"물리": "hagik", "지략": "bangwon", "균형": "eorin"}


func _ready() -> void:
	_load()


## 11/2 사용자 (2차): 고급 · 희귀가 구분되지 않는다 → 흰 · 회 · 초록 · 보라 · 빨강 · 하늘 · 주황 · 금. 색이 가까운 등급은 글꼴(굵기 · 기울임)로도 가른다 (tier_font)
const TIER_COL := {1: "#f2f2ee", 2: "#9aa1aa", 3: "#2fc24f", 4: "#a64cf2", 5: "#f03c3c", 6: "#45c8f5", 7: "#ff8a1c", 8: "#ffd23a"}
## 이전 색 (원랜디): {1: "#64748b", 2: "#16a34a", 3: "#2563eb", 4: "#7c3aed", 5: "#ea580c", 6: "#e11d48", 7: "#db2777", 8: "#ca8a04"}      # 11/2 사용자: 원랜디 등급색 (흔함 · 안흔함 · 특별함 · 희귀함 · 전설적인 · 초월함 · 영원한), 불멸만 히든조합 분홍 (불멸의 갈색은 신화 금과 겹쳤다)


## 11/3 사용자: "배급이 너무 많아 결핍이 없다 · 4~5일차에 풀덱 · 화요일 아침에 신화" —— 수입을 약 75% 로, 뒤 일차일수록 더 줄인다 (기본패 환산 누적 142 · 286 · 490 · 738 · 1164 · 1674 · 2244 → 108 · 222 · 392 · 580 · 854 · 1270 · 1676).
## 신화 한 장 = 기본패 약 125장인데 첫날 수입이 142장이라 화요일 아침에 신화가 됐다 → 첫날 108장, 풀덱(약 800장)은 5일차 끝 무렵.
## 원본 game.json 은 그대로 두고 불러온 뒤 덮어쓴다. ECON_ON = false 면 예전 수치
const ECON_ON := true
const ECON := {
	"DRAWS": [11, 10, 9, 8, 7, 6, 5],                     # 예전 14 · 13 · 12 · 11 · 10 · 9 · 8
	"QUEST_BASE": [6, 7, 8, 8, 9, 10, 11],                # 예전 7 · 9 · 12 · 14 · 17 · 20 · 23
	"PVP_BASE": {"win": 5, "lose": 4},                    # 예전 7 · 4 —— 11/5 사용자: 져도 보급 위험이 너무 크지 않게 (3 → 4)
	"UNIQUE_PHASES": [3, 9, 15],                          # 11/5 사용자: 유니크를 1 · 3 · 5일차 → 2 · 4 · 6일차 아침 (페이즈 번호 = 일차×3)
	"QUEST_REWARD": [[{"t": 3, "n": 2}], [{"t": 4, "n": 1}], [{"t": 4, "n": 1}], [{"t": 4, "n": 1}, {"t": 3, "n": 1}],
		[{"t": 5, "n": 1}], [{"t": 5, "n": 1}, {"t": 3, "n": 1}], [{"t": 5, "n": 1}, {"t": 4, "n": 1}]],
	"RANDOM_GRANT": [[], [], [{"t": 4, "n": 1}], [{"t": 4, "n": 1}], [{"t": 4, "n": 1}], [{"t": 4, "n": 1}, {"t": 5, "n": 1}], [{"t": 5, "n": 1}, {"t": 4, "n": 1}]],
}
## 진형 우대 고침 (11/5 사용자: 모든 진형의 특색이 올바른지 · 전력에 영향을 주는지 —— tests/form_check.tscn).
## 같은 덱으로 진형만 바꿔 보니 장사진이 가장 약하고(승률 33 · 35%) 우대 병종을 넣어도 이득이 없었다. 안행진은 우대 병종이 오히려 손해,
## 학익진의 '발동 +7%' 는 거의 힘이 없었다 —— 원본 FORMBOON 위에 덮어쓴다
const FORMBOON_FIX := {
	"hagik": {"stat": "atk", "v": 0.12},       # 궁병 · 도적 발동 +7% → 공격 +12% (날개가 사계를 넓힌다)
	"anhaeng": {"stat": "atk", "v": 0.14, "d": "사선으로 파고든다"},     # 도적 · 기병 속도 +14% → 공격 +14%
	"jangsa": {"v": 0.32},                     # 책사 · 술사 책략 +15% → +28% → 11/6 +32% (불멸 무작위 덱 승률 45%, 가장 낮았다)
	"chuhaeng": {"stat": "atk", "v": 0.14, "d": "송곳이 틈을 낸다"},      # 11/6 도적 · 모사 속도 +13% → 공격 +14% (우대 덱 15% —— 속도는 힘이 안 됐다)
}


func _apply_econ() -> void:
	for k in FORMBOON_FIX:
		D.FORMBOON[k].merge(FORMBOON_FIX[k], true)
	if not ECON_ON:
		return
	for key in ECON:
		D[key] = ECON[key].duplicate(true)


func _load() -> void:
	var f := FileAccess.open("res://data/game.json", FileAccess.READ)
	D = JSON.parse_string(f.get_as_text())
	K = D.K
	# 솔국지 확장 카드 —— 원본 뒤에 붙인다 (data/cards_ext.json)
	var ext = JSON.parse_string(FileAccess.open("res://data/cards_ext.json", FileAccess.READ).get_as_text())
	D.CARDDEF.append_array(ext.cards)
	D.RECDEF.append_array(ext.recipes)
	D.ITEMDEF.append_array(ext.items)
	for k in ext.get("status", {}):
		D.STATUS[k] = ext.status[k]
	CLASS_COUNTER = ext.get("class_counter", {})
	SKILL_COND = ext.get("skill_cond", {})
	QUEST_ROSTERS = ext.get("quest_rosters", {}).get("stages", [])
	D.SKILLPOOL["범용"] = ext.get("skills_ext", []).filter(func(x): return x.has("n"))     # 범용 기술 (누구나 추가 기술로)
	# 11/2 인물 줄기 · 인연 조합 · 장수 고유 기술 (data/lines.json —— tools/scripts/lines.py 가 만든다)
	LINES = JSON.parse_string(FileAccess.open("res://data/lines.json", FileAccess.READ).get_as_text())
	AURA = JSON.parse_string(FileAccess.open("res://data/myth_aura.json", FileAccess.READ).get_as_text())
	AURA.erase("_설명")
	D.CARDDEF.append_array(LINES.cards)
	D.ITEMDEF.append_array(LINES.get("items", []))
	for nm in LINES.skills:
		SKILL_COND[LINES.skills[nm].n] = LINES.skills[nm].get("cond", "always")
	_apply_econ()
	_build_fonts()

	for r in D.CARDDEF:
		C[r[0]] = {"id": r[0], "name": r[1], "tier": int(r[2]), "tag": r[3], "fac": r[4],
			"atk": float(r[5]), "def": float(r[6]), "int": float(r[7]), "res": float(r[8]),
			"spd": float(r[9]), "tr": int(r[10]), "pv": int(r[11]), "sk": r[12],
			"kind": r[13], "need": r[14]}
	for k in C:
		_BASE[k] = {"atk": C[k].atk, "def": C[k].def, "int": C[k].int, "res": C[k].res, "spd": C[k].spd}
	set_stat_adjust(ext.get("stat_adjust", {}))
	for r in D.RECDEF:
		RECOF[r[0]] = r[1]
	for k in LINES.recipes:
		RECOF[k] = LINES.recipes[k]
	# 11/2 (5) 줄기 인물의 초월 카드는 적 전용 (토벌 편성이 쓰는 것이 있어 지우지 않는다)
	for k in LINES.get("rename", {}):        # 11/4 전설은 접두어 없이 이름만
		if C.has(k):
			C[k].name = LINES.rename[k]
	for k in LINES.get("retire", []):
		C[k].kind = "retired"
		RECOF.erase(k)
	for k in LINES.get("aura", {}):
		AURA[k] = LINES.aura[k]
		if LINES.aura[k].has("kiin"):
			KIIN_BY_KEY[LINES.aura[k].kiin] = k
	D.RECDEF = RECOF.keys().map(func(k): return [k, RECOF[k]])      # 조합을 돌며 찾는 곳이 새 카드 · 바뀐 재료를 보도록
	for r in D.ITEMDEF:
		IT[r[0]] = {"id": r[0], "name": r[1], "grade": r[2], "tag": r[3], "pri": r[4],
			"pa": float(r[5]), "sec": r[6], "sa": float(r[7]), "rb": float(r[8]), "use": r[9]}
		ITEM_BY_NAME[r[1]] = r[0]
		if r[2] == "유니크":         # 11/2 사용자: 유니크 능력치 하향 —— 주 · 부 ×0.75, 계략 저항 7 → 5 (전설 레어 0.24 · 0.09 · 3 바로 위)
			IT[r[0]].pa = snappedf(IT[r[0]].pa * UNIQUE_MUL, 0.01)
			IT[r[0]].sa = snappedf(IT[r[0]].sa * UNIQUE_MUL, 0.01)
			IT[r[0]].rb = minf(IT[r[0]].rb, 5.0)
	for k in C:
		if C[k].tier >= 8 and not is_foe(k) and C[k].need != "" and ITEM_BY_NAME.has(C[k].need):
			MYTH_ITEMS[ITEM_BY_NAME[C[k].need]] = true

	for t in D.TIER:
		TIER[int(t)] = {"n": D.TIER[t].n, "c": Color(D.TIER[t].c)}
	# 솔국지 확장 (11/2 사용자): 등급색은 원랜디(원피스 랜덤 디펜스)를 따른다 —— 원본 game.json 색은 그대로 둔다
	for t in TIER_COL:
		TIER[t].c = Color(TIER_COL[t])
	for t in TIER:
		var pvs := []
		for k in C:
			if C[k].tier == t and not is_foe(k):
				pvs.append(C[k].pv)
		if pvs.is_empty():        # 11/3 일반 등급 삭제 —— 플레이어 카드가 없는 등급은 적 전용 카드로 값만 잡는다
			for k in C:
				if C[k].tier == t:
					pvs.append(C[k].pv)
		else:
			PLAY_TIERS.append(t)
		TIER[t].lo = pvs.min()
		TIER[t].hi = pvs.max()
	PLAY_TIERS.sort()

	for k in C:
		if C[k].tier == 1:
			BASE.append(k)

	ULT = JSON.parse_string(FileAccess.open("res://data/ultimates.json", FileAccess.READ).get_as_text())
	for p in LINES.get("ults", {}):
		ULT.list[p] = LINES.ults[p]
	PSV = JSON.parse_string(FileAccess.open("res://data/passives.json", FileAccess.READ).get_as_text())
	for p in LINES.get("ladder_from", {}):        # 11/2 (5) 새 인물 —— 닮은 인물의 특기 사다리를 빌린다 (초월까지만)
		var src: String = LINES.ladder_from[p]
		PSV.ladder[p] = PSV.ladder.get(src, []).filter(func(e): return int(e[1]) <= 6)
		if PSV.level.has(src):
			PSV.level[p] = PSV.level[src]
	for p in LINES.get("ladder", {}):          # 11/3 사용자: 장수들이 특기를 더 많이 —— 등급마다 최소 수만큼 채운 사다리 (lines.py fill_ladders)
		PSV.ladder[p] = LINES.ladder[p]
	merge_stats()      # 11/6 #15 책략 · 책략방어 통합
	_reskill()
	_build_forms()
	_build_pools()
	_build_icons()


## 원본 reskill() —— CARDDEF 안의 스킬 정의는 버리고 SKILLPOOL 기준으로 다시 물린다. 패시브만 남긴다.
func _reskill() -> void:
	var ids: Array = C.keys()
	ids.sort_custom(func(a, b):
		if C[a].tier != C[b].tier:
			return C[a].tier < C[b].tier
		return a < b)
	var idx := {}
	var reserved: Array = PSV.reserved_skills
	for k in ids:
		var c: Dictionary = C[k]
		if c.tier < 4:
			c.sk = null
			c.sks = []
			continue
		# 11/2 장수 고유 기술 —— 인물마다 하나 (lines.json skills). 첫 기술로
		var sig = LINES.skills.get(person(k))
		if sig != null:
			c.sk = _build_from(sig, c.tier)
			continue
		# 인물에게 지정된 스킬 (계열 인물의 계열 스킬) —— 없으면 남은 병종 스킬을 돌려 쓴다
		var want: String = PSV.skill.get(person(k), {}).get(c.tag, "")
		var pool: Array = D.SKILLPOOL[c.tag]
		var i := -1
		if want != "":
			for j in pool.size():
				if pool[j].n == want: i = j
		if i < 0:
			var free := []
			for j in pool.size():
				if not reserved.has(pool[j].n): free.append(j)
			var key: String = c.tag + str(c.tier)
			idx[key] = idx.get(key, 0)
			i = free[idx[key] % free.size()]
			idx[key] += 1
		c.sk = _build_skill(c.tag, i, c.tier)
	for k in ids:
		C[k].sks = _skill_list(k)


## 기술 여러 개 (솔국지 확장, 2026-10-30) —— 첫 기술은 원본 배정 그대로, 희귀부터 기술을 더한다 (희귀 · 전설 · 초월 +1, 불멸 · 신화 +2). 기술마다 충전이 따로 돈다.
## 더하는 기술은 그 인물 특기의 축(도트 · 둔화 · 혼란 …)에 맞는 것부터, 자기 주 능력치(공격 / 책략)와 같은 종류만.
## 11/2 사용자: 장수마다 특화가 느껴지게 —— 희귀 · 전설은 고유 기술 하나만, 초월 · 불멸 +1, 신화 +2 (예전 4~6 +1 · 7~8 +2)
const SKILL_EXTRA := {6: 1, 7: 1, 8: 2}
const AXIS_SKILLS := {"도트": ["화공", "화시난발", "역병"], "둔화": ["수공", "철기유린"], "혼란": ["혹세", "봉계"],
	"책방깎": ["팔문금쇄", "저주"], "방깎": ["필사돌격", "저격"], "물리": ["횡소천군", "일점돌파", "일제사격"],
	"책략": ["이간", "밀계"], "공깎": ["후미교란", "철기유린"], "책략깎": ["밀계", "이간"], "철벽": ["철벽방진"],
	"인덕": ["격려", "독려", "인덕"], "사기": ["진두지휘", "격문", "고함", "고취", "격려", "독려"]}

func _skill_list(k: String) -> Array:
	var c: Dictionary = C[k]
	if c.sk == null:
		return []
	var out := [c.sk]
	var n: int = SKILL_EXTRA.get(c.tier, 0)
	if n <= 0:
		return out
	var kind := "int" if INT_TAGS.has(c.tag) else "phys"      # 11/6 #15 능력치 통합 —— 병종으로
	var want := []
	# 아군 사기를 북돋는 특기(함성 · 독전 · 고무)를 가진 인물은 사기 기술을 먼저 받는다
	if PSV.ladder.get(person(k), []).any(func(e): return e[0] in ["함성", "독전", "고무"] and c.tier >= int(e[1])):
		want.append_array(AXIS_SKILLS["사기"])
	for e in PSV.ladder.get(person(k), []):
		var a: String = PSV.traits.get(e[0], {}).get("attr", "")
		for nm in AXIS_SKILLS.get(a, []):
			if not want.has(nm): want.append(nm)
	for nm in D.SKILLPOOL[c.tag].map(func(x): return x.n):
		if not want.has(nm): want.append(nm)
	for tg in D.TAGORDER:      # 범용 사기 기술(고함 · 고취 …)은 사기 특기를 가진 인물만 (위 want) —— 모두에게 붙어 고유 기술을 덮었다
		for x in D.SKILLPOOL[tg]:
			if not want.has(x.n): want.append(x.n)
	for nm in want:
		if out.size() > n:
			break
		if out.any(func(x): return x.n == nm):
			continue
		var b = _build_skill_named(nm, c.tier)
		if b != null and b.eff.kind == kind:
			out.append(b)
	return out


func _build_skill_named(nm: String, tier: int):
	for tg in D.SKILLPOOL:
		var pool: Array = D.SKILLPOOL[tg]
		for j in pool.size():
			if pool[j].n == nm:
				return _build_skill(tg, j, tier)
	return null


## 합친 상태이상 (2026-10-30) —— 출혈은 화상으로, 봉인은 혼란으로. 원본 기술 · 고유기 데이터는 그대로 두고 불러올 때 바꾼다
const ST_MERGE := {"bleed": "burn", "seal": "confuse"}


func _build_skill(tag: String, i: int, tier: int) -> Dictionary:
	var pool: Array = D.SKILLPOOL[tag]
	return _build_from(pool[i % pool.size()], tier)


## 11/3 일반 기술 —— 삼국지13 · 14 참고: 발동은 어렵게(비용 · 엄격한 조건), 효과는 크게.
## 비용 = 충전 몇 번 분량 (삼국지13 채배 소모처럼 큰 기술일수록 비싸다). 위력 배율은 SK_POWER.
## 11/5 사용자: 일반 기술은 파괴력을 낮추고 더 자주 —— 위력 약 6할 · 비용 약 5.5할 (예전 1.7 · 1.5 · 1.5 · 1.3 · 1.4 · 1.25)
const SK_POWER := {"mult": 0.9, "morale": 1.0, "heal": 1.0, "status": 1.0, "buff": 1.15, "exec": 1.0, "dur": 1}      # 11/4 사용자: 기술 · 고유기 위력을 낮춘다 (2.1 · 1.8 · 1.8 · 1.5 · 1.6 · 1.4 에서)
const ULT_POWER := 0.8     # 11/4 사용자: 고유기 타격 · 회복 · 사기 전체 배율 (ult_of)
const ULT_OVER := 3.2     # 고유기 한 방은 가장 센 일반 기술의 이만큼 이상 (ult_of) —— 11/3 1.5 → 2.0 (고유기가 클라이맥스). 11/5 일반 기술 위력을 1.7 → 0.9 로 낮춰 1.7 → 3.2 (고유기 바닥은 그대로)
## 11/3 등급이 높을수록 충전 속도(RATE 0.25 → 0.45)가 빨라 신화는 부대당 한 판 5번 넘게 터졌다 —— 비용도 등급만큼 올려 2~3번으로
const SK_COST_TIER := {6: 1.25, 7: 1.45, 8: 1.75}
const SK_COST := {"front1": 0.6, "back1": 0.6,      # 11/5 사용자: 일반 기술 몇몇은 잘 터지게 —— 한 부대만 치는 기술은 싸게 (1.6 → 1.1)
	"front3": 1.1, "back2": 1.1, "denseLine": 1.1, "all": 1.3}      # 11/5 사용자 2차: 더 자주 —— 모두 약 5.5할 (1.1 · 2.0 · 2.4 에서)


func sk_cost(e: Dictionary) -> float:
	if not e.has("mult"):
		return 1.1
	var t: String = e.get("tgt", "front1")
	return SK_COST.get(t, 1.4)


## 발동 조건을 엄격하게 —— '언제나'를 빼고 문턱을 높인다. 남는 것이 없으면 대상 모양으로 정한다
func strict_cond(cond: String, e: Dictionary) -> String:
	var out := []
	for one in cond.split("|"):
		var kv := one.split(":")
		var v: String = kv[1] if kv.size() > 1 else ""
		match kv[0]:
			"always": continue
			# 11/5 사용자: 조건이 까다로워 일반 기술이 거의 안 터졌다 (희귀 · 전설 한 판 1.4회) —— 원본 조건 그대로, 수만 조금 엄하게
			"hurt", "ally_hurt": out.append("%s:%s" % [kv[0], str(snappedf(float(v) * 0.95, 0.05))])
			"foe_hurt": out.append("foe_hurt:%s" % str(snappedf(float(v), 0.05)))
			"dense", "front_n": out.append("%s:%d" % [kv[0], maxi(2, int(v))])
			"foe_n": out.append("foe_n:%d" % maxi(3, int(v)))
			"ally_morale": out.append("ally_morale:%d" % roundi(float(v)))
			_: out.append(one)
	if out.is_empty():
		var t: String = e.get("tgt", "front1")
		if e.has("exec"): out.append("foe_hurt:0.6")
		elif t == "front1": out.append("always")
		elif t in ["back1", "back2", "line:후군"]: out.append("back_n:1")
		elif t == "all": out.append("foe_n:3")
		else: out.append("dense:2")
	return "|".join(out)


func _scale_buff(b: Dictionary) -> Dictionary:
	var o := b.duplicate()
	if o.has("amt"): o.amt = snappedf(float(o.amt) * SK_POWER.buff, 0.01)
	if o.has("dur"): o.dur = int(o.dur) + SK_POWER.dur
	return o


func _build_from(base: Dictionary, tier: int) -> Dictionary:
	var m: float = D.SKMUL.get(str(tier), 1.0)
	var e := {"kind": base.k, "tgt": base.tgt}
	if base.has("mult"): e.mult = snappedf(base.mult * m * SK_POWER.mult, 0.001)
	if base.has("morale"): e.morale = snappedf(base.morale * m * SK_POWER.morale, 0.1)
	if base.has("tHeal"): e.tHeal = snappedf(base.tHeal * m * SK_POWER.heal, 0.0001)
	if base.has("heal"): e.heal = snappedf(float(base.heal) * SK_POWER.heal, 0.1)
	if base.has("exec"): e.exec = minf(0.35, snappedf(float(base.exec) * SK_POWER.exec, 0.01))
	if base.has("pierce"): e.pierce = minf(0.6, float(base.pierce) + 0.1)
	for key in ["spd", "foeSpd", "resDown", "selfBuff", "allyBuff", "stance"]:
		if base.has(key):
			e[key] = _scale_buff(base[key])
	for key in ["cleanse", "rally"]:
		if base.has(key):
			e[key] = base[key]
	if base.has("status"):
		var s: Dictionary = base.status.duplicate()
		s.k = ST_MERGE.get(s.k, s.k)
		if s.k == "confuse":
			s.dur = 1          # 혼란은 차례를 통째로 날린다 —— 봉인(2턴)에서 온 것도 1턴
		var ratio: bool = s.k == "burn" or s.k == "flood"
		e.status = {"k": s.k,
			"val": snappedf(s.val * m * (SK_POWER.status if s.k != "confuse" else 1.0), 0.001 if ratio else 0.1),
			"dur": int(s.dur) + int(D.SKDUR.get(str(tier), 0))}
	return {"n": base.n, "eff": e, "psv": null, "cond": strict_cond(str(SKILL_COND.get(base.n, "always")), e),
		"cost": snappedf(sk_cost(e) * SK_COST_TIER.get(tier, 1.0), 0.1)}


## 줄 배율 · 선호 자리도 덧붙인다 (LINE · AFF). 적 · 토벌 편성도 같은 진형 데이터를 쓴다
## 11/6 사용자: 진형 4행 5열 (9칸 그대로). 5열 —— 좌익 · 좌 · 중앙 · 우 · 우익. 가운데 열(2)만 '중앙', 나머지는 '측면'.
## (오전의 5행 × 3열 '본진' 안은 거둔다 —— 줄은 원본 4줄: 선봉 · 전군 · 중군 · 후군)
const FORM45 := {
	"eorin":    ["..X..", ".XXX.", ".XXX.", ".X.X."],     # 어린진 —— 비늘이 겹친 물고기
	"hagik":    ["X...X", "XX.XX", "..X..", ".X.X."],     # 학익진 —— 앞으로 벌린 두 날개
	"bongsi":   ["..X..", ".X.X.", "X.X.X", ".XXX."],     # 봉시진 —— 화살촉
	"anwol":    ["X...X", "X...X", ".XXX.", ".X.X."],     # 안월진 —— 초승달
	"bangwon":  [".XXX.", "X...X", "X...X", ".X.X."],     # 방원진 —— 둥근 고리
	"anhaeng":  ["XX...", "XXX..", "..XX.", "...XX"],     # 안행진 —— 사선
	"chuhaeng": ["..X..", "..X..", ".XXX.", "XX.XX"],     # 추행진 —— 송곳
	"jangsa":   ["XXX..", "..X..", "..XXX", "...XX"],     # 장사진 —— 굽이치는 뱀
}
const FORM_COLS := 5
const FORM_MID := 2


## 11/6 사용자 #15: 마법 개념 삭제 —— 공격 = 공 · 책 중 높은 쪽, 방어 = 방 · 책방 중 높은 쪽. int · res 칸은 같은 값을 둔다 (옛 코드가 읽어도 같게).
## 원본 game.json 은 그대로. 능력치 보정(stat_adjust)이 끝난 뒤에 합친다. 화면 용어도 공격 · 방어로 (STATNM · MOD_LABEL · 특기 설명문)
const TXT_ALIAS := [["책략방어", "방어"], ["책방", "방어"], ["책략 피해", "피해"], ["책략 치명타", "치명타"], ["물리 피해", "피해"], ["책략을", "공격을"], ["책략이", "공격이"], ["책략 +", "공격 +"], ["책략 −", "공격 −"], ["책략 -", "공격 -"]]
const MERGE_DEF_W := 0.5      # 방어 = 방 + (책방 − 방) × 이만큼 (책방이 더 클 때) —— 0.3 으로 내려도 유생 · 술사 3장 덱 70% 그대로 (11/6): 원인은 방어가 아니다
func merge_stats() -> void:
	for k in C:
		var c: Dictionary = C[k]
		c.atk = maxf(float(c.atk), float(c["int"]))
		c["int"] = c.atk
		c["def"] = maxf(float(c["def"]), lerpf(float(c["def"]), float(c.res), MERGE_DEF_W))      # 11/6 밸런스: 책방을 다 받으면 책략계 3장 덱 승률 60~75% —— 절반만
		c.res = c["def"]
	D.STATNM["int"] = "공격"
	D.STATNM["res"] = "방어"
	for tn in PSV.traits:
		var t: Dictionary = PSV.traits[tn]
		if t.has("d"):
			for a in TXT_ALIAS:
				t.d = str(t.d).replace(a[0], a[1])
	for g in ["fire", "water", "dash", "guard", "scheme", "virtue"]:
		if PSV.has(g) and PSV[g] is Dictionary and PSV[g].has("d"):
			for a in TXT_ALIAS:
				PSV[g].d = str(PSV[g].d).replace(a[0], a[1])


func _apply_rows5() -> void:      # 이름은 그대로 —— 진형 4행 5열을 덮어쓴다
	for k in FORM45:
		if D.FORM.has(k):
			D.FORM[k].mask = FORM45[k].duplicate()


func _build_forms() -> void:
	_apply_rows5()
	for k in D.FORM:
		var f: Dictionary = D.FORM[k].duplicate(true)
		var slots := []
		var grid := []
		for ri in f.mask.size():
			var row := []
			var s: String = f.mask[ri]
			for ci in s.length():
				if s[ci] == "X":
					row.append(slots.size())
					slots.append({"line": D.LINES[ri], "row": ri, "col": ci,
						"side": "중앙" if ci == FORM_MID else "측면"})
				else:
					row.append(-1)
			grid.append(row)
		f.slots = slots
		f.grid = grid
		FORM[k] = f


func _build_pools() -> void:
	for style in ["물리", "지략", "균형"]:
		POOLS[style] = {}
		for t in TIER:
			var arr := []
			for k in C:
				if C[k].tier != t or is_foe(k):
					continue
				if style == "물리" and not PHYS_TAGS.has(C[k].tag): continue
				if style == "지략" and not INT_TAGS.has(C[k].tag): continue
				arr.append(k)
			POOLS[style][t] = arr


func _build_icons() -> void:
	for tag in D.TAGPATH:
		var p: Dictionary = D.TAGPATH[tag]
		var paint := ""
		if p.m == "s":
			paint = 'fill="none" stroke="#fff" stroke-width="%s" stroke-linecap="round"' % str(p.get("w", 1.8))
		else:
			paint = 'fill="#fff"' + (' fill-rule="evenodd"' if p.m == "e" else "")
		var svg := '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 12 12" width="12" height="12"><path %s d="%s"/></svg>' % [paint, p.d]
		var img := Image.new()
		img.load_svg_from_string(svg, 8.0)
		ICON[tag] = ImageTexture.create_from_image(img)


func _build_fonts() -> void:
	# 본문은 동봉한 나눔고딕, 제목은 나눔명조 (둘 다 OFL) —— 휴대폰에도 같은 글꼴이 나오도록 동봉한다.
	# 한자·기호처럼 나눔에 없는 글자는 시스템 글꼴로 넘긴다
	var sys := SystemFont.new()
	sys.font_names = PackedStringArray(["Malgun Gothic", "Noto Sans CJK KR", "Apple SD Gothic Neo", "Segoe UI Symbol", "Segoe UI"])
	var body: FontFile = load("res://assets/fonts/NanumGothic-Regular.ttf")
	body.fallbacks = [sys]
	font_body = body
	var bold: FontFile = load("res://assets/fonts/NanumGothic-Bold.ttf")
	bold.fallbacks = [sys]
	font_bold = bold
	var disp: FontFile = load("res://assets/fonts/NanumMyeongjo-ExtraBold.ttf")
	disp.fallbacks = [body]
	font_display = disp


# ───────── 조회 ─────────

func tier_color(k: String) -> Color:
	return KIIN_COL if C[k].kind == "kiin" else TIER[C[k].tier].c


## 등급 이름 —— 기인은 따로 (능력치 계산은 전설 등급 그대로)
func tier_name(k: String) -> String:
	return "기인" if C[k].kind == "kiin" else TIER[C[k].tier].n


const KIIN_TEXT := {"guard": "병력 70% 아래 아군이 받는 피해의 절반을 대신 받는다", "no_charge": "적 기병의 첫 돌격을 막는다",
	"no_form": "적 진형 보너스를 없앤다", "charge_up": "아군 기병의 첫 돌격 피해 +50%", "ult_block": "적 고유기 두 번을 막아 낸다",
	"ult_cut": "적이 고유기 기를 모으면 두 번까지 끊고 게이지를 비운다", "heal_cut": "적 회복 −50% · 이기면 기본패 +2",
	"ambush": "개전에 적 후열 하나를 습격 (사기 −40 · 혼란 2턴)", "form_x2": "아군 진형 보너스 3배",
	"death_gauge": "쓰러지면 아군 전원 고유기 게이지 +70 · 사기 +15", "ticket": "이기면 그날 보급 등급 선택권 +1",
	"aura_half": "적 위세 효과 절반", "revive": "처음 무너진 아군 2부대를 병력 40%로 일으켜 세운다",
	"seal": "개전과 중반에 적 전원 기술 봉인", "wind_slow": "적 고유기 기 모으기 +1초 · 편성에 있으면 토벌 적 편성을 미리 본다",
	"turncoat": "개전에 적 하나를 혼란 —— 혼란된 적은 제 편을 친다", "morale_crash": "개전에 적 전원 사기 −18"}

## 11/3 기인 —— 한 판에 각 1장, 전설 옆 단계의 기능 장수 (data/lines.json KIIN)
const KIIN_COL := Color("#2ee6c0")
func is_kiin(k) -> bool:
	return k != null and C.has(k) and C[k].kind == "kiin"


## 기능 키(guard · revive …)를 가진 기인 카드 id (없으면 "")
func kiin_card(key: String) -> String:
	return KIIN_BY_KEY.get(key, "")


## 등급 글꼴 —— 기본 · 일반은 보통 고딕, 고급 · 희귀는 명조, 전설은 굵은 고딕, 초월은 굵은 기울임, 불멸 · 신화는 더 굵은 기울임
var _tier_fonts := {}
func tier_font(t: int) -> Font:
	if _tier_fonts.is_empty():
		for i in range(1, 9):
			var base: Font = font_body if i <= 2 else (font_display if i <= 4 else font_bold)
			if i >= 6:
				var fv := FontVariation.new()
				fv.base_font = font_bold
				fv.variation_embolden = [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.5, 0.9][i - 1]
				fv.variation_transform = Transform2D(Vector2(1, 0), Vector2(0.22, 1), Vector2.ZERO)     # 기울임
				base = fv
			_tier_fonts[i] = base
	return _tier_fonts[clampi(t, 1, 8)]


func fac_color(fac: String) -> Color:
	return Color(D.FAC[fac].c)


## 인물 이름 —— "의절 관우" → "관우". 같은 인물의 여러 등급 카드가 초상 한 장을 나눠 쓴다.
## 토벌 전용 황건 카드 (11/2, tools/scripts/foe_cards.py) —— 플레이어는 얻지 못한다: 뽑기 · 상점 · 도감 · 무작위 보드에서 빠진다
## 적 전용 —— 원래 적 카드(foe)와, 11/2 줄기 재편으로 플레이어 쪽에서 뺀 카드(retired —— 토벌 편성에는 남고 초상도 그대로)
func is_foe(k: String) -> bool:
	return C[k].kind == "foe" or C[k].kind == "retired"


func person(k: String) -> String:
	var parts: PackedStringArray = C[k].name.split(" ")
	return parts[parts.size() - 1]


## 초상 —— assets/portraits/<인물>.png, 병사 카드는 assets/troops/<병종>.png 를 찾는다.
## 높은 등급 카드는 등급 그림을 먼저 찾고 없으면 한 단계씩 내려간다: 신화 → <인물>_신화 → _불멸 → _초월 → <인물>, 불멸 → _불멸 → _초월 → <인물>, 초월 → _초월 → <인물>.
## (일러스트를 등급 구간마다 따로 뽑는다 —— prompts/삼국지_일러스트_프롬프트.md)
## 없으면 null 을 돌려주고, 그리는 쪽에서 수묵 실루엣 플레이스홀더를 쓴다.
## 임포트 없이 파일을 떨궈 넣기만 하면 바뀌도록 Image 로 직접 읽는다. 파일이 없으면(내보낸 앱) 임포트된 텍스처를 쓴다.
## 신화 그림 (<인물>_신화.png) —— 고유기 컷인에 쓴다. 등급과 관계없이 그 인물의 신화 그림이 있으면 (없으면 null)
## 11/5 사용자: 신화 아래 등급(고급 ~ 불멸)이 신화 그림을 쓰는 곳(고유기 컷인 · 조합 시트 배경 · 카드 상세)에서는 같은 장면을 수수하게 그린
## <인물>_장면.png 를 먼저 쓴다 (prompts/등급별/5_장면). 없으면 지금처럼 신화 그림
func myth_art(k: String) -> Texture2D:
	if C[k].tier <= 2:
		return null
	if C[k].tier < 8:
		var low := _load_portrait("res://assets/portraits/%s_장면" % person(k))
		if low != null:
			return low
	return _load_portrait("res://assets/portraits/%s_신화" % person(k))


## 전투용 원형 얼굴 썸네일 (11/3) —— assets/faces/<인물>.png 가 있으면 (prompts/얼굴썸네일 로 그린 메달). 없으면 null
func face_tex(k: String) -> Texture2D:
	if C[k].tier <= 2 or C[k].kind == "foe":
		return null
	return _load_portrait("res://assets/faces/%s" % person(k))


func portrait(k: String) -> Texture2D:
	var base := portrait_base(k)
	return _portrait_cache.get(base) if base != "" else null


## 이 카드가 실제로 쓰는 그림 경로(확장자 없이). 그림이 하나도 없으면 ""
func portrait_base(k: String) -> String:
	if _portrait_pick.has(k):
		return _portrait_pick[k]
	var c: Dictionary = C[k]
	var cands: Array = []
	if c.tier <= 2 or c.kind == "foe":
		cands = ["res://assets/troops/%s" % c.tag]
	else:
		var p := "res://assets/portraits/%s" % person(k)
		if TIER_ART:
			if c.tier >= 8:
				cands.append(p + "_신화")
			if c.tier >= 7:
				cands.append(p + "_불멸")
			if c.tier >= 6:
				cands.append(p + "_초월")
		cands.append(p)
	var pick := ""
	for b in cands:
		if _load_portrait(b) != null:
			pick = b
			break
	_portrait_pick[k] = pick
	return pick


func _load_portrait(base: String) -> Texture2D:
	if _portrait_cache.has(base):
		return _portrait_cache[base]
	var tex: Texture2D = null
	for ext in ["png", "jpg", "jpeg", "webp"]:
		var path := "%s.%s" % [base, ext]
		var img: Image = null
		if FileAccess.file_exists(path):
			img = _load_image(path)
		elif ResourceLoader.exists(path):
			# 내보낸 앱(휴대폰)에는 원본 그림 파일이 없고 임포트된 텍스처만 들어간다
			var t = load(path)
			if t is Texture2D:
				img = t.get_image()
				if img and img.is_compressed():
					img.decompress()
		if img:
			# 11/3 사용자: 일러스트가 선명하지 않다 —— 600~900px 그림을 70px 칸에 줄이면 밉맵 없이 지글거린다. 밉맵 + 선형 밉맵 거르기(project.godot)
			if not img.has_mipmaps() and maxi(img.get_width(), img.get_height()) > 96:
				img.generate_mipmaps()
			tex = ImageTexture.create_from_image(img)
			# 네 귀퉁이가 투명하면 잘라 낸 인물 그림으로 보고, 그려진 영역만 기억해 둔다
			if img.detect_alpha() != Image.ALPHA_NONE:
				var w := img.get_width() - 1
				var h := img.get_height() - 1
				if img.get_pixel(0, 0).a < 0.1 and img.get_pixel(w, 0).a < 0.1 and img.get_pixel(0, h).a < 0.1 and img.get_pixel(w, h).a < 0.1:
					var ur := img.get_used_rect()
					_portrait_used[base] = Rect2(ur)
					_portrait_face[base] = _find_face(img, ur)
					var n := 0
					var on := 0
					for y in range(ur.position.y, ur.end.y, 8):
						for x in range(ur.position.x, ur.end.x, 8):
							n += 1
							if img.get_pixel(x, y).a > 0.5:
								on += 1
					if n > 0 and on > n * 0.77:     # 새 화풍 패널 0.79~0.89, 오려 낸 인물은 0.74 이하
						# 패널 윗변 —— 깃털·창끝이 패널 위로 튀어나와 있다. 한 줄이 거의 다 찬 첫 줄을 패널 시작으로 본다
						var top := ur.position.y
						for y in range(ur.position.y, ur.end.y, 2):
							var row := 0
							var cnt := 0
							for x in range(ur.position.x, ur.end.x, 4):
								cnt += 1
								if img.get_pixel(x, y).a > 0.5:
									row += 1
							if row > cnt * 0.85:
								top = y
								break
						_portrait_panel[base] = top
			break
	_portrait_cache[base] = tex
	return tex


## 패널째 잘린 그림인가 —— 사각형이 꽉 차 있어 칸에 맞춰 위쪽만 보여 줘도 된다
func portrait_panel(k: String) -> bool:
	return _portrait_panel.has(portrait_base(k))


## 패널 윗변의 그림 속 y —— 이보다 위는 패널 밖으로 튀어나온 깃·무기
func portrait_panel_top(k: String) -> float:
	return float(_portrait_panel.get(portrait_base(k), 0))


## 전투용 썸네일 —— 그림에서 얼굴 자리(정사각형). 잘라 낸 인물이 아니면 위쪽 가운데
func portrait_face(k: String) -> Rect2:
	var base := portrait_base(k)
	if _portrait_face.has(base):
		return _portrait_face[base]
	var tex := portrait(k)
	if tex == null:
		return Rect2()
	var ts := tex.get_size()
	var side := minf(ts.x, ts.y) * 0.55
	return Rect2((ts.x - side) / 2, ts.y * 0.1, side, side)


## 얼굴 찾기 —— 2등신 인물은 머리가 위쪽 40% 안에 있다. 머리 띠(위 18~40%)의 줄마다 가장 넓게 이어진 불투명 구간의
## 가운데를 모아 중앙값을 가로 중심으로 쓴다 (옆으로 뻗은 창·깃발에 끌려가지 않게). 크기는 인물 키의 38%
static func _find_face(img: Image, ur: Rect2i) -> Rect2:
	var h := float(ur.size.y)
	var mids := []
	var widths := []
	for y in range(int(ur.position.y + h * 0.18), int(ur.position.y + h * 0.40), 3):
		var best := 0
		var best_mid := 0.0
		var run := 0
		var start := 0
		for x in range(ur.position.x, ur.end.x, 2):
			if img.get_pixel(x, y).a > 0.5:
				if run == 0:
					start = x
				run += 2
				if run > best:
					best = run
					best_mid = start + run * 0.5
			else:
				run = 0
		if best > 0:
			mids.append(best_mid)
			widths.append(best)
	if mids.is_empty():
		return Rect2(ur.position.x, ur.position.y, ur.size.x, ur.size.x)
	mids.sort()
	var cx: float = mids[mids.size() / 2]
	var side := h * 0.38
	var cy := ur.position.y + h * 0.29
	return Rect2(cx - side / 2, cy - side / 2, side, side)


## 잘라 낸 인물 그림이면 그려진 영역, 아니면 빈 Rect2
func portrait_used(k: String) -> Rect2:
	return _portrait_used.get(portrait_base(k), Rect2())


## 그림 읽기 —— 확장자가 아니라 파일 앞머리로 형식을 가린다 (JPEG 를 .png 로 저장한 경우 등)
func _load_image(path: String) -> Image:
	var bytes := FileAccess.get_file_as_bytes(path)
	if bytes.size() < 12:
		return null
	var img := Image.new()
	var err := ERR_FILE_UNRECOGNIZED
	if bytes[0] == 0x89 and bytes[1] == 0x50 and bytes[2] == 0x4E and bytes[3] == 0x47:
		err = img.load_png_from_buffer(bytes)
	elif bytes[0] == 0xFF and bytes[1] == 0xD8:
		err = img.load_jpg_from_buffer(bytes)
	elif bytes.slice(0, 4).get_string_from_ascii() == "RIFF" and bytes.slice(8, 12).get_string_from_ascii() == "WEBP":
		err = img.load_webp_from_buffer(bytes)
	if err != OK:
		push_warning("초상 그림을 읽지 못했다 (PNG·JPEG·WebP 만 된다): " + path)
		return null
	return img


## 특기 —— {self: {name, d, m}, group: {name, d, scope, scale} 또는 null}. 고급 미만은 null.
## 개인 특기 m 은 등급 배율을 곱해 둔다. 단체 특기는 엔진이 scale 을 곱해 쓴다 (겹침 판정 때문).
var _psv_cache := {}

func passives_of(k: String):
	if _psv_cache.has(k):
		return _psv_cache[k]
	var out = null
	var c: Dictionary = C[k]
	var lad = PSV.ladder.get(person(k)) if c.tier >= 3 else null
	if lad != null:
		out = {"traits": [], "groups": []}
		for e in lad:
			if c.tier < int(e[1]) or (e.size() > 2 and c.tier > int(e[2])):
				continue
			var t: Dictionary = PSV.traits[e[0]]
			var attr: String = t.get("attr", "")
			var lv := trait_level(k, e[0])
			var sc: float = (PSV.level_scale_attr if attr != "" else PSV.level_scale)[str(lv)]
			sc *= float(PSV.get("axis_tier_mul", {}).get(attr, {}).get(str(c.tier), 1.0))      # 축 × 등급 밸런스 (10/31)
			if t.has("self"):      # 금색 특기 —— 단체 효과와 함께 주인에게만 붙는 장치
				var sm := {}
				for key in t.self:
					sm[key] = t.self[key] * (1.0 if key in PSV.flags else sc)
				out.traits.append({"name": e[0], "d": t.d, "m": sm, "attr": attr, "lv": lv})
			if t.has("scope"):
				out.groups.append({"name": e[0], "d": t.d, "scope": t.scope, "scale": sc, "attr": attr, "lv": lv})
			elif not t.has("self"):
				var m := {}
				for key in t.m:
					m[key] = t.m[key] * (1.0 if key in PSV.flags else sc)
				out.traits.append({"name": e[0], "d": t.d, "m": m, "attr": attr, "lv": lv})
		if out.traits.is_empty() and out.groups.is_empty():
			out = null
	_psv_cache[k] = out
	return out


## 특기 레벨 —— passives.json level[인물][특기][카드 등급]. 없으면 카드 등급 - 2 (고급 1 ~ 신화 6). 1~9
func trait_level(k: String, name_: String) -> int:
	var t: int = C[k].tier
	var lv = PSV.get("level", {}).get(person(k), {}).get(name_, {}).get(str(t))
	return clampi(int(lv) if lv != null else t - 2, 1, 9)


## 카드의 특기 —— 사다리 순서로 [{name, lv, group, d, mt(수치 요약)}]
func trait_list(k: String) -> Array:
	var ps = passives_of(k)
	if ps == null:
		return []
	var by := {}
	for t in ps.traits:
		by[t.name] = {"name": t.name, "lv": t.lv, "group": false, "attr": t.attr, "unique": PSV.traits[t.name].get("unique", false), "d": t.d, "mt": mods_text(t.m, 1.0, C[k].tier)}
	for g in ps.groups:
		var gmt := mods_text(PSV.traits[g.name].m, g.scale, C[k].tier)
		if by.has(g.name) and by[g.name].mt != "":      # 금색 —— 주인 장치 수치도 함께
			gmt = (gmt + " · " if gmt != "" else "") + "자신 " + by[g.name].mt
		by[g.name] = {"name": g.name, "lv": g.lv, "group": true, "attr": g.attr, "unique": PSV.traits[g.name].get("unique", false), "d": g.d, "mt": gmt}
	var out := []
	for e in PSV.ladder[person(k)]:
		if by.has(e[0]):
			out.append(by[e[0]])
	return out


## 특기 칸 색 —— 축마다 (2026-10-30: 물리 · 책략 · 도트 · 공깎 · 책략깎 · 방깎 · 책방깎 · 둔화 · 혼란 · 철벽 · 인덕), 축 없는 개인은 회황, 단체는 청록
const TRAIT_COL := {"물리": Color("#c98a2e"), "책략": Color("#3f7fc0"), "도트": Color("#c8553d"),
	"공깎": Color("#b0504a"), "책략깎": Color("#5a6fc0"), "방깎": Color("#a8893c"), "책방깎": Color("#8a5ab8"),
	"둔화": Color("#3f9aa8"), "혼란": Color("#9a5ab0"), "철벽": Color("#6f8aa6"), "인덕": Color("#4f9a5a"), "사기": Color("#d6b84a"),
	"": Color("#8a8668"), "단체": Color("#3f9a94")}

func trait_col(t: Dictionary) -> Color:
	if t.attr == "" and t.group:
		return TRAIT_COL["단체"]
	return TRAIT_COL.get(t.attr, TRAIT_COL[""])


## 단체 특기 이름 -> 정의
func group_def(name_: String) -> Dictionary:
	return PSV.traits[name_]


## 덱 점검용 —— 카드끼리 단체 특기가 닿는지 (진형 자리는 병종으로 짐작한다)
func passive_hits(g: Dictionary, owner_k: String, k: String) -> bool:
	var sc: String = g.scope
	if sc == "foe":
		return false
	if sc == "all":
		return true
	if sc == "fac":
		return C[k].fac == C[owner_k].fac
	if sc.begins_with("tag:"):
		return C[k].tag == sc.substr(4)
	if sc.begins_with("line:"):
		var front: bool = D.FRONT_WANT[C[k].tag] >= 1
		return front == (sc.find("선봉") >= 0)
	return false


const MOD_LABEL := {"atk": "공격", "def": "방어", "int": "공격", "res": "방어", "spd": "속도", "troop": "병력",      # 11/6 #15 책략 → 공격 · 책략방어 → 방어
	"morale": "시작 사기", "crit": "치명타 확률", "critd": "치명타 피해", "icrit": "치명타 확률", "rate": "스킬 발동",
	"dr": "받는 피해 -", "idr": "받는 피해 -", "rout": "패주 확률 -", "shock": "큰 손실 충격 -",
	"counter": "반격", "stres": "상태이상 저항", "low_atk": "절반 이하 공격", "avenge": "아군 이탈마다 공격",
	"opener": "첫 공격 피해", "first": "선공", "regen": "턴마다 병력", "mregen": "턴마다 사기",
	"rout_loss": "아군 이탈 충격 -", "mshield": "받는 사기 피해 -", "mdeal": "주는 사기 피해",
	"rpierce": "적 방어 무시", "front_atk": "선봉·전군 공격", "back_int": "중군·후군 공격", "foe_morale": "적 시작 사기 -",
	"ignite": "점화 확률", "fire_amp": "불타는 적에게 피해", "burn_amp": "건 화상 피해", "spread": "화상 번짐",
	"fire_res": "화상 저항", "fire_weak": "받는 화상 피해", "burn_dur": "화상 지속(턴)", "terror": "화상마다 적 사기 -", "fear": "적 패주 확률", "st_amp": "거는 상태이상 세기",
	"soak": "침수 확률", "water_amp": "잠긴 적에게 피해", "flow": "수몰 흐름", "flood_slow": "잠긴 적 속도 -", "flood_res": "수몰 저항", "fire_hit": "불길 추가 피해", "water_hit": "물살 추가 피해",
	"shatter": "와해 확률", "break_amp": "와해된 적에게 피해", "break_hit": "충격 추가 피해", "exec_break": "와해된 적 처형 문턱", "break_res": "와해 저항",
	"aim": "표식 확률", "mark_amp": "표식된 적에게 피해", "mark_hit": "관통 추가 피해", "mark_res": "표식 저항",
	"phalanx": "방진 확률", "counter_hit": "반격 피해", "phalanx_amp": "방진 중 반격 피해",
	"sow": "혼란 확률", "jolt": "맞힐 때 적 사기 -", "confuse_amp": "혼란·봉인된 적에게 피해",
	"mend": "차례마다 치료", "cheer_hit": "맞힐 때 아군 치료",
	"kill_amp": "적을 무너뜨린 뒤 다음 공격 피해", "cleave": "같은 열 이웃에게 피해", "icleave": "같은 열 이웃에게 피해",
	"int_low": "절반 아래 적에게 피해", "sk_amp": "기술 피해", "ally_sk": "아군 기술 때 충전",
	"cut_atk": "맞힐 때 적 공격 −(내 공격의)", "cut_int": "맞힐 때 적 공격 −(내 공격의)", "cut_def": "맞힐 때 적 방어 −(내 공격의)",
	"cut_res": "맞힐 때 적 방어 −(내 공격의)", "first_cut": "첫 공격 적 방어 −(내 공격의)", "open_cut_atk": "시작에 적 선봉 공격 −(내 공격의)",
	"open_cut_int": "시작에 적 후군 공격 −(내 공격의)", "open_cut_res": "시작에 적 전원 방어 −(내 공격의)",
	"awe": "꺾인 적 혼란 확률", "weak_amp": "디버프 걸린 적에게 피해",
	"rally_kill": "적을 무너뜨리면 아군 전원 사기", "cheer_turn": "차례마다 같은 열 사기(전투 전체)", "resolve": "아군이 무너지면 사기",
	"steady": "사기 60 아래에서 한 번 사기", "ult_rally": "아군 고유기 때 아군 전원 사기"}
const FLOW_LABEL := {"regen": "전투 동안 병력", "mregen": "전투 동안 사기", "mend": "전투 동안 치료", "cheer_hit": "전투 동안 맞힐 때 치료"}
const MOD_FLAT := ["morale", "mregen", "foe_morale", "burn_dur", "jolt", "rally_kill", "cheer_turn", "resolve", "steady", "ult_rally"]


## 수치 요약 —— "치명타 확률 +14% · 치명타 피해 +69%"
func mods_text(m: Dictionary, scale := 1.0, tier := 5) -> String:
	var out := []
	for k in m:
		if k == "first":
			out.append("선공")
			continue
		if k in ["kindle", "blaze", "night", "scorch", "drown", "tide", "steam", "collapse", "rush", "first_break", "chain_mark", "spot", "focus", "mark_break",
				"wall", "last_stand", "phalanx_break", "confuse_pass", "turncoat", "confuse_break", "confuse_burn", "moved", "oath", "starve", "moved_phalanx",
				"chase", "open_slow"]:      # 계열 마무리 —— 설명으로 충분
			continue
		var v: float = m[k] * (1.0 if k in PSV.flags else scale)      # 11/3 화상 지속 같은 정수 값은 전투에서도 배율 없이 (예전 화면엔 +0 으로)
		var lb: String = MOD_LABEL.get(k, k)
		var sign := "" if lb.ends_with("-") else "+"
		if k in ["regen", "mregen", "terror", "mend", "cheer_hit"]:      # 턴마다 흐르는 양 —— 11/3: 턴 하나로는 0.0 처럼 보여 '전투 동안' 합으로 적는다 (보통 길이 전투)
			v *= Battle.pace_for(tier) * (1.0 if k == "terror" else RtBattle.turns_for(tier))
			var pct: bool = k in ["regen", "mend", "cheer_hit"]
			out.append(("%s%s%.0f%%" if pct else ("%s%s%.1f" if k == "terror" else "%s%s%.0f")) % [FLOW_LABEL.get(k, lb), sign, v * 100 if pct else v])
			continue
		if k in MOD_FLAT:
			out.append("%s%s%.0f" % [lb, sign, v])
		else:
			out.append("%s%s%.0f%%" % [lb, sign, v * 100])
	return " · ".join(out)


func passive_text(k: String) -> String:
	# 특기 이름 뒤에 레벨 —— 개인 특기는 따로 적지 않고 단체만 표시한다. attr(계열)은 내부 분류라 보이지 않는다
	var lines := []
	for t in trait_list(k):
		lines.append("『%s%s』%s %s%s" % [t.name, "" if t.unique else str(t.lv), " 단체" if t.group else "", t.d, ("\n   " + t.mt) if t.mt != "" else ""])
	return "\n".join(lines)


## 고유기 —— 신화 기준 수치를 불멸 카드에는 tier7_scale, 초월 카드에는 tier6_scale 배로 줄여 준다
func ult_of(k: String):
	var base = ULT.list.get(person(k))
	if base == null:
		return null
	var u: Dictionary = base.duplicate(true)
	u.first = u.get("first", ULT.first.get(str(C[k].tier), ULT.first["6"]))      # 기인(전설 등급)은 초월 값
	u.cd = u.get("cd", ULT.cd)
	for comp in u.eff:
		if comp.has("status"):
			comp.status.k = ST_MERGE.get(comp.status.k, comp.status.k)
			if comp.status.k == "confuse":
				comp.status.dur = mini(int(comp.status.dur), 1)
	if C[k].tier <= 7:
		var s: float = ULT.tier7_scale if C[k].tier == 7 else ULT.tier6_scale
		for comp in u.eff:
			for key in ["mult", "heal", "morale"]:
				if comp.has(key):
					comp[key] = comp[key] * s
			if comp.has("buff"):
				comp.buff.amt = comp.buff.amt * s
			if comp.has("status") and comp.status.k in ["burn", "bleed", "flood", "plague"]:
				comp.status.val = comp.status.val * s
	for comp in u.eff:
		for key in ["mult", "heal", "morale"]:
			if comp.has(key):
				comp[key] = comp[key] * ULT_POWER
	# 11/3 사용자: 일반 기술이 고유기보다 세면 안 된다 —— 고유기 한 방(배율 × 그 등급 전투 turn_mul)이
	# 그 카드의 가장 센 일반 기술의 ULT_OVER 배 아래면 고유기 타격을 그만큼 올린다
	var um := 0.0
	for comp in u.eff:
		if comp.t == "hit":
			um = maxf(um, float(comp.mult))
	var sm := 0.0
	for sk in C[k].get("sks", []):
		sm = maxf(sm, float(sk.eff.get("mult", 0.0)))
	var tm := Battle.turn_mul_for(C[k].tier)
	if um > 0 and sm > 0 and um * tm < sm * ULT_OVER:
		var f := sm * ULT_OVER / (um * tm)
		for comp in u.eff:
			if comp.t == "hit":
				comp.mult = snappedf(float(comp.mult) * f, 0.01)
	u.wait = ult_wait(k, u)
	return u


## 고유기 대기 시간 (11/4 사용자: 병종이 아니라 장수마다) —— 전투 시작 뒤 이 초가 지나야 쓴다.
## 고유기 세기 점수(타격 배율 × 대상 수 + 상태 · 버프 · 회복 · 사기)가 클수록 늦게: 10 ~ 26초. ULT_WAIT 에 적은 장수는 그 값
const ULT_WAIT := {"여포": 22.0}      # 측정으로 따로 맞춘 장수 (신화 여포는 기병 첫 돌격으로 10초 안에 터지던 장수)
const TGT_N := {"front1": 1.0, "back1": 1.0, "front3": 2.2, "back2": 1.8, "denseLine": 2.2, "all": 3.5,
	"line:후군": 2.0, "line:선봉+전군": 2.0}

func ult_score(u: Dictionary) -> float:
	var sc := 0.0
	for comp in u.eff:
		var n: float = TGT_N.get(str(comp.get("tgt", "front1")), 2.0)
		if comp.t == "hit":
			sc += float(comp.get("mult", 0.0)) * n
		if comp.has("status"):
			sc += 1.2 * n
		if comp.has("buff"):
			sc += absf(float(comp.buff.amt)) * 3.0 * n
		if comp.has("heal"):
			sc += float(comp.heal) * 8.0 * n
		if comp.has("morale"):
			sc += float(comp.morale) * 0.04 * n
	return sc


func ult_wait(k: String, u: Dictionary) -> float:
	if ULT_WAIT.has(person(k)):
		return ULT_WAIT[person(k)]
	return clampf(6.0 + ult_score(u) * 0.7, 8.0, 18.0)      # 11/6 밸런스: 대기 10~26초가 판 길이(약 38초)의 절반 → 8~18초


## 능력치 보정 (솔국지 확장, data/cards_ext.json stat_adjust) —— 원본 HTML 수치(game.json)는 그대로 두고 곱한다.
## {"병종": {"등급": {"atk": 0.9, ...}}} —— 다시 부르면 원본에서 새로 계산한다 (점검 장면이 값을 바꿔 볼 때)
func set_stat_adjust(adj: Dictionary) -> void:
	STAT_ADJ = adj
	for k in C:
		var m: Dictionary = adj.get(C[k].tag, {}).get(str(C[k].tier), {})
		for s in _BASE[k]:
			C[k][s] = _BASE[k][s] * float(m.get(s, 1.0))


## 한 단계 위 등급 —— 플레이어 카드가 없는 등급(11/3 삭제한 일반)은 건너뛴다
func next_tier(t: int) -> int:
	for x in PLAY_TIERS:
		if x > t:
			return x
	return mini(8, t + 1)


func by_tier(t: int) -> Array:
	var order: Array = D.TAGORDER
	var out := []
	for k in C:
		if C[k].tier == t and not is_foe(k):
			out.append(k)
	out.sort_custom(func(a, b):
		var ta := order.find(C[a].tag)
		var tb := order.find(C[b].tag)
		if ta != tb:
			return ta < tb
		return C[a].name < C[b].name)
	return out


func aff_of(tag: String, line: String, side: String) -> String:
	var a: Dictionary = D.AFF.get(tag, {})
	if a.is_empty():
		return ""
	for z in a.pref:
		if z[0] == line and z[1] == side:
			return "pref"
	if a.bad[0] == line and a.bad[1] == side:
		return "bad"
	return ""


# ───────── 보드 생성 (원본 genBoard / autoPlace) ─────────

func gen_board(pv: float, style: String, rng: RandomNumberGenerator) -> Dictionary:
	var mid := func(t): return roundi((TIER[t].lo + TIER[t].hi) / 2.0)
	var tiers := []
	tiers.resize(9)
	tiers.fill(1)
	var spent := 9
	for g in 400:
		var lo := 0
		for i in range(1, 9):
			if tiers[i] < tiers[lo]:
				lo = i
		var t: int = tiers[lo]
		if t >= 7:
			break
		var nt := next_tier(t)
		var cost: int = mid.call(nt) - mid.call(t)
		if spent + cost > pv:
			break
		tiers[lo] = nt
		spent += cost
	var cards := []
	for t in tiers:
		var src: Array = POOLS[style].get(t, [])
		if src.is_empty():
			src = POOLS["균형"][t]
		var ok := src.filter(func(k): return C[k].tier < 8)
		if ok.is_empty():
			ok = src
		var fresh := ok.filter(func(k): return C[k].tier < 3 or not cards.any(func(x): return person(x) == person(k)))      # 같은 인물은 한 부대만
		if not fresh.is_empty():
			ok = fresh
		cards.append(ok[rng.randi() % ok.size()])
	return {"cards": cards, "form": STYLE_FORM[style]}


func auto_place(cards: Array, form: String) -> Array:
	var f: Dictionary = FORM[form]
	var fw: Dictionary = D.FRONT_WANT
	var order := cards.filter(func(k): return k != null)
	order.sort_custom(func(a, b):
		if C[a].tier != C[b].tier:
			return C[a].tier > C[b].tier
		return fw[C[a].tag] > fw[C[b].tag])
	var out := []
	out.resize(9)
	var used := []
	used.resize(9)
	used.fill(false)
	for k in order:
		var best := -1
		var bs := -1e9
		for i in f.slots.size():
			if used[i]:
				continue
			var s: Dictionary = f.slots[i]
			var z := aff_of(C[k].tag, s.line, s.side)
			var v: float = (6.0 if z == "pref" else -4.0 if z == "bad" else 0.0) \
				- absf(D.LINE[s.line].pri - (4 - fw[C[k].tag])) * 0.6
			if v > bs:
				bs = v
				best = i
		if best >= 0:
			used[best] = true
			out[best] = k
	return out


# ───────── 설명문 (원본 skillDesc) ─────────

## 11/2 실시간 엔진에서 실제로 맞는 범위 (resolve_targets 와 맞춘다)
const TGT_RT := {"front1": "맞붙은 적 1부대", "back1": "적진 가장 뒤 1부대", "back2": "적진 가장 뒤 2부대",
	"front3": "대상과 그 둘레 3부대", "all": "사거리 안 적 전체", "denseLine": "가장 밀집한 적 무리",
	"line:후군": "적 후군(뒤쪽 절반, 최대 3부대)", "line:선봉+전군": "적 선봉 · 전군(앞쪽 절반, 최대 3부대)",
	"allyAll": "아군 전체", "allyFront": "적과 가장 가까운 아군", "self": "자신"}

func tgt_name(t: String) -> String:
	if TGT_RT.has(t):
		return TGT_RT[t]
	if D.TGTNM.has(t):
		return D.TGTNM[t]
	if t.begins_with("line:"):
		return t.substr(5).replace("+", "·") + " 전체"
	return t


func skill_desc(c: Dictionary, sk = null) -> String:
	if sk == null:
		sk = c.sk
	if sk == null:
		return ""
	var e: Dictionary = sk.eff
	var p := []
	var pct := func(v): return "%d%%" % roundi(v * 100)
	match e.kind:
		"phys": p.append("적 %s에 물리 %s" % [tgt_name(e.tgt), pct.call(e.mult)])
		"int": p.append("적 %s에 책략 %s" % [tgt_name(e.tgt), pct.call(e.mult)])
	var pc := Battle.pace_for(c.tier)
	if e.has("morale"): p.append("사기 −%.1f" % (e.morale * pc))
	if e.has("pierce"): p.append("방어 %s 무시" % pct.call(e.pierce))
	if e.has("exec"): p.append("병력 %s 이하면 즉시 이탈" % pct.call(e.exec))
	if e.has("stance"): p.append("자신 반격 %s · %d턴" % [pct.call(e.stance.amt), e.stance.dur])
	if e.has("status"): p.append("『%s』 %d턴" % [D.STATUS[e.status.k].n, e.status.dur])
	if e.has("tHeal"): p.append("아군 병력 %.1f%% 회복" % (e.tHeal * pc * 100))
	if e.has("heal"): p.append("아군 전원 사기 +%d" % roundi(e.heal * (1.0 if e.get("rally", false) else pc)))
	if e.has("cleanse"): p.append("아군 상태이상 %d종 해제" % e.cleanse)
	if e.has("spd"): p.append("대상 속도 %s" % pct.call(e.spd.amt))
	if e.has("foeSpd"): p.append("대상 속도 %s" % pct.call(e.foeSpd.amt))
	if e.has("resDown"): p.append("대상 책략방어 %s" % pct.call(e.resDown.amt))
	if e.has("selfBuff"): p.append("자신 %s %s" % [D.STATNM[e.selfBuff.stat], pct.call(e.selfBuff.amt)])
	if e.has("allyBuff"): p.append("%s %s %s" % [tgt_name(e.allyBuff.tgt), D.STATNM[e.allyBuff.stat], pct.call(e.allyBuff.amt)])
	return " · ".join(p)


## 일반 기술 발동 조건 글 —— "자신 병력 60% 이하 또는 …"
## 기술 발동 안내 —— "적 맨 앞 열에 2부대 이상 · 충전 1.6" (11/3 비용)
func sk_when(sk: Dictionary) -> String:
	var t := cond_text(str(sk.get("cond", "always")))
	if sk.has("cost"):
		t += " · 충전 %s" % str(snappedf(float(sk.cost), 0.1))
	return t


func cond_text(cond: String) -> String:
	var out := []
	for one in cond.split("|"):
		var kv := one.split(":")
		var v: String = kv[1] if kv.size() > 1 else ""
		var pc := "%d%%" % roundi(float(v) * 100) if v.is_valid_float() else v
		match kv[0]:
			"always": out.append("충전되면 바로")
			"hurt": out.append("자신 병력 %s 이하" % pc)
			"ally_hurt": out.append("아군 병력 %s 이하가 있을 때" % pc)
			"foe_hurt": out.append("적 병력 %s 이하가 있을 때" % pc)
			"dense": out.append("한 열에 적 %s부대 이상" % v)
			"front_n": out.append("적 맨 앞 열에 %s부대 이상" % v)
			"foe_n": out.append("적 %s부대 이상" % v)
			"back_n": out.append("적 후열에 %s부대 이상" % v)
			"line": out.append("적 %s이 있을 때" % v)
			"no_st": out.append("『%s』 아닌 적이 있을 때" % D.STATUS[v].n)
			"ally_st": out.append("상태이상 걸린 아군이 있을 때")
			"foe_morale": out.append("적 사기가 아군 이상일 때")
			"ally_morale": out.append("아군 사기가 %s 아래일 때" % v)
			_: out.append(one)
	return " 또는 ".join(out)


## 병종 상성 배율 —— 공격 병종 a 가 수비 병종 d 를 칠 때 (1 ± amt)
func cls_mul(a: String, d: String, tier := 8) -> float:
	if CLASS_COUNTER.is_empty():
		return 1.0
	# 책략계가 끼는 상성은 등급마다 세기가 다르다 (책략은 낮은 등급에서 약하고 높은 등급에서 세다)
	var amt := float(CLASS_COUNTER.amt)
	if (INT_TAGS.has(a) or INT_TAGS.has(d)) and CLASS_COUNTER.has("int_amt"):
		amt = float(CLASS_COUNTER.int_amt.get(str(tier), amt))
	if CLASS_COUNTER.win.get(a, []).has(d):
		return 1.0 + amt
	if CLASS_COUNTER.lose.get(a, []).has(d):
		return 1.0 - amt
	return 1.0


const AURA_TO := {"all": "아군", "front": "선봉 · 전군 아군", "back": "중군 · 후군 아군", "fac": "같은 세력 아군", "rel": "인연 장수",
	"low": "병력 절반 아래 아군"}
const AURA_FOE := {"all": "적", "front": "적 선봉 · 전군", "back": "적 중군 · 후군"}
## 특수 효과 이름 —— [이름, 백분율로 보이는가]
const AURA_M := {"crit": ["치명타 확률", true], "critd": ["치명타 피해", true], "dr": ["받는 피해", false],
	"idr": ["받는 피해", false], "counter": ["반격 확률", true], "regen": ["턴마다 병력 회복", true],
	"mregen": ["턴마다 사기 회복", false], "rate": ["기술 발동", true], "rout": ["패주 저항", true], "stres": ["상태이상 저항", true],
	"low_atk": ["병력 절반 아래 공격", true], "kill_amp": ["적을 무너뜨린 뒤 피해", true], "weak_amp": ["약해진 적에게 피해", true],
	"ignite": ["점화 확률", true], "spread": ["불 번짐", true], "st_amp": ["지속 피해 세기", true], "opener": ["첫 공격 피해", true],
	"fire_res": ["화공 저항", true], "cleave": ["같은 열 이웃에게 피해", true], "icleave": ["같은 열 이웃에게 피해", true],
	"fear": ["적을 패주시킬 확률", true]}
const AURA_HIDE := ["turncoat"]      # 기인 설명(KIIN_TEXT)이 대신 적는 키


## 위세 설명 —— "의리지가: 인연 장수 공격 +12% · 방어 +12%" (이름 · 효과를 따로 쓰려면 aura_effect)
func aura_text(k: String) -> String:
	if not AURA.has(k):
		return ""
	return "%s: %s" % [AURA[k].n, aura_effect(k)]


func aura_effect(k: String) -> String:
	if not AURA.has(k):
		return ""
	var a: Dictionary = AURA[k]
	var who: String = AURA_TO.get(a.get("to", "all"), "아군")
	if a.get("to", "") == "tag" or (not a.has("to") and a.has("tag")):
		who = "아군 " + a.tag
	var parts := []
	var mine := []
	for st in a.get("ally", {}):
		mine.append(_pct(D.STATNM.get(st, st), a.ally[st]))
	for mk in a.get("m", {}):
		if mk in AURA_HIDE:
			continue
		var d: Array = AURA_M.get(mk, [mk, true])
		var v: float = a.m[mk]
		if mk in ["dr", "idr"]:
			mine.append(_pct(d[0], -v))
		elif d[1]:
			mine.append(_pct(d[0], v))
		else:
			mine.append("%s +%s" % [d[0], str(snappedf(v, 0.1))])
	if not mine.is_empty():
		parts.append(who + " " + " · ".join(mine))
	var theirs := []
	for st in a.get("foe", {}):
		theirs.append(_pct(D.STATNM.get(st, st), a.foe[st]))
	if not theirs.is_empty():
		var ft: String = a.get("foe_to", "all")
		var fw: String = ("적 " + ft.substr(4)) if ft.begins_with("tag:") else AURA_FOE.get(ft, "적")
		parts.append(fw + " " + " · ".join(theirs))
	if a.has("kiin"):
		parts.append(KIIN_TEXT.get(a.kiin, ""))
	return " / ".join(parts)


func _pct(name: String, v: float) -> String:
	return "%s %s%d%%" % [name, "+" if v > 0 else "−", roundi(absf(v) * 100)]

