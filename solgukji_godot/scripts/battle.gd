class_name Battle
extends RefCounted
## 전투 엔진 —— 원본 runBattle() 이식. 판정과 계수는 원본과 같다.
## 원본의 텍스트 로그에 연출용 필드를 더했다:
##   fx  : phys / int / morale / heal / buff / status / tick / cleanse / dodge / skill / rout / turn / end
##   a   : 행동한 유닛 key,  f : 대상 유닛 key,  n : 병력 수치,  m : 사기 수치,  st : 상태이상 종류
##   ai  : 행동 묶음 번호 (한 유닛의 한 차례 행동, 또는 턴 끝 정산),  ph : act / end,  who : 행동한 유닛 key
##   turn: 몇 번째 턴인지 —— 실시간 연출은 이 셋으로 행동을 시간축에 다시 깐다
##   s   : 이벤트 직후 모든 유닛의 [병력, 사기, 생존, 상태이상 목록] 스냅샷

const MYTH_AMP := 1.3     # 신화 장수가 제 유니크를 들면 아이템 효과 배율 (11/2 1.6 → 1.3 하향)
## 턴 배율 —— 솔국지 확장 (10/30). 전투를 이만큼 더 많은 턴으로 늘린다 (같은 등급 평균 4~10턴 → 15턴 안팎).
## 매 턴 반복되는 것(피해 · 회복 · 상태이상 확률 · 지속 턴)은 pace 로 나눠지거나 턴당 비율이 같아 그대로 둔다.
## 한 판에 한 번뿐인 것은 이만큼 키운다 —— 고유기 위력 · 고유기와 전투 시작 효과와 군령의 지속 턴 · 군령 사기.
## 이만큼 천천히 차는 것 —— 고유기 게이지 · 군령 포인트 · 같은 진영 고유기 간격. 턴마다 굴리는 패주 확률은 전체 빈도가 같게 줄인다.
## 턴 상한(원본 K.cap 20)과 첫 턴 기병 돌격 · 첫 공격 보너스도 이만큼 늘린다. 바꿀 때는 set_turn_mul().
## 등급마다 전투 길이가 달라(배율 3 에서 고급 10턴 · 초월 28턴) 전투에 나온 카드의 평균 등급으로 배율을 고른다 —— 어느 등급이든 15턴 안팎.
const BASE_PACE := 0.35
const TURN_MUL := {1: 4.9, 2: 4.9, 3: 4.9, 4: 5.9, 5: 3.7, 6: 2.8, 7: 3.75, 8: 9.8}   # 10/30 시너지 없앤 뒤 다시 맞춤
static var auto_turn := true      # 전투마다 평균 등급으로 배율을 고른다 (점검 장면이 --tmul 로 고정하면 false)
static var turn_mul := 3.0
## 전투 속도 —— 솔국지 확장 (원본에 없음). 턴마다 흐르는 양(병력·사기 피해, 지속 피해, 회복)을 모두 이만큼 곱한다. = BASE_PACE / turn_mul
## 원본 계수 그대로면 같은 등급끼리 2~3턴에 끝나 상태이상·디버프가 쓸 틈이 없다. 0.35 면 같은 등급끼리 평균 4~11턴
## (tests/turns.tscn). 비율은 그대로라 원본의 균형(피해 대 회복, 직접 대 지속)은 유지된다. 일회성 기준값
## (반파·괴멸 사기 하락, 패주 확률, 처형 문턱)은 바꾸지 않는다.
static var pace := BASE_PACE / 3.0


static func set_turn_mul(m: float) -> void:
	turn_mul = m
	pace = BASE_PACE / m


## 평균 등급 t 의 턴 배율 —— 표 사이는 잇는다
static func turn_mul_for(t: float) -> float:
	var lo := clampi(floori(t), 1, 8)
	var hi := clampi(lo + 1, 1, 8)
	return lerpf(TURN_MUL[lo], TURN_MUL[hi], clampf(t - lo, 0.0, 1.0))


## 그 등급 전투의 pace (카드 설명의 턴당 수치용)
static func pace_for(t: float) -> float:
	return BASE_PACE / turn_mul_for(t)


## 한 판에 한 번뿐인 효과의 턴당 세기 (고유기 · 군령 설명용) —— 턴 배율과 상관없이 같다
static func burst() -> float:
	return pace * turn_mul
## 사기는 '결과' —— 솔국지 확장. 책략 한 대마다 능력치에 비례해 사기를 깎던 것(원본 K.morale)을 없앴다.
## 사기 통은 등급과 관계없이 100 이라 낮은 등급에선 그 피해가 거의 0 이었고(책사·술사가 약한 까닭), 높은 등급에선 과했다.
## 대신 책략은 병력 피해가 int_troop 배로 오르고, 패주는 병력이 꺾여도 일어난다(rout_hp 아래, 비율에 따라).
## 스킬·고유기·특기의 고정 사기 효과, 아군 이탈·반파 충격, 역병 같은 '사건'은 그대로다.
static var int_troop := 1.7
static var rout_hp := 0.3          # 병력이 이 비율 아래면 턴 끝마다 패주를 굴린다
static var rout_hp_slope := 1.5    # (rout_hp - 남은 비율) × 이만큼 —— 10% 남으면 30%
static var ults_enabled := true     # 고유기 켜기 (밸런스 비교용으로 끌 수 있다)
static var passives_enabled := true  # 특기(개인·단체) 켜기
static var temper_enabled := true    # 11/7 고유기 기질 —— 장수별 게이지 원천 · 발동 조건 (끄면 모두 같은 원천 · 시간 대기만)
static var fire_enabled := true      # 화공 계열 켜기 (솔국지 확장 —— 비교용으로 끌 수 있다)
static var water_enabled := true     # 수공 계열 켜기 (수몰 이감 규칙 포함)
static var axis_off := {}            # 특기 축 끄기 (점검용) —— {"물리": true, …} 이면 그 축의 특기가 붙지 않는다
static var axis_off_camp := ""       # 축 끄기를 한쪽 진영에만 ("A" · "B", 비우면 양쪽) —— 점검할 덱 쪽만 끄려고
static var tr_mul := {"A": 1.0, "B": 1.0}      # 진영 병력 배율 —— Run.simulate · BattleView 가 전투 전에 넣고 뒤에 되돌린다 (11/6)
static var myth_power := 1.0     # 신화 능력치 배율 (속도 제외) —— 11/2 사용자: 단순 전투력은 1.15, 대신 위세(data/myth_aura.json)로 판을 바꾼다. 11/8 신화 몸값: 1.0 (카드 수치만으로 불멸의 공격 ×1.17 · 방어 ×1.21)
static var aura_enabled := true   # 위세 켜기 (비교용)
static var myth_troop := 0.75    # 11/8 신화 몸값 —— 신화 병력 배율 (mk_unit). 카드 병력 70000 → 52500 (불멸 47000 의 ×1.12, 예전 ×1.49)
static var paeup_enabled := true   # 11/8 패업 켜기 (비교용 —— 끄면 모두 불발)
static var aura_camp := ""        # 한쪽 진영만 위세 ("A" · "B", 비우면 양쪽) —— 점검용
static var synergy_enabled := false  # 세력 · 병종 시너지 (원본 SYN · TAGSYN) —— 10/30 사용자 결정으로 끔. 덱의 개성은 특기 · 기술이 맡는다
static var cut_enabled := true       # 수치 깎기 켜기 (위축 · 산란 · 파갑 —— 솔국지 확장)
static var guard_enabled := true     # 철벽 계열 켜기 (방진 · 반격 · 사수 —— 솔국지 확장)
static var counter_charge := false   # 반격을 맞은 쪽도 고유기 게이지가 차는가 —— 차면 반격이 적 고유기를 앞당겨 철벽이 손해를 봤다(10/29 측정)
static var scheme_enabled := true    # 계략 계열 켜기 (혼란 걸기 · 키우기 · 옮기기 · 미인계)
static var virtue_enabled := true    # 인덕 계열 켜기 (치료 · 분발 · 도원결의 · 단량)
## 11/3 8병종 역할 (사용자: 병종이 제 역할을 못 한다 —— tests/tag_role.tscn: 창병이 탱커 · 딜러를 겸하고 도적은 하는 일이 없었다)
## 창병 = 벽(도발 · 피해는 낮게) · 기병 = 첫 돌격 · 궁병 = 엄호받는 화력 · 도적 = 후열 암살 · 고유기 끊기
## 책사 = 범위 책략 화력 · 유생 = 치료 전담 · 술사 = 상태이상 전담 · 모사 = 사기 깎기
static var tag_roles := true
## 11/6 밸런스: 기병 3장 덱 30% → 돌격 뒤 배율 0.8 → 0.9 · 전체 0.9 → 1.0, 책략계 피격 감면(int_guard)은 방어 통합으로 대신
## (11/8 ROLE · CHARGE · SPEAR_ATK 는 점검 장면 tests/mono_league 가 바꿔 볼 수 있게 static var)
## 11/8 병종 균형: 유생 치료 schol_heal 1.6 → 0.6 (몰빵 리그전 유생 덱 84% —— 치료가 분발 · 인의 방진을 내내 켰다. 분발 재발동 대기 moved_cd 와 함께).
##   병종마다 준 피해 · 받는 피해 · 사거리 배율(등급 무관 한 값)은 data/cards_ext.json class_guard 의 dmg · taken · range (class_tune), 지원 등급 성장은 sup, 맞붙음 상성은 engage
static var ROLE := {"charge": 2.0, "horse_after": 0.9, "horse_all": 1.0, "int_guard": 1.0, "bow_cover": 1.25, "rogue_vs_int": 1.7, "rogue_vs_bow": 1.3, "rogue_all": 0.92,
	"rogue_gauge": 10.0, "rogue_charge": 0.3, "strat_int": 2.4, "schol_heal": 0.6, "schol_int": 1.3, "occul_heal": 0.3, "occul_status": 1.3, "occul_int": 1.55,      # 11/6 밸런스: 유생 · 술사 3장 덱 70% → 치료 2.5 → 2.0 · 상태이상 1.8 → 1.5
	"schem_morale": 2.2, "schem_int": 2.0}
## 낮은 등급 책략계 피해 (원본은 높은 등급에서야 책략이 세다 —— 희귀 책략계 3장 덱 승률 13~33%) · 기병 첫 돌격도 등급마다
const INT_LOW := {3: 1.6, 4: 1.6, 5: 1.3, 6: 1.1}
## 높은 등급 책사 책략 배율 —— 11/5 사용자: 책사계가 너무 약하다 (불멸 책사 피해 0.44 · 팀 평균 1.0)
const STRAT_HI := {7: 1.6, 8: 1.6}
static var CHARGE := {3: 1.15, 4: 1.15, 5: 1.3, 6: 1.45, 7: 1.7, 8: 1.9}
## 창병 피해 배율 —— 낮은 등급일수록 선호 자리 보너스(공격 ×1.22)가 커 더 낮춘다
static var SPEAR_ATK := {3: 0.45, 4: 0.45, 5: 0.5, 6: 0.55, 7: 0.6, 8: 0.65}
const INT_TAG := ["책사", "유생", "술사", "모사"]

static var counter_enabled := true   # 병종 상성 켜기 (솔국지 확장 —— DB.cls_mul)
## 11/8 피해 두 갈래 · 병종 갑옷 · 결계 · 깎기 (docs/역할_재설계_1108.md 9.1, 수치는 data/cards_ext.json class_guard → DB.GUARD)
static var shield_enabled := true    # 끄면 예전 판정 그대로 (지문 비교 · 점검용)
static var side_trait := {"A": {}, "B": {}}    # 토벌 우두머리 성질 {t: armor · ward · mix, v} —— tr_mul 처럼 Run.simulate · BattleView 가 전투 전에 넣고 뒤에 되돌린다
static var guard_over := {}          # 점검용 병종 막 덮어쓰기 {병종: 값} (--guard=창병:0.3,…) —— 물리 병종은 갑옷, 책략 병종은 결계
## 11/8 병종 균형 —— 병종 단위 배율 (data/cards_ext.json class_guard 의 dmg 준 피해(건 화상 · 출혈 포함) · taken 받는 피해 · range 원거리 사거리: {병종: 배율 또는 {등급: 배율}}).
## 점검 장면은 tune_over 로 덮어쓴다 (--set=dmg:창병:1.2 → {"dmg": {"창병": 1.2}})
static var tune_over := {}
## 11/8 분발 재발동 대기 (턴) —— 0 이면 예전처럼 치료받을 때마다 분발 · 인의 방진을 늘려 준다.
## 1 이상이면 분발은 새로 일어날 때만 걸리고(늘리지 않는다) 끝난 뒤 이만큼 지나야 다시 —— 여러 유생이 치료를 겹쳐 분발 · 방진이 내내 켜지던 것을 끊는다
static var moved_cd := 4

## 전투 중 개입 —— 고유기 직접 발동과 군령.
## 입력은 [행동 번호, 진영, 종류, 값]. 같은 시드 + 같은 입력이면 언제나 같은 결과다(결정적).
## 화면은 입력이 생길 때마다 처음부터 다시 계산한다 —— 입력 앞부분은 똑같이 나오고 뒤만 달라진다.
## 정책: auto(충전되면 제 차례에 바로 · 군령은 늘 돌격) · smart(상황을 보고 끼어든다) · manual(입력만)
##       tac:<고유기>:<군령> —— 덱 주인이 정하는 비동기 상대 AI 전술. smart = tac:영리:영리
##         고유기  즉시(차면 바로) · 영리(값어치 볼 때) · 위기(아군이 꺾였을 때만)
##         군령    공세(늘 돌격) · 영리(상대를 보고) · 수비(방진·재정비로 버틴다)
const GAUGE_ACT := 30.0       # 제 차례마다
const GAUGE_HIT := 80.0       # 병력을 잃은 비율 × 이만큼
const GAUGE_DEAL := 6.0       # 때릴 때마다
## 11/7 고유기 기질(temper) —— 사용자: 발동 조건을 단순 시간 대기만이 아니라 장수별로. 장수마다 기질 하나 (data/ultimates.json "temper", 없으면 temper_of 규칙):
##   맹장 = 때릴 때 차고 적을 무너뜨리면 더, 맞닿은 적이 있을 때 쓴다 · 수호 = 맞을 때 · 아군이 잃을 때 차고 아군이 다쳤을 때 쓴다
##   지략 = 차례마다 꾸준히 + 상태이상을 걸 때, 맞힐 적이 둘 이상일 때 · 저격 = 때릴 때 · 적을 무너뜨릴 때, 병력 60% 아래 적이 사거리 안일 때
##   분노 = 맞을 때 · 아군이 잃을 때 · 아군이 무너지면 크게, 아군이 무너졌거나 자기 병력 70% 아래일 때
## 값: act 차례 배율 · deal 때릴 때 배율 · hit 맞을 때 배율 · ally 아군이 잃은 비율 × GAUGE_HIT 의 몫 · kill 적을 무너뜨리면 + · fall 아군이 무너지면 + · status 상태이상 걸면 + · wait 대기 시간 배율
const TEMPER := {
	"맹장": {"act": 0.6, "deal": 2.2, "hit": 1.0, "ally": 0.0, "kill": 25.0, "fall": 0.0, "status": 0.0, "wait": 0.9},
	"수호": {"act": 1.0, "deal": 0.6, "hit": 1.8, "ally": 0.8, "kill": 0.0, "fall": 40.0, "status": 0.0, "wait": 1.0},     # 11/7 측정: 0.8 · 1.6 · 0.5 · 30 에선 불멸 · 신화 수호가 19~22% 만 터졌다
	"지략": {"act": 1.4, "deal": 0.8, "hit": 0.6, "ally": 0.0, "kill": 0.0, "fall": 0.0, "status": 12.0, "wait": 1.1},
	"저격": {"act": 1.0, "deal": 2.0, "hit": 0.8, "ally": 0.0, "kill": 40.0, "fall": 0.0, "status": 0.0, "wait": 1.0},     # 11/7 측정: 0.8 · 1.6 · 35 에선 26~44% · 첫 발동 30초
	"분노": {"act": 0.6, "deal": 1.2, "hit": 1.4, "ally": 0.6, "kill": 0.0, "fall": 40.0, "status": 0.0, "wait": 0.85},
}
const TEMPER_FREE := 22.0     # 전투 이 초(턴 엔진은 6턴)가 지나면 기질 발동 조건 없이 —— 쓰지도 못하고 끝나지 않게
const ULT_CHARGES := {6: 3, 7: 3, 8: 3}   # 11/7 사용자: 한 전투에서 다시 쓸 수 있되 쓸수록 어렵게 (예전 1번) —— 3번 상한
## 11/7 고유기 재사용 체감 —— 쓴 뒤 게이지 0 에서 다시 모으되 n번 쓴 장수는 기 모이는 속도 × reult_decay^n, 다음 발동은 제 대기 시간 × reult_wait 가 지나야.
## 목표(사용자): 두 번째 발동은 가끔(장수 20~30%), 세 번째는 거의 없음, 전투 길이 35초 안팎. 사람이 누르는 can_ult 도 같은 규칙
static var reult_decay := 0.7      # 11/7 측정: 2회 이상 발동 초월 9 · 불멸 4 · 신화 3%, 3회 0~1% —— 두 번째를 제 속도로 해도 같았다(전투 36~42초에 첫 발동 22~25초라 시간이 한계). 목표 20~30% 는 사용자 결정
static var reult_wait := 0.5
## 11/7 고유기 밸런스 2차 (사용자: "발동이 잦은 장수가 많다(주태 등) · 고유기 한 방으로 게임이 그냥 끝난다(신화 주유) · 거의 모든 범위에 효과가 있다")
## 고유기 한 방 상한 —— 고유기 한 번이 한 부대에서 앗는 병력은 그 부대 최대 병력의 이 몫까지 (쓴 장수 등급별, 기인은 초월 값). 처형 · 화상 같은 지속 피해는 따로.
## 높은 등급 고유기가 낮은 등급 부대(희귀 · 기인)를 한 번에 지우던 것 (리그전 덱: 한 부대 30% 넘게 7% · 50% 넘게 3% · 최대 100%)
## 측정(리그전 덱 40판): 한 부대 30% 넘게 7 → 2% · 50% 넘게 3 → 0% · 최대 100 → 30% · 고유기 한 번에 무너진 부대 0.22 → 0.12. 같은 등급끼리는 거의 걸리지 않는다(30% 넘는 피해 0~2%)
static var ult_cap := {6: 0.25, 7: 0.25, 8: 0.3}
## 기질별 재발동 대기 배율 —— 없으면 reult_wait. 수호 · 분노는 아군이 다칠수록 기가 차서 늘 먼저 차 있고, 같은 진영 고유기 순번(먼저 찬 장수부터)만 기다리다
## 판 후반에 거듭 터졌다 (기준 60판: 주태(초월) 보유 부대당 1.27번 · 2회 이상 36%, 하후돈 · 마초 · 장비(불멸) 0.96~1.22번 —— 등급 평균 0.65 · 0.53).
## 재사용 감쇠를 0.55 로 낮추거나 쓴 뒤 아군 피해로 받는 기를 절반으로 해도 주태는 그대로였다(1.26번 · 31%) —— 기가 아니라 시간으로 막는다
## 측정(30판 짝 비교): 수호 ×2.5 · 분노 ×2.0 —— 주태 1.26 → 1.08번 · 2회 이상 31 → 13% · 재발동 간격 24 → 35초, 하후돈 2회 이상 18 → 5%. 다른 기질 · 등급 평균은 그대로
static var reult_temper := {"수호": 2.5, "분노": 2.0}
var _ult_by: Unit = null       # 지금 고유기를 쓰는 장수 (상한 등급)
var _ult_taken := {}           # 이번 고유기에 부대마다 잃은 병력 (상한용)
const SK_BANK := 2.0       # 일반 기술 충전 상한 —— 조건이 안 맞는 동안 두 번까지 모아 둔다
const ULT_SIDE_GAP := 4       # 같은 진영 고유기 사이 최소 행동 수
const PTS_EVERY := 6          # 행동 6번마다 군령 포인트 1
const PTS_MAX := 3.0
const CMD_COST := 2.0
const CMD_TURNS := 2
const CRISIS_LOSS := 0.35     # 위기 —— 아군 평균 병력 손실이 이만큼 넘거나
const CRISIS_UNITS := 5       #        살아 있는 부대가 이만큼 이하면
static var crisis_amp := 1.3  # 위기에 쓴 고유기 위력 배율 (배수진) —— 점검용으로 바꿀 수 있어 static
static var cmd_links := true   # 특기–군령 연결 켜기 (비교용)
## 작전 (덱 주인이 전투 전에 고른다 —— 11/1 덱 감상 전투). 영리가 늘 이기지 않게 작전마다 강점을 하나씩
static var tac_rush_pts := 2.0     # 공세 군령 —— 군령 포인트를 이만큼 들고 시작 (첫 돌격이 바로)
static var tac_rush_atk := 0.25    # 공세 군령 —— 돌격의 공격 상승 +이만큼 (맹진처럼)
static var tac_hold_amp := 1.6     # 위기 고유기 —— 배수진 위력 배율 (영리 · 즉시는 crisis_amp)
static var breach := 0.0      # 돌격 중인 공격자가 무시하는 적 방진 피해 감소 비율 —— 0 이 기본 (올리면 조작 효과가 사라진다, 기획 문서 참고)
const CMDS := {
	"돌격": {"d": "공격 +20% · 방어 -25%", "buffs": [{"stat": "atk", "amt": 0.20}, {"stat": "def", "amt": -0.25}, {"stat": "breach", "amt": 1.0}]},
	"방진": {"d": "받는 피해 -30% · 속도 -10% · 받는 고유기 피해 추가 -35%", "buffs": [{"stat": "guard", "amt": 0.30}, {"stat": "spd", "amt": -0.10}, {"stat": "uguard", "amt": 0.35}]},
	"재정비": {"d": "사기 +9 · 패주 확률 -60%", "buffs": [{"stat": "calm", "amt": 0.6}], "morale": 25.0},     # 사기는 heal_morale 에서 pace(0.35)를 곱해 +9
}


