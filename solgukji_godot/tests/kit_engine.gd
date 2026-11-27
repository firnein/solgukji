extends Node
## 11/27 장수 키트 Q · W · E · R · P —— 전투 엔진 점검 (scripts/kit.gd · kit_rt.gd · data/kit.json · Battle.mk_unit · act · _kit_tag)
## 실행: godot --headless --path . res://tests/kit_engine.tscn [-- --cells=c177:q,c190:r (그 칸만) --verbose --immortal (불멸 키트 스위치를 켜고 불멸 30명 점검) --trans (초월 15명) --kiin (기인 22명)]
##  9) (11/27) 초월 · 기인 키트 스위치 —— 꺼짐(기본): 초월 · 기인은 키트 장수가 아니고 그 전투가 예전(키트 끔)과 같다. --trans · --kiin: 그 등급 75칸 · 110칸 강화가 모두 일한다
##  8) (11/27) 불멸 키트 스위치 —— 꺼짐(기본): 불멸은 키트 장수가 아니고 불멸 전투가 예전(키트 끔)과 같다. --immortal: 신화 21 + 불멸 30, 불멸 150칸 강화가 모두 일한다
##  1) 특기 배제 —— 키트 장수의 DB.passives_of 는 고유 특기 하나와 그 이름의 단체 효과만. Kit.enabled 를 끄면 예전 그대로 (캐시가 따라온다)
##  2) 자료 —— kit.json 21명 × 5칸 (11/27 대현량사 장각 c192 는 토벌 적 전용으로 빠졌고, 같은 날 새 신화 11명이 더해졌다): 이름 · 글 · 강화 이름 · 글 · 엔진 필드(fx), q·w·e 의 cd, new 칸의 sk. 강화 상태 형식(칸 목록 · 장수당 2칸 · 옛 형식 읽기)
##  3) 전투 준비 —— 정책의 kit 이 유닛에 실리고(준비만 시키는 화면 길 _setup 포함) 상대 진영 · 카드 사전에 새지 않는다. 결과의 policy · roster 에 kit
##  4) 재사용 대기 —— 같은 칸 기술은 cd 초 안에 다시 나가지 않는다 (다시 쓰기 · 당김이 없는 편성에서)
##  5) 105칸 (기존 10명 50칸 + 새 11명 55칸) —— 칸마다 강화를 켠 판에서 그 강화가 실제로 일하고(kup 사건 · b.stats["kup:진영:카드:칸"]), 끈 같은 판에서는 일하지 않는다
##  6) 사건 —— 기술 slot q/w/e · 고유기 slot r · 고유 특기 알림 slot p · 강화한 칸이면 up, kup 사건의 이름이 kit.json 과 같다, 옛 augs 필드는 없다
##  7) 결정성 —— 같은 씨앗이면 같은 사건 (강화 없음 · 있음). Kit.enabled 를 끄면 kit 정책이 아무것도 바꾸지 않는다
const Kit := preload("res://scripts/kit.gd")

var fails := 0
var verbose := false


func ok(cond: bool, what: String) -> void:
	if not cond:
		fails += 1
	print("%s · %s" % ["통과" if cond else "실패", what])


func _ready() -> void:
	PlayLog.enabled = false
	get_tree().create_timer(3000.0).timeout.connect(func(): get_tree().quit(1))
	var a := {}
	for s in OS.get_cmdline_user_args():
		var kv := s.trim_prefix("--").split("=", true, 1)
		a[kv[0]] = kv[1] if kv.size() > 1 else "1"
	verbose = a.has("verbose")
	Kit.enabled = true
	Kit.immortal = a.has("immortal")      # 11/27 불멸 키트 스위치 (게임은 Kit.IMMORTAL_ON 상수) —— --immortal 이면 켠 상태로 점검
	Kit.trans = a.has("trans")            # 11/27 초월 · 기인 키트 스위치 (게임은 Kit.TRANS_ON · KIIN_ON 상수)
	Kit.kiin = a.has("kiin")
	Kit.up_any = Kit.immortal or Kit.trans or Kit.kiin      # 11/27 강화는 신화만(Kit.can_up) —— 켠 등급의 강화 엔진 길은 점검에서만 열어 계속 본다
	var myths: Array = DB.C.keys().filter(func(k): return Kit.on(k))
	myths.sort()
	if Kit.trans or Kit.kiin:
		_ready_tk(myths, str(a.get("cells", "")))
		return
	if Kit.immortal:
		_ready_immortal(myths, str(a.get("cells", "")))
		return
	ok(myths.size() == 21, "키트 장수 21명 (지금 %d)" % myths.size())
	if not a.has("cells"):
		_check_immortal_off()
		_check_tk_off()
	if not a.has("cells"):
		_check_passives(myths)
		_check_data(myths)
		_check_setup()
		_check_cooldown()
	_check_cells(myths, str(a.get("cells", "")))
	if not a.has("cells"):
		_check_events()
		_check_determinism()
	print("장수 키트 엔진 점검 —— 실패 %d" % fails)
	get_tree().quit(1 if fails > 0 else 0)


# ───────── 1) 특기 배제 ─────────

func _check_passives(myths: Array) -> void:
	var bad := []
	for k in myths:
		var ps = DB.passives_of(k)
		var pn: String = Kit.p_name(k)
		if pn == "" or ps == null or ps.traits.size() > 1 or ps.groups.size() > 1 or ps.traits.any(func(t): return t.name != pn) or ps.groups.any(func(g): return g.name != pn):
			bad.append(k)
	ok(bad.is_empty(), "켬 —— 키트 장수의 특기는 고유 특기 하나 + 같은 이름의 단체 효과뿐 %s" % str(bad))
	var keep := JSON.stringify(DB.passives_of("c177"))
	Kit.enabled = false
	var off = DB.passives_of("c177")
	ok(off != null and off.traits.size() > 1 and not Kit.on("c177"), "끔 —— 관우의 일반 특기가 돌아온다 (특기 %d개 · 캐시가 따라온다)" % (off.traits.size() if off != null else 0))
	Kit.enabled = true
	ok(JSON.stringify(DB.passives_of("c177")) == keep, "다시 켬 —— 고유 특기만")


# ───────── 2) 자료 ─────────

