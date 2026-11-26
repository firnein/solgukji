extends Control

const FormationMotion = preload("res://scripts/field/painted_formation.gd")
const CasterFx = preload("res://scripts/field/painted_caster.gd")
const MythUltimateMotion = preload("res://scripts/field/myth_ultimate_motion.gd")
const KitFx = preload("res://scripts/field/painted_kit.gd")
var caster = CasterFx.new(self)     # 11/25 책략계 기여 표시 (버프 · 디버프 · 천문 · 혼란 · 위세 · 기술 발동 · 책략 타격)
var kit = KitFx.new(self)           # 11/27 장수 키트 Q · W · E · R · P 발동 표시 (칸 색 고리 · 번쩍임 · 맞은 표식)
var caster_stats: Dictionary:      # 점검용 (tests/caster_vis_shot)
	get:
		return caster.stats
var v
var atlas: Texture2D
var cells: Array[AtlasTexture] = []
var walk_meshes := {}
var formations := {}
var visible_soldiers: Array = []      # 점검용 사전 목록 (keep_dicts 일 때만 채운다) —— 그리기는 아래 묶음 배열을 쓴다
## 11/19 프레임: 병사마다 키 11개짜리 사전을 만들고 람다로 정렬하던 것이 삽화 그리기의 절반이었다 ——
## 인형 값은 묶음 배열 한 줄(FIG_W 칸)에, 깊이 순서는 정수 키(화면 y · 번호) 정렬로. 그리는 모양 · 순서는 그대로
const FIG_W := 12              # x, y, 키, 칸, 투명, 기울기, 걸음 세기, 보폭, 피격, 좌우 뒤집기, 매복 그늘(− 면 등장 번쩍), 모양(병사 단계 0~5 + 신화 시트면 8)
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
var burn_fronts := {}        # 실제 화상 부여 순간과 불이 들어온 방향
var fire_paths: Array = []   # 실제 spread 사건만 남기는 부대 사이 확산 경로
const MAX_FIRE_PATHS := 1
const FIRE_PATH_LIFE := 1.15
var flames := {}
var peerless := {}
var contacts: Array = []
var bodies: Array = []
var volleys: Array = []
var ults: Array = []          # 11/17 고유기 이펙트 —— 삽화 화면에서는 type2 의 2D 연출이 꺼져 있어 여기서 그린다
const MAX_ULTS := 6
# 11/22 매복 · 우회 표현 —— 좌우 가장자리 숲 · 바위 지형(Type2View.cover_target)을 지나는 부대를 그늘 속처럼 흐릿하게, 나오면 짧게 등장 연출.
# 화면 전용 —— 판정 · 위치와 무관 (부대 자리만 읽는다)
var cover := {}                # 부대 key -> 그늘 (0~1, 부드럽게 따라간다)
var _hid := {}                 # 부대 key -> 그늘에 깊이 들어간 적이 있다 (나올 때 등장 연출)
var reveals: Array = []        # {key, t0} —— 등장 연출
var _bared := {}               # 부대 key -> 마지막으로 적과 맞닿은 시각 (visual_time)
const COVER_HOLD := 3.0
const STEALTH_COVER := 0.9     # 은신 상태의 그늘 깊이 (0~1)
const COVER_IN := 1.6          # 그늘로 드는 빠르기 (초당)
const COVER_OUT := 3.0         # 나오는 빠르기
const REVEAL_LIFE := 1.0
const REVEAL_FLASH := 0.35
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
const TAGS := ["창병", "기병", "궁병", "도적", "책사", "유생", "", "모사"]      # 아틀라스 칸 순서 (진영마다 8칸) —— 6번은 옛 술사 그림 자리라 비워 둔다 (11/27 술사 병종 삭제, 모사가 7번 칸을 그대로 쓰게)
const STRIDE_FRAMES := 12
static var batch_rendering := true
static var action_frames_on := true # 점검용으로 끄면 같은 인형 수로 이전 정지 원화와 비교한다.
static var tier_fx := true     # 11/24 점검용 (tests/tier_sprite_shot --tierfx=0) —— 끄면 등급 차등(크기 · 테두리 빛 · 기운 · 군기) · 신화 시트 없이 (전후 비교)
var action_frames_ready := false
var myth_ready := false        # 11/24 신화 시트를 읽었나 (painted_batch 가 셰이더에 넘기는 조건과 같다)
## 11/24 사용자 「신화는 초상화 일러스트 참고해서 스프라이트」 —— 신화 부대에 그 인물의 장수 인형 하나 (초상을 IP-Adapter 로 참조해 뽑은 그림,
## tools/scripts/hero_gen.py → make_myth_heroes.py → assets/war_painting/myth_heroes_v1.png + data/myth_heroes.json). 병사와 같은 묶음 · 깊이 순서
static var heroes_on := true   # 점검용 (tests/tier_sprite_shot --heroes=0) —— 끄면 장수 인형 없이 (전후 비교)
var hero_ready := false
var _hero_cells := {}          # 인물 이름 -> 칸 번호 (data/myth_heroes.json)
var _immortal_hero_cells := {}
var _transcendent_hero_cells := {}
var _hero_fill := PackedFloat32Array()      # 칸 번호 -> 인형 키 / 칸 키 (발 0.97 기준)
var _hero_scale := PackedFloat32Array()
var _hero_of := {}             # 카드 id -> 칸 번호 (-1 = 없음)
var _hero_falls := {}
var _hero_poses := 1
var hero_feet := {}
var hero_h := {}               # 부대 key -> 이번 그리기의 장수 인형 키 (화면 px) —— 머리 위 칸 딱지 · 시전 고리 크기 (11/27 키트)
const HERO_RECOIL_TIME := 0.38
var batch: Node2D
var top_effects: Node2D
var glow_effects: Node2D
var _glow_q: Array = []
const GLOW_SPR := ["flame_02", "flame_03", "flame_04", "fire_01", "fire_02", "spark_01", "spark_04", "light_02", "star_06",
	"magic_01", "magic_03", "magic_05", "slash_01", "slash_02", "slash_03", "twirl_01", "circle_03", "circle_05", "trace_01", "muzzle_02",
	"spark_05", "spark_06", "star_04", "star_07", "star_08", "scratch_01", "slash_04", "trace_02", "trace_04", "twirl_02", "twirl_03",
	"circle_02", "light_01", "light_03", "magic_02", "magic_04", "muzzle_01", "muzzle_03"]      # 11/23 기술 · 잔기술 이펙트 (_draw_skill_fx)
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
	if ResourceLoader.exists("res://assets/war_painting/troops_action_blue_v1.png") and ResourceLoader.exists("res://assets/war_painting/troops_action_red_v1.png"):
		batch.action_blue = load("res://assets/war_painting/troops_action_blue_v1.png")
		batch.action_red = load("res://assets/war_painting/troops_action_red_v1.png")
		action_frames_ready = batch.action_blue != null and batch.action_red != null
		if ResourceLoader.exists("res://assets/war_painting/troops_myth_blue_v1.png") and ResourceLoader.exists("res://assets/war_painting/troops_myth_red_v1.png"):
			batch.myth_blue = load("res://assets/war_painting/troops_myth_blue_v1.png")      # 11/24 신화 부대 전용 (tools/scripts/make_myth_troops.py)
			batch.myth_red = load("res://assets/war_painting/troops_myth_red_v1.png")
			myth_ready = batch.myth_blue != null and batch.myth_red != null and batch.myth_blue.get_size() == batch.action_blue.get_size() and batch.myth_red.get_size() == batch.action_red.get_size()
		_load_heroes()
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
	_hero_falls.clear()
	hero_feet.clear()
	hero_h.clear()
	contacts.clear()
	volleys.clear()
	ults.clear()
	skill_fx_q.clear()
	_hero_skill_motion.clear()
	_glow_q.clear()
	last_clock = -1.0
	visual_time = 0.0
	motion_dt = 0.0
	charges.clear()
	rallies.clear()
	fire_seas.clear()
	burn_fronts.clear()
	fire_paths.clear()
	flames.clear()
	peerless.clear()
	cover.clear()
	_hid.clear()
	_bared.clear()
	reveals.clear()
	caster.reset()
	kit.reset()

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
				var count := mini(form.count, 8) if kind == "volley" else 1 # 책략 동작은 원화로 보이고 투사체는 한 줄만 남긴다.
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

## group —— battle_view 의 사건 묶음 (skill · who …). 없어도 된다 (점검)
func play_event(event: Dictionary, ultimate, updates: Array = [], group: Dictionary = {}) -> void:
	var now: float = v.field.clock
	var source: Squad = v.field.squads.get(event.get("a", ""))
	var target: Squad = v.field.squads.get(event.get("f", ""))
	var direct := source != null and target != null and source.camp != target.camp
	var damage: bool = direct and event.get("fx", "") in ["phys", "int"] and float(event.get("n", 0)) > 0.0
	var power := _hit_power(source, target, event, ultimate) if damage else 0.0
	var magic: bool = damage and event.get("fx") == "int"
	if magic and ultimate == null and (str(group.get("skill", "")) != "" or event.get("crit", false)):
		power = maxf(power, MAGIC_PUSH)      # 11/25 책략 기술 · 치명타는 대열이 밀린다 (평타는 단계 세기 그대로)
	_record_burn(event)
	caster.on_event(event)
	if damage:
		_record_contact(source, target, power, magic)
		if magic:
			var dir := _formation(source).center.direction_to(_formation(target).center)
			caster.add_spark(_formation(target).center - dir * target.edge(dir) * 0.6, source.tag)
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
	return not _hero_falls.is_empty() or bodies.any(func(body): return visual_time < float(body.start) + float(body.duration))

func _sync_troops(updates: Array, source: Squad, target: Squad, power: float, quiet: bool) -> void:
	for update in updates:
		var sq: Squad = v.field.squads.get(update.key)
		if sq == null:
			continue
		var form := _formation(sq)
		var ratio := clampf(float(update.troops) / maxf(1.0, sq.max), 0.0, 1.0)
		var solo_hero := _shows_hero(sq)
		form.ratio = ratio
		ratios[sq.key] = form.ratio
		var wanted := ceili(form.ratio * form.capacity)
		if quiet or wanted > 0:
			_hero_falls.erase(sq.key)
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
			if not quiet and not solo_hero:
				_spawn_body(sq, form, id, direction, force if n < launch_count else 0.0, n)
			form.remove_soldier(id)
		if wanted == 0 and not quiet and solo_hero:
			_hero_falls[sq.key] = {"at": form.center, "dir": direction,
				"form": form, "start": visual_time, "mirror": not form.facing_right}

func _spawn_body(sq: Squad, form: FormationMotion, id: int, direction: Vector2, power: float, order: int) -> void:
	# 무너진 병사는 전열 안에서 넘어지고 밀린다. 고유기도 병사를 공중으로 날리지 않는다.
	var flying := false
	var seed := float(id * 13 + form.serial * 7 + int(sq.row.slot) * 3)
	var spread := sin(seed * 1.7) * 0.28
	var travel := 8.0 + minf(power, 2.0) * 7.0
	var duration := 0.38 + minf(power, 2.0) * 0.05
	var facing := 1.0 if sin(seed) > 0.0 else -1.0
	bodies.append({"at": form.feet[id], "direction": direction.rotated(spread),
		"start": visual_time + minf(0.12, order * 0.027), "duration": duration,
		"distance": travel, "height": (40.0 + power * 30.0) if flying else 0.0,
		"turn": facing * (1.25 + power * 0.24), "h": _figure_height(sq, form),
		"cell": maxi(0, TAGS.find(sq.tag)) + (0 if sq.camp == "A" else 8),
		"flying": flying, "end": visual_time + duration + 2.6, "mirror": (not form.facing_right if sq.camp == "A" else form.facing_right)})
	if bodies.size() > MAX_BODIES:
		bodies.pop_front()

const MAGIC_PUSH := 1.0
func _record_contact(source: Squad, target: Squad, power: float, magic: bool) -> void:
	var from := _formation(source)
	var form := _formation(target)
	var direction := from.center.direction_to(form.center)
	if direction.is_zero_approx():
		direction = Vector2.from_angle(from.heading)
	var at := form.center - direction * target.edge(direction)
	if _shows_hero(target) and visual_time >= form.hero_hurt_at + HERO_RECOIL_TIME:
		form.hero_hurt_at = visual_time
		form.hero_hurt_power = power
		form.hero_hurt_dir = direction
		form.hero_hurt_mirror = not form.facing_right
	if (not magic and source.cls != "ranged") or power >= (MAGIC_PUSH if magic else 1.5):      # 11/25 책략 타격은 1.0 부터 대열이 밀린다 (예전 1.5 —— 책략은 거의 닿지 않았다)
		form.receive_impact(at, direction, power)
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

	if source.cls == "melee" or source.cls == "cav":
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
	_formation(target).receive_impact(_formation(target).center - direction * target.edge(direction), direction, 0.55 if brace else 1.9)

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
	for key in _hero_falls.keys():
		if visual_time >= float(_hero_falls[key].start) + HERO_FALL_TIME:
			_hero_falls.erase(key)
	fire_paths = fire_paths.filter(func(path): return visual_time - float(path.start) < FIRE_PATH_LIFE)
	for key in burn_fronts.keys():
		var burning: Squad = v.field.squads.get(key)
		if burning == null or not burning.alive or not burning.statuses.has("burn"):
			burn_fronts.erase(key)
	contacts = contacts.filter(func(h): return visual_time < h.end)
	volleys = volleys.filter(func(shot): return last_clock < shot.end)
	ults = ults.filter(func(u): return last_clock < float(u.end) and last_clock >= float(u.start) - 5.0)
	if not skill_fx_q.is_empty():
		skill_fx_q = skill_fx_q.filter(func(s): return last_clock < float(s.end) and last_clock >= float(s.start) - 5.0)
	caster.prune(last_clock)
	kit.prune(last_clock)
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
		_cover_step(sq)
	if not reveals.is_empty():
		reveals = reveals.filter(func(r): return visual_time - float(r.t0) < REVEAL_LIFE)
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

const BOSS_FIG := 1.7
const FIGURE_SCALE := 1.4 # 최소 14px였던 병사는 약 20px로. 발 위치·대열 간격은 유지한다.

