class_name Squad
extends RefCounted
## 전장의 한 부대 —— 장수 카드 한 장이 병사 인형 무리 하나가 된다.
## 판정은 Battle 이 이미 끝냈다. 부대는 받은 결과를 몸으로 보여줄 뿐이다.
##
## 움직임 원칙 (빙글빙글 돌지 않도록)
##  · 상대를 정하는 순간 접근 방향(axis)을 한 번 정하고 고정한다. 매 프레임 다시 재지 않는다.
##    두 부대가 서로를 노리면 같은 축을 나눠 쓰므로 한 줄에서 맞부딪친다.
##  · 대열 방향은 초당 TURN 라디안까지만 돈다.
##  · 병사는 대열 자리를 향해 각자 제 걸음으로 걷고, 걷는 쪽 또는 적 쪽을 본다 (병사마다 따로).
##  · 맞닿은 앞 두 줄은 병사마다 다른 박자로 찌르고 휘두르며, 맞으면 움찔 물러선다.
##
## 바글바글하게 (밀도)
##  · 부대당 병사를 토탈워 쪽으로 늘리고, 어깨가 닿는 간격으로 세운다.
##  · 줄마다 반 칸씩 엇갈리고, 자리마다 크게 어긋나며, 서 있어도 조금씩 꼼지락거린다.
##  · 맞붙으면 앞 네 줄은 대열 자리를 버리고 마주 선 적 병사(duel)를 에워싸며 붙고, 뒷줄은 앞으로 밀고 든다.
##
## 흐트러짐 (loose) —— 실시간 전투처럼
##  · 싸우는 동안 병사마다 대열 자리에서 벗어난 만큼(free)을 기억한다. 싸움이 끝나도 바로 칸으로 돌아가지 않고
##    흐트러진 무리 그대로 다음 상대에게 몰려가며, 몇 초에 걸쳐 천천히 대열을 되찾는다.

## 병종 → 연출 계열
const CLS := {"창병": "melee", "도적": "melee", "기병": "cav", "궁병": "ranged",
	"책사": "caster", "유생": "caster", "술사": "caster", "모사": "caster"}
## 등급별 병사 인형 수 —— 기병은 절반, 지략 계열은 호위대까지 쳐서 절반 남짓
const COUNT := {1: 34, 2: 38, 3: 43, 4: 57, 5: 80, 6: 109, 7: 137, 8: 172}     # 11/4 사용자: 높은 장수일수록 큰 군세 —— DENSITY 3.5 를 곱해 고급 150 · 희귀 200 · 전설 280 · 초월 380 · 불멸 480 · 신화 600명 (11/3 은 252~525 로 차이가 2배뿐)
## 11/4 사용자: 압도적인 스케일 —— 병사를 작게 · 간격도 그만큼 (넓은 땅 위의 큰 군세로 보이게)
const SCALE_BODY := 0.72
const SCALE_SP := 1.0      # 11/4 사용자: 간격만 넓히면 밀려 번진다 —— 간격은 보통으로, 대신 대열 칸(RS · CS)을 키웠다
const MAX_W := 220.0     # 11/4 저녁 북적임: 옆 부대와 맞닿게 (205 → 220 = CS)     # 부대 폭 상한 (px) —— 옆 부대 간격(CS 220) 안
const FEW_TROOPS := 12000.0     # 이 병력 아래 부대는 병사를 덜 그린다 (11/5)
const PER_PV := 5.5      # PV 1 당 병사 수 (11/4 3.9 → 저녁 5.5: 북적이게 —— 전장이 성글었다)
## 등급별 병사 몸집 · 간격 배율 —— 초월 위는 정예라 크고 넓게 선다
const TIER_SIZE := {6: 1.1, 7: 1.2, 8: 1.32}
## 장수 인형 크기
const GEN_SIZE := {6: 1.45, 7: 1.6, 8: 1.85}
static var count_scale := 1.0   # 품질 설정 —— 모바일은 병사 수를 줄인다 (Settings)
## 11/3 GPU 병사 (War3D._gpu) —— 살아 있는 병사는 셰이더가 대열 자리에 그리므로 병사마다 걷기 계산을 하지 않는다.
## 병력이 줄면 뒷자리(slot 큰 쪽)부터 지우고(대열이 뒤에서 줄어든다), 쓰러지는 병사는 앞줄 자리에 놓아 CPU 가 넘어뜨린다
static var gpu := false
const CPU_SHARE := 0.33         # GPU 가 아닐 때(점묘 · 타입2) 병사 수 배율 —— 예전 수(약 1,700명)로
static var DENSITY := 3.5            # 11/3 GPU 병사 —— 후반 대전 약 5,000명 (예전 1.15 ≈ 1,700명). 2D 전장(점묘 · 타입2)은 CPU 라 CPU_SHARE 만큼만 —— 11/3 사용자: 1,000~2,000명이 바글바글한 '병사의 바다' 로 (11/2 의 1.1 · 넓은 간격에서 수를 늘리고 간격을 좁힘)
## 이동 속도 (px/초) —— 기병은 돌격 때 더 빨라진다
const SPEED := {"창병": 62.0, "도적": 80.0, "기병": 95.0, "궁병": 55.0,
	"책사": 50.0, "유생": 50.0, "술사": 52.0, "모사": 52.0}
