extends Node
## 11/26 기인 값어치 점검 —— 실제 온라인 대전 기록의 덱 쌍으로 "기인 한 장"의 값을 잰다 (측정 전용, 기록은 읽기만). 결과 정리: docs/기인_값어치_1126.md · 집계 tests/kiin_value.py
## 입력: 기록 정리본 JSON (tests/counter_check 와 같은 형식)
## 실행:
##   godot --headless --path . res://tests/kiin_value.tscn -- --mode=dump --out=C:/.../kiin_db.json
##       카드 표 (id · 이름 · 등급 · 종류 · 병종 · 병력 · 공격 · 방어 · PV · 기본패 환산값 · 조합 재료 · 인연 · 기인 기능 키) + 기인 몸 배율을 바꿨을 때의 능력치
##   godot --headless --path . res://tests/kiin_value.tscn -- --mode=sim --in=C:/.../real_battles.json [--seeds=2] [--vars=base,role,slot,body] [--part=1 --parts=3] --out=C:/.../x.jsonl
##       기인이 한 장이라도 든 판만. 판 · 시드마다 변형 한 판씩 —— 한 줄씩 jsonl (w: 그 쪽 승 1 · 무 0.5 · 패 0 · mg: 그 쪽 남은 병력 몫 차 -1~1)
##   godot --headless --path . res://tests/kiin_value.tscn -- --mode=ins --in=... [--min=5.0] [--seeds=1] --out=...
##       보조 측정 —— 기인 또는 초월이 든 쪽의 그 칸(같은 값 76 자리)에 기인 22명을 차례로 바꿔 넣는다. --lv=0,2 (0 효과 켬 · 1 기능만 끔 · 2 위세까지 끔)
##   godot --headless --path . res://tests/kiin_value.tscn [-- --games=20 --base=5]
##       (예전 방식, 참고용) 같은 무작위 base 등급 8장에 기인 1장을 넣은 덱 대 그 자리에 base 등급 무작위 1장을 넣은 덱 —— 실제 덱이 아니라 무작위 덱이다
## 변형 (sim):
##   base            지금 그대로 (부대 기록 ros · 기인이 연 연쇄 수 포함)
##   r_fc            그 쪽만 기인 연쇄 덤 끔 —— 마무리 ×1.0 · 합동 상한 보통(Battle.inyeon_cap_mul). 먼저 터지는 것은 그대로
##   r_off           r_fc + 먼저 터지지도 않는다 (RtBattle.yeon_kiin_first_off) —— 연쇄 역할 전부 끔
##   r_fin15         그 쪽만 마무리 ×1.5        r_fin15cap22  마무리 ×1.5 · 상한 ×2.2        r_fin20  마무리 ×2.0 · 상한 ×2.5
##   r_all13 · r_all15 (--vars 에 role2)  기인이 연 연쇄에 든 장수 모두 ×1.3 / 모두 ×1.5 · 상한 ×2.5 —— 구조를 바꾼 안의 시험
##   fx1 / fx2       그 칸 기인의 기능만 끔 / 위세까지 끔 (Battle.kiin_fx_off) —— 몸 · 고유기 · 특기 · 연쇄 역할은 그대로
##   unL1            그 칸을 조합 재료의 전설 한 장으로 (남는 재료는 버림 —— 아래쪽 기준)
##   unL2            재료 전설 두 장을 깐다 (한 장은 그 칸, 한 장은 덱에서 가장 약한 전설 미만 카드 자리) —— 기인 값이 전설 2장(56)이라면
##   unAll           재료 전부(전설 2 · 희귀 2)를 깐다 —— "안 합치고 그대로 뒀다면" (같은 값 76)
##   imm / up        그 칸을 불멸 / 초월로 (인물이 안 겹치는 것 가운데 돌아가며 --nimm · --nup 장)
##   b80 · b80s90 · b100   기인 몸 배율(병력 · 능력치) 0.8·0.85 / 0.8·0.9 / 1.0·1.0 —— 양쪽 기인 모두 (DB.set_branch)
var idx := {}
var sw
var BT
var f: FileAccess
var imms := []
var ups := []
var kiins := []