func _check_data(myths: Array) -> void:
	var bad := []
	var n := 0
	for k in myths:
		var sks: Array = DB.C[k].get("sks", [])
		var mine := Kit.skills_of(k)
		if mine.size() != 3:
			bad.append("%s 기술 %d개" % [k, mine.size()])
		for slot in Kit.SLOTS:
			var c := Kit.cell(k, slot)
			n += 1
			if str(c.get("n", "")) == "" or str(c.get("d", "")) == "" or str(c.get("up", {}).get("n", "")) == "" or str(c.get("up", {}).get("d", "")) == "" or str(c.get("fx", {}).get("k", "")) == "":
				bad.append("%s.%s 글 · fx" % [k, slot])
			var i: int = Kit.SLOTS.find(slot)
			if i < 3:
				if float(c.get("cd", 0.0)) <= 0.0:
					bad.append("%s.%s cd" % [k, slot])
				if bool(c.get("new", false)) != c.has("sk"):
					bad.append("%s.%s new/sk" % [k, slot])
				if not c.has("sk") and (i >= sks.size() or str(sks[i].n) != str(c.n)):
					bad.append("%s.%s 카드 기술 이름" % [k, slot])
				if i < mine.size() and (str(mine[i].n) != str(c.n) or not is_equal_approx(float(mine[i].cd), float(c.cd)) or str(mine[i].slot) != slot):
					bad.append("%s.%s skills_of" % [k, slot])
			elif slot == "r" and str(DB.ult_of(k).name) != str(c.n):
				bad.append("%s.r 고유기 이름" % k)
			elif slot == "p" and Kit.p_name(k) != str(c.n):
				bad.append("%s.p 고유 특기 이름" % k)
	ok(n == myths.size() * 5 and bad.is_empty(), "kit.json %d칸 —— 이름" % n + " · 글 · 강화 · 엔진 필드 · 재사용 대기 · 카드 기술과 이름이 맞는다 %s" % str(bad))
	var c0 := JSON.stringify(DB.C["c177"])
	var q: Dictionary = DB.C["c177"].sks[0]
	var mq: Dictionary = Kit.skills_of("c177")[0]
	ok(is_equal_approx(float(mq.eff.mult), float(q.eff.mult) * Kit.base_sk * float(Kit.cell("c177", "q").get("mul", 1.0))) and JSON.stringify(DB.C["c177"]) == c0, "skills_of —— 바탕 배율이 든 사본 (카드 사전은 그대로)")
	ok(Kit.norm({"c177": ["q", "w", "e"], "c001": ["q"], "c190": ["z", "r", "r"]}) == {"c177": ["q", "w"], "c190": ["r"]}, "Kit.norm —— 장수당 2칸 · 모르는 카드 · 칸 · 겹침은 버린다")
	ok(Kit.norm({"c177": {"q": ["dmg"], "p": ["amp", "amp"], "w": []}}) == {"c177": ["q", "p"]}, "Kit.norm —— 옛 형식(칸 → 강화 목록)은 강화한 칸 목록으로")
	ok(Kit.up_cost({}, "c177") == Kit.UP_COST[0] and Kit.up_cost({"c177": ["q"]}, "c177") == Kit.UP_COST[1] and Kit.up_cost({"c177": ["q", "r"]}, "c177") == -1 and Kit.up_block({"c177": ["q", "r"]}, "c177", "p") != "", "강화 값 · 장수당 두 칸 뒤에는 더 못 한다")


# ───────── 덱 · 전투 ─────────

## 신화 한 장 + tier 등급 여덟 (자동 배치). skip 번째부터 고른다 —— 같은 인물은 한 번만. more: 꼭 넣을 카드들
func _deck(myth: String, skip: int, tier := 7, more := []) -> Array:
	var pool: Array = DB.by_tier(tier).filter(func(k): return not DB.is_foe(k) and not DB.is_kiin(k) and DB.C[k].kind != "retired")
	pool.sort()
	var ids := []
	var seen := {}
	for k in [myth] + more:
		if k != "" and not seen.has(DB.person(k)):
			ids.append(k)
			seen[DB.person(k)] = true
	var i := skip
	var guard := 0
	while ids.size() < 9 and guard < 400:
		guard += 1
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


func _run(a: Array, b: Array, pol: Dictionary, seed_v: int, ma := 100.0, mb := 100.0) -> Array:
	var bt := RtBattle.new(seed_v)
	var r: Dictionary = bt.run(a, "eorin", ma, null, b, "eorin", mb, null, "", "", [], pol)
	var keys := {}      # "진영:카드" -> 부대 키
	for u in bt.units:
		keys[u.camp + ":" + str(u.c.id)] = u.key
	bt.units.clear()
	return [r, keys]


func _unit(bt: RtBattle, camp: String, cid: String):
	for u in bt.units:
		if u.camp == camp and u.c.id == cid:
			return u
	return null


func _fp(r: Dictionary) -> int:
	var h := 0
	for e in r.ev:
		h = hash([h, e.get("t"), e.get("fx"), e.get("a"), e.get("f"), e.get("n"), e.get("m"), e.get("slot"), e.get("up"), e.get("kup")])
	for u in r.roster:
		h = hash([h, u.key, u.left, u.dmg, u.taken, u.alive])
	return h


# ───────── 3) 전투 준비 ─────────

