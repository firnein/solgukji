extends Node
## 특기 축 점검 —— 실행: godot --headless --path . res://tests/attr.tscn [-- --attr=물리|책략|도트|공깎|책략깎|방깎|책방깎|둔화|혼란|철벽|인덕 --games=200]
##
## 축 덱: 그 등급에서 그 축 특기(고유 특기 포함)가 붙은 카드 중 6장(많으면 판마다 무작위) + 같은 등급 무작위로 9장.
##  ① 축 덱 vs 같은 등급 무작위 —— 그 축을 켰을 때와 껐을 때 (Battle.axis_off, 차이가 축의 몫)
##  ② 축 덱 vs 한 등급 위 무작위 —— 등급 격차가 그대로인지
## 양쪽 영리 AI, 홀수 판은 진영을 바꿔 붙인다.

const FORMS := ["eorin", "hagik", "bongsi", "anwol", "bangwon", "anhaeng", "chuhaeng", "jangsa"]
const COUNTER := {}       # 맞수 인물 (2026-10-30 축 개편 뒤로는 비워 둔다)
const NOT_DECK := {}
var games := 200
var attr := "물리"


func _ready() -> void:
	var args := {}
	for s in OS.get_cmdline_user_args():
		var kv := s.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	games = int(args.get("games", "200"))
	if args.has("tmul"):                  # 턴 배율 (Battle.turn_mul) 바꿔 보기
		Battle.auto_turn = false
		Battle.set_turn_mul(float(args.tmul))
	attr = str(args.get("attr", "물리"))
	Battle.ults_enabled = not args.has("noult")
	Battle.counter_charge = args.has("charge")
	Battle.counter_enabled = not args.has("nocls")
	for k in ["dr", "int_dr", "counter", "amp", "dur"]:       # 철벽 수치 바꿔 보기 (--g_dr=0 처럼)
		if args.has("g_" + k): DB.PSV.guard[k] = float(args["g_" + k])
	for k in DB.PSV.virtue:                  # 인덕 수치 (--v_moved=0.4 처럼)
		if args.has("v_" + k): DB.PSV.virtue[k] = float(args["v_" + k])
	if args.has("mend"):                     # 인술 치료 비율
		DB.PSV.traits["인술"].m["mend"] = float(args["mend"])
		DB._psv_cache.clear()
	var tiers: Array = Array(str(args.get("tiers", "3,4,5,6,7,8")).split(",")).map(func(x): return int(x))
	var t0 := Time.get_ticks_msec()
	var cp: String = COUNTER.get(attr, "")
	for t in tiers:
		var deck := _attr_cards(t, attr, cp)
		var ctr := DB.by_tier(t).filter(func(k): return DB.person(k) == cp)
		print("━━ %s · %s %d장 (%s)%s" % [DB.TIER[t].n, attr, deck.size(), ", ".join(deck.map(func(k): return DB.C[k].name)),
			(" · %s 있음" % cp) if not ctr.is_empty() else ""])
		if deck.is_empty():
			continue
		_toggle(attr, false)
		var off := _match(t, deck, t, [], [])
		_toggle(attr, true)
		var on := _match(t, deck, t, [], [])
		print("  같은 등급 무작위: 켬 %.0f%% · 끔 %.0f%% (%s 몫 %+.0f%%p) · %.1f턴 · %s 비중 %.0f%% · %s" % [
			on.w, off.w, attr, on.w - off.w, on.turns, attr, on.share, on.note])
		print("    (끔: %s)" % off.note)
		if not ctr.is_empty():
			var c := _match(t, deck, t, ctr, [])
			print("  %s 든 상대: %.0f%% · %s 비중 %.0f%%" % [cp, c.w, attr, c.share])
		if t < 8:
			var up := _match(t, deck, t + 1, [], [])
			print("  한 등급 위 무작위: %.0f%%" % up.w)
	print("소요 %.1f초" % ((Time.get_ticks_msec() - t0) / 1000.0))
	get_tree().quit()


func _toggle(a: String, on: bool) -> void:
	if on: Battle.axis_off.erase(a)
	else: Battle.axis_off[a] = true


