extends Node
## 11/20 조작(입력 처리) 회귀 점검 —— 커밋 a6e9df5 · f134a35 의 조작 폴리싱이 다시 깨지지 않는지 본다.
## 실행(헤드리스): Godot --headless --path . res://tests/ctl_check.tscn
## 캡처(창 실행):   Godot --path . --rendering-method mobile --resolution 450x968 res://tests/ctl_check.tscn -- --shot
##                  → 편성판에서 카드를 끌고 있는 순간을 captures/ctl_drag.png 로 찍고 끝낸다 (K 만 돈다)
## 줄마다 "통과/실패 · 이름", 끝에 "조작 점검 —— N개 · 실패 M". 실패가 있으면 종료 코드 1.
##
## 고치기 전 코드(56e6b18)로도 돌릴 수 있게, 새로 생긴 함수 · 변수(back · _render_soon · tap_ready · done_btn · _drop_fx …)는
## has_method · get · call 로만 부른다 (직접 부르면 옛 코드에서 파싱 오류로 통째로 못 돈다).
## 입력은 get_viewport().push_input(e, true) 로 넣는다 (Input.parse_input_event 는 창 배율이 곱해져 좌표가 어긋난다).
## 사용자 저장은 쓰지 않는다 (Run.dev_nosave · PlayLog.enabled = false · 가짜 접속기).

const GO_BACK := 1007      # NOTIFICATION_WM_GO_BACK_REQUEST
const InyeonUI := preload("res://scripts/ui/inyeon_ui.gd")

var gs                      # GameScreen —— 일부러 형을 안 적는다 (옛 코드에 없는 멤버를 실행 때 찾게)
var stage: Control          # 게임 화면 위에 덮는 점검용 판 (타일 · 목록을 따로 올린다)
var cnt := {}
var total := 0
var bad := 0
var shot := false


class FakeNet extends Online.PickNet:
	var sent: Array = []
	func send(d: Dictionary) -> void:
		sent.append(d)
	func save_cfg() -> void:
		pass      # 점검은 net.cfg 를 쓰지 않는다


func _ready() -> void:
	shot = OS.get_cmdline_user_args().has("--shot")
	Run.dev_nosave = true
	Run.dev_immortal = true
	PlayLog.enabled = false
	var cfg0 = _read(NetClient.CFG)
	var live0 = _read(Online.LIVE)
	gs = load("res://scenes/game.tscn").instantiate()
	add_child(gs)
	await _frames(3)
	var r := Run.new()
	r.new_game(5)
	r.dev_autoplay()
	r.dev_autoplay()
	gs.run = r
	gs._title.visible = false
	gs.go("draw")
	await _frames(10)
	gs.close_sheet()
	gs._bands.clear()
	gs._hide_band()
	await _wait(0.4)
	stage = Control.new()
	stage.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	stage.theme = UI.theme()
	var bg := ColorRect.new()
	bg.color = DB.PAL.ink
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	stage.add_child(bg)
	stage.visible = false
	add_child(stage)
	if shot:
		await _k_drag()
		get_tree().quit(1 if bad > 0 else 0)
		return
	await _d_tiles()
	await _c_scroll()
	await _c_sheet_portrait()
	await _b_swipe()
	await _a_sheet()
	await _t_tabkeys()
	await _e_focus()
	await _k_drag()
	await _battle_checks()
	await _online_checks(live0)
	if _read(NetClient.CFG) != cfg0:
		print("경고 · net.cfg 가 바뀌어 되돌린다")
		_write(NetClient.CFG, cfg0)
	await _a_title()
	print("조작 점검 —— %d개 · 실패 %d" % [total, bad])
	get_tree().quit(1 if bad > 0 else 0)


# ───────── 도우미 ─────────

func ck(name: String, ok: bool, note := "") -> void:
	total += 1
	if not ok:
		bad += 1
	print("%s · %s%s" % ["통과" if ok else "실패", name, (" —— " + note) if note != "" else ""])


func skip(name: String, why: String) -> void:
	print("건너뜀 · %s —— %s" % [name, why])


func inc(key: String) -> void:
	cnt[key] = int(cnt.get(key, 0)) + 1


func n(key: String) -> int:
	return int(cnt.get(key, 0))


func _frames(k := 2) -> void:
	for i in k:
		await get_tree().process_frame


func _wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout


func _read(path: String):
	return FileAccess.get_file_as_string(path) if FileAccess.file_exists(path) else null