func _check_setup() -> void:
	var a := _deck("c177", 0)
	var b := _deck("c177", 1)      # 같은 신화가 양 진영에
	var c0 := JSON.stringify(DB.C["c177"])
	var ps0 := JSON.stringify(DB.passives_of("c177"))
	var kit := {"c177": ["q", "p", "r"]}      # 셋째 칸은 버려진다 (장수당 2칸)
	var base := RtBattle.new(7)
	base._setup(a, "eorin", 100, null, b, "eorin", 100, null, "", "", [], _pol({}))
	var bt := RtBattle.new(7)
	bt._setup(a, "eorin", 100, null, b, "eorin", 100, null, "", "", [], _pol(kit))      # 준비만 (BattleView.start_stats 와 같은 길)
	var ua = _unit(bt, "A", "c177")
	var ub = _unit(bt, "B", "c177")
	var u0 = _unit(base, "A", "c177")
	ok(ua.kit == ["q", "p"] and ub.kit == [] and u0.kit == [], "유닛에 강화한 칸 목록이 실린다 (A 만 · 장수당 2칸)")
	ok(ua.c.sks.size() == 3 and str(ua.c.sks[0].slot) == "q" and float(ua.c.sks[1].cd) == float(Kit.cell("c177", "w").cd) and JSON.stringify(ua.c.sks) == JSON.stringify(ub.c.sks), "키트 기술(칸 · 재사용 대기)이 실린다 —— 기술 수치는 강화와 무관")
	ok(JSON.stringify(DB.C["c177"]) == c0 and JSON.stringify(DB.passives_of("c177")) == ps0, "준비 뒤에도 카드 사전 · 특기 캐시는 그대로")
	ok(bt.policy.get("kit") == {"A": {"c177": ["q", "p"]}, "B": {}}, "정책에 거른 kit 이 남는다 (결과의 policy 로 화면이 같은 엔진을 준비한다)")
	var seven = null
	for u in bt.units:
		if u.kit == null and seven == null:
			seven = u
	ok(seven != null and is_same(seven.c, DB.C[seven.c.id]), "키트 장수가 아닌 부대는 카드 원본을 그대로 쓴다")
	var bl := RtBattle.new(7)
	bl._setup(_deck("c190", 0), "eorin", 100, null, b, "eorin", 100, null, "", "", [], _pol({}))
	var ul = _unit(bl, "A", "c190")
	ok(float(ul.m.get("moved_phalanx", 0.0)) > 0.0 and float(ul.m.get("moved", 0.0)) > 0.0, "유비 인의 —— 일반 특기 분발 없이도 분발이 켜진다")
	for x in [base, bt, bl]:
		x.units.clear()
	var res: Array = _run(a, b, _pol(kit), 7)
	var r: Dictionary = res[0]
	var rk := {}
	for u in r.roster:
		if u.has("kit"):
			rk[u.key] = u.kit
	ok(r.policy.get("kit") == {"A": {"c177": ["q", "p"]}, "B": {}} and rk.size() == 2 and rk.get(res[1]["A:c177"]) == ["q", "p"] and rk.get(res[1]["B:c177"]) == [], "결과 —— policy.kit · roster 의 키트 장수 줄에 강화한 칸 목록")
	var leak := 0
	for k in r.stats:
		if str(k).begins_with("kup:B:"):
			leak += int(r.stats[k])
	var mine := 0
	for k in r.stats:
		if str(k).begins_with("kup:A:"):
			mine += int(r.stats[k])
	ok(leak == 0, "강화는 상대 진영의 같은 카드에 새지 않는다 (A 발동 %d · B 발동 %d)" % [mine, leak])


# ───────── 4) 재사용 대기 ─────────

func _check_cooldown() -> void:
	var a := _deck("c177", 0)
	var b := _deck("c182", 2)
	var short := 0
	var n := 0
	var per := {"q": 0, "w": 0, "e": 0}
	var secs := 0.0
	var n_old := 0
	var secs_old := 0.0
	for sd in [11, 23, 37]:
		var res: Array = _run(a, b, _pol({}), sd)
		var k: String = res[1]["A:c177"]
		var last := {}
		for e in res[0].ev:
			if str(e.get("fx", "")) == "skill" and str(e.get("a", "")) == k and e.has("slot"):
				var s := str(e.slot)
				per[s] = int(per[s]) + 1
				n += 1
				if last.has(s) and float(e.tm) - float(last[s]) < float(Kit.cell("c177", s).cd) - 0.11:
					short += 1
				last[s] = float(e.tm)
		secs += float(res[0].len)
		Kit.enabled = false
		var old: Array = _run(a, b, _pol({}), sd)
		Kit.enabled = true
		var ko: String = old[1]["A:c177"]
		for e in old[0].ev:
			if str(e.get("fx", "")) == "skill" and str(e.get("a", "")) == ko and DB.C["c177"].sks.any(func(x): return str(x.n) == str(e.get("name", ""))):
				n_old += 1
		secs_old += float(old[0].len)
	ok(n > 0 and short == 0, "관우 —— 같은 칸 기술은 재사용 대기 안에 다시 나가지 않는다 (%d번 · 어긋남 %d · Q %d W %d E %d)" % [n, short, per.q, per.w, per.e])
	ok(n / maxf(1.0, secs) <= n_old / maxf(1.0, secs_old) * 1.05, "관우 기술 발동 간격 (11/27 잽 3~4초 · 결정타 12~14초 —— 예전보다 잦지 않으면 된다) —— 예전(충전) %.1f초에 한 번 → 지금 %.1f초에 한 번" % [secs_old / maxf(1.0, n_old), secs / maxf(1.0, n)])


# ───────── 5) 105칸 ─────────

## 그 칸의 강화가 나올 만한 편성들 —— [A 덱, B 덱, A 사기, B 사기]. 차례로 해 본다
func _scenes(k: String, slot: String) -> Array:
	var foe_std := _deck("c192" if k != "c192" else "c195", 2)                    # 불멸 여덟(모두 고유기) + 상태이상을 거는 신화
	var foe_heal := _deck("c190" if k != "c190" else "c194", 4, 7, ["c195" if k != "c195" else "c192"])      # 씻어 주는 유비 + 불 · 혼란
	var foe_spear := DB.auto_place(_tagged(["창병", "창병", "창병", "기병", "기병", "도적", "궁병", "책사", "유생"], 7, k), "eorin")
	var wash: Array = ["s07", "s11", "E11", "c103"].filter(func(x): return DB.C.has(x))      # 상태이상을 씻는 기술을 가진 카드 (유비 · 장소)
	var foe_wash := DB.auto_place(wash + _tagged(["창병", "창병", "기병", "궁병", "도적"], 7, k), "eorin")
	var out := [
		[_deck(k, 0), foe_std, 100.0, 100.0],
		[_deck(k, 1), foe_heal, 100.0, 100.0],
		[_deck(k, 0, 5), foe_std, 100.0, 100.0],      # 약한 아군 —— 장수가 몰리고 무너진다 (버팀 · 출사표 · 칭병 · 격노 · 되살리기)
		[_deck(k, 2), foe_spear, 100.0, 100.0],       # 창병 · 기병 · 도적이 달라붙는다 (퇴각 · 쌍고검 · 수적의 왕)
		[_deck(k, 0), _deck("", 2, 4), 100.0, 31.0],  # 사기가 낮은 약한 적 (지제)
		[_deck(k, 0, 4), foe_std, 31.0, 100.0],       # 사기가 낮은 약한 아군 (백성)
		[_deck(k, 1), foe_wash, 100.0, 100.0],        # 상태이상을 자꾸 씻는 적 (대현량사)
		[_deck(k, 3, 7, ["c195" if k != "c195" else "c187"]), foe_spear, 100.0, 100.0],      # 아군에 불을 지르는 신화가 함께 (순풍)
		[_deck(k, 0), _deck("", 0, 6), 100.0, 100.0],      # 11/27 한 등급 아래(초월) 적 —— 고유기로 무너뜨리는 판 (여포 난무). 술사 삭제로 7급 풀 · 병종이 바뀌어 위 판들(창병 적 편성)에서 여포가 고유기로 적을 무너뜨리지 못했다
	]
	return out


