extends Node
const RoomLog := preload("res://scripts/net/room_log.gd")
## 온라인 방 기록 점검 (11/10) —— 가짜 서버로 Room 을 직접 돌린다. 실행: godot --headless --path . res://tests/room_log.tscn
## ① 기록을 켠 방과 끈 방이 서버로 보내는 메시지가 한 글자도 다르지 않다 (난수 · 상태를 건드리지 않는다 —— 같은 시드로 두 번)
## ② 기록 파일: 사람 수만큼(봇은 없다) · 줄마다 올바른 JSON · start 에 이름 · 끊김/재접속/나감 줄 · 토큰이 없다
## ③ 기록을 끈 방(점검 방은 기본으로 끔)에서는 파일이 없다
## ④ 동의 (11/10) —— rec 없는 사람(시험1)은 파일이 없고, 다른 사람 파일에 그 사람의 이름 · 편성 · 상대 부대 기록이 없다 (players 에서 빠지고 hidden 숫자만 · 전투 상대는 "(비공개)")
## ⑤ 동의를 철회하고 돌아오면(reattach rec=false) 그 사람 파일은 consent_off 로 끝나고 더 쓰지 않는다 · 아무도 동의하지 않은 방은 기록기가 없다

const DIR := "user://playlog_online_roomlog"
var had_rlog := false
const STOP_SLOT := 4          # 이 페이즈 번호(day*3+phase)까지만 돈다 —— 길게 재지 않게

class FakeSrv:
	var out := []
	func send(peer: int, msg: Dictionary) -> void:
		var m := msg.duplicate(true)
		_strip(m)
		out.append(str(peer) + JSON.stringify(m, "", false, true).md5_text())
	func _strip(d) -> void:
		if d is Dictionary:
			d.erase("remain")        # 시계에 따라 달라지는 값
			for k in d:
				_strip(d[k])
		elif d is Array:
			for x in d:
				_strip(x)


func _ready() -> void:
	var fails := []
	_clear()
	if OS.get_cmdline_user_args().has("--full"):      # 끝까지(토너먼트 · over 줄) —— 기록만 켜고 한 번
		_play(true, 999)
		_check_files(fails, true)
		print("FAIL: ", fails if not fails.is_empty() else "없음")
		get_tree().quit(1 if not fails.is_empty() else 0)
		return
	var off := _play(false)
	_check_no_files(fails)
	var on := _play(true)
	if off.size() != on.size():
		fails.append("메시지 수가 다르다: 끔 %d · 켬 %d" % [off.size(), on.size()])
	else:
		for i in off.size():
			if off[i] != on[i]:
				fails.append("메시지 %d 번이 다르다 (기록 때문에 서버 응답이 바뀜)" % i)
				break
	print("메시지 %d개 · 기록 끔/켬 %s" % [on.size(), "같음" if off == on else "다름"])
	_check_files(fails)
	_check_mix(fails)
	print("FAIL: ", fails if not fails.is_empty() else "없음")
	get_tree().quit(1 if not fails.is_empty() else 0)


func _clear() -> void:
	DirAccess.make_dir_recursive_absolute(DIR)
	for fn in DirAccess.get_files_at(DIR):
		DirAccess.remove_absolute(DIR + "/" + fn)


## 같은 시드로 한 방을 STOP_SLOT 까지 돌리고 서버가 보낸 메시지의 해시 목록을 돌려준다
func _play(log_on: bool, stop_slot := STOP_SLOT, rec := [true, true, true], back_rec := true) -> Array:
	RoomLog.test_ok = log_on
	RoomLog.dir = DIR
	var srv := FakeSrv.new()
	var r := Room.new(srv, "LOGT", "test")
	r.rng.seed = 20261110
	for k in 3:
		r.add_human(k + 1, "시험%d" % k, "tk%d" % k, rec[k])
	r.start()
	var left := false
	var back := false
	var n := 0
	while r.stage != "over" and r.day * 3 + r.phase < stop_slot and n < 400:
		n += 1
		for s in r.humans():
			if s.peer >= 0 and r.stage in Room.ACT_STAGES and not s.dead:
				r.on_cmd(s.peer, "do_draw", [])
				r.on_cmd(s.peer, "begin_picks", ["phase", -1])
				r.on_cmd(s.peer, "auto_deploy", [])
				r.on_cmd(s.peer, "nonsense", [1.0, "x"])      # 거절되는 명령도 기록에 ok:false 로 남는다
		var slot := r.day * 3 + r.phase
		if slot == 1 and r.stage == "evening_prep" and not left:
			left = true
			r.remove_peer(2)                  # 시험1 접속 끊김
		if slot == 2 and r.stage == "morning" and left and not back:
			back = true
			r.reattach(22, "tk1", back_rec)   # 같은 토큰으로 돌아옴 (back_rec=false 면 동의를 철회하고)
		if slot == 3 and r.stage == "morning":
			r.on_leave(3)                     # 시험2 스스로 나감
		for s in r.humans():
			if s.peer >= 0:
				r.on_ready(s.peer, true, r.stage_no)
		r.tick()
	had_rlog = r.rlog != null
	r.rlog = null
	return srv.out


func _check_no_files(fails: Array) -> void:
	var n := DirAccess.get_files_at(DIR).size()
	if n != 0:
		fails.append("기록을 껐는데 파일이 %d개" % n)


