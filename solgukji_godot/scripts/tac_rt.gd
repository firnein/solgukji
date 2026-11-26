extends RefCounted
## 군략 카드 —— 전투 안 처리 (11/15 1차, docs/군략_카드_초안.md)
##
## 전투 시간을 셋으로 나눠(단계 길이 = RtBattle.BATTLE_SEC / 3, 3단계는 끝까지) 단계가 시작될 때마다
##  ① 양쪽 카드를 편다 (연환계는 다음 칸 카드를 끌어온다) → ② 무효 판정(혼란 · 공성계 · 함진영 · 군기 엄정)
##  ③ 상성 → ④ 세기 = 덱 쏠림 × (짐 0.5) × 팔진도 × 연환계 × 계열 강화(창림 · 서량 철기 · 지리 · 수군 …) → ⑤ 효과 부품을 건다.
## 이긴 쪽은 그 단계 공격 +15% 를 더 받는다. 단계 시작마다 사건 하나(fx "tac") —— 화면이 양쪽 카드를 뒤집어 보인다.
## 무작위는 전투 rng 하나(상태 대상 고르기)뿐 —— 같은 입력이면 같은 결과.
##
## 효과 부품 (data/tactics.json fx) —— k 종류 · v 값 · who 내 부대 거르기 · tgt 적 대상 거르기 · from 때린 쪽 거르기
##   단계 동안: atk 주는 피해 · foe_atk 적이 주는 피해 · taken 받는 피해 · def / foe_def 방어 · spd / foe_spd 이동 속도
##             range 사거리 · interval 공격 간격 · reflect 되돌림 · splash 옆 부대 · hit_st 맞히면 상태 · yeon_cut 적 인연 합동 끊기
##             kill_morale 처치마다 사기 · steady 사기 안 깎임 · 패주 안 함
##   바로: morale / foe_morale · heal · st 상태(화상 · 수몰) · gauge 적 대장 고유기 게이지 · self_loss · grain(결과에만)
##   전투 동안(scope battle): amp_fam · morale_floor · burn_amp · block_info · weather
##   상성 규칙: beats · draw_vs · nullify(fams, "*" 전부) · foe_half
##   붙는 말: when "next"(다음 단계) · span 2(다음 단계까지) · if win/lose · dur 초 · terrain forest/river · each(늘 카드: 단계마다)
## who / tgt: "ranged" · "melee" · "front"(앞 열) · "low"(병력 30% 아래) · "leader"(최고 등급) · "leader_nb"(대장 + 이웃) ·
##   "center"(가운데 열) · "flank"(측면 열 · 후열) · [병종 …]

const Tac := preload("res://scripts/tactics.gd")
const NEAR := 160.0

var b                         # RtBattle
var pack := {"A": {}, "B": {}}
var stage := -1
var stage_sec := 0.0
var t0 := 0.0
var rec := []                 # 단계마다 {A: {id, fam, out, x, via}, B: {...}}
var grain := {"A": 0, "B": 0}
var weather := ""
var _by := {"A": {}, "B": {}}       # 지금 걸린 부품 —— 진영 -> 종류 -> [부품]
var _battle := {"A": [], "B": []}   # 전투 동안 부품 (놓인 단계부터)
var _pass := {"A": [], "B": []}     # 늘 카드 · 영구 부품
var _amps := {"A": [], "B": []}     # 계열 강화 {fams, v, id}
var _next := {"A": [], "B": []}     # 다음 단계로 넘길 부품
var _eff := {"A": [], "B": []}      # 단계별 펼친 카드 {id, mul, via}
var _floor := {"A": 0.0, "B": 0.0}
var _steady := {}                   # 유닛 -> 사기 바닥 (부동여산)
var _burn := {"A": 0.0, "B": 0.0}
var _block := {"A": false, "B": false}   # 군기 엄정 —— 상대의 정보 · 심리 카드 무효
var _null_next := {"A": false, "B": false}   # 요술 —— 이 진영의 다음 단계 카드도 무효
var _yeon := {"A": 0.0, "B": 0.0}
var _ext := {"A": false, "B": false}
var _info := {}               # 유닛 -> {col, front, back}
var _leader := {"A": null, "B": null}
var _tags := {"A": [], "B": []}
var _terr := {}