## 11/24 사용자 「책략계 스프라이트가 유독 크다」 —— 인형 키를 그 병종의 열 수(지원 3 · 궁병 5 · 보병 6)로 잰 간격에 맞추다 보니
## 같은 폭의 부대라도 열이 적은 지원 병종은 간격 제한을 안 받아 기본 키(60)를 그대로 받았다 (보병은 간격 때문에 작아진다).
## 걷는 병종은 모두 보병 열 수로 간격을 잰다 (기병은 말이 있어 제 열 수 그대로). 책략계 원화는 넓은 소매 · 도포로 칸을 더 채워(불투명 넓이 1.25 배) 조금 줄인다
const SUPPORT_TAGS := ["책사", "유생", "모사"]
const SUPPORT_ART := 0.9
## 11/24 사용자 「같은 병종이라도 등급에 따라 차등, 좀 더 강해 보여야」 —— 병사 단계(Type2View.grade_of: 등급 · 시작 병력 · 기인)별 인형 키 배율
##   0 잡병(고급 이하) · 1 정병(희귀) · 2 정예(전설) · 3 근위(초월 · 기인) · 4 철위(불멸) · 5 신병(신화). 색 · 테두리 빛 · 기운 · 군기는 셰이더(painted_batch.gdshader)가 단계로 그린다
const GRADE_FIG := [0.9, 0.96, 1.03, 1.09, 1.15, 1.2]
const GRADE_BANNER := [0.9, 1.0, 1.06, 1.14, 1.24, 1.34]      # 군기 키 상한 배율
const MYTH_TIER := 8           # 이 등급 이상만 신화 전용 시트

func _grade(sq: Squad) -> int:
	if not tier_fx:
		return 1
	if v != null and v.has_method("_g"):
		return clampi(int(v._g(sq)), 0, 5)
	return clampi(sq.tier - 3, 0, 5)

## 셰이더에 넘기는 모양 값 —— 병사 단계 + 신화 시트(8)
func _style(sq: Squad, grade: int) -> float:
	return float(grade + (8 if tier_fx and sq.tier >= MYTH_TIER and action_frames_ready and myth_ready else 0))

func _figure_height(sq: Squad, form: FormationMotion) -> float:
	var scale: float = _pk(form.center)
	var nominal := (72.0 if form.cavalry else 60.0) * scale
	var gaps := form.cols - 1
	if not form.cavalry:
		gaps = (6 if sq.hw >= 48.0 else 4) - 1      # painted_formation._init 의 보병 열 수
	var horizontal := 2.0 * form.half_width / maxf(1, gaps) * scale
	var h := clampf(minf(nominal, horizontal / 0.58), 14.0, 46.0) * FIGURE_SCALE
	if sq.tag in SUPPORT_TAGS:
		h *= SUPPORT_ART
	h *= float(GRADE_FIG[_grade(sq)])
	if bool(sq.row.get("boss", false)):      # 토벌 총대장 —— 병사 인형을 크게 (그림만, 자리 · 충돌은 그대로)
		h *= BOSS_FIG
	return h

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
	hero_feet.clear()
	hero_h.clear()
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
		if _hero_falls.has(sq.key):
			_collect_hero_fall(sq, _hero_falls[sq.key])
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
			if form != null and not _shows_hero(sq):
				if batch_rendering:
					_mark_batch(sq, form)
				else:
					_draw_formation_mark(sq, form)
			if form != null and form.count > 0 and sq.alive and caster.has_aura(sq):
				caster.aura_marks(sq, form)      # 11/25 위세 —— 늘 켜진 진영 효과를 가진 부대 발밑 금빛 원
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
	_draw_fire_paths(ci)
	for sq: Squad in v.field.order:
		if sq.fade > 0.01:
			_draw_status(sq, ci)
	_draw_volleys(ci)
	_draw_links(ci)
	_draw_mythic_actions(ci)
	_draw_reveals(ci)
	_draw_skill_fx(ci)
	caster.draw(ci)
	_draw_ults(ci)
	kit.draw(ci)      # 11/27 키트 칸 표시 —— 고유기 이펙트 위에 (R 고리 · 맞은 표식이 묻히지 않게)

func _collect_figures(sq: Squad, form: FormationMotion) -> void:
	var h := _figure_height(sq, form)
	var grade := _grade(sq)
	var style := _style(sq, grade)
	var cell := maxi(0, TAGS.find(sq.tag)) + (0 if sq.camp == "A" else 8)
	var action_base := 32 + maxi(0, TAGS.find(sq.tag)) * 4 + (0 if sq.camp == "A" else 32)
	var animated := action_frames_ready and action_frames_on and batch_rendering
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
	if animated:
		mirror = not form.facing_right # 새 동작 원화는 양쪽 모두 공격이 화면 오른쪽으로 뻗는다.

	var attacking := form.action_kind == "melee" and visual_time - form.last_action < 0.55
	var eligible := (form.contact or attacking) and sq.state != "flee" and target != null and target.alive
	var ranged: bool = form.action_kind == "volley" or form.action_kind == "spell"
	var bow_base := visual_time - form.last_action      # 활 당김은 쏜 뒤 0.5초 안에만 보인다 (그 뒤는 0)
	var sway := 0.035 if form.cavalry else 0.012
	var fade_sq := sq.fade
	var cv := cover_of(sq)
	fade_sq *= 1.0 - 0.35 * maxf(cv, 0.0)
	if _shows_hero(sq):
		if form.count > 0:
			_collect_hero(sq, form, _hero_index(sq), h, axis, not form.facing_right, eligible, ranged, bow_base, fade_sq, cv, sway)
		return
	var front_ids: Array = form.nearest_living(form.center + direction * sq.edge(direction), form.cols) if eligible else []
	var scr: PackedVector2Array = _scr.get(sq.key, PackedVector2Array())
	if scr.size() != form.capacity:
		scr.resize(form.capacity)
	var fleeing := sq.state == "flee"
	var has_front := not front_ids.is_empty()
	var slot_f := float(sq.row.slot)
	var dizzy: bool = not fleeing and sq.statuses.has("confuse")      # 11/25 혼란 —— 병사들이 제자리에서 비틀거린다 (화면만)
	var dizzy_px := h * 0.05
	for id in form.capacity:
		if form.alive[id] == 0:
			continue
		var p: Vector2 = _pm(form.feet[id])
		scr[id] = p
		var p0 := p      # 11/18 발은 _place 에서 이미 접촉선 안 —— 찌르기 · 밀림으로 옮겨진 인형만 다시 맞춘다
		var tilt := 0.0
		tilt -= axis.x * minf(0.2, form.recoil[id].length() / maxf(form.row_gap, 1.0) * 0.5)
		var gait: float = form.gait[id]
		var stride: float = form.strides[id]
		var hit := 0.0
		var pose := 0
		if not fleeing:
			if has_front and front_ids.has(id):
				# 11/19 찌르기 곡선은 앞줄만, 그것도 친 지 0.4초 안일 때만 잰다 (예전엔 모든 병사가 매 프레임 smoothstep 네 번)
				var age := visual_time - form.strike_at[id]
				if age >= 0.0 and age < 0.34:
					pose = 1 if age < 0.12 else 2
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
				if bow_age >= 0.0 and bow_age < 0.4:
					pose = 1 if bow_age < 0.12 else 2
				var bow := smoothstep(0.0, 0.1, bow_age) * (1.0 - smoothstep(0.15, 0.32, bow_age))
				tilt -= axis.x * bow * 0.065
		var hurt_age := visual_time - form.hurt_at[id]
		if hurt_age >= 0.0 and hurt_age < 0.38:
			if hurt_age < 0.28:
				pose = 3
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
		if dizzy:      # 접촉선 맞추기 뒤에 —— 몇 px 흔들림이라 다시 재지 않는다
			var ph := visual_time * 6.2 + id * 1.7 + slot_f
			p.x += sin(ph) * dizzy_px
			tilt += sin(ph * 0.83 + 1.1) * 0.12
		var n := figure_count
		figure_count += 1
		if _figs.size() < figure_count * FIG_W:
			_figs.resize(maxi(figure_count * FIG_W, _figs.size() * 2))
		var b := n * FIG_W
		_figs[b] = p.x
		_figs[b + 1] = p.y
		_figs[b + 2] = h
		_figs[b + 3] = action_base + pose if animated else cell
		_figs[b + 4] = fade_sq * form.opacity[id]
		_figs[b + 5] = tilt
		_figs[b + 6] = gait
		_figs[b + 7] = stride
		_figs[b + 8] = hit
		_figs[b + 9] = 1.0 if mirror else 0.0
		_figs[b + 10] = cv
		_figs[b + 11] = style if animated else float(grade)
		_fig_sq.append(sq)
		_fig_keys.append(((int(roundf(p.y * 8.0)) + 0x80000) << 16) | n)
	if form.count > 0 and batch_rendering:
		_collect_standard(sq, form, h / FIGURE_SCALE, fade_sq, cv, grade)
	_scr[sq.key] = scr

## 11/24 신화 장수 인형 ————————————————————————————————————————————————
const HERO_DATA := "res://data/myth_hero_actions.json"
const LEGACY_HERO_DATA := "res://data/myth_heroes.json"
const IMMORTAL_HERO_DATA := "res://data/immortal_hero_actions.json"
const TRANSCENDENT_HERO_DATA := "res://data/transcendent_hero_actions.json"
const TRANSCENDENT_TIER := 6
const IMMORTAL_TIER := 7
const HERO_CELL := 96
const IMMORTAL_HERO_OFFSET := 48 # 셰이더의 불멸 장수 시작 칸 = 96 + 48
const TRANSCENDENT_HERO_OFFSET := 216 # First transcendent shader cell = 96 + 216.
const HERO_FIG := 1.75         # 장수 키 = 병사 인형 키 × 이 값 (사용자 샘플 기준)
const HERO_BODY := 0.92        # 병사 인형이 칸에서 차지하는 키 (동작 시트 실측 0.84~1.0) —— 장수 키를 칸이 아닌 몸으로 맞춘다
const HERO_LUNGE := 2.2        # 공격 · 피격 때 내지르기 · 움찔 폭 (병사 대비, 그림 한 장이라 자리 · 기울기로)
const MYTH_HERO_STYLE := 13.0
const IMMORTAL_HERO_STYLE := 12.0
const HERO_FALL_TIME := 0.60

func _load_heroes() -> void:
	var data_path := HERO_DATA if FileAccess.file_exists(HERO_DATA) else LEGACY_HERO_DATA
	_load_hero_sheet(data_path, _hero_cells, 0)
	_load_hero_sheet(IMMORTAL_HERO_DATA, _immortal_hero_cells, IMMORTAL_HERO_OFFSET)
	_load_hero_sheet(TRANSCENDENT_HERO_DATA, _transcendent_hero_cells, TRANSCENDENT_HERO_OFFSET)
	hero_ready = not _hero_cells.is_empty() or not _immortal_hero_cells.is_empty() or not _transcendent_hero_cells.is_empty()

func _load_hero_sheet(data_path: String, map: Dictionary, offset: int) -> void:
	if not FileAccess.file_exists(data_path):
		return
	var d = JSON.parse_string(FileAccess.get_file_as_string(data_path))
	if typeof(d) != TYPE_DICTIONARY or not ResourceLoader.exists(str(d.get("sheet", ""))):
		return
	var tex: Texture2D = load(str(d.sheet))
	var grid: Array = d.get("grid", [4, 3])
	var slots := int(grid[0]) * int(grid[1])
	if tex == null or slots <= 0:
		return
	if offset == 0 and slots > IMMORTAL_HERO_OFFSET:
		return
	if offset == IMMORTAL_HERO_OFFSET and offset + slots > TRANSCENDENT_HERO_OFFSET:
		return
	var poses := clampi(int(d.get("poses", 1)), 1, 4)
	_hero_fill.resize(maxi(_hero_fill.size(), offset + slots))
	_hero_scale.resize(_hero_fill.size())
	var cells_: Dictionary = d.get("cells", {})
	for nm in cells_:
		var i := int(cells_[nm].get("i", -1))
		if i < 0 or i + poses > slots:
			continue
		map[str(nm)] = offset + i
		_hero_fill[offset + i] = maxf(0.2, float(cells_[nm].get("fill", HERO_BODY)))
		_hero_scale[offset + i] = float(cells_[nm].get("scale", 1.0))
	if offset == 0:
		_hero_poses = poses
		batch.hero_atlas = tex
		batch.hero_grid = Vector2(int(grid[0]), int(grid[1]))
	elif offset == IMMORTAL_HERO_OFFSET:
		batch.immortal_hero_atlas = tex
		batch.immortal_hero_grid = Vector2(int(grid[0]), int(grid[1]))
	else:
		batch.transcendent_hero_atlas = tex
		batch.transcendent_hero_grid = Vector2(int(grid[0]), int(grid[1]))

func _shows_hero(sq: Squad) -> bool:
	return batch_rendering and hero_ready and heroes_on and tier_fx and sq.tier in [TRANSCENDENT_TIER, IMMORTAL_TIER, MYTH_TIER] and _hero_index(sq) >= 0

func _collect_hero_fall(sq: Squad, fall: Dictionary) -> void:
	var at: Vector2 = fall.at
	var axis := (_pm(at + Vector2(fall.dir) * 16.0) - _pm(at)).normalized()
	var phase := smoothstep(0.0, HERO_FALL_TIME, visual_time - float(fall.start))
	var p := _pm(at) + axis * (phase * 6.0)
	var h := _figure_height(sq, fall.form)
	var transcendent := sq.tier == TRANSCENDENT_TIER
	var fall_tilt := 0.28 if transcendent else 1.36
	var tilt := phase * fall_tilt * (1.0 if axis.x >= 0.0 else -1.0)
	_append_hero(sq, _hero_index(sq), 4 if transcendent else 3, p, h, 1.0 - phase, tilt, 0.0, 0.0, fall.mirror, 0.0)

## 그 부대 장수의 인형 칸 (없으면 -1) —— 카드 id 로 한 번만 찾는다
func _hero_index(sq: Squad) -> int:
	var k := sq.cid
	if sq.tier == TRANSCENDENT_TIER:
		return int(_transcendent_hero_cells.get(k, -1))
	if not _hero_of.has(k):
		var person := DB.person(k) if DB.C.has(k) else ""
		var immortal_idx := int(_immortal_hero_cells.get(person, -1))
		_hero_of[k] = immortal_idx if sq.tier == IMMORTAL_TIER else int(_hero_cells.get(person, immortal_idx))
	return int(_hero_of[k])

