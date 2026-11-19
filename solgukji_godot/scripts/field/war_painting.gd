extends Control

const FormationMotion = preload("res://scripts/field/painted_formation.gd")
var v
var atlas: Texture2D
var cells: Array[AtlasTexture] = []
var walk_meshes := {}
var formations := {}
var visible_soldiers: Array = []      # 점검용 사전 목록 (keep_dicts 일 때만 채운다) —— 그리기는 아래 묶음 배열을 쓴다
## 11/19 프레임: 병사마다 키 11개짜리 사전을 만들고 람다로 정렬하던 것이 삽화 그리기의 절반이었다 ——
## 인형 값은 묶음 배열 한 줄(FIG_W 칸)에, 깊이 순서는 정수 키(화면 y · 번호) 정렬로. 그리는 모양 · 순서는 그대로
const FIG_W := 10              # x, y, 키, 칸, 투명, 기울기, 걸음 세기, 보폭, 피격, 좌우 뒤집기
var _figs := PackedFloat32Array()
var _fig_sq: Array = []
var _fig_keys := PackedInt64Array()
var figure_count := 0          # 지난 그리기의 인형 수
static var keep_dicts := false # 점검용 —— visible_soldiers 사전 목록도 채운다 (tests/motion5_replay)
var _scr := {}                 # 부대 key -> 이번 그리기의 발 화면 좌표 (수집이 채우고 표식이 다시 쓴다)
# 투영 캐시 —— 그리기 한 번 동안 같은 값 (v.map 은 부를 때마다 화풍 확인 · depth_scale 을 다시 불렀다)
var _po := Vector2.ZERO
var _pc := Vector2.ZERO
var _ps := 1.0
var _pt := 1.0
var ratios := {}
var last_clock := -1.0
var visual_time := 0.0
var motion_dt := 0.0
var _cl_tick := 0
var _cl_i := 0
var paint_updates := 0       # 11/19 실제 삽화 갱신 횟수 (점검 motion5_replay 가 초당으로 잰다)
var _skip_dt := 0.0          # 11/18 부하 2단계부터 30Hz —— 건너뛴 프레임의 시간을 모아 다음 갱신에 넘긴다
var charges := {}
var rallies := {}
var fire_seas := {}
var flames := {}
var peerless := {}
var contacts: Array = []
var bodies: Array = []
var volleys: Array = []
var ults: Array = []          # 11/17 고유기 이펙트 —— 삽화 화면에서는 type2 의 2D 연출이 꺼져 있어 여기서 그린다
const MAX_ULTS := 6
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
static var batch_rendering := true
var batch: Node2D
var top_effects: Node2D
var glow_effects: Node2D
var _glow_q: Array = []
const GLOW_SPR := ["flame_02", "flame_03", "flame_04", "fire_01", "fire_02", "spark_01", "spark_04", "light_02", "star_06",
	"magic_01", "magic_03", "magic_05", "slash_01", "slash_02", "slash_03", "twirl_01", "circle_03", "circle_05", "trace_01", "muzzle_02"]
const GLOW_BOOST := 1.6        # 더하기 합성에서 그림 자체가 어두워(평균 회색 0.3~0.5) 색을 조금 밝게

class TopEffects extends Node2D:
	var painter
	func _draw() -> void:
		var t0 := Time.get_ticks_usec()
		painter._draw_overlay(self)
		if painter.v != null and painter.v.field != null:
			painter.v.field.pt("삽화 위층", t0)

## 11/17 빛나는 효과 층 —— kenney 효과 그림은 회색 + 낮은 알파(더하기 합성용)라 보통 합성으로는 황토 땅에 어두운 얼룩만 남았다
## (불꽃 · 화상 · 불바다 · 낙뢰 · 검기가 안 보였다). 그런 그림은 _spr 가 모아 두고 이 층이 더하기로 그린다
class GlowEffects extends Node2D:
	var painter
	func _draw() -> void:
		for g in painter._glow_q:
			painter.v._spr_at(self, g[0], g[1], g[2], g[3], g[4], g[5])
		painter._glow_q.clear()

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
	batch = preload("res://scripts/field/painted_batch.gd").new()
	batch.atlas = atlas
	batch.visible = batch_rendering
	add_child(batch)
	top_effects = TopEffects.new()
	top_effects.painter = self
	top_effects.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR      # 11/17 효과 스프라이트(kenney)는 밉맵이 없다 —— 부모의 밉맵 필터를 물려받으면 안 그려졌다
	add_child(top_effects)
	glow_effects = GlowEffects.new()
	glow_effects.painter = self
	glow_effects.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	var add := CanvasItemMaterial.new()
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	glow_effects.material = add
	add_child(glow_effects)


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
	if batch != null:
		batch.update_figures([], ALLY_CLOTH, ENEMY_CLOTH)
	formations.clear()
	ratios.clear()
	visible_soldiers.clear()
	figure_count = 0
	_fig_sq.clear()
	_fig_keys.clear()
	_scr.clear()
	bodies.clear()
	contacts.clear()
	volleys.clear()
	ults.clear()
	_glow_q.clear()
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
				var count := mini(form.count, 8) if kind == "volley" else 3      # 11/17 책략 평타는 구슬 셋 (하나는 안 보였다 —— 「후열 주유가 무기력해 보인다」)
				if count <= 0:
					continue
				volleys.append({"start": v.field.clock, "end": v.field.clock + flight + 0.12 + (count - 1) * 0.025,
					"flight": flight,
					"from": form.center, "to": _formation(dst).center, "camp": sq.camp,
					"count": count, "kind": kind, "tag": sq.tag})
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
	# 11/18 모바일 19fps: 삽화(인형 위치 · 수집 · 정렬 · 묶음 버퍼)가 부하 조절 단계를 따르지 않고 늘 60Hz 로 돌아
	# 단계가 끝까지 올라가도 줄어드는 것이 없었다 → 2단계부터 갱신 · 그리기를 두 프레임에 한 번 (사이 시간은 모아 넘긴다)
	# 11/19 홀짝 프레임 → 실제 경과 시간 30Hz (Type2View.gate) —— 느린 기기에서 반으로 또 줄이지 않는다
	var lv := int(v.load_lv) if v.get("load_lv") != null else 0
	if lv >= 2 and v.has_method("gate") and not v.gate("paint", dt, 1.0 / 30.0):
		_skip_dt += dt
		return
	dt += _skip_dt
	_skip_dt = 0.0
	paint_updates += 1
	var t0 := Time.get_ticks_usec()
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
	ults = ults.filter(func(u): return last_clock < float(u.end) and last_clock >= float(u.start) - 5.0)
	_cl_tick += 1
	_cl_i = 0
	for sq: Squad in v.field.order:
		if sq.state == "gone":
			formations.erase(sq.key)
			continue
		var form := _formation(sq)
		# 11/19 접촉선은 부대 수 제곱 계산 —— 부대마다 엇갈려 네 번에 한 번만 다시 잰다 (선은 천천히 움직인다. 화면 전용 —— 판정과 무관)
		_cl_i += 1
		if not batch_rendering:
			form.contact_limits = []
		elif (_cl_tick + _cl_i) % 4 == 0 or not form.limits_ready:
			form.contact_limits = _contact_limits(sq)
			form.limits_ready = true
		form.step(sq, motion_dt)
		ratios[sq.key] = form.ratio
	v.field.pt("삽화 갱신", t0)
	queue_redraw()
	if top_effects != null:
		top_effects.queue_redraw()
	if glow_effects != null:
		glow_effects.queue_redraw()

func squad_at(screen: Vector2) -> Squad:
	var local := get_global_transform_with_canvas().affine_inverse() * screen
	var best: Squad = null
	var best_distance := INF
	for i in figure_count:
		var b := i * FIG_W
		var h := _figs[b + 2]
		var p := Vector2(_figs[b], _figs[b + 1] - h * 0.42)
		var distance := p.distance_squared_to(local)
		if distance <= pow(maxf(10.0, h * 0.45), 2) and distance < best_distance:
			best_distance = distance
			best = _fig_sq[i]
	return best

func _proj_begin() -> void:
	_po = v.size * v._painting_origin
	_pc = v._center + v._jit
	_ps = v._scale
	_pt = Type2View.PAINT_TILT * v._painting_stretch

## v.map 과 같은 식 (삽화 투영) —— _proj_begin 뒤에만
func _pm(p: Vector2) -> Vector2:
	var d := p - _pc
	return _po + Vector2(d.y, -d.x * _pt) * (_ps / maxf(0.35, 1.0 + d.x * Type2View.PAINT_PERSPECTIVE))

## v.depth_scale(p) * v._scale 과 같다
func _pk(p: Vector2) -> float:
	return _ps / maxf(0.35, 1.0 + (p.x - _pc.x) * Type2View.PAINT_PERSPECTIVE)

func _figure_height(sq: Squad, form: FormationMotion) -> float:
	var scale: float = _pk(form.center)
	var nominal := (61.0 if form.cavalry else 51.0) * scale
	var horizontal := 2.0 * form.half_width / maxf(1, form.cols - 1) * scale
	return clampf(minf(nominal, horizontal / 0.58), 12.0, 46.0)

func _contact_limits(sq: Squad) -> Array:
	var limits := []
	if sq.state == "flee" or not sq.alive:
		return limits
	for other: Squad in v.field.order:
		if not other.alive or other.camp == sq.camp or other.state == "flee":
			continue
		var delta := other.pos - sq.pos
		if delta.length_squared() > pow(sq.hw + sq.hd() + other.hw + other.hd() + 30.0, 2):
			continue
		var gap := -INF
		var normal := Vector2.ZERO
		for axis: Vector2 in [sq.fwd, sq.right(), other.fwd, other.right()]:
			if delta.dot(axis) < 0.0:
				axis = -axis
			var separation := delta.dot(axis) - sq.edge(axis) - other.edge(axis)
			if separation > gap:
				gap = separation
				normal = axis
		if gap > RtBattle.TOUCH + 4.0 or normal == Vector2.ZERO:
			continue
		var own_edge := sq.pos.dot(normal) + sq.edge(normal)
		var foe_edge := other.pos.dot(normal) - other.edge(normal)
		limits.append({"normal": normal, "edge": (own_edge + foe_edge) * 0.5 - 8.0})
	return limits

