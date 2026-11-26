extends Node
## 11/27 장수 키트 Q · W · E · R · P —— 전투 엔진 점검 (scripts/kit.gd · kit_rt.gd · data/kit.json · Battle.mk_unit · act · _kit_tag)
## 실행: godot --headless --path . res://tests/kit_engine.tscn [-- --cells=c177:q,c190:r (그 칸만) --verbose]
##  1) 특기 배제 —— 키트 장수의 DB.passives_of 는 고유 특기 하나와 그 이름의 단체 효과만. Kit.enabled 를 끄면 예전 그대로 (캐시가 따라온다)
##  2) 자료 —— kit.json 10명 × 5칸 (11/27 대현량사 장각 c192 는 토벌 적 전용으로 빠졌다): 이름 · 글 · 강화 이름 · 글 · 엔진 필드(fx), q·w·e 의 cd, new 칸의 sk. 강화 상태 형식(칸 목록 · 장수당 2칸 · 옛 형식 읽기)
##  3) 전투 준비 —— 정책의 kit 이 유닛에 실리고(준비만 시키는 화면 길 _setup 포함) 상대 진영 · 카드 사전에 새지 않는다. 결과의 policy · roster 에 kit
##  4) 재사용 대기 —— 같은 칸 기술은 cd 초 안에 다시 나가지 않는다 (다시 쓰기 · 당김이 없는 편성에서)
##  5) 50칸 —— 칸마다 강화를 켠 판에서 그 강화가 실제로 일하고(kup 사건 · b.stats["kup:진영:카드:칸"]), 끈 같은 판에서는 일하지 않는다
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
	var myths: Array = DB.C.keys().filter(func(k): return Kit.on(k))
	myths.sort()
	ok(myths.size() == 10, "키트 장수 10명 (지금 %d)" % myths.size())
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
	ok(n == 50 and bad.is_empty(), "kit.json 50칸 —— 이름 · 글 · 강화 · 엔진 필드 · 재사용 대기 · 카드 기술과 이름이 맞는다 %s" % str(bad))
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
	ok(n / maxf(1.0, secs) < n_old / maxf(1.0, secs_old), "관우 기술 발동 간격 —— 예전(충전) %.1f초에 한 번 → 지금 %.1f초에 한 번" % [secs_old / maxf(1.0, n_old), secs / maxf(1.0, n)])


# ───────── 5) 50칸 ─────────

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
	ok(dead.is_empty(), "강화 50칸 —— 칸마다 그 강화가 실제로 일하는 판이 있다 (전투 %d판) 못 본 칸: %s" % [runs, str(dead)])
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

func _check_determinism() -> void:
	var a := _deck("c187", 0)
	var b := _deck("c194", 1)
	var kit := {"c187": ["e", "r"]}
	var kitb := {"c194": ["w", "p"]}
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
