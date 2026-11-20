extends RefCounted
## 11/19 장수 개성 —— 사용자 "같은 병종이라도 장수마다 다른 특징이 명확하게 두드러지게" (docs/장수_개성_정리_1119.md 4장).
## 장수마다 고유 특기 하나(passives.json traits, unique)의 m 키를 읽어 실시간 엔진에 행동을 붙인다.
## 판정 자리: 표적(target_w) · 주는 피해(amp) · 받는 피해(taken) · 맞힌 뒤(after_hit) · 맞은 뒤(after_taken) · 쓰러뜨림(on_kill)
## · 이동(steer) · 주기(tick) · 패주 버팀(hold_rout · calm). 판정은 rng 만 쓰고 부대 순서대로 돈다 (결정적).

const KEYS := ["taunt", "seek_low", "seek_gen", "seek_back", "seek_cav", "seek_strong", "seek_guard",
	"amp_low", "amp_cav", "amp_strong", "amp_gen", "amp_rear", "amp_open", "amp_same", "amp_still", "amp_come", "amp_drown",
	"amp_allies", "amp_early", "amp_late", "amp_last", "amp_behind", "amp_far", "amp_kill", "amp_guard", "no_pin",
	"charge_amp", "charge_run", "dr_still", "dr_link", "dr_low", "dr_early", "dodge_big", "ult_dr",
	"shove", "bind", "slow_on", "morale_on", "gauge_on", "bleed_on", "pierce_hit", "throw",
	"counter_all", "dr_guard", "enrage", "ult_ret", "chain", "kill_gauge", "absorb", "undying", "ally_calm", "morale_floor",
	"kite", "hit_run", "blink", "stealth", "ambush", "rear_spawn",
	"roar", "cheer_aura", "cleanse_aura", "spd_aura", "def_aura", "atk_down", "cav_aura", "caster_aura", "tier_aura", "boost_best",
	"give_troops", "truce", "mark", "trap", "rain", "quake", "confuse_aura", "gauge_aura", "frail_water",
	"cav_show"]      # 1.2 기병 —— 숫자만 바뀌는 특기(속도 · 방어 · 회복 · 수몰 저항)의 말풍선 표식 (값은 1, 판정에는 안 쓴다)

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
	if x != 0.0 and TIER_KEYS.has(k):
		x *= tier_mul(k, int(u.c.tier))
	return x


## 등급 세기 배율 (TIER_KEYS 만) —— 장수 정보창 설명(DB.mods_list)도 같은 값을 쓴다
static func tier_mul(k: String, tier: int) -> float:
	if not TIER_KEYS.has(k):
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
	if v(a, "amp_late") > 0.0: m *= 1.0 + v(a, "amp_late") * clampf((tm - 20.0) / 30.0, 0.0, 1.0)
	if v(a, "amp_last") > 0.0 and _allies(a).size() <= 3: m *= 1.0 + v(a, "amp_last")
	if v(a, "amp_behind") > 0.0:
		var mine := 0.0
		var theirs := 0.0
		for o in b.units:
			if o.alive:
				if o.camp == a.camp: mine += o.troops
				else: theirs += o.troops
		if mine < theirs * 0.85: m *= 1.0 + v(a, "amp_behind")
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
	return m


## 때린 뒤 (때린 쪽 키) —— loss 는 이번 타격이 깎은 병력
func after_hit(a, d, loss: float, far: bool) -> void:
	if a.m.is_empty() or a.countering or a.sg.get("piercing", false):
		return
	a.sg["hits"] = int(a.sg.get("hits", 0)) + 1
	a.sg["same"] = int(a.sg.get("same", 0)) + 1 if a.sg.get("last") == d else 0
	a.sg["last"] = d
	cav_hit(a, d, loss, far)      # 1.2 기병 —— 계수 · 말풍선
	if not d.alive:
		return
	if v(a, "shove") > 0.0 and (not far or b._ranged(a)) and not b._in_ult:
		var dir: Vector2 = d.pos - a.pos
		if dir.length() > 0.1:
			d.pos += dir.normalized() * minf(30.0, v(a, "shove"))
			b._clamp_arena(d)
	if v(a, "bind") > 0.0 and b.rng.randf() < v(a, "bind"):
		b.inflict(a, d, "flood", 0.0, 1)
		cav_bind(a, d)
	if v(a, "slow_on") > 0.0 and b.rng.randf() < 0.35:
		d.sga["spd"] = minf(float(d.sga.get("spd", 0.0)), -minf(0.5, v(a, "slow_on")))
	if v(a, "morale_on") > 0.0:
		d.morale -= v(a, "morale_on")
		a.mdmg += v(a, "morale_on")
	if v(a, "gauge_on") > 0.0 and d.ult != null:
		d.gauge = maxf(0.0, d.gauge - v(a, "gauge_on"))
	if v(a, "bleed_on") > 0.0 and b.rng.randf() < v(a, "bleed_on"):
		b.inflict(a, d, "bleed", 0.05, 2)
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
				cav_pierce(a, best)
	if v(a, "hit_run") > 0.0 and not far and b._tm >= float(a.sg.get("run_cd", 0.0)):
		a.sg["back"] = b._tm + minf(2.0, v(a, "hit_run"))
		a.sg["run_cd"] = b._tm + 3.5


