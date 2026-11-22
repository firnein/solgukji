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
	"give_troops", "truce", "mark", "trap", "rain", "quake", "confuse_aura", "gauge_aura", "frail_water",
	"escort", "seek_rear", "die_hard", "burn_out", "twin", "dr_last",      # 1.2 창병
	"revive", "fire_chain", "gauge_cut", "cult", "dr_early_all",      # 1.2 책사 · 술사
	"cav_show",      # 1.2 기병 —— 숫자만 바뀌는 특기(속도 · 방어 · 회복 · 수몰 저항)의 말풍선 표식 (값은 1, 판정에는 안 쓴다)
	"rear_land", "breach", "rescue", "bridge", "feign_fire", "breakout", "flee", "body_guard"]      # 11/22 특별한 특기 —— 전장 행동을 바꾼다 (아래 「특별한 특기」)
const SPECIAL_KEYS := ["rear_land", "breach", "rescue", "bridge", "feign_fire", "breakout", "flee", "body_guard"]

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
const TIER_KEYS := {"taunt": true, "dr_guard": true, "counter_all": true, "dr_low": true,
	"amp_low": true, "amp_same": true, "pierce_hit": true, "enrage": true, "roar": true, "shove": true, "amp_guard": true, "dr_still": true, "escort": true, "die_hard": true,      # 1.2 창병
	"ult_dr": true, "amp_gen": true, "dodge_big": true, "dr_early_all": true, "caster_aura": true, "cult": true, "quake": true,      # 1.2 책사 · 술사 (곽가 · 주건평 · 우번 · 이의 · 남화노선 · 장각 · 황권 · 장보)
	"amp_far": true, "amp_still": true, "amp_come": true, "amp_open": true, "amp_cav": true, "amp_allies": true, "amp_drown": true}      # 1.2 궁병 · 도적 —— 피해 · 감소 몫

static var special_on := true      # 11/22 특별한 특기(SPECIAL_KEYS · 음평 착지) —— 점검(tests/sig_special --off)이 끄고 전 · 후를 잰다. 게임에서는 늘 true
static var special_only := []      # 점검용 —— 비어 있지 않으면 이 특별 특기 키만 켠다 (그 카드 하나의 효과만 재게)

var b      # RtBattle
var hide_until := 0.0       # 숨은 부대가 있을 수 있는 마지막 시각 —— RtBattle._foes_of 가 이때까지만 숨은 부대를 거른다 (여몽 위장 · 황개 거짓 항복 · 조조 할수기포)
var who := {}              # 키 -> 그 키를 가진 부대들 (전투 시작에 한 번)
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
		for k in (KEYS + NOTE_KEYS) if u.c.tag in SAGE_TAGS else KEYS:      # 엔진 기본 키는 책사 · 술사만 (말풍선용)
			if float(u.m.get(k, 0.0)) != 0.0:
				if k in SPECIAL_KEYS and (not special_on or (not special_only.is_empty() and not k in special_only)):
					continue
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
				_f(u, "ambush", 0.0)
			else:                  # 등애 —— 적 뒤에서
				var back := c.x
				for o in foes:
					back = maxf(back, o.pos.x) if sx > 0 else minf(back, o.pos.x)
				u.pos = Vector2(back + sx * 90.0, c.y + (60.0 if u.slot % 2 == 0 else -60.0))
				u.fwd = Vector2(-sx, 0.0)
				_note_m(u, "rear_spawn")
	for u in who.get("stealth", []):
		u.sg["hide"] = v(u, "stealth")
		hide_until = maxf(hide_until, v(u, "stealth"))
		_f(u, "stealth", 0.0)
	_special_setup()


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
	w *= _spear_w(u, o)      # 1.2 창병 호위 · 후위 수비
	return maxf(0.15, w)


# ───────── 피해 ─────────

## 때리는 쪽 배율 (기본 공격 · 반격 · 기술 · 고유기 모두)
func amp(a, d, far: bool) -> float:
	if a.m.is_empty():
		return 1.0
	var m := 1.0
	var tm: float = b._tm
	if v(a, "amp_low") > 0.0 and d.troops < d.max * LOW: m *= 1.0 + v(a, "amp_low")
	if v(a, "amp_cav") > 0.0 and d.c.tag == "기병": m *= _f(a, "amp_cav", 1.0 + v(a, "amp_cav"))
	if v(a, "amp_strong") > 0.0 and (d.c.tier > a.c.tier or float(d.c.atk) > float(a.c.atk)): m *= 1.0 + v(a, "amp_strong")
	if v(a, "amp_gen") > 0.0 and d.ult != null: m *= 1.0 + v(a, "amp_gen"); _stat("sig_amp_gen"); _note(a, "amp_gen", "고유기를 가진 적의 약점을 짚었다")
	if v(a, "amp_rear") > 0.0:
		var dv: Vector2 = a.pos - d.pos
		if dv.length() > 0.1 and absf(d.fwd.angle_to(dv)) > PI / 3.0:
			m *= 1.0 + v(a, "amp_rear")
	if v(a, "amp_open") > 0.0 and int(a.sg.get("hits", 0)) < 3: m *= _f(a, "amp_open", 1.0 + v(a, "amp_open"))
	if v(a, "amp_same") > 0.0 and a.sg.get("last") == d: m *= _f(a, "amp_same", 1.0 + v(a, "amp_same") * minf(5.0, float(a.sg.get("same", 0))) / 5.0)
	if v(a, "amp_still") > 0.0 and float(a.sg.get("still", 0.0)) >= 1.0: m *= _f(a, "amp_still", 1.0 + v(a, "amp_still"))
	if v(a, "amp_come") > 0.0 and d.vel.dot(a.pos - d.pos) > 0.0 and d.vel.length() > 10.0: m *= _f(a, "amp_come", 1.0 + v(a, "amp_come"))
	if v(a, "amp_drown") > 0.0 and (b.has_st(d, "flood") or b.has_st(d, "confuse")): m *= _f(a, "amp_drown", 1.0 + v(a, "amp_drown"))
	if v(a, "amp_allies") > 0.0: m *= _f(a, "amp_allies", 1.0 + v(a, "amp_allies") * float(_allies(a).size()) / 9.0)
	if v(a, "amp_early") > 0.0: m *= 1.0 + v(a, "amp_early") * clampf(1.0 - tm / 40.0, 0.0, 1.0); _stat("sig_amp_early"); _note(a, "amp_early", "개전 초반 계략이 매섭다")
	if v(a, "amp_late") > 0.0: m *= 1.0 + v(a, "amp_late") * clampf((tm - 20.0) / 30.0, 0.0, 1.0)
	if v(a, "amp_late") > 0.0: _stat("sig_amp_late")
	if v(a, "amp_last") > 0.0 and _allies(a).size() <= LAST_N: m *= 1.0 + v(a, "amp_last")
	if v(a, "amp_behind") > 0.0:
		var mine := 0.0
		var theirs := 0.0
		for o in b.units:
			if o.alive:
				if o.camp == a.camp: mine += o.troops
				else: theirs += o.troops
		if mine < theirs * 0.85: m *= 1.0 + v(a, "amp_behind")
		if mine < theirs * 0.85: _stat("sig_amp_behind")
	if v(a, "amp_far") > 0.0 and far: m *= _f(a, "amp_far", 1.0 + v(a, "amp_far") * clampf(b._gap(a, d) / 260.0, 0.0, 1.0))
	if v(a, "amp_kill") > 0.0: m *= 1.0 + v(a, "amp_kill") * minf(3.0, float(a.kills)) / 3.0
	if v(a, "amp_guard") > 0.0 and b._phalanx(d): m *= 1.0 + v(a, "amp_guard"); _stat("sig_amp_guard"); _note_s(a, "amp_guard", "방진의 틈을 꿰뚫었다")
	if v(a, "die_hard") > 0.0: m *= 1.0 + v(a, "die_hard") * clampf((DIE_HARD_FROM - a.troops / a.max) / DIE_HARD_FROM, 0.0, 1.0)      # 1.2 방덕 결사 —— 병력이 줄수록
	# 책사 · 술사 (1.2) 엔진 기본 키 —— 숫자만 바뀌므로 말풍선으로 보이게 한다
	if a.in_skill:
		if v(a, "sk_amp") > 0.0: _note_s(a, "sk_amp", "기술이 매섭다")
		if v(a, "rate") > 0.0: _note_s(a, "rate", "기술이 빨리 찬다")
	if v(a, "fire_amp") > 0.0 and b.has_st(d, "burn"): _note_s(a, "fire_amp", "불타는 적에게 더 매섭다")
	if v(a, "icleave") > 0.0 and b.is_caster(a.c): _note_s(a, "icleave", "옆 부대까지 덮쳤다")
	if v(a, "no_pin") > 0.0 and b._pinned(a):
		m /= maxf(0.1, b.engage_v("pin_atk", 1.0))
		if b.is_caster(a.c): _stat("sig_no_pin"); _note_s(a, "no_pin", "붙어도 계략을 거두지 않는다")
		else: _f(a, "no_pin", 0.0)      # 궁병 (태사자 · 엄안) —— 말풍선은 BOW_TEXT
	return m


