extends Node
## motion.5 잔여 점검: 실제 공격 경로와 전설 주유의 동일 조건 교체 비교.
const FORMS := ["eorin", "hagik", "bongsi", "anwol"]
const DAMAGE := ["basic", "minor", "skill", "ultimate", "counter", "other"]

class Probe extends RtBattle:
	var contributions := {}
	var minor_depth := 0
	func row(key: String) -> Dictionary:
		if not contributions.has(key):
			contributions[key] = {"basic": 0.0, "minor": 0.0, "skill": 0.0, "ultimate": 0.0,
				"counter": 0.0, "other": 0.0, "actions": 0, "hits": 0, "charges": 0, "braces": 0,
				"first_hit": -1.0, "status_applications": 0}
		return contributions[key]
	func _do_minor(u: Unit, target: Unit, minor: Dictionary, kind: String, foes: Array, allies: Array) -> void:
		minor_depth += 1
		super._do_minor(u, target, minor, kind, foes, allies)
		minor_depth -= 1
	func act(u: Unit) -> void:
		row(u.key).actions += 1
		super.act(u)
	func L(cls: String, message: String, extra: Dictionary = {}) -> void:
		super.L(cls, message, extra)
		if not extra.get("fx", "") in ["phys", "int"]:
			return
		var a: Unit = null
		var d: Unit = null
		for u in units:
			if u.key == extra.get("a", ""): a = u
			if u.key == extra.get("f", ""): d = u
		if a == null or d == null or a.camp == d.camp:
			return
		var kind := "other"
		if a.countering: kind = "counter"
		elif _in_ult: kind = "ultimate"
		elif a.in_skill: kind = "skill"
		elif minor_depth > 0: kind = "minor"
		elif a.cleaving: kind = "other"
		elif _ph == "act" and _who == a.key: kind = "basic"
		var r := row(a.key)
		# n can overkill. Count actual primary-target troop loss, excluding shared damage.
		var amount := float(extra.get("n", 0.0))
		r[kind] += clampf(amount + minf(d.troops, 0.0), 0.0, amount)
		r.hits += 1
		if r.first_hit < 0.0: r.first_hit = _tm
	func phys_hit(a: Unit, d: Unit, mult: float, no_counter := false, pierce := 0.0) -> void:
		var begin := ev.size()
		super.phys_hit(a, d, mult, no_counter, pierce)
		for i in range(begin, ev.size()):
			var e: Dictionary = ev[i]
			if e.get("a") == a.key and e.get("f") == d.key and e.get("fx") in ["phys", "int"]:
				if e.get("painted_charge") == "hit": row(a.key).charges += 1
				if e.get("painted_charge") == "brace": row(a.key).braces += 1
				break
	func inflict(a: Unit, d: Unit, kind: String, value: float, duration: int) -> void:
		var begin := ev.size()
		super.inflict(a, d, kind, value, duration)
		if a != null:
			for i in range(begin, ev.size()):
				if ev[i].get("fx") == "status" and ev[i].get("f") == d.key:
					row(a.key).status_applications += 1

func pick_unique(pool: Array, count: int, rng: RandomNumberGenerator, excluded: Array = []) -> Array:
	var candidates := pool.filter(func(k): return not excluded.has(DB.person(k)))
	var out := []
	while out.size() < count and not candidates.is_empty():
		var index := rng.randi_range(0, candidates.size() - 1)
		var key: String = candidates[index]
		out.append(key)
		candidates = candidates.filter(func(k): return DB.person(k) != DB.person(key))
	assert(out.size() == count)
	return out

func observation(bt: Probe, result: Dictionary, camp: String) -> Array:
	var out := []
	for u in bt.units:
		if u.camp != camp: continue
		var r := bt.row(u.key).duplicate()
		r.merge({"id": u.c.id, "name": u.c.name, "tag": u.c.tag, "tier": u.c.tier,
			"slot": u.slot, "max": u.max, "alive": u.alive, "left": maxf(0.0, u.troops),
			"dot": u.dot, "healing": u.theal, "support_gain": u.gain, "ults": u.ult_n})
		out.append(r)
	return out

func verify_probe() -> void:
	var pool := DB.by_tier(5).filter(func(k): return not DB.is_foe(k))
	var a := DB.auto_place(pool.slice(0, 9), "eorin")
	var b := DB.auto_place(pool.slice(9, 18), "hagik")
	var ordinary := RtBattle.new(65100).run(a, "eorin", 100, null, b, "hagik", 100, null, "", "", [], {"A": "auto", "B": "auto"})
	var measured := Probe.new(65100).run(a, "eorin", 100, null, b, "hagik", 100, null, "", "", [], {"A": "auto", "B": "auto"})
	assert(JSON.stringify(ordinary.ev) == JSON.stringify(measured.ev), "Measurement must not alter events or RNG")
	assert(ordinary.win == measured.win and ordinary.left == measured.left and ordinary.eLeft == measured.eLeft)
	print("PASS role probe purity: identical events / outcome / survivors")

