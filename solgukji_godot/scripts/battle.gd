class_name Battle
extends RefCounted
## 전투 엔진 —— 원본 runBattle() 이식. 판정과 계수는 원본과 같다.
## 원본의 텍스트 로그에 연출용 필드를 더했다:
##   fx  : phys / int / morale / heal / buff / status / tick / cleanse / dodge / skill / rout / turn / end
##   a   : 행동한 유닛 key,  f : 대상 유닛 key,  n : 병력 수치,  m : 사기 수치,  st : 상태이상 종류
##   ai  : 행동 묶음 번호 (한 유닛의 한 차례 행동, 또는 턴 끝 정산),  ph : act / end,  who : 행동한 유닛 key
##   turn: 몇 번째 턴인지 —— 실시간 연출은 이 셋으로 행동을 시간축에 다시 깐다
##   s   : 이벤트 직후 모든 유닛의 [병력, 사기, 생존, 상태이상 목록] 스냅샷

const MYTH_AMP := 1.6
static var ults_enabled := true     # 고유기 켜기 (밸런스 비교용으로 끌 수 있다)
static var passives_enabled := true  # 특기(개인·단체) 켜기


class Unit:
	var c: Dictionary
	var line: String
	var side: String
	var camp: String
	var slot: int
	var key: String
	var item = null
	var troops: float
	var max: float
	var morale: float
	var syn_atk: float
	var syn_spd: float
	var ts = null           # 병종 시너지 {stat, v, lv}
	var caps := {}
	var regen_up := false
	var fast_side := false
	var boon = null
	var buffs := []
	var alive := true
	var hit50 := false
	var hit25 := false
	var m := {}               # 특기 수정치 (data/passives.json 의 m 키) —— mv() 로 읽는다
	var avenge_n := 0         # 비장 —— 아군이 무너진 횟수
	var opened := false       # 첫 공격을 했는가 (기신·강행·습격)
	var dmg := 0.0
	var mdmg := 0.0
	var heal := 0.0
	var kills := 0
	var last_hit: Unit = null
	var st := []
	var ult = null            # 고유기 (불멸·신화) —— DB.ult_of 참고
	var ult_ready := 99       # 고유기를 쓸 수 있는 턴


var K: Dictionary
var rng := RandomNumberGenerator.new()
var units: Array[Unit] = []
var ev := []
var _ai := 0
var _ph := "act"
var _who := ""
var _turn := 0


func _init(seed_value: int = -1) -> void:
	K = DB.K
	if seed_value >= 0:
		rng.seed = seed_value
	else:
		rng.randomize()


func rnd(a: float, b: float) -> float:
	return a + rng.randf() * (b - a)


func pick(a: Array):
	return a[rng.randi() % a.size()]


static func jong(w: String) -> bool:
	if w.is_empty():
		return false
	var c := w.unicode_at(w.length() - 1) - 0xAC00
	return c >= 0 and c < 11172 and c % 28 != 0


static func ga(w: String) -> String: return w + ("이" if jong(w) else "가")
static func eul(w: String) -> String: return w + ("을" if jong(w) else "를")
static func nm(u: Unit) -> String: return ("적 " if u.camp == "B" else "") + u.c.name


# ───────── 시너지 ─────────

static func fac_syn(cards: Array, form: String) -> Dictionary:
	var fc := {}
	var tc := {}
	for k in cards:
		if k == null:
			continue
		var c: Dictionary = DB.C[k]
		fc[c.fac] = fc.get(c.fac, 0) + 1
		tc[c.tag] = tc.get(c.tag, 0) + 1
	var out := {"morale": 0.0, "atk": 1.0, "spd": 1.0, "troop": 1.0, "list": [], "tag": {},
		"tagList": [], "caps": {}, "boon": DB.D.FORMBOON.get(form)}
	for f in fc:
		var s = DB.D.SYN.get(f)
		if s == null:
			continue
		var lv := -1
		for i in DB.D.SYN_STEP.size():
			if fc[f] >= DB.D.SYN_STEP[i]:
				lv = i
		if lv < 0:
			continue
		var v: float = s.v[lv]
		if s.stat == "morale":
			out.morale += v
		else:
			out[s.stat] *= (1.0 + v)
		out.list.append({"fac": f, "n": fc[f], "lv": lv + 1, "v": v})
		if f == "촉" and fc[f] >= 5: out.regenUp = true
		if f == "오" and fc[f] >= 5: out.fastSide = true
	for t in tc:
		var s = DB.D.TAGSYN.get(t)
		if s == null:
			continue
		var lv := -1
		for i in DB.D.TAGSYN_STEP.size():
			if tc[t] >= DB.D.TAGSYN_STEP[i]:
				lv = i
		if lv < 0:
			continue
		out.tag[t] = {"stat": s.stat, "v": float(s.v[lv]), "lv": lv + 1}
		out.tagList.append({"tag": t, "n": tc[t], "lv": lv + 1})
		if tc[t] >= 5:
			out.caps[t] = s.cap
	return out


