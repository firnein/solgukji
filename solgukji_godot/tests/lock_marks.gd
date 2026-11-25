extends Node
## 선점 · 사망 · 재료 선점 표시 점검 (11/25 사용자 "멀티에서 다른 사람이 먼저 선점한게 표기가 안되는 부분이 많음")
## 실행: godot --headless --path . res://tests/lock_marks.tscn
## 잠금을 꾸민 Run(불멸 I 를 「정지」가 등용 · 초월 L 을 「동오」가 등용 · 불멸 D 사망)으로 화면을 그려,
## 가지지 않은 장수 가운데 이번 판에 얻을 길이 없는 것(스스로 잠김 + 재료가 아래까지 잠김 —— 이 점검이 따로 셈)이 나오는 타일 · 글이 표시를 갖는지 센다.
##   조합 탭(목표 보드 · 갈무리 목표 줄 · 추천) · 전체 조합법 시트 · 조합법 시트(까닭 · 재료 칩) · 상세창(까닭 · 큰 카드 · 조합 줄) · 선택권 창 맨 위 묶음 ·
##   다른 사람이 등용한 직후 열려 있던 조합법 시트가 바뀌는가 · 잠긴 칸을 누르면 까닭 알림
## 옛 코드에서도 돈다 (새 함수는 has_method 로만 부른다) —— 고치기 전/후 빠짐 수를 비교하려고

var gs
var MT: Script = load("res://scripts/ui/mini_tile.gd")      # 새 정적 함수는 이름으로 부른다 (옛 코드에서도 읽히게)
var miss := []
var seen := 0
var M := ""        # 재료(불멸 I)가 선점된 신화 —— 갈무리
var I := ""
var M2 := ""       # 열어 둔 조합법 시트 —— 나중에 그 재료가 선점된다
var I2 := ""


func _ready() -> void:
	Run.dev_nosave = true
	Run.dev_immortal = true
	PlayLog.enabled = false
	gs = load("res://scenes/game.tscn").instantiate()
	add_child(gs)
	await _frames(3)
	var r := Run.new()
	r.new_game(5)
	r.dev_autoplay()
	r.dev_autoplay()
	gs.run = r
	gs._title.visible = false
	_pick_targets(r)
	print("LOCK|신화 %s(재료 %s 선점) · 신화 %s(나중에 재료 %s 선점)" % [DB.C[M].name, DB.C[I].name, DB.C[M2].name, DB.C[I2].name])
	var L := _first(6, [])
	var D := _first(7, [I, I2])
	r.locked = {I: {"by": "정지"}, L: {"by": "동오"}, D: {"dead": 1}}
	gs.forge_tree.pins = [M]
	if gs.run.has_method("block_text"):
		print("LOCK|block_text(M)=%s · mat_block=%s · have(I)=%d" % [gs.run.block_text(M), gs.run.mat_block(M), gs.run.have(I)])
	gs.go("forge")
	await _frames(4)
	_check_tiles("조합 탭", gs._body)
	_check_text("조합 탭 · 갈무리 목표 줄", gs._body, "만들 수 없다")
	_check_goals()
	for ft in [0, 7, 8]:      # 전체 · 불멸 · 신화 거르기 (전체는 가까운 순 36장만 먼저 그린다)
		gs.forge_tier = ft
		gs.recipes_sheet()
		await _frames(3)
		_check_tiles("전체 조합법 시트(등급 %d)" % ft, gs._sheet_body)
	gs.forge_tier = 0
	gs.recipe_sheet(M)
	await _frames(3)
	_check_text("조합법 시트 · 까닭", gs._sheet_body, "만들 수 없다")
	_check_text("조합법 시트 · 재료 칩", gs._sheet_body, "%s 0/" % DB.person(I), "선점")
	_check_big("조합법 시트 · 큰 카드", M)
	gs.card_info(M)
	await _frames(3)
	_check_text("상세창 · 까닭", gs._sheet_body, "만들 수 없다")
	_check_big("상세창 · 큰 카드", M)
	gs.card_info(I)
	await _frames(3)
	_check_tiles("상세창 · 조합 줄(재료 쪽)", gs._sheet_body)
	var tk := _picker_tier(r)
	if tk > 0:
		r.tickets[str(tk)] = 1
		gs.picker(tk)
		await _frames(3)
		_check_tiles("선택권 창", gs._sheet_body)
	# 다른 사람이 방금 등용 —— 열려 있던 조합법 시트가 그 자리에서 바뀌는가
	gs.close_sheet()
	await _wait(0.3)
	gs.recipe_sheet(M2)
	await _frames(3)
	var r2 := Run.new()
	r2.from_dict(JSON.parse_string(JSON.stringify(r.to_dict())))
	r2.locked[I2] = {"by": "정지"}
	gs.run = r2
	gs.render()
	await _frames(4)
	_check_text("열린 조합법 시트 · 새 잠금 반영", gs._sheet_body, "만들 수 없다")
	# 잠긴 칸 누름 —— 까닭 알림
	if MT.has_method("deny"):
		var before := _toast_text()
		MT.call("deny", I)
		await _frames(2)
		seen += 1
		var after := _toast_text()
		if after == before or not after.contains("정지 세력이 등용"):
			miss.append("잠긴 칸 누름 · 알림 없음")
	else:
		seen += 1
		miss.append("잠긴 칸 누름 · 거절음만 (까닭 알림 없음)")
	for m in miss:
		print("MISS|", m)
	print("LOCK|자리 %d · 빠짐 %d" % [seen, miss.size()])
	get_tree().quit(1 if not miss.is_empty() else 0)


