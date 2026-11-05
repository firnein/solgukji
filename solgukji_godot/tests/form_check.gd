extends Node
## 진형 점검 (11/5 사용자: 모든 진형의 특색이 올바른지, 전력에 영향을 주는지)
## 실행: godot --headless --path . res://tests/form_check.tscn [-- --games=40 --tier=7]
## ① 무작위 덱: 같은 덱 · 같은 상대 · 같은 시드로 진형만 바꿔 승률 (진형 자체의 힘)
## ② 우대 덱: 그 진형 우대 병종 4장 + 무작위 5장 —— 그 진형으로 둔 승률 대 어린진(기준)으로 둔 승률 (우대가 힘이 되는가)

const FORMS := ["eorin", "hagik", "bongsi", "anwol", "bangwon", "anhaeng", "chuhaeng", "jangsa"]


func _ready() -> void:
	var args := {}
	for s in OS.get_cmdline_user_args():
		var kv := s.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	var games := int(args.get("games", "40"))
	var t := int(args.get("tier", "7"))
	var pool: Array = DB.by_tier(t).filter(func(k): return not DB.is_kiin(k))
	var rng := RandomNumberGenerator.new()
	rng.seed = 500 + t
	var w := {}
	var left := {}
	for f in FORMS:
		w[f] = 0
		left[f] = 0.0
	for g in games:
		var a := []
		var b := []
		for i in 9:
			a.append(pool[rng.randi() % pool.size()])
			b.append(pool[rng.randi() % pool.size()])
		var fb: String = FORMS[rng.randi() % FORMS.size()]
		var sd := rng.randi()
		for f in FORMS:
			var r := RtBattle.make(sd).run(DB.auto_place(a, f), f, 100, null, DB.auto_place(b, fb), fb, 100, null, "", "", [], {"A": "smart", "B": "smart"})
			if r.win: w[f] += 1
			left[f] += _left(r, "A")
	print("== 등급 %d · 무작위 덱 %d판 (같은 덱 · 상대 · 시드, 진형만 바꿈) ==" % [t, games])
	for f in FORMS:
		print("  %s  승률 %3d%%  잔존 %3d%%" % [DB.FORM[f].n, roundi(100.0 * w[f] / games), roundi(100.0 * left[f] / games)])
	print("== 우대 덱 (우대 병종 4장 + 무작위 5장): 그 진형 대 어린진 ==")
	for f in FORMS:
		var bn: Dictionary = DB.D.FORMBOON[f]
		var favored: Array = pool.filter(func(k): return bn.tags.has(DB.C[k].tag))
		if favored.is_empty(): continue
		var wf := 0
		var we := 0
		var r2 := RandomNumberGenerator.new()
		r2.seed = 900 + t
		for g in games:
			var a := []
			for i in 4: a.append(favored[r2.randi() % favored.size()])
			for i in 5: a.append(pool[r2.randi() % pool.size()])
			var b := []
			for i in 9: b.append(pool[r2.randi() % pool.size()])
			var fb: String = FORMS[r2.randi() % FORMS.size()]
			var sd := r2.randi()
			var rf := RtBattle.make(sd).run(DB.auto_place(a, f), f, 100, null, DB.auto_place(b, fb), fb, 100, null, "", "", [], {"A": "smart", "B": "smart"})
			var re := RtBattle.make(sd).run(DB.auto_place(a, "eorin"), "eorin", 100, null, DB.auto_place(b, fb), fb, 100, null, "", "", [], {"A": "smart", "B": "smart"})
			if rf.win: wf += 1
			if re.win: we += 1
		print("  %s (%s %s +%d%%)  그 진형 %3d%% · 어린진 %3d%%" % [DB.FORM[f].n, "·".join(bn.tags), bn.stat, roundi(float(bn.v) * 100),
			roundi(100.0 * wf / games), roundi(100.0 * we / games)])
	get_tree().quit()


func _left(r: Dictionary, cp: String) -> float:
	var a := 0.0
	var m := 0.0
	for u in r.roster:
		if u.camp == cp:
			a += maxf(0.0, float(u.left))
			m += float(u.max)
	return a / maxf(1.0, m)