func _write(path: String, text) -> void:
	if text == null:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
		return
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f != null:
		f.store_string(text)
		f.close()


func _down(p: Vector2) -> void:
	_mb(p, true)


func _up(p: Vector2) -> void:
	_mb(p, false)


func _mb(p: Vector2, on: bool) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = on
	e.position = p
	e.global_position = p
	e.button_mask = MOUSE_BUTTON_MASK_LEFT if on else 0
	get_viewport().push_input(e, true)


func _move(from: Vector2, to: Vector2) -> void:
	var e := InputEventMouseMotion.new()
	e.position = to
	e.global_position = to
	e.relative = to - from
	e.button_mask = MOUSE_BUTTON_MASK_LEFT
	get_viewport().push_input(e, true)


func _tap(p: Vector2) -> void:
	_down(p)
	await _frames(1)
	_up(p)
	await _frames(2)


## p 에서 눌러 d 만큼 steps 걸음으로 옮긴 뒤 뗀다
func _swipe(p: Vector2, d: Vector2, steps := 6) -> void:
	_down(p)
	await _frames(1)
	var prev := p
	for i in steps:
		var q := p + d * (float(i + 1) / float(steps))
		_move(prev, q)
		prev = q
		await _frames(1)
	_up(prev)
	await _frames(2)


func _key(kc: int) -> void:
	for on in [true, false]:
		var e := InputEventKey.new()
		e.keycode = kc
		e.physical_keycode = kc
		e.pressed = on
		get_viewport().push_input(e, true)
		await _frames(1)


func _all(root: Node, pred: Callable, out := []) -> Array:
	for c in root.get_children():
		if pred.call(c):
			out.append(c)
		_all(c, pred, out)
	return out


func _mid(c: Control) -> Vector2:
	return c.get_global_rect().get_center()


func _stop_scroll() -> void:
	TouchScroll._fling = null
	TouchScroll._target = null
	TouchScroll._press = Vector2.INF
	TouchScroll._cands = []


## 시트를 열고 넓은 버튼 하나를 넣는다 (누르면 cnt[key] + 1)
func _sheet_btn(key: String) -> Button:
	var body: VBoxContainer = gs.open_sheet("조작 점검")
	var b := UI.btn("넓은 버튼", inc.bind(key), "", 64)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(b)
	await _wait(0.5)
	return b


func _sheet_closed() -> bool:
	return not gs._sheet.visible or gs.get("_sheet_closing") == true


# ───────── D · L —— 타일의 판정 상수 · 소리 ─────────

func _d_tiles() -> void:
	stage.visible = true
	var k: String = gs.run.inv.keys()[0] if not gs.run.inv.is_empty() else DB.C.keys()[0]
	var mt := MiniTile.new().setup(k, 1)
	mt.position = Vector2(20, 20)
	mt.size = UI.TILE_M
	mt.tapped.connect(func(_k): inc("d_mt"))
	stage.add_child(mt)
	var ct := CardTile.new().setup(k, 1)
	ct.position = Vector2(120, 20)
	ct.tapped.connect(func(_k): inc("d_ct"))
	stage.add_child(ct)
	var lk := MiniTile.new().setup(k, 0)      # 잠긴 타일 (가지지 않았고 MiniTile.locked 에 있다)
	lk.position = Vector2(20, 130)
	lk.size = UI.TILE_M
	lk.tapped.connect(func(_k): inc("l_lk"))
	stage.add_child(lk)
	await _frames(3)
	for pr in [["MiniTile", mt, "d_mt"], ["CardTile", ct, "d_ct"]]:
		var p := _mid(pr[1])
		cnt[pr[2]] = 0
		await _swipe(p, Vector2(12, 0), 2)
		ck("D %s —— 12px 움직인 뒤 떼면 탭이 아니다" % pr[0], n(pr[2]) == 0, "tapped %d번" % n(pr[2]))
		cnt[pr[2]] = 0
		await _swipe(p, Vector2(6, 0), 1)
		ck("D %s —— 6px 는 탭이다" % pr[0], n(pr[2]) == 1, "tapped %d번" % n(pr[2]))
	# L —— 소리. Sfx._last 는 {이름: 마지막으로 재생한 시각} (Sfx.play 가 적는다)
	var last: Dictionary = Sfx._last
	if not Sfx._s.has("deny") or not Sfx._s.has("tap"):
		skip("L 소리 · 거절음", "소리 파일이 올라오지 않았다")
	else:
		var keep: Dictionary = MiniTile.locked
		MiniTile.locked = {k: "dead"}
		last.clear()
		await _tap(_mid(lk))
		ck("L 잠긴 MiniTile 탭 —— 거절음 Sfx.play(\"deny\")", last.has("deny") and n("l_lk") == 0, "재생 %s · tapped %d번" % [str(last.keys()), n("l_lk")])
		MiniTile.locked = keep
		last.clear()
		await _tap(_mid(ct))
		ck("L CardTile 탭 —— 소리가 난다", not last.is_empty(), "재생 %s" % str(last.keys()))
	for c in [mt, ct, lk]:
		c.queue_free()
	stage.visible = false
	await _frames(2)


