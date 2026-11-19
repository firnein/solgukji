extends Node
## 11/19 기 찼는데 못 쓴 까닭을 관문별로 센다 (영리 정책) —— 판정은 그대로, 묻는 순간만 엿본다
## 실행: godot --headless --path . res://tests/temper_block.tscn [-- --n=30]

class Spy extends RtBattle:
	var seen := {}     # 기질 -> 관문 -> 수
	func _note(u: Unit, why: String) -> void:
		var d: Dictionary = seen.get(u.temper, {})
		d[why] = int(d.get(why, 0)) + 1
		seen[u.temper] = d
	func can_ult(u: Unit) -> bool:
		if u.ult != null and u.charges > 0 and u.gauge >= 100.0 and u.alive:
			if _tm < float(u.ult.get("wait", 14.0)) * _tw(u, "wait"):
				_note(u, "1 장수 대기")
			else:
				var ok := super.can_ult(u)
				if not ok:
					var wn := 0
					for w in _wind:
						if w.camp == u.camp: wn += 1
					if wn >= wind_max: _note(u, "2a 동시 기 모으기")
					elif _tm - _ult_t < ult_gap * _gap_tier(): _note(u, "2b 전역 간격")
					elif _tm - _ult_side_t[u.camp] < ult_side_sec: _note(u, "2c 진영 간격(초)")
					elif act_n - _ult_last[u.camp] < Battle.ULT_SIDE_GAP * turn_mul: _note(u, "2d 진영 간격(행동 수)")
					elif not _reult_ok(u): _note(u, "2e 재사용 대기")
					else: _note(u, "2f 봉인 등")
				return ok
		return super.can_ult(u)
	func _ult_ok(u: Unit, ult_t: String) -> bool:
		if not _temper_ok(u):
			_note(u, "3 기질 조건")
			return false
		var ok := super._ult_ok(u, ult_t)
		_note(u, "5 통과" if ok else "4 값어치")
		return ok

func _ready() -> void:
	var args := {}
	for arg in OS.get_cmdline_user_args():
		var kv := arg.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	var n := int(args.get("n", "30"))
	var tot := {}
	var waits := {}
	for i in n:
		var tl: Array = Array(str(args.get("tiers", "6,7,8")).split(",")).map(func(x): return int(x))
		var tier: int = tl[i % tl.size()]
		var pool := DB.by_tier(tier).filter(func(k): return not DB.is_foe(k))
		var rng := RandomNumberGenerator.new()
		rng.seed = 55100 + i
		var a := _pick(pool, rng)
		var b := _pick(pool, rng)
		var bt := Spy.new(55100 + i)
		bt.run(DB.auto_place(a, "eorin"), "eorin", 100, null, DB.auto_place(b, "hagik"), "hagik", 100, null, "", "", [], {"A": "smart", "B": "smart"})
		for tp in bt.seen:
			var d: Dictionary = tot.get(tp, {})
			for k in bt.seen[tp]:
				d[k] = int(d.get(k, 0)) + int(bt.seen[tp][k])
			tot[tp] = d
		for u in bt.units:
			if u.ult != null:
				var w: Array = waits.get(u.temper, [0.0, 0])
				w[0] += float(u.ult.get("wait", 14.0)) * bt._tw(u, "wait")
				w[1] += 1
				waits[u.temper] = w
	for tp in tot:
		var d: Dictionary = tot[tp]
		var s := 0
		for k in d: s += int(d[k])
		var ks := d.keys()
		ks.sort()
		var line := "%s (장수 대기 평균 %.1f초): " % [tp, waits[tp][0] / waits[tp][1]]
		for k in ks:
			line += "%s %d%%  " % [k, 100 * int(d[k]) / s]
		print(line)
	get_tree().quit()

func _pick(pool: Array, rng: RandomNumberGenerator) -> Array:
	var out := []
	var people := []
	var cand := pool.duplicate()
	while out.size() < 9 and not cand.is_empty():
		var k: String = cand.pop_at(rng.randi_range(0, cand.size() - 1))
		if not people.has(DB.person(k)):
			out.append(k)
			people.append(DB.person(k))
	return out
