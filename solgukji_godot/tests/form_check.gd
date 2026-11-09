extends Node
## 진형 점검 (11/5 사용자: 모든 진형의 특색이 올바른지, 전력에 영향을 주는지)
## 실행: godot --headless --path . res://tests/form_check.tscn [-- --games=40 --tier=7]
## ① 무작위 덱: 같은 덱 · 같은 상대 · 같은 시드로 진형만 바꿔 승률 (진형 자체의 힘)
## (11/9 진형 우대 삭제 —— 예전 ② 우대 덱 점검은 뺐다. 진형은 모양(칸)과 칸 선호(AFF)로만 힘이 다르다)

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
	get_tree().quit()


func _left(r: Dictionary, cp: String) -> float:
	var a := 0.0
	var m := 0.0
	for u in r.roster:
		if u.camp == cp:
			a += maxf(0.0, float(u.left))
			m += float(u.max)
	return a / maxf(1.0, m)
