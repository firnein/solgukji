class_name Room
extends RefCounted
## 방 하나 —— 서버(집 PC)가 판정한다. 휴대폰은 명령만 보내고 결과를 받는다.
## 자리 8개: 사람이 앉고 빈자리는 봇. 사람마다 Run 하나(mp=true)를 들고, 단계는 모두 같은 타이머로 넘어간다.
##
## 하루(= 게임의 한 페이즈, 7일 × 3 = 21일차)는 네 단계 (11/7 사용자 기획):
##   아침 morning      징집 · 조합 · 편성 (약 1분). 모두 '준비 완료'거나 시간이 끝나면 다음
##   점심 noon         서버가 각자의 토벌을 계산해 보내고, 각자 본다. 다 봤으면(준비) 다음
##   저녁 evening_prep 상대가 정해진다 —— 멸망하지 않은 8자리를 PV 순으로 세워 위에서부터 인접한 짝 (_begin_evening).
##                     어제 만난 상대는 피하고, 사람끼리는 이틀 연속 금지 (11/7 사용자 결정 ①②).
##                     상대의 이름 · 전적만 보고(PV 는 안 보인다, 결정 ⑥) 편성을 고칠 준비 시간 (약 1분)
##   저녁 evening      서버가 대전을 계산해 보내고 본다. 모두 다 봤으면 다음 날 아침
## 7일째 저녁은 8인 토너먼트 —— 점심(토벌)은 없고 저녁 준비에 대진표를 보인 뒤 8강 · 4강 · 결승을 라운드마다 본다.
## 응답이 없는 사람(접속 끊김, 또는 단계 내내 아무 행동도 없음)은 단계가 끝날 때 그 사람의 자산으로 봇이 대신한다
## (Run.bot_prepare —— 징집 · 선택권 · 조합 · 편성). 행동은 했지만 못 끝낸 사람은 공짜 징집과 빈 편성만 채운다.
## 다시 들어오면 같은 토큰으로 자리로 돌아와 그 단계부터 이어간다 (보던 전투가 남았으면 다시 보낸다).
## 멸망은 혼자 할 때와 같다 (결정 ④). 다만 사람이 나 혼자 남으면(다른 사람 모두 멸망 · 퇴장) 계속할지 묻고, 아니면 방을 닫는다.
## 1단계 —— 전투는 양쪽 자동(고유기·군령을 AI 가). 결과 전체를 보내 휴대폰은 재생만 한다. 전투는 끝까지 봐야 '준비'가 된다 (결정 ⑦).

const MODES := {
	"fast": {"n": "빠른 — 아침 1분 · 하루 약 4분", "morning": 60.0, "noon": 75.0, "prep": 60.0, "evening": 100.0},
	"normal": {"n": "보통 — 아침 1분 30초 · 하루 약 5분", "morning": 90.0, "noon": 75.0, "prep": 90.0, "evening": 100.0},
	"test": {"n": "점검", "morning": 1.0, "noon": 0.5, "prep": 0.5, "evening": 0.5},
}
const SEATS := 8
const STAGE_N := {"lobby": "대기실", "morning": "아침 — 징집·조합", "noon": "점심 — 토벌", "evening_prep": "저녁 — 대전 준비",
	"evening": "저녁 — 대전", "over": "끝"}
const ACT_STAGES := ["morning", "evening_prep"]        # 명령(징집 · 조합 · 편성)을 받는 단계
const WATCH_STAGES := ["noon", "evening"]              # 전투를 보는 단계

var server                    # MatchServer —— send(peer, msg)
var code := ""
var mode := "fast"
var host := -1                # 방장 peer
var seats := []               # [{name, human, peer, token, run, bot, ready, dead, battles, acted, watched, foe, last_foe, last_human}]
                              #   last_foe = 어제 저녁에 만난 자리 번호(-1 이면 없음) · last_human = 그 상대가 사람이었나
var started := false
var human_n0 := 0             # 시작할 때 사람 수 —— 2명 이상이던 방에서 혼자 남으면 묻는다
var alone := ""               # "" · "ask"(혼자 남아 계속할지 묻는 중) · "go"(계속하기로 했다)
var stage := "lobby"          # lobby · morning · noon · evening_prep · evening · over
var stage_no := 0             # 단계가 바뀔 때마다 1씩 —— 늦게 온 '준비 완료'를 거른다
var stage_end := 0.0
var day := 0
var phase := 0
var pairs := []               # 저녁 대진 [[자리 a, 자리 b]] —— b 는 봇일 수 있다
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


