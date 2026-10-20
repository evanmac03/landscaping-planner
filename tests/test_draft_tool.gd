extends Node
## Tests for the drawing tools: shape construction from picks, refusal of
## degenerate shapes, the rubber-band preview, and the open-ended tools.

const Tool := preload("res://scripts/draft/draft_tool.gd")
const Entity := preload("res://scripts/draft/draft_entity.gd")


func _tool(kind: Tool.Kind, layer: StringName = &"310-PAVING"):
	var tool = Tool.new()
	tool.begin(kind, layer)
	return tool


func test_a_line_commits_on_the_second_pick() -> void:
	var tool = _tool(Tool.Kind.LINE)
	var first: Dictionary = tool.click(Vector2(0, 0))
	assert(not first["committed"])
	assert(first["progress"] == 1)
	assert(tool.is_active())
	var second: Dictionary = tool.click(Vector2(4, 3))
	assert(second["committed"])
	var line = second["entity"]
	assert(line.kind == Entity.Kind.LINE)
	assert(line.point(0).is_equal_approx(Vector2(0, 0)))
	assert(line.point(1).is_equal_approx(Vector2(4, 3)))
	assert(not tool.is_active())
	assert(second["progress"] == 0)


## A zero-length line is a drafting mistake, so it is refused and the bad pick is
## handed back rather than left in the tool's state.
func test_a_degenerate_line_is_refused_and_the_pick_is_returned() -> void:
	var tool = _tool(Tool.Kind.LINE)
	tool.click(Vector2(2, 2))
	var refused: Dictionary = tool.click(Vector2(2, 2))
	assert(not refused["committed"])
	assert(refused["entity"] == null)
	assert(refused["rejected"])
	assert(tool.point_count() == 1)
	assert(tool.last_reason() != "")
	# The tool is still usable: pick somewhere else and it completes.
	assert(tool.click(Vector2(5, 2))["committed"])


func test_a_circle_takes_its_radius_from_the_second_pick() -> void:
	var tool = _tool(Tool.Kind.CIRCLE)
	tool.click(Vector2(1, 1))
	var result: Dictionary = tool.click(Vector2(4, 5))
	assert(result["committed"])
	var circle = result["entity"]
	assert(circle.kind == Entity.Kind.CIRCLE)
	assert(circle.point(0).is_equal_approx(Vector2(1, 1)))
	assert(is_equal_approx(circle.params[2], 5.0))


func test_a_circle_needs_a_radius() -> void:
	var tool = _tool(Tool.Kind.CIRCLE)
	tool.click(Vector2(1, 1))
	var refused: Dictionary = tool.click(Vector2(1, 1))
	assert(not refused["committed"])
	assert(refused["rejected"])


func test_a_rectangle_is_defined_by_its_diagonal() -> void:
	var tool = _tool(Tool.Kind.RECTANGLE)
	tool.click(Vector2(0, 0))
	var result: Dictionary = tool.click(Vector2(4, 2))
	assert(result["committed"])
	var rect = result["entity"]
	assert(rect.kind == Entity.Kind.RECT)
	assert(rect.point(0).is_equal_approx(Vector2(2, 1)))
	assert(is_equal_approx(rect.params[2], 4.0))
	assert(is_equal_approx(rect.params[3], 2.0))


func test_a_rectangle_needs_two_distinct_corners() -> void:
	var tool = _tool(Tool.Kind.RECTANGLE)
	tool.click(Vector2(0, 0))
	assert(not tool.click(Vector2(4, 0))["committed"])


func test_an_arc_is_centre_then_start_then_sweep() -> void:
	var tool = _tool(Tool.Kind.ARC)
	tool.click(Vector2(0, 0))
	var second: Dictionary = tool.click(Vector2(5, 0))
	assert(not second["committed"])
	var third: Dictionary = tool.click(Vector2(0, 5))
	assert(third["committed"])
	var arc = third["entity"]
	assert(arc.kind == Entity.Kind.ARC)
	assert(is_equal_approx(arc.params[2], 5.0))
	assert(is_equal_approx(arc.params[3], 0.0))
	assert(is_equal_approx(arc.params[4], PI * 0.5))


func test_an_arc_can_sweep_backwards() -> void:
	var tool = _tool(Tool.Kind.ARC)
	tool.click(Vector2(0, 0))
	tool.click(Vector2(5, 0))
	var clockwise: Dictionary = tool.click(Vector2(0, -5))
	assert(is_equal_approx(clockwise["entity"].params[4], -PI * 0.5))


