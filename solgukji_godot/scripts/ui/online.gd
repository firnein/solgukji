class_name Online
extends Node
## 온라인 대전 —— 집 PC 서버(MatchServer)에 붙는다. 게임 화면(GameScreen)은 그대로 쓰고,
## 행동(act)은 서버에도 보내며, 서버가 돌려준 상태(Run)로 화면을 바꾼다.
## 접속 시트(서버·이름·방 목록·방 만들기·코드로 참가) → 대기실(코드·자리·시작) → 게임.
## 서버는 콤보로 고른다 —— data/servers.json 의 서버(Dev = 집 PC, 빌드 때 그 PC 의 아이피로 고쳐진다) + 「직접 입력…」. 고른 것은 user://net.cfg 에 남는다 (11/7).
## 하루는 아침(징집·조합·편성) → 점심(토벌 보기) → 저녁 준비(상대 이름·전적을 보고 편성) → 저녁(대전 보기) 네 단계 (room.gd, 11/7).
## 11/11 사용자: 점심(토벌)은 1~3일차만 —— 4일차부터는 아침 → 저녁 준비 → 저녁 세 단계 (방 정보 noon, 머리띠 진행 막대도 세 칸). 전투를 다 보면(결과표가 뜨는 순간) 준비 완료가 자동으로 간다 (replay_ended).
## 명령은 준비 단계(아침 · 저녁 준비)와, 11/11 부터 전투를 보는 단계(점심 · 저녁, 토너먼트 저녁 제외)에서도 보낼 수 있다 (방 정보 act = can_act). '준비 완료'는 방 정보의 stage_no 를 실어 보낸다 —— 늦게 간 준비는 서버가 버린다.
## 전투는 서버가 계산해 보낸 결과를 차례로 재생한다(1단계 —— 자동 전투). 끝까지 본다 (11/10 사용자: 멀티플레이 스킵 없음 — 예전 '결과로 건너뛰기'(BattleView.skip, 11/9 사용자: 리플레이를 나갈 방법)로
## 끝까지 가야 '준비 완료'가 된다 (결정 ⑦ —— 건너뛰어도 결과표는 보고 닫는다). 결과에 실린 재료(res.bp)로 전투장수창의 버프 수치도 혼자 할 때와 같다.
## 11/12 사용자(페이즈 개편, room.gd 맨 위): 아침 = 징집 · 조합 · 편성 · 점심/저녁 = 다 본 뒤 징집 · 조합만 · 저녁 준비 = 편성만. 방 정보 act_draw · act_form · why_*
## 로 버튼을 막고 이유를 띄운다 (can_act(kind) · block_reason). 새 아침이면 가운데 띠 '아침이 밝았습니다'.
## 11/12 사용자: 서버가 다음 단계로 넘어갔는데 아직 전투를 보고 있으면(재생이 밀림) 바로 건너뛴다 (_stage_moved).
## 끊기면 3초마다 다시 붙는다 —— 토큰이 같아 진행 중인 자리로 돌아가 그 단계부터 이어간다 (이미 다 본 전투는 목록만 받는다).
## 사람이 나 혼자 남으면(다른 사람 모두 멸망·퇴장) 서버가 묻는다 —— 계속할지, 방을 닫을지.
## 소식(봇 · 다른 사람의 기인 이상 등용 · 멸망 · 퇴장)은 서버가 news {list:[{text, kind, who?, unit?, id?, when?, hot?}]} 로 뿌린다 —— 알림 + Run.news(머리띠 '소식') (11/9 사용자).
## 11/10 사용자: hot 이 있으면(사람의 기인 이상 등용) 알림 대신 '긴급' 띠 연출(GameScreen.urgent). id · when 은 소식 항목에 그대로 담는다(안 읽은 소식 뱃지 · 소식 시트의 시점 글).
## 11/10 사용자: 남은 시간 5초부터 비프 + 붉은 가장자리 깜빡임 (11/12 깜빡임은 10초부터, 비프는 5초부터) —— 명령을 받는 시간제 단계(아침 · 저녁 준비)에서, 아직 '준비 완료'를 안 눌렀을 때만 (_warn_tick).
## 한마디(say): 방 정보의 미리 적힌 글(room.quick)만, 전투 탭 · 대기실 · 전투 재생 위 띠의 [한마디] 에서 {"t":"say","i":번호}.
## 받은 {who, text} 는 11/12 부터 구름 말풍선(GameScreen.say_pop) —— 보낸 사람의 유저 칸 옆, 안 보이면 위쪽 가운데 (11/9 알림 줄 · 전장 위 줄은 걷었다).
## 11/12 존재감: 자리마다 상태 아이콘(act_st) · 소식 · 상대 칸의 이모트 반응(react_row) · 설욕전 · 멸망 띠(band fall).
## 11/10 사용자: 한마디 시트 위쪽에 이모티콘 한 줄(Icons.EMOTES 8종) —— {"t":"emote","i":번호}. 받은 {who, i} 는 어디서나 GameScreen.emote_pop 으로 이름 + 큰 기호가 1.5초 (글과 같은 2초 간격).
## 서버가 방 정보에 emote_n 을 주지 않으면(옛 서버) 이모티콘 줄은 숨긴다.
## 전투 목록(battles)의 항목은 {title, res, kind, params} —— params(내 쪽이 A 가 되게 맞춘 재료)를 BattleView.play_res 에 넘겨 전투장수창 버프 수치를 혼자 할 때와 같게 (11/9 사용자).
## 머리띠(GameScreen._render_head)는 온라인이면 방의 일차 · 단계 · 남은 시간을 보인다 —— 혼자 하기의 요일 · 페이즈 · 병사 수 대신 (11/9 사용자: 싱크 · 병사 수 제거).

const WarnEdge := preload("res://scripts/ui/warn_edge.gd")      # class_name 없이 (낡은 .godot 캐시에서 'not declared')
const WARN_SEC := 10           # 남은 시간이 이 초 이하(10 → 1)면 붉은 가장자리 깜빡임 (11/12 사용자: 깜빡임은 10초부터)
const BEEP_SEC := 5            # 비프는 그대로 5초부터 (10초 내내 울리면 시끄럽다)
## 11/12 사용자: 4일차~ 준비 15초 —— 깜빡임이 10초부터면 단계의 2/3 가 붉다. 단계 길이(room.stage_len)의 1/3 이하부터, 5 ~ 10초 사이로 (60 · 30초 단계 10초 · 15초 단계 5초)
const SERVERS := "res://data/servers.json"      # 서버 목록 —— 콤보에 이 순서대로 (Dev 주소는 build_apk.bat 의 release.py 가 이 PC 의 LAN IPv4 로 고친다)
const CUSTOM := "직접 입력…"
## 11/10 사용자: "동의를 받아야지" —— 온라인 접속 전에 플레이 기록 동의를 받는다. 문구를 바꾸면 NetClient.CONSENT_VER 를 올려 모두에게 다시 묻는다.
## 동의는 user://net.cfg 의 consent · consent_ver 에 남고(NetClient.set_consent), 접속할 때마다 hello 의 rec 로 서버에 알린다 —— 동의한 사람만 서버(RoomLog)가 기록한다.
const CONSENT_TITLE := "플레이 기록 동의"
const CONSENT_TEXT := "온라인 대전은 이름 · 행동 · 전투 결과를 서버에 저장해 밸런스 분석에만 씁니다.\n동의하지 않으면 온라인 대전은 할 수 없습니다."
## 한마디 —— 자유 입력 없이 서버가 방 정보에 실어 준 글(room.quick)만, 번호로 보낸다 {"t":"say","i":번호} (11/9 사용자)

var gs: GameScreen
var net: PickNet
var servers := []             # 콤보의 서버 [{name, url}] (data/servers.json)
var rooms := []
var room := {}                # 서버가 준 방 정보 (Room.info)
var in_game := false
var stage_end := 0.0          # 이 기기 시계로 지금 단계가 끝나는 시각
var watch := []               # 남은 볼 전투 [{title, res}]
var last_battles := []        # 이번 단계 전투 (다시 보기)
var _last_watched := {}       # 마지막으로 본(또는 보던) 전투 —— 전투 탭의 결과 칸 (11/9 사용자: 결과창이 없었다)
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
var _warn_fx: Control = null      # 붉은 가장자리 (WarnEdge)
var _warn_c := -1                 # 마지막으로 비프를 울린 남은 초 (올림)
var _pick_max := Room.SEATS       # 방 만들기 시트에서 고른 총 인원 (4 · 6 · 8, 11/11) —— create 의 max
var _pick_claim := true           # 11/12 장수 선점제 (기본 켜짐) —— create 의 claim
var _pick_deaths := 0             # 11/12 장수 사망룰 인원 (0 = 끔 · 3 · 5 · 10) —— create 의 deaths
var _intro_room := ""             # 규칙 안내(선점제 팝업 · 사망 연출)를 띄운 방 코드 —— 한 판에 한 번
var dev_max := 8                  # 점검용 —— 가짜 방의 총 인원 (--gseats=4)
var dev_sheet := false            # 점검용 —— 접속 없이 방 만들기 시트까지 그려 본다 (--gsheet=oncreate)
var _stage_len := 0.0             # 지금 단계의 전체 길이 (방 정보 stage_len, 옛 서버는 단계 시작 때 남은 시간)
var _noon_end_room := ""          # 토벌 종료 띠를 띄운 방 코드 —— 한 판에 한 번 (상태 · 소식 어느 쪽이 먼저 와도)
var _warn_off_no := -1            # 이 단계 번호에서는 '준비 완료'를 눌렀다 —— 서버가 알려 주기 전에도 바로 끈다


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
	_warn_tick()
	_tick += dt
	if _tick >= 0.5 and in_game and gs.run != null:
		_tick = 0.0
		gs._render_head()
		if gs.page == "war" and not gs.battle_visible():
			_update_clock_label()