## 장수 한 명을 대열 중심에 그리며, 기존 부대의 공격·피격 시각을 받는다.
func _collect_hero(sq: Squad, form: FormationMotion, idx: int, soldier_h: float, axis: Vector2, mirror: bool,
		eligible: bool, ranged: bool, bow_base: float, fade_sq: float, cv: float, sway: float) -> void:
	var strike := -10.0
	var gait := 0.0
	var living := 0
	var lead := -1
	for id in form.capacity:
		if form.alive[id] == 0:
			continue
		strike = maxf(strike, form.strike_at[id])
		gait += form.gait[id]
		living += 1
		if lead < 0:
			lead = id
	if living == 0:
		return
	var at := form.center
	gait /= living
	var stride: float = form.strides[lead]
	var p := _pm(at)
	var p0 := p
	var tilt := 0.0
	var pose := 0
	if sq.state != "flee":
		if eligible and not ranged:
			var age := visual_time - strike
			var windup := 0.0
			var thrust := 0.0
			if age >= 0.0 and age < 0.4:
				pose = 1 if age < 0.12 else 2
				windup = smoothstep(0.0, 0.09, age) * (1.0 - smoothstep(0.09, 0.13, age))
				thrust = smoothstep(0.09, 0.13, age) * (1.0 - smoothstep(0.18, 0.4, age))
			var guard := sin(visual_time * 3.1 + float(sq.row.slot)) * form.contact_weight
			p += axis * guard * 0.8 * (1.0 - gait)
			tilt += axis.x * guard * 0.018
			p += axis * (thrust * 3.2 - windup * 1.2) * HERO_LUNGE
			tilt += axis.x * (thrust * 0.16 - windup * 0.07)
			gait *= 0.35
		elif ranged and bow_base < 0.5:
			if bow_base >= 0.0 and bow_base < 0.4:
				pose = 1 if bow_base < 0.12 else 2
			var bow := smoothstep(0.0, 0.1, bow_base) * (1.0 - smoothstep(0.15, 0.32, bow_base))
			tilt -= axis.x * bow * 0.08
			p -= axis * bow * 2.0
	var hurt_age := visual_time - form.hero_hurt_at
	if hurt_age >= 0.0 and hurt_age < HERO_RECOIL_TIME:
		pose = 3
		mirror = form.hero_hurt_mirror
		var hurt_axis: Vector2 = (_pm(at + form.hero_hurt_dir * 16.0) - _pm(at)).normalized()
		var recoil := smoothstep(0.0, 0.055, hurt_age) * (1.0 - smoothstep(0.11, HERO_RECOIL_TIME, hurt_age))
		p += hurt_axis * recoil * (2.0 + form.hero_hurt_power * 2.4) * HERO_LUNGE * 0.7
		tilt += hurt_axis.x * recoil * (0.07 + form.hero_hurt_power * 0.05)
		gait *= 1.0 - recoil
	if gait > 0.001:
		tilt += sin(stride) * gait * sway * 0.7
	if p != p0 and not form.contact_limits.is_empty():
		p = _pm(form.constrain_foot(v.unmap(p)))
	if sq.state != "flee" and sq.statuses.has("confuse"):      # 11/25 혼란 —— 장수도 비틀거린다
		var ph := visual_time * 5.4 + float(sq.row.slot)
		p.x += sin(ph) * soldier_h * 0.07
		tilt += sin(ph * 0.8 + 0.7) * 0.1
	if sq.state != "flee":
		var motion := MythUltimateMotion.INACTIVE
		for i in range(ults.size() - 1, -1, -1):
			var action: Dictionary = ults[i]
			if action.a != sq.key:
				continue
			var age := last_clock - float(action.start)
			if action.phase == "dash" and age >= 0.3 and not sq.moving:
				break
			if pose == 3 and action.phase != "impact":
				break
			motion = MythUltimateMotion.sample(sq.cid, action.phase, age, float(action.end) - float(action.start))
			break
		if motion.w < 0.0 and pose != 3 and _hero_skill_motion.has(sq.key):
			var skill: Dictionary = _hero_skill_motion[sq.key]
			var age := last_clock - float(skill.start)
			motion = MythUltimateMotion.sample_skill(sq.cid, skill.style, skill.kind, age, skill.delay)
		if motion.w >= 0.0:
			p += (axis * motion.x - Vector2(0.0, motion.y)) * soldier_h
			tilt += motion.z * (-1.0 if mirror else 1.0)
			pose = int(motion.w)
			gait = 0.0
	_append_hero(sq, idx, pose, p, soldier_h, fade_sq, tilt, gait, stride, mirror, cv)

func _append_hero(sq: Squad, idx: int, pose: int, p: Vector2, soldier_h: float, fade_sq: float,
		tilt: float, gait: float, stride: float, mirror: bool, cv: float) -> void:
	var n := figure_count
	figure_count += 1
	if _figs.size() < figure_count * FIG_W:
		_figs.resize(maxi(figure_count * FIG_W, _figs.size() * 2))
	var b := n * FIG_W
	_figs[b] = p.x
	_figs[b + 1] = p.y
	var immortal := sq.tier == IMMORTAL_TIER
	var transcendent := sq.tier == TRANSCENDENT_TIER
	var scale := 1.55 if immortal else (1.4 if transcendent else HERO_FIG)
	var h := soldier_h * scale * _hero_scale[idx] * HERO_BODY / _hero_fill[idx]
	_figs[b + 2] = h
	hero_feet[sq.key] = p - Vector2(0.0, pow(absf(sin(stride)), 3.0) * gait * h * 0.012)
	hero_h[sq.key] = h * _hero_fill[idx]      # 칸 키가 아니라 몸 키 (칸마다 여백이 다르다 —— 말 탄 여포는 칸의 일부만 쓴다)
	var frame := pose if idx >= IMMORTAL_HERO_OFFSET else mini(pose, _hero_poses - 1)
	if transcendent:
		# Idle, action, recoil, defeat. The wind-up reuses idle with a tilt.
		frame = maxi(0, pose - 1)
	_figs[b + 3] = float(HERO_CELL + idx + frame)
	_figs[b + 4] = fade_sq
	_figs[b + 5] = tilt
	_figs[b + 6] = gait
	_figs[b + 7] = stride
	_figs[b + 8] = 0.0
	_figs[b + 9] = 1.0 if mirror else 0.0
	_figs[b + 10] = cv
	var style := IMMORTAL_HERO_STYLE if immortal or transcendent else MYTH_HERO_STYLE
	_figs[b + 11] = style + (0.0 if sq.camp == "A" else 16.0)
	_fig_sq.append(sq)
	_fig_keys.append(((int(roundf(p.y * 8.0)) + 0x80000) << 16) | n)

## 부대 안에 꽂힌 군기도 병사와 같은 깊이 순서·GPU 묶음에 넣는다.
## 셀 16/17은 아틀라스 대신 셰이더가 그리는 청/적 천과 깃대다.
func _collect_standard(sq: Squad, form: FormationMotion, soldier_h: float, alpha: float, shade: float, grade := 1) -> void:
	var facing := Vector2.from_angle(form.heading)
	var right := Vector2(-facing.y, facing.x)
	var at := form.center - facing * minf(sq.hd0 * 0.65, form.row_gap * maxf(1, form.rows - 1)) + right * form.half_width * 0.65
	var p := _pm(at)
	var n := figure_count
	figure_count += 1
	if _figs.size() < figure_count * FIG_W:
		_figs.resize(maxi(figure_count * FIG_W, _figs.size() * 2))
	var b := n * FIG_W
	var leaning := 0.0
	if sq.state == "flee":
		leaning = -0.75 if sq.camp == "A" else 0.75
	elif sq.morale < 40.0:
		leaning = (40.0 - sq.morale) / 40.0 * 0.45
	_figs[b] = p.x
	_figs[b + 1] = p.y
	_figs[b + 2] = clampf(soldier_h * 2.0, 25.0, 47.0 * float(GRADE_BANNER[grade]))      # 11/24 높은 단계일수록 군기를 크게
	_figs[b + 3] = 16.0 if sq.camp == "A" else 17.0
	_figs[b + 4] = alpha
	_figs[b + 5] = leaning + sin(form.motion_clock * 3.0 + sq.row.slot) * 0.025
	_figs[b + 6] = 0.0
	_figs[b + 7] = form.motion_clock * 4.0 + sq.row.slot
	_figs[b + 8] = 0.0
	_figs[b + 9] = 0.0
	_figs[b + 10] = shade
	_figs[b + 11] = float(grade)
	_fig_sq.append(sq)
	_fig_keys.append(((int(roundf(p.y * 8.0)) + 0x80000) << 16) | n)

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
	var mk_fade := sq.fade * (1.0 - 0.8 * maxf(cover_of(sq), 0.0))      # 그늘 속 부대는 진영색 표식도 흐리게
	var selected: bool = v.view != null and v.view.hud != null and v.view.hud.highlight_k(sq.key) > 0.0
	var contributing: bool = v.view != null and v.view.hud != null and v.view.hud.story.pulse(sq.key, v.view.clock)
	if selected:
		color = Color("#d8f2ff")
	elif contributing:
		color = EMBER
	var fill := Color(color, (0.15 if selected else (0.11 if contributing else 0.045)) * mk_fade)
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
	var rim_c := Color(color, (0.95 if selected else (0.7 if contributing else 0.25)) * mk_fade)
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
	var ink := Color(INK, 0.7 * mk_fade)
	var lc := Color(color, 0.8 * mk_fade)
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

## 11/22 매복 그늘 —— 지형 그늘로 부드럽게 들고 나며, 깊이 들었다가 빠져나오면 등장 연출을 건다
func _cover_step(sq: Squad) -> void:
	if sq.contact:      # 적과 맞붙으면 드러난다 (기습이 닿은 순간 등장) —— 맞닿음이 잠깐 끊겨도 깜빡이지 않게 COVER_HOLD 초 동안 드러난 채
		_bared[sq.key] = visual_time
	var bare := visual_time - float(_bared.get(sq.key, -99.0)) < COVER_HOLD
	var want: float = v.cover_target(sq) if not bare and v.has_method("cover_target") and sq.alive and sq.state != "flee" else 0.0
	# 11/27 키트 은신 (표적이 되지 않는다) —— 사건 스냅숏의 상태에 stealth · hide 가 있으면 맞붙어 있어도 그늘에 묻는다. 풀리면 등장 연출(「기습!」)이 그대로 뜬다
	if sq.alive and sq.state != "flee" and (sq.statuses.has("stealth") or sq.statuses.has("hide")):
		want = maxf(want, STEALTH_COVER)
	var cur: float = cover.get(sq.key, want if last_clock <= 0.0 else 0.0)
	cur = move_toward(cur, want, motion_dt * (COVER_IN if want > cur else COVER_OUT))
	cover[sq.key] = cur
	if cur > 0.6:
		_hid[sq.key] = true
	elif cur < 0.3 and _hid.has(sq.key):
		_hid.erase(sq.key)
		if sq.alive and sq.state != "flee":
			reveals.append({"key": sq.key, "t0": visual_time})


## 그리는 값 —— 0~1 그늘, 막 나온 부대는 음수(번쩍)
func cover_of(sq: Squad) -> float:
	var cv: float = cover.get(sq.key, 0.0)
	for r in reveals:
		if r.key == sq.key:
			var age := visual_time - float(r.t0)
			if age < REVEAL_FLASH:
				return -(1.0 - age / REVEAL_FLASH)
	return cv


## 등장 연출 —— 숲을 헤치고 나온 자리에 흙먼지 고리 · 흩어지는 잎 · 「기습!」
func _draw_reveals(ci: CanvasItem) -> void:
	for r in reveals:
		var sq: Squad = v.field.squads.get(r.key)
		if sq == null or not sq.alive:
			continue
		var age := visual_time - float(r.t0)
		var t := clampf(age / REVEAL_LIFE, 0.0, 1.0)
		var p: Vector2 = v.map(sq.pos)
		var k: float = v.depth_scale(sq.pos) * _ps
		var fade := 1.0 - t
		var rad := sq.hw * (0.5 + 0.9 * sqrt(t)) * k
		ci.draw_set_transform(p, 0.0, Vector2(1.0, 0.42))
		ci.draw_arc(Vector2.ZERO, rad, 0.0, TAU, 28, Color(0.80, 0.70, 0.50, 0.55 * fade), 5.0 * k * fade + 1.0, true)
		ci.draw_arc(Vector2.ZERO, rad * 0.7, 0.0, TAU, 24, Color(0.92, 0.85, 0.66, 0.35 * fade), 2.0, true)
		ci.draw_set_transform(Vector2.ZERO)
		var seed_f := float(hash(r.key) % 97)
		for i in 9:
			var a := seed_f + i * 0.7
			var dir := Vector2(cos(a * 2.3), -absf(sin(a * 1.7)) * 0.8 - 0.2)
			var q := p + dir * sq.hw * (0.3 + 1.1 * t) * k + Vector2(0, sq.hw * 0.6 * t * t * k)
			var leaf := Color(0.30, 0.42, 0.22, 0.85 * fade) if i % 3 != 0 else Color(0.55, 0.50, 0.30, 0.8 * fade)
			ci.draw_set_transform(q, a + t * 6.0, Vector2(1.0, 0.5))
			ci.draw_circle(Vector2.ZERO, 2.4 * k + 0.6, leaf)
		ci.draw_set_transform(Vector2.ZERO)
		var la := smoothstep(0.0, 0.08, t) * (1.0 - smoothstep(0.65, 1.0, t))
		_action_label(p + Vector2(0, -sq.hw * 0.8 * k - 16.0 - 14.0 * t), "기습!", Color("#ffd27a"), la, ci)


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
				var trail := PackedVector2Array([p])
				for k in range(1, 6):      # 11/25 꼬리 —— 날아온 길을 다섯 점 거슬러 (예전 1.5px 선 한 토막)
					var tk := maxf(0.0, t - k * 0.04)
					trail.append(v.map(start.lerp(end + spread, tk)) - Vector2(0, 5.0 + sin(tk * PI) * height * v.depth_scale(world)))
				_spell_orb(ci, shot, p, trail, t)
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
	var story = v.view.hud.story
	if not story.active(v.view.clock) or story.current.kind == "fire":
		return
	for e in v.view.hud._deck_links:
		if e.a != story.current.provider or e.b != story.current.target:
			continue
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

## 메타데이터가 없는 공격이나 단순 화상 활용을 확산으로 추정하지 않는다.
func _record_burn(event: Dictionary) -> void:
	if event.get("fx") != "status" or event.get("st") != "burn":
		return
	var target: Squad = v.field.squads.get(str(event.get("f", "")))
	if target == null:
		return
	var source: Squad = v.field.squads.get(str(event.get("from", event.get("a", ""))))
	var form := _formation(target)
	var direction := Vector2.from_angle(form.heading)
	if source != null and source != target:
		direction = _formation(source).center.direction_to(form.center)
	if not burn_fronts.has(target.key):
		burn_fronts[target.key] = {"start": visual_time, "direction": direction}
	if not bool(event.get("spread", false)) or source == null or source == target:
		return
	if v.view != null and v.view.hud != null:
		var story = v.view.hud.story
		if story.active(v.view.clock) and not story.accepts_fire(event, v.view.clock):
			return
	for path in fire_paths:
		if path.a == source.key and path.b == target.key and visual_time - float(path.start) < 0.35:
			return
	# 대표 연계 하나를 끝까지 보여준다. 새 사건마다 바꿔 가며 화면을 채우지 않는다.
	if fire_paths.size() >= MAX_FIRE_PATHS:
		return
	fire_paths.append({"a": source.key, "b": target.key, "start": visual_time,
		"from": _formation(source).center, "to": form.center})

