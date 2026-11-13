extends Node
## 대표 덱 리그전 —— 실행: godot --headless --path . res://tests/meta.tscn [-- --games=60 --tiers=4,5,6,7,8]
##
## 등급마다 대표 덱 여섯 가지를 서로 붙여 상성표를 낸다. 덱 = 그 갈래 카드 중 6장(판마다 무작위) + 같은 등급 무작위 3장.
##   돌파: 돌파 특기가 붙은 기병   표적: 표적 특기가 붙은 궁병·인물   화공 · 수공: 그 계열 카드
##   창병: 창병 카드   책략: 책사·술사·모사·유생 카드
## 목표: 어떤 덱도 전체 승률 60% 를 넘지 않고, 덱마다 유리한 상대와 불리한 상대가 있다.
## 양쪽 영리 AI, 홀수 판은 진영을 바꾼다.

const FORMS := ["eorin", "hagik", "bongsi", "anwol", "bangwon", "anhaeng", "chuhaeng", "jangsa"]
const ARCH := ["돌파", "표적", "화공", "수공", "창병", "책략"]
const NOT_DECK := ["사마의", "조인", "허저", "전위", "정봉"]      # 맞수 특기만 가진 인물
var games := 60


func _ready() -> void:
	var args := {}
	for s in OS.get_cmdline_user_args():
		var kv := s.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	games = int(args.get("games", "60"))
	var tiers := Array(str(args.get("tiers", "4,5,6,7,8")).split(",")).map(func(x): return int(x))
	var t0 := Time.get_ticks_msec()
	for t in tiers:
		var core := {}
		for a in ARCH:
			core[a] = _core(t, a)
		var names := ARCH.filter(func(a): return core[a].size() >= 3)
		var tot := {}
		var cnt := {}
		var rows := []
		for a in names:
			var row := "  %s%s" % [a, " ".repeat(3)]
			for b in names:
				if a == b:
					row += "   —  "
					continue
				var w := _match(t, core[a], core[b], ARCH.find(a) * 10 + ARCH.find(b))
				row += " %4.0f%%" % w
				tot[a] = tot.get(a, 0.0) + w
				cnt[a] = cnt.get(a, 0) + 1
			rows.append(row)
		print("━━ %s (%d판씩) —— 줄의 덱이 칸의 덱을 이긴 비율" % [DB.TIER[t].n, games])
		var head := "        "
		for b in names:
			head += "  %s" % b
		print(head)
		for r in rows:
			print(r)
		var summ := []
		for a in names:
			summ.append("%s %.0f%%" % [a, tot[a] / cnt[a]])
		print("  전체: " + " · ".join(summ))
	print("소요 %.1f초" % ((Time.get_ticks_msec() - t0) / 1000.0))
	get_tree().quit()


func _core(t: int, a: String) -> Array:
	return DB.by_tier(t).filter(func(k):
		if NOT_DECK.has(DB.person(k)): return false
		var c: Dictionary = DB.C[k]
		match a:
			"창병": return c.tag == "창병"
			"책략": return DB.INT_TAGS.has(c.tag)
		var ps = DB.passives_of(k)
		return ps != null and (ps.traits + ps.groups).any(func(x): return x.attr == a))


func _deck(core: Array, pool: Array, rng: RandomNumberGenerator) -> Array:
	var d := core.duplicate()
	while d.size() > 6:
		d.remove_at(rng.randi() % d.size())
	while d.size() < 9:
		d.append(pool[rng.randi() % pool.size()])
	return d


func _match(t: int, ca: Array, cb: Array, sd0: int) -> float:
	var rng := RandomNumberGenerator.new()
	rng.seed = 4000 + t * 97 + sd0
	var pool: Array = DB.by_tier(t)
	var w := 0.0
	for i in games:
		var a := _deck(ca, pool, rng)
		var b := _deck(cb, pool, rng)
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
	return w / games * 100
