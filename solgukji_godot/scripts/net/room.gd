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
##                     멸망한 사람의 짝이던 자리는 쉬지 않고 — 다른 산 사람이 있으면 그 사람의 '그림자'(저녁 편성 복사본, 11/11 그림자 대전), 없으면 떠돌이 군세(유랑군)와 붙는다. 봇끼리의 짝은 싸우지 않는다.
##                     상대의 이름 · 전적만 보고(PV 는 안 보인다, 결정 ⑥) 편성을 고칠 준비 시간 (약 1분)
##   저녁 evening      서버가 대전을 계산해 보내고 본다. 모두 다 봤으면 다음 날 아침
## 11/11 사용자(온라인 방): 점심(토벌)은 1~3일차(day 0~2)에만 —— 4일차(day 3)부터는 아침(준비) → 저녁 준비(대전 준비) → 저녁(대전) 세 단계 (Room.has_noon).
## 없어진 토벌 보상은 그 일차의 대전이 대신 준다 (Run.pvp_quest_equiv). 대전 패배 민심 피해는 온라인에서 토벌과 같게(Run.HP_PVP_MUL_ONLINE).
## 11/11 사용자: 점심 · 저녁(전투를 보는 단계)은 내 전투를 다 보면(또는 볼 전투가 없으면 · 끊김/봇 대행이면) 서버가 기다리지 않고 넘어간다 —— 그동안 징집 · 조합 · 편성은 계속 할 수 있다 (can_cmd, 토너먼트 저녁만 잠긴다).
## 11/12 사용자(페이즈 개편): 모든 보상(토벌 · 대전)은 1페이즈(아침)에 준다 (Run.held → Run.advance). 단계마다 할 수 있는 일 (cmd_block):
##   1 아침(1분 → 4일차~ 30초)  징집 · 조합 · 편성 모두  (11/12 사용자: 토벌이 사라지는 4일차~ 는 준비 · 대전 준비가 절반 —— 시작 때 「토벌 종료」 알림)
##   2 점심(토벌)           토벌을 다 본 뒤 기다리는 동안 징집 · 조합만 (편성 불가)
##   3 저녁 준비(30초 → 4일차~ 15초)  편성만 (징집 · 조합 불가)
##   4 저녁(대전)           대전을 다 본 뒤 기다리는 동안 징집 · 조합만 (편성 불가) —— 먼저 끝난 사람의 빈 시간을 쓰게. 토너먼트 저녁은 모두 잠김
## 안 되는 명령은 거부하고 그 사람에게 이유를 보낸다 ({"t":"error"}). 방 정보에 act_draw · act_form · why_draw · why_form
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
	"fast": {"n": "빠른 — 준비 1분 · 대전 준비 30초", "morning": 60.0, "noon": 75.0, "prep": 30.0, "evening": 100.0, "morning2": 30.0, "prep2": 15.0},      # 11/12 사용자: 1페이즈 1분 · 유저전 준비 30초 / 같은 날 사용자: 토벌이 사라지는 4일차~ 는 절반 (morning2 · prep2)
	"normal": {"n": "보통 — 준비 1분 · 대전 준비 30초", "morning": 60.0, "noon": 75.0, "prep": 30.0, "evening": 100.0, "morning2": 30.0, "prep2": 15.0},
	"test": {"n": "점검", "morning": 1.0, "noon": 0.5, "prep": 0.5, "evening": 0.5, "morning2": 1.0, "prep2": 0.5},      # 점검 모드는 빠르게 그대로 (4일차~ 도 같은 값)
}
const SEATS := 8              # 기본 자리 수 —— 방장이 만들 때 고르지 않으면 (옛 클라이언트) 8
const SEAT_OPTIONS := [4, 6, 8]      # 방장이 고를 수 있는 총 인원(짝수) —— 자리 수 = 총 인원, 빈자리만 봇 (11/11 사용자)
const SEED_ORDER := [0, 7, 3, 4, 1, 6, 2, 5]      # 토너먼트 8강 시드 배치 (1-8, 4-5, 2-7, 3-6) —— 인원이 8 미만이면 8 이상 시드 자리는 부전승
const STAGE_N := {"lobby": "대기실", "morning": "준비 — 징집·조합·편성", "noon": "토벌", "evening_prep": "대전 준비",
	"evening": "대전", "over": "끝"}
const ACT_STAGES := ["morning", "evening_prep"]        # 명령(징집 · 조합 · 편성)을 받는 준비 단계 (시간제 · 준비 완료 버튼) —— 전투를 보는 단계에서도 can_cmd 가 허락한다
## 한마디 —— 자유 입력 없이 이 글만 보낼 수 있다 (11/9 사용자: 대기실 · 아침 · 저녁 준비 · 전투를 보는 중 다른 사람에게 짧게)
const QUICK_MSGS := ["잘 부탁합니다", "빨리 준비해 주세요", "다음엔 이깁니다", "잠시만요", "ㅋㅋ", "GG",
	"니오넨비욘", "줴줴이야~", "7층이나 가죠", "아니 추가", "커피 내기 ㄱ", "봉진이형 커피 고마워", "지훈아 커피 고마워", "한솔아 커피 고마워"]      # 11/12 사용자 —— 좋은 승부였습니다 · 운이 좋았네요 · 커피 고마워. 빼고 새 글 (클라이언트는 방 정보의 quick 목록을 그대로 쓰므로 번호가 바뀌어도 된다 —— 서버 재시작 필요)
## 11/12 사용자: 기인 이상 장수가 유저전(대전)에서 이기며 연속으로 수훈(MVP)하면 방 전체에 소식 —— 횟수별 문구(4 이상은 4), 3연속부터 긴급 띠
const MVP_STREAK_TEXT := {2: "기세가 오르고 있습니다", 3: "미쳐 날뛰고 있습니다", 4: "아무도 막지 못하고 있습니다"}
const SHADOW_EPI := "그림자"      # 그림자 대전 상대의 소속 글 (_foe_info.epi) —— 이름은 "<자리 이름>의 그림자"
const SAY_GAP := 2.0         # 한 사람이 한마디를 보낼 수 있는 간격 (초) —— 글과 이모티콘이 함께 쓴다
const EMOTE_N := 8            # 한마디 이모티콘 개수 (11/10) —— 그림은 클라이언트가 가진다(Icons.EMOTES), 서버는 번호 범위만 검증 (자유 입력 없음)
const WATCH_STAGES := ["noon", "evening"]              # 전투를 보는 단계
const FORM_CMDS := ["place", "unplace", "swap", "set_form", "set_tac", "auto_deploy", "clear_board", "set_equip"]      # 편성 명령 —— 나머지(징집 · 선택권 · 조합 · 보급)는 '징집 · 조합'
## 11/12 방 규칙 —— 장수 선점제(claim, 기본 켜짐) · 장수 사망룰(deaths = 판 시작 때 죽는 기인 이상 장수 수, 0 = 끔). 대상은 is_urgent_unit(기인 이상)
const DEATH_OPTIONS := [3, 5, 10]
const STAGE_SHORT := {"morning": "준비", "noon": "토벌", "evening_prep": "대전 준비", "evening": "대전"}      # 소식의 시점 글 (Online.STAGE_SHORT 와 같다)

