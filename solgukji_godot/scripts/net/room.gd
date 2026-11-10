class_name Room
extends RefCounted
const RoomLog := preload("res://scripts/net/room_log.gd")      # 11/10 class_name 캐시(.godot)와 무관하게 (낡은 캐시에서 "RoomLog not declared")
## 방 하나 —— 서버(집 PC)가 판정한다. 휴대폰은 명령만 보내고 결과를 받는다.
## 자리 8개: 사람이 앉고 빈자리는 봇. 사람마다 Run 하나(mp=true)를 들고, 단계는 모두 같은 타이머로 넘어간다.
##
## 하루(= 게임의 한 페이즈, 7일 × 3 = 21일차)는 네 단계 (11/7 사용자 기획):
##   아침 morning      징집 · 조합 · 편성 (약 1분). 모두 '준비 완료'거나 시간이 끝나면 다음
##   점심 noon         서버가 각자의 토벌을 계산해 보내고, 각자 본다. 다 봤으면(준비) 다음
##   저녁 evening_prep 상대가 정해진다 —— 8자리(사람 + 빈자리 봇)를 라운드로빈(원 방식)으로 돌린다 (_begin_evening · rr_round, 11/10 사용자).
##                     저녁(토너먼트 빼고 0~19번째)마다 한 라운드, 7라운드에 한 사람이 다른 일곱 자리 전원과 정확히 한 번씩 (20번 = 7 + 7 + 6).
##                     난수 없이 순번과 자리 배치(방의 첫 저녁에 한 번 섞고 고정)로만 정한다. 11/7 결정 ① ②(PV 순 인접 · 어제 상대 회피 · 사람끼리 이틀 연속 금지)는 이것으로 대체.
##                     멸망한 사람의 짝이던 자리는 쉬지 않고 떠돌이 군세(유랑군)와 붙는다. 봇끼리의 짝은 싸우지 않는다.
##                     상대의 이름 · 전적만 보고(PV 는 안 보인다, 결정 ⑥) 편성을 고칠 준비 시간 (약 1분)
##   저녁 evening      서버가 대전을 계산해 보내고 본다. 모두 다 봤으면 다음 날 아침
## 7일째 저녁은 8인 토너먼트 —— 점심(토벌)은 없고 저녁 준비에 대진표를 보인 뒤 8강 · 4강 · 결승을 라운드마다 본다.
## 응답이 없는 사람(접속 끊김, 또는 단계 내내 아무 행동도 없음)은 단계가 끝날 때 그 사람의 자산으로 봇이 대신한다
## (Run.bot_prepare —— 징집 · 선택권 · 조합 · 편성). 행동은 했지만 못 끝낸 사람은 공짜 징집과 빈 편성만 채운다.
## 다시 들어오면 같은 토큰으로 자리로 돌아와 그 단계부터 이어간다 (보던 전투가 남았으면 다시 보낸다).
## 멸망은 혼자 할 때와 같다 (결정 ④). 다만 사람이 나 혼자 남으면(다른 사람 모두 멸망 · 퇴장) 계속할지 묻고, 아니면 방을 닫는다.
## 1단계 —— 전투는 양쪽 자동(고유기를 AI 가). 결과 전체를 보내 휴대폰은 재생만 한다. 다 보거나 '결과로 건너뛰기'를 눌러야 '준비'가 된다 (결정 ⑦, 11/9 건너뛰기 허용).
## "battles" 의 각 항목 {title, res, kind, params} —— params 는 BattleView.play() 가 _p 로 짓는 재료와 같은 키(a·fa·ma·ea·b·fb·mb·eb·seed·title·foe·policy·tra·trb·tb),
## 받는 사람이 A 가 되게 뒤집은 것 —— 휴대폰이 전투장수창의 버프 수치를 혼자 할 때와 같게 잰다 (11/9 사용자).
## 소식(봇 등용 · 사람의 기인 이상 등용 · 멸망 · 퇴장 · 재접속)은 방의 모든 사람에게 뿌린다 ({"t":"news","list":[{text,kind,id,when,hot?}]} + 각자의 Run.news). 한마디(say)는 미리 적힌 글(QUICK_MSGS)만, 2초에 한 번 (11/9 사용자).
## 11/10 사용자: 기인 이상(기인 · 초월 · 불멸 · 신화)을 사람이 등용하면 다른 사람에게 '긴급' 띠 연출 —— 알림에 hot=1 (Online → GameScreen.urgent). 소식 항목마다 방 안에서 늘어나는 번호 id(안 읽은 소식 뱃지)와
## 만들어진 시점 when("3일차 아침" —— 온라인의 일차는 day_no, 단계는 아침 · 점심 · 저녁 준비 · 저녁)를 붙인다.

