class_name UltFx
extends RefCounted
## 고유기 대형 이펙트 —— War3D 위에 얹는다. 모든 시간은 전장 시계(clock) 기준이라
## 슬로모션·일시정지에 맞춰 함께 느려진다.
##   slash 초승달 검기 · charge 금빛 궤적+충격파 · arrowstorm 화살비 · firestorm 불기둥+그을음
##   thunder 낙뢰 · poison 독안개 · illusion 보랏빛 소용돌이 · aura/heal 빛기둥
##   shadow 검은 연기 · whirlwind 회전 충격파 · roar 겹겹 충격파+화면 흔들림
## 모든 고유기 공통: 장수 발밑에 도는 법진 → 터지는 순간 화면 섬광 · 큰 충격파 고리 · 맞은 부대 병사가 공중으로 날아간다
##   (날리는 세기는 LAUNCH —— 물리 계열일수록 세다)
const MAGIC := ["thunder", "poison", "illusion", "aura", "heal", "firestorm"]      # 술법 계열 —— 법진 · 빛기둥 · 섬광
const LAUNCH := {"slash": 0.95, "charge": 1.0, "whirlwind": 0.9, "roar": 0.7, "thunder": 0.75, "firestorm": 0.55,
	"shadow": 0.5, "illusion": 0.35, "poison": 0.25, "arrowstorm": 0.3}

var w: War3D
var timed := []           # [시각, Callable]
var live := []            # {n: Node3D, t0, life, kind, m: Material, ...}
var trails := {}          # 부대 key -> 끝나는 시각 (돌격 궤적)
var _scorch_tex: Texture2D
static var _circle_tex: Texture2D     # 한 번 그려 두고 전투마다 다시 쓴다


func _init(war: War3D) -> void:
	w = war
	var g := GradientTexture2D.new()
	g.width = 128
	g.height = 128
	g.fill = GradientTexture2D.FILL_RADIAL
	g.fill_from = Vector2(0.5, 0.5)
	g.fill_to = Vector2(1.0, 0.5)
	var gr := Gradient.new()
	gr.colors = PackedColorArray([Color(0.05, 0.03, 0.02, 0.9), Color(0.08, 0.05, 0.03, 0.55), Color(0, 0, 0, 0)])
	gr.offsets = PackedFloat32Array([0, 0.55, 1])
	g.gradient = gr
	_scorch_tex = g
	if _circle_tex == null:
		_circle_tex = _magic_circle()


func clear() -> void:
	timed.clear()
	live.clear()
	trails.clear()


func at(delay: float, f: Callable) -> void:
	timed.append([w.clock + delay, f])


## 발동 —— 컷인과 함께 기를 모으고, delay 뒤에 터진다
func play(vfx: String, akey: String, foes: Array, allies: Array, delay: float) -> void:
	var a: Squad = w.squads.get(akey)
	if a == null:
		return
	var col := _col(vfx)
	if w.flat != null and w.flat.has_method("fx_ult"):      # 11/6 타입2 —— 2D 연출 (병사 날리기는 그대로, 섬광은 술법만 옅게)
		w.flat.fx_ult_charge(a, col, MAGIC.has(vfx), foes)
		at(delay, func(): _impact_flat(vfx, akey, foes, allies, col))
		return
	var ap := w.p3(a.pos)
	# 기 모으기 —— 11/5 사용자 "고유기가 다 비슷하다": 법진 · 빛기둥은 술법 계열만. 무장 계열은 흙먼지 · 기합 고리
	if MAGIC.has(vfx):
		_circle(ap, col, 22.0, delay + 0.7)
		_pillar(ap, col, delay + 0.4, 0.6)
	else:
		w._particles(ap + Vector3(0, 0.3, 0), "dust", Color("#b8a07a"))
		_shock(ap, col, 9.0)
	match vfx:
		"charge", "whirlwind":
			trails[akey] = w.clock + delay + 2.5
	at(delay, func(): _impact(vfx, akey, foes, allies, col))


func _impact_flat(vfx: String, akey: String, foes: Array, allies: Array, col: Color) -> void:
	var a: Squad = w.squads.get(akey)
	if MAGIC.has(vfx):
		w.ult_flash.emit(col)
	var lp: float = LAUNCH.get(vfx, 0.0)
	for k in foes:
		var d: Squad = w.squads.get(k)
		if d != null and lp > 0.0:
			var c: Vector2 = d.pos + (a.pos - d.pos).normalized() * d.edge((a.pos - d.pos).normalized()) * 0.6 if a else d.pos
			w.launch(k, c, 55.0, lp)
	w.flat.fx_ult(vfx, a, foes, allies, col)


