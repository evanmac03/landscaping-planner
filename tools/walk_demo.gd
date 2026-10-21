extends Node
## A walk-through: the camera visits four places around the garden, dwells at each, and
## one still is rendered from every stop.
##
## A development tool rather than part of the game. It drives the *real* presentation
## camera in the *real* scene and renders through the *real* exporter, so what it makes
## is what a client would be shown. The route is built from the yard's own bounds rather
## than hard-coded, so it walks whatever garden is on the drawing.
##
## A walk-through is a sequence, and Movie Maker is how Godot records one (`--write-movie`,
## with `OS.has_feature("movie")` true while it runs). This demo films the same walk a
## frame at a time instead: it steps the director's clock and takes a still at each stop,
## which is what makes the walk checkable in a screenshot. What it prints at the end is
## the route's own arithmetic - the distance, the dwell, the duration - because the thing
## worth seeing is that the walk is *described* and not merely played.

const AppScene := preload("res://scenes/main.tscn")
const RouteScript := preload("res://scripts/vis/walk_route.gd")
const DirectorScript := preload("res://scripts/vis/walk_director.gd")
const TierScript := preload("res://scripts/vis/presentation_tier.gd")

## How high the camera stands, in metres: about a person's eye.
const EYE_M := 1.6
## How long to stand at each stop.
const DWELL_S := 2.5
## The stops are authored, and the authoring matters: a walk-through of a garden with a
## house in the middle is a walk *along the garden*, not a lap around the house. A stop
## behind the house looks at the back of the house, and a stop inside it looks at nothing.
## These four stand on the open side and look across at the dwelling, which is the view a
## client is shown.
##
## `SPAN` is how far along the garden's width the walk runs, each way from the middle, and
## `AT_FRONT` how far out from the middle towards the open side, as a share of the garden's
## depth - far enough out that the walk stands in the garden rather than against the wall.
## `SWING` is how far across the garden the camera is aimed, opposite the side it is
## standing on, so the walker looks *along* the garden instead of flat at a wall: a
## walk-through that stares down the front of a house is a photograph of a house.
const SPAN := 0.20
const AT_FRONT := 0.42
const SWING := 0.40
## The stills' size, and where they land. `preview/` is gitignored: a picture of output
## goes stale the moment the exporter changes.
const STILL_SIZE := Vector2i(960, 540)
const OUT_DIR := "res://preview/walk-demo"
## How long to wait for a still before giving up on it. A tool that blocks forever on a
## refused render is worse than one that reports it.
const WAIT_FRAMES := 900

var _app: Node = null
var _director: Node3D = null
## The presentation camera, which the walk-through takes over: the stills are taken from
## wherever the walk has got to.
var _camera: Camera3D = null


func _ready() -> void:
	_app = AppScene.instantiate()
	_app.name = "App"
	add_child(_app)
	# Two frames: one for the app's own `_ready`, one for the presenter to adopt the site.
	await get_tree().process_frame
	await get_tree().process_frame
	_director = _app.get_node_or_null("Presentation") as Node3D
	if _director == null:
		print("walk_demo: main.tscn has no Presentation node")
		return
	await _run()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	_director.set_tier(TierScript.STILL)
	_director.frame_yard()
	_camera = _director.orbit.camera as Camera3D
	if _camera == null:
		print("walk_demo: the presenter has no camera to walk")
		return
	await get_tree().process_frame

	var route = _build_route()
	print("route: %s" % route.describe())
	for index in route.count():
		var stop: Dictionary = route.stops()[index]
		print("  %d. %s at (%.1f, %.1f, %.1f), looks at (%.1f, %.1f, %.1f), %s s" % [
			index + 1, String(stop["name"]),
			Vector3(stop["at"]).x, Vector3(stop["at"]).y, Vector3(stop["at"]).z,
			Vector3(stop["look"]).x, Vector3(stop["look"]).y, Vector3(stop["look"]).z,
			String.num(float(stop["dwell"]), 1),
		])

	var director = DirectorScript.new()
	director.bind(route)
	if not director.play():
		print("walk_demo: the route cannot be walked: %s" % route.refusal())
		return

	# Walk it out in frame-sized steps, taking a still when the camera is standing at a
	# stop. The clock is the route's, so the stills are the moments the walk pauses.
	var taken: Array[String] = []
	var step := 0.05
	var guard := 0
	var standing_at := -1
	while guard < 4000:
		guard += 1
		if director.playing:
			director.advance(step)
		var stage: Dictionary = director.stage()
		var stop_index: int = int(stage["stop"])
		if stop_index >= 0 and stop_index != standing_at and not bool(stage["done"]):
			standing_at = stop_index
			# Stand the real camera where the walk is, then render from there: the still
			# is of the stop, not of wherever the orbit rig was last left.
			director.apply_to(_camera)
			var path: String = await _one_still(stop_index, stage)
			if path != "":
				taken.append(path)
		if not director.playing:
			break

	print("walk: %d stills written, %.1f s of walking" % [taken.size(), director.elapsed])
	print(director.describe())


## A route of four stops along the garden, built from the yard's own bounds rather than
## hard-coded, so it walks whatever garden is on the drawing.
func _build_route():
	var bounds: Rect2 = _director.yard.get_bounds()
	var mid_x: float = bounds.position.x + bounds.size.x * 0.5
	var mid_z: float = bounds.position.y + bounds.size.y * 0.5
	# The open side of the garden, and the line across it the camera is aimed at.
	var stand_z: float = mid_z + bounds.size.y * AT_FRONT
	var aim_z: float = mid_z - bounds.size.y * 0.18
	var route = RouteScript.new()
	var names: Array[String] = ["left", "centre left", "centre right", "right"]
	# Four places along the open side, evenly spread across the garden's width, each
	# looking across to the far side: the walker turns their head as they go.
	for index in names.size():
		var share: float = -1.0 + 2.0 * float(index) / float(names.size() - 1)
		var at := Vector3(mid_x + bounds.size.x * SPAN * share, EYE_M, stand_z)
		var aim := Vector3(mid_x - bounds.size.x * SWING * share, EYE_M, aim_z)
		route.add_stop(names[index], at, aim, DWELL_S)
	return route


## One still from where the camera is standing, which the director has already placed.
func _one_still(index: int, stage: Dictionary) -> String:
	var written: Array[String] = []
	var refused: Array[String] = []
	var on_written := func(path: String) -> void: written.append(path)
	var on_refused := func(reason: String) -> void: refused.append(reason)
	_director.still_written.connect(on_written)
	_director.still_failed.connect(on_refused)
	_director.render_still(STILL_SIZE)
	var waited := 0
	while written.is_empty() and refused.is_empty() and waited < WAIT_FRAMES:
		await get_tree().process_frame
		waited += 1
	_director.still_written.disconnect(on_written)
	_director.still_failed.disconnect(on_refused)
	if not refused.is_empty():
		print("  stop %d refused: %s" % [index + 1, refused[0]])
		return ""
	if written.is_empty():
		print("  stop %d: no still came back in %d frames" % [index + 1, WAIT_FRAMES])
		return ""
	var target := "%s/stop-%d.png" % [OUT_DIR, index + 1]
	DirAccess.copy_absolute(written[0], ProjectSettings.globalize_path(target))
	var at: Vector3 = stage["position"]
	print("  stop %d: still at (%.1f, %.1f, %.1f)" % [index + 1, at.x, at.y, at.z])
	return target