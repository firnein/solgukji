class_name ForgeTree
extends RefCounted
## 갈무리 —— 만들고 싶은 장수를 갈무리해 두면 조합 탭 맨 위에 나무 모양으로 모인다 (10/30 · 10/31 사용자).
## 갈무리한 장수가 위 가운데, 그 재료가 아래로 좌우에 갈라져 붙고, 재료의 재료가 또 그 아래로.
## 이미 가진 재료는 ✓ 로 접고, 모자란 재료는 [재료 ▾] 로 고급 재료가 나올 때까지 몇 단이든 펼친다. 일반 등급 이하(창병대 · 궁수대 …)는 그리지 않고
## 부모 칸에 '기본패 n장' 으로만 적는다. 칸마다 [조합], 아래 [모두 조합] 은 아래에서부터 되는 만큼 잇달아 조합한다.
## 갈무리 목록은 화면 쪽 취향이라 Run(서버 판정)에 넣지 않고 기기에 따로 둔다 (user://pins.json).
## 11/12 사용자: 새 판에 이전 판의 갈무리가 남아 있었다 —— 혼자 하기의 새 판(_new_game)만 비우고 온라인 새 판은 비우지 않았다.
## 이제 파일에 어느 판의 갈무리인지(game = Run 의 rng 씨앗)를 함께 적고, 판이 바뀌면(bind) 비운다. 옛 파일(배열)은 지금 판의 것으로 받아들인다

const PATH := "user://pins.json"
const MAX_PINS := 6
const MAX_DEPTH := 8           # 안전 한도 —— 일반 등급 이하는 빼므로 고급 재료에서 끝난다 (10/31 사용자: 고급까지 계속 펼치기)
const BASIC_TIER := 2          # 이 등급 이하 재료는 트리에서 뺀다
const NW := 62.0               # 칸 너비 · 높이 (재료)
const NH := 86.0
const RW := 92.0               # 맨 위 (갈무리한 장수)
const RH := 124.0
const GAP := 8.0
const ROW := 34.0              # 줄 사이 (선이 지나간다)
const BTN := 28.0              # 칸 아래 [조합] 자리

var gs: GameScreen
var pins: Array = []
var opened := {}               # 갈무리 장수 -> {펼친 재료 경로("관우/장비/…"): true} —— 어느 단이든 여럿 펼친다
var game := ""                # 이 갈무리가 속한 판 (GameScreen.game_id) —— "" 이면 아직 모른다 (옛 파일)
## 11/15 사용자: 완성 순서 —— pins 의 차례가 곧 「순서대로 모두 조합」의 차례(앞이 먼저 재료를 가져간다).
## morder 는 갈무리 장수마다 그 재료를 끝낼 차례 {장수: [재료 …]} (없으면 조합법 차례 · 가장 깊은 것부터). 둘 다 pins.json 에 (갈무리와 같은 곳 —— Run 저장은 온라인에서 서버 것으로 덮인다)
var morder := {}
const CHAIN_MAX := 200         # 모두 조합 한 번의 조합 수 한도 (예전 40 —— 깊은 나무는 한 번에 끝나지 않았다)


func _init(g: GameScreen) -> void:
	gs = g
	if FileAccess.file_exists(PATH):
		var d = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		if d is Dictionary:
			game = str(d.get("game", ""))
			var mo = d.get("morder", {})
			if mo is Dictionary:
				for k in mo:
					if mo[k] is Array:
						morder[str(k)] = mo[k].filter(func(x): return x is String and DB.C.has(x))
			d = d.get("pins", [])
		if d is Array:
			pins = d.filter(func(k): return k is String and DB.RECOF.has(k))


func _save() -> void:
	if Run.dev_nosave:      # 11/20 점검 실행은 사용자 갈무리(pins.json)를 덮지 않는다
		return
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"game": game, "pins": pins, "morder": morder}))


## 새 판 —— 갈무리를 비운다
func clear() -> void:
	pins.clear()
	opened.clear()
	morder.clear()
	_save()


## 지금 판(id)에 맞춘다 —— 다른 판의 갈무리면 비운다. 비웠으면 true (다시 그려야 한다)
func bind(id: String) -> bool:
	if id == "" or id == game:
		return false
	var other := game != "" and not pins.is_empty()
	game = id
	if other:
		pins.clear()
		opened.clear()
		morder.clear()
	_save()
	return other


func pinned(k: String) -> bool:
	return pins.has(k)


## 11/22 사용자: "사망한 장수는 갈무리할 수 없도록" —— 장수 사망룰로 이번 판 등용 불가 (Run.locked 의 dead)
func is_dead(k: String) -> bool:
	return gs.run != null and gs.run.locked.has(k) and gs.run.lock_text(k) == "사망"


func toggle(k: String) -> void:
	if not pins.has(k) and is_dead(k):
		gs.toast("%s은(는) 이번 판에 사망해 갈무리할 수 없습니다" % DB.C[k].name, "bad")
		return
	if pins.has(k):
		pins.erase(k)
		morder.erase(k)
		gs.toast("%s 갈무리 해제" % DB.C[k].name)
	else:
		if pins.size() >= MAX_PINS:
			morder.erase(pins.pop_back())
		pins.push_front(k)
		gs.toast("%s 갈무리 — 조합 탭 맨 위에" % DB.C[k].name, "gain")
	_save()
	gs.render()