## 짐이 둘 다 비었으면 null —— 전투 처리를 켜지 않는다 (옛 점검 · 계획 없는 전투는 예전과 똑같다)
static func make(battle, tp):
	if not (tp is Dictionary):
		return null
	if Tac.empty_load(tp.get("A")) and Tac.empty_load(tp.get("B")):
		return null
	var t = load("res://scripts/tac_rt.gd").new()
	t._setup(battle, tp)
	return t


func _setup(battle, tp: Dictionary) -> void:
	Tac.data()
	b = battle
	stage_sec = RtBattle.BATTLE_SEC / float(Tac.STAGES)
	for z in b.terrain:
		_terr[str(z.k)] = true
	var rows := {"A": [], "B": []}
	for u in b.units:
		var fm: String = b._meta.aForm if u.camp == "A" else b._meta.bForm
		var sl: Array = DB.FORM[fm].slots
		var s: Dictionary = sl[u.slot] if u.slot < sl.size() else {"row": 0, "col": DB.FORM_MID}
		_info[u] = {"col": int(s.col), "row": int(s.row)}
		rows[u.camp].append(int(s.row))
		_tags[u.camp].append(str(u.c.tag))
		var L = _leader[u.camp]
		if L == null or u.c.tier > L.c.tier or (u.c.tier == L.c.tier and u.max > L.max):
			_leader[u.camp] = u
	for u in b.units:
		var rs: Array = rows[u.camp]
		_info[u]["front"] = int(_info[u].row) == rs.min()
		_info[u]["back"] = int(_info[u].row) == rs.max() and rs.min() != rs.max()
	for cp in ["A", "B"]:
		var pl = tp.get(cp, {})
		pack[cp] = pl if pl is Dictionary else {}
		var p := Tac.norm(pack[cp].get("p", []))
		var e := []
		for i in Tac.STAGES:
			e.append({"id": p[i] if Tac.placeable(p[i]) else "", "mul": 1.0, "via": ""})
		for i in Tac.STAGES - 1:      # 연환계 —— 다음 칸 카드를 이번 칸에도, 두 칸 모두 ×1.5
			if e[i].id != "" and bool(Tac.card(e[i].id).get("link", false)):
				var nx: String = e[i + 1].id
				if nx != "" and not bool(Tac.card(nx).get("link", false)):
					e[i] = {"id": nx, "mul": 1.5, "via": e[i].id}
					e[i + 1].mul = 1.5
				else:
					e[i] = {"id": "", "mul": 1.0, "via": e[i].id}
		if e[Tac.STAGES - 1].id != "" and bool(Tac.card(e[Tac.STAGES - 1].id).get("link", false)):
			e[Tac.STAGES - 1] = {"id": "", "mul": 1.0, "via": e[Tac.STAGES - 1].id}
		_eff[cp] = e
		# 늘 카드 · 영구 부품
		for id in pack[cp].get("own", []):
			var c := Tac.card(str(id))
			if str(c.get("kind", "")) != "passive" or bool(c.get("off", false)):
				continue
			for part in c.fx:
				_add_scope(cp, part, 1.0, str(id), true)
		for part in pack[cp].get("perm", []):
			if part is Dictionary:
				_add_scope(cp, part, 1.0, "", true)


## 전투 동안 걸리는 것 · 늘 카드 —— 강화 · 하한 · 화상 · 인연 같은 깃발은 바로, 나머지는 _pass / _battle 에 쌓는다
func _add_scope(cp: String, part: Dictionary, s: float, id: String, passive: bool) -> void:
	if part.has("terrain") and not _terr.has(str(part.terrain)):
		return
	match str(part.k):
		"amp_fam":
			_amps[cp].append({"fams": part.fams, "v": float(part.v) * s})
		"amp_card":
			_amps[cp].append({"id": str(part.id), "v": float(part.v) * s})
		"morale_floor":
			_floor[cp] = maxf(_floor[cp], float(part.v))
		"burn_amp":
			_burn[cp] += float(part.v) * s
		"block_info":
			_block[cp] = true
		"yeon_amp":
			_yeon[cp] += float(part.v) * s
		"confuse_ext":
			_ext[cp] = true
		"weather":
			_weather(cp)
		_:
			var e := part.duplicate()
			e["c"] = cp
			e["s"] = s
			e["src"] = id
			if passive:
				_pass[cp].append(e)
			else:
				_battle[cp].append(e)