func mk_unit(cid: String, slot_info: Dictionary, camp: String, morale: float, slot: int, item, syn: Dictionary) -> Unit:
	var u := Unit.new()
	u.c = DB.C[cid]
	u.line = slot_info.line
	u.side = slot_info.side
	u.camp = camp
	u.slot = slot
	u.key = camp + str(slot)
	u.item = item
	u.ts = syn.tag.get(u.c.tag)
	var tr: float = u.c.tr * syn.troop * (1.0 + u.ts.v if u.ts and u.ts.stat == "troop" else 1.0)
	u.troops = roundf(tr)
	u.max = roundf(tr)
	u.morale = minf(200, morale + syn.morale)
	u.syn_atk = syn.atk
	u.syn_spd = syn.spd
	u.caps = syn.caps
	u.regen_up = syn.get("regenUp", false)
	u.fast_side = syn.get("fastSide", false)
	var boon = syn.boon
	u.boon = boon if boon and boon.tags.has(u.c.tag) else null
	if passives_enabled:
		var ps = DB.passives_of(cid)
		if ps != null:
			for k in ps.self.m:
				u.m[k] = u.m.get(k, 0.0) + ps.self.m[k]
	if u.c.tier >= 7:
		u.ult = DB.ult_of(cid)
		if u.ult:
			u.ult_ready = int(u.ult.first) + rng.randi() % 2     # 장수마다 충전 시점을 흩는다
	return u


func innate_item(cid: String):
	var need: String = DB.C[cid].need
	return DB.ITEM_BY_NAME.get(need) if need != "" else null


func is_signature(u: Unit) -> bool:
	return u.c.need != "" and DB.ITEM_BY_NAME.get(u.c.need) == u.item


# ───────── 실효 수치 ─────────

func eff(u: Unit, stat: String) -> float:
	var c := u.c
	var lm: Dictionary = DB.D.LINE[u.line]
	var af: Dictionary = DB.D.AFF[c.tag]
	var v: float = c[stat]
	if stat == "atk": v *= lm.atk
	if stat == "def": v *= lm.def
	if stat == "int": v *= lm.int
	if stat == "atk" and lm.pri <= 2: v *= 1 + mv(u, "front_atk")
	if stat == "int" and lm.pri >= 3: v *= 1 + mv(u, "back_int")
	v *= 1 + mv(u, stat)
	if stat == "atk":
		if u.troops < u.max * 0.5: v *= 1 + mv(u, "low_atk")
		v *= 1 + mv(u, "avenge") * u.avenge_n
	var zone := DB.aff_of(c.tag, u.line, u.side)
	if zone == "pref" and af.b.has(stat): v *= af.b[stat]
	if zone == "bad" and af.p.has(stat): v *= af.p[stat]
	if u.item:
		var it: Dictionary = DB.IT[u.item]
		var amp := MYTH_AMP if is_signature(u) else 1.0
		if it.pri == stat: v *= (1 + it.pa * amp)
		if it.sec == stat: v *= (1 + it.sa * amp)
	if stat == "atk": v *= u.syn_atk
	if stat == "spd": v *= u.syn_spd
	if u.ts and u.ts.stat == stat: v *= (1 + u.ts.v)
	if u.boon and u.boon.stat == stat: v *= (1 + u.boon.v)
	for b in u.buffs:
		if b.stat == stat: v *= (1 + b.amt)
	if stat == "atk" or stat == "int": v *= (0.4 + 0.6 * (u.troops / u.max))
	return maxf(1, v)


func mv(u: Unit, k: String) -> float:
	return u.m.get(k, 0.0)


func has_st(u: Unit, k: String) -> bool:
	return u.st.any(func(s): return s.k == k)


func sk_rate(u: Unit) -> float:
	if has_st(u, "seal"):
		return 0.0
	var r: float = DB.D.RATE.get(str(u.c.tier), 0.0)
	if u.item:
		r += DB.IT[u.item].rb / 100.0 * (MYTH_AMP if is_signature(u) else 1.0)
	if u.ts and u.ts.stat == "rate": r += u.ts.v
	if u.boon and u.boon.stat == "rate": r += u.boon.v
	return r + mv(u, "rate")


