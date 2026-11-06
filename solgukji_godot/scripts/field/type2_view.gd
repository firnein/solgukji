class_name Type2View
extends DotView
## 타입2 전장 (11/3 사용자: 삼국지11 스타일 그래픽을 더 디벨롭 —— '타입2' 로 부른다).
## 삼국지11 전투 지도처럼: 비스듬히 내려다본 채색 지도판 + 옅은 육각 격자, 부대는 작은 병사 인형 무리(진영색) +
## 뒤에 큰 깃발(성씨 한 글자, 등급색 테두리) + 아래 이름판(이름 · 병력 막대). 상태는 발밑 육각 칸으로(수몰 파랑 · 화상 주황 · 파갑 금 간 방패).
## 판정 · 움직임은 그대로(Squad · RtBattle), 그리기만 바꾼다 —— DotView 를 물려받아 War3D.flat 자리에 들어간다
## (이름표 · 피해 숫자 · 기술 범위는 DotView 처럼 map() 을 따라온다).

const TILT := 1.25             # 세로 배율 —— 11/6 사용자 "더 넓게": 세로 화면을 다 쓰도록 앞뒤 거리를 늘린다 (0.62 눌림 → 1.25 늘림)
const FIG := 17.0              # 병사 인형 크기 (px, 화면 —— 배율 1 기준) —— 11/6 보는 맛: 15 → 17
const T2_SPREAD := 1.0         # 11/7 군집 강체: 병사는 엔진 발자국을 그대로 채운다 (넓혀 그리던 1.35 는 RtBattle.FP_SPREAD 로 발자국에 들어갔다)
const HEX := 34.0              # 육각 한 칸 (전장 px)
const CLONES := 1              # 11/6 3차(목표: 휴대폰에서도 품질 그대로 대군): 묶음(단순한 인형 열둘) 하나 = 병사 하나 —— 화면 병사 수 4배, 그리는 칸은 1/3
const CLONES_SMALL := 2        # 병사가 SMALL_SQ 명보다 적은 부대(1일차 등)
const PACK := 12               # 묶음 그림 하나에 든 인형 수 (4 × 3)
const STRIDE := 16             # 멀티메시 버퍼 한 칸 —— 변환 8 + 색 4 + 사용자 4 (x: 아틀라스 왼쪽 0 = 장수 한 명, 0.5 = 묶음)
const SMALL_SQ := 12
const CLONE_OFF := [Vector2(0, 0), Vector2(0.62, 0.42), Vector2(-0.58, 0.5), Vector2(0.1, 0.85), Vector2(-0.3, -0.45)]     # 인형 크기 대비 자리 (예전)
const CLONE_GRID := [Vector2(0, 0), Vector2(0.5, 0.5), Vector2(-0.5, 0.5), Vector2(0.5, -0.5), Vector2(-0.5, -0.5)]   # 대열 반 칸 단위 (오른쪽, 앞) —— 명세 1단계
## 1단계-3: 병종별 대열 모양 —— 가로 간격 배율. 창병 밀집, 궁병 산개, 책략계 호위 간격 (병사 수 · 판정은 그대로)
const FORM_SHAPE := {"창병": 0.9, "기병": 1.05, "궁병": 1.25, "도적": 1.1, "책사": 1.15, "유생": 1.15, "술사": 1.15, "모사": 1.15}
const TEAM_A := Color("#4a8ae8")      # 11/6 묶음 인형은 작아서 색이 탁해진다 —— 밝게
const TEAM_B := Color("#ec4f3c")

var _fig_tex: Texture2D
var _ground: ColorRect          # 바닥 —— 셰이더 지도 (shaders/type2_ground.gdshader, 11/6)
var _under: Under               # 병사 아래 층 —— 부대 바닥 · 흙먼지 · 상태 칸 · 기술 범위
var _mid_y := 0.0


func _ready() -> void:
	super._ready()
	_fig_tex = _make_atlas()
	_mm.texture = _fig_tex
	_mm.multimesh.instance_count = 0
	_mm.multimesh.use_custom_data = true
	var fm := ShaderMaterial.new()
	fm.shader = Shader.new()
	fm.shader.code = FIG_SHADER
	_mm.material = fm
	_ground = ColorRect.new()
	_ground.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ground.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/type2_ground.gdshader")
	_ground.material = mat
	add_child(_ground)
	move_child(_ground, 0)
	_under = Under.new()
	_under.v = self
	_under.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_under.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_under)
	move_child(_under, 1)


func setup() -> void:
	_camp_cache.clear()
	super.setup()
	for sq: Squad in field.order:
		var base := TEAM_A if sq.camp == "A" else TEAM_B
		_col[sq.key] = base.lightened(0.06 * (sq.row.slot % 3)) if sq.tier < 6 else base.lerp(DB.TIER[sq.tier].c, 0.25)
	var ys := 0.0
	for sq: Squad in field.order:
		ys += sq.pos.y
	_mid_y = ys / maxf(1.0, field.order.size())
	_roll_ground()
	_reset_feel()
	_setup_tac()
	_build_gpu()


## 전장 px → 화면 px —— DotView 처럼 아군 아래 · 적 위, 세로를 TILT 만큼 눌러 비스듬히
func map(p: Vector2) -> Vector2:
	var d := p - _center - _jit
	return size * 0.5 + Vector2(d.y, -d.x * TILT) * _scale


func _fit(now := false) -> void:
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for sq: Squad in field.order:
		if not sq.alive or sq.state == "gone" or sq.state == "flee":
			continue
		var r := maxf(sq.depth(), sq.hw * 2.0) * 0.3 * T2_SPREAD      # 11/6 사용자: 더 넓게 —— 부대 한가운데만 담고 화면을 꽉 채운다
		lo = lo.min(sq.pos - Vector2(r, r))
		hi = hi.max(sq.pos + Vector2(r, r))
	if lo.x == INF:
		return
	var span := hi - lo
	var s := minf((size.x - 40.0 * 2) / maxf(span.y, 1.0), (size.y - 75.0 * 2) / maxf(span.x * TILT, 1.0))
	_want_scale = clampf(s, 0.35, 3.0)
	_want_center = (lo + hi) * 0.5
	_base_scale = _want_scale
	if _focus_on():
		_want_scale = clampf(_base_scale * float(_focus.mul), 0.35, 4.0)
		_want_center = _focus.c
	if now:
		_scale = _want_scale
		_center = _want_center


## 부하 조절 (11/6 목표) —— 실제 프레임 시간을 지켜보다 무거우면 단계를 올린다. 병사 수는 줄이지 않는다.
## 0 그대로 · 1 전선 먼지 · 이동 먼지 · 불티를 줄이고 바닥 층을 3프레임마다 · 2 + 2D 연출 상한 낮춤 · HUD 를 30Hz 로
var load_lv := 0
var _ft := 1.0 / 60.0
var _lv_hold := 0.0
var drawn_figs := 0            # 지난 프레임에 그린 인형 수 (묶음 × PACK) —— 성능 표시용


func _load_step(dt: float) -> void:
	var real := Performance.get_monitor(Performance.TIME_PROCESS)
	_ft = lerpf(_ft, maxf(dt, real), 0.05)
	_lv_hold -= dt
	if _lv_hold > 0.0:
		return
	if _ft > 1.0 / 40.0 and load_lv < 2:
		load_lv += 1
		_lv_hold = 2.0
	elif _ft < 1.0 / 57.0 and load_lv > 0:
		load_lv -= 1
		_lv_hold = 4.0


func _process(dt: float) -> void:
	var t0 := Time.get_ticks_usec()
	_load_step(dt)
	super._process(dt)
	if not visible or field == null:
		return
	field.pt("타입2 병사", t0)
	_feel_step(dt)
	if _gmm != null:
		var gm: ShaderMaterial = _gmm.material
		gm.set_shader_parameter("center", _center + _jit)
		gm.set_shader_parameter("scl", _scale)
		gm.set_shader_parameter("vsize", size)
		gm.set_shader_parameter("fig", FIG * clampf(_scale * 1.15, 0.6, 1.8) * GPU_FIG)
	var mat: ShaderMaterial = _ground.material
	mat.set_shader_parameter("center", _center + _jit)
	mat.set_shader_parameter("scl", _scale)
	mat.set_shader_parameter("tilt", TILT)
	mat.set_shader_parameter("vsize", size)
	mat.set_shader_parameter("mid_y", _mid_y)
	mat.set_shader_parameter("hex", HEX)
	mat.set_shader_parameter("camp_a", _camp_x("A"))
	mat.set_shader_parameter("camp_b", _camp_x("B"))
	if Engine.get_process_frames() % (2 if load_lv == 0 else 3) == 1:
		_under.queue_redraw()      # 부대 바닥이 부대를 따라가야 한다 (무거우면 3프레임마다)
	if _fx_layer and (not _fx.is_empty() or Engine.get_process_frames() % 2 == 0):      # 깃발이 부대를 따라간다
		_fx_layer.queue_redraw()
		if _fx_add:
			_fx_add.queue_redraw()
	if _label_layer and field.clock - _intro_t0 < INTRO_T + 0.5:
		_label_layer.queue_redraw()
	elif _label_layer and _label_layer.visible:
		_label_layer.visible = false      # 다 보여 줬다 —— 다음 전투에서 다시 켠다


## 진영 시작선 (전장 x) —— 바닥에 옅은 진지선을 긋는다 (11/6 사용자: 바닥 타일링 의미 불분명 → 의미 있는 선만)
var _camp_cache := {}
func _camp_x(cp: String) -> float:
	if _camp_cache.has(cp):
		return _camp_cache[cp]
	var s := 0.0
	var n := 0
	for sq: Squad in field.order:
		if sq.camp == cp:
			s += sq.pos.x
			n += 1
	if n == 0:
		return 0.0
	_camp_cache[cp] = s / n
	return _camp_cache[cp]


func _area_spread() -> float:
	return T2_SPREAD


func _area_alpha() -> float:
	return 0.7


func _clones(sq: Squad) -> int:
	return CLONES_SMALL if sq.soldiers.size() < SMALL_SQ else CLONES


## 병사 인형 —— 진영색, 맞으면 흰빛, 쓰러지면 눕고 바랜다. 위에 있을수록(멀수록) 먼저 그려 겹침 순서를 맞춘다
var _buf := PackedFloat32Array()
static var UNIT_C := _unit_circle(16)
## 발자국 판 꼭짓점 (앞 x · 오른쪽 y, 반폭 단위) —— 앞끝 두 점이 먼저 (앞끝 선을 긋는다), 모서리는 깎았다
const FOOT_C := [Vector2(1, -0.8), Vector2(1, 0.8), Vector2(0.8, 1), Vector2(-0.8, 1), Vector2(-1, 0.8), Vector2(-1, -0.8), Vector2(-0.8, -1), Vector2(0.8, -1)]


