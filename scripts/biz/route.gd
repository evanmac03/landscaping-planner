class_name Route
extends RefCounted
## A crew day as a proposed order of stops, and the assumption it was computed under (spec §7.2).
##
## Routing is a heuristic, and **a heuristic that states its assumption** (§2.8): the travelling-
## salesman optimum is a research problem, drive times are a guess without a real routing service, and
## a crew sent the wrong way twice stops trusting the software. So this is nearest-neighbour from where
## the crew starts, then 2-opt while the total drive time improves - **deterministic**, no randomness
## and no time limit, so the same stops give the same order every run.
##
## The result is a **proposal**, not a decision. The office drags stops and the sequence wins; this
## only computes `order`. A stop whose window cannot be met is **reported as late**, never silently
## reordered - the window belongs to the customer's plumber or the nursery's delivery, not to the
## optimiser.
##
## All times here are **minutes**: window bounds are minutes from midnight, `start_minute` is when the
## day begins, and drive and service are durations in minutes. Money is nowhere in this file.

## What a straight-line estimate assumes when no matrix is supplied. Stated, printed with the route,
## and overridable - a route computed on 40 km/h is a different artefact from one computed on a real
## drive-time matrix, so which one it was is part of the result.
const DEFAULT_SPEED_KMH := 40.0
const MINUTES_PER_HOUR := 60.0
const METRES_PER_KM := 1000.0

## What a stop's `window_start`/`window_end` mean when absent: no window, so it can never be late.
const NO_WINDOW := -1


## Plan a day. `stops` are `{id, at: Vector2, window_start, window_end, service_minutes}` and the
## result is `{order, legs, late, total_drive_minutes, finish_minute, note}`.
##
## `matrix` is an optional drive-time matrix keyed `"a|b"` where `a`/`b` are stop indices and `-1` is
## the crew's start: supply it and the route is computed on it rather than on the speed estimate.
## Every key it does not hold falls back to the straight-line estimate, so a partial matrix is fine.
static func plan(home: Vector2, stops: Array, speed_kmh: float = DEFAULT_SPEED_KMH,
		matrix: Dictionary = {}, start_minute: int = 0) -> Dictionary:
	var note := _note_for(speed_kmh, matrix)
	var order: Array[int] = []
	var legs: Array[Dictionary] = []
	if stops.is_empty():
		return {
			"order": order, "legs": legs, "late": [], "total_drive_minutes": 0.0,
			"finish_minute": start_minute, "note": note,
		}

	order = _nearest_neighbour(home, stops, speed_kmh, matrix)
	_two_opt(order, home, stops, speed_kmh, matrix)

	# Walk the proposed order with a clock, and say which windows it misses.
	var late: Array[Dictionary] = []
	var clock := start_minute
	var previous := -1
	var total := 0.0
	for index in order:
		var drive := _leg_minutes(home, stops, speed_kmh, matrix, previous, index)
		total += drive
		clock += int(round(drive))
		legs.append({"from": previous, "to": index, "drive_minutes": drive})
		var stop: Dictionary = stops[index]
		var window_start := int(stop.get("window_start", NO_WINDOW))
		var window_end := int(stop.get("window_end", NO_WINDOW))
		if window_start != NO_WINDOW and clock < window_start:
			clock = window_start
		if window_end != NO_WINDOW and clock > window_end:
			late.append({"index": index, "by_minutes": clock - window_end})
		clock += int(stop.get("service_minutes", 0))
		previous = index
	# And the drive home, which is part of the day even though it is not a stop.
	var home_leg := _leg_minutes(home, stops, speed_kmh, matrix, previous, -1)
	total += home_leg
	clock += int(round(home_leg))
	legs.append({"from": previous, "to": -1, "drive_minutes": home_leg})

	return {
		"order": order,
		"legs": legs,
		"late": late,
		"total_drive_minutes": total,
		"finish_minute": clock,
		"note": note,
	}


## The order of stop indices a day would be worked in, without the clock. A convenience for a caller
## that only wants the sequence.
static func order_for(home: Vector2, stops: Array, speed_kmh: float = DEFAULT_SPEED_KMH,
		matrix: Dictionary = {}) -> Array[int]:
	if stops.is_empty():
		return []
	var order := _nearest_neighbour(home, stops, speed_kmh, matrix)
	_two_opt(order, home, stops, speed_kmh, matrix)
	return order


