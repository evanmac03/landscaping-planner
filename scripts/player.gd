class_name PlanPlayer
extends CharacterBody3D
## First-person walk controller for the ground-level view of the planner.
##
## The body's Y rotation carries the yaw (turning) and the Head node's X
## rotation carries the pitch (looking up and down), so the two never fight each
## other. The ViewController enables and disables the controller around the
## camera flight so the player never drifts while the camera is moving.

## Eye height above the feet in metres. Set to match ViewController.land_eye_height
## so the flight hands over to the player's camera without a visible jump.
@export var eye_height: float = 1.7
@export var walk_speed: float = 4.5
@export var run_speed: float = 9.0
## Higher values reach the target speed sooner. Used as an exponential smoothing
## rate so movement is frame-rate independent.
@export var acceleration: float = 14.0
@export var mouse_sensitivity: float = 0.0022
## Turn rate for the arrow-key look fallback, in radians per second.
@export var arrow_key_turn_speed: float = 1.9
@export var pitch_limit_deg: float = 88.0

@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera3D

var _yaw: float = 0.0
var _pitch: float = 0.0
var _gravity: float = 9.8
var _active: bool = false
var _mouse_captured: bool = false


func _ready() -> void:
	_gravity = float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8))
	head.position = Vector3(0.0, eye_height, 0.0)
	set_look(_yaw, _pitch)


## True while the player owns the camera and responds to input.
func is_active() -> bool:
	return _active


func set_active(active: bool) -> void:
	_active = active
	if not active:
		velocity = Vector3.ZERO


## Aim the head directly. The ViewController calls this at the end of the flight
## so the handover from the flight camera is seamless.
func set_look(yaw: float, pitch: float) -> void:
	var limit: float = deg_to_rad(pitch_limit_deg)
	_yaw = yaw
	_pitch = clampf(pitch, -limit, limit)
	rotation = Vector3(0.0, _yaw, 0.0)
	head.rotation = Vector3(_pitch, 0.0, 0.0)


func get_yaw() -> float:
	return _yaw


func get_pitch() -> float:
	return _pitch


## Feet-down placement at a world XZ spot, facing `yaw`. Used when the flight
## lands so the player is already standing where the camera came to rest.
func place(spot: Vector2, floor_y: float, yaw: float, pitch: float) -> void:
	global_position = Vector3(spot.x, floor_y, spot.y)
	velocity = Vector3.ZERO
	set_look(yaw, pitch)


## World position of the eye, used to start the return flight from exactly where
## the player is looking.
func eye_position() -> Vector3:
	return head.global_position


func capture_mouse() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	_mouse_captured = true


func release_mouse() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	_mouse_captured = false


func is_mouse_captured() -> bool:
	return _mouse_captured


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and _active and _mouse_captured:
		var motion: InputEventMouseMotion = event
		# Mouse right turns right (negative yaw); mouse down looks down.
		set_look(
			_yaw - motion.relative.x * mouse_sensitivity,
			_pitch - motion.relative.y * mouse_sensitivity
		)
		return

	if not _active:
		return

	if event.is_action_pressed("ui_cancel"):
		release_mouse()
	elif event is InputEventMouseButton:
		var button: InputEventMouseButton = event
		# Clicking the world while the cursor is free takes the mouse back.
		# Clicks that land on HUD controls are consumed by the GUI and never
		# reach here, so the buttons keep working.
		if button.pressed and button.button_index == MOUSE_BUTTON_LEFT and not _mouse_captured:
			capture_mouse()


func _physics_process(delta: float) -> void:
	if not _active:
		return

	# Arrow-key look fallback, so the ground view is usable without a mouse.
	var turn: float = Input.get_axis("look_right", "look_left")
	var tilt: float = Input.get_axis("look_down", "look_up")
	if absf(turn) > 0.001 or absf(tilt) > 0.001:
		set_look(
			_yaw + turn * arrow_key_turn_speed * delta,
			_pitch + tilt * arrow_key_turn_speed * delta
		)

	if not is_on_floor():
		velocity.y -= _gravity * delta
	elif velocity.y < 0.0:
		velocity.y = 0.0

	# The stick gives x = right - left and y = back - forward; the body's local
	# +Z is backwards, so basis.z * y walks forward for a negative y. Read through
	# MoveInput, so a command on Ctrl does not also take a step.
	var stick: Vector2 = MoveInput.stick()
	var direction: Vector3 = transform.basis.x * stick.x + transform.basis.z * stick.y
	direction.y = 0.0
	if direction.length_squared() > 0.0:
		direction = direction.normalized()

	var speed: float = run_speed if MoveInput.sprinting() else walk_speed
	var target: Vector3 = direction * speed
	var weight: float = 1.0 - exp(-acceleration * delta)
	velocity.x = lerpf(velocity.x, target.x, weight)
	velocity.z = lerpf(velocity.z, target.z, weight)

	move_and_slide()