static func _unit_circle(n: int) -> PackedVector2Array:
	var out := PackedVector2Array()
	for k in n:
		out.append(Vector2(cos(TAU * k / n), sin(TAU * k / n)))
	return out


func _draw_dots() -> void:
	var mm := _mm.multimesh
	# 11/6 병사 1,000명 넘게 매번 정렬하던 것을 부대 단위 정렬로 (후반 fps 68 → ?) —— 부대끼리 겹침 순서만 맞으면 충분하다
	var sqs: Array = field.order.duplicate()
	sqs.sort_custom(func(a, b): return map(a.pos).y < map(b.pos).y)
	var gpu_on0: bool = _gmm != null
	var nfig := 0
	var sparks := 0
	var clock0 := field.clock
	for sq: Squad in sqs:
		if gpu_on0:      # GPU 전투 —— CPU 는 장수 · 쓰러지는 병사만 (병사 4천 명을 매 프레임 훑지 않는다)
			var dl: Array = _dying.get(sq.key, [])
			if not dl.is_empty() and Engine.get_process_frames() % 30 == 0:
				_dying[sq.key] = dl.filter(func(x): return x.die_t >= 0 and clock0 - x.die_t <= 2.0 and not x.alive)
			nfig += 1 + _dying.get(sq.key, []).size()
		else:
			nfig += sq.soldiers.size()
		if sq.alive and sq.contact and sq.engaged != null:
			sparks += 8 if load_lv == 0 else 3
	var total := nfig * (1 if gpu_on0 else CLONES_SMALL) + sparks
	if mm.instance_count < total or mm.instance_count > total * 2 + 256:      # 버퍼를 꼭 필요한 만큼만 (매 프레임 통째로 올린다)
		mm.instance_count = total + 64
	if _buf.size() != mm.instance_count * STRIDE:
		_buf.resize(mm.instance_count * STRIDE)
	var clock := field.clock
	var gpu_on: bool = _gmm != null
	# 11/6 인스턴스마다 set_instance_* 를 부르던 것을 버퍼 한 번에 (2D 변환 8 + 색 4). 남는 칸은 visible_instance_count 로 감춘다
	var i := 0
	var sz := FIG * clampf(_scale * 1.15, 0.6, 1.8)
	for sq: Squad in sqs:
		if sq.state == "gone":
			continue
		var base_c: Color = _col.get(sq.key, Color.WHITE)
		var flip := -1.0 if (sq.camp == "B") else 1.0
		var ncl := _clones(sq)
		var lean := -0.35 if sq.camp == "A" else 0.35
		var back_s := (map(sq.pos - sq.fwd * 10.0) - map(sq.pos)) / 10.0      # 화면에서 '뒤로' 1px 당
		# 1단계(명세): 복제 인형은 랜덤 오프셋이 아니라 대열 격자의 빈 칸(병사 사이 중간점)에 —— 대열이 촘촘한 직사각형으로 보인다
		var hs: float = sq.sp * T2_SPREAD * 0.5
		var dr: Vector2 = map(sq.pos + sq.right() * hs) - map(sq.pos)
		var df: Vector2 = map(sq.pos + sq.fwd * hs) - map(sq.pos)
		var shape: float = FORM_SHAPE.get(sq.tag, 1.0)
		dr *= shape
		var figs_cpu: Array = sq.soldiers
		if gpu_on:
			figs_cpu = ([sq.general] if sq.general else []) + _dying.get(sq.key, [])
		for s in figs_cpu:
			if gpu_on and s.alive and s != sq.general:
				continue      # GPU 병사 —— 셰이더가 그린다
			var rot := 0.0
			var c := base_c
			if not s.alive:
				if s.die_t < 0:
					continue
				var dt: float = clock - s.die_t
				if dt > 2.0:
					continue
				rot = s.fall * minf(1.0, dt / 0.35) * PI * (0.5 if s == sq.general or gpu_on else 0.18)
				c = c.darkened(0.45)
				c.a = clampf(1.0 - (dt - 1.2) / 0.8, 0, 1)
			elif sq.state == "flee":
				c.a = sq.fade
			if sq.armor_broken and s.alive:
				c = c.lerp(Color("#7a4a2a"), 0.35)      # 파갑 —— 갑옷이 녹슨 빛
			if clock - s.hit_t < 0.15 and clock >= s.hit_t:
				c = c.lerp(Color(1, 1, 1), 0.3)      # 맞은 빛은 옅고 짧게 —— 무리 전체가 번쩍거렸다
			var p := map(sq.pos + (s.pos - sq.pos) * T2_SPREAD + s.jit * 1.2)
			if not s.alive:      # 맞아 쓰러지며 뒤로 밀려난다
				p += back_s * 9.0 * ease(minf(1.0, (clock - s.die_t) / 0.3), 0.4)
			elif clock - s.hit_t < 0.18 and clock >= s.hit_t:      # 맞으면 움찔 뒤로
				p += back_s * 3.0 * sin(PI * (clock - s.hit_t) / 0.18)
			if s.air > 0.0:
				p.y -= s.air * 6.0 * _scale
				rot = s.spin
			var bob := 0.0
			if s.alive:      # 걸음 —— 위아래로 살짝, 공격 —— 앞으로 기운다
				bob = s.walk * 0.9
				p.y -= absf(sin(bob)) * 1.4
				var a: float = (clock - s.atk_t0) / Squad.ATTACK_TIME
				if a >= 0 and a <= 1:
					rot = lean * sin(PI * a)
			var gen: bool = s == sq.general
			var dep: float = 0.82 + 0.18 * clampf(p.y / maxf(size.y, 1.0), 0.0, 1.0)      # 1단계-2: 화면 위(먼) 부대는 작게
			var h: float = sz * (1.25 if gen else 1.0) * s.size * dep
			var cr := cos(rot)
			var sr := sin(rot)
			var one: bool = gen or gpu_on      # GPU 전투의 쓰러지는 병사는 한 명짜리 인형
			if gpu_on and not gen:
				h *= GPU_FIG
			for ci in (1 if one else ncl):
				var hc := h * (1.0 if ci == 0 else 0.94) * (1.0 if one else PACK_H)
				var o: Vector2 = (dr * CLONE_GRID[ci].x + df * CLONE_GRID[ci].y) + Vector2(0, -hc * 0.5)
				if ci > 0 and s.alive:
					o.y -= absf(sin(bob + ci * 0.9)) * 1.4 - absf(sin(bob)) * 1.4      # 복제마다 걸음 위상을 어긋나게
				var cc := c if ci == 0 else c.darkened(0.06 * ci)
				var b := i * STRIDE
				var sx := hc * flip * (1.0 if one else PACK_W)
				_buf[b] = cr * sx
				_buf[b + 1] = -sr * hc
				_buf[b + 2] = 0.0
				_buf[b + 3] = p.x + o.x
				_buf[b + 4] = sr * sx
				_buf[b + 5] = cr * hc
				_buf[b + 6] = 0.0
				_buf[b + 7] = p.y + o.y
				_buf[b + 8] = cc.r
				_buf[b + 9] = cc.g
				_buf[b + 10] = cc.b
				_buf[b + 11] = cc.a
				_buf[b + 12] = 0.0 if one else 0.5
				i += 1
	# 전선 불꽃
	for sq: Squad in field.order:
		if not (sq.alive and sq.contact and sq.engaged != null):
			continue
		var en: Squad = sq.engaged
		var mid: Vector2 = en.pos + sq.axis * en.edge(sq.axis)      # 맞닿은 가장자리
		var perp := Vector2(-sq.axis.y, sq.axis.x)
		for j in (8 if load_lv == 0 else 3):
			var ph := fposmod(_t * 3.0 + j * 0.41 + float(sq.row.slot) * 0.13, 1.0)
			var at: Vector2 = mid + perp * (fposmod(j * 37.3 + floor(_t * 3.0 + j * 0.41) * 11.0, 1.0) - 0.5) * sq.hw * 2.0
			var sp := 4.5 * (1.0 - ph) * clampf(_scale, 0.7, 1.6)
			var q := map(at) + Vector2(0, -ph * 10.0 - 6.0)
			var r := ph * 3.0
			var b := i * STRIDE
			_buf[b] = cos(r) * sp
			_buf[b + 1] = -sin(r) * sp
			_buf[b + 2] = 0.0
			_buf[b + 3] = q.x
			_buf[b + 4] = sin(r) * sp
			_buf[b + 5] = cos(r) * sp
			_buf[b + 6] = 0.0
			_buf[b + 7] = q.y
			_buf[b + 8] = 1.0
			_buf[b + 9] = 0.9
			_buf[b + 10] = 0.65
			_buf[b + 11] = 0.85 * (1.0 - ph)
			_buf[b + 12] = 0.0
			i += 1
	mm.buffer = _buf
	mm.visible_instance_count = i
	drawn_figs = i


## 바닥은 셰이더(_ground), 부대 바닥 · 상태는 Under 층이 그린다 (11/6 깃발 뺌 —— 사용자: 깃발 같은 건 빼고 넓게) —— 이 노드는 아무것도 그리지 않는다
func _draw() -> void:
	pass


class Under extends Control:
	var v: Type2View
	func _draw() -> void:
		if v != null and v.field != null:
			v._draw_under(self)


## 병사 아래 —— 부대 바닥(진영색 타원, 아군 · 적 덩어리가 한눈에) · 걷는 부대 뒤 흙먼지 · 상태 칸 · 기술 범위
func _draw_under(ci: CanvasItem) -> void:
	var t0 := Time.get_ticks_usec()
	_draw_under_inner(ci)
	field.pt("타입2 바닥", t0)


