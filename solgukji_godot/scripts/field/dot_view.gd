class_name DotView
extends Control
## 점묘 전장 (10/31 사용자: 모델링을 쓰지 않는 방향 —— 블라인드삼국 전투처럼) —— 3D 대신 위에서 내려다본 2D 로,
## 병사 한 명 = 점 하나. 부대마다 진영 안에서 색을 조금씩 달리하고(아군 파랑~보라, 적 빨강~노랑), 맞닿은 전선에 흰 불꽃이 튄다.
## 장수는 둥근 초상 토큰 + 병력 숫자. 병사 위치 · 움직임 · 판정은 War3D/Squad 가 하던 그대로 쓰고 그리기만 바꾼다
## (War3D.flat 이 이것을 가리키면 to_screen 이 이 화면 좌표를 돌려줘 이름표 · 피해 숫자도 따라온다).

const DOT := 5.0               # 점 크기 (px, 화면)
const SPREAD := 2.3            # 점묘에서는 부대 안 병사 사이를 이만큼 넓혀 그린다 (큰 점 무리로 —— 블라인드삼국)
const SPARK := 3.0
const MARGIN := 22.0           # 부대들을 담을 때 화면 가장자리 여유 (px)
const A_HUE := [0.58, 0.64, 0.70, 0.76, 0.54, 0.62, 0.68, 0.74, 0.60]     # 아군 —— 파랑 · 남색 · 보라 · 하늘
const B_HUE := [0.0, 0.04, 0.08, 0.12, 0.02, 0.06, 0.1, 0.14, 0.03]       # 적 —— 빨강 · 주황 · 노랑

var view                       # BattleView
var field: War3D
var _mm: MultiMeshInstance2D
var _scale := 1.0              # 전장 px → 화면 px
var _center := Vector2.ZERO    # 화면 가운데에 오는 전장 자리
var _want_scale := 1.0
var _want_center := Vector2.ZERO
var _col := {}                 # 부대 key -> 색
var _t := 0.0
var _areas := []               # [{shape, col, t0, life}] —— 기술 범위 · 고유기 예고 (전장 시각)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	_mm = MultiMeshInstance2D.new()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_2D
	mm.use_colors = true
	var q := QuadMesh.new()
	q.size = Vector2(1, 1)
	mm.mesh = q
	_mm.multimesh = mm
	_mm.texture = _dot_tex()
	add_child(_mm)


## 전투가 바뀌면 부대 색을 다시 매긴다
func setup() -> void:
	_col.clear()
	var ia := 0
	var ib := 0
	for sq: Squad in field.order:
		var h: float
		if sq.camp == "A":
			h = A_HUE[ia % A_HUE.size()]
			ia += 1
		else:
			h = B_HUE[ib % B_HUE.size()]
			ib += 1
		_col[sq.key] = Color.from_hsv(h, 0.62, 0.95)
	_fit(true)


## 전장 px → 화면 px. 위에서 내려다보며, 아군(A)은 아래 · 적(B)은 위 (전장 x 가 화면 위쪽)
func map(p: Vector2) -> Vector2:
	var d := p - _center
	return size * 0.5 + Vector2(d.y, -d.x) * _scale


## 살아 있는 부대를 모두 담게 크기 · 가운데를 맞춘다 (천천히 따라간다)
func _fit(now := false) -> void:
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for sq: Squad in field.order:
		if not sq.alive or sq.state == "gone":
			continue
		var r := maxf(sq.depth(), sq.cols * sq.sp) * 0.6 * SPREAD + 10.0
		lo = lo.min(sq.pos - Vector2(r, r))
		hi = hi.max(sq.pos + Vector2(r, r))
	if lo.x == INF:
		return
	var span := hi - lo
	# 화면 가로 = 전장 y, 세로 = 전장 x
	var s := minf((size.x - MARGIN * 2) / maxf(span.y, 1.0), (size.y - MARGIN * 2) / maxf(span.x, 1.0))
	_want_scale = clampf(s, 0.35, 3.0)
	_want_center = (lo + hi) * 0.5
	if now:
		_scale = _want_scale
		_center = _want_center


func _process(dt: float) -> void:
	if not visible or field == null:
		return
	_t += dt
	if Engine.get_process_frames() % 6 == 0:
		_fit()
	var k := 1.0 - exp(-dt * 1.2)
	_scale = lerpf(_scale, _want_scale, k)
	_center = _center.lerp(_want_center, k)
	if Engine.get_process_frames() % 2 == 0:
		_draw_dots()          # 점은 한 프레임 걸러 (2,000명 넘으면 스크립트가 무겁다)
	if not _areas.is_empty() or Engine.get_process_frames() % 10 == 0:
		queue_redraw()        # 범위가 있으면 매 프레임, 없으면 배경 격자만 가끔


