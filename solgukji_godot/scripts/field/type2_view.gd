class_name Type2View
extends DotView
## 타입2 전장 (11/3 사용자: 삼국지11 스타일 그래픽을 더 디벨롭 —— '타입2' 로 부른다).
## 삼국지11 전투 지도처럼: 비스듬히 내려다본 채색 지도판 + 옅은 육각 격자, 부대는 작은 병사 인형 무리(진영색) +
## 뒤에 큰 깃발(성씨 한 글자, 등급색 테두리) + 아래 이름판(이름 · 병력 막대). 상태는 발밑 육각 칸으로(수몰 파랑 · 화상 주황 · 파갑 금 간 방패).
## 판정 · 움직임은 그대로(Squad · RtBattle), 그리기만 바꾼다 —— DotView 를 물려받아 War3D.flat 자리에 들어간다
## (이름표 · 피해 숫자 · 기술 범위는 DotView 처럼 map() 을 따라온다).

const TILT := 0.62             # 세로 눌림 —— 비스듬히 내려다본 지도
const FIG := 15.0              # 병사 인형 크기 (px, 화면 —— 배율 1 기준)
const T2_SPREAD := 1.35        # 부대 안 병사 사이 (점묘보다 촘촘하게 —— 삼국지11 의 부대 덩어리)
const HEX := 34.0              # 육각 한 칸 (전장 px)
const TEAM_A := Color("#3f78c8")
const TEAM_B := Color("#c8483a")

var _bg: Texture2D
var _fig_tex: Texture2D


func _ready() -> void:
	super._ready()
	_fig_tex = _make_fig()
	_mm.texture = _fig_tex
	_bg = _make_bg()


func setup() -> void:
	super.setup()
	for sq: Squad in field.order:
		var base := TEAM_A if sq.camp == "A" else TEAM_B
		_col[sq.key] = base.lightened(0.06 * (sq.row.slot % 3)) if sq.tier < 6 else base.lerp(DB.TIER[sq.tier].c, 0.25)


## 전장 px → 화면 px —— DotView 처럼 아군 아래 · 적 위, 세로를 TILT 만큼 눌러 비스듬히
func map(p: Vector2) -> Vector2:
	var d := p - _center
	return size * 0.5 + Vector2(d.y, -d.x * TILT) * _scale


func _fit(now := false) -> void:
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for sq: Squad in field.order:
		if not sq.alive or sq.state == "gone":
			continue
		var r := maxf(sq.depth(), sq.cols * sq.sp) * 0.6 * T2_SPREAD + 26.0
		lo = lo.min(sq.pos - Vector2(r, r))
		hi = hi.max(sq.pos + Vector2(r, r))
	if lo.x == INF:
		return
	var span := hi - lo
	var s := minf((size.x - MARGIN * 2) / maxf(span.y, 1.0), (size.y - MARGIN * 2 - 60) / maxf(span.x * TILT, 1.0))
	_want_scale = clampf(s, 0.35, 3.0)
	_want_center = (lo + hi) * 0.5
	if now:
		_scale = _want_scale
		_center = _want_center


func _process(dt: float) -> void:
	super._process(dt)
	if visible and Engine.get_process_frames() % 2 == 1:
		queue_redraw()        # 깃발 · 이름판이 부대를 따라가야 한다


