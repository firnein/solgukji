extends RefCounted
## 기본 행동 연출 (11/11 사용자) —— 고유기가 없는 초반(전설 미만)에도 전장이 밋밋하지 않게, 병종마다 평타 · 돌격 · 사격 · 시전에 작은 타격 연출을 입힌다.
## 그리기만 한다 (판정 · 시뮬 · RNG 와 무관) —— 타입2 전장(Type2View)이 하나 가지고, 이벤트가 닿는 자리(War3D.clash · volley · cast, 맞닿음 감지)에서 부른다.
##
##  병종별                                 모양
##   기병   돌격 충격      맞닿는 순간 파편 부채 + (초월급부터) 땅 충격 고리 · 돌격 중 속도선 · 타격마다 작은 파편 + 먼지
##   창병   창 찌르기      찌른 쪽에서 꽂히는 밝은 선 + 되튀는 불꽃
##   도적   칼 타격(보병)  × 자 베기 자국 + 사방 불꽃
##   궁병   사격           포물선 화살 여럿 + 꼬리 + 떨어진 자리 점
##   책사 · 유생 · 술사 · 모사   시전      발밑 빛고리 + 떠오르는 빛알 · 날아가는 구슬(꼬리) + 맞은 자리 퍼짐
##
## 등급 배율은 아래 TIER 표 하나에 모았다 —— 숫자만 고치면 된다. 낮은 등급은 작고 짧고 적고 무채색, 높은 등급은 크고 많고 길고 등급색 빛.
## 고유기가 기 모으는 중 · 터지는 중(hold)에는 평타 연출을 ULT_DUCK 배로 줄인다 (고유기가 주인공).
## 모바일 · 대군: 동시에 살아 있는 낱개 수 상한 CAP, 한 프레임 새로 만드는 수 PER_FRAME, 부대마다 최소 간격 CD, 화면 밖은 만들지 않는다, 부하 단계(load_lv)가 오르면 더 줄인다.
## 그리는 동안 새 배열 · 사전을 만들지 않는다 (만들 때만 사전 하나).

const CAP := [110, 56]            # 동시에 살아 있는 낱개(파편 · 화살 · 빛알) 상한 [PC, 휴대폰]
const PER_FRAME := 5              # 한 프레임에 새로 만드는 연출 수 상한
const CD := 0.5                   # 같은 부대의 타격 연출 최소 간격 (전장 초)
const CD_RUN := 0.7               # 같은 부대의 돌격 속도선 간격
const ULT_DUCK := 0.4             # 고유기 연출 중 평타 연출 세기
const LV_MUL := [1.0, 0.85, 0.6, 0.45, 0.35]      # 부하 단계(load_lv 0~4)별 세기
const LIGHT_MUL := 0.6            # 자유 사격 · 자유 시전(제 차례 사이) 세기

## 등급(1~8)별 배율 —— [크기, 개수, 수명, 꼬리 길이, 등급색 빛 세기, 등급색 물들임]
##   크기 · 개수 · 수명 · 꼬리 : 5(희귀급 기준 1.0)를 기준으로 한 배율.  빛 : 0 이면 빛 없음.  물들임 : 0 무채색 ~ 1 등급색
const T_SZ := 0
const T_N := 1
const T_LIFE := 2
const T_TRAIL := 3
const T_GLOW := 4
const T_TINT := 5
const TIER := [
	[0.85, 0.35, 0.75, 0.55, 0.00, 0.00],      # 0 (안 쓴다 · 1 과 같게)
	[0.85, 0.35, 0.75, 0.55, 0.00, 0.00],      # 1
	[0.95, 0.45, 0.80, 0.65, 0.00, 0.00],      # 2
	[1.05, 0.55, 0.85, 0.75, 0.00, 0.05],      # 3
	[1.20, 0.70, 0.95, 0.85, 0.10, 0.20],      # 4
	[1.40, 0.85, 1.00, 1.00, 0.20, 0.35],      # 5
	[1.65, 1.00, 1.15, 1.25, 0.32, 0.50],      # 6 (전설)
	[1.95, 1.20, 1.30, 1.55, 0.45, 0.65],      # 7
	[2.30, 1.45, 1.50, 1.90, 0.60, 0.80],      # 8
]
const RING_TIER := 5              # 이 등급부터 돌격 땅 충격 고리 · 타격 번쩍 별