## 5초 경고 —— 할 일이 남은 시간제 단계에서만. 전투를 보는 단계(점심 · 저녁)는 재생이 끝나야 넘어가고 시간이 다 돼도 할 일이 없어 울리지 않는다.
## 0초 · 단계가 바뀜 · '준비 완료' · 멸망/종료 · 접속 끊김이면 바로 끈다. 소리는 Sfx 의 효과음 크기(Settings.sfx_vol, 0 이면 무음)를 따른다
func warn_active() -> bool:
	if not in_game or gs.run == null or gs.run.over != null or room.is_empty() or not can_act() or not (str(room.get("stage", "")) in Room.ACT_STAGES):
		return false
	if _warn_off_no == int(room.get("stage_no", -2)) or bool(me().get("ready", false)) or bool(me().get("dead", false)):
		return false
	return true


## 붉은 가장자리를 시작하는 남은 초 —— 단계 길이의 1/3, 5 ~ 10초 사이 (길이를 모르면 10)
func warn_sec() -> int:
	if _stage_len <= 0.0:
		return WARN_SEC
	return clampi(int(floor(_stage_len / 3.0)), BEEP_SEC, WARN_SEC)


func _warn_tick() -> void:
	var r := remain()
	var c := int(ceil(r))
	if r > 0.0 and c <= warn_sec() and warn_active():
		if _warn_fx == null or not is_instance_valid(_warn_fx):
			_warn_fx = WarnEdge.new()
			gs.add_child(_warn_fx)
		if c != _warn_c:
			_warn_c = c
			if c <= BEEP_SEC:
				Sfx.play("alert_beep", 0.0, 0.0)
		_warn_fx.show_phase(clampf(float(c) - r, 0.0, 1.0))      # 막 c 초가 됐을 때 0 → 다음 초 직전 1
	elif _warn_c != -1 or (_warn_fx != null and is_instance_valid(_warn_fx) and _warn_fx.visible):
		_warn_c = -1
		if _warn_fx != null and is_instance_valid(_warn_fx):
			_warn_fx.hide_now()


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


## 플레이 기록 동의 칸 (접속 시트의 이름 칸 아래) —— 구분선 + 아직 동의 전이면 금 제목 + 종이색 두 줄(무엇을 · 왜 · 안 하면), 동의했으면 회색 한 줄 + 작은 「동의 철회」.
## 서버가 저장하는 것 = 이름 · 행동 · 전투 결과 (Room 의 RoomLog). 버튼(동의하고 접속 · 취소)은 이 칸을 부르는 connect_sheet 가 붙인다
func record_notice() -> Control:
	var v := UI.vbox(4)
	v.add_child(UI.hair())
	if net.consented():
		var row := UI.hbox(8)
		var l := UI.hint("플레이 기록 동의함 · 이름 · 행동 · 전투 결과")
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(l)
		row.add_child(UI.btn("동의 철회", _withdraw_consent, "ghost", 36))
		v.add_child(row)
		return v
	v.add_child(UI.lbl(CONSENT_TITLE, 14, DB.PAL.gold))
	var t := UI.lbl(CONSENT_TEXT, 13, DB.PAL.paper.darkened(0.15))
	t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(t)
	return v


## 동의 철회 —— 기기에 남긴 동의를 지운다. 접속해 있었으면 연결도 끊는다(서버가 이어서 기록하지 않게 · 방에서는 자리를 봇이 이어받는다). 다음 접속 때 다시 묻는다
func _withdraw_consent() -> void:
	var live := net.is_open() or in_game or not room.is_empty()
	net.set_consent(false)
	if live:
		leave()
		gs.toast("기록 동의를 철회해 접속을 끊었다")
		gs._go_online()
	else:
		connect_sheet()


## 「접속」 · 「동의하고 접속」 —— 동의 전이면 consent=true 로 (주소가 비었으면 동의도 남기지 않는다)
func _connect_pressed(consent := false) -> void:
	net.player = _name_edit.text.strip_edges()
	var u := _picked_url()
	if u == "":
		_status = "주소를 넣어 주세요"
		connect_sheet()
		return
	if consent:
		net.set_consent(true)
	_status = "접속 중…"
	_leaving = false
	net.connect_to(u)
	connect_sheet()


## refresh 면(제목 · 메뉴에서 열 때) 접속해 있으면 방 목록을 다시 받는다 —— 'rooms' 가 오면 시트가 다시 그려진다 (11/9)
func connect_sheet(refresh := false) -> void:
	if refresh and net.is_open():
		net.send({"t": "list"})
	var b := gs.open_sheet("온라인 대전")
	b.add_child(UI.hint("Dev = 집 PC 서버, 어디서나 접속.\n같은 집 와이파이면 「Dev 와이파이」도 된다."))      # 문장마다 줄을 나눈다 —— 「직접 입력…」이 줄 끝에서 갈라지지 않게
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
	b.add_child(record_notice())
	if net.consented():
		b.add_child(UI.btn("접속" if not net.is_open() else "다시 접속", _connect_pressed, "pri"))
	else:      # 동의 전 —— 동의하고 접속하거나 취소(접속 안 함)
		var cb := UI.hbox(8)
		var ok := UI.btn("동의하고 접속", func(): _connect_pressed(true), "pri")
		ok.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cb.add_child(ok)
		var no := UI.btn("취소", func(): gs.close_sheet(), "ghost")
		no.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cb.add_child(no)
		b.add_child(cb)
	b.add_child(UI.lbl(_status, 14, DB.PAL.jade if net.is_open() else DB.PAL.bamboo_dim))
	if not net.is_open() and not dev_sheet:
		return
	# 11/9 사용자: 세션이 연결돼 있으면 다른 방으로 갈 수 없었다 —— 지금 방을 보여 주고 나갈 수 있게, 다른 방에 들어가면 지금 방은 자동으로 나간다
	if not room.is_empty():
		b.add_child(UI.eyebrow("지금 방"))
		var cur := UI.hbox(8)
		var cl := UI.lbl("%s  ·  %s · %d/%d명%s" % [str(room.get("code", "")), str(room.get("mode_n", "")), (room.get("seats", []) as Array).size(), room_max(), " · 진행 중" if in_game else " · 대기 중"], 15, DB.PAL.paper)
		cl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		cur.add_child(cl)
		cur.add_child(UI.btn("나가기", leave_room, "warn"))
		b.add_child(cur)
		b.add_child(UI.hint("나가면 내 자리는 AI 가 이어받는다. 다른 방을 만들거나 들어가도 지금 방에서는 나간다."))
	b.add_child(UI.eyebrow("방 만들기"))
	# 11/11 사용자: 총 인원(자리 수)은 방장이 고른다 —— 짝수 4 · 6 · 8. 사람이 앉고 남은 자리만 시작할 때 봇이 채운다
	var seat_box := UI.vbox(4)
	b.add_child(seat_box)
	_fill_seat_pick(seat_box)
	var mk := UI.hbox()
	for m in ["fast", "normal"]:
		var bt := UI.btn(Room.MODES[m].n, func():
			_drop_room()
			net.send({"t": "create", "mode": m, "max": _pick_max, "claim": _pick_claim, "deaths": _pick_deaths}), "gold")
		bt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART      # 긴 모드 글이 시트 폭을 밀지 않게 (두 칸이 한 줄에 들어가도록 줄바꿈)
		bt.custom_minimum_size = Vector2(0, 64)
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
	cr.add_child(UI.btn("참가", func():
		_drop_room()
		net.send({"t": "join", "code": _code_edit.text.to_upper()})))
	b.add_child(cr)
	b.add_child(UI.eyebrow("열린 방 — %d개" % rooms.size()))
	for r in rooms:
		if not room.is_empty() and str(r.code) == str(room.get("code", "")):
			continue      # 지금 있는 방은 목록에서 뺀다
		var rb := UI.btn("%s  ·  %s 방장 · %d/%d명 · %s" % [r.code, r.host, r.n, int(r.get("max", Room.SEATS)), r.mode_n], func():
			_drop_room()
			net.send({"t": "join", "code": r.code}))
		rb.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		rb.clip_text = true
		b.add_child(rb)
	b.add_child(UI.btn("새로 고침", func(): net.send({"t": "list"}), "ghost"))


## 총 인원 고르기 —— [4명 | 6명 | 8명] + 한 줄 안내 (고르면 이 상자만 다시 그린다 — 시트의 이름 · 주소 칸은 그대로)
func _fill_seat_pick(box: Control) -> void:
	for c in box.get_children():
		c.queue_free()
	var items := []
	for n in Room.SEAT_OPTIONS:
		items.append([str(n), "%d명" % n])
	box.add_child(UI.lbl("총 인원 — 빈자리만 봇", 14, DB.PAL.bamboo))
	box.add_child(UI.segmented(items, str(_pick_max), func(k: String):
		_pick_max = int(k)
		_fill_seat_pick(box)))
	box.add_child(UI.hint("사람 3명이면 %d명 방은 봇 %d명. 시작하면 바꿀 수 없다." % [_pick_max, maxi(0, _pick_max - 3)]))
	# 11/12 방 규칙 —— 장수 선점제(기본 켜짐) · 장수 사망룰(기본 끔, 3 · 5 · 10명)
	box.add_child(UI.lbl("장수 선점제 — 기인 이상은 먼저 등용한 사람만", 14, DB.PAL.bamboo))
	box.add_child(UI.segmented([["1", "켜기"], ["0", "끄기"]], "1" if _pick_claim else "0", func(k: String):
		_pick_claim = k == "1"
		_fill_seat_pick(box)))
	var dl := [["0", "끄기"]]
	for n in Room.DEATH_OPTIONS:
		dl.append([str(n), "%d명" % n])
	box.add_child(UI.lbl("장수 사망룰 — 시작 때 기인 이상 무작위 사망", 14, DB.PAL.bamboo))
	box.add_child(UI.segmented(dl, str(_pick_deaths), func(k: String):
		_pick_deaths = int(k)
		_fill_seat_pick(box)))


## 이 방의 자리 수(총 인원) —— 옛 서버는 max 를 주지 않는다 → 8
func room_max() -> int:
	return int(room.get("max", Room.SEATS))


