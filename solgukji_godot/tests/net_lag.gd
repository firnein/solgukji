extends Node
## 11/21 온라인 지연 실측 —— 서버는 따로 띄운다 (server.bat 처럼 다른 포트, 재려면 -- --lagstat). 실행:
##   godot --headless --path . res://tests/net_lag.tscn -- --url=ws://127.0.0.1:7787 --mode=ping --n=60
##   godot --headless --path . res://tests/net_lag.tscn -- --url=ws://127.0.0.1:7787 --mode=game --players=2 --phases=3
## ping: 방 목록(list → rooms) 왕복 n번 —— 전송 + 서버 한 바퀴의 바닥 지연 (wss:// Funnel 주소면 바깥 중계 포함).
##       hello 를 보내지 않는다 (사용자 서버에 대고 재도 방 · 기록 · 접속 줄이 생기지 않는다)
## game: 사람 N명이 방(빠른 · 8자리 = 봇 8-N)을 만들어 실제 휴대폰처럼 명령을 보낸다 —— 아침: 징집 → 선택권 → 모두 조합(한꺼번에 여러 개) → 자동 편성 → 군략 → 준비.
##       잰다: 명령 → 그 번호(ack)가 실린 상태까지 왕복 · 명령 묶음 하나에 받은 상태 수와 바이트 · 마지막 준비 → 다음 단계 상태 · 전투(battles) 도착 ·
##       판 내내 100ms 마다 list 를 보내 서버가 멈춘 구간(왕복이 튀는 곳)
##       --spec=1 이면 11/21 관전: 먼저 다 본 사람이 spec_list 를 받고 spectate 로 진행 중인 사람 전투를 받는지 본다
## 결과는 "NETLAG|" 줄

var url := "ws://127.0.0.1:7787"
var mode := "ping"
var lanes := []               # [{ws, i, name, ...}]
var t_start := 0
var phases := 3
var players := 2
var spec_test := false
var noact := false            # --noact: 아침에 명령 없이 바로 준비 (11/21 봇 대행 자리로 찍혀 전투 단계가 시간을 다 채우던 것)
var code := ""
var out := {}                 # 이름 -> [값...] (ms)
var notes := []
var errors := []


class Lane:
	var ws := WebSocketPeer.new()
	var i := 0
	var st := -1
	var q := 0                       # 보낸 명령 번호
	var sent := {}                   # q -> [보낸 시각 us, 명령]
	var pings := []                  # list 를 보낸 시각 us (차례대로 돌아온다)
	var next_ping := 0
	var run: Dictionary = {}
	var room: Dictionary = {}
	var sno := -1
	var phase_key := ""
	var step := ""                   # 아침 진행 단계
	var burst_q := 0                 # 모두 조합 묶음의 마지막 번호
	var burst_n := 0
	var states_since_burst := 0
	var bytes_since_burst := 0
	var ready_sent := false
	var ready_t := 0
	var ready_acked := true
	var stage_t := 0
	var watch_wait := -1             # 전투를 받고 준비를 보낼 시각 us
	var in_game := false
	var mornings := 0
	var done := false
	var spec_got := false            # 관전 목록을 받았나
	var spec_play := false           # 관전 전투를 받았나

	func send(d: Dictionary) -> void:
		if ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
			ws.send_text(JSON.stringify(d))


func _ready() -> void:
	var args := {}
	for s in OS.get_cmdline_user_args():
		var kv := s.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	url = str(args.get("url", url))
	mode = str(args.get("mode", mode))
	phases = int(args.get("phases", "3"))
	players = int(args.get("players", "2"))
	spec_test = args.has("spec")
	noact = args.has("noact")
	var n := 1 if mode == "ping" else players
	for i in n:
		var l := Lane.new()
		l.i = i
		l.ws.inbound_buffer_size = 1 << 24
		l.ws.outbound_buffer_size = 1 << 20
		l.ws.max_queued_packets = 4096
		l.ws.connect_to_url(url)
		lanes.append(l)
	t_start = Time.get_ticks_usec()
	if mode == "ping":
		_ping_mode(int(args.get("n", "60")))
	get_tree().create_timer(float(args.get("limit", "600"))).timeout.connect(func():
		errors.append("시간 초과")
		_report())


