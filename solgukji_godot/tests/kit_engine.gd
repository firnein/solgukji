extends Node
## 11/27 장수 키트 Q · W · E · R · P —— 전투 엔진 점검 (scripts/kit.gd · Battle.mk_unit · _kit_unit · _kit_tag · _targets)
## 실행: godot --headless --path . res://tests/kit_engine.tscn
##  1) 특기 배제 —— 키트 장수의 DB.passives_of 는 고유 특기 하나와 그 이름의 단체 효과만. Kit.enabled 를 끄면 예전 그대로 (캐시가 따라온다)
##  2) 강화 사본 —— Kit.apply_skill · apply_ult · p_apply 가 강화마다 의도대로, 원본(DB.C · 고유기 원본)은 그대로
##  3) 전투 준비 —— 정책의 kit 이 유닛 사본에 반영되고(준비만 시키는 화면 길 _setup 포함) 상대 진영 · 카드 사전에 새지 않는다
##  4) 전투 —— 화공 → 그 장수가 건 화상 · 확산 → 기술 한 번에 맞는 부대 수 · 연마 → 기술 횟수 · 각성 → 고유 특기 수치
##  5) 사건 —— 기술 slot q/w/e · 고유기 slot r · 고유 특기 알림(fx passive) slot p 하나씩 · 개성 말풍선 slot p, 키트 장수가 아니면 붙지 않는다
##  6) 결정성 —— 같은 씨앗이면 같은 사건 (강화 없음 · 있음), Kit.enabled 를 끄면 kit 정책이 아무것도 바꾸지 않는다
## (11/27 강화 방식이 '목록에서 골라 쌓기'에서 '칸마다 장수 고유 효과'로 바뀔 예정 —— 2) 의 강화별 사본 점검과 4) 의 강화별 전투 차이는 지금 강화 표(Kit.AUG)
##  기준이라 표가 바뀌면 그 두 묶음은 새 효과로 다시 쓴다. 1) · 3) 의 길(정책 → 유닛 사본 · 진영 분리) · 5) · 6) 은 새 방식에서도 그대로 쓴다)
const Kit := preload("res://scripts/kit.gd")

var fails := 0


func ok(cond: bool, what: String) -> void:
	if not cond:
		fails += 1
	print("%s · %s" % ["통과" if cond else "실패", what])


func _ready() -> void:
	PlayLog.enabled = false
	get_tree().create_timer(1500.0).timeout.connect(func(): get_tree().quit(1))
	Kit.enabled = true
	var myths: Array = DB.C.keys().filter(func(k): return Kit.on(k))
	myths.sort()
	ok(myths.size() == 11, "키트 장수 11명 (지금 %d)" % myths.size())
	_check_passives(myths)
	_check_copies(myths)
	_check_setup()
	_check_battle()
	_check_events()
	_check_determinism()
	print("장수 키트 엔진 점검 —— 실패 %d" % fails)
	get_tree().quit(1 if fails > 0 else 0)


# ───────── 1) 특기 배제 ─────────

func _check_passives(myths: Array) -> void:
	var bad := []
	var no_p := []
	for k in myths:
		var ps = DB.passives_of(k)
		var pn: String = Kit.p_name(k)
		if pn == "":
			no_p.append(k)
			continue
		if ps == null or ps.traits.size() > 1 or ps.groups.size() > 1 or ps.traits.any(func(t): return t.name != pn) or ps.groups.any(func(g): return g.name != pn):
			bad.append(k)
	ok(no_p.is_empty(), "키트 장수마다 고유 특기가 있다 %s" % str(no_p))
	ok(bad.is_empty(), "켬 —— 키트 장수의 특기는 고유 특기 하나 + 같은 이름의 단체 효과뿐 %s" % str(bad))
	var keep := JSON.stringify(DB.passives_of("c177"))
	var seven: Array = DB.by_tier(7).filter(func(k): return not DB.is_foe(k) and not DB.is_kiin(k))
	seven.sort()
	var keep7 := JSON.stringify(DB.passives_of(seven[0]))
	Kit.enabled = false
	var off = DB.passives_of("c177")
	ok(off != null and off.traits.size() > 1, "끔 —— 관우의 일반 특기가 돌아온다 (특기 %d개 · 캐시가 따라온다)" % (off.traits.size() if off != null else 0))
	ok(not Kit.on("c177"), "끔 —— 키트 장수가 없다")
	ok(JSON.stringify(DB.passives_of(seven[0])) == keep7, "키트 장수가 아닌 카드(불멸)는 켬 · 끔이 같다")
	Kit.enabled = true
	ok(JSON.stringify(DB.passives_of("c177")) == keep, "다시 켬 —— 고유 특기만 (캐시가 따라온다)")
	Kit.min_tier = 9
	ok(DB.passives_of("c177").traits.size() > 1, "min_tier 를 올리면 신화도 예전 그대로")
	Kit.min_tier = 8
	ok(JSON.stringify(DB.passives_of("c177")) == keep, "min_tier 되돌림")


