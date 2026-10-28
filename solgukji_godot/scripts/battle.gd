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
## 전투 속도 —— 솔국지 확장 (원본에 없음). 턴마다 흐르는 양(병력·사기 피해, 지속 피해, 회복)을 모두 이만큼 곱한다.
## 원본 계수 그대로면 같은 등급끼리 2~3턴에 끝나 상태이상·디버프가 쓸 틈이 없다. 0.35 면 같은 등급끼리 평균 4~11턴
## (tests/turns.tscn). 비율은 그대로라 원본의 균형(피해 대 회복, 직접 대 지속)은 유지된다. 일회성 기준값
## (반파·괴멸 사기 하락, 패주 확률, 처형 문턱)은 바꾸지 않는다.
static var pace := 0.35
## 사기는 '결과' —— 솔국지 확장. 책략 한 대마다 능력치에 비례해 사기를 깎던 것(원본 K.morale)을 없앴다.
## 사기 통은 등급과 관계없이 100 이라 낮은 등급에선 그 피해가 거의 0 이었고(책사·술사가 약한 까닭), 높은 등급에선 과했다.
## 대신 책략은 병력 피해가 int_troop 배로 오르고, 패주는 병력이 꺾여도 일어난다(rout_hp 아래, 비율에 따라).
## 스킬·고유기·특기의 고정 사기 효과, 아군 이탈·반파 충격, 역병 같은 '사건'은 그대로다.
static var int_troop := 1.7
static var rout_hp := 0.3          # 병력이 이 비율 아래면 턴 끝마다 패주를 굴린다
static var rout_hp_slope := 1.5    # (rout_hp - 남은 비율) × 이만큼 —— 10% 남으면 30%
static var ults_enabled := true     # 고유기 켜기 (밸런스 비교용으로 끌 수 있다)
static var passives_enabled := true  # 특기(개인·단체) 켜기
static var fire_enabled := true      # 화공 속성 켜기 (솔국지 확장 —— 비교용으로 끌 수 있다)
static var water_enabled := true     # 수공 속성 켜기 (수몰 이감 규칙 포함)

## 전투 중 개입 —— 고유기 직접 발동과 군령.
## 입력은 [행동 번호, 진영, 종류, 값]. 같은 시드 + 같은 입력이면 언제나 같은 결과다(결정적).
## 화면은 입력이 생길 때마다 처음부터 다시 계산한다 —— 입력 앞부분은 똑같이 나오고 뒤만 달라진다.
## 정책: auto(충전되면 제 차례에 바로 · 군령은 늘 돌격) · smart(상황을 보고 끼어든다) · manual(입력만)
##       tac:<고유기>:<군령> —— 덱 주인이 정하는 비동기 상대 AI 전술. smart = tac:영리:영리
##         고유기  즉시(차면 바로) · 영리(값어치 볼 때) · 위기(아군이 꺾였을 때만)
##         군령    공세(늘 돌격) · 영리(상대를 보고) · 수비(방진·재정비로 버틴다)
const GAUGE_ACT := 30.0       # 제 차례마다
const GAUGE_HIT := 80.0       # 병력을 잃은 비율 × 이만큼
const GAUGE_DEAL := 6.0       # 때릴 때마다
const ULT_CHARGES := {7: 1, 8: 1}   # 불멸·신화 모두 전투당 1번
const ULT_SIDE_GAP := 4       # 같은 진영 고유기 사이 최소 행동 수
const PTS_EVERY := 6          # 행동 6번마다 군령 포인트 1
const PTS_MAX := 3.0
const CMD_COST := 2.0
const CMD_TURNS := 2
const CRISIS_LOSS := 0.35     # 위기 —— 아군 평균 병력 손실이 이만큼 넘거나
const CRISIS_UNITS := 5       #        살아 있는 부대가 이만큼 이하면
static var crisis_amp := 1.3  # 위기에 쓴 고유기 위력 배율 (배수진) —— 점검용으로 바꿀 수 있어 static
static var cmd_links := true   # 특기–군령 연결 켜기 (비교용)
static var breach := 0.0      # 돌격 중인 공격자가 무시하는 적 방진 피해 감소 비율 —— 0 이 기본 (올리면 조작 효과가 사라진다, 기획 문서 참고)
const CMDS := {
	"돌격": {"d": "공격 +20% · 방어 -25%", "buffs": [{"stat": "atk", "amt": 0.20}, {"stat": "def", "amt": -0.25}, {"stat": "breach", "amt": 1.0}]},
	"방진": {"d": "받는 피해 -30% · 속도 -10% · 받는 고유기 피해 추가 -35%", "buffs": [{"stat": "guard", "amt": 0.30}, {"stat": "spd", "amt": -0.10}, {"stat": "uguard", "amt": 0.35}]},
	"재정비": {"d": "사기 +9 · 패주 확률 -60%", "buffs": [{"stat": "calm", "amt": 0.6}], "morale": 25.0},     # 사기는 heal_morale 에서 pace(0.35)를 곱해 +9
}


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
	var night_used := false   # 야습 —— 첫 공격의 확정 점화를 썼는가
	var dmg := 0.0
	var mdmg := 0.0
	var heal := 0.0
	var kills := 0
	var last_hit: Unit = null
	var st := []
	var ult = null            # 고유기 (불멸·신화) —— DB.ult_of 참고
	var gauge := 0.0          # 고유기 게이지 (100 이면 준비)
	var charges := 0          # 남은 고유기 횟수


