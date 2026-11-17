extends Control

const FormationMotion = preload("res://scripts/field/painted_formation.gd")
var v
var atlas: Texture2D
var cells: Array[AtlasTexture] = []
var walk_meshes := {}
var formations := {}
var visible_soldiers: Array = []
var ratios := {}
var last_clock := -1.0
var visual_time := 0.0
var motion_dt := 0.0
var charges := {}
var rallies := {}
var fire_seas := {}
var flames := {}
var peerless := {}
var contacts: Array = []
var bodies: Array = []
var volleys: Array = []
const MAX_BODIES := 96
const MAX_CONTACTS := 48
const INK := Color("#29271f")
const PAPER := Color("#e3cfa1")
const JADE := Color("#a9e4bb")
const EMBER := Color("#ed9954")
const ALLY_MARK := Color("#8bd8ff")
const ENEMY_MARK := Color("#ff8a66")
const ALLY_CLOTH := Color("#b3dcff")
const ENEMY_CLOTH := Color("#ffc7aa")
const TAGS := ["창병", "기병", "궁병", "도적", "책사", "유생", "술사", "모사"]
const STRIDE_FRAMES := 12

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	atlas = load("res://assets/war_painting/troops_01.png")
	var cell := atlas.get_size() / 4.0
	for i in 16:
		var t := AtlasTexture.new()
		t.atlas = atlas
		t.region = Rect2(Vector2(i % 4, i / 4) * cell, cell)
		t.filter_clip = true
		cells.append(t)
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS


func _walk_mesh(cell: int, phase: int, strength: int) -> ArrayMesh:
	var key := (cell * STRIDE_FRAMES + phase) * 4 + strength
	if walk_meshes.has(key):
		return walk_meshes[key]
	var cavalry := cell % 8 == 1
	var swing := sin(TAU * phase / STRIDE_FRAMES) * strength / 3.0
	var vertices := PackedVector2Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	var region := cells[cell].region.grow(-0.75)
	for row in 7:
		for col in 7:
			var uv := Vector2(col, row) / 6.0
			var lower := smoothstep(0.56, 1.0, uv.y)
			var half := lerpf(-1.0, 1.0, smoothstep(0.31, 0.67, uv.x))
			var point := uv - Vector2(0.5, 0.97)
			point.x += swing * (0.009 * (1.0 - lower) + half * lower * (0.055 if cavalry else 0.05))
			point.y -= lower * maxf(0.0, swing * half) * (0.068 if cavalry else 0.056)
			vertices.append(point)
			uvs.append((region.position + region.size * uv) / atlas.get_size())
			if row < 6 and col < 6:
				var i := row * 7 + col
				indices.append_array([i, i + 7, i + 1, i + 1, i + 7, i + 8])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, Mesh.ARRAY_FLAG_USE_2D_VERTICES)
	walk_meshes[key] = mesh
	return mesh

func reset() -> void:
	formations.clear()
	ratios.clear()
	visible_soldiers.clear()
	bodies.clear()
	contacts.clear()
	volleys.clear()
	last_clock = -1.0
	visual_time = 0.0
	motion_dt = 0.0
	charges.clear()
	rallies.clear()
	fire_seas.clear()
	flames.clear()
	peerless.clear()

func _formation(sq: Squad) -> FormationMotion:
	var form: FormationMotion = formations.get(sq.key)
	if form == null:
		form = FormationMotion.new(sq)
		formations[sq.key] = form
	return form

func prepare_attack(source_key: String, targets: Array, kind: String) -> void:
	var sq: Squad = v.field.squads.get(source_key)
	if sq == null or targets.is_empty() or not sq.alive or sq.state == "flee":
		return
	var target: Squad = v.field.squads.get(targets[0])
	if target == null:
		return
	var form := _formation(sq)
	form.action_kind = kind
	form.action_target = target.key
	form.last_action = visual_time
	if kind == "volley" or kind == "spell":
		var flight := 0.72 if kind == "volley" else 0.6
		for key in targets:
			var dst: Squad = v.field.squads.get(key)
			if dst != null:
				volleys.append({"start": v.field.clock, "end": v.field.clock + flight,
					"from": form.center, "to": _formation(dst).center, "camp": sq.camp,
					"count": mini(form.count, 8) if kind == "volley" else 1, "kind": kind})
	else:
		var point := form.center.direction_to(_formation(target).center)
		var edge := form.center + point * sq.edge(point)
		for id in form.nearest_living(edge, form.cols):
			form.strike_at[id] = visual_time + (id % form.cols) * 0.018

func _hit_power(source: Squad, target: Squad, event: Dictionary, ultimate) -> float:
	if event.get("painted_charge", "") == "brace":
		return 0.0
	if ultimate != null:
		return 2.0 * Type2View.hit_skill_mul(source, target)
	if event.get("painted_charge", "") == "hit":
		return 1.65
	if source.cls == "ranged":
		return 0.35 if event.get("crit", false) else 0.0
	var power := Type2View.hit_power(source, target)
	if event.get("crit", false) or event.has("mn"):
		power = maxf(power, 0.85)
	return clampf(power, 0.0, 1.5)

func play_event(event: Dictionary, ultimate, updates: Array = []) -> void:
	var now: float = v.field.clock
	var source: Squad = v.field.squads.get(event.get("a", ""))
	var target: Squad = v.field.squads.get(event.get("f", ""))
	var direct := source != null and target != null and source.camp != target.camp
	var damage: bool = direct and event.get("fx", "") in ["phys", "int"] and float(event.get("n", 0)) > 0.0
	var power := _hit_power(source, target, event, ultimate) if damage else 0.0
	if damage:
		_record_contact(source, target, power, event.get("fx") == "int")
	_sync_troops(updates, source, target, power, false)
	var charge: String = event.get("painted_charge", "")
	if charge != "" and direct:
		_record_impact(source, target, now, charge == "brace")
	if source != null and event.has("peerless_bonus"):
		peerless[source.key] = {"end": now + 0.9, "bonus": event.peerless_bonus}
	if event.has("kin_by") and target != null:
		var after := float(event.kin_ratio)
		var before := after - float(event.n) / maxf(1.0, target.max)
		rallies[target.key] = {"start": now, "end": now + 1.2, "source": event.kin_by,
			"label": "한실부흥  %d%% → %d%%" % [roundi(before * 100.0), roundi(after * 100.0)]}
	if source != null and event.has("sea_duration") and not event.get("area", []).is_empty():
		var area: Dictionary = event.area[0]
		fire_seas[source.key] = {"start": now, "end": now + float(event.sea_duration),
			"center": Vector2(area.x, area.y), "radius": float(area.r) + float(event.get("sea_margin", 0.0))}
	for key in event.get("sea_targets", []):
		flames[key] = {"start": now, "end": now + 0.65, "size": 0.75}
	if event.has("sea_end"):
		fire_seas.erase(event.sea_end)
	if ultimate != null and direct and source.key == ultimate.get("a", ""):
		if source.cid == "c195" and event.get("fx") == "int":
			flames[target.key] = {"start": now, "end": now + 0.85, "size": 1.5}
		elif source.cid == "c181" and event.get("fx") == "phys":
			_record_impact(source, target, now, false)

func sync_quiet(updates: Array) -> void:
	_sync_troops(updates, null, null, 0.0, true)

func has_unsettled_casualties() -> bool:
	return bodies.any(func(body): return visual_time < float(body.start) + float(body.duration))

func _sync_troops(updates: Array, source: Squad, target: Squad, power: float, quiet: bool) -> void:
	for update in updates:
		var sq: Squad = v.field.squads.get(update.key)
		if sq == null:
			continue
		var form := _formation(sq)
		form.ratio = clampf(float(update.troops) / maxf(1.0, sq.max), 0.0, 1.0)
		ratios[sq.key] = form.ratio
		var wanted := ceili(form.ratio * form.capacity)
		if wanted >= form.count:
			form.restore_soldiers(wanted, sq)
			continue
		var direction := Vector2.from_angle(form.heading)
		if source != null and source.camp != sq.camp:
			direction = _formation(source).center.direction_to(form.center)
		var impact_at := form.center - direction * sq.edge(direction)
		var victims := form.nearest_living(impact_at, form.count - wanted)
		var force := power if sq == target else 0.0
		var launch_count := mini(victims.size(), ceili(force * 2.0))
		for n in victims.size():
			var id: int = victims[n]
			if not quiet:
				_spawn_body(sq, form, id, direction, force if n < launch_count else 0.0, n)
			form.remove_soldier(id)