func _ready() -> void:
	PlayLog.enabled = false
	var a := {}
	for s in OS.get_cmdline_user_args():
		var kv := s.trim_prefix("--").split("=", true, 1)
		a[kv[0]] = kv[1] if kv.size() > 1 else "1"
	for k in DB.C:
		if DB.is_foe(k):
			continue
		var c: Dictionary = DB.C[k]
		var key := JSON.stringify([c.name, int(c.tier), c.tag])
		if not idx.has(key) or DB.C[idx[key]].kind == "retired":
			idx[key] = k
		if c.kind == "retired":
			continue
		if DB.is_kiin(k):
			kiins.append(k)
		elif int(c.tier) == 7:
			imms.append(k)
		elif int(c.tier) == 6:
			ups.append(k)
	imms.sort()
	ups.sort()
	kiins.sort()
	var mode := str(a.get("mode", "sim" if a.has("in") else "rand"))
	if mode == "rand":
		_rand(int(a.get("games", "20")), int(a.get("base", "5")))
		get_tree().quit(0)
		return
	if mode == "dump":
		_dump(str(a.get("out", "user://kiin_db.json")))
		get_tree().quit(0)
		return
	sw = load("res://tests/real_myth_swap.gd").new()
	sw.idx = idx
	BT = load("res://tests/kiin_bt.gd")
	var rows: Array = JSON.parse_string(FileAccess.get_file_as_string(str(a.get("in", ""))))
	f = FileAccess.open(str(a.get("out", "user://kiin_value.jsonl")), FileAccess.WRITE)
	var part := int(a.get("part", "1"))
	var parts := int(a.get("parts", "1"))
	var seeds := int(a.get("seeds", "1"))
	var n := 0
	if mode == "sim":
		n = _sim(rows, part, parts, seeds, Array(str(a.get("vars", "base,role,slot,body")).split(",")), int(a.get("nimm", "6")), int(a.get("nup", "4")))
	else:
		n = _ins(rows, part, parts, seeds, float(a.get("min", "5.0")), int(a.get("nimm", "4")), Array(str(a.get("lv", "0,2")).split(",")).map(func(x): return int(x)))
	f.close()
	sw.free()
	print("ZGL_KIIN 끝 mode=%s part=%d/%d 판 %d" % [mode, part, parts, n])
	get_tree().quit(0)


# ───────── 공통 ─────────

func _plan(b: Dictionary) -> Dictionary:
	if not (b.me_plan as Array).is_empty() or not (b.foe_plan as Array).is_empty():
		return {"A": {"p": b.me_plan, "own": b.me_own, "perm": []}, "B": {"p": b.foe_plan, "own": [], "perm": []}}
	return {}


func _kslots(S: Dictionary) -> Array:
	var out := []
	for i in S.cards.size():
		if S.cards[i] != null and DB.is_kiin(S.cards[i]):
			out.append(i)
	return out


## 한 판 —— {aw: A 승 1 · 무 0.5 · 패 0, mg: A 쪽 남은 병력 몫 차, r: 결과, st: stats}
func _go(sd: int, A: Dictionary, B: Dictionary, plan: Dictionary, role := {}) -> Dictionary:
	var bt = BT.new(sd)
	bt.role = role
	var r: Dictionary = sw._run_bt(bt, A, B, plan, false)
	var hp := {"A": 0.0, "B": 0.0}
	var cn := {"A": 0, "B": 0}
	for u in r.roster:
		if not hp.has(u.camp):
			continue
		cn[u.camp] += 1
		if u.alive:
			hp[u.camp] += clampf(float(u.left) / maxf(1.0, float(u.max)), 0.0, 1.0)
	var st: Dictionary = bt.stats.duplicate()
	bt.units.clear()
	return {"aw": 0.5 if bool(r.draw) else (1.0 if bool(r.win) else 0.0), "mg": hp.A / maxf(1.0, cn.A) - hp.B / maxf(1.0, cn.B), "r": r, "st": st}


