extends Node
## Tests for the walk-through: the route as a clock, and the one transform a director puts
## on a camera.
##
## The arithmetic is the part worth pinning. A walk-through nobody can describe is a
## screensaver (REQ-V9.3), and what makes it describable is that it is stops and dwells
## rather than a path: so the tests here are about *when* the camera is where - at the
## first stop at nought seconds, half way along the first leg half a leg later, standing
## at the last stop at the end - and about a route of one stop being refused rather than
## followed silently (REQ-V9.5).

const Route := preload("res://scripts/vis/walk_route.gd")
const Director := preload("res://scripts/vis/walk_director.gd")


## A route of two stops three metres apart, dwelling two seconds each.
func _straight_route() -> WalkRoute:
	var route := Route.new()
	route.add_stop("door", Vector3(0, 1.6, 0), Vector3(0, 1.6, 3), 2.0)
	route.add_stop("path end", Vector3(0, 1.6, 3), Vector3(0, 1.6, 0), 2.0)
	return route


# --- the route -----------------------------------------------------------------------


func test_a_new_route_has_nothing_in_it_and_says_so() -> void:
	var route := Route.new()
	assert(route.is_empty())
	assert(route.count() == 0)
	assert(route.stops().is_empty())
	assert(route.refusal() != "", "an empty route says why it cannot be walked")
	assert(route.refusal().contains("no stops"), "the reason names the missing stops: %s" % route.refusal())
	assert(route.describe() == "an empty walk-through")


func test_a_route_of_one_stop_is_refused_rather_than_followed() -> void:
	var route := Route.new()
	route.add_stop("somewhere", Vector3.ZERO, Vector3.FORWARD)
	assert(route.count() == 1)
	# REQ-V9.5: one stop is a picture, not a walk, and it is named as such.
	assert(route.refusal() != "")
	assert(route.refusal().contains("two stops"), "the reason wants two: %s" % route.refusal())
	# And there is no path to follow: a curve of one point has no length.
	assert(route.path() == null, "a one-stop route has no path")


func test_a_stop_carries_its_place_its_target_and_its_dwell() -> void:
	var route := Route.new()
	assert(route.add_stop("door", Vector3(1, 2, 3), Vector3(4, 5, 6), 3.5), "the stop was taken")
	var stop: Dictionary = route.stops()[0]
	assert(String(stop["name"]) == "door")
	assert(Vector3(stop["at"]) == Vector3(1, 2, 3))
	assert(Vector3(stop["look"]) == Vector3(4, 5, 6))
	assert(is_equal_approx(float(stop["dwell"]), 3.5))
	# A stop that does not state a dwell gets the default, which is a stated one.
	route.add_stop("bench", Vector3.ZERO, Vector3.FORWARD)
	assert(is_equal_approx(float(route.stops()[1]["dwell"]), Route.DEFAULT_DWELL_S))


func test_a_dwell_that_is_not_a_dwell_is_refused() -> void:
	var route := Route.new()
	assert(not route.add_stop("negative", Vector3.ZERO, Vector3.FORWARD, -1.0), "a negative dwell is refused")
	assert(not route.add_stop("forever", Vector3.ZERO, Vector3.FORWARD, 100000.0), "a dwell past the cap is refused")
	assert(not route.add_stop("not a number", Vector3.ZERO, Vector3.FORWARD, INF), "an infinite dwell is refused")
	assert(route.count() == 0, "nothing was taken")


func test_a_route_is_capped() -> void:
	var route := Route.new()
	for index in Route.MAX_STOPS:
		assert(route.add_stop("stop %d" % index, Vector3(0, 0, float(index)), Vector3.FORWARD), "stop %d fits" % index)
	assert(route.count() == Route.MAX_STOPS)
	assert(not route.add_stop("one too many", Vector3.ZERO, Vector3.FORWARD), "a full route refuses")


func test_the_legs_and_the_totals_are_the_route_s_own_measurements() -> void:
	var route := _straight_route()
	var legs: Array[float] = route.leg_lengths()
	assert(legs.size() == 1, "two stops make one leg")
	assert(is_equal_approx(legs[0], 3.0), "the leg is three metres, got %s" % legs[0])
	assert(is_equal_approx(route.total_travel(), 3.0))
	assert(is_equal_approx(route.total_dwell(), 4.0), "two two-second dwells")
	# Three metres at walking pace plus four seconds of standing.
	assert(is_equal_approx(route.duration(), 4.0 + 3.0 / Route.WALK_SPEED_MPS))


