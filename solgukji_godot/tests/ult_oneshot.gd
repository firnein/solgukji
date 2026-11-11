extends Node
## 고유기 '한 방' 점검 (11/7 사용자: 고유기 한 방으로 게임이 그냥 끝나버리는 판이 많다 —— 신화 주유 등)
## 실행: godot --headless --path . res://tests/ult_oneshot.tscn -- --tiers=6,7,8 --games=60 [--top=10] [--who=주유,여포] [--min=4] [--mix=rr] [--cap= --decay= --rwait= --rtemper= --allr= --alln= --inyeon=0|1 --capmul=]
## 같은 등급 무작위 9장끼리 영리 대 영리 (--mix=rr 이면 비용 약 620 리그전 덱 넷 —— budget_mix --set=rr 과 같은 구성 —— 에서 무작위로 둘). 고유기 한 번마다
##   ① 증발: 그 순간 상대 전체 병력(살아 있는 부대 합)에서 바로 사라진 비율 (처형 · 패주로 무너진 부대의 남은 병력 포함)
##   ② 5초 손실: 발동 뒤 5초 동안 상대 전체 병력이 줄어든 비율 (화상 · 패주 전염까지)
##   ③ 한 방 끝: 발동 때 상대 병력이 처음의 40% 넘게 남아 있었는데 5초 안에 쓴 쪽 승리로 끝난 판
##   ④ 격파: 그 한 번에 무너진 부대 수
##   ⑤ 맞은 부대: 그 고유기에 병력을 잃은 적 부대 수 · 부대마다 직접 피해(그 부대 최대 병력 대비, 처형 제외)
## 를 모아 등급별 · 장수별로 집계한다. 장수별 표는 평균 증발 비율 순 (--min 번 이상 쓴 장수만), --who 로 지목한 장수는 늘 보인다.
## 고유기 피해 몫 = 고유기 직접 피해 / 전체 직접 피해 (화상 같은 지속 피해는 빼고).

const RR := {"몰빵": {"신화": 1, "불멸": 5, "희귀": 3}, "초월섞음": {"신화": 1, "불멸": 4, "초월": 2, "기인": 1, "희귀": 1},
	"기인섞음": {"신화": 1, "불멸": 4, "기인": 3, "희귀": 1}, "고루": {"신화": 1, "불멸": 3, "초월": 3, "기인": 2}}


## 고유기마다 앞뒤 상대 병력을 재는 엔진 (판정은 RtBattle 그대로)
class Probe extends RtBattle:
	var probes := []
	var start_tr := {"A": 0.0, "B": 0.0}


	func _foe_troops(cp: String) -> float:
		var s := 0.0
		for o in units:
			if o.alive and o.camp != cp:
				s += maxf(0.0, o.troops)
		return s


	func _do_ult(u: Unit, foes: Array, allies: Array) -> void:
		if start_tr.A <= 0.0:
			for o in units:
				start_tr[o.camp] += o.max
		var live: Array = foes.filter(func(o): return o.alive)
		var before := 0.0
		var tb := {}
		for o in live:
			before += maxf(0.0, o.troops)
			tb[o] = maxf(0.0, o.troops)
		super._do_ult(u, foes, allies)
		var after := 0.0
		var kills := 0
		var hit := []          # 맞은 부대마다 직접 피해 (최대 병력 대비)
		for o in live:
			after += maxf(0.0, o.troops) if o.alive else 0.0      # 무너진 부대는 남은 병력도 잃은 것
			if not o.alive or o.troops <= 0.0:
				kills += 1
			var direct: float = float(tb[o]) - maxf(0.0, o.troops)
			if direct > 0.5:
				hit.append(direct / maxf(1.0, o.max))
		var foe_cp := "B" if u.camp == "A" else "A"
		probes.append({"tm": _tm, "camp": u.camp, "key": u.key, "id": u.c.id, "name": u.c.name, "tier": u.c.tier, "nth": u.ult_n,
			"before": before, "foe_hp": before / maxf(1.0, start_tr[foe_cp]), "now": (before - after) / maxf(1.0, before),
			"kills": kills, "n0": live.size(), "loss5": -1.0, "hit": hit, "coll0": bool(_collapsed[foe_cp]), "coll5": false})


	func _settle(frac: float, final: bool) -> String:
		for p in probes:
			if p.loss5 < 0.0 and _tm >= p.tm + 5.0 - 0.001:
				p.loss5 = 1.0 - _foe_troops(p.camp) / maxf(1.0, p.before)
				p.coll5 = bool(_collapsed["B" if p.camp == "A" else "A"])
		return super._settle(frac, final)


	## 끝난 뒤 —— 5초가 안 지난 발동은 끝 시점 값으로
	func close(winner: String) -> void:
		for p in probes:
			if p.loss5 < 0.0:
				p.loss5 = 1.0 - _foe_troops(p.camp) / maxf(1.0, p.before)
				p.coll5 = bool(_collapsed["B" if p.camp == "A" else "A"]) or winner == p.camp
			p["end_in5"] = _tm - p.tm <= 5.0 and winner == p.camp
			p["trig"] = not p.coll0 and p.coll5      # 이 고유기 뒤 5초 안에 상대가 총붕괴(또는 쓴 쪽 승리) —— 판을 끝낸 한 방
			p["oneshot"] = p.end_in5 and p.foe_hp >= 0.4


