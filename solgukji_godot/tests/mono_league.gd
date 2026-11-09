extends Node
## 11/8 병종 몰빵 대 고루 리그전 (docs/역할_재설계_1108.md 9.4-1) —— 실행: godot --headless --path . res://tests/mono_league.tscn
##   [-- --games=8 --tier=7 --decks=창병6,술사6,물리9,책략9,고루 --noshield --guard=창병:0.3,기병:0.15,술사:0.3,책사:0.15]
## 같은 등급 카드로만 짜서 비용을 맞춘다 (budget_mix 처럼 판마다 덱을 새로 뽑고, 같은 시드로 자리를 바꿔 두 번).
## 덱: <병종>6 = 그 병종 6 + 무작위 3 · 물리9 / 책략9 = 그 피해 종류만 · 고루 = 병종마다 1 + 무작위 1 (갑옷 깎기 · 결계 깎기 장수 각 1 먼저) · 고루0 = 고루에서 깎기 장수를 뺀 것
## 11/8 덱 이름 뒤 @등급 → 그 등급 카드 (예: 지원6@8 대 전투9 = 한 등급 위 지원 덱 대 전투 덱) · <병종>N = 그 병종 N + 무작위 · 전투9 = 창 · 기 · 궁 · 도적 · 책사 · 술사만
##   지원6 = 유생 · 모사 6 + 전투 3 · 섞음N = 유생 · 모사 N + 전투 나머지 · --pairs=A:B,C:D → 그 맞대결만 (앞 덱 승률)
## 결과: 상성표(행 덱의 승률) · 리그 평균 · 상대별 승률 폭(가장 높은 − 가장 낮은)
## 11/8 병종 균형 원인 찾기 —— 기능을 끄거나 값을 바꿔 같은 리그를 다시 잰다 (덱 · 시드는 그대로라 차이가 그 기능의 몫):
##   --off=고유기,특기,역할,상성,인덕,잔기술,위세,계략,철벽,화공,수공,깎기,기질,치료(유생 치료),기술(일반 기술),우대(삭제됨 —— 아무 일도 안 함),자리(선호 자리 배율),줄(줄 배율),책줄(책략계 줄 배율만),우회(도적 크게 돌기),후열평타(평타로 가장 깊은 적 치기),패업
##   --myth=1.0:0.8:0.6 → 신화 능력치 · 병력 · 특기 배율 · 덱 장각O · 장각X · 주유O · 주유X (패업 조건 맞춤 · 못 맞춤, 신화 1 + 불멸 7)
##   --set=cast:220,bow:250,gap:70,near:1.5,far:0.85,bank:2,charge:1.6,allr:320,heal:1.6 (유생 치료 배율),movedcd:0 (분발 재발동 대기 턴)
##     cnt:0.25 (병종 상성 세기) · cnti:0.25 (책략계가 끼는 상성 세기만) · 병종 배율 (Battle.tune_over): dmg:병종:배율 (준 피해) · taken:병종:배율 (받는 피해) · range:병종:배율 (원거리 사거리)
##   --stat → 덱마다 전투 길이(초) · 한 판 치료(최대 병력 몫 합) · 끝에 남은 부대 수
##   --axis=물리,책략,도트,공깎,책략깎,방깎,둔화,혼란,철벽,인덕,사기,없음 → 그 축의 특기를 양쪽 모두 끈다
##   --seed=700 → 덱 뽑기 · 전투 시드 바탕 (같은 값끼리는 덱이 같다 —— 다른 값으로 과적합을 본다)
##   --ev → 덱마다 준 피해의 출처(평타 · 기술 · 잔기술 · 고유기 · 지속 피해) 몫과 한 판 기술 횟수 · 기술 한 번에 맞힌 적 수 (사건 기록으로 센다)

const DECKS := ["창병6", "기병6", "궁병6", "도적6", "책사6", "모사6", "술사6", "유생6", "물리9", "책략9", "고루", "고루0"]

var pool: Array = []
var by_tag := {}
var phys_sh: Array = []
var int_sh: Array = []
var tier0 := 7
var last_tags: Array = []      # 기준9 의 병종 줄 (신화K 가 맞춘다)
var tiers := {}      # 등급 → [pool, by_tag, phys_sh, int_sh] (덱 이름 뒤 @등급 으로 다른 등급 덱을 섞는다)
const PAEUP_DECK := {"장각": "c192", "주유": "c195"}      # 11/8 패업 측정 덱 —— 장각O · 장각X · 주유O · 주유X (불멸 7칸 + 신화 1칸)
const FIGHT := ["창병", "기병", "궁병", "도적", "책사", "술사"]      # 전투 병종
const SUPPORT := ["유생", "모사"]      # 지원 병종 (유생 치료 · 사기 · 버프, 모사 약화 · 제어)