func _draw_under_inner(ci: CanvasItem) -> void:
	for sq: Squad in field.order:
		if not sq.alive or sq.state == "gone":
			continue
		var fade: float = sq.fade if sq.state == "flee" else 1.0
		var team := TEAM_A if sq.camp == "A" else TEAM_B
		# 11/7 군집 강체 —— 부대 발자국(엔진이 겹치지 않게 놓는 직사각형)을 모서리를 깎은 판으로. 앞끝은 밝은 선 (어디를 보는지)
		var hd := sq.hd() + 4.0
		var hw := sq.hw + 4.0
		var c := sq.pos
		var rt := sq.right()
		var mc := map(c)      # 지도는 1차 변환 —— 축 둘만 옮기고 꼭짓점은 조합한다 (map 을 점마다 부르지 않게)
		var ex := map(c + sq.fwd * hd) - mc
		var ey := map(c + rt * hw) - mc
		var pts := PackedVector2Array()
		pts.resize(FOOT_C.size())
		for k in FOOT_C.size():
			pts[k] = mc + ex * FOOT_C[k].x + ey * FOOT_C[k].y
		var hl: float = view.hud.highlight_k(sq.key) if view != null and view.hud != null else 0.0      # 11/6 #11 아래 프로필을 누른 부대
		# 11/7 사용자: 장수(부대)를 감싸는 판 · 테두리 선은 뺀다 —— 아래 프로필을 눌러 강조할 때만 잠깐 보인다
		if hl > 0.01:
			ci.draw_colored_polygon(pts, Color(team.lightened(hl * 0.5), 0.35 * hl * fade))
			pts.append(pts[0])
			ci.draw_polyline(pts, Color(team.lightened(0.85), hl * fade), 1.6 + 2.4 * hl)
		# 전선 먼지 —— 맞붙은 자리에 흙먼지가 계속 인다 (11/6 보는 맛)
		if load_lv == 0 and sq.contact and sq.engaged != null and is_instance_valid(sq.engaged):
			var mid: Vector2 = sq.engaged.pos + sq.axis * sq.engaged.edge(sq.axis)
			var perp := Vector2(-sq.axis.y, sq.axis.x)
			for j in 4:
				var ph := fposmod(_t * 0.9 + j * 0.25 + sq.row.slot * 0.17, 1.0)
				var at: Vector2 = mid + perp * (fposmod(j * 0.29 + sq.row.slot * 0.11, 1.0) - 0.5) * sq.hw * 2.0 * T2_SPREAD
				ci.draw_circle(map(at), (5.0 + ph * 12.0) * clampf(_scale, 0.6, 1.8), Color(0.74, 0.66, 0.5, 0.26 * sin(PI * ph)))
		# 흙먼지 —— 움직이는 부대 뒤로 뭉게뭉게
		if load_lv == 0 and sq.moving and sq.state != "flee":
			for j in 5:
				var ph := fposmod(_t * 1.4 + j * 0.2, 1.0)
				var at: Vector2 = c - sq.fwd * (hd + 4.0 + ph * 22.0) + rt * (fposmod(j * 0.37, 1.0) - 0.5) * hw * 1.4
				ci.draw_circle(map(at), (3.0 + ph * 7.0) * clampf(_scale, 0.6, 1.6), Color(0.72, 0.64, 0.48, 0.32 * (1.0 - ph)))
	_draw_tac_under(ci)
	_draw_status_hex(ci)
	_draw_areas(ci)


## 부대 발밑 상태 칸 —— 삼국지11 처럼 칸에 불 · 물을 칠한다
func _hex_at(ci: CanvasItem, p: Vector2, col: Color, fill_a: float) -> void:
	var pts := PackedVector2Array()
	for k in 6:
		var a := PI / 3.0 * k
		pts.append(map(p + Vector2(cos(a), sin(a)) * HEX * 1.4))
	ci.draw_colored_polygon(pts, Color(col, fill_a * 0.6))
	pts.append(pts[0])
	ci.draw_polyline(pts, Color(col, minf(0.5, fill_a * 2.0)), 1.2)      # 11/6 옅게 —— 화상 칸이 화면을 덮었다


func _draw_status_hex(ci: CanvasItem) -> void:
	for sq: Squad in field.order:
		if not sq.alive or sq.state == "gone":
			continue
		var c := sq.pos
		if sq.statuses.has("burn"):
			_hex_at(ci, c, Color("#ff7a2a"), 0.22 + 0.08 * sin(_t * 8.0 + sq.row.slot))
		if sq.statuses.has("flood"):
			_hex_at(ci, c, Color("#3d8fe0"), 0.24 + 0.06 * sin(_t * 3.0))       # 이감 —— 물에 발이 묶였다
		if sq.statuses.has("confuse"):
			_hex_at(ci, c, Color("#b57edc"), 0.18)


## 병사 인형 그림 —— 흰색(진영색을 곱한다): 머리 · 투구 술 · 몸 · 창. 오른쪽을 본다
const PACK_W := 1.7            # 묶음 칸 가로 배율 (인형 크기 대비)
const PACK_H := 1.35
const FIG_SHADER := """
shader_type canvas_item;
varying float atlas_x;
varying vec4 tint;
void vertex() {
	atlas_x = INSTANCE_CUSTOM.x;
	tint = COLOR;
}
void fragment() {
	vec4 t = texture(TEXTURE, vec2(UV.x * 0.5 + atlas_x, UV.y));
	COLOR = t * tint;
}
"""