func _attr_cards(t: int, a: String, counter: String) -> Array:
	return DB.by_tier(t).filter(func(k):
		if DB.person(k) == counter or NOT_DECK.get(a, []).has(DB.person(k)): return false
		var ps = DB.passives_of(k)
		return ps != null and (ps.traits + ps.groups).any(func(x): return x.attr == a))


## 내 덱(core 6장 + 무작위)을 상대(foe_core + tf 등급 무작위)와 붙인다. foe_core 가 6장을 넘으면 판마다 6장만
func _match(t: int, core: Array, tf: int, foe_core: Array, _x: Array) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = 900 + t * 7 + tf
	var pool: Array = DB.by_tier(t).filter(func(k): return not core.has(k))
	var fpool: Array = DB.by_tier(tf).filter(func(k): return not foe_core.has(k))
	var w := 0.0
	var turns := 0
	var share := 0.0
	var dmg := 0.0
	var st := {}
	for i in games:
		var a := core.duplicate()
		while a.size() > 6:
			a.remove_at(rng.randi() % a.size())
		while a.size() < 9:
			a.append(pool[rng.randi() % pool.size()])
		var b := foe_core.duplicate()
		while b.size() > 6:
			b.remove_at(rng.randi() % b.size())
		while b.size() < 9:
			b.append(fpool[rng.randi() % fpool.size()])
		var fa: String = FORMS[rng.randi() % FORMS.size()]
		var fb: String = FORMS[rng.randi() % FORMS.size()]
		var sd := rng.randi() % 100000
		var flip := i % 2 == 1
		var pa := DB.auto_place(a, fa)
		var pb := DB.auto_place(b, fb)
		var r: Dictionary
		if flip:
			r = Battle.new(sd).run(pb, fb, 100, null, pa, fa, 100, null, "", "", [], {"A": "smart", "B": "smart"})
		else:
			r = Battle.new(sd).run(pa, fa, 100, null, pb, fb, 100, null, "", "", [], {"A": "smart", "B": "smart"})
		var won: bool = r.win != flip and not r.draw
		w += 1.0 if won else (0.5 if r.draw else 0.0)
		turns += r.turns
		var s: Dictionary = r.stats
		match attr:
			"도트": share += s.burn + s.fire_amp
			"철벽": share += s.counter_dmg
			"인덕": share += s.mends
			"물리", "책략": share += s.cleaves
			_: share += s.tac_amp
		dmg += s.dmg + s.burn + s.flood
		for k in s:
			st[k] = st.get(k, 0.0) + float(s[k])
	var per := func(k): return st.get(k, 0.0) / games
	var note := ""
	match attr:
		"도트": note = "점화 %.1f · 번짐 %.1f /판" % [per.call("ignites"), per.call("spreads")]
		"물리", "책략": note = "기세 %.1f · 추격 %.1f · 이웃 피해 %.0f · 처형 %.1f /판" % [per.call("kills_amp"), per.call("chases"), per.call("cleaves"), per.call("execs")]
		"공깎", "책략깎", "방깎", "책방깎": note = "깎기 %.1f회 · 깎은 양 %.0f /판" % [per.call("cut_n"), per.call("cuts")]
		"둔화": note = "침수 %.1f · 도강 %.1f · 휩쓸림 %.1f /판" % [per.call("soaks"), per.call("tides"), per.call("drowned")]
		"혼란": note = "혼란 %.1f · 위압 %.1f · 옮김 %.1f · 제 편 공격 %.1f /판" % [per.call("confuses"), per.call("awes"), per.call("passes"), per.call("turncoats")]
		"철벽": note = "방진 %.1f · 반격 %.1f · 사수 %.1f /판 (비중 = 반격 피해)" % [per.call("phalanx"), per.call("counters"), per.call("stands")]
		"인덕": note = "치료 %.0f · 분발 %.1f · 도원결의 %.2f /판 (비중 = 치료량)" % [per.call("mends"), per.call("moved"), per.call("oaths")]
	return {"w": w / games * 100, "turns": float(turns) / games, "share": share / maxf(1, dmg) * 100, "note": note,
		"doused": per.call("doused")}
