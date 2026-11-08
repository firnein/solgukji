extends Node
## 11/9 원랜디식 역할 재배치 측정 (tools/scripts/role_assign.py) —— 비용을 맞춘 덱끼리, 같은 인물 겹침 없이
## 실행: godot --headless --path . res://tests/role_mix.tscn -- --pairs=불멸6+기인2+초월1:불멸7+희귀2 [--games=40 --seed=900 --cost]
## 덱 = 조각을 + 로 이음. 조각 = <등급><거르기?><장수 수>
##   등급: 신화 · 불멸 · 초월 · 기인 · 전설 · 희귀
##   거르기 (기인): 대표 역할 이름 (방깎 · 결계 · 기절 · 둔화 · 공깎 · 철벽 · 도트 · 치료 · 지원) · 핵심(방깎 · 결계 · 기절 · 둔화) · 비핵심(나머지)
##   거르기 (나머지 등급): 창기 (창병 · 기병) · 물리 (창 · 기 · 궁 · 도적) · 책략 (책사 · 모사 · 술사 · 유생)
## 판마다 덱을 새로 뽑고 같은 시드로 자리를 바꿔 두 번 —— 앞 덱의 승률. 비용 = 기본패 환산 (budget_mix 와 같다)
## --cost → 덱마다 평균 비용만 적고 끝

const CORE := ["방깎", "결계 깨기", "기절", "둔화"]
const ROLE_ALIAS := {"결계": "결계 깨기"}
const GRADES := {"신화": 8, "불멸": 7, "초월": 6, "기인": 5, "전설": 5, "희귀": 4}
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


## 조각 → [후보 카드, 장수 수]
func _piece(s: String) -> Array:
	var g := s.substr(0, 2)
	var rest := s.substr(2)
	var n := 0
	var i := rest.length()
	while i > 0 and rest[i - 1] >= "0" and rest[i - 1] <= "9":
		i -= 1
	n = int(rest.substr(i))
	var f := rest.substr(0, i)
	var t: int = GRADES[g]
	var src: Array = DB.by_tier(t).filter(func(k): return (g == "기인") == DB.is_kiin(k) and not DB.is_foe(k))
	if f != "":
		var kr: Dictionary = DB.PSV.get("role", {}).get("kiin", {})
		f = ROLE_ALIAS.get(f, f)
		src = src.filter(func(k):
			var tag: String = DB.C[k].tag
			if g == "기인":
				var role: String = str(kr.get(DB.person(k), ["", 1, ""])[2])
				if f == "핵심": return CORE.has(role)
				if f == "비핵심": return not CORE.has(role)
				return role == f
			if f == "창기": return tag in ["창병", "기병"]
			if f == "물리": return DB.dmg_kind(tag) == "phys"
			if f == "책략": return DB.dmg_kind(tag) == "int"
			push_error("모르는 거르기 " + f)
			return false)
	return [src, n]


func _deck(spec: String, rng: RandomNumberGenerator) -> Array:
	var out := []
	for s in spec.split("+"):
		var pc := _piece(s)
		for i in int(pc[1]):
			var cand: Array = pc[0].filter(func(k): return not out.any(func(x): return DB.person(x) == DB.person(k)))
			out.append(cand[rng.randi() % cand.size()])
	return out


func _avg_cost(spec: String) -> float:
	var s := 0.0
	for p in spec.split("+"):
		var pc := _piece(p)
		var a := 0.0
		for k in pc[0]:
			a += _cost(k)
		s += a / maxf(1, pc[0].size()) * int(pc[1])
	return s


func _ready() -> void:
	var args := {}
	for s in OS.get_cmdline_user_args():
		var kv := s.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	var games := int(args.get("games", "40"))
	var seed0 := int(args.get("seed", "900"))
	var pi := 0
	for pr in str(args.get("pairs", "")).split(",", false):
		var ab := pr.split(":")
		if args.has("cost"):
			print("%s 비용 %.0f · %s 비용 %.0f" % [ab[0], _avg_cost(ab[0]), ab[1], _avg_cost(ab[1])])
			continue
		var rng := RandomNumberGenerator.new()
		rng.seed = seed0 + pi * 17
		pi += 1
		var w := 0.0
		for g in games:
			var a := DB.auto_place(_deck(ab[0], rng), "eorin")
			var b := DB.auto_place(_deck(ab[1], rng), "eorin")
			var sd := rng.randi() % 1000000
			var r1 := RtBattle.make(sd).run(a, "eorin", 100, null, b, "eorin", 100, null, "", "", [], {"A": "smart", "B": "smart"})
			var r2 := RtBattle.make(sd).run(b, "eorin", 100, null, a, "eorin", 100, null, "", "", [], {"A": "smart", "B": "smart"})
			w += (1.0 if r1.win else (0.5 if r1.draw else 0.0)) + (1.0 if (not r2.win and not r2.draw) else (0.5 if r2.draw else 0.0))
		print("%s (%.0f) 대 %s (%.0f): %.1f%%" % [ab[0], _avg_cost(ab[0]), ab[1], _avg_cost(ab[1]), w / (games * 2.0) * 100])
	get_tree().quit()
