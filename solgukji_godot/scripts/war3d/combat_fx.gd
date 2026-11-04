class_name CombatFx
extends Node3D
## 전투 알림 효과 (10/31 사용자: 삼국지13 처럼 "공격하고 있다 · 쏘고 있다" 가 멀리서도 분명하게) —— War3D 가 하나 가진다.
##  ① 공격 화살표: 친 부대 → 맞은 부대로 땅에 진영색 화살표 (근접 굵고 짧게 · 원거리 가늘게). 친 뒤 ATTACK_HOLD 초 동안 남는다.
##  ② 근접 베기: 맞은 부대 앞에 카메라를 향한 큰 초승달 궤적 + 충격 별.
##  ③ 사격 · 책략 궤적: 쏜 부대에서 맞은 부대로 포물선 띠가 흘러간다 (화살 노랑, 책략은 상태색).
## 부대마다 지금 하는 일(act_kind · act_t)은 Squad 에 적어 두고 이름표(BattleView)도 읽는다.

const ATTACK_HOLD := 1.6         # 공격 화살표가 남는 시간 (전장 초)
const TRACE_SEG := 16

var w: War3D
var _arrow_tex: Texture2D
var _slash_tex: Texture2D
var _star_tex: Texture2D
var _glow_tex: Texture2D
var _flip := {}                  # 부대 key -> 다음 베기를 반대로 (X 자)
var _marks := {}                 # 부대 key -> Decal (공격 화살표)
var _sprites := []               # [{n: Sprite3D, t0, life, s0, s1, spin}]
var _traces := []                # [{p0, p1, h, t0, dur, col, w}]
var _ribbon: MeshInstance3D
var _im: ImmediateMesh


func _init(owner_: War3D) -> void:
	w = owner_
	_arrow_tex = _make_arrow()
	_slash_tex = _make_slash()
	_star_tex = _make_star()
	_glow_tex = _make_glow()
	_im = ImmediateMesh.new()
	_ribbon = MeshInstance3D.new()
	_ribbon.mesh = _im
	_ribbon.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.vertex_color_use_as_albedo = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.no_depth_test = false
	_ribbon.material_override = m
	_ribbon.extra_cull_margin = 16384
	add_child(_ribbon)


func clear() -> void:
	for k in _marks:
		if is_instance_valid(_marks[k]):
			_marks[k].queue_free()
	_marks.clear()
	for s in _sprites:
		if is_instance_valid(s.n):
			s.n.queue_free()
	_sprites.clear()
	_traces.clear()


## 부대가 쳤다 —— kind: melee · shoot · cast
func acted(a: Squad, d: Squad, kind: String) -> void:
	if a == null or d == null:
		return
	a.act_kind = kind
	a.act_t = w.clock
	a.act_tgt = d


## 근접 베기 —— 맞은 부대의 친 쪽 가장자리에 초승달 + 별
const MAX_BIG := 3               # 한꺼번에 보이는 큰 효과(베기 · 궤적) 수 —— 넘치면 새 것은 건너뛴다

func _busy() -> bool:
	return _sprites.size() / 2 + _traces.size() >= MAX_BIG


func slash(a: Squad, d: Squad) -> void:
	acted(a, d, "melee")
	if _busy() or w.overview:
		return                   # 멀리 볼 때는 초승달 대신 발밑 판 번쩍임
	var dir := (a.pos - d.pos).normalized()
	var at := d.pos + dir * d.depth() * 0.5 + Vector2(-dir.y, dir.x) * w.rng.randf_range(-25, 25)
	var p := w.p3(at, 1.6)
	# 10/31 사용자: 잘 안 보인다 → 카메라 거리만큼 키워 화면에서 늘 크게 · 어두운 테두리 위에 밝은 궤적 · 휘두르듯 돌며 0.55초 · 번갈아 X 자로
	var k := clampf(w.cam.global_position.distance_to(p) / 28.0, 0.9, 3.2)     # 10/31 사용자: 너무 진하다 → 작게 · 한 겹 · 옅게
	var flip: bool = _flip.get(a.key, false)
	_flip[a.key] = not flip
	var r := w.rng.randf_range(-0.35, 0.35) + (PI * 0.5 if flip else 0.0) + (0.0 if a.camp == "A" else PI)
	var sweep := -1.1 if flip else 1.1
	_sprite(_slash_tex, p, Color(1.0, 0.95, 0.85, 0.55), 0.4, 2.0 * k, 3.2 * k, r - sweep, r + sweep * 0.3, 11)
	_sprite(_star_tex, p, Color(1.0, 0.92, 0.6, 0.6), 0.22, 1.0 * k, 2.0 * k, w.rng.randf() * TAU, w.rng.randf() * TAU, 12)