## 갈무리한 장수를 완성했다 —— 갈무리에서 뺀다 (11/3 사용자)
func done(k: String) -> void:
	if pins.has(k):
		pins.erase(k)
		opened.erase(k)
		morder.erase(k)
		_save()
		gs.toast("%s 완성 — 갈무리에서 뺐다" % DB.C[k].name, "gain")


## 갈무리에서 조용히 뺀다 (알림은 부르는 쪽이) —— 11/12 다른 유저가 먼저 등용한 장수
func drop(k: String) -> void:
	if pins.has(k):
		pins.erase(k)
		opened.erase(k)
		morder.erase(k)
		_save()


## 모두 펴기 / 모두 접기 (11/3 사용자) —— 펼 수 있는 재료 경로를 모두 연다
func open_all(root: String) -> void:
	if all_open(root):
		opened.erase(root)
	else:
		var o := {}
		_collect_paths(_node(root, 1, 0, root, "", true), o)
		opened[root] = o
	gs.render()


func all_open(root: String) -> bool:
	var o := {}
	_collect_paths(_node(root, 1, 0, root, "", true), o)
	if o.is_empty():
		return false
	var cur: Dictionary = opened.get(root, {})
	for p in o:
		if not cur.has(p):
			return false
	return true


func _collect_paths(nd: Dictionary, o: Dictionary) -> void:
	for c in nd.kids:
		if c.has("k") and not c.ok and DB.RECOF.has(c.k) and not c.kids.is_empty():
			o[c.path] = true
		_collect_paths(c, o)


## 갈무리 칸 —— 조합 탭 맨 위
func build() -> Control:
	var v := UI.vbox(UI.SP_S)
	if pins.is_empty():          # 11/2 사용자: 갈무리 안내 글은 빼고 공간 확보
		v.visible = false
		return v
	# 11/15 사용자: 완성 순서를 정하는 창 + 그 차례대로 한 번에 —— 갈무리 묶음 머리줄 [갈무리 N] … [완성 순서] [순서대로 모두 조합]
	var hd := UI.hbox(UI.SP_S)
	hd.alignment = BoxContainer.ALIGNMENT_END      # 11/25 UX: 「갈무리 N」 머리글은 조합 탭 맨 윗줄(GameScreen._page_forge)이 쓴다
	var ob := UI.btn("완성 순서", func(): order_sheet(), "ghost", UI.BH_S)
	ob.add_theme_font_size_override("font_size", UI.FS_BODY)
	ob.custom_minimum_size.x = 84
	hd.add_child(ob)
	if pins.size() >= 2:
		var any := false
		for k in pins:
			if gs.run.block_text(k) == "" and (gs.run.can_forge(k) or _chain_can(_node(k, 1, 0, k, "", true))):      # 11/25 막힌 목표는 세지 않는다
				any = true
				break
		var ab := UI.btn("순서대로 모두 조합", func(): forge_all(), "pri" if any else "", UI.BH_S)
		ab.add_theme_font_size_override("font_size", UI.FS_BODY)
		ab.disabled = not any or not gs.can_act()
		hd.add_child(ab)
	v.add_child(hd)
	for k in pins:
		v.add_child(UI.panel(_goal(k), 10))
	return v


## 11/25 UX: 갈무리 목표 한 줄 —— 초상 · 이름 · 재료 진행 막대 · 모자란 재료 · [모두 조합] · [나무 ▾].
## 재료 나무(_card)는 펼쳤을 때만 그 아래에 (예전에는 목표마다 나무가 늘 펼쳐져 둘이면 화면이 찼다). 펼친 상태는 이 탭에 있는 동안 (goal_open)
var goal_open := {}