func _spawn_body(sq: Squad, form: FormationMotion, id: int, direction: Vector2, power: float, order: int) -> void:
	var flying := power >= 0.75
	var seed := float(id * 13 + form.serial * 7 + int(sq.row.slot) * 3)
	var spread := sin(seed * 1.7) * 0.28
	var travel := (60.0 + power * 36.0) if flying else 9.0
	var duration := 0.56 + power * 0.08 if flying else 0.28
	var facing := 1.0 if sin(seed) > 0.0 else -1.0
	bodies.append({"at": form.feet[id], "direction": direction.rotated(spread),
		"start": visual_time + minf(0.12, order * 0.027), "duration": duration,
		"distance": travel, "height": (40.0 + power * 30.0) if flying else 0.0,
		"turn": facing * (1.25 + power * 0.24), "h": _figure_height(sq, form),
		"cell": maxi(0, TAGS.find(sq.tag)) + (0 if sq.camp == "A" else 8),
		"flying": flying, "end": visual_time + duration + 2.6, "mirror": (not form.facing_right if sq.camp == "A" else form.facing_right)})
	if bodies.size() > MAX_BODIES:
		bodies.pop_front()

func _record_contact(source: Squad, target: Squad, power: float, magic: bool) -> void:
	var from := _formation(source)
	var form := _formation(target)
	var direction := from.center.direction_to(form.center)
	if direction.is_zero_approx():
		direction = Vector2.from_angle(from.heading)
	var at := form.center - direction * target.edge(direction)
	var ids := form.nearest_living(at, mini(form.cols, 2 + floori(power)))
	form.serial += 1
	var received := 0
	for id in ids:
		if visual_time - form.hurt_at[id] < 0.14:
			continue
		var offset := received * 0.018
		form.hurt_at[id] = visual_time + offset
		form.hurt_power[id] = power
		form.hurt_dir[id] = direction
		contacts.append({"start": visual_time + offset, "end": visual_time + 0.28 + offset,
			"at": form.feet[id], "key": target.key, "id": id, "direction": direction,
			"power": power, "magic": magic, "ranged": source.cls == "ranged"})
		received += 1
		if contacts.size() > MAX_CONTACTS:
			contacts.pop_front()

	if source.cls != "ranged":
		var front := from.center + direction * source.edge(direction)
		for id in from.nearest_living(front, from.cols):
			from.strike_at[id] = visual_time - 0.105 + (id % from.cols) * 0.012
		from.action_target = target.key
		from.action_kind = "melee"
		from.last_action = visual_time

func _record_impact(source: Squad, target: Squad, now: float, brace: bool) -> void:
	var direction := _formation(source).center.direction_to(_formation(target).center)
	if direction.is_zero_approx():
		direction = source.fwd
	charges[target.key] = {"start": now, "end": now + 0.65, "direction": direction,
		"at": _formation(target).center - direction * target.edge(direction), "brace": brace}

func _process(dt: float) -> void:
	if not is_visible_in_tree() or v == null or v.field == null:
		return
	var elapsed := 0.0 if last_clock < 0 else clampf(float(v.field.clock) - last_clock, 0.0, 0.25)

	motion_dt = minf(minf(dt, elapsed), 0.05) if elapsed > 0.0 else 0.0
	visual_time += motion_dt
	last_clock = v.field.clock
	for effects: Dictionary in [charges, rallies, fire_seas, flames, peerless]:
		for key in effects.keys():
			if last_clock >= effects[key].end:
				effects.erase(key)
	bodies = bodies.filter(func(b): return visual_time < b.end)
	contacts = contacts.filter(func(h): return visual_time < h.end)
	volleys = volleys.filter(func(shot): return last_clock < shot.end)
	for sq: Squad in v.field.order:
		if sq.state == "gone":
			formations.erase(sq.key)
			continue
		var form := _formation(sq)
		form.step(sq, motion_dt)
		ratios[sq.key] = form.ratio
	queue_redraw()

func squad_at(screen: Vector2) -> Squad:
	var local := get_global_transform_with_canvas().affine_inverse() * screen
	var best: Squad = null
	var best_distance := INF
	for figure in visible_soldiers:
		var p: Vector2 = figure.p - Vector2(0.0, figure.h * 0.42)
		var distance := p.distance_squared_to(local)
		if distance <= pow(maxf(10.0, figure.h * 0.45), 2) and distance < best_distance:
			best_distance = distance
			best = figure.sq
	return best