const MODES := {
	"fast": {"n": "빠른 — 아침 1분 · 하루 약 4분", "morning": 60.0, "noon": 75.0, "prep": 60.0, "evening": 100.0},
	"normal": {"n": "보통 — 아침 1분 30초 · 하루 약 5분", "morning": 90.0, "noon": 75.0, "prep": 90.0, "evening": 100.0},
	"test": {"n": "점검", "morning": 1.0, "noon": 0.5, "prep": 0.5, "evening": 0.5},
}
const SEATS := 8
const STAGE_N := {"lobby": "대기실", "morning": "아침 — 징집·조합", "noon": "점심 — 토벌", "evening_prep": "저녁 — 대전 준비",
	"evening": "저녁 — 대전", "over": "끝"}
const ACT_STAGES := ["morning", "evening_prep"]        # 명령(징집 · 조합 · 편성)을 받는 단계
## 한마디 —— 자유 입력 없이 이 글만 보낼 수 있다 (11/9 사용자: 대기실 · 아침 · 저녁 준비 · 전투를 보는 중 다른 사람에게 짧게)
const QUICK_MSGS := ["잘 부탁합니다", "빨리 준비해 주세요", "좋은 승부였습니다", "운이 좋았네요", "다음엔 이깁니다", "잠시만요", "ㅋㅋ", "GG"]
const SAY_GAP := 2.0          # 한 사람이 한마디를 보낼 수 있는 간격 (초)
const WATCH_STAGES := ["noon", "evening"]              # 전투를 보는 단계
const STAGE_SHORT := {"morning": "아침", "noon": "점심", "evening_prep": "저녁 준비", "evening": "저녁"}      # 소식의 시점 글 (Online.STAGE_SHORT 와 같다)

var server                    # MatchServer —— send(peer, msg)
var code := ""
var mode := "fast"
var host := -1                # 방장 peer
var seats := []               # [{name, human, peer, token, run, bot, ready, dead, battles, acted, watched, foe}]
var started := false
var human_n0 := 0             # 시작할 때 사람 수 —— 2명 이상이던 방에서 혼자 남으면 묻는다
var alone := ""               # "" · "ask"(혼자 남아 계속할지 묻는 중) · "go"(계속하기로 했다)
var stage := "lobby"          # lobby · morning · noon · evening_prep · evening · over
var stage_no := 0             # 단계가 바뀔 때마다 1씩 —— 늦게 온 '준비 완료'를 거른다
var stage_end := 0.0
var day := 0
var phase := 0
var pairs := []               # 저녁 대진 [[자리 a, 자리 b]] —— b 는 봇일 수 있다. 음수 -1 - d 는 멸망한 자리 d 를 대신하는 떠돌이 군세
var rr_order := []            # 라운드로빈 자리 배치 —— 첫 저녁에 rng 로 한 번 섞고 방이 끝날 때까지 고정 (같은 순번이면 같은 짝)
var _ghosts := {}             # 멸망한 자리 번호 -> 떠돌이 군세(자리 밖 봇) —— 저녁 대전 상대 (전적은 이어진다)
var tour = null               # {round, list:[{name, seat}], res:[[{a, b, w}]], next}
var rng := RandomNumberGenerator.new()
var empty_since := -1.0
var news_seq := 0             # 소식 항목 번호 —— _news_add 가 1씩 올려 붙인다 (휴대폰이 안 읽은 소식을 가른다)
var _news_stage := ""         # _advance 중에는 아직 stage 가 지난 단계라 시점을 '아침'으로 못박는다
var rlog: RoomLog = null      # 사람마다 플레이 기록 (11/10) —— 부수 효과일 뿐, 없어도(점검 방 · 쓰기 실패) 방은 그대로 간다


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


