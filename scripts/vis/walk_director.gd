class_name VisWalkDirector
extends RefCounted
## Walks a camera along a `WalkRoute`: the clock, and the one transform it applies.
##
## The arithmetic lives in `WalkRoute` (where it can be tested without a camera); this is
## the small part that has a camera in its hand. It holds the elapsed time, steps it by a
## frame's delta, and turns "where am I and what am I looking at" into a `Transform3D` and
## onto the camera.
##
## The camera is set by *global transform* rather than through a rig, because a
## walk-through is not an orbit: the camera goes where the route says regardless of which
## parent it happens to sit under. `Basis.looking_at` is the whole of the aiming - a
## camera whose position equals its target has no direction to look in, so that case keeps
## the camera's existing orientation and moves it, rather than raising.
##
## A walk-through is a *sequence*, and Godot's Movie Maker records one (`--write-movie`,
## with `OS.has_feature("movie")` true while it runs). Nothing here reaches for it: the
## director advances the same clock a recorded frame or a live frame would, so what
## `tools/walk_demo.gd` renders as stills is the same walk Movie Maker would film.

## A frame longer than this is a stall, not a step. Clamping means a hitched frame skips
## a moment of the walk instead of teleporting the camera half a leg down the route.
const MAX_STEP_S := 0.25
## The shortest leg the director will bother looking along, in metres.
const EPSILON_M := 1.0e-4

## The route being walked.
var route: WalkRoute = null
## Metres per second. A walk-through that glides is a fly-through.
var speed_mps: float = WalkRoute.WALK_SPEED_MPS
## Seconds since the walk began.
var elapsed: float = 0.0
## Whether the clock is running.
var playing: bool = false


## Point the director at a route. Does not start it: `play()` is a decision.
func bind(route_ref: WalkRoute) -> void:
	route = route_ref
	elapsed = 0.0
	playing = false


## Begin the walk. Refused, in the route's own words, when the route cannot be walked -
## one stop or none (REQ-V9.5) - so a caller learns why instead of watching a still frame.
func play() -> bool:
	if route == null:
		return false
	if route.refusal() != "":
		return false
	elapsed = 0.0
	playing = true
	return true


## Stand still, where the walk has got to.
func stop() -> void:
	playing = false


## Back to the first stop, still playing if it was playing.
func restart() -> void:
	elapsed = 0.0


## Step the clock by a frame. Returns whether the walk is still running afterwards.
func advance(delta: float) -> bool:
	if not playing:
		return false
	elapsed += clampf(delta, 0.0, MAX_STEP_S)
	if is_done():
		playing = false
	return playing


## Whether the walk has reached the last stop.
func is_done() -> bool:
	if route == null:
		return true
	return elapsed >= route.duration(speed_mps)


## The whole state right now: `WalkRoute.stage_at` plus the share of the walk done.
func stage() -> Dictionary:
	if route == null:
		return {"position": Vector3.ZERO, "look": Vector3.ZERO, "stop": -1, "travelling": false, "done": true, "progress": 1.0}
	return route.stage_at(elapsed, speed_mps)


## How much of the walk is behind the camera, in 0..1.
func progress() -> float:
	return float(stage()["progress"])


## The transform the camera should be at right now. Pure: it reads the route and the
## clock and touches nothing.
##
## `fallback_up` is the camera's own current basis, used only for the degenerate case
## where the camera is standing exactly on what it is meant to look at.
func camera_transform(fallback_basis: Basis = Basis()) -> Transform3D:
	var here: Dictionary = stage()
	var position: Vector3 = here["position"]
	var look: Vector3 = here["look"]
	var to_target: Vector3 = look - position
	if to_target.length() < EPSILON_M:
		# Nothing to aim along: keep the orientation the camera already had and move it.
		return Transform3D(fallback_basis, position)
	return Transform3D(Basis.looking_at(to_target, Vector3.UP), position)


## Put the camera where the walk is. Returns false when there is nothing to apply, so a
## caller can say so rather than discovering a camera that never moved.
##
## A camera inside the tree is placed by *global* transform, because a walk-through is not
## an orbit and the camera goes where the route says whatever parent it sits under. A
## camera not yet in the tree has no global transform to read or write, so the local one
## is used instead - which is what lets this be proved without a running scene.
func apply_to(camera: Camera3D) -> bool:
	if camera == null or route == null or route.is_empty():
		return false
	if camera.is_inside_tree():
		camera.global_transform = camera_transform(camera.global_transform.basis)
	else:
		camera.transform = camera_transform(camera.transform.basis)
	return true


## The walk in one line, for a status bar or a dock.
func describe() -> String:
	if route == null:
		return "no walk-through is loaded"
	if route.refusal() != "":
		return route.refusal()
	return "%s - %s, %.1f s in, %.0f%% done" % [
		route.describe(),
		"playing" if playing else ("done" if is_done() else "paused"),
		elapsed,
		progress() * 100.0,
	]