## 지금 방을 떠난다 (연결은 둔다) —— 서버는 leave 를 받으면 left · rooms 를 보낸다. 혼자 하던 판이 저장돼 있으면 그것으로 돌아간다 (11/9)
func leave_room() -> void:
	net.send({"t": "leave"})
	_drop_room()
	_status = "방에서 나왔다"
	connect_sheet()


## 다른 방으로 옮기기 전 —— 클라이언트 쪽 방 상태를 비운다 (서버는 create · join 때 지금 방에서 먼저 뺀다)
func _drop_room() -> void:
	if room.is_empty() and not in_game:
		return
	room = {}
	in_game = false
	watch = []
	last_battles = []
	_last_watched = {}
	_stage_no = -1
	_seen_all = false
	_asked_alone = false
	_hide_lobby()
	gs.hide_battle()
	if Run.has_save():
		gs.run = Run.load_saved()
	gs.render()


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
			if in_game:
				_unpin_claimed(gs.run, r)
			gs.run = r
			stage_end = Room.now() + float(room.remain)
			if int(room.get("stage_no", 0)) != _stage_no:
				_stage_len = float(room.get("stage_len", room.remain))      # 새 단계 —— 길이 (옛 서버는 필드가 없어 지금 남은 시간)
				# 새 단계 —— 본 기록을 지운다. 전투는 battles 메시지로 따로 온다. 보는 단계가 아니면 지난 전투 줄 · 결과 칸도 걷는다
				var was_watch := _stage_no >= 0 and ((gs.battle_visible() and not gs._battle.finished) or not watch.is_empty())      # 결과표를 보는 중이면 그대로 둔다
				_stage_no = int(room.get("stage_no", 0))
				_seen_all = false
				if was_watch:
					_stage_moved()
				if str(room.stage) == "morning" and in_game:
					if bool(room.get("noon_end", false)):
						noon_end_band(Room.cut_text(str(room.get("mode", "fast"))))      # 11/12 4일차 첫 아침 —— 「아침이 밝았습니다」 대신 「토벌 종료」 (타이머 안내)
					else:
						gs.band("아침이 밝았습니다", DB.PAL.gold, "장수를 등용하고 전투를 준비하세요")
					if not gs.battle_visible() and gs.page != "draw":
						gs.go("draw")      # 11/12 사용자: 새 페이즈(아침)가 열리면 징집 페이지로
				if not (str(room.stage) in Room.WATCH_STAGES):
					watch = []
					last_battles = []
					_last_watched = {}
			if not in_game:
				in_game = true
				_hide_lobby()
				gs.close_sheet()
				gs._title.visible = false
				Sfx.music("prep")
				gs.go("draw")
				_maybe_ask_alone()
				_rules_intro()
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
			_last_watched = {}
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
		"news":
			# 11/9 사용자: 다른 사람 · 봇의 소식 {"list": [{text, kind, who?, unit?, id?, when?, hot?}]} —— 알림 + 소식 목록(머리띠 뱃지 · 전황 소식 시트). 같은 것(id 또는 who·unit 또는 글)은 한 번만
			# 11/10 사용자: hot(사람의 기인 이상 등용)이면 알림 한 줄 대신 '긴급' 띠 연출. id · when 은 항목에 그대로(안 읽은 소식 뱃지 · 시점 글)
			for it in d.get("list", []):
				if not (it is Dictionary):
					continue
				var tx := str(it.get("text", ""))
				var who := str(it.get("who", ""))
				var unit := str(it.get("unit", ""))
				var nid := int(it.get("id", 0))
				var line := str(it.get("line", ""))      # 11/12 유저전 수훈 연속 —— 띠 문구. 소식 목록에는 글로만 (장수가 있으면 등용 줄로 보인다)
				if str(it.get("band", "")) == "noon_end":
					noon_end_band(line)      # 11/12 토벌 종료 띠 (상태가 먼저 와서 이미 띄웠으면 건너뜀) —— 알림 줄은 따로 띄우지 않고 소식 목록에만
					line = ""
				elif bool(it.get("hot", false)) and who != "" and str(it.get("band", "")) == "fall":
					gs.urgent(who, "", line, "fall")      # 11/12 멸망 띠 —— 장수 없이 「유저의 나라가 무너졌습니다 / 남은 군주 N명」
					line = ""
				elif bool(it.get("hot", false)) and who != "" and DB.C.has(unit):
					gs.urgent(who, unit, line)
				elif tx != "":
					gs.toast(tx, str(it.get("kind", "news")))
				if line != "":
					unit = ""
				if gs.run == null:
					continue
				var dup := false
				for nw in gs.run.news:
					if nid > 0:
						dup = dup or int(nw.get("id", 0)) == nid
					elif unit != "" and str(nw.get("who", "")) == who and str(nw.get("unit", "")) == unit:
						dup = true
					elif unit == "" and tx != "" and str(nw.get("text", "")) == tx:
						dup = true
				if not dup and (tx != "" or unit != ""):
					var item := {"who": who, "unit": unit, "text": tx}
					if nid > 0:
						item["id"] = nid
					if it.has("when"):
						item["when"] = str(it.when)
					gs.run.news.push_front(item)
					gs.run.news = gs.run.news.slice(0, 12)
			if gs.run != null:
				gs._render_head()
		"say":
			# 11/9 사용자: 한마디 {who, text} —— 알림으로, 전투를 보는 중이면 전장 왼쪽 위 줄로도 (알림 상자는 전투 · 대기실 아래에 깔린다)
			# 11/12 사용자: 글도 이모티콘처럼 구름 말풍선으로 —— 보낸 사람의 유저 칸(자리 줄 · 군웅 칸 · 대기실 줄)이 보이면 그 옆, 아니면 위쪽 가운데 (SayBubble)
			var who := str(d.get("who", ""))
			var tx := str(d.get("text", ""))
			if tx != "":
				gs.say_pop(who, tx, -1, anchor_of(who))
		"emote":
			# 11/10 사용자: 한마디 이모티콘 {who, i} —— 어디서나(대기실 · 아침 · 저녁 준비 · 전투 보는 중). 11/12 글과 같은 구름 말풍선, 유저 칸 옆
			var who := str(d.get("who", ""))
			gs.say_pop(who, "", int(d.get("i", -1)), anchor_of(who))
		"act_st":
			# 11/12 사용자(존재감): 자리마다 지금 하는 일 {"st": [자리 순]} —— 방 정보의 줄에 넣고 보이는 아이콘만 바꾼다 (화면을 다시 그리지 않는다)
			var st = d.get("st", [])
			var ss: Array = room.get("seats", [])
			if st is Array and st.size() == ss.size():
				for i in ss.size():
					if ss[i] is Dictionary and bool(ss[i].get("human", false)):
						ss[i]["st"] = str(st[i])
				_st_refresh()
		"error":
			gs.toast(str(d.msg), "bad")
		"left":
			_drop_room()
			_refresh_sheet()


## 11/12 사용자: 토벌이 사라지는 순간 가운데 띠 「토벌 종료 / 이제부터 준비 30초 · 대전 준비 15초」 —— 한 판(방)에 한 번
func noon_end_band(line: String) -> void:
	var code_ := str(room.get("code", ""))
	if _noon_end_room == code_ and code_ != "":
		return
	_noon_end_room = code_
	gs.band("토벌 종료", DB.PAL.seal.lightened(0.15), "이제부터 %s" % line if line != "" else "")


func send_cmd(m: String, a: Array) -> void:
	net.send({"t": "cmd", "m": m, "a": a})


## '준비 완료' —— 지금 단계 번호를 실어 보낸다 (지난 단계의 준비가 다음 단계에 섞이지 않게)
func send_ready(on: bool) -> void:
	_warn_off_no = int(room.get("stage_no", -1)) if on else -1
	net.send({"t": "ready", "on": on, "sno": int(room.get("stage_no", -1))})


## 한마디 —— 미리 적힌 글의 번호만 보낸다 (서버가 2초에 한 번으로 거른다)
func send_say(i: int) -> void:
	net.send({"t": "say", "i": i})


## 이모티콘 하나 —— 번호만 보낸다 (서버가 글과 같은 2초 간격으로 거르고 번호 범위를 검증한다)
func send_emote(i: int) -> void:
	net.send({"t": "emote", "i": i})


## 이모티콘 한 줄 —— 8칸 가로 (칸 높이 46). 누르면 보내고 시트를 닫는다
func _emote_row() -> Control:
	var n := mini(int(room.get("emote_n", 0)), Icons.EMOTES.size())
	var h := UI.hbox(4)
	for i in n:
		var bt := UI.btn("", func():
			send_emote(i)
			gs.close_sheet(), "", 46)
		bt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bt.custom_minimum_size = Vector2(0, 46)
		bt.tooltip_text = Icons.EMOTE_NAMES[i]
		var ic := Icons.View.new(Icons.EMOTES[i], DB.PAL.paper, 26.0)
		ic.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
		ic.position = Vector2(-13, -13)
		bt.add_child(ic)
		h.add_child(bt)
	return h


## 한마디 시트 —— 방 정보의 미리 적힌 글(room.quick)을 버튼으로. 대기실(가득 덮는 판) 위에서도 보이게 시트를 맨 앞으로 (11/9 사용자)
func quick_sheet() -> void:
	var quick: Array = room.get("quick", [])
	var b := gs.open_sheet("한마디")
	if lobby != null and is_instance_valid(lobby):
		gs.move_child(gs._sheet_mask, -1)
		gs.move_child(gs._sheet, -1)
	b.add_child(UI.hint("방의 모두에게 보인다 · 2초에 한 번"))
	if int(room.get("emote_n", 0)) > 0:
		b.add_child(_emote_row())
	if quick.is_empty():
		b.add_child(UI.hint("서버가 아직 글 목록을 주지 않았다."))
	var g := UI.grid(150, 8)
	for i in quick.size():
		var bt := UI.btn(str(quick[i]), func():
			send_say(i)
			gs.close_sheet(), "", 46)
		bt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		g.add_child(bt)
	b.add_child(g)


