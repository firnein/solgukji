class_name RtBattle
extends Battle
## 실시간 전투 엔진 (10/30 사용자: 삼국지11 쪽 · 실시간 · 위치로 피격 판정)
##
## 판정 공식 · 특기 · 상태 · 고유기 · 군령은 Battle 을 그대로 쓰고, 두 가지를 바꾼다.
##  ① 차례 —— 턴 순서 대신 TICK(0.1초)마다 시간이 흐른다. 유닛마다 행동 준비(atb)가 차고,
##     다 찬 채로 사거리 안에 적이 있으면 그때 친다. 턴 끝 정산(사기 · 회복 · 상태 · 패주)은 PERIOD 초마다.
##  ② 대상 —— 앞열 · 후열 규칙 대신 실제 위치. 근접은 맞닿은 적만, 궁병 · 지략은 사거리 안의 적만 친다.
##     맞닿은 적이 있으면 묶인다(그 적부터 상대). 범위 기술은 대상 둘레 · 늘어선 줄 · 사거리 안 전체로.
##     옆에서 치면 피해 +SIDE, 뒤에서 치면 +REAR. 반격은 맞닿은 근접 공격에만.
## 같은 시드 · 같은 입력이면 같은 결과 (서버 판정 · 재계산 그대로). 화면은 위치 기록(track)을 따라 움직인다.

const TICK := 0.1
static var SETTLE := 0.2       # 정산(사기 · 회복 · 지속 피해 · 패주)을 나눠 하는 간격 (초) —— 11/3 사용자: 턴 끝에 한꺼번에 툭 바뀌던 것을 촘촘히
const PERIOD_MUL := {3: 1.75, 4: 0.8, 5: 0.65, 6: 0.51, 7: 0.41, 8: 0.51}   # 등급별 턴 간격 배율 —— 같은 등급 31~38초 (11/1 측정 · 자동 감상 전투라 줄였다). 11/7 군집 강체로 초월 이상이 38~45초로 길어져 초월 0.55 → 0.51 · 불멸 0.53 → 0.41 · 신화 0.6 → 0.51 (측정 36 · 38 · 36초. 불멸 0.39 는 38초 그대로에 시간 끝 판만 늘어 0.41)
const BATTLE_SEC := 35.0                # 같은 등급 감상 전투의 보통 길이 (초) —— 카드 설명의 '전투 동안' 수치용 (11/3)


## 그 등급 전투 한 판의 턴 수 (보통 길이 기준)
static func turns_for(t: float) -> float:
	return BATTLE_SEC / turn_sec(t)


## 그 등급 전투의 한 턴(정산 간격) 길이 (초) —— 화면 설명의 'N턴'을 초로 바꿀 때 (DB.sec_text). 1·2등급은 3등급과 같게
static func turn_sec(t: float) -> float:
	return period_base * PERIOD_MUL[clampi(roundi(t), 3, 8)]


static var period_base := 1.9           # 예전 한 턴에 해당하는 시간 (초) —— 턴 끝 정산 간격 · 행동 간격의 기준. 11/1 2.9→1.9 (감상 전투 35초 안팎)
const TRACK_EVERY := 0.4      # 위치 기록 간격 (초)
const ARENA := Rect2(-560, -480, 1120, 960)     # 기본 전장 (실제 판은 arena —— 진형 자리 · 발자국에 맞춰 run() 이 정한다)
var arena := ARENA
const BODY := 28.0            # (예전 원형 부대 반지름 —— 지금은 발자국(hw · hd)을 쓴다)
const CONTACT := 64.0         # (예전 맞닿음 중심 거리 —— 화면 호환용, 판정은 TOUCH 틈)

# ───────── 군집 강체 (11/7 사용자: 군집은 다른 군집을 뚫고 들어갈 수 없다 —— 기본 물리의 느낌) ─────────
## 부대마다 대열 발자국(앞뒤 반깊이 hd · 좌우 반폭 hw 의 직사각형, 방향 fwd)을 둔다. 크기는 병사 수(PV · 병력)로 정하되 진형 칸(CS · RS)에 맞게 상한.
## 움직임은 속도 벡터(가속 ACC_T · 감속 DEC_T 초), 돌기는 TURN_RATE —— 옆 부대를 더 파고드는 회전은 줄인다.
## 틱마다 발자국끼리 겹치지 않게 푼다(_solve, SOLVE_ITERS 번) —— 아군은 ALLY_GAP 틈, 맞붙은 적은 FOE_MIX 만큼만 파고든다. 병력이 많은 쪽이 덜 밀린다(떠밀기).
## 맞닿음(TOUCH) · 근접 사거리(melee_gap) · 원거리 사거리는 모두 발자국 가장자리 사이 틈(_gap)으로 잰다.
## 병력이 줄면 깊이가 뒤에서부터 줄어든다(앞줄 고정). 앞이 막힌 부대는 막은 부대를 비켜 옆으로 흘러간다(_steer) —— 예비대가 측면으로 돈다.
const FP_SPREAD := 1.35       # 병사 간격 배율 (Type2View 가 넓혀 그리던 값을 발자국에 넣었다)
const FP_SP := {"기병": 12.0, "책사": 8.5, "유생": 8.5, "술사": 8.5, "모사": 8.5}     # 병사 간격 (px) —— 그 밖은 7.0
const FP_RATIO := {"기병": 2.0, "책사": 2.0, "유생": 2.0, "술사": 2.0, "모사": 2.0}   # 폭 : 깊이 —— 그 밖은 2.6 (넓고 얇은 가로줄)
const FP_TIER := {6: 1.1, 7: 1.2, 8: 1.32}       # 초월 위는 정예라 넓게 선다 (Squad.TIER_SIZE 와 같게)
const FP_PER_PV := 5.5        # PV 1 당 기준 병사 수 (Squad.PER_PV 와 같게)
const FP_FEW := 12000.0       # 이 병력 아래 부대는 작게 (Squad.FEW_TROOPS)
const CELL_W := 0.86          # 발자국 폭 상한 —— 열 간격(CS · lay)의 비율. 옆 부대와 틈 약 30px
const CELL_D := 0.80          # 깊이 상한 —— 행 간격(RS · lay)의 비율
const TOUCH := 6.0            # 가장자리 틈이 이 안이면 맞닿음(묶임)
static var melee_gap := 70.0  # 근접 공격이 닿는 가장자리 틈 —— 예전 중심 거리 130 과 같은 몫(130 − 반지름 28 × 2 ≈ 74): 앞 부대 바로 뒤의 작은 둘째 줄은 앞 부대 너머로 친다. 22 로 두면 전투가 20~30% 길어졌다 (11/7 측정)
static var ALLY_SEP := 2.7         # (예전 값 —— 점검 장면 호환용)
const AREA_GAP := 40.0        # '둘레' 범위 기술(front3 · denseLine) —— 대상 발자국과 틈이 이 안인 적
const ALLY_GAP := 8.0         # 아군 발자국 사이 최소 틈
const FOE_MIX := 6.0          # 맞붙은 적끼리 이만큼은 파고든다 (앞줄이 섞인다)
const SOLVE_ITERS := 3
const ACC_T := 0.6            # 멈춤 → 제 속도까지 (초)
const DEC_T := 0.4            # 제 속도 → 멈춤 (초)
const HD_MIN := 6.0
const LOOK := 60.0            # 앞을 살피는 거리 (px) —— 이 안에 막은 부대가 있으면 비켜 간다
## 11/19 전투 알고리즘 고도화 (사용자 목표) —— 이동 감사(tests/algo_audit) 기준: 옆걸음 29.6% · 갈지자 판당 11.8회 · 원거리 막혀 선 시간 판당 47.8초.
##  ① 비켜 가기 관성: 비켜 갈 쪽을 한 번 고르면 그 길이 막힐 때까지 지키고, 막힘이 풀린 뒤에도 STEER_KEEP 초 동안 같은 쪽 성분을 줄여 가며 푼다
##     (틱마다 더 트인 쪽을 다시 골라 좌우로 꺾이고, 풀리자마자 곧장 꺾어 다시 걸리던 갈지자)
##  ② 가는 쪽 보기: 노리는 적과 틈이 FACE_GAP 보다 멀고 실제로 걷고 있으면 적이 아니라 가는 방향을 본다 (돌아갈 때 적을 보며 게걸음하던 것). 가까워지면 적을 본다
##  ③ 원거리 대기: 앞이 아군에 막힌 원거리가 제자리에서 기다리는 시간 3초 → RANGED_WAIT (사거리 안에 적이 없는데 서 있기만 했다)
## 셋 다 끄면(algo_v2 = false) 예전 움직임 그대로 —— 전후 비교 · 점검용
static var algo_v2 := true
## 11/19 공정한 처리 순서 —— 틱마다 부대를 units 순서(A 진영 전부 → B 진영 전부)로 움직이고 행동시켜, 같은 덱을 진영만 바꿔 돌려도 A 쪽이 더 이겼다
## (tests/algo_audit 진영 교체 600판에서 A 승률 약 55%). 온라인 대전은 한쪽이 늘 A 라 그 사람이 덕을 본다.
## 거울 대전(같은 덱 · 같은 진형) 480판: A 승률 67.2%. 가장 큰 까닭은 고유기 전역 간격(ult_gap) —— 대기 시간이 풀리는 틱에 양쪽이 함께 준비되면
## 먼저 처리되는 A 가 늘 선수를 잡고, B 는 2.5초를 더 기다렸다.
## 두 진영을 번갈아 세운 순서(A0 B0 A1 B1 …)를 쓰고, 먼저 하는 진영은 틱마다 시드 · 틱 번호 해시로 정한다 (짝 · 홀로 번갈면 14.0초 같은 정각 틱이
## 늘 같은 쪽이라 58.1% 가 남았다). 전투 난수(rng)는 건드리지 않는다 —— 같은 시드면 같은 결과. units 자체(사건 기록의 부대 번호)는 그대로
static var fair_order := true
static var fair_debug := 0
var _ord_ab: Array = []
var _ord_ba: Array = []
var _tick_n := 0
var _tick_b_first := false
var _fair_seed := 0
## 켤 것 (비트) —— 1 비켜 가기 관성 · 2 가는 쪽 보기 · 4 원거리 다가서기 · 대기. 기본 5 (① + ③).
## 240판 진영 교체 측정(11/19): 예전 → ①+③: 원거리 막혀 선 시간 51.0 → 25.1초/판 · 원거리 노는 시간 31.8 → 25.6% · 근접 노는 시간 24.0 → 22.5% ·
## 전투 길이 36.8 → 35.7초 · 병종별 피해 ±3% 안. ②(가는 쪽 보기)는 옆걸음을 28.5 → 22.5%(근접만) / 8.5%(원거리 포함)로 줄이지만
## 갈지자(판당 12.5 → 17.7회)와 원거리 막힘이 늘어 기본에서는 끈다 —— 삽화 화면은 병사 그림이 가는 쪽을 보게 이미 처리한다
static var algo_bits := 5
const STEER_KEEP := 0.5
const FACE_GAP := 70.0
const FACE_SPEED := 12.0      # 이보다 느리면(거의 섰다) 적을 본다
const FACE_LEAN := 0.6        # 붐비는 곳에서 가는 쪽으로 트는 한도 (라디안, 약 34도)
const FACE_CLEAR := 30.0      # 둘레가 이만큼 비어 있을 때만 가는 쪽을 본다
const RANGED_CLOSE := 12.0    # ③ 원거리는 앞 아군과 틈이 이만큼 남을 때까지는 계속 다가선다 (LOOK 60px 앞에서 멈춰 사거리를 버리지 않게)
const RANGED_WAIT := 1.2
## 11/19 점검 (tests/algo_audit) —— 이동 알고리즘 감사: 틱마다 실제로 움직인 방향과 부대가 보는 방향을 견줘 옆걸음 · 뒷걸음 · 갈지자 · 막혀 선 시간을 stats 에 센다.
## 켜도 판정 · 난수 · 사건 기록은 그대로 (세기만 한다)
static var algo_probe := false
var _ap_pos := {}      # 유닛 -> 지난 틱 자리
var _ap_dir := {}      # 유닛 -> 지난 틱 이동 방향 (움직였을 때만)
var _ap_met := false   # 첫 맞닿음이 있었는가
static var rigid_probe := false     # 점검 (tests/rigid_check) —— 풀고 난 뒤 남은 겹침 · 막힌 시간 · 측면으로 돈 시간을 stats 에 센다


## 부대 발자국 (반폭, 반깊이) —— 엔진 · 화면이 같은 식을 쓴다 (품질 설정과 무관하게 결정적)
static func footprint(c: Dictionary, max_troops: float, lay: float) -> Vector2:
	var tag := str(c.get("tag", ""))
	var few := sqrt(clampf(max_troops / FP_FEW, 0.3, 1.0))
	var n := float(c.get("pv", 20)) * FP_PER_PV * few
	if tag == "기병":
		n *= 0.75
	elif FP_SP.has(tag):
		n *= 0.7
	var sp: float = FP_SP.get(tag, 7.0) * FP_TIER.get(int(c.get("tier", 3)), 1.0) * FP_SPREAD
	var ratio: float = FP_RATIO.get(tag, 2.6)
	var area := n * sp * sp
	var w := minf(sqrt(area * ratio), CS * lay * CELL_W)
	var d := minf(area / w, RS * lay * CELL_D)
	return Vector2(maxf(w, 44.0) * 0.5, maxf(d, 18.0) * 0.5)
const GAP := 300.0      # 양군 선봉 사이 (11/4 240 → 300)
const RS := 150.0      # 11/4 사용자: 대열 칸 자체를 키운다 —— 앞뒤 열 간격 78 → 150 (깊은 부대가 앞뒤로 겹쳐 번졌다)
const CS := 210.0      # 열 간격 (11/4 118 → 175 → 220, 11/6 5열로 165, 11/7 사용자 '더 넓은 범위로' 210 —— 전체 폭 840, RtBattle · War3D 같게)
const LANE_W := 1.7    # 11/7 근접 부대가 적을 고를 때 옆(가로) 거리를 이만큼 무겁게 —— 자기 앞 열의 적부터 (다들 가운데로 몰리지 않게)
const TAUNT_R := 160.0
## 11/5 사용자: 병사가 적으면 진형을 촘촘하게 시작 —— 양군 병력 합이 LAY_FULL 아래면 열 · 좌우 간격을 √(합 / LAY_FULL) 배 (최소 LAY_MIN),
## 선봉 사이(GAP)는 그 30% 만큼만 줄인다. 1일차(합 1.5만) 0.62 · 3일차(6만) 0.63~0.7 · 후반(15만 이상) 1
static var compact_enabled := true
const LAY_FULL := 150000.0
const LAY_MIN := 0.62
var lay := 1.0
const SPEED := {"창병": 62.0, "도적": 105.0, "기병": 95.0, "궁병": 55.0, "책사": 50.0, "유생": 50.0, "술사": 50.0, "모사": 50.0}
static var bow_range := 250.0      # 궁병 사거리 (점검 장면이 바꿔 볼 수 있게 static)
static var cast_range := 220.0     # 지략 계열(책략으로 치는 유닛) 사거리
static var melee_reach := 130.0    # (예전 근접 중심 거리 —— 11/7 강체부터 판정은 melee_gap 틈. 점검 장면 호환용으로 남김)
static var melee_bank := 2.0       # 근접은 행동 준비를 이만큼 모아 둔다 —— 걸어가는 동안 쌓았다가 닿자마자 몰아 친다
static var int_mul := 0.6          # 책략 피해 배율 —— 후열이 안전해진 만큼 (고유기 제외). 등급별 INT_TIER 를 곱한다
static var int_tier := {3: 1.5, 4: 1.35, 5: 0.85, 6: 0.7, 7: 0.75, 8: 0.8}   # 공격자 카드 등급별 책략 배율 (10/31 측정 —— 낮은 등급 지략이 약하고 높은 등급이 세다)
## 11/19 사용자: 기병 전투는 빨리 끝나 좋은데 나머지는 지루하다 —— 몰빵 거울전 첫 부대 무너짐이 기병 6초 · 나머지 9~19초 (tests/class_tempo).
## 기병 돌격(cav_charge) · 창병 붙는 순간(spear_impact)이 없는 병종도 첫 공격 한 번을 세게 (반격 · 고유기 제외)
static var first_strike := {}      # 11/19 첫 공격 1.6배는 첫 무너짐을 못 당겼다(궁병 9.4 → 9.9초) —— 비워 둔다
## 11/19 A2 반복되는 결정타 —— 기병은 돌격이 판당 14번 되풀이되어 빨리 끝난다. 다른 전투 병종도 N 번째 차례마다 그 차례의 타격 전부 heavy_mul 배
## (반격 · 고유기 제외. 지원 병종 술사 · 모사 · 유생은 뺀다)
static var heavy_every := {}      # 11/19 4번째 · 1.6배를 해 봤으나 거울전 첫 무너짐이 0~1초만 당겨졌다 —— 비워 둔다
static var heavy_mul := 1.6
static var cav_charge := 1.6       # 기병 돌격 —— CHARGE_RUN 넘게 달려와 친 첫 물리 공격 피해 배율
const CHARGE_RUN := 120.0
static var near_mul := 1.5         # 맞닿아 친 물리 피해 배율 (삼국지11 —— 근접이 세다)
static var far_mul := 0.85          # 떨어진 곳(활 · 책략)에서 친 피해 배율 —— 근접은 맞닿아야만 쳐서 덜 치므로 맞춘다
const AREA := 95.0            # 둘레 범위 (front3 · denseLine)
static var all_r := 320.0   # '적 전체' 기술이 닿는 거리 (고유기는 아래 ult_all_r)
## 11/7 고유기 밸런스 2차 (사용자: "고유기가 거의 모든 범위에 효과가 있다") —— 고유기의 '적 전체'(all)는 전장 전체가 아니라
## 노리는 적(맞붙은 적 · 없으면 가장 가까운 적) 둘레 반지름 ult_all_r 안의 적. 가장자리가 원에 걸치면 맞는다. 0 이면 예전처럼 전장 전체
## 측정(같은 등급 30판, 반지름은 노리는 적 한가운데에서 발자국 가장자리까지): 신화 '적 전체' 고유기 번당 맞는 부대 5.7~6.2 → 3.3~3.6 (300 이면 2.4~2.9 · 220 이면 1.9 로 너무 좁다),
## 신화 고유기 한 번 평균 증발 12.0 → 9.9% (한 방 상한과 함께)
static var ult_all_r := 380.0
static var ult_all_n := 0     # 그 가운데 가까운 순으로 최대 이만큼 (0 이면 제한 없음)
const LINE_W := 45.0          # 줄 범위의 반폭
const SIDE := 0.15            # 옆에서 친 피해 +
const REAR := 0.30            # 뒤에서 친 피해 +
const TURN_RATE := 2.5        # 부대가 도는 속도 (라디안/초)