class Unit:
	var strat_aura := 0.0     # 책략 오라 세기 (이웃 책사 · 모사, _settle 마다 갱신)
	var minor_n := -1         # 잔기술 차례 세기 (-1 = 아직 시작 전)
	var c: Dictionary
	var line: String
	var side: String
	var camp: String
	var slot: int
	var key: String
	var item = null
	var troops: float
	var max: float
	var morale: float
	var syn_atk: float
	var syn_spd: float
	var ts = null           # 병종 시너지 {stat, v, lv}
	var caps := {}
	var regen_up := false
	var fast_side := false
	var boon = null
	var buffs := []
	var alive := true
	var hit50 := false
	var hit25 := false
	var m := {}               # 특기 수정치 (data/passives.json 의 m 키) —— mv() 로 읽는다
	var avenge_n := 0         # 비장 —— 아군이 무너진 횟수
	var opens := 0            # 첫 공격 보너스를 쓴 횟수 (기신·강행·습격) —— 턴 배율만큼 나눠 쓴다
	var night_used := false   # 야습 —— 첫 공격의 확정 점화를 썼는가
	var cut_used := false     # 쇄갑 —— 첫 물리 공격의 큰 파갑을 썼는가
	var cut := {"atk": 0.0, "int": 0.0, "def": 0.0}   # 수치 깎기 (위축 · 산란 · 파갑) —— 전투 끝까지 쌓이고 0 까지
	var shield := {"phys": 0.0, "int": 0.0}   # 11/8 갑옷(받는 물리 피해 −) · 결계(받는 책략 피해 −) —— 병종 기본, 토벌 우두머리는 그날 성질
	var shred := {"phys": {"v": 0.0, "t": 0, "by": ""}, "int": {"v": 0.0, "t": 0, "by": ""}}   # 갑옷 · 결계 깎기 (값 · 남은 턴 · 출처 부대 키) —— 종류별 가장 센 하나. 출처를 Unit 으로 들면 순환 참조가 생겨 키로
	var kill_amp := 0.0       # 기세 —— 적을 무너뜨린 뒤 다음 공격 피해 +
	var chase_turn := -1      # 추격 —— 이 턴에 한 번 더 쳤다
	var in_skill := false     # 기술을 쓰는 중 (신산)
	var cleaving := false     # 휩쓸기 · 파상 피해 중 (다시 번지지 않게)
	var steady_used := false  # 진정 —— 사기 60 아래에서 한 번 추스름을 썼는가
	var moved_next := -999    # 11/8 분발을 다시 받을 수 있는 턴 (moved_cd)
	var stand_used := false   # 사수 —— 방진 중 병력 1에서 버티기를 썼는가
	var countering := false   # 반격 중 (점검 통계용)
	var taken := 0.0          # 받은 병력 피해 합 (결과표 —— 11/3: '처음 − 남은' 은 쓰러진 부대가 모두 최대 병력으로 같아 보였다)
	var theal := 0.0          # 병력 치료 합 (최대 병력 대비 · 점검용)
	var charged := false      # 기병 첫 돌격을 했는가 (11/3 병종 역할)
	var dmg := 0.0
	var mdmg := 0.0
	var heal := 0.0
	var kills := 0
	var last_hit: Unit = null
	var st := []
	var ult = null            # 고유기 (초월·불멸·신화) —— DB.ult_of 참고
	var gauge := 0.0          # 고유기 게이지 (100 이면 준비)
	var ult_ready_t := -1.0   # 게이지가 100 에 닿은 시각 (실시간 엔진) —— 먼저 찬 부대가 먼저 쓴다 (11/6 #14)
	var temper := ""          # 고유기 기질 (11/7, TEMPER 의 열쇠. 고유기가 없으면 빈 글)
	var ult_n := 0            # 이 전투에서 고유기를 쓴 횟수 (11/7 재사용 체감 —— 쓸수록 게이지가 느리게 찬다)
	var ult_tm := -99.0       # 마지막으로 고유기를 쓴 시각 (실시간 엔진, 초)
	var ult_turn := -99       # 마지막으로 고유기를 쓴 턴 (턴 엔진)
	var sk_ch := []           # 기술 충전 —— 11/3 부터 [0] 하나를 모든 기술이 나눠 쓴다
	var charges := 0          # 남은 고유기 횟수
	# 실시간 엔진(RtBattle) —— 전장 위치와 행동 준비. 턴 엔진은 쓰지 않는다
	var pos := Vector2.ZERO
	var fwd := Vector2.RIGHT
	var tgt: Unit = null      # 지금 노리는 적
	var atb := 0.0            # 행동 준비 (1 이 되면 사거리 안의 적을 친다)
	var retgt := 0.0          # 다음 대상 다시 고르기까지 (초)
	var ran := 0.0            # 마지막 공격 뒤 달려온 거리 (기병 돌격)
	# 11/7 군집 강체 (RtBattle) —— 대열 발자국 · 속도
	var hw := 28.0            # 발자국 반폭 (좌우)
	var hd := 28.0            # 발자국 반깊이 (앞뒤) —— 병력에 따라 뒤에서부터 줄어든다
	var hd0 := 28.0           # 처음 반깊이
	var vel := Vector2.ZERO   # 속도 (px/초)
	var block_t := 0.0        # 앞이 막힌 채 지난 시간 (초)


var K: Dictionary
var rng := RandomNumberGenerator.new()
var units: Array[Unit] = []
var ev := []
var _ai := 0
var _ph := "act"
var _who := ""
var _turn := 0
var inputs := []              # 받을 입력 [행동 번호, 진영, 종류, 값]
var applied := []             # 실제로 적용된 입력 (재생·검증용)
var rejected := []            # 거절된 입력과 까닭 (점검용)
var policy := {"A": "auto", "B": "auto"}
var act_n := 0                # 지금까지 끝낸 행동 수 —— 입력 시점의 기준
var pts := {"A": 0.0, "B": 0.0}
var cmdm := {"A": {}, "B": {}}    # 특기–군령 연결 (data/passives.json catalog 의 cmd) —— 진영 단위
var _ult_last := {"A": -99, "B": -99}
var _bdone := -1              # 입력 판정(_between)을 마친 행동 번호 —— 사건에 bd 로 적어 화면이 입력 시점을 고른다
var _sk_on := false           # 일반 기술 타격 중 (점검 통계)
var _in_ult := false          # 고유기 타격 중 —— 방진이 이만큼 막는다
var _one := 1.0               # 한 번뿐인 효과(고유기 · 군령 사기)의 세기 배율 —— 그동안 turn_mul
var _long := 1.0              # 한 번뿐인 효과(고유기 · 전투 시작 · 군령)의 지속 턴 배율 —— 그동안 turn_mul
var _myths: Array[Unit] = []   # 위세를 가진 장수 (신화 · 초월 —— 전투 준비 때 모은다)
var _aura_m: Array[Unit] = []  # 그 가운데 특수 효과(m)를 주는 장수 —— mv() 가 더한다
var _tm := 0.0                # 전장 시각(초) —— 실시간 엔진만 쓴다. 사건에 tm 으로 적는다
var stats := {"dmg": 0.0, "ult_dmg": 0.0, "sk_dmg": 0.0, "sk_n": 0, "blocked": 0, "ult_hits": 0,    # 점검용
	"burn": 0.0, "fire_amp": 0.0, "ignites": 0, "spreads": 0, "doused": 0, "terror": 0.0, "blazes": 0, "scorched": 0,
	"flood": 0.0, "water_amp": 0.0, "soaks": 0, "flows": 0, "drowned": 0, "tides": 0, "steams": 0,
	"tac_amp": 0.0, "cuts": 0.0, "cut_n": 0, "execs": 0, "kills_amp": 0, "chases": 0, "cleaves": 0.0, "awes": 0, "rallied": 0.0,
	"phalanx": 0, "counters": 0, "counter_dmg": 0.0, "stands": 0, "phys": 0.0, "intd": 0.0, "ph_taken": 0.0,
	"scheme_amp": 0.0, "confuses": 0, "passes": 0, "turncoats": 0, "jolts": 0.0,
	"mends": 0.0, "moved": 0, "oaths": 0, "shreds": 0}
var _oath_used := {"A": false, "B": false}
## 11/4 연출 점검 —— 승부가 갈린 뒤 평타만 30초 넘게 이어지던 '정리 시간'을 끊는다.
## 총붕괴: 한쪽이 부대 5/9 이상을 잃거나 병력이 처음의 30% 아래면 남은 부대 사기가 초마다 크게 깎여 줄줄이 무너진다.
## 결전: 45초가 넘으면 양군 사기 회복이 멈추고 조금씩 깎인다 —— 약한 쪽부터 무너진다.
const COLLAPSE_TROOPS := 0.3    # 남은 병력이 처음의 이 비율 아래이고
const COLLAPSE_VS_FOE := 0.5    # 적 병력의 이 비율에도 못 미치면 총붕괴 (부대 수는 보지 않는다 —— 신화 한 부대가 군세의 반일 수 있다)
const COLLAPSE_MORALE := 45.0   # 한 턴(period)마다 깎이는 사기
const COLLAPSE_ROUT := 3.0      # 총붕괴 진영의 패주 확률 배율
const COLLAPSE_HOLD_TIER := 7   # 이 등급부터(불멸 · 신화)는 총붕괴에 휩쓸리지 않는다 —— 9부대 중 신화 하나가 남아도 버틴다
const DECISIVE_T := 45.0
const DECISIVE_MORALE := 12.0
const ROUT_SPREAD := 1.5        # 패주 전염 (K.routSame · routOther 배율) —— 한 번 무너지면 줄줄이
var _collapsed := {"A": false, "B": false}
var _decisive := false
var _start_troops := {"A": 0.0, "B": 0.0}
var _kiin_u := {}              # 11/3 기인 —— 기능 키 -> 유닛 배열
var _kiin_used := {}           # "키:진영" -> 쓴 횟수
var _paeup := {}               # 11/8 패업(霸業) —— "효과키:진영" -> 신화 유닛 (전투 전 편성으로 정한다. 기인 kiin 과 따로)
var _paeup_used := {}          # "효과키:진영" -> 쓴 횟수
var _stolen := {}             # 11/9 협천자 —— 빼앗긴 적 위세 장수 -> 빼앗은 쪽 진영
var _omen := {}               # 11/9 천문 —— 기를 모으는 적 장수 -> 그 고유기가 칠 아군 칸 키들
var _pass_busy := false       # 오관참장 돌진 중 (연쇄로 또 돌진하지 않게)
var _paeup_log := []           # 결과 기록 —— [{camp, id, n, on, have, need}]
const PAEUP_ST := ["burn", "flood", "plague", "seal", "confuse"]      # 태평요술이 세는 상태이상 (출혈은 빼다 —— 설계 문서 4.2)
var _ult_null := false         # 서성 장강방벽 —— 이번 고유기는 피해가 없다
const KIIN_MID_TURN := 10      # 좌자 · 초선 —— 중반 한 번 더
## 덱 연쇄 —— 진영별 특기 연쇄 횟수 (결과표 · 전투 중 강조). 1 · 3 · 6 · 10 · 15 · 20 · 30 · 50 번째에 사건을 남긴다
var chains := {"A": {}, "B": {}}
const CHAIN_MARKS := [1, 3, 6, 10, 15, 20, 30, 50]


func _init(seed_value: int = -1) -> void:
	K = DB.K
	if seed_value >= 0:
		rng.seed = seed_value
	else:
		rng.randomize()


func rnd(a: float, b: float) -> float:
	return a + rng.randf() * (b - a)


func pick(a: Array):
	return a[rng.randi() % a.size()]


static func jong(w: String) -> bool:
	if w.is_empty():
		return false
	var c := w.unicode_at(w.length() - 1) - 0xAC00
	return c >= 0 and c < 11172 and c % 28 != 0


static func ga(w: String) -> String: return w + ("이" if jong(w) else "가")
static func eul(w: String) -> String: return w + ("을" if jong(w) else "를")
static func nm(u: Unit) -> String: return ("적 " if u.camp == "B" else "") + u.c.name


# ───────── 시너지 ─────────

static func fac_syn(cards: Array, form: String) -> Dictionary:
	var fc := {}
	var tc := {}
	for k in cards:
		if k == null:
			continue
		var c: Dictionary = DB.C[k]
		fc[c.fac] = fc.get(c.fac, 0) + 1
		tc[c.tag] = tc.get(c.tag, 0) + 1
	var out := {"morale": 0.0, "atk": 1.0, "spd": 1.0, "troop": 1.0, "list": [], "tag": {},
		"tagList": [], "caps": {}, "boon": DB.D.FORMBOON.get(form)}
	if not synergy_enabled:      # 10/30 세력 · 병종 시너지 없앰 —— 진형 우대(boon)만 남는다
		return out
	for f in fc:
		var s = DB.D.SYN.get(f)
		if s == null:
			continue
		var lv := -1
		for i in DB.D.SYN_STEP.size():
			if fc[f] >= DB.D.SYN_STEP[i]:
				lv = i
		if lv < 0:
			continue
		var v: float = s.v[lv]
		if s.stat == "morale":
			out.morale += v
		else:
			out[s.stat] *= (1.0 + v)
		out.list.append({"fac": f, "n": fc[f], "lv": lv + 1, "v": v})
		if f == "촉" and fc[f] >= 5: out.regenUp = true
		if f == "오" and fc[f] >= 5: out.fastSide = true
	for t in tc:
		var s = DB.D.TAGSYN.get(t)
		if s == null:
			continue
		var lv := -1
		for i in DB.D.TAGSYN_STEP.size():
			if tc[t] >= DB.D.TAGSYN_STEP[i]:
				lv = i
		if lv < 0:
			continue
		out.tag[t] = {"stat": s.stat, "v": float(s.v[lv]), "lv": lv + 1}
		out.tagList.append({"tag": t, "n": tc[t], "lv": lv + 1})
		if tc[t] >= 5:
			out.caps[t] = s.cap
	return out


func mk_unit(cid: String, slot_info: Dictionary, camp: String, morale: float, slot: int, item, syn: Dictionary) -> Unit:
	var u := Unit.new()
	u.c = DB.C[cid]
	u.line = slot_info.line
	u.side = slot_info.side
	u.camp = camp
	u.slot = slot
	u.key = camp + str(slot)
	u.item = item
	u.ts = syn.tag.get(u.c.tag)
	var tr: float = u.c.tr * syn.troop * (1.0 + u.ts.v if u.ts and u.ts.stat == "troop" else 1.0)
	if u.c.tier >= 8: tr *= myth_troop
	tr *= float(tr_mul.get(camp, 1.0))      # 11/6 밸런스: 진영 병력 배율 (토벌 고정 편성을 일차에 맞춰 줄인다 —— Run.QUEST_TR)
	u.troops = roundf(tr)
	u.max = roundf(tr)
	u.morale = minf(200, morale + syn.morale)
	u.syn_atk = syn.atk
	u.syn_spd = syn.spd
	u.caps = syn.caps
	u.regen_up = syn.get("regenUp", false)
	u.fast_side = syn.get("fastSide", false)
	var boon = syn.boon
	u.boon = boon if boon and boon.tags.has(u.c.tag) else null
	var ps = DB.passives_of(cid)
	if ps != null:
		for t in ps.traits:
			if not _trait_on(t, camp):
				continue
			for k in t.m:
				var mk: String = _shred_key(t.name, k) if shield_enabled else k      # 11/8 방어 깎기 특기 → 갑옷 · 결계 깎기 키
				u.m[mk] = u.m.get(mk, 0.0) + t.m[k]
	# 11/3 특기 점검 (tests/trait_probe): 수엄칠군(drown)을 가진 관우에게 수몰을 거는 수단이 없어, 아군에 수공 장수가 없으면 한 번도 발동하지 않았다.
	# 설명대로 "자신의 수공이 칠군을 잠근다" —— 스스로 맞힐 때 수몰을 건다
	if u.m.get("drown", 0.0) > 0 and u.m.get("soak", 0.0) <= 0 and _trait_on({"attr": "수공"}, camp):
		u.m["soak"] = DROWN_SOAK
	if shield_enabled:
		_set_shield(u, camp, slot)
	if u.c.tier >= 6 or u.c.kind == "kiin":      # 11/3 기인도 고유기 (초월 세기)
		u.ult = DB.ult_of(cid)
		if u.ult:
			u.charges = ULT_CHARGES.get(u.c.tier, 1)
			u.temper = temper_of(u)
	return u


## 11/8 병종 갑옷 · 결계 —— 점검 덮어쓰기(guard_over)가 먼저. 토벌 우두머리(B 진영 고정 편성 9부대 —— 잡병은 9번 칸부터)는
## 그날 성질로 바꿔 쓴다 (더하지 않는다): armor 갑옷만 · ward 결계만 · mix 선봉 · 전군 줄은 갑옷, 중군 · 후군 줄은 결계
func _set_shield(u: Unit, camp: String, slot: int) -> void:
	var tag: String = u.c.tag
	if guard_over.has(tag):
		var gv := float(guard_over[tag])
		u.shield = {"phys": 0.0 if INT_TAG.has(tag) else gv, "int": gv if INT_TAG.has(tag) else 0.0}
	else:
		u.shield = DB.guard_of(tag)
	var tr: Dictionary = side_trait.get(camp, {})
	if camp != "B" or slot >= 9 or str(tr.get("t", "")) == "":
		return
	var t := str(tr.t)
	var v := float(tr.get("v", 0.0))
	if t == "mix":
		t = "armor" if u.line in ["선봉", "전군"] else "ward"
	u.shield = {"phys": v if t == "armor" else 0.0, "int": v if t == "ward" else 0.0}


## 점검 인자 --guard=창병:0.3,기병:0.15,… → guard_over (병종: 막)
static func guard_arg(s: String) -> Dictionary:
	var out := {}
	for kv in s.split(",", false):
		var p := kv.split(":")
		if p.size() == 2:
			out[p[0].strip_edges()] = float(p[1])
	return out


## 11/8 방어 깎기 특기 키 → 갑옷 · 결계 깎기 키 (켬 = 1, 수치는 엔진 등급표 class_guard.shred).
## passives.json 이 아직 예전 키라 특기 이름으로 가른다 —— 현혹(책략이 맞을 때) · 요언(개전 적 전원)은 결계, 나머지는 갑옷.
## 2단계에서 데이터 키를 shred · first_shred · wshred · open_wshred 로 바꾸면 그대로 지나간다
const SHRED_KEY := {"cut_def": "shred", "first_cut": "first_shred", "open_cut_def": "open_wshred"}
static func _shred_key(tn: String, k: String) -> String:
	if k == "cut_def" and tn == "현혹":
		return "wshred"
	return SHRED_KEY.get(k, k)


## 특기 켜짐 —— 축(attr)이 axis_off 에 있으면 끈다. 철벽 · 인덕은 guard_enabled · virtue_enabled 로도 끈다
func _trait_on(t: Dictionary, camp := "") -> bool:
	if not passives_enabled:
		return false
	if axis_off.has(t.attr) and (axis_off_camp == "" or camp == "" or camp == axis_off_camp):
		return false
	match t.attr:
		"도트": return fire_enabled
		"철벽": return guard_enabled
		"인덕": return virtue_enabled
	return true


func innate_item(cid: String):
	var need: String = DB.C[cid].need
	return DB.ITEM_BY_NAME.get(need) if need != "" else null


func is_signature(u: Unit) -> bool:
	return u.c.need != "" and DB.ITEM_BY_NAME.get(u.c.need) == u.item


# ───────── 실효 수치 ─────────

func eff(u: Unit, stat: String) -> float:
	stat = S(stat)      # 11/6 #15 int → atk
	var c := u.c
	var lm: Dictionary = DB.D.LINE[u.line]
	var af: Dictionary = DB.D.AFF[c.tag]
	var v: float = c[stat]
	var caster := is_caster(c)
	if c.tier >= 8 and stat != "spd": v *= myth_power      # 11/2 사용자: 신화 한 장이 불멸 · 초월보다 확실히 세게
	if stat == "atk": v *= (lm.int if caster else lm.atk)      # 책략계는 예전 책략 줄 배율(뒤에서 세다)
	if stat == "def": v *= lm.def
	if stat == "atk" and mv(u, "front_atk") != 0.0 and _is_front(u): v *= 1 + mv(u, "front_atk")
	if stat == "atk" and mv(u, "back_int") != 0.0 and _is_back(u): v *= 1 + mv(u, "back_int")
	v *= 1 + mv(u, stat)
	if stat == "atk":
		if u.troops < u.max * 0.5: v *= 1 + mv(u, "low_atk")
		v *= 1 + mv(u, "avenge") * u.avenge_n
	var zone := DB.aff_of(c.tag, u.line, u.side)
	if zone == "pref": v *= _sm(af.b, stat)
	if zone == "bad": v *= _sm(af.p, stat)
	if u.item:
		var it: Dictionary = DB.IT[u.item]
		var amp := MYTH_AMP if is_signature(u) else 1.0
		if S(it.pri) == stat: v *= (1 + it.pa * amp)
		if S(it.sec) == stat: v *= (1 + it.sa * amp)
	if stat == "atk": v *= u.syn_atk
	if stat == "spd": v *= u.syn_spd * _flood_slow(u)
	if u.ts and S(u.ts.stat) == stat: v *= (1 + u.ts.v)
	if u.boon and S(u.boon.stat) == stat: v *= (1 + u.boon.v)
	for b in u.buffs:
		if S(b.stat) == stat: v *= (1 + b.amt)
	if stat == "atk": v *= (0.4 + 0.6 * (u.troops / u.max))
	v *= morale_mul(u)               # 사기 —— 모든 능력치에 (2026-10-30 사용자 결정)
	if aura_enabled and not _myths.is_empty():
		v *= _aura_mul(u, stat)
	if u.strat_aura > 0.0 and stat == "def":
		v *= 1.0 + STRAT_AURA_DEF * u.strat_aura
	if stat == "atk" and not _paeup.is_empty():
		v *= _paeup_atk(u)      # 손권 제왕술 · 여포 무쌍
	v -= u.cut.get(stat, 0.0) + u.cut.get(STAT_INV.get(stat, "_"), 0.0)        # 위축 · 산란 · 파갑 —— 0 까지
	return maxf(1, v)


## 11/6 사용자 #15 "마법 개념 삭제 · 모두 그냥 피해로 통일 · 책략 / 책략방어 제거"
## 카드의 공격 = 공 · 책 중 높은 쪽, 방어 = 방 · 책방 중 높은 쪽 (DB.merge_stats). 피해 경로는 phys_hit 하나.
## 옛 데이터(특기 · 아이템 · 위세 · 기술 · 진형 우대)의 int 와 책략 전용 키는 아래 별칭으로 공격 쪽에 합친다.
## 책략방어(res)는 11/7 데이터에서 지웠다 —— 방어(def)로 옮기고, 한 효과에 둘이 같이 있으면 큰 값 하나만 남겼다 (tools/scripts/extract.py drop_res)
## 책략계 병종(INT_TAG)은 '원거리 · 범위 · 상태이상' 역할로만 남고, 줄 배율은 예전 책략 줄 배율(LINE.int)을 공격에 쓴다
const STAT_ALIAS := {"int": "atk"}
const STAT_INV := {"atk": "int"}
const MV_ALIAS := {"atk": "int", "crit": "icrit", "dr": "idr", "cleave": "icleave", "cut_atk": "cut_int"}
static func S(stat: String) -> String:
	return STAT_ALIAS.get(stat, stat)
static func is_caster(c: Dictionary) -> bool:
	return INT_TAG.has(c.tag)
## 사전에서 stat 과 그 옛 별칭을 합쳐 읽는다 (더하는 값)
static func _sv(d: Dictionary, stat: String, dflt := 0.0) -> float:
	var v := float(d.get(stat, dflt))
	if STAT_INV.has(stat) and d.has(STAT_INV[stat]):
		v = (v if d.has(stat) else 0.0) + float(d[STAT_INV[stat]])
	return v
## 곱하는 값 —— 둘 다 있으면 곱
static func _sm(d: Dictionary, stat: String) -> float:
	var v := float(d.get(stat, 1.0))
	if STAT_INV.has(stat) and d.has(STAT_INV[stat]):
		v *= float(d[STAT_INV[stat]])
	return v


## 책략 오라 (11/4 지시서: 책사 · 모사가 기술 쿨타임 중에도 무기력하지 않게) —— 살아 있는 책사 · 모사 이웃(같은 열 · 실시간은 가까운 거리,
## 자기 자신 포함)이 있으면 방어 +5% (11/7 방어 4% · 책략방어 5% 를 큰 값 하나로). 둘 이상은 1.6 배까지만. 정산마다 한 번 센다 (eff 가 매번 세지 않게)
## 잔기술 3차 (11/5 사용자: 병종이 아니라 장수 특징으로 —— 책략계 평타가 약해 무기력하다. 일정 차례마다 가벼운 불 · 독병 · 거짓 정보 ·
## 랜스 돌격 · 암습 · 단도 던지기 같은 기본기). 장수(고급 이상)마다 하나, 특기 축(도트 → 화계, 혼란 → 거짓 정보 …)으로 고르고
## 축이 없으면 병종 기본기. 평타 every 번에 한 번 평타 대신 쓴다. 충전 · 비용 · 조건 없음, 난수 없음.
## 타격 사건에 이름(mn) · 종류(mk)만 붙인다 —— 화면이 종류별 이펙트를 그린다 (War3D.minor_fx)
##   mult 위력 · back 적 후열을 노린다 · kind phys/int 타격 종류(없으면 장수 주 능력치) · st [상태, 세기, 턴] · foe / self 짧은 능력치(턴)
##   morale 적 사기 − · extra 같은 적에게 한 번 더 · mend/cheer 가장 지친 아군 병력 + / 사기 +
static var minor_enabled := true
const MINOR := {
	"fire": {"n": "화계", "every": 3, "mult": 0.9, "kind": "int", "st": ["burn", 0.05, 2]},
	"poison": {"n": "독병", "every": 3, "mult": 0.7, "st": ["plague", 3.0, 2], "foe": {"stat": "atk", "amt": -0.06, "dur": 2}},
	"rumor": {"n": "유언비어", "every": 5, "mult": 0.6, "kind": "int", "st": ["confuse", 1.0, 1], "morale": 3.0},
	"curse": {"n": "저주", "every": 3, "mult": 1.0, "kind": "int", "foe": {"stat": "def", "amt": -0.1, "dur": 2}},
	"thunder": {"n": "낙뢰", "every": 4, "mult": 1.5, "kind": "int"},
	"cheer": {"n": "격려", "every": 3, "mult": 0.9, "mend": 0.01, "cheer": 4.0},
	"guard": {"n": "방벽", "every": 3, "mult": 1.0, "self": {"stat": "def", "amt": 0.1, "dur": 2}},
	"lance": {"n": "창기 돌격", "every": 4, "mult": 1.6, "kind": "phys", "morale": 3.0},
	"ambush": {"n": "암습", "every": 3, "mult": 1.4, "kind": "phys", "back": true},
	"dagger": {"n": "단도 던지기", "every": 3, "mult": 0.8, "kind": "phys", "back": true, "st": ["bleed", 0.04, 2]},
	"thrust": {"n": "찌르기", "every": 3, "mult": 1.3, "kind": "phys", "foe": {"stat": "def", "amt": -0.05, "dur": 2}},
	"volley": {"n": "연사", "every": 3, "mult": 1.0, "kind": "phys", "extra": 0.6},
	# 11/5 사용자: 장비가 거짓 정보(책략 피해)를 쓴다 —— 책략 잔기술을 무장(공격 ≥ 책략)이 받으면 같은 축의 무력판으로 (MINOR_PHYS)
	"fire_arrow": {"n": "불화살", "every": 3, "mult": 0.9, "kind": "phys", "st": ["burn", 0.04, 2]},                  # 화계의 무력판 (적벽 · 박망파의 불화살)
	"roar": {"n": "일갈", "every": 5, "mult": 0.7, "kind": "phys", "st": ["confuse", 1.0, 1], "morale": 4.0},          # 거짓 정보의 무력판 (장판교의 일갈)
	"shatter": {"n": "방패 깨기", "every": 3, "mult": 1.0, "kind": "phys", "foe": {"stat": "def", "amt": -0.1, "dur": 2}},   # 저주의 무력판
	"spark": {"n": "도술 일격", "every": 4, "mult": 1.3, "kind": "phys"},          # 낙뢰의 무력판 (드물다)
	"awe": {"n": "위압", "every": 3, "mult": 0.9, "kind": "phys", "morale": 3.0, "foe": {"stat": "atk", "amt": -0.08, "dur": 2}}}   # 독병의 무력판 —— 위세로 적을 움츠리게 (관우의 위진화하)
