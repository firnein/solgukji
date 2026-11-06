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
	return BATTLE_SEC / (period_base * PERIOD_MUL[clampi(roundi(t), 3, 8)])


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
static var cav_charge := 1.6       # 기병 돌격 —— CHARGE_RUN 넘게 달려와 친 첫 물리 공격 피해 배율
const CHARGE_RUN := 120.0
static var near_mul := 1.5         # 맞닿아 친 물리 피해 배율 (삼국지11 —— 근접이 세다)
static var far_mul := 0.85          # 떨어진 곳(활 · 책략)에서 친 피해 배율 —— 근접은 맞닿아야만 쳐서 덜 치므로 맞춘다
const AREA := 95.0            # 둘레 범위 (front3 · denseLine)
const ALL_R := 320.0          # '적 전체' 기술이 닿는 거리 (고유기는 전장 전체)
const LINE_W := 45.0          # 줄 범위의 반폭
const SIDE := 0.15            # 옆에서 친 피해 +
const REAR := 0.30            # 뒤에서 친 피해 +
const TURN_RATE := 2.5        # 부대가 도는 속도 (라디안/초)

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


## 결정적 순서로 유닛을 놓고 시간을 흘린다
func run(a_cards: Array, a_form: String, a_morale: float, a_equip, b_cards: Array, b_form: String,
		b_morale: float, b_equip, title := "", foe_name := "", inputs_ := [], policy_ := {}) -> Dictionary:
	_make_terrain(rng.seed)
	lay = 1.0
	if compact_enabled:
		var tr := 0.0
		for k in a_cards + b_cards:
			if k != null and DB.C.has(str(k)):
				tr += float(DB.C[str(k)].tr)
		lay = clampf(sqrt(tr / LAY_FULL), LAY_MIN, 1.0)
	_setup(a_cards, a_form, a_morale, a_equip, b_cards, b_form, b_morale, b_equip, title, foe_name, inputs_, policy_)
	for i in units.size():
		_idx[units[i]] = i
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
	_record()
	while _tm < cap_t and winner == "":
		_tm += TICK
		_move()
		_fire_winds()
		for u in units:
			if not u.alive:
				continue
			if u.gauge >= 100.0 and u.ult_ready_t < 0.0:
				u.ult_ready_t = _tm
			u.atb = minf(1.0 if _ranged(u) else melee_bank, u.atb + TICK / _interval(u))
			if u.atb >= 1.0 and not _ready_to_hit(u):
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
				_act_one(u)
				if live_count("A") == 0 or live_count("B") == 0:
					break
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
	_record()
	var r := _result(winner, turn)
	r["track"] = track
	r["terrain"] = terrain
	r["rt"] = true
	r["lay"] = lay
	r["arena"] = [roundi(arena.position.x), roundi(arena.position.y), roundi(arena.size.x), roundi(arena.size.y)]
	r["len"] = snappedf(_tm, 0.1)
	return r


## 행동 간격 —— 한 턴(period)에 한 번이 기준, 빠르면 조금 짧게 (±25%)
func _interval(u: Unit) -> float:
	var s := eff(u, "spd") / maxf(1.0, float(u.c.spd))
	return period / clampf(0.75 + 0.25 * s * (float(u.c.spd) / 75.0), 0.8, 1.25)


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
const WIND := 2.5
const WIND_FAST := 0.7
const CUT_GAUGE := 30.0        # 끊긴 장수는 게이지가 이만큼 남는다 (횟수는 그대로)
var _wind := {}                # 유닛 -> 터질 시각
## 11/2 사용자: 후반에 고유기가 연달아 터진다 → 초 단위 간격. 어느 진영이든 직전 고유기에서 ULT_GAP 초,
## 같은 진영은 ULT_SIDE_SEC 초가 지나야 다음 고유기 (맞받아치기로 바로 받아치던 것도 없앴다)
static var ult_gap := 2.5
static var ult_side_sec := 3.0      # 11/6 밸런스: 같은 진영 고유기 간격 4.5 → 3.0
var _ult_t := -99.0
var _ult_side_t := {"A": -99.0, "B": -99.0}


