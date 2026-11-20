extends RefCounted
## 11/19 장수 개성 —— 사용자 "같은 병종이라도 장수마다 다른 특징이 명확하게 두드러지게" (docs/장수_개성_정리_1119.md 4장).
## 장수마다 고유 특기 하나(passives.json traits, unique)의 m 키를 읽어 실시간 엔진에 행동을 붙인다.
## 판정 자리: 표적(target_w) · 주는 피해(amp) · 받는 피해(taken) · 맞힌 뒤(after_hit) · 맞은 뒤(after_taken) · 쓰러뜨림(on_kill)
## · 이동(steer) · 주기(tick) · 패주 버팀(hold_rout · calm). 판정은 rng 만 쓰고 부대 순서대로 돈다 (결정적).

const KEYS := ["slow_self", "gauge_top", "gauge_refund", "def_weak", "ward_aura", "song", "supply", "st_short", "fame",      # 1.2 모사 · 유생 (아래 맨 끝 머리)
	"taunt", "seek_low", "seek_gen", "seek_back", "seek_cav", "seek_strong", "seek_guard",
	"amp_low", "amp_cav", "amp_strong", "amp_gen", "amp_rear", "amp_open", "amp_same", "amp_still", "amp_come", "amp_drown",
	"amp_allies", "amp_early", "amp_late", "amp_last", "amp_behind", "amp_far", "amp_kill", "amp_guard", "no_pin",
	"charge_amp", "charge_run", "dr_still", "dr_link", "dr_low", "dr_early", "dodge_big", "ult_dr",
	"shove", "bind", "slow_on", "morale_on", "gauge_on", "bleed_on", "pierce_hit", "throw",
	"counter_all", "dr_guard", "enrage", "ult_ret", "chain", "kill_gauge", "absorb", "undying", "ally_calm", "morale_floor",
	"kite", "hit_run", "blink", "stealth", "ambush", "rear_spawn",
	"roar", "cheer_aura", "cleanse_aura", "spd_aura", "def_aura", "atk_down", "cav_aura", "caster_aura", "tier_aura", "boost_best",
	"give_troops", "truce", "mark", "trap", "rain", "quake", "confuse_aura", "gauge_aura", "frail_water"]

const R_AURA := 260.0       # 주변 오라 반지름
const AURA_T := 4.0         # 주변 오라 주기 (초)
const TAUNT_R := 240.0      # 도발 반지름
const LOW := 0.35           # '약한 적' —— 병력 비율

# 11/21 1.2 창병 탱커 셋 (조인 도발 · 전위 역습 범위 · 주태 불사) —— 엔진 쪽 수치는 여기 한곳. 인물별 세기는 passives.json sig (tools/scripts/gold_traits.py SIG_TANK)
const TAUNT_PULSE := 3.0    # 도발을 다시 외치는 간격 (초)
const TAUNT_HOLD := 3.5     # 도발에 걸린 적이 표적을 도발한 부대로 붙드는 시간 (초) —— 외침 간격보다 길어 반지름 안에 있으면 끊기지 않는다
const TAUNT_SAY := 6.0      # 도발 말풍선 간격 (초)
const COUNTER_CD := 1.0     # 역습 범위 —— 되받아치기 간격 (초)
const COUNTER_MAX := 1.2    # 역습 범위 —— 한 번에 되받아치는 세기 상한 (기본 공격 배수)
const COUNTER_SAY := 3.0    # 역습 범위 말풍선 간격 (초)
const UNDYING_SHOW := 4.0   # 불사가 패주를 버틴 뒤 딱지를 보이는 시간 (초)
const UNDYING_SAY := 8.0    # 불사 말풍선 간격 (초)
const GUARD_DR_MAX := 0.6   # 방진 중 받는 피해 감소 상한
## 등급 세기 —— 개성 키는 보통 등급 배율을 받지 않지만, 아래 키는 TIER_BASE 급 값에서 한 급마다 TIER_STEP 만큼 세진다 (4급 0.9 · 5급 1.0 · 6급 1.1 · 7급 1.2 …)
const TIER_BASE := 5
const TIER_STEP := 0.1
const TIER_KEYS := {"taunt": true, "dr_guard": true, "counter_all": true, "dr_low": true}

var b      # RtBattle
var who := {}               # 키 -> 그 키를 가진 부대들 (전투 시작에 한 번)
var _next := {}             # [부대, 일] -> 다음 시각
var _mark := {}             # 진영 -> 지목된 적 부대 (법정)
var _seen := {}             # [부대, 적] -> true (팔진 —— 적마다 한 번)


## 전투가 끝나면 —— 부대 · 전투를 붙든 참조를 끊는다
func release() -> void:
	for u in b.units:
		u.sg.clear()
		u.sga.clear()
	_mark.clear()
	_next.clear()
	_seen.clear()
	who.clear()
	b = null


static func make(bt) -> Object:
	var s = load("res://scripts/sig_rt.gd").new()
	s.b = bt
	for u in bt.units:
		for k in KEYS:
			if float(u.m.get(k, 0.0)) != 0.0:
				if not s.who.has(k):
					s.who[k] = []
				s.who[k].append(u)
	return s if not s.who.is_empty() else null


func v(u, k: String) -> float:
	var x := float(u.m.get(k, 0.0))
	if x != 0.0 and tiered(k):
		x *= tier_mul(k, int(u.c.tier))
	return x


## 등급 세기 배율 (TIER_KEYS 만) —— 장수 정보창 설명(DB.mods_list)도 같은 값을 쓴다
static func tier_mul(k: String, tier: int) -> float:
	if not tiered(k):
		return 1.0
	return maxf(0.5, 1.0 + TIER_STEP * float(tier - TIER_BASE))


func _stat(k: String, n := 1) -> void:
	b.stats[k] = int(b.stats.get(k, 0)) + n


func has(k: String) -> bool:
	return who.has(k)


func _due(u, job: String, every: float) -> bool:
	var key := "%s:%s" % [u.key if u != null else "_", job]
	var t: float = _next.get(key, 0.0)
	if b._tm < t:
		return false
	_next[key] = b._tm + every
	return true


