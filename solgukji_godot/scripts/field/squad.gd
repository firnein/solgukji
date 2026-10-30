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
const COUNT := {1: 36, 2: 44, 3: 54, 4: 64, 5: 72, 6: 80, 7: 88, 8: 96}
static var count_scale := 1.0   # 품질 설정 —— 모바일은 병사 수를 줄인다 (Settings)
## 이동 속도 (px/초) —— 기병은 돌격 때 더 빨라진다
const SPEED := {"창병": 62.0, "도적": 80.0, "기병": 95.0, "궁병": 55.0,
	"책사": 50.0, "유생": 50.0, "술사": 52.0, "모사": 52.0}
const TURN := 1.4           # 대열이 도는 속도 (라디안/초)
const SOLDIER_TURN := 7.0   # 병사가 고개를 돌리는 속도
const CONTACT_GAP := 2.0    # 맞닿은 두 대열 앞줄 사이 (px)
const DUEL_RANKS := 2       # 맞붙으면 일대일로 흩어지는 앞줄 수 (10/30 4 → 2: 대열이 덩어리로 남게)
const DUEL_DIST := 7.0      # 일대일로 붙은 두 병사 사이 (px)
const LOOSE_IN := 0.6       # 맞붙으면 초당 이만큼 흐트러진다 (10/30 1.2 → 0.6)
const LOOSE_OUT := 0.22     # 떨어지면 초당 이만큼 대열을 되찾는다 (약 4~5초)
const ATTACK_TIME := 0.38   # 한 번 찌르거나 휘두르는 시간


class Soldier:
	var pos: Vector2
	var slot := 0             # 대열 안 자리 (재정렬하면 바뀐다)
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

var troops: float
var max: float
var morale: float
var statuses: Array = []
var alive := true
var fade := 1.0
var glow := 0.0
var hurt := 0.0
var cheer := false
var loose := 0.0          # 흐트러짐 0~1
var _rk := 1              # 이번 프레임의 줄 수 (매번 세지 않도록)
var _figs: Array = []     # 병사 + 장수 (한 번 만들어 계속 쓴다)
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
	var n: int = maxi(12, roundi(COUNT[tier] * count_scale))
	match cls:
		"cav":
			n = maxi(12, n / 2)
			sp = 11.5
			cols = 8
		"caster":
			n = maxi(12, int(n * 0.45))
			sp = 7.5
			cols = 7
		_:
			sp = 6.2
			cols = 13
	for i in n:
		soldiers.append(_new_soldier(i))
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
	s.size = _rng.randf_range(0.92, 1.08)
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
	var n := 0
	for s in soldiers:
		if s.alive: n += 1
	return n


func ranks() -> int:
	return maxi(1, ceili(float(maxi(1, alive_count())) / cols))


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


## 살아남은 병사로 대열을 다시 짠다 —— 앞줄부터 채우되, 지금 서 있는 자리와 가까운 순서를 지킨다
func relayout() -> void:
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
	return e.pos + axis * (e.depth() * 0.5 + depth() * 0.5 + CONTACT_GAP) + perp * slot_off


func _turn_toward(v: Vector2, dt: float) -> void:
	if v.length() < 0.001:
		return
	var a := fwd.angle()
	var b := v.angle()
	fwd = Vector2.from_angle(rotate_toward(a, b, TURN * dt))


func update(dt: float, clock: float) -> void:
	if state == "gone":
		return
	var speed: float = SPEED[tag]
	moving = false
	_rk = ranks()
	if state == "flee":
		var away := Vector2(-1, 0) if camp == "A" else Vector2(1, 0)
		pos += away * speed * 1.5 * dt
		_turn_toward(away, dt * 3.0)
		fade -= dt * 0.3
		moving = true
		if fade <= 0:
			state = "gone"
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
	for s: Soldier in _figs:
		if not s.alive or s.air > 0.0:
			continue            # 공중에 뜬 병사는 War3D._air 가 움직인다
		if calm and (s.slot & 3) != _slice:
			continue
		var want_p: Vector2
		var rk: int
		if s == general:
			rk = 99
			want_p = front - fwd * (_rk * sp + 6)
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
		s.walk += stepv.length() * 0.55
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
	if troops <= 0 and general and general.alive:
		general.alive = false
		general.die_t = clock + 0.5
	hurt = 1.0


## 앞줄 병사를 움찔하게 한다 (돌격 충격 등)
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
