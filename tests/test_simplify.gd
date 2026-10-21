extends Node
## Tests for auto-simplify: the Douglas-Peucker pass, the promise it keeps about how far a
## dropped vertex may have moved, and the refusal that stops it detaching one shape from
## another.

const Geom := preload("res://scripts/draft/geom2d.gd")
const Entity := preload("res://scripts/draft/draft_entity.gd")
const Simplify := preload("res://scripts/draft/draft_simplify.gd")
const Document := preload("res://scripts/draft/draft_document.gd")

## A default tolerance in model metres at 1:100, used across the pass tests.
const TOL := 0.04


func _poly(xys: Array) -> PackedVector2Array:
	var points := PackedVector2Array()
	for pair: Array in xys:
		points.append(Vector2(pair[0], pair[1]))
	return points


## The shortest distance from a point to an open polyline, in model metres.
func _deviation(point: Vector2, polyline: PackedVector2Array) -> float:
	if polyline.size() == 1:
		return point.distance_to(polyline[0])
	var best := INF
	for index in polyline.size() - 1:
		best = minf(best, Geom.distance_to_segment(point, polyline[index], polyline[index + 1]))
	return best


# --- the pass itself -----------------------------------------------------------------


func test_collinear_points_all_come_out() -> void:
	var line := _poly([[0.0, 0.0], [1.0, 0.0], [2.0, 0.0], [3.0, 0.0], [4.0, 0.0]])
	assert(Geom.simplify(line, TOL).size() == 2, "a straight run is two points")


func test_the_two_ends_are_always_kept() -> void:
	var line := _poly([[0.0, 0.0], [1.0, 0.0], [2.0, 0.0], [3.0, 0.0]])
	var out := Geom.simplify(line, TOL)
	assert(out.size() == 2)
	assert(out[0] == line[0], "the first point is pinned")
	assert(out[out.size() - 1] == line[line.size() - 1], "the last point is pinned")


func test_a_zero_tolerance_changes_nothing() -> void:
	var line := _poly([[0.0, 0.0], [1.0, 0.2], [2.0, 0.0]])
	assert(Geom.simplify(line, 0.0).size() == 3, "a tolerance of zero drops nothing")


func test_a_point_further_off_than_the_tolerance_is_kept() -> void:
	var line := _poly([[0.0, 0.0], [1.0, 0.5], [2.0, 0.0]])
	var out := Geom.simplify(line, TOL)
	assert(out.size() == 3, "the spike is a corner, not noise")


func test_a_point_inside_the_tolerance_is_dropped() -> void:
	var line := _poly([[0.0, 0.0], [1.0, 0.01], [2.0, 0.0]])
	var out := Geom.simplify(line, TOL)
	assert(out.size() == 2, "a tenth of a millimetre off a straight run is noise")


## The promise the whole pass is built on: no dropped vertex's true position lies further
## from the simplified line than the tolerance.
func test_every_original_point_stays_within_the_tolerance() -> void:
	var line := _poly([
		[0.0, 0.0], [1.0, 0.02], [2.0, -0.03], [3.0, 0.0], [4.0, 1.0],
		[5.0, 1.01], [6.0, 1.0], [7.0, 0.0],
	])
	var out := Geom.simplify(line, TOL)
	for point: Vector2 in line:
		assert(_deviation(point, out) <= TOL + 1.0e-6,
			"a dropped point %s moved further than the tolerance" % point)


func test_the_same_input_simplifies_the_same_way_twice() -> void:
	var line := _poly([[0.0, 0.0], [1.0, 0.03], [2.0, 0.0], [3.0, 0.02], [4.0, 0.0]])
	assert(Geom.simplify(line, TOL) == Geom.simplify(line, TOL), "the pass is deterministic")


func test_the_pass_never_adds_a_point() -> void:
	var line := _poly([[0.0, 0.0], [1.0, 0.5], [2.0, 0.0]])
	assert(Geom.simplify(line, TOL).size() <= line.size())


func test_fewer_than_three_points_is_returned_unchanged() -> void:
	var pair := _poly([[0.0, 0.0], [1.0, 1.0]])
	assert(Geom.simplify(pair, TOL).size() == 2)


