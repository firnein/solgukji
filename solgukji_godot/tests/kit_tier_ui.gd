extends Node
## 11/27 강화는 신화만 —— 사용자 "qwer 이 적용된 모든 장수는 ui 에 qwer 반영, 단 신화를 제외한 등급에는 강화할 수 없음"
##   godot --headless --path . res://tests/kit_tier_ui.tscn            (흐름 점검)
##   godot --path . --resolution 540x1200 res://tests/kit_tier_ui.tscn -- --out=폴더   (창 —— 불멸 정보창 캡처 kit4_immortal_info.png)
## ① Kit.can_up —— 신화 참 · 불멸 · 초월 · 기인은 스위치를 켜도 거짓
## ② 스위치 켠 불멸에 kit_up 명령 → 거절 · 전공 그대로 · 강화 값 −1
## ③ 정책 · 저장 · 상대 강화에 불멸 강화가 들어와도 Kit.norm 이 버린다 (전투 유닛에도 강화 없음) · 타일 표시 없음
## ④ 정보창 —— 스위치 켠 불멸은 다섯 줄 · 강화 버튼 · 펼침 · 칸 현황 · 전공 · 강화 효과 글 없음 / 스위치 끔이면 예전 정보창(키트 묶음 없음) / 신화는 그대로 강화 버튼

const Kit := preload("res://scripts/kit.gd")

var fails := 0
var headless := false
var args := {}


func ok(cond: bool, what: String) -> void:
	if not cond:
		fails += 1
	print("%s · %s" % ["통과" if cond else "실패", what])


