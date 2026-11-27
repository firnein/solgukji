extends RefCounted
## 11/27 장수 키트 실행부 —— 키트 장수(신화)의 Q · W · E 재사용 대기 · 고유 동작 기술 · 칸별 강화 효과 (자료 data/kit.json, 규칙 scripts/kit.gd).
## 실시간 엔진(RtBattle)이 키트 장수가 있는 판에만 만든다 (sig_rt · tac_rt 와 같은 꼴). 판정은 b.rng 만 쓰고 부대 순서대로 돈다 (결정적).
##
## 자리(갈고리)
##   기술: pick(차례에 쓸 기술) · fire(쓴다 —— 사건 · 효과 · 대기) · idle(닿는 적이 없어 기다리는 차례에 free 기술) · resolve(고유 동작 · 덧붙임 · 강화 효과)
##   고유기: after_ult(쓴 뒤 —— 맞은 적 · 무너진 적)     고유 특기: setup(개전) · tick(주기) · hold_rout(버팀) · on_fall(무너짐)
##   판정에 끼는 것: hit_mul(표식 · 보호) · dodge(고유기 피하기) · no_heal · no_morale · st_block(상태이상 면역) · cleanse_block(풀 수 없는 혼란)
##     · rooted(묶임) · force_tgt(점찍은 적) · no_hold(창병에게 안 붙잡힘) · nocut(끊기지 않는 고유기) · taunt_of(도발) · rogue_hit(도적에게 맞아 밀리는 대기)
## 부대 상태는 Unit.kt (사전 —— 끝 시각 · 깃발), 재사용 대기는 Unit.sk_next, 고유기 늦춤 · 당김은 Unit.ult_hold · ult_shift (+ 기)
## 강화 효과가 일하면 kup 사건을 남긴다 (_kup —— 화면이 강화 이름을 띄운다). b.stats["kup:<진영>:<카드>:<칸>"] 에 횟수 (점검이 읽는다)
const Kit := preload("res://scripts/kit.gd")

const GAUGE_SEC := 5.0      # 고유기 '대기 1초'에 해당하는 기 —— 당김(+) · 늦춤(−)에 함께 쓴다 (기는 100 이 가득, 보통 20초 안팎에 찬다)
const ROGUE_DELAY := 0.3    # 도적에게 맞을 때마다 키트 장수의 기술 대기가 밀리는 초 (충전 방식의 도적 충전 깎기 0.15 에 해당)
const START_CD := 0.5       # 개전 때 첫 대기 —— cd 의 이 몫부터 센다 (접전 전에 한꺼번에 터지지 않게)
const SAY_GAP := 6.0        # 지속형 강화(사기 바닥 · 풀 수 없는 혼란 …)의 kup 사건 최소 간격 (초)
const TOUCH_R := 8.0        # '붙은 적' —— 발자국 틈이 이 안
const STAGGER := 0.7        # 밀려난 부대가 잃는 행동 준비 (1 = 한 차례) —— 밀려나며 주춤한다. 밀기만 하면 적이 사거리 밖으로 흩어져 민 쪽이 손해였다 (실제 대전 덱: 여포 돌파 −4.3%p)

var b                       # RtBattle
var hide_until := 0.0       # 숨은 부대가 있을 수 있는 마지막 시각 (RtBattle._foes_of 가 이때까지만 숨은 부대를 거른다)
var ks := []                # 키트 부대들 (부대 순서)
var _fx := {}               # 부대 -> {칸: fx 사전} (강화한 칸만)
var _said := {}             # "부대키:칸" -> 다음 kup 사건을 낼 수 있는 시각 (지속형)
var _immune := {}           # 진영 -> [끝 시각, 건 장수]  (장각 태평도 —— 상태이상 면역)
var _rev := {}              # 진영 -> {by, until, ratio}  (유비 도원결의 —— 예약된 되살리기)
var _busy := false          # 다시 쓰기(연참 · 난무) 중 —— 또 다시 쓰지 않는다
var _pat := {}              # 진영 -> [끝 시각, 받는 피해 감소]  (11/27 육손 지구전 —— 개전 얼마 동안)


static func make(bt) -> Object:
	var any := false
	for u in bt.units:
		if u.kit != null:
			any = true
			break
	if not any:
		return null
	var s = load("res://scripts/kit_rt.gd").new()
	s.b = bt
	for u in bt.units:
		if u.kit == null:
			continue
		s.ks.append(u)
		var m := {}
		for slot in u.kit:
			var f = Kit.cell(u.c.id, str(slot)).get("fx")
			if f is Dictionary:
				m[str(slot)] = f
		s._fx[u] = m
	return s


## 전투가 끝나면 —— 부대 · 전투를 붙든 참조를 끊는다
func release() -> void:
	for u in b.units:
		u.kt.clear()
	ks.clear()
	_fx.clear()
	_immune.clear()
	_rev.clear()
	_pat.clear()
	b = null


func _up(u, slot: String) -> Dictionary:
	var m = _fx.get(u)
	if m == null:
		return {}
	return m.get(slot, {})


func _upk(u, slot: String) -> String:
	return str(_up(u, slot).get("k", ""))


func _stat(u, slot: String) -> void:
	var key := "kup:%s:%s:%s" % [str(u.camp), str(u.c.id), slot]
	b.stats[key] = int(b.stats.get(key, 0)) + 1


## 강화 효과가 일했다 —— 따로 사건 하나 (fx "kup"). gap > 0 이면 그 초 안에는 다시 내지 않는다 (지속형)
func _kup(u, slot: String, text: String, f := "", gap := 0.0) -> void:
	_stat(u, slot)
	if gap > 0.0:
		var key := "%s:%s" % [str(u.key), slot]
		if b._tm < float(_said.get(key, -1.0)):
			return
		_said[key] = b._tm + gap
	var nm := str(Kit.cell(u.c.id, slot).get("up", {}).get("n", ""))
	var x := {"fx": "kup", "a": u.key, "slot": slot, "up": true, "kup": nm}
	if f != "":
		x["f"] = f
	b.L("sk", "%s의 「%s」 —— %s" % [b.nm(u), nm, text], x)


func _live(us: Array) -> Array:
	var out := []
	for o in us:
		if o.alive and not b._hidden(o):
			out.append(o)
	return out


func _foes(u) -> Array:
	var out := []
	for o in b.units:
		if o.alive and o.camp != u.camp:
			out.append(o)
	return out


func _allies(u) -> Array:
	var out := []
	for o in b.units:
		if o.alive and o.camp == u.camp:
			out.append(o)
	return out


# ───────── 개전 · 주기 ─────────

func setup() -> void:
	for u in ks:
		var sks: Array = u.c.get("sks", [])
		u.sk_next = []
		for sk in sks:
			u.sk_next.append(float(sk.get("start", float(sk.get("cd", 8.0)) * START_CD)))      # (sk.start: 그 기술의 첫 대기 초 —— 개전 직후 적진 뒤로 뛰어드는 기술을 늦출 때)
		var up := _up(u, "p")
		if str(up.get("k", "")) == "open_ult_delay":      # 장료 위명 —— 개전 때 적 최강 장수의 고유기를 늦춘다
			var t = _top_gen(_foes(u))
			if t != null and t.ult != null:
				t.ult_shift += float(up.get("sec", 6.0))
				_kup(u, "p", "%s의 고유기가 %d초 늦어진다" % [b.nm(t), roundi(float(up.get("sec", 6.0)))], str(t.key))
		elif str(up.get("k", "")) == "patience":      # 11/27 육손 지구전 —— 개전 얼마 동안 아군이 받는 피해 −
			_pat[u.camp] = [b._tm + float(up.get("sec", 15.0)), float(up.get("dr", 0.15))]
			_kup(u, "p", "%d초 동안 지키며 때를 기다린다 (아군이 받는 피해 −%d%%)" % [roundi(float(up.get("sec", 15.0))), roundi(float(up.get("dr", 0.15)) * 100)])
		elif str(up.get("k", "")) == "open_haste":      # 11/27 불멸 (여몽 수불석권 · 주유 웅자영발) —— 개전 때 자기 기술 대기를 당긴다
			for jj in u.sk_next.size():
				u.sk_next[jj] = maxf(0.0, float(u.sk_next[jj]) - float(up.get("sec", 2.0)))
			_kup(u, "p", "기술이 %d초 빨리 준비된다" % roundi(float(up.get("sec", 2.0))))
		elif str(up.get("k", "")) == "open_mark":      # 11/27 불멸 (법정 선견지명) —— 개전 때 적 최강 장수에게 표식
			var t = _top_gen(_foes(u))
			if t != null:
				t.kt["vuln"] = maxf(float(t.kt.get("vuln", 0.0)) if b._tm < float(t.kt.get("vuln_t", -1.0)) else 0.0, float(up.get("amt", 0.2)))
				t.kt["vuln_t"] = maxf(float(t.kt.get("vuln_t", 0.0)), b._tm + float(up.get("sec", 8.0)))
				_kup(u, "p", "%s 지목한다 (%d초 동안 받는 피해 +%d%%)" % [b.eul(b.nm(t)), roundi(float(up.get("sec", 8.0))), roundi(float(up.get("amt", 0.2)) * 100)], str(t.key))


func tick(_dt: float) -> void:
	var tm: float = b._tm
	for u in ks:
		if not u.alive:
			continue
		var up := _up(u, "p")
		if up.is_empty():
			continue
		match str(up.get("k", "")):
			"rage":      # 여포 격노 —— 병력이 꺾이면 한 번, 잠시 속도 두 배
				if not u.kt.get("p_used", false) and u.troops < u.max * float(up.get("below", 0.3)):
					u.kt["p_used"] = true
					u.buffs.append({"stat": "spd", "amt": float(up.get("spd", 1.0)), "dur": ceili(float(up.get("sec", 6.0)))})
					_kup(u, "p", "분노로 공격이 빨라진다")
			"retreat_once":      # 손권 퇴각 —— 근접 적이 붙으면 한 번 물러나며 그 적을 늦춘다
				if not u.kt.get("p_used", false):
					var pn = b._pinner(u, _foes(u))
					if pn != null:
						u.kt["p_used"] = true
						var away: Vector2 = u.pos - pn.pos
						var dir: Vector2 = away.normalized() if away.length() > 0.1 else -u.fwd
						u.pos += dir * float(up.get("px", 120.0))
						b._clamp_arena(u)
						u.vel = Vector2.ZERO
						var sl: Array = up.get("slow", [-0.35, 3])
						b.add_buff(pn, {"stat": "spd", "amt": float(sl[0]), "dur": int(sl[1])}, "kit:퇴각")
						_kup(u, "p", "물러나며 %s 늦춘다" % b.eul(b.nm(pn)), str(pn.key))
			"sick_hide":      # 사마의 칭병 —— 병력이 절반 아래면 한 번, 숨고 상태이상을 턴다
				if not u.kt.get("p_used", false) and u.troops < u.max * float(up.get("below", 0.5)):
					u.kt["p_used"] = true
					_hide(u, float(up.get("sec", 3.0)))
					var n := 0
					while n < 4 and b.cleanse(u):
						n += 1
					_kup(u, "p", "병을 핑계로 몸을 숨긴다")
			"morale_floor":      # 유비 백성 —— 살아 있는 동안 아군 사기가 바닥 아래로 떨어지지 않는다
				var v := float(up.get("v", 30.0))
				var lifted := false
				for o in b.units:
					if o.alive and o.camp == u.camp and o.morale < v:
						o.morale = v
						lifted = true
				if lifted:
					_kup(u, "p", "백성의 믿음이 아군의 사기를 붙든다", "", SAY_GAP)
			_:
				_p_tick(u, up)      # 11/27 새 신화 (장비 연인호걸 · 황충 노익장 · 위연 불복 · 여몽 오하아몽)


# ───────── 기술: 고르기 · 쓰기 ─────────

## 이번 차례에 쓸 기술 번호 (없으면 −1) —— 준비된(재사용 대기가 끝난) 기술 가운데 조건이 맞고 가장 오래 기다린 것. idle 이면 닿는 적 없이도 쓰는 기술(free)만
func pick(u, foes: Array, allies: Array, idle: bool) -> int:
	if b.has_st(u, "seal") or b.has_st(u, "confuse"):
		return -1
	var sks: Array = u.c.get("sks", [])
	var best := -1
	for j in sks.size():
		if j >= u.sk_next.size() or b._tm < float(u.sk_next[j]) - 0.001:
			continue
		var sk: Dictionary = sks[j]
		if idle and not bool(sk.get("free", false)):
			continue
		if best >= 0 and float(u.sk_next[j]) >= float(u.sk_next[best]):
			continue
		if _cond(u, sk, foes, allies):
			best = j
	return best


func _cond(u, sk: Dictionary, foes: Array, allies: Array) -> bool:
	var cond := str(sk.get("cond", "always"))
	match cond:
		"always":
			return true
		"pinned":
			return not _touching(u).is_empty()
		"ally_ult":
			return _ult_next(u, true) != null
	return b._sk_cond(u, cond, foes, allies)


## 기술 j 를 쓴다 —— 대기를 다시 세고(다시 쓰기면 그대로), 사건 · 효과 · 강화 효과
func fire(u, j: int, foes: Array, allies: Array, extra := {}, again := false) -> void:
	var sks: Array = u.c.get("sks", [])
	if j < 0 or j >= sks.size():
		return
	var sk: Dictionary = sks[j]
	if not again:
		u.sk_next[j] = b._tm + float(sk.get("cd", 8.0))
	var x: Dictionary = extra.duplicate()
	if sk.eff.has("act"):
		x["act"] = str(sk.eff.act)
	var ts: Array = b._sk_cast(u, j, sk, foes, allies, x)
	resolve(u, j, sk, ts, foes, allies)


## 닿는 적이 없어 기다리는 차례 —— free 기술이 준비됐으면 쓴다 (썼으면 true)
func idle(u) -> bool:
	if u.sk_next.is_empty():
		return false
	var foes: Array = b.units.filter(func(o): return o.camp != u.camp)
	if not foes.any(func(o): return o.alive):
		return false
	var allies: Array = b.units.filter(func(o): return o.camp == u.camp)
	var j := pick(u, foes, allies, true)
	if j < 0:
		return false
	b._ai += 1
	b._ph = "act"
	b._who = u.key
	fire(u, j, foes, allies)
	u.in_skill = false
	b._sk_on = false
	b.check_rout()
	return true


## 기술 효과 마무리 —— 고유 동작(act) · 기술 바탕의 덧붙임 · 강화 효과. ts: 엔진이 이미 친 대상 (고유 동작 기술이면 빈 배열)
func resolve(u, j: int, sk: Dictionary, ts: Array, foes: Array, allies: Array) -> void:
	var e: Dictionary = sk.eff
	var slot: String = Kit.SLOTS[j]
	var up := _up(u, slot)
	var hit: Array = ts
	if e.has("act"):
		var fn := "_act_" + str(e.act)
		hit = call(fn, u, slot, sk, up, foes, allies) if has_method(fn) else []
	for t in hit:
		if not t.alive or t.camp == u.camp:
			continue
		if e.has("act"):      # 엔진 기본 처리를 거치지 않은 기술 —— 속도 깎기 · 상태이상을 여기서
			if e.has("spd"):
				b.add_buff(t, {"stat": "spd", "amt": float(e.spd.amt), "dur": int(e.spd.dur)}, "sk:" + str(sk.n))
			if e.has("status") and str(e.act) != "fireship":
				b.inflict(u, t, str(e.status.k), float(e.status.val), int(e.status.dur))
		if e.has("confuse"):
			_confuse(u, t, float(e.confuse))
		if e.has("seal"):
			_seal(u, t, float(e.seal))
		if e.has("udelay"):
			_ult_delay(t, float(e.udelay))
		if e.has("noheal"):
			t.kt["noheal_t"] = maxf(float(t.kt.get("noheal_t", 0.0)), b._tm + float(e.noheal))
		if e.has("nomor"):
			t.kt["nomor_t"] = maxf(float(t.kt.get("nomor_t", 0.0)), b._tm + float(e.nomor))
		if e.has("root"):
			t.kt["root_t"] = maxf(float(t.kt.get("root_t", 0.0)), b._tm + float(e.root))
			t.vel = Vector2.ZERO
		if e.has("msteal"):
			var ms := minf(float(e.msteal), maxf(0.0, t.morale))
			t.morale -= ms
			u.morale = minf(200.0, u.morale + ms)
			u.mdmg += ms
			b.L("mo", "『%s』 —— %s의 사기를 빼앗았다 (사기 %d)" % [str(sk.n), b.nm(t), roundi(ms)], {"fx": "morale", "f": t.key, "m": ms})
	if not up.is_empty():
		var fu := "_up_" + str(up.get("k", ""))
		if has_method(fu):
			call(fu, u, j, sk, up, hit, foes, allies)


# ───────── 고유 동작 기술 (sk.eff.act) —— 돌려주는 값은 맞은(노린) 적들 ─────────