const TURN := 1.4           # 대열이 도는 속도 (라디안/초)
const SOLDIER_TURN := 7.0   # 병사가 고개를 돌리는 속도
const CONTACT_GAP := 2.0    # 맞닿은 두 대열 앞줄 사이 (px)
const DUEL_RANKS := 2       # 맞붙으면 일대일로 흩어지는 앞줄 수 (10/30 4 → 2: 대열이 덩어리로 남게)
const DUEL_DIST := 7.0      # 일대일로 붙은 두 병사 사이 (px)
const LOOSE_IN := 0.25      # 맞붙으면 초당 이만큼 흐트러진다 (10/30 1.2 → 0.6, 10/31 0.25 —— 대열이 덩어리로 남게)
const LOOSE_OUT := 0.22     # 떨어지면 초당 이만큼 대열을 되찾는다 (약 4~5초)
const ATTACK_TIME := 0.38   # 한 번 찌르거나 휘두르는 시간
const ARENA := Rect2(-460, -280, 920, 560)   # 전장 —— 부대 중심이 이 밖으로 나가지 않는다 (진형 끝 x 276 · 등장 436 · y 118)
const FLEE_OUT := 110.0     # 패주하는 부대는 전장 밖으로 이만큼까지만 달아난다


class Soldier:
	var pos: Vector2
	var slot := 0             # 대열 안 자리 (재정렬하면 바뀐다)
	var slot_old := -1        # GPU —— 걸어 나오기 전 자리 (-1 이면 없음)
	var move_t := -99.0       # GPU —— 자리를 옮기기 시작한 시각
	var gseed := 0.0          # GPU —— 병사 씨앗
	var jit: Vector2          # 자리마다 조금씩 어긋나게
	var alive := true
	var die_t := -1.0         # 쓰러지는 시각
	var fall := 1.0           # 쓰러지는 방향
	var phase := 0.0
	var walk := 0.0
	var spawn_t := -1.0
	var scatter := Vector2.ZERO
	var yaw := 0.0            # 바라보는 각 (2D 평면)
	var pace := 1.0           # 걸음 빠르기 —— 병사마다 조금씩 다르다
	var next_atk := 0.0       # 다음 공격 시각
	var atk_t0 := -9.0        # 지금 공격을 시작한 시각
	var hit_t := -9.0         # 마지막으로 움찔한 시각
	var wander := Vector2.ZERO
	var size := 1.0           # 키 —— 병사마다 조금씩
	var tint := 0.5           # 옷 색 밝기 —— 병사마다 조금씩
	var duel = null           # 맞붙은 적 병사 (Soldier)
	var drawn := Vector3(1e9, 0, 0)   # 마지막으로 GPU 에 쓴 (x, y, 방향) —— 같으면 다시 쓰지 않는다
	var drawn_w := 0.0        # 마지막으로 쓴 무기 각도
	var wander_t := 0.0       # 다음에 자리를 살짝 바꿀 시각
	var walk_drawn := 0.0     # 마지막으로 그린 걸음 —— 바뀌었으면 걷는 중
	var drawn_mv := false
	var drawn_br := false     # 마지막으로 그린 '갑옷 깨짐(파갑)' —— 바뀌면 다시 쓴다
	var air := 0.0            # 공중에 뜬 높이 (m) —— 고유기에 날아간다
	var vy := 0.0             # 위로 솟는 속도 (m/초)
	var spin := 0.0           # 날아가며 뒤집힌 각
	var kb := Vector2.ZERO    # 밀려나는 속도 (px/초)
	var free := Vector2.ZERO  # 싸우며 대열 자리에서 벗어난 만큼 —— loose 만큼 남는다


var key: String
var row: Dictionary
var camp: String
var cid: String
var tag: String
var tier: int
var cls: String
var sp: float             # 병사 간격
var cols: int
var soldiers: Array[Soldier] = []
var general: Soldier = null

var pos: Vector2
var home: Vector2
var fwd: Vector2          # 대열이 바라보는 방향
var goal = null           # 행군 목표 (Vector2 또는 null)
var engaged: Squad = null # 싸우러 가는 / 싸우는 상대
var axis := Vector2.ZERO  # 상대 → 나 방향. 상대를 정할 때 한 번만 정한다
var slot_off := 0.0       # 같은 상대에 여럿이 붙을 때 옆으로 비킨다
var contact := false      # 상대 대열과 맞닿았다
var impact := false       # 이번 프레임에 막 부딪쳤다 (기병 돌격 연출용, War3D 가 지운다)
var face_to = null        # 상대가 없을 때 바라볼 곳 (Vector2 또는 null)
var state := "hold"       # hold / move / flee / gone
var moving := false
var move_s := 0.0           # moving 을 부드럽게 따라가는 값(0~1) —— 구운 병사가 걷기 ↔ 서기 자세를 섞는 데 쓴다 (11/4 저녁: 뚝뚝 바뀌어 깜빡였다)