## 11/4 사용자: 고유기 대기 시간은 장수마다 (DB.ult_of 가 고유기 세기로 정한 wait 초 —— 센 고유기일수록 늦게). 그 전에는 쓰지 않는다
func can_ult(u: Unit) -> bool:
	var full: bool = u.ult != null and u.charges > 0 and u.gauge >= 100.0 and u.alive      # 점검용 —— 찼는데 막힌 이유를 센다 (11/6 #14)
	if u.ult != null and _tm < float(u.ult.get("wait", 14.0)) * _tw(u, "wait"):      # 11/7 기질 배율 (맹장 0.9 · 분노 0.85 · 지략 1.1)
		if full: stats["ult_blk_wait"] = stats.get("ult_blk_wait", 0) + 1
		return false
	# 11/6 #14: 기 모으기는 진영마다 하나씩 (예전엔 어느 쪽이든 하나만 —— 처리량이 반이었다). 전체 간격 ult_gap 은 그대로
	for w in _wind:
		if w.camp == u.camp:
			if full: stats["ult_blk_wind"] = stats.get("ult_blk_wind", 0) + 1
			return false
	if _tm - _ult_t < ult_gap or _tm - _ult_side_t[u.camp] < ult_side_sec:
		if full: stats["ult_blk_gap"] = stats.get("ult_blk_gap", 0) + 1
		return false
	var ok := super.can_ult(u)
	if full and not ok: stats["ult_blk_base"] = stats.get("ult_blk_base", 0) + 1
	return ok


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
	var reach: float = (cast_range if is_caster(u.c) else melee_gap + 90.0) + 40.0      # 발자국 틈 기준
	var n := 0
	for f in foes:
		if f.alive and _gap(u, f) <= reach:
			n += 1
	return n


func _interrupt_ult(u: Unit) -> void:
	if _wind.has(u):
		return
	var fast := false
	var wait := WIND + (1.0 if _kv(_foe(u.camp), "wind_slow") else 0.0)      # 점복 관로 —— 적 고유기 기 모으기 +1초
	_wind[u] = _tm + wait
	_ult_t = _tm                  # 11/6 #14: 간격(ult_gap · ult_side_sec)은 기를 모으기 시작한 때부터 센다 (예전엔 터진 뒤부터 —— 기 모으기 2.5초가 간격에 더해져 한 판에 몇 번 못 썼다)
	_ult_side_t[u.camp] = _tm
	u.gauge = 0.0                 # 다시 누를 수 없게 (터지거나 끊길 때 정리)
	u.ult_ready_t = -1.0
	_ult_last[u.camp] = act_n
	# 맞을 곳 미리 보기 —— 지금 자리 기준으로 고유기 대상들을 원으로
	var foes := units.filter(func(o): return o.camp != u.camp)
	var allies := units.filter(func(o): return o.camp == u.camp)
	var warn := []
	_in_ult = true
	for comp in u.ult.eff:
		if comp.t == "ally":
			continue
		for t in resolve_targets(comp.tgt, foes, u, allies):
			if t.alive and not warn.any(func(w): return w.k == t.key):
				warn.append({"k": t.key, "x": roundi(t.pos.x), "y": roundi(t.pos.y), "r": 60})
	_in_ult = false
	_ai += 1
	_ph = "act"
	_who = u.key
	L("sk", "%s 『%s』 기를 모은다%s" % [ga(nm(u)), u.ult.name, ""],
		{"fx": "ult_warn", "a": u.key, "name": u.ult.name, "wait": wait, "warn": warn, "fast": fast})
	var zh := _kv(_foe(u.camp), "ult_cut")      # 매복 주환 —— 적 고유기 기 모으기를 한 번 끊고 게이지를 비운다
	if zh and int(_kiin_used.get("ult_cut:" + zh.camp, 0)) < 2:      # 두 번까지
		_kiin_used["ult_cut:" + zh.camp] = int(_kiin_used.get("ult_cut:" + zh.camp, 0)) + 1
		_cut_wind(u, zh)
		u.gauge = 0.0


## 기 모으기가 끝난 고유기를 터뜨린다 (유닛 순서대로 —— 같은 시각이면 결정적으로)
func _fire_winds() -> void:
	for u in units:
		if not _wind.has(u) or _wind[u] > _tm + 0.001:
			continue
		_wind.erase(u)
		if not u.alive or has_st(u, "confuse"):
			u.gauge = CUT_GAUGE
			continue
		super._interrupt_ult(u)


## 기 모으던 장수가 적 고유기에 맞았다 —— 끊긴다
func _cut_wind(d: Unit, a: Unit) -> void:
	_wind.erase(d)
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
		return bow_range * hill
	if is_caster(u.c):
		return cast_range * hill
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
	return m


