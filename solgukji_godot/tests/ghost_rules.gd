extends Node
const RoomLog := preload("res://scripts/net/room_log.gd")
## 그림자 대전 규칙 점검 (11/11 사용자) —— 가짜 서버로 Room 을 직접 돌린다 (소켓 없음, 포트 없음).
## 실행: godot --headless --path . res://tests/ghost_rules.tscn
## 멸망한 사람의 짝이던 산 사람 C 는 떠돌이 군세 대신 다른 산 사람 X 의 '그림자'(X 의 잠긴 편성 복사본)와 싸운다.
## ① 짝이 [C, -1 - d, X] · C 의 상대 이름이 "<X>의 그림자" · 전투 params 의 상대 편성 = X 의 편성 · 제목 · foe 에 "그림자"
## ② C 가 이기면 C 전적 +1 승, 지면 +1 패 · 민심 깎임 (사람과의 대전과 같다) — X 는 자기 진짜 상대와의 전투 결과만 반영 (그림자 때문에 전적 · 민심 · 경고가 바뀌지 않는다), X 의 편성 불변
## ③ X 자신의 저녁 상대(foe)와 전투는 그대로 (진짜 상대)
## ④ 소식은 C · X 에게만 (다음 날 아침을 열 때) —— "…의 그림자에게 승리/패배" · "…당신의 그림자와 싸워 …" · 제3자에게는 없다
## ⑤ 산 사람이 C 하나뿐(또는 나머지가 떠난 자리)이면 전처럼 떠돌이 군세 · 봇은 그림자를 만나지 않는다
## ⑥ 플레이 기록(RoomLog)의 battle_start 에 ghost: true · ghost_of: X 이름

const LOG_DIR := "user://playlog_online_ghost"
var fails := []
var seen_win := false
var seen_loss := false


class FakeSrv:
	var out := []        # [peer, msg]
	func send(peer: int, msg: Dictionary) -> void:
		out.append([peer, msg.duplicate(true)])
	func of(peer: int, t: String) -> Array:
		return out.filter(func(o): return o[0] == peer and o[1].t == t).map(func(o): return o[1])


func _ready() -> void:
	_clear_logs()
	var n_ok := 0
	var seed_ := 100
	while n_ok < 12 and seed_ < 124 and not (seen_win and seen_loss and n_ok >= 3):
		if _round(seed_, seed_ % 3, seed_ % 4 == 0):
			n_ok += 1
		seed_ += 1
	if not seen_win or not seen_loss:
		print("(주의) 이긴 경우 %s · 진 경우 %s 를 모두 보지 못했다 — 씨앗을 늘려 보세요" % [str(seen_win), str(seen_loss)])
	_alone_cases()
	_clear_logs()
	RoomLog.test_ok = false
	RoomLog.dir = "user://playlog_online"
	print("FAIL: ", fails if not fails.is_empty() else "없음")
	get_tree().quit(1 if not fails.is_empty() else 0)


func _fail(s: String) -> void:
	if fails.size() < 14:
		fails.append(s)


func _clear_logs() -> void:
	DirAccess.make_dir_recursive_absolute(LOG_DIR)
	for fn in DirAccess.get_files_at(LOG_DIR):
		DirAccess.remove_absolute(LOG_DIR + "/" + fn)


func _mk(n_seats: int, humans_n: int, seed_: int, log_on := false) -> Array:
	RoomLog.test_ok = log_on
	RoomLog.dir = LOG_DIR
	var srv := FakeSrv.new()
	var r := Room.new(srv, "GHOST", "test", n_seats)
	r.rng.seed = seed_
	for i in humans_n:
		r.add_human(i + 1, "사람%d" % (i + 1), "tk%d" % i, true)
	r.start()
	return [r, srv]