var troops: float
var max: float
var morale: float
var statuses: Array = []
var alive := true
var fade := 1.0
var glow := 0.0
var flourish_t := -1.0     # 11/4 고유기 —— 이 시각까지 장수가 무기를 크게 휘두른다 (War3D._weapon_angle)
var hurt := 0.0
var hurt_at := -99.0        # 마지막으로 병력을 잃은 시각 —— 자동 카메라가 '뜨거운 곳'을 고르는 데 쓴다 (11/4)
var shove_t := 0.0          # 다음 전선 떠밀기 시각 (War3D._shove)
var break_t := -99.0        # 파갑이 터진 시각 (번쩍)
var armor_broken := false   # 파갑 · 쇄갑을 맞아 방어가 깎였다 (War3D 가 병사 갑옷을 녹슨 색으로)
var cheer := false
var loose := 0.0          # 흐트러짐 0~1
# 지금 하는 일 (CombatFx 가 적는다) —— melee · shoot · cast, 친 시각, 친 상대. 공격 화살표 · 이름표 아이콘이 읽는다
var act_kind := ""
var act_t := -99.0
var act_tgt: Squad = null
# 실시간 엔진(RtBattle)의 위치 기록을 따라간다 —— War3D.follow_track 이 채운다. 판정이 위치로 나므로 화면이 제멋대로 움직이면 안 된다
var puppet := false
var pgoal := Vector2.ZERO
var pfwd := Vector2.RIGHT
var ptgt: Squad = null
var ptouch := false
var _rk := 1              # 이번 프레임의 줄 수 (매번 세지 않도록)
var _figs: Array = []     # 병사 + 장수 (한 번 만들어 계속 쓴다)
var _alive := 0           # 살아 있는 병사 수 (set_troops 가 맞춘다 —— 매번 세지 않는다)
var walk_acc := 0.0       # GPU 병사 걸음 박자 —— 부대가 움직인 거리
var shove_v := 0.0        # GPU 병사 떠밀기 (+ 뒤로 · − 앞으로, px) —— War3D 가 넣고 줄인다
var flee_t := 0.0         # 패주한 지 몇 초
var changed_figs := []    # GPU —— 이번에 쓰러지거나 되살아난 병사 (War3D._sync 가 가져간다)
var moved_figs := []      # GPU —— 자리가 바뀐(쓰러져 숨기거나 앞으로 걸어 나온) 병사 (War3D._gpu_sync 가 인스턴스 값을 고친다)
var cell := []            # GPU —— 대열 칸 -> 병사 (빈칸 null). 앞줄이 쓰러지면 그 열 뒷사람들이 한 칸씩 걸어 나온다
var gpos_slow := Vector2.ZERO   # GPU —— 늦게 따라오는 부대 위치 · 방향 (병사마다 섞어 대열이 휘고 늘어진다)
var gfwd_slow := Vector2.RIGHT
var gsq := Vector2.ONE      # GPU —— 대열 압축 (앞뒤, 좌우). 옆 부대와 겹치지 않게 그쪽 방향으로 좁힌다
var gfront := 0.0         # GPU —— 앞줄 오프셋을 부드럽게 (줄 수가 바뀔 때 대열이 툭 튀지 않게)
var _slice := 0           # 가만히 선 부대는 병사를 네 조로 나눠 번갈아 움직인다
var _rng: RandomNumberGenerator


func _init(r: Dictionary, at: Vector2, rng: RandomNumberGenerator) -> void:
	_rng = rng
	row = r
	key = r.key
	camp = r.camp
	cid = r.id
	tag = r.tag
	tier = r.tier
	cls = CLS[tag]
	troops = r.max
	max = r.max
	morale = 100
	home = at
	pos = at
	fwd = Vector2(1, 0) if camp == "A" else Vector2(-1, 0)
	# 11/4 사용자: 병사 수는 PV 에 비례 (신화 PV 155 ≈ 600명 → 1 PV ≈ 3.9명: 고급 약 22 · 희귀 52 · 전설 150 · 초월 350 · 불멸 470명)
	var pv: float = float(DB.C[r.id].pv) if r.has("id") and DB.C.has(r.id) else float(COUNT[tier])
	# 11/5 사용자 "초반 전투에서 병력이 얼마 없는데 병력이 많은 것처럼 병사들이 위치" —— 병력(고급 500 · 희귀 900 · 전설 2,700)이 적은 부대는
	# 병사도 덜 그린다: 병력 12,000 아래는 √(병력 / 12,000) 배 (최소 0.55). 전설(8,500) 0.84 · 초월 이상은 그대로
	var few := sqrt(clampf(float(r.get("max", 12000.0)) / FEW_TROOPS, 0.3, 1.0))
	var n: int = clampi(roundi(pv * PER_PV * few * count_scale * (1.0 if gpu else CPU_SHARE)), 5, 1000)     # GPU 칸 번호는 1024 안 (셰이더 인코딩)
	match cls:
		"cav":
			n = maxi(5, int(n * 0.75))
			sp = 12.0
			cols = 9
		"caster":
			n = maxi(5, int(n * 0.7))
			sp = 8.5
			cols = 7
		_:
			sp = 7.0
			cols = 14
	sp *= TIER_SIZE.get(tier, 1.0) * SCALE_SP
	# 11/4 사용자: 토탈워 삼국처럼 넓고 얇은 가로줄 —— 폭을 √n × 2.4 (기병 2.6), 깊이는 그만큼 얕게 (예전 × 1.35 · 1.5)
	cols = maxi(mini(cols, ceili(n / 2.0)), roundi(sqrt(n) * (2.6 if cls == "cav" else 2.4)))     # 작은 부대는 한 줄로 길게 늘어서지 않게 (11/5)
	# 11/4 사용자: 개전하자마자 대열이 쭈그러들었다 —— 옆 부대 간격(RtBattle.CS 118)보다 넓으면 War3D._squeeze 가 좌우를 반 아래로 좁힌다.
	# 폭을 옆 간격 안으로 묶는다 (넓은 가로줄은 엔진 부대 간격을 키워야 가능)
	cols = mini(cols, maxi(4, int(MAX_W / sp)))
	for i in n:
		soldiers.append(_new_soldier(i))
	_alive = n
	cell = soldiers.duplicate()
	cell.resize(ceili(float(n) / cols) * cols)
	_gpu_rows = ceili(float(n) / cols)
	if tier >= 3:
		general = _new_soldier(0)
	_figs = soldiers.duplicate()
	if general:
		_figs.append(general)
	_rk = ranks()
	for s in _figs:
		s.pos = _desired(s)
		s.yaw = fwd.angle()