func burn_sites(sq: Squad) -> PackedVector2Array:
	var points := PackedVector2Array()
	var form: FormationMotion = formations.get(sq.key)
	if form == null or not sq.alive or not sq.statuses.has("burn"):
		return points
	var ids: Array[int] = []
	for id in form.capacity:
		if form.alive[id] != 0:
			ids.append(id)
	var n := mini(3, ids.size())
	var front: Dictionary = burn_fronts.get(sq.key, {})
	var direction: Vector2 = front.get("direction", Vector2.from_angle(form.heading))
	var age := visual_time - float(front.get("start", visual_time - 2.0))
	var span := maxf(sq.edge(direction), 1.0)
	for j in n:
		var at: Vector2 = form.feet[ids[j * ids.size() / n]]
		var delay := clampf(((at - form.center).dot(direction) / span + 1.0) * 0.5, 0.0, 1.0) * 0.7
		if age >= delay:
			points.append(at)
	return points

func _draw_fire_paths(ci: CanvasItem) -> void:
	for path in fire_paths:
		var source: Squad = v.field.squads.get(path.a)
		var target: Squad = v.field.squads.get(path.b)
		var start: Vector2 = path.from
		var end: Vector2 = path.to
		if source != null and formations.has(source.key):
			start = formations[source.key].center
		if target != null and formations.has(target.key):
			end = formations[target.key].center
		var direction := start.direction_to(end)
		var distance := start.distance_to(end)
		if source != null:
			start += direction * minf(distance * 0.32, source.edge(direction) * 0.7)
		if target != null:
			end -= direction * minf(distance * 0.32, target.edge(direction) * 0.7)
		var age := visual_time - float(path.start)
		var reach := clampf(age / 0.65, 0.0, 1.0)
		var alpha := 1.0 - smoothstep(0.7, FIRE_PATH_LIFE, age)
		var side := Vector2(-direction.y, direction.x) * minf(distance * 0.1, 20.0)
		var trail := PackedVector2Array()
		for j in 7:
			var u := reach * j / 6.0
			trail.append(v.map(start.lerp(end, u) + side * sin(u * PI)))
		if reach > 0.01:
			ci.draw_polyline(trail, Color(0.18, 0.1, 0.04, alpha * 0.55), 5.0, true)
			ci.draw_polyline(trail, Color(0.87, 0.38, 0.08, alpha * 0.7), 1.6, true)
		for j in 3:
			var u := reach - j * 0.1
			if u <= 0.0:
				continue
			var world := start.lerp(end, u) + side * sin(u * PI)
			var at: Vector2 = v.map(world)
			var h: float = (12.0 + sin(age * 13.0 + j * 1.7) * 3.0) * v.depth_scale(world)
			_spr(ci, "flame_02", at - Vector2(0, h * 0.4), h * 1.8, Color(1, 0.55, 0.15, alpha * 0.85), sin(j * 2.4) * 0.12, Vector2(0.6, 1))

func _draw_status(sq: Squad, ci: CanvasItem = null) -> void:
	if ci == null:
		ci = self
	if not sq.alive:
		return
	var p: Vector2 = v.map(sq.pos)
	var perspective: float = v.depth_scale(sq.pos)
	if sq.statuses.has("burn"):
		var sites := burn_sites(sq)
		for j in sites.size():
			var phase: float = v.field.clock * 5.0 + j * 1.7
			var base: Vector2 = v.map(sites[j])
			var h: float = (12.0 + 4.0 * sin(phase)) * v.depth_scale(sites[j])
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
	if sq.statuses.has("confuse"):      # 11/25 도는 별 셋 + 물음표 (예전 반지름 7px 호 하나)
		caster.draw_confuse(ci, sq)


# ───────── 고유기 이펙트 (11/17) ─────────
# 사용자: 「고유기 이펙트가 왜 안 나오냐」 —— 삽화 화면에서는 type2 의 fx()/_draw_fx 가 모두 꺼져 컷인 · 카메라 · 병사 밀림만 남았다.
# 화면 섬광 · 팝콘 날리기 없이 붓 획 · 불꽃 · 낙뢰 · 화살비처럼 종류가 한눈에 갈리게 그린다. 판정 · 수치와 무관한 화면 연출.
const ULT_LIFE := {"firestorm": 2.4, "thunder": 1.5, "slash": 1.1, "shadow": 1.3, "poison": 2.4, "illusion": 1.8, "aura": 1.8, "heal": 1.8, "roar": 1.2, "whirlwind": 1.4, "charge": 1.0}

## 11/19 화염 계열 여섯 —— 인물마다 불이 오는 방식이 다르다 (없으면 불덩이 셋). 다른 계열은 인물 갈래 번호(sd)로 획 수 · 각도 · 색을 바꾼다
##  wave 주유 적벽대화: 바람을 탄 불벽이 적진을 쓸고 지나간다 · trail 육손 이릉: 불길이 진영을 따라 차례로 옮겨붙는다 · arrows 정보 화선: 불화살 떼
##  ram 황개 고육지계: 불배 하나가 곧장 들이받고 터진다 · chain 방통 연환: 쇠사슬로 엮인 뒤 사슬을 따라 탄다 · erupt 동탁 낙양겁화: 땅에서 불기둥이 솟는다
const ULT_STYLE := {"여포": "halberd_whirlwind", "관우": "crescent", "주유": "wave", "육손": "trail", "정보": "arrows", "황개": "ram", "방통": "chain", "동탁": "erupt"}

## phase "charge" —— 기 모으기 (시전자 둘레), "impact" —— 맞는 순간 (적 · 아군 부대)
func add_ult(vfx: String, a_key: String, foes: Array, allies: Array, col: Color, phase: String, lite := false) -> void:
	var now: float = v.field.clock
	var a: Squad = v.field.squads.get(a_key)
	var e := {"vfx": vfx, "a": a_key, "col": col, "phase": phase, "start": now,
		"end": now + (0.55 if phase == "charge" else 3.0 if phase == "dash" else float(ULT_LIFE.get(vfx, 1.0))),
		"from": a.pos if a != null else Vector2.ZERO, "hits": [], "allies": []}
	# 11/19 사용자: 같은 계열 고유기라도 이펙트가 달라 보이게 —— 인물마다 모양(style) · 갈래 번호(sd)를 싣는다
	var who: String = DB.person(a.cid) if a != null and DB.C.has(a.cid) else ""
	e["style"] = str(ULT_STYLE.get(who, ""))
	e["sd"] = absi(hash(who)) % 997
	e["lite"] = lite
	if lite:      # 11/24 빠른 · 미니 고유기 —— 기술 레시피(_skill_hit)를 고유기 크기로 키워 쓴다 (_draw_lite_ult). 시전 부대 등급(tl)으로 크기 · 장식
		var tl := fx_tier(a)
		e["k"] = str(LITE_ULT_STYLE.get(vfx, "flash"))
		e["tl"] = tl
		e["tc"] = _fx_tier_col(a, tl)
		e["sc"] = LITE_ULT_SC * float(FX_TIER_SC[tl])
		e["big"] = true
		e.end = now + (BattleView.ULT_DELAY if phase == "charge" else maxf(1.0, float(SKILL_FX_LIFE.get(e.k, 1.0)) * 1.15))
		if phase == "impact":
			skill_fx_seen["고유기:" + vfx] = int(skill_fx_seen.get("고유기:" + vfx, 0)) + 1
	var storm := vfx == "arrowstorm"
	if storm and phase == "impact" and not lite:      # 화살비 —— 기 모으기 동안은 컷인이 덮고 있어, 컷인이 걷힌 맞는 순간에 떼로 솟아 쏟아진다
		e.end = now + 1.8
	if phase == "impact":
		for k in (foes.slice(0, LITE_ULT_HITS) if lite else foes):      # 빠른 고유기는 부대 셋까지 (비용)
			var d: Squad = v.field.squads.get(k)
			if d == null:
				continue
			var spots := []
			for j in (5 if lite else 7):      # 빠른 고유기는 기술 레시피가 쓰는 다섯 지점만
				var h1 := float(hash(str(k) + ":" + str(j)) % 10007) / 10007.0
				var h2 := float(hash(str(j) + ":" + str(k) + ":y") % 10007) / 10007.0
				spots.append(d.pos + d.right() * (h1 * 2.0 - 1.0) * d.hw * 0.75 + d.fwd * (h2 * 2.0 - 1.0) * d.hd() * 0.55)
			var dir: Vector2 = (d.pos - e.from).normalized() if not (d.pos - e.from).is_zero_approx() else d.fwd
			e.hits.append({"at": d.pos, "spots": spots, "right": d.right(), "fwd": d.fwd, "hw": d.hw, "hd": d.hd(), "dir": dir})
		for k in (allies.slice(0, LITE_ULT_HITS) if lite else allies):
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
		if e.phase != "impact" or bool(e.get("lite", false)):
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
		if bool(e.get("lite", false)):
			_draw_lite_ult(ci, e, t, col, fade)
			continue
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

## 간단한 고유기는 부대 주변에서 끝난다. 배경 암전 · 카메라 · 슬로우 · 다중 불기둥은 큰 고유기만 쓴다.
## 11/24 사용자: 「빠른 고유기로 나갈 때 이펙트 생략되고 있는지?」 —— 예전엔 0.45초 동안 반지름 8~17px 고리 · 선 하나라 사실상 안 보였다.
## 이제 기술 레시피(_skill_hit · _skill_self)를 기술보다 크게(LITE_ULT_SC, 기술 0.6 · 큰 고유기 약 1.15) 쓰고,
## 고유기 표식(기 모으기: 발밑 금빛 원상 + 머리 위 붉은 인장 / 맞는 순간: 땅에 금빛 원상 + 인장이 쾅 찍힌다)과 종류별 먹 그림 · 등급 장식을 얹는다.
## 비용 —— 부대 셋 · 부대마다 효과 지점 다섯 (add_ult), 수명 1~2초
const LITE_ULT_STYLE := {"firestorm": "fire", "thunder": "bolt", "slash": "slash", "shadow": "shadow", "poison": "poison", "illusion": "vortex",
	"aura": "aura", "heal": "heal", "roar": "flash", "whirlwind": "slash", "charge": "charge", "arrowstorm": "rain"}
const LITE_ULT_SC := 1.05
const LITE_ULT_HITS := 3
func _draw_lite_ult(ci: CanvasItem, e: Dictionary, _t: float, col: Color, _fade: float) -> void:
	var age := last_clock - float(e.start)
	var life := maxf(0.05, float(e.end) - float(e.start))
	var from: Vector2 = e.from
	if e.phase == "charge":
		_ult_mark_charge(ci, e, from, age, life, col)
		return
	var fade := 1.0 - smoothstep(0.65, 1.0, age / life)
	var k: String = e.get("k", "flash")
	var sc: float = e.sc
	if SELF_STYLES.has(k):      # 회복 —— 아군 부대마다 · 위세 —— 시전자와 아군
		var sites: Array = []
		if k != "heal" or e.allies.is_empty():
			sites.append(from)
		sites.append_array(e.allies)
		for i in mini(sites.size(), LITE_ULT_HITS + 1):
			var q: Vector2 = sites[i]
			var ai: float = age - i * 0.08
			if ai < 0.0:
				continue
			_tier_under(ci, e, q, ai, fade)
			_skill_self(ci, e, ai, clampf(ai / life, 0.0, 1.0), fade, q)
			_lite_extra(ci, e, q, ai, life, fade, col)
			_tier_over(ci, e, q, ai, fade)
		_seal_stamp(ci, from, age, fade, sc)
		return
	if e.vfx in ["roar", "whirlwind"]:
		_lite_shock(ci, e, from, age, life, col, fade)
	if e.tl == 5 and e.style == "halberd_whirlwind" and age < 0.84:
		_draw_myth_halberd_whirlwind(ci, from, age)
	for i in e.hits.size():
		var hit: Dictionary = e.hits[i]
		var ai: float = age - i * 0.07
		if ai < 0.0:
			continue
		_tier_under(ci, e, hit.at, ai, fade)
		_ult_mark_ground(ci, e, hit.at, ai, fade)
		_skill_hit(ci, e, hit, ai, life, fade)
		_lite_extra(ci, e, hit.at, ai, life, fade, col)
		if e.tl == 5 and e.style == "wave" and ai < 0.64 and i == 0:
			_draw_myth_fire_wave(ci, from, hit.at, ai)
		if e.tl == 5 and e.style == "crescent" and ai < 0.50 and i == 0:
			_draw_myth_crescent(ci, from, hit.at, ai)
		_tier_over(ci, e, hit.at, ai, fade)
	_seal_stamp(ci, e.hits[0].at if not e.hits.is_empty() else from, age, fade, sc)


func _draw_myth_halberd_whirlwind(ci: CanvasItem, from: Vector2, age: float) -> void:
	var center := _pm(from)
	var unit := maxf(29.0, _px(from, 95.0))
	for pass_index in 3:
		var t := (age - pass_index * 0.15) / 0.54
		if t <= 0.0 or t >= 1.0:
			continue
		var fade := smoothstep(0.0, 0.12, t) * (1.0 - smoothstep(0.40, 1.0, t))
		var radius := unit * (0.66 + 0.52 * t + pass_index * 0.16)
		var head := -PI * 0.65 + t * TAU * 1.06 + pass_index * 2.05
		var arc := PackedVector2Array()
		for step in 25:
			var angle := head - 2.05 * (1.0 - step / 24.0)
			arc.append(center + Vector2(cos(angle), sin(angle) * 0.54 - 0.38) * radius)
		ci.draw_polyline(arc, Color(0.29, 0.03, 0.04, fade * 0.74), unit * 0.32, true)
		ci.draw_polyline(arc, Color(1.0, 0.27, 0.13, fade * 0.94), unit * 0.16, true)
		ci.draw_polyline(arc, Color(1.0, 0.89, 0.55, fade), unit * 0.055, true)


