extends Node
## 11/12 봇 군세 점검 (작업현황 94) —— 실행: godot --headless --path . res://tests/bot_army.tscn [-- --games=6]
## ① 지속 —— 한 봇의 군세는 전투마다 새로 뽑지 않는다: 같은 페이즈의 연속 전투는 9장 모두 같고, 페이즈가 넘어갈 때 PV 가 오른 만큼 필요한 칸만 바뀐다 (이웃 페이즈 겹침 ≥ 6장)
## ② 유일 —— 군세 · gen_board 덱에 같은 인물(person)이 둘 없다 (전설 이하 낮은 등급 3 미만 기본패는 인물이 아니다), 카드 id 도 겹치지 않는다
## ③ 결정성 —— 같은 시드 두 번이면 군세 · 편성 · 장비가 완전히 같다 (혼자 하기 Run · 온라인 Room 의 봇 자리 · 저장 불러오기 뒤)
## ④ 곡선 —— 군세의 등급 분포가 같은 PV 에서 예전 gen_board 와 같은 구조(board_tiers)다 —— 봇 전력 곡선(BOT_LATE · QUEST_TR · TOUR_BOT_MUL)은 건드리지 않았다
## ⑤ 온라인 —— Room 의 봇 자리 · 유랑군(떠돌이 군세)도 같은 군세가 이어진다, 방 정보 미러에 군세가 실린다

var fails := []
var _stat := {"pairs": 0, "min_shared": 9, "sum_shared": 0, "jump_pairs": 0}


func _fail(s: String) -> void:
	if fails.size() < 30:
		fails.append(s)


class FakeSrv:
	var out := []
	func send(peer: int, msg: Dictionary) -> void:
		out.append([peer, msg])


func _ready() -> void:
	var games := 6
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--games="):
			games = int(a.trim_prefix("--games="))
	_unique_scan()
	_solo_persistence(games)
	_determinism()
	_save_load()
	_room_bots()
	_curve()
	_rosters_info()
	print("겹침(이웃 페이즈 · 같은 봇) 쌍 %d · 평균 %.2f장 · 최소 %d장 · PV 급등으로 6장 미만이 허락된 쌍 %d" % [
		_stat.pairs, float(_stat.sum_shared) / maxf(1.0, _stat.pairs), _stat.min_shared, _stat.jump_pairs])
	var row := []
	for ph in range(1, 21):
		row.append("%d:%d/%d" % [ph, int(_stat.get("lo_%d" % ph, 0)), int(_stat.get("n_%d" % ph, 0))])
	print("페이즈별 겹침 6장 미만(쌍 수/전체) ", " ".join(row))
	print("FAIL: ", fails if not fails.is_empty() else "없음")
	get_tree().quit(1 if not fails.is_empty() else 0)


## 한 덱의 유일성 점검 —— 틀리면 사유 문자열
func _dup_reason(cards: Array) -> String:
	var ids := {}
	var ps := {}
	for k in cards:
		var t: int = int(DB.C[k].tier)
		if t >= 3:
			if ids.has(k):
				return "같은 카드 %s 가 둘" % k
			var p := DB.person(k)
			if ps.has(p):
				return "같은 인물 %s 가 둘 (%s · %s)" % [p, ps[p], k]
			ps[p] = k
		ids[k] = true
	return ""


## ② gen_board · army_fit 로 PV 0 ~ 3000, 성향 셋, 씨앗 여럿 —— 같은 인물 · 카드 없음
func _unique_scan() -> void:
	var n := 0
	var low_dups := 0
	for style in ["물리", "지략", "균형"]:
		for sd in 40:
			var rg := RandomNumberGenerator.new()
			rg.seed = 1000 + sd
			var army := []
			for pv in range(0, 3000, 25):
				var eb := DB.gen_board(float(pv), style, rg)
				var why := _dup_reason(eb.cards)
				if why != "":
					_fail("gen_board pv %d %s: %s" % [pv, style, why])
				if eb.cards.size() != 9:
					_fail("gen_board 장수 %d" % eb.cards.size())
				army = DB.army_fit(army, float(pv), style, DB.mix_seed(sd, 3, 5))
				var why2 := _dup_reason(army)
				if why2 != "":
					_fail("army_fit pv %d %s: %s" % [pv, style, why2])
				var low := {}
				for k in army:
					if int(DB.C[k].tier) < 3:
						low[k] = int(low.get(k, 0)) + 1
				for k in low:
					if low[k] > 1 and low.size() < DB.BASE.size():
						low_dups += 1
						if low_dups <= 2:
							print("  겹침 예 pv %d %s: %s · 기본패 %d종" % [pv, style, str(army), DB.BASE.size()])
				n += 2
	print("유일성 점검 %d덱 · 기본패끼리 겹침(가능한데도) %d" % [n, low_dups])
	if low_dups > 0:
		_fail("기본패 id 가 겹칠 필요가 없는데 겹쳤다 %d번" % low_dups)