func _ready() -> void:
	for s in OS.get_cmdline_user_args():
		var kv := s.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	headless = DisplayServer.get_name() == "headless"
	PlayLog.enabled = false
	get_tree().create_timer(600.0).timeout.connect(func(): get_tree().quit(1))
	Kit.enabled = true
	Kit.immortal = false
	Kit.trans = false
	Kit.kiin = false
	Kit.up_any = false
	var myth := "c177"
	var imm := _first(func(k): return int(DB.C[k].tier) == Kit.IMMORTAL_TIER and not DB.is_kiin(k), "immortal")
	var tr := _first(func(k): return int(DB.C[k].tier) == Kit.TRANS_TIER and not DB.is_kiin(k), "trans")
	var ki := _first(func(k): return DB.is_kiin(k), "kiin")
	print("불멸 %s(%s) · 초월 %s(%s) · 기인 %s(%s)" % [imm, DB.C[imm].name, tr, DB.C[tr].name, ki, DB.C[ki].name])

	# ── ① can_up
	ok(Kit.on(myth) and Kit.can_up(myth), "신화(%s) —— 키트 장수 · 강화 가능" % DB.C[myth].name)
	ok(not Kit.can_up(imm) and not Kit.can_up(tr) and not Kit.can_up(ki), "스위치 끔 —— 불멸 · 초월 · 기인 강화 불가")
	ok(not Kit.on(imm) and Kit.cell(imm, "q").is_empty(), "스위치 끔 —— 불멸은 키트 장수가 아니다 (예전 그대로)")
	Kit.immortal = true
	Kit.trans = true
	Kit.kiin = true
	ok(Kit.on(imm) and Kit.on(tr) and Kit.on(ki), "스위치 켬 —— 불멸 · 초월 · 기인이 키트 장수")
	ok(not Kit.can_up(imm) and not Kit.can_up(tr) and not Kit.can_up(ki) and Kit.can_up(myth), "스위치 켬 —— 그래도 강화는 신화만")
	ok(Kit.up_cost({}, imm) == -1 and Kit.up_cost({}, myth) == int(Kit.UP_COST[0]), "강화 값 —— 불멸 −1 · 신화 %d" % int(Kit.UP_COST[0]))
	ok(Kit.up_block({}, imm, "q").contains("신화") and Kit.up_block({}, ki, "w").contains("신화") and Kit.up_block({}, myth, "q") == "", "up_block —— 불멸 · 기인 「%s」 · 신화 통과" % Kit.up_block({}, imm, "q"))

	# ── ② Run 명령
	var r := Run.new()
	r.new_game(3)
	for i in 6:
		r.dev_autoplay()
	_put(r, [myth, imm])
	r.merit = 20
	r.kit = {}
	ok(r.have(imm) > 0, "불멸을 가졌다")
	var res = r.command("kit_up", [imm, "q"])
	ok(res == false and r.merit == 20 and r.kit.is_empty(), "불멸 kit_up → 거절 · 전공 20 그대로 · 강화 없음 (%s · %s)" % [str(res), r.kit_block(imm, "q")])
	ok(r.kit_cost(imm) == -1, "Run.kit_cost(불멸) −1")
	ok(r.command("kit_up", [myth, "q"]) == true and r.merit == 20 - int(Kit.UP_COST[0]) and r.kit == {myth: ["q"]}, "신화 kit_up → 된다 (전공 %d)" % r.merit)

	# ── ③ norm · 표시 · 전투
	var raw := {imm: ["q", "r"], tr: ["w"], ki: ["e"], myth: ["q"]}
	ok(Kit.norm(raw) == {myth: ["q"]}, "Kit.norm —— 불멸 · 초월 · 기인 강화를 버린다 %s" % str(Kit.norm(raw)))
	ok(Kit.ups_of(raw, imm).is_empty() and Kit.spent(raw) == int(Kit.UP_COST[0]), "ups_of(불멸) 빈 배열 · 쓴 전공은 신화 몫만")
	MiniTile.kit = raw
	ok(MiniTile.kit_marks(imm, null, true).is_empty() and MiniTile.kit_marks(myth, null, true) == ["q"], "편성 타일 —— 불멸에는 강화 글자 없음 · 신화는 Q")
	MiniTile.kit = {}
	r.kit = raw.duplicate(true)
	ok(not r.kit_side().has(imm), "전투에 넘기는 내 강화에 불멸이 없다")
	var a := DB.auto_place([myth, imm] + _fill([myth, imm], 7), "eorin")
	var b := DB.auto_place(_fill([], 9), "eorin")
	var bt := RtBattle.new(7)
	bt._setup(a, "eorin", 100, null, b, "eorin", 100, null, "", "", [], {"A": "smart", "B": "smart", "kit": {"A": raw, "B": {}}})
	var ui_ = _unit(bt, "A", imm)
	var um = _unit(bt, "A", myth)
	ok(bt.policy.get("kit") == {"A": {myth: ["q"]}, "B": {}}, "전투 정책 —— 불멸 강화는 버려진다 %s" % str(bt.policy.get("kit")))
	ok(ui_ != null and ui_.kit == [] and um != null and um.kit == ["q"], "전투 유닛 —— 불멸 강화 없음 · 신화 Q (%s · %s)" % [str(ui_.kit if ui_ != null else "?"), str(um.kit if um != null else "?")])
	bt.units.clear()

	# ── ④ 정보창
	Run.dev_immortal = true
	Run.dev_nosave = true
	var gs: GameScreen = load("res://scenes/game.tscn").instantiate()
	add_child(gs)
	await _wait(1.2)
	gs._new_game()
	await _wait(0.4)
	gs._coach_finish()
	gs.forge_tree.clear()
	r.kit = {myth: ["q"]}
	r.merit = 20
	r.grain = maxi(r.grain, 12)
	r.auto_draw()
	gs.run = r
	gs.deploy.seg = ""
	gs.go("deploy")
	await _wait(0.6)
	gs.close_sheet()
	gs._bands.clear()      # 띠 알림 · 토스트를 치운다 (캡처에 겹치지 않게)
	gs._hide_band()
	for c in gs._toast_box.get_children():
		c.queue_free()
	await _wait(0.2)
	gs.card_info(imm)
	await _wait(0.9)
	var sec := _find(gs._sheet_body, "KitSection")
	var rows := _rows(sec)
	var tx := _texts(sec)
	ok(sec != null and rows.size() == 5 and rows.map(func(n): return str(n.get_meta("kit_slot"))) == Kit.SLOTS, "불멸 정보창 —— 키트 다섯 줄 Q · W · E · R · P (%d)" % rows.size())
	ok(_buttons(sec).is_empty() and _find(sec, "KitUpLine") == null and _find(sec, "KitRuleRow") == null, "강화 버튼 · 「강화 · 이름 ▸」 · 칸 현황 없음")
	ok(tx.contains("강화는 신화 장수만") and not tx.contains("가진 " + Kit.CUR_N) and not tx.contains("모자람"), "머리 —— 「강화는 신화 장수만」 · 가진 전공 · 부족 문구 없음")
	var up_leak := Kit.SLOTS.filter(func(sl): return tx.contains(str(Kit.cell(imm, sl).get("up", {}).get("n", "@@"))))
	ok(up_leak.is_empty() and Kit.SLOTS.all(func(sl): return tx.contains(str(UI.kit_text(imm, sl).name))), "기술 이름은 보이고 강화 이름 · 효과는 없다 %s" % str(up_leak))
	ok(_find(gs._sheet_body, "SkillsSection") == null, "일반 기술 묶음 대신 키트 줄 (신화와 같은 모양)")
	await _shot("kit4_immortal_info")
	# 신화는 그대로
	gs.card_info(myth)
	await _wait(0.9)
	var ms := _find(gs._sheet_body, "KitSection")
	ok(ms != null and _buttons(ms).size() == 4 and _find(ms, "KitRuleRow") != null and _texts(ms).contains("가진 " + Kit.CUR_N), "신화 정보창 —— 강화 버튼 4 · 칸 현황 · 가진 전공 (예전 그대로)")
	# 스위치 끔 —— 예전 정보창
	Kit.immortal = false
	Kit.trans = false
	Kit.kiin = false
	gs.card_info(imm)
	await _wait(0.9)
	ok(_find(gs._sheet_body, "KitSection") == null, "스위치 끔 —— 불멸 정보창에 키트 묶음 없음 (예전 그대로)")
	print("실패 %d" % fails)
	get_tree().quit(1 if fails > 0 else 0)