func _new_soldier(i: int) -> Soldier:
	var s := Soldier.new()
	s.slot = i
	s.jit = Vector2.from_angle(_rng.randf() * TAU) * _rng.randf() * sp * 0.42
	s.size = _rng.randf_range(0.92, 1.08) * TIER_SIZE.get(tier, 1.0) * SCALE_BODY
	s.tint = _rng.randf()
	s.phase = _rng.randf() * TAU
	s.fall = 1.0 if _rng.randf() < 0.5 else -1.0
	s.pace = _rng.randf_range(0.88, 1.15)
	s.next_atk = _rng.randf_range(0.0, 1.5)
	return s


## 병사 + 장수. 같은 배열을 돌려주므로 받는 쪽에서 고치지 않는다.
func all_figures() -> Array:
	return _figs


func alive_count() -> int:
	return _alive


func ranks() -> int:
	if gpu and not cell.is_empty():
		return _gpu_rows
	return maxi(1, ceili(float(maxi(1, alive_count())) / cols))


var _gpu_rows := 1
func _recount_rows() -> void:
	var last := -1
	for i in range(cell.size() - 1, -1, -1):
		if cell[i] != null:
			last = i
			break
	_gpu_rows = maxi(1, last / cols + 1)


func depth() -> float:
	return ranks() * sp


func right() -> Vector2:
	return Vector2(-fwd.y, fwd.x)


func rank_of(s: Soldier) -> int:
	return 99 if s == general else s.slot / cols


## 대열 자리 → 월드 좌표. 대열의 "중심"이 pos, 앞줄(rank 0)이 앞쪽 끝이다.
func _desired(s: Soldier) -> Vector2:
	var front := pos + fwd * (_rk - 1) * sp * 0.5
	if s == general:
		return front - fwd * (_rk * sp + 6)
	var c := s.slot % cols
	var rk := s.slot / cols
	var lateral := (c - (cols - 1) / 2.0 + (0.5 if rk % 2 == 1 else 0.0)) * sp   # 줄마다 반 칸 엇갈림
	return front - fwd * (rk * sp * 0.92) + right() * lateral + s.jit


## 장수 (11/4 지시서: 삼탈워처럼 장수와 병사를 분리) —— 장수는 대열에 박힌 칸이 아니라 제 반경 안을 누비는 지휘관이다.
## 맞붙기 전: 대열 앞을 좌우로 오가며 선두에 선다 (책략 장수는 대열 뒤). 맞붙으면: 전선을 따라 순찰하고, 몇 초에 한 번 전선으로 돌진했다 빠진다.
## 병력이 30% 아래면 대열 뒤로 물러난다. 움직임은 속도 · 가속 한도 · 마찰 (튀지 않게), 기울기는 가속으로 (War3D 가 그린다)
var gvel := Vector2.ZERO      # 장수 속도
var gacc := Vector2.ZERO      # 장수 가속 (기울기 연출)
var g_charge_t := 0.0         # 다음 돌진 시각
var g_charging := 0.0         # 돌진 남은 시간
var cast_t := -99.0           # 기술 · 고유기를 쓴 시각 (장수 금빛 펄스)
func _move_general(g: Soldier, dt: float, clock: float, front: Vector2) -> void:
	var rgt := right()
	var hw: float = cols * sp * 0.5 * gsq.y
	var ph: float = g.phase + clock * 0.35
	var tgt: Vector2
	var low: bool = troops < max * 0.3
	if cls == "caster" or low:
		tgt = front - fwd * (_rk * sp * gsq.x + 10.0) + rgt * sin(ph) * hw * 0.5        # 대열 뒤 (책략 · 패색)
	elif contact and engaged:
		if clock >= g_charge_t:
			g_charge_t = clock + _rng.randf_range(4.5, 8.0)
			g_charging = 1.1
		var n := (engaged.pos - pos).normalized()
		var line := front + n * 2.0
		tgt = line - n * (4.0 if g_charging <= 0.0 else -14.0) + Vector2(-n.y, n.x) * sin(ph * 1.6) * hw * 0.7
	else:
		tgt = front + fwd * (sp * 2.2 + 8.0) + rgt * sin(ph) * hw * 0.55                # 선두에서 좌우로
	g_charging = maxf(0.0, g_charging - dt)
	var speed: float = SPEED[tag] * (1.9 if g_charging > 0.0 else 1.25)
	var want: Vector2 = (tgt - g.pos) * 2.0
	if want.length() > speed:
		want = want.normalized() * speed
	var v0 := gvel
	gvel = gvel.move_toward(want, speed * 3.0 * dt)
	gacc = gacc.lerp((gvel - v0) / maxf(dt, 0.001), minf(1.0, dt * 6.0))
	g.pos = keep_in(g.pos + gvel * dt)
	g.walk += gvel.length() * dt * 0.25
	var look := gvel if gvel.length() > speed * 0.3 else ((engaged.pos - g.pos) if engaged else fwd)
	if look.length() > 0.001:
		g.yaw = rotate_toward(g.yaw, look.angle(), 4.0 * dt)