static var flank_spd := 1.8             # 11/22 사용자 "우회가 너무 오래 걸린다" —— 우회 길목으로 도는 동안(도적 · 장합 우회 기병) 이동 속도 배율
static var probe_rogue_flank := true    # 11/8 점검 (tests/mono_league --off=우회) —— 끄면 도적이 적 무리 옆으로 크게 돌지 않고 곧장 간다
static var probe_back_basic := true     # --off=후열평타: 도적의 후열 평타 비교용. 원거리는 이 스위치와 무관하게 사거리 안 최근접 적.
static var enabled := true    # 게임 · 서버의 전투를 실시간 엔진으로 (false 면 예전 턴 엔진 —— 비교용)

# 지형 (삼국지11) —— 판마다 시드로 좌우 대칭이 되게 깐다. 숲 · 언덕 {k, x, y, r} · 강 {k: "river", x, w(반폭)}
static var terrain_enabled := false     # 11/2 사용자: 지형효과 제거 (숲 · 강 · 언덕 —— 판정 · 화면 모두)
const FOREST := {"def": 0.85, "arrow": 0.8, "burn": 1.5, "move": 0.8}    # 숲 안의 부대: 받는 물리 ×, 떨어진 곳에서 맞는 물리 추가 ×, 화상 ×, 이동 ×
const RIVER := {"hurt": 1.15, "move": 0.55}                            # 강 안의 부대: 받는 물리 × · 이동 ×
const HILL := {"hit": 1.15, "range": 1.2, "move": 0.85}                 # 언덕 위에서 아래를 치면 × · 원거리 사거리 × · 이동 ×
var terrain := []
var period := 2.9         # 이번 전투의 턴 간격 (평균 등급으로 PERIOD_MUL 을 곱한다)
var track := []               # [[시각, [x, y, 방향각, 대상 번호(-1), 맞닿음 0/1] × 유닛]]
var _next_track := 0.0
var _idx := {}                # 유닛 -> 번호


## 게임에서 쓰는 엔진을 만든다 —— 실시간(기본) 또는 예전 턴 엔진
static func make(seed_value: int) -> Battle:
	return RtBattle.new(seed_value) if enabled else Battle.new(seed_value)


## 이번 전투의 한 턴 길이 (초) —— 전투 기록의 지속 표시용
func _turn_sec() -> float:
	return period


## 결정적 순서로 유닛을 놓고 시간을 흘린다
func run(a_cards: Array, a_form: String, a_morale: float, a_equip, b_cards: Array, b_form: String,
		b_morale: float, b_equip, title := "", foe_name := "", inputs_ := [], policy_ := {}) -> Dictionary:
	_make_terrain(rng.seed)
	_fair_seed = int(rng.seed)
	lay = 1.0
	if compact_enabled:
		var tr := 0.0
		for k in a_cards + b_cards:
			if k != null and DB.C.has(str(k)):
				tr += float(DB.C[str(k)].tr)
		lay = clampf(sqrt(tr / LAY_FULL), LAY_MIN, 1.0)
	var tp = policy_.get("plan")      # 11/15 군략 카드 —— 양쪽 계획은 정책과 같은 길로 온다 (Run.policy_for). 정책에서는 떼어 낸다
	var pol := policy_
	if tp != null:
		pol = policy_.duplicate()
		pol.erase("plan")
	_setup(a_cards, a_form, a_morale, a_equip, b_cards, b_form, b_morale, b_equip, title, foe_name, inputs_, pol)
	for i in units.size():
		_idx[units[i]] = i
	var ua: Array = units.filter(func(o): return o.camp == "A")
	var ub: Array = units.filter(func(o): return o.camp != "A")
	_ord_ab = []
	_ord_ba = []
	for i in maxi(ua.size(), ub.size()):
		if i < ua.size():
			_ord_ab.append(ua[i])
		if i < ub.size():
			_ord_ab.append(ub[i])
			_ord_ba.append(ub[i])
		if i < ua.size():
			_ord_ba.append(ua[i])
	if inyeon_theme and inyeon_enabled:
		_yeon_up_setup()
	_sg = load("res://scripts/sig_rt.gd").make(self) if sig_enabled else null      # 11/19 장수 개성 —— 개성 키가 있는 판에만
	if _sg != null:
		_sg.setup()
	# 전장 범위 —— 진형 자리 · 발자국에 맞춘다 (앞뒤로 반 행, 옆으로 한 열 남짓 여유: 예비대가 측면으로 돌 자리)
	var xh := 0.0
	var yh := 0.0
	for u in units:
		xh = maxf(xh, absf(u.pos.x) + u.hd)
		yh = maxf(yh, absf(u.pos.y) + u.hw)
	xh += RS * lay * 0.5
	yh += CS * lay * 0.9
	arena = Rect2(-xh, -yh, xh * 2.0, yh * 2.0)
	# 처음 행동 준비 —— 빠른 유닛이 먼저 (예전 턴 순서의 속도 정렬). 선제 특기 · 첫 턴 기병은 바로
	for u in units:
		var sp := eff(u, "spd") * (1 + rnd(-0.15, 0.15))
		u.atb = clampf(0.35 + sp / 220.0, 0.35, 0.95)
		if mv(u, "first") > 0 or (u.caps.has("기병") and u.c.tag == "기병"):
			u.atb = 1.0
	var ts := 0.0
	for u in units:
		ts += u.c.tier
	var mt := clampf(ts / maxf(1, units.size()), 3.0, 8.0)
	var lo_t := floori(mt)
	var hi_t := mini(8, lo_t + 1)
	period = period_base * lerpf(PERIOD_MUL[lo_t], PERIOD_MUL[hi_t], mt - lo_t)
	var turn := 1
	_turn_begin(turn)
	var winner := ""
	var cap_t: float = K.cap * turn_mul * period
	var next_end := period
	var next_set := SETTLE
	var last_set := 0.0
	if tp != null:
		tac = load("res://scripts/tac_rt.gd").make(self, tp)
	if tac != null:
		tac.tick()      # 1단계 공개 —— 시작하자마자
	_record()
	while _tm < cap_t and winner == "":
		_tm += TICK
		if tac != null:
			tac.tick()
		_tick_n += 1
		_tick_b_first = (hash(_fair_seed * 31 + _tick_n * 7919) >> 5) & 1 == 1
		if fair_debug != 0:      # 점검용 —— 1 이면 늘 A 먼저, 2 면 늘 B 먼저
			_tick_b_first = fair_debug == 2
		var tp0 := Time.get_ticks_usec() if algo_probe else 0
		_move()
		if algo_probe:
			var tp1 := Time.get_ticks_usec()
			stats["us_move"] = stats.get("us_move", 0) + tp1 - tp0
			tp0 = tp1
		_fire_winds()
		_dash_tick()
		_paeup_tick(TICK)
		if _sg != null:
			_sg.tick(TICK)
		for u: Unit in _tick_units():
			if not u.alive:
				continue
			if u.gauge >= 100.0 and u.ult_ready_t < 0.0:
				u.ult_ready_t = _tm
			var atb_cap := 1.0 if u.ranged else melee_bank
			if u.atb != atb_cap or probe_on:      # 11/15 성능: 이미 가득 찬 준비는 더해도 그대로다 —— 행동 간격(eff)을 재지 않는다
				u.atb = minf(atb_cap, u.atb + TICK / _interval(u))
			if u.atb >= 1.0 and not _ready_to_hit(u):
				_idle_gauge(u, TICK)
				var wk := "wait_r" if _ranged(u) else "wait_m"      # 점검용 —— 준비가 다 찼는데 닿는 적이 없어 노는 시간
				stats[wk] = stats.get(wk, 0.0) + TICK
				if not _ranged(u) and u.tgt != null:
					var dd := u.pos.distance_to(u.tgt.pos)
					stats["idle_d"] = stats.get("idle_d", 0.0) + dd * TICK
					var bucket := "idle_near" if dd < 120.0 else ("idle_mid" if dd < 300.0 else "idle_far")
					stats[bucket] = stats.get(bucket, 0.0) + TICK
			if u.atb >= 1.0 and _ready_to_hit(u):
				u.atb -= 1.0
				var ak := "acts_r" if _ranged(u) else "acts_m"
				stats[ak] = stats.get(ak, 0) + 1
				var ta0 := Time.get_ticks_usec() if algo_probe else 0
				_act_one(u)
				if algo_probe:
					stats["us_act_one"] = stats.get("us_act_one", 0) + Time.get_ticks_usec() - ta0
				if live_count("A") == 0 or live_count("B") == 0:
					break
		if algo_probe:
			var tp2 := Time.get_ticks_usec()
			stats["us_act"] = stats.get("us_act", 0) + tp2 - tp0
			tp0 = tp2
		if tac != null:
			tac.clamp_morale()      # 군령 엄수 · 부동여산 —— 정산(패주 굴림) 전에 사기 바닥
		if _tm >= next_end - 0.001:
			next_end += period
			winner = _settle((_tm - last_set) / period, true)      # 턴 경계 —— 남은 몫 + 지속 시간 줄이기
			last_set = _tm
			next_set = _tm + SETTLE
			if winner == "":
				turn += 1
				_turn_begin(turn)
		elif _tm >= next_set - 0.001:
			winner = _settle((_tm - last_set) / period, false)     # 11/3 0.2초마다 흐름만 나눠서 (실시간처럼)
			last_set = _tm
			next_set = _tm + SETTLE
		elif live_count("A") == 0 or live_count("B") == 0:
			winner = "draw" if live_count("A") + live_count("B") == 0 else ("A" if live_count("B") == 0 else "B")
		if _tm >= _next_track - 0.001:
			_record()
		if algo_probe:
			stats["us_settle"] = stats.get("us_settle", 0) + Time.get_ticks_usec() - tp0
	_record()
	var r := _result(winner, turn)
	r["track"] = track
	r["terrain"] = terrain
	r["rt"] = true
	r["lay"] = lay
	r["arena"] = [roundi(arena.position.x), roundi(arena.position.y), roundi(arena.size.x), roundi(arena.size.y)]
	r["len"] = snappedf(_tm, 0.1)
	if tac != null:
		r["tac"] = tac.summary()      # 단계마다 양쪽 카드 · 상성, 약탈 군량
		tac.b = null                  # 서로 붙든 참조를 끊는다
		tac = null
	if _sg != null:
		_sg.release()      # 서로 붙든 참조를 끊는다 (장수 개성)
		_sg = null
	return r


## 행동 간격 —— 한 턴(period)에 한 번이 기준, 빠르면 조금 짧게 (±25%)
## 11/19 사용자: "속도 100 = 초당 1번 공격" —— 행동 간격 = SPD_RULE_BASE / 속도 초. 등급별 턴 배율(PERIOD_MUL)은 정산 간격(상태 지속 · 회복 주기)에만 남는다.
## 실험(tests/spd_rule, 16판씩)을 보고 사용자가 "그대로 초당 1번으로 켠다"고 정했다: 3급 33 → 19초 · 4급 40 → 30 · 5급 33 → 26 · 6급 이상은 거의 그대로.
## false 면 예전 식(한 턴에 한 번, 속도는 ±25%)
static var spd_rule := true
const SPD_RULE_BASE := 100.0

func _interval(u: Unit) -> float:
	var fl := _flood_slow(u)      # 수몰 이감은 속도 반영이 1/4 뿐인 간격식에 묻히지 않게 따로 곱한다 (11/8 —— 이동은 eff 로 그대로)
	if spd_rule:
		return SPD_RULE_BASE / maxf(20.0, eff(u, "spd") / fl) / fl * (tac.int_mul(u) if tac != null else 1.0)
	var s := eff(u, "spd") / fl / maxf(1.0, float(u.c.spd))
	return period / clampf(0.75 + 0.25 * s * (float(u.c.spd) / 75.0), 0.8, 1.25) / fl * (tac.int_mul(u) if tac != null else 1.0)      # 11/15 군략 공격 간격 (노궁 연사 · 제갈연노)


## 사거리 때문에 차례를 못 쓰는 동안에도 기본 충전은 흐른다.
## 실제 행동의 충전량은 그대로 두고, 놓친 시간의 몫만 보충한다.
func _idle_gauge(u: Unit, dt: float) -> void:
	if not u.alive or u.ult == null or u.charges <= 0 or u.gauge >= 100.0 or _wind.has(u) or has_st(u, "confuse"):
		return
	var before := u.gauge
	_gauge_add(u, GAUGE_ACT / gauge_div() * _tw(u, "act") * dt / _interval(u))
	stats["idle_gauge"] = float(stats.get("idle_gauge", 0.0)) + u.gauge - before
	if u.gauge >= 100.0 and u.ult_ready_t < 0.0:
		u.ult_ready_t = _tm


## 유닛을 만들 때 바로 진형 자리에 세운다 —— 전투 시작 효과(위진 · 철옹성 · 수공 …)도 거리로 판정하므로
func mk_unit(cid: String, slot_info: Dictionary, camp: String, morale: float, slot: int, item, syn: Dictionary) -> Unit:
	var u := super.mk_unit(cid, slot_info, camp, morale, slot, item, syn)
	var x: float = GAP / 2 * (0.7 + 0.3 * lay) + slot_info.row * RS * lay
	u.pos = Vector2(-x if camp == "A" else x, (slot_info.col - DB.FORM_MID) * CS * lay)
	u.fwd = Vector2(1, 0) if camp == "A" else Vector2(-1, 0)
	var fp := footprint(u.c, u.max, lay)
	u.hw = fp.x
	u.hd0 = fp.y
	u.hd = fp.y
	u.ranged = u.c.tag == "궁병" or is_caster(u.c)
	return u


# ───────── 열 대신 거리 (10/31 사용자: 특기를 거리 기준으로) ─────────
const NEAR_R := 160.0          # 이 안이면 '같은 열 이웃'
const FRONT_R := 170.0         # 가장 가까운 적이 이 안이면 '앞에 섰다'
const BACK_R := 230.0          # 가장 가까운 적이 이 밖이면 '뒤에 섰다'

func _by_distance() -> bool:
	return true


# ───────── 고유기 기 모으기 (10/31 사용자: 전투에 판단할 거리를 —— 예고 → 대응) ─────────
## 고유기는 바로 터지지 않고 WIND 초 동안 기를 모은다. 그동안 상대는 ① 방진으로 받거나 ② 제 고유기로 그 장수를 맞혀 끊는다.
## 11/2 맞받아치기(적이 기를 모을 때 쓴 고유기는 WIND_FAST 초 만에 터져 끊는다)와 영리한 AI 의 고유기 아껴 두기는 없앴다 —— 자동 감상에서 고유기가 연달아 터졌다.
const WIND := 2.5      # 기본값 —— 11/22 장수별 값은 고유기 데이터의 wind (DB.ult_of, data/ultimates.json)
const WIND_FAST := 0.7
const CUT_GAUGE := 30.0        # 끊긴 장수는 게이지가 이만큼 남는다 (횟수는 그대로)
var _wind := {}                # 유닛 -> 터질 시각
## 11/17 사용자: 「마초는 기병인데 먼 곳에 꽂혀도 되나」 → 돌격 고유기(vfx charge · 근접)는 기를 다 모으면 실제로 달려가 부딪히는 순간 터진다.
## 대상은 달려온 길의 띠(line:선봉+전군) 또는 원래 규칙을 부딪힌 자리 기준으로 (그 전에는 적 진영 앞쪽 3부대를 거리 없이 쳤다)
const DASH_MUL := 3.2          # 돌진 속도 = 병종 이동 속도 × 이만큼
const DASH_MAX := 3.0          # 이 안에 못 닿으면 그 자리에서 터진다 (막혔을 때 —— 최후열 돌격은 멀어 2초 넘게 달린다)
var _dash := {}                # 유닛 -> {from, t, end}
static var probe_dash := false
var _dash_from := {}           # 터지는 동안만 —— 달려온 출발점 (띠 대상 계산)
## 11/2 사용자: 후반에 고유기가 연달아 터진다 → 초 단위 간격. 어느 진영이든 직전 고유기에서 ULT_GAP 초,
## 같은 진영은 ULT_SIDE_SEC 초가 지나야 다음 고유기 (맞받아치기로 바로 받아치던 것도 없앴다)
static var ult_gap := 2.5           # 11/11 기 충전 수정 2: (2.5 유지)
static var ult_side_sec := 2.3      # 11/6 밸런스: 같은 진영 고유기 간격 4.5 → 3.0 → (11/11) 2.3
## 11/19 등급별 전역 간격 배율 —— 7등급은 판이 31초로 가장 짧아(6등급 38 · 8등급 45) 간격 2.5초에 걸려 고유기 장수 절반만 썼다(54%). 표 사이는 잇는다
static var ult_gap_tier := {}      # 11/19 7등급 0.8 을 해 봤으나 고유기가 많아진 만큼 판이 짧아져(31 → 29.5초) 발동 수가 같았다 —— 비워 둔다
func _gap_tier() -> float:
	var lo := floori(tier_avg)
	var f := tier_avg - lo
	return lerpf(float(ult_gap_tier.get(lo, 1.0)), float(ult_gap_tier.get(lo + 1, 1.0)), f)