## 작은 [한마디] 버튼 —— 전투 탭 머리줄 · 대기실
func _say_btn() -> Button:
	var b := UI.btn("한마디", quick_sheet, "ghost", 34)
	b.add_theme_font_size_override("font_size", 13)
	b.custom_minimum_size = Vector2(66, 34)
	return b


# ───────── 존재감 (11/12 사용자: 다른 유저도 지금 뭔가 하고 있다) —— 상태 아이콘 · 유저 칸(말풍선 자리) · 이모트 반응 ─────────
## 서버 Room.seat_status 의 값 → [아이콘(Icons), 짧은 글, 색]. 글꼴 이모지는 기기마다 달라 선 아이콘으로 (🔨 ⚔ 🛡 💤 ✔)
const ST_LOOK := {"busy": ["forge", "징집·조합 중", "#D9A64B"], "quest": ["blade", "토벌 중", "#e0806f"], "pvp": ["shield", "대전 중", "#e0806f"],
	"idle": ["zz", "대기", "#8D7B5C"], "ready": ["check", "준비 완료", "#8fd4c2"]}
const REACTS := [1, 4, 5]      # 소식 · 상대 발표의 반응 —— 폭소 · 놀람 · 좋아요 (Icons.EMOTES 번호, 한마디 이모티콘 흐름 그대로)
var _st_views := []            # [[칸(HBox), 이름]] —— act_st 가 오면 보이는 것만 바꾼다
var _anchors := {}             # 이름 -> 유저 칸(Control) —— 한마디 말풍선이 붙는 자리 (가장 최근에 그린 것)


## 작은 상태 표시 (아이콘 + 짧은 글) —— st 가 비면 숨는다. 이름으로 등록해 act_st 때 바뀐다
func st_view(who: String, st: String) -> Control:
	var h := UI.hbox(3)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(Icons.View.new("", Color.WHITE, 15.0))
	var l := UI.lbl("", 11, DB.PAL.bamboo_dim)
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(l)
	_st_views = _st_views.filter(func(e): return is_instance_valid(e[0]))
	_st_views.append([h, who])
	_st_apply(h, st)
	return h


func _st_apply(h: Control, st: String) -> void:
	var lk: Array = ST_LOOK.get(st, [])
	h.visible = not lk.is_empty()
	if lk.is_empty():
		return
	var ic: Icons.View = h.get_child(0)
	ic.icon = str(lk[0])
	ic.col = Color(str(lk[2]))
	ic.queue_redraw()
	var l: Label = h.get_child(1)
	l.text = str(lk[1])
	l.add_theme_color_override("font_color", Color(str(lk[2])))
	h.tooltip_text = str(lk[1])


func seat_st(who: String) -> String:
	for s in room.get("seats", []):
		if s is Dictionary and str(s.get("name", "")) == who:
			return str(s.get("st", ""))
	return ""


func _st_refresh() -> void:
	_st_views = _st_views.filter(func(e): return is_instance_valid(e[0]))
	for e in _st_views:
		_st_apply(e[0], seat_st(str(e[1])))


## 유저 칸 등록 —— 자리 줄 · 군웅 칸 · 대기실 줄을 그릴 때
func anchor(who: String, c: Control) -> void:
	_anchors[who] = c


## 그 사람의 유저 칸 —— 지금 보이는 것만 (전투 재생 중이면 가려져 있으니 없음)
func anchor_of(who: String) -> Control:
	var c = _anchors.get(who)
	if c == null or not is_instance_valid(c) or not (c as Control).is_visible_in_tree() or gs.battle_visible():
		return null
	return c


## 반응 버튼 한 줄 —— 누르면 그 이모티콘을 방에 보낸다 (한마디와 같은 2초 간격 · 서버 검증)
func react_row(sz := 30.0) -> Control:
	var h := UI.hbox(2)
	h.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var n := mini(int(room.get("emote_n", 0)), Icons.EMOTES.size())
	for k in REACTS:
		if k >= n:
			continue
		var kk: int = k
		var bt := UI.btn("", func(): send_emote(kk), "ghost", int(sz))
		bt.custom_minimum_size = Vector2(sz + 4.0, sz)
		bt.tooltip_text = Icons.EMOTE_NAMES[k]
		var d := roundf(sz * 0.62)
		var ic := Icons.View.new(Icons.EMOTES[k], DB.PAL.paper, d)
		ic.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
		ic.position = Vector2(-d / 2.0, -d / 2.0)      # 한마디 이모티콘 줄(_emote_row)과 같은 방식 —— 가운데 앵커에서 반지름만큼
		bt.add_child(ic)
		h.add_child(bt)
	return h


## 할 수 있나 —— kind "draw"(징집 · 조합) · "form"(편성) · ""(무엇이든). 서버의 방 정보 act_draw · act_form (11/12), 옛 서버는 act · 준비 단계만
func can_act(kind := "") -> bool:
	if not in_game or gs.run == null or gs.run.over != null or room.is_empty():
		return false
	if kind != "" and room.has("act_" + kind):
		return bool(room["act_" + kind])
	if room.has("act"):
		return bool(room.act)
	return str(room.get("stage", "")) in Room.ACT_STAGES


## 막힌 이유 한 줄 (서버가 방 정보에 실어 준 글)
func block_reason(kind: String) -> String:
	var t := str(room.get("why_" + kind, ""))
	return t if t != "" else ("지금은 편성할 수 없다" if kind == "form" else "지금은 징집 · 조합할 수 없다")


## 명령 이름 → 종류 (Room.FORM_CMDS 면 편성)
static func cmd_kind(m: String) -> String:
	return "form" if m in Room.FORM_CMDS else "draw"


func me() -> Dictionary:
	if room.is_empty() or int(room.you) < 0:
		return {}
	return room.seats[int(room.you)]


func remain() -> float:
	return maxf(0.0, stage_end - Room.now())


## 11/10 사용자: 단계 이름이 페이즈 이름(오전 · 오후 · 저녁)과 같은 시간대 말이라 헷갈린다 —— 하는 일로 부른다 (아침 → 준비 · 점심 → 토벌 · 저녁 준비 → 대전 준비 · 저녁 → 대전)
const STAGE_SHORT := {"morning": "준비", "noon": "토벌", "evening_prep": "대전 준비", "evening": "대전"}
## 11/10 사용자: 온라인의 '일차'는 방의 페이즈 번호(day_no = 일 × 3 + 페이즈 + 1, 1~21)라 12일차까지 가는 것처럼 보였다 —— 화면에는 혼자 하기와 같은 게임 날짜 · 페이즈(예: day_no 12 → 「4일차 저녁」)로 보인다. 서버 · 기록의 day_no 는 그대로
func day_text() -> String:
	var n := maxi(1, int(room.get("day_no", 1)))
	return "%d일차 %s" % [(n - 1) / 3 + 1, Run.PHASE_N[(n - 1) % 3]]


const STAGE_IDX := {"morning": 0, "noon": 1, "evening_prep": 2, "evening": 3}      # 머리띠 진행 막대의 네 칸 (11/9)
const STAGE_IDX3 := {"morning": 0, "evening_prep": 1, "evening": 2}      # 11/11 토벌이 없는 날(4일차~)의 세 칸


## 이 일차에 점심(토벌) 단계가 있나 —— 서버의 방 정보 noon (옛 서버는 늘 있다). 점심이 지금이면 당연히 있다
func has_noon() -> bool:
	return str(room.get("stage", "")) == "noon" or bool(room.get("noon", true))


## 머리띠 진행 막대 —— 칸 수 · 지금 칸
func head_steps() -> int:
	return 4 if has_noon() else 3


func head_idx() -> int:
	var st := str(room.get("stage", ""))
	var m: Dictionary = STAGE_IDX if has_noon() else STAGE_IDX3
	return int(m.get(st, head_steps() - 1 if st == "over" else 0))


## 남은 시간 "1:20"
func remain_text() -> String:
	var r := int(ceil(remain()))
	return "%d:%02d" % [r / 60, r % 60]


## 머리띠의 단계 글 —— "저녁 준비 · 1:20" (판이 끝났으면 "끝")
func head_stage_text() -> String:
	var st: String = str(room.get("stage", ""))
	if st == "over":
		return "끝"
	if STAGE_SHORT.has(st):
		return "%s · %s" % [STAGE_SHORT[st], remain_text()]
	return str(room.get("stage_n", ""))


func clock_text() -> String:
	var st: String = room.get("stage", "")
	var r := int(ceil(remain()))
	if st == "over":
		return "  ·  끝"
	if STAGE_SHORT.has(st):
		return "  ·  %s %d:%02d" % [day_text(), r / 60, r % 60]
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

## 11/11 사용자: 전투를 다 보면 준비 완료가 자동 —— 결과표가 뜨는 순간(BattleView.ended, 끝까지 가도 · 건너뛰어도) 이번 단계 마지막 전투면 바로 보낸다.
## 결과표를 닫기를 기다리지 않는다 (다른 사람이 모두 끝났으면 바로 다음 단계). 이미 준비면 다시 보내지 않는다 (준비 취소를 되돌리지 않게)
func replay_ended() -> void:
	if not in_game or not watch.is_empty() or room.is_empty():
		return
	if not (str(room.get("stage", "")) in Room.WATCH_STAGES) or last_battles.is_empty():
		return
	if bool(me().get("ready", false)) or _warn_off_no == int(room.get("stage_no", -2)):
		return
	send_ready(true)


## 11/12 사용자: 전투 싱크가 밀렸다 —— 서버는 이미 다음 단계인데 재생 중(또는 볼 전투가 남음)이면 바로 건너뛴다. 결과는 전투 탭의 지난 전투 · 소식으로
func _stage_moved() -> void:
	watch = []
	if gs.battle_visible() and not gs._battle.finished:
		gs.hide_battle()
		gs.toast("다른 사람이 모두 끝나 전투를 건너뛰었다", "news")
	if gs.battle_visible() or str(room.get("stage", "")) in Room.WATCH_STAGES:
		return
	gs.go("draw" if str(room.get("stage", "")) == "morning" else "deploy")