func _draw_myth_crescent(ci: CanvasItem, from: Vector2, to: Vector2, age: float) -> void:
	var origin := _pm(from)
	var target := _pm(to)
	var heading := (target - origin).angle()
	var radius := maxf(25.0, _px(to, 105.0))
	var progress := smoothstep(0.0, 0.22, age)
	var opacity := smoothstep(0.0, 0.055, age) * (1.0 - smoothstep(0.20, 0.50, age))
	var center := origin.lerp(target, 0.60) - Vector2(0.0, radius * 0.35)
	var end := heading - 1.35 + progress * 2.70
	var start := maxf(heading - 1.52, end - 1.18)
	ci.draw_arc(center, radius, start, end, 22, Color(0.04, 0.38, 0.23, opacity * 0.52), radius * 0.32, true)
	ci.draw_arc(center, radius, start, end, 22, Color(0.22, 0.95, 0.61, opacity), radius * 0.13, true)
	ci.draw_arc(center, radius * 1.04, start, end, 22, Color(1.0, 0.94, 0.72, opacity), radius * 0.047, true)


func _draw_myth_fire_wave(ci: CanvasItem, from: Vector2, to: Vector2, age: float) -> void:
	var origin := _pm(from)
	var target := _pm(to)
	var dir := origin.direction_to(target)
	var side := Vector2(-dir.y, dir.x)
	var unit := maxf(14.0, _px(to, 62.0))
	var progress := smoothstep(0.0, 0.46, age)
	var strength := smoothstep(0.0, 0.10, age) * (1.0 - smoothstep(0.40, 0.64, age))
	var front := origin.lerp(target + dir * unit * 0.55, progress)
	for k in 7:
		var lane := float(k - 3)
		var at := front + side * lane * unit * 0.30 - dir * absf(lane) * unit * 0.14
		var crest := 1.0 - absf(lane) * 0.16
		_flame(ci, at, unit * 2.2 * crest * strength, unit * 0.36, last_clock * 8.0 + k, strength * 0.88)


## 고유기 표식 (기 모으기) —— 시전자 발밑에 금빛 원상이 커지며 돌고, 기가 불티로 빨려 들며, 머리 위로 붉은 인장이 튀어나온다
func _ult_mark_charge(ci: CanvasItem, e: Dictionary, from: Vector2, age: float, life: float, col: Color) -> void:
	var fs: Vector2 = v.map(from)
	var u := maxf(30.0, _px(from, 115.0)) * float(e.get("sc", LITE_ULT_SC))
	var q := clampf(age / life, 0.0, 1.0)
	var g := ease(minf(1.0, q * 1.8), 0.4)
	_ink_ground(ci, "enso_0", fs, u * (1.3 + 0.4 * g), Color(1.0, 0.8, 0.28, 0.95 * g), age * 2.2, 0.5)
	_ink_ground(ci, "enso_1", fs, u * (0.9 + 0.2 * g), Color(col, 0.85 * g), -age * 2.8, 0.5)
	for j in 6:
		var ang := j * TAU / 6.0 + age * 3.0
		var rr := u * 1.4 * (1.0 - q)
		_ink(ci, "ember", fs + Vector2(cos(ang), sin(ang) * 0.5) * rr - Vector2(0, u * 0.35 * q), u * 0.32, Color(col.lightened(0.25), 0.95 * sin(PI * q)), ang + PI * 0.5)
	var pop := 1.0 + 0.7 * (1.0 - ease(minf(1.0, age / 0.16), 0.3))
	_ink(ci, "seal", fs - Vector2(0, u * (0.95 + 0.15 * q)), u * 0.5 * pop, Color(1, 1, 1, minf(1.0, age / 0.08)), sin(age * 3.0) * 0.08)


## 고유기 표식 (맞는 자리) —— 땅에 금빛 원상이 붓으로 그어지며 번진다
func _ult_mark_ground(ci: CanvasItem, e: Dictionary, at: Vector2, age: float, fade: float) -> void:
	var u := maxf(30.0, _px(at, 115.0)) * float(e.sc)
	var g := ease(minf(1.0, age / 0.22), 0.35)
	_ink_ground(ci, "enso_%d" % (int(e.sd) % 2), v.map(at), u * (1.9 + 0.5 * g), Color(1.0, 0.8, 0.28, 0.9 * fade * g), age * 0.9 + float(e.sd), 0.5)


## 붉은 인장 —— 첫 맞는 자리 위에 크게 떨어져 쾅 찍히고 머물다 흐려진다
func _seal_stamp(ci: CanvasItem, at: Vector2, age: float, fade: float, sc: float) -> void:
	var u := maxf(30.0, _px(at, 115.0)) * sc
	var pop := 1.0 + 0.8 * (1.0 - ease(minf(1.0, age / 0.12), 0.25))
	var al := minf(1.0, age / 0.06) * fade * (1.0 - smoothstep(0.6, 0.95, age))
	var p: Vector2 = v.map(at) - Vector2(0, u * 1.1)
	if age > 0.1 and age < 0.4:      # 찍히는 순간 금빛 테가 퍼진다
		var q := (age - 0.1) / 0.3
		ci.draw_arc(p, u * (0.35 + 0.4 * q), 0.0, TAU, 20, Color(1.0, 0.85, 0.35, 0.9 * (1.0 - q)), 3.0, true)
	_ink(ci, "seal", p, u * 0.62 * pop, Color(1, 1, 1, al), -0.1)


## 포효 · 선풍 (빠른 고유기) —— 시전자에서 먹 원상 충격파가 퍼진다. 선풍은 바람 날 셋 · 나뭇잎이 휘감는다
func _lite_shock(ci: CanvasItem, e: Dictionary, from: Vector2, age: float, life: float, col: Color, fade: float) -> void:
	var fs: Vector2 = v.map(from)
	var u := maxf(30.0, _px(from, 115.0)) * float(e.sc)
	for j in 2:
		var q := clampf((age - j * 0.14) / 0.7, 0.0, 1.0)
		if q > 0.0 and q < 1.0:
			_ink_ground(ci, "enso_%d" % j, fs, u * (1.0 + 3.2 * ease(q, 0.5)), Color(INK if j == 0 else col, 0.85 * (1.0 - q)), age * 1.5 + j, 0.5)
			_world_ring(ci, from, 25.0 + q * 210.0 * float(e.sc), Color(col, 0.8 * (1.0 - q)), 5.0 - j * 2.0)
	if e.vfx == "whirlwind":
		for k in 3:
			var a0 := age * 8.0 + k * TAU / 3.0
			_crescent(ci, fs, u * 1.1, a0, 1.5, u * 0.22, Color(1.0, 0.95, 0.82, 0.9 * fade))
		for k in 7:
			var ang := age * 6.0 + k * TAU / 7.0
			var rr := u * (0.7 + 0.5 * fposmod(k * 0.37, 1.0))
			_ink(ci, "petal", fs + Vector2(cos(ang), sin(ang) * 0.5) * rr - Vector2(0, u * 0.4), u * 0.22, Color(0.55, 0.75, 0.3, 0.9 * fade), ang * 1.7)


## 빠른 고유기 종류마다 덧붙는 먹 그림 —— 기술 레시피 위에 고유기다운 한 겹
func _lite_extra(ci: CanvasItem, e: Dictionary, at: Vector2, age: float, life: float, fade: float, col: Color) -> void:
	var c: Vector2 = v.map(at)
	var u := maxf(30.0, _px(at, 115.0)) * float(e.sc)
	var sd := int(e.sd)
	var t := clampf(age / life, 0.0, 1.0)
	match str(e.vfx):
		"firestorm":      # 불티가 높이 솟는다
			for j in 8:
				var h1 := fposmod(sin(sd * 0.9 + j * 5.3) * 377.1, 1.0)
				var q := fposmod(age * 0.9 + h1, 1.0)
				_ink(ci, "ember", c + Vector2((h1 - 0.5) * u * 1.8, -q * u * 2.2), u * 0.3 * (1.0 - q * 0.5), Color(1.0, 0.45 + 0.35 * h1, 0.12, sin(PI * q) * fade), sin(age + j) * 0.5)
		"thunder":      # 머리 위 먹구름
			_ink(ci, "ink_wash_%d" % (sd % 2), c - Vector2(0, u * 3.0), u * 2.8, Color(0.12, 0.13, 0.2, 0.75 * sin(PI * t)), 0.0, Vector2(1.0, 0.45))
		"slash", "whirlwind":      # 벤 자리에 먹이 튄다
			if age > 0.12:
				_ink(ci, "ink_splash_%d" % (sd % 3), c - Vector2(0, u * 0.15), u * 1.2 * ease(minf(1.0, (age - 0.12) / 0.15), 0.3), Color(INK, 0.7 * fade), sd * 0.3, Vector2(1.0, 0.7))
		"shadow":      # 먹빛 어둠이 피어오른다
			_ink(ci, "ink_wash_%d" % (sd % 2), c - Vector2(0, u * (0.3 + 0.4 * t)), u * 2.2, Color(0.08, 0.05, 0.12, 0.65 * fade * minf(1.0, age * 4.0)), sd * 0.5)
		"poison":      # 독 거품이 오른다
			for j in 7:
				var h1 := fposmod(sin(sd * 1.9 + j * 4.7) * 211.3, 1.0)
				var q := fposmod(age * 0.8 + h1, 1.0)
				var p := c + Vector2((h1 - 0.5) * u * 1.6, -q * u * 1.4)
				var r := u * (0.06 + 0.06 * h1) * (0.6 + q)
				ci.draw_circle(p, r, Color(0.55, 0.85, 0.3, 0.8 * sin(PI * q) * fade))
				ci.draw_arc(p, r, 0.0, TAU, 10, Color(INK, 0.6 * sin(PI * q) * fade), 1.2, true)
		"illusion":      # 보랏빛 구름이 감돌고 꽃잎이 흩날린다
			for j in 2:
				var ang := age * 2.2 + j * PI + sd
				_ink(ci, "cloud", c + Vector2(cos(ang), sin(ang) * 0.5) * u * 0.8 - Vector2(0, u * 0.6), u * 0.9, Color(0.8, 0.62, 1.0, 0.9 * fade * minf(1.0, age * 5.0)), sin(ang) * 0.15)
			for j in 6:
				var ang := -age * 4.0 + j * TAU / 6.0
				_ink(ci, "petal", c + Vector2(cos(ang), sin(ang) * 0.5) * u * (0.6 + 0.4 * t) - Vector2(0, u * 0.3), u * 0.2, Color(1.0, 0.72, 0.9, 0.9 * fade), ang * 1.3)
		"aura":      # 금빛 별이 반짝인다
			for j in 3:
				var q := fposmod(age * 1.4 + j / 3.0, 1.0)
				var p := c + Vector2(sin(sd + j * 2.4) * u * 0.8, -u * (0.5 + 0.9 * q))
				_ink(ci, "star", p, u * 0.35 * sin(PI * q), Color(1.0, 0.86, 0.35, fade), age * 2.0 + j)
		"heal":      # 꽃잎이 흩날리며 내려앉는다
			for j in 7:
				var h1 := fposmod(sin(sd * 2.3 + j * 6.1) * 157.7, 1.0)
				var q := fposmod(age * 0.6 + h1, 1.0)
				var p := c + Vector2((h1 - 0.5) * u * 1.8 + sin(age * 3.0 + j) * u * 0.2, -u * 1.4 * (1.0 - q))
				_ink(ci, "petal", p, u * 0.2, Color(1.0, 0.78, 0.86, 0.95 * sin(PI * q) * fade), age * 2.0 + j)
		"charge":      # 금빛 발톱 자국 —— 돌진의 기세
			var hit_dir := Vector2.ZERO
			for h: Dictionary in e.hits:
				if h.at == at:
					hit_dir = h.dir
			var sa := _scr_ang(at, hit_dir if hit_dir != Vector2.ZERO else Vector2.RIGHT)
			var g := ease(minf(1.0, age / 0.12), 0.3)
			_ink(ci, "claw", c - Vector2(0, u * 0.25), u * 1.5 * g, Color(1.0, 0.78, 0.3, 0.95 * fade), sa - PI * 0.5)
		"roar":      # 맞은 자리 흙먼지가 번진다
			_ink_ground(ci, "ink_wash_%d" % (sd % 2), c, u * 2.2 * ease(minf(1.0, age / 0.3), 0.4), Color(0.72, 0.6, 0.4, 0.6 * fade), sd, 0.5)
		"arrowstorm":      # 화살 그늘 —— 땅이 짙어진다
			_ink_ground(ci, "ink_wash_%d" % (sd % 2), c, u * 2.6, Color(0.2, 0.17, 0.12, 0.45 * sin(PI * t)), sd, 0.5)

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
	if col.a <= 0.001 or sz < 1.0:
		return
	var radius := absf(sz) * stretch.length() * 0.5
	if c.x + radius < 0.0 or c.y + radius < 0.0 or c.x - radius > v.size.x or c.y - radius > v.size.y:
		return
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
## 11/25 사용자 「책략계가 하는 일이 눈에 띄지 않는다」 —— 1.5px 선 · 1.7px 점 → 가늘어지는 꼬리 · 먹 테두리 구슬 · 더하기 빛
const SPELL_COL := {"책사": Color(1.0, 0.55, 0.18), "모사": Color(0.55, 0.8, 1.0), "유생": Color(0.5, 0.95, 0.7)}
func _spell_orb(ci: CanvasItem, shot: Dictionary, tip: Vector2, trail: PackedVector2Array, t: float) -> void:
	var col: Color = SPELL_COL.get(str(shot.get("tag", "")), EMBER)
	if trail.size() >= 2:
		ci.draw_polyline(trail, Color(INK, 0.4), 4.5, false)
		for k in trail.size() - 1:
			var w := 3.6 * (1.0 - float(k) / trail.size())
			ci.draw_line(trail[k], trail[k + 1], Color(col, 0.9 * (1.0 - float(k) / trail.size())), maxf(1.0, w), false)
	ci.draw_circle(tip, 4.2, Color(INK, 0.55))
	ci.draw_circle(tip, 3.3, col)
	ci.draw_circle(tip, 1.6, Color(1, 1, 1, 0.95))
	_spr(ci, "light_02", tip, 26.0, Color(col, 0.8 * sin(clampf(t, 0.0, 1.0) * PI * 0.5 + 0.5)))

