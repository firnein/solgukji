extends Node
const RoomLog := preload("res://scripts/net/room_log.gd")
## 서버 점검 —— 실행: godot --headless --path . res://tests/net.tscn [-- --players=4 --seats=4|6|8 --port=7791]
## 서버(MatchServer)와 가짜 플레이어 N명을 한 프로세스에 띄워 실제 WebSocket 으로 한 판을 끝까지 돈다.
## 하루 = 아침(징집 → 선택권 → 조합 → 자동 편성 → 준비) → 점심(토벌이 오면 '본 것'으로 준비) → 저녁 준비(빈 편성 채우고 준비) → 저녁(대전이 오면 준비).
## 둘째 플레이어는 2일차에 끊었다가 같은 토큰으로 돌아온다 (그동안은 봇이 대신한다).
## 점검 모드(test)는 멸망하지 않아 7일째 토너먼트까지 간다.
## 확인: 모두 끝까지 가는가 · 사람끼리 대전의 승패가 양쪽에서 맞는가 · 저녁 준비에 받은 상대와 실제 대전 상대가 같은가 ·
##       라운드로빈(11/10): 한 바퀴(자리 수 - 1 저녁) 안에 같은 상대를 두 번 만나지 않는가 · 오류 메시지가 없는가.
## 11/11 자리 수 --seats=4|6|8 (기본 8): create 에 max 를 실어 보낸다 —— 방 정보의 max · 자리 수 · 봇 수(= max - 사람 수)를 확인한다. --port= 로 포트를 바꾼다 (다른 세션과 겹치지 않게).

const DEFAULT_PORT := 7791
const LOG_DIR := "user://playlog_online_net"

var server: MatchServer
var bots := []                # [{c: NetClient, name, state, room, …}]
var code := ""
var errors := []
var pvp_seen := {}            # "day.phase" -> [[나, 상대, 승?, 무?]]
var foe_log := {}             # 이름 -> {day_no: 상대 이름}  (저녁 준비에 받은 상대)
var human_names := []
var port := DEFAULT_PORT
var seats_n := 8              # --seats —— 방의 총 인원 (create 의 max)
var n_humans := 0
var seat_checked := false
var norec := 0               # 기록에 동의하지 않은 가짜 클라이언트 수 (마지막 사람들)
var t0 := 0.0
var stage_count := {}         # 단계 이름 -> 본 횟수 (첫 플레이어 기준)


func _ready() -> void:
	var args := {}
	for s in OS.get_cmdline_user_args():
		var kv := s.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	var n := int(args.get("players", "3"))
	port = int(args.get("port", str(DEFAULT_PORT)))
	seats_n = int(args.get("seats", "8"))
	n_humans = n
	norec = int(args.get("norec", "1" if n >= 3 else "0"))      # 11/10 동의 —— 끝에서부터 이만큼은 기록에 동의하지 않은 클라이언트(hello 에 rec 없음)
	RoomLog.test_ok = true                       # 11/10 온라인 기록 —— 점검 방도 이 점검에서는 남기고 끝에 파일을 본다
	RoomLog.dir = LOG_DIR
	DirAccess.make_dir_recursive_absolute(LOG_DIR)
	for fn in DirAccess.get_files_at(LOG_DIR):
		DirAccess.remove_absolute(LOG_DIR + "/" + fn)
	server = MatchServer.new()
	server.port = port
	add_child(server)
	t0 = Time.get_ticks_msec() / 1000.0
	for i in n:
		var c := NetClient.new()
		c.player = "시험%d" % i
		c.token = ""
		c.consent_ver = NetClient.CONSENT_VER if i < n - norec else 0      # 동의한 것처럼 hello 에 rec=true / 안 한 사람은 rec=false (메모리만)
		add_child(c)
		var b := {"c": c, "name": c.player, "i": i, "state": null, "room": null, "dropped": false, "back": false, "done": false,
			"sno": -1}
		bots.append(b)
		human_names.append(c.player)
		foe_log[c.player] = {}
		c.message.connect(func(d): _on_msg(b, d))
		c.connect_to("ws://127.0.0.1:%d" % port)