const K_CHARGE := 0
const K_PIKE := 1
const K_BLADE := 2
const K_HITCAV := 3
const K_ARROW := 4
const K_CGLOW := 5
const K_ORB := 6
const K_STREAK := 7

const C_STEEL := Color("#f4f6ff")
const C_SPARK := Color("#ffe9b0")
const C_SHARD := Color("#ffd98a")
const C_DUST := Color("#b8a07a")
const C_ARROW := Color("#f1e6c6")

var v                              # Type2View
var _list: Array = []              # 살아 있는 연출 {k, p, q, sd, t0, life, sz, n, col, glow, s, ...}
var _cost := 0                     # 살아 있는 낱개 수 합
var _fn := 0                       # 이번 프레임에 새로 만든 수
var _cd := {}                      # 부대 key -> 다음 타격 연출 가능 시각
var _ult_until := -1.0             # 이 시각까지 고유기 연출 중 (전장 시각)
var _r := RandomNumberGenerator.new()      # 연출 전용 난수 —— 시뮬 · War3D.rng 와 섞지 않는다


func _init(view) -> void:
	v = view
	_r.seed = 20251111


func clear() -> void:
	_list.clear()
	_cost = 0
	_fn = 0
	_cd.clear()
	_ult_until = -1.0


func live() -> bool:
	return not _list.is_empty()


## 고유기 기 모으기 · 폭발 구간 —— dur 초 동안 평타 연출을 줄인다
func hold(dur: float) -> void:
	_ult_until = maxf(_ult_until, v.field.clock + dur)


func ult_on() -> bool:
	return v.field.clock < _ult_until or (v.view != null and float(v.view.slow_t) > 0.0)


## 매 프레임 한 번 —— 끝난 것을 제자리에서 걷어 낸다 (새 배열을 만들지 않는다)
func prune() -> void:
	_fn = 0
	if _list.is_empty():
		return
	var now: float = v.field.clock
	var w := 0
	var cost := 0
	for i in _list.size():
		var e: Dictionary = _list[i]
		if now - e.t0 < e.life:
			_list[w] = e
			w += 1
			cost += e.n
	_list.resize(w)
	_cost = cost


# ───────── 만들기 ─────────

static func _h(s: float, j: int) -> float:
	return fposmod(sin(s * 12.9898 + float(j) * 78.233) * 43758.5453, 1.0)


func _tier(sq) -> int:
	return clampi(int(sq.tier), 1, 8)


## 지금 이 부대가 연출을 만들어도 되는가 —— 세기(0이면 안 만든다)를 돌려준다. at: 전장 자리
func _gate(sq, at: Vector2, light: bool, gap := CD) -> float:
	if _fn >= PER_FRAME or not sq.alive or v.size.x <= 1.0:
		return 0.0
	var sp: Vector2 = v.map(at)
	if sp.x < -40.0 or sp.y < -40.0 or sp.x > v.size.x + 40.0 or sp.y > v.size.y + 40.0:
		return 0.0                 # 화면 밖
	var now: float = v.field.clock
	var k: float = LV_MUL[mini(int(v.load_lv), LV_MUL.size() - 1)]
	var duck := ult_on()
	if duck:
		k *= ULT_DUCK
	if light:
		k *= LIGHT_MUL
	if now < float(_cd.get(sq.key, -1.0)):
		return 0.0
	_cd[sq.key] = now + gap / (ULT_DUCK if duck else 1.0)
	return k


func _col(base: Color, tier: int) -> Color:
	var tc: Color = DB.TIER[tier].c
	return base.lerp(tc.lightened(0.25), float(TIER[tier][T_TINT]))


func _sdir(at: Vector2, w: Vector2) -> Vector2:
	var d: Vector2 = v.map(at + w) - v.map(at)
	return d.normalized() if d.length() > 0.001 else Vector2.RIGHT