func _ready() -> void:
	var args := {}
	for s in OS.get_cmdline_user_args():
		var kv := s.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	var games := int(args.get("games", "8"))
	var seed0 := int(args.get("seed", "700"))      # 덱 뽑기 · 전투 시드의 바탕 (바꾸면 다른 덱으로 다시 잰다)
	var tier := int(args.get("tier", "7"))
	var names: Array = Array(str(args.get("decks", ",".join(DECKS))).split(","))
	if args.has("noshield"):
		Battle.shield_enabled = false
	Battle.guard_over = Battle.guard_arg(str(args.get("guard", "")))
	if args.has("myth"):      # --myth=능력치:병력 → 신화 배율 (Battle.myth_power · myth_troop) 덮어쓰기
		var mp := str(args.myth).split(":")
		Battle.myth_power = float(mp[0])
		if mp.size() > 1: Battle.myth_troop = float(mp[1])
		if mp.size() > 2: DB.set_myth_trait(float(mp[2]))
	print("신화 배율 능력치 %.2f · 병력 %.2f · 특기 %.2f" % [Battle.myth_power, Battle.myth_troop, DB.myth_trait])
	var knob := _knobs(str(args.get("off", "")), str(args.get("set", "")))
	for ax in str(args.get("axis", "")).split(",", false):      # 특기 축 끄기 (양쪽) —— 없음 = 축이 없는 특기(단체 특기 대부분)
		Battle.axis_off["" if ax == "없음" else ax] = true
		knob += " · 축 끔 " + ax
	var stat := args.has("stat")
	var evs := args.has("ev")
	tier0 = tier
	_use(tier)
	print("── 리그전 등급 %d (%s) · 막 %s · 판 %d × 자리 2 · 갑옷 깎기 %d명 · 결계 깎기 %d명 %s%s" % [tier, DB.TIER[tier].n,
		"끔" if not Battle.shield_enabled else ("켬" if Battle.guard_over.is_empty() else str(Battle.guard_over)), games, phys_sh.size(), int_sh.size(),
		"" if names.size() == DECKS.size() else str(names), knob])
	var w := {}
	var st := {}
	for a in names:
		w[a] = {}
		st[a] = {"n": 0, "len": 0.0, "heal": 0.0, "left": 0.0, "basic": 0.0, "sk": 0.0, "minor": 0.0, "ult": 0.0, "dot": 0.0, "casts": 0.0, "tgts": 0.0}
	var t0 := Time.get_ticks_msec()
	if args.has("pairs"):      # --pairs=지원6@8:전투9,… → 그 맞대결만 (앞 덱의 승률)
		for pr in str(args.pairs).split(",", false):
			var ab := pr.split(":")
			var rng := RandomNumberGenerator.new()
			rng.seed = seed0 + hash(pr) % 1000
			var s := 0.0
			var pq := {"n": 0, "on": 0, "used": 0, "st3": 0}
			for g in games:
				var da := DB.auto_place(_deck(ab[0], rng), "eorin")
				var db := DB.auto_place(_deck(ab[1], rng), "eorin")
				if g == 0 and args.has("show"):      # --show → 첫 판 덱 병종
					print("  %s: %s / %s: %s" % [ab[0], _tags(da), ab[1], _tags(db)])
				var sd := rng.randi() % 1000000
				var r1 := RtBattle.make(sd).run(da, "eorin", 100, null, db, "eorin", 100, null, "", "", [], {"A": "smart", "B": "smart"})
				var r2 := RtBattle.make(sd).run(db, "eorin", 100, null, da, "eorin", 100, null, "", "", [], {"A": "smart", "B": "smart"})
				s += (1.0 if r1.win else (0.5 if r1.draw else 0.0)) + (1.0 if (not r2.win and not r2.draw) else (0.5 if r2.draw else 0.0))
				for r in [r1, r2]:      # 패업 —— 발동 판 · 적벽연소 옮김 횟수 · 상태이상 3개가 한 부대에 겹친 판
					for p in r.get("paeup", []):
						pq.n += 1
						pq.on += 1 if p.on else 0
						pq.used += p.used
					if r.ev.any(func(e): return e.c == "st" and e.s.any(func(x): return x[3].filter(func(k): return k in ["burn", "flood", "plague", "seal", "confuse", "bleed"]).size() >= 3)):
						pq.st3 += 1
				if g == 0 and args.has("show"):      # 첫 판 길이 · 남은 부대 (병종 병력%)
					print("  " + " ".join(r1.roster.map(func(x): return "%s%s 피해%d 사기피해%d 남은사기%d" % [x.camp, x.tag, x.dmg, roundi(x.mdmg), roundi(x.morale)])))
					print("  %.0f초 이김 %s · 남음 %s" % [float(r1.get("len", 0.0)), r1.win, " ".join(r1.roster.filter(func(x): return x.alive).map(func(x): return "%s%s%d" % [x.camp, x.tag, roundi(100.0 * x.left / maxf(1, x.max))]))])
			print("맞대결 %s 대 %s : %d%%%s" % [ab[0], ab[1], roundi(s / (games * 2.0) * 100),
				"" if pq.n == 0 else "   (패업 발동 %d/%d · 적벽연소 옮김 %d번 · 상태이상 3겹 %d/%d판)" % [pq.on, pq.n, pq.used, pq.st3, games * 2]])
		print("끝 (%.0f초)" % ((Time.get_ticks_msec() - t0) / 1000.0))
		get_tree().quit()
		return
	for i in names.size():
		for j in range(i + 1, names.size()):
			var rng := RandomNumberGenerator.new()
			rng.seed = seed0 + i * 31 + j
			var s := 0.0
			for g in games:
				var da := DB.auto_place(_deck(names[i], rng), "eorin")
				var db := DB.auto_place(_deck(names[j], rng), "eorin")
				var sd := rng.randi() % 1000000
				var r1 := RtBattle.make(sd).run(da, "eorin", 100, null, db, "eorin", 100, null, "", "", [], {"A": "smart", "B": "smart"})
				var r2 := RtBattle.make(sd).run(db, "eorin", 100, null, da, "eorin", 100, null, "", "", [], {"A": "smart", "B": "smart"})
				s += (1.0 if r1.win else (0.5 if r1.draw else 0.0)) + (1.0 if (not r2.win and not r2.draw) else (0.5 if r2.draw else 0.0))
				if evs:
					_ev(st[names[i]], r1, "A")
					_ev(st[names[j]], r1, "B")
					_ev(st[names[j]], r2, "A")
					_ev(st[names[i]], r2, "B")
				if stat:
					_stat(st[names[i]], r1, "A")
					_stat(st[names[j]], r1, "B")
					_stat(st[names[j]], r2, "A")
					_stat(st[names[i]], r2, "B")
			var p := s / (games * 2.0)
			w[names[i]][names[j]] = p
			w[names[j]][names[i]] = 1.0 - p
	var head := "%-6s" % "덱"
	for b in names:
		head += " %5s" % str(b).left(4)
	print(head + "   평균   폭")
	var rows := []
	for a in names:
		var line := "%-6s" % a
		var sum := 0.0
		var lo := 1.0
		var hi := 0.0
		for b in names:
			if a == b:
				line += "     -"
				continue
			var p: float = w[a][b]
			line += " %5d" % roundi(p * 100)
			sum += p
			lo = minf(lo, p)
			hi = maxf(hi, p)
		var avg := sum / (names.size() - 1)
		rows.append([avg, a])
		print(line + "  %4d%%  %3d" % [roundi(avg * 100), roundi((hi - lo) * 100)])
	rows.sort_custom(func(x, y): return x[0] > y[0])
	if evs:
		print("덱      평타%  기술%  잔기%  고유%  지속%  기술/판  기술당 대상")
		for a in names:
			var e: Dictionary = st[a]
			var tot := maxf(1.0, e.basic + e.sk + e.minor + e.ult + e.dot)
			print("%-6s  %4d  %4d  %4d  %4d  %4d   %5.1f   %4.2f" % [a, roundi(e.basic / tot * 100), roundi(e.sk / tot * 100), roundi(e.minor / tot * 100),
				roundi(e.ult / tot * 100), roundi(e.dot / tot * 100), e.casts / maxf(1, e.n_ev), e.tgts / maxf(1, e.casts)])
	if stat:
		print("덱      길이(초)  치료  남은부대")
		for a in names:
			var e: Dictionary = st[a]
			print("%-6s  %6.1f  %5.2f  %5.1f" % [a, e.len / maxf(1, e.n), e.heal / maxf(1, e.n), e.left / maxf(1, e.n)])
	print("순위: %s   (%.0f초)" % [" > ".join(rows.map(func(x): return "%s %d%%" % [x[1], roundi(x[0] * 100)])), (Time.get_ticks_msec() - t0) / 1000.0])
	get_tree().quit()