## 맞는 쪽 배율. 큰 한 방 피하기(우번)는 여기서 굴린다
func taken(d, a, mult: float) -> float:
	if d.m.is_empty() and not has("ult_dr") and not has("dr_link") and not has("dr_early_all") and not has("body_guard") and not d.sg.has("sp_dr"):
		return 1.0
	var m := _special_taken(d, a)
	if d.sg.has("hide") and b._tm < float(d.sg["hide"]):      # 위장 중인데 맞았다 (범위 피해 말고는 없어야 한다)
		_stat("sig_hide_hit")
	if v(d, "dr_still") > 0.0 and float(d.sg.get("still", 0.0)) >= 1.0: m *= _f(d, "dr_still", 1.0 - minf(0.6, v(d, "dr_still")))
	if v(d, "dr_low") > 0.0: m *= 1.0 - minf(0.6, v(d, "dr_low")) * clampf(1.0 - d.troops / d.max, 0.0, 1.0)
	if v(d, "dr_early") > 0.0 and b._tm < 20.0: m *= 1.0 - minf(0.6, v(d, "dr_early")); _stat("sig_dr_early")
	if v(d, "dr_guard") > 0.0 and b._phalanx(d): m *= 1.0 - minf(GUARD_DR_MAX, v(d, "dr_guard"))      # 11/21 조인 —— 방진을 친 동안
	m *= _spear_taken(d)      # 1.2 창병 고수 · 방진 연결 · 버팀목
	if has("ult_dr") and b._in_ult:
		var best := 0.0
		var bu = null
		for o in who["ult_dr"]:
			if o.alive and o.camp == d.camp and v(o, "ult_dr") >= best:
				best = v(o, "ult_dr")
				bu = o
		m *= 1.0 - minf(0.6, best)
		_stat("sig_ult_dr")
		if bu != null:
			_note(bu, "ult_dr", "적 고유기가 닥치기 전에 아군을 물렸다")
	if has("dr_early_all") and b._tm < EARLY_T:      # 이의 —— 개전 직후 아군 전원 (이의가 살아 있는 동안)
		var be := 0.0
		var bo = null
		for o in who["dr_early_all"]:
			if o.alive and o.camp == d.camp and v(o, "dr_early_all") >= be:
				be = v(o, "dr_early_all")
				bo = o
		if bo != null:
			m *= 1.0 - minf(0.5, be)
			_stat("sig_dr_early_all")
			_note(bo, "dr_early_all", "개전 직후 아군이 덜 다친다")
	if v(d, "dodge_big") > 0.0 and (b._in_ult or mult >= 1.5) and b.rng.randf() < minf(0.6, v(d, "dodge_big")):
		_stat("sig_dodge_big")
		_say(d, "점술 —— 큰 한 방을 피했다")
		m *= 0.05
	if v(d, "frail_water") > 0.0 and b.has_st(d, "flood"): m *= 1.0 + v(d, "frail_water")
	if v(d, "frail_water") > 0.0 and b.has_st(d, "flood"): _note_m(d, "frail_water")
	return m


## 때린 뒤 (때린 쪽 키) —— loss 는 이번 타격이 깎은 병력
func after_hit(a, d, loss: float, far: bool) -> void:
	if a.m.is_empty() or a.countering or a.sg.get("piercing", false):
		return
	if not a.sg.has("pn"):      # 인물 이름 (카드 이름 '목우 황월영' 의 끝말)
		a.sg["pn"] = str(a.c.name).split(" ")[-1]
	if STAT_SAY.has(a.sg["pn"]):
		_f(a, "p_" + str(a.sg["pn"]), 0.0)      # 수치만 바뀌는 개성(연노 · 광폭 · 화선 …) —— 치는 동안 말풍선
	a.sg["hits"] = int(a.sg.get("hits", 0)) + 1
	a.sg["same"] = int(a.sg.get("same", 0)) + 1 if a.sg.get("last") == d else 0
	a.sg["last"] = d
	_spear_hit(a, d, loss, far)      # 1.2 창병 —— 발동 기록 · 말풍선
	_special_hit(a, d)      # 11/22 장료 돌파 · 조운 구출 —— 정한 적에게 닿은 순간
	cav_hit(a, d, loss, far)      # 1.2 기병 —— 계수 · 말풍선
	if not d.alive:
		return
	if v(a, "shove") > 0.0 and (not far or b._ranged(a)) and not b._in_ult:
		var dir: Vector2 = d.pos - a.pos
		if dir.length() > 0.1:
			d.pos += dir.normalized() * minf(30.0, v(a, "shove"))
			_note_m(a, "shove")
			b._clamp_arena(d)
			_note(a, "shove", "함진 돌파 —— 적을 밀며 파고든다")
	if v(a, "bind") > 0.0 and b.rng.randf() < v(a, "bind"):
		b.inflict(a, d, "flood", 0.0, 1)
		cav_bind(a, d)
	if v(a, "slow_on") > 0.0 and b.rng.randf() < 0.35:
		d.sga["spd"] = minf(float(d.sga.get("spd", 0.0)), -minf(0.5, v(a, "slow_on")))
		_stat("sig_slow_on")
		_note(a, "slow_on", "맞힌 적의 발이 늦어졌다")
	if v(a, "morale_on") > 0.0:
		d.morale -= v(a, "morale_on")
		_stat("sig_morale_on")
		_note_s(a, "morale_on", "적의 사기를 꺾었다", false)
		a.mdmg += v(a, "morale_on")
	if v(a, "gauge_on") > 0.0:
		if d.ult != null:
			d.gauge = maxf(0.0, d.gauge - v(a, "gauge_on"))
			_f(a, "gauge_on", 0.0)
		elif d.atb > 0.3 and b._tm >= float(d.sg.get("gd", 0.0)):      # 고유기가 없는 적은 다음 공격 준비를 늦춘다 (예전엔 아무 일도 없었다) —— 같은 적에게는 GAUGE_CD 초에 한 번
			d.sg["gd"] = b._tm + GAUGE_CD
			d.atb = maxf(0.0, d.atb - minf(0.5, v(a, "gauge_on") * GAUGE_ATB))
			_f(a, "gauge_on", 0.0)
	if v(a, "bleed_on") > 0.0 and b.rng.randf() < v(a, "bleed_on"):
		b.inflict(a, d, "bleed", 0.05, 2)
		if b.is_caster(a.c): _stat("sig_bleed_on"); _note_s(a, "bleed_on", "독이 번져 피를 흘린다", false)
		else: _f(a, "bleed_on", 0.0)      # 궁병 (하제 독화살) —— 말풍선은 BOW_TEXT
	if v(a, "amp_guard") > 0.0 and b._phalanx(d) and _due(a, "gbreak", PHALANX_BREAK_CD):      # 서서 간파 —— 방진을 깨뜨린다 (피해 증가에 더해)
		d.buffs = d.buffs.filter(func(x): return x.stat != "phalanx")
		_stat("sig_phalanx_break")
		b.L("sk", "%s의 %s —— %s의 방진을 깨뜨렸다" % [b.nm(a), _gname(a), b.nm(d)], {"fx": "debuff", "f": d.key, "a": a.key, "sig": true})
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
		_f(a, "hit_run", 0.0)


