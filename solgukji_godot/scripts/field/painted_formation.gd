extends RefCounted

var feet := PackedVector2Array()
var strides := PackedFloat32Array()
var gait := PackedFloat32Array()
var opacity := PackedFloat32Array()
var alive := PackedByteArray()
var ranks := PackedInt32Array()
var strike_at := PackedFloat32Array()
var hurt_at := PackedFloat32Array()
var hero_hurt_at := -10.0
var hero_hurt_power := 0.0
var hero_hurt_dir := Vector2.ZERO
var hero_hurt_mirror := false
var hurt_power := PackedFloat32Array()
var hurt_dir := PackedVector2Array()
var visual_ranks := PackedFloat32Array()
var refill_at := PackedFloat32Array()
var recoil := PackedVector2Array()
var recoil_velocity := PackedVector2Array()
var impulse_at := PackedFloat32Array()
var impulse_dir := PackedVector2Array()
var impulse_power := PackedFloat32Array()
var flanks := PackedFloat32Array()
var scatter := PackedVector2Array()
var motion_clock := 0.0
var last_wave := -10.0
var initialized := false
var center := Vector2.ZERO
var heading := 0.0
var ratio := 1.0
var cols := 5
var rows := 4
var count := 0
var capacity := 0
var cavalry := false
var contact := false
var contact_weight := 0.0
var facing_right := true
var serial := 0
var last_action := -10.0
var action_target := ""
var action_kind := ""
var half_width := 0.0
var row_gap := 0.0
var contact_limits: Array = [] # Visual half-planes; never change simulation positions.
var limits_ready := false      # 11/19 접촉선을 한 번이라도 쟀는가 (war_painting 이 네 프레임에 한 번 다시 잰다)

func constrain_foot(point: Vector2) -> Vector2:
	for boundary in contact_limits:
		var normal: Vector2 = boundary.normal
		var excess := point.dot(normal) - float(boundary.edge)
		if excess > 0.0:
			point -= normal * excess
	return point

func _init(sq: Squad) -> void:
	cavalry = sq.tag == "기병"
	var support := sq.tag in ["책사", "유생", "술사", "모사"]
	# 병종을 대열의 윤곽으로 구분한다. 대표 인형만 바꾸며 엔진 발자국은 그대로다.
	# 대열 구분을 위해 병사 수를 늘리지 않는다. 보병 18·기병 12·궁병 10·지원 6 이하.
	cols = 3 if support else (4 if cavalry else (5 if sq.tag == "궁병" else 6))
	rows = 2 if support or sq.tag == "궁병" else 3

	if sq.hw < 48.0:
		cols = clampi(cols - 1, 3, 4)
	if sq.hd0 < 24.0:
		rows = mini(rows, 2)
	capacity = cols * rows
	ratio = clampf(sq.troops / maxf(sq.max, 1.0), 0.0, 1.0)
	count = ceili(ratio * capacity)
	center = sq.pos
	heading = sq.fwd.angle()
	facing_right = sq.camp == "A"
	half_width = sq.hw * 0.85
	row_gap = maxf(12.0, sq.hd0 * 1.72 / maxf(1, rows - 1))
	for i in capacity:
		alive.append(1 if i < count else 0)
		ranks.append(i / cols)
		feet.append(center)
		strides.append(fposmod(i * 2.399 + sq.row.slot * 0.7, TAU))
		gait.append(0.0)
		opacity.append(1.0 if i < count else 0.0)
		strike_at.append(-10.0)
		hurt_at.append(-10.0)
		hurt_power.append(0.0)
		hurt_dir.append(Vector2.ZERO)
		visual_ranks.append(float(i / cols))
		refill_at.append(0.0)
		recoil.append(Vector2.ZERO)
		recoil_velocity.append(Vector2.ZERO)
		impulse_at.append(-1.0)
		impulse_dir.append(Vector2.ZERO)
		impulse_power.append(0.0)
		flanks.append(float(i % cols) / maxf(1, cols - 1) * 2.0 - 1.0)
		scatter.append(Vector2(sin(i * 2.399) * half_width * 0.18, sin(i * 1.71) * row_gap * 0.15))
	reform()
	_place(sq, 0.0, true)
	initialized = true