## 덱 병종 줄 (자리 배치 결과 —— 원소가 사전이면 key, 문자열이면 그대로)
func _tags(d) -> String:
	var out := []
	for x in d:
		if x == null:
			continue
		var k = x.get("key", x.get("k", "")) if x is Dictionary else x
		out.append(DB.C[k].tag if DB.C.has(k) else str(k))
	return " ".join(out)


## 그 등급 카드 풀로 바꾼다 (처음 쓸 때 만든다)
func _use(t: int) -> void:
	if not tiers.has(t):
		var pl := DB.by_tier(t).filter(func(k): return not DB.is_kiin(k))
		var bt := {}
		var ps := []
		var is_ := []
		for k in pl:
			var tg: String = DB.C[k].tag
			if not bt.has(tg):
				bt[tg] = []
			bt[tg].append(k)
			if _phys_shred(k):
				ps.append(k)
			if _int_shred(k):
				is_.append(k)
		tiers[t] = [pl, bt, ps, is_]
	pool = tiers[t][0]
	by_tag = tiers[t][1]
	phys_sh = tiers[t][2]
	int_sh = tiers[t][3]


## 덱 이름 —— 이름@등급 이면 그 등급 카드로 (없으면 --tier). 전투9 = 전투 병종만 · 지원6 = 유생 · 모사 6 + 전투 3 · 섞음N = 지원 N + 전투 나머지 · <병종>N = 그 병종 N + 무작위
func _deck(spec: String, rng: RandomNumberGenerator) -> Array:
	var at := spec.split("@")
	_use(int(at[1]) if at.size() > 1 else tier0)
	var name_: String = at[0]
	var out := []
	var fight := pool.filter(func(k): return DB.C[k].tag in FIGHT)
	var sup := pool.filter(func(k): return DB.C[k].tag in SUPPORT)
	if name_ == "기준9":      # 신화 칸 측정의 기준 —— 그 등급 무작위 9 (병종 줄을 기억해 신화K 가 같은 병종으로 짠다)
		for i in 9:
			_add(out, pool, rng)
		last_tags = out.map(func(k): return DB.C[k].tag)
		return out
	if name_.begins_with("신화"):      # 신화K = 바로 앞 기준9 와 같은 병종 줄, K 칸을 한 등급 위 같은 병종으로 · 신화K비 = 같은 비용 (불멸 95 · 신화 126 → 마지막 칸을 비운다)
		var cost := name_.ends_with("비")
		var kk := int(name_.trim_prefix("신화").trim_suffix("비"))
		var tags: Array = last_tags.duplicate()
		if cost:
			tags.pop_back()
		var up_t := (int(at[1]) if at.size() > 1 else tier0) + 1
		var hi: Array = DB.by_tier(up_t).filter(func(k): return not DB.is_kiin(k))
		for i in tags.size():
			if i < kk:
				var same := hi.filter(func(k): return DB.C[k].tag == tags[i])
				_add(out, same if not same.is_empty() else hi, rng)
			else:
				_add(out, by_tag.get(tags[i], pool), rng)
		return out
	if PAEUP_DECK.has(name_.left(2)) and name_.length() >= 3:      # 11/8 패업 —— 장각O = 신화 장각 + 조건 장수 3 + 조건 밖 4 (신화1비 와 같은 8칸) · X = 조건 밖 7 (불발) · 뒤에 9 = 9칸 (신화1 처럼)
		var cid: String = PAEUP_DECK[name_.left(2)]
		var cond := str(DB.AURA[cid].paeup.cond)
		var hit: Array = pool.filter(func(k): return Battle.paeup_counts(k, cond))
		var miss: Array = pool.filter(func(k): return not Battle.paeup_counts(k, cond))
		out.append(cid)
		var nh := int(DB.AURA[cid].paeup.need) if name_.substr(2, 1) == "O" else 0
		for i in nh:
			_add(out, hit, rng)
		while out.size() < (9 if name_.ends_with("9") else 8):
			_add(out, miss, rng)
		return out
	if name_.begins_with("전투"):      # 전투N = 전투 병종 N 장만 (N < 9 면 덱이 작다 —— 높은 등급 몇 장의 힘을 잴 때)
		for i in int(name_.trim_prefix("전투")):
			_add(out, fight, rng)
		return out
	if name_ == "지원6" or name_.begins_with("섞음"):
		var ns := 6 if name_ == "지원6" else int(name_.trim_prefix("섞음"))
		for i in ns:      # 유생 · 모사 번갈아
			_add(out, by_tag.get(SUPPORT[i % 2], sup), rng)
		while out.size() < 9:
			_add(out, fight, rng)
		return out
	if name_ == "물리9" or name_ == "책략9":
		var src := pool.filter(func(k): return DB.dmg_kind(DB.C[k].tag) == ("phys" if name_ == "물리9" else "int"))
		for i in 9:
			_add(out, src, rng)
	elif name_.begins_with("고루"):
		var no_sh := name_ == "고루0"
		if not no_sh:
			_add(out, phys_sh, rng)
			_add(out, int_sh, rng)
		for tg in DB.D.TAGORDER:
			if out.any(func(x): return DB.C[x].tag == tg):
				continue
			_add(out, by_tag.get(tg, []).filter(func(k): return not no_sh or not (phys_sh.has(k) or int_sh.has(k))), rng)
		while out.size() < 9:
			_add(out, pool.filter(func(k): return not no_sh or not (phys_sh.has(k) or int_sh.has(k))), rng)
	else:
		var n := int(name_.right(1))
		var tg := name_.left(name_.length() - 1)
		for i in n:
			_add(out, by_tag.get(tg, []), rng)
		while out.size() < 9:
			_add(out, pool, rng)
	return out


