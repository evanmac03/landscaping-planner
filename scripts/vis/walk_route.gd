class_name WalkRoute
extends RefCounted
## An ordered walk through the garden: the stops a client is shown, and how long the
## camera dwells at each.
##
## A route is authored data, not a camera path. The stops are places a person would
## stand - "living room door", "end of the path" - which is what makes a walk-through
## feel like a visit rather than a drone flight (specification section 9.2).
##
## The route is also its own clock. `duration()` is how long the walk takes, and
## `position_at()` / `look_at()` answer where the camera is and what it is pointed at
## after so many seconds - pausing at each stop for its own dwell, then travelling the
## leg to the next. That timing is here rather than in a director because it is pure
## arithmetic and a director is a node: a walk-through that can only be checked by
## watching it is a walk-through nobody can test, and REQ-V9.3 is about the dwell.
##
## `WALK_SPEED_MPS` is 1.4, which is a person's walking pace. A walk-through that
## glides is a fly-through, and one that runs is a chase.

## The most stops a route will hold. A walk-through is a handful of places a client is
## shown, not a tour of the whole county.
const MAX_STOPS := 64
## How long the camera dwells at a stop that did not say.
const DEFAULT_DWELL_S := 2.5
## A dwell nobody would sit through, refused rather than clamped silently at the top end.
const MAX_DWELL_S := 120.0
## Walking pace, metres per second.
const WALK_SPEED_MPS := 1.4
## A speed below this is standing still with extra steps.
const MIN_SPEED_MPS := 0.05
## The height the camera walks at, in metres: about a person's eye.
const EYE_M := 1.6

## How a garden walk is shaped, as shares of the garden's own bounds, so it walks whatever
## garden is on the drawing. A walk-through of a garden with a house in the middle is a walk
## *along* the garden, not a lap around the house: a stop behind the house looks at the back
## of it and a stop inside looks at nothing. The stops stand on the open side and look across
## at the dwelling, which is the view a client is shown.
##
## `YARD_SPAN` is how far along the width the walk runs each way from the middle, `YARD_AT_FRONT`
## how far out from the middle towards the open side as a share of the depth - far enough out to
## stand in the garden rather than against the wall - and `YARD_SWING` how far across the garden
## the camera is aimed, opposite the side it is standing on, so the walker looks *along* the
## garden instead of flat at a wall: a walk-through that stares down the front of a house is a
## photograph of a house. `YARD_AIM_BACK` is how far past the middle the look-at line sits.
const YARD_SPAN := 0.20
const YARD_AT_FRONT := 0.42
const YARD_SWING := 0.40
const YARD_AIM_BACK := 0.18
## The four places along the open side, in the order they are visited.
const YARD_STOP_NAMES: Array[String] = ["left", "centre left", "centre right", "right"]

## The stops, in the order they were added.
var _stops: Array[Dictionary] = []


## Add a stop: where to stand, what to look at, and how long to stay. Refused when the
## route is full or the dwell is not a dwell, in both cases by returning false so the
## caller can say why rather than discovering a missing stop later.
##
## The target is `aim_at` and not `look_at` because `look_at` is the route's own question
## ("what is the camera pointed at after n seconds"); a parameter of that name would shadow
## the method for the whole file.
func add_stop(stop_name: String, at: Vector3, aim_at: Vector3, dwell_s: float = DEFAULT_DWELL_S) -> bool:
	if _stops.size() >= MAX_STOPS:
		return false
	if not is_finite(dwell_s) or dwell_s < 0.0 or dwell_s > MAX_DWELL_S:
		return false
	_stops.append({
		"name": stop_name,
		"at": at,
		"look": aim_at,
		"dwell": dwell_s,
	})
	return true


## Every stop, in order.
func stops() -> Array[Dictionary]:
	return _stops.duplicate(true)


## How many stops there are.
func count() -> int:
	return _stops.size()


func is_empty() -> bool:
	return _stops.is_empty()


## Forget the route: it is authored data a person makes once.
func clear() -> void:
	_stops.clear()


## Why the route cannot be walked yet, or "" when it can. REQ-V9.5: a route with fewer
## than two stops is refused, named, and never followed silently - one stop is a picture
## and no stops is a camera in the dark.
func refusal() -> String:
	if _stops.is_empty():
		return "the walk-through has no stops yet."
	if _stops.size() < 2:
		return "a walk-through needs somewhere to walk: two stops, not one."
	return ""


