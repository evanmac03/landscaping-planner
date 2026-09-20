class_name ViewController
extends Node
## Drives the plan <-> ground transition of the landscaping planner.
##
## The planner holds a single 3D world. The "2D" plan view is an orthographic
## Camera3D looking straight down; the ground view is the player's first-person
## camera. Instead of cutting between them, one flight camera travels between the
## two poses, so the plan appears to stand up into the ground view.
##
## What makes the flight continuous is that a perspective camera high up with a
## narrow field of view frames very nearly what an orthographic camera frames.
## The camera therefore changes projection on the first frame of the flight, at
## the altitude where the two projections agree exactly (see ViewMath), so the
## change is invisible. The tween then descends, pitches level and widens the
## field of view until the plan has turned into a view from the ground.
##
## Layout requirement: in the main scene, the Player node must appear before this
## node so the player's own _ready() has run before the first pose is applied.

enum ViewMode {
	PLAN,   ## Orthographic, looking straight down at the design.
	GROUND, ## First person, walking the design at eye height.
}

signal view_mode_changed(mode: ViewMode)
signal transition_started(to_ground: bool)
signal transition_finished(to_ground: bool)

@export var flight_camera: Camera3D
@export var player: PlanPlayer
## The landscaping content, used to centre the plan view. Optional.
@export var yard: Node3D

@export_group("Plan view")
## Metres of world visible across the plan view's height (the camera's
## orthographic size). Overwritten by fit_plan_to_yard() on start.
@export var plan_size: float = 23.0
## XZ extent of the design, used to frame the plan view on start.
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

var mode: ViewMode = ViewMode.PLAN:
	set(value):
		if mode == value:
			return
		mode = value
		view_mode_changed.emit(mode)

## World XZ point at the centre of the plan view. Also where the flight aims.
var plan_focus: Vector2 = Vector2.ZERO

var _tween: Tween
var _transitioning: bool = false
var _dragging: bool = false


func _ready() -> void:
	if flight_camera == null or player == null:
		push_error("ViewController: flight_camera and player must both be assigned.")
		set_process(false)
		set_process_unhandled_input(false)
		return
	if yard != null:
		plan_focus = Vector2(yard.global_position.x, yard.global_position.z)
	fit_plan_to_yard()
	_apply_plan_pose()
	flight_camera.current = true
	player.set_active(false)
	player.release_mouse()
	view_mode_changed.emit(mode)


func is_transitioning() -> bool:
	return _transitioning


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
	_apply_plan_pose()


## Recentre the plan view on the design without changing the zoom.
func recentre_plan() -> void:
	if yard != null:
		plan_focus = Vector2(yard.global_position.x, yard.global_position.z)
	_apply_plan_pose()


func toggle_view() -> void:
	if _transitioning:
		return
	if mode == ViewMode.PLAN:
		fly_to_ground()
	else:
		fly_to_plan()


## Dive from the plan view down to eye level. Reversed by fly_to_plan().
func fly_to_ground() -> void:
	if _transitioning or mode == ViewMode.GROUND:
		return
	_transitioning = true
	transition_started.emit(true)

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
	if _transitioning or mode == ViewMode.PLAN:
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
	_apply_plan_pose()


func _apply_plan_pose() -> void:
	if flight_camera == null:
		return
	flight_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	flight_camera.size = plan_size
	flight_camera.global_position = Vector3(plan_focus.x, plan_height, plan_focus.y)
	# Looking straight down with the camera's up vector along world -Z, so world
	# -Z reads as "up" on screen, the way a landscape plan is drawn.
	flight_camera.global_rotation = Vector3(-PI * 0.5, 0.0, 0.0)
	# Keep the perspective field of view pre-matched so the projection swap on the
	# first frame of the flight needs no last-minute change.
	flight_camera.fov = ViewMath.match_fov(plan_size, plan_height)


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
	_transitioning = false
	mode = ViewMode.GROUND
	transition_finished.emit(true)


func _on_arrived_at_plan() -> void:
	# The matching was exact, so swapping to the orthographic projection here is
	# invisible: same position, same rotation, same framing.
	_apply_plan_pose()
	flight_camera.current = true
	player.set_active(false)
	_transitioning = false
	mode = ViewMode.PLAN
	transition_finished.emit(false)


func _kill_tween() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = null


func _process(delta: float) -> void:
	if mode != ViewMode.PLAN or _transitioning:
		return

	var zoom_axis: float = Input.get_axis("zoom_out", "zoom_in")
	if absf(zoom_axis) > 0.001:
		zoom_by(1.0 - zoom_axis * 1.8 * delta, get_viewport().get_mouse_position())

	# WASD pans the plan view: forward moves the camera up the screen, which is
	# world -Z.
	var stick: Vector2 = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	if stick.length_squared() <= 0.0:
		return
	plan_focus += stick * (plan_size * pan_rate * delta)
	plan_focus = ViewMath.clamp_to_rect(plan_focus, pan_bounds)
	_apply_plan_pose()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_view"):
		toggle_view()
		get_viewport().set_input_as_handled()
		return

	if mode != ViewMode.PLAN or _transitioning:
		return

	if event is InputEventMouseButton:
		var button: InputEventMouseButton = event
		match button.button_index:
			MOUSE_BUTTON_RIGHT:
				_dragging = button.pressed
			MOUSE_BUTTON_WHEEL_UP:
				if button.pressed:
					zoom_by(1.0 / zoom_step, button.position)
			MOUSE_BUTTON_WHEEL_DOWN:
				if button.pressed:
					zoom_by(zoom_step, button.position)
	elif event is InputEventMouseMotion and _dragging:
		var motion: InputEventMouseMotion = event
		# Drag the design with the cursor: the plan point under the mouse stays put.
		plan_focus -= motion.relative * (plan_size / maxf(
			get_viewport().get_visible_rect().size.y, 1.0
		))
		plan_focus = ViewMath.clamp_to_rect(plan_focus, pan_bounds)
		_apply_plan_pose()