var K: Dictionary
var rng := RandomNumberGenerator.new()
var units: Array[Unit] = []
var ev := []
var _ai := 0
var _ph := "act"
var _who := ""
var _turn := 0
var inputs := []              # 받을 입력 [행동 번호, 진영, 종류, 값]
var applied := []             # 실제로 적용된 입력 (재생·검증용)
var rejected := []            # 거절된 입력과 까닭 (점검용)
var policy := {"A": "auto", "B": "auto"}
var act_n := 0                # 지금까지 끝낸 행동 수 —— 입력 시점의 기준
var pts := {"A": 0.0, "B": 0.0}
var cmdm := {"A": {}, "B": {}}    # 특기–군령 연결 (data/passives.json catalog 의 cmd) —— 진영 단위
var _ult_last := {"A": -99, "B": -99}
var _bdone := -1              # 입력 판정(_between)을 마친 행동 번호 —— 사건에 bd 로 적어 화면이 입력 시점을 고른다
var _in_ult := false          # 고유기 타격 중 —— 방진이 이만큼 막는다
var stats := {"dmg": 0.0, "ult_dmg": 0.0, "blocked": 0, "ult_hits": 0,    # 점검용
	"burn": 0.0, "fire_amp": 0.0, "ignites": 0, "spreads": 0, "doused": 0, "terror": 0.0, "blazes": 0, "scorched": 0,
	"flood": 0.0, "water_amp": 0.0, "soaks": 0, "flows": 0, "drowned": 0, "tides": 0, "steams": 0}


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
	var ps = DB.passives_of(cid)
	if ps != null:
		for t in ps.traits:
			if not _trait_on(t):
				continue
			for k in t.m:
				u.m[k] = u.m.get(k, 0.0) + t.m[k]
	if u.c.tier >= 7:
		u.ult = DB.ult_of(cid)
		if u.ult:
			u.charges = ULT_CHARGES.get(u.c.tier, 1)
	return u


## 특기 켜짐 —— 속성(화공) 특기는 fire_enabled, 나머지는 passives_enabled
func _trait_on(t: Dictionary) -> bool:
	match t.attr:
		"화공": return fire_enabled
		"수공": return water_enabled
	return passives_enabled


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
	if stat == "spd": v *= u.syn_spd * _flood_slow(u)
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
		snap.append([maxi(0, roundi(u.troops)), roundi(u.morale), 1 if u.alive else 0, u.st.map(func(x): return x.k),
			int(u.gauge), u.charges])     # 내림 —— 100 은 정말 다 찼을 때만
	var e := {"c": cls, "t": text, "s": snap, "ai": _ai, "ph": _ph, "who": _who, "turn": _turn,
		"an": act_n, "pts": [pts.A, pts.B], "bd": _bdone == act_n}
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
	dmg *= 1.0 - _guard(a, d)
	if _in_ult:
		dmg *= 1.0 - _buff_sum(d, "uguard")
	var fm := _fire_mul(a, d)
	var wm := _water_mul(a, d)
	dmg *= fm * wm
	var loss := maxf(1, roundf(dmg * K.troop * pace))
	stats.fire_amp += loss * (1.0 - 1.0 / fm)
	stats.water_amp += loss * (1.0 - 1.0 / wm)
	_stat(d, loss)
	d.troops -= loss
	a.dmg += loss
	d.last_hit = a
	_charge(d, a, loss)
	L(a.camp, "%s%s %s 들이쳤다 — 병력 %s 손실" % ["치명타! " if crit else "", ga(nm(a)), eul(nm(d)), num(loss)],
		{"fx": "phys", "a": a.key, "f": d.key, "n": loss, "crit": crit, "fire": fm > 1.0, "water": wm > 1.0})
	_ignite(a, d)
	_soak(a, d)
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
	dmg *= 1.0 - _guard(a, d)
	if _in_ult:
		dmg *= 1.0 - _buff_sum(d, "uguard")
	var fm := _fire_mul(a, d)
	var wm := _water_mul(a, d)
	dmg *= fm * wm
	var aoe: float = K.aoe if spread >= 3 else 1.0
	var loss := maxf(1, roundf(dmg * K.intTroop * int_troop * pace * aoe))
	stats.fire_amp += loss * (1.0 - 1.0 / fm)
	stats.water_amp += loss * (1.0 - 1.0 / wm)
	_stat(d, loss)
	_charge(d, a, loss)
	d.troops -= loss
	a.dmg += loss
	d.last_hit = a
	L("mo", "%s%s의 계략이 %s의 진을 흔들었다 — 병력 %s 손실" % ["치명타! " if crit else "", nm(a), nm(d), num(loss)],
		{"fx": "int", "a": a.key, "f": d.key, "n": loss, "crit": crit, "fire": fm > 1.0, "water": wm > 1.0})
	_ignite(a, d)
	_soak(a, d)


