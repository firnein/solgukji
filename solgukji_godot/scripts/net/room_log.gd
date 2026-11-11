extends RefCounted
## 온라인 방 플레이 기록 (11/10 사용자: 온라인 대전도 플레이 분석할 수 있게 다른 플레이어 로그도 수집)
## 방(Room)이 시작하면 사람 플레이어마다 파일 하나를 연다 —— 서버 PC 의 user://playlog_online/<시작시각>_<방코드>_<자리번호>.jsonl
## (Windows: %APPDATA%\Godot\app_userdata\솔국지\playlog_online). 봇 자리는 파일이 없고 상대로만 적힌다.
## 형식은 혼자 하기의 PlayLog 와 같다 —— 한 줄 = {"ts","ev","day","phase",...} 라서 tools/scripts/analyze_playlog.py --logs 로 그대로 읽힌다.
##   start         판 시작 —— seed · ver · online:true · player(이름) · seat · room · mode · players(사람 이름들) · bots(봇 이름들)
##   act           사람의 명령 (Run.COMMANDS) 과 결과 —— PlayLog.act_data 와 같은 칸 + ok
##   stage         단계가 바뀜 (morning · noon · evening_prep · evening · over) —— 줄마다 "stage" 칸이 따라온다
##   ready         '준비 완료' —— sec = 단계가 시작하고 몇 초 만에
##   bot_fill      응답이 없어(단계 내내 행동이 없거나 접속이 끊겨) 봇이 그 단계를 통째로 대신함 (disconnected)
##   battle_start / battle_end   토벌 · 대전 · 토너먼트 —— PlayLog 와 같은 칸 + foe_name · foe_human(사람과 붙었나) · auto(접속이 끊겨 봇이 대신 편성한 판) · ghost/ghost_of(그림자 대전 11/11 —— 멸망한 자리 대신 산 사람의 편성 복사본과 붙은 판, foe_human 은 true)
##   (stage 칸은 계산한 때의 단계 —— 토벌은 morning 끝, 대전은 evening_prep 끝에 서버가 계산한다)
##   reward        토벌 · 대전 뒤 경고 · 민심 · 전적
##   phase_end     하루(페이즈) 끝 스냅샷 —— PlayLog 와 같은 칸 (page_sec 만 없다). sec = 아침부터 몇 초
##   disconnect / reconnect / leave   끊김 · 같은 토큰으로 돌아옴 · 스스로 나감(자리는 봇이 이어받는다 —— 이 줄이 마지막)
##   over          판 끝 —— 우승 · 순위 · 멸망
## 동의한 사람만 남긴다 (11/10 사용자: "동의를 받아야지") —— 클라이언트가 hello 에 rec:true 를 보낸 사람(방의 seat.rec)만 파일이 있다. rec 가 없거나(옛 APK) false 면 파일을 만들지 않는다.
##   기록하는 사람의 파일에도 기록 안 하는 사람의 이름 · 편성 · 행동은 넣지 않는다: start 의 players 는 동의한 사람만(안 한 사람은 hidden 숫자),
##   그 사람과 붙은 전투는 foe_name 을 "(비공개)" 로 · 상대 편성/전력비/상대 부대 기록(foe · foe_form · foe_tac · foe_morale · foe_equip · tr_ratio · foe_troops · units 의 상대 부대 · chains 의 상대)을 빼고
##   내 결과(win · 내 잔존 · 상대 잔존 비율)만 남긴다. 제목 · 전리품 출처 · over 메시지 속 그 사람 이름도 "(비공개)".
## 서버가 아는 것만 쓴다 (탭 · 배속 · 전투 중 개입은 없다). IP · 토큰은 쓰지 않는다. 이름은 방에 들어온 이름(중복이면 번호가 붙는다) 그대로.
## 기록은 부수 효과일 뿐 —— 난수도 상태도 건드리지 않고, 쓰기에 실패해도 게임은 그대로 간다 (서버 콘솔에 한 줄).

static var enabled := true
static var test_ok := false                 # 점검 방(mode=test)은 기록하지 않는다 —— tests/net · tests/room_log 가 켠다
static var dir := "user://playlog_online"
const KEEP_DAYS := 30                       # 서버를 켤 때 이보다 오래된 파일은 지운다 (purge)
const HIDDEN := "(비공개)"                 # 기록 안 하는 사람의 이름 자리
const MAX_ARGS := 6                         # 명령 인자는 이만큼 · 글자는 24자까지만 (이상한 입력이 기록을 키우지 않게)

