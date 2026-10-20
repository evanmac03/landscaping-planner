extends Node
## Tests for the spatial index and the snap engine: candidate priority, pixel
## aperture, snap hysteresis, intersection pruning and the tracking constraints.

const Grid := preload("res://scripts/draft/spatial_grid.gd")
const Snap := preload("res://scripts/draft/snap_engine.gd")
const Entity := preload("res://scripts/draft/draft_entity.gd")


func _line(id: int, a: Vector2, b: Vector2):
	var entity = Entity.make_line(a, b)
	entity.id = id
	return entity


func _circle(id: int, centre: Vector2, radius: float):
	var entity = Entity.make_circle(centre, radius)
	entity.id = id
	return entity


func _arc(id: int, centre: Vector2, radius: float, start: float, sweep: float):
	var entity = Entity.make_arc(centre, radius, start, sweep)
	entity.id = id
	return entity


func _engine(entities: Array):
	var engine = Snap.new()
	engine.bind(entities)
	return engine


# --- spatial grid -------------------------------------------------------------------


func test_grid_queries_only_overlapping_boxes() -> void:
	var grid = Grid.new()
	grid.insert(1, Rect2(0, 0, 1, 1))
	grid.insert(2, Rect2(10, 10, 1, 1))
	grid.insert(3, Rect2(50, 50, 1, 1))
	var found := grid.query(Rect2(-1, -1, 3, 3))
	assert(found.size() == 1)
	assert(found[0] == 1)
	assert(grid.count() == 3)


func test_grid_removal_and_rebuild() -> void:
	var grid = Grid.new()
	grid.insert(1, Rect2(0, 0, 1, 1))
	grid.insert(2, Rect2(0, 0, 1, 1))
	grid.remove(1)
	var found := grid.query(Rect2(-1, -1, 3, 3))
	assert(found.size() == 1)
	assert(found[0] == 2)
	# Removing something already gone must not corrupt the buckets.
	grid.remove(1)
	assert(grid.count() == 1)
	grid.rebuild([_line(7, Vector2(2, 2), Vector2(3, 2))])
	assert(grid.count() == 1)
	assert(grid.query(Rect2(1.5, 1.5, 2, 2))[0] == 7)


## A site-sized box must not be smeared across tens of thousands of buckets.
func test_grid_puts_huge_boxes_on_the_overflow_list() -> void:
	var grid = Grid.new()
	grid.insert(1, Rect2(-300, -300, 600, 600))
	assert(grid.overflow_count() == 1)
	assert(grid.bucket_count() == 0)
	# Still found, anywhere.
	var far := grid.query(Rect2(290, 290, 1, 1))
	assert(far.size() == 1)
	assert(far[0] == 1)
	grid.remove(1)
	assert(grid.query(Rect2(290, 290, 1, 1)).is_empty())
	assert(grid.query(Rect2(0, 0, 1, 1)).is_empty())


func test_grid_cell_maths() -> void:
	assert(Grid.cell_of(Vector2(0.0, 0.0), 4.0) == Vector2i(0, 0))
	assert(Grid.cell_of(Vector2(3.99, 0.0), 4.0) == Vector2i(0, 0))
	assert(Grid.cell_of(Vector2(4.0, 0.0), 4.0) == Vector2i(1, 0))
	# Negative coordinates must floor, not truncate toward zero.
	assert(Grid.cell_of(Vector2(-0.01, -4.5), 4.0) == Vector2i(-1, -2))
	assert(Grid.cell_span_for(Rect2(0, 0, 4, 4), 4.0) == 4)
	assert(Grid.cell_span_for(Rect2(0, 0, 600, 600), 4.0) == 22801)


# --- snap priority ------------------------------------------------------------------


## The load-bearing rule of the whole engine: priority outranks distance. The
## cursor here sits right on the midpoint, but an endpoint still wins.
func test_an_endpoint_outranks_a_closer_midpoint() -> void:
	var engine = _engine([_line(1, Vector2(0, 0), Vector2(0.6, 0))])
	var result: Dictionary = engine.resolve(Vector2(0.3, 0.01), 10.0)
	assert(result["snapped"])
	assert(result["mode"] == Snap.Mode.ENDPOINT)
	assert(result["point"].is_equal_approx(Vector2(0, 0)))
	assert(result["label"] == "endpoint")