func _col(vfx: String) -> Color:
	return {"slash": Color("#ffe6a0"), "charge": Color("#ffd257"), "arrowstorm": Color("#f2e2b8"),
		"firestorm": Color("#ff7a2a"), "thunder": Color("#a8d8ff"), "poison": Color("#7fd06b"),
		"illusion": Color("#c08cff"), "aura": Color("#ffd76e"), "heal": Color("#8ff0c8"),
		"shadow": Color("#7a5cff"), "whirlwind": Color("#ffe0a0"), "roar": Color("#ffb070")}.get(vfx, Color.WHITE)


func _impact(vfx: String, akey: String, foes: Array, allies: Array, col: Color) -> void:
	var a: Squad = w.squads.get(akey)
	var ap := w.p3(a.pos) if a else Vector3.ZERO
	var fpos := []
	for k in foes:
		if w.squads.has(k):
			fpos.append(w.p3(w.squads[k].pos))
	var apos := []
	for k in allies:
		if w.squads.has(k):
			apos.append(w.p3(w.squads[k].pos))
	# 공통은 병사 날리기만. 섬광은 술법 계열, 큰 충격파는 무장 돌진 계열(charge · roar · whirlwind), 흔들림 세기도 종류마다
	w.shake = maxf(w.shake, {"roar": 1.0, "charge": 0.9, "thunder": 0.8, "whirlwind": 0.7, "slash": 0.6}.get(vfx, 0.4))
	if MAGIC.has(vfx):
		w.ult_flash.emit(col)
	var lp: float = LAUNCH.get(vfx, 0.0)
	for k in foes:
		var d: Squad = w.squads.get(k)
		if d == null:
			continue
		var dp := w.p3(d.pos)
		if vfx in ["charge", "roar", "whirlwind"]:
			_shock(dp, col, 16.0)
		if lp > 0.0:
			var c: Vector2 = d.pos + (a.pos - d.pos).normalized() * d.edge((a.pos - d.pos).normalized()) * 0.6 if a else d.pos
			w.launch(k, c, 55.0, lp)
	match vfx:
		"slash":      # 검기 셋이 엇갈려 지나간다
			for p in fpos:
				_crescent(p + Vector3(0, 1.3, 0), (p - ap).normalized(), col)
				var pp: Vector3 = p
				at(0.1, func(): _crescent(pp + Vector3(0, 1.8, 0), (pp - ap).normalized().rotated(Vector3.UP, 0.5), col.lightened(0.3)))
				at(0.2, func(): _crescent(pp + Vector3(0, 0.9, 0), (pp - ap).normalized().rotated(Vector3.UP, -0.6), col))
				_cut(p, (p - ap).normalized())
				w._particles(p + Vector3(0, 1, 0), "spark", col)
				w._ring(p + Vector3(0, 0.2, 0), col, 0.6)
				w._light(p + Vector3(0, 2, 0), col, 6.0, 0.35)
		"charge":     # 장수에서 적까지 흙먼지 길이 깔린다
			for p in fpos:
				for i in 6:
					var q: Vector3 = ap.lerp(p, (i + 1) / 7.0)
					at(i * 0.04, func(): w._particles(q + Vector3(0, 0.3, 0), "dust", Color("#b8a07a")))
				w._ring(p + Vector3(0, 0.2, 0), col, 0.8)
				w._particles(p + Vector3(0, 0.3, 0), "dust", Color("#b8a07a"))
				w._particles(p + Vector3(0, 1, 0), "spark", col)
				w._light(p + Vector3(0, 2, 0), col, 5.0, 0.4)
			for k in foes:
				if w.squads.has(k):
					w.squads[k].stagger(w.clock, w.rng)
		"arrowstorm":
			for k in foes:
				var d: Squad = w.squads.get(k)
				if d == null:
					continue
				for i in 120:
					var tp := d.pos + Vector2(w.rng.randf_range(-45, 45), w.rng.randf_range(-45, 45))
					var p1 := w.p3(tp, 0.1)
					var p0 := ap + Vector3(w.rng.randf_range(-6, 6), 2.0, w.rng.randf_range(-6, 6))
					w.arrows.append({"p0": p0, "p1": p1, "t0": w.clock - 0.35 + w.rng.randf() * 0.5, "dur": 0.9,
						"h": 14.0 + w.rng.randf() * 6.0, "puff": i % 9 == 0})
		"firestorm":
			for p in fpos:
				for i in 3:
					var o := Vector3(w.rng.randf_range(-3, 3), 0, w.rng.randf_range(-3, 3))
					w._particles(p + o, "fire", Color("#ff7a2a"))
				w._particles(p + Vector3(0, 2.5, 0), "smoke", Color("#2e2925"))
				w._particles(p + Vector3(0, 1, 0), "ember", Color("#ffb04a"))
				_pillar(p, Color("#ff6a20"), 0.9, 1.0)
				_scorch(p)
			for k in foes:      # 땅에 붙은 불 —— 맞은 부대 자리마다 셋, 6초
				var d: Squad = w.squads.get(k)
				if d == null:
					continue
				for i in 3:
					w.fire_patch(d.pos + Vector2(w.rng.randf_range(-35, 35), w.rng.randf_range(-25, 25)), 6.0, 1.1)
		"thunder":
			for p in fpos:
				_circle(p, col, 18.0, 0.9)
				for i in 8:      # 낙뢰가 연달아 (첫 줄기만 점광)
					at(i * 0.11, func(): _bolt(p + Vector3(w.rng.randf_range(-4, 4), 0, w.rng.randf_range(-4, 4)), col, i > 0))
		"poison":     # 독안개가 3초 동안 피어오른다
			for p in fpos:
				_circle(p, col, 18.0, 1.4)
				for i in 6:
					var pp: Vector3 = p + Vector3(w.rng.randf_range(-4, 4), 0.5, w.rng.randf_range(-4, 4))
					at(i * 0.5, func(): w._particles(pp, "mist", col))
		"illusion":   # 소용돌이 · 적이 휘청이며 엉킨다
			for p in fpos:
				_spiral(p, col)
				_circle(p, col, 20.0, 1.2)
				w._particles(p + Vector3(0, 1.5, 0), "haze", col)
			for k in foes:
				if w.squads.has(k):
					w.squads[k].stagger(w.clock, w.rng)
		"aura", "heal":
			for p in apos:
				_circle(p, col, 16.0, 1.4)
				_pillar(p, col, 1.3, 1.0)
				w._particles(p + Vector3(0, 0.8, 0), "heal", col)
				w._ring(p + Vector3(0, 0.2, 0), col, 0.9)
			for p in fpos:
				w._particles(p + Vector3(0, 1, 0), "spark", col)
		"shadow":     # 장수가 연기로 사라지고, 적마다 차례로 검은 검기가 번뜩인다
			if a:
				w._particles(ap + Vector3(0, 1, 0), "smoke", Color("#1a1424"))
			for i in fpos.size():
				var p: Vector3 = fpos[i]
				at(i * 0.14, func():
					w._particles(p + Vector3(0, 1, 0), "smoke", Color("#1a1424"))
					_crescent(p + Vector3(0, 1.1, 0), (p - ap).normalized(), col)
					_crescent(p + Vector3(0, 1.4, 0), (p - ap).normalized().rotated(Vector3.UP, 1.4), col))
		"whirlwind":
			for i in 3:
				at(i * 0.12, func(): w._ring(ap + Vector3(0, 0.3 + i * 0.4, 0), col, 0.7))
			for p in fpos:
				_crescent(p + Vector3(0, 1.2, 0), (p - ap).normalized(), col)
				w._particles(p + Vector3(0, 1, 0), "spark", col)
		"roar":
			for i in 4:
				at(i * 0.15, func(): _shock(ap, col, 26.0))
			w.shake = 1.0
			for p in fpos:
				w._particles(p + Vector3(0, 0.3, 0), "dust", Color("#b8a07a"))


