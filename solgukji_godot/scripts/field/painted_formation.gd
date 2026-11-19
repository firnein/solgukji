extends RefCounted

var feet := PackedVector2Array()
var strides := PackedFloat32Array()
var gait := PackedFloat32Array()
var opacity := PackedFloat32Array()
var alive := PackedByteArray()
var ranks := PackedInt32Array()
var strike_at := PackedFloat32Array()
var hurt_at := PackedFloat32Array()
var hurt_power := PackedFloat32Array()
var hurt_dir := PackedVector2Array()
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
	cols = 4 if cavalry or support else 5
	rows = 2 if support else(3 if cavalry or sq.tag == "궁병" else 4)

	if sq.hw < 48.0:
		cols = maxi(3, cols - 1)
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
	reform()
	_place(sq, 0.0, true)

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
		ranks[i] = next_row[col]
		next_row[col] += 1

func remove_soldier(id: int) -> void:
	if alive[id] == 0:
		return
	alive[id] = 0
	count -= 1
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
		count += 1
		reform()

		feet[i] = center - Vector2.from_angle(heading) * sq.hd0

var move_vel := Vector2.ZERO

func step(sq: Squad, dt: float) -> void:
	if dt <= 0.0:
		return
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
	var follow := 1.0 - exp(- dt * 11.0)
	var limited := not contact_limits.is_empty()      # 11/19 접촉선이 없으면 병사마다 두 번 부르던 제한 함수를 건너뛴다
	for i in capacity:
		if alive[i] == 0:
			continue
		var row := ranks[i]
		var col := i % cols
		var flank := (float(col) / maxf(1, cols - 1) * 2.0 - 1.0)
		var stagger := (0.16 if row % 2 == 0 else -0.16) * half_width / cols
		var depth := front - row * row_gap
		if cavalry:

			depth -= absf(flank) * row_gap * 0.7 * (1.0 - contact_weight)
		var offset := facing * depth + right * (flank * half_width + stagger)
		if sq.state == "flee":
			offset += right * sin(float(i) * 2.4) * (12.0 + row * 3.0)
		var goal := center + offset
		if limited:
			goal = constrain_foot(goal)
		if initial:
			feet[i] = goal
			continue
		var before := feet[i]
		feet[i] = constrain_foot(before.lerp(goal, follow)) if limited else before.lerp(goal, follow)
		var speed := feet[i].distance_to(before) / dt
		var walking := smoothstep(10.0, 90.0, speed)
		gait[i] = lerpf(gait[i], walking, 1.0 - exp(- dt * 9.0))
		strides[i] = fposmod(strides[i] + minf(speed * 0.08, 10.0 if cavalry else 8.0) * dt, TAU)
		opacity[i] = move_toward(opacity[i], 1.0, dt * 3.0)

func nearest_living(at: Vector2, limit: int) -> Array[int]:
	var ids: Array[int] = []
	for i in capacity:
		if alive[i] != 0:
			ids.append(i)
	ids.sort_custom(func(a, b): return feet[a].distance_squared_to(at) < feet[b].distance_squared_to(at))
	return ids.slice(0, mini(limit, ids.size()))