## 사람 4명(4석) 방에서 한 명을 멸망시키고 ev 번째 저녁까지 돌려, 그림자 대전이 낀 저녁 하나를 점검한다. 점검한 경우 true
func _round(seed_: int, dead_i_: int, log_on: bool) -> bool:
	if log_on:
		_clear_logs()
	var mk := _mk(4, 4, seed_, log_on)
	var r: Room = mk[0]
	var srv: FakeSrv = mk[1]
	var dead_i := dead_i_
	r.seats[dead_i].dead = true
	for s in r.humans():
		if not s.dead:
			r._fill(s)
	r.day = seed_ % 2
	r.phase = (seed_ / 2) % 3
	r._begin_evening()
	var tri := r.pairs.filter(func(p): return p.size() > 2)
	if tri.size() != 1:
		_fail("[씨앗 %d] 그림자 짝이 %d 개 (기대 1) %s" % [seed_, tri.size(), str(r.pairs)])
		return false
	var p: Array = tri[0]
	var ci: int = p[0]
	var xi: int = p[2]
	if p[1] != -1 - dead_i or xi == ci or r.seats[xi].dead or not r.seats[xi].human or r.seats[ci].dead:
		_fail("[씨앗 %d] 그림자 짝이 이상하다 %s (멸망 %d)" % [seed_, str(p), dead_i])
		return false
	var c: Dictionary = r.seats[ci]
	var x: Dictionary = r.seats[xi]
	var rc: Run = c.run
	var rx: Run = x.run
	var shadow_name := "%s의 그림자" % x.name
	# ① 저녁 준비의 상대 표시
	if c.foe == null or c.foe.name != shadow_name or c.foe.epi != Room.SHADOW_EPI or c.foe.human:
		_fail("[씨앗 %d] C 의 상대 표시 %s (기대 %s)" % [seed_, str(c.foe), shadow_name])
	var row: Dictionary = r.info(ci).seats[ci]
	if row.foe != shadow_name or r.info(ci).foe.name != shadow_name:
		_fail("[씨앗 %d] info 의 foe 가 그림자 이름이 아니다 (%s)" % [seed_, str(row.foe)])
	if x.foe == null or str(x.foe.name).contains("그림자"):
		_fail("[씨앗 %d] X 의 상대가 그림자로 바뀌었다 (%s)" % [seed_, str(x.foe)])
	var x_foe_name: String = x.foe.name
	# 스냅샷
	var c0 := {"hp": rc.hp, "w": rc.my_w, "l": rc.my_l, "strikes": rc.strikes}
	var x0 := {"hp": rx.hp, "w": rx.my_w, "l": rx.my_l, "strikes": rx.strikes, "board": rx.board.duplicate(true), "form": rx.form, "equip": rx.equip.duplicate(true), "tac": rx.tac}
	var x_board: Array = rx.board.duplicate()
	var x_form = rx.form
	var third := -1
	for i in 4:
		if i != ci and i != xi and i != dead_i:
			third = i
	# 계산
	r.stage_end = 0.0
	r._end_prep()
	if c.battles.size() != 1:
		_fail("[씨앗 %d] C 의 전투가 %d 개" % [seed_, c.battles.size()])
		return false
	var cb: Dictionary = c.battles[0]
	var pr: Dictionary = cb.params
	if not str(cb.title).contains("그림자") or not str(pr.title).contains("그림자") or pr.foe != shadow_name or not str(cb.res.get("title", cb.title)).contains("그림자"):
		_fail("[씨앗 %d] 전투 제목 · foe 에 그림자 이름이 없다 (%s / %s)" % [seed_, str(cb.title), str(pr.foe)])
	if pr.b != x_board or pr.fb != x_form:
		_fail("[씨앗 %d] 그림자의 편성이 X 의 편성과 다르다" % seed_)
	# C 정산 —— 사람과의 대전과 같다
	var win: bool = bool(cb.res.win)
	if win:
		seen_win = true
		if rc.my_w != c0.w + 1 or rc.my_l != c0.l or rc.hp != c0.hp:
			_fail("[씨앗 %d] C 승리인데 전적 %d-%d · 민심 %s (이전 %s)" % [seed_, rc.my_w, rc.my_l, str(rc.hp), str(c0)])
	else:
		seen_loss = true
		if rc.my_l != c0.l + 1 or rc.my_w != c0.w or not (rc.hp < c0.hp):
			_fail("[씨앗 %d] C 패배인데 전적 %d-%d · 민심 %s (이전 %s)" % [seed_, rc.my_w, rc.my_l, str(rc.hp), str(c0)])
	if rc.strikes != c0.strikes:
		_fail("[씨앗 %d] 대전으로 C 경고가 바뀜" % seed_)
	if not str(rc.last_spoil.get("src", "")).contains("그림자") or int(rc.last_spoil.get("n", 0)) != int(DB.D.PVP_BASE.win):
		_fail("[씨앗 %d] C 보상 기록 이상 %s" % [seed_, str(rc.last_spoil)])
	# X —— 자기 진짜 상대와의 전투 결과만 반영 (그림자 때문에 바뀐 것 없음)
	if x.battles.size() != 1 or str(x.battles[0].title).contains("그림자") or x.battles[0].params.foe != x_foe_name:
		_fail("[씨앗 %d] X 자신의 전투가 바뀌었다 (%s)" % [seed_, str(x.battles.map(func(b): return b.title))])
	else:
		var xw: bool = bool(x.battles[0].res.win)
		if rx.my_w != x0.w + (1 if xw else 0) or rx.my_l != x0.l + (0 if xw else 1):
			_fail("[씨앗 %d] X 전적이 자기 전투(%s)와 다르다: %d-%d (이전 %d-%d)" % [seed_, "승" if xw else "패", rx.my_w, rx.my_l, x0.w, x0.l])
		if xw and rx.hp != x0.hp:
			_fail("[씨앗 %d] X 가 자기 전투에 이겼는데 민심이 바뀜 (%s → %s)" % [seed_, str(x0.hp), str(rx.hp)])
		if rx.strikes != x0.strikes:
			_fail("[씨앗 %d] X 의 경고가 바뀜" % seed_)
	if rx.board != x0.board or rx.form != x0.form or rx.equip != x0.equip or rx.tac != x0.tac:
		_fail("[씨앗 %d] X 의 편성이 바뀌었다 (그림자 계산이 원본을 건드림)" % seed_)
	# 소식 —— 아직 안 보냈다 (결과가 새지 않게 다음 날 아침에)
	var pre_news := srv.out.filter(func(o): return o[1].t == "news" and str(o[1].list[0].get("text", "")).contains("그림자"))
	if not pre_news.is_empty():
		_fail("[씨앗 %d] 대전을 보기 전에 그림자 소식이 갔다" % seed_)
	var xn0: int = rx.news.size()
	var cn0: int = rc.news.size()
	var tn0: int = r.seats[third].run.news.size()
	srv.out.clear()
	r.stage_end = 0.0
	r.tick()      # evening → 다음 날 아침 (_advance)
	var res_t := "무승부" if cb.res.get("draw", false) else ("승리" if win else "패배")
	var cmsgs := srv.of(ci + 1, "news").filter(func(m): return str(m.list[0].text).contains("그림자"))
	var xmsgs := srv.of(xi + 1, "news").filter(func(m): return str(m.list[0].text).contains("그림자"))
	var tmsgs := srv.of(third + 1, "news").filter(func(m): return str(m.list[0].text).contains("그림자"))
	if cmsgs.size() != 1 or not str(cmsgs[0].list[0].text).contains(shadow_name + "에게 " + res_t) or not str(cmsgs[0].list[0].text).contains(c.name):
		_fail("[씨앗 %d] C 의 소식 %s (기대 …%s에게 %s)" % [seed_, str(cmsgs.map(func(m): return m.list[0].text)), shadow_name, res_t])
	if xmsgs.size() != 1 or not str(xmsgs[0].list[0].text).contains("당신의 그림자와 싸워 " + res_t) or not str(xmsgs[0].list[0].text).contains(c.name):
		_fail("[씨앗 %d] X 의 소식 %s" % [seed_, str(xmsgs.map(func(m): return m.list[0].text))])
	if not tmsgs.is_empty():
		_fail("[씨앗 %d] 제3자에게 그림자 소식이 갔다" % seed_)
	var want_when := "%d일차 %s" % [seed_ % 2 + 1, Run.PHASE_N[(seed_ / 2) % 3]]
	for m in cmsgs + xmsgs:
		var it: Dictionary = m.list[0]
		if not it.has("id") or str(it.get("when", "")) != want_when + "" and not str(it.get("when", "")).begins_with(want_when):
			_fail("[씨앗 %d] 소식 id · 시점 이상 %s (기대 %s)" % [seed_, str(it), want_when])
	if rc.news.size() <= cn0 or rx.news.size() <= xn0 or r.seats[third].run.news.size() != tn0:
		_fail("[씨앗 %d] Run.news 반영(C %d→%d · X %d→%d · 제3자 %d→%d)" % [seed_, cn0, rc.news.size(), xn0, rx.news.size(), tn0, r.seats[third].run.news.size()])
	if r._shadow_news.size() != 0:
		_fail("소식 대기열이 비지 않았다")
	# ⑥ 기록
	if r.rlog != null:
		r.rlog.close_all()
		_check_log(seed_, ci, xi, c.name, x.name, shadow_name)
		r.rlog = null
	print("[씨앗 %d] 멸망 %s · C=%s vs 그림자(%s) → C %s · X 의 진짜 상대 %s%s" % [seed_, r.seats[dead_i].name, c.name, x.name, res_t, x_foe_name, " · 기록 확인" if log_on else ""])
	return true