var code := ""
var files := {}               # 자리 번호 -> FileAccess
var closed := {}              # 자리 번호 -> true (over · leave 를 적은 뒤 —— 더 쓰지 않는다)
var stage := ""
var hidden_names := []          # 기록하지 않는 사람들의 이름 (제목 · 메시지에서 가린다)
var stage_t0 := 0.0
var day_t0 := 0.0
var _warned := false


static func wanted(mode: String) -> bool:
	return enabled and (mode != "test" or test_ok)


static func _now() -> float:
	return Time.get_unix_time_from_system()


## 오래된 기록 지우기 —— 서버 시작 때. 지운 개수
static func purge() -> int:
	var n := 0
	if not DirAccess.dir_exists_absolute(dir):
		return 0
	for fn in DirAccess.get_files_at(dir):
		if not fn.ends_with(".jsonl"):
			continue
		var path := dir + "/" + fn
		var age := _now() - float(FileAccess.get_modified_time(path))
		if age > KEEP_DAYS * 86400.0 and DirAccess.remove_absolute(path) == OK:
			n += 1
	return n


## 기록 안 하는 사람의 이름을 가린다 (전투 제목 "대전 · 이름" · over 메시지 "이름을 꺾고…")
func _scrub(text: String) -> String:
	for n in hidden_names:
		if n != "":
			text = text.replace(n, HIDDEN)
	return text


func _warn(msg: String) -> void:
	if not _warned:
		_warned = true
		printerr("[기록] %s —— 게임은 그대로 진행" % msg)


## 방이 시작될 때 —— 사람마다 파일을 열고 start 줄을 적는다 (Run 들은 이미 만들어져 있어야 한다)
func open(room) -> void:
	code = room.code
	if DirAccess.make_dir_recursive_absolute(dir) != OK and not DirAccess.dir_exists_absolute(dir):
		_warn("기록 폴더를 만들지 못했다: %s" % dir)
		return
	var t := Time.get_datetime_dict_from_system()
	var stamp := "%04d%02d%02d_%02d%02d%02d" % [t.year, t.month, t.day, t.hour, t.minute, t.second]
	var humans: Array = room.humans().filter(func(s): return s.get("rec", false)).map(func(s): return s.name)
	hidden_names = room.humans().filter(func(s): return not s.get("rec", false)).map(func(s): return s.name)
	var bots: Array = room.seats.filter(func(s): return not s.human).map(func(s): return s.name)
	for i in room.seats.size():
		var s: Dictionary = room.seats[i]
		if not s.human or not s.get("rec", false):      # 동의하지 않은 사람 · 봇은 파일 없음
			continue
		var path := "%s/%s_%s_%d.jsonl" % [dir, stamp, code, i]
		var f := FileAccess.open(path, FileAccess.WRITE)
		if f == null:
			_warn("기록 파일을 열지 못했다: %s (오류 %d)" % [path, FileAccess.get_open_error()])
			continue
		files[i] = f
		put(i, s.run, "start", {"seed": str(s.run.rng.seed), "os": OS.get_name(), "ver": Changelog.version(), "online": true,
			"player": s.name, "seat": i, "room": code, "mode": room.mode, "players": humans, "hidden": hidden_names.size(), "bots": bots})
	if not files.is_empty():
		print("방 %s 기록 → %s (사람 %d명)" % [code, ProjectSettings.globalize_path(dir), files.size()])


func put(i: int, run, ev: String, data := {}) -> void:
	var f: FileAccess = files.get(i)
	if f == null or closed.has(i) or run == null:
		return
	var d := {"ts": snappedf(_now(), 0.01), "ev": ev, "day": run.day, "phase": run.phase, "stage": stage}
	d.merge(data)
	f.store_line(JSON.stringify(d))
	f.flush()


## 동의를 철회하고 돌아왔다 —— 마지막 줄을 적고 닫는다. 이 사람 이름은 이제 다른 사람 파일에서도 가려진다
func consent_off(i: int, run, name_: String) -> void:
	put(i, run, "consent_off")
	close_seat(i)
	if not hidden_names.has(name_):
		hidden_names.append(name_)


func close_seat(i: int) -> void:
	closed[i] = true
	files.erase(i)


func close_all() -> void:
	for i in files.keys():
		close_seat(i)