func morale_hit(d: Unit, amt: float, who: String, spread: int, src: Unit) -> void:
	var a: float = amt * pace * (K.aoe if spread >= 3 else 1.0) * morale_guard(src, d)
	if src: a *= 1.0 + mv(src, "mdeal")
	a *= 1.0 - mv(d, "mshield")
	d.morale -= a
	if src: src.mdmg += a
	L("mo", "『%s』에 %s의 군세가 술렁인다 — 사기 %d 감소" % [who, nm(d), roundi(a)],
		{"fx": "morale", "f": d.key, "m": a})


func heal_troop(d: Unit, ratio: float, who: String, src: Unit) -> void:
	if not d.alive or _scorched(d): return
	var g := minf(roundf(d.max * ratio * pace), d.max - d.troops)
	if g <= 0: return
	d.troops += g
	if src: src.heal += g / 300.0
	L("hl", "『%s』에 %s의 대오가 정비된다 — 병력 +%s" % [who, nm(d), num(g)],
		{"fx": "heal", "f": d.key, "n": g})


func heal_morale(d: Unit, amt: float, who: String, src: Unit) -> void:
	var b := d.morale
	d.morale = minf(200, d.morale + amt * pace)
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
	var scale: float = d.max * pace if kind in ["burn", "flood", "bleed"] else (pace if kind == "plague" else 1.0)
	var fire := 1.0
	var sp := 0.0
	if kind == "burn":
		fire = _burn_mul(a, d)
		ext += int(mv(a, "burn_dur")) if a else 0
		sp = mv(a, "spread") if a else 0.0
	elif kind == "flood" and water_enabled:
		fire = 1.0 - minf(0.9, mv(d, "flood_res"))
		sp = mv(a, "flow") if a else 0.0
	var amp := 1.0 + (mv(a, "st_amp") if a and kind in ["burn", "flood", "bleed", "plague"] else 0.0)     # 요술
	var v := maxf(1, roundf(val * scale * stx * resist * fire * amp))
	var t := maxi(dur, 1) + ext
	if kind == "flood":
		_douse(d)
	var old = null
	for s in d.st:
		if s.k == kind: old = s
	if old:
		old.val = maxf(old.val, v)
		old.dur = maxi(old.dur, t)
		old.sp = maxf(old.get("sp", 0.0), sp)
	else:
		if d.st.size() >= 2:
			var w = d.st[0]
			for s in d.st:
				if s.dur <= w.dur: w = s
			d.st.erase(w)
		d.st.append({"k": kind, "val": v, "dur": t, "sp": sp})
	L("st", "%s 『%s』에 걸렸다 — %d턴" % [ga(nm(d)), DB.D.STATUS[kind].n, t],
		{"fx": "status", "f": d.key, "st": kind})


func cleanse(u: Unit) -> bool:
	if u.st.is_empty(): return false
	var k: String = u.st.pop_front().k
	var sn: String = DB.D.STATUS[k].n
	L("hl", "%s의 『%s』%s 씻겼다" % [nm(u), sn, "이" if jong(sn) else "가"], {"fx": "cleanse", "f": u.key, "st": k})
	return true


func tick_status() -> void:
	var spreads := []
	for u in units:
		if not u.alive or u.st.is_empty(): continue
		for s in u.st:
			match s.k:
				"burn":
					u.troops -= s.val
					stats.burn += s.val
					var tr := _side_max(_foe(u.camp), "terror")
					if tr > 0:
						u.morale -= tr * pace
						stats.terror += tr * pace
					if s.get("sp", 0.0) > 0 and rng.randf() < s.sp:
						spreads.append([u, s])
					L("st", "%s 불길에 휩싸인다 — 병력 %s 손실" % [ga(nm(u)), num(s.val)], {"fx": "tick", "f": u.key, "st": "burn", "n": s.val})
				"flood":
					var l := roundf(s.val * 0.7)
					u.troops -= l
					stats.flood += l
					if s.get("sp", 0.0) > 0 and rng.randf() < s.sp:
						spreads.append([u, s])
					L("st", "%s의 진영이 물에 잠긴다 — 병력 %s 손실" % [nm(u), num(l)], {"fx": "tick", "f": u.key, "st": "flood", "n": l})
				"bleed":
					u.troops -= s.val
					L("st", "%s의 상처가 벌어진다 — 병력 %s 손실" % [nm(u), num(s.val)], {"fx": "tick", "f": u.key, "st": "bleed", "n": s.val})
				"plague":
					u.morale -= s.val
					L("st", "%s의 군세에 역병이 돈다 — 사기 %d 감소" % [nm(u), roundi(s.val)], {"fx": "tick", "f": u.key, "st": "plague", "m": s.val})
		for s in u.st: s.dur -= 1
		u.st = u.st.filter(func(s): return s.dur > 0)
	for sp in spreads:
		_spread_burn(sp[0], sp[1])
	_drown()
	for cp in ["A", "B"]:
		var side := units.filter(func(u): return u.alive and u.camp == cp)
		if side.is_empty() or not side[0].caps.has("유생"): continue
		for u in side:
			if not u.st.is_empty():
				cleanse(u)
				break


# ───────── 화공 (솔국지 확장) ─────────