func _dir_to(u, t) -> Vector2:
	var d: Vector2 = t.pos - u.pos
	return d.normalized() if d.length() > 0.1 else u.fwd


## 띠 안의 적 —— from 에서 dir 로 ln 까지, 반폭 w (발자국이 걸치면 든다). 가까운 순
func _band(live: Array, from: Vector2, dir: Vector2, ln: float, w: float) -> Array:
	var perp := Vector2(-dir.y, dir.x)
	var out := []
	for o in live:
		var v: Vector2 = o.pos - from
		var along := v.dot(dir)
		if along >= -10.0 and along <= ln + RtBattle._extent(o, dir) and absf(v.cross(dir)) <= w + RtBattle._extent(o, perp):
			out.append(o)
	out.sort_custom(func(x, y):
		var ax: float = (x.pos - from).dot(dir)
		var ay: float = (y.pos - from).dot(dir)
		return ax < ay if ax != ay else str(x.key) < str(y.key))
	return out


## 장료 위진소요 —— 적 대열을 꿰뚫고 지나가며 지나친 적 모두에게 피해
func _act_dash_through(u, slot: String, sk: Dictionary, up: Dictionary, foes: Array, _allies_: Array) -> Array:
	var e: Dictionary = sk.eff
	var live := _live(foes)
	if live.is_empty():
		return []
	var t0 = u.tgt if (u.tgt != null and u.tgt.alive and live.has(u.tgt)) else b._nearest(u.pos, live)
	var dir := _dir_to(u, t0)
	var w := float(e.get("w", 55.0))
	var hit := _band(live, u.pos, dir, float(e.get("len", 300.0)), w)
	if hit.is_empty():
		hit = [t0]
	var far := 0.0
	for o in hit:
		far = maxf(far, (o.pos - u.pos).dot(dir) + RtBattle._extent(o, dir))
	var from: Vector2 = u.pos
	var to: Vector2 = from + dir * (far + RtBattle._extent(u, dir) + 14.0)
	b._mark(u, {"k": "line", "x": from.x, "y": from.y, "x2": to.x, "y2": to.y, "w": w})
	for o in hit:
		if o.alive and u.alive:
			b.phys_hit(u, o, float(e.mult), true)
	if u.alive:
		u.pos = to
		b._clamp_arena(u)
		u.vel = Vector2.ZERO
		u.fwd = -dir
		u.tgt = null
		u.retgt = 0.0
		u.ran = 0.0
	return hit


## 장료 팔백결사 —— 적 후열 1부대를 점찍어 달려든다 (묶이지 않는다 · 공격 +)
func _act_dive(u, slot: String, sk: Dictionary, _up_: Dictionary, foes: Array, _allies_: Array) -> Array:
	var e: Dictionary = sk.eff
	var live := _live(foes)
	if live.is_empty():
		return []
	var rg := live.filter(func(o): return o.ranged)
	var t = b._deepest(u, rg if not rg.is_empty() else live)
	var sec := float(e.get("sec", 5.0))
	u.kt["ftg"] = t
	u.kt["ftg_t"] = b._tm + sec
	u.tgt = t
	u.retgt = 0.5
	b.add_buff(u, {"stat": "atk", "amt": float(e.get("atk", 0.3)), "dur": ceili(sec)}, "sk:" + str(sk.n))
	b._mark(u, {"k": "circle", "x": roundi(t.pos.x), "y": roundi(t.pos.y), "r": 60})
	b.L("sk", "%s %s 점찍고 달려든다" % [b.ga(b.nm(u)), b.eul(b.nm(t))], {"fx": "debuff", "a": u.key, "f": t.key})
	return [t]


## 여포 적토질주 —— 병력이 가장 많은 적 장수에게 곧장 달려들어 강타
func _act_charge_to(u, slot: String, sk: Dictionary, up: Dictionary, foes: Array, _allies_: Array) -> Array:
	var e: Dictionary = sk.eff
	var live := _live(foes)
	if live.is_empty():
		return []
	var gens := live.filter(func(o): return o.ult != null)
	var pool: Array = gens if not gens.is_empty() else live
	var t = pool[0]
	for o in pool:
		if o.troops > t.troops:
			t = o
	var dir := _dir_to(u, t)
	var from: Vector2 = u.pos
	var stop: Vector2 = t.pos - dir * (RtBattle._extent(t, dir) + RtBattle._extent(u, dir) + 4.0)
	var run := (stop - from).dot(dir)
	if run > 0.0:
		if str(up.get("k", "")) == "path_push":      # 돌파 —— 달려드는 길의 적을 좌우로 밀쳐낸다
			var pushed := 0
			for o in _band(live, from, dir, run, 50.0):
				if o == t or not o.alive:
					continue
				var side := signf((o.pos - from).cross(dir))
				if side == 0.0:
					side = 1.0 if int(o.slot) % 2 == 0 else -1.0
				_shove(o, Vector2(-dir.y, dir.x) * -side * float(up.get("px", 60.0)), u)
				pushed += 1
			if pushed > 0:
				_kup(u, slot, "길을 막은 적 %d부대를 밀쳐낸다" % pushed)
		u.pos = stop
		b._clamp_arena(u)
		u.vel = Vector2.ZERO
	u.fwd = dir
	u.tgt = t
	u.retgt = 0.5
	u.ran = 0.0
	b._mark(u, {"k": "line", "x": from.x, "y": from.y, "x2": u.pos.x, "y2": u.pos.y, "w": 40.0})
	b.phys_hit(u, t, float(e.mult), false)
	return [t]


## 여포 원문사극 —— 가장 먼 적 1부대를 쏘아 고유기를 끊는다 (혼란은 덧붙임 confuse)
func _act_snipe(u, slot: String, sk: Dictionary, _up_: Dictionary, foes: Array, _allies_: Array) -> Array:
	var live := _live(foes)
	if live.is_empty():
		return []
	var t = _farthest(u, live)
	b._mark(u, {"k": "line", "x": u.pos.x, "y": u.pos.y, "x2": t.pos.x, "y2": t.pos.y, "w": 14.0})
	b.phys_hit(u, t, float(sk.eff.mult), true)
	if t.alive and b._wind.has(t):
		b._cut_wind(t, u)
	return [t]


## 손권 강동결집 —— 가장 위태로운 아군 1부대를 보호하고 상태이상을 턴다
func _act_protect(u, slot: String, sk: Dictionary, up: Dictionary, foes: Array, allies: Array) -> Array:
	var e: Dictionary = sk.eff
	var t = _weakest(allies)
	if t == null:
		return []
	var sec := float(e.get("sec", 4.0))
	t.kt["dr"] = float(e.get("dr", 0.35))
	t.kt["dr_t"] = b._tm + sec
	var n := 0
	while n < 4 and b.cleanse(t):
		n += 1
	b.L("sk", "『%s』 —— %s 지킨다 (%d초 동안 받는 피해 −%d%%)" % [str(sk.n), b.eul(b.nm(t)), roundi(sec), roundi(float(e.get("dr", 0.35)) * 100)], {"fx": "buff", "f": t.key, "up": true})
	if str(up.get("k", "")) == "push_off":      # 구원 —— 그 아군에게 붙은 적을 밀쳐낸다
		var off := _touching(t)
		for o in off:
			_push(t, o, float(up.get("px", 60.0)), u)
		if not off.is_empty():
			_kup(u, slot, "%s에게 붙은 적 %d부대를 밀쳐낸다" % [b.nm(t), off.size()], str(t.key))
	return []


## 손권 호령 —— 아군 전체의 기술 대기를 당긴다
func _act_haste(u, slot: String, sk: Dictionary, _up_: Dictionary, _foes_: Array, allies: Array) -> Array:
	var sec := float(sk.eff.get("sec", 2.0))
	for o in allies:
		if o.alive:
			_sk_haste(o, sec, u, Kit.SLOTS.find(slot))
	b.L("sk", "『%s』 —— 아군의 기술이 %d초 빨라진다" % [str(sk.n), roundi(sec)], {"fx": "buff", "f": u.key, "up": true})
	return []


## 감녕 백기야습 —— 모습을 감췄다가 적 후열 뒤에 나타나 친다
func _act_shadow(u, slot: String, sk: Dictionary, up: Dictionary, foes: Array, _allies_: Array) -> Array:
	var live := _live(foes)
	if live.is_empty():
		return []
	var rg := live.filter(func(o): return o.ranged)
	var t = b._deepest(u, rg if not rg.is_empty() else live)
	var back := Vector2(1.0 if u.camp == "A" else -1.0, 0.0)      # 그 적의 뒤쪽 (적 진영 깊은 쪽)
	u.pos = t.pos + back * (RtBattle._extent(t, back) + RtBattle._extent(u, back) + 4.0)
	b._clamp_arena(u)
	u.vel = Vector2.ZERO
	u.fwd = -back
	u.tgt = t
	u.retgt = 0.5
	u.ran = 0.0
	b._mark(u, {"k": "circle", "x": roundi(t.pos.x), "y": roundi(t.pos.y), "r": 60})
	b.phys_hit(u, t, float(sk.eff.mult), false)
	if str(up.get("k", "")) == "area_confuse":      # 야습 —— 나타날 때 주변 적 혼란
		var n := 0
		for o in live:
			if o.alive and b._gap(u, o) <= float(up.get("r", 90.0)) and _confuse(u, o, float(up.get("sec", 1.5))):
				n += 1
		if n > 0:
			_kup(u, slot, "어둠 속 기습에 적 %d부대가 혼란에 빠진다" % n)
	return [t]


## 감녕 비도 —— 가장 먼 적 원거리 1부대에 단도를 던진다 (둔화 · 고유기 지연은 덧붙임)
func _act_throw(u, slot: String, sk: Dictionary, _up_: Dictionary, foes: Array, _allies_: Array) -> Array:
	var live := _live(foes)
	if live.is_empty():
		return []
	var rg := live.filter(func(o): return o.ranged)
	var t = _farthest(u, rg if not rg.is_empty() else live)
	b._mark(u, {"k": "line", "x": u.pos.x, "y": u.pos.y, "x2": t.pos.x, "y2": t.pos.y, "w": 10.0})
	b.phys_hit(u, t, float(sk.eff.mult), true)
	return [t]


## 제갈량 밀계 —— 가장 강한 적 장수 1부대에 피해 (고유기 지연은 덧붙임)
func _act_smite(u, slot: String, sk: Dictionary, _up_: Dictionary, foes: Array, _allies_: Array) -> Array:
	var t = _top_gen(_live(foes))
	if t == null:
		return []
	b._mark(u, {"k": "circle", "x": roundi(t.pos.x), "y": roundi(t.pos.y), "r": 60})
	_hit(u, t, float(sk.eff.mult), 1)
	return [t]


## 주유 고육계 —— 가장 튼튼한 아군이 적 3부대를 도발하고 피해를 덜 받는다
func _act_decoy(u, slot: String, sk: Dictionary, up: Dictionary, foes: Array, allies: Array) -> Array:
	var e: Dictionary = sk.eff
	var al := allies.filter(func(o): return o.alive and not o.ranged and o != u)
	if al.is_empty():
		al = allies.filter(func(o): return o.alive)
	var live := _live(foes)
	if al.is_empty() or live.is_empty():
		return []
	var tank = al[0]
	for o in al:
		if o.troops > tank.troops:
			tank = o
	var near: Array = live.duplicate()
	near.sort_custom(func(x, y):
		var dx: float = x.pos.distance_squared_to(tank.pos)
		var dy: float = y.pos.distance_squared_to(tank.pos)
		return dx < dy if dx != dy else str(x.key) < str(y.key))
	near = near.slice(0, int(e.get("n", 3)))
	var sec := float(e.get("sec", 4.0))
	for o in near:
		o.sg["tnt"] = tank
		o.sg["tnt_t"] = b._tm + sec
	tank.kt["dr"] = float(e.get("dr", 0.3))
	tank.kt["dr_t"] = b._tm + sec
	b.L("sk", "『%s』 —— %s 적 %d부대를 끌어들인다 (%d초 동안 받는 피해 −%d%%)" % [str(sk.n), b.ga(b.nm(tank)), near.size(), roundi(sec), roundi(float(e.get("dr", 0.3)) * 100)],
		{"fx": "buff", "f": tank.key, "up": true})
	if str(up.get("k", "")) == "taunt_burn":      # 거짓 항복 —— 도발된 적에게 불이 붙는다
		for o in near:
			b.inflict(u, o, "burn", float(up.get("val", 0.15)), int(up.get("dur", 3)))
		_kup(u, slot, "끌려든 적 %d부대에 불이 붙는다" % near.size(), str(tank.key))
	return []


## 주유 화선돌입 —— 가장 밀집한 적 무리에 큰 화염, 이미 타던 적은 폭발해 주변에 번진다
func _act_fireship(u, slot: String, sk: Dictionary, up: Dictionary, foes: Array, _allies_: Array) -> Array:
	var e: Dictionary = sk.eff
	var live := _live(foes)
	if live.is_empty():
		return []
	var best: Array = []
	for c in live:
		var g := live.filter(func(o): return o == c or b._gap(o, c) <= RtBattle.AREA_GAP + 20.0)
		if g.size() > best.size():
			best = g
	var was := best.filter(func(o): return b.has_st(o, "burn"))
	b._mark_targets(u, best)
	var st: Dictionary = e.get("status", {"k": "burn", "val": 0.2, "dur": 4})
	for o in best:
		if o.alive:
			_hit(u, o, float(e.mult), best.size())
		if o.alive:
			b.inflict(u, o, "burn", float(st.val), int(st.dur))
	var blasted := []
	var r := float(e.get("r", 70.0))
	for o in was:
		for x in live:
			if x != o and x.alive and not blasted.has(x) and b._gap(x, o) <= r:
				blasted.append(x)
	for x in blasted:
		if x.alive:
			_hit(u, x, float(e.get("blast", 0.8)), 1)
		if x.alive and not b.has_st(x, "burn"):
			b.inflict(u, x, "burn", float(st.val), int(st.dur))
	if not was.is_empty():
		b.L("sk", "『%s』 —— 타던 불이 터져 주변 %d부대를 덮친다" % [str(sk.n), blasted.size()], {"fx": "status", "f": was[0].key, "st": "burn", "from": u.key, "spread": true})
		if str(up.get("k", "")) == "blast_confuse":      # 화염폭풍 —— 폭발에 휘말린 적 혼란
			var n := 0
			for x in was + blasted:
				if x.alive and _confuse(u, x, float(up.get("sec", 1.5))):
					n += 1
			if n > 0:
				_kup(u, slot, "폭발에 휘말린 적 %d부대가 혼란에 빠진다" % n)
	var out: Array = best.duplicate()
	for x in blasted:
		if not out.has(x):
			out.append(x)
	return out


## 유비 삼고초려 —— 고유기가 가장 가까운 아군의 고유기 대기를 당긴다
func _act_ult_haste(u, slot: String, sk: Dictionary, up: Dictionary, _foes_: Array, _allies_: Array) -> Array:
	var t = _ult_next(u, true)
	if t == null:
		return []
	var sec := float(sk.eff.get("sec", 3.0))
	_ult_haste(t, sec)
	b.L("sk", "『%s』 —— %s의 고유기가 %d초 앞당겨진다" % [str(sk.n), b.nm(t), roundi(sec)], {"fx": "buff", "f": t.key, "up": true})
	if str(up.get("k", "")) == "nocut":      # 와룡출려 —— 그 장수의 다음 고유기는 끊기지 않는다
		t.kt["nocut"] = [u, slot]
		_kup(u, slot, "%s의 다음 고유기는 끊기지 않는다" % b.nm(t), str(t.key))
	return []


## 유비 쌍고검 —— 유비에게 붙은 적을 베어 밀쳐낸다 (둔화는 덧붙임)
func _act_sweep_off(u, slot: String, sk: Dictionary, up: Dictionary, _foes_: Array, allies: Array) -> Array:
	var e: Dictionary = sk.eff
	var hit := _touching(u)
	for t in hit:
		if t.alive:
			_hit(u, t, float(e.mult), hit.size())
		if t.alive:
			_push(u, t, float(e.get("px", 70.0)))
	if str(up.get("k", "")) == "ally_dive" and not hit.is_empty():      # 의형제 —— 밀쳐낸 적에게 가장 가까운 아군 근접 장수가 달려든다
		var t0 = null
		for t in hit:
			if t.alive:
				t0 = t
				break
		if t0 != null:
			var best = null
			var bd := INF
			for o in allies:
				if not o.alive or o == u or o.ranged:
					continue
				var d: float = o.pos.distance_to(t0.pos) * (1.0 if o.ult != null else 1.5)      # 장수(고유기를 가진 부대) 먼저
				if d < bd:
					bd = d
					best = o
			if best != null:
				best.kt["ftg"] = t0
				best.kt["ftg_t"] = b._tm + float(up.get("sec", 4.0))
				best.tgt = t0
				_kup(u, slot, "%s %s에게 달려든다" % [b.ga(b.nm(best)), b.nm(t0)], str(best.key))
	return hit


