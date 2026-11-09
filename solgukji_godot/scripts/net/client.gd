class_name NetClient
extends Node
## 서버 접속 —— WebSocket 하나. 받은 JSON 은 message 신호로 넘긴다.
## 주소·이름·토큰은 user://net.cfg 에 남겨 다음에 그대로 쓴다 (토큰이 있으면 진행 중인 방으로 돌아간다).

signal opened
signal closed
signal message(d: Dictionary)

const CFG := "user://net.cfg"

var ws := WebSocketPeer.new()
var url := "ws://127.0.0.1:7777"
var player := ""
var token := ""
var _state := WebSocketPeer.STATE_CLOSED


func _init() -> void:
	var cf := ConfigFile.new()
	if cf.load(CFG) == OK:
		url = cf.get_value("net", "url", url)
		player = cf.get_value("net", "name", "")
		token = cf.get_value("net", "token", "")


func save_cfg() -> void:
	var cf := ConfigFile.new()
	cf.set_value("net", "url", url)
	cf.set_value("net", "name", player)
	cf.set_value("net", "token", token)
	cf.save(CFG)


func connect_to(u: String) -> Error:
	url = u.strip_edges()
	if not url.contains("://"):
		url = "ws://" + url
	if url.begins_with("ws://") and url.count(":") < 2:      # wss:// (터널) 은 443 기본 포트 그대로
		url += ":7777"
	ws = WebSocketPeer.new()
	ws.inbound_buffer_size = 1 << 24      # 전투 결과(사건 수백 개)를 통째로 받는다
	ws.outbound_buffer_size = 1 << 20
	ws.max_queued_packets = 4096
	save_cfg()
	return ws.connect_to_url(url)


func is_open() -> bool:
	return ws.get_ready_state() == WebSocketPeer.STATE_OPEN


func send(d: Dictionary) -> void:
	if is_open():
		ws.send_text(JSON.stringify(d, "", false, true))


func close() -> void:
	ws.close()


func _process(_dt: float) -> void:
	ws.poll()
	var st := ws.get_ready_state()
	if st != _state:
		_state = st
		if st == WebSocketPeer.STATE_OPEN:
			send({"t": "hello", "name": player, "token": token})
			opened.emit()
		elif st == WebSocketPeer.STATE_CLOSED:
			closed.emit()
	while st == WebSocketPeer.STATE_OPEN and ws.get_available_packet_count() > 0:
		var pkt := ws.get_packet()
		if not ws.was_string_packet():
			pkt = pkt.decompress_dynamic(-1, FileAccess.COMPRESSION_GZIP)     # 큰 메시지는 gzip
		var d = JSON.parse_string(pkt.get_string_from_utf8())
		if typeof(d) == TYPE_DICTIONARY:
			if d.get("t") == "hello":
				token = str(d.token)
				save_cfg()
			message.emit(d)