## 병사 인형 —— 진영색, 맞으면 흰빛, 쓰러지면 눕고 바랜다. 위에 있을수록(멀수록) 먼저 그려 겹침 순서를 맞춘다
func _draw_dots() -> void:
	var mm := _mm.multimesh
	var figs := []
	for sq: Squad in field.order:
		for s in sq.soldiers:
			figs.append([sq, s])
	var sparks := 0
	for sq: Squad in field.order:
		if sq.alive and sq.contact and sq.engaged != null:
			sparks += 8
	var total := figs.size() + sparks
	if mm.instance_count < total:
		mm.instance_count = total + 64
	var clock := field.clock
	var pts := []
	for f in figs:
		var sq: Squad = f[0]
		var s = f[1]
		var off: Vector2 = (s.pos - sq.pos) * T2_SPREAD + s.jit * 1.2
		pts.append([map(sq.pos + off), sq, s])
	pts.sort_custom(func(a, b): return a[0].y < b[0].y)
	var i := 0
	var sz := FIG * clampf(_scale * 1.15, 0.6, 1.8)
	for e in pts:
		var p: Vector2 = e[0]
		var sq: Squad = e[1]
		var s = e[2]
		var c: Color = _col.get(sq.key, Color.WHITE)
		var rot := 0.0
		var h: float = sz * (1.25 if s == sq.general else 1.0) * s.size
		if not s.alive:
			var dt: float = clock - s.die_t if s.die_t >= 0 else 99.0
			if s.die_t < 0 or dt > 2.0 or sq.state == "gone":
				mm.set_instance_transform_2d(i, Transform2D(0, Vector2.ZERO, 0, Vector2(-9999, -9999)))
				i += 1
				continue
			rot = s.fall * minf(1.0, dt / 0.35) * PI * 0.5
			c = c.darkened(0.45)
			c.a = clampf(1.0 - (dt - 1.2) / 0.8, 0, 1)
		elif sq.state == "flee":
			c.a = sq.fade
		if sq.armor_broken and s.alive:
			c = c.lerp(Color("#7a4a2a"), 0.35)      # 파갑 —— 갑옷이 녹슨 빛
		if clock - s.hit_t < 0.25 and clock >= s.hit_t:
			c = c.lerp(Color(1, 1, 1), 0.65)
		if s.air > 0.0:
			p.y -= s.air * 6.0 * _scale
			rot = s.spin
		# 걸음 —— 위아래로 살짝, 공격 —— 앞으로 기운다
		if s.alive:
			p.y -= absf(sin(s.walk * 0.9)) * 1.4
			var a: float = (clock - s.atk_t0) / Squad.ATTACK_TIME
			if a >= 0 and a <= 1:
				rot = (-0.35 if sq.camp == "A" else 0.35) * sin(PI * a)
		var flip := -1.0 if (sq.camp == "B") else 1.0
		mm.set_instance_transform_2d(i, Transform2D(rot, Vector2(h * flip, h), 0, p + Vector2(0, -h * 0.5)))
		mm.set_instance_color(i, c)
		i += 1
	# 전선 불꽃
	for sq: Squad in field.order:
		if not (sq.alive and sq.contact and sq.engaged != null):
			continue
		var en: Squad = sq.engaged
		var mid: Vector2 = en.pos + sq.axis * en.depth() * 0.5
		var perp := Vector2(-sq.axis.y, sq.axis.x)
		for j in 8:
			var ph := fposmod(_t * 3.0 + j * 0.41 + float(sq.row.slot) * 0.13, 1.0)
			var at: Vector2 = mid + perp * (fposmod(j * 37.3 + floor(_t * 3.0 + j * 0.41) * 11.0, 1.0) - 0.5) * sq.cols * sq.sp
			var sp := 5.0 * (1.0 - ph)
			mm.set_instance_transform_2d(i, Transform2D(ph * 3.0, Vector2(sp, sp), 0, map(at) + Vector2(0, -ph * 10.0 - 6.0)))
			mm.set_instance_color(i, Color(1, 0.95, 0.7, 1.0 - ph))
			i += 1
	for j in range(i, mm.instance_count):
		mm.set_instance_transform_2d(j, Transform2D(0, Vector2.ZERO, 0, Vector2(-9999, -9999)))


## 바탕 —— 채색 지도 + 육각 격자 + 상태 칸, 그리고 깃발 · 이름판 (병사 인형은 MultiMesh 가 위에 그린다 → 깃발은 따로 위 층)
func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("#5f7a4a"))
	if _bg:
		var ts := _bg.get_size() * 1.6 * maxf(_scale, 0.5)
		var o := map(Vector2.ZERO)
		var x0 := fposmod(o.x, ts.x) - ts.x
		var y0 := fposmod(o.y, ts.y) - ts.y
		var y := y0
		while y < size.y:
			var x := x0
			while x < size.x:
				draw_texture_rect(_bg, Rect2(Vector2(x, y), ts), false)
				x += ts.x
			y += ts.y
	_draw_hex()
	_draw_status_hex()
	_draw_areas()


## 육각 격자 —— 전장 좌표의 육각을 눌린 화면으로. 화면 안쪽만
func _draw_hex() -> void:
	var w := HEX * sqrt(3.0)
	var hc := Color(0.1, 0.12, 0.06, 0.13)
	var inv_c := _center
	var half := size * 0.5 / maxf(_scale, 0.01)
	var lo := inv_c - Vector2(half.y / TILT, half.x) - Vector2(HEX * 2, w)
	var hi := inv_c + Vector2(half.y / TILT, half.x) + Vector2(HEX * 2, w)
	var row := int(floor(lo.x / (HEX * 1.5)))
	while row * HEX * 1.5 < hi.x:
		var cx: float = row * HEX * 1.5
		var col := int(floor(lo.y / w))
		while col * w < hi.y:
			var cy: float = col * w + (w * 0.5 if row % 2 != 0 else 0.0)
			var pts := PackedVector2Array()
			for k in 7:
				var a := PI / 3.0 * k
				pts.append(map(Vector2(cx + cos(a) * HEX, cy + sin(a) * HEX)))
			draw_polyline(pts, hc, 1.0)
			col += 1
		row += 1