static var wind_max := 2            # 11/11 기 충전 수정 2: 한 진영이 동시에 기를 모을 수 있는 수 1 → 2
var _ult_t := -99.0
var _ult_side_t := {"A": -99.0, "B": -99.0}
var _target_preview := false
var _capture_preview_areas := false
var _preview_areas: Array = []
var _last_warn_areas: Array = []


## 11/4 사용자: 고유기 대기 시간은 장수마다 (DB.ult_of 가 고유기 세기로 정한 wait 초 —— 센 고유기일수록 늦게). 그 전에는 쓰지 않는다
func can_ult(u: Unit) -> bool:
	var full: bool = u.ult != null and u.charges > 0 and u.gauge >= 100.0 and u.alive      # 점검용 —— 찼는데 막힌 이유를 센다 (11/6 #14)
	if u.ult != null and _tm < float(u.ult.get("wait", 14.0)) * _tw(u, "wait"):      # 11/7 기질 배율 (맹장 0.9 · 분노 0.85 · 지략 1.1)
		if full: stats["ult_blk_wait"] = stats.get("ult_blk_wait", 0) + 1
		return false
	# 11/6 #14: 기 모으기는 진영마다 하나씩 (예전엔 어느 쪽이든 하나만 —— 처리량이 반이었다). 전체 간격 ult_gap 은 그대로
	var wn := 0
	for w in _wind:
		if w.camp == u.camp:
			wn += 1
	if wn >= wind_max:
		if full: stats["ult_blk_wind"] = stats.get("ult_blk_wind", 0) + 1
		return false
	if _tm - _ult_t < ult_gap * _gap_tier() or _tm - _ult_side_t[u.camp] < ult_side_sec:
		if full: stats["ult_blk_gap"] = stats.get("ult_blk_gap", 0) + 1
		return false
	var ok := super.can_ult(u)
	if full and not ok: stats["ult_blk_base"] = stats.get("ult_blk_base", 0) + 1
	return ok


## 11/7 재사용 체감 —— 다음 발동은 (장수 대기 × 기질 배율) × reult_wait 초가 지나야 (11/7 2차: 수호 · 분노는 reult_temper 배율)
func _reult_ok(u: Unit) -> bool:
	if u.ult_n == 0:
		return true
	return _tm - u.ult_tm >= float(u.ult.get("wait", 14.0)) * _tw(u, "wait") * float(reult_temper.get(u.temper, reult_wait))


## 11/7 기질 조건 —— 실시간: TEMPER_FREE 초가 지나면 풀린다 · 맞닿음은 발자국 틈 · 사거리 안의 약한 적
func _ult_free_now() -> bool:
	return _tm >= TEMPER_FREE


func _touching_foe(u: Unit) -> bool:
	for o in units:
		if o.alive and o.camp != u.camp and _gap(u, o) <= TOUCH + 2.0:
			return true
	return false


func _foe_low_in_reach(u: Unit, foes: Array) -> bool:
	var reach := _reach(u) + 2.0
	for o in foes:
		if o.troops / o.max < 0.7 and _gap(u, o) <= reach:
			return true
	return false


func _ult_reach_n(u: Unit, foes: Array) -> int:
	if u.ult == null:
		return 0
	# 고유기는 평타 사거리 제한이 없다. 실제 고유기와 동일한 대상 계산으로 판단한다.
	# 판단만 하면서 과거 사건의 area를 수정하지 않도록 _mark도 막는다.
	var previous_ult := _in_ult
	var previous_preview := _target_preview
	_in_ult = true
	_target_preview = true
	var targets := {}
	var allies := units.filter(func(o): return o.alive and o.camp == u.camp)
	for comp in u.ult.eff:
		if comp.t not in ["hit", "foe"] or not comp.has("tgt"):
			continue
		for target in resolve_targets(str(comp.tgt), foes, u, allies):
			if target.alive and target.camp != u.camp:
				targets[target.key] = true
	_in_ult = previous_ult
	_target_preview = previous_preview
	return targets.size()


func _interrupt_ult(u: Unit) -> void:
	if _wind.has(u):
		return
	var fast := false
	var wait := float(u.ult.get("wind", WIND)) + (1.0 if _kv(_foe(u.camp), "wind_slow") else 0.0)      # 점복 관로 —— 적 고유기 기 모으기 +1초
	_wind[u] = _tm + wait
	_ult_t = _tm                  # 11/6 #14: 간격(ult_gap · ult_side_sec)은 기를 모으기 시작한 때부터 센다 (예전엔 터진 뒤부터 —— 기 모으기 2.5초가 간격에 더해져 한 판에 몇 번 못 썼다)
	_ult_side_t[u.camp] = _tm
	u.gauge = 0.0                 # 다시 누를 수 없게 (터지거나 끊길 때 정리)
	u.ult_ready_t = -1.0
	_ult_last[u.camp] = act_n
	var warn := _ult_warn_list(u)
	_paeup_omen(u, warn.map(func(w): return w.k))
	_ai += 1
	_ph = "act"
	_who = u.key
	L("sk", "%s 『%s』 기를 모은다%s" % [ga(nm(u)), u.ult.name, ""],
		{"fx": "ult_warn", "a": u.key, "name": u.ult.name, "wait": wait, "warn": warn, "warn_shapes": _last_warn_areas.duplicate(true), "fast": fast})
	var zh := _kv(_foe(u.camp), "ult_cut")      # 매복 주환 —— 적 고유기 기 모으기를 한 번 끊고 게이지를 비운다
	if zh and int(_kiin_used.get("ult_cut:" + zh.camp, 0)) < 2:      # 두 번까지
		_kiin_used["ult_cut:" + zh.camp] = int(_kiin_used.get("ult_cut:" + zh.camp, 0)) + 1
		_cut_wind(u, zh)
		u.gauge = 0.0
	if inyeon_enabled and _wind.has(u):
		_inyeon_recruit(u, wait)


## 맞을 곳 미리 보기 —— 지금 자리 기준으로 고유기 대상들을 원으로
func _ult_warn_list(u: Unit) -> Array:
	var foes := units.filter(func(o): return o.camp != u.camp)
	var allies := units.filter(func(o): return o.camp == u.camp)
	var warn := []
	var previous_ult := _in_ult
	var previous_preview := _target_preview
	var previous_capture := _capture_preview_areas
	var previous_areas := _preview_areas
	_target_preview = true
	_capture_preview_areas = true
	_preview_areas = []
	_in_ult = true
	for comp in u.ult.eff:
		if comp.t == "ally":
			continue
		for t in resolve_targets(comp.tgt, foes, u, allies):
			if t.alive and not warn.any(func(w): return w.k == t.key):
				warn.append({"k": t.key, "x": roundi(t.pos.x), "y": roundi(t.pos.y), "r": 60})
	_last_warn_areas = _preview_areas.duplicate(true)
	_preview_areas = previous_areas
	_capture_preview_areas = previous_capture
	_target_preview = previous_preview
	_in_ult = previous_ult
	return warn


# ───────── 11/11 인연 합동 고유기 ─────────
## 한 장수(대표)가 기를 모으기 시작하면, 같은 인연(data/inyeon.json)의 게이지 100 인 아군이 기를 모으는 동안 하나씩 합류한다 (대표 포함 최대 INYEON_MAX 명).
## 합류는 대표의 기 모으기 길이(wait)의 inyeon_join_at 비율 지점에서 · 터지는 것은 대표의 끝 시각부터 inyeon_stagger 초 간격으로 (대표 → 먼저 합류한 장수 순).
## 합류한 장수의 고유기는 보통 한 번과 같다 (charges · ult_n · ult_tm · 게이지 0) —— 다만 ult_gap · ult_side_sec · 대기 시간 · 기질 조건 · _ult_ok 는 보지 않는다 (게이지 100 이면 충분).
## 끊김 —— 장수마다 따로 오늘과 똑같이 (끊긴 장수만 못 쏜다 · CUT_GAUGE). 대표가 끊기면 아직 합류하지 않은 장수의 합류는 취소, 이미 합류한 장수는 제 시각에 그대로 쏜다.
const INYEON_MAX := 3
static var inyeon_join_at := [0.32, 0.64]      # 합류 시각 (대표 기 모으기 길이 비율) —— 2.5초면 +0.8 · +1.6
static var inyeon_stagger := 0.2               # 터지는 간격 (초)
var _join_q := []              # 합류 예약 [{u, lead, at, grp, name}]

# ───────── 11/12 인연 주제 · 기인이 연다 · 초월이 키운다 (사용자 확정) ─────────
## 끄면(false) 예전과 비트 단위로 같다. 켜면 —— ① 연쇄(합동 2명 이상)가 끝나면 그 인연의 주제 효과(data/inyeon.json theme)가 터진다
## ② 기인이 연쇄에 끼면 맨 먼저 터지고(대표보다 inyeon_stagger 먼저), 마무리 장수 피해 ×yeon_kiin_fin_mul · 합동 상한 배수 yeon_kiin_cap_mul
## ③ 같은 인연 초월이 살아 있으면 그 인연 장수 게이지 ×Battle.inyeon_up_gain, 초월이 연쇄에 끼면 참여 상한 INYEON_MAX_UP 명
static var inyeon_theme := true
const INYEON_MAX_UP := 4
static var inyeon_join_at4 := [0.24, 0.48, 0.72]   # 4명 연쇄의 합류 시각 (대표 기 모으기 길이 비율)
static var yeon_kiin_fin_mul := 1.3
static var yeon_kiin_cap_mul := 1.8
static var yeon_n4_amp := 0.8       # 11/22 4명 연쇄에 든 장수의 고유기 피해 배율 (1.0 = 예전). 0.8: 4인 연쇄 한 번 적 현재 병력 대비 29 → 27% (기인이 열면 37~42 → 32~36%), tests/chain_power
static var yeon_up_join := 70.0      # 11/12 2차 85 → 70 (초월 인연 덱 20판 4명 연쇄 4 → 6, 무작위 덱은 문턱과 무관하게 0 —— 구성원 넷이 모이는 일이 드묾). 같은 인연 초월이 살아 있으면(또는 자신이 초월이면) 게이지가 이만큼만 차도 합류 (평소 100)


func _join_gauge(o: Unit) -> float:
	if inyeon_theme and (is_up_u(o) or (_gain_up.has(o) and _gain_up[o].any(func(x): return x.alive))):
		return yeon_up_join
	return 100.0


static func is_kiin_u(o: Unit) -> bool:
	return o.c.kind == "kiin"


static func is_up_u(o: Unit) -> bool:      # 초월 (기인 아님)
	return o.c.tier == 6 and o.c.kind != "kiin"


## 같은 인연 초월 —— 고유기 있는 아군마다, 인연을 같이 나누는 초월 아군(자기 말고)
func _yeon_up_setup() -> void:
	for u in units:
		if u.ult == null:
			continue
		var my: Array = DB.INYEON_OF.get(DB.person(u.c.id), [])
		if my.is_empty():
			continue
		var ups := []
		for o in units:
			if o == u or o.camp != u.camp or o.ult == null or not is_up_u(o):
				continue
			var po: String = DB.person(o.c.id)
			if my.any(func(n): return DB.INYEON[n].has(po)):
				ups.append(o)
		if not ups.is_empty():
			_gain_up[u] = ups
var _wind_grp := {}            # 합동에 든 장수 -> 그룹 {lead, name, members, taken, fired}


## 11/11 시험용 손잡이(기본 꺼짐 = 설계대로 게이지 100 이면 충분) —— 켜면 합류하는 장수도 제 대기 시간(장수 wait × 기질)과 재사용 대기(_reult_ok)는 지킨다
static var inyeon_gate_time := false


func _join_ok(o: Unit) -> bool:
	if inyeon_gate_time and o.ult != null and (_tm < float(o.ult.get("wait", 14.0)) * _tw(o, "wait") or not _reult_ok(o)):
		return false
	return ults_enabled and o.alive and o.ult != null and o.charges > 0 and o.gauge >= _join_gauge(o) \
		and not has_st(o, "seal") and not has_st(o, "confuse") and not _wind.has(o) and not _wind_grp.has(o)


func _inyeon_recruit(u: Unit, wait: float) -> void:
	if tac != null and tac.yeon_cut(u.camp):      # 11/15 군략 이간 —— 이 단계 인연 합동을 모으지 못한다
		return
	var lead_in: Array = DB.INYEON_OF.get(DB.person(u.c.id), [])
	if lead_in.is_empty():
		return
	var cands := []
	for o in units:
		if o == u or o.camp != u.camp or not _join_ok(o):
			continue
		var po: String = DB.person(o.c.id)
		if lead_in.any(func(n): return DB.INYEON[n].has(po)):
			cands.append(o)
	if cands.is_empty():
		return
	cands.sort_custom(func(x, y):      # 게이지가 먼저 찬 장수부터, 같으면 등급이 높은 장수, 그래도 같으면 유닛 순서 (주제 켬: 기인 → 초월이 맨 앞)
		if inyeon_theme:
			var kx := is_kiin_u(x)
			if kx != is_kiin_u(y):
				return kx
			var ux := is_up_u(x)
			if ux != is_up_u(y):
				return ux
		var rx: float = x.ult_ready_t if x.ult_ready_t >= 0.0 else 1e9
		var ry: float = y.ult_ready_t if y.ult_ready_t >= 0.0 else 1e9
		if rx != ry:
			return rx < ry
		if x.c.tier != y.c.tier:
			return x.c.tier > y.c.tier
		return _idx[x] < _idx[y])
	var mx := INYEON_MAX
	if inyeon_theme and (is_up_u(u) or cands.any(func(o): return is_up_u(o))):      # 초월이 끼면 참여 상한 +1
		mx = INYEON_MAX_UP
	var picks: Array = cands.slice(0, mx - 1)
	# 인연 이름 —— 대표의 인연 가운데 뽑힌 장수가 가장 많이 든 것 (같으면 파일 순서)
	var best := ""
	var bn := -1
	for n in lead_in:
		var c := 0
		for o in picks:
			if DB.INYEON[n].has(DB.person(o.c.id)):
				c += 1
		if c > bn:
			bn = c
			best = n
	var grp := {"lead": u, "name": best, "members": [u], "taken": {}, "fired": false}
	var at: Array = inyeon_join_at
	if inyeon_theme:
		if picks.size() >= 3:
			at = inyeon_join_at4
		if is_kiin_u(u):
			grp["kiin"] = u      # 기인이 대표 —— 원래 맨 먼저 터진다
	_wind_grp[u] = grp
	for i in picks.size():
		var o: Unit = picks[i]
		var po: String = DB.person(o.c.id)
		var nm_ := best
		if not DB.INYEON[best].has(po):      # 그룹 이름을 같이 나누지 않는 장수는 대표와 나누는 첫 인연
			nm_ = lead_in.filter(func(n): return DB.INYEON[n].has(po))[0]
		_join_q.append({"u": o, "lead": u, "at": _tm + wait * float(at[mini(i, at.size() - 1)]), "grp": grp, "name": nm_})


## 합류 때가 된 장수를 붙인다 (매 틱, 고유기를 터뜨리기 전에)
func _inyeon_joins() -> void:
	for j in _join_q.duplicate():
		if j.at > _tm + 0.001:
			continue
		_join_q.erase(j)
		var lead: Unit = j.lead
		var o: Unit = j.u
		if not _wind.has(lead) or not _join_ok(o):      # 대표가 끊겼거나 그새 못 쓰게 됐다
			continue
		var grp: Dictionary = j.grp
		var ord: int = grp.members.size()
		grp.members.append(o)
		_wind_grp[o] = grp
		var end: float = float(_wind[lead]) + inyeon_stagger * ord
		if inyeon_theme:
			if not grp.has("kiin") and is_kiin_u(o):      # 기인은 연쇄를 연다 —— 대표보다 먼저 터진다
				grp["kiin"] = o
				end = float(_wind[lead]) - inyeon_stagger
			elif grp.has("kiin") and grp.kiin != lead:      # 기인이 앞에 끼어 뒤 장수는 한 칸씩 당겨진다
				end = float(_wind[lead]) + inyeon_stagger * (ord - 1)
		_wind[o] = end
		o.gauge = 0.0
		o.ult_ready_t = -1.0
		stats["inyeon_join"] = int(stats.get("inyeon_join", 0)) + 1
		var warn := _ult_warn_list(o)
		_paeup_omen(o, warn.map(func(w): return w.k))
		_ai += 1
		_ph = "act"
		_who = o.key
		L("sk", "%s 『%s』 인연 『%s』 —— %s도 기를 모은다" % [ga(nm(o)), o.ult.name, j.name, nm(lead)],
			{"fx": "ult_join", "a": o.key, "lead": lead.key, "name": o.ult.name, "inyeon": j.name, "ord": ord, "wait": end - _tm, "warn": warn, "warn_shapes": _last_warn_areas.duplicate(true)})


