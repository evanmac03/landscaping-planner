class_name PresentationDirector
extends Node3D
## Drives the client presentation: the camera, the light, the quality, the stills.
##
## Everything here is reversible. The director holds no design state and writes
## none; it records what it changed and puts it back, so a presentation can end
## mid-sentence and the designer's session is exactly as they left it. That is the
## whole reason it records *values* rather than a list of things to undo: a
## remembered value cannot be restored to the wrong thing.
##
## It talks to the rest of the game by signal rather than by reaching into it
## (`presentation_changed`, `still_written`), so the HUD can hide its own working
## furniture without this node knowing what furniture the HUD has.

## Presentation started or ended, so the UI can put the working tools away.
signal presentation_changed(active: bool)
## A still is about to be taken. Anything that must not appear in the picture
## hides itself on this, and shows itself again on `still_written`/`still_failed`.
signal still_beginning
## A still was written. The path is absolute and inside `user://`.
signal still_written(path: String)
## A still could not be made. The reason is for a status line, not a log.
signal still_failed(reason: String)
## Something worth saying that is neither a success nor a failure.
signal note(text: String)

const Tier := preload("res://scripts/vis/presentation_tier.gd")
const SunStudyScript := preload("res://scripts/vis/sun_study.gd")
const OrbitCameraScript := preload("res://scripts/vis/orbit_camera.gd")
const StillExporterScript := preload("res://scripts/vis/still_exporter.gd")
const SidecarScript := preload("res://scripts/vis/still_sidecar.gd")

## How tall the box is that "frame the yard" frames. A garden is a flat thing with
## a house in it, and framing the full height of the house would halve the plan's
## size on screen for no gain.
const YARD_BOX_HEIGHT_M := 6.0
## Pixels of drag per metre of ground when panning the rig sideways.
const TRUCK_PIXELS_PER_METRE := 60.0

@export var sun: DirectionalLight3D
@export var world_environment: WorldEnvironment
@export var orbit: OrbitCameraScript
@export var yard: Yard
@export var view_controller: ViewController
## The flat 2D plan's layer: hidden while presenting, because a presentation is a
## view of the garden and not of the drawing.
@export var plan_layer: CanvasLayer
## The 3D linework overlay: a working aid, hidden while presenting.
@export var draft_overlay: Node3D
## The scale a still is recorded at. Authored here rather than read from the
## document, because the document's own scale is a property of the *sheet*.
@export var plot_scale: float = 100.0

@export_group("Sun study")
## Degrees north. The one number that makes a shadow study mean anything.
@export var latitude: float = 44.6
## Day of the year, 1-366.
@export var day_of_year: int = 172
## Solar time in hours, 0-24. Noon is 12.0.
@export var hour: float = 16.0

var tier: int = Tier.WORKING

var _active: bool = false
var _restore: Array[Dictionary] = []
var _previous_camera: Camera3D = null
var _drag_button: int = MOUSE_BUTTON_NONE
var _exporter: StillExporterScript


func _ready() -> void:
	# The renderer is made here rather than placed in the scene: it exists only for
	# the duration of a shot, and a node that spends its life doing nothing is a
	# node somebody will eventually mistake for something that does.
	_exporter = StillExporterScript.new()
	_exporter.name = "StillExporter"
	add_child(_exporter)
	# The site's latitude comes off the drawing, so the shadows in a presentation agree
	# with the survey rather than with whatever this node happened to be set to. The
	# exported value stays as the fallback for a scene with no drawing behind it.
	var site: float = _site_latitude()
	if not is_zero_approx(site):
		latitude = site


## The latitude the drawing says the site is at, or 0 when there is no drawing to ask.
##
## Reached the same way `DerivedBuilder` reaches the document: through the view controller,
## which owns the drafting controller. A `0.0` answer means "no opinion" rather than "the
## equator", which is why it is a sentinel here and not a default.
func _site_latitude() -> float:
	if view_controller == null or not view_controller.has_method("draft_controller"):
		return 0.0
	var controller: Node = view_controller.draft_controller()
	if controller == null:
		return 0.0
	var drawing = controller.document
	if drawing == null:
		return 0.0
	return float(drawing.site_latitude)


func is_active() -> bool:
	return _active