func test_a_route_of_no_places_costs_no_time() -> void:
	var route := Route.new()
	assert(is_equal_approx(route.duration(), 0.0))
	assert(is_equal_approx(route.total_travel(), 0.0))


func test_a_pace_below_walking_is_not_a_pace() -> void:
	var route := _straight_route()
	# A speed of nothing is standing still with extra steps, so the walk falls back to
	# walking pace rather than dividing the travel by zero.
	assert(is_equal_approx(route.duration(0.0), route.duration(Route.WALK_SPEED_MPS)))
	assert(is_equal_approx(route.duration(-5.0), route.duration(Route.WALK_SPEED_MPS)))


func test_a_two_stop_route_has_a_path_and_a_one_stop_route_does_not() -> void:
	var route := _straight_route()
	var path: Curve3D = route.path()
	assert(path != null, "two stops are a path")
	assert(path.point_count == 2, "the path has a point per stop")


func test_the_walk_starts_standing_at_the_first_stop() -> void:
	var route := _straight_route()
	var stage: Dictionary = route.stage_at(0.0)
	assert(int(stage["stop"]) == 0, "at nought seconds the camera is at the first stop")
	assert(not bool(stage["travelling"]))
	assert(not bool(stage["done"]))
	assert(Vector3(stage["position"]) == Vector3(0, 1.6, 0))
	assert(Vector3(stage["look"]) == Vector3(0, 1.6, 3), "looking where the stop says")


func test_the_walk_dwells_before_it_moves() -> void:
	var route := _straight_route()
	# Halfway through the first dwell, still standing at the first stop.
	var stage: Dictionary = route.stage_at(1.0)
	assert(int(stage["stop"]) == 0)
	assert(Vector3(stage["position"]) == Vector3(0, 1.6, 0), "a dwell is standing still")


func test_half_a_leg_along_is_halfway_between_the_stops_on_the_way() -> void:
	var route := _straight_route()
	# Two seconds dwelling, then half of the 3 m leg at 1.4 m/s: 2.0 + 1.5/1.4.
	var elapsed: float = 2.0 + 1.5 / Route.WALK_SPEED_MPS
	var stage: Dictionary = route.stage_at(elapsed)
	assert(bool(stage["travelling"]), "the camera is on the way")
	assert(int(stage["stop"]) == -1, "it is at no stop while it travels")
	var position: Vector3 = stage["position"]
	assert(is_equal_approx(position.z, 1.5), "half a leg is halfway, got %s" % position)
	# And it is already aimed at where it is going, not still at where it was.
	assert(Vector3(stage["look"]) == Vector3(0, 1.6, 0), "travelling looks at the next stop")


func test_the_walk_ends_standing_at_the_last_stop() -> void:
	var route := _straight_route()
	var stage: Dictionary = route.stage_at(route.duration() + 10.0)
	assert(bool(stage["done"]), "past the end the walk is done")
	assert(int(stage["stop"]) == route.count() - 1)
	assert(Vector3(stage["position"]) == Vector3(0, 1.6, 3), "at the last stop's place")
	assert(Vector3(stage["look"]) == Vector3(0, 1.6, 0), "looking where it said")


func test_position_and_look_read_the_same_stage() -> void:
	var route := _straight_route()
	var elapsed: float = 3.0
	assert(route.position_at(elapsed) == Vector3(route.stage_at(elapsed)["position"]))
	assert(route.look_at(elapsed) == Vector3(route.stage_at(elapsed)["look"]))


func test_progress_runs_from_zero_to_one() -> void:
	var route := _straight_route()
	assert(is_equal_approx(float(route.stage_at(0.0)["progress"]), 0.0))
	assert(is_equal_approx(float(route.stage_at(route.duration())["progress"]), 1.0))
	var mid: float = float(route.stage_at(route.duration() * 0.5)["progress"])
	assert(mid > 0.2 and mid < 0.8, "the middle of the walk is in the middle, got %s" % mid)


func test_the_route_describes_itself() -> void:
	var route := _straight_route()
	var text := route.describe()
	assert(text.contains("2 stops"), "the count is named: %s" % text)
	assert(text.contains("m of walking"), "the distance is named: %s" % text)
	assert(text.contains("s of standing"), "the dwell is named: %s" % text)