# ───────── 부품 ─────────

func _add_mat(col: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.vertex_color_use_as_albedo = true
	m.albedo_color = col
	return m


func _spawn(mesh: Mesh, col: Color, pos: Vector3, life: float, kind: String, extra := {}) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	var m := _add_mat(col)
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	w.fx_root.add_child(mi)
	mi.position = pos
	var rec := {"n": mi, "t0": w.clock, "life": life, "kind": kind, "m": m, "col": col}
	rec.merge(extra)
	live.append(rec)
	return mi


## 초승달 검기 —— 수평 띠 모양 원호. 바깥은 진하고 안쪽은 투명하다
func _crescent(p: Vector3, dir: Vector3, col: Color) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var seg := 18
	for i in seg:
		var a0 := lerpf(-1.2, 1.2, float(i) / seg)
		var a1 := lerpf(-1.2, 1.2, float(i + 1) / seg)
		var fade0 := sin(PI * float(i) / seg)
		var fade1 := sin(PI * float(i + 1) / seg)
		var r0 := 7.4
		var r1 := 5.6
		var o0 := Vector3(cos(a0), 0, sin(a0))
		var o1 := Vector3(cos(a1), 0, sin(a1))
		var ca := Color(1, 1, 1, fade0)
		var cb := Color(1, 1, 1, fade1)
		var ci := Color(1, 1, 1, 0)
		for v in [[o0 * r0, ca], [o1 * r0, cb], [o1 * r1, ci], [o0 * r0, ca], [o1 * r1, ci], [o0 * r1, ci]]:
			st.set_color(v[1])
			st.add_vertex(v[0])
	var mi := _spawn(st.commit(), col, p, 0.6, "crescent", {"yaw": atan2(-dir.z, dir.x) + PI})
	mi.rotation = Vector3(0.25, atan2(-dir.z, dir.x) + PI, 0)


func _pillar(p: Vector3, col: Color, life: float, radius: float) -> void:
	var cm := CylinderMesh.new()
	cm.top_radius = radius * 0.5
	cm.bottom_radius = radius * 1.6
	cm.height = 18
	cm.radial_segments = 16
	cm.cap_top = false
	cm.cap_bottom = false
	var mi := _spawn(cm, Color(col, 0.45), p + Vector3(0, 9, 0), life, "pillar")
	mi.scale = Vector3(1, 0.01, 1)


func _shock(p: Vector3, col: Color, r: float) -> void:
	var tm := TorusMesh.new()
	tm.inner_radius = 0.92
	tm.outer_radius = 1.0
	tm.rings = 40
	tm.ring_segments = 4
	var mi := _spawn(tm, col, p + Vector3(0, 0.4, 0), 0.6, "shock", {"r": r})
	mi.scale = Vector3(0.1, 0.4, 0.1)


func _spiral(p: Vector3, col: Color) -> void:
	for i in 3:
		var tm := TorusMesh.new()
		tm.inner_radius = 2.2 + i * 0.9
		tm.outer_radius = 2.45 + i * 0.9
		tm.rings = 32
		tm.ring_segments = 4
		var mi := _spawn(tm, col, p + Vector3(0, 0.4 + i * 0.9, 0), 1.1, "spiral", {"spin": 3.0 - i})
		mi.scale = Vector3(1, 0.15, 1)


## 낙뢰 —— 하늘에서 지그재그로 꺾여 내려오는 줄기. 섬광과 불꽃을 함께 터뜨린다
func _bolt(p: Vector3, col: Color, lite := false) -> void:
	var k := MeshKit.new()
	var pts := []
	var top := p + Vector3(w.rng.randf_range(-4, 4), 42, w.rng.randf_range(-4, 4))
	for i in 10:
		var u := i / 9.0
		var q := top.lerp(p, u)
		if i > 0 and i < 9:
			q += Vector3(w.rng.randf_range(-1.6, 1.6), 0, w.rng.randf_range(-1.6, 1.6))
		pts.append(q)
	for i in 9:
		k.cyl(pts[i], pts[i + 1], 0.09, Color(1, 1, 1, 1), 4)
		k.cyl(pts[i], pts[i + 1], 0.4, Color(1, 1, 1, 0.25), 5)
	var mi := _spawn(k.mesh(), col.lightened(0.4), Vector3.ZERO, 0.28, "bolt")
	mi.position = Vector3.ZERO
	if not lite:      # 잔기술 낙뢰(lite)는 점광 · 고리 없이, 흔들림도 작게 (11/5 번쩍거림)
		w._light(p + Vector3(0, 4, 0), col, 16.0, 0.3)
		w._ring(p + Vector3(0, 0.2, 0), col, 0.5)
	w._particles(p + Vector3(0, 0.5, 0), "spark", col.lightened(0.5))
	w.shake = maxf(w.shake, 0.15 if lite else 0.4)


func _scorch(p: Vector3) -> void:
	var d := Decal.new()
	d.texture_albedo = _scorch_tex
	d.size = Vector3(11, 6, 11)
	d.position = p
	d.modulate = Color(1, 1, 1, 0.85)
	w.fx_root.add_child(d)


## 법진 —— 땅에 비추는 빛 무늬. 커지며 돌다가 사라진다
func _circle(p: Vector3, col: Color, size: float, life: float) -> void:
	var d := Decal.new()
	d.texture_albedo = _circle_tex
	d.texture_emission = _circle_tex
	d.emission_energy = 2.5
	d.modulate = col.lightened(0.2)
	d.size = Vector3(size, 8.0, size)
	d.cull_mask = 1
	d.position = p
	w.fx_root.add_child(d)
	live.append({"n": d, "t0": w.clock, "life": life, "kind": "circle", "m": null, "col": col, "size": size})


## 땅에 남는 검흔 —— 길쭉한 그을음
func _cut(p: Vector3, dir: Vector3) -> void:
	var d := Decal.new()
	d.texture_albedo = _scorch_tex
	d.size = Vector3(16, 6, 2.2)
	d.position = p
	d.rotation.y = atan2(-dir.z, dir.x) + PI * 0.5
	d.modulate = Color(1, 1, 1, 0.8)
	d.cull_mask = 1
	w.fx_root.add_child(d)


## 법진 무늬 —— 겹 원 · 눈금 · 육각별을 한 번 그려 둔다 (흰색, 알파로 모양)
static func _magic_circle() -> Texture2D:
	var n := 128
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var c := n / 2.0
	var star := []
	for i in 6:
		star.append(Vector2.from_angle(TAU * i / 6.0 - PI / 2) * 0.62)
	for y in n:
		for x in n:
			var p := Vector2((x - c) / c, (y - c) / c)
			var r := p.length()
			var a := 0.0
			# 겹 원
			for rr in [0.96, 0.86, 0.62, 0.3]:
				a = maxf(a, 1.0 - absf(r - rr) / 0.025)
			# 바깥 띠의 눈금
			if r > 0.86 and r < 0.96:
				var ang := atan2(p.y, p.x)
				a = maxf(a, 0.75 * float(fposmod(ang * 24.0 / PI, 2.0) < 0.35))
			# 육각별 —— 두 개의 삼각형
			for t in 2:
				for i in 3:
					var a0: Vector2 = star[(i * 2 + t) % 6]
					var a1: Vector2 = star[((i + 1) * 2 + t) % 6]
					var e := a1 - a0
					var u := clampf((p - a0).dot(e) / e.length_squared(), 0, 1)
					var dd := (p - (a0 + e * u)).length()
					a = maxf(a, 1.0 - dd / 0.022)
			# 가운데 은은한 빛
			a = maxf(a, 0.25 * (1.0 - smoothstep(0.0, 0.3, r)))
			if r > 1.0:
				a = 0.0
			a = clampf(a, 0, 1)
			img.set_pixel(x, y, Color(a, a, a, a))       # 발광은 알파를 보지 않는다 —— 색에도 미리 곱해 둔다
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


func step() -> void:
	# 예약된 순간
	var keep := []
	for t in timed:
		if w.clock >= t[0]:
			t[1].call()
		else:
			keep.append(t)
	timed = keep
	# 돌격 궤적 —— 달리는 부대 뒤로 금빛 먼지를 흘린다
	for k in trails.keys():
		var sq: Squad = w.squads.get(k)
		if sq == null or w.clock > trails[k]:
			trails.erase(k)
			continue
		if sq.moving and w.rng.randf() < 0.5:
			w._particles(w.p3(sq.pos - sq.fwd * 10, 0.4), "trail", Color("#ffd257"))
	# 살아 있는 부품
	var lk := []
	for r in live:
		var u: float = (w.clock - r.t0) / r.life
		if u >= 1.0:
			r.n.queue_free()
			continue
		lk.append(r)
		var m: StandardMaterial3D = r.m
		match r.kind:
			"crescent":
				r.n.rotation.y = r.yaw + lerpf(-0.9, 0.9, ease(u, 0.5))
				r.n.scale = Vector3.ONE * lerpf(0.7, 1.3, u)
				m.albedo_color = Color(r.col, 1.0 - u * u)
			"pillar":
				var g := minf(1.0, u * 4.0)
				r.n.scale = Vector3(1.0 - u * 0.4, g, 1.0 - u * 0.4)
				m.albedo_color = Color(r.col, r.col.a * (1.0 - u))
			"shock":
				var s: float = lerpf(0.1, r.r, ease(u, 0.4))
				r.n.scale = Vector3(s, 0.4, s)
				m.albedo_color = Color(r.col, 1.0 - u)
			"spiral":
				r.n.rotation.y += r.spin * 0.016
				m.albedo_color = Color(r.col, 1.0 - u)
			"circle":
				var dc: Decal = r.n
				var g := ease(minf(1.0, u * 3.0), 0.4)
				dc.size = Vector3(r.size * (0.4 + 0.6 * g), 8.0, r.size * (0.4 + 0.6 * g))
				dc.rotation.y += 0.02
				dc.modulate.a = 1.0 - smoothstep(0.7, 1.0, u)
			"bolt":
				m.albedo_color = Color(r.col, (1.0 - u) * (0.6 + 0.4 * sin(w.clock * 90.0)))
	live = lk