func _row(base: Dictionary, cp: String, v: String, g: Dictionary, more := {}) -> void:
	var o := base.duplicate()
	o["side"] = cp
	o["v"] = v
	o["w"] = g.aw if cp == "A" else 1.0 - g.aw
	o["mg"] = snappedf(g.mg if cp == "A" else -g.mg, 0.001)
	for k in more:
		o[k] = more[k]
	f.store_line(JSON.stringify(o))


## 그 쪽(cp)만 S2 로 바꿔 한 판
func _go_side(sd: int, me: Dictionary, foe: Dictionary, plan: Dictionary, cp: String, S2: Dictionary, role := {}) -> Dictionary:
	return _go(sd, S2 if cp == "A" else me, foe if cp == "A" else S2, plan, role)


## 칸의 카드를 바꾼다 (원래 카드의 전용 장비는 뺀다 —— tests/real_myth_swap 과 같다)
func _put(S: Dictionary, slot: int, k: String) -> void:
	var orig = S.cards[slot]
	S.cards[slot] = k
	if orig != null and str(DB.C[orig].get("need", "")) != "" and S.equip[slot] is Array:
		var inn = DB.ITEM_BY_NAME.get(DB.C[orig].need)
		S.equip[slot] = (S.equip[slot] as Array).filter(func(x): return x != inn)


func _persons(S: Dictionary, skip: int) -> Dictionary:
	var o := {}
	for i in S.cards.size():
		if i != skip and S.cards[i] != null:
			o[DB.person(S.cards[i])] = true
	return o


## 기인을 조합 재료로 되돌려 깐다 —— 재료 가운데 가장 센 전설이 그 칸, 나머지는 덱에서 가장 약한(등급 → PV) "재료보다 등급이 낮은" 카드 자리.
## nleg: 깔 전설 수 (1 · 2) · rares: 희귀도 깐다. 돌려주는 값: {S: 바뀐 쪽, put: 실제로 깐 장 수} (재료가 없으면 빈 사전)
func _unfuse(S: Dictionary, slot: int, nleg: int, rares: bool) -> Dictionary:
	var k: String = S.cards[slot]
	var mats: Array = (DB.RECOF.get(k, []) as Array).filter(func(q): return DB.C.has(str(q))).map(func(q): return str(q))
	mats.sort_custom(func(x, y):
		if DB.C[x].tier != DB.C[y].tier:
			return DB.C[x].tier > DB.C[y].tier
		return DB.C[x].pv > DB.C[y].pv)
	var S2: Dictionary = S.duplicate(true)
	var per := _persons(S, slot)
	var put := 0
	var legs := 0
	var first := true
	for q in mats:
		var t := int(DB.C[q].tier)
		if t >= 5 and legs >= nleg:
			continue
		if t < 5 and not rares:
			continue
		if per.has(DB.person(q)):
			continue
		if first:
			_put(S2, slot, q)
			first = false
		else:
			var at := -1
			for i in S2.cards.size():
				var c = S2.cards[i]
				if c == null or i == slot or DB.is_kiin(c) or int(DB.C[c].tier) >= t:
					continue
				if at < 0 or int(DB.C[c].tier) < int(DB.C[S2.cards[at]].tier) or (int(DB.C[c].tier) == int(DB.C[S2.cards[at]].tier) and DB.C[c].pv < DB.C[S2.cards[at]].pv):
					at = i
			if at < 0:
				continue
			per.erase(DB.person(S2.cards[at]))
			_put(S2, at, q)
		per[DB.person(q)] = true
		put += 1
		if t >= 5:
			legs += 1
	if first:
		return {}
	return {"S": S2, "put": put}