func _on_msg(b: Dictionary, d: Dictionary) -> void:
	var c: NetClient = b.c
	match str(d.t):
		"error":
			errors.append("%s: %s" % [b.name, d.msg])
		"rooms":
			if b.i == 0 and code == "" and not b.has("created"):
				b.created = true
				c.send({"t": "create", "mode": "test", "max": seats_n})
			elif b.i > 0 and code != "" and b.room == null:
				c.send({"t": "join", "code": code})
		"room":
			b.room = d.room
			if b.i == 0:
				code = d.room.code
				if int(d.room.get("max", -1)) != seats_n:
					errors.append("방 정보의 max %s (기대 %d)" % [str(d.room.get("max")), seats_n])
				var hs: int = d.room.seats.filter(func(s): return s.human).size()
				if hs == bots.size() and not d.room.started:
					c.send({"t": "start"})
				elif hs == 1:
					for o in bots.slice(1):
						if o.room == null and o.c.is_open():
							o.c.send({"t": "list"})
		"state":
			b.state = d
			b.room = d.room
			var run: Dictionary = d.run
			var rm: Dictionary = d.room
			if int(rm.stage_no) != b.sno:
				b.sno = int(rm.stage_no)
				if b.i == 0:
					stage_count[rm.stage] = stage_count.get(rm.stage, 0) + 1
				# 저녁 준비 —— 받은 상대를 적어 둔다 (PV 가 실려 오면 안 된다, 결정 ⑥)
				if rm.stage == "evening_prep" and rm.get("foe") != null:
					var f: Dictionary = rm.foe
					if f.has("pv"):
						errors.append("%s: 상대 정보에 PV 가 실려 있다" % b.name)
					foe_log[b.name][int(rm.day_no)] = str(f.name)
			if not seat_checked:
				seat_checked = true
				var bn: int = rm.seats.filter(func(s): return not s.human).size()
				if rm.seats.size() != seats_n or int(rm.max) != seats_n or bn != seats_n - n_humans:
					errors.append("자리 %d · max %s · 봇 %d (기대 %d · %d · %d)" % [rm.seats.size(), str(rm.max), bn, seats_n, seats_n, seats_n - n_humans])
				print("  방 자리 %d (max %d) · 사람 %d · 봇 %d" % [rm.seats.size(), int(rm.max), n_humans, bn])
			if rm.get("alone", "") == "ask":
				c.send({"t": "alone", "go": true})
			if run.over != null and not b.done:
				b.done = true
				print("  %s 끝: %s (%s)" % [b.name, "우승" if run.over.win else "탈락", run.over.msg])
			if (rm.stage in Room.ACT_STAGES) and run.over == null:
				_play(b, run, rm)
			# 둘째는 2일차 오전에 끊었다가 1.5초 뒤 같은 토큰으로 돌아온다
			if b.i == 1 and int(run.day) == 1 and not b.dropped:
				b.dropped = true
				var tok: String = c.token
				c.close()
				print("  %s 접속 끊음 (2일차 · %s)" % [b.name, rm.stage])
				await get_tree().create_timer(1.5).timeout
				c.token = tok
				c.connect_to("ws://127.0.0.1:%d" % port)
				b.back = true
		"battles":
			var dn := int(d.day) * 3 + int(d.phase) + 1
			for x in d.list:
				var res: Dictionary = x.res
				if str(x.title) == "대전 · " + b.name or str(res.title) != str(x.title):
					errors.append("%s: 전투 제목이 이상하다 (%s / %s)" % [b.name, x.title, res.title])
				if str(x.title).begins_with("대전 · "):
					var foe := str(x.title).trim_prefix("대전 · ")
					var key := "%d.%d" % [d.day, d.phase]
					if not pvp_seen.has(key):
						pvp_seen[key] = []
					pvp_seen[key].append([b.name, foe, res.win, res.draw])
					# 저녁 준비에 받은 상대와 같은가 (끊겨 있던 동안은 못 받았을 수 있다)
					if foe_log[b.name].has(dn) and foe_log[b.name][dn] != foe:
						errors.append("%s: %d일차 저녁 상대가 다르다 (준비 때 %s · 대전 %s)" % [b.name, dn, foe_log[b.name][dn], foe])
					foe_log[b.name][dn] = foe
			if not bool(d.get("seen", false)):
				c.send({"t": "ready", "on": true, "sno": int(d.stage_no)})


