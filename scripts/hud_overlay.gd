class_name HudOverlay
extends Control
## Drawing layer for the planner's on-screen drafting aids.
##
## In either overhead view it draws the two things that make a top-down look read
## as a landscape plan: a metre scale bar and a north arrow. In the ground view it
## draws a crosshair instead. Both are suppressed during a camera flight, when
## neither view is really active.

## Lengths a scale bar is allowed to show, in metres.
const NICE_METRES: Array[float] = [1.0, 2.0, 5.0, 10.0, 20.0, 50.0, 100.0]
## Longest a scale bar may be drawn, in pixels. The largest nice length that fits
## is chosen, so the bar stays about the same size on screen at every zoom.
const BAR_MAX_PIXELS: float = 220.0

var mode: ViewController.ViewMode = ViewController.ViewMode.OVERHEAD_3D
var pixels_per_metre: float = 20.0
var transitioning: bool = false


func set_mode(new_mode: ViewController.ViewMode) -> void:
	if mode == new_mode:
		return
	mode = new_mode
	queue_redraw()


## Suppress the aids while the camera is flying between the two views.
func set_transitioning(value: bool) -> void:
	if transitioning == value:
		return
	transitioning = value
	queue_redraw()


## Update the overhead zoom. Cheap to call every frame; redraws only on change.
func set_pixels_per_metre(value: float) -> void:
	if is_equal_approx(pixels_per_metre, value):
		return
	pixels_per_metre = value
	if mode != ViewController.ViewMode.GROUND:
		queue_redraw()


func _draw() -> void:
	if transitioning:
		return
	if mode == ViewController.ViewMode.GROUND:
		_draw_crosshair()
	else:
		_draw_scale_bar()
		_draw_north_arrow()


func _draw_scale_bar() -> void:
	var metres: float = NICE_METRES[0]
	for candidate: float in NICE_METRES:
		if candidate * pixels_per_metre <= BAR_MAX_PIXELS:
			metres = candidate

	var bar_pixels: float = metres * pixels_per_metre
	var screen: Vector2 = size
	var left: float = screen.x - 44.0 - bar_pixels
	var top: float = screen.y - 52.0
	var bar_height: float = 10.0

	# A dark backing plate so the bar stays legible over grass or pale paving.
	draw_rect(
		Rect2(left - 12.0, top - 30.0, bar_pixels + 24.0, bar_height + 42.0),
		Color(0.06, 0.08, 0.09, 0.62)
	)
	# Alternating halves, the way a printed map scale bar is drawn.
	draw_rect(Rect2(left, top, bar_pixels * 0.5, bar_height), Color(0.08, 0.08, 0.08, 0.95))
	draw_rect(
		Rect2(left + bar_pixels * 0.5, top, bar_pixels * 0.5, bar_height),
		Color(0.96, 0.96, 0.94, 0.95)
	)
	draw_rect(Rect2(left, top, bar_pixels, bar_height), Color(1, 1, 1, 0.5), false, 1.0)

	var font: Font = get_theme_default_font()
	if font == null:
		return
	var label_colour := Color(0.96, 0.97, 0.94, 0.92)
	draw_string(
		font, Vector2(left, top - 8.0), "0",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 14, label_colour
	)
	draw_string(
		font, Vector2(left + bar_pixels - 44.0, top - 8.0), "%d m" % int(metres),
		HORIZONTAL_ALIGNMENT_RIGHT, 44.0, 14, label_colour
	)


func _draw_north_arrow() -> void:
	# World -Z is "up" the plan view, so north is straight up on screen.
	var screen: Vector2 = size
	var tip := Vector2(screen.x - 62.0, screen.y - 168.0)
	var half_width: float = 13.0
	var height: float = 40.0
	var waist := tip.y + height * 0.68

	draw_circle(Vector2(tip.x, tip.y + height * 0.55), 34.0, Color(0.06, 0.08, 0.09, 0.62))
	# Two triangles rather than one concave polygon, given a light and a dark half
	# so the arrow reads as folded.
	draw_colored_polygon(
		PackedVector2Array([
			tip,
			Vector2(tip.x - half_width, tip.y + height),
			Vector2(tip.x, waist),
		]),
		Color(0.96, 0.96, 0.94, 0.95)
	)
	draw_colored_polygon(
		PackedVector2Array([
			tip,
			Vector2(tip.x, waist),
			Vector2(tip.x + half_width, tip.y + height),
		]),
		Color(0.62, 0.64, 0.62, 0.95)
	)

	var font: Font = get_theme_default_font()
	if font == null:
		return
	draw_string(
		font, Vector2(tip.x - 20.0, tip.y - 12.0), "N",
		HORIZONTAL_ALIGNMENT_CENTER, 40.0, 18, Color(0.96, 0.97, 0.94, 0.92)
	)


func _draw_crosshair() -> void:
	var centre: Vector2 = size * 0.5
	var inner: float = 5.0
	var outer: float = 13.0
	var arms: Array[Vector2] = [
		Vector2.RIGHT, Vector2.LEFT, Vector2.DOWN, Vector2.UP
	]
	# Dark pass first so the crosshair survives on pale ground.
	for arm: Vector2 in arms:
		draw_line(
			centre + arm * inner + Vector2.ONE,
			centre + arm * outer + Vector2.ONE,
			Color(0.0, 0.0, 0.0, 0.35), 3.0
		)
	for arm: Vector2 in arms:
		draw_line(
			centre + arm * inner,
			centre + arm * outer,
			Color(1.0, 1.0, 1.0, 0.8), 1.5
		)