## 조조 망매지갈 —— 사기가 가장 낮은 아군 2부대의 사기를 올리고 패주를 막는다
func _act_cheer_low(u, slot: String, sk: Dictionary, up: Dictionary, _foes_: Array, allies: Array) -> Array:
	var e: Dictionary = sk.eff
	var al := allies.filter(func(o): return o.alive)
	al.sort_custom(func(x, y): return x.morale < y.morale if x.morale != y.morale else str(x.key) < str(y.key))
	al = al.slice(0, int(e.get("n", 2)))
	var sec := float(e.get("sec", 3.0))
	for o in al:
		b._rally(o, float(e.get("morale", 15.0)), str(sk.n))
		o.kt["norout_t"] = maxf(float(o.kt.get("norout_t", 0.0)), b._tm + sec)
		if str(up.get("k", "")) == "dodge_ult":      # 허허실실 —— 다음에 맞는 고유기를 한 번 피한다
			o.kt["dodge"] = [u, slot]
			o.kt.erase("dodge_by")
	if str(up.get("k", "")) == "dodge_ult" and not al.is_empty():
		_kup(u, slot, "%d부대가 다음 고유기를 한 번 피한다" % al.size(), str(al[0].key))
	return []


# ───────── 강화 효과 (기술 —— fx.k) ─────────

## 관우 연참 —— 이 기술로 적이 무너지면 바로 한 번 더 쓴다
func _up_recast_kill(u, j: int, sk: Dictionary, up: Dictionary, hit: Array, foes: Array, allies: Array) -> void:
	if _busy or not u.alive or not hit.any(func(o): return not o.alive) or not foes.any(func(o): return o.alive):
		return
	_busy = true
	_stat(u, Kit.SLOTS[j])
	fire(u, j, foes, allies, {"kup": str(Kit.cell(u.c.id, Kit.SLOTS[j]).get("up", {}).get("n", "")), "again": true}, true)
	_busy = false


## 관우 격퇴(뒤로 밀고 둔화) · 여포 극풍(좌우로 흩는다)
func _up_push(u, j: int, _sk: Dictionary, up: Dictionary, hit: Array, _foes_: Array, _allies_: Array) -> void:
	var n := 0
	var first := ""
	for i in hit.size():
		var t = hit[i]
		if not t.alive:
			continue
		if bool(up.get("side", false)):
			var fw: Vector2 = u.fwd
			var side := signf(fw.cross(t.pos - u.pos))
			if side == 0.0:
				side = 1.0 if i % 2 == 0 else -1.0
			_shove(t, Vector2(-fw.y, fw.x) * side * float(up.get("px", 50.0)), u)
		else:
			_push(u, t, float(up.get("px", 45.0)))
		if up.has("slow"):
			b.add_buff(t, {"stat": "spd", "amt": float(up.slow[0]), "dur": int(up.slow[1])}, "kit:" + Kit.SLOTS[j])
		if first == "":
			first = str(t.key)
		n += 1
	if n > 0:
		_kup(u, Kit.SLOTS[j], "적 %d부대를 %s" % [n, "좌우로 흩어 놓는다" if bool(up.get("side", false)) else "뒤로 밀어낸다"], first)


## 관우 단기 —— 맞은 적의 고유기를 끊거나 늦춘다
func _up_ult_stop(u, j: int, _sk: Dictionary, up: Dictionary, hit: Array, _foes_: Array, _allies_: Array) -> void:
	for t in hit:
		if not t.alive or t.ult == null or t.charges <= 0:
			continue
		if b._wind.has(t):
			b._cut_wind(t, u)
			if not b._wind.has(t):
				_kup(u, Kit.SLOTS[j], "%s의 고유기를 끊었다" % b.nm(t), str(t.key))
				continue
		_ult_delay(t, float(up.get("sec", 4.0)))
		_kup(u, Kit.SLOTS[j], "%s의 고유기가 %d초 늦어진다" % [b.nm(t), roundi(float(up.get("sec", 4.0)))], str(t.key))


## 장료 연환돌격 —— 돌격 뒤 가까운 다른 적에게 한 번 더 들이친다
func _up_chain_hit(u, j: int, sk: Dictionary, up: Dictionary, hit: Array, foes: Array, _allies_: Array) -> void:
	if hit.is_empty() or not u.alive:
		return
	var t0 = hit[0]
	var best = _beside(t0, _live(foes), float(up.get("r", 120.0)))
	if best == null:
		return
	_kup(u, Kit.SLOTS[j], "%s에게 한 번 더 들이친다" % b.nm(best), str(best.key))
	b.phys_hit(u, best, float(up.get("mult", 1.3)), true)


## 장료 파진 —— 지나친 적에게 표식 (받는 피해 증가)
func _up_vuln(u, j: int, _sk: Dictionary, up: Dictionary, hit: Array, _foes_: Array, _allies_: Array) -> void:
	var n := 0
	var first := ""
	for t in hit:
		if t.alive:
			t.kt["vuln"] = float(up.get("amt", 0.2))
			t.kt["vuln_t"] = b._tm + float(up.get("sec", 4.0))
			if first == "":
				first = str(t.key)
			n += 1
	if n > 0:
		_kup(u, Kit.SLOTS[j], "지나친 적 %d부대에 표식 (받는 피해 +%d%%)" % [n, roundi(float(up.get("amt", 0.2)) * 100)], first)


## 장료 결사 —— 달려드는 동안 쓰러지지 않는다
func _up_stand_self(u, j: int, _sk: Dictionary, up: Dictionary, _hit: Array, _foes_: Array, _allies_: Array) -> void:
	u.kt["stand_t"] = maxf(float(u.kt.get("stand_t", 0.0)), b._tm + float(up.get("sec", 5.0)))
	_kup(u, Kit.SLOTS[j], "%d초 동안 쓰러지지 않는다" % roundi(float(up.get("sec", 5.0))))


## 봉인 —— 여포 신궁 · 감녕 방울 소리 · 제갈량 공성 · 사마의 금쇄
func _up_seal(u, j: int, _sk: Dictionary, up: Dictionary, hit: Array, _foes_: Array, _allies_: Array) -> void:
	var n := 0
	var first := ""
	for t in hit:
		if t.alive and t.camp != u.camp and _seal(u, t, float(up.get("sec", 3.0))):
			if first == "":
				first = str(t.key)
			n += 1
	if n > 0:
		_kup(u, Kit.SLOTS[j], "적 %d부대의 기술을 봉한다" % n, first)


## 손권 관통 —— 화살이 길 위의 적을 꿰뚫고 지나간다
func _up_pierce_line(u, j: int, sk: Dictionary, up: Dictionary, hit: Array, foes: Array, _allies_: Array) -> void:
	var live := _live(foes)
	var got := []
	for t in hit:
		var dir := _dir_to(u, t)
		for o in _band(live, u.pos, dir, u.pos.distance_to(t.pos), 26.0):
			if not hit.has(o) and not got.has(o):
				got.append(o)
	if got.is_empty():
		return
	_kup(u, Kit.SLOTS[j], "화살이 길 위의 적 %d부대를 꿰뚫는다" % got.size(), str(got[0].key))
	for o in got:
		if o.alive and u.alive:
			b.phys_hit(u, o, float(sk.eff.get("mult", 1.0)) * float(up.get("mult", 0.5)), true)


## 손권 천명 —— 고유기가 가장 가까운 아군의 고유기 대기를 당긴다
func _up_ult_haste_ally(u, j: int, _sk: Dictionary, up: Dictionary, _hit: Array, _foes_: Array, _allies_: Array) -> void:
	var t = _ult_next(u, false)
	if t == null:
		return
	_ult_haste(t, float(up.get("sec", 3.0)))
	_kup(u, Kit.SLOTS[j], "%s의 고유기가 %d초 앞당겨진다" % [b.nm(t), roundi(float(up.get("sec", 3.0)))], str(t.key))


## 감녕 출혈 —— 맞은 적이 피를 흘린다
func _up_bleed(u, j: int, _sk: Dictionary, up: Dictionary, hit: Array, _foes_: Array, _allies_: Array) -> void:
	var first := ""
	for t in hit:
		if t.alive:
			b.inflict(u, t, "bleed", float(up.get("val", 0.06)), int(up.get("dur", 4)))
			if first == "" and b.has_st(t, "bleed"):
				first = str(t.key)
	if first != "":
		_kup(u, Kit.SLOTS[j], "맞은 적이 피를 흘린다", first)


## 제갈량 순풍 · 주유 연환 —— 맞은 적 가운데 불타는 적의 화상이 옆의 타지 않는 부대로 번진다 (n 부대까지). 연환은 불붙은 적과 불이 옮은 부대를 함께 늦춘다
func _up_spread_burn(u, j: int, _sk: Dictionary, up: Dictionary, hit: Array, foes: Array, _allies_: Array) -> void:
	var live := _live(foes)
	var left := int(up.get("n", 3))
	var n := 0
	var slowed := 0
	var first := ""
	for t in hit:
		if not t.alive:
			continue
		var s = b._st_of(t, "burn")
		if s == null:
			continue
		if up.has("slow"):
			b.add_buff(t, {"stat": "spd", "amt": float(up.slow[0]), "dur": int(up.slow[1])}, "kit:" + Kit.SLOTS[j])
			slowed += 1
			if first == "":
				first = str(t.key)
		if left <= 0:
			continue
		var best = _beside(t, live.filter(func(o): return not b.has_st(o, "burn")), float(up.get("r", 100.0)))
		if best == null:
			continue
		b._spread_burn_to(t, s, best, str(u.key))
		if up.has("slow"):
			b.add_buff(best, {"stat": "spd", "amt": float(up.slow[0]), "dur": int(up.slow[1])}, "kit:" + Kit.SLOTS[j])
		if first == "" or n == 0:
			first = str(best.key)
		left -= 1
		n += 1
	if n > 0:
		_kup(u, Kit.SLOTS[j], "불길이 옆의 %d부대로 번진다" % n, first)
	elif slowed > 0:
		_kup(u, Kit.SLOTS[j], "불붙은 적 %d부대의 발이 묶인다" % slowed, first)


## 제갈량 반목 —— 사기가 가장 낮은 적 1부대 혼란
func _up_confuse_low(u, j: int, _sk: Dictionary, up: Dictionary, _hit: Array, foes: Array, _allies_: Array) -> void:
	var t = null
	for o in _live(foes):
		if not b.has_st(o, "confuse") and (t == null or o.morale < t.morale):
			t = o
	if t != null and _confuse(u, t, float(up.get("sec", 3.0))):
		_kup(u, Kit.SLOTS[j], "%s 서로를 의심해 혼란에 빠진다" % b.ga(b.nm(t)), str(t.key))


## 유비 의병 —— 가장 약한 아군 1부대가 잠시 쓰러지지 않는다
func _up_stand_ally(u, j: int, _sk: Dictionary, up: Dictionary, _hit: Array, _foes_: Array, allies: Array) -> void:
	var t = _weakest(allies)
	if t == null:
		return
	t.kt["stand_t"] = maxf(float(t.kt.get("stand_t", 0.0)), b._tm + float(up.get("sec", 3.0)))
	_kup(u, Kit.SLOTS[j], "%s %d초 동안 쓰러지지 않는다" % [b.ga(b.nm(t)), roundi(float(up.get("sec", 3.0)))], str(t.key))


## 장각 선동 —— 혼란한 적 1부대가 옆의 자기 편을 한 번 친다
func _up_turncoat(u, j: int, _sk: Dictionary, up: Dictionary, hit: Array, foes: Array, _allies_: Array) -> void:
	var c = null
	for t in hit:
		if t.alive and b.has_st(t, "confuse"):
			c = t
			break
	if c == null:
		return
	var best = _beside(c, foes, float(up.get("r", 90.0)))
	if best == null:
		return
	_kup(u, Kit.SLOTS[j], "홀린 %s 제 편 %s 친다" % [b.ga(b.nm(c)), b.eul(b.nm(best))], str(c.key))
	if b.is_caster(c.c):
		b.int_hit(c, best, float(up.get("mult", 1.0)), 1)
	else:
		b.phys_hit(c, best, float(up.get("mult", 1.0)), true)


## 장각 미혹 —— 맞은 적은 잠시 치료를 받지 못한다
func _up_noheal(u, j: int, _sk: Dictionary, up: Dictionary, hit: Array, _foes_: Array, _allies_: Array) -> void:
	var first := ""
	var n := 0
	for t in hit:
		if t.alive:
			t.kt["noheal_t"] = maxf(float(t.kt.get("noheal_t", 0.0)), b._tm + float(up.get("sec", 3.0)))
			t.kt["noheal_by"] = [u, Kit.SLOTS[j]]
			if first == "":
				first = str(t.key)
			n += 1
	if n > 0:
		_kup(u, Kit.SLOTS[j], "적 %d부대가 %d초 동안 치료를 받지 못한다" % [n, roundi(float(up.get("sec", 3.0)))], first)


## 장각 낙뢰 —— 번개가 가까운 적에게 한 번 튄다
func _up_bounce(u, j: int, _sk: Dictionary, up: Dictionary, hit: Array, foes: Array, _allies_: Array) -> void:
	var live := _live(foes)
	var got := []
	for t in hit:
		var best = _beside(t, live, float(up.get("r", 120.0)), hit + got)
		if best != null:
			got.append(best)
	if got.is_empty():
		return
	_kup(u, Kit.SLOTS[j], "번개가 가까운 %d부대로 튄다" % got.size(), str(got[0].key))
	for o in got:
		if o.alive and u.alive:
			_hit(u, o, float(up.get("mult", 0.9)), 1)


## 조조 천자의 명 —— 가장 강한 아군 1부대의 기술 대기를 모두 없앤다
func _up_sk_reset_ally(u, j: int, _sk: Dictionary, _up_: Dictionary, _hit: Array, _foes_: Array, allies: Array) -> void:
	var t = null
	for o in allies:
		if not o.alive or o == u or (o.c.get("sks", []) as Array).is_empty():
			continue
		if t == null or int(o.c.tier) > int(t.c.tier) or (int(o.c.tier) == int(t.c.tier) and float(o.c.atk) > float(t.c.atk)):
			t = o
	if t == null:
		return
	_sk_haste(t, 999.0, null, -1)
	_kup(u, Kit.SLOTS[j], "%s의 기술이 모두 준비된다" % b.nm(t), str(t.key))


## 조조 단량 —— 그 부대와 주변 부대가 치료를 받지 못한다
func _up_noheal_area(u, j: int, _sk: Dictionary, up: Dictionary, hit: Array, foes: Array, _allies_: Array) -> void:
	if hit.is_empty():
		return
	var t0 = hit[0]
	var n := 0
	for o in foes:
		if o.alive and (o == t0 or b._gap(o, t0) <= float(up.get("r", 90.0))):
			o.kt["noheal_t"] = maxf(float(o.kt.get("noheal_t", 0.0)), b._tm + float(up.get("sec", 4.0)))
			o.kt["noheal_by"] = [u, Kit.SLOTS[j]]
			n += 1
	if n > 0:
		_kup(u, Kit.SLOTS[j], "군량이 끊겨 적 %d부대가 치료를 받지 못한다" % n, str(t0.key))


## 사마의 간파 —— 고유기를 모으던 적은 끊긴다
func _up_cut_wind(u, j: int, _sk: Dictionary, _up_: Dictionary, hit: Array, _foes_: Array, _allies_: Array) -> void:
	for t in hit:
		if t.alive and b._wind.has(t):
			b._cut_wind(t, u)
			if not b._wind.has(t):
				_kup(u, Kit.SLOTS[j], "%s의 고유기를 간파해 끊었다" % b.nm(t), str(t.key))


## 사마의 창궐 —— 역병이 옆 부대로 번진다
func _up_plague_spread(u, j: int, sk: Dictionary, up: Dictionary, hit: Array, foes: Array, _allies_: Array) -> void:
	var live := _live(foes)
	var st: Dictionary = sk.eff.get("status", {"k": "plague", "val": 25, "dur": 5})
	var got := []
	for t in hit:
		if not t.alive or not b.has_st(t, "plague"):
			continue
		var best = _beside(t, live.filter(func(o): return not b.has_st(o, "plague")), float(up.get("r", 100.0)), got)
		if best != null:
			got.append(best)
	if got.is_empty():
		return
	_kup(u, Kit.SLOTS[j], "역병이 옆의 %d부대로 번진다" % got.size(), str(got[0].key))
	for o in got:
		b.inflict(u, o, "plague", float(st.val), int(st.dur))


# ───────── 고유기 뒤 (강화 r 칸 · 고유 특기 가운데 고유기에 걸린 것) ─────────