## 11/5 사용자: 격려가 69명에게 몰렸다 —— 인물마다 연의 일화로 나눈다 (MINOR_PERSON 이 축 · 병종보다 먼저)
const MINOR_STORY := {
	"vanguard": {"n": "선봉 돌파", "every": 3, "mult": 1.4, "kind": "phys", "morale": 3.0},
	"duel": {"n": "일기토", "every": 4, "mult": 1.7, "kind": "phys", "self": {"stat": "atk", "amt": 0.08, "dur": 2}},           # 사수관 · 백마 · 반하의 일기토
	"lone_ride": {"n": "단기 돌파", "every": 3, "mult": 1.3, "kind": "phys", "back": true, "self": {"stat": "spd", "amt": 0.1, "dur": 2}},   # 장판파
	"xiliang": {"n": "서량 철기", "every": 3, "mult": 1.3, "kind": "phys", "foe": {"stat": "spd", "amt": -0.1, "dur": 2}},
	"white_horse": {"n": "백마의종", "every": 3, "mult": 1.0, "kind": "phys", "back": true, "extra": 0.5},
	"cleave": {"n": "방천화극", "every": 4, "mult": 1.5, "kind": "phys", "extra": 0.4},
	"conquer": {"n": "소패왕의 돌격", "every": 3, "mult": 1.4, "kind": "phys", "morale": 4.0},
	"tiger": {"n": "사호", "every": 3, "mult": 1.5, "kind": "phys", "back": true},                  # 범을 쏘아 잡은 손권
	"raid": {"n": "강상 기습", "every": 3, "mult": 1.4, "kind": "phys", "back": true, "morale": 2.0},   # 수적 · 설중분전 · 백의도강
	"plunder": {"n": "약탈", "every": 3, "mult": 1.2, "kind": "phys", "morale": 4.0, "foe": {"stat": "atk", "amt": -0.05, "dur": 2}},
	"last_stand": {"n": "결사 항전", "every": 3, "mult": 1.1, "kind": "phys", "self": {"stat": "def", "amt": 0.12, "dur": 2}},   # 관을 지고 나선 방덕
	"ambush_shot": {"n": "매복 사격", "every": 3, "mult": 1.5, "kind": "phys", "back": true},        # 낙봉파 · 현산의 매복
	"surprise": {"n": "우회 기습", "every": 3, "mult": 1.4, "kind": "phys", "back": true, "st": ["bleed", 0.03, 2]},   # 자오곡
	"plan": {"n": "계책", "every": 3, "mult": 1.1, "kind": "int", "foe": {"stat": "def", "amt": -0.06, "dur": 2}},
	"secret": {"n": "밀고", "every": 4, "mult": 1.2, "kind": "int", "back": true, "morale": 3.0},      # 오소를 알린 허유
	"omen": {"n": "점괘", "every": 3, "mult": 0.9, "kind": "int", "foe": {"stat": "def", "amt": -0.1, "dur": 2}},
	"proclaim": {"n": "격문", "every": 4, "mult": 0.7, "kind": "int", "morale": 6.0},                 # 원소를 위해 쓴 진림의 격문
	"remonstrate": {"n": "간언", "every": 3, "mult": 0.9, "kind": "int", "morale": 3.0, "foe": {"stat": "def", "amt": -0.08, "dur": 2}},
	"diplomacy": {"n": "설득", "every": 3, "mult": 0.6, "kind": "int", "foe": {"stat": "atk", "amt": -0.08, "dur": 2}},   # 손유 동맹 · 거짓 항복서
	"supply": {"n": "군량 보급", "every": 3, "mult": 0.5, "mend": 0.02, "cheer": 3.0},
	"recommend": {"n": "인재 천거", "every": 3, "mult": 0.6, "cheer": 6.0},                          # 순욱 · 수경 선생
	"zither": {"n": "금음", "every": 3, "mult": 0.6, "kind": "int", "cheer": 5.0, "foe": {"stat": "spd", "amt": -0.06, "dur": 2}},   # 이교의 거문고 · 호가십팔박
	"heal_bone": {"n": "괄골요독", "every": 3, "mult": 0.4, "mend": 0.03},                           # 관우의 뼈를 긁어 독을 뺀 화타
	"benevolence": {"n": "인의", "every": 3, "mult": 0.6, "mend": 0.015, "cheer": 6.0},
	# 11/5 2차 —— 위압 · 방벽 · 유언비어 묶음도 나눈다
	"rescue": {"n": "주군 호위", "every": 3, "mult": 1.1, "kind": "phys", "mend": 0.01, "cheer": 3.0},                       # 몸에 상처 열두 곳 —— 손권을 구한 주태 · 능통
	"sword_dance": {"n": "검무", "every": 3, "mult": 1.2, "kind": "phys", "extra": 0.4},                                     # 칼 찬 시녀를 거느린 손상향
	"hefei": {"n": "합비 돌격", "every": 4, "mult": 1.6, "kind": "phys", "back": true, "morale": 5.0},                       # 팔백 기로 십만을 친 장료
	"divine_bow": {"n": "신궁", "every": 3, "mult": 1.6, "kind": "phys", "back": true},                                      # 태사자의 활
	"forced_march": {"n": "질풍 급습", "every": 3, "mult": 1.3, "kind": "phys", "self": {"stat": "spd", "amt": 0.12, "dur": 2}},   # 사흘에 오백 리, 엿새에 천 리
	"hold_fort": {"n": "농성", "every": 3, "mult": 0.9, "self": {"stat": "def", "amt": 0.15, "dur": 2}},                     # 진창의 학소 · 번성의 조인 · 업성의 심배
	"repeat_xbow": {"n": "연노", "every": 3, "mult": 0.8, "kind": "phys", "extra": 0.6},                                     # 황월영의 연노
	"old_general": {"n": "노익장", "every": 3, "mult": 1.5, "kind": "phys", "self": {"stat": "atk", "amt": 0.08, "dur": 2}},     # 늙어서 더 굳센 황충 · 정보
	"trap_camp": {"n": "함진영", "every": 3, "mult": 1.5, "kind": "phys", "foe": {"stat": "def", "amt": -0.08, "dur": 2}},      # 고순의 함진영 —— 치면 반드시 깨뜨린다
	"discipline": {"n": "엄정한 군율", "every": 3, "mult": 1.1, "kind": "phys", "self": {"stat": "def", "amt": 0.08, "dur": 2}, "foe": {"stat": "atk", "amt": -0.05, "dur": 2}},   # 주아부에 비긴 서황 · 우금의 군기
	"multitude": {"n": "하북 대군", "every": 3, "mult": 1.0, "kind": "phys", "cheer": 4.0},
	"imperial_seal": {"n": "전국옥새", "every": 4, "mult": 0.8, "kind": "int", "cheer": 4.0, "morale": 3.0},                 # 옥새를 쥐고 황제를 칭한 원술
	"bodyguard": {"n": "쌍철극", "every": 3, "mult": 1.4, "kind": "phys", "self": {"stat": "def", "amt": 0.1, "dur": 2}},      # 조조를 지킨 악래 전위
	"eye": {"n": "발시담정", "every": 4, "mult": 1.5, "kind": "phys", "morale": 5.0, "self": {"stat": "atk", "amt": 0.1, "dur": 2}},   # 화살 박힌 눈을 삼킨 하후돈
	"bare": {"n": "나의 출전", "every": 3, "mult": 1.7, "kind": "phys", "self": {"stat": "def", "amt": -0.08, "dur": 2}},     # 갑옷을 벗고 마초와 싸운 허저
	"sow": {"n": "이간계", "every": 5, "mult": 0.7, "kind": "int", "st": ["confuse", 1.0, 1], "morale": 3.0},               # 마초와 한수를 갈라놓은 가후
	"taoist_book": {"n": "태평요술", "every": 3, "mult": 1.2, "kind": "int", "foe": {"stat": "def", "amt": -0.06, "dur": 2}},
	"haunt": {"n": "원혼", "every": 4, "mult": 1.0, "kind": "int", "morale": 4.0, "foe": {"stat": "def", "amt": -0.08, "dur": 2}},   # 손책을 괴롭힌 우길의 혼
	"yellow": {"n": "창천이사", "every": 5, "mult": 0.8, "kind": "int", "st": ["confuse", 1.0, 1], "morale": 4.0},          # 푸른 하늘은 이미 죽었다
	"ten_ambush": {"n": "십면매복", "every": 4, "mult": 1.0, "kind": "int", "back": true, "morale": 4.0},
	"plum": {"n": "망매지갈", "every": 3, "mult": 0.8, "kind": "int", "cheer": 6.0}}                                          # 매실 숲 이야기로 목마름을 잊게 한 조조
const MINOR_PERSON := {
	"하후패": "vanguard", "안량": "vanguard", "오의": "vanguard", "한당": "vanguard", "반장": "vanguard", "오반": "vanguard", "곽회": "vanguard",
	"화웅": "duel", "문추": "duel", "마초": "duel", "조운": "lone_ride", "마대": "xiliang", "마등": "xiliang", "공손찬": "white_horse",
	"여포": "cleave", "손책": "conquer", "손권": "tiger",
	"정봉": "raid", "장흠": "raid", "주환": "raid", "여몽": "raid", "엄백호": "raid",
	"장연": "plunder", "장만성": "plunder", "관해": "plunder", "주창": "plunder", "장패": "plunder",
	"방덕": "last_stand", "고람": "last_stand", "기령": "last_stand", "관흥": "last_stand",
	"황조": "ambush_shot", "엄안": "ambush_shot", "장임": "ambush_shot", "왕평": "ambush_shot",
	"위연": "surprise", "장포": "surprise", "장합": "surprise",
	"이적": "plan", "유엽": "plan", "서서": "plan", "강유": "plan", "제갈각": "plan", "마속": "plan", "동소": "plan", "보즐": "plan",
	"허유": "secret", "맹달": "secret", "주건평": "omen", "우번": "omen", "진림": "proclaim", "공융": "proclaim", "전풍": "remonstrate",
	"제갈근": "diplomacy", "감택": "diplomacy", "마량": "diplomacy", "노숙": "diplomacy", "여범": "diplomacy",
	"미축": "supply", "간옹": "supply", "진군": "supply", "비의": "supply", "순욱": "recommend", "사마휘": "recommend",
	"대교": "zither", "소교": "zither", "채문희": "zither", "화타": "heal_bone", "유비": "benevolence",
	"관평": "last_stand", "능조": "vanguard", "능통": "rescue", "주태": "rescue", "손상향": "sword_dance", "여상": "volley",
	"장료": "hefei", "태사자": "divine_bow", "하후연": "forced_march", "학소": "hold_fort", "조인": "hold_fort", "이전": "hold_fort", "심배": "hold_fort",
	"황월영": "repeat_xbow", "황충": "old_general", "정보": "old_general", "고순": "trap_camp", "서황": "discipline", "우금": "discipline",
	"악진": "vanguard", "요화": "vanguard", "원소": "multitude", "원술": "imperial_seal", "장소": "remonstrate", "장완": "supply",
	"전위": "bodyguard", "하후돈": "eye", "허저": "bare", "가후": "sow", "관로": "omen", "초주": "omen", "남화노선": "taoist_book",
	"우길": "haunt", "장각": "yellow", "저수": "remonstrate", "정욱": "ten_ambush", "조조": "plum", "진궁": "plan"}
const MINOR_PHYS := {"fire": "fire_arrow", "rumor": "roar", "curse": "shatter", "thunder": "spark", "poison": "awe"}
const MINOR_AXIS := {"도트": "fire", "혼란": "rumor", "공깎": "poison", "둔화": "poison", "책략깎": "curse", "방깎": "curse",
	"인덕": "cheer", "사기": "cheer", "철벽": "guard"}
const MINOR_TAG := {"창병": "thrust", "기병": "lance", "궁병": "volley", "도적": "ambush", "책사": "fire", "유생": "cheer",
	"술사": "thunder", "모사": "rumor"}
static var _minor_cache := {}
var _minor_nm := ""
var _minor_mk := ""


## 이 카드의 잔기술 종류 —— 특기 축(카드 등급에서 열린 첫 축) → 병종. 술사의 책략깎 · 방깎은 낙뢰, 도적이 책략형이면 단도
static func minor_kind(k: String) -> String:
	if _minor_cache.has(k):
		return _minor_cache[k]
	var c: Dictionary = DB.C[k]
	var out := ""
	if c.tier >= 3 and MINOR_PERSON.has(DB.person(k)):
		out = MINOR_PERSON[DB.person(k)]
	elif c.tier >= 3:
		for e in DB.PSV.ladder.get(DB.person(k), []):
			if c.tier < int(e[1]) or (e.size() > 2 and c.tier > int(e[2])):
				continue
			var a: String = DB.PSV.traits.get(e[0], {}).get("attr", "")
			if MINOR_AXIS.has(a):
				out = MINOR_AXIS[a]
				break
		if out == "":
			out = MINOR_TAG.get(c.tag, "")
		if out == "curse" and c.tag == "술사":
			out = "thunder"
		if out == "ambush" and is_caster(c):
			out = "dagger"
		if MINOR_PHYS.has(out) and not is_caster(c):      # 무장은 책략 잔기술 대신 무력판 (책략 0 이면 피해가 1 이었다)
			out = MINOR_PHYS[out]
	_minor_cache[k] = out
	return out


## 잔기술 정의 —— 축 · 병종 잔기술(MINOR) 또는 인물 잔기술(MINOR_STORY)
static func minor_def(mk: String) -> Dictionary:
	return MINOR[mk] if MINOR.has(mk) else MINOR_STORY.get(mk, {})


## 이번 평타가 잔기술인가 —— [정의, 종류] 또는 []
func _minor(u: Unit) -> Array:
	if not minor_enabled or has_st(u, "seal"):
		return []
	var mk := minor_kind(u.c.id)
	if mk == "":
		return []
	var m: Dictionary = minor_def(mk)
	if u.minor_n < 0:
		u.minor_n = u.slot % int(m.every)      # 부대마다 차례를 어긋나게
	u.minor_n += 1
	if u.minor_n < int(m.every):
		return []
	u.minor_n = 0
	return [m, mk]


## 잔기술 한 번 —— 타격(대상은 back 이면 적 후열) + 덧붙임. 상태이상은 inflict(저항 판정 · 기록 포함)
func _do_minor(u: Unit, t: Unit, m: Dictionary, mk: String, foes: Array, allies: Array) -> void:
	if m.get("back", false):
		var bt := resolve_targets("back1", foes, u, allies)
		if not bt.is_empty() and bt[0].alive:
			t = bt[0]
	var phys: bool = (m.kind == "phys") if m.has("kind") else not is_caster(u.c)
	var tl := clampf(0.8 + 0.1 * (u.c.tier - 3), 0.8, 1.3)      # 등급이 높을수록 조금 세게
	_minor_nm = m.n
	_minor_mk = mk
	if phys: phys_hit(u, t, float(m.mult) * tl)
	else: int_hit(u, t, float(m.mult) * tl, 1)
	_minor_nm = ""
	_minor_mk = ""
	if m.has("self"):
		u.buffs.append({"stat": m.self.stat, "amt": float(m.self.amt), "dur": int(m.self.dur)})
	if t.alive:
		if m.has("st"):
			var st: Array = m.st
			inflict(u, t, st[0], float(st[1]) * (1.0 if st[0] == "confuse" else tl), int(st[2]))
		if m.has("foe"):
			t.buffs.append({"stat": m.foe.stat, "amt": float(m.foe.amt), "dur": int(m.foe.dur)})
		if m.has("morale"):
			t.morale = maxf(0.0, t.morale - float(m.morale))
		if m.has("extra"):
			if phys: phys_hit(u, t, float(m.extra) * tl, true)
			else: int_hit(u, t, float(m.extra) * tl, 1)
	if m.has("cheer") or m.has("mend"):
		var low: Unit = null
		for o in allies:
			if o.alive and (low == null or o.troops / o.max < low.troops / low.max):
				low = o
		if low != null:
			if m.has("cheer"):
				low.morale = minf(200.0, low.morale + float(m.cheer))
			if m.has("mend") and not _scorched(low):
				low.troops = minf(low.max, low.troops + roundf(low.max * float(m.mend)))


static var strat_aura_enabled := false     # 11/4 사용자: 밸런스는 나중에 —— 꺼 둔다
const STRAT_TAGS := ["책사", "모사"]
const STRAT_AURA_DEF := 0.05      # 방어 +5% (11/7 방어 0.04 · 책략방어 0.05 를 큰 값 하나로)
func _strat_step() -> void:
	if not strat_aura_enabled:
		return
	for u in units:
		u.strat_aura = 0.0
		if not u.alive:
			continue
		var n := 0
		for o in units:
			if o.alive and o.camp == u.camp and STRAT_TAGS.has(o.c.tag) and (o == u or _same_line(o, u)):
				n += 1
		u.strat_aura = 0.0 if n == 0 else (1.0 if n == 1 else 1.6)


static func _sv_m(d: Dictionary, k: String) -> float:
	return float(d.get(k, 0.0)) + (float(d.get(MV_ALIAS[k], 0.0)) if MV_ALIAS.has(k) else 0.0)


## 위세 (신화 · 초월) —— 살아 있는 장수마다 아군 전체(ally, tag 가 있으면 그 병종만) · 적 전체(foe) 배율
func _aura_mul(u: Unit, stat: String) -> float:
	var m := 1.0
	for mu in _myths:
		if not mu.alive:
			continue
		var a: Dictionary = DB.AURA[mu.c.id]
		var mc := _acamp(mu)
		var h := 0.5 if _kv(_foe(mc), "aura_half") else 1.0      # 연합 노숙 —— 적 위세 절반
		if mc == u.camp:
			if a.has("ally") and not _no_ally(u) and _aura_on(mu, a, u):
				m *= 1.0 + _sv(a.ally, stat) * h
		elif a.has("foe") and _aura_foe_on(a, u):
			m *= 1.0 + _sv(a.foe, stat) * h
	return m


## 위세가 이 아군에게 닿는가 —— to: all · front · back · fac · rel · low · tag (11/2 (6))
func _aura_on(mu: Unit, a: Dictionary, u: Unit) -> bool:
	match a.get("to", "all"):      # 전열 · 후열은 진형 칸의 열 (11/3 사용자 —— 거리 판정은 맞붙기 전 전원이 후열이 된다)
		"front": return pri(u) <= 2
		"back": return pri(u) >= 3
		"fac": return u.c.fac == mu.c.fac
		"rel": return u == mu or a.rel.has(DB.person(u.c.id))
		"low": return u.troops < u.max * 0.5
		"tag": return u.c.tag == a.tag
	return not a.has("tag") or u.c.tag == a.tag


## 위세가 이 적에게 닿는가 —— foe_to: all · front · back · tag:병종
func _aura_foe_on(a: Dictionary, u: Unit) -> bool:
	var ft: String = a.get("foe_to", "all")
	if ft == "front": return pri(u) <= 2
	if ft == "back": return pri(u) >= 3
	if ft.begins_with("tag:"): return u.c.tag == ft.substr(4)
	return true


const DROWN_SOAK := 0.2              # 수엄칠군 장수의 침수 확률 (스스로 수몰을 건다)
static var probe_on := false           # 점검용 (tests/trait_probe) —— mv 로 읽힌 특기 효과 키를 센다
static var probe := {}

func mv(u: Unit, k: String) -> float:
	var v: float = u.m.get(k, 0.0) + (float(u.m.get(MV_ALIAS[k], 0.0)) if MV_ALIAS.has(k) else 0.0)      # 11/6 #15 책략 전용 키를 합친다
	if probe_on and v != 0.0:
		probe[k] = int(probe.get(k, 0)) + 1
	if not _aura_m.is_empty():
		for mu in _aura_m:
			if mu.alive and _acamp(mu) == u.camp and not _no_ally(u):
				var a: Dictionary = DB.AURA[mu.c.id]
				if (a.m.has(k) or (MV_ALIAS.has(k) and a.m.has(MV_ALIAS[k]))) and _aura_on(mu, a, u):
					v += _sv_m(a.m, k) * (0.5 if _kv(_foe(_acamp(mu)), "aura_half") else 1.0)
	return v


func has_st(u: Unit, k: String) -> bool:
	return u.st.any(func(s): return s.k == k)


func sk_rate(u: Unit) -> float:
	if has_st(u, "seal"):
		return 0.0
	var r: float = DB.D.RATE.get(str(u.c.tier), 0.0)
	if u.item:
		r += DB.IT[u.item].rb / 100.0 * (MYTH_AMP if is_signature(u) else 1.0)
	if u.ts and u.ts.stat == "rate": r += u.ts.v
	if u.boon and u.boon.stat == "rate": r += u.boon.v
	return r + mv(u, "rate")


## 사기 —— 모든 능력치(공격 · 방어 · 책략 · 책방 · 속도)에 곱한다 (2026-10-30 사용자 결정). 사기 0 → 0.6배, 100 → 1배, 200 → 1.4배.
## 예전(원본)은 주는 피해에만 0.5 + 사기/200 을 곱했다. 사기 30 이하에서 패주를 굴리는 것은 그대로
static var morale_w := 0.4

func morale_mul(u: Unit) -> float:
	return 1.0 + morale_w * (clampf(u.morale, 0, 200) - 100.0) / 100.0


func m_mul(_u: Unit) -> float:
	return 1.0


func morale_guard(atk: Unit, def: Unit) -> float:
	if atk == null or def.c.tier < K.guardFrom:
		return 1.0
	var gap: int = def.c.tier - atk.c.tier
	return 1.0 if gap <= 0 else maxf(0.18, pow(K.guard, gap))


# ───────── 대상 선정 ─────────

func pri(u: Unit) -> int:
	return int(DB.D.LINE[u.line].pri)


# ───────── 열 판정 —— 턴 엔진은 진형의 열, 실시간 엔진(RtBattle)은 거리로 바꿔 쓴다 (10/31 사용자: 특기를 거리 기준으로) ─────────

## 거리로 판정하는 엔진인가 (실시간 엔진이 true)
func _by_distance() -> bool:
	return false


## 같은 열 이웃인가 (번짐 · 휩쓸기 · 반간 · 독전 · 패주 충격)
func _same_line(a: Unit, b: Unit) -> bool:
	return a.line == b.line


## 앞쪽 묶음 / 뒤쪽 묶음 (us 는 한 진영의 살아 있는 유닛들)
func _front_of(us: Array) -> Array:
	if us.is_empty(): return []
	var mn: int = us.map(pri).min()
	return us.filter(func(o): return pri(o) == mn)


func _back_of(us: Array) -> Array:
	if us.is_empty(): return []
	var mx: int = us.map(pri).max()
	return us.filter(func(o): return pri(o) == mx)


## 앞에 섰나 / 뒤에 섰나 (전방 공격 · 후방 책략 특기)
func _is_front(u: Unit) -> bool:
	return pri(u) <= 2


func _is_back(u: Unit) -> bool:
	return pri(u) >= 3