var server                    # MatchServer —— send(peer, msg)
var code := ""
var mode := "fast"
var max_seats := SEATS        # 이 방의 자리 수(총 인원) —— 4 · 6 · 8 (11/11). 시작할 때 빈자리만 봇으로 채운다
var host := -1                # 방장 peer
var seats := []               # [{name, human, peer, token, run, bot, ready, dead, battles, acted, watched, foe}]
var started := false
var human_n0 := 0             # 시작할 때 사람 수 —— 2명 이상이던 방에서 혼자 남으면 묻는다
var alone := ""               # "" · "ask"(혼자 남아 계속할지 묻는 중) · "go"(계속하기로 했다)
var stage := "lobby"          # lobby · morning · noon · evening_prep · evening · over
var stage_no := 0             # 단계가 바뀔 때마다 1씩 —— 늦게 온 '준비 완료'를 거른다
var stage_end := 0.0
var stage_len_now := 0.0      # 지금 단계의 전체 길이 (초) —— 방 정보 stage_len (휴대폰이 5초 경고를 단계 길이에 맞춘다)
var noon_end_sent := false    # 토벌 종료 알림(4일차 첫 단계)을 보냈나 —— 한 판에 한 번
var day := 0
var phase := 0
var pairs := []               # 저녁 대진 [[자리 a, 자리 b]] —— b 는 봇일 수 있다. 음수 -1 - d 는 멸망한 자리 d 를 대신하는 떠돌이 군세.
                              # 세 번째 칸 x(자리 번호)가 있으면 [a, -1 - d, x] —— 군세 대신 산 사람 x 의 그림자 (11/11 그림자 대전)
var rr_order := []            # 라운드로빈 자리 배치 —— 첫 저녁에 rng 로 한 번 섞고 방이 끝날 때까지 고정 (같은 순번이면 같은 짝)
var _ghosts := {}             # 멸망한 자리 번호 -> 떠돌이 군세(자리 밖 봇) —— 저녁 대전 상대 (전적은 이어진다)
var _mvp_news := []           # 수훈 연속 소식 대기 [{s, unit, n}] —— 그림자 소식처럼 대전을 다 본 뒤(다음 아침) 보낸다
var _shadow_news := []        # 그림자 대전 결과 소식 대기 —— 대전을 다 본 뒤(다음 날 아침을 열 때) 보낸다 (미리 보내면 결과가 새므로)
var tour = null               # {round, list:[{name, seat}], res:[[{a, b, w}]], next}
var rng := RandomNumberGenerator.new()
var empty_since := -1.0
var news_seq := 0             # 소식 항목 번호 —— _news_add 가 1씩 올려 붙인다 (휴대폰이 안 읽은 소식을 가른다)
var _news_stage := ""         # _advance 중에는 아직 stage 가 지난 단계라 시점을 '아침'으로 못박는다
var rlog: RoomLog = null      # 사람마다 플레이 기록 (11/10) —— 부수 효과일 뿐, 없어도(점검 방 · 쓰기 실패) 방은 그대로 간다
var claim_on := true          # 11/12 장수 선점제 —— 기인 이상은 먼저 등용한 사람만 (다른 사람은 조합 불가)
var death_n := 0              # 11/12 장수 사망룰 —— 판 시작 때 죽는 기인 이상 장수 수 (0 = 끔)
var claims := {}              # 선점 기록: 장수 id -> 먼저 등용한 자리 이름 (그 사람이 멸망 · 퇴장해도 풀지 않는다 —— 단순하게)
var dead_units := []          # 사망한 장수 id (시작 때 정하고 고정)


func _init(srv, room_code: String, m: String, n_seats = SEATS, claim = true, deaths = 0) -> void:
	server = srv
	code = room_code
	mode = m if MODES.has(m) else "fast"
	max_seats = valid_seats(n_seats)
	claim_on = not (typeof(claim) == TYPE_BOOL and not claim)      # 없거나 이상하면 켜짐 (옛 클라이언트도 선점제)
	death_n = valid_deaths(deaths)
	rng.randomize()


## 방 만들기 메시지의 deaths —— 3 · 5 · 10 만, 나머지(없음 · 0 · 이상한 값)는 0(끔)
static func valid_deaths(v) -> int:
	if (typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT) and int(v) == v and int(v) in DEATH_OPTIONS:
		return int(v)
	return 0


## 방 만들기 메시지의 max —— 허용한 짝수(4 · 6 · 8)만, 없거나 이상하면 8 (옛 클라이언트)
static func valid_seats(v) -> int:
	if (typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT) and int(v) == v and int(v) in SEAT_OPTIONS:
		return int(v)
	return SEATS


static func now() -> float:
	return Time.get_ticks_msec() / 1000.0


## 이 일차(0 = 1일차)에 점심(토벌) 단계가 있나 —— 1~3일차만 (11/11)
static func has_noon(day_i: int) -> bool:
	return Run.online_noon(day_i)


## 단계 길이(초) —— 토벌이 없는 날(4일차~)의 준비(morning) · 대전 준비(evening_prep)는 절반 (MODES 의 morning2 · prep2, 11/12 사용자). 점심 · 저녁은 그대로
static func stage_len(mode_: String, st: String, day_i: int) -> float:
	var m: Dictionary = MODES[mode_] if MODES.has(mode_) else MODES.fast
	var late := not has_noon(day_i)
	match st:
		"morning": return float(m.morning2 if late else m.morning)
		"noon": return float(m.noon)
		"evening_prep": return float(m.prep2 if late else m.prep)
		"evening": return float(m.evening)
	return 0.0


## 초 → 글 —— 60 → "1분", 30 → "30초", 0.5 → "0.5초" (점검 모드)
static func sec_text(v: float) -> String:
	if v >= 60.0 and fmod(v, 60.0) == 0.0:
		return "%d분" % int(v / 60.0)
	return "%d초" % int(v) if v == floorf(v) else "%.1f초" % v


## 토벌이 사라지는 날의 새 타이머 글 —— "준비 30초 · 대전 준비 15초"
static func cut_text(mode_: String) -> String:
	var d := Run.ONLINE_NOON_DAYS
	return "준비 %s · 대전 준비 %s" % [sec_text(stage_len(mode_, "morning", d)), sec_text(stage_len(mode_, "evening_prep", d))]


func humans() -> Array:
	return seats.filter(func(s): return s.human)


func seat_of(peer: int) -> int:
	for i in seats.size():
		if seats[i].human and seats[i].peer == peer:
			return i
	return -1


func day_no() -> int:
	return day * 3 + phase + 1


## 소식의 시점 글 —— "3일차 저녁" (11/10: 게임 날짜 · 페이즈 — 화면의 Online.day_text 와 같은 표기. day_no 는 페이즈 번호 1~21)
func when_text() -> String:
	var st := _news_stage if _news_stage != "" else stage
	return "%d일차 %s" % [day + 1, Run.PHASE_N[clampi(phase, 0, 2)]] if STAGE_SHORT.has(st) else ""


# ───────── 대기실 ─────────

