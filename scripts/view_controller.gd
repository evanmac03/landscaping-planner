class_name ViewController
extends Node
## Views the one 3D world three ways, and moves design objects from any of them.
##
## There is a single 3D scene; only the way it is viewed changes:
##
##  - PLAN_2D     a flat schematic plan, drawn in 2D from that same geometry
##  - OVERHEAD_3D the same ground through an orthographic 3D camera
##  - GROUND      first person, walking the design at eye height
##
## The two overhead views deliberately share one focus and one zoom, so switching
## between them keeps you looking at exactly the same patch of ground, and the
## change reads as the drawing flattening into a render rather than as a jump
## somewhere else. Editing works identically in both: a drag picks the nearest
## design object by its on-screen footprint and writes straight to its 3D
## transform, so there is no per-view copy of anything to keep in step.
##
## The flight between overhead and ground is the trick from before: a perspective
## camera high up with a narrow field of view frames almost exactly what an
## orthographic camera frames, so the projection can be swapped on the first frame
## of the flight without the change being visible (see ViewMath). The tween then
## descends, pitches level and widens the view until the plan has become a view
## from the ground.
##
## Layout requirement: in the main scene, the Player node must appear before this
## node so the player's own _ready() has run before the first pose is applied.

enum ViewMode {
	PLAN_2D,     ## Flat schematic plan, drawn in 2D.
	OVERHEAD_3D, ## Orthographic 3D camera looking straight down.
	GROUND,      ## First person, walking the design at eye height.
}

## Guards the "run this next" slot; an enum value or NO_PENDING.
const NO_PENDING := -1

const DraftToolScript := preload("res://scripts/draft/draft_tool.gd")
const DraftControllerScript := preload("res://scripts/draft/draft_controller.gd")
const PlantSuitabilityScript := preload("res://scripts/plant_suitability.gd")

signal view_mode_changed(mode: ViewMode)
signal transition_started(to_ground: bool)
signal transition_finished(to_ground: bool)
## Planting was armed or put away, so a menu can say which plant a click will put down.
signal planting_changed(species_id: StringName)

@export var flight_camera: Camera3D
@export var player: PlanPlayer
## The landscaping content, used to centre the plan view. Optional.
@export var yard: Node3D
## Holds the flat 2D plan. Shown only in PLAN_2D.
@export var plan_layer: CanvasLayer
@export var plan_canvas: PlanCanvas
## Flat ring drawn under the hovered or dragged object in the 3D overhead view.
@export var selection_ring: Node3D

@export_group("Overhead view")
## Metres of world visible across the overhead view's height. Shared by the
## orthographic camera and the 2D plan, so the two always frame the same patch.
## Overwritten by fit_plan_to_yard() on start.
@export var plan_size: float = 23.0
## XZ extent of the design, used to frame the overhead view on start.
@export var yard_extent: Vector2 = Vector2(28.0, 20.0)
## Fraction of the screen left as margin around the design when fitting.
@export var fit_margin: float = 1.18
## Altitude of the plan camera. Must clear everything in the scene and stay well
## inside the camera's far plane.
@export var plan_height: float = 60.0
@export var plan_size_min: float = 6.0
@export var plan_size_max: float = 140.0
## Multiplier applied per mouse-wheel notch.
@export var zoom_step: float = 1.12
## Pan metres per second, as a fraction of the visible height per second, so
## panning feels the same at every zoom level.
@export var pan_rate: float = 0.85
## How far the plan view may be panned, in world XZ.
@export var pan_bounds: Rect2 = Rect2(-45.0, -35.0, 90.0, 70.0)

@export_group("Editing")
## Space a design object may be dragged into, in world XZ. Kept just inside the
## fence so nothing can be pushed through it.
@export var edit_bounds: Rect2 = Rect2(-13.25, -9.25, 26.5, 18.5)
## Extra screen-space slack around an object's own on-screen size when picking,
## which makes small props comfortable to grab.
@export var pick_slack: float = 10.0
## Cross-fade time between the two overhead views.
@export var crossfade_time: float = 0.28

@export_group("Flight")
@export var flight_time: float = 1.7
## Field of view the flight ends on, in the player's camera.
@export var ground_fov: float = 70.0
## Where the flight may set the player down, in world XZ. Kept inside the fence.
@export var land_bounds: Rect2 = Rect2(-12.4, -8.4, 24.8, 16.8)
## The flight lands this far behind whatever you were examining, facing it.
@export var land_back_off: float = 4.0
## Height of the ground the player stands on.
@export var floor_y: float = 0.0
## Eye height at the end of the descent. Must match PlanPlayer.eye_height.
@export var land_eye_height: float = 1.7

var mode: ViewMode = ViewMode.OVERHEAD_3D:
	set(value):
		if mode == value:
			return
		mode = value
		view_mode_changed.emit(mode)

## World XZ point at the centre of the overhead view. Shared by both overhead
## views, and where the ground flight aims.
var plan_focus: Vector2 = Vector2.ZERO