func _pick(pool: Array, per: Dictionary, start: int, n: int) -> Array:
	var ok: Array = pool.filter(func(k): return not per.has(DB.person(k)))
	var out := []
	for i in mini(n, ok.size()):
		out.append(ok[(start + i) % ok.size()])
	return out


## 기인 몸 배율(병력 · 능력치) 변형 —— 이름 → 기인 카드별 능력치. 처음 한 번 계산해 두고(_prep_bodies) 판마다 기인 카드 값만 갈아 끼운다(_body).
## DB.set_branch 를 그냥 다시 부르면 불멸 평균이 카드별 배율(card_adjust)을 먹은 값으로 잡혀 처음과 어긋난다 —— 배율을 걷어 내고 부른 뒤 다시 곱한다.
## 기인이 아닌 카드는 처음 값을 그대로 되돌려 한 비트도 달라지지 않는다.
const SK := ["tr", "pv", "atk", "int", "def", "res"]
const BK := ["atk", "int", "def", "res"]
var _bodies := {}


func _snap(ids: Array) -> Dictionary:
	var o := {}
	for k in ids:
		var c := {}
		for s in SK:
			c[s] = DB.C[k][s]
		var b := {}
		if DB._BASE.has(k):
			for s in BK:
				b[s] = DB._BASE[k][s]
		o[k] = {"c": c, "b": b}
	return o


func _load(sn: Dictionary) -> void:
	for k in sn:
		for s in sn[k].c:
			DB.C[k][s] = sn[k].c[s]
		for s in sn[k].b:
			DB._BASE[k][s] = sn[k].b[s]


func _prep_bodies(defs: Dictionary) -> void:
	var all0 := _snap(DB.C.keys())
	var on0: Dictionary = DB._card_adj_on.duplicate()
	var tr0: Dictionary = DB._card_adj_tr.duplicate()
	var adj: Dictionary = DB.CARD_ADJ
	_bodies["base"] = _snap(kiins)
	for bn in defs:
		DB.CARD_ADJ = {}
		DB.apply_card_adjust()
		DB.set_branch(DB.BRANCH_TR, DB.BRANCH_ST, defs[bn][0], defs[bn][1])
		DB.CARD_ADJ = adj
		DB.apply_card_adjust()
		_bodies[bn] = _snap(kiins)
		DB.CARD_ADJ = {}
		DB.apply_card_adjust()
		DB.set_branch(DB.BRANCH_TR, DB.BRANCH_ST)
		DB.CARD_ADJ = adj
		_load(all0)
		DB._card_adj_on = on0.duplicate()
		DB._card_adj_tr = tr0.duplicate()
	DB._psv_cache.clear()


func _body(bn: String) -> void:
	_load(_bodies[bn])


# ───────── sim ─────────