func _draw() -> void:
	visible_soldiers.clear()
	if v == null or v.field == null or cells.is_empty():
		return
	var t0 := Time.get_ticks_usec()
	_proj_begin()
	_draw_fire_seas()
	_draw_bodies(false)
	var tq: int = v.field.pt("삽화·바닥", t0)
	figure_count = 0
	_fig_sq.clear()
	_fig_keys.clear()
	for sq: Squad in v.field.order:
		if sq.state != "gone" and sq.fade > 0.01:
			var form: FormationMotion = formations.get(sq.key)
			if form != null:
				_collect_figures(sq, form)
	tq = v.field.pt("삽화·수집", tq)
	_mk_pts.clear()
	_mk_cols.clear()
	_mk_idx.clear()
	_mk_rim.clear()
	_mk_rim_c.clear()
	_mk_ln.clear()
	_mk_ink.clear()
	_mk_lc.clear()
	for sq: Squad in v.field.order:
		if sq.state != "gone" and sq.fade > 0.01:
			var form: FormationMotion = formations.get(sq.key)
			if form != null:
				if batch_rendering:
					_mark_batch(sq, form)
				else:
					_draw_formation_mark(sq, form)
	if not _mk_idx.is_empty():      # 부대 바닥 면 · 먼지 —— 삼각형 묶음 한 번
		RenderingServer.canvas_item_add_triangle_array(get_canvas_item(), _mk_idx, _mk_pts, _mk_cols)
	var mk_aa: bool = v.get("load_lv") == null or int(v.load_lv) < 2      # 11/18 부하 2단계부터 표식 선의 안티에일리어싱을 끈다
	if not _mk_rim.is_empty():
		draw_multiline_colors(_mk_rim, _mk_rim_c, 1.1, mk_aa)
	if not _mk_ln.is_empty():
		draw_multiline_colors(_mk_ln, _mk_ink, 3.0, mk_aa)
		draw_multiline_colors(_mk_ln, _mk_lc, 1.5, mk_aa)
	tq = v.field.pt("삽화·표식", tq)
	_fig_keys.sort()      # 화면 y 가 작은(먼) 인형부터 —— 키 = (y × 8 + 오프셋) << 16 | 번호
	v.drawn_figs = figure_count + bodies.size()
	if keep_dicts or not batch_rendering:
		for k in _fig_keys:
			visible_soldiers.append(_fig_dict(int(k & 0xFFFF)))
	tq = v.field.pt("삽화·정렬", tq)
	if batch_rendering:
		batch.update_packed(_figs, _fig_keys, FIG_W, ALLY_CLOTH, ENEMY_CLOTH)
	v.field.pt("삽화·버퍼", tq)
	if not batch_rendering:
		for figure in visible_soldiers:
			_draw_soldier(figure)
	v.field.pt("삽화 그리기", t0)

func _draw_overlay(ci: CanvasItem) -> void:
	if v == null or v.field == null:
		return
	_draw_contacts(ci)
	_draw_bodies(true, ci)
	for sq: Squad in v.field.order:
		if sq.fade > 0.01:
			_draw_status(sq, ci)
	_draw_volleys(ci)
	_draw_links(ci)
	_draw_mythic_actions(ci)
	_draw_ults(ci)

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
	var axis: Vector2 = (_pm(form.center + direction * 20.0) - _pm(form.center)).normalized()

	# 11/17 사용자 「옆으로 미끄러진다」 —— 그림 좌우를 늘 목표 적 쪽으로 두어, 옆으로 갈 때 걷는 쪽과 반대를 보며 미끄러졌다(문워크).
	# 맞붙지 않고 최근 공격하지 않은 채 화면 가로로 제법 움직이면 가는 쪽을 본다
	var face_x := axis.x
	var mv_screen: Vector2 = _pm(form.center + form.move_vel * 0.25) - _pm(form.center)
	var walking: bool = not form.contact and visual_time - form.last_action > 0.6 and mv_screen.length() > 2.5 * v.depth_scale(form.center)
	if walking and absf(mv_screen.x) > mv_screen.length() * 0.35:
		face_x = signf(mv_screen.x)
	if face_x > 0.3:
		form.facing_right = true
	elif face_x < -0.3:
		form.facing_right = false
	var mirror := not form.facing_right if sq.camp == "A" else form.facing_right

	var attacking := form.action_kind == "melee" and visual_time - form.last_action < 0.55
	var eligible := (form.contact or attacking) and sq.state != "flee" and target != null and target.alive
	var front_ids: Array = form.nearest_living(form.center + direction * sq.edge(direction), form.cols) if eligible else[]
	var scr: PackedVector2Array = _scr.get(sq.key, PackedVector2Array())
	if scr.size() != form.capacity:
		scr.resize(form.capacity)
	var fleeing := sq.state == "flee"
	var has_front := not front_ids.is_empty()
	var slot_f := float(sq.row.slot)
	var ranged: bool = form.action_kind == "volley" or form.action_kind == "spell"
	var bow_base := visual_time - form.last_action      # 활 당김은 쏜 뒤 0.5초 안에만 보인다 (그 뒤는 0)
	var sway := 0.035 if form.cavalry else 0.012
	var fade_sq := sq.fade
	for id in form.capacity:
		if form.alive[id] == 0:
			continue
		var p: Vector2 = _pm(form.feet[id])
		scr[id] = p
		var p0 := p      # 11/18 발은 _place 에서 이미 접촉선 안 —— 찌르기 · 밀림으로 옮겨진 인형만 다시 맞춘다
		var tilt := 0.0
		var gait: float = form.gait[id]
		var stride: float = form.strides[id]
		var hit := 0.0
		if not fleeing:
			if has_front and front_ids.has(id):
				# 11/19 찌르기 곡선은 앞줄만, 그것도 친 지 0.4초 안일 때만 잰다 (예전엔 모든 병사가 매 프레임 smoothstep 네 번)
				var age := visual_time - form.strike_at[id]
				var windup := 0.0
				var thrust := 0.0
				if age < 0.4:
					windup = smoothstep(0.0, 0.09, age) * (1.0 - smoothstep(0.09, 0.13, age))
					thrust = smoothstep(0.09, 0.13, age) * (1.0 - smoothstep(0.18, 0.4, age))
				var guard := sin(visual_time * 4.3 + id * 2.4 + slot_f) * form.contact_weight
				p += axis * guard * 0.55 * (1.0 - gait)
				tilt += axis.x * guard * 0.022
				p += axis * (thrust * 3.2 - windup * 1.2)
				tilt += axis.x * (thrust * 0.14 - windup * 0.065)
				gait *= 0.35
			elif ranged and bow_base < 0.5:
				var bow_age := bow_base - (id / form.cols) * 0.025
				var bow := smoothstep(0.0, 0.1, bow_age) * (1.0 - smoothstep(0.15, 0.32, bow_age))
				tilt -= axis.x * bow * 0.065
		var hurt_age := visual_time - form.hurt_at[id]
		if hurt_age >= 0.0 and hurt_age < 0.38:
			var hurt_axis: Vector2 = (_pm(form.feet[id] + form.hurt_dir[id] * 16.0) - p).normalized()
			var recoil := smoothstep(0.0, 0.055, hurt_age) * (1.0 - smoothstep(0.11, 0.38, hurt_age))
			p += hurt_axis * recoil * (2.0 + form.hurt_power[id] * 2.4)
			tilt += hurt_axis.x * recoil * (0.09 + form.hurt_power[id] * 0.06)
			hit = 1.0 - smoothstep(0.025, 0.14, hurt_age)
			gait *= 1.0 - recoil
		if gait > 0.001:
			tilt += sin(stride) * gait * sway
		if p != p0 and not form.contact_limits.is_empty():
			# Attack thrust and recoil must respect the same visible contact front.
			p = _pm(form.constrain_foot(v.unmap(p)))
		var n := figure_count
		figure_count += 1
		if _figs.size() < figure_count * FIG_W:
			_figs.resize(maxi(figure_count * FIG_W, _figs.size() * 2))
		var b := n * FIG_W
		_figs[b] = p.x
		_figs[b + 1] = p.y
		_figs[b + 2] = h
		_figs[b + 3] = cell
		_figs[b + 4] = fade_sq * form.opacity[id]
		_figs[b + 5] = tilt
		_figs[b + 6] = gait
		_figs[b + 7] = stride
		_figs[b + 8] = hit
		_figs[b + 9] = 1.0 if mirror else 0.0
		_fig_sq.append(sq)
		_fig_keys.append(((int(roundf(p.y * 8.0)) + 0x80000) << 16) | n)
	_scr[sq.key] = scr

## 11/19 그리기 호출 · 프레임: 부대마다 면 1 + 테두리 1 + 앞줄 표식 2 + 먼지 3 번씩 따로 그리던 것(18부대 ≈ 120회)을
## 전 부대 것을 모아 면(삼각형 묶음) 1 · 테두리 1 · 표식 2 번으로. 모양 · 색 · 자리는 _draw_formation_mark 와 같다
var _mk_pts := PackedVector2Array()
var _mk_cols := PackedColorArray()
var _mk_idx := PackedInt32Array()
var _mk_rim := PackedVector2Array()
var _mk_rim_c := PackedColorArray()
var _mk_ln := PackedVector2Array()
var _mk_ink := PackedColorArray()
var _mk_lc := PackedColorArray()
const DUST_SEG := 10

func _mark_batch(sq: Squad, form: FormationMotion) -> void:
	if form.count == 0:
		return
	var facing := Vector2.from_angle(form.heading)
	var right := Vector2(- facing.y, facing.x)
	var front := form.center + facing * maxf(sq.hd0 * form.ratio, RtBattle.HD_MIN) * 0.86
	var last_rank := 0
	for id in form.capacity:
		if form.alive[id] != 0 and form.ranks[id] > last_rank:
			last_rank = form.ranks[id]
	var back := front - facing * maxf(12.0, form.row_gap * last_rank)
	var side := right * (form.half_width + 7.0)
	var a := _pm(back - side)
	var b := _pm(front - side)
	var c := _pm(front + side)
	var d := _pm(back + side)
	var color := ALLY_MARK if sq.camp == "A" else ENEMY_MARK
	var fill := Color(color, 0.075 * sq.fade)
	var base := _mk_pts.size()
	_mk_pts.append(a)
	_mk_pts.append(b)
	_mk_pts.append(c)
	_mk_pts.append(d)
	for i in 4:
		_mk_cols.append(fill)
	_mk_idx.append(base)
	_mk_idx.append(base + 1)
	_mk_idx.append(base + 2)
	_mk_idx.append(base)
	_mk_idx.append(base + 2)
	_mk_idx.append(base + 3)
	var rim_c := Color(color, 0.38 * sq.fade)
	_mk_rim.append(a)
	_mk_rim.append(b)
	_mk_rim.append(b)
	_mk_rim.append(c)
	_mk_rim.append(c)
	_mk_rim.append(d)
	for i in 3:
		_mk_rim_c.append(rim_c)
	var scr: PackedVector2Array = _scr.get(sq.key, PackedVector2Array())
	var half := maxf(2.0, _figure_height(sq, form) * 0.17)
	var ink := Color(INK, 0.7 * sq.fade)
	var lc := Color(color, 0.8 * sq.fade)
	var ally := sq.camp == "A"
	for id in form.capacity:
		if form.alive[id] == 0 or form.ranks[id] != 0:
			continue
		var p: Vector2 = (scr[id] if id < scr.size() else _pm(form.feet[id])) + Vector2(0, 1)
		if ally:
			_mk_ln.append(p + Vector2(- half, 0))
			_mk_ln.append(p + Vector2(half, 0))
			_mk_ink.append(ink)
			_mk_lc.append(lc)
		else:
			var mid := p + Vector2(0, 1.5)
			_mk_ln.append(p + Vector2(- half, -1))
			_mk_ln.append(mid)
			_mk_ln.append(mid)
			_mk_ln.append(p + Vector2(half, -1))
			_mk_ink.append(ink)
			_mk_ink.append(ink)
			_mk_lc.append(lc)
			_mk_lc.append(lc)
	# 먼지 (_draw_dust 와 같은 자리 · 크기 · 빛) —— 같은 삼각형 묶음에
	if not sq.contact and not sq.moving:
		return
	var width := form.half_width * 2.0
	for j in 3:
		var phase := fposmod(v.field.clock * 0.8 + j * 0.33, 1.0)
		var at: Vector2 = form.center + sq.right() * (j - 1) * width * 0.3
		if sq.contact:
			at += sq.fwd * sq.hd()
		else:
			at -= sq.fwd * sq.hd()
		var dc := Color(0.72, 0.64, 0.46, sin(phase * PI) * 0.13 * sq.fade)
		var cen := _pm(at)
		var rad := (4.0 + phase * 7.0) * _pk(at) / _ps
		var b0 := _mk_pts.size()
		_mk_pts.append(cen)
		_mk_cols.append(dc)
		for k in DUST_SEG:
			_mk_pts.append(cen + Vector2.from_angle(TAU * k / DUST_SEG) * rad)
			_mk_cols.append(dc)
			_mk_idx.append(b0)
			_mk_idx.append(b0 + 1 + k)
			_mk_idx.append(b0 + 1 + (k + 1) % DUST_SEG)