func _add(e: Dictionary) -> bool:
	if _cost + int(e.n) > int(CAP[1 if v._mobile() else 0]):
		return false
	_list.append(e)
	_cost += int(e.n)
	_fn += 1
	v._ensure_fx_layer()
	return true


func _base(kind: int, at: Vector2, sd: Vector2, tier: int, k: float, base_n: float, life: float, col: Color) -> Dictionary:
	var t: Array = TIER[tier]
	var n := roundi(base_n * float(t[T_N]) * k)
	if n <= 0:
		return {}
	return {"k": kind, "p": at, "q": at, "sd": sd, "t0": v.field.clock, "life": life * float(t[T_LIFE]),
		"sz": float(t[T_SZ]) * (0.5 + 0.5 * minf(1.0, k)), "n": n, "col": _col(col, tier),
		"glow": float(t[T_GLOW]) * k, "tc": DB.TIER[tier].c, "s": _r.randf() * 100.0, "tr": float(t[T_TRAIL]),
		"ring": tier >= RING_TIER and k >= 0.8, "fl": 0.0, "w0": 0.0, "w1": 0.0, "rt": Vector2.ZERO}


## 근접 타격 한 번 (War3D.clash —— 사건이 적용되는 순간)
func melee_hit(a, d, strong: bool) -> void:
	if not is_instance_valid(a) or not is_instance_valid(d):
		return
	var dir: Vector2 = a.pos - d.pos
	var l := dir.length()
	if l < 0.01:
		return
	dir /= l
	var perp := Vector2(-dir.y, dir.x)
	var at: Vector2 = d.pos + dir * d.edge(dir) + perp * _r.randf_range(-1.0, 1.0) * minf(d.hw * 0.6, 40.0)
	var k := _gate(a, at, false)
	if k <= 0.0:
		return
	if strong:
		k *= 1.25
	var t := _tier(a)
	var sd := _sdir(at, -dir)
	var e: Dictionary
	match str(a.tag):
		"기병":
			e = _base(K_HITCAV, at, sd, t, k, 4.0, 0.45, C_SHARD)
		"창병":
			e = _base(K_PIKE, at, sd, t, k, 5.0, 0.32, C_SPARK)
		"도적":
			e = _base(K_BLADE, at, sd, t, k, 5.0, 0.34, C_STEEL)
		_:
			e = _base(K_BLADE, at, sd, t, k * 0.8, 3.0, 0.3, C_STEEL)
	if not e.is_empty():
		_add(e)


## 두 부대가 처음 맞닿는 순간 (Type2View._feel_step) —— 기병은 돌격 충격, 나머지는 첫 타격
func contact(a, d, mid: Vector2) -> void:
	if a.cls == "ranged" or a.cls == "caster":
		return
	var k := _gate(a, mid, false, 0.0)
	if k <= 0.0:
		return
	var t := _tier(a)
	var sd := _sdir(mid, d.pos - a.pos)
	var e: Dictionary
	match str(a.tag):
		"기병":
			e = _base(K_CHARGE, mid, sd, t, k * 1.2, 8.0, 0.6, C_SHARD)
		"창병":
			e = _base(K_PIKE, mid, sd, t, k * 1.3, 6.0, 0.36, C_SPARK)
		_:
			e = _base(K_BLADE, mid, sd, t, k * 1.2, 5.0, 0.38, C_STEEL)
	if not e.is_empty():
		_add(e)
		_cd[a.key] = v.field.clock + CD


## 달려가는 기병 —— 속도선 (맞닿기 전, 부대마다 CD_RUN 간격)
func charge_run(a) -> void:
	var front: Vector2 = a.pos + a.fwd * (a.hd() + 2.0)
	var k := _gate_run(a, front)
	if k <= 0.0:
		return
	var t := _tier(a)
	var e := _base(K_STREAK, front, _sdir(front, a.fwd), t, k, 4.0, 0.4, Color("#e8dcc0"))
	if e.is_empty():
		return
	e.rt = a.right() * (3.2 * float(TIER[t][T_SZ]) / maxf(0.001, v._scale))      # 줄 사이 간격 (전장 px)
	e.fl = minf(a.hw, 60.0)
	_add(e)