# ───────── C —— '떼기'만 보던 처리기 (스크롤 목록 안) ─────────

func _c_scroll() -> void:
	stage.visible = true
	var sc: ScrollContainer = UI.scroll()
	sc.position = Vector2(16, 60)
	sc.size = Vector2(get_viewport().get_visible_rect().size.x - 32, 560)
	stage.add_child(sc)
	var v := UI.vbox(12)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(v)
	# 보급품 카드
	var item: Control = gs.deploy._item_card(str(DB.IT.keys()[0]), 1, "")
	v.add_child(item)
	# 인연 줄
	var ik := ""
	for k in DB.C.keys():
		if not DB.inyeon_of(k).is_empty():
			ik = k
			break
	var row: Control = null
	if ik != "":
		row = InyeonUI.detail_row(DB.inyeon_of(ik), gs._inyeon_ctx(ik), 13, true, func(_c): pass, inc.bind("c_iy"))
		v.add_child(row)
	# 진영 미리 보기 메달
	var fv := FormationView.new().setup(gs.run.board.duplicate(), gs.run.form)
	fv.on_medal = func(_k): inc("c_fv")
	v.add_child(fv)
	var pad := Control.new()
	pad.custom_minimum_size = Vector2(0, 900)
	v.add_child(pad)
	await _frames(4)
	# 줄마다: 세로로 쓸면 탭이 안 나가고, 제자리 탭은 나간다
	if row == null:
		skip("C 인연 줄", "인연이 있는 장수를 못 찾았다")
	else:
		var p := row.get_global_rect().position + Vector2(30, row.size.y / 2)
		await _c_pair("C 인연 줄(inyeon_ui)", sc, p, func(): return n("c_iy"))
	var lay: Array = fv.layout()
	if lay.is_empty():
		skip("C 진영 메달", "편성된 장수가 없다")
	else:
		sc.scroll_vertical = 0
		await _frames(2)
		var p2: Vector2 = fv.get_global_rect().position + lay[0][0] + Vector2(0, -8)
		await _c_pair("C 진영 메달(formation_view)", sc, p2, func(): return n("c_fv"))
		# 옛 처리기는 뗀 자리만 봤다 —— 옆에서 가로로 쓸어 와(목록은 세로라 굴러가지 않는다) 메달 위에서 떼면 상세가 열렸다
		sc.scroll_vertical = 0
		await _frames(2)
		p2 = fv.get_global_rect().position + lay[0][0] + Vector2(0, -8)
		var dx := -60.0 if lay[0][0].x > fv.size.x / 2.0 else 60.0
		var f0 := n("c_fv")
		await _swipe(p2 + Vector2(dx, 0), Vector2(-dx, 0), 6)
		_stop_scroll()
		ck("C 진영 메달(formation_view) —— 옆에서 쓸어 와 메달 위에서 떼면 탭이 아니다", n("c_fv") == f0, "탭 %d번" % (n("c_fv") - f0))
	sc.scroll_vertical = 0
	await _frames(2)
	var p3 := _mid(item)
	await _c_pair("C 보급품 카드(deploy_page)", sc, p3, func(): return 1 if gs._sheet.visible and gs.get("_sheet_closing") != true else 0, true)
	sc.queue_free()
	stage.visible = false
	await _frames(2)


