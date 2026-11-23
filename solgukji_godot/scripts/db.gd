extends Node
## 게임 데이터 —— data/game.json 은 HTML 프로토타입에서 tools/scripts/extract.py 로 뽑은 것이다.
## 원본의 상수 이름(CARDDEF, FORM, AFF …)을 그대로 따라 이식 대조가 쉽도록 했다.

const PAL := {
	"ink": Color("#131A2B"), "ink2": Color("#1B2338"), "ink3": Color("#242E49"), "ink4": Color("#33405F"),
	"paper": Color("#E9E3D3"), "bamboo": Color("#C6AC7C"), "bamboo_dim": Color("#8D7B5C"),
	"seal": Color("#BE4A3C"), "jade": Color("#4F9080"), "gold": Color("#D9A64B"),
	"yeon": Color("#E58BA3"),      # 11/11 인연 —— 붉은 실(맺어진 사이)의 연분홍. 금(보상) · 옥(좋음) · 인장 붉음(나쁨)과 안 겹치는 한 색
	# 11/14 UI 감사 #7 —— 글자색은 먹 바탕(ink · ink2 · ink3) 위 4.5:1 이상. bamboo_dim · seal 은 선 · 면 · 장식에만
	"text_dim": Color("#A89574"),  # 설명 · 힌트 · 보조 글자 (ink2 위 5.4:1 · ink3 위 4.7:1)
	"danger": Color("#E0806F"),    # 빨간 글자 —— 부족 · 실패 · 위험 (ink2 위 5.6:1). 면 · 테두리는 seal
	"alarm": Color("#FF3A2D"),     # 위급 연출(위급 띠 · 멸망 띠 · 엔딩)의 선명한 붉음 —— 글자 · 상자에는 쓰지 않는다
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
var CARD_ADJ := {}      # 11/10 카드별 힘 배율 {id: 배율 | {st, tr, psv}} (data/cards_ext.json card_adjust, apply_card_adjust) —— 능력치(공 · 방 · 책 · 책방) · 병력 · 특기 세기. 속도 · PV 는 그대로
var _card_adj_on := {}  # 지금 곱해 둔 능력치 배율 (다시 불러도 겹쳐 곱하지 않게)
var _card_adj_tr := {}  # 지금 곱해 둔 병력 배율
const TIER_ART := true   # 11/10 사용자: 등급별 일러스트(<인물>_초월 · _불멸 · _기인.png)가 있는 카드만 그 그림을 쓴다 —— 없으면 기본 초상. 이전 설명: 초월 · 불멸 · 신화 전용 그림(<인물>_신화.png 등)을 쓸까 —— 10/30 사용자: 지금은 모든 등급이 기본 그림 (true 로 바꾸면 export_presets.cfg 의 exclude_filter 에서 *_초월 · *_불멸 · *_신화 도 빼야 APK 에 들어간다)
const TIER_ART_MYTH := true   # 11/11 사용자: 신화 그림(<인물>_신화.png)이 있는 신화 카드는 신화 그림으로 (예전엔 컷인 전용이라 신화 유비가 불멸 그림을 썼다). 없는 인물은 한 단계씩 아래 그림(불멸 → 초월 → 기본)
var _BASE := {}         # 보정 전 원본 능력치

var _portrait_cache := {}
var _portrait_used := {}     # 배경이 투명한 그림 -> 실제로 그려진 영역 (Rect2)
var _portrait_panel := {}    # 패널째 잘린 그림(그려진 영역이 거의 꽉 찬 사각형) —— 칸을 꽉 채워 그린다
var _portrait_face := {}     # 그림 -> 얼굴 자리 (그림 속 정사각형 Rect2) —— 전투용 썸네일 (10/30)
var _portrait_pick := {}     # 카드 key -> 실제로 쓰는 그림 경로 (등급 그림이 없으면 기본 그림)
## 11/10 점검용 —— 초상 읽기에 든 시간(마이크로초 합)을 구간별로 센다 (tests/forge_first). 시간 재기만 하고 결과에는 영향 없다
var prof := {"n": 0, "main": 0, "decode": 0, "res": 0, "mip": 0, "tex": 0, "scan": 0}
var ULT: Dictionary          # data/ultimates.json —— 불멸·신화 고유기
var INYEON := {}             # 11/11 인연 —— 이름 -> [인물 이름 4~5명] (data/inyeon.json list, 파일 순서). 고유기 합동 발동 (RtBattle._inyeon_recruit)
var INYEON_FIN := {}         # 11/12 인연기 —— 인연 이름 -> {t, n} (data/inyeon.json fin)
var INYEON_THEME := {}       # 11/12 인연 주제 —— 인연 이름 -> {t, n, plus?} (data/inyeon.json theme)
var INYEON_OF := {}         # 인물 이름 -> [그 인물이 든 인연 이름들, 파일 순서]
var PSV: Dictionary          # data/passives.json —— 개인·단체 특기
var _inyeon_of_person := {}  # 인물 이름 -> [인연 이름] (json 순서)
var CLASS_COUNTER: Dictionary # 병종 상성 (data/cards_ext.json)
var GUARD: Dictionary = {}    # 11/8 피해 두 갈래 · 병종 갑옷 · 결계 · 깎기 · 토벌 우두머리 성질 (data/cards_ext.json class_guard) —— 없으면 막 0 · 깎기 없음
var bot_mix := true           # 11/8 봇 덱 병종 섞기 (gen_board —— 같은 병종 3장까지 · 물리 · 책략 각 3장 이상). 끄면 예전 몰빵 그대로 (비교용)
var bot_shape := true         # 11/22 봇 덱 등급 섞기 (board_tiers —— 에이스 · 중견 · 바닥 계단). 끄면 예전 평평한 배분(9칸이 한 등급, 후반 초월 9장) (비교용)
var bot_yeon := true          # 11/22 봇 덱 인연 고려 (_army_pick —— 초월 이상 칸은 이미 뽑힌 장수와 인연이 맞는 인물을 먼저). 끄면 예전 무작위 (비교용)
var SKILL_COND: Dictionary   # 일반 기술 발동 조건 (data/cards_ext.json skill_cond)
var QUEST_ROSTERS: Array = []  # 토벌 고정 편성 —— 황건적 소탕 [일차][단계] (data/cards_ext.json quest_rosters, 11/2)

const PHYS_TAGS := ["창병", "기병", "궁병", "도적"]
const INT_TAGS := ["책사", "유생", "술사", "모사"]
const STYLE_FORM := {"물리": "hagik", "지략": "bangwon", "균형": "eorin"}


func _ready() -> void:
	set_process(false)      # 초상 미리 읽기(warm_portraits)가 있을 때만 돈다
	if OS.get_cmdline_user_args().has("--nothumb"):      # 점검용 —— 작은 칸도 원본 그림으로 (11/15 전과 비교)
		thumbs_on = false
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
	"UNIQUE_PHASES": [3],                              # 11/5 사용자: 유니크를 2 · 4 · 6일차 아침으로. 11/9 사용자: 세 번째(6일차) 지급 없앰 (페이즈 번호 = 일차×3). 11/11 사용자: 두 번째(4일차)도 없앰 —— 첫 지급(2일차)만, 대신 한 번 다시 뽑기
	# 11/7 사용자: 정상 플레이에서 장수가 너무 많이 만들어져 초월 · 기인은 버려지고 신화 · 불멸로만 덱이 꾸려진다 →
	# 4일차부터 희귀 · 전설 배급을 줄인다 (모두 이겼을 때 기본패 환산 누적 405 · 612 · 903 · 1321 · 1747 → 405 · 570 · 777 · 984 · 약 1165).
	# 전설 무작위 배급 5 · 6 · 7일차 6 · 9 · 7장 → 3 · 3 · 3장. 예전 값은 줄 끝 주석. 점검 tests/supply_check · tests/budget_mix
	"PICKS": [[{"t": 2, "n": 2}], [{"t": 3, "n": 1}, {"t": 1, "n": 1}], [{"t": 3, "n": 2}, {"t": 2, "n": 1}], [{"t": 4, "n": 1}, {"t": 3, "n": 1}],
		[{"t": 4, "n": 1}], [{"t": 4, "n": 1}], [{"t": 4, "n": 1}]],                 # 예전 5일차 전설 1 · 6일차 전설 1 + 희귀 1 · 7일차 전설 1
	"QUEST_REWARD": [[{"t": 3, "n": 2}], [{"t": 4, "n": 1}], [{"t": 4, "n": 1}], [{"t": 4, "n": 1}],
		[{"t": 5, "n": 1}], [{"t": 5, "n": 1}], [{"t": 5, "n": 1}]],                 # 예전 4일차 + 고급 · 6일차 + 고급 · 7일차 + 희귀
	"RANDOM_GRANT": [[], [], [{"t": 4, "n": 1}], [], [], [], []],                  # 예전 4 · 5일차 희귀 1, 6 · 7일차 희귀 1 + 전설 1
}
## 11/7 7일차 선택권 (Run.pick_list) —— 오전 · 오후 · 저녁(토너먼트 직전). 예전 [초월→전설 1] · [전설 1] · [초월→전설 1 + 희귀 2]
const DAY7_PICKS := [[{"t": 4, "n": 1}], [{"t": 4, "n": 1}], [{"t": 5, "n": 1}, {"t": 4, "n": 1}]]
## 11/9 사용자: 진형 우대(FORMBOON —— 진형마다 병종 둘에 능력치 +11~16%)를 없앴다. 칸 선호(AFF)와 같은 보상이 겹치고 화면이 복잡해서.
## data/game.json 의 FORMBOON 은 남겨 두었지만 코드는 읽지 않는다 (예전 FORMBOON_FIX 학익 · 안행 · 장사 · 추행 보정도 함께 삭제 —— 작업현황 51 에 값이 적혀 있다)


