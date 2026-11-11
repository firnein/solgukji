extends Node
## 인연 합동 고유기 측정 (11/11) —— 실행: godot --headless --path . res://tests/inyeon_measure.tscn -- --mode=rate|shot|deck|avail [--tiers=6,7,8] [--games=30] [--names=호뢰관,적벽대전] [--capmul=1.5]
##   rate : 같은 시드 · 같은 무작위 덱으로 인연 끔 / 켬 짝 비교 —— 고유기 발동률 · 발동 부대당 횟수 · 첫 발동 · 2회 · 3회 · 전투 길이 · 합동 횟수 · 합류 수 · A 승률
##   shot : 고유기 한 번(단독) 대 합동 한 번(대표 + 합류 전체)이 한 부대에 앗는 병력 (그 부대 최대 병력 대비) —— 평균 · 최대 · 30%/50% 넘는 비율. --capmul=0 이면 합동 상한 없음
##   deck : 인연 구성원으로 짠 덱(그 등급 구성원 + 같은 등급 무작위) 대 같은 등급 무작위 덱 —— 켬/끔 승률 · 합동 횟수 (자리 바꿔 절반씩)
##   avail: 인연마다 등급별로 구성원 카드가 몇 명 있는지

const NAMES_DEFAULT := ["호뢰관", "적벽대전", "이교의 연", "소요진", "오장원", "완성의 변"]


## 고유기 한 번마다 맞은 부대의 손실(그 부대 최대 병력 대비)을 잰다. 합동이면 그룹 전체에서 부대별로 합친다
class Probe extends RtBattle:
	var singles := []          # 단독 고유기 한 번마다 [부대 손실, …]
	var joints := {}           # 대표 -> {부대: 합친 손실}
	var jsizes := {}           # 대표 -> 명

	func _do_ult(u: Unit, foes: Array, allies: Array) -> void:
		var live: Array = foes.filter(func(o): return o.alive)
		var tb := {}
		for o in live:
			tb[o] = maxf(0.0, o.troops)
		var grp: Dictionary = _ult_grp
		super._do_ult(u, foes, allies)
		var hit := {}
		for o in live:
			var lost: float = float(tb[o]) - (maxf(0.0, o.troops) if o.alive else 0.0)
			if lost > 0.5:
				hit[o] = lost / maxf(1.0, o.max)
		if grp.is_empty():
			singles.append(hit.values())
		else:
			var gk = grp.lead      # 사전은 값으로 해시되고 taken 이 바뀌므로 대표 장수를 열쇠로
			if not joints.has(gk):
				joints[gk] = {}
				jsizes[gk] = 0
			jsizes[gk] += 1
			for o in hit:
				joints[gk][o] = float(joints[gk].get(o, 0.0)) + float(hit[o])


func _args() -> Dictionary:
	var args := {}
	for s in OS.get_cmdline_user_args():
		var kv := s.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	return args


func _ready() -> void:
	var args := _args()
	var mode := str(args.get("mode", "rate"))
	var tiers: Array = Array(str(args.get("tiers", "6,7,8")).split(",")).map(func(x): return int(x))
	var games := int(args.get("games", "30"))
	if args.has("capmul"):
		Battle.inyeon_cap_mul = float(args.capmul)
	RtBattle.inyeon_gate_time = str(args.get("gate", "0")) == "1"      # 합류 장수도 대기 시간 · 재사용 대기를 지킨다 (시험용)
	print("합류도 대기 시간 지킴 %s · 합동 상한 배수 %.2f · 합류 시각 %s · 터짐 간격 %.2f초" % [str(RtBattle.inyeon_gate_time), Battle.inyeon_cap_mul, str(RtBattle.inyeon_join_at), RtBattle.inyeon_stagger])
	match mode:
		"rate":
			_rate(tiers, games)
		"shot":
			_shot(tiers, games)
		"deck":
			var names: Array = Array(str(args.get("names", ",".join(NAMES_DEFAULT))).split(","))
			_deck(tiers, games, names)
		"avail":
			_avail()
	get_tree().quit()


func _run(a: Array, b: Array, sd: int, on: bool, probe := false) -> Array:
	Battle.inyeon_enabled = on
	var bt: RtBattle = Probe.new(sd) if probe else RtBattle.new(sd)
	var r := bt.run(DB.auto_place(a, "eorin"), "eorin", 100, null, DB.auto_place(b, "hagik"), "hagik", 100, null, "", "", [], {"A": "smart", "B": "smart"})
	Battle.inyeon_enabled = true
	return [r, bt]


func _rand_deck(t: int, rng: RandomNumberGenerator, excl := []) -> Array:
	var pool: Array = DB.by_tier(t).filter(func(k): return not excl.has(DB.person(k)))
	var out := []
	for j in 9:
		out.append(pool[rng.randi() % pool.size()])
	return out