## 한 봇의 군세를 페이즈마다 따라가며 이웃 페이즈 겹침을 센다
func _track(b: Dictionary, prev: Array, now: Array, who: String, tag: String) -> void:
	if prev.is_empty():
		return
	var shared := 0
	var pc := prev.duplicate()
	for k in now:
		if pc.has(k):
			shared += 1
			pc.erase(k)
	_stat.pairs += 1
	var ph := int(tag.get_slice(" ", 1))
	_stat["lo_%d" % ph] = int(_stat.get("lo_%d" % ph, 0)) + (1 if shared < 6 else 0)
	_stat["n_%d" % ph] = int(_stat.get("n_%d" % ph, 0)) + 1
	_stat.sum_shared += shared
	_stat.min_shared = mini(int(_stat.min_shared), shared)
	if shared < 6:
		_stat.jump_pairs += 1
		# 허락 조건: 이 PV 에서 바뀌어야 하는 칸 수가 정말 4 이상이었다
		var need := _need(prev, float(b.pv))
		if 9 - need < 6 and need < 4:
			_fail("%s %s: 겹침 %d장인데 필요한 교체는 %d칸" % [who, tag, shared, need])
		elif 9 - need >= 6:
			_fail("%s %s: 겹침 %d장 < 6 (필요한 교체 %d칸)" % [who, tag, shared, need])


## 이 군세를 PV 에 맞추려면 바뀌어야 하는 칸 수 (등급 배분 비교)
func _need(army: Array, pv: float) -> int:
	var want := DB.board_tiers(pv)
	want.sort()
	want.reverse()
	var have := army.map(func(k): return int(DB.C[k].tier))
	have.sort()
	have.reverse()
	var c := 0
	for j in 9:
		if int(have[j]) != int(want[j]):
			c += 1
	return c


## ① 혼자 하기 Run —— 7일 동안 페이즈마다 봇마다 대전 편성을 두세 번 뽑아 군세가 이어지는지
func _solo_persistence(games: int) -> void:
	var step := 0
	for g in games:
		var r := Run.new()
		r.new_game(300 + g)
		var prev := {}
		for p in 21:
			r.day = p / 3
			r.phase = p % 3
			for b in r.bots:
				var s1 := Run.bot_side_of(b, int(r.rng.seed), p)
				var s2 := Run.bot_side_of(b, int(r.rng.seed), p)
				var s3 := Run.bot_side_of(b, int(r.rng.seed), p, 1.0)
				if str(s1.cards) != str(s2.cards) or str(s1.cards) != str(s3.cards) or str(s1.equip) != str(s2.equip):
					_fail("봇 %s 같은 페이즈 %d 에 군세 · 장비가 달라졌다" % [b.name, p])
				var why := _dup_reason(s1.cards.filter(func(k): return k != null))
				if why != "":
					_fail("봇 %s 페이즈 %d: %s" % [b.name, p, why])
				var army: Array = (b.army as Array).duplicate()
				if prev.has(b.name):
					_track(b, prev[b.name], army, "솔로 %d %s" % [g, b.name], "페이즈 %d" % p)
				prev[b.name] = army
				# 토너먼트 · 신화 배율은 이번 전투만 —— 저장된 군세가 바뀌지 않는다
				var before := str(b.army)
				var _t := Run.bot_side_of(b, int(r.rng.seed), p, 0.75)
				var _m := Run.bot_side_of(b, int(r.rng.seed), p, 1.3)
				if str(b.army) != before:
					_fail("봇 %s 배율 전투가 저장된 군세를 바꿨다" % b.name)
			# PV 가 한 페이즈 자라고 토벌에 실패하면 ×0.94 (실제 흐름) —— Run.advance 가 하는 일과 같다
			for b in r.bots:
				b.pv += Run.bot_pv_gain(r.day, r.phase) * b.skill * 1.0
				if step % 5 == 0:
					b.pv *= 0.94
				step += 1
	print("혼자 하기 지속 점검 %d판" % games)


