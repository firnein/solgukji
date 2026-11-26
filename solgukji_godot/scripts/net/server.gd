class_name MatchServer
extends Node
const RoomLog := preload("res://scripts/net/room_log.gd")      # 11/10 class_name 캐시(.godot)와 무관하게 (낡은 캐시에서 "RoomLog not declared")
## 대전 서버 —— 집 PC 에서 화면 없이 띄운다: server.bat (godot --headless … res://scenes/server.tscn -- --port=7777)
## WebSocket 으로 휴대폰을 받는다. 메시지는 JSON 한 줄 {"t": 종류, …}.
##
## 받는 것 (휴대폰 → 서버)
##   hello {name, token, rec}   첫 인사. token 이 진행 중인 방의 자리와 맞으면 그 자리로 돌아간다.
##                         rec = 플레이 기록 동의 (11/10) —— true 인 사람만 서버가 기록한다 (RoomLog). 없으면(옛 APK) 접속은 되지만 기록하지 않는다
##   list                  열린 방 목록
##   create {mode, max}    방 만들기 (fast · normal) —— 만든 사람이 방장. max = 총 인원(자리 수) 4 · 6 · 8 (11/11, 없거나 이상하면 8 — 옛 APK). 시작할 때 빈자리만 봇
##                         11/12 claim = 장수 선점제(없으면 켜짐) · deaths = 장수 사망룰 인원 3 · 5 · 10 (없거나 0 이면 끔). 방 정보에 claim · deaths · dead_units
##                         11/13 sell = 유닛 판매 · 군량 상점(없으면 켜짐). 방 정보에 sell
##                         11/26 hp = 패배 민심 피해 배율 0.5 · 1 · 1.5 · 2 (없으면 1). 방 정보에 hp
##   join {code}           코드로 들어가기
##   leave                 방에서 나가기
##   start                 방장이 시작 (빈자리는 봇)
##   cmd {m, a}            징집·조합·편성 명령 (Run.COMMANDS) —— 준비 단계(아침 · 저녁 준비) + 전투를 보는 단계(점심 · 저녁, 토너먼트 저녁 제외, 11/11). 방 정보의 act 가 지금 받는지 알려 준다
##   ready {on, sno}       준비 완료 —— sno 는 받은 방 정보의 stage_no (지난 단계의 준비는 버린다)
##   alone {go}            혼자 남았을 때의 답 —— go 가 참이면 봇만 상대로 계속, 아니면 방을 닫는다
##   say {i}               한마디 —— Room.QUICK_MSGS 의 번호 (자유 입력 없음, 2초에 한 번). 방의 모두에게 say 로 뿌린다 (11/9)
##   emote {i}             한마디 이모티콘 —— 0 ~ Room.EMOTE_N-1 번호만 (글과 같은 2초 간격). 방의 모두에게 {"t":"emote","who","i"} (11/10)
##   spectate {id}         11/21 관전 —— spec_list 의 id("자리:번호"). 내 전투를 다 본 사람만. 답: spec {id, who, foe, title, kind, res, params, at(그 사람이 보기 시작한 뒤 초), stage_no}
##                         spec_list {list: [{id, who, foe, kind, title, at}], stage_no} 은 보는 단계에서 다 본 사람에게 목록이 바뀔 때마다 온다
## 32KB 가 넘는 메시지는 gzip 바이너리로 보낸다.
## 보내는 것: hello {id, token} · rooms {list} · room {room} · state {run, room} · battles {list, stage, stage_no, seen} · toast {text, kind, news?} · say {who, text} · error {msg} · left
## 방 정보(room)에 11/11 추가: noon(이 일차에 점심 단계가 있나 — 4일차부터 false) · act(지금 cmd 를 받나). 없으면(옛 서버) 클라이언트가 점심 있음 · 준비 단계만으로 본다.
## 방 진행(아침 · 점심 · 저녁 단계)은 room.gd. 플레이 기록(사람마다 jsonl)은 room_log.gd (11/10).

const CODE_CHARS := "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"