func test_the_aperture_rejects_distant_candidates() -> void:
	var engine = _engine([_line(1, Vector2(0, 0), Vector2(4, 0))])
	# 12 px aperture at 100 px/m is 0.12 m; the cursor is 5 m away.
	var result: Dictionary = engine.resolve(Vector2(5.0, 0.0), 100.0)
	assert(not result["snapped"])
	assert(result["mode"] == Snap.Mode.NONE)


func test_the_aperture_is_measured_in_pixels_not_metres() -> void:
	var engine = _engine([_line(1, Vector2(0, 0), Vector2(4, 0))])
	# Same world cursor, coarser zoom: 0.12 m tolerance becomes 1.2 m.
	assert(not engine.resolve(Vector2(0.3, 0.0), 100.0)["mode"] == Snap.Mode.ENDPOINT)
	engine.clear_lock()
	var result: Dictionary = engine.resolve(Vector2(0.1, 0.0), 10.0)
	assert(result["mode"] == Snap.Mode.ENDPOINT)


## Hysteresis, which is what makes a snap feel stable instead of flickering
## between targets as the mouse moves.
func test_a_lock_holds_through_the_exit_aperture_then_releases() -> void:
	var engine = _engine([_line(1, Vector2(0, 0), Vector2(4, 0))])
	var first: Dictionary = engine.resolve(Vector2(0.05, 0.05), 100.0)
	assert(first["mode"] == Snap.Mode.ENDPOINT)

	# 0.15 m is past the 0.12 m aperture but inside the 0.192 m exit aperture.
	var held: Dictionary = engine.resolve(Vector2(0.15, 0.0), 100.0)
	assert(held["mode"] == Snap.Mode.ENDPOINT)
	assert(held["point"].is_equal_approx(Vector2(0, 0)))

	# 0.30 m is past the exit aperture, so the lock lets go and the nearest
	# point on the line takes over.
	var released: Dictionary = engine.resolve(Vector2(0.30, 0.0), 100.0)
	assert(released["mode"] == Snap.Mode.NEAREST)
	assert(released["point"].is_equal_approx(Vector2(0.3, 0)))
	assert(engine.locked_point().is_equal_approx(Vector2(0.3, 0)))


func test_disabling_the_locked_mode_clears_the_lock() -> void:
	var engine = _engine([_line(1, Vector2(0, 0), Vector2(4, 0))])
	engine.resolve(Vector2(0.02, 0.0), 100.0)
	assert(engine.locked_point().is_equal_approx(Vector2(0, 0)))
	engine.set_enabled(Snap.Mode.ENDPOINT, false)
	assert(engine.locked_point().is_equal_approx(Vector2.ZERO))


func test_binding_clears_the_lock() -> void:
	var engine = _engine([_line(1, Vector2(0, 0), Vector2(4, 0))])
	engine.resolve(Vector2(0.02, 0.0), 100.0)
	engine.bind([_line(2, Vector2(1, 1), Vector2(5, 1))])
	assert(engine.locked_point().is_equal_approx(Vector2.ZERO))


# --- candidate kinds ----------------------------------------------------------------


func test_intersections_are_found_where_two_entities_cross() -> void:
	var engine = _engine([
		_line(1, Vector2(0, 0), Vector2(4, 0)),
		_line(2, Vector2(2, -2), Vector2(2, 2)),
	])
	var result: Dictionary = engine.resolve(Vector2(2.0, 0.0), 100.0)
	assert(result["mode"] == Snap.Mode.INTERSECTION)
	assert(result["point"].is_equal_approx(Vector2(2, 0)))