## 불타는 적을 칠 때 피해 배율 —— 공격자의 fire_amp, 대상의 fire_res 가 깎는다
func _fire_mul(a: Unit, d: Unit) -> float:
	if a == null or not fire_enabled:
		return 1.0
	var res := 1.0 - minf(1.0, mv(d, "fire_res"))
	var m := 1.0 + mv(a, "fire_hit") * res          # 화염일격 —— 즉발 (고급·희귀)
	if has_st(d, "burn"):
		m *= 1.0 + mv(a, "fire_amp") * res
	return m


## 화상 세기 배율 —— 건 쪽 burn_amp, 받는 쪽 fire_weak 는 올리고 fire_res 는 내린다
func _burn_mul(a: Unit, d: Unit) -> float:
	var m := (1.0 + (mv(a, "burn_amp") if a else 0.0)) * (1.0 + mv(d, "fire_weak"))
	return m * (1.0 - minf(0.9, mv(d, "fire_res")))


## 점화로 거는 화상 세기 —— 거는 카드 등급별 (data/passives.json fire.burn.val)
func _fire_burn(a: Unit) -> float:
	return float(DB.PSV.fire.burn.val[str(clampi(a.c.tier, 3, 8))])


## 점화 —— 맞힐 때마다 ignite 확률로 화상
func _ignite(a: Unit, d: Unit) -> void:
	var p := mv(a, "ignite")
	if mv(a, "night") > 0 and not a.night_used:
		a.night_used = true
		p = 1.0
	if p <= 0 or d.troops <= 0 or not d.alive:
		return
	if p >= 1.0 or rng.randf() < p:
		stats.ignites += 1
		inflict(a, d, "burn", _fire_burn(a), int(DB.PSV.fire.burn.dur))


## 번짐 —— 같은 열의 이웃(없으면 아무 아군)에게 화상이 옮겨 붙는다. 세기는 spread_val 배, 번진 불은 반만 다시 번진다
func _spread_burn(u: Unit, s: Dictionary) -> void:
	var cand := units.filter(func(o): return o.alive and o != u and o.camp == u.camp and not has_st(o, s.k))
	if cand.is_empty():
		return
	var same := cand.filter(func(o): return o.line == u.line)
	_spread_burn_to(u, s, pick(same if not same.is_empty() else cand))


func _spread_burn_to(u: Unit, s: Dictionary, t: Unit) -> void:
	var water: bool = s.k == "flood"
	var res := mv(t, "flood_res") if water else mv(t, "fire_res")
	var weak := 0.0 if water else mv(t, "fire_weak")
	var v := maxf(1, roundf(s.val / u.max * t.max * float(DB.PSV.water.flow_val if water else DB.PSV.fire.spread_val) * (1.0 + weak) * (1.0 - minf(0.9, res))))
	if t.st.size() >= 2:
		var w = t.st[0]
		for x in t.st:
			if x.dur <= w.dur: w = x
		t.st.erase(w)
	t.st.append({"k": s.k, "val": v, "dur": maxi(1, s.dur), "sp": s.sp * 0.5})
	if water:
		stats.flows += 1
		L("st", "물길이 %s의 진영으로 흘러들었다" % nm(t), {"fx": "status", "f": t.key, "st": "flood", "from": u.key})
	else:
		stats.spreads += 1
		L("st", "불길이 %s에게 번졌다" % nm(t), {"fx": "status", "f": t.key, "st": "burn", "from": u.key})


## 진영에서 가장 센 수정치 (살아 있는 부대 중)
func _side_max(cp: String, k: String) -> float:
	var v := 0.0
	for o in units:
		if o.alive and o.camp == cp:
			v = maxf(v, mv(o, k))
	return v


## 화선돌격·박망파 —— 전투 시작에 적 선봉 전체에 화상 (가진 장수마다)
func _kindle() -> void:
	for u in units:
		if mv(u, "kindle") <= 0:
			continue
		var foes := units.filter(func(o): return o.camp != u.camp)
		var front := resolve_targets("allyFront", [], u, foes)
		L("sk", "%s의 불길이 적 선봉을 덮친다" % nm(u), {"fx": "skill", "a": u.key, "name": "화공", "kind": "int"})
		for t in front:
			inflict(u, t, "burn", _fire_burn(u), int(DB.PSV.fire.burn.dur))


## 칠백리 —— 불타던 부대가 무너지면 그 불이 같은 열 전체로
func _blaze(u: Unit) -> void:
	var s = null
	for x in u.st:
		if x.k == "burn": s = x
	if s == null:
		return
	for t in units:
		if t.alive and t != u and t.camp == u.camp and t.line == u.line and not has_st(t, "burn"):
			_spread_burn_to(u, s, t)
			stats.blazes += 1


## 오소 —— 불타는 부대는 (적에게 오소가 있으면) 병력을 회복하지 못한다
func _scorched(d: Unit) -> bool:
	if not fire_enabled or not has_st(d, "burn") or _side_max(_foe(d.camp), "scorch") <= 0:
		return false
	stats.scorched += 1
	return true


# ───────── 수공 (솔국지 확장) ─────────