func reform() -> void:
	var next_row := PackedInt32Array()
	next_row.resize(cols)
	var ordered: Array[int] = []
	for i in capacity:
		ordered.append(i)
	ordered.sort_custom(func(a, b): return ranks[a] < ranks[b] if ranks[a] != ranks[b] else a < b)
	for i in ordered:
		if alive[i] == 0:
			continue
		var col := i % cols
		if not initialized:
			visual_ranks[i] = float(next_row[col])
		elif ranks[i] != next_row[col]:
			# 빈자리를 잠시 남긴 뒤 후열이 걸어 들어온다. 자리 번호와 보이는 줄을 분리한다.
			refill_at[i] = motion_clock + 0.32 + col * 0.025
		ranks[i] = next_row[col]
		next_row[col] += 1

func remove_soldier(id: int) -> void:
	if alive[id] == 0:
		return
	alive[id] = 0
	count -= 1
	recoil[id] = Vector2.ZERO
	recoil_velocity[id] = Vector2.ZERO
	impulse_at[id] = -1.0
	reform()

func restore_soldiers(wanted: int, sq: Squad) -> void:
	for i in capacity:
		if count >= wanted:
			break
		if alive[i] != 0:
			continue
		alive[i] = 1
		opacity[i] = 0.0
		gait[i] = 0.0
		strike_at[i] = -10.0
		hurt_at[i] = -10.0
		ranks[i] = capacity
		visual_ranks[i] = rows + 0.5
		recoil[i] = Vector2.ZERO
		recoil_velocity[i] = Vector2.ZERO
		count += 1
		reform()

		feet[i] = center - Vector2.from_angle(heading) * sq.hd0

var move_vel := Vector2.ZERO

## 실제 피격 지점에서 뒤쪽 줄로 충격이 전달된다. 부대 중심·엔진 위치는 움직이지 않는다.
func receive_impact(at: Vector2, direction: Vector2, power: float) -> void:
	if count == 0 or (motion_clock - last_wave < 0.16 and power < 1.6):
		return
	last_wave = motion_clock
	var push := direction.normalized()
	if push.is_zero_approx():
		return
	var first := INF
	for i in capacity:
		if alive[i] != 0:
			first = minf(first, (feet[i] - at).dot(push))
	for i in capacity:
		if alive[i] == 0:
			continue
		var depth := maxf(0.0, (feet[i] - at).dot(push) - first)
		var rank_distance := depth / maxf(row_gap, 12.0)
		impulse_at[i] = motion_clock + minf(0.24, rank_distance * 0.07)
		impulse_dir[i] = push
		impulse_power[i] = (105.0 + clampf(power, 0.0, 2.0) * 170.0) / (1.0 + rank_distance * 0.25)

func step(sq: Squad, dt: float) -> void:
	if dt <= 0.0:
		return
	motion_clock += dt
	var following_track := sq.puppet and sq.state != "flee"
	var goal := sq.pgoal if following_track else sq.pos
	var facing := sq.pfwd if following_track else sq.fwd
	var before := center
	center = center.lerp(goal, 1.0 - exp(- dt * 16.0))
	move_vel = move_vel.lerp((center - before) / dt, 1.0 - exp(- dt * 5.0))      # 11/17 병사 그림이 가는 쪽을 보게 (문워크 방지)
	heading = rotate_toward(heading, facing.angle(), dt * 3.2)
	contact = (sq.ptouch if following_track else sq.contact) and sq.state != "flee"
	contact_weight = move_toward(contact_weight, 1.0 if contact else 0.0, dt * 5.0)
	_place(sq, dt, false)

