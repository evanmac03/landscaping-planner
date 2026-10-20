extends Node
## Tests for drawing a ground zone by hand: a closed ring the designer draws becomes a zone on the
## map rather than an entity on the drawing, because a hand zone has nothing on the plan behind it -
## the outline *is* the zone.
##
## The controller is built with its parts and no scene tree, and the ring is fed to the polygon tool
## directly: `tool.click` only collects points, and the controller's own `finish_closed` commits.

const Ctrl := preload("res://scripts/draft/draft_controller.gd")
const Tool := preload("res://scripts/draft/draft_tool.gd")
const Document := preload("res://scripts/draft/draft_document.gd")
const SnapScript := preload("res://scripts/draft/snap_engine.gd")


func _controller():
	var controller = Ctrl.new()
	controller.document = Document.new()
	controller.snap = SnapScript.new()
	controller.tool = Tool.new()
	return controller


## Feed the ring's corners to the polygon tool, then close it through the controller.
func _draw_ring(controller, corners: Array) -> Dictionary:
	for corner: Vector2 in corners:
		controller.tool.click(corner)
	return controller.finish_closed()


func _square(size: float = 10.0) -> PackedVector2Array:
	return PackedVector2Array([
		Vector2(0.0, 0.0), Vector2(size, 0.0), Vector2(size, size), Vector2(0.0, size)])


# --- drawing one ----------------------------------------------------------------------


func test_a_drawn_ring_states_a_ground_zone_and_puts_nothing_on_the_drawing() -> void:
	var controller = _controller()
	controller.begin_ground_zone()
	assert(controller.ground_zone_pending(), "the polygon tool is in hand for a zone")
	var pick: Dictionary = _draw_ring(controller, [Vector2(0, 0), Vector2(10, 0), Vector2(10, 10)])
	assert(bool(pick["committed"]), "the ring closed")
	assert(controller.document.count() == 0, "no entity: the zone holds the ring itself")
	assert(controller.document.environment.zone_count() == 1, "and the map has the zone")
	assert(not controller.ground_zone_pending(), "the purpose is spent")
	assert(controller.dirty, "stating ground is an edit")
	assert(controller.document.environment.zones[0].outline.size() == 3)
	controller.free()


func test_without_the_zone_purpose_the_same_ring_is_ordinary_geometry() -> void:
	var controller = _controller()
	controller.arm(Tool.Kind.POLYLINE)
	_draw_ring(controller, [Vector2(0, 0), Vector2(10, 0), Vector2(10, 10)])
	assert(controller.document.count() == 1, "a polygon on the drawing")
	assert(controller.document.environment.zone_count() == 0, "and nothing stated")
	controller.free()


func test_a_ground_zone_is_one_undo_step() -> void:
	var controller = _controller()
	controller.begin_ground_zone()
	_draw_ring(controller, [Vector2(0, 0), Vector2(10, 0), Vector2(10, 10)])
	assert(controller.document.environment.zone_count() == 1)
	assert(controller.document.undo_last())
	assert(controller.document.environment.zone_count() == 0, "one Ctrl+Z takes the zone off the map")
	controller.free()


func test_two_hand_zones_are_numbered_apart() -> void:
	var controller = _controller()
	controller.state_ground_zone(_square(10.0))
	controller.state_ground_zone(PackedVector2Array([
		Vector2(20, 20), Vector2(30, 20), Vector2(30, 30)]))
	assert(controller.document.environment.zone_count() == 2)
	assert(controller.document.environment.zones[1].source == "by hand:zone#2")
	controller.free()


func test_a_hand_zone_answers_for_the_ground_inside_it() -> void:
	var controller = _controller()
	controller.state_ground_zone(_square(10.0))
	assert(controller.document.environment.zone_at(Vector2(5, 5)) != null, "inside")
	assert(controller.document.environment.zone_at(Vector2(50, 50)) == null, "outside")
	controller.free()


func test_the_status_line_says_a_zone_was_stated() -> void:
	var controller = _controller()
	var stated: Dictionary = controller.state_ground_zone(_square(10.0))
	assert(bool(stated["ok"]), String(stated["reason"]))
	assert(String(stated["message"]).contains("ground zone 1"))
	controller.free()


# --- refusing, and putting it away ----------------------------------------------------


func test_a_ring_that_encloses_nothing_is_refused() -> void:
	var controller = _controller()
	var refused: Dictionary = controller.state_ground_zone(
		PackedVector2Array([Vector2(0, 0), Vector2(1, 1)]))
	assert(not bool(refused["ok"]))
	assert(String(refused["reason"]).contains("enclose"))
	assert(controller.document.environment.zone_count() == 0)
	controller.free()


func test_choosing_another_tool_drops_the_zone_purpose() -> void:
	var controller = _controller()
	controller.begin_ground_zone()
	controller.arm(Tool.Kind.LINE)
	assert(not controller.ground_zone_pending(), "a click no longer means a zone")
	controller.free()


func test_putting_the_tools_away_drops_the_zone_purpose() -> void:
	var controller = _controller()
	controller.begin_ground_zone()
	controller.set_drawing(false)
	assert(not controller.ground_zone_pending())
	controller.free()