func day_no() -> int:
	return day * 3 + phase + 1


# ───────── 대기실 ─────────

func add_human(peer: int, name_: String, token: String) -> int:
	if started or humans().size() >= SEATS:
		return -1
	seats.append({"name": _unique(name_), "human": true, "peer": peer, "token": token, "run": null,
		"bot": null, "ready": false, "dead": false, "battles": [], "acted": false, "watched": false, "foe": null,
		"last_foe": -1, "last_human": false})
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
		seats[i].peer = -1          # 자리는 남는다 —— 봇이 이어받고, 다시 들어오면 넘겨받는다
		seats[i].ready = false
		_mirror()
		push_all()
	if humans().filter(func(s): return s.peer >= 0).is_empty():
		empty_since = now()


## 스스로 나간 사람 —— 진행 중이면 자리를 봇에게 영구히 넘긴다 (토큰을 끊어 돌아오지 못한다)
func on_leave(peer: int) -> void:
	var i := seat_of(peer)
	remove_peer(peer)
	if i >= 0 and started:
		seats[i].token = ""
		_check_alone()


## 같은 토큰으로 돌아온 사람 —— 지금 단계의 상태를 주고, 보던 전투가 남았으면 다시 보낸다
func reattach(peer: int, token: String) -> bool:
	for s in seats:
		if s.human and s.token == token:
			s.peer = peer
			empty_since = -1.0
			if started:
				if stage in WATCH_STAGES and s.watched:
					s.ready = true       # 끊기기 전에 다 봤다 —— 다시 보지 않아도 된다
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
			"dead": s.dead, "pv": _pv(s), "foe": s.foe.name if s.foe != null else ""})
	var me = null
	if i >= 0 and seats[i].foe != null:
		me = seats[i].foe
	return {"code": code, "mode": mode, "mode_n": MODES[mode].n, "started": started, "stage": stage, "stage_no": stage_no,
		"stage_n": STAGE_N.get(stage, stage), "remain": maxf(0.0, stage_end - now()), "day": day, "phase": phase,
		"day_no": day_no(), "you": i, "host": i >= 0 and seats[i].human and seats[i].peer == host, "seats": ss, "foe": me,
		"alone": alone, "tour_round": tour.round if tour != null else -1}


func push_lobby() -> void:
	for i in seats.size():
		if seats[i].human and seats[i].peer >= 0:
			server.send(seats[i].peer, {"t": "room", "room": info(i)})


# ───────── 시작 · 진행 ─────────

func start() -> void:
	if started:
		return
	started = true
	human_n0 = humans().size()
	var used := seats.map(func(s): return s.name)
	var names: Array = DB.D.BOTNAME.duplicate()
	var bi := 0
	while seats.size() < SEATS:
		var b: Array = names[bi % names.size()]
		var nm: String = b[0] if not used.has(b[0]) else "%s%d" % [b[0], bi + 2]
		used.append(nm)
		seats.append(_bot_seat(nm, b[1], b[2], DB.D.STYLES[bi % DB.D.STYLES.size()], 0.0,
			snappedf(rng.randf_range(Run.SKILL_LO, Run.SKILL_HI), 0.01)))
		bi += 1
	for s in humans():
		var r := Run.new()
		r.new_game(rng.randi())
		r.mp = true
		s.run = r
	_mirror()
	_stage("morning")


func _bot_seat(nm: String, epi: String, fac: String, style: String, pv: float, skill: float) -> Dictionary:
	return {"name": nm, "human": false, "peer": -1, "token": "", "run": null, "ready": true, "dead": false, "battles": [],
		"acted": false, "watched": false, "foe": null, "last_foe": -1, "last_human": false,
		"bot": {"epi": epi, "fac": fac, "style": style, "pv": pv, "w": 0, "l": 0, "strikes": 0, "skill": skill}}


func _stage(st: String) -> void:
	stage = st
	stage_no += 1
	var m: Dictionary = MODES[mode]
	var len := 0.0
	match st:
		"morning": len = m.morning
		"noon": len = m.noon
		"evening_prep": len = m.prep
		"evening": len = m.evening
	stage_end = now() + len
	for s in seats:
		if s.human:
			s.ready = false
			s.acted = false
			s.watched = false
	push_all()