var _tween: Tween
var _fade: Tween
var _transitioning: bool = false
var _fading: bool = false
var _panning: bool = false
## A view to move to once the current transition has settled.
var _pending: int = NO_PENDING

var _grabbed: Node3D = null
## Screen-space vector from the grabbed object's centre to the cursor, so picking
## an object up never yanks it to centre itself under the pointer.
var _grab_offset: Vector2 = Vector2.ZERO
## Where the cursor was on the previous motion event of a drag.
var _drag_cursor: Vector2 = Vector2.ZERO
var _hovered: Node3D = null
var _hand_cursor: bool = false

## The drafting controller, when the scene has one. Input is routed from here
## because this node already owns the overhead mouse handling and knows which
## view you are looking at.
var _draft = null

## The catalogue a planted species is looked up in, and the species a click on the plan will put
## down. Held here because this node is the one that already knows where a screen point is on the
## ground; the browser knows what a plant *is* and hands it over rather than reaching in.
var plant_catalogue: PlantCatalogue = null
var planting_species: StringName = &""

## What the last verdict about the plant in hand said: `{verdict, ok, certain, colour, findings,
## summary, label, species, place, conditions}` from `PlantSuitability`. Empty until a plant is armed
## and the cursor is over the plan.
##
## Kept rather than only pushed at the canvas, because a verdict is a thing a person can ask about -
## the state line says which plant is in hand, and the ring says whether it belongs here.
var planting_verdict: Dictionary = {}

var _placeable_cache: Array[Node3D] = []
var _placeable_cache_ready: bool = false


func _ready() -> void:
	if flight_camera == null or player == null:
		push_error("ViewController: flight_camera and player must both be assigned.")
		set_process(false)
		set_process_unhandled_input(false)
		return
	if plan_canvas != null:
		plan_canvas.rebind(yard)
		plan_canvas.modulate.a = 0.0
	if plan_layer != null:
		plan_layer.visible = false
	_draft = get_node_or_null(^"../DraftController")
	_set_viewport_3d(true)
	# The plan's scale is derived from the viewport height, so it has to be
	# re-applied when the window changes size or the two overhead views drift
	# apart (the 3D camera does not care about the viewport size, the plan does).
	get_viewport().size_changed.connect(_on_viewport_resized)
	if yard != null:
		plan_focus = Vector2(yard.global_position.x, yard.global_position.z)
	fit_plan_to_yard()
	flight_camera.current = true
	player.set_active(false)
	player.release_mouse()
	view_mode_changed.emit(mode)


func is_transitioning() -> bool:
	return _transitioning or _fading


func is_overhead() -> bool:
	return mode != ViewMode.GROUND


## The design objects the planner lets you select and move.
func placeables() -> Array[Node3D]:
	if not _placeable_cache_ready:
		_placeable_cache.clear()
		for node in get_tree().get_nodes_in_group(Yard.PLACEABLE_GROUP):
			if node is Node3D and is_instance_valid(node):
				_placeable_cache.append(node)
		_placeable_cache_ready = true
	return _placeable_cache


## Zoom so the design fits the plan view with a margin. Safe to call any time.
func fit_plan_to_yard() -> void:
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	var aspect: float = viewport_size.x / maxf(viewport_size.y, 1.0)
	plan_size = clampf(
		maxf(yard_extent.y, yard_extent.x / maxf(aspect, 0.001)) * fit_margin,
		plan_size_min,
		plan_size_max
	)
	plan_focus = ViewMath.clamp_to_rect(plan_focus, pan_bounds)
	_apply_overhead_view()


# --- view control -----------------------------------------------------------------


## Swap between the flat 2D plan and the 3D overhead view. From the ground it goes
## to the plan, flying up through the overhead framing on the way, because the key
## is the one that gets you back to drawing and the plan is where drawing happens.
func toggle_overhead() -> void:
	_go(ViewMode.PLAN_2D if mode != ViewMode.PLAN_2D else ViewMode.OVERHEAD_3D)


## Toggle the ground-level view.
func toggle_ground() -> void:
	_go(ViewMode.OVERHEAD_3D if mode == ViewMode.GROUND else ViewMode.GROUND)


## Go to a named view.
##
## The toggle above is what one key needs; a menu lists the places you can be, and asking for the
## place you are already in is not a request to leave it. Without the guard, choosing the current
## view from a menu would start a flight to where it already is, which reads as a flicker and a
## wasted second.
func show_mode(target: ViewMode) -> void:
	if target != mode:
		_go(target)


## Move to a view, queueing the request if a transition is already under way.
func _go(target: ViewMode) -> void:
	if _transitioning or _fading:
		_pending = target
		return
	if target == ViewMode.GROUND:
		if mode == ViewMode.PLAN_2D:
			# No 3D is being rendered behind the flat plan, so step back to the 3D
			# overhead view first and dive once that has settled.
			_pending = ViewMode.GROUND
			_switch_overhead(ViewMode.OVERHEAD_3D)
		else:
			fly_to_ground()
	elif mode == ViewMode.GROUND:
		_pending = target
		fly_to_plan()
	else:
		_switch_overhead(target)