## 맞은 뒤 (맞은 쪽 키)
func after_taken(d, a, loss: float, far: bool) -> void:
	if d.m.is_empty() or not d.alive or a == null:
		return
	var tm: float = b._tm
	cav_taken(d, a, loss, far)      # 1.2 기병 —— 계수 · 말풍선
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
	cav_kill(k, victim)      # 1.2 기병 —— 계수 · 말풍선
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
	return cav_steer(u, t, desired)      # 1.2 기병 —— 장합 우회


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
				_cav(u, "throw")
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
				b.phys_hit(u, ra, minf(2.5, v(u, "ult_ret")), true)
	for u in who.get("taunt", []):      # 11/21 도발 —— 키 하나(taunt)로 누구에게나 붙는 일반 장치
		if u.alive and _due(u, "taunt", TAUNT_PULSE):
			_taunt(u)
	cav_tick(dt)      # 1.2 기병 —— 숫자 특기 말풍선
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
		if v(u, "roar") > 0.0:
			var hit := _near(u, fo)
			for o in hit:
				o.morale -= v(u, "roar")
				u.mdmg += v(u, "roar")
				o.sga["spd"] = float(o.sga.get("spd", 0.0)) - 0.2
			if not hit.is_empty():
				_say(u, "일갈 —— 주변 적이 움츠러든다", false)
		if v(u, "cheer_aura") > 0.0:
			for o in _near(u, al):
				var g := minf(200.0 - o.morale, v(u, "cheer_aura"))
				if g > 0.0:
					o.morale += g
					u.hmo += g
		if v(u, "cleanse_aura") > 0.0:
			for o in _near(u, al, R_AURA * 1.5):
				if not o.st.is_empty() and b.rng.randf() < v(u, "cleanse_aura"):
					b.cleanse(o)
					break
		if v(u, "spd_aura") > 0.0:
			for o in _near(u, al):
				o.sga["spd"] = float(o.sga.get("spd", 0.0)) + v(u, "spd_aura")
		if v(u, "def_aura") > 0.0:
			for o in _near(u, al):
				o.sga["def"] = float(o.sga.get("def", 0.0)) + v(u, "def_aura")
		if v(u, "atk_down") > 0.0:
			for o in _near(u, fo):
				o.sga["atk"] = float(o.sga.get("atk", 0.0)) - v(u, "atk_down")
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
		if v(u, "boost_best") > 0.0:
			var best = null
			for o in al:
				if o != u and (best == null or float(o.c.atk) > float(best.c.atk)):
					best = o
			if best != null:
				best.sga["atk"] = float(best.sga.get("atk", 0.0)) + v(u, "boost_best")
		if v(u, "gauge_aura") > 0.0:
			for o in al:
				if o.ult != null and o.charges > 0:
					o.gauge = minf(100.0, o.gauge + v(u, "gauge_aura"))
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
				if o != u and o.troops < o.max * 0.5 and (hurt == null or o.troops / o.max < hurt.troops / hurt.max):
					hurt = o
			if hurt != null and u.troops > u.max * 0.4:
				var g2 := minf(hurt.max - hurt.troops, minf(u.troops * 0.5, hurt.max * v(u, "give_troops")))
				if g2 > 0.0:
					u.troops -= g2
					hurt.troops += g2
					u.htr += g2
					b.L("hl", "%s의 양보 —— %s에게 병력을 나눠 주었다" % [b.nm(u), b.nm(hurt)], {"fx": "heal", "f": hurt.key, "n": g2, "healer": u.key, "sig": true})
		if v(u, "truce") > 0.0 and _due(u, "truce", 12.0) and not fo.is_empty():
			var t0 = fo[b.rng.randi_range(0, fo.size() - 1)]
			b.inflict(u, t0, "confuse", 1.0, 1)
			_say(u, "화친 —— 적 하나가 칼을 거두었다")
		if v(u, "mark") > 0.0 and _due(u, "mark", 10.0):
			var best2 = null
			for o in fo:
				if best2 == null or (o.ult != null and best2.ult == null) or (int(o.c.tier) > int(best2.c.tier)) or (int(o.c.tier) == int(best2.c.tier) and o.troops > best2.troops):
					best2 = o
			if best2 != null:
				_mark[u.camp] = best2
				b.L("sk", "%s의 정군 —— %s 지목" % [b.nm(u), b.nm(best2)], {"fx": "debuff", "f": best2.key, "a": u.key, "sig": true})
		if v(u, "trap") > 0.0 and _due(u, "trap", 8.0) and not fo.is_empty():
			var near = b._nearest(u.pos, fo)
			if near != null:
				b.L("sk", "%s의 십면매복 —— 함정이 터졌다" % b.nm(u), {"fx": "skill", "a": u.key, "name": "십면매복", "kind": "int"})
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