## 고유기를 쓴 뒤 —— hits: 이 고유기가 노린 적들 (타격 · 적 효과), 무너졌는지는 지금 alive 로 본다
func after_ult(u, hits: Array) -> void:
	var foes: Array = b.units.filter(func(o): return o.camp != u.camp)
	var allies: Array = b.units.filter(func(o): return o.camp == u.camp)
	var pk := _upk(u, "p")
	if pk == "ult_haste_sk":      # 주유 미주랑 —— 고유기를 쓰면 아군 전체의 기술 대기 단축
		for o in allies:
			if o.alive:
				_sk_haste(o, float(_up(u, "p").get("sec", 2.0)), null, -1)
		_kup(u, "p", "아군의 기술이 %d초 빨라진다" % roundi(float(_up(u, "p").get("sec", 2.0))))
	var up := _up(u, "r")
	if up.is_empty():
		return
	var fn := "_ult_" + str(up.get("k", ""))
	if has_method(fn):
		call(fn, u, up, hits, foes, allies)
	elif has_method("_up_" + str(up.get("k", ""))):      # 11/27 불멸 —— 고유기 전용 효과가 없으면 같은 이름의 기술 강화 효과를 고유기에 맞은 적에게 (칸 번호 3 = r)
		call("_up_" + str(up.get("k", "")), u, 3, {"n": str(u.ult.get("name", "")) if u.ult != null else "", "eff": {}}, up, hits, foes, allies)


## 관우 수엄칠군 —— 맞은 적이 물에 잠긴다
func _ult_flood(u, up: Dictionary, hits: Array, _foes_: Array, _allies_: Array) -> void:
	var first := ""
	for t in hits:
		if t.alive and t.camp != u.camp:
			b.inflict(u, t, "flood", 0.0, int(up.get("sec", 4)))
			if first == "" and b.has_st(t, "flood"):
				first = str(t.key)
	if first != "":
		_kup(u, "r", "맞은 적이 물에 잠긴다", first)


## 장료 지제 —— 이 고유기에 맞은 적 가운데 사기가 가장 낮은 n 부대는 혼란
## (글은 '사기 50 이하'였다 —— 기술 · 고유기의 사기 회복으로 적 사기가 거의 늘 100 을 넘어 실제 대전 덱에서 한 번도 걸리지 않는 판이 95% 였다)
func _ult_confuse_morale(u, up: Dictionary, hits: Array, _foes_: Array, _allies_: Array) -> void:
	var pool: Array = hits.filter(func(t): return t.alive and t.camp != u.camp and not b.has_st(t, "confuse"))
	pool.sort_custom(func(x, y): return x.morale < y.morale if x.morale != y.morale else str(x.key) < str(y.key))
	var n := 0
	var first := ""
	for t in pool.slice(0, int(up.get("n", 2))):
		if _confuse(u, t, float(up.get("sec", 2.0))):
			if first == "":
				first = str(t.key)
			n += 1
	if n > 0:
		_kup(u, "r", "겁먹은 적 %d부대가 혼란에 빠진다" % n, first)


## 여포 난무 —— 무너뜨린 적 하나마다 방천화극(Q)을 즉시 한 번
func _ult_recast_q_kills(u, up: Dictionary, hits: Array, foes: Array, allies: Array) -> void:
	var n := 0
	for t in hits:
		if not t.alive and t.camp != u.camp:
			n += 1
	n = mini(n, int(up.get("max", 3)))
	if n <= 0 or _busy:
		return
	_busy = true
	var nm := str(Kit.cell(u.c.id, "r").get("up", {}).get("n", ""))
	for i in n:
		if not u.alive or not foes.any(func(o): return o.alive):
			break
		_stat(u, "r")
		b._ai += 1
		b._who = u.key
		fire(u, 0, foes, allies, {"kup": nm, "again": true}, true)
		u.in_skill = false
		b._sk_on = false
		b.check_rout()
	_busy = false


## 손권 불퇴 —— 잠시 아군이 패주하지 않는다
func _ult_norout_all(u, up: Dictionary, _hits: Array, _foes_: Array, allies: Array) -> void:
	for o in allies:
		if o.alive:
			o.kt["norout_t"] = maxf(float(o.kt.get("norout_t", 0.0)), b._tm + float(up.get("sec", 5.0)))
	_kup(u, "r", "%d초 동안 아군이 패주하지 않는다" % roundi(float(up.get("sec", 5.0))))


## 감녕 그림자 · 사마의 잠행 —— 고유기 뒤 은신
func _ult_hide(u, up: Dictionary, _hits: Array, _foes_: Array, _allies_: Array) -> void:
	if not u.alive:
		return
	_hide(u, float(up.get("sec", 3.0)))
	_kup(u, "r", "%d초 동안 모습을 감춘다" % roundi(float(up.get("sec", 3.0))))


## 제갈량 팔문 —— 이 고유기의 혼란은 풀릴 때 옆 부대로 한 번 옮겨 간다 (Battle._cf_tick 이 kt_pass 를 본다)
func _ult_confuse_pass(u, _up_: Dictionary, hits: Array, _foes_: Array, _allies_: Array) -> void:
	for t in hits:
		if t.alive and t.camp != u.camp:
			var s = b._st_of(t, "confuse")
			if s != null and str(s.get("by", "")) == str(u.key) and not s.get("passed", false):
				s["kt_pass"] = u.key


## (팔문) 혼란이 풀려 옮겨 간다 —— Battle._cf_tick 이 부른다
func cf_passed(d, s: Dictionary) -> void:
	for u in ks:
		if str(u.key) == str(s.get("kt_pass", "")):
			_kup(u, "r", "%s의 혼란이 옆 부대로 옮겨 간다" % b.nm(d), str(d.key))
			return


## 주유 열화 —— 불타는 동안 그 적은 치료를 받지 못한다
func _ult_noheal_burn(u, _up_: Dictionary, hits: Array, _foes_: Array, _allies_: Array) -> void:
	var first := ""
	for t in hits:
		if t.alive and t.camp != u.camp and b.has_st(t, "burn"):
			t.kt["noheal_burn"] = true
			t.kt["noheal_by"] = [u, "r"]
			if first == "":
				first = str(t.key)
	if first != "":
		_kup(u, "r", "불타는 동안 치료를 받지 못한다", first)


## 유비 도원결의 —— 무너진 아군 1부대를 다시 일으킨다 (없으면 얼마 동안 처음 무너지는 아군을 일으켜 세운다)
func _ult_revive(u, up: Dictionary, _hits: Array, _foes_: Array, allies: Array) -> void:
	var t = null
	for o in allies:
		if not o.alive and not o.boss and o != u and (t == null or o.max > t.max):
			t = o
	var ratio := float(up.get("ratio", 0.25))
	if t == null:
		_rev[u.camp] = {"by": u, "until": b._tm + float(up.get("wait", 8.0)), "ratio": ratio}
		return
	t.alive = true
	t.troops = maxf(1.0, roundf(t.max * ratio))
	t.morale = maxf(t.morale, 60.0)
	t.st.clear()
	t.atb = 0.0
	t.tgt = null
	t.vel = Vector2.ZERO
	t.kt.clear()
	u.htr += t.troops
	_stat(u, "r")
	b.L("hl", "%s의 「%s」 —— 무너졌던 %s 다시 일어선다" % [b.nm(u), str(Kit.cell(u.c.id, "r").get("up", {}).get("n", "")), b.ga(b.nm(t))],
		{"fx": "heal", "f": t.key, "n": t.troops, "healer": u.key, "revive": true, "a": u.key, "slot": "r", "up": true, "kup": str(Kit.cell(u.c.id, "r").get("up", {}).get("n", ""))})


## 장각 태평도 —— 고유기 뒤 얼마 동안 아군이 상태이상에 걸리지 않는다
func _ult_st_immune(u, up: Dictionary, _hits: Array, _foes_: Array, _allies_: Array) -> void:
	_immune[u.camp] = [b._tm + float(up.get("sec", 6.0)), u]
	_kup(u, "r", "%d초 동안 아군이 상태이상에 걸리지 않는다" % roundi(float(up.get("sec", 6.0))))


## 조조 견제 —— 고유기가 가장 가까운 적의 고유기를 늦춘다
func _ult_ult_delay_foe(u, up: Dictionary, _hits: Array, foes: Array, _allies_: Array) -> void:
	var t = null
	for o in foes:
		if o.alive and o.ult != null and o.charges > 0 and b._wind.has(o):
			t = o
			break
	if t == null:
		for o in foes:
			if o.alive and o.ult != null and o.charges > 0 and (t == null or o.gauge > t.gauge):
				t = o
	if t == null:
		return
	_ult_delay(t, float(up.get("sec", 5.0)))
	_kup(u, "r", "%s의 고유기가 %d초 늦어진다" % [b.nm(t), roundi(float(up.get("sec", 5.0)))], str(t.key))


# ───────── 엔진이 묻는 것 (갈고리) ─────────

## 패주를 버티나 (true 면 이번 패주를 취소) —— Battle.rout 맨 앞
func hold_rout(u, cause: String) -> bool:
	if cause == "boss":
		return false
	var tm: float = b._tm
	if u.ult != null and not u.kt.get("guarded", false):      # 11/27 허저 호위무사 —— 아군 장수가 처음 무너질 때 한 번, 곁으로 달려가 버티게 한다
		for g in ks:
			if g != u and g.alive and g.camp == u.camp and not g.kt.get("p_used", false) and _upk(g, "p") == "guard_lord":
				g.kt["p_used"] = true
				u.kt["guarded"] = true
				u.kt["stand_t"] = tm + float(_up(g, "p").get("sec", 3.0))
				_run_to(g, u)
				_kup(g, "p", "%s 곁으로 달려가 지킨다" % b.nm(u), str(u.key))
				break
	if u.kit != null and not u.kt.get("stand_used", false) and _upk(u, "p") == "stand_once":      # 관우 무신 —— 처음 무너질 때 한 번
		u.kt["stand_used"] = true
		u.kt["stand_t"] = tm + float(_up(u, "p").get("sec", 4.0))
		_kup(u, "p", "쓰러지지 않고 버틴다")
	if tm < float(u.kt.get("stand_t", -1.0)):
		u.troops = maxf(u.troops, 1.0)
		u.morale = maxf(u.morale, 10.0)
		return true
	if tm < float(u.kt.get("norout_t", -1.0)) and cause != "annihilated" and u.troops > 0.0:
		u.morale = maxf(u.morale, 10.0)
		return true
	var rv = _rev.get(u.camp)
	if rv != null and not u.boss:
		_rev.erase(u.camp)
		if tm <= float(rv.until):
			var by = rv.by
			u.troops = maxf(u.troops, roundf(u.max * float(rv.ratio)))
			u.morale = maxf(u.morale, 60.0)
			by.htr += u.troops
			_stat(by, "r")
			var nm := str(Kit.cell(by.c.id, "r").get("up", {}).get("n", ""))
			b.L("hl", "%s의 「%s」 —— 무너지던 %s 다시 일어선다" % [b.nm(by), nm, b.ga(b.nm(u))],
				{"fx": "heal", "f": u.key, "n": u.troops, "healer": by.key, "revive": true, "a": by.key, "slot": "r", "up": true, "kup": nm})
			return true
	return false


## 부대가 무너졌다 —— Battle.rout (살아 있는 표시가 꺼진 뒤)
func on_fall(u) -> void:
	_p_fall(u)      # 11/27 새 신화 (동탁 주지육림 · 장로 역귀 · 태사자 유한 · 순욱 빈 찬합 · 진궁 백문루)
	if u.kit == null or _upk(u, "p") != "testament":
		return
	var up := _up(u, "p")      # 제갈량 출사표 —— 무너지면 아군 전체가 분발하고 패주하지 않는다
	var sec := float(up.get("sec", 6.0))
	var amt: float = float(DB.PSV.virtue.moved)
	for o in b.units:
		if not o.alive or o.camp != u.camp:
			continue
		o.kt["norout_t"] = maxf(float(o.kt.get("norout_t", 0.0)), b._tm + sec)
		if not o.buffs.any(func(x): return x.get("moved", false)):
			o.buffs.append({"stat": "atk", "amt": amt, "dur": ceili(sec), "moved": true})
			o.buffs.append({"stat": "int", "amt": amt, "dur": ceili(sec), "moved": true})
	_kup(u, "p", "남긴 글에 아군이 %d초 동안 분발하고 물러서지 않는다" % roundi(sec))


## 받는 피해 배율 —— 표식(받는 피해 +) · 보호(받는 피해 −)
func hit_mul(_a, d) -> float:
	var m := 1.0
	if not _pat.is_empty() and _pat.has(d.camp):      # 11/27 육손 지구전
		if b._tm < float(_pat[d.camp][0]):
			m *= 1.0 - float(_pat[d.camp][1])
		else:
			_pat.erase(d.camp)
	if d.kt.is_empty():
		return m
	var tm: float = b._tm
	if tm < float(d.kt.get("vuln_t", -1.0)):
		m *= 1.0 + float(d.kt.get("vuln", 0.0))
	if tm < float(d.kt.get("dr_t", -1.0)):
		m *= 1.0 - float(d.kt.get("dr", 0.0))
	return m


## (조조 허허실실) 이 고유기 타격을 피하나 —— 한 고유기의 타격을 모두 피하고 사라진다
func dodge(_a, d) -> bool:
	var g = d.kt.get("dodge")
	if g == null or b._ult_by == null or b._ult_by.camp == d.camp:
		return false
	var mark := [b._ult_by, int(b._ult_by.ult_n)]
	var by = d.kt.get("dodge_by")
	if by == null:
		d.kt["dodge_by"] = mark
		var src = g[0]
		_stat(src, str(g[1]))
		var nm := str(Kit.cell(src.c.id, str(g[1])).get("up", {}).get("n", ""))
		b.L("mo", "%s의 「%s」 —— %s 고유기를 피했다" % [b.nm(src), nm, b.ga(b.nm(d))], {"fx": "dodge", "a": b._ult_by.key, "f": d.key, "slot": str(g[1]), "up": true, "kup": nm})
		return true
	if by[0] == mark[0] and int(by[1]) == int(mark[1]):
		return true
	d.kt.erase("dodge")
	d.kt.erase("dodge_by")
	return false


## 치료를 받지 못하나 (병력)
func no_heal(d) -> bool:
	if b._tm < float(d.kt.get("noheal_t", -1.0)):
		_noheal_said(d)
		return true
	if d.kt.get("noheal_burn", false):
		if b.has_st(d, "burn"):
			_noheal_said(d)
			return true
		d.kt.erase("noheal_burn")
	return false


func _noheal_said(d) -> void:
	var by = d.kt.get("noheal_by")
	if by != null:
		_kup(by[0], str(by[1]), "%s 치료를 받지 못한다" % b.ga(b.nm(d)), str(d.key), SAY_GAP)


## 사기가 회복되지 않나
func no_morale(d) -> bool:
	return b._tm < float(d.kt.get("nomor_t", -1.0))


## 상태이상을 막나 (장각 태평도 —— 적이 거는 것만)
func st_block(a, d, kind: String) -> bool:
	if a != null and a.camp != d.camp and not d.kt.is_empty() and b._tm < float(d.kt.get("stimm_t", -1.0)):      # 11/27 위연 철옹성 · 순욱 천거 —— 그 부대만
		var only: Array = d.kt.get("stimm_k", [])
		if only.is_empty() or only.has(kind):
			var by = d.kt.get("stimm_by")
			if by != null:
				_stat(by[0], str(by[1]))
				var bn := str(Kit.cell(by[0].c.id, str(by[1])).get("up", {}).get("n", ""))
				b.L("st", "%s의 「%s」 —— %s 『%s』%s 받지 않는다" % [b.nm(by[0]), bn, b.ga(b.nm(d)), DB.D.STATUS[kind].n, "을" if Battle.jong(DB.D.STATUS[kind].n) else "를"],
					{"fx": "resist", "f": d.key, "st": kind, "a": by[0].key, "slot": str(by[1]), "up": true, "kup": bn})
			return true
	var im = _immune.get(d.camp)
	if im == null or a == null or a.camp == d.camp:
		return false
	if b._tm >= float(im[0]):
		_immune.erase(d.camp)
		return false
	var u = im[1]
	_stat(u, "r")
	var nm := str(Kit.cell(u.c.id, "r").get("up", {}).get("n", ""))
	b.L("st", "%s의 「%s」 —— %s 『%s』%s 받지 않는다" % [b.nm(u), nm, b.ga(b.nm(d)), DB.D.STATUS[kind].n, "을" if Battle.jong(DB.D.STATUS[kind].n) else "를"],
		{"fx": "resist", "f": d.key, "st": kind, "a": u.key, "slot": "r", "up": true, "kup": nm})
	return true


