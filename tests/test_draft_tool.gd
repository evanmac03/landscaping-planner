extends Node
## Tests for the drawing tools: shape construction from picks, refusal of
## degenerate shapes, the rubber-band preview, and the open-ended tools.

const Tool := preload("res://scripts/draft/draft_tool.gd")
const Entity := preload("res://scripts/draft/draft_entity.gd")
const Dimension := preload("res://scripts/draft/dimension.gd")
const Ctrl := preload("res://scripts/draft/draft_controller.gd")
const LayerSet := preload("res://scripts/draft/layer_set.gd")


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
		Tool.Kind.DIMENSION, Tool.Kind.DIMENSION_LINEAR, Tool.Kind.DIMENSION_RADIUS,
	]
	for kind: Tool.Kind in kinds:
		assert(Tool.label_for(kind) != "?")
		var tool = _tool(kind)
		assert(tool.needed_points() >= 0)


# --- dimension ----------------------------------------------------------------------


## The dimension line is whichever stroke in a layout is longest. Extension lines
## are only a gap plus an overshoot long, so this cannot mistake one of those for
## the line that carries the measurement.
func _dimension_line(layout: Dictionary) -> PackedVector2Array:
	var longest := PackedVector2Array()
	for stroke: PackedVector2Array in layout["lines"]:
		if stroke.size() < 2:
			continue
		if longest.is_empty() \
				or stroke[0].distance_to(stroke[1]) > longest[0].distance_to(longest[1]):
			longest = stroke
	return longest


## What a dimension says, read through the shared layout at 1:100.
func _dimension_text(entity) -> String:
	return String(Dimension.layout(entity, 100.0)["labels"][0]["text"])


## A dimension is two points to measure and somewhere to put the line that
## measures them, so it takes three picks and commits on the third.
func test_a_dimension_is_measured_between_two_points_and_placed_by_a_third() -> void:
	var tool = _tool(Tool.Kind.DIMENSION, LayerSet.DIMENSION)
	assert(Tool.label_for(Tool.Kind.DIMENSION) == "Aligned dimension")
	assert(tool.needed_points() == 3)
	assert(not tool.is_measure())
	assert(not (tool.click(Vector2(0, 0))["committed"]))
	assert(not (tool.click(Vector2(6, 0))["committed"]))
	assert(tool.point_count() == 2)
	var third: Dictionary = tool.click(Vector2(3, 2))
	assert(third["committed"])
	var dimension = third["entity"]
	assert(dimension.kind == Entity.Kind.DIMENSION)
	assert(dimension.point(0).is_equal_approx(Vector2(0, 0)))
	assert(dimension.point(1).is_equal_approx(Vector2(6, 0)))
	assert(int(dimension.params[5]) == Entity.DimensionKind.ALIGNED)
	assert(not tool.is_active())


## The tool and the layout have to agree about which side of the measured points
## the offset puts the line, or the dimension jumps across the wall the moment the
## third pick is committed.
func test_the_dimension_line_lands_on_the_side_it_was_placed() -> void:
	for placed: Vector2 in [Vector2(3, 2), Vector2(3, -2), Vector2(-5, 1.5)]:
		var tool = _tool(Tool.Kind.DIMENSION)
		tool.click(Vector2(0, 0))
		tool.click(Vector2(6, 0))
		var dimension = tool.click(placed)["entity"]
		var line := _dimension_line(Dimension.layout(dimension, 100.0))
		assert(line.size() == 2)
		var middle := (line[0] + line[1]) * 0.5
		# As far out as the pick, measured perpendicular to what is being
		# dimensioned, and on the pick's own side of it.
		assert(is_equal_approx(middle.x, 3.0))
		assert(is_equal_approx(absf(middle.y), absf(placed.y)))
		assert(signf(middle.y) == signf(placed.y))


## Two identical picks measure nothing, so the dimension is refused and the bad
## pick handed back - the same contract every shape tool has.
func test_a_dimension_refuses_two_identical_points() -> void:
	var tool = _tool(Tool.Kind.DIMENSION)
	tool.click(Vector2(2, 2))
	var refused: Dictionary = tool.click(Vector2(2, 2))
	assert(not refused["committed"])
	assert(refused["rejected"])
	assert(tool.point_count() == 1)
	assert(tool.last_reason().contains("distinct"))
	# Still usable: name a real second point and a place for the line.
	assert(tool.click(Vector2(7, 2))["progress"] == 2)
	assert(tool.click(Vector2(4, 1))["committed"])