## 맞은 뒤 (맞은 쪽 키)
func after_taken(d, a, loss: float, far: bool) -> void:
	if d.sg.has("bg"):      # 11/22 전위 호위 —— 아군이 덜 받은 몫을 전위가 대신 받는다
		_guard_take(d, loss)
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
		_stat_u(d, "enrage")
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
	if v(k, "kill_gauge") > 0.0:
		if k.ult != null:
			k.gauge = minf(100.0, k.gauge + v(k, "kill_gauge"))
			_f(k, "kill_gauge", 0.0)
		else:      # 고유기가 없는 장수(3~4급 약탈)는 기 대신 쓰러뜨린 부대의 병력을 거둔다 (예전엔 아무 일도 없었다)
			_loot(k, victim)
	if v(k, "absorb") > 0.0:
		var g := minf(k.max - k.troops, victim.max * v(k, "absorb"))
		if g > 0.0:
			k.troops += g
			_stat("sig_absorb")
			k.htr += g
			b.L("hl", "%s의 변절 유도 —— 흩어진 적병을 거두었다" % b.nm(k), {"fx": "heal", "f": k.key, "n": g, "healer": k.key, "sig": true})


## 패주를 버티나 (true 면 이번 패주를 취소)
func hold_rout(u, cause: String) -> bool:
	if has("revive") and not (cause in ["annihilated", "boss"]) and u.troops > 0.0 and _revive(u):
		return true
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
	var by = null
	for o in who["ally_calm"]:
		if o.alive and o.camp == u.camp and o.pos.distance_to(u.pos) < R_AURA and v(o, "ally_calm") > best:
			best = v(o, "ally_calm")
			by = o
	if by != null:
		_note(by, "ally_calm", "군율 —— 흔들리는 아군을 다잡는다")      # 패주 판정이 걸린 부대에만 불린다
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
	if v(u, "feign_fire") > 0.0 and not u.sg.get("fg_done", false):      # 11/22 황개 거짓 항복 —— 숨은 동안 적진으로 걸어 들어간다
		var to: Vector2 = t.pos - u.pos
		return to.normalized() * sp if b._gap(u, t) > FEIGN_GAP and to.length() > 0.1 else Vector2.ZERO
	if has("escort") and v(u, "escort") > 0.0:
		var esc: Vector2 = _escort_steer(u, t, pin, desired, sp)
		if esc != desired:
			return esc
	if v(u, "kite") > 0.0 and pin != null and b._ranged(u):
		var away2: Vector2 = u.pos - pin.pos
		if away2.length() > 0.1:
			if not u.sg.get("kt", false):      # 후퇴 사격 —— 물러나기 시작할 때마다 한 번 센다 (틱마다 세지 않는다)
				u.sg["kt"] = true
				_f(u, "kite", 0.0)
			_stat("sig_kite_ticks")
			return away2.normalized() * sp * minf(1.0, 0.6 + v(u, "kite"))
	u.sg["kt"] = false
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
				_stat_u(u, "throw")
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
				_stat("sig_blink")
				_say(u, "선술 —— 홀연히 자리를 옮겼다")
		# 간웅 —— 고유기를 맞으면 되받아친다
		if u.sg.has("ret") and not b._in_ult:
			var ra = u.sg["ret"]
			u.sg.erase("ret")
			if ra != null and ra.alive:
				_say(u, "간웅 —— 되받아쳤다")
				_stat("sig_ult_ret")
				b.phys_hit(u, ra, minf(2.5, v(u, "ult_ret")), true)
	for u in who.get("burn_out", []):      # 1.2 주연 화계 차단
		if u.alive and _due(u, "burn_out", BURN_OUT_T):
			_burn_out(u)
	for u in who.get("taunt", []):      # 11/21 도발 —— 키 하나(taunt)로 누구에게나 붙는 일반 장치
		if u.alive and _due(u, "taunt", TAUNT_PULSE):
			_taunt(u)
	_scholar_tick()
	_special_tick()      # 11/22 특별한 특기
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
		_scholar_aura(u, al, fo)
		if v(u, "roar") > 0.0:
			var hit := _near(u, fo)
			for o in hit:
				o.morale -= v(u, "roar")
				u.mdmg += v(u, "roar")
				o.sga["spd"] = float(o.sga.get("spd", 0.0)) - 0.2
			if not hit.is_empty():
				_note(u, "roar", "일갈 —— 주변 적이 움츠러든다", ROAR_SAY, false)
				_stat("sig_roar", hit.size())
		if v(u, "cheer_aura") > 0.0:
			for o in _near(u, al):
				var g := minf(200.0 - o.morale, v(u, "cheer_aura"))
				if g > 0.0:
					o.morale += g
					u.hmo += g
					_note_m(u, "cheer_aura")
		if v(u, "cleanse_aura") > 0.0:
			for o in _near(u, al, R_AURA * 1.5):
				if not o.st.is_empty() and b.rng.randf() < v(u, "cleanse_aura"):
					b.cleanse(o)
					_stat("sig_cleanse_aura")
					_note(u, "cleanse_aura", "아군의 상태이상을 풀어 주었다")
					break
		if v(u, "spd_aura") > 0.0:
			for o in _near(u, al):
				o.sga["spd"] = float(o.sga.get("spd", 0.0)) + v(u, "spd_aura")
			_f(u, "spd_aura", 0.0)
		if v(u, "def_aura") > 0.0:
			for o in _near(u, al):
				o.sga["def"] = float(o.sga.get("def", 0.0)) + v(u, "def_aura")
				_note_m(u, "def_aura")
		if v(u, "atk_down") > 0.0:
			for o in _near(u, fo):
				o.sga["atk"] = float(o.sga.get("atk", 0.0)) - v(u, "atk_down")
				_note_m(u, "atk_down")
		if v(u, "quake") > 0.0:
			for o in _near(u, fo):
				o.sga["spd"] = float(o.sga.get("spd", 0.0)) - v(u, "quake")
				_stat("sig_quake")
				_note_s(u, "quake", "주변 적의 발이 묶인다", false)
		if v(u, "cav_aura") > 0.0:
			for o in al:
				if o.c.tag == "기병":
					o.sga["atk"] = float(o.sga.get("atk", 0.0)) + v(u, "cav_aura")
		if v(u, "caster_aura") > 0.0:
			for o in al:
				if b.is_caster(o.c):
					o.sga["atk"] = float(o.sga.get("atk", 0.0)) + v(u, "caster_aura")
					_stat("sig_caster_aura")
					_note(u, "caster_aura", "아군 술사들이 힘을 얻었다")
		if v(u, "tier_aura") > 0.0:
			var top := 0
			for o in al:
				top = maxi(top, int(o.c.tier))
			for o in al:
				if int(o.c.tier) >= top:
					o.sga["atk"] = float(o.sga.get("atk", 0.0)) + v(u, "tier_aura")
					_note_m(u, "tier_aura")
		if v(u, "boost_best") > 0.0:
			var best = null
			for o in al:
				if o != u and (best == null or float(o.c.atk) > float(best.c.atk)):
					best = o
			if best != null:
				best.sga["atk"] = float(best.sga.get("atk", 0.0)) + v(u, "boost_best")
				_note_m(u, "boost_best")
		if v(u, "gauge_aura") > 0.0:
			for o in al:
				if o.ult != null and o.charges > 0:
					o.gauge = minf(100.0, o.gauge + v(u, "gauge_aura"))
					_note_m(u, "gauge_aura")
		if v(u, "morale_floor") > 0.0:
			for o in _near(u, al):
				if o.morale < v(u, "morale_floor"):
					_stat("sig_morale_floor")
					_note(u, "morale_floor", "무너지려는 아군의 사기를 붙들었다")
				o.morale = maxf(o.morale, v(u, "morale_floor"))
		if v(u, "confuse_aura") > 0.0:
			var lost := 0
			for o in _near(u, fo, BAGUA_R):      # 1.2 팔진 반지름을 넓혔다 (200 → BAGUA_R) —— 뒤에 선 책사 둘레에 적이 거의 들지 않아 열 판에 한 번도 안 걸렸다
				var sk: String = str(u.key) + ">" + str(o.key)
				if not _seen.has(sk):
					_seen[sk] = true
					b.inflict(u, o, "confuse", 1.0, 1)
					if b.has_st(o, "confuse"):
						_stat("sig_confuse_aura")
						lost += 1
			if lost > 0:
				_say(u, "%s —— 팔진에 든 적 %d부대가 홀렸다" % [_gname(u), lost], false)
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
			_stat("sig_rain")
			_say(u, "청우 —— 비가 내린다")
		_sage_auras(u, al, fo)      # 1.2 책사 · 술사 —— 연영 · 사항계 · 황천 · 오소 정보