## 같은 인물은 한 장만 —— 실제 게임처럼(Run.dup_slot: 고급 이상 같은 인물은 한 칸만). 그 병종에 고를 인물이 없으면 다른 병종으로 채운다 (11/8 지휘: 예전엔 겹쳐 넣어 신화 위세 · 단체 특기가 몇 배로 쌓였다)
func _add(out: Array, src: Array, rng: RandomNumberGenerator) -> void:
	if src.is_empty():
		src = pool
	var cand := src.filter(func(k): return not out.any(func(x): return DB.person(x) == DB.person(k)))
	if cand.is_empty():
		cand = pool.filter(func(k): return not out.any(func(x): return DB.person(x) == DB.person(k)))
	if cand.is_empty():
		cand = src
	out.append(cand[rng.randi() % cand.size()])


static func _phys_shred(k: String) -> bool:
	var ps = DB.passives_of(k)
	if ps == null:
		return false
	return ps.traits.any(func(t): return t.name != "현혹" and (t.m.has("cut_def") or t.m.has("first_cut") or t.m.has("rush")))


static func _int_shred(k: String) -> bool:
	var ps = DB.passives_of(k)
	if ps == null:
		return false
	return ps.traits.any(func(t): return t.name == "현혹" or t.name == "요언")


func _stat(e: Dictionary, r: Dictionary, cp: String) -> void:
	e.n += 1
	e.len += float(r.get("len", 0.0))
	for x in r.roster:
		if x.camp == cp:
			e.heal += float(x.theal)
			e.left += 1.0 if x.alive else 0.0


