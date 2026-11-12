extends Node
## 인연 합동 고유기 점검 (11/11) —— 실행: godot --headless --path . res://tests/inyeon.tscn
## (a) 데이터: inyeon.json 의 모든 인연 4~5명 · 중복 없음 · 알려진 인물 · 모든 인물이 고유기 보유 · 장수당 3~6개 인연
## (b) 유비 + 관우 + 장비를 게이지 100 으로 강제 → 합류해 합동 고유기 하나로 터진다 (대표 창 · 합류 시각 · 터지는 순서 · 사건 항목)
## (c) 둘만 찼으면 둘이 터진다 · 인연 없는 장수가 섞이면 합류하지 않는다
## (d) inyeon_enabled=false 면 예전처럼 장수마다 따로 (간격 ult_side_sec 이상)
## (e) 합동 상한: 한 부대가 합동 전체에서 받는 병력 ≤ 단일 상한 × inyeon_cap_mul
## (f~h) 11/12 인연 주제 (RtBattle.inyeon_theme) —— 기인이 연다 · 초월이 키운다(4명) · 주제 사건 · 무작위 덱에서 기인/초월 연쇄 횟수

var _fail := 0


func _ok(cond: bool, msg: String) -> void:
	if not cond:
		_fail += 1
		print("  실패: ", msg)


## 시작 직후 지정한 인물만 게이지 100 · 대기 0 으로 만들고 나머지(양 진영)는 고유기를 없앤다 (적이 끊거나 먼저 쏘지 못하게)
class Forced extends RtBattle:
	var full := []            # 게이지를 채울 A 진영 인물 이름
	var keep := []            # 고유기를 남길 B 진영 인물 이름 (끊기 시험)
	var _done := false

	func _turn_begin(turn: int) -> void:
		super._turn_begin(turn)
		if _done:
			return
		_done = true
		for u in units:
			var p := DB.person(u.c.id)
			if u.camp == "A" and full.has(p) and u.ult != null:
				u.gauge = 100.0
				u.ult_ready_t = 0.0 + 0.01 * full.find(p)      # 먼저 적은 인물이 먼저 찬 것으로
				u.ult.wait = 0.0
			elif u.camp == "B" and keep.has(p) and u.ult != null:
				u.ult.wait = 0.0
			else:
				u.ult = null


func _card(person: String, tier: int) -> String:
	for k in DB.by_tier(tier):
		if DB.person(k) == person and DB.ult_of(k) != null:
			return k
	return ""


func _pick(persons: Array, fill_tier := 7) -> Array:
	var out := []
	for p in persons:
		var k := ""
		for t in [7, 8, 6]:
			k = _card(p, t)
			if k != "":
				break
		out.append(k)
	var used := out.map(func(k): return DB.person(k))
	for k in DB.by_tier(fill_tier):
		if out.size() >= 9:
			break
		if not used.has(DB.person(k)):
			out.append(k)
			used.append(DB.person(k))
	return out


func _run(a_persons: Array, full: Array, seed_v := 5, keep_b := []) -> Dictionary:
	var a := _pick(a_persons)
	var b := _pick(keep_b, 7)
	var bt := Forced.new(seed_v)
	bt.full = full
	bt.keep = keep_b
	var r := bt.run(DB.auto_place(a, "eorin"), "eorin", 100, null, DB.auto_place(b, "hagik"), "hagik", 100, null, "", "", [], {"A": "auto", "B": "auto"})
	r["bt"] = bt
	return r


func _evs(r: Dictionary, fx: String) -> Array:
	return r.ev.filter(func(e): return e.get("fx") == fx)