## A ring must not collapse to a point just because every vertex is within the tolerance
## of the ring's start - for a small bed that would be the bed disappearing.
func test_a_closed_ring_keeps_its_shape() -> void:
	var ring := PackedVector2Array()
	for index in 16:
		var angle := TAU * float(index) / 16.0
		ring.append(Vector2(cos(angle), sin(angle)) * 3.0)
	var out := Geom.simplify(ring, TOL, true)
	assert(out.size() >= 3, "a ring keeps at least a triangle")
	assert(Geom.polygon_area(out) > Geom.polygon_area(ring) * 0.9,
		"the ring's shape survives, not just its vertex count")


func test_a_closed_ring_passes_through_its_original_vertices() -> void:
	var ring := _poly([
		[0.0, 0.0], [2.0, 0.01], [4.0, 0.0], [4.0, 4.0], [0.0, 4.0],
	])
	var out := Geom.simplify(ring, TOL, true)
	for point: Vector2 in ring:
		var best := INF
		for index in out.size():
			var a: Vector2 = out[index]
			var b: Vector2 = out[(index + 1) % out.size()]
			best = minf(best, Geom.distance_to_segment(point, a, b))
		assert(best <= TOL + 1.0e-6, "a ring vertex %s strayed further than the tolerance" % point)


# --- what the pass is run at ---------------------------------------------------------


func test_the_default_tolerance_is_a_paper_length() -> void:
	# 0.4 paper mm at 1:100 is 40 model mm.
	assert(is_equal_approx(Simplify.default_tolerance(100.0), 0.04))
	assert(is_equal_approx(Simplify.default_tolerance(50.0), 0.02),
		"half the scale is half the model tolerance")


func test_a_zero_scale_still_gives_a_tolerance() -> void:
	assert(Simplify.default_tolerance(0.0) > 0.0, "a scale of nothing is not a tolerance of nothing")


# --- what the pass refuses -----------------------------------------------------------


func test_a_line_is_not_simplifiable() -> void:
	var reason := Simplify.refusal_for(Entity.make_line(Vector2.ZERO, Vector2(1.0, 0.0)))
	assert(reason != "", "two points have nothing to take out")


func test_a_circle_is_not_simplifiable() -> void:
	var reason := Simplify.refusal_for(Entity.make_circle(Vector2.ZERO, 2.0))
	assert(reason.contains("polyline"), "a circle is named as having no vertices to take out")


func test_a_curved_polyline_is_refused_naming_the_arcs() -> void:
	var curved := Entity.make_polyline(_poly([[0.0, 0.0], [1.0, 0.0], [1.0, 1.0], [0.0, 1.0]]), true)
	curved.bulges = PackedFloat64Array([0.4, 0.0, 0.0, 0.0])
	assert(not Simplify.is_simplifiable(curved))
	assert(Simplify.refusal_for(curved).contains("arcs"),
		"the reason says the corners are arcs, not that the shape is arbitrary")


func test_a_plain_polygon_is_simplifiable() -> void:
	var square := Entity.make_polyline(_poly([[0.0, 0.0], [4.0, 0.0], [4.0, 4.0], [0.0, 4.0]]), true)
	assert(Simplify.is_simplifiable(square))
	assert(Simplify.refusal_for(square) == "")


# --- the shared corner rule ----------------------------------------------------------


## The rule the whole feature exists for: a corner two shapes meet at may not be pulled
## off the drawing, so the shape that would have to move is refused by name.
func test_a_shared_corner_that_would_move_refuses_the_shape() -> void:
	var bed := Entity.make_polyline(_poly([[0.0, 0.0], [5.0, 0.01], [10.0, 0.0]]))
	var wall := Entity.make_line(Vector2(5.0, 0.01), Vector2(5.0, 5.0))
	var report := Simplify.plan([bed, wall], TOL)
	assert(report.refusals.size() == 1, "the bed is refused")
	assert(report.entries.is_empty(), "and its simplification is not offered")
	assert(String(report.refusals[0]["reason"]).contains("shares"),
		"the reason names the shared corner, not a generic failure")