## 병사가 지금 서 있는 자리 —— GPU 병사는 위치를 따로 갖지 않으므로 대열 자리로 (화살 · 쓰러질 자리 계산용)
func fig_pos(s: Soldier) -> Vector2:
	if gpu and s.alive and s != general:
		return gpu_pos(s.slot) + s.jit * 0.6
	return s.pos


## GPU 병사가 그려지는 자리 (셰이더 soldier_gpu 의 대열 · 늦게 따라오기 · 압축 · 물결을 평균 병사로)
func gpu_pos(slot: int) -> Vector2:
	var rows: float = maxf(1.0, _gpu_rows)
	var rk := slot / cols
	var c := slot % cols
	var half := (cols - 1) / 2.0
	var edge := absf(c - half) / maxf(half, 1.0)
	var lag := clampf(1.0 - (rk / rows) * 0.7 - edge * 0.25 - 0.15, 0.08, 1.0)
	var p0 := gpos_slow.lerp(pos, lag)
	var f0 := gfwd_slow.lerp(fwd, lag).normalized()
	var r0 := Vector2(-f0.y, f0.x)
	var lx := -(rk * sp * 0.92) * gsq.x
	var ly := (c - half + (0.5 if rk % 2 == 1 else 0.0)) * sp * gsq.y
	return p0 + f0 * (gfront * gsq.x + lx) + r0 * ly


## 대열 자리 (어긋남 없이) —— 셰이더(soldier_gpu)와 같은 식
func slot_pos(slot: int) -> Vector2:
	var front := pos + fwd * (_rk - 1) * sp * 0.5 * gsq.x
	var rk := slot / cols
	var c := slot % cols
	return front - fwd * (rk * sp * 0.92 * gsq.x) + right() * ((c - (cols - 1) / 2.0 + (0.5 if rk % 2 == 1 else 0.0)) * sp * gsq.y)


## 살아남은 병사로 대열을 다시 짠다 —— 앞줄부터 채우되, 지금 서 있는 자리와 가까운 순서를 지킨다
func relayout() -> void:
	if gpu:
		return              # GPU 는 자리가 고정 (살아 있는 수만큼 앞에서부터 그린다)
	var live := soldiers.filter(func(s): return s.alive)
	live.sort_custom(func(a, b): return a.slot < b.slot)
	for i in live.size():
		live[i].slot = i


## 상대 정하기 —— 이때 한 번만 접근 방향을 잰다
func set_target(t: Squad, off: float) -> void:
	if t == engaged:
		return
	engaged = t
	contact = false
	slot_off = off
	if t == null:
		return
	if t.engaged == self and t.axis != Vector2.ZERO:
		axis = -t.axis                     # 서로 노리면 같은 축에서 맞부딪친다
	else:
		var d := pos - t.pos
		axis = d.normalized() if d.length() > 1.0 else (Vector2(-1, 0) if camp == "A" else Vector2(1, 0))
	state = "move"


func engage_point() -> Vector2:
	var e := engaged
	var perp := Vector2(-axis.y, axis.x)
	return keep_in(e.pos + axis * (e.depth() * 0.5 + depth() * 0.5 + CONTACT_GAP) + perp * slot_off)


## 전장 안으로 —— 패주하는 부대는 FLEE_OUT 만큼 더 나갈 수 있다
func keep_in(p: Vector2) -> Vector2:
	var r := ARENA.grow(FLEE_OUT) if state == "flee" else ARENA
	return p.clamp(r.position, r.end)


func _turn_toward(v: Vector2, dt: float) -> void:
	if v.length() < 0.001:
		return
	var a := fwd.angle()
	var b := v.angle()
	fwd = Vector2.from_angle(rotate_toward(a, b, TURN * dt))