func m_mul(u: Unit) -> float:
	return 0.5 + clampf(u.morale, 0, 200) / 200.0


func morale_guard(atk: Unit, def: Unit) -> float:
	if atk == null or def.c.tier < K.guardFrom:
		return 1.0
	var gap: int = def.c.tier - atk.c.tier
	return 1.0 if gap <= 0 else maxf(0.18, pow(K.guard, gap))


# ───────── 대상 선정 ─────────

func pri(u: Unit) -> int:
	return int(DB.D.LINE[u.line].pri)


func resolve_targets(spec: String, foes: Array, me: Unit, allies: Array) -> Array:
	if spec == "self": return [me]
	if spec == "allyAll": return allies.filter(func(u): return u.alive)
	if spec == "allyFront":
		var al := allies.filter(func(u): return u.alive)
		if al.is_empty(): return []
		var p: int = al.map(pri).min()
		return al.filter(func(u): return pri(u) == p)
	var live := foes.filter(func(u): return u.alive)
	if live.is_empty(): return []
	var ps := live.map(pri)
	var mn: int = ps.min()
	var mx: int = ps.max()
	var front := live.filter(func(u): return pri(u) == mn)
	var back := live.filter(func(u): return pri(u) == mx)
	match spec:
		"front1": return [pick(front)]
		"back1": return [pick(back)]
		"back2":
			var s := live.duplicate()
			s.sort_custom(func(a, b): return pri(a) > pri(b))
			return s.slice(0, 2)
		"front3":
			var s := live.duplicate()
			s.sort_custom(func(a, b): return pri(a) < pri(b))
			return s.slice(0, 3)
		"all": return live
		"denseLine":
			var g := {}
			for u in live:
				if not g.has(u.line): g[u.line] = []
				g[u.line].append(u)
			var best: Array = []
			for l in g:
				if g[l].size() > best.size(): best = g[l]
			return best
	if spec.begins_with("line:"):
		var want := spec.substr(5).split("+")
		var m := live.filter(func(u): return want.has(u.line))
		return m if not m.is_empty() else front
	return front


func basic_target(u: Unit, foes: Array) -> Array:
	if u.c.tag == "궁병" and (u.caps.has("궁병") or DB.aff_of(u.c.tag, u.line, u.side) == "pref"):
		return resolve_targets("back1", foes, u, [])
	if u.c.tag == "도적": return resolve_targets("back1", foes, u, [])
	if u.c.int > u.c.atk: return resolve_targets("back1", foes, u, [])
	return resolve_targets("front1", foes, u, [])


# ───────── 로그 ─────────

func L(cls: String, text: String, extra: Dictionary = {}) -> void:
	var snap := []
	for u in units:
		snap.append([maxi(0, roundi(u.troops)), roundi(u.morale), 1 if u.alive else 0, u.st.map(func(x): return x.k)])
	var e := {"c": cls, "t": text, "s": snap, "ai": _ai, "ph": _ph, "who": _who, "turn": _turn}
	e.merge(extra)
	ev.append(e)


static func num(v: float) -> String:
	var s := str(roundi(v))
	var out := ""
	var neg := s.begins_with("-")
	if neg: s = s.substr(1)
	for i in s.length():
		if i > 0 and (s.length() - i) % 3 == 0: out += ","
		out += s[i]
	return ("-" if neg else "") + out


# ───────── 타격 ─────────

func phys_hit(a: Unit, d: Unit, mult: float, no_counter := false, pierce := 0.0) -> void:
	if d.caps.has("도적") and d.c.tag == "도적" and rng.randf() < 0.45:
		L("mo", "%s 몸을 틀어 흘려냈다" % ga(nm(d)), {"fx": "dodge", "a": a.key, "f": d.key})
		return
	var A := eff(a, "atk")
	var Dv := eff(d, "def")
	if pierce > 0: Dv *= (1 - pierce)
	var crit: bool = rng.randf() < DB.PSV.base_crit + mv(a, "crit")
	var cm: float = (DB.PSV.base_critd + mv(a, "critd")) if crit else 1.0
	var op := 1.0 if a.opened else 1.0 + mv(a, "opener")
	a.opened = true
	var dmg := A * (A / (A + Dv)) * m_mul(a) * rnd(0.9, 1.1) * mult * cm * op * (1.0 - mv(d, "dr"))
	var loss := maxf(1, roundf(dmg * K.troop))
	d.troops -= loss
	a.dmg += loss
	d.last_hit = a
	L(a.camp, "%s%s %s 들이쳤다 — 병력 %s 손실" % ["치명타! " if crit else "", ga(nm(a)), eul(nm(d)), num(loss)],
		{"fx": "phys", "a": a.key, "f": d.key, "n": loss, "crit": crit})
	if not no_counter and d.alive:
		var stance = null
		for b in d.buffs:
			if b.stat == "counter": stance = b
		var p: float = (0.70 if d.caps.has("창병") and d.c.tag == "창병" else 0.0) + (stance.amt if stance else 0.0) + mv(d, "counter")
		if p > 0 and rng.randf() < p:
			L("sk", "%s 창을 되받아 찔렀다" % ga(nm(d)), {"fx": "buff", "f": d.key})
			phys_hit(d, a, 1.28, true)


