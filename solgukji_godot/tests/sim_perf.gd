extends Node
## 전투 계산(RtBattle) 시간 점검 (11/15 퍼포먼스 최적화) —— 실행: godot --headless --path . res://tests/sim_perf.tscn [-- --n=4]
## 등급 5 ~ 8 의 9 대 9 전투를 등급마다 n 판 돌려 한 판에 걸리는 시간(ms) · 사건 수를 찍는다 (온라인 서버 · 봇 · 내 전투 모두 이 계산을 쓴다).
## 결과 해시도 같이 찍는다 —— 고치기 전후가 같아야 한다

func _ready() -> void:
	var n := 4
	for s in OS.get_cmdline_user_args():
		if s.begins_with("--n="):
			n = int(s.trim_prefix("--n="))
	var rng := RandomNumberGenerator.new()
	rng.seed = 2025
	var h := 0
	var all := 0.0
	var cnt := 0
	for t in [5, 6, 7, 8]:
		var pool: Array = DB.by_tier(t)
		var ms := 0.0
		var worst := 0.0
		var evs := 0
		for i in n:
			var a := []
			var b := []
			for j in 9:
				a.append(pool[rng.randi() % pool.size()])
				b.append(pool[rng.randi() % pool.size()])
			var sd := rng.randi() % 100000
			var pa: Array = DB.auto_place(a, "eorin")
			var pb: Array = DB.auto_place(b, "hagik")
			var t0 := Time.get_ticks_usec()
			var r: Dictionary = RtBattle.make(sd).run(pa, "eorin", 100, null, pb, "hagik", 100, null, "", "", [], {"A": "smart", "B": "smart"})
			var d := (Time.get_ticks_usec() - t0) / 1000.0
			ms += d
			worst = maxf(worst, d)
			evs += r.ev.size()
			h = hash(str(h) + str(hash(var_to_str(r.ev))))
		all += ms
		cnt += n
		print("SIMPERF|등급 %d|한 판 평균 %.1fms|가장 긴 판 %.1fms|사건 %d" % [t, ms / n, worst, evs / n])
	print("SIMPERF|전체 평균 %.1fms|해시 %d" % [all / cnt, h])
	# 섞은 판 —— 등급 3 ~ 8 · 기인 · 토벌 적 · 무작위 장비 · 여러 진형. 결과 사전 전체(사건 · 위치 기록)를 해시로 (고치기 전후 같아야 한다)
	var every: Array = []
	for k in DB.C:
		if int(DB.C[k].tier) >= 3:
			every.append(k)
	every.sort()
	var items: Array = DB.IT.keys()
	items.sort()
	var forms: Array = DB.FORM.keys()
	forms.sort()
	var wh := 0
	var wms := 0.0
	var wn := n * 3
	for i in wn:
		var a := []
		var b := []
		var ea := []
		var eb := []
		for j in 9:
			a.append(every[rng.randi() % every.size()])
			b.append(every[rng.randi() % every.size()])
			ea.append(items[rng.randi() % items.size()] if rng.randi() % 3 == 0 else null)
			eb.append([items[rng.randi() % items.size()], items[rng.randi() % items.size()]] if rng.randi() % 4 == 0 else null)
		var fa: String = forms[rng.randi() % forms.size()]
		var fb: String = forms[rng.randi() % forms.size()]
		var sd := rng.randi() % 100000
		var t0 := Time.get_ticks_usec()
		var r: Dictionary = RtBattle.make(sd).run(DB.auto_place(a, fa), fa, 70 + rng.randi() % 60, ea, DB.auto_place(b, fb), fb, 70 + rng.randi() % 60, eb, "", "", [], {"A": "smart", "B": "smart"})
		wms += (Time.get_ticks_usec() - t0) / 1000.0
		wh = hash(str(wh) + str(hash(var_to_str(r))))
	print("SIMPERF|섞은 판 %d|한 판 평균 %.1fms|해시 %d" % [wn, wms / wn, wh])
	get_tree().quit()