## 화상 —— 숲에서는 크게 번진다
func _burn_mul(a: Unit, d: Unit) -> float:
	return super._burn_mul(a, d) * (FOREST.burn if _in(d.pos, "forest") else 1.0)


func _ranged(u: Unit) -> bool:
	return u.c.tag == "궁병" or is_caster(u.c)


func _foes_of(u: Unit) -> Array:
	return units.filter(func(o): return o.alive and o.camp != u.camp)


func _ready_to_hit(u: Unit) -> bool:
	if has_st(u, "confuse"):
		return true            # 혼란은 제자리에서 차례를 날리거나 제 편을 친다 (Battle.act)
	return u.tgt != null and u.tgt.alive and _gap(u, u.tgt) <= _reach(u) + 2.0


# ───────── 발자국 기하 ─────────

static func _rt(u: Unit) -> Vector2:
	return Vector2(-u.fwd.y, u.fwd.x)


## 발자국이 dir 방향으로 뻗은 반폭
static func _extent(u: Unit, dir: Vector2) -> float:
	return u.hd * absf(dir.dot(u.fwd)) + u.hw * absf(dir.dot(Vector2(-u.fwd.y, u.fwd.x)))


## 두 발자국 가장자리 사이 틈 (겹치면 음수 —— 가장 얕게 파고든 깊이). 네 축(두 부대의 앞뒤 · 좌우)으로 재는 분리축 판정
func _gap(a: Unit, b: Unit) -> float:
	var d := b.pos - a.pos
	var best := -INF
	for ax in [a.fwd, _rt(a), b.fwd, _rt(b)]:
		var sep := absf(d.dot(ax)) - _extent(a, ax) - _extent(b, ax)
		if sep > best:
			best = sep
	return best


func _speed(u: Unit) -> float:
	return SPEED.get(u.c.tag, 55.0) * clampf(eff(u, "spd") / maxf(1.0, float(u.c.spd)), 0.5, 1.5) * _terrain_move(u)


# ───────── 움직임 ─────────

func _move() -> void:
	for u in units:
		if not u.alive:
			continue
		u.retgt -= TICK
		var foes := _foes_of(u)
		if foes.is_empty():
			u.vel = Vector2.ZERO
			continue
		# 맞닿은 적이 있으면 묶인다 —— 발자국이 맞닿은(틈 TOUCH 안) 적 가운데 가장 가까운 적을 상대 (원거리도 붙으면 맞받아 싸운다)
		var pin: Unit = null
		var pd := TOUCH + 2.0
		for o in foes:
			var g := _gap(u, o)
			if g <= pd:
				pd = g
				pin = o
		# 기병 · 도적은 맞닿아도 묶이지 않고 노리던 후열로 파고든다
		var slip: bool = (u.c.tag == "기병" or u.c.tag == "도적") and u.tgt != null and u.tgt.alive and pin != u.tgt
		if slip:
			pin = null
		if pin != null and (u.tgt == null or not u.tgt.alive or _gap(u, u.tgt) > _reach(u)):
			u.tgt = pin
		elif u.tgt == null or not u.tgt.alive or u.retgt <= 0.0:
			u.tgt = _choose(u, foes)
			u.retgt = 0.5
		var sp := _speed(u)
		if has_st(u, "confuse"):
			u.vel = u.vel.move_toward(Vector2.ZERO, sp / DEC_T * TICK)
			u.pos += u.vel * TICK
			continue
		var t := u.tgt
		var to := t.pos - u.pos
		var dist := to.length()
		var gap := _gap(u, t)
		var want := TOUCH if not _ranged(u) else _reach(u) - 4.0
		var desired := Vector2.ZERO
		if pin == null and gap > want:
			var dir := to / maxf(dist, 0.001)
			# 기병은 적 무리를 돌아 옆 · 뒤로 파고든다 (멀 때만)
			if u.c.tag == "기병" and gap > 150.0:
				var side := signf(u.pos.y - _centroid(foes).y)
				if side == 0.0:
					side = 1.0 if u.slot % 2 == 0 else -1.0
				dir = (dir + Vector2(-dir.y, dir.x) * side * 0.55 * signf(dir.x if dir.x != 0 else 1.0)).normalized()
			# 11/4 사용자: 도적은 측면으로 크게 돌아 적 후열에 붙는다 —— 적 무리 옆 바깥 길목(적 폭 + 여유)을 지나 노리는 적 뒤로
			if u.c.tag == "도적" and gap > 70.0:
				var way = _flank_way(u, t, foes)
				if way != null:
					var wv: Vector2 = way - u.pos
					if wv.length() > 20.0:
						dir = wv.normalized()
			dir = _steer(u, dir, t)
			if dir != Vector2.ZERO:
				desired = dir * minf(sp, (gap - want) / TICK)      # 노리는 적 앞에서 멈춘다 (파고들지 않게)
		else:
			u.block_t = 0.0
		# 속도 —— 가속 · 감속 시간을 두어 미끄러지거나 순간이동하지 않는다
		var acc := sp / (ACC_T if desired.length() > u.vel.length() else DEC_T)
		u.vel = u.vel.move_toward(desired, acc * TICK)
		var step := u.vel * TICK
		u.pos += step
		if desired != Vector2.ZERO:
			u.ran += step.length()
		_turn_to(u, to)
	_depth_update()
	_solve()