func _allies(u) -> Array:
	return b.units.filter(func(o): return o.alive and o.camp == u.camp)


func _foes(u) -> Array:
	return b.units.filter(func(o): return o.alive and o.camp != u.camp)


func _say(u, text: String, up := true) -> void:
	b.L("sk", "%s의 %s" % [b.nm(u), text], {"fx": "buff", "f": u.key, "up": up, "sig": true})


# ───────── 시작 ─────────

## 전장 범위를 재기 전 —— 매복(측면 출현) · 후방 출현 · 위장 · 첫 기술
func setup() -> void:
	_scholar_setup()
	for k in ["ambush", "rear_spawn"]:
		for u in who.get(k, []):
			var foes := _foes(u)
			if foes.is_empty():
				continue
			var c: Vector2 = b._centroid(foes)
			var ext := 0.0
			for o in b.units:
				ext = maxf(ext, absf(o.pos.y) + o.hw)
			var sx := signf(c.x - u.pos.x)
			if k == "ambush":      # 장연 —— 적 진영 옆에서
				u.pos = Vector2(lerpf(u.pos.x, c.x, 0.55), (ext + 30.0) * (1.0 if u.slot % 2 == 0 else -1.0))
			else:                  # 등애 —— 적 뒤에서
				var back := c.x
				for o in foes:
					back = maxf(back, o.pos.x) if sx > 0 else minf(back, o.pos.x)
				u.pos = Vector2(back + sx * 90.0, c.y + (60.0 if u.slot % 2 == 0 else -60.0))
				u.fwd = Vector2(-sx, 0.0)
				_note(u, "rear_spawn")
	for u in who.get("stealth", []):
		u.sg["hide"] = v(u, "stealth")


# ───────── 표적 ─────────

## 근접 표적 고르기의 무게 (작을수록 먼저) —— rt _choose 의 w 에 곱한다
func target_w(u, o, d: float) -> float:
	var w := 1.0
	if has("taunt") and v(o, "taunt") > 0.0 and d < TAUNT_R:
		w *= 1.0 - minf(0.8, v(o, "taunt"))
		if u.sg.get("tnt") == o:
			w *= 0.3      # 도발에 걸린 적 —— 도발한 부대를 훨씬 먼저 (표적 강제는 RtBattle 이동 쪽 taunt_of)
	if has("mark") and _mark.get(u.camp) == o:
		_stat("sig_mark_w")
		w *= 0.6
	if u.m.is_empty():
		return w
	if v(u, "seek_low") > 0.0 and o.troops < o.max * LOW:
		w *= 1.0 - minf(0.8, v(u, "seek_low"))
	if v(u, "seek_gen") > 0.0 and o.ult != null:
		w *= 1.0 - minf(0.8, v(u, "seek_gen"))
	if v(u, "seek_back") > 0.0 and b._ranged(o):
		w *= 1.0 - minf(0.8, v(u, "seek_back"))
	if v(u, "seek_cav") > 0.0 and o.c.tag == "기병":
		w *= 1.0 - minf(0.8, v(u, "seek_cav"))
	if v(u, "seek_strong") > 0.0 and (o.c.tier > u.c.tier or float(o.c.atk) > float(u.c.atk)):
		w *= 1.0 - minf(0.8, v(u, "seek_strong"))
	if v(u, "seek_guard") > 0.0 and o.tgt != null and o.tgt.alive and o.tgt.camp == u.camp and o.tgt != u and b._gap(o, o.tgt) <= RtBattle.TOUCH + 6.0:
		w *= 1.0 - minf(0.8, v(u, "seek_guard"))
	return maxf(0.15, w)


# ───────── 피해 ─────────

## 때리는 쪽 배율 (기본 공격 · 반격 · 기술 · 고유기 모두)
func amp(a, d, far: bool) -> float:
	if a.m.is_empty():
		return 1.0
	var m := 1.0
	var tm: float = b._tm
	if v(a, "amp_low") > 0.0 and d.troops < d.max * LOW: m *= 1.0 + v(a, "amp_low")
	if v(a, "amp_cav") > 0.0 and d.c.tag == "기병": m *= 1.0 + v(a, "amp_cav")
	if v(a, "amp_strong") > 0.0 and (d.c.tier > a.c.tier or float(d.c.atk) > float(a.c.atk)): m *= 1.0 + v(a, "amp_strong")
	if v(a, "amp_gen") > 0.0 and d.ult != null: m *= 1.0 + v(a, "amp_gen")
	if v(a, "amp_rear") > 0.0:
		var dv: Vector2 = a.pos - d.pos
		if dv.length() > 0.1 and absf(d.fwd.angle_to(dv)) > PI / 3.0:
			m *= 1.0 + v(a, "amp_rear")
	if v(a, "amp_open") > 0.0 and int(a.sg.get("hits", 0)) < 3: m *= 1.0 + v(a, "amp_open")
	if v(a, "amp_same") > 0.0 and a.sg.get("last") == d: m *= 1.0 + v(a, "amp_same") * minf(5.0, float(a.sg.get("same", 0))) / 5.0
	if v(a, "amp_still") > 0.0 and float(a.sg.get("still", 0.0)) >= 1.0: m *= 1.0 + v(a, "amp_still")
	if v(a, "amp_come") > 0.0 and d.vel.dot(a.pos - d.pos) > 0.0 and d.vel.length() > 10.0: m *= 1.0 + v(a, "amp_come")
	if v(a, "amp_drown") > 0.0 and (b.has_st(d, "flood") or b.has_st(d, "confuse")): m *= 1.0 + v(a, "amp_drown")
	if v(a, "amp_allies") > 0.0: m *= 1.0 + v(a, "amp_allies") * float(_allies(a).size()) / 9.0
	if v(a, "amp_early") > 0.0: m *= 1.0 + v(a, "amp_early") * clampf(1.0 - tm / 40.0, 0.0, 1.0)
	if v(a, "amp_early") > 0.0: _stat("sig_amp_early")
	if v(a, "amp_late") > 0.0: m *= 1.0 + v(a, "amp_late") * clampf((tm - 20.0) / 30.0, 0.0, 1.0)
	if v(a, "amp_late") > 0.0: _stat("sig_amp_late")
	if v(a, "amp_last") > 0.0 and _allies(a).size() <= 3: m *= 1.0 + v(a, "amp_last")
	if v(a, "amp_behind") > 0.0:
		var mine := 0.0
		var theirs := 0.0
		for o in b.units:
			if o.alive:
				if o.camp == a.camp: mine += o.troops
				else: theirs += o.troops
		if mine < theirs * 0.85: m *= 1.0 + v(a, "amp_behind")
		if mine < theirs * 0.85: _stat("sig_amp_behind")
	if v(a, "amp_far") > 0.0 and far: m *= 1.0 + v(a, "amp_far") * clampf(b._gap(a, d) / 260.0, 0.0, 1.0)
	if v(a, "amp_kill") > 0.0: m *= 1.0 + v(a, "amp_kill") * minf(3.0, float(a.kills)) / 3.0
	if v(a, "amp_guard") > 0.0 and b._phalanx(d): m *= 1.0 + v(a, "amp_guard")
	if v(a, "no_pin") > 0.0 and b._pinned(a): m /= maxf(0.1, b.engage_v("pin_atk", 1.0))
	return m