func _dispatch_pending() -> void:
	if _pending == NO_PENDING:
		return
	var target: int = _pending
	_pending = NO_PENDING
	_go(target)


## Cross-fade between the flat plan and the 3D overhead render.
func _switch_overhead(target: ViewMode) -> void:
	if target == mode or plan_layer == null or plan_canvas == null:
		return
	var to_2d: bool = target == ViewMode.PLAN_2D
	_clear_selection()
	mode = target
	_apply_overhead_view()

	# Both projections must be rendered while the plan fades, so the dissolve has
	# something to dissolve into. CanvasLayer has no modulate of its own, so the
	# fade lives on the canvas node underneath it.
	_set_viewport_3d(true)
	plan_layer.visible = true
	plan_canvas.modulate.a = 0.0 if to_2d else 1.0
	_fading = true
	if _fade != null and _fade.is_valid():
		_fade.kill()
	_fade = create_tween().bind_node(self)
	_fade.tween_property(plan_canvas, "modulate:a", 1.0 if to_2d else 0.0, crossfade_time)
	_fade.tween_callback(_on_faded.bind(to_2d))


func _on_faded(to_2d: bool) -> void:
	_fading = false
	if plan_layer != null:
		plan_layer.visible = to_2d
	if plan_canvas != null:
		plan_canvas.modulate.a = 1.0 if to_2d else 0.0
	# Nothing 3D is visible behind the flat plan, so stop rendering it.
	_set_viewport_3d(not to_2d)
	_dispatch_pending()


func _set_viewport_3d(enabled: bool) -> void:
	var viewport: Viewport = get_viewport()
	if viewport != null:
		viewport.disable_3d = not enabled


## Keeps the flat plan's scale tied to the new window size.
func _on_viewport_resized() -> void:
	if get_viewport().disable_3d:
		return
	_apply_overhead_view()


## Dive from the plan view down to eye level. Reversed by fly_to_plan().
func fly_to_ground() -> void:
	if _transitioning or _fading or mode == ViewMode.GROUND:
		return
	_transitioning = true
	transition_started.emit(true)
	_clear_selection()

	# Land a little behind whatever you were examining and face it, so arriving
	# at ground level frames the part of the design you were just looking at.
	# World -Z is "up" the plan view, which is the direction we land facing.
	var landing: Vector2 = ViewMath.clamp_to_rect(
		plan_focus + Vector2(0.0, land_back_off), land_bounds
	)
	var landing_yaw: float = 0.0
	var matched_fov: float = ViewMath.match_fov(plan_size, plan_height)

	# First frame of the flight: identical framing to the plan view, but in
	# perspective. Switching projection here is invisible because at plan_height
	# this field of view frames exactly what the orthographic camera did.
	flight_camera.global_position = Vector3(plan_focus.x, plan_height, plan_focus.y)
	flight_camera.global_rotation = Vector3(-PI * 0.5, 0.0, 0.0)
	flight_camera.fov = matched_fov
	flight_camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	flight_camera.current = true
	player.set_active(false)
	player.release_mouse()

	_kill_tween()
	_tween = create_tween().set_parallel(true).bind_node(self)
	_tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	_tween.tween_property(
		flight_camera, "global_position",
		Vector3(landing.x, floor_y + land_eye_height, landing.y), flight_time
	)
	# Hold the downward tilt for most of the descent and only level out on
	# arrival (EASE_IN keeps the eased value low early), so the design stays
	# framed the whole way instead of the camera staring off over the boundary.
	_tween.tween_property(
		flight_camera, "global_rotation",
		Vector3(0.0, landing_yaw, 0.0), flight_time
	).set_ease(Tween.EASE_IN)
	_tween.tween_property(flight_camera, "fov", ground_fov, flight_time)
	_tween.chain().tween_callback(_on_landed)