## 이번 판에 얻을 길이 없는가 —— 이 점검이 따로 센다 (Run.mat_block 과 같은 규칙: 모자란 재료를 아래까지, 선택권으로 받는 전설 이하는 그 아래를 보지 않는다)
func _blocked(k: String) -> bool:
	var r: Run = gs.run
	if r.have(k) > 0:
		return false
	if r.locked.has(k):
		return true
	return DB.RECOF.has(k) and _path(k, 0)


func _path(k: String, depth: int) -> bool:
	var r: Run = gs.run
	if depth > 10:
		return false
	var m := Run.mat_count(DB.RECOF[k])
	for q in m:
		if r.have(q) >= int(m[q]):
			continue
		if r.locked.has(q):
			return true
		if DB.RECOF.has(q) and (DB.is_kiin(q) or int(DB.C[q].tier) > Run.FREE_TIER_CAP) and _path(q, depth + 1):
			return true
	return false


func _pick_targets(r: Run) -> void:
	for k in DB.by_tier(8):
		if DB.is_foe(k) or not DB.RECOF.has(k) or r.have(k) > 0:
			continue
		for q in Run.mat_count(DB.RECOF[k]):
			if int(DB.C[q].tier) == 7 and r.have(q) <= 0:
				if M == "":
					M = k
					I = q
				elif q != I and M2 == "" and not Run.mat_count(DB.RECOF[k]).has(I):
					M2 = k
					I2 = q
				break


func _first(t: int, skip: Array) -> String:
	for k in DB.by_tier(t):
		if not DB.is_foe(k) and gs.run.have(k) <= 0 and not skip.has(k) and k != I:
			return k
	return ""


## 타일 —— 가지지 않았고 얻을 길이 없는 장수가 표시 없이 나오면 빠짐
func _check_tiles(area: String, root: Node) -> void:
	var n := 0
	var bad := 0
	for t in root.find_children("*", "", true, false):
		var k := ""
		var q := -1
		var marked := false
		if t is MiniTile:
			if t.get("show_lock") == false:
				continue
			k = t.k
			q = t.qty
			marked = t._is_locked()
		elif t is CardTile:
			k = t.k
			q = t.qty
			marked = t.has_method("_draw") and MT.has_method("mark_of") and not MT.call("mark_of", k, q).is_empty()
		else:
			continue
		if k == "" or q > 0 or not _blocked(k):
			continue
		n += 1
		if not marked:
			bad += 1
			if bad <= 3:
				miss.append("%s · %s 타일에 표시 없음 (%s)" % [area, DB.C[k].name, "스스로 잠김" if gs.run.locked.has(k) else "재료 잠김"])
	seen += n
	if bad > 3:
		miss.append("%s · 그 밖에 %d장 더" % [area, bad - 3])
	print("LOCK|%s · 얻을 길 없는 타일 %d장 · 표시 없음 %d" % [area, n, bad])


func _check_text(area: String, root: Node, want: String, also := "") -> void:
	seen += 1
	if OS.get_cmdline_user_args().has("--dbg"):
		print("DBG|", area, " | ", " ## ".join(_texts(root).filter(func(x): return x.length() > 1)).substr(0, 600))
	for s in _texts(root):
		if s.contains(want) and (also == "" or s.contains(also)):
			return
	miss.append("%s · 「%s%s」 글 없음" % [area, want, (" … " + also) if also != "" else ""])


func _check_big(area: String, k: String) -> void:
	seen += 1
	for cv in gs._sheet_body.find_children("*", "CardView", true, false):
		if cv.k == k:
			if cv.get("lock_n") != null and int(cv.lock_n) <= 0 and not MT.call("mark_of", k, 0).is_empty():
				return
	miss.append("%s · 큰 카드에 표시 없음" % area)


## 추천 목표 · 인연 추천에 얻을 길 없는 장수가 끼는가 (조합 탭이 쓰는 목록 그대로)
func _check_goals() -> void:
	var lst: Array = gs._forge_goals(DB.D.RECDEF)
	var sp := {}
	for o in lst:
		sp[DB.person(o)] = true
	lst += gs.run.bond_goals(sp, 6)
	lst += gs.run.forge_goals(DB.D.RECDEF.map(func(x): return x[0]), 6, 1e9)
	seen += 1
	var b := lst.filter(func(o): return _blocked(o))
	if not b.is_empty():
		miss.append("추천 목표 · 얻을 길 없는 %s" % ", ".join(b.map(func(o): return DB.C[o].name)))


func _picker_tier(r: Run) -> int:
	for t in [5, 4, 3]:
		if not Run.pickable(t).is_empty():
			return t
	return 0


func _texts(root: Node) -> Array:
	var out := []
	for n in root.find_children("*", "", true, false):
		if n is RichTextLabel:
			out.append(n.text + " " + n.get_parsed_text())
		elif n is Label or n is Button:
			out.append(n.text)
	return out.map(func(x): return str(x).replace(char(0x2060), ""))


func _toast_text() -> String:
	return " | ".join(_texts(gs._toast_box))


func _frames(k := 2) -> void:
	for i in k:
		await get_tree().process_frame


func _wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout
