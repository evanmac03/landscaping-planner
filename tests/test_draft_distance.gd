extends Node
## Tests for direct distance entry through the drafting controller: what it takes to type a length,
## where the point lands, and that the entry goes away with the shape it belonged to.
##
## The controller is driven with no scene around it, against the slice of the plan canvas it actually
## talks to, so what is proved is the controller's own arithmetic and its promises. The grammar itself
## is proved in `tests/test_distance_entry.gd`.

const ControllerScript := preload("res://scripts/draft/draft_controller.gd")
const DocumentScript := preload("res://scripts/draft/draft_document.gd")
const ToolScript := preload("res://scripts/draft/draft_tool.gd")
const SnapScript := preload("res://scripts/draft/snap_engine.gd")
const Units := preload("res://scripts/draft/units.gd")

## What the plan in these tests is scaled at, so a screen point and a world point stay told apart.
const PPM := 39.0


## The part of the plan canvas a drafting controller talks to. The real one is a Node2D that reads the
## yard and draws it, which a test has no use for.
class StubCanvas extends Node2D:
	var snap: Dictionary = {}
	var ghost: Dictionary = {}
	var status_text: String = ""
	var pixels_per_metre: float = 39.0

	func set_selection(_ids: Array) -> void:
		pass

	func screen_to_world(screen: Vector2) -> Vector2:
		return screen / pixels_per_metre


## A controller with a drawing to draw on, a tool in hand and no scene around it.
func _controller() -> DraftController:
	var controller := ControllerScript.new()
	controller.snap = SnapScript.new()
	controller.tool = ToolScript.new()
	controller.canvas = StubCanvas.new()
	# The canvas goes with the controller, so one free() takes both down and no node is left behind.
	controller.add_child(controller.canvas)
	controller.document = DocumentScript.new()
	controller.drawing = true
	controller.arm(ToolScript.Kind.LINE)
	return controller


## World metres for a screen point, so a test can say where the cursor is in the drawing's own terms.
func _w(screen: Vector2) -> Vector2:
	return screen / PPM


## Type a whole length through the controller, the way a hand types it.
func _type(controller: DraftController, text: String) -> void:
	for index in text.length():
		controller.type_distance(text.substr(index, 1))


func test_a_length_cannot_be_typed_before_the_first_point() -> void:
	var controller := _controller()
	controller.set_snapping(false)
	assert(not controller.can_type_distance(), "nothing is in flight yet")
	assert(not controller.type_distance("5"), "so a number is refused")
	assert(controller.distance_text() == "", "and nothing was typed")
	assert(not controller.has_distance_entry())
	assert(
		controller.status().contains("pick the first point"),
		"and the line says what is missing: %s" % controller.status()
	)
	controller.free()


func test_the_typed_length_lands_exactly_where_it_says() -> void:
	var controller := _controller()
	controller.set_snapping(false)
	controller.click(Vector2(0.0, 0.0))
	assert(controller.can_type_distance(), "a first point is down")
	# The cursor points the way the length runs; the number says how far along it.
	controller.hover(Vector2(390.0, 0.0))
	_type(controller, "6.2")
	assert(controller.distance_text() == "6.2")
	var placed: Dictionary = controller.commit_distance()
	assert(bool(placed.get("committed", false)), "the point was placed: %s" % placed)
	assert(controller.document.count() == 1, "which made one line")
	var line = controller.document.entities()[0]
	assert(line.point(1).is_equal_approx(Vector2(6.2, 0.0)), "ending 6.2 m along the cursor: %s" % line.point(1))
	assert(not controller.has_distance_entry(), "and the typed length is done with")
	controller.free()


func test_a_typed_angle_needs_no_cursor_at_all() -> void:
	var controller := _controller()
	controller.set_snapping(false)
	controller.click(Vector2(390.0, 390.0))
	# No hover: the cursor is still sitting on the point the length would run from, which by itself says
	# nothing about direction - so an angle is the only way to place it.
	_type(controller, "5")
	assert(controller.commit_distance().is_empty(), "without a direction there is nothing to place")
	assert(
		controller.status().contains("point the cursor"),
		"and the line says so: %s" % controller.status()
	)
	assert(controller.has_distance_entry(), "while what was typed is still there to be finished")
	_type(controller, "<90")
	var placed: Dictionary = controller.commit_distance()
	assert(bool(placed.get("committed", false)), "%s" % placed)
	var line = controller.document.entities()[0]
	assert(
		line.point(1).is_equal_approx(Vector2(10.0, 15.0)),
		"five metres at ninety degrees, which is +y: %s" % line.point(1)
	)
	controller.free()