# ── 창병 (1.2) ──
## 1.2 「전장의 개성」 창병 18명 —— 발동 횟수(b.stats["sig_*"])를 남기고, 보이게(말풍선 · 표적 · 움직임) 한다. 수치는 상식선 기본값.
const SPEAR_SAY := 6.0       # 창병 개성 말풍선 간격 (초) —— 부대 · 개성마다
const ROAR_SAY := 8.0        # 일갈 말풍선 간격 (초)
const ESCORT_R := 190.0      # 호위 —— 아군 장수에게서 이 안이면 곁에 있는 것
const ESCORT_PULL := 0.9     # 호위 —— 곁으로 돌아가는 속도 (제 속도의 몫)
const ESCORT_NEAR := 260.0   # 호위 —— 이 안의 아군 장수만 지킨다
const BURN_OUT_T := 2.0      # 화계 차단 —— 불을 끄는 간격 (초)
const BURN_OUT_LEFT := 1     # 화계 차단 —— 주변 아군 화상이 남는 길이 (이 이하로 줄인다)
const LAST_N := 5           # 버팀목 —— 아군이 이 수 이하(아홉 중 절반)로 남으면
const REAR_R := 120.0        # 후위 수비 —— 아군 원거리와 이 틈 안까지 다가온 적을 먼저 친다
const TWIN_R := 110.0        # 삼첨도 —— 둘째 적과의 틈이 이 안이면 함께 찌른다 (긴 삼첨도가 곁의 적까지)
const DIE_HARD_FROM := 0.8   # 결사 —— 병력이 이 비율 아래로 줄면 공격이 오르기 시작
static var say_on := true    # 점검용 —— false 면 말풍선 없이 횟수만 (전 · 후 비교)


## 횟수만 —— 판 전체(sig_<key>)와 그 부대 몫(su_<부대>_<key>, 점검이 읽는다)
func _stat_u(u, key: String) -> void:
	_stat("sig_" + key)
	_stat("su_%s_%s" % [u.key, key])


## 발동 한 번 —— 횟수(sig_<key>)를 올리고, 말풍선은 every 초에 한 번
func _note(u, key: String, text: String, every := SPEAR_SAY, up := true) -> void:
	_stat_u(u, key)
	if not say_on:
		return
	var sk := "say_" + key
	if b._tm >= float(u.sg.get(sk, 0.0)):
		u.sg[sk] = b._tm + every
		_say(u, text, up)


## 가장 가까운 아군 장수(고유기를 가진 부대) —— 호위 대상. 1초마다 다시 고른다
func _escort_of(u):
	var g = u.sg.get("esc_g")
	if g != null and g.alive and b._tm < float(u.sg.get("esc_t", 0.0)):
		return g
	var best = null
	var bd := ESCORT_NEAR
	for o in b.units:
		if o.alive and o.camp == u.camp and o != u and o.ult != null:
			var d: float = o.pos.distance_to(u.pos)
			if d < bd:
				bd = d
				best = o
	u.sg["esc_g"] = best
	u.sg["esc_t"] = b._tm + 1.0
	return best


## 표적 무게 —— 호위(아군 장수의 표적 · 아군 장수를 치는 적) · 후위 수비(아군 원거리에 붙은 적)
func _spear_w(u, o) -> float:
	var w := 1.0
	if has("escort") and v(u, "escort") > 0.0:
		var g = _escort_of(u)
		if g != null:
			if g.tgt == o:
				w *= 1.0 - minf(0.8, v(u, "escort"))
			elif o.tgt == g:
				w *= 1.0 - minf(0.8, v(u, "escort")) * 0.6
	if has("seek_rear") and v(u, "seek_rear") > 0.0:
		if _rear_threat(u, o):
			w *= 1.0 - minf(0.8, v(u, "seek_rear"))
	return w


## 후위 수비 —— o 가 u 의 아군 원거리 부대를 노리거나 그 곁(REAR_R)까지 다가왔나
func _rear_threat(u, o) -> bool:
	var ot = o.tgt
	if ot != null and ot.alive and ot.camp == u.camp and b._ranged(ot):
		return true
	for r in b.units:
		if r.alive and r.camp == u.camp and r != u and b._ranged(r) and b._gap(o, r) <= REAR_R:
			return true
	return false


## 호위 이동 —— 아군 장수에게서 멀어졌고 아직 손 닿는 적이 없으면 곁으로 돌아간다
func _escort_steer(u, t, pin, desired: Vector2, sp: float) -> Vector2:
	if pin != null:
		u.sg.erase("esc_on")
		return desired
	var g = _escort_of(u)
	if g == null or u.pos.distance_to(g.pos) <= ESCORT_R or b._gap(u, t) <= RtBattle.TOUCH + 8.0:
		u.sg.erase("esc_on")
		return desired
	var to: Vector2 = g.pos - u.pos
	if not u.sg.has("esc_on"):
		u.sg["esc_on"] = true
		_note(u, "escort_back", "호위 —— 아군 장수 곁으로 돌아간다")
	return to.normalized() * sp * ESCORT_PULL


## 때린 뒤 기록 —— 어느 개성이 이번 타격에서 일했나 (loss = 이번 타격이 깎은 병력)
func _spear_hit(a, d, loss: float, far: bool) -> void:
	if v(a, "amp_guard") > 0.0 and b._phalanx(d):
		_note(a, "amp_guard", "함진영 —— 방진을 짓밟는다")
	var was_low: bool = d.troops + loss < d.max * LOW
	if was_low and (v(a, "amp_low") > 0.0 or v(a, "seek_low") > 0.0):
		_note(a, "amp_low", "처형 —— 꺾인 적을 베어 넘긴다")
	if int(a.sg.get("same", 0)) >= 1 and v(a, "amp_same") > 0.0:
		_note(a, "amp_same", "맞붙기 —— 한 적에게 매달려 갈수록 거세진다")
	if v(a, "amp_open") > 0.0 and int(a.sg.get("hits", 0)) <= 3:
		_note(a, "amp_open", "선봉 패기 —— 첫 접전부터 거세게 친다", 12.0)
	if v(a, "amp_strong") > 0.0 and (d.c.tier > a.c.tier or float(d.c.atk) > float(a.c.atk)):
		_note(a, "amp_strong", "강적 노림 —— 센 적에게 이를 간다")
	if v(a, "amp_last") > 0.0 and _allies(a).size() <= LAST_N:
		_note(a, "amp_last", "버팀목 —— 마지막까지 버틴다")
	if v(a, "die_hard") > 0.0 and a.troops < a.max * DIE_HARD_FROM:
		_note(a, "die_hard", "결사 —— 물러서지 않고 맞선다" if a.troops < a.max * 0.5 else "결사 —— 이를 악문다")
	if v(a, "seek_guard") > 0.0 and d.tgt != null and d.tgt.camp == a.camp and d.tgt != a:      # 옛 표적 장치 (점검 전후 비교용)
		_stat_u(a, "seek_guard")
	if v(a, "seek_rear") > 0.0 and _rear_threat(a, d):
		_note(a, "seek_rear", "후위 수비 —— 아군 후열에 붙은 적을 쳤다")
	if v(a, "escort") > 0.0:
		var g = _escort_of(a)
		if g != null and (g.tgt == d or d.tgt == g):
			_note(a, "escort", "호위 —— 아군 장수를 지킨다")
	if v(a, "twin") > 0.0 and not far and not b._in_ult:
		var other = null
		var bg := TWIN_R
		for o in b.units:
			if o.alive and o.camp == d.camp and o != d and not b._ranged(o):
				var gp: float = b._gap(a, o)
				if gp <= bg:
					bg = gp
					other = o
		if other != null:
			a.sg["piercing"] = true      # after_hit 되돌림 방지 (관통과 같은 장치)
			b.phys_hit(a, other, v(a, "twin"), true)
			a.sg["piercing"] = false
			_note(a, "twin", "삼첨도 —— 두 적을 한꺼번에 찔렀다")