## Intersection generation is O(n^2) across the whole drawing if it is not
## restricted to what the aperture already selected, so this pins the
## restriction: a crossing elsewhere on the plan must not contribute here.
func test_intersections_come_only_from_nearby_entities() -> void:
	var near := [
		_line(1, Vector2(0, 0), Vector2(4, 0)),
		_line(2, Vector2(2, -2), Vector2(2, 2)),
	]
	var far := [
		_line(3, Vector2(0, 50), Vector2(4, 50)),
		_line(4, Vector2(2, 48), Vector2(2, 52)),
	]
	var engine = _engine(near + far)
	var here: Dictionary = engine.resolve(Vector2(2.0, 0.0), 100.0)
	assert(here["mode"] == Snap.Mode.INTERSECTION)
	var count_here: int = here["candidates"]

	# The far crossing resolves on its own terms, and contributes no candidates
	# to the near query.
	engine.clear_lock()
	var there: Dictionary = engine.resolve(Vector2(2.0, 50.0), 100.0)
	assert(there["mode"] == Snap.Mode.INTERSECTION)
	assert(there["candidates"] == count_here)

	# An engine with only the far pair has nothing within the aperture here.
	var distant = _engine(far)
	var nothing: Dictionary = distant.resolve(Vector2(2.0, 0.0), 100.0)
	assert(not nothing["snapped"])
	assert(nothing["candidates"] == 0)


func test_circle_gives_its_centre_and_quadrants() -> void:
	var engine = _engine([_circle(1, Vector2(10, 10), 4.0)])
	var quadrant: Dictionary = engine.resolve(Vector2(14.0, 10.05), 100.0)
	assert(quadrant["mode"] == Snap.Mode.QUADRANT)
	assert(quadrant["point"].is_equal_approx(Vector2(14, 10)))

	engine.clear_lock()
	var centre: Dictionary = engine.resolve(Vector2(10.04, 10.0), 100.0)
	assert(centre["mode"] == Snap.Mode.CENTRE)
	assert(centre["point"].is_equal_approx(Vector2(10, 10)))


func test_an_arc_gives_its_ends_and_its_midpoint() -> void:
	var engine = _engine([_arc(1, Vector2.ZERO, 5.0, 0.0, PI * 0.5)])
	var end: Dictionary = engine.resolve(Vector2(0.05, 5.0), 100.0)
	assert(end["mode"] == Snap.Mode.ENDPOINT)
	assert(end["point"].is_equal_approx(Vector2(0, 5)))

	engine.clear_lock()
	var mid_arc := Vector2(cos(PI * 0.25), sin(PI * 0.25)) * 5.0
	var middle: Dictionary = engine.resolve(mid_arc, 100.0)
	assert(middle["mode"] == Snap.Mode.MIDPOINT)
	assert(middle["point"].is_equal_approx(mid_arc))


func test_polyline_vertices_and_segment_midpoints() -> void:
	var entity = Entity.make_polyline(PackedVector2Array([
		Vector2(0, 0), Vector2(4, 0), Vector2(4, 6),
	]))
	entity.id = 1
	var engine = _engine([entity])
	var vertex: Dictionary = engine.resolve(Vector2(4.0, 0.03), 100.0)
	assert(vertex["mode"] == Snap.Mode.ENDPOINT)
	var middle: Dictionary = engine.resolve(Vector2(4.0, 3.0), 100.0)
	assert(middle["mode"] == Snap.Mode.MIDPOINT)
	assert(middle["point"].is_equal_approx(Vector2(4, 3)))


func test_rectangle_gives_corners_and_centre() -> void:
	var entity = Entity.make_rectangle(Vector2(0, 0), Vector2(4, 2))
	entity.id = 1
	var engine = _engine([entity])
	var corner: Dictionary = engine.resolve(Vector2(2.0, 1.02), 100.0)
	assert(corner["mode"] == Snap.Mode.ENDPOINT)
	var centre: Dictionary = engine.resolve(Vector2(0.02, 0.0), 100.0)
	assert(centre["mode"] == Snap.Mode.CENTRE)


func test_perpendicular_uses_the_previous_point() -> void:
	var engine = _engine([_line(1, Vector2(0, 0), Vector2(10, 0))])
	var result: Dictionary = engine.resolve(Vector2(4.0, 0.03), 100.0, Vector2(4, 5), true)
	assert(result["mode"] == Snap.Mode.PERPENDICULAR)
	assert(result["point"].is_equal_approx(Vector2(4, 0)))

	# Without a previous point the snap cannot exist at all.
	engine.clear_lock()
	var alone: Dictionary = engine.resolve(Vector2(4.0, 0.03), 100.0)
	assert(alone["mode"] != Snap.Mode.PERPENDICULAR)


