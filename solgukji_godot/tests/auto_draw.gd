extends Node
## 11/25 자동 징집 점검 —— 준비 단계(아침)가 열릴 때마다 사람 자리가 기본패를 정확히 한 번 받는가
## ① 온라인: Room 을 직접 돌린다 —— 아침마다 받았는지 · 받은 수(DRAWS + 징병) · 중복 do_draw 가 조용히 넘어가는지(오류 · 패 변화 없음)
##    · 끊긴 자리(봇 대행 _fill → bot_prepare) · 재접속이 두 번 받게 하지 않는지 · 기록(RoomLog) 줄에 auto:true
## ② 혼자 하기: GameScreen.render 가 새 판 · 다음 페이즈 · 받기 전 저장 이어하기에서 한 번만 받는지, 받은 뒤 저장을 이어하면 안 받는지
## 실행: <godot> --headless --path . res://tests/auto_draw.tscn

const RoomLog := preload("res://scripts/net/room_log.gd")
const Tac := preload("res://scripts/tactics.gd")

class FakeSrv:
	var out := []
	func send(peer: int, msg: Dictionary) -> void:
		out.append([peer, msg])


var fails := []
const DIR := "user://test_auto_draw_log"


func _fail(s: String) -> void:
	if fails.size() < 40:
		fails.append(s)


func _ready() -> void:
	Run.dev_nosave = true
	_online()
	await _solo()
	print("FAIL: ", fails if not fails.is_empty() else "없음")
	get_tree().quit(1 if not fails.is_empty() else 0)


func _base_n(r: Run) -> int:
	var n := 0
	for k in DB.BASE:
		n += int(r.inv.get(k, 0))
	return n


# ───────── ① 온라인 ─────────

func _online() -> void:
	RoomLog.test_ok = true
	RoomLog.dir = DIR
	DirAccess.make_dir_recursive_absolute(DIR)
	for f in DirAccess.get_files_at(DIR):
		DirAccess.remove_absolute(DIR + "/" + f)
	var srv := FakeSrv.new()
	var r := Room.new(srv, "ADRW", "test")
	r.rng.seed = 20261125
	for k in 3:
		r.add_human(k + 1, "시험%d" % k, "tk%d" % k, true)
	r.start()
	var mornings := 0
	var seen_no := -1
	var left := false
	var back := false
	var guard := 0
	var draws := {}      # 자리 -> 아침마다 받은 last_draw (같은 배열이면 다시 받지 않은 것)
	while r.stage != "over" and r.day < 4 and guard < 300:
		guard += 1
		if r.stage_no != seen_no and r.stage == "morning":
			print("  아침 %d일차 p%d" % [r.day + 1, r.phase])
		if r.stage == "morning" and r.stage_no != seen_no:
			seen_no = r.stage_no
			mornings += 1
			for s in r.humans():
				if s.dead or s.run == null:
					continue
				var rr: Run = s.run
				var i := r.seats.find(s)
				if not rr.drawn or rr.last_draw.size() < rr.draws_n():
					_fail("%d일차 p%d %s: 아침이 열렸는데 자동 징집 %s · %d장 (기대 %d 이상)" % [r.day + 1, r.phase, s.name, rr.drawn, rr.last_draw.size(), rr.draws_n()])
				draws[i] = rr.last_draw
				# 이미 받은 징집을 또 보낸다 —— 패 · 기록 그대로, 오류 없이
				if s.peer >= 0:
					var b0 := _base_n(rr)
					var n_out := srv.out.size()
					r.on_cmd(s.peer, "do_draw", [], 900 + mornings)
					if _base_n(rr) != b0 or not is_same(rr.last_draw, draws[i]):
						_fail("%d일차 p%d %s: 중복 do_draw 가 패를 바꿨다" % [r.day + 1, r.phase, s.name])
					for m in srv.out.slice(n_out):
						if str(m[1].get("t", "")) == "error" or (str(m[1].get("t", "")) == "toast" and str(m[1].get("kind", "")) == "bad"):
							_fail("%d일차 p%d %s: 중복 do_draw 에 오류 · 거절 알림 %s" % [r.day + 1, r.phase, s.name, str(m[1])])
		var slot := r.day * 3 + r.phase
		if slot == 1 and r.stage == "noon" and not left:
			left = true
			r.remove_peer(2)      # 시험1 끊김 —— 다음 아침들은 봇 대행(_fill)이 채운다
		if slot == 3 and r.stage == "morning" and left and not back:
			back = true
			var rr: Run = r.seats[1].run
			var ld = rr.last_draw
			r.reattach(22, "tk1", true)      # 재접속 —— 다시 받지 않는다
			if not is_same(rr.last_draw, ld):
				_fail("재접속에 징집을 다시 받았다")
		for s in r.humans():
			if s.peer >= 0 and r.stage in Room.ACT_STAGES and not s.dead:
				r.on_cmd(s.peer, "begin_picks", ["phase", -1])
				r.on_cmd(s.peer, "auto_deploy", [])
		# 단계가 끝나기 전(대행 _fill 뒤) —— 이번 아침의 기본패가 그대로인가
		var pre_morning := r.stage == "morning"
		for s in r.humans():
			s.ready = true
		r.stage_end = 0.0
		r.tick()
		if pre_morning:
			for s in r.humans():
				var i := r.seats.find(s)
				if not s.dead and s.run != null and draws.has(i) and not is_same(s.run.last_draw, draws[i]) and r.stage != "morning":
					_fail("%d일차 %s: 아침이 끝나며(대행 · 다른 명령) 기본패를 다시 받았다" % [r.day + 1, s.name])
	if mornings < 6:
		_fail("아침이 %d번뿐 (6 이상 기대)" % mornings)
	# 기록 —— 자동으로 받은 줄은 act/do_draw + auto:true, 아침 수만큼 (끊긴 자리도 받는다), 사람이 누른 do_draw 줄은 없다
	var rl = r.rlog
	r.rlog = null
	if rl != null:
		rl.close_all()
	var auto_n := 0
	var hand_n := 0
	for fn in DirAccess.get_files_at(DIR):
		for ln in FileAccess.get_file_as_string(DIR + "/" + fn).split("\n", false):
			var d = JSON.parse_string(ln)
			if d is Dictionary and str(d.get("ev", "")) == "act" and str(d.get("m", "")) == "do_draw":
				if bool(d.get("auto", false)):
					auto_n += 1
				else:
					hand_n += 1
	if auto_n < mornings * 3 - 3 or hand_n != 0:
		_fail("기록: 자동 do_draw 줄 %d (아침 %d × 3 근처 기대) · 사람 do_draw 줄 %d (0 기대)" % [auto_n, mornings, hand_n])
	print("온라인: 아침 %d번 · 기록 자동 징집 %d줄 · 중복 명령 무시 확인" % [mornings, auto_n])
	RoomLog.test_ok = false