## 합동에서 빠진다 (끊김 · 못 쏨) —— 아직 합류하지 않은 예약도 대표가 빠지면 지운다
func _inyeon_drop(d: Unit) -> void:
	if _wind_grp.has(d):
		var grp: Dictionary = _wind_grp[d]
		if grp.members.size() > 1:      # 합류한 짝이 있는 합동에서 끊겼다 (혼자 기를 모으던 대표가 끊긴 것은 합동이 아니다)
			stats["inyeon_cut"] = int(stats.get("inyeon_cut", 0)) + 1
		grp.members.erase(d)
		_wind_grp.erase(d)
		if grp.get("kiin") == d and not grp.get("fired", false):      # 연쇄를 열 기인이 끊겼다 —— 대표가 다시 연다
			grp.erase("kiin")
		_inyeon_fin_check(grp)
	_join_q = _join_q.filter(func(j): return j.lead != d)


# ───────── 11/12 인연기 (사용자: 합동이 a+b 가 아니라 c 의 효과와 이펙트가 나오게) ─────────
## 합동 고유기가 2명 이상 실제로 터지면, 마지막 장수가 쏜 뒤(남은 장수가 끊겨 더 쏠 사람이 없을 때도) 그 인연의 인연기가 한 번 터진다.
## 틀 셋 —— fire(적 전체 화상) · duel(적 최강 장수에게 일격 + 사기) · rally(아군 전체 사기 + 공격). 수치는 [2명, 3명].
## 피해형으로 키우지 않는다 —— 합동 상한(inyeon_cap_mul)에 걸려 체감이 없다. 상태 · 사기 위주.
static var inyeon_fin_enabled := true
static var FIN := {
	"fire": {"burn": [0.05, 0.08], "dur": [2, 3]},
	"duel": {"mult": [1.0, 1.6], "morale": [12.0, 20.0]},
	"rally": {"morale": [10.0, 18.0], "atk": [0.10, 0.15], "dur": 2},
}


func _inyeon_fin_check(grp: Dictionary) -> void:
	if not (inyeon_fin_enabled or inyeon_theme) or not grp.get("fired", false) or grp.get("fin", false) or int(grp.get("shot", 0)) < 2:
		return
	if grp.members.any(func(o): return _wind.has(o)):      # 아직 쏠 장수가 남았다
		return
	grp["fin"] = true
	if inyeon_fin_enabled:
		_inyeon_fin_fire(grp)
	if inyeon_theme:      # 11/12 인연 주제 —— 인연기 다음에
		_inyeon_theme_fire(grp)


func _inyeon_fin_fire(grp: Dictionary) -> void:
	var def: Dictionary = DB.inyeon_fin(grp.name)
	if def.is_empty() or not FIN.has(def.t):
		return
	var by: Unit = grp.lead if grp.lead.alive else null
	if by == null:
		for o in grp.members:
			if o.alive:
				by = o
				break
	if by == null:
		return
	var foes := units.filter(func(o): return o.alive and o.camp != by.camp)
	var allies := units.filter(func(o): return o.alive and o.camp == by.camp)
	if foes.is_empty():
		return
	var i := 1 if int(grp.shot) >= 3 else 0
	var tune: Dictionary = FIN[def.t]
	stats["inyeon_fin"] = int(stats.get("inyeon_fin", 0)) + 1
	_ai += 1
	_ph = "act"
	_who = by.key
	_one = turn_mul
	_long = turn_mul
	L("sk", "인연 『%s』 인연기 『%s』 —— %s" % [grp.name, def.n, DB.INYEON_FIN_DESC.get(def.t, "")],
		{"fx": "inyeon_fin", "a": by.key, "name": def.n, "inyeon": grp.name, "kind": def.t, "cnt": int(grp.shot)})
	match def.t:
		"fire":
			for t in foes:
				inflict(by, t, "burn", float(tune.burn[i]), int(tune.dur[i]))
		"duel":
			var best: Unit = foes[0]
			for t in foes:      # 적 최강 장수 —— 등급, 같으면 남은 병력
				if t.c.tier > best.c.tier or (t.c.tier == best.c.tier and t.troops > best.troops):
					best = t
			phys_hit(by, best, float(tune.mult[i]), true)
			if best.alive:
				morale_hit(best, float(tune.morale[i]), def.n, 1, by)
		"rally":
			for o in allies:
				heal_morale(o, float(tune.morale[i]), def.n, by)
				add_buff(o, {"stat": "atk", "amt": float(tune.atk[i]), "dur": int(tune.dur)})
	_one = 1.0
	_long = 1.0


## 기 모으기가 끝난 고유기를 터뜨린다 (유닛 순서대로 —— 같은 시각이면 결정적으로)
func _fire_winds() -> void:
	if not _join_q.is_empty():
		_inyeon_joins()
	for u: Unit in _tick_units():
		if not _wind.has(u) or _wind[u] > _tm + 0.001 or _yeon_held(u):
			continue
		_wind.erase(u)
		if not u.alive or has_st(u, "confuse"):
			u.gauge = CUT_GAUGE
			_inyeon_drop(u)
			continue
		if _dash_ult(u):
			var dt := _dash_target(u)
			if dt != null and _gap(u, dt) > TOUCH + 2.0:
				_dash[u] = {"from": u.pos, "t": dt, "end": _tm + DASH_MAX, "g0": _gap(u, dt), "t0": _tm}
				L("sk", "%s 적진으로 돌진한다" % ga(nm(u)), {"fx": "ult_dash", "a": u.key, "f": dt.key})
				continue
		_fire_one(u)


## 11/22 연쇄를 여는 장수(대표 · 기인)가 아직 돌진 중이면 합류한 짝은 기다린다 —— 돌격 대표(마초 · 조운 · 손책 …)는 기를 다 모은 뒤
## 최대 DASH_MAX 초 달려가 부딪혀야 터지는데, 짝은 대표의 원래 끝 시각 + inyeon_stagger 에 먼저 터져 버려 연쇄가 깨졌다 (짝 · 대표 모두 단독, tests/chain_rate)
func _yeon_held(u: Unit) -> bool:
	var grp: Dictionary = _wind_grp.get(u, {})
	if grp.is_empty() or grp.get("fired", false):
		return false
	var head: Unit = grp.get("kiin", grp.lead) if inyeon_theme else grp.lead
	return head != u and _dash.has(head) and grp.members.has(head)


## 기를 다 모은 (돌격이면 부딪힌) 고유기 하나를 터뜨린다
func _fire_one(u: Unit) -> void:
	var grp: Dictionary = _wind_grp.get(u, {})
	if not grp.is_empty():
		_inyeon_fire_setup(u, grp)
		if grp.get("head") == u and _dash_from.has(u):      # 돌진 끝에 연 연쇄 —— 기다리던 짝은 지금부터 inyeon_stagger 간격으로
			var k := 0
			for o in grp.members:
				if o != u and _wind.has(o):
					k += 1
					_wind[o] = maxf(float(_wind[o]), _tm + inyeon_stagger * k)
	super._interrupt_ult(u)
	var joint: bool = not _ult_grp.is_empty()      # 합동으로 터졌다 (대표가 끊겨 혼자 쏜 장수는 세지 않는다)
	_ult_grp = {}
	_ult_extra = {}
	_ult_amp_x = 1.0
	_wind_grp.erase(u)
	if joint:
		grp["shot"] = int(grp.get("shot", 0)) + 1
		_inyeon_fin_check(grp)
	_join_q = _join_q.filter(func(j): return j.lead != u)
	_omen.erase(u)


## 돌격 고유기 —— 근접 장수의 vfx charge 고유기
func _dash_ult(u: Unit) -> bool:
	return u.ult != null and str(u.ult.get("vfx", "")) == "charge" and not _ranged(u)


## 달려갈 적 —— 첫 타격 대상이 최후열(back1 · back2)이면 가장 깊은 적, 아니면 발자국 틈이 가장 가까운 적
func _dash_target(u: Unit) -> Unit:
	var live := units.filter(func(o): return o.alive and o.camp != u.camp and not _hidden(o))
	if live.is_empty():
		return null
	var spec := ""
	for comp in u.ult.eff:
		if comp.t == "hit" and comp.has("tgt"):
			spec = str(comp.tgt)
			break
	if spec in ["back1", "back2"]:
		return _deepest(u, live)
	var best: Unit = null
	var bd := INF
	for o in live:
		var g := _gap(u, o)
		if g < bd:
			bd = g
			best = o
	return best


## 돌진 중인 장수를 움직이고, 닿으면(또는 시간이 다 되면) 고유기를 터뜨린다 (유닛 순서대로 —— 결정적)
func _dash_tick() -> void:
	if _dash.is_empty():
		return
	for u in units:
		if not _dash.has(u):
			continue
		var d: Dictionary = _dash[u]
		if not u.alive or has_st(u, "confuse"):
			_dash.erase(u)
			u.gauge = CUT_GAUGE
			_inyeon_drop(u)
			continue
		var t: Unit = d.t
		if not t.alive:
			t = _dash_target(u)
			d.t = t
		var arrived := t == null or _gap(u, t) <= TOUCH + 2.0 or _tm >= float(d.end) - 0.001
		if not arrived:
			var to := t.pos - u.pos
			var sp: float = float(SPEED.get(u.c.tag, 55.0)) * DASH_MUL
			var step := minf(sp * TICK, maxf(0.0, _gap(u, t) - TOUCH))
			var dir := to.normalized()
			u.vel = dir * sp
			u.pos += dir * step
			u.ran += step
			_turn_to(u, to)
			arrived = _gap(u, t) <= TOUCH + 2.0
		if arrived:
			_dash.erase(u)
			u.vel = Vector2.ZERO
			if t != null:
				u.tgt = t
			_dash_from[u] = d.from
			stats["dash_n"] = int(stats.get("dash_n", 0)) + 1      # 점검용 —— 돌진 고유기 수 · 터질 때 부딪힌 적과의 틈 (tests/ult_dash)
			if t != null:
				stats["dash_gap_max"] = maxf(float(stats.get("dash_gap_max", 0.0)), _gap(u, t))
				if probe_dash:
					print("DASHLOG ", u.c.name, " g0=", roundi(d.g0), " g1=", roundi(_gap(u, t)), " t=", snappedf(_tm - float(d.t0), 0.01), " tgt=", t.c.name, " moved=", roundi(u.pos.distance_to(d.from)))
			_fire_one(u)
			_dash_from.erase(u)


## 합동 고유기의 사건 항목 · 상한 그룹을 정한다 —— 대표는 inyeon · mates, 따라 쏘는 장수는 inyeon · lead (대표가 이미 터졌을 때만 —— 대표가 끊겼으면 보통 고유기처럼)
func _inyeon_fire_setup(u: Unit, grp: Dictionary) -> void:
	var head: Unit = grp.get("kiin", grp.lead) if inyeon_theme else grp.lead      # 11/12 기인이 끼면 기인이 연다
	if u == head and not grp.fired:
		var mates := []
		for o in grp.members:
			if o != u and _wind.has(o):
				mates.append(o.key)
		if mates.is_empty():
			return
		grp.fired = true
		grp["head"] = u
		grp["n0"] = 1 + mates.size()      # 11/22 연쇄 인원 —— 인원별 합동 상한 (Battle.inyeon_cap_n)
		if inyeon_theme:
			grp["foes0"] = units.filter(func(o): return o.alive and o.camp != u.camp).size()
		_ult_extra = {"inyeon": grp.name, "mates": mates}
		stats["inyeon_joint"] = int(stats.get("inyeon_joint", 0)) + 1
		stats["inyeon_units"] = int(stats.get("inyeon_units", 0)) + 1 + mates.size()
		var kn := "inyeon_n2" if mates.size() == 1 else ("inyeon_n3" if mates.size() == 2 else "inyeon_n4")
		stats[kn] = int(stats.get(kn, 0)) + 1
		if inyeon_theme:
			if is_kiin_u(u):
				grp["cap_mul"] = yeon_kiin_cap_mul
				grp["kiin_open"] = true
				stats["inyeon_kiin"] = int(stats.get("inyeon_kiin", 0)) + 1
				_ult_extra["open"] = "kiin"
			if grp.members.any(func(o): return is_up_u(o) and (o == u or _wind.has(o))):
				stats["inyeon_up"] = int(stats.get("inyeon_up", 0)) + 1
	elif grp.fired:
		_ult_extra = {"inyeon": grp.name, "lead": grp.get("head", grp.lead).key}
		if inyeon_theme and grp.get("kiin_open", false) and not grp.members.any(func(o): return o != u and _wind.has(o)):
			_ult_amp_x = yeon_kiin_fin_mul      # 기인이 연 연쇄의 마무리
			_ult_extra["finish"] = true
			stats["inyeon_kiin_fin"] = int(stats.get("inyeon_kiin_fin", 0)) + 1
	else:
		return
	if inyeon_theme and int(grp.get("n0", 0)) >= 4:      # 11/22 4명 연쇄 —— 장수마다 피해 ×yeon_n4_amp (한 번에 적 병력 25~35% 목표, tests/chain_power)
		_ult_amp_x *= yeon_n4_amp
	_ult_grp = grp


func _paeup_unwind(d: Unit) -> void:
	if _wind.has(d):
		_cut_wind_quiet(d)


func _cut_wind_quiet(d: Unit) -> void:
	_wind.erase(d)
	_inyeon_drop(d)
	d.gauge = 0.0


## 기 모으던 장수가 적 고유기에 맞았다 —— 끊긴다
func _cut_wind(d: Unit, a: Unit) -> void:
	_wind.erase(d)
	_inyeon_drop(d)
	d.gauge = CUT_GAUGE
	stats["ult_cuts"] = stats.get("ult_cuts", 0) + 1
	L("sk", "%s 『%s』 기세가 끊겼다!" % [ga(nm(d)), d.ult.name], {"fx": "ult_cut", "a": a.key, "f": d.key, "name": d.ult.name})


## 적이 기를 모으는 중이면 위협 최대 —— 영리한 AI 가 방진으로 받는다
func _ult_threat(cp: String) -> float:
	for o in _wind:
		if o.camp != cp:
			return 100.0
	return super._ult_threat(cp)


func _foe_dist(u: Unit) -> float:
	var best := INF
	for o in units:
		if o.alive and o.camp != u.camp:
			best = minf(best, u.pos.distance_to(o.pos))
	return best


func _same_line(a: Unit, b: Unit) -> bool:
	return a.pos.distance_to(b.pos) <= NEAR_R


## 앞쪽 묶음 —— 적에게 가장 가까운 유닛과 40 안쪽 차이로 가까운 유닛들
func _front_of(us: Array) -> Array:
	if us.is_empty(): return []
	var d := us.map(func(o): return _foe_dist(o))
	var mn: float = d.min()
	var out := []
	for i in us.size():
		if d[i] <= mn + 40.0:
			out.append(us[i])
	return out


func _back_of(us: Array) -> Array:
	if us.is_empty(): return []
	var d := us.map(func(o): return _foe_dist(o))
	var mx: float = d.max()
	var out := []
	for i in us.size():
		if d[i] >= mx - 40.0:
			out.append(us[i])
	return out


func _is_front(u: Unit) -> bool:
	return _foe_dist(u) <= FRONT_R


func _is_back(u: Unit) -> bool:
	return _foe_dist(u) >= BACK_R


## 가장 빽빽한 무리 —— 한 유닛 둘레 AREA 안에 모인 수의 최댓값
func _dense_max(us: Array) -> int:
	var best := 0
	for c in us:
		best = maxi(best, us.filter(func(o): return o == c or _gap(o, c) <= AREA_GAP).size())
	return best


## 사거리 —— 발자국 가장자리 사이 틈 (11/7 강체: 중심 거리가 아니라 대열 앞끝에서 적 대열까지)
func _reach(u: Unit) -> float:
	var hill := HILL.range if _in(u.pos, "hill") else 1.0
	if u.c.tag == "궁병":
		return bow_range * hill * Battle.class_tune("range", u.c.tag, u.c.tier) * (tac.range_mul(u) if tac != null else 1.0)
	if is_caster(u.c):
		return cast_range * hill * Battle.class_tune("range", u.c.tag, u.c.tier) * (tac.range_mul(u) if tac != null else 1.0)      # 11/8 병종 사거리 배율 (class_guard.range)
	return melee_gap