## 사격 —— 포물선 띠 (궁병 화살만. 책략은 띠 없이 구슬만 —— 10/31 사용자)
func trace(a: Squad, d: Squad, kind: String, col: Color) -> void:
	acted(a, d, kind)
	if _busy():
		return
	var p0 := w.p3(a.pos, 1.8)
	var p1 := w.p3(d.pos + Vector2(w.rng.randf_range(-15, 15), w.rng.randf_range(-12, 12)), 0.8)
	var dist := p0.distance_to(p1)
	_traces.append({"p0": p0, "p1": p1, "h": 2.0 + dist * 0.22, "t0": w.clock,
		"dur": 0.5 + dist / 70.0, "col": Color(col, 0.45), "w": 0.14})        # 10/31 가늘고 옅게


func _sprite(tex: Texture2D, p: Vector3, col: Color, life: float, s0: float, s1: float, r0: float, r1: float, prio := 10) -> void:
	var s := Sprite3D.new()
	s.texture = tex
	s.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	s.shaded = false
	s.no_depth_test = true
	s.render_priority = prio
	s.modulate = col
	s.pixel_size = 0.01
	s.position = p
	s.rotation.z = r0
	s.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	s.alpha_cut = SpriteBase3D.ALPHA_CUT_DISABLED
	add_child(s)
	_sprites.append({"n": s, "t0": w.clock, "life": life, "s0": s0, "s1": s1, "r0": r0, "r1": r1, "a": col.a})


## 매 프레임 —— 화살표 · 베기 · 궤적
func step() -> void:
	var clock := w.clock
	# ① 공격 화살표
	for sq: Squad in w.order:
		# 11/4 연출 점검: 원거리 · 책략 화살표가 5일차엔 8~10줄로 전장을 갈랐다 —— 땅 화살표는 근접만 (사격은 화살 · 구슬이 알린다)
		var on: bool = sq.alive and sq.state != "flee" and sq.act_tgt != null and sq.act_tgt.alive and clock - sq.act_t < ATTACK_HOLD and sq.act_kind == "melee"
		var d: Decal = _marks.get(sq.key)
		if not on:
			if d:
				d.visible = false
			continue
		if d == null:
			d = Decal.new()
			d.texture_albedo = _arrow_tex
			d.upper_fade = 0.3
			d.lower_fade = 0.3
			d.cull_mask = 1
			add_child(d)
			_marks[sq.key] = d
		var t: Squad = sq.act_tgt
		var v := t.pos - sq.pos
		var ln := v.length()
		var melee: bool = sq.act_kind == "melee"
		var start := 14.0 if melee else 30.0
		# 11/4 연출 점검: 멀리 있는 상대로 달려갈 때 긴 쐐기가 전장을 갈랐다 —— 짧은 토막(최대 70px)으로 방향만
		var stop := minf(maxf(start + 10.0, ln - t.depth() * 0.4 - 6.0), start + 70.0)
		var a := sq.pos + v / maxf(ln, 0.01) * start
		var b := sq.pos + v / maxf(ln, 0.01) * stop
		var mid := (a + b) * 0.5
		d.visible = true
		d.position = w.p3(mid)
		d.size = Vector3(a.distance_to(b) * War3D.S, 20.0, (34.0 if melee else 18.0) * War3D.S)
		d.rotation = Vector3(0, -v.angle(), 0)
		var u := (clock - sq.act_t) / ATTACK_HOLD
		var team: Color = War3D.TEAM[sq.camp].lightened(0.35)
		var col := team.lerp(Color(1.0, 0.55, 0.25), 0.55) if melee else team
		d.modulate = Color(col, (1.0 - u * u) * (0.6 if melee else 0.7))      # 11/4 0.95 → 0.6 옅게
	# ② 베기 · 별
	var keep := []
	for s in _sprites:
		var u: float = (clock - s.t0) / s.life
		if u >= 1.0 or not is_instance_valid(s.n):
			if is_instance_valid(s.n):
				s.n.queue_free()
			continue
		var k := lerpf(s.s0, s.s1, ease(u, 0.4))
		s.n.scale = Vector3.ONE * k
		s.n.rotation.z = lerpf(s.r0, s.r1, ease(u, 0.3))
		s.n.modulate.a = s.a * (1.0 - u * u * u)
		keep.append(s)
	_sprites = keep
	# ③ 궤적 —— 머리(지금 자리)에서 꼬리로 옅어지는 띠
	_im.clear_surfaces()
	var live := []
	for t in _traces:
		var u: float = (clock - t.t0) / t.dur
		if u >= 1.25:
			continue
		live.append(t)
	_traces = live
	if live.is_empty():
		return
	if not live.any(func(t): return clampf((clock - t.t0) / t.dur, 0.0, 1.0) - clampf((clock - t.t0) / t.dur - 0.25, 0.0, 1.0) >= 0.01):
		return              # 그릴 궤적이 없으면 빈 면을 만들지 않는다
	var cam := w.cam
	_im.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for t in live:
		var head: float = clampf((clock - t.t0) / t.dur, 0.0, 1.0)
		var tail: float = clampf(head - 0.25, 0.0, 1.0)
		var fade: float = 1.0 - clampf(((clock - t.t0) / t.dur - 1.0) / 0.25, 0.0, 1.0)
		if head - tail < 0.01:
			continue
		var prev_l := Vector3.ZERO
		var prev_r := Vector3.ZERO
		var prev_c := Color()
		for i in TRACE_SEG + 1:
			var f := lerpf(tail, head, float(i) / TRACE_SEG)
			var p := _arc(t, f)
			var q := _arc(t, minf(1.0, f + 0.02))
			var side: Vector3 = (q - p).cross(cam.global_position - p).normalized() * float(t.w) * (0.35 + 0.65 * float(i) / TRACE_SEG)
			var c := Color(t.col, t.col.a * fade * float(i) / TRACE_SEG)
			var l: Vector3 = p - side
			var r: Vector3 = p + side
			if i > 0:
				_im.surface_set_color(prev_c); _im.surface_add_vertex(prev_l)
				_im.surface_set_color(prev_c); _im.surface_add_vertex(prev_r)
				_im.surface_set_color(c); _im.surface_add_vertex(r)
				_im.surface_set_color(prev_c); _im.surface_add_vertex(prev_l)
				_im.surface_set_color(c); _im.surface_add_vertex(r)
				_im.surface_set_color(c); _im.surface_add_vertex(l)
			prev_l = l
			prev_r = r
			prev_c = c
	_im.surface_end()