## Before the second pick there is nothing to measure, so the ghost is the plain
## rubber band; after it, the ghost is the dimension the cursor is placing.
func test_the_dimension_preview_follows_the_cursor_as_the_line_placement() -> void:
	var tool = _tool(Tool.Kind.DIMENSION)
	assert(tool.preview(Vector2(1, 1)) == null)
	tool.click(Vector2(0, 0))
	var rubber = tool.preview(Vector2(6, 0))
	assert(rubber.kind == Entity.Kind.LINE)
	tool.click(Vector2(6, 0))
	var ghost = tool.preview(Vector2(3, 2))
	assert(ghost.kind == Entity.Kind.DIMENSION)
	assert(is_equal_approx(float(ghost.params[4]), -2.0))
	# A preview is not a commit: the placement is still the user's to make.
	assert(tool.point_count() == 2)


func test_the_dimension_tool_guides_its_three_picks() -> void:
	var tool = _tool(Tool.Kind.DIMENSION)
	assert(tool.status().contains("measure from"))
	tool.click(Vector2(0, 0))
	assert(tool.status().contains("measure to"))
	tool.click(Vector2(4, 0))
	assert(tool.status().contains("dimension line"))


## An annotation is not a site feature, so the dimension tool draws on the
## dimension layer whatever is selected. Having made that choice it must not leave
## the next line stranded there either - which is why the selected layer is kept
## apart from the layer the active tool is drawing on.
func test_a_dimension_draws_on_the_dimension_layer_not_the_selected_one() -> void:
	var controller = Ctrl.new()
	assert(controller._layer_for(Tool.Kind.DIMENSION) == LayerSet.DIMENSION)
	assert(controller._layer_for(Tool.Kind.LINE) == LayerSet.NEW_HARDSCAPE)
	controller.drawing_layer = LayerSet.NEW_PLANTING
	assert(controller._layer_for(Tool.Kind.LINE) == LayerSet.NEW_PLANTING)
	assert(controller._layer_for(Tool.Kind.DIMENSION) == LayerSet.DIMENSION)
	controller.free()


# --- linear dimension ---------------------------------------------------------------


## A linear dimension measures the extent along whichever axis the picks lie
## mostly along, not the diagonal between them. That is the reading for an overall
## width, and it is a different number on purpose.
func test_a_linear_dimension_measures_the_extent_along_the_dominant_axis() -> void:
	var tool = _tool(Tool.Kind.DIMENSION_LINEAR, LayerSet.DIMENSION)
	assert(Tool.label_for(Tool.Kind.DIMENSION_LINEAR) == "Linear dimension")
	assert(tool.needed_points() == 3)
	tool.click(Vector2(0, 0))
	assert(tool.click(Vector2(10, 3))["progress"] == 2)
	var dimension = tool.click(Vector2(4, 5))["entity"]
	assert(int(dimension.params[5]) == Entity.DimensionKind.LINEAR)
	# Ten metres across, not the 10.44 m between the two picks.
	assert(_dimension_text(dimension) == "10.00 m")
	# And the line is set out on the perpendicular axis, where it was placed.
	var line := _dimension_line(Dimension.layout(dimension, 100.0))
	assert(is_equal_approx(line[0].x, 0.0))
	assert(is_equal_approx(line[1].x, 10.0))
	assert(is_equal_approx(line[0].y, 5.0))
	assert(is_equal_approx(line[1].y, 5.0))


## Which axis it measures follows from the picks, so a mostly-vertical pair is
## measured up the page and its line is set out to the side.
func test_a_linear_dimension_follows_the_axis_the_picks_lie_along() -> void:
	var tool = _tool(Tool.Kind.DIMENSION_LINEAR)
	tool.click(Vector2(0, 0))
	tool.click(Vector2(2, 6))
	var dimension = tool.click(Vector2(-3, 1))["entity"]
	assert(_dimension_text(dimension) == "6.00 m")
	var line := _dimension_line(Dimension.layout(dimension, 100.0))
	assert(is_equal_approx(line[0].x, -3.0))
	assert(is_equal_approx(line[1].x, -3.0))
	assert(is_equal_approx(line[0].y, 0.0))
	assert(is_equal_approx(line[1].y, 6.0))