func test_a_route_survives_its_dict_with_its_stops() -> void:
	var route := _straight_route()
	var back: WalkRoute = Route.from_dict(route.to_dict())
	assert(back.count() == route.count())
	assert(is_equal_approx(back.total_travel(), route.total_travel()))
	assert(is_equal_approx(back.total_dwell(), route.total_dwell()))
	assert(Vector3(back.stops()[1]["at"]) == Vector3(0, 1.6, 3))


func test_a_row_that_will_not_read_is_skipped_rather_than_invented() -> void:
	var data := {
		"stops": [
			{"name": "good", "at": [0.0, 1.0, 0.0], "look": [0.0, 1.0, 5.0], "dwell": 2.0},
			{"name": "no look", "at": [0.0, 1.0, 2.0]},
			"not a row at all",
			{"name": "bad at", "at": [1.0], "look": [0.0, 1.0, 0.0]},
			{"name": "good again", "at": [0.0, 1.0, 4.0], "look": [0.0, 1.0, 0.0], "dwell": 1.0},
		],
	}
	var route: WalkRoute = Route.from_dict(data)
	assert(route.count() == 2, "only the two readable rows became stops, got %d" % route.count())
	assert(String(route.stops()[0]["name"]) == "good")
	assert(String(route.stops()[1]["name"]) == "good again")


func test_a_file_that_is_not_a_route_reads_as_no_walk() -> void:
	assert(Route.from_dict({}).count() == 0)
	assert(Route.from_dict({"stops": "nonsense"}).count() == 0)


# --- the yard walk, as one shared shape ----------------------------------------------


func test_a_yard_walk_is_built_from_the_gardens_own_bounds() -> void:
	var route: WalkRoute = Route.for_yard(Rect2(0, 0, 10, 8))
	assert(route.count() == 4, "four places along the open side, got %d" % route.count())
	assert(route.refusal() == "", "and it can be walked: %s" % route.refusal())
	var stops: Array[Dictionary] = route.stops()
	for stop: Dictionary in stops:
		var at: Vector3 = stop["at"]
		assert(is_equal_approx(at.y, Route.EYE_M), "the camera walks at eye height: %s" % at.y)
		# Every stop stands inside the garden's own footprint.
		assert(at.x >= 0.0 and at.x <= 10.0, "a stop stands within the width: %s" % at.x)
		assert(at.z >= 0.0 and at.z <= 8.0, "and within the depth: %s" % at.z)
		assert(is_equal_approx(float(stop["dwell"]), Route.DEFAULT_DWELL_S), "each dwells a default")
	# The stops run left to right in order, and the walk goes somewhere.
	assert(Vector3(stops[0]["at"]).x < Vector3(stops[3]["at"]).x, "the walk runs across the garden")
	assert(route.total_travel() > 0.0, "and it is a walk, not a stand: %s" % route.total_travel())
	var slow: WalkRoute = Route.for_yard(Rect2(0, 0, 10, 8), 5.0)
	assert(is_equal_approx(float(slow.stops()[0]["dwell"]), 5.0), "a stated dwell is used")


func test_a_yard_walk_walks_the_garden_it_is_given() -> void:
	# The same shape on a bigger garden is a bigger walk, and a garden elsewhere is walked elsewhere.
	var small: WalkRoute = Route.for_yard(Rect2(0, 0, 10, 8))
	var large: WalkRoute = Route.for_yard(Rect2(0, 0, 20, 8))
	assert(large.total_travel() > small.total_travel(), "a wider garden is a longer walk")
	assert(small.count() == large.count(), "with the same number of stops")
	var moved: WalkRoute = Route.for_yard(Rect2(40, 25, 10, 8))
	assert(Vector3(moved.stops()[0]["at"]).x > Vector3(small.stops()[0]["at"]).x,
		"and a garden elsewhere is walked elsewhere")


# --- the director -------------------------------------------------------------------


func test_a_director_with_no_route_walks_nothing() -> void:
	var director := Director.new()
	assert(not director.play(), "there is no route to play")
	assert(not director.is_done() == false, "a director with no route is done")
	assert(director.describe() == "no walk-through is loaded")


func test_a_route_of_one_stop_cannot_be_played() -> void:
	var director := Director.new()
	var route := Route.new()
	route.add_stop("somewhere", Vector3.ZERO, Vector3.FORWARD)
	director.bind(route)
	assert(not director.play(), "one stop is not a walk-through")
	assert(director.describe().contains("two stops"), "and it says why: %s" % director.describe())