## A shared corner that survives the pass is no problem, even though other points go.
func test_a_shared_corner_that_survives_does_not_refuse() -> void:
	var bed := Entity.make_polyline(_poly([[0.0, 0.0], [5.0, 0.0], [10.0, 0.0]]))
	var wall := Entity.make_line(Vector2(5.0, 0.0), Vector2(5.0, 5.0))
	var report := Simplify.plan([bed, wall], TOL)
	assert(report.refusals.is_empty(), "a shared corner still on the line is not a detachment")
	assert(report.changed_count() == 1, "and the bed is still simplified")
	assert(int(report.entries[0]["after"]) == 2)


# --- planning and applying -----------------------------------------------------------


func test_planning_changes_nothing() -> void:
	var document = Document.new()
	var bed := Entity.make_polyline(_poly([[0.0, 0.0], [2.5, 0.0], [5.0, 0.0]]))
	var id: int = document.add(bed)
	var before: int = document.get_entity(id).point_count()
	Simplify.plan(document.visible_entities(), TOL)
	assert(document.get_entity(id).point_count() == before, "a plan is read-only")


func test_apply_replaces_the_shape_and_keeps_its_layer_and_id() -> void:
	var document = Document.new()
	var bed := Entity.make_polyline(_poly([[0.0, 0.0], [2.5, 0.0], [5.0, 0.0]]))
	var id: int = document.add(bed)
	var report := Simplify.plan(document.visible_entities(), TOL)
	var written: int = Simplify.apply(document, report)
	assert(written == 1)
	var after: Entity = document.get_entity(id)
	assert(after != null, "the shape keeps its id")
	assert(after.point_count() == 2, "and lost its collinear vertex")
	assert(after.layer == bed.layer, "and keeps its layer")


func test_apply_is_one_undo_step() -> void:
	var document = Document.new()
	var bed := Entity.make_polyline(_poly([[0.0, 0.0], [2.5, 0.0], [5.0, 0.0]]))
	var id: int = document.add(bed)
	var before: int = document.get_entity(id).point_count()
	var report := Simplify.plan(document.visible_entities(), TOL)
	assert(Simplify.apply(document, report) == 1)
	assert(document.get_entity(id).point_count() == 2)
	assert(document.undo_last(), "the whole pass is one undo step")
	assert(document.get_entity(id).point_count() == before, "and the vertex comes back")


func test_an_empty_plan_leaves_the_drawing_and_the_undo_stack_alone() -> void:
	var document = Document.new()
	document.add(Entity.make_circle(Vector2.ZERO, 2.0))
	var report := Simplify.plan(document.visible_entities(), TOL)
	assert(report.is_noop(), "a circle is nothing to simplify")
	assert(Simplify.apply(document, report) == 0)
	assert(not document.undo_last(), "nothing happened, so there is nothing to undo")


# --- the report ----------------------------------------------------------------------


func test_the_report_describes_what_it_did() -> void:
	var bed := Entity.make_polyline(_poly([[0.0, 0.0], [2.5, 0.0], [5.0, 0.0]]))
	var report := Simplify.plan([bed], TOL)
	assert(report.describe() == "1 shape simplified, 1 point removed",
		"the report says what it did, in words")


func test_a_report_with_nothing_to_do_says_so() -> void:
	var report := Simplify.plan([], TOL)
	assert(report.is_noop())
	assert(report.describe() == "nothing to simplify")


func test_the_report_round_trips_to_data() -> void:
	var bed := Entity.make_polyline(_poly([[0.0, 0.0], [2.5, 0.0], [5.0, 0.0]]))
	var wall := Entity.make_line(Vector2(2.5, 0.01), Vector2(2.5, 5.0))
	var off := Entity.make_polyline(_poly([[0.0, 0.0], [5.0, 0.01], [10.0, 0.0]]))
	var report := Simplify.plan([bed, off, wall], TOL)
	var data := report.to_dict()
	assert(is_equal_approx(float(data["tolerance"]), TOL))
	assert(data["entries"].size() == report.changed_count())
	assert(data["refused"].size() == report.refused_count(), "refusals travel with the plan")