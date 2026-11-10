extends Node
## 온라인 접속 시트 점검 (11/7 서버 콤보) —— 실행: godot --path . --resolution 540x1200 res://tests/online_sheet.tscn -- --out=폴더
## GameScreen 을 띄워 _go_online() 으로 접속 시트를 열고 찍는다: online_dev.png(처음 켠 상태 —— Dev 가 골라져 있다) ·
## online_custom.png(「직접 입력…」을 고른 모습 —— 주소 칸) · online_popup.png(콤보 목록을 펼친 모습).
## 이어서 고른 서버가 user://net.cfg 에 남아 다시 열 때 그대로 골라지는지, 콤보 전에 저장된 파일(주소만)도 맞게 읽는지 본다.
## [--gonline=ws://127.0.0.1:7792 --gname=시험 --gcreate=fast] 면 캡처 대신 이 장면 안에 서버를 띄우고, 게임 화면이 그 점검 인자로
## 콤보를 거치지 않고 그 주소에 붙어 방까지 만드는지 본다.
## 시작할 때 user://net.cfg 를 비우고(처음 켠 휴대폰처럼) 끝나면 되돌린다. 접속은 127.0.0.1 에만 한다 (집 PC 서버에 붙지 않게).

var ok := true
var out := ""
var _backup = null            # 시작 전 net.cfg 내용 (없었으면 null)


func _ready() -> void:
	var args := {}
	for s in OS.get_cmdline_user_args():
		var kv := s.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	out = str(args.get("out", "user://"))
	if FileAccess.file_exists(NetClient.CFG):
		_backup = FileAccess.get_file_as_string(NetClient.CFG)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(NetClient.CFG))
	if args.has("gonline"):
		await _gonline(args)
	else:
		await _sheet()
	_restore()
	print("결과: %s" % ("통과" if ok else "실패"))
	get_tree().quit(0 if ok else 1)