func int_hit(a: Unit, d: Unit, mult: float, spread: int) -> void:
	var I := eff(a, "int")
	var R := eff(d, "res")
	R *= 1.0 - mv(a, "rpierce")
	if a.ts and a.ts.stat == "brk": R *= (1 - a.ts.v)
	var crit: bool = rng.randf() < mv(a, "icrit")
	var cm: float = (DB.PSV.base_critd + mv(a, "critd")) if crit else 1.0
	var dmg := I * (I / (I + R)) * m_mul(a) * rnd(0.9, 1.1) * mult * cm * (1.0 - mv(d, "idr"))
	var aoe: float = K.aoe if spread >= 3 else 1.0
	var ml: float = dmg * K.morale * aoe * morale_guard(a, d)
	ml *= (1.0 + mv(a, "mdeal")) * (1.0 - mv(d, "mshield"))
	d.morale -= ml
	var loss := maxf(1, roundf(dmg * K.intTroop * aoe))
	d.troops -= loss
	a.dmg += loss
	a.mdmg += ml
	d.last_hit = a
	L("mo", "%s%s의 계략이 %s의 진을 흔들었다 — 병력 %s · 사기 %d" % ["치명타! " if crit else "", nm(a), nm(d), num(loss), roundi(ml)],
		{"fx": "int", "a": a.key, "f": d.key, "n": loss, "m": ml, "crit": crit})


func morale_hit(d: Unit, amt: float, who: String, spread: int, src: Unit) -> void:
	var a: float = amt * (K.aoe if spread >= 3 else 1.0) * morale_guard(src, d)
	if src: a *= 1.0 + mv(src, "mdeal")
	a *= 1.0 - mv(d, "mshield")
	d.morale -= a
	if src: src.mdmg += a
	L("mo", "『%s』에 %s의 군세가 술렁인다 — 사기 %d 감소" % [who, nm(d), roundi(a)],
		{"fx": "morale", "f": d.key, "m": a})


func heal_troop(d: Unit, ratio: float, who: String, src: Unit) -> void:
	if not d.alive: return
	var g := minf(roundf(d.max * ratio), d.max - d.troops)
	if g <= 0: return
	d.troops += g
	if src: src.heal += g / 300.0
	L("hl", "『%s』에 %s의 대오가 정비된다 — 병력 +%s" % [who, nm(d), num(g)],
		{"fx": "heal", "f": d.key, "n": g})


func heal_morale(d: Unit, amt: float, who: String, src: Unit) -> void:
	var b := d.morale
	d.morale = minf(200, d.morale + amt)
	var g := d.morale - b
	if src and g > 0: src.heal += g
	if g > 0.5:
		L("hl", "『%s』에 %s의 군세가 다시 일어선다 — 사기 +%d" % [who, nm(d), roundi(g)],
			{"fx": "heal", "f": d.key, "m": g})


func add_buff(u: Unit, b: Dictionary) -> void:
	u.buffs.append({"stat": b.stat, "amt": float(b.amt), "dur": int(b.dur)})
	var up: bool = b.amt > 0
	L("sk", "%s의 %s %s · %s%d%%" % [nm(u), ga(DB.D.STATNM.get(b.stat, b.stat)), "올랐다" if up else "꺾였다",
		"+" if up else "", roundi(b.amt * 100)], {"fx": "buff", "f": u.key, "up": up})


