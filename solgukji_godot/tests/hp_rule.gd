extends Node
## 11/26 방 옵션 「민심 피해 배율」 점검 —— Room.hp_mul 이 사람 자리의 Run.hp_rule 로 들어가고, 패배 피해 미리보기 · 방 정보 · 저장에 실리는가


class FakeSrv:
	var sent := []
	func send(peer, msg) -> void:
		sent.append([peer, msg])
	func room_closed(_code) -> void:
		pass


var fails := 0


func ok(cond: bool, what: String) -> void:
	if not cond:
		fails += 1
	print("%s · %s" % ["통과" if cond else "실패", what])


func _ready() -> void:
	PlayLog.enabled = false
	ok(is_equal_approx(Room.valid_hp(1.5), 1.5) and is_equal_approx(Room.valid_hp(2), 2.0) and is_equal_approx(Room.valid_hp(0.5), 0.5), "허용 값 0.5 · 1.5 · 2")
	ok(is_equal_approx(Room.valid_hp(3), 1.0) and is_equal_approx(Room.valid_hp(null), 1.0) and is_equal_approx(Room.valid_hp("2"), 1.0) and is_equal_approx(Room.valid_hp(-1), 1.0), "이상한 값은 1.0")
	var old := Room.new(FakeSrv.new(), "OLD", "test", 4)
	ok(is_equal_approx(old.hp_mul, 1.0), "옵션 없이 만든 방(옛 클라이언트)은 ×1")
	for mul in [1.0, 1.5, 2.0, 0.5]:
		var srv := FakeSrv.new()
		var r := Room.new(srv, "HP", "test", 4, true, 0, true, mul)
		r.add_human(1, "가", "t1", false)
		r.start()
		var run: Run = r.seats[0].run
		ok(is_equal_approx(run.hp_rule, mul), "×%s 방 —— Run.hp_rule" % str(mul))
		ok(is_equal_approx(float(r.info(0).get("hp", -1.0)), mul), "×%s 방 —— 방 정보 hp" % str(mul))
		ok(is_equal_approx(run.hp_today(), Run.hp_base(run.day) * mul), "×%s 방 —— 오늘 패배 기본 피해" % str(mul))
		var back := Run.new()
		back.from_dict(JSON.parse_string(JSON.stringify(run.to_dict())))
		ok(is_equal_approx(back.hp_rule, mul), "×%s 방 —— 저장 · 전송 뒤에도 그대로" % str(mul))
	var solo := Run.new()
	solo.new_game(7)
	ok(is_equal_approx(solo.hp_rule, 1.0) and is_equal_approx(solo.hp_today(), Run.hp_base(0)), "혼자 하기는 ×1")
	var legacy := Run.new()
	var d := solo.to_dict()
	d.erase("hp_rule")
	legacy.from_dict(d)
	ok(is_equal_approx(legacy.hp_rule, 1.0), "옛 저장(hp_rule 없음)은 ×1")
	print("민심 배율 점검 —— 실패 %d" % fails)
	get_tree().quit(1 if fails > 0 else 0)