func _sim(rows: Array, part: int, parts: int, seeds: int, vars: Array, nimm: int, nup: int) -> int:
	var kk := 0
	var done := 0
	var bodies := {"b80": [0.8, 0.85], "b80s90": [0.8, 0.9], "b100": [1.0, 1.0]}
	if vars.has("body"):
		_prep_bodies(bodies)
	var roles := {"r_fc": [1.0, Battle.inyeon_cap_mul, false], "r_off": [1.0, Battle.inyeon_cap_mul, true], "r_fin15": [1.5, RtBattle.yeon_kiin_cap_mul, false],
		"r_fin15cap22": [1.5, 2.2, false], "r_fin20": [2.0, 2.5, false]}
	if not vars.has("role"):
		roles = {}
	if vars.has("role2"):      # 구조를 바꾼 안 —— 기인이 연 연쇄에 든 장수 모두의 고유기 피해 배율 (tests/kiin_bt 의 all)
		roles["r_all13"] = [1.3, RtBattle.yeon_kiin_cap_mul, false, 1.3]
		roles["r_all15"] = [1.5, 2.5, false, 1.5]
	for bi in rows.size():
		var b: Dictionary = rows[bi]
		var me: Dictionary = sw._side(b.me)
		var foe: Dictionary = sw._side(b.foe)
		if me.is_empty() or foe.is_empty():
			continue
		var ks := {"A": _kslots(me), "B": _kslots(foe)}
		if ks.A.is_empty() and ks.B.is_empty():
			continue
		kk += 1
		if kk % parts != part - 1:
			continue
		done += 1
		var plan := _plan(b)
		for si in seeds:
			var sd := int(b.seed) + si * 7919
			var base := {"bi": bi, "day": int(b.day), "s": si, "nk": [ks.A.size(), ks.B.size()]}
			if vars.has("base"):
				var g := _go(sd, me, foe, plan)
				var key_cp := {}
				var kkey := {}
				var ros := []
				for u in g.r.roster:
					key_cp[str(u.key)] = u.camp
					if DB.C.has(u.id) and DB.is_kiin(u.id):
						kkey[str(u.key)] = true
					if u.camp in ["A", "B"]:
						ros.append([u.camp, u.id, int(u.dmg) - int(u.over), int(u.taken), int(u.kills), 1 if u.alive else 0, int(u.max), int(u.slot)])
				var ch := {"A": [0, 0, 0, 0, 0], "B": [0, 0, 0, 0, 0]}      # 진영별 [연쇄 수 · 기인이 연 연쇄 · 기인 마무리 · 고유기(미니 제외) · 기인 고유기]
				for e in g.r.ev:
					if e.get("fx") != "ult" or e.get("mini", false):
						continue
					var cp0: String = key_cp.get(str(e.a), "")
					if not ch.has(cp0):
						continue
					ch[cp0][3] += 1
					if kkey.has(str(e.a)):
						ch[cp0][4] += 1
					if e.has("mates"):
						ch[cp0][0] += 1
						if e.get("open", "") == "kiin":
							ch[cp0][1] += 1
					if e.get("finish", false):
						ch[cp0][2] += 1
				for cp in ["A", "B"]:
					_row(base, cp, "base", g, {"ros": ros, "ch": ch[cp], "rec": (1.0 if bool(b.win) else 0.0) if not bool(b.draw) else 0.5} if cp == "A" else {"ch": ch[cp]})
			if vars.has("body"):
				for bn in bodies:
					_body(bn)
					var g := _go(sd, me, foe, plan)
					for cp in ["A", "B"]:
						_row(base, cp, bn, g)
				_body("base")
			for cp in ["A", "B"]:
				if ks[cp].is_empty():
					continue
				var S: Dictionary = me if cp == "A" else foe
				if not roles.is_empty():
					for rn in roles:
						var rr: Array = roles[rn]
						RtBattle.yeon_kiin_first_off = cp if rr[2] else ""
						var g := _go(sd, me, foe, plan, {cp: {"fin": rr[0], "cap": rr[1], "all": rr[3] if rr.size() > 3 else 1.0}})
						RtBattle.yeon_kiin_first_off = ""
						_row(base, cp, rn, g)
				if not vars.has("slot"):
					continue
				for slot in ks[cp]:
					var k: String = S.cards[slot]
					var more := {"slot": slot, "k": k}
					for lv in [1, 2]:
						Battle.kiin_fx_off = {cp + ":" + str(slot): lv}
						var g := _go(sd, me, foe, plan)
						Battle.kiin_fx_off = {}
						_row(base, cp, "fx%d" % lv, g, more)
					for un in [["unL1", 1, false], ["unL2", 2, false], ["unAll", 2, true]]:
						var u2 := _unfuse(S, slot, un[1], un[2])
						if u2.is_empty():
							continue
						var g := _go_side(sd, me, foe, plan, cp, u2.S)
						_row(base, cp, un[0], g, more.merged({"put": u2.put, "m": u2.S.cards[slot]}))
					var per := _persons(S, slot)
					for pk in [["imm", imms, nimm], ["up", ups, nup]]:
						for m in _pick(pk[1], per, bi * 5 + si * int(pk[2]) + slot, pk[2]):
							var S2: Dictionary = S.duplicate(true)
							_put(S2, slot, m)
							var g := _go_side(sd, me, foe, plan, cp, S2)
							_row(base, cp, pk[0], g, more.merged({"m": m}))
		f.flush()
	return done


