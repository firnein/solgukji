class_name Room
extends RefCounted
## 방 하나 —— 서버(집 PC)가 판정한다. 휴대폰은 명령만 보내고 결과를 받는다.
## 자리 8개: 사람이 앉고 빈자리는 봇. 사람마다 Run 하나(mp=true)를 들고, 페이즈는 모두 같은 타이머로 넘어간다.
##
## 한 페이즈: 준비(prep, 길게) —— 각자 징집·조합·편성. 다 '준비 완료'거나 시간이 끝나면
##           전투 —— 서버가 토벌(각자)과 대전(사람끼리 짝, 남으면 봇)을 계산해 결과를 보낸다
##           관전(watch) —— 각자 전투를 본다(토벌 2배속 10~20초 + 대전 50~60초). 다 '준비 완료'거나 시간이 끝나면 다음 페이즈
## 7일째 저녁은 8인 토너먼트 —— 라운드마다 관전을 거친다.
## 접속이 끊긴 사람은 준비 시간이 끝날 때 AI 가 대신 징집·조합·편성한다. 다시 들어오면 넘겨받는다.
## 1단계 —— 전투는 양쪽 자동(고유기·군령을 AI 가). 결과 전체를 보내 휴대폰은 재생만 한다.

const MODES := {
	"fast": {"n": "빠른 — 준비 100초 · 하루 약 10분", "prep": 100.0, "watch": 100.0},
	"normal": {"n": "보통 — 준비 160초 · 하루 약 13분", "prep": 160.0, "watch": 100.0},
	"test": {"n": "점검", "prep": 1.0, "watch": 0.5},
}
const SEATS := 8

var server                    # MatchServer —— send(peer, msg)
var code := ""
var mode := "fast"
var host := -1                # 방장 peer
var seats := []               # [{name, human, peer, token, run, bot, ready, dead, battles}]
var started := false
var stage := "lobby"          # lobby · prep · watch · over
var stage_end := 0.0
var day := 0
var phase := 0
var tour = null               # {round, list:[{name, seat}], res:[[{a, b, w}]], next}
var rng := RandomNumberGenerator.new()
var empty_since := -1.0


func _init(srv, room_code: String, m: String) -> void:
	server = srv
	code = room_code
	mode = m if MODES.has(m) else "fast"
	rng.randomize()


static func now() -> float:
	return Time.get_ticks_msec() / 1000.0


func humans() -> Array:
	return seats.filter(func(s): return s.human)


func seat_of(peer: int) -> int:
	for i in seats.size():
		if seats[i].human and seats[i].peer == peer:
			return i
	return -1


# ───────── 대기실 ─────────

func add_human(peer: int, name_: String, token: String) -> int:
	if started or humans().size() >= SEATS:
		return -1
	seats.append({"name": _unique(name_), "human": true, "peer": peer, "token": token, "run": null,
		"bot": null, "ready": false, "dead": false, "battles": []})
	if host < 0:
		host = peer
	push_lobby()
	return seats.size() - 1


func _unique(n: String) -> String:
	n = n.strip_edges().substr(0, 12)
	if n == "":
		n = "무명"
	var out := n
	var k := 2
	while seats.any(func(s): return s.name == out):
		out = "%s%d" % [n, k]
		k += 1
	return out


func remove_peer(peer: int) -> void:
	var i := seat_of(peer)
	if i < 0:
		return
	if not started:
		seats.remove_at(i)
		if host == peer:
			var hs := humans()
			host = hs[0].peer if not hs.is_empty() else -1
		push_lobby()
	else:
		seats[i].peer = -1          # 자리는 남는다 —— AI 가 이어받고, 다시 들어오면 넘겨받는다
		seats[i].ready = false
		_mirror()
		push_all()
	if humans().filter(func(s): return s.peer >= 0).is_empty():
		empty_since = now()


func reattach(peer: int, token: String) -> bool:
	for s in seats:
		if s.human and s.token == token:
			s.peer = peer
			empty_since = -1.0
			if started:
				_mirror()
				push(s)
				_send_battles(s)
			else:
				push_lobby()
			return true
	return false


func info(i: int) -> Dictionary:
	var ss := []
	for s in seats:
		ss.append({"name": s.name, "human": s.human, "online": s.human and s.peer >= 0, "ready": s.ready,
			"dead": s.dead, "pv": _pv(s)})
	return {"code": code, "mode": mode, "mode_n": MODES[mode].n, "started": started, "stage": stage,
		"remain": maxf(0.0, stage_end - now()), "day": day, "phase": phase, "you": i,
		"host": i >= 0 and seats[i].human and seats[i].peer == host, "seats": ss}