## 원인 찾기 손잡이 —— 이 프로세스 안에서만 바꾼다 (데이터 파일은 그대로). 바꾼 것을 한 줄로 돌려준다
func _knobs(off: String, set_: String) -> String:
	var out := []
	for o in off.split(",", false):
		match o:
			"고유기": Battle.ults_enabled = false
			"특기": Battle.passives_enabled = false
			"역할": Battle.tag_roles = false
			"상성": Battle.counter_enabled = false
			"인덕": Battle.virtue_enabled = false
			"잔기술": Battle.minor_enabled = false
			"위세": Battle.aura_enabled = false
			"패업": Battle.paeup_enabled = false
			"계략": Battle.scheme_enabled = false
			"철벽": Battle.guard_enabled = false
			"화공": Battle.fire_enabled = false
			"수공": Battle.water_enabled = false
			"깎기": Battle.cut_enabled = false
			"기질": Battle.temper_enabled = false
			"치료": Battle.ROLE.schol_heal = 0.0
			"기술":
				for k in DB.C:
					for sk in DB.C[k].get("sks", []):
						sk.cost = 999.0
			"우대": pass      # 11/9 진형 우대 삭제 —— 이제 끌 것이 없다 (아무 일도 안 한다)
			"자리":
				for tg in DB.D.AFF:
					DB.D.AFF[tg].b = {}
					DB.D.AFF[tg].p = {}
			"줄":
				for ln in DB.D.LINE:
					for k in ["atk", "def", "int"]:
						DB.D.LINE[ln][k] = 1.0
			"우회": RtBattle.probe_rogue_flank = false
			"후열평타": RtBattle.probe_back_basic = false
			"책줄":      # 책략계 공격 줄 배율만 (뒤 1.3 · 앞 0.8)
				for ln in DB.D.LINE:
					DB.D.LINE[ln]["int"] = 1.0
			_:
				push_error("모르는 --off: " + o)
				continue
		out.append(o)
	var sets := []
	for kv in set_.split(",", false):
		var p := kv.split(":")
		if p.size() == 3:
			if not Battle.tune_over.has(p[0]):
				Battle.tune_over[p[0]] = {}
			Battle.tune_over[p[0]][p[1]] = float(p[2])
			sets.append(kv)
			continue
		var v := float(p[1])
		match p[0]:
			"cast": RtBattle.cast_range = v
			"bow": RtBattle.bow_range = v
			"gap": RtBattle.melee_gap = v
			"near": RtBattle.near_mul = v
			"far": RtBattle.far_mul = v
			"bank": RtBattle.melee_bank = v
			"charge": RtBattle.cav_charge = v
			"allr": RtBattle.all_r = v
			"heal": Battle.ROLE.schol_heal = v
			"movedcd": Battle.moved_cd = int(v)
			"cnti":     # 책략계가 끼는 상성 세기만 (등급별 int_amt 를 모두 이 값으로)
				for t in DB.CLASS_COUNTER.get("int_amt", {}):
					DB.CLASS_COUNTER.int_amt[t] = v
			"cnt":      # 병종 상성 세기 (등급별 책략 상성도 같은 비율로)
				var r := v / float(DB.CLASS_COUNTER.amt)
				DB.CLASS_COUNTER.amt = v
				for t in DB.CLASS_COUNTER.get("int_amt", {}):
					DB.CLASS_COUNTER.int_amt[t] = float(DB.CLASS_COUNTER.int_amt[t]) * r
			_:
				push_error("모르는 --set: " + p[0])
				continue
		sets.append(kv)
	if out.is_empty() and sets.is_empty():
		return ""
	return " · 끔 %s · 값 %s" % [",".join(out), ",".join(sets)]