## 소식의 시점 글 —— "3일차 아침" (day_no · 지금 단계)
func when_text() -> String:
	var st := _news_stage if _news_stage != "" else stage
	return "%d일차 %s" % [day_no(), STAGE_SHORT.get(st, "")] if STAGE_SHORT.has(st) else ""


# ───────── 대기실 ─────────

## rec = 플레이 기록 동의 (hello 의 rec) —— 참인 사람만 RoomLog 가 파일로 남긴다. 기본은 거절(기록 안 함)
func add_human(peer: int, name_: String, token: String, rec := false) -> int:
	if started or humans().size() >= SEATS:
		return -1
	seats.append({"name": _unique(name_), "human": true, "peer": peer, "token": token, "run": null,
		"bot": null, "ready": false, "dead": false, "battles": [], "acted": false, "watched": false, "foe": null,
		"say_t": -100.0, "rec": rec})
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


func remove_peer(peer: int, why := "disconnect") -> void:
	var i := seat_of(peer)
	if i < 0:
		return
	if started and rlog != null and seats[i].run != null:
		rlog.event(i, seats[i].run, why)
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
	remove_peer(peer, "leave")
	if i >= 0 and started:
		seats[i].token = ""
		var it := {"who": seats[i].name, "text": "방을 떠났다 — 자리는 봇이 이어받는다"}
		_news_add(it)
		_announce("%s이(가) 방을 떠났다 — 자리는 봇이 이어받는다" % seats[i].name, it)
		_check_alone()


## 같은 토큰으로 돌아온 사람 —— 지금 단계의 상태를 주고, 보던 전투가 남았으면 다시 보낸다
func reattach(peer: int, token: String, rec := true) -> bool:
	for s in seats:
		if s.human and s.token == token:
			s.peer = peer
			if s.get("rec", false) and not rec:      # 돌아오며 동의를 철회했다 —— 그 자리의 기록은 여기서 멈춘다 (켜는 쪽은 없다: 이미 지난 판은 못 남긴다)
				s.rec = false
				if started and rlog != null and s.run != null:
					rlog.consent_off(_idx(s), s.run, s.name)
			empty_since = -1.0
			if started:
				if rlog != null:
					rlog.event(_idx(s), s.run, "reconnect")
				if stage in WATCH_STAGES and s.watched:
					s.ready = true       # 끊기기 전에 다 봤다 —— 다시 보지 않아도 된다
				var it := {"who": s.name, "text": "%s이(가) 돌아왔다" % s.name}
				_news_add(it, s)
				_announce("%s이(가) 돌아왔다" % s.name, it, s)
				_mirror()
				push(s)
				_send_battles(s)
			else:
				push_lobby()
			return true
	return false


