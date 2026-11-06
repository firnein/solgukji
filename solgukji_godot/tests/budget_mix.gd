extends Node
## 같은 비용 덱 맞대결 (11/7 사용자: 초월 · 기인이 버려지고 신화 · 불멸로만 덱이 꾸려진다 —— 덱 다양성)
## 실행: godot --headless --path . res://tests/budget_mix.tscn [-- --games=40]
## 비용 = 기본패 환산 (재료를 끝까지 풀어 센 기본패 수, supply_check 와 같다). 비용이 비슷한 세 덱을 붙인다:
##   최상위: 가장 높은 등급을 최대한 + 남는 칸은 희귀
##   섞음:   불멸 · 초월 · 기인 · 전설을 고루
##   중간:   초월 · 기인 위주
## 비용이 같은데 최상위 덱이 크게 이기면 —— 보급이 모자라도 위 등급만 모은다(초월 · 기인이 손해인 카드).
## 비슷하면 —— 보급이 칸보다 먼저 모자라게 하면 중간 등급이 덱에 남는다.

var cost := {}


func _cost(k: String) -> float:
	if cost.has(k):
		return cost[k]
	var v := 1.0
	if DB.C[k].tier > 1 and DB.RECOF.has(k):
		v = 0.0
		for m in DB.RECOF[k]:
			if DB.C.has(str(m)):
				v += _cost(str(m))
	cost[k] = v
	return v


func _pool(g: String) -> Array:
	var t: int = {"신화": 8, "불멸": 7, "초월": 6, "기인": 5, "전설": 5, "희귀": 4}[g]
	return DB.by_tier(t).filter(func(k): return (g == "기인") == DB.is_kiin(k))


## 구성 {등급: 장수} 대로 무작위 9장 (같은 인물 겹치지 않게)
func _deck(mix: Dictionary, rng: RandomNumberGenerator) -> Array:
	var out := []
	for g in mix:
		var src := _pool(g)
		for i in int(mix[g]):
			var cand := src.filter(func(k): return not out.any(func(x): return DB.person(x) == DB.person(k)))
			out.append(cand[rng.randi() % cand.size()])
	return out


func _avg_cost(mix: Dictionary) -> float:
	var s := 0.0
	for g in mix:
		var src := _pool(g)
		var a := 0.0
		for k in src:
			a += _cost(k)
		s += a / src.size() * int(mix[g])
	return s


func _ready() -> void:
	var args := {}
	for s in OS.get_cmdline_user_args():
		var kv := s.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	var games: int = int(args.get("games", "40"))
	var sets := [
		["약 430", {"최상위": {"불멸": 4, "희귀": 5}, "섞음": {"불멸": 2, "초월": 3, "기인": 2, "전설": 2}, "중간": {"초월": 8, "기인": 1}}],
		["약 620", {"최상위": {"신화": 1, "불멸": 5, "희귀": 3}, "섞음": {"신화": 1, "불멸": 3, "초월": 3, "기인": 2}, "중간": {"신화": 1, "불멸": 2, "초월": 6}}],
		["약 790", {"최상위": {"신화": 1, "불멸": 7, "희귀": 1}, "섞음": {"신화": 1, "불멸": 6, "초월": 2}, "중간": {"신화": 1, "불멸": 4, "초월": 4}}],
	] if args.get("set", "") == "new" else [      # --set=new —— 11/7 초월 조합 비용을 낮춘 뒤 (약 48) 비용을 다시 맞춘 구성
		["약 430", {"최상위": {"불멸": 4, "희귀": 5}, "섞음": {"불멸": 2, "초월": 2, "기인": 3, "전설": 2}, "중간": {"초월": 5, "기인": 3, "전설": 1}}],
		["약 620", {"최상위": {"신화": 1, "불멸": 5, "희귀": 3}, "섞음": {"신화": 1, "불멸": 3, "초월": 2, "기인": 3}, "중간": {"신화": 1, "불멸": 1, "초월": 5, "기인": 2}}],
		["약 800", {"최상위": {"신화": 1, "불멸": 7, "희귀": 1}, "섞음": {"신화": 1, "불멸": 5, "초월": 2, "기인": 1}, "중간": {"신화": 1, "불멸": 3, "초월": 5}}],
	]
	if args.get("set", "") == "rr":      # --set=rr —— 비용 약 620 리그전: 중간 등급을 섞은 덱이 고를 만한가
		sets = [["약 620 리그전", {"몰빵": {"신화": 1, "불멸": 5, "희귀": 3}, "초월섞음": {"신화": 1, "불멸": 4, "초월": 2, "기인": 1, "희귀": 1},
			"기인섞음": {"신화": 1, "불멸": 4, "기인": 3, "희귀": 1}, "고루": {"신화": 1, "불멸": 3, "초월": 3, "기인": 2}}]]
	if args.get("set", "") == "rr430":
		sets = [["약 430 리그전", {"몰빵": {"불멸": 4, "희귀": 5}, "초월섞음": {"불멸": 3, "초월": 2, "기인": 1, "전설": 1, "희귀": 2},
			"기인섞음": {"불멸": 3, "기인": 4, "희귀": 2}, "고루": {"불멸": 2, "초월": 3, "기인": 2, "전설": 2}}]]
	if args.get("set", "") == "rr790":
		sets = [["약 790 리그전", {"몰빵": {"신화": 1, "불멸": 7, "희귀": 1}, "초월섞음": {"신화": 1, "불멸": 6, "초월": 2},
			"기인섞음": {"신화": 1, "불멸": 6, "기인": 2}, "고루": {"신화": 1, "불멸": 5, "초월": 2, "기인": 1}}]]
	if args.has("only"):      # --only=1,2 —— 몇 번째 구간만 (0부터)
		var keep: Array = Array(str(args.only).split(",")).map(func(x): return int(x))
		var picked := []
		for i in sets.size():
			if keep.has(i):
				picked.append(sets[i])
		sets = picked
	for st in sets:
		var mixes: Dictionary = st[1]
		var desc := []
		for nm in mixes:
			desc.append("%s(%s · 비용 %d)" % [nm, " ".join(mixes[nm].keys().map(func(g): return "%s%d" % [g, mixes[nm][g]])), _avg_cost(mixes[nm])])
		print("── 비용 %s: %s" % [st[0], " / ".join(desc)])
		var names: Array = mixes.keys()
		for i in names.size():
			for j in range(i + 1, names.size()):
				var rng := RandomNumberGenerator.new()
				rng.seed = 900 + i * 10 + j
				var w := 0.0
				for g in games:
					var a := DB.auto_place(_deck(mixes[names[i]], rng), "eorin")
					var b := DB.auto_place(_deck(mixes[names[j]], rng), "eorin")
					var sd := rng.randi() % 1000000
					var r1 := RtBattle.make(sd).run(a, "eorin", 100, null, b, "eorin", 100, null, "", "", [], {"A": "smart", "B": "smart"})
					var r2 := RtBattle.make(sd).run(b, "eorin", 100, null, a, "eorin", 100, null, "", "", [], {"A": "smart", "B": "smart"})
					w += (1.0 if r1.win else (0.5 if r1.draw else 0.0)) + (1.0 if (not r2.win and not r2.draw) else (0.5 if r2.draw else 0.0))
				print("   %s 대 %s: %.0f%%" % [names[i], names[j], w / (games * 2.0) * 100])
	get_tree().quit()