## 아침 · 저녁 준비에 할 일 —— 상태가 올 때마다 다음 한 걸음
func _play(b: Dictionary, run: Dictionary, room: Dictionary) -> void:
	var c: NetClient = b.c
	if room.stage == "morning":
		if not run.drawn and int(DB.D.DRAWS[int(run.day)]) > 0:
			c.send({"t": "cmd", "m": "do_draw", "a": []})
			return
		if not run.picked:
			c.send({"t": "cmd", "m": "begin_picks", "a": ["phase", -1]})
			return
		var tk: Dictionary = run.get("tickets", {})
		var tt: Array = tk.keys().filter(func(x): return int(tk[x]) > 0)
		if not tt.is_empty():
			var pl: Array = DB.by_tier(int(tt[0]))
			pl.sort_custom(func(x, y): return DB.C[x].tr > DB.C[y].tr)
			c.send({"t": "cmd", "m": "pick", "a": [pl[b.i % mini(6, pl.size())]]})
			return
		# 조합할 수 있으면 높은 등급부터 하나씩
		var r := Run.new()
		r.from_dict(run.duplicate(true))
		for t in range(8, 1, -1):
			for k in DB.by_tier(t):
				if r.can_forge(k):
					c.send({"t": "cmd", "m": "forge", "a": [k]})
					return
	var key := "%d.%d.%s" % [run.day, run.phase, room.stage]
	if not b.has("deployed_at") or b.deployed_at != key:
		b.deployed_at = key
		c.send({"t": "cmd", "m": "auto_deploy", "a": []})
		return
	var me: Dictionary = room.seats[room.you]
	if not me.ready:
		c.send({"t": "ready", "on": true, "sno": int(room.stage_no)})


func _process(_dt: float) -> void:
	var el := Time.get_ticks_msec() / 1000.0 - t0
	var all_done := not bots.is_empty() and bots.all(func(b): return b.done)
	if all_done or el > 300.0:
		_report(el, all_done)
		set_process(false)
		get_tree().quit()


func _report(el: float, all_done: bool) -> void:
	for key in pvp_seen:
		for x in pvp_seen[key]:
			for y in pvp_seen[key]:
				if x[0] == y[1] and y[0] == x[1] and not x[3] and x[2] == y[2]:
					errors.append("%s 대전 승패가 양쪽에서 같다: %s vs %s" % [key, x, y])
	var pairs := 0
	for key in pvp_seen:
		pairs += pvp_seen[key].filter(func(x): return pvp_seen[key].any(func(y): return y[0] == x[1])).size()
	# 상대 선정 규칙 (11/10 라운드로빈) —— 저녁 7번이 한 바퀴: 같은 바퀴 안에서 같은 상대를 두 번 만나면 안 된다 (토너먼트 21일차는 뺀다)
	var hh := 0
	var repeat := 0
	var seen_n := 0
	for nm in foe_log:
		var fl: Dictionary = foe_log[nm]
		var per_cycle := {}      # 바퀴 번호 -> {상대: 횟수}
		for dn in fl:
			if int(dn) > 20:
				continue
			if fl[dn] in human_names:
				hh += 1
			seen_n += 1
			var cy := (int(dn) - 1) / (seats_n - 1)
			if not per_cycle.has(cy):
				per_cycle[cy] = {}
			per_cycle[cy][fl[dn]] = int(per_cycle[cy].get(fl[dn], 0)) + 1
		for cy in per_cycle:
			for foe in per_cycle[cy]:
				if per_cycle[cy][foe] > 1:
					repeat += 1
					errors.append("%s: %d번째 바퀴에 %s 를 %d번 만났다" % [nm, cy + 1, foe, per_cycle[cy][foe]])
	_check_logs()
	print("서버 점검 %.1f초 · 모두 끝 %s · 사람끼리 대전 %d건(양쪽 집계) · 재접속 %s · 오류 %d" % [el, all_done, pairs,
		bots.size() > 1 and bots[1].back, errors.size()])
	print("  단계 횟수(첫 플레이어): %s" % str(stage_count))
	print("  저녁 상대 %d건 중 사람 %d건 · 같은 바퀴 안에서 같은 상대를 두 번 만난 건수 %d" % [seen_n, hh, repeat])
	print("  가장 큰 메시지 %.0f KB" % (server.max_msg / 1024.0))
	for e in errors.slice(0, 10):
		print("  ", e)