func _gate_run(sq, at: Vector2) -> float:
	if _fn >= PER_FRAME or not sq.alive:
		return 0.0
	var key := "r" + str(sq.key)
	var now: float = v.field.clock
	if now < float(_cd.get(key, -1.0)):
		return 0.0
	var sp: Vector2 = v.map(at)
	if sp.x < -40.0 or sp.y < -40.0 or sp.x > v.size.x + 40.0 or sp.y > v.size.y + 40.0:
		return 0.0
	var k: float = LV_MUL[mini(int(v.load_lv), LV_MUL.size() - 1)]
	var duck := ult_on()
	if duck:
		k *= ULT_DUCK
	_cd[key] = now + CD_RUN / (ULT_DUCK if duck else 1.0)
	return k * 0.7


## 궁병 사격 (War3D.volley) —— 한 번에 화살 몇 발을 하나로 묶어 만든다
func volley(a, d, light: bool, emph: bool) -> void:
	var gap := 0.35 if emph else (CD * 1.3 if light else CD * 0.8)
	var k := _gate(a, a.pos, light, gap)
	if k <= 0.0:
		return
	if emph:
		k *= 1.4
	var t := _tier(a)
	var dist: float = a.pos.distance_to(d.pos)
	var e := _base(K_ARROW, a.pos, _sdir(a.pos, d.pos - a.pos), t, k, 4.0, 0.75 + dist / 700.0, C_ARROW)
	if e.is_empty():
		return
	e.q = d.pos
	e.fl = 0.42 + dist / 900.0               # 비행 시간
	e.life = 0.3 + e.fl + 0.25               # 발사 시차 + 비행 + 떨어진 점
	e.w0 = minf(a.hw, 70.0)
	e.w1 = minf(d.hw, 70.0)
	e.rt = a.right()
	_add(e)


## 책략 시전 (War3D.cast) —— 시전자 발밑 빛고리 + 구슬
func cast(a, d, col: Color, light: bool) -> void:
	var k := _gate(a, a.pos, light, CD * 1.2)
	if k <= 0.0:
		return
	var t := _tier(a)
	var c := col if col.a > 0.0 else Color("#c9a2ff")
	var g := _base(K_CGLOW, a.pos, Vector2.RIGHT, t, k, 4.0, 0.75, c)
	if not g.is_empty():
		_add(g)
	var dist: float = a.pos.distance_to(d.pos)
	var o := _base(K_ORB, a.pos, _sdir(a.pos, d.pos - a.pos), t, k, 3.0, 0.7, c)
	if o.is_empty():
		return
	o.q = d.pos
	o.fl = 0.4 + dist / 800.0
	o.life = o.fl + 0.35
	o.w1 = minf(d.hw, 60.0)
	o.rt = a.right()
	_add(o)


# ───────── 그리기 ─────────

func draw(ci: CanvasItem, add: bool) -> void:
	if _list.is_empty():
		return
	var now: float = v.field.clock
	var zs := clampf(float(v._scale), 0.8, 1.8)
	for e in _list:
		var u: float = (now - e.t0) / e.life
		if u < 0.0 or u >= 1.0:
			continue
		match int(e.k):
			K_CHARGE:
				_d_charge(ci, add, e, u, zs)
			K_PIKE:
				_d_pike(ci, add, e, u, zs)
			K_BLADE:
				_d_blade(ci, add, e, u, zs)
			K_HITCAV:
				_d_hitcav(ci, add, e, u, zs)
			K_ARROW:
				_d_arrow(ci, add, e, now, zs)
			K_CGLOW:
				_d_cglow(ci, add, e, u, zs)
			K_ORB:
				_d_orb(ci, add, e, now, zs)
			K_STREAK:
				_d_streak(ci, add, e, u, zs)


## 등급색 바닥 빛 + (초월급부터) 번쩍 별
func _glow(ci: CanvasItem, e: Dictionary, sp: Vector2, rad: float, al: float) -> void:
	if float(e.glow) > 0.01 and int(v.load_lv) < 3:
		v._spr_at(ci, "light_02", sp, rad, Color(e.tc, float(e.glow) * al))