func _goal(root: String) -> Control:
	var v := UI.vbox(UI.SP_S)
	var c: Dictionary = DB.C[root]
	var row := UI.hbox(UI.SP_M)
	var t := gs.mtile(root, gs.run.pool().get(root, -1), func(id): gs.recipe_sheet(id))
	t.custom_minimum_size = Vector2(NW, NH)
	t.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(t)
	var mid := UI.vbox(3)
	mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mid.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var nl := UI.lbl(str(c.name), UI.FS_LABEL, (DB.KIIN_COL if DB.is_kiin(root) else DB.TIER[int(c.tier)].c).lightened(0.25), true)
	nl.clip_text = true
	nl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	mid.add_child(nl)
	# 11/26 재료 한 장이 한 칸 —— 가진 재료는 그 등급 색으로 채운다 (칸만 봐도 전설을 가졌는지 · 무엇이 빠졌는지). 옆의 퍼센트는 기본패로 환산한 실제 진행
	var pg: Vector2i = gs._forge_progress(root)
	mid.add_child(UI.lbl("재료 %d/%d · 진행 %d%%" % [pg.x, pg.y, gs.run.goal_pct(root)], UI.FS_CAP, DB.PAL.bamboo, true))
	mid.add_child(SheetStyle.tier_meter(gs.tier_segs(root)))
	var miss: Array = gs._missing(root)
	var ml := UI.lbl("부족 · " + " · ".join(miss) if not miss.is_empty() else "재료를 다 모았다", UI.FS_CAP, DB.PAL.text_dim if not miss.is_empty() else DB.PAL.jade)
	ml.clip_text = true
	ml.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	mid.add_child(ml)
	var blk: String = gs.run.block_text(root)      # 11/25 선점 · 사망 · 재료 선점으로 막힌 목표 —— 조용히 빼지 않고 까닭을 보이고 「모두 조합」을 끈다
	if blk != "":
		mid.add_child(gs._lock_line(blk + " — 만들 수 없다"))
	row.add_child(mid)
	var bx := UI.vbox(UI.SP_XS)
	bx.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var can: bool = blk == "" and (gs.run.can_forge(root) or _chain_can(_node(root, 1, 0, root, "", true)))
	var all := UI.btn("모두 조합", func(): forge_chain(root), "pri" if can else "", UI.BH_S)
	all.add_theme_font_size_override("font_size", UI.FS_BODY)
	all.custom_minimum_size.x = 96
	all.disabled = not can or not gs.can_act()
	bx.add_child(all)
	var op: bool = goal_open.get(root, false)
	var fb := UI.btn(("재료 접기 ▴" if drill else "나무 접기 ▴") if op else ("재료 보기 ▾" if drill else "재료 나무 ▾"), func():
		goal_open[root] = not goal_open.get(root, false)
		gs.render(), "ghost", UI.BH_XS)
	fb.add_theme_font_size_override("font_size", UI.FS_CAP)
	fb.add_theme_color_override("font_color", DB.PAL.bamboo)
	bx.add_child(fb)
	row.add_child(bx)
	v.add_child(row)
	if op:
		v.add_child(_drill(root) if drill else _card(root, true))
	return v


## 11/25 사용자: "갈무리 트리 펼쳐놓을 때 가로가 늘어진다 · 세로로 해도 늘어진다 —— 새로운 방식" → 나무를 그리지 않는다.
##   ① 재료 한 줄: 지금 보는 장수의 재료만. 모자란 재료의 「재료 ▾」를 누르면 그 줄이 그 재료의 재료로 바뀌고, 위에 길(조조 › 위왕 조조)이 붙는다 —— 몇 단이든 한 줄
##   ② 모자란 기본패 한 줄: 맨 아래까지 다 풀었을 때 아직 모자란 기본패를 병종별로 (+ 아이템). 중간 조합은 「모두 조합」이 한다 —— 사람이 구할 것은 이것뿐
## 목표 하나의 높이가 깊이와 상관없이 늘 같다
static var drill := true
var focus := {}      # 갈무리 장수 -> 지금 보는 재료 경로 ("" = 맨 위)

func _drill(root: String) -> Control:
	var v := UI.vbox(UI.SP_S)
	var full := _node(root, 1, 0, root, "", true)
	var nd := full
	var crumbs := [[root, ""]]
	var acc := ""
	for seg in str(focus.get(root, "")).split("/", false):
		acc = seg if acc == "" else acc + "/" + seg
		var hit = null
		for c in nd.kids:
			if c.has("k") and str(c.get("path", "")) == acc:
				hit = c
		if hit == null or (hit.kids.is_empty() and int(hit.get("basic", 0)) <= 0):
			break      # 그 사이 재료가 채워졌다 —— 갈 수 있는 데까지만
		nd = hit
		crumbs.append([hit.k, acc])
	focus[root] = str(crumbs[-1][1])
	if crumbs.size() > 1:      # 길 —— 앞 칸을 누르면 그 단으로 올라간다
		var cr := UI.hbox(2)
		for i in crumbs.size():
			var nm: String = str(DB.C[crumbs[i][0]].name)      # 카드 이름 그대로 (난세간웅 조조 › 위왕 조조 › 조조 —— 인물 이름만 쓰면 같은 이름이 겹친다)
			if i < crumbs.size() - 1:
				var p: String = crumbs[i][1]
				var cb := UI.btn(nm + "  ›", func():
					focus[root] = p
					gs.render(), "ghost", UI.BH_XS)
				cb.add_theme_font_size_override("font_size", UI.FS_CAP)
				cb.add_theme_color_override("font_color", DB.PAL.bamboo)
				cr.add_child(cb)
			else:
				var cl := UI.lbl(nm + "의 재료", UI.FS_CAP, DB.PAL.paper, true)
				cl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
				cr.add_child(cl)
		var cs := UI.scroll(true)      # 길이 길어지면 옆으로 민다 (끝이 보이게 맨 뒤로 넘겨 둔다)
		cs.custom_minimum_size.y = UI.BH_XS + 2
		cs.add_child(cr)
		cs.ready.connect(func():
			await cs.get_tree().process_frame
			if is_instance_valid(cs):
				cs.scroll_horizontal = int(cs.get_h_scroll_bar().max_value))
		v.add_child(cs)
	var st := UI.strip(int(GAP))
	for c in nd.kids:
		st[1].add_child(_drill_cell(root, c))
	if int(nd.get("basic", 0)) > 0:
		var bl := UI.lbl("＋ 기본패\n%d장" % int(nd.basic), UI.FS_CAP, DB.PAL.bamboo)
		bl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		bl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		bl.custom_minimum_size = Vector2(NW, NH)
		st[1].add_child(bl)
	st[0].custom_minimum_size.y = NH + BTN + 2
	v.add_child(st[0])
	var lack := base_lack(full)
	if not lack.is_empty():
		var lr := UI.hbox(UI.SP_XS)
		var ll := UI.lbl("모자란 기본패", UI.FS_CAP, DB.PAL.bamboo)
		ll.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		lr.add_child(ll)
		for q in Run.sort_cards(lack.keys()):
			var t := gs.mtile(q, int(lack[q]))
			t.custom_minimum_size = Vector2(34, 46)
			lr.add_child(t)
		v.add_child(lr)
	var row := UI.hbox(UI.SP_S)
	row.alignment = BoxContainer.ALIGNMENT_END
	var x := UI.btn("갈무리 해제", func(): toggle(root), "ghost", UI.BH_XS)
	x.add_theme_font_size_override("font_size", UI.FS_CAP)
	row.add_child(x)
	v.add_child(row)
	return v