## 받는 쪽 배율 —— 고수(제자리) · 방진 연결(옆 창병과 붙으면 고람도 옆 창병도) · 버팀목(아군 셋 이하)
func _spear_taken(d) -> float:
	var m := 1.0
	if v(d, "dr_still") > 0.0 and float(d.sg.get("still", 0.0)) >= 1.0:
		_note(d, "dr_still", "고수 —— 제자리에서 버틴다")
	if v(d, "dr_last") > 0.0 and _allies(d).size() <= LAST_N:
		m *= 1.0 - minf(0.6, v(d, "dr_last"))
		_note(d, "dr_last", "버팀목 —— 마지막까지 버틴다")
	if has("dr_link") and d.c.tag == "창병":
		for o in b.units:
			if o != d and o.alive and o.camp == d.camp and o.c.tag == "창병" and o.pos.distance_to(d.pos) < d.hw + o.hw + 40.0 \
					and (v(d, "dr_link") > 0.0 or v(o, "dr_link") > 0.0):
				var src = d if v(d, "dr_link") > 0.0 else o
				m *= 1.0 - minf(0.5, v(src, "dr_link"))
				_note(src, "dr_link", "방진 연결 —— 옆 창병과 어깨를 맞댔다")
				break
	return m


## 화계 차단 —— 자신 · 주변 아군의 화상을 곧 꺼지게 한다
func _burn_out(u) -> void:
	var n := 0
	for o in _allies(u):
		if o.pos.distance_to(u.pos) > R_AURA:
			continue
		for s in o.st:
			if s.k == "burn" and int(s.dur) > BURN_OUT_LEFT:
				s.dur = BURN_OUT_LEFT
				n += 1
	if n > 0:
		_note(u, "burn_out", "화계 차단 —— 번진 불을 눌러 껐다")
		_stat("sig_burn_out_n", n)


# ── 책사 · 술사 (1.2) ──
## 담당 31명: 책사 17 (주유 · 육손 · 방통 · 제갈량 · 곽가 · 서서 · 강유 · 종회 · 마량 · 순유 · 저수 · 제갈각 · 황권 · 감택 · 유엽 · 이적 · 허유)
## 술사 14 (장각 · 좌자 · 우길 · 관로 · 장로 · 화타 · 남화노선 · 길평 · 우번 · 이의 · 오범 · 장보 · 주건평 · 초주).
## 책략 병종은 화공 · 수공 · 혼란 · 결계 · 치료 · 사기 장치가 이미 많다 —— 겹치는 사람은 표적 · 범위 · 타이밍으로 갈래를 나눈다.
## 점검: tests/sig_probe_sage.tscn (발동 횟수만 센다)
const NOTE_KEYS := ["rate", "sk_amp", "fire_amp", "icleave", "starve"]      # 엔진(Battle)이 이미 처리하는 키 —— 말풍선만 sig_rt 가 붙인다 (등급 배율 flags 에는 넣지 않는다)
const SAGE_TAGS := ["책사", "술사"]
const SAGE_SAY := 10.0       # 말풍선 간격 (초) —— 사람 · 키마다 (숫자만 바뀌는 개성을 보이게)
const EARLY_T := 20.0         # 이의 예언이 막아 주는 개전 직후 시간 (초)
const BAGUA_R := 320.0        # 제갈량 팔진 반지름
const PHALANX_BREAK_CD := 8.0 # 서서 간파 —— 방진을 깨뜨리는 간격 (초)
const CHAIN_R := 220.0        # 육손 연영 —— 불길이 건너가는 거리
const CHAIN_N := 2            # 육손 연영 —— 한 번에 건너가는 부대 수
const GAUGE_CUT_T := 10.0     # 감택 사항계 —— 간격 (초)
const CULT_MAX := 4           # 장각 황천 —— 사기로 치는 걸린 적 부대 수 상한
const REVIVE_MORALE := 45.0   # 화타 청낭 —— 일으킨 부대의 사기 하한
const REVIVE_R := 520.0       # 화타 청낭 —— 일으킬 수 있는 거리


## 개성 이름 —— passives.json sig 의 이름, 없으면 그 인물의 고유(금색) 특기 이름 (말풍선 머리)
func _gname(u) -> String:
	var gn = u.sg.get("gn")
	if gn != null:
		return gn
	var p: String = DB.person_of_name(str(u.c.name))
	var e = DB.PSV.get("sig", {}).get(p)
	var out := ""
	if e != null and str(e[0]) != "":
		out = str(e[0])
	else:
		for x in DB.PSV.ladder.get(p, []):
			if DB.PSV.traits.get(x[0], {}).get("unique", false):
				out = str(x[0])
	if out == "":
		out = "책략"
	u.sg["gn"] = out
	return out


## 말풍선 —— u 의 key 개성이 작동할 때 SAGE_SAY 초에 한 번 ("이름 —— 글")
func _note_s(u, key: String, text: String, up := true) -> void:
	if not (u.c.tag in SAGE_TAGS):      # 같은 키를 쓰는 다른 병종 장수(창병 · 모사 · 유생 …)의 말풍선은 그 담당자가 붙인다
		return
	var t := "n_" + key
	if b._tm < float(u.sg.get(t, 0.0)):
		return
	u.sg[t] = b._tm + SAGE_SAY
	_say(u, "%s —— %s" % [_gname(u), text], up)


## 화타 청낭 —— 무너지는 부대를 한 번 일으킨다 (화타마다 한 번, 병력 일부 회복 + 사기 하한). 일으켰으면 true
func _revive(u) -> bool:
	for h in who["revive"]:
		if not h.alive or h.camp != u.camp or h.sg.get("rv_used", false) or h.pos.distance_to(u.pos) > REVIVE_R:
			continue
		h.sg["rv_used"] = true
		var g := minf(u.max - u.troops, u.max * v(h, "revive"))
		if g > 0.0:
			u.troops += g
			h.htr += g
		u.morale = maxf(u.morale, REVIVE_MORALE)
		_stat("sig_revive")
		b.L("hl", "%s의 %s —— 무너지던 %s을 다시 일으켰다" % [b.nm(h), _gname(h), b.nm(u)], {"fx": "heal", "f": u.key, "n": g, "healer": h.key, "sig": true})
		return true
	return false


## 주기마다 (_auras 가 부른다) —— 연영 · 사항계 · 황천 · 오소 정보
func _sage_auras(u, al: Array, fo: Array) -> void:
	if fo.is_empty():
		return
	if v(u, "fire_chain") > 0.0:      # 육손 연영 —— 내 불에 타는 적에서 가장 가까운 안 타는 적으로 건너간다 (주유 확산은 옆 부대 확률, 이쪽은 진영 따라 줄줄이)
		var burning := []
		for o in fo:
			var s = b._st_of(o, "burn")
			if s != null and (str(s.get("by", "")) == str(u.key) or str(s.get("spread_by", "")) == str(u.key)):
				burning.append([o, s])
		var hopped := 0
		for _i in CHAIN_N:
			var src = null
			var ss = null
			var dst = null
			var bd := CHAIN_R
			for pair in burning:
				for t in fo:
					if t.alive and not b.has_st(t, "burn"):
						var dd: float = pair[0].pos.distance_to(t.pos)
						if dd < bd:
							bd = dd
							src = pair[0]
							ss = pair[1]
							dst = t
			if dst == null:
				break
			b._spread_burn_to(src, ss, dst, str(u.key))
			burning.append([dst, b._st_of(dst, "burn")])
			hopped += 1
		if hopped > 0:
			_stat("sig_fire_chain", hopped)
			_note_s(u, "fire_chain", "불길이 진영을 따라 줄줄이 번진다", false)
	if v(u, "gauge_cut") > 0.0 and _due(u, "gcut", GAUGE_CUT_T):      # 감택 사항계 —— 고유기 기가 가장 찬 적 장수 하나의 기를 뺀다 (맞힌 적마다 빼는 관로 천기와 다르게 주기 · 표적)
		var tg = null
		for o in fo:
			if o.ult != null and o.charges > 0 and o.gauge > 0.0 and (tg == null or o.gauge > tg.gauge):
				tg = o
		if tg != null:
			tg.gauge = maxf(0.0, tg.gauge - v(u, "gauge_cut"))
			_stat("sig_gauge_cut")
			b.L("sk", "%s의 %s —— %s의 고유기 기가 흩어졌다" % [b.nm(u), _gname(u), b.nm(tg)], {"fx": "debuff", "f": tg.key, "a": u.key, "sig": true})
	if v(u, "cult") > 0.0:      # 장각 황천 —— 상태이상에 걸린 적이 많을수록 주변 아군 사기가 오른다 (고정 사기 회복 mregen 과 다르게 걸린 적 수에 따른다)
		var n := 0
		for o in fo:
			if not o.st.is_empty():
				n += 1
		n = mini(n, CULT_MAX)
		if n > 0:
			var up := 0
			for o in _near(u, al, R_AURA * 1.5):
				var g := minf(200.0 - o.morale, v(u, "cult") * n)
				if g > 0.0:
					o.morale += g
					u.hmo += g
					up += 1
			if up > 0:
				_stat("sig_cult", up)
				_note_s(u, "cult", "걸려든 적 %d부대 —— 아군의 기세가 오른다" % n)
	if v(u, "starve") > 0.0:      # 허유 오소 정보 —— 효과는 엔진(Battle.heal_troop)이 적 회복에 곱한다. 말풍선만
		_note_s(u, "starve", "적의 군량을 끊어 회복이 줄었다", false)