## 맞는 쪽 배율. 큰 한 방 피하기(우번)는 여기서 굴린다
func taken(d, a, mult: float) -> float:
	if d.m.is_empty() and not has("ult_dr"):
		return 1.0
	var m := 1.0
	if v(d, "dr_still") > 0.0 and float(d.sg.get("still", 0.0)) >= 1.0: m *= 1.0 - minf(0.6, v(d, "dr_still"))
	if v(d, "dr_low") > 0.0: m *= 1.0 - minf(0.6, v(d, "dr_low")) * clampf(1.0 - d.troops / d.max, 0.0, 1.0)
	if v(d, "dr_early") > 0.0 and b._tm < 20.0: m *= 1.0 - minf(0.6, v(d, "dr_early"))
	if v(d, "dr_guard") > 0.0 and b._phalanx(d): m *= 1.0 - minf(GUARD_DR_MAX, v(d, "dr_guard"))      # 11/21 조인 —— 방진을 친 동안
	if v(d, "dr_link") > 0.0:
		for o in b.units:
			if o != d and o.alive and o.camp == d.camp and o.c.tag == "창병" and o.pos.distance_to(d.pos) < d.hw + o.hw + 40.0:
				m *= 1.0 - minf(0.5, v(d, "dr_link"))
				break
	if has("ult_dr") and b._in_ult:
		var best := 0.0
		for o in who["ult_dr"]:
			if o.alive and o.camp == d.camp:
				best = maxf(best, v(o, "ult_dr"))
		m *= 1.0 - minf(0.6, best)
	if v(d, "dodge_big") > 0.0 and (b._in_ult or mult >= 1.5) and b.rng.randf() < minf(0.6, v(d, "dodge_big")):
		_say(d, "점술 —— 큰 한 방을 피했다")
		m *= 0.05
	if v(d, "frail_water") > 0.0 and b.has_st(d, "flood"): m *= 1.0 + v(d, "frail_water")
	if v(d, "frail_water") > 0.0 and b.has_st(d, "flood"): _note(d, "frail_water")
	return m


## 때린 뒤 (때린 쪽 키) —— loss 는 이번 타격이 깎은 병력
func after_hit(a, d, loss: float, far: bool) -> void:
	if a.m.is_empty() or a.countering or a.sg.get("piercing", false):
		return
	a.sg["hits"] = int(a.sg.get("hits", 0)) + 1
	a.sg["same"] = int(a.sg.get("same", 0)) + 1 if a.sg.get("last") == d else 0
	a.sg["last"] = d
	if not d.alive:
		return
	if v(a, "shove") > 0.0 and (not far or b._ranged(a)) and not b._in_ult:
		var dir: Vector2 = d.pos - a.pos
		if dir.length() > 0.1:
			d.pos += dir.normalized() * minf(30.0, v(a, "shove"))
			_note(a, "shove")
			b._clamp_arena(d)
	if v(a, "bind") > 0.0 and b.rng.randf() < v(a, "bind"):
		b.inflict(a, d, "flood", 0.0, 1)
	if v(a, "slow_on") > 0.0 and b.rng.randf() < 0.35:
		d.sga["spd"] = minf(float(d.sga.get("spd", 0.0)), -minf(0.5, v(a, "slow_on")))
	if v(a, "morale_on") > 0.0:
		d.morale -= v(a, "morale_on")
		a.mdmg += v(a, "morale_on")
	if v(a, "gauge_on") > 0.0 and d.ult != null:
		d.gauge = maxf(0.0, d.gauge - v(a, "gauge_on"))
		_note(a, "gauge_on")
	if v(a, "bleed_on") > 0.0 and b.rng.randf() < v(a, "bleed_on"):
		b.inflict(a, d, "bleed", 0.05, 2)
		_note(a, "bleed_on")
	if v(a, "pierce_hit") > 0.0 and not b._in_ult:
		var dir2: Vector2 = d.pos - a.pos
		if dir2.length() > 0.1:
			dir2 = dir2.normalized()
			var best = null
			var bd := 160.0
			for o in b.units:
				if o.alive and o.camp == d.camp and o != d:
					var rel: Vector2 = o.pos - d.pos
					var dd := rel.length()
					if dd < bd and rel.dot(dir2) > dd * 0.5:
						bd = dd
						best = o
			if best != null:
				a.sg["piercing"] = true
				b.phys_hit(a, best, v(a, "pierce_hit"), true)
				a.sg["piercing"] = false
	if v(a, "hit_run") > 0.0 and not far and b._tm >= float(a.sg.get("run_cd", 0.0)):
		a.sg["back"] = b._tm + minf(2.0, v(a, "hit_run"))
		a.sg["run_cd"] = b._tm + 3.5