# ───────── 2) 강화 사본 ─────────

func _check_copies(_myths: Array) -> void:
	var c0 := JSON.stringify(DB.C["c177"])
	var q: Dictionary = DB.C["c177"].sks[0]      # 참장돌파 —— front3 · 처형 · 사기
	var b := Kit.base_sk
	var s := Kit.apply_skill(q, [])
	ok(is_equal_approx(s.eff.mult, q.eff.mult * b) and not is_same(s, q) and not is_same(s.eff, q.eff), "강화 없음 —— 바탕 배율만 든 사본 (×%s)" % str(b))
	s = Kit.apply_skill(q, ["dmg"])
	ok(is_equal_approx(s.eff.mult, q.eff.mult * b * Kit.DMG_SK), "강격 —— 기술 피해 ×%s" % str(Kit.DMG_SK))
	s = Kit.apply_skill(q, ["wide"])
	ok(s.eff.tgt == "all" and s.eff.tgt0 == "front3", "확산 —— front3 → all, 원래 범위는 tgt0")
	s = Kit.apply_skill(DB.C["c177"].sks[2], ["wide"])
	ok(s.eff.tgt == "front3" and s.eff.tgt0 == "front1", "확산 —— front1 → front3")
	s = Kit.apply_skill(q, ["fire"])
	ok(s.eff.has("status") and s.eff.status.k == "burn" and not s.eff.has("status2"), "화공 —— 상태이상이 없는 기술에는 status 로 화상")
	var zj: Dictionary = DB.C["c192"].sks[0]      # 장각 황건봉기 —— 혼란
	s = Kit.apply_skill(zj, ["fire"])
	ok(s.eff.status.k == "confuse" and s.eff.has("status2") and s.eff.status2.k == "burn", "화공 —— 이미 혼란이 있는 기술에는 status2 로 화상")
	var zy: Dictionary = DB.C["c195"].sks[0]      # 주유 적진방화 —— 화상
	s = Kit.apply_skill(zy, ["fire"])
	ok(is_equal_approx(s.eff.status.val, zy.eff.status.val * 1.5) and not s.eff.has("status2"), "화공 —— 이미 화상인 기술은 화상 세기 ×1.5")
	s = Kit.apply_skill(q, ["slow"])
	ok(s.eff.has("spd") and is_equal_approx(s.eff.spd.amt, Kit.SLOW.amt), "둔화 —— 맞은 적 속도 %s" % str(Kit.SLOW.amt))
	var gn: Dictionary = DB.C["c197"].sks[0]      # 감녕 수적약탈 —— 이미 속도 깎기
	s = Kit.apply_skill(gn, ["slow"])
	ok(s.eff.spd.amt < gn.eff.spd.amt, "둔화 —— 이미 속도를 깎는 기술은 더 깎는다 (%s → %s)" % [str(gn.eff.spd.amt), str(snappedf(s.eff.spd.amt, 0.01))])
	s = Kit.apply_skill(q, ["awe"])
	ok(is_equal_approx(s.eff.morale, q.eff.morale + Kit.AWE_SK), "위압 —— 기술 사기 피해 +%s" % str(Kit.AWE_SK))
	s = Kit.apply_skill(q, ["quick"])
	ok(is_equal_approx(s.cost, q.cost * Kit.QUICK_SK), "연마 —— 충전 비용 ×%s" % str(Kit.QUICK_SK))
	var lb: Dictionary = DB.C["c190"].sks[0]      # 유비 백성구휼 —— 치료 · 아군 방어
	s = Kit.apply_skill(lb, ["cheer"])
	var bs := Kit.base_sup
	ok(is_equal_approx(s.eff.tHeal, lb.eff.tHeal * bs * Kit.CHEER_SK) and is_equal_approx(s.eff.allyBuff.amt, lb.eff.allyBuff.amt * bs * Kit.CHEER_SK), "고무 —— 치료 · 아군 강화 ×%s" % str(Kit.CHEER_SK))
	s = Kit.apply_skill(lb, [])
	ok(is_equal_approx(s.eff.tHeal, lb.eff.tHeal * bs) and is_equal_approx(s.eff.allyBuff.amt, lb.eff.allyBuff.amt * bs) and int(s.eff.allyBuff.dur) == int(lb.eff.allyBuff.dur), "강화 없음 —— 아군 회복 · 강화에 바탕 배율 (×%s, 지속은 그대로)" % str(bs))
	s = Kit.apply_skill(q, ["dmg", "wide", "fire"])
	ok(is_equal_approx(s.eff.mult, q.eff.mult * b * Kit.DMG_SK) and s.eff.tgt == "all" and s.eff.status.k == "burn", "강화 셋이 함께 든다")
	ok(JSON.stringify(DB.C["c177"]) == c0, "카드 사전(DB.C)은 그대로")
	# 고유기
	var u0: Dictionary = DB.ult_of("c177")      # 청룡언월참 —— front3 타격
	var u0s := JSON.stringify(u0)
	var bu := Kit.base_ult
	var x := Kit.apply_ult(u0, ["dmg"])
	ok(is_equal_approx(x.eff[0].mult, u0.eff[0].mult * bu * Kit.DMG_ULT), "고유기 강격 —— 타격 ×%s" % str(Kit.DMG_ULT))
	x = Kit.apply_ult(u0, ["wide"])
	ok(x.eff[0].tgt == "all" and x.eff[0].tgt0 == "front3", "고유기 확산 —— front3 → all, 원래 범위는 tgt0")
	x = Kit.apply_ult(u0, ["fire"])
	ok(x.eff[0].has("status") and x.eff[0].status.k == "burn", "고유기 화공 —— 타격에 화상")
	var gu: Dictionary = DB.ult_of("c197")      # 감녕 백기겁영 —— 혼란
	x = Kit.apply_ult(gu, ["fire"])
	ok(x.eff[0].status.k == "confuse" and x.eff[0].status2.k == "burn", "고유기 화공 —— 혼란이 있는 타격에는 status2")
	x = Kit.apply_ult(u0, ["awe"])
	ok(x.eff.size() == u0.eff.size() + 1 and x.eff[-1].t == "foe" and is_equal_approx(x.eff[-1].morale, Kit.AWE_ULT), "고유기 위압 —— 적 사기 효과가 하나 더")
	x = Kit.apply_ult(u0, ["quick"])
	ok(is_equal_approx(x.wait, u0.wait * Kit.QUICK_ULT), "고유기 연마 —— 대기 ×%s" % str(Kit.QUICK_ULT))
	var lu: Dictionary = DB.ult_of("c190")      # 유비 인덕의 기치 —— 아군 회복 · 강화
	x = Kit.apply_ult(lu, ["cheer"])
	ok(is_equal_approx(x.eff[0].heal, lu.eff[0].heal * bs * Kit.CHEER_ULT) and is_equal_approx(x.eff[0].buff.amt, lu.eff[0].buff.amt * bs * Kit.CHEER_ULT) and int(x.eff[0].buff.dur) == int(lu.eff[0].buff.dur) + 1, "고유기 고무 —— 회복 · 강화 ×%s, 지속 +1" % str(Kit.CHEER_ULT))
	x = Kit.apply_ult(lu, [])
	ok(is_equal_approx(x.eff[0].heal, lu.eff[0].heal * bs) and is_equal_approx(x.eff[0].morale, lu.eff[0].morale * bs) and int(x.eff[0].buff.dur) == int(lu.eff[0].buff.dur), "고유기 강화 없음 —— 아군 효과에 바탕 배율 (×%s)" % str(bs))
	ok(JSON.stringify(u0) == u0s, "고유기 원본은 그대로")
	# 고유 특기
	ok(is_equal_approx(Kit.p_scale(["amp", "amp"]), 1.0 + 2 * Kit.P_AMP) and is_equal_approx(Kit.p_mul(["amp"]), Kit.base_p * (1.0 + Kit.P_AMP)), "각성 —— 한 번에 +%d%%" % roundi(Kit.P_AMP * 100))
	ok(Kit.p_scales("crit") and Kit.p_scales("amp_low") and not Kit.p_scales("drown") and not Kit.p_scales("seek_low") and not Kit.p_scales("chain") and not Kit.p_scales("kindle"),
		"각성이 곱하는 키 —— 수치(치명 · 꺾인 적 피해)는 곱하고 깃발 · 행동 키(익수 · 표적 · 연격 · 화선)는 그대로")
	var pm: Dictionary = Kit.p_apply({"crit": 0.04, "drown": 1.0, "seek_low": 0.5, "amp_low": 0.3}, ["amp"])
	var px := Kit.p_mul(["amp"])
	ok(is_equal_approx(pm.crit, 0.04 * px) and is_equal_approx(pm.amp_low, 0.3 * px) and is_equal_approx(pm.drown, 1.0) and is_equal_approx(pm.seek_low, 0.5), "p_apply —— 전투와 같은 값의 사본")
	# 검증 —— 넘치는 수 · 모르는 강화 · 붙일 수 없는 칸
	var cl := Kit.clean({"c177": {"q": ["dmg", "dmg", "fire", "wide", "slow"], "p": ["amp", "amp", "amp", "amp"], "r": ["slow", "nope"], "z": ["dmg"]}, "c001": {"q": ["dmg"]}})
	ok(cl.get("c177", {}).get("q", []) == ["dmg", "fire", "wide"] and cl.c177.p == ["amp", "amp", "amp"] and not cl.c177.has("r") and not cl.c177.has("z") and cl.size() == 1, "Kit.clean —— 겹침 · 넘침 · 못 붙이는 강화 · 키트 장수가 아닌 카드는 버린다")