## 그 등급의 첫 카드 (적 전용 · 은퇴 제외 · 고유기 있음 · 그 스위치를 켜면 칸 자료가 있는 것)
func _first(pred: Callable, sw: String) -> String:
	var ks: Array = DB.C.keys().filter(func(k): return pred.call(k) and not DB.is_foe(k) and str(DB.C[k].get("kind", "")) != "retired" and DB.has_ult(k))
	ks.sort()
	_sw(sw, true)
	var out := ""
	for k in ks:
		if Kit.SLOTS.all(func(sl): return not Kit.cell(k, sl).is_empty()):
			out = k
			break
	_sw(sw, false)
	return out


func _sw(sw: String, v: bool) -> void:
	match sw:
		"immortal":
			Kit.immortal = v
		"trans":
			Kit.trans = v
		"kiin":
			Kit.kiin = v


## 편성판 앞 칸에 카드들을 올린다 (가진 장수로)
func _put(r: Run, ks: Array) -> void:
	var slots := []
	for i in 9:
		if r.board[i] != null:
			slots.append(i)
	for i in 9:
		if r.board[i] == null:
			slots.append(i)
	for j in ks.size():
		r.board[slots[j]] = ks[j]


## 전설 이하 키트 아닌 카드 n장 (같은 인물 빼고)
func _fill(skip: Array, n: int) -> Array:
	var seen := {}
	for k in skip:
		seen[DB.person(k)] = true
	var pool: Array = DB.by_tier(5).filter(func(k): return not DB.is_foe(k) and not DB.is_kiin(k) and DB.C[k].kind != "retired")
	pool.sort()
	var out := []
	for k in pool:
		if out.size() >= n:
			break
		if seen.has(DB.person(k)):
			continue
		seen[DB.person(k)] = true
		out.append(k)
	return out


func _unit(bt, camp: String, cid: String):
	for u in bt.units:
		if u.camp == camp and u.c.id == cid:
			return u
	return null


func _find(n: Node, nm: String) -> Node:
	if n == null:
		return null
	if n.name == nm and not n.is_queued_for_deletion():
		return n
	for c in n.get_children():
		var f := _find(c, nm)
		if f != null:
			return f
	return null


func _rows(n: Node) -> Array:
	var o := []
	if n == null or n.is_queued_for_deletion():
		return o
	if n.has_meta("kit_slot"):
		o.append(n)
	for c in n.get_children():
		o.append_array(_rows(c))
	return o


func _texts(n: Node) -> String:
	if n == null or n.is_queued_for_deletion():
		return ""
	var s := ""
	if n is Label:
		s += (n as Label).text + "\n"
	elif n is RichTextLabel:
		s += (n as RichTextLabel).get_parsed_text() + "\n"
	for c in n.get_children():
		s += _texts(c)
	return s.replace(UI.WJ, "")


## 전공 기호가 든 버튼들 (강화 버튼)
func _buttons(n: Node) -> Array:
	var o := []
	if n == null or n.is_queued_for_deletion():
		return o
	if n is Button and _has_merit_icon(n):
		o.append(n)
	for c in n.get_children():
		o.append_array(_buttons(c))
	return o


func _has_merit_icon(n: Node) -> bool:
	if n is Icons.View and (n as Icons.View).icon == "merit":
		return true
	for c in n.get_children():
		if _has_merit_icon(c):
			return true
	return false


func _wait(s: float) -> void:
	await get_tree().create_timer(s).timeout


func _shot(name: String) -> void:
	if headless or not args.has("out"):
		return
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [str(args.out), name])
