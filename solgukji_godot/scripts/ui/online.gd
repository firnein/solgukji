class_name Online
extends Node
## 온라인 대전 —— 집 PC 서버(MatchServer)에 붙는다. 게임 화면(GameScreen)은 그대로 쓰고,
## 행동(act)은 서버에도 보내며, 서버가 돌려준 상태(Run)로 화면을 바꾼다.
## 접속 시트(서버·이름·방 목록·방 만들기·코드로 참가) → 대기실(코드·자리·시작) → 게임.
## 서버는 콤보로 고른다 —— data/servers.json 의 서버(Dev = 집 PC, 빌드 때 그 PC 의 아이피로 고쳐진다) + 「직접 입력…」. 고른 것은 user://net.cfg 에 남는다 (11/7).
## 하루는 아침(징집·조합·편성) → 점심(토벌 보기) → 저녁 준비(상대 이름·전적을 보고 편성) → 저녁(대전 보기) 네 단계 (room.gd, 11/7).
## 명령은 아침 · 저녁 준비에만 보낼 수 있다. '준비 완료'는 방 정보의 stage_no 를 실어 보낸다 —— 늦게 간 준비는 서버가 버린다.
## 전투는 서버가 계산해 보낸 결과를 차례로 재생한다(1단계 —— 자동 전투). 다 봐야 '준비 완료'가 된다 (건너뛰기 없음, 결정 ⑦).
## 끊기면 3초마다 다시 붙는다 —— 토큰이 같아 진행 중인 자리로 돌아가 그 단계부터 이어간다 (이미 다 본 전투는 목록만 받는다).
## 사람이 나 혼자 남으면(다른 사람 모두 멸망·퇴장) 서버가 묻는다 —— 계속할지, 방을 닫을지.

const SERVERS := "res://data/servers.json"      # 서버 목록 —— 콤보에 이 순서대로 (Dev 주소는 build_apk.bat 의 release.py 가 이 PC 의 LAN IPv4 로 고친다)
const CUSTOM := "직접 입력…"

var gs: GameScreen
var net: PickNet
var servers := []             # 콤보의 서버 [{name, url}] (data/servers.json)
var rooms := []
var room := {}                # 서버가 준 방 정보 (Room.info)
var in_game := false
var stage_end := 0.0          # 이 기기 시계로 지금 단계가 끝나는 시각
var watch := []               # 남은 볼 전투 [{title, res}]
var last_battles := []        # 이번 단계 전투 (다시 보기)
var _seen_all := false        # 이번 단계의 전투를 다 봤다 —— 그래야 '준비 완료'를 누를 수 있다
var _stage_no := -1           # 마지막으로 받은 단계 번호 —— 바뀌면 본 기록을 지운다
var _asked_alone := false     # 혼자 남았다는 물음을 띄웠다
var lobby: Control
var _status := "접속 전"
var dev_auto := false         # 점검용 —— 준비 시간에 알아서 징집·선택권·조합·편성·준비 (--gauto)
var _retry := -1.0
var _leaving := false
var _url_pick: OptionButton   # 서버 콤보 —— servers 뒤에 「직접 입력…」
var _url_edit: LineEdit       # 직접 입력 칸 —— 「직접 입력…」을 골랐을 때만 보인다
var _name_edit: LineEdit
var _code_edit: LineEdit
var _tick := 0.0


func _ready() -> void:
	servers = load_servers()
	net = PickNet.new()
	_load_pick()
	add_child(net)
	net.message.connect(_on_msg)
	net.opened.connect(func():
		_status = "접속됨 — %s" % net.url
		_retry = -1.0
		_refresh_sheet())
	net.closed.connect(func():
		_status = "접속 끊김"
		if _leaving:
			return
		if in_game or not room.is_empty():
			gs.toast("서버와 끊겼다 — 다시 붙는 중", "bad")
			_retry = 3.0
		_refresh_sheet())
	if net.player == "":
		net.player = "장수%d" % (randi() % 900 + 100)


func _process(dt: float) -> void:
	if _retry > 0:
		_retry -= dt
		if _retry <= 0:
			net.connect_to(net.url)
			_retry = 5.0
	_tick += dt
	if _tick >= 0.5 and in_game and gs.run != null:
		_tick = 0.0
		gs._render_head()
		if gs.page == "war" and not gs.battle_visible():
			_update_clock_label()


