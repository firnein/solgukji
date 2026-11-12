extends "res://tests/inyeon.gd"
## 인연기 점검 (11/12 사용자) —— 실행: godot --headless --path . res://tests/inyeon_fin.tscn
## (a) 데이터: fin 의 인연 이름 · 틀이 맞다  (b) 셋 합동(호뢰관 · 일기토) → 인연기 한 번, 마지막 고유기 뒤  (c) 둘 합동 → 2명 수치
## (d) 화공 · 고무 틀  (e) 끄면 없음 · 인연기 없는 인연은 없음 · 대표가 끊기면 없음


func _fins(r: Dictionary) -> Array:
	return _evs(r, "inyeon_fin")


func _after(r: Dictionary, fin: Dictionary) -> Array:      # 인연기 사건과 같은 행동(ai)의 뒤따르는 사건
	return r.ev.filter(func(e): return e.ai == fin.ai and e != fin)


func _ready() -> void:
	# (a)
	for n in DB.INYEON_FIN:
		_ok(DB.INYEON.has(n), "fin: 모르는 인연 %s" % n)
		_ok(RtBattle.FIN.has(DB.INYEON_FIN[n].t), "fin: %s 틀 %s" % [n, DB.INYEON_FIN[n].t])
		_ok(DB.inyeon_fin_text(n) != "", "fin: %s 설명" % n)
	_ok(DB.inyeon_fin_text("북벌 저지") == "", "인연기 없는 인연은 설명 없음")
	print("(a) 인연기 %d개" % DB.INYEON_FIN.size())

	# (b) 유비 관우 장비 —— 호뢰관(일기토) 3명
	var r := _run(["유비", "관우", "장비"], ["유비", "관우", "장비"])
	var f := _fins(r)
	var ults := _evs(r, "ult")
	_ok(not f.is_empty(), "셋 합동 뒤 인연기")
	if not f.is_empty():
		var e: Dictionary = f[0]
		var tail := _after(r, e)
		print("(b) %s · 인연 『%s』 · 틀 %s · %d명 · +%.2fs(첫 고유기 뒤) · 뒤따른 사건 %s" % [e.name, e.inyeon, e.kind, e.cnt, e.tm - ults[0].tm, str(tail.map(func(x): return x.get("fx", "")))])
		_ok(e.inyeon == ults[0].inyeon, "인연기의 인연 = 합동의 인연")
		_ok(int(e.cnt) == 3, "3명 (지금 %d)" % int(e.cnt))
		_ok(r.ev.find(e) > r.ev.find(ults[2]), "세 번째 고유기 뒤에 터진다")
		if e.kind == "duel":
			_ok(tail.any(func(x): return x.get("fx") == "phys") and tail.any(func(x): return x.get("fx") == "morale"), "일기토: 일격 + 사기")
		var first_t: float = e.tm
		_ok(f.filter(func(x): return absf(x.tm - first_t) < 0.5).size() == 1, "한 합동에 인연기 한 번")

	# (c) 둘만
	var r2 := _run(["유비", "관우", "장비"], ["유비", "관우"])
	var f2 := _fins(r2)
	_ok(not f2.is_empty() and int(f2[0].cnt) == 2, "둘 합동 → 2명 인연기")
	print("(c) 둘: 인연기 %d · %s" % [f2.size(), str(f2[0].get("cnt", 0)) if not f2.is_empty() else "-"])

	# (d) 화공(적벽대전: 주유 제갈량 황개) · 고무(조씨 일족: 조조 하후돈 하후연)
	var r3 := _run(["주유", "제갈량", "황개"], ["주유", "제갈량", "황개"])
	var f3 := _fins(r3)
	_ok(not f3.is_empty(), "화공 인연기")
	if not f3.is_empty():
		var t3 := _after(r3, f3[0])
		print("(d1) %s · 『%s』 · 틀 %s · 화상 %d부대" % [f3[0].name, f3[0].inyeon, f3[0].kind, t3.filter(func(x): return x.get("st", "") == "burn").size()])
		if f3[0].kind == "fire":
			_ok(t3.any(func(x): return x.get("st", "") == "burn" or x.get("fx", "") == "resist"), "화공: 화상")
	var r4 := _run(["조조", "하후돈", "하후연"], ["조조", "하후돈", "하후연"])
	var f4 := _fins(r4)
	_ok(not f4.is_empty(), "고무 인연기")
	if not f4.is_empty():
		var t4 := _after(r4, f4[0])
		print("(d2) %s · 『%s』 · 틀 %s · 뒤따른 %s" % [f4[0].name, f4[0].inyeon, f4[0].kind, str(t4.map(func(x): return x.get("fx", "")))])
		if f4[0].kind == "rally":
			_ok(t4.any(func(x): return x.get("fx") == "buff"), "고무: 공격 버프")

	# (e) 끄면 없음 · 인연기 없는 인연 · 대표 끊김
	RtBattle.inyeon_fin_enabled = false
	var r5 := _run(["유비", "관우", "장비"], ["유비", "관우", "장비"])
	RtBattle.inyeon_fin_enabled = true
	_ok(_fins(r5).is_empty(), "끄면 인연기 없음")
	var r6 := _run(["여포", "진궁", "장료"], ["여포", "진궁", "장료"])      # 하비 포위 · 여포 군단 —— 인연기 없음
	var u6 := _evs(r6, "ult")
	var f6 := _fins(r6)
	var nm6: String = str(u6[0].get("inyeon", "")) if not u6.is_empty() else ""
	print("(e) 끔 %d · 인연 『%s』(인연기 %s) %d" % [_fins(r5).size(), nm6, "있음" if DB.INYEON_FIN.has(nm6) else "없음", f6.size()])
	if not DB.INYEON_FIN.has(nm6):
		_ok(f6.filter(func(x): return absf(x.tm - u6[0].tm) < 3.0).is_empty(), "인연기 없는 인연은 터지지 않는다")
	print("    대표 끊김: %s" % _run_cut_fin())

	print("인연기 점검 %s (실패 %d)" % ["통과" if _fail == 0 else "실패", _fail])
	get_tree().quit(1 if _fail > 0 else 0)


func _run_cut_fin() -> String:
	var a := _pick(["유비", "관우", "장비"])
	var b := _pick([], 7)
	var bt := CutLead.new(5)
	bt.full = ["유비", "관우", "장비"]
	var r := bt.run(DB.auto_place(a, "eorin"), "eorin", 100, null, DB.auto_place(b, "hagik"), "hagik", 100, null, "", "", [], {"A": "auto", "B": "auto"})
	var warns := _evs(r, "ult_warn")
	var t0: float = warns[0].tm if not warns.is_empty() else 0.0
	var early := _fins(r).filter(func(x): return x.tm <= t0 + 3.2)
	_ok(early.is_empty(), "대표가 끊긴 합동은 인연기 없음 (지금 %d)" % early.size())
	return "첫 합동 창의 인연기 %d" % early.size()
