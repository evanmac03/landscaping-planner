
extends Node
## The touch gestures the overhead views answer: a pinch to zoom the plan, and a two-finger drag to pan
## it.
##
## The arithmetic is tested on its own, and so is the reading of the gesture - which gesture asks for
## zoom and which for pan is a function of the event alone, and that is the half of this feature that can be
## wrong. What is *not* here is the wiring: whether a gesture pushed at the running game reaches the view
## at all. That cannot be pushed through the runner, so it is shown by `tools/touch_demo.gd`, which drives
## the real scene, and finally by a thumb on the phone.

const ViewControllerScript := preload("res://scripts/view_controller.gd")
const ViewMathScript := preload("res://scripts/view_math.gd")


# --- the arithmetic, on its own ---------------------------------------------------------


## The view's zoom is the *width of the plan it shows*, so spreading the fingers shrinks that number and
## pinching them together grows it: the multiplier is the reciprocal of the spread.
func test_spreading_the_fingers_zooms_in_and_closing_them_zooms_out() -> void:
	assert(is_equal_approx(ViewMathScript.zoom_factor_for_spread(1.0), 1.0), "still fingers are no zoom")
	assert(ViewMathScript.zoom_factor_for_spread(2.0) < 1.0, "twice as far apart shows less ground")
	assert(ViewMathScript.zoom_factor_for_spread(0.5) > 1.0, "half as far apart shows more ground")


## A spread that arrives as nothing, or as nonsense, is stillness rather than an infinite zoom.
func test_a_pinch_that_reports_no_movement_is_no_zoom_at_all() -> void:
	assert(is_equal_approx(ViewMathScript.zoom_factor_for_spread(0.0), 1.0))
	assert(is_equal_approx(ViewMathScript.zoom_factor_for_spread(-3.0), 1.0))


## A drag moves the design the opposite way, by one screen pixel's worth of ground - so dragging the
## screen's own height moves the view exactly one screenful of the plan.
func test_a_drag_moves_the_design_the_opposite_way_by_one_pixels_worth_of_ground() -> void:
	var moved: Vector2 = ViewMathScript.focus_after_screen_drag(
		Vector2(10.0, 5.0), Vector2(100.0, 0.0), 40.0, 800.0
	)
	assert(is_equal_approx(moved.x, 5.0), "dragged right, so the view moved left: %f" % moved.x)
	assert(is_equal_approx(moved.y, 5.0), "and not up or down at all")

	var full: Vector2 = ViewMathScript.focus_after_screen_drag(
		Vector2(10.0, 5.0), Vector2(0.0, 800.0), 40.0, 800.0
	)
	assert(
		is_equal_approx(full.y, 5.0 - 40.0),
		"a drag of the whole height moves one plan width of ground: %f" % full.y
	)


## A viewport with no height divides by one rather than by nothing: a finite move, not a jump to
## infinity.
func test_a_viewport_of_no_height_still_moves_the_design_finitely() -> void:
	var moved: Vector2 = ViewMathScript.focus_after_screen_drag(
		Vector2.ZERO, Vector2(10.0, 10.0), 20.0, 0.0
	)
	assert(moved.is_finite(), "a finite move: %s" % str(moved))
	assert(is_equal_approx(moved.x, -200.0), "one pixel is a whole plan width: %f" % moved.x)


# --- which gesture asks for what ---------------------------------------------------------


## A pinch is read as a zoom and two fingers dragged together as a pan. This is the reading a person's
## hands depend on, so it is held down here rather than discovered on the phone.
func test_a_pinch_is_read_as_a_zoom_and_a_two_finger_drag_as_a_pan() -> void:
	var pinch := InputEventMagnifyGesture.new()
	pinch.factor = 2.0
	pinch.position = Vector2(800.0, 450.0)
	var zoom: Dictionary = ViewControllerScript.touch_command(pinch)
	assert(zoom["kind"] == &"zoom", "a pinch zooms: %s" % str(zoom))
	assert(is_equal_approx(zoom["factor"], 0.5), "and by the reciprocal of the spread")
	assert((zoom["at"] as Vector2).is_equal_approx(Vector2(800.0, 450.0)), "about the fingers")

	var drag := InputEventPanGesture.new()
	drag.delta = Vector2(-40.0, 12.0)
	var pan: Dictionary = ViewControllerScript.touch_command(drag)
	assert(pan["kind"] == &"pan", "two fingers dragged pan: %s" % str(pan))
	assert((pan["delta"] as Vector2).is_equal_approx(Vector2(-40.0, 12.0)), "by what the glass reported")


## Anything that is not one of those two asks for nothing: a mouse moving, a key, a single touch. A single
## finger is the mouse, and on this drawing the mouse moves what is under it - so a touch must not be read
## as a pan as well, or one finger would do two things at once.
func test_a_gesture_that_is_neither_a_pinch_nor_a_drag_asks_for_nothing() -> void:
	assert(ViewControllerScript.touch_command(InputEventMouseMotion.new())["kind"] == &"none")
	assert(ViewControllerScript.touch_command(InputEventKey.new())["kind"] == &"none")
	var touch := InputEventScreenTouch.new()
	touch.pressed = true
	touch.position = Vector2(400.0, 300.0)
	assert(ViewControllerScript.touch_command(touch)["kind"] == &"none", "one finger is the mouse")
	var drag := InputEventScreenDrag.new()
	drag.relative = Vector2(30.0, 0.0)
	assert(ViewControllerScript.touch_command(drag)["kind"] == &"none", "and so is one finger moving")


## Two fingers resting on the glass ask for a zoom of one, which is the factor `zoom_by` treats as no
## movement at all - so a hand laid on the screen is not a zoom that creeps.
func test_two_fingers_resting_ask_for_a_zoom_of_one_which_moves_nothing() -> void:
	var pinch := InputEventMagnifyGesture.new()
	pinch.factor = 1.0
	pinch.position = Vector2(100.0, 100.0)
	var zoom: Dictionary = ViewControllerScript.touch_command(pinch)
	assert(zoom["kind"] == &"zoom", "it is still a pinch: %s" % str(zoom))
	assert(is_equal_approx(zoom["factor"], 1.0), "but a zoom of one: %f" % zoom["factor"])