## 맞은 뒤 (맞은 쪽 키)
func after_taken(d, a, loss: float, far: bool) -> void:
	if d.m.is_empty() or not d.alive or a == null:
		return
	var tm: float = b._tm
	if v(d, "counter_all") > 0.0 and not far and not a.countering and not b._in_ult and tm >= float(d.sg.get("ca", 0.0)):
		d.sg["ca"] = tm + COUNTER_CD
		var hit := 0
		var pw := minf(COUNTER_MAX, v(d, "counter_all"))
		for o in b.units:
			# 11/21 때린 적도 포함 —— 맞닿은 근접 적 전부 (한 부대에게만 맞아도 발동, 둘러싸일수록 여럿에게)
			if o.alive and o.camp != d.camp and not b._ranged(o) and b._gap(d, o) <= RtBattle.TOUCH + 4.0:
				d.countering = true
				b.phys_hit(d, o, pw, true)
				d.countering = false
				hit += 1
		if hit > 0:
			_stat("sig_counter_all")
			_stat("sig_counter_all_hits", hit)
			if tm >= float(d.sg.get("ca_say", 0.0)):      # 말풍선은 COUNTER_SAY 초에 한 번 (반격 타격은 매번 —— 맞은 적마다 부딪힘 연출)
				d.sg["ca_say"] = tm + COUNTER_SAY
				_say(d, "쌍철극 —— 둘러싼 적 %d부대를 되받아쳤다" % hit)
	if v(d, "enrage") > 0.0 and loss > d.max * 0.05 and tm >= float(d.sg.get("rage", 0.0)):
		d.sg["rage"] = tm + 6.0
		d.sg["hold"] = tm + 3.0
		d.sga["atk"] = maxf(float(d.sga.get("atk", 0.0)), minf(0.6, v(d, "enrage")))
		d.sg["rage_off"] = tm + 3.0
		_say(d, "분노 —— 눈알을 삼키고 덤벼든다")
	if v(d, "ult_ret") > 0.0 and b._in_ult and a.camp != d.camp and tm >= float(d.sg.get("ret_t", 0.0)):
		d.sg["ret_t"] = tm + 6.0
		d.sg["ret"] = a


## 적을 쓰러뜨림 (k 가 쓰러뜨린 쪽)
func on_kill(k, victim) -> void:
	if k == null or not k.alive or k.m.is_empty() or k.camp == victim.camp:
		return
	if v(k, "chain") > 0.0:
		k.ran = maxf(k.ran, RtBattle.CHARGE_RUN)
		k.retgt = 0.0
		k.atb = maxf(k.atb, 1.0)
		k.tgt = null
		_say(k, "무쌍 —— 곧장 다음 적에게")
	if v(k, "kill_gauge") > 0.0 and k.ult != null:
		k.gauge = minf(100.0, k.gauge + v(k, "kill_gauge"))
	if v(k, "absorb") > 0.0:
		var g := minf(k.max - k.troops, victim.max * v(k, "absorb"))
		if g > 0.0:
			k.troops += g
			_stat("sig_absorb")
			k.htr += g
			b.L("hl", "%s의 변절 유도 —— 흩어진 적병을 거두었다" % b.nm(k), {"fx": "heal", "f": k.key, "n": g, "healer": k.key, "sig": true})


## 패주를 버티나 (true 면 이번 패주를 취소)
func hold_rout(u, cause: String) -> bool:
	if u.m.is_empty() or cause in ["annihilated", "boss"] or u.troops <= 0.0:
		return false
	# 불사 —— 이 판정이 Battle.rout 맨 앞이라 불굴 계열(rout 키: 패주 확률 · 붕괴 · 결전 사기 감소를 줄임)과 겹치지 않는다.
	# 불굴은 '패주에 이르기까지'를 늦추고, 불사는 '이른 패주 자체'를 병력 문턱까지 취소한다. 문턱 아래에서는 불굴만 남는다
	if v(u, "undying") > 0.0 and u.troops > u.max * clampf(v(u, "undying"), 0.05, 0.5):
		u.morale = maxf(u.morale, 15.0)
		u.sg["ud_show"] = b._tm + UNDYING_SHOW
		_stat("sig_undying")
		if b._tm >= float(u.sg.get("ud_say", 0.0)):
			u.sg["ud_say"] = b._tm + UNDYING_SAY
			_say(u, "불사 —— 상처투성이로 버틴다")
		return true
	if b._tm < float(u.sg.get("hold", 0.0)):
		u.morale = maxf(u.morale, 10.0)
		return true
	return false


## 군율 —— 주변 아군 패주 확률을 줄이는 몫 (가장 센 하나)
func calm(u) -> float:
	if not has("ally_calm"):
		return 0.0
	var best := 0.0
	for o in who["ally_calm"]:
		if o.alive and o.camp == u.camp and o.pos.distance_to(u.pos) < R_AURA:
			best = maxf(best, v(o, "ally_calm"))
	return minf(0.8, best)


func spd_mul(u) -> float:
	return 1.0


# ───────── 이동 ─────────

## 맞붙음을 풀고 물러나야 하나 (치고 빠지기)
func backing(u) -> bool:
	return b._tm < float(u.sg.get("back", -1.0))


## 원하는 속도를 바꾼다 —— 치고 빠지기 · 후퇴 사격
func steer(u, t, pin, desired: Vector2, sp: float) -> Vector2:
	if t == null:
		return desired
	if backing(u):
		var away: Vector2 = u.pos - t.pos
		return away.normalized() * sp if away.length() > 0.1 else desired
	if v(u, "kite") > 0.0 and pin != null and b._ranged(u):
		var away2: Vector2 = u.pos - pin.pos
		if away2.length() > 0.1:
			return away2.normalized() * sp * minf(1.0, 0.6 + v(u, "kite"))
	return desired


# ───────── 주기 ─────────