## 단계가 바뀔 때 —— 모든 사람의 파일에 한 줄
func on_stage(room) -> void:
	stage = room.stage
	stage_t0 = _now()
	if stage == "morning":
		day_t0 = stage_t0
	for i in files.keys():
		var s: Dictionary = room.seats[i]
		if not s.dead:
			put(i, s.run, "stage", {"no": room.stage_no, "remain": snappedf(room.stage_end - Room.now(), 0.1)})


func ready(i: int, run, on: bool) -> void:
	put(i, run, "ready", {"on": on, "sec": snappedf(_now() - stage_t0, 0.1)})


## 명령 —— 인자는 JSON 에서 온 것이라 float 정수를 int 로, 이상한 것은 잘라 쓴다
func act(i: int, run, m: String, a: Array, r) -> void:
	if not files.has(i):
		return
	var clean := []
	for x in a.slice(0, MAX_ARGS):
		if x is float and x == floorf(x):
			clean.append(int(x))
		elif x is String:
			clean.append((x as String).substr(0, 24))
		elif x is int or x is float or x is bool:
			clean.append(x)
		else:
			clean.append("?")
	var d := PlayLog.act_data(m.substr(0, 24), clean, r)
	d["ok"] = r != null and not (r is bool and not r)      # 명령이 거절되면 null · false (do_draw 같은 것은 카드 배열이 온다)
	put(i, run, "act", d)


## 전투 한 판 —— 이 사람 기준(bt.a = 나)의 bt 와 결과. foe_* 는 상대 (토벌은 적 부대 이름 · 사람 아님)
## foe_rec = 상대가 사람이면 그 사람이 기록에 동의했나 —— 아니면(foe_hidden) 상대 이름 · 편성 · 상대 부대 기록을 남기지 않는다
func battle(i: int, run, bt: Dictionary, res: Dictionary, foe_name: String, foe_human: bool, auto := false, foe_rec := true, extra := {}) -> void:
	if not files.has(i):
		return
	var hide := foe_human and not foe_rec
	var x := {"foe_name": HIDDEN if hide else foe_name, "foe_human": foe_human}
	if hide:
		x["foe_hidden"] = true
	if auto:
		x["auto"] = true
	if not extra.is_empty():      # 그림자 대전 (11/11) —— ghost: true · ghost_of: 원본 자리 이름 (원본이 기록에 동의 안 했으면 가린다)
		x.merge(extra)
		if hide and x.has("ghost_of"):
			x["ghost_of"] = HIDDEN
	var a := PlayLog.battle_start_data(bt)
	a["title"] = _scrub(str(a.title))
	if hide:
		for k in ["foe", "foe_form", "foe_tac", "foe_morale", "foe_equip", "tr_ratio"]:
			a.erase(k)
	a.merge(x)
	put(i, run, "battle_start", a)
	var b := PlayLog.battle_end_data(bt, res, 0.0, [], {})
	if hide:
		for k in ["foe_troops", "foe_troops_max"]:
			b.erase(k)
		b["units"] = (b.units as Array).filter(func(u): return u.camp == "A")
		b["chains"] = {"A": (b.chains as Dictionary).get("A", {})}
	b.merge(x)
	put(i, run, "battle_end", b)


func reward(i: int, run) -> void:
	var d := PlayLog.reward_data(run)
	if d.get("spoil") is Dictionary and (d.spoil as Dictionary).has("src"):      # 전리품 출처 "대전 · 이름"
		d.spoil = (d.spoil as Dictionary).duplicate()
		d.spoil["src"] = _scrub(str(d.spoil.src))
	put(i, run, "reward", d)


func phase_end(i: int, run, auto := false) -> void:
	if not files.has(i):
		return
	var d := {"sec": snappedf(_now() - day_t0, 0.1)}
	d.merge(PlayLog.phase_end_data(run))
	if not hidden_names.is_empty():      # 다른 자리들의 전력(bot_pv) 중 기록 안 하는 사람의 것은 뺀다
		d["bot_pv"] = run.bots.filter(func(b): return not hidden_names.has(str(b.name))).map(func(b): return int(b.pv))
	if auto:
		d["auto"] = true
	put(i, run, "phase_end", d)


func over(i: int, run) -> void:
	if not files.has(i) or run == null or run.over == null:
		return
	var d := PlayLog.over_data(run)
	d["msg"] = _scrub(str(d.msg))
	put(i, run, "over", d)
	close_seat(i)


func event(i: int, run, ev: String, data := {}) -> void:
	put(i, run, ev, data)
	if ev == "leave":
		close_seat(i)