func test_an_impossible_length_is_refused_with_words_and_kept() -> void:
	var controller := _controller()
	controller.set_snapping(false)
	controller.click(Vector2(390.0, 390.0))
	controller.hover(Vector2(780.0, 390.0))
	_type(controller, "0")
	assert(controller.commit_distance().is_empty(), "a length of nothing is not a point")
	assert(
		controller.status().contains("more than nothing"),
		"and the line says why: %s" % controller.status()
	)
	assert(controller.has_distance_entry(), "while what was typed is still there to be corrected")
	controller.free()


func test_the_point_is_the_length_typed_even_with_snapping_on() -> void:
	var controller := _controller()
	# Grid snapping on, at a pitch that does not divide the length: the point must still be the length
	# that was typed, because a length that came back as the grid's nearest cell would not be it.
	controller.set_grid_snap(true)
	controller.set_grid_step(0.5)
	controller.click(Vector2(0.0, 0.0))
	controller.hover(Vector2(390.0, 0.0))
	_type(controller, "6.3")
	controller.commit_distance()
	var line = controller.document.entities()[0]
	assert(
		line.point(1).is_equal_approx(Vector2(6.3, 0.0)),
		"exactly 6.3 m, not the grid's nearest cell: %s" % line.point(1)
	)
	controller.free()


func test_the_drawing_s_own_unit_is_the_unit_typed() -> void:
	var controller := _controller()
	controller.set_snapping(false)
	controller.document.units.system = Units.System.IMPERIAL
	controller.click(Vector2(0.0, 0.0))
	controller.hover(Vector2(390.0, 0.0))
	_type(controller, "10")
	controller.commit_distance()
	var line = controller.document.entities()[0]
	assert(
		line.point(1).is_equal_approx(Vector2(3.048, 0.0)),
		"ten feet, because that is the unit the drawing measures in: %s" % line.point(1)
	)
	controller.free()


func test_the_entry_is_put_away_with_the_shape_it_belonged_to() -> void:
	var controller := _controller()
	controller.set_snapping(false)
	controller.click(Vector2(390.0, 390.0))
	assert(controller.type_distance("5"))
	assert(controller.has_distance_entry())
	controller.cancel()
	assert(not controller.has_distance_entry(), "cancelling the shape takes the length with it")
	assert(not controller.can_type_distance(), "and there is no first point left to measure from")
	# The same for a new tool: the length was going to finish *that* shape.
	controller.click(Vector2(390.0, 390.0))
	assert(controller.type_distance("5"))
	controller.set_tool(ToolScript.Kind.CIRCLE)
	assert(not controller.has_distance_entry(), "and a new tool takes it too")
	controller.free()


func test_backspace_peels_and_escape_drops_the_typed_length() -> void:
	var controller := _controller()
	controller.set_snapping(false)
	controller.click(Vector2(390.0, 390.0))
	_type(controller, "123")
	assert(controller.backspace_distance())
	assert(controller.distance_text() == "12")
	assert(controller.backspace_distance())
	assert(controller.distance_text() == "1")
	assert(controller.cancel_distance(), "escape drops what is left")
	assert(not controller.has_distance_entry())
	assert(not controller.backspace_distance(), "nothing typed, nothing to drop")
	assert(not controller.cancel_distance(), "and nothing to put away")
	controller.free()


func test_the_label_reads_as_the_length_and_the_key_that_places_it() -> void:
	var controller := _controller()
	controller.set_snapping(false)
	controller.click(Vector2(390.0, 390.0))
	assert(controller.distance_label() == "", "nothing typed, nothing to say")
	controller.type_distance("5")
	assert(controller.distance_label().contains("5"), "%s" % controller.distance_label())
	assert(
		controller.distance_label().contains("places it"),
		"the key that finishes it is named: %s" % controller.distance_label()
	)
	assert(
		controller.status().contains(controller.distance_label()),
		"and it leads the status line: %s" % controller.status()
	)
	# A `<` with nothing written after it yet is echoed rather than called a mistake, and the line does
	# not offer the key that would refuse.
	_type(controller, "<")
	assert(controller.distance_label() == "5.0 m at", "%s" % controller.distance_label())
	assert(not controller.distance_label().contains("places it"), "no key is offered yet")
	# A single digit is already a legal angle, so from here it can go down.
	_type(controller, "4")
	assert(controller.distance_label().contains("at 4.0"), "%s" % controller.distance_label())
	assert(
		controller.distance_label().contains("places it"),
		"and the key is offered again: %s" % controller.distance_label()
	)
	_type(controller, "5")
	assert(controller.distance_label().contains("at 45"), "%s" % controller.distance_label())
	controller.free()