## 물에 잠긴 적을 칠 때 피해 배율 —— 공격자의 water_amp, 대상의 flood_res 가 깎는다
func _water_mul(a: Unit, d: Unit) -> float:
	if a == null or not water_enabled:
		return 1.0
	var res := 1.0 - minf(1.0, mv(d, "flood_res"))
	var m := 1.0 + mv(a, "water_hit") * res         # 수격 —— 즉발 (고급·희귀)
	if has_st(d, "flood"):
		m *= 1.0 + mv(a, "water_amp") * res
	return m


## 수몰된 부대의 속도 배율 (이감) —— 기본 water.slow + 적 진영의 격류, 제방이 깎는다
func _flood_slow(u: Unit) -> float:
	if not water_enabled or not has_st(u, "flood"):
		return 1.0
	var sl := minf(0.7, float(DB.PSV.water.slow) + _side_max(_foe(u.camp), "flood_slow"))
	return 1.0 - sl * (1.0 - minf(1.0, mv(u, "flood_res")))


## 침수로 거는 수몰 세기 —— 거는 카드 등급별
func _water_flood(a: Unit) -> float:
	return float(DB.PSV.water.flood.val[str(clampi(a.c.tier, 3, 8))])


## 침수 —— 맞힐 때마다 soak 확률로 수몰
func _soak(a: Unit, d: Unit) -> void:
	var p := mv(a, "soak")
	if p <= 0 or d.troops <= 0 or not d.alive:
		return
	if rng.randf() < p:
		stats.soaks += 1
		inflict(a, d, "flood", _water_flood(a), int(DB.PSV.water.flood.dur))


## 백의도강 —— 전투 시작에 적 후군 전체에 수몰 (가진 장수마다)
func _tide() -> void:
	for u in units:
		if mv(u, "tide") <= 0:
			continue
		var live := units.filter(func(o): return o.camp != u.camp and o.alive)
		if live.is_empty():
			continue
		var mx: int = live.map(pri).max()
		L("sk", "%s의 군사가 강을 건너 적 후군을 덮친다" % nm(u), {"fx": "skill", "a": u.key, "name": "수공", "kind": "int"})
		for t in live.filter(func(o): return pri(o) == mx):
			stats.tides += 1
			inflict(u, t, "flood", _water_flood(u), int(DB.PSV.water.flood.dur))


## 수엄칠군 —— 적에게 수엄칠군이 있으면, 잠긴 채 병력이 drown_at 아래로 떨어진 부대는 휩쓸려 무너진다
func _drown() -> void:
	if not water_enabled:
		return
	for u in units:
		if not u.alive or not has_st(u, "flood") or u.troops / u.max >= float(DB.PSV.water.drown_at):
			continue
		if _side_max(_foe(u.camp), "drown") > 0:
			stats.drowned += 1
			rout(u, "물에 휩쓸려 무너졌다")


## 수몰이 걸리면 불이 꺼진다
func _douse(d: Unit) -> void:
	if fire_enabled and water_enabled and _side_max(_foe(d.camp), "steam") > 0:
		for x in d.st:
			if x.k == "burn":
				x.val = roundf(x.val * 1.3)
				stats.steams += 1
				L("st", "묶인 %s의 진영에 불길이 더 거세진다" % nm(d), {"fx": "status", "f": d.key, "st": "burn"})
		return
	for x in d.st:
		if x.k == "burn":
			d.st.erase(x)
			stats.doused += 1
			L("st", "%s의 불길이 물에 꺼졌다" % nm(d), {"fx": "cleanse", "f": d.key, "st": "burn"})
			return