# ───────── 덱 · 전투 ─────────

## 불멸 여덟 + 신화 한 장 (자동 배치). skip 번째부터 고른다 —— 같은 인물은 한 번만
func _deck(myth: String, skip: int) -> Array:
	var pool: Array = DB.by_tier(7).filter(func(k): return not DB.is_foe(k) and not DB.is_kiin(k) and DB.C[k].kind != "retired" and DB.person(k) != DB.person(myth))
	pool.sort()
	var ids := [myth]
	var seen := {DB.person(myth): true}
	var i := skip
	while ids.size() < 9:
		var k: String = pool[i % pool.size()]
		i += 3
		if seen.has(DB.person(k)):
			continue
		seen[DB.person(k)] = true
		ids.append(k)
	return DB.auto_place(ids, "eorin")


func _pol(kit_a: Dictionary, kit_b := {}) -> Dictionary:
	var p := {"A": "smart", "B": "smart"}
	if not kit_a.is_empty() or not kit_b.is_empty():
		p["kit"] = {"A": kit_a, "B": kit_b}
	return p


func _prep(a: Array, b: Array, pol: Dictionary, seed_v := 7) -> RtBattle:
	var bt := RtBattle.new(seed_v)
	bt._setup(a, "eorin", 100, null, b, "eorin", 100, null, "", "", [], pol)      # 준비만 (BattleView.start_stats 와 같은 길)
	return bt