func tick(dt: float) -> void:
	var tm: float = b._tm
	for u in b.units:
		if not u.alive or u.m.is_empty():
			continue
		# 제자리 —— 고수 · 농성
		if v(u, "dr_still") > 0.0 or v(u, "amp_still") > 0.0:
			var lp: Vector2 = u.sg.get("lp", u.pos)
			u.sg["still"] = float(u.sg.get("still", 0.0)) + dt if lp.distance_to(u.pos) < 1.5 else 0.0
			u.sg["lp"] = u.pos
		if u.sg.has("rage_off") and tm >= float(u.sg["rage_off"]):
			u.sg.erase("rage_off")
			u.sga.erase("atk")
		# 유성추 —— 붙기 직전 던지기 한 방
		if v(u, "throw") > 0.0 and not u.sg.get("thrown", false) and u.tgt != null and u.tgt.alive:
			var g: float = b._gap(u, u.tgt)
			if g > 20.0 and g < 150.0:
				u.sg["thrown"] = true
				_say(u, "유성추 —— 달려들며 던졌다")
				b.phys_hit(u, u.tgt, v(u, "throw"), true)
		# 선술 —— 붙잡히면 물러나 나타난다
		if v(u, "blink") > 0.0 and b._pinned(u) and _due(u, "blink", 8.0):
			var pn = b._pinner(u, _foes(u))
			if pn != null:
				var away: Vector2 = (u.pos - pn.pos)
				u.pos += (away.normalized() if away.length() > 0.1 else Vector2(-1.0 if u.camp == "B" else 1.0, 0.0) * -1.0) * 150.0
				b._clamp_arena(u)
				_say(u, "선술 —— 홀연히 자리를 옮겼다")
		# 간웅 —— 고유기를 맞으면 되받아친다
		if u.sg.has("ret") and not b._in_ult:
			var ra = u.sg["ret"]
			u.sg.erase("ret")
			if ra != null and ra.alive:
				_say(u, "간웅 —— 되받아쳤다")
				_stat("sig_ult_ret")
				b.phys_hit(u, ra, minf(2.5, v(u, "ult_ret")), true)
	for u in who.get("taunt", []):      # 11/21 도발 —— 키 하나(taunt)로 누구에게나 붙는 일반 장치
		if u.alive and _due(u, "taunt", TAUNT_PULSE):
			_taunt(u)
	_scholar_tick()
	if _due(null, "aura", AURA_T):
		_auras()


# ───────── 도발 (11/21) ─────────
## 도발 —— TAUNT_PULSE 초마다 반지름(TAUNT_R × 등급 세기) 안의 적 부대에 '도발' 을 건다. 걸린 적은 TAUNT_HOLD 초 동안
## 표적을 도발한 부대로 돌린다 (근접은 다른 적에게 묶여 있으면 도발한 부대가 손 닿는 거리일 때만, 원거리는 사거리 안일 때만 —— RtBattle 이동).
## 기록: o.sg["tnt"] = 도발한 부대 · o.sg["tnt_t"] = 풀리는 시각. 화면 딱지는 shown() 의 "taunted"
func _taunt(u) -> void:
	var r := TAUNT_R * tier_mul("taunt", int(u.c.tier))
	var tm: float = b._tm
	var fresh := 0
	for o in _foes(u):
		if b._hidden(o) or b._gap(u, o) > r:
			continue
		var cur = o.sg.get("tnt")
		if cur != null and cur != u and cur.alive and tm < float(o.sg.get("tnt_t", 0.0)) and v(cur, "taunt") >= v(u, "taunt"):
			continue      # 더 센 도발이 이미 걸려 있다
		if cur != u or tm >= float(o.sg.get("tnt_t", 0.0)):
			fresh += 1
		o.sg["tnt"] = u
		o.sg["tnt_t"] = tm + TAUNT_HOLD
	if fresh > 0:
		_stat("sig_taunt", fresh)
		if tm >= float(u.sg.get("tnt_say", 0.0)):
			u.sg["tnt_say"] = tm + TAUNT_SAY
			_say(u, "도발 —— 주변 적 %d부대가 달려든다" % fresh)


## 도발에 걸려 있으면 도발한 부대 (풀렸거나 쓰러졌으면 null)
func taunt_of(o):
	var t = o.sg.get("tnt")
	if t == null:
		return null
	if not t.alive or b._tm >= float(o.sg.get("tnt_t", 0.0)):
		o.sg.erase("tnt")
		return null
	return t


## 화면 딱지 —— Battle._shown_st 가 덧붙인다 (상태이상이 아닌 표시용: 도발에 걸림 · 불사 버팀)
func shown(u, out: Array) -> void:
	if u.sg.has("tnt") and taunt_of(u) != null:
		out.append("taunted")
	if u.sg.has("ud_show") and b._tm < float(u.sg["ud_show"]):
		out.append("undying")


func _near(u, pool: Array, r := R_AURA) -> Array:
	return pool.filter(func(o): return o.alive and o.pos.distance_to(u.pos) < r)


