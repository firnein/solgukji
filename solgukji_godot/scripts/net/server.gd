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
##   create {mode}         방 만들기 (fast · normal) —— 만든 사람이 방장
##   join {code}           코드로 들어가기
##   leave                 방에서 나가기
##   start                 방장이 시작 (빈자리는 봇)
##   cmd {m, a}            징집·조합·편성 명령 (Run.COMMANDS)
##   ready {on, sno}       준비 완료 —— sno 는 받은 방 정보의 stage_no (지난 단계의 준비는 버린다)
##   alone {go}            혼자 남았을 때의 답 —— go 가 참이면 봇만 상대로 계속, 아니면 방을 닫는다
##   say {i}               한마디 —— Room.QUICK_MSGS 의 번호 (자유 입력 없음, 2초에 한 번). 방의 모두에게 say 로 뿌린다 (11/9)
## 32KB 가 넘는 메시지는 gzip 바이너리로 보낸다.
## 보내는 것: hello {id, token} · rooms {list} · room {room} · state {run, room} · battles {list, stage, stage_no, seen} · toast {text, kind, news?} · say {who, text} · error {msg} · left
## 방 진행(아침 · 점심 · 저녁 단계)은 room.gd. 플레이 기록(사람마다 jsonl)은 room_log.gd (11/10).

const CODE_CHARS := "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"

var port := 7777
var tcp := TCPServer.new()
var peers := {}               # id -> {ws, name, token, room}
var rooms := {}               # code -> Room
var _next_id := 1
var max_msg := 0              # 점검용 —— 가장 큰 메시지 (보낸 바이트, 압축 뒤)


func _ready() -> void:
	for s in OS.get_cmdline_user_args():
		var kv := s.trim_prefix("--").split("=", true, 1)
		if kv[0] == "port" and kv.size() > 1:
			port = int(kv[1])
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
	while tcp.is_connection_available():
		var ws := WebSocketPeer.new()
		ws.inbound_buffer_size = 1 << 22
		ws.outbound_buffer_size = 1 << 24
		ws.max_queued_packets = 4096
		if ws.accept_stream(tcp.take_connection()) == OK:
			var id := _next_id
			_next_id += 1
			peers[id] = {"ws": ws, "name": "", "token": "", "room": "", "rec": false}
	for id in peers.keys():
		var p: Dictionary = peers[id]
		var ws: WebSocketPeer = p.ws
		ws.poll()
		match ws.get_ready_state():
			WebSocketPeer.STATE_OPEN:
				while ws.get_available_packet_count() > 0:
					var txt := ws.get_packet().get_string_from_utf8()
					var d = JSON.parse_string(txt)
					if typeof(d) == TYPE_DICTIONARY and d.has("t"):
						_handle(id, d)
			WebSocketPeer.STATE_CLOSED:
				_drop(id)
	for code in rooms.keys():
		var r: Room = rooms[code]
		r.tick()
		# 아무도 없는 방은 10분 뒤 (끝난 방은 1분 뒤) 지운다
		if r.empty_since > 0 and Room.now() - r.empty_since > (60.0 if r.stage == "over" else 600.0):
			rooms.erase(code)
			print("방 %s 정리" % code)
		elif not r.started and r.seats.is_empty():
			rooms.erase(code)


func send(id: int, msg: Dictionary) -> void:
	if not peers.has(id):
		return
	var ws: WebSocketPeer = peers[id].ws
	if ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
		var txt := JSON.stringify(msg, "", false, true)
		var raw := txt.to_utf8_buffer()
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
			var r := Room.new(self, code, str(d.get("mode", "fast")))
			rooms[code] = r
			p.room = code
			r.add_human(id, p.name, p.token, p.rec)
			print("%s 방 %s 만듦 (%s)" % [p.name, code, r.mode])
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
				print("방 %s 시작 — 사람 %d명" % [p.room, rooms[p.room].humans().size()])
		"cmd":
			if rooms.has(p.room):
				var a = d.get("a", [])
				rooms[p.room].on_cmd(id, str(d.get("m", "")), a if a is Array else [])
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
				"mode": r.mode, "mode_n": Room.MODES[r.mode].n})
	send(id, {"t": "rooms", "list": lst})


func _new_code() -> String:
	while true:
		var c := ""
		for i in 4:
			c += CODE_CHARS[randi() % CODE_CHARS.length()]
		if not rooms.has(c):
			return c
	return ""
