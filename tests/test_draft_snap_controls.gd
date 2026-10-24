extends Node
## Tests for the controller's snapping surface: the switches the snapping page and the menu drive.
##
## The engine's own arithmetic is proved in `tests/test_snap.gd`. What is proved here is that the
## settings are *reachable* - that a controller assembled with no scene can turn the master switch,
## ortho, polar, grid and every object-snap mode on and off; that a setting which did not move says
## nothing; and that the master switch really gates the engine rather than merely being remembered.

const ControllerScript := preload("res://scripts/draft/draft_controller.gd")
const SnapScript := preload("res://scripts/draft/snap_engine.gd")

## Every object-snap mode, in the engine's own priority order.
const OBJECT_MODES: Array = [
	SnapScript.Mode.ENDPOINT,
	SnapScript.Mode.INTERSECTION,
	SnapScript.Mode.MIDPOINT,
	SnapScript.Mode.CENTRE,
	SnapScript.Mode.QUADRANT,
	SnapScript.Mode.PERPENDICULAR,
	SnapScript.Mode.TANGENT,
	SnapScript.Mode.NEAREST,
]


## A controller with an engine and no scene around it - the way the menu snapshot sees one.
func _controller() -> DraftController:
	var controller := ControllerScript.new()
	controller.snap = SnapScript.new()
	return controller


func test_a_bare_controller_answers_every_question_safely() -> void:
	var controller := _controller()
	assert(controller.is_snapping(), "snapping is on to begin with")
	assert(not controller.is_ortho(), "ortho is off")
	assert(not controller.is_polar(), "and so is polar")
	assert(not controller.is_grid_snap(), "and grid snapping")
	assert(controller.grid_step() > 0.0, "the grid has a pitch: %s" % controller.grid_step())
	assert(controller.polar_step_degrees() > 0.0, "and polar an increment")
	var state: Dictionary = controller.snap_state()
	for key: String in ["snapping", "modes", "ortho", "polar", "grid", "grid_step", "polar_step"]:
		assert(state.has(key), "the snapshot carries %s" % key)
	controller.free()


func test_turning_a_switch_reports_itself_once() -> void:
	var controller := _controller()
	var heard: Array[bool] = []
	controller.snap_changed.connect(func() -> void: heard.append(true))
	controller.set_ortho(true)
	assert(controller.is_ortho(), "ortho is on")
	assert(heard.size() == 1, "and it said so once, got %d" % heard.size())
	controller.set_ortho(true)
	assert(heard.size() == 1, "setting it to what it already was says nothing")
	controller.toggle_ortho()
	assert(not controller.is_ortho(), "the toggle turns it off")
	assert(heard.size() == 2, "and that said so too")
	controller.set_polar(true)
	controller.set_grid_snap(true)
	controller.set_snapping(false)
	assert(not controller.is_snapping())
	assert(heard.size() == 5, "every real move was announced, got %d" % heard.size())
	controller.free()


func test_every_object_snap_mode_can_be_turned_off_and_on() -> void:
	var controller := _controller()
	for mode: int in OBJECT_MODES:
		assert(controller.is_snap_mode(mode), "mode %d is live to begin with" % mode)
		controller.set_snap_mode(mode, false)
		assert(not controller.is_snap_mode(mode), "mode %d can be switched off" % mode)
		controller.set_snap_mode(mode, true)
		assert(controller.is_snap_mode(mode), "and back on")
	controller.free()


func test_a_step_that_is_not_a_distance_is_refused() -> void:
	var controller := _controller()
	var grid: float = controller.grid_step()
	controller.set_grid_step(0.0)
	assert(is_equal_approx(controller.grid_step(), grid), "a grid of no size is not a grid")
	controller.set_grid_step(-2.0)
	assert(is_equal_approx(controller.grid_step(), grid), "nor is a negative one")
	controller.set_grid_step(2.0)
	assert(is_equal_approx(controller.grid_step(), 2.0), "a real step is taken")
	var polar: float = controller.polar_step_degrees()
	controller.set_polar_step_degrees(0.0)
	assert(is_equal_approx(controller.polar_step_degrees(), polar), "a polar step of nothing is refused")
	controller.set_polar_step_degrees(15.0)
	assert(is_equal_approx(controller.polar_step_degrees(), 15.0))
	controller.free()


func test_the_master_switch_gates_the_engine() -> void:
	var controller := _controller()
	# Grid snapping is a constraint: it moves the point whenever nothing exact is near.
	controller.set_grid_snap(true)
	controller.set_grid_step(0.5)
	var cursor := Vector2(1.23, 4.87)
	var snapped: Dictionary = controller._pick_point(cursor, 100.0, Vector2.ZERO, false)
	assert(bool(snapped["snapped"]), "with the switch on the point moved")
	assert(int(snapped["mode"]) == SnapScript.Mode.GRID, "and the engine says what moved it")
	# The master switch off: the pick is the cursor, exactly, whatever the engine would have said.
	controller.set_snapping(false)
	var raw: Dictionary = controller._pick_point(cursor, 100.0, Vector2.ZERO, false)
	assert(not bool(raw["snapped"]), "with the switch off nothing is snapped")
	assert(Vector2(raw["point"]) == cursor, "the pick is the cursor itself: %s" % raw["point"])
	assert(String(raw["label"]) == "", "and no snap is named")
	assert(String(raw["glyph"]) == "")
	controller.free()


func test_the_snapshot_reports_what_the_switches_hold() -> void:
	var controller := _controller()
	controller.set_ortho(true)
	controller.set_grid_snap(true)
	controller.set_grid_step(1.0)
	controller.set_snap_mode(SnapScript.Mode.NEAREST, false)
	var state: Dictionary = controller.snap_state()
	assert(bool(state["ortho"]) and bool(state["grid"]), "the toggles are in the snapshot")
	assert(not bool(state["polar"]), "and one that is off is off in there too")
	assert(is_equal_approx(float(state["grid_step"]), 1.0), "with the pitch")
	var modes: Dictionary = state["modes"]
	assert(bool(modes.get(SnapScript.Mode.ENDPOINT, false)), "the exact snaps stay live")
	assert(not bool(modes.get(SnapScript.Mode.NEAREST, true)), "and the noisy one is off")
	controller.free()


func test_a_held_shift_constrains_without_turning_ortho_on() -> void:
	var controller := _controller()
	assert(not controller.is_ortho(), "the setting is off")
	# Straight along the axis from the point already picked, for this pick alone.
	var held: Dictionary = controller._pick_point(Vector2(3.0, 0.4), 100.0, Vector2.ZERO, true, true)
	assert(Vector2(held["point"]).is_equal_approx(Vector2(3, 0)), "a held Shift holds the point")
	# Released, the same cursor is left where it is.
	var free: Dictionary = controller._pick_point(Vector2(3.0, 0.4), 100.0, Vector2.ZERO, true, false)
	assert(Vector2(free["point"]).is_equal_approx(Vector2(3.0, 0.4)), "released, it is the cursor")
	assert(not controller.is_ortho(), "and the drawing's setting was never touched")
	controller.free()