extends Node
## 등급별 · 기질별 고유기 발동률 (11/7) —— 같은 등급 무작위 9장끼리, 고유기가 있는 부대 가운데 한 번이라도 터뜨린 비율 · 첫 발동 시각
## 실행: godot --headless --path . res://tests/ult_rate.tscn -- --tiers=6,7,8 --games=30 [--by=person --top=10 --who=주태,전위] [--cap= --decay= --rwait= --rtemper= --allr= --alln=]
## --by=person: 장수(인물 · 등급)별 —— 보유 부대 수 · 발동률 · 보유 부대당 횟수 · 첫 발동 · 재발동 간격(같은 부대의 연속 발동 사이) · 2회 이상.
##   보유 부대당 횟수 순으로 --top 명 + 수동 지정 기질 6명(장비 · 하후돈 · 마초 · 황개 · 전위 · 주태) + --who 가 지목한 장수

const MANUAL := ["장비", "하후돈", "마초", "황개", "전위", "주태"]      # ultimates.json "temper" 수동 지정


func _ready() -> void:
	var args := {}
	for s in OS.get_cmdline_user_args():
		var kv := s.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	var games := int(args.get("games", "30"))
	var tiers := Array(str(args.get("tiers", "6,7,8")).split(",")).map(func(x): return int(x))
	var by_person: bool = args.get("by", "") == "person"
	var top := int(args.get("top", "10"))
	var who: Array = Array(str(args.get("who", "")).split(",")) if args.get("who", "") != "" else []
	print(preload("res://tests/ult_oneshot.gd").knobs(args))      # --cap · --decay · --rwait · --rtemper · --allr · --alln (ult_oneshot.gd 참고)
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var per := {}      # "인물(등급)" -> [보유, 발동, 횟수, 첫 발동 합, 2회 이상, 간격 합, 간격 수, 기질]
	for t in tiers:
		var have := 0
		var fired := 0
		var n_ult := 0
		var twice := 0
		var thrice := 0
		var first_t := 0.0
		var len_sum := 0.0
		var tp := {}      # 기질 -> [보유, 발동, 첫 발동 합]
		for i in games:
			var pool: Array = DB.by_tier(t)
			var a := []
			var b := []
			for j in 9:
				a.append(pool[rng.randi() % pool.size()])
				b.append(pool[rng.randi() % pool.size()])
			var bt := RtBattle.new(rng.randi() % 100000)
			var r := bt.run(DB.auto_place(a, "eorin"), "eorin", 100, null, DB.auto_place(b, "hagik"), "hagik", 100, null, "", "", [], {"A": "smart", "B": "smart"})
			len_sum += float(r.len)
			var cnt := {}
			var ft := {}
			var lt := {}      # 마지막 발동 시각 (간격용)
			var gaps := {}    # 부대 -> [간격 합, 수]
			for e in r.ev:
				if e.get("fx") == "ult":
					var k: String = str(e.get("a", ""))
					cnt[k] = int(cnt.get(k, 0)) + 1
					var tm := float(e.get("tm", 0.0))
					if not ft.has(k):
						ft[k] = tm
					else:
						if not gaps.has(k):
							gaps[k] = [0.0, 0]
						gaps[k][0] += tm - float(lt[k])
						gaps[k][1] += 1
					lt[k] = tm
			for u in bt.units:
				if u.ult != null:
					have += 1
					var tk: String = u.temper if u.temper != "" else "(없음)"
					if not tp.has(tk):
						tp[tk] = [0, 0, 0.0]
					tp[tk][0] += 1
					var pk := "%s(%d)" % [DB.person(u.c.id), u.c.tier]
					if not per.has(pk):
						per[pk] = [0, 0, 0, 0.0, 0, 0.0, 0, tk]
					per[pk][0] += 1
					if cnt.has(u.key):
						fired += 1
						n_ult += int(cnt[u.key])
						first_t += float(ft[u.key])
						if int(cnt[u.key]) >= 2:
							twice += 1
						if int(cnt[u.key]) >= 3:
							thrice += 1
						tp[tk][1] += 1
						tp[tk][2] += float(ft[u.key])
						per[pk][1] += 1
						per[pk][2] += int(cnt[u.key])
						per[pk][3] += float(ft[u.key])
						if int(cnt[u.key]) >= 2:
							per[pk][4] += 1
						if gaps.has(u.key):
							per[pk][5] += gaps[u.key][0]
							per[pk][6] += gaps[u.key][1]
		print("등급 %d (%d판): 전투 %.1f초 · 고유기 보유 부대 %d 중 발동 %d (%.0f%%) · 발동 부대당 %.2f번 · 첫 발동 평균 %.1f초 · 2회 이상 %.0f%% · 3회 %.0f%%" % [
			t, games, len_sum / games, have, fired, 100.0 * fired / maxf(1, have), float(n_ult) / maxf(1, fired), first_t / maxf(1, fired),
			100.0 * twice / maxf(1, have), 100.0 * thrice / maxf(1, have)])
		var parts := []
		for tk in tp:
			parts.append("%s %d명 발동 %.0f%% 첫 %.1f초" % [tk, tp[tk][0], 100.0 * tp[tk][1] / maxf(1, tp[tk][0]), tp[tk][2] / maxf(1, tp[tk][1])])
		print("   기질별: " + " · ".join(parts))
	if by_person:
		var ks: Array = per.keys().filter(func(k): return per[k][0] >= 4)
		ks.sort_custom(func(x, y): return float(per[x][2]) / per[x][0] > float(per[y][2]) / per[y][0])
		print("장수(등급) · 기질 · 보유 부대 · 발동률% · 보유 부대당 횟수 · 첫 발동(초) · 재발동 간격(초) · 2회 이상%")
		var shown := []
		for k in ks.slice(0, top):
			shown.append(k)
			_row(k, per[k])
		print("── 수동 지정 · 지목 장수")
		for k in ks:
			if shown.has(k):
				continue
			var pn: String = str(k).substr(0, str(k).find("("))      # k 는 타입 없는 배열 원소 —— := 로 추론하면 파스 오류(스크립트가 안 붙어 quit() 이 안 불리고 장면이 끝없이 떠 있었다)
			if MANUAL.has(pn) or who.has(pn):
				_row(k, per[k])
	get_tree().quit()


func _row(k: String, p: Array) -> void:
	print("   %s · %s · %d · %.0f · %.2f · %.1f · %s · %.0f" % [k, p[7], p[0], 100.0 * p[1] / maxf(1, p[0]), float(p[2]) / maxf(1, p[0]),
		p[3] / maxf(1, p[1]), ("%.1f (%d건)" % [p[5] / p[6], p[6]]) if p[6] > 0 else "—", 100.0 * p[4] / maxf(1, p[0])])
