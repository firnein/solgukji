extends Node
## 화공 점검 —— 실행: godot --headless --path . res://tests/fire.tscn [-- --games=200]
##
## 화공 덱: 그 등급의 화공 카드 중 6장(많으면 판마다 무작위) + 같은 등급 무작위로 9장. 화공 카드 = data/passives.json fire.persons (사마의 제외).
##  ① 화공 덱 vs 같은 등급 무작위 —— 화공을 켰을 때와 껐을 때 (차이가 화공의 몫)
##  ② 화공 덱 vs 사마의(천우·우중)가 든 무작위 —— 맞수
##  ③ 화공 덱 vs 한 등급 위 무작위 —— 등급 격차가 그대로인지
## 양쪽 영리 AI, 홀수 판은 진영을 바꿔 붙인다.

const FORMS := ["eorin", "hagik", "bongsi", "anwol", "bangwon", "anhaeng", "chuhaeng", "jangsa"]
var games := 200


func _ready() -> void:
	var args := {}
	for s in OS.get_cmdline_user_args():
		var kv := s.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	games = int(args.get("games", "200"))
	var t0 := Time.get_ticks_msec()
	var fire_p: Array = DB.PSV.fire.persons.keys().filter(func(n): return n != "사마의")
	for t in [3, 4, 5, 6, 7, 8]:
		var fire := DB.by_tier(t).filter(func(k): return fire_p.has(DB.person(k)) and DB.passives_of(k) != null and DB.passives_of(k).get("fire") != null)
		var sma := DB.by_tier(t).filter(func(k): return DB.person(k) == "사마의")
		print("━━ %s · 화공 %d장 (%s)%s" % [DB.TIER[t].n, fire.size(), ", ".join(fire.map(func(k): return DB.C[k].name)),
			" · 사마의 있음" if not sma.is_empty() else ""])
		if fire.is_empty():
			continue
		Battle.fire_enabled = false
		var off := _match(t, fire, t, [])
		Battle.fire_enabled = true
		var on := _match(t, fire, t, [])
		print("  같은 등급 무작위: 화공 켬 %.0f%% · 끔 %.0f%% (화공 몫 %+.0f%%p) · %.1f턴 · 화상 비중 %.0f%% · 점화 %.1f · 번짐 %.1f /판" % [
			on.w, off.w, on.w - off.w, on.turns, on.share, on.ign, on.spr])
		if not sma.is_empty():
			var c := _match(t, fire, t, sma)
			print("  사마의 든 상대: %.0f%% · 화상 비중 %.0f%%" % [c.w, c.share])
		if t < 8:
			var up := _match(t, fire, t + 1, [])
			print("  한 등급 위 무작위: %.0f%%" % up.w)
	print("소요 %.1f초" % ((Time.get_ticks_msec() - t0) / 1000.0))
	get_tree().quit()


func _match(t: int, fire: Array, tf: int, foe_core: Array) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = 900 + t * 7 + tf
	var pool: Array = DB.by_tier(t).filter(func(k): return not fire.has(k))
	var fpool: Array = DB.by_tier(tf)
	var w := 0.0
	var turns := 0
	var burn := 0.0
	var amp := 0.0
	var dmg := 0.0
	var ign := 0
	var spr := 0
	for i in games:
		var a := fire.duplicate()
		while a.size() > 6:
			a.remove_at(rng.randi() % a.size())
		while a.size() < 9:
			a.append(pool[rng.randi() % pool.size()])
		var b := foe_core.duplicate()
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
		burn += r.stats.burn
		amp += r.stats.fire_amp
		dmg += r.stats.dmg + r.stats.burn
		ign += r.stats.ignites
		spr += r.stats.spreads
	return {"w": w / games * 100, "turns": float(turns) / games, "share": (burn + amp) / maxf(1, dmg) * 100,
		"ign": float(ign) / games, "spr": float(spr) / games}
