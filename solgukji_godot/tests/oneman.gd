extends Node
## 11/13 원맨 대 군단 점검 —— 9 대 9. 실행: godot --headless --path . res://tests/oneman.tscn [-- --games=100]
## 원맨 = 신화 한 장 + 낮은 등급으로 나머지, 군단 = 고등급 여럿. 줄마다: 원맨 승률 · 평균 턴 · 원맨 쪽 신화의 피해 비중.
## 진형은 판마다 무작위, 홀수 판은 진영을 바꾼다. 같은 인물은 한 덱에 한 번.

const FORMS := ["eorin", "hagik", "bongsi", "anwol", "bangwon", "anhaeng", "chuhaeng", "jangsa"]
var games := 100
var rng := RandomNumberGenerator.new()


func _ready() -> void:
	var args := {}
	for s in OS.get_cmdline_user_args():
		var kv := s.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	games = int(args.get("games", "100"))
	var t0 := Time.get_ticks_msec()
	var yeopo := _by_name("비장 여포")
	var joun := _by_name("단기구주 조운")
	# [이름, 원맨 덱 (고정 카드 + 채울 등급), 군단 덱 (등급: 장수 수), 군단 창병 최소]
	var rows := [
		["여포 + 희귀 8  대  불멸 2 · 초월 2 · 전설 5", [yeopo], 4, {7: 2, 6: 2, 5: 5}],
		["여포 + 조운 + 희귀 7  대  불멸 2 · 초월 2 · 전설 5", [yeopo, joun], 4, {7: 2, 6: 2, 5: 5}],
		["여포 + 희귀 8  대  전설 9", [yeopo], 4, {5: 9}],
		["여포 + 희귀 8  대  초월 3 · 전설 6", [yeopo], 4, {6: 3, 5: 6}],
		["여포 + 희귀 8  대  불멸 5 · 초월 4", [yeopo], 4, {7: 5, 6: 4}],
		["여포 + 전설 8  대  불멸 2 · 초월 2 · 전설 5", [yeopo], 5, {7: 2, 6: 2, 5: 5}],
		["여포 + 전설 8  대  불멸 5 · 초월 4", [yeopo], 5, {7: 5, 6: 4}],
	]
	for r in rows:
		_run(r[0], r[1], int(r[2]), r[3])
	print("소요 %.1f초" % ((Time.get_ticks_msec() - t0) / 1000.0))
	get_tree().quit()


func _by_name(nm: String) -> String:
	for k in DB.C:
		if str(DB.C[k].get("name", "")) == nm and not DB.is_foe(k):
			return k
	push_error("없는 장수: " + nm)
	return ""


func _pool(t: int) -> Array:
	return DB.by_tier(t).filter(func(k): return not DB.is_kiin(k))


## 등급별 수대로 무작위로 뽑는다 —— 같은 인물 한 번, 창병이 spear_min 보다 적으면 다시
func _army(spec: Dictionary, used: Array, spear_min: int) -> Array:
	for _try in 50:
		var out := []
		var seen := used.duplicate()
		for t in spec:
			var p := _pool(int(t))
			var left := int(spec[t])
			var guard := 0
			while left > 0 and guard < 500:
				guard += 1
				var k: String = p[rng.randi() % p.size()]
				var who := DB.person(k)
				if seen.has(who):
					continue
				seen.append(who)
				out.append(k)
				left -= 1
		if out.filter(func(k): return DB.C[k].tag == "창병").size() >= spear_min:
			return out
	return []


func _run(title: String, fixed: Array, fill_t: int, spec: Dictionary) -> void:
	rng.seed = 4242
	var w := 0.0
	var turns := 0.0
	var share := 0.0
	var n := 0
	for i in games:
		var used := fixed.map(func(k): return DB.person(k))
		var a := fixed.duplicate() + _army({fill_t: 9 - fixed.size()}, used, 0)
		var b := _army(spec, [], 2)
		if a.size() != 9 or b.size() != 9:
			continue
		var fa: String = FORMS[rng.randi() % FORMS.size()]
		var fb: String = FORMS[rng.randi() % FORMS.size()]
		var bt := RtBattle.new(rng.randi() % 100000)
		var pa := DB.auto_place(a, fa)
		var pb := DB.auto_place(b, fb)
		var flip := i % 2 == 1
		var r: Dictionary = bt.run(pb, fb, 100, null, pa, fa, 100, null, "", "", [], {"A": "smart", "B": "smart"}) if flip else bt.run(pa, fa, 100, null, pb, fb, 100, null, "", "", [], {"A": "smart", "B": "smart"})
		w += 0.5 if r.draw else (1.0 if (r.win != flip) else 0.0)
		turns += r.turns
		var mine := "B" if flip else "A"
		var tot := 0.0
		var top := 0.0
		for u in bt.units:
			if u.camp == mine:
				var d: float = u.dmg
				tot += d
				if u.key == fixed[0]:
					top = d
		share += top / maxf(1.0, tot)
		n += 1
	print("%s: 원맨 승률 %.0f%% · %.1f턴 · 신화 피해 비중 %.0f%% (%d판)" % [title, w / maxf(1, n) * 100.0, turns / maxf(1, n), share / maxf(1, n) * 100.0, n])