## Enter the presentation. Returns false when there is nothing to present with.
func begin(new_tier: int = Tier.PRESENTATION) -> bool:
	if _active:
		return true
	if orbit == null or orbit.camera == null:
		# A note rather than an error: this is a state the GUI can put the application
		# into - pressing Present in a scene with no rig - so it has to be reportable
		# without a log error, and the panel is where the person who pressed it reads
		# the answer.
		note.emit("There is no presentation camera to present with.")
		return false
	_active = true
	tier = new_tier

	# Everything that can change is recorded *before* it changes, once.
	_remember_once(sun, "directional_shadow_max_distance")
	_remember_once(sun, "shadow_blur")
	if world_environment != null and world_environment.environment != null:
		_remember_once(world_environment.environment, "ssao_enabled")
		_remember_once(world_environment.environment, "ssao_radius")
		_remember_once(world_environment.environment, "ssao_intensity")
	_remember_once(plan_layer, "visible")
	_remember_once(draft_overlay, "visible")
	_apply_tier()

	# The keyboard belongs to the presentation, so the view controller is taken out
	# of the input and process loops entirely rather than being asked to ignore
	# events. Its own two flags are recorded, so putting it back cannot put it back
	# wrong.
	if view_controller != null:
		_restore.append({
			"target": view_controller, "property": "_presentation_suspended",
			"value": false, "flag": true,
		})
		_suspend_controller(true)

	# Hide the working surfaces. Recorded, so a session that was already in the flat
	# plan returns to the flat plan.
	#
	# Assigned under an `if` rather than behind a null-safe expression: `x.y = ...`
	# evaluates `x.y` as the assignment's target before the right-hand side, so a
	# ternary guarding the *value* still reads the property off a null node.
	if plan_layer != null:
		plan_layer.visible = false
	if draft_overlay != null:
		draft_overlay.visible = false

	_previous_camera = get_viewport().get_camera_3d()
	orbit.camera.current = true
	# Entering always frames the garden, so the presentation starts from the same
	# view every time rather than from wherever the designer's mouse left it.
	frame_yard()
	presentation_changed.emit(true)
	return true


## Leave the presentation, putting back everything that was changed.
func end() -> void:
	if not _active:
		return
	_active = false
	_drag_button = MOUSE_BUTTON_NONE
	# Reversed, so a property recorded twice would be restored in the order it was
	# set. Nothing records twice (`_remember_once`), but the order is the honest one
	# to unwind in either way.
	for index in range(_restore.size() - 1, -1, -1):
		var change: Dictionary = _restore[index]
		if bool(change.get("flag", false)):
			_restore_flag(change)
			continue
		# `set` rather than a typed assignment: the recorded target is an Object and
		# the property is a name, which is the only way to undo a heterogeneous list
		# of changes without a branch per property.
		change["target"].set(String(change["property"]), change["value"])
	_restore.clear()
	if _previous_camera != null and is_instance_valid(_previous_camera):
		_previous_camera.current = true
	_previous_camera = null
	presentation_changed.emit(false)


## Set the quality tier, whether or not a presentation is running. Choosing the
## budget and entering the presentation are separate acts: a designer may want to
## see what "Still" looks like before committing to a client walk-through.
func set_tier(new_tier: int) -> void:
	tier = new_tier
	_apply_tier()


## Aim the sun. Returns false when it is below the horizon, which is reported
## rather than clamped - a garden at night is a decision, not an accident.
func apply_sun(new_latitude: float, new_day: int, new_hour: float) -> bool:
	latitude = new_latitude
	day_of_year = new_day
	hour = new_hour
	if sun == null:
		return false
	if not SunStudyScript.apply(sun, latitude, day_of_year, hour):
		note.emit("The sun is below the horizon at %.1f h." % hour)
		return false
	note.emit(SunStudyScript.describe(latitude, day_of_year, hour))
	return true


## Frame the fenced property, using the yard's own bounds so the picture and the
## plan agree about what "the garden" is.
func frame_yard() -> void:
	if orbit == null or yard == null:
		return
	var bounds: Rect2 = yard.get_bounds()
	var box := AABB(
		Vector3(bounds.position.x, 0.0, bounds.position.y),
		Vector3(bounds.size.x, YARD_BOX_HEIGHT_M, bounds.size.y)
	)
	# A little air around the fence, so the picture does not end at a post.
	orbit.frame(box, 0.12)


## Render a proposal still of the current view and write it, with its record.
##
## Asynchronous: it waits for real frames, and it says what happened by signal, so
## the caller is a status line rather than a function that blocks the frame it was
## pressed in.
func render_still(output_size: Vector2i) -> void:
	if _exporter == null:
		still_failed.emit("there is no renderer to take a still with.")
		return
	if orbit == null or orbit.camera == null:
		still_failed.emit("there is no camera to render from.")
		return
	still_beginning.emit()
	var record: Dictionary = SidecarScript.record(
		"3D presentation",
		output_size,
		StillExporterScript.SUPERSAMPLE,
		Tier.name_of(tier),
		SunStudyScript.position(latitude, day_of_year, hour),
		orbit.state() if orbit != null else {},
		plot_scale,
		_entity_count()
	)
	var path: String = await _exporter.render_still(
		[orbit.camera] as Array[Node],
		output_size,
		StillExporterScript.timestamp_name("presentation"),
		record
	)
	if path == "":
		still_failed.emit("the render came back blank or empty.")
	else:
		still_written.emit(path)


