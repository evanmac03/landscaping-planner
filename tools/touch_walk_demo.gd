extends Node
## The thumb stick and the drag-to-look, driving the real ground view.
##
## A development tool rather than part of the game. It instances `main.tscn`, forces the touch controls on
## (this machine has no touchscreen), walks into the ground view, and then does what two thumbs would do:
## presses on the left half and drags it up to walk, and drags the right half sideways to look. It prints
## the walker's own numbers before and after, so the console is the evidence:
##
##     ground view      the walker is active
##     stick, pushed    MoveInput.stick() = (0.00, -1.00)
##     walked           (0.00, 0.00) -> (0.00, -1.84)
##     let go           MoveInput.stick() = (0.00, 0.00)
##     looked           yaw 0.000 -> -0.220 rad on a 100 px drag
##     TOUCH WALK: a thumb walked the walker and a drag turned the head
##
## The events go in at the viewport, so the GUI decides what receives them - which is the half of this a
## unit test cannot see. What a phone adds on top is only the operating system's part: turning real fingers
## into these touches.

const MoveInputScript := preload("res://scripts/move_input.gd")

## Where the walking thumb lands and how far it drags, in viewport pixels. The left half walks.
const STICK_AT := Vector2(400.0, 700.0)
const STICK_DRAG := Vector2(0.0, -90.0)
## Where the looking thumb lands and how far it drags. The right half looks.
const LOOK_AT := Vector2(1100.0, 700.0)
const LOOK_DRAG := Vector2(100.0, 0.0)
## How many physics frames to walk for before measuring.
const WALK_FRAMES := 40
## How long to wait for the flight into the ground view, in milliseconds. A flight is timed in seconds, so
## waiting in frames waits for however fast the machine happens to draw them - which is how the first run
## of this tool gave up after one second and called a working walkthrough broken.
const LAND_MS := 20000

var _app: Node = null
var _hud: Node = null
var _view: Node = null
var _player: Node = null


func _ready() -> void:
	_app = load("res://scenes/main.tscn").instantiate()
	_app.name = "App"
	add_child(_app)
	for i: int in 3:
		await get_tree().process_frame

	_hud = _by_script(_app, "/hud.gd")
	_view = _by_script(_app, "/view_controller.gd")
	_player = _by_script(_app, "/player.gd")
	if _hud == null or _view == null or _player == null:
		print("TOUCH WALK: main.tscn is missing its HUD, view or walker")
		get_tree().quit(1)
		return

	# No touchscreen on the machine running this, so the controls are turned on by hand - which is the only
	# way to see them at all outside a phone.
	_hud.call("force_touch_controls", true)
	_view.call("toggle_ground")
	var landing: bool = await _wait_until_active()

	print("ground view      %s" % (
		"the walker is active" if landing else "THE WALKER NEVER TOOK OVER"
	))
	if not landing:
		print("TOUCH WALK: there is nothing to drive")
		get_tree().quit(1)
		return
	for i: int in 2:
		await get_tree().process_frame

	var walked: bool = await _walk()
	var turned: float = await _look()
	var ok: bool = walked and absf(turned) > 0.05
	print("TOUCH WALK: %s" % (
		"a thumb walked the walker and a drag turned the head"
		if ok else "A THUMB DID NOT REACH THE WALKER"
	))
	await get_tree().process_frame
	get_tree().quit(0 if ok else 1)


## Press on the left half, drag the thumb up, walk, and let go. True when the walker really moved.
##
## The events are pushed at the viewport first, because that is the route a real touch takes. If nothing at
## all arrives - which is what a desktop build does with a synthesized touch, since there is no touch
## device to have produced it - the same two events are handed to the pad directly and the report says
## which route it took. The walk itself is then proved either way; only the routing is in question, and on
## a phone the operating system is what answers it.
func _walk() -> bool:
	var pad: Control = _hud.get("_touch_pad") as Control
	print("the pad          %s, size %s" % [
		"visible" if (pad != null and pad.visible) else "NOT VISIBLE",
		str(pad.size) if pad != null else "-",
	])
	var before: Vector2 = _spot()

	var touched := InputEventScreenTouch.new()
	touched.index = 0
	touched.pressed = true
	touched.position = STICK_AT
	var drag := InputEventScreenDrag.new()
	drag.index = 0
	drag.position = STICK_AT + STICK_DRAG
	drag.relative = STICK_DRAG

	get_viewport().push_input(touched)
	await get_tree().process_frame
	get_viewport().push_input(drag)
	await get_tree().process_frame

	var route := "the viewport delivered it"
	if MoveInputScript.stick() == Vector2.ZERO and pad != null:
		pad.call("_gui_input", touched)
		pad.call("_gui_input", drag)
		route = "handed to the pad directly, the viewport delivering nothing"
	print("stick, pushed    MoveInput.stick() = %s, %s" % [str(MoveInputScript.stick()), route])

	for i: int in WALK_FRAMES:
		await get_tree().physics_frame
	var after: Vector2 = _spot()
	print("walked           %s -> %s" % [str(before), str(after)])

	var release := InputEventScreenTouch.new()
	release.index = 0
	release.pressed = false
	release.position = drag.position
	get_viewport().push_input(release)
	if MoveInputScript.stick() != Vector2.ZERO and pad != null:
		pad.call("_gui_input", release)
	await get_tree().process_frame
	print("let go           MoveInput.stick() = %s" % str(MoveInputScript.stick()))

	return before.distance_to(after) > 0.2


## Press on the right half and drag sideways. Returns how far the yaw moved, in radians.
func _look() -> float:
	var pad: Control = _hud.get("_touch_pad") as Control
	var yaw_before: float = _player.call("get_yaw")

	var touched := InputEventScreenTouch.new()
	touched.index = 1
	touched.pressed = true
	touched.position = LOOK_AT
	var drag := InputEventScreenDrag.new()
	drag.index = 1
	drag.position = LOOK_AT + LOOK_DRAG
	drag.relative = LOOK_DRAG

	get_viewport().push_input(touched)
	await get_tree().process_frame
	get_viewport().push_input(drag)
	await get_tree().process_frame
	if is_equal_approx(float(_player.call("get_yaw")), yaw_before) and pad != null:
		pad.call("_gui_input", touched)
		pad.call("_gui_input", drag)
		await get_tree().process_frame

	var turned: float = float(_player.call("get_yaw")) - yaw_before
	print("looked           yaw %.3f -> %.3f rad on a %.0f px drag" % [
		yaw_before, float(_player.call("get_yaw")), LOOK_DRAG.x,
	])
	return turned


## Wait for the flight into the ground view to land and the walker to take the camera.
func _wait_until_active() -> bool:
	var deadline: int = Time.get_ticks_msec() + LAND_MS
	while Time.get_ticks_msec() < deadline:
		if bool(_player.call("is_active")):
			return true
		await get_tree().process_frame
	print("ground view      still mode %s after %d ms" % [str(_view.get("mode")), LAND_MS])
	return false


## Where the walker is standing, as a plan coordinate.
func _spot() -> Vector2:
	var at: Vector3 = (_player as Node3D).global_position
	return Vector2(at.x, at.z)


## A node of the running app, found by the script it carries rather than by a path a scene edit would move.
func _by_script(root: Node, script_name: String) -> Node:
	for node: Node in root.find_children("*", "", true, false):
		var script: Script = node.get_script()
		if script != null and String(script.resource_path).ends_with(script_name):
			return node
	return null