func _check_files(fails: Array, full := false) -> void:
	var files := Array(DirAccess.get_files_at(DIR)).filter(func(f): return f.ends_with(".jsonl"))
	print("기록 파일 %d개: %s" % [files.size(), str(files)])
	if files.size() != 3:
		fails.append("사람 3명인데 파일 %d개" % files.size())
	var evs := {}
	for fn in files:
		var lines := FileAccess.get_file_as_string(DIR + "/" + fn).split("\n", false)
		var first = null
		var last = null
		var bad := 0
		for ln in lines:
			var d = JSON.parse_string(ln)
			if typeof(d) != TYPE_DICTIONARY or not (d.has("ts") and d.has("ev") and d.has("day") and d.has("phase")):
				bad += 1
				continue
			if first == null:
				first = d
			last = d
			evs[d.ev] = int(evs.get(d.ev, 0)) + 1
			if ln.contains("tk0") or ln.contains("tk1") or ln.contains("tk2") or ln.contains("127.0.0.1"):
				fails.append("%s: 토큰/주소가 기록에 있다" % fn)
		if bad > 0:
			fails.append("%s: 올바르지 않은 줄 %d" % [fn, bad])
		if first == null or first.ev != "start" or not first.has("player") or not first.get("online", false) or str(first.player) not in ["시험0", "시험1", "시험2"]:
			fails.append("%s: start 줄 이상 %s" % [fn, str(first)])
		else:
			print("  %s → %d줄 · 이름 %s · 마지막 %s" % [fn.substr(0, 28), lines.size(), first.player, last.ev])
			if first.player == "시험2" and last.ev != "leave":
				fails.append("나간 사람의 마지막 줄이 leave 가 아니다 (%s)" % last.ev)
			if full and first.player != "시험2" and last.ev != "over":
				fails.append("%s: 끝까지 갔는데 마지막 줄이 over 가 아니다 (%s)" % [first.player, last.ev])
			if first.players.size() != 3 or first.bots.size() != 5 or not first.has("room") or not first.has("seat"):
				fails.append("start 칸 부족 %s" % str(first))
	print("  줄 종류: %s" % str(evs))
	var need := ["start", "act", "stage", "ready", "battle_start", "battle_end", "reward", "phase_end", "disconnect", "reconnect", "leave", "bot_fill"]
	if full:
		need.append("over")
	for k in need:
		if not evs.has(k):
			fails.append("기록에 %s 줄이 하나도 없다" % k)


## 동의 (11/10) —— ④ rec 없는 사람 · ⑤ 철회 · 아무도 동의 안 한 방
func _check_mix(fails: Array) -> void:
	_clear()
	_play(true, 6, [true, false, true])
	var files := Array(DirAccess.get_files_at(DIR)).filter(func(f): return f.ends_with(".jsonl"))
	if files.size() != 2:
		fails.append("동의한 사람이 2명인데 파일 %d개" % files.size())
	var hidden_battles := 0
	for fn in files:
		var txt := FileAccess.get_file_as_string(DIR + "/" + fn)
		if txt.contains("시험1"):
			for ln in txt.split("\n", false):
				if ln.contains("시험1"):
					fails.append("%s: 동의하지 않은 사람 이름이 기록에 있다: %s" % [fn.substr(0, 30), ln.substr(0, 400)])
		for ln in txt.split("\n", false):
			var d = JSON.parse_string(ln)
			if typeof(d) != TYPE_DICTIONARY:
				fails.append("%s: 올바르지 않은 줄" % fn)
				continue
			if d.ev == "start" and (d.players.size() != 2 or int(d.get("hidden", 0)) != 1):
				fails.append("start 의 players/hidden 이상: %s" % str(d))
			if d.ev in ["battle_start", "battle_end"] and d.get("foe_hidden", false):
				hidden_battles += 1
				for k in ["foe", "foe_form", "foe_tac", "foe_morale", "foe_equip", "tr_ratio", "foe_troops", "foe_troops_max"]:
					if d.has(k):
						fails.append("%s: 동의 안 한 상대의 %s 가 남았다" % [d.ev, k])
				if d.foe_name != RoomLog.HIDDEN:
					fails.append("동의 안 한 상대 이름이 남았다: %s" % d.foe_name)
				if d.ev == "battle_end" and (d.units as Array).any(func(u): return u.camp != "A"):
					fails.append("동의 안 한 상대 부대 기록이 남았다")
	print("동의 안 한 사람 1명 —— 파일 %d개 · 이름 없음 · 상대가 그 사람인 전투 줄 %d" % [files.size(), hidden_battles])
	# 철회하고 돌아옴
	_clear()
	_play(true, 6, [true, true, true], false)
	files = Array(DirAccess.get_files_at(DIR)).filter(func(f): return f.ends_with(".jsonl"))
	var found := false
	for fn in files:
		var lines := FileAccess.get_file_as_string(DIR + "/" + fn).split("\n", false)
		var d = JSON.parse_string(lines[0])
		if d.player == "시험1":
			found = true
			var last = JSON.parse_string(lines[lines.size() - 1])
			if last.ev != "consent_off":
				fails.append("철회한 사람의 마지막 줄이 consent_off 가 아니다 (%s)" % last.ev)
			print("철회: 시험1 %d줄 · 마지막 %s" % [lines.size(), last.ev])
	if not found:
		fails.append("철회한 사람의 파일이 없다")
	# 아무도 동의하지 않음 —— 기록기 자체가 없다
	_clear()
	_play(true, 3, [false, false, false])
	if not DirAccess.get_files_at(DIR).is_empty():
		fails.append("아무도 동의하지 않았는데 파일이 있다")
	if had_rlog:
		fails.append("아무도 동의하지 않았는데 기록기가 만들어졌다")
