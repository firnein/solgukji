extends Node
## 덱빌딩 효과 점검 —— 실행: godot --headless --path . res://tests/deck.tscn [-- --games=150 --passive=1]
##
## 시너지 덱: 세력 시너지·병종 시너지·단체 특기 대상 수가 최대가 되도록 한 장씩 고른 9장 + 어울리는 진형.
## 무작위 덱: 같은 등급 무작위 9장 + 무작위 진형.
## 시너지 덱이 무작위 덱을 얼마나 이기는지가 "덱을 잘 짜면 이긴다"의 크기다.
## 덤으로 시너지 덱이 한 등급 위 무작위 덱을 상대로 몇 판이나 버티는지도 본다.

const FORMS := ["eorin", "hagik", "bongsi", "anwol", "bangwon", "anhaeng", "chuhaeng", "jangsa"]
var games := 150
var rng := RandomNumberGenerator.new()


func _ready() -> void:
	var args := {}
	for s in OS.get_cmdline_user_args():
		var kv := s.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	games = int(args.get("games", "150"))
	if args.get("passive", "1") == "0" and "passives_enabled" in Battle:
		Battle.passives_enabled = false
	rng.seed = 4242
	var use_p: bool = DB.has_method("passives_of") and args.get("passive", "1") != "0"
	print("특기 %s · %d판씩" % ["켬" if use_p else "끔", games])
	for t in [5, 6, 7, 8]:
		var same := _match(t, t, use_p)
		var up := _match(t, t + 1, use_p) if t < 8 else -1.0
		print("  %s: 시너지 덱 vs 무작위 덱 %.0f%%%s" % [DB.TIER[t].n, same * 100,
			"" if up < 0 else " · 시너지 덱 vs 한 등급 위 무작위 %.1f%%" % (up * 100)])
	get_tree().quit()


func _match(t_mine: int, t_foe: int, use_p: bool) -> float:
	var w := 0.0
	for g in games:
		var mine := _synergy_deck(t_mine, use_p)
		var foe := []
		var pool: Array = DB.by_tier(t_foe)
		for i in 9:
			foe.append(pool[rng.randi() % pool.size()])
		var fa := _best_form(mine)
		var fb: String = FORMS[rng.randi() % FORMS.size()]
		var r := Battle.new(rng.randi() % 1000000).run(DB.auto_place(mine, fa), fa, 100, null,
			DB.auto_place(foe, fb), fb, 100, null)
		w += 1.0 if r.win else (0.5 if r.draw else 0.0)
	return w / games


func _synergy_deck(t: int, use_p: bool) -> Array:
	var pool: Array = DB.by_tier(t)
	var deck := [pool[rng.randi() % pool.size()]]
	while deck.size() < 9:
		var best := ""
		var bs := -1e9
		for k in pool:
			var s := _score(deck + [k], use_p) + rng.randf() * 0.3
			if s > bs:
				bs = s
				best = k
		deck.append(best)
	return deck


func _score(deck: Array, use_p: bool) -> float:
	var fc := {}
	var tc := {}
	for k in deck:
		fc[DB.C[k].fac] = fc.get(DB.C[k].fac, 0) + 1
		tc[DB.C[k].tag] = tc.get(DB.C[k].tag, 0) + 1
	var s := 0.0
	for f in fc:
		for st in DB.D.SYN_STEP:
			if fc[f] >= st:
				s += 2.0
	for g in tc:
		for st in DB.D.TAGSYN_STEP:
			if tc[g] >= st:
				s += 1.5
	if use_p:
		var seen := {}
		for k in deck:
			var ps = DB.passives_of(k)
			if ps == null:
				continue
			for g in ps.groups:
				var w: float = [1.0, 0.5, 0.0][mini(seen.get(g.name, 0), 2)]     # 둘까지 겹친다
				seen[g.name] = seen.get(g.name, 0) + 1
				if g.scope == "all" or g.scope == "foe":
					s += 1.0 * w
					continue
				var n := 0
				for j in deck:
					if DB.passive_hits(g, k, j):
						n += 1
				s += 0.5 * mini(n, 6) * w
	return s


func _best_form(deck: Array) -> String:
	var best := "eorin"
	var bn := -1
	for f in FORMS:
		var n := 0
		for k in deck:
			if DB.D.FORMBOON[f].tags.has(DB.C[k].tag):
				n += 1
		if n > bn:
			bn = n
			best = f
	return best