## 부대 발밑 상태 칸 —— 삼국지11 처럼 칸에 불 · 물을 칠한다
func _hex_at(p: Vector2, col: Color, fill_a: float) -> void:
	var pts := PackedVector2Array()
	for k in 6:
		var a := PI / 3.0 * k
		pts.append(map(p + Vector2(cos(a), sin(a)) * HEX * 1.4))
	draw_colored_polygon(pts, Color(col, fill_a))
	pts.append(pts[0])
	draw_polyline(pts, Color(col, minf(1.0, fill_a * 3.0)), 2.0)


func _draw_status_hex() -> void:
	for sq: Squad in field.order:
		if not sq.alive or sq.state == "gone":
			continue
		var c := sq.pos - sq.fwd * sq.depth() * 0.5
		if sq.statuses.has("burn"):
			_hex_at(c, Color("#ff7a2a"), 0.22 + 0.08 * sin(_t * 8.0 + sq.row.slot))
		if sq.statuses.has("flood"):
			_hex_at(c, Color("#3d8fe0"), 0.24 + 0.06 * sin(_t * 3.0))       # 이감 —— 물에 발이 묶였다
		if sq.statuses.has("confuse"):
			_hex_at(c, Color("#b57edc"), 0.18)


## 깃발 · 이름판 —— 병사 인형(MultiMesh) 위에 오도록 따로 그리는 층
class Overlay extends Control:
	var v: Type2View
	func _draw() -> void:
		if v == null or v.field == null:
			return
		var items := []
		for sq: Squad in v.field.order:
			if sq.alive and sq.state != "gone":
				items.append(sq)
		items.sort_custom(func(a, b): return v.map(a.pos).y < v.map(b.pos).y)
		for sq: Squad in items:
			_flag(sq)

	func _flag(sq: Squad) -> void:
		var back := sq.pos - sq.fwd * (sq.depth() * 0.5 * Type2View.T2_SPREAD + 8.0)
		var base := v.map(back)
		var s := clampf(v._scale * 1.1, 0.7, 1.6)
		var pole := 34.0 * s
		var top := base + Vector2(0, -pole)
		var col: Color = Type2View.TEAM_A if sq.camp == "A" else Type2View.TEAM_B
		var tc: Color = DB.TIER[sq.tier].c
		var fade: float = sq.fade if sq.state == "flee" else 1.0
		draw_line(base, top, Color(0.18, 0.12, 0.08, fade), 2.0)
		# 깃발 —— 바람에 살짝 흔들리는 사각, 등급색 테두리, 가운데 성씨 한 글자
		var fw := 20.0 * s
		var fh := 22.0 * s
		var dir := 1.0 if sq.camp == "A" else -1.0
		var wav := sin(v._t * 4.0 + sq.row.slot) * 2.0 * s
		var p0 := top
		var p1 := top + Vector2(fw * dir, wav)
		var p2 := top + Vector2(fw * dir, fh + wav)
		var p3 := top + Vector2(0, fh)
		draw_colored_polygon(PackedVector2Array([p0, p1, p2, p3]), Color(col.darkened(0.15), fade))
		draw_polyline(PackedVector2Array([p0, p1, p2, p3, p0]), Color(tc, fade), 2.0 if sq.tier >= 6 else 1.2)
		var nm: String = DB.person(sq.cid) if sq.tier > 2 else sq.tag
		var ch := nm.left(1)
		var fs := int(15 * s)
		var cpos := (p0 + p2) * 0.5
		draw_string_outline(DB.font_display, cpos + Vector2(-fs * 0.5, fs * 0.36), ch, HORIZONTAL_ALIGNMENT_CENTER, fs, fs, 3, Color(0, 0, 0, 0.6 * fade))
		draw_string(DB.font_display, cpos + Vector2(-fs * 0.5, fs * 0.36), ch, HORIZONTAL_ALIGNMENT_CENTER, fs, fs, Color(1, 0.97, 0.88, fade))
		# 이름 · 병력은 전투 화면의 이름표(초상 + 막대)가 따라온다 —— 겹치지 않게 깃발만
		if sq.armor_broken:      # 파갑 —— 금 간 방패 표시
			var sc := p1 + Vector2(6.0 * s * dir, 4.0 * s)
			draw_circle(sc, 5.5 * s, Color("#e8a84a", fade))
			draw_line(sc + Vector2(-2, -4) * s, sc + Vector2(1, 0) * s, Color(0.1, 0.05, 0, fade), 1.5)
			draw_line(sc + Vector2(1, 0) * s, sc + Vector2(-1, 4) * s, Color(0.1, 0.05, 0, fade), 1.5)