# ── 기술 · 잔기술 이펙트 (11/23) ──
## 11/23 사용자: 「전설 이하 전투가 재미없다 · 일반 기술도 이펙트 없이 글자만 뜬다」 —— 삽화 화면에서는 type2 의 2D 연출(fx)이 꺼져 있어
## 기술 · 잔기술은 이름 글자만 떴다. 기술 이름(없으면 종류 · 병종)으로 갈래를 골라 Kenney CC0 그림으로 그린다
## (assets/fx/kenney —— tools/scripts/make_fx_sprites.py). 판정 · 수치와 무관한 화면 연출. 잔기술은 작고 짧게(sc 0.7).
const SKILL_STYLE := {"화공": "fire", "불바다": "fire", "화시난발": "fire", "역병": "poison", "수공": "water", "수계": "water",
	"천문": "bolt", "봉인부적": "bolt", "요술": "bolt", "제왕술": "aura", "후발제인": "flash",
	"난무": "vortex", "유계": "vortex", "양호상쟁": "vortex", "혹세": "vortex", "이간": "vortex", "허실": "vortex", "진법": "vortex", "반간": "vortex", "봉계": "vortex",
	"저주": "curse", "밀계": "curse", "교란": "curse",
	"무쌍": "slash", "오관참장": "slash", "백인시비": "slash", "횡소천군": "slash", "방원지세": "slash", "팔문금쇄": "slash",
	"일점돌파": "pierce", "필사돌격": "charge", "철기유린": "charge", "위진": "charge", "위진소요진": "charge", "추격": "charge",
	"일제사격": "arrows", "화망": "firearrows", "저격": "snipe",
	"백기야습": "shadow", "암습": "shadow", "매복": "shadow", "배후차단": "shadow", "후미교란": "shadow",
	"장강방벽": "guard", "철옹성": "guard", "철벽방진": "guard",
	"격려": "heal", "결속": "heal", "독려": "heal", "인덕": "heal", "진두지휘": "aura", "격문": "aura", "고함": "aura", "고취": "aura"}
## 병종 잔기술이 하는 일(Battle.MINOR_ACT) → 갈래. 꺼져 있으면 잔기술 종류(MINOR_BASE_STYLE)로
const MINOR_ACT_STYLE := {"push": "pierce", "through": "through", "rain": "rain", "steal": "steal", "zone": "zone", "rout": "vortex", "rally": "heal", "burst": "burst"}
const MINOR_BASE_STYLE := {"fire": "fire", "fire_arrow": "firearrows", "poison": "poison", "rumor": "vortex", "roar": "vortex", "awe": "vortex",
	"curse": "curse", "shatter": "slash", "thunder": "bolt", "spark": "bolt", "cheer": "heal", "guard": "guard", "lance": "charge",
	"ambush": "shadow", "dagger": "shadow", "thrust": "pierce", "volley": "arrows"}
const SKILL_FX_LIFE := {"fire": 1.4, "poison": 1.8, "zone": 2.4, "water": 1.3, "bolt": 0.9, "burst": 0.9, "flash": 0.9, "vortex": 1.4, "curse": 1.2,
	"slash": 0.8, "pierce": 0.7, "charge": 1.0, "through": 0.9, "arrows": 0.9, "firearrows": 1.0, "rain": 1.0, "snipe": 0.8,
	"shadow": 0.9, "steal": 1.0, "heal": 1.4, "guard": 1.2, "aura": 1.4}
## 11/24 사용자: 「일반 기술 이펙트를 고유기랑 똑같은 걸 쓰면 어떡해, 최소한 작게라도」 —— 기술은 고유기(1.0)의 0.6, 잔기술은 그보다 작게
const SKILL_FX_SC := 0.6
const CASTER_SKILL_FX_SC := 0.8      # 11/25 책략계 기술은 조금 크게 (「책략계가 하는 일이 눈에 띄지 않는다」 —— 고유기 1.0 보다는 작게)
const MINOR_FX_SC := 0.45
const SELF_STYLES := ["heal", "guard", "aura"]
const MAX_SKILL_FX := 20
var skill_fx_q: Array = []
var _hero_skill_motion := {}
var skill_fx_seen := {}        # 점검용 —— 갈래마다 붙은 수 (tests/skill_fx_shot)


static func skill_style(name: String, kind: String, tag: String) -> String:
	if SKILL_STYLE.has(name):
		return SKILL_STYLE[name]
	match kind:
		"heal":
			return "heal"
		"def", "morale":
			return "curse"
		"int":
			return {"책사": "fire", "모사": "vortex", "유생": "flash"}.get(tag, "curse")
	return {"기병": "charge", "궁병": "arrows", "도적": "shadow", "창병": "pierce"}.get(tag, "slash")


## 기술 —— battle_view 가 기술 묶음을 시작할 때 (delay: 근접 0.1 · 화살 0.55 · 책략 0.45 —— 맞는 순간에 맞춘다)
func add_skill(name: String, a_key: String, targets: Array, kind: String, delay: float) -> void:
	var a: Squad = v.field.squads.get(a_key)
	if a != null:
		var caster_unit: bool = a.tag in SUPPORT_TAGS
		var style := skill_style(name, kind, a.tag)
		if DB.C.has(a.cid):
			_hero_skill_motion[a.key] = {"start": v.field.clock, "style": style, "kind": kind, "delay": delay}
		_add_skill_fx(style, a, targets, CASTER_SKILL_FX_SC if caster_unit else SKILL_FX_SC, delay)      # 시전 원 + 이름은 skill 사건에서 (caster.on_event)


## 잔기술 —— 맞는 순간 (Type2View.fx_minor 가 삽화 화면이면 이리 넘긴다)
func add_minor(mk: String, a_key: String, d_key: String) -> void:
	if int(v.load_lv) >= 3:
		return
	var a: Squad = v.field.squads.get(a_key)
	if a == null:
		return
	var st := ""
	if Battle.minor_act_enabled and Battle.MINOR_ACT.has(a.tag):
		st = str(MINOR_ACT_STYLE.get(str(Battle.MINOR_ACT[a.tag].act), ""))
		if st == "zone" and str((Battle.minor_def(mk).get("st", ["burn"]) as Array)[0]) == "plague":
			st = "poison"
	if st == "":
		st = str(MINOR_BASE_STYLE.get(str(War3D.MINOR_FX.get(mk, mk)), "slash"))
	_add_skill_fx(st, a, [d_key], MINOR_FX_SC, 0.0, true)


func _add_skill_fx(style: String, a: Squad, targets: Array, sc: float, delay: float, minor := false) -> void:
	var now: float = v.field.clock + delay
	var sd := absi(hash(a.key + style + str(Time.get_ticks_msec()))) % 997
	var tl := fx_tier(a)      # 11/24 등급 차등 —— 크기 (잔기술은 조금만) · 장식 (_tier_under · _tier_over)
	var e := {"k": style, "start": now, "end": now + float(SKILL_FX_LIFE.get(style, 1.0)) * (0.8 if sc < 1.0 else 1.0),
		"from": a.pos, "sc": sc * float((MINOR_TIER_SC if minor else FX_TIER_SC)[tl]), "sd": sd, "hits": [],
		"tl": tl, "tc": _fx_tier_col(a, tl), "minor": minor, "a": a.key}
	for o: Dictionary in skill_fx_q:      # 11/24 같은 부대 · 같은 갈래가 0.6초 안에 또 붙으면 겹쳐 그리지 않는다 (신화 판 위세가 45초에 200번 넘게 붙었다)
		if o.get("a", "") == a.key and o.k == style and absf(float(o.start) - now) < 0.6:
			skill_fx_seen["겹침 생략"] = int(skill_fx_seen.get("겹침 생략", 0)) + 1
			return
	for k in targets.slice(0, 4):
		var d: Squad = v.field.squads.get(k)
		if d == null or d == a:
			continue
		var spots := []
		for j in 5:      # 발자국 안 지점 —— 화면 쪽 해시 (전투 rng 를 건드리지 않는다)
			var h1 := float(hash(str(k) + ":" + str(j) + ":" + str(sd)) % 10007) / 10007.0
			var h2 := float(hash(str(j) + ":" + str(sd) + ":" + str(k)) % 10007) / 10007.0
			spots.append(d.pos + d.right() * (h1 * 2.0 - 1.0) * d.hw * 0.7 + d.fwd * (h2 * 2.0 - 1.0) * d.hd() * 0.5)
		var dir: Vector2 = (d.pos - a.pos).normalized() if d.pos != a.pos else d.fwd
		e.hits.append({"at": d.pos, "spots": spots, "dir": dir, "right": d.right(), "fwd": d.fwd, "hw": d.hw, "hd": d.hd()})
	if e.hits.is_empty() and not SELF_STYLES.has(style):
		return
	skill_fx_q.append(e)
	skill_fx_seen[style] = int(skill_fx_seen.get(style, 0)) + 1
	while skill_fx_q.size() > MAX_SKILL_FX:
		skill_fx_q.pop_front()


func _draw_skill_fx(ci: CanvasItem) -> void:
	for e: Dictionary in skill_fx_q:
		var age := last_clock - float(e.start)
		if age < 0.0:
			continue
		var life := float(e.end) - float(e.start)
		var t := clampf(age / life, 0.0, 1.0)
		var fade := 1.0 - smoothstep(0.65, 1.0, t)
		if SELF_STYLES.has(e.k):
			_tier_under(ci, e, e.from, age, fade)
			_skill_self(ci, e, age, t, fade)
			_tier_over(ci, e, e.from, age, fade)
			continue
		for i in e.hits.size():
			var hit: Dictionary = e.hits[i]
			var ai: float = age - i * 0.06
			if ai < 0.0:
				continue
			_tier_under(ci, e, hit.at, ai, fade)
			_skill_hit(ci, e, hit, ai, life, fade)
			_tier_over(ci, e, hit.at, ai, fade)


## 화면에서 hit.dir 이 가리키는 각
func _scr_ang(at: Vector2, dir: Vector2) -> float:
	return (v.map(at + dir * 20.0) - v.map(at)).angle()


