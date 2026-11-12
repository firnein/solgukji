extends Node
const RoomLog := preload("res://scripts/net/room_log.gd")
## 서버 점검 —— 실행: godot --headless --path . res://tests/net.tscn [-- --players=4 --seats=4|6|8 --port=7791]
## 서버(MatchServer)와 가짜 플레이어 N명을 한 프로세스에 띄워 실제 WebSocket 으로 한 판을 끝까지 돈다.
## 하루 = 아침(징집 → 선택권 → 조합 → 자동 편성 → 준비) → 점심(토벌이 오면 '본 것'으로 준비) → 저녁 준비(빈 편성 채우고 준비) → 저녁(대전이 오면 준비).
## 둘째 플레이어는 2일차에 끊었다가 같은 토큰으로 돌아온다 (그동안은 봇이 대신한다).
## 점검 모드(test)는 7일차까지 멸망하지 않고, 8일차부터 민심이 바닥난 세력이 무너져 최후 1인이 남으면 끝난다 (11/12 토너먼트 없음).
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
var info_rows := 0            # 확인한 사람 자리 줄 수 (hp · key, 11/11)
var end_day := 0              # 11/12 판이 끝난 일차
var winner := ""
var watch_cmds := 0           # 11/11 기다리는 단계(점심 · 저녁)에 보낸 명령 수 (첫 플레이어만 —— 나머지는 옛 클라이언트처럼 준비 단계에서만 보낸다)
var form_denied := 0          # 11/12 기다리는 동안 보낸 편성이 이유와 함께 거부된 수
var act_checked := 0
var act_st_n := 0             # 11/12 받은 상태 아이콘 메시지 수          # 방 정보 act · noon 을 확인한 상태 수


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
		"act_st":      # 11/12 상태 아이콘 —— 자리 수만큼, 알려진 값만
			act_st_n += 1
			if (d.st as Array).size() != seats_n or (d.st as Array).any(func(x): return not (str(x) in ["", "busy", "quest", "pvp", "idle", "ready"])):
				errors.append("%s: act_st 이상 %s" % [b.name, str(d.st)])
		"error":
			if int(b.get("want_err", 0)) > 0 and str(d.msg).contains("편성"):      # 11/12 기다리는 동안의 편성 —— 거부되어야 맞다
				b.want_err = int(b.want_err) - 1
				form_denied += 1
			else:
				errors.append("%s: %s (%s · %s일차)" % [b.name, d.msg, str(b.room.get("stage", "")) if b.room != null else "", str(int(b.room.get("day", -1)) + 1) if b.room != null else ""])
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
				# 11/11 점심(토벌)은 1~3일차만 · 방 정보 noon / act 가 규칙과 맞는가
				if rm.stage == "noon" and int(rm.day) >= Run.ONLINE_NOON_DAYS:
					errors.append("%s: %d일차에 점심 단계가 왔다" % [b.name, int(rm.day) + 1])
				if bool(rm.get("noon", true)) != (int(rm.day) < Run.ONLINE_NOON_DAYS):
					errors.append("%s: 방 정보 noon %s (일차 %d)" % [b.name, str(rm.get("noon")), int(rm.day) + 1])
				if run.over == null and rm.stage != "over":
					# 11/12 페이즈 개편: 아침 = 징집 · 편성, 저녁 준비 = 편성만, 점심 · 저녁 = 편성 불가 (징집 · 조합은 다 본 뒤)
					var want_draw: bool = rm.stage == "morning"
					var want_form: bool = rm.stage in Room.ACT_STAGES
					act_checked += 1
					if not rm.has("act") or bool(rm.get("act_form")) != want_form or (not (rm.stage in Room.WATCH_STAGES) and bool(rm.get("act_draw")) != want_draw):
						errors.append("%s: 방 정보 act %s · 징집 %s · 편성 %s (%s)" % [b.name, str(rm.get("act")), str(rm.get("act_draw")), str(rm.get("act_form")), rm.stage])
				# 저녁 준비 —— 받은 상대를 적어 둔다 (PV 가 실려 오면 안 된다, 결정 ⑥)
				if rm.stage == "evening_prep" and rm.get("foe") != null:
					var f: Dictionary = rm.foe
					if f.has("pv"):
						errors.append("%s: 상대 정보에 PV 가 실려 있다" % b.name)
					foe_log[b.name][int(rm.day_no)] = str(f.name)
			# 첫 플레이어는 전투를 다 본 뒤 기다리는 동안 징집을 한다 (새 클라이언트) · 편성은 거부되어야 한다
			if b.i == 0 and run.over == null and (rm.stage in Room.WATCH_STAGES) and bool(rm.get("act_draw", false)) and int(b.get("wcmd_no", -1)) != int(rm.stage_no):
				b.wcmd_no = int(rm.stage_no)
				watch_cmds += 1
				c.send({"t": "cmd", "m": "do_draw", "a": []})
				c.send({"t": "cmd", "m": "auto_deploy", "a": []})
				b["want_err"] = int(b.get("want_err", 0)) + 1
			# 11/11 기록 탭 —— 사람 자리마다 hp · key(기초불신 id 만), 봇에는 없다, 그 밖의 키는 허용 목록 안에서만 (실제 WebSocket 으로 온 줄)
			for sr in rm.seats:
				for sk in sr:
					if not (sk in ["name", "human", "online", "ready", "dead", "pv", "foe", "hp", "key", "st", "rank"]):      # st = 11/12 지금 하는 일 (사람 자리) · rank = 11/12 최종 순위
						errors.append("%s: 자리 줄에 허용되지 않은 키 %s" % [b.name, sk])
				if bool(sr.human):
					if not (sr.has("hp") and sr.has("key")):
						errors.append("%s: 사람 자리 줄에 hp · key 가 없다" % b.name)
					else:
						info_rows += 1
						for kc in sr.key:
							if not Room.is_urgent_unit(str(kc)):
								errors.append("%s: key 에 기초불신이 아닌 카드 %s" % [b.name, kc])
				elif sr.has("key") or not sr.has("hp"):
					errors.append("%s: 봇 자리 줄에 key 가 있거나 hp 가 없다 (11/12 봇도 민심)" % b.name)
			if not seat_checked:
				seat_checked = true
				var bn: int = rm.seats.filter(func(s): return not s.human).size()
				if rm.seats.size() != seats_n or int(rm.max) != seats_n or bn != seats_n - n_humans:
					errors.append("자리 %d · max %s · 봇 %d (기대 %d · %d · %d)" % [rm.seats.size(), str(rm.max), bn, seats_n, seats_n, seats_n - n_humans])
				print("  방 자리 %d (max %d) · 사람 %d · 봇 %d" % [rm.seats.size(), int(rm.max), n_humans, bn])
			if rm.get("alone", "") == "ask":
				c.send({"t": "alone", "go": true})
			# 11/11 온라인 대전 패배 민심 ×1.0 —— 점검 모드는 7일차까지 민심이 바닥나도 멸망하지 않고 다음 날 아침에 over 가 지워진다(일시적). 방 over 만 끝으로 센다
			if rm.stage == "over" and not b.done:
				b.done = true
				if run.over == null:
					errors.append("%s: 판이 끝났는데 over 가 없다" % b.name)
				else:
					print("  %s 끝: %s · %s위 (%s) · %d일차" % [b.name, "천하 통일" if run.over.win else "멸망", str(run.over.get("rank", "?")), run.over.msg, int(run.day) + 1])
					if not run.over.has("rank"):
						errors.append("%s: over 에 rank 가 없다" % b.name)
				var alive_n: int = rm.seats.filter(func(x): return not bool(x.dead)).size()
				if b.i == 0:
					end_day = int(rm.day) + 1
					winner = str(rm.get("winner", ""))
					print("  판 끝 —— %d일차 · 천하 통일 %s · 남은 자리 %d" % [end_day, winner, alive_n])
					if alive_n != 1 or winner == "":
						errors.append("최후 1인이 아니다 (남은 자리 %d · winner %s)" % [alive_n, winner])
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
		if not run.drawn and int(DB.D.DRAWS[mini(int(run.day), 6)]) > 0:
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
	if room.stage in Room.ACT_STAGES and (not b.has("deployed_at") or b.deployed_at != key):      # 11/12 편성은 아침 · 저녁 준비에만
		b.deployed_at = key
		c.send({"t": "cmd", "m": "auto_deploy", "a": []})
		return
	var me: Dictionary = room.seats[room.you]
	if not me.ready:
		c.send({"t": "ready", "on": true, "sno": int(room.stage_no)})