func _figure_height(sq: Squad, form: FormationMotion) -> float:
	var scale: float = v.depth_scale(form.center) * v._scale
	var nominal := (61.0 if form.cavalry else 51.0) * scale
	var horizontal := 2.0 * form.half_width / maxf(1, form.cols - 1) * scale
	return clampf(minf(nominal, horizontal / 0.58), 12.0, 46.0)

func _draw() -> void:
	visible_soldiers.clear()
	if v == null or v.field == null or cells.is_empty():
		return
	_draw_fire_seas()
	_draw_bodies(false)
	for sq: Squad in v.field.order:
		if sq.state != "gone" and sq.fade > 0.01:
			var form: FormationMotion = formations.get(sq.key)
			if form != null:
				_draw_formation_mark(sq, form)
				_collect_figures(sq, form)
	visible_soldiers.sort_custom(func(a, b): return a.p.y < b.p.y)
	v.drawn_figs = visible_soldiers.size() + bodies.size()
	for figure in visible_soldiers:
		_draw_soldier(figure)
	_draw_contacts()
	_draw_bodies(true)
	for sq: Squad in v.field.order:
		if sq.state != "gone" and sq.fade > 0.01:
			_draw_status(sq)
	_draw_volleys()
	_draw_links()
	_draw_mythic_actions()

func _collect_figures(sq: Squad, form: FormationMotion) -> void:
	var h := _figure_height(sq, form)
	var cell := maxi(0, TAGS.find(sq.tag)) + (0 if sq.camp == "A" else 8)
	var facing := Vector2.from_angle(form.heading)
	var direction := facing
	var target: Squad = v.field.squads.get(form.action_target)
	if form.contact and sq.engaged != null:
		target = sq.engaged
	if target != null and target.alive and sq.state != "flee":
		direction = form.center.direction_to(_formation(target).center)
	var axis: Vector2 = (v.map(form.center + direction * 20.0) - v.map(form.center)).normalized()

	if axis.x > 0.3:
		form.facing_right = true
	elif axis.x < -0.3:
		form.facing_right = false
	var mirror := not form.facing_right if sq.camp == "A" else form.facing_right

	var attacking := form.action_kind == "melee" and visual_time - form.last_action < 0.55
	var eligible := (form.contact or attacking) and sq.state != "flee" and target != null and target.alive
	var front_ids: Array = form.nearest_living(form.center + direction * sq.edge(direction), form.cols) if eligible else[]
	for id in form.capacity:
		if form.alive[id] == 0:
			continue
		var p: Vector2 = v.map(form.feet[id])
		var tilt := 0.0
		var gait: float = form.gait[id]
		var stride: float = form.strides[id]
		var hit := 0.0
		var age := visual_time - form.strike_at[id]
		var windup := smoothstep(0.0, 0.09, age) * (1.0 - smoothstep(0.09, 0.13, age))
		var thrust := smoothstep(0.09, 0.13, age) * (1.0 - smoothstep(0.18, 0.4, age))
		if sq.state != "flee":
			if front_ids.has(id):

				var guard := sin(visual_time * 4.3 + id * 2.4 + float(sq.row.slot)) * form.contact_weight
				p += axis * guard * 0.55 * (1.0 - gait)
				tilt += axis.x * guard * 0.022
				p += axis * (thrust * 3.2 - windup * 1.2)
				tilt += axis.x * (thrust * 0.14 - windup * 0.065)
				gait *= 0.35
			elif form.action_kind in ["volley", "spell"]:
				var bow_age := visual_time - form.last_action - (id / form.cols) * 0.025
				var bow := smoothstep(0.0, 0.1, bow_age) * (1.0 - smoothstep(0.15, 0.32, bow_age))
				tilt -= axis.x * bow * 0.065
		var hurt_age := visual_time - form.hurt_at[id]
		if hurt_age >= 0.0 and hurt_age < 0.38:
			var hurt_axis: Vector2 = (v.map(form.feet[id] + form.hurt_dir[id] * 16.0) - p).normalized()
			var recoil := smoothstep(0.0, 0.055, hurt_age) * (1.0 - smoothstep(0.11, 0.38, hurt_age))
			p += hurt_axis * recoil * (2.0 + form.hurt_power[id] * 2.4)
			tilt += hurt_axis.x * recoil * (0.09 + form.hurt_power[id] * 0.06)
			hit = 1.0 - smoothstep(0.025, 0.14, hurt_age)
			gait *= 1.0 - recoil
		tilt += sin(stride) * gait * (0.035 if form.cavalry else 0.012)
		visible_soldiers.append({"p": p, "h": h, "cell": cell, "fade": sq.fade * form.opacity[id],
			"tilt": tilt, "gait": gait, "stride": stride, "hurt": hit, "mirror": mirror, "sq": sq})