func _ready() -> void:
	# (a) 데이터
	var ult_names: Array = DB.ULT.list.keys()
	var persons := {}
	for k in DB.C:
		persons[DB.person(k)] = true
	_ok(DB.INYEON.size() == 51, "인연 수 51 (지금 %d)" % DB.INYEON.size())
	for n in DB.INYEON:
		var ps: Array = DB.INYEON[n]
		_ok(ps.size() >= 4 and ps.size() <= 5, "%s: 인원 %d (4~5)" % [n, ps.size()])
		var seen := {}
		for p in ps:
			_ok(not seen.has(p), "%s: %s 중복" % [n, p])
			seen[p] = true
			_ok(persons.has(p), "%s: 모르는 인물 %s" % [n, p])
			_ok(DB.ULT.list.has(p), "%s: %s 고유기 없음" % [n, p])
	var hist := {}
	for p in DB.INYEON_OF:
		var c: int = DB.INYEON_OF[p].size()
		_ok(c >= 3 and c <= 6, "%s: 인연 %d개 (3~6)" % [p, c])
		hist[c] = int(hist.get(c, 0)) + 1
	print("(a) 인연 %d · 인연에 든 인물 %d (장수당 개수 분포 %s) · 고유기 보유 인물 %d" % [DB.INYEON.size(), DB.INYEON_OF.size(), str(hist), ult_names.size()])

	# (b) 유비 관우 장비 —— 셋 다 찬 채로 시작 (도원결의 · 호뢰관 · 무쌍의 호걸 …)
	var r := _run(["유비", "관우", "장비"], ["유비", "관우", "장비"])
	var warns := _evs(r, "ult_warn")
	var joins := _evs(r, "ult_join")
	var ults := _evs(r, "ult")
	print("(b) 셋: 예고 %d · 합류 %d · 터짐 %d" % [warns.size(), joins.size(), ults.size()])
	_ok(warns.size() >= 1 and joins.size() >= 2, "합류 둘")
	if warns.size() >= 1 and joins.size() >= 2 and ults.size() >= 3:
		var w0: Dictionary = warns[0]
		var t0: float = w0.tm
		var dur: float = w0.wait
		print("   대표 %s 예고 %.2fs · 창 %.2f" % [w0.a, t0, dur])
		for j in joins.slice(0, 2):
			print("   합류 %s +%.2fs · 인연 『%s』 · 남은 %.2f · ord %d" % [j.a, j.tm - t0, j.inyeon, j.wait, j.ord])
			_ok(j.lead == w0.a, "합류의 대표가 예고한 장수")
		_ok(absf((joins[0].tm - t0) - dur * 0.32) <= 0.06, "합류1 시각 ≈ +%.2f (지금 %.2f)" % [dur * 0.32, joins[0].tm - t0])
		_ok(absf((joins[1].tm - t0) - dur * 0.64) <= 0.06, "합류2 시각 ≈ +%.2f (지금 %.2f)" % [dur * 0.64, joins[1].tm - t0])
		var keys := [w0.a, joins[0].a, joins[1].a]
		for i in 3:
			var u: Dictionary = ults[i]
			print("   터짐 %d %s +%.2fs · 항목 %s" % [i, u.a, u.tm - t0, str([u.get("inyeon", ""), u.get("mates", u.get("lead", ""))])])
			_ok(u.a == keys[i], "터지는 순서 %d = %s (지금 %s)" % [i, keys[i], u.a])
			_ok(absf((u.tm - t0) - (dur + 0.2 * i)) <= 0.06, "터짐 %d 시각 ≈ +%.2f" % [i, dur + 0.2 * i])
		_ok(ults[0].get("mates", []).size() == 2 and ults[1].get("lead", "") == w0.a and ults[2].get("lead", "") == w0.a, "사건 항목 mates · lead")
		var bt: RtBattle = r.bt
		_ok(int(bt.stats.get("inyeon_joint", 0)) >= 1 and int(bt.stats.get("inyeon_units", 0)) >= 3 and int(bt.stats.get("inyeon_n3", 0)) >= 1, "stats 합동 · 3명")

	# (c) 둘만 찼다 / 인연 없는 장수가 섞임
	var r2 := _run(["유비", "관우", "장비"], ["유비", "관우"])
	var j2 := _evs(r2, "ult_join")
	var u2 := _evs(r2, "ult")
	print("(c1) 둘만 참: 합류 %d · 터짐 %d (처음 %d명 합동)" % [j2.size(), u2.size(), 1 + (u2[0].get("mates", []).size() if not u2.is_empty() else 0)])
	_ok(not j2.is_empty() and j2[0].lead != j2[0].a, "둘 합류")
	_ok(j2.size() >= 1 and u2.size() >= 2 and u2[0].get("mates", []).size() == 1, "합동 둘")
	var r3 := _run(["유비", "관우", "조조"], ["유비", "조조"])      # 유비 · 조조는 서서의 어머니 · 하비 포위 …
	var r4 := _run(["유비", "여포", "허저"], ["유비", "허저"])      # 유비 · 허저는 인연 없음?
	var share34 := _shares("유비", "허저")
	var j3 := _evs(r3, "ult_join")
	var j4 := _evs(r4, "ult_join")
	print("(c2) 유비+조조 합류 %d · 유비+허저(공유 인연 %s) 합류 %d" % [j3.size(), str(share34), j4.size()])
	_ok(not j3.is_empty() or _shares("유비", "조조").is_empty(), "유비+조조 합류 (공유 인연이 있으면)")
	_ok(j4.is_empty() == share34.is_empty(), "공유 인연이 없으면 합류하지 않는다 (있으면 합류)")

	# (d) 끄면 예전처럼 따로
	Battle.inyeon_enabled = false
	var r5 := _run(["유비", "관우", "장비"], ["유비", "관우", "장비"])
	Battle.inyeon_enabled = true
	var u5 := _evs(r5, "ult")
	print("(d) 끔: 합류 %d · 터짐 %d" % [_evs(r5, "ult_join").size(), u5.size()])
	_ok(_evs(r5, "ult_join").is_empty(), "끄면 합류 없음")
	_ok(u5.size() >= 2, "끄면 따로 터진다")
	if u5.size() >= 2:
		var gap: float = u5[1].tm - u5[0].tm
		print("   첫 두 발동 간격 %.2fs (ult_side_sec %.1f)" % [gap, RtBattle.ult_side_sec])
		_ok(gap >= RtBattle.ult_side_sec - 0.06, "끄면 간격 ult_side_sec 이상")
		_ok(not u5[0].has("inyeon") and not u5[0].has("mates"), "끄면 사건에 합동 항목 없음")

	# (e) 대표가 끊기는 경우 —— 합류한 장수는 제 시각에 쏘고, 사건에는 lead 가 없다 (보통 고유기처럼)
	var r6 := _run_cut()
	print("(e) 끊김: %s" % r6)

	if RtBattle.inyeon_theme:
		_theme_checks()

	print("인연 점검 %s (실패 %d)" % ["통과" if _fail == 0 else "실패", _fail])
	get_tree().quit(1 if _fail > 0 else 0)