# ───────── rate ─────────
func _rate(tiers: Array, games: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	for t in tiers:
		var acc := {}
		for on in [false, true]:
			acc[on] = {"have": 0, "fired": 0, "n": 0, "first": 0.0, "twice": 0, "thrice": 0, "len": 0.0, "joint": 0, "units": 0, "n2": 0, "n3": 0, "join": 0, "cut": 0, "capped": 0, "fights_joint": 0, "win": 0, "ults": 0}
		var seeds := []
		var decks := []
		for i in games:
			var a := _rand_deck(t, rng)
			var b := _rand_deck(t, rng)
			decks.append([a, b, rng.randi() % 100000])
		for on in [false, true]:
			var s: Dictionary = acc[on]
			for d in decks:
				var rr := _run(d[0], d[1], d[2], on)
				var r: Dictionary = rr[0]
				var bt: RtBattle = rr[1]
				s.len += float(r.len)
				if r.win:
					s.win += 1
				var cnt := {}
				var ft := {}
				for e in r.ev:
					if e.get("fx") == "ult":
						var k: String = str(e.get("a", ""))
						cnt[k] = int(cnt.get(k, 0)) + 1
						if not ft.has(k):
							ft[k] = float(e.get("tm", 0.0))
				for u in bt.units:
					if u.ult != null:
						s.have += 1
						if cnt.has(u.key):
							s.fired += 1
							s.ults += int(cnt[u.key])
							s.first += float(ft[u.key])
							if int(cnt[u.key]) >= 2:
								s.twice += 1
							if int(cnt[u.key]) >= 3:
								s.thrice += 1
				var st: Dictionary = bt.stats
				s.joint += int(st.get("inyeon_joint", 0))
				s.units += int(st.get("inyeon_units", 0))
				s.n2 += int(st.get("inyeon_n2", 0))
				s.n3 += int(st.get("inyeon_n3", 0))
				s.join += int(st.get("inyeon_join", 0))
				s.cut += int(st.get("inyeon_cut", 0))
				s.capped += int(st.get("inyeon_capped", 0))
				if int(st.get("inyeon_joint", 0)) > 0:
					s.fights_joint += 1
		print("── 등급 %d (%d판 · 같은 시드 짝) ──" % [t, games])
		for on in [false, true]:
			var s: Dictionary = acc[on]
			print("  %s: 길이 %.1fs · 보유 %d 중 발동 %d (%.0f%%) · 발동 부대당 %.2f번 · 첫 발동 %.1fs · 2회↑ %.0f%% · 3회↑ %.0f%% · 판당 고유기 %.2f회 · 합동 %d (판 %d/%d · 2인 %d · 3인 %d · 합류 %d · 끊김 %d · 합동상한 걸림 %d) · A 승 %d" % [
				"켬" if on else "끔", s.len / games, s.have, s.fired, 100.0 * s.fired / maxf(1, s.have), float(s.ults) / maxf(1, s.fired), s.first / maxf(1, s.fired),
				100.0 * s.twice / maxf(1, s.have), 100.0 * s.thrice / maxf(1, s.have), float(s.ults) / games, s.joint, s.fights_joint, games, s.n2, s.n3, s.join, s.cut, s.capped, s.win])


# ───────── shot ─────────
func _shot(tiers: Array, games: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 23
	for t in tiers:
		var one := []        # 단독 한 번에 맞은 부대 손실
		var jn := []         # 합동 한 번에 맞은 부대 손실 (그룹 합)
		var jn_sz := []
		var n_single := 0
		var n_joint := 0
		for i in games:
			var a := _rand_deck(t, rng)
			var b := _rand_deck(t, rng)
			var sd := rng.randi() % 100000
			var rr := _run(a, b, sd, true, true)
			var pr: Probe = rr[1]
			for h in pr.singles:
				n_single += 1
				one.append_array(h)
			for g in pr.joints:
				n_joint += 1
				jn_sz.append(pr.jsizes[g])
				jn.append_array(pr.joints[g].values())
		print("── 등급 %d (%d판) ──" % [t, games])
		print("  단독 고유기 %d번 · 맞은 부대 %d · %s" % [n_single, one.size(), _dist(one)])
		print("  합동 고유기 %d번 (평균 %.2f명) · 맞은 부대 %d · %s" % [n_joint, _mean(jn_sz), jn.size(), _dist(jn)])


func _mean(a: Array) -> float:
	var s := 0.0
	for x in a:
		s += float(x)
	return s / maxf(1, a.size())


func _dist(a: Array) -> String:
	if a.is_empty():
		return "—"
	var mx := 0.0
	var g30 := 0
	var g50 := 0
	for x in a:
		mx = maxf(mx, float(x))
		if float(x) > 0.3:
			g30 += 1
		if float(x) > 0.5:
			g50 += 1
	return "한 부대 평균 %.1f%% · 최대 %.0f%% · 30%% 넘음 %.0f%% · 50%% 넘음 %.1f%%" % [100.0 * _mean(a), 100.0 * mx, 100.0 * g30 / a.size(), 100.0 * g50 / a.size()]


# ───────── deck ─────────
func _members(name_: String, t: int) -> Array:
	var out := []
	for p in DB.INYEON[name_]:
		for k in DB.by_tier(t):
			if DB.person(k) == p and DB.ult_of(k) != null and not DB.is_kiin(k):
				out.append(k)
				break
	return out


func _deck(tiers: Array, games: int, names: Array) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 31
	for t in tiers:
		print("── 등급 %d ──" % t)
		var pool_w := {false: 0, true: 0}      # 인연 덱 전체 합산 승수
		var pool_n := 0
		var pool_j := 0
		for name_ in names:
			var mem := _members(name_, t)
			if mem.size() < 3:
				print("  『%s』 그 등급 구성원 %d명뿐 —— 건너뜀" % [name_, mem.size()])
				continue
			var w := {false: 0, true: 0}
			var joints := {false: 0, true: 0}
			var fights := {false: 0, true: 0}
			var units := {false: 0, true: 0}
			var n3 := {false: 0, true: 0}
			var pers: Array = mem.map(func(k): return DB.person(k))
			for i in games:
				var deck := mem.duplicate()
				var pool: Array = DB.by_tier(t).filter(func(k): return not pers.has(DB.person(k)))
				while deck.size() < 9:
					var k: String = pool[rng.randi() % pool.size()]
					if not deck.has(k):
						deck.append(k)
				var foe := _rand_deck(t, rng)
				var sd := rng.randi() % 100000
				for on in [false, true]:
					var side_a := i % 2 == 0      # 자리 절반씩 바꾼다
					var rr := _run(deck, foe, sd, on) if side_a else _run(foe, deck, sd, on)
					var r: Dictionary = rr[0]
					var bt: RtBattle = rr[1]
					var won: bool = r.win if side_a else (not r.win and not r.draw)
					if won:
						w[on] += 1
					var st: Dictionary = bt.stats
					var camp_joint := 0
					joints[on] += int(st.get("inyeon_joint", 0))
					units[on] += int(st.get("inyeon_units", 0))
					n3[on] += int(st.get("inyeon_n3", 0))
					if int(st.get("inyeon_joint", 0)) > 0:
						fights[on] += 1
			pool_w[false] += w[false]
			pool_w[true] += w[true]
			pool_n += games
			pool_j += joints[true]
			print("  『%s』 구성원 %d명 (%s) 덱 대 무작위 %d판: 끔 승률 %.0f%% → 켬 %.0f%% (%+.0fp) · 켬 합동 판당 %.2f회 (합동 있었던 판 %d%%, 3인 %d, 합동에 쓴 장수 %d)" % [
				name_, mem.size(), ",".join(pers), games, 100.0 * w[false] / games, 100.0 * w[true] / games, 100.0 * (w[true] - w[false]) / games,
				float(joints[true]) / games, roundi(100.0 * fights[true] / games), n3[true], units[true]])
		if pool_n > 0:
			print("  ▶ 인연 덱 합산 %d판: 끔 승률 %.1f%% → 켬 %.1f%% (%+.1fp) · 켬 합동 판당 %.2f회" % [pool_n, 100.0 * pool_w[false] / pool_n, 100.0 * pool_w[true] / pool_n, 100.0 * (pool_w[true] - pool_w[false]) / pool_n, float(pool_j) / pool_n])
		# 대조 —— 무작위 대 무작위로 켬/끔이 한쪽에 치우치지 않는지 (A 승률)
		var cw := {false: 0, true: 0}
		var cj := 0
		for i in games:
			var a := _rand_deck(t, rng)
			var b := _rand_deck(t, rng)
			var sd := rng.randi() % 100000
			for on in [false, true]:
				var rr := _run(a, b, sd, on)
				if rr[0].win:
					cw[on] += 1
				if on:
					cj += int(rr[1].stats.get("inyeon_joint", 0))
		print("  대조 무작위 대 무작위 %d판: A 승 끔 %d → 켬 %d · 켬 합동 판당 %.2f회" % [games, cw[false], cw[true], float(cj) / games])


func _avail() -> void:
	for n in DB.INYEON:
		var s := []
		for t in [6, 7, 8]:
			s.append("%d:%d" % [t, _members(n, t).size()])
		print("%s (%d명) %s" % [n, DB.INYEON[n].size(), " ".join(s)])