## rec = 플레이 기록 동의 (hello 의 rec) —— 참인 사람만 RoomLog 가 파일로 남긴다. 기본은 거절(기록 안 함)
func add_human(peer: int, name_: String, token: String, rec := false) -> int:
	if started or humans().size() >= max_seats:
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
		if s.human and s.run != null:
			# 11/11 사용자: 다른 유저의 민심 · 핵심 유닛을 기록 탭에서 본다 —— 이전(11/9)에는 내 자리에만 보냈다.
			# 사람 자리마다 hp(정수) + key(기초불신 = 기인 · 초월 · 불멸 · 신화 카드 id 배열, 등급 높은 순). PV · 병사 수 · 나머지 덱은 여전히 보내지 않는다 (결정 ⑥).
			# 필드만 늘렸다 —— 옛 클라이언트는 모르는 키를 무시한다. 봇 자리에는 없다 (민심도 카드도 없다)
			row["hp"] = s.run.hp
			row["key"] = key_cards(s.run)
		if started and s.human:
			row["st"] = seat_status(s)      # 11/12 온라인 존재감 —— 지금 하는 일 (아래 '존재감' 절)
		ss.append(row)
	var me = null
	if i >= 0 and seats[i].foe != null:
		me = seats[i].foe
	return {"code": code, "mode": mode, "max": max_seats, "mode_n": MODES[mode].n, "started": started, "stage": stage, "stage_no": stage_no,
		"stage_n": STAGE_N.get(stage, stage), "remain": maxf(0.0, stage_end - now()), "stage_len": stage_len_now, "noon_end": noon_end_sent and day == Run.ONLINE_NOON_DAYS and phase == 0 and stage == "morning", "day": day, "phase": phase,
		"day_no": day_no(), "you": i, "host": i >= 0 and seats[i].human and seats[i].peer == host, "seats": ss, "foe": me,
		"noon": has_noon(day), "act": i >= 0 and can_cmd(i),
		"act_draw": cmd_block(i, "forge") == "", "act_form": cmd_block(i, "place") == "", "why_draw": cmd_block(i, "forge"), "why_form": cmd_block(i, "place"), "alone": alone, "tour_round": tour.round if tour != null else -1, "quick": QUICK_MSGS, "emote_n": EMOTE_N,
		"claim": claim_on, "deaths": death_n, "dead_units": dead_units, "dead_myth": dead_myths()}


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
	var gen_names := DB.gen_bot_names(rng.seed, max_seats, used)      # 11/10 봇 이름은 방마다 랜덤 (사람 이름과 겹치지 않게)
	while seats.size() < max_seats:
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
		r.on_forge = _on_forged.bind(s)
	_pick_deaths()
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
	var len := stage_len(mode, st, day)
	stage_len_now = len
	stage_end = now() + len
	for s in seats:
		if s.human:
			s.ready = false
			s.acted = false
			s.watched = false
			if st in ACT_STAGES:
				s["auto"] = false
			elif st in WATCH_STAGES and s.battles.is_empty():
				s.ready = true          # 11/11 볼 전투가 없다(멸망 · 토너먼트 부전승 · 탈락) —— 누르지 않아도 준비다
				s.watched = true
	if rlog != null:
		rlog.on_stage(self)
	push_all()


## 준비를 기다리는 사람 —— 접속해 있고 멸망하지 않은 사람. 모두 준비면 시간이 남아도 넘어간다.
## 전투를 보는 단계에서는 볼 전투가 있는 사람은 멸망했어도 기다린다 (토너먼트 탈락전 · 멸망한 토벌을 끝까지 보게)
func _live() -> Array:
	var tour_eve := stage == "evening" and tour != null
	return humans().filter(func(s):
		if s.peer < 0:
			return false
		if stage in WATCH_STAGES and s.get("auto", false):
			return false      # 11/11 직전 준비를 봇이 대신 했다(단계 내내 아무 행동 없음 = 자리를 비움) —— 전투를 다 보기를 기다리지 않는다
		if tour_eve and s.battles.is_empty():
			return false      # 토너먼트 부전승(이번 라운드는 싸움이 없다) · 이미 탈락 —— 기다리지 않는다
		return not s.dead or (stage in WATCH_STAGES and not s.battles.is_empty()))


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
	_status_sync()
	var live := _live()
	var all_ready := (not live.is_empty() or (stage == "evening" and tour != null)) and live.all(func(s): return s.ready)
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


## 이 명령을 지금 받을 수 있나 —— 되면 "", 안 되면 짧은 이유 (11/12 사용자 페이즈 개편, 맨 위 설명).
## m 이 FORM_CMDS 면 편성, 아니면 징집 · 조합. 이미 계산된 판(토벌 · 대전)은 편성을 복사해 갔으므로 기다리는 동안의 징집 · 조합이 그 결과를 바꾸지 못한다.
## 늘 안 되는 것: 멸망 · 판이 끝난 사람, 토너먼트 저녁(라운드마다 그 순간의 편성으로 곧바로 다시 계산한다)
func cmd_block(i: int, m: String) -> String:
	if not started or i < 0 or i >= seats.size() or not seats[i].human or seats[i].dead or seats[i].run == null or seats[i].run.over != null:
		return "지금은 할 수 없다"
	var form: bool = m in FORM_CMDS
	match stage:
		"morning":
			return ""
		"evening_prep":
			return "" if form else "대전 준비 중 — 지금은 편성만 할 수 있다"
		"noon", "evening":
			if stage == "evening" and tour != null:
				return "토너먼트 중에는 손댈 수 없다"
			if form:
				return "지금은 편성할 수 없다 — 다음 준비 때"
			if not seats[i].watched:
				return "전투를 다 본 뒤에 할 수 있다"
			return ""
	return "지금은 할 수 없다"


## 무엇이든 하나라도 할 수 있나 (방 정보 act —— 옛 클라이언트용)
func can_cmd(i: int) -> bool:
	return cmd_block(i, "forge") == "" or cmd_block(i, "place") == ""


func on_cmd(peer: int, m: String, a: Array) -> void:
	var i := seat_of(peer)
	if i < 0:
		return
	var why := cmd_block(i, m)
	if why != "":
		server.send(peer, {"t": "error", "msg": why})
		push(seats[i])      # 클라이언트가 먼저 바꿔 둔 상태를 되돌린다
		return
	var r: Run = seats[i].run
	why = lock_reason(r, m, a)
	if why != "":
		server.send(peer, {"t": "toast", "text": why, "kind": "bad"})
		push(seats[i])      # 클라이언트가 먼저 해 본 조합을 되돌린다
		return
	var ok = r.command(m, a)
	seats[i].acted = true
	seats[i]["cmd_t"] = now()      # 11/12 상태 아이콘 —— 방금 손을 댔다 (BUSY_SEC 동안 🔨)
	if rlog != null:
		rlog.act(i, r, m, a, ok)
	# 11/9 사용자: 다른 사람의 소식도 와야 한다 —— 조합 · 선택권으로 등용하면 방의 다른 사람에게 소식 + 알림
	# 11/10 사용자: 기인 이상(기인 · 초월 · 불멸 · 신화)으로 정리 —— 기인은 등급 값이 전설(5)이라 is_kiin 으로 따로 센다. 본인에게는 보내지 않는다(조합 완성 연출이 있다)
	if ok and m in ["forge", "pick"] and not a.is_empty() and is_urgent_unit(str(a[0])):
		var it := {"who": seats[i].name, "unit": str(a[0])}
		_news_add(it, seats[i])
		_announce("%s가 %s을(를) 등용했습니다" % [seats[i].name, DB.C[str(a[0])].name], it, seats[i], true)
		_foe_preview(i, str(a[0]))      # 11/12 오늘 밤 상대에게만 예고
	var sig := ",".join(key_cards(r))
	var changed: bool = sig != str(seats[i].get("key_sig", ""))
	seats[i]["key_sig"] = sig
	if changed:
		push_all()      # 11/11 핵심 유닛이 늘거나 줄었다 —— 다른 사람 화면의 기록 탭도 새로 (보통은 단계가 바뀔 때만 모두에게 간다). 드문 일이라 부담이 없다
	else:
		push(seats[i])