## The route as a path through the stops, in the order they were added.
##
## Godot's `Curve3D.add_point` with no handles draws a straight segment, so this is the
## polyline through the stops; `look_at()` turns the camera *while* it travels, which is
## what keeps a walk-through from stopping dead and spinning on the spot. Null when there
## are fewer than two stops, because a curve of one point has no length to follow and a
## caller told "" is better served than one handed an empty path.
func path() -> Curve3D:
	if _stops.size() < 2:
		return null
	var curve := Curve3D.new()
	for stop: Dictionary in _stops:
		curve.add_point(stop["at"])
	return curve


## The straight-line length of each leg, in metres. One shorter than the stop count.
func leg_lengths() -> Array[float]:
	var out: Array[float] = []
	for index in _stops.size() - 1:
		out.append(Vector3(_stops[index]["at"]).distance_to(Vector3(_stops[index + 1]["at"])))
	return out


## How far the camera travels in all.
func total_travel() -> float:
	var out := 0.0
	for length: float in leg_lengths():
		out += length
	return out


## How long the camera stands still in all.
func total_dwell() -> float:
	var out := 0.0
	for stop: Dictionary in _stops:
		out += float(stop["dwell"])
	return out


## How long the whole walk takes at a stated pace: the dwells plus the legs.
func duration(speed_mps: float = WALK_SPEED_MPS) -> float:
	var pace: float = speed_mps if speed_mps >= MIN_SPEED_MPS else WALK_SPEED_MPS
	return total_dwell() + total_travel() / pace


## Where the camera stands after `elapsed` seconds.
##
## The clock runs: dwell at the first stop, travel to the second, dwell there, and so on.
## During a dwell the answer is the stop's own place; during a leg it is the point that
## many metres along the path, so the camera moves at the pace asked for. Past the end it
## is the last stop, which is what "finished" looks like rather than a teleport.
func position_at(elapsed: float, speed_mps: float = WALK_SPEED_MPS) -> Vector3:
	var stage := stage_at(elapsed, speed_mps)
	return Vector3(stage["position"])


## What the camera is pointed at after `elapsed` seconds: the stop it is standing at
## while it dwells, and the *next* stop's target while it travels - so the camera turns on
## the way rather than after it arrives.
func look_at(elapsed: float, speed_mps: float = WALK_SPEED_MPS) -> Vector3:
	var stage := stage_at(elapsed, speed_mps)
	return Vector3(stage["look"])


## The whole state after `elapsed` seconds, in one dictionary, so a director and a test
## ask the same question once: `{position, look, stop, travelling, done, progress}`.
##
## `stop` is the index of the stop the camera is at, or -1 while it is travelling;
## `progress` is the walk as a share of its own duration, in 0..1.
func stage_at(elapsed: float, speed_mps: float = WALK_SPEED_MPS) -> Dictionary:
	if _stops.is_empty():
		return {"position": Vector3.ZERO, "look": Vector3.ZERO, "stop": -1, "travelling": false, "done": true, "progress": 1.0}
	var pace: float = speed_mps if speed_mps >= MIN_SPEED_MPS else WALK_SPEED_MPS
	var total: float = duration(pace)
	var clock: float = maxf(elapsed, 0.0)
	if clock >= total:
		# Arrived. The camera stands at the last stop rather than teleporting anywhere.
		var arrived: Dictionary = _stops[_stops.size() - 1]
		return {
			"position": Vector3(arrived["at"]),
			"look": Vector3(arrived["look"]),
			"stop": _stops.size() - 1,
			"travelling": false,
			"done": true,
			"progress": 1.0,
		}
	var travelled := 0.0
	for index in _stops.size():
		var stop: Dictionary = _stops[index]
		var dwell: float = float(stop["dwell"])
		if clock <= dwell:
			return {
				"position": Vector3(stop["at"]),
				"look": Vector3(stop["look"]),
				"stop": index,
				"travelling": false,
				"done": false,
				"progress": clock / total,
			}
		clock -= dwell
		if index >= _stops.size() - 1:
			break
		var leg: float = Vector3(stop["at"]).distance_to(Vector3(_stops[index + 1]["at"]))
		var leg_time: float = leg / pace
		if clock <= leg_time:
			var along: float = travelled + clock * pace
			return {
				"position": _point_along(along),
				"look": Vector3(_stops[index + 1]["look"]),
				"stop": -1,
				"travelling": true,
				"done": false,
				"progress": elapsed / total,
			}
		clock -= leg_time
		travelled += leg
	var end_stop: Dictionary = _stops[_stops.size() - 1]
	return {
		"position": Vector3(end_stop["at"]),
		"look": Vector3(end_stop["look"]),
		"stop": _stops.size() - 1,
		"travelling": false,
		"done": true,
		"progress": 1.0,
	}


