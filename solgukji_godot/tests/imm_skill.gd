extends Node
## 11/26 불멸 기술 횟수 · 책략계 사거리 점검 —— "책략계 불멸이 무력계보다 일반 기술을 덜 쓰는 이유가 속도인가?" (측정 전용 · 결과는 docs/불멸_기술횟수_1126.md)
## 실제 온라인 대전 기록의 덱 · 진형 · 장비 · 군략 그대로 재현하고, 불멸(등급 7 · 기인 아님) 부대마다 아래를 적는다 (jsonl, 한 줄 = 한 부대):
##   T 살아 있던 시간 · t1 첫 행동 시각(사거리에 든 때) · tf 첫 일반 기술 시각 · acts 행동 수 · fires 일반 기술 수
##   pot 살아 있는 동안 ∫dt/행동 간격 (늘 사거리 안이었다면 했을 행동 수) · wait 준비가 찼는데 닿는 적이 없던 시간 · cf 혼란으로 날린 차례
##   blk 기술 하나가 다 찼는데 조건 · 차례 고르기로 못 쓴 차례 · col 두 기술이 같이 차서 하나가 밀린 차례
## → 기술 수 = T × (pot/T: 속도) × (acts/pot: 사거리 · 대기) × (fires/acts: 비용 ÷ 충전 구조) 로 나눈다 (tools 없이 python 으로 합산)
## 엔진은 고치지 않는다 —— RtBattle 을 물려받은 Probe 가 act · _move · _idle_skill 을 감싸 세기만 한다.
## 실행: godot --headless --path . res://tests/imm_skill.tscn -- --in=C:/.../real_battles.json --part=1 --parts=3 --out=C:/.../x.jsonl
##   --mode=table        : 불멸 카드 표만 찍는다 (병종 · 속도 · 기술 비용 · 이론 간격)
##   --spd=95            : 책략계 불멸의 속도를 이 값으로 (실험)        --spdmul=1.2 : 배율로
##   --costmul=0.6       : 책략계 불멸 일반 기술 비용 배율 (실험)       --idle=1.0   : RtBattle.caster_idle_charge
##   --range=176         : RtBattle.cast_range —— 책략계 실제 사거리 (11/26 부터 기본 250 · 병종 배율 없음. 그 전 측정은 220 × 0.8 = 176 이 기준선이라 250 / 275 / 312.5 로 넣었다)
##   --move=1.3          : 책략계 불멸 이동 속도 배율
##   --allr=364          : RtBattle.all_r ('전체' 기술이 닿는 중심 거리, 기본 320)
##   --flip=0            : 뒤집은 판은 건너뛴다
##   --all=1             : 불멸이 없는 판도 · 모든 부대를 적는다 (사거리 실험 —— 사거리는 책략계 전 등급에 걸린다). 부대 줄에 tier · kiin 이 붙는다
##     bit 원거리 부대가 적 도적 · 기병의 근접 사거리 안에 있던 시간 · mel 적 근접 아무에게나 · alln / allh / allf / all0 '전체' 기술 횟수 · 맞은 부대 합 · 그때 살아 있던 적 합 · 아무도 못 맞힌 횟수
##     판 줄: fa 먼저 친 진영 · fu 첫 (미니 아닌) 고유기 진영 · nA / nB 책략계 부대 수(전 등급)
var idx := {}