## 오라 —— AURA_T 마다 다시 잰다 (sga 는 eff 가 곱하는 몫)
func _auras() -> void:
	for o in b.units:
		var keep_atk = o.sga.get("atk") if o.sg.has("rage_off") else null
		o.sga.clear()
		if keep_atk != null:
			o.sga["atk"] = keep_atk
	var tm: float = b._tm
	for u in b.units:
		if not u.alive or u.m.is_empty():
			continue
		var al := _allies(u)
		var fo := _foes(u)
		_scholar_aura(u, al, fo)
		if v(u, "roar") > 0.0:
			var hit := _near(u, fo)
			for o in hit:
				o.morale -= v(u, "roar")
				u.mdmg += v(u, "roar")
				o.sga["spd"] = float(o.sga.get("spd", 0.0)) - 0.2
			if not hit.is_empty():
				_say(u, "일갈 —— 주변 적이 움츠러든다", false)
				_stat("sig_roar", hit.size())
		if v(u, "cheer_aura") > 0.0:
			for o in _near(u, al):
				var g := minf(200.0 - o.morale, v(u, "cheer_aura"))
				if g > 0.0:
					o.morale += g
					u.hmo += g
					_note(u, "cheer_aura")
		if v(u, "cleanse_aura") > 0.0:
			for o in _near(u, al, R_AURA * 1.5):
				if not o.st.is_empty() and b.rng.randf() < v(u, "cleanse_aura"):
					b.cleanse(o)
					_note(u, "cleanse_aura")
					break
		if v(u, "spd_aura") > 0.0:
			for o in _near(u, al):
				o.sga["spd"] = float(o.sga.get("spd", 0.0)) + v(u, "spd_aura")
				_note(u, "spd_aura")
		if v(u, "def_aura") > 0.0:
			for o in _near(u, al):
				o.sga["def"] = float(o.sga.get("def", 0.0)) + v(u, "def_aura")
				_note(u, "def_aura")
		if v(u, "atk_down") > 0.0:
			for o in _near(u, fo):
				o.sga["atk"] = float(o.sga.get("atk", 0.0)) - v(u, "atk_down")
				_note(u, "atk_down")
		if v(u, "quake") > 0.0:
			for o in _near(u, fo):
				o.sga["spd"] = float(o.sga.get("spd", 0.0)) - v(u, "quake")
		if v(u, "cav_aura") > 0.0:
			for o in al:
				if o.c.tag == "기병":
					o.sga["atk"] = float(o.sga.get("atk", 0.0)) + v(u, "cav_aura")
		if v(u, "caster_aura") > 0.0:
			for o in al:
				if b.is_caster(o.c):
					o.sga["atk"] = float(o.sga.get("atk", 0.0)) + v(u, "caster_aura")
		if v(u, "tier_aura") > 0.0:
			var top := 0
			for o in al:
				top = maxi(top, int(o.c.tier))
			for o in al:
				if int(o.c.tier) >= top:
					o.sga["atk"] = float(o.sga.get("atk", 0.0)) + v(u, "tier_aura")
					_note(u, "tier_aura")
		if v(u, "boost_best") > 0.0:
			var best = null
			for o in al:
				if o != u and (best == null or float(o.c.atk) > float(best.c.atk)):
					best = o
			if best != null:
				best.sga["atk"] = float(best.sga.get("atk", 0.0)) + v(u, "boost_best")
				_note(u, "boost_best")
		if v(u, "gauge_aura") > 0.0:
			for o in al:
				if o.ult != null and o.charges > 0:
					o.gauge = minf(100.0, o.gauge + v(u, "gauge_aura"))
					_note(u, "gauge_aura")
		if v(u, "morale_floor") > 0.0:
			for o in _near(u, al):
				o.morale = maxf(o.morale, v(u, "morale_floor"))
		if v(u, "confuse_aura") > 0.0:
			for o in _near(u, fo, 200.0):
				var sk: String = str(u.key) + ">" + str(o.key)
				if not _seen.has(sk):
					_seen[sk] = true
					b.inflict(u, o, "confuse", 1.0, 1)
		if v(u, "give_troops") > 0.0 and _due(u, "give", 8.0):
			var hurt = null
			for o in al:
				if o != u and o.troops < o.max * GIVE_BELOW and (hurt == null or o.troops / o.max < hurt.troops / hurt.max):
					hurt = o
			if hurt != null and u.troops > u.max * 0.4:
				var g2 := minf(hurt.max - hurt.troops, minf(u.troops * 0.5, hurt.max * v(u, "give_troops")))
				if g2 > 0.0:
					u.troops -= g2
					hurt.troops += g2
					u.htr += g2
					_stat("sig_give_troops")
					b.L("hl", "%s의 양보 —— %s에게 병력을 나눠 주었다" % [b.nm(u), b.nm(hurt)], {"fx": "heal", "f": hurt.key, "n": g2, "healer": u.key, "sig": true})
		if v(u, "truce") > 0.0 and _due(u, "truce", 12.0) and not fo.is_empty():
			var t0 = fo[b.rng.randi_range(0, fo.size() - 1)]
			b.inflict(u, t0, "confuse", 1.0, 1)
			_say(u, "화친 —— 적 하나가 칼을 거두었다")
			_stat("sig_truce")
		if v(u, "mark") > 0.0 and _due(u, "mark", 10.0):
			var best2 = null
			for o in fo:
				if best2 == null or (o.ult != null and best2.ult == null) or (int(o.c.tier) > int(best2.c.tier)) or (int(o.c.tier) == int(best2.c.tier) and o.troops > best2.troops):
					best2 = o
			if best2 != null:
				_mark[u.camp] = best2
				_stat("sig_mark")
				b.L("sk", "%s의 정군 —— %s 지목" % [b.nm(u), b.nm(best2)], {"fx": "debuff", "f": best2.key, "a": u.key, "sig": true})
		if v(u, "trap") > 0.0 and _due(u, "trap", 8.0) and not fo.is_empty():
			var near = b._nearest(u.pos, fo)
			if near != null:
				b.L("sk", "%s의 십면매복 —— 함정이 터졌다" % b.nm(u), {"fx": "skill", "a": u.key, "name": "십면매복", "kind": "int"})
				_stat("sig_trap")
				b.phys_hit(u, near, v(u, "trap"), true)
				b.inflict(u, near, "flood", 0.0, 1)
		if v(u, "rain") > 0.0 and _due(u, "rain", 10.0):
			for o in al:
				for s in o.st:
					if s.k == "burn":
						s.dur = 0
			if not fo.is_empty():
				b.inflict(u, fo[b.rng.randi_range(0, fo.size() - 1)], "flood", 0.0, 2)
			_say(u, "청우 —— 비가 내린다")



# ── 모사 · 유생 (1.2) ──
## 11/21 1.2 전장의 개성 —— 모사 16 · 유생 18. 책략 병종은 장치가 이미 많아('숫자만 바뀌는' 오라가 많았다) 겹치는 사람끼리 갈래를 나눈다:
##  · 기 채우기 셋: 전원에게 조금(여범 gauge_aura) · 가장 찬 한 명에게 몰아서(순욱 gauge_top) · 고유기를 쓴 직후 되돌려 줌(장완 gauge_refund)
##  · 방어 셋: 주변 + 제 속도↓(심배 def_aura · slow_self) · 가장 위태로운 한 부대만 크게(노숙 def_weak) · 아주 넓은 범위(장소 ward_aura)
##  · 병력 주기 둘: 자기 병력을 덜어 위기 아군에게(도겸 give_troops) · 덜지 않고 꺾인 아군을 치료(미축 supply)
##  · 사기 둘: 주변 전원 조금씩(유비 cheer_aura) · 사기 가장 낮은 한 명을 크게(채문희 song)
##  · 상태이상 풀기: 확률로 하나 씻김(전풍 · 비의 cleanse_aura) · 지속을 줄임(보즐 st_short)
## 눈에 보이게 —— 숫자만 바뀌는 오라는 SAYS 의 말풍선(간격 SAY_GAP)으로 알린다. 수치는 상식선 기본값(밸런스 측정 없음).
## 등급 세기 —— 5급 기준 한 급마다 +10% (TIER_BASE · TIER_STEP). 상세창 수치도 같은 값 (tier_mul)
const TIER_SCHOLAR := {"gauge_top": true, "gauge_refund": true, "gauge_aura": true, "def_weak": true, "ward_aura": true, "def_aura": true,
	"song": true, "supply": true, "give_troops": true, "cheer_aura": true, "spd_aura": true, "atk_down": true, "boost_best": true,
	"tier_aura": true, "cleanse_aura": true}