## 세로 쓸기 → 0번, 제자리 탭 → 1번. sheet 면 탭이 시트를 여는 대상 (횟수 대신 시트가 열렸는지 —— 사이에 닫는다)
func _c_pair(name: String, sc: ScrollContainer, p: Vector2, count: Callable, sheet := false) -> void:
	var c0: int = count.call()
	await _swipe(p, Vector2(0, -48), 6)
	_stop_scroll()
	await _frames(2)
	var c1: int = count.call()
	ck("%s —— 세로로 쓸면 탭이 안 나간다" % name, c1 - c0 == 0, "탭 %d번 · 목록 %dpx 굴림" % [c1 - c0, sc.scroll_vertical])
	if sheet and c1 > 0:
		gs.close_sheet()
		await _wait(0.4)
	sc.scroll_vertical = 0
	await _frames(2)
	c0 = count.call()
	await _tap(p)
	c1 = count.call()
	ck("%s —— 제자리 탭은 나간다" % name, c1 - c0 == 1, "탭 %d번" % (c1 - c0))
	if sheet:
		gs.close_sheet()
		await _wait(0.4)


## 조합 시트의 초상 (UI.tap 을 쓰는 곳) —— 쓸면 상세가 안 열리고, 탭하면 열린다. 이어서 Esc 가 한 단계만 닫는지 (A)
func _c_sheet_portrait() -> void:
	var out := ""
	for rd in DB.D.RECDEF:
		if DB.RECOF.has(rd[0]) and not DB.is_foe(rd[0]):
			out = rd[0]
			break
	if out == "":
		skip("C 조합 시트 초상", "조합법이 있는 장수를 못 찾았다")
		return
	gs.recipe_sheet(out)
	await _wait(0.6)
	var cvs := _all(gs._sheet_body, func(c): return c is CardView and c.mouse_filter == Control.MOUSE_FILTER_STOP and c.is_visible_in_tree())
	if cvs.is_empty():
		skip("C 조합 시트 초상", "시트에서 초상을 못 찾았다")
		gs.close_sheet()
		await _wait(0.4)
		return
	var p := _mid(cvs[0])
	var h0: int = gs._hist.size()
	await _swipe(p, Vector2(0, -48), 6)
	_stop_scroll()
	await _wait(0.3)
	ck("C 조합 시트 초상(UI.tap) —— 세로로 쓸면 상세가 안 열린다", gs._hist.size() == h0 and str(gs._route.get("kind", "")) == "recipe", "길 %d → %d · 지금 %s" % [h0, gs._hist.size(), str(gs._route.get("kind", ""))])
	if gs._hist.size() != h0:      # 열려 버렸다 —— 조합 시트로 돌아가 탭을 본다
		gs.go_back()
		await _wait(0.5)
	gs._sheet_scroll.scroll_vertical = 0
	await _frames(3)
	cvs = _all(gs._sheet_body, func(c): return c is CardView and c.mouse_filter == Control.MOUSE_FILTER_STOP and c.is_visible_in_tree())
	if cvs.is_empty():
		skip("C 조합 시트 초상 탭", "돌아온 시트에서 초상을 못 찾았다")
		gs.close_sheet()
		await _wait(0.4)
		return
	h0 = gs._hist.size()
	await _tap(_mid(cvs[0]))
	await _wait(0.5)
	var opened: bool = gs._hist.size() == h0 + 1
	ck("C 조합 시트 초상(UI.tap) —— 제자리 탭은 상세를 연다", opened, "길 %d → %d" % [h0, gs._hist.size()])
	if opened:      # A —— 카드 시트가 두 겹일 때 Esc 는 한 단계만 (상세 → 조합 시트)
		await _key(KEY_ESCAPE)
		await _wait(0.5)
		ck("A Esc —— 시트가 두 겹이면 한 단계만 닫힌다 (상세 → 조합 시트)", gs._sheet.visible and gs._hist.size() == h0 and str(gs._route.get("kind", "")) == "recipe", "시트 %s · 길 %d" % [str(gs._sheet.visible), gs._hist.size()])
	gs._hist.clear()
	gs.close_sheet()
	await _wait(0.4)


# ───────── B —— 쓸어 닫기 ─────────

func _b_swipe() -> void:
	var b := await _sheet_btn("b")
	var p := Vector2(b.get_global_rect().position.x + 40, _mid(b).y)
	cnt["b"] = 0
	await _swipe(p, Vector2(120, 0), 8)
	await _wait(0.4)
	ck("B 쓸어 닫기 —— 버튼 위에서 오른쪽 120px 쓸면 시트가 닫힌다", not gs._sheet.visible, "시트 보임 %s" % str(gs._sheet.visible))
	ck("B 쓸어 닫기 —— 손가락 밑 버튼은 눌리지 않는다", n("b") == 0, "pressed %d번" % n("b"))
	_stop_scroll()
	gs.close_sheet()
	await _wait(0.4)
	b = await _sheet_btn("b")
	cnt["b"] = 0
	await _tap(_mid(b))
	ck("B 같은 버튼을 그냥 탭하면 한 번 눌린다", n("b") == 1, "pressed %d번" % n("b"))
	gs.close_sheet()
	await _wait(0.4)