# ───────── 접속 시트 ─────────

## net.cfg 에 고른 서버도 남기는 접속기 —— NetClient.save_cfg() 는 파일을 새로 써서 주소 · 이름 · 토큰 말고는 지운다.
## 그 파일을 쓸 때마다(접속 · 인사) 고른 서버 이름(server —— "" 이면 직접 입력)과 직접 친 주소(custom)를 덧붙인다
class PickNet extends NetClient:
	var server := ""
	var custom := ""

	func save_cfg() -> void:
		super()
		var cf := ConfigFile.new()
		cf.load(CFG)
		cf.set_value("net", "server", server)
		cf.set_value("net", "custom", custom)
		cf.save(CFG)


## 서버 목록 (data/servers.json) —— 이름 · 주소가 다 있는 것만, 적힌 순서대로
static func load_servers() -> Array:
	var out := []
	if not FileAccess.file_exists(SERVERS):
		return out
	var d = JSON.parse_string(FileAccess.get_file_as_string(SERVERS))
	if typeof(d) != TYPE_DICTIONARY or typeof(d.get("servers")) != TYPE_ARRAY:
		return out
	for s in d.servers:
		if typeof(s) == TYPE_DICTIONARY and str(s.get("name", "")) != "" and str(s.get("url", "")) != "":
			out.append({"name": str(s.name), "url": str(s.url)})
	return out


## 지난번 고른 서버 —— net.cfg 의 server 가 목록에 있으면 그것 ("" 이면 직접 입력).
## 콤보 전에 저장된 파일(주소만 있다)은 그 주소가 목록에 있으면 그 서버, 없으면 직접 입력에 그 주소. 처음이면 맨 앞 서버(Dev)
func _load_pick() -> void:
	var cf := ConfigFile.new()
	var ok := cf.load(NetClient.CFG) == OK
	net.custom = str(cf.get_value("net", "custom", "")) if ok else ""
	if ok and cf.has_section_key("net", "server"):
		var nm := str(cf.get_value("net", "server"))
		if nm == "" or _server_index(nm) >= 0:
			net.server = nm
			return
	if ok and cf.has_section_key("net", "url"):
		for s in servers:
			if s.url == net.url:
				net.server = s.name
				return
		net.server = ""
		if net.custom == "":
			net.custom = net.url
		return
	net.server = servers[0].name if not servers.is_empty() else ""


func _server_index(nm: String) -> int:
	for i in servers.size():
		if servers[i].name == nm:
			return i
	return -1


## 접속할 주소 —— 고른 서버의 주소, 직접 입력이면 친 주소
func _picked_url() -> String:
	var i := _server_index(net.server)
	return servers[i].url if i >= 0 else net.custom.strip_edges()


## 서버 콤보 —— servers.json 순서대로 "이름 · 주소", 맨 끝에 「직접 입력…」. 직접 입력을 고르면 아래 주소 칸이 열린다
func _server_pick() -> OptionButton:
	var P := DB.PAL
	var ob := OptionButton.new()
	ob.custom_minimum_size = Vector2(0, 48)
	ob.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ob.fit_to_longest_item = false      # 긴 주소가 시트 폭을 밀지 않게 —— 넘치면 … 로 줄인다
	ob.clip_text = true
	ob.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	ob.action_mode = BaseButton.ACTION_MODE_BUTTON_RELEASE      # 떼야 열린다 —— 시트를 끌다가 목록이 열리지 않게 (끌면 TouchScroll 이 누름을 취소)
	ob.add_theme_font_size_override("font_size", 16)
	var open_sb := UI.flat(P.ink4, P.bamboo, 1, 8, 10)      # 목록이 열린 동안 —— 버튼의 밝은 눌림 색 대신
	ob.add_theme_stylebox_override("pressed", open_sb)
	ob.add_theme_stylebox_override("hover_pressed", open_sb)
	ob.add_theme_color_override("font_pressed_color", P.paper)
	ob.add_theme_color_override("font_hover_pressed_color", P.paper)
	for s in servers:
		ob.add_item("%s · %s" % [s.name, s.url])
	ob.add_item(CUSTOM)
	var i := _server_index(net.server)
	ob.select(i if i >= 0 else servers.size())
	# 펼친 목록 —— 시트와 같은 색, 손가락으로 고르기 좋게 줄을 넉넉히
	var pm := ob.get_popup()
	pm.add_theme_stylebox_override("panel", UI.flat(P.ink2, P.bamboo_dim, 1, 8, 6))
	pm.add_theme_stylebox_override("hover", UI.flat(P.ink4, P.ink4, 0, 6, 6))
	pm.add_theme_font_size_override("font_size", 16)
	pm.add_theme_constant_override("v_separation", 20)
	pm.add_theme_constant_override("item_start_padding", 10)
	pm.add_theme_constant_override("item_end_padding", 14)
	pm.add_theme_color_override("font_color", P.paper)
	pm.add_theme_color_override("font_hover_color", P.paper)
	ob.item_selected.connect(func(idx: int):
		net.server = servers[idx].name if idx < servers.size() else ""
		_url_edit.visible = net.server == ""
		gs._fit_sheet(false))
	return ob