## 가장 빽빽한 무리의 수 (기술 조건 dense)
func _dense_max(us: Array) -> int:
	var g := {}
	for o in us:
		g[o.line] = g.get(o.line, 0) + 1
	return 0 if g.is_empty() else int(g.values().max())


func resolve_targets(spec: String, foes: Array, me: Unit, allies: Array) -> Array:
	if spec == "self": return [me]
	if spec == "allyAll": return allies.filter(func(u): return u.alive)
	if spec == "allyFront":
		var al := allies.filter(func(u): return u.alive)
		if al.is_empty(): return []
		var p: int = al.map(pri).min()
		return al.filter(func(u): return pri(u) == p)
	var live := foes.filter(func(u): return u.alive)
	if live.is_empty(): return []
	var ps := live.map(pri)
	var mn: int = ps.min()
	var mx: int = ps.max()
	var front := live.filter(func(u): return pri(u) == mn)
	var back := live.filter(func(u): return pri(u) == mx)
	match spec:
		"front1": return [pick(front)]
		"back1": return [pick(back)]
		"back2":
			var s := live.duplicate()
			s.sort_custom(func(a, b): return pri(a) > pri(b))
			return s.slice(0, 2)
		"front3":
			var s := live.duplicate()
			s.sort_custom(func(a, b): return pri(a) < pri(b))
			return s.slice(0, 3)
		"all": return live
		"denseLine":
			var g := {}
			for u in live:
				if not g.has(u.line): g[u.line] = []
				g[u.line].append(u)
			var best: Array = []
			for l in g:
				if g[l].size() > best.size(): best = g[l]
			return best
	if spec.begins_with("line:"):
		var want := spec.substr(5).split("+")
		var m := live.filter(func(u): return want.has(u.line))
		return m if not m.is_empty() else front
	return front


func basic_target(u: Unit, foes: Array) -> Array:
	var back: bool = (u.c.tag == "궁병" and (u.caps.has("궁병") or DB.aff_of(u.c.tag, u.line, u.side) == "pref")) 		or u.c.tag == "도적" or is_caster(u.c)
	return resolve_targets("back1" if back else "front1", foes, u, [])


# ───────── 로그 ─────────

func L(cls: String, text: String, extra: Dictionary = {}) -> void:
	var snap := []
	for u in units:
		snap.append([maxi(0, roundi(u.troops)), roundi(u.morale), 1 if u.alive else 0, _shown_st(u),
			int(u.gauge), u.charges])     # 내림 —— 100 은 정말 다 찼을 때만
	var e := {"c": cls, "t": text, "s": snap, "ai": _ai, "ph": _ph, "who": _who, "turn": _turn, "tm": snappedf(_tm, 0.01),
		"an": act_n, "pts": [pts.A, pts.B], "bd": _bdone == act_n}
	e.merge(extra)
	if _minor_nm != "" and (e.get("fx") == "phys" or e.get("fx") == "int"):      # 잔기술 이름 · 종류는 그 타격 사건에
		e["mn"] = _minor_nm
		e["mk"] = _minor_mk
		_minor_nm = ""
	ev.append(e)


static func num(v: float) -> String:
	var s := str(roundi(v))
	var out := ""
	var neg := s.begins_with("-")
	if neg: s = s.substr(1)
	for i in s.length():
		if i > 0 and (s.length() - i) % 3 == 0: out += ","
		out += s[i]
	return ("-" if neg else "") + out


# ───────── 타격 ─────────

func phys_hit(a: Unit, d: Unit, mult: float, no_counter := false, pierce := 0.0) -> void:
	if d.caps.has("도적") and d.c.tag == "도적" and rng.randf() < 0.45:
		L("mo", "%s 몸을 틀어 흘려냈다" % ga(nm(d)), {"fx": "dodge", "a": a.key, "f": d.key})
		return
	var A := eff(a, "atk")
	var Dv := eff(d, "def")
	if pierce > 0: Dv *= (1 - pierce)
	Dv *= 1.0 - mv(a, "rpierce")
	if a.ts and a.ts.stat == "brk": Dv *= (1 - a.ts.v)
	var crit: bool = rng.randf() < DB.PSV.base_crit + mv(a, "crit")
	var cm: float = (DB.PSV.base_critd + mv(a, "critd")) if crit else 1.0
	var op := 1.0 if a.opens >= roundi(turn_mul) else 1.0 + mv(a, "opener")
	a.opens += 1
	var dmg := A * (A / (A + Dv)) * m_mul(a) * rnd(0.9, 1.1) * mult * cm * op * (1.0 - mv(d, "dr")) * _amp_once(a)
	if shield_enabled:
		dmg *= 1.0 - _shield(d, dmg_kind(a))      # 11/8 갑옷 · 결계 —— 피해 종류는 때리는 장수의 병종 (평타 · 기술 · 고유기 · 잔기술 · 반격 모두 여기로 온다)
	if d.troops / d.max <= 0.5:
		dmg *= 1.0 + mv(a, "int_low")          # 기책 —— 병력 절반 아래인 적에게
	if a.in_skill:
		dmg *= 1.0 + mv(a, "sk_amp")           # 신산 —— 기술 피해
	dmg *= 1.0 - _guard(a, d)
	dmg *= _omen_mul(a, d)      # 제갈량 천문
	if _in_ult:
		dmg *= (1.0 - _buff_sum(d, "uguard")) * (0.0 if _ult_null else 1.0)
	var fm := _fire_mul(a, d)
	var wm := 1.0
	var tm := _tac_mul(a, d)
	var sm := _scheme_mul(a, d)
	if _phalanx(d):
		dmg *= 1.0 - float(DB.PSV.guard.dr)        # 방진 —— 받는 물리 피해 감소
	dmg *= fm * wm * tm * sm * (DB.cls_mul(a.c.tag, d.c.tag, a.c.tier) if counter_enabled else 1.0)
	dmg *= _role_mul(a, d, true)
	var loss := _stand(d, _kiin_guard(d, maxf(1, roundf(dmg * K.troop * pace * _one))))
	if _in_ult and _ult_by != null and not ult_cap.is_empty():
		loss = _ult_clamp(d, loss)
	if tag_roles and a.c.tag == "도적" and not a.countering:      # 도적 —— 맞힌 적의 고유기 게이지 · 기술 충전을 깎는다
		d.gauge = maxf(0.0, d.gauge - ROLE.rogue_gauge)
		if not d.sk_ch.is_empty():
			d.sk_ch[0] = maxf(0.0, d.sk_ch[0] - ROLE.rogue_charge)
	stats.tac_amp += loss * (1.0 - 1.0 / tm)
	stats.scheme_amp += loss * (1.0 - 1.0 / sm)
	if a.countering:
		stats.counter_dmg += loss
	if not _in_ult:
		if _hit_kind == "int": stats.intd += loss
		else: stats.phys += loss
		if _phalanx(d): stats.ph_taken += loss
	stats.fire_amp += loss * (1.0 - 1.0 / fm)
	stats.water_amp += loss * (1.0 - 1.0 / wm)
	_stat(d, loss)
	d.troops -= loss
	a.dmg += loss
	d.last_hit = a
	_charge(d, a, loss)
	_paeup_snipe(a, d)
	L(a.camp, "%s%s %s %s — 병력 %s 손실" % ["치명타! " if crit else "", ga(nm(a)), eul(nm(d)), "쳤다" if _hit_kind == "int" else "들이쳤다", num(loss)],
		{"fx": _hit_kind, "a": a.key, "f": d.key, "n": loss, "crit": crit, "fire": fm > 1.0, "water": wm > 1.0})
	_ignite(a, d)
	_soak(a, d)
	_wash(a)
	_tac_hit(a, d, true)
	_after_hit(a, d)
	_cleave(a, d, mult, true)
	if not no_counter and d.alive:
		var stance = null
		for b in d.buffs:
			if b.stat == "counter": stance = b
		var ph := _phalanx(d)
		var p: float = (0.70 if d.caps.has("창병") and d.c.tag == "창병" else 0.0) + (stance.amt if stance else 0.0) + mv(d, "counter")
		if ph:
			p += float(DB.PSV.guard.counter)           # 방진 —— 반격 확률 +
		if p > 0 and rng.randf() < p:
			L("sk", "%s 창을 되받아 찔렀다" % ga(nm(d)), {"fx": "buff", "f": d.key})
			var cmul := 1.28
			if ph:
				cmul *= 1.0 + float(DB.PSV.guard.amp)       # 방진 —— 반격 피해 +
			if guard_enabled:
				cmul *= 1.0 + mv(d, "counter_hit") + (mv(d, "phalanx_amp") if ph else 0.0)     # 반격(즉발) · 역습
			stats.counters += 1
			_chain(d.camp, "반격", d.key)
			d.countering = true
			phys_hit(d, a, cmul, true)
			d.countering = false
			if ph and mv(d, "phalanx_break") > 0 and a.alive:            # 일신시담 —— 방진 중 되받아치면 적 방어를 크게 깎는다
				if shield_enabled:
					_shred(d, a, "phys", _shred_v(d) * _gv("shred_big", 1.5), int(_gv("shred_dur", 3)), "일신시담")      # 11/8 갑옷을 크게 벗긴다
				else:
					_cut(d, a, "def", 0.15 * d.c.atk, "일신시담")


func int_hit(a: Unit, d: Unit, mult: float, spread: int) -> void:
	# 11/6 사용자 #15: 책략 피해 경로를 없앤다 —— 계산은 phys_hit 와 같다 (공격 vs 방어). 범위(aoe) · 반격 없음 · 반목(sow)만 남긴다.
	# 사건 종류는 "int" 로 남겨 화면이 책략 연출(보랏빛 숫자 · 투사체)을 그대로 쓴다
	_hit_kind = "int"
	phys_hit(a, d, mult * (K.aoe if spread >= 3 else 1.0), true, 0.0)
	_hit_kind = "phys"
	if scheme_enabled and d.alive and d.troops > 0 and mv(a, "sow") > 0 and rng.randf() < mv(a, "sow"):     # 반목 —— 책략이 맞으면 혼란
		stats.confuses += 1
		_chain(a.camp, "반목", a.key)
		inflict(a, d, "confuse", 1, int(DB.PSV.scheme.dur))


var _hit_kind := "phys"      # phys_hit 가 기록할 사건 종류 (int_hit 가 바꾼다)


# ───────── 11/8 피해 두 갈래 · 갑옷 · 결계 · 깎기 (docs/역할_재설계_1108.md 3장) ─────────

## 피해 종류 —— 때리는 장수의 병종 ("phys" 물리 · "int" 책략). 기술의 kind · _hit_kind 는 연출에만
func dmg_kind(u: Unit) -> String:
	return DB.dmg_kind(u.c.tag)


## 받는 쪽의 막 —— 병종(또는 우두머리 성질) 막 − 걸린 깎기, 0 ~ cap
func _shield(d: Unit, k: String) -> float:
	var s: Dictionary = d.shred[k]
	return clampf(float(d.shield[k]) - (float(s.v) if int(s.t) > 0 else 0.0), 0.0, _gv("cap", 0.75))


static func _gv(k: String, dflt: float) -> float:
	return float(DB.GUARD.get(k, dflt))


## 병종 배율 —— 점검 덮어쓰기 → class_guard 순으로 찾고 없으면 1. 값이 등급표면 그 등급 값
static func class_tune(key: String, tag: String, tier: int) -> float:
	var v = tune_over.get(key, {}).get(tag, DB.GUARD.get(key, {}).get(tag, 1.0))
	if v is Dictionary:
		return float(v.get(str(tier), 1.0))
	return float(v)


## 깎는 양 —— 장수 등급표 (1단계는 등급만, 장수별 레벨 차이는 2단계). 11/9 기인은 기인 값 (DB.shred_val)
static func _shred_v(a: Unit) -> float:
	return DB.shred_val(a.c.id)


## 갑옷(k = "phys") · 결계("int") 깎기 —— 대상마다 종류별 가장 센 하나. 난수를 쓰지 않는다.
## 지금 걸린 값 이하면 다른 출처는 무시(같은 값은 먼저 건 것 유지), 같은 출처는 남은 턴만 갱신. 더 크면 바꿔 끼운다 (출처 a.key —— 기여 계산용)
func _shred(a: Unit, d: Unit, k: String, v: float, dur: int, why: String) -> void:
	if not cut_enabled or not d.alive or v <= 0.0 or dur <= 0:
		return
	var s: Dictionary = d.shred[k]
	if int(s.t) > 0 and v <= float(s.v):
		if s.by == a.key:
			s.t = maxi(int(s.t), dur)
		return
	s.v = v
	s.t = dur
	s.by = a.key
	stats.shreds += 1
	if float(d.shield[k]) > 0.0:      # 막이 없는 적은 기록만 줄인다 (걸린 것은 같다)
		L("st", "『%s』 %s의 %s −%d%%" % [why, nm(d), "갑옷" if k == "phys" else "결계", roundi(v * 100)],
			{"fx": "debuff", "f": d.key, "st": "shred_" + k, "n": v})


## 깎기 남은 턴 —— 턴 끝마다 (실시간 엔진은 period 마다) tick_status 가 부른다
func _shred_tick() -> void:
	if not shield_enabled:
		return
	for u in units:
		for k in u.shred:
			if int(u.shred[k].t) > 0:
				u.shred[k].t = int(u.shred[k].t) - 1

## 병종 역할 배율 (tag_roles) —— 준 피해에 곱한다
func _role_mul(a: Unit, d: Unit, phys: bool) -> float:
	if not tag_roles:
		return 1.0
	var g := 1.0
	if phys and INT_TAG.has(d.c.tag):      # 책략계는 물리에 덜 맞는다 (후열이 먼저 무너져 3장 덱 승률 21~42%) —— 11/5 책사도 (생존 26~33%)
		g = ROLE.int_guard
	if a.c.tag == "기병":
		g *= ROLE.horse_all
	return _role_tag(a, d, phys) * g * class_tune("dmg", a.c.tag, a.c.tier) * class_tune("taken", d.c.tag, d.c.tier) * _engage_mul(a, d)      # 11/6 #15 책략 전용 배율(INT_LOW · strat_int …)은 쓰지 않는다 —— 피해 경로가 하나. 11/8 병종 배율


## 11/8 맞붙음 상성 —— 실제 자리에서 생기는 상성 (묶인 원거리 · 창병 정면의 도적 · 묶이지 않은 후열을 노리는 도적). 자리가 없는 턴제 엔진은 1, 실시간 엔진(RtBattle)이 덮어쓴다
func _engage_mul(_a: Unit, _d: Unit) -> float:
	return 1.0


## 11/8 맞붙음 · 지원 값 (class_guard.engage) —— 점검 덮어쓰기(tune_over.engage) 먼저
static func engage_v(k: String, dflt: float) -> float:
	return float(tune_over.get("engage", {}).get(k, DB.GUARD.get("engage", {}).get(k, dflt)))


## 11/8 지원 병종 등급 성장 —— 유생 치료 · 모사 사기 깎기가 등급마다 class_guard.sup[병종] 씩 커진다 (전설 = 1, 등급표 없이 한 값)
static func sup_mul(tag: String, tier: int) -> float:
	var step := float(tune_over.get("sup", {}).get(tag, DB.GUARD.get("sup", {}).get(tag, 0.0)))
	return maxf(0.5, 1.0 + step * (tier - 5))


func _role_tag(a: Unit, d: Unit, phys: bool) -> float:
	match a.c.tag:
		"창병":
			return SPEAR_ATK.get(a.c.tier, 0.6)
		"기병":
			if phys and not a.charged and not a.countering:
				a.charged = true
				if _kv(d.camp, "no_charge"):       # 함진 고순 —— 적 기병 첫 돌격 막음
					return ROLE.horse_after
				return CHARGE.get(a.c.tier, ROLE.charge) * (1.5 if _kv(a.camp, "charge_up") else 1.0)      # 서량 마등
			return ROLE.horse_after
		"궁병":
			if units.any(func(o): return o.alive and o.camp == a.camp and o.c.tag == "창병"):
				return ROLE.bow_cover
		"도적":      # 11/8 후열 가산(rogue_vs_int 1.7 · rogue_vs_bow 1.3)은 맞붙음 상성(engage.rogue_free —— 묶이지 않은 후열)과 병종 상성표로 합쳤다
			return ROLE.rogue_all
		"책사":
			if not phys: return ROLE.strat_int * STRAT_HI.get(a.c.tier, 1.0)
		"모사":
			if not phys: return ROLE.schem_int
		"술사":
			if not phys: return ROLE.occul_int
		"유생":
			if not phys: return ROLE.schol_int
	return 1.0


func morale_hit(d: Unit, amt: float, who: String, spread: int, src: Unit) -> void:
	var a: float = amt * pace * _one * (K.aoe if spread >= 3 else 1.0) * morale_guard(src, d)
	if tag_roles and src and src.c.tag == "모사": a *= ROLE.schem_morale * sup_mul("모사", src.c.tier)      # 11/8 지원 등급 성장
	if src: a *= 1.0 + mv(src, "mdeal")
	a *= 1.0 - mv(d, "mshield")
	d.morale -= a
	if src: src.mdmg += a
	L("mo", "『%s』에 %s의 군세가 술렁인다 — 사기 %d 감소" % [who, nm(d), roundi(a)],
		{"fx": "morale", "f": d.key, "m": a})


func heal_troop(d: Unit, ratio: float, who: String, src: Unit) -> void:
	if not d.alive or _scorched(d): return
	if _no_ally(d) and src != d: return      # 여포 무쌍 —— 아군의 치료를 받지 않는다
	if virtue_enabled and _side_max(_foe(d.camp), "starve") > 0:
		ratio *= 1.0 - float(DB.PSV.virtue.starve)      # 단량 —— 적이 군량을 끊었다
	if _kv(_foe(d.camp), "heal_cut"):      # 흑산 장연 —— 적 회복 −50%
		ratio *= 0.5
	if tag_roles and src:      # 치료는 유생 전담 (술사는 상태이상)
		ratio *= ROLE.schol_heal * sup_mul("유생", src.c.tier) if src.c.tag == "유생" else (ROLE.occul_heal if src.c.tag == "술사" else 1.0)      # 11/8 지원 등급 성장
	var g := minf(roundf(d.max * ratio * pace * _one), d.max - d.troops)
	if g <= 0: return
	d.troops += g
	if src:
		src.heal += g / 300.0
		src.theal += g / d.max      # 점검용 —— 병력 치료만 (최대 병력 대비)
	L("hl", "『%s』에 %s의 대오가 정비된다 — 병력 +%s" % [who, nm(d), num(g)],
		{"fx": "heal", "f": d.key, "n": g})
	if virtue_enabled and _side_max(d.camp, "moved") > 0:
		_give_moved(d)


func heal_morale(d: Unit, amt: float, who: String, src: Unit) -> void:
	if _no_ally(d) and src != d: return      # 여포 무쌍
	var b := d.morale
	d.morale = minf(200, d.morale + amt * pace * _one)
	var g := d.morale - b
	if src and g > 0: src.heal += g
	if g > 0.5:
		L("hl", "『%s』에 %s의 군세가 다시 일어선다 — 사기 +%d" % [who, nm(d), roundi(g)],
			{"fx": "heal", "f": d.key, "m": g})


func add_buff(u: Unit, b: Dictionary) -> void:
	if _no_ally(u) and b.amt > 0 and not u.in_skill and not (_in_ult and _ult_by == u): return      # 여포 무쌍 —— 아군이 거는 버프를 받지 않는다
	u.buffs.append({"stat": b.stat, "amt": float(b.amt), "dur": roundi(int(b.dur) * _long)})
	var up: bool = b.amt > 0
	L("sk", "%s의 %s %s · %s%d%%" % [nm(u), ga(DB.D.STATNM.get(b.stat, b.stat)), "올랐다" if up else "꺾였다",
		"+" if up else "", roundi(b.amt * 100)], {"fx": "buff", "f": u.key, "up": up})


func inflict(a: Unit, d: Unit, kind: String, val: float, dur: int) -> void:
	if not d.alive: return
	if mv(d, "stres") > 0 and rng.randf() < mv(d, "stres"):
		L("st", "%s 『%s』%s 버텨냈다" % [ga(nm(d)), DB.D.STATUS[kind].n, "을" if jong(DB.D.STATUS[kind].n) else "를"],
			{"fx": "resist", "f": d.key, "st": kind})
		return
	var stx: float = (1 + a.ts.v) if a and a.ts and a.ts.stat == "stx" else 1.0
	if tag_roles and a and a.c.tag == "술사": stx *= ROLE.occul_status
	var ext := (1 if a and a.caps.has("책사") else 0) + (1 if a and a.caps.has("술사") else 0)
	var resist := 1.0 if a and a.caps.has("술사") else (morale_guard(a, d) if d.c.tier >= K.guardFrom else 1.0)
	var scale: float = d.max * pace if kind in ["burn", "flood", "bleed"] else (pace if kind == "plague" else 1.0)
	var fire := 1.0
	var sp := 0.0
	if kind == "burn":
		fire = _burn_mul(a, d)
		ext += int(mv(a, "burn_dur")) if a else 0
		sp = mv(a, "spread") if a else 0.0
	elif kind == "flood" and water_enabled:
		fire = 1.0 - minf(0.9, mv(d, "flood_res"))
	var amp := 1.0 + (mv(a, "st_amp") if a and kind in ["burn", "flood", "bleed", "plague"] else 0.0)     # 요술
	var cd := class_tune("dmg", a.c.tag, a.c.tier) if a and kind in ["burn", "bleed"] else 1.0      # 11/8 병종 배율 —— 지속 피해(화상 · 출혈)도 건 장수 병종의 준 피해 배율을 받는다
	var v := maxf(1, roundf(val * scale * stx * resist * fire * amp * cd))
	var t := roundi((maxi(dur, 1) + ext) * _long)
	if kind == "flood":
		_steam(d)
	var old = null
	for s in d.st:
		if s.k == kind: old = s
	if old:
		old.val = maxf(old.val, v)
		old.dur = maxi(old.dur, t)
		old.sp = maxf(old.get("sp", 0.0), sp)
	else:
		if d.st.size() >= _st_cap(d):
			var w = d.st[0]
			for s in d.st:
				if s.dur <= w.dur: w = s
			d.st.erase(w)
		d.st.append({"k": kind, "val": v, "dur": t, "sp": sp})
	L("st", "%s 『%s』에 걸렸다 — %d턴" % [ga(nm(d)), DB.D.STATUS[kind].n, t],
		{"fx": "status", "f": d.key, "st": kind})
	if temper_enabled and a and a.alive and a.camp != d.camp and not _in_ult:      # 11/7 지략 —— 상태이상을 걸 때마다 찬다
		_gauge_add(a, _tw(a, "status"))


func cleanse(u: Unit) -> bool:
	if u.st.is_empty(): return false
	var k: String = u.st.pop_front().k
	var sn: String = DB.D.STATUS[k].n
	L("hl", "%s의 『%s』%s 씻겼다" % [nm(u), sn, "이" if jong(sn) else "가"], {"fx": "cleanse", "f": u.key, "st": k})
	return true


func tick_status(frac := 1.0, final := true) -> void:
	var spreads := []
	var passes := []
	for u in units:
		if not u.alive or u.st.is_empty(): continue
		for s in u.st:
			match s.k:
				"burn":
					var bv: float = s.val * frac
					if scheme_enabled and has_st(u, "confuse") and _side_max(_foe(u.camp), "confuse_burn") > 0:
						u.troops -= bv          # 팔진화계 —— 혼란된 적의 화상이 두 배로 탄다
						stats.burn += bv
					u.troops -= bv
					stats.burn += bv
					var tr := _side_max(_foe(u.camp), "terror")
					if tr > 0:
						u.morale -= tr * pace * frac
						stats.terror += tr * pace * frac
					if s.get("sp", 0.0) > 0 and rng.randf() < 1.0 - pow(1.0 - float(s.sp), frac):
						spreads.append([u, s])
					if final:
						L("st", "%s 불길에 휩싸인다 — 병력 %s 손실" % [ga(nm(u)), num(s.val)], {"fx": "tick", "f": u.key, "st": "burn", "n": s.val})
				"flood":
					pass       # 둔화 —— 피해 없이 느려지기만 한다 (eff 의 _flood_slow)
				"bleed":
					u.troops -= s.val * frac
					if final:
						L("st", "%s의 상처가 벌어진다 — 병력 %s 손실" % [nm(u), num(s.val)], {"fx": "tick", "f": u.key, "st": "bleed", "n": s.val})
				"plague":
					u.morale -= s.val * frac
					if final:
						L("st", "%s의 군세에 역병이 돈다 — 사기 %d 감소" % [nm(u), roundi(s.val)], {"fx": "tick", "f": u.key, "st": "plague", "m": s.val})
		if not final:
			continue
		for s in u.st: s.dur -= 1
		for s in u.st:
			if s.k == "confuse" and s.dur <= 0 and not s.get("passed", false) and scheme_enabled \
					and _side_max(_foe(u.camp), "confuse_pass") > 0:
				passes.append(u)
		u.st = u.st.filter(func(s): return s.dur > 0)
	for sp in spreads:
		_spread_burn(sp[0], sp[1])
	if not final:
		return
	_shred_tick()      # 11/8 갑옷 · 결계 깎기
	for u in passes:                                  # 반간 —— 풀린 혼란이 같은 열 이웃에게 옮겨 간다 (한 번만)
		var cand := units.filter(func(o): return o.alive and o != u and o.camp == u.camp and _same_line(o, u) and not has_st(o, "confuse"))
		if cand.is_empty(): continue
		var t: Unit = cand[rng.randi() % cand.size()]
		stats.passes += 1
		_chain(_foe(u.camp), "반간")
		inflict(null, t, "confuse", 1, int(DB.PSV.scheme.dur))
		var c = _st_of(t, "confuse")
		if c: c.passed = true
	_drown()
	for cp in ["A", "B"]:
		var side := units.filter(func(u): return u.alive and u.camp == cp)
		if side.is_empty() or not side[0].caps.has("유생"): continue
		for u in side:
			if not u.st.is_empty():
				cleanse(u)
				break