## 병종 목록대로 그 등급 카드를 하나씩 (인물 겹치지 않게, 이름순 —— 그 등급에 모자라면 아래 등급에서)
func _tagged(tags: Array, tier: int, not_person_of: String) -> Array:
	var pool: Array = []
	for tr in [tier, tier - 1, tier - 2]:
		var one: Array = DB.by_tier(tr).filter(func(k): return not DB.is_foe(k) and not DB.is_kiin(k) and DB.C[k].kind != "retired")
		one.sort()
		pool.append_array(one)
	var seen := {DB.person(not_person_of): true}
	var ids := []
	for t in tags:
		for k in pool:
			if str(DB.C[k].tag) == str(t) and not seen.has(DB.person(k)):
				seen[DB.person(k)] = true
				ids.append(k)
				break
	return ids


func _check_cells(myths: Array, only: String) -> void:
	var want := {}
	for x in only.split(",", false):
		want[x] = true
	var dead := []
	var stray := []
	var runs := 0
	for k in myths:
		for slot in Kit.SLOTS:
			if not want.is_empty() and not want.has("%s:%s" % [k, slot]):
				continue
			var key := "kup:A:%s:%s" % [k, slot]
			var nm := str(Kit.cell(k, slot).up.n)
			var got := 0
			var where := ""
			var scs := _scenes(k, slot)
			for si in scs.size():
				for sd in [5, 17, 29]:
					var sc: Array = scs[si]
					var res: Array = _run(sc[0], sc[1], _pol({k: [slot]}), sd, sc[2], sc[3])
					runs += 1
					var r: Dictionary = res[0]
					var n := int(r.stats.get(key, 0))
					if n <= 0:
						continue
					var evn := 0      # 그 이름의 kup 사건
					for e in r.ev:
						if str(e.get("kup", "")) == nm:
							evn += 1
					var off: Dictionary = _run(sc[0], sc[1], _pol({}), sd, sc[2], sc[3])[0]      # 같은 판 · 강화 끔
					runs += 1
					var off_n := int(off.stats.get(key, 0))
					for e in off.ev:
						if e.has("kup") or (bool(e.get("up", false)) and str(e.get("fx", "")) in ["skill", "ult", "ult_warn", "ult_join", "passive", "kup"]):
							off_n += 1
					if evn <= 0 or off_n > 0:
						stray.append("%s.%s(%s) 사건 %d · 끈 판 %d" % [k, slot, nm, evn, off_n])
					got = n
					where = "편성 %d · 씨앗 %d · 사건 %d" % [si + 1, sd, evn]
					break
				if got > 0:
					break
			if got <= 0:
				dead.append("%s.%s(%s)" % [k, slot, nm])
			elif verbose:
				print("    %s %s 「%s」 %d번 (%s)" % [DB.C[k].name, Kit.SLOT_N[slot], nm, got, where])
	ok(dead.is_empty(), "강화 %d칸 —— 칸마다 그 강화가 실제로 일하는 판이 있다 (전투 %d판) 못 본 칸: %s" % [myths.size() * 5 if want.is_empty() else want.size(), runs, str(dead)])
	ok(stray.is_empty(), "강화가 일하면 그 이름의 kup 사건이 남고, 끈 같은 판에는 없다 %s" % str(stray))


# ───────── 6) 사건 ─────────

func _check_events() -> void:
	var a := _deck("c190", 0)      # 유비 —— 단체 효과가 있는 고유 특기 (11/27 장각 c192 는 키트에서 빠졌다)
	var b := _deck("c181", 2)      # 여포 —— 단체 효과가 없는 고유 특기
	var res: Array = _run(a, b, _pol({"c190": ["e", "r"]}, {"c181": ["q"]}), 101)
	var r: Dictionary = res[0]
	var ka: String = res[1]["A:c190"]
	var kb: String = res[1]["B:c181"]
	var names := {ka: {}, kb: {}}
	var ups := {ka: ["e", "r"], kb: ["q"]}
	for i in 3:
		names[ka][str(Kit.cell("c190", Kit.SLOTS[i]).n)] = Kit.SLOTS[i]
		names[kb][str(Kit.cell("c181", Kit.SLOTS[i]).n)] = Kit.SLOTS[i]
	var upn := {}      # 강화 이름 -> [부대 키, 칸]
	for s in ["e", "r"]:
		upn[str(Kit.cell("c190", s).up.n)] = [ka, s]
	upn[str(Kit.cell("c181", "q").up.n)] = [kb, "q"]
	var sk_ok := 0
	var sk_bad := 0
	var ult_ok := 0
	var ult_bad := 0
	var p_note := {}
	var stray := 0
	var augs := 0
	var kup_ok := 0
	var kup_bad := 0
	for e in r.ev:
		var fx := str(e.get("fx", ""))
		var who := str(e.get("a", e.get("f", "")))
		var mine := who == ka or who == kb
		if e.has("augs"):
			augs += 1
		if e.has("kup"):
			var w = upn.get(str(e.kup))
			if w != null and str(e.get("slot", "")) == str(w[1]) and str(e.get("a", "")) == str(w[0]) and bool(e.get("up", false)):
				kup_ok += 1
			else:
				kup_bad += 1
			continue
		if e.has("slot") and not mine:
			stray += 1
		if fx == "skill" and mine:
			var want: String = names[who].get(str(e.get("name", "")), "")
			if want == "":
				if e.has("slot"):
					sk_bad += 1      # 카드 · 키트 기술이 아닌 사건(패업 · 특기)에 칸이 붙었다
				continue
			if str(e.get("slot", "")) == want and bool(e.get("up", false)) == (ups[who] as Array).has(want):
				sk_ok += 1
			else:
				sk_bad += 1
		elif fx in ["ult", "ult_warn", "ult_join"] and mine:
			if str(e.get("slot", "")) == "r" and bool(e.get("up", false)) == (ups[who] as Array).has("r"):
				ult_ok += 1
			else:
				ult_bad += 1
		elif fx == "passive" and e.has("slot"):
			p_note[who] = int(p_note.get(who, 0)) + 1
			if str(e.slot) != "p" or e.has("up"):
				sk_bad += 1
	ok(sk_ok > 0 and sk_bad == 0, "기술 사건 —— 칸 q/w/e 와 강화 여부(up)가 맞다 (%d건 · 어긋남 %d)" % [sk_ok, sk_bad])
	ok(ult_ok > 0 and ult_bad == 0, "고유기 사건(ult · ult_warn · ult_join) —— 칸 r 과 강화 여부 (%d건 · 어긋남 %d)" % [ult_ok, ult_bad])
	ok(int(p_note.get(ka, 0)) == 1 and int(p_note.get(kb, 0)) == 1 and p_note.size() == 2, "고유 특기 알림(fx passive · slot p) —— 키트 장수마다 한 번 %s" % str(p_note))
	ok(kup_ok > 0 and kup_bad == 0, "kup 사건 —— 강화 이름 · 칸 · 장수가 kit.json 과 맞다 (%d건 · 어긋남 %d)" % [kup_ok, kup_bad])
	ok(stray == 0 and augs == 0, "키트 장수가 아닌 부대의 사건에는 slot 이 없고, 옛 augs 필드는 없다 (%d · %d)" % [stray, augs])


