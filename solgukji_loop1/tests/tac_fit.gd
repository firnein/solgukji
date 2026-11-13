extends Node
## 작전 궁합 점검 —— 실행: godot --headless --path . res://tests/tac_fit.tscn [-- --cls=기병 --games=40 --pv=1000]
## 한 병종이 9장 중 5장인 덱(나머지는 아무 병종)을 만들어, 같은 상대(균형)에게 작전 셋을 각각 써 본다.
## 같은 두 덱을 자리를 바꿔 두 번 붙인다. 균형 대비 맹공 · 굳히기의 승률 차이를 병종마다 본다.

const FORMS := ["eorin", "hagik", "bongsi", "anwol", "bangwon", "anhaeng", "chuhaeng", "jangsa"]
const CLS := ["창병", "기병", "궁병", "도적", "책사", "유생", "술사", "모사"]


func _ready() -> void:
	var args := {}
	for s in OS.get_cmdline_user_args():
		var kv := s.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	var games := int(args.get("games", "40"))
	var pv := float(args.get("pv", "1000"))
	for c in ([args.cls] if args.has("cls") else CLS):
		_run(c, games, pv)
	get_tree().quit()


func _run(cls: String, games: int, pv: float) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 900 + CLS.find(cls)
	var w := {}
	for t in Run.TACS:
		w[t] = 0.0
	for g in games:
		var x := _deck(pv, cls, rng)
		var y := _deck(pv * rng.randf_range(0.95, 1.05), "", rng)
		var fx: String = FORMS[rng.randi() % FORMS.size()]
		var fy: String = FORMS[rng.randi() % FORMS.size()]
		var seed := rng.randi() % 1000000
		for t in Run.TACS:
			var p: String = Run.TACS[t].pol
			var r1 := RtBattle.make(seed).run(DB.auto_place(x, fx), fx, 100, null, DB.auto_place(y, fy), fy, 100, null, "", "", [], {"A": p, "B": "smart"})
			var r2 := RtBattle.make(seed).run(DB.auto_place(y, fy), fy, 100, null, DB.auto_place(x, fx), fx, 100, null, "", "", [], {"A": "smart", "B": p})
			w[t] += (1.0 if r1.win else (0.5 if r1.draw else 0.0)) + (1.0 if (not r2.win and not r2.draw) else (0.5 if r2.draw else 0.0))
	var base: float = w["균형"] / (games * 2.0)
	var out := []
	for t in Run.TACS:
		out.append("%s %+.1f" % [t, (w[t] / (games * 2.0) - base) * 100])
	print("%s 덱: 균형 승률 %.0f%% · 균형 대비 %s %%p" % [cls, base * 100, " · ".join(out.slice(1))])


## 전설 9장에서 무작위 자리를 한 등급씩 올리며 PV 를 쓰고, 5자리는 cls 병종으로 고른다 (그 등급에 없으면 아무거나)
func _deck(pv: float, cls: String, rng: RandomNumberGenerator) -> Array:
	var mid := func(t): return (DB.TIER[t].lo + DB.TIER[t].hi) / 2.0
	var tiers := []
	tiers.resize(9)
	tiers.fill(5)
	var spent: float = mid.call(5) * 9
	while true:
		var ok := []
		for i in 9:
			if tiers[i] < 8 and spent + mid.call(tiers[i] + 1) - mid.call(tiers[i]) <= pv:
				ok.append(i)
		if ok.is_empty():
			break
		var i: int = ok[rng.randi() % ok.size()]
		spent += mid.call(tiers[i] + 1) - mid.call(tiers[i])
		tiers[i] += 1
	var out := []
	for i in 9:
		var src: Array = DB.by_tier(tiers[i])
		if cls != "" and i < 5:
			var f := src.filter(func(k): return DB.C[k].tag == cls)
			if not f.is_empty():
				src = f
		out.append(src[rng.randi() % src.size()])
	return out