## 재료 한 칸 —— 초상(가진 수/필요 수) + 아래 ✓ / [조합] / [재료 ▾](그 재료의 재료로 들어간다)
func _drill_cell(root: String, nd: Dictionary) -> Control:
	var run: Run = gs.run
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	v.custom_minimum_size.x = NW
	if nd.has("item"):
		var it: Dictionary = DB.IT[nd.item]
		var l := UI.rich("[center][color=%s]＋%s[/color]\n[color=#A89574]%s[/color][/center]" % ["#d59700" if nd.ok else "#e0806f", it.name, "보유" if nd.ok else "보급품"], UI.FS_CAP)
		l.custom_minimum_size = Vector2(NW, NH)
		v.add_child(l)
		return v
	var k: String = nd.k
	var can: bool = not nd.ok and run.can_forge(k)
	var t := gs.mtile(k, -1, func(id): gs.recipe_sheet(id) if DB.RECOF.has(id) else gs.card_info(id))
	t.custom_minimum_size = Vector2(NW, NH)
	t.lit = can
	t.badge = "%d/%d" % [nd.have, nd.need]
	t.badge_col = Color(DB.PAL.jade, 0.9) if nd.ok else Color(DB.PAL.seal, 0.9)
	t.dim = nd.have <= 0 and not can
	v.add_child(t)
	if nd.ok:
		var ok := UI.lbl("✓", UI.FS_CAP, DB.PAL.jade)
		ok.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		ok.custom_minimum_size = Vector2(NW, BTN - 2)
		v.add_child(ok)
	elif can:
		var b := UI.btn("조합", func():
			if gs.act("forge", [k]):
				gs.toast("%s 조합 완료" % DB.C[k].name, "gain"), "pri", BTN - 2)
		b.disabled = not gs.can_act()
		b.add_theme_font_size_override("font_size", UI.FS_CAP)
		v.add_child(b)
	elif not nd.kids.is_empty() or int(nd.get("basic", 0)) > 0:
		var path: String = nd.path
		var fb := UI.btn("재료 ▾", func():
			focus[root] = path
			gs.render(), "ghost", BTN - 2)
		fb.add_theme_font_size_override("font_size", UI.FS_CAP)
		v.add_child(fb)
	else:
		var nl := UI.lbl("구해야 함", UI.FS_CAP, DB.PAL.seal.lightened(0.25))      # 조합법이 없는 재료 —— 선택권 · 상점으로
		nl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		nl.custom_minimum_size = Vector2(NW, BTN - 2)
		v.add_child(nl)
	return v


## 맨 아래까지 다 풀었을 때 아직 모자란 기본패 {기본패: 장 수} —— 나무 전체가 쓰는 수를 병종별로 모아 가진 수를 뺀다
func base_lack(full: Dictionary) -> Dictionary:
	var need := {}
	_base_need(full, need, true)
	var out := {}
	for q in need:
		var lack: int = int(need[q]) - gs.run.have(q)
		if lack > 0:
			out[q] = lack
	return out


func _base_need(nd: Dictionary, need: Dictionary, top := false) -> void:
	if not nd.has("k") or nd.get("ok", false) or not DB.RECOF.has(nd.k):
		return
	var want: int = 1 if top else maxi(0, int(nd.need) - int(nd.have))
	var m := Run.mat_count(DB.RECOF[nd.k])
	for q in m:
		if DB.C[q].tier <= BASIC_TIER:
			need[q] = int(need.get(q, 0)) + int(m[q]) * want
	for c in nd.kids:
		_base_need(c, need)


## 완성 순서 시트 (11/15 사용자) —— 갈무리 장수의 차례(위가 먼저 —— 「순서대로 모두 조합」이 이 차례로, 재료가 겹치면 위 장수가 먼저 가져간다)와
## 장수마다 그 재료(전설 · 전설 · 희귀 …)를 끝낼 차례(「모두 조합」이 앞 재료의 가지부터 조합한다)를 ▲ ▼ 로 바꾼다. 바꾸면 바로 저장(pins.json)
func order_sheet(scroll_y := 0) -> void:
	var b := gs.open_sheet("완성 순서")
	var hint := UI.hint("위에 있을수록 먼저 완성한다. 「순서대로 모두 조합」은 이 차례로 돌고, 재료가 겹치면 위 장수가 먼저 가져간다. 장수 아래 재료 차례는 「모두 조합」이 어느 재료부터 끝낼지다.")
	b.add_child(hint)
	if pins.is_empty():
		b.add_child(UI.empty("pick", "갈무리한 장수가 없다", "조합 탭에서 장수를 눌러 갈무리하면 여기서 완성 순서를 정할 수 있다."))
		return
	var moved := func():
		var y := gs._sheet_scroll.scroll_vertical
		gs.render()
		order_sheet(y)
	for i in pins.size():
		var k: String = pins[i]
		var pv := UI.vbox(UI.SP_XS)
		var row := UI.hbox(UI.SP_S)
		var no := UI.lbl(str(i + 1), UI.FS_TITLE, DB.PAL.gold, true)
		no.custom_minimum_size.x = 20
		no.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		no.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(no)
		var t := gs.mtile(k, -1, func(id): gs.recipe_sheet(id))
		t.custom_minimum_size = Vector2(46, 62)
		row.add_child(t)
		var tv := UI.vbox(2)
		tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tv.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var nl := UI.lbl(DB.C[k].name, UI.FS_LABEL, DB.tier_color(k).lightened(0.2), true)
		UI.wrap_text(nl)
		tv.add_child(nl)
		var can := gs.run.can_forge(k)
		tv.add_child(UI.lbl("%s · %s" % [DB.tier_name(k), "지금 조합 가능" if can else "모자람 %d" % gs.run.miss_count(k)], UI.FS_CAP, DB.PAL.jade if can else DB.PAL.text_dim))
		row.add_child(tv)
		row.add_child(_move_btn("▲", i > 0, func():
			move_pin(k, -1)
			moved.call()))
		row.add_child(_move_btn("▼", i < pins.size() - 1, func():
			move_pin(k, 1)
			moved.call()))
		pv.add_child(row)
		var mats := order_mats(k)
		if mats.size() >= 2:
			pv.add_child(UI.hair())
			var need := Run.mat_count(DB.RECOF[k])
			for j in mats.size():
				var q: String = mats[j]
				var mr := UI.hbox(UI.SP_S)
				var ml := UI.lbl("재료 %d" % (j + 1), UI.FS_CAP, DB.PAL.bamboo)
				ml.custom_minimum_size.x = 44
				ml.size_flags_vertical = Control.SIZE_SHRINK_CENTER
				mr.add_child(ml)
				var have := gs.run.have(q)
				var done: bool = have >= int(need[q])
				var qn := UI.lbl(DB.C[q].name, UI.FS_BODY, DB.tier_color(q).lightened(0.2), true)
				qn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				qn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
				UI.wrap_text(qn)
				mr.add_child(qn)
				var st := UI.lbl("%s %d/%d" % [DB.tier_name(q), have, int(need[q])], UI.FS_CAP, DB.PAL.jade if done else DB.PAL.text_dim)
				st.size_flags_vertical = Control.SIZE_SHRINK_CENTER
				mr.add_child(st)
				mr.add_child(_move_btn("▲", j > 0, func():
					move_mat(k, q, -1)
					moved.call()))
				mr.add_child(_move_btn("▼", j < mats.size() - 1, func():
					move_mat(k, q, 1)
					moved.call()))
				pv.add_child(mr)
		b.add_child(UI.panel(pv, 10))
	if scroll_y > 0:
		gs._restore_sheet_scroll.call_deferred(scroll_y)


## ▲ ▼ —— 48×48 (최소 터치 범위)
func _move_btn(glyph: String, on: bool, cb: Callable) -> Button:
	var mb := UI.btn(glyph, cb, "ghost", UI.HIT)
	mb.custom_minimum_size = Vector2(UI.HIT, UI.HIT)
	mb.add_theme_font_size_override("font_size", UI.FS_BODY)
	mb.disabled = not on
	mb.modulate.a = 1.0 if on else 0.35
	mb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return mb


## 트리 노드 —— {k, need, have, ok, kids[], basic(뺀 기본패 모자란 수)} 또는 {item, ok}
## full 이면 접힘과 상관없이 끝까지 (모두 조합이 쓴다)
func _node(k: String, n: int, depth: int, root := "", path := "", full := false) -> Dictionary:
	var rk := k if depth == 0 else root
	return node_of(gs.run, k, n, depth, path, full, opened.get(rk, {}), morder.get(rk, []))