# ───────── 장수 선점제 · 사망룰 (11/12) ─────────

## 사망 장수 뽑기 —— 조합으로 얻을 수 있는 기인 이상(적 전용 제외) 중 death_n 명. 방의 rng 로 (시작 때 한 번), 모두에게 소식 한 줄
func _pick_deaths() -> void:
	dead_units = []
	if death_n > 0:
		var cand: Array = DB.RECOF.keys().filter(func(k): return is_urgent_unit(str(k)) and not DB.is_foe(str(k)))
		cand.sort()
		while dead_units.size() < death_n and not cand.is_empty():
			dead_units.append(str(cand.pop_at(rng.randi() % cand.size())))
	_sync_locks()
	if not dead_units.is_empty():
		_news_stage = "morning"
		var tx := "%s 사망 —— 이번 판 등용 불가" % " · ".join(dead_units.map(func(k): return DB.C[k].name))
		var dm := dead_myths()
		if not dm.is_empty():      # 하위 불멸이 죽어 함께 못 만드는 신화
			tx += " (신화 %s 도)" % " · ".join(dm.map(func(k): return DB.C[k].name))
		_news_add({"who": "천명", "text": tx})
		_news_stage = ""


## 불멸(7등급) 카드 k 를 재료로 쓰는 신화 id —— 하위 불멸이 사망하면 신화도 못 만든다. 없으면 "" (11/12 사용자)
static func myth_over(k: String) -> String:
	if not DB.C.has(k) or int(DB.C[k].tier) != 7:
		return ""
	for o in DB.RECOF:
		if DB.C.has(o) and int(DB.C[o].tier) >= 8 and not DB.is_foe(str(o)) and DB.RECOF[o].has(k):
			return str(o)
	return ""


## 사망 장수의 상위 신화들 (이미 사망 명단에 든 신화는 뺀다) —— 방 정보 dead_myth
func dead_myths() -> Array:
	var out := []
	for k in dead_units:
		var m := myth_over(str(k))
		if m != "" and not (m in dead_units) and not (m in out):
			out.append(m)
	return out


## 사람마다 Run.locked 를 새로 채운다 —— 사망 장수 + (선점제면) 다른 사람이 먼저 등용한 장수
func _sync_locks() -> void:
	for s in humans():
		if s.run == null:
			continue
		var lk := {}
		for k in dead_units:
			lk[k] = {"dead": 1}
		for k in dead_myths():
			lk[k] = {"dead": 1}      # 하위 불멸이 사망 —— 그 신화도 등용 불가 (재료인 불멸을 못 만드니 원래도 못 만들지만 표시 · 거부 · 유니크 보급 거르기에 명시)
		if claim_on:
			for k in claims:
				if str(claims[k]) != str(s.name):
					lk[k] = {"by": claims[k]}
		s.run.locked = lk
		if s.run.prune_unique_offer():      # 11/12 열려 있는 유니크 보급에 막힌 신화의 재료가 있으면 갈아 끼운다
			if s.peer >= 0:
				server.send(s.peer, {"t": "toast", "text": "다른 유저가 신화를 선점해 유니크 보급 한 개가 바뀌었습니다", "kind": "news"})


## Run.forge 가 성공하면 부른다 (사람의 명령 · 봇 대행 모두) —— 기인 이상을 처음 등용하면 선점으로 적고 다른 사람의 Run 을 바로 잠근다
## (같은 단계에서 봇 대행이 차례로 조합해도 뒤 사람이 같은 장수를 만들지 못하게)
func _on_forged(k: String, s: Dictionary) -> void:
	# 11/12 사용자: 신화를 만들어 재료인 하위 불멸이 없어져도 그 불멸의 선점은 풀지 않는다 —— 신화를 만든 사람 몫으로 남아 다른 사람이 그 불멸을 얻지 못한다
	if not claim_on or not is_urgent_unit(k) or claims.has(k):
		return
	claims[k] = s.name
	_sync_locks()


## 등용 거부 까닭 —— 잠긴 장수를 조합하려 하면 (클라이언트가 늦게 받은 경우 등). "" 이면 거부 아님
func lock_reason(r: Run, m: String, a: Array) -> String:
	if not (m in ["forge", "pick"]) or a.is_empty() or not r.locked.has(str(a[0])):
		return ""
	var k := str(a[0])
	var nm: String = DB.C[k].name if DB.C.has(k) else k
	var e = r.locked[k]
	if e is Dictionary and e.has("by"):
		return "장수 선점제 —— %s은(는) %s 세력이 먼저 등용해 등용할 수 없습니다" % [nm, str(e.by)]
	return "장수 사망룰 —— %s은(는) 이번 판에 사망해 등용할 수 없습니다" % nm


## 긴급 소식 대상 —— 기인 이상 (기인 · 초월 6 · 불멸 7 · 신화 8)
static func is_urgent_unit(k: String) -> bool:
	return DB.C.has(k) and (DB.is_kiin(k) or int(DB.C[k].tier) >= 6)


## 11/11 기록 탭에 보이는 핵심 유닛 —— 가진 카드(손패 + 편성판) 중 기초불신(기인 · 초월 · 불멸 · 신화)의 id (한 종류에 하나 · 등급 높은 순 → id 순).
## 순위: 신화 8 > 불멸 7 > 초월 6 > 기인 (기인은 등급 값이 전설 5 라 따로 5 로 센다)
static func key_cards(r: Run) -> Array:
	var out := []
	var p := r.pool()
	for k in p:
		if is_urgent_unit(str(k)) and int(p[k]) > 0:
			out.append(str(k))
	out.sort_custom(func(a, b):
		var ra := key_rank(a)
		var rb := key_rank(b)
		return ra > rb if ra != rb else a < b)
	return out


static func key_rank(k: String) -> int:
	return 5 if DB.is_kiin(k) else int(DB.C[k].tier)


## 응답이 없는 사람 몫을 봇이 한다 —— 끊겼거나 단계 내내 아무 행동도 없으면 전부, 행동은 했으면 빈 것만
func _fill(s: Dictionary, full_if_idle := true) -> void:
	var r: Run = s.run
	var idle: bool = s.peer < 0 or (full_if_idle and not s.acted)
	s["auto"] = idle      # 11/11 봇이 대신했다 —— 이어지는 전투 보는 단계에서 기다리지 않는다 (_live)
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
	if not has_noon(day):
		# 11/11 사용자: 4일차~ 는 토벌이 없다 —— 점심 단계 없이 바로 저녁 준비(상대 정하기). 봇의 토벌 실패(strikes)만 그대로 센다 (봇 성장 곡선 불변)
		for s in seats:
			s.battles = []
		_bot_quest_strikes()
		_begin_evening()
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
	_bot_quest_strikes()
	_check_alone()