## 준비를 기다리는 사람 —— 접속해 있고 멸망하지 않은 사람. 모두 준비면 시간이 남아도 넘어간다.
## 전투를 보는 단계에서는 볼 전투가 있는 사람은 멸망했어도 기다린다 (토너먼트 탈락전 · 멸망한 토벌을 끝까지 보게)
func _live() -> Array:
	return humans().filter(func(s): return s.peer >= 0 and (not s.dead or (stage in WATCH_STAGES and not s.battles.is_empty())))


## 사람이 나 혼자 남았나 —— 다른 사람이 모두 멸망했거나 나갔다(토큰 끊김). 2명 이상이던 방에서 한 번만 묻는다 (결정 ④)
func _check_alone() -> void:
	if not started or stage == "over" or tour != null or human_n0 < 2 or alone != "":
		return
	var alive := humans().filter(func(s): return not s.dead and s.token != "")
	if alive.size() == 1:
		alone = "ask"
		push(alive[0])


## 혼자 남은 사람의 답 —— 계속하면 봇만 상대로 끝까지, 아니면 방을 닫는다
func on_alone(peer: int, go: bool) -> void:
	var i := seat_of(peer)
	if i < 0 or alone != "ask":
		return
	if go:
		alone = "go"
		push_all()
		return
	for s in humans():
		if s.run.over == null:
			s.run.over = {"win": false, "msg": "다른 사람이 모두 떠나 방을 닫았다"}
	stage = "over"
	stage_no += 1
	push_all()


func tick() -> void:
	if not started or stage == "over":
		return
	var live := _live()
	var all_ready := not live.is_empty() and live.all(func(s): return s.ready)
	if now() < stage_end and not all_ready:
		return
	match stage:
		"morning": _end_morning()
		"noon": _begin_evening()
		"evening_prep": _end_prep()
		"evening":
			if tour != null:
				_tour_next()
			else:
				_advance()


func on_ready(peer: int, on: bool, sno := -1) -> void:
	var i := seat_of(peer)
	if i < 0:
		return
	if sno >= 0 and sno != stage_no:
		return                   # 지난 단계의 '준비 완료' —— 버린다
	seats[i].ready = on
	if on and stage in WATCH_STAGES:
		seats[i].watched = true
	push_all()


func on_cmd(peer: int, m: String, a: Array) -> void:
	var i := seat_of(peer)
	if i < 0 or not (stage in ACT_STAGES) or seats[i].dead:
		return
	var r: Run = seats[i].run
	r.command(m, a)
	seats[i].acted = true
	push(seats[i])


## 응답이 없는 사람 몫을 봇이 한다 —— 끊겼거나 단계 내내 아무 행동도 없으면 전부, 행동은 했으면 빈 것만
func _fill(s: Dictionary, full_if_idle := true) -> void:
	var r: Run = s.run
	var idle: bool = s.peer < 0 or (full_if_idle and not s.acted)
	r.bot_prepare(idle)


func _end_morning() -> void:
	for s in humans():
		if not s.dead:
			_fill(s)
	if day == 6 and phase == 2:
		_tour_seed()             # 7일째 저녁 —— 토벌 없이 바로 토너먼트 준비
		_stage("evening_prep")
		return
	_quests()
	_stage("noon")
	for s in humans():
		_send_battles(s)


func _quests() -> void:
	for s in seats:
		s.battles = []
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
	_check_alone()


