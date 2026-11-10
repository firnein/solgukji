extends Control
## 받은 이모티콘 팝업 (11/10 사용자) —— 한마디 이모티콘을 받으면 보낸 사람 이름과 함께 큰 기호가 1.5초 떠올랐다 사라진다.
## 자리: 화면 위쪽 1/3 의 아래쪽(높이 33.5%) 가로 한 줄 가운데 —— 긴급 등용 띠(UrgentBand, 높이 23.5% 중심 ±10%)의 바로 아래라 겹치지 않고,
## 5초 경고(WarnEdge)는 가장자리뿐이다. 여러 개는 한 줄에 나란히(최대 MAX 개, 넘으면 가장 오래된 것부터 걷는다). 입력은 막지 않고 소리는 없다.
## 대기실 · 아침 · 저녁 준비 · 전투 보는 중 모두 GameScreen 위에 올려 그린다 (z_index 44 —— 시트 · 전투판 위, 긴급 띠 45 아래).
## class_name 은 만들지 않는다(낡은 .godot 캐시에서 'not declared') —— GameScreen 이 preload 로 쓴다.

const MAX := 4                  # 한꺼번에 보이는 개수
const LIFE := 1.5               # 보이는 시간 (초) —— 튀어나오는 0.18 + 머묾 + 사라지는 0.35 를 포함
const W := 104.0
const H := 126.0
const TOP := 0.335              # 화면 높이 중 줄이 시작하는 위치 (긴급 띠 아래 끝 ≈ 31.5% + 흔들림 · 떠오름 14px 을 피한다)

var _row: HBoxContainer


## 한 개 띄운다 —— k = 이모티콘 번호(Icons.EMOTES), 범위 밖이면 무시
func add(who: String, k: int) -> void:
	if k < 0 or k >= Icons.EMOTES.size():
		return
	if _row == null:
		return
	while _row.get_child_count() >= MAX:
		_row.get_child(0).free()
	var slot := Control.new()
	slot.custom_minimum_size = Vector2(W, H)
	slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_row.add_child(slot)
	var card := _Card.new()
	card.k = k
	card.who = who
	card.size = Vector2(W, H)
	card.pivot_offset = Vector2(W / 2.0, H / 2.0)
	slot.add_child(card)
	card.scale = Vector2(0.55, 0.55)
	card.modulate.a = 0.0
	var tw := card.create_tween()
	tw.set_parallel(true)
	tw.tween_property(card, "modulate:a", 1.0, 0.1)
	tw.tween_property(card, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(card, "position:y", -14.0, LIFE).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	var fade := card.create_tween()
	fade.tween_interval(LIFE - 0.35)
	fade.tween_property(card, "modulate:a", 0.0, 0.35)
	fade.tween_callback(slot.queue_free)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 44
	_row = HBoxContainer.new()
	_row.add_theme_constant_override("separation", 8)
	_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_row)


func _process(_dt: float) -> void:
	global_position = Vector2.ZERO          # 부모(GameScreen)가 크기를 갖지 않아 앵커가 듣지 않는다 (UrgentBand 와 같다)
	var vs := get_viewport_rect().size
	size = vs
	_row.position = Vector2(0, vs.y * TOP)
	_row.size = Vector2(vs.x, H)


## 카드 한 장 —— 먹색 면(모서리 4) · 큰 기호(금) · 이름(종이색)
class _Card extends Control:
	var k := 0
	var who := ""

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var sb := UI.flat(Color(DB.PAL.ink, 0.9), Color(0, 0, 0, 0), 0, UI.R, 0)
		draw_style_box(sb, Rect2(Vector2.ZERO, size))
		Icons.draw(self, Icons.EMOTES[k], Vector2(size.x / 2.0, 46.0), 62.0, DB.PAL.gold)
		var f: Font = DB.font_body
		var nm := who
		var fs := 14
		while fs > 10 and f.get_string_size(nm, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > size.x - 10.0:
			fs -= 1
		while nm.length() > 2 and f.get_string_size(nm, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > size.x - 10.0:
			nm = nm.substr(0, nm.length() - 1)
		var tw := f.get_string_size(nm, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string(f, Vector2((size.x - tw) / 2.0, 100.0), nm, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, DB.PAL.paper)
		var lf: String = Icons.EMOTE_NAMES[k]
		var lw := f.get_string_size(lf, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
		draw_string(f, Vector2((size.x - lw) / 2.0, 117.0), lf, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(DB.PAL.paper, 0.5))