## 앞이 막혔으면 비켜 간다 —— 진행 방향 LOOK 안에 다른 부대(아군 · 노리지 않는 적)가 있으면 그 옆으로. 양쪽 가운데 더 트인 쪽으로,
## 오래 막힐수록 더 옆으로 (예비대가 전선 뒤에서 기다리지 않고 측면으로 흘러 나간다). 원거리는 3초까지는 제자리에서 기다린다
func _steer(u: Unit, dir: Vector2, t: Unit) -> Vector2:
	var blocker := _blocker(u, dir, t, LOOK)
	if blocker == null:
		u.block_t = 0.0
		return dir
	u.block_t += TICK
	if rigid_probe:
		stats["block_t"] = stats.get("block_t", 0.0) + TICK
	if _ranged(u) and u.block_t < 3.0:
		return Vector2.ZERO
	var perp := Vector2(-dir.y, dir.x)
	var free_p := _free_run(u, perp, t)
	var free_m := _free_run(u, -perp, t)
	var side := 0.0
	if absf(free_p - free_m) > 8.0:
		side = 1.0 if free_p > free_m else -1.0
	else:
		var lat := (t.pos - u.pos).dot(perp)
		side = signf(lat) if absf(lat) > 4.0 else (1.0 if u.slot % 2 == 0 else -1.0)
	if maxf(free_p, free_m) < 6.0:
		return Vector2.ZERO        # 양옆도 막혔다 —— 기다린다 (앞이 열리면 간다)
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
		var eo := _extent(o, dir)
		if ahead - eu - eo > look:
			continue
		if absf(v.dot(perp)) >= pu + _extent(o, perp) + 4.0:
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
	var best: Unit = null
	var bs := INF
	var lane: bool = not _ranged(u) and u.c.tag != "기병" and u.c.tag != "도적"
	for o in foes:
		var d := maxf(0.0, _gap(u, o))
		if lane:      # 앞 열 우선 —— 진형 폭만큼 전선이 넓게 선다 (옆 거리는 무겁게)
			d = maxf(0.0, Vector2(o.pos.x - u.pos.x, (o.pos.y - u.pos.y) * LANE_W).length() - u.hd - o.hd)
		var w := 1.0
		# 기병 · 도적은 원거리 · 지략 부대를 노린다 (멀리 돌아가더라도)
		if (u.c.tag == "기병" or u.c.tag == "도적") and _ranged(o):
			w = 0.6 if u.c.tag == "도적" else 0.75
		if u.tgt == o:
			w *= 0.8            # 노리던 적을 쉽게 바꾸지 않는다
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
				if al != u and al.alive and al.camp == u.camp and not _ranged(al) and _gap(al, o) <= TOUCH + 4.0:
					crowd += 1
			w *= 1.0 + 0.35 * crowd
		if d * w < bs:
			bs = d * w
			best = o
	return best


func _centroid(us: Array) -> Vector2:
	var c := Vector2.ZERO
	for o in us:
		c += o.pos
	return c / maxf(1, us.size())


