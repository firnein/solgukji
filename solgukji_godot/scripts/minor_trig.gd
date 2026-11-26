extends RefCounted
## 11/24 잡기술 발동 조건 —— 사용자 "잡기술을 평타 몇 번당 발동으로만 통일하지 말아줘 · 병종마다가 아니라 장수마다로".
## 인물 잡기술(Battle.MINOR_STORY)은 연의 일화에 맞는 조건, 공용 잡기술(화계 · 찌르기 …)은 병종 조건.
## 판정은 장수가 공격하는 순간(Battle._minor) —— 조건이 맞고 재사용 간격이 지났으면 평타 대신 잡기술.
## 사건형 조건(맞음 · 쓰러뜨림 · 부딪힘 …)은 tick 이 기록하고 ARM 초 안에 공격하면 쓴다. 난수 없음 (결정적).
## 끄기: RtBattle.minor_trig = false (예전대로 평타 N 번마다)

const ARM := 3.0         # 사건이 일어난 뒤 이 초 안에 공격하면 잡기술
const NEAR := 100.0      # '주변' 적 · 아군 (발자국 틈)
const SIDE := 200.0      # 수 비교(합비 돌격 · 하북 대군)의 범위
const CD := 3.0          # 기본 재사용 간격 (초) —— 11/24 4 → 3 (사용자: 늘어지는 전투)
## 맞닿음(근접전) = 근접 공격이 닿는 틈 (RtBattle.melee_gap) —— 근접 부대는 TOUCH 까지 붙지 않고 이 틈에서 싸운다

## [조건, 재사용 간격 초, 값] —— every 는 평타 값번마다 (예전 방식)
const STORY := {
	"vanguard": ["contact_new"], "duel": ["solo"], "lone_ride": ["surround"], "xiliang": ["impact"],
	"white_horse": ["foe_low_morale"], "cleave": ["multi_touch"], "conquer": ["kill"], "tiger": ["bigger"],
	"raid": ["engaged"], "plunder": ["foe_low_morale"], "last_stand": ["half"], "surprise": ["flank"],
	"hefei": ["outnumbered"], "forced_march": ["ran"], "trap_camp": ["rammed"], "bodyguard": ["ally_hit"],
	"eye": ["big_hit"], "bare": ["long_melee"], "multitude": ["outnumber"], "discipline": ["hit_n", CD, 3],
	"hold_fort": ["hit_n", CD, 2], "rescue": ["lord_hit"], "sword_dance": ["every", 0.0, 3], "old_general": ["every", 0.0, 3],
	"ambush_shot": ["unwatched"], "divine_bow": ["far"], "repeat_xbow": ["every", 0.0, 3],
	"plan": ["every", 0.0, 3], "secret": ["foe_wind"], "omen": ["timer", 5.0], "proclaim": ["morale_behind"],
	"remonstrate": ["losing"], "diplomacy": ["hit"], "sow": ["clustered"], "taoist_book": ["foe_status"],
	"haunt": ["ally_down"], "yellow": ["timer", 6.0], "ten_ambush": ["deep"], "imperial_seal": ["timer", 6.0],
	"supply": ["ally_low", 6.0, 0.6], "recommend": ["ally_down"], "zither": ["ally_morale_low"],
	"heal_bone": ["ally_status"], "benevolence": ["ally_low", CD, 0.5], "plum": ["ally_morale_low"]}
## 공용 잡기술 —— 병종 조건
const CLASS := {
	"창병": ["melee_hit", 3.0], "기병": ["impact"], "궁병": ["volley", 4.0], "도적": ["foe_wind"],
	"책사": ["clustered", 6.0], "모사": ["camp_kill"], "유생": ["ally_low", 5.0, 0.7]}

var b = null
var s := {}              # 부대 → 상태
var camp_t := {}         # "A:ally_down" 같은 진영 사건 → 시각
var foe_wind := {}       # 진영 → [기 모으기 시작한 적, 시각]
var _wind_seen := {}
var _lord := {}          # 진영 → 등급이 가장 높은 장수


static func make(bt) -> Object:
	var m = load("res://scripts/minor_trig.gd").new()
	m.b = bt
	for u in bt.units:
		m.s[u] = {"next": -99.0, "used": -99.0, "tk": u.taken, "hits": 0, "hit_t": -99.0, "mhit_t": -99.0, "big_t": -99.0,
			"touch": {}, "mel0": -1.0, "new_t": -99.0, "imp_t": -99.0, "ram_t": -99.0, "kill_t": -99.0,
			"half": u.troops >= u.max * 0.5, "half_n": 0, "half_t": -99.0, "ahit_t": -99.0, "alive": u.alive}
	for cp in ["A", "B"]:
		var best = null
		for u in bt.units:
			if u.camp == cp and (best == null or u.c.tier > best.c.tier or (u.c.tier == best.c.tier and u.max > best.max)):
				best = u
		m._lord[cp] = best
	return m