## 봇의 토벌 —— 그날 기준(QPV)에 못 미치면 실패 한 번 · 전력 6% 깎임 (봇 성장 곡선). 토벌이 없는 날(4일차~)에도 똑같이 돈다
func _bot_quest_strikes() -> void:
	var qpv := float(DB.D.QPV[day][phase])
	for s in seats:
		if not s.human and s.bot.pv < qpv * 0.95 * rng.randf_range(0.92, 1.08):
			s.bot.strikes += 1
			s.bot.pv *= 0.94


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
## 11/11 그림자 대전: alive_humans(멸망하지 않은 사람 자리들)를 주면, 산 자리가 사람이고 자신 말고 산 사람이 또 있을 때 군세 대신
## 그 사람 x 의 그림자와 붙는다 [산 자리, -1 - 멸망 자리, x]. 안 주면(기본) 전과 같다.
static func rr_plan(order: Array, rd: int, dead: Array, alive_humans: Array = [], cycle := 0) -> Array:
	var out := []
	var sd := dead.duplicate()
	sd.sort()
	for p in rr_round(order, rd):
		var da: bool = p[0] in dead
		var db: bool = p[1] in dead
		if da and db:
			continue
		elif da:
			out.append(shadow_pair(int(p[1]), int(p[0]), sd, alive_humans, cycle))
		elif db:
			out.append(shadow_pair(int(p[0]), int(p[1]), sd, alive_humans, cycle))
		else:
			out.append(p)
	return out


## 멸망한 자리 d 의 짝이던 산 자리 c 의 오늘 짝 —— c 가 사람이고 다른 산 사람이 있으면 [c, -1 - d, x], 아니면 [c, -1 - d] (떠돌이 군세).
## x 는 자신을 뺀 산 사람(자리 번호 오름차순)을 돌아가며 고른다: 인덱스 = (cycle * 멸망 수 + d 의 멸망 순서 + c) % 후보 수.
## cycle = 저녁 순번(day*3 + phase) / (자리 수 - 1) = 몇 번째 바퀴. 한 바퀴에 c 는 멸망 자리마다 한 번씩 그림자와 붙으니 (cycle, d 순서)가 c 에게 1씩 늘어나는 번호가 되고,
## 그래서 후보 모두가 고르게(차 ≤ 1) 돌아온다. 난수 없음 —— 같은 입력이면 같은 x
static func shadow_pair(c: int, d: int, dead_sorted: Array, alive_humans: Array, cycle: int) -> Array:
	var pr := [c, -1 - d]
	if not (c in alive_humans):
		return pr
	var cands := alive_humans.filter(func(h): return int(h) != c)
	if cands.is_empty():
		return pr
	cands.sort()
	pr.append(int(cands[(cycle * dead_sorted.size() + dead_sorted.find(d) + c) % cands.size()]))
	return pr


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
	var alive_h := []      # 그림자의 원본이 될 수 있는 사람 —— 멸망하지 않았고 자리를 떠나지 않은(token 이 있는) 사람. 접속이 끊겨 봇이 대신하는 사람도 포함 (덱은 진짜)
	for i in seats.size():
		if seats[i].human and seats[i].dead:
			dead.append(i)
		elif seats[i].human and seats[i].run != null and seats[i].token != "":
			alive_h.append(i)
	var ev_no := day * 3 + phase
	pairs = rr_plan(rr_order, ev_no % (max_seats - 1), dead, alive_h, ev_no / (max_seats - 1))
	for p in pairs:
		var a: Dictionary = _pair_seat(p[0])
		var b: Dictionary = _pair_seat(p[1], int(p[2]) if p.size() > 2 else -1)
		if a.human:
			a.foe = _foe_for(a, b)
		if b.human:
			b.foe = _foe_for(b, a)
	_stage("evening_prep")


## 짝에 적힌 번호의 자리 —— 음수는 멸망한 자리를 대신하는 떠돌이 군세 (세기 = 방 평균 PV, 전적은 이어진다)
## shadow >= 0 이면 군세 대신 그 자리(산 사람)의 그림자 —— 이름 "<이름>의 그림자", 전적은 원본의 것을 보이기만 한다 (원본은 건드리지 않는다)
func _pair_seat(i: int, shadow := -1) -> Dictionary:
	if i >= 0:
		return seats[i]
	if shadow >= 0:
		var src: Dictionary = seats[shadow]
		var sh := _bot_seat("%s의 그림자" % src.name, SHADOW_EPI, "군", "균형", float(_pv(src)), 1.0)
		sh.bot.w = src.run.my_w
		sh.bot.l = src.run.my_l
		sh["shadow_of"] = shadow
		return sh
	var d := -1 - i
	if not _ghosts.has(d):
		_ghosts[d] = _bot_seat("유랑군 %d" % (d + 1), "떠돌이 군세", "군", "균형", 0.0, 1.0)
	_ghosts[d].bot.pv = float(_avg_pv())
	return _ghosts[d]


## 상대 정보 —— 이름 · 전적 · 핵심 장수 (PV 와 편성은 보이지 않는다, 결정 ⑥)
## 11/12 사용자: 상대가 정해지면 그 핵심 장수(key_cards —— 기록 탭의 「군웅」 과 같은 것)를 높은 등급부터. 사람은 그 Run, 그림자는 원본의 Run.
## 봇은 군세를 전투마다 새로 뽑아 key 가 없다(클라이언트가 예시를 그린다). 봇의 칭호(BOTNAME 의 둘째 칸)는 보이지 않는다 —— epi "봇"
func _foe_info(s: Dictionary) -> Dictionary:
	var d := {"name": s.name, "human": s.human, "online": s.human and s.peer >= 0,
		"epi": "사람" if s.human else (s.bot.epi if s.bot.epi in [SHADOW_EPI, "떠돌이 군세"] else "봇"), "w": s.run.my_w if s.human else s.bot.w, "l": s.run.my_l if s.human else s.bot.l}
	if s.human:
		d["key"] = key_cards(s.run)
	elif s.has("shadow_of"):
		d["key"] = key_cards(seats[int(s.shadow_of)].run)
	return d


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
		var x := int(p[2]) if p.size() > 2 else -1
		var a: Dictionary = _pair_seat(p[0])
		var b: Dictionary = _pair_seat(p[1], x)
		if x >= 0 and a.human:
			_pvp_shadow(a, seats[x], b)
		elif a.human and b.human:
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
	_mvp_track(x, res, "A", bool(res.win))
	_mvp_track(y, res, "B", bool(flipped.win))
	_beat_track(x, y, bool(res.win), bool(res.draw))      # 11/12 설욕전
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
	_mvp_track(x, res, "A", bool(res.win))
	if res.win:
		b.bot.l += 1
	else:
		b.bot.w += 1
	x.battles.append({"title": bt.title, "res": res, "kind": "pvp", "params": _params(bt, false)})
	if rlog != null:
		rlog.battle(_idx(x), rx, bt, res, b.name, false, x.peer < 0)
		rlog.reward(_idx(x), rx)