# ── 궁병 · 도적 (1.2) ──
## 표적 고르기 · 후퇴 사격 · 침투 · 치고 빠지기 · 매복이 실제로 일어났는지 세고 (b.stats "sig_<키>"), 일어날 때 말풍선 한 줄을 띄운다 (키마다 간격 BOW_SAY 초).
## 점검은 tests/sig_probe_bow.tscn. 수치는 상식선 기본값 —— 밸런스는 따로 재지 않는다.
const BOW_SAY := 6.0        # 같은 키 말풍선 최소 간격 (초) —— 키별 간격은 BOW_TEXT 의 둘째 칸
const STEALTH_MAX := 12.0   # 위장(stealth)이 한 판에서 숨는 최대 시간 —— 표적 후보 거르기를 켜 두는 한계 (RtBattle._foes_of)
## 키 -> [말풍선, 간격(초)]. "키@병종" 이 있으면 그 병종은 그 글을 쓴다 (같은 키라도 궁병은 엄호 · 도적은 호위)
const BOW_TEXT := {
	"seek_gen": ["저격 —— 고유기 장수 부대를 겨눈다", 6.0],
	"seek_guard": ["엄호 —— 아군에게 붙은 적을 겨눈다", 6.0],
	"seek_guard@도적": ["호위 —— 아군에게 붙은 적을 벤다", 6.0],
	"seek_cav": ["기병 저격 —— 적 기병을 겨눈다", 6.0],
	"seek_back": ["우회 —— 후열을 노린다", 8.0],
	"seek_low": ["저격 —— 약한 부대를 먼저", 6.0],
	"amp_far": ["원사 —— 먼 적을 꿰뚫었다", 8.0],
	"amp_still": ["농성 사격 —— 자리를 지켜 쏜다", 8.0],
	"amp_come": ["길목 사격 —— 달려드는 적을 맞혔다", 6.0],
	"amp_open": ["매복 사격 —— 첫 사격이 매섭다", 99.0],
	"amp_open@도적": ["선등 —— 첫 칼이 매섭다", 99.0],
	"amp_cav": ["기병 저격 —— 기병에 깊이 박혔다", 6.0],
	"amp_same": ["연격 —— 같은 적을 몰아친다", 6.0],
	"amp_allies": ["무리 —— 아군이 많아 거세다", 12.0],
	"amp_drown": ["수적 —— 물에 잠긴 적을 벤다", 6.0],
	"dr_still": ["방벽 —— 자리를 지켜 피해를 줄인다", 8.0],
	"no_pin": ["붙어도 흐트러지지 않고 쏜다", 8.0],
	"bleed_on": ["독화살 —— 적이 피를 흘린다", 6.0],
	"slow_on": ["제압 사격 —— 적의 발이 묶인다", 6.0],
	"morale_on": ["약탈 공포 —— 적의 사기가 꺾인다", 6.0],
	"gauge_on": ["교란 —— 적 고유기의 기를 뺐다", 6.0],
	"kill_gauge": ["약탈 —— 쓰러뜨리고 기를 얻었다", 8.0],
	"kite": ["후퇴 사격 —— 물러나며 쏜다", 5.0],
	"hit_run": ["치고 빠지기 —— 한 칼 치고 물러난다", 4.0],
	"spd_aura": ["충복 —— 주변 아군이 빨라진다", 12.0],
	"p_정보": ["화선 —— 화살에 불을 붙인다", 10.0],
	"p_황개": ["고육 —— 불화살이 더 거세다", 10.0],
	"p_황월영": ["연노 —— 빠르게 연사한다", 10.0],
	"p_황조": ["일제사 —— 옆 적까지 맞혔다", 8.0],
	"p_손상향": ["칼춤 —— 옆 적까지 벤다", 8.0],
	"p_정봉": ["설중 돌격 —— 눈보라를 가르며 달려든다", 10.0],
	"p_관해": ["광폭 —— 방어를 버리고 덤벼든다", 10.0],
	"stealth": ["위장 —— 몸을 숨겼다", 99.0],
	"ambush": ["매복 —— 적 옆에서 나타난다", 99.0],
}


## 키 k 가 이 판에서 한 번 일어났다 —— 횟수를 세고 말풍선을 (간격마다) 띄운다. 돌려주는 값은 mul 그대로 (곱셈 자리에 끼워 쓴다).
## mul 이 1.0 이면 효과가 없던 판정이라 세지 않는다 (0.0 은 '곱이 아닌 사건' 이라 늘 센다)
func _f(u, k: String, mul: float) -> float:
	if mul == 1.0:
		return mul
	_stat("sig_" + k)
	_stat("u%s:%s" % [u.key, k])      # 장수별 횟수 (점검이 제 부대 것만 읽는다)
	var tx = BOW_TEXT.get(k + "@" + str(u.c.tag), BOW_TEXT.get(k))
	if tx != null:
		var tm: float = b._tm
		var key := "bx_" + k
		if not u.sg.has(key) or tm >= float(u.sg[key]):
			u.sg[key] = tm + float(tx[1])
			_say(u, str(tx[0]))
	return mul


## 표적이 평소(가장 가까운 적) 대신 개성 때문에 바뀌었다 —— 고른 적 o 가 어느 개성 키에 걸렸는지 세고 말풍선
func note_pick(u, o) -> void:
	if u.m.is_empty() or o == null or u.sg.get("pk") == o:      # 같은 적을 계속 겨누는 동안은 한 번만
		return
	u.sg["pk"] = o
	for k in ["seek_gen", "seek_guard", "seek_cav", "seek_back", "seek_low", "seek_strong"]:
		if v(u, k) > 0.0 and _seek_ok(u, o, k):
			_f(u, k, 0.0)


func _seek_ok(u, o, k: String) -> bool:
	match k:
		"seek_gen": return o.ult != null
		"seek_cav": return o.c.tag == "기병"
		"seek_back": return b._ranged(o)
		"seek_low": return o.troops < o.max * LOW
		"seek_strong": return o.c.tier > u.c.tier or float(o.c.atk) > float(u.c.atk)
		"seek_guard": return o.tgt != null and o.tgt.alive and o.tgt.camp == u.camp and o.tgt != u and b._gap(o, o.tgt) <= RtBattle.TOUCH + 6.0
	return false

const STAT_SAY := {"정보": true, "황개": true, "황월영": true, "황조": true, "손상향": true, "정봉": true, "관해": true}      # 수치만 바뀌는 개성 —— 치는 동안 말풍선 (BOW_TEXT "p_이름")
const LOOT_CAP := 0.15      # 약탈 —— 쓰러뜨린 부대 최대 병력 대비 거두는 몫 상한
const LOOT_PER := 0.002     # 약탈 —— kill_gauge 1점마다 거두는 몫 (40 -> 8%)
const GAUGE_CD := 2.0       # 교란 —— 같은 적의 공격 준비를 다시 늦추기까지 (초) —— 연타로 묶어 두지 못하게
const GAUGE_ATB := 0.05     # 교란 —— gauge_on 1점마다 늦추는 공격 준비 (6 -> 0.3)