## 점검 · 옛 그리기용 —— 묶음 배열 한 줄을 예전 사전 꼴로
func _fig_dict(n: int) -> Dictionary:
	var b := n * FIG_W
	return {"p": Vector2(_figs[b], _figs[b + 1]), "h": _figs[b + 2], "cell": int(_figs[b + 3]), "fade": _figs[b + 4],
		"tilt": _figs[b + 5], "gait": _figs[b + 6], "stride": _figs[b + 7], "hurt": _figs[b + 8], "mirror": _figs[b + 9] > 0.5, "sq": _fig_sq[n]}

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
	var rim := PackedVector2Array([_pm(back - right * (form.half_width + 7.0)),
		_pm(front - right * (form.half_width + 7.0)), _pm(front + right * (form.half_width + 7.0)),
		_pm(back + right * (form.half_width + 7.0))])
	var color := ALLY_MARK if sq.camp == "A" else ENEMY_MARK
	# 11/18 부하 2단계부터 표식 선의 안티에일리어싱을 끈다 (부대마다 매 프레임 —— 삽화 그리기에서 가장 무거웠다)
	var aa := v.get("load_lv") == null or int(v.load_lv) < 2
	draw_colored_polygon(rim, Color(color, 0.075 * sq.fade))
	draw_polyline(rim, Color(color, 0.38 * sq.fade), 1.1, aa)

	var scr: PackedVector2Array = _scr.get(sq.key, PackedVector2Array())
	var marks := PackedVector2Array()
	var half := maxf(2.0, _figure_height(sq, form) * 0.17)      # 11/18 부대마다 같다 —— 인형마다 다시 재던 것을 밖으로
	for id in form.capacity:
		if form.alive[id] == 0 or form.ranks[id] != 0:
			continue
		var p: Vector2 = (scr[id] if id < scr.size() else _pm(form.feet[id])) + Vector2(0, 1)
		var shape := PackedVector2Array([p + Vector2(- half, 0), p + Vector2(half, 0)])
		if sq.camp != "A":
			shape = PackedVector2Array([p + Vector2(- half, -1), p + Vector2(0, 1.5), p + Vector2(half, -1)])
		if not batch_rendering:
			draw_polyline(shape, Color(INK, 0.7 * sq.fade), 3.0, true)
			draw_polyline(shape, Color(color, 0.8 * sq.fade), 1.5, true)
			continue
		for segment in shape.size() - 1:
			marks.append_array([shape[segment], shape[segment + 1]])
	if not marks.is_empty():
		draw_multiline(marks, Color(INK, 0.7 * sq.fade), 3.0, aa)
		draw_multiline(marks, Color(color, 0.8 * sq.fade), 1.5, aa)
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

func _draw_bodies(airborne: bool, ci: CanvasItem = null) -> void:
	if ci == null:
		ci = self
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
			ci.draw_set_transform(p, 0, Vector2(1, 0.3))
			ci.draw_circle(Vector2.ZERO, h * 0.19, Color(0.08, 0.06, 0.04, 0.18 * alpha))
			ci.draw_set_transform(Vector2.ZERO)
		var tumble := smoothstep(0.0, 1.0, t)
		var turn := float(body.turn) * tumble
		var squash := lerpf(1.0, 0.4, smoothstep(0.78, 1.0, t))
		var cloth := ALLY_CLOTH if body.cell < 8 else ENEMY_CLOTH
		var tint := Color(cloth.darkened(0.25 * tumble), alpha * (0.7 if t >= 1.0 else 1.0))
		ci.draw_set_transform(p - Vector2(0, height + h * 0.3), turn, Vector2(-1.0 if body.mirror else 1.0, squash))
		ci.draw_texture_rect(cells[body.cell], Rect2(- h * 0.5, - h * 0.62, h, h), false, tint)
		ci.draw_set_transform(Vector2.ZERO)
		var landing := age - float(body.duration)
		if body.flying and landing >= 0.0 and landing < 0.27:
			var dust := landing / 0.27
			ci.draw_set_transform(p, 0, Vector2(1.0, 0.42))
			ci.draw_circle(Vector2.ZERO, 4.0 + dust * h * 0.5, Color(PAPER, (1.0 - dust) * 0.36))
			ci.draw_set_transform(Vector2.ZERO)

func _draw_contacts(ci: CanvasItem = null) -> void:
	if ci == null:
		ci = self
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
				ci.draw_line(p - side * 5.0 * power, p + side * 6.0 * power, Color(color, flash * 0.85), 2.0, true)
			ci.draw_circle(p, 2.0 * power, Color(color, flash), true, -1.0, true)
		var fade := 1.0 - smoothstep(0.04, 0.25, age)
		for i in (4 if hit.power > 1.0 else 2):
			var ray := axis.rotated((float(i) - 1.5) * 0.75)
			var travel := age * 28.0 * power
			ci.draw_line(p + ray * travel, p + ray * (travel + 3.0 * power), Color(EMBER, fade * 0.9), 1.2, true)

func volley_progress(shot: Dictionary, id: int, clock: float) -> float:
	return clampf((clock - float(shot.start) - 0.12 - id * 0.025) / float(shot.flight), 0.0, 1.0)

func _draw_volleys(ci: CanvasItem = null) -> void:
	if ci == null:
		ci = self
	for shot in volleys:
		var start: Vector2 = shot.from
		var end: Vector2 = shot.to
		for id in shot.count:
			var t := volley_progress(shot, id, last_clock)
			if t <= 0.0 or t >= 1.0:
				continue
			var spread := Vector2(0.0, (float(id) - float(shot.count - 1) * 0.5) * 8.0)
			var world := start.lerp(end + spread, t)
			var prev_t := maxf(0.0, t - 0.045)
			var height := 18.0 + start.distance_to(end) * 0.025
			var p: Vector2 = v.map(world) - Vector2(0, 5.0 + sin(t * PI) * height * v.depth_scale(world))
			var prev: Vector2 = v.map(start.lerp(end + spread, prev_t)) - Vector2(0, 5.0 + sin(prev_t * PI) * height * v.depth_scale(world))
			if shot.kind == "spell":
				_spell_orb(ci, shot, id, start, end, spread, t, height)
				continue
			var color := PAPER
			ci.draw_line(prev, p, Color(INK, 0.8), 2.0, true)
			ci.draw_line(prev, p, color, 1.0, true)

func fire_sea_outline(sea: Dictionary) -> PackedVector2Array:
	# The boundary is already active on the first tick. Animate flames, not radius.
	return v.area_outline({"x": sea.center.x, "y": sea.center.y, "r": sea.radius})

func _draw_fire_seas() -> void:
	for sea: Dictionary in fire_seas.values():
		var fade := clampf(float(sea.end) - last_clock, 0.0, 1.0)
		var center: Vector2 = sea.center
		var radius := float(sea.radius)
		var rim := fire_sea_outline(sea)
		draw_colored_polygon(rim, Color(0.46, 0.18, 0.08, 0.34 * fade))
		rim.append(rim[0])
		draw_polyline(rim, Color(EMBER, 0.58 * fade), 1.8, true)
		for i in 12:
			var spot := center + Vector2.from_angle(TAU * i / 12.0) * radius * (0.71 + (i % 3) * 0.1)
			var at: Vector2 = v.map(spot)
			var flicker := 0.5 + 0.5 * sin(last_clock * 8.0 + float(i) * 2.4)
			var h: float = (13.0 + flicker * 9.0) * v.depth_scale(spot)
			_spr(self, "flame_02", at + Vector2(0, - h * 0.32), h, Color(EMBER, (0.26 + flicker * 0.32) * fade), 0.1, Vector2(0.7, 1.0))

func _draw_mythic_actions(ci: CanvasItem = null) -> void:
	if ci == null:
		ci = self
	for sea: Dictionary in fire_seas.values():
		var age := maxf(0.0, last_clock - float(sea.start))
		if age < 1.45:
			_action_label(v.map(sea.center), "적벽 불바다", EMBER, clampf((1.45 - age) * 3.0, 0.0, 1.0), ci)
	for key in peerless:
		var sq: Squad = v.field.squads.get(key)
		if sq != null and sq.alive:
			var mark: Dictionary = peerless[key]
			var at: Vector2 = v.map(sq.pos - sq.fwd * sq.hd() * 0.65)
			_action_label(at + Vector2(0, -24), "무쌍  공격 +%d%%" % mark.bonus, PAPER, clampf((float(mark.end) - last_clock) * 4.0, 0.0, 1.0), ci)
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
		ci.draw_polyline(arc, Color(accent, (1.0 - t) * 0.8), 2.2, true)
		if hit.brace:
			_action_label(v.map(center), "창벽", PAPER, 1.0 - t, ci)
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
			ci.draw_line(start.lerp(dst, maxf(0.0, progress - 0.3)), start.lerp(dst, progress), Color(JADE, 0.8), 2.0, true)
		ci.draw_arc(dst, 9.0 + t * 13.0, 0.0, TAU, 20, Color(JADE, (1.0 - t) * 0.65), 1.5, true)
		_action_label(dst + Vector2(0, -23), rally.label, JADE, clampf((1.0 - t) * 3.0, 0.0, 1.0), ci)
	for key in flames:
		var target: Squad = v.field.squads.get(key)
		if target == null or target.fade <= 0.01:
			continue
		var flame: Dictionary = flames[key]
		var t := clampf((last_clock - float(flame.start)) / (float(flame.end) - float(flame.start)), 0.0, 1.0)
		for i in range(-1, 2):
			var at: Vector2 = v.map(target.pos + target.right() * float(i) * target.hw * 0.65)
			var h: float = (12.0 + sin(t * PI) * 23.0) * float(flame.size) * v.depth_scale(target.pos)
			_spr(ci, "flame_02", at - Vector2(0, h * 0.5), h, Color(EMBER, (1.0 - t) * 0.9), 0.0, Vector2(0.75, 1.0))