func rout(u: Unit, why: String) -> void:
	if not u.alive: return
	u.alive = false
	if fire_enabled and has_st(u, "burn") and _side_max(_foe(u.camp), "blaze") > 0:
		_blaze(u)
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
		b_morale: float, b_equip, title := "", foe_name := "", inputs_ := [], policy_ := {}) -> Dictionary:
	inputs = inputs_
	for cp in policy_:
		policy[cp] = policy_[cp]
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
	if passives_enabled or fire_enabled:
		_apply_group_passives()
		for cp in ["A", "B"]:
			pts[cp] = minf(PTS_MAX, cmdm[cp].get("pts_start", 0.0))

	if fire_enabled:
		_kindle()
	if water_enabled:
		_tide()
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
			_between()
			if not o[0].alive:
				act_n += 1
				continue
			_ai += 1
			_ph = "act"
			_who = o[0].key
			act(o[0])
			check_rout()
			act_n += 1
			if act_n % PTS_EVERY == 0:
				for cp in ["A", "B"]:
					pts[cp] = minf(PTS_MAX, pts[cp] + 1.0 + cmdm[cp].get("pts_rate", 0.0))
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
				var rg: float = K.regen * pace * (1.5 if u.regen_up else 1.0)
				if u.caps.has("유생"): rg *= 2
				u.morale = minf(100, u.morale + rg)
		for cp in ["A", "B"]:
			var side := units.filter(func(u): return u.alive and u.camp == cp)
			if side.is_empty() or not side[0].caps.has("유생"): continue
			for u in side:
				if _scorched(u): continue
				var g := minf(roundf(u.max * 0.045 * pace), u.max - u.troops)
				if g > 0: u.troops += g
			L("hl", "대오를 추스른다 — 진영 병력 %.1f%% 회복" % (4.5 * pace), {"fx": "heal", "f": side[0].key})
		tick_status()
		check_rout()
		for cp in ["A", "B"]:
			var healed := ""
			for u in units:
				if not u.alive or u.camp != cp: continue
				if mv(u, "mregen") > 0:
					u.morale = minf(200, u.morale + mv(u, "mregen") * pace)
				if mv(u, "regen") > 0 and u.troops < u.max and not _scorched(u):
					u.troops = minf(u.max, u.troops + roundf(u.max * mv(u, "regen") * pace))
					healed = u.key
			if healed != "":
				L("hl", "특기로 대오를 추스른다", {"fx": "heal", "f": healed})
		for u in units:
			if not u.alive: continue
			var r := u.troops / u.max
			var pm := maxf(K.routMin, (30 - u.morale) * K.routSlope) if u.morale <= 30 else 0.0
			var pt := (rout_hp - r) * rout_hp_slope if r < rout_hp else 0.0
			if pm <= 0 and pt <= 0: continue
			var p := 1.0 - (1.0 - pm) * (1.0 - pt)
			p *= 1.0 + _side_max(_foe(u.camp), "fear")      # 위압 —— 적 진영에서 가장 센 값 하나
			p *= 1.0 - mv(u, "rout")
			p *= 1.0 - _buff_sum(u, "calm")
			if u.caps.has("유생"): p *= 0.5
			if rng.randf() < p:
				if pm >= pt:
					rout(u, "사기 %d에서 끝내 패주했다" % maxi(0, roundi(u.morale)))
				else:
					rout(u, "병력이 꺾여 패주했다 (남은 병력 %d%%)" % roundi(r * 100))
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
		"left": live_count("A"), "eLeft": live_count("B"), "turns": turn, "applied": applied, "rejected": rejected, "policy": policy.duplicate(), "stats": stats}


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
	# 고유기 —— 자동 정책이면 준비된 차례에 바로 쓴다 (영리한 AI·사람은 _between 에서 끼어든다)
	u.gauge = minf(100.0, u.gauge + GAUGE_ACT * (1.2 if u.c.tier >= 8 else 1.0))
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
	u.charges -= 1
	u.gauge = 0.0
	_ult_last[u.camp] = act_n
	_in_ult = true
	var nm_: String = ul.name
	var amp := crisis_amp if _crisis(u.camp) else 1.0
	L("sk", "%s 고유기 『%s』 —— “%s”%s" % [nm(u), nm_, ul.shout, " (배수진 —— 위력 ×%.1f)" % amp if amp > 1.0 else ""],
		{"fx": "ult", "a": u.key, "name": nm_, "shout": ul.shout, "vfx": ul.vfx, "crisis": amp > 1.0})
	for comp_ in ul.eff:
		var comp: Dictionary = _amp_comp(comp_, amp)
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
	_in_ult = false


## 단체 특기 —— 전투 시작에 한 번. 같은 이름은 둘까지 겹친다 (센 것 하나 + 두 번째는 절반).
func _apply_group_passives() -> void:
	var got := {}             # 유닛 -> {특기 이름: [배율, …]}
	var owner := {}           # [진영, 이름] -> 가장 센 주인 (기록용)
	for u in units:
		var ps = DB.passives_of(u.c.id)
		if ps == null:
			continue
		for g in ps.groups:
			if _trait_on(g):
				_group_from(u, g, got, owner)
	_finish_groups(got, owner)


func _group_from(u: Unit, g: Dictionary, got: Dictionary, owner: Dictionary) -> void:
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


func _finish_groups(got: Dictionary, owner: Dictionary) -> void:
	for t in got:
		for nm_ in got[t]:
			var sc: Array = got[t][nm_]
			sc.sort()
			sc.reverse()
			var total: float = sc[0] + (sc[1] * 0.5 if sc.size() > 1 else 0.0)
			var base: Dictionary = DB.group_def(nm_).m
			for k in base:
				t.m[k] = t.m.get(k, 0.0) + base[k] * (1.0 if k == "burn_dur" else total)
	for ok in owner:
		var o: Array = owner[ok]
		var cm: Dictionary = DB.group_def(o[3].name).get("cmd", {}) if cmd_links else {}
		for k in cm:
			cmdm[o[0].camp][k] = maxf(cmdm[o[0].camp].get(k, 0.0), cm[k] * o[1])
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



# ───────── 전투 중 개입 ─────────

func _stat(d: Unit, loss: float) -> void:
	stats.dmg += loss
	if _in_ult:
		stats.ult_dmg += loss
		stats.ult_hits += 1
		if _buff_sum(d, "uguard") > 0:
			stats.blocked += 1


func _charge(d: Unit, a: Unit, loss: float) -> void:
	d.gauge = minf(100.0, d.gauge + GAUGE_HIT * loss / d.max)
	a.gauge = minf(100.0, a.gauge + GAUGE_DEAL)


func _buff_sum(u: Unit, stat: String) -> float:
	var s := 0.0
	for b in u.buffs:
		if b.stat == stat:
			s += b.amt
	return s


func can_ult(u: Unit) -> bool:
	return ults_enabled and u.alive and u.ult != null and u.charges > 0 and u.gauge >= 100.0 \
		and not has_st(u, "seal") and act_n - _ult_last[u.camp] >= ULT_SIDE_GAP