func connect_sheet() -> void:
	var b := gs.open_sheet("온라인 대전")
	b.add_child(UI.hint("Dev = 집 PC 서버(server.bat), 같은 와이파이에서.\n밖에서는 「직접 입력…」에 포트포워딩 · 터널 주소(wss://…)."))      # 문장마다 줄을 나눈다 —— 「직접 입력…」이 줄 끝에서 갈라지지 않게
	var row := UI.vbox(4)
	row.add_child(UI.lbl("서버", 14, DB.PAL.bamboo))
	_url_pick = _server_pick()
	row.add_child(_url_pick)
	_url_edit = LineEdit.new()
	_url_edit.text = net.custom
	_url_edit.placeholder_text = "ws://주소:7777  ·  wss://…"
	_url_edit.custom_minimum_size = Vector2(0, 48)
	_url_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_url_edit.visible = _server_index(net.server) < 0
	_url_edit.text_changed.connect(func(tx: String): net.custom = tx.strip_edges())      # 시트를 다시 그려도(접속 끊김 등) 친 주소가 남게
	row.add_child(_url_edit)
	b.add_child(row)
	var row2 := UI.vbox(4)
	row2.add_child(UI.lbl("이름", 14, DB.PAL.bamboo))
	_name_edit = LineEdit.new()
	_name_edit.text = net.player
	_name_edit.max_length = 12
	_name_edit.custom_minimum_size = Vector2(0, 48)
	_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row2.add_child(_name_edit)
	b.add_child(row2)
	b.add_child(UI.btn("접속" if not net.is_open() else "다시 접속", func():
		net.player = _name_edit.text.strip_edges()
		var u := _picked_url()
		if u == "":
			_status = "주소를 넣어 주세요"
			connect_sheet()
			return
		_status = "접속 중…"
		_leaving = false
		net.connect_to(u)
		connect_sheet(), "pri"))
	b.add_child(UI.lbl(_status, 14, DB.PAL.jade if net.is_open() else DB.PAL.bamboo_dim))
	if not net.is_open():
		return
	b.add_child(UI.eyebrow("방 만들기"))
	var mk := UI.hbox()
	for m in ["fast", "normal"]:
		var bt := UI.btn(Room.MODES[m].n, func(): net.send({"t": "create", "mode": m}), "gold")
		bt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		mk.add_child(bt)
	b.add_child(mk)
	b.add_child(UI.eyebrow("코드로 들어가기"))
	var cr := UI.hbox()
	_code_edit = LineEdit.new()
	_code_edit.placeholder_text = "예) K7QX"
	_code_edit.max_length = 4
	_code_edit.custom_minimum_size = Vector2(0, 48)
	_code_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cr.add_child(_code_edit)
	cr.add_child(UI.btn("참가", func(): net.send({"t": "join", "code": _code_edit.text.to_upper()})))
	b.add_child(cr)
	b.add_child(UI.eyebrow("열린 방 — %d개" % rooms.size()))
	for r in rooms:
		var rb := UI.btn("%s  ·  %s 방장 · %d명 · %s" % [r.code, r.host, r.n, r.mode_n], func(): net.send({"t": "join", "code": r.code}))
		rb.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		rb.clip_text = true
		b.add_child(rb)
	b.add_child(UI.btn("새로 고침", func(): net.send({"t": "list"}), "ghost"))