## 돌기 —— TURN_RATE 까지. 돌아서 옆 부대를 더 파고들게 되면 반 · 반의 반만 돌고, 그래도 파고들면 이번 틱은 멈춘다 (대열이 이웃을 쓸고 지나가지 않게)
func _turn_to(u: Unit, v: Vector2) -> void:
	if v.length() < 0.001:
		return
	var a0 := u.fwd.angle()
	var a1 := rotate_toward(a0, v.angle(), TURN_RATE * TICK)
	if absf(a1 - a0) < 0.0001:
		return
	var near := []
	var reach := u.hw + u.hd + 4.0
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
	var live: Array = units.filter(func(o): return o.alive)
	var pre := {}
	for u in live:
		pre[u] = u.pos
	for it in SOLVE_ITERS:
		for i in live.size():
			var a: Unit = live[i]
			for j in range(i + 1, live.size()):
				var b: Unit = live[j]
				var want: float = ALLY_GAP if a.camp == b.camp else -FOE_MIX
				var d: Vector2 = b.pos - a.pos
				if d.length() > a.hw + a.hd + b.hw + b.hd + want:
					continue
				var best := -INF
				var bn := Vector2.ZERO
				for ax in [a.fwd, _rt(a), b.fwd, _rt(b)]:
					var proj := d.dot(ax)
					var sep := absf(proj) - _extent(a, ax) - _extent(b, ax)
					if sep > best:
						best = sep
						bn = ax if proj >= 0.0 else -ax
				if best >= want:
					continue
				var push := want - best
				var ma := a.troops + 1.0
				var mb := b.troops + 1.0
				a.pos -= bn * push * (mb / (ma + mb))
				b.pos += bn * push * (ma / (ma + mb))
		for u in live:
			_clamp_arena(u)
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
	var live := foes.filter(func(u): return u.alive)
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
			_mark(me, {"k": "circle", "x": roundi(main.pos.x), "y": roundi(main.pos.y), "r": AREA})
			return s.slice(0, 3)
		"all":
			if _in_ult:
				_mark(me, {"k": "circle", "x": roundi(_centroid(live).x), "y": roundi(_centroid(live).y), "r": 300})
				return live
			return live.filter(func(o): return me.pos.distance_to(o.pos) <= ALL_R)
		"denseLine":
			var best: Array = [main]
			var bc: Unit = main
			for c in near:
				var g := live.filter(func(o): return o == c or _gap(o, c) <= AREA_GAP)
				if g.size() > best.size():
					best = g
					bc = c
			_mark(me, {"k": "circle", "x": roundi(bc.pos.x), "y": roundi(bc.pos.y), "r": AREA})
			return best
	# 11/2 열 —— 설명대로 적 진영의 앞쪽(선봉 · 전군) / 뒤쪽(후군) 절반, 최대 3부대 (예전엔 나에서 대상으로 뻗은 띠였다)
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
		_mark(me, {"k": "line", "x": roundi(me.pos.x), "y": roundi(me.pos.y), "x2": roundi(tip.x), "y2": roundi(tip.y), "w": LINE_W})
		return s if not s.is_empty() else [main]
	return [main]


## 기본 공격 —— 예전 규칙(궁병 · 도적 · 책략 유닛은 후열을 노린다)을 사거리 안에서: 닿는 적 가운데 적진 가장 깊은 적
## 범위 기록 —— 방금 펼친 기술 · 고유기 사건에 덮은 곳을 적는다 (화면이 땅에 미리 그린다)
func _mark(me: Unit, shape: Dictionary) -> void:
	for i in range(ev.size() - 1, maxi(-1, ev.size() - 40), -1):
		var e: Dictionary = ev[i]
		if (e.get("fx") == "skill" or e.get("fx") == "ult") and e.get("a") == me.key:
			if not e.has("area"):
				e["area"] = []
			e.area.append(shape)
			return


func basic_target(u: Unit, foes: Array) -> Array:
	var back: bool = (u.c.tag == "궁병" and (u.caps.has("궁병") or DB.aff_of(u.c.tag, u.line, u.side) == "pref")) 		or u.c.tag == "도적" or is_caster(u.c)
	return resolve_targets("back1" if back else "front1", foes, u, [])


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
	if not _in_ult:
		m *= far_mul if far else near_mul
		if a.c.tag == "기병" and a.ran >= CHARGE_RUN and not far and not a.countering:
			m *= cav_charge
			stats["charges"] = stats.get("charges", 0) + 1
	if not a.countering:
		a.ran = 0.0
	var n0 := ev.size()
	super.phys_hit(a, d, m, no_counter or far, pierce)
	if _in_ult and _wind.has(d) and d.camp != a.camp:
		_cut_wind(d, a)
	if dir != "":
		# 이 타격의 사건에 방향을 적는다 —— 화면이 '측면!' · '후방!' 을 띄운다
		for i in range(n0, ev.size()):
			if ev[i].get("fx") == "phys" and ev[i].get("a") == a.key and ev[i].get("f") == d.key:
				ev[i]["dir"] = dir
				break


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
