extends Node
## 11/13 병종 1 대 1 점검 —— 같은 등급의 기병 한 부대와 창병 한 부대만 붙인다 (9부대 덱이 아니라 빠르다).
## 실행: godot --headless --path . res://tests/duel_tag.tscn [-- --tiers=3,4,5,6,7 --per=6 --seeds=2 --a=기병 --b=창병]
## 줄마다: 등급 · 맞대결 · a 승률 · 평균 턴 · 이긴 쪽 남은 병력 비율. 양쪽 진영을 바꿔 한 번씩. 맨 끝에 상성 끔 · 돌격 끔 비교(a 대 b 만)

var per := 6
var only := ""        # --only=여포: a 쪽 장수 이름에 이 글자가 든 것만 · 두 부대 모드는 짝마다 한 줄
var seeds := 2


func _ready() -> void:
	var args := {}
	for s in OS.get_cmdline_user_args():
		var kv := s.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	per = int(args.get("per", "6"))
	seeds = int(args.get("seeds", "2"))
	only = str(args.get("only", ""))
	var ta: String = str(args.get("a", "기병"))
	var tb: String = str(args.get("b", "창병"))
	var tiers: Array = Array(str(args.get("tiers", "3,4,5,6,7")).split(",")).map(func(x): return int(x))
	var t0 := Time.get_ticks_msec()
	if args.has("stat"):
		_stat(ta, tb)
	if args.has("two"):      # --two=8:6+6,8:0+0,8:6+0 —— a 한 부대 대 b 두 부대 (b 의 등급 둘)
		for kv in str(args.two).split(","):
			var bb: PackedStringArray = kv.split(":")[1].split("+")
			_row2(int(kv.split(":")[0]), ta, tb, int(bb[0]), int(bb[1]))
		get_tree().quit()
		return
	if args.has("cross"):      # --cross=5:4,7:5 —— a 는 앞 등급, b 는 뒤 등급 (등급 차이가 날 때)
		for kv in str(args.cross).split(","):
			_row(int(kv.split(":")[0]), ta, tb, int(kv.split(":")[1]))
		get_tree().quit()
		return
	print("== 기본 규칙")
	for t in tiers:
		_row(t, ta, tb)
		_row(t, ta, ta)
		_row(t, tb, tb)
	print("== 상성 끔 (counter_enabled = false)")
	Battle.counter_enabled = false
	for t in tiers:
		_row(t, ta, tb)
	Battle.counter_enabled = true
	print("== 돌격 배율 1.0 (cav_charge)")
	var keep := RtBattle.cav_charge
	RtBattle.cav_charge = 1.0
	for t in tiers:
		_row(t, ta, tb)
	RtBattle.cav_charge = keep
	print("== 고유기 끔")
	Battle.ults_enabled = false
	for t in tiers:
		_row(t, ta, tb)
	Battle.ults_enabled = true
	print("소요 %.1f초" % ((Time.get_ticks_msec() - t0) / 1000.0))
	get_tree().quit()


## 등급 0 = 기인 (등급 값은 전설이지만 kind 가 kiin). 그 밖의 등급은 기인을 뺀다
func _pick(t: int, tag: String) -> Array:
	var l: Array
	if t == 0:
		l = DB.C.keys().filter(func(k): return DB.is_kiin(k) and DB.C[k].tag == tag and not DB.is_foe(k))
	else:
		l = DB.by_tier(t).filter(func(k): return DB.C[k].tag == tag and not DB.is_kiin(k))
	return l.slice(0, per)


func _tn(t: int) -> String:
	return "기인" if t == 0 else str(DB.TIER[t].n)


## --stat: 등급별 기병 · 창병의 장수 수 · 평균 PV · 평균 전투력(병력 tr) · 무력 · 방어
func _stat(ta: String, tb: String) -> void:
	for t in [3, 4, 5, 0, 6, 7, 8]:
		for tag in [ta, tb]:
			var keep := per
			per = 999
			var l := _pick(t, tag)
			per = keep
			if l.is_empty():
				print("%s %s: 없음" % [_tn(t), tag])
				continue
			var pv := 0.0
			var tr := 0.0
			for k in l:
				pv += float(DB.C[k].pv)
				tr += float(DB.C[k].tr)
			print("%s %s: %d명 · 평균 PV %.1f · 평균 전투력 %.0f · %s" % [_tn(t), tag, l.size(), pv / l.size(), tr / l.size(), ", ".join(l.map(func(k): return "%s(%d/%d)" % [str(DB.C[k].get("name", k)), int(DB.C[k].pv), int(DB.C[k].tr)]))])