var port := 7777
var tcp := TCPServer.new()
var peers := {}               # id -> {ws, name, token, room}
var rooms := {}               # code -> Room
var _next_id := 1
var max_msg := 0              # 점검용 —— 가장 큰 메시지 (보낸 바이트, 압축 뒤)
## 11/21 지연 실측 —— --lagstat 을 주면 5초마다 서버 한 프레임 · 메시지 처리 · 보낸 양을 한 줄로 찍는다 (tests/net_lag 와 짝). 없으면 재지 않는다
var lagstat := false
var _ls := {}                 # 종류 -> [횟수, 합 us, 최대 us] (h:받은 메시지 처리 · s:보낸 메시지 바이트 · f:프레임 · tick)
var _ls_t := 0
var _ls_frame := 0
## 11/21 상태 모아 보내기 —— 받은 메시지를 처리하는 동안(_batch) Room.push 는 자리마다 한 번으로 모았다가 처리가 끝나면 그때의 최신 상태를 한 번 보낸다.
## 모두 조합(명령 여러 개가 한 번에 옴)마다 상태(5KB)가 명령 수만큼 가서 휴대폰이 그만큼 화면을 다시 짓던 것 (측정: 조합 6개 → 상태 6개 · 29KB).
## 다른 종류의 메시지를 그 사람에게 보내기 전에는 모아 둔 상태를 먼저 보낸다 (순서 유지 —— 상태 다음에 전투 · 알림)
var _batch := false
var _st_q := {}               # peer -> [Room, 자리 Dictionary]


func _ready() -> void:
	for s in OS.get_cmdline_user_args():
		var kv := s.trim_prefix("--").split("=", true, 1)
		if kv[0] == "port" and kv.size() > 1:
			port = int(kv[1])
		elif kv[0] == "lagstat":
			lagstat = true
	var err := tcp.listen(port, "*")
	if err != OK:
		printerr("포트 %d 을(를) 열지 못했다 (%s) — 다른 프로그램이 쓰고 있지 않은지 확인" % [port, error_string(err)])
		get_tree().quit(1)
		return
	var gone := RoomLog.purge()      # 온라인 플레이 기록(RoomLog.dir) 중 RoomLog.KEEP_DAYS 일 넘은 것 정리 (11/10)
	print("플레이 기록 폴더: %s%s" % [ProjectSettings.globalize_path(RoomLog.dir), (" — 오래된 기록 %d개 지움" % gone) if gone > 0 else ""])
	print("솔국지 서버 — 포트 %d 에서 기다리는 중. 휴대폰에서 ws://<이 PC 주소>:%d 로 접속" % [port, port])
	for a in IP.get_local_addresses():
		if a.count(".") == 3 and not a.begins_with("127.") and not a.begins_with("169.254."):
			print("  이 PC 주소 후보: ws://%s:%d" % [a, port])


func _process(_dt: float) -> void:
	var f0 := Time.get_ticks_usec() if lagstat else 0
	if lagstat and _ls_frame > 0:
		_ls_add("gap", f0 - _ls_frame)      # 프레임 사이 간격 (서버가 얼마나 자주 소켓을 보나)
	while tcp.is_connection_available():
		var ws := WebSocketPeer.new()
		ws.inbound_buffer_size = 1 << 22
		ws.outbound_buffer_size = 1 << 24
		ws.max_queued_packets = 4096
		ws.heartbeat_interval = 15.0      # 11/11 반쯤 끊긴 연결(휴대폰이 잠들어 소켓만 남음)을 ping 으로 빨리 알아챈다 —— 끊김을 알아야 방이 그 사람을 기다리지 않는다
		if ws.accept_stream(tcp.take_connection()) == OK:
			var id := _next_id
			_next_id += 1
			peers[id] = {"ws": ws, "name": "", "token": "", "room": "", "rec": false}
	_batch = true
	for id in peers.keys():
		if not peers.has(id):
			continue
		var p: Dictionary = peers[id]
		var ws: WebSocketPeer = p.ws
		ws.poll()
		match ws.get_ready_state():
			WebSocketPeer.STATE_OPEN:
				while ws.get_available_packet_count() > 0:
					var txt := ws.get_packet().get_string_from_utf8()
					var d = JSON.parse_string(txt)
					if typeof(d) == TYPE_DICTIONARY and d.has("t"):
						var h0 := Time.get_ticks_usec() if lagstat else 0
						_handle(id, d)
						if lagstat:
							_ls_add("h:" + str(d.t) + (":" + str(d.get("m", "")) if d.t == "cmd" else ""), Time.get_ticks_usec() - h0)
			WebSocketPeer.STATE_CLOSED:
				_drop(id)
	_batch = false
	flush_states()
	for code in rooms.keys():
		var r: Room = rooms[code]
		var k0 := Time.get_ticks_usec() if lagstat else 0
		r.tick()
		if lagstat:
			var k := Time.get_ticks_usec() - k0
			if k > 1000:
				_ls_add("tick", k)
		# 아무도 없는 방은 10분 뒤 (끝난 방은 1분 뒤) 지운다
		if r.empty_since > 0 and Room.now() - r.empty_since > (60.0 if r.stage == "over" else 600.0):
			rooms.erase(code)
			print("방 %s 정리" % code)
		elif not r.started and r.seats.is_empty():
			rooms.erase(code)
	if lagstat:
		var now_us := Time.get_ticks_usec()
		_ls_add("frame", now_us - f0)
		_ls_frame = now_us
		if now_us - _ls_t > 5000000:
			_ls_t = now_us
			var parts := []
			for k in _ls:
				var v: Array = _ls[k]
				parts.append("%s n%d avg%.1f max%.1f" % [k, v[0], v[1] / 1000.0 / maxf(1, v[0]), v[2] / 1000.0])      # ms (s:* 는 KB)
			print("LAGSTAT|" + " | ".join(parts))
			_ls.clear()