## 저녁 —— 상대를 정한다 (11/7 결정 ①②, 문서 3절): 멸망하지 않은 자리를 PV 순으로 세워 위에서부터 짝을 짓는다.
## 어제 만난 상대는 피하고, 어제 사람과 붙었으면 오늘은 봇 (사람끼리 이틀 연속 금지). 피할 수 없을 때만 그대로 짝.
## 사람 + 봇을 가리지 않으니 사람이 홀수여도 봇이 짝이 된다. 봇끼리의 짝은 싸우지 않는다 (기록만).
## 준비 시간 동안 상대의 이름 · 전적을 보고 편성을 고친다
func _begin_evening() -> void:
	pairs = []
	for s in seats:
		s.foe = null
		s.battles = []
	var lst := []
	for i in seats.size():
		if not (seats[i].human and seats[i].dead):
			lst.append(i)
	lst.sort_custom(func(a, b): return _pv(seats[a]) > _pv(seats[b]))
	if lst.size() % 2 == 1:
		# 홀수면 가장 약한 봇을 빼 사람은 늘 짝이 맞게 (사람뿐이면 꼴찌 사람이 쉰다)
		for k in range(lst.size() - 1, -1, -1):
			if not seats[lst[k]].human:
				lst.remove_at(k)
				break
	# 위에서부터 인접한 짝 —— 규칙(어제 상대 · 사람끼리 연속)을 모두 지키는 짝이 있으면 그것(8자리라 되짚어도 싸다),
	# 없으면 규칙을 무시하고 그냥 인접한 짝
	var found := _match(lst, 0)
	if found.is_empty():
		for x in range(0, lst.size() - 1, 2):
			found.append([lst[x], lst[x + 1]])
	pairs = found
	# 오늘 상대를 '어제 상대'로 적어 둔다 —— 내일 피한다
	for s in seats:
		s.last_foe = -1
		s.last_human = false
	for p in pairs:
		var a: Dictionary = seats[p[0]]
		var b: Dictionary = seats[p[1]]
		a.last_foe = p[1]
		a.last_human = b.human
		b.last_foe = p[0]
		b.last_human = a.human
		if a.human:
			a.foe = _foe_info(b)
		if b.human:
			b.foe = _foe_info(a)
	_stage("evening_prep")


## 순서대로 짝을 짓되 규칙을 지키는 짝만 —— 첫 미배정을 가장 가까운 상대부터 붙여 보고 안 되면 되짚는다. 못 찾으면 빈 배열
func _match(lst: Array, from: int) -> Array:
	while from < lst.size() and lst[from] < 0:
		from += 1
	if from >= lst.size():
		return []
	var a: int = lst[from]
	for y in range(from + 1, lst.size()):
		var b: int = lst[y]
		if b < 0 or not _can_pair(a, b):
			continue
		lst[from] = -1
		lst[y] = -1
		var rest := _match(lst, from + 1)
		var ok := not rest.is_empty() or lst.all(func(k): return k < 0)
		lst[from] = a
		lst[y] = b
		if ok:
			rest.push_front([a, b])
			return rest
	return []


## 오늘 이 둘이 붙어도 되나 —— 어제 만난 사이가 아니고, 사람끼리면 둘 다 어제 사람과 붙지 않았어야
func _can_pair(a: int, b: int) -> bool:
	var sa: Dictionary = seats[a]
	var sb: Dictionary = seats[b]
	if sa.last_foe == b or sb.last_foe == a:
		return false
	if sa.human and sb.human and (sa.last_human or sb.last_human):
		return false
	return true


## 상대 정보 —— 이름 · 전적만 (PV 와 편성은 보이지 않는다, 결정 ⑥)
func _foe_info(s: Dictionary) -> Dictionary:
	return {"name": s.name, "human": s.human, "online": s.human and s.peer >= 0,
		"epi": "사람" if s.human else s.bot.epi, "w": s.run.my_w if s.human else s.bot.w, "l": s.run.my_l if s.human else s.bot.l}


func _end_prep() -> void:
	for s in humans():
		if not s.dead:
			_fill(s, false)      # 저녁 준비는 아침에 편성이 끝나 있다 —— 끊긴 사람만 봇이 전부, 나머지는 빈 편성만
	if tour != null:
		_tour_round()
	else:
		_pvps()
	_stage("evening")
	for s in humans():
		_send_battles(s)


func _pvps() -> void:
	for s in seats:
		s.battles = []
	for p in pairs:
		var a: Dictionary = seats[p[0]]
		var b: Dictionary = seats[p[1]]
		if a.human and b.human:
			_pvp_humans(a, b)
		elif a.human:
			_pvp_bot(a, b)
		elif b.human:
			_pvp_bot(b, a)
		# 봇끼리는 싸우지 않는다
	pairs = []


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