func _draw_formation_mark(sq: Squad, form: FormationMotion) -> void:
	if form.count == 0:
		return
	var facing := Vector2.from_angle(form.heading)
	var right := Vector2(- facing.y, facing.x)
	var front := form.center + facing * maxf(sq.hd0 * form.ratio, RtBattle.HD_MIN) * 0.86
	var last_rank := 0
	for id in form.capacity:
		if form.alive[id] != 0:
			last_rank = maxi(last_rank, form.ranks[id])

	var back := front - facing * maxf(12.0, form.row_gap * last_rank)
	var rim := PackedVector2Array([v.map(back - right * (form.half_width + 7.0)),
		v.map(front - right * (form.half_width + 7.0)), v.map(front + right * (form.half_width + 7.0)),
		v.map(back + right * (form.half_width + 7.0))])
	var color := ALLY_MARK if sq.camp == "A" else ENEMY_MARK
	draw_colored_polygon(rim, Color(color, 0.075 * sq.fade))
	draw_polyline(rim, Color(color, 0.38 * sq.fade), 1.1, true)

	for id in form.capacity:
		if form.alive[id] == 0 or form.ranks[id] != 0:
			continue
		var p: Vector2 = v.map(form.feet[id]) + Vector2(0, 1)
		var half := maxf(2.0, _figure_height(sq, form) * 0.17)
		var shape := PackedVector2Array([p + Vector2(- half, 0), p + Vector2(half, 0)])
		if sq.camp != "A":
			shape = PackedVector2Array([p + Vector2(- half, -1), p + Vector2(0, 1.5), p + Vector2(half, -1)])
		draw_polyline(shape, Color(INK, 0.7 * sq.fade), 3.0, true)
		draw_polyline(shape, Color(color, 0.8 * sq.fade), 1.5, true)
	_draw_dust(sq, form.half_width * 2.0, form)

func _draw_soldier(f: Dictionary) -> void:
	var p: Vector2 = f.p
	var h: float = f.h
	var gait: float = f.gait
	var lift := pow(absf(sin(f.stride)), 3.0) * gait * h * (0.027 if f.cell % 8 == 1 else 0.009)
	draw_set_transform(p, 0.0, Vector2(1.0, 0.32))
	draw_circle(Vector2.ZERO, h * 0.19, Color(0.1, 0.08, 0.05, 0.25 * f.fade))
	draw_set_transform(Vector2.ZERO)
	var cloth := ALLY_CLOTH if f.cell < 8 else ENEMY_CLOTH
	var tint := Color(cloth.lerp(Color("#fff3df"), f.hurt * 0.75), f.fade)
	var stretch := Vector2(-1.0 if f.mirror else 1.0, 1.0)
	var origin := p - Vector2(0.0, lift)
	var strength := clampi(roundi(gait * 3.0), 0, 3)
	var phase := roundi(float(f.stride) * STRIDE_FRAMES / TAU) % STRIDE_FRAMES
	if strength > 0 and phase != 0 and phase != STRIDE_FRAMES / 2:
		draw_mesh(_walk_mesh(f.cell, phase, strength), atlas, Transform2D(f.tilt, stretch * h, 0.0, origin), tint)
	else:
		draw_set_transform(origin, f.tilt, stretch)
		draw_texture_rect(cells[f.cell], Rect2(- h * 0.5, - h * 0.97, h, h), false, tint)
		draw_set_transform(Vector2.ZERO)