func _shares(a: String, b: String) -> Array:
	return DB.INYEON_OF.get(a, []).filter(func(n): return DB.INYEON[n].has(b))


## 대표만 직접 끊어 본다 —— 합류 예약이 취소되고 이미 합류한 장수는 따로 쏜다
class CutLead extends Forced:
	var cut_at := 1.2      # 대표 예고 후 이 초에 대표를 끊는다
	var t_warn := -1.0
	var did := false

	func _fire_winds() -> void:
		if t_warn < 0.0 and not _wind.is_empty():
			t_warn = _tm
		if not did and t_warn >= 0.0 and _tm - t_warn >= cut_at - 0.001:
			did = true
			for u in _wind.keys():
				if _wind_grp.has(u) and _wind_grp[u].lead == u:
					var foe: Unit = units.filter(func(o): return o.camp != u.camp)[0]
					_cut_wind(u, foe)
		super._fire_winds()


func _run_cut() -> String:
	var a := _pick(["유비", "관우", "장비"])
	var b := _pick([], 7)
	var bt := CutLead.new(5)
	bt.full = ["유비", "관우", "장비"]
	var r := bt.run(DB.auto_place(a, "eorin"), "eorin", 100, null, DB.auto_place(b, "hagik"), "hagik", 100, null, "", "", [], {"A": "auto", "B": "auto"})
	var warns := _evs(r, "ult_warn")
	var joins := _evs(r, "ult_join")
	var cuts := _evs(r, "ult_cut")
	var ults := _evs(r, "ult")
	var first: Dictionary = ults[0] if not ults.is_empty() else {}
	_ok(not warns.is_empty() and cuts.size() >= 1, "대표가 끊겼다")
	# 11/12: 첫 합동(대표 첫 예고 뒤 2.6초 안)만 센다 —— 진형이 바뀌면 전투 뒤쪽에 다른 합동이 또 나올 수 있다
	var t0w := float(warns[0].get("tm", 0.0)) if not warns.is_empty() else 0.0
	var joins1 := joins.filter(func(e): return float(e.get("tm", 0.0)) <= t0w + 2.6 and str(e.get("lead", "")) == str(warns[0].get("a", "")))
	_ok(joins1.size() == 1, "대표가 +1.2초에 끊기면 합류1(+0.8)만 합류 (지금 %d)" % joins1.size())
	_ok(not first.is_empty() and not first.has("lead") and not first.has("mates"), "합류한 장수는 보통 고유기로 쏜다")
	return "합류 %d · 끊김 %d · 첫 발동 항목 %s" % [joins.size(), cuts.size(), str(first.get("inyeon", "-"))]