# ───────── 화공 (솔국지 확장) ─────────

## 불타는 적을 칠 때 피해 배율 —— 공격자의 fire_amp, 대상의 fire_res 가 깎는다
func _fire_mul(a: Unit, d: Unit) -> float:
	if a == null or not fire_enabled:
		return 1.0
	var res := 1.0 - minf(1.0, mv(d, "fire_res"))
	var m := 1.0 + mv(a, "fire_hit") * res          # 화염일격 —— 즉발 (고급·희귀)
	if has_st(d, "burn"):
		m *= 1.0 + mv(a, "fire_amp") * res
	return m


## 화상 세기 배율 —— 건 쪽 burn_amp, 받는 쪽 fire_weak 는 올리고 fire_res 는 내린다
func _burn_mul(a: Unit, d: Unit) -> float:
	var m := (1.0 + (mv(a, "burn_amp") if a else 0.0)) * (1.0 + mv(d, "fire_weak"))
	return m * (1.0 - minf(0.9, mv(d, "fire_res")))


## 점화로 거는 화상 세기 —— 거는 카드 등급별 (data/passives.json fire.burn.val)
func _fire_burn(a: Unit) -> float:
	return float(DB.PSV.fire.burn.val[str(clampi(a.c.tier, 3, 8))])


## 점화 —— 맞힐 때마다 ignite 확률로 화상
func _ignite(a: Unit, d: Unit) -> void:
	var p := mv(a, "ignite")
	if mv(a, "night") > 0 and not a.night_used:
		a.night_used = true
		p = 1.0
	if p <= 0 or d.troops <= 0 or not d.alive:
		return
	if p >= 1.0 or rng.randf() < p:
		stats.ignites += 1
		_chain(a.camp, "점화", a.key)
		inflict(a, d, "burn", _fire_burn(a), int(DB.PSV.fire.burn.dur))


## 번짐 —— 같은 열의 이웃(없으면 아무 아군)에게 화상이 옮겨 붙는다. 세기는 spread_val 배, 번진 불은 반만 다시 번진다
func _spread_burn(u: Unit, s: Dictionary) -> void:
	var cand := units.filter(func(o): return o.alive and o != u and o.camp == u.camp and not has_st(o, s.k))
	if cand.is_empty():
		return
	var same := cand.filter(func(o): return _same_line(o, u))
	_spread_burn_to(u, s, pick(same if not same.is_empty() else cand))


func _spread_burn_to(u: Unit, s: Dictionary, t: Unit) -> void:
	var water: bool = s.k == "flood"
	var res := mv(t, "flood_res") if water else mv(t, "fire_res")
	var weak := 0.0 if water else mv(t, "fire_weak")
	var v := maxf(1, roundf(s.val / u.max * t.max * float(DB.PSV.water.flow_val if water else DB.PSV.fire.spread_val) * (1.0 + weak) * (1.0 - minf(0.9, res))))
	if t.st.size() >= _st_cap(t):
		var w = t.st[0]
		for x in t.st:
			if x.dur <= w.dur: w = x
		t.st.erase(w)
	t.st.append({"k": s.k, "val": v, "dur": maxi(1, s.dur), "sp": s.sp * 0.5})
	if water:
		stats.flows += 1
		_chain(_foe(t.camp), "물길")
		L("st", "물길이 %s의 진영으로 흘러들었다" % nm(t), {"fx": "status", "f": t.key, "st": "flood", "from": u.key})
	else:
		stats.spreads += 1
		_chain(_foe(t.camp), "불길 번짐")
		L("st", "불길이 %s에게 번졌다" % nm(t), {"fx": "status", "f": t.key, "st": "burn", "from": u.key})


## 진영에서 가장 센 수정치 (살아 있는 부대 중)
func _side_max(cp: String, k: String) -> float:
	var v := 0.0
	for o in units:
		if o.alive and o.camp == cp:
			v = maxf(v, mv(o, k))
	return v


## 화선돌격·박망파 —— 전투 시작에 적 선봉 전체에 화상 (가진 장수마다)
func _kindle() -> void:
	for u in units:
		if mv(u, "kindle") <= 0:
			continue
		var foes := units.filter(func(o): return o.camp != u.camp)
		var front := resolve_targets("allyFront", [], u, foes)
		L("sk", "%s의 불길이 적 선봉을 덮친다" % nm(u), {"fx": "skill", "a": u.key, "name": "화공", "kind": "int"})
		for t in front:
			inflict(u, t, "burn", _fire_burn(u), int(DB.PSV.fire.burn.dur))


## 칠백리 —— 불타던 부대가 무너지면 그 불이 같은 열 전체로
func _blaze(u: Unit) -> void:
	var s = null
	for x in u.st:
		if x.k == "burn": s = x
	if s == null:
		return
	for t in units:
		if t.alive and t != u and t.camp == u.camp and _same_line(t, u) and not has_st(t, "burn"):
			_spread_burn_to(u, s, t)
			stats.blazes += 1
			_chain(_foe(u.camp), "연소")


## 오소 —— 불타는 부대는 (적에게 오소가 있으면) 병력을 회복하지 못한다
func _scorched(d: Unit) -> bool:
	if not fire_enabled or not has_st(d, "burn") or _side_max(_foe(d.camp), "scorch") <= 0:
		return false
	stats.scorched += 1
	return true


# ───────── 수공 (솔국지 확장) ─────────

## 수몰된 부대의 속도 배율 (이감) —— 기본 water.slow + 적 진영의 격류, 제방이 깎는다
func _flood_slow(u: Unit) -> float:
	if not water_enabled or not has_st(u, "flood"):
		return 1.0
	var sl := minf(float(DB.PSV.water.get("slow_cap", 0.7)), float(DB.PSV.water.slow) + _side_max(_foe(u.camp), "flood_slow"))
	return 1.0 - sl * (1.0 - minf(1.0, mv(u, "flood_res")))


## 침수로 거는 수몰 세기 —— 거는 카드 등급별
func _water_flood(a: Unit) -> float:
	return float(DB.PSV.water.flood.val[str(clampi(a.c.tier, 3, 8))])


## 침수 —— 맞힐 때마다 soak 확률로 수몰
func _soak(a: Unit, d: Unit) -> void:
	var p := mv(a, "soak")
	if p <= 0 or d.troops <= 0 or not d.alive:
		return
	if rng.randf() < p:
		stats.soaks += 1
		_chain(a.camp, "침수", a.key)
		inflict(a, d, "flood", _water_flood(a), int(DB.PSV.water.flood.dur))


## 백의도강 —— 전투 시작에 적 후군 전체에 수몰 (가진 장수마다)
func _tide() -> void:
	for u in units:
		if mv(u, "tide") <= 0:
			continue
		var live := units.filter(func(o): return o.camp != u.camp and o.alive)
		if live.is_empty():
			continue
		L("sk", "%s의 군사가 강을 건너 적 후군을 덮친다" % nm(u), {"fx": "skill", "a": u.key, "name": "수공", "kind": "int"})
		for t in _back_of(live):
			stats.tides += 1
			_chain(u.camp, "백의도강", u.key)
			inflict(u, t, "flood", _water_flood(u), int(DB.PSV.water.flood.dur))


## 수엄칠군 —— 적에게 수엄칠군이 있으면, 잠긴 채 병력이 drown_at 아래로 떨어진 부대는 휩쓸려 무너진다
func _drown() -> void:
	if not water_enabled:
		return
	for u in units:
		if not u.alive or not has_st(u, "flood") or u.troops / u.max >= float(DB.PSV.water.drown_at):
			continue
		if _side_max(_foe(u.camp), "drown") > 0:
			stats.drowned += 1
			_chain(_foe(u.camp), "수엄칠군")
			rout(u, "물에 휩쓸려 무너졌다")


# ───────── 수치 깎기 · 물리 · 책략 (솔국지 확장, 2026-10-30) ─────────

func _st_of(u: Unit, k: String):
	for x in u.st:
		if x.k == k:
			return x
	return null


const CUT_NAME := {"atk": "공격", "int": "책략", "def": "방어"}
const CUT_ST := {"atk": "cut_atk", "int": "cut_int", "def": "cut_def"}   # 화면 상태 이름 (위축 · 산란 · 파갑 —— 현혹(책략방어)은 11/7 파갑으로 합쳤다)


## 수치로 깎는다 (위축 · 산란 · 파갑) —— 전투 끝까지 쌓이고 0 까지. 명경(stres)이 막을 수 있다
func _cut(a: Unit, d: Unit, stat: String, amt: float, why: String) -> void:
	stat = S(stat)      # 11/6 #15
	if not cut_enabled or not d.alive or amt <= 0:
		return
	if mv(d, "stres") > 0 and rng.randf() < mv(d, "stres"):
		return
	var room := eff(d, stat) - 1.0
	var v := minf(amt, maxf(0, room))
	if v <= 0:
		return
	d.cut[stat] += v
	stats.cuts += v
	stats.cut_n += 1
	L("st", "『%s』 %s의 %s −%d" % [why, nm(d), CUT_NAME[stat], roundi(v)], {"fx": "debuff", "f": d.key, "st": CUT_ST[stat], "n": v})


## 맞힐 때마다 깎는 양 —— 특기 값 × 자기 능력치(물리는 공격, 책략은 책략). 10/30 턴 배율로 나누던 것을 뺐다 (높은 등급에서 거의 0 이 됐다)
func _cut_amt(a: Unit, key: String, phys: bool) -> float:
	return mv(a, key) * (a.c.atk if phys else a.c["int"])


## 디버프에 걸린 적인가 (약점) —— 화상 · 둔화 · 혼란 · 봉인 · 역병, 또는 깎인 수치
func _debuffed(d: Unit) -> bool:
	if d.st.any(func(x): return x.k in ["burn", "bleed", "flood", "confuse", "seal", "plague"]):
		return true
	for k in d.cut:
		if d.cut[k] > 0:
			return true
	if shield_enabled and (int(d.shred.phys.t) > 0 or int(d.shred["int"].t) > 0):      # 11/8 갑옷 · 결계 깎기
		return true
	return false


## 피해 배율 —— 약점(디버프 걸린 적에게)
func _tac_mul(a: Unit, d: Unit) -> float:
	if a == null:
		return 1.0
	var m := 1.0 + (mv(a, "weak_amp") if _debuffed(d) else 0.0)
	if water_enabled and has_st(d, "flood"):
		m *= 1.0 + float(DB.PSV.water.get("weak", 0.0))      # 둔화 —— 발이 묶인 적은 더 아프게 맞는다
	return m


## 한 번 쓰고 사라지는 피해 배율 —— 기세(적을 무너뜨린 뒤 다음 공격)
func _amp_once(a: Unit) -> float:
	if a == null or a.kill_amp <= 0 or a.cleaving:
		return 1.0
	var m := 1.0 + a.kill_amp
	a.kill_amp = 0.0
	stats.kills_amp += 1
	_chain(a.camp, "기세", a.key)
	return m


## 맞힌 뒤 —— 위축 · 산란 · 파갑(현혹 포함) · 쇄갑 · 위압(사기 낮은 적 혼란) · 일기당천(깎인 적 처형)
func _tac_hit(a: Unit, d: Unit, phys: bool) -> void:
	if d.troops <= 0 or not d.alive or a.cleaving:
		return
	if mv(a, "cut_atk") > 0:
		_cut(a, d, "atk", _cut_amt(a, "cut_atk", not is_caster(a.c)), "위축")
	if phys and shield_enabled:      # 11/8 갑옷 · 결계 깎기 —— 수치는 등급표, 특기 키는 켬/끔만 (깎기 특기를 둘 가진 장수도 한 번)
		if mv(a, "shred") > 0:
			_shred(a, d, "phys", _shred_v(a), int(_gv("shred_dur", 3)), "파갑")
		if mv(a, "first_shred") > 0 and not a.cut_used:
			a.cut_used = true
			_shred(a, d, "phys", _shred_v(a) * _gv("shred_big", 1.5), int(_gv("shred_big_dur", 6)), "쇄갑")
		if mv(a, "wshred") > 0:
			_shred(a, d, "int", _shred_v(a), int(_gv("shred_dur", 3)), "현혹")
	elif phys:
		if mv(a, "cut_def") > 0:
			_cut(a, d, "def", _cut_amt(a, "cut_def", true), "파갑")
		if mv(a, "first_cut") > 0 and not a.cut_used:
			a.cut_used = true
			_cut(a, d, "def", mv(a, "first_cut") * a.c.atk, "쇄갑")
	else:
		if mv(a, "cut_int") > 0:
			_cut(a, d, "int", _cut_amt(a, "cut_int", false), "산란")
	if scheme_enabled and has_st(d, "confuse") and mv(a, "confuse_break") > 0:      # 경국(초선) —— 혼란된 적의 방어가 무너진다
		_cut(a, d, "def", 0.06 * maxf(a.c.atk, a.c["int"]) / turn_mul, "경국")
	if mv(a, "awe") > 0 and d.morale <= 60 and rng.randf() < mv(a, "awe"):      # 위압 —— 꺾인 적은 겁에 질려 차례를 날린다
		stats.awes += 1
		_chain(a.camp, "위압", a.key)
		inflict(a, d, "confuse", 1, int(DB.PSV.scheme.dur))
	var ex := mv(a, "exec_break")
	if ex > 0 and (int(d.shred.phys.t) > 0 if shield_enabled else d.cut.def > 0) and d.troops / d.max <= ex:      # 비장(여포) —— 방어(11/8 갑옷)가 깎인 적을 베어 넘긴다
		stats.execs += 1
		_chain(a.camp, "비장", a.key)
		rout(d, "한 칼에 베였다")


## 휩쓸기(물리) · 파상(책략) —— 맞힌 적의 같은 열 이웃에게 피해 일부
func _cleave(a: Unit, d: Unit, mult: float, phys: bool) -> void:
	var r := mv(a, "cleave" if phys else "icleave")
	if r <= 0 or a.cleaving or a.countering:
		return
	var near := units.filter(func(o): return o.alive and o != d and o.camp == d.camp and _same_line(o, d))
	if near.is_empty():
		return
	a.cleaving = true
	for t in near:
		var b: float = t.troops
		if phys: phys_hit(a, t, mult * r, true)
		else: int_hit(a, t, mult * r, 1)
		stats.cleaves += b - t.troops
	a.cleaving = false


## 전투 시작 —— 위진(장료, 적 선봉 방어) · 기선(적 선봉 공격) · 이간(적 후군 책략) · 요언(적 전원 방어) · 수계(적 전원 둔화)
func _tac_open() -> void:
	for u in units:
		var live := units.filter(func(o): return o.camp != u.camp and o.alive)
		if live.is_empty():
			continue
		var front := _front_of(live)
		var back := _back_of(live)
		if mv(u, "rush") > 0:
			L("sk", "%s의 기병이 적 선봉을 들이친다" % nm(u), {"fx": "skill", "a": u.key, "name": "위진", "kind": "phys"})
			for t in front:
				if shield_enabled: _shred(u, t, "phys", _shred_v(u) * _gv("shred_big", 1.5), roundi(_gv("shred_big_dur", 6) * _long), "위진")      # 11/8 적 선봉 갑옷을 크게 —— 지속은 다른 시작 효과처럼 턴 배율만큼 (6턴 × turn_mul)
				else: _cut(u, t, "def", 0.2 * u.c.atk, "위진")
		if mv(u, "open_cut_atk") > 0:
			for t in front: _cut(u, t, "atk", mv(u, "open_cut_atk") * maxf(u.c.atk, u.c["int"]), "기선")
		if mv(u, "open_cut_int") > 0:
			for t in back: _cut(u, t, "int", mv(u, "open_cut_int") * u.c["int"], "이간")
		if mv(u, "open_cut_def") > 0:
			for t in live: _cut(u, t, "def", mv(u, "open_cut_def") * u.c["int"], "요언")
		if mv(u, "open_wshred") > 0:      # 11/8 요언 —— 적 전원 결계를 크게 (shield_enabled 면 open_cut_def 가 이 키로 바뀐다)
			for t in live: _shred(u, t, "int", _shred_v(u) * _gv("shred_big", 1.5), roundi(_gv("shred_big_dur", 6) * _long), "요언")      # 지속은 턴 배율만큼 (위진과 같게)
		if water_enabled and mv(u, "open_slow") > 0:
			L("sk", "%s 둑을 터뜨려 적진을 늦춘다" % ga(nm(u)), {"fx": "skill", "a": u.key, "name": "수계", "kind": "int"})
			for t in live: inflict(u, t, "flood", 1, 1)


## 무너질 때 —— 기세(무너뜨린 쪽 다음 공격 +) · 추격(한 번 더 칠 차례를 줄 세운다)
var _chase_q: Array = []

func _tac_rout(u: Unit) -> void:
	var k = u.last_hit
	if k == null or k.camp == u.camp or not k.alive:
		return
	if mv(k, "kill_amp") > 0:
		k.kill_amp = mv(k, "kill_amp")
	if mv(k, "chase") > 0 and k.chase_turn != _turn:
		k.chase_turn = _turn
		_chase_q.append(k)


## 추격 —— 줄 선 장수가 곧바로 기본 공격 한 번
func _do_chase() -> void:
	while not _chase_q.is_empty():
		var k: Unit = _chase_q.pop_front()
		if not k.alive:
			continue
		var foes := units.filter(func(o): return o.camp != k.camp)
		var tt := basic_target(k, foes)
		if tt.is_empty() or not tt[0].alive:
			continue
		stats.chases += 1
		_chain(k.camp, "추격", k.key)
		L("sk", "%s 달아나는 적을 몰아친다" % ga(nm(k)), {"fx": "skill", "a": k.key, "name": "추격", "kind": "phys"})
		if is_caster(k.c): int_hit(k, tt[0], 1, 1)
		else: phys_hit(k, tt[0], 1, true)


# ───────── 철벽 · 계략 · 인덕 (솔국지 확장) ─────────

## 머리표에 보일 상태 —— 상태이상에 방진 · 분발 버프를 더한다 (표시용, 판정에 쓰지 않는다)
func _shown_st(u: Unit) -> Array:
	var out: Array = u.st.map(func(x): return x.k)
	if _phalanx(u):
		out.append("phalanx")
	if u.buffs.any(func(b): return b.get("moved", false)):
		out.append("moved")
	for k in u.cut:
		if u.cut[k] > 0:
			out.append(CUT_ST[k])
	if shield_enabled and int(u.shred.phys.t) > 0 and float(u.shield.phys) > 0.0 and not out.has("cut_def"):
		out.append("cut_def")      # 11/8 갑옷 깨짐 —— 제 아이콘은 3단계, 지금은 파갑 표지를 같이 쓴다
	return out


## 방진 중인가 (철벽)
func _phalanx(u: Unit) -> bool:
	return guard_enabled and _buff_sum(u, "phalanx") > 0


## 방진을 친다 —— 버프 stat "phalanx" (eff() 가 읽지 않는 표시용), 이미 있으면 남은 턴만 늘린다
func _give_phalanx(u: Unit, dur: int, why: String) -> void:
	if not guard_enabled or not u.alive:
		return
	for b in u.buffs:
		if b.stat == "phalanx":
			b.dur = maxi(b.dur, roundi(dur * _long))
			return
	u.buffs.append({"stat": "phalanx", "amt": 1.0, "dur": roundi(dur * _long)})
	stats.phalanx += 1
	L("sk", "%s 방진을 친다 (%s)" % [ga(nm(u)), why], {"fx": "buff", "f": u.key, "up": true})


## 사수 —— 방진 중 이 피해로 무너질 참이면 한 번, 병력 1을 남긴다
func _stand(d: Unit, loss: float) -> float:
	if d.troops - loss <= 0 and not d.stand_used and mv(d, "last_stand") > 0 and _phalanx(d):
		d.stand_used = true
		stats.stands += 1
		L("sk", "%s 방진을 지키며 끝내 버틴다" % ga(nm(d)), {"fx": "buff", "f": d.key, "up": true})
		return maxf(0, d.troops - 1)
	return loss


## 철옹성 —— 전투 시작에 아군 전열(가장 앞 열) 전원 방진 1턴 (턴 시작에 1 줄어 2로 준다)
func _guard_open() -> void:
	if not guard_enabled:
		return
	for u in units:
		if mv(u, "wall") <= 0 or not u.alive:
			continue
		var mine := units.filter(func(o): return o.camp == u.camp and o.alive)
		L("sk", "%s의 명으로 전열이 성벽처럼 늘어선다" % nm(u), {"fx": "skill", "a": u.key, "name": "철옹성", "kind": "phys"})
		for t in _front_of(mine):
			_give_phalanx(t, 2, "철옹성")


## 혼란 · 봉인된 적을 칠 때 (허실) · 초선 폐월(혼란된 적은 와해된 것으로)
func _scheme_mul(a: Unit, d: Unit) -> float:
	if a == null or not scheme_enabled:
		return 1.0
	var m := 1.0
	var dazed := has_st(d, "confuse") or has_st(d, "seal")
	if dazed:
		m *= 1.0 + mv(a, "confuse_amp")
	return m


## 사기를 채운다 (사기 축 —— 함성 · 독전 · 결사 · 진정 · 고무). log=false 면 기록 없이 (차례마다 조금씩 차는 것)
func _rally(u: Unit, amt: float, why: String, log := true) -> void:
	if not u.alive or amt <= 0:
		return
	var b := u.morale
	u.morale = minf(200, u.morale + amt)
	stats.rallied += u.morale - b
	if log and u.morale - b >= 1:
		L("hl", "『%s』 %s의 사기 +%d" % [why, nm(u), roundi(u.morale - b)], {"fx": "heal", "f": u.key, "m": u.morale - b})


## 자기 차례 시작 —— 방진(철벽) · 인술(가장 지친 아군 치료) · 독전 · 진정
func _turn_start(u: Unit) -> void:
	if mv(u, "cheer_turn") > 0:      # 독전 —— 차례마다 같은 열 아군 사기 + (턴 배율만큼 나눠 전투 전체로는 같게)
		for o in units:
			if o.alive and o.camp == u.camp and _same_line(o, u):
				_rally(o, mv(u, "cheer_turn") / turn_mul, "", false)
	if mv(u, "steady") > 0 and not u.steady_used and u.morale < 60:      # 진정 —— 사기가 60 아래로 떨어지면 한 번 추스른다
		u.steady_used = true
		_rally(u, mv(u, "steady"), "진정")
	if guard_enabled and mv(u, "phalanx") > 0 and rng.randf() < mv(u, "phalanx"):
		_give_phalanx(u, int(DB.PSV.guard.dur), "방진")
	if virtue_enabled and mv(u, "mend") > 0:
		var t = _most_hurt(u.camp)
		if t:
			var b: float = t.troops
			heal_troop(t, mv(u, "mend"), "인술", u)
			stats.mends += t.troops - b


func _most_hurt(cp: String):
	var al := units.filter(func(o): return o.alive and o.camp == cp and o.troops < o.max and not _scorched(o))
	if al.is_empty():
		return null
	al.sort_custom(func(x, y): return x.troops / x.max < y.troops / y.max)
	return al[0]