func inflict(a: Unit, d: Unit, kind: String, val: float, dur: int) -> void:
	if not d.alive: return
	if mv(d, "stres") > 0 and rng.randf() < mv(d, "stres"):
		L("st", "%s 『%s』%s 버텨냈다" % [ga(nm(d)), DB.D.STATUS[kind].n, "을" if jong(DB.D.STATUS[kind].n) else "를"],
			{"fx": "resist", "f": d.key, "st": kind})
		return
	var stx: float = (1 + a.ts.v) if a and a.ts and a.ts.stat == "stx" else 1.0
	var ext := (1 if a and a.caps.has("책사") else 0) + (1 if a and a.caps.has("술사") else 0)
	var resist := 1.0 if a and a.caps.has("술사") else (morale_guard(a, d) if d.c.tier >= K.guardFrom else 1.0)
	var scale: float = d.max if kind in ["burn", "flood", "bleed"] else 1.0
	var v := maxf(1, roundf(val * scale * stx * resist))
	var t := maxi(dur, 1) + ext
	var old = null
	for s in d.st:
		if s.k == kind: old = s
	if old:
		old.val = maxf(old.val, v)
		old.dur = maxi(old.dur, t)
	else:
		if d.st.size() >= 2:
			var w = d.st[0]
			for s in d.st:
				if s.dur <= w.dur: w = s
			d.st.erase(w)
		d.st.append({"k": kind, "val": v, "dur": t})
	L("st", "%s 『%s』에 걸렸다 — %d턴" % [ga(nm(d)), DB.D.STATUS[kind].n, t],
		{"fx": "status", "f": d.key, "st": kind})


func cleanse(u: Unit) -> bool:
	if u.st.is_empty(): return false
	var k: String = u.st.pop_front().k
	var sn: String = DB.D.STATUS[k].n
	L("hl", "%s의 『%s』%s 씻겼다" % [nm(u), sn, "이" if jong(sn) else "가"], {"fx": "cleanse", "f": u.key, "st": k})
	return true


func tick_status() -> void:
	for u in units:
		if not u.alive or u.st.is_empty(): continue
		for s in u.st:
			match s.k:
				"burn":
					u.troops -= s.val
					L("st", "%s 불길에 휩싸인다 — 병력 %s 손실" % [ga(nm(u)), num(s.val)], {"fx": "tick", "f": u.key, "st": "burn", "n": s.val})
				"flood":
					var l := roundf(s.val * 0.7)
					u.troops -= l
					L("st", "%s의 진영이 물에 잠긴다 — 병력 %s 손실" % [nm(u), num(l)], {"fx": "tick", "f": u.key, "st": "flood", "n": l})
				"bleed":
					u.troops -= s.val
					L("st", "%s의 상처가 벌어진다 — 병력 %s 손실" % [nm(u), num(s.val)], {"fx": "tick", "f": u.key, "st": "bleed", "n": s.val})
				"plague":
					u.morale -= s.val
					L("st", "%s의 군세에 역병이 돈다 — 사기 %d 감소" % [nm(u), roundi(s.val)], {"fx": "tick", "f": u.key, "st": "plague", "m": s.val})
		for s in u.st: s.dur -= 1
		u.st = u.st.filter(func(s): return s.dur > 0)
	for cp in ["A", "B"]:
		var side := units.filter(func(u): return u.alive and u.camp == cp)
		if side.is_empty() or not side[0].caps.has("유생"): continue
		for u in side:
			if not u.st.is_empty():
				cleanse(u)
				break


func rout(u: Unit, why: String) -> void:
	if not u.alive: return
	u.alive = false
	if u.last_hit and u.last_hit.camp != u.camp: u.last_hit.kills += 1
	for o in units:
		if not o.alive or o.camp != u.camp: continue
		o.morale -= (K.routSame if o.line == u.line else K.routOther) * (1.0 - mv(o, "rout_loss"))
		if mv(o, "avenge") > 0 and o.avenge_n < 3:
			o.avenge_n += 1
	L("rt", "%s의 군세가 %s" % [nm(u), why], {"fx": "rout", "f": u.key})


func check_rout() -> void:
	for o in units:
		if o.alive and o.troops <= 0: rout(o, "병력이 다해 무너졌다")


# ───────── 본 전투 ─────────