func _draw_bodies(airborne: bool) -> void:
	for body in bodies:
		var age := maxf(0.0, visual_time - float(body.start))
		var t := clampf(age / float(body.duration), 0.0, 1.0)
		var flying: bool = body.flying and t < 1.0
		if flying != airborne:
			continue
		var ground: Vector2 = body.at + body.direction * float(body.distance) * (1.0 - pow(1.0 - t, 1.8))
		var p: Vector2 = v.map(ground)
		var scale: float = v._scale * v.depth_scale(ground)
		var height := 4.0 * t * (1.0 - t) * float(body.height) * scale
		var h: float = body.h
		var alpha := 1.0 - smoothstep(float(body.duration) + 1.2, float(body.duration) + 2.6, age)
		if flying:
			draw_set_transform(p, 0, Vector2(1, 0.3))
			draw_circle(Vector2.ZERO, h * 0.19, Color(0.08, 0.06, 0.04, 0.18 * alpha))
			draw_set_transform(Vector2.ZERO)
		var tumble := smoothstep(0.0, 1.0, t)
		var turn := float(body.turn) * tumble
		var squash := lerpf(1.0, 0.4, smoothstep(0.78, 1.0, t))
		var cloth := ALLY_CLOTH if body.cell < 8 else ENEMY_CLOTH
		var tint := Color(cloth.darkened(0.25 * tumble), alpha * (0.7 if t >= 1.0 else 1.0))
		draw_set_transform(p - Vector2(0, height + h * 0.3), turn, Vector2(-1.0 if body.mirror else 1.0, squash))
		draw_texture_rect(cells[body.cell], Rect2(- h * 0.5, - h * 0.62, h, h), false, tint)
		draw_set_transform(Vector2.ZERO)
		var landing := age - float(body.duration)
		if body.flying and landing >= 0.0 and landing < 0.27:
			var dust := landing / 0.27
			draw_set_transform(p, 0, Vector2(1.0, 0.42))
			draw_circle(Vector2.ZERO, 4.0 + dust * h * 0.5, Color(PAPER, (1.0 - dust) * 0.36))
			draw_set_transform(Vector2.ZERO)

func _draw_contacts() -> void:
	for hit in contacts:
		var age := visual_time - float(hit.start)
		if age < 0.0:
			continue
		var at: Vector2 = hit.at
		var form: FormationMotion = formations.get(hit.key)
		if form != null and form.alive[hit.id] != 0:
			at = form.feet[hit.id]
		var p: Vector2 = v.map(at) - Vector2(0, 7.0 * v.depth_scale(at))
		var axis: Vector2 = (v.map(at + hit.direction * 16.0) - v.map(at)).normalized()
		var side := Vector2(- axis.y, axis.x)
		var flash := 1.0 - smoothstep(0.025, 0.13, age)
		var power := 1.0 + float(hit.power) * 0.45
		var color := JADE if hit.magic else PAPER
		if flash > 0.0:
			if not hit.ranged:
				draw_line(p - side * 5.0 * power, p + side * 6.0 * power, Color(color, flash * 0.85), 2.0, true)
			draw_circle(p, 2.0 * power, Color(color, flash), true, -1.0, true)
		var fade := 1.0 - smoothstep(0.04, 0.25, age)
		for i in (4 if hit.power > 1.0 else 2):
			var ray := axis.rotated((float(i) - 1.5) * 0.75)
			var travel := age * 28.0 * power
			draw_line(p + ray * travel, p + ray * (travel + 3.0 * power), Color(EMBER, fade * 0.9), 1.2, true)

func _draw_volleys() -> void:
	for shot in volleys:
		var start: Vector2 = shot.from
		var end: Vector2 = shot.to
		for id in shot.count:
			var delay := float(id) * 0.008
			var t := clampf((last_clock - float(shot.start) - 0.12 - delay) / maxf(0.1, float(shot.end) - float(shot.start) - 0.12 - delay), 0.0, 1.0)
			if t <= 0.0:
				continue
			var spread := Vector2(0.0, (float(id) - float(shot.count - 1) * 0.5) * 8.0)
			var world := start.lerp(end, t) + spread
			var prev_t := maxf(0.0, t - 0.045)
			var height := 18.0 + start.distance_to(end) * 0.025
			var p: Vector2 = v.map(world) - Vector2(0, 5.0 + sin(t * PI) * height * v.depth_scale(world))
			var prev: Vector2 = v.map(start.lerp(end, prev_t) + spread) - Vector2(0, 5.0 + sin(prev_t * PI) * height * v.depth_scale(world))
			var color := PAPER if shot.kind == "volley" else EMBER
			draw_line(prev, p, Color(INK, 0.8), 2.0, true)
			draw_line(prev, p, color, 1.0, true)