## 맞힌 뒤 (물리 · 책략 공통) —— 교란(즉발 사기 -) · 위무(즉발 아군 치료)
func _after_hit(a: Unit, d: Unit) -> void:
	if scheme_enabled and d.alive and mv(a, "jolt") > 0:
		d.morale -= mv(a, "jolt")
		stats.jolts += mv(a, "jolt")
	if virtue_enabled and mv(a, "cheer_hit") > 0:
		var t = _most_hurt(a.camp)
		if t:
			var b: float = t.troops
			heal_troop(t, mv(a, "cheer_hit"), "위무", a)
			stats.mends += t.troops - b


## 분발 —— 치료받은 아군이 2턴 동안 공격 · 책략 + (이미 있으면 남은 턴만 늘린다). 유비 「인의」면 방진도 친다
func _give_moved(u: Unit) -> void:
	var dur: int = int(DB.PSV.virtue.moved_dur)
	var found := false
	for b in u.buffs:
		if b.get("moved", false):
			if moved_cd <= 0:
				b.dur = maxi(b.dur, dur)
			found = true
	if moved_cd > 0 and (found or _turn < u.moved_next):
		return          # 11/8 분발 중이거나 끝난 뒤 대기 중 —— 늘리지도 (인의) 방진을 다시 치지도 않는다
	if not found:
		u.moved_next = _turn + dur + moved_cd
		var amt: float = DB.PSV.virtue.moved
		u.buffs.append({"stat": "atk", "amt": amt, "dur": dur, "moved": true})
		u.buffs.append({"stat": "int", "amt": amt, "dur": dur, "moved": true})
		stats.moved += 1
		L("sk", "%s 분발해 힘을 낸다" % ga(nm(u)), {"fx": "buff", "f": u.key, "up": true})
	if _side_max(u.camp, "moved_phalanx") > 0:
		_give_phalanx(u, dur, "인의")


## 증기 —— 주유의 수륙병진: 수몰된 부대의 불길이 더 거세진다 (화공의 맞수가 아니라 짝). 수몰이 불을 끄지는 않는다 (11/8 수공 제어 전담)
func _steam(d: Unit) -> void:
	if fire_enabled and water_enabled and _side_max(_foe(d.camp), "steam") > 0:
		for x in d.st:
			if x.k == "burn":
				x.val = roundf(x.val * 1.3)
				stats.steams += 1
				_chain(_foe(d.camp), "증기")
				L("st", "묶인 %s의 진영에 불길이 더 거세진다" % nm(d), {"fx": "status", "f": d.key, "st": "burn"})


## 수공 장수인가 —— 수몰을 걸거나 · 깔거나 · 막는 특기를 가진 부대
func _is_water(u: Unit) -> bool:
	for k in ["soak", "tide", "drown", "flood_slow", "flood_res", "open_slow"]:
		if u.m.get(k, 0.0) > 0:
			return true
	return false


## 물길 정화 —— 수공 장수가 공격할 때마다 가장 가까운 아군(자신 포함) 한 부대의 화상을 씻는다 (적 화공의 맞수)
func _wash(a: Unit) -> void:
	if not water_enabled or not _is_water(a):
		return
	var best: Unit = null
	var bd := 1e18
	for o in units:
		if o.camp != a.camp or not o.alive or not has_st(o, "burn"):
			continue
		var dd := o.pos.distance_squared_to(a.pos)
		if dd < bd:
			bd = dd
			best = o
	if best == null:
		return
	for x in best.st:
		if x.k == "burn":
			best.st.erase(x)
			break
	stats.doused += 1
	_chain(a.camp, "물길 정화", a.key)
	L("st", "%s의 물길이 %s의 불길을 꺼뜨렸다" % [nm(a), nm(best)], {"fx": "cleanse", "f": best.key, "st": "burn"})


## 11/8 패업(霸業) —— 신화의 덱 조건 (data/myth_aura.json 의 paeup). 전투 전 편성만 보고 정한다 (결정성 · 온라인 재현)
## cond: status = 상태이상(PAEUP_ST)을 거는 장수 · burn = 화상을 거는 장수, 자신 외 need 명 이상
func _paeup_setup() -> void:
	for u in units:
		if not paeup_enabled or not aura_enabled or not DB.AURA.has(u.c.id) or not DB.AURA[u.c.id].has("paeup") or (aura_camp != "" and u.camp != aura_camp):
			continue
		var pa: Dictionary = DB.AURA[u.c.id].paeup
		var cond := str(pa.cond)
		var have := 0
		if cond != "none":
			for o in units:
				if o != u and o.camp == u.camp and paeup_counts(o.c.id, cond):
					have += 1
		var on := have >= int(pa.need)
		var dtxt := str(pa.get("d", ""))
		if on and str(pa.fx) == "steal_aura":      # 협천자 —— 적 위세 하나를 빼앗는다 (없으면 불발)
			var vic = _paeup_steal_pick(u)
			if vic == null:
				on = false
			else:
				_stolen[vic] = u.camp
				dtxt = "적 %s의 위세 『%s』를 빼앗아 아군 편으로 쓴다" % [nm(vic), str(DB.AURA[vic.c.id].n)]
		if on:
			_paeup[str(pa.fx) + ":" + u.camp] = u
		_paeup_log.append({"camp": u.camp, "id": u.c.id, "key": u.key, "who": nm(u), "n": str(pa.n), "d": dtxt, "fx": str(pa.fx),
			"what": str(pa.get("what", "화상" if cond == "burn" else "상태이상")), "on": on, "have": have, "need": int(pa.need)})


## 이 카드가 패업 조건(cond)에 들어가는가
static func paeup_counts(cid: String, cond: String) -> bool:
	var ks := st_kinds_of(cid)
	if cond == "burn":
		return ks.has("burn")
	return PAEUP_ST.any(func(k): return ks.has(k))


## 카드가 거는 상태이상 종류 (정적) —— 특기 축(도트 → 화상 · 둔화 → 수몰 · 혼란 → 혼란) + 잔기술 · 기술 · 고유기의 status
static var _stk_cache := {}
static func st_kinds_of(cid: String) -> Dictionary:
	if _stk_cache.has(cid):
		return _stk_cache[cid]
	var out := {}
	var ps = DB.passives_of(cid)
	if ps != null:
		for t in ps.traits + ps.groups:
			match str(t.attr):
				"도트": out["burn"] = true
				"둔화": out["flood"] = true
				"혼란": out["confuse"] = true
	var mk := minor_kind(cid)
	if mk != "" and minor_def(mk).has("st"):
		out[str(minor_def(mk).st[0])] = true
	for sk in DB.C[cid].get("sks", []):
		if sk.has("eff") and sk.eff.has("status"):
			out[str(sk.eff.status.k)] = true
	if DB.C[cid].tier >= 6 or DB.C[cid].kind == "kiin":
		var ul = DB.ult_of(cid)
		if ul:
			for comp in ul.eff:
				if comp.has("status"):
					out[str(comp.status.k)] = true
	_stk_cache[cid] = out
	return out


## 한 부대가 동시에 걸리는 상태이상 한도 —— 2, 적 진영에 태평요술(장각 패업)이 발동했으면 3
func _st_cap(d: Unit) -> int:
	return 3 if _paeup.has("st_cap:" + _foe(d.camp)) else 2


## 적벽연소(주유 패업) —— 화상 걸린 적이 쓰러지면 남은 화상이 병력이 가장 많은 적 한 부대로 옮겨붙는다 (전투당 2번, 세기 spread_val)
func _paeup_burn(u: Unit) -> void:
	var key := "rout_burn:" + _foe(u.camp)
	var zy = _paeup.get(key)
	if zy == null or int(_paeup_used.get(key, 0)) >= 2:
		return
	var s = null
	for x in u.st:
		if x.k == "burn": s = x
	if s == null:
		return
	var best: Unit = null
	for t in units:
		if t.alive and t != u and t.camp == u.camp and not has_st(t, "burn") and (best == null or t.troops > best.troops):
			best = t
	if best == null:
		return
	_paeup_used[key] = int(_paeup_used.get(key, 0)) + 1
	L("sk", "%s의 적벽연소 —— 쓰러진 %s의 불길이 %s에게 옮겨붙는다" % [nm(zy), nm(u), nm(best)], {"fx": "skill", "a": zy.key, "name": "적벽연소", "kind": "int"})
	_spread_burn_to(u, s, best)


## 11/9 패업 2차 —— 조조 협천자 · 관우 오관참장 · 제갈량 천문 · 감녕 백기야습 · 장료 위진소요진 · 손권 제왕술 · 여포 무쌍
## 시간 · 거리가 들어가는 것(감녕 · 장료 · 손권 · 천문)은 실시간 엔진(RtBattle)에서만 움직인다. 난수 없이 슬롯 · 시각으로만 고른다 (결정성)

## 패업 효과가 켜져 있는가 (이 진영의 신화가 살아 있어야 한다) —— 켜졌으면 그 신화
func _pa(fx: String, cp: String):
	var z = _paeup.get(fx + ":" + cp)
	return z if z != null and z.alive else null


func _pa_use(fx: String, cp: String, cap: int) -> bool:
	var k := fx + ":" + cp
	if int(_paeup_used.get(k, 0)) >= cap:
		return false
	_paeup_used[k] = int(_paeup_used.get(k, 0)) + 1
	return true


## 위세를 빼앗은 쪽으로 본 이 위세 장수의 진영 (협천자)
func _acamp(mu: Unit) -> String:
	return str(_stolen.get(mu, mu.camp))


## 협천자 —— 훔칠 적 위세 장수 (신화 · 초월 먼저, 등급 높은 순 · 칸 번호 순). 없으면 null
func _paeup_steal_pick(u: Unit):
	var best = null
	for v in _myths:
		if v.camp == u.camp or _stolen.has(v):
			continue
		if best == null or v.c.tier > best.c.tier or (v.c.tier == best.c.tier and v.slot < best.slot):
			best = v
	return best


## 여포 무쌍 —— 아군의 치료 · 버프 · 위세를 받지 않는 여포인가
func _no_ally(u: Unit) -> bool:
	return not _paeup.is_empty() and _paeup.get("peerless:" + u.camp) == u


## 공격 배율 —— 손권 제왕술(공격하지 않는다 → 0) · 여포 무쌍(쓰러진 아군마다 +12%, 최대 +60%)
func _paeup_atk(u: Unit) -> float:
	if _paeup.get("crown:" + u.camp) == u:
		return 0.0
	if _paeup.get("peerless:" + u.camp) == u:
		return 1.0 + minf(0.6, 0.12 * float(_paeup_used.get("peerless_n:" + u.camp, 0)))
	return 1.0


## 감녕 백기야습 —— 개전 8초 동안 숨는다 (적의 목표가 되지 않는다)
func _hidden(u: Unit) -> bool:
	return u.alive and not _paeup.is_empty() and _by_distance() and _tm < 8.0 and _paeup.get("hide:" + u.camp) == u


## 장료 위진소요진 —— 적이 거리를 두 배로 치는 장료인가
func _pa_wei(o: Unit) -> bool:
	return not _paeup.is_empty() and o.alive and _paeup.get("wei_aura:" + o.camp) == o


## 실시간 틱 —— 장료 위진소요진(둘레 250 안 적 사기 초당 −2) · 손권 제왕술(15초마다 고유기 장수 하나의 기를 가득)
func _paeup_tick(dt: float) -> void:
	if _paeup.is_empty():
		return
	for cp in ["A", "B"]:
		var z = _pa("wei_aura", cp)
		if z != null:
			var hit := false
			for o in units:
				if o.alive and o.camp != cp and o.pos.distance_to(z.pos) <= 250.0:
					o.morale -= 2.0 * dt
					hit = true
			if hit and _pa_use("wei_aura_log", cp, 1):
				L("sk", "%s의 위진소요진 —— 둘레의 적이 기세에 눌린다" % nm(z), {"fx": "skill", "a": z.key, "name": "위진소요진", "kind": "phys"})
		var sq = _pa("crown", cp)
		if sq != null:
			var n := int(_paeup_used.get("crown_n:" + cp, 0))
			if _tm >= 15.0 * float(n + 1):
				_paeup_used["crown_n:" + cp] = n + 1
				var last := str(_paeup_used.get("crown_last:" + cp, ""))
				var best: Unit = null
				for o in units:
					if o.alive and o.camp == cp and o != sq and o.ult != null and o.charges > 0 and o.key != last and (best == null or o.gauge < best.gauge):
						best = o
				if best != null:
					best.gauge = 100.0
					_paeup_used["crown_last:" + cp] = best.key
					L("sk", "%s의 제왕술 —— %s 대도독으로 세워 기를 가득 채운다" % [nm(sq), nm(best)], {"fx": "skill", "a": sq.key, "name": "제왕술", "kind": "int"})


## 감녕 백기야습 —— 숨은 동안 처음 닿은 고유기 장수의 기를 0 으로 (기 모으는 중이면 취소)
func _paeup_snipe(a: Unit, d: Unit) -> void:
	if _paeup.is_empty() or a.countering or a.camp == d.camp or not _hidden(a) or d.ult == null:
		return
	if not _pa_use("hide_hit", a.camp, 1):
		return
	d.gauge = 0.0
	_paeup_unwind(d)
	L("sk", "%s의 백기야습 —— %s의 기가 흩어진다" % [nm(a), nm(d)], {"fx": "skill", "a": a.key, "name": "백기야습", "kind": "phys"})


## 기 모으기 취소 (실시간 엔진이 덮어쓴다)
func _paeup_unwind(_d: Unit) -> void:
	pass


## 제갈량 천문 —— 적이 기를 모으기 시작하면 그 고유기가 칠 아군(keys)이 받는 피해를 절반으로 (전투당 처음 세 번)
func _paeup_omen(caster: Unit, keys: Array) -> void:
	var cp := _foe(caster.camp)
	var z = _pa("omen", cp)
	if z == null or not _pa_use("omen", cp, 3):
		return
	_omen[caster] = keys
	L("sk", "%s의 천문 —— %s의 기운을 읽어 아군이 받을 피해를 줄인다" % [nm(z), nm(caster)], {"fx": "skill", "a": z.key, "name": "천문", "kind": "int"})


func _omen_mul(a: Unit, d: Unit) -> float:
	if not _omen.is_empty() and _in_ult and _omen.has(a) and _omen[a].has(d.key):
		return 0.5
	return 1.0


## 쓰러짐에 반응하는 패업 —— 여포 무쌍(아군이 쓰러질 때마다 공격 +) · 관우 오관참장(무너뜨린 뒤 가장 가까운 적으로 돌진)
func _paeup_fall(u: Unit) -> void:
	if _paeup.is_empty():
		return
	var lb = _pa("peerless", u.camp)
	if lb != null and lb != u:
		_paeup_used["peerless_n:" + u.camp] = int(_paeup_used.get("peerless_n:" + u.camp, 0)) + 1
		if int(_paeup_used["peerless_n:" + u.camp]) <= 5:
			L("sk", "%s의 무쌍 —— %s 쓰러지자 분노가 쌓인다 (공격 +%d%%)" % [nm(lb), nm(u), roundi(minf(0.6, 0.12 * int(_paeup_used["peerless_n:" + u.camp])) * 100)], {"fx": "skill", "a": lb.key, "name": "무쌍", "kind": "phys"})
	var lh = u.last_hit
	if lh != null and lh.camp != u.camp and lh.alive and _pa("pass5", lh.camp) == lh and not _pass_busy:
		var seq := int(_paeup_used.get("pass5_n:" + lh.camp, 0))
		var last_t := float(_paeup_used.get("pass5_t:" + lh.camp, -99.0))
		var now := _tm if _by_distance() else float(_turn) * 3.0
		seq = mini(5, seq + 1) if now - last_t <= 10.0 else 0
		_paeup_used["pass5_n:" + lh.camp] = seq
		_paeup_used["pass5_t:" + lh.camp] = now
		var best: Unit = null
		for o in units:
			if o.alive and o.camp != lh.camp and o != u and (best == null or (lh.pos.distance_to(o.pos) < lh.pos.distance_to(best.pos)) or (lh.pos.distance_to(o.pos) == lh.pos.distance_to(best.pos) and o.slot < best.slot)):
				best = o
		if best != null:
			var mult: float = float(CHARGE.get(lh.c.tier, ROLE.charge)) * (1.0 + 0.15 * seq)
			L("sk", "%s의 오관참장 —— 곧바로 %s에게 돌진한다 (연속 %d · 돌진 피해 +%d%%)" % [nm(lh), nm(best), seq + 1, seq * 15], {"fx": "skill", "a": lh.key, "name": "오관참장", "kind": "phys"})
			_pass_busy = true
			phys_hit(lh, best, mult, true)
			_pass_busy = false


func rout(u: Unit, why: String) -> void:
	if not u.alive: return
	var ht := _kv(u.camp, "revive")      # 신의 화타 —— 처음 무너진 아군 2부대를 병력 40%로
	if ht and ht != u and int(_kiin_used.get("revive:" + u.camp, 0)) < 2:
		_kiin_used["revive:" + u.camp] = int(_kiin_used.get("revive:" + u.camp, 0)) + 1
		u.troops = maxf(u.troops, roundf(u.max * 0.4))
		u.morale = maxf(u.morale, 60.0)
		L("hl", "%s의 기사회생 —— %s 다시 일어선다" % [nm(ht), ga(nm(u))], {"fx": "heal", "f": u.key, "n": u.troops})
		return
	if virtue_enabled and not _oath_used[u.camp] and _side_max(u.camp, "oath") > 0:      # 도원결의 —— 진영에서 한 번, 무너질 부대를 일으켜 세운다
		_oath_used[u.camp] = true
		stats.oaths += 1
		_chain(u.camp, "도원결의", u.key)
		u.troops = maxf(u.troops, roundf(u.max * float(DB.PSV.virtue.oath)))
		u.morale = maxf(u.morale, 60.0)
		L("hl", "도원의 맹세 —— %s 다시 일어선다" % ga(nm(u)), {"fx": "heal", "f": u.key, "n": u.troops})
		return
	u.alive = false
	if DB.AURA.has(u.c.id) and DB.AURA[u.c.id].get("kiin", "") == "death_gauge":      # 유계 곽가 —— 쓰러지면 아군 전원 고유기 게이지 +50
		for o in units:
			if o.alive and o.camp == u.camp:
				o.gauge = minf(100.0, o.gauge + 70.0)
				o.morale += 15.0
		L("sk", "%s의 유계 —— 남긴 계책이 펼쳐진다" % nm(u), {"fx": "skill", "a": u.key, "name": "유계", "kind": "int"})
	if fire_enabled and has_st(u, "burn") and _side_max(_foe(u.camp), "blaze") > 0:
		_blaze(u)
	if fire_enabled and has_st(u, "burn"):
		_paeup_burn(u)
	_paeup_fall(u)
	_tac_rout(u)
	if u.last_hit and u.last_hit.camp != u.camp: u.last_hit.kills += 1
	if temper_enabled:      # 11/7 기질 —— 적을 무너뜨린 맹장 · 저격은 기세가 오르고, 아군이 무너지면 수호 · 분노가 끓는다
		if u.last_hit and u.last_hit.camp != u.camp and u.last_hit.alive:
			_gauge_add(u.last_hit, _tw(u.last_hit, "kill"))
		for o in units:
			if o.alive and o.camp == u.camp and o != u:
				_gauge_add(o, _tw(o, "fall"))
	for o in units:
		if not o.alive or o.camp != u.camp: continue
		o.morale -= (K.routSame if _same_line(o, u) else K.routOther) * ROUT_SPREAD * (1.0 - mv(o, "rout_loss"))
		if mv(o, "avenge") > 0 and o.avenge_n < 3:
			o.avenge_n += 1
		if mv(o, "resolve") > 0:      # 결사 —— 아군이 무너지면 오히려 사기가 오른다
			_rally(o, mv(o, "resolve"), "결사")
	var lh = u.last_hit
	if lh and lh.camp != u.camp and lh.alive and mv(lh, "rally_kill") > 0:      # 함성 —— 적을 무너뜨리면 아군 전원 사기 +
		for o in units:
			if o.alive and o.camp == lh.camp:
				_rally(o, mv(lh, "rally_kill"), "함성")
	L("rt", "%s의 군세가 %s" % [nm(u), why], {"fx": "rout", "f": u.key})


## 총붕괴 · 결전 판정 (정산마다) —— 전투 끝을 당긴다 (위 상수 설명)
func _check_collapse(frac: float) -> void:
	if _start_troops.A <= 0.0:
		for u in units:
			_start_troops[u.camp] += u.max
	for cp in ["A", "B"]:
		if _collapsed[cp]:
			for u in units:
				if u.alive and u.camp == cp and u.c.tier < COLLAPSE_HOLD_TIER:      # 불멸 · 신화는 홀로 남아도 버틴다 (11/4 사용자)
					u.morale -= COLLAPSE_MORALE * frac
			continue
		if _collapsed[_foe(cp)]:
			continue
		# 11/4 사용자: 부대 수가 아니라 병력(군세)으로 —— 신화 한 부대가 남아 전황을 뒤집을 수 있으면 붕괴가 아니다.
		# 남은 병력이 처음의 30% 아래이고, 적 병력의 절반에도 못 미칠 때만
		var total := 0
		var tr := 0.0
		var foe_tr := 0.0
		for u in units:
			if u.camp != cp:
				if u.alive: foe_tr += u.troops
				continue
			total += 1
			if u.alive:
				tr += u.troops
		if total < 3 or tr <= 0.0:
			continue
		if tr < _start_troops[cp] * COLLAPSE_TROOPS and tr < foe_tr * COLLAPSE_VS_FOE:
			_collapsed[cp] = true
			stats["collapse_" + cp] = snappedf(_tm, 0.1)
			L("rt", "%s 총붕괴 —— 남은 부대가 줄줄이 무너진다" % ("아군" if cp == "A" else "적군"), {"fx": "collapse", "camp": cp})
	if _tm > DECISIVE_T:
		if not _decisive:
			_decisive = true
			L("div", "해가 기운다 —— 결전. 양군의 사기가 흔들린다", {"fx": "decisive"})
		for u in units:
			if u.alive and not _collapsed[u.camp]:
				u.morale -= DECISIVE_MORALE * frac


func check_rout() -> void:
	for o in units:
		if o.alive and o.troops <= 0: rout(o, "병력이 다해 무너졌다")
	if not _chase_q.is_empty():
		_do_chase()
		check_rout()


# ───────── 본 전투 ─────────

func run(a_cards: Array, a_form: String, a_morale: float, a_equip, b_cards: Array, b_form: String,
		b_morale: float, b_equip, title := "", foe_name := "", inputs_ := [], policy_ := {}) -> Dictionary:
	_setup(a_cards, a_form, a_morale, a_equip, b_cards, b_form, b_morale, b_equip, title, foe_name, inputs_, policy_)
	var turn := 0
	var winner := ""
	var cap := roundi(K.cap * turn_mul)
	while turn < cap and winner == "":
		turn += 1
		_turn_begin(turn)
		var order := []
		for u in units:
			if not u.alive: continue
			var sp: float
			if mv(u, "first") > 0: sp = eff(u, "spd") * 1.25
			else: sp = eff(u, "spd") * (1 + rnd(-0.15, 0.15))
			if turn <= roundi(turn_mul) and u.caps.has("기병") and u.c.tag == "기병": sp *= 1.6
			if u.fast_side: sp *= 1.12
			order.append([u, sp])
		order.sort_custom(func(x, y): return x[1] > y[1])
		for o in order:
			_act_one(o[0])
		winner = _turn_end()
	return _result(winner, turn)


var _meta := {}               # run 재료 중 결과에 그대로 돌려줄 것 (진형 · 시너지 · 제목)