## ③ 결정성 —— 같은 시드면 같은 군세 · 편성 · 장비 (Run 두 번)
func _determinism() -> void:
	var a := _solo_fingerprint(777)
	var b := _solo_fingerprint(777)
	var c := _solo_fingerprint(778)
	if a != b:
		_fail("같은 시드 두 번의 봇 군세가 다르다")
	if a == c:
		_fail("다른 시드인데 봇 군세가 같다 (시드가 안 먹는다)")
	print("결정성 점검 —— 시드 777 두 번 같음 · 778 다름")


func _solo_fingerprint(seed_: int) -> String:
	var r := Run.new()
	r.new_game(seed_)
	var out := []
	for p in 21:
		r.day = p / 3
		r.phase = p % 3
		for b in r.bots:
			var s := Run.bot_side_of(b, int(r.rng.seed), p)
			out.append("%s|%s|%s|%s" % [b.name, str(s.cards), str(s.equip), s.tac])
			b.pv += Run.bot_pv_gain(r.day, r.phase) * b.skill
	return "\n".join(out)


## 저장 → JSON → 불러오기 뒤에도 군세가 이어진다 (aseed 가 정수로 돌아온다)
func _save_load() -> void:
	var r := Run.new()
	r.new_game(55)
	for p in 8:
		r.day = p / 3
		r.phase = p % 3
		for b in r.bots:
			Run.bot_side_of(b, int(r.rng.seed), p)
			b.pv += 40.0
	var txt := JSON.stringify(r.to_dict(), "", false, true)
	var r2 := Run.new()
	r2.from_dict(JSON.parse_string(txt))
	for i in r.bots.size():
		var b: Dictionary = r.bots[i]
		var b2: Dictionary = r2.bots[i]
		if str(b.army) != str(b2.army):
			_fail("저장 뒤 군세가 달라졌다 %s" % b.name)
		if int(b.aseed) != int(b2.aseed) or typeof(b2.aseed) != TYPE_INT:
			_fail("저장 뒤 aseed 가 달라졌다 %s (%s → %s)" % [b.name, str(b.aseed), str(b2.aseed)])
		var s1 := Run.bot_side_of(b, int(r.rng.seed), 8)
		var s2 := Run.bot_side_of(b2, int(r2.rng.seed), 8)
		if str(s1.cards) != str(s2.cards) or str(s1.equip) != str(s2.equip):
			_fail("저장 뒤 다음 편성이 달라졌다 %s" % b.name)
	print("저장 불러오기 점검 끝")


func _mk_room(seed_: int) -> Room:
	var srv := FakeSrv.new()
	var r := Room.new(srv, "BA", "test", 8)
	r.rng.seed = seed_
	r.add_human(1, "사람", "tk0")
	r.start()
	return r


