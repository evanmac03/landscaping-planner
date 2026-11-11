extends Node
## The two touch gestures driven at the real view, so that the half of pinch-zoom and two-finger pan
## that a unit test cannot hold down is shown to work: that a gesture reaches the view at all.
##
## A development tool rather than part of the game. It instances `main.tscn` and pushes a synthesized
## pinch and a two-finger drag into the real viewport - the same path an Android gesture takes once the
## platform has read it out of the touches, so everything after that point is the game's own code. Run
## `scenes/touch_demo.tscn` and read the console:
##
##     before           23.00 m of plan, focus (0.00, 0.00)
##     pinch 1.60       14.38 m of plan, focus (0.00, 0.00)
##     two-finger drag  14.38 m of plan, focus (-2.87, 1.61)
##     TOUCH DEMO: a pinch zoomed the plan in and a two-finger drag moved the view
##
## What cannot be shown from here is the part that belongs to the operating system: whether a real thumb
## and finger produce these events. That is what the phone is for.

const ViewScript := preload("res://scripts/view_controller.gd")
const ViewMathScript := preload("res://scripts/view_math.gd")

## The pinch and the drag to send. The pinch is about the middle of the screen, which is the one place
## that leaves the focus where it is - so the drag's movement afterwards is the drag's alone.
const PINCH_SPREAD := 1.6
const DRAG_DELTA := Vector2(-160.0, 90.0)

var _app: Node = null
var _view: ViewScript = null


func _ready() -> void:
	_app = load("res://scenes/main.tscn").instantiate()
	_app.name = "App"
	add_child(_app)
	for i in 3:
		await get_tree().process_frame

	_view = _view_controller(_app)
	if _view == null:
		print("TOUCH DEMO: no view controller in main.tscn")
		get_tree().quit(1)
		return

	var size_before: float = _view.plan_size
	var focus_before: Vector2 = _view.plan_focus
	print("before           %.2f m of plan, focus %s" % [size_before, focus_before])

	var middle: Vector2 = get_viewport().get_visible_rect().size * 0.5
	var pinch := InputEventMagnifyGesture.new()
	pinch.factor = PINCH_SPREAD
	pinch.position = middle
	get_viewport().push_input(pinch)
	await get_tree().process_frame
	var size_after: float = _view.plan_size
	var focus_after_pinch: Vector2 = _view.plan_focus
	print("pinch %-9.2f  %.2f m of plan, focus %s" % [PINCH_SPREAD, size_after, focus_after_pinch])

	var drag := InputEventPanGesture.new()
	drag.delta = DRAG_DELTA
	get_viewport().push_input(drag)
	await get_tree().process_frame
	var focus_after_drag: Vector2 = _view.plan_focus
	print("two-finger drag  %.2f m of plan, focus %s" % [_view.plan_size, focus_after_drag])

	var zoomed: bool = size_after < size_before
	var expect_focus: Vector2 = ViewMathScript.focus_after_screen_drag(
		focus_after_pinch, DRAG_DELTA, size_after, get_viewport().get_visible_rect().size.y
	)
	var panned: bool = focus_after_drag.is_equal_approx(expect_focus)
	print("TOUCH DEMO: %s" % _verdict(zoomed, size_before, size_after))
	if not panned:
		print("TOUCH DEMO: the drag moved the focus to %s instead of the %s the same drag moves by hand" % [
			focus_after_drag, expect_focus,
		])
	var ok: bool = zoomed and panned
	print("TOUCH DEMO: %s" % (
		"both gestures reached the real view" if ok else "A GESTURE DID NOT REACH THE VIEW"
	))
	await get_tree().process_frame
	get_tree().quit(0 if ok else 1)


func _verdict(zoomed: bool, size_before: float, size_after: float) -> String:
	if not zoomed:
		return "the pinch did not zoom: %.2f m of plan before and after" % size_before
	return "a pinch of %.2f zoomed the plan in from %.2f m to %.2f m" % [
		PINCH_SPREAD, size_before, size_after,
	]


## The running app's own view controller, found by the script it carries rather than by a node path that
## a scene edit would move out from under this tool.
func _view_controller(root: Node) -> ViewScript:
	for node: Node in root.find_children("*", "", true, false):
		var script: Script = node.get_script()
		if script != null and String(script.resource_path).ends_with("view_controller.gd"):
			return node
	return null