## 그림자 대전 (11/11) —— c 가 멸망한 자리 대신 산 사람 xs 의 그림자와 싸운다. 그림자 = xs 의 지금 잠긴 편성(진형 · 작전 · 장비 · 사기)의 복사본.
## c 쪽은 사람과의 대전과 똑같이 정산(전적 · 보상 · 민심)하고, xs 는 아무것도 바뀌지 않는다 (전적 · 민심 · 순위 · 경고 · 보상 · 전투 기록 없음).
## 결과 소식은 대전을 다 본 뒤 (다음 날 아침을 열 때) c · xs 에게만
func _pvp_shadow(c: Dictionary, xs: Dictionary, sh: Dictionary) -> void:
	var rc: Run = c.run
	var bt := {"kind": "pvp", "a": rc._my_side(), "b": (xs.run._my_side() as Dictionary).duplicate(true), "seed": rng.randi() % 1000000,
		"title": "대전 · %s" % sh.name, "foe": sh.name, "inputs": []}
	bt.pol = Run.policy_for(bt)
	var res := Run.simulate(bt, [], bt.pol)
	rc.battle = bt
	rc.finish_battle(res)
	_mvp_track(c, res, "A", bool(res.win))
	c.battles.append({"title": bt.title, "res": res, "kind": "pvp", "params": _params(bt, false)})
	_shadow_news.append({"c": c, "x": xs, "win": bool(res.win), "draw": bool(res.draw)})
	if rlog != null:
		rlog.battle(_idx(c), rc, bt, res, sh.name, true, c.peer < 0, bool(xs.get("rec", false)), {"ghost": true, "ghost_of": xs.name})
		rlog.reward(_idx(c), rc)


## 한 진영의 수훈 장수 id —— Battle 의 MVP 와 같은 공식(피해 + 기술 피해 · 회복 ×420 + 처치 ×3200)을 결과 로스터로. 없으면 ""
static func side_mvp(res: Dictionary, camp: String) -> String:
	var best := ""
	var bm := 0.0
	for u in res.get("roster", []):
		if str(u.get("camp", "")) != camp:
			continue
		var m := float(u.get("dmg", 0)) + float(u.get("mdmg", 0)) * 420.0 + float(u.get("heal", 0)) * 420.0 + float(u.get("kills", 0)) * 3200.0
		if m > bm:
			bm = m
			best = str(u.get("id", ""))
	return best


## 유저전 수훈 연속 —— 이긴 판의 수훈이 기인 이상이고 지난 판과 같은 장수면 +1, 아니면 처음부터. 2 이상이면 소식 대기
func _mvp_track(s: Dictionary, res: Dictionary, camp: String, won: bool) -> void:
	if not s.human:
		return
	_streak_track(s, won)      # 11/12 판세 소식 —— 연승 (유저전마다 한 번씩 불린다)
	var k := side_mvp(res, camp) if won else ""
	var st: Array = s.get("mvp_st", ["", 0])
	if k == "" or not is_urgent_unit(k):
		s["mvp_st"] = ["", 0]
		return
	var n: int = int(st[1]) + 1 if str(st[0]) == k else 1
	s["mvp_st"] = [k, n]
	if n >= 2:
		_mvp_news.append({"s": s, "unit": k, "n": n})


## 수훈 연속 소식 —— 방 전체에 (대전을 다 본 뒤라 결과가 새지 않는다). 3연속부터 긴급 띠(hot) —— line 은 띠 문구
func _flush_mvp_news() -> void:
	var save := _news_stage
	_news_stage = "evening"
	for e in _mvp_news:
		var s: Dictionary = e.s
		var nm: String = DB.C[e.unit].name
		var tail: String = MVP_STREAK_TEXT[mini(int(e.n), 4)]
		var tx := "%s의 %s%s %s (%d연속 수훈)" % [s.name, nm, "이" if _batchim(nm) else "가", tail, int(e.n)]
		var it := {"who": s.name, "text": tx}      # 소식 목록에는 글만 (장수가 있으면 등용 줄로 보이므로)
		_news_add(it)
		var ann := it.duplicate()
		ann["unit"] = e.unit
		ann["line"] = tail
		_announce(tx, ann, null, int(e.n) >= 3)
	_mvp_news = []
	_news_stage = save


static func _batchim(t: String) -> bool:
	if t == "":
		return false
	var c := t.unicode_at(t.length() - 1)
	return c >= 0xAC00 and c <= 0xD7A3 and (c - 0xAC00) % 28 != 0


## 그림자 대전 결과 소식 —— 싸운 사람 c 와 원본 x 에게만 (방 전체에는 뿌리지 않는다). 대전을 다 본 뒤라 결과가 새지 않는다
func _flush_shadow_news() -> void:
	var save := _news_stage
	_news_stage = "evening"      # 소식의 시점은 싸운 저녁
	for e in _shadow_news:
		var c: Dictionary = e.c
		var x: Dictionary = e.x
		var res_t := "무승부" if e.draw else ("승리" if e.win else "패배")
		var it_c := {"who": c.name, "text": "%s의 그림자에게 %s" % [x.name, res_t]}
		_news_add(it_c, null, [c])
		_announce("%s이(가) %s" % [c.name, it_c.text], it_c, null, false, [c])
		var it_x := {"who": c.name, "text": "당신의 그림자와 싸워 %s" % res_t}
		_news_add(it_x, null, [x])
		_announce("%s이(가) %s" % [c.name, it_x.text], it_x, null, false, [x])
	_shadow_news = []
	_news_stage = save


func _bot_side(b: Dictionary) -> Dictionary:
	return Run.bot_side(b.bot.pv * Run.BOT_PV_MUL, b.bot.style, day * 3 + phase, rng)


## 다음 날 아침
func _advance() -> void:
	_flush_shadow_news()
	_flush_mvp_news()
	_flush_presence_news()      # 11/12 연승 · 민심 위기 —— 대전을 다 본 뒤
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
	var cut := day == Run.ONLINE_NOON_DAYS and phase == 0 and not noon_end_sent      # 4일차 첫 단계 —— 토벌이 사라지고 타이머가 절반이 된다 (한 판에 한 번)
	if cut:
		noon_end_sent = true      # 방 정보 noon_end 가 이 단계 상태에 실리도록 _stage 전에
	_stage("morning")
	if cut:
		_noon_end_news()
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
	while ps.size() < max_seats:      # 멸망한 사람 자리는 떠돌이 군세로 채운다
		var bs := _bot_seat("유랑군 %d" % k, "떠돌이 군세", "군", "균형", float(_avg_pv()), 1.0)
		seats.append(bs)
		ps.append({"name": bs.name, "seat": seats.size() - 1, "pv": _pv(bs)})
		k += 1
	ps.sort_custom(func(a, b): return a.pv > b.pv)
	# 대진표는 8강 · 4강 · 결승 틀 하나 —— 인원이 8 미만이면 8 이상 시드(상대 없는 자리)는 부전승. 8명이면 8강 4판, 6명이면 8강 2판(1 · 2위 시드 부전승), 4명이면 4강부터.
	# 부전승 자리는 carry 에 먼저 넣고(빈 칸 = 8강 승자가 들어간다), 8강이 없으면 carry 가 곧 4강 명단
	var lst := []
	var carry := []
	for m in 4:
		var i: int = SEED_ORDER[m * 2]
		var j: int = SEED_ORDER[m * 2 + 1]
		if j < ps.size():
			lst.append(ps[i])
			lst.append(ps[j])
			carry.append(null)
		else:
			carry.append(ps[i])
	var first := 0
	var bye := []
	if lst.is_empty():
		first = 1
		lst = carry
		carry = []
	else:
		for c in carry:
			if c != null:
				bye.append(c.name)
	tour = {"round": first, "list": lst, "res": [null, null, null], "next": null, "carry": carry, "bye": bye}
	for m in lst.size() / 2:
		var a: Dictionary = lst[m * 2]
		var b: Dictionary = lst[m * 2 + 1]
		for pair in [[a, b], [b, a]]:
			var s: Dictionary = seats[pair[0].seat]
			if s.human:
				s.foe = _foe_for(s, seats[pair[1].seat])
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
				run.over = {"win": false, "msg": "%s에서 %s에게 패했다 — 최종 %s" % [Run.ROUNDNM[r], pair[1].name, tour_rank_text(r)]}
				s.dead = true
		ms.append({"a": a, "b": b, "w": w.name})
	tour.res[r] = ms
	tour.next = ms.map(func(x): return x.a if x.w == x.a.name else x.b)
	_tour_view()
	for s in humans():
		if s.run.over != null:
			_log_over(s)