func _row(t: int, ta: String, tb: String, t2 := -1) -> void:
	var la := _pick(t, ta)
	var lb := _pick(t if t2 < 0 else t2, tb)
	if la.is_empty() or lb.is_empty():
		return
	var w := 0.0
	var n := 0
	var turns := 0.0
	var left := 0.0
	for a in la:
		for b in lb:
			if a == b:
				continue
			for s in seeds:
				for flip in [false, true]:
					var bt := RtBattle.new(1000 + t * 97 + s * 13 + n)
					var pa := DB.auto_place([a], "eorin")
					var pb := DB.auto_place([b], "eorin")
					var r: Dictionary = bt.run(pb, "eorin", 100, null, pa, "eorin", 100, null, "", "", [], {"A": "smart", "B": "smart"}) if flip else bt.run(pa, "eorin", 100, null, pb, "eorin", 100, null, "", "", [], {"A": "smart", "B": "smart"})
					var a_win: bool = (r.win != flip) and not r.draw
					w += 0.5 if r.draw else (1.0 if a_win else 0.0)
					turns += r.turns
					var tr := 0.0
					var mx := 0.0
					for u in bt.units:
						if (u.camp == "A") == r.win:
							tr += maxf(0.0, u.troops)
							mx += u.max
					left += tr / maxf(1.0, mx)
					n += 1
	if n > 0:
		print("%s %s 대 %s%s: %s 승률 %.0f%% · %.1f턴 · 이긴 쪽 남은 병력 %.0f%% (%d판)" % [_tn(t), ta, "" if t2 < 0 else _tn(t2) + " ", tb, ta, w / n * 100.0, turns / n, left / n * 100.0, n])


## a 한 부대 대 b 두 부대 (서로 다른 장수 둘) —— 승률 · 턴 · 이긴 쪽 남은 병력
func _row2(t: int, ta: String, tb: String, t1: int, t2: int) -> void:
	var la := _pick(t, ta)
	if only != "":
		la = la.filter(func(k): return str(DB.C[k].get("name", k)).contains(only))
	var l1 := _pick(t1, tb)
	var l2 := _pick(t2, tb)
	var w := 0.0
	var n := 0
	var turns := 0.0
	var left := 0.0
	for a in la:
		for i in l1.size():
			for j in l2.size():
				if l1[i] == l2[j] or (t1 == t2 and j <= i):
					continue
				var pw := 0.0
				var pn := 0
				var pt := 0.0
				var pl := 0.0
				for s in seeds:
					for flip in [false, true]:
						var bt := RtBattle.new(2000 + t * 97 + s * 13 + n)
						var pa := DB.auto_place([a], "eorin")
						var pb := DB.auto_place([l1[i], l2[j]], "eorin")
						var r: Dictionary = bt.run(pb, "eorin", 100, null, pa, "eorin", 100, null, "", "", [], {"A": "smart", "B": "smart"}) if flip else bt.run(pa, "eorin", 100, null, pb, "eorin", 100, null, "", "", [], {"A": "smart", "B": "smart"})
						var a_win: bool = (r.win != flip) and not r.draw
						w += 0.5 if r.draw else (1.0 if a_win else 0.0)
						turns += r.turns
						var tr := 0.0
						var mx := 0.0
						for u in bt.units:
							if (u.camp == "A") == r.win:
								tr += maxf(0.0, u.troops)
								mx += u.max
						left += tr / maxf(1.0, mx)
						n += 1
						pw += 0.5 if r.draw else (1.0 if a_win else 0.0)
						pn += 1
						pt += r.turns
						pl += tr / maxf(1.0, mx)
				if only != "" and pn > 0:
					print("  %s 대 %s + %s: 승률 %.0f%% · %.1f턴 · 이긴 쪽 남은 병력 %.0f%% (%d판)" % [str(DB.C[a].get("name", a)), str(DB.C[l1[i]].get("name", "")), str(DB.C[l2[j]].get("name", "")), pw / pn * 100.0, pt / pn, pl / pn * 100.0, pn])
	if n > 0:
		print("%s %s 1 대 %s+%s %s 2: %s 승률 %.0f%% · %.1f턴 · 이긴 쪽 남은 병력 %.0f%% (%d판)" % [_tn(t), ta, _tn(t1), _tn(t2), tb, ta, w / n * 100.0, turns / n, left / n * 100.0, n])
