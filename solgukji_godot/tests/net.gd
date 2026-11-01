extends Node
## 서버 점검 —— 실행: godot --headless --path . res://tests/net.tscn [-- --players=3]
## 서버(MatchServer)와 가짜 플레이어 N명을 한 프로세스에 띄워 실제 WebSocket 으로 한 판을 끝까지 돈다.
## 플레이어: 방 만들기 · 코드로 참가 · 시작 · 매 페이즈 징집 → 선택권 → 자동 편성 → 준비 · 전투가 오면 준비.
## 둘째 플레이어는 2일차에 끊었다가 같은 토큰으로 돌아온다 (그동안은 AI 가 대신한다).
## 점검 모드(test)는 멸망하지 않아 토너먼트까지 간다.
## 확인: 모두 끝까지 가는가 · 사람끼리 대전의 승패가 양쪽에서 맞는가 · 오류 메시지가 없는가.

const PORT := 7791

var server: MatchServer
var bots := []                # [{c: NetClient, name, state, room, battles_seen, log}]
var code := ""
var errors := []
var pvp_seen := {}            # "day.phase" -> [[나, 상대, 승?]]
var t0 := 0.0


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
		var b := {"c": c, "name": c.player, "i": i, "state": null, "room": null, "dropped": false, "back": false, "done": false}
		bots.append(b)
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
			if run.over != null and not b.done:
				b.done = true
				print("  %s 끝: %s (%s)" % [b.name, "우승" if run.over.win else "탈락", run.over.msg])
			if d.room.stage == "prep" and run.over == null:
				_play(b, run, d.room)
			# 둘째는 2일차 오전에 끊었다가 1.5초 뒤 같은 토큰으로 돌아온다
			if b.i == 1 and int(run.day) == 1 and not b.dropped:
				b.dropped = true
				var tok: String = c.token
				c.close()
				print("  %s 접속 끊음 (2일차)" % b.name)
				await get_tree().create_timer(1.5).timeout
				c.token = tok
				c.connect_to("ws://127.0.0.1:%d" % PORT)
				b.back = true
		"battles":
			for x in d.list:
				var res: Dictionary = x.res
				if str(x.title) == "대전 · " + b.name or str(res.title) != str(x.title):
					errors.append("%s: 전투 제목이 이상하다 (%s / %s)" % [b.name, x.title, res.title])
				if str(x.title).begins_with("대전 · "):
					var key := "%d.%d" % [d.day, d.phase]
					if not pvp_seen.has(key):
						pvp_seen[key] = []
					pvp_seen[key].append([b.name, str(x.title).trim_prefix("대전 · "), res.win, res.draw])
			c.send({"t": "ready", "on": true})


## 준비 시간에 할 일 —— 상태가 올 때마다 다음 한 걸음
func _play(b: Dictionary, run: Dictionary, room: Dictionary) -> void:
	var c: NetClient = b.c
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
	if not b.has("deployed_at") or b.deployed_at != "%d.%d" % [run.day, run.phase]:
		b.deployed_at = "%d.%d" % [run.day, run.phase]
		c.send({"t": "cmd", "m": "auto_deploy", "a": []})
		return
	var me: Dictionary = room.seats[room.you]
	if not me.ready:
		c.send({"t": "ready", "on": true})


func _process(_dt: float) -> void:
	var el := Time.get_ticks_msec() / 1000.0 - t0
	var all_done := not bots.is_empty() and bots.all(func(b): return b.done)
	if all_done or el > 240.0:
		_report(el, all_done)
		set_process(false)
		get_tree().quit()


func _report(el: float, all_done: bool) -> void:
	var bad := 0
	for key in pvp_seen:
		for x in pvp_seen[key]:
			for y in pvp_seen[key]:
				if x[0] == y[1] and y[0] == x[1] and not x[3] and x[2] == y[2]:
					bad += 1
					errors.append("%s 대전 승패가 양쪽에서 같다: %s vs %s" % [key, x, y])
	var pairs := 0
	for key in pvp_seen:
		pairs += pvp_seen[key].filter(func(x): return pvp_seen[key].any(func(y): return y[0] == x[1])).size()
	print("서버 점검 %.1f초 · 모두 끝 %s · 사람끼리 대전 %d건(양쪽 집계) · 재접속 %s · 오류 %d" % [el, all_done, pairs,
		bots.size() > 1 and bots[1].back, errors.size()])
	print("  가장 큰 메시지 %.0f KB" % (server.max_msg / 1024.0))
	for e in errors.slice(0, 10):
		print("  ", e)
