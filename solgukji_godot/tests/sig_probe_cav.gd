extends Node
## 1.2 기병 22명 개성 점검 —— 첫 등장 등급에서 몇 판 돌려 행동 키가 실제로 발동하나 (횟수만. 밸런스 측정이 아니다)
## 실행: godot --headless --path . res://tests/sig_probe_cav.tscn [-- --n=10 --base --only=여포 --list]
##  --base : 말풍선 · 우회를 끄고 계수만 (전/후 비교용)  --list : 고유 특기 글 · 키만 출력

const PEOPLE := ["여포", "조운", "마초", "장료", "손책", "장합", "공손찬", "마등", "동탁", "원소", "문추", "화웅", "마대", "조홍", "곽회", "한수", "반장", "오반", "안량", "오의", "하후패", "한당"]

func _ready() -> void:
	var args := {}
	for arg in OS.get_cmdline_user_args():
		var kv := arg.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	var n := int(args.get("n", "10"))
	load("res://scripts/sig_rt.gd").set_cav_fx(not args.has("base"))
	for person in PEOPLE:
		if args.has("only") and str(args.only) != person:
			continue
		var cards: Array = DB.C.keys().filter(func(k): return DB.person(k) == person and not DB.is_foe(k))
		var ck: String = ""
		for c in cards:
			if ck == "" or DB.C[c].tier < DB.C[ck].tier:
				ck = c
		if ck == "":
			print("%s —— 카드 없음" % person)
			continue
		var tier: int = DB.C[ck].tier
		for t in DB.trait_list(ck):
			if t.unique:
				print("  [%s] %s —— %s" % [t.name, t.d, t.mt])
		if args.has("list"):
			continue
		var pool := DB.by_tier(tier).filter(func(k): return not DB.is_foe(k) and DB.person(k) != person)
		var sum := {}
		var sec := 0.0
		var says := 0
		var dev := 0.0         # 위치 기록 —— 이 부대가 첫 접촉까지 지나간 길이 / 직선 거리
		var devn := 0
		var lat := 0.0
		var latn := 0
		for i in n:
			var rng := RandomNumberGenerator.new()
			rng.seed = 12200 + i
			var a := [ck] + _pick(pool, rng, 8)
			var b := _pick_mix(pool, rng)      # 적 9부대 —— 궁병 셋 · 기병 둘을 섞어 후열 노리기 · 기병 견제를 볼 수 있게
			var bt := RtBattle.new(12200 + i)
			var r: Dictionary = bt.run(DB.auto_place(a, "eorin"), "eorin", 100, null, DB.auto_place(b, "hagik"), "hagik", 100, null, "", "", [], {"A": "smart", "B": "smart"})
			sec += float(r.len)
			for k in bt.stats:
				if str(k).begins_with("sig_") and str(k).ends_with("@" + DB.C[ck].name):
					var kk := str(k).substr(4).split("@")[0]
					sum[kk] = int(sum.get(kk, 0)) + int(bt.stats[k])
			for e in r.ev:
				if e.get("sig", false) and str(e.get("t", "")).contains(DB.C[ck].name):
					says += 1
			var tr: Array = r.track
			var ui := -1
			for j in bt.units.size():
				if bt.units[j].c.name == DB.C[ck].name:
					ui = j
					break
			if ui >= 0 and tr.size() > 2:
				var path := 0.0
				var first: Array = tr[0][1][ui]
				var last: Array = first
				for f in tr:
					var row2: Array = f[1][ui]
					path += Vector2(row2[0], row2[1]).distance_to(Vector2(last[0], last[1]))
					last = row2
					if int(row2[4]) == 1:
						break
				var sl := Vector2(first[0], first[1]).distance_to(Vector2(last[0], last[1]))
				if sl > 50.0:
					dev += path / sl
					devn += 1
				for f in tr:      # 출발 2초 뒤 옆(y)으로 얼마나 벗어났나 —— 우회 확인
					if float(f[0]) >= 2.0:
						lat += absf(float(f[1][ui][1]) - float(first[1]))
						latn += 1
						break
		print("%s %s(%d급) %d판 %.0f초 —— %s · 말풍선 %d · 길/직선 %.2f · 2초 옆이동 %.0f" % [person, ck, tier, n, sec / n, sum, says, dev / maxf(1, devn), lat / maxf(1, latn)])
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


## 적 9부대: 궁병 셋 + 기병 둘 + 나머지 (같은 인물은 한 번만)
func _pick_mix(pool: Array, rng: RandomNumberGenerator) -> Array:
	var out := []
	var people := []
	for tag in ["궁병", "궁병", "궁병", "기병", "기병"]:
		var cand := pool.filter(func(k): return DB.C[k].tag == tag and not people.has(DB.person(k)))
		if not cand.is_empty():
			var k: String = cand[rng.randi_range(0, cand.size() - 1)]
			out.append(k)
			people.append(DB.person(k))
	var cand2 := pool.duplicate()
	while out.size() < 9 and not cand2.is_empty():
		var k2: String = cand2.pop_at(rng.randi_range(0, cand2.size() - 1))
		if not people.has(DB.person(k2)):
			out.append(k2)
			people.append(DB.person(k2))
	return out