func _action_label(at: Vector2, label: String, color: Color, alpha: float, ci: CanvasItem = null) -> void:
	if ci == null:
		ci = self
	var width := DB.font_bold.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
	var pos := at - Vector2(width * 0.5, 7)
	ci.draw_string_outline(DB.font_bold, pos, label, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, 4, Color(INK, alpha))
	ci.draw_string(DB.font_bold, pos, label, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(color, alpha))

func _draw_links(ci: CanvasItem = null) -> void:
	if ci == null:
		ci = self
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
			ci.draw_circle(at, 2.5 - j * 0.5, Color(e.col, (1.0 - t) * 0.85))

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
		draw_circle(_pm(at), (4.0 + phase * 7.0) * _pk(at) / _ps, Color(0.72, 0.64, 0.46, sin(phase * PI) * 0.13 * sq.fade))

func _draw_status(sq: Squad, ci: CanvasItem = null) -> void:
	if ci == null:
		ci = self
	if not sq.alive:
		return
	var p: Vector2 = v.map(sq.pos)
	var perspective: float = v.depth_scale(sq.pos)
	if sq.statuses.has("burn"):
		for j in 4:
			var phase: float = v.field.clock * 5.0 + j * 1.7
			var base: Vector2 = v.map(sq.pos + sq.right() * (j - 1.5) * sq.hw * 0.5)
			var h := (13.0 + 5.0 * sin(phase)) * perspective
			_spr(ci, "flame_02", base + Vector2(0, -h * 0.45), h * 2.0, Color(1.0, 0.62, 0.20, 0.85), sin(phase) * 0.12, Vector2(0.65, 1.0))
	if sq.statuses.has("cut_def") or sq.statuses.has("cut_res"):
		var q := p + Vector2(14, -22) * perspective
		ci.draw_set_transform(q, 0, Vector2.ONE * perspective)
		q = Vector2.ZERO
		var shield := PackedVector2Array([q + Vector2(-6, -7), q + Vector2(6, -7), q + Vector2(5, 2), q + Vector2(0, 7), q + Vector2(-5, 2), q + Vector2(-6, -7)])
		ci.draw_polyline(shield, Color("#e6bd79"), 1.5, true)
		ci.draw_polyline(PackedVector2Array([q + Vector2(1, -7), q + Vector2(-2, -1), q + Vector2(2, 1), q + Vector2(0, 7)]), INK, 2.5, true)
		ci.draw_set_transform(Vector2.ZERO)
	if sq.statuses.has("flood"):
		for j in 2:
			ci.draw_arc(p + Vector2(0, j * 3) * perspective, (13 + j * 2) * perspective, 0.1, PI - 0.1, 12, Color(0.35, 0.65, 0.75, 0.7), 1.3, true)
	if sq.statuses.has("confuse"):
		ci.draw_arc(p + Vector2(0, -17) * perspective, 7 * perspective, v.field.clock, v.field.clock + PI * 1.6, 12, Color("#be9aca"), 1.7, true)


# ───────── 고유기 이펙트 (11/17) ─────────
# 사용자: 「고유기 이펙트가 왜 안 나오냐」 —— 삽화 화면에서는 type2 의 fx()/_draw_fx 가 모두 꺼져 컷인 · 카메라 · 병사 밀림만 남았다.
# 화면 섬광 · 팝콘 날리기 없이 붓 획 · 불꽃 · 낙뢰 · 화살비처럼 종류가 한눈에 갈리게 그린다. 판정 · 수치와 무관한 화면 연출.
const ULT_LIFE := {"firestorm": 2.4, "thunder": 1.5, "slash": 1.1, "shadow": 1.3, "poison": 2.4, "illusion": 1.8, "aura": 1.8, "heal": 1.8, "roar": 1.2, "whirlwind": 1.4, "charge": 1.0}

## 11/19 화염 계열 여섯 —— 인물마다 불이 오는 방식이 다르다 (없으면 불덩이 셋). 다른 계열은 인물 갈래 번호(sd)로 획 수 · 각도 · 색을 바꾼다
##  wave 주유 적벽대화: 바람을 탄 불벽이 적진을 쓸고 지나간다 · trail 육손 이릉: 불길이 진영을 따라 차례로 옮겨붙는다 · arrows 정보 화선: 불화살 떼
##  ram 황개 고육지계: 불배 하나가 곧장 들이받고 터진다 · chain 방통 연환: 쇠사슬로 엮인 뒤 사슬을 따라 탄다 · erupt 동탁 낙양겁화: 땅에서 불기둥이 솟는다
const ULT_STYLE := {"주유": "wave", "육손": "trail", "정보": "arrows", "황개": "ram", "방통": "chain", "동탁": "erupt"}

## phase "charge" —— 기 모으기 (시전자 둘레), "impact" —— 맞는 순간 (적 · 아군 부대)
func add_ult(vfx: String, a_key: String, foes: Array, allies: Array, col: Color, phase: String) -> void:
	var now: float = v.field.clock
	var a: Squad = v.field.squads.get(a_key)
	var e := {"vfx": vfx, "a": a_key, "col": col, "phase": phase, "start": now,
		"end": now + (0.55 if phase == "charge" else 3.0 if phase == "dash" else float(ULT_LIFE.get(vfx, 1.0))),
		"from": a.pos if a != null else Vector2.ZERO, "hits": [], "allies": []}
	# 11/19 사용자: 같은 계열 고유기라도 이펙트가 달라 보이게 —— 인물마다 모양(style) · 갈래 번호(sd)를 싣는다
	var who: String = DB.person(a.cid) if a != null and DB.C.has(a.cid) else ""
	e["style"] = str(ULT_STYLE.get(who, ""))
	e["sd"] = absi(hash(who)) % 997
	var storm := vfx == "arrowstorm"
	if storm and phase == "impact":      # 화살비 —— 기 모으기 동안은 컷인이 덮고 있어, 컷인이 걷힌 맞는 순간에 떼로 솟아 쏟아진다
		e.end = now + 1.8
	if phase == "impact":
		for k in foes:
			var d: Squad = v.field.squads.get(k)
			if d == null:
				continue
			var spots := []
			for j in 7:      # 발자국 안 고정 지점 —— 화면 쪽 해시 (전투 rng 를 건드리지 않는다)
				var h1 := float(hash(str(k) + ":" + str(j)) % 10007) / 10007.0
				var h2 := float(hash(str(j) + ":" + str(k) + ":y") % 10007) / 10007.0
				spots.append(d.pos + d.right() * (h1 * 2.0 - 1.0) * d.hw * 0.75 + d.fwd * (h2 * 2.0 - 1.0) * d.hd() * 0.55)
			e.hits.append({"at": d.pos, "spots": spots, "right": d.right(), "fwd": d.fwd, "hw": d.hw, "hd": d.hd()})
		for k in allies:
			var q: Squad = v.field.squads.get(k)
			if q != null:
				e.allies.append(q.pos)
	ults.append(e)
	while ults.size() > MAX_ULTS:
		ults.pop_front()

## 전장 길이 L 을 그 자리의 화면 px 로
func _px(at: Vector2, length: float) -> float:
	return (v.map(at + Vector2(0, length)) - v.map(at)).length()

## 전장 원을 화면 타원으로 (먹 테두리 + 색)
func _world_ring(ci: CanvasItem, c: Vector2, r: float, col: Color, width: float) -> void:
	var pts := PackedVector2Array()
	for k in 25:
		var t := TAU * k / 24.0
		pts.append(v.map(c + Vector2(cos(t), sin(t)) * r))
	ci.draw_polyline(pts, Color(INK, col.a * 0.55), width + 2.0, true)
	ci.draw_polyline(pts, col, width, true)

## 11/17 사용자: 「이펙트가 잘 안 보이면 배경을 좀 바꿔도」 —— 고유기가 터지는 동안 전장(땅 · 병사)을 종류 색의 어둠으로 깔고 그 위에 효과를 그린다.
## 메달 · HUD 는 위층이라 밝은 그대로. 화살비는 검은 화살이라 반대로 하늘을 밝게 씻는다
const ULT_DIM := {"firestorm": Color(0.16, 0.03, 0.0, 0.42), "thunder": Color(0.02, 0.04, 0.14, 0.5), "poison": Color(0.03, 0.1, 0.02, 0.42),
	"illusion": Color(0.1, 0.03, 0.16, 0.42), "shadow": Color(0.04, 0.02, 0.07, 0.5), "arrowstorm": Color(1.0, 0.96, 0.88, 0.12)}
const ULT_DIM_BASE := Color(0.06, 0.05, 0.04, 0.36)
func _ult_backdrop(ci: CanvasItem) -> void:
	var best := 0.0
	var tint := ULT_DIM_BASE
	for e: Dictionary in ults:
		if e.phase != "impact":
			continue
		var age := last_clock - float(e.start)
		var life := float(e.end) - float(e.start)
		if age < 0.0 or age > life:
			continue
		var k := minf(1.0, age / 0.12) * (1.0 - smoothstep(life - 0.45, life, age))
		if k > best:
			best = k
			tint = ULT_DIM.get(e.vfx, ULT_DIM_BASE)
	if best > 0.01:
		ci.draw_rect(Rect2(Vector2(-40, -40), v.size + Vector2(80, 80)), Color(tint, tint.a * best))

func _draw_ults(ci: CanvasItem) -> void:
	_ult_backdrop(ci)
	for e: Dictionary in ults:
		var age := last_clock - float(e.start)
		if age < 0.0:
			continue
		var life := float(e.end) - float(e.start)
		var t := clampf(age / life, 0.0, 1.0)
		var col: Color = e.col
		var fade := 1.0 - smoothstep(0.7, 1.0, t)
		if e.vfx == "arrowstorm":
			if e.phase == "impact":
				_arrow_storm(ci, e, age)
			continue
		if e.phase == "charge":
			_ult_charge(ci, e, t, col)
			continue
		if e.phase == "dash":
			_ult_dash(ci, e, age)
			continue
		var from: Vector2 = e.from
		if e.vfx in ["roar", "whirlwind"]:
			_shock_from(ci, e, age, t, col, fade, from)
		for hit: Dictionary in e.hits:
			_ult_hit(ci, e, hit, t, age, col, fade, from)
		if e.vfx in ["aura", "heal"]:
			if e.vfx == "aura":
				_sunburst(ci, from, age, col, fade, int(e.get("sd", 0)))
			for q: Vector2 in e.allies:
				_pillar(ci, q, age, col, fade)

func _ult_charge(ci: CanvasItem, e: Dictionary, t: float, col: Color) -> void:
	var from: Vector2 = e.from
	var fs: Vector2 = v.map(from)
	if e.vfx in UltFx.MAGIC:      # 술법 —— 조여드는 고리 + 법진, 무장 —— 흙먼지만 (고리는 장풍처럼 보였다)
		for j in 2:
			var u := clampf(t * 1.3 - j * 0.3, 0.0, 1.0)
			if u > 0.0 and u < 1.0:
				_world_ring(ci, from, 70.0 - u * 45.0, Color(col, sin(u * PI) * 0.9), 2.5)
		var ma := sin(t * PI)      # 법진 —— 두 겹 고리 + 도는 별 모양 (흐린 그림 대신 선)
		_world_ring(ci, from, 55.0, Color(col, 0.85 * ma), 3.0)
		_world_ring(ci, from, 40.0, Color(col, 0.6 * ma), 1.8)
		var star := PackedVector2Array()
		for k in 6:
			var ang := t * 4.0 + k * TAU * 2.0 / 5.0
			star.append(v.map(from + Vector2(cos(ang), sin(ang)) * 52.0))
		ci.draw_polyline(star, Color(col.lightened(0.3), 0.8 * ma), 2.0, true)
	else:
		for j in 5:
			var ang := TAU * j / 5.0 + t
			var at := from + Vector2(cos(ang), sin(ang)) * 30.0 * (1.0 - t * 0.5)
			ci.draw_circle(v.map(at), _px(at, 14.0), Color(0.78, 0.69, 0.5, 0.55 * sin(t * PI)))

