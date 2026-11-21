extends Control
## Optional title screen ornament. Disable from the command line with --polish=0.

const GOLD := Color("#d9a64b")
const PAPER := Color("#f2dfb5")

var _time := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(delta: float) -> void:
	_time += delta
	queue_redraw()


func _draw() -> void:
	var w := size.x
	var h := size.y
	if w < 1.0 or h < 1.0:
		return
	var inset := clampf(w * 0.055, 18.0, 34.0)
	var edge := Color(GOLD, 0.28)
	var bright := Color(PAPER, 0.48 + 0.10 * sin(_time * 0.8))
	var corner := 22.0
	var t := 1.0

	# Four quiet corner strokes frame the changing key art without boxing it in.
	for x_sign: float in [-1.0, 1.0]:
		var x := inset if x_sign < 0.0 else w - inset
		var dx := corner * x_sign
		for y_sign: float in [-1.0, 1.0]:
			var y := inset if y_sign < 0.0 else h - inset
			var dy := corner * y_sign
			draw_line(Vector2(x, y), Vector2(x + dx, y), edge, t, true)
			draw_line(Vector2(x, y), Vector2(x, y + dy), edge, t, true)

	# A small seal inspired mark and hairline sit in the open space above the title.
	var cx := w * 0.5
	var y0 := h * 0.07
	var half := minf(54.0, w * 0.16)
	draw_line(Vector2(cx - half, y0), Vector2(cx - 9.0, y0), edge, t, true)
	draw_line(Vector2(cx + 9.0, y0), Vector2(cx + half, y0), edge, t, true)
	var diamond := PackedVector2Array([
		Vector2(cx, y0 - 5.0), Vector2(cx + 5.0, y0),
		Vector2(cx, y0 + 5.0), Vector2(cx - 5.0, y0),
	])
	draw_colored_polygon(diamond, Color(GOLD, 0.72))

	# Bottom rule gives the menu a visual anchor while keeping the art visible.
	var rule_y := h * 0.68
	draw_line(Vector2(w * 0.30, rule_y), Vector2(w * 0.46, rule_y), edge, t, true)
	draw_line(Vector2(w * 0.54, rule_y), Vector2(w * 0.70, rule_y), edge, t, true)
	draw_circle(Vector2(cx, rule_y), 1.5, bright)