func _process(_dt: float) -> void:
	var el := Time.get_ticks_msec() / 1000.0 - t0
	var all_done := not bots.is_empty() and bots.all(func(b): return b.done)
	if all_done or el > 480.0:
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
	# 상대 선정 규칙 (11/10 라운드로빈) —— 저녁 7번이 한 바퀴: 같은 바퀴 안에서 같은 상대를 두 번 만나면 안 된다 (멸망이 없는 1~7일차 = 21저녁만 —— 8일차부터는 남은 세력끼리 다시 짠다)
	var hh := 0
	var repeat := 0
	var seen_n := 0
	for nm in foe_log:
		var fl: Dictionary = foe_log[nm]
		var per_cycle := {}      # 바퀴 번호 -> {상대: 횟수}
		for dn in fl:
			if int(dn) > 21:
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
	print("  기다리는 단계 명령 %d번 (편성 거부 %d번) · 방 정보 act · noon 확인 %d번" % [watch_cmds, form_denied, act_checked])
	if all_done and (watch_cmds == 0 or form_denied == 0):      # 단계가 막 넘어가면 명령이 다음 단계에 닿을 수 있어 수가 꼭 같지는 않다
		errors.append("기다리는 동안 징집 %d번 · 편성 거부 %d번" % [watch_cmds, form_denied])
	if all_done and int(stage_count.get("noon", 0)) != 9:
		errors.append("점심(토벌) 단계가 %d번 (기대 9 = 1~3일차 × 3페이즈)" % int(stage_count.get("noon", 0)))
	if all_done and (int(stage_count.get("morning", 0)) < 22 or int(stage_count.get("evening_prep", 0)) < 22):
		errors.append("준비 %d번 · 대전 준비 %d번 (기대 22 이상 —— 7일이 지나도 이어진다)" % [int(stage_count.get("morning", 0)), int(stage_count.get("evening_prep", 0))])
	print("  끝난 일차 %d · 천하 통일 %s" % [end_day, winner])
	print("  상태 아이콘(act_st) %d번 받음" % act_st_n)
	if all_done and act_st_n == 0:
		errors.append("act_st 를 한 번도 받지 못했다")
	print("  사람 자리 줄 %d개 확인 (hp · key 있음 · 기초불신 id 만 · 봇 줄에는 없음)" % info_rows)
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