# ── 그리기 부품 (11/17 사용자: 「황충 고유기 정도의 임팩트는 있어야지, 나머지는 쓰는지 티도 안 난다」) ──
# 흐린 효과 그림 대신 진한 도형 + 꼭짓점 색 그라데이션 + 먹 테두리로 그린다. 황토 지면 위에서도 읽히게.

## 불길 혀 하나 —— 바닥 c(화면), 높이 h, 폭 w. 아래 붉은 주황 → 끝 노랑 · 투명
func _flame(ci: CanvasItem, c: Vector2, h: float, w: float, phase: float, a: float) -> void:
	if h < 1.0 or w < 0.3:      # 11/19 높이 0 다각형 오류 방지
		return
	if h < 2.0 or a <= 0.01:
		return
	var sway := sin(phase) * w * 0.45
	var pts := PackedVector2Array([c + Vector2(-w, 0), c + Vector2(-w * 0.75, -h * 0.4), c + Vector2(-w * 0.35 + sway * 0.5, -h * 0.75),
		c + Vector2(sway, -h), c + Vector2(w * 0.35 + sway * 0.5, -h * 0.7), c + Vector2(w * 0.8, -h * 0.35), c + Vector2(w, 0)])
	var cols := PackedColorArray()
	for p in pts:
		var k := clampf((c.y - p.y) / h, 0.0, 1.0)
		cols.append(Color(Color(0.85, 0.18, 0.04).lerp(Color(1.0, 0.85, 0.3), k), a * (1.0 - k * 0.55)))
	ci.draw_polygon(pts, cols)
	var core := PackedVector2Array([c + Vector2(-w * 0.45, 0), c + Vector2(sway * 0.6, -h * 0.6), c + Vector2(w * 0.45, 0)])
	ci.draw_colored_polygon(core, Color(1.0, 0.95, 0.65, a * 0.85))

## 채운 타원 (화면 반지름 rx, ry)
func _ellipse(ci: CanvasItem, c: Vector2, rx: float, ry: float, col: Color) -> void:
	var pts := PackedVector2Array()
	for k in 20:
		var t := TAU * k / 20.0
		pts.append(c + Vector2(cos(t) * rx, sin(t) * ry))
	ci.draw_colored_polygon(pts, col)

## 초승달 붓 획 —— 가운데 c, 반지름 r, 시작 각 a0, 펼친 각 span, 가장 굵은 곳 th
func _crescent(ci: CanvasItem, c: Vector2, r: float, a0: float, span: float, th: float, col: Color, squash := 0.55) -> void:
	if span <= 0.02:
		return
	var outer := PackedVector2Array()
	var inner := PackedVector2Array()
	for k in 13:
		var u := float(k) / 12.0
		var ang := a0 + span * u
		var w := th * sin(u * PI)
		outer.append(c + Vector2(cos(ang) * r, sin(ang) * r * squash))
		inner.append(c + Vector2(cos(ang) * (r - w), sin(ang) * (r - w) * squash))
	inner.reverse()
	var poly := outer + inner
	ci.draw_colored_polygon(poly, col)
	outer.append_array(inner)
	outer.append(outer[0])
	ci.draw_polyline(outer, Color(INK, col.a * 0.7), 1.8, true)

## 낙뢰 —— top 에서 bottom 까지 지그재그 (seed 로 모양 고정)
func _bolt(ci: CanvasItem, top: Vector2, bottom: Vector2, seed: float, col: Color, a: float) -> void:
	var pts := PackedVector2Array([top])
	var w := top.distance_to(bottom) * 0.09
	for k in range(1, 9):
		pts.append(top.lerp(bottom, k / 9.0) + Vector2(sin(seed * 3.7 + k * 2.9) * w, 0))
	pts.append(bottom)
	ci.draw_polyline(pts, Color(col, a * 0.45), 10.0, true)
	ci.draw_polyline(pts, Color(col.lightened(0.4), a * 0.9), 4.5, true)
	ci.draw_polyline(pts, Color(1, 1, 1, a), 1.8, true)
	var b0: Vector2 = pts[4]      # 곁가지 하나
	var b1 := b0 + Vector2(sin(seed) * w * 3.0, w * 2.5)
	ci.draw_polyline(PackedVector2Array([b0, b0.lerp(b1, 0.5) + Vector2(w * 0.6, 0), b1]), Color(1, 1, 1, a * 0.8), 1.4, true)

## 시전자에서 퍼지는 기합 · 회오리 (포효 · 선풍)
func _shock_from(ci: CanvasItem, e: Dictionary, age: float, t: float, col: Color, fade: float, from: Vector2) -> void:
	for j in 3:      # 기합 고리 세 겹 —— 전장 380 까지 (화면 100px 남짓)
		var u := clampf((age - j * 0.12) / 0.75, 0.0, 1.0)
		if u > 0.0 and u < 1.0:
			_world_ring(ci, from, 30.0 + u * 350.0, Color(col, (1.0 - u) * 0.95), 11.0 - j * 3.0)
			_world_ring(ci, from, 20.0 + u * 320.0, Color(PAPER, (1.0 - u) * 0.65), 4.0)
	var fs: Vector2 = v.map(from)
	var r := maxf(55.0, _px(from, 230.0))
	for k in 14:      # 바닥에서 밀려 나가는 흙먼지 띠
		var ang := k * TAU / 14.0
		var u2 := clampf(age / 0.9, 0.0, 1.0)
		var p := fs + Vector2(cos(ang), sin(ang) * 0.5) * r * (0.35 + u2 * 0.75)
		ci.draw_circle(p, r * 0.12 * (0.6 + u2), Color(0.8, 0.71, 0.52, 0.7 * (1.0 - u2)))
	if e.vfx == "whirlwind":      # 시전자 둘레를 휘감는 커다란 바람 날 다섯
		for k in 5:
			var a0 := age * 8.0 + k * TAU / 5.0
			var rr := r * (0.7 + 0.12 * sin(age * 5.0 + k))
			_crescent(ci, fs, rr, a0, 1.7, r * 0.2, Color(1.0, 0.95, 0.82, 0.95 * fade))
			_crescent(ci, fs, rr * 0.75, a0 + 0.6, 1.3, r * 0.12, Color(col, 0.85 * fade))

## 아군 빛기둥 —— 바닥 고리 + 위로 옅어지는 기둥 + 떠오르는 마름모 빛
func _pillar(ci: CanvasItem, q: Vector2, age: float, col: Color, fade: float) -> void:
	var qs: Vector2 = v.map(q)
	var w := maxf(16.0, _px(q, 55.0))
	var h := w * 5.5 * minf(1.0, age * 4.0)
	if h < 1.0:      # 11/19 막 시작한 프레임(높이 0)의 찌그러진 다각형이 「Invalid polygon data」 오류를 냈다 (오류 출력이 프레임도 잡아먹는다)
		return
	var pts := PackedVector2Array([qs + Vector2(-w, 0), qs + Vector2(-w * 0.6, -h), qs + Vector2(w * 0.6, -h), qs + Vector2(w, 0)])
	ci.draw_polygon(pts, PackedColorArray([Color(col, 0.75 * fade), Color(col, 0.0), Color(col, 0.0), Color(col, 0.75 * fade)]))
	var core := PackedVector2Array([qs + Vector2(-w * 0.35, 0), qs + Vector2(-w * 0.15, -h * 0.9), qs + Vector2(w * 0.15, -h * 0.9), qs + Vector2(w * 0.35, 0)])
	ci.draw_polygon(core, PackedColorArray([Color(1, 1, 1, 0.6 * fade), Color(1, 1, 1, 0.0), Color(1, 1, 1, 0.0), Color(1, 1, 1, 0.6 * fade)]))
	_ellipse(ci, qs, w * 1.3, w * 0.5, Color(col, 0.35 * fade))
	_world_ring(ci, q, 22.0 + sin(age * 6.0) * 4.0, Color(col.lightened(0.3), 0.9 * fade), 2.5)
	for k in 6:
		var u := fmod(age * 1.3 + k * 0.17, 1.0)
		var p := qs + Vector2(sin(k * 2.1) * w * 0.8, -h * u)
		ci.draw_circle(p, w * 0.1 * (1.0 - u * 0.5), Color(col.lightened(0.5), 0.9 * fade * (1.0 - u)))

## 11/19 화염 계열 —— 인물마다 다른 불 (ULT_STYLE). 앞 0.45초는 불이 오는 방식, 그 뒤는 타는 모양(불길 수 · 키 · 연기)도 갈래마다 다르다
func _fire_style(ci: CanvasItem, e: Dictionary, hit: Dictionary, age: float, fade: float, from: Vector2, unit: float) -> void:
	var at: Vector2 = hit.at
	var ds: Vector2 = v.map(at)
	var fs: Vector2 = v.map(from)
	var spots: Array = hit.spots
	var right: Vector2 = hit.right
	var fwd: Vector2 = hit.fwd
	var hw := float(hit.hw)
	var hd := float(hit.hd)
	var style := str(e.get("style", ""))
	var dir := (ds - fs).normalized() if not (ds - fs).is_zero_approx() else Vector2.UP
	var side := Vector2(-dir.y, dir.x)
	var g := clampf((age - 0.3) / 0.25, 0.0, 1.0)      # 불이 붙어 번지는 정도
	var n_flame := 14
	var tall := 1.0
	var smoke := 3
	match style:
		"wave":      # 주유 —— 바람 줄기가 먼저 스치고, 불벽이 시전자 쪽에서 적진을 쓸고 지나간다
			var u := clampf(age / 0.75, 0.0, 1.0)
			for k in 7:
				var wu := fmod(age * 1.8 + k * 0.143, 1.0)
				var w0 := ds + side * (k - 3) * unit * 0.55 + dir * unit * (-3.0 + wu * 6.0)
				ci.draw_line(w0, w0 + dir * unit * 0.9, Color(1.0, 0.86, 0.62, 0.5 * fade * sin(PI * wu)), 1.6, true)
			if u < 1.0:
				var front := ds + dir * unit * (-2.4 + u * 4.8)
				_ellipse(ci, front - dir * unit * 0.7, unit * 2.2, unit * 0.6, Color(0.9, 0.3, 0.05, 0.35))
				for k in 9:
					var fp := front + side * (k - 4) * unit * 0.42 + Vector2(0, sin(k * 1.7 + age * 9.0) * unit * 0.1)
					_flame(ci, fp, unit * (1.9 + 0.5 * sin(k * 2.3 + age * 12.0)), unit * 0.3, last_clock * 8.0 + k, 0.95)
			g = clampf((age - 0.35) / 0.3, 0.0, 1.0)
			n_flame = 18
			tall = 1.25
		"trail":      # 육손 —— 불씨가 진영을 따라 달리며 지나간 자리마다 차례로 불기둥이 선다
			var u := clampf(age / 0.85, 0.0, 1.0)
			var path := PackedVector2Array()
			for k in 7:
				path.append(v.map(at + right * (k / 3.0 - 1.0) * hw * 1.25 + fwd * sin(k * 2.2) * hd * 0.5))
			var reach := u * (path.size() - 1)
			var lit := PackedVector2Array()
			for k in path.size():
				if float(k) <= reach:
					lit.append(path[k])
			if lit.size() < path.size():
				var kk := int(reach)
				lit.append(path[kk].lerp(path[mini(kk + 1, path.size() - 1)], reach - kk))
			if lit.size() >= 2:
				ci.draw_polyline(lit, Color(0.35, 0.08, 0.02, 0.6 * fade), unit * 0.32, true)
				ci.draw_polyline(lit, Color(1.0, 0.62, 0.15, 0.9 * fade), unit * 0.14, true)
				ci.draw_circle(lit[-1], unit * 0.22, Color(1.0, 0.92, 0.6, fade))
			for k in path.size():
				var lu := clampf(reach - k + 0.3, 0.0, 1.0)
				if lu > 0.0:
					_flame(ci, path[k], unit * (2.3 - 0.9 * clampf(age - 0.9, 0.0, 1.0)) * lu, unit * 0.2, last_clock * 9.0 + k * 1.3, 0.95 * fade)
			g = 0.0      # 번지는 불바다 대신 줄지어 선 불기둥
			smoke = 2
		"arrows":      # 정보 —— 가는 불화살 떼가 포물선으로 쏟아져 여기저기 작은 불이 붙는다
			for j in 12:
				var u := clampf((age - j * 0.035) / 0.42, 0.0, 1.0)
				if u > 0.0 and u < 1.0:
					var sp: Vector2 = v.map(spots[j % spots.size()]) + Vector2(sin(j * 3.3), cos(j * 2.1)) * unit * 0.3
					var p1 := fs.lerp(sp, u) - Vector2(0, sin(u * PI) * unit * 2.6)
					var u0 := maxf(0.0, u - 0.06)
					var p0 := fs.lerp(sp, u0) - Vector2(0, sin(u0 * PI) * unit * 2.6)
					ci.draw_line(p0, p1, Color(INK, 0.9), 2.0, true)
					ci.draw_line(p0.lerp(p1, 0.55), p1, Color(1.0, 0.6, 0.12), 3.0, true)
					ci.draw_circle(p1, unit * 0.09, Color(1.0, 0.92, 0.55))
			for j in 7:      # 꽂힌 자리마다 작은 불
				var lu := clampf((age - 0.4 - j * 0.035) / 0.2, 0.0, 1.0)
				if lu > 0.0:
					var sp2: Vector2 = v.map(spots[j])
					_ellipse(ci, sp2, unit * 0.75 * lu, unit * 0.3 * lu, Color(0.9, 0.35, 0.06, 0.45 * fade))
					_flame(ci, sp2, unit * 1.5 * lu * (0.8 + 0.2 * sin(last_clock * 10.0 + j)), unit * 0.24, last_clock * 7.0 + j, 0.95 * fade)
			g = 0.0
			smoke = 1
		"ram":      # 황개 —— 불붙은 배 하나가 낮게 곧장 달려와 들이받고 크게 터진다
			var u := clampf(age / 0.42, 0.0, 1.0)
			if u < 1.0:
				var bp := fs.lerp(ds, u) - Vector2(0, sin(u * PI) * unit * 0.5)
				var tail := PackedVector2Array()
				for k in 8:
					var uu := maxf(0.0, u - k * 0.05)
					tail.append(fs.lerp(ds, uu) - Vector2(0, sin(uu * PI) * unit * 0.5))
				ci.draw_polyline(tail, Color(0.25, 0.1, 0.05, 0.6), unit * 0.75, true)
				ci.draw_polyline(tail, Color(0.95, 0.4, 0.06, 0.85), unit * 0.5, true)
				ci.draw_circle(bp, unit * 0.55, Color(0.35, 0.16, 0.06))      # 선체
				_flame(ci, bp, unit * 1.3, unit * 0.4, last_clock * 10.0, 1.0)
			else:
				var bu := clampf((age - 0.42) / 0.5, 0.0, 1.0)
				_world_ring(ci, at, 20.0 + bu * 150.0, Color(1.0, 0.75, 0.3, 0.95 * (1.0 - bu)), 4.0)
				for k in 12:
					var ang := k * TAU / 12.0 + 0.3
					var rd := Vector2(cos(ang), sin(ang) * 0.55)
					var d0 := ds + rd * unit * (0.4 + bu * 2.4)
					ci.draw_line(d0, d0 + rd * unit * 0.5, Color(1.0, 0.8, 0.35, 0.9 * (1.0 - bu)), 3.0, true)
			g = clampf((age - 0.42) / 0.2, 0.0, 1.0)
			n_flame = 9
			tall = 1.7
			smoke = 4
		"chain":      # 방통 —— 쇠사슬이 부대를 엮고, 불이 사슬을 타고 돈다
			var u := clampf(age / 0.35, 0.0, 1.0)
			var ring := PackedVector2Array()
			for k in 13:
				var ang := k * TAU / 12.0
				ring.append(v.map(at + right * cos(ang) * hw * 1.1 + fwd * sin(ang) * hd * 1.1))
			var shown := clampi(int(u * ring.size()), 2, ring.size())
			for k in shown - 1:      # 사슬 —— 마디마다 작은 고리
				ci.draw_line(ring[k], ring[k + 1], Color(0.12, 0.11, 0.1, 0.9 * fade), 3.0, true)
				ci.draw_arc(ring[k].lerp(ring[k + 1], 0.5), unit * 0.11, 0, TAU, 8, Color(0.55, 0.5, 0.42, 0.9 * fade), 1.6, true)
			var run := clampf((age - 0.3) / 0.6, 0.0, 1.0)
			for k in int(run * 12.0):
				_flame(ci, ring[k], unit * (1.1 + 0.3 * sin(k * 1.9 + last_clock * 8.0)), unit * 0.2, last_clock * 8.0 + k, 0.95 * fade)
			g = clampf((age - 0.8) / 0.3, 0.0, 1.0)
			n_flame = 6
		"erupt":      # 동탁 —— 날아오는 것 없이 땅이 붉게 갈라지고 불기둥이 솟는다. 연기가 가장 짙다
			for j in 7:
				var lu := clampf((age - j * 0.07) / 0.3, 0.0, 1.0)
				if lu <= 0.0:
					continue
				var sp: Vector2 = v.map(spots[j])
				var crack := PackedVector2Array([sp + Vector2(-unit * 0.5, 0), sp + Vector2(-unit * 0.15, unit * 0.08), sp + Vector2(unit * 0.1, -unit * 0.06), sp + Vector2(unit * 0.5, unit * 0.04)])
				ci.draw_polyline(crack, Color(1.0, 0.45, 0.08, 0.9 * fade), 2.5, true)
				var hgt := maxf(2.0, unit * 3.0 * lu * (1.0 - 0.35 * clampf(age - 1.0, 0.0, 1.0)))
				var col_pts := PackedVector2Array([sp + Vector2(-unit * 0.16, 0), sp + Vector2(-unit * 0.1, -hgt), sp + Vector2(unit * 0.1, -hgt), sp + Vector2(unit * 0.16, 0)])
				ci.draw_polygon(col_pts, PackedColorArray([Color(0.75, 0.12, 0.02, 0.85 * fade), Color(1.0, 0.6, 0.1, 0.0), Color(1.0, 0.6, 0.1, 0.0), Color(0.75, 0.12, 0.02, 0.85 * fade)]))
				_flame(ci, sp, unit * 1.2 * lu, unit * 0.24, last_clock * 8.0 + j, 0.95 * fade)
			g = clampf((age - 0.25) / 0.3, 0.0, 1.0)
			n_flame = 8
			tall = 0.9
			smoke = 6
		_:      # 불덩이 셋이 꼬리를 끌고 날아와 꽂힌다
			for j in 3:
				var u := clampf((age - j * 0.08) / 0.4, 0.0, 1.0)
				if u > 0.0 and u < 1.0:
					var sp: Vector2 = v.map(spots[j])
					var tail := PackedVector2Array()
					for k in 7:
						var uu := maxf(0.0, u - k * 0.04)
						tail.append(fs.lerp(sp, uu) - Vector2(0, sin(uu * PI) * unit * 2.2))
					ci.draw_polyline(tail, Color(0.9, 0.3, 0.05, 0.7), unit * 0.3, true)
					ci.draw_circle(tail[0], unit * 0.32, Color(0.95, 0.35, 0.05))
					ci.draw_circle(tail[0], unit * 0.18, Color(1.0, 0.9, 0.5))
	var age2 := maxf(0.0, age - 0.3)
	if age >= 0.3:
		for k in smoke:      # 검은 연기 —— 솟으며 커진다
			var sm := ds + Vector2((k - (smoke - 1) * 0.5) * unit * 0.7, -unit * (1.6 + age2 * 2.5 + (k % 3) * 0.3))
			ci.draw_circle(sm, unit * (0.45 + age2 * 0.5), Color(0.16, 0.11, 0.09, 0.4 * fade))
	if g > 0.0:
		_ellipse(ci, ds, unit * 2.0 * g, unit * 0.85 * g, Color(0.85, 0.25, 0.04, 0.4 * fade))
		_ellipse(ci, ds, unit * 1.2 * g, unit * 0.5 * g, Color(1.0, 0.55, 0.1, 0.35 * fade))
		for k in n_flame:
			var sp2: Vector2 = spots[k % spots.size()]
			var base: Vector2 = v.map(sp2) + Vector2(((k * 37) % 9 - 4) * unit * 0.12, ((k * 53) % 5 - 2) * unit * 0.06)
			var flick := 0.75 + 0.25 * sin(last_clock * 11.0 + k * 1.9)
			_flame(ci, base, unit * (1.0 + (k % 3) * 0.35) * flick * g * tall, unit * 0.26, last_clock * 7.0 + k, 0.95 * fade)