## Rise from eye level back to the plan view. Reverses fly_to_ground().
func fly_to_plan() -> void:
	if _transitioning or _fading or mode == ViewMode.OVERHEAD_3D:
		return
	_transitioning = true
	transition_started.emit(false)

	# Re-centre the plan on where the player is standing so going back up keeps
	# your place in the design.
	plan_focus = ViewMath.clamp_to_rect(
		Vector2(player.global_position.x, player.global_position.z), pan_bounds
	)

	# First frame of the flight: exactly what the player is looking at. The
	# flight camera takes over the player's pose, so the handover is invisible.
	# Wrap the yaw so the tween never unwinds accumulated full turns.
	flight_camera.global_position = player.eye_position()
	flight_camera.global_rotation = Vector3(
		player.get_pitch(), ViewMath.wrap_angle(player.get_yaw()), 0.0
	)
	flight_camera.fov = ground_fov
	flight_camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	flight_camera.current = true
	player.set_active(false)
	player.release_mouse()

	_kill_tween()
	_tween = create_tween().set_parallel(true).bind_node(self)
	_tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	_tween.tween_property(
		flight_camera, "global_position",
		Vector3(plan_focus.x, plan_height, plan_focus.y), flight_time
	)
	# Mirror of the descent: tilt down early (EASE_OUT raises the eased value
	# quickly), then spend the climb looking at the design.
	_tween.tween_property(
		flight_camera, "global_rotation",
		Vector3(-PI * 0.5, 0.0, 0.0), flight_time
	).set_ease(Tween.EASE_OUT)
	_tween.tween_property(
		flight_camera, "fov", ViewMath.match_fov(plan_size, plan_height), flight_time
	)
	_tween.chain().tween_callback(_on_arrived_at_plan)


## Multiply the plan zoom. Pass `pivot_pixel` (usually the mouse position) to keep
## the world point under that pixel fixed, the way a map tool should zoom.
func zoom_by(factor: float, pivot_pixel: Vector2 = Vector2.INF) -> void:
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	var old_size: float = plan_size
	var new_size: float = clampf(plan_size * factor, plan_size_min, plan_size_max)
	if is_equal_approx(old_size, new_size):
		return
	plan_size = new_size
	if pivot_pixel != Vector2.INF:
		var offset: Vector2 = pivot_pixel - viewport_size * 0.5
		# Screen +x is world +x and screen +y is world +z, because the plan camera
		# looks down with its up vector along world -Z.
		var anchor: Vector2 = plan_focus + offset * (old_size / maxf(viewport_size.y, 1.0))
		plan_focus = anchor - offset * (new_size / maxf(viewport_size.y, 1.0))
		plan_focus = ViewMath.clamp_to_rect(plan_focus, pan_bounds)
	_apply_overhead_view()


## Points both overhead views at the same patch of ground: the orthographic 3D
## camera and the 2D plan are driven from one focus and one zoom, which is what
## lets you switch between them without the subject moving.
func _apply_overhead_view() -> void:
	if flight_camera != null:
		flight_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
		flight_camera.size = plan_size
		flight_camera.global_position = Vector3(plan_focus.x, plan_height, plan_focus.y)
		# Looking straight down with the camera's up vector along world -Z, so
		# world -Z reads as "up" on screen, the way a landscape plan is drawn.
		flight_camera.global_rotation = Vector3(-PI * 0.5, 0.0, 0.0)
		# Keep the perspective field of view pre-matched so the projection swap on
		# the first frame of the flight needs no last-minute change.
		flight_camera.fov = ViewMath.match_fov(plan_size, plan_height)
	if plan_canvas != null:
		plan_canvas.apply_view(plan_focus, plan_size, get_viewport().get_visible_rect().size)


func _on_landed() -> void:
	var spot: Vector2 = Vector2(
		flight_camera.global_position.x, flight_camera.global_position.z
	)
	# Snap the player to exactly where the camera came to rest -- same spot, eye
	# height, yaw and pitch -- so handing the camera over shows no jump at all.
	player.place(
		spot,
		floor_y,
		flight_camera.global_rotation.y,
		flight_camera.global_rotation.x
	)
	player.camera.current = true
	player.set_active(true)
	player.capture_mouse()
	_set_cursor_hand(false)
	_transitioning = false
	mode = ViewMode.GROUND
	transition_finished.emit(true)
	_dispatch_pending()


func _on_arrived_at_plan() -> void:
	# The matching was exact, so swapping to the orthographic projection here is
	# invisible: same position, same rotation, same framing.
	_apply_overhead_view()
	flight_camera.current = true
	player.set_active(false)
	_transitioning = false
	mode = ViewMode.OVERHEAD_3D
	transition_finished.emit(false)
	_dispatch_pending()


func _kill_tween() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = null


# --- picking and moving -----------------------------------------------------------


## Take hold of the design object under `screen`, if there is one. A single
## implementation serves both overhead views: they differ only in how a world
## point maps to the screen, and both write straight to the object's transform.
func begin_move(screen: Vector2) -> void:
	var node: Node3D = nearest_placeable(screen)
	if node == null:
		return
	_grabbed = node
	var centre: Vector2 = _world_to_screen(Vector3(
		node.global_position.x, floor_y, node.global_position.z
	))
	_grab_offset = centre - screen
	_drag_cursor = screen
	if plan_canvas != null:
		plan_canvas.grabbed = node
	_refresh_selection_ring()


func update_move(screen: Vector2) -> void:
	if _grabbed == null:
		return
	var world: Vector2 = _screen_to_world(screen + _grab_offset)
	world = ViewMath.clamp_to_rect(world, edit_bounds)
	var position: Vector3 = _grabbed.global_position
	_grabbed.global_position = Vector3(world.x, position.y, world.y)
	_refresh_selection_ring()