func test_the_linear_dimension_guides_its_three_picks() -> void:
	var tool = _tool(Tool.Kind.DIMENSION_LINEAR)
	assert(tool.status().contains("measure from"))
	tool.click(Vector2(0, 0))
	assert(tool.status().contains("measure to"))
	tool.click(Vector2(4, 0))
	assert(tool.status().contains("dimension line"))


func test_the_linear_ghost_follows_the_cursor_as_the_line_placement() -> void:
	var tool = _tool(Tool.Kind.DIMENSION_LINEAR)
	tool.click(Vector2(0, 0))
	assert(tool.preview(Vector2(8, 0)).kind == Entity.Kind.LINE)
	tool.click(Vector2(8, 0))
	var ghost = tool.preview(Vector2(4, 2))
	assert(int(ghost.params[5]) == Entity.DimensionKind.LINEAR)
	assert(is_equal_approx(float(ghost.params[4]), 2.0))
	assert(tool.point_count() == 2)


# --- radial dimension ---------------------------------------------------------------


## A radius is a centre and a point on the circle, so it takes two picks and no
## placement: which way the leader runs is the same act as naming the radius.
func test_a_radial_dimension_takes_a_centre_and_a_point_on_the_circle() -> void:
	var tool = _tool(Tool.Kind.DIMENSION_RADIUS, LayerSet.DIMENSION)
	assert(Tool.label_for(Tool.Kind.DIMENSION_RADIUS) == "Radial dimension")
	assert(tool.needed_points() == 2)
	assert(tool.status().contains("centre"))
	assert(not tool.click(Vector2(4, 4))["committed"])
	assert(tool.status().contains("circle"))
	var second: Dictionary = tool.click(Vector2(4, 6.5))
	assert(second["committed"])
	var dimension = second["entity"]
	assert(int(dimension.params[5]) == Entity.DimensionKind.RADIUS)
	assert(_dimension_text(dimension) == "R2.50 m")
	# The leader runs from the centre out to the edge it was picked on.
	var layout: Dictionary = Dimension.layout(dimension, 100.0)
	assert(layout["lines"].size() == 1)
	var leader: PackedVector2Array = layout["lines"][0]
	assert(leader[0].is_equal_approx(Vector2(4, 4)))
	assert(leader[1].is_equal_approx(Vector2(4, 6.5)))


## A centre with the edge picked on top of it is a circle of no size, so the pick
## is refused and handed back like any other degenerate shape.
func test_a_radial_dimension_refuses_a_circle_of_no_size() -> void:
	var tool = _tool(Tool.Kind.DIMENSION_RADIUS)
	tool.click(Vector2(1, 1))
	var refused: Dictionary = tool.click(Vector2(1, 1))
	assert(not refused["committed"])
	assert(refused["rejected"])
	assert(tool.point_count() == 1)
	assert(tool.click(Vector2(1, 3))["committed"])


## A radius takes no placement, so its ghost can show the measurement itself from
## the first pick onwards rather than a bare rubber band.
func test_the_radial_ghost_shows_the_radius_before_it_is_committed() -> void:
	var tool = _tool(Tool.Kind.DIMENSION_RADIUS)
	assert(tool.preview(Vector2(1, 1)) == null)
	tool.click(Vector2(0, 0))
	var ghost = tool.preview(Vector2(3, 4))
	assert(ghost.kind == Entity.Kind.DIMENSION)
	assert(int(ghost.params[5]) == Entity.DimensionKind.RADIUS)
	assert(_dimension_text(ghost) == "R5.00 m")
	# Shown, not committed.
	assert(tool.point_count() == 1)