func watch_next() -> void:
	if watch.is_empty():
		if gs.battle_visible():
			gs.hide_battle()
			# 다 봤으면 준비 완료 —— 다시 누르면 취소된다 (결정 ⑦: 끝까지 본 뒤에만)
			_seen_all = true
			if str(room.get("stage", "")) in Room.WATCH_STAGES and not bool(me().get("ready", false)):
				send_ready(true)      # 보통은 replay_ended 가 결과표가 뜨는 순간 이미 보냈다 —— 건너뛰기 · 재연결 등으로 못 보냈을 때의 보험
		gs.go("war")
		return
	var b: Dictionary = watch.pop_front()
	_last_watched = b          # 닫고 전투 탭으로 돌아오면 이 전투의 결과 칸을 보인다
	gs.show_battle(b.res, watch.is_empty(), str(b.get("kind", "")), b.get("params", {}))


# ───────── 대기실 ─────────

func _show_lobby() -> void:
	Sfx.music("title")
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
	var s := UI.lbl("총 %d명 · %s (4일차~ 절반)%s · 친구에게 서버 주소와 이 코드를 알려 주세요" % [room_max(), room.mode_n, rules_text()], 15, DB.PAL.bamboo_dim)
	s.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	s.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(s)
	var sv := UI.vbox(4)
	for i in room.seats.size():
		var st: Dictionary = room.seats[i]
		var lr := UI.rich("[b]%s[/b]%s%s" % [st.name, "  [color=#D9A64B]방장[/color]" if i == 0 else "",
			"  [color=#8fd4c2](나)[/color]" if i == int(room.you) else ""], 17)
		sv.add_child(lr)
		anchor(str(st.name), lr)      # 11/12 한마디 말풍선이 붙는 자리
	for i in range(room.seats.size(), room_max()):
		sv.add_child(UI.rich("[color=#5d6a88]빈자리 — 시작하면 봇[/color]", 15))
	v.add_child(UI.panel(sv, 14))
	if room.host:
		v.add_child(UI.btn("시작 — 사람 %d명 + 봇 %d" % [room.seats.size(), room_max() - room.seats.size()], func(): net.send({"t": "start"}), "pri", 60))
	else:
		v.add_child(UI.hint("방장이 시작하기를 기다리는 중…"))
	var cb := UI.btn("방 정보 복사 (서버 주소 + 방 코드)", copy_room_info, "ghost")      # 11/11 사용자: 서버 주소와 방 코드를 한 번에 복사해 바로 보낼 수 있게
	v.add_child(cb)
	var hb := UI.hbox(8)
	var sb := UI.btn("한마디", quick_sheet, "ghost")
	sb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(sb)
	var lb := UI.btn("나가기", func():
		net.send({"t": "leave"})
		room = {}
		_hide_lobby()
		connect_sheet(), "ghost")
	lb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(lb)
	v.add_child(hb)
	gs.move_child(gs._toast_box, -1)      # 대기실은 화면을 다 덮는다 —— 알림(한마디 · 소식)이 그 위에 보이게


## 방 규칙 한 토막 (11/12) —— " · 장수 선점제 · 사망 3명". 옛 서버는 claim 이 없다 → 빈 글
func rules_text() -> String:
	var out := ""
	if bool(room.get("claim", false)):
		out += " · 장수 선점제"
	if int(room.get("deaths", 0)) > 0:
		out += " · 장수 사망 %d명" % int(room.deaths)
	return out