## 토너먼트에서 진 라운드(0 = 8강 · 1 = 4강 · 2 = 결승)의 최종 순위 글 —— 8강 탈락은 5위부터 방 인원(max)까지
func tour_rank_text(r: int) -> String:
	return ("5~%d위" % max_seats) if r == 0 else ("3~4위" if r == 1 else "2위")


## 사람마다 Run.tour 를 채운다 —— 화면(_bracket)이 그대로 그린다
func _tour_view() -> void:
	for s in humans():
		var v := {"round": tour.round, "res": [null, null, null], "my_match": -1, "next": null, "bye": tour.get("bye", [])}
		var rounds: Array = tour.res.duplicate()
		if rounds[tour.round] == null:
			rounds[tour.round] = _tour_pending(tour.list)
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
	var nxt: Array = tour.next
	if not tour.carry.is_empty():      # 부전승으로 먼저 올라가 있던 자리 + 8강 승자 (빈 칸에 차례로)
		var full := []
		var k := 0
		for c in tour.carry:
			if c == null:
				full.append(nxt[k])
				k += 1
			else:
				full.append(c)
		nxt = full
		tour.carry = []
		tour.bye = []
	tour.list = nxt
	tour.round += 1
	for s in seats:
		s.foe = null
	for m in tour.list.size() / 2:
		var a: Dictionary = tour.list[m * 2]
		var b: Dictionary = tour.list[m * 2 + 1]
		for pair in [[a, b], [b, a]]:
			var s: Dictionary = seats[pair[0].seat]
			if s.human:
				s.foe = _foe_for(s, seats[pair[1].seat])
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
## 11/12 사용자(온라인 존재감): 방 전체에 긴급 띠 「<유저>의 나라가 무너졌습니다 —— 남은 군주 N명」 (band = "fall", 장수 없는 띠 · 옛 휴대폰은 알림 한 줄)
func _fallen(s: Dictionary) -> void:
	var n := seats.filter(func(o): return not (o.human and o.dead)).size()
	var tx := "%s의 나라가 무너졌습니다 —— 남은 군주 %d명" % [s.name, n]
	var it := {"who": s.name, "text": tx}
	_news_add(it, s)
	var ann := it.duplicate()
	ann["band"] = "fall"
	ann["line"] = "남은 군주 %d명" % n
	_announce(tx, ann, s, true)


## 11/12 사용자: 토벌이 사라지는 순간(4일차 첫 단계)의 알림 —— 「토벌 종료 / 이제부터 준비 30초 · 대전 준비 15초」. 방 전체에 소식 한 줄 + band "noon_end" (새 휴대폰은 아침 띠 대신 이 띠,
## 옛 휴대폰은 band · line 을 모르고 text 를 알림 한 줄로만 본다). 필드만 늘렸다
func _noon_end_news() -> void:
	var line := cut_text(mode)
	var it := {"who": "천명", "text": "토벌 종료 —— 이제부터 %s" % line, "band": "noon_end", "line": line}
	_news_add(it)
	_announce(it.text, it)


## 소식을 모든 사람의 Run.news 에 넣는다 (except 는 뺀다) —— 머리띠 '소식' 뱃지 · 전황 소식 시트가 그대로 쓴다
func _news_add(it: Dictionary, except = null, only = null) -> void:
	if not it.has("id"):
		news_seq += 1
		it["id"] = news_seq
	if not it.has("when"):
		var w := when_text()
		if w != "":
			it["when"] = w
	for s in humans():
		if s == except or s.run == null or (only != null and not (s in only)):
			continue
		s.run.news.push_front(it)
		s.run.news = s.run.news.slice(0, 12)


## 접속한 모든 사람에게 소식 한 줄 {"t":"news","list":[{text, kind, who?, unit?, id?, when?, hot?}]} (except 는 뺀다) —— who · unit · id · when 은 상태의 Run.news 항목과 같아 휴대폰이 겹침을 가릴 수 있다.
## hot = 긴급 띠 연출을 띄우라는 표시 (사람의 기인 이상 등용만) —— 모르는 옛 휴대폰은 그냥 알림 한 줄
func _announce(text: String, it = null, except = null, hot := false, only = null) -> void:
	var e := {"text": text, "kind": "news"}
	if it is Dictionary:
		for k in ["who", "unit", "id", "when", "line", "band"]:
			if it.has(k):
				e[k] = it[k]
	if hot:
		e["hot"] = 1
	for s in humans():
		if s == except or s.peer < 0 or (only != null and not (s in only)):
			continue
		server.send(s.peer, {"t": "news", "list": [e]})


## 한마디 · 이모티콘을 보낼 수 있나 —— 자리가 있고, 한 사람이 SAY_GAP 초에 한 번 (글과 이모티콘이 같은 간격을 쓴다). 되면 보낸 시각을 적고 자리를 돌려준다
func _say_seat(peer: int) -> Dictionary:
	var si := seat_of(peer)
	if si < 0:
		return {}
	var s: Dictionary = seats[si]
	if now() - float(s.get("say_t", -100.0)) < SAY_GAP:
		return {}
	s.say_t = now()
	return s


## 한마디 —— 미리 적힌 글(QUICK)의 번호만 받는다. 한 사람이 SAY_GAP 초에 한 번. 대기실에서도 된다
func on_say(peer: int, i: int) -> void:
	if seat_of(peer) < 0 or i < 0 or i >= QUICK_MSGS.size():
		return
	var s := _say_seat(peer)
	if s.is_empty():
		return
	for o in humans():
		if o.peer >= 0:
			server.send(o.peer, {"t": "say", "who": s.name, "text": QUICK_MSGS[i]})


## 한마디 이모티콘 (11/10 사용자) —— 번호(0 ~ EMOTE_N-1)만 받는다. 간격은 글과 같이 쓴다. 방의 모두에게 {"t":"emote","who","i"}.
## 옛 클라이언트는 모르는 종류라 그냥 무시한다. 기록(RoomLog)에는 한마디를 남기지 않으므로 이모티콘도 남기지 않는다
func on_emote(peer: int, i: int) -> void:
	if seat_of(peer) < 0 or i < 0 or i >= EMOTE_N:
		return
	var s := _say_seat(peer)
	if s.is_empty():
		return
	for o in humans():
		if o.peer >= 0:
			server.send(o.peer, {"t": "emote", "who": s.name, "i": i})