func run(a_cards: Array, a_form: String, a_morale: float, a_equip, b_cards: Array, b_form: String,
		b_morale: float, b_equip, title := "", foe_name := "") -> Dictionary:
	var a_syn := fac_syn(a_cards, a_form)
	var b_syn := fac_syn(b_cards, b_form)
	var aS: Array = DB.FORM[a_form].slots
	var bS: Array = DB.FORM[b_form].slots
	for i in a_cards.size():
		var k = a_cards[i]
		if k and i < aS.size():
			units.append(mk_unit(k, aS[i], "A", a_morale, i, a_equip[i] if a_equip and a_equip[i] else innate_item(k), a_syn))
	for i in b_cards.size():
		var k = b_cards[i]
		if k and i < bS.size():
			units.append(mk_unit(k, bS[i], "B", b_morale, i, b_equip[i] if b_equip and b_equip[i] else innate_item(k), b_syn))
	if passives_enabled:
		_apply_group_passives()

	var turn := 0
	var winner := ""
	while turn < K.cap and winner == "":
		turn += 1
		_turn = turn
		_ai += 1
		_ph = "act"
		_who = ""
		L("div", "", {"fx": "turn", "turn": turn})
		for u in units:
			for b in u.buffs: b.dur -= 1
			u.buffs = u.buffs.filter(func(b): return b.dur > 0)
		var order := []
		for u in units:
			if not u.alive: continue
			var sp: float
			if mv(u, "first") > 0: sp = eff(u, "spd") * 1.25
			else: sp = eff(u, "spd") * (1 + rnd(-0.15, 0.15))
			if turn == 1 and u.caps.has("기병") and u.c.tag == "기병": sp *= 1.6
			if u.fast_side: sp *= 1.12
			order.append([u, sp])
		order.sort_custom(func(x, y): return x[1] > y[1])

		for o in order:
			_ai += 1
			_ph = "act"
			_who = o[0].key
			act(o[0])
			check_rout()
		_ai += 1
		_ph = "end"
		_who = ""

		for u in units:
			if not u.alive: continue
			var r := u.troops / u.max
			var tg := 1.0 - mv(u, "shock")
			if not u.hit50 and r <= 0.5:
				u.hit50 = true
				u.morale -= K.hit50 * tg
			if not u.hit25 and r <= 0.25:
				u.hit25 = true
				u.morale -= K.hit25 * tg
			if u.morale > 30 and u.morale < 100:
				var rg: float = K.regen * (1.5 if u.regen_up else 1.0)
				if u.caps.has("유생"): rg *= 2
				u.morale = minf(100, u.morale + rg)
		for cp in ["A", "B"]:
			var side := units.filter(func(u): return u.alive and u.camp == cp)
			if side.is_empty() or not side[0].caps.has("유생"): continue
			for u in side:
				var g := minf(roundf(u.max * 0.045), u.max - u.troops)
				if g > 0: u.troops += g
			L("hl", "대오를 추스른다 — 진영 병력 4.5% 회복", {"fx": "heal", "f": side[0].key})
		tick_status()
		check_rout()
		for cp in ["A", "B"]:
			var healed := ""
			for u in units:
				if not u.alive or u.camp != cp: continue
				if mv(u, "mregen") > 0:
					u.morale = minf(200, u.morale + mv(u, "mregen"))
				if mv(u, "regen") > 0 and u.troops < u.max:
					u.troops = minf(u.max, u.troops + roundf(u.max * mv(u, "regen")))
					healed = u.key
			if healed != "":
				L("hl", "특기로 대오를 추스른다", {"fx": "heal", "f": healed})
		for u in units:
			if not u.alive or u.morale > 30: continue
			var p := maxf(K.routMin, (30 - u.morale) * K.routSlope)
			p *= 1.0 - mv(u, "rout")
			if u.caps.has("유생"): p *= 0.5
			if rng.randf() < p:
				rout(u, "사기 %d에서 끝내 패주했다" % maxi(0, roundi(u.morale)))
		var aA := live_count("A")
		var bA := live_count("B")
		if aA == 0 and bA == 0: winner = "draw"
		elif bA == 0: winner = "A"
		elif aA == 0: winner = "B"

	_ai += 1
	_ph = "end"
	if winner == "":
		var at := 0.0
		var bt := 0.0
		for u in units:
			if not u.alive: continue
			if u.camp == "A": at += u.troops
			else: bt += u.troops
		winner = "A" if at > bt else ("B" if bt > at else "draw")
		L("div", "해가 기운다 — 잔존 병력 %s 대 %s" % [num(at), num(bt)], {"fx": "turn"})

	for u in units:
		u.last_hit = null       # 순환 참조를 끊어 RefCounted 가 풀리게 한다
	var roster := []
	for u in units:
		roster.append({"id": u.c.id, "name": u.c.name, "tier": u.c.tier, "tag": u.c.tag, "fac": u.c.fac,
			"line": u.line, "side": u.side, "camp": u.camp, "max": u.max, "key": u.key, "slot": u.slot,
			"item": u.item, "morale": u.morale})
	var merit := func(u: Unit): return u.dmg + u.mdmg * 420 + u.heal * 420 + u.kills * 3200
	var mine := units.filter(func(u): return u.camp == "A" and merit.call(u) > 0)
	mine.sort_custom(func(x, y): return merit.call(x) > merit.call(y))
	var mvp = null
	if not mine.is_empty():
		mvp = {"name": mine[0].c.name, "id": mine[0].c.id, "kills": mine[0].kills, "dmg": roundi(mine[0].dmg)}
	return {"win": winner == "A", "draw": winner == "draw", "ev": ev, "roster": roster, "title": title,
		"foe": foe_name, "aForm": a_form, "bForm": b_form, "aSyn": a_syn, "bSyn": b_syn, "mvp": mvp,
		"left": live_count("A"), "eLeft": live_count("B"), "turns": turn}


