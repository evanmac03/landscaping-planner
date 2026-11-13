extends Node
## The two touch gestures driven at the real view, so that the half of pinch-zoom and two-finger pan
## that a unit test cannot hold down is shown to work: that a gesture reaches the view at all.
##
## A development tool rather than part of the game. It instances `main.tscn`, **closes the launch doorway** -
## both of its pages, because a `Window` is handed input before anything behind it and would eat the gestures -
## and then pushes a synthesized pinch and a two-finger drag into the real viewport: the same path an Android
## gesture takes once the platform has read it out of the touches, so everything after that point is the game's
## own code. Run `scenes/touch_demo.tscn` and read the console:
##
##     before           23.60 m of plan, focus (0.0, 0.0)
##     pinch 1.60       14.75 m of plan, focus (0.0, 0.0)
##     two-finger drag  14.75 m of plan, focus (2.622222, -1.475)
##     TOUCH DEMO: a pinch of 1.60 zoomed the plan in from 23.60 m to 14.75 m
##     TOUCH DEMO: both gestures reached the real view
##
## The doorway is closed by each page's own `request_close`, which is the one place a page of this program
## hides itself. Two other ways were measured and neither works: an Escape pushed at the root viewport never
## reaches a page inside a `Window`, and taking the door's dismissed *choice* opens the begin-a-drawing page in
## its place - the same `Window`, eating the same gestures. If a page is still up the tool **says so and
## measures nothing**, because a demo that reported gestures not reaching the view when the view was covered
## would be worse than a demo that reported nothing.
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

	# **Both doorway pages have to be away first, and this is the fault this tool had.** A `Window` is handed input
	# before anything behind it - which is the doorway's whole job - so a gesture pushed while one is up is read
	# by the page and never arrives at the view. Measured: `before 23.60 m of plan` and `pinch 1.60 23.60 m of
	# plan`, a pinch that moved nothing, with `PROBE page start_window` in the same log to say why. The doorway
	# was added to this program long after this tool was written.
	#
	# They are closed by their own hand, and then the tool *asks* whether that worked rather than assuming: a demo
	# that measured the view behind a page would report gestures that do reach it as gestures that do not, which
	# is worse than reporting nothing at all.
	var doorway: String = await _put_the_doorway_away(_app)
	if not doorway.is_empty():
		print("TOUCH DEMO: %s" % doorway)
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
		focus_after_pinch,
		DRAG_DELTA,
		size_after,
		get_viewport().get_visible_rect().size.y,
	)
	var panned: bool = focus_after_drag.is_equal_approx(expect_focus)
	print("TOUCH DEMO: %s" % _verdict(zoomed, size_before, size_after))
	if not panned:
		print(
			"TOUCH DEMO: the drag moved the focus to %s instead of the %s the same drag moves by hand"
			% [focus_after_drag, expect_focus]
		)
	var ok: bool = zoomed and panned
	print("TOUCH DEMO: %s" % ("both gestures reached the real view" if ok else "A GESTURE DID NOT REACH THE VIEW"))
	await get_tree().process_frame
	get_tree().quit(0 if ok else 1)


func _verdict(zoomed: bool, size_before: float, size_after: float) -> String:
	if not zoomed:
		return "the pinch did not zoom: %.2f m of plan before and after" % size_before
	return "a pinch of %.2f zoomed the plan in from %.2f m to %.2f m" % [PINCH_SPREAD, size_before, size_after]


## Put the doorway pages away, and say so in words if they will not go.
##
## Empty when nothing was standing over the board, or when it is gone. The words of a refusal when a page is
## still up: the caller prints them and stops, because every measurement below would be about a screen nobody is
## looking at.
##
## Each page has its own `request_close` - the one place a page of this program hides itself, so that its Close
## button, Escape, the title bar's cross and taking a choice all leave the same state. That is the door to use,
## and two dead ends were measured on the way to it:
##   - **an Escape pushed at the root viewport never reaches a page that lives in a `Window`**, because the window
##     owns its own input. That is `PageEscape`'s whole reason for existing, and the refusal below is what said so;
##   - **taking the door's dismissed *choice*** puts the door away and opens the begin-a-drawing page in its
##     place, because that is exactly what choosing the drawing board means. The second page then stands where the
##     first did, and the gesture is eaten just the same.
##
## Closing both pages by their own hand leaves the board bare and the drawing behind it untouched.
func _put_the_doorway_away(root: Node) -> String:
	var hud: Node = _hud_in(root)
	if hud == null:
		return "no HUD in main.tscn, so the doorway cannot be asked about"
	var door: StartWindow = _door_in(root)
	if door != null and door.visible:
		door.request_close()
	var begin: StartDrawingWindow = _begin_page_in(root)
	if begin != null and begin.visible:
		begin.request_close()
	await get_tree().process_frame
	if hud.is_the_doorway_up():
		return "a doorway page is still up, and a page in front receives every gesture - nothing was measured"
	return ""


## The running app's own HUD, found by the script it carries rather than by a node path a scene edit would move
## out from under this tool. The whole path is compared, not the tail of it: `phone_hud.gd` also ends in `hud.gd`.
func _hud_in(root: Node) -> Node:
	for node: Node in root.find_children("*", "", true, false):
		var script: Script = node.get_script()
		if script != null and String(script.resource_path) == "res://scripts/hud.gd":
			return node
	return null


## The door itself, found by its own class rather than by a name a scene edit would move out from under this tool.
func _door_in(root: Node) -> StartWindow:
	for node: Node in root.find_children("*", "", true, false):
		var door: StartWindow = node as StartWindow
		if door != null:
			return door
	return null


## The begin-a-drawing page, found the same way. It is the second page of the doorway and the one the front door
## opens the moment the drawing board is chosen, so a tool that only put the door away would measure its gestures
## against this one instead.
func _begin_page_in(root: Node) -> StartDrawingWindow:
	for node: Node in root.find_children("*", "", true, false):
		var begin: StartDrawingWindow = node as StartDrawingWindow
		if begin != null:
			return begin
	return null


## The running app's own view controller, found by the script it carries rather than by a node path that
## a scene edit would move out from under this tool.
func _view_controller(root: Node) -> ViewScript:
	for node: Node in root.find_children("*", "", true, false):
		var script: Script = node.get_script()
		if script != null and String(script.resource_path).ends_with("view_controller.gd"):
			return node
	return null