func _ls_add(k: String, us: int) -> void:
	var v: Array = _ls.get(k, [0, 0, 0])
	v[0] += 1
	v[1] += us
	v[2] = maxi(v[2], us)
	_ls[k] = v


## Room.push 가 묻는다 —— 지금 모으는 중이면 맡아 두고 true (같은 사람의 앞선 것은 덮는다: 보낼 때 그때의 최신 상태를 짓는다)
func queue_state(peer: int, room: Room, seat: Dictionary) -> bool:
	if not _batch:
		return false
	_st_q[peer] = [room, seat]
	return true


func batching() -> bool:
	return _batch


## 모아 둔 상태를 보낸다
func flush_states() -> void:
	while not _st_q.is_empty():
		var peer: int = _st_q.keys()[0]
		var e: Array = _st_q[peer]
		_st_q.erase(peer)
		(e[0] as Room).push_now(e[1])


func send(id: int, msg: Dictionary) -> void:
	if _st_q.has(id) and str(msg.get("t", "")) != "state":
		var e: Array = _st_q[id]      # 이 사람에게 모아 둔 상태가 있으면 먼저 (상태 → 전투 · 알림 순서를 지킨다)
		_st_q.erase(id)
		(e[0] as Room).push_now(e[1])
	if not peers.has(id):
		return
	var ws: WebSocketPeer = peers[id].ws
	if ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
		var j0 := Time.get_ticks_usec() if lagstat else 0
		var txt := JSON.stringify(msg, "", false, true)
		var raw := txt.to_utf8_buffer()
		if lagstat:
			_ls_add("s:" + str(msg.get("t", "")), raw.size())
			_ls_add("json", Time.get_ticks_usec() - j0)
		if raw.size() > 32768:
			# 큰 메시지(전투 결과)는 gzip 으로 줄여 바이너리로 보낸다 —— 받는 쪽이 풀어 쓴다
			var z := raw.compress(FileAccess.COMPRESSION_GZIP)
			max_msg = maxi(max_msg, z.size())
			ws.put_packet(z)
		else:
			max_msg = maxi(max_msg, raw.size())
			ws.send_text(txt)


func _drop(id: int) -> void:
	var p: Dictionary = peers[id]
	if rooms.has(p.room):
		rooms[p.room].remove_peer(id)
	peers.erase(id)
	if p.name != "":
		print("%s 접속 끊김" % p.name)


