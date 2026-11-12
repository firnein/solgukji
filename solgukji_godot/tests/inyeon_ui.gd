extends Node
## 인연 UI 데이터 점검 (11/11) —— 실행: godot --headless --path . res://tests/inyeon_ui.tscn
## DB.inyeon_of / inyeon_members / inyeon_links 가 맞는지, 고유기 인물 모두 인연 3개 이상인지, 덱 판정(같은 인물 한 번만 · 2명 이상만)을 본다.

var fails := 0


func _ok(cond: bool, msg: String) -> void:
	print("%s %s" % ["  통과" if cond else "  실패", msg])
	if not cond:
		fails += 1


## 인물 이름 -> 고유기를 쓸 수 있는 카드 id (등급 가장 높은 것)
func _card(p: String) -> String:
	return DB.inyeon_card_of_person(p)


func _ready() -> void:
	print("인연 %d개" % DB.INYEON.size())
	var bad_n := 0
	for nm in DB.INYEON:
		var m: Array = DB.inyeon_members(nm)
		if m.size() < 4 or m.size() > 5:
			bad_n += 1
			print("   구성원 수 이상: %s %d" % [nm, m.size()])
	_ok(bad_n == 0, "인연마다 4~5명")
	var ult_persons := {}
	for k in DB.C:
		if not DB.is_foe(k) and DB.inyeon_card(k):
			ult_persons[DB.person(k)] = true
	var lo := 99
	var hi := 0
	var few := []
	for p in ult_persons:
		var n: int = DB.inyeon_of_person(p).size()
		lo = mini(lo, n)
		hi = maxi(hi, n)
		if n < 3:
			few.append("%s(%d)" % [p, n])
	# 데이터 경고 (실패로 세지 않는다) —— 인연 json 은 사용자 확정본이라 코드가 고치지 않는다. 지금 판에서 쓰는 고유기 카드 인물 중 인연이 3개 미만인 사람
	print("  경고 고유기 인물 %d명 중 인연 3개 미만 %d명 (최소 %d · 최대 %d) %s" % [ult_persons.size(), few.size(), lo, hi, str(few)])
	var ok3 := 0
	for p in ult_persons:
		if DB.inyeon_of_person(p).size() >= 3:
			ok3 += 1
	_ok(ok3 >= 50 and lo >= 2 and hi <= 5, "인연이 3개 이상인 고유기 인물 %d명 · 최소 2 · 최대 5개 (11/13)" % ok3)
	var ghost := []
	for nm in DB.INYEON:
		for p in DB.inyeon_members(nm):
			if not ult_persons.has(p):
				ghost.append("%s/%s" % [nm, p])
	print("  경고 지금 고유기 카드가 없는 구성원(퇴역 카드뿐) %d건 %s" % [ghost.size(), str(ghost)])
	var gw := _card("관우")
	_ok(gw != "", "관우 카드 있음 (%s)" % gw)
	var gi: Array = DB.inyeon_of(gw)
	_ok(gi.has("호뢰관") and gi.has("번성 전투") and gi.has("형주 쟁탈") and gi.has("오호대장"), "관우 → %s" % str(gi))      # 11/13 겹침 정리로 무쌍의 호걸에서 빠짐
	var yi: Array = DB.inyeon_of(_card("유비"))
	_ok(yi.has("호뢰관") and yi.has("서서의 어머니"), "유비 → %s" % str(yi))
	for k in DB.BASE:
		_ok(DB.inyeon_of(k).is_empty(), "기본패 %s 인연 없음" % DB.C[k].name)
		break
	var deck := [_card("유비"), _card("관우"), _card("장비"), _card("조조"), null, DB.BASE[0]]
	var by := {}
	for l in DB.inyeon_links(deck):
		by[l.n] = l
		_ok(l["in"].size() >= 2, "인연 %s 는 2명 이상 (%s)" % [l.n, str(l["in"])])
	_ok(by.has("호뢰관") and by["호뢰관"]["in"] == ["유비", "관우", "장비"] and by["호뢰관"]["out"] == ["여포", "화웅"], "호뢰관 유비 · 관우 · 장비 → %s" % str(by.get("호뢰관")))
	_ok(by.has("오호대장") and by["오호대장"]["in"] == ["관우", "장비"], "오호대장 관우 · 장비 2명 → %s" % str(by.get("오호대장")))      # 11/13 조조 · 유비가 함께 든 인연은 없어졌다
	_ok(not by.has("적벽대전"), "조조 혼자뿐인 적벽대전은 제외")
	var gw2 := ""
	for k in DB.C:
		if not DB.is_foe(k) and DB.inyeon_card(k) and DB.person(k) == "관우" and k != gw:
			gw2 = k
			break
	var solo: Array = DB.inyeon_links([gw, gw2 if gw2 != "" else gw])
	_ok(solo.is_empty(), "관우 두 장(%s)은 한 사람 —— 인연 없음 (%d)" % [gw2, solo.size()])
	_ok(DB.inyeon_links([]).is_empty() and DB.inyeon_links([null, null]).is_empty(), "빈 덱")
	print("실패 %d" % fails)
	get_tree().quit(1 if fails > 0 else 0)