func test_an_arc_with_no_sweep_is_refused() -> void:
	var tool = _tool(Tool.Kind.ARC)
	tool.click(Vector2(0, 0))
	tool.click(Vector2(5, 0))
	var refused: Dictionary = tool.click(Vector2(10, 0))
	assert(not refused["committed"])
	assert(refused["rejected"])


func test_a_polyline_collects_points_until_it_is_finished() -> void:
	var tool = _tool(Tool.Kind.POLYLINE)
	assert(tool.needed_points() == 0)
	tool.click(Vector2(0, 0))
	tool.click(Vector2(4, 0))
	tool.click(Vector2(4, 3))
	assert(tool.point_count() == 3)
	var finished: Dictionary = tool.finish()
	assert(finished["committed"])
	var polyline = finished["entity"]
	assert(polyline.kind == Entity.Kind.POLYLINE)
	assert(polyline.point_count() == 3)
	assert(not polyline.is_closed())
	assert(not tool.is_active())


func test_closing_a_polyline_makes_a_polygon() -> void:
	var tool = _tool(Tool.Kind.POLYLINE)
	tool.click(Vector2(0, 0))
	tool.click(Vector2(4, 0))
	tool.click(Vector2(4, 3))
	var closed: Dictionary = tool.finish_closed()
	assert(closed["committed"])
	assert(closed["entity"].kind == Entity.Kind.POLYGON)
	assert(closed["entity"].is_closed())


func test_a_polyline_needs_two_points_to_finish() -> void:
	var tool = _tool(Tool.Kind.POLYLINE)
	assert(not tool.finish()["committed"])
	tool.click(Vector2(0, 0))
	var early: Dictionary = tool.finish()
	assert(not early["committed"])
	assert(early["rejected"])
	# Nothing was thrown away in the attempt.
	assert(tool.point_count() == 1)


func test_a_closed_polyline_needs_three_points() -> void:
	var tool = _tool(Tool.Kind.POLYLINE)
	tool.click(Vector2(0, 0))
	tool.click(Vector2(4, 0))
	assert(not tool.finish_closed()["committed"])
	assert(tool.point_count() == 2)


func test_the_measure_tool_reports_a_displacement() -> void:
	var tool = _tool(Tool.Kind.MEASURE)
	assert(tool.is_measure())
	tool.click(Vector2(0, 0))
	var result: Dictionary = tool.click(Vector2(3, 4))
	assert(result["committed"])
	assert(result["entity"] == null)
	var measure: Dictionary = result["measure"]
	assert(is_equal_approx(measure["distance"], 5.0))
	assert(measure["delta"].is_equal_approx(Vector2(3, 4)))
	assert(is_equal_approx(measure["angle"], atan2(4.0, 3.0)))


func test_measure_preview_does_not_commit() -> void:
	var tool = _tool(Tool.Kind.MEASURE)
	tool.click(Vector2(0, 0))
	var preview: Dictionary = tool.preview_measure(Vector2(0, 2))
	assert(is_equal_approx(preview["distance"], 2.0))
	# Still exactly one pick in.
	assert(tool.point_count() == 1)


func test_cancel_clears_the_shape() -> void:
	var tool = _tool(Tool.Kind.POLYLINE)
	tool.click(Vector2(0, 0))
	tool.click(Vector2(1, 0))
	assert(tool.is_active())
	tool.cancel()
	assert(not tool.is_active())
	assert(tool.point_count() == 0)
	assert(tool.last_reason() == "")


func test_starting_a_tool_clears_the_previous_shape() -> void:
	var tool = _tool(Tool.Kind.POLYLINE)
	tool.click(Vector2(0, 0))
	tool.begin(Tool.Kind.LINE)
	assert(tool.point_count() == 0)
	assert(tool.kind == Tool.Kind.LINE)


func test_backspace_drops_the_last_point() -> void:
	var tool = _tool(Tool.Kind.POLYLINE)
	tool.click(Vector2(0, 0))
	tool.click(Vector2(4, 0))
	tool.click(Vector2(4, 3))
	assert(tool.undo_point())
	assert(tool.point_count() == 2)
	assert(tool.points()[1].is_equal_approx(Vector2(4, 0)))
	tool.undo_point()
	tool.undo_point()
	assert(not tool.undo_point())
	assert(tool.point_count() == 0)