## 전투 준비 —— 유닛 만들기 · 턴 배율 · 단체 특기 · 전투 시작 효과
func _setup(a_cards: Array, a_form: String, a_morale: float, a_equip, b_cards: Array, b_form: String,
		b_morale: float, b_equip, title: String, foe_name: String, inputs_: Array, policy_: Dictionary) -> void:
	inputs = inputs_
	for cp in policy_:
		policy[cp] = policy_[cp]
	var a_syn := fac_syn(a_cards, a_form)
	var b_syn := fac_syn(b_cards, b_form)
	var aS: Array = DB.FORM[a_form].slots
	var bS: Array = DB.FORM[b_form].slots
	for i in a_cards.size():
		var k = a_cards[i]
		if k and i < aS.size():
			units.append(mk_unit(k, aS[i], "A", a_morale, i, a_equip[i] if a_equip and a_equip[i] else innate_item(k), a_syn))
	for i in b_cards.size():
		var k = b_cards[i]
		if k and i < bS.size():
			units.append(mk_unit(k, bS[i], "B", b_morale, i, b_equip[i] if b_equip and b_equip[i] else innate_item(k), b_syn))
	for u in units:
		if DB.AURA.has(u.c.id) and DB.AURA[u.c.id].has("kiin"):
			var kk: String = DB.AURA[u.c.id].kiin
			if not _kiin_u.has(kk): _kiin_u[kk] = []
			_kiin_u[kk].append(u)
		if aura_enabled and DB.AURA.has(u.c.id) and (aura_camp == "" or u.camp == aura_camp):
			_myths.append(u)
			if DB.AURA[u.c.id].has("m"):
				_aura_m.append(u)
	_paeup_setup()
	if auto_turn and not units.is_empty():
		var ts := 0.0
		for u in units:
			ts += u.c.tier
		set_turn_mul(turn_mul_for(ts / units.size()))
	if passives_enabled or fire_enabled:
		_apply_group_passives()
		for cp in ["A", "B"]:
			pts[cp] = minf(PTS_MAX, cmdm[cp].get("pts_start", 0.0) + (tac_rush_pts if _tac(cp, 2) == "공세" else 0.0))
			if _tac(cp, 2) == "공세":
				cmdm[cp]["assault"] = cmdm[cp].get("assault", 0.0) + tac_rush_atk

	_long = turn_mul                 # 전투 시작 효과는 한 번뿐 —— 지속 턴을 턴 배율만큼
	if fire_enabled:
		_kindle()
	if water_enabled:
		_tide()
	_tac_open()
	_guard_open()
	if aura_enabled:
		for u in _myths:
			L("sk", "%s의 %s —— %s" % [nm(u), "기인" if DB.is_kiin(u.c.id) else "위세", DB.aura_text(u.c.id)])
		for p in _paeup_log:      # 개전 뒤 공개 —— 발동 · 불발 한 줄
			L("sk", "%s의 패업 『%s』 %s (%s 장수 %d/%d)%s" % [p.who, p.n, "발동" if p.on else "불발", p.what, p.have, p.need, " —— " + p.d if p.on else ""],
				{"fx": "skill", "a": p.key, "name": p.n, "kind": "int"} if p.on else {})
	_kiin_open()
	_long = 1.0
	_meta = {"title": title, "foe": foe_name, "aForm": a_form, "bForm": b_form, "aSyn": a_syn, "bSyn": b_syn}


## 11/3 기인 —— 살아 있는 그 기능의 유닛 (없으면 null)
func _kv(cp: String, key: String) -> Unit:
	for u in _kiin_u.get(key, []):
		if u.alive and u.camp == cp:
			return u
	return null


## 전투 시작 기인 —— 진형 보너스 · 습격 · 사기 · 봉인 · 이간
func _kiin_open() -> void:
	if _kiin_u.is_empty():
		return
	for cp in ["A", "B"]:
		var fo := _foe(cp)
		var mine := units.filter(func(o): return o.camp == cp)
		if _kv(fo, "no_form"):           # 교변 장합 —— 적 진형 보너스 없음
			for u in mine: u.boon = null
		elif _kv(cp, "form_x2"):         # 단복 서서 —— 아군 진형 보너스 2배
			for u in mine:
				if u.boon:
					u.boon = u.boon.duplicate()
					u.boon.v = float(u.boon.v) * 3.0
		var sx := _kv(cp, "ambush")       # 궁요 손상향 —— 적 후열 하나 습격
		if sx:
			var back := units.filter(func(o): return o.camp == fo and o.alive)
			back.sort_custom(func(x, y): return pri(x) > pri(y))
			if not back.is_empty():
				back[0].morale -= 40.0
				inflict(sx, back[0], "confuse", 1, 2)
				L("sk", "%s 적 후열 %s 습격했다" % [ga(nm(sx)), eul(nm(back[0]))], {"fx": "skill", "a": sx.key, "name": "백인시비", "kind": "phys"})
		var gh := _kv(cp, "morale_crash")  # 난무 가후 —— 적 전원 사기 −25
		if gh:
			for o in units:
				if o.alive and o.camp == fo: o.morale -= 18.0
			L("sk", "%s의 난무 —— 적진이 흔들린다" % nm(gh), {"fx": "skill", "a": gh.key, "name": "난무", "kind": "int"})
	_kiin_wave()


## 좌자 봉인 · 초선 이간 —— 개전 (좌자는 KIIN_MID_TURN 에 한 번 더 —— 초선은 개전만)
func _kiin_wave() -> void:
	var mid := _turn >= KIIN_MID_TURN
	for cp in ["A", "B"]:
		var fo := _foe(cp)
		var foes := units.filter(func(o): return o.camp == fo and o.alive)
		var zz := _kv(cp, "seal")
		if zz:
			for o in foes: inflict(zz, o, "seal", 1, 1)
			L("sk", "%s의 둔갑 —— 적의 기술이 막혔다" % nm(zz), {"fx": "skill", "a": zz.key, "name": "봉인부적", "kind": "int"})
		var cs := _kv(cp, "turncoat")
		if cs and not foes.is_empty() and not mid:
			foes.sort_custom(func(x, y): return x.slot < y.slot)
			inflict(cs, foes[_turn % foes.size()], "confuse", 1, 1)      # 하나만 (둘이면 판이 기울었다 —— 값어치 88~91%)
			L("sk", "%s의 이간 —— 적이 서로를 의심한다" % nm(cs), {"fx": "skill", "a": cs.key, "name": "양호상쟁", "kind": "int"})


## 전위 호위 —— 병력 절반 아래 아군이 받는 피해의 40%를 대신 받는다
func _kiin_guard(d: Unit, loss: float) -> float:
	var g := _kv(d.camp, "guard")
	if g == null or g == d or d.troops >= d.max * 0.7:
		return loss
	var share := roundf(loss * 0.5)
	if g.troops <= share + 1:
		return loss
	g.troops -= share
	return loss - share


## 턴 시작 —— 버프 지속 턴을 하나 줄인다
func _turn_begin(turn: int) -> void:
	_turn = turn
	if turn == KIIN_MID_TURN and not _kiin_u.is_empty():
		_kiin_wave()
	_ai += 1
	_ph = "act"
	_who = ""
	L("div", "", {"fx": "turn", "turn": turn})
	for u in units:
		for b in u.buffs: b.dur -= 1
		u.buffs = u.buffs.filter(func(b): return b.dur > 0)


## 한 유닛의 한 차례 —— 입력 판정 · 행동 · 패주 확인 · 군령 포인트
func _act_one(u: Unit) -> void:
	_between()
	if not u.alive:
		act_n += 1
		return
	_ai += 1
	_ph = "act"
	_who = u.key
	act(u)
	check_rout()
	act_n += 1
	if act_n % PTS_EVERY == 0:
		for cp in ["A", "B"]:
			pts[cp] = minf(PTS_MAX, pts[cp] + (1.0 + cmdm[cp].get("pts_rate", 0.0)) / turn_mul)


## 턴 끝 정산 —— 사기 · 회복 · 상태이상 · 패주. 승부가 났으면 "A" · "B" · "draw"
func _turn_end() -> String:
	return _settle(1.0, true)


## 정산 —— 턴 끝의 흐름(사기 · 회복 · 지속 피해 · 패주)을 frac(그 턴의 몫)만큼. 11/3 사용자: 실시간 엔진은 0.2초마다 나눠
## 부른다 (RtBattle.SETTLE). 지속 시간 줄이기 · 기록 문구는 턴 경계(final)에서만. 턴제는 frac 1 로 한 번 —— 예전과 같다
func _settle(frac: float, final: bool) -> String:
	_strat_step()
	_ai += 1
	_ph = "end"
	_who = ""

	for u in units:
		if not u.alive: continue
		var r := u.troops / u.max
		var tg := 1.0 - mv(u, "shock")
		if not u.hit50 and r <= 0.5:
			u.hit50 = true
			u.morale -= K.hit50 * tg
		if not u.hit25 and r <= 0.25:
			u.hit25 = true
			u.morale -= K.hit25 * tg
		if u.morale > 30 and u.morale < 100 and not _collapsed[u.camp] and not _decisive:
			var rg: float = K.regen * pace * frac * (1.5 if u.regen_up else 1.0)
			if u.caps.has("유생"): rg *= 2
			u.morale = minf(100, u.morale + rg)
	_check_collapse(frac)
	for cp in ["A", "B"]:
		var side := units.filter(func(u): return u.alive and u.camp == cp)
		if side.is_empty() or not side[0].caps.has("유생"): continue
		for u in side:
			if _scorched(u): continue
			var g := minf(u.max * 0.045 * pace * frac, u.max - u.troops)
			if g > 0: u.troops += g
		if final:
			L("hl", "대오를 추스른다 — 진영 병력 %.1f%% 회복" % (4.5 * pace), {"fx": "heal", "f": side[0].key})
	tick_status(frac, final)
	check_rout()
	for cp in ["A", "B"]:
		var healed := ""
		for u in units:
			if not u.alive or u.camp != cp: continue
			if mv(u, "mregen") > 0:
				u.morale = minf(200, u.morale + mv(u, "mregen") * pace * frac)
			if mv(u, "regen") > 0 and u.troops < u.max and not _scorched(u):
				u.troops = minf(u.max, u.troops + u.max * mv(u, "regen") * pace * frac)
				healed = u.key
		if healed != "" and final:
			L("hl", "특기로 대오를 추스른다", {"fx": "heal", "f": healed})
	for u in units:
		if not u.alive: continue
		var r := u.troops / u.max
		var pm := maxf(K.routMin, (30 - u.morale) * K.routSlope) if u.morale <= 30 else 0.0
		var pt := (rout_hp - r) * rout_hp_slope if r < rout_hp else 0.0
		if pm <= 0 and pt <= 0: continue
		var p := 1.0 - (1.0 - pm) * (1.0 - pt)
		p *= 1.0 + _side_max(_foe(u.camp), "fear")      # 위압 —— 적 진영에서 가장 센 값 하나
		p *= 1.0 - mv(u, "rout")
		p *= 1.0 - _buff_sum(u, "calm")
		if u.caps.has("유생"): p *= 0.5
		if _collapsed[u.camp] and u.c.tier < COLLAPSE_HOLD_TIER: p *= COLLAPSE_ROUT
		p = 1.0 - pow(1.0 - minf(p, 1.0), frac / turn_mul)     # 턴이 늘어난 만큼 · 나눠 부른 몫만큼 —— 전투 전체로 보면 같은 빈도
		if rng.randf() < p:
			if pm >= pt:
				rout(u, "사기 %d에서 끝내 패주했다" % maxi(0, roundi(u.morale)))
			else:
				rout(u, "병력이 꺾여 패주했다 (남은 병력 %d%%)" % roundi(r * 100))
	var aA := live_count("A")
	var bA := live_count("B")
	if aA == 0 and bA == 0: return "draw"
	if bA == 0: return "A"
	if aA == 0: return "B"
	return ""


## 결과 —— 시간이 다 되면 잔존 병력으로 가린다
func _result(winner: String, turn: int) -> Dictionary:
	_ai += 1
	_ph = "end"
	if winner == "":
		var at := 0.0
		var bt := 0.0
		for u in units:
			if not u.alive: continue
			if u.camp == "A": at += u.troops
			else: bt += u.troops
		winner = "A" if at > bt else ("B" if bt > at else "draw")
		L("div", "해가 기운다 — 잔존 병력 %s 대 %s" % [num(at), num(bt)], {"fx": "turn"})

	for u in units:
		u.last_hit = null       # 순환 참조를 끊어 RefCounted 가 풀리게 한다
		u.tgt = null
	var roster := []
	for u in units:
		roster.append({"id": u.c.id, "name": u.c.name, "tier": u.c.tier, "tag": u.c.tag, "fac": u.c.fac,
			"line": u.line, "side": u.side, "camp": u.camp, "max": u.max, "key": u.key, "slot": u.slot,
			"item": u.item, "morale": u.morale, "dmg": roundi(u.dmg), "heal": roundi(u.heal), "kills": u.kills,
			"mdmg": snappedf(u.mdmg, 0.1), "left": roundi(u.troops), "alive": u.alive, "theal": snappedf(u.theal, 0.001), "taken": roundi(u.taken)})   # 끝난 뒤 결과표 (mdmg · left · alive: 점검용)
	var merit := func(u: Unit): return u.dmg + u.mdmg * 420 + u.heal * 420 + u.kills * 3200
	var mine := units.filter(func(u): return u.camp == "A" and merit.call(u) > 0)
	mine.sort_custom(func(x, y): return merit.call(x) > merit.call(y))
	var mvp = null
	if not mine.is_empty():
		mvp = {"name": mine[0].c.name, "id": mine[0].c.id, "kills": mine[0].kills, "dmg": roundi(mine[0].dmg)}
	return {"win": winner == "A", "draw": winner == "draw", "ev": ev, "roster": roster, "title": _meta.title,
		"foe": _meta.foe, "aForm": _meta.aForm, "bForm": _meta.bForm, "aSyn": _meta.aSyn, "bSyn": _meta.bSyn, "mvp": mvp,
		"left": live_count("A"), "eLeft": live_count("B"), "turns": turn, "applied": applied, "rejected": rejected, "policy": policy.duplicate(), "stats": stats, "chains": chains,
		"paeup": _paeup_log.map(func(p): return {"camp": p.camp, "id": p.id, "n": p.n, "on": p.on, "have": p.have, "need": p.need, "used": int(_paeup_used.get(p.fx + ":" + p.camp, 0))})}


func live_count(cp: String) -> int:
	return units.filter(func(u): return u.alive and u.camp == cp).size()


func act(u: Unit) -> void:
	if not u.alive: return
	if has_st(u, "confuse"):
		if scheme_enabled and _side_max(_foe(u.camp), "turncoat") > 0:      # 미인계 —— 혼란된 적이 제 편을 친다
			var own := units.filter(func(o): return o.alive and o != u and o.camp == u.camp)
			if not own.is_empty():
				var t: Unit = own[rng.randi() % own.size()]
				stats.turncoats += 1
				_chain(_foe(u.camp), "미인계")
				L("st", "혼란에 빠진 %s 제 편 %s 들이친다" % [ga(nm(u)), eul(nm(t))], {"fx": "status", "f": u.key, "st": "confuse"})
				if is_caster(u.c): int_hit(u, t, 1, 1)
				else: phys_hit(u, t, 1, true)
				return
		L("st", "%s 혼란에 빠져 움직이지 못한다" % ga(nm(u)), {"fx": "status", "f": u.key, "st": "confuse"})
		return
	_turn_start(u)
	var foes := units.filter(func(o): return o.camp != u.camp)
	var allies := units.filter(func(o): return o.camp == u.camp)
	if not foes.any(func(o): return o.alive): return
	# 고유기 —— 자동 정책이면 준비된 차례에 바로 쓴다 (영리한 AI·사람은 _between 에서 끼어든다)
	_gain(u, GAUGE_ACT / gauge_div() * _tw(u, "act"))      # 11/4 신화 1.2배 뺌 (너무 빨랐다). 11/7 기질 배율 · 재사용 감쇠
	var sk = null
	var used := false
	# 일반 기술 (솔국지 확장) —— 원본은 차례마다 확률로 발동. 이제 그 확률만큼 충전이 쌓이고, 다 찬 채로 조건(cards_ext skill_cond)이 맞는 차례에 비용 없이 발동.
	# 11/3 사용자 (빈도 리밸런싱): 기술이 여럿이어도 충전은 하나를 나눠 쓴다 —— 예전엔 기술마다 따로 돌아 신화(기술 3개)는 부대당 한 판에 7.5번 터지고
	# 피해의 73%가 기술이었다. 이제 기술이 많으면 '더 자주'가 아니라 '고를 것이 많다'. 한 차례에 하나만, 앞 기술(고유 기술)부터 조건을 본다
	var sks: Array = u.c.get("sks", [])
	if not sks.is_empty():
		if u.sk_ch.is_empty():
			u.sk_ch.append(0.5)
		var cap := 0.0
		for x in sks:
			cap = maxf(cap, float(x.get("cost", 1.0)))
		u.sk_ch[0] = minf(cap, u.sk_ch[0] + sk_rate(u))      # 가장 비싼 기술 비용만큼 모은다 (더 모아 두지 않는다)
	for j in sks.size():
		if used or not u.alive or not foes.any(func(o): return o.alive):
			break
		if u.sk_ch[0] < float(sks[j].get("cost", 1.0)) or not _sk_cond(u, str(sks[j].get("cond", "always")), foes, allies):
			continue
		sk = sks[j]
		var e: Dictionary = sk.eff
		var ok := true
		if e.get("cond") == "hurt" and u.troops / u.max > 0.5: ok = false
		if ok: u.sk_ch[0] -= float(sk.get("cost", 1.0))
		if ok:
			used = true
			u.in_skill = true
			_sk_on = true
			stats.sk_n += 1
			for o in allies:
				if o != u and o.alive and mv(o, "ally_sk") > 0:      # 연계 —— 아군이 기술을 쓰면 내 기술 충전이 모두 찬다
					for jj in o.sk_ch.size():
						o.sk_ch[jj] = minf(SK_BANK, o.sk_ch[jj] + mv(o, "ally_sk"))
			L("sk", "%s 『%s』%s 펼친다" % [ga(nm(u)), sk.n, "을" if jong(sk.n) else "를"],
				{"fx": "skill", "a": u.key, "name": sk.n, "kind": e.kind})
			match e.kind:
				"phys":
					var ts := resolve_targets(e.tgt, foes, u, allies)
					for t in ts:
						if not t.alive: continue
						phys_hit(u, t, e.mult, false, e.get("pierce", 0.0))
						if e.has("exec") and t.troops > 0 and t.troops / t.max <= e.exec: rout(t, "한 칼에 짓밟혔다")
						if e.has("morale"): morale_hit(t, e.morale, sk.n, ts.size(), u)
						if e.has("spd"): add_buff(t, {"stat": "spd", "amt": e.spd.amt, "dur": e.spd.dur})
						if e.has("foeSpd"): add_buff(t, {"stat": "spd", "amt": e.foeSpd.amt, "dur": e.foeSpd.dur})
						if e.has("defDown"): _cut(u, t, "def", -float(e.defDown.amt) * eff(t, "def"), sk.n)      # 방어 감소 → 파갑(수치)
						if e.has("status"): inflict(u, t, e.status.k, e.status.val, int(e.status.dur))
					if e.has("selfBuff"): add_buff(u, e.selfBuff)
					if e.has("heal"):      # 범용 사기 기술 (진두지휘 · 고함)
						for t in allies:
							if t.alive: _rally(t, e.heal, sk.n) if e.get("rally", false) else heal_morale(t, e.heal, sk.n, u)
					if e.has("stance"): u.buffs.append({"stat": "counter", "amt": float(e.stance.amt), "dur": int(e.stance.dur)})
					if e.has("allyBuff"):
						for t in resolve_targets(e.allyBuff.tgt, foes, u, allies): add_buff(t, e.allyBuff)
				"int":
					var ts := resolve_targets(e.tgt, foes, u, allies)
					for t in ts:
						if not t.alive: continue
						int_hit(u, t, e.mult, ts.size())
						if e.has("morale"): morale_hit(t, e.morale, sk.n, ts.size(), u)
						if e.has("defDown"): _cut(u, t, "def", -float(e.defDown.amt) * eff(t, "def"), sk.n)      # 방어 감소 → 파갑(수치)
						if e.has("status"): inflict(u, t, e.status.k, e.status.val, int(e.status.dur))
						# 11/2 책략 기술의 속도 깎기 (수공 · 혹세의 foeSpd 가 적혀만 있고 쓰이지 않았다)
						if e.has("foeSpd"): add_buff(t, {"stat": "spd", "amt": e.foeSpd.amt, "dur": e.foeSpd.dur})
						if e.has("spd"): add_buff(t, {"stat": "spd", "amt": e.spd.amt, "dur": e.spd.dur})
						if u.caps.has("모사") and rng.randf() < 0.30: inflict(u, t, "confuse", 1, 1)      # 봉인은 혼란으로 합쳤다
					if e.has("heal"):
						for t in allies:
							if t.alive: _rally(t, e.heal, sk.n) if e.get("rally", false) else heal_morale(t, e.heal, sk.n, u)
					if e.has("selfBuff"): add_buff(u, e.selfBuff)
					if e.has("tHeal"):
						for t in allies:
							if t.alive: heal_troop(t, e.tHeal, sk.n, u)
					if e.has("cleanse"):
						var n: int = e.cleanse
						for t in allies:
							if n <= 0: break
							if t.alive and not t.st.is_empty() and cleanse(t): n -= 1
					if e.has("allyBuff"):
						for t in resolve_targets(e.allyBuff.tgt, foes, u, allies): add_buff(t, e.allyBuff)
	u.in_skill = false
	_sk_on = false
	if not used:
		var tt := basic_target(u, foes)
		if not tt.is_empty() and tt[0].alive:
			var mn := _minor(u)
			if not mn.is_empty():
				_do_minor(u, tt[0], mn[0], mn[1], foes, allies)
			elif is_caster(u.c): int_hit(u, tt[0], 1, 1)
			else: phys_hit(u, tt[0], 1)


## 일반 기술 발동 조건 —— DB.cond_text 와 같은 문법. '|' 는 또는
func _sk_cond(u: Unit, cond: String, foes: Array, allies: Array) -> bool:
	var lf := foes.filter(func(o): return o.alive)
	var la := allies.filter(func(o): return o.alive)
	for one in cond.split("|"):
		var kv := one.split(":")
		var v: String = kv[1] if kv.size() > 1 else ""
		match kv[0]:
			"always": return true
			"hurt":
				if u.troops / u.max <= float(v): return true
			"ally_hurt":
				if la.any(func(o): return o.troops / o.max <= float(v)): return true
			"foe_hurt":
				if lf.any(func(o): return o.troops / o.max <= float(v)): return true
			"dense":
				if _dense_max(lf) >= int(v): return true
			"front_n":
				if _front_of(lf).size() >= int(v): return true
			"foe_n":
				if lf.size() >= int(v): return true
			"back_n":      # 11/3 적 후열에 v 부대 이상 (후열을 노리는 기술)
				if lf.filter(func(o): return _is_back(o)).size() >= int(v): return true
			"line":
				var lp: int = int(DB.D.LINE[v].pri) if DB.D.LINE.has(v) else 1
				if lf.any(func(o): return (o.line == v) if not _by_distance() else (_is_front(o) if lp <= 2 else _is_back(o))): return true
			"no_st":
				if lf.any(func(o): return not has_st(o, v)): return true
			"ally_st":
				if la.any(func(o): return o.st.any(func(x): return x.k in ["burn", "bleed", "flood", "plague", "confuse", "seal", "break", "mark"])): return true
			"ally_morale":
				if not la.is_empty() and la.reduce(func(s, o): return s + o.morale, 0.0) / la.size() <= float(v): return true
			"foe_morale":
				if not lf.is_empty() and not la.is_empty():
					var fm: float = lf.reduce(func(s, o): return s + o.morale, 0.0) / lf.size()
					var am: float = la.reduce(func(s, o): return s + o.morale, 0.0) / la.size()
					if fm >= am: return true
	return false