func _handle(id: int, d: Dictionary) -> void:
	var p: Dictionary = peers[id]
	match str(d.t):
		"hello":
			p.name = str(d.get("name", "무명")).substr(0, 12)
			p.token = str(d.get("token", ""))
			p.rec = typeof(d.get("rec")) == TYPE_BOOL and d.rec      # 기록 동의 —— 참(true)일 때만. 없거나 다른 값이면 기록하지 않는다
			if p.token == "":
				p.token = "%d%d" % [Time.get_ticks_usec(), randi()]
			send(id, {"t": "hello", "id": id, "token": p.token})
			print("%s 접속" % p.name)
			# 진행 중인 방에 자리가 있으면 돌아간다
			for code in rooms:
				if rooms[code].reattach(id, p.token, p.rec):
					p.room = code
					print("  %s → 방 %s 로 돌아감" % [p.name, code])
					return
			_send_rooms(id)
		"list":
			_send_rooms(id)
		"create":
			_leave(id)
			var code := _new_code()
			var r := Room.new(self, code, str(d.get("mode", "fast")), d.get("max", Room.SEATS), d.get("claim", true), d.get("deaths", 0), d.get("sell", true), d.get("hp", 1.0))
			rooms[code] = r
			p.room = code
			r.add_human(id, p.name, p.token, p.rec)
			print("%s 방 %s 만듦 (%s · %d명 · 선점제 %s · 사망 %d · 판매 %s · 민심 ×%s)" % [p.name, code, r.mode, r.max_seats, "켜짐" if r.claim_on else "꺼짐", r.death_n, "켜짐" if r.sell_on else "꺼짐", str(r.hp_mul)])
		"join":
			var code := str(d.get("code", "")).to_upper().strip_edges()
			if not rooms.has(code):
				send(id, {"t": "error", "msg": "그런 방이 없다: %s" % code})
				return
			var r: Room = rooms[code]
			# 11/9 사용자: 다른 방에 있다가 들어가면 먼저 나간다 (진행 중이던 방은 자리를 봇에게). 이미 들어 있는 방이면 그 자리로 그대로
			if p.room != "" and p.room != code:
				_leave(id)
			if r.reattach(id, p.token, p.rec):
				p.room = code
				return
			_leave(id)
			if r.add_human(id, p.name, p.token, p.rec) < 0:
				send(id, {"t": "error", "msg": "이미 시작했거나 자리가 없다"})
				return
			p.room = code
			print("%s 방 %s 참가" % [p.name, code])
		"leave":
			_leave(id)
			send(id, {"t": "left"})
			_send_rooms(id)
		"start":
			if rooms.has(p.room) and rooms[p.room].host == id:
				rooms[p.room].start()
				print("방 %s 시작 — 사람 %d명 + 봇 %d (총 %d명)" % [p.room, rooms[p.room].humans().size(), rooms[p.room].max_seats - rooms[p.room].humans().size(), rooms[p.room].max_seats])
		"cmd":
			if rooms.has(p.room):
				var a = d.get("a", [])
				rooms[p.room].on_cmd(id, str(d.get("m", "")), a if a is Array else [], int(d.get("q", -1)))
		"ready":
			if rooms.has(p.room):
				rooms[p.room].on_ready(id, bool(d.get("on", true)), int(d.get("sno", -1)))
		"alone":
			if rooms.has(p.room):
				rooms[p.room].on_alone(id, bool(d.get("go", true)))
		"say":
			# 11/9 사용자: 한마디 —— 미리 적힌 글(Room.QUICK)의 번호. 방이 2초에 한 번으로 거른다
			if rooms.has(p.room):
				rooms[p.room].on_say(id, int(d.get("i", -1)))
		"emote":
			# 11/10 사용자: 한마디 이모티콘 —— 번호만. 범위 · 간격은 방이 거른다
			if rooms.has(p.room):
				rooms[p.room].on_emote(id, int(d.get("i", -1)))
		"perf":
			# 11/19 전투 프레임 실측 —— 클라이언트가 전투 하나를 본 뒤 보내는 요약. 기록만 한다 (11/21 kind "net" = 왕복 · 상태 처리 실측)
			if rooms.has(p.room) and d.get("d") is Dictionary:
				rooms[p.room].on_perf(id, d.d)
		"spectate":
			# 11/21 관전 —— 내 전투를 다 본 뒤 다른 사람(사람이 낀) 전투를 받아 재생. 판정과 무관
			if rooms.has(p.room):
				rooms[p.room].on_spectate(id, str(d.get("id", "")))


func _leave(id: int) -> void:
	var p: Dictionary = peers[id]
	if rooms.has(p.room):
		# 진행 중인 방에서 스스로 나가면 자리를 봇에게 넘기고 토큰을 끊는다 (Room.on_leave)
		rooms[p.room].on_leave(id)
	p.room = ""


func _send_rooms(id: int) -> void:
	var lst := []
	for code in rooms:
		var r: Room = rooms[code]
		if not r.started:
			lst.append({"code": code, "host": r.seats[0].name if not r.seats.is_empty() else "", "n": r.humans().size(),
				"max": r.max_seats, "mode": r.mode, "mode_n": Room.MODES[r.mode].n})
	send(id, {"t": "rooms", "list": lst})


func _new_code() -> String:
	while true:
		var c := ""
		for i in 4:
			c += CODE_CHARS[randi() % CODE_CHARS.length()]
		if not rooms.has(c):
			return c
	return ""