func _refresh_sheet() -> void:
	if gs._sheet.visible and gs._sheet_title.text == "온라인 대전" and not in_game and room.is_empty():
		connect_sheet()


# ───────── 받기 ─────────

func _on_msg(d: Dictionary) -> void:
	match str(d.t):
		"rooms":
			rooms = d.list
			_refresh_sheet()
		"room":
			room = d.room
			if not room.started:
				gs.close_sheet()
				_show_lobby()
		"state":
			room = d.room
			var r := Run.new()
			r.from_dict(d.run)
			gs.run = r
			stage_end = Room.now() + float(room.remain)
			if int(room.get("stage_no", 0)) != _stage_no:
				# 새 단계 —— 본 기록을 지운다. 전투는 battles 메시지로 따로 온다
				_stage_no = int(room.get("stage_no", 0))
				_seen_all = false
				if not (str(room.stage) in Room.WATCH_STAGES):
					watch = []
			if not in_game:
				in_game = true
				_hide_lobby()
				gs.close_sheet()
				gs._title.visible = false
				gs.go("draw")
				_maybe_ask_alone()
				if dev_auto:
					_dev_step()
				return
			if not gs.battle_visible():
				gs.render()
			_maybe_ask_alone()
			if dev_auto:
				_dev_step()
		"battles":
			last_battles = d.list
			if bool(d.get("seen", false)):
				# 재접속 —— 끊기기 전에 다 본 전투. 목록만 두고 다시 보지 않는다
				watch = []
				_seen_all = true
				if not gs.battle_visible():
					gs.render()
			else:
				watch = d.list.duplicate()
				if not gs.battle_visible():
					watch_next()
		"toast":
			gs.toast(str(d.text), str(d.kind))
		"error":
			gs.toast(str(d.msg), "bad")
		"left":
			room = {}
			in_game = false
			_hide_lobby()


func send_cmd(m: String, a: Array) -> void:
	net.send({"t": "cmd", "m": m, "a": a})


## '준비 완료' —— 지금 단계 번호를 실어 보낸다 (지난 단계의 준비가 다음 단계에 섞이지 않게)
func send_ready(on: bool) -> void:
	net.send({"t": "ready", "on": on, "sno": int(room.get("stage_no", -1))})


func can_act() -> bool:
	return in_game and (str(room.get("stage", "")) in Room.ACT_STAGES) and gs.run != null and gs.run.over == null


func me() -> Dictionary:
	if room.is_empty() or int(room.you) < 0:
		return {}
	return room.seats[int(room.you)]


func remain() -> float:
	return maxf(0.0, stage_end - Room.now())


const STAGE_SHORT := {"morning": "아침", "noon": "점심", "evening_prep": "저녁 준비", "evening": "저녁"}


func clock_text() -> String:
	var st: String = room.get("stage", "")
	var r := int(ceil(remain()))
	if st == "over":
		return "  ·  끝"
	if STAGE_SHORT.has(st):
		return "  ·  %d일차 %s %d:%02d" % [int(room.get("day_no", 0)), STAGE_SHORT[st], r / 60, r % 60]
	return ""


## 혼자 남았다 —— 서버가 물으면 한 번만 시트를 띄운다 (답하면 room.alone 이 "go" 로 바뀌거나 방이 끝난다)
func _maybe_ask_alone() -> void:
	if str(room.get("alone", "")) != "ask":
		_asked_alone = false
		return
	if _asked_alone:
		return
	_asked_alone = true
	if dev_auto:
		net.send({"t": "alone", "go": true})
		return
	var b := gs.open_sheet("혼자 남았다")
	b.add_child(UI.hint("다른 사람이 모두 멸망했거나 방을 나갔다. 남은 날은 봇만 상대하게 된다. 계속할까요?"))
	b.add_child(UI.btn("계속한다 — 봇만 상대로 끝까지", func():
		net.send({"t": "alone", "go": true})
		gs.close_sheet(), "pri", 56))
	b.add_child(UI.btn("그만둔다 — 방을 닫는다", func():
		net.send({"t": "alone", "go": false})
		gs.close_sheet(), "warn", 56))


