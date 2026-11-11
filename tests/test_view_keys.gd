extends Node
## The ground view's way out, and the separation of the two view keys.
##
## The two keys are scoped on purpose: Q (toggle_view) owns the two overhead views and
## nothing else; G (toggle_ground) owns the ground view and nothing else. These tests
## drive the controller's *own* input handler with the very events the keys send, so
## they check the routing itself rather than a restatement of it.
##
## The bug this guards against was not a wrong destination but a missing hand-over: the
## mode variable moved to the overhead view while the player's first-person camera kept
## rendering, so the ground view was a room with no door. That is why the ground state
## is established the way a person enters it - by diving - and why the assertions look
## at which camera is current and whether the player was put away, not only at the enum.
## Setting `mode = GROUND` by hand would leave the player inactive and the flight camera
## current, which is exactly the state that hid the bug, so it is never done here.

const MAIN_PATH := "res://scenes/main.tscn"

var _main: Node = null


## Bring the planner up and settle it, returning its ViewController.
func _bring_up() -> ViewController:
	_main = load(MAIN_PATH).instantiate()
	add_child(_main)
	await get_tree().process_frame
	await get_tree().process_frame
	return _main.get_node("ViewController") as ViewController


## Take the planner back down, so a test leaves no scene behind it.
func _tear_down() -> void:
	if _main != null:
		_main.queue_free()
		_main = null
	# A test that ended inside the flat plan has switched 3D rendering off on the one
	# viewport every test shares; turn it back on so the next scene is not invisible.
	get_viewport().disable_3d = false
	await get_tree().process_frame


## Send one action as a key press, exactly as the input system would deliver it.
func _press(controller: ViewController, action: StringName) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = true
	controller._unhandled_input(event)


## Let any flight or cross-fade finish, then give the pending dispatch a chance to run.
func _settle(controller: ViewController) -> void:
	var calm := 0
	for i in 3600:
		await get_tree().process_frame
		if controller.is_transitioning():
			calm = 0
		else:
			calm += 1
			if calm >= 3:
				return


## Walk the planner down to the ground the way a person does, so the player really is
## active and really does own the camera.
func _to_ground(controller: ViewController) -> void:
	controller.mode = ViewController.ViewMode.OVERHEAD_3D
	_press(controller, &"toggle_ground")
	await _settle(controller)


## G is the one way out of the ground, and it re-enables the overhead camera.
func test_g_leaves_the_ground_for_the_overhead_view() -> void:
	var controller: ViewController = await _bring_up()
	var player: PlanPlayer = controller.get_node("../Player") as PlanPlayer
	await _to_ground(controller)
	assert(player.is_active() and player.camera.current, "the test really is down on the ground")

	_press(controller, &"toggle_ground")
	await _settle(controller)
	assert(controller.mode == ViewController.ViewMode.OVERHEAD_3D,
		"G from the ground lands on the 3D overhead view")
	assert(controller.flight_camera.current, "the flight camera is the one rendering again")
	assert(not player.is_active(), "the player was put away")
	await _tear_down()


## Q has no business in the ground view: it must not move you at all.
func test_q_does_nothing_in_the_ground_view() -> void:
	var controller: ViewController = await _bring_up()
	await _to_ground(controller)
	_press(controller, &"toggle_view")
	assert(controller.mode == ViewController.ViewMode.GROUND, "Q left the ground view alone")
	assert(not controller.is_transitioning(), "and started nothing")
	await _tear_down()


## G from the overhead view still dives to the ground, hands the camera to the player.
func test_g_dives_from_overhead_to_the_ground() -> void:
	var controller: ViewController = await _bring_up()
	var player: PlanPlayer = controller.get_node("../Player") as PlanPlayer
	controller.mode = ViewController.ViewMode.OVERHEAD_3D
	_press(controller, &"toggle_ground")
	await _settle(controller)
	assert(controller.mode == ViewController.ViewMode.GROUND, "G from overhead lands on the ground")
	assert(player.is_active(), "the player owns the camera")
	assert(player.camera.current, "the player's camera is the one rendering")
	await _tear_down()


## Q swaps the two overhead views and only those two, in both directions.
func test_q_swaps_only_the_two_overhead_views() -> void:
	var controller: ViewController = await _bring_up()
	controller.mode = ViewController.ViewMode.OVERHEAD_3D
	_press(controller, &"toggle_view")
	await _settle(controller)
	assert(controller.mode == ViewController.ViewMode.PLAN_2D, "Q shows the flat plan")
	_press(controller, &"toggle_view")
	await _settle(controller)
	assert(controller.mode == ViewController.ViewMode.OVERHEAD_3D, "Q shows the 3D overhead view")
	await _tear_down()


## Neither key can be swallowed by the other: from the ground, Q is refused and G still
## gets you out.
func test_the_two_keys_do_not_interfere() -> void:
	var controller: ViewController = await _bring_up()
	var player: PlanPlayer = controller.get_node("../Player") as PlanPlayer
	await _to_ground(controller)

	_press(controller, &"toggle_view")
	assert(controller.mode == ViewController.ViewMode.GROUND, "Q is refused on the ground")
	assert(player.camera.current, "and the ground camera is untouched by it")

	_press(controller, &"toggle_ground")
	await _settle(controller)
	assert(controller.mode == ViewController.ViewMode.OVERHEAD_3D, "G still gets you out afterwards")
	assert(controller.flight_camera.current and not player.is_active(),
		"and the overhead camera is really the one rendering")
	await _tear_down()