func _run(a: Array, b: Array, pol: Dictionary, seed_v: int) -> Array:
	var bt := RtBattle.new(seed_v)
	var r: Dictionary = bt.run(a, "eorin", 100, null, b, "eorin", 100, null, "", "", [], pol)
	var keys := {}      # 카드 id -> 진영별 부대 키
	for u in bt.units:
		keys[u.camp + ":" + u.c.id] = u.key
	bt.units.clear()
	return [r, keys]


func _unit(bt: RtBattle, camp: String, cid: String):
	for u in bt.units:
		if u.camp == camp and u.c.id == cid:
			return u
	return null


# ───────── 3) 전투 준비 ─────────

func _check_setup() -> void:
	var a := _deck("c177", 0)
	var b := _deck("c177", 1)      # 같은 신화가 양 진영에
	var c0 := JSON.stringify(DB.C["c177"])
	var ps0 := JSON.stringify(DB.passives_of("c177"))
	var kit := {"c177": {"q": ["dmg", "wide"], "w": ["fire"], "r": ["dmg", "quick"], "p": ["amp", "amp"]}}
	var base := _prep(a, b, _pol({}))
	var bt := _prep(a, b, _pol(kit))
	var ua = _unit(bt, "A", "c177")
	var ub = _unit(bt, "B", "c177")
	var u0 = _unit(base, "A", "c177")
	var src: Dictionary = DB.C["c177"]
	ok(ua.kit != null and ua.kit.q == ["dmg", "wide"] and ua.kit.e == [] and ub.kit != null and ub.kit.q == [], "유닛에 칸별 강화가 실린다 (강화가 없는 쪽은 빈 배열)")
	ok(is_equal_approx(ua.c.sks[0].eff.mult, src.sks[0].eff.mult * Kit.base_sk * Kit.DMG_SK) and ua.c.sks[0].eff.tgt == "all" and ua.c.sks[1].eff.has("status"), "A 관우 —— 기술에 강화가 들었다")
	ok(is_equal_approx(ub.c.sks[0].eff.mult, src.sks[0].eff.mult * Kit.base_sk) and ub.c.sks[0].eff.tgt == "front3" and not ub.c.sks[1].eff.has("status"), "B 관우 —— 같은 카드라도 강화가 새지 않는다")
	ok(is_equal_approx(ua.ult.eff[0].mult, u0.ult.eff[0].mult * Kit.DMG_ULT) and is_equal_approx(ua.ult.wait, u0.ult.wait * Kit.QUICK_ULT) and is_equal_approx(ub.ult.eff[0].mult, u0.ult.eff[0].mult), "고유기 —— A 만 강화")
	ok(ua.temper == u0.temper, "기질은 강화와 무관")
	var x := Kit.p_mul(["amp", "amp"]) / Kit.p_mul([])
	ok(is_equal_approx(ua.m.amp_low, u0.m.amp_low * x) and is_equal_approx(ua.m.seek_low, u0.m.seek_low) and is_equal_approx(ua.m.drown, u0.m.drown), "각성 —— 고유 특기 수치 ×%s (깃발 · 표적 키는 그대로)" % str(snappedf(x, 0.01)))
	ok(is_equal_approx(ub.m.amp_low, u0.m.amp_low), "B 관우의 고유 특기는 그대로")
	# 단체 효과 —— 무성: 아군 전원 공격 · 방어. A 진영의 다른 부대가 받은 몫이 커진다
	var ally_a = null
	var ally_0 = null
	for u in bt.units:
		if u.camp == "A" and u.c.id != "c177" and ally_a == null:
			ally_a = u
	for u in base.units:
		if u.camp == "A" and ally_a != null and u.key == ally_a.key:
			ally_0 = u
	ok(ally_a != null and ally_0 != null and float(ally_a.m.get("atk", 0.0)) > float(ally_0.m.get("atk", 0.0)), "각성 —— 단체 효과(아군 공격)도 커진다 (%s → %s)" % [str(snappedf(float(ally_0.m.get("atk", 0.0)), 0.001)), str(snappedf(float(ally_a.m.get("atk", 0.0)), 0.001))])
	ok(JSON.stringify(DB.C["c177"]) == c0 and JSON.stringify(DB.passives_of("c177")) == ps0, "준비 뒤에도 카드 사전 · 특기 캐시는 그대로")
	ok(not bt.policy.has("kit"), "정책 사전에는 kit 이 남지 않는다 (떼어 낸다)")
	var seven = null
	for u in bt.units:
		if u.kit == null and seven == null:
			seven = u
	ok(seven != null and is_same(seven.c, DB.C[seven.c.id]), "키트 장수가 아닌 부대는 카드 원본을 그대로 쓴다")
	# 화공이 status2 로 붙는 기술 —— 장각 황건봉기
	var bz := _prep(_deck("c192", 0), b, _pol({"c192": {"q": ["fire"]}}))
	var uz = _unit(bz, "A", "c192")
	ok(uz.c.sks[0].eff.status.k == "confuse" and uz.c.sks[0].eff.has("status2") and uz.c.sks[0].eff.status2.k == "burn", "장각 Q 화공 —— 전투 사본에 status2")
	# 유비 「인의」 —— 일반 특기 「분발」이 빠져도 인의의 주인이 분발을 일으킨다 (Battle.mk_unit)
	var bl := _prep(_deck("c190", 0), b, _pol({}))
	var ul = _unit(bl, "A", "c190")
	ok(float(ul.m.get("moved_phalanx", 0.0)) > 0.0 and float(ul.m.get("moved", 0.0)) > 0.0, "유비 인의 —— 일반 특기 분발 없이도 분발이 켜진다")
	for x2 in [base, bt, bz, bl]:
		x2.units.clear()