func end_move() -> void:
	if _grabbed == null:
		return
	_grabbed = null
	if plan_canvas != null:
		plan_canvas.grabbed = null
	_refresh_selection_ring()


func is_moving() -> bool:
	return _grabbed != null


## The design object whose on-screen footprint contains `screen`, preferring the
## closest. Measured in screen space, so picking feels the same at every zoom.
func nearest_placeable(screen: Vector2) -> Node3D:
	var best: Node3D = null
	var best_distance: float = INF
	var pixels_per_metre: float = _pixels_per_metre()
	for node: Node3D in placeables():
		var centre: Vector2 = _world_to_screen(
			Vector3(node.global_position.x, floor_y, node.global_position.z)
		)
		var reach: float = PlanStyle.footprint_radius(node) * pixels_per_metre + pick_slack
		var distance: float = centre.distance_to(screen)
		if distance <= reach and distance < best_distance:
			best = node
			best_distance = distance
	return best


func _pixels_per_metre() -> float:
	if mode == ViewMode.PLAN_2D and plan_canvas != null:
		return plan_canvas.pixels_per_metre
	return get_viewport().get_visible_rect().size.y / maxf(plan_size, 0.001)


func _world_to_screen(world: Vector3) -> Vector2:
	if mode == ViewMode.PLAN_2D and plan_canvas != null:
		return plan_canvas.world_to_screen(world)
	return flight_camera.unproject_position(world)


func _screen_to_world(screen: Vector2) -> Vector2:
	if mode == ViewMode.PLAN_2D and plan_canvas != null:
		return plan_canvas.screen_to_world(screen)
	var origin: Vector3 = flight_camera.project_ray_origin(screen)
	var direction: Vector3 = flight_camera.project_ray_normal(screen)
	if absf(direction.y) < 0.00001:
		return Vector2(origin.x, origin.z)
	var distance: float = (floor_y - origin.y) / direction.y
	var hit: Vector3 = origin + direction * distance
	return Vector2(hit.x, hit.z)


func _clear_selection() -> void:
	_grabbed = null
	_hovered = null
	if plan_canvas != null:
		plan_canvas.grabbed = null
		plan_canvas.hovered = null
	_set_cursor_hand(false)
	_refresh_selection_ring()


## Tracks what is under the cursor and mirrors it into the plan canvas, the 3D
## selection ring and the mouse cursor, so all three agree on what a click picks.
func _update_hover() -> void:
	if is_moving():
		return
	var found: Node3D = nearest_placeable(get_viewport().get_mouse_position())
	if found == _hovered:
		return
	_hovered = found
	if plan_canvas != null:
		plan_canvas.hovered = found
	_set_cursor_hand(found != null)
	_refresh_selection_ring()


func _set_cursor_hand(wants_hand: bool) -> void:
	if wants_hand == _hand_cursor:
		return
	_hand_cursor = wants_hand
	Input.set_default_cursor_shape(
		Input.CURSOR_POINTING_HAND if wants_hand else Input.CURSOR_ARROW
	)


func _refresh_selection_ring() -> void:
	if selection_ring == null:
		return
	var node: Node3D = _grabbed if _grabbed != null else _hovered
	selection_ring.visible = node != null and mode == ViewMode.OVERHEAD_3D
	if not selection_ring.visible:
		return
	var radius: float = PlanStyle.footprint_radius(node) + 0.35
	selection_ring.global_position = Vector3(
		node.global_position.x, floor_y + 0.05, node.global_position.z
	)
	# The ring mesh is authored at radius 1, so the footprint sizes it directly.
	selection_ring.scale = Vector3.ONE * radius