## 행동 사이 —— 이번 행동 번호에 걸린 입력을 처리하고, 영리한 AI 가 판단한다
func _between() -> void:
	_bdone = act_n
	# 양쪽 AI 는 이번 판단 직전의 같은 상황을 보고 동시에 정한다. 예전엔 A 가 먼저 군령을 내리면 B 가 그걸 보고
	# 같은 순간에 방진으로 받아쳐 B 쪽이 늘 유리했다 (영리 대 영리, 덱을 바꿔 붙여도 A 승률 40% 안팎).
	# 사람(A)의 입력도 이 뒤에 처리되므로 AI 가 사람의 군령을 보고 맞대응하지 못한다.
	var seen := {}
	for cp in ["A", "B"]:
		seen[cp] = {"charging": _side_has(_foe(cp), "atk"), "threat": _ult_threat(cp)}
	for inp in inputs:
		if int(inp[0]) == act_n:
			_apply_input(inp)
	for cp in ["A", "B"]:
		if policy[cp] == "smart":
			_smart(cp, "영리", "영리", seen[cp])
		elif str(policy[cp]).begins_with("tac:"):
			var tp: PackedStringArray = str(policy[cp]).split(":")
			_smart(cp, tp[1], tp[2], seen[cp])
		elif policy[cp] == "auto":
			for u in units:
				if u.camp == cp and can_ult(u):
					_interrupt_ult(u)
					break
			if pts[cp] >= CMD_COST:
				_command(cp, "돌격")


func _apply_input(inp: Array) -> void:
	var cp: String = inp[1]
	match inp[2]:
		"ult":
			for u in units:
				if u.key == inp[3] and u.camp == cp:
					if can_ult(u):
						_interrupt_ult(u)
						applied.append(inp)
					else:
						rejected.append([inp, "alive=%s ult=%s charges=%d gauge=%.1f seal=%s gap=%d" % [u.alive, u.ult != null, u.charges, u.gauge, has_st(u, "seal"), act_n - _ult_last[cp]]])
		"cmd":
			if pts[cp] >= CMD_COST and CMDS.has(inp[3]):
				_command(cp, inp[3])
				applied.append(inp)
		"policy":
			policy[cp] = inp[3]
			applied.append(inp)


func _interrupt_ult(u: Unit) -> void:
	_ai += 1
	_ph = "act"
	_who = u.key
	var foes := units.filter(func(o): return o.camp != u.camp)
	var allies := units.filter(func(o): return o.camp == u.camp)
	_do_ult(u, foes, allies)
	check_rout()


func _command(cp: String, name_: String) -> void:
	pts[cp] -= CMD_COST
	_ai += 1
	_ph = "act"
	_who = ""
	var c: Dictionary = CMDS[name_]
	L("sk", "%s 진영 군령 『%s』 —— %s" % ["아군" if cp == "A" else "적", name_, c.d],
		{"fx": "cmd", "camp": cp, "name": name_})
	for u in units:
		if not u.alive or u.camp != cp:
			continue
		for b in c.buffs:
			u.buffs.append({"stat": b.stat, "amt": _cmd_amt(cp, name_, b), "dur": CMD_TURNS})
		if c.has("morale"):
			heal_morale(u, c.morale * (1.0 + cmdm[cp].get("rally", 0.0)), name_, null)


## 특기가 세게 해 주는 군령 수치 —— 맹진은 돌격의 공격, 창진은 방진의 피해 감소, 군주는 재정비
func _cmd_amt(cp: String, name_: String, b: Dictionary) -> float:
	var up := 0.0
	if name_ == "돌격" and b.stat == "atk":
		up = cmdm[cp].get("assault", 0.0)
	elif name_ == "방진" and b.stat == "guard":
		up = cmdm[cp].get("phalanx", 0.0)
	elif name_ == "재정비" and b.stat == "calm":
		return minf(0.9, b.amt * (1.0 + cmdm[cp].get("rally", 0.0)))
	return b.amt * (1.0 + up)


## 영리한 AI —— 고유기는 값어치가 있을 때, 군령은 상대를 보고 고른다
func _smart(cp: String, ult_t: String, cmd_t: String, seen: Dictionary) -> void:
	# 기본은 자동과 같다 (충전되면 쓰고, 포인트는 돌격). 다른 점:
	#  ① 적이 돌격 중이면 방진으로 받는다 —— 적의 공격 상승은 막고, 방어가 내려간 적을 친다
	#  ② 적 광역 고유기가 터지기 직전이면 방진
	#  ③ 회복·격려형 고유기는 아군이 꺾일 때까지 아껴 둔다
	var threat: float = seen.threat
	var foe_charging: bool = seen.charging
	if cmd_t != "공세" and pts[cp] >= CMD_COST and not _side_has(cp, "uguard") and (foe_charging or threat >= 75.0):
		_command(cp, "방진")
	for u in units:
		if u.camp == cp and can_ult(u) and _ult_ok(u, ult_t):
			_interrupt_ult(u)
			break
	if pts[cp] < CMD_COST:
		return
	match cmd_t:
		"공세":
			_command(cp, "돌격")
		"수비":
			# 돌격은 하지 않는다. 사기가 꺾이면 재정비, 포인트가 넘치면 방진을 미리 친다
			if _avg_morale(cp) < 60.0:
				_command(cp, "재정비")
			elif pts[cp] >= PTS_MAX and not _side_has(cp, "guard"):
				_command(cp, "방진")
		_:
			if not foe_charging and threat < 50.0:
				_command(cp, "돌격")