const LABELS_SCHOLAR := {
	"slow_self": ["자신 속도 -", "%"], "gauge_top": ["8초마다 기가 가장 찬 아군 고유기 기", "n"], "gauge_refund": ["고유기를 쓴 아군에게 돌려주는 기", "n"],
	"def_weak": ["가장 위태로운 아군 방어", "%"], "ward_aura": ["넓은 범위 아군 방어", "%"], "song": ["8초마다 사기 낮은 아군 하나 사기", "n"],
	"supply": ["8초마다 꺾인 아군 치료", "%"], "st_short": ["", ""], "fame": ["", ""]}
const SAY_GAP := 10.0       # 말풍선 기본 간격 (초) —— 같은 장수 · 같은 일은 이 간격 안에 한 번만
const TOP_T := 8.0          # 순욱 —— 가장 찬 아군에게 기를 몰아주는 간격 (초, 오라 주기 4초의 배수)
const SONG_T := 8.0         # 채문희 —— 사기 낮은 아군을 일으키는 간격
const SONG_LOW := 90.0      # 채문희 —— 사기가 이 아래인 아군만
const SUPPLY_T := 8.0       # 미축 —— 군량을 푸는 간격
const SUPPLY_LOW := 0.7     # 미축 —— 병력 비율이 이 아래인 아군만
const GIVE_BELOW := 0.35   # 도겸 —— 병력 비율이 이 아래인 위기 아군에게만 제 병력을 나눈다
const WEAK_BELOW := 0.9     # 노숙 —— 병력 비율이 이 아래여야 '위태로운 아군'
const WARD_R := 1.7         # 장소 —— 방어 결계 반지름 (오라 반지름 배수)
const SHORT_R := 1.3        # 보즐 —— 상태이상 지속을 줄이는 반지름 (오라 반지름 배수)
const EARLY_END := 25.0     # 원술 —— 칭제 기세가 꺾였다고 알리는 때 (초)
const LATE_SAY := 24.0      # 사마의 —— 낭고가 발톱을 드러냈다고 알리는 때 (초)
const BEHIND_SAY := 12.0    # 진궁 —— 밀리고 있다고 알리는 간격
## 키별 말풍선 [글, 간격(초), 올라감(true) / 내려감(false)] —— 이름은 SCHOLAR_NAME (모사 · 유생 34명만 말한다)
const SAYS := {
	"shove": ["적을 뒤로 밀어냈다", 6.0, true], "gauge_on": ["말솜씨로 적의 기를 뺐다", 8.0, true], "bleed_on": ["적이 피를 흘린다", 6.0, false],
	"cheer_aura": ["주변 아군의 사기가 오른다", 10.0, true], "cleanse_aura": ["아군의 이상을 풀어 주었다", 8.0, true],
	"spd_aura": ["아군의 발걸음이 가벼워졌다", 12.0, true], "def_aura": ["아군의 방어가 단단해졌다", 12.0, true],
	"atk_down": ["주변 적이 넋을 잃었다", 10.0, false], "tier_aura": ["가장 높은 등급 부대가 힘을 낸다", 12.0, true],
	"boost_best": ["가장 강한 아군 장수에게 힘을 실었다", 12.0, true], "gauge_aura": ["아군의 기가 차오른다", 10.0, true],
	"rear_spawn": ["적의 등 뒤에 나타났다", 999.0, true], "frail_water": ["물에 잠겨 무너진다", 10.0, false],
	"ward_aura": ["넓은 결계로 아군을 감쌌다", 12.0, true], "st_short": ["아군의 이상이 가라앉는다", 8.0, true]}
const SCHOLAR_NAME := {"가후": "독사", "초선": "경국", "사마의": "낭고", "조조": "간웅", "진궁": "백문 결의", "등애": "음평 기습", "원술": "칭제", "정욱": "십면매복",
	"전풍": "강직", "이유": "독살", "맹달": "변절 유도", "여범": "재무", "동소": "밀어내기", "마속": "산상 포진", "보즐": "안정", "심배": "농성",
	"유비": "인의", "순욱": "왕좌", "노숙": "대의", "사마휘": "수경", "법정": "정군", "미축": "군량 보급", "대교": "국색", "소교": "청아", "장소": "보국",
	"채문희": "호가", "장완": "정무", "공융": "명사", "도겸": "양보", "비의": "중재", "간옹": "담소", "제갈근": "화친", "진군": "구품", "진림": "격문"}


static func tiered(k: String) -> bool:
	return TIER_KEYS.has(k) or TIER_SCHOLAR.has(k)


## 모사 · 유생이면 그 특성 이름 (아니면 "" —— 말하지 않는다)
func _sn(u) -> String:
	return str(SCHOLAR_NAME.get(DB.person(u.c.id), ""))


## 같은 장수 · 같은 일은 gap 초 안에 한 번만 말풍선 (모사 · 유생만)
func _say_gap(u, job: String, text: String, gap := SAY_GAP, up := true) -> void:
	var jk := "sy_" + job
	if b._tm < float(u.sg.get(jk, 0.0)):
		return
	u.sg[jk] = b._tm + gap
	var nm := _sn(u)
	if nm == "":
		return
	_say(u, "%s —— %s" % [nm, text], up)


## 발동 기록(점검용 통계) + SAYS 말풍선
func _note(u, k: String, n := 1) -> void:
	_stat("sig_" + k, n)
	var sy = SAYS.get(k)
	if sy != null:
		_say_gap(u, k, str(sy[0]), float(sy[1]), bool(sy[2]))