class Probe extends RtBattle:
	var pr := {}        # 부대 → 기록
	var reg := false
	var track_all := false
	var first_camp := ""
	static var move_mul := 1.0      # 실험 —— 책략계 불멸의 이동 속도 배율 (엔진 SPEED 는 그대로)

	func _speed(u: Unit) -> float:
		var v := super._speed(u)
		if move_mul != 1.0 and int(u.c.tier) == 7 and is_caster(u.c) and not DB.is_kiin(u.c.id):
			v *= move_mul
		return v

	func _init(sd: int = -1) -> void:
		super(sd)

	func _move() -> void:
		super._move()
		if not reg:
			reg = true
			for u in units:
				if track_all or (int(u.c.tier) == 7 and not DB.is_kiin(u.c.id)):
					pr[u] = {"td": -1.0, "t1": -1.0, "tf": -1.0, "acts": 0, "fires": 0, "pot": 0.0, "spd_t": 0.0, "wait": 0.0, "cf": 0, "blk": 0, "col": 0, "rate": sk_rate(u), "life": 0.0, "s0": eff(u, "spd"),
						"bit": 0.0, "mel": 0.0, "alln": 0, "allh": 0, "allf": 0, "all0": 0}
		for u in pr:
			var p: Dictionary = pr[u]
			if p.td >= 0.0:
				continue
			if not u.alive:
				p.td = _tm
				continue
			p.life += TICK
			p.pot += TICK / _interval(u)
			p.spd_t += eff(u, "spd") * TICK
			if track_all and u.ranged:      # 물림 —— 적 근접 부대의 손이 닿는 틈 안에 있던 시간 (도적 · 기병 따로)
				var m := false
				var b := false
				for o in units:
					if o.alive and o.camp != u.camp and not o.ranged and _gap(o, u) <= melee_gap + 2.0:
						m = true
						if o.c.tag == "도적" or o.c.tag == "기병":
							b = true
							break
				if m: p.mel += TICK
				if b: p.bit += TICK

	func resolve_targets(spec: String, foes: Array, me: Unit, allies: Array) -> Array:
		var out := super.resolve_targets(spec, foes, me, allies)
		if spec == "all" and me.in_skill and not _in_ult and not _target_preview and pr.has(me):
			var p: Dictionary = pr[me]
			p.alln += 1
			p.allh += out.size()
			if out.is_empty():
				p.all0 += 1
			for o in foes:
				if o.alive:
					p.allf += 1
		return out

	func _idle_skill(u: Unit, dt: float) -> void:
		if pr.has(u):
			pr[u].wait += dt
		super._idle_skill(u, dt)

	func act(u: Unit) -> void:
		if first_camp == "":
			first_camp = u.camp
		if not pr.has(u):
			super.act(u)
			return
		var p: Dictionary = pr[u]
		var before := 0
		for j in u.sk_cnt:
			before += int(u.sk_cnt[j])
		var cf := has_st(u, "confuse")
		var ready := 0
		if not cf:
			var sks: Array = u.c.get("sks", [])
			var r := sk_rate(u)
			for j in sks.size():
				var ch: float = float(u.sk_ch[j]) if j < u.sk_ch.size() else 0.5
				if ch + r >= float(sks[j].get("cost", 1.0)) - 0.0001:
					ready += 1
		super.act(u)
		p.acts += 1
		if p.t1 < 0.0:
			p.t1 = _tm
		if cf:
			p.cf += 1
		var after := 0
		for j in u.sk_cnt:
			after += int(u.sk_cnt[j])
		if after > before:
			p.fires += 1
			if p.tf < 0.0:
				p.tf = _tm
			if ready >= 2:
				p.col += 1
		elif ready >= 1:
			p.blk += 1