## 이 상태이상은 씻어 낼 수 없나 (장각 대현량사 —— 장각이 건 혼란)
func cleanse_block(d, s: Dictionary) -> bool:
	if str(s.get("k", "")) != "confuse":
		return false
	for u in ks:
		if u.alive and str(u.key) == str(s.get("by", "")) and _upk(u, "p") == "cf_lock":
			_kup(u, "p", "%s의 혼란은 풀어 낼 수 없다" % b.nm(d), str(d.key), SAY_GAP)
			return true
	return false


## 그 자리에 묶였나 (사마의 팔문금쇄)
func rooted(u) -> bool:
	return b._tm < float(u.kt.get("root_t", -1.0))


## 점찍은 적 (장료 팔백결사 · 유비 의형제) —— 풀렸으면 null
func force_tgt(u):
	var f = u.kt.get("ftg")
	if f == null:
		return null
	if not f.alive or b._tm >= float(u.kt.get("ftg_t", 0.0)) or b._hidden(f):
		u.kt.erase("ftg")
		u.kt.erase("ftg_t")
		return null
	return f


## 창병에게 붙잡히지 않나 (감녕 수적의 왕)
func no_hold(u, spear) -> bool:
	if u.kit == null or _upk(u, "p") != "no_hold":
		return false
	var seen: Array = u.kt.get("slip_seen", [])
	if not seen.has(spear.key):
		seen.append(spear.key)
		u.kt["slip_seen"] = seen
		_kup(u, "p", "%s의 창을 뿌리치고 빠져나간다" % b.nm(spear), str(spear.key))
	return true


## 이 고유기는 끊기지 않나 (유비 와룡출려) —— 한 번 막고 나면 그 고유기가 터질 때까지 유지
func nocut(d) -> bool:
	var g = d.kt.get("nocut")
	if g == null:
		return false
	_kup(g[0], str(g[1]), "%s의 고유기는 끊기지 않는다" % b.nm(d), str(d.key), 1.0)
	return true


## 고유기를 쐈다 —— 끊기지 않는 표시를 지운다
func ult_fired(u) -> void:
	if not u.kt.is_empty():
		u.kt.erase("nocut")


## 도발에 걸려 있으면 도발한 부대 (sig_rt 가 없는 판의 대비 —— 같은 기록 sg.tnt · tnt_t)
func taunt_of(o):
	var t = o.sg.get("tnt")
	if t == null:
		return null
	if not t.alive or b._tm >= float(o.sg.get("tnt_t", 0.0)):
		o.sg.erase("tnt")
		return null
	return t


## 도적에게 맞았다 —— 기술 대기가 조금씩 밀린다
func rogue_hit(d) -> void:
	for j in d.sk_next.size():
		d.sk_next[j] = maxf(float(d.sk_next[j]), b._tm) + ROGUE_DELAY if float(d.sk_next[j]) > b._tm else float(d.sk_next[j])


## (조조 영웅론) 간웅이 되받아쳤다 —— 그 적의 고유기 대기를 처음으로 되돌린다
func on_ult_ret(u, ra) -> void:
	if u.kit == null or _upk(u, "p") != "ret_reset" or ra == null or not ra.alive or ra.ult == null:
		return
	ra.gauge = 0.0
	ra.ult_ready_t = -1.0
	ra.ult_hold = maxf(ra.ult_hold, b._tm + float(ra.ult.get("wait", 14.0)) * b._tw(ra, "wait"))
	_kup(u, "p", "%s의 고유기 대기가 처음으로 돌아간다" % b.nm(ra), str(ra.key))


# ───────── 11/27 새 신화 11명 (장비 · 허저 · 동탁 · 황충 · 태사자 · 위연 · 여몽 · 육손 · 순욱 · 장로 · 진궁) —— 고유 동작 기술 ─────────

## 둘레 살아 있는 적 —— u 와 발자국 틈이 r 안 (가까운 순)
func _around(u, pool: Array, r: float) -> Array:
	var out: Array = pool.filter(func(o): return o.alive and not b._hidden(o) and b._gap(u, o) <= r)
	out.sort_custom(func(x, y):
		var gx: float = b._gap(u, x)
		var gy: float = b._gap(u, y)
		return gx < gy if gx != gy else str(x.key) < str(y.key))
	return out


## 적 t 의 등 뒤(적 진영 깊은 쪽)로 옮긴다 —— 감녕 백기야습과 같은 자리
func _behind(u, t) -> void:
	var back := Vector2(1.0 if u.camp == "A" else -1.0, 0.0)
	u.pos = t.pos + back * (RtBattle._extent(t, back) + RtBattle._extent(u, back) + 4.0)
	b._clamp_arena(u)
	u.vel = Vector2.ZERO
	u.fwd = -back
	u.tgt = t
	u.retgt = 0.5
	u.ran = 0.0


## t 곁으로 달려간다 (t 쪽으로 붙어 선다)
func _run_to(u, t) -> void:
	var dir := _dir_to(u, t)
	var stop: Vector2 = t.pos - dir * (RtBattle._extent(t, dir) + RtBattle._extent(u, dir) + 4.0)
	if (stop - u.pos).dot(dir) > 0.0:
		b._mark(u, {"k": "line", "x": u.pos.x, "y": u.pos.y, "x2": stop.x, "y2": stop.y, "w": 40.0})
		u.pos = stop
		b._clamp_arena(u)
		u.vel = Vector2.ZERO
	u.fwd = dir
	u.ran = 0.0


## 장비 장판교 —— 둘레 적 n 부대를 도발해 끌어들이고 잠시 받는 피해를 덜 받는다 (강화 단교는 root_st 가 이 적들을 묶는다)
func _act_bridge(u, slot: String, sk: Dictionary, _up_: Dictionary, foes: Array, _allies_: Array) -> Array:
	var e: Dictionary = sk.eff
	var live := _live(foes)
	if live.is_empty():
		return []
	var near := _around(u, live, 400.0).slice(0, int(e.get("n", 3)))
	if near.is_empty():
		near = [b._nearest(u.pos, live)]
	var sec := float(e.get("sec", 4.0))
	for o in near:
		o.sg["tnt"] = u
		o.sg["tnt_t"] = b._tm + sec
	u.kt["dr"] = float(e.get("dr", 0.35))
	u.kt["dr_t"] = b._tm + sec
	b._mark(u, {"k": "circle", "x": roundi(u.pos.x), "y": roundi(u.pos.y), "r": 90})
	b.L("sk", "『%s』 —— %s 다리목을 막아서 적 %d부대를 끌어들인다 (%d초 동안 받는 피해 −%d%%)" % [str(sk.n), b.ga(b.nm(u)), near.size(), roundi(sec), roundi(float(e.get("dr", 0.35)) * 100)],
		{"fx": "buff", "f": u.key, "up": true})
	return near


## 허저 일기토 —— 가장 강한 근접 적 장수와 서로만 노린다 (허저 공격 +)
func _act_duel(u, slot: String, sk: Dictionary, _up_: Dictionary, foes: Array, _allies_: Array) -> Array:
	var e: Dictionary = sk.eff
	var live := _live(foes)
	if live.is_empty():
		return []
	var melee := live.filter(func(o): return not o.ranged)
	var t = _top_gen(melee if not melee.is_empty() else live)
	if t == null:
		return []
	var sec := float(e.get("sec", 5.0))
	u.kt["ftg"] = t
	u.kt["ftg_t"] = b._tm + sec
	u.tgt = t
	u.retgt = 0.5
	t.sg["tnt"] = u
	t.sg["tnt_t"] = b._tm + sec
	b.add_buff(u, {"stat": "atk", "amt": float(e.get("atk", 0.3)), "dur": ceili(sec)}, "sk:" + str(sk.n))
	b._mark(u, {"k": "line", "x": u.pos.x, "y": u.pos.y, "x2": t.pos.x, "y2": t.pos.y, "w": 30.0})
	b.L("sk", "『%s』 —— %s %s에게 일기토를 청한다 (%d초)" % [str(sk.n), b.ga(b.nm(u)), b.nm(t), roundi(sec)], {"fx": "debuff", "a": u.key, "f": t.key})
	b.phys_hit(u, t, float(e.get("mult", 1.2)), true)
	return [t]


## 허저 견우백보 —— 가장 먼 근접 적 1부대를 끌어당겨 친다 (묶임은 덧붙임 root)
func _act_pull(u, slot: String, sk: Dictionary, _up_: Dictionary, foes: Array, _allies_: Array) -> Array:
	var live := _live(foes)
	if live.is_empty():
		return []
	var melee := live.filter(func(o): return not o.ranged)
	var t = _farthest(u, melee if not melee.is_empty() else live)
	var dir := _dir_to(u, t)
	var from: Vector2 = t.pos
	t.pos = u.pos + dir * (RtBattle._extent(u, dir) + RtBattle._extent(t, dir) + 4.0)
	b._clamp_arena(t)
	t.vel = Vector2.ZERO
	t.atb = maxf(0.0, t.atb - STAGGER)
	b._mark(u, {"k": "line", "x": from.x, "y": from.y, "x2": t.pos.x, "y2": t.pos.y, "w": 30.0})
	b.L("mo", "%s 끌려왔다" % b.ga(b.nm(t)), {"fx": "push", "f": t.key, "a": u.key, "push": true})
	_hit(u, t, float(sk.eff.mult), 1)
	return [t]


## 동탁 서량철기 —— 병력이 가장 꺾인 적 1부대에 달려들어 강타 (병력이 문턱 아래면 이탈)
func _act_prey(u, slot: String, sk: Dictionary, _up_: Dictionary, foes: Array, _allies_: Array) -> Array:
	var e: Dictionary = sk.eff
	var live := _live(foes)
	if live.is_empty():
		return []
	var t = live[0]
	for o in live:
		if o.troops / o.max < t.troops / t.max:
			t = o
	_run_to(u, t)
	u.tgt = t
	u.retgt = 0.5
	b.phys_hit(u, t, float(e.mult), false)
	if t.alive and t.troops > 0 and t.troops / t.max <= float(e.get("exec", 0.0)):
		b.rout(t, "서량 철기에 짓밟혔다")
	return [t]


## 동탁 상국의 위세 —— 적 전체 사기 타격 · 잠시 공격 감소
func _act_cow(u, slot: String, sk: Dictionary, _up_: Dictionary, foes: Array, _allies_: Array) -> Array:
	var e: Dictionary = sk.eff
	var live := _live(foes)
	for o in live:
		b.morale_hit(o, float(e.get("morale", 10.0)), str(sk.n), live.size(), u)
		b.add_buff(o, {"stat": "atk", "amt": float(e.get("atk", -0.15)), "dur": int(e.get("sec", 4))}, "sk:" + str(sk.n))
	return live


## 황충 일시관천 —— 가장 먼 적까지 꿰뚫는 화살, 지나는 길의 적 모두
func _act_lance_shot(u, slot: String, sk: Dictionary, _up_: Dictionary, foes: Array, _allies_: Array) -> Array:
	var live := _live(foes)
	if live.is_empty():
		return []
	var t = _farthest(u, live)
	var dir := _dir_to(u, t)
	var hit := _band(live, u.pos, dir, u.pos.distance_to(t.pos), float(sk.eff.get("w", 24.0)))
	if not hit.has(t):
		hit.append(t)
	b._mark(u, {"k": "line", "x": u.pos.x, "y": u.pos.y, "x2": t.pos.x, "y2": t.pos.y, "w": 14.0})
	for o in hit:
		if o.alive:
			b.phys_hit(u, o, float(sk.eff.mult), true)
	return hit


## 황충 노장분전 —— 가장 먼 적 2부대 사격, 자신의 병력이 꺾였으면 더 세다
func _act_low_shot(u, slot: String, sk: Dictionary, _up_: Dictionary, foes: Array, _allies_: Array) -> Array:
	var e: Dictionary = sk.eff
	var live := _live(foes)
	if live.is_empty():
		return []
	live.sort_custom(func(x, y):
		var dx: float = x.pos.distance_squared_to(u.pos)
		var dy: float = y.pos.distance_squared_to(u.pos)
		return dx > dy if dx != dy else str(x.key) < str(y.key))
	var ts: Array = live.slice(0, int(e.get("n", 2)))
	var m := float(e.mult) * (float(e.get("x", 1.5)) if u.troops < u.max * float(e.get("below", 0.5)) else 1.0)
	b._mark_targets(u, ts)
	for o in ts:
		if o.alive:
			b.phys_hit(u, o, m, true)
	return ts


## 태사자 쌍극난타 —— 가까운 적 2부대를 치고 뒤로 물러난다
func _act_strike_back(u, slot: String, sk: Dictionary, _up_: Dictionary, foes: Array, _allies_: Array) -> Array:
	var e: Dictionary = sk.eff
	var ts := _around(u, _live(foes), 9999.0).slice(0, int(e.get("n", 2)))
	if ts.is_empty():
		return []
	b._mark_targets(u, ts)
	for o in ts:
		if o.alive:
			b.phys_hit(u, o, float(e.mult), true)
	if u.alive:
		var away: Vector2 = u.pos - ts[0].pos
		var dir: Vector2 = away.normalized() if away.length() > 0.1 else -u.fwd
		u.pos += dir * float(e.get("px", 90.0))
		b._clamp_arena(u)
		u.vel = Vector2.ZERO
	return ts


## 태사자 북해구원 —— 가장 위태로운 아군에게 붙은 적을 쏘아 밀어낸다 (붙은 적이 없으면 그 아군에게 가장 가까운 적)
func _act_rescue_shot(u, slot: String, sk: Dictionary, _up_: Dictionary, foes: Array, allies: Array) -> Array:
	var e: Dictionary = sk.eff
	var w = _weakest(allies)
	var live := _live(foes)
	if w == null or live.is_empty():
		return []
	var ts := _touching(w)
	if ts.is_empty():
		ts = [b._nearest(w.pos, live)]
	for o in ts:
		b._mark(u, {"k": "line", "x": u.pos.x, "y": u.pos.y, "x2": o.pos.x, "y2": o.pos.y, "w": 10.0})
		if o.alive:
			b.phys_hit(u, o, float(e.mult), true)
		if o.alive:
			_push(w, o, float(e.get("px", 60.0)), u)
	return ts


## 위연 자오곡 —— 가장 강한 적 장수의 등 뒤에 나타나 친다 (고유기 지연은 덧붙임 udelay)
func _act_ambush_gen(u, slot: String, sk: Dictionary, _up_: Dictionary, foes: Array, _allies_: Array) -> Array:
	var t = _top_gen(_live(foes))
	if t == null:
		return []
	_behind(u, t)
	b._mark(u, {"k": "circle", "x": roundi(t.pos.x), "y": roundi(t.pos.y), "r": 60})
	b.phys_hit(u, t, float(sk.eff.mult), false)
	return [t]


## 위연 한중진수 —— 그 자리를 지키며 받는 피해를 덜고 되받아친다
func _act_hold_ground(u, slot: String, sk: Dictionary, _up_: Dictionary, _foes_: Array, _allies_: Array) -> Array:
	var e: Dictionary = sk.eff
	var sec := float(e.get("sec", 4.0))
	u.kt["dr"] = float(e.get("dr", 0.3))
	u.kt["dr_t"] = b._tm + sec
	u.kt["root_t"] = maxf(float(u.kt.get("root_t", 0.0)), b._tm + sec)
	u.vel = Vector2.ZERO
	u.buffs.append({"stat": "counter", "amt": float(e.get("counter", 0.5)), "dur": ceili(sec)})
	b.L("sk", "『%s』 —— %s 자리를 지킨다 (%d초 동안 받는 피해 −%d%% · 되받아치기)" % [str(sk.n), b.ga(b.nm(u)), roundi(sec), roundi(float(e.get("dr", 0.3)) * 100)],
		{"fx": "buff", "f": u.key, "up": true})
	return []


## 여몽 형주기습 —— 적 후열 무리 한가운데 나타나 둘레 적을 치고 몸을 감춘다
func _act_cross_river(u, slot: String, sk: Dictionary, _up_: Dictionary, foes: Array, _allies_: Array) -> Array:
	var e: Dictionary = sk.eff
	var live := _live(foes)
	if live.is_empty():
		return []
	var t = b._deepest(u, live)
	_behind(u, t)
	var hit := _around(u, live, float(e.get("r", 90.0)))
	if not hit.has(t):
		hit.push_front(t)
	b._mark(u, {"k": "circle", "x": roundi(u.pos.x), "y": roundi(u.pos.y), "r": roundi(float(e.get("r", 90.0)))})
	for o in hit:
		if o.alive and u.alive:
			_hit(u, o, float(e.mult), hit.size())
	if u.alive:
		_hide(u, float(e.get("hide", 2.0)))
	return hit


