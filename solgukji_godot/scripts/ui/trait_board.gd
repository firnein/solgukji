class_name TraitBoard
extends Control
## 특기판 —— 게임의 모든 일반 특기를 (고유 특기는 빼고 —— UI.trait_chips 로 따로) 계열 순서로 같은 폭 칸에 늘어놓고, 이 카드가 가진 특기만 계열 색으로 칠한다(이름 + 레벨).
## 없는 특기는 어둡게 이름만. 칸 수는 cols, 높이는 줄 수로 정해진다.

const ORDER := ["", "화공", "수공", "돌파", "표적", "철벽", "계략", "인덕", "단체"]

var k := ""
var cols := 5
var fs := 10
var ch := 16.0
var gap := 2.0
var _all: Array = []         # [{name, attr, group}] —— 계열 순서
var _mine := {}              # 이름 -> {lv, ...}


func setup(id: String, n_cols := 5) -> TraitBoard:
	k = id
	cols = n_cols
	_all = all_traits()
	for t in DB.trait_list(k):
		if not t.unique:
			_mine[t.name] = t
	var rows := ceili(_all.size() / float(cols))
	custom_minimum_size = Vector2(0, rows * (ch + gap) - gap)
	mouse_filter = Control.MOUSE_FILTER_PASS
	return self


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
		var col := DB.trait_col(t)
		var own: bool = _mine.has(t.name)
		var sb := StyleBoxFlat.new()
		sb.set_corner_radius_all(3)
		sb.set_border_width_all(1)
		if own:
			sb.bg_color = col.darkened(0.35)
			sb.border_color = col.lightened(0.25)
		else:
			sb.bg_color = DB.PAL.ink2
			sb.border_color = Color(col, 0.28)
		draw_style_box(sb, r)
		var lv := str(_mine[t.name].lv) if own else ""
		var f := fs
		while f > 7 and fb.get_string_size(t.name + lv, HORIZONTAL_ALIGNMENT_LEFT, -1, f).x > cw - 4:
			f -= 1
		var nw := fb.get_string_size(t.name, HORIZONTAL_ALIGNMENT_LEFT, -1, f).x
		var lw := fb.get_string_size(lv, HORIZONTAL_ALIGNMENT_LEFT, -1, f).x
		var x := r.position.x + (cw - nw - lw) / 2
		var y := r.position.y + ch / 2 + f * 0.36
		draw_string(fb, Vector2(x, y), t.name, HORIZONTAL_ALIGNMENT_LEFT, -1, f, Color("#F2EEE4") if own else Color(DB.PAL.bamboo_dim, 0.55))
		if own:
			draw_string(fb, Vector2(x + nw, y), lv, HORIZONTAL_ALIGNMENT_LEFT, -1, f, Color("#FFD76E"))