## 천시 —— 원거리 · 책략 부대가 상대보다 많으면 바람(내 화상 +50% · 원거리 공격 +15%), 아니면 비(이 전투 화상 무효)
func _weather(cp: String) -> void:
	var mine: int = _tags[cp].filter(func(t): return t in ["궁병", "책사"]).size()
	var foe: int = _tags[_foe(cp)].filter(func(t): return t in ["궁병", "책사"]).size()
	if mine >= foe:
		weather = "wind"
		_burn[cp] += 0.5
		_battle[cp].append({"k": "atk", "v": 0.15, "who": "ranged", "c": cp, "s": 1.0, "src": "천시"})
	else:
		weather = "rain"


static func _foe(cp: String) -> String:
	return "B" if cp == "A" else "A"


## 매 틱 (시간을 흘린 뒤) —— 단계가 바뀌면 연다
func tick() -> void:
	var k := mini(Tac.STAGES - 1, int(b._tm / stage_sec))
	if k != stage:
		_begin(k)


func _begin(k: int) -> void:
	stage = k
	t0 = b._tm
	var ca: Dictionary = _eff.A[k]
	var cb: Dictionary = _eff.B[k]
	var ida: String = ca.id
	var idb: String = cb.id
	# 군기 엄정은 무효 판정 전에 —— 이번 단계에 놓았어도 상대의 혼란을 바로 막는다
	for cp in ["A", "B"]:
		if _has_part(_eff[cp][k].id, "block_info"):
			_block[cp] = true
	# 무효 —— 혼란(정보 · 심리, 군기 엄정이 막는다) · 공성계 · 함진영 · 요술로 이어진 혼란
	var xa := _nullified("A", ida, idb)
	var xb := _nullified("B", idb, ida)
	var ua := "" if xa else ida
	var ub := "" if xb else idb
	_null_next = {"A": false, "B": false}
	if ub == "혼란" and _ext.B and xa:
		_null_next.A = true
	if ua == "혼란" and _ext.A and xb:
		_null_next.B = true
	# 전투 동안 깃발(동남풍 · 천리행군 강화 · 군령 엄수 · 천시 …) —— 무효가 아닌 카드만, 이번 단계부터
	for cp in ["A", "B"]:
		var id: String = ua if cp == "A" else ub
		if id == "":
			continue
		for part in Tac.card(id).fx:
			if str(part.get("scope", "")) == "battle":
				_add_scope(cp, part, _scale(cp, id, "draw", _eff[cp][k].mul), id, false)
	var oa := Tac.outcome(Tac.fams(ua), Tac.fams(ub), _rules(ua), _rules(ub))
	var ob: String = {"win": "lose", "lose": "win", "draw": "draw"}[oa]
	var outs := {"A": oa, "B": ob}
	var used := {"A": ua, "B": ub}
	# 부동여산 바닥은 바로 효과(위보 · 보급로 차단)보다 먼저 —— 이 단계 동안 사기가 깎이지 않는다
	_steady = {}
	var steady := {"A": _has_part(ua, "steady"), "B": _has_part(ub, "steady")}
	for u in b.units:
		if u.alive and steady[u.camp]:
			_steady[u] = u.morale
	# 이번 단계 부품
	var cur := {"A": [], "B": []}
	for cp in ["A", "B"]:
		var carry: Array = _next[cp]
		_next[cp] = []
		for e in carry:
			_put(cp, e, cur)
		var id: String = used[cp]
		if id != "":
			var s := _scale(cp, id, outs[cp], _eff[cp][k].mul)
			if _has_part(used[_foe(cp)], "foe_half"):
				s *= 0.5
			for part in Tac.card(id).fx:
				if str(part.get("scope", "")) == "battle":
					continue
				if part.has("if") and str(part["if"]) != outs[cp]:
					continue
				if part.has("terrain") and not _terr.has(str(part.terrain)):
					continue
				var e: Dictionary = part.duplicate()
				e["c"] = cp
				e["s"] = s
				e["src"] = id
				if str(part.get("when", "")) == "next":
					e.erase("when")
					e.erase("if")
					_next[cp].append(e)
					continue
				if int(part.get("span", 1)) > 1:
					var e2 := e.duplicate()
					e2.erase("span")
					_next[cp].append(e2)
				_put(cp, e, cur)
		if outs[cp] == "win":
			_put(cp, {"k": "atk", "v": float(Tac.RULE.win_atk), "c": cp, "s": 1.0, "src": "상성"}, cur)
		for e in _pass[cp]:
			if bool(e.get("each", false)):
				if e.has("if") and str(e["if"]) != outs[cp]:
					continue
				_put(cp, e, cur)
	if k == Tac.STAGES - 1:
		_next = {"A": [], "B": []}
	# 지금 걸린 부품 —— 단계 + 전투 동안 + 늘
	_by = {"A": {}, "B": {}}
	for cp in ["A", "B"]:
		for e in cur[cp] + _battle[cp] + _pass[cp].filter(func(x): return not bool(x.get("each", false))):
			var kk := str(e.k)
			if not _by[cp].has(kk):
				_by[cp][kk] = []
			_by[cp][kk].append(e)
	for u in _steady:
		u.morale = maxf(u.morale, _steady[u])
	var ent := {}
	for cp in ["A", "B"]:
		var raw: String = _eff[cp][k].id
		var fs := Tac.fams(used[cp])
		ent[cp] = {"id": raw, "fam": Tac.fam_text(raw), "out": outs[cp], "x": raw != "" and used[cp] == "", "via": str(_eff[cp][k].via)}
		if fs.size() > 1:
			ent[cp]["fam"] = _best_fam(fs, Tac.fams(used[_foe(cp)]))
	rec.append(ent)
	var tx := "%d단계 —— %s 대 %s" % [k + 1, _nm(ent.A), _nm(ent.B)]
	if oa != "draw":
		tx += " · %s 우세" % ("아군" if oa == "win" else "적")
	b.L("tac", tx, {"fx": "tac", "stage": k + 1, "A": ent.A, "B": ent.B})


