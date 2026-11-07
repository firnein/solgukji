extends Node
## 엔진 지문 —— 실행: godot --headless --path . res://tests/fingerprint.tscn [-- --rt] [--noshield]
## 정해진 시드 40판의 사건 기록을 해시로 찍는다. 엔진을 고친 뒤 같은 값이면 판정이 바뀌지 않은 것이다.
## --noshield —— 11/8 갑옷 · 결계 · 깎기(Battle.shield_enabled)를 끈다. 끈 값이 그 전 지문과 같아야 한다

func _ready() -> void:
	var rt: bool = OS.get_cmdline_user_args().has("--rt")
	if OS.get_cmdline_user_args().has("--noshield"):
		Battle.shield_enabled = false
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var h := 0
	var wins := 0
	for i in 40:
		var t: int = 3 + i % 6
		var pool: Array = DB.by_tier(t)
		var a := []
		var b := []
		for j in 9:
			a.append(pool[rng.randi() % pool.size()])
			b.append(pool[rng.randi() % pool.size()])
		var sd := rng.randi() % 100000
		var bt: Battle = RtBattle.new(sd) if rt else Battle.new(sd)
		var r := bt.run(DB.auto_place(a, "eorin"), "eorin", 100, null, DB.auto_place(b, "hagik"), "hagik", 100, null,
			"", "", [], {"A": "smart", "B": "smart"})
		var s := ""
		for e in r.ev:
			s += str(e.t) + str(e.s)
		h = hash(str(h) + s)
		wins += 1 if r.win else 0
	print("지문 %d · A 승 %d/40" % [h, wins])
	get_tree().quit()
