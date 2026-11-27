extends Node
## 11/27 빠른 채팅(한마디) 키보드 점검 —— 엔터로 열기 · 닫기, 숫자 키(윗줄 · 숫자패드)로 그 번호의 글 보내기, 입력 칸 · 다른 시트 위에서는 무시.
## 실행(헤드리스): Godot --headless --path . res://tests/quick_chat_keys.tscn
## 사용자 저장은 쓰지 않는다 (Run.dev_nosave · PlayLog.enabled = false · 가짜 접속기). 실패가 있으면 종료 코드 1.

var gs
var on: Online
var fake
var total := 0
var bad := 0


class FakeNet extends Online.PickNet:
	var sent: Array = []
	func send(d: Dictionary) -> void:
		sent.append(d)
	func save_cfg() -> void:
		pass


func _ready() -> void:
	Run.dev_nosave = true
	Run.dev_immortal = true
	PlayLog.enabled = false
	gs = load("res://scenes/game.tscn").instantiate()
	add_child(gs)
	await _frames(3)
	var r := Run.new()
	r.new_game(5)
	r.dev_autoplay()
	gs.run = r
	gs._title.visible = false
	gs.go("draw")
	await _frames(10)
	gs.close_sheet()
	await _wait(0.4)
	on = Online.new()
	on.gs = gs
	gs.add_child(on)
	on.set_process(false)
	fake = FakeNet.new()
	add_child(fake)
	fake.set_process(false)
	on.net = fake
	on.in_game = true
	on.room = {"quick": Room.QUICK_MSGS, "emote_n": Room.EMOTE_N}
	gs.online = on
	await _checks()
	gs.online = null
	print("빠른 채팅 키 점검 —— %d개 · 실패 %d" % [total, bad])
	get_tree().quit(1 if bad > 0 else 0)


func _checks() -> void:
	# 1. 엔터 → 한마디 시트가 열리고, 글 앞에 번호
	_key(KEY_ENTER)
	await _frames(3)
	var b1 := _btn_text(0)
	var b10 := _btn_text(9)
	ck("엔터 → 한마디 시트가 열린다", on.quick_open() and gs._sheet_title.text == "한마디", gs._sheet_title.text)
	ck("글 앞에 번호 1~9, 10번째부터는 번호 없음", b1 == "1. " + str(Room.QUICK_MSGS[0]) and (Room.QUICK_MSGS.size() < 10 or b10 == str(Room.QUICK_MSGS[9])), "%s / %s" % [b1, b10])
	# 2. 숫자 3 → 3번 글을 보내고 닫힌다
	fake.sent.clear()
	_key(KEY_3)
	await _frames(2)
	ck("숫자 3 → {t:say, i:2} 를 보낸다", fake.sent.size() == 1 and str(fake.sent[0].get("t")) == "say" and int(fake.sent[0].get("i")) == 2, str(fake.sent))
	ck("보낸 뒤 시트가 닫힌다", not on.quick_open(), "")
	await _wait(0.4)
	# 3. 엔터 → 열림, 엔터 → 닫힘 (보내지 않음)
	fake.sent.clear()
	_key(KEY_ENTER)
	await _frames(2)
	var o1 := on.quick_open()
	_key(KEY_ENTER)
	await _frames(2)
	ck("열린 상태에서 엔터 → 닫힌다 (보내지 않음)", o1 and not on.quick_open() and fake.sent.is_empty(), "열림 %s" % str(o1))
	await _wait(0.4)
	# 4. 숫자패드 엔터 · 숫자패드 2
	_key(KEY_KP_ENTER)
	await _frames(2)
	_key(KEY_KP_2)
	await _frames(2)
	ck("숫자패드 엔터 → 열림, 숫자패드 2 → i:1", fake.sent.size() == 1 and int(fake.sent[0].get("i")) == 1 and not on.quick_open(), str(fake.sent))
	await _wait(0.4)
	# 5. ESC 로 닫힌다
	_key(KEY_ENTER)
	await _frames(2)
	_key(KEY_ESCAPE)
	await _frames(2)
	ck("ESC → 닫힌다", not on.quick_open(), "")
	await _wait(0.4)
	# 6. 시트가 닫혀 있으면 숫자 키는 글을 보내지 않는다
	fake.sent.clear()
	_key(KEY_4)
	await _frames(2)
	ck("시트가 닫힌 동안 숫자 키 → 보내지 않음", fake.sent.is_empty(), str(fake.sent))
	if gs._sheet.visible:
		gs.close_sheet()
	gs.go("draw")
	await _wait(0.4)
	# 7. 입력 칸에 포커스가 있으면 엔터를 가로채지 않는다
	var ed := LineEdit.new()
	gs.add_child(ed)
	await _frames(2)
	ed.grab_focus()
	await _frames(1)
	_key(KEY_ENTER)
	await _frames(2)
	ck("입력 칸 포커스 중 엔터 → 열리지 않는다", not on.quick_open() and not gs._sheet.visible, "포커스 %s" % str(get_viewport().gui_get_focus_owner()))
	ed.queue_free()
	await _frames(2)
	# 8. 다른 시트가 떠 있으면 엔터를 가로채지 않는다
	gs.open_sheet("다른 창")
	await _frames(2)
	_key(KEY_ENTER)
	await _frames(2)
	ck("다른 시트 위에서 엔터 → 한마디로 바뀌지 않는다", gs._sheet.visible and gs._sheet_title.text == "다른 창" and not on.quick_open(), gs._sheet_title.text)
	gs.close_sheet()
	await _wait(0.4)
	# 9. 온라인 판 · 대기실이 아니면 열리지 않는다
	on.in_game = false
	_key(KEY_ENTER)
	await _frames(2)
	ck("온라인 판 · 대기실 밖 → 엔터로 열리지 않는다", not on.quick_open() and not gs._sheet.visible, "")
	on.in_game = true


func ck(name: String, ok: bool, note := "") -> void:
	total += 1
	if not ok:
		bad += 1
	print("%s · %s%s" % ["통과" if ok else "실패", name, (" —— " + note) if note != "" else ""])


func _key(kc: int) -> void:
	var e := InputEventKey.new()
	e.keycode = kc
	e.physical_keycode = kc
	e.pressed = true
	get_viewport().push_input(e, true)
	var u := e.duplicate()
	u.pressed = false
	get_viewport().push_input(u, true)


func _btn_text(i: int) -> String:
	var g = on._qs_grid
	if not is_instance_valid(g) or i >= g.get_child_count():
		return ""
	return str(g.get_child(i).text)


func _frames(k := 2) -> void:
	for i in k:
		await get_tree().process_frame


func _wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout
