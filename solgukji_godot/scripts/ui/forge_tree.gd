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


func _init(g: GameScreen) -> void:
	gs = g
	if FileAccess.file_exists(PATH):
		var d = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		if d is Dictionary:
			game = str(d.get("game", ""))
			d = d.get("pins", [])
		if d is Array:
			pins = d.filter(func(k): return k is String and DB.RECOF.has(k))


func _save() -> void:
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"game": game, "pins": pins}))


## 새 판 —— 갈무리를 비운다
func clear() -> void:
	pins.clear()
	opened.clear()
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
	_save()
	return other


func pinned(k: String) -> bool:
	return pins.has(k)


func toggle(k: String) -> void:
	if pins.has(k):
		pins.erase(k)
		gs.toast("%s 갈무리 해제" % DB.C[k].name)
	else:
		if pins.size() >= MAX_PINS:
			pins.pop_back()
		pins.push_front(k)
		gs.toast("%s 갈무리 — 조합 탭 맨 위에" % DB.C[k].name, "gain")
	_save()
	gs.render()


## 갈무리한 장수를 완성했다 —— 갈무리에서 뺀다 (11/3 사용자)
func done(k: String) -> void:
	if pins.has(k):
		pins.erase(k)
		opened.erase(k)
		_save()
		gs.toast("%s 완성 — 갈무리에서 뺐다" % DB.C[k].name, "gain")


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
	var v := UI.vbox(8)
	if pins.is_empty():          # 11/2 사용자: 갈무리 안내 글은 빼고 공간 확보
		v.visible = false
		return v
	for k in pins:
		v.add_child(UI.panel(_card(k), 10))
	return v


## 트리 노드 —— {k, need, have, ok, kids[], basic(뺀 기본패 모자란 수)} 또는 {item, ok}
## full 이면 접힘과 상관없이 끝까지 (모두 조합이 쓴다)
func _node(k: String, n: int, depth: int, root := "", path := "", full := false) -> Dictionary:
	var run: Run = gs.run
	var have := run.have(k)
	var nd := {"k": k, "need": n, "have": have, "ok": depth > 0 and have >= n, "kids": [], "basic": 0, "path": path}
	if nd.ok or not DB.RECOF.has(k) or depth >= MAX_DEPTH:
		return nd
	if depth >= 1 and not full and not is_open(root, path):
		nd["fold"] = true       # 접힌 재료 —— [재료 ▾] 로 펼친다
		return nd
	var want := n - have if depth > 0 else 1
	var m := Run.mat_count(DB.RECOF[k])
	for q in m:
		var need: int = m[q] * want
		if DB.C[q].tier <= BASIC_TIER:
			nd.basic += maxi(0, need - run.have(q))
			continue
		nd.kids.append(_node(q, need, depth + 1, root if depth > 0 else k, (path + "/" if path != "" else "") + q, full))
	var ni = Run.need_item(k)
	if ni != null:
		nd.kids.append({"item": ni, "ok": run.bag.get(ni, 0) > 0, "kids": []})
	return nd


func _card(root: String) -> Control:
	var v := UI.vbox(6)
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
	var row := UI.hbox(6)
	var can := _chain_can(tree)
	var all := UI.btn("모두 조합", func(): forge_chain(root), "pri" if can else "", 40)
	all.disabled = not can or not gs.can_act()
	all.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(all)
	var ao := all_open(root)
	var ob := UI.btn("모두 접기" if ao else "모두 펴기", func(): open_all(root), "", 40)
	ob.custom_minimum_size.x = 92
	ob.disabled = not ao and _chain_paths_empty(root)
	row.add_child(ob)
	var x := UI.btn("해제", func(): toggle(root), "ghost", 40)
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
func _deepest_forgeable(nd: Dictionary, depth: int, best: Array) -> void:
	for c in nd.kids:
		_deepest_forgeable(c, depth + 1, best)
	if nd.has("k") and not nd.ok and gs.run.can_forge(nd.k) and depth > best[1]:
		best[0] = nd.k
		best[1] = depth


## 모두 조합 —— 가장 깊은 재료부터 되는 것을 하나씩 조합하고, 트리를 다시 잰다. 맨 위 장수가 나오면 멈춘다
func forge_chain(root: String) -> void:
	var made := []
	gs._forge_quiet = true      # 11/6 #17 한 장마다 연출하지 않고 끝에 셔플로
	for _i in 40:
		if gs.run.can_forge(root):
			if gs.act("forge", [root]):
				made.append(root)
			break
		var best := [null, 0]
		_deepest_forgeable(_node(root, 1, 0, root, "", true), 0, best)       # 접힌 재료 안쪽까지
		if best[0] == null or not gs.act("forge", [best[0]]):
			break
		made.append(best[0])
	gs._forge_quiet = false
	if made.is_empty():
		gs.toast("지금 조합할 수 있는 재료가 없다")
	else:
		gs.toast("조합 %d번 — %s" % [made.size(), " → ".join(made.map(func(x): return DB.C[x].name))], "gain")
		if DB.C[made[made.size() - 1]].tier < 7:      # 불멸 이상은 ForgeFanfare 가 이미 떴다
			ForgeFx.play_chain(gs, made)


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
			var l := UI.rich("[center][color=%s]＋%s[/color]\n[color=#8D7B5C]%s[/color][/center]" % [
				"#d59700" if nd.ok else "#e0806f", it.name, "보유" if nd.ok else "아이템 보급품"], 12)
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
			fb.add_theme_font_size_override("font_size", 11)
			v.add_child(fb)
		elif not nd.ok and run.can_forge(k) and depth > 0:
			var b := UI.btn("조합", func():
				if gs.act("forge", [k]):
					gs.toast("%s 조합 완료" % DB.C[k].name, "gain"), "pri", ForgeTree.BTN - 2)
			b.disabled = not gs.can_act()
			b.add_theme_font_size_override("font_size", 12)
			v.add_child(b)
		else:
			var txt := ""
			if depth > 0 and nd.ok:
				txt = "✓"
			elif nd.basic > 0:
				txt = "기본패 %d장" % nd.basic
			elif depth == 0:
				txt = "모자람 %d" % run.miss_count(k)
			var l := UI.lbl(txt, 11, DB.PAL.jade if nd.ok else DB.PAL.bamboo)
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