func _arc(t: Dictionary, u: float) -> Vector3:
	var p: Vector3 = t.p0.lerp(t.p1, u)
	p.y += sin(u * PI) * t.h
	return p


# ───────── 그림 (코드로 그린다) ─────────

## 땅 화살표 —— 오른쪽(+x)을 가리킨다. 몸통은 가운데가 밝고 가장자리가 옅다
func _make_arrow() -> Texture2D:
	var img := Image.create(256, 64, false, Image.FORMAT_RGBA8)
	for y in 64:
		for x in 256:
			var cy := absf(y - 31.5) / 32.0
			var a := 0.0
			if x < 196:
				a = clampf((0.42 - cy) / 0.12, 0, 1) * clampf(x / 40.0, 0, 1) * (0.55 + 0.45 * x / 196.0)
			else:
				var lim := (256.0 - x) / 60.0
				a = clampf((lim - cy) / 0.08, 0, 1)
			img.set_pixel(x, y, Color(1, 1, 1, a))
	return ImageTexture.create_from_image(img)


## 초승달 베기 궤적 —— 큰 원에서 오른쪽으로 비킨 작은 원을 뺀 모양 (왼쪽이 두껍고 위아래 끝이 뾰족). 또렷한 테 + 둘레 빛
func _make_slash() -> Texture2D:
	var n := 128
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	for y in n:
		for x in n:
			var p := Vector2(x - n / 2.0, y - n / 2.0) / (n / 2.0)
			var d_out := p.length() - 0.9                       # 큰 원 안이면 음수
			var d_in := 0.8 - (p - Vector2(0.26, 0.0)).length()  # 작은 원 밖이면 음수
			var d := maxf(d_out, d_in)                           # 초승달 안이면 음수
			var core := clampf(-d / 0.025, 0, 1)
			var halo := clampf(1.0 - d / 0.09, 0, 1) * 0.35 if d > 0 and d_in > -0.05 else 0.0
			img.set_pixel(x, y, Color(1, 1, 1, maxf(core, halo)))
	return ImageTexture.create_from_image(img)


## 둥근 빛
func _make_glow() -> Texture2D:
	var n := 64
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	for y in n:
		for x in n:
			var r := Vector2(x - n / 2.0, y - n / 2.0).length() / (n / 2.0)
			img.set_pixel(x, y, Color(1, 1, 1, pow(clampf(1.0 - r, 0, 1), 1.6)))
	return ImageTexture.create_from_image(img)


## 충격 별 (네 갈래)
func _make_star() -> Texture2D:
	var n := 64
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	for y in n:
		for x in n:
			var p := Vector2(x - n / 2.0, y - n / 2.0) / (n / 2.0)
			var a := maxf(clampf(1.0 - absf(p.x) * 7.0, 0, 1) * clampf(1.0 - absf(p.y), 0, 1), clampf(1.0 - absf(p.y) * 7.0, 0, 1) * clampf(1.0 - absf(p.x), 0, 1))
			a = maxf(a, clampf(1.0 - p.length() * 2.2, 0, 1))
			img.set_pixel(x, y, Color(1, 1, 1, a))
	return ImageTexture.create_from_image(img)