func _draw_fire_seas() -> void:
	for sea: Dictionary in fire_seas.values():
		var age := maxf(0.0, last_clock - float(sea.start))
		var fade := clampf(float(sea.end) - last_clock, 0.0, 1.0)
		var center: Vector2 = sea.center
		var radius := float(sea.radius) * lerpf(0.6, 1.0, smoothstep(0.0, 0.42, age))
		var rim := PackedVector2Array()
		for i in 32:
			rim.append(v.map(center + Vector2.from_angle(TAU * i / 32.0) * radius))
		draw_colored_polygon(rim, Color(0.46, 0.18, 0.08, 0.34 * fade))
		rim.append(rim[0])
		draw_polyline(rim, Color(EMBER, 0.58 * fade), 1.8, true)
		for i in 12:
			var spot := center + Vector2.from_angle(TAU * i / 12.0) * radius * (0.71 + (i % 3) * 0.1)
			var at: Vector2 = v.map(spot)
			var flicker := 0.5 + 0.5 * sin(last_clock * 8.0 + float(i) * 2.4)
			var h: float = (13.0 + flicker * 9.0) * v.depth_scale(spot)
			v._spr_at(self, "flame_02", at + Vector2(0, - h * 0.32), h, Color(EMBER, (0.26 + flicker * 0.32) * fade), 0.1, Vector2(0.7, 1.0))

func _draw_mythic_actions() -> void:
	for sea: Dictionary in fire_seas.values():
		var age := maxf(0.0, last_clock - float(sea.start))
		if age < 1.45:
			_action_label(v.map(sea.center), "적벽 불바다", EMBER, clampf((1.45 - age) * 3.0, 0.0, 1.0))
	for key in peerless:
		var sq: Squad = v.field.squads.get(key)
		if sq != null and sq.alive:
			var mark: Dictionary = peerless[key]
			var at: Vector2 = v.map(sq.pos - sq.fwd * sq.hd() * 0.65)
			_action_label(at + Vector2(0, -24), "무쌍  공격 +%d%%" % mark.bonus, PAPER, clampf((float(mark.end) - last_clock) * 4.0, 0.0, 1.0))
	for hit: Dictionary in charges.values():
		var t := clampf((last_clock - float(hit.start)) / 0.65, 0.0, 1.0)
		var axis: Vector2 = hit.direction
		var side := axis.orthogonal()
		var center: Vector2 = hit.at
		var accent := PAPER if hit.brace else EMBER
		var arc := PackedVector2Array()
		for i in range(-4, 5):
			var point := center + side * float(i) * (5.0 + t * 4.0) + axis * (1.0 - absf(float(i)) / 4.0) * t * 22.0
			arc.append(v.map(point))
		draw_polyline(arc, Color(accent, (1.0 - t) * 0.8), 2.2, true)
		if hit.brace:
			_action_label(v.map(center), "창벽", PAPER, 1.0 - t)
	for key in rallies:
		var target: Squad = v.field.squads.get(key)
		if target == null or not target.alive:
			continue
		var rally: Dictionary = rallies[key]
		var t := clampf((last_clock - float(rally.start)) / 1.2, 0.0, 1.0)
		var dst: Vector2 = v.map(target.pos - target.fwd * target.hd() * 0.65)
		var source: Squad = v.field.squads.get(rally.source)
		if source != null and source != target and t < 0.43:
			var start: Vector2 = v.map(source.pos - source.fwd * source.hd() * 0.65)
			var progress := minf(1.0, t * 6.0)
			draw_line(start.lerp(dst, maxf(0.0, progress - 0.3)), start.lerp(dst, progress), Color(JADE, 0.8), 2.0, true)
		draw_arc(dst, 9.0 + t * 13.0, 0.0, TAU, 20, Color(JADE, (1.0 - t) * 0.65), 1.5, true)
		_action_label(dst + Vector2(0, -23), rally.label, JADE, clampf((1.0 - t) * 3.0, 0.0, 1.0))
	for key in flames:
		var target: Squad = v.field.squads.get(key)
		if target == null or target.fade <= 0.01:
			continue
		var flame: Dictionary = flames[key]
		var t := clampf((last_clock - float(flame.start)) / (float(flame.end) - float(flame.start)), 0.0, 1.0)
		for i in range(-1, 2):
			var at: Vector2 = v.map(target.pos + target.right() * float(i) * target.hw * 0.65)
			var h: float = (12.0 + sin(t * PI) * 23.0) * float(flame.size) * v.depth_scale(target.pos)
			v._spr_at(self, "flame_02", at - Vector2(0, h * 0.5), h, Color(EMBER, (1.0 - t) * 0.9), 0.0, Vector2(0.75, 1.0))