func _place(sq: Squad, dt: float, initial: bool) -> void:
	var facing := Vector2.from_angle(heading)
	var right := Vector2(- facing.y, facing.x)
	var front := maxf(sq.hd0 * ratio, RtBattle.HD_MIN) * 0.86
	var limited := not contact_limits.is_empty()      # 11/19 접촉선이 없으면 병사마다 두 번 부르던 제한 함수를 건너뛴다
	# 전 병사에 공통인 계수는 부대 갱신당 한 번만 계산한다.
	var decay := exp(-12.0 * dt)
	var follow := 1.0 - exp(-11.0 * dt)
	var hit_follow := 1.0 - exp(-24.0 * dt)
	var gait_follow := 1.0 - exp(-9.0 * dt)
	var recoil_limit := maxf(12.0, row_gap * 0.75)
	var disorder := clampf((0.55 - ratio) * 2.2, 0.0, 0.9)
	var fleeing := sq.state == "flee"
	var taper := lerpf(1.7, 1.0, contact_weight)
	var wedge_gap := row_gap * float(rows - 1) / (rows - 1 + taper)
	var stride_limit := 10.0 if cavalry else 8.0
	for i in capacity:
		if alive[i] == 0:
			continue
		if not initial and not fleeing and visual_ranks[i] != float(ranks[i]) and motion_clock >= refill_at[i]:
			visual_ranks[i] = move_toward(visual_ranks[i], float(ranks[i]), dt * 2.0)
		if impulse_at[i] >= 0.0 and motion_clock >= impulse_at[i]:
			recoil_velocity[i] += impulse_dir[i] * impulse_power[i]
			impulse_at[i] = -1.0
		if not initial and (recoil_velocity[i].length_squared() > 0.0025 or recoil[i].length_squared() > 0.0025):
			recoil_velocity[i] = (recoil_velocity[i] - recoil[i] * 110.0 * dt) * decay
			recoil[i] = (recoil[i] + recoil_velocity[i] * dt).limit_length(recoil_limit)
		elif not initial:
			recoil[i] = Vector2.ZERO
			recoil_velocity[i] = Vector2.ZERO
		var row := visual_ranks[i]
		var flank := flanks[i]
		var stagger := (1.0 if ranks[i] % 2 == 0 else -1.0) * 0.16 * half_width / cols
		if row != float(ranks[i]):
			stagger = cos(row * PI) * 0.16 * half_width / cols
		var depth := front - row * row_gap
		if cavalry:
			# 가운데가 앞서고 양 날개가 뒤따르는 쐐기. 뒤쪽도 원래 대열 깊이 안에 둔다.
			depth = front - (row + absf(flank) * taper) * wedge_gap
		var offset := facing * depth + right * (flank * half_width + stagger)
		if disorder > 0.0:
			offset += (right * scatter[i].x + facing * scatter[i].y) * disorder
		if fleeing:
			offset += right * sin(float(i) * 2.4 + motion_clock * 1.7) * (half_width * 0.45 + row * 4.0)
			offset -= facing * fposmod(i * 1.61, 1.0) * row_gap * 0.8
		var goal := center + offset + recoil[i]
		if limited:
			goal = constrain_foot(goal)
		if initial:
			feet[i] = goal
			continue
		var before := feet[i]
		# 충격은 바로 전달하고 대열 이동·보충만 기존 보간을 따른다.
		var response := hit_follow if recoil[i].length_squared() > 1.0 else follow
		feet[i] = constrain_foot(before.lerp(goal, response)) if limited else before.lerp(goal, response)
		var speed := feet[i].distance_to(before) / dt
		var walking := smoothstep(10.0, 90.0, speed)
		gait[i] = lerpf(gait[i], walking, gait_follow)
		strides[i] = fposmod(strides[i] + minf(speed * 0.08, stride_limit) * dt, TAU)
		opacity[i] = move_toward(opacity[i], 1.0, dt * 3.0)

func nearest_living(at: Vector2, limit: int) -> Array[int]:
	var ids: Array[int] = []
	for i in capacity:
		if alive[i] != 0:
			ids.append(i)
	ids.sort_custom(func(a, b): return feet[a].distance_squared_to(at) < feet[b].distance_squared_to(at))
	return ids.slice(0, mini(limit, ids.size()))