func _process(delta: float) -> void:
	if _transitioning or _fading or mode == ViewMode.GROUND:
		return

	var zoom_axis: float = Input.get_axis("zoom_out", "zoom_in")
	if absf(zoom_axis) > 0.001:
		zoom_by(1.0 - zoom_axis * 1.8 * delta, get_viewport().get_mouse_position())

	# WASD pans: forward moves the view up the screen, which is world -Z. Not
	# while a tool is armed: D is arm-drawing and also move-right, and the tool
	# keys are on the number row, so the keyboard belongs to the drawing.
	# Read through MoveInput, so a command on Ctrl does not also pan.
	var stick: Vector2 = Vector2.ZERO
	if _draft == null or not _draft.drawing:
		stick = MoveInput.stick()
	if stick.length_squared() > 0.0:
		plan_focus += stick * (plan_size * pan_rate * delta)
		plan_focus = ViewMath.clamp_to_rect(plan_focus, pan_bounds)
		_apply_overhead_view()

	# While a tool is armed the hovered-object ring would be a lie: the click is
	# going to the drawing, not to whatever plant is underneath it.
	if _draft == null or not _draft.drawing:
		_update_hover()

	# The plant in hand is judged against the ground every frame rather than on mouse motion: the
	# cursor is in the same place after a pan, a zoom or a menu entry has just changed what the
	# ground is, and all three change the answer. Reading the position here also means the verdict
	# cannot go stale while the mouse is still.
	if is_planting():
		_update_plant_ghost()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_view"):
		toggle_overhead()
		get_viewport().set_input_as_handled()
		return

	if event.is_action_pressed("toggle_ground"):
		toggle_ground()
		get_viewport().set_input_as_handled()
		return

	if mode == ViewMode.GROUND or _transitioning or _fading:
		return

	# Planting owns the left button while it is armed, and it comes before the drawing tools because
	# arming a plant puts the tools away: a click that put a shrub down *and* started a polyline
	# would be one click doing two things.
	if is_planting():
		if event.is_action_pressed("draft_cancel"):
			stop_planting()
			get_viewport().set_input_as_handled()
			return
		if event is InputEventMouseButton:
			var planting_click: InputEventMouseButton = event
			if planting_click.pressed and planting_click.button_index == MOUSE_BUTTON_LEFT:
				plant_at(planting_click.position)
				get_viewport().set_input_as_handled()
				return

	if _draft != null:
		if event.is_action_pressed("draft_mode"):
			_draft.toggle_drawing()
			if _draft.drawing and plan_canvas != null:
				plan_canvas.hovered = null
			get_viewport().set_input_as_handled()
			return
		# Plotting is not a tool, so it does not need drawing to be armed.
		if event.is_action_pressed("draft_plot"):
			_draft.plot()
			get_viewport().set_input_as_handled()
			return
		# Nor is the standard a dimension is drawn to: it belongs to the drawing,
		# not to the shape being picked.
		if event.is_action_pressed("draft_dimension_style"):
			_draft.cycle_dimension_style()
			get_viewport().set_input_as_handled()
			return
		if _draft.drawing and _handle_drafting(event):
			return

	if event.is_action_pressed("edit_offset"):
		_arm_edit(DraftControllerScript.EditKind.OFFSET)
		return
	if event.is_action_pressed("edit_trim"):
		_arm_edit(DraftControllerScript.EditKind.TRIM)
		return
	if event.is_action_pressed("edit_extend"):
		_arm_edit(DraftControllerScript.EditKind.EXTEND)
		return
	if event.is_action_pressed("edit_fillet"):
		_arm_edit(DraftControllerScript.EditKind.FILLET)
		return
	if event.is_action_pressed("edit_erase"):
		_arm_edit(DraftControllerScript.EditKind.ERASE)
		return
	if event.is_action_pressed("edit_rotate"):
		_arm_edit(DraftControllerScript.EditKind.ROTATE)
		return

	if event.is_action_pressed("fit_view"):
		fit_plan_to_yard()
		get_viewport().set_input_as_handled()
		return

	if event is InputEventMouseButton:
		var button: InputEventMouseButton = event
		match button.button_index:
			MOUSE_BUTTON_LEFT:
				if button.pressed:
					begin_move(button.position)
				else:
					end_move()
			MOUSE_BUTTON_RIGHT:
				_panning = button.pressed
			MOUSE_BUTTON_WHEEL_UP:
				if button.pressed:
					zoom_by(1.0 / zoom_step, button.position)
			MOUSE_BUTTON_WHEEL_DOWN:
				if button.pressed:
					zoom_by(zoom_step, button.position)
	elif event is InputEventMouseMotion:
		var motion: InputEventMouseMotion = event
		if is_moving():
			# A real mouse always reports an absolute position. Captured input and
			# automation sometimes report only a delta, which would leave the drag
			# pinned in place, so accumulate the delta in that case.
			var cursor: Vector2 = motion.position
			if cursor.is_equal_approx(_drag_cursor) and not motion.relative.is_zero_approx():
				cursor += motion.relative
			_drag_cursor = cursor
			update_move(cursor)
		elif _panning:
			# Drag the design with the cursor: the point under the mouse stays put.
			plan_focus -= motion.relative * (plan_size / maxf(
				get_viewport().get_visible_rect().size.y, 1.0
			))
			plan_focus = ViewMath.clamp_to_rect(plan_focus, pan_bounds)
			_apply_overhead_view()


# --- planting -------------------------------------------------------------------------


## Whether a click on the plan will put a plant down.
func is_planting() -> bool:
	return not planting_species.is_empty()


## Arm a species, so the next click on the plan plants one of it.
##
## Each placed plant is an ordinary design object the moment it lands - in the yard's planting
## subtree and in the `placeable` group - so this node does not need to know anything else about it:
## picking, dragging, the plan symbol and the 3D model all keep working without a second code path.
func arm_planting(catalogue: PlantCatalogue, species_id: StringName) -> bool:
	if catalogue == null or not catalogue.has(species_id):
		return false
	plant_catalogue = catalogue
	planting_species = species_id
	# A click cannot be two things, so arming a plant puts the drawing tools away.
	if _draft != null and _draft.drawing:
		_draft.set_drawing(false)
	planting_verdict = {}
	_say_planting()
	planting_changed.emit(planting_species)
	return true