var _over: Overlay

func _enter_tree() -> void:
	if _over == null:
		_over = Overlay.new()
		_over.v = self
		_over.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_over.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_over.z_index = 1
		add_child.call_deferred(_over)



func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAW and _over:
		_over.queue_redraw()


## 병사 인형 그림 —— 흰색(진영색을 곱한다): 머리 · 투구 술 · 몸 · 창. 오른쪽을 본다
func _make_fig() -> Texture2D:
	var n := 32
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var put := func(x: int, y: int, c: Color):
		if x >= 0 and y >= 0 and x < n and y < n:
			img.set_pixel(x, y, c)
	var body := Color(1, 1, 1, 1)
	var dark := Color(0.35, 0.33, 0.3, 1)
	var skin := Color(0.98, 0.86, 0.72, 1)
	for y in n:
		for x in n:
			var fx := (x + 0.5) / n
			var fy := (y + 0.5) / n
			# 머리
			if Vector2(fx - 0.46, fy - 0.2).length() < 0.1:
				put.call(x, y, skin)
			# 투구
			if Vector2(fx - 0.46, fy - 0.16).length() < 0.11 and fy < 0.17:
				put.call(x, y, dark)
			# 몸통 (아래로 넓어지는 갑옷)
			var hw := 0.12 + (fy - 0.3) * 0.25
			if fy > 0.3 and fy < 0.72 and absf(fx - 0.46) < hw:
				put.call(x, y, body)
			# 다리
			if fy >= 0.72 and fy < 0.95 and (absf(fx - 0.40) < 0.045 or absf(fx - 0.53) < 0.045):
				put.call(x, y, dark)
			# 창 (오른손, 비스듬히)
			if absf((fx - 0.72) - (0.55 - fy) * 0.25) < 0.022 and fy > 0.04 and fy < 0.85:
				put.call(x, y, Color(0.55, 0.42, 0.28, 1))
			if absf((fx - 0.78) - (0.55 - fy) * 0.25) < 0.04 and fy > 0.02 and fy < 0.1:
				put.call(x, y, Color(0.85, 0.85, 0.9, 1))
	# 윤곽 —— 투명 칸 옆의 불투명 칸을 어둡게 (작게 그려도 형체가 읽히게)
	var out := img.duplicate()
	for y in n:
		for x in n:
			if img.get_pixel(x, y).a > 0.5:
				continue
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var q: Vector2i = Vector2i(x, y) + d
				if q.x >= 0 and q.y >= 0 and q.x < n and q.y < n and img.get_pixel(q.x, q.y).a > 0.5:
					out.set_pixel(x, y, Color(0.06, 0.05, 0.04, 0.85))
					break
	return ImageTexture.create_from_image(out)


## 채색 지도 바탕 —— 풀빛 · 흙빛 얼룩 (값 노이즈 두 겹). 한 번 만들어 깐다
func _make_bg() -> Texture2D:
	var n := 128
	var noise := FastNoiseLite.new()
	noise.seed = 11
	noise.frequency = 0.035
	noise.fractal_octaves = 3
	var img := Image.create(n, n, false, Image.FORMAT_RGB8)
	var grass := Color("#6d8a4f")
	var grass2 := Color("#86a05a")
	var soil := Color("#a08a5c")
	for y in n:
		for x in n:
			# 이음매 없이 —— 네 귀퉁이를 섞는다
			var u := float(x) / n
			var w := float(y) / n
			var v1 := noise.get_noise_2d(x, y)
			var v2 := noise.get_noise_2d(x - n, y)
			var v3 := noise.get_noise_2d(x, y - n)
			var v4 := noise.get_noise_2d(x - n, y - n)
			var v := lerpf(lerpf(v1, v2, u), lerpf(v3, v4, u), w)
			var c := grass.lerp(grass2, clampf(v * 1.5 + 0.5, 0, 1))
			if v > 0.28:
				c = c.lerp(soil, clampf((v - 0.28) * 3.0, 0, 0.8))
			img.set_pixel(x, y, c)
	return ImageTexture.create_from_image(img)