func _do_ult(u: Unit, foes: Array, allies: Array) -> void:
	var ul: Dictionary = u.ult
	u.charges -= 1
	u.gauge = 0.0
	u.ult_n += 1          # 11/7 재사용 체감 —— 이제부터 게이지가 느리게 찬다
	u.ult_tm = _tm
	u.ult_turn = _turn
	_ult_last[u.camp] = act_n
	var cheer := _side_max(u.camp, "ult_rally")      # 고무 —— 아군이 고유기를 쓰면 아군 전원 사기 +
	if cheer > 0:
		for o in units:
			if o.alive and o.camp == u.camp:
				_rally(o, cheer, "고무")
	_in_ult = true
	_ult_by = u
	_ult_taken = {}
	_one = turn_mul
	_long = turn_mul
	var ss := _kv(_foe(u.camp), "ult_block")      # 의성 서성 —— 적의 첫 고유기 한 번은 피해가 없다
	_ult_null = ss != null and int(_kiin_used.get("ult_block:" + ss.camp, 0)) < 2      # 두 번까지
	if _ult_null:
		_kiin_used["ult_block:" + ss.camp] = int(_kiin_used.get("ult_block:" + ss.camp, 0)) + 1
		L("sk", "%s의 장강방벽 —— 고유기를 받아 낸다" % nm(ss), {"fx": "skill", "a": ss.key, "name": "장강방벽", "kind": "phys"})
	var nm_: String = ul.name
	var amp := (tac_hold_amp if _tac(u.camp, 1) == "위기" else crisis_amp) if _crisis(u.camp) else 1.0
	L("sk", "%s 고유기 『%s』 —— “%s”%s" % [nm(u), nm_, ul.shout, " (배수진 —— 위력 ×%.1f)" % amp if amp > 1.0 else ""],
		{"fx": "ult", "a": u.key, "name": nm_, "shout": ul.shout, "vfx": ul.vfx, "crisis": amp > 1.0})
	for comp_ in ul.eff:
		var comp: Dictionary = _amp_comp(comp_, amp)
		var ts := resolve_targets(comp.tgt, foes, u, allies)
		match comp.t:
			"hit":
				for t in ts:
					if not t.alive: continue
					if comp.kind == "phys":
						phys_hit(u, t, comp.mult, false, comp.get("pierce", 0.0))
					else:
						int_hit(u, t, comp.mult, ts.size())
					if comp.has("exec") and t.alive and t.troops > 0 and t.troops / t.max <= comp.exec:
						rout(t, "고유기에 짓밟혔다")
					if comp.has("morale") and t.alive:
						morale_hit(t, comp.morale, nm_, ts.size(), u)
					if comp.has("status") and t.alive:
						inflict(u, t, comp.status.k, comp.status.val, int(comp.status.dur))
			"ally":
				for t in ts:
					if not t.alive: continue
					if comp.has("heal"):
						heal_troop(t, comp.heal, nm_, u)
					if comp.has("morale"):
						heal_morale(t, comp.morale, nm_, u)
					if comp.has("buff"):
						add_buff(t, comp.buff)
					if comp.has("cleanse"):
						for i in int(comp.cleanse):
							if not cleanse(t): break
			"foe":
				for t in ts:
					if not t.alive: continue
					if comp.has("morale"):
						morale_hit(t, comp.morale, nm_, ts.size(), u)
					if comp.has("buff"):
						add_buff(t, comp.buff)
					if comp.has("status"):
						inflict(u, t, comp.status.k, comp.status.val, int(comp.status.dur))
	_in_ult = false
	_ult_by = null
	_ult_null = false
	_one = 1.0
	_long = 1.0


## 단체 특기 —— 전투 시작에 한 번. 같은 이름은 둘까지 겹친다 (센 것 하나 + 두 번째는 절반).
func _apply_group_passives() -> void:
	var got := {}             # 유닛 -> {특기 이름: [배율, …]}
	var owner := {}           # [진영, 이름] -> 가장 센 주인 (기록용)
	for u in units:
		var ps = DB.passives_of(u.c.id)
		if ps == null:
			continue
		for g in ps.groups:
			if _trait_on(g, u.camp):
				_group_from(u, g, got, owner)
	_finish_groups(got, owner)


func _group_from(u: Unit, g: Dictionary, got: Dictionary, owner: Dictionary) -> void:
	var n := 0
	for t in units:
		if _scope_hits(g.scope, u, t):
			if not got.has(t):
				got[t] = {}
			if not got[t].has(g.name):
				got[t][g.name] = []
			got[t][g.name].append(g.scale)
			n += 1
	var ok: String = u.camp + g.name
	if not owner.has(ok) or g.scale > owner[ok][1]:
		owner[ok] = [u, g.scale, n, g]


func _finish_groups(got: Dictionary, owner: Dictionary) -> void:
	for t in got:
		for nm_ in got[t]:
			var sc: Array = got[t][nm_]
			sc.sort()
			sc.reverse()
			var total: float = sc[0] + (sc[1] * 0.5 if sc.size() > 1 else 0.0)
			var base: Dictionary = DB.group_def(nm_).m
			for k in base:
				t.m[k] = t.m.get(k, 0.0) + base[k] * (1.0 if k == "burn_dur" else total)
	for ok in owner:
		var o: Array = owner[ok]
		var cm: Dictionary = DB.group_def(o[3].name).get("cmd", {}) if cmd_links else {}
		for k in cm:
			cmdm[o[0].camp][k] = maxf(cmdm[o[0].camp].get(k, 0.0), cm[k] * o[1])
		L("sk", "%s의 단체 특기 『%s』 — %s" % [nm(o[0]), o[3].name, o[3].d],
			{"fx": "passive", "a": o[0].key, "name": o[3].name, "n": o[2]})
	# 병력·사기는 시작 값에 바로 반영한다
	for u in units:
		if mv(u, "troop") > 0:
			u.max = roundf(u.max * (1.0 + mv(u, "troop")))
			u.troops = u.max
		u.morale = clampf(u.morale + mv(u, "morale") - mv(u, "foe_morale"), 0, 200)


func _scope_hits(scope: String, u: Unit, t: Unit) -> bool:
	if scope == "foe":
		return t.camp != u.camp
	if t.camp != u.camp:
		return false
	if scope == "all":
		return true
	if scope == "fac":
		return t.c.fac == u.c.fac
	if scope.begins_with("tag:"):
		return t.c.tag == scope.substr(4)
	if scope.begins_with("line:"):
		return scope.substr(5).split(",").has(t.line)
	return false



# ───────── 전투 중 개입 ─────────

func _stat(d: Unit, loss: float) -> void:
	stats.dmg += loss
	d.taken += loss
	if _sk_on:
		stats.sk_dmg += loss
	if _in_ult:
		stats.ult_dmg += loss
		stats.ult_hits += 1
		if _buff_sum(d, "uguard") > 0:
			stats.blocked += 1


func _charge(d: Unit, a: Unit, loss: float) -> void:
	if a.countering and not counter_charge:
		return
	_gain(d, GAUGE_HIT * loss / d.max * _tw(d, "hit"))
	_gain(a, GAUGE_DEAL / gauge_div() * _tw(a, "deal"))
	if temper_enabled:      # 11/7 수호 · 분노 —— 아군이 병력을 잃으면 함께 찬다
		for o in units:
			if o != d and o.alive and o.camp == d.camp and o.temper != "":
				var w := _tw(o, "ally")
				if w > 0.0:
					_gain(o, GAUGE_HIT * loss / d.max * w)


## 고유기 게이지가 차는 속도의 나눗수 —— 11/3: 신화 전투(turn_mul 9.8)는 게이지가 판이 끝날 때쯤에야 차서 고유기가 부대당 0.15번뿐이었다.
## 턴 배율이 GAUGE_DIV_MAX 를 넘는 등급은 거기서 멈춘다
const GAUGE_DIV_MAX := 4.5

func gauge_div() -> float:
	return minf(turn_mul, GAUGE_DIV_MAX)


func _buff_sum(u: Unit, stat: String) -> float:
	var s := 0.0
	for b in u.buffs:
		if b.stat == stat:
			s += b.amt
	return s


func can_ult(u: Unit) -> bool:
	return ults_enabled and u.alive and u.ult != null and u.charges > 0 and u.gauge >= 100.0 \
		and not has_st(u, "seal") and act_n - _ult_last[u.camp] >= ULT_SIDE_GAP * turn_mul and _reult_ok(u)


## 행동 사이 —— 이번 행동 번호에 걸린 입력을 처리하고, 영리한 AI 가 판단한다
func _between() -> void:
	_bdone = act_n
	# 양쪽 AI 는 이번 판단 직전의 같은 상황을 보고 동시에 정한다. 예전엔 A 가 먼저 군령을 내리면 B 가 그걸 보고
	# 같은 순간에 방진으로 받아쳐 B 쪽이 늘 유리했다 (영리 대 영리, 덱을 바꿔 붙여도 A 승률 40% 안팎).
	# 사람(A)의 입력도 이 뒤에 처리되므로 AI 가 사람의 군령을 보고 맞대응하지 못한다.
	var seen := {}
	for cp in ["A", "B"]:
		seen[cp] = {"charging": _side_has(_foe(cp), "atk"), "threat": _ult_threat(cp)}
	for inp in inputs:
		if int(inp[0]) == act_n:
			_apply_input(inp)
	for cp in ["A", "B"]:
		if policy[cp] == "smart":
			_smart(cp, "영리", "영리", seen[cp])
		elif str(policy[cp]).begins_with("tac:"):
			var tp: PackedStringArray = str(policy[cp]).split(":")
			_smart(cp, tp[1], tp[2], seen[cp])
		elif policy[cp] == "auto":
			for u in units:
				if u.camp == cp and can_ult(u):
					_interrupt_ult(u)
					break
			if pts[cp] >= CMD_COST:
				_command(cp, "돌격")


func _apply_input(inp: Array) -> void:
	var cp: String = inp[1]
	match inp[2]:
		"ult":
			for u in units:
				if u.key == inp[3] and u.camp == cp:
					if can_ult(u):
						_interrupt_ult(u)
						applied.append(inp)
					else:
						rejected.append([inp, "alive=%s ult=%s charges=%d gauge=%.1f seal=%s gap=%d" % [u.alive, u.ult != null, u.charges, u.gauge, has_st(u, "seal"), act_n - _ult_last[cp]]])
		"cmd":
			if pts[cp] >= CMD_COST and CMDS.has(inp[3]):
				_command(cp, inp[3])
				applied.append(inp)
		"policy":
			policy[cp] = inp[3]
			applied.append(inp)


func _interrupt_ult(u: Unit) -> void:
	_ai += 1
	_ph = "act"
	_who = u.key
	var foes := units.filter(func(o): return o.camp != u.camp)
	var allies := units.filter(func(o): return o.camp == u.camp)
	_do_ult(u, foes, allies)
	check_rout()


func _command(cp: String, name_: String) -> void:
	pts[cp] -= CMD_COST
	_ai += 1
	_ph = "act"
	_who = ""
	var c: Dictionary = CMDS[name_]
	L("sk", "%s 진영 군령 『%s』 —— %s" % ["아군" if cp == "A" else "적", name_, c.d],
		{"fx": "cmd", "camp": cp, "name": name_})
	for u in units:
		if not u.alive or u.camp != cp:
			continue
		for b in c.buffs:
			u.buffs.append({"stat": b.stat, "amt": _cmd_amt(cp, name_, b), "dur": roundi(CMD_TURNS * turn_mul)})
		if c.has("morale"):
			_one = turn_mul
			heal_morale(u, c.morale * (1.0 + cmdm[cp].get("rally", 0.0)), name_, null)
			_one = 1.0


## 특기가 세게 해 주는 군령 수치 —— 맹진은 돌격의 공격, 창진은 방진의 피해 감소, 군주는 재정비
func _cmd_amt(cp: String, name_: String, b: Dictionary) -> float:
	var up := 0.0
	if name_ == "돌격" and b.stat == "atk":
		up = cmdm[cp].get("assault", 0.0)
	elif name_ == "방진" and b.stat == "guard":
		up = cmdm[cp].get("phalanx", 0.0)
	elif name_ == "재정비" and b.stat == "calm":
		return minf(0.9, b.amt * (1.0 + cmdm[cp].get("rally", 0.0)))
	return b.amt * (1.0 + up)


## 영리한 AI —— 고유기는 값어치가 있을 때, 군령은 상대를 보고 고른다
func _smart(cp: String, ult_t: String, cmd_t: String, seen: Dictionary) -> void:
	# 기본은 자동과 같다 (충전되면 쓰고, 포인트는 돌격). 다른 점:
	#  ① 적이 돌격 중이면 방진으로 받는다 —— 적의 공격 상승은 막고, 방어가 내려간 적을 친다
	#  ② 적 광역 고유기가 터지기 직전이면 방진
	#  ③ 회복·격려형 고유기는 아군이 꺾일 때까지 아껴 둔다
	var threat: float = seen.threat
	var foe_charging: bool = seen.charging
	if cmd_t != "공세" and pts[cp] >= CMD_COST and not _side_has(cp, "uguard") and (foe_charging or threat >= 75.0):
		_command(cp, "방진")
	# 11/6 사용자 #14 "책사 고유기가 거의 안 터진다": units 순서(선봉부터)에서 첫 번째 가능한 부대를 쓰고 끝내 뒷줄 책사는 늘 밀렸다
	# → 게이지가 먼저 찬 부대부터, 같으면 등급이 높은 부대
	var ready := []
	for u in units:
		if u.camp == cp and can_ult(u) and _ult_ok(u, ult_t):
			ready.append(u)
	if not ready.is_empty():
		ready.sort_custom(func(x, y):
			if x.ult_ready_t != y.ult_ready_t:
				return (x.ult_ready_t if x.ult_ready_t >= 0.0 else 1e9) < (y.ult_ready_t if y.ult_ready_t >= 0.0 else 1e9)
			return x.c.tier > y.c.tier)
		_interrupt_ult(ready[0])
	if pts[cp] < CMD_COST:
		return
	match cmd_t:
		"공세":
			_command(cp, "돌격")
		"수비":
			# 돌격은 하지 않는다. 사기가 꺾이면 재정비, 포인트가 넘치면 방진을 미리 친다
			if _avg_morale(cp) < 60.0:
				_command(cp, "재정비")
			elif pts[cp] >= PTS_MAX and not _side_has(cp, "guard"):
				_command(cp, "방진")
		_:
			if not foe_charging and threat < 50.0:
				_command(cp, "돌격")


## 작전 정책의 한 부분 —— tac:<고유기>:<군령> 에서 i 번째 (아니면 "")
func _tac(cp: String, i: int) -> String:
	var p := str(policy.get(cp, ""))
	return p.split(":")[i] if p.begins_with("tac:") else ""


func _ult_ok(u: Unit, ult_t: String) -> bool:
	if not _temper_ok(u):
		return false
	match ult_t:
		"즉시":
			return true
		"위기":
			return _crisis(u.camp) or u.troops / u.max < 0.4      # 쓰지도 못하고 쓰러지지 않게
	return _ult_worth(u)


## 덱 연쇄 한 번 —— 세고, 고비(CHAIN_MARKS)마다 사건을 남긴다 (화면이 크게 알린다)
func _chain(cp: String, name_: String, key := "") -> void:
	var n: int = chains[cp].get(name_, 0) + 1
	chains[cp][name_] = n
	if n in CHAIN_MARKS:
		L("sk", "%s 진영 연쇄 『%s』 ×%d" % ["아군" if cp == "A" else "적", name_, n], {"fx": "chain", "camp": cp, "name": name_, "n": n, "a": key})


## 위기 —— 아군이 꺾였는가. 이때 쓴 고유기는 crisis_amp 배 (배수진)
func _crisis(cp: String) -> bool:
	var mine := units.filter(func(o): return o.alive and o.camp == cp)
	var hurt := 0.0
	for o in mine:
		hurt += 1.0 - o.troops / o.max
	return hurt / maxf(1, mine.size()) > CRISIS_LOSS or mine.size() <= CRISIS_UNITS


func _amp_comp(comp: Dictionary, amp: float) -> Dictionary:
	if amp == 1.0:
		return comp
	var c := comp.duplicate()
	if c.t == "hit":
		c.mult = c.mult * amp
	elif c.t == "ally":
		for k in ["heal", "morale"]:
			if c.has(k):
				c[k] = c[k] * amp
	return c


## 방진의 피해 감소 —— 돌격 중인 공격자는 그 일부를 무시한다
func _guard(a: Unit, d: Unit) -> float:
	return _buff_sum(d, "guard") * (1.0 - (breach if _buff_sum(a, "breach") > 0 else 0.0))


func _avg_morale(cp: String) -> float:
	var n := 0
	var m := 0.0
	for o in units:
		if o.alive and o.camp == cp:
			m += o.morale
			n += 1
	return m / maxf(1, n)


func _foe(cp: String) -> String:
	return "B" if cp == "A" else "A"


## 적 진영에서 가장 많이 찬 광역 고유기 게이지
func _ult_threat(cp: String) -> float:
	var g := 0.0
	for u in units:
		if u.camp != cp and u.alive and u.ult != null and u.charges > 0 and _ult_wide(u):
			g = maxf(g, u.gauge)
	return g


func _foe_has_ult(cp: String) -> bool:
	for u in units:
		if u.camp != cp and u.alive and u.ult != null and u.charges > 0:
			return true
	return false


func _side_has(cp: String, stat: String) -> bool:
	for u in units:
		if u.camp == cp and u.alive and _buff_sum(u, stat) > 0:
			return true
	return false


func _ult_wide(u: Unit) -> bool:
	for comp in u.ult.eff:
		if comp.t == "hit" and (comp.tgt in ["all", "front3", "denseLine"] or str(comp.tgt).begins_with("line:")):
			return true
	return false


func _ult_phys(u: Unit) -> bool:
	for comp in u.ult.eff:
		if comp.t == "hit" and comp.kind == "phys":
			return true
	return false


## 11/7 기질 —— 고유기 데이터의 "temper" 가 있으면 그것, 없으면 규칙: 아군 회복 · 강화만 하면 수호, 책략계 병종이면 지략,
## 궁병 · 도적은 저격, 타격 없이 적 상태이상만 걸면 지략, 그 밖은 맹장
func temper_of(u: Unit) -> String:
	if u.ult == null:
		return ""
	return temper_name(u.c, u.ult)


## 카드 · 고유기 데이터만으로 기질 이름 (화면도 쓴다 —— 디테일창)
static func temper_name(c: Dictionary, ult: Dictionary) -> String:
	var t := str(ult.get("temper", ""))
	if TEMPER.has(t):
		return t
	var ally_only := true
	var foe_status := false
	var hit := false
	for comp in ult.eff:
		if comp.t == "hit":
			hit = true
			ally_only = false
		elif comp.t == "foe":
			ally_only = false
			if comp.has("status"):
				foe_status = true
	if ally_only:
		return "수호"
	if is_caster(c):
		return "지략"
	if c.tag == "궁병" or c.tag == "도적":
		return "저격"
	if foe_status and not hit:
		return "지략"
	return "맹장"


## 기질 한 줄 설명 (디테일창 · 카드)
const TEMPER_DESC := {
	"맹장": "때릴수록 기가 빨리 찬다. 적과 맞닿으면 쓴다",
	"수호": "맞거나 아군이 다칠수록 기가 찬다. 아군이 다쳤을 때 쓴다",
	"지략": "차례마다 꾸준히, 상태이상을 걸면 더 찬다. 맞힐 적이 둘 넘으면 쓴다",
	"저격": "때리고 적을 무너뜨릴수록 기가 찬다. 약해진 적이 사거리 안이면 쓴다",
	"분노": "맞거나 아군이 무너질수록 기가 빨리 찬다. 아군이 무너지거나 병력 70% 아래면 쓴다",
}


## 기질 가중치 —— 기질이 없거나(고유기 없음) 꺼져 있으면 배율 1 · 덧셈 0
func _tw(u: Unit, key: String) -> float:
	if not temper_enabled or u.temper == "" or not TEMPER.has(u.temper):
		return 1.0 if key in ["act", "deal", "hit", "wait"] else 0.0
	return float(TEMPER[u.temper][key])


func _gauge_add(u: Unit, v: float) -> void:
	if v > 0.0 and u.alive and u.ult != null and u.charges > 0:
		_gain(u, v)


## 게이지 더하기 —— 11/7 재사용 체감: n번 쓴 장수는 reult_decay^n 배로 느리게 찬다
func _gain(u: Unit, v: float) -> void:
	if v <= 0.0:
		return
	u.gauge = minf(100.0, u.gauge + v * (pow(reult_decay, u.ult_n) if u.ult_n > 0 else 1.0))      # n번 쓴 장수는 reult_decay^n 배로 (쓸수록 어렵게)


## 고유기 한 방 상한 (11/7 2차) —— 이번 고유기에 이 부대가 잃는 병력은 최대 병력 × ult_cap[쓴 장수 등급] 까지.
## 사람이 누른 고유기 · AI 고유기 모두 _do_ult 를 지나므로 같다. 고유기 중 받은 반격(쓴 장수가 잃는 병력)에도 같은 상한
func _ult_clamp(d: Unit, loss: float) -> float:
	var cap := float(ult_cap.get(clampi(int(_ult_by.c.tier), 6, 8), 0.0))
	if cap <= 0.0:
		return loss
	var got: float = _ult_taken.get(d, 0.0)
	var out := clampf(cap * d.max - got, 0.0, loss)
	_ult_taken[d] = got + out
	if out < loss:
		stats["ult_capped"] = int(stats.get("ult_capped", 0)) + 1
	return out


## 다시 쓸 수 있는가 —— 턴 엔진: 쓴 지 3턴 (RtBattle 은 대기 시간 × reult_wait 초로 덮어쓴다)
func _reult_ok(u: Unit) -> bool:
	return u.ult_n == 0 or _turn - u.ult_turn >= 3


## 기질 발동 조건 (영리 AI · 자동 판단에만 —— 사람이 직접 누르는 것은 그대로). TEMPER_FREE 가 지나면 조건 없이
func _temper_ok(u: Unit) -> bool:
	if not temper_enabled or u.temper == "" or _ult_free_now():
		return true
	var foes := units.filter(func(o): return o.alive and o.camp != u.camp)
	var mine := units.filter(func(o): return o.alive and o.camp == u.camp)
	match u.temper:
		"맹장":
			return _touching_foe(u)
		"수호":
			var hurt := 0.0
			for o in mine:
				hurt += 1.0 - o.troops / o.max
			return hurt / maxf(1, mine.size()) > 0.10 or _crisis(u.camp)
		"지략":
			return _ult_reach_n(u, foes) >= 2 or foes.size() <= 3
		"저격":
			return _foe_low_in_reach(u, foes)
		"분노":
			return u.troops / u.max < 0.7 or units.any(func(o): return o.camp == u.camp and not o.alive)
	return true


## 기질 조건이 풀리는 때 —— 실시간 엔진은 TEMPER_FREE 초 (RtBattle 이 덮어쓴다), 턴 엔진은 6턴
func _ult_free_now() -> bool:
	return _turn > 6


## 맞닿은 적이 있는가 —— 턴 엔진은 자리가 없어 늘 참 (RtBattle 이 덮어쓴다)
func _touching_foe(_u: Unit) -> bool:
	return true


## 병력 60% 아래인 적이 사거리 안에 있는가 (RtBattle 이 사거리로 덮어쓴다)
func _foe_low_in_reach(_u: Unit, foes: Array) -> bool:
	return foes.any(func(o): return o.troops / o.max < 0.7)


func _ult_worth(u: Unit) -> bool:
	var mine := units.filter(func(o): return o.alive and o.camp == u.camp)
	var foes := units.filter(func(o): return o.alive and o.camp != u.camp)
	if foes.is_empty() or mine.is_empty():
		return false
	var hurt := 0.0
	var low_morale := 0.0
	for o in mine:
		hurt += 1.0 - o.troops / o.max
		low_morale += 1.0 if o.morale < 60 else 0.0
	hurt /= mine.size()
	var support := true
	var wide := false
	for comp in u.ult.eff:
		if comp.t != "ally":
			support = false
		if comp.has("tgt") and comp.tgt in ["all", "front3", "denseLine"] or str(comp.get("tgt", "")).begins_with("line:"):
			wide = true
	if support:
		return hurt > 0.3 or low_morale >= mine.size() * 0.4      # 아군이 꺾였을 때 아껴 둔 회복·격려
	if wide:      # 11/6 사용자 #14 "책사 고유기가 거의 안 터진다": '적 4부대 이상' 이라 게이지가 찰 무렵엔 영영 못 썼다 → 맞힐 수 있는 적 2 이상이거나 적이 3 이하로 줄었으면
		return _ult_reach_n(u, foes) >= 2 or foes.size() <= 3
	return true                                                    # 단일 대상은 바로


## 광역 고유기가 지금 맞힐 수 있는 적 수 —— 턴 엔진은 자리가 없어 전부, 실시간 엔진은 사거리 안만 (RtBattle 이 덮어쓴다)
func _ult_reach_n(_u: Unit, foes: Array) -> int:
	return foes.size()


func _pick_cmd(cp: String) -> String:
	var mine := units.filter(func(o): return o.alive and o.camp == cp)
	var foes := units.filter(func(o): return o.alive and o.camp != cp)
	if mine.is_empty() or foes.is_empty():
		return ""
	var morale := 0.0
	var phys := 0
	for o in mine:
		morale += o.morale
		if DB.PHYS_TAGS.has(o.c.tag):
			phys += 1
	morale /= mine.size()
	var foe_melee := 0
	for o in foes:
		if o.c.tag in ["창병", "기병", "도적"]:
			foe_melee += 1
	var foe_int := foes.size() - foe_melee
	if morale < 55:
		return "재정비"                     # 사기가 꺾였으면 무너지기 전에 추스른다
	if foe_melee * 3 >= foes.size() * 2:
		return "방진"                       # 근접이 몰려오면 버틴다
	if foe_int * 3 >= foes.size() * 2 and morale < 80:
		return "재정비"                     # 책략으로 사기를 깎는 상대
	return "돌격"