func push_lobby() -> void:
	for i in seats.size():
		if seats[i].human and seats[i].peer >= 0:
			server.send(seats[i].peer, {"t": "room", "room": info(i)})


# ───────── 시작 · 진행 ─────────

func start() -> void:
	if started:
		return
	started = true
	var used := seats.map(func(s): return s.name)
	var names: Array = DB.D.BOTNAME.duplicate()
	var bi := 0
	while seats.size() < SEATS:
		var b: Array = names[bi % names.size()]
		var nm: String = b[0] if not used.has(b[0]) else "%s%d" % [b[0], bi + 2]
		used.append(nm)
		seats.append({"name": nm, "human": false, "peer": -1, "token": "", "run": null, "ready": true, "dead": false, "battles": [],
			"bot": {"epi": b[1], "fac": b[2], "style": DB.D.STYLES[bi % DB.D.STYLES.size()], "pv": 0.0, "w": 0, "l": 0,
				"strikes": 0, "skill": snappedf(rng.randf_range(Run.SKILL_LO, Run.SKILL_HI), 0.01)}})
		bi += 1
	for s in humans():
		var r := Run.new()
		r.new_game(rng.randi())
		r.mp = true
		s.run = r
	_mirror()
	_stage("prep")


func _stage(st: String) -> void:
	stage = st
	var m: Dictionary = MODES[mode]
	stage_end = now() + (m.prep if st == "prep" else m.watch if st == "watch" else 0.0)
	for s in seats:
		if s.human:
			s.ready = false
	push_all()


func tick() -> void:
	if not started or stage == "over":
		return
	var live := humans().filter(func(s): return s.peer >= 0 and not (stage == "prep" and s.dead))
	var all_ready := not live.is_empty() and live.all(func(s): return s.ready)
	if now() < stage_end and not all_ready:
		return
	if stage == "prep":
		_end_prep()
	elif stage == "watch":
		if tour != null:
			_tour_next()
		else:
			_advance()


func on_ready(peer: int, on: bool) -> void:
	var i := seat_of(peer)
	if i >= 0:
		seats[i].ready = on
		push_all()


func on_cmd(peer: int, m: String, a: Array) -> void:
	var i := seat_of(peer)
	if i < 0 or stage != "prep" or seats[i].dead:
		return
	var r: Run = seats[i].run
	r.command(m, a)
	push(seats[i])


func _end_prep() -> void:
	for s in humans():
		if s.dead:
			continue
		var r: Run = s.run
		if s.peer < 0:
			# 접속이 끊긴 자리 —— AI 가 대신 징집·선택권·조합·편성
			if not r.drawn and r.draws_n() > 0:
				r.do_draw()
			r.begin_picks("phase")
			if not r.granted and not r.grant_list().is_empty():
				r.random_grant()
			r._dev_spend()
		elif r.placed() == 0:
			r.auto_deploy()
	if day == 6 and phase == 2:
		_tour_start()
	else:
		_battles()
	_stage("watch")
	for s in humans():
		_send_battles(s)


func _battles() -> void:
	for s in seats:
		s.battles = []
	# 토벌 —— 각자 혼자
	for s in humans():
		if s.dead:
			continue
		var r: Run = s.run
		var q := r.start_quest()
		q.pol = Run.policy_for(q)
		var res := Run.simulate(q, [], q.pol)
		r.finish_battle(res)
		s.battles.append({"title": q.title, "res": res, "kind": "quest"})
		if r.over != null and mode == "test":
			r.over = null          # 점검 모드는 멸망하지 않는다 —— 토너먼트까지 가 본다
		if r.over != null:
			s.dead = true
	var qpv := float(DB.D.QPV[day][phase])
	for s in seats:
		if not s.human and s.bot.pv < qpv * 0.95 * rng.randf_range(0.92, 1.08):
			s.bot.strikes += 1
			s.bot.pv *= 0.94
	# 대전 —— 사람끼리 짝, 남으면 봇
	var hs: Array = humans().filter(func(s): return not s.dead)
	_shuffle(hs)
	var bots: Array = seats.filter(func(s): return not s.human)
	while not hs.is_empty():
		var a: Dictionary = hs.pop_back()
		if not hs.is_empty():
			_pvp_humans(a, hs.pop_back())
		elif not bots.is_empty():
			_pvp_bot(a, bots[rng.randi() % bots.size()])