# ── 기병 (1.2) ──
## 기병 22명(여포 · 조운 · 마초 · 장료 · 손책 · 장합 · 공손찬 · 마등 · 동탁 · 원소 · 문추 · 화웅 · 마대 · 조홍 · 곽회 · 한수 · 반장 · 오반 · 안량 · 오의 · 하후패 · 한당)의
## '발동했다' 계수(stats sig_*)와 '보이게'(말풍선 · 우회). 키 · 세기는 passives.json sig 그대로 —— 여기서는 계수 · 말풍선 · 우회 경로만 더한다.
## 계수와 말풍선은 판정(rng · 위치)을 바꾸지 않는다. 우회(장합)만 이동 방향을 더 꺾는다.
static var cav_fx := true             # 점검용 —— false 면 계수만 하고 말풍선 · 우회를 끈다 (전/후 비교. 게임에서는 늘 true)
const CAV_SAY := 6.0                  # 기병 말풍선 기본 간격 (초) —— 같은 장수 · 같은 말
const CAV_SAY_LONG := 12.0            # 자주 일어나는 것(오라 · 달림 · 병력 회복)의 간격
const FLANK_MIN := 170.0              # 이 거리 아래로 붙으면 우회를 멈추고 곧장 달려든다
const RUN_SPEED := 40.0               # '달리는 중' 으로 치는 속도 (한수 말풍선)


static func set_cav_fx(on: bool) -> void:
	cav_fx = on


## 계수 + (켜져 있으면) 말풍선 —— 같은 장수 · 같은 일은 every 초에 한 번만 말한다
func _cav(u, k: String, text := "", every := CAV_SAY, n := 1) -> void:
	_stat("sig_%s@%s" % [k, u.c.name], n)      # 계수는 그 장수 이름으로 (한 판에 같은 키를 가진 다른 부대와 섞이지 않게)
	if cav_fx and text != "" and _due(u, "cv_" + k, every):
		_say(u, text)


## 때린 뒤 —— 맞힌 쪽 키 (after_hit 에서 hits · last 갱신 직후)
func cav_hit(a, d, loss: float, far: bool) -> void:
	var tm: float = b._tm
	if v(a, "amp_early") > 0.0 and tm < 40.0:
		_cav(a, "amp_early", "개전 초반 —— 매섭게 몰아친다")
	if v(a, "amp_kill") > 0.0 and a.kills > 0:
		_cav(a, "amp_kill", "기세 —— 쓰러뜨린 적 %d부대, 공격이 오른다" % mini(3, a.kills))
	if v(a, "amp_allies") > 0.0:
		_cav(a, "amp_allies", "명문의 위세 —— 아군 %d부대가 받쳐 준다" % _allies(a).size(), CAV_SAY_LONG)
	if v(a, "amp_low") > 0.0 and d.troops + loss < d.max * LOW:
		_cav(a, "amp_low", "추격 —— 꺾인 적을 끝까지 쫓는다")
	if v(a, "amp_open") > 0.0 and int(a.sg.get("hits", 0)) <= 3:
		_cav(a, "amp_open", "효기 —— 첫 돌격이 거세다", 20.0)
	if v(a, "amp_rear") > 0.0:
		var dv: Vector2 = a.pos - d.pos
		if dv.length() > 0.1 and absf(d.fwd.angle_to(dv)) > PI / 3.0:
			_cav(a, "amp_rear", "급습 —— 옆 · 뒤를 쳤다")
	if v(a, "amp_cav") > 0.0 and d.c.tag == "기병":
		_cav(a, "amp_cav", "기병 견제 —— 적 기병을 아프게 쳤다")
	if v(a, "seek_back") > 0.0 and b._ranged(d):
		_cav(a, "seek_back", "후열 돌파 —— 원거리 부대를 잡았다")
	if v(a, "seek_guard") > 0.0 and d.tgt != null and d.tgt.alive and d.tgt.camp == a.camp and d.tgt != a:
		_cav(a, "seek_guard", "구원 —— 아군에게 붙은 적을 막았다")
	if v(a, "morale_on") > 0.0:
		_cav(a, "morale_on", "위압 —— 맞은 적의 사기가 꺾인다")
	if v(a, "hit_run") > 0.0 and not far and tm >= float(a.sg.get("run_cd", 0.0)):
		_cav(a, "hit_run", "치고 빠지기 —— 말머리를 돌린다")