func stop_planting() -> void:
	if planting_species.is_empty():
		return
	planting_species = &""
	planting_verdict = {}
	if plan_canvas != null:
		plan_canvas.status_text = ""
		plan_canvas.plant_ghost = {}
	planting_changed.emit(planting_species)


## What the plan says the ground is like, which is the drawing's own map. Null in a scene with no
## drawing, and every check treats that as "nothing is stated" rather than as a reason to fail.
func environment_map() -> ZoneMap:
	var controller: DraftControllerScript = draft_controller()
	if controller == null:
		return null
	var document: DraftDocument = controller.document
	return document.environment if document != null else null


## Judge one species against the ground at one point, without planting anything. The question the
## ring answers, askable from a script or a test.
func spot_verdict(species: PlantSpecies, world: Vector2) -> Dictionary:
	if species == null:
		return {}
	return PlantSuitabilityScript.check_at(species, environment_map(), world)


## Show where the plant in hand would go, and what the plan's own conditions say about that spot.
##
## Three things are decided here and nowhere else: which point on the ground the cursor is over, how
## much room the plant will want, and the verdict. The canvas is handed a point, a radius and a
## colour and draws them, so there is one place to change what a verdict means and one place that
## knows how to draw a ring.
func _update_plant_ghost() -> void:
	if plan_canvas == null or plant_catalogue == null:
		return
	var species: PlantSpecies = plant_catalogue.get_species(planting_species)
	if species == null:
		plan_canvas.plant_ghost = {}
		return
	var world: Vector2 = ViewMath.clamp_to_rect(
		_screen_to_world(get_viewport().get_mouse_position()), edit_bounds
	)
	var verdict: Dictionary = PlantSuitabilityScript.check_at(species, environment_map(), world)
	planting_verdict = verdict
	plan_canvas.plant_ghost = {
		"point": world,
		# The room the plant will want, not the size of the dot it is drawn as.
		"radius": species.spread_m() * 0.5,
		"colour": verdict["colour"],
		"label": verdict["label"],
		"verdict": verdict["verdict"],
		"species": planting_species,
	}


## Put one down where the cursor is, and leave the species armed so the next click puts down
## another: a bed is a dozen of the same plant, and re-arming after every one would be a dozen trips
## to the library.
func plant_at(screen: Vector2) -> Dictionary:
	if not is_planting():
		return {"ok": false, "reason": "nothing is being planted", "node": null, "scale": 1.0}
	var world: Vector2 = ViewMath.clamp_to_rect(_screen_to_world(screen), edit_bounds)
	var result: Dictionary = PlantPlacement.place(
		plant_catalogue, planting_species, yard, Vector3(world.x, floor_y, world.y)
	)
	if not bool(result["ok"]):
		if plan_canvas != null:
			plan_canvas.status_text = String(result["reason"])
		return result
	# The plan is a projection of the yard, so it is told to read it again; and the picker caches
	# the objects it can select, so that cache is dropped. Miss either and the new plant is a plant
	# you can see and not touch, or touch and not see.
	refresh_after_planting()
	# What the plan says about where it went, in words. The ring only ever described the spot under
	# the cursor; this describes the spot the plant is actually standing on, which is the one thing
	# the designer cannot see for themselves.
	_judge_placement(world)
	_say_planting(planting_verdict)
	result["suitability"] = planting_verdict
	return result


## The yard has changed: one plant, or a bed of them. The plan is a projection of the yard and the
## picker caches what it can select, so both have to be told, and they have to be told together -
## which is why this is one function rather than two lines written out at each of the places that
## plant something.
func refresh_after_planting() -> void:
	_placeable_cache_ready = false
	if plan_canvas != null:
		plan_canvas.rebind(yard)


## Judge the plant in hand against the ground at one point, and remember the answer.
func _judge_placement(world: Vector2) -> void:
	if plant_catalogue == null:
		planting_verdict = {}
		return
	var species: PlantSpecies = plant_catalogue.get_species(planting_species)
	planting_verdict = spot_verdict(species, world)


## How many plants are standing in the yard, for a menu that reports on the planting.
func planted_count() -> int:
	return PlantPlacement.planted(yard).size()


func _say_planting(verdict: Dictionary = {}) -> void:
	if plan_canvas == null or plant_catalogue == null:
		return
	var species: PlantSpecies = plant_catalogue.get_species(planting_species)
	if species == null:
		plan_canvas.status_text = ""
		return
	# `name` is not available as a local: it is a property of every Node, and shadowing it is an
	# error here for the same reason it would be a bug anywhere else in this file.
	var label: String = (
		species.common_name if not species.common_name.is_empty() else species.display_name()
	)
	var summary: String = String(verdict.get("summary", ""))
	# Armed but nothing placed yet: what the click will do. Only a *placement* writes the verdict
	# here - the one under the cursor is drawn at the cursor, because a status line rewritten every
	# frame is a status line that flickers while the mouse moves.
	if summary.is_empty():
		plan_canvas.status_text = "Click to plant %s  (%d planted)  -  Escape puts it away" % [
			label, planted_count()
		]
		return
	plan_canvas.status_text = "%s  %d planted.  Escape puts it away." % [summary, planted_count()]


