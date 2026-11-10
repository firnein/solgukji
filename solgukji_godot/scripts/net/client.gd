class_name NetClient
extends Node
## 서버 접속 —— WebSocket 하나. 받은 JSON 은 message 신호로 넘긴다.
## 주소·이름·토큰은 user://net.cfg 에 남겨 다음에 그대로 쓴다 (토큰이 있으면 진행 중인 방으로 돌아간다).

signal opened
signal closed
signal message(d: Dictionary)

const CFG := "user://net.cfg"
## 11/10 플레이 기록 동의 —— 서버가 이름 · 행동 · 전투 결과를 저장해도 되는지. 문구(Online.CONSENT_TEXT)가 바뀌면 이 번호를 올린다 → 모두에게 다시 묻는다.
const CONSENT_VER := 1

var ws := WebSocketPeer.new()
var url := "ws://127.0.0.1:7777"
var player := ""
var token := ""
var consent_ver := 0            # 동의한 문구 번호 (0 = 동의 없음). 동의 안 한 채로는 접속하지 않는다 (Online) —— hello 의 rec 로 서버에 알린다
var _write_consent := false     # set_consent 가 쓸 때만 true —— 그 밖의 save_cfg 는 파일에 있던 동의를 그대로 둔다 (점검 · 개발 인자가 메모리에서 정한 동의가 기기에 남지 않게)
var _state := WebSocketPeer.STATE_CLOSED


func _init() -> void:
	var cf := ConfigFile.new()
	if cf.load(CFG) == OK:
		url = cf.get_value("net", "url", url)
		player = cf.get_value("net", "name", "")
		token = cf.get_value("net", "token", "")
		if int(cf.get_value("net", "consent", 0)) == 1:
			consent_ver = int(cf.get_value("net", "consent_ver", 0))


## 지금 문구에 동의했나 —— 문구가 바뀌어 번호가 올랐으면 다시 받아야 한다
func consented() -> bool:
	return consent_ver == CONSENT_VER


## 동의 · 철회를 기기(net.cfg 의 consent · consent_ver)에 남긴다
func set_consent(on: bool) -> void:
	consent_ver = CONSENT_VER if on else 0
	_write_consent = true
	save_cfg()
	_write_consent = false


func save_cfg() -> void:
	var old := ConfigFile.new()
	old.load(CFG)
	var cf := ConfigFile.new()
	cf.set_value("net", "url", url)
	cf.set_value("net", "name", player)
	cf.set_value("net", "token", token)
	if _write_consent:
		cf.set_value("net", "consent", 1 if consent_ver > 0 else 0)
		cf.set_value("net", "consent_ver", consent_ver)
	else:
		cf.set_value("net", "consent", int(old.get_value("net", "consent", 0)))
		cf.set_value("net", "consent_ver", int(old.get_value("net", "consent_ver", 0)))
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
			send({"t": "hello", "name": player, "token": token, "rec": consented()})      # rec = 플레이 기록 동의 (없으면 서버는 기록하지 않는다)
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