func release() -> void:
	b = null
	s.clear()
	_lord.clear()
	foe_wind.clear()


## 매 TICK —— 맞음 · 쓰러짐 · 맞닿음 · 기 모으기 시작을 기록한다
func tick() -> void:
	var tm: float = b._tm
	for w in b._wind:
		if not _wind_seen.has(w):
			_wind_seen[w] = true
			foe_wind[b._foe(w.camp)] = [w, tm]
	for w in _wind_seen.keys():
		if not b._wind.has(w):
			_wind_seen.erase(w)
	for u in b.units:
		var st: Dictionary = s[u]
		if st.alive and not u.alive:
			st.alive = false
			camp_t[u.camp + ":ally_down"] = tm
			var k = u.last_hit
			if k != null and k.camp != u.camp and s.has(k):
				s[k].kill_t = tm
				camp_t[k.camp + ":kill"] = tm
			if _lord.get(u.camp) == u:
				_lord[u.camp] = _next_lord(u.camp)
			continue
		if not u.alive:
			continue
		var dt: float = u.taken - float(st.tk)
		st.tk = u.taken
		if dt > 0.0:
			st.hits = int(st.hits) + 1
			st.hit_t = tm
			if dt >= u.max * 0.05:
				st.big_t = tm
			if _lord.get(u.camp) == u:
				camp_t[u.camp + ":lord_hit"] = tm
			for o in b.units:
				if o != u and o.alive and o.camp == u.camp and b._gap(o, u) <= 40.0:
					s[o].ahit_t = tm
		var half: bool = u.troops >= u.max * 0.5
		if st.half and not half and int(st.half_n) < 2:
			st.half_n = int(st.half_n) + 1
			st.half_t = tm
		st.half = half
		# 맞닿음 —— 새로 닿은 적 · 달려와 부딪힘 · 들이받힘 · 이어진 근접전
		var now := {}
		var melee_on := false
		for o in b.units:
			if o.alive and o.camp != u.camp and b._gap(u, o) <= b.melee_gap + 2.0:
				now[o] = true
				if not o.ranged:
					melee_on = true
				if not st.touch.has(o):
					st.new_t = tm
					if u.ran >= 100.0:
						st.imp_t = tm
					if o.ran >= 60.0:
						st.ram_t = tm
		if dt > 0.0 and melee_on:
			st.mhit_t = tm
		st.touch = now
		if now.is_empty():
			st.mel0 = -1.0
		elif float(st.mel0) < 0.0:
			st.mel0 = tm


func _next_lord(cp: String):
	var best = null
	for u in b.units:
		if u.alive and u.camp == cp and (best == null or u.c.tier > best.c.tier or (u.c.tier == best.c.tier and u.max > best.max)):
			best = u
	return best


## 이 공격에 잡기술을 쓰는가 —— null 이면 예전 방식(평타 N 번), false 면 아직, Unit 이면 그 적에게
func gate(u, mk: String, t):
	var tr: Array = STORY.get(mk, CLASS.get(u.c.tag, ["every", 0.0, 3]))
	if tr[0] == "every":
		return null
	var st: Dictionary = s[u]
	var tm: float = b._tm
	if tm < float(st.next):
		return false
	var cd: float = float(tr[1]) * CD / 4.0 if tr.size() > 1 else CD      # 따로 적은 간격도 기본 간격(처음 4초)에 비례해 줄인다
	var p = tr[2] if tr.size() > 2 else 0
	var hit = _cond(u, st, str(tr[0]), p, t, tm)
	if hit == null or (hit is bool and not hit):
		return false
	st.next = tm + cd
	st.used = tm
	b.stats["mt_" + str(tr[0])] = int(b.stats.get("mt_" + str(tr[0]), 0)) + 1      # 점검용 —— 조건별 발동 수
	return t if hit is bool else hit


func _armed(st: Dictionary, key: String, tm: float) -> bool:
	var at: float = float(st[key])
	return at >= tm - ARM and at > float(st.used)


func _camp_armed(st: Dictionary, key: String, tm: float) -> bool:
	var at: float = float(camp_t.get(key, -99.0))
	return at >= tm - ARM and at > float(st.used)