## 육손 연영소각 —— 가장 가까운 적부터 이어 붙은 적들로 불길을 이어 놓는다
func _act_fire_chain(u, slot: String, sk: Dictionary, _up_: Dictionary, foes: Array, _allies_: Array) -> Array:
	var e: Dictionary = sk.eff
	var live := _live(foes)
	if live.is_empty():
		return []
	var chain := [b._nearest(u.pos, live)]
	while chain.size() < int(e.get("n", 4)):
		var nx = _beside(chain[chain.size() - 1], live, float(e.get("r", 110.0)), chain)
		if nx == null:
			break
		chain.append(nx)
	b._mark_targets(u, chain)
	var st: Dictionary = e.get("burn", {"val": 0.14, "dur": 3})
	for o in chain:
		if o.alive:
			_hit(u, o, float(e.mult), chain.size())
		if o.alive:
			b.inflict(u, o, "burn", float(st.val), int(st.dur))
	return chain


## 육손 백면서생 —— 적 전체에 표식(받는 피해 +), 가장 강한 적 장수의 고유기를 늦춘다
func _act_scorn(u, slot: String, sk: Dictionary, _up_: Dictionary, foes: Array, _allies_: Array) -> Array:
	var e: Dictionary = sk.eff
	var live := _live(foes)
	if live.is_empty():
		return []
	var sec := float(e.get("sec", 4.0))
	for o in live:
		o.kt["vuln"] = maxf(float(o.kt.get("vuln", 0.0)) if b._tm < float(o.kt.get("vuln_t", -1.0)) else 0.0, float(e.get("vuln", 0.15)))
		o.kt["vuln_t"] = maxf(float(o.kt.get("vuln_t", 0.0)), b._tm + sec)
	var t = _top_gen(live)
	if t != null:
		_ult_delay(t, float(e.get("udelay_top", 3.0)))
	b.L("sk", "『%s』 —— 적이 얕보고 방심한다 (%d초 동안 받는 피해 +%d%%)%s" % [str(sk.n), roundi(sec), roundi(float(e.get("vuln", 0.15)) * 100), (" · %s의 고유기가 늦어진다" % b.nm(t)) if t != null else ""],
		{"fx": "debuff", "a": u.key, "f": t.key if t != null else u.key})
	return live


## 순욱 인재천거 —— 기술 대기가 가장 많이 남은 아군 n 부대의 기술을 당긴다
func _act_recommend(u, slot: String, sk: Dictionary, _up_: Dictionary, _foes_: Array, allies: Array) -> Array:
	var e: Dictionary = sk.eff
	var al: Array = allies.filter(func(o): return o.alive and o != u and not (o.c.get("sks", []) as Array).is_empty())
	if al.is_empty():
		return []
	var left := {}
	for o in al:
		var m := 0.0
		if o.kit != null:
			for x in o.sk_next:
				m = maxf(m, float(x) - b._tm)
		else:
			m = 1.0 - (float(o.sk_ch[0]) if not o.sk_ch.is_empty() else 0.0)
		left[o] = m
	al.sort_custom(func(x, y): return float(left[x]) > float(left[y]) if float(left[x]) != float(left[y]) else str(x.key) < str(y.key))
	al = al.slice(0, int(e.get("n", 2)))
	var sec := float(e.get("sec", 3.0))
	for o in al:
		_sk_haste(o, sec, null, -1)
	b.L("sk", "『%s』 —— %s의 기술이 %d초 빨라진다" % [str(sk.n), ", ".join(al.map(func(o): return b.nm(o))), roundi(sec)], {"fx": "buff", "f": al[0].key, "up": true})
	return al


## 순욱 순령유향 —— 아군 전체 사기 + · 잠시 받는 피해 −
func _act_fragrance(u, slot: String, sk: Dictionary, _up_: Dictionary, _foes_: Array, allies: Array) -> Array:
	var e: Dictionary = sk.eff
	var sec := float(e.get("sec", 4.0))
	for o in allies:
		if not o.alive:
			continue
		b._rally(o, float(e.get("morale", 12.0)), str(sk.n), false)
		if not (b._tm < float(o.kt.get("dr_t", -1.0)) and float(o.kt.get("dr", 0.0)) > float(e.get("dr", 0.15))):
			o.kt["dr"] = float(e.get("dr", 0.15))
			o.kt["dr_t"] = b._tm + sec
	b.L("sk", "『%s』 —— 향기가 아군에 머문다 (사기 +%d · %d초 동안 받는 피해 −%d%%)" % [str(sk.n), roundi(float(e.get("morale", 12.0))), roundi(sec), roundi(float(e.get("dr", 0.15)) * 100)],
		{"fx": "buff", "f": u.key, "up": true})
	return []


## 장로 오두미 —— 아군 전체 병력 회복 · 상태이상 하나씩 씻기
func _act_rice(u, slot: String, sk: Dictionary, _up_: Dictionary, _foes_: Array, allies: Array) -> Array:
	var e: Dictionary = sk.eff
	for o in allies:
		if not o.alive:
			continue
		b.heal_troop(o, float(e.get("heal", 0.06)), str(sk.n), u)
		for i in int(e.get("cleanse", 1)):
			if not b.cleanse(o):
				break
	return []


## 진궁 여포영입 —— 가장 강한 아군 근접 장수를 적 후열로 풀어 놓는다 (공격 +)
func _act_unleash(u, slot: String, sk: Dictionary, _up_: Dictionary, foes: Array, allies: Array) -> Array:
	var e: Dictionary = sk.eff
	var live := _live(foes)
	var al: Array = allies.filter(func(o): return o.alive and o != u and not o.ranged)
	if al.is_empty() or live.is_empty():
		return []
	var t = _top_gen(al)
	var f = b._deepest(t, live)
	var sec := float(e.get("sec", 5.0))
	t.kt["ftg"] = f
	t.kt["ftg_t"] = b._tm + sec
	t.tgt = f
	b.add_buff(t, {"stat": "atk", "amt": float(e.get("atk", 0.3)), "dur": ceili(sec)}, "sk:" + str(sk.n))
	b.L("sk", "『%s』 —— %s %s에게 달려든다 (%d초 동안 공격 +%d%%)" % [str(sk.n), b.ga(b.nm(t)), b.nm(f), roundi(sec), roundi(float(e.get("atk", 0.3)) * 100)], {"fx": "buff", "f": t.key, "up": true})
	return [t]


# ───────── 11/27 새 신화 11명 —— 기술 강화 효과 (fx.k) ─────────

## 장비 포효 —— 맞은 적 가운데 사기가 가장 낮은 n 부대 혼란
func _up_confuse_hit(u, j: int, _sk: Dictionary, up: Dictionary, hit: Array, _foes_: Array, _allies_: Array) -> void:
	var pool: Array = hit.filter(func(t): return t.alive and t.camp != u.camp and not b.has_st(t, "confuse"))
	pool.sort_custom(func(x, y): return x.morale < y.morale if x.morale != y.morale else str(x.key) < str(y.key))
	var n := 0
	var first := ""
	for t in pool.slice(0, int(up.get("n", 2))):
		if _confuse(u, t, float(up.get("sec", 1.5))):
			if first == "":
				first = str(t.key)
			n += 1
	if n > 0:
		_kup(u, Kit.SLOTS[j], "겁에 질린 적 %d부대가 혼란에 빠진다" % n, first)


## 장비 만부부당 —— 이 기술로 적을 무너뜨리면 둘레 적 사기 −
func _up_kill_fear(u, j: int, _sk: Dictionary, up: Dictionary, hit: Array, foes: Array, _allies_: Array) -> void:
	if not hit.any(func(o): return not o.alive):
		return
	var n := 0
	for o in _around(u, _live(foes), float(up.get("r", 150.0))):
		o.morale -= float(up.get("morale", 20.0))
		n += 1
	_kup(u, Kit.SLOTS[j], "적을 베어 넘기자 둘레 적 %d부대의 사기가 꺾인다" % n)


## 허저 호위 —— 가장 위태로운 아군 1부대가 잠시 받는 피해를 덜 받는다
func _up_guard_ally(u, j: int, _sk: Dictionary, up: Dictionary, _hit: Array, _foes_: Array, allies: Array) -> void:
	var t = _weakest(allies)
	if t == null:
		return
	t.kt["dr"] = maxf(float(t.kt.get("dr", 0.0)) if b._tm < float(t.kt.get("dr_t", -1.0)) else 0.0, float(up.get("dr", 0.4)))
	t.kt["dr_t"] = maxf(float(t.kt.get("dr_t", 0.0)), b._tm + float(up.get("sec", 3.0)))
	_kup(u, Kit.SLOTS[j], "%s 지킨다 (%d초 동안 받는 피해 −%d%%)" % [b.eul(b.nm(t)), roundi(float(up.get("sec", 3.0))), roundi(float(up.get("dr", 0.4)) * 100)], str(t.key))


## 허저 견인 —— 맞은 첫 적 둘레의 다른 적에게도 피해
func _up_splash(u, j: int, _sk: Dictionary, up: Dictionary, hit: Array, foes: Array, _allies_: Array) -> void:
	if hit.is_empty() or not u.alive:
		return
	var t0 = hit[0]
	var got := _live(foes).filter(func(o): return not hit.has(o) and b._gap(o, t0) <= float(up.get("r", 90.0)))
	if got.is_empty():
		return
	_kup(u, Kit.SLOTS[j], "둘레 적 %d부대가 함께 휩쓸린다" % got.size(), str(got[0].key))
	for o in got:
		if o.alive and u.alive:
			_hit(u, o, float(up.get("mult", 0.8)), got.size())


## 동탁 약탈 —— 맞은 적 가운데 그 상태이상(st)에 걸린 적에게서 사기를 빼앗는다
func _up_msteal_st(u, j: int, _sk: Dictionary, up: Dictionary, hit: Array, _foes_: Array, _allies_: Array) -> void:
	var tot := 0.0
	var first := ""
	for t in hit:
		if not t.alive or t.camp == u.camp or not b.has_st(t, str(up.get("st", "burn"))):
			continue
		var ms := minf(float(up.get("m", 8.0)), maxf(0.0, t.morale))
		t.morale -= ms
		u.morale = minf(200.0, u.morale + ms)
		u.mdmg += ms
		tot += ms
		if first == "":
			first = str(t.key)
	if tot > 0.0:
		_kup(u, Kit.SLOTS[j], "불탄 적에게서 사기 %d를 빼앗는다" % roundi(tot), first)


## 동탁 포식 —— 이 기술로 적을 무너뜨리면 병력 회복
func _up_kill_heal(u, j: int, _sk: Dictionary, up: Dictionary, hit: Array, _foes_: Array, _allies_: Array) -> void:
	if not u.alive or not hit.any(func(o): return not o.alive):
		return
	_self_heal(u, float(up.get("ratio", 0.1)), Kit.SLOTS[j])
	_kup(u, Kit.SLOTS[j], "무너뜨린 적을 삼켜 병력을 되찾는다")


## 동탁 천도 —— 맞은 적 가운데 사기가 가장 낮은 1부대를 적진 뒤쪽으로 밀어낸다
func _up_push_low(u, j: int, _sk: Dictionary, up: Dictionary, hit: Array, _foes_: Array, _allies_: Array) -> void:
	var t = null
	for o in hit:
		if o.alive and o.camp != u.camp and (t == null or o.morale < t.morale):
			t = o
	if t == null:
		return
	var back := Vector2(1.0 if u.camp == "A" else -1.0, 0.0)
	_shove(t, back * float(up.get("px", 100.0)), u)
	_kup(u, Kit.SLOTS[j], "%s 적진 뒤로 끌려간다" % b.ga(b.nm(t)), str(t.key))


## 황충 일전필살 —— 이 기술로 적을 무너뜨리면 기술 대기가 모두 풀린다
func _up_kill_reset(u, j: int, _sk: Dictionary, _up_: Dictionary, hit: Array, _foes_: Array, _allies_: Array) -> void:
	if not u.alive or not hit.any(func(o): return not o.alive):
		return
	for jj in u.sk_next.size():
		u.sk_next[jj] = minf(float(u.sk_next[jj]), b._tm)
	_kup(u, Kit.SLOTS[j], "기술이 모두 다시 준비된다")


## 황충 노당익장 —— 쏠 때마다 사기 +, 병력이 꺾였으면 병력도 조금
func _up_self_rally(u, j: int, _sk: Dictionary, up: Dictionary, _hit: Array, _foes_: Array, _allies_: Array) -> void:
	if not u.alive:
		return
	var nm := str(Kit.cell(u.c.id, Kit.SLOTS[j]).get("up", {}).get("n", ""))
	b._rally(u, float(up.get("morale", 15.0)), nm, false)
	var heal: bool = u.troops < u.max * float(up.get("below", 0.6))
	if heal:
		_self_heal(u, float(up.get("heal", 0.08)), Kit.SLOTS[j])
	_kup(u, Kit.SLOTS[j], "늙은 장수가 기운을 낸다 (사기 +%d%s)" % [roundi(float(up.get("morale", 15.0))), " · 병력 회복" if heal else ""])


## 태사자 탈투 —— 맞은 적에게 걸린 이로운 효과(능력치 강화)를 벗겨 낸다
func _up_strip(u, j: int, _sk: Dictionary, _up_: Dictionary, hit: Array, _foes_: Array, _allies_: Array) -> void:
	var n := 0
	var first := ""
	for t in hit:
		if not t.alive or t.camp == u.camp:
			continue
		var before: int = t.buffs.size()
		t.buffs = t.buffs.filter(func(x): return float(x.get("amt", 0.0)) <= 0.0 or str(x.get("stat", "")) == "counter")
		if t.buffs.size() < before:
			n += before - t.buffs.size()
			if first == "":
				first = str(t.key)
	if n > 0:
		_kup(u, Kit.SLOTS[j], "적의 강화 %d개를 벗겨 낸다" % n, first)


## 위연 반골 —— 맞은 적 1부대가 혼란에 빠져 옆의 제 편을 친다
func _up_incite(u, j: int, _sk: Dictionary, up: Dictionary, hit: Array, foes: Array, _allies_: Array) -> void:
	for t in hit:
		if not t.alive or t.camp == u.camp or b.has_st(t, "confuse"):
			continue
		if not _confuse(u, t, float(up.get("sec", 1.5))):
			continue
		var best = _beside(t, foes, float(up.get("r", 120.0)))
		if best != null:
			_kup(u, Kit.SLOTS[j], "%s 등을 돌려 제 편 %s 친다" % [b.ga(b.nm(t)), b.eul(b.nm(best))], str(t.key))
			if b.is_caster(t.c):
				b.int_hit(t, best, float(up.get("mult", 0.8)), 1)
			else:
				b.phys_hit(t, best, float(up.get("mult", 0.8)), true)
		else:
			_kup(u, Kit.SLOTS[j], "%s 혼란에 빠진다" % b.ga(b.nm(t)), str(t.key))
		return


## 위연 잠복 —— 친 뒤 잠시 은신
func _up_hide_self(u, j: int, _sk: Dictionary, up: Dictionary, _hit: Array, _foes_: Array, _allies_: Array) -> void:
	if not u.alive:
		return
	_hide(u, float(up.get("sec", 2.0)))
	_kup(u, Kit.SLOTS[j], "%d초 동안 모습을 감춘다" % roundi(float(up.get("sec", 2.0))))


## 위연 철옹성 —— 버티는 동안 상태이상에 걸리지 않는다 (걸려 있던 것도 턴다)
func _up_st_guard(u, j: int, _sk: Dictionary, up: Dictionary, _hit: Array, _foes_: Array, _allies_: Array) -> void:
	if not u.alive:
		return
	var n := 0
	while n < 4 and b.cleanse(u):
		n += 1
	u.kt["stimm_t"] = b._tm + float(up.get("sec", 4.0))
	u.kt["stimm_k"] = []
	u.kt["stimm_by"] = [u, Kit.SLOTS[j]]
	_kup(u, Kit.SLOTS[j], "%d초 동안 상태이상에 걸리지 않는다" % roundi(float(up.get("sec", 4.0))))


## 순욱 천거 —— 당겨 준 아군이 잠시 혼란 · 봉인에 걸리지 않는다
func _up_st_guard_ally(u, j: int, _sk: Dictionary, up: Dictionary, hit: Array, _foes_: Array, _allies_: Array) -> void:
	var n := 0
	var first := ""
	for o in hit:
		if o.alive and o.camp == u.camp:
			o.kt["stimm_t"] = b._tm + float(up.get("sec", 4.0))
			o.kt["stimm_k"] = ["confuse", "seal"]
			o.kt["stimm_by"] = [u, Kit.SLOTS[j]]
			if first == "":
				first = str(o.key)
			n += 1
	if n > 0:
		_kup(u, Kit.SLOTS[j], "아군 %d부대가 %d초 동안 혼란 · 봉인에 걸리지 않는다" % [n, roundi(float(up.get("sec", 4.0)))], first)