# ───────── 4) 전투에서 실제 차이 ─────────

## 그 부대의 사건을 훑는다 —— {sk: {칸: 횟수}, tg: {칸: [기술 한 번에 맞은 부대 수 …]}, burn: 그 부대가 건 화상 수, ult: 고유기 수}
func _scan(r: Dictionary, key: String) -> Dictionary:
	var out := {"sk": {}, "tg": {}, "burn": 0, "ult": 0}
	var cur_ai := -1
	var cur_slot := ""
	var hit := {}
	for e in r.ev:
		var fx := str(e.get("fx", ""))
		if fx == "skill" and str(e.get("a", "")) == key and e.has("slot"):
			if cur_slot != "":
				out.tg[cur_slot].append(hit.size())
			cur_ai = int(e.get("ai", -1))
			cur_slot = str(e.slot)
			hit = {}
			out.sk[cur_slot] = int(out.sk.get(cur_slot, 0)) + 1
			if not out.tg.has(cur_slot):
				out.tg[cur_slot] = []
		elif cur_slot != "" and int(e.get("ai", -1)) != cur_ai:
			out.tg[cur_slot].append(hit.size())
			cur_slot = ""
		elif cur_slot != "" and fx in ["phys", "int"] and str(e.get("a", "")) == key:
			hit[str(e.get("f", ""))] = true
		if fx == "status" and str(e.get("st", "")) == "burn" and str(e.get("from", "")) == key:
			out.burn += 1
		if fx == "ult" and str(e.get("a", "")) == key:
			out.ult += 1
	if cur_slot != "":
		out.tg[cur_slot].append(hit.size())
	return out


func _sum(x: Array) -> float:
	var s := 0.0
	for v in x:
		s += float(v)
	return s