## 약탈 —— 고유기 없는 장수가 적을 무너뜨리면 그 병력 일부를 거둔다
func _loot(k, victim) -> void:
	var g := minf(k.max - k.troops, victim.max * minf(LOOT_CAP, v(k, "kill_gauge") * LOOT_PER))
	if g <= 0.0:
		return
	k.troops += g
	k.htr += g
	_stat("sig_kill_gauge")
	_stat("u%s:kill_gauge" % k.key)
	b.L("hl", "%s의 약탈 —— 쓰러뜨린 적의 병력을 거두었다" % b.nm(k), {"fx": "heal", "f": k.key, "n": g, "healer": k.key, "sig": true})



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
func _note_m(u, k: String, n := 1) -> void:
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
			_note_m(u, "ward_aura", hit.size())
	if v(u, "st_short") > 0.0:      # 안정 —— 걸린 이상의 지속을 줄인다
		var cut := 0
		for o in _near(u, al, R_AURA * SHORT_R):
			for s in o.st:
				if int(s.dur) > 1:
					s.dur = int(s.dur) - 1
					cut += 1
		if cut > 0:
			_note_m(u, "st_short", cut)
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
	b.stats["flank_run_t"] = b.stats.get("flank_run_t", 0.0) + b.TICK
	return wv.normalized() * desired.length() * b.flank_spd      # 11/22 우회하는 동안은 빨리 (RtBattle.flank_spd)


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


# ───────── 특별한 특기 (11/22) ─────────
## 사용자 "등애가 적진으로 날아가 아무것도 못 하고 퇴각했다 · 그래도 이런 특별한 특기는 더 많아야 한다" —— 숫자가 아니라 전장 행동을 바꾸는 특기.
## 인물 일화에서 하나씩 (키 값 = 세기, passives.json sig):
##  · 등애 음평 기습 rear_land   —— 적 뒤에 내려앉는 순간 주변 적에게 책략 피해 · 사기 −, 잠시 받는 피해 − · 고유기 기 + (내려서 한 건 하고 버틴다)
##  · 장료 합비 돌파 breach      —— BREACH_T 마다 적 최강 장수에게 곧장 파고들고(맞닿은 적을 흘려 지나간다), 닿는 순간 그 둘레 적 사기를 꺾는다
##  · 조운 장판 구출 rescue      —— 무너지는 아군을 치는 적에게 달려가 떼어 내고(물러서게), 그 아군은 잠시 덜 다친다
##  · 장비 장판교 호령 bridge    —— 둘레에 적이 몰리면 일갈해 둘레 적이 겁먹고 물러선다 (사기 −)
##  · 황개 고육계 feign_fire     —— 개전에 거짓 항복해(숨은 채) 적진으로 걸어 들어가 불을 지르고 빠진다
##  · 태사자 포위 돌파 breakout  —— 근접 적에게 붙잡히면 활을 쏘며 포위를 뚫고 물러난다
##  · 조조 할수기포 flee         —— 병력이 꺾이면 한 번, 몸을 숨겨 빠져나가고 잠시 덜 다친다 (쫓던 적은 표적을 잃는다)
##  · 전위 호위 body_guard       —— 둘레 아군이 받는 피해 일부를 대신 받는다 (호위 이동 escort 와 함께)
## 판정은 rng 를 쓰지 않고 부대 순서대로 돈다 (결정적). 점검: tests/sig_special.tscn (--off 로 끄고 짝비교)
const LAND_T := 0.3          # 등애 —— 내려앉는 때 (초)
const LAND_R := 250.0        # 등애 —— 기습이 닿는 거리
const LAND_MORALE := 15.0    # 등애 —— 기습에 꺾이는 적 사기
const LAND_DR := 0.45        # 등애 —— 내려앉은 뒤 받는 피해 감소
const LAND_DR_T := 7.0       # 등애 —— 그 시간 (초)
const LAND_GAUGE := 40.0     # 등애 —— 고유기가 있으면 채우는 기
const BREACH_T := 15.0       # 장료 —— 돌파를 다시 거는 간격 (초)
const BREACH_HOLD := 6.0     # 장료 —— 한 번 돌파에 정한 적을 쫓는 최대 시간
const BREACH_R := 170.0      # 장료 —— 닿는 순간 사기가 꺾이는 둘레
const RESCUE_LOW := 0.4      # 조운 —— 병력이 이 비율 아래인 아군을 구한다
const RESCUE_R := 650.0      # 조운 —— 구하러 가는 최대 거리
const RESCUE_CD := 12.0      # 조운 —— 다시 구하러 가기까지 (초)
const RESCUE_HOLD := 5.0     # 조운 —— 구하러 가는 시간 · 그 아군이 덜 다치는 시간
const RESCUE_MORALE := 15.0  # 조운 —— 구한 아군의 사기
const RESCUE_PUSH := 1.5     # 조운 —— 떼어 낸 적이 물러서는 시간 (초)
const BRIDGE_N := 3          # 장비 —— 둘레에 이만큼 적이 몰리면 (병력이 꺾였으면 둘)
const BRIDGE_R := 200.0      # 장비 —— 호령이 닿는 틈
const BRIDGE_CD := 16.0      # 장비 —— 다시 외치기까지 (초)
const BRIDGE_BACK := 1.6     # 장비 —— 겁먹은 적이 물러서는 시간 (초)
const FEIGN_T := 7.0         # 황개 —— 거짓 항복(숨음) 최대 시간 (초)
const FEIGN_GAP := 24.0      # 황개 —— 적과 이 틈까지 다가가면 불을 지른다
const FEIGN_R := 230.0       # 황개 —— 불길이 닿는 거리
const FEIGN_DUR := 3         # 황개 —— 화상 지속
const FEIGN_BACK := 2.5      # 황개 —— 불을 지르고 빠지는 시간 (초)
const BREAK_CD := 12.0       # 태사자 —— 다시 뚫기까지 (초)
const BREAK_RUN := 1.6       # 태사자 —— 물러나는 시간 (초)
const FLEE_LOW := 0.25       # 조조 —— 병력이 이 비율 아래로 꺾이면
const FLEE_RUN := 3.0        # 조조 —— 빠져나가는 시간 (초)
const FLEE_HIDE := 1.5       # 조조 —— 숨는 시간 (초)
const FLEE_DR_T := 5.0       # 조조 —— 덜 다치는 시간 (초)
const FLEE_MORALE := 40.0    # 조조 —— 사기 하한
const GUARD_R := 180.0       # 전위 —— 지키는 둘레 (발자국 가장자리 틈)
const GUARD_KEEP := 0.5      # 전위 —— 제 병력이 이 비율 아래면 대신 받지 않는다
const GUARD_TAKE := 0.6      # 전위 —— 대신 받는 몫에 곱한다 (두꺼운 갑옷 —— 아군이 덜 받은 몫보다 적게 깎인다)


## 말풍선 —— 특기 이름 (passives.json sig 이름) + 글, 횟수 sig_<key>
func _sp(u, key: String, text: String, up := true) -> void:
	_stat_u(u, key)
	if say_on:
		_say(u, "%s —— %s" % [_gname(u), text], up)


## 정한 적 (장료 돌파 · 조운 구출) —— 풀렸거나 쓰러졌거나 숨었으면 null
func force_tgt(u):
	var f = u.sg.get("ftg")
	if f == null:
		return null
	if not f.alive or b._tm >= float(u.sg.get("ftg_t", 0.0)) or b._hidden(f):
		u.sg.erase("ftg")
		u.sg.erase("ftk")
		return null
	return f


func _hide(u, until: float) -> void:
	u.sg["hide"] = until
	hide_until = maxf(hide_until, until)


func _special_setup() -> void:
	for u in who.get("feign_fire", []):      # 황개 —— 거짓 항복: 숨은 채 시작
		_hide(u, FEIGN_T)


## 받는 쪽 배율 —— 잠시 덜 다침(sp_dr: 등애 착지 · 조운이 구한 아군 · 조조 할수기포) · 전위 호위
func _special_taken(d, a) -> float:
	var m := 1.0
	if d.sg.has("sp_dr"):
		if b._tm < float(d.sg.get("sp_dr_t", 0.0)):
			m *= 1.0 - minf(0.6, float(d.sg["sp_dr"]))
			_stat("sig_sp_dr")
		else:
			d.sg.erase("sp_dr")
	d.sg.erase("bg")
	if has("body_guard") and a != null and a.camp != d.camp:
		for g in who["body_guard"]:
			if g != d and g.alive and g.camp == d.camp and g.troops > g.max * GUARD_KEEP and b._gap(g, d) <= GUARD_R:
				var sh := minf(0.5, v(g, "body_guard"))
				m *= 1.0 - sh
				d.sg["bg"] = [g, sh]
				break
	return m