## 여몽 수공 · 육손 퇴로차단 · 장비 단교 —— 맞은 적(st 가 있으면 그 상태이상에 걸린 적만)이 그 자리에 묶인다
func _up_root_st(u, j: int, _sk: Dictionary, up: Dictionary, hit: Array, _foes_: Array, _allies_: Array) -> void:
	var st := str(up.get("st", ""))
	var n := 0
	var first := ""
	for t in hit:
		if not t.alive or t.camp == u.camp or (st != "" and not b.has_st(t, st)):
			continue
		t.kt["root_t"] = maxf(float(t.kt.get("root_t", 0.0)), b._tm + float(up.get("sec", 2.0)))
		t.vel = Vector2.ZERO
		if first == "":
			first = str(t.key)
		n += 1
	if n > 0:
		_kup(u, Kit.SLOTS[j], "적 %d부대가 %d초 동안 그 자리에 묶인다" % [n, roundi(float(up.get("sec", 2.0)))], first)


## 여몽 사별삼일 · 장로 귀신들림 —— 맞은 적의 기술 대기가 밀린다
func _up_sk_delay(u, j: int, _sk: Dictionary, up: Dictionary, hit: Array, _foes_: Array, _allies_: Array) -> void:
	var n := 0
	var first := ""
	for t in hit:
		if not t.alive or t.camp == u.camp or (t.c.get("sks", []) as Array).is_empty():
			continue
		_sk_slow(t, float(up.get("sec", 3.0)))
		if first == "":
			first = str(t.key)
		n += 1
	if n > 0:
		_kup(u, Kit.SLOTS[j], "적 %d부대의 기술이 %d초 늦어진다" % [n, roundi(float(up.get("sec", 3.0)))], first)


## 여몽 생포 —— 맞은 적 가운데 병력이 가장 적은 1부대를 묶고 봉인
func _up_capture(u, j: int, _sk: Dictionary, up: Dictionary, hit: Array, _foes_: Array, _allies_: Array) -> void:
	var t = null
	for o in hit:
		if o.alive and o.camp != u.camp and (t == null or o.troops < t.troops):
			t = o
	if t == null:
		return
	var sec := float(up.get("sec", 3.0))
	t.kt["root_t"] = maxf(float(t.kt.get("root_t", 0.0)), b._tm + sec)
	t.vel = Vector2.ZERO
	_seal(u, t, sec)
	_kup(u, Kit.SLOTS[j], "%s 사로잡는다 (%d초 묶임 · 봉인)" % [b.eul(b.nm(t)), roundi(sec)], str(t.key))


## 육손 화공 —— 불붙은 적에서 불길이 치솟아 둘레의 다른 적에게도 피해
func _up_burst_burn(u, j: int, _sk: Dictionary, up: Dictionary, hit: Array, foes: Array, _allies_: Array) -> void:
	var src = null
	for t in hit:
		if t.alive and b.has_st(t, "burn"):
			src = t
			break
	if src == null or not u.alive:
		return
	var got := _live(foes).filter(func(o): return o != src and b._gap(o, src) <= float(up.get("r", 90.0)))
	if got.is_empty():
		return
	_kup(u, Kit.SLOTS[j], "불길이 치솟아 둘레 적 %d부대를 덮친다" % got.size(), str(src.key))
	for o in got:
		if o.alive and u.alive:
			_hit(u, o, float(up.get("mult", 0.6)), got.size())


## 육손 방심 —— 맞은 적은 잠시 사기가 회복되지 않는다
func _up_nomor_hit(u, j: int, _sk: Dictionary, up: Dictionary, hit: Array, _foes_: Array, _allies_: Array) -> void:
	var n := 0
	for t in hit:
		if t.alive and t.camp != u.camp:
			t.kt["nomor_t"] = maxf(float(t.kt.get("nomor_t", 0.0)), b._tm + float(up.get("sec", 4.0)))
			n += 1
	if n > 0:
		_kup(u, Kit.SLOTS[j], "방심한 적 %d부대의 사기가 %d초 동안 회복되지 않는다" % [n, roundi(float(up.get("sec", 4.0)))])


## 순욱 구현 —— 상태이상이 가장 많은 아군 1부대를 모두 씻는다
func _up_cleanse_weak(u, j: int, _sk: Dictionary, _up_: Dictionary, _hit: Array, _foes_: Array, allies: Array) -> void:
	var t = null
	for o in allies:
		if o.alive and not o.st.is_empty() and (t == null or o.st.size() > t.st.size()):
			t = o
	if t == null:
		return
	var n := 0
	while n < 4 and b.cleanse(t):
		n += 1
	if n > 0:
		_kup(u, Kit.SLOTS[j], "%s의 상태이상 %d개를 씻는다" % [b.nm(t), n], str(t.key))


## 순욱 유향 —— 아군 전체 병력 회복
func _up_heal_all(u, j: int, _sk: Dictionary, up: Dictionary, _hit: Array, _foes_: Array, allies: Array) -> void:
	var nm := str(Kit.cell(u.c.id, Kit.SLOTS[j]).get("up", {}).get("n", ""))
	for o in allies:
		if o.alive:
			b.heal_troop(o, float(up.get("ratio", 0.04)), nm, u)
	_kup(u, Kit.SLOTS[j], "향기가 머문 아군의 병력이 회복된다")


## 장로 의사 —— 그 상태이상에 걸린 적 하나마다 아군 병력 회복
func _up_heal_by_st(u, j: int, _sk: Dictionary, up: Dictionary, _hit: Array, foes: Array, allies: Array) -> void:
	var n := 0
	for o in foes:
		if o.alive and b.has_st(o, str(up.get("st", "plague"))):
			n += 1
	if n <= 0:
		return
	var ratio := minf(float(up.get("max", 0.06)), float(up.get("per", 0.01)) * n)
	var nm := str(Kit.cell(u.c.id, Kit.SLOTS[j]).get("up", {}).get("n", ""))
	for o in allies:
		if o.alive:
			b.heal_troop(o, ratio, nm, u)
	_kup(u, Kit.SLOTS[j], "병든 적 %d부대만큼 아군이 회복된다 (병력 +%d%%)" % [n, roundi(ratio * 100)])


## 장로 정실 —— 가장 위태로운 아군 1부대가 잠시 표적이 되지 않는다
func _up_hide_ally(u, j: int, _sk: Dictionary, up: Dictionary, _hit: Array, _foes_: Array, allies: Array) -> void:
	var t = _weakest(allies)
	if t == null:
		return
	_hide(t, float(up.get("sec", 3.0)))
	_kup(u, Kit.SLOTS[j], "%s 정실에 숨긴다 (%d초 동안 표적이 되지 않는다)" % [b.eul(b.nm(t)), roundi(float(up.get("sec", 3.0)))], str(t.key))


## 진궁 비장 —— 풀어 놓은 아군 장수의 고유기를 당긴다
func _up_unleash_ult(u, j: int, _sk: Dictionary, up: Dictionary, hit: Array, _foes_: Array, _allies_: Array) -> void:
	for o in hit:
		if o.alive and o.camp == u.camp and o.ult != null and o.charges > 0:
			_ult_haste(o, float(up.get("sec", 3.0)))
			_kup(u, Kit.SLOTS[j], "%s의 고유기가 %d초 앞당겨진다" % [b.nm(o), roundi(float(up.get("sec", 3.0)))], str(o.key))
			return


# ───────── 11/27 새 신화 11명 —— 고유기 강화 효과 (r 칸 fx.k) ─────────

## 장비 호통 —— 고유기에 맞은 적이 그 자리에 얼어붙는다
func _ult_root(u, up: Dictionary, hits: Array, _foes_: Array, _allies_: Array) -> void:
	var n := 0
	var first := ""
	for t in hits:
		if t.alive and t.camp != u.camp:
			t.kt["root_t"] = maxf(float(t.kt.get("root_t", 0.0)), b._tm + float(up.get("sec", 2.0)))
			t.vel = Vector2.ZERO
			if first == "":
				first = str(t.key)
			n += 1
	if n > 0:
		_kup(u, "r", "적 %d부대가 %d초 동안 얼어붙는다" % [n, roundi(float(up.get("sec", 2.0)))], first)


## 허저 호치 —— 고유기로 적을 무너뜨리면 고유기 기를 되찾는다
func _ult_refund(u, up: Dictionary, hits: Array, _foes_: Array, _allies_: Array) -> void:
	if not u.alive or u.charges <= 0 or not hits.any(func(t): return not t.alive and t.camp != u.camp):
		return
	u.gauge = minf(100.0, u.gauge + 100.0 * float(up.get("ratio", 0.5)))
	_kup(u, "r", "고유기 기를 %d%% 되찾는다" % roundi(float(up.get("ratio", 0.5)) * 100))


## 동탁 겁화 · 장로 봉고 —— 고유기에 맞은 적이 잠시 사기 회복(morale) · 치료(heal)를 받지 못한다
func _ult_deny(u, up: Dictionary, hits: Array, _foes_: Array, _allies_: Array) -> void:
	var sec := float(up.get("sec", 4.0))
	var n := 0
	for t in hits:
		if not t.alive or t.camp == u.camp:
			continue
		if bool(up.get("morale", false)):
			t.kt["nomor_t"] = maxf(float(t.kt.get("nomor_t", 0.0)), b._tm + sec)
		if bool(up.get("heal", false)):
			t.kt["noheal_t"] = maxf(float(t.kt.get("noheal_t", 0.0)), b._tm + sec)
			t.kt["noheal_by"] = [u, "r"]
		n += 1
	if n > 0:
		var what: String = "치료 · 사기 회복을" if bool(up.get("heal", false)) and bool(up.get("morale", false)) else ("치료를" if bool(up.get("heal", false)) else "사기 회복을")
		_kup(u, "r", "적 %d부대가 %d초 동안 %s 받지 못한다" % [n, roundi(sec), what])


## 황충 정군산 —— 고유기에 맞은 적 가운데 가장 강한 장수 1부대 봉인
func _ult_seal_top(u, up: Dictionary, hits: Array, _foes_: Array, _allies_: Array) -> void:
	var t = _top_gen(hits.filter(func(o): return o.alive and o.camp != u.camp))
	if t != null and _seal(u, t, float(up.get("sec", 4.0))):
		_kup(u, "r", "%s의 기술을 봉한다" % b.nm(t), str(t.key))


## 태사자 신궁 —— 고유기에 맞은 적의 고유기 기를 빼앗아 자신의 고유기를 당긴다
func _ult_drain(u, up: Dictionary, hits: Array, _foes_: Array, _allies_: Array) -> void:
	var sec := float(up.get("sec", 3.0))
	var n := 0
	var first := ""
	for t in hits:
		if t.alive and t.camp != u.camp and t.ult != null and t.charges > 0:
			_ult_delay(t, sec)
			if first == "":
				first = str(t.key)
			n += 1
	if n <= 0:
		return
	if u.alive and u.ult != null and u.charges > 0:
		u.gauge = minf(100.0, u.gauge + sec * GAUGE_SEC * n)
	_kup(u, "r", "적 %d부대의 고유기 기를 빼앗는다 (%d초 늦춤)" % [n, roundi(sec)], first)


## 위연 불사 —— 고유기 뒤 잠시 쓰러지지 않는다
func _ult_stand(u, up: Dictionary, _hits: Array, _foes_: Array, _allies_: Array) -> void:
	if not u.alive:
		return
	u.kt["stand_t"] = maxf(float(u.kt.get("stand_t", 0.0)), b._tm + float(up.get("sec", 4.0)))
	_kup(u, "r", "%d초 동안 쓰러지지 않는다" % roundi(float(up.get("sec", 4.0))))


## 여몽 허실 —— 고유기에 맞은 적에게 표식 (받는 피해 +)
func _ult_mark(u, up: Dictionary, hits: Array, _foes_: Array, _allies_: Array) -> void:
	var n := 0
	var first := ""
	for t in hits:
		if t.alive and t.camp != u.camp:
			t.kt["vuln"] = maxf(float(t.kt.get("vuln", 0.0)) if b._tm < float(t.kt.get("vuln_t", -1.0)) else 0.0, float(up.get("amt", 0.25)))
			t.kt["vuln_t"] = maxf(float(t.kt.get("vuln_t", 0.0)), b._tm + float(up.get("sec", 4.0)))
			if first == "":
				first = str(t.key)
			n += 1
	if n > 0:
		_kup(u, "r", "적 %d부대에 표식 (받는 피해 +%d%%)" % [n, roundi(float(up.get("amt", 0.25)) * 100)], first)


## 육손 화소연영 —— 고유기 뒤 불타는 적의 화상이 옆의 타지 않는 부대로 번진다
func _ult_burn_spread(u, up: Dictionary, hits: Array, foes: Array, _allies_: Array) -> void:
	var live := _live(foes)
	var left := int(up.get("n", 3))
	var n := 0
	var first := ""
	for t in hits:
		if left <= 0:
			break
		if not t.alive or t.camp == u.camp:
			continue
		var s = b._st_of(t, "burn")
		if s == null:
			continue
		var best = _beside(t, live.filter(func(o): return not b.has_st(o, "burn")), float(up.get("r", 100.0)))
		if best == null:
			continue
		b._spread_burn_to(t, s, best, str(u.key))
		if first == "":
			first = str(best.key)
		left -= 1
		n += 1
	if n > 0:
		_kup(u, "r", "불길이 옆의 %d부대로 번진다" % n, first)


## 순욱 청류 —— 고유기 뒤 아군 모두의 상태이상을 하나씩 씻는다
func _ult_cleanse_all(u, _up_: Dictionary, _hits: Array, _foes_: Array, allies: Array) -> void:
	var n := 0
	for o in allies:
		if o.alive and b.cleanse(o):
			n += 1
	if n > 0:
		_kup(u, "r", "아군 %d부대의 상태이상을 씻는다" % n)


# ───────── 11/27 새 신화 11명 —— 고유 특기 강화 (p 칸 —— tick · setup · hold_rout · on_fall 이 부른다) ─────────

## 주기형 고유 특기 강화 (tick 에서 그 장수마다)
func _p_tick(u, up: Dictionary) -> void:
	var tm: float = b._tm
	match str(up.get("k", "")):
		"roar_low":      # 장비 연인호걸 —— 병력이 꺾이면 한 번, 둘레 적 혼란
			if not u.kt.get("p_used", false) and u.troops < u.max * float(up.get("below", 0.4)):
				u.kt["p_used"] = true
				var n := 0
				for o in _around(u, _foes(u), float(up.get("r", 120.0))):
					if _confuse(u, o, float(up.get("sec", 1.5))):
						n += 1
				_kup(u, "p", "벼락같은 호통에 둘레 적 %d부대가 혼란에 빠진다" % n)
		"second_wind":      # 황충 노익장 —— 병력이 절반 아래면 한 번, 병력 · 사기를 되찾는다
			if not u.kt.get("p_used", false) and u.troops < u.max * float(up.get("below", 0.5)):
				u.kt["p_used"] = true
				_self_heal(u, float(up.get("heal", 0.2)), "p")
				u.morale = maxf(u.morale, 100.0)
				_kup(u, "p", "늙어도 꺾이지 않는다 —— 병력 · 사기를 되찾는다")
		"defiant":      # 위연 불복 —— 혼란 · 봉인을 떨쳐 내고 잠시 공격 +
			if tm >= float(u.kt.get("p_next", 0.0)) and (b.has_st(u, "confuse") or b.has_st(u, "seal")):
				u.kt["p_next"] = tm + float(up.get("gap", 8.0))
				for k in ["confuse", "seal"]:
					var s = b._st_of(u, k)
					if s != null:
						u.st.erase(s)
						if k == "confuse":
							b._cf_off(u)
				b.add_buff(u, {"stat": "atk", "amt": float(up.get("atk", 0.3)), "dur": int(up.get("sec", 3))}, "kit:불복")
				_kup(u, "p", "굴복하지 않고 떨쳐 일어선다")
		"grow_reset":      # 여몽 오하아몽 —— 일정 시간마다 기술 대기가 모두 풀린다
			if not u.kt.has("p_next"):
				u.kt["p_next"] = float(up.get("every", 20.0))
			if tm >= float(u.kt.p_next):
				u.kt["p_next"] = tm + float(up.get("every", 20.0))
				for jj in u.sk_next.size():
					u.sk_next[jj] = minf(float(u.sk_next[jj]), tm)
				_kup(u, "p", "깨친 바가 있어 기술이 모두 다시 준비된다")
		"purify_tick":      # 장로 귀도 —— 일정 시간마다 상태이상이 가장 많은 아군 1부대를 씻는다
			if tm >= float(u.kt.get("p_next", 0.0)):
				var t = null
				for o in _allies(u):
					if not o.st.is_empty() and (t == null or o.st.size() > t.st.size()):
						t = o
				if t != null and b.cleanse(t):
					u.kt["p_next"] = tm + float(up.get("every", 6.0))
					_kup(u, "p", "%s의 상태이상을 씻는다" % b.nm(t), str(t.key))
		"low_haste_all":      # 11/27 불멸 (제갈량 국궁진췌 · 육손 대도독의 침착) —— 병력이 꺾이면 한 번, 아군 전체 기술 대기 당김
			if not u.kt.get("p_used", false) and u.troops < u.max * float(up.get("below", 0.5)):
				u.kt["p_used"] = true
				var n := 0
				for o in _allies(u):
					if not (o.c.get("sks", []) as Array).is_empty():
						_sk_haste(o, float(up.get("sec", 3.0)), null, -1)
						n += 1
				_kup(u, "p", "아군 %d부대의 기술이 %d초 빨라진다" % [n, roundi(float(up.get("sec", 3.0)))])
		"low_guard":      # 11/27 불멸 (진궁 충절불이 · 손권 강동 수성) —— 병력이 꺾이면 한 번, 아군 전체가 잠시 받는 피해 −
			if not u.kt.get("p_used", false) and u.troops < u.max * float(up.get("below", 0.4)):
				u.kt["p_used"] = true
				var dr := float(up.get("dr", 0.2))
				for o in _allies(u):
					o.kt["dr"] = maxf(float(o.kt.get("dr", 0.0)) if tm < float(o.kt.get("dr_t", -1.0)) else 0.0, dr)
					o.kt["dr_t"] = maxf(float(o.kt.get("dr_t", 0.0)), tm + float(up.get("sec", 4.0)))
				_kup(u, "p", "%d초 동안 아군이 받는 피해 −%d%%" % [roundi(float(up.get("sec", 4.0))), roundi(dr * 100)])
		"fear_tick":      # 11/27 불멸 (동탁 폭정) —— 일정 시간마다 둘레 적 사기 −
			if not u.kt.has("p_next"):
				u.kt["p_next"] = float(up.get("every", 6.0))
			if tm >= float(u.kt.p_next):
				var near := _around(u, _foes(u), float(up.get("r", 120.0)))
				if not near.is_empty():
					u.kt["p_next"] = tm + float(up.get("every", 6.0))
					for o in near:
						o.morale -= float(up.get("morale", 8.0))
					_kup(u, "p", "폭정에 둘레 적 %d부대의 사기가 꺾인다" % near.size(), str(near[0].key))
		"low_purge":      # 11/27 불멸 (관우 괄골요독) —— 병력이 꺾이면 한 번, 상태이상을 모두 씻고 잠시 걸리지 않는다
			if not u.kt.get("p_used", false) and u.troops < u.max * float(up.get("below", 0.5)):
				u.kt["p_used"] = true
				var n := 0
				while n < 4 and b.cleanse(u):
					n += 1
				u.kt["stimm_t"] = tm + float(up.get("sec", 4.0))
				u.kt["stimm_k"] = []
				u.kt["stimm_by"] = [u, "p"]
				_kup(u, "p", "뼈를 긁어 독을 씻어 낸다 —— %d초 동안 상태이상에 걸리지 않는다" % roundi(float(up.get("sec", 4.0))))