func _shards(ci: CanvasItem, e: Dictionary, sp: Vector2, eu: float, u: float, zs: float, cone: float, center: float, r0: float, r1: float, wd: float) -> void:
	var sz: float = e.sz * zs
	var col: Color = e.col
	var core := Color(col.lightened(0.45), 1.0 - u)
	for j in int(e.n):
		var a: float = center + (_h(e.s, j) - 0.5) * cone
		var d := Vector2(cos(a), sin(a) * 0.75)
		var rr: float = (0.6 + 0.4 * _h(e.s, j + 31))
		ci.draw_line(sp + d * sz * (r0 + 8.0 * eu) * rr, sp + d * sz * (r0 + (r1 - r0) * 1.4 * eu) * rr, core, maxf(1.2, wd * sz * 1.3))


func _d_charge(ci: CanvasItem, add: bool, e: Dictionary, u: float, zs: float) -> void:
	var sp: Vector2 = v.map(e.p)
	var sz: float = e.sz * zs
	var eu := 1.0 - (1.0 - u) * (1.0 - u)
	if not add:
		var dc := Color(C_DUST.lerp(e.tc, 0.15), 0.26 * (1.0 - u))
		for j in 3:
			var o := Vector2(cos(e.s + j * 2.1), sin(e.s + j * 2.1) * 0.6) * sz * 9.0 * eu
			ci.draw_circle(sp + o, sz * (5.0 + 10.0 * eu), dc)
		return
	_glow(ci, e, sp, sz * 70.0 * (0.6 + 0.6 * u), 1.0 - u)
	_shards(ci, e, sp, eu, u, zs, TAU, e.s, 6.0, 22.0, 1.3)
	if e.ring:
		ci.draw_set_transform(sp, 0.0, Vector2(1.0, 0.6))
		ci.draw_arc(Vector2.ZERO, sz * (12.0 + 38.0 * eu), 0.0, TAU, 20, Color(e.col, 0.55 * (1.0 - u)), 2.0)
		ci.draw_set_transform(Vector2.ZERO)
		if u < 0.35:
			v._spr_at(ci, "star_06", sp, sz * 34.0, Color(1, 1, 1, 0.8 * (1.0 - u / 0.35)), e.s)


func _d_hitcav(ci: CanvasItem, add: bool, e: Dictionary, u: float, zs: float) -> void:
	var sp: Vector2 = v.map(e.p)
	var sz: float = e.sz * zs
	var eu := 1.0 - (1.0 - u) * (1.0 - u)
	if not add:
		ci.draw_circle(sp + Vector2(0, sz * 2.0), sz * (5.0 + 9.0 * eu), Color(C_DUST, 0.24 * (1.0 - u)))
		return
	_glow(ci, e, sp, sz * 46.0 * (0.6 + 0.5 * u), 1.0 - u)
	var sd: Vector2 = e.sd
	_shards(ci, e, sp, eu, u, zs, 2.2, sd.angle(), 4.0, 20.0, 1.2)


func _d_pike(ci: CanvasItem, add: bool, e: Dictionary, u: float, zs: float) -> void:
	if not add:
		return
	var sp: Vector2 = v.map(e.p)
	var sz: float = e.sz * zs
	var eu := 1.0 - (1.0 - u) * (1.0 - u)
	var sd: Vector2 = e.sd
	var col: Color = e.col
	_glow(ci, e, sp, sz * 40.0, 1.0 - u)
	var ln := sz * (20.0 + 14.0 * float(e.tr) * 0.5)
	ci.draw_line(sp - sd * ln * (1.0 - u * 0.8), sp, Color(col, 0.55 * (1.0 - u)), maxf(1.0, 3.0 * sz))
	ci.draw_line(sp - sd * ln * 0.7 * (1.0 - u), sp, Color(1, 1, 1, 0.9 * (1.0 - u)), maxf(1.0, 1.4 * sz))
	ci.draw_circle(sp, sz * 2.6 * (1.0 - u * 0.5), Color(1, 1, 1, 0.9 * (1.0 - u)))
	_shards(ci, e, sp, eu, u, zs, 2.0, (-sd).angle(), 3.0, 16.0, 1.1)
	if e.ring and u < 0.4:
		v._spr_at(ci, "star_06", sp, sz * 26.0, Color(1, 1, 1, 0.7 * (1.0 - u / 0.4)), e.s)