func info(i: int) -> Dictionary:
	var ss := []
	for k in seats.size():
		var s: Dictionary = seats[k]
		var row := {"name": s.name, "human": s.human, "online": s.human and s.peer >= 0, "ready": s.ready,
			"dead": s.dead, "pv": _pv(s), "foe": s.foe.name if s.foe != null else ""}
		if k == i and s.run != null:
			row["hp"] = s.run.hp          # 민심은 내 자리에만 (다른 사람에게는 숨긴다)
		ss.append(row)
	var me = null
	if i >= 0 and seats[i].foe != null:
		me = seats[i].foe
	return {"code": code, "mode": mode, "mode_n": MODES[mode].n, "started": started, "stage": stage, "stage_no": stage_no,
		"stage_n": STAGE_N.get(stage, stage), "remain": maxf(0.0, stage_end - now()), "day": day, "phase": phase,
		"day_no": day_no(), "you": i, "host": i >= 0 and seats[i].human and seats[i].peer == host, "seats": ss, "foe": me,
		"alone": alone, "tour_round": tour.round if tour != null else -1, "quick": QUICK_MSGS}


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
	var gen_names := DB.gen_bot_names(rng.seed, SEATS, used)      # 11/10 봇 이름은 방마다 랜덤 (사람 이름과 겹치지 않게)
	while seats.size() < SEATS:
		var b: Array = names[bi % names.size()]
		var nm: String = gen_names[bi]
		used.append(nm)
		seats.append(_bot_seat(nm, b[1], b[2], DB.D.STYLES[bi % DB.D.STYLES.size()], 0.0,
			snappedf(rng.randf_range(Run.SKILL_LO, Run.SKILL_HI), 0.01)))
		bi += 1
	for s in humans():
		var r := Run.new()
		r.new_game(rng.randi())
		r.mp = true
		s.run = r
	if RoomLog.wanted(mode):
		rlog = RoomLog.new()
		rlog.open(self)
		if rlog.files.is_empty():      # 동의한 사람이 없으면(또는 열지 못했으면) 기록기는 없는 것으로
			rlog = null
	_mirror()
	_stage("morning")


func _bot_seat(nm: String, epi: String, fac: String, style: String, pv: float, skill: float) -> Dictionary:
	return {"name": nm, "human": false, "peer": -1, "token": "", "run": null, "ready": true, "dead": false, "battles": [],
		"acted": false, "watched": false, "foe": null,
		"bot": {"epi": epi, "fac": fac, "style": style, "pv": pv, "w": 0, "l": 0, "strikes": 0, "skill": skill, "top": 0}}      # top = 소식을 띄운 최고 등급 (Run.bot_news 와 같은 기준)


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
	if rlog != null:
		rlog.on_stage(self)
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
	_log_end()
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
	if rlog != null:
		rlog.ready(i, seats[i].run, on)
	if on and stage in WATCH_STAGES:
		seats[i].watched = true
	push_all()


func on_cmd(peer: int, m: String, a: Array) -> void:
	var i := seat_of(peer)
	if i < 0 or not (stage in ACT_STAGES) or seats[i].dead:
		return
	var r: Run = seats[i].run
	var ok = r.command(m, a)
	seats[i].acted = true
	if rlog != null:
		rlog.act(i, r, m, a, ok)
	# 11/9 사용자: 다른 사람의 소식도 와야 한다 —— 조합 · 선택권으로 등용하면 방의 다른 사람에게 소식 + 알림
	# 11/10 사용자: 기인 이상(기인 · 초월 · 불멸 · 신화)으로 정리 —— 기인은 등급 값이 전설(5)이라 is_kiin 으로 따로 센다. 본인에게는 보내지 않는다(조합 완성 연출이 있다)
	if ok and m in ["forge", "pick"] and not a.is_empty() and is_urgent_unit(str(a[0])):
		var it := {"who": seats[i].name, "unit": str(a[0])}
		_news_add(it, seats[i])
		_announce("%s가 %s을(를) 등용했습니다" % [seats[i].name, DB.C[str(a[0])].name], it, seats[i], true)
	push(seats[i])


## 긴급 소식 대상 —— 기인 이상 (기인 · 초월 6 · 불멸 7 · 신화 8)
static func is_urgent_unit(k: String) -> bool:
	return DB.C.has(k) and (DB.is_kiin(k) or int(DB.C[k].tier) >= 6)