# ───────── 7) 결정성 ─────────

func _check_determinism(ia := "c187", ib := "c194", kit := {"c187": ["e", "r"]}, kitb := {"c194": ["w", "p"]}) -> void:
	var a := _deck(ia, 0)
	var b := _deck(ib, 1)
	var same0 := true
	var same1 := true
	var differs := 0
	for sd in [3, 5, 8]:
		var x: Dictionary = _run(a, b, _pol({}), sd)[0]
		var y: Dictionary = _run(a, b, _pol({}), sd)[0]
		same0 = same0 and _fp(x) == _fp(y) and x.ev.size() == y.ev.size()
		var p: Dictionary = _run(a, b, _pol(kit, kitb), sd)[0]
		var q: Dictionary = _run(a, b, _pol(kit, kitb), sd)[0]
		same1 = same1 and _fp(p) == _fp(q)
		if _fp(p) != _fp(x):
			differs += 1
	ok(same0, "강화 없는 키트 전투 —— 같은 씨앗이면 같은 사건")
	ok(same1, "강화가 든 전투 —— 같은 씨앗이면 같은 사건")
	ok(differs >= 2, "강화는 실제로 전투를 바꾼다 (%d/3판)" % differs)
	Kit.enabled = false
	var off_same := true
	var no_slot := true
	for sd in [3, 5]:
		var x: Dictionary = _run(a, b, _pol({}), sd)[0]
		var y: Dictionary = _run(a, b, _pol(kit, kitb), sd)[0]
		off_same = off_same and _fp(x) == _fp(y)
		for e in y.ev:
			if e.has("slot") or e.has("kup") or (e.has("up") and str(e.get("fx", "")) in ["skill", "ult", "ult_warn", "ult_join", "passive", "kup"]):
				no_slot = false
		for u in y.roster:
			if u.has("kit"):
				no_slot = false
	Kit.enabled = true
	ok(off_same, "Kit.enabled 를 끄면 kit 정책이 있어도 결과가 같다 (예전 그대로)")
	ok(no_slot, "Kit.enabled 를 끄면 사건 · roster 에 칸 표시가 없다")


# ───────── 8) 불멸 키트 스위치 (11/27 —— Kit.IMMORTAL_ON / Kit.immortal) ─────────

## 불멸 30명 (7성 · 적 전용 · 은퇴 제외 · 고유기 있음)
func _immortals() -> Array:
	var out: Array = DB.C.keys().filter(func(k): return int(DB.C[k].tier) == Kit.IMMORTAL_TIER and not DB.is_foe(k) and str(DB.C[k].kind) != "retired" and DB.has_ult(k))
	out.sort()
	return out


## 꺼짐 (게임 기본) —— 불멸은 키트 장수가 아니고, 불멸 칸 자료 · 강화 정책이 아무것도 바꾸지 않는다. 불멸 전투는 키트를 끈 것과 같은 씨앗 → 같은 결과
func _check_immortal_off() -> void:
	var ims := _immortals()
	var data_n := 0
	for k in ims:
		if Kit.data().has(k):
			data_n += 1
	ok(ims.size() == 30 and data_n == 30, "불멸 30명 —— kit.json 에 칸 자료가 있다 (명단 %d · 자료 %d)" % [ims.size(), data_n])
	ok(not Kit.IMMORTAL_ON and not Kit.immortal, "스위치 기본값 꺼짐 (Kit.IMMORTAL_ON = %s)" % str(Kit.IMMORTAL_ON))
	var leak := []
	for k in ims:
		if Kit.on(k) or not Kit.cell(k, "q").is_empty() or not Kit.cell(k, "p").is_empty():
			leak.append(k)
	ok(leak.is_empty() and Kit.norm({"L38": ["q", "r"], "s01": ["w"]}).is_empty(), "꺼짐 —— 불멸은 키트 장수가 아니다 (Kit.on · cell 빈 사전 · 강화 정책은 버려진다) %s" % str(leak))
	var ps0 := JSON.stringify(DB.passives_of("L38"))
	ok((DB.passives_of("L38").traits as Array).size() > 1, "꺼짐 —— 불멸은 일반 특기를 그대로 쓴다")
	Kit.immortal = true
	var ps1 := JSON.stringify(DB.passives_of("L38"))
	Kit.immortal = false
	ok(ps1 != ps0 and JSON.stringify(DB.passives_of("L38")) == ps0, "스위치를 켰다 끄면 특기 캐시가 따라온다 (켬: 고유 특기만 → 끔: 예전 그대로)")
	# 불멸 · 7성만 든 판 (신화 없음) —— 꺼짐이면 키트가 아예 없는 판(Kit.enabled 끔)과 같은 사건, 불멸 강화 정책을 줘도 같다
	var same := true
	var marks := 0
	var n := 0
	for pair in [["L38", "s01"], ["L12", "c169"], ["c156", "L05"]]:
		var a := _deck(pair[0], 0)
		var b := _deck(pair[1], 1)
		for sd in [3, 7]:
			var base: Dictionary = _run(a, b, _pol({}), sd)[0]
			var pol: Dictionary = _run(a, b, _pol({pair[0]: ["q", "r"]}, {pair[1]: ["w", "p"]}), sd)[0]
			Kit.enabled = false
			var old: Dictionary = _run(a, b, _pol({}), sd)[0]
			Kit.enabled = true
			n += 1
			if not (_fp(base) == _fp(old) and _fp(pol) == _fp(old) and base.ev.size() == old.ev.size()):
				same = false
			for e in base.ev + pol.ev:
				if e.has("slot") or e.has("kup"):
					marks += 1
	ok(same and marks == 0, "꺼짐 —— 불멸 전투 %d판: 같은 씨앗이면 예전(키트 끔)과 같은 결과 · 강화 정책도 무시 · 칸 표시 없음 (표시 %d)" % [n, marks])