## 꿰뚫음 한 번 (after_hit 의 pierce_hit 가 뒤의 적을 쳤을 때)
func cav_pierce(a, best) -> void:
	_cav(a, "pierce", "관통 —— %s까지 꿰뚫었다" % b.nm(best))


## 묶음 한 번 (bind 굴림이 맞았을 때)
func cav_bind(a, d) -> void:
	_cav(a, "bind", "포박 —— %s을(를) 묶었다" % b.nm(d))


## 쓰러뜨림 (on_kill 맨 앞)
func cav_kill(k, victim) -> void:
	if v(k, "chain") > 0.0:
		_cav(k, "chain")      # 말풍선은 on_kill 의 무쌍이 낸다
	if v(k, "amp_kill") > 0.0:
		_cav(k, "amp_kill_on", "기세 —— %s을(를) 무너뜨렸다" % b.nm(victim), 4.0)


## 맞은 뒤 (맞은 쪽 키)
func cav_taken(d, a, loss: float, far: bool) -> void:
	if int(v(d, "cav_show")) == 2 and v(d, "def") > 0.0:
		_cav(d, "def","중기병 —— 두꺼운 갑옷이 막아냈다", CAV_SAY_LONG)


## 돌격이 박힌 순간 (rt_battle 물리 타격에서 기병 돌격 가산을 받을 때)
func on_charge(a, d) -> void:
	if v(a, "charge_amp") > 0.0:
		_cav(a, "charge_amp", "맹습 —— 돌격이 더 깊이 박힌다")
	if v(a, "charge_run") > 0.0 and a.ran < RtBattle.CHARGE_RUN:
		_cav(a, "charge_run", "즉시 돌격 —— 짧게 달려도 부딪는다")
	if v(a, "chain") > 0.0 and a.kills > 0:
		_cav(a, "chain_charge")      # 무쌍 이후 돌격이 박힘 (여포)


## 이동 —— 장합 우회: 후열(원거리)을 노리는 기병은 적 무리 옆 바깥 길목(도적 우회와 같은 _flank_way)을 지나 노린 적 뒤로 돌아 든다 (steer 끝에서)
func cav_steer(u, t, desired: Vector2) -> Vector2:
	if desired == Vector2.ZERO or u.c.tag != "기병" or v(u, "seek_back") <= 0.0 or not b._ranged(t):
		return desired
	if b._gap(u, t) <= FLANK_MIN:
		return desired
	var way = b._flank_way(u, t, _foes(u))
	if way == null:
		return desired
	var wv: Vector2 = way - u.pos
	if wv.length() <= 20.0:
		return desired
	if _due(u, "cv_flank_t", 3.0):
		_cav(u, "flank", "우회 —— 옆으로 돌아 후열을 노린다", CAV_SAY_LONG)
	if not cav_fx:
		return desired
	return wv.normalized() * desired.length()


## 주기 (tick 끝에서) —— 숫자만 바뀌는 특기(속도 · 회복 · 수몰 저항 · 오라)를 말풍선으로 보인다
func cav_tick(dt: float) -> void:
	for u in b.units:
		if not u.alive or u.m.is_empty():
			continue
		var show := int(v(u, "cav_show"))      # 숫자 특기 표식 —— 1 속도(한수) · 2 방어(오의) · 3 회복(하후패) · 4 수몰 저항(한당). 일반 능력치와 섞이지 않게 장수가 정한다
		if show == 1 and v(u, "spd") > 0.0 and u.vel.length() > RUN_SPEED and _due(u, "cv_spd_t", CAV_SAY_LONG):
			_cav(u, "spd", "경기병 —— 쏜살같이 달린다", 0.0)
		if show == 3 and v(u, "regen") > 0.0 and u.troops < u.max * 0.95 and _due(u, "cv_regen_t", CAV_SAY_LONG):
			_cav(u, "regen", "추스름 —— 흩어진 병력을 추슬렀다", 0.0)
		if show == 4 and v(u, "flood_res") > 0.0 and b.has_st(u, "flood") and _due(u, "cv_flood_t", CAV_SAY_LONG):
			_cav(u, "flood_res", "강동 기병 —— 물살에도 말을 몰아간다", 0.0)
		if v(u, "cav_aura") > 0.0 and _due(u, "cv_aura_t", AURA_T):
			_cav(u, "cav_aura", "서량 기치 —— 아군 기병의 기세가 오른다", CAV_SAY_LONG)