## 전위 호위 —— 아군이 덜 받은 몫(loss 는 줄어든 뒤의 피해)을 전위가 대신 받는다. 전위는 이것으로 쓰러지지 않는다 (병력 1 이상)
func _guard_take(d, loss: float) -> void:
	var e = d.sg["bg"]
	d.sg.erase("bg")
	var g = e[0]
	if not g.alive or loss <= 0.0:
		return
	var sh: float = e[1]
	var x := minf(loss * sh / maxf(0.05, 1.0 - sh) * GUARD_TAKE, g.troops - 1.0)
	if x <= 0.0:
		return
	g.troops -= x
	g.taken += x
	_stat("sig_body_guard_n", int(x))
	_note(g, "body_guard", "호위 —— %s 대신 창을 받는다" % b.nm(d), SPEAR_SAY * 2.0)


## 때린 뒤 —— 정한 적에게 닿은 순간 (장료 돌파 · 조운 구출)
func _special_hit(a, d) -> void:
	if a.sg.get("ftg") != d:
		return
	var kind := str(a.sg.get("ftk", ""))
	a.sg.erase("ftg")
	a.sg.erase("ftk")
	var tm: float = b._tm
	if kind == "breach":
		var n := 0
		for o in _foes(a):
			if o == d or b._gap(o, d) <= BREACH_R:
				o.morale -= v(a, "breach") * (1.0 if o == d else 0.5)
				a.mdmg += v(a, "breach") * (1.0 if o == d else 0.5)
				n += 1
		_sp(a, "breach_hit", "%s의 본진을 꿰뚫었다 —— 적 %d부대가 흔들린다" % [b.nm(d), n])
	elif kind == "rescue":
		d.sg["back"] = tm + RESCUE_PUSH      # 아군을 치던 적이 물러선다 (표적은 그대로 —— 뒤로 밀린다)
		_sp(a, "rescue_hit", "%s을(를) 떼어 냈다" % b.nm(d))


## 주기 (tick 끝) —— 착지 · 돌파 · 구출 · 호령 · 거짓 항복 · 포위 돌파 · 할수기포
func _special_tick() -> void:
	var tm: float = b._tm
	for u in who.get("rear_land", []):      # 등애 —— 내려앉는 순간 한 번
		if u.alive and not u.sg.get("landed", false) and tm >= LAND_T:
			u.sg["landed"] = true
			var n := 0
			for o in _foes(u):
				if o.pos.distance_to(u.pos) <= LAND_R + o.hw:
					if b.is_caster(u.c): b.int_hit(u, o, v(u, "rear_land"), 1)
					else: b.phys_hit(u, o, v(u, "rear_land"), true)
					o.morale -= LAND_MORALE
					u.mdmg += LAND_MORALE
					n += 1
			u.sg["sp_dr"] = LAND_DR
			u.sg["sp_dr_t"] = tm + LAND_DR_T
			if u.ult != null and u.charges > 0:
				u.gauge = minf(100.0, u.gauge + LAND_GAUGE)
			_stat("sig_rear_land_n", n)
			_sp(u, "rear_land", "험로를 넘어 적의 등 뒤를 쳤다 —— 적 %d부대가 놀란다" % n)
	for u in who.get("breach", []):      # 장료 —— 적 최강 장수에게 곧장
		if u.alive and not u.sg.has("ftg") and _due(u, "breach", BREACH_T):
			var best = null
			for o in _foes(u):
				if b._hidden(o):
					continue
				if best == null or int(o.c.tier) > int(best.c.tier) or (int(o.c.tier) == int(best.c.tier) and (o.ult != null and best.ult == null or o.troops > best.troops)):
					best = o
			if best != null:
				u.sg["ftg"] = best
				u.sg["ftk"] = "breach"
				u.sg["ftg_t"] = tm + BREACH_HOLD
				_sp(u, "breach", "%s을(를) 향해 적진을 가른다" % b.nm(best))
	for u in who.get("rescue", []):      # 조운 —— 무너지는 아군을 치는 적에게
		if not u.alive or u.sg.has("ftg") or tm < float(u.sg.get("rs_cd", 0.0)) or not _due(u, "rs_chk", 1.0):
			continue
		var hurt = null
		for o in _allies(u):
			if o != u and o.troops < o.max * RESCUE_LOW and o.pos.distance_to(u.pos) <= RESCUE_R and (hurt == null or o.troops / o.max < hurt.troops / hurt.max):
				hurt = o
		if hurt == null:
			continue
		var foe = null
		var bd := INF
		for o in _foes(u):
			if o.tgt == hurt and not b._hidden(o):
				var dd: float = o.pos.distance_to(hurt.pos)
				if dd < bd:
					bd = dd
					foe = o
		if foe == null:
			continue
		u.sg["rs_cd"] = tm + RESCUE_CD
		u.sg["ftg"] = foe
		u.sg["ftk"] = "rescue"
		u.sg["ftg_t"] = tm + RESCUE_HOLD
		hurt.sg["sp_dr"] = v(u, "rescue")
		hurt.sg["sp_dr_t"] = tm + RESCUE_HOLD
		var g := minf(200.0 - hurt.morale, RESCUE_MORALE)
		if g > 0.0:
			hurt.morale += g
			u.hmo += g
		_sp(u, "rescue", "%s을(를) 구하러 적진을 가른다" % b.nm(hurt))
	for u in who.get("bridge", []):      # 장비 —— 둘레에 적이 몰리면 호령
		if not u.alive or tm < float(u.sg.get("br_cd", 0.0)) or not _due(u, "br_chk", 0.5):
			continue
		var near := []
		for o in _foes(u):
			if not b._ranged(o) and b._gap(u, o) <= BRIDGE_R:
				near.append(o)
		if near.size() >= BRIDGE_N or (near.size() >= 2 and u.troops < u.max * 0.6):
			u.sg["br_cd"] = tm + BRIDGE_CD
			for o in near:
				o.morale -= v(u, "bridge")
				u.mdmg += v(u, "bridge")
				o.sg["back"] = tm + BRIDGE_BACK
			_stat("sig_bridge_n", near.size())
			_sp(u, "bridge", "장판교의 호령 —— 적 %d부대가 겁먹고 물러선다" % near.size(), false)
	for u in who.get("feign_fire", []):      # 황개 —— 적진에 닿거나 숨음이 풀리면 불을 지른다
		if not u.alive or u.sg.get("fg_done", false):
			continue
		var close := false
		for o in _foes(u):
			if b._gap(u, o) <= FEIGN_GAP + 4.0:
				close = true
				break
		if close or tm >= FEIGN_T:
			u.sg["fg_done"] = true
			u.sg["hide"] = tm
			var n := 0
			for o in _foes(u):
				if o.pos.distance_to(u.pos) <= FEIGN_R + o.hw:
					b.inflict(u, o, "burn", v(u, "feign_fire"), FEIGN_DUR)
					n += 1
			u.sg["back"] = tm + FEIGN_BACK
			_stat("sig_feign_fire_n", n)
			_sp(u, "feign_fire", "거짓 항복한 배에서 불길이 치솟는다 —— 적 %d부대" % n)
	for u in who.get("breakout", []):      # 태사자 —— 근접 적에게 붙잡히면 쏘며 뚫고 물러난다
		if not u.alive or tm < float(u.sg.get("bk_cd", 0.0)):
			continue
		var touch := []
		for o in _foes(u):
			if not b._ranged(o) and b._gap(u, o) <= RtBattle.TOUCH + 4.0:
				touch.append(o)
		if touch.size() >= 2 or (touch.size() >= 1 and u.troops < u.max * 0.6):
			u.sg["bk_cd"] = tm + BREAK_CD
			u.sg["back"] = tm + BREAK_RUN
			for o in touch:
				b.phys_hit(u, o, v(u, "breakout"), true)
			_sp(u, "breakout", "활을 쏘며 포위를 뚫는다")
	for u in who.get("flee", []):      # 조조 —— 한 번, 꺾이면 빠져나간다
		if u.alive and not u.sg.get("fled", false) and u.troops < u.max * FLEE_LOW:
			u.sg["fled"] = true
			u.sg["back"] = tm + FLEE_RUN
			_hide(u, tm + FLEE_HIDE)
			u.sg["sp_dr"] = v(u, "flee")
			u.sg["sp_dr_t"] = tm + FLEE_DR_T
			u.morale = maxf(u.morale, FLEE_MORALE)
			for o in _foes(u):
				if o.tgt == u:
					o.tgt = null
					o.retgt = 0.0
			_sp(u, "flee", "수염을 자르고 몸을 빼낸다")