## 사건 기록으로 피해 출처를 센다 —— 기술 · 고유기 사건(fx skill · ult)과 같은 행동 번호(ai)의 타격은 그 기술 몫, 잔기술은 mn 이 붙은 타격
func _ev(e: Dictionary, r: Dictionary, cp: String) -> void:
	e["n_ev"] = e.get("n_ev", 0) + 1
	var ctx := {}        # 장수 키 -> [종류, ai]
	var hit := {}        # "키|ai" -> 맞힌 적 키들
	for x in r.ev:
		var fx = x.get("fx")
		var a = x.get("a")
		if fx == "skill" or fx == "ult":
			if a != null and str(a).begins_with(cp):
				ctx[a] = ["sk" if fx == "skill" else "ult", x.get("ai")]
				if fx == "skill" and x.has("kind"):
					e.casts += 1
					hit[str(a) + "|" + str(x.get("ai"))] = {}
			continue
		if fx == "tick" and x.has("n") and not str(x.get("f", cp)).begins_with(cp):
			e.dot += float(x.n)
			continue
		if (fx == "phys" or fx == "int") and x.has("n") and a != null and str(a).begins_with(cp):
			var n := float(x.n)
			var c = ctx.get(a)
			if x.has("mn"):
				e.minor += n
			elif c != null and c[1] == x.get("ai"):
				if c[0] == "sk":
					e.sk += n
					var hk := str(a) + "|" + str(x.get("ai"))
					if hit.has(hk):
						hit[hk][x.get("f")] = true
				else:
					e.ult += n
			else:
				e.basic += n
	for hk in hit:
		e.tgts += hit[hk].size()