## 지형 만들기 —— 전투 rng 와 따로 돌린다 (지형 때문에 판정 난수가 밀리지 않게)
func _make_terrain(sd: int) -> void:
	terrain = []
	if not terrain_enabled:
		return
	var tr := RandomNumberGenerator.new()
	tr.seed = hash(str(sd) + "지형")
	if tr.randf() < 0.45:
		terrain.append({"k": "river", "x": 0, "y": 0, "w": tr.randi_range(26, 38)})
	for i in tr.randi_range(0, 2):
		var x := tr.randi_range(70, 380)
		var y := tr.randi_range(-210, 210)
		var r := tr.randi_range(60, 100)
		terrain.append({"k": "forest", "x": -x, "y": y, "r": r})
		terrain.append({"k": "forest", "x": x, "y": y, "r": r})
	if tr.randf() < 0.55:
		var x := tr.randi_range(160, 330)
		var y := tr.randi_range(-190, 190)
		var r := tr.randi_range(80, 110)
		terrain.append({"k": "hill", "x": -x, "y": y, "r": r})
		terrain.append({"k": "hill", "x": x, "y": y, "r": r})


## p 가 그 지형 안인가
func _in(p: Vector2, kind: String) -> bool:
	for z in terrain:
		if z.k != kind:
			continue
		if kind == "river":
			if absf(p.x - float(z.x)) <= float(z.w):
				return true
		elif p.distance_to(Vector2(z.x, z.y)) <= float(z.r):
			return true
	return false


func _terrain_move(u: Unit) -> float:
	var m := 1.0
	if _in(u.pos, "forest"): m *= FOREST.move
	if _in(u.pos, "river"): m *= RIVER.move
	if _in(u.pos, "hill"): m *= HILL.move
	if _in_sea(u): m *= SEA_SLOW      # 주유 적벽 불바다 —— 안의 적은 느려진다
	return m


## 화상 —— 숲에서는 크게 번진다
func _burn_mul(a: Unit, d: Unit) -> float:
	return super._burn_mul(a, d) * (FOREST.burn if _in(d.pos, "forest") else 1.0) * (tac.burn_mul(a) if tac != null else 1.0)      # 11/15 군략 동남풍 · 천시


func _ranged(u: Unit) -> bool:
	return u.ranged      # 궁병 · 책략계 (mk_unit 이 정해 둔다)


func _foes_of(u: Unit) -> Array:
	var out := []      # 11/15 성능: filter(람다) → 그냥 훑기 (같은 순서 · 같은 답. 틱마다 부대 수만큼 불린다)
	var cp := u.camp
	var hide_on: bool = (not _paeup.is_empty() and _tm < 8.0) or (_sg != null and _tm < _sg.hide_until)      # 숨는 장수는 패업이 있는 판의 개전 8초 · 1.2 여몽 위장 · 11/22 황개 거짓 항복 · 조조 할수기포뿐 (_hidden 의 조건) —— 그 밖에는 묻지 않는다
	for o in units:
		if o.alive and o.camp != cp and not (hide_on and _hidden(o)):      # 감녕 백기야습 —— 숨은 동안은 목표가 되지 않는다
			out.append(o)
	return out


func _ready_to_hit(u: Unit) -> bool:
	if has_st(u, "confuse"):
		return true            # 혼란은 제자리에서 차례를 날리거나 제 편을 친다 (Battle.act)
	if u.ranged:
		u.tgt = _nearest_ranged_target(u, _foes_of(u))
		return u.tgt != null
	return u.tgt != null and u.tgt.alive and not _hidden(u.tgt) and _gap(u, u.tgt) <= _reach(u) + 2.0


# ───────── 발자국 기하 ─────────

static func _rt(u: Unit) -> Vector2:
	return Vector2(-u.fwd.y, u.fwd.x)


## 발자국이 dir 방향으로 뻗은 반폭
static func _extent(u: Unit, dir: Vector2) -> float:
	return u.hd * absf(dir.dot(u.fwd)) + u.hw * absf(dir.dot(Vector2(-u.fwd.y, u.fwd.x)))


## 두 발자국 가장자리 사이 틈 (겹치면 음수 —— 가장 얕게 파고든 깊이). 네 축(두 부대의 앞뒤 · 좌우)으로 재는 분리축 판정
## 11/15 성능: 전투 계산에서 가장 많이 불리는 함수 (틱마다 수백 번) —— 축 배열 · _rt · _extent 호출을 풀어 썼다. 식 · 계산 순서는 그대로라 결과는 같다
func _gap(a: Unit, b: Unit) -> float:
	var d := b.pos - a.pos
	var af := a.fwd
	var ar := Vector2(-af.y, af.x)
	var bf := b.fwd
	var br := Vector2(-bf.y, bf.x)
	var ahd := a.hd
	var ahw := a.hw
	var bhd := b.hd
	var bhw := b.hw
	var best := -INF
	var sep := absf(d.dot(af)) - (ahd * absf(af.dot(af)) + ahw * absf(af.dot(ar))) - (bhd * absf(af.dot(bf)) + bhw * absf(af.dot(br)))
	if sep > best:
		best = sep
	sep = absf(d.dot(ar)) - (ahd * absf(ar.dot(af)) + ahw * absf(ar.dot(ar))) - (bhd * absf(ar.dot(bf)) + bhw * absf(ar.dot(br)))
	if sep > best:
		best = sep
	sep = absf(d.dot(bf)) - (ahd * absf(bf.dot(af)) + ahw * absf(bf.dot(ar))) - (bhd * absf(bf.dot(bf)) + bhw * absf(bf.dot(br)))
	if sep > best:
		best = sep
	sep = absf(d.dot(br)) - (ahd * absf(br.dot(af)) + ahw * absf(br.dot(ar))) - (bhd * absf(br.dot(bf)) + bhw * absf(br.dot(br)))
	if sep > best:
		best = sep
	return best


func _speed(u: Unit) -> float:
	return SPEED.get(u.c.tag, 55.0) * clampf(eff(u, "spd") / maxf(1.0, float(u.c.spd)), 0.5, 1.5) * _terrain_move(u) * (tac.spd_mul(u) if tac != null else 1.0)


# ───────── 움직임 ─────────

func _move() -> void:
	# 11/19 성능: 적 목록은 진영마다 같다 (이동 중에는 아무도 쓰러지지 않는다) —— 부대마다 다시 만들지 않고 진영마다 한 번
	var foes_of_a: Array = []
	var foes_of_b: Array = []
	var got_a := false
	var got_b := false
	for u: Unit in _tick_units():
		if not u.alive or _dash.has(u):
			continue
		u.retgt -= TICK
		var foes: Array
		if u.camp == "A":
			if not got_a:
				foes_of_a = _foes_of(u)
				got_a = true
			foes = foes_of_a
		else:
			if not got_b:
				foes_of_b = _foes_of(u)
				got_b = true
			foes = foes_of_b
		if foes.is_empty():
			u.vel = Vector2.ZERO
			continue
		# 맞닿은 적이 있으면 묶인다 —— 발자국이 맞닿은(틈 TOUCH 안) 적 가운데 가장 가까운 적을 상대 (원거리도 붙으면 맞받아 싸운다)
		var pin: Unit = null
		var pd := TOUCH + 2.0
		# 11/15 성능: 가운데끼리 이만큼 멀면 틈이 TOUCH 를 넘는 것이 확실하다 (틈 ≥ 거리 / √2 − 두 발자국의 반폭 + 반깊이) —— 그런 적은 틈을 재지 않는다 (결과는 같다)
		var far_r := u.hw + u.hd + 12.0
		var upos := u.pos
		for o in foes:
			if upos.distance_to(o.pos) * 0.7 > far_r + o.hw + o.hd:
				continue
			var g := _gap(u, o)
			if g <= pd:
				pd = g
				pin = o
		# 기병 · 도적은 맞닿아도 묶이지 않고 노리던 후열로 파고든다
		var slip: bool = (u.c.tag == "기병" or u.c.tag == "도적") and u.tgt != null and u.tgt.alive and pin != u.tgt
		if slip and u.c.tag == "도적" and pin != null and pin.c.tag == "창병" and Battle.tag_roles and rogue_hold > 0.0:
			# 11/19 사용자: 도적 대책 2 —— 창병 도발이 도적에게도. 맞닿은 창병이 그 도적을 rogue_hold 초 붙잡는다 (창병 하나가 같은 도적을 한 번만)
			var hk := [u, pin]
			var left: float = float(_rogue_held.get(hk, rogue_hold))
			if left > 0.0:
				if not _rogue_held.has(hk):
					stats["rogue_held"] = int(stats.get("rogue_held", 0)) + 1
				_rogue_held[hk] = left - TICK
				slip = false
		var ft = _sg.force_tgt(u) if (_sg != null and u.sg.has("ftg") and not u.ranged) else null      # 11/22 특별한 특기 —— 장료 돌파 · 조운 구출: 정한 적에게 곧장 (기병은 맞닿은 적을 흘려 지나간다)
		if ft != null:
			u.tgt = ft
			slip = (u.c.tag == "기병" or u.c.tag == "도적") and pin != ft
		if slip:
			pin = null
		if _sg != null and _sg.backing(u):      # 11/19 치고 빠지기 —— 물러나는 동안 묶이지 않는다
			pin = null
		# 11/16 사용자 "뒷라인이 도적에게 공격 받아도 타겟팅을 바꾸지 않음" —— 원거리(궁병 · 책략계)는 근접 적이 달라붙으면 사거리 안의 옛 목표를 버리고 붙은 적을 상대한다
		if u.ranged:
			u.tgt = _choose(u, foes)
		elif pin != null and (u.tgt == null or not u.tgt.alive or _gap(u, u.tgt) > _reach(u)):
			u.tgt = pin
		elif u.tgt == null or not u.tgt.alive or u.retgt <= 0.0 or _hidden(u.tgt):
			u.tgt = _choose(u, foes)
			u.retgt = 0.5
		# 11/21 도발 (sig_rt taunt) —— 도발에 걸린 부대는 표적을 도발한 부대로 돌린다.
		# 원거리 · 다른 적에게 묶인 근접은 도발한 부대가 손 닿는 거리(사거리)일 때만 (묶인 채 엉뚱한 곳으로 걸어가지 않게)
		if _sg != null and _sg.has("taunt") and u.sg.has("tnt"):
			var tt = _sg.taunt_of(u)
			if tt != null and tt != u.tgt and not _hidden(tt) and ((not u.ranged and pin == null) or _gap(u, tt) <= _reach(u)):
				u.tgt = tt
				stats["sig_taunt_pull"] = int(stats.get("sig_taunt_pull", 0)) + 1
		if ft != null and ft.alive:
			u.tgt = ft
		# 11/15 성능: 이동 속도(eff → 특기 · 위세 · 버프를 다 훑는다)는 실제로 움직일 때만 잰다 —— 맞붙어 서 있는 부대(목표 속도 0 · 지금 속도 0)는
		# 속도가 얼마든 그대로 0 이다. 점검용 특기 세기(probe_on)를 켠 판은 예전처럼 늘 잰다 (읽힌 횟수가 같게)
		var sp := _speed(u) if probe_on else -1.0
		if has_st(u, "confuse"):
			if sp < 0.0:
				sp = _speed(u)
			u.vel = u.vel.move_toward(Vector2.ZERO, sp / DEC_T * TICK)
			u.pos += u.vel * TICK
			continue
		var t := u.tgt
		if t == null:      # 11/20 노릴 적이 없다 (남은 적이 모두 은신 중일 때 등) —— 예전에는 여기서 null 접근 오류가 나 그 틱의 나머지 부대 이동까지 끊겼다. 제자리에서 멈춘다
			if sp < 0.0:
				sp = _speed(u)
			u.vel = u.vel.move_toward(Vector2.ZERO, sp / DEC_T * TICK)
			u.pos += u.vel * TICK
			continue
		var to := t.pos - u.pos
		var dist := to.length()
		var gap := _gap(u, t)
		var want := TOUCH if not _ranged(u) else _reach(u) - 4.0
		var desired := Vector2.ZERO
		var flanking := false
		if pin == null and gap > want:
			var dir := to / maxf(dist, 0.001)
			# 기병은 적 무리를 돌아 옆 · 뒤로 파고든다 (멀 때만)
			if u.c.tag == "기병" and gap > 150.0:
				var side := signf(u.pos.y - _centroid(foes).y)
				if side == 0.0:
					side = 1.0 if u.slot % 2 == 0 else -1.0
				dir = (dir + Vector2(-dir.y, dir.x) * side * 0.55 * signf(dir.x if dir.x != 0 else 1.0)).normalized()
			# 11/4 사용자: 도적은 측면으로 크게 돌아 적 후열에 붙는다 —— 적 무리 옆 바깥 길목(적 폭 + 여유)을 지나 노리는 적 뒤로
			if u.c.tag == "도적" and gap > 70.0 and probe_rogue_flank:
				var way = _flank_way(u, t, foes)
				if way != null:
					var wv: Vector2 = way - u.pos
					if wv.length() > 20.0:
						dir = wv.normalized()
						flanking = true
			dir = _steer(u, dir, t)
			if dir != Vector2.ZERO:
				if sp < 0.0:
					sp = _speed(u)
				if flanking:
					sp *= flank_spd      # 11/22 우회 길목으로 도는 동안은 빨리 —— 적진 투입을 당긴다
					stats["flank_run_t"] = stats.get("flank_run_t", 0.0) + TICK
				desired = dir * minf(sp, (gap - want) / TICK)      # 노리는 적 앞에서 멈춘다 (파고들지 않게)
		else:
			u.block_t = 0.0
		if _sg != null and (not u.m.is_empty() or u.sg.has("back")):      # 11/19 치고 빠지기 · 후퇴 사격 · 11/22 장비 호령에 물러서는 적
			var d2: Vector2 = _sg.steer(u, t, pin, desired, sp if sp >= 0.0 else _speed(u))
			if d2 != desired:
				desired = d2
				if sp < 0.0:
					sp = _speed(u)
		# 속도 —— 가속 · 감속 시간을 두어 미끄러지거나 순간이동하지 않는다
		if desired != Vector2.ZERO or u.vel != Vector2.ZERO or sp >= 0.0:
			if sp < 0.0:
				sp = _speed(u)
			var acc := sp / (ACC_T if desired.length() > u.vel.length() else DEC_T)
			u.vel = u.vel.move_toward(desired, acc * TICK)
			var step := u.vel * TICK
			u.pos += step
			if desired != Vector2.ZERO:
				u.ran += step.length()
		# ② 멀리 걷는 동안은 가는 쪽을 본다 (묶였거나 가까우면 적을 본다)
		if algo_v2 and algo_bits & 2 and pin == null and not u.ranged and gap > FACE_GAP and u.vel.length() > FACE_SPEED:
			# 붐비는 곳에서는 적 쪽에서 가는 쪽으로 FACE_LEAN 까지만 튼다 (넓은 대열이 좁은 틈에서 크게 돌면 이웃과 부딪친다). 트인 곳에서는 가는 쪽 그대로
			var lean := clampf(angle_difference(to.angle(), u.vel.angle()), -FACE_LEAN, FACE_LEAN)
			_turn_to(u, Vector2.from_angle(to.angle() + lean), u.vel)
		else:
			_turn_to(u, to)
	var tq0 := Time.get_ticks_usec() if algo_probe else 0
	_depth_update()
	_solve()
	if algo_probe:
		stats["us_solve"] = stats.get("us_solve", 0) + Time.get_ticks_usec() - tq0
		_algo_probe()


## 11/19 고유기 선수 (fair_order) —— 행동 사이마다(_between) 양쪽 AI 가 고유기를 정하는데 늘 A 가 먼저였다. 한쪽이 기를 모으기 시작하면
## 전역 간격(ult_gap) 동안 양쪽 다 못 쓰므로, 둘 다 준비된 순간마다 A 가 자리를 잡고 B 는 밀렸다 —— 거울 대전 A 승률 치우침의 본체
## (고유기를 끄면 48.4%, 켜면 64.7% · 960판씩). 고유기를 더 오래 못 쓴 진영이 먼저 정한다. 같으면(개전 직후) 시드 · 행동 번호 해시
const _CAMPS_AB := ["A", "B"]
const _CAMPS_BA := ["B", "A"]
func _camp_order() -> Array:
	if not fair_order:
		return _CAMPS_AB
	var ta: float = _ult_side_t.A
	var tb: float = _ult_side_t.B
	if ta != tb:
		return _CAMPS_AB if ta < tb else _CAMPS_BA
	return _CAMPS_BA if (hash(_fair_seed * 131 + act_n * 7919) >> 5) & 1 == 1 else _CAMPS_AB


## 이번 틱의 부대 처리 순서 (fair_order) —— 진영을 번갈아, 틱마다 먼저 하는 쪽을 바꿔서
func _tick_units() -> Array:
	if not fair_order:
		return units
	return _ord_ba if _tick_b_first else _ord_ab