## 전투 시작 —— 명사(공융)는 아군 시작 사기를 올려 두었다고 알린다
func _scholar_setup() -> void:
	for u in who.get("fame", []):
		_say_gap(u, "fame", "아군 전원의 의기가 높아졌다", 999.0)


func _weakest(al: Array, below: float):
	var best = null
	for o in al:
		var r: float = o.troops / maxf(1.0, o.max)
		if r < below and (best == null or r < best.troops / maxf(1.0, best.max)):
			best = o
	return best


func _is_behind(a) -> bool:
	var mine := 0.0
	var theirs := 0.0
	for o in b.units:
		if o.alive:
			if o.camp == a.camp: mine += o.troops
			else: theirs += o.troops
	return mine < theirs * 0.85


## 시각으로 알리는 것 · 쓴 순간을 지켜보는 것 (프레임마다)
func _scholar_tick() -> void:
	var tm: float = b._tm
	for u in who.get("amp_early", []):      # 칭제 —— 초반 기세와 그 끝
		if u.alive:
			if tm < 4.0:
				_say_gap(u, "early", "천하를 얻은 듯 기세가 하늘을 찌른다", 999.0)
			elif tm >= EARLY_END:
				_say_gap(u, "early_end", "기세가 한풀 꺾였다", 999.0, false)
	for u in who.get("amp_late", []):      # 낭고 —— 늦게 드러내는 발톱
		if u.alive and tm >= LATE_SAY:
			_say_gap(u, "late", "숨겨 둔 발톱을 드러낸다", 999.0)
	for u in who.get("amp_behind", []):      # 백문 결의 —— 밀릴 때
		if u.alive and tm >= float(u.sg.get("bh_chk", 0.0)):
			u.sg["bh_chk"] = tm + 1.0
			if _is_behind(u):
				_say_gap(u, "behind", "밀릴수록 이를 악문다", BEHIND_SAY)
	for u in who.get("gauge_refund", []):      # 정무 —— 고유기를 쓴 아군에게 기를 돌려준다
		if not u.alive:
			continue
		for o in _allies(u):
			if o.ult == null:
				continue
			var jk := "gr_" + str(o.key)
			var seen: float = float(u.sg.get(jk, -99.0))
			if o.ult_tm > seen:
				u.sg[jk] = o.ult_tm
				if seen > -99.0 or o.ult_tm > 0.0:
					if o.charges > 0:
						o.gauge = minf(100.0, o.gauge + v(u, "gauge_refund"))
						_stat("sig_gauge_refund")
						_say_gap(u, "refund", "%s의 고유기에 기를 보태 주었다" % b.nm(o), 6.0)


## 오라 주기마다 (AURA_T) —— 모사 · 유생의 갈래 (sga 는 이 주기 앞에서 비워졌다)
func _scholar_aura(u, al: Array, fo: Array) -> void:
	if v(u, "slow_self") > 0.0:      # 농성 —— 진영은 단단히, 제 몸은 무겁다
		u.sga["spd"] = float(u.sga.get("spd", 0.0)) - minf(0.6, v(u, "slow_self"))
	if v(u, "def_weak") > 0.0:      # 대의 —— 가장 위태로운 한 부대만 크게 감싼다
		var weak = _weakest(al, WEAK_BELOW)
		if weak != null:
			weak.sga["def"] = float(weak.sga.get("def", 0.0)) + v(u, "def_weak")
			_stat("sig_def_weak")
			if u.sg.get("dw") != weak:
				u.sg["dw"] = weak
				_say_gap(u, "dw", "%s을(를) 감싼다" % b.nm(weak), 6.0)
	if v(u, "ward_aura") > 0.0:      # 보국 —— 아주 넓은 범위의 방어 결계
		var hit := _near(u, al, R_AURA * WARD_R)
		for o in hit:
			o.sga["def"] = float(o.sga.get("def", 0.0)) + v(u, "ward_aura")
		if not hit.is_empty():
			_note(u, "ward_aura", hit.size())
	if v(u, "st_short") > 0.0:      # 안정 —— 걸린 이상의 지속을 줄인다
		var cut := 0
		for o in _near(u, al, R_AURA * SHORT_R):
			for s in o.st:
				if int(s.dur) > 1:
					s.dur = int(s.dur) - 1
					cut += 1
		if cut > 0:
			_note(u, "st_short", cut)
	if v(u, "gauge_top") > 0.0 and _due(u, "gtop", TOP_T):      # 왕좌 —— 기가 가장 찬 아군 한 명에게 몰아준다
		var top = null
		for o in al:
			if o.ult != null and o.charges > 0 and o.gauge < 100.0 and (top == null or o.gauge > top.gauge):
				top = o
		if top != null:
			top.gauge = minf(100.0, top.gauge + v(u, "gauge_top"))
			_stat("sig_gauge_top")
			_say_gap(u, "gtop", "%s의 기를 북돋웠다" % b.nm(top), 6.0)
	if v(u, "song") > 0.0 and _due(u, "song", SONG_T):      # 호가 —— 사기가 가장 낮은 한 명을 일으킨다
		var low = null
		for o in al:
			if o.morale < SONG_LOW and (low == null or o.morale < low.morale):
				low = o
		if low != null:
			var g := minf(200.0 - low.morale, v(u, "song"))
			if g > 0.0:
				low.morale += g
				u.hmo += g
				_stat("sig_song")
				_say_gap(u, "song", "%s의 사기를 일으켰다" % b.nm(low), 6.0)
	if v(u, "supply") > 0.0 and _due(u, "supply", SUPPLY_T):      # 군량 보급 —— 제 병력은 덜지 않고 꺾인 아군을 치료
		var hurt = _weakest(al, SUPPLY_LOW)
		if hurt != null:
			var before: float = hurt.troops
			b.heal_troop(hurt, v(u, "supply"), "군량 보급", u)
			if hurt.troops > before:
				_stat("sig_supply")
				_say_gap(u, "supply", "%s에게 군량을 풀었다" % b.nm(hurt), 6.0)