# --- drafting -------------------------------------------------------------------------


## Whether the drawing tools are armed, which the HUD asks for in order to show the
## drafting keys. The keys themselves are the HUD's business: this answers one
## question and nothing else.
func is_drafting() -> bool:
	return _draft != null and _draft.drawing


## Take an editing command. It is a mode of the drawing tools rather than a tool,
## so it puts planting away: a click cannot both plant a shrub and trim a line.
func _arm_edit(kind: int) -> void:
	if _draft == null:
		return
	if is_planting():
		stop_planting()
	if plan_canvas != null:
		plan_canvas.hovered = null
	_draft.arm_edit(kind)
	get_viewport().set_input_as_handled()


## The drafting controller, for a palette to drive.
##
## Handed out whole rather than through a forward per button. It already answers
## every question a palette asks and performs every action a button takes, so
## forwarding each one would be a second copy of its interface, free to fall behind
## the first - which is exactly how a palette ends up with a button that no longer
## does what it says.
func draft_controller() -> DraftControllerScript:
	return _draft


## While a tool is armed it owns the left button. Right-drag still pans and the
## wheel still zooms, so you can keep drawing while moving around the plan, and
## the design objects underneath are left alone: a click goes to the drawing.
func _handle_drafting(event: InputEvent) -> bool:
	if event.is_action_pressed("draft_cancel"):
		_draft.cancel()
		get_viewport().set_input_as_handled()
		return true
	if event.is_action_pressed("draft_finish"):
		_draft.finish()
		get_viewport().set_input_as_handled()
		return true
	if event.is_action_pressed("draft_undo"):
		_draft.undo()
		get_viewport().set_input_as_handled()
		return true
	if event.is_action_pressed("draft_redo"):
		_draft.redo()
		get_viewport().set_input_as_handled()
		return true
	if event.is_action_pressed("draft_close"):
		_draft.finish_closed()
		get_viewport().set_input_as_handled()
		return true
	# Backspace peels the shape back one point at a time, and falls back to
	# undoing the last committed entity once there is nothing left to peel.
	if event.is_action_pressed("draft_undo_point"):
		if not _draft.undo_point():
			_draft.undo()
		get_viewport().set_input_as_handled()
		return true
	if _select_draft_tool(event):
		return true

	if event is InputEventMouseButton:
		var button: InputEventMouseButton = event
		if button.button_index == MOUSE_BUTTON_LEFT:
			if button.pressed:
				_draft.click(button.position)
			get_viewport().set_input_as_handled()
			return true
		if button.button_index == MOUSE_BUTTON_RIGHT:
			_panning = button.pressed
			get_viewport().set_input_as_handled()
			return true
		if button.button_index == MOUSE_BUTTON_WHEEL_UP:
			if button.pressed:
				zoom_by(1.0 / zoom_step, button.position)
			get_viewport().set_input_as_handled()
			return true
		if button.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			if button.pressed:
				zoom_by(zoom_step, button.position)
			get_viewport().set_input_as_handled()
			return true
	elif event is InputEventMouseMotion:
		var motion: InputEventMouseMotion = event
		if _panning:
			plan_focus -= motion.relative * (plan_size / maxf(
				get_viewport().get_visible_rect().size.y, 1.0
			))
			plan_focus = ViewMath.clamp_to_rect(plan_focus, pan_bounds)
			_apply_overhead_view()
		_draft.hover(motion.position)
		get_viewport().set_input_as_handled()
		return true
	return false


## Number keys pick the tool, which is how every CAD tool palette has worked
## since forever: the hand never leaves the left of the keyboard.
func _select_draft_tool(event: InputEvent) -> bool:
	var tools: Array = [
		["draft_line", DraftToolScript.Kind.LINE],
		["draft_polyline", DraftToolScript.Kind.POLYLINE],
		["draft_rect", DraftToolScript.Kind.RECTANGLE],
		["draft_circle", DraftToolScript.Kind.CIRCLE],
		["draft_arc", DraftToolScript.Kind.ARC],
		["draft_measure", DraftToolScript.Kind.MEASURE],
		["draft_dimension", DraftToolScript.Kind.DIMENSION],
		["draft_dimension_linear", DraftToolScript.Kind.DIMENSION_LINEAR],
		["draft_dimension_radius", DraftToolScript.Kind.DIMENSION_RADIUS],
	]
	for entry in tools:
		if event.is_action_pressed(entry[0]):
			_draft.set_tool(entry[1])
			get_viewport().set_input_as_handled()
			return true
	return false