func _algo_probe() -> void:
	for u in units:
		if not u.alive:
			continue
		var p0: Vector2 = _ap_pos.get(u, u.pos)
		_ap_pos[u] = u.pos
		var d: Vector2 = u.pos - p0
		var spd := d.length() / TICK
		var cls := "r" if u.ranged else "m"
		stats["ap_t_" + cls] = stats.get("ap_t_" + cls, 0.0) + TICK
		if u.tgt != null and u.tgt.alive and _gap(u, u.tgt) <= TOUCH + 3.0:
			if not _ap_met:
				_ap_met = true
				stats["ap_first_touch"] = _tm
		if spd <= 15.0:
			if u.block_t > 0.0:
				stats["ap_blocked_" + cls] = stats.get("ap_blocked_" + cls, 0.0) + TICK      # 막혀서 서 있다
			_ap_dir.erase(u)
			continue
		stats["ap_move_" + cls] = stats.get("ap_move_" + cls, 0.0) + TICK
		stats["ap_dist"] = stats.get("ap_dist", 0.0) + d.length()
		var off := absf(angle_difference(d.angle(), u.fwd.angle()))
		if off > deg_to_rad(120.0):
			stats["ap_back"] = stats.get("ap_back", 0.0) + TICK      # 뒷걸음
		elif off > deg_to_rad(60.0):
			stats["ap_crab"] = stats.get("ap_crab", 0.0) + TICK      # 옆걸음
		if _ap_dir.has(u):
			var turn := absf(angle_difference((_ap_dir[u] as Vector2).angle(), d.angle()))
			if turn > deg_to_rad(50.0):
				stats["ap_zig"] = stats.get("ap_zig", 0) + 1      # 한 틱(0.1초) 사이에 가는 방향이 50도 넘게 꺾였다 (갈지자 · 떨림)
			stats["ap_turn_sum"] = stats.get("ap_turn_sum", 0.0) + turn
		_ap_dir[u] = d


## 앞이 막혔으면 비켜 간다 —— 진행 방향 LOOK 안에 다른 부대(아군 · 노리지 않는 적)가 있으면 그 옆으로. 양쪽 가운데 더 트인 쪽으로,
## 오래 막힐수록 더 옆으로 (예비대가 전선 뒤에서 기다리지 않고 측면으로 흘러 나간다). 원거리는 3초까지는 제자리에서 기다린다
func _steer(u: Unit, dir: Vector2, t: Unit) -> Vector2:
	var blocker := _blocker(u, dir, t, LOOK)
	if blocker == null:
		u.block_t = 0.0
		if algo_v2 and algo_bits & 1 and u.steer_side != 0.0 and u.steer_keep > 0.0:
			# ① 방금 비켜 나왔다 —— 곧장 꺾으면 모서리에 다시 걸린다. 같은 쪽 성분을 줄여 가며 푼다 (그 길이 막혔으면 곧장)
			u.steer_keep -= TICK
			var d2 := (dir + Vector2(-dir.y, dir.x) * u.steer_side * 0.7 * (u.steer_keep / STEER_KEEP)).normalized()
			if _blocker(u, d2, t, LOOK) == null:
				return d2
		u.steer_side = 0.0
		return dir
	if algo_v2 and algo_bits & 4 and _ranged(u) and blocker.camp == u.camp:
		# ③ 앞 아군 바로 뒤까지는 붙는다 —— 한 걸음이라도 다가서면 사거리에 드는 적이 생긴다
		var room := (blocker.pos - u.pos).dot(dir) - _extent(u, dir) - _extent(blocker, dir)
		if room > RANGED_CLOSE:
			return dir
	u.block_t += TICK
	if rigid_probe:
		stats["block_t"] = stats.get("block_t", 0.0) + TICK
	if _ranged(u) and u.block_t < (RANGED_WAIT if algo_v2 and algo_bits & 4 else 3.0):
		return Vector2.ZERO
	var perp := Vector2(-dir.y, dir.x)
	var free_p := _free_run(u, perp, t)
	var free_m := _free_run(u, -perp, t)
	var side := u.steer_side if algo_v2 and algo_bits & 1 else 0.0
	if side != 0.0 and (free_p if side > 0.0 else free_m) < 6.0:
		side = 0.0      # 고른 쪽이 막혔다 —— 다시 고른다
	if side == 0.0:
		if absf(free_p - free_m) > 8.0:
			side = 1.0 if free_p > free_m else -1.0
		else:
			var lat := (t.pos - u.pos).dot(perp)
			side = signf(lat) if absf(lat) > 4.0 else (1.0 if u.slot % 2 == 0 else -1.0)
	if maxf(free_p, free_m) < 6.0:
		u.steer_side = 0.0
		return Vector2.ZERO        # 양옆도 막혔다 —— 기다린다 (앞이 열리면 간다)
	u.steer_side = side
	u.steer_keep = STEER_KEEP
	var k := clampf(0.7 + u.block_t * 0.4, 0.7, 1.6)
	return (dir * 0.6 + perp * side * k).normalized()


## 진행 방향 dir 로 look 안에서 가장 먼저 걸리는 부대 (노리는 적 t 는 뺀다)
func _blocker(u: Unit, dir: Vector2, t: Unit, look: float) -> Unit:
	var perp := Vector2(-dir.y, dir.x)
	var eu := _extent(u, dir)
	var pu := _extent(u, perp)
	var best: Unit = null
	var bd := INF
	for o in units:
		if o == u or o == t or not o.alive:
			continue
		var v := o.pos - u.pos
		var ahead := v.dot(dir)
		if ahead <= 0.0:
			continue
		var of: Vector2 = o.fwd      # 11/15 성능: _extent(o, dir) · _extent(o, perp) 를 풀어 썼다 (같은 식)
		var ort := Vector2(-of.y, of.x)
		var eo: float = o.hd * absf(dir.dot(of)) + o.hw * absf(dir.dot(ort))
		if ahead - eu - eo > look:
			continue
		if absf(v.dot(perp)) >= pu + (o.hd * absf(perp.dot(of)) + o.hw * absf(perp.dot(ort))) + 4.0:
			continue
		if ahead < bd:
			bd = ahead
			best = o
	return best


## 그 방향으로 막히지 않고 갈 수 있는 거리 (최대 LOOK · 4)
func _free_run(u: Unit, dir: Vector2, t: Unit) -> float:
	var b := _blocker(u, dir, t, LOOK * 4.0)
	if b == null:
		return LOOK * 4.0
	return maxf(0.0, (b.pos - u.pos).dot(dir) - _extent(u, dir) - _extent(b, dir))


## 병력이 줄면 깊이가 뒤에서부터 줄어든다 —— 앞줄은 그 자리 (맞닿은 전선이 유지된다)
func _depth_update() -> void:
	for u in units:
		if not u.alive:
			continue
		var nh := maxf(u.hd0 * clampf(u.troops / maxf(1.0, u.max), 0.0, 1.0), HD_MIN)
		if absf(nh - u.hd) > 0.01:
			u.pos += u.fwd * (u.hd - nh)
			u.hd = nh


## 도적 우회 길목 —— 아직 노리는 적보다 앞(우리 쪽)에 있으면 적 무리 옆 바깥 점, 지나갔으면 null (곧장 친다)
var _flank := {}        # 유닛 -> 돌아갈 쪽 (+1 · -1), 처음 한 번 정한다
var _rogue_held := {}   # [도적, 창병] -> 남은 붙잡힘 초 (도적 대책 2)
static var rogue_hold := 2.5      # 11/19 창병이 맞닿은 도적을 붙잡는 초 (0 이면 예전처럼 흘려 지나간다)
static var escort_w := 0.4        # 11/19 도적 대책 1 —— 우리 후열에 붙은 적 기병 · 도적을 놀던 근접 부대가 고를 때 거리 배율 (1 이면 예전)
const ESCORT_R := 320.0           # 호위하러 갈 최대 거리
func _flank_way(u: Unit, t: Unit, foes: Array):
	var ahead := 1.0 if u.camp == "A" else -1.0       # A 는 +x 로 나아간다
	if (t.pos.x - u.pos.x) * ahead < 40.0:
		return null
	var c := _centroid(foes)
	if not _flank.has(u):
		var sd := signf(u.pos.y - c.y)
		_flank[u] = sd if sd != 0.0 else (1.0 if u.slot % 2 == 0 else -1.0)
	var half := 0.0
	for o in foes:
		half = maxf(half, absf(o.pos.y - c.y) + o.hw)
	return Vector2(t.pos.x - ahead * 30.0, c.y + _flank[u] * (half + u.hw + 60.0))


func _choose(u: Unit, foes: Array) -> Unit:
	if u.ranged:
		return _nearest_ranged_target(u, foes, false)
	var best: Unit = null
	var bs := INF
	var best0: Unit = null      # 1.2 개성 표적 가중을 뺀 선택 (개성 때문에 바뀌었나 세는 용)
	var bs0 := INF
	var lane: bool = not _ranged(u) and u.c.tag != "기병" and u.c.tag != "도적"
	for o in foes:
		var d := maxf(0.0, _gap(u, o))
		if lane:      # 앞 열 우선 —— 진형 폭만큼 전선이 넓게 선다 (옆 거리는 무겁게)
			d = maxf(0.0, Vector2(o.pos.x - u.pos.x, (o.pos.y - u.pos.y) * LANE_W).length() - u.hd - o.hd)
		if _pa_wei(o):
			d = (d + 30.0) * 2.0      # 장료 위진소요진 —— 거리를 두 배로 쳐서 덜 노려진다
		var w := 1.0
		# 기병 · 도적은 원거리 · 지략 부대를 노린다 (멀리 돌아가더라도)
		if (u.c.tag == "기병" or u.c.tag == "도적") and _ranged(o):
			w = 0.6 if u.c.tag == "도적" else 0.75
		if u.tgt == o:
			w *= 0.8            # 노리던 적을 쉽게 바꾸지 않는다
		# 11/19 사용자: 도적 대책 1 (호위) —— 우리 원거리 · 책략 부대에 붙은 적 기병 · 도적은 근접 부대(도적 제외)가 막으러 간다.
		# 맞붙어 묶인 부대는 여기 오지 않는다(_choose 는 묶이지 않았을 때만) —— 놀거나 막혀 기다리던 부대가 돌아선다
		if escort_w < 1.0 and not _ranged(u) and u.c.tag != "도적" and (o.c.tag == "도적" or o.c.tag == "기병") 				and o.tgt != null and o.tgt.alive and o.tgt.camp == u.camp and _ranged(o.tgt) and _gap(o, o.tgt) <= TOUCH + 6.0 and d < ESCORT_R:
			w *= escort_w
			if best != o and d * w < bs:
				stats["escort"] = int(stats.get("escort", 0)) + 1
		# 11/7 강체: 앞이 막힌 지 1초가 넘은 근접 부대는 길이 트인 적을 고른다 (예비대가 전선 뒤에서 기다리지 않고 측면의 적에게 간다)
		if lane and u.block_t > 1.0:
			var dv: Vector2 = o.pos - u.pos
			if dv.length() > 1.0 and _blocker(u, dv.normalized(), o, LOOK * 2.0) != null:
				w *= 1.6
		# 11/3 창병 도발 —— 가까이 온 근접 적은 창병부터 친다 (도적은 흘려 지나간다)
		if Battle.tag_roles and o.c.tag == "창병" and not _ranged(u) and u.c.tag != "도적" and d < TAUNT_R:
			w *= 0.5
		if not _ranged(u):
			# 근접은 아군이 이미 몰려 싸우는 적보다 빈 적을 (줄 서서 놀지 않게)
			var crowd := 0
			for al in units:
				# 11/15 성능: 멀리 있는 아군은 틈을 재지 않는다 (위 _move 의 맞닿음 판정과 같은 까닭 —— 틈이 TOUCH + 4 를 넘는 것이 확실하다)
				if al != u and al.alive and al.camp == u.camp and not al.ranged and al.pos.distance_to(o.pos) * 0.7 <= al.hw + al.hd + o.hw + o.hd + 14.0 and _gap(al, o) <= TOUCH + 4.0:
					crowd += 1
			w *= 1.0 + 0.35 * crowd
		if d * w < bs0:
			bs0 = d * w
			best0 = o
		if _sg != null:
			w *= _sg.target_w(u, o, d)      # 11/19 장수 개성 —— 도발 · 노리는 적 · 지목
		if d * w < bs:
			bs = d * w
			best = o
	if _sg != null and best != best0 and best != null and not u.m.is_empty():
		_sg.note_pick(u, best)
	return best


func _centroid(us: Array) -> Vector2:
	var c := Vector2.ZERO
	for o in us:
		c += o.pos
	return c / maxf(1, us.size())


## 돌기 —— TURN_RATE 까지. 돌아서 옆 부대를 더 파고들게 되면 반 · 반의 반만 돌고, 그래도 파고들면 이번 틱은 멈춘다 (대열이 이웃을 쓸고 지나가지 않게)
## open_v (11/19 ②) —— 둘레에 다른 부대가 없을 때(트인 곳을 돌아갈 때)는 v 대신 이쪽을 본다. 붐비는 곳에서 넓은 대열이 돌면 이웃과 부딪쳐 막힘 · 떨림이 늘었다
func _turn_to(u: Unit, v: Vector2, open_v := Vector2.ZERO) -> void:
	if v.length() < 0.001:
		return
	var a0 := u.fwd.angle()
	var near := []
	var reach := u.hw + u.hd + 4.0
	var scanned := false
	if open_v != Vector2.ZERO:
		scanned = true
		var wide := reach + FACE_CLEAR
		var open := true
		for o in units:
			if o != u and o.alive:
				var od := u.pos.distance_to(o.pos)
				if od < reach + o.hw + o.hd:
					near.append(o)
				if od < wide + o.hw + o.hd:
					open = false
		if open:
			v = open_v
	var a1 := rotate_toward(a0, v.angle(), TURN_RATE * TICK)
	if absf(a1 - a0) < 0.0001:
		return
	if not scanned:
		for o in units:
			if o != u and o.alive and u.pos.distance_to(o.pos) < reach + o.hw + o.hd:
				near.append(o)
	var pen0 := _pen_sum(u, near)
	var f0 := u.fwd
	for k in [1.0, 0.5, 0.25]:
		u.fwd = Vector2.from_angle(lerp_angle(a0, a1, k))
		if near.is_empty() or _pen_sum(u, near) <= pen0 + 0.5:
			return
	u.fwd = f0


## 이웃 발자국에 파고든 깊이의 합 (아군은 틈 0, 적은 FOE_MIX 까지는 봐 준다)
func _pen_sum(u: Unit, near: Array) -> float:
	var s := 0.0
	for o in near:
		var g := _gap(u, o)
		var allow: float = 0.0 if o.camp == u.camp else FOE_MIX
		if g < -allow:
			s += -allow - g
	return s


## 겹치지 않게 (11/7 강체) —— 발자국끼리 분리축 판정으로 겹친 만큼 민다. 아군은 ALLY_GAP 틈을 두고, 적은 FOE_MIX 까지만 파고든다.
## 병력이 많은 쪽이 덜 밀린다(떠밀기 —— 큰 군세가 작은 부대를 밀어낸다). 몇 번 되풀이해 연쇄 겹침까지 푼다. 밀린 쪽은 그쪽으로 가던 속도를 잃는다
func _solve() -> void:
	var live: Array = units.filter(func(o): return o.alive and not _dash.has(o))      # 11/17 돌진 중인 고유기 장수는 대열을 뚫고 지나간다 (닿아 터진 뒤 다시 밀어낸다)
	var pre := {}
	for u in live:
		pre[u] = u.pos
	# 11/15 성능: 방향 · 발자국 크기는 푸는 동안 바뀌지 않는다(자리만 밀린다) —— 부대마다 한 번 읽어 두고, 축 배열 · _extent 호출은 풀어 썼다 (식 · 순서 그대로)
	var n_live := live.size()
	var fw: Array[Vector2] = []
	var rt: Array[Vector2] = []
	var hds := PackedFloat64Array()
	var hws := PackedFloat64Array()
	for u in live:
		var f: Vector2 = u.fwd
		fw.append(f)
		rt.append(Vector2(-f.y, f.x))
		hds.append(u.hd)
		hws.append(u.hw)
	for it in SOLVE_ITERS:
		var moved := false
		for i in n_live:
			var a: Unit = live[i]
			var af := fw[i]
			var ar := rt[i]
			var ahd := hds[i]
			var ahw := hws[i]
			var acamp := a.camp
			for j in range(i + 1, n_live):
				var b: Unit = live[j]
				var want: float = ALLY_GAP if acamp == b.camp else -FOE_MIX
				var d: Vector2 = b.pos - a.pos
				var bhd := hds[j]
				var bhw := hws[j]
				if d.length() > ahw + ahd + bhw + bhd + want:
					continue
				var bf := fw[j]
				var br := rt[j]
				var best := -INF
				var bn := Vector2.ZERO
				var proj := d.dot(af)
				var sep := absf(proj) - (ahd * absf(af.dot(af)) + ahw * absf(af.dot(ar))) - (bhd * absf(af.dot(bf)) + bhw * absf(af.dot(br)))
				if sep > best:
					best = sep
					bn = af if proj >= 0.0 else -af
				proj = d.dot(ar)
				sep = absf(proj) - (ahd * absf(ar.dot(af)) + ahw * absf(ar.dot(ar))) - (bhd * absf(ar.dot(bf)) + bhw * absf(ar.dot(br)))
				if sep > best:
					best = sep
					bn = ar if proj >= 0.0 else -ar
				proj = d.dot(bf)
				sep = absf(proj) - (ahd * absf(bf.dot(af)) + ahw * absf(bf.dot(ar))) - (bhd * absf(bf.dot(bf)) + bhw * absf(bf.dot(br)))
				if sep > best:
					best = sep
					bn = bf if proj >= 0.0 else -bf
				proj = d.dot(br)
				sep = absf(proj) - (ahd * absf(br.dot(af)) + ahw * absf(br.dot(ar))) - (bhd * absf(br.dot(bf)) + bhw * absf(br.dot(br)))
				if sep > best:
					best = sep
					bn = br if proj >= 0.0 else -br
				if best >= want:
					continue
				var push := want - best
				var ma := a.troops + 1.0
				var mb := b.troops + 1.0
				a.pos -= bn * push * (mb / (ma + mb))
				b.pos += bn * push * (ma / (ma + mb))
				moved = true
		for u in live:
			var p0: Vector2 = u.pos
			_clamp_arena(u)
			if u.pos != p0:
				moved = true
		if not moved:
			break      # 11/15 성능: 이번 바퀴에 아무도 밀리지 않았다 —— 남은 바퀴도 똑같이 아무 일이 없다
	if rigid_probe:      # 남은 겹침 —— 풀고도 1px 넘게 파고든 쌍 (연쇄 겹침이 다 안 풀린 경우)
		for i in live.size():
			for j in range(i + 1, live.size()):
				var want_ij: float = ALLY_GAP if live[i].camp == live[j].camp else -FOE_MIX
				var pen: float = want_ij - _gap(live[i], live[j])
				if pen > 1.0:
					stats["pen_n"] = stats.get("pen_n", 0) + 1
					stats["pen_max"] = maxf(float(stats.get("pen_max", 0.0)), pen)
		for u in live:
			if absf(u.pos.y) > CS * lay * 1.5 + u.hw * 0.5:
				stats["flank_t"] = stats.get("flank_t", 0.0) + TICK      # 진형 바깥 옆으로 돈 시간 (유닛 합)
	for u in live:
		var corr: Vector2 = u.pos - pre[u]
		if corr.length() > 0.01:
			var n := corr.normalized()
			var into: float = u.vel.dot(n)
			if into < 0.0:
				u.vel -= n * into        # 막힌 쪽으로 가던 속도는 버린다 (벽에 대고 미끄러지듯)


