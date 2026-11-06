extends Node
## 서버 점검 —— 실행: godot --headless --path . res://tests/net.tscn [-- --players=4]
## 서버(MatchServer)와 가짜 플레이어 N명을 한 프로세스에 띄워 실제 WebSocket 으로 한 판을 끝까지 돈다.
## 하루 = 아침(징집 → 선택권 → 조합 → 자동 편성 → 준비) → 점심(토벌이 오면 '본 것'으로 준비) → 저녁 준비(빈 편성 채우고 준비) → 저녁(대전이 오면 준비).
## 둘째 플레이어는 2일차에 끊었다가 같은 토큰으로 돌아온다 (그동안은 봇이 대신한다).
## 점검 모드(test)는 멸망하지 않아 7일째 토너먼트까지 간다.
## 확인: 모두 끝까지 가는가 · 사람끼리 대전의 승패가 양쪽에서 맞는가 · 저녁 준비에 받은 상대와 실제 대전 상대가 같은가 ·
##       사람끼리 이틀 연속 붙지 않는가(11/7 결정 ②) · 어제 상대와 다시 붙지 않는가(결정 ①) · 오류 메시지가 없는가.

const PORT := 7791

var server: MatchServer
var bots := []                # [{c: NetClient, name, state, room, …}]
var code := ""
var errors := []
var pvp_seen := {}            # "day.phase" -> [[나, 상대, 승?, 무?]]
var foe_log := {}             # 이름 -> {day_no: 상대 이름}  (저녁 준비에 받은 상대)
var human_names := []
var t0 := 0.0
var stage_count := {}         # 단계 이름 -> 본 횟수 (첫 플레이어 기준)


func _ready() -> void:
	var args := {}
	for s in OS.get_cmdline_user_args():
		var kv := s.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	var n := int(args.get("players", "3"))
	server = MatchServer.new()
	server.port = PORT
	add_child(server)
	t0 = Time.get_ticks_msec() / 1000.0
	for i in n:
		var c := NetClient.new()
		c.player = "시험%d" % i
		c.token = ""
		add_child(c)
		var b := {"c": c, "name": c.player, "i": i, "state": null, "room": null, "dropped": false, "back": false, "done": false,
			"sno": -1}
		bots.append(b)
		human_names.append(c.player)
		foe_log[c.player] = {}
		c.message.connect(func(d): _on_msg(b, d))
		c.connect_to("ws://127.0.0.1:%d" % PORT)


func _on_msg(b: Dictionary, d: Dictionary) -> void:
	var c: NetClient = b.c
	match str(d.t):
		"error":
			errors.append("%s: %s" % [b.name, d.msg])
		"rooms":
			if b.i == 0 and code == "" and not b.has("created"):
				b.created = true
				c.send({"t": "create", "mode": "test"})
			elif b.i > 0 and code != "" and b.room == null:
				c.send({"t": "join", "code": code})
		"room":
			b.room = d.room
			if b.i == 0:
				code = d.room.code
				var hs: int = d.room.seats.filter(func(s): return s.human).size()
				if hs == bots.size() and not d.room.started:
					c.send({"t": "start"})
				elif hs == 1:
					for o in bots.slice(1):
						if o.room == null and o.c.is_open():
							o.c.send({"t": "list"})
		"state":
			b.state = d
			b.room = d.room
			var run: Dictionary = d.run
			var rm: Dictionary = d.room
			if int(rm.stage_no) != b.sno:
				b.sno = int(rm.stage_no)
				if b.i == 0:
					stage_count[rm.stage] = stage_count.get(rm.stage, 0) + 1
				# 저녁 준비 —— 받은 상대를 적어 둔다 (PV 가 실려 오면 안 된다, 결정 ⑥)
				if rm.stage == "evening_prep" and rm.get("foe") != null:
					var f: Dictionary = rm.foe
					if f.has("pv"):
						errors.append("%s: 상대 정보에 PV 가 실려 있다" % b.name)
					foe_log[b.name][int(rm.day_no)] = str(f.name)
			if rm.get("alone", "") == "ask":
				c.send({"t": "alone", "go": true})
			if run.over != null and not b.done:
				b.done = true
				print("  %s 끝: %s (%s)" % [b.name, "우승" if run.over.win else "탈락", run.over.msg])
			if (rm.stage in Room.ACT_STAGES) and run.over == null:
				_play(b, run, rm)
			# 둘째는 2일차 오전에 끊었다가 1.5초 뒤 같은 토큰으로 돌아온다
			if b.i == 1 and int(run.day) == 1 and not b.dropped:
				b.dropped = true
				var tok: String = c.token
				c.close()
				print("  %s 접속 끊음 (2일차 · %s)" % [b.name, rm.stage])
				await get_tree().create_timer(1.5).timeout
				c.token = tok
				c.connect_to("ws://127.0.0.1:%d" % PORT)
				b.back = true
		"battles":
			var dn := int(d.day) * 3 + int(d.phase) + 1
			for x in d.list:
				var res: Dictionary = x.res
				if str(x.title) == "대전 · " + b.name or str(res.title) != str(x.title):
					errors.append("%s: 전투 제목이 이상하다 (%s / %s)" % [b.name, x.title, res.title])
				if str(x.title).begins_with("대전 · "):
					var foe := str(x.title).trim_prefix("대전 · ")
					var key := "%d.%d" % [d.day, d.phase]
					if not pvp_seen.has(key):
						pvp_seen[key] = []
					pvp_seen[key].append([b.name, foe, res.win, res.draw])
					# 저녁 준비에 받은 상대와 같은가 (끊겨 있던 동안은 못 받았을 수 있다)
					if foe_log[b.name].has(dn) and foe_log[b.name][dn] != foe:
						errors.append("%s: %d일차 저녁 상대가 다르다 (준비 때 %s · 대전 %s)" % [b.name, dn, foe_log[b.name][dn], foe])
					foe_log[b.name][dn] = foe
			if not bool(d.get("seen", false)):
				c.send({"t": "ready", "on": true, "sno": int(d.stage_no)})