# ───────── 전투 재생 ─────────

func watch_next() -> void:
	if watch.is_empty():
		if gs.battle_visible():
			gs.hide_battle()
			# 다 봤으면 준비 완료 —— 다시 누르면 취소된다 (결정 ⑦: 끝까지 본 뒤에만)
			_seen_all = true
			if str(room.get("stage", "")) in Room.WATCH_STAGES:
				send_ready(true)
		gs.go("war")
		return
	var b: Dictionary = watch.pop_front()
	gs.show_battle(b.res, watch.is_empty(), str(b.get("kind", "")))


# ───────── 대기실 ─────────

func _show_lobby() -> void:
	_hide_lobby()
	lobby = ColorRect.new()
	lobby.color = DB.PAL.ink
	lobby.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	gs.add_child(lobby)
	TouchScroll.block(lobby)
	var c := MarginContainer.new()
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var side := maxf(24.0, (gs.size.x - 520.0) / 2.0)
	for sd in ["left", "right"]:
		c.add_theme_constant_override("margin_" + sd, int(side))
	lobby.add_child(c)
	var v := UI.vbox(12)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	c.add_child(v)
	var t := UI.lbl("방 %s" % room.code, 54, DB.PAL.gold, true)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	var s := UI.lbl("%s · 친구에게 서버 주소와 이 코드를 알려 주세요" % room.mode_n, 15, DB.PAL.bamboo_dim)
	s.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	s.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(s)
	var sv := UI.vbox(4)
	for i in room.seats.size():
		var st: Dictionary = room.seats[i]
		sv.add_child(UI.rich("[b]%s[/b]%s%s" % [st.name, "  [color=#D9A64B]방장[/color]" if i == 0 else "",
			"  [color=#8fd4c2](나)[/color]" if i == int(room.you) else ""], 17))
	for i in range(room.seats.size(), Room.SEATS):
		sv.add_child(UI.rich("[color=#5d6a88]빈자리 — 시작하면 봇[/color]", 15))
	v.add_child(UI.panel(sv, 14))
	if room.host:
		v.add_child(UI.btn("시작 — 사람 %d명 + 봇 %d" % [room.seats.size(), Room.SEATS - room.seats.size()], func(): net.send({"t": "start"}), "pri", 60))
	else:
		v.add_child(UI.hint("방장이 시작하기를 기다리는 중…"))
	v.add_child(UI.btn("나가기", func():
		net.send({"t": "leave"})
		room = {}
		_hide_lobby()
		connect_sheet(), "ghost"))


func _hide_lobby() -> void:
	if lobby != null:
		lobby.queue_free()
		lobby = null


func leave() -> void:
	_leaving = true
	net.send({"t": "leave"})
	net.close()
	in_game = false
	room = {}
	watch = []
	_hide_lobby()
	gs.hide_battle()
	gs.online = null
	queue_free()


# ───────── 전투 탭 ─────────

var _clock_lbl: Label


func _update_clock_label() -> void:
	if _clock_lbl != null and is_instance_valid(_clock_lbl):
		_clock_lbl.text = _stage_text()


func _stage_text() -> String:
	var r := int(ceil(remain()))
	var t := "%d:%02d" % [r / 60, r % 60]
	match str(room.get("stage", "")):
		"morning": return "아침 %s — 징집·조합·편성을 마치고 '준비 완료'. 모두 준비되면 바로 점심(토벌)" % t
		"noon": return "점심 %s — 토벌을 끝까지 보면 '준비 완료'. 모두 보면 저녁 상대가 정해진다" % t
		"evening_prep": return "저녁 준비 %s — 상대를 보고 편성·작전을 고친 뒤 '준비 완료'. 모두 준비되면 대전" % t
		"evening":
			if int(room.get("tour_round", -1)) >= 0:
				return "토너먼트 %s — %s을 끝까지 보면 '준비 완료'. 모두 보면 다음 라운드" % [t, Run.ROUNDNM[int(room.tour_round)]]
			return "저녁 %s — 대전을 끝까지 보면 '준비 완료'. 모두 보면 다음 날 아침" % t
		"over": return "판이 끝났다"
	return ""