func update(dt: float, clock: float) -> void:
	if state == "gone":
		return
	var pos0 := pos
	var speed: float = SPEED[tag]
	moving = false
	_rk = ranks()
	if state == "flee":
		var away := Vector2(-1, 0) if camp == "A" else Vector2(1, 0)
		pos += away * speed * 1.5 * dt
		_turn_toward(away, dt * 3.0)
		fade -= dt * (0.3 if keep_in(pos) == pos else 0.9)     # 전장 끝에 닿으면 빨리 사라진다
		moving = true
		if fade <= 0:
			state = "gone"
	elif puppet:
		_puppet(dt)
	else:
		if engaged and (not engaged.alive or engaged.state == "flee" or engaged.state == "gone"):
			engaged = null
			contact = false
		var tgt = goal
		var want_dir := Vector2.ZERO
		if engaged:
			tgt = engage_point()
			want_dir = -axis
		if tgt != null:
			var d: Vector2 = tgt - pos
			# 붙어 있으면 상대가 조금 밀려도 그대로 버틴다 (자리 다툼으로 떨지 않도록)
			var tol := 9.0 if contact else 2.5
			if d.length() > tol:
				var sp_now := speed
				if cls == "cav" and engaged and d.length() > 60.0:
					sp_now *= 1.9            # 돌격
				pos += d.normalized() * minf(sp_now * dt, d.length())
				moving = true
				if not engaged:
					want_dir = d
			elif engaged and not contact:
				contact = true
				impact = true
			elif not engaged:
				goal = null
		if want_dir == Vector2.ZERO:
			if face_to != null:
				want_dir = face_to - pos
			else:
				want_dir = Vector2(1, 0) if camp == "A" else Vector2(-1, 0)
		_turn_toward(want_dir, dt)
	pos = keep_in(pos)
	move_s = move_toward(move_s, 1.0 if moving else 0.0, dt * 4.0)
	walk_acc += pos.distance_to(pos0) * 0.25      # 11/4 저녁 사용자: 1배속인데 배속 돌린 듯 —— 걸음 박자 0.55 → 0.25 (창병 초당 4.9걸음 → 2.2)
	if state == "flee":
		flee_t += dt

	if contact:
		loose = minf(1.0, loose + dt * LOOSE_IN)
	else:
		loose = maxf(0.0, loose - dt * LOOSE_OUT)
	glow = maxf(0, glow - dt * 1.4)
	hurt = maxf(0, hurt - dt * 2.5)
	var enemy_at = engaged.pos if engaged else face_to
	# 대열 자리 계산에 쓰는 값은 부대마다 한 번만
	var front := pos + fwd * (_rk - 1) * sp * 0.5
	var rgt := right()
	var half := (cols - 1) / 2.0
	var calm: bool = not moving and not contact and state != "flee" and not cheer and loose <= 0.0
	_slice = (_slice + 1) % 4
	var sdt := dt * 4.0 if calm else dt
	var figs: Array = _figs if not gpu else ([general] if general else [])     # GPU —— 병사는 셰이더가, 여기선 장수만
	for s: Soldier in figs:
		if not s.alive or s.air > 0.0:
			continue            # 공중에 뜬 병사는 War3D._air 가 움직인다
		if gpu and s != general:
			continue            # GPU 병사 —— 셰이더가 대열 자리에 그린다
		if s == general and gpu and state != "flee":
			_move_general(s, dt, clock, front)
			continue
		if calm and (s.slot & 3) != _slice:
			continue
		var want_p: Vector2
		var rk: int
		if s == general:
			rk = 99
			# 10/31 사용자: 말 탄 장수는 선봉 —— 맨 앞 가운데 (맞붙으면 앞줄과 나란히). 책략 부대만 뒤에
			if cls == "caster":
				want_p = front - fwd * (_rk * sp + 6)
			else:
				want_p = front + fwd * (2.0 if contact else sp * 1.6 + 4.0)
		else:
			rk = s.slot / cols
			var c := s.slot % cols
			want_p = front - fwd * (rk * sp * 0.92) + rgt * ((c - half + (0.5 if rk & 1 else 0.0)) * sp) + s.jit
		var grid_p := want_p
		var fighting: bool = contact and rk < DUEL_RANKS
		var pressing: bool = contact and not fighting and s != general     # 뒷줄 —— 앞으로 밀고 든다
		# 서 있어도 꼼지락거린다 —— 싸울 때는 더 크게, 더 자주
		if clock >= s.wander_t:
			s.wander_t = clock + _rng.randf_range(0.4, 1.2) * (1.0 if fighting else 3.0)
			s.wander = Vector2.from_angle(_rng.randf() * TAU) * _rng.randf() * sp * (0.6 if fighting else 0.3)
		want_p += s.wander
		if fighting and s.duel != null and s.duel.alive:
			# 일대일 —— 마주 선 적 병사 앞에 선다. 여럿이 한 적에 붙으면 병사마다 다른 각도로 에워싼다
			var away: Vector2 = s.pos - s.duel.pos
			var dir: Vector2 = (away.normalized() if away.length() > 0.1 else -fwd).rotated((s.phase - PI) * 0.4)
			var stand: Vector2 = s.duel.pos + dir * DUEL_DIST
			want_p = want_p + (stand - want_p).limit_length(sp * (2.5 + 3.5 * loose))
		elif fighting:
			want_p += fwd * sp * 0.5
		elif pressing:
			want_p += fwd * sp * minf(rk - DUEL_RANKS + 1, 3) * 0.6 * loose        # 빈자리로 밀려든다
		# 흐트러짐 —— 싸우는 동안 벗어난 만큼 기억했다가, 대열로 천천히 돌아간다
		if fighting or pressing:
			s.free = (s.pos - grid_p).limit_length(sp * 6.0)
		elif loose > 0.0:
			want_p = grid_p + s.free * loose + s.wander
		else:
			s.free = Vector2.ZERO
		if fighting:
			if clock >= s.next_atk:
				s.atk_t0 = clock
				s.next_atk = clock + _rng.randf_range(0.6, 1.7) * (1.0 + rk * 0.4)
			var a := clampf((clock - s.atk_t0) / ATTACK_TIME, 0, 1)
			want_p += fwd * 4.0 * sin(PI * a)
		var h: float = clock - s.hit_t
		if h < 0.3:
			want_p -= fwd * 3.0 * (1.0 - h / 0.3)
		if state == "flee":
			s.scatter += Vector2(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1)) * dt * 40.0
			want_p += s.scatter
		# 제 걸음으로 걷는다 —— 멀면 서둘러 따라붙는다
		var d: Vector2 = want_p - s.pos
		var lim: float = speed * s.pace * (1.0 + clampf(d.length() / 25.0, 0, 1.5))
		if state == "flee":
			lim *= 1.5
		var stepv := d.limit_length(lim * sdt)
		if d.length() < 0.6:
			stepv = d
		s.pos += stepv
		s.walk += stepv.length() * 0.25
		# 바라보는 쪽 —— 걷고 있으면 걷는 쪽, 서 있으면 적 쪽 (없으면 대열 방향)
		var look := fwd
		if stepv.length() > speed * 0.35 * sdt and state != "hold" or state == "flee":
			look = stepv
		elif fighting and s.duel != null and s.duel.alive:
			look = s.duel.pos - s.pos
		elif enemy_at != null and (contact or engaged):
			look = enemy_at - s.pos
		if look.length() > 0.001:
			s.yaw = rotate_toward(s.yaw, look.angle(), SOLDIER_TURN * sdt)