func live_count(cp: String) -> int:
	return units.filter(func(u): return u.alive and u.camp == cp).size()


func act(u: Unit) -> void:
	if not u.alive: return
	if has_st(u, "confuse"):
		L("st", "%s 혼란에 빠져 움직이지 못한다" % ga(nm(u)), {"fx": "status", "f": u.key, "st": "confuse"})
		return
	var foes := units.filter(func(o): return o.camp != u.camp)
	var allies := units.filter(func(o): return o.camp == u.camp)
	if not foes.any(func(o): return o.alive): return
	# 고유기 —— 준비되면 이번 차례를 고유기로 쓴다 (봉인 중에는 못 쓴다)
	if ults_enabled and u.ult != null and _turn >= u.ult_ready and not has_st(u, "seal"):
		u.ult_ready = _turn + int(u.ult.cd)
		_do_ult(u, foes, allies)
		return
	var sk = u.c.sk
	var used := false
	if sk and rng.randf() < sk_rate(u):
		var e: Dictionary = sk.eff
		var ok := true
		if e.get("cond") == "hurt" and u.troops / u.max > 0.5: ok = false
		if ok:
			used = true
			L("sk", "%s 『%s』%s 펼친다" % [ga(nm(u)), sk.n, "을" if jong(sk.n) else "를"],
				{"fx": "skill", "a": u.key, "name": sk.n, "kind": e.kind})
			match e.kind:
				"phys":
					var ts := resolve_targets(e.tgt, foes, u, allies)
					for t in ts:
						if not t.alive: continue
						phys_hit(u, t, e.mult, false, e.get("pierce", 0.0))
						if e.has("exec") and t.troops > 0 and t.troops / t.max <= e.exec: rout(t, "한 칼에 짓밟혔다")
						if e.has("morale"): morale_hit(t, e.morale, sk.n, ts.size(), u)
						if e.has("spd"): add_buff(t, {"stat": "spd", "amt": e.spd.amt, "dur": e.spd.dur})
						if e.has("resDown"): add_buff(t, {"stat": "res", "amt": e.resDown.amt, "dur": e.resDown.dur})
						if e.has("status"): inflict(u, t, e.status.k, e.status.val, int(e.status.dur))
					if e.has("selfBuff"): add_buff(u, e.selfBuff)
					if e.has("stance"): u.buffs.append({"stat": "counter", "amt": float(e.stance.amt), "dur": int(e.stance.dur)})
					if e.has("allyBuff"):
						for t in resolve_targets(e.allyBuff.tgt, foes, u, allies): add_buff(t, e.allyBuff)
				"int":
					var ts := resolve_targets(e.tgt, foes, u, allies)
					for t in ts:
						if not t.alive: continue
						int_hit(u, t, e.mult, ts.size())
						if e.has("morale"): morale_hit(t, e.morale, sk.n, ts.size(), u)
						if e.has("resDown"): add_buff(t, {"stat": "res", "amt": e.resDown.amt, "dur": e.resDown.dur})
						if e.has("status"): inflict(u, t, e.status.k, e.status.val, int(e.status.dur))
						if u.caps.has("모사") and rng.randf() < 0.30: inflict(u, t, "seal", 1, 2)
					if e.has("heal"):
						for t in allies:
							if t.alive: heal_morale(t, e.heal, sk.n, u)
					if e.has("tHeal"):
						for t in allies:
							if t.alive: heal_troop(t, e.tHeal, sk.n, u)
					if e.has("cleanse"):
						var n: int = e.cleanse
						for t in allies:
							if n <= 0: break
							if t.alive and not t.st.is_empty() and cleanse(t): n -= 1
					if e.has("allyBuff"):
						for t in resolve_targets(e.allyBuff.tgt, foes, u, allies): add_buff(t, e.allyBuff)
	if not used:
		var tt := basic_target(u, foes)
		if not tt.is_empty() and tt[0].alive:
			if u.c.int > u.c.atk: int_hit(u, tt[0], 1, 1)
			else: phys_hit(u, tt[0], 1)