func _add(k: String, ms: float) -> void:
	if not out.has(k):
		out[k] = []
	out[k].append(ms)


func _now() -> int:
	return Time.get_ticks_usec()


# ───────── ping ─────────

func _ping_mode(n: int) -> void:
	var l: Lane = lanes[0]
	while l.ws.get_ready_state() != WebSocketPeer.STATE_OPEN:
		l.ws.poll()
		if l.ws.get_ready_state() == WebSocketPeer.STATE_CLOSED:
			errors.append("접속 실패 %s" % url)
			_report()
			return
		await get_tree().process_frame
	_add("connect", (_now() - t_start) / 1000.0)
	for k in n:
		var t0 := _now()
		l.send({"t": "list"})
		var got := false
		while not got:
			l.ws.poll()
			while l.ws.get_available_packet_count() > 0:
				var pkt := l.ws.get_packet()
				if not l.ws.was_string_packet():
					pkt = pkt.decompress_dynamic(-1, FileAccess.COMPRESSION_GZIP)
				var d = JSON.parse_string(pkt.get_string_from_utf8())
				if d is Dictionary and str(d.get("t")) == "rooms":
					got = true
			if l.ws.get_ready_state() == WebSocketPeer.STATE_CLOSED:
				errors.append("끊김")
				_report()
				return
			if not got:
				await get_tree().process_frame
		_add("ping", (_now() - t0) / 1000.0)
		await get_tree().create_timer(0.05).timeout
	_report()


# ───────── game ─────────

func _process(_dt: float) -> void:
	if mode != "game":
		return
	var now := _now()
	for l: Lane in lanes:
		l.ws.poll()
		var s := l.ws.get_ready_state()
		if s != l.st:
			l.st = s
			if s == WebSocketPeer.STATE_OPEN:
				l.send({"t": "hello", "name": "지연%d" % l.i, "token": "", "rec": false})
			elif s == WebSocketPeer.STATE_CLOSED and not l.done:
				errors.append("%d 끊김" % l.i)
		while l.ws.get_available_packet_count() > 0:
			var pkt := l.ws.get_packet()
			var sz := pkt.size()
			if not l.ws.was_string_packet():
				pkt = pkt.decompress_dynamic(-1, FileAccess.COMPRESSION_GZIP)
			var d = JSON.parse_string(pkt.get_string_from_utf8())
			if d is Dictionary:
				_on_msg(l, d, sz)
		# 판 내내 100ms 마다 list —— 서버가 바쁘면 왕복이 튄다
		if l.in_game and not l.done and now >= l.next_ping:
			l.next_ping = now + 100000
			l.pings.append(now)
			l.send({"t": "list"})
		if l.watch_wait > 0 and now >= l.watch_wait:
			l.watch_wait = -1
			_send_ready(l)
	if not lanes.is_empty() and lanes.all(func(x): return x.done):
		_report()


func _cmd(l: Lane, m: String, a: Array) -> int:
	l.q += 1
	l.sent[l.q] = [_now(), m]
	l.send({"t": "cmd", "m": m, "a": a, "q": l.q})
	return l.q


func _send_ready(l: Lane) -> void:
	l.ready_sent = true
	l.ready_acked = false
	l.ready_t = _now()
	l.send({"t": "ready", "on": true, "sno": int(l.room.get("stage_no", -1))})