# ───────── 존재감 (11/12 사용자: 정적인 게임에서 다른 유저의 움직임을 계속 느끼게) ─────────
## 상태 아이콘 —— 방 정보의 사람 자리 줄 st 와, 바뀔 때마다 모두에게 {"t":"act_st","st":[자리마다]} (가벼운 메시지, 상태 전체를 다시 보내지 않는다).
##   busy 🔨 징집 · 조합 · 편성 중(마지막 명령이 BUSY_SEC 안) · quest ⚔ 토벌 중 · pvp 🛡 대전 중(아직 다 안 봤다) · idle 💤 대기 · ready ✔ 준비 완료(아침 · 저녁 준비)
##   멸망 · 끊김 · 봇 · 대기실은 "" (끊김 · 멸망은 따로 표시가 있다)
## 상대 예고 —— 오늘 밤 내 유저전 상대(사람)가 기인 이상을 등용하면 나에게만 소식 (방 전체의 등용 띠는 그대로)
## 판세 소식 —— N연승(3 이상, 이번 저녁에 늘었을 때) · 민심 위기(30 이하로 처음) : 대전을 다 본 뒤(_advance 맨 앞) 방 전체에 소식 + 작은 알림 (긴급 띠 아님)
## 설욕전 —— 나를 (사람끼리 대전에서) 이긴 사람과 다시 만나면 상대 정보에 revenge = true. 이기면 지운다
const BUSY_SEC := 6.0
const STREAK_MIN := 3
const HP_CRISIS := 30         # HpGauge 의 붉은 선과 같다
var _st_sig := ""


func seat_status(s: Dictionary) -> String:
	if not started or not s.human or s.dead or s.peer < 0 or stage == "over":
		return ""
	if stage in ACT_STAGES and s.ready:
		return "ready"
	if stage in WATCH_STAGES and not s.watched and not s.battles.is_empty():
		return "quest" if stage == "noon" else "pvp"
	if now() - float(s.get("cmd_t", -100.0)) < BUSY_SEC:
		return "busy"
	return "idle"


## 상태가 바뀌었으면 모두에게 (tick 마다 부른다 —— 자리 8개라 가볍다)
func _status_sync() -> void:
	var st := []
	for s in seats:
		st.append(seat_status(s))
	var sig := ",".join(st)
	if sig == _st_sig:
		return
	_st_sig = sig
	for o in humans():
		if o.peer >= 0:
			server.send(o.peer, {"t": "act_st", "st": st})


## 오늘 밤 이 자리(i)의 상대가 될 사람 자리 —— 아침 · 점심에만(저녁 준비부터는 상대 칸이 이미 보인다). 첫 저녁 전(자리 배치 전) · 토너먼트 날 · 그림자 · 봇이면 -1.
## _begin_evening 과 같은 식(rr_plan)으로 미리 셈한다 —— 난수를 쓰지 않는다
func tonight_foe(i: int) -> int:
	if not (stage in ["morning", "noon"]) or tour != null or rr_order.size() != seats.size() or (day == 6 and phase == 2):
		return -1
	var dead := []
	var alive_h := []
	for k in seats.size():
		if seats[k].human and seats[k].dead:
			dead.append(k)
		elif seats[k].human and seats[k].run != null and seats[k].token != "":
			alive_h.append(k)
	var ev_no := day * 3 + phase
	for p in rr_plan(rr_order, ev_no % (max_seats - 1), dead, alive_h, ev_no / (max_seats - 1)):
		if p.size() != 2 or int(p[0]) < 0 or int(p[1]) < 0:
			continue
		var o := -1
		if int(p[0]) == i:
			o = int(p[1])
		elif int(p[1]) == i:
			o = int(p[0])
		if o >= 0 and seats[o].human and not seats[o].dead:
			return o
	return -1


## 등용한 사람(i)의 오늘 밤 상대에게만 —— "오늘 밤 상대 <유저>가 방금 <장수>를 데려왔습니다"
func _foe_preview(i: int, k: String) -> void:
	var o := tonight_foe(i)
	if o < 0:
		return
	var nm: String = DB.C[k].name
	var tx := "오늘 밤 상대 %s%s 방금 %s%s 데려왔습니다" % [seats[i].name, "이" if _batchim(seats[i].name) else "가", nm, "을" if _batchim(nm) else "를"]
	var it := {"who": seats[i].name, "text": tx}
	_news_add(it, null, [seats[o]])
	_announce(tx, it, null, false, [seats[o]])


## 유저전 하나가 끝날 때마다 —— 이기면 연승 +1(이번 저녁에 늘었다 표시), 지거나 비기면 0
func _streak_track(s: Dictionary, won: bool) -> void:
	if won:
		s["win_st"] = int(s.get("win_st", 0)) + 1
		s["win_new"] = true
	else:
		s["win_st"] = 0
		s["win_new"] = false


## 사람끼리 대전 —— 진 쪽의 beat_by 에 이긴 사람 이름을 적는다. 설욕(이긴 쪽이 예전에 졌던 상대)하면 지운다
func _beat_track(x: Dictionary, y: Dictionary, x_won: bool, draw: bool) -> void:
	if draw:
		return
	var w: Dictionary = x if x_won else y
	var l: Dictionary = y if x_won else x
	var lb: Array = l.get("beat_by", [])
	if not lb.has(w.name):
		lb.append(w.name)
	l["beat_by"] = lb
	var wb: Array = w.get("beat_by", [])
	wb.erase(l.name)
	w["beat_by"] = wb


## 상대 정보 + 설욕전 표시 (me 가 예전에 other 에게 졌다)
func _foe_for(me: Dictionary, other: Dictionary) -> Dictionary:
	var d := _foe_info(other)
	if other.human and (me.get("beat_by", []) as Array).has(other.name):
		d["revenge"] = true
	return d


## 연승 · 민심 위기 소식 —— 대전을 다 본 뒤라 결과가 새지 않는다. 본인에게는 보내지 않는다 (자기 화면에 이미 보인다)
func _flush_presence_news() -> void:
	var save := _news_stage
	_news_stage = "evening"
	for s in humans():
		if s.dead or s.run == null:
			continue
		var tx := ""
		if bool(s.get("win_new", false)) and int(s.get("win_st", 0)) >= STREAK_MIN:
			tx = "%s %d연승 중" % [s.name, int(s.win_st)]
		s["win_new"] = false
		var hp := int(s.run.hp)
		if hp > 0 and hp <= HP_CRISIS and s.run.over == null and not bool(s.get("hp_warn", false)):
			s["hp_warn"] = true
			var t2 := "%s 민심 %d, 위태롭습니다" % [s.name, hp]
			var it2 := {"who": s.name, "text": t2}
			_news_add(it2, s)
			_announce(t2, it2, s)
		if tx != "":
			var it := {"who": s.name, "text": tx}
			_news_add(it, s)
			_announce(tx, it, s)
	_news_stage = save


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