## 아틀라스 64 × 32 —— 왼쪽 32: 장수 한 명(예전 인형), 오른쪽 32: 단순한 인형 여섯 묶음(뒤 줄 셋 · 앞 줄 셋, 머리 · 몸 · 창 한 줄)
func _make_atlas() -> Texture2D:
	var one: Image = (_make_fig() as ImageTexture).get_image()
	var n := 48
	one.resize(n, n, Image.INTERPOLATE_NEAREST)
	var img := Image.create(n * 2, n, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	img.blit_rect(one, Rect2i(0, 0, n, n), Vector2i(0, 0))
	var pack := Image.create(n, n, false, Image.FORMAT_RGBA8)
	pack.fill(Color(0, 0, 0, 0))
	var body := Color(1, 1, 1, 1)
	var dark := Color(0.32, 0.3, 0.27, 1)
	var skin := Color(0.96, 0.84, 0.7, 1)
	var spear := Color(0.6, 0.47, 0.3, 1)
	# [가운데 x, 발 y, 키] —— 뒤 줄은 위로 · 조금 작게, 앞 줄은 반 칸 비켜서
	var men := [[5.5, 15.0, 11.0], [17.5, 14.0, 11.0], [29.5, 15.0, 11.0], [41.5, 14.5, 11.0],
		[11.0, 30.5, 12.0], [23.0, 31.0, 12.0], [35.0, 30.0, 12.0], [44.5, 31.0, 12.0],
		[5.5, 46.5, 13.0], [17.5, 47.0, 13.0], [29.5, 46.0, 13.0], [41.5, 47.0, 13.0]]
	for m in men:
		var cx: float = m[0]
		var fy: float = m[1]
		var h: float = m[2]
		var hy := fy - h      # 머리 꼭대기
		for y in range(int(hy) - 3, int(fy) + 1):
			for x in range(int(cx) - 5, int(cx) + 6):
				if x < 0 or y < 0 or x >= n or y >= n:
					continue
				var px := x + 0.5
				var py := y + 0.5
				var col := Color(0, 0, 0, 0)
				# 창 —— 오른쪽으로 비스듬히 위로
				if absf((px - (cx + 3.2)) + (py - (hy + h * 0.4)) * 0.18) < 0.6 and py > hy - 3 and py < fy - 1:
					col = spear
				# 몸 (사다리꼴)
				var t := (py - (hy + h * 0.32)) / (h * 0.5)
				if t >= 0.0 and t <= 1.0 and absf(px - cx) < 1.6 + t * 1.3:
					col = body
				# 다리
				if py > hy + h * 0.82 and py <= fy and (absf(px - (cx - 1.0)) < 0.7 or absf(px - (cx + 1.0)) < 0.7):
					col = dark
				# 머리
				if Vector2(px - cx, py - (hy + h * 0.2)).length() < h * 0.17:
					col = skin
				if Vector2(px - cx, py - (hy + h * 0.13)).length() < h * 0.18 and py < hy + h * 0.15:
					col = dark      # 투구
				if col.a > 0.0:
					pack.set_pixel(x, y, col)
	# 윤곽
	var out := pack.duplicate()
	for y in n:
		for x in n:
			if pack.get_pixel(x, y).a > 0.5:
				continue
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var q: Vector2i = Vector2i(x, y) + d
				if q.x >= 0 and q.y >= 0 and q.x < n and q.y < n and pack.get_pixel(q.x, q.y).a > 0.5:
					out.set_pixel(x, y, Color(0.06, 0.05, 0.04, 0.8))
					break
	img.blit_rect(out, Rect2i(0, 0, n, n), Vector2i(n, 0))
	return ImageTexture.create_from_image(img)


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


func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAW and _under:
		_under.queue_redraw()      # 기술 범위가 떠 있으면 DotView 가 매 프레임 다시 그린다


# ───────── 2D 연출 (11/6 사용자: 타입2 면 번쩍이는 것들과 기존 연출을 손봐야) ─────────
# 3D 연출(입자 · 점광 · 법진)은 타입2 에서 보이지 않고 부하만 냈다 —— War3D.minor_fx · UltFx.play · fire_patch 가
# 타입2 면 여기로 넘긴다. 번쩍임 없이: 화면 섬광 대신 퍼지는 고리 · 짧은 번개 · 땅에 남는 불 · 옅은 안개.

class FxLayer extends Control:
	var v: Type2View
	var add := false
	func _draw() -> void:
		if v != null and v.field != null:
			if add:
				v._draw_fx_add(self)
			else:
				v._draw_fx(self)


var _fx := []                  # {k, p, q, col, t0, life, r, s}
var _fx_layer: FxLayer
var _frng := RandomNumberGenerator.new()


class LabelLayer extends Control:
	var v: Type2View
	func _draw() -> void:
		if v != null and v.field != null:
			v._draw_tac_top(self)


var _label_layer: LabelLayer
var _fx_add: FxLayer
var _sprs := {}


func _spr(nm: String) -> Texture2D:
	if not _sprs.has(nm):
		_sprs[nm] = load("res://assets/fx/kenney/%s.png" % nm) if ResourceLoader.exists("res://assets/fx/kenney/%s.png" % nm) else null
	return _sprs[nm]


## 스프라이트 하나 —— 가운데 c, 크기 sz(px), 회전 rot
func _spr_at(ci: CanvasItem, nm: String, c: Vector2, sz: float, col: Color, rot := 0.0, stretch := Vector2.ONE) -> void:
	var t := _spr(nm)
	if t == null or sz < 1.0:
		return
	ci.draw_set_transform(c, rot, stretch)
	ci.draw_texture_rect(t, Rect2(Vector2(-sz, -sz) * 0.5, Vector2(sz, sz)), false, col)
	ci.draw_set_transform(Vector2.ZERO)


## 더하기 층 —— 빛나는 것만 (불꽃 · 불벽 · 불덩이 · 불기둥 · 검기 · 충격파 · 튀는 불티 · 번개 빛 · 소용돌이 · 회복 빛)
func _draw_fx_add(ci: CanvasItem) -> void:
	var now := field.clock
	var zs := clampf(_scale, 0.6, 1.8)
	var fl := ["flame_02", "flame_03", "flame_04"]
	for e in _fx:
		var u: float = (now - e.t0) / e.life
		if u < 0.0 or u >= 1.0:
			continue
		var col: Color = e.col
		var p: Vector2 = e.p
		var sp := map(p)
		match e.k:
			"fire":
				var al := clampf(u * 8.0, 0, 1) * clampf((1.0 - u) * 5.0, 0, 1)
				for j in 3:
					var ph: float = _t * (6.0 + j) + e.s + j * 2.1
					var base := sp + Vector2((j - 1) * e.r * 0.5 * zs, 0)
					var h: float = e.r * zs * (2.0 + 0.4 * sin(ph))
					_spr_at(ci, fl[(int(_t * 10.0 + j + e.s)) % 3], base + Vector2(0, -h * 0.4), h, Color(1.0, 0.5, 0.15, 0.8 * al), sin(ph) * 0.12, Vector2(0.7, 1.0))
				_spr_at(ci, "light_02", sp, e.r * zs * 3.0, Color(1.0, 0.45, 0.1, 0.35 * al))
			"firewall":
				var dir: Vector2 = (p - e.q).normalized() if e.q != p else Vector2.RIGHT
				var perp := Vector2(-dir.y, dir.x)
				var front: Vector2 = p - dir * e.r + dir * e.r * 2.0 * ease(u, 0.6)
				var al := clampf(u * 6.0, 0, 1) * clampf((1.0 - u) * 3.0, 0, 1)
				for j in 11:
					var f := (j / 10.0 - 0.5) * 2.0
					var bp := map(front + perp * f * e.r * 1.1)
					var ph: float = _t * 9.0 + j * 1.7 + e.s
					var h: float = e.r * zs * (0.75 + 0.2 * sin(ph)) * (1.0 - absf(f) * 0.35)
					_spr_at(ci, fl[(j + int(_t * 12.0)) % 3], bp + Vector2(0, -h * 0.4), h, Color(1.0, 0.45, 0.12, 0.9 * al), sin(ph) * 0.15, Vector2(0.75, 1.0))
				_spr_at(ci, "light_02", map(front), e.r * zs * 3.2, Color(1.0, 0.4, 0.1, 0.4 * al))
			"fireball":
				var from := map(e.q)
				for j in 5:
					var bu := maxf(0.0, u - j * 0.04)
					var bp := from.lerp(sp, bu) + Vector2(0, -sin(PI * bu) * 90.0 * zs)
					_spr_at(ci, "fire_01" if j == 0 else "smoke_04", bp, e.r * zs * (2.4 - j * 0.3), Color(1.0, 0.55, 0.15, 0.9 - j * 0.16), _t * 4.0 + j)
				if u > 0.9:
					_spr_at(ci, "muzzle_02", sp, e.r * zs * 5.0, Color(1.0, 0.6, 0.2, (1.0 - u) * 9.0), e.s)
			"pillar":
				var al := sin(PI * u)
				var h: float = e.r * zs * 2.0 * ease(clampf(u * 1.6, 0, 1), 0.4)
				_spr_at(ci, "flame_03", sp + Vector2(0, -h * 0.45), h, Color(1.0, 0.5, 0.15, 0.9 * al), 0.0, Vector2(0.45, 1.0))
				_spr_at(ci, "light_02", sp, e.r * zs * 2.6, Color(1.0, 0.5, 0.15, 0.5 * al))
			"pillar_c":
				var al := sin(PI * u)
				_spr_at(ci, "light_02", sp + Vector2(0, -e.r * zs * 0.8), e.r * zs * 2.4, Color(col, 0.6 * al), 0.0, Vector2(0.35, 1.0))
				_spr_at(ci, "magic_03", sp, e.r * zs * 1.6, Color(col, 0.7 * al), _t * 1.5)
			"slash":
				var dir: Vector2 = (sp - map(e.q)).normalized() if e.q != Vector2.ZERO else Vector2.RIGHT
				var al := 1.0 - u
				_spr_at(ci, ["slash_01", "slash_02", "slash_03"][int(e.s) % 3], sp, e.r * zs * (1.6 + 0.6 * u), Color(col, 0.95 * al), dir.angle() + PI * 0.5)
			"shock":
				_spr_at(ci, "circle_05", sp, e.r * zs * 2.2 * ease(u, 0.3), Color(col, 0.7 * (1.0 - u)), 0.0, Vector2(1.0, 1.0 / TILT * 0.8))
			"burst":
				_spr_at(ci, ["spark_01", "spark_04"][int(e.s) % 2], sp, e.r * zs * (1.2 + 1.2 * u), Color(col, 1.0 - u), e.s)
			"bigbolt", "bolt":
				var al := 1.0 - u
				_spr_at(ci, "light_02", sp, (60.0 if e.k == "bigbolt" else 26.0) * zs, Color(col.lightened(0.3), 0.8 * al))
				_spr_at(ci, "star_06", sp, (44.0 if e.k == "bigbolt" else 18.0) * zs, Color(1, 1, 1, al), e.s)
			"spiral":
				_spr_at(ci, "twirl_01", sp, e.r * zs * 2.2, Color(col, 0.75 * sin(PI * u)), -_t * 3.0, Vector2(1.0, 0.8))
			"heal":
				_spr_at(ci, "magic_05", sp + Vector2(0, -u * 30.0 * zs), e.r * zs * 1.4, Color(col, 0.8 * sin(PI * u)), _t)


func _ensure_fx_layer() -> void:
	if _label_layer == null:      # 진형 이름 —— 전투 HUD(이름표 메달)보다 위 (시작 몇 초만)
		_label_layer = LabelLayer.new()
		_label_layer.v = self
		_label_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_label_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_label_layer.z_index = 5
		add_child(_label_layer)
	if _fx_layer == null:
		_fx_layer = FxLayer.new()
		_fx_layer.v = self
		_fx_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_fx_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		add_child(_fx_layer)      # 병사(_mm) 위, 전투 HUD 아래
		# 11/7 빛나는 연출(불 · 검기 · 충격파 · 번개 빛)은 더하기(Add) 섞기 층에 Kenney CC0 스프라이트로 (assets/fx/kenney)
		_fx_add = FxLayer.new()
		_fx_add.v = self
		_fx_add.add = true
		_fx_add.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_fx_add.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		var am := CanvasItemMaterial.new()
		am.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		_fx_add.material = am
		add_child(_fx_add)


func fx(k: String, p: Vector2, col: Color, life: float, delay := 0.0, r := 30.0, q := Vector2.ZERO) -> void:
	_ensure_fx_layer()
	if _fx.size() > (320 if load_lv < 2 else 120):      # 11/7 고유기 연출이 커져 칸을 늘렸다
		return
	_fx.append({"k": k, "p": p, "q": q, "col": col, "t0": field.clock + delay, "life": life, "r": r, "s": _frng.randf() * 100.0})


## 부대가 보이는 한가운데 (병사는 T2_SPREAD 만큼 넓혀 그린다) · 그 둘레 한 점
func vis_c(sq: Squad) -> Vector2:
	return sq.pos      # 11/7 강체: pos 가 발자국 한가운데


func vis_spot(sq: Squad) -> Vector2:
	var wd := maxf(10.0, sq.hw * 0.8)
	var dd := maxf(6.0, sq.hd() * 0.6)
	return vis_c(sq) + sq.right() * _frng.randf_range(-wd, wd) + sq.fwd * _frng.randf_range(-dd, dd)


func fx_minor(mk: String, a: Squad, d: Squad) -> void:
	var ap := vis_c(a)
	var dp := vis_c(d)
	match mk:
		"fire":
			for i in 3:
				fx("proj", vis_spot(d), Color("#ff8a3c"), 0.45, i * 0.06, 0.0, ap)
			for i in 2:
				fx("fire", vis_spot(d), Color("#ff7a2a"), 4.0, 0.45, 9.0)
		"poison":
			fx("proj", dp, Color("#7fd06b"), 0.45, 0.0, 0.0, ap)
			for i in 2:
				fx("mist", vis_spot(d), Color("#7fd06b"), 2.2, 0.45, 22.0)
		"rumor":
			fx("spiral", dp, Color("#b07cff"), 1.2, 0.1, 26.0)
			d.stagger(field.clock, field.rng)
		"curse":
			for i in 3:
				fx("proj", vis_spot(d), Color("#a070d0"), 0.45, i * 0.07, 0.0, ap)
			fx("mist", dp, Color("#5a3a7a"), 1.6, 0.5, 24.0)
		"thunder":
			fx("bolt", vis_spot(d), Color("#a8d8ff"), 0.35, 0.15)
			fx("ring", dp, Color("#a8d8ff"), 0.5, 0.15, 22.0)
		"cheer":
			fx("heal", ap, Color("#8ff0c8"), 1.2, 0.0, 22.0)
		"guard":
			fx("ring", ap, Color("#9fc4e8"), 0.7, 0.0, 26.0)
		"lance":
			fx("ring", dp, Color("#ffd257"), 0.55, 0.0, 26.0)
			fx("dust", dp, Color("#b8a07a"), 0.9, 0.0, 18.0)
			d.stagger(field.clock, field.rng)
		"ambush":
			var sp := vis_spot(d)
			fx("mist", sp, Color("#1a1424"), 1.0, 0.0, 16.0)
			fx("slash", sp, Color("#c9b8ff"), 0.4, 0.1, 18.0, ap)
		"dagger":
			for i in 3:
				fx("proj", vis_spot(d), Color("#e8ecf2"), 0.4, i * 0.05, 0.0, ap)
			fx("burst", dp, Color("#ffffff"), 0.35, 0.45, 14.0)
		"thrust":
			var sp := vis_spot(d)
			fx("slash", sp, Color("#ffe6a0"), 0.35, 0.0, 16.0, ap)
			fx("burst", sp, Color("#fff2b0"), 0.3, 0.05, 12.0)
		"volley":
			for i in 6:
				fx("proj", vis_spot(d), Color("#e8dcc0"), 0.5, i * 0.04, 0.0, ap)


## 고유기 —— 기 모으기(술법은 빛고리, 무장은 흙먼지) 뒤 delay 에 종류별로 터진다
func fx_ult_charge(a: Squad, col: Color, magic: bool, foes: Array = []) -> void:
	var ap := vis_c(a)
	if a.camp == "A" or a.tier >= 8 or Settings.cam_fx >= 2:      # 적게 모드: 아군 고유기 · 적 신화 고유기만
		# 11/7 맞는 순간에 카메라가 이미 그 자리에 있도록 —— 기 모으기부터 시전자와 맞을 적을 함께 담는다
		var pts := [ap]
		for k in foes:
			if field.squads.has(k):
				pts.append(vis_c(field.squads[k]))
		var cen := Vector2.ZERO
		for q in pts:
			cen += q
		cen /= pts.size()
		focus(cen.lerp(ap, 0.25) if pts.size() > 1 else ap, 1.5 if pts.size() > 2 else 1.8, 3.4, 4)
	# 명세 3단계 '예고': 화면 가장자리 비네트 + 시전자 둘레 고리가 조여든다
	fx("vignette", ap, col, 2.6, 0.0, 0.0)
	fx("inring", ap, col, 2.2, 0.0, 90.0)
	fx("inring", ap, col, 2.2, 0.6, 70.0)
	if magic:
		fx("ring", ap, col, 0.9, 0.0, 40.0)
		fx("ring", ap, col, 0.9, 0.25, 30.0)
	else:
		fx("dust", ap, Color("#b8a07a"), 0.9, 0.0, 26.0)
		fx("ring", ap, col, 0.5, 0.0, 22.0)


func fx_ult(vfx: String, a: Squad, foes: Array, allies: Array, col: Color) -> void:
	var ap := vis_c(a) if a else Vector2.ZERO
	var ds := []
	for k in foes:
		if field.squads.has(k):
			ds.append(field.squads[k])
	if not ds.is_empty():      # 맞는 쪽으로 카메라를 옮기고 흔든다
		var cen := Vector2.ZERO
		for d: Squad in ds:
			cen += vis_c(d)
		if a == null or a.camp == "A" or a.tier >= 8 or Settings.cam_fx >= 2:
			focus(cen / ds.size(), 1.7 if ds.size() > 2 else 2.0, 2.2, 4)      # 11/6 사용자: 고유기가 맞는 순간으로 카메라 (기 모으기보다 우선)
		shake((9.0 if vfx in ["roar", "charge", "thunder", "whirlwind", "firestorm"] else 6.0) * (1.0 if Settings.cam_fx >= 2 else 0.6))
	# 명세 3단계 '폭발': 한 프레임 강한 섬광, 연출은 화면 1/3 크기, 맞는 부대 전원이 앞줄부터 밀린다, 땅에 흔적 5초
	if not ds.is_empty() and view != null and view.hud != null:
		view.hud.flash(col, true)
	for d: Squad in ds:
		d.knock_wave(field.clock, field.rng)
	for i in ds.size():
		var d: Squad = ds[i]
		var dp := vis_c(d)
		fx("scar", dp, Color(0.1, 0.08, 0.06), 5.0, 0.3, 46.0)
		match vfx:
			"slash":
				for j in 5:
					fx("slash", vis_spot(d), col, 0.75, j * 0.1, 80.0, ap)
				fx("burst", dp, col, 0.5, 0.0, 90.0)
				fx("shock", dp, col, 0.6, 0.0, 110.0)
			"charge":
				for j in 10:
					fx("dust", ap.lerp(dp, (j + 1) / 11.0), Color("#b8a07a"), 1.1, j * 0.03, 28.0)
				fx("shock", dp, col, 0.7, 0.2, 130.0)
				fx("burst", dp, Color("#fff2b0"), 0.4, 0.2, 60.0)
			"firestorm":      # 11/7 사용자 '주유 적벽대화처럼 눈에 띄게' —— 불덩이가 날아가 꽂히고, 불벽이 적진을 휩쓸고, 불바다가 남는다
				for j in 4:
					fx("fireball", vis_spot(d), Color("#ff7a2a"), 0.7, j * 0.09, 26.0, ap + a.right() * _frng.randf_range(-40, 40) if a else ap)
				fx("firewall", dp, Color("#ff6a20"), 2.2, 0.55, 150.0, ap)
				for j in 10:
					fx("fire", vis_spot(d) + Vector2(_frng.randf_range(-30, 30), _frng.randf_range(-30, 30)), Color("#ff7a2a"), 7.0, 0.6 + j * 0.06, 26.0)
				fx("pillar", dp, Color("#ff8a3c"), 1.2, 0.6, 200.0)
				fx("shock", dp, Color("#ffb060"), 0.8, 0.6, 180.0)
				fx("scar", dp, Color(0.12, 0.05, 0.02), 8.0, 0.8, 90.0)
			"thunder":        # 하늘이 어두워지고 굵은 낙뢰가 잇달아 —— 맞은 자리마다 충격 고리
				for j in 6:
					fx("bigbolt", vis_spot(d), col, 0.85, j * 0.14, 0.0)
				for j in 8:
					fx("bolt", vis_spot(d), col, 0.4, 0.1 + j * 0.08)
				fx("shock", dp, col, 0.7, 0.0, 170.0)
				fx("scar", dp, Color(0.05, 0.08, 0.15), 6.0, 0.2, 80.0)
			"poison":         # 짙은 독안개가 적진을 덮고 오래 머문다
				for j in 10:
					fx("mist", vis_spot(d) + Vector2(_frng.randf_range(-40, 40), _frng.randf_range(-40, 40)), col, 4.0, j * 0.25, 55.0)
				fx("shock", dp, col, 0.8, 0.0, 150.0)
			"illusion":       # 보랏빛 소용돌이가 적진을 감고 적이 비틀거린다
				fx("spiral", dp, col, 2.4, 0.0, 120.0)
				fx("spiral", dp, col.lightened(0.3), 2.0, 0.3, 80.0)
				fx("shock", dp, col, 0.8, 0.0, 150.0)
				d.stagger(field.clock, field.rng)
			"shadow":         # 검은 연기가 터지고 사방에서 검기가 번뜩인다
				fx("mist", dp, Color("#1a1424"), 1.6, i * 0.14, 70.0)
				for j in 6:
					fx("slash", vis_spot(d), col if j % 2 == 0 else col.lightened(0.3), 0.45, i * 0.14 + j * 0.07, 70.0, dp + Vector2(cos(j * 1.05), sin(j * 1.05)) * 80.0)
			"arrowstorm":     # 하늘을 덮는 화살비
				for j in 26:
					fx("proj", vis_spot(d) + Vector2(_frng.randf_range(-30, 30), _frng.randf_range(-30, 30)), col, 0.6, j * 0.025, 0.0, ap + a.right() * _frng.randf_range(-60, 60) if a else ap)
				fx("burst", dp, col, 0.5, 0.6, 90.0)
				fx("shock", dp, col, 0.6, 0.6, 140.0)
			"roar", "whirlwind":      # 큰 충격파가 두 겹으로 퍼지고 흙먼지가 인다
				fx("shock", dp, col, 0.8, 0.0, 200.0)
				fx("shock", dp, col, 0.8, 0.2, 140.0)
				fx("burst", dp, col, 0.5, 0.0, 100.0)
				for j in 5:
					fx("dust", vis_spot(d), Color("#b8a07a"), 1.2, j * 0.05, 50.0)
			_:
				fx("shock", dp, col, 0.6, 0.0, 110.0)
				fx("burst", dp, col, 0.5, 0.0, 70.0)
	if vfx in ["aura", "heal"]:
		for k in allies:
			if field.squads.has(k):
				var q := vis_c(field.squads[k])
				fx("pillar_c", q, col, 1.4, 0.0, 120.0)
				fx("heal", q, col, 1.8, 0.0, 60.0)
				fx("shock", q, col, 0.9, 0.0, 110.0)
	# 화면 전체가 고유기 색으로 잠깐 물든다 (섬광이 아니라 천천히 물들었다 걷힌다)
	if vfx in ["firestorm", "thunder", "poison", "illusion", "shadow"]:
		fx("tint", Vector2.ZERO, {"firestorm": Color("#ff5a1a"), "thunder": Color("#1a2a55"), "poison": Color("#2f5a1a"), "illusion": Color("#4a2a6a"), "shadow": Color("#0a0610")}[vfx], 2.0, 0.0, 0.0)


## 화면 위 타원 (전장의 원을 지도 배율로)
func _ell(ci: CanvasItem, c: Vector2, rad: float, col: Color, width := 0.0) -> void:
	var pts := PackedVector2Array()
	for k in 24:
		var a := TAU * k / 24.0
		pts.append(map(c + Vector2(cos(a), sin(a)) * rad))
	if width <= 0.0:
		ci.draw_colored_polygon(pts, col)
	else:
		pts.append(pts[0])
		ci.draw_polyline(pts, col, width)


## 1단계-4: 군기 —— 부대 뒤 가운데에 세력색 깃발(전설 이상 둘). 바람에 흔들리는 사인 파형. 11/6에 뺀 성씨 깃발 대신 글자 없이 작게
func _draw_flags(ci: CanvasItem) -> void:
	var zs := clampf(_scale, 0.6, 1.8)
	for sq: Squad in field.order:
		if not sq.alive or sq.state == "gone" or sq.state == "flee" or sq.tier <= 2:
			continue
		var team := TEAM_A if sq.camp == "A" else TEAM_B
		var fac_c: Color = DB.fac_color(sq.row.fac) if "fac" in sq.row else team
		var n := 2 if sq.tier >= 5 else 1
		for j in n:
			var at: Vector2 = sq.pos - sq.fwd * (sq.hd() + 6.0) + sq.right() * ((j - (n - 1) * 0.5) * 14.0)
			var base := map(at)
			var h := 26.0 * zs
			var top := base + Vector2(0, -h)
			ci.draw_line(base, top, Color(0.25, 0.2, 0.15, 0.9), 1.5 * zs)
			var w := 11.0 * zs
			var wave := sin(_t * 4.0 + sq.row.slot * 0.7 + j) * 2.5 * zs
			var pts := PackedVector2Array([top, top + Vector2(w, 3.0 * zs + wave), top + Vector2(0, 9.0 * zs)])
			ci.draw_colored_polygon(pts, Color(fac_c.lerp(team, 0.45), 0.95))
			ci.draw_polyline(pts + PackedVector2Array([top]), Color(0, 0, 0, 0.35), 1.0)


func _draw_fx(ci: CanvasItem) -> void:
	_draw_flags(ci)
	var now := field.clock
	var keep := []
	var zs := clampf(_scale, 0.6, 1.8)
	for e in _fx:
		var u: float = (now - e.t0) / e.life
		if u >= 1.0:
			continue
		keep.append(e)
		if u < 0.0:
			continue
		var col: Color = e.col
		var p: Vector2 = e.p
		var sp := map(p)
		match e.k:
			"vignette":  # 고유기 예고 —— 화면 가장자리가 어두워지고 색이 물든다 (명세 3단계)
				var al := sin(PI * u) * 0.55
				var r := Rect2(Vector2.ZERO, size)
				var th := size.y * 0.22
				ci.draw_rect(Rect2(0, 0, size.x, th), Color(col.darkened(0.6), al), true)
				ci.draw_rect(Rect2(0, size.y - th, size.x, th), Color(col.darkened(0.6), al), true)
				ci.draw_rect(Rect2(0, 0, size.x * 0.12, size.y), Color(col.darkened(0.6), al * 0.8), true)
				ci.draw_rect(Rect2(size.x * 0.88, 0, size.x * 0.12, size.y), Color(col.darkened(0.6), al * 0.8), true)
			"inring":    # 조여드는 고리 (예고)
				_ell(ci, p, e.r * (1.0 - 0.85 * ease(u, 0.6)), Color(col, 0.9 * u), 2.0 + 2.0 * u)
			"shock":     # 충격파 —— 두 겹 고리가 크게 퍼진다 (폭발)
				_ell(ci, p, e.r * ease(u, 0.3), Color(col, 0.8 * (1.0 - u)), 5.0 * (1.0 - u) + 1.5)
				_ell(ci, p, e.r * 0.7 * ease(u, 0.3), Color(1, 1, 1, 0.6 * (1.0 - u)), 2.0)
			"fireball":  # 날아가 꽂히는 불덩이 —— 꼬리를 끌며 포물선
				var from := map(e.q)
				var at := from.lerp(sp, u) + Vector2(0, -sin(PI * u) * 90.0 * zs)
				for j in 6:
					var bu := maxf(0.0, u - j * 0.035)
					var bp := from.lerp(sp, bu) + Vector2(0, -sin(PI * bu) * 90.0 * zs)
					ci.draw_circle(bp, e.r * zs * 0.5 * (1.0 - j * 0.14), Color(1.0, 0.45 + j * 0.05, 0.1, 0.6 * (1.0 - j * 0.15)))
				ci.draw_circle(at, e.r * zs * 0.55, Color(1.0, 0.85, 0.4, 0.95))
			"firewall":  # 불벽 —— 시전자 쪽에서 적진을 넘어 휩쓸고 지나간다
				var dir: Vector2 = (p - e.q).normalized() if e.q != p else Vector2.RIGHT
				var perp := Vector2(-dir.y, dir.x)
				var front: Vector2 = p - dir * e.r + dir * e.r * 2.0 * ease(u, 0.6)
				var al := clampf(u * 6.0, 0, 1) * clampf((1.0 - u) * 3.0, 0, 1)
				pass      # 불벽 불꽃은 더하기 층 스프라이트로
			"bigbolt":   # 굵은 낙뢰 —— 하늘 끝에서 꺾이며 떨어지고, 맞은 자리에 빛 웅덩이
				var top := sp + Vector2(sin(e.s) * 40.0, -320.0 * zs)      # 맞는 자리 위 높은 곳에서 (화면 맨 위가 아니라 —— 위쪽 적에게 떨어지면 HUD 밑에 숨었다)
				var pts := PackedVector2Array([top])
				for j in range(1, 9):
					pts.append(top.lerp(sp, j / 9.0) + Vector2(sin(e.s * 2.3 + j * 1.9) * 22.0 * zs, 0))
				pts.append(sp)
				var al := 1.0 - u
				ci.draw_polyline(pts, Color(col, 0.3 * al), 16.0 * zs)
				ci.draw_polyline(pts, Color(col.lightened(0.4), 0.7 * al), 6.0 * zs)
				ci.draw_polyline(pts, Color(1, 1, 1, al), 2.5)
				_ell(ci, p, 30.0 * (1.0 + u), Color(col, 0.45 * al))
			"pillar_c":  # 빛기둥 (회복 · 위세) —— 땅에서 솟는 옅은 기둥
				var al := sin(PI * u)
				var w: float = e.r * zs * 0.3
				var h: float = e.r * zs * 2.2 * ease(clampf(u * 2.0, 0, 1), 0.4)
				ci.draw_rect(Rect2(sp + Vector2(-w, -h), Vector2(w * 2.0, h)), Color(col, 0.22 * al))
				ci.draw_rect(Rect2(sp + Vector2(-w * 0.35, -h), Vector2(w * 0.7, h)), Color(col.lightened(0.5), 0.35 * al))
			"tint":      # 화면 전체가 고유기 색으로 잠깐 물든다
				ci.draw_rect(Rect2(Vector2.ZERO, size), Color(col, 0.28 * sin(PI * minf(1.0, u * 1.3))))
			"pillar":    # 불기둥 (화염 고유기)
				var al := sin(PI * u)
				var w: float = e.r * zs * 0.35 * (0.6 + 0.4 * u)
				var h: float = e.r * zs * 1.6 * ease(clampf(u * 1.6, 0, 1), 0.4)
				pass      # 11/7 불꽃 그림은 더하기 층(_draw_fx_add) 스프라이트로
			"scar":      # 땅 흔적 —— 검흔 · 그을음, 천천히 바랜다 (여운)
				_spr_at(ci, "scorch_02", sp, e.r * zs * 2.2, Color(0, 0, 0, 0.5 * (1.0 - u)), e.s)
			"ring":      # 퍼지는 고리
				_ell(ci, p, e.r * (0.3 + 0.7 * ease(u, 0.4)), Color(col, 0.75 * (1.0 - u)), 2.5)
			"burst":     # 사방으로 튀는 획
				for j in 8:
					var a: float = TAU * j / 8.0 + e.s
					var d0 := Vector2(cos(a), sin(a) * 0.8)
					var l0: float = e.r * zs * (0.3 + 0.7 * u)
					ci.draw_line(sp + d0 * l0 * 0.5, sp + d0 * l0, Color(col, 1.0 - u), 2.0)
			"bolt":      # 하늘에서 내리꽂는 번개 —— 짧게, 화면 섬광 없이
				var top := sp + Vector2(sin(e.s) * 20.0, -170.0 * zs)
				var pts := PackedVector2Array([top])
				for j in range(1, 7):
					pts.append(top.lerp(sp, j / 7.0) + Vector2(sin(e.s * 3.1 + j * 2.3) * 9.0 * zs, 0))
				pts.append(sp)
				var al := 1.0 - u
				ci.draw_polyline(pts, Color(col, 0.35 * al), 6.0)
				ci.draw_polyline(pts, Color(1, 1, 1, 0.9 * al), 1.8)
				_ell(ci, p, 10.0 * (1.0 + u), Color(col, 0.35 * al))
			"fire":      # 땅에 붙은 불 —— 그을음 위에 너울대는 불꽃 셋
				var al := clampf(u * 8.0, 0, 1) * clampf((1.0 - u) * 5.0, 0, 1)
				_spr_at(ci, "scorch_01", sp, e.r * zs * 2.4, Color(0, 0, 0, 0.45 * al), e.s)      # 그을음 (불꽃은 더하기 층)
			"mist":      # 피어오르는 안개
				var al := sin(PI * u)
				for j in 3:
					var o: Vector2 = Vector2(cos(e.s + j * 1.7), sin(e.s + j * 1.7)) * e.r * 0.45
					_spr_at(ci, ["smoke_01", "smoke_04", "smoke_07"][j], map(p + o) + Vector2(u * 8.0, -u * 10.0), e.r * zs * (1.2 + 0.6 * u), Color(col, 0.42 * al), e.s + j + u * 0.6)
			"slash":     # 검기 —— 날아온 쪽에 수직으로 그어지는 호
				var dir: Vector2 = (sp - map(e.q)).normalized() if e.q != Vector2.ZERO else Vector2.RIGHT
				var rad: float = e.r * zs
				var a0 := dir.angle() - PI * 0.4
				var a1 := a0 + PI * 0.8 * ease(clampf(u * 2.5, 0, 1), 0.4)
				ci.draw_arc(sp - dir * rad * 0.6, rad, a0, a1, 16, Color(col, 0.9 * (1.0 - u)), 3.5)
				ci.draw_arc(sp - dir * rad * 0.6, rad, a0, a1, 16, Color(1, 1, 1, 0.7 * (1.0 - u)), 1.2)
			"proj":      # 날아가는 화살 · 부적 · 단도 —— 짧은 꼬리
				var from := map(e.q)
				var at := from.lerp(sp, u)
				var back := from.lerp(sp, maxf(0.0, u - 0.18))
				ci.draw_line(back, at, Color(col, 0.55), 2.0)
				ci.draw_circle(at, 2.6 * zs, col)
			"spiral":    # 소용돌이 (혼란)
				for j in 3:
					var a0: float = _t * 4.0 + j * TAU / 3.0
					ci.draw_arc(sp, e.r * zs * (0.4 + 0.25 * j) * (1.0 - u * 0.3), a0, a0 + 2.0, 12, Color(col, 0.7 * sin(PI * u)), 2.0)
			"dust":      # 흙먼지
				for j in 3:
					var o: Vector2 = Vector2(cos(e.s + j * 2.1), sin(e.s + j * 2.1)) * e.r * 0.4
					_ell(ci, p + o, e.r * (0.4 + 0.6 * u), Color(col, 0.3 * (1.0 - u)))
			"heal":      # 떠오르는 초록 십자
				for j in 4:
					var c := sp + Vector2(sin(e.s + j * 1.9) * e.r * zs * 0.8, -u * 30.0 * zs - j * 6.0)
					var hc := Color(col, sin(PI * u))
					ci.draw_line(c + Vector2(-4, 0), c + Vector2(4, 0), hc, 2.0)
					ci.draw_line(c + Vector2(0, -4), c + Vector2(0, 4), hc, 2.0)
	_fx = keep


# ───────── 전황 읽기 (11/6 탑뷰 강점: 진형 · 사거리 · 전술 화살표) ─────────
# 모두 그리기만 한다 —— 판정 · 결정성과 무관. 위치는 Squad(재생 결과), 진형은 res.aForm / bForm.

const BOON_COL := Color("#E8C25A")
const INTRO_T := 4.0            # 전투 시작 뒤 진형 윤곽 · 이름을 보여 주는 시간
var _form := {}                 # "A"/"B" -> 진형 키
var _boon := {}                 # 부대 key -> true (진형 우대를 받는 병종)
var _intro_t0 := 0.0


func _setup_tac() -> void:
	_form.clear()
	_boon.clear()
	var res: Dictionary = view.res if view != null and view.res is Dictionary else {}
	_form["A"] = str(res.get("aForm", ""))
	_form["B"] = str(res.get("bForm", ""))
	for sq: Squad in field.order:
		var bn = DB.D.FORMBOON.get(_form.get(sq.camp, ""))
		if bn != null and bn.tags.has(sq.tag):
			_boon[sq.key] = true
	_intro_t0 = field.clock
	_ensure_fx_layer()
	_label_layer.visible = true


func _intro_alpha() -> float:
	var t := field.clock - _intro_t0
	return clampf(t / 0.35, 0, 1) * clampf((INTRO_T - t) / 0.9, 0, 1)


## 병사 아래 층 —— 진형 윤곽(시작), 사거리 부채꼴 · 책략 실(행동할 때), 전술 화살표(움직일 때)
func _draw_tac_under(ci: CanvasItem) -> void:
	var lv := tac_level()
	if lv <= 0:
		return
	# 1) 진형 윤곽 —— 같은 편 부대들을 감싸는 선 (시작 몇 초)
	var ia := _intro_alpha()
	if ia > 0.01:
		for camp in ["A", "B"]:
			var pts := PackedVector2Array()
			for sq: Squad in field.order:
				if sq.camp == camp and sq.alive:
					pts.append(map(vis_c(sq)))
			if pts.size() >= 3:
				var hull := Geometry2D.convex_hull(pts)
				var team := TEAM_A if camp == "A" else TEAM_B
				ci.draw_colored_polygon(hull, Color(team, 0.08 * ia))
				_dashed(ci, hull, Color(BOON_COL, 0.75 * ia), 2.0)
			for sq: Squad in field.order:      # 우대 받는 부대끼리 금빛으로 잇는다
				if sq.camp == camp and sq.alive and _boon.has(sq.key):
					ci.draw_circle(map(vis_c(sq)), 4.0, Color(BOON_COL, 0.9 * ia))
	var now := field.clock
	for sq: Squad in field.order:
		if not sq.alive or sq.state == "gone":
			continue
		var team := TEAM_A if sq.camp == "A" else TEAM_B
		var c := vis_c(sq)
		# 2) 사거리 · 책략 —— 쏘거나 시전한 직후 1.2초
		var since := now - sq.act_t
		if lv >= 1 and since < 1.2 and sq.act_tgt != null and is_instance_valid(sq.act_tgt) and sq.act_kind in ["shoot", "cast"]:
			var tp := vis_c(sq.act_tgt)
			var al := 1.0 - since / 1.2
			if sq.act_kind == "shoot":
				if lv >= 2:
					_fan(ci, c, tp, RtBattle.bow_range, Color(team.lightened(0.3), al))
			else:
				var cc := Color("#b48cff")
				if lv >= 2:
					_fan(ci, c, tp, RtBattle.cast_range, Color(cc, al * 0.8))
				# 책략 실 —— 시전자에서 대상까지 흐르는 보랏빛 점선
				var a := map(c)
				var b := map(tp)
				var n := int(a.distance_to(b) / 16.0)
				var dc := Color(cc, 0.85 * al)
				for j in n:
					var f := fposmod(j / float(maxi(1, n)) + now * 1.4, 1.0)
					ci.draw_rect(Rect2(a.lerp(b, f) - Vector2(1.5, 1.5), Vector2(3, 3)), dc)      # 원보다 싸다 (11/6 부하)
				_ell(ci, tp, 18.0, Color(cc, 0.6 * al), 1.5)
		# 3) 전술 화살표 —— 상대에게 다가가는 중 (맞닿기 전), 패주는 뒤로 회색
		if lv < 2:
			continue
		if sq.state == "flee":
			var back := c - sq.fwd * 70.0
			_arrow(ci, map(c), map(back), Color(0.75, 0.75, 0.75, 0.35 * sq.fade), 4.0)
		elif not sq.contact and _foe_of(sq) != null and (sq.moving or sq.state == "move"):
			var tp := vis_c(_foe_of(sq))
			var d := c.distance_to(tp)
			if d > 60.0:      # 방향만 —— 끝까지 그으면 화살표가 전장을 가로질러 얽혔다 (11/6 점검)
				var a := map(c + (tp - c).normalized() * 26.0)
				var b := map(c + (tp - c).normalized() * minf(d - 24.0, 95.0))
				_arrow(ci, a, b, Color(team.lightened(0.35), 0.42), 5.0)


## 다가가는 상대 —— 재생 부대(puppet)는 ptgt, 아니면 engaged
func _foe_of(sq: Squad) -> Squad:
	if sq.engaged != null and is_instance_valid(sq.engaged) and sq.engaged.alive:
		return sq.engaged
	if sq.puppet and sq.ptgt != null and is_instance_valid(sq.ptgt) and sq.ptgt.alive:
		return sq.ptgt
	return null


## 우대 금테 —— 부대 바닥 타원 둘레 (계속)
func _boon_ring(ci: CanvasItem, pts: PackedVector2Array, sq: Squad, fade: float) -> void:
	if _boon.has(sq.key) and tac_level() >= 1:
		ci.draw_polyline(pts, Color(BOON_COL, 0.6 * fade), 1.6)      # 큰 부대는 타원이 커서 굵은 금테가 화면을 덮었다 (11/6 점검)


## 진형 이름 · 우대 효과 —— 각 편 무리 바깥(아군 아래 · 적 위)에 (시작 몇 초)
func _draw_tac_top(ci: CanvasItem) -> void:
	if tac_level() <= 0:
		return
	var ia := _intro_alpha()
	if ia <= 0.01:
		return
	for camp in ["A", "B"]:
		var fk: String = _form.get(camp, "")
		if fk == "" or not DB.FORM.has(fk):
			continue
		var lo := INF
		var hi := -INF
		var sx := 0.0
		var n := 0
		for sq: Squad in field.order:
			if sq.camp == camp and sq.alive:
				var p := map(vis_c(sq))
				lo = minf(lo, p.y)
				hi = maxf(hi, p.y)
				sx += p.x
				n += 1
		if n == 0:
			continue
		var y := minf(hi + 44.0, size.y - 30.0) if camp == "A" else maxf(lo - 52.0, 120.0)      # 위쪽 시계 · 병력 막대와 겹치지 않게
		var x := sx / n
		var nm: String = DB.FORM[fk].n
		var bn = DB.D.FORMBOON.get(fk)
		var sub := ("%s %s +%d%%" % [" · ".join(bn.tags), DB.D.STATNM.get(bn.stat, "스킬 발동"), roundi(float(bn.v) * 100)]) if bn else ""
		var fd := DB.font_display
		var w := 300.0
		var tc := Color("#a9c8f0") if camp == "A" else Color("#f0aaa2")
		# 받침 —— 부대 · 이름표 위에 겹쳐도 읽히게
		var bw: float = maxf(fd.get_string_size(nm, HORIZONTAL_ALIGNMENT_LEFT, -1, 22).x, DB.font_bold.get_string_size(sub, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x) + 28.0
		var plate := StyleBoxFlat.new()
		plate.bg_color = Color(0.04, 0.05, 0.08, 0.62 * ia)
		plate.border_color = Color(BOON_COL, 0.45 * ia)
		plate.set_border_width_all(1)
		plate.set_corner_radius_all(4)
		ci.draw_style_box(plate, Rect2(x - bw / 2, y - 24, bw, 48 if sub != "" else 30))
		ci.draw_string_outline(fd, Vector2(x - w / 2, y), nm, HORIZONTAL_ALIGNMENT_CENTER, w, 22, 6, Color(0, 0, 0, 0.75 * ia))
		ci.draw_string(fd, Vector2(x - w / 2, y), nm, HORIZONTAL_ALIGNMENT_CENTER, w, 22, Color(tc.lightened(0.3), ia))
		if sub != "":
			ci.draw_string_outline(DB.font_bold, Vector2(x - w / 2, y + 18), sub, HORIZONTAL_ALIGNMENT_CENTER, w, 12, 4, Color(0, 0, 0, 0.75 * ia))
			ci.draw_string(DB.font_bold, Vector2(x - w / 2, y + 18), sub, HORIZONTAL_ALIGNMENT_CENTER, w, 12, Color(BOON_COL, ia))


func _dashed(ci: CanvasItem, poly: PackedVector2Array, col: Color, wd: float) -> void:
	for i in poly.size() - 1:
		var a := poly[i]
		var b := poly[i + 1]
		var l := a.distance_to(b)
		var k := 0.0
		while k < l:
			ci.draw_line(a.lerp(b, k / l), a.lerp(b, minf(l, k + 8.0) / l), col, wd)
			k += 14.0


## 사거리 부채꼴 —— 대상 쪽으로 ±22°, 안은 아주 옅게 · 끝 호만 조금 진하게
func _fan(ci: CanvasItem, c: Vector2, tp: Vector2, reach: float, col: Color) -> void:
	var dir := (tp - c).normalized()
	var a0 := dir.angle() - 0.38
	var mc := map(c)
	var ex := map(c + Vector2(reach, 0)) - mc
	var ey := map(c + Vector2(0, reach)) - mc
	var pts := PackedVector2Array([mc])
	var arc := PackedVector2Array()
	for k in 9:
		var a := a0 + 0.76 * k / 8.0
		var q := mc + ex * cos(a) + ey * sin(a)
		pts.append(q)
		arc.append(q)
	ci.draw_colored_polygon(pts, Color(col, 0.07 * col.a))
	ci.draw_polyline(arc, Color(col, 0.45 * col.a), 1.5)


## 전술 화살표 —— 굵은 몸통 + 삼각 머리
func _arrow(ci: CanvasItem, a: Vector2, b: Vector2, col: Color, wd: float) -> void:
	var d := b - a
	var l := d.length()
	if l < 8.0:
		return
	var u := d / l
	var nrm := Vector2(-u.y, u.x)
	var head := minf(14.0, l * 0.4)
	ci.draw_line(a, b - u * head, col, wd)
	ci.draw_colored_polygon(PackedVector2Array([b, b - u * head + nrm * head * 0.6, b - u * head - nrm * head * 0.6]), col)


# ───────── 보는 맛 (11/6 사용자: 탑뷰로 바꾸니 보는 맛이 다 사라졌다) ─────────
# 카메라가 사건으로 다가간다(첫 격돌 · 장수 격파 · 고유기), 부딪치면 흔들리고 흙먼지가 인다.
# 번쩍임(화면 섬광 · 흰빛)은 쓰지 않는다 —— 움직임 · 먼지 · 흔들림으로.

var _focus := {}               # {c: 전장 자리, mul: 배율, until, pri}
var _base_scale := 1.0
var _jit := Vector2.ZERO       # 흔들림 (전장 px)
var _shake := 0.0
var _was_contact := {}
var _was_alive := {}
var _clashed := false
var _focus_free := 0.0


func tac_level() -> int:
	if view != null and view.speed == 0.0:
		return 2      # 일시정지 —— 다 보여 준다
	return Settings.tac_info


func _focus_on() -> bool:
	return not _focus.is_empty() and field != null and field.clock < float(_focus.until)


## 그 자리로 다가간다 —— pri 가 높은 장면이 진행 중이면 끼어들지 않는다 (고유기 3 > 격돌 2 > 격파 1)
## 11/6 사용자 "불필요한 카메라 무빙 자제": Settings.cam_fx 0 이면 다가가지 않고, 1 이면 pri 3(고유기 · 격파 중 중요한 것)만, 어떤 장면이든 3초 안에 겹치면 한 번
func focus(c: Vector2, mul: float, dur: float, pri := 1) -> void:
	if Settings.cam_fx == 0 or (Settings.cam_fx == 1 and pri < 3):
		return
	if _focus_on() and int(_focus.pri) > pri:
		return
	if field.clock < _focus_free:      # 숨 돌릴 틈 —— 카메라가 계속 튀었다 (11/6 점검)
		return
	_focus_free = field.clock + dur + 3.0
	_focus = {"c": c, "mul": mul, "until": field.clock + dur, "pri": pri}
	_want_scale = clampf(_base_scale * mul, 0.35, 4.0)
	_want_center = c


func shake(amt: float) -> void:
	_shake = maxf(_shake, amt)


func _feel_step(dt: float) -> void:
	# 다가가거나 돌아올 때는 빠르게 (DotView 의 느린 따라가기 위에 한 번 더)
	var fast := _focus_on() or absf(_scale - _want_scale) > _base_scale * 0.08
	if fast:
		var k := 1.0 - exp(-dt * 3.2)
		_scale = lerpf(_scale, _want_scale, k)
		_center = _center.lerp(_want_center, k)
	if not _focus.is_empty() and not _focus_on():
		_focus = {}
		_fit()
	# 흔들림
	_shake = maxf(0.0, _shake - dt * 22.0)
	_jit = Vector2(randf_range(-1, 1), randf_range(-1, 1)) * _shake / maxf(_scale, 0.3) if _shake > 0.05 else Vector2.ZERO
	# 부딪침 · 격파 감지
	var first := Vector2.INF
	for sq: Squad in field.order:
		var on := sq.contact and sq.alive and sq.engaged != null
		if on and not _was_contact.get(sq.key, false):
			var en: Squad = sq.engaged
			var mid: Vector2 = en.pos + sq.axis * en.edge(sq.axis)
			var cav: bool = sq.tag == "기병"
			fx("ring", mid, Color("#e8d3a0"), 0.5, 0.0, 34.0 if cav else 24.0)
			fx("dust", mid, Color("#b8a07a"), 1.1, 0.0, 30.0 if cav else 20.0)
			fx("burst", mid, Color("#ffe2a0"), 0.35, 0.0, 18.0)
			if Settings.cam_fx >= 2:
				shake(5.0 if cav else 2.5)
			if first == Vector2.INF:
				first = mid
		_was_contact[sq.key] = on
		if _was_alive.get(sq.key, true) and not sq.alive:
			var c := vis_c(sq)
			fx("ring", c, Color("#ffffff"), 0.6, 0.0, 40.0)
			fx("dust", c, Color("#8a7a62"), 1.4, 0.0, 34.0)
			shake((6.0 if sq.tier >= 4 else 3.0) * (1.0 if Settings.cam_fx >= 2 else 0.5))
			if sq.tier >= 6:      # 초월 이상 장수가 무너질 때만 다가간다 (적게 모드에서도 —— pri 3)
				focus(c, 1.6, 1.3, 3)
		_was_alive[sq.key] = sq.alive
	if first != Vector2.INF and not _clashed:
		_clashed = true
		focus(first, 1.7, 1.8, 2)      # 첫 격돌 —— 부딪치는 자리로 (보통 모드에서만)
		if Settings.cam_fx >= 2:
			shake(7.0)


func _reset_feel() -> void:
	_focus = {}
	_jit = Vector2.ZERO
	_shake = 0.0
	_was_contact.clear()
	_was_alive.clear()
	_clashed = false
	_focus_free = 0.0


# ───────── GPU 병사 (11/6 목표: 휴대폰에서도 품질이 떨어지지 않는 대군) ─────────
# War3D 가 GPU 병사 모드면(타입2 도 기본), 살아 있는 병졸은 shaders/type2_gpu.gdshader 가 부대 데이터(squad_tex)로 자리를 계산해 그린다.
# CPU 는 병사마다 위치 계산 · 버퍼 쓰기를 하지 않는다 —— 쓰러지거나 자리를 옮긴 병사만 gpu_moved 로 그 인스턴스 값을 고친다.
const GPU_FIG := 0.8            # GPU 병사 인형 크기 (장수 인형 대비)
var _gmm: MultiMeshInstance2D = null
var _gi := {}                   # Soldier -> 인스턴스 번호
var gpu_count := 0


func _build_gpu() -> void:
	if _gmm != null:
		_gmm.queue_free()
		_gmm = null
	_gi.clear()
	_dying.clear()
	gpu_count = 0
	if not field._gpu or field._sq_tex == null:
		return
	var lst := []
	for row in field.order.size():
		var sq: Squad = field.order[row]
		for sd in sq.soldiers:
			if sd != sq.general:
				lst.append([row, sd])
	if lst.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_2D
	mm.use_colors = false
	mm.use_custom_data = true
	var q := QuadMesh.new()
	q.size = Vector2(1, 1)
	mm.mesh = q
	mm.instance_count = lst.size()
	var buf := PackedFloat32Array()
	buf.resize(lst.size() * 12)
	for i in lst.size():
		var row: int = lst[i][0]
		var sd = lst[i][1]
		var b := i * 12
		buf[b] = 1.0
		buf[b + 5] = 1.0
		buf[b + 8] = float(row)
		buf[b + 9] = War3D._gslot(sd)
		buf[b + 10] = sd.gseed
		buf[b + 11] = sd.move_t
		_gi[sd] = i
	mm.buffer = buf
	_gmm = MultiMeshInstance2D.new()
	_gmm.multimesh = mm
	_gmm.texture = _fig_tex
	var gm := ShaderMaterial.new()
	gm.shader = load("res://shaders/type2_gpu.gdshader")
	gm.set_shader_parameter("squad_tex", field._sq_tex)
	gm.set_shader_parameter("tilt", TILT)
	gm.set_shader_parameter("spread", T2_SPREAD)
	gm.set_shader_parameter("team_a", TEAM_A)
	gm.set_shader_parameter("team_b", TEAM_B)
	_gmm.material = gm
	add_child(_gmm)
	move_child(_gmm, _mm.get_index())      # 바닥 위 · 장수(CPU 인형) 아래
	gpu_count = lst.size()


var _dying := {}                # 부대 key -> 쓰러지는 병사 (CPU 가 눕히며 그린다, 2초 뒤 빠진다)


func gpu_moved(sd, row: int, slot: float, seed: float, mt: float) -> void:
	if _gmm != null and _gi.has(sd):
		_gmm.multimesh.set_instance_custom_data(_gi[sd], Color(row, slot, seed, mt))
	if not sd.alive and row < field.order.size():
		var k: String = field.order[row].key
		if not _dying.has(k):
			_dying[k] = []
		if not _dying[k].has(sd):
			_dying[k].append(sd)


## 탑뷰 화살 · 부적 (War3D.volley · cast 가 넘긴다) —— 몇 발만, 병사를 고르지 않고 부대 둘레에서
func fx_volley(a: Squad, dkeys: Array, emph := false) -> void:
	if load_lv >= 2 and not emph:
		return
	var ap := vis_c(a)
	for dk in dkeys:
		var d: Squad = field.squads.get(dk)
		if d == null:
			continue
		for i in (6 if emph else 3):
			fx("proj", vis_spot(d), Color("#e8dcc0"), 0.5, i * 0.05, 0.0, ap + a.right() * _frng.randf_range(-20, 20))


func fx_cast(a: Squad, dkeys: Array, col: Color) -> void:
	if load_lv >= 2:
		return
	var ap := vis_c(a)
	for dk in dkeys:
		var d: Squad = field.squads.get(dk)
		if d != null:
			fx("proj", vis_c(d), col, 0.55, 0.0, 0.0, ap)



## 11/7 사용자 '전투 지형에 약간의 랜덤성' —— 바닥 지도만 전투마다 다르게 (판정과 무관). 같은 전투(시드)는 같은 땅
const GROUNDS := [      # [풀 어두운, 풀 밝은, 흙 얼룩] —— 초원 · 마른 들 · 늦가을 · 짙은 숲가
	[Color(0.36, 0.45, 0.27), Color(0.47, 0.55, 0.31), 0.0],
	[Color(0.45, 0.46, 0.30), Color(0.56, 0.54, 0.36), 0.6],
	[Color(0.44, 0.42, 0.26), Color(0.57, 0.50, 0.30), 0.35],
	[Color(0.29, 0.40, 0.25), Color(0.38, 0.49, 0.29), 0.1],
]
func _roll_ground() -> void:
	var r := RandomNumberGenerator.new()
	var sd = view._p.get("seed") if view != null and view.get("_p") is Dictionary else null
	r.seed = hash(str(sd) + "바닥") if sd != null else hash(str(field.order.map(func(q): return q.cid)))
	var g: Array = GROUNDS[r.randi() % GROUNDS.size()]
	var m: ShaderMaterial = _ground.material
	m.set_shader_parameter("seed_off", Vector2(r.randf_range(-4000, 4000), r.randf_range(-4000, 4000)))
	m.set_shader_parameter("grass_lo", g[0])
	m.set_shader_parameter("grass_hi", g[1])
	m.set_shader_parameter("soil_amt", float(g[2]) + r.randf_range(0.0, 0.3))
	m.set_shader_parameter("forest_amt", r.randf_range(0.42, 0.6))
	m.set_shader_parameter("forest_side", r.randf_range(220.0, 340.0))
	var side := 1.0 if r.randf() < 0.5 else -1.0
	m.set_shader_parameter("road_y", _mid_y + side * r.randf_range(260.0, 380.0) if r.randf() < 0.6 else 9999.0)
	m.set_shader_parameter("creek_y", _mid_y - side * r.randf_range(300.0, 420.0) if r.randf() < 0.4 else 9999.0)
	m.set_shader_parameter("rock_amt", r.randf_range(0.0, 1.0) if r.randf() < 0.7 else 0.0)