## 켬 (--immortal) —— 신화 21 + 불멸 30 = 51명이 키트 장수. 불멸의 특기 · 칸 자료 · 칸마다 강화가 실제로 일하는지 · 사건 · 결정성
func _ready_immortal(kits: Array, cells: String) -> void:
	var ims := _immortals()
	ok(kits.size() == 51 and ims.all(func(k): return kits.has(k)), "켬 —— 키트 장수 51명 (신화 21 + 불멸 %d · 지금 %d)" % [ims.size(), kits.size()])
	if cells == "":
		_check_passives(ims)
		_check_data(kits)
		_check_immortal_rules(ims)
	_check_cells(ims, cells)
	if cells == "":
		_check_immortal_events()
		_check_determinism("L12", "c169", {"L12": ["w", "r"]}, {"c169": ["q", "p"]})
	Kit.immortal = false
	print("장수 키트 엔진 점검 (불멸 켬) —— 실패 %d" % fails)
	get_tree().quit(1 if fails > 0 else 0)


## 불멸 칸 규칙 —— 같은 인물의 신화와 기술 이름 · 강화 이름이 겹치지 않는다, 칸마다 vfx, 대기 3~14초, 고유기 · 특기 강화 효과가 엔진에 있다
func _check_immortal_rules(ims: Array) -> void:
	var myth_of := {}
	for k in DB.C.keys():
		if int(DB.C[k].tier) >= 8 and Kit.on(k):
			myth_of[DB.person(k)] = k
	var rt = load("res://scripts/kit_rt.gd").new()
	var bad := []
	var with_myth := 0
	for k in ims:
		var m = myth_of.get(DB.person(k))
		if m != null:
			with_myth += 1
			var taken := {}
			for s in Kit.SLOTS:
				taken[str(Kit.cell(m, s).up.n)] = true
				if s in ["q", "w", "e"]:
					taken[str(Kit.cell(m, s).n)] = true
			for s in Kit.SLOTS:
				if s in ["q", "w", "e"] and taken.has(str(Kit.cell(k, s).n)):
					bad.append("%s.%s 이름이 신화와 같다" % [k, s])
				if taken.has(str(Kit.cell(k, s).up.n)):
					bad.append("%s.%s 강화 이름이 신화와 같다" % [k, s])
		for s in Kit.SLOTS:
			var c := Kit.cell(k, s)
			if s != "p" and (c.get("vfx", []) as Array).is_empty():
				bad.append("%s.%s vfx" % [k, s])
			if s in ["q", "w", "e"] and (float(c.cd) < 3.0 or float(c.cd) > 14.0):
				bad.append("%s.%s 대기 %s" % [k, s, str(c.cd)])
			if s in ["q", "w", "e"] and c.has("sk") and c.sk.eff.has("act") and not rt.has_method("_act_" + str(c.sk.eff.act)):
				bad.append("%s.%s 고유 동작 %s 없음" % [k, s, str(c.sk.eff.act)])
		var rk := str(Kit.cell(k, "r").fx.k)
		if not rt.has_method("_ult_" + rk) and not rt.has_method("_up_" + rk):
			bad.append("%s.r 강화 효과 %s 없음" % [k, rk])
	ok(bad.is_empty(), "불멸 칸 규칙 —— 신화가 있는 %d명은 기술 · 강화 이름이 신화와 다르다, vfx · 대기 3~14초 · 고유 동작 · 고유기 강화 효과가 엔진에 있다 %s" % [with_myth, str(bad)])


## 불멸 사건 —— 기술 slot q/w/e · 고유기 slot r · 고유 특기 알림 slot p (신화와 같은 길)
func _check_immortal_events() -> void:
	var a := _deck("L38", 0)
	var b := _deck("s07", 2)
	var res: Array = _run(a, b, _pol({"L38": ["w", "r"]}, {"s07": ["q"]}), 101)
	var r: Dictionary = res[0]
	var ka: String = res[1]["A:L38"]
	var kb: String = res[1]["B:s07"]
	var sk := {ka: 0, kb: 0}
	var ul := {ka: 0, kb: 0}
	var pn := {ka: 0, kb: 0}
	var bad := 0
	for e in r.ev:
		var who := str(e.get("a", ""))
		if not sk.has(who) or e.has("kup"):
			continue
		match str(e.get("fx", "")):
			"skill":
				if e.has("slot"):
					sk[who] += 1
					var want: bool = (who == ka and str(e.slot) == "w") or (who == kb and str(e.slot) == "q")
					if bool(e.get("up", false)) != want:
						bad += 1
			"ult":
				if str(e.get("slot", "")) == "r":
					ul[who] += 1
					if bool(e.get("up", false)) != (who == ka):
						bad += 1
			"passive":
				if str(e.get("slot", "")) == "p":
					pn[who] += 1
	var rk := {}
	for u in r.roster:
		if u.has("kit"):
			rk[u.key] = u.kit
	ok(int(sk[ka]) > 0 and int(sk[kb]) > 0 and int(ul[ka]) + int(ul[kb]) > 0 and bad == 0, "불멸 사건 —— 기술 칸 q/w/e · 고유기 칸 r · 강화 여부(up)가 맞다 (여포 기술 %d · 유비 기술 %d · 고유기 %d · 어긋남 %d)" % [sk[ka], sk[kb], int(ul[ka]) + int(ul[kb]), bad])
	ok(int(pn[ka]) == 1 and int(pn[kb]) == 1 and rk.get(ka) == ["w", "r"] and rk.get(kb) == ["q"], "불멸 고유 특기 알림 한 번씩 · 결과 roster 에 강화한 칸 %s" % str(rk))

# ───────── 9) 초월 · 기인 키트 스위치 (11/27 —— Kit.TRANS_ON · KIIN_ON / Kit.trans · kiin) ─────────

## 초월 15명 (6성 · 기인 아님 · 적 전용 · 은퇴 제외 · 고유기 있음) · 기인 22명 (kind kiin · 고유기 있음)
func _trans_list() -> Array:
	var out: Array = DB.C.keys().filter(func(k): return int(DB.C[k].tier) == Kit.TRANS_TIER and not DB.is_kiin(k) and not DB.is_foe(k) and str(DB.C[k].kind) != "retired" and DB.has_ult(k))
	out.sort()
	return out


