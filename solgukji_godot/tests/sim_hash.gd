extends Node
## 시뮬 결과 전체 해시 —— 실행: godot --headless --path . res://tests/sim_hash.tscn
## 정해진 시드 12판(등급 2~8)의 결과 사전 전체(사건 · 위치 기록 · 승패 …)를 문자열로 만들어 해시로 찍는다.
## 연출(view)만 고쳤을 때 고치기 전과 같은 값이어야 한다 (11/11 기본 행동 연출 작업의 결정성 점검).

## --theme=0 이면 11/12 인연 주제 규칙만 끈다.
## --inyeon=0 이면 인연 합동 고유기를 끄고 돌린다 (끈 해시는 인연 도입 전과 같아야 한다). 판마다 합동 횟수도 찍는다
func _ready() -> void:
	for s in OS.get_cmdline_user_args():
		if s == "--inyeon=0":
			Battle.inyeon_enabled = false
		if s == "--theme=0":      # 11/12 인연 주제 · 기인 연다 · 초월 키운다 끔 (끈 해시는 주제 도입 전과 같아야 한다)
			RtBattle.inyeon_theme = false
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var h := 0
	var lines := []
	for i in 12:
		var t: int = 2 + i % 7
		var pool: Array = DB.by_tier(t)
		if pool.is_empty():      # 낮은 등급은 적 전용만 있을 수 있다 —— 가리지 않고 모은다
			for k in DB.C:
				if DB.C[k].tier == t:
					pool.append(k)
		if pool.is_empty():
			continue
		var a := []
		var b := []
		for j in 9:
			a.append(pool[rng.randi() % pool.size()])
			b.append(pool[rng.randi() % pool.size()])
		var sd := rng.randi() % 100000
		var r: Dictionary = RtBattle.make(sd).run(DB.auto_place(a, "eorin"), "eorin", 100, null, DB.auto_place(b, "hagik"), "hagik", 100, null,
			"", "", [], {"A": "smart", "B": "smart"})
		var s := var_to_str(r)
		var hh := hash(s)
		h = hash(str(h) + str(hh))
		lines.append("  판 %d 등급 %d 시드 %d · 사건 %d · 길이 %d · 해시 %d · 합동 %d" % [i, t, sd, r.ev.size(), s.length(), hh, int(r.stats.get("inyeon_joint", 0))])
	for l in lines:
		print(l)
	print("전체 해시 %d" % h)
	get_tree().quit()