## 화면 없이 Run 만으로 (점검 tests/auto_forge_perf 도 쓴다) —— open = 펼친 경로들, order = 맨 위 장수의 재료 차례 (비면 조합법 차례)
static func node_of(run: Run, k: String, n: int, depth: int, path: String, full: bool, open: Dictionary, order: Array) -> Dictionary:
	var have := run.have(k)
	var nd := {"k": k, "need": n, "have": have, "ok": depth > 0 and have >= n, "kids": [], "basic": 0, "path": path}
	if nd.ok or not DB.RECOF.has(k) or depth >= MAX_DEPTH:
		return nd
	if depth >= 1 and not full and not open.has(path):
		nd["fold"] = true       # 접힌 재료 —— [재료 ▾] 로 펼친다
		return nd
	var want := n - have if depth > 0 else 1
	var m := Run.mat_count(DB.RECOF[k])
	var qs: Array = m.keys()
	if depth == 0 and not order.is_empty():
		qs = sorted_mats(qs, order)
	for q in qs:
		var need: int = m[q] * want
		if DB.C[q].tier <= BASIC_TIER:
			nd.basic += maxi(0, need - run.have(q))
			continue
		nd.kids.append(node_of(run, q, need, depth + 1, (path + "/" if path != "" else "") + q, full, open, order))
	var ni = Run.need_item(k)
	if ni != null:
		nd.kids.append({"item": ni, "ok": run.bag.get(ni, 0) > 0, "kids": []})
	return nd


## 재료를 정해 둔 차례로 (차례에 없는 재료는 조합법 차례 그대로 뒤에)
static func sorted_mats(qs: Array, order: Array) -> Array:
	var out := []
	for q in order:
		if qs.has(q) and not out.has(q):
			out.append(q)
	for q in qs:
		if not out.has(q):
			out.append(q)
	return out


## 차례를 정할 수 있는 재료 —— 맨 위 장수의 재료 가운데 스스로 조합되는 것 (기본패 · 조합법 없는 재료는 뺀다), 지금 차례로
func order_mats(root: String) -> Array:
	var qs: Array = Run.mat_count(DB.RECOF.get(root, [])).keys().filter(func(q): return DB.C[q].tier > BASIC_TIER and DB.RECOF.has(q))
	return sorted_mats(qs, morder.get(root, []))


## 갈무리 장수의 차례를 한 칸 옮긴다 (d = -1 위로 · +1 아래로)
func move_pin(k: String, d: int) -> void:
	var i := pins.find(k)
	var j := i + d
	if i < 0 or j < 0 or j >= pins.size():
		return
	pins[i] = pins[j]
	pins[j] = k
	_save()


## 재료의 차례를 한 칸 옮긴다
func move_mat(root: String, q: String, d: int) -> void:
	var lst := order_mats(root)
	var i := lst.find(q)
	var j := i + d
	if i < 0 or j < 0 or j >= lst.size():
		return
	lst[i] = lst[j]
	lst[j] = q
	morder[root] = lst
	_save()


## 갈무리 장수들이 (아래 재료까지) 필요로 하는 수 {재료: {need, root}} —— 판매 확인(11/15)이 쓴다. 기본패도 센다. root 는 차례가 가장 앞인 갈무리 장수
static func needs_of(run: Run, roots: Array) -> Dictionary:
	var out := {}
	for root in roots:
		if not DB.RECOF.has(root):
			continue
		var acc := {}
		_needs_walk(run, root, 1, 0, acc)
		for q in acc:
			if not out.has(q):
				out[q] = {"need": 0, "root": root}
			out[q].need += acc[q]
	return out


static func _needs_walk(run: Run, k: String, want: int, depth: int, acc: Dictionary) -> void:
	if want <= 0 or not DB.RECOF.has(k) or depth >= MAX_DEPTH:
		return
	var m := Run.mat_count(DB.RECOF[k])
	for q in m:
		var need: int = m[q] * want
		acc[q] = int(acc.get(q, 0)) + need
		_needs_walk(run, q, need - run.have(q), depth + 1, acc)


func _card(root: String, slim := false) -> Control:      # slim: 목표 한 줄(_goal) 아래에 펼친 나무 —— 「모두 조합」은 윗줄에 있다
	var v := UI.vbox(UI.SP_S)
	var tree := _node(root, 1, 0)
	var view := TreeView.new()
	view.ft = self
	view.build(tree)
	if view.custom_minimum_size.x > 360.0:
		var sc := UI.scroll(true)
		sc.custom_minimum_size.y = view.custom_minimum_size.y
		sc.add_child(view)
		v.add_child(sc)
		# 맨 위 장수가 가운데 오게 넘겨 둔다
		sc.ready.connect(func():
			await sc.get_tree().process_frame
			sc.scroll_horizontal = int((view.custom_minimum_size.x - sc.size.x) / 2))
	else:
		var c := CenterContainer.new()
		c.add_child(view)
		v.add_child(c)
	var row := UI.hbox(UI.SP_S)
	var can := _chain_can(tree)
	var all := UI.btn("모두 조합", func(): forge_chain(root), "pri" if can else "", UI.BH_S)
	all.disabled = not can or not gs.can_act()
	all.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if slim:
		all.free()
		row.alignment = BoxContainer.ALIGNMENT_END
	else:
		row.add_child(all)
	var ao := all_open(root)
	var ob := UI.btn("모두 접기" if ao else "모두 펴기", func(): open_all(root), "", UI.BH_S)
	ob.custom_minimum_size.x = 92
	ob.disabled = not ao and _chain_paths_empty(root)
	row.add_child(ob)
	var x := UI.btn("해제", func(): toggle(root), "ghost", UI.BH_S)
	x.custom_minimum_size.x = 64
	row.add_child(x)
	v.add_child(row)
	return v