## 병력 변화를 병사 수로 옮긴다. 줄면 적과 가까운 병사부터 쓰러지고, 그 옆 병사는 움찔한다.
func set_troops(t: float, from: Vector2, clock: float, rng: RandomNumberGenerator) -> void:
	troops = clampf(t, 0, max)
	var n := soldiers.size()
	var want := 0 if troops <= 0 else maxi(1, ceili(n * troops / max))
	if gpu:
		_set_troops_gpu(want, from, clock, rng)
		return
	var live := soldiers.filter(func(s): return s.alive)
	if live.size() > want:
		live.sort_custom(func(a, b): return a.pos.distance_squared_to(from) < b.pos.distance_squared_to(from))
		var kill := live.size() - want
		for i in kill:
			var s: Soldier = live[i]
			s.alive = false
			s.die_t = clock + rng.randf() * 0.7      # 한꺼번에 쓰러지지 않게 흩는다
		for i in range(kill, mini(kill + 4, live.size())):
			live[i].hit_t = clock + rng.randf() * 0.4
		relayout()
		_alive = want
	elif live.size() < want:
		# 회복 —— 쓰러진 자리에서 다시 일어서는 대신 뒤에서 보충병이 들어온다
		var dead := soldiers.filter(func(s): return not s.alive)
		for i in mini(want - live.size(), dead.size()):
			var s: Soldier = dead[i]
			s.alive = true
			s.die_t = -1
			s.spawn_t = clock
			s.pos = pos - fwd * (depth() + 20)
			s.yaw = fwd.angle()
		relayout()
		_alive = soldiers.filter(func(x): return x.alive).size()
	if troops <= 0 and general and general.alive:
		general.alive = false
		general.die_t = clock + 0.5
	hurt = 1.0


## GPU 병사 (11/3 사용자: 싸움은 앞에서 나는데 뒤에서부터 사라졌다) —— 적과 가까운 앞줄 병사가 쓰러지고,
## 그 열의 뒷사람들이 한 칸씩 앞으로 걸어 나와 빈자리를 메운다. 뒷줄은 자연스럽게 들쭉날쭉해진다
func _set_troops_gpu(want: int, from: Vector2, clock: float, rng: RandomNumberGenerator) -> void:
	if want <= 0 and _alive > 0:
		# 전멸 · 패주 끝 —— 제자리에서 한꺼번에 쓰러진다 (한 명씩 고르면 수백 명 × 칸 전체라 프레임이 튄다)
		for i in cell.size():
			var v = cell[i]
			if v == null:
				continue
			v.pos = gpu_pos(i) + v.jit * 0.6
			v.yaw = fwd.angle()
			v.alive = false
			v.die_t = clock + rng.randf() * 0.6
			v.air = 0.0
			cell[i] = null
			changed_figs.append(v)
			moved_figs.append(v)
		_alive = 0
		_recount_rows()
	elif _alive > want:
		for _k in _alive - want:
			var v := _pick_victim(from, rng)
			if v == null:
				break
			var vs: int = v.slot
			v.pos = gpu_pos(vs) + v.jit * 0.6
			v.yaw = fwd.angle()
			v.alive = false
			v.die_t = clock + rng.randf() * 0.5
			v.air = 0.0
			cell[vs] = null
			changed_figs.append(v)
			moved_figs.append(v)
			if (from - pos).dot(fwd) > (from - pos).length() * 0.5:      # 정면에서 맞았을 때만 뒷사람이 앞으로 메운다
				_close_column(vs, clock)
			_alive -= 1
		_recount_rows()
	elif _alive < want:
		# 회복 —— 보충병이 뒤에서 걸어 들어와 가장 앞쪽 빈칸(앞줄까지 비어 버린 열이면 그 열 맨 앞)에 선다
		for sd in soldiers:
			if _alive >= want:
				break
			if sd.alive:
				continue
			var at := cell.find(null)
			if at < 0:
				break
			sd.alive = true
			sd.die_t = -1
			sd.spawn_t = clock
			sd.slot = at
			sd.slot_old = mini(at + cols * 3, 1023)
			sd.move_t = clock
			cell[at] = sd
			changed_figs.append(sd)
			moved_figs.append(sd)
			_alive += 1
		_recount_rows()
	if troops <= 0 and general and general.alive:
		general.alive = false
		general.die_t = clock + 0.5
		changed_figs.append(general)
	hurt = 1.0