# ───────── ② 혼자 하기 ─────────

func _solo() -> void:
	PlayLog.enabled = false
	print("혼자 하기 시작")
	var gs = load("res://scenes/game.tscn").instantiate()
	add_child(gs)
	for i in 3:
		await get_tree().process_frame
	var r := Run.new()
	r.new_game(11)
	var b0 := _base_n(r)
	gs.run = r
	gs._title.visible = false
	gs.go("draw")
	await get_tree().process_frame
	if not r.drawn or _base_n(r) != b0 + r.draws_n() or r.last_draw.size() != r.draws_n():
		_fail("혼자 하기 새 판: 자동 징집 %s · 기본패 %d → %d (기대 +%d)" % [r.drawn, b0, _base_n(r), r.draws_n()])
	if gs._draw_cta_node != null and is_instance_valid(gs._draw_cta_node):
		_fail("자동 징집 뒤에도 「징집하기」 버튼이 있다")
	var b1 := _base_n(r)
	gs.render()
	gs.go("forge")
	gs.go("draw")
	if _base_n(r) != b1:
		_fail("다시 그리기에 또 받았다 %d → %d" % [b1, _base_n(r)])
	# 다음 페이즈 —— 한 번 더, 정확히 한 번
	for ph in 4:
		r.advance()
		var b2 := _base_n(r)
		var want := r.draws_n() + r.tk_draw
		gs.go("draw")
		gs.render()
		if not r.drawn or _base_n(r) != b2 + want:
			_fail("혼자 하기 %d일차 p%d: 기본패 %d → %d (기대 +%d)" % [r.day + 1, r.phase, b2, _base_n(r), want])
	# 받은 뒤 저장 → 이어하기: 안 받는다
	var d := r.to_dict()
	var r2 := Run.new()
	r2.from_dict(JSON.parse_string(JSON.stringify(d)))
	var b3 := _base_n(r2)
	gs.run = r2
	gs.go("draw")
	if _base_n(r2) != b3:
		_fail("받은 뒤 저장을 이어하니 또 받았다 %d → %d" % [b3, _base_n(r2)])
	# 받기 전 저장(옛 저장) → 이어하기: 받는다
	var r3 := Run.new()
	r3.new_game(12)
	r3.advance()
	var b4 := _base_n(r3)
	var r4 := Run.new()
	r4.from_dict(JSON.parse_string(JSON.stringify(r3.to_dict())))
	gs.run = r4
	gs.go("draw")
	if not r4.drawn or _base_n(r4) != b4 + r4.draws_n():
		_fail("받기 전 저장을 이어하니 %s · %d → %d (기대 +%d)" % [r4.drawn, b4, _base_n(r4), r4.draws_n()])
	# 징병(연구) —— 받은 뒤 얻으면 그 자리에서 +2
	var b5 := _base_n(r4)
	var n5 := r4.last_draw.size()
	r4._tk_econ(Tac.card("징병"))
	if _base_n(r4) != b5 + 2 or r4.last_draw.size() != n5 + 2 or r4.tk_draw != 0:
		_fail("받은 뒤 징병: 기본패 %d → %d · last_draw %d → %d · tk_draw %d (기대 +2 · +2 · 0)" % [b5, _base_n(r4), n5, r4.last_draw.size(), r4.tk_draw])
	print("혼자 하기: 새 판 · 다음 페이즈 4번 · 이어하기(받은 뒤 · 받기 전) · 징병 확인")
	gs.queue_free()