# ───────── 11/12 인연 주제 · 기인이 연다 · 초월이 키운다 ─────────
func _kiin_card(person: String) -> String:
	for k in DB.C:
		if DB.C[k].kind == "kiin" and DB.person(k) == person and DB.ult_of(k) != null:
			return k
	return ""


func _any(person: String, tiers: Array) -> String:
	for t in tiers:
		var k := _card(person, t)
		if k != "":
			return k
	return ""


## 오호대장 가운데 초월 카드가 있는 인물 (없으면 "")
func _up_of(nm: String, skip: String) -> String:
	for p in DB.INYEON[nm]:
		if p != skip and _card(p, 6) != "":
			return p
	return ""


func _run_cards(a: Array, full: Array, seed_v := 5) -> Dictionary:
	var used := a.map(func(k): return DB.person(k))
	for k in DB.by_tier(7):
		if a.size() >= 9:
			break
		if not used.has(DB.person(k)):
			a.append(k)
			used.append(DB.person(k))
	var b := _pick([], 7)
	var bt := Forced.new(seed_v)
	bt.full = full
	var r := bt.run(DB.auto_place(a, "eorin"), "eorin", 100, null, DB.auto_place(b, "hagik"), "hagik", 100, null, "", "", [], {"A": "auto", "B": "auto"})
	r["bt"] = bt
	return r