## The sun's current position, for a status line or a saved view.
func sun_settings() -> Dictionary:
	return SunStudyScript.position(latitude, day_of_year, hour)


func _apply_tier() -> void:
	var look: Dictionary = Tier.look(tier)
	if sun != null:
		sun.directional_shadow_max_distance = float(look["shadow_max_distance"])
		sun.shadow_blur = float(look["shadow_blur"])
	if world_environment == null or world_environment.environment == null:
		return
	var environment: Environment = world_environment.environment
	environment.ssao_enabled = bool(look["ssao"])
	environment.ssao_radius = float(look["ssao_radius"])
	environment.ssao_intensity = float(look["ssao_intensity"])


## Record a property's value the first time it is about to be changed. Recording
## once is what makes a second tier change restore the *original* value rather than
## the last one.
func _remember_once(target: Object, property: String) -> void:
	if target == null:
		return
	for change in _restore:
		if change["target"] == target and String(change["property"]) == property:
			return
	_restore.append({
		"target": target, "property": property, "value": target.get(property),
	})


## Record a flag that is undone by a function rather than by `set`. The view
## controller's two process flags are the case: restoring them without returning
## the controller to its previous state would be recording the wrong thing.
##
## The entry is not read: what has to be undone is the suspension itself, and the
## controller's own previous flags are held in its metadata.
func _restore_flag(_change: Dictionary) -> void:
	if view_controller == null:
		return
	_suspend_controller(false)


## Take the view controller's input and process loops, or give them back.
##
## Suspending it is what stops a stray Q, Tab or Enter from re-framing the view
## out from under a presenter - and it takes the drafting tools out of reach
## entirely, which is the point: presentation must not be able to edit the design.
func _suspend_controller(suspend: bool) -> void:
	if view_controller == null:
		return
	var flag: String = "_presentation_suspended"
	if suspend:
		# What it currently has, so a controller that was already idle stays idle.
		view_controller.set_meta(flag, {
			"process": view_controller.is_processing(),
			"input": view_controller.is_processing_unhandled_input(),
		})
		view_controller.set_process(false)
		view_controller.set_process_unhandled_input(false)
		return
	var previous: Variant = view_controller.get_meta(flag, {})
	view_controller.set_process(bool(previous.get("process", true)))
	view_controller.set_process_unhandled_input(bool(previous.get("input", true)))
	view_controller.remove_meta(flag)


func _entity_count() -> int:
	if view_controller == null:
		return 0
	var controller = view_controller.draft_controller()
	if controller == null or controller.document == null:
		return 0
	return int(controller.document.count())


## Metres of ground per pixel of drag at the pivot, so panning the rig feels the
## same at every distance: far out, a drag moves a lot of garden; up close, a
## little.
func _metres_per_pixel() -> float:
	if orbit == null or orbit.camera == null:
		return 0.01
	var viewport_height: float = get_viewport().get_visible_rect().size.y
	if viewport_height <= 0.0:
		return 0.01
	return (
		2.0 * orbit.distance() * tan(deg_to_rad(orbit.camera.fov * 0.5))
	) / viewport_height


func _unhandled_input(event: InputEvent) -> void:
	if not _active or orbit == null:
		return
	# The wheel dollies, using the actions the working views already dolly with, so
	# the wheel means the same thing in both.
	if event.is_action_pressed(&"zoom_in"):
		orbit.dolly(1.0)
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed(&"zoom_out"):
		orbit.dolly(-1.0)
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if button.button_index == MOUSE_BUTTON_RIGHT or button.button_index == MOUSE_BUTTON_MIDDLE:
			_drag_button = button.button_index if button.pressed else MOUSE_BUTTON_NONE
			get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseMotion and _drag_button != MOUSE_BUTTON_NONE:
		var motion := event as InputEventMouseMotion
		if _drag_button == MOUSE_BUTTON_RIGHT:
			# Right-drag walks around the garden, which is the gesture a client is
			# going to make.
			orbit.orbit(motion.relative)
		else:
			# Middle-drag slides the view sideways. Screen down is ground south, and
			# screen right is ground east, which is the same mapping the plan uses.
			orbit.truck(
				Vector2(motion.relative.x, motion.relative.y) * _metres_per_pixel()
			)
		get_viewport().set_input_as_handled()