## 게임에 처음 들어왔을 때(1일차 첫 아침) 규칙 안내 —— 선점제 팝업을 닫으면 사망 장수 연출 (겹치면 이 순서로). 방마다 한 번
func _rules_intro() -> void:
	var code_ := str(room.get("code", ""))
	if code_ == "" or code_ == _intro_room or dev_auto:
		return
	if int(room.get("day", 0)) != 0 or int(room.get("phase", 0)) != 0 or str(room.get("stage", "")) != "morning":
		_intro_room = code_      # 첫 아침이 지난 뒤 들어왔다(재접속) —— 다시 띄우지 않는다
		return
	_intro_room = code_
	var dead: Array = room.get("dead_units", []).filter(func(k): return DB.C.has(str(k)))
	dead = dead.filter(func(k):      # 11/12 하위 불멸이 같이 죽은 신화는 그 불멸 카드에 얹어 한 번에 (GameScreen._next_death) —— 따로 한 번 더 찢지 않는다
		return not dead.any(func(o): return Room.myth_over(str(o)) == str(k)))
	var show_dead := func():
		for k in dead:
			gs.death_card(str(k))
	if not bool(room.get("claim", false)):
		show_dead.call()
		return
	var b := gs.open_sheet("장수 선점제입니다")
	b.add_child(UI.hint("다른 유저가 먼저 등용한 기인 이상(기인 · 초월 · 불멸 · 신화) 장수는 등용할 수 없습니다.
먼저 조합한 사람이 그 장수를 차지합니다."))
	b.add_child(UI.btn("알겠습니다", func():
		gs.close_sheet()
		show_dead.call(), "pri", 52))


## 다른 사람이 먼저 등용해 새로 잠긴 장수 —— 내가 갈무리해 둔 것이면 갈무리를 풀고 알린다 (11/12 장수 선점제)
func _unpin_claimed(old: Run, r: Run) -> void:
	if old == null:
		return
	for k in r.locked:
		var e = r.locked[k]
		if not (e is Dictionary and e.has("by")) or old.locked.has(k):
			continue
		if gs.forge_tree.pinned(str(k)):
			gs.forge_tree.drop(str(k))
			gs.toast("%s이(가) %s에게 등용되어 갈무리가 해제되었습니다" % [DB.C[k].name, str(e.by)], "bad")


## 방 정보 복사 —— 서버 주소 · 방 코드를 클립보드에 (메신저에 그대로 붙여 넣어 친구에게 보낸다). 11/11 사용자
func room_info_text() -> String:
	var url := str(net.url).strip_edges()
	var lines := ["[솔국지] 같이 해요!"]
	if url != "":
		lines.append("서버: %s" % url)
	lines.append("방 코드: %s" % str(room.get("code", "")))
	lines.append("(온라인 → 서버 주소 직접 입력 → 접속 → 방 코드 입력)")
	return "\n".join(lines)


func copy_room_info() -> void:
	DisplayServer.clipboard_set(room_info_text())
	UI.buzz()
	gs.toast("방 정보를 복사했습니다 — 붙여 넣어 보내세요", "gain")


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
## 11/9 사용자: "온라인의 전투탭 구성은 아예 다 뜯어고칠 것" —— 혼자 하기의 전투 탭(GameScreen._page_war · _result_panel)과 같은 결로 다시 짰다.
## 위에서부터: 단계 카드(N일차 · 단계 · 남은 시간 · 지금 할 일 한 줄) → 주 행동 '준비 완료'(전투를 다 보기 전엔 이유와 함께 잠김) →
## 이번 단계 전투(결과 칸 + 한 줄씩 · 보기 / 다시 보기) → 저녁 상대 → 자리(한 줄씩) → 대진표. 긴 설명 글은 뺐다.
## 상자는 테두리 없는 먹색 면 · 반지름 UI.R · 줄은 UI.hair() 로 나눈다 · 주 행동만 금 얇은 선 (작업현황 ㊽ 규칙)

var _clock_lbl: Label


func _update_clock_label() -> void:
	if _clock_lbl != null and is_instance_valid(_clock_lbl):
		_clock_lbl.text = remain_text()


## 지금 할 일 한 줄
func _stage_hint() -> String:
	var st := str(room.get("stage", ""))
	var rd: bool = me().get("ready", false)
	match st:
		"morning": return ("다른 사람을 기다리는 중 — 모두 준비되면 %s" % ("토벌" if has_noon() else "대전 준비")) if rd else "징집 · 조합 · 편성을 마치고 준비 완료"
		"noon": return "다른 사람을 기다리는 중 — 모두 보면 대전 상대가 정해진다. 그동안 징집 · 조합을 해 둘 수 있다 (편성은 대전 준비 때)" if rd else "토벌을 끝까지 보면 자동으로 준비된다"
		"evening_prep": return "다른 사람을 기다리는 중 — 모두 준비되면 대전" if rd else "상대를 보고 편성을 고친 뒤 준비 완료 (징집 · 조합은 다음 아침)"
		"evening":
			if int(room.get("tour_round", -1)) >= 0:
				if _tour_bye():
					return "부전승 — 이번 라운드는 쉰다. 다른 대진을 기다리는 중"
				return "다른 사람을 기다리는 중 — 모두 보면 다음 라운드" if rd else "%s을 보고 준비 완료" % Run.ROUNDNM[int(room.tour_round)]
			return "다른 사람을 기다리는 중 — 모두 보면 다음 아침. 그동안 징집 · 조합을 해 둘 수 있다 (보상은 아침에)" if rd else "대전을 끝까지 보면 자동으로 준비된다"
		"over": return "판이 끝났다"
	return ""


## 토너먼트에서 이번 라운드에 내 대진이 없다 (인원이 8 미만인 방의 상위 시드 부전승) —— 멸망 · 탈락한 사람은 아니다
func _tour_bye() -> bool:
	var run: Run = gs.run
	return run != null and run.over == null and run.tour != null and int(run.tour.get("my_match", -1)) < 0 and str(room.get("stage", "")) == "evening" and last_battles.is_empty()


## 단계 이름 —— 토너먼트 저녁은 라운드 이름
func _stage_name() -> String:
	var st := str(room.get("stage", ""))
	if st == "evening" and int(room.get("tour_round", -1)) >= 0:
		return "토너먼트 %s" % Run.ROUNDNM[int(room.tour_round)]
	return str(STAGE_SHORT.get(st, room.get("stage_n", "")))


## 상대 줄 —— 이름 · 전적 · 핵심 장수 (PV 와 편성은 보이지 않는다, 결정 ⑥)
## 11/12 사용자: 봇의 칭호("전력 1위 사냥꾼" 등)는 빼고 "봇" 으로. 상대의 핵심 장수(기인 이상)를 높은 등급부터 한 줄로 —— 사람 · 그림자는 서버가 준 key, 봇은 지금 전력의 예(GameScreen.bot_key)
func _foe_panel() -> Control:
	var f: Dictionary = room.foe
	var v := UI.vbox(6)
	var tag := ""
	if f.human and not f.online:
		tag = "  [color=#e0806f]끊김 — 봇 대행[/color]"
	var epi := str(f.get("epi", ""))
	if not f.human and not (epi in [Room.SHADOW_EPI, "떠돌이 군세"]):
		epi = "봇"
	var fh := UI.hbox(6)
	var fn := UI.rich("[font_size=18][b]%s[/b][/font_size]  [color=#8D7B5C]%s[/color]%s" % [f.name, epi, tag], 16)
	fn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	fh.add_child(fn)
	if int(room.get("emote_n", 0)) > 0:
		fh.add_child(react_row())      # 11/12 상대 발표에 반응 (한마디 이모티콘 흐름)
	v.add_child(fh)
	if bool(f.get("revenge", false)):      # 11/12 나를 이긴 사람과 다시 만났다
		var rv := UI.hbox(4)
		rv.add_child(Icons.View.new("blade", DB.PAL.seal, 16.0))
		var rl := UI.lbl("설욕전 —— 지난번에 이 상대에게 졌다", 14, Color("#e0806f"), true)
		rl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		rv.add_child(rl)
		v.add_child(rv)
	v.add_child(UI.rich("[color=#C6AC7C]전적 %d승 %d패[/color]" % [int(f.w), int(f.l)], 14))
	var key := []
	var guess := false
	if f.get("key") is Array:
		for k in f.key:      # 믿지 않는다 —— 모르는 id · 기초불신이 아닌 카드 · 중복은 거른다 (peer_rows 와 같다)
			var ks := str(k)
			if DB.C.has(ks) and Room.is_urgent_unit(ks) and not key.has(ks):
				key.append(ks)
	elif not f.human:
		for b in gs.run.bots:
			if str(b.name) == str(f.name):
				key = GameScreen.bot_key(gs.run, b)
				guess = true
				break
	key.sort_custom(func(a, b):
		var ra := Room.key_rank(a)
		var rb := Room.key_rank(b)
		return ra > rb if ra != rb else a < b)
	if not key.is_empty():
		v.add_child(UI.lbl("핵심 장수%s" % (" (봇 군세는 전투마다 새로 뽑는다 —— 예)" if guess else ""), 12, DB.PAL.bamboo_dim))
		var fl := HFlowContainer.new()
		fl.add_theme_constant_override("h_separation", 4)
		fl.add_theme_constant_override("v_separation", 4)
		for k in key:
			var t := MiniTile.new().setup(str(k), -1)
			t.custom_minimum_size = Vector2(50, 74)
			t.tapped.connect(func(kk): gs.card_info(kk))
			fl.add_child(t)
		v.add_child(fl)
	elif f.get("key") is Array or guess:
		v.add_child(UI.lbl("핵심 장수 아직 없음", 12, DB.PAL.bamboo_dim))
	if str(room.get("stage", "")) == "evening_prep":
		v.add_child(UI.hint("편성 탭에서 진형 · 작전을 고칠 수 있다. 상대의 편성은 보이지 않는다."))
	return UI.sect("오늘 저녁 상대", UI.panel(v))


## 결과 칸 —— 혼자 하기의 GameScreen._result_panel 과 같은 꼴: 큰 승리 · 패배, 전투 이름, 잔존 · 수훈 · 기본패 · 선택권 · 민심.
## 서버 Run 의 last_result 가 아니라 본 전투의 결과(x.res)로 그린다 —— 토너먼트는 last_result 가 없고, 어느 전투를 봤는지가 정확하다
func _result_panel(x: Dictionary) -> Control:
	var run: Run = gs.run
	var res: Dictionary = x.res
	var win: bool = bool(res.get("win", false))
	var draw: bool = bool(res.get("draw", false))
	var col := Color("#C6AC7C") if draw else (Color("#8fd4c2") if win else Color("#e0806f"))
	var v := UI.vbox(8)
	var h := UI.hbox(10)
	var big := UI.lbl("무승부" if draw else ("승리" if win else "패배"), 24, col, true)
	big.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(big)
	var tl := UI.lbl(str(x.get("title", res.get("title", ""))), 14, DB.PAL.bamboo)
	tl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(tl)
	v.add_child(h)
	var parts := ["잔존 %d : %d" % [int(res.get("left", 0)), int(res.get("eLeft", 0))]]
	var mvp = res.get("mvp")
	if mvp is Dictionary and str(mvp.get("name", "")) != "":
		parts.append("수훈 %s" % mvp.name)
	if run.last_spoil != null and str(x.get("kind", "")) != "tour":
		parts.append(UI.spoil_bb(run.last_spoil))      # 11/10 토벌 성과 보너스는 금색 "(대승 +M)" (서버 mirror 의 last_spoil)
	if run.ticket_left() > 0:
		parts.append("선택권 %d" % run.ticket_left())
	if not win and int(run.last_hp_loss) > 0:
		parts.append("민심 −%d" % int(run.last_hp_loss))
	v.add_child(UI.result_line(parts))
	if run.over != null:
		v.add_child(UI.rich("[color=%s][b]%s[/b][/color] — %s. 남은 판은 관전한다." % ["#8fd4c2" if run.over.win else "#e0806f", "우승" if run.over.win else "탈락", run.over.msg], 13))
	return UI.panel(v, 12)


## 전투 한 줄 —— 승 · 패 / 이름 / 잔존 + 보기 버튼
func _battle_row(x: Dictionary, seen: bool) -> Control:
	var res: Dictionary = x.res
	var win: bool = bool(res.get("win", false))
	var draw: bool = bool(res.get("draw", false))
	var h := UI.hbox(8)
	var col := "#C6AC7C" if draw else ("#8fd4c2" if win else "#e0806f")
	var r := UI.rich("[color=%s][b]%s[/b][/color]  %s  [color=#8D7B5C]잔존 %d 대 %d[/color]" % [col, "무승부" if draw else ("승리" if win else "패배"),
		str(x.get("title", "")), int(res.get("left", 0)), int(res.get("eLeft", 0))], 14)
	r.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	r.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(r)
	var b := UI.btn("다시 보기" if seen else "보기", func():
		watch = [x]
		watch_next(), "ghost", 36)
	b.add_theme_font_size_override("font_size", 13)
	b.custom_minimum_size = Vector2(78, 36)
	h.add_child(b)
	return h


## 자리 한 줄 —— ✔ 준비 · 이름 · (나) · vs 상대 · 봇 · 끊김 · 멸망. PV · 병사 수는 적지 않는다 (결정 ⑥ · 11/9 사용자)
func _seat_row(i: int, st: String) -> Control:
	var s2: Dictionary = room.seats[i]
	var mark := "✔" if s2.ready and s2.human else "·"
	var mcol := "#8fd4c2" if s2.ready and s2.human else "#5d6a88"
	var who := "[b]%s[/b]" % s2.name
	if i == int(room.you):
		who += "  [color=#8fd4c2](나)[/color]"
	var tags := []
	if not s2.human:
		tags.append("[color=#8D7B5C]봇[/color]")
	elif not s2.online:
		tags.append("[color=#e0806f]끊김 — 봇 대행[/color]")
	if s2.dead:
		tags.append("[color=#e0806f]멸망[/color]")
	if str(s2.get("foe", "")) != "" and st in ["evening_prep", "evening"]:
		tags.append("[color=#8D7B5C]vs %s[/color]" % s2.foe)
	var rt := UI.rich("[color=%s]%s[/color]  %s%s" % [mcol, mark, who, ("   " + "  ".join(tags)) if not tags.is_empty() else ""], 14)
	if not s2.human:
		return rt
	# 11/12 사람 자리 —— 오른쪽에 지금 하는 일(상태 아이콘), 줄은 한마디 말풍선이 붙는 자리
	var h := UI.hbox(6)
	rt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(rt)
	h.add_child(st_view(str(s2.name), str(s2.get("st", ""))))
	anchor(str(s2.name), h)
	return h


## 11/11 사용자: 기록 탭에서 다른 유저의 민심 · 핵심 유닛(기초불신 = 기인 · 초월 · 불멸 · 신화)을 본다 —— 군웅 줄의 재료.
## room = Room.info 의 사전, my_hp · my_key = 내 것(서버 줄보다 지금 Run 이 정확하다). 사람 자리만, 나 먼저 그다음 자리 순.
## 줄 {name, me, online, dead, hp(−1 = 모름), key(Array · 기초불신 id 만, 높은 등급 순), has_key(false = 옛 서버라 모름)}.
## 옛 서버의 줄(hp · key 없음)도 깨지지 않는다 —— hp −1 · has_key false 로 화면에는 「—」
static func peer_rows(room: Dictionary, my_hp: int, my_key: Array) -> Array:
	var out := []
	var you := int(room.get("you", -1))
	var seats: Array = room.get("seats", [])
	for i in seats.size():
		var s = seats[i]
		if not (s is Dictionary) or not bool(s.get("human", false)):
			continue
		var me: bool = i == you
		var hp := -1
		var raw = null
		if me:
			hp = my_hp if my_hp >= 0 else (clampi(int(s.hp), 0, Run.HP_MAX) if s.has("hp") else -1)
			raw = my_key
		else:
			if s.has("hp") and (s.hp is int or s.hp is float):
				hp = clampi(int(s.hp), 0, Run.HP_MAX)
			if s.get("key") is Array:
				raw = s.key
		var key := []
		if raw is Array:
			for k in raw:      # 믿지 않는다 —— 모르는 id · 기초불신이 아닌 카드 · 중복은 거른다
				var ks := str(k)
				if DB.C.has(ks) and Room.is_urgent_unit(ks) and not key.has(ks):
					key.append(ks)
			key.sort_custom(func(a, b):
				var ra := Room.key_rank(a)
				var rb := Room.key_rank(b)
				return ra > rb if ra != rb else a < b)
		var row := {"name": str(s.get("name", "")), "me": me, "online": bool(s.get("online", false)), "dead": bool(s.get("dead", false)),
			"hp": hp, "key": key, "has_key": raw is Array}
		if s.has("st"):
			row["st"] = str(s.st)      # 11/12 지금 하는 일 (Room.seat_status)
		if me:
			out.push_front(row)      # 나는 맨 위
		else:
			out.append(row)
	return out


## 기록 탭의 「군웅」 —— 사람마다 한 칸: 이름 + 민심 게이지(머리띠와 같은 것), 아래에 핵심 유닛 작은 카드 줄 (누르면 디테일창).
## 11/12 사용자: 봇 자리도 줄로 —— 봇에게는 민심이 없다(멸망하지 않는 세력)고 적고, 핵심 유닛은 지금 전력으로 뽑힐 군세의 예시(GameScreen.bot_key —— 봇 군세는 전투마다 새로 뽑는다)
func peers_section() -> Control:
	var run: Run = gs.run
	var seats: Array = room.get("seats", [])
	var v := UI.vbox(8)
	for r in peer_rows(room, run.hp, Room.key_cards(run)):
		v.add_child(peer_row(gs, r))
	for x in seats:
		if x is Dictionary and not bool(x.get("human", false)):
			for b in run.bots:      # 서버의 거울(Room._mirror) —— 봇의 전력 · 성향은 여기에 있다
				if str(b.name) == str(x.get("name", "")):
					v.add_child(peer_row(gs, GameScreen.bot_row(run, b)))
					break
	return UI.sect("군웅 — 민심 · 핵심 유닛", v)


## 한 사람(또는 봇)의 칸 —— 혼자 하기 기록 탭(GameScreen._page_rank)도 같이 쓴다
static func peer_row(scr: GameScreen, r: Dictionary) -> Control:
	var P := DB.PAL
	var v := UI.vbox(6)
	var h := UI.hbox(8)
	var nl := UI.lbl(str(r.name), 16, P.gold if r.me else P.paper, true)
	nl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	nl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	nl.clip_text = true
	h.add_child(nl)
	var tag := ""
	var tcol: Color = P.bamboo_dim
	if r.me:
		tag = "나"
		tcol = P.jade
	elif r.dead:
		tag = "멸망"
		tcol = P.seal
	elif bool(r.get("bot", false)):
		tag = "봇"
	elif not r.online:
		tag = "끊김"
		tcol = P.seal
	if tag != "":
		var tl := UI.lbl(tag, 12, tcol, true)
		tl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(tl)
	if r.has("st") and scr.online != null:
		h.add_child(scr.online.st_view(str(r.name), str(r.st)))      # 11/12 지금 하는 일 (온라인 사람 칸만)
	if bool(r.get("bot", false)):
		var bl := UI.lbl(str(r.get("note", "민심 없음")), 13, P.bamboo_dim)      # 봇은 민심이 없다 —— 전적 · 토벌 실패만
		bl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(bl)
	elif int(r.hp) >= 0:
		var g := GameScreen.HpGauge.new()      # 머리띠의 민심 게이지를 그대로 (30 이하 붉음 · 위험 표시까지)
		g.set_now(float(r.hp))
		g.custom_minimum_size = Vector2(150, 24)
		g.mouse_filter = Control.MOUSE_FILTER_IGNORE
		g.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		g.set_process(false)      # 맥동은 머리띠만 —— 줄마다 매 프레임 다시 그리지 않는다
		h.add_child(g)
	else:
		var dl := UI.lbl("민심 —", 14, P.bamboo_dim)
		dl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(dl)
	v.add_child(h)
	if not r.has_key:
		v.add_child(UI.lbl("핵심 유닛 —", 13, P.bamboo_dim))
	elif r.key.is_empty():
		v.add_child(UI.lbl("핵심 유닛 아직 없음", 13, P.bamboo_dim))
	else:
		if bool(r.get("bot", false)):
			v.add_child(UI.lbl("핵심 유닛 (봇 군세는 전투마다 새로 뽑는다 —— 지금 전력의 예)", 12, P.bamboo_dim))
		var fl := HFlowContainer.new()
		fl.add_theme_constant_override("h_separation", 4)
		fl.add_theme_constant_override("v_separation", 4)
		for k in r.key:
			var t := MiniTile.new().setup(str(k), -1)
			t.custom_minimum_size = Vector2(50, 74)      # 폭 56 미만 = 작은 칸 (초상 · 이름) —— 한 줄 12장
			t.tapped.connect(func(kk): scr.card_info(kk))
			fl.add_child(t)
		v.add_child(fl)
	var pnl := UI.panel(v, 10)
	if r.me:
		pnl.add_theme_stylebox_override("panel", UI.flat(P.ink3, P.gold, 1, 8, 10))
	if scr.online != null and scr.online.in_game and not bool(r.get("bot", false)):
		scr.online.anchor(str(r.name), pnl)      # 11/12 한마디 말풍선이 붙는 자리
	return pnl


func war_page() -> Control:
	var run: Run = gs.run
	var v := UI.vbox(14)
	var st: String = str(room.get("stage", ""))
	if run.over != null and st == "over":
		v.add_child(gs._over_panel())
		return v
	var my: Dictionary = me()
	var watching: bool = st in Room.WATCH_STAGES
	# (a) 단계 카드 —— N일차 · 단계 · 남은 시간 · 지금 할 일
	var head := UI.vbox(4)
	var hr := UI.hbox(8)
	var tl := UI.lbl("%s · %s 단계" % [day_text(), _stage_name()], 20, DB.PAL.paper, true)
	tl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hr.add_child(tl)
	_clock_lbl = UI.lbl(remain_text(), 20, DB.PAL.gold, true)
	_clock_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hr.add_child(_clock_lbl)
	hr.add_child(_say_btn())
	head.add_child(hr)
	var hint := UI.lbl(_stage_hint(), 13, DB.PAL.bamboo)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	head.add_child(hint)
	if run.over != null:
		head.add_child(UI.rich("[color=#e0806f][b]%s[/b][/color] — %s. 남은 판은 관전한다." % ["우승" if run.over.win else "탈락", run.over.msg], 13))
	v.add_child(UI.panel(head))
	# 혼자 남았다 —— 서버가 묻는 중 (시트를 닫았어도 여기서 답할 수 있다)
	if str(room.get("alone", "")) == "ask":
		var av := UI.vbox(6)
		av.add_child(UI.rich("[color=#D9A64B][b]혼자 남았다[/b][/color] — 다른 사람이 모두 멸망했거나 나갔다. 남은 날은 봇만 상대한다.", 14))
		var ah := UI.hbox(8)
		var b1 := UI.btn("계속한다", func(): net.send({"t": "alone", "go": true}), "pri", 46)
		var b2 := UI.btn("방을 닫는다", func(): net.send({"t": "alone", "go": false}), "warn", 46)
		b1.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		ah.add_child(b1)
		ah.add_child(b2)
		av.add_child(ah)
		v.add_child(UI.panel(av))
	# (b) 주 행동 —— 준비 완료 · 준비 취소. 보는 단계에 아직 안 본 전투가 있으면 이유와 함께 잠근다
	if not my.is_empty() and st != "over" and not my.dead:
		var rd: bool = my.ready
		var unseen: bool = watching and not _seen_all and not last_battles.is_empty()
		var disabled: bool = unseen and not rd
		var sub := "다른 사람을 기다리는 중 — 다시 누르면 취소"
		if not rd:
			if disabled:
				sub = "전투를 끝까지 보면 열린다"
			else:
				match st:
					"morning": sub = "모두 준비되면 토벌로" if has_noon() else "모두 준비되면 대전 준비로"
					"noon": sub = "모두 보면 대전 상대가 정해진다"
					"evening_prep": sub = "모두 준비되면 대전"
					"evening": sub = "모두 보면 다음으로"
		v.add_child(UI.act("준비 취소" if rd else "준비 완료", sub, func(): send_ready(not rd), "ghost" if rd else "pri", disabled))
		if st == "morning" and has_noon() and run.quest_open():      # 11/12 험지 토벌 고르기 —— 토벌이 있는 일차의 준비 단계
			v.add_child(gs.quest_hard_btn())
		if watching and not watch.is_empty():
			v.add_child(UI.btn("남은 전투 보기 (%d)" % watch.size(), func(): watch_next(), "gold", 46))
	# (c) 이번 단계 전투 —— 본 전투의 결과 칸 + 한 줄씩
	if not last_battles.is_empty():
		var bv := UI.vbox(8)
		var shown: Dictionary = _last_watched
		if shown.is_empty() and _seen_all and last_battles.size() == 1:
			shown = last_battles[0]      # 재접속 등으로 목록만 받았어도 하나뿐이면 그 결과
		if not shown.is_empty():
			bv.add_child(_result_panel(shown))
		var rows := UI.vbox(6)
		for i in last_battles.size():
			var x: Dictionary = last_battles[i]
			if i > 0:
				rows.add_child(UI.hair())
			rows.add_child(_battle_row(x, _seen_all or not watch.any(func(w): return is_same(w, x))))      # 내용 비교(has)는 큰 결과에 느리다 —— 같은 객체인지만
		bv.add_child(UI.panel(rows, 10))
		v.add_child(UI.sect("이번 단계 전투", bv))
	elif watching:
		v.add_child(UI.sect("이번 단계 전투", UI.panel(UI.hint("볼 전투가 없다 — 관전 중"))))
	# (d) 저녁 상대
	if room.get("foe") != null and st in ["evening_prep", "evening"]:
		v.add_child(_foe_panel())
	# (e) 자리 —— 한 줄씩
	var seats: Array = room.get("seats", [])
	if not seats.is_empty():
		var sv := UI.vbox(5)
		for i in seats.size():
			if i > 0:
				sv.add_child(UI.hair())
			sv.add_child(_seat_row(i, st))
		var hn := seats.filter(func(x): return x.human).size()
		var rn := seats.filter(func(x): return x.human and x.ready).size()
		v.add_child(UI.sect("자리 — 사람 %d · 봇 %d · 준비 %d/%d" % [hn, seats.size() - hn, rn, hn], UI.panel(sv, 10)))
	# (f) 대진표
	if run.tour != null:
		v.add_child(gs._bracket())
	return v


## 점검용 —— 서버 없이 전투 탭을 그려 본다 (--gsheet=onwar:noon 등). 가짜 방 정보 + 지금 Run 으로 토벌 하나를 계산해 '본 전투'로 둔다
func dev_fake_room(stage: String, remain_s := 75.0) -> void:      # remain_s —— 남은 시간 (점검: --gsheet=onwar:morning:6 으로 5초 경고)
	var run: Run = gs.run
	var do_menu := stage.ends_with("+menu")        # "noon+menu" —— 재생 화면의 ⋯ 메뉴(전투 기록실)까지 연다
	stage = stage.trim_suffix("+menu")
	var do_say := stage.ends_with("+say")          # "morning+say" —— 전투 탭 위에 한마디 시트
	stage = stage.trim_suffix("+say")
	var do_rank := stage.ends_with("+rank") or stage.ends_with("+oldrank")      # "morning+rank" —— 기록 탭(군웅 민심 · 핵심 유닛, 11/11). "+oldrank" 는 한 사람이 옛 서버의 줄(hp · key 없음)
	var do_old := stage.ends_with("+oldrank")
	stage = stage.trim_suffix("+oldrank").trim_suffix("+rank")
	var do_watch := do_menu or stage.ends_with("+watch")      # "noon+watch" —— 전투 재생 화면까지 (위 띠의 한마디 · 결과로 버튼 점검)
	stage = stage.trim_suffix("+watch")
	in_game = true
	gs._title.visible = false
	Sfx.music("prep")
	var n_max := clampi(dev_max, 4, 8)
	var seats := [{"name": net.player, "human": true, "online": true, "ready": false, "dead": false, "pv": run.my_pv(), "foe": "", "hp": run.hp, "key": Room.key_cards(run)},
		{"name": "장수214", "human": true, "online": true, "ready": true, "dead": false, "pv": 0, "foe": "", "hp": 72, "key": _dev_key([8, 7, 7, 6, 5, 5])},
		{"name": "장수377", "human": true, "online": false, "ready": false, "dead": false, "pv": 0, "foe": "", "hp": 24, "key": _dev_key([7, 6, 5])}]
	if stage == "lobby":      # 점검용 —— 대기실 (사람 3명 + 빈자리 · 시작 버튼)
		room = {"code": "K7QX", "mode": "fast", "max": n_max, "mode_n": Room.MODES.fast.n, "started": false, "stage": "lobby", "you": 0, "host": true,
			"seats": seats, "quick": [], "emote_n": 0}
		in_game = false
		_show_lobby()
		return
	if do_rank:
		seats.append({"name": "장수590", "human": true, "online": true, "ready": false, "dead": false, "pv": 0, "foe": "", "hp": 55, "key": []})
		if do_old:      # 옛 서버 —— hp · key 가 아예 없다
			seats[3].erase("hp")
			seats[3].erase("key")
		for ki in _dev_key([7, 5]):      # 내 줄에도 몇 장 (점검 전용 —— 저장하지 않는다)
			run.give(ki)
		seats[0].key = Room.key_cards(run)
	for b in run.bots.slice(0, n_max - seats.size()):
		seats.append({"name": b.name, "human": false, "online": false, "ready": true, "dead": false, "pv": 0, "foe": ""})
	run.bots = run.bots.slice(0, n_max - 1)      # 서버의 거울처럼 —— 다른 자리 N-1 개
	if stage in ["evening_prep", "evening"]:
		seats[0].foe = seats[3].name
		seats[3].foe = seats[0].name
		if seats.size() > 4:
			seats[1].foe = seats[4].name
			seats[4].foe = seats[1].name
	var day_no := run.day * 3 + run.phase + 1
	room = {"code": "K7QX", "mode": "fast", "max": n_max, "mode_n": Room.MODES.fast.n, "started": true, "stage": stage, "stage_no": 3,
		"stage_n": Room.STAGE_N.get(stage, stage), "remain": remain_s, "day": run.day, "phase": run.phase, "day_no": day_no, "you": 0, "host": true,
		"seats": seats, "foe": ({"name": seats[3].name, "human": false, "online": false, "epi": "", "w": 3, "l": 1} if stage in ["evening_prep", "evening"] else null),
		"noon": run.day < Run.ONLINE_NOON_DAYS, "act": true, "alone": "", "tour_round": -1, "quick": Room.QUICK_MSGS, "emote_n": Room.EMOTE_N}
	stage_end = Room.now() + remain_s
	_stage_no = 3
	if stage in Room.WATCH_STAGES:
		var q := run.start_quest()
		q.pol = Run.policy_for(q)
		var res := Run.simulate(q, [], q.pol)
		if gs._dev_bonus_r >= 0.0:      # 점검: --gbonus=0.85 로 이긴 것으로 (서버 대신 여기서 보너스를 계산해 mirror 처럼 last_spoil 에 둔다)
			gs._dev_force_bonus(res)
		run.mp = true      # 서버의 Run 처럼 —— 보너스 알림은 클라이언트(GameScreen)가 직접 띄운다
		run.finish_battle(res)
		var prm :={"a": q.a.cards, "fa": q.a.form, "ma": q.a.morale, "ea": q.a.equip, "b": q.b.cards, "fb": q.b.form, "mb": q.b.morale, "eb": q.b.equip,
			"seed": q.seed, "title": q.title, "foe": q.foe, "policy": q.pol, "tra": float(q.a.get("tr_mul", 1.0)), "trb": float(q.b.get("tr_mul", 1.0)), "tb": q.b.get("trait", {})}
		last_battles = [{"title": q.title, "res": res, "kind": "quest", "params": prm}]
		_last_watched = last_battles[0]
		_seen_all = true
		if do_watch:
			_seen_all = false
			watch = last_battles.duplicate()
			gs.go("war")
			watch_next()
			# 점검 출력 —— 재생에서도 전투장수창의 시작 능력치(버프 포함)가 잡히는지 (params → _p)
			for u in res.roster:
				if u.camp != "A":
					continue
				var ss: Dictionary = gs._battle.start_stats(str(u.key))
				if ss.is_empty():
					print("onwar start_stats %s %s: 빈 사전" % [u.key, u.name])
				else:
					var line := "onwar start_stats %s %s: 공 %d→%d · 방 %d→%d · 속 %d→%d · %s" % [u.key, u.name, roundi(ss.atk[0]), roundi(ss.atk[2]),
						roundi(ss["def"][0]), roundi(ss["def"][2]), roundi(ss.spd[0]), roundi(ss.spd[2]), str(ss.line)]
					print(line)
			if do_menu:
				get_tree().create_timer(1.0).timeout.connect(func(): gs._battle.set_side_visible(true))
			elif gs._battle.has_method("show_quick"):
				get_tree().create_timer(1.2).timeout.connect(func(): gs._battle.show_quick("장수214", str(room.quick[0])))      # 한마디 줄 점검
			elif gs._battle.has_method("say_line"):
				get_tree().create_timer(1.2).timeout.connect(func(): gs._battle.say_line("장수214", str(room.quick[0])))
			return
	gs.go("rank" if do_rank else "war")
	if do_say:
		quick_sheet()


## 점검용 —— 등급(8 신화 · 7 불멸 · 6 초월 · 5 = 기인)마다 돌려 가며 카드 id 를 하나씩 (같은 등급은 앞에서부터 겹치지 않게)
func _dev_key(tiers: Array) -> Array:
	var out := []
	var used := {}
	for t in tiers:
		var pool: Array = DB.C.keys().filter(func(k): return DB.is_kiin(k)) if int(t) == 5 else DB.by_tier(int(t))
		for k in pool:
			if not used.has(k):
				used[k] = true
				out.append(k)
				break
	return out


## 점검용 —— --gemote=3 : 받은 이모티콘 팝업(3번) + 한마디 시트. "3,4,5" 는 여러 개(줄), "cmp" 는 8종을 14 · 22 · 40 · 62px 로 나란히 그린 비교 그림
func dev_emote(arg: String) -> void:
	if arg == "cmp":
		var cmp := _EmoteCmp.new()
		cmp.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		cmp.z_index = 60
		gs.add_child(cmp)
		return
	var names := ["장수214", "유비", "조조 맹덕", "장수377"]
	var n := 0
	for t in arg.split(","):
		gs.emote_pop(names[n % names.size()], int(t))
		n += 1
	quick_sheet()


## 8종 비교 그림 (점검용) —— 크기별 (14 · 22 · 40 · 62px) 먹색 바탕에 종이색 선
class _EmoteCmp extends Control:
	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), DB.PAL.ink)
		var f: Font = DB.font_body
		var cols := [14.0, 22.0, 40.0, 62.0]
		var x0 := 70.0
		var y := 40.0
		draw_string(f, Vector2(8, 24), "한마디 이모티콘 8종 (400 기준 좌표 — 화면 720 폭이면 1.8배)", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, DB.PAL.paper)
		for k in Icons.EMOTES.size():
			draw_string(f, Vector2(6, y + 34), "%d %s" % [k, Icons.EMOTE_NAMES[k]], HORIZONTAL_ALIGNMENT_LEFT, -1, 13, DB.PAL.paper)
			var x := x0 + 20.0
			for d in cols:
				Icons.draw(self, Icons.EMOTES[k], Vector2(x, y + 32), d, DB.PAL.paper)
				x += d + 22.0
			Icons.draw(self, Icons.EMOTES[k], Vector2(x + 14, y + 32), 40.0, DB.PAL.gold)
			draw_line(Vector2(0, y + 66), Vector2(size.x, y + 66), Color(DB.PAL.paper, 0.1), 1.0)
			y += 76.0


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
	if r.placed() < 9 and not r.inv.is_empty() and can_act("form"):
		gs.act("auto_deploy")
	elif not me().get("ready", true):
		send_ready(true)