func _check_log(seed_: int, ci: int, xi: int, cname: String, xname: String, shadow_name: String) -> void:
	var found := 0
	var x_ghost := 0
	for fn in DirAccess.get_files_at(LOG_DIR):
		if not fn.ends_with(".jsonl"):
			continue
		var is_c := fn.ends_with("_%d.jsonl" % ci)
		var is_x := fn.ends_with("_%d.jsonl" % xi)
		for ln in FileAccess.get_file_as_string(LOG_DIR + "/" + fn).split("\n", false):
			var d = JSON.parse_string(ln)
			if typeof(d) != TYPE_DICTIONARY:
				continue
			if d.get("ev", "") == "battle_start":
				if d.get("ghost", false):
					if is_c:
						found += 1
						if d.get("ghost_of", "") != xname or d.get("foe_name", "") != shadow_name or d.get("foe_human", false) != true:
							_fail("[씨앗 %d] 기록 ghost 칸 이상 %s" % [seed_, ln.substr(0, 200)])
					if is_x:
						x_ghost += 1
	if found != 1:
		_fail("[씨앗 %d] C 기록에 ghost battle_start 가 %d 개" % [seed_, found])
	if x_ghost != 0:
		_fail("[씨앗 %d] X 기록에 그림자 전투가 있다" % seed_)