## 응답이 없는 사람 몫을 봇이 한다 —— 끊겼거나 단계 내내 아무 행동도 없으면 전부, 행동은 했으면 빈 것만
func _fill(s: Dictionary, full_if_idle := true) -> void:
	var r: Run = s.run
	var idle: bool = s.peer < 0 or (full_if_idle and not s.acted)
	if rlog != null and idle:      # 행동은 했지만 못 끝낸 사람의 빈 편성 채우기는 적지 않는다 —— 봇이 통째로 대신한 것만
		rlog.event(_idx(s), r, "bot_fill", {"disconnected": s.peer < 0})
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
		s.battles.append({"title": q.title, "res": res, "kind": "quest", "params": _params(q, false)})
		if r.over != null and mode == "test":
			r.over = null          # 점검 모드는 멸망하지 않는다 —— 토너먼트까지 가 본다
		if rlog != null:
			var si := _idx(s)
			rlog.battle(si, r, q, res, str(q.title), false, s.peer < 0)
			rlog.reward(si, r)
		if r.over != null:
			s.dead = true
			_log_over(s)
			_fallen(s)
	var qpv := float(DB.D.QPV[day][phase])
	for s in seats:
		if not s.human and s.bot.pv < qpv * 0.95 * rng.randf_range(0.92, 1.08):
			s.bot.strikes += 1
			s.bot.pv *= 0.94
	_check_alone()


## 라운드로빈(원 방식) 한 라운드 —— order[0] 을 고정하고 나머지 n-1 자리를 한 칸씩 돌려 [[a, b] × n/2].
## rd = 0 ~ n-2: 이 n-1 라운드 동안 모든 두 자리가 정확히 한 번씩 만난다 (n = 8 이면 7라운드)
static func rr_round(order: Array, rd: int) -> Array:
	var n := order.size()
	var m := n - 1
	var out := [[order[0], order[1 + rd % m]]]
	for i in range(1, n / 2):
		out.append([order[1 + (rd + i) % m], order[1 + ((rd - i) % m + m) % m]])
	return out


## 오늘의 짝 —— rr_round 에서 멸망한 자리(dead)를 낀 짝만 손본다: 둘 다 멸망이면 짝이 없고, 한쪽만이면 산 자리는 쉬지 않고
## 떠돌이 군세와 붙는다 [산 자리, -1 - 멸망 자리]. (실제 자리와 바꿔 붙이면 한 바퀴 안에 같은 상대를 두 번 만나게 되므로 쓰지 않는다)
static func rr_plan(order: Array, rd: int, dead: Array) -> Array:
	var out := []
	for p in rr_round(order, rd):
		var da: bool = p[0] in dead
		var db: bool = p[1] in dead
		if da and db:
			continue
		elif da:
			out.append([p[1], -1 - int(p[0])])
		elif db:
			out.append([p[0], -1 - int(p[1])])
		else:
			out.append(p)
	return out


## 저녁 —— 상대를 정한다 (11/10 사용자: 라운드로빈): 저녁 순번(day*3 + phase, 토너먼트 저녁은 여기 오지 않는다)으로 라운드를 정해
## 8자리를 원 방식으로 짝짓는다 —— 7라운드에 한 사람이 나머지 일곱 자리와 한 번씩. 난수 없음(자리 배치만 방 첫 저녁에 한 번 섞는다).
## 사람 + 봇을 가리지 않고, 멸망한 사람의 짝이던 자리는 떠돌이 군세와 붙는다. 봇끼리의 짝은 싸우지 않는다 (기록만).
## 준비 시간 동안 상대의 이름 · 전적을 보고 편성을 고친다
func _begin_evening() -> void:
	pairs = []
	for s in seats:
		s.foe = null
		s.battles = []
	if rr_order.size() != seats.size():
		rr_order = []
		for i in seats.size():
			rr_order.append(i)
		for i in range(rr_order.size() - 1, 0, -1):      # Fisher-Yates (방의 rng)
			var j := rng.randi() % (i + 1)
			var t = rr_order[i]
			rr_order[i] = rr_order[j]
			rr_order[j] = t
	var dead := []
	for i in seats.size():
		if seats[i].human and seats[i].dead:
			dead.append(i)
	pairs = rr_plan(rr_order, (day * 3 + phase) % (seats.size() - 1), dead)
	for p in pairs:
		var a: Dictionary = _pair_seat(p[0])
		var b: Dictionary = _pair_seat(p[1])
		if a.human:
			a.foe = _foe_info(b)
		if b.human:
			b.foe = _foe_info(a)
	_stage("evening_prep")