## 쓰러질 병사 —— 11/4 사용자: HP 가 아니라 군집처럼. 공격이 온 쪽(from)에 가까운 병사부터 —— 오른쪽에서 맞으면 오른쪽이 깎인다.
## 살아 있는 모든 병사 가운데 가까운 다섯 중 하나 (한 점만 파이지 않게 조금 흩는다)
func _pick_victim(from: Vector2, rng: RandomNumberGenerator) -> Soldier:
	var best := []
	for i in cell.size():
		var sd = cell[i]
		if sd == null:
			continue
		var d := slot_pos(i).distance_squared_to(from)
		if best.size() < 5:
			best.append([d, sd])
			best.sort_custom(func(x, y): return x[0] < y[0])
		elif d < best[4][0]:
			best[4] = [d, sd]
			best.sort_custom(func(x, y): return x[0] < y[0])
	if best.is_empty():
		return null
	return best[rng.randi() % best.size()][1]


## 빈칸 뒤의 같은 열 병사들이 한 칸씩 앞으로 (뒤로 갈수록 조금씩 늦게 출발)
func _close_column(vs: int, clock: float) -> void:
	var c := vs % cols
	var r := vs / cols
	var rows := cell.size() / cols
	var k := 0
	for rr in range(r + 1, rows):
		var sd = cell[rr * cols + c]
		if sd == null:
			continue
		var to := (rr - 1 - k) * cols + c
		if cell[to] != null:
			continue
		cell[rr * cols + c] = null
		cell[to] = sd
		sd.slot_old = sd.slot
		sd.slot = to
		sd.move_t = clock + (rr - r) * 0.08
		moved_figs.append(sd)


## 앞줄 병사를 움찔하게 한다 (돌격 충격 등)
## 엔진 위치를 따라간다 —— 기록 사이(0.4초)를 부드럽게 잇고, 엔진이 맞닿았다고 하면 그 적과 맞붙는다
var pvel := Vector2.ZERO      # 따라가는 속도 (11/4 지시서: 스프링처럼 튀지 않게 가속 · 마찰로)
func _puppet(dt: float) -> void:
	var speed: float = SPEED[tag]
	var d := pgoal - pos
	var l := d.length()
	# 목표까지 거리에 비례한 속도를 원하되, 가속은 한도 안에서 · 마찰로 줄인다 —— 기록이 툭 바뀌어도 부대가 튀지 않는다
	var want: Vector2 = d * 2.4
	var vmax := speed * (2.2 if cls == "cav" else 1.7)
	if want.length() > vmax:
		want = want.normalized() * vmax
	pvel = pvel.move_toward(want, speed * 4.0 * dt)
	if l < 0.5 and pvel.length() < 2.0:
		pvel = Vector2.ZERO
	pos += pvel * dt
	if l > 40.0:
		pos += d * minf(1.0, dt * 1.5)          # 아주 멀어지면(순간이동 · 되감기) 서서히 당겨 붙인다
	moving = pvel.length() > 6.0
	if ptouch and ptgt != null and ptgt.alive and ptgt.state != "flee":
		var ax := pos - ptgt.pos
		if engaged != ptgt:
			engaged = ptgt
			axis = ax.normalized() if ax.length() > 1.0 else axis
			contact = true
			impact = true
		elif ax.length() > 1.0:
			axis = axis.lerp(ax.normalized(), minf(1.0, dt * 2.0)).normalized()
	else:
		engaged = null
		contact = false
	_turn_toward(pfwd, dt * 1.5)


func stagger(clock: float, rng: RandomNumberGenerator) -> void:
	for s in soldiers:
		if s.alive and s.slot / cols < 2:
			s.hit_t = clock + rng.randf() * 0.2


func rout(clock: float, rng: RandomNumberGenerator) -> void:
	alive = false
	engaged = null
	contact = false
	if troops <= 0 or alive_count() == 0:
		set_troops(0, pos + fwd * 30, clock, rng)
		state = "gone"
	else:
		state = "flee"