func _check_battle() -> void:
	var a := _deck("c177", 0)
	var b := _deck("c182", 2)
	var seeds := [11, 23, 37, 41, 59, 67]
	var n0 := {"burn": 0, "tg": [], "w": 0, "all": 0}
	var nf := {"burn": 0}
	var nw := {"tg": []}
	var nq := {"w": 0, "all": 0}
	for sd in seeds:
		var r0: Array = _run(a, b, _pol({}), sd)
		var k: String = r0[1]["A:c177"]
		var s0 := _scan(r0[0], k)
		n0.burn += int(s0.burn)
		n0.w += int(s0.sk.get("w", 0))
		n0.all += int(s0.sk.get("q", 0)) + int(s0.sk.get("w", 0)) + int(s0.sk.get("e", 0))
		n0.tg.append_array(s0.tg.get("w", []))
		var rf: Array = _run(a, b, _pol({"c177": {"q": ["fire"], "w": ["fire"], "e": ["fire"]}}), sd)
		nf.burn += int(_scan(rf[0], k).burn)
		var rw: Array = _run(a, b, _pol({"c177": {"w": ["wide"]}}), sd)
		nw.tg.append_array(_scan(rw[0], k).tg.get("w", []))
		var rq: Array = _run(a, b, _pol({"c177": {"w": ["quick"]}}), sd)
		var sq := _scan(rq[0], k)
		nq.w += int(sq.sk.get("w", 0))
		nq.all += int(sq.sk.get("q", 0)) + int(sq.sk.get("w", 0)) + int(sq.sk.get("e", 0))
	ok(nf.burn > n0.burn, "화공 —— 관우가 건 화상 %d → %d (여섯 판)" % [n0.burn, nf.burn])
	var t0: float = _sum(n0.tg) / maxf(1.0, n0.tg.size())
	var t1: float = _sum(nw.tg) / maxf(1.0, nw.tg.size())
	ok(n0.tg.size() > 0 and nw.tg.size() > 0 and t1 > t0, "확산 —— 관우 W(횡소천군) 한 번에 맞는 부대 %.2f → %.2f (%d · %d번)" % [t0, t1, n0.tg.size(), nw.tg.size()])
	# 연마 —— 관우는 기술 셋이 차례마다 하나씩 거의 쉬지 않고 나가(한 차례에 기술 하나) 전체 횟수는 늘 수 없다: 연마한 칸의 몫이 는다
	var sh0: float = n0.w / maxf(1.0, n0.all)
	var sh1: float = nq.w / maxf(1.0, nq.all)
	ok(sh1 > sh0, "연마 —— 관우 W 의 기술 몫 %d/%d → %d/%d (%.0f%% → %.0f%%)" % [n0.w, n0.all, nq.w, nq.all, sh0 * 100, sh1 * 100])
	# 기술이 비싸 차례가 남는 장수(사마의 2.4 · 2.4 · 1.9)는 전체 횟수가 는다
	var a2 := _deck("L50", 0)
	var c0 := 0
	var c1 := 0
	var l0 := 0.0
	var l1 := 0.0
	for sd in seeds:
		var x0: Array = _run(a2, b, _pol({}), sd)
		var k2: String = x0[1]["A:L50"]
		var y0 := _scan(x0[0], k2)
		c0 += int(y0.sk.get("q", 0)) + int(y0.sk.get("w", 0)) + int(y0.sk.get("e", 0))
		l0 += float(x0[0].len)
		var x1: Array = _run(a2, b, _pol({"L50": {"q": ["quick"], "w": ["quick"], "e": ["quick"]}}), sd)
		var y1 := _scan(x1[0], k2)
		c1 += int(y1.sk.get("q", 0)) + int(y1.sk.get("w", 0)) + int(y1.sk.get("e", 0))
		l1 += float(x1[0].len)
	ok(c1 / maxf(1.0, l1) > c0 / maxf(1.0, l0), "연마 —— 사마의 기술 횟수 %d → %d (초당 %.3f → %.3f)" % [c0, c1, c0 / maxf(1.0, l0), c1 / maxf(1.0, l1)])
	# 강격 —— 같은 씨앗 첫 Q 타격이 같은 표적에 더 크게 (갈라지기 전)
	var bigger := 0
	var cmp := 0
	for sd in seeds:
		var d0 := _first_hit(_run(a, b, _pol({}), sd), "A:c177")
		var d1 := _first_hit(_run(a, b, _pol({"c177": {"q": ["dmg"], "w": ["dmg"], "e": ["dmg"]}}), sd), "A:c177")
		if d0.is_empty() or d1.is_empty() or d0[0] != d1[0]:
			continue
		cmp += 1
		if float(d1[1]) > float(d0[1]) * 1.15:
			bigger += 1
	ok(cmp > 0 and bigger == cmp, "강격 —— 첫 기술 타격이 같은 표적에 더 크다 (%d/%d판)" % [bigger, cmp])
	# 상대 진영에 새지 않는다 —— B 장료의 기술 · 고유기만 강화하면 A 관우의 준비 수치는 그대로 (위 _check_setup 은 같은 카드, 여기는 다른 카드)
	var p0 := _prep(a, b, _pol({}))
	var p1 := _prep(a, b, _pol({}, {"c182": {"q": ["dmg"], "r": ["dmg", "wide"]}}))
	var ka = _unit(p0, "A", "c177")
	var kb = _unit(p1, "A", "c177")
	ok(JSON.stringify(ka.c.sks) == JSON.stringify(kb.c.sks) and JSON.stringify(ka.m) == JSON.stringify(kb.m) and JSON.stringify(ka.ult) == JSON.stringify(kb.ult), "B 의 기술 · 고유기만 강화하면 A 키트 장수는 그대로")
	# 적에게 거는 단체 효과(장료 위진 —— 적 시작 사기 −)는 각성으로 세진다: A 부대가 받는 몫이 커진다 (이건 새는 것이 아니라 고유 특기의 효과)
	var p2 := _prep(a, b, _pol({}, {"c182": {"p": ["amp", "amp"]}}))
	var kc = _unit(p2, "A", "c177")
	ok(float(kc.m.get("foe_morale", 0.0)) > float(ka.m.get("foe_morale", 0.0)) and float(ka.m.get("foe_morale", 0.0)) > 0.0 and JSON.stringify(ka.c.sks) == JSON.stringify(kc.c.sks),
		"B 장료 각성 —— 적(A)에게 거는 단체 효과가 커진다 (적 시작 사기 −%s → −%s)" % [str(snappedf(float(ka.m.get("foe_morale", 0.0)), 0.1)), str(snappedf(float(kc.m.get("foe_morale", 0.0)), 0.1))])
	p0.units.clear()
	p1.units.clear()
	p2.units.clear()