func test_the_select_tool_takes_no_points() -> void:
	var tool = _tool(Tool.Kind.SELECT)
	var result: Dictionary = tool.click(Vector2(1, 1))
	assert(not result["committed"])
	assert(not tool.is_active())


# --- preview ------------------------------------------------------------------------


func test_a_line_previews_from_its_first_point() -> void:
	var tool = _tool(Tool.Kind.LINE)
	assert(tool.preview(Vector2(1, 1)) == null)
	tool.click(Vector2(0, 0))
	var ghost = tool.preview(Vector2(2, 0))
	assert(ghost != null)
	assert(ghost.kind == Entity.Kind.LINE)
	assert(ghost.point(1).is_equal_approx(Vector2(2, 0)))


func test_a_rectangle_previews_from_corner_to_cursor() -> void:
	var tool = _tool(Tool.Kind.RECTANGLE)
	tool.click(Vector2(1, 1))
	var ghost = tool.preview(Vector2(5, 3))
	assert(ghost != null)
	assert(ghost.point(0).is_equal_approx(Vector2(3, 2)))
	assert(is_equal_approx(ghost.params[2], 4.0))
	assert(is_equal_approx(ghost.params[3], 2.0))


func test_a_circle_previews_its_radius() -> void:
	var tool = _tool(Tool.Kind.CIRCLE)
	tool.click(Vector2(0, 0))
	var ghost = tool.preview(Vector2(0, 6))
	assert(ghost != null)
	assert(is_equal_approx(ghost.params[2], 6.0))


func test_an_arc_previews_a_circle_then_the_arc() -> void:
	var tool = _tool(Tool.Kind.ARC)
	tool.click(Vector2(0, 0))
	var radius_ghost = tool.preview(Vector2(4, 0))
	assert(radius_ghost != null)
	assert(radius_ghost.kind == Entity.Kind.CIRCLE)
	tool.click(Vector2(4, 0))
	var arc_ghost = tool.preview(Vector2(0, 4))
	assert(arc_ghost != null)
	assert(arc_ghost.kind == Entity.Kind.ARC)
	assert(is_equal_approx(arc_ghost.params[4], PI * 0.5))


func test_a_polyline_preview_follows_the_cursor() -> void:
	var tool = _tool(Tool.Kind.POLYLINE)
	tool.click(Vector2(0, 0))
	tool.click(Vector2(4, 0))
	var ghost = tool.preview(Vector2(4, 3))
	assert(ghost != null)
	assert(ghost.point_count() == 3)


## A preview that happens to be degenerate must show nothing rather than
## flickering a zero-size shape.
func test_a_degenerate_preview_shows_nothing() -> void:
	var tool = _tool(Tool.Kind.CIRCLE)
	tool.click(Vector2(2, 2))
	assert(tool.preview(Vector2(2, 2)) == null)
	var rect_tool = _tool(Tool.Kind.RECTANGLE)
	rect_tool.click(Vector2(2, 2))
	assert(rect_tool.preview(Vector2(5, 2)) == null)


# --- labels and status --------------------------------------------------------------


func test_status_guides_the_next_pick() -> void:
	var tool = _tool(Tool.Kind.LINE)
	assert(tool.status() == "Specify the first point")
	tool.click(Vector2(0, 0))
	assert(tool.status() == "Specify the second point")
	var arc_tool = _tool(Tool.Kind.ARC)
	assert(arc_tool.status() == "Specify the centre")
	arc_tool.click(Vector2(0, 0))
	assert(arc_tool.status() == "Specify the start point")
	arc_tool.click(Vector2(1, 0))
	assert(arc_tool.status() == "Specify the end point")
	assert(_tool(Tool.Kind.SELECT).status() != "")


func test_every_tool_has_a_label_and_a_point_count() -> void:
	var kinds: Array = [
		Tool.Kind.SELECT, Tool.Kind.LINE, Tool.Kind.POLYLINE,
		Tool.Kind.RECTANGLE, Tool.Kind.CIRCLE, Tool.Kind.ARC, Tool.Kind.MEASURE,
	]
	for kind: Tool.Kind in kinds:
		assert(Tool.label_for(kind) != "?")
		var tool = _tool(kind)
		assert(tool.needed_points() >= 0)