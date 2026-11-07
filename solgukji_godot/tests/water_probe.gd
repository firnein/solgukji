extends Node
## 수공 점검 —— 실행: godot --headless --path . res://tests/water_probe.tscn [-- --games=30 --tier=5,6,7,8]
## 수공 특기(attr "수공")를 많이 가진 9장 덱(수공 덱)을 같은 등급 무작위 덱 · 화공 덱 · 기병 덱과 실시간 엔진으로 붙인다.
## 판마다 같은 시드 · 진형으로 수공 켬/끔(Battle.water_enabled)을 나란히 재고, 자리를 바꿔 두 번 싸운다.
## 목표: 같은 등급 무작위 상대 켬 − 끔 = 0 ~ +10%p, 화공 덱 · 기병 덱의 맞수가 될 것.

const FORMS := ["eorin", "hagik", "bongsi", "anwol", "bangwon", "anhaeng", "chuhaeng", "jangsa"]
var games := 30
var rng := RandomNumberGenerator.new()


func _ready() -> void:
	var args := {}
	for s in OS.get_cmdline_user_args():
		var kv := s.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	games = int(args.get("games", "30"))
	var tiers := []
	for t in str(args.get("tier", "5,6,7,8")).split(",", false):
		tiers.append(int(t))
	rng.seed = 777
	if args.has("dbg"):
		for t in tiers:
			for at in ["둔화", "도트"]:
				var n := 0
				for k in DB.by_tier(t):
					if _attr_n(k, at) >= 1.0: n += 1
				print("%s %s 카드 %d / %d" % [DB.TIER[t].n, at, n, DB.by_tier(t).size()])
		get_tree().quit()
		return
	for t in tiers:
		var rows := []
		for sc in ["수공/무작위", "수공/화공", "기병/수공섞음"]:
			var on := _run(t, sc, true)
			var off := _run(t, sc, false)
			rows.append("%s 켬 %.0f%% 끔 %.0f%% (%+.0f)" % [sc, on * 100, off * 100, (on - off) * 100])
		print("%s: %s" % [DB.TIER[t].n, " | ".join(rows)])
	Battle.water_enabled = true
	get_tree().quit()


## 같은 시드로 켬/끔 한 번씩 돌리려고 시드를 다시 맞춘다
func _run(t: int, sc: String, water: bool) -> float:
	rng.seed = 1000 + t * 7 + sc.length()
	Battle.water_enabled = water
	var w := 0.0
	for g in games:
		var mine: Array
		var foe: Array
		if sc == "수공/무작위":
			mine = _deck(t, "attr", "둔화", [])
			foe = _deck(t, "rand", "", [])
		elif sc == "수공/화공":
			mine = _deck(t, "attr", "둔화", [])
			foe = _deck(t, "attr", "도트", mine)
		else:
			mine = _deck(t, "tag", "기병", [])
			foe = _deck(t, "attr", "둔화", mine, 5)
		var fa: String = FORMS[rng.randi() % FORMS.size()]
		var fb: String = FORMS[rng.randi() % FORMS.size()]
		var seed := rng.randi() % 1000000
		var a := DB.auto_place(mine, fa)
		var b := DB.auto_place(foe, fb)
		var r1 := RtBattle.make(seed).run(a, fa, 100, null, b, fb, 100, null, "", "", [], {"A": "smart", "B": "smart"})
		var r2 := RtBattle.make(seed).run(DB.auto_place(foe, fb), fb, 100, null, DB.auto_place(mine, fa), fa, 100, null, "", "", [], {"A": "smart", "B": "smart"})
		w += (1.0 if r1.win else (0.5 if r1.draw else 0.0)) + (1.0 if (not r2.win and not r2.draw) else (0.5 if r2.draw else 0.0))
	return w / (games * 2)


## 덱 만들기 —— kind: attr(특기 축 이름 — 수공=둔화 · 화공=도트 — 을 많이 가진 순) · tag(그 병종) · rand. want 가 있으면 앞 want 장만 그 기준, 나머지는 무작위
func _deck(t: int, kind: String, key: String, avoid: Array, want := 9) -> Array:
	var pool: Array = DB.by_tier(t)
	var scored := []
	for k in pool:
		var s := 0.0
		if kind == "attr":
			s = _attr_n(k, key)
		elif kind == "tag":
			s = 3.0 if DB.C[k].tag == key else 0.0
		scored.append([s + rng.randf() * 0.9, k])
	scored.sort_custom(func(x, y): return x[0] > y[0])
	var deck := []
	for e in scored:
		if kind == "rand" or deck.size() >= want:
			break
		var k: String = e[1]
		if (kind == "attr" and e[0] < 1.0):
			break
		if deck.any(func(x): return DB.person(x) == DB.person(k)) or avoid.any(func(x): return DB.person(x) == DB.person(k)):
			continue
		deck.append(k)
	var guard := 0
	while deck.size() < 9 and guard < 500:
		guard += 1
		var k: String = pool[rng.randi() % pool.size()]
		if not deck.any(func(x): return DB.person(x) == DB.person(k)) and not avoid.any(func(x): return DB.person(x) == DB.person(k)):
			deck.append(k)
	return deck


func _attr_n(k: String, attr: String) -> float:
	var ps = DB.passives_of(k)
	if ps == null:
		return 0.0
	var n := 0.0
	for x in ps.traits + ps.groups:
		if attr == "둔화":     # 수공 = 수몰을 걸거나 · 깔거나 · 막는 특기 (축 이름이 둔화가 아닌 금색 · 신화 특기까지)
			var m: Dictionary = x.get("m", {})
			for wk in ["soak", "tide", "drown", "flood_slow", "flood_res", "open_slow", "flow", "water_amp", "water_hit"]:
				if m.has(wk):
					n += 1.0
		elif x.attr == attr:
			n += 1.0
	return n
