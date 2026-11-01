class_name Online
extends Node
## 온라인 대전 —— 집 PC 서버(MatchServer)에 붙는다. 게임 화면(GameScreen)은 그대로 쓰고,
## 행동(act)은 서버에도 보내며, 서버가 돌려준 상태(Run)로 화면을 바꾼다.
## 접속 시트(주소·이름·방 목록·방 만들기·코드로 참가) → 대기실(코드·자리·시작) → 게임.
## 전투는 서버가 계산해 보낸 결과를 차례로 재생한다(1단계 —— 자동 전투). 다 보면 '준비 완료'를 보낸다.
## 끊기면 3초마다 다시 붙는다 —— 토큰이 같아 진행 중인 자리로 돌아간다.

var gs: GameScreen
var net: NetClient
var rooms := []
var room := {}                # 서버가 준 방 정보 (Room.info)
var in_game := false
var stage_end := 0.0          # 이 기기 시계로 지금 단계가 끝나는 시각
var watch := []               # 남은 볼 전투 [{title, res}]
var last_battles := []        # 이번 페이즈 전투 (다시 보기)
var lobby: Control
var _status := "접속 전"
var dev_auto := false         # 점검용 —— 준비 시간에 알아서 징집·선택권·조합·편성·준비 (--gauto)
var _retry := -1.0
var _leaving := false
var _url_edit: LineEdit
var _name_edit: LineEdit
var _code_edit: LineEdit
var _tick := 0.0


func _ready() -> void:
	net = NetClient.new()
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

func connect_sheet() -> void:
	var b := gs.open_sheet("온라인 대전")
	b.add_child(UI.hint("집 PC 에서 server.bat 을 띄우고, 그 PC 의 주소를 넣는다. 같은 와이파이면 ws://192.168.x.x:7777, 밖에서는 공유기 포트포워딩 주소나 Cloudflare 터널 주소(wss://…)."))
	var row := UI.vbox(4)
	row.add_child(UI.lbl("서버 주소", 14, DB.PAL.bamboo))
	_url_edit = LineEdit.new()
	_url_edit.text = net.url
	_url_edit.custom_minimum_size = Vector2(0, 48)
	_url_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
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
		_status = "접속 중…"
		_leaving = false
		net.connect_to(_url_edit.text)
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
			if not in_game:
				in_game = true
				_hide_lobby()
				gs.close_sheet()
				gs._title.visible = false
				gs.go("draw")
				if dev_auto:
					_dev_step()
				return
			if not gs.battle_visible():
				gs.render()
			if dev_auto:
				_dev_step()
		"battles":
			last_battles = d.list
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


func can_act() -> bool:
	return in_game and room.get("stage", "") == "prep" and gs.run != null and gs.run.over == null


func me() -> Dictionary:
	if room.is_empty() or int(room.you) < 0:
		return {}
	return room.seats[int(room.you)]


func remain() -> float:
	return maxf(0.0, stage_end - Room.now())


func clock_text() -> String:
	var st: String = room.get("stage", "")
	var r := int(ceil(remain()))
	match st:
		"prep": return "  ·  준비 %d:%02d" % [r / 60, r % 60]
		"watch": return "  ·  관전 %d:%02d" % [r / 60, r % 60]
		"over": return "  ·  끝"
	return ""


# ───────── 전투 재생 ─────────

func watch_next() -> void:
	if watch.is_empty():
		if gs.battle_visible():
			gs.hide_battle()
			# 다 봤으면 준비 완료 —— 다시 누르면 취소된다
			if room.get("stage", "") == "watch":
				net.send({"t": "ready", "on": true})
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
	match room.get("stage", ""):
		"prep": return "준비 시간 %d:%02d — 징집·조합·편성을 마치고 '준비 완료'. 모두 준비되면 바로 전투" % [r / 60, r % 60]
		"watch": return "전투 결과 %d:%02d — 다 보면 '준비 완료'. 모두 준비되면 다음 페이즈" % [r / 60, r % 60]
		"over": return "판이 끝났다"
	return ""