func _pool(g: String) -> Array:
	var t: int = {"신화": 8, "불멸": 7, "초월": 6, "기인": 5, "희귀": 4}[g]
	return DB.by_tier(t).filter(func(k): return (g == "기인") == DB.is_kiin(k))


## 구성 {등급: 장수 수} 대로 무작위 9장 (같은 인물 겹치지 않게) —— budget_mix 와 같은 방식
func _mix_deck(mix: Dictionary, rng: RandomNumberGenerator) -> Array:
	var out := []
	for g in mix:
		var src := _pool(g)
		for i in int(mix[g]):
			var cand := src.filter(func(k): return not out.any(func(x): return DB.person(x) == DB.person(k)))
			out.append(cand[rng.randi() % cand.size()])
	return out


func _ready() -> void:
	var args := {}
	for s in OS.get_cmdline_user_args():
		var kv := s.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	var games := int(args.get("games", "60"))
	var top := int(args.get("top", "10"))
	var min_n := int(args.get("min", "4"))
	var who: Array = Array(str(args.get("who", "주유,주태")).split(",")) if args.get("who", "") != "" else []
	var mix: bool = str(args.get("mix", "")) == "rr"
	print(knobs(args))
	var tiers: Array = [0] if mix else Array(str(args.get("tiers", "6,7,8")).split(",")).map(func(x): return int(x))
	var rng := RandomNumberGenerator.new()
	rng.seed = 23
	var per := {}      # "인물(등급)" -> {n, now, loss5, kills, ge30, end5, oneshot, tier, person, nth2, hit_n, hit_sum, hit30}
	var t_start := Time.get_ticks_msec()
	for t in tiers:
		var n := 0
		var now_sum := 0.0
		var loss5_sum := 0.0
		var kills_sum := 0
		var ge := [0, 0, 0]       # 증발 20 · 30 · 40% 이상
		var l5 := [0, 0, 0]       # 5초 손실 20 · 30 · 40% 이상
		var end5 := 0
		var trig := 0             # 총붕괴 유발 (5초 안)
		var oneshot := 0
		var games_oneshot := 0
		var len_sum := 0.0
		var dmg_sum := 0.0
		var udmg_sum := 0.0
		var n_hitult := 0         # 적 부대를 하나라도 맞힌 고유기
		var hits := 0             # 맞은 부대 (연)
		var hit_sum := 0.0
		var hge := [0, 0, 0]      # 한 부대 직접 피해 20 · 30 · 50% 이상
		var hmax := 0.0
		for i in games:
			var a := []
			var b := []
			if mix:
				var names: Array = RR.keys()
				a = _mix_deck(RR[names[rng.randi() % names.size()]], rng)
				b = _mix_deck(RR[names[rng.randi() % names.size()]], rng)
			else:
				var pool: Array = DB.by_tier(t)
				for j in 9:
					a.append(pool[rng.randi() % pool.size()])
					b.append(pool[rng.randi() % pool.size()])
			var bt := Probe.new(rng.randi() % 100000)
			var fb := "eorin" if mix else "hagik"
			var r := bt.run(DB.auto_place(a, "eorin"), "eorin", 100, null, DB.auto_place(b, fb), fb, 100, null, "", "", [], {"A": "smart", "B": "smart"})
			var winner := "A" if r.win else ("draw" if r.draw else "B")
			bt.close(winner)
			len_sum += float(r.len)
			dmg_sum += float(bt.stats.dmg)
			udmg_sum += float(bt.stats.ult_dmg)
			var g_one := false
			for p in bt.probes:
				n += 1
				now_sum += p.now
				loss5_sum += p.loss5
				kills_sum += p.kills
				for k in 3:
					if p.now >= 0.2 + 0.1 * k: ge[k] += 1
					if p.loss5 >= 0.2 + 0.1 * k: l5[k] += 1
				if p.end_in5: end5 += 1
				if p.trig: trig += 1
				if p.oneshot:
					oneshot += 1
					g_one = true
				var ph: Array = p.hit
				if not ph.is_empty():
					n_hitult += 1
				for x in ph:
					hits += 1
					hit_sum += float(x)
					hmax = maxf(hmax, float(x))
					if float(x) >= 0.2: hge[0] += 1
					if float(x) >= 0.3: hge[1] += 1
					if float(x) >= 0.5: hge[2] += 1
				var pk := "%s(%d)" % [DB.person(p.id), p.tier]
				if not per.has(pk):
					per[pk] = {"n": 0, "now": 0.0, "loss5": 0.0, "kills": 0, "ge30": 0, "end5": 0, "oneshot": 0, "tier": p.tier, "person": DB.person(p.id), "nth2": 0,
						"hit_n": 0, "hit_sum": 0.0, "hit30": 0, "trig": 0}
				var q: Dictionary = per[pk]
				q.n += 1
				q.now += p.now
				q.loss5 += p.loss5
				q.kills += p.kills
				if p.now >= 0.3: q.ge30 += 1
				if p.end_in5: q.end5 += 1
				if p.oneshot: q.oneshot += 1
				if p.trig: q.trig += 1
				if p.nth >= 2: q.nth2 += 1
				q.hit_n += ph.size()
				for x in ph:
					q.hit_sum += float(x)
					if float(x) >= 0.3: q.hit30 += 1
			if g_one:
				games_oneshot += 1
		var label := "리그전 덱(비용 약 620)" if mix else "등급 %d" % t
		print("%s (%d판 · 전투 %.1f초): 고유기 %d번(판당 %.1f) · 평균 증발 %.1f%% · 평균 5초 손실 %.1f%% · 격파 %.2f부대/번 · 고유기 피해 몫 %.0f%%" % [
			label, games, len_sum / games, n, float(n) / games, 100.0 * now_sum / maxf(1, n), 100.0 * loss5_sum / maxf(1, n), float(kills_sum) / maxf(1, n),
			100.0 * udmg_sum / maxf(1.0, dmg_sum)])
		print("   증발 20 · 30 · 40%% 이상: %.0f · %.0f · %.0f%% / 5초 손실 20 · 30 · 40%% 이상: %.0f · %.0f · %.0f%% / 5초 안 승리로 끝 %.0f%% / 한 방 끝(상대 40%% 넘게 남았는데) %.0f%% —— 판 기준 %.0f%% / 5초 안 총붕괴 유발 %.0f%% (판당 %.2f번)" % [
			100.0 * ge[0] / maxf(1, n), 100.0 * ge[1] / maxf(1, n), 100.0 * ge[2] / maxf(1, n),
			100.0 * l5[0] / maxf(1, n), 100.0 * l5[1] / maxf(1, n), 100.0 * l5[2] / maxf(1, n),
			100.0 * end5 / maxf(1, n), 100.0 * oneshot / maxf(1, n), 100.0 * games_oneshot / games, 100.0 * trig / maxf(1, n), float(trig) / games])
		print("   맞은 부대: 적을 맞힌 고유기 %d번 · 번당 %.1f부대 / 한 부대 직접 피해(최대 병력 대비) 평균 %.1f%% · 20%% 넘게 %.0f%% · 30%% 넘게 %.0f%% · 50%% 넘게 %.0f%% · 최대 %.0f%%" % [
			n_hitult, float(hits) / maxf(1, n_hitult), 100.0 * hit_sum / maxf(1, hits), 100.0 * hge[0] / maxf(1, hits), 100.0 * hge[1] / maxf(1, hits),
			100.0 * hge[2] / maxf(1, hits), 100.0 * hmax])
	# 장수별 —— 평균 증발 순
	var ks: Array = per.keys().filter(func(k): return per[k].n >= min_n)
	ks.sort_custom(func(x, y): return per[x].now / per[x].n > per[y].now / per[y].n)
	print("장수(등급) · 횟수 · 평균 증발% · 30% 넘게 % · 5초 손실% · 격파/번 · 5초 안 승리 끝% · 한 방 끝% · 2회째 이상 · 맞은 부대/번 · 부대당 직접 피해% · 부대 30% 넘게 % · 총붕괴 유발%")
	var shown := []
	for k in ks.slice(0, top):
		shown.append(k)
		_row(k, per[k])
	for k in per:
		if shown.has(k):
			continue
		if who.any(func(w): return per[k].person == w):
			_row(k, per[k])
	# 판을 끝낸 장수 —— 5초 안 총붕괴 유발 비율 순 (--min 번 이상)
	var ko: Array = per.keys().filter(func(k): return per[k].trig > 0 and per[k].n >= min_n)
	ko.sort_custom(func(x, y): return float(per[x].trig) / per[x].n > float(per[y].trig) / per[y].n)
	print("── 총붕괴 유발 비율 순 (5초 안에 상대가 총붕괴 —— 판을 끝낸 한 방)")
	for k in ko.slice(0, top):
		_row(k, per[k])
	print("소요 %.1f초" % ((Time.get_ticks_msec() - t_start) / 1000.0))
	get_tree().quit()


