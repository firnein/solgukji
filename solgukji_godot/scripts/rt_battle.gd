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
const PERIOD_MUL := {3: 1.75, 4: 0.8, 5: 0.65, 6: 0.55, 7: 0.53, 8: 0.6}   # 등급별 턴 간격 배율 —— 같은 등급 31~38초 (11/1 측정 · 자동 감상 전투라 줄였다)
const BATTLE_SEC := 35.0                # 같은 등급 감상 전투의 보통 길이 (초) —— 카드 설명의 '전투 동안' 수치용 (11/3)


## 그 등급 전투 한 판의 턴 수 (보통 길이 기준)
static func turns_for(t: float) -> float:
	return BATTLE_SEC / (period_base * PERIOD_MUL[clampi(roundi(t), 3, 8)])


static var period_base := 1.9           # 예전 한 턴에 해당하는 시간 (초) —— 턴 끝 정산 간격 · 행동 간격의 기준. 11/1 2.9→1.9 (감상 전투 35초 안팎)
const TRACK_EVERY := 0.4      # 위치 기록 간격 (초)
const ARENA := Rect2(-460, -280, 920, 560)
const BODY := 28.0            # 부대 반지름 (px) —— 이보다 가까이 겹치지 않는다
static var ALLY_SEP := 2.7     # 아군 부대끼리 떨어지는 거리 (BODY 배) —— 11/3 2.0 → 2.7: 가운데 한 덩어리로 뭉쳐 누가 누군지 안 보였다
const CONTACT := 64.0         # 근접 공격이 닿는 중심 거리
const GAP := 240.0            # 양군 선봉 사이 · 열 간격 · 옆 간격 (War3D 와 같다)
const RS := 78.0
const CS := 118.0
const TAUNT_R := 160.0
const SPEED := {"창병": 62.0, "도적": 105.0, "기병": 95.0, "궁병": 55.0, "책사": 50.0, "유생": 50.0, "술사": 50.0, "모사": 50.0}
static var bow_range := 250.0      # 궁병 사거리 (점검 장면이 바꿔 볼 수 있게 static)
static var cast_range := 220.0     # 지략 계열(책략으로 치는 유닛) 사거리
static var melee_reach := 130.0    # 근접 공격이 닿는 중심 거리 —— 맞닿음보다 넓어 아군 너머 둘째 줄도 친다 (10/31: 64 면 근접이 막혀 유닛당 11초 놀았다)
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
	_setup(a_cards, a_form, a_morale, a_equip, b_cards, b_form, b_morale, b_equip, title, foe_name, inputs_, policy_)
	for i in units.size():
		_idx[units[i]] = i
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
	r["len"] = snappedf(_tm, 0.1)
	return r


## 행동 간격 —— 한 턴(period)에 한 번이 기준, 빠르면 조금 짧게 (±25%)
func _interval(u: Unit) -> float:
	var s := eff(u, "spd") / maxf(1.0, float(u.c.spd))
	return period / clampf(0.75 + 0.25 * s * (float(u.c.spd) / 75.0), 0.8, 1.25)


## 유닛을 만들 때 바로 진형 자리에 세운다 —— 전투 시작 효과(위진 · 철옹성 · 수공 …)도 거리로 판정하므로
func mk_unit(cid: String, slot_info: Dictionary, camp: String, morale: float, slot: int, item, syn: Dictionary) -> Unit:
	var u := super.mk_unit(cid, slot_info, camp, morale, slot, item, syn)
	var x: float = GAP / 2 + slot_info.row * RS
	u.pos = Vector2(-x if camp == "A" else x, (slot_info.col - 1) * CS)
	u.fwd = Vector2(1, 0) if camp == "A" else Vector2(-1, 0)
	return u


# ───────── 열 대신 거리 (10/31 사용자: 특기를 거리 기준으로) ─────────
const NEAR_R := 110.0          # 이 안이면 '같은 열 이웃'
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
static var ult_side_sec := 4.5
var _ult_t := -99.0
var _ult_side_t := {"A": -99.0, "B": -99.0}