## 접속 시트 —— 캡처 3장 + 고른 서버 저장 · 다시 열기
func _sheet() -> void:
	var servers := Online.load_servers()
	_check("servers.json 을 읽는다", not servers.is_empty() and servers[0].name == "Dev", str(servers))
	if servers.is_empty():
		return
	var dev_url: String = servers[0].url
	var gs: GameScreen = load("res://scenes/game.tscn").instantiate()
	add_child(gs)
	await get_tree().create_timer(1.0).timeout
	gs._go_online()
	await get_tree().create_timer(0.9).timeout
	var ob := _pick(gs)
	_check("처음 켠 상태 —— Dev 가 골라져 있다", ob != null and ob.selected == 0 and ob.get_item_text(0) == "Dev · " + dev_url, ob.text if ob else "콤보 없음")
	if ob == null:
		return
	_check("항목은 서버 + 맨 끝 「직접 입력…」", ob.item_count == servers.size() + 1 and ob.get_item_text(ob.item_count - 1) == Online.CUSTOM, str(ob.item_count))
	_check("Dev 일 때 주소 칸은 숨는다", not gs.online._url_edit.visible, "")
	_check("콤보가 시트 폭 안에 든다", ob.get_global_rect().end.x <= gs._sheet.get_global_rect().end.x - 8, "%s / 시트 %s" % [ob.get_global_rect(), gs._sheet.get_global_rect()])
	_check("처음 켠 기기 —— 동의 칸 + 「동의하고 접속」 · 「취소」 (그냥 「접속」은 없다)", not gs.online.net.consented() and _find_btn(gs._sheet_body, "동의하고 접속") != null and _find_btn(gs._sheet_body, "취소") != null and _find_btn(gs._sheet_body, "접속") == null, "")
	_check("동의 문구가 시트에 있다", _has_text(gs._sheet_body, Online.CONSENT_TITLE) and _has_text(gs._sheet_body, Online.CONSENT_TEXT), "")
	await _shot("online_dev.png")
	# 직접 입력 —— 사용자가 목록에서 고른 것처럼 (select + item_selected)
	var last := ob.item_count - 1
	ob.select(last)
	ob.item_selected.emit(last)
	await get_tree().create_timer(0.7).timeout
	var ed: LineEdit = gs.online._url_edit
	_check("「직접 입력…」을 고르면 주소 칸이 열린다", ed.visible and ed.get_global_rect().end.y <= gs._sheet_scroll.get_global_rect().end.y, "%s" % ed.get_global_rect())
	_check("콤보 · 주소 칸 · 이름 칸 높이가 같다", ed.size.y == gs.online._name_edit.size.y and ob.size.y == ed.size.y, "콤보 %s · 주소 %s · 이름 %s" % [ob.size, ed.size, gs.online._name_edit.size])
	await _shot("online_custom.png")
	ob.show_popup()
	await get_tree().create_timer(0.5).timeout
	await _shot("online_popup.png")
	var pm := ob.get_popup()
	print("  목록: 위치 %s · 크기 %s · 화면 %s" % [pm.position, pm.size, get_viewport().get_visible_rect().size])
	pm.hide()
	await get_tree().create_timer(0.3).timeout
	# 직접 입력으로 「접속」 —— 아무도 없는 포트라 바로 끊긴다. net.cfg 에 server="" · custom · url 이 남아야 한다
	var url := "ws://127.0.0.1:7999"
	ed.text = url
	ed.text_changed.emit(url)
	_find_btn(gs._sheet_body, "동의하고 접속").pressed.emit()
	await get_tree().create_timer(1.2).timeout
	var cf := ConfigFile.new()
	cf.load(NetClient.CFG)
	_check("동의하고 접속하면 net.cfg 에 consent=1 · consent_ver 가 남는다", int(cf.get_value("net", "consent", 0)) == 1 and int(cf.get_value("net", "consent_ver", 0)) == NetClient.CONSENT_VER, cf.encode_to_text().replace("
", " "))
	_check("접속하면 net.cfg 에 직접 입력이 남는다", str(cf.get_value("net", "server", "?")) == "" and str(cf.get_value("net", "custom", "")) == url and str(cf.get_value("net", "url", "")) == url, cf.encode_to_text().replace("\n", " "))
	await _reopen(gs)
	ob = _pick(gs)
	_check("다시 열면 「직접 입력…」 그대로 · 칸에 그 주소", ob.selected == ob.item_count - 1 and gs.online._url_edit.visible and gs.online._url_edit.text == url, ob.text)
	_check("동의한 기기 —— 다시 묻지 않는다 (「접속」 · 「동의 철회」, 동의 문구 없음)", gs.online.net.consented() and _find_btn(gs._sheet_body, "접속") != null and _find_btn(gs._sheet_body, "동의 철회") != null and _find_btn(gs._sheet_body, "동의하고 접속") == null and not _has_text(gs._sheet_body, Online.CONSENT_TEXT), "")
	await _shot("online_consented.png")
	# Dev 로 바꿔 저장 —— 집 PC 서버에 붙지 않으려고 접속 대신 저장만 (접속 때 부르는 것과 같은 save_cfg)
	ob.select(0)
	ob.item_selected.emit(0)
	gs.online.net.save_cfg()
	await _reopen(gs)
	ob = _pick(gs)
	_check("Dev 로 바꾸고 다시 열면 Dev · 직접 친 주소는 남아 있다", ob.selected == 0 and not gs.online._url_edit.visible and gs.online.net.custom == url, ob.text)
	_check("다른 설정을 저장해도(save_cfg) 동의는 그대로", gs.online.net.consented(), "")
	# 동의 철회 —— net.cfg 에서 지우고, 다시 열면 다시 묻는다
	_find_btn(gs._sheet_body, "동의 철회").pressed.emit()
	await get_tree().create_timer(0.5).timeout
	cf = ConfigFile.new()
	cf.load(NetClient.CFG)
	_check("철회하면 net.cfg 의 consent=0 · 시트가 다시 동의를 묻는다", int(cf.get_value("net", "consent", 1)) == 0 and not gs.online.net.consented() and _find_btn(gs._sheet_body, "동의하고 접속") != null, cf.encode_to_text().replace("
", " "))
	await _reopen(gs)
	_check("철회 뒤 다시 열어도 동의 전", not gs.online.net.consented() and _find_btn(gs._sheet_body, "동의하고 접속") != null, "")
	# 「취소」 —— 접속하지 않고 시트를 닫는다
	_find_btn(gs._sheet_body, "취소").pressed.emit()
	await get_tree().create_timer(0.6).timeout
	_check("「취소」는 접속 없이 시트를 닫는다", not gs.sheet_open() and not gs.online.net.is_open(), "")
	gs._go_online()
	await get_tree().create_timer(0.6).timeout
	# 문구가 바뀌어 번호가 올랐다 —— 예전 번호로 동의한 기기는 다시 묻는다
	cf = ConfigFile.new()
	cf.load(NetClient.CFG)
	cf.set_value("net", "consent", 1)
	cf.set_value("net", "consent_ver", NetClient.CONSENT_VER - 1)
	cf.save(NetClient.CFG)
	await _reopen(gs)
	_check("예전 문구 번호(consent_ver 낮음)로 동의했으면 다시 묻는다", not gs.online.net.consented() and _find_btn(gs._sheet_body, "동의하고 접속") != null, "")
	# 콤보 전에 저장된 파일 (주소 · 이름 · 토큰만) —— Dev 주소면 Dev, 다른 주소면 직접 입력에 그 주소
	_old_cfg(dev_url)
	await _reopen(gs)
	ob = _pick(gs)
	_check("예전 파일(Dev 주소) → Dev", ob.selected == 0, ob.text)
	_check("예전 파일(consent 없음) → 동의 전", not gs.online.net.consented(), "")
	_old_cfg("ws://10.1.2.3:7777")
	await _reopen(gs)
	ob = _pick(gs)
	_check("예전 파일(다른 주소) → 직접 입력에 그 주소", ob.selected == ob.item_count - 1 and gs.online._url_edit.text == "ws://10.1.2.3:7777", "%s · %s" % [ob.text, gs.online._url_edit.text])
	await _shot("online_custom_saved.png")


## --gonline —— 서버를 이 장면 안에 띄우고 게임 화면의 점검 인자 처리(_dev_args)가 콤보를 거치지 않고 붙는지
func _gonline(args: Dictionary) -> void:
	var url := str(args.gonline)
	var server := MatchServer.new()
	server.port = int(url.get_slice(":", 2))
	add_child(server)
	_old_cfg("ws://10.1.2.3:7777")      # 콤보는 다른 것(직접 입력 10.1.2.3)을 가리키게 해 둔다
	var gs: GameScreen = load("res://scenes/game.tscn").instantiate()
	add_child(gs)
	var t := 0.0
	while t < 8.0 and (gs.online == null or gs.online.room.is_empty()):
		await get_tree().create_timer(0.2).timeout
		t += 0.2
	_check("--gonline 주소로 붙어 방을 만들었다", gs.online != null and gs.online.net.url == url and str(gs.online.room.get("code", "")).length() == 4,
		"%s · 방 %s" % [gs.online.net.url if gs.online else "-", gs.online.room.get("code", "-") if gs.online else "-"])
	var cf := ConfigFile.new()
	cf.load(NetClient.CFG)
	_check("콤보 선택(직접 입력 10.1.2.3)은 그대로 남는다", str(cf.get_value("net", "server", "?")) == "" and str(cf.get_value("net", "custom", "")) == "ws://10.1.2.3:7777" and str(cf.get_value("net", "url", "")) == url,
		cf.encode_to_text().replace("\n", " "))
	if gs.online != null:
		gs.online.leave()
	await get_tree().create_timer(0.3).timeout


## 접속을 닫고 시트를 다시 연다 —— 새 Online 이 net.cfg 를 다시 읽는다 (앱을 껐다 켠 것처럼)
func _reopen(gs: GameScreen) -> void:
	gs.online.leave()
	gs.close_sheet()
	await get_tree().create_timer(0.5).timeout
	gs._go_online()
	await get_tree().create_timer(0.8).timeout


## 콤보 전 형식의 net.cfg (NetClient 가 쓰던 주소 · 이름 · 토큰만)
func _old_cfg(url: String) -> void:
	var cf := ConfigFile.new()
	cf.set_value("net", "url", url)
	cf.set_value("net", "name", "시험")
	cf.set_value("net", "token", "")
	cf.save(NetClient.CFG)


func _restore() -> void:
	if _backup == null:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(NetClient.CFG))
	else:
		var f := FileAccess.open(NetClient.CFG, FileAccess.WRITE)
		f.store_string(_backup)
		f.close()


## 지금 시트에 보이는 서버 콤보 (Online._url_pick —— 시트를 다시 그리면 새것으로 바뀐다)
func _pick(gs: GameScreen) -> OptionButton:
	var ob: OptionButton = gs.online._url_pick if gs.online != null else null
	if ob == null or not is_instance_valid(ob) or ob.is_queued_for_deletion() or not gs._sheet_body.is_ancestor_of(ob):
		return null
	return ob


func _find_btn(n: Node, text: String) -> Button:
	if n is Button and not (n is OptionButton) and n.text == text and n.is_visible_in_tree() and not n.is_queued_for_deletion():
		return n
	for c in n.get_children():
		var r := _find_btn(c, text)
		if r != null:
			return r
	return null


func _has_text(n: Node, text: String) -> bool:
	if n is Label and n.text == text and n.is_visible_in_tree():
		return true
	for c in n.get_children():
		if _has_text(c, text):
			return true
	return false


func _check(label: String, cond: bool, detail: String) -> void:
	print(("✔ " if cond else "✘ ") + label + ("" if cond or detail == "" else "  (%s)" % detail))
	ok = ok and cond


func _shot(fname: String) -> void:
	await RenderingServer.frame_post_draw
	var path := out.path_join(fname)
	get_viewport().get_texture().get_image().save_png(path)
	print("캡처 ", path)