func _kiin_list() -> Array:
	var out: Array = DB.C.keys().filter(func(k): return DB.is_kiin(k) and not DB.is_foe(k) and DB.has_ult(k))
	out.sort()
	return out


## 꺼짐 (게임 기본) —— 초월 · 기인은 키트 장수가 아니고, 그 칸 자료 · 강화 정책이 아무것도 바꾸지 않는다
func _check_tk_off() -> void:
	var tr := _trans_list()
	var ki := _kiin_list()
	var data_n := 0
	for k in tr + ki:
		if Kit.data().has(k):
			data_n += 1
	ok(tr.size() == 15 and ki.size() == 22 and data_n == 37, "초월 15명 · 기인 22명 —— kit.json 에 칸 자료가 있다 (초월 %d · 기인 %d · 자료 %d)" % [tr.size(), ki.size(), data_n])
	ok(not Kit.TRANS_ON and not Kit.KIIN_ON and not Kit.trans and not Kit.kiin, "스위치 기본값 꺼짐 (Kit.TRANS_ON = %s · Kit.KIIN_ON = %s)" % [str(Kit.TRANS_ON), str(Kit.KIIN_ON)])
	var leak := []
	for k in tr + ki:
		if Kit.on(k) or not Kit.cell(k, "q").is_empty() or not Kit.cell(k, "p").is_empty():
			leak.append(k)
	ok(leak.is_empty() and Kit.norm({"c117": ["q", "r"], "K21": ["w"], "N01": ["e"]}).is_empty(), "꺼짐 —— 초월 · 기인은 키트 장수가 아니다 (Kit.on · cell 빈 사전 · 강화 정책은 버려진다) %s" % str(leak))
	var t0 := JSON.stringify(DB.passives_of("c117"))
	var k0 := JSON.stringify(DB.passives_of("K21"))
	Kit.trans = true
	var t1 := JSON.stringify(DB.passives_of("c117"))
	var k_mid := JSON.stringify(DB.passives_of("K21"))
	Kit.trans = false
	Kit.kiin = true
	var k1 := JSON.stringify(DB.passives_of("K21"))
	var t_mid := JSON.stringify(DB.passives_of("c117"))
	Kit.kiin = false
	ok(t1 != t0 and k_mid == k0 and k1 != k0 and t_mid == t0 and JSON.stringify(DB.passives_of("c117")) == t0 and JSON.stringify(DB.passives_of("K21")) == k0,
		"스위치를 켰다 끄면 특기 캐시가 따라온다 · 초월 스위치는 기인을, 기인 스위치는 초월을 건드리지 않는다")
	Kit.trans = true
	var on_t: bool = tr.all(func(k): return Kit.on(k)) and not ki.any(func(k): return Kit.on(k)) and not _immortals().any(func(k): return Kit.on(k))
	Kit.trans = false
	Kit.kiin = true
	var on_k: bool = ki.all(func(k): return Kit.on(k)) and not tr.any(func(k): return Kit.on(k)) and not _immortals().any(func(k): return Kit.on(k))
	Kit.kiin = false
	ok(on_t and on_k, "스위치는 서로 독립 —— 초월만 켜면 초월만, 기인만 켜면 기인만 키트 장수 (불멸은 그대로 꺼짐)")
	# 초월 · 기인이 든 판 —— 꺼짐이면 키트가 아예 없는 판(Kit.enabled 끔)과 같은 사건, 그 등급의 강화 정책을 줘도 같다
	var same := true
	var marks := 0
	var n := 0
	for pair in [["c117", "K21"], ["K14", "c140"], ["K18", "s06"]]:
		var a := _deck(pair[0], 0, 6)
		var b := _deck(pair[1], 1, 6, ["K02", "K07"])
		for sd in [3, 7]:
			var base: Dictionary = _run(a, b, _pol({}), sd)[0]
			var pol: Dictionary = _run(a, b, _pol({pair[0]: ["q", "r"]}, {pair[1]: ["w", "p"], "K02": ["e"]}), sd)[0]
			Kit.enabled = false
			var old: Dictionary = _run(a, b, _pol({}), sd)[0]
			Kit.enabled = true
			n += 1
			if not (_fp(base) == _fp(old) and _fp(pol) == _fp(old) and base.ev.size() == old.ev.size()):
				same = false
			for e in base.ev + pol.ev:
				if e.has("slot") or e.has("kup"):
					marks += 1
	ok(same and marks == 0, "꺼짐 —— 초월 · 기인 전투 %d판: 같은 씨앗이면 예전(키트 끔)과 같은 결과 · 강화 정책도 무시 · 칸 표시 없음 (표시 %d)" % [n, marks])
	# 신화 · 불멸 · 초월 · 기인이 섞인 판 —— 초월 · 기인 강화 정책은 무시되고 신화 키트는 그대로 일한다
	var mixed := true
	var myth_marks := 0
	for sd in [5, 11]:
		var a := DB.auto_place(["c177", "L38", "c117", "K01", "N01", "c140", "K21", "s11", "c127"], "eorin")
		var b := DB.auto_place(["c181", "s01", "K14", "c150", "K02", "c145", "N03", "K12", "c132"], "eorin")
		var x: Dictionary = _run(a, b, _pol({"c177": ["q", "r"]}, {"c181": ["w"]}), sd)[0]
		var y: Dictionary = _run(a, b, _pol({"c177": ["q", "r"], "c117": ["q"], "K01": ["w", "p"]}, {"c181": ["w"], "K14": ["r"], "c150": ["e"]}), sd)[0]
		mixed = mixed and _fp(x) == _fp(y) and x.ev.size() == y.ev.size()
		for e in y.ev:
			if e.has("slot"):
				myth_marks += 1
	ok(mixed and myth_marks > 0, "꺼짐 —— 신화 · 불멸 · 초월 · 기인이 섞인 판: 초월 · 기인 강화 정책은 무시되고 같은 씨앗이면 같은 결과, 신화 칸 표시는 그대로 (%d)" % myth_marks)


## 켬 (--trans · --kiin) —— 그 등급이 키트 장수. 특기 · 칸 자료 · 칸 규칙 · 칸마다 강화가 실제로 일하는지 · 사건 · 결정성
func _ready_tk(kits: Array, cells: String) -> void:
	var tks: Array = (_trans_list() if Kit.trans else []) + (_kiin_list() if Kit.kiin else [])
	var want: int = 21 + (30 if Kit.immortal else 0) + tks.size()
	ok(kits.size() == want and tks.all(func(k): return kits.has(k)), "켬 —— 키트 장수 %d명 (신화 21%s%s%s · 지금 %d)" % [want, " + 불멸 30" if Kit.immortal else "", " + 초월 15" if Kit.trans else "", " + 기인 22" if Kit.kiin else "", kits.size()])
	var label: String = " · ".join((["초월"] if Kit.trans else []) + (["기인"] if Kit.kiin else []))
	if cells == "":
		_check_passives(tks)
		_check_data(kits)
		_check_tk_rules(tks)
	_check_cells(tks, cells)
	if cells == "":
		if Kit.trans:
			_check_tk_events("c140", "N03", {"c140": ["w", "r"]}, {"N03": ["q"]})
			_check_determinism("c117", "c150", {"c117": ["w", "r"]}, {"c150": ["q", "p"]})
		if Kit.kiin:
			_check_tk_events("K21", "K02", {"K21": ["e", "r"]}, {"K02": ["q"]})
			_check_determinism("K14", "K18", {"K14": ["w", "r"]}, {"K18": ["e", "p"]})
	Kit.trans = false
	Kit.kiin = false
	Kit.immortal = false
	print("장수 키트 엔진 점검 (%s 켬) —— 실패 %d" % [label, fails])
	get_tree().quit(1 if fails > 0 else 0)


## 초월 · 기인 칸 규칙 —— 같은 인물의 다른 등급(신화 · 불멸)과 기술 · 강화 이름이 겹치지 않는다, 칸마다 vfx, 대기 3~14초, 고유 동작 · 고유기 강화 · 고유 특기 강화가 엔진에 있다
func _check_tk_rules(tks: Array) -> void:
	var rt = load("res://scripts/kit_rt.gd").new()
	var src: String = (load("res://scripts/kit_rt.gd") as Script).source_code
	var bad := []
	var with_hi := 0
	for k in tks:
		var taken := {}
		for o in DB.C.keys():
			if o == k or DB.person(o) != DB.person(k) or not Kit.data().has(o):
				continue
			var h: Dictionary = Kit.data()[o]
			for s in Kit.SLOTS:
				if h.get(s) is Dictionary:
					taken[str(h[s].get("up", {}).get("n", ""))] = true
					if s in ["q", "w", "e"]:
						taken[str(h[s].get("n", ""))] = true
		if not taken.is_empty():
			with_hi += 1
		for s in Kit.SLOTS:
			var c := Kit.cell(k, s)
			if s in ["q", "w", "e"] and taken.has(str(c.n)):
				bad.append("%s.%s 이름이 같은 인물의 다른 등급과 같다" % [k, s])
			if taken.has(str(c.up.n)):
				bad.append("%s.%s 강화 이름이 같은 인물의 다른 등급과 같다" % [k, s])
			if s != "p" and (c.get("vfx", []) as Array).is_empty():
				bad.append("%s.%s vfx" % [k, s])
			if s in ["q", "w", "e"] and (float(c.cd) < 3.0 or float(c.cd) > 14.0):
				bad.append("%s.%s 대기 %s" % [k, s, str(c.cd)])
			if s in ["q", "w", "e"] and c.has("sk") and c.sk.eff.has("act") and not rt.has_method("_act_" + str(c.sk.eff.act)):
				bad.append("%s.%s 고유 동작 %s 없음" % [k, s, str(c.sk.eff.act)])
		var rk := str(Kit.cell(k, "r").fx.k)
		if not rt.has_method("_ult_" + rk) and not rt.has_method("_up_" + rk):
			bad.append("%s.r 강화 효과 %s 없음" % [k, rk])
		var pk := str(Kit.cell(k, "p").fx.k)
		if not src.contains("\"%s\"" % pk):
			bad.append("%s.p 강화 효과 %s 없음" % [k, pk])
	ok(bad.is_empty(), "초월 · 기인 칸 규칙 —— 같은 인물의 다른 등급이 있는 %d명과 이름이 겹치지 않는다, vfx · 대기 3~14초 · 고유 동작 · 고유기 · 고유 특기 강화가 엔진에 있다 %s" % [with_hi, str(bad)])


## 초월 · 기인 사건 —— 기술 slot q/w/e · 고유기 slot r · 고유 특기 알림 slot p · 강화 여부(up) · roster 의 kit (신화와 같은 길)
func _check_tk_events(ia: String, ib: String, kit_a: Dictionary, kit_b: Dictionary) -> void:
	var a := _deck(ia, 0, 6)
	var b := _deck(ib, 2, 6)
	var res: Array = _run(a, b, _pol(kit_a, kit_b), 101)
	var r: Dictionary = res[0]
	var ka: String = res[1]["A:" + ia]
	var kb: String = res[1]["B:" + ib]
	var ups := {ka: kit_a[ia], kb: kit_b[ib]}
	var sk := {ka: 0, kb: 0}
	var ul := 0
	var pn := {ka: 0, kb: 0}
	var bad := 0
	for e in r.ev:
		var who := str(e.get("a", ""))
		if not sk.has(who) or e.has("kup"):
			continue
		match str(e.get("fx", "")):
			"skill":
				if e.has("slot"):
					sk[who] += 1
					if bool(e.get("up", false)) != (ups[who] as Array).has(str(e.slot)):
						bad += 1
			"ult":
				if str(e.get("slot", "")) == "r":
					ul += 1
					if bool(e.get("up", false)) != (ups[who] as Array).has("r"):
						bad += 1
				else:
					bad += 1
			"passive":
				if str(e.get("slot", "")) == "p":
					pn[who] += 1
	var rk := {}
	for u in r.roster:
		if u.has("kit"):
			rk[u.key] = u.kit
	ok(int(sk[ka]) > 0 and int(sk[kb]) > 0 and ul > 0 and bad == 0, "%s · %s 사건 —— 기술 칸 q/w/e · 고유기 칸 r · 강화 여부(up)가 맞다 (기술 %d · %d · 고유기 %d · 어긋남 %d)" % [DB.C[ia].name, DB.C[ib].name, sk[ka], sk[kb], ul, bad])
	ok(int(pn[ka]) == 1 and int(pn[kb]) == 1 and rk.get(ka) == kit_a[ia] and rk.get(kb) == kit_b[ib], "%s · %s 고유 특기 알림 한 번씩 · 결과 roster 에 강화한 칸 %s" % [DB.C[ia].name, DB.C[ib].name, str(rk)])