func _ult_hit(ci: CanvasItem, e: Dictionary, hit: Dictionary, t: float, age: float, col: Color, fade: float, from: Vector2) -> void:
	var at: Vector2 = hit.at
	var ds: Vector2 = v.map(at)
	var spots: Array = hit.spots
	var unit := maxf(40.0, _px(at, 130.0))      # 이 자리의 기준 크기 —— 부대 하나가 30px 남짓이라 고유기는 몇 부대를 덮게 (11/17 「티도 안 난다」)
	match str(e.vfx):
		"firestorm":      # 11/19 인물마다 다른 불 (ULT_STYLE) —— 기본은 불덩이 셋이 꼬리를 끌고 날아와 꽂힌다
			_fire_style(ci, e, hit, age, fade, from, unit)
		"thunder":      # 주변이 어두워지고 굵은 낙뢰가 잇달아 꽂힌다 —— 꽂힌 자리마다 흰 별 · 그을음
			_ellipse(ci, ds, unit * 1.5, unit * 0.7, Color(0.05, 0.07, 0.16, 0.35 * fade))
			var tv := int(e.get("sd", 0)) % 3      # 11/19 갈래 —— 0 낙뢰 다섯 · 1 굵은 벼락 하나에 잔 번개 둘 · 2 가는 번개 여덟이 빠르게
			var tn: int = [5, 3, 8][tv]
			var tgap: float = [0.13, 0.22, 0.07][tv]
			var tcol: Color = [col, Color("#ffe9a0"), Color("#d9b8ff")][tv]
			for j in tn:
				var st := j * tgap
				var big := tv == 1 and j == 0
				var u := (age - st) / (0.3 if big else 0.16)
				if u <= 0.0:
					continue
				var sp: Vector2 = ds if big else v.map(spots[j % spots.size()])
				if u < 1.0:
					var top := Vector2(sp.x + sin(j * 4.1) * unit * 1.5, maxf(40.0, sp.y - unit * 7.0))
					var flicker := 1.0 if fmod(age * 30.0 + j, 2.0) < 1.4 else 0.5
					_bolt(ci, top, sp, float(j) + at.x, tcol, (1.0 - u * 0.6) * flicker)
					if big:      # 굵은 벼락 —— 옆으로 한 줄 더, 바닥에 충격 고리
						_bolt(ci, top + Vector2(unit * 0.25, 0), sp + Vector2(unit * 0.12, 0), 7.0 + at.x, tcol, (1.0 - u * 0.6) * flicker)
						_world_ring(ci, at, 30.0 + u * 90.0, Color(tcol, 0.9 * (1.0 - u)), 3.0)
					_ellipse(ci, sp, unit * (0.7 + u * 0.4), unit * (0.28 + u * 0.15), Color(0.85, 0.92, 1.0, 0.75 * (1.0 - u)))
				_ellipse(ci, sp, unit * 0.55, unit * 0.25, Color(0.08, 0.08, 0.12, 0.55 * fade))
		"slash", "shadow":      # 11/17 사용자 「검기 짜친다」 —— 초승달 대신 일섬: 가늘고 긴 선이 순간 그어졌다 벤 자국 · 먹 튐만 남는다
			if e.vfx == "shadow":
				_ellipse(ci, ds, unit * 1.7, unit * 0.8, Color(0.05, 0.03, 0.08, 0.5 * fade))
			var sv := int(e.get("sd", 0)) % 4      # 11/19 갈래 —— 0 엇갈린 세 줄 · 1 길게 한 줄(가로) 뒤에 잔상 · 2 다섯 줄 난무(별 모양) · 3 십자 두 줄
			var glow: Color = [Color(1.0, 0.86, 0.5), Color(0.75, 0.92, 1.0), Color(1.0, 0.62, 0.45), Color(0.95, 0.95, 0.82)][sv] if e.vfx == "slash" else col
			var angs: Array = [[-0.95, 0.75, -0.25], [0.05, 0.12, -0.04], [-1.25, -0.63, 0.0, 0.63, 1.25], [-0.78, 0.78]][sv]
			var lens: float = [3.2, 5.0, 2.4, 3.8][sv]
			var gap: float = [0.09, 0.14, 0.05, 0.12][sv]
			for j in angs.size():
				var st := j * gap + (0.0 if e.vfx == "slash" else j * 0.04)
				var u := (age - st) / 0.55
				if u <= 0.0 or u >= 1.0:
					continue
				var ang: float = float(angs[j]) + sin(at.x * 0.37 + j) * (0.15 if sv == 0 else 0.04)
				var cen: Vector2 = (v.map(spots[j % spots.size()]) if sv == 0 or sv == 2 else ds) + Vector2(0, -unit * 0.25)
				_iseom(ci, cen, ang, unit * lens * (1.0 - 0.18 * j if sv == 1 else 1.0), unit * (0.13 if sv != 1 else 0.17), glow, u, j + at.x)
		"poison":      # 짙은 독안개 덩이가 퍼지며 솟는다
			var g := minf(1.0, age * 2.5)
			_ellipse(ci, ds, unit * 1.5 * g, unit * 0.65 * g, Color(0.14, 0.28, 0.06, 0.5 * fade))
			for k in 12:
				var sp: Vector2 = v.map(spots[k % spots.size()])
				var rise := fmod(age * 0.6 + k * 0.13, 1.0)
				var p := sp + Vector2(sin(age * 1.5 + k) * unit * 0.4, -rise * unit * 2.2)
				ci.draw_circle(p, unit * (0.3 + rise * 0.35) * g, Color(col.darkened(0.35), 0.7 * fade * (1.0 - rise * 0.6)))
				ci.draw_arc(p, unit * (0.3 + rise * 0.35) * g, 0, TAU, 14, Color(0.08, 0.16, 0.04, 0.45 * fade * (1.0 - rise)), 1.5, true)
		"illusion":      # 보랏빛 소용돌이 세 갈래가 적진을 감는다
			_ellipse(ci, ds, unit * 1.5, unit * 0.7, Color(col.darkened(0.4), 0.4 * fade))
			var iv := int(e.get("sd", 0)) % 3      # 11/19 갈래 —— 0 세 갈래 소용돌이 · 1 거꾸로 도는 다섯 갈래(가늘게) · 2 두 갈래 큰 소용돌이 + 맥동 고리
			var arms: int = [3, 5, 2][iv]
			var spin: float = [4.0, -5.5, 2.8][iv]
			if iv == 2:
				for rk in 3:
					var ru := fmod(age * 0.9 + rk / 3.0, 1.0)
					_world_ring(ci, at, 20.0 + ru * 110.0, Color(col.lightened(0.35), 0.8 * fade * (1.0 - ru)), 2.5)
			for arm in arms:
				var pts := PackedVector2Array()
				for k in 22:
					var u := float(k) / 21.0
					var ang := age * spin + arm * TAU / arms + u * (4.5 if iv != 1 else 3.0)
					pts.append(ds + Vector2(cos(ang), sin(ang) * 0.5) * unit * 1.5 * (1.0 - u * 0.85))
				ci.draw_polyline(pts, Color(INK, 0.4 * fade), 9.0, true)
				ci.draw_polyline(pts, Color(col.lightened(0.2), 0.95 * fade), 5.0, true)
		"charge":      # 실제로 달려와 부딪힌 앞줄 —— 흙구름이 터지고 파편이 튄다 (달리는 동안은 _ult_dash)
			var a_sq: Squad = v.field.squads.get(e.a)
			var src: Vector2 = a_sq.pos if a_sq != null else from
			var dirw := (at - src).normalized() if not (at - src).is_zero_approx() else Vector2.RIGHT
			var side := dirw.orthogonal()
			var hit_at: Vector2 = at - dirw * float(hit.get("hd", 20.0))
			var hs: Vector2 = v.map(hit_at)
			var u2 := clampf(age / 0.9, 0.0, 1.0)
			var front: Vector2 = (v.map(hit_at + dirw * 10.0) - hs).normalized()
			for k in 7:
				var p: Vector2 = v.map(hit_at + side * (k - 3) * float(hit.get("hw", 24.0)) * 0.3) + Vector2(0, -u2 * unit * 0.5 * (1 + k % 2))
				var rr := unit * (0.3 + u2 * 0.45)
				ci.draw_circle(p, rr, Color(0.8, 0.71, 0.52, 0.85 * (1.0 - u2)))
				ci.draw_arc(p, rr, PI * 0.9, PI * 2.1, 10, Color(INK, 0.5 * (1.0 - u2)), 2.0, true)
			var deb := PackedVector2Array()
			for k in 10:
				var dd := dirw.rotated(-1.2 + k * 0.27)
				var p0: Vector2 = v.map(hit_at + dd * (8.0 + u2 * 40.0))
				deb.append(p0)
				deb.append(p0 + (v.map(hit_at + dd * 20.0) - hs).normalized() * 5.0)
			ci.draw_multiline(deb, Color(INK, 0.85 * (1.0 - u2)), 3.0, true)
			for k in 14:      # 튀어 오르는 흙덩이 —— 돌진 방향으로 포물선
				var r1 := fposmod(sin(at.x * 0.1 + k * 12.9898) * 43758.5, 1.0)
				var r2 := fposmod(sin(at.y * 0.1 + k * 78.233) * 24634.6, 1.0)
				var uk := clampf(age / (0.45 + r2 * 0.2), 0.0, 1.0)
				if uk >= 1.0:
					continue
				var dk := dirw.rotated((r1 - 0.5) * 1.8)
				var p0: Vector2 = v.map(hit_at + dk * (6.0 + uk * (40.0 + r2 * 50.0)))
				ci.draw_circle(p0 - Vector2(0, sin(uk * PI) * unit * (0.5 + r1 * 0.8)), 1.6 + r2 * 2.2, Color(0.3, 0.22, 0.14, 0.9 * (1.0 - uk * 0.5)))
		"roar", "whirlwind":      # 맞은 자리에 흙먼지
			var u3 := clampf(age / 0.8, 0.0, 1.0)
			for k in 4:
				var p: Vector2 = v.map(spots[k]) + Vector2(0, -u3 * unit * 0.4)
				ci.draw_circle(p, unit * (0.3 + u3 * 0.45), Color(0.78, 0.69, 0.5, 0.6 * (1.0 - u3)))
		_:
			_world_ring(ci, at, 15.0 + t * 50.0, Color(col, 0.8 * fade), 2.0)