## 11/23 황토 땅 위에서 읽히게 —— 고유기처럼 진한 도형 + 먹 테두리가 바탕이고, Kenney 그림(폭발 · 독안개 · 섬광 · 먼지 · 연기)은 보통 합성으로 얹는다.
## 더하기 합성 그림(빛 · 별)은 밝은 땅에서 거의 안 보여 곁들임으로만.
func _skill_hit(ci: CanvasItem, e: Dictionary, hit: Dictionary, age: float, life: float, fade: float) -> void:
	if age < 0.0:
		return
	var sc: float = e.sc
	var sd: int = e.sd
	var at: Vector2 = hit.at
	var c: Vector2 = v.map(at)
	var u := maxf(30.0, _px(at, 115.0)) * sc
	var sp: Array = hit.spots
	var t := clampf(age / life, 0.0, 1.0)
	var sa := _scr_ang(at, hit.dir)
	var sdir := Vector2.from_angle(sa)
	var big := sc >= 1.0 or bool(e.get("big", false))      # 빠른 고유기(big)는 갈래마다 겹을 많이
	match e.k:
		"fire":      # 불덩이가 터지고(폭발 그림) 불길이 혀를 날름거리다 검은 연기가 오른다
			_ellipse(ci, c, u * 0.9, u * 0.4, Color(0.2, 0.06, 0.02, 0.35 * fade))
			for j in (3 if big else 2):
				var a2 := age - j * 0.09
				if a2 < 0.0:
					continue
				var p: Vector2 = v.map(sp[j])
				var g := ease(minf(1.0, a2 / 0.25), 0.4)
				_flame(ci, p, u * (0.75 + 0.2 * sin(a2 * 10.0 + j)) * g, u * 0.2, a2 * 8.0 + j, 0.95 * fade)
				if a2 < 0.8:
					_spr(ci, "explosion%02d" % [0, 2, 4, 6][(sd + j) % 4], p - Vector2(0, u * 0.3), u * (0.7 + 0.8 * g), Color(1, 1, 1, 1.0 - smoothstep(0.4, 0.8, a2)), sd + j * 1.7)
				if a2 > 0.35:
					var r2 := clampf((a2 - 0.35) / maxf(0.2, life - 0.35), 0.0, 1.0)
					_spr(ci, "blackSmoke%02d" % [0, 3, 6, 9][(sd + j) % 4], p - Vector2(0, u * (0.5 + 0.7 * r2)), u * (0.6 + 0.5 * r2), Color(1, 1, 1, 0.55 * (1.0 - r2)), sd - j)
			for j in (2 if big else 1):      # 11/24 먹 선 불꽃 —— 삽화풍 불길 한 송이 (큰 것은 둘)
				var a2 := age - 0.05 - j * 0.12
				if a2 <= 0.0:
					continue
				var fz := u * (0.95 if j == 0 else 0.75) * ease(minf(1.0, a2 / 0.2), 0.4) * (1.0 + 0.06 * sin(a2 * 14.0 + j))
				_ink(ci, "flame_%d" % ((sd + j) % 2), v.map(sp[j + 2]) - Vector2(0, fz * 0.45), fz, Color(1, 1, 1, 0.95 * fade), sin(a2 * 6.0 + j) * 0.06)
		"poison":      # 초록 독안개 덩이가 퍼지며 머문다
			var g0 := minf(1.0, age * 3.0)
			_ink_ground(ci, "ink_wash_%d" % (sd % 2), c, u * 2.3 * g0, Color(0.3, 0.52, 0.1, 0.65 * fade), sd, 0.5)      # 11/24 먹 번짐 독물
			_ellipse(ci, c, u * 1.0 * g0, u * 0.45 * g0, Color(0.14, 0.28, 0.06, 0.45 * fade))
			for j in 4:
				var a2 := age - j * 0.1
				if a2 < 0.0:
					continue
				var r2 := clampf(a2 / life, 0.0, 1.0)
				_spr(ci, "fart%02d" % [0, 2, 4, 6][(sd + j) % 4], v.map(sp[j]) - Vector2(0, u * 0.25 * r2), u * (0.7 + 0.5 * ease(minf(1.0, a2 / 0.4), 0.4)), Color(1, 1, 1, 0.85 * fade * minf(1.0, a2 * 5.0)), sd + j + a2 * 0.5)
		"zone":      # 땅에 불길이 남는다 (책사 잔기술 —— 들어선 적이 탄다)
			var al := minf(1.0, age * 5.0) * fade
			_ellipse(ci, c, u * 1.1, u * 0.5, Color(0.25, 0.07, 0.02, 0.4 * al))
			for j in 5:
				_flame(ci, v.map(sp[j]), u * (0.6 + 0.18 * sin(age * 9.0 + j)), u * 0.18, age * 8.0 + j * 1.3, 0.9 * al)
			if age < 0.5:
				_spr(ci, "explosion%02d" % [0, 2, 4, 6][sd % 4], c - Vector2(0, u * 0.25), u * (0.8 + age), Color(1, 1, 1, 1.0 - age / 0.5), sd)
		"water":      # 물결 —— 푸른 초승달 물마루가 시전자 쪽에서 적진을 쓸고, 물보라가 인다
			var side := sdir.orthogonal()
			_ellipse(ci, c, u * 1.1, u * 0.45, Color(0.1, 0.25, 0.45, 0.35 * fade))
			for j in 3:
				var a2 := age - j * 0.12
				if a2 < 0.0 or a2 > life * 0.8:
					continue
				var r2 := a2 / (life * 0.8)
				var w: Vector2 = c + sdir * u * (-1.0 + 2.0 * ease(r2, 0.6)) + side * (j - 1) * u * 0.5
				_crescent(ci, w, u * 0.7, sa - 1.1, 2.2, u * 0.22, Color(0.45, 0.72, 1.0, 0.9 * (1.0 - r2)), 0.6)
				if j == 1 or (big and j == 0):      # 11/24 먹 선 물마루 —— 나아가는 쪽으로 말린다
					_ink(ci, "wave", w - Vector2(0, u * 0.3), u * (1.0 if j == 1 else 0.8), Color(1, 1, 1, 0.95 * (1.0 - r2 * r2)), 0.0, Vector2(-1.0 if sdir.x < 0.0 else 1.0, 1.0))
				_spr(ci, "whitePuff%02d" % [0, 3, 6, 9][(sd + j) % 4], w + sdir * u * 0.3, u * (0.6 + 0.4 * r2), Color(0.75, 0.9, 1.0, 0.75 * (1.0 - r2)), sd + j)
			if big:      # 얼음 조각이 튄다 (수계)
				for j in 4:
					var q := clampf((age - 0.15) / 0.6, 0.0, 1.0)
					if q <= 0.0 or q >= 1.0:
						continue
					var dd := Vector2.from_angle(-PI * 0.5 + (j - 1.5) * 0.55)
					_ink(ci, "ice", c + dd * u * (0.3 + 0.9 * q) + Vector2(0, u * q * q * 0.8), u * 0.35, Color(0.7, 0.88, 1.0, 1.0 - q), dd.angle() + PI * 0.5)
		"bolt":      # 낙뢰 —— 하늘에서 지그재그 벼락이 꽂히고 섬광 · 그을음
			var tal_a := fade * (1.0 - smoothstep(0.45, 0.85, age))
			if tal_a > 0.01:      # 11/24 부적 —— 하늘에서 내려와 붙고, 벼락과 함께 타들어 간다
				var tq := ease(clampf(age / 0.25, 0.0, 1.0), 0.4)
				_ink(ci, "talisman", c - Vector2(0, u * (1.6 - 0.55 * tq)), u * 0.8, Color(1, 1, 1, tal_a), sin(age * 5.0 + sd) * 0.15)
			for j in (2 if big else 1):
				var a2 := age - j * 0.16
				if a2 < 0.0:
					continue
				var p: Vector2 = v.map(sp[j])
				_ellipse(ci, p, u * 0.5, u * 0.22, Color(0.08, 0.08, 0.12, 0.5 * fade))
				if a2 < 0.45:
					var q := a2 / 0.45
					var flicker := 1.0 if fmod(a2 * 30.0 + j, 2.0) < 1.4 else 0.5
					_bolt(ci, Vector2(p.x + sin(sd + j * 4.1) * u * 0.8, maxf(40.0, p.y - u * 4.5)), p, float(sd + j), Color(0.65, 0.8, 1.0), (1.0 - q * 0.6) * flicker)
					_spr(ci, "flash%02d" % [0, 2, 4, 6][(sd + j) % 4], p - Vector2(0, u * 0.15), u * (0.6 + 0.6 * q), Color(0.8, 0.9, 1.0, 1.0 - q), sd + j)
		"burst", "flash":      # 둘레로 터지는 섬광 + 먹 테두리 충격파 고리 (후발제인)
			var warm: bool = e.k == "flash"
			var col := Color(1.0, 0.82, 0.35) if warm else Color(0.78, 0.6, 1.0)
			var g := ease(minf(1.0, age / 0.25), 0.4)
			_spr(ci, "flash%02d" % [0, 2, 4, 6][sd % 4], c - Vector2(0, u * 0.25), u * (0.9 + 1.0 * g), Color(1, 1, 1, fade) if warm else Color(0.85, 0.75, 1.0, fade), sd)
			_ink(ci, "star", c - Vector2(0, u * 0.3), u * (0.45 + 0.6 * g) * (1.0 - 0.35 * t), Color(col, fade), age * 1.5 + sd)      # 11/24 먹 테 별빛
			for j in 2:
				var q := clampf((age - j * 0.12) / 0.6, 0.0, 1.0)
				if q > 0.0 and q < 1.0:
					_world_ring(ci, at, 20.0 + q * 95.0 * sc, Color(col, 0.9 * (1.0 - q)), 4.0 - j * 1.5)
		"vortex":      # 보랏빛 소용돌이 두 갈래가 적진을 감는다 (혼란 · 사기)
			var al := sin(PI * t)
			_ink_ground(ci, "ink_wash_%d" % (sd % 2), c, u * 2.2, Color(0.4, 0.2, 0.55, 0.6 * al), sd + age * 0.5, 0.5)      # 11/24 보랏빛 먹 번짐
			_ellipse(ci, c, u * 1.0, u * 0.45, Color(0.18, 0.06, 0.25, 0.35 * al))
			if big:      # 구름이 감돈다
				var ang := age * 2.5 + sd
				_ink(ci, "cloud", c + Vector2(cos(ang), sin(ang) * 0.5) * u * 0.6 - Vector2(0, u * 0.5), u * 0.8, Color(0.82, 0.65, 1.0, 0.9 * al), sin(ang) * 0.15)
			for arm in 2:
				var pts := PackedVector2Array()
				for k in 16:
					var q := float(k) / 15.0
					var ang := age * 5.0 + arm * PI + q * 4.0
					pts.append(c + Vector2(cos(ang), sin(ang) * 0.5) * u * 1.1 * (1.0 - q * 0.85))
				ci.draw_polyline(pts, Color(INK, 0.4 * al), 7.0, true)
				ci.draw_polyline(pts, Color(0.8, 0.55, 1.0, 0.95 * al), 3.5, true)
		"curse":      # 땅에 검보라 법진 —— 두 겹 고리 + 별, 짙은 기운이 피어오른다 (방깎 · 저주)
			var al := sin(PI * t)
			_ink_ground(ci, "ink_splash_%d" % (sd % 3), c, u * 1.9 * ease(minf(1.0, age / 0.25), 0.4), Color(0.3, 0.12, 0.42, 0.75 * al), sd, 0.5)      # 11/24 검보라 먹이 번진다
			_world_ring(ci, at, 48.0 * sc, Color(0.62, 0.3, 0.85, 0.9 * al), 3.0)
			_world_ring(ci, at, 32.0 * sc, Color(0.62, 0.3, 0.85, 0.6 * al), 1.8)
			var star := PackedVector2Array()
			for k in 6:
				var ang := age * 1.5 + k * TAU * 2.0 / 5.0
				star.append(v.map(at + Vector2(cos(ang), sin(ang)) * 45.0 * sc))
			ci.draw_polyline(star, Color(0.8, 0.55, 1.0, 0.8 * al), 2.0, true)
			for j in 3:
				var a2 := age - j * 0.1
				if a2 < 0.0:
					continue
				var r2 := clampf(a2 / life, 0.0, 1.0)
				_spr(ci, "blackSmoke%02d" % [0, 3, 6, 9][(sd + j) % 4], v.map(sp[j]) - Vector2(0, u * (0.2 + 0.6 * r2)), u * (0.5 + 0.4 * r2), Color(0.55, 0.35, 0.7, 0.7 * (1.0 - r2)), sd + j)
		"slash":      # 일섬 —— 굵은 빛 선이 엇갈려 그어지고 먹 자국 · 먹 튐이 남는다
			var angs: Array = [[-0.9, 0.7, -0.2], [0.1, -0.8, 0.9], [-1.2, 0.0, 1.2]][sd % 3]
			for j in (3 if big else 1):
				var a2 := age - j * 0.08
				if a2 < 0.0 or a2 > 0.6:
					continue
				var p: Vector2 = (v.map(sp[j]) if big else c) + Vector2(0, -u * 0.2)
				_iseom(ci, p, float(angs[j]), u * (2.4 if big else 1.8), u * 0.11, Color(1.0, 0.86, 0.5), a2 / 0.6, sd + j)
			for j in (2 if big else 1):      # 11/24 붓 획 벤 자국 —— 번쩍인 뒤 마른 붓으로 그은 먹 획이 남는다
				var a3 := age - j * 0.08 - 0.1
				if a3 <= 0.0:
					continue
				var p: Vector2 = (v.map(sp[j]) if big else c) + Vector2(0, -u * 0.2)
				var dd := Vector2(cos(float(angs[j])), sin(float(angs[j])) * 0.6)
				var bl := u * (2.4 if big else 1.8) * (0.5 + 0.5 * ease(minf(1.0, a3 / 0.1), 0.3))
				_ink(ci, "brush_%d" % ((sd + j) % 2), p, bl, Color(INK, 0.8 * (1.0 - smoothstep(0.35, 0.8, t))), dd.angle(), Vector2(1.0, 0.6))
		"pierce":      # 찌르기 —— 창끝 방향으로 곧은 빛 선이 꿰뚫고, 맞은 자리에서 흙먼지가 밀려난다 (창병 잔기술 = 밀쳐 냄)
			_iseom(ci, c - sdir * u * 0.3, atan2(sdir.y / 0.6, sdir.x), u * 2.0, u * 0.12, Color(1.0, 0.92, 0.65), clampf(age / 0.5, 0.0, 1.0), sd)
			if age > 0.1:      # 11/24 꿰뚫린 자리에 먹이 튄다 (찌른 쪽으로 길게)
				_ink(ci, "ink_splash_%d" % (sd % 3), c + sdir * u * 0.35, u * 0.9 * ease(minf(1.0, (age - 0.1) / 0.15), 0.3), Color(INK, 0.6 * fade), sa, Vector2(1.0, 0.6))
			for k in 3:
				var q := clampf((age - 0.05) / 0.6, 0.0, 1.0)
				if q <= 0.0 or q >= 1.0:
					continue
				var p := c + sdir * u * (0.3 + 0.6 * q) + sdir.orthogonal() * (k - 1) * u * 0.35
				var rr := u * (0.18 + 0.25 * q)
				ci.draw_circle(p, rr, Color(0.8, 0.71, 0.52, 0.8 * (1.0 - q)))
				ci.draw_arc(p, rr, PI * 0.9, PI * 2.1, 10, Color(INK, 0.45 * (1.0 - q)), 1.6, true)
		"charge", "through":      # 기병 —— 부딪힌 자리에 흙구름 · 파편. through 는 뒤 부대까지 꿰뚫는 빛 선
			var q := clampf(age / (life * 0.9), 0.0, 1.0)
			var side := sdir.orthogonal()
			for k in (5 if big else 4):
				var p := c - sdir * u * 0.3 + side * (k - 2) * u * 0.32 + Vector2(0, -q * u * 0.4 * (1 + k % 2))
				var rr := u * (0.22 + q * 0.35)
				ci.draw_circle(p, rr, Color(0.8, 0.71, 0.52, 0.85 * (1.0 - q)))
				ci.draw_arc(p, rr, PI * 0.9, PI * 2.1, 10, Color(INK, 0.5 * (1.0 - q)), 1.8, true)
			var deb := PackedVector2Array()
			for k in 8:
				var dd := sdir.rotated(-1.1 + k * 0.31)
				var p0 := c - sdir * u * 0.3 + dd * u * (0.2 + q * 0.9)
				deb.append(p0)
				deb.append(p0 + dd * u * 0.12)
			ci.draw_multiline(deb, Color(INK, 0.85 * (1.0 - q)), 2.5, true)
			if e.k == "charge":      # 11/24 기세 —— 붉은 금빛 발톱 자국 세 줄이 부딪힌 쪽으로 할퀸다
				_ink(ci, "claw", c - Vector2(0, u * 0.2), u * 1.1 * ease(minf(1.0, age / 0.1), 0.3), Color(1.0, 0.62, 0.25, 0.9 * (1.0 - q)), sa - PI * 0.5)
			if e.k == "through":
				_iseom(ci, c + sdir * u * 0.6, atan2(sdir.y / 0.6, sdir.x), u * 3.0, u * 0.1, Color(1.0, 0.88, 0.55), clampf(age / 0.55, 0.0, 1.0), sd)
		"arrows", "firearrows", "rain":      # 화살이 쏟아져 꽂히고 흙이 튄다 (rain = 둘레 넓게)
			var fire: bool = e.k == "firearrows"
			var n := 12 if big or e.k == "rain" else 7
			var spread := 1.8 if e.k == "rain" else 1.0
			var from := -sdir * u * 0.9 + Vector2(0, -u * 1.6)
			var right: Vector2 = hit.right
			var fwd: Vector2 = hit.fwd
			var lines := PackedVector2Array()
			for i in n:
				var a2 := age - i * 0.03
				if a2 < 0.0:
					continue
				var h1 := fposmod(sin(sd * 3.1 + i * 7.7) * 431.7, 1.0)
				var h2 := fposmod(sin(sd * 5.3 + i * 3.9) * 917.3, 1.0)
				var p: Vector2 = v.map(at + right * (h1 * 2.0 - 1.0) * float(hit.hw) * spread + fwd * (h2 * 2.0 - 1.0) * float(hit.hd) * spread)
				if a2 < 0.25:
					var head := p + from * (1.0 - a2 / 0.25)
					lines.append(head + from.normalized() * u * 0.55)
					lines.append(head)
				elif a2 < 0.65:      # 꽂힌 화살 + 튄 흙 (불화살은 불꽃)
					var q := (a2 - 0.25) / 0.4
					lines.append(p + from.normalized() * u * 0.25)
					lines.append(p)
					if fire:
						_flame(ci, p, u * 0.35 * (1.0 - q * 0.5), u * 0.08, a2 * 9.0 + i, 0.9 * (1.0 - q))
					else:
						ci.draw_circle(p, u * (0.06 + 0.1 * q), Color(0.75, 0.65, 0.45, 0.8 * (1.0 - q)))
			if not lines.is_empty():
				ci.draw_multiline(lines, Color(INK, 0.85 * fade), 2.6, true)
				ci.draw_multiline(lines, Color(EMBER, fade) if fire else Color(PAPER, 0.95 * fade), 1.2, true)
		"snipe":      # 저격 —— 길고 곧은 한 줄기가 후열에 꽂히고 고리가 퍼진다
			if age < 0.2:
				var q := age / 0.2
				var head := c - sdir * u * 3.0 * (1.0 - q)
				ci.draw_line(head - sdir * u * 1.0, head, Color(INK, 0.85), 4.0, true)
				ci.draw_line(head - sdir * u * 1.0, head, Color(1.0, 0.95, 0.75), 2.0, true)
			else:
				var q := clampf((age - 0.2) / maxf(0.1, life - 0.2), 0.0, 1.0)
				_world_ring(ci, at, 10.0 + q * 50.0, Color(1.0, 0.9, 0.55, 0.9 * (1.0 - q)), 3.0)
				_spr(ci, "flash%02d" % [0, 2, 4, 6][sd % 4], c - Vector2(0, u * 0.1), u * (0.5 + 0.3 * q), Color(1, 1, 1, 1.0 - q), sd)
				_ink(ci, "star", c - Vector2(0, u * 0.1), u * 0.5 * (1.0 - q), Color(1.0, 0.9, 0.55, 1.0 - q), age * 3.0)      # 11/24
		"shadow", "steal":      # 어둠이 번지고 보랏빛 일섬이 엇갈린다 (도적). steal 은 빼앗은 기운이 시전자에게 날아간다
			_ink_ground(ci, "ink_splash_%d" % (sd % 3), c, u * 2.0 * ease(minf(1.0, age / 0.2), 0.4), Color(0.06, 0.04, 0.09, 0.8 * fade), sd, 0.5)      # 11/24 먹물이 번진다
			_ellipse(ci, c, u * 1.0, u * 0.45, Color(0.05, 0.03, 0.08, 0.45 * fade))
			for j in 2:
				var a2 := age - j * 0.08
				if a2 < 0.0:
					continue
				var r2 := clampf(a2 / life, 0.0, 1.0)
				_spr(ci, "blackSmoke%02d" % [0, 3, 6, 9][(sd + j) % 4], v.map(sp[j]), u * (0.6 + 0.4 * r2), Color(0.35, 0.25, 0.45, 0.7 * (1.0 - r2)), sd + j)
				var a3 := a2 - 0.1
				if a3 > 0.0 and a3 < 0.55:
					_iseom(ci, c + Vector2(0, -u * 0.2), [-0.8, 0.8][j], u * 1.8, u * 0.1, Color(0.8, 0.65, 1.0), a3 / 0.55, sd + j)
			if e.k == "steal" and age > 0.2 and age < 0.85:
				var q := (age - 0.2) / 0.65
				var orb := c.lerp(v.map(e.from), ease(q, 0.5)) - Vector2(0, sin(PI * q) * u * 0.8)
				ci.draw_circle(orb, u * 0.14, Color(INK, 0.6))
				ci.draw_circle(orb, u * 0.11, Color(0.75, 0.5, 1.0))
				ci.draw_circle(orb, u * 0.05, Color(1, 1, 1, 0.95))