func _theme_checks() -> void:
	# (f) 기인이 연다 —— 기인 카드가 있는 인연에서 (불멸 이상 대표 + 기인 + 한 명 더)
	var fk := ""
	var fa := []
	var ff := []
	for nm in DB.INYEON:
		for p in DB.INYEON[nm]:
			var kc := _kiin_card(p)
			if kc == "":
				continue
			var hi: Array = DB.INYEON[nm].filter(func(q): return q != p and _any(q, [7, 8]) != "")
			if hi.size() >= 2:
				fk = kc
				fa = [_any(hi[0], [7, 8]), kc, _any(hi[1], [7, 8])]
				ff = [hi[0], p, hi[1]]
				break
		if fk != "":
			break
	var r := _run_cards(fa, ff)
	var warns := _evs(r, "ult_warn")
	var ults := _evs(r, "ult")
	print("(f) 기인 %s %s: 예고 %d · 합류 %d · 터짐 %d" % [fk, str(ff), warns.size(), _evs(r, "ult_join").size(), ults.size()])
	if warns.size() >= 1 and ults.size() >= 3:
		var t0: float = warns[0].tm
		var dur: float = warns[0].wait
		for i in 3:
			print("   터짐 %d %s +%.2fs · %s" % [i, ults[i].a, ults[i].tm - t0, str([ults[i].get("inyeon", ""), ults[i].get("mates", ults[i].get("lead", "")), ults[i].get("open", ""), ults[i].get("finish", false)])])
		var kkey := ""
		for u in r.bt.units:
			if u.c.id == fk:
				kkey = u.key
		_ok(ults[0].a == kkey, "기인이 맨 먼저 터진다 (지금 %s)" % ults[0].a)
		_ok(absf((ults[0].tm - t0) - (dur - 0.2)) <= 0.06, "기인은 대표보다 0.2초 먼저")
		_ok(ults[0].get("mates", []).size() == 2 and ults[0].get("open", "") == "kiin", "기인 사건에 mates · open")
		_ok(ults[2].get("finish", false), "마무리 장수 표시")
	_ok(int(r.bt.stats.get("inyeon_kiin", 0)) >= 1 and int(r.bt.stats.get("inyeon_kiin_fin", 0)) >= 1, "stats 기인 연쇄 · 마무리")
	_ok(not _evs(r, "inyeon_theme").is_empty(), "주제 사건")

	# (g) 초월이 키운다 —— 불멸 이상 대표 + 초월 + 둘 더 = 4명
	var ga_ := []
	var gf := []
	for nm in DB.INYEON:
		var up := ""
		for p in DB.INYEON[nm]:
			if _card(p, 6) != "":
				up = p
				break
		if up == "":
			continue
		var hi: Array = DB.INYEON[nm].filter(func(q): return q != up and _any(q, [7, 8]) != "")
		if hi.size() >= 3:
			ga_ = [_any(hi[0], [7, 8]), _card(up, 6), _any(hi[1], [7, 8]), _any(hi[2], [7, 8])]
			gf = [hi[0], up, hi[1], hi[2]]
			break
	var r2 := _run_cards(ga_, gf)
	var w2 := _evs(r2, "ult_warn")
	var j2 := _evs(r2, "ult_join")
	var u2 := _evs(r2, "ult")
	print("(g) 초월 %s: 합류 %d · 터짐 %d · 첫 합동 %d명" % [str(gf), j2.size(), u2.size(), 1 + (u2[0].get("mates", []).size() if not u2.is_empty() else 0)])
	_ok(j2.size() >= 3, "초월이 끼면 셋 합류")
	if w2.size() >= 1 and j2.size() >= 3:
		var t0: float = w2[0].tm
		var dur: float = w2[0].wait
		for i in 3:
			print("   합류 %d %s +%.2fs" % [i, j2[i].a, j2[i].tm - t0])
			_ok(absf((j2[i].tm - t0) - dur * [0.24, 0.48, 0.72][i]) <= 0.06, "4명 합류 시각 %d" % i)
		_ok(u2[0].get("mates", []).size() == 3, "4명 합동")
	_ok(int(r2.bt.stats.get("inyeon_n4", 0)) >= 1 and int(r2.bt.stats.get("inyeon_up", 0)) >= 1, "stats 4명 · 초월 연쇄")
	_ok(not r2.bt._gain_up.is_empty(), "같은 인연 초월 기 충전 가속 대상")

	# (h) 무작위 덱 (불멸 6 · 초월 2 · 기인 1) 20판 —— 기인/초월 참여 연쇄가 실제로 나오나 (횟수만)
	var kiins := []
	for k in DB.C:
		if DB.C[k].kind == "kiin" and DB.inyeon_card(k) and not DB.inyeon_of(k).is_empty():
			kiins.append(k)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1112
	var tot := {}
	for g in 20:
		var decks := []
		for side in 2:
			var d := []
			var ps := []
			for spec in [[7, 6], [6, 2]]:
				var pool: Array = DB.by_tier(spec[0])
				var n := 0
				while n < spec[1]:
					var k: String = pool[rng.randi() % pool.size()]
					if not ps.has(DB.person(k)):
						d.append(k)
						ps.append(DB.person(k))
						n += 1
			while true:
				var k: String = kiins[rng.randi() % kiins.size()]
				if not ps.has(DB.person(k)):
					d.append(k)
					break
			decks.append(d)
		var res: Dictionary = RtBattle.make(rng.randi() % 100000).run(DB.auto_place(decks[0], "eorin"), "eorin", 100, null, DB.auto_place(decks[1], "hagik"), "hagik", 100, null,
			"", "", [], {"A": "smart", "B": "smart"})
		for key in ["inyeon_joint", "inyeon_kiin", "inyeon_kiin_fin", "inyeon_up", "inyeon_n4", "inyeon_theme", "inyeon_fin"]:
			tot[key] = int(tot.get(key, 0)) + int(res.stats.get(key, 0))
	print("(h) 무작위 20판 (불멸 6 · 초월 2 · 기인 1): 합동 %d · 기인이 연 연쇄 %d (마무리 %d) · 초월 낀 연쇄 %d · 4명 %d · 주제 %d · 인연기 %d" % [
		tot.inyeon_joint, tot.inyeon_kiin, tot.inyeon_kiin_fin, tot.inyeon_up, tot.inyeon_n4, tot.inyeon_theme, tot.inyeon_fin])
	_ok(tot.inyeon_theme > 0, "무작위 덱에서 주제가 터진다")
