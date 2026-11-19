extends Node
## 11/19 한 장수(조인 · 전위)의 사기가 어느 함수에서 깎이나 —— 함수 앞뒤로 재고 안쪽 함수 몫은 뺀다 (판정은 그대로)
## 실행: godot --headless --path . res://tests/morale_spy.tscn [-- --who=조인 --n=8]

class Spy extends RtBattle:
	var key := ""
	var me: Unit = null
	var got := {}
	var _stk := []
	func _me() -> Unit:
		if me == null:
			for u in units:
				if u.key == key: me = u
		return me
	func _sp_in() -> void:
		_stk.append([_me().morale if _me() != null else 0.0, 0.0])
	func _sp_out(name: String) -> void:
		var f: Array = _stk.pop_back()
		var d: float = (_me().morale if _me() != null else 0.0) - float(f[0])
		var own: float = d - float(f[1])
		if own < -0.001:
			got[name] = float(got.get(name, 0.0)) - own
		if not _stk.is_empty():
			_stk[-1][1] += d
	func morale_hit(d: Unit, amt: float, who: String, spread: int, src: Unit) -> void:
		_sp_in(); super.morale_hit(d, amt, who, spread, src); _sp_out("사기 피해(" + (src.c.tag if src != null else "?") + ")")
	func _after_hit(a: Unit, d: Unit, loss: float) -> void:
		_sp_in(); super._after_hit(a, d, loss); _sp_out("교란(맞은 뒤)")
	func rout(u: Unit, why: String, cause := "effect") -> void:
		_sp_in(); super.rout(u, why, cause); _sp_out("옆 부대 패주 충격")
	func _check_collapse(frac: float) -> void:
		_sp_in(); super._check_collapse(frac); _sp_out("붕괴 · 결전")
	func tick_status(frac := 1.0, final := true) -> void:
		_sp_in(); super.tick_status(frac, final); _sp_out("상태이상(공포 등)")
	func _settle(frac: float, final: bool) -> String:
		_sp_in(); var r := super._settle(frac, final); _sp_out("병력 50% · 25% 문턱 등 정산"); return r
	func _paeup_tick(dt: float) -> void:
		_sp_in(); super._paeup_tick(dt); _sp_out("패업(위진소요진 등)")
	func _do_minor(u: Unit, t: Unit, m: Dictionary, mk: String, foes: Array, allies: Array) -> void:
		_sp_in(); super._do_minor(u, t, m, mk, foes, allies); _sp_out("잔기술")
	func phys_hit(a: Unit, d: Unit, mult: float, no_counter := false, pierce := 0.0) -> void:
		_sp_in(); super.phys_hit(a, d, mult, no_counter, pierce); _sp_out("타격 안(" + a.c.tag + ")")
	func check_rout() -> void:
		_sp_in(); super.check_rout(); _sp_out("패주 판정")

func _ready() -> void:
	var args := {}
	for arg in OS.get_cmdline_user_args():
		var kv := arg.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	var who := str(args.get("who", "조인"))
	var n := int(args.get("n", "8"))
	var k0: String = DB.C.keys().filter(func(k): return DB.person(k) == who and not DB.is_foe(k))[0]
	var tier: int = DB.C[k0].tier
	var pool := DB.by_tier(tier).filter(func(k): return not DB.is_foe(k) and DB.person(k) != who)
	var tot := {}
	var ends := []
	for i in n:
		var rng := RandomNumberGenerator.new()
		rng.seed = 99100 + i
		var a := [k0]
		var people := [who]
		while a.size() < 9:
			var k: String = pool[rng.randi_range(0, pool.size() - 1)]
			if not people.has(DB.person(k)):
				a.append(k); people.append(DB.person(k))
		var b := []
		people = []
		while b.size() < 9:
			var k: String = pool[rng.randi_range(0, pool.size() - 1)]
			if not people.has(DB.person(k)):
				b.append(k); people.append(DB.person(k))
		var bt := Spy.new(99100 + i)
		var pa := DB.auto_place(a, "eorin")
		bt.key = "A" + str(0)
		var r: Dictionary = {}
		# key 는 roster 순서 —— 먼저 한 번 돌려 key 를 알아낸다 (같은 시드라 결과 같음)
		var probe: Dictionary = RtBattle.new(99100 + i).run(pa, "eorin", 100, null, DB.auto_place(b, "hagik"), "hagik", 100, null, "", "", [], {"A": "smart", "B": "smart"})
		for rr in probe.roster:
			if str(rr.id) == k0 and str(rr.camp) == "A": bt.key = str(rr.key)
		r = bt.run(pa, "eorin", 100, null, DB.auto_place(b, "hagik"), "hagik", 100, null, "", "", [], {"A": "smart", "B": "smart"})
		for k in bt.got:
			tot[k] = float(tot.get(k, 0.0)) + float(bt.got[k])
		var m := bt._me()
		ends.append("%s 병력 %d%% 사기 %d" % ["생존" if m.alive else ("패주" if m.troops > 0 else "전멸"), int(100 * m.troops / m.max), int(m.morale)])
	var ks := tot.keys()
	ks.sort_custom(func(x, y): return tot[x] > tot[y])
	print(who, " %d판 끝: " % n, ends)
	print("사기를 잃은 곳 (합, 판당): ", ks.map(func(k): return "%s %d" % [k, tot[k] / n]))
	get_tree().quit()