## All four dimension commands are annotations rather than site features, so all
## four draw on the dimension layer whatever was selected.
func test_every_dimension_command_is_an_annotation() -> void:
	var dimensions: Array = [
		Tool.Kind.DIMENSION, Tool.Kind.DIMENSION_LINEAR, Tool.Kind.DIMENSION_RADIUS,
		Tool.Kind.DIMENSION_ANGULAR,
	]
	for kind: Tool.Kind in dimensions:
		assert(Tool.is_dimension(kind))
		assert(not _tool(kind).is_measure())
	assert(not Tool.is_dimension(Tool.Kind.LINE))
	assert(not Tool.is_dimension(Tool.Kind.MEASURE))
	var controller = Ctrl.new()
	controller.drawing_layer = LayerSet.NEW_PLANTING
	for kind: Tool.Kind in dimensions:
		assert(controller._layer_for(kind) == LayerSet.DIMENSION)
	assert(controller._layer_for(Tool.Kind.ARC) == LayerSet.NEW_PLANTING)
	controller.free()


## An angular dimension is a corner, a point along each of its two sides, and then somewhere for the arc
## to stand. Four picks - one more than any other command - and the fourth decides only the radius.
func test_an_angular_dimension_is_a_corner_and_two_sides_and_an_arc() -> void:
	var tool = _tool(Tool.Kind.DIMENSION_ANGULAR, LayerSet.DIMENSION)
	assert(Tool.label_for(Tool.Kind.DIMENSION_ANGULAR) == "Angular dimension")
	assert(tool.needed_points() == 4)
	# One pick at a time, and nothing commits until the fourth.
	assert(not (tool.click(Vector2(0, 0))["committed"]))
	assert(not (tool.click(Vector2(4, 0))["committed"]))
	assert(not (tool.click(Vector2(0, 4))["committed"]))
	var fourth: Dictionary = tool.click(Vector2(2, 0))
	assert(fourth["committed"], "it completes on the pick that puts the arc somewhere")
	var angle = fourth["entity"]
	assert(angle.kind == Entity.Kind.DIMENSION)
	assert(int(angle.params[5]) == Entity.DimensionKind.ANGULAR)
	assert(angle.point(0).is_equal_approx(Vector2(0, 0)), "the corner")
	assert(angle.point(1).is_equal_approx(Vector2(4, 0)), "a point along the first side")
	assert(is_equal_approx(angle.params[4], 2.0), "and the radius is how far the arc was put out")
	# Read back through the shared layout, so the tool and the drawing agree about the number.
	assert(_dimension_text(angle) == "90.00°", _dimension_text(angle))
	assert(not tool.is_active())


## What is not an angle is refused on the pick that made it, and the pick is handed back so the tool
## stays where the drawer thinks it is.
func test_an_angular_dimension_refuses_what_is_not_an_angle() -> void:
	# Two sides in one direction enclose nothing. The refusal comes when the shape is finished, which for
	# this command is the fourth pick - the shared machine builds at `needed_points`, and only the pair
	# of points is checked as it is completed.
	var same_way = _tool(Tool.Kind.DIMENSION_ANGULAR)
	same_way.click(Vector2(0, 0))
	same_way.click(Vector2(4, 0))
	same_way.click(Vector2(9, 0))
	var collinear: Dictionary = same_way.click(Vector2(3, 0))
	assert(not collinear["committed"], "a straight line is not an angle")
	assert(same_way.last_reason().contains("same direction"), same_way.last_reason())
	assert(same_way.point_count() == 3, "and the pick that failed was given back")

	# A second pick on the corner itself is a side of no length, refused as the pair it completes.
	var flat = _tool(Tool.Kind.DIMENSION_ANGULAR)
	flat.click(Vector2(0, 0))
	var on_the_corner: Dictionary = flat.click(Vector2(0, 0))
	assert(not on_the_corner["committed"])
	assert(flat.last_reason().contains("distinct"), flat.last_reason())
	assert(flat.point_count() == 1)

	# And an arc put out on the corner itself has no radius.
	var no_radius = _tool(Tool.Kind.DIMENSION_ANGULAR)
	no_radius.click(Vector2(0, 0))
	no_radius.click(Vector2(4, 0))
	no_radius.click(Vector2(0, 4))
	var at_the_corner: Dictionary = no_radius.click(Vector2(0, 0))
	assert(not at_the_corner["committed"], "an arc with no radius is not an arc")
	assert(no_radius.last_reason().contains("stand off"), no_radius.last_reason())