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


## The walk-through of whatever garden is on the drawing. The route shape lives in
## `WalkRoute.for_yard`, so the demo renders the very route the game walks.
func _build_route() -> WalkRoute:
	return RouteScript.for_yard(_director.yard.get_bounds())


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