# ───────── A —— 뒤로 / Esc (시트) ─────────

func _a_sheet() -> void:
	await _sheet_btn("a")
	await _key(KEY_ESCAPE)
	await _wait(0.4)
	ck("A Esc —— 열린 시트가 닫힌다", not gs._sheet.visible)
	gs.close_sheet()
	await _wait(0.3)
	await _sheet_btn("a")
	gs.notification(GO_BACK)
	await _wait(0.5)
	ck("A Android 뒤로 —— 열린 시트가 닫힌다", not gs._sheet.visible)
	gs.close_sheet()
	await _wait(0.3)


# ───────── T —— 탭 단축키 (1 · 2 · 3 · 4 → 징집 · 조합 · 편성 · 전투, 5 → 기록) ─────────

func _t_tabkeys() -> void:
	if not gs.has_method("tab_keys_ok"):
		skip("T 탭 단축키", "옛 코드")
		return
	gs.close_sheet()
	await _wait(0.3)
	var got := []
	for kc in [KEY_2, KEY_3, KEY_4, KEY_1, KEY_KP_2, KEY_5]:
		await _key(kc)
		await _frames(3)
		got.append(gs.page)
	ck("T 숫자 키 —— 아래 탭이 바뀐다", got.slice(0, 5) == ["forge", "deploy", "war", "draw", "forge"] and got[5] in ["rank", "line", "update"], str(got))
	gs.go("draw")
	await _frames(4)
	await _sheet_btn("a")
	await _key(KEY_3)
	await _frames(3)
	ck("T 시트가 열려 있으면 숫자 키를 받지 않는다", gs.page == "draw" and gs._sheet.visible, gs.page)
	gs.close_sheet()
	await _wait(0.3)
	gs.go("draw")
	await _frames(4)


# ───────── E —— 버튼 포커스 ─────────

func _e_focus() -> void:
	stage.visible = true
	var b := UI.btn("포커스 점검", inc.bind("e"))
	b.position = Vector2(20, 300)
	b.size = Vector2(220, 56)
	stage.add_child(b)
	await _frames(3)
	cnt["e"] = 0
	await _tap(_mid(b))
	var first := n("e")
	await _key(KEY_SPACE)
	await _frames(2)
	ck("E TouchButton 을 누른 뒤 스페이스 —— 다시 눌리지 않는다", first == 1 and n("e") == 1, "탭 뒤 %d번 · 스페이스 뒤 %d번" % [first, n("e")])
	get_viewport().gui_release_focus()
	b.queue_free()
	stage.visible = false
	await _frames(2)


# ───────── K —— 편성판 끌기 강조 (+ 캡처) ─────────

func _k_drag() -> void:
	gs.go("deploy")
	await _frames(8)
	var boxes := _all(gs, func(c): return c is DeployPage.SlotBox and c.slot >= 0 and c.is_visible_in_tree())
	var from: Control = null
	var other: Control = null
	for b in boxes:
		if gs.run.board[b.slot] != null and from == null:
			from = b
	for b in boxes:
		if b != from and (other == null or gs.run.board[b.slot] == null):
			other = b
	if from == null or other == null:
		skip("K 편성판 끌기 강조", "편성판에 장수가 놓인 칸이 없다")
		return
	var lit := func(): return boxes.filter(func(b): return is_instance_valid(b) and b.get("_drop_fx") != null).size()
	var p := _mid(from)
	_down(p)
	await _wait(0.7)      # 꾹 누르면(0.35초) 끌기가 시작된다
	var q := _mid(other)
	_move(p, p.lerp(q, 0.5))
	await _frames(2)
	_move(p.lerp(q, 0.5), q)
	await _frames(3)
	var dragging: bool = get_viewport().gui_is_dragging()
	var on: int = lit.call()
	ck("K 편성판 끌기 —— 끄는 동안 놓을 수 있는 칸이 강조된다", dragging and on > 0, "끌기 %s · 강조된 칸 %d / %d" % [str(dragging), on, boxes.size()])
	if shot:
		await _wait(0.4)
		await RenderingServer.frame_post_draw
		var path := ProjectSettings.globalize_path("res://").path_join("../captures/ctl_drag.png").simplify_path()
		var img := get_viewport().get_texture().get_image()
		img.save_png(path)
		var r := Rect2(from.get_global_rect())
		for b in boxes:
			r = r.merge(b.get_global_rect())
		var s := float(img.get_width()) / get_viewport().get_visible_rect().size.x
		print("캡처 · %s · 그림 %dx%d · 편성판 %d,%d,%d,%d" % [path, img.get_width(), img.get_height(), int(r.position.x * s), int(r.position.y * s), int(r.end.x * s), int(r.end.y * s)])
	var top := Vector2(q.x, 6)      # 놓을 수 없는 곳(머리띠)에서 뗀다 —— 편성은 그대로
	_move(q, top)
	await _frames(1)
	_up(top)
	await _frames(4)
	var off: int = lit.call()
	ck("K 편성판 끌기 —— 놓은 뒤 강조가 걷힌다", not get_viewport().gui_is_dragging() and off == 0, "끌기 %s · 강조된 칸 %d" % [str(get_viewport().gui_is_dragging()), off])
	_stop_scroll()