# ───────── ins (보조) ─────────

func _ins(rows: Array, part: int, parts: int, seeds: int, mn: float, nimm: int, lvs: Array) -> int:
	var kk := 0
	var done := 0
	for bi in rows.size():
		var b: Dictionary = rows[bi]
		if (_avg(b.me) + _avg(b.foe)) / 2.0 < mn:
			continue
		var me: Dictionary = sw._side(b.me)
		var foe: Dictionary = sw._side(b.foe)
		if me.is_empty() or foe.is_empty():
			continue
		var tg := {"A": _slot76(me), "B": _slot76(foe)}
		if tg.A < 0 and tg.B < 0:
			continue
		kk += 1
		if kk % parts != part - 1:
			continue
		done += 1
		var plan := _plan(b)
		for si in seeds:
			var sd := int(b.seed) + si * 7919
			var base := {"bi": bi, "day": int(b.day), "s": si}
			var g0 := _go(sd, me, foe, plan)
			for cp in ["A", "B"]:
				var slot: int = tg[cp]
				if slot < 0:
					continue
				var S: Dictionary = me if cp == "A" else foe
				var more := {"slot": slot, "k": S.cards[slot]}
				_row(base, cp, "base", g0, more)
				var per := _persons(S, slot)
				for m in kiins:
					if per.has(DB.person(m)):
						continue
					var S2: Dictionary = S.duplicate(true)
					_put(S2, slot, m)
					for lv in lvs:
						if lv == 1 and not (DB.AURA.has(m) and DB.AURA[m].has("kiin")):
							continue      # 기능 키가 없는 기인은 "기능만 끔"이 지금과 같다
						Battle.kiin_fx_off = {cp + ":" + str(slot): lv} if lv > 0 else {}
						var g := _go_side(sd, me, foe, plan, cp, S2)
						Battle.kiin_fx_off = {}
						_row(base, cp, "ins%d" % lv, g, more.merged({"m": m}))
				for m in _pick(imms, per, bi * 5 + si * nimm + slot, nimm):
					var S2: Dictionary = S.duplicate(true)
					_put(S2, slot, m)
					_row(base, cp, "imm", _go_side(sd, me, foe, plan, cp, S2), more.merged({"m": m}))
		f.flush()
	return done


## 같은 값(76) 자리 —— 첫 기인 칸, 없으면 첫 초월 칸 (없으면 -1)
func _slot76(S: Dictionary) -> int:
	var ks := _kslots(S)
	if not ks.is_empty():
		return ks[0]
	for i in S.cards.size():
		if S.cards[i] != null and int(DB.C[S.cards[i]].tier) == 6:
			return i
	return -1


func _avg(s: Dictionary) -> float:
	var t := 0.0
	for c in s.cards:
		t += float(c[1])
	return t / maxf(1.0, float(s.cards.size()))


# ───────── dump ─────────