# --- the heuristic ---------------------------------------------------------------------------


## Nearest neighbour from the crew's position: repeatedly go to the closest stop not yet visited.
## A tie is broken by the lower index, which is what makes the same stops give the same order.
static func _nearest_neighbour(home: Vector2, stops: Array, speed_kmh: float,
		matrix: Dictionary) -> Array[int]:
	var order: Array[int] = []
	var remaining: Array[int] = []
	for index in stops.size():
		remaining.append(index)
	var here := -1
	while not remaining.is_empty():
		var best := 0
		var best_minutes := INF
		for slot in remaining.size():
			var candidate: int = remaining[slot]
			var minutes := _leg_minutes(home, stops, speed_kmh, matrix, here, candidate)
			if minutes < best_minutes - 1e-9:
				best_minutes = minutes
				best = slot
		var chosen: int = remaining[best]
		order.append(chosen)
		remaining.remove_at(best)
		here = chosen
	return order


## 2-opt: reverse any run of stops that shortens the round trip, until none does. Deterministic -
## the loops run in index order and the improvement test is strict, so it always settles the same way.
static func _two_opt(order: Array[int], home: Vector2, stops: Array, speed_kmh: float,
		matrix: Dictionary) -> void:
	var count := order.size()
	if count < 3:
		return
	var improved := true
	while improved:
		improved = false
		for i in count - 1:
			for j in range(i + 1, count):
				var before := _tour_minutes(order, home, stops, speed_kmh, matrix)
				_reverse_slice(order, i, j)
				var after := _tour_minutes(order, home, stops, speed_kmh, matrix)
				if after < before - 1e-9:
					improved = true
				else:
					_reverse_slice(order, i, j)  # not an improvement: put it back
	# Nothing to return: `order` was edited in place.


static func _reverse_slice(order: Array[int], from_index: int, to_index: int) -> void:
	var left := from_index
	var right := to_index
	while left < right:
		var held: int = order[left]
		order[left] = order[right]
		order[right] = held
		left += 1
		right -= 1


## The drive time of a whole tour: home, each stop in order, and home again.
static func _tour_minutes(order: Array[int], home: Vector2, stops: Array, speed_kmh: float,
		matrix: Dictionary) -> float:
	var total := 0.0
	var previous := -1
	for index in order:
		total += _leg_minutes(home, stops, speed_kmh, matrix, previous, index)
		previous = index
	total += _leg_minutes(home, stops, speed_kmh, matrix, previous, -1)
	return total


static func _leg_minutes(home: Vector2, stops: Array, speed_kmh: float, matrix: Dictionary,
		from_index: int, to_index: int) -> float:
	var key := "%d|%d" % [from_index, to_index]
	if matrix.has(key):
		return float(matrix[key])
	return drive_minutes(_point_of(home, stops, from_index), _point_of(home, stops, to_index), speed_kmh)


## Drive time between two places at a constant speed, in minutes. `at` is the drawing's model metres
## and `speed_kmh` is kilometres per hour, so the units are converted in one place.
static func drive_minutes(from_at: Vector2, to_at: Vector2, speed_kmh: float = DEFAULT_SPEED_KMH) -> float:
	var speed := speed_kmh if speed_kmh > 0.0 else DEFAULT_SPEED_KMH
	var km := from_at.distance_to(to_at) / METRES_PER_KM
	return km / speed * MINUTES_PER_HOUR


## The place an index refers to: -1 is the crew's start, anything else is that stop's `at`.
static func _point_of(home: Vector2, stops: Array, index: int) -> Vector2:
	if index < 0 or index >= stops.size():
		return home
	var stop: Dictionary = stops[index]
	var at = stop.get("at", Vector2.ZERO)
	if at is Vector2:
		return at
	if at is Array and (at as Array).size() == 2:
		return Vector2(float(at[0]), float(at[1]))
	return Vector2.ZERO


static func _note_for(speed_kmh: float, matrix: Dictionary) -> String:
	if matrix.is_empty():
		return "nearest-neighbour plus 2-opt over a straight-line estimate at %s km/h" % str(speed_kmh)
	return "nearest-neighbour plus 2-opt over the supplied drive-time matrix, with %s km/h for legs it does not hold" % str(speed_kmh)