func _ready() -> void:
	PlayLog.enabled = false
	var a := {}
	for s in OS.get_cmdline_user_args():
		var kv := s.trim_prefix("--").split("=", true, 1)
		a[kv[0]] = kv[1] if kv.size() > 1 else "1"
	var imm: Array = DB.by_tier(7).filter(func(k): return not DB.is_foe(k) and not DB.is_kiin(k) and DB.C[k].kind != "retired")
	imm.sort()
	# 실험 —— 책략계 불멸만, 이 프로세스의 메모리 안에서만 바꾼다 (데이터 파일은 그대로)
	for k in imm:
		var c: Dictionary = DB.C[k]
		if not Battle.is_caster(c):
			continue
		if a.has("spd"):
			c.spd = float(a.spd)
		if a.has("spdmul"):
			c.spd = roundf(float(c.spd) * float(a.spdmul))
		if a.has("costmul"):
			for s in c.sks:
				s.cost = snappedf(float(s.get("cost", 1.0)) * float(a.costmul), 0.01)
	if a.has("idle"):
		RtBattle.caster_idle_charge = float(a.idle)
	if a.has("range"):
		RtBattle.cast_range = float(a.range)
	if a.has("allr"):
		RtBattle.all_r = float(a.allr)
	if a.has("move"):
		Probe.move_mul = float(a.move)
	if str(a.get("mode", "run")) == "table":
		for k in imm:
			var c: Dictionary = DB.C[k]
			var sks := []
			for s in c.sks:
				sks.append({"n": s.n, "tgt": s.eff.tgt, "kind": s.eff.kind, "cost": s.get("cost", 1.0), "cond": s.get("cond", "always"), "mult": s.eff.get("mult", 0.0)})
			print("IMM_TABLE " + JSON.stringify({"id": k, "name": c.name, "tag": c.tag, "caster": Battle.is_caster(c), "spd": c.spd, "atk": c.atk, "def": c.def, "tr": c.tr,
				"rate": float(DB.D.RATE.get("7", 0.0)), "move": RtBattle.SPEED.get(c.tag, 55.0), "sks": sks}))
		print("IMM_TABLE_END cast_range=%s bow_range=%s melee_gap=%s idle=%s melee_bank=%s" % [RtBattle.cast_range, RtBattle.bow_range, RtBattle.melee_gap, RtBattle.caster_idle_charge, RtBattle.melee_bank])
		get_tree().quit(0)
		return
	for k in DB.C:
		if DB.is_foe(k):
			continue
		var c: Dictionary = DB.C[k]
		var key := JSON.stringify([c.name, int(c.tier), c.tag])
		if not idx.has(key) or DB.C[idx[key]].kind == "retired":
			idx[key] = k
	var part := int(a.get("part", "1"))
	var parts := int(a.get("parts", "1"))
	var all := str(a.get("all", "0")) != "0"
	var flips: Array = [false] if str(a.get("flip", "1")) == "0" else [false, true]
	var rows: Array = JSON.parse_string(FileAccess.get_file_as_string(str(a.get("in", ""))))
	var sw = load("res://tests/real_myth_swap.gd").new()
	sw.idx = idx
	var f := FileAccess.open(str(a.get("out", "user://imm_skill_%d.jsonl" % part)), FileAccess.WRITE)
	var k := 0
	var nb := 0
	for bi in rows.size():
		var b: Dictionary = rows[bi]
		var has7 := all
		for sn in ["me", "foe"]:
			for c in b[sn].cards:
				if int(c[1]) == 7:
					has7 = true
		if not has7:
			continue
		k += 1
		if k % parts != part - 1:
			continue
		var me: Dictionary = sw._side(b.me)
		var foe: Dictionary = sw._side(b.foe)
		if me.is_empty() or foe.is_empty():
			continue
		var plan := {}
		if not (b.me_plan as Array).is_empty() or not (b.foe_plan as Array).is_empty():
			plan = {"A": {"p": b.me_plan, "own": b.me_own, "perm": []}, "B": {"p": b.foe_plan, "own": [], "perm": []}}
		for flip in flips:
			var bt := Probe.new(int(b.seed))
			bt.track_all = all
			var r: Dictionary = sw._run_bt(bt, foe if flip else me, me if flip else foe, plan, flip)
			var aw: float = 0.5 if bool(r.draw) else (1.0 if bool(r.win) else 0.0)
			var tm: float = bt._tm
			var nc := {"A": 0, "B": 0}
			var np := {"A": 0, "B": 0}
			var na := {"A": 0, "B": 0}
			var fu := ""
			for e in r.ev:
				if e.get("fx") == "ult_warn" and not e.get("mini", false):
					fu = str(e.a).substr(0, 1)
					break
			var taken := {}
			for ru in r.roster:
				taken[str(ru.camp) + str(int(ru.slot))] = float(ru.taken)
			var dmg := {}
			for ru in r.roster:
				dmg[str(ru.camp) + str(int(ru.slot))] = float(ru.dmg) - float(ru.over)
			for u in bt.pr:
				var p: Dictionary = bt.pr[u]
				var cst: bool = Battle.is_caster(u.c)
				var imm7: bool = int(u.c.tier) == 7 and not DB.is_kiin(u.c.id)
				if cst: na[u.camp] += 1
				if imm7:
					if cst: nc[u.camp] += 1
					else: np[u.camp] += 1
				var cnt := []
				for j in (u.c.sks as Array).size():
					cnt.append(int(u.sk_cnt.get(j, 0)))
				f.store_line(JSON.stringify({"k": "u", "bi": bi, "day": b.day, "flip": flip, "id": u.c.id, "name": u.c.name, "tag": u.c.tag, "caster": cst, "line": u.line, "camp": u.camp,
					"w": aw if u.camp == "A" else 1.0 - aw, "T": snappedf(p.life, 0.1), "dead": p.td >= 0.0, "t1": snappedf(p.t1, 0.1), "tf": snappedf(p.tf, 0.1),
					"acts": p.acts, "fires": p.fires, "pot": snappedf(p.pot, 0.01), "spd_t": snappedf(p.spd_t, 0.1), "spd0": u.c.spd, "s0": snappedf(p.s0, 0.1), "wait": snappedf(p.wait, 0.1),
					"cf": p.cf, "cf_sec": snappedf(u.cf_sec, 0.1), "blk": p.blk, "col": p.col, "rate": snappedf(p.rate, 0.001), "ult": u.ult_n, "cnt": cnt,
					"dmg": dmg.get(u.key, 0.0), "tm": snappedf(tm, 0.1), "tier": int(u.c.tier), "kiin": DB.is_kiin(u.c.id), "max": u.max, "taken": taken.get(u.key, 0.0),
					"bit": snappedf(p.bit, 0.1), "mel": snappedf(p.mel, 0.1), "alln": p.alln, "allh": p.allh, "allf": p.allf, "all0": p.all0}))
			f.store_line(JSON.stringify({"k": "b", "bi": bi, "day": b.day, "flip": flip, "aw": aw, "tm": snappedf(tm, 0.1), "cA": nc.A, "cB": nc.B, "pA": np.A, "pB": np.B, "nA": na.A, "nB": na.B, "fa": bt.first_camp, "fu": fu}))
			bt.pr.clear()
			bt.units.clear()
			nb += 1
	f.close()
	print("IMM_SKILL done part=%d/%d 판 %d" % [part, parts, nb])
	get_tree().quit(0)