## 무너진 부대 u —— 새 신화 고유 특기 강화 (동탁 주지육림 · 태사자 유한 · 순욱 빈 찬합 · 진궁 백문루)
func _p_fall(u) -> void:
	var tm: float = b._tm
	for k in ks:      # 동탁 주지육림 —— 적 부대가 무너질 때마다 공격 +
		if k.alive and k.camp != u.camp and _upk(k, "p") == "feast" and int(k.kt.get("feast_n", 0)) < int(_up(k, "p").get("max", 5)):
			k.kt["feast_n"] = int(k.kt.get("feast_n", 0)) + 1
			k.buffs.append({"stat": "atk", "amt": float(_up(k, "p").get("amt", 0.08)), "dur": 999})
			_kup(k, "p", "적이 무너질수록 기세가 오른다 (공격 +%d%% · %d번째)" % [roundi(float(_up(k, "p").get("amt", 0.08)) * 100), int(k.kt.feast_n)])
		if k.alive and k.camp != u.camp and _upk(k, "p") == "plague_jump" and b.has_st(u, "plague"):      # 장로 역귀 —— 역병에 걸린 적이 무너지면 둘레로 옮는다
			var pu := _up(k, "p")
			var got := _around(u, _live(_allies(u)), float(pu.get("r", 150.0))).filter(func(o): return not b.has_st(o, "plague")).slice(0, int(pu.get("n", 2)))
			for o in got:
				b.inflict(k, o, "plague", float(pu.get("val", 40)), int(pu.get("dur", 4)))
			if not got.is_empty():
				_kup(k, "p", "무너진 %s의 역병이 둘레 %d부대로 옮는다" % [b.nm(u), got.size()], str(got[0].key))
		if not k.alive or k == u:      # 11/27 불멸 —— 무너진 부대를 보는 고유 특기 강화 (아래)
			continue
		var kk := _upk(k, "p")
		if kk == "kill_haste" and k.camp != u.camp and int(k.kt.get("kh_n", 0)) < int(_up(k, "p").get("max", 4)):      # 손책 질풍노도 · 태사자 대장부의 뜻 —— 적이 무너질 때마다 기술 대기 당김
			k.kt["kh_n"] = int(k.kt.get("kh_n", 0)) + 1
			var sec := float(_up(k, "p").get("sec", 2.0))
			for jj in k.sk_next.size():
				k.sk_next[jj] = float(k.sk_next[jj]) - sec
			_kup(k, "p", "적이 무너지자 기술이 %s초 빨라진다 (%d번째)" % [str(snappedf(sec, 0.1)), int(k.kt.kh_n)])
		elif kk == "avenge" and k.camp == u.camp and not k.kt.get("p_used", false):      # 장비 형님의 원수 · 마초 복수의 맹세 · 강유 승상의 유지 —— 아군이 처음 무너지면 한 번
			k.kt["p_used"] = true
			var pu := _up(k, "p")
			b.add_buff(k, {"stat": "atk", "amt": float(pu.get("atk", 0.3)), "dur": ceili(float(pu.get("sec", 6.0)))}, "kit:p")
			k.morale = maxf(k.morale, 100.0)
			_kup(k, "p", "%s 무너지자 분노가 치민다 (%d초 동안 공격 +%d%%)" % [b.ga(b.nm(u)), roundi(float(pu.get("sec", 6.0))), roundi(float(pu.get("atk", 0.3)) * 100)], str(u.key))
		elif kk == "grief_heal" and k.camp == u.camp and int(k.kt.get("gh_n", 0)) < int(_up(k, "p").get("max", 3)):      # 유비 유비의 눈물 —— 아군이 무너질 때마다 아군 전체 병력 회복
			k.kt["gh_n"] = int(k.kt.get("gh_n", 0)) + 1
			var nm := str(Kit.cell(k.c.id, "p").get("up", {}).get("n", ""))
			for o in _allies(k):
				b.heal_troop(o, float(_up(k, "p").get("ratio", 0.04)), nm, k)
			_kup(k, "p", "%s 잃은 눈물에 아군이 다시 일어선다 (병력 +%d%%)" % [b.eul(b.nm(u)), roundi(float(_up(k, "p").get("ratio", 0.04)) * 100)], str(u.key))
	if u.kit == null:
		return
	var up := _up(u, "p")
	match str(up.get("k", "")):
		"last_grudge":      # 태사자 유한 —— 자신을 무너뜨린 적에게 표식 · 봉인
			var lh = u.last_hit
			if lh != null and lh.alive and lh.camp != u.camp:
				lh.kt["vuln"] = float(up.get("amt", 0.3))
				lh.kt["vuln_t"] = tm + float(up.get("sec", 4.0))
				_seal(u, lh, float(up.get("seal", 3.0)))
				_kup(u, "p", "쓰러지며 남긴 한 —— %s 표식 · 봉인" % b.ga(b.nm(lh)), str(lh.key))
		"empty_box":      # 순욱 빈 찬합 —— 무너지면 아군 모두의 기술 대기가 풀린다
			var n := 0
			for o in b.units:
				if o.alive and o.camp == u.camp and not (o.c.get("sks", []) as Array).is_empty():
					_sk_haste(o, 999.0, null, -1)
					n += 1
			_kup(u, "p", "빈 찬합을 받아 든 순욱 —— 아군 %d부대의 기술이 모두 준비된다" % n)
		"curse_fall":      # 진궁 백문루 —— 무너지면 적 전체 혼란
			var n := 0
			for o in b.units:
				if o.alive and o.camp != u.camp and _confuse(u, o, float(up.get("sec", 1.5))):
					n += 1
			_kup(u, "p", "백문루의 결의 —— 적 %d부대가 혼란에 빠진다" % n)


# ───────── 11/27 새 신화 11명 —— 부품 ─────────

## 자기 병력 회복 (치료 막기와 관계없는 회복 —— 강화 효과가 직접 되찾는 것)
func _self_heal(u, ratio: float, slot: String) -> void:
	var g := minf(roundf(u.max * ratio), u.max - u.troops)
	if g <= 0.0:
		return
	u.troops += g
	u.htr += g
	b.L("hl", "『%s』에 %s의 대오가 정비된다 — 병력 +%s" % [str(Kit.cell(u.c.id, slot).get("up", {}).get("n", "")), b.nm(u), b.num(g)], {"fx": "heal", "f": u.key, "n": g})


## 기술 대기를 sec 초 민다 —— 키트 장수는 다음 사용 시각, 그 밖은 그 초만큼의 충전을 덜어 낸다 (0 아래로는 안 간다)
func _sk_slow(o, sec: float) -> void:
	var sks: Array = o.c.get("sks", [])
	if sks.is_empty():
		return
	if o.kit != null:
		for jj in o.sk_next.size():
			o.sk_next[jj] = maxf(float(o.sk_next[jj]), b._tm) + sec
		return
	var sub: float = b.sk_rate(o) * sec / maxf(0.1, b._interval(o))
	for jj in o.sk_ch.size():
		o.sk_ch[jj] = maxf(0.0, float(o.sk_ch[jj]) - sub)


# ───────── 부품 ─────────

func _hit(a, d, mult: float, n: int) -> void:
	if b.is_caster(a.c):
		b.int_hit(a, d, mult, n)
	else:
		b.phys_hit(a, d, mult, true)


## 밀어낸다 —— from 에서 멀어지는 쪽으로 (by: 밀어낸 장수 —— 사건의 a)
func _push(from, t, px: float, by = null) -> void:
	var d: Vector2 = t.pos - from.pos
	var dir: Vector2 = d.normalized() if d.length() > 0.1 else from.fwd
	_shove(t, dir * px, by if by != null else from)


## 부대를 off 만큼 옮기고 밀려남 사건을 남긴다 (fx "push" · f 밀려난 부대 · a 밀어낸 장수 · "push": true —— 화면이 길 기록만으로는 밀려난 것을 가릴 수 없다)
func _shove(t, off: Vector2, by) -> void:
	t.pos += off
	b._clamp_arena(t)
	t.vel = Vector2.ZERO
	t.atb = maxf(0.0, t.atb - STAGGER)
	b.L("mo", "%s 밀려났다" % b.ga(b.nm(t)), {"fx": "push", "f": t.key, "a": by.key, "push": true})


## 혼란 sec 초 (등급 저항만큼 짧아진다 · 한 번 상한 Battle.cf_max_sec). 새로 걸렸으면 true
func _confuse(a, t, sec: float) -> bool:
	if not t.alive or b.has_st(t, "confuse"):
		return false
	b.inflict(a, t, "confuse", 1.0, maxi(1, ceili(sec + 0.5)))
	var s = b._st_of(t, "confuse")
	if s == null:
		return false
	if s.has("end"):
		s["end"] = float(t.cf_t0) + minf(Battle.cf_max_sec, sec) * (1.0 - float(Battle.cf_tier_res.get(int(t.c.tier), 0.0)))
	return true


## 봉인 sec 초 —— 기술을 쓰지 못한다 (고유기도). 걸렸으면 true
func _seal(a, t, sec: float) -> bool:
	if not t.alive:
		return false
	b.inflict(a, t, "seal", 1.0, maxi(1, roundi(sec)))
	return b.has_st(t, "seal")


func _hide(u, sec: float) -> void:
	var until: float = b._tm + sec
	u.sg["hide"] = maxf(float(u.sg.get("hide", 0.0)), until)
	hide_until = maxf(hide_until, until)


## 고유기를 sec 초 늦춘다 —— 모으는 중이면 터지는 때를 미루고, 아니면 기를 덜고 그동안 시작하지 못하게
func _ult_delay(t, sec: float) -> void:
	if t.ult == null or t.charges <= 0:
		return
	if b._wind.has(t):
		b._wind[t] = float(b._wind[t]) + sec
		return
	t.gauge = maxf(0.0, t.gauge - sec * GAUGE_SEC)
	if t.gauge < 100.0:
		t.ult_ready_t = -1.0
	t.ult_hold = maxf(t.ult_hold, b._tm + sec)


## 고유기를 sec 초 당긴다 —— 기를 채우고 장수 대기 · 묶임을 그만큼 줄인다
func _ult_haste(t, sec: float) -> void:
	if t.ult == null or t.charges <= 0:
		return
	t.gauge = minf(100.0, t.gauge + sec * GAUGE_SEC)
	t.ult_shift -= sec
	t.ult_hold -= sec
	if t.gauge >= 100.0 and t.ult_ready_t < 0.0:
		t.ult_ready_t = b._tm


## 고유기가 가장 가까운(기가 가장 찬) 아군 —— 아직 모으지 않는, 횟수가 남은 장수. skip_self 면 u 는 뺀다
func _ult_next(u, skip_self: bool):
	var t = null
	for o in b.units:
		if not o.alive or o.camp != u.camp or o.ult == null or o.charges <= 0 or b._wind.has(o) or (skip_self and o == u):
			continue
		if t == null or o.gauge > t.gauge or (o.gauge == t.gauge and int(o.c.tier) > int(t.c.tier)):
			t = o
	return t


## 기술 대기를 sec 초 당긴다 —— 키트 장수는 다음 사용 시각, 그 밖은 그 초만큼의 충전 (skip_u 의 skip_j 번 기술은 그대로 —— 호령 자신)
func _sk_haste(o, sec: float, skip_u, skip_j: int) -> void:
	var sks: Array = o.c.get("sks", [])
	if sks.is_empty():
		return
	if o.kit != null:
		for jj in o.sk_next.size():
			if not (o == skip_u and jj == skip_j):
				o.sk_next[jj] = float(o.sk_next[jj]) - sec
		return
	var add: float = b.sk_rate(o) * sec / maxf(0.1, b._interval(o)) if sec < 900.0 else 99.0
	if Battle.sk_split:
		while o.sk_ch.size() < sks.size():
			o.sk_ch.append(0.5)
		for jj in sks.size():
			o.sk_ch[jj] = minf(float(sks[jj].get("cost", 1.0)), float(o.sk_ch[jj]) + add)
	else:
		if o.sk_ch.is_empty():
			o.sk_ch.append(0.5)
		var cap := 0.0
		for x in sks:
			cap = maxf(cap, float(x.get("cost", 1.0)))
		o.sk_ch[0] = minf(cap, float(o.sk_ch[0]) + add)


## t 의 이웃 —— pool 가운데 살아 있고 발자국 틈이 r 안인 가장 가까운 부대 (skip 은 뺀다). 없으면 null.
## ('옆 부대 · 주변' 은 가운데 거리가 아니라 발자국 틈으로 잰다 —— 진형 칸이 넓어(열 210 · 행 150) 가운데 거리로는 이웃이 거의 잡히지 않는다)
func _beside(t, pool: Array, r: float, skip := []):
	var best = null
	var bd := r
	for o in pool:
		if o == t or not o.alive or skip.has(o):
			continue
		var g: float = b._gap(o, t)
		if g <= bd and (best == null or g < bd):
			bd = g
			best = o
	return best


## u 에게 붙은 근접 적들 (발자국 틈 TOUCH_R 안 · 부대 순서)
func _touching(u) -> Array:
	var out := []
	for o in b.units:
		if o.alive and o.camp != u.camp and not o.ranged and not b._hidden(o) and b._gap(u, o) <= TOUCH_R:
			out.append(o)
	return out


## 가장 위태로운 아군 (병력 비율이 가장 낮은 · 살아 있는)
func _weakest(allies: Array):
	var t = null
	for o in allies:
		if o.alive and (t == null or o.troops / o.max < t.troops / t.max):
			t = o
	return t


func _farthest(u, pool: Array):
	var t = null
	var bd := -1.0
	for o in pool:
		var d: float = o.pos.distance_squared_to(u.pos)
		if d > bd:
			bd = d
			t = o
	return t


## 가장 강한 장수 —— 고유기를 가진 부대 가운데 등급 · 공격 · 병력 순 (없으면 부대 전체에서)
func _top_gen(pool: Array):
	var gens := pool.filter(func(o): return o.alive and o.ult != null)
	var from: Array = gens if not gens.is_empty() else pool.filter(func(o): return o.alive)
	var t = null
	for o in from:
		if t == null or int(o.c.tier) > int(t.c.tier) or (int(o.c.tier) == int(t.c.tier) and (float(o.c.atk) > float(t.c.atk) or (float(o.c.atk) == float(t.c.atk) and o.troops > t.troops))):
			t = o
	return t