# ───────── F · E · G · H —— 전투 화면 ─────────

func _battle_checks() -> void:
	var bv = gs._battle
	if gs.run.placed() == 0:
		gs.run.auto_deploy()
	gs.run.battle = null
	gs._start("quest")
	var t := 0.0
	while t < 40.0 and (not gs._battle_layer.visible or bv.cards_bar.get_child_count() == 0 or bv.cards_bar.get_child(0).is_queued_for_deletion()):
		await _wait(0.2)
		t += 0.2
	await _wait(0.5)
	var live: bool = gs._battle_layer.visible and bv.cards_bar.get_child_count() > 0
	if not gs._battle_layer.visible:
		gs._battle_layer.visible = true      # 전투가 안 떴어도 키보드 · 메뉴는 볼 수 있다
		await _frames(3)
	bv._set_speed(BattleView.SPEEDS[0])
	bv.set_side_visible(false)
	await _frames(2)
	# F —— Esc 메뉴
	await _key(KEY_ESCAPE)
	var opened: bool = bv._side.visible
	await _key(KEY_ESCAPE)
	ck("F 전투 Esc —— 메뉴가 열리고 다시 누르면 닫힌다", opened and not bv._side.visible, "첫 Esc 뒤 %s · 둘째 뒤 %s" % [str(opened), str(bv._side.visible)])
	bv.set_side_visible(false)
	# F —— 숫자 2 = SPEEDS[1]
	await _key(KEY_2)
	ck("F 전투 숫자 2 —— 배속이 SPEEDS[1]", is_equal_approx(bv.speed, BattleView.SPEEDS[1]), "speed %s" % str(bv.speed))
	# E —— ⋯ 버튼을 누른 뒤 스페이스는 그 버튼이 아니라 일시정지
	bv._set_speed(BattleView.SPEEDS[0])
	var mbs := _all(bv, func(c): return c is Button and c.text == "⋯" and c.is_visible_in_tree())
	if mbs.is_empty():
		skip("E 전투 스페이스", "⋯ 버튼을 못 찾았다")
	else:
		await _tap(_mid(mbs[0]))
		var open2: bool = bv._side.visible
		await _key(KEY_SPACE)
		ck("E 전투 —— ⋯ 을 누른 뒤 스페이스는 일시정지 (버튼을 다시 누르지 않는다)", open2 and bv._side.visible and bv.speed == 0.0, "메뉴 %s → %s · speed %s" % [str(open2), str(bv._side.visible), str(bv.speed)])
		get_viewport().gui_release_focus()
	bv.set_side_visible(false)
	bv._set_speed(0.0)      # 멈춘 채로 (점검 중에 전투가 끝나지 않게)
	await _frames(2)
	# G —— 아래 장수 카드
	if not live:
		skip("G 아래 장수 카드", "전투가 뜨지 않아 카드가 없다")
	else:
		var card: Control = bv.cards_bar.get_child(0)
		var p := _mid(card)
		var hl: Dictionary = bv.hud._hl
		hl.clear()
		await _swipe(p, Vector2(0, -150), 6)
		ck("G MiniCard —— 누른 채 카드 밖으로 옮겨 떼면 발동 0번", hl.size() == 0, "강조 %d번" % hl.size())
		hl.clear()
		await _tap(p)
		ck("G MiniCard —— 안에서 떼면 발동 1번", hl.size() == 1, "강조 %d번" % hl.size())
		_stop_scroll()
	# H —— 게임 나가기 두 번 누르기
	var lb: Button = bv._leave_btn
	var keep_cb: Callable = bv.leave_cb
	bv.leave_cb = inc.bind("h")
	bv.set_side_visible(true)
	await _frames(2)
	var text0 := lb.text
	cnt["h"] = 0
	lb.pressed.emit()
	await _frames(1)
	var h1 := n("h")
	ck("H 게임 나가기 —— 첫 누름에는 나가지 않고 글이 바뀐다", h1 == 0 and lb.text != text0, "나가기 %d번 · 글 「%s」" % [h1, lb.text])
	await _wait(0.2)
	lb.pressed.emit()
	await _frames(1)
	ck("H 게임 나가기 —— 2.5초 안 두 번째 누름에 나간다", h1 == 0 and n("h") == 1, "나가기 %d번" % n("h"))
	bv.leave_cb = keep_cb
	bv.set_side_visible(false)
	# F —— 결과표에서 Enter = [종료]. 진짜 종료 버튼은 판을 정리하므로 대역 버튼을 넣어 센다
	ck("F 결과표 —— 게임 화면이 [종료] 버튼을 전투 화면에 넘겨 둔다 (done_btn)", bv.get("done_btn") != null and bv.get("done_btn") == gs._battle_done)
	var spy := Button.new()
	spy.text = "종료(대역)"
	spy.position = Vector2(10, 200)
	spy.size = Vector2(120, 44)
	spy.focus_mode = Control.FOCUS_NONE
	spy.pressed.connect(inc.bind("f_done"))
	gs._battle_layer.add_child(spy)
	bv.set("done_btn", spy)
	var was_fin: bool = bv.finished
	bv.finished = true
	await _frames(2)
	cnt["f_done"] = 0
	await _key(KEY_ENTER)
	ck("F 결과표에서 Enter —— [종료] 버튼 pressed 1번", n("f_done") == 1, "pressed %d번" % n("f_done"))
	bv.set("done_btn", gs._battle_done)
	spy.queue_free()
	bv.finished = was_fin
	bv.process_mode = Node.PROCESS_MODE_DISABLED      # 뒤에서 전투가 돌지 않게
	gs._battle_layer.visible = false
	gs.close_sheet()
	await _wait(0.4)