## 그 부대의 첫 기술(slot 이 붙은 것) 직후 첫 타격 [표적 키, 병력 손실] (없으면 빈 배열)
func _first_hit(res: Array, who: String) -> Array:
	var key: String = res[1][who]
	var on := false
	for e in res[0].ev:
		var fx := str(e.get("fx", ""))
		if fx == "skill" and str(e.get("a", "")) == key and e.has("slot"):
			on = true
		elif on and fx in ["phys", "int"] and str(e.get("a", "")) == key:
			return [str(e.get("f", "")), float(e.get("n", 0.0))]
	return []


# ───────── 5) 사건 ─────────

func _check_events() -> void:
	var a := _deck("c192", 0)      # 장각 —— 단체 효과가 있는 고유 특기 · 개성 말풍선(황천)
	var b := _deck("c181", 2)      # 여포 —— 단체 효과가 없는 고유 특기
	var kit_a := {"c192": {"q": ["fire"], "e": ["wide", "dmg"], "r": ["dmg"], "p": ["amp"]}}
	var res: Array = _run(a, b, _pol(kit_a), 101)
	var r: Dictionary = res[0]
	var ka: String = res[1]["A:c192"]
	var kb: String = res[1]["B:c181"]
	var names := {}
	for i in 3:
		names[str(DB.C["c192"].sks[i].n)] = Kit.SLOTS[i]
	var bnames := {}
	for i in 3:
		bnames[str(DB.C["c181"].sks[i].n)] = Kit.SLOTS[i]
	var sk_ok := 0
	var sk_bad := 0
	var ult_ok := 0
	var ult_bad := 0
	var p_note := {}
	var say_p := 0
	var say_bad := 0
	var stray := 0
	for e in r.ev:
		var fx := str(e.get("fx", ""))
		var who := str(e.get("a", e.get("f", "")))
		var mine := who == ka or who == kb
		if e.has("slot") and not mine:
			stray += 1
		if fx == "skill" and mine:
			var want: String = (names if who == ka else bnames).get(str(e.get("name", "")), "")
			if want == "":
				if e.has("slot"):
					sk_bad += 1      # 카드 기술이 아닌 사건(패업 · 특기)에 칸이 붙었다
				continue
			var augs: Array = kit_a.c192.get(want, []) if who == ka else []
			if str(e.get("slot", "")) == want and e.get("augs") == augs:
				sk_ok += 1
			else:
				sk_bad += 1
		elif fx in ["ult", "ult_warn", "ult_join"] and mine:
			var augs: Array = kit_a.c192.r if who == ka else []
			if str(e.get("slot", "")) == "r" and e.get("augs") == augs:
				ult_ok += 1
			else:
				ult_bad += 1
		elif fx == "passive" and e.has("slot"):
			p_note[who] = int(p_note.get(who, 0)) + 1
			if str(e.slot) != "p" or (who == ka and e.get("augs") != ["amp"]) or (who == kb and e.get("augs") != []):
				sk_bad += 1
		elif fx == "buff" and bool(e.get("sig", false)) and not e.has("escape"):
			if mine and str(e.get("slot", "")) == "p":
				say_p += 1
			elif mine:
				say_bad += 1
	ok(sk_ok > 0 and sk_bad == 0, "기술 사건 —— 칸 q/w/e 와 강화가 맞다 (%d건 · 어긋남 %d)" % [sk_ok, sk_bad])
	ok(ult_ok > 0 and ult_bad == 0, "고유기 사건(ult · ult_warn · ult_join) —— 칸 r 과 강화 (%d건 · 어긋남 %d)" % [ult_ok, ult_bad])
	ok(int(p_note.get(ka, 0)) == 1 and int(p_note.get(kb, 0)) == 1 and p_note.size() == 2, "고유 특기 알림(fx passive · slot p) —— 키트 장수마다 한 번 (단체 효과가 없는 여포도) %s" % str(p_note))
	ok(say_bad == 0, "키트 장수의 개성 말풍선에는 slot p (%d건 · 빠진 것 %d)" % [say_p, say_bad])
	ok(stray == 0, "키트 장수가 아닌 부대의 사건에는 slot 이 없다 (%d)" % stray)
	var rk := {}
	for u in r.roster:
		if u.has("kit"):
			rk[u.key] = u.kit
	ok(rk.size() == 2 and rk.get(ka, {}).get("e", []) == ["wide", "dmg"] and rk.get(kb, {}).get("q", ["x"]) == [], "결과 roster 의 키트 장수 줄에 칸별 강화")
	# 화공 status2 —— 장각 Q(혼란 + 화상): 장각이 건 화상이 Q 직후에 난다
	var q_burn := 0
	var cur := -1
	for e in r.ev:
		if str(e.get("fx", "")) == "skill" and str(e.get("a", "")) == ka and str(e.get("slot", "")) == "q":
			cur = int(e.get("ai", -1))
		elif cur >= 0 and int(e.get("ai", -1)) == cur and str(e.get("fx", "")) == "status" and str(e.get("st", "")) == "burn" and str(e.get("from", "")) == ka:
			q_burn += 1
	ok(q_burn > 0, "status2 —— 장각 Q(혼란 기술)에 붙인 화공이 화상을 건다 (%d번)" % q_burn)