## A point `distance` metres along the path, measured in the same straight legs
## `look_at` walks. Piecewise, so it never depends on a bake interval nobody set.
func _point_along(distance: float) -> Vector3:
	var left: float = maxf(distance, 0.0)
	var lengths := leg_lengths()
	for index in lengths.size():
		var leg: float = lengths[index]
		var from := Vector3(_stops[index]["at"])
		var to := Vector3(_stops[index + 1]["at"])
		if left <= leg:
			return from.lerp(to, left / leg) if leg > 0.0 else to
		left -= leg
	return Vector3(_stops[_stops.size() - 1]["at"])


## A one-line summary, for a dock or a status bar.
func describe() -> String:
	if _stops.is_empty():
		return "an empty walk-through"
	return "%d stops, %.1f m of walking, %.1f s of standing, %.0f s in all" % [
		_stops.size(), total_travel(), total_dwell(), duration(),
	]


## The route as data, so it survives the file with its stops.
func to_dict() -> Dictionary:
	var rows: Array = []
	for stop: Dictionary in _stops:
		rows.append({
			"name": String(stop["name"]),
			"at": [Vector3(stop["at"]).x, Vector3(stop["at"]).y, Vector3(stop["at"]).z],
			"look": [Vector3(stop["look"]).x, Vector3(stop["look"]).y, Vector3(stop["look"]).z],
			"dwell": float(stop["dwell"]),
		})
	return {"stops": rows}


## A route from data. A row that will not read is skipped rather than invented, and a
## dwell that is not a dwell becomes the default, so an old file still walks.
static func from_dict(data: Dictionary) -> WalkRoute:
	var route := WalkRoute.new()
	var rows: Variant = data.get("stops", [])
	if not rows is Array:
		return route
	for row: Variant in rows:
		if not row is Dictionary:
			continue
		var entry: Dictionary = row
		var at: Variant = entry.get("at", null)
		var look: Variant = entry.get("look", null)
		if not at is Array or not look is Array or (at as Array).size() < 3 or (look as Array).size() < 3:
			continue
		var at_v: Array = at
		var look_v: Array = look
		var dwell := DEFAULT_DWELL_S
		var stated: Variant = entry.get("dwell", DEFAULT_DWELL_S)
		if stated is float or stated is int:
			dwell = float(stated)
		route.add_stop(
			String(entry.get("name", "")),
			Vector3(float(at_v[0]), float(at_v[1]), float(at_v[2])),
			Vector3(float(look_v[0]), float(look_v[1]), float(look_v[2])),
			dwell
		)
	return route


## A walk-through of a garden, built from the garden's own bounds rather than hard-coded, so it
## walks whatever garden is on the drawing. Four places along the open side, evenly spread
## across the width, each looking across to the far side: the walker turns their head as they go.
##
## This is the one description of the yard walk, so the game that plays it and the demo that
## renders it depart from the same route rather than two copies of the same authoring taste.
static func for_yard(bounds: Rect2, dwell_s: float = DEFAULT_DWELL_S) -> WalkRoute:
	var route := WalkRoute.new()
	var mid_x: float = bounds.position.x + bounds.size.x * 0.5
	var mid_z: float = bounds.position.y + bounds.size.y * 0.5
	var stand_z: float = mid_z + bounds.size.y * YARD_AT_FRONT
	var aim_z: float = mid_z - bounds.size.y * YARD_AIM_BACK
	var places: int = YARD_STOP_NAMES.size()
	for index in places:
		var share: float = -1.0 + 2.0 * float(index) / float(maxi(places - 1, 1))
		var at := Vector3(mid_x + bounds.size.x * YARD_SPAN * share, EYE_M, stand_z)
		var aim := Vector3(mid_x - bounds.size.x * YARD_SWING * share, EYE_M, aim_z)
		route.add_stop(YARD_STOP_NAMES[index], at, aim, dwell_s)
	return route