func _pvp_humans(x: Dictionary, y: Dictionary) -> void:
	var rx: Run = x.run
	var ry: Run = y.run
	var bt := {"kind": "pvp", "a": rx._my_side(), "b": ry._my_side(), "seed": rng.randi() % 1000000,
		"title": "대전 · %s" % y.name, "foe": y.name, "inputs": []}
	bt.pol = Run.policy_for(bt)        # 각자 고른 작전
	var res := Run.simulate(bt, [], bt.pol)
	rx.battle = bt
	rx.finish_battle(res)
	x.battles.append({"title": bt.title, "res": res, "kind": "pvp"})
	var bt2: Dictionary = bt.duplicate(true)
	bt2.title = "대전 · %s" % x.name
	bt2.foe = x.name
	var flipped := Run.flip_res(res)
	flipped.title = bt2.title         # 화면 제목은 결과에 든 것을 쓴다 —— 뒤집은 쪽은 상대 이름으로
	flipped.foe = x.name
	ry.battle = bt2
	ry.finish_battle(flipped)
	y.battles.append({"title": bt2.title, "res": flipped, "kind": "pvp"})


func _pvp_bot(x: Dictionary, b: Dictionary) -> void:
	var rx: Run = x.run
	var bt := {"kind": "pvp", "a": rx._my_side(), "b": _bot_side(b), "seed": rng.randi() % 1000000,
		"title": "대전 · %s" % b.name, "foe": b.name, "inputs": []}
	bt.pol = Run.policy_for(bt)        # 각자 고른 작전
	var res := Run.simulate(bt, [], bt.pol)
	rx.battle = bt
	rx.finish_battle(res)
	if res.win:
		b.bot.l += 1
	else:
		b.bot.w += 1
	x.battles.append({"title": bt.title, "res": res, "kind": "pvp"})


func _bot_side(b: Dictionary) -> Dictionary:
	return Run.bot_side(b.bot.pv * Run.BOT_PV_MUL, b.bot.style, day * 3 + phase, rng)


func _advance() -> void:
	phase += 1
	if phase > 2:
		phase = 0
		day += 1
	for s in seats:
		if s.human:
			if not s.dead:
				s.run.advance()
		else:
			s.bot.pv += (22 + day * 4 + (4 if phase == 2 else 0)) * s.bot.skill * rng.randf_range(0.9, 1.1)
		s.battles = []
	_mirror()
	_stage("prep")
	for s in humans():
		if s.peer >= 0:
			for t in s.run.toasts:
				server.send(s.peer, {"t": "toast", "text": t[0], "kind": t[1]})
		s.run.toasts.clear()


func _shuffle(a: Array) -> void:
	for i in range(a.size() - 1, 0, -1):
		var j := rng.randi() % (i + 1)
		var t = a[i]
		a[i] = a[j]
		a[j] = t


# ───────── 토너먼트 ─────────

func _tour_start() -> void:
	var ps := []
	for i in seats.size():
		var s: Dictionary = seats[i]
		if s.human and s.dead:
			continue
		ps.append({"name": s.name, "seat": i, "pv": _pv(s)})
	var k := 1
	while ps.size() < SEATS:      # 멸망한 사람 자리는 떠돌이 군세로 채운다
		var bs := {"name": "유랑군 %d" % k, "human": false, "peer": -1, "token": "", "run": null, "ready": true, "dead": false,
			"battles": [], "bot": {"epi": "떠돌이 군세", "fac": "군", "style": "균형", "pv": float(_avg_pv()), "w": 0, "l": 0, "strikes": 0, "skill": 1.0}}
		seats.append(bs)
		ps.append({"name": bs.name, "seat": seats.size() - 1, "pv": _pv(bs)})
		k += 1
	ps.sort_custom(func(a, b): return a.pv > b.pv)
	var lst := []
	for i in [0, 7, 3, 4, 1, 6, 2, 5]:
		lst.append(ps[i])
	tour = {"round": 0, "list": lst, "res": [null, null, null], "next": null}
	_tour_round()


func _avg_pv() -> int:
	var t := 0.0
	for s in seats:
		t += _pv(s)
	return roundi(t / maxf(1, seats.size()))


func _side_of(e: Dictionary) -> Dictionary:
	var s: Dictionary = seats[e.seat]
	return s.run._my_side() if s.human else _bot_side(s)