func _chain_paths_empty(root: String) -> bool:
	var o := {}
	_collect_paths(_node(root, 1, 0, root, "", true), o)
	return o.is_empty()


## 지금 트리 안에서 하나라도 조합할 수 있는가
func _chain_can(nd: Dictionary) -> bool:
	if nd.has("k") and not nd.ok and gs.run.can_forge(nd.k):
		return true
	for c in nd.kids:
		if _chain_can(c):
			return true
	return false


## 가장 깊은 곳부터 조합할 수 있는 것
static func _deepest_forgeable(run: Run, nd: Dictionary, depth: int, best: Array) -> void:
	for c in nd.kids:
		_deepest_forgeable(run, c, depth + 1, best)
	if nd.has("k") and not nd.ok and run.can_forge(nd.k) and depth > best[1]:
		best[0] = nd.k
		best[1] = depth


## 모두 조합의 알맹이 (화면 없이) —— 가장 깊은 재료부터 되는 것을 하나씩 do_forge(k) 로 조합하고 나무를 다시 잰다. 맨 위 장수가 나오면 멈춘다.
## order(재료 완성 차례)를 정했으면 앞 재료의 가지부터 끝낸다 (그 가지에서 될 것이 없으면 다음 재료로). 만든 것을 차례로 돌려준다
static func chain(run: Run, root: String, do_forge: Callable, order: Array = [], cap := CHAIN_MAX) -> Array:
	var made := []
	for _i in cap:
		if run.can_forge(root):
			if do_forge.call(root):
				made.append(root)
			break
		var tree := node_of(run, root, 1, 0, "", true, {}, order)       # 접힌 재료 안쪽까지
		var best := [null, 0]
		if order.is_empty():
			_deepest_forgeable(run, tree, 0, best)
		else:
			for c in tree.kids:
				_deepest_forgeable(run, c, 1, best)
				if best[0] != null:
					break
		if best[0] == null or not do_forge.call(best[0]):
			break
		made.append(best[0])
	return made


## 모두 조합 —— 11/15 사용자 "자동조합 여러 명일 때 프리징": 예전에는 한 장 조합할 때마다 저장 + 화면 전체 다시 그리기(갈무리 나무 여섯 · 조합법 타일)를
## 했다 (한 번에 수십 번). 이제 조합은 조용히(gs.act_quiet) 잇달아 하고 저장 · 다시 그리기는 끝에 한 번
func forge_chain(root: String) -> void:
	_chain_run([root])


## 순서대로 모두 조합 —— 갈무리 차례(pins)대로 하나씩 모두 조합. 앞 장수가 먼저 재료를 가져간다
func forge_all() -> void:
	_chain_run(pins.duplicate())


func _chain_run(roots: Array) -> void:
	if not gs.can_act_or_tell("forge"):
		return
	var made := []
	gs._forge_quiet = true      # 11/6 #17 한 장마다 연출하지 않고 끝에 셔플로
	for root in roots:
		if gs.run.block_text(root) != "":      # 11/25 막힌 목표(선점 · 재료 선점)는 재료를 쓰지 않는다
			continue
		made.append_array(chain(gs.run, root, func(k): return gs.act_quiet("forge", [k]) == true, morder.get(root, [])))
	gs._forge_quiet = false
	if made.is_empty():
		gs.toast("지금 조합할 수 있는 재료가 없다")
		gs.render()
		return
	Sfx.play("forge")
	gs.toast("조합 %d번 — %s" % [made.size(), _made_text(made)], "gain")
	gs.changed()
	var top := 0
	for k in made:
		top = maxi(top, int(DB.C[k].tier))
	if top < 7:      # 불멸 이상은 ForgeFanfare 가 이미 떴다
		ForgeFx.play_chain(gs, made)


## 알림 글 —— 많으면 끝의 몇 개만 (수십 번 조합이면 이름 수십 개가 알림을 덮는다)
static func _made_text(made: Array) -> String:
	var names: Array = made.map(func(x): return DB.C[x].name)
	if names.size() <= 5:
		return " → ".join(names)
	return "… → " + " → ".join(names.slice(names.size() - 4))


func is_open(root: String, path: String) -> bool:
	return opened.get(root, {}).has(path)


## 펼치기 / 접기 —— 접으면 그 아래 펼친 것도 모두 접는다
func toggle_open(root: String, path: String) -> void:
	var o: Dictionary = opened.get(root, {})
	if o.has(path):
		for k in o.keys():
			if k == path or str(k).begins_with(path + "/"):
				o.erase(k)
	else:
		o[path] = true
	opened[root] = o
	gs.render()


