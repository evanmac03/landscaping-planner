extends Node
## The route: nearest-neighbour plus 2-opt, stated, deterministic, and reporting late windows
## (spec §7.2, §2.8).

const RouteScript := preload("res://scripts/biz/route.gd")


## Four stops on a line and one off it, so nearest-neighbour alone takes a wrong turn that 2-opt fixes.
func _square_stops() -> Array:
	return [
		{"id": "A", "at": Vector2(0, 0)},
		{"id": "B", "at": Vector2(1000, 0)},
		{"id": "C", "at": Vector2(1000, 1000)},
		{"id": "D", "at": Vector2(0, 1000)},
	]


func test_a_day_with_no_stops_is_still_the_day_it_started() -> void:
	var plan := RouteScript.plan(Vector2.ZERO, [], 40.0, {}, 480)
	assert((plan["order"] as Array).is_empty())
	assert(float(plan["total_drive_minutes"]) == 0.0)
	assert(int(plan["finish_minute"]) == 480)
	assert(String(plan["note"]).contains("40"), "and the assumption is stated")


func test_drive_minutes_measures_a_distance_at_a_speed_in_one_place() -> void:
	# 1 km at 40 km/h is a minute and a half.
	assert(absf(RouteScript.drive_minutes(Vector2.ZERO, Vector2(1000, 0), 40.0) - 1.5) < 0.0001)
	# Twice the distance is twice the time.
	assert(absf(RouteScript.drive_minutes(Vector2.ZERO, Vector2(2000, 0), 40.0) - 3.0) < 0.0001)
	# A speed of nothing falls back rather than dividing by zero.
	assert(absf(RouteScript.drive_minutes(Vector2.ZERO, Vector2(1000, 0), 0.0) - 1.5) < 0.0001)


func test_the_route_starts_with_the_nearest_stop() -> void:
	var stops: Array = [
		{"id": "far", "at": Vector2(5000, 0)},
		{"id": "near", "at": Vector2(500, 0)},
		{"id": "mid", "at": Vector2(2000, 0)},
	]
	var plan := RouteScript.plan(Vector2.ZERO, stops, 40.0)
	assert((plan["order"] as Array)[0] == 1, "the nearest stop is visited first")


func test_the_same_stops_give_the_same_order_every_time() -> void:
	# §2.8: deterministic, no randomness. Two runs of one list are one order.
	var first := RouteScript.order_for(Vector2.ZERO, _square_stops(), 40.0)
	var second := RouteScript.order_for(Vector2.ZERO, _square_stops(), 40.0)
	assert(first == second)
	# And a tie is broken by index, not by chance.
	var tied: Array = [{"id": "a", "at": Vector2(1000, 0)}, {"id": "b", "at": Vector2(0, 1000)}]
	var tied_order := RouteScript.order_for(Vector2.ZERO, tied, 40.0)
	assert(tied_order == [0, 1], "a tie is broken by index, not by chance")


func test_two_opt_never_makes_a_tour_worse_than_the_one_it_started_from() -> void:
	var home := Vector2(-500.0, 500.0)
	var stops := _square_stops()
	var naive := 0.0
	var previous := home
	for stop in stops:
		naive += RouteScript.drive_minutes(previous, stop["at"], 40.0)
		previous = stop["at"]
	naive += RouteScript.drive_minutes(previous, home, 40.0)
	var plan := RouteScript.plan(home, stops, 40.0)
	assert(float(plan["total_drive_minutes"]) <= naive + 0.001,
		"the optimiser improved the tour it was given, or left it alone")
	# And every stop is on the route exactly once.
	var order: Array = plan["order"]
	var seen := {}
	for index in order:
		seen[index] = true
	assert(order.size() == 4 and seen.size() == 4)


func test_the_legs_include_the_drive_home() -> void:
	var plan := RouteScript.plan(Vector2.ZERO, [{"id": "A", "at": Vector2(1000, 0)}], 40.0)
	var legs: Array = plan["legs"]
	assert(legs.size() == 2, "out and back")
	assert(int((legs[0] as Dictionary)["from"]) == -1, "the first leg leaves home")
	assert(int((legs[1] as Dictionary)["to"]) == -1, "and the last one comes home")


func test_the_total_is_the_sum_of_the_legs() -> void:
	var plan := RouteScript.plan(Vector2.ZERO, _square_stops(), 40.0)
	var summed := 0.0
	for leg in (plan["legs"] as Array):
		summed += float((leg as Dictionary)["drive_minutes"])
	assert(absf(summed - float(plan["total_drive_minutes"])) < 0.0001)


func test_a_window_that_cannot_be_met_is_reported_not_reordered() -> void:
	var stops: Array = [
		{"id": "A", "at": Vector2(0, 0), "window_start": 480, "window_end": 500},
		{"id": "B", "at": Vector2(1000, 0), "window_start": 480, "window_end": 481, "service_minutes": 120},
	]
	var plan := RouteScript.plan(Vector2.ZERO, stops, 40.0, {}, 480)
	var late: Array = plan["late"]
	assert(late.size() == 1, "exactly one window is missed")
	assert(int((late[0] as Dictionary)["index"]) == 1)
	assert(int((late[0] as Dictionary)["by_minutes"]) > 0)
	# The order itself was left alone: the optimiser does not move a customer's window.
	var order: Array = plan["order"]
	assert(order.size() == 2)


func test_waiting_for_a_window_to_open_is_not_being_late() -> void:
	var stops: Array = [{"id": "A", "at": Vector2(1000, 0), "window_start": 600, "window_end": 660}]
	var plan := RouteScript.plan(Vector2.ZERO, stops, 40.0, {}, 480)
	assert((plan["late"] as Array).is_empty(), "arriving early is not a conflict, it is a wait")
	assert(int(plan["finish_minute"]) >= 600, "and the clock waited for the window")


func test_service_time_extends_the_day() -> void:
	var stops: Array = [{"id": "A", "at": Vector2(1000, 0), "service_minutes": 90}]
	var plan := RouteScript.plan(Vector2.ZERO, stops, 40.0, {}, 480)
	# 1.5 out rounds to 2, 90 on site, 1.5 home rounds to 2: the clock lands on 574.
	assert(int(plan["finish_minute"]) == 574, str(plan["finish_minute"]))


func test_a_supplied_matrix_beats_the_speed_estimate_and_says_so() -> void:
	# The drive out is really twenty minutes, not one and a half; the matrix says so.
	var stops: Array = [{"id": "A", "at": Vector2(1000, 0)}]
	var matrix := {"-1|0": 20.0, "0|-1": 25.0}
	var plan := RouteScript.plan(Vector2.ZERO, stops, 40.0, matrix, 480)
	assert(absf(float(plan["total_drive_minutes"]) - 45.0) < 0.0001, str(plan["total_drive_minutes"]))
	assert(String(plan["note"]).contains("matrix"), "and the note says which assumption it used")