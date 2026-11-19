class_name Press
extends RefCounted
## 11/20 조작 폴리싱 —— 누름 판정을 한 군데서. 사용자: "조작 폴리싱"
##
## 예전에는 곳마다 판정이 달랐다: '떼기'만 보는 처리기(목록을 쓸면 TouchScroll 이 넣는 화면 밖 떼기를 탭으로 받아 시트가 열렸다),
## 탭 취소 거리 14px(스크롤 시작 10px 보다 커서 죽은 값), 꾹 누름 0.35 · 0.45초가 섞여 있었다.
## 이제 손으로 입력을 받는 컨트롤은 이 도우미로 판정한다:
##
##   var _pr := Press.new()
##   func _gui_input(e: InputEvent) -> void:
##       match _pr.feed(self, e):
##           Press.TAP: ...          # 범위 안에서 눌러, TAP_SLOP 안에서, 범위 안에서 뗐다
##           Press.CANCEL: ...       # 움직였거나 밖에서 뗐다 (눌림 모양을 걷을 때)
##   func _process(_dt): if _pr.long_due(): ...   # 꾹 누름 (한 번만 참)
##
## 상수는 TouchScroll.SLOP(10)과 맞춘다 —— 스크롤이 시작되는 거리와 탭이 취소되는 거리가 같아야 한다.

const TAP_SLOP := 10.0       # 이만큼 움직이면 탭이 아니다 (= TouchScroll.SLOP)
const HOLD_DRAG := 0.35      # 꾹 눌러 끌기 시작 (초)
const LONG_PRESS := 0.45     # 꾹 눌러 보기 · 판매 (초)
const SWIPE_CLOSE := 90.0    # 오른쪽으로 쓸어 닫기 (px)

enum { NONE, DOWN, TAP, CANCEL }

var down := Vector2.INF      # 누른 자리 (컨트롤 좌표). INF 면 누르고 있지 않다
var t0 := 0                  # 누른 시각 (ms)
var long_fired := false      # 꾹 누름이 이미 났다 —— 뗄 때 탭으로 또 치지 않는다


## 누르고 있는가
func held() -> bool:
	return down != Vector2.INF


## 누름을 걷는다 (화면이 바뀌었을 때 등)
func reset() -> void:
	down = Vector2.INF
	long_fired = false


## 입력 하나를 먹인다 —— DOWN(눌렀다) · TAP(탭으로 뗐다) · CANCEL(움직이거나 밖에서 떼어 무효) · NONE
## 왼쪽 버튼(= 터치)만 본다. 휠 · 오른쪽 버튼은 NONE
func feed(c: Control, e: InputEvent) -> int:
	if e is InputEventMouseButton:
		if e.button_index != MOUSE_BUTTON_LEFT:
			return NONE
		if e.pressed:
			down = e.position
			t0 = Time.get_ticks_msec()
			long_fired = false
			return DOWN
		if down == Vector2.INF:
			return NONE
		var ok: bool = not long_fired and is_tap(c, e.position, down)
		down = Vector2.INF
		return TAP if ok else CANCEL
	if e is InputEventMouseMotion and down != Vector2.INF:
		if e.position.distance_to(down) > TAP_SLOP:
			down = Vector2.INF
			return CANCEL
	return NONE


## 꾹 누름이 찼는가 —— 한 번만 참을 돌려준다 (그 뒤 떼어도 탭이 아니다). sec 는 LONG_PRESS · HOLD_DRAG
func long_due(sec := LONG_PRESS) -> bool:
	if down == Vector2.INF or long_fired:
		return false
	if Time.get_ticks_msec() - t0 >= int(sec * 1000.0):
		long_fired = true
		return true
	return false


## 뗀 자리 up 이 탭인가 —— 누른 자리에서 TAP_SLOP 안이고 컨트롤 범위 안.
## TouchScroll 이 스크롤을 시작하며 넣는 화면 밖 '떼기'(-99999)는 여기서 걸러진다
static func is_tap(c: Control, up: Vector2, down_at: Vector2) -> bool:
	if down_at == Vector2.INF or up.x < -1000.0:
		return false
	if up.distance_to(down_at) > TAP_SLOP:
		return false
	return Rect2(Vector2.ZERO, c.size).has_point(up)