## 짝에 적힌 번호의 자리 —— 음수는 멸망한 자리를 대신하는 떠돌이 군세 (세기 = 방 평균 PV, 전적은 이어진다)
func _pair_seat(i: int) -> Dictionary:
	if i >= 0:
		return seats[i]
	var d := -1 - i
	if not _ghosts.has(d):
		_ghosts[d] = _bot_seat("유랑군 %d" % (d + 1), "떠돌이 군세", "군", "균형", 0.0, 1.0)
	_ghosts[d].bot.pv = float(_avg_pv())
	return _ghosts[d]


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
		var a: Dictionary = _pair_seat(p[0])
		var b: Dictionary = _pair_seat(p[1])
		if a.human and b.human:
			_pvp_humans(a, b)
		elif a.human:
			_pvp_bot(a, b)
		elif b.human:
			_pvp_bot(b, a)
		# 봇끼리는 싸우지 않는다
	pairs = []
	if mode != "test":      # 대전에서 민심이 바닥난 사람 —— 끝 줄은 지금 적는다 (점검 방은 다음 날 아침에 over 를 지우고 계속 가므로 적지 않는다)
		for s in humans():
			if s.run.over != null:
				_log_over(s)


func _pvp_humans(x: Dictionary, y: Dictionary) -> void:
	var rx: Run = x.run
	var ry: Run = y.run
	var bt := {"kind": "pvp", "a": rx._my_side(), "b": ry._my_side(), "seed": rng.randi() % 1000000,
		"title": "대전 · %s" % y.name, "foe": y.name, "inputs": []}
	bt.pol = Run.policy_for(bt)        # 각자 고른 작전
	var res := Run.simulate(bt, [], bt.pol)
	rx.battle = bt
	rx.finish_battle(res)
	x.battles.append({"title": bt.title, "res": res, "kind": "pvp", "params": _params(bt, false)})
	var bt2: Dictionary = bt.duplicate(true)
	bt2.title = "대전 · %s" % x.name
	bt2.foe = x.name
	var flipped := Run.flip_res(res)
	flipped.title = bt2.title         # 화면 제목은 결과에 든 것을 쓴다 —— 뒤집은 쪽은 상대 이름으로
	flipped.foe = x.name
	ry.battle = bt2
	ry.finish_battle(flipped)
	y.battles.append({"title": bt2.title, "res": flipped, "kind": "pvp", "params": _params(bt, true, bt2.title, x.name)})
	if rlog != null:
		var bt3 := {"kind": "pvp", "title": bt2.title, "seed": bt.seed, "a": bt.b, "b": bt.a}      # y 기준 —— 내가 a
		rlog.battle(_idx(x), rx, bt, res, y.name, true, x.peer < 0, bool(y.get("rec", false)))
		rlog.reward(_idx(x), rx)
		rlog.battle(_idx(y), ry, bt3, flipped, x.name, true, y.peer < 0, bool(x.get("rec", false)))
		rlog.reward(_idx(y), ry)


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
	x.battles.append({"title": bt.title, "res": res, "kind": "pvp", "params": _params(bt, false)})
	if rlog != null:
		rlog.battle(_idx(x), rx, bt, res, b.name, false, x.peer < 0)
		rlog.reward(_idx(x), rx)


