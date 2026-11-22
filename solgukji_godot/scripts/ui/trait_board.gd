class_name TraitBoard
extends Control
## 특기판 —— 기본은 이 카드가 가진 일반 특기만 칸으로 늘어놓는다(이름 + 레벨, 한 가지 먹색 —— 11/9 계열 색은 걷음). 판을 누르면 게임의 모든 일반 특기를
## 계열 순서로 펼치고(가진 것만 색, 없는 것은 어둡게 이름만), 다시 누르면 접는다. 펼침 상태는 다른 카드에서도 이어진다.
## 고유 특기는 여기 넣지 않는다 (UI.unique_chips 로 따로). 칸 수는 cols, 높이는 줄 수로 정해진다.

const ORDER := ["물리", "책략", "도트", "공깎", "책략깎", "방깎", "둔화", "혼란", "사기", "철벽", "인덕", "", "단체"]

static var expanded := false   # 모든 특기를 펼쳐 보는 중

var k := ""
var cols := 5
var fs := 10
var ch := 16.0
var gap := 2.0
var _all: Array = []         # 보여 줄 칸 [{name, attr, group}] —— 계열 순서 (접힘이면 가진 것만)
var _mine := {}              # 이름 -> {lv, ...}
var _pr := Press.new()       # 11/20 조작: 누름 판정은 Press 한 벌
var fixed := false           # 펼칠 수 없다 —— 가진 특기만 (아이템 보급 창, 11/3)


func setup(id: String, n_cols := 5) -> TraitBoard:
	k = id
	cols = n_cols
	for t in DB.trait_list(k):
		if not t.unique:
			_mine[t.name] = t
	mouse_filter = Control.MOUSE_FILTER_STOP
	_rebuild()
	return self


func _rebuild() -> void:
	_all = all_traits()
	if not expanded or fixed:
		_all = _all.filter(func(t): return _mine.has(t.name))
	var rows := ceili((_all.size() + (0 if fixed else 1)) / float(cols))      # 마지막 칸은 '모두 보기' · '접기'
	var h := rows * (ch + gap) - gap
	if _toggle_alone():
		h -= ch - TOGGLE_LINE_H      # 혼자 남은 토글은 칸이 아니라 낮은 글자 줄
	custom_minimum_size = Vector2(0, h)
	queue_redraw()


func _gui_input(e: InputEvent) -> void:
	if fixed:
		return
	if _pr.feed(self, e) == Press.TAP:
		UI.buzz()
		expanded = not expanded
		_rebuild()
		accept_event()


## 11/22 특기 수가 칸 수의 배수면 '모두 ▾' 칸이 혼자 새 줄로 넘어가 빈 줄처럼 보였다 (갈무리창 5특기) ——
## 그때만 칸 대신 오른쪽 끝의 낮은 글자 줄(TOGGLE_LINE_H)로 그린다. 누르는 곳은 판 전체 그대로
const TOGGLE_LINE_H := 13.0
func _toggle_alone() -> bool:
	return not fixed and _all.size() > 0 and _all.size() % cols == 0


## 사다리에 실제로 쓰이는 특기 전부 —— 계열(ORDER) 순서, 같은 계열 안은 passives.json 순서
static func all_traits() -> Array:
	var used := {}
	for p in DB.PSV.ladder:
		for e in DB.PSV.ladder[p]:
			used[e[0]] = true
	var out := []
	for cat in ORDER:
		for n in DB.PSV.traits:
			if not used.has(n) or DB.PSV.traits[n].get("unique", false):
				continue
			var t: Dictionary = DB.PSV.traits[n]
			var attr: String = t.get("attr", "")
			var group: bool = t.has("scope")
			var c2: String = "단체" if attr == "" and group else attr
			if c2 == cat:
				out.append({"name": n, "attr": attr, "group": group})
	return out


func _draw() -> void:
	var fb := DB.font_body
	var cw := (size.x - gap * (cols - 1)) / cols
	for i in _all.size():
		var t: Dictionary = _all[i]
		var r := Rect2((cw + gap) * (i % cols), (ch + gap) * (i / cols), cw, ch)
		var own: bool = _mine.has(t.name)
		var sb := StyleBoxFlat.new()      # 11/9 사용자: 계열마다 색을 칠한 칩 줄이 'AI 티' —— 가진 특기는 먹색 면 + 종이색 글 + 금 레벨, 없는 것은 옅게. 테두리 없음
		sb.set_corner_radius_all(2)
		sb.bg_color = DB.PAL.ink4 if own else Color(DB.PAL.ink3, 0.45)
		draw_style_box(sb, r)
		var lv := str(_mine[t.name].lv) if own else ""
		var f := fs
		while f > 7 and fb.get_string_size(t.name + lv, HORIZONTAL_ALIGNMENT_LEFT, -1, f).x > cw - 4:
			f -= 1
		var nw := fb.get_string_size(t.name, HORIZONTAL_ALIGNMENT_LEFT, -1, f).x
		var lw := fb.get_string_size(lv, HORIZONTAL_ALIGNMENT_LEFT, -1, f).x
		var x := r.position.x + (cw - nw - lw) / 2
		var y := r.position.y + ch / 2 + f * 0.36
		draw_string(fb, Vector2(x, y), t.name, HORIZONTAL_ALIGNMENT_LEFT, -1, f, DB.PAL.paper if own else Color(DB.PAL.bamboo_dim, 0.55))
		if own:
			draw_string(fb, Vector2(x + nw, y), lv, HORIZONTAL_ALIGNMENT_LEFT, -1, f, DB.PAL.gold)
	# 마지막 칸 —— 모두 보기 · 접기 (펼칠 수 없는 판은 없음)
	if fixed:
		return
	var i := _all.size()
	if _toggle_alone():
		var ty := (ch + gap) * (i / cols)
		var tl := "모든 특기 접기 ▴" if expanded else "모든 특기 보기 ▾"
		var tf := fs - 1
		draw_string(fb, Vector2(0, ty + TOGGLE_LINE_H * 0.5 + tf * 0.36), tl, HORIZONTAL_ALIGNMENT_RIGHT, size.x, tf, Color(DB.PAL.bamboo, 0.85))
		return
	var hr := Rect2((cw + gap) * (i % cols), (ch + gap) * (i / cols), cw, ch)
	var hs := StyleBoxFlat.new()
	hs.set_corner_radius_all(2)
	hs.bg_color = Color(DB.PAL.ink3, 0.6)
	draw_style_box(hs, hr)
	var label := "접기 ▴" if expanded else "모두 ▾"
	draw_string(fb, Vector2(hr.position.x, hr.position.y + ch / 2 + fs * 0.36), label, HORIZONTAL_ALIGNMENT_CENTER, cw, fs, DB.PAL.bamboo)