## 11/4 사용자: 고유기 대기 시간은 장수마다 (DB.ult_of 가 고유기 세기로 정한 wait 초 —— 센 고유기일수록 늦게). 그 전에는 쓰지 않는다
func can_ult(u: Unit) -> bool:
	if u.ult != null and _tm < float(u.ult.get("wait", 14.0)):
		return false
	if _wind.size() > 0 or _tm - _ult_t < ult_gap or _tm - _ult_side_t[u.camp] < ult_side_sec:
		return false
	return super.can_ult(u)


func _interrupt_ult(u: Unit) -> void:
	if _wind.has(u):
		return
	var fast := false
	var wait := WIND + (1.0 if _kv(_foe(u.camp), "wind_slow") else 0.0)      # 점복 관로 —— 적 고유기 기 모으기 +1초
	_wind[u] = _tm + wait
	_ult_t = _tm + wait
	_ult_side_t[u.camp] = _tm + wait
	u.gauge = 0.0                 # 다시 누를 수 없게 (터지거나 끊길 때 정리)
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
		best = maxi(best, us.filter(func(o): return o.pos.distance_to(c.pos) <= AREA).size())
	return best


func _reach(u: Unit) -> float:
	var hill := HILL.range if _in(u.pos, "hill") else 1.0
	if u.c.tag == "궁병":
		return bow_range * hill
	if u.c.int > u.c.atk:
		return cast_range * hill
	return melee_reach


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
	return u.c.tag == "궁병" or u.c.int > u.c.atk


func _foes_of(u: Unit) -> Array:
	return units.filter(func(o): return o.alive and o.camp != u.camp)


func _ready_to_hit(u: Unit) -> bool:
	if has_st(u, "confuse"):
		return true            # 혼란은 제자리에서 차례를 날리거나 제 편을 친다 (Battle.act)
	return u.tgt != null and u.tgt.alive and u.pos.distance_to(u.tgt.pos) <= _reach(u) + 2.0


# ───────── 움직임 ─────────

func _move() -> void:
	for u in units:
		if not u.alive:
			continue
		u.retgt -= TICK
		var foes := _foes_of(u)
		if foes.is_empty():
			continue
		# 맞닿은 적이 있으면 묶인다 —— 가장 가까운 맞닿은 적을 상대 (원거리도 붙으면 맞받아 싸운다)
		var pin: Unit = null
		var pd := CONTACT + 4.0
		for o in foes:
			var d := u.pos.distance_to(o.pos)
			if d <= pd:
				pd = d
				pin = o
		# 기병 · 도적은 맞닿아도 묶이지 않고 노리던 후열로 파고든다
		var slip: bool = (u.c.tag == "기병" or u.c.tag == "도적") and u.tgt != null and u.tgt.alive and pin != u.tgt
		if slip:
			pin = null
		if pin != null and (u.tgt == null or not u.tgt.alive or u.pos.distance_to(u.tgt.pos) > _reach(u)):
			u.tgt = pin
		elif u.tgt == null or not u.tgt.alive or u.retgt <= 0.0:
			u.tgt = _choose(u, foes)
			u.retgt = 0.5
		if has_st(u, "confuse"):
			continue
		var t := u.tgt
		var to := t.pos - u.pos
		var dist := to.length()
		var want := _reach(u) - 4.0
		if pin == null and dist > want:
			var dir := to / maxf(dist, 0.001)
			# 기병은 적 무리를 돌아 옆 · 뒤로 파고든다 (멀 때만)
			if u.c.tag == "기병" and dist > 170.0:
				var side := signf(u.pos.y - _centroid(foes).y)
				if side == 0.0:
					side = 1.0 if u.slot % 2 == 0 else -1.0
				dir = (dir + Vector2(-dir.y, dir.x) * side * 0.55 * signf(dir.x if dir.x != 0 else 1.0)).normalized()
			# 앞을 아군이 막고 있으면 옆으로 돌아간다
			for al in units:
				if al == u or not al.alive or al.camp != u.camp:
					continue
				var v := al.pos - u.pos
				var ahead := v.dot(dir)
				var lat := v.cross(dir)
				if ahead > 0.0 and ahead < 75.0 and absf(lat) < 50.0:
					var perp := Vector2(-dir.y, dir.x)
					dir = (dir + perp * (-signf(lat) if lat != 0.0 else 1.0) * 0.9).normalized()
					break
			var sp: float = SPEED.get(u.c.tag, 55.0) * clampf(eff(u, "spd") / maxf(1.0, float(u.c.spd)), 0.5, 1.5) * _terrain_move(u)
			var step := minf(sp * TICK, dist - want)
			u.pos += dir * step
			u.ran += step
		_turn_to(u, to)
	_separate()