func war_page() -> Control:
	var run: Run = gs.run
	var v := UI.vbox(16)
	if run.over != null and room.get("stage", "") == "over":
		v.add_child(gs._over_panel())
		return v
	var head := UI.vbox(6)
	head.add_child(UI.rich("[font_size=20][b]%s요일 %s[/b][/font_size]   [color=#8D7B5C]온라인 방 %s · %s[/color]" % [
		Run.DAYNAME[run.day], Run.PHASE_N[run.phase], room.code, room.mode_n]))
	_clock_lbl = UI.lbl(_stage_text(), 16, DB.PAL.gold)
	_clock_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	head.add_child(_clock_lbl)
	if run.over != null:
		head.add_child(UI.rich("[color=#e0806f][b]%s[/b][/color] — %s. 남은 판은 관전한다." % ["우승" if run.over.win else "탈락", run.over.msg]))
	v.add_child(UI.panel(head))
	var my: Dictionary = me()
	if not my.is_empty() and room.stage != "over":
		var rd: bool = my.ready
		var b := UI.act("준비 취소" if rd else "준비 완료",
			"다른 사람을 기다리는 중" if rd else ("토벌과 대전이 시작된다" if room.stage == "prep" else "다음 페이즈로"),
			func(): net.send({"t": "ready", "on": not rd}), "ghost" if rd else "pri")
		v.add_child(b)
	# 자리
	var sv := UI.vbox(4)
	for i in room.seats.size():
		var st: Dictionary = room.seats[i]
		var mark := "✔" if st.ready and st.human else ("·" if st.human else "봇")
		var col := "#8fd4c2" if st.ready and st.human else "#8D7B5C"
		var who := "[b]%s[/b]%s" % [st.name, " (나)" if i == int(room.you) else ""]
		var tag := "" if st.online or not st.human else "  [color=#e0806f]끊김 — AI 대행[/color]"
		if st.dead:
			tag += "  [color=#e0806f]멸망[/color]"
		sv.add_child(UI.rich("[color=%s]%s[/color]  %s  [color=#C6AC7C]%d PV[/color]%s" % [col, mark, who, st.pv, tag], 15))
	var two := UI.vbox(16)
	var sp := UI.sect("자리 — 사람 %d · 봇 %d" % [room.seats.filter(func(x): return x.human).size(), room.seats.filter(func(x): return not x.human).size()], UI.panel(sv))
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	two.add_child(sp)
	# 이번 페이즈 전투
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
		bv.add_child(UI.hint("준비 시간이 끝나면 서버가 토벌과 대전을 치른다."))
	if run.last_spoil != null:
		bv.add_child(UI.hint("기본패 %d장 획득 — %s" % [run.last_spoil.n, run.last_spoil.src]))
	if run.ticket_left() > 0:
		bv.add_child(UI.rich("[color=#D9A64B]선택권 %d장 — 다음 준비 시간에 징집 화면에서[/color]" % run.ticket_left(), 14))
	var bp := UI.sect("이번 페이즈 전투", UI.panel(bv))
	bp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	two.add_child(bp)
	v.add_child(two)
	if run.tour != null:
		v.add_child(gs._bracket())
	v.add_child(UI.hint("온라인 1단계 — 전투는 양쪽 모두 자동(고유기·군령을 AI 가). 준비 시간에 편성을 끝내지 못하면 서버가 자동 편성한다. 접속이 끊기면 AI 가 대신 진행하고, 다시 들어오면 넘겨받는다."))
	return v


## 점검용 자동 플레이 —— 상태가 올 때마다 한 걸음
func _dev_step() -> void:
	var r: Run = gs.run
	if not can_act():
		return
	if not r.drawn and r.draws_n() > 0:
		gs.act("do_draw")
	elif not r.picked:
		gs.act("begin_picks", ["phase", -1])
	elif r.ticket_left() > 0:
		var pl: Array = DB.by_tier(r.ticket_tiers()[0])
		pl.sort_custom(func(x, y): return DB.C[x].tr > DB.C[y].tr)
		gs.act("pick", [pl[randi() % mini(6, pl.size())]])
	elif r.placed() < 9 and not r.inv.is_empty():
		gs.act("auto_deploy")
	elif not me().get("ready", true):
		net.send({"t": "ready", "on": true})