## 아침 · 저녁 준비에 할 일 —— 상태가 올 때마다 다음 한 걸음
func _play(b: Dictionary, run: Dictionary, room: Dictionary) -> void:
	var c: NetClient = b.c
	if room.stage == "morning":
		if not run.drawn and int(DB.D.DRAWS[int(run.day)]) > 0:
			c.send({"t": "cmd", "m": "do_draw", "a": []})
			return
		if not run.picked:
			c.send({"t": "cmd", "m": "begin_picks", "a": ["phase", -1]})
			return
		var tk: Dictionary = run.get("tickets", {})
		var tt: Array = tk.keys().filter(func(x): return int(tk[x]) > 0)
		if not tt.is_empty():
			var pl: Array = DB.by_tier(int(tt[0]))
			pl.sort_custom(func(x, y): return DB.C[x].tr > DB.C[y].tr)
			c.send({"t": "cmd", "m": "pick", "a": [pl[b.i % mini(6, pl.size())]]})
			return
		# 조합할 수 있으면 높은 등급부터 하나씩
		var r := Run.new()
		r.from_dict(run.duplicate(true))
		for t in range(8, 1, -1):
			for k in DB.by_tier(t):
				if r.can_forge(k):
					c.send({"t": "cmd", "m": "forge", "a": [k]})
					return
	var key := "%d.%d.%s" % [run.day, run.phase, room.stage]
	if not b.has("deployed_at") or b.deployed_at != key:
		b.deployed_at = key
		c.send({"t": "cmd", "m": "auto_deploy", "a": []})
		return
	var me: Dictionary = room.seats[room.you]
	if not me.ready:
		c.send({"t": "ready", "on": true, "sno": int(room.stage_no)})


func _process(_dt: float) -> void:
	var el := Time.get_ticks_msec() / 1000.0 - t0
	var all_done := not bots.is_empty() and bots.all(func(b): return b.done)
	if all_done or el > 300.0:
		_report(el, all_done)
		set_process(false)
		get_tree().quit()


func _report(el: float, all_done: bool) -> void:
	for key in pvp_seen:
		for x in pvp_seen[key]:
			for y in pvp_seen[key]:
				if x[0] == y[1] and y[0] == x[1] and not x[3] and x[2] == y[2]:
					errors.append("%s 대전 승패가 양쪽에서 같다: %s vs %s" % [key, x, y])
	var pairs := 0
	for key in pvp_seen:
		pairs += pvp_seen[key].filter(func(x): return pvp_seen[key].any(func(y): return y[0] == x[1])).size()
	# 상대 선정 규칙 —— 어제 상대와 오늘 상대가 같으면 안 되고, 사람끼리 이틀 연속이면 안 된다
	var hh := 0
	var repeat := 0
	var hh_streak := 0
	for nm in foe_log:
		var fl: Dictionary = foe_log[nm]
		for dn in fl:
			if fl[dn] in human_names:
				hh += 1
			if fl.has(dn - 1):
				if fl[dn - 1] == fl[dn]:
					repeat += 1
					errors.append("%s: %d일차와 %d일차 상대가 같다 (%s)" % [nm, dn - 1, dn, fl[dn]])
				if (fl[dn - 1] in human_names) and (fl[dn] in human_names):
					hh_streak += 1
					errors.append("%s: 사람과 이틀 연속 붙었다 (%d일차 %s · %d일차 %s)" % [nm, dn - 1, fl[dn - 1], dn, fl[dn]])
	print("서버 점검 %.1f초 · 모두 끝 %s · 사람끼리 대전 %d건(양쪽 집계) · 재접속 %s · 오류 %d" % [el, all_done, pairs,
		bots.size() > 1 and bots[1].back, errors.size()])
	print("  단계 횟수(첫 플레이어): %s" % str(stage_count))
	print("  저녁 상대 중 사람 %d건 · 어제와 같은 상대 %d건 · 사람과 이틀 연속 %d건" % [hh, repeat, hh_streak])
	print("  가장 큰 메시지 %.0f KB" % (server.max_msg / 1024.0))
	for e in errors.slice(0, 10):
		print("  ", e)