func _ult_ok(u: Unit, ult_t: String) -> bool:
	match ult_t:
		"즉시":
			return true
		"위기":
			return _crisis(u.camp) or u.troops / u.max < 0.4      # 쓰지도 못하고 쓰러지지 않게
	return _ult_worth(u)


## 위기 —— 아군이 꺾였는가. 이때 쓴 고유기는 crisis_amp 배 (배수진)
func _crisis(cp: String) -> bool:
	var mine := units.filter(func(o): return o.alive and o.camp == cp)
	var hurt := 0.0
	for o in mine:
		hurt += 1.0 - o.troops / o.max
	return hurt / maxf(1, mine.size()) > CRISIS_LOSS or mine.size() <= CRISIS_UNITS


func _amp_comp(comp: Dictionary, amp: float) -> Dictionary:
	if amp == 1.0:
		return comp
	var c := comp.duplicate()
	if c.t == "hit":
		c.mult = c.mult * amp
	elif c.t == "ally":
		for k in ["heal", "morale"]:
			if c.has(k):
				c[k] = c[k] * amp
	return c


## 방진의 피해 감소 —— 돌격 중인 공격자는 그 일부를 무시한다
func _guard(a: Unit, d: Unit) -> float:
	return _buff_sum(d, "guard") * (1.0 - (breach if _buff_sum(a, "breach") > 0 else 0.0))


func _avg_morale(cp: String) -> float:
	var n := 0
	var m := 0.0
	for o in units:
		if o.alive and o.camp == cp:
			m += o.morale
			n += 1
	return m / maxf(1, n)


func _foe(cp: String) -> String:
	return "B" if cp == "A" else "A"


## 적 진영에서 가장 많이 찬 광역 고유기 게이지
func _ult_threat(cp: String) -> float:
	var g := 0.0
	for u in units:
		if u.camp != cp and u.alive and u.ult != null and u.charges > 0 and _ult_wide(u):
			g = maxf(g, u.gauge)
	return g


func _foe_has_ult(cp: String) -> bool:
	for u in units:
		if u.camp != cp and u.alive and u.ult != null and u.charges > 0:
			return true
	return false


func _side_has(cp: String, stat: String) -> bool:
	for u in units:
		if u.camp == cp and u.alive and _buff_sum(u, stat) > 0:
			return true
	return false


func _ult_wide(u: Unit) -> bool:
	for comp in u.ult.eff:
		if comp.t == "hit" and (comp.tgt in ["all", "front3", "denseLine"] or str(comp.tgt).begins_with("line:")):
			return true
	return false


func _ult_phys(u: Unit) -> bool:
	for comp in u.ult.eff:
		if comp.t == "hit" and comp.kind == "phys":
			return true
	return false


func _ult_worth(u: Unit) -> bool:
	var mine := units.filter(func(o): return o.alive and o.camp == u.camp)
	var foes := units.filter(func(o): return o.alive and o.camp != u.camp)
	if foes.is_empty() or mine.is_empty():
		return false
	var hurt := 0.0
	var low_morale := 0.0
	for o in mine:
		hurt += 1.0 - o.troops / o.max
		low_morale += 1.0 if o.morale < 60 else 0.0
	hurt /= mine.size()
	var support := true
	var wide := false
	for comp in u.ult.eff:
		if comp.t != "ally":
			support = false
		if comp.has("tgt") and comp.tgt in ["all", "front3", "denseLine"] or str(comp.get("tgt", "")).begins_with("line:"):
			wide = true
	if support:
		return hurt > 0.3 or low_morale >= mine.size() * 0.4      # 아군이 꺾였을 때 아껴 둔 회복·격려
	if wide:
		return foes.size() >= 4                                    # 적이 아직 많을 때 광역기
	return true                                                    # 단일 대상은 바로


func _pick_cmd(cp: String) -> String:
	var mine := units.filter(func(o): return o.alive and o.camp == cp)
	var foes := units.filter(func(o): return o.alive and o.camp != cp)
	if mine.is_empty() or foes.is_empty():
		return ""
	var morale := 0.0
	var phys := 0
	for o in mine:
		morale += o.morale
		if DB.PHYS_TAGS.has(o.c.tag):
			phys += 1
	morale /= mine.size()
	var foe_melee := 0
	for o in foes:
		if o.c.tag in ["창병", "기병", "도적"]:
			foe_melee += 1
	var foe_int := foes.size() - foe_melee
	if morale < 55:
		return "재정비"                     # 사기가 꺾였으면 무너지기 전에 추스른다
	if foe_melee * 3 >= foes.size() * 2:
		return "방진"                       # 근접이 몰려오면 버틴다
	if foe_int * 3 >= foes.size() * 2 and morale < 80:
		return "재정비"                     # 책략으로 사기를 깎는 상대
	return "돌격"