func _on_msg(l: Lane, d: Dictionary, sz: int) -> void:
	var now := _now()
	match str(d.t):
		"hello":
			if l.i == 0:
				l.send({"t": "create", "mode": "fast", "max": 8})
		"rooms":
			if not l.pings.is_empty() and l.in_game:
				var t0: int = l.pings.pop_front()
				_add("ping_ingame", (now - t0) / 1000.0)
				_add("ping_" + str(l.room.get("stage", "?")), (now - t0) / 1000.0)
			elif l.i > 0 and code != "" and l.room.is_empty():
				l.send({"t": "join", "code": code})
		"room":
			l.room = d.room
			if l.i == 0:
				code = str(d.room.code)
				var hs: int = d.room.seats.filter(func(x): return x.human).size()
				if hs == players and not d.room.started:
					l.send({"t": "start"})
				elif hs < players:
					for o: Lane in lanes.slice(1):
						if o.room.is_empty():
							o.send({"t": "join", "code": code})
		"error":
			notes.append("%d 오류: %s" % [l.i, d.msg])
		"spec_list":
			if not (d.get("list", []) as Array).is_empty() and not l.spec_got:
				l.spec_got = true
				_add("spec_list_after_ready", (now - l.ready_t) / 1000.0)
				var it: Dictionary = d.list[0]
				l.send({"t": "spectate", "id": str(it.id)})
				l.set_meta("spec_t", now)
		"spec":
			if not l.spec_play:
				l.spec_play = true
				_add("spec_rtt", (now - int(l.get_meta("spec_t", now))) / 1000.0)
				notes.append("%d 관전 받음: %s · %.1f초부터 · 사건 %d" % [l.i, str(d.get("title", "")), float(d.get("at", 0.0)), (d.get("res", {}).get("ev", []) as Array).size()])
		"battles":
			_add("battles_after_ready", (now - l.ready_t) / 1000.0 if l.ready_t > 0 else -1.0)
			_add("battles_after_stage", (now - l.stage_t) / 1000.0)
			_add("battles_kb", sz / 1000.0)
			if not bool(d.get("seen", false)):
				# 앞 사람은 0.5초 · 뒤 사람은 길게(관전 점검이면 8초) 보고 준비 —— 마지막 준비 → 다음 단계까지를 잰다
				var wait := 0.5 if l.i == 0 else (8.0 if spec_test else 2.0)
				l.watch_wait = now + int(wait * 1000000.0)
				l.ready_sent = false
		"state":
			l.in_game = true
			l.run = d.run
			var prev_sno := l.sno
			l.room = d.room
			_add("state_kb", sz / 1000.0)
			var ack := int(d.get("ack", -1))
			for q in l.sent.keys():
				if int(q) <= ack:
					_add("rtt_" + str(l.sent[q][1]), (now - int(l.sent[q][0])) / 1000.0)
					_add("rtt_all", (now - int(l.sent[q][0])) / 1000.0)
					l.sent.erase(q)
			if l.burst_q > 0:
				l.states_since_burst += 1
				l.bytes_since_burst += sz
				if ack >= l.burst_q:
					_add("burst_rtt_last", (now - l.get_meta("burst_t", now)) / 1000.0)
					_add("burst_states", l.states_since_burst)
					_add("burst_kb", l.bytes_since_burst / 1000.0)
					notes.append("%d 모두 조합 %d개 → 상태 %d개 · %.1fKB · 마지막 ack 까지 %.0fms" % [l.i, l.burst_n, l.states_since_burst, l.bytes_since_burst / 1000.0, (now - l.get_meta("burst_t", now)) / 1000.0])
					l.burst_q = 0
			var my_seat: Dictionary = l.room.seats[int(l.room.you)] if int(l.room.get("you", -1)) >= 0 else {}
			if not l.ready_acked and (bool(my_seat.get("ready", false)) or int(l.room.get("stage_no", -1)) != prev_sno):
				l.ready_acked = true
				_add("ready_ack", (now - l.ready_t) / 1000.0)      # 준비 → 서버가 내 준비를 알린 상태 (버튼이 바뀌는 때)
			var sno := int(l.room.get("stage_no", -1))
			if sno != prev_sno:
				l.sno = sno
				l.stage_t = now
				if l.ready_sent and l.ready_t > 0:
					_add("stage_after_ready", (now - l.ready_t) / 1000.0)
				l.ready_sent = false
				l.step = ""
				if str(l.room.stage) == "morning":
					l.mornings += 1
					if l.mornings > phases:
						l.done = true
						return
				if str(l.room.stage) == "over":
					l.done = true
					return
			if l.run.get("over") != null:
				l.done = true
				return
			_play(l)


