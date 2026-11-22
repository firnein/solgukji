extends Node
## 인연 연쇄 성립률 (11/22) —— 실행: godot --headless --path . res://tests/chain_rate.tscn -- [--games=80] [--old=옛 ultimates.json 경로] [--starve=6] [--tier=7]
## 덱: 인연 구성원 넷(초월 1 + 불멸/신화 3, 짝수 판) 또는 셋(불멸/신화 3, 홀수 판) + 무작위, 상대는 같은 등급 무작위 9 (영리 AI 끼리)
## 구성원 고유기 가운데 연쇄(2명 이상 실제로 터진 합동)에 든 몫 · 연쇄 수 · 평균 인원, 그리고 구성원이 대표로 기를 모을 때 짝이 못 낀 까닭

class Probe extends RtBattle:
	var mine := "A"
	var ppl := []          # 인연 구성원 인물
	var grps := []
	var leads := 0
	var shots := 0
	var why := {}

	func _mem(o: Unit) -> bool:
		return o.camp == mine and ppl.has(DB.person(o.c.id))

	func _inyeon_recruit(u: Unit, wait: float) -> void:
		if _mem(u):
			leads += 1
			for o in units:
				if o == u or not _mem(o) or not o.alive or o.ult == null:
					continue
				var k := "ok"
				if o.charges <= 0:
					k = "횟수 끝"
				elif _wind.has(o) or _wind_grp.has(o):
					k = "제 기 모으는 중"
				elif o.gauge < _join_gauge(o):
					k = "게이지 덜 참"
				elif not _join_ok(o):
					k = "그 밖"
				why[k] = int(why.get(k, 0)) + 1
		super._inyeon_recruit(u, wait)
		if _mem(u) and _wind_grp.has(u):
			grps.append(_wind_grp[u])

	func _fire_one(u: Unit) -> void:
		if _mem(u):
			shots += 1
		var gr: Dictionary = _wind_grp.get(u, {})
		if not gr.is_empty():
			gr["peak"] = maxi(int(gr.get("peak", 0)), gr.members.size())
			if u == gr.lead and _dash_from.has(u):
				gr["dash"] = true
		super._fire_one(u)


func _args() -> Dictionary:
	var args := {}
	for s in OS.get_cmdline_user_args():
		var kv := s.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	return args


func _card(p: String, t: int) -> String:
	for k in DB.by_tier(t):
		if DB.person(k) == p and DB.ult_of(k) != null and not DB.is_kiin(k):
			return k
	return ""


func _any(p: String, ts: Array) -> String:
	for t in ts:
		var k := _card(p, t)
		if k != "":
			return k
	return ""


func _ready() -> void:
	var args := _args()
	var games := int(args.get("games", "80"))
	var ft := int(args.get("tier", "7"))
	var decks := []
	for nm in DB.INYEON:
		for p in DB.INYEON[nm]:
			if _card(p, 6) == "":
				continue
			var hi: Array = DB.INYEON[nm].filter(func(q): return q != p and _any(q, [7, 8]) != "")
			if args.has("fast"):      # --fast=1 —— 11/22 장수별 wind · wait 가 붙은 장수를 앞에 (그 장수가 든 인연만)
				var fs := hi.filter(func(q): return DB.ULT.list[q].has("wind") or DB.ULT.list[q].has("wait"))
				if fs.is_empty():
					break
				hi = fs + hi.filter(func(q): return not fs.has(q))
			if hi.size() >= 3:
				decks.append([_card(p, 6)] + hi.slice(0, 3).map(func(q): return _any(q, [7, 8])))
				decks.append(hi.slice(0, 3).map(func(q): return _any(q, [7, 8])))
				break
	if args.has("old"):      # 옛 고유기 데이터 (장수별 wind · wait 없던 것) 로 바꿔 본다
		var old = JSON.parse_string(FileAccess.open(str(args.old), FileAccess.READ).get_as_text())
		for p in old.list:
			if DB.ULT.list.has(p) and not DB.LINES.get("ults", {}).has(p):
				DB.ULT.list[p] = old.list[p]
		DB.ULT.erase("wind")
	if args.has("starve"):
		Battle.ult_starve = float(args.starve)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1122
	var tot := {"fail": 0, "fdash": 0, "dash": 0, "joins": 0, "cut": 0, "leads": 0, "shots": 0, "in": 0, "ch": 0, "n": 0, "n4": 0}
	var why := {}
	for g in games:
		var a: Array = decks[g % decks.size()].duplicate()
		var ps := a.map(func(k): return DB.person(k))
		var pool: Array = DB.by_tier(ft)
		while a.size() < 9:
			var k: String = pool[rng.randi() % pool.size()]
			if not ps.has(DB.person(k)):
				a.append(k)
				ps.append(DB.person(k))
		var b := []
		while b.size() < 9:
			var k: String = pool[rng.randi() % pool.size()]
			if not b.has(k):
				b.append(k)
		var sd := rng.randi() % 100000
		var side_a := g % 2 == 0
		var bt := Probe.new(sd)
		bt.mine = "A" if side_a else "B"
		bt.ppl = decks[g % decks.size()].map(func(k): return DB.person(k))
		bt.run(DB.auto_place(a if side_a else b, "eorin"), "eorin", 100, null, DB.auto_place(b if side_a else a, "hagik"), "hagik", 100, null,
			"", "", [], {"A": "smart", "B": "smart"})
		tot.leads += bt.leads
		tot.shots += bt.shots
		tot.joins += int(bt.stats.get("inyeon_join", 0))
		tot.cut += int(bt.stats.get("inyeon_cut", 0))
		for gr in bt.grps:
			var n := int(gr.get("shot", 0))
			if int(gr.get("peak", 0)) >= 2 and n < 2:
				tot.fail += 1
				if gr.get("dash", false):
					tot.fdash += 1
			if gr.get("dash", false):
				tot.dash += 1
			if n >= 2:
				tot.ch += 1
				tot["in"] += n
				if n >= 4:
					tot.n4 += 1
		for k in bt.why:
			why[k] = int(why.get(k, 0)) + int(bt.why[k])
	print("── %d판 · %s · 굶주림 %.0f초 ──" % [games, "옛 고유기 데이터" if args.has("old") else "지금 데이터", Battle.ult_starve])
	print("  구성원 대표 기 모으기 %d번 · 합류(양 진영) %d · 합동 끊김 %d · 덱 %d개" % [tot.leads, tot.joins, tot.cut, decks.size()])
	print("  구성원 고유기 %d번 (판당 %.2f) · 연쇄 %d번 (판당 %.2f, 4인 %d) · 연쇄 평균 %.2f명 · 고유기 가운데 연쇄에 든 몫 %.1f%%" % [
		tot.shots, float(tot.shots) / games, tot.ch, float(tot.ch) / games, tot.n4, float(tot["in"]) / maxf(1, tot.ch), 100.0 * tot["in"] / maxf(1, tot.shots)])
	print("  짝이 붙었는데 연쇄가 안 된 합동 %d번 (그 가운데 대표가 돌진한 것 %d · 돌진 대표 합동 %d번)" % [tot.fail, tot.fdash, tot.dash])
	var ws := []
	for k in why:
		ws.append("%s %d" % [k, why[k]])
	print("  구성원이 대표로 모을 때 짝 상태 —— " + " · ".join(ws))
	get_tree().quit()