func _clamp_arena(u: Unit) -> void:
	var ex := _extent(u, Vector2.RIGHT)
	var ey := _extent(u, Vector2.DOWN)
	u.pos.x = clampf(u.pos.x, arena.position.x + ex, arena.end.x - ex)
	u.pos.y = clampf(u.pos.y, arena.position.y + ey, arena.end.y - ey)


func _record() -> void:
	_next_track = _tm + TRACK_EVERY
	var fr := []
	for u in units:
		var ti := -1
		if u.tgt != null and u.tgt.alive:
			ti = _idx[u.tgt]
		var touch := 1 if ti >= 0 and _gap(u, u.tgt) <= TOUCH + 3.0 else 0
		fr.append([roundi(u.pos.x), roundi(u.pos.y), snappedf(u.fwd.angle(), 0.01), ti, touch])
	track.append([snappedf(_tm, 0.01), fr])


# ───────── 위치로 대상 고르기 ─────────

## 행동 · 기술 · 고유기의 대상 —— 위치로 고른다. 고유기는 거리 제한 없이 크게
func resolve_targets(spec: String, foes: Array, me: Unit, allies: Array) -> Array:
	if spec == "self": return [me]
	if spec == "allyAll": return allies.filter(func(u): return u.alive)
	if spec == "allyFront":
		var al := allies.filter(func(u): return u.alive)
		if al.is_empty(): return []
		var fr := _foes_of(me)
		if fr.is_empty(): return al
		var dist := al.map(func(o): return fr.map(func(f): return o.pos.distance_to(f.pos)).min())
		var mn: float = dist.min()
		var out := []
		for i in al.size():
			if dist[i] <= mn + 30.0:
				out.append(al[i])
		return out
	var live := foes.filter(func(u): return u.alive and not _hidden(u))
	if live.is_empty(): return []
	var reach := INF if _in_ult else _reach(me) + 2.0
	var near := live.filter(func(o): return _gap(me, o) <= reach)
	var main: Unit = me.tgt if me.tgt != null and me.tgt.alive and near.has(me.tgt) else null
	if main == null:
		main = _nearest(me.pos, near if not near.is_empty() else live)
	if near.is_empty() and not _in_ult:
		return []
	match spec:
		"front1":
			return [main]
		# 11/2 최후열은 설명대로 적진에서 가장 깊은 부대 (사거리 안만 보던 것을 고침 —— 앞 적이 막아도 뒤를 친다)
		"back1":
			var d1 := _deepest(me, live)
			_mark(me, {"k": "circle", "x": roundi(d1.pos.x), "y": roundi(d1.pos.y), "r": 60})
			return [d1]
		"back2":
			var s := live.duplicate()
			s.sort_custom(func(a, b): return _depth(me, a) > _depth(me, b))
			for o in s.slice(0, 2):
				_mark(me, {"k": "circle", "x": roundi(o.pos.x), "y": roundi(o.pos.y), "r": 60})
			return s.slice(0, 2)
		"front3":
			var s := live.filter(func(o): return o == main or _gap(o, main) <= AREA_GAP)
			s.sort_custom(func(a, b): return (-1.0 if a == main else _gap(a, main)) < (-1.0 if b == main else _gap(b, main)))
			s = s.slice(0, 3)
			_mark_targets(me, s)
			return s
		"all":
			if _in_ult:
				if ult_all_r <= 0.0 and ult_all_n <= 0:
					_mark_targets(me, live)
					return live
				return _ult_area(me, main, live)
			return live.filter(func(o): return me.pos.distance_to(o.pos) <= all_r)
		"denseLine":
			var best: Array = [main]
			for c in near:
				var g := live.filter(func(o): return o == c or _gap(o, c) <= AREA_GAP)
				if g.size() > best.size():
					best = g
			_mark_targets(me, best)
			return best
	# 11/2 열 —— 설명대로 적 진영의 앞쪽(선봉 · 전군) / 뒤쪽(후군) 절반, 최대 3부대 (예전엔 나에서 대상으로 뻗은 띠였다)
	if spec == "line:선봉+전군" and _dash_ult(me):
		# 돌격 고유기 —— 달려온 길(예고 때는 달려갈 길) 띠 안의 적, 부딪힌 적에 가까운 순으로 3부대까지
		var org: Vector2 = _dash_from.get(me, me.pos)
		var hit: Unit = me.tgt if me.tgt != null and me.tgt.alive and live.has(me.tgt) and _dash_from.has(me) else null
		if hit == null:
			hit = _dash_target(me)
		if hit == null:
			return []
		var dir := (hit.pos - org).normalized()
		if dir == Vector2.ZERO:
			dir = me.fwd
		var ln := org.distance_to(hit.pos) + 80.0
		var perp := Vector2(-dir.y, dir.x)
		var s := live.filter(func(o):
			var v: Vector2 = o.pos - org
			var along := v.dot(dir)
			return o == hit or (along >= -10.0 and along <= ln + _extent(o, dir) and absf(v.cross(dir)) <= LINE_W + _extent(o, perp)))
		s.sort_custom(func(a, b): return a.pos.distance_squared_to(hit.pos) < b.pos.distance_squared_to(hit.pos))
		s = s.slice(0, 3)
		if _dash_from.has(me) and not _target_preview:
			for o in s:
				stats["dash_line_far"] = maxf(float(stats.get("dash_line_far", 0.0)), _gap(me, o))
		var tip := org + dir * ln
		_mark(me, {"k": "line", "x": org.x, "y": org.y, "x2": tip.x, "y2": tip.y, "w": LINE_W})
		return s
	if spec == "line:후군" or spec == "line:선봉+전군":
		var s := live.duplicate()
		var back := spec == "line:후군"
		s.sort_custom(func(a, b): return _depth(me, a) > _depth(me, b) if back else _depth(me, a) < _depth(me, b))
		s = s.slice(0, mini(3, ceili(s.size() / 2.0)))
		for o in s:
			_mark(me, {"k": "circle", "x": roundi(o.pos.x), "y": roundi(o.pos.y), "r": 60})
		return s
	if spec.begins_with("line:"):
		# 줄 —— 나에서 대상으로 뻗은 띠 안의 적 모두
		var dir := (main.pos - me.pos).normalized()
		var ln := me.pos.distance_to(main.pos) + 80.0
		var perp := Vector2(-dir.y, dir.x)
		var s := live.filter(func(o):
			var v: Vector2 = o.pos - me.pos
			var along := v.dot(dir)
			return along >= -10.0 and along <= ln + _extent(o, dir) and absf(v.cross(dir)) <= LINE_W + _extent(o, perp))
		var tip := me.pos + dir * ln
		_mark(me, {"k": "line", "x": me.pos.x, "y": me.pos.y, "x2": tip.x, "y2": tip.y, "w": LINE_W})
		return s if not s.is_empty() else [main]
	return [main]


## 고유기 '적 전체' 범위 (11/7 2차) —— 노리는 적 둘레 반지름 ult_all_r 안 (발자국 가장자리가 걸치면), 가까운 순으로 ult_all_n 까지.
## 기 모으기 예고(_interrupt_ult) · 실제 터짐 · 사람이 누른 고유기 모두 이 함수 —— 같은 규칙
func _ult_area(me: Unit, main: Unit, live: Array) -> Array:
	var c := main.pos
	var s := live.filter(func(o):
		if o == main or ult_all_r <= 0.0:
			return true
		var v: Vector2 = c - o.pos
		return v.length() - _extent(o, v.normalized()) <= ult_all_r)
	s.sort_custom(func(a, b): return a.pos.distance_squared_to(c) < b.pos.distance_squared_to(c))
	if ult_all_n > 0 and s.size() > ult_all_n:
		s = s.slice(0, ult_all_n)
	if ult_all_r > 0.0:
		_mark(me, {"k": "circle", "x": c.x, "y": c.y, "r": ult_all_r})
	if ult_all_r <= 0.0 or ult_all_n > 0:
		_mark_targets(me, s)
	return s


## Gap-based groups and capped/global skills select units rather than a circle.
## Record each selected footprint, including its orientation, at this instant.
func _mark_targets(me: Unit, targets: Array) -> void:
	for target: Unit in targets:
		var forward := target.fwd * target.hd
		var side := target.fwd.orthogonal() * target.hw
		var boundary := []
		for offset in [-forward - side, forward - side, forward + side, -forward + side]:
			var point: Vector2 = target.pos + offset
			boundary.append([point.x, point.y])
		_mark(me, {"k": "footprint", "x": target.pos.x, "y": target.pos.y,
			"r": 0.0, "target": target.key, "boundary": boundary})


## 범위 기록 —— 방금 펼친 기술 · 고유기 사건에 덮은 곳을 적는다 (화면이 땅에 미리 그린다)
func _mark(me: Unit, shape: Dictionary) -> void:
	if _target_preview:
		if _capture_preview_areas:
			_preview_areas.append(shape.duplicate(true))
		return
	for i in range(ev.size() - 1, maxi(-1, ev.size() - 40), -1):
		var e: Dictionary = ev[i]
		if (e.get("fx") == "skill" or e.get("fx") == "ult") and e.get("a") == me.key:
			if not e.has("area"):
				e["area"] = []
			e.area.append(shape)
			return


## 기본 공격: 원거리는 사거리 안 최근접, 도적은 기존 후열 특성을 유지한다.
func basic_target(u: Unit, foes: Array) -> Array:
	if u.ranged:
		var nearest := _nearest_ranged_target(u, foes)
		return [nearest] if nearest != null else []
	var back: bool = probe_back_basic and ((u.c.tag == "궁병" and (u.caps.has("궁병") or DB.aff_of(u.c.tag, u.line, u.side) == "pref")) 		or u.c.tag == "도적" or is_caster(u.c))
	return resolve_targets("back1" if back else "front1", foes, u, [])


## Keep the existing footprint-gap range rule, then rank eligible enemies by
## center distance. Movement may approach the nearest enemy only if none is in range.
func _nearest_ranged_target(u: Unit, foes: Array, only_in_range := true) -> Unit:
	var best: Unit = null
	var approach: Unit = null
	var best_d := INF
	var approach_d := INF
	var reach := _reach(u) + 2.0
	# 11/19 성능: 가운데끼리 멀면 틈이 사거리를 넘는 것이 확실하다 (틈 ≥ 거리 / √2 − 두 발자국의 반폭 + 반깊이) —— 그런 적은 틈을 재지 않는다.
	# 원거리 부대마다 틱에 두 번(이동 · 행동) 적 전부의 틈을 쟀다. 결과는 같다 (tests/algo_audit 지문 동일)
	var far := reach + u.hw + u.hd
	var track: bool = _sg != null and only_in_range and not u.m.is_empty()      # 1.2 개성 때문에 표적이 바뀌었나 세려고 개성 없는 최근접도 함께 본다
	var plain: Unit = null
	var plain_d := INF
	for o in foes:
		if not o.alive or o.camp == u.camp or _hidden(o):
			continue
		var distance := u.pos.distance_squared_to(o.pos)
		if track and distance < plain_d:
			var lim0: float = (far + o.hw + o.hd) / 0.7
			if distance <= lim0 * lim0 and _gap(u, o) <= reach:
				plain = o
				plain_d = distance
		if not only_in_range and distance < approach_d:
			approach = o
			approach_d = distance
		var sc := distance
		if _sg != null:      # 11/19 장수 개성 —— 원거리도 도발 · 노리는 적을 따른다 (사거리 안에서만)
			var sw: float = _sg.target_w(u, o, sqrt(distance))
			sc *= sw * sw
		if sc < best_d:
			var lim: float = (far + o.hw + o.hd) / 0.7
			if distance <= lim * lim and _gap(u, o) <= reach:
				best = o
				best_d = sc
	if track and best != null and best != plain:
		_sg.note_pick(u, best)
	return best if best != null or only_in_range else approach


## 원거리 부대 u 에 맞닿은 근접 적 가운데 가장 가까운 것 (없으면 null) —— _pinned 와 같은 기준(틈 TOUCH + 2)
func _pinner(u: Unit, foes: Array) -> Unit:
	var best: Unit = null
	var bd := TOUCH + 2.0
	var far_r := u.hw + u.hd + 12.0
	for o in foes:
		if not o.alive or o.ranged or o.camp == u.camp or _hidden(o) or u.pos.distance_to(o.pos) * 0.7 > far_r + o.hw + o.hd:
			continue
		var g := _gap(u, o)
		if g <= bd:
			bd = g
			best = o
	return best


func _nearest(p: Vector2, us: Array) -> Unit:
	var best: Unit = null
	var bd := INF
	for o in us:
		var d := p.distance_to(o.pos)
		if d < bd:
			bd = d
			best = o
	return best


## 적진 깊이 —— 그 적 진영 쪽으로 얼마나 물러나 있나 (A 는 왼쪽, B 는 오른쪽에서 시작)
func _depth(me: Unit, o: Unit) -> float:
	return o.pos.x if me.camp == "A" else -o.pos.x


func _deepest(me: Unit, us: Array) -> Unit:
	var best: Unit = us[0]
	for o in us:
		if _depth(me, o) > _depth(me, best):
			best = o
	return best


# ───────── 방향 · 반격 ─────────