static func _nm(e: Dictionary) -> String:
	if str(e.id) == "":
		return "없음"
	return "%s%s" % [e.id, " (무효)" if bool(e.x) else ""]


func _best_fam(fs: Array, foe: Array) -> String:
	for f in fs:
		if Tac.outcome([f], foe) == "win":
			return f
	return fs[0]


## 이 카드가 상대 카드에 의해 무효인가
func _nullified(cp: String, mine: String, theirs: String) -> bool:
	if mine == "":
		return false
	if _null_next[cp]:
		return true
	var fo := _foe(cp)
	var mc := Tac.card(mine)
	if str(mc.get("cat", "")) == "info" and _block[fo]:
		return true
	if theirs == "":
		return false
	var tc := Tac.card(theirs)
	if str(tc.get("cat", "")) == "info" and _block[cp]:
		return false      # 상대의 혼란은 내 군기 엄정이 막는다
	for part in tc.fx:
		if str(part.k) == "nullify":
			var fs: Array = part.fams
			if fs.has("*"):
				return true
			for f in Tac.fams(mine):
				if fs.has(f):
					return true
	return false


func _rules(id: String) -> Dictionary:
	var out := {"beats": [], "draw_vs": []}
	if id == "":
		return out
	for part in Tac.card(id).fx:
		if str(part.k) in ["beats", "draw_vs"]:
			out[str(part.k)].append_array(part.fams)
	return out


func _has_part(id: String, k: String) -> bool:
	if id == "":
		return false
	for part in Tac.card(id).fx:
		if str(part.k) == k:
			return true
	return false


## 세기 —— 덱 쏠림 × 상성(짐 0.5) × 연환계 × 계열 강화 · 카드 강화
func _scale(cp: String, id: String, out: String, mul: float) -> float:
	var fs := Tac.fams(id)
	var s := Tac.bias(fs, _tags[cp]) * mul
	if out == "lose":
		s *= float(Tac.RULE.lose_mul)
	for a in _amps[cp]:
		if a.has("id"):
			if str(a.id) == id:
				s *= 1.0 + float(a.v)
			continue
		var af: Array = a.fams
		if af.has("*") or fs.any(func(f): return af.has(f)):
			s *= 1.0 + float(a.v)
	return s


## 부품 하나를 이번 단계에 —— 바로 효과는 지금 하고, 나머지는 cur 에 (dur 이 있으면 끝 시각)
func _put(cp: String, e: Dictionary, cur: Dictionary) -> void:
	var s := float(e.get("s", 1.0))
	var v := float(e.get("v", 0.0)) * s
	match str(e.k):
		"morale":
			for u in _side(cp, e.get("who")):
				u.morale = clampf(u.morale + v, 0.0, 200.0)
		"foe_morale":
			for u in _side(_foe(cp), null):
				u.morale = clampf(u.morale + v, 0.0, 200.0)
		"heal":
			for u in _side(cp, e.get("who")):
				u.troops = minf(u.max, u.troops + u.max * v)
		"self_loss":
			for u in _side(cp, null):
				u.troops = maxf(1.0, u.troops - u.troops * float(e.v))
		"gauge":
			var L = _leader[_foe(cp)]
			if L != null and L.alive:
				L.gauge = maxf(0.0, L.gauge * (1.0 + v))
		"st":
			_status(cp, e, s)
		"grain":
			grain[cp] += roundi(v)
		_:
			var x := e.duplicate()
			x["v"] = v
			x["s"] = 1.0
			if e.has("p"):
				x["p"] = minf(1.0, float(e.p) * s)      # 불화살 —— 확률도 세기만큼
			if e.has("dur"):
				x["t1"] = t0 + float(e.dur)
			cur[cp].append(x)