## 산 사람이 하나뿐이거나 나머지가 떠난 자리 · 봇은 그림자를 만나지 않는다 —— 전처럼 떠돌이 군세
func _alone_cases() -> void:
	# (a) 사람 2 + 봇 2, 한 명 멸망 —— 남은 사람 A 는 다른 산 사람이 없다
	var mk := _mk(4, 2, 7)
	var r: Room = mk[0]
	r.seats[1].dead = true
	_fill_all(r)
	var ghosts := 0
	for er in 6:
		r.day = er / 3
		r.phase = er % 3
		r._begin_evening()
		for p in r.pairs:
			if p.size() > 2:
				_fail("[혼자] 산 사람이 하나뿐인데 그림자 짝 %s" % str(p))
		if r.seats[0].foe != null and r.seats[0].foe.epi == "떠돌이 군세":
			ghosts += 1
	if ghosts == 0:
		_fail("[혼자] 6 저녁 동안 유랑군과 한 번도 안 붙었다")
	# (b) 사람 3 + 봇 1 —— 한 명 멸망, 한 명은 자리를 떠남(token 없음): A 는 그림자 원본이 없다 (떠난 자리는 봇이 대신 — 원본 아님)
	mk = _mk(4, 3, 8)
	r = mk[0]
	r.seats[2].dead = true
	r.seats[1].token = ""
	_fill_all(r)
	for er in 6:
		r.day = er / 3
		r.phase = er % 3
		r._begin_evening()
		for p in r.pairs:
			if p.size() > 2:
				_fail("[떠난 자리] 떠난 사람을 원본으로 그림자 짝이 생겼다 %s" % str(p))
	# (c) 사람 3 + 봇 1, 한 명 멸망 —— 봇이 그림자를 만나지 않는다 (짝에서 봇 자리가 셋째 칸의 주인이 되지 않는다) · 6 저녁 중 사람은 모두 한 번 이상 그림자를 만난다
	mk = _mk(4, 3, 9)
	r = mk[0]
	r.seats[2].dead = true
	_fill_all(r)
	var met := {}
	for er in 6:
		r.day = er / 3
		r.phase = er % 3
		r._begin_evening()
		for p in r.pairs:
			if p.size() > 2:
				if not r.seats[p[0]].human:
					_fail("[봇] 봇 자리 %d 가 그림자와 붙는다 %s" % [p[0], str(p)])
				met[p[0]] = int(met.get(p[0], 0)) + 1
	print("혼자 · 떠난 자리 · 봇 점검 끝 (사람 3명 방 6 저녁: 그림자 대전 %s)" % str(met))
	if met.size() != 2:
		_fail("[봇] 산 사람 둘이 모두 그림자와 붙어야 한다 %s" % str(met))


func _fill_all(r: Room) -> void:
	for s in r.humans():
		if not s.dead:
			r._fill(s)