func test_tangent_from_an_outside_point() -> void:
	var engine = _engine([_circle(1, Vector2.ZERO, 5.0)])
	var previous := Vector2(20, 0)
	var spread := acos(5.0 / 20.0)
	var tangent := Vector2(cos(spread), sin(spread)) * 5.0
	var result: Dictionary = engine.resolve(tangent, 100.0, previous, true)
	assert(result["mode"] == Snap.Mode.TANGENT)
	assert(result["point"].distance_to(tangent) < 0.001)


func test_nearest_is_the_fallback_on_an_outline() -> void:
	var engine = _engine([_line(1, Vector2(0, 0), Vector2(10, 0))])
	var result: Dictionary = engine.resolve(Vector2(5.3, 0.05), 100.0)
	assert(result["mode"] == Snap.Mode.NEAREST)
	assert(result["point"].is_equal_approx(Vector2(5.3, 0)))


func test_disabling_a_mode_drops_its_candidates() -> void:
	var engine = _engine([_line(1, Vector2(0, 0), Vector2(0.6, 0))])
	engine.set_enabled(Snap.Mode.ENDPOINT, false)
	var result: Dictionary = engine.resolve(Vector2(0.3, 0.01), 10.0)
	assert(result["mode"] != Snap.Mode.ENDPOINT)


# --- constraints --------------------------------------------------------------------


## Grid is a constraint, not a target: an exact snap always outranks it.
func test_grid_snapping_only_applies_when_nothing_exact_is_near() -> void:
	var empty_engine = Snap.new()
	empty_engine.grid_snap = true
	empty_engine.grid_step = 0.5
	var on_grid: Dictionary = empty_engine.resolve(Vector2(1.23, 4.87), 100.0)
	assert(on_grid["mode"] == Snap.Mode.GRID)
	assert(on_grid["point"].is_equal_approx(Vector2(1.0, 5.0)))

	var engine = _engine([_line(1, Vector2(3, 3), Vector2(3.02, 3))])
	engine.grid_snap = true
	engine.grid_step = 0.5
	var exact: Dictionary = engine.resolve(Vector2(3.01, 3.0), 100.0)
	assert(exact["mode"] == Snap.Mode.ENDPOINT)


func test_ortho_locks_to_an_axis_through_the_previous_point() -> void:
	var engine = _engine([])
	engine.ortho = true
	var horizontal: Dictionary = engine.resolve(Vector2(3.0, 0.4), 100.0, Vector2(0, 0), true)
	assert(horizontal["point"].is_equal_approx(Vector2(3, 0)))
	engine.clear_lock()
	var vertical: Dictionary = engine.resolve(Vector2(0.4, 3.0), 100.0, Vector2(0, 0), true)
	assert(vertical["point"].is_equal_approx(Vector2(0, 3)))


func test_polar_snaps_the_direction_and_keeps_the_distance() -> void:
	var engine = _engine([])
	engine.polar = true
	engine.polar_step_degrees = 45.0
	var cursor := Vector2(3.0, 2.9)
	var result: Dictionary = engine.resolve(cursor, 100.0, Vector2.ZERO, true)
	assert(result["mode"] == Snap.Mode.POLAR)
	var offset: Vector2 = result["point"]
	assert(is_equal_approx(offset.length(), cursor.length()))
	assert(absf(offset.angle() - PI * 0.25) < 0.0001)


func test_constraints_do_nothing_without_a_previous_point() -> void:
	var engine = _engine([])
	engine.ortho = true
	engine.grid_snap = true
	engine.grid_step = 0.5
	var result: Dictionary = engine.resolve(Vector2(1.23, 4.87), 100.0)
	# Grid still applies; ortho needs something to be orthogonal to.
	assert(result["mode"] == Snap.Mode.GRID)
	assert(result["point"].is_equal_approx(Vector2(1.0, 5.0)))