func _apply_econ() -> void:
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
	# 11/21 장수 개성 표시용 딱지 (상태이상이 아니다 —— 정화 · 저항 · 칸 수와 무관. sig_rt.shown 이 화면 상태 목록에만 넣는다)
	D.STATUS["taunted"] = {"n": "도발", "c": "#ff7a4a", "d": "적장의 도발에 걸렸다 —— 잠시 표적을 그 부대로 돌린다"}
	D.STATUS["undying"] = {"n": "불사", "c": "#ffd257", "d": "패주 직전에 버텨 섰다 —— 병력 문턱까지 물러서지 않는다"}
	CLASS_COUNTER = ext.get("class_counter", {})
	GUARD = ext.get("class_guard", {})
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
		IT[r[0]].slot = "armor" if str(r[4]) == "def" else "weapon"      # 11/13 장수 아이템 칸 둘(무기 · 갑옷) —— 주 능력치가 방어면 갑옷, 나머지는 무기
		ITEM_BY_NAME[r[1]] = r[0]
		if r[2] == "유니크":         # 11/2 사용자: 유니크 능력치 하향 —— 주 · 부 ×0.75, 계략 저항 7 → 5 (전설 레어 0.24 · 0.09 · 3 바로 위)
			IT[r[0]].pa = snappedf(IT[r[0]].pa * UNIQUE_MUL, 0.01)
			IT[r[0]].sa = snappedf(IT[r[0]].sa * UNIQUE_MUL, 0.01)
			IT[r[0]].rb = minf(IT[r[0]].rb, 5.0)
	D.IGRADE["고대"] = "#e0563a"      # 11/13 고대 등급 (레어와 유니크 사이 —— 군량 뽑기로만 나온다, data/cards_ext.json g01~g16)
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
		if C[k].tier == 1 and not is_foe(k):      # 11/9 황건 잡병(y1x, 적 전용)은 기본패가 아니다
			BASE.append(k)

	ULT = JSON.parse_string(FileAccess.open("res://data/ultimates.json", FileAccess.READ).get_as_text())
	for p in LINES.get("ults", {}):
		ULT.list[p] = LINES.ults[p]
	PSV = JSON.parse_string(FileAccess.open("res://data/passives.json", FileAccess.READ).get_as_text())
	_load_inyeon()
	D.STATUS.flood.d = "물에 잠겨 이동 · 공격이 %d%% 느려지고 기병은 돌격하지 못한다 (제방은 느려짐을 줄이고 격류는 더한다)" % roundi(float(PSV.water.slow) * 100)      # 11/9 수공 제어 전담 —— 지속 피해 없이 이감 + 돌격 봉쇄 (원본 설명 '병력이 잠기고' 는 옛 규칙)
	for p in LINES.get("ladder_from", {}):        # 11/2 (5) 새 인물 —— 닮은 인물의 특기 사다리를 빌린다 (초월까지만)
		var src: String = LINES.ladder_from[p]
		PSV.ladder[p] = PSV.ladder.get(src, []).filter(func(e): return int(e[1]) <= 6)
		if PSV.level.has(src):
			var own: Dictionary = PSV.level.get(p, {})      # 11/13 자기 표(특기 레벨을 벌린 칸)가 있으면 원래 인물 표 위에 덮는다
			var lvp: Dictionary = PSV.level[src].duplicate(true) if not own.is_empty() else PSV.level[src]
			for tn in own:
				var lt: Dictionary = lvp.get(tn, {})
				for tk in own[tn]:
					lt[tk] = own[tn][tk]
				lvp[tn] = lt
			PSV.level[p] = lvp
	for p in LINES.get("ladder", {}):          # 11/3 사용자: 장수들이 특기를 더 많이 —— 등급마다 최소 수만큼 채운 사다리 (lines.py fill_ladders)
		PSV.ladder[p] = LINES.ladder[p]
	_apply_sig()      # 11/19 장수 개성 —— 인물마다 고유 하나를 첫 등급부터 (passives.json sig)
	merge_stats()      # 11/6 #15 책략 · 책략방어 통합
	set_branch(BRANCH_TR, BRANCH_ST)      # 11/9 초월 · 기인 몸을 불멸 평균의 0.75 · 0.88 / 0.7 · 0.85 로
	CARD_ADJ = ext.get("card_adjust", {}).duplicate()
	CARD_ADJ.erase("_설명")
	apply_card_adjust()      # 11/10 전투 밸런스 —— 카드별 능력치 미세 조정 (몸 정규화 뒤에 곱한다)
	_reskill()
	_apply_roles()      # 11/9 원랜디식 역할 재배치 —— 기술 고르기(_reskill) 뒤에 (사다리가 바뀌어도 카드 기술은 그대로)
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
## 11/7 책방깎(팔문금쇄 · 저주)은 방깎으로 합쳤다 —— 무장은 필사돌격 · 저격, 책략계는 팔문금쇄 · 저주를 그대로 받는다 (종류가 맞는 것만)
const AXIS_SKILLS := {"도트": ["화공", "화시난발", "역병"], "둔화": ["수공", "철기유린"], "혼란": ["혹세", "봉계"],
	"방깎": ["필사돌격", "저격", "팔문금쇄", "저주"], "물리": ["횡소천군", "일점돌파", "일제사격"],
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
			# 11/23 사용자: 움직이며 싸우는데 '후군' 조건 —— 줄 조건은 거리 조건으로 (앞 줄 → 맞붙은 적, 뒤 줄 → 떨어져 있는 적)
			"line": out.append("front_n:1" if int(D.LINE.get(v, {}).get("pri", 1)) <= 2 else "back_n:1")
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
	for key in ["spd", "foeSpd", "defDown", "selfBuff", "allyBuff", "stance"]:
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
## 11/12 사용자: 한 줄 5칸이 꽉 찬 진형(11/12 새벽 시안)은 쓰지 않는다 —— 한 줄에 최대 3칸. 모양은 11/6 5열 시안을 되살리되 학익 · 추행의 4칸 줄을 3칸으로 고쳤다 (11/13 사용자: 한 줄 4칸까지 허용)
const FORM45 := {
	# 11/13 사용자: 고증 · 레퍼런스(삼국지 시리즈 · 전국 팔진)에 맞게 재수정 —— "방원진은 방어형인데 선봉(기병 자리)이 많고 봉시는 그 반대인데 기병이 한 칸".
	# 같은 날 사용자: "한 행에 4열까지 허용 · 3312, 3321 같은 것은 특징이 없다" —— 여덟 진형 모두 윤곽이 한눈에 다른 모양으로 다시 (줄당 최대 4칸, 9칸).
	# 예전(11/12): 어린 1·3·3·2 · 학익 3·2·1·3 · 봉시 1·2·3·3 · 안월 2·2·3·2 · 방원 3·2·2·2 · 안행 2·3·2·2 · 추행 1·2·3·3 · 장사 3·1·3·2
	"eorin":    ["..X..", ".X.X.", "X.X.X", ".XXX."],     # 어린진 —— 꼭짓점이 앞인 삼각 (1·2·3·3) 균형
	"hagik":    ["X...X", "XX.XX", ".X.X.", "..X.."],     # 학익진 —— 앞으로 벌린 두 날개가 대장에게 모인다 (2·4·2·1) 포위
	"bongsi":   [".XXX.", "XX.XX", "..X..", "..X.."],     # 봉시진 —— 넓은 화살촉과 긴 살대 (3·4·1·1) 돌격
	"anwol":    [".XXX.", "X...X", "X...X", "X...X"],     # 안월진 —— 앞으로 휜 초승달, 가운데가 빈다 (3·2·2·2) 양익 중시
	"bangwon":  [".....", ".XXX.", "X.X.X", ".XXX."],     # 방원진 —— 대장을 둘러싼 원진, 선봉 없음 (0·3·3·3) 방어
	"anhaeng":  ["..X..", ".X.X.", "X...X", "XX.XX"],     # 안행진 —— 기러기 떼의 ㅅ 자 대형 (1·2·2·4). 11/13 사용자: 비대칭(사선)은 쓰지 않는다 —— 모든 진형 좌우 대칭
	"chuhaeng": ["..X..", "..X..", ".XXX.", "XX.XX"],     # 추행진 —— 가늘고 긴 송곳 끝과 넓은 자루 (1·1·3·4) 한 점 돌파
	"jangsa":   [".X.X.", ".X.X.", ".X.X.", ".XXX."],     # 장사진 —— 두 줄로 길게 늘어선 종대 (2·2·2·3)
}
const FORM_COLS := 5
const FORM_MID := 2


## 11/6 사용자 #15: 마법 개념 삭제 —— 공격 = 공 · 책 중 높은 쪽, 방어 = 방 · 책방 중 높은 쪽. int · res 칸은 같은 값을 둔다 (옛 코드가 읽어도 같게).
## 능력치 보정(stat_adjust)이 끝난 뒤에 합친다. 화면 용어도 공격 · 방어로 (STATNM · MOD_LABEL · 특기 설명문)
## 11/7 책략방어(res)는 데이터에서 지웠다 (효과는 방어로, 같이 있으면 큰 값 하나만 —— tools/scripts/extract.py drop_res). 카드 res 칸만 남아 방어와 같은 값
const TXT_ALIAS := [["공격과 책략이", "공격이"], ["공격과 책략을", "공격을"], ["공격 · 책략이", "공격이"], ["공격 · 책략 · ", "공격 · "], ["공격 · 책략 +", "공격 +"], ["공격·책략 +", "공격 +"], ["책략 피해", "피해"], ["책략 치명타", "치명타"], ["물리 피해", "피해"], ["책략을", "공격을"], ["책략이", "공격이"], ["책략 +", "공격 +"], ["책략 −", "공격 −"], ["책략 -", "공격 -"]]
const MERGE_DEF_W := 0.5      # 방어 = 방 + (책방 − 방) × 이만큼 (책방이 더 클 때) —— 0.3 으로 내려도 유생 · 술사 3장 덱 70% 그대로 (11/6): 원인은 방어가 아니다
func merge_stats() -> void:
	for k in C:
		var c: Dictionary = C[k]
		c.atk = maxf(float(c.atk), float(c["int"]))
		c["int"] = c.atk
		c["def"] = maxf(float(c["def"]), lerpf(float(c["def"]), float(c.res), MERGE_DEF_W))      # 11/6 밸런스: 책방을 다 받으면 책략계 3장 덱 승률 60~75% —— 절반만
		c.res = c["def"]
	D.STATNM["int"] = "공격"
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
		f.full = ""      # 11/12 5칸이 꽉 찬 줄 (편성판 머리에 '선봉 5칸')
		for ri in f.mask.size():
			if str(f.mask[ri]) == "X".repeat(FORM_COLS):
				f.full = D.LINES[ri]
		FORM[k] = f
	for k in FORM.keys():
		_build_horde(k)


## 11/7 사용자: 황건적은 물량이 많았다 —— 토벌 적 전용 '대군' 진형 (horde_<진형>). 4행 5열 전 칸.
## 0~8 번 칸은 원래 진형 그대로(우두머리 장수들이 같은 모양으로 선다), 9 번부터는 빈 칸을 앞 줄 · 가운데부터 채운다 (잡병이 앞을 메운다).
## 플레이어 진형 띠에는 나오지 않는다 (foe)
const HORDE_PFX := "horde_"
func _build_horde(k: String) -> void:
	var b: Dictionary = FORM[k]
	var f: Dictionary = b.duplicate(true)
	var rows: int = b.mask.size()
	var extra := []
	for ri in rows:
		for ci in FORM_COLS:
			if int(b.grid[ri][ci]) < 0:
				extra.append([ri, ci])
	extra.sort_custom(func(x, y): return x[0] < y[0] if x[0] != y[0] else absi(x[1] - FORM_MID) < absi(y[1] - FORM_MID))
	for e in extra:
		f.grid[e[0]][e[1]] = f.slots.size()
		f.slots.append({"line": D.LINES[e[0]], "row": e[0], "col": e[1], "side": "중앙" if e[1] == FORM_MID else "측면"})
	var full := []
	for ri in rows:
		full.append("X".repeat(FORM_COLS))
	f.mask = full
	f.foe = true
	FORM[HORDE_PFX + k] = f


## 대군 잡병 —— 토벌 우두머리 편성(cards)의 가장 낮은 등급보다 drop 등급 아래(최소 floor_t) 황건 병사를 n 부대. 앞에 설 병종부터 (대군 진형의 9 번 칸부터 앞 줄 순서)
## 11/9 사용자: 기본 · 일반 등급 플레이어 부대(창병 · 궁병 · 기병 …)가 섞여 나왔다 —— 1 · 2 등급도 황건 잡병(y1x · y2x, 적 전용)으로
## 11/9 사용자: 후반에도 낮은 등급 잡병이 20칸 중 11칸을 채워 의미 없이 쓸려 나간다 —— 일차별 하한(Run.QUEST_RABBLE_FLOOR)으로 올리고, 4등급부터는 정예(y<등급>5~9)도 섞는다
func horde_rabble(cards: Array, n: int, rng: RandomNumberGenerator, drop := 2, floor_t := 1) -> Array:
	var lo := 9
	for k in cards:
		if k != null:
			lo = mini(lo, int(C[k].tier))
	var t := clampi(maxi(lo - drop, floor_t), 1, 7)
	var pool: Array = []
	for i in 10:
		var id := "y%d%d" % [t, i]
		if C.has(id):
			pool.append(id)
	var out := []
	for i in n:
		out.append(pool[rng.randi() % pool.size()])
	var fw: Dictionary = D.FRONT_WANT
	out.sort_custom(func(a, b): return fw[C[a].tag] > fw[C[b].tag])
	return out


## 11/10 사용자: 봇 이름에 랜덤성 —— 「낙양성최씨」 처럼 삼국지 지명 + 평범한 사람 이름. 판(시드)마다 달라지고 같은 시드면 같다
## (Run · Room 의 난수를 쓰지 않는다 —— 쓰면 그 뒤 난수가 밀려 기존 판 · 기록 재현이 어긋난다)
const BOT_PLACES := ["낙양", "장안", "성도", "건업", "허창", "업성", "형주", "양양", "서주", "하비", "여남", "진양", "한중", "적벽", "관도", "장판", "호로관", "오장원", "이릉", "합비", "유주", "기주", "청주", "남피", "장사", "강릉", "복양", "완성", "백제성", "강동"]
const BOT_SURNAMES := ["최", "김", "이", "박", "정", "강", "윤", "장", "한", "오", "서", "임", "조", "문", "황", "노", "백", "방", "송", "허"]
const BOT_JOBS := ["대장장이", "약방주인", "주모", "훈장", "서생", "상인", "백정", "나루지기", "마부", "포졸", "초병", "객주", "떡장수", "점쟁이", "사냥꾼", "뱃사공", "도공", "소금장수"]
const BOT_ADJ := ["떠돌이", "늙은", "젊은", "수상한", "배고픈", "느긋한", "성질급한", "눈치빠른", "은퇴한", "소문난"]
const BOT_TITLES := ["도령", "장군", "도독", "군사", "어른", "나리"]
func _bot_name_one(r: RandomNumberGenerator) -> String:
	var place: String = BOT_PLACES[r.randi() % BOT_PLACES.size()]
	var sur: String = BOT_SURNAMES[r.randi() % BOT_SURNAMES.size()]
	var job: String = BOT_JOBS[r.randi() % BOT_JOBS.size()]
	var x := r.randf()
	if x < 0.35:      # 낙양성최씨
		return "%s%s%s씨" % [place, "" if place.ends_with("성") or place.ends_with("관") else "성", sur]
	if x < 0.55:      # 허창대장장이
		return place + job
	if x < 0.75:      # 늙은서생
		return str(BOT_ADJ[r.randi() % BOT_ADJ.size()]) + job
	if x < 0.92:      # 성도김도독
		return place + sur + str(BOT_TITLES[r.randi() % BOT_TITLES.size()])
	return sur + str(BOT_TITLES[r.randi() % BOT_TITLES.size()])      # 최군사


## n 개의 서로 다른 봇 이름 —— used 는 이미 있는 이름(사람 플레이어 등)과 겹치지 않게
func gen_bot_names(seed_val, n: int, used: Array = []) -> Array:
	var r := RandomNumberGenerator.new()
	r.seed = hash("botnames:%s" % str(seed_val))
	var out := []
	var taken := used.duplicate()
	var guard := 0
	while out.size() < n and guard < 1000:
		guard += 1
		var nm := _bot_name_one(r)
		if taken.has(nm):
			continue
		taken.append(nm)
		out.append(nm)
	while out.size() < n:      # 거의 일어나지 않는다
		out.append("산적%d" % (out.size() + 1))
	return out


func _build_pools() -> void:
	for style in ["물리", "지략", "균형"]:
		POOLS[style] = {}
		for t in TIER:
			var arr := []
			for k in C:
				if C[k].tier != t or is_foe(k):
					continue
				if is_kiin(k): continue      # 11/9 기인 몸이 불멸 0.7 급이라 봇의 전설 칸에서 뺀다
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
	# 본문은 동봉한 나눔고딕, 제목은 송명 SongMyung (둘 다 OFL) —— 휴대폰에도 같은 글꼴이 나오도록 동봉한다.
	# 한자·기호처럼 나눔에 없는 글자는 시스템 글꼴로 넘긴다
	var sys := SystemFont.new()
	sys.font_names = PackedStringArray(["Malgun Gothic", "Noto Sans CJK KR", "Apple SD Gothic Neo", "Segoe UI Symbol", "Segoe UI"])
	var body: FontFile = load("res://assets/fonts/NanumGothic-Regular.ttf")
	body.fallbacks = [sys]
	font_body = body
	var bold: FontFile = load("res://assets/fonts/NanumGothic-Bold.ttf")
	bold.fallbacks = [sys]
	font_bold = bold
	# 제목 글꼴 —— 송명 단일 굵기를 살짝 굵게 (가는 획이 작은 글자에서 옅어지지 않도록). 되돌리려면 font_display = disp 한 줄
	var disp: FontFile = load("res://assets/fonts/SongMyung-Regular.ttf")
	disp.fallbacks = [body]
	var dv := FontVariation.new()
	dv.base_font = disp
	dv.variation_embolden = 0.3
	font_display = dv


## 11/10 제목 글꼴을 크기로 고른다 —— 송명(font_display)은 큰 제목에서만 좋고, 작은 글자(이 크기 미만)는 가는 획이 뭉개져 읽기 어렵다는 지적 → 굵은 고딕(font_bold).
## 임계값은 여기 한 곳 (눈으로 보고 정함, 작업현황 55). 송명만 쓰려면 TITLE_BIG = 0, 전부 고딕이면 큰 값.
const TITLE_BIG := 18.0
func title_font(fs: float) -> Font:
	return font_display if fs >= TITLE_BIG else font_bold


# ───────── 조회 ─────────

func tier_color(k: String) -> Color:
	return KIIN_COL if C[k].kind == "kiin" else TIER[C[k].tier].c


## 등급 이름 —— 기인은 따로 (능력치 계산은 전설 등급 그대로)
func tier_name(k: String) -> String:
	return "기인" if C[k].kind == "kiin" else TIER[C[k].tier].n


## 11/10 새 기인 효과 두 가지의 수치 —— 여기만 고치면 전투 · 설명 글이 같이 바뀐다 (효과 설명 · 되돌리는 법은 작업현황 54)
const KIIN_MATCHUP_DR := 0.14      # 교변 장합 —— 상성이 불리한 공격에 아군이 받는 피해 −14% (11/10 밸런스: 임시 0.20 → 0.14 —— 장합 한 칸이 승률 +33%p 로 기인 중 가장 셌다, 효과를 끈 판 +23)
const KIIN_SHARE := 0.30           # 단복 서서 —— 아군이 받는 피해 중 가까운 아군이 나눠 받는 몫 30% (11/10 밸런스: 임시 0.20 → 0.30 —— 서서 한 칸 −14%p, 효과 값 +3.6%p 로 약했다)
const KIIN_SHARE_N := 2            # 단복 서서 —— 나눠 받는 가장 가까운 아군 부대 수 (최대)

const KIIN_TEXT := {"guard": "병력 70% 아래 아군이 받는 피해의 절반을 대신 받는다", "no_charge": "적 기병의 첫 돌격을 막는다",
	"charge_up": "아군 기병의 첫 돌격 피해 +50%", "ult_block": "적 고유기 두 번을 막아 낸다",
	"ult_cut": "적이 고유기 기를 모으면 두 번까지 끊고 게이지를 비운다", "heal_cut": "적 회복 −50% · 이기면 기본패 +2",
	"ambush": "개전에 적 후열 하나를 습격 (사기 −40 · 잠시 혼란)",
	"death_gauge": "쓰러지면 아군 전원 고유기 게이지 +70 · 사기 +15", "ticket": "이기면 그날 보급 등급 선택권 +1 (전설 등급이면 랜덤권)",
	"aura_half": "적 위세 효과 절반", "revive": "처음 무너진 아군 2부대를 병력 40%로 일으켜 세운다",
	"seal": "개전과 중반에 적 전원 기술 봉인", "wind_slow": "적 고유기 기 모으기 +1초 · 편성에 있으면 토벌 적 편성을 미리 본다",
	"turncoat": "개전에 적 하나를 혼란 —— 혼란된 적은 제 편을 친다", "morale_crash": "개전에 적 전원 사기 −18"}


## 기인 기능 설명 —— 수치가 상수(KIIN_MATCHUP_DR · KIIN_SHARE · KIIN_SHARE_N)에서 오는 두 개는 여기서 만들고 나머지는 KIIN_TEXT
func kiin_text(key: String) -> String:
	match key:
		"matchup_dr":
			return "상성이 불리한 공격에 아군이 받는 피해 −%d%%" % roundi(KIIN_MATCHUP_DR * 100.0)
		"share":
			return "아군이 받는 피해의 %d%%를 가까운 아군 %d부대가 나눠 받는다" % [roundi(KIIN_SHARE * 100.0), KIIN_SHARE_N]
	return KIIN_TEXT.get(key, "")

## 11/3 기인 —— 한 판에 각 1장, 전설 옆 단계의 기능 장수 (data/lines.json KIIN)
const KIIN_COL := Color("#2ee6c0")
func is_kiin(k) -> bool:
	return k != null and C.has(k) and C[k].kind == "kiin"


## 기능 키(guard · revive …)를 가진 기인 카드 id (없으면 "")
func kiin_card(key: String) -> String:
	return KIIN_BY_KEY.get(key, "")


## 등급 글꼴 —— 기본 · 일반은 보통 고딕, 고급 · 희귀는 명조, 전설은 굵은 고딕, 초월은 굵은 기울임, 불멸 · 신화는 더 굵은 기울임
## 11/10 고급 · 희귀(명조 = 송명)도 작은 글자(fs < TITLE_BIG)에서는 굵은 고딕으로 —— fs 를 안 넘기면 큰 글자로 본다
var _tier_fonts := {}
func tier_font(t: int, fs := 99.0) -> Font:
	if (t == 3 or t == 4) and fs < TITLE_BIG:
		return font_bold
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


## 11/19 장수 개성 (passives.json sig, docs/장수_개성_정리_1119.md) —— 인물마다 고유(금색) 특기 하나를 그 인물의 첫 등급부터.
## 이미 고유가 있으면 그 고유에 설명 · 키를 붙이고 붙는 등급을 앞당긴다. 없으면 새 고유를 만든다. 개성 키는 등급 배율을 곱하지 않는다(flags).
## 사다리 덮어쓰기(ladder_from · lines.ladder)가 끝난 뒤에 —— 빌린 사다리를 고치지 않게 그 인물 사다리만 새 배열로 바꾼다
func _apply_sig() -> void:
	var sg: Dictionary = PSV.get("sig", {})
	if sg.is_empty():
		return
	var sk: Array = load("res://scripts/sig_rt.gd").KEYS
	for key in sk:
		if not PSV.flags.has(key):
			PSV.flags.append(key)
	var all_scope: Array = sg.get("scope_all", [])
	for p in sg:
		if p.begins_with("_") or p == "scope_all":
			continue
		var e: Array = sg[p]
		var t0 := 3      # 그 인물의 가장 낮은 카드부터 (사다리는 3급부터 읽는다 —— 카드가 없는 등급은 상관없다)
		var lad: Array = []
		for x in PSV.ladder.get(p, []):
			lad.append(x.duplicate())
		var hit := -1
		for i in lad.size():
			if PSV.traits.get(lad[i][0], {}).get("unique", false):
				hit = i
		var add: Dictionary = e[2]
		if hit >= 0:
			var tn: String = lad[hit][0]
			var t: Dictionary = PSV.traits[tn]
			if not add.is_empty():
				var into := "self" if (t.has("scope") or t.has("self")) else "m"
				if not t.has(into):
					t[into] = {}
				for key in add:
					t[into][key] = float(t[into].get(key, 0.0)) + float(add[key])
			if str(e[1]) != "":
				t.d = "%s · %s" % [t.d, e[1]]
			lad[hit][1] = mini(int(lad[hit][1]), t0)
		elif str(e[0]) != "":
			var nt := {"d": str(e[1]), "m": add.duplicate(), "attr": "", "unique": true}
			if all_scope.has(p):
				nt["scope"] = "all"
			PSV.traits[str(e[0])] = nt
			lad.append([str(e[0]), t0])
		PSV.ladder[p] = lad


## 카드 이름에서 인물 이름만 —— "호치 허저" → "허저" (결과 칸의 수훈처럼 좁은 자리에)
func person_of_name(nm: String) -> String:
	var parts: PackedStringArray = nm.split(" ")
	return parts[parts.size() - 1]


func person(k: String) -> String:
	var parts: PackedStringArray = C[k].name.split(" ")
	return parts[parts.size() - 1]


## 초상 —— assets/portraits/<인물>.png, 병사 카드는 assets/troops/<병종>.png (prompts/기본패), 토벌 적 카드는 assets/foes/<id>.png (prompts/토벌적) 를 찾는다.
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
## 11/15 사용자 "메달 이미지 해당 등급의 이미지를 얼굴 자르는 방식으로": 등급 그림(<인물>_기인 · _초월 · _불멸 · _신화)을 쓰는 카드는 그 그림에서 자른
## 얼굴 메달 assets/faces/<인물>_<등급>.png (tools/scripts/tier_faces.py) 을 먼저 쓴다. 없으면 기본 메달 <인물>.png
func face_tex(k: String) -> Texture2D:
	if C[k].tier <= 2 or C[k].kind == "foe":
		return null
	var art := portrait_base(k).get_file()
	if art.contains("_"):
		var ft := _load_portrait("res://assets/faces/%s" % art)
		if ft != null:
			return ft
	return _load_portrait("res://assets/faces/%s" % person(k))


## 고유기 컷인 그림 (11/15 사용자 "불멸 고유기에 신화 일러가 나오지 않도록") —— 그 카드가 쓰는 등급 그림 그대로 (불멸 → _불멸 · 초월 → _초월 · 신화 → _신화).
## 예전엔 등급과 관계없이 그 인물의 신화 그림(myth_art)을 썼다. 큰 등급 그림이 없는 카드(기본 · 기인 그림)는 null —— 그리는 쪽에서 얼굴 메달을 쓴다
func ult_art(k: String) -> Texture2D:
	var art := portrait_base(k).get_file()
	if art.ends_with("_신화") or art.ends_with("_불멸") or art.ends_with("_초월"):
		return portrait(k)
	return null


func portrait(k: String) -> Texture2D:
	var key := _pkey(k)
	return _portrait_cache.get(key) if key != "" else null


# ───────── 작은 칸용 반쪽 그림 (11/15 성능 · 메모리 —— docs/성능_1115.md) ─────────
## 초상은 압축 없는 RGBA + 밉맵으로 그래픽 메모리에 올라간다 (720×720 한 장 2.8MB). 조합 탭 미리 읽기(warm)가 190장을 다 올려 제목 화면에서 이미 350MB,
## 탭을 돌면 650MB 였다 —— 휴대폰에는 무겁다. 목록의 작은 타일(한 변 THUMB_MAX 논리 px 안쪽)은 원본의 밉맵 1단계(가로 · 세로 절반, 메모리 1/4)만 올려 그린다.
## 그 크기에서는 그래픽카드가 어차피 1단계 아래 밉맵만 읽으므로 보이는 그림은 같다. 큰 칸(카드 상세 · 조합 시트 · 컷인 · 띠)은 예전처럼 원본을 그때 읽는다.
## 캐시 열쇠: 원본은 경로 그대로, 반쪽은 경로 + "#s". 그려진 영역 · 얼굴 자리 · 패널 윗변은 원본에서 재서 반쪽 크기로 줄여 둔다 (같은 자리를 가리킨다).
## Art.draw_portrait 가 작은 칸을 그리는 동안만 small 을 켠다 —— 그 밖에서 DB.portrait · portrait_used … 를 부르면 늘 원본이다
const THUMB_FROM := 512       # 짧은 변이 이보다 큰 그림(기본 초상 558 ~ 720 정사각)만 반쪽을 만든다 —— 등급 그림(불멸 400×520 · 초월 470×600 · 기인 383×640 …)은 원래 작아 원본 그대로 (반쪽 열쇠도 원본을 가리킨다)
const THUMB_MAX := 88.0       # 칸의 긴 변(논리 px)이 이 안이면 반쪽 (목록 타일 69 · 추천 조합 타일 85). 보통 휴대폰(논리 1 = 2.7px)에서 238px —— 가장 작은 반쪽(558 → 279px)보다 작다
var thumbs_on := true         # 점검용 (--nothumb : 예전처럼 원본만)
var dbg_full := false         # 점검용 (tests/ui_perf --full) —— 원본을 읽을 때마다 이름을 찍는다 (어느 화면이 원본을 올리는지)
var small := false


## 이 카드가 지금 쓰는 그림의 캐시 열쇠 (없으면 ""). 그 그림이 캐시에 올라와 있게 한다
func _pkey(k: String) -> String:
	var base := portrait_base(k)
	if base == "":
		return ""
	if small and thumbs_on:
		var key := base + "#s"
		if not _portrait_cache.has(key):
			_load_portrait(base, true)
		return key
	if not _portrait_cache.has(base):
		_load_portrait(base)
	return base


## 이 카드가 실제로 쓰는 그림 경로(확장자 없이). 그림이 하나도 없으면 ""
func portrait_base(k: String) -> String:
	if _portrait_pick.has(k):
		return _portrait_pick[k]
	var cands: Array = _portrait_cands(k)
	var pick := ""
	for b in cands:
		if _load_portrait(b, small and thumbs_on) != null:      # 있는지만 보면 된다 —— 지금 그리는 크기로 읽는다 (원본을 괜히 올리지 않게)
			pick = b
			break
	_portrait_pick[k] = pick
	return pick


func prof_reset() -> void:
	for k in prof:
		prof[k] = 0


func prof_cache_size() -> int:
	return _portrait_cache.size()


func _load_portrait(base: String, sm := false) -> Texture2D:
	var key := base + "#s" if sm else base
	if _portrait_cache.has(key):
		return _portrait_cache[key]
	if sm and _portrait_cache.has(base):
		var ft: Texture2D = _portrait_cache[base]
		if ft == null or mini(ft.get_width(), ft.get_height()) <= THUMB_FROM:      # 그림이 없거나 원래 작다 —— 반쪽 열쇠도 원본을 가리킨다
			_alias(key, base)
			return ft
	var t0 := Time.get_ticks_usec()
	if not sm and dbg_full:
		print("FULL|", base.get_file())
	var r := _decode_portrait(base, sm)
	var tex := _finish_portrait(key, r)
	prof.main += Time.get_ticks_usec() - t0
	return tex


## 캐시 열쇠 to 가 from 과 같은 그림 · 같은 영역을 가리키게 한다
func _alias(to: String, from: String) -> void:
	_portrait_cache[to] = _portrait_cache.get(from)
	if _portrait_used.has(from):
		_portrait_used[to] = _portrait_used[from]
		_portrait_face[to] = _portrait_face[from]
	if _portrait_panel.has(from):
		_portrait_panel[to] = _portrait_panel[from]


## 밉맵이 있는 그림의 1단계(가로 · 세로 절반)를 따로 떼어 낸 그림 (밉맵 포함). 못 떼면 null
static func _mip1(img: Image) -> Image:
	if not img.has_mipmaps() or img.get_mipmap_count() < 1 or img.is_compressed():
		return null
	var w := maxi(1, img.get_width() >> 1)
	var h := maxi(1, img.get_height() >> 1)
	var data := img.get_data()
	var a := img.get_mipmap_offset(1)
	var b := img.get_mipmap_offset(2) if img.get_mipmap_count() >= 2 else data.size()
	if a <= 0 or b <= a or (b - a) % (w * h) != 0:
		return null
	var th := Image.create_from_data(w, h, false, img.get_format(), data.slice(a, b))
	if th == null or th.is_empty():
		return null
	if maxi(w, h) > 96:
		th.generate_mipmaps()
	return th


## 그림 한 장 읽기 —— 파일 읽기 · 디코드 · 밉맵 · 투명 영역 검사까지 (여기는 메인 스레드가 아니어도 된다: 자기 Image 만 만지고 DB 상태는 건드리지 않는다).
## 결과: {img, used(Rect2) · face(Rect2) — 잘라 낸 인물일 때만, panel(패널 윗변 y) — 패널째 잘린 그림일 때만, us(구간별 마이크로초)}. img 가 null 이면 그림 없음
## sm —— 작은 칸용 반쪽 (위 '작은 칸용 반쪽 그림'). 큰 그림이면 img 가 1단계 밉맵이고 영역들도 그 크기로 줄어 있다. 원래 작은 그림이면 원본 그대로 + full = true
const PORTRAIT_FACE_CENTER := {"우금": Vector2(0.53, 0.44), "주창": Vector2(0.53, 0.42), "조홍": Vector2(0.49, 0.36)}


static func _decode_portrait(base: String, sm := false) -> Dictionary:
	var out := {"img": null, "us": {"decode": 0, "res": 0, "mip": 0, "scan": 0}}
	var us: Dictionary = out.us
	for ext in ["png", "jpg", "jpeg", "webp"]:
		var path := "%s.%s" % [base, ext]
		var img: Image = null
		var t0 := Time.get_ticks_usec()
		if FileAccess.file_exists(path):
			img = _load_image(path)
			us.decode += Time.get_ticks_usec() - t0
		elif ResourceLoader.exists(path):
			# 내보낸 앱(휴대폰)에는 원본 그림 파일이 없고 임포트된 텍스처만 들어간다
			var t = load(path)
			if t is Texture2D:
				img = t.get_image()
				if img and img.is_compressed():
					img.decompress()
			us.res += Time.get_ticks_usec() - t0
		if img:
			t0 = Time.get_ticks_usec()
			# 11/3 사용자: 일러스트가 선명하지 않다 —— 600~900px 그림을 70px 칸에 줄이면 밉맵 없이 지글거린다. 밉맵 + 선형 밉맵 거르기(project.godot)
			if not img.has_mipmaps() and maxi(img.get_width(), img.get_height()) > 96:
				img.generate_mipmaps()
			us.mip += Time.get_ticks_usec() - t0
			t0 = Time.get_ticks_usec()
			out.img = img
			# 네 귀퉁이가 투명하면 잘라 낸 인물 그림으로 보고, 그려진 영역만 기억해 둔다
			if img.detect_alpha() != Image.ALPHA_NONE:
				var w := img.get_width() - 1
				var h := img.get_height() - 1
				if img.get_pixel(0, 0).a < 0.1 and img.get_pixel(w, 0).a < 0.1 and img.get_pixel(0, h).a < 0.1 and img.get_pixel(w, h).a < 0.1:
					var ur := img.get_used_rect()
					out.used = Rect2(ur)
					out.face = _find_face(img, ur)
					if base.begins_with("res://assets/portraits/") and PORTRAIT_FACE_CENTER.has(base.get_file()):
						# 깃발이나 장병기가 머리보다 높게 잡히는 초상은 얼굴 위치를 따로 맞춘다.
						var center: Vector2 = PORTRAIT_FACE_CENTER[base.get_file()] * Vector2(img.get_size())
						out.face.position = center - out.face.size * 0.5
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
						out.panel = top
			if sm:
				var th: Image = _mip1(img) if mini(img.get_width(), img.get_height()) > THUMB_FROM else null
				if th != null:
					var sc := Vector2(th.get_width() / float(img.get_width()), th.get_height() / float(img.get_height()))
					out.img = th
					if out.has("used"):
						out.used = Rect2(out.used.position * sc, out.used.size * sc)
						out.face = Rect2(out.face.position * sc, out.face.size * sc)
					if out.has("panel"):
						out.panel = out.panel * sc.y
				else:
					out.full = true
			us.scan += Time.get_ticks_usec() - t0
			break
	return out


## 읽은 그림을 캐시에 올린다 —— 메인 스레드에서 (ImageTexture 만들기 + 사전 채우기뿐이라 가볍다). 이미 캐시에 있으면(같은 그림을 먼저 읽은 경우) 버린다
func _finish_portrait(base: String, r: Dictionary) -> Texture2D:
	if _portrait_cache.has(base):
		return _portrait_cache[base]
	var tex: Texture2D = null
	if r.img != null:
		var t0 := Time.get_ticks_usec()
		tex = ImageTexture.create_from_image(r.img)
		prof.tex += Time.get_ticks_usec() - t0
		prof.n += 1
		for k in r.us:
			prof[k] += r.us[k]
		if r.has("used"):
			_portrait_used[base] = r.used
			_portrait_face[base] = r.face
		if r.has("panel"):
			_portrait_panel[base] = r.panel
	_portrait_cache[base] = tex
	if base.ends_with("#s") and (r.img == null or r.get("full", false)):      # 그림이 없거나 원래 작은 그림 —— 원본 열쇠도 같은 것을 가리킨다 (다시 읽지 않게)
		var full := base.trim_suffix("#s")
		if not _portrait_cache.has(full):
			_alias(full, base)
	return tex


# ───────── 초상 미리 읽기 (11/10) —— 처음 조합 탭을 열 때 140여 장을 한꺼번에 읽어 PC 에서 1초 가까이 멈췄다 (작업현황 60) ─────────
## 디코드 · 밉맵 · 투명 검사는 작업 스레드에서(한 번에 WARM_FLY 장), 메인 스레드는 끝난 것을 캐시에 올리기만 한다 (프레임당 WARM_US 안쪽, 적어도 한 장).
## 그림 캐시일 뿐이라 판정 · 난수에는 영향이 없다. 아직 못 읽은 그림은 그리는 쪽이 예전처럼 그 자리에서 읽는다 (portrait → _load_portrait)
const WARM_FLY := 2
const WARM_US := 2000
var warm_enabled := true      # 점검용 —— false 면 미리 읽지 않는다 (예전 동작과 비교, --nowarm)
var _warm_q: Array = []       # 읽을 그림 경로 (앞이 먼저)
var _warm_seen := {}          # 이미 줄에 올린 경로
var _warm_fly: Array = []     # [{id, base, r}] 작업 스레드에서 읽는 중


## 이 카드가 쓸 수 있는 그림 경로 후보 (앞이 먼저 —— portrait_base 가 이 순서로 고른다)
func _portrait_cands(k: String) -> Array:
	var c: Dictionary = C[k]
	if c.kind == "foe":
		return ["res://assets/foes/%s" % k, "res://assets/troops/%s" % c.tag]
	if c.tier <= 2:
		return ["res://assets/troops/%s" % c.tag]
	var p := "res://assets/portraits/%s" % person(k)
	var cands: Array = []
	if TIER_ART:
		if is_kiin(k):      # 11/10 기인은 역할 그림(<인물>_기인.png) 먼저
			cands.append(p + "_기인")
		if TIER_ART_MYTH and c.tier >= 8:      # 신화 v1 그림(<인물>_신화.png)은 지금 컷인 전용 —— 카드 초상에는 v2 가 그려진 뒤 켠다
			cands.append(p + "_신화")
		if c.tier >= 7:
			cands.append(p + "_불멸")
		if c.tier >= 6:
			cands.append(p + "_초월")
	cands.append(p)
	return cands


## 이 카드들의 초상을 미리 읽도록 줄에 올린다. front=true 면 이미 줄에 있던 것보다 앞으로 (지금 곧 볼 카드)
func warm_portraits(keys: Array, front := false) -> void:
	if not warm_enabled:
		return
	var add: Array = []
	for k in keys:
		if not C.has(k):
			continue
		for b0 in _portrait_cands(k):
			var b: String = b0 + "#s" if thumbs_on else b0      # 11/15 미리 읽기는 목록 타일용 —— 반쪽 그림을 올린다 (원본은 큰 칸이 그릴 때)
			if _portrait_cache.has(b):
				if _portrait_cache[b] != null:
					break      # 이 후보가 있으면 portrait_base 는 뒤 후보를 보지 않는다
				continue      # 그림이 없다고 알려진 후보
			if add.has(b) or (_warm_seen.has(b) and not front):
				continue
			if front:
				_warm_q.erase(b)      # 앞으로 옮긴다
			_warm_seen[b] = true
			add.append(b)
	if front:
		_warm_q = add + _warm_q
	else:
		_warm_q.append_array(add)
	if not _warm_q.is_empty():
		set_process(true)


func warm_pending() -> int:
	return _warm_q.size() + _warm_fly.size()


func _process(_dt: float) -> void:
	if _warm_q.is_empty() and _warm_fly.is_empty():
		set_process(false)
		return
	var t0 := Time.get_ticks_usec()
	var i := 0
	while i < _warm_fly.size():
		var f: Dictionary = _warm_fly[i]
		if WorkerThreadPool.is_task_completed(f.id):
			WorkerThreadPool.wait_for_task_completion(f.id)
			_warm_fly.remove_at(i)
			_finish_portrait(f.base, f.slot.r)
			if Time.get_ticks_usec() - t0 > WARM_US:
				break
		else:
			i += 1
	prof.main += Time.get_ticks_usec() - t0
	while _warm_fly.size() < WARM_FLY and not _warm_q.is_empty():
		var base: String = _warm_q.pop_front()
		if _portrait_cache.has(base):
			continue
		var slot := {"r": {}}
		var path := base.trim_suffix("#s")      # 줄의 열쇠는 캐시 열쇠 —— "#s" 가 붙어 있으면 반쪽 그림
		var sm := base.ends_with("#s")
		var id := WorkerThreadPool.add_task(func(): slot.r = DB._decode_portrait(path, sm))
		_warm_fly.append({"id": id, "base": base, "slot": slot})


func _exit_tree() -> void:
	for f in _warm_fly:
		WorkerThreadPool.wait_for_task_completion(f.id)


## 패널째 잘린 그림인가 —— 사각형이 꽉 차 있어 칸에 맞춰 위쪽만 보여 줘도 된다
func portrait_panel(k: String) -> bool:
	return _portrait_panel.has(_pkey(k))


## 패널 윗변의 그림 속 y —— 이보다 위는 패널 밖으로 튀어나온 깃·무기
func portrait_panel_top(k: String) -> float:
	return float(_portrait_panel.get(_pkey(k), 0))


## 전투용 썸네일 —— 그림에서 얼굴 자리(정사각형). 잘라 낸 인물이 아니면 위쪽 가운데
func portrait_face(k: String) -> Rect2:
	var base := _pkey(k)
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
	return _portrait_used.get(_pkey(k), Rect2())


## 그림 읽기 —— 확장자가 아니라 파일 앞머리로 형식을 가린다 (JPEG 를 .png 로 저장한 경우 등)
static func _load_image(path: String) -> Image:
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
## 11/8 신화 몸값 —— 신화(8등급) 특기 세기 배율 (불멸 → 신화 격차만. 다른 등급 사이는 그대로). 점검 도구가 바꾸면 set_myth_trait 로 (캐시를 비운다)
var myth_trait := 0.4      # 측정 (기준9 대 신화1, 병력 0.75 · 능력치 1.0): 1.0 → 신화1 73% · 0.7 → 68 · 0.5 → 70 · 0.3 → 63 · 0 → 58 (위세 몫 약 7%p)
func set_myth_trait(v: float) -> void:
	myth_trait = v
	_psv_cache.clear()

## 11/9 원랜디식 역할 재배치 (passives.json role, tools/scripts/role_assign.py) —— 불멸은 몸과 화력, 기인은 대체 못 하는 역할.
## immortal_drop: 불멸(7) 카드에서만 역할 특기를 빼고 (사다리 구간을 ~6 · 8~ 로 쪼갠다 —— 신화 · 아래 등급은 그대로) 같은 레벨의 화력 특기를 붙인다.
## kiin: 기인 카드(전설 등급 5)에 대표 특기가 없으면 붙인다 (기인 인물은 기인 카드 하나뿐). 세기 배율은 passives_of 가 곱한다
func _apply_roles() -> void:
	var r: Dictionary = PSV.get("role", {})
	for p in r.get("immortal_drop", {}):
		var lad: Array = PSV.ladder.get(p, [])
		for pair in r.immortal_drop[p]:
			var out := []
			for e in lad:
				var hi := int(e[2]) if e.size() > 2 else 99
				if e[0] != pair[0] or int(e[1]) > 7 or hi < 7:
					out.append(e)
					continue
				if int(e[1]) <= 6:
					out.append([e[0], e[1], 6])
				if hi >= 8:
					out.append([e[0], 8] if hi == 99 else [e[0], 8, hi])
			out.append([pair[1], 7, 7])
			var lv = PSV.level.get(p, {}).get(pair[0], {}).get("7")
			if lv != null:
				var lvp: Dictionary = PSV.level[p].duplicate(true)      # ladder_from 이 레벨 표를 함께 쓸 수 있어 복사해 고친다
				var lt: Dictionary = lvp.get(pair[1], {})
				lt["7"] = lv
				lvp[pair[1]] = lt
				PSV.level[p] = lvp
			lad = out
		PSV.ladder[p] = lad
	for p in r.get("kiin", {}):
		var t: String = r.kiin[p][0]
		var lad: Array = PSV.ladder.get(p, [])
		if not lad.any(func(e): return e[0] == t and int(e[1]) <= 5 and (e.size() < 3 or int(e[2]) >= 5)):
			lad.append([t, 5, 5])
			PSV.ladder[p] = lad


func passives_of(k: String):
	if _psv_cache.has(k):
		return _psv_cache[k]
	var out = null
	var c: Dictionary = C[k]
	var lad = PSV.ladder.get(person(k)) if c.tier >= 3 else null
	if lad != null:
		out = {"traits": [], "groups": []}
		var kr: Array = PSV.get("role", {}).get("kiin", {}).get(person(k), ["", 1.0])
		for e in lad:
			if c.tier < int(e[1]) or (e.size() > 2 and c.tier > int(e[2])):
				continue
			var t: Dictionary = PSV.traits[e[0]]
			var attr: String = t.get("attr", "")
			var lv := trait_level(k, e[0])
			var sc: float = (PSV.level_scale_attr if attr != "" else PSV.level_scale)[str(lv)]
			var tmul := float(t.get("tier_mul", PSV.get("axis_tier_mul", {}).get(attr, {})).get(str(c.tier), 1.0))
			sc *= tmul      # 축 × 등급 밸런스 (10/31) —— 특기에 tier_mul 이 있으면 그것 (현혹 · 요언, 11/7)
			if c.tier >= 8:
				sc *= myth_trait
			sc *= card_psv(k)      # 11/10 카드별 특기 세기 배율 (card_adjust.psv)
			if c.get("kind", "") == "kiin" and str(kr[0]) == e[0]:      # 11/9 기인 대표 역할 —— 세기 배율
				sc *= float(kr[1])
			# 11/22 금색(고유) 특기의 고정값 키(시작 사기 · 적 시작 사기 등 GROUP_FLAT) —— 축 등급 배율 · 신화 배율을 빼고 레벨표만 따른다
			# (만인적 적 시작 사기 4급 −11 > 8급 −8 · 위진 6급 −18 > 8급 −8 처럼 낮은 등급이 더 세던 역전)
			var fsc := sc
			if t.get("unique", false):
				fsc = sc / maxf(0.001, tmul * (myth_trait if c.tier >= 8 else 1.0))
			if t.has("self"):      # 금색 특기 —— 단체 효과와 함께 주인에게만 붙는 장치
				var sm := {}
				for key in t.self:
					sm[key] = t.self[key] * (1.0 if key in PSV.flags else sc)
				out.traits.append({"name": e[0], "d": t.d, "m": sm, "attr": attr, "lv": lv})
			if t.has("scope"):
				out.groups.append({"name": e[0], "d": t.d, "scope": t.scope, "scale": sc, "fscale": fsc, "attr": attr, "lv": lv})
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
## 11/9 갑옷 · 결계 깎기 양 (막 −) —— class_guard.shred 등급표, 기인 카드는 kiin 값 (없으면 등급 값)
func shred_val(k: String) -> float:
	var sh: Dictionary = GUARD.get("shred", {})
	var t := str(C[k].tier)
	return float(sh.get("kiin", sh.get(t, 0.0)) if is_kiin(k) else sh.get(t, 0.0))


## 깎기 특기 수치 한 줄 —— 현혹 · 요언은 결계, 나머지는 갑옷 (Battle._shred_key 와 같은 규칙)
func shred_text(k: String, nm: String, m: Dictionary) -> String:
	if not Battle.shield_enabled or not GUARD.has("shred"):
		return ""
	var v := roundi(shred_val(k) * 100)
	var big := roundi(shred_val(k) * float(GUARD.get("shred_big", 1.5)) * 100)
	if m.has("open_cut_def"):
		return "시작에 적 전원 결계 −%d%%p" % big
	var w := "결계" if nm == "현혹" else "갑옷"
	if m.has("first_cut"):
		return "첫 공격 적 %s −%d%%p" % [w, big]
	if m.has("cut_def"):
		return "맞힐 때 적 %s −%d%%p" % [w, v]
	return ""


func trait_list(k: String) -> Array:
	var ps = passives_of(k)
	if ps == null:
		return []
	var by := {}
	for t in ps.traits:
		# 11/20 수치를 구조(ml: mods_list 항목 배열)로도 싣는다 —— mt 는 그것을 이어 붙인 문장 (디테일창 수치 칩)
		var tml := mods_list(t.m, 1.0, C[k].tier, C[k].spd)
		var st := shred_text(k, t.name, t.m)
		if st != "":
			tml.append(mod_split(st))
		by[t.name] = {"name": t.name, "lv": t.lv, "group": false, "attr": t.attr, "unique": PSV.traits[t.name].get("unique", false), "d": turn_text(t.d, C[k].tier, C[k].spd), "mt": " · ".join(tml.map(mod_str)), "ml": tml}
	for g in ps.groups:
		var gm0: Dictionary = PSV.traits[g.name].m.duplicate()
		for fk in GROUP_FLAT:      # 11/22 고정값 키는 fscale (passives_of)
			if gm0.has(fk):
				gm0[fk] = float(gm0[fk]) * float(g.get("fscale", g.scale)) / maxf(0.001, g.scale)
		var gml := mods_list(gm0, g.scale, C[k].tier, C[k].spd)
		if by.has(g.name) and by[g.name].mt != "":      # 금색 —— 주인 장치 수치도 함께
			var own: Array = by[g.name].ml
			for oi in own.size():      # 문장은 예전처럼 "자신 " 을 한 번만 (첫 항목 앞)
				gml.append([("자신 " if oi == 0 else "") + str(own[oi][0]), own[oi][1], own[oi][2]])
		by[g.name] = {"name": g.name, "lv": g.lv, "group": true, "attr": g.attr, "unique": PSV.traits[g.name].get("unique", false), "d": turn_text(g.d, C[k].tier, C[k].spd), "mt": " · ".join(gml.map(mod_str)), "ml": gml}
	var out := []
	for e in PSV.ladder[person(k)]:
		if by.has(e[0]):
			out.append(by[e[0]])
			by.erase(e[0])      # 11/9 역할 재배치로 한 특기가 등급 구간 둘로 쪼개져 있다 —— 한 번만
	return out


## 특기 칸 색 —— 축마다 (2026-10-30: 물리 · 책략 · 도트 · 공깎 · 책략깎 · 방깎 · 둔화 · 혼란 · 철벽 · 인덕 —— 책방깎은 11/7 방깎으로 합쳤다), 축 없는 개인은 회황, 단체는 청록
const TRAIT_COL := {"물리": Color("#c98a2e"), "책략": Color("#3f7fc0"), "도트": Color("#c8553d"),
	"공깎": Color("#b0504a"), "책략깎": Color("#5a6fc0"), "방깎": Color("#a8893c"),
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


const MOD_LABEL := {"atk": "공격", "def": "방어", "int": "공격", "spd": "속도", "troop": "병력",      # 11/6 #15 책략 → 공격 (책략방어는 11/7 데이터에서 방어로)
	"morale": "시작 사기", "crit": "치명타 확률", "critd": "치명타 피해", "icrit": "치명타 확률", "rate": "기술 준비 속도",
	"dr": "받는 피해 -", "idr": "받는 피해 -", "rout": "패주 확률 -", "shock": "큰 손실 충격 -",
	"counter": "반격", "stres": "상태이상 저항", "low_atk": "절반 이하 공격", "avenge": "아군 이탈마다 공격",
	"opener": "첫 공격 피해", "first": "개전 직후 바로 행동", "regen": "일정 시간마다 병력", "mregen": "일정 시간마다 사기",
	"rout_loss": "아군 이탈 충격 -", "mshield": "받는 사기 피해 -", "mdeal": "주는 사기 피해",
	"rpierce": "적 방어 무시", "front_atk": "적과 맞붙은 동안 공격", "back_int": "싸움에서 떨어져 있는 동안 책략", "foe_morale": "적 시작 사기 -",
	"ignite": "점화 확률", "fire_amp": "불타는 적에게 피해", "burn_amp": "건 화상 피해", "spread": "화상 번짐",
	"fire_res": "화상 저항", "fire_weak": "받는 화상 피해", "burn_dur": "화상 지속", "terror": "불타는 적 사기 -", "fear": "적 패주 확률", "st_amp": "거는 상태이상 세기",
	"soak": "침수 확률", "water_amp": "잠긴 적에게 피해", "flow": "수몰 흐름", "flood_slow": "잠긴 적 속도 -", "flood_res": "수몰 저항", "fire_hit": "불길 추가 피해", "water_hit": "물살 추가 피해",
	"shatter": "와해 확률", "break_amp": "와해된 적에게 피해", "break_hit": "충격 추가 피해", "exec_break": "와해된 적 처형 문턱", "break_res": "와해 저항",
	"aim": "표식 확률", "mark_amp": "표식된 적에게 피해", "mark_hit": "관통 추가 피해", "mark_res": "표식 저항",
	"phalanx": "방진 확률", "counter_hit": "반격 피해", "phalanx_amp": "방진 중 반격 피해",
	"sow": "혼란 확률", "jolt": "맞힐 때 적 사기 -", "confuse_amp": "혼란·봉인된 적에게 피해",
	"mend": "주기마다 치료", "cheer_hit": "맞힐 때 아군 치료",
	"kill_amp": "적을 무너뜨린 뒤 다음 공격 피해", "cleave": "맞힌 적 주변에 피해", "icleave": "맞힌 적 주변에 피해",
	"int_low": "절반 아래 적에게 피해", "sk_amp": "기술 피해", "ally_sk": "아군이 기술을 쓰면 내 기술 준비",
	"cut_atk": "맞힐 때 적 공격 −(내 공격의)", "cut_int": "맞힐 때 적 공격 −(내 공격의)", "cut_def": "맞힐 때 적 방어 −(내 공격의)",
	"first_cut": "첫 공격 적 방어 −(내 공격의)", "open_cut_atk": "시작에 적 선봉 공격 −(내 공격의)",
	"open_cut_int": "시작에 적 후군 공격 −(내 공격의)", "open_cut_def": "시작에 적 전원 방어 −(내 공격의)",
	"awe": "꺾인 적 혼란 확률", "weak_amp": "디버프 걸린 적에게 피해",
	"rally_kill": "적을 무너뜨리면 아군 전원 사기", "cheer_turn": "주변 아군 사기",      # 11/19 값은 mods_text 가 '약 N초마다 +X' 로 (행동할 때마다 준다)
	"resolve": "아군이 무너지면 사기",
	"steady": "사기 60 아래에서 한 번 사기", "ult_rally": "아군 고유기 때 아군 전원 사기"}
## 11/19 사용자: 장수 정보창 고유 특기 설명에 개성 키가 날것으로 보였다 ("seek_low+50% · amp_low+30%") —— 장수 개성 키(sig_rt.gd KEYS)의 글.
## [글, 꼴] 꼴: "%" 백분율 · "n" 숫자 · "" 적지 않는다(표적 고르기 · 행동 —— 특기 설명 문장이 말해 준다). 글이 "-" 로 끝나면 깎는 값
const SIG_LABEL := {
	"taunt": ["", ""], "seek_low": ["", ""], "seek_gen": ["", ""], "seek_back": ["", ""], "seek_cav": ["", ""], "seek_strong": ["", ""], "seek_guard": ["", ""],
	"no_pin": ["", ""], "charge_run": ["", ""], "shove": ["", ""], "chain": ["", ""], "undying": ["", ""], "morale_floor": ["", ""], "kite": ["", ""],
	"hit_run": ["", ""], "blink": ["", ""], "stealth": ["", ""], "ambush": ["", ""], "rear_spawn": ["", ""], "truce": ["", ""], "mark": ["", ""], "trap": ["", ""],
	"rain": ["", ""], "confuse_aura": ["", ""], "cleanse_aura": ["", ""],
	"escort": ["", ""], "seek_rear": ["", ""], "burn_out": ["", ""], "twin": ["", ""],      # 1.2 창병
	"rear_land": ["착지 기습 피해(공격의)", "%"], "breach": ["돌파에 꺾이는 적 사기", "n"], "rescue": ["구한 아군 받는 피해 -", "%"], "bridge": ["호령에 꺾이는 적 사기", "n"],      # 11/22 특별한 특기
	"feign_fire": ["", ""], "breakout": ["포위 돌파 사격 피해(공격의)", "%"], "flee": ["빠져나갈 때 받는 피해 -", "%"], "body_guard": ["둘레 아군 대신 받는 피해", "%"],
	"die_hard": ["병력이 줄수록 공격 최대", "%"], "dr_last": ["아군 다섯 이하일 때 받는 피해 -", "%"],
	"fire_chain": ["", ""], "revive": ["무너지는 부대를 일으킬 때 병력", "%"], "gauge_cut": ["10초마다 적 고유기 기 -", "n"], "cult": ["걸린 적 한 부대마다 주변 아군 사기", "n"], "dr_early_all": ["개전 20초 동안 아군 받는 피해 -", "%"],      # 1.2 책사 · 술사
	"amp_low": ["병력이 꺾인 적에게 피해", "%"], "amp_cav": ["기병에게 피해", "%"], "amp_strong": ["더 센 적에게 피해", "%"], "amp_gen": ["고유기를 가진 적에게 피해", "%"],
	"amp_rear": ["옆 · 뒤에서 칠 때 피해", "%"], "amp_open": ["첫 세 번 공격 피해", "%"], "amp_same": ["같은 적을 칠수록 피해 최대", "%"],
	"amp_still": ["제자리에서 쏠 때 피해", "%"], "amp_come": ["다가오는 적에게 피해", "%"], "amp_drown": ["수몰 · 혼란한 적에게 피해", "%"],
	"amp_allies": ["아군이 많이 남을수록 피해 최대", "%"], "amp_early": ["개전 초반 피해", "%"], "amp_late": ["싸움이 길어질수록 피해 최대", "%"],
	"amp_last": ["아군 다섯 이하일 때 피해", "%"], "amp_behind": ["아군이 밀릴수록 피해 최대", "%"], "amp_far": ["멀리서 쏠수록 피해 최대", "%"],
	"amp_kill": ["적을 무너뜨릴수록 피해 최대", "%"], "amp_guard": ["방진을 친 적에게 피해", "%"], "charge_amp": ["돌격 피해", "%"],
	"dr_still": ["제자리에서 받는 피해 -", "%"], "dr_link": ["옆 창병과 붙어 서면 받는 피해 -", "%"], "dr_low": ["병력이 줄수록 받는 피해 최대 -", "%"],
	"dr_early": ["개전 20초 동안 받는 피해 -", "%"], "dr_guard": ["방진을 친 동안 받는 피해 -", "%"], "dodge_big": ["큰 한 방을 피할 확률", "%"], "ult_dr": ["아군이 받는 적 고유기 피해 -", "%"],
	"bind": ["맞힌 적을 묶을 확률", "%"], "slow_on": ["맞힌 적 속도 -", "%"], "morale_on": ["맞힌 적 사기 -", "n"], "gauge_on": ["맞힌 적 고유기 기 -", "n"],
	"bleed_on": ["출혈을 입힐 확률", "%"], "pierce_hit": ["뒤의 적에게 꿰뚫는 피해", "%"], "throw": ["던지기 피해(공격의)", "%"],
	"counter_all": ["붙은 적 전부에게 반격 피해", "%"], "enrage": ["크게 맞은 뒤 공격", "%"], "ult_ret": ["적 고유기 되받아치기 피해", "%"],
	"kill_gauge": ["적을 무너뜨리면 고유기 기", "n"], "absorb": ["무너뜨린 적 병력을 거두는 몫", "%"], "ally_calm": ["주변 아군 패주 확률 -", "%"],
	"roar": ["4초마다 주변 적 사기 -", "n"], "cheer_aura": ["4초마다 주변 아군 사기", "n"],      # 11/19 '주기마다 · 일갈마다' 는 얼마마다인지 알 수 없었다 —— 오라 주기(sig_rt.gd AURA_T = 4초)
	"spd_aura": ["주변 아군 속도", "%"], "def_aura": ["주변 아군 방어", "%"],
	"atk_down": ["주변 적 공격 -", "%"], "cav_aura": ["아군 기병 공격", "%"], "caster_aura": ["아군 책략 부대 공격", "%"], "tier_aura": ["아군 최고 등급 부대 공격", "%"],
	"boost_best": ["가장 강한 아군 장수 공격", "%"], "give_troops": ["꺾인 아군에게 나눠 주는 병력", "%"], "quake": ["주변 적 속도 -", "%"],
	"gauge_aura": ["4초마다 아군 고유기 기", "n"], "frail_water": ["받는 수몰 피해", "%"],
	"cav_show": ["", ""]}
const FLOW_LABEL := {"regen": "전투 동안 병력", "mregen": "전투 동안 사기", "mend": "전투 동안 치료", "cheer_hit": "전투 동안 맞힐 때 치료"}
const GROUP_FLAT := ["morale", "foe_morale"]      # 11/22 금색 단체 특기에서 등급 · 신화 배율 대신 레벨표만 따르는 고정값 키 (passives_of fscale)
const MOD_FLAT := ["morale", "mregen", "foe_morale", "burn_dur", "jolt", "rally_kill", "cheer_turn", "resolve", "steady", "ult_rally"]
## 11/19 사용자: "속도 100 = 초당 1번 공격"(RtBattle.spd_rule) —— 행동할 때마다 일어나는 효과 (Battle._turn_start · _after_hit).
## 이들의 '전투 동안' 합계는 정산 횟수(turns_for)가 아니라 그 카드의 행동 횟수(acts_for)로 곱한다. regen · mregen · terror 는 정산(_settle · tick_status)마다라 그대로.
## 독전(cheer_turn)도 행동마다지만 합계 대신 '약 N초마다 +X' 로 적는다
const MOD_PER_ACT := ["mend", "cheer_hit"]


## 수치 요약 —— "치명타 확률 +14% · 치명타 피해 +69%" (mods_list 를 이어 붙인다 —— 문장과 칩이 같은 계산을 쓴다)
func mods_text(m: Dictionary, scale := 1.0, tier := 5, spd := 0.0) -> String:
	return " · ".join(mods_list(m, scale, tier, spd).map(mod_str))


## mods_list 한 항목 → 문장 조각
func mod_str(e: Array) -> String:
	return str(e[0]) + str(e[1]) + ((" (%s)" % e[2]) if str(e[2]) != "" else "")


## 11/20 수치를 구조로 —— [글, 값, 덧말] 배열 (문장 = 글 + 값 + " (덧말)"). 디테일창 능력 카드의 수치 칩이 쓴다 (mod_chip). 값이 없는 항목은 글만
func mods_list(m: Dictionary, scale := 1.0, tier := 5, spd := 0.0) -> Array:
	var out := []
	for k in m:
		if k == "first":
			out.append(["개전 직후 바로 행동", "", ""])
			continue
		if k == "int" and m.has("atk"):      # 11/11 사용자: 공격 · 책략이 합쳐진 뒤(11/6 #15) '공격+5% · 공격+5%' 로 두 번 적혔다 —— 한 번만 (큰 값)
			continue
		if k in ["kindle", "blaze", "night", "scorch", "drown", "tide", "steam", "collapse", "rush", "first_break", "chain_mark", "spot", "focus", "mark_break",
				"wall", "last_stand", "phalanx_break", "confuse_pass", "turncoat", "confuse_break", "confuse_burn", "moved", "oath", "starve", "moved_phalanx",
				"chase", "open_slow"]:      # 계열 마무리 —— 설명으로 충분
			continue
		if k in ["cut_def", "first_cut", "open_cut_def"] and Battle.shield_enabled and GUARD.has("shred"):      # 11/9 갑옷 · 결계 깎기 —— 수치는 엔진 등급표 (trait_list 가 shred_text 로 적는다)
			continue
		var sig_lab: Dictionary = SIG_LABEL if SIG_LABEL.has(k) else load("res://scripts/sig_rt.gd").LABELS_SCHOLAR      # 11/21 모사 · 유생 새 키의 글은 sig_rt 에
		if sig_lab.has(k):      # 11/19 장수 개성 키 —— 등급 배율 없이, 제 글로 (행동뿐인 키는 설명 문장에 맡긴다)
			var se: Array = sig_lab[k]
			if str(se[0]) == "":
				continue
			var sv := float(m[k]) * float(load("res://scripts/sig_rt.gd").tier_mul(k, int(tier)))      # 11/21 등급 세기 키(sig_rt TIER_KEYS)는 그 등급 값으로
			var sl: String = se[0]
			var ssign := "" if sl.ends_with("-") else " +"
			if str(se[1]) == "%":
				out.append([sl + ssign.left(1), "%s%d%%" % [ssign.substr(1), roundi(sv * 100.0)], ""])
			else:
				out.append([sl + ssign.left(1), ssign.substr(1) + (str(roundi(sv)) if is_equal_approx(sv, roundf(sv)) else "%.1f" % sv), ""])
			continue
		var mv: float = maxf(float(m[k]), float(m["int"])) if k == "atk" and m.has("int") else float(m[k])
		var v: float = mv * (1.0 if k in PSV.flags else scale)      # 11/3 화상 지속 같은 정수 값은 전투에서도 배율 없이 (예전 화면엔 +0 으로)
		var lb: String = MOD_LABEL.get(k, k)
		var sign := "" if lb.ends_with("-") or mv < 0.0 else "+"      # 1.2 음수 값은 '방어+-6%' 가 아니라 '방어-6%'
		if k == "terror":      # 11/19 불타는 적은 정산 한 번(Battle.tick_status)마다 사기가 깎인다 —— '화상마다 −0.4' 는 무엇마다인지 알 수 없었다
			out.append([lb, "%.1f" % (v * Battle.pace_for(tier)), sec_text(1, tier) + "마다"])
			continue
		if k == "cheer_turn":      # 11/19 독전 —— 행동할 때마다 주변 아군 사기 + (Battle._turn_start: 값 / 턴 배율). 날값(8)을 '전투 동안 +8' 이라 적고 있었다 —— 한 번에 오르는 값과 간격으로
			out.append([lb + " ", "+%.1f" % (v / Battle.turn_mul_for(tier)), sec_str(act_sec(tier, spd)) + "마다"])
			continue
		if k == "rate":      # 11/19 사용자: "충전 1.1 이런 것도 모호하다" —— 행동마다 기술 준비가 이만큼 더 찬다. 그 등급 기본값(D.RATE) 대비 빨라지는 비율로
			var rb := float(D.RATE.get(str(int(tier)), 0.0))
			out.append([lb, "+%.0f%%" % ((v / rb if rb > 0.0 else v) * 100), ""])
			continue
		if k in ["regen", "mregen", "mend", "cheer_hit"]:      # 턴마다 흐르는 양 —— 11/3: 턴 하나로는 0.0 처럼 보여 '전투 동안' 합으로 적는다 (보통 길이 전투)
			v *= Battle.pace_for(tier) * (acts_for(tier, spd) if k in MOD_PER_ACT else RtBattle.turns_for(tier))      # 11/19 인술 · 위무는 행동마다 (acts_for), 회복 · 사기 회복은 정산마다
			var pct: bool = k in ["regen", "mend", "cheer_hit"]
			out.append([FLOW_LABEL.get(k, lb), sign + (("%.0f%%" % (v * 100)) if pct else ("%.0f" % v)), ""])
			continue
		if k == "burn_dur":      # 11/14 화상 지속 —— 턴 대신 초
			out.append([lb + " ", "+" + sec_text(v, tier), ""])
		elif k in MOD_FLAT:
			out.append([lb, sign + ("%.0f" % v), ""])
		elif absf(v * 100) < 5.0 and absf(v * 100 - roundf(v * 100)) >= 0.05:      # 11/13 작은 % 는 한 자리까지 —— 정수로 반올림하면 레벨이 올라도 '+1% · +1%' 로 같아 보였다
			out.append([lb, sign + ("%.1f%%" % (v * 100)), ""])
		else:
			out.append([lb, sign + ("%.0f%%" % (v * 100)), ""])
	return out


## 수치 칩용 —— mods_list 항목을 [값, 글] 로. "받는 피해 -" + "30%" → ["−30%", "받는 피해"], 값이 없으면 ["", 글]
func mod_chip(e: Array) -> Array:
	var lb := str(e[0]).strip_edges()
	var v := str(e[1])
	if v == "":
		return ["", lb]
	if lb.ends_with("-") or lb.ends_with("−"):
		lb = lb.left(lb.length() - 1).strip_edges()
		v = "−" + v.trim_prefix("+")
	elif lb.contains(" −(내 공격의)"):
		lb = lb.replace(" −(내 공격의)", "") + " (내 공격의)"
		v = "−" + v.trim_prefix("+")
	if str(e[2]) != "":
		lb += " · " + str(e[2])
	return [v, lb]


## "첫 공격 적 갑옷 −30%p" 같은 완성 문장 조각을 [글, 값, ""] 로 —— 마지막 낱말이 수치일 때만 (아니면 글만)
func mod_split(s: String) -> Array:
	var i := s.rfind(" ")
	if i > 0:
		var tail := s.substr(i + 1)
		if tail.length() > 0 and (tail[0] in "+-−" or tail[0].is_valid_int()):
			return [s.substr(0, i + 1), tail, ""]
	return [s, "", ""]


## 11/14 전투가 실시간이라 화면에는 '턴' 대신 초로 —— 턴 수 × 그 등급 한 턴 길이(RtBattle.turn_sec), 0.5초 단위 (최소 0.5). 수치 · 판정은 그대로
func sec_text(turns: float, tier: float) -> String:
	return sec_str(turns * RtBattle.turn_sec(tier))


## 11/19 사용자: "속도 100 = 초당 1번 공격" —— 그 카드가 한 번 행동하는 간격(초) = RtBattle.SPD_RULE_BASE / 속도 (RtBattle._interval 과 같은 식).
## 행동마다 일어나는 것(기술 준비 · 독전 · 인술 · 방진 · 잔기술)의 글에 쓴다. 카드 기본 속도라 전투 중 사기 · 버프 · 수몰로 달라진다 (그래서 '약').
## 속도를 모르거나(0) 규칙이 꺼져 있으면 예전처럼 그 등급 한 턴 길이. 지속 시간('N턴')은 정산 간격(period)마다 줄어 sec_text 그대로다
func act_sec(tier: float, spd: float) -> float:
	if RtBattle.spd_rule and spd > 0.0:
		return RtBattle.SPD_RULE_BASE / maxf(20.0, spd)
	return RtBattle.turn_sec(tier)


## 보통 길이 전투(RtBattle.BATTLE_SEC) 한 판의 행동 횟수 —— '전투 동안' 합계용 (mods_text)
func acts_for(tier: float, spd: float) -> float:
	return RtBattle.BATTLE_SEC / act_sec(tier, spd)


## 초 → "약 X초" (0.5초 단위, 최소 0.5)
func sec_str(sec: float) -> String:
	var s := maxf(0.5, snappedf(sec, 0.5))
	return "약 %s초" % (str(roundi(s)) if is_equal_approx(s, roundf(s)) else "%.1f" % s)


var _turn_re: RegEx

## 데이터 설명글의 'N턴' · '턴마다' 를 그 카드 등급의 초로 (데이터 원문은 그대로 둔다)
## 11/19 '턴마다'(독전 · 인술 · 방진)는 엔진에서 그 부대가 행동할 때마다(Battle._turn_start)라 이제 100 / 속도 초 (act_sec) —— spd 를 받는다.
## 'N턴'(상태 · 버프 지속)과 '턴마다 한 번'(추격 —— _turn 이 바뀔 때)은 정산 간격(period)이라 예전 환산(sec_text) 그대로
func turn_text(s: String, tier: float, spd := 0.0) -> String:
	if s.find("턴") < 0:
		return s
	s = s.replace("첫 턴에", "개전 직후").replace("몇 턴 동안", "잠시").replace("턴마다 한 번", sec_text(1, tier) + "마다 한 번") \
		.replace("턴마다", sec_str(act_sec(tier, spd)) + "마다").replace("한 턴 더", sec_text(1, tier) + " 더")
	if _turn_re == null:
		_turn_re = RegEx.create_from_string("(\\d+)턴")
	var ms := _turn_re.search_all(s)
	for i in range(ms.size() - 1, -1, -1):
		var m: RegExMatch = ms[i]
		s = s.substr(0, m.get_start()) + sec_text(float(m.get_string(1)), tier) + s.substr(m.get_end())
	return s


func passive_text(k: String) -> String:
	# 특기 이름 뒤에 레벨 —— 개인 특기는 따로 적지 않고 단체만 표시한다. attr(계열)은 내부 분류라 보이지 않는다
	var lines := []
	for t in trait_list(k):
		lines.append("『%s%s』%s %s%s" % [t.name, "" if t.unique else str(t.lv), " 단체" if t.group else "", t.d, ("\n   " + t.mt) if t.mt != "" else ""])
	return "\n".join(lines)


## ───────── 인연 (11/11) —— 고유기를 함께 발동하는 장수 조합. 장수는 인물 이름(DB.person), 고유기가 있는 인물만 ─────────
func _load_inyeon() -> void:
	INYEON = {}
	_inyeon_of_person = {}
	var f := FileAccess.open("res://data/inyeon.json", FileAccess.READ)
	if f == null:
		return
	var d = JSON.parse_string(f.get_as_text())
	if not (d is Dictionary):
		return
	INYEON = d.get("list", {})
	INYEON_FIN = d.get("fin", {})
	INYEON_THEME = d.get("theme", {})
	for nm in INYEON:
		for p in INYEON[nm]:
			if not _inyeon_of_person.has(p):
				_inyeon_of_person[p] = []
			_inyeon_of_person[p].append(nm)
	INYEON_OF = _inyeon_of_person      # 전투(RtBattle)가 읽는 이름 —— 같은 사전


## 11/13 아이템 등급 순서 (높은 것부터) · 칸 이름 —— 장수마다 무기 한 칸 · 갑옷 한 칸
const IGRADE_ORDER := ["유니크", "고대", "레어", "매직", "일반"]
const ISLOT_NAME := {"weapon": "무기", "armor": "갑옷"}
func item_slot(id) -> String:
	return str(IT[id].slot) if id != null and IT.has(id) else ""


## 11/12 인연기 —— 합동 고유기 뒤에 터지는 그 인연만의 효과 {t: fire|duel|rally, n: 이름}. 없으면 빈 사전
const INYEON_FIN_KIND := {"fire": "화공", "duel": "일기토", "rally": "고무"}
const INYEON_FIN_DESC := {"fire": "적 전체 화상", "duel": "적 최강 장수에게 일격 · 사기 감소", "rally": "아군 전체 사기 · 공격 상승"}
func inyeon_fin(nm: String) -> Dictionary:
	return INYEON_FIN.get(nm, {})


## 인연기 한 줄 설명 (디테일창 · 편성 시트) —— 없으면 ""
func inyeon_fin_text(nm: String) -> String:
	var f := inyeon_fin(nm)
	if f.is_empty():
		return ""
	return "인연기 『%s』 —— %s (3명이면 더 강하게)" % [f.n, INYEON_FIN_DESC.get(f.t, "")]


## 11/12 인연 주제 —— 연쇄가 끝나면 그 인연 계열의 큰 효과 (RtBattle._inyeon_theme_fire)
const INYEON_THEME_KIND := {"ignite": "점화", "spread": "불길 번짐", "blaze": "연소", "steam": "증기", "flood": "침수", "tide": "백의도강",
	"counter": "반격", "chase": "추격", "momentum": "기세", "exec": "비장", "confuse": "혼란", "slow": "둔화", "ambush": "매복",
	"plague": "역병", "cleanse": "정화", "duel": "일기토"}
const INYEON_THEME_DESC := {"ignite": "적 전원 화상, 이미 타는 적은 남은 화상이 즉시 터진다", "spread": "적 선봉 화상, 타는 적마다 주변으로 번진다",
	"blaze": "타는 적의 불길이 거세지고 안 타는 적은 화상", "steam": "적 전원 수몰 · 화상, 화상 ×1.3", "flood": "적 전원 수몰, 병력이 바닥난 적은 휩쓸려 패주",
	"tide": "적 후군 수몰 + 기습", "counter": "아군 전원 반격 확률 · 반격 피해 크게 (잠시)", "chase": "연쇄 장수마다 적을 몰아친다 (무너진 적만큼)",
	"momentum": "아군 전원 다음 공격 강화", "exec": "방어가 깎인 적을 베어 넘기고 적 선봉 방어를 깎는다", "confuse": "적 상위 부대 혼란",
	"slow": "적 전원 둔화 · 고유기 게이지 감소", "ambush": "기 모으는 적을 끊고, 나머지 적 고유기 게이지 감소", "plague": "적 전원 역병 · 적 최강 장수 봉인",
	"cleanse": "아군 전원 상태이상 해제 · 사기", "duel": "적 최강 장수에게 일격 · 사기 감소"}
const INYEON_THEME_PLUS := {"confuse": "적 최강 장수 혼란", "slow": "적 전원 둔화", "phalanx": "아군 전원 방진"}
## 기인 · 초월의 몫 (11/12 사용자) —— 인연 시트 · 디테일창 규칙 줄
## 11/13 사용자: 한 덩어리 글 대신 짧은 항목 3줄 [라벨, 설명] —— 합동 발동 / 기인 / 초월 (InyeonUI.rule_hint 가 라벨에 등급색)
const INYEON_RULES := [["합동", "게이지 찬 같은 인연 장수가 함께 발동 · 3명 (초월 끼면 4명)"],
	["기인", "연쇄를 연다 · 맨 먼저 터지고 마무리 장수 피해 +"],
	["초월", "연쇄를 키운다 · 같은 인연 장수의 기가 빨리 찬다 · 4명 연쇄"]]
const INYEON_ROLE := "기인: 연쇄를 연다 · 맨 먼저 터지고 마무리 장수 피해 +\n초월: 연쇄를 키운다 · 같은 인연 장수의 기가 빨리 찬다 · 4명까지"


## 11/13 그 인연에 실제로 있는 기인 · 초월 인물 {kiin: [인물], up: [인물]} —— 기인 카드 / 초월(등급 6, 기인 아님) 카드가 있는 구성원 (RtBattle 과 같은 기준)
func inyeon_roles(nm: String) -> Dictionary:
	var o := {"kiin": [], "up": []}
	for p in inyeon_members(nm):
		var kc := false
		var up := false
		for k in C:
			if is_foe(k) or person(k) != p or not inyeon_card(k):
				continue
			if is_kiin(k):
				kc = true
			elif C[k].tier == 6:
				up = true
		if kc:
			o.kiin.append(p)
		if up:
			o.up.append(p)
	return o


## 11/13 주제 · 인연기를 [제목, 효과] 두 줄로 —— 이름이 겹치면(백의도강 『백의도강』) 한 번만. 없으면 빈 배열
func inyeon_theme_lines(nm: String) -> Array:
	var t := inyeon_theme(nm)
	if t.is_empty():
		return []
	var kind: String = INYEON_THEME_KIND.get(t.t, "")
	var d := inyeon_theme_desc(t)
	return ["주제 · %s" % t.n, d if kind == "" or kind == str(t.n) else "%s —— %s" % [kind, d]]


func inyeon_fin_lines(nm: String) -> Array:
	var f := inyeon_fin(nm)
	if f.is_empty():
		return []
	var kind: String = INYEON_FIN_KIND.get(f.t, "")
	var d: String = INYEON_FIN_DESC.get(f.t, "") + " (3명이면 더 강하게)"
	return ["인연기 · %s" % f.n, d if kind == "" or kind == str(f.n) else "%s —— %s" % [kind, d]]
func inyeon_theme(nm: String) -> Dictionary:
	return INYEON_THEME.get(nm, {})


func inyeon_theme_desc(def: Dictionary) -> String:
	var s: String = INYEON_THEME_DESC.get(str(def.get("t", "")), "")
	var p := str(def.get("plus", ""))
	if p != "" and INYEON_THEME_PLUS.has(p):
		s += " + " + INYEON_THEME_PLUS[p]
	return s


## 인연 주제 한 줄 (디테일창 · 편성 시트) —— 없으면 ""
func inyeon_theme_text(nm: String) -> String:
	var t := inyeon_theme(nm)
	if t.is_empty():
		return ""
	var l := inyeon_theme_lines(nm)
	return "%s: %s" % [l[0], l[1]]


## 이 카드가 고유기를 쓸 수 있나 (초월 이상 · 기인 —— 디테일창 · 전투와 같은 기준). 인연은 이런 카드만 친다
func inyeon_card(k) -> bool:
	return k != null and C.has(k) and (C[k].tier >= 6 or C[k].kind == "kiin") and ULT.list.has(person(k))


## 그 인물이 속한 인연 이름들 (json 순서) —— 인물 이름으로
func inyeon_of_person(p: String) -> Array:
	return _inyeon_of_person.get(p, [])


## 카드 k 의 인물이 속한 인연 이름들 (json 순서). 고유기를 쓸 수 없는 카드 · 인연이 없는 인물은 빈 배열
func inyeon_of(k) -> Array:
	return inyeon_of_person(person(k)) if inyeon_card(k) else []


## 인연의 구성원 (인물 이름, 4~5명)
func inyeon_members(nm: String) -> Array:
	return INYEON.get(nm, [])


## 덱(카드 id 배열, null 가능)에서 같이 발동하는 인연 —— [{n: 인연 이름, in: [덱에 있는 구성원 인물 이름 (구성원 순서)], out: [없는 구성원]}] 2명 이상 있는 것만, json 순서.
## 같은 인물은 한 번만 센다. 한 번에 합동하는 최대 인원은 INYEON_MAX
const INYEON_MAX := 3
## 인연 규칙 한 줄 설명 (11/11 사용자) —— 디테일창 인연 줄 · 편성 인연 시트가 같이 쓴다. 5명 인연도 3명씩 나뉘어 발동한다 (덱이 정형화되지 않게 일부러 제한)
const INYEON_RULE := "게이지 찬 같은 인연 장수가 함께 발동 · 3명 (초월 끼면 4명)"
func inyeon_links(deck: Array) -> Array:
	var ps := {}
	for k in deck:
		if inyeon_card(k):
			ps[person(k)] = true
	var out := []
	for nm in INYEON:
		var inn := []
		var outn := []
		for p in INYEON[nm]:
			(inn if ps.has(p) else outn).append(p)
		if inn.size() >= 2:
			out.append({"n": nm, "in": inn, "out": outn})
	return out


## 고유기를 쓸 수 있는 카드 중 인물 p 의 카드를 하나 —— 초상 · 디테일창으로 넘길 때. high 면 등급 높은 것, 아니면 낮은 것(초월 · 기인 쪽)
func inyeon_card_of_person(p: String, high := true) -> String:
	var best := ""
	for k in C:
		if is_foe(k) or not inyeon_card(k) or person(k) != p:
			continue
		if best == "" or (C[k].tier > C[best].tier if high else C[k].tier < C[best].tier):
			best = k
	return best


## 고유기 —— 신화 기준 수치를 불멸 카드에는 tier7_scale, 초월 카드에는 tier6_scale 배로 줄여 준다
func ult_of(k: String):
	var base = ULT.list.get(person(k))
	if base == null:
		return null
	var u: Dictionary = base.duplicate(true)
	u.first = u.get("first", ULT.first.get(str(C[k].tier), ULT.first["6"]))      # 기인(전설 등급)은 초월 값
	u.cd = u.get("cd", ULT.cd)
	u.wind = float(u.get("wind", ULT.get("wind", 2.5)))      # 11/22 기 모으기 초 —— 장수별 (data/ultimates.json "wind", 없으면 공통값 2.5)
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


## 11/20 고유기 효과를 구조로 —— 디테일창 고유기 카드: 큰 숫자 하나(hero {v, l}) + 꼬리표(chips [{l, v, k}], k: "tgt" 범위 · "st" 상태 · "cap" 상한 · "" 수치).
## 수치 계산은 UI.ult_desc 와 같다 (타격 = 배율 × 그 등급 turn_mul, 회복 · 사기 = × Battle.burst). 큰 숫자는 첫 효과의 대표 값 (타격 > 회복 > 버프 > 사기)
func ult_parts(u: Dictionary, tier := 0) -> Dictionary:
	var tm := Battle.turn_mul_for(tier) if tier > 0 else 1.0
	var cap := float(Battle.ult_cap.get(clampi(tier, 6, 8), 0.0)) if tier > 0 else 0.0
	var rows := []      # 효과마다 {t, tgt, items: [[글, 값, 종류]]}
	for comp in u.eff:
		var t := str(comp.get("t", ""))
		var items := []
		match t:
			"hit":
				items.append(["피해", "%d%%" % roundi(float(comp.mult) * tm * 100), ""])
				if comp.has("exec"):
					items.append(["병력 %d%% 이하 즉사" % roundi(float(comp.exec) * 100), "", "st"])
				if comp.has("morale"):
					items.append(["사기", "−%d" % roundi(float(comp.morale) * Battle.burst()), ""])
				if comp.has("status"):
					items.append([str(D.STATUS.get(comp.status.k, {}).get("n", comp.status.k)), "", "st"])
			"ally":
				if comp.has("heal"):
					items.append(["병력 회복", "+%s%%" % str(snappedf(float(comp.heal) * Battle.burst() * 100, 0.1)).trim_suffix(".0"), ""])
				if comp.has("buff"):
					items.append([str(D.STATNM.get(comp.buff.stat, comp.buff.stat)), ("%+d%%" % roundi(float(comp.buff.amt) * 100)).replace("-", "−"), ""])
				if comp.has("morale"):
					items.append(["사기", "+%d" % roundi(float(comp.morale) * Battle.burst()), ""])
				if comp.has("cleanse"):
					items.append(["상태 해제", "", "st"])
			"foe":
				if comp.has("buff"):
					items.append([str(D.STATNM.get(comp.buff.stat, comp.buff.stat)), ("%+d%%" % roundi(float(comp.buff.amt) * 100)).replace("-", "−"), ""])
				if comp.has("morale"):
					items.append(["사기", "−%d" % roundi(float(comp.morale) * Battle.burst()), ""])
				if comp.has("status"):
					items.append([str(D.STATUS.get(comp.status.k, {}).get("n", comp.status.k)), "", "st"])
		if not items.is_empty():
			rows.append({"t": t, "tgt": str(comp.get("tgt", "")), "items": items})
	var out := {"hero": {}, "chips": []}
	if rows.is_empty():
		return out
	var hi := 0      # 큰 숫자를 낼 효과 —— 값이 있는 첫 효과
	for i in rows.size():
		if rows[i].items.any(func(e): return str(e[1]) != ""):
			hi = i
			break
	var h0: Dictionary = rows[hi]
	var ally0: bool = h0.t == "ally"
	var side0 := ("자신" if h0.tgt == "self" else "아군") if ally0 else "적"
	for i in rows.size():
		var r: Dictionary = rows[i]
		var same: bool = r.tgt == h0.tgt and (r.t == "ally") == ally0
		var who := ""
		if i == hi:
			out.chips.append({"l": _ult_tgt(r.t, r.tgt), "v": "", "k": "tgt"})
		elif same:
			who = side0
		else:
			who = _ult_tgt(r.t, r.tgt)
		for e in r.items:
			if i == hi and out.hero.is_empty() and str(e[1]) != "":
				out.hero = {"v": e[1], "l": e[0] if r.t == "hit" else side0 + " " + str(e[0])}
				continue
			var lb: String = (who + " " + str(e[0])) if who != "" else str(e[0])
			if not out.hero.is_empty() and str(e[1]) != "" and str(e[2]) == "" and str(out.hero.v) == str(e[1]) and same and r.t != "hit" and h0.t != "hit":
				if not str(out.hero.l).contains(str(e[0])):      # 같은 대상 · 같은 값의 버프는 큰 숫자 글에 합친다 ("아군 공격 · 책략")
					out.hero.l = str(out.hero.l) + " · " + str(e[0])
				continue
			var dup := false
			for c in out.chips:
				if str(c.l) == lb and str(c.v) == str(e[1]):
					dup = true
				elif str(c.k) == "" and str(e[2]) == "" and str(e[1]) != "" and str(c.v) == str(e[1]) and str(c.get("w", "")) == who and who != "" and not str(e[0]) in ["피해", "사기"] and not str(c.l).ends_with("피해") and not str(c.l).ends_with("사기"):
					c.l = str(c.l) + " · " + str(e[0])      # "적 공격 −20%" + "적 방어 −20%" → "적 공격 · 방어 −20%"
					dup = true
				if dup:
					break
			if not dup:
				out.chips.append({"l": lb, "v": e[1], "k": e[2], "w": who})
	if cap > 0.0 and rows.any(func(r): return r.t == "hit"):      # 한 방 상한 —— 맨 끝에 옅게 (한 부대가 이 고유기에 잃는 병력은 최대 병력의 이만큼까지)
		out.chips.append({"l": "한 부대 피해 상한", "v": "병력의 %d%%" % roundi(cap * 100), "k": "cap"})
	return out


## 고유기 꼬리표의 대상 글 —— '적 전체' 는 전장 전체가 아니라 노리는 적 둘레 (UI.ult_desc 와 같은 규칙)
func _ult_tgt(t: String, tgt: String) -> String:
	if tgt == "all" and t != "ally":
		return "적 둘레 전체"
	return tgt_name(tgt)


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


## 장수창 고유기 꼬리표 —— "8초부터", 기 모으기가 공통값(2.5초)과 다르면 " · 기 1.5초" 를 붙인다 (11/22)
func ult_when(u: Dictionary) -> String:
	var s := "%d초부터" % roundi(float(u.get("wait", 14.0)))
	var w := float(u.get("wind", 2.5))
	if absf(w - float(ULT.get("wind", 2.5))) > 0.01:
		s += " · 기 %s초" % str(snappedf(w, 0.1))
	return s


func ult_wait(k: String, u: Dictionary) -> float:
	if u.has("wait"):      # 11/22 장수별 대기 —— data/ultimates.json 의 그 장수 "wait" (기습형은 일찍)
		return float(u.wait)
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


## 11/9 사용자: 기인 · 초월은 여전히 너무 낮은 병력 —— 같은 병종 불멸 평균의 이만큼으로 몸(병력 · 공격 · 방어)과 PV 를 맞춘다.
## 불멸과 같은 급은 아니다 (11/8 동급화 0.9 · 0.95 는 거절): 초월 병력 0.75 · 능력치 0.88, 기인 병력 0.7 · 능력치 0.85.
## 카드 사이 차이는 비율로 남긴다. 위세 · 기인 기능 · 고유기 · 기술 · 등급 번호(초월 6 · 기인 5)는 그대로.
## PV 는 몸에 맞게 √(병력 배율 × 능력치 배율) —— 초월 약 0.81 · 기인 약 0.77 (불멸 PV 평균 대비). 병력 배율 0 이면 끈다 (예전 몸)
const BRANCH_TR := 0.75     # 초월 병력
const BRANCH_ST := 0.88     # 초월 공격 · 방어
const BRANCH_KIIN_TR := 0.7
const BRANCH_KIIN_ST := 0.85
var _branch_src := {}       # 바꾸기 전 원래 값 (다시 부를 때 그것에서 계산)

func set_branch(tr_mul: float, st_mul: float, ktr := BRANCH_KIIN_TR, kst := BRANCH_KIIN_ST) -> void:
	var grp := func(k: String) -> String:
		if is_foe(k): return ""
		if is_kiin(k): return "kiin"
		return "6" if C[k].tier == 6 else ("7" if C[k].tier == 7 else "")
	if _branch_src.is_empty():
		for k in C:
			if grp.call(k) in ["6", "kiin"]:
				_branch_src[k] = {"tr": C[k].tr, "pv": C[k].pv, "atk": C[k].atk, "def": C[k]["def"],
					"b_atk": _BASE[k].atk, "b_int": _BASE[k]["int"], "b_def": _BASE[k]["def"], "b_res": _BASE[k].res}
	# 병종마다 평균 (불멸 · 초월 · 기인) —— [병력, PV, 공격, 방어, 수]
	var avg := {}
	for k in C:
		var g: String = grp.call(k)
		if g == "":
			continue
		var src: Dictionary = _branch_src.get(k, {"tr": C[k].tr, "pv": C[k].pv, "atk": C[k].atk, "def": C[k]["def"]})
		var key: String = g + ":" + str(C[k].tag)
		var a: Array = avg.get(key, [0.0, 0.0, 0.0, 0.0, 0])
		a[0] += float(src.tr); a[1] += float(src.pv); a[2] += float(src.atk); a[3] += float(src["def"]); a[4] += 1
		avg[key] = a
	for k in _branch_src:
		var s: Dictionary = _branch_src[k]
		var c: Dictionary = C[k]
		var mine: Array = avg[grp.call(k) + ":" + str(c.tag)]
		var im: Array = avg.get("7:" + str(c.tag), [])
		if tr_mul <= 0.0 or im.is_empty():
			c.tr = s.tr; c.pv = s.pv; c.atk = s.atk; c["int"] = s.atk; c["def"] = s["def"]; c.res = s["def"]
			_BASE[k].atk = s.b_atk; _BASE[k]["int"] = s.b_int; _BASE[k]["def"] = s.b_def; _BASE[k].res = s.b_res
			continue
		var n: float = mine[4]
		var kn := is_kiin(k)
		var tm: float = ktr if kn else tr_mul
		var sm: float = kst if kn else st_mul
		var fo: float = sm * (im[2] / im[4]) / (mine[2] / n)
		var fd: float = sm * (im[3] / im[4]) / (mine[3] / n)
		c.tr = int(roundf(float(s.tr) * tm * (im[0] / im[4]) / (mine[0] / n) / 100.0) * 100)
		c.pv = maxi(1, roundi(float(s.pv) * sqrt(tm * sm) * (im[1] / im[4]) / (mine[1] / n)))
		c.atk = roundf(s.atk * fo); c["int"] = c.atk
		c["def"] = roundf(s["def"] * fd); c.res = c["def"]
		_BASE[k].atk = s.b_atk * fo; _BASE[k]["int"] = s.b_int * fo; _BASE[k]["def"] = s.b_def * fd; _BASE[k].res = s.b_res * fd
	# 등급 PV 범위 (봇 덱 짜기) —— 기인은 따로라 전설 범위에 넣지 않는다
	for t in [5, 6]:
		var pvs := []
		for k in C:
			if C[k].tier == t and not is_foe(k) and not is_kiin(k):
				pvs.append(C[k].pv)
		if not pvs.is_empty() and TIER.has(t):
			TIER[t].lo = pvs.min()
			TIER[t].hi = pvs.max()


## 11/10 카드별 힘 배율 (전투 밸런스) —— data/cards_ext.json card_adjust {id: 배율 | {"st": 능력치, "tr": 병력, "psv": 특기 세기}}.
## 숫자 하나 = 능력치 · 병력 · 특기 세기(개인 · 단체 수치)를 모두 그 배율로. 측정(tests/card_value): 능력치만 ±8% 는 승률 기여 ±1%p, 셋을 함께 ±8% 는 약 ±5%p.
## 몸 정규화(set_branch) 뒤에 곱하므로 초월 · 기인도 그대로 먹는다. PV(비용)는 그대로.
func _adj_of(k: String, key: String) -> float:
	var raw = CARD_ADJ.get(k)
	if raw == null:
		return 1.0
	if raw is Dictionary:
		return float(raw.get(key, 1.0))
	return float(raw)


## 카드의 특기 세기 배율 (passives_of 가 곱한다)
func card_psv(k: String) -> float:
	return _adj_of(k, "psv")


## 이미 곱한 배율은 나눠 내고 새로 곱하므로 몇 번 불러도 같다 (점검 도구가 CARD_ADJ 를 바꿔 다시 부를 수 있다)
func apply_card_adjust() -> void:
	_psv_cache.clear()      # 특기 세기 배율(psv)이 바뀌었을 수 있다
	for k in C:
		var want := _adj_of(k, "st")
		var want_tr := _adj_of(k, "tr")
		var have := float(_card_adj_on.get(k, 1.0))
		var have_tr := float(_card_adj_tr.get(k, 1.0))
		if not is_equal_approx(want, have):
			var f := want / have
			for s in ["atk", "def", "int", "res"]:
				C[k][s] = C[k][s] * f
				if _BASE.has(k):
					_BASE[k][s] = _BASE[k][s] * f
			_card_adj_on[k] = want
		if not is_equal_approx(want_tr, have_tr):
			C[k].tr = int(roundf(float(C[k].tr) * want_tr / have_tr / 100.0) * 100)      # 병력은 100 단위
			_card_adj_tr[k] = want_tr


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

## 봇 덱의 9칸 등급 —— 가장 낮은 칸부터 한 단계씩 올리며 PV 를 쓴다 (gen_board 와 군세 유지(army_fit)가 같이 쓴다. 난수 없음)
## 11/22 사용자: 후반 봇이 모두 초월 9장이었다 —— 가장 낮은 칸부터 올리는 평평한 배분은 9칸이 늘 한 등급(차이 ≤ 1)이고,
## 초월(15종)과 불멸 값 차이가 커서 PV 700~1000 사이가 통째로 「초월만」이었다. 이제는 계단 —— 높은 칸부터 줄 세워 칸 r 의 등급 칸수(PLAY_TIERS 위치)가
## 「바닥 + BOT_SHAPE[r]」 모양이 되게 한 칸씩 올린다 (에이스 2장 +2 · 중견 3장 +1 · 바닥 4장). 앞섬은 「바닥 − 1」 칸까지만이라 초반(바닥 희귀 아래)은 예전처럼 평평하다.
## 같은 키면 바닥 쪽을 먼저 올린다 (에이스가 모양보다 한 칸 더 앞서지 않게). 걸음 순서는 PV 와 상관없이 하나로 정해져 있고 PV 는 어디서 멈추는지만 정한다 ——
## 그래서 PV 가 오르면 늘 한 칸 한 단계씩만 바뀐다 (군세 유지 army_fit 이 한 장씩 바꾸는 약속 그대로).
## 값(같은 PV 맞대결로 맞춤, tests/bot_deck_mix): 불멸 · 신화는 카드 PV 에 비해 세다 —— 봇 예산에서는 불멸 한 장에 bot_imm_extra, 신화에 bot_myth_extra 를 더 쓴다.
## 신화는 맨 앞 한 칸만 —— 불멸 중견까지 차고 바닥이 초월로 오르는 무렵(키 35)에 한 걸음으로. 일찍 들이면 그 값을 모으는 동안 군세가 멈춰(같은 PV 에서 약해져) 늦게 둔다
const BOT_SHAPE := [2, 2, 1, 1, 1, 0, 0, 0, 0]
const BOT_MYTH_KEY := 35
var bot_imm_extra := 30
var bot_myth_extra := 120
func board_tiers(pv: float) -> Array:
	if not bot_shape:
		return board_tiers_flat(pv)
	var mid := func(t): return roundi((TIER[t].lo + TIER[t].hi) / 2.0) + (bot_imm_extra if t == 7 else 0) + (bot_myth_extra if t == 8 else 0)
	var top := PLAY_TIERS.size() - 1
	var idx := []
	idx.resize(9)
	idx.fill(0)
	var spent: int = mid.call(PLAY_TIERS[0]) * 9
	for g in 600:
		var base: int = idx.min()
		var myth_ok: bool = int(idx[0]) == top - 1 and int(idx[1]) >= top - 1
		var best := -1
		var bk := 1 << 30
		for r in 9:
			var key: int
			if r == 0 and myth_ok:
				key = BOT_MYTH_KEY
			else:
				if int(idx[r]) >= top - 1:
					continue
				var b: int = mini(int(BOT_SHAPE[r]), maxi(0, base - 1))
				key = (int(idx[r]) - b) * 10 + b
			if key < bk:
				bk = key
				best = r
		if best < 0:
			break
		var cost: int = mid.call(PLAY_TIERS[idx[best] + 1]) - mid.call(PLAY_TIERS[idx[best]])
		if spent + cost > pv:
			break
		spent += cost
		idx[best] += 1
	return idx.map(func(i): return int(PLAY_TIERS[i]))


## 예전 평평한 배분 (bot_shape 끔 —— 비교용)
func board_tiers_flat(pv: float) -> Array:
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
	return tiers


func gen_board(pv: float, style: String, rng: RandomNumberGenerator) -> Dictionary:
	var tiers := board_tiers(pv)
	var cards := []
	var mix_tags := _mix_tags(style, rng) if bot_mix else []
	if bot_yeon:
		# 높은 등급 칸부터 고른다 —— 인연은 초월 이상끼리라, 먼저 뽑힌 에이스에 맞춰 나머지가 붙는다 (칸 순서 · 병종은 그대로)
		cards.resize(tiers.size())
		var order := range(tiers.size())
		order.sort_custom(func(a, b): return tiers[a] > tiers[b] if tiers[a] != tiers[b] else a < b)
		for i in order:
			var tag := str(mix_tags[i]) if bot_mix else ""
			cards[i] = _army_pick(int(tiers[i]), tag, cards, rng.randi(), style)
		return {"cards": cards, "form": STYLE_FORM[style]}
	for i in tiers.size():
		var t: int = tiers[i]
		var tag := str(mix_tags[i]) if bot_mix else ""
		var k := _army_pick(t, tag, cards, rng.randi(), style)
		cards.append(k)
	return {"cards": cards, "form": STYLE_FORM[style]}


## 11/12 봇 군세 한 칸 뽑기 (작업현황 94) —— 이미 뽑힌 others 와 겹치지 않게: 카드 id 는 늘, 같은 인물(person)은 전설 이하 낮은 등급(3 미만 기본패)을 빼고 한 부대만.
## 후보 순서: 그 등급 · 그 병종(없으면 같은 피해 종류 · 아무나, _mix_src) → 그 등급 전체 → 한 등급 낮은 곳 … 안 겹치는 것이 하나라도 있는 첫 곳에서 고른다.
## 맨 아래 등급(기본패 8종)은 9칸을 채우면 모자라 겹칠 수 있다 —— 마지막 수단으로만 겹침을 허용. seed 만으로 같은 결과(난수 상태 없음)
## bot_mix 를 끈 옛 방식(style 풀)은 style 로 고른다
func _army_pick(t: int, tag: String, others: Array, seed_: int, style := "균형", keep := "") -> String:
	var rg := RandomNumberGenerator.new()
	rg.seed = seed_
	var used_id := {}
	var used_p := {}
	for k in others:
		if k == null:
			continue
		used_id[str(k)] = true
		if int(C[k].tier) >= 3:
			used_p[person(k)] = true
	var lim := 9 if (bot_shape and t >= 8) else 8      # 11/22 신화는 계단 배분의 맨 앞 칸(t = 8)만
	var free := func(k): return C[k].tier < lim and not used_id.has(k) and (int(C[k].tier) < 3 or not used_p.has(person(k)))
	# 11/22 인연 —— 초월 이상 칸은 병종 칸보다 인연을 먼저: 같은 피해 종류(물리 · 책략)에서 병종 3장 한도를 지키며, 이미 뽑힌 장수와 인연이 가장 많이 겹치는 인물
	# (군세가 자랄 때는 그 칸의 원래 인물(keep)의 윗 등급을 가장 먼저). 맞는 사람이 없으면 아래 예전 고르기
	if bot_yeon and t >= 6:
		var y := _yeon_pick(t, tag, others, keep, lim, free)
		if not y.is_empty():
			return y[rg.randi() % y.size()]
	var chains := []
	if bot_mix:
		chains.append(_mix_src(t, tag, lim))
	else:
		var src: Array = POOLS[style].get(t, [])
		chains.append(src if not src.is_empty() else POOLS["균형"].get(t, []))
	chains.append(POOLS["균형"].get(t, []).filter(func(k): return C[k].tier < lim))
	var lt := t
	while lt > 1:
		lt = _prev_tier(lt)
		chains.append(POOLS["균형"].get(lt, []).filter(func(k): return C[k].tier < 8))
	for src in chains:
		var ok: Array = src.filter(free)
		if not ok.is_empty():
			return ok[rg.randi() % ok.size()]
	var last: Array = chains[0] if not chains[0].is_empty() else chains[1]
	return last[rg.randi() % last.size()]


## 11/22 인연 맞춰 고르기 —— 그 등급에서 쓸 수 있는(free) 고유기 카드 가운데 점수가 가장 높은 후보들. 점수 = 이미 뽑힌 고유기 장수 중
## 이 인물과 인연을 함께하는 사람 수 (+3: 그 칸의 원래 인물 keep). 후보는 병종 칸(tag)과 같은 피해 종류(물리 · 책략)이고 그 병종이 others 에 3장 미만인 것 ——
## 봇 덱 병종 규칙(_mix_tags: 같은 병종 3장까지 · 물리/책략 비율)은 그대로. 0점뿐이면 빈 배열(예전 고르기)
func _yeon_pick(t: int, tag: String, others: Array, keep: String, lim: int, free: Callable) -> Array:
	var mates := {}
	var tag_n := {}
	for k in others:
		if k == null:
			continue
		tag_n[C[k].tag] = int(tag_n.get(C[k].tag, 0)) + 1
		if inyeon_card(k):
			mates[person(k)] = true
	var kind: Array = INT_TAGS if INT_TAGS.has(tag) else PHYS_TAGS
	var best := []
	var bs := 0
	for k in POOLS["균형"].get(t, []):
		if not free.call(k) or C[k].tier >= lim or not inyeon_card(k):
			continue
		if bot_mix and tag != "" and C[k].tag != tag and (not kind.has(C[k].tag) or int(tag_n.get(C[k].tag, 0)) >= 3):
			continue
		var p := person(k)
		var s := 3 if p == keep else 0
		for m in mates:
			if m != p and inyeon_of_person(p).any(func(n): return INYEON[n].has(m)):
				s += 1
		if s > bs:
			bs = s
			best = [k]
		elif s == bs and s > 0:
			best.append(k)
	return best


## 덱(카드 id 배열)에서 실제로 맺어지는 인연 —— 고유기 카드 인물이 2명 이상 든 인연 이름 {이름: 인원}. 점검 · 표시용
func deck_yeon(cards: Array) -> Dictionary:
	var ps := {}
	for k in cards:
		if k != null and inyeon_card(k):
			ps[person(k)] = true
	var out := {}
	for nm in INYEON:
		var n := 0
		for p in INYEON[nm]:
			if ps.has(p):
				n += 1
		if n >= 2:
			out[nm] = n
	return out


## 한 등급 아래 플레이 등급 (기본 = 1)
func _prev_tier(t: int) -> int:
	var prev := 1
	for x in PLAY_TIERS:
		if x >= t:
			break
		prev = x
	return prev


## 정수 섞기(64비트 곱 · 시프트) —— 씨앗을 이어 붙인다. hash() 는 버전마다 달라질 수 있어 쓰지 않는다 (봇 군세는 서버 · 점검이 같은 결과여야 한다)
static func mix_seed(a: int, b: int, c := 0) -> int:
	var x: int = (a ^ 0x5bd1e995) * 0x100000001b3 + b
	x = (x ^ (x >> 29)) * 0x27d4eb2f165667c5 + c
	x = x ^ (x >> 32)
	return x & 0x7fffffff


## 11/12 사용자(작업현황 94): 봇 군세는 전투마다 새로 뽑지 않는다 —— 봇마다 9장짜리 군세를 한 번 만들고(army 가 비었을 때 gen_board), PV 가 오르면 필요한 칸만
## 한 단계 위 카드로 바꾼다(army_fit). 칸의 병종은 그대로. 새 등급 배분(board_tiers)과 맞게 현재 등급을 높은 순으로 줄 세워 비교하므로 보통은 PV 가 한 칸치 오를 때 한 장만 바뀐다.
## PV 가 내려가도(토벌 실패 ×0.94) 같은 식으로 맞춘다. 반환은 새 9장(army 는 건드리지 않는다) —— 부르는 쪽이 저장한다. aseed 한 값으로 모든 선택이 정해진다 (난수 상태 없음)
func army_fit(army: Array, pv: float, style: String, aseed: int) -> Array:
	if army.size() != 9:
		var rg := RandomNumberGenerator.new()
		rg.seed = aseed
		return gen_board(pv, style, rg).cards
	var want := board_tiers(pv)
	want.sort()
	want.reverse()
	var order := []
	for i in 9:
		order.append(i)
	order.sort_custom(func(a, b):
		var ta: int = C[army[a]].tier
		var tb: int = C[army[b]].tier
		return ta > tb if ta != tb else a < b)
	var todo := []
	for j in 9:
		var i: int = order[j]
		if int(C[army[i]].tier) != int(want[j]):
			todo.append([i, int(want[j])])
	var out := army.duplicate()
	todo.sort_custom(func(a, b): return a[1] > b[1] if a[1] != b[1] else a[0] < b[0])      # 높은 등급부터 고른다
	for e in todo:
		var i: int = e[0]
		var others := out.duplicate()
		others[i] = null
		out[i] = _army_pick(int(e[1]), str(C[out[i]].tag), others, mix_seed(aseed, i, int(e[1])), style, person(out[i]))
	# 겹침 고치기 —— 처음 만들 때 기본패 8종이 9칸에 모자라 겹쳤던 칸 · 옛 저장의 겹침이, 같은 등급의 안 겹치는 카드가 생기면 바뀐다 (없으면 그대로)
	for i in range(1, 9):
		var k: String = out[i]
		for j in i:
			var o: String = out[j]
			if o == k or (int(C[k].tier) >= 3 and person(o) == person(k)):
				var others2 := out.duplicate()
				others2[i] = null
				out[i] = _army_pick(int(C[k].tier), str(C[k].tag), others2, mix_seed(aseed, i, 100 + int(C[k].tier)), style)
				break
	return out


## 11/8 봇 덱 병종 (docs/역할_재설계_1108.md 7.2) —— 몰빵이면 몰빵 카운터가 정답이 되어 '고루'의 가치가 흐려진다.
## 같은 병종 3장까지 · 물리 · 책략 각 3장 이상, 성향은 몰빵 대신 쏠림 (물리 6:3 · 지략 3:6 · 균형 5:4). 칸마다 섞어 높은 등급이 한 병종에 몰리지 않게
const BOT_MIX_PHYS := {"물리": 6, "지략": 3, "균형": 5}
func _mix_tags(style: String, rng: RandomNumberGenerator) -> Array:
	var n_phys: int = BOT_MIX_PHYS.get(style, 5)
	var out := []
	for grp in [[PHYS_TAGS, n_phys], [INT_TAGS, 9 - n_phys]]:
		var cnt := {}
		for i in int(grp[1]):
			var cand: Array = grp[0].filter(func(x): return int(cnt.get(x, 0)) < 3)
			var tg: String = cand[rng.randi() % cand.size()]
			cnt[tg] = int(cnt.get(tg, 0)) + 1
			out.append(tg)
	for i in range(out.size() - 1, 0, -1):
		var j := rng.randi() % (i + 1)
		var x = out[i]
		out[i] = out[j]
		out[j] = x
	return out


## 그 등급의 그 병종 (없으면 같은 피해 종류, 그래도 없으면 아무나) —— 신화는 뺀다
func _mix_src(t: int, tag: String, lim := 8) -> Array:
	var all_: Array = POOLS["균형"].get(t, []).filter(func(k): return C[k].tier < lim)
	var same := all_.filter(func(k): return C[k].tag == tag)
	if not same.is_empty():
		return same
	var kind: Array = INT_TAGS if INT_TAGS.has(tag) else PHYS_TAGS
	var near := all_.filter(func(k): return kind.has(C[k].tag))
	if not near.is_empty():
		return near
	return all_ if not all_.is_empty() else POOLS["균형"].get(t, [])


func auto_place(cards: Array, form: String) -> Array:
	var f: Dictionary = FORM[form]
	var fw: Dictionary = D.FRONT_WANT
	var order := cards.filter(func(k): return k != null)
	order.sort_custom(func(a, b):
		if C[a].tier != C[b].tier:
			return C[a].tier > C[b].tier
		return fw[C[a].tag] > fw[C[b].tag])
	var out := []
	out.resize(maxi(9, f.slots.size()))
	var used := []
	used.resize(out.size())
	used.fill(false)
	# 11/11 사용자: 선봉에 술사가 서는 경우가 있다(창병이 있는데도) —— 등급 높은 순으로 자리를 고르면 높은 등급 술사가 먼저 뒷자리를 채우고
	# 남은 선봉에 들어갔다. 선봉 자리는 등급과 상관없이 먼저, 그 자리에 가장 맞는 카드(기병 · 창병 …)로 채운다
	var rest: Array = order.duplicate()
	for i in f.slots.size():
		var s0: Dictionary = f.slots[i]
		if s0.line != "선봉" or rest.is_empty():
			continue
		var bk = null
		var bv := -1e9
		for k in rest:
			var z0 := aff_of(C[k].tag, s0.line, s0.side)
			var v0: float = (6.0 if z0 == "pref" else -4.0 if z0 == "bad" else 0.0) - absf(D.LINE[s0.line].pri - (4 - fw[C[k].tag])) * 0.6 + float(C[k].tier) * 0.01
			if v0 > bv and v0 >= -2.0:      # 술사 · 모사(−2.4)는 이 자리의 몫이 아니다 (책사 · 유생 · 도적 −1.8 은 앞줄 카드가 모자랄 때만) —— 그래도 남으면 아래 일반 배치가 정한다
				bv = v0
				bk = k
		if bk != null:
			used[i] = true
			out[i] = bk
			rest.erase(bk)
	for k in rest:
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
	"line:후군": "가장 뒤쪽 적 (최대 3부대)", "line:선봉+전군": "가장 앞쪽 적 (최대 3부대)",
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
		"phys": p.append("%s에 물리 %s" % [_foe_tgt(e.tgt), pct.call(e.mult)])
		"int": p.append("%s에 책략 %s" % [_foe_tgt(e.tgt), pct.call(e.mult)])
	var pc := Battle.pace_for(c.tier)
	# 11/19 능력치 변화에 부호와 지속 시간 —— '자신 방어 35%' 는 오르는지 깎이는지, 얼마 동안인지 알 수 없었다 (지속은 정산 간격 단위 → sec_text)
	var buf := func(who: String, stat: String, b: Dictionary) -> String:
		var dur := (" (%s)" % sec_text(float(b.dur), c.tier)) if float(b.get("dur", 0)) > 0.0 else ""
		return "%s %s%s %+d%%" % [who, D.STATNM.get(stat, stat), dur, roundi(float(b.amt) * 100)]
	if e.has("morale"): p.append("사기 −%.1f" % (e.morale * pc))
	if e.has("pierce"): p.append("방어 %s 무시" % pct.call(e.pierce))
	if e.has("exec"): p.append("병력 %s 이하면 즉시 이탈" % pct.call(e.exec))
	if e.has("stance"): p.append("자신 반격 확률 (%s) +%s" % [sec_text(e.stance.dur, c.tier), pct.call(e.stance.amt)])
	if e.has("status"): p.append("『%s』 %s" % [D.STATUS[e.status.k].n, sec_text(e.status.dur, c.tier)])
	if e.has("tHeal"): p.append("아군 병력 %.1f%% 회복" % (e.tHeal * pc * 100))
	if e.has("heal"): p.append("아군 전원 사기 +%d" % roundi(e.heal * (1.0 if e.get("rally", false) else pc)))
	if e.has("cleanse"): p.append("아군 상태이상 %d종 해제" % e.cleanse)
	if e.has("spd"): p.append(buf.call("대상", "spd", e.spd))
	if e.has("foeSpd"): p.append(buf.call("대상", "spd", e.foeSpd))
	if e.has("defDown"): p.append("대상 방어 %s" % pct.call(e.defDown.amt))
	if e.has("selfBuff"): p.append(buf.call("자신", str(e.selfBuff.stat), e.selfBuff))
	if e.has("allyBuff"): p.append(buf.call(tgt_name(e.allyBuff.tgt), str(e.allyBuff.stat), e.allyBuff))
	return " · ".join(p)


## 대상 이름 앞의 '적' —— 이름에 이미 '적'이 들어 있으면 붙이지 않는다 (11/19 '적 맞붙은 적 1부대' · '적 적 후군' 으로 겹쳐 적혔다)
func _foe_tgt(t: String) -> String:
	var tn := tgt_name(t)
	return tn if tn.find("적") >= 0 else "적 " + tn


## 11/19 일반 기술이 다시 준비되는 시간(초) —— 행동할 때마다 준비가 D.RATE[등급] 만큼 차고(Battle.sk_rate) 비용(sk.cost)만큼 모이면 쓴다
## → 비용 / RATE 번 행동 × 행동 간격(act_sec). 아이템 · 특기(기술 준비 속도)는 넣지 않은 기본값. RATE 가 없는 등급(3급 이하)은 0
func sk_every_sec(sk: Dictionary, c: Dictionary) -> float:
	var r := float(D.RATE.get(str(int(c.get("tier", 0))), 0.0))
	if r <= 0.0:
		return 0.0
	return float(sk.get("cost", 1.0)) / r * act_sec(float(c.tier), float(c.get("spd", 0.0)))


## 기술을 둘 이상 가진 장수 —— 준비는 하나를 나눠 쓴다 (Battle.act: sk_ch[0]). 기술 칸 아래 한 줄
const SK_SHARE_NOTE := "기술은 한 번에 하나만 쓴다 —— 하나를 쓰면 나머지도 그만큼 다시 기다린다"


## 일반 기술 발동 조건 글 —— "자신 병력 60% 이하 또는 …"
## 기술 발동 안내 —— "적 전열에 2부대 이상일 때 · 약 4.5초마다"
## 11/19 사용자: "충전 1.1 이런 것도 무슨 표현인지 모호하다" —— 충전 숫자는 비용(행동마다 RATE 씩 모아 이만큼 차면 쓴다)이었다. 그 장수가 실제로 몇 초마다 쓰는지로 적는다 (c 가 없으면 조건만)
func sk_when(sk: Dictionary, c := {}) -> String:
	var cond := str(sk.get("cond", "always"))
	var sec := sk_every_sec(sk, c) if not c.is_empty() else 0.0
	if sec <= 0.0:
		return cond_text(cond)
	var every := sec_str(sec) + "마다"
	if cond.split("|").has("always"):
		return every
	return "%s · %s" % [cond_text(cond), every]


## 11/19 '한 열 · 맨 앞 열 · 후열' 은 턴제 칸 기준 —— 실시간 판정(RtBattle._dense_max 뭉친 무리 · _front_of 가장 앞선 무리 · _is_back 내 편에서 먼 적)대로
func cond_text(cond: String) -> String:
	var out := []
	for one in cond.split("|"):
		var kv := one.split(":")
		var v: String = kv[1] if kv.size() > 1 else ""
		var pc := "%d%%" % roundi(float(v) * 100) if v.is_valid_float() else v
		match kv[0]:
			"always": out.append("준비되면 바로")
			"hurt": out.append("자신 병력 %s 이하" % pc)
			"ally_hurt": out.append("아군 병력 %s 이하가 있을 때" % pc)
			"foe_hurt": out.append("적 병력 %s 이하가 있을 때" % pc)
			"dense": out.append("적 %s부대 이상이 뭉쳐 있을 때" % v)
			"front_n": out.append("맨 앞에 선 적이 %s부대 이상일 때" % v)
			"foe_n": out.append("적이 %s부대 이상 남았을 때" % v)
			"back_n": out.append("싸움에서 떨어져 있는 적이 있을 때" if int(v) <= 1 else "싸움에서 떨어져 있는 적이 %s부대 이상일 때" % v)
			"line":      # 11/23 strict_cond 가 거리 조건으로 바꾼다 —— 예전 데이터를 그대로 보일 때만
				var lt := "맞붙은 적이 있을 때" if int(D.LINE.get(v, {}).get("pri", 1)) <= 2 else "싸움에서 떨어져 있는 적이 있을 때"
				if not out.has(lt): out.append(lt)
			"no_st": out.append("『%s』 아닌 적이 있을 때" % D.STATUS[v].n)
			"ally_st": out.append("상태이상 걸린 아군이 있을 때")
			"foe_morale": out.append("적 사기가 아군 이상일 때")
			"ally_morale": out.append("사기가 %s 아래인 아군이 있을 때" % v)
			_: out.append(one)
	return " 또는 ".join(out)


## 병종 상성 배율 —— 공격 병종 a 가 수비 병종 d 를 칠 때 (1 ± amt)
## 11/8 피해 종류 —— "phys" 물리 · "int" 책략 (class_guard.kind, 없으면 책략계 병종이면 책략)
func dmg_kind(tag: String) -> String:
	return str(GUARD.get("kind", {}).get(tag, "int" if INT_TAGS.has(tag) else "phys"))


## 11/19 카드 표지 —— 장수 역할 한 줄 (사용자: "해당 장수의 롤을 축약해서 적어 준다" —— 조인 '아군 보호' · 주유 '광역 화공' · 화타 '병력 회복').
## data/roles.json: person[인물] → key[그 인물 개성(passives.json sig)의 첫 키] → tag[병종] 순서로 정한다. 병졸 카드(1~2급) · 적 전용은 빈 사전.
## {t 글, col 갈래 색, icon 기호 이름(Icons · "plus"), cat 갈래}. 예전 기인 두 글자 칩(방깎 · 파계 …)을 대신한다
var ROLES := {}
var _role_cache := {}

func role_chip(k: String) -> Dictionary:
	if _role_cache.has(k):
		return _role_cache[k]
	var out := {}
	if ROLES.is_empty():
		var f := FileAccess.open("res://data/roles.json", FileAccess.READ)
		ROLES = JSON.parse_string(f.get_as_text()) if f != null else {"cat": {}}
	var c: Dictionary = C.get(k, {})
	if not c.is_empty() and int(c.tier) > 2 and ROLES.has("key"):
		var pn := person(k)
		var e = ROLES.person.get(pn)
		if e == null:
			var sg = PSV.get("sig", {}).get(pn)
			if sg is Array and sg.size() >= 3:
				for key in (sg[2] as Dictionary):
					if ROLES.key.has(key):
						e = ROLES.key[key]
						break
		if e != null and str(e[0]).begins_with("@"):      # @dmg · @tough —— 같은 일도 병종에 따라 부르는 말이 다르다 (근접 공격 · 원거리 공격 · 광역 책략 …)
			e = (ROLES.get(str(e[0]).substr(1), {}) as Dictionary).get(str(c.tag))
		if e == null:
			e = ROLES.tag.get(str(c.tag))
		if e != null and ROLES.cat.has(str(e[1])):
			var ct: Array = ROLES.cat[str(e[1])]
			out = {"t": str(e[0]), "col": Color(str(ct[0])), "icon": str(ct[1]), "cat": str(e[1])}
	_role_cache[k] = out
	return out


## 피해 종류 색 —— 물리 주황 · 책략 파랑 (카드 병종 기호 테두리 · 디테일창 글)
func kind_col(tag: String) -> Color:
	return Color("#6fa8ff") if dmg_kind(tag) == "int" else Color("#ff8a6a")


## 병종 기본 막 {phys: 갑옷, int: 결계}
func guard_of(tag: String) -> Dictionary:
	return {"phys": float(GUARD.get("armor", {}).get(tag, 0.0)), "int": float(GUARD.get("ward", {}).get(tag, 0.0))}


## 카드 한 줄 —— "물리 피해 · 갑옷 30%" / "책략 피해 · 결계 30%" / "물리 피해" (막을 끄면 빈 글)
func guard_text(tag: String) -> String:
	if GUARD.is_empty() or not Battle.shield_enabled:
		return ""
	var g := guard_of(tag)
	var s := "%s 피해" % ("책략" if dmg_kind(tag) == "int" else "물리")
	if g.phys > 0:
		s += " · 갑옷 %d%%" % roundi(g.phys * 100)
	if g["int"] > 0:
		s += " · 결계 %d%%" % roundi(g["int"] * 100)
	return s


## 11/8 토벌 일차별 우두머리 성질 (class_guard.quest[일차], 0 = 1일차) —— t 갑옷 · 결계, x 행동 성질(11/19), boss 총대장(11/19 늘 켬)
## 7일차가 넘으면(온라인은 끝까지 토벌) 막은 7일차 그대로, 행동 성질은 QUEST_X_LATE 를 돈다 —— 날마다 다른 퍼즐
const QUEST_X_LATE := ["rush", "stand", "regen", "rage"]
func quest_trait(day: int) -> Dictionary:
	var q: Array = GUARD.get("quest", [])
	var out := {"boss": true}
	if q.is_empty():
		return out
	var t: Dictionary = q[clampi(day, 0, q.size() - 1)]
	if str(t.get("t", "")) != "":
		out["t"] = t.t
		out["v"] = t.get("v", 0.0)
	var x := str(t.get("x", ""))
	if day >= q.size():
		x = QUEST_X_LATE[(day - q.size()) % QUEST_X_LATE.size()]
	if x != "":
		out["x"] = x
	return out


## 행동 성질 이름 · 한 줄 (Battle.QUEST_X 와 같은 값)
const QUEST_X_TEXT := {"regen": "재생 · 병력 회복", "rage": "광폭 · 궁지 공격 +40%", "rush": "질주 · 속도 +25%", "stand": "결사 · 패주 저항"}


## 토벌 성질 한 줄 —— "철갑 · 물리 −45%" / "부적 · 책략 −45%" / "철갑 앞 · 부적 뒤 60%", 행동 성질이 있으면 " / 재생 · 병력 회복"
func trait_text(t: Dictionary) -> String:
	var v := roundi(float(t.get("v", 0.0)) * 100)
	var s := ""
	match str(t.get("t", "")):
		"armor": s = "철갑 · 물리 −%d%%" % v
		"ward": s = "부적 · 책략 −%d%%" % v
		"mix": s = "철갑 앞 · 부적 뒤 %d%%" % v
	var x := str(QUEST_X_TEXT.get(str(t.get("x", "")), ""))
	if x != "":
		s = x if s == "" else s + " / " + x
	return s


func cls_mul(a: String, d: String, tier := 8) -> float:
	if CLASS_COUNTER.is_empty():
		return 1.0
	# 책략계가 끼는 상성은 등급마다 세기가 다르다 (책략은 낮은 등급에서 약하고 높은 등급에서 세다)
	var amt := float(CLASS_COUNTER.amt)
	if (INT_TAGS.has(a) or INT_TAGS.has(d)) and CLASS_COUNTER.has("int_amt"):
		amt = float(CLASS_COUNTER.int_amt.get(str(tier), amt))
	var pair: Dictionary = CLASS_COUNTER.get("pair_amt", {})      # 11/20 쌍마다 세기 ("공격>수비": amt) —— 없으면 amt
	if CLASS_COUNTER.win.get(a, []).has(d):
		return 1.0 + float(pair.get(a + ">" + d, amt))
	if CLASS_COUNTER.lose.get(a, []).has(d):
		return 1.0 - float(pair.get(a + ">" + d, amt))
	return 1.0


const AURA_TO := {"all": "아군", "front": "선봉 · 전군 아군", "back": "중군 · 후군 아군", "fac": "같은 세력 아군", "rel": "인연 장수",
	"low": "병력 절반 아래 아군"}
const AURA_FOE := {"all": "적", "front": "적 선봉 · 전군", "back": "적 중군 · 후군"}
## 특수 효과 이름 —— [이름, 백분율로 보이는가]
const AURA_M := {"crit": ["치명타 확률", true], "critd": ["치명타 피해", true], "dr": ["받는 피해", false],
	"idr": ["받는 피해", false], "counter": ["반격 확률", true], "regen": ["전투 동안 병력 회복", true],
	"mregen": ["전투 동안 사기 회복", false], "rate": ["기술 준비 속도", true], "rout": ["패주 저항", true], "stres": ["상태이상 저항", true],
	"low_atk": ["병력 절반 아래 공격", true], "kill_amp": ["적을 무너뜨린 뒤 피해", true], "weak_amp": ["약해진 적에게 피해", true],
	"ignite": ["점화 확률", true], "spread": ["불 번짐", true], "st_amp": ["지속 피해 세기", true], "opener": ["첫 공격 피해", true],
	"fire_res": ["화공 저항", true], "cleave": ["맞힌 적 주변에 피해", true], "icleave": ["맞힌 적 주변에 피해", true],
	"fear": ["적을 패주시킬 확률", true]}
const AURA_HIDE := ["turncoat"]      # 기인 설명(KIIN_TEXT)이 대신 적는 키


## 위세 설명 —— "의리지가: 인연 장수 공격 +12% · 방어 +12%" (이름 · 효과를 따로 쓰려면 aura_effect)
func aura_text(k: String) -> String:
	if not AURA.has(k):
		return ""
	return "%s: %s" % [AURA[k].n, aura_effect(k)]


func aura_effect(k: String) -> String:
	var al := aura_list(k)
	var parts := []
	for g in al.groups:
		parts.append(str(g.who) + " " + " · ".join(g.items.map(func(e): return "%s %s" % [e[0], e[1]])))
	if str(al.text) != "":
		parts.append(al.text)
	return " / ".join(parts)


## 11/20 위세 효과를 구조로 —— {groups: [{who: "아군", items: [[글, 값] …]}, {who: "적", …}], text: 기인 기능 설명("" 이면 없음)}.
## aura_effect 가 이것을 이어 붙인다 (디테일창 능력 카드의 수치 칩과 문장이 같은 계산)
func aura_list(k: String) -> Dictionary:
	var out := {"groups": [], "text": ""}
	if not AURA.has(k):
		return out
	var a: Dictionary = AURA[k]
	var who: String = AURA_TO.get(a.get("to", "all"), "아군")
	if a.get("to", "") == "tag" or (not a.has("to") and a.has("tag")):
		who = "아군 " + a.tag
	var mine := []
	for st in a.get("ally", {}):
		mine.append(_pct2(D.STATNM.get(st, st), a.ally[st]))
	for mk in a.get("m", {}):
		if mk in AURA_HIDE:
			continue
		var d: Array = AURA_M.get(mk, [mk, true])
		var v: float = a.m[mk]
		# 11/19 '일정 시간마다 +1%' 는 얼마마다인지 알 수 없었다 —— 특기(mods_text)처럼 보통 길이 전투의 합계로. 기술 준비는 그 등급 기본값 대비
		var at := float(C[k].tier) if C.has(k) else 8.0
		if mk in ["regen", "mregen"]:
			v *= Battle.pace_for(at) * RtBattle.turns_for(at)
		elif mk == "rate" and float(D.RATE.get(str(int(at)), 0.0)) > 0.0:
			v /= float(D.RATE[str(int(at))])
		if mk in ["dr", "idr"]:
			mine.append(_pct2(d[0], -v))
		elif d[1]:
			mine.append(_pct2(d[0], v))
		else:
			mine.append([d[0], "+%s" % str(snappedf(v, 0.1))])
	if not mine.is_empty():
		out.groups.append({"who": who, "items": mine})
	var theirs := []
	for st in a.get("foe", {}):
		theirs.append(_pct2(D.STATNM.get(st, st), a.foe[st]))
	if not theirs.is_empty():
		var ft: String = a.get("foe_to", "all")
		var fw: String = ("적 " + ft.substr(4)) if ft.begins_with("tag:") else AURA_FOE.get(ft, "적")
		out.groups.append({"who": fw, "items": theirs})
	if a.has("kiin"):
		out.text = kiin_text(a.kiin)
	return out


func _pct(name: String, v: float) -> String:
	return "%s %s%d%%" % [name, "+" if v > 0 else "−", roundi(absf(v) * 100)]


## _pct 의 구조판 —— [글, 값]
func _pct2(name: String, v: float) -> Array:
	return [name, "%s%d%%" % ["+" if v > 0 else "−", roundi(absf(v) * 100)]]