## 아침 · 저녁 준비에 할 일 —— 상태가 올 때마다 다음 한 걸음 (휴대폰처럼 먼저 내 쪽에서 해 보고 보낸다)
func _play(l: Lane) -> void:
	var rm := l.room
	if not (str(rm.get("stage", "")) in Room.ACT_STAGES) or l.ready_sent or not l.sent.is_empty():
		return
	var run := l.run
	if noact and rm.stage == "morning":
		var me0: Dictionary = rm.seats[int(rm.you)]
		if not bool(me0.ready):
			_send_ready(l)
		return
	if rm.stage == "morning":
		if not run.drawn and int(DB.D.DRAWS[mini(int(run.day), 6)]) > 0:
			_cmd(l, "do_draw", [])
			return
		if not run.picked:
			_cmd(l, "begin_picks", ["phase", -1])
			return
		var tk: Dictionary = run.get("tickets", {})
		var tt: Array = tk.keys().filter(func(x): return int(tk[x]) > 0)
		if not tt.is_empty():
			var pl: Array = DB.by_tier(int(tt[0]))
			pl.sort_custom(func(x, y): return DB.C[x].tr > DB.C[y].tr)
			_cmd(l, "pick", [pl[l.i % mini(6, pl.size())]])
			return
		if l.step == "":
			# 모두 조합 —— 휴대폰의 act_quiet 처럼 내 쪽에서 차례로 조합해 보고 명령을 한꺼번에 보낸다
			l.step = "forged"
			var r := Run.new()
			r.from_dict(run.duplicate(true))
			var n := 0
			var more := true
			while more and n < 12:
				more = false
				for t in range(8, 1, -1):
					for k in DB.by_tier(t):
						if n < 12 and r.can_forge(k):
							r.command("forge", [k])
							l.burst_q = _cmd(l, "forge", [k])
							n += 1
							more = true
			if n > 0:
				l.burst_n = n
				l.states_since_burst = 0
				l.bytes_since_burst = 0
				l.set_meta("burst_t", _now())
				return
		if l.step == "forged":
			l.step = "deployed"
			_cmd(l, "auto_deploy", [])
			return
	if l.step != "planned":
		l.step = "planned"
		var tp: Array = run.get("tk_plan", [])
		if tp.size() == 3:
			_cmd(l, "set_plan", [0, ["돌격", "우회", "방진"][l.i % 3]])
			return
	var me: Dictionary = rm.seats[int(rm.you)]
	if not bool(me.ready):
		_send_ready(l)


func _pct(a: Array, p: float) -> float:
	var s := a.duplicate()
	s.sort()
	return float(s[clampi(int(round((s.size() - 1) * p)), 0, s.size() - 1)])


var _reported := false


func _report() -> void:
	if _reported:
		return
	_reported = true
	var keys := out.keys()
	keys.sort()
	for k in keys:
		var a: Array = out[k]
		var tot := 0.0
		for v in a:
			tot += float(v)
		print("NETLAG|%s|n=%d|avg=%.1f|p50=%.1f|p90=%.1f|max=%.1f" % [k, a.size(), tot / a.size(), _pct(a, 0.5), _pct(a, 0.9), _pct(a, 1.0)])
	for nt in notes.slice(0, 30):
		print("NETLAG|note|" + str(nt))
	if spec_test:
		var got := lanes.any(func(x): return x.spec_got)
		var play := lanes.any(func(x): return x.spec_play)
		print("NETLAG|spec|목록 %s · 재생 %s" % [got, play])
		if not (got and play):
			errors.append("관전 목록 %s · 관전 재생 %s" % [got, play])
	for e in errors:
		print("NETLAG|error|" + str(e))
	for l: Lane in lanes:
		l.ws.close()
	get_tree().quit(0 if errors.is_empty() else 1)