## 시전자 둘레 —— 회복(초록 고리 · 오르는 빛 구슬) · 방어(푸른 빛 막 · 두꺼운 고리) · 위세(금빛 햇살 고리)
func _skill_self(ci: CanvasItem, e: Dictionary, age: float, t: float, fade: float, at := Vector2.INF) -> void:
	var from: Vector2 = e.from if at == Vector2.INF else at      # 빠른 고유기 —— 아군 부대마다 (at)
	var fc: Vector2 = v.map(from)
	var sc: float = e.sc
	var u := maxf(30.0, _px(from, 115.0)) * sc
	var sd: int = e.sd
	match e.k:
		"heal":
			var al := sin(PI * t)
			_ellipse(ci, fc, u * 0.9, u * 0.4, Color(0.4, 0.95, 0.6, 0.3 * al))
			_world_ring(ci, from, 40.0 * sc + 25.0 * t, Color(0.45, 1.0, 0.65, 0.9 * al), 3.0)
			for j in 6:
				var h1 := fposmod(sin(sd * 1.7 + j * 4.1) * 311.3, 1.0)
				var q := fposmod(age * 1.1 + j / 6.0, 1.0)
				var p := fc + Vector2((h1 - 0.5) * u * 1.4, -q * u * 1.4)
				var a := sin(PI * q) * fade
				ci.draw_circle(p, u * 0.08, Color(INK, 0.45 * a))
				ci.draw_circle(p, u * 0.065, Color(0.55, 1.0, 0.7, a))
				ci.draw_circle(p, u * 0.03, Color(1, 1, 1, a))
			for j in 4:      # 11/24 연둣빛 잎이 감돌며 오른다
				var q := fposmod(age * 0.9 + j * 0.25, 1.0)
				var ang := age * 3.0 + j * TAU / 4.0
				_ink(ci, "petal", fc + Vector2(cos(ang) * u * 0.7, -q * u * 1.2 + sin(ang) * u * 0.15), u * 0.2, Color(0.6, 0.95, 0.55, sin(PI * q) * fade), ang)
		"guard", "aura":
			var gold: bool = e.k == "aura"
			var col := Color(1.0, 0.82, 0.35) if gold else Color(0.6, 0.8, 1.0)
			var g := ease(minf(1.0, age / 0.3), 0.3)
			if gold:      # 11/24 금빛 상서로운 구름이 피어오른다
				_ink(ci, "cloud", fc - Vector2(0, u * (0.7 + 0.35 * t)), u * 1.0 * (0.7 + 0.3 * g), Color(1.0, 0.85, 0.4, 0.9 * fade * g))
			else:      # 귀갑 방패 막
				_ink(ci, "shell", fc - Vector2(0, u * 0.3), u * (1.5 + 0.3 * g), Color(0.62, 0.82, 1.0, 0.85 * fade * g), 0.0, Vector2(1.0, 0.75))
			_ellipse(ci, fc - Vector2(0, u * 0.15), u * (0.9 + 0.3 * g), u * (0.55 + 0.2 * g), Color(col, 0.22 * fade))
			_world_ring(ci, from, (36.0 + 14.0 * g) * sc, Color(col, 0.95 * fade), 4.0)
			_world_ring(ci, from, (52.0 + 20.0 * g) * sc, Color(col, 0.55 * fade), 2.0)
			if gold:
				for j in 2:
					var q := clampf((age - j * 0.2) / 0.8, 0.0, 1.0)
					if q > 0.0 and q < 1.0:
						_world_ring(ci, from, 30.0 + q * 130.0 * sc, Color(col, (1.0 - q) * 0.9), 3.5 - j * 1.5)

# ── 먹 그림풍 효과 그림 · 등급 차등 (11/24) ──
## assets/fx/ink —— tools/scripts/make_ink_fx.py 가 그린 먹 번짐 · 붓 획 · 원상 · 부적 · 인장 · 꽃잎 · 얼음 · 불꽃 · 파도 · 구름 · 별 · 귀갑 · 발톱.
## 보통 합성 —— 흰 가면은 col 을 곱해 물들이고(먹이면 INK), 먹 테두리 그림은 채움만 물든다. 정사각이 아닌 그림(붓 획 · 부적)은 긴 변이 sz
static var _ink_tex := {}
func _ink(ci: CanvasItem, nm: String, c: Vector2, sz: float, col: Color, rot := 0.0, stretch := Vector2.ONE) -> void:
	if col.a <= 0.01 or sz < 2.0:
		return
	var tex := _ink_get(nm)
	if tex == null:
		return
	var ts := tex.get_size()
	var half := ts / maxf(ts.x, ts.y) * sz * 0.5
	var radius := half.length() * maxf(absf(stretch.x), absf(stretch.y))
	if c.x + radius < 0.0 or c.y + radius < 0.0 or c.x - radius > v.size.x or c.y - radius > v.size.y:
		return
	ci.draw_set_transform(c, rot, stretch)
	ci.draw_texture_rect(tex, Rect2(-half, half * 2.0), false, col)
	ci.draw_set_transform(Vector2.ZERO)


## 땅에 누운 그림 —— 땅 위에서 rot 만큼 돌린 뒤 위아래를 squash 로 눌러 원근을 준다 (원상 · 먹 번짐)
func _ink_ground(ci: CanvasItem, nm: String, c: Vector2, sz: float, col: Color, rot := 0.0, squash := 0.5) -> void:
	if col.a <= 0.01 or sz < 2.0:
		return
	var tex := _ink_get(nm)
	if tex == null:
		return
	var r := sz * 0.5
	if c.x + r < 0.0 or c.y + r * squash < 0.0 or c.x - r > v.size.x or c.y - r * squash > v.size.y:
		return
	ci.draw_set_transform_matrix(Transform2D(Vector2(cos(rot), sin(rot) * squash), Vector2(-sin(rot), cos(rot) * squash), c))
	ci.draw_texture_rect(tex, Rect2(-Vector2(r, r), Vector2(sz, sz)), false, col)
	ci.draw_set_transform(Vector2.ZERO)


func _ink_get(nm: String) -> Texture2D:
	if _ink_tex.has(nm):
		return _ink_tex[nm]
	var path := "res://assets/fx/ink/%s.png" % nm
	var tex: Texture2D = load(path) if ResourceLoader.exists(path) else null
	_ink_tex[nm] = tex
	return tex


## 11/24 사용자: 「등급에 따른 이펙트도 차등」 —— 시전 부대 등급(Squad.tier · 기인)으로 기술 · 잔기술 · 빠른 고유기 이펙트를 나눈다
##   0 기본 · 일반 · 고급, 1 희귀 —— 담백 (크기만) / 2 전설 —— 금빛 불티 / 3 기인 · 초월 —— + 등급 색 원상 (기인 옥빛 · 초월 하늘빛)
##   4 불멸 —— + 원상 두 겹 (주황 · 금) / 5 신화 —— 흑금: 금 테 두른 먹 번짐 + 먹 원상 + 금빛 충격파 + 먹 불티 섞임
## 잔기술은 여전히 담백하게 —— 크기만 조금, 장식은 신화의 옅은 먹 원상 하나
## 신화 아홉이 한꺼번에 쓰는 판에서도 화면이 금빛으로 덮이지 않게 겹은 둘까지 (11/24 점검: 원상 세 겹 · 큰 충격파는 과했다)
const FX_TIER_SC := [0.9, 1.0, 1.08, 1.15, 1.22, 1.3]
const MINOR_TIER_SC := [0.92, 1.0, 1.03, 1.06, 1.09, 1.12]
const FX_TIER_EMBERS := [0, 0, 4, 5, 6, 6]
static func fx_tier(a: Squad) -> int:
	if a == null:
		return 0
	if DB.C.has(a.cid) and DB.is_kiin(a.cid):
		return 3
	return [0, 0, 0, 0, 1, 2, 3, 4, 5][clampi(a.tier, 0, 8)]


func _fx_tier_col(a: Squad, tl: int) -> Color:
	if tl == 3 and a != null and DB.C.has(a.cid) and DB.is_kiin(a.cid):
		return DB.KIIN_COL
	return [Color(1, 1, 1), Color("#c79bff"), Color("#ffd257"), Color("#6fd6ff"), Color("#ff9a3c"), Color("#ffd23a")][clampi(tl, 0, 5)]


## 등급 장식 —— 효과 밑 (땅): 원상 · 흑금 먹 번짐
func _tier_under(ci: CanvasItem, e: Dictionary, at: Vector2, age: float, fade: float) -> void:
	var tl := int(e.get("tl", 0))
	var minor := bool(e.get("minor", false))
	if tl < 3 or (minor and tl < 5):
		return
	var c: Vector2 = v.map(at)
	var u := maxf(30.0, _px(at, 115.0)) * float(e.sc)
	var g := ease(minf(1.0, age / 0.3), 0.4)
	var sd := int(e.sd)
	if minor:      # 신화 잔기술 —— 옅은 먹 원상 하나만
		_ink_ground(ci, "enso_%d" % (sd % 2), c, u * 1.5 * (0.85 + 0.15 * g), Color(INK, 0.55 * fade * g), age * 0.8 + sd, 0.5)
		return
	if tl >= 5:      # 신화 —— 금 테를 두른 먹이 땅에 튀고, 그 위에 먹 원상
		var nm := "ink_splash_%d" % (sd % 3)
		var sf := fade * (1.0 - 0.6 * smoothstep(0.5, 1.2, age))      # 먹 번짐은 일찍 옅어진다 (신화 판이 먹투성이가 되지 않게)
		_ink_ground(ci, nm, c, u * (2.1 * g + 0.2), Color(1.0, 0.78, 0.22, 0.95 * sf), sd * 0.7, 0.5)
		_ink_ground(ci, nm, c, u * (1.85 * g + 0.15), Color(0.07, 0.06, 0.05, 0.85 * sf), sd * 0.7, 0.5)
		_ink_ground(ci, "enso_%d" % (sd % 2), c, u * 1.7 * (0.85 + 0.15 * g), Color(INK, 0.85 * fade * g), age * 0.8 + sd, 0.5)
		return
	_ink_ground(ci, "enso_%d" % (sd % 2), c, u * 1.7 * (0.85 + 0.15 * g), Color(e.get("tc", Color.WHITE), 0.85 * fade * g), age * 0.8 + sd, 0.5)
	if tl == 4:      # 불멸 —— 거꾸로 도는 금빛 원상 한 겹 더
		_ink_ground(ci, "enso_%d" % ((sd + 1) % 2), c, u * 1.3 * (0.85 + 0.15 * g), Color(1.0, 0.82, 0.3, 0.75 * fade * g), -age * 1.1 - sd, 0.5)


## 등급 장식 —— 효과 위: 금빛 불티 (신화는 먹 불티가 섞이고 금빛 충격파가 한 겹 더)
func _tier_over(ci: CanvasItem, e: Dictionary, at: Vector2, age: float, fade: float) -> void:
	var tl := int(e.get("tl", 0))
	if tl < 2 or bool(e.get("minor", false)):
		return
	var c: Vector2 = v.map(at)
	var u := maxf(30.0, _px(at, 115.0)) * float(e.sc)
	var sd := int(e.sd)
	for j in int(FX_TIER_EMBERS[tl]):
		var h1 := fposmod(sin(sd * 1.3 + j * 7.1) * 513.7, 1.0)
		var h2 := fposmod(sin(sd * 2.7 + j * 3.3) * 271.9, 1.0)
		var q := fposmod(age * (0.7 + 0.5 * h2) + h1, 1.0)
		var p := c + Vector2((h1 - 0.5) * u * 1.7 + sin(age * 3.0 + j) * u * 0.12, u * 0.1 - q * u * 1.6)
		var ec: Color = Color(INK) if tl >= 5 and j % 3 == 0 else (Color(1.0, 0.78, 0.25) if tl != 3 else Color(e.get("tc", Color.WHITE)).lerp(Color(1.0, 0.85, 0.4), 0.4))
		_ink(ci, "ember", p, maxf(9.0, u * (0.5 + 0.15 * h2)) * (1.0 - q * 0.35), Color(ec, sin(PI * q) * fade), sin(age * 2.0 + j) * 0.4)
	if tl >= 5 and age < 0.5:      # 신화 —— 금빛 충격파 한 겹 (먹 테)
		var q2 := age / 0.5
		_world_ring(ci, at, 15.0 + q2 * 95.0 * float(e.sc), Color(1.0, 0.84, 0.3, 0.9 * (1.0 - q2)), 3.5)