## 상태 —— 적 부대 무작위 n 곳 (전투 rng). 거는 장수는 내 대장 (없으면 살아 있는 아무나). 진 쪽은 곳 수가 준다
func _status(cp: String, e: Dictionary, s: float) -> void:
	var src = _leader[cp]
	if src == null or not src.alive:
		var al := _side(cp, null)
		if al.is_empty():
			return
		src = al[0]
	var n := int(e.get("n_river", e.n)) if _terr.has("river") else int(e.n)
	n = maxi(1, roundi(n * minf(1.0, s)))
	var pool := _side(_foe(cp), null)
	var kind := str(e.st)
	for i in mini(n, pool.size()):
		var j: int = b.rng.randi() % pool.size()
		var t = pool[j]
		pool.remove_at(j)
		if kind == "burn":
			b.inflict(src, t, "burn", b._fire_burn(src), int(DB.PSV.fire.burn.dur))
		elif kind == "flood":
			b.inflict(src, t, "flood", b._water_flood(src), int(DB.PSV.water.flood.dur))
		else:
			b.inflict(src, t, kind, 1, int(DB.PSV.scheme.dur))


func _side(cp: String, who) -> Array:
	var out := []
	for u in b.units:
		if u.alive and u.camp == cp and _who(who, u):
			out.append(u)
	return out


func _live(e: Dictionary) -> bool:
	return not e.has("t1") or b._tm < float(e.t1)


## 내 부대 거르기
func _who(w, u) -> bool:
	if w == null:
		return true
	if w is Array:
		return (w as Array).has(str(u.c.tag))
	match str(w):
		"all": return true
		"ranged": return b._ranged(u)
		"melee": return not b._ranged(u)
		"front": return bool(_info.get(u, {}).get("front", false))
		"low": return u.troops < u.max * 0.3
		"leader": return u == _leader[u.camp]
		"leader_nb":
			var L = _leader[u.camp]
			return L != null and L.alive and (u == L or u.pos.distance_to(L.pos) <= NEAR)
	return false


## 적 대상 거르기
func _tgt(t, d) -> bool:
	if t == null:
		return true
	match str(t):
		"center": return int(_info.get(d, {}).get("col", -1)) == DB.FORM_MID
		"flank":
			var inf: Dictionary = _info.get(d, {})
			return int(inf.get("col", DB.FORM_MID)) in [0, DB.FORM_COLS - 1] or bool(inf.get("back", false))
	return _who(t, d)


## 때린 쪽 거르기
func _from(f, a, far: bool) -> bool:
	if f == null:
		return true
	if f is Array:
		return (f as Array).has(str(a.c.tag))
	match str(f):
		"ranged": return b._ranged(a)
		"melee": return not b._ranged(a) and not far
	return true


func _list(cp: String, k: String) -> Array:
	return _by[cp].get(k, [])


# ───────── 엔진이 묻는 것 ─────────

## 한 타격의 배율 —— 내 주는 피해 · 적이 걸어 둔 '적 공격 −' · 받는 쪽 받는 피해 · 인연 합동
func hit_mul(a, d, far: bool) -> float:
	if a.camp == d.camp:
		return 1.0
	var m := 1.0
	for e in _list(a.camp, "atk"):
		if _live(e) and _who(e.get("who"), a) and _tgt(e.get("tgt"), d):
			m *= 1.0 + float(e.v)
	for e in _list(d.camp, "foe_atk"):
		if _live(e) and _who(e.get("who"), a):
			m *= 1.0 + float(e.v)
	for e in _list(d.camp, "taken"):
		if _live(e) and _from(e.get("from"), a, far) and _who(e.get("who"), d):
			m *= 1.0 + float(e.v)
	if _yeon[a.camp] > 0.0 and b._in_ult and not b._ult_grp.is_empty():
		m *= 1.0 + _yeon[a.camp]
	return maxf(0.05, m)