func _bot_side(b: Dictionary) -> Dictionary:
	return Run.bot_side(b.bot.pv * Run.BOT_PV_MUL, b.bot.style, day * 3 + phase, rng)


## 다음 날 아침
func _advance() -> void:
	if rlog != null:
		for s in humans():
			if not s.dead:
				rlog.phase_end(_idx(s), s.run, s.peer < 0)
	phase += 1
	if phase > 2:
		phase = 0
		day += 1
	_news_stage = "morning"      # 이 아래에서 생기는 소식(멸망 · 봇 등용)의 시점은 새 날의 아침
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
						_log_over(s)
						_fallen(s)
		else:
			s.bot.pv += Run.bot_pv_gain(day, phase) * s.bot.skill * rng.randf_range(0.9, 1.1)
		s.battles = []
	# 11/10 사용자: 온라인 대전의 전황 소식은 유저의 것만 —— 봇 등용 소식은 방에 뿌리지 않는다 (11/9 에 넣었던 것을 뺀다).
	# _bot_news() 는 봇의 최고 등급 기록(top)과 난수를 쓰므로 호출은 그대로 두고 결과만 버린다 (난수 순서 불변)
	_bot_news()
	_mirror()
	_stage("morning")
	for s in humans():
		if s.peer >= 0:
			for t in s.run.toasts:
				server.send(s.peer, {"t": "toast", "text": t[0], "kind": t[1]})
		s.run.toasts.clear()
	_news_stage = ""
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
		if sb.human:
			var fr := Run.flip_res(res)
			fr.title = "%s · %s" % [Run.ROUNDNM[r], a.name]
			fr.foe = a.name
			sb.battles.append({"title": fr.title, "res": fr, "kind": "tour", "params": _params(bt, true, fr.title, a.name)})
			if rlog != null:
				rlog.battle(_idx(sb), sb.run, {"kind": "tour", "title": fr.title, "seed": bt.seed, "a": bt.b, "b": bt.a}, fr, a.name, sa.human, sb.peer < 0, bool(sa.get("rec", false)))
		if sa.human:
			sa.battles.append({"title": bt.title, "res": res, "kind": "tour", "params": _params(bt, false)})
			if rlog != null:
				rlog.battle(_idx(sa), sa.run, bt, res, b.name, sb.human, sa.peer < 0, bool(sb.get("rec", false)))
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
	for s in humans():
		if s.run.over != null:
			_log_over(s)


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
	_log_end()
	push_all()


# ───────── 소식 · 한마디 ─────────

## 전투 재료 —— BattleView.play() 가 _p 로 짓는 것과 같은 키 (a·fa·ma·ea·b·fb·mb·eb·seed·title·foe·policy·tra·trb·tb), 11/9 사용자(온라인 재생에도 버프 수치).
## flipped 면 B 쪽 사람에게 주는 것 —— 양쪽 · 작전 정책을 바꾸고 화면 제목 · 상대 이름도 그 사람 기준(상대 = 원래 A 쪽 이름)
func _params(bt: Dictionary, flipped: bool, title_ := "", foe_ := "") -> Dictionary:
	var pol: Dictionary = bt.get("pol", Run.policy_for(bt))
	var a: Dictionary = bt.b if flipped else bt.a
	var b: Dictionary = bt.a if flipped else bt.b
	var title: String = title_ if title_ != "" else str(bt.title)
	var foe: String = foe_ if foe_ != "" else str(bt.foe)
	return {"a": a.cards, "fa": a.form, "ma": a.get("morale", 100), "ea": a.get("equip"),
		"b": b.cards, "fb": b.form, "mb": b.get("morale", 100), "eb": b.get("equip"),
		"seed": bt.seed, "title": title, "foe": foe,
		"policy": {"A": pol.get("B", "smart"), "B": pol.get("A", "smart")} if flipped else {"A": pol.get("A", "smart"), "B": pol.get("B", "smart")},
		"tra": float(a.get("tr_mul", 1.0)), "trb": float(b.get("tr_mul", 1.0)), "tb": b.get("trait", {})}