# ───────── I · J · A(온라인) ─────────

func _online_checks(live0) -> void:
	var on := Online.new()
	on.gs = gs
	gs.add_child(on)
	on.set_process(false)      # _process 는 점검이 직접 부른다
	var fake := FakeNet.new()
	add_child(fake)
	fake.set_process(false)
	on.net = fake
	on.in_game = true
	gs.go("draw")
	await _frames(6)
	# I —— 눌림이 있는 동안은 다시 그리기를 미룬다
	if not on.has_method("_render_soon"):
		ck("I 서버 state 다시 그리기 미룸 —— 누르는 동안 gs.render() 가 안 불린다", false, "_render_soon 이 없다 (state 를 받으면 곧바로 gs.render())")
		ck("I 서버 state 다시 그리기 미룸 —— 뗀 뒤 한 번 불린다", false, "_render_soon 이 없다")
	else:
		stage.visible = true      # 누름이 게임 화면의 버튼에 닿지 않게 덮는다
		await _frames(2)
		var hold := InputEventMouseButton.new()
		hold.button_index = MOUSE_BUTTON_LEFT
		hold.pressed = true
		hold.position = Vector2(5, 5)
		hold.global_position = Vector2(5, 5)
		Input.parse_input_event(hold)
		Input.flush_buffered_events()
		await _frames(2)
		var held: bool = gs.call("touch_held")
		var id0 := _page_id()
		on.call("_render_soon")
		await _frames(2)
		var id1 := _page_id()
		ck("I 서버 state 다시 그리기 미룸 —— 누르는 동안 gs.render() 가 안 불린다", held and id1 == id0 and int(on.get("_render_wait")) >= 0, "눌림 %s · 페이지 %s" % [str(held), "그대로" if id1 == id0 else "다시 그렸다"])
		var rel := InputEventMouseButton.new()
		rel.button_index = MOUSE_BUTTON_LEFT
		rel.pressed = false
		rel.position = Vector2(5, 5)
		rel.global_position = Vector2(5, 5)
		Input.parse_input_event(rel)
		Input.flush_buffered_events()
		await _frames(2)
		_stop_scroll()
		on._process(0.016)
		await _frames(2)
		var id2 := _page_id()
		on._process(0.016)
		await _frames(2)
		var id3 := _page_id()
		ck("I 서버 state 다시 그리기 미룸 —— 뗀 뒤 한 번 불린다", id2 != id1 and id3 == id2 and int(on.get("_render_wait")) < 0, "뗀 뒤 %s · 그다음 프레임 %s" % ["다시 그렸다" if id2 != id1 else "그대로", "그대로" if id3 == id2 else "또 그렸다"])
		stage.visible = false
	# J —— 준비 버튼 연타
	on.room = {"stage_no": 3}
	fake.sent.clear()
	var m := "tap_ready" if on.has_method("tap_ready") else "send_ready"      # 옛 버튼은 send_ready 를 바로 불렀다
	on.call(m, true)
	await _wait(0.1)
	on.call(m, false)
	var rd: int = fake.sent.filter(func(d): return str(d.get("t", "")) == "ready").size()
	ck("J 준비 버튼 연타(0.1초 간격 두 번) —— 서버로 나가는 메시지 1번", rd == 1, "%s 로 %d번 나갔다" % [m, rd])
	# A —— 온라인 판에서 뒤로: 바로 떠나지 않고 확인 시트
	gs.online = on
	gs._title.visible = false
	fake.sent.clear()
	var live1 = _read(Online.LIVE)
	gs.notification(GO_BACK)
	await _wait(0.6)
	var left: bool = not is_instance_valid(on) or on.is_queued_for_deletion() or gs.online == null or fake.sent.any(func(d): return str(d.get("t", "")) == "leave")
	var asked: bool = gs._sheet.visible and gs._sheet_title.text == "온라인 방에서 나갈까요?"
	ck("A 온라인 판에서 뒤로 —— 바로 online.leave() 하지 않고 확인 시트가 뜬다", not left and asked, "떠남 %s · 확인 시트 %s" % [str(left), str(asked)])
	if _read(Online.LIVE) != live1:      # 옛 코드의 leave() 가 돌아가기 표시를 지웠으면 되돌린다
		_write(Online.LIVE, live1)
	if _read(Online.LIVE) != live0 and live0 == null:
		_write(Online.LIVE, null)
	gs.close_sheet()
	await _wait(0.4)
	gs.online = null
	if is_instance_valid(on) and not on.is_queued_for_deletion():
		on.queue_free()
	fake.queue_free()
	BattleView.perf_sink = Callable()
	await _frames(3)