func def_mul(u) -> float:
	var m := 1.0
	for e in _list(u.camp, "def"):
		if _live(e) and _who(e.get("who"), u):
			m *= 1.0 + float(e.v)
	for e in _list(_foe(u.camp), "foe_def"):
		if _live(e):
			m *= 1.0 + float(e.v)
	return maxf(0.1, m)


func spd_mul(u) -> float:
	var m := 1.0
	for e in _list(u.camp, "spd"):
		if _live(e) and _who(e.get("who"), u):
			m *= 1.0 + float(e.v)
	for e in _list(_foe(u.camp), "foe_spd"):
		if _live(e):
			m *= 1.0 + float(e.v)
	return maxf(0.0, m)


func range_mul(u) -> float:
	var m := 1.0
	for e in _list(u.camp, "range"):
		if _live(e) and _who(e.get("who"), u):
			m *= 1.0 + float(e.v)
	return m


func int_mul(u) -> float:
	var m := 1.0
	for e in _list(u.camp, "interval"):
		if _live(e) and _who(e.get("who"), u):
			m *= 1.0 + float(e.v)
	return maxf(0.3, m)


## 화상 배율 —— 비면 0 (무효), 동남풍 · 바람이면 거는 쪽 +
func burn_mul(a) -> float:
	if weather == "rain":
		return 0.0
	return 1.0 + (_burn[a.camp] if a != null else 0.0)


## 이 진영의 인연 합동이 끊겼나 (상대의 이간)
func yeon_cut(cp: String) -> bool:
	for e in _list(_foe(cp), "yeon_cut"):
		if _live(e):
			return true
	return false


func no_rout(u) -> bool:
	return _steady.has(u)


## 사기 바닥 —— 군령 엄수(진영) · 부동여산(단계 시작 사기)
func clamp_morale() -> void:
	if _floor.A <= 0.0 and _floor.B <= 0.0 and _steady.is_empty():
		return
	for u in b.units:
		if not u.alive:
			continue
		var f: float = _floor[u.camp]
		if _steady.has(u):
			f = maxf(f, _steady[u])
		if u.morale < f:
			u.morale = f


## 타격 뒤 —— 되돌림 · 화살비 · 불화살. 바로 병력을 깎아 다시 타격을 부르지 않는다
func after_hit(a, d, far: bool, loss: float) -> void:
	if a.camp == d.camp or loss <= 0.0:
		return
	for e in _list(d.camp, "reflect"):
		if _live(e) and a.alive and _from(e.get("from"), a, far):
			_direct(d, a, loss * float(e.v), "되돌림")
	for e in _list(a.camp, "splash"):
		if _live(e) and _who(e.get("who"), a):
			var t = _near_foe(d)
			if t != null:
				_direct(a, t, loss * float(e.v), "화살비")
	for e in _list(a.camp, "hit_st"):
		if _live(e) and _who(e.get("who"), a) and d.alive and b.rng.randf() < float(e.get("p", 1.0)):
			if str(e.st) == "burn":
				b.inflict(a, d, "burn", b._fire_burn(a), int(DB.PSV.fire.burn.dur))
			else:
				b.inflict(a, d, str(e.st), 1, int(DB.PSV.scheme.dur))


func _near_foe(d):
	var best = null
	var bd := 140.0
	for o in b.units:
		if o.alive and o != d and o.camp == d.camp:
			var x: float = o.pos.distance_to(d.pos)
			if x < bd:
				bd = x
				best = o
	return best


func _direct(src, t, amt: float, why: String) -> void:
	amt = roundf(minf(amt, t.troops))
	if amt < 1.0:
		return
	t.troops -= amt
	t.taken += amt
	src.dmg += amt
	t.last_hit = src
	b.L(src.camp, "『%s』 %s — 병력 %s 손실" % [why, b.nm(t), Battle.num(amt)], {"fx": "phys", "a": src.key, "f": t.key, "n": amt, "tac": why})


## 부대가 무너졌다 —— 상벌 분명
func on_fall(u) -> void:
	var k = u.last_hit
	if k == null or k.camp == u.camp:
		return
	for e in _list(k.camp, "kill_morale"):
		if _live(e):
			for o in b.units:
				if o.alive and o.camp == k.camp:
					o.morale = minf(200.0, o.morale + float(e.v))


## 결과에 싣는 것 —— 단계마다 양쪽 카드 · 상성, 진영별 군량(약탈)
func summary() -> Dictionary:
	return {"log": rec, "grain": grain, "weather": weather}