func _near(u, camp_foe: bool, r: float) -> int:
	var n := 0
	for o in b.units:
		if o.alive and o != u and (o.camp != u.camp) == camp_foe and b._gap(u, o) <= r:
			n += 1
	return n


func _cond(u, st: Dictionary, k: String, p, t, tm: float):
	match k:
		"contact_new": return _armed(st, "new_t", tm)
		"solo": return _near(u, true, NEAR) == 1
		"surround": return _near(u, true, NEAR) >= 3
		"impact": return _armed(st, "imp_t", tm)
		"foe_low_morale": return t.morale < 60.0
		"multi_touch": return _near(u, true, 150.0) >= 2
		"kill": return _armed(st, "kill_t", tm)
		"bigger": return t.troops > u.troops
		"engaged": return t.tgt != null and t.tgt != u and t.tgt.camp == u.camp
		"half": return _armed(st, "half_t", tm)
		"flank":
			var v: Vector2 = u.pos - t.pos
			return v.length() > 0.1 and absf(t.fwd.angle_to(v)) > PI / 3.0
		"outnumbered": return _near(u, true, SIDE) > _near(u, false, SIDE) + 1
		"outnumber": return _near(u, false, SIDE) + 1 > _near(u, true, SIDE)
		"ran": return u.ran >= 150.0
		"rammed": return _armed(st, "ram_t", tm)
		"ally_hit": return _armed(st, "ahit_t", tm)
		"big_hit": return _armed(st, "big_t", tm)
		"long_melee": return float(st.mel0) >= 0.0 and tm - float(st.mel0) >= 5.0
		"hit_n":
			if int(st.hits) >= int(p):
				st.hits = 0
				return true
			return false
		"lord_hit": return _camp_armed(st, u.camp + ":lord_hit", tm) and _lord.get(u.camp) != u
		"unwatched":
			for o in b.units:
				if o.alive and o.camp != u.camp and o.tgt == u:
					return false
			return true
		"far": return b._gap(u, t) >= 0.8 * b._reach(u)
		"foe_wind":
			var fw: Array = foe_wind.get(u.camp, [])
			if fw.is_empty() or float(fw[1]) < tm - ARM or float(fw[1]) <= float(st.used) or not fw[0].alive:
				return false
			return fw[0]
		"timer": return true
		"morale_behind": return _avg_morale(b._foe(u.camp)) > _avg_morale(u.camp)
		"losing": return _sum_troops(u.camp) < _sum_troops(b._foe(u.camp))
		"hit": return _armed(st, "hit_t", tm)
		"melee_hit": return _armed(st, "mhit_t", tm)
		"clustered":
			for o in b.units:
				if o.alive and o != t and o.camp == t.camp and b._gap(t, o) <= 40.0:
					return true
			return false
		"foe_status":
			if _dot_like(t):
				return true
			for o in b.units:
				if o.alive and o.camp != u.camp and _dot_like(o):
					return o
			return false
		"ally_down": return _camp_armed(st, u.camp + ":ally_down", tm)
		"deep":
			for a in b.units:
				if a.alive and a.camp == u.camp and a.ranged:
					for o in b.units:
						if o.alive and o.camp != u.camp and b._gap(a, o) <= 120.0:
							return o
			return false
		"ally_low":
			for a in b.units:
				if a.alive and a.camp == u.camp and a.troops < a.max * float(p):
					return true
			return false
		"ally_morale_low":
			for a in b.units:
				if a.alive and a.camp == u.camp and a.morale < 80.0:
					return true
			return false
		"ally_status":
			for a in b.units:
				if a.alive and a.camp == u.camp and a.st.any(func(x): return x.k in ["burn", "plague", "bleed"]):
					return true
			return false
		"volley":
			var r: float = b._reach(u) + 2.0
			var n := 0
			for o in b.units:
				if o.alive and o.camp != u.camp and b._gap(u, o) <= r:
					n += 1
			return n >= 2
		"camp_kill": return _camp_armed(st, u.camp + ":kill", tm) or t.morale < 60.0
	return null


func _dot_like(o) -> bool:
	return o.st.any(func(x): return x.k in ["burn", "plague", "bleed", "flood", "confuse"])


func _avg_morale(cp: String) -> float:
	var n := 0
	var m := 0.0
	for o in b.units:
		if o.alive and o.camp == cp:
			n += 1
			m += o.morale
	return m / maxf(1.0, n)


func _sum_troops(cp: String) -> float:
	var m := 0.0
	for o in b.units:
		if o.alive and o.camp == cp:
			m += o.troops
	return m