func _d_blade(ci: CanvasItem, add: bool, e: Dictionary, u: float, zs: float) -> void:
	if not add:
		return
	var sp: Vector2 = v.map(e.p)
	var sz: float = e.sz * zs
	var eu := 1.0 - (1.0 - u) * (1.0 - u)
	var col: Color = e.col
	_glow(ci, e, sp, sz * 40.0, 1.0 - u)
	var a1: float = -0.7 + (_h(e.s, 3) - 0.5) * 0.6
	var l := sz * (11.0 + 5.0 * eu)
	var al := 1.0 - u * u
	for q in 2:
		var d := Vector2(cos(a1 + q * 1.75), sin(a1 + q * 1.75) * 0.8) * l
		ci.draw_line(sp - d, sp + d, Color(col, 0.7 * al), maxf(1.0, 2.6 * sz))
		ci.draw_line(sp - d * 0.8, sp + d * 0.8, Color(1, 1, 1, 0.95 * al), maxf(1.0, 1.1 * sz))
	_shards(ci, e, sp, eu, u, zs, TAU, e.s, 4.0, 15.0, 1.0)
	if e.ring and u < 0.4:
		v._spr_at(ci, "star_06", sp, sz * 24.0, Color(1, 1, 1, 0.7 * (1.0 - u / 0.4)), e.s)


func _d_streak(ci: CanvasItem, add: bool, e: Dictionary, u: float, zs: float) -> void:
	if not add:
		return
	var sz: float = e.sz * zs
	var sd: Vector2 = e.sd
	var n := int(e.n)
	var rt: Vector2 = e.rt
	var ln := sz * 22.0 * float(e.tr)
	var col: Color = e.col
	for j in n:
		var off: Vector2 = rt * ((float(j) - (n - 1) * 0.5) + (_h(e.s, j) - 0.5) * 0.8) * (e.fl / maxf(1.0, n * 2.0)) * 0.3
		var p0: Vector2 = v.map(e.p + off) - sd * sz * 4.0 * (0.5 + u)
		ci.draw_line(p0, p0 - sd * ln * (0.6 + 0.4 * _h(e.s, j + 9)), Color(col, 0.38 * (1.0 - u)), maxf(1.0, 1.3 * sz))


## 포물선 위 자리 (화면) —— 시작 S · 끝 E · 높이 h
static func _arc(s: Vector2, t: Vector2, h: float, u: float) -> Vector2:
	return s.lerp(t, u) + Vector2(0.0, -sin(PI * u) * h)


func _d_arrow(ci: CanvasItem, add: bool, e: Dictionary, now: float, zs: float) -> void:
	if not add:
		return
	var sz: float = e.sz * zs
	var rt: Vector2 = e.rt
	var s0: Vector2 = e.p
	var s1: Vector2 = e.q
	var col: Color = e.col
	var tr: float = 0.12 * float(e.tr)
	for j in int(e.n):
		var dl := _h(e.s, j + 5) * 0.28
		var uj: float = (now - e.t0 - dl) / e.fl
		if uj <= 0.0:
			continue
		var S: Vector2 = v.map(s0 + rt * (_h(e.s, j) - 0.5) * e.w0 * 2.0)
		var E: Vector2 = v.map(s1 + rt * (_h(e.s, j + 17) - 0.5) * e.w1 * 2.0)
		if uj < 1.0:
			var h := clampf(S.distance_to(E) * 0.2, 8.0, 52.0)
			var p0 := _arc(S, E, h, uj)
			var p1 := _arc(S, E, h, maxf(0.0, uj - tr * 0.4))
			var p2 := _arc(S, E, h, maxf(0.0, uj - tr * 0.8))
			var p3 := _arc(S, E, h, maxf(0.0, uj - tr * 1.3))
			var w := maxf(1.0, 1.5 * sz)
			ci.draw_line(p2, p3, Color(col, 0.22), w * 0.8)
			ci.draw_line(p1, p2, Color(col, 0.5), w)
			ci.draw_line(p0, p1, Color(col.lightened(0.4), 0.95), w * 1.2)
			ci.draw_circle(p0, 1.3 * sz + 0.4, Color(1, 1, 1, 0.9))
		else:
			var lu: float = (uj - 1.0) * float(e.fl) / 0.22
			if lu < 1.0:
				var a := Color(col.lightened(0.3), 0.8 * (1.0 - lu))
				for q in 3:
					var d := Vector2(cos(q * 2.1 + e.s + j), sin(q * 2.1 + e.s + j) * 0.7) * sz * (3.0 + 5.0 * lu)
					ci.draw_line(E + d * 0.4, E + d, a, 1.0)
				if float(e.glow) > 0.01 and lu < 0.5:
					ci.draw_circle(E, sz * 4.0, Color(e.tc, float(e.glow) * 0.5 * (1.0 - lu * 2.0)))