func _page_id() -> int:
	var host: Control = gs._fixed if gs._fixed.visible else gs._body
	var live := host.get_children().filter(func(c): return not c.is_queued_for_deletion())
	return live[-1].get_instance_id() if not live.is_empty() else 0


# ───────── A —— 뒤로 / Esc (타이틀) —— 맨 끝 (옛 코드는 여기서 앱이 꺼진다) ─────────

func _a_title() -> void:
	if not is_instance_valid(gs._title):
		await _frames(3)
	gs.close_sheet()
	gs._battle_layer.visible = false
	gs._title.visible = true
	await _wait(0.4)
	var bt0 = gs.get("_back_t")
	await _key(KEY_ESCAPE)
	await _wait(0.3)
	ck("A 타이틀에서 Esc —— 종료하지 않는다", gs.get("_back_t") == bt0 and gs._title.visible, "종료 무장 %s" % ("안 됨" if gs.get("_back_t") == bt0 else "됨"))
	# 여기까지의 합계를 먼저 찍는다 —— 옛 코드는 다음 줄(뒤로)에서 get_tree().quit() 이 불려 점검이 끝난다
	print("조작 점검(타이틀 뒤로 전까지) —— %d개 · 실패 %d" % [total, bad])
	print("A 타이틀에서 뒤로 한 번 —— 이 줄 뒤에 결과가 안 찍히면 앱이 바로 종료된 것 (실패)")
	gs.notification(GO_BACK)
	await _wait(0.5)
	var bt = gs.get("_back_t")
	var armed: bool = bt != null and Time.get_ticks_msec() - int(bt) < 2000
	ck("A 타이틀에서 뒤로 한 번 —— 종료하지 않고 알림만", bt != null and int(bt) > 0, "앱이 살아 있다")
	ck("A 타이틀에서 뒤로 —— 2초 안 두 번째면 종료할 상태 (실제 quit 은 부르지 않는다)", armed, "첫 뒤로 뒤 %dms" % (Time.get_ticks_msec() - int(bt) if bt != null else -1))