## 온라인 기록 (11/10) —— 사람 수만큼 파일 · 줄마다 올바른 JSON · 이름 · 토큰 없음 (over 줄은 tests/room_log.tscn -- --full 이 본다 —— 이 점검의 가짜 플레이어는 첫 대전 패배 때 끝낸다)
func _check_logs() -> void:
	var files := Array(DirAccess.get_files_at(LOG_DIR)).filter(func(f): return f.ends_with(".jsonl"))
	var lines_n := 0
	var kinds := {}
	var overs := 0
	var bad := 0
	var names := []
	var hh := 0
	var hidden := 0
	for fn in files:
		var lines := FileAccess.get_file_as_string(LOG_DIR + "/" + fn).split("\n", false)
		lines_n += lines.size()
		var last = null
		for ln in lines:
			var d = JSON.parse_string(ln)
			if typeof(d) != TYPE_DICTIONARY or not d.has("ev"):
				bad += 1
				continue
			last = d
			kinds[d.ev] = int(kinds.get(d.ev, 0)) + 1
			if d.ev == "start":
				names.append(d.get("player", ""))
			if d.ev == "battle_end" and d.get("foe_human", false):
				hh += 1
				if d.get("foe_hidden", false):
					hidden += 1
					if d.has("foe_troops") or d.has("foe_troops_max") or (d.units as Array).any(func(u): return u.camp != "A"):
						errors.append("동의 안 한 상대의 부대 기록이 남았다: %s" % fn)
			for c in bots:
				if ln.contains(c.c.token) and c.c.token != "":
					errors.append("기록에 토큰이 있다: %s" % fn)
		if last != null and last.ev == "over":
			overs += 1
	if files.size() != bots.size() - norec:
		errors.append("기록 파일 %d개 (동의한 사람 %d명)" % [files.size(), bots.size() - norec])
	if bad > 0:
		errors.append("올바르지 않은 기록 줄 %d" % bad)
	for nm in human_names:
		var agreed: bool = human_names.find(nm) < human_names.size() - norec
		if agreed and not names.has(nm):
			errors.append("기록에 이름 %s 가 없다" % nm)
		if not agreed:      # 동의 안 한 사람 —— 이름 · 편성이 어느 파일에도 없다
			if names.has(nm):
				errors.append("동의 안 한 %s 의 파일이 만들어졌다" % nm)
			for fn in files:
				if FileAccess.get_file_as_string(LOG_DIR + "/" + fn).contains(nm):
					errors.append("%s: 동의 안 한 %s 의 이름이 기록에 있다" % [fn, nm])
	print("  온라인 기록: 파일 %d개 · %d줄 · 끝 줄 있는 것 %d · 사람끼리 대전 줄 %d (그중 상대가 동의 안 한 사람 %d) · 줄 종류 %s" % [files.size(), lines_n, overs, hh, hidden, str(kinds)])