func test_playing_a_real_route_starts_the_clock() -> void:
	var director := Director.new()
	director.bind(_straight_route())
	assert(director.play(), "two stops can be walked")
	assert(director.playing)
	assert(is_equal_approx(director.elapsed, 0.0))
	assert(is_equal_approx(director.progress(), 0.0))


func test_the_clock_only_moves_while_it_is_playing() -> void:
	var director := Director.new()
	director.bind(_straight_route())
	assert(not director.advance(0.2), "a paused director does not advance")
	assert(is_equal_approx(director.elapsed, 0.0))
	director.play()
	assert(director.advance(0.2), "a playing one does")
	assert(is_equal_approx(director.elapsed, 0.2))


func test_a_stalled_frame_does_not_teleport_the_camera() -> void:
	var director := Director.new()
	director.bind(_straight_route())
	director.play()
	director.advance(10.0)
	assert(is_equal_approx(director.elapsed, Director.MAX_STEP_S), "a stalled frame is clamped, got %s" % director.elapsed)


func test_the_walk_finishes_and_stops_itself() -> void:
	var director := Director.new()
	var route := _straight_route()
	director.bind(route)
	director.play()
	# Walk it out in frame-sized steps.
	var guard := 0
	while director.playing and guard < 1000:
		director.advance(0.05)
		guard += 1
	assert(not director.playing, "the walk stopped itself at the end")
	assert(director.is_done())
	assert(is_equal_approx(director.progress(), 1.0))


func test_stopping_and_restarting_are_two_different_things() -> void:
	var director := Director.new()
	director.bind(_straight_route())
	director.play()
	director.advance(0.2)
	director.stop()
	assert(not director.playing)
	assert(is_equal_approx(director.elapsed, 0.2), "stopping leaves the walk where it was")
	director.restart()
	assert(is_equal_approx(director.elapsed, 0.0), "restarting puts it back at the first stop")
	assert(not director.playing, "and does not start it again on its own")


func test_the_camera_transform_stands_at_the_walk_and_looks_along_it() -> void:
	var director := Director.new()
	director.bind(_straight_route())
	director.play()
	var transform := director.camera_transform()
	assert(transform.origin == Vector3(0, 1.6, 0), "at the first stop")
	# A camera looks down its own -Z, so the walk's target is where that axis points.
	var forward: Vector3 = -transform.basis.z
	var wanted: Vector3 = (Vector3(0, 1.6, 3) - Vector3(0, 1.6, 0)).normalized()
	assert(forward.dot(wanted) > 0.999, "the camera faces the stop's target: %s" % forward)


func test_a_camera_standing_on_what_it_looks_at_keeps_its_own_way_round() -> void:
	# The degenerate case a height-corrected stop can produce: position == target. There
	# is no direction to aim along, so the camera is moved and not spun.
	var director := Director.new()
	var route := Route.new()
	route.add_stop("here", Vector3(0, 1, 0), Vector3(0, 1, 0), 1.0)
	route.add_stop("nowhere", Vector3(0, 1, 0), Vector3(0, 1, 0), 1.0)
	director.bind(route)
	director.play()
	var fallback := Basis.looking_at(Vector3(1, 0, 0), Vector3.UP)
	var transform := director.camera_transform(fallback)
	assert(transform.origin == Vector3(0, 1, 0))
	assert(transform.basis.is_equal_approx(fallback), "the camera kept its own orientation")


func test_applying_to_a_camera_moves_it_to_the_walk() -> void:
	var director := Director.new()
	director.bind(_straight_route())
	director.play()
	# No scene, so the director writes the camera's local transform - the same transform a
	# camera in the tree would have as its global one.
	var camera := Camera3D.new()
	assert(director.apply_to(camera), "the camera was placed")
	assert(camera.transform.origin == Vector3(0, 1.6, 0), "at the first stop")
	# A director with no route cannot place a camera anywhere.
	var empty := Director.new()
	assert(not empty.apply_to(camera), "nothing to apply")
	assert(not director.apply_to(null), "and there is nowhere to apply it to")
	camera.free()


func test_the_director_describes_itself() -> void:
	var director := Director.new()
	director.bind(_straight_route())
	director.play()
	var text := director.describe()
	assert(text.contains("playing"), "the state is named: %s" % text)
	assert(text.contains("2 stops"), "and so is the route: %s" % text)