func _do_ult(u: Unit, foes: Array, allies: Array) -> void:
	var ul: Dictionary = u.ult
	var nm_: String = ul.name
	L("sk", "%s 고유기 『%s』 —— “%s”" % [nm(u), nm_, ul.shout],
		{"fx": "ult", "a": u.key, "name": nm_, "shout": ul.shout, "vfx": ul.vfx})
	for comp in ul.eff:
		var ts := resolve_targets(comp.tgt, foes, u, allies)
		match comp.t:
			"hit":
				for t in ts:
					if not t.alive: continue
					if comp.kind == "phys":
						phys_hit(u, t, comp.mult, false, comp.get("pierce", 0.0))
					else:
						int_hit(u, t, comp.mult, ts.size())
					if comp.has("exec") and t.alive and t.troops > 0 and t.troops / t.max <= comp.exec:
						rout(t, "고유기에 짓밟혔다")
					if comp.has("morale") and t.alive:
						morale_hit(t, comp.morale, nm_, ts.size(), u)
					if comp.has("status") and t.alive:
						inflict(u, t, comp.status.k, comp.status.val, int(comp.status.dur))
			"ally":
				for t in ts:
					if not t.alive: continue
					if comp.has("heal"):
						heal_troop(t, comp.heal, nm_, u)
					if comp.has("morale"):
						heal_morale(t, comp.morale, nm_, u)
					if comp.has("buff"):
						add_buff(t, comp.buff)
					if comp.has("cleanse"):
						for i in int(comp.cleanse):
							if not cleanse(t): break
			"foe":
				for t in ts:
					if not t.alive: continue
					if comp.has("morale"):
						morale_hit(t, comp.morale, nm_, ts.size(), u)
					if comp.has("buff"):
						add_buff(t, comp.buff)
					if comp.has("status"):
						inflict(u, t, comp.status.k, comp.status.val, int(comp.status.dur))


## 단체 특기 —— 전투 시작에 한 번. 같은 이름은 둘까지 겹친다 (센 것 하나 + 두 번째는 절반).
func _apply_group_passives() -> void:
	var got := {}             # 유닛 -> {특기 이름: [배율, …]}
	var owner := {}           # [진영, 이름] -> 가장 센 주인 (기록용)
	for u in units:
		var ps = DB.passives_of(u.c.id)
		if ps == null or ps.group == null:
			continue
		var g: Dictionary = ps.group
		var n := 0
		for t in units:
			if _scope_hits(g.scope, u, t):
				if not got.has(t):
					got[t] = {}
				if not got[t].has(g.name):
					got[t][g.name] = []
				got[t][g.name].append(g.scale)
				n += 1
		var ok: String = u.camp + g.name
		if not owner.has(ok) or g.scale > owner[ok][1]:
			owner[ok] = [u, g.scale, n, g]
	for t in got:
		for nm_ in got[t]:
			var sc: Array = got[t][nm_]
			sc.sort()
			sc.reverse()
			var total: float = sc[0] + (sc[1] * 0.5 if sc.size() > 1 else 0.0)
			var base: Dictionary = DB.PSV.catalog[nm_].m
			for k in base:
				t.m[k] = t.m.get(k, 0.0) + base[k] * total
	for ok in owner:
		var o: Array = owner[ok]
		L("sk", "%s의 단체 특기 『%s』 — %s" % [nm(o[0]), o[3].name, o[3].d],
			{"fx": "passive", "a": o[0].key, "name": o[3].name, "n": o[2]})
	# 병력·사기는 시작 값에 바로 반영한다
	for u in units:
		if mv(u, "troop") > 0:
			u.max = roundf(u.max * (1.0 + mv(u, "troop")))
			u.troops = u.max
		u.morale = clampf(u.morale + mv(u, "morale") - mv(u, "foe_morale"), 0, 200)


func _scope_hits(scope: String, u: Unit, t: Unit) -> bool:
	if scope == "foe":
		return t.camp != u.camp
	if t.camp != u.camp:
		return false
	if scope == "all":
		return true
	if scope == "fac":
		return t.c.fac == u.c.fac
	if scope.begins_with("tag:"):
		return t.c.tag == scope.substr(4)
	if scope.begins_with("line:"):
		return scope.substr(5).split(",").has(t.line)
	return false