func _dump(out: String) -> void:
	var cards := {}
	for k in DB.C:
		if DB.is_foe(k) or DB.C[k].kind == "retired":
			continue
		var c: Dictionary = DB.C[k]
		var p := DB.person(k)
		var au: Dictionary = DB.AURA.get(k, {})
		cards[k] = {"name": c.name, "person": p, "tier": int(c.tier), "kind": c.kind, "tag": c.tag, "fac": c.fac, "tr": int(c.tr), "atk": float(c.atk), "def": float(c["def"]), "pv": int(c.pv),
			"cost": Run.base_cost(k), "rec": (DB.RECOF.get(k, []) as Array).map(func(q): return str(q)), "yeon": DB.INYEON_OF.get(p, []), "kiin": str(au.get("kiin", "")), "aura": not au.is_empty(),
			"ult": DB.ULT.list.has(p)}
	var alt := {}
	_prep_bodies({"0.8_0.85": [0.8, 0.85], "0.8_0.9": [0.8, 0.9], "1.0_1.0": [1.0, 1.0], "0.7_0.85": [DB.BRANCH_KIIN_TR, DB.BRANCH_KIIN_ST]})
	for bn in _bodies:
		var o := {}
		for k in kiins:
			var c: Dictionary = _bodies[bn][k].c
			o[k] = [int(c.tr), float(c.atk), float(c["def"]), int(c.pv)]
		alt[bn] = o
	var same := true      # 같은 배율로 다시 셈한 값이 처음과 같은가 · 되돌린 뒤 지금 값이 처음과 같은가 (점검 도구가 기본값을 흘리지 않는지)
	for k in DB.C:
		if not cards.has(k):
			continue
		if int(DB.C[k].tr) != cards[k].tr or float(DB.C[k].atk) != cards[k].atk or float(DB.C[k]["def"]) != cards[k]["def"]:
			same = false
	for k in kiins:
		var c: Dictionary = _bodies["0.7_0.85"][k].c
		if int(c.tr) != cards[k].tr or not is_equal_approx(float(c.atk), cards[k].atk) or not is_equal_approx(float(c["def"]), cards[k]["def"]):
			same = false
	var ff := FileAccess.open(out, FileAccess.WRITE)
	ff.store_string(JSON.stringify({"cards": cards, "alt": alt, "restore_ok": same, "idx": idx, "fin": RtBattle.yeon_kiin_fin_mul, "cap": RtBattle.yeon_kiin_cap_mul, "cap0": Battle.inyeon_cap_mul}))
	ff.close()
	print("ZGL_KIIN dump %s 기인 %d · 초월 %d · 불멸 %d · 몸 되돌림 %s" % [out, kiins.size(), ups.size(), imms.size(), "같음" if same else "다름"])


# ───────── rand (예전 방식 —— 무작위 덱, 참고용) ─────────
const FORMS := ["eorin", "hagik", "bongsi", "anwol", "bangwon", "anhaeng", "chuhaeng", "jangsa"]

func _rand(games: int, base_t: int) -> void:
	var pool: Array = DB.by_tier(base_t).filter(func(k): return not DB.is_kiin(k))
	var out := []
	for k in kiins:
		var rng := RandomNumberGenerator.new()
		rng.seed = 4242
		var w := 0.0
		for g in games:
			var a := []
			for i in 8: a.append(pool[rng.randi() % pool.size()])
			var b := a.duplicate()
			a.append(k)
			b.append(pool[rng.randi() % pool.size()])
			var fm: String = FORMS[rng.randi() % FORMS.size()]
			var sd := rng.randi()
			var r1 := RtBattle.make(sd).run(DB.auto_place(a, fm), fm, 100, null, DB.auto_place(b, fm), fm, 100, null, "", "", [], {"A": "smart", "B": "smart"})
			var r2 := RtBattle.make(sd).run(DB.auto_place(b, fm), fm, 100, null, DB.auto_place(a, fm), fm, 100, null, "", "", [], {"A": "smart", "B": "smart"})
			w += (1.0 if r1.win else (0.5 if r1.draw else 0.0)) + (0.0 if r2.win else (0.5 if r2.draw else 1.0))
		out.append([DB.C[k].name, w / (2.0 * games)])
	out.sort_custom(func(x, y): return x[1] > y[1])
	print("기인 값어치 (등급 %d 덱 · %d판 × 2)" % [base_t, games])
	for o in out:
		print("  %-10s %3d%%" % [o[0], roundi(o[1] * 100)])