## 옆 · 뒤에서 친 물리 피해 +, 떨어진 곳(활 · 고유기)에서 맞으면 반격하지 않는다
func phys_hit(a: Unit, d: Unit, mult: float, no_counter := false, pierce := 0.0) -> void:
	var v := (a.pos - d.pos)
	var far := _gap(a, d) > melee_gap + 6.0
	var m := mult
	var dir := ""
	if v.length() > 0.1 and not _in_ult:
		var ang := absf(d.fwd.angle_to(v))
		if ang > PI * 2.0 / 3.0:
			m *= 1.0 + REAR
			dir = "후방"
			stats["rear"] = stats.get("rear", 0) + 1
		elif ang > PI / 3.0:
			m *= 1.0 + SIDE
			dir = "측면"
			stats["side"] = stats.get("side", 0) + 1
	if not terrain.is_empty():
		if _in(d.pos, "forest"):
			m *= FOREST.def * (FOREST.arrow if far else 1.0)
		if _in(d.pos, "river"):
			m *= RIVER.hurt
		if _in(a.pos, "hill") and not _in(d.pos, "hill"):
			m *= HILL.hit
	var painted_charge := ""
	if not _in_ult:
		m *= far_mul if far else near_mul
		if a.c.tag == "기병" and a.ran >= CHARGE_RUN * (1.0 - minf(0.7, mv(a, "charge_run"))) and not far and not a.countering and not (water_enabled and has_st(a, "flood")):     # 수몰된 기병은 돌격을 못 한다 (11/8 수공 제어 전담)
			if d.c.tag == "창병" and _front(d, a):      # 11/8 창병 정면은 돌격을 막는다 (창벽)
				m *= engage_v("brace", 1.0)
				painted_charge = "brace"
			else:
				m *= cav_charge * (1.0 + mv(a, "charge_amp"))
				stats["charges"] = stats.get("charges", 0) + 1
				painted_charge = "hit"
				if _sg != null:      # 1.2 기병 —— 돌격 개성(맹습 · 즉시 돌격 · 무쌍) 계수 · 말풍선
					_sg.on_charge(a, d)
		if a.c.tag == "창병" and a.ran >= SPEAR_RUN and not far and not a.countering:      # 11/8 창병은 붙는 순간이 힘
			m *= engage_v("spear_impact", 1.0)
	var heavy := false
	if not _in_ult and not a.countering and heavy_every.has(a.c.tag):
		if a.atk_act != act_n:
			a.atk_act = act_n
			a.atk_n += 1
			if a.atk_n % int(heavy_every[a.c.tag]) == 0:
				stats["heavies"] = stats.get("heavies", 0) + 1
		if a.atk_n % int(heavy_every[a.c.tag]) == 0:
			m *= heavy_mul
			heavy = true
	if not _in_ult and not a.countering and not a.opened:
		a.opened = true
		var fs := float(first_strike.get(a.c.tag, 1.0))
		if fs != 1.0:
			m *= fs
			stats["first_strikes"] = stats.get("first_strikes", 0) + 1
	if a.c.tag == "창병" and d.c.tag == "창병" and a.camp != d.camp:      # 11/14 창병끼리 —— 창병 갑옷 · 방어 이점이 서로 상쇄돼 판이 늘어진다 (거울전 53초 → 35초 안팎)
		m *= engage_v("spear_mirror", 1.0)
	if not a.countering:
		a.ran = 0.0
	if tac != null:
		m *= tac.hit_mul(a, d, far)      # 11/15 군략 —— 주는 피해 · 적 공격 − · 받는 피해
	if _sg != null and a.camp != d.camp:
		m *= _sg.amp(a, d, far) * _sg.taken(d, a, m)      # 11/19 장수 개성 —— 주는 · 받는 피해
	var n0 := ev.size()
	super.phys_hit(a, d, m, no_counter or far, pierce)
	if _sg != null and a.camp != d.camp:
		var sl := 0.0
		for i in range(n0, ev.size()):
			if (ev[i].get("fx") == "phys" or ev[i].get("fx") == "int") and ev[i].get("a") == a.key and ev[i].get("f") == d.key:
				sl = float(ev[i].get("n", 0.0))
				break
		if sl > 0.0:
			_sg.after_hit(a, d, sl, far)
			_sg.after_taken(d, a, sl, far)
	if tac != null:      # 되돌림 · 화살비 · 불화살 —— 이 타격으로 깎인 병력 기준
		for i in range(n0, ev.size()):
			if (ev[i].get("fx") == "phys" or ev[i].get("fx") == "int") and ev[i].get("a") == a.key and ev[i].get("f") == d.key and not ev[i].has("tac"):
				tac.after_hit(a, d, far, float(ev[i].get("n", 0.0)))
				break
	if _in_ult and _wind.has(d) and d.camp != a.camp:
		_cut_wind(d, a)
	if heavy:      # 11/19 결정타 —— 사건에 적어 둔다 (화면 연출용)
		for i in range(n0, ev.size()):
			if (ev[i].get("fx") == "phys" or ev[i].get("fx") == "int") and ev[i].get("a") == a.key and ev[i].get("f") == d.key:
				ev[i]["heavy"] = true
				break
	if dir != "" or painted_charge != "":
		# 이 타격의 사건에 방향을 적는다 —— 화면이 '측면!' · '후방!' 을 띄운다
		for i in range(n0, ev.size()):
			if ev[i].get("fx") == "phys" and ev[i].get("a") == a.key and ev[i].get("f") == d.key:
				if dir != "":
					ev[i]["dir"] = dir
				if painted_charge != "":
					ev[i]["painted_charge"] = painted_charge
				break


# ───────── 11/8 맞붙음 상성 (class_guard.engage) ─────────
const SPEAR_RUN := 60.0      # 창병이 이만큼 걸어와 친 첫 공격이 '붙는 순간'

## a 가 d 의 정면(앞 60도 안)에 있는가
static func _front(d: Unit, a: Unit) -> bool:
	var v := a.pos - d.pos
	return v.length() < 0.1 or absf(d.fwd.angle_to(v)) <= PI / 3.0


## 원거리(궁병 · 책략계)가 근접 적에게 맞닿아 묶였는가
func _pinned(u: Unit) -> bool:
	if not _ranged(u):
		return false
	for o in units:
		if o.alive and o.camp != u.camp and not _ranged(o) and _gap(u, o) <= TOUCH + 2.0:
			return true
	return false


## 실제 자리에서 생기는 상성 —— 묶인 원거리는 덜 치고 더 맞는다 · 창병 정면의 도적 · 묶이지 않은 후열을 노리는 도적 · 창병 없는 궁병과 꺾인 적을 노리는 기병
func _engage_mul(a: Unit, d: Unit) -> float:
	if not counter_enabled or a.camp == d.camp:
		return 1.0
	var m := 1.0
	var pa := _pinned(a)
	var pd := _pinned(d)
	if pa:
		m *= engage_v("pin_atk", 1.0)
	if pd:
		m *= engage_v("pin_taken", 1.0)
	match a.c.tag:
		"도적":
			if d.c.tag == "창병" and _front(d, a):
				m /= engage_v("rogue_front", 1.0)
			elif _ranged(d) and not pd:
				m *= engage_v("rogue_free", 1.0)
		"창병":
			if d.c.tag == "도적" and _front(a, d):
				m *= engage_v("rogue_front", 1.0)
		"기병":
			if d.c.tag == "궁병" and not units.any(func(o): return o.alive and o.camp == d.camp and o.c.tag == "창병"):
				m *= engage_v("horse_bow", 1.0)
			if d.morale < 60.0:
				m *= engage_v("horse_low", 1.0)
	return m


func int_hit(a: Unit, d: Unit, mult: float, spread: int) -> void:
	var m := mult
	if not terrain.is_empty() and _in(a.pos, "hill") and not _in(d.pos, "hill"):
		m *= HILL.hit
	if not _in_ult:      # 11/6 #15 책략 배율(int_mul · int_tier)은 쓰지 않는다 —— 거리 배율만
		if _gap(a, d) > melee_gap + 6.0:
			m *= far_mul
	super.int_hit(a, d, m, spread)
	if _in_ult and _wind.has(d) and d.camp != a.camp:
		_cut_wind(d, a)


# ───────── 11/12 인연 주제 —— 연쇄가 끝나면 그 인연 계열의 큰 효과 (기존 전투 효과를 그대로 쓴다) ─────────
## 수치는 [2명, 3명 이상]. 피해형은 작게 —— 상태 · 처형 · 버프 위주. 인연기(FIN)가 있는 인연은 인연기 다음에 터지고, 주제는 인연기와 겹치지 않게 골랐다(data/inyeon.json theme).
static var THEME := {
	"ignite": {"burn": [0.05, 0.07], "dur": [2, 3], "pop": [0.5, 0.7]},      # 점화 —— 안 타는 적은 화상, 이미 타는 적은 남은 화상의 pop 만큼 즉시 터진다
	"spread": {"burn": [0.04, 0.06], "dur": [2, 3]},                         # 불길 번짐 —— 적 선봉 화상 + 타는 적마다 같은 열로 번짐
	"blaze": {"amp": [1.25, 1.4], "burn": [0.04, 0.06], "dur": [2, 3]},      # 연소 —— 타는 적의 불길이 거세진다(세기 ×amp · 1턴 더), 안 타는 적은 화상
	"steam": {"burn": [0.04, 0.06], "dur": [2, 3], "amp": 1.3},              # 증기 —— 적 전원 수몰 + 화상, 화상 ×1.3
	"flood": {"dur": [2, 3], "rout": [0.15, 0.2]},                            # 침수 —— 적 전원 수몰, 병력 rout 아래 적은 휩쓸려 패주
	"tide": {"dur": [2, 3], "mult": [0.5, 0.75]},                             # 백의도강 —— 적 후군 수몰 + 기습(물리 일격)
	"counter": {"p": [0.35, 0.5], "amp": [0.3, 0.5], "dur": 2},              # 반격 —— 아군 전원 반격 확률 · 반격 피해 + (2턴)
	"chase": {"mult": [0.8, 1.0]},                                            # 추격 —— 연쇄에 든 장수마다 적을 몰아친다 (연쇄 동안 무너진 적만큼, 1~2번)
	"momentum": {"amp": [0.25, 0.4]},                                         # 기세 —— 아군 전원 다음 공격 +
	"exec": {"at": [0.3, 0.4]},                                               # 비장 —— 방어가 깎인 적 중 병력 at 아래를 베어 넘기고, 적 선봉 방어를 깎는다
	"confuse": {"n": [2, 3]},                                                 # 혼란(반목 · 반간 · 미인계 · 위압) —— 적 상위 n 부대 혼란
	"slow": {"gauge": [15.0, 25.0]},                                          # 둔화 —— 적 전원 수몰(발 묶임) + 고유기 게이지 −
	"ambush": {"gauge": [20.0, 30.0]},                                        # 매복 —— 기 모으는 적은 끊고, 나머지는 게이지 −
	"plague": {"val": [8.0, 12.0], "dur": [2, 3]},                            # 역병 · 봉인 —— 적 전원 역병 + 적 최강 장수 봉인
	"cleanse": {"n": [1, 2], "morale": [8.0, 14.0]},                          # 정화 · 고무 —— 아군 전원 상태이상 해제 + 사기
	"duel": {"mult": [1.0, 1.6], "morale": [12.0, 20.0]},                     # 일기토 —— 적 최강 장수에게 일격 + 사기
}


func _yeon_best(foes: Array) -> Unit:      # 적 최강 장수 —— 등급, 같으면 남은 병력 (인연기 duel 과 같은 기준)
	var best: Unit = foes[0]
	for t in foes:
		if t.c.tier > best.c.tier or (t.c.tier == best.c.tier and t.troops > best.troops):
			best = t
	return best


func _inyeon_theme_fire(grp: Dictionary) -> void:
	var def: Dictionary = DB.inyeon_theme(grp.name)
	if def.is_empty() or not THEME.has(def.t):
		return
	var head: Unit = grp.get("head", grp.lead)
	var by: Unit = head if head.alive else null
	if by == null:
		for o in grp.members:
			if o.alive:
				by = o
				break
	if by == null and grp.lead.alive:
		by = grp.lead
	if by == null:
		return
	var foes := units.filter(func(o): return o.alive and o.camp != by.camp)
	var allies := units.filter(func(o): return o.alive and o.camp == by.camp)
	if foes.is_empty():
		return
	var i := 1 if int(grp.shot) >= 3 else 0
	var tune: Dictionary = THEME[def.t]
	var plus := str(def.get("plus", ""))
	stats["inyeon_theme"] = int(stats.get("inyeon_theme", 0)) + 1
	_ai += 1
	_ph = "act"
	_who = by.key
	_one = turn_mul
	_long = turn_mul
	L("sk", "인연 『%s』 %s 『%s』 —— %s" % [grp.name, DB.INYEON_THEME_KIND.get(def.t, ""), def.n, DB.inyeon_theme_desc(def)],
		{"fx": "inyeon_theme", "a": by.key, "name": def.n, "inyeon": grp.name, "kind": def.t, "plus": plus, "cnt": int(grp.shot)})
	match def.t:
		"ignite":
			for t in foes:
				var s = _st_of(t, "burn")
				if s != null:      # 이미 타는 적 —— 남은 화상이 한꺼번에 터진다
					var amt: float = float(s.val) * maxf(1.0, float(s.dur)) * float(tune.pop[i])
					t.st.erase(s)
					_dot_hit(t, s, amt)
					stats.burn += amt
					L("st", "%s의 불길이 한꺼번에 터졌다 — 병력 %s 손실" % [nm(t), num(amt)], {"fx": "tick", "f": t.key, "st": "burn", "n": roundi(amt)})
				else:
					inflict(by, t, "burn", float(tune.burn[i]), int(tune.dur[i]))
		"spread":
			for t in _front_of(foes):
				inflict(by, t, "burn", float(tune.burn[i]), int(tune.dur[i]))
			for t in foes:
				var s = _st_of(t, "burn")
				if s != null and t.alive:
					for o in units:
						if o.alive and o != t and o.camp == t.camp and _same_line(o, t) and not has_st(o, "burn"):
							_spread_burn_to(t, s, o)
		"blaze":
			for t in foes:
				var s = _st_of(t, "burn")
				if s != null:
					s.val = roundf(float(s.val) * float(tune.amp[i]))
					s.dur = int(s.dur) + 1
					L("st", "%s의 불길이 거세진다" % nm(t), {"fx": "status", "f": t.key, "st": "burn"})
				else:
					inflict(by, t, "burn", float(tune.burn[i]), int(tune.dur[i]))
		"steam":
			for t in foes:
				inflict(by, t, "flood", _water_flood(by), int(tune.dur[i]))
				inflict(by, t, "burn", float(tune.burn[i]), int(tune.dur[i]))
				var s = _st_of(t, "burn")
				if s != null:
					s.val = roundf(float(s.val) * float(tune.amp))
		"flood":
			for t in foes:
				inflict(by, t, "flood", _water_flood(by), int(tune.dur[i]))
			for t in foes:
				if t.alive and t.troops > 0 and t.troops / t.max <= float(tune.rout[i]):
					stats.drowned += 1
					rout(t, "물에 휩쓸려 무너졌다")
		"tide":
			for t in _back_of(foes):
				inflict(by, t, "flood", _water_flood(by), int(tune.dur[i]))
				if t.alive:
					phys_hit(by, t, float(tune.mult[i]), true)
		"counter":
			for o in allies:
				o.buffs.append({"stat": "counter", "amt": float(tune.p[i]), "dur": roundi(int(tune.dur) * _long)})
				o.buffs.append({"stat": "counter_amp", "amt": float(tune.amp[i]), "dur": roundi(int(tune.dur) * _long)})
				L("sk", "%s 반격 태세를 갖춘다" % ga(nm(o)), {"fx": "buff", "f": o.key, "up": true})
		"chase":
			var n := clampi(int(grp.get("foes0", 0)) - foes.size(), 1, 2)      # 연쇄 동안 무너진 적만큼 (1~2번)
			for k in grp.members:
				for r in n:
					if not k.alive:
						break
					var tt := basic_target(k, units.filter(func(o): return o.camp != k.camp))
					if tt.is_empty() or not tt[0].alive:
						break
					stats.chases += 1
					L("sk", "%s 달아나는 적을 몰아친다" % ga(nm(k)), {"fx": "skill", "a": k.key, "name": "추격", "kind": "phys"})
					if is_caster(k.c): int_hit(k, tt[0], float(tune.mult[i]), 1)
					else: phys_hit(k, tt[0], float(tune.mult[i]), true)
		"momentum":
			for o in allies:
				o.kill_amp = maxf(o.kill_amp, float(tune.amp[i]))
				L("sk", "%s 기세가 오른다" % ga(nm(o)), {"fx": "buff", "f": o.key, "up": true})
		"exec":
			for t in foes:
				var cut: bool = int(t.shred.phys.t) > 0 if shield_enabled else t.cut.def > 0
				if t.alive and cut and t.troops > 0 and t.troops / t.max <= float(tune.at[i]):
					stats.execs += 1
					rout(t, "한 칼에 베였다")
			for t in _front_of(units.filter(func(o): return o.alive and o.camp != by.camp)):
				if shield_enabled: _shred(by, t, "phys", _shred_v(by) * _gv("shred_big", 1.5), int(_gv("shred_dur", 3)), def.n)
				else: _cut(by, t, "def", 0.15 * by.c.atk, def.n)
		"confuse":
			var ord := foes.duplicate()
			ord.sort_custom(func(x, y):
				if x.c.tier != y.c.tier:
					return x.c.tier > y.c.tier
				if x.troops != y.troops:
					return x.troops > y.troops
				return _idx[x] < _idx[y])
			for t in ord.slice(0, int(tune.n[i])):
				stats.confuses += 1
				inflict(by, t, "confuse", 1, int(DB.PSV.scheme.dur))
		"slow":
			for t in foes:
				inflict(by, t, "flood", 1, 1)
				t.gauge = maxf(0.0, t.gauge - float(tune.gauge[i]))
		"ambush":
			for t in foes:
				if _wind.has(t):
					_cut_wind(t, by)
				else:
					t.gauge = maxf(0.0, t.gauge - float(tune.gauge[i]))
		"plague":
			for t in foes:
				inflict(by, t, "plague", float(tune.val[i]), int(tune.dur[i]))
			var b := _yeon_best(foes)
			if b.alive:
				inflict(by, b, "seal", 1, 1)
		"cleanse":
			for o in allies:
				for r in int(tune.n[i]):
					if not cleanse(o): break
				heal_morale(o, float(tune.morale[i]), def.n, by)
		"duel":
			var b := _yeon_best(foes)
			phys_hit(by, b, float(tune.mult[i]), true)
			if b.alive:
				morale_hit(b, float(tune.morale[i]), def.n, 1, by)
	var left := units.filter(func(o): return o.alive and o.camp != by.camp)
	match plus:      # 덧붙는 효과 (data/inyeon.json theme.plus)
		"confuse":
			if not left.is_empty():
				var b := _yeon_best(left)
				stats.confuses += 1
				inflict(by, b, "confuse", 1, int(DB.PSV.scheme.dur))
		"slow":
			for t in left:
				inflict(by, t, "flood", 1, 1)
		"phalanx":
			for o in allies:
				_give_phalanx(o, 2, def.n)
	_one = 1.0
	_long = 1.0