func _draw_dots() -> void:
	var mm := _mm.multimesh
	var n := 0
	for sq: Squad in field.order:
		n += sq.soldiers.size()
	var sparks := 0
	for sq: Squad in field.order:
		if sq.alive and sq.contact and sq.engaged != null:
			sparks += 10
	var total := n + sparks
	if mm.instance_count < total:
		mm.instance_count = total + 64
	var i := 0
	var clock := field.clock
	for sq: Squad in field.order:
		var base: Color = _col.get(sq.key, Color.WHITE)
		var gone: bool = sq.state == "gone"
		for s in sq.soldiers:
			var c := base
			var sz := DOT
			if not s.alive:
				var dt: float = clock - s.die_t if s.die_t >= 0 else 99.0
				if s.die_t < 0 or dt > 1.6 or gone:
					mm.set_instance_transform_2d(i, Transform2D(0, Vector2.ZERO, 0, Vector2(-9999, -9999)))
					i += 1
					continue
				c = base.lerp(Color(1, 1, 1), 0.5 * clampf(1.0 - dt * 3.0, 0, 1))      # 쓰러지는 순간 번쩍
				c.a = clampf(1.0 - dt / 1.6, 0, 1) * 0.7
				sz = DOT * (1.0 + 0.5 * clampf(1.0 - dt * 2.0, 0, 1))
			elif sq.state == "flee":
				c.a = sq.fade
			if clock - s.hit_t < 0.25 and clock >= s.hit_t:
				c = c.lerp(Color(1, 1, 1), 0.6)
			# 부대 가운데에서 SPREAD 배로 벌리고, 병사마다 조금씩 흔들어 자연스러운 무리로
			var off: Vector2 = (s.pos - sq.pos) * SPREAD + s.jit * 2.5
			var p := map(sq.pos + off)
			if s.air > 0.0:
				p.y -= s.air * 6.0 * _scale        # 날아가는 병사는 위로
				sz *= 1.4
			mm.set_instance_transform_2d(i, Transform2D(0, Vector2(sz, sz), 0, p))
			mm.set_instance_color(i, c)
			i += 1
	# 전선 불꽃 —— 맞닿은 부대 사이에 흰 점이 튄다
	for sq: Squad in field.order:
		if not (sq.alive and sq.contact and sq.engaged != null):
			continue
		var e: Squad = sq.engaged
		var mid: Vector2 = e.pos + sq.axis * e.depth() * 0.5
		var perp := Vector2(-sq.axis.y, sq.axis.x)
		for j in 10:
			var ph := fposmod(_t * 3.0 + j * 0.37 + float(sq.row.slot) * 0.13, 1.0)
			var at: Vector2 = mid + perp * (fposmod(j * 37.3 + floor(_t * 3.0 + j * 0.37) * 11.0, 1.0) - 0.5) * sq.cols * sq.sp
			var sp := SPARK * (1.0 - ph)
			mm.set_instance_transform_2d(i, Transform2D(0, Vector2(sp, sp), 0, map(at) + Vector2(0, -ph * 6.0)))
			mm.set_instance_color(i, Color(1, 1, 0.92, 1.0 - ph))
			i += 1
	for j in range(i, mm.instance_count):
		mm.set_instance_transform_2d(j, Transform2D(0, Vector2.ZERO, 0, Vector2(-9999, -9999)))


func add_area(shape: Dictionary, col: Color, life: float) -> void:
	_areas.append({"shape": shape, "col": col, "t0": field.clock, "life": life})


## 범위 —— 원(안은 옅게, 테두리는 진하게 · 오래 남는 예고는 테두리가 안쪽으로 조여든다) · 띠
func _draw_areas() -> void:
	var keep := []
	for a in _areas:
		var u: float = (field.clock - a.t0) / a.life
		if u >= 1.0:
			continue
		keep.append(a)
		var al := minf(1.0, u * 6.0) * (1.0 if u < 0.8 else (1.0 - u) / 0.2)
		var sh: Dictionary = a.shape
		var col: Color = a.col
		if sh.k == "line":
			var p0 := map(Vector2(sh.x, sh.y))
			var p1 := map(Vector2(sh.x2, sh.y2))
			draw_line(p0, p1, Color(col, 0.18 * al), float(sh.w) * 2.0 * _scale * SPREAD * 0.5)
			continue
		var c := map(Vector2(sh.x, sh.y))
		var r: float = float(sh.r) * _scale * SPREAD * 0.6
		draw_circle(c, r, Color(col, 0.16 * al))
		draw_arc(c, r, 0, TAU, 40, Color(col, 0.85 * al), 2.5)
		if a.life > 1.5:
			draw_arc(c, r * (1.0 - u), 0, TAU, 40, Color(col, 0.6 * al), 2.0)       # 조여드는 고리 —— 터지는 때를 알린다
	_areas = keep


## 배경 —— 어두운 바탕에 옅은 격자
func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("#0b0f17"))
	var g := 40.0 * _scale
	if g < 8.0:
		g *= 4.0
	var o := map(Vector2.ZERO)
	var gc := Color(0.35, 0.42, 0.55, 0.07)
	var x := fposmod(o.x, g)
	while x < size.x:
		draw_line(Vector2(x, 0), Vector2(x, size.y), gc, 1.0)
		x += g
	var y := fposmod(o.y, g)
	while y < size.y:
		draw_line(Vector2(0, y), Vector2(size.x, y), gc, 1.0)
		y += g
	_draw_areas()


func _dot_tex() -> Texture2D:
	var n := 16
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	for y in n:
		for x in n:
			var d := Vector2(x - n / 2.0 + 0.5, y - n / 2.0 + 0.5).length() / (n / 2.0)
			img.set_pixel(x, y, Color(1, 1, 1, clampf((1.0 - d) * 2.2, 0, 1)))
	return ImageTexture.create_from_image(img)