## 상대 줄 —— 이름 · 전적만 (PV 는 보이지 않는다, 결정 ⑥)
func _foe_panel() -> Control:
	var f: Dictionary = room.foe
	var v := UI.vbox(4)
	var tag := ""
	if f.human and not f.online:
		tag = "  [color=#e0806f]끊김 — 봇 대행[/color]"
	v.add_child(UI.rich("[font_size=18][b]%s[/b][/font_size]  [color=#8D7B5C]%s[/color]%s" % [f.name, f.epi, tag], 16))
	v.add_child(UI.rich("[color=#C6AC7C]전적 %d승 %d패[/color]" % [int(f.w), int(f.l)], 14))
	var st: String = str(room.get("stage", ""))
	if st == "evening_prep":
		v.add_child(UI.hint("편성 탭에서 진형·작전을 고칠 수 있다. 상대의 편성은 보이지 않는다."))
	return UI.sect("오늘 저녁 상대", UI.panel(v))


func war_page() -> Control:
	var run: Run = gs.run
	var v := UI.vbox(16)
	var st: String = str(room.get("stage", ""))
	if run.over != null and st == "over":
		v.add_child(gs._over_panel())
		return v
	var head := UI.vbox(6)
	head.add_child(UI.rich("[font_size=20][b]%d일차 · %s[/b][/font_size]   [color=#C6AC7C]%s요일 %s[/color]   [color=#8D7B5C]방 %s · %s[/color]" % [
		int(room.get("day_no", 0)), STAGE_SHORT.get(st, room.get("stage_n", "")), Run.DAYNAME[run.day], Run.PHASE_N[run.phase], room.code, room.mode_n]))
	_clock_lbl = UI.lbl(_stage_text(), 16, DB.PAL.gold)
	_clock_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	head.add_child(_clock_lbl)
	if run.over != null:
		head.add_child(UI.rich("[color=#e0806f][b]%s[/b][/color] — %s. 남은 판은 관전한다." % ["우승" if run.over.win else "탈락", run.over.msg]))
	v.add_child(UI.panel(head))
	if str(room.get("alone", "")) == "ask":
		var av := UI.vbox(6)
		av.add_child(UI.rich("[color=#D9A64B][b]혼자 남았다[/b][/color] — 다른 사람이 모두 멸망했거나 나갔다. 남은 날은 봇만 상대한다."))
		var ah := UI.hbox(8)
		var b1 := UI.btn("계속한다", func(): net.send({"t": "alone", "go": true}), "pri", 48)
		var b2 := UI.btn("방을 닫는다", func(): net.send({"t": "alone", "go": false}), "warn", 48)
		b1.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		ah.add_child(b1)
		ah.add_child(b2)
		av.add_child(ah)
		v.add_child(UI.panel(av))
	var my: Dictionary = me()
	if not my.is_empty() and st != "over" and not my.dead:
		var rd: bool = my.ready
		var watching: bool = st in Room.WATCH_STAGES
		var disabled: bool = watching and not rd and not _seen_all and not last_battles.is_empty()
		var sub := "다른 사람을 기다리는 중"
		if not rd:
			match st:
				"morning": sub = "점심 토벌로"
				"noon": sub = "전투를 끝까지 보면" if disabled else "저녁 상대 선정으로"
				"evening_prep": sub = "대전 시작"
				"evening": sub = "전투를 끝까지 보면" if disabled else "다음으로"
		var b := UI.act("준비 취소" if rd else "준비 완료", sub, func(): send_ready(not rd), "ghost" if rd else "pri", disabled)
		v.add_child(b)
		if watching and not watch.is_empty():
			v.add_child(UI.btn("남은 전투 보기 (%d)" % watch.size(), func(): watch_next(), "gold", 48))
	if room.get("foe") != null and st in ["evening_prep", "evening"]:
		v.add_child(_foe_panel())
	# 자리
	var sv := UI.vbox(4)
	for i in room.seats.size():
		var s2: Dictionary = room.seats[i]
		var mark := "✔" if s2.ready and s2.human else ("·" if s2.human else "봇")
		var col := "#8fd4c2" if s2.ready and s2.human else "#8D7B5C"
		var who := "[b]%s[/b]%s" % [s2.name, " (나)" if i == int(room.you) else ""]
		var tag := "" if s2.online or not s2.human else "  [color=#e0806f]끊김 — 봇 대행[/color]"
		if s2.dead:
			tag += "  [color=#e0806f]멸망[/color]"
		var vs := ""
		if str(s2.get("foe", "")) != "" and st in ["evening_prep", "evening"]:
			vs = "  [color=#8D7B5C]vs %s[/color]" % s2.foe
		sv.add_child(UI.rich("[color=%s]%s[/color]  %s  [color=#C6AC7C]%d PV[/color]%s%s" % [col, mark, who, s2.pv, vs, tag], 15))
	var two := UI.vbox(16)
	var sp := UI.sect("자리 — 사람 %d · 봇 %d" % [room.seats.filter(func(x): return x.human).size(), room.seats.filter(func(x): return not x.human).size()], UI.panel(sv))
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	two.add_child(sp)
	# 이번 단계 전투
	var bv := UI.vbox(6)
	for x in last_battles:
		var res: Dictionary = x.res
		var h := UI.hbox(8)
		var col2 := "#8fd4c2" if res.win else ("#C6AC7C" if res.draw else "#e0806f")
		var r := UI.rich("[color=%s][b]%s[/b][/color]  %s — 잔존 %d 대 %d" % [col2, "무승부" if res.draw else ("승리" if res.win else "패배"), x.title, res.left, res.eLeft], 15)
		r.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(r)
		h.add_child(UI.btn("다시 보기", func():
			watch = [x]
			watch_next(), "ghost", 44))
		bv.add_child(h)
	if last_battles.is_empty():
		match st:
			"morning": bv.add_child(UI.hint("아침이 끝나면 서버가 각자의 토벌을 치러 보낸다."))
			"evening_prep": bv.add_child(UI.hint("준비가 끝나면 서버가 대전을 치러 보낸다."))
			_: bv.add_child(UI.hint("이번 단계에 볼 전투가 없다 — 관전 중."))
	if run.last_spoil != null:
		bv.add_child(UI.hint("기본패 %d장 획득 — %s" % [run.last_spoil.n, run.last_spoil.src]))
	if run.ticket_left() > 0:
		bv.add_child(UI.rich("[color=#D9A64B]선택권 %d장 — 다음 아침에 징집 화면에서[/color]" % run.ticket_left(), 14))
	var bp := UI.sect("이번 단계 전투", UI.panel(bv))
	bp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	two.add_child(bp)
	v.add_child(two)
	if run.tour != null:
		v.add_child(gs._bracket())
	v.add_child(UI.hint("온라인 1단계 — 전투는 양쪽 모두 자동(고유기·군령을 AI 가)이고 끝까지 본다. 아침·저녁 준비에 편성을 끝내지 못하면 서버가 채운다. 접속이 끊기면 봇이 대신 진행하고, 다시 들어오면 그 단계부터 이어간다."))
	return v


## 점검용 자동 플레이 —— 상태가 올 때마다 한 걸음 (아침: 징집 → 선택권 → 편성 → 준비 · 저녁 준비: 빈 편성 채우고 준비)
func _dev_step() -> void:
	var r: Run = gs.run
	if not can_act():
		return
	var st: String = str(room.get("stage", ""))
	if st == "morning":
		if not r.drawn and r.draws_n() > 0:
			gs.act("do_draw")
			return
		elif not r.picked:
			gs.act("begin_picks", ["phase", -1])
			return
		elif r.ticket_left() > 0:
			var pl: Array = Run.pickable(r.ticket_tiers()[0])
			pl.sort_custom(func(x, y): return DB.C[x].tr > DB.C[y].tr)
			gs.act("pick", [pl[randi() % mini(6, pl.size())]])
			return
	if r.placed() < 9 and not r.inv.is_empty():
		gs.act("auto_deploy")
	elif not me().get("ready", true):
		send_ready(true)
