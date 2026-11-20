extends Node
## 11/21 1.2 모사 16 · 유생 18 개성 점검 —— 행동 키가 실제로 발동하나 (횟수만. 밸런스 측정이 아니다)
## 실행: godot --headless --path . res://tests/sig_probe_scholar.tscn [-- --n=8 --who=가후,조조 --t=5]

const PEOPLE := ["가후", "초선", "사마의", "조조", "진궁", "등애", "원술", "정욱", "전풍", "이유", "맹달", "여범", "동소", "마속", "보즐", "심배",
	"유비", "순욱", "노숙", "사마휘", "법정", "미축", "대교", "소교", "장소", "채문희", "장완", "공융", "도겸", "비의", "간옹", "제갈근", "진군", "진림"]

const ALIAS := {"sig_mark_w": "mark", "sig_resist": "stres", "sig_sow": "sow", "sig_turncoat": "turncoat", "sig_confuse_break": "confuse_break"}


func _ready() -> void:
	var args := {}
	for arg in OS.get_cmdline_user_args():
		var kv := arg.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	var n := int(args.get("n", "8"))
	Battle.sig_enabled = true
	var who: Array = PEOPLE if not args.has("who") else Array(str(args["who"]).split(","))
	for person in who:
		var cards: Array = DB.C.keys().filter(func(k): return DB.person(k) == person and not DB.is_foe(k))
		cards.sort_custom(func(a, b): return DB.C[a].tier < DB.C[b].tier)
		for ck in cards:
			var tier: int = DB.C[ck].tier
			if args.has("t") and int(args["t"]) != tier:
				continue
			if args.has("desc"):      # 장수 상세창 고유 특기 글 · 수치 (턴 표현이 남았나)
				for t in DB.trait_list(ck):
					if t.unique:
						var line := "  [%s] %s —— %s" % [t.name, t.d, t.mt]
						print(("(턴!) " if line.contains("턴") else "") + person + " " + ck + line)
				continue
			var pool := DB.by_tier(tier).filter(func(k): return not DB.is_foe(k) and DB.person(k) != person)
			if args.has("mix"):      # 기 · 사기 계열은 고유기를 가진 윗등급 아군이 있어야 보인다 (3~4급은 고유기가 없다) —— 아군은 윗등급을 섞는다
				for tt in range(tier + 1, 9):
					pool += DB.by_tier(tt).filter(func(k): return not DB.is_foe(k) and DB.person(k) != person)
			var sum := {}
			var says := {}
			var mk := ""
			for i in n:
				var rng := RandomNumberGenerator.new()
				rng.seed = 93100 + i
				var a := [ck] + _pick(pool, rng, 8)
				var b := _pick(pool, rng, 9)
				var bt := RtBattle.new(93100 + i)
				var r: Dictionary = bt.run(DB.auto_place(a, "eorin"), "eorin", 100, null, DB.auto_place(b, "hagik"), "hagik", 100, null, "", "", [], {"A": "smart", "B": "smart"})
				var mdict := {}
				for u in bt.units:
					if u.c.id == ck:
						mdict = u.m
						if i == 0:
							mk = str(u.m)
				if args.has("morale"):
					var lo := 999
					var cnt := 0
					for e in r.ev:
						for row in e.s:
							lo = mini(lo, int(row[1]))
							if int(row[1]) < 55: cnt += 1
					print("   사기 최저 ", lo, " · 55 미만 행 ", cnt)
				if args.has("raw"):
					print("   raw ", bt.stats.keys().filter(func(k): return str(k).begins_with("sig_")).map(func(k): return "%s=%s" % [k, bt.stats[k]]))
				for k in bt.stats:
					if str(k).begins_with("sig_"):
						var mkey: String = ALIAS.get(k, str(k).substr(4))
						var other := false      # 같은 키를 가진 다른 부대가 판에 있으면 그 판은 세지 않는다 (내 발동이 아니다)
						for u in bt.units:
							if u.c.id != ck and float(u.m.get(mkey, 0.0)) != 0.0:
								other = true
						if not other and float(mdict.get(mkey, 0.0)) != 0.0:
							sum[k] = int(sum.get(k, 0)) + int(bt.stats[k])
				for e in r.ev:
					if e.get("sig", false) and str(e.get("t", "")).contains(person):
						var t := str(e.get("t", ""))
						var head := t.split(" ——")[0]
						var key := head.substr(head.rfind("의 ") + 2)
						says[key] = int(says.get(key, 0)) + 1
			print("%s %s(%d급 %s) %d판 · m=%s\n    통계 %s · 말풍선 %s" % [person, ck, tier, DB.C[ck].tag, n, mk, sum, says])
	get_tree().quit()


func _pick(pool: Array, rng: RandomNumberGenerator, cnt: int) -> Array:
	var out := []
	var people := []
	var cand := pool.duplicate()
	while out.size() < cnt and not cand.is_empty():
		var k: String = cand.pop_at(rng.randi_range(0, cand.size() - 1))
		if not people.has(DB.person(k)):
			out.append(k)
			people.append(DB.person(k))
	return out