## ⑤ 온라인 —— 봇 자리 · 유랑군 모두 같은 군세가 이어진다, 같은 시드는 같다, 방 정보 미러에 군세가 실린다
func _room_bots() -> void:
	var ra := _mk_room(4242)
	var rb := _mk_room(4242)
	var prev := {}
	var shots := {}
	for ev in 21:
		ra.day = ev / 3
		ra.phase = ev % 3
		rb.day = ra.day
		rb.phase = ra.phase
		for i in ra.seats.size():
			var s: Dictionary = ra.seats[i]
			if s.human:
				continue
			var sa: Dictionary = ra._bot_side(s)
			var sa2: Dictionary = ra._bot_side(s)
			var sb: Dictionary = rb._bot_side(rb.seats[i])
			if str(sa.cards) != str(sa2.cards) or str(sa.equip) != str(sa2.equip):
				_fail("방 봇 %s 같은 페이즈에 편성이 달라졌다" % s.name)
			if str(sa.cards) != str(sb.cards) or str(sa.equip) != str(sb.equip):
				_fail("같은 시드의 두 방이 봇 %s 편성이 다르다 (페이즈 %d)" % [s.name, ev])
			var why := _dup_reason(sa.cards.filter(func(k): return k != null))
			if why != "":
				_fail("방 봇 %s 페이즈 %d: %s" % [s.name, ev, why])
			if prev.has(i):
				_track(s.bot, prev[i], (s.bot.army as Array).duplicate(), "방 %s" % s.name, "페이즈 %d" % ev)
			prev[i] = (s.bot.army as Array).duplicate()
			shots[i] = sa
			# 실제 진행처럼 PV 가 자란다 (Room._advance 와 같은 식)
			s.bot.pv += Run.bot_pv_gain(ra.day, ra.phase) * s.bot.skill
			rb.seats[i].bot.pv = s.bot.pv
	# 방 정보 미러 —— 사람의 Run.bots 에 군세가 실린다
	ra._mirror()
	var mir: Array = ra.seats[0].run.bots
	if mir.is_empty() or mir.any(func(b): return (b.get("army", []) as Array).size() != 9 and not str(b.epi).begins_with("사람")):
		_fail("방 미러 bots 에 군세가 안 실렸다")
	# 유랑군(멸망한 자리를 대신하는 떠돌이 군세) —— 같은 자리는 같은 봇 · 같은 군세가 이어진다
	ra.seats[0].dead = true
	var g := ra._pair_seat(-1)
	var g2 := ra._pair_seat(-1)
	if g != g2:
		_fail("유랑군이 매번 새로 만들어진다")
	var c1: Array = ra._bot_side(g).cards
	g.bot.pv = float(ra._avg_pv()) * 1.08
	var c2: Array = ra._bot_side(g).cards
	var sh := 0
	var pc: Array = c1.duplicate()
	for k in c2:
		if k != null and pc.has(k):
			sh += 1
			pc.erase(k)
	if sh < 6:
		_fail("유랑군 군세가 PV ×1.08 에 %d장만 이어졌다" % sh)
	print("온라인 봇 점검 끝 (유랑군 겹침 %d장)" % sh)


## ④ 곡선 —— 같은 PV 에서 군세(첫 생성)의 등급 분포가 board_tiers 와 같다 (전력 곡선 불변)
func _curve() -> void:
	var bad := 0
	for sd in 20:
		for pv in range(0, 2500, 50):
			var army := DB.army_fit([], float(pv), "균형", sd + 1)
			var have := army.map(func(k): return int(DB.C[k].tier))
			have.sort()
			var want := DB.board_tiers(float(pv))
			want.sort()
			if have != want:
				bad += 1
	if bad > 0:
		_fail("처음 만든 군세의 등급 분포가 board_tiers 와 다르다 %d번" % bad)
	# 자란 군세도 같은 분포 (한 칸씩 올려 와도 등급 배분은 board_tiers)
	var army2 := []
	var bad2 := 0
	for pv in range(0, 2500, 10):
		army2 = DB.army_fit(army2, float(pv), "물리", 99)
		var h2 := army2.map(func(k): return int(DB.C[k].tier))
		h2.sort()
		var w2 := DB.board_tiers(float(pv))
		w2.sort()
		if h2 != w2:
			bad2 += 1
	if bad2 > 0:
		_fail("자란 군세의 등급 분포가 board_tiers 와 다르다 %d번 (PV 2500 까지)" % bad2)
	print("곡선 점검 —— 분포 불일치 %d · %d" % [bad, bad2])


## 참고 —— 토벌 고정 편성(data/cards_ext.json quest_rosters)은 손으로 쓴 적 덱이라 겹침이 있을 수 있다 (고치지 않는다, 알림만)
func _rosters_info() -> void:
	var dup := 0
	for st in DB.QUEST_ROSTERS:
		for q in (st if st is Array else [st]):
			if q is Dictionary and q.has("cards") and _dup_reason(q.cards) != "":
				dup += 1
	print("토벌 고정 편성 중 같은 인물 · 카드 겹침 %d 편성 (참고)" % dup)