## 다음 날 아침
func _advance() -> void:
	phase += 1
	if phase > 2:
		phase = 0
		day += 1
	for s in seats:
		s.foe = null
		if s.human:
			if not s.dead:
				s.run.advance()
				# 11/4 점검: Run.advance 가 3일차에 들어설 때 경고 4회면 멸망시킨다 (11/3) —— 방도 같이 처리해야 한다
				if s.run.over != null and not s.run.over.win:
					if mode == "test":
						s.run.over = null       # 점검 모드는 멸망하지 않는다
					else:
						s.dead = true
		else:
			s.bot.pv += Run.bot_pv_gain(day, phase) * s.bot.skill * rng.randf_range(0.9, 1.1)
		s.battles = []
	_mirror()
	_stage("morning")
	for s in humans():
		if s.peer >= 0:
			for t in s.run.toasts:
				server.send(s.peer, {"t": "toast", "text": t[0], "kind": t[1]})
		s.run.toasts.clear()
	_check_alone()


# ───────── 토너먼트 ─────────

## 7일째 저녁 준비 —— 시딩과 대진표만 (전투는 준비가 끝나면)
func _tour_seed() -> void:
	var ps := []
	for i in seats.size():
		var s: Dictionary = seats[i]
		if s.human and s.dead:
			continue
		ps.append({"name": s.name, "seat": i, "pv": _pv(s)})
	var k := 1
	while ps.size() < SEATS:      # 멸망한 사람 자리는 떠돌이 군세로 채운다
		var bs := _bot_seat("유랑군 %d" % k, "떠돌이 군세", "군", "균형", float(_avg_pv()), 1.0)
		seats.append(bs)
		ps.append({"name": bs.name, "seat": seats.size() - 1, "pv": _pv(bs)})
		k += 1
	ps.sort_custom(func(a, b): return a.pv > b.pv)
	var lst := []
	for i in [0, 7, 3, 4, 1, 6, 2, 5]:
		lst.append(ps[i])
	tour = {"round": 0, "list": lst, "res": [null, null, null], "next": null}
	for m in lst.size() / 2:
		var a: Dictionary = lst[m * 2]
		var b: Dictionary = lst[m * 2 + 1]
		for pair in [[a, b], [b, a]]:
			var s: Dictionary = seats[pair[0].seat]
			if s.human:
				s.foe = _foe_info(seats[pair[1].seat])
	_tour_view()


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
		var rounds := [tour.res[0] if tour.res[0] != null else _tour_pending(tour.list), tour.res[1], tour.res[2]]
		for r in 3:
			if rounds[r] == null:
				continue
			var ms := []
			for i in rounds[r].size():
				var m: Dictionary = rounds[r][i]
				var a := {"name": m.a.name, "me": m.a.name == s.name, "pv": m.a.pv}
				var b := {"name": m.b.name, "me": m.b.name == s.name, "pv": m.b.pv}
				if a.me or b.me:
					if r == tour.round:
						v.my_match = i
				ms.append({"a": a, "b": b, "w": m.get("w")})
			v.res[r] = ms
		s.run.tour = v


## 아직 치르지 않은 라운드의 대진 (승자 없음)
func _tour_pending(lst: Array) -> Array:
	var ms := []
	for m in lst.size() / 2:
		ms.append({"a": lst[m * 2], "b": lst[m * 2 + 1], "w": null})
	return ms


func _tour_next() -> void:
	if tour.round >= 2:
		_finish()
		return
	tour.list = tour.next
	tour.round += 1
	for s in seats:
		s.foe = null
	for m in tour.list.size() / 2:
		var a: Dictionary = tour.list[m * 2]
		var b: Dictionary = tour.list[m * 2 + 1]
		for pair in [[a, b], [b, a]]:
			var s: Dictionary = seats[pair[0].seat]
			if s.human:
				s.foe = _foe_info(seats[pair[1].seat])
	_tour_round()
	_stage("evening")
	for s in humans():
		_send_battles(s)


func _finish() -> void:
	for s in humans():
		if s.run.over == null:
			s.run.over = {"win": false, "msg": "토너먼트가 끝났다"}
	stage = "over"
	stage_no += 1
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
				var epi := "사람" + ("" if o.peer >= 0 else " · 접속 끊김 — 봇 대행") + (" · 멸망" if o.dead else "")
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


## 이 단계의 전투 —— 아직 안 봤으면 보게, 이미 다 봤으면(재접속) 목록만 (seen)
func _send_battles(s: Dictionary) -> void:
	if s.peer >= 0 and stage in WATCH_STAGES and not s.battles.is_empty():
		server.send(s.peer, {"t": "battles", "list": s.battles, "day": day, "phase": phase, "stage_no": stage_no,
			"stage": stage, "seen": s.watched})
