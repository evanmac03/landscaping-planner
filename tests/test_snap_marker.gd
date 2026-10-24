extends Node
## Tests for the snap marker: the shape drawn at the cursor for each kind of snap.
##
## The engine carries a table of *characters* for its modes, and the shipped font (Open Sans
## SemiBold) has none of them - `Font.has_char` is false for all nine - so a marker drawn from that
## table would be nine boxes of tofu. The marker is drawn as a shape per mode instead, which is what
## a drafting program does anyway, and this is what pins the vocabulary.

const Canvas := preload("res://scripts/plan_canvas.gd")
const Snap := preload("res://scripts/draft/snap_engine.gd")

## The marker's half-width, in whatever unit the caller works in - here, for the shapes' own sake.
const HALF := 6.0

## Every mode that can be snapped to, and none of them twice.
const MODES: Array = [
	Snap.Mode.ENDPOINT,
	Snap.Mode.INTERSECTION,
	Snap.Mode.MIDPOINT,
	Snap.Mode.CENTRE,
	Snap.Mode.QUADRANT,
	Snap.Mode.PERPENDICULAR,
	Snap.Mode.TANGENT,
	Snap.Mode.NEAREST,
	Snap.Mode.GRID,
	Snap.Mode.POLAR,
]


func test_every_snap_mode_draws_a_shape_and_no_snap_draws_nothing() -> void:
	for mode: int in MODES:
		var strokes: Array = Canvas.marker_strokes(mode, HALF)
		assert(not strokes.is_empty(), "mode %d has a marker" % mode)
		for stroke: PackedVector2Array in strokes:
			assert(stroke.size() >= 2, "every stroke has two points at least")
	assert(Canvas.marker_strokes(Snap.Mode.NONE, HALF).is_empty(), "and no snap draws nothing")


func test_the_marker_is_centred_on_the_point_and_no_bigger_than_asked() -> void:
	for mode: int in MODES:
		for stroke: PackedVector2Array in Canvas.marker_strokes(mode, HALF):
			for vertex: Vector2 in stroke:
				assert(absf(vertex.x) <= HALF + 0.0001, "x within the marker: %s" % vertex)
				assert(absf(vertex.y) <= HALF + 0.0001, "y within the marker: %s" % vertex)
	# A bigger marker is a bigger marker, so the size is the caller's and not baked in.
	var wide: Array = Canvas.marker_strokes(Snap.Mode.ENDPOINT, HALF * 2.0)
	assert(is_equal_approx(absf(wide[0][1].x), HALF * 2.0), "the size asked for is the size drawn")


func test_the_four_closed_shapes_a_person_reads_at_a_glance() -> void:
	var square: PackedVector2Array = Canvas.marker_strokes(Snap.Mode.ENDPOINT, HALF)[0]
	assert(square.size() == 5, "an endpoint is a closed square, got %d points" % square.size())
	assert(square[0].is_equal_approx(square[square.size() - 1]), "and it closes")
	var triangle: PackedVector2Array = Canvas.marker_strokes(Snap.Mode.MIDPOINT, HALF)[0]
	assert(triangle.size() == 4, "a midpoint is a closed triangle")
	assert(is_equal_approx(absf(triangle[1].x), HALF), "with its base as wide as the marker")
	var circle: PackedVector2Array = Canvas.marker_strokes(Snap.Mode.CENTRE, HALF)[0]
	assert(circle.size() > 8, "a centre is a ring of points, got %d" % circle.size())
	assert(circle[0].is_equal_approx(circle[circle.size() - 1]), "and the ring closes")
	var diamond: PackedVector2Array = Canvas.marker_strokes(Snap.Mode.QUADRANT, HALF)[0]
	assert(diamond.size() == 5, "a quadrant is a closed diamond")
	assert(is_equal_approx(diamond[1].y, 0.0), "with a point out to the side")


func test_the_modes_that_are_not_a_closed_shape_are_drawn_as_strokes() -> void:
	# A cross, a tee, an angle and a square with a cross in it are strokes rather than outlines.
	assert(Canvas.marker_strokes(Snap.Mode.INTERSECTION, HALF).size() == 2, "an intersection is a cross")
	assert(Canvas.marker_strokes(Snap.Mode.PERPENDICULAR, HALF).size() == 2, "a perpendicular is a tee")
	assert(Canvas.marker_strokes(Snap.Mode.POLAR, HALF).size() == 2, "polar is an angle")
	assert(Canvas.marker_strokes(Snap.Mode.GRID, HALF).size() == 3, "a grid is a square with a cross in it")
	assert(Canvas.marker_strokes(Snap.Mode.TANGENT, HALF).size() == 1, "a tangent is one arc")
	var arc: PackedVector2Array = Canvas.marker_strokes(Snap.Mode.TANGENT, HALF)[0]
	assert(arc.size() > 2, "and the arc is curved, got %d points" % arc.size())
	assert(not arc[0].is_equal_approx(arc[arc.size() - 1]), "an arc is open, unlike a ring")


func test_the_catch_all_wears_the_endpoint_s_marker() -> void:
	# The engine's own character table gives nearest the endpoint's character; the shapes agree.
	var endpoint: Array = Canvas.marker_strokes(Snap.Mode.ENDPOINT, HALF)
	var nearest: Array = Canvas.marker_strokes(Snap.Mode.NEAREST, HALF)
	assert(nearest.size() == endpoint.size())
	assert(nearest[0].size() == endpoint[0].size())