func _row(k: String, q: Dictionary) -> void:
	print("   %s · %d · %.0f · %.0f · %.0f · %.2f · %.0f · %.0f · %d · %.1f · %.0f · %.0f · %.0f" % [k, q.n, 100.0 * q.now / q.n, 100.0 * q.ge30 / q.n, 100.0 * q.loss5 / q.n,
		float(q.kills) / q.n, 100.0 * q.end5 / q.n, 100.0 * q.oneshot / q.n, q.nth2, float(q.hit_n) / q.n, 100.0 * q.hit_sum / maxf(1, q.hit_n), 100.0 * q.hit30 / maxf(1, q.hit_n),
		100.0 * q.trig / q.n])


## 고유기 조정값 바꿔 보기 (이번 실행만, 11/7 2차) —— --cap=0.25,0.25,0.3 (초월 · 불멸 · 신화 한 방 상한, 0 이면 끔) · --decay=0.6 (재사용 감쇠) ·
## --rwait=0.5 (재발동 대기 배율) · --rtemper=수호:2.5,분노:2 (기질별 재발동 대기 배율, 0 이면 끔) · --allr=300 (고유기 '적 전체' 반지름, 0 이면 전장 전체) · --alln=4 (최대 부대 수)
static func knobs(args: Dictionary) -> String:
	if args.has("cap"):
		var v: Array = Array(str(args.cap).split(",")).map(func(x): return float(x))
		Battle.ult_cap = {} if v.size() == 1 and float(v[0]) <= 0.0 else {6: v[0], 7: v[mini(1, v.size() - 1)], 8: v[mini(2, v.size() - 1)]}
	if args.has("decay"):
		Battle.reult_decay = float(args.decay)
	if args.has("rwait"):
		Battle.reult_wait = float(args.rwait)
	if args.has("rtemper"):
		var rt := {}
		for kv in str(args.rtemper).split(","):
			var p := kv.split(":")
			if p.size() == 2:
				rt[p[0]] = float(p[1])
		Battle.reult_temper = rt
	if args.has("allr"):
		RtBattle.ult_all_r = float(args.allr)
	if args.has("alln"):
		RtBattle.ult_all_n = int(args.alln)
	if args.has("inyeon"):      # 11/11 인연 합동 고유기 —— --inyeon=0 이면 끈다 (고치기 전과 같은 값 · 짝 비교)
		Battle.inyeon_enabled = str(args.inyeon) != "0"
	if args.has("capmul"):
		Battle.inyeon_cap_mul = float(args.capmul)
	return "고유기 조정값 —— 한 방 상한 %s · 재사용 감쇠 %.2f · 재발동 대기 ×%.2f · 기질별 재발동 대기 %s · '적 전체' %s · %s" % [
		str(Battle.ult_cap) if not Battle.ult_cap.is_empty() else "없음", Battle.reult_decay, Battle.reult_wait,
		str(Battle.reult_temper) if not Battle.reult_temper.is_empty() else "없음",
		"반지름 %d" % roundi(RtBattle.ult_all_r) if RtBattle.ult_all_r > 0.0 else "전장 전체",
		"최대 %d부대" % RtBattle.ult_all_n if RtBattle.ult_all_n > 0 else "부대 수 제한 없음"]