## 봇 등용 소식 —— Run.bot_news 와 같은 기준: 실제로 편성 가능한 최고 등급(전설 이상)이 올라갔을 때만
func _bot_news() -> Array:
	var out := []
	for s in seats:
		if s.human:
			continue
		var b: Dictionary = s.bot
		var bb := DB.gen_board(b.pv, b.style, rng)
		var top := 0
		for k in bb.cards:
			top = maxi(top, int(DB.C[k].tier))
		if top < 6 or top <= int(b.get("top", 0)):
			continue
		b.top = top
		var pl: Array = DB.POOLS[b.style].get(top, []).filter(func(k): return DB.C[k].tier < 8)
		if pl.is_empty():
			continue
		out.append({"who": s.name, "unit": pl[rng.randi() % pl.size()]})
	return out


## 멸망 —— 방의 다른 사람에게 소식
func _fallen(s: Dictionary) -> void:
	var it := {"who": s.name, "text": "세력이 멸망했다"}
	_news_add(it, s)
	_announce("%s 세력이 멸망했다" % s.name, it, s)


## 소식을 모든 사람의 Run.news 에 넣는다 (except 는 뺀다) —— 머리띠 '소식' 뱃지 · 전황 소식 시트가 그대로 쓴다
func _news_add(it: Dictionary, except = null) -> void:
	if not it.has("id"):
		news_seq += 1
		it["id"] = news_seq
	if not it.has("when"):
		var w := when_text()
		if w != "":
			it["when"] = w
	for s in humans():
		if s == except or s.run == null:
			continue
		s.run.news.push_front(it)
		s.run.news = s.run.news.slice(0, 12)


## 접속한 모든 사람에게 소식 한 줄 {"t":"news","list":[{text, kind, who?, unit?, id?, when?, hot?}]} (except 는 뺀다) —— who · unit · id · when 은 상태의 Run.news 항목과 같아 휴대폰이 겹침을 가릴 수 있다.
## hot = 긴급 띠 연출을 띄우라는 표시 (사람의 기인 이상 등용만) —— 모르는 옛 휴대폰은 그냥 알림 한 줄
func _announce(text: String, it = null, except = null, hot := false) -> void:
	var e := {"text": text, "kind": "news"}
	if it is Dictionary:
		for k in ["who", "unit", "id", "when"]:
			if it.has(k):
				e[k] = it[k]
	if hot:
		e["hot"] = 1
	for s in humans():
		if s == except or s.peer < 0:
			continue
		server.send(s.peer, {"t": "news", "list": [e]})


## 한마디 —— 미리 적힌 글(QUICK)의 번호만 받는다. 한 사람이 SAY_GAP 초에 한 번. 대기실에서도 된다
func on_say(peer: int, i: int) -> void:
	var si := seat_of(peer)
	if si < 0 or i < 0 or i >= QUICK_MSGS.size():
		return
	var s: Dictionary = seats[si]
	if now() - float(s.get("say_t", -100.0)) < SAY_GAP:
		return
	s.say_t = now()
	for o in humans():
		if o.peer >= 0:
			server.send(o.peer, {"t": "say", "who": s.name, "text": QUICK_MSGS[i]})


# ───────── 기록 (RoomLog) ─────────

func _idx(s: Dictionary) -> int:
	for i in seats.size():
		if is_same(seats[i], s):
			return i
	return -1


func _log_over(s: Dictionary) -> void:
	if rlog != null and s.run != null:
		rlog.over(_idx(s), s.run)


## 판이 끝났다(토너먼트 결승 뒤 · 혼자 남아 방을 닫음) —— 아직 끝 줄이 없는 사람에게 적고 파일을 닫는다
func _log_end() -> void:
	if rlog == null:
		return
	rlog.on_stage(self)
	for s in humans():
		_log_over(s)
	rlog.close_all()


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
