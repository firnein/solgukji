extends Node
## 인연 연쇄 한 방의 파괴력 (11/22) —— 실행: godot --headless --path . res://tests/chain_power.tscn -- [--games=60]
## 덱: 초월이 든 인연 4명(초월 1 + 불멸/신화 3) + --tier(기본 7 불멸) 무작위 5, 상대는 같은 등급 무작위 9. --capn=4:1.0,3:1.3 인원별 합동 상한 배수 시험 · --kiin=1 그 인연 기인 추가 · --n4amp · --kfin · --kcap 손잡이 시험 (자리는 판마다 바꾼다)
## 연쇄 하나마다 —— 대표가 터진 순간부터 마지막 장수(인연기 · 주제 포함)까지 적 진영이 잃은 병력 (그 순간 적 총 병력 대비 · 적 총 최대 병력 대비)
## 판마다 —— 첫 4인 연쇄를 쏜 진영의 승률 · 그 뒤 남은 전투 시간. 같은 판을 인연 끔으로도 돌려 승률 차 · 같은 시각 5초 손실(대조)을 본다

class Probe extends RtBattle:
	var recs := []        # {n, camp, t0, pre, mx, loss}
	var open := {}        # 그룹 -> 기록 (그룹은 사전이라 대표 장수를 열쇠로)
	var singles := []     # 단독 고유기 한 번의 적 총 병력 대비 손실

	func _foe_sum(camp: String) -> Array:
		var s := 0.0
		var m := 0.0
		for o in units:
			if o.camp != camp:
				m += o.max
				if o.alive:
					s += maxf(0.0, o.troops)
		return [s, m]

	func _inyeon_fire_setup(u: Unit, grp: Dictionary) -> void:
		var was: bool = grp.get("fired", false)
		if not was and not open.has(grp.lead):
			var fs := _foe_sum(u.camp)
			open[grp.lead] = {"camp": u.camp, "t0": _tm, "pre": fs[0], "mx": fs[1], "grp": grp, "own": _own_sum(u.camp)}
		super._inyeon_fire_setup(u, grp)
		if not grp.get("fired", false):
			open.erase(grp.lead)

	func _do_ult(u: Unit, foes: Array, allies: Array) -> void:
		if not _ult_grp.is_empty():
			super._do_ult(u, foes, allies)
			return
		var fs := _foe_sum(u.camp)
		super._do_ult(u, foes, allies)
		if fs[0] > 0.0:
			singles.append((fs[0] - _foe_sum(u.camp)[0]) / fs[0])

	func _close() -> void:
		for k in open.keys():
			var r: Dictionary = open[k]
			var grp: Dictionary = r.grp
			if grp.members.any(func(o): return _wind.has(o) or _dash.has(o)):
				continue
			open.erase(k)
			r.erase("grp")
			r["n"] = int(grp.get("shot", 0))
			r["loss"] = r.pre - _foe_sum(r.camp)[0]
			r["at5"] = float(r.t0) + 5.0
			recs.append(r)

	var marks := []       # 대조(인연 끔) 판 —— [{camp, at}] 시각에 적 총 병력을 적어 둔다
	func _fire_winds() -> void:
		super._fire_winds()
		for m in marks:
			if not m.has("v") and _tm >= float(m.at):
				m["v"] = _foe_sum(m.camp)[0]
		for r in recs:
			if not r.has("loss5") and _tm >= float(r.at5):
				r["loss5"] = r.pre - _foe_sum(r.camp)[0]
				r["own5"] = _own_sum(r.camp)

	func _own_sum(camp: String) -> float:
		var s := 0.0
		for o in units:
			if o.camp == camp and o.alive:
				s += maxf(0.0, o.troops)
		return s

	func finish() -> void:      # 전투가 5초 안에 끝난 기록
		for r in recs:
			if not r.has("loss5"):
				r["loss5"] = r.pre - _foe_sum(r.camp)[0]
				r["own5"] = _own_sum(r.camp)

	func _fire_one(u: Unit) -> void:
		super._fire_one(u)
		_close()

	func _inyeon_drop(d: Unit) -> void:
		super._inyeon_drop(d)
		_close()


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
	var games := int(args.get("games", "60"))
	if args.has("n4amp"):
		RtBattle.yeon_n4_amp = float(args.n4amp)
	if args.has("kfin"):
		RtBattle.yeon_kiin_fin_mul = float(args.kfin)
	if args.has("kcap"):
		RtBattle.yeon_kiin_cap_mul = float(args.kcap)
	var with_kiin := str(args.get("kiin", "0")) == "1"
	var ft := int(args.get("tier", "7"))      # 채우는 카드 · 상대 덱 등급
	for kv in str(args.get("capn", "")).split(",", false):      # --capn=4:1.0,3:1.3 —— 인원별 합동 상한 배수 시험
		var p2 := kv.split(":")
		Battle.inyeon_cap_n[int(p2[0])] = float(p2[1])
	var decks4 := []
	for nm in DB.INYEON:
		for p in DB.INYEON[nm]:
			if _card(p, 6) == "":
				continue
			var hi: Array = DB.INYEON[nm].filter(func(q): return q != p and _any(q, [7, 8]) != "")
			if hi.size() >= 3:
				var d4: Array = [_card(p, 6)] + hi.slice(0, 3).map(func(q): return _any(q, [7, 8]))
				if with_kiin:      # --kiin=1 —— 그 인연의 기인(다른 인물)을 하나 더 넣는다 (기인이 여는 연쇄)
					var used: Array = d4.map(func(k): return DB.person(k))
					for k in DB.C:
						if DB.C[k].kind == "kiin" and DB.ult_of(k) != null and DB.inyeon_of(k).has(nm) and not used.has(DB.person(k)):
							d4.append(k)
							break
					if d4.size() < 5:
						break
				decks4.append(d4)
				break
	print("4인 피해 ×%.2f · 기인 마무리 ×%.2f · 인연 상한 배수 %.2f · 기인 %.2f · 4인 배수 %.2f · 3인 배수 %.2f · 초월 합류 문턱 %.0f · 인연 덱 %d개" % [
		RtBattle.yeon_n4_amp, RtBattle.yeon_kiin_fin_mul, Battle.inyeon_cap_mul, RtBattle.yeon_kiin_cap_mul, float(Battle.inyeon_cap_n.get(4, Battle.inyeon_cap_mul)), float(Battle.inyeon_cap_n.get(3, Battle.inyeon_cap_mul)), RtBattle.yeon_up_join, decks4.size()])
	var rng := RandomNumberGenerator.new()
	rng.seed = 1122
	var by_n := {}             # n -> [pre 대비, max 대비]
	var first4 := 0
	var first4_win := 0
	var rem := []
	var t4 := []
	var lens := []
	var singles := []
	var ctl5 := []
	var c45 := []
	var w := {true: 0, false: 0}
	for g in games:
		var a: Array = decks4[g % decks4.size()].duplicate()
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
		var mine := "A" if side_a else "B"
		var marks := []
		for on in [true, false]:
			Battle.inyeon_enabled = on
			var bt := Probe.new(sd)
			bt.marks = marks
			var r: Dictionary = bt.run(DB.auto_place(a if side_a else b, "eorin"), "eorin", 100, null, DB.auto_place(b if side_a else a, "hagik"), "hagik", 100, null,
				"", "", [], {"A": "smart", "B": "smart"})
			Battle.inyeon_enabled = true
			bt.finish()
			var winner := "draw" if r.draw else ("A" if r.win else "B")
			if winner == mine:
				w[on] += 1
			if not on:
				for i in range(0, marks.size(), 2):
					var m0: Dictionary = marks[i]
					var m1: Dictionary = marks[i + 1]
					var v0: float = m0.get("v", bt._foe_sum(m0.camp)[0])
					var v1: float = m1.get("v", bt._foe_sum(m1.camp)[0])
					ctl5.append((v0 - v1) / maxf(1.0, v0))
				continue
			lens.append(float(r.len))
			singles.append_array(bt.singles)
			var got4 := false
			for rc in bt.recs:
				var n: int = rc.n
				if n < 2:
					continue
				if not by_n.has(n):
					by_n[n] = []
				by_n[n].append([rc.loss / maxf(1.0, rc.pre), rc.loss / maxf(1.0, rc.mx), rc.loss5 / maxf(1.0, rc.pre), rc.own / maxf(1.0, rc.pre), rc.own5 / maxf(1.0, rc.pre - rc.loss5), rc.pre / maxf(1.0, rc.mx)])
				if n >= 4 and not got4:
					got4 = true
					marks.append({"camp": rc.camp, "at": float(rc.t0)})
					marks.append({"camp": rc.camp, "at": float(rc.t0) + 5.0})
					c45.append(rc.loss5 / maxf(1.0, rc.pre))
					first4 += 1
					if winner == rc.camp:
						first4_win += 1
					rem.append(float(r.len) - float(rc.t0))
					t4.append(float(rc.t0))
	print("── %d판 · 평균 전투 %.1fs · 단독 고유기 %d번 적 총 병력 대비 평균 %.1f%% ──" % [games, _mean(lens), singles.size(), 100.0 * _mean(singles)])
	for n in [2, 3, 4]:
		if not by_n.has(n):
			print("  %d인 연쇄 없음" % n)
			continue
		var a0: Array = by_n[n].map(func(x): return x[0])
		var a1: Array = by_n[n].map(func(x): return x[1])
		var a2: Array = by_n[n].map(func(x): return x[2])
		var r0: Array = by_n[n].map(func(x): return x[3])
		var r5: Array = by_n[n].map(func(x): return minf(x[4], 20.0))
		var g35 := a0.filter(func(x): return x > 0.35).size()
		var g50 := a0.filter(func(x): return x > 0.5).size()
		var hi: Array = by_n[n].filter(func(x): return x[0] > 0.5).map(func(x): return x[5])
		var lo: Array = by_n[n].filter(func(x): return x[0] <= 0.5).map(func(x): return x[5])
		print("  %d인 연쇄 %d번 —— 적 현재 병력 대비 평균 %.1f%% (중앙 %.1f · 35%%↑ %d%% · 50%%↑ %d%%) · 적 최대 대비 %.1f%% · 5초 뒤까지 %.1f%% · 병력비(내/적) %.2f → 5초 뒤 중앙 %.2f · 적 남은 병력(최대 대비) 50%%↑ 때 %.0f%% / 그 밖 %.0f%%" % [
			n, a0.size(), 100.0 * _mean(a0), 100.0 * _med(a0), roundi(100.0 * g35 / a0.size()), roundi(100.0 * g50 / a0.size()), 100.0 * _mean(a1), 100.0 * _mean(a2), _med(r0), _med(r5), 100.0 * _mean(hi), 100.0 * _mean(lo)])
	print("  4인 연쇄 난 판 %d/%d · 쏜 쪽 승 %d (%.0f%%) · 발동 %.1fs · 발동 뒤 남은 시간 평균 %.1fs (중앙 %.1f)" % [first4, games, first4_win, 100.0 * first4_win / maxf(1, first4), _mean(t4), _mean(rem), _med(rem)])
	print("  4인 연쇄 뒤 5초 적 손실 %.1f%% 대 같은 판 인연 끔 같은 시각 5초 %.1f%% (연쇄 몫 %+.1fp) · 인연 덱 승률 끔 %.0f%% → 켬 %.0f%%" % [
		100.0 * _mean(c45), 100.0 * _mean(ctl5), 100.0 * (_mean(c45) - _mean(ctl5)), 100.0 * w[false] / games, 100.0 * w[true] / games])
	get_tree().quit()


func _mean(a: Array) -> float:
	var s := 0.0
	for x in a:
		s += float(x)
	return s / maxf(1, a.size())


func _med(a: Array) -> float:
	if a.is_empty():
		return 0.0
	var b := a.duplicate()
	b.sort()
	return float(b[b.size() / 2])