func _action_label(at: Vector2, label: String, color: Color, alpha: float) -> void:
	var width := DB.font_bold.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
	var pos := at - Vector2(width * 0.5, 7)
	draw_string_outline(DB.font_bold, pos, label, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, 4, Color(INK, alpha))
	draw_string(DB.font_bold, pos, label, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(color, alpha))

func _draw_links() -> void:
	if v.view == null or v.view.hud == null:
		return
	for e in v.view.hud._deck_links:
		var a: Squad = v.field.squads.get(e.a)
		var b: Squad = v.field.squads.get(e.b)
		if a == null or b == null or not a.alive or not b.alive:
			continue
		var t := clampf((float(v.view.clock) - float(e.t)) / 0.85, 0.0, 1.0)
		for j in 3:
			var u := clampf(t * 1.3 - j * 0.06, 0.0, 1.0)
			var world: Vector2 = a.pos.lerp(b.pos, u)
			var at: Vector2 = v.map(world) + Vector2(0, -sin(u * PI) * 15.0 * v.depth_scale(world))
			draw_circle(at, 2.5 - j * 0.5, Color(e.col, (1.0 - t) * 0.85))

func _draw_dust(sq: Squad, width: float, form: FormationMotion) -> void:
	if not sq.contact and not sq.moving:
		return
	for j in 3:
		var phase := fposmod(v.field.clock * 0.8 + j * 0.33, 1.0)
		var at: Vector2 = form.center + sq.right() * (j - 1) * width * 0.3
		if sq.contact:
			at += sq.fwd * sq.hd()
		else:
			at -= sq.fwd * sq.hd()
		draw_circle(v.map(at), (4.0 + phase * 7.0) * v.depth_scale(at), Color(0.72, 0.64, 0.46, sin(phase * PI) * 0.13 * sq.fade))

func _draw_status(sq: Squad) -> void:
	if not sq.alive:
		return
	var p: Vector2 = v.map(sq.pos)
	var perspective: float = v.depth_scale(sq.pos)
	if sq.statuses.has("burn"):
		for j in 4:
			var phase: float = v.field.clock * 5.0 + j * 1.7
			var base: Vector2 = v.map(sq.pos + sq.right() * (j - 1.5) * sq.hw * 0.5)
			var h := (13.0 + 5.0 * sin(phase)) * perspective
			v._spr_at(self, "flame_02", base + Vector2(0, -h * 0.45), h * 2.0, Color(1.0, 0.62, 0.20, 0.85), sin(phase) * 0.12, Vector2(0.65, 1.0))
	if sq.statuses.has("cut_def") or sq.statuses.has("cut_res"):
		var q := p + Vector2(14, -22) * perspective
		draw_set_transform(q, 0, Vector2.ONE * perspective)
		q = Vector2.ZERO
		var shield := PackedVector2Array([q + Vector2(-6, -7), q + Vector2(6, -7), q + Vector2(5, 2), q + Vector2(0, 7), q + Vector2(-5, 2), q + Vector2(-6, -7)])
		draw_polyline(shield, Color("#e6bd79"), 1.5, true)
		draw_polyline(PackedVector2Array([q + Vector2(1, -7), q + Vector2(-2, -1), q + Vector2(2, 1), q + Vector2(0, 7)]), INK, 2.5, true)
		draw_set_transform(Vector2.ZERO)
	if sq.statuses.has("flood"):
		for j in 2:
			draw_arc(p + Vector2(0, j * 3) * perspective, (13 + j * 2) * perspective, 0.1, PI - 0.1, 12, Color(0.35, 0.65, 0.75, 0.7), 1.3, true)
	if sq.statuses.has("confuse"):
		draw_arc(p + Vector2(0, -17) * perspective, 7 * perspective, v.field.clock, v.field.clock + PI * 1.6, 12, Color("#be9aca"), 1.7, true)