func _ready() -> void:
	get_tree().create_timer(600.0).timeout.connect(func(): get_tree().quit(1))
	var args := {}
	for arg in OS.get_cmdline_user_args():
		var pair := arg.trim_prefix("--").split("=", true, 1)
		args[pair[0]] = pair[1] if pair.size() > 1 else "1"
	verify_probe()
	if args.has("verify-only"):
		get_tree().quit()
		return
	var trials := int(args.get("trials", "12"))
	var report := {"seed": 65100, "trials": trials, "engine": Engine.get_version_info().string,
		"role_runs": [], "zhou_yu_runs": [], "notes": "Direct damage excludes overkill/shared damage; DOT/healing/support use existing engine counters. No win-rate balance verdict from small samples."}
	var original_ults := Battle.ults_enabled
	if not args.has("zhou-only"):
		for tier in [5, 7, 8]:
			var pool := DB.by_tier(tier).filter(func(k): return not DB.is_foe(k))
			var rng := RandomNumberGenerator.new()
			rng.seed = 65100 + tier
			for trial in trials:
				var a := pick_unique(pool, 9, rng)
				var b := pick_unique(pool, 9, rng)
				var fa: String = FORMS[trial % FORMS.size()]
				var fb: String = FORMS[(trial + 1) % FORMS.size()]
				var seed_ := 65100 + trial
				for enabled in [true, false]:
					Battle.ults_enabled = enabled
					for mirror in [false, true]:
						var bt := Probe.new(seed_)
						var result := bt.run(DB.auto_place(b if mirror else a, fb if mirror else fa),
							fb if mirror else fa, 100, null, DB.auto_place(a if mirror else b, fa if mirror else fb),
							fa if mirror else fb, 100, null, "", "", [], {"A": "auto", "B": "auto"})
						report.role_runs.append({"tier": tier, "trial": trial, "ultimates": enabled, "mirror": mirror,
							"length": result.len, "units": observation(bt, result, "B" if mirror else "A")})
				print("ROLE_AUDIT tier=", tier, " trial=", trial + 1, "/", trials)
	var pool := DB.by_tier(5).filter(func(k): return not DB.is_foe(k) and not DB.is_kiin(k))
	var subject := ""
	for key in pool:
		if DB.person(key) == "주유": subject = key
	assert(subject != "", "Missing legendary Zhou Yu")
	var peers := pool.filter(func(k): return DB.C[k].tag == DB.C[subject].tag and DB.person(k) != "주유")
	peers.sort()
	peers = peers.slice(0, mini(3, peers.size()))
	var candidates := [subject] + peers
	var excluded: Array = candidates.map(func(k): return DB.person(k))
	var rng := RandomNumberGenerator.new()
	rng.seed = 75100
	Battle.ults_enabled = original_ults
	for trial in trials:
		var base := pick_unique(pool, 8, rng, excluded)
		var enemy := pick_unique(pool, 9, rng, excluded)
		for slot in [1, 7]:
			for key in candidates:
				var deck := base.duplicate()
				deck.insert(slot, key)
				for mirror in [false, true]:
					var bt := Probe.new(75100 + trial)
					var result := bt.run(enemy if mirror else deck, "eorin", 100, null,
						deck if mirror else enemy, "eorin", 100, null, "", "", [], {"A": "auto", "B": "auto"})
					var rows := observation(bt, result, "B" if mirror else "A")
					var r: Dictionary = rows.filter(func(u): return int(u.slot) == slot)[0]
					r.merge({"trial": trial, "mirror": mirror, "length": result.len,
						"win": (not result.win and not result.draw) if mirror else (result.win and not result.draw), "draw": result.draw})
					report.zhou_yu_runs.append(r)
		print("ZHOU_AUDIT trial=", trial + 1, "/", trials)
	Battle.ults_enabled = original_ults
	var path := "res://../build/motion5_role_audit.json"
	var output := FileAccess.open(path, FileAccess.WRITE)
	assert(output != null)
	output.store_string(JSON.stringify(report, "\t"))
	output.close()
	print("PASS role audit: ", report.role_runs.size(), " role battles / ", report.zhou_yu_runs.size(), " paired commander runs -> ", path)
	get_tree().quit()