# ───────── 6) 결정성 ─────────

func _fp(r: Dictionary) -> int:
	var h := 0
	for e in r.ev:
		h = hash([h, e.get("t"), e.get("fx"), e.get("a"), e.get("f"), e.get("n"), e.get("m"), e.get("slot"), e.get("augs")])
	for u in r.roster:
		h = hash([h, u.key, u.left, u.dmg, u.taken, u.alive])
	return h


func _check_determinism() -> void:
	var a := _deck("c187", 0)
	var b := _deck("c194", 1)
	var kit := {"c187": {"q": ["dmg", "fire", "slow"], "w": ["awe"], "r": ["dmg", "wide", "fire"], "p": ["amp", "amp", "amp"]}}
	var same0 := true
	var same1 := true
	var differs := 0
	for sd in [3, 5, 8]:
		var x: Dictionary = _run(a, b, _pol({}), sd)[0]
		var y: Dictionary = _run(a, b, _pol({}), sd)[0]
		same0 = same0 and _fp(x) == _fp(y) and x.ev.size() == y.ev.size()
		var p: Dictionary = _run(a, b, _pol(kit), sd)[0]
		var q: Dictionary = _run(a, b, _pol(kit), sd)[0]
		same1 = same1 and _fp(p) == _fp(q)
		if _fp(p) != _fp(x):
			differs += 1
	ok(same0, "강화 없는 키트 전투 —— 같은 씨앗이면 같은 사건")
	ok(same1, "강화가 든 전투 —— 같은 씨앗이면 같은 사건")
	ok(differs == 3, "강화는 실제로 전투를 바꾼다 (%d/3판)" % differs)
	Kit.enabled = false
	var off_same := true
	var no_slot := true
	for sd in [3, 5]:
		var x: Dictionary = _run(a, b, _pol({}), sd)[0]
		var y: Dictionary = _run(a, b, _pol(kit), sd)[0]
		off_same = off_same and _fp(x) == _fp(y)
		for e in y.ev:
			if e.has("slot"):
				no_slot = false
		for u in y.roster:
			if u.has("kit"):
				no_slot = false
	Kit.enabled = true
	ok(off_same, "Kit.enabled 를 끄면 kit 정책이 있어도 결과가 같다 (예전 그대로)")
	ok(no_slot, "Kit.enabled 를 끄면 사건 · roster 에 칸 표시가 없다")