## 11/17 화살비 —— 사용자 참고 「영웅」의 하늘을 덮는 화살 떼. 수백 발의 먹빛 화살이 시전자 뒤에서 높이 솟아 포물선으로 적진에 쏟아지고, 꽂힌 화살이 남는다.
## 선 묶음(draw_multiline) 한두 번으로 그린다 —— 화살 수가 많아도 그리기 호출은 늘지 않는다
const STORM_ARROWS := 380      # 11/17 사용자 「화살비 너무 과함」 900 → 380
func _arrow_storm(ci: CanvasItem, e: Dictionary, age: float) -> void:
	var hits: Array = e.hits
	if hits.is_empty():
		return
	var a_sq: Squad = v.field.squads.get(e.a)
	var from: Vector2 = e.from
	var aw: float = a_sq.hw if a_sq != null else 24.0
	var fade := 1.0 - smoothstep(float(e.end) - float(e.start) - 0.5, float(e.end) - float(e.start), age)
	var n := clampi(STORM_ARROWS / hits.size(), 60, 160)
	var flying := PackedVector2Array()
	var flying_far := PackedVector2Array()
	var stuck := PackedVector2Array()
	var sky := float(v.size.y) * 0.2      # 포물선 꼭대기 —— 화면 1/5 쯤
	for hi in hits.size():
		var hit: Dictionary = hits[hi]
		var r_ax: Vector2 = hit.right
		var f_ax: Vector2 = hit.fwd
		for k in n:
			var r1 := fposmod(sin(k * 12.9898 + hi * 78.233) * 43758.5453, 1.0)
			var r2 := fposmod(sin(k * 39.3468 + hi * 11.135) * 24634.6345, 1.0)
			var r3 := fposmod(sin(k * 73.156 + hi * 52.235) * 12573.9187, 1.0)
			var r4 := fposmod(sin(k * 5.7121 + hi * 91.71) * 35711.1773, 1.0)
			var launch: Vector2 = v.map(from + Vector2(r2 * 2.0 - 1.0, r3 * 2.0 - 1.0) * aw * 0.8) + Vector2((r1 * 2.0 - 1.0) * 90.0, 0)      # 넓은 띠에서 쏘아 하늘을 덮는다
			var land_w: Vector2 = hit.at + r_ax * (r3 * 2.0 - 1.0) * float(hit.hw) * 0.95 + f_ax * (r4 * 2.0 - 1.0) * float(hit.hd) * 0.8
			var land: Vector2 = v.map(land_w)
			var t0 := r1 * 0.3            # 쏘는 시차 —— 두어 물결로 쏟아진다
			var dur := 0.34 + r4 * 0.1
			var u := (age - t0) / dur
			if u <= 0.0:
				continue
			var hgt := sky * (0.55 + r2 * 0.85)
			if u < 1.0:
				var p := launch.lerp(land, u) - Vector2(0, hgt * 4.0 * u * (1.0 - u))
				var tang := (land - launch) - Vector2(0, hgt * (4.0 - 8.0 * u))
				var dir := tang.normalized()
				var ln := 9.0 + r1 * 6.0
				var arr := flying if (k % 3) != 0 else flying_far
				arr.append(p - dir * ln)
				arr.append(p)
			else:      # 꽂힌 화살 —— 떨어지던 기울기 그대로 짧게
				var dir2 := ((land - launch) + Vector2(0, hgt * 4.0)).normalized()
				stuck.append(land - dir2 * 6.0)
				stuck.append(land)
	if not flying_far.is_empty():
		ci.draw_multiline(flying_far, Color(0.16, 0.18, 0.24, 0.55 * fade), 1.0, true)
	if not flying.is_empty():
		ci.draw_multiline(flying, Color(0.10, 0.11, 0.15, 0.9 * fade), 1.4, true)
	if not stuck.is_empty():
		ci.draw_multiline(stuck, Color(0.12, 0.10, 0.08, 0.85 * fade), 1.2, true)


## 돌진 중 —— 달리는 부대 뒤로 부대 폭만큼 속도선, 발밑에서 뒤로 날리는 흙먼지 (부대가 실제로 움직인다)
func _ult_dash(ci: CanvasItem, e: Dictionary, age: float) -> void:
	var a_sq: Squad = v.field.squads.get(e.a)
	if a_sq == null or not a_sq.alive:
		return
	var src: Vector2 = a_sq.pos
	var from: Vector2 = e.from
	var dirw := (src - from).normalized() if src.distance_to(from) > 4.0 else a_sq.fwd
	var side := dirw.orthogonal()
	var fade := 1.0 if (v.field.squads.get(e.a) != null and v.field.squads.get(e.a).moving) or age < 0.3 else 0.0
	var streaks := PackedVector2Array()
	for k in 11:
		var off := (float(k) / 10.0 * 2.0 - 1.0) * a_sq.hw * 0.95
		var ln := 50.0 + fmod(k * 37.0, 40.0)
		var head := src + side * off - dirw * (a_sq.hd() * 0.6 + fmod(k * 17.0, 14.0))
		streaks.append(v.map(head))
		streaks.append(v.map(head - dirw * ln))
	ci.draw_multiline(streaks, Color(INK, 0.35 * fade), 4.5, true)
	ci.draw_multiline(streaks, Color(PAPER, 0.85 * fade), 2.4, true)
	var unit := maxf(24.0, _px(src, 80.0))
	for k in 5:
		var w := src - dirw * (a_sq.hd() + 10.0 + k * 16.0) + side * sin(k * 2.3 + age * 3.0) * a_sq.hw * 0.6
		ci.draw_circle(v.map(w), unit * (0.22 + k * 0.06), Color(0.78, 0.69, 0.5, 0.6 * fade * (1.0 - k * 0.15)))


## 효과 그림 하나 —— 빛나는 그림(GLOW_SPR)은 더하기 층으로 미루고, 연기 · 그을음 같은 어두운 그림은 바로 그린다
func _spr(ci: CanvasItem, nm: String, c: Vector2, sz: float, col: Color, rot := 0.0, stretch := Vector2.ONE) -> void:
	if glow_effects != null and GLOW_SPR.has(nm):
		if _glow_q.size() < 900:
			_glow_q.append([nm, c, sz, Color(col.r * GLOW_BOOST, col.g * GLOW_BOOST, col.b * GLOW_BOOST, col.a), rot, stretch])
		return
	v._spr_at(ci, nm, c, sz, col, rot, stretch)


## 위세 · 격려(aura) —— 시전자에게서 금빛 햇살이 퍼지고 바닥에 금 고리가 남는다
## 11/19 인물 갈래(sd)로 햇살 수 · 도는 방향 · 빛깔이 다르다 (위세 계열 열한 명이 모두 같아 보였다)
func _sunburst(ci: CanvasItem, from: Vector2, age: float, col: Color, fade: float, sd := 0) -> void:
	var fs: Vector2 = v.map(from)
	var r := maxf(60.0, _px(from, 220.0)) * minf(1.0, age * 3.0)
	if r < 2.0:      # 11/19 첫 프레임(반지름 0)의 찌그러진 삼각형 열여섯이 「Invalid polygon data」 오류를 냈다 —— 위세 고유기마다 오류 16줄
		return
	var rays: int = [16, 12, 20, 8][sd % 4]
	var spin: float = [0.6, -0.9, 0.35, 1.4][sd % 4]
	var tint: Color = [Color(1.0, 0.82, 0.3), Color(0.72, 0.9, 1.0), Color(0.62, 1.0, 0.72), Color(1.0, 0.62, 0.4)][(sd / 4) % 4]
	for k in rays:
		var ang := k * TAU / rays + age * spin
		var w := 0.14 if k % 2 == 0 else 0.08
		var ln := r * (1.0 if k % 2 == 0 else 0.7)
		var tip := fs + Vector2(cos(ang), sin(ang) * 0.55) * ln
		var l := fs + Vector2(cos(ang - w), sin(ang - w) * 0.55) * ln * 0.25
		var rr := fs + Vector2(cos(ang + w), sin(ang + w) * 0.55) * ln * 0.25
		ci.draw_polygon(PackedVector2Array([l, tip, rr]), PackedColorArray([Color(tint, 0.95 * fade), Color(tint, 0.1 * fade), Color(tint, 0.95 * fade)]))
	_ellipse(ci, fs, r * 0.28, r * 0.15, Color(1, 0.95, 0.7, 0.6 * fade))
	for j in 2:
		var u := clampf((age - j * 0.2) / 0.8, 0.0, 1.0)
		if u > 0.0 and u < 1.0:
			_world_ring(ci, from, 30.0 + u * 180.0, Color(col, (1.0 - u) * 0.9), 5.0 - j * 2.0)


## 일섬 —— 가운데 c, 각 ang, 길이 ln, 가장 굵은 폭 w. u 0~0.22 에 한쪽 끝에서 반대 끝으로 번쩍 그어지고 → 머리카락 굵기의 먹 자국으로 식으며 먹이 튄다
func _iseom(ci: CanvasItem, c: Vector2, ang: float, ln: float, w: float, glow: Color, u: float, seed: float) -> void:
	var d := Vector2(cos(ang), sin(ang) * 0.6).normalized()
	var n := d.orthogonal()
	var a := c - d * ln * 0.5
	var b := c + d * ln * 0.5
	var draw_u := minf(1.0, u / 0.22)
	var head := a.lerp(b, draw_u)
	if u < 0.45 and a.distance_squared_to(head) > 9.0:      # 번쩍 —— 뾰족한 마름모 빛 (바깥 빛 + 흰 심). 11/19 길이 0 인 첫 프레임은 건너뛴다 (다각형 오류)
		var k := maxf(0.05, 1.0 if u < 0.22 else 1.0 - (u - 0.22) / 0.23)
		var mid := a.lerp(head, 0.55)
		ci.draw_colored_polygon(PackedVector2Array([a, mid + n * w * 2.2 * k, head, mid - n * w * 2.2 * k]), Color(glow, 0.45 * k))
		ci.draw_colored_polygon(PackedVector2Array([a, mid + n * w * k, head, mid - n * w * k]), Color(1, 1, 1, 0.95 * k))
	if u > 0.15:      # 벤 자국 —— 가는 먹 선이 남았다 흐려진다
		var cut := clampf(1.0 - (u - 0.15) / 0.85, 0.0, 1.0)
		ci.draw_line(a.lerp(b, 0.06), a.lerp(b, 0.94), Color(INK, 0.85 * cut), 1.6, true)
		for k2 in 6:      # 먹 튐 —— 선 가운데 둘레로 작은 방울
			var r1 := fposmod(sin(seed * 7.1 + k2 * 3.3) * 437.5, 1.0)
			var r2 := fposmod(sin(seed * 2.9 + k2 * 5.7) * 913.1, 1.0)
			var p := c + d * (r1 - 0.5) * ln * 0.6 + n * (r2 - 0.5) * w * 9.0 * minf(1.0, (u - 0.15) * 4.0)
			ci.draw_circle(p, 1.0 + r2 * 1.8, Color(INK, 0.75 * cut))


## 11/17 후열 책략 평타 —— 병종 색 구슬이 꼬리를 끌며 날아가 맞는 자리에서 번쩍인다 (판정 · 수치 무관)
const SPELL_COL := {"책사": Color(1.0, 0.55, 0.18), "술사": Color(0.75, 0.5, 1.0), "모사": Color(0.55, 0.8, 1.0), "유생": Color(0.5, 0.95, 0.7)}
func _spell_orb(ci: CanvasItem, shot: Dictionary, id: int, start: Vector2, end: Vector2, spread: Vector2, t: float, height: float) -> void:
	var col: Color = SPELL_COL.get(str(shot.get("tag", "")), EMBER)
	var tail := PackedVector2Array()
	for k in 6:
		var tt := maxf(0.0, t - k * 0.035)
		var w: Vector2 = start.lerp(end + spread, tt)
		tail.append(v.map(w) - Vector2(0, 8.0 + sin(tt * PI) * height * 1.6 * v.depth_scale(w)))
	ci.draw_polyline(tail, Color(INK, 0.35), 6.0, true)
	ci.draw_polyline(tail, Color(col, 0.75), 3.5, true)
	ci.draw_circle(tail[0], 5.0, Color(INK, 0.6))
	ci.draw_circle(tail[0], 4.0, col)
	ci.draw_circle(tail[0], 2.0, Color(1, 1, 1, 0.95))
	if t > 0.86:      # 맞는 자리 —— 납작한 섬광 고리
		var u := (t - 0.86) / 0.14
		var hit: Vector2 = v.map(end + spread)
		ci.draw_arc(hit, 6.0 + u * 12.0, 0, TAU, 16, Color(col, 1.0 - u), 2.5, true)