func _tour_round() -> void:
	for s in seats:
		s.battles = []
	var r: int = tour.round
	var L: Array = tour.list
	var ms := []
	for m in L.size() / 2:
		var a: Dictionary = L[m * 2]
		var b: Dictionary = L[m * 2 + 1]
		var bt := {"kind": "tour", "a": _side_of(a), "b": _side_of(b), "seed": rng.randi() % 1000000,
			"title": "%s · %s" % [Run.ROUNDNM[r], b.name], "foe": b.name, "inputs": []}
		bt.pol = Run.policy_for(bt)
		var res := Run.simulate(bt, [], bt.pol)
		var w: Dictionary = a if res.win else b
		var sa: Dictionary = seats[a.seat]
		var sb: Dictionary = seats[b.seat]
		if sa.human:
			sa.battles.append({"title": bt.title, "res": res, "kind": "tour"})
		if sb.human:
			var fr := Run.flip_res(res)
			fr.title = "%s · %s" % [Run.ROUNDNM[r], a.name]
			fr.foe = a.name
			sb.battles.append({"title": fr.title, "res": fr, "kind": "tour"})
		for pair in [[sa, b, w == a], [sb, a, w == b]]:
			var s: Dictionary = pair[0]
			if not s.human:
				continue
			var run: Run = s.run
			if pair[2]:
				if r == 2:
					run.over = {"win": true, "msg": "%s을(를) 꺾고 천하를 얻었다" % pair[1].name}
				else:
					run.my_w += 1
			else:
				run.over = {"win": false, "msg": "%s에서 %s에게 패했다 — 최종 %s" % [Run.ROUNDNM[r], pair[1].name, ["5~8위", "3~4위", "2위"][r]]}
				s.dead = true
		ms.append({"a": a, "b": b, "w": w.name})
	tour.res[r] = ms
	tour.next = ms.map(func(x): return x.a if x.w == x.a.name else x.b)
	_tour_view()


## 사람마다 Run.tour 를 채운다 —— 화면(_bracket)이 그대로 그린다
func _tour_view() -> void:
	for s in humans():
		var v := {"round": tour.round, "res": [null, null, null], "my_match": -1, "next": null}
		for r in 3:
			if tour.res[r] == null:
				continue
			var ms := []
			for i in tour.res[r].size():
				var m: Dictionary = tour.res[r][i]
				var a := {"name": m.a.name, "me": m.a.name == s.name, "pv": m.a.pv}
				var b := {"name": m.b.name, "me": m.b.name == s.name, "pv": m.b.pv}
				if a.me or b.me:
					if r == tour.round:
						v.my_match = i
				ms.append({"a": a, "b": b, "w": m.w})
			v.res[r] = ms
		s.run.tour = v


func _tour_next() -> void:
	if tour.round >= 2:
		_finish()
		return
	tour.list = tour.next
	tour.round += 1
	_tour_round()
	_stage("watch")
	for s in humans():
		_send_battles(s)


func _finish() -> void:
	for s in humans():
		if s.run.over == null:
			s.run.over = {"win": false, "msg": "토너먼트가 끝났다"}
	stage = "over"
	push_all()


# ───────── 보내기 ─────────

func _pv(s: Dictionary) -> int:
	if s.human:
		return s.run.my_pv() if s.run != null else 0
	return roundi(s.bot.pv)


## 사람마다 Run.bots 를 다른 자리들의 거울로 채운다 —— 순위 화면·머리띠 순위가 그대로 쓴다
func _mirror() -> void:
	for s in humans():
		var lst := []
		for o in seats:
			if o == s:
				continue
			if o.human:
				var r: Run = o.run
				var epi := "사람" + ("" if o.peer >= 0 else " · 접속 끊김 — AI 대행") + (" · 멸망" if o.dead else "")
				lst.append({"name": o.name, "epi": epi, "fac": "촉", "style": "균형", "pv": float(r.my_pv()),
					"w": r.my_w, "l": r.my_l, "strikes": r.strikes, "top": 0, "skill": 1.0})
			else:
				var b: Dictionary = o.bot
				lst.append({"name": o.name, "epi": b.epi, "fac": b.fac, "style": b.style, "pv": b.pv,
					"w": b.w, "l": b.l, "strikes": b.strikes, "top": 0, "skill": b.skill})
		s.run.bots = lst


func push(s: Dictionary) -> void:
	if s.peer < 0:
		return
	server.send(s.peer, {"t": "state", "run": s.run.to_dict(), "room": info(seats.find(s))})


func push_all() -> void:
	if started:
		_mirror()
		for s in humans():
			push(s)
	else:
		push_lobby()


func _send_battles(s: Dictionary) -> void:
	if s.peer >= 0 and stage == "watch" and not s.battles.is_empty():
		server.send(s.peer, {"t": "battles", "list": s.battles, "day": day, "phase": phase})