func _choose(u: Unit, foes: Array) -> Unit:
	var best: Unit = null
	var bs := INF
	for o in foes:
		var d := u.pos.distance_to(o.pos)
		var w := 1.0
		# 기병 · 도적은 원거리 · 지략 부대를 노린다 (멀리 돌아가더라도)
		if (u.c.tag == "기병" or u.c.tag == "도적") and _ranged(o):
			w = 0.6 if u.c.tag == "도적" else 0.75
		if u.tgt == o:
			w *= 0.8            # 노리던 적을 쉽게 바꾸지 않는다
		# 11/3 창병 도발 —— 가까이 온 근접 적은 창병부터 친다 (도적은 흘려 지나간다)
		if Battle.tag_roles and o.c.tag == "창병" and not _ranged(u) and u.c.tag != "도적" and d < TAUNT_R:
			w *= 0.5
		if not _ranged(u):
			# 근접은 아군이 이미 몰려 싸우는 적보다 빈 적을 (줄 서서 놀지 않게)
			var crowd := 0
			for al in units:
				if al != u and al.alive and al.camp == u.camp and not _ranged(al) and al.pos.distance_to(o.pos) <= CONTACT + 8.0:
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


func _turn_to(u: Unit, v: Vector2) -> void:
	if v.length() < 0.001:
		return
	u.fwd = Vector2.from_angle(rotate_toward(u.fwd.angle(), v.angle(), TURN_RATE * TICK))


## 겹치지 않게 —— 가까운 두 부대를 반씩 민다. 맞닿은 적끼리는 CONTACT 보다 가까워지지 않는다
func _separate() -> void:
	for i in units.size():
		var a := units[i]
		if not a.alive:
			continue
		for j in range(i + 1, units.size()):
			var b := units[j]
			if not b.alive:
				continue
			var lim := BODY * ALLY_SEP if a.camp == b.camp else CONTACT - 6.0
			var d := a.pos - b.pos
			var l := d.length()
			if l < lim:
				var n := d / l if l > 0.01 else Vector2(0, 1 if i % 2 == 0 else -1)
				var push := n * (lim - l) * 0.5
				a.pos += push
				b.pos -= push
		a.pos = a.pos.clamp(ARENA.position, ARENA.end)


func _record() -> void:
	_next_track = _tm + TRACK_EVERY
	var fr := []
	for u in units:
		var ti := -1
		if u.tgt != null and u.tgt.alive:
			ti = _idx[u.tgt]
		var touch := 1 if ti >= 0 and u.pos.distance_to(u.tgt.pos) <= CONTACT + 4.0 else 0
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
	var near := live.filter(func(o): return me.pos.distance_to(o.pos) <= reach)
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
			var s := live.filter(func(o): return o.pos.distance_to(main.pos) <= AREA)
			s.sort_custom(func(a, b): return a.pos.distance_to(main.pos) < b.pos.distance_to(main.pos))
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
				var g := live.filter(func(o): return o.pos.distance_to(c.pos) <= AREA)
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
		var s := live.filter(func(o):
			var v: Vector2 = o.pos - me.pos
			var along := v.dot(dir)
			return along >= -10.0 and along <= ln and absf(v.cross(dir)) <= LINE_W)
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
	var back: bool = (u.c.tag == "궁병" and (u.caps.has("궁병") or DB.aff_of(u.c.tag, u.line, u.side) == "pref")) 		or u.c.tag == "도적" or u.c.int > u.c.atk
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
	var far := v.length() > melee_reach + 6.0
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
	if not _in_ult:
		m *= int_mul * float(int_tier.get(int(a.c.tier), 1.0))
		if a.pos.distance_to(d.pos) > melee_reach + 6.0:
			m *= far_mul
	super.int_hit(a, d, m, spread)
	if _in_ult and _wind.has(d) and d.camp != a.camp:
		_cut_wind(d, a)