## 나무 그림 —— 칸들을 자리 잡아 놓고, 부모 아래 가운데에서 자식들 위로 선을 긋는다
class TreeView extends Control:
	var ft: ForgeTree
	var root := ""
	var _links := []          # [부모 아래 점, 자식 위 점, 다 갖췄나]

	func build(tree: Dictionary) -> void:
		root = tree.k
		mouse_filter = Control.MOUSE_FILTER_PASS
		var w := _width(tree, 0)
		var h := _place(tree, 0, 0.0, w)
		custom_minimum_size = Vector2(w, h + 8)

	func _nw(depth: int) -> float:
		return ForgeTree.RW if depth == 0 else ForgeTree.NW

	func _width(nd: Dictionary, depth: int) -> float:
		var kw := 0.0
		for c in nd.kids:
			kw += _width(c, depth + 1) + ForgeTree.GAP
		nd["_w"] = maxf(_nw(depth), kw - ForgeTree.GAP)
		return nd._w

	## 노드를 x0 ~ x0 + span 가운데에 놓고, 자식들을 그 아래 나눠 놓는다. 이 아래로 쓴 높이를 돌려준다
	func _place(nd: Dictionary, depth: int, x0: float, span: float) -> float:
		var nw := _nw(depth)
		var nh := ForgeTree.RH if depth == 0 else ForgeTree.NH
		var cx := x0 + span / 2
		var y := _y(depth)
		var cell := _cell(nd, depth)
		cell.position = Vector2(cx - nw / 2, y)
		add_child(cell)
		var bottom := y + nh + ForgeTree.BTN
		if nd.kids.is_empty():
			return bottom
		var kx := cx - (float(nd._w) if nd._w > nw else nw) / 2
		var total := 0.0
		for c in nd.kids:
			total += float(c._w) + ForgeTree.GAP
		total -= ForgeTree.GAP
		kx = cx - total / 2
		var deepest := bottom
		for c in nd.kids:
			var cw: float = c._w
			_links.append([Vector2(cx, y + nh + ForgeTree.BTN - 4), Vector2(kx + cw / 2, _y(depth + 1)), c.get("ok", false)])
			deepest = maxf(deepest, _place(c, depth + 1, kx, cw))
			kx += cw + ForgeTree.GAP
		return deepest

	func _y(depth: int) -> float:
		if depth == 0:
			return 0.0
		return ForgeTree.RH + ForgeTree.BTN + ForgeTree.ROW + (depth - 1) * (ForgeTree.NH + ForgeTree.BTN + ForgeTree.ROW)

	## 칸 하나 —— 초상(가진 수/필요 수) + 아래 [조합] 또는 ✓
	func _cell(nd: Dictionary, depth: int) -> Control:
		var gs: GameScreen = ft.gs
		var run: Run = gs.run
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 2)
		var nw := _nw(depth)
		v.custom_minimum_size.x = nw
		if nd.has("item"):
			var it: Dictionary = DB.IT[nd.item]
			var l := UI.rich("[center][color=%s]＋%s[/color]\n[color=#A89574]%s[/color][/center]" % [
				"#d59700" if nd.ok else "#e0806f", it.name, "보유" if nd.ok else "아이템 보급품"], UI.FS_CAP)
			l.custom_minimum_size = Vector2(nw, ForgeTree.NH)
			v.add_child(l)
			return v
		var k: String = nd.k
		var t := gs.mtile(k, -1, func(id): gs.recipe_sheet(id) if DB.RECOF.has(id) else gs.card_info(id))
		t.custom_minimum_size = Vector2(nw, ForgeTree.RH if depth == 0 else ForgeTree.NH)
		t.lit = not nd.ok and run.can_forge(k)
		if depth == 0:
			t.qty = nd.have
		else:
			t.badge = "%d/%d" % [nd.have, nd.need]
			t.badge_col = Color(DB.PAL.jade, 0.9) if nd.ok else Color(DB.PAL.seal, 0.9)
			t.dim = nd.have <= 0 and not t.lit
		v.add_child(t)
		var op: bool = depth >= 1 and ft.is_open(root, nd.path)
		if nd.has("fold") or (op and not nd.ok and not run.can_forge(k)):
			var path: String = nd.path
			var fb := UI.btn("접기 ▴" if op else "재료 ▾", func(): ft.toggle_open(root, path), "ghost", ForgeTree.BTN - 2)
			fb.add_theme_font_size_override("font_size", UI.FS_CAP)
			v.add_child(fb)
		elif not nd.ok and run.can_forge(k) and depth > 0:
			var b := UI.btn("조합", func():
				if gs.act("forge", [k]):
					gs.toast("%s 조합 완료" % DB.C[k].name, "gain"), "pri", ForgeTree.BTN - 2)
			b.disabled = not gs.can_act()
			b.add_theme_font_size_override("font_size", UI.FS_CAP)
			v.add_child(b)
		else:
			var txt := ""
			if depth > 0 and nd.ok:
				txt = "✓"
			elif nd.basic > 0:
				txt = "기본패 %d장" % nd.basic
			elif depth == 0:
				txt = "모자람 %d" % run.miss_count(k)
			var l := UI.lbl(txt, UI.FS_CAP, DB.PAL.jade if nd.ok else DB.PAL.bamboo)
			l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			l.custom_minimum_size = Vector2(nw, ForgeTree.BTN - 2)
			v.add_child(l)
		return v

	func _draw() -> void:
		for ln in _links:
			var a: Vector2 = ln[0]
			var b: Vector2 = ln[1]
			var col := Color(DB.PAL.jade, 0.8) if ln[2] else Color(DB.PAL.bamboo_dim, 0.9)
			var mid := (a.y + b.y) / 2
			draw_polyline(PackedVector2Array([a, Vector2(a.x, mid), Vector2(b.x, mid), b]), col, 2.0)