func _d_cglow(ci: CanvasItem, add: bool, e: Dictionary, u: float, zs: float) -> void:
	if not add:
		return
	var sp: Vector2 = v.map(e.p)
	var sz: float = e.sz * zs
	var col: Color = e.col
	var eu := 1.0 - (1.0 - u) * (1.0 - u)
	var al := sin(PI * u)
	_glow(ci, e, sp, sz * 60.0, al)
	ci.draw_set_transform(sp, 0.0, Vector2(1.0, 0.55))
	ci.draw_arc(Vector2.ZERO, sz * (10.0 + 18.0 * eu), 0.0, TAU, 20, Color(col, 0.6 * (1.0 - u)), 2.0)
	ci.draw_set_transform(Vector2.ZERO)
	for j in int(e.n):
		var o := Vector2((_h(e.s, j) - 0.5) * sz * 22.0, sz * 4.0 * (_h(e.s, j + 7) - 0.5))
		ci.draw_circle(sp + o + Vector2(0.0, -eu * sz * (16.0 + 14.0 * _h(e.s, j + 3))), maxf(0.8, sz * 1.8 * (1.0 - u)), Color(col.lightened(0.3), 0.85 * al))


func _d_orb(ci: CanvasItem, add: bool, e: Dictionary, now: float, zs: float) -> void:
	if not add:
		return
	var sz: float = e.sz * zs
	var col: Color = e.col
	var S: Vector2 = v.map(e.p + e.rt * 4.0)
	var E: Vector2 = v.map(e.q)
	var uj: float = (now - e.t0) / e.fl
	if uj <= 0.0:
		return
	if uj < 1.0:
		var h := clampf(S.distance_to(E) * 0.22, 10.0, 56.0)
		var tl: float = 0.07 * float(e.tr)
		for q in 5:
			var pu := maxf(0.0, uj - tl * q)
			var f := 1.0 - q * 0.19
			ci.draw_circle(_arc(S, E, h, pu), maxf(0.8, sz * 3.4 * f), Color(col, 0.55 * f))
		var head := _arc(S, E, h, uj)
		ci.draw_circle(head, sz * 5.0, Color(col, 0.28))
		ci.draw_circle(head, sz * 2.4, Color(col.lightened(0.6), 0.95))
	else:
		var lu: float = (uj - 1.0) * float(e.fl) / 0.3
		if lu < 1.0:
			var eu := 1.0 - (1.0 - lu) * (1.0 - lu)
			ci.draw_set_transform(E, 0.0, Vector2(1.0, 0.6))
			ci.draw_arc(Vector2.ZERO, sz * (6.0 + 18.0 * eu), 0.0, TAU, 18, Color(col, 0.7 * (1.0 - lu)), 2.0)
			ci.draw_set_transform(Vector2.ZERO)
			var a := Color(col.lightened(0.4), 0.9 * (1.0 - lu))
			for q in 4:
				var d := Vector2(cos(q * 1.57 + e.s), sin(q * 1.57 + e.s) * 0.8) * sz * (4.0 + 9.0 * eu)
				ci.draw_line(E + d * 0.3, E + d, a, 1.2)
			if float(e.glow) > 0.01 and lu < 0.6:
				ci.draw_circle(E, sz * 8.0, Color(e.tc, float(e.glow) * 0.5 * (1.0 - lu / 0.6)))
