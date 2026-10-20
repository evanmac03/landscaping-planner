class_name OrbitCamera
extends Node3D
## The presentation rig: a pivot with a camera held away from it.
##
## Three axes on three nodes - yaw on the arm, pitch on the elevation, distance
## on the boom - so each is one number on one axis: no quaternion arithmetic, no
## gimbal surprise at the poles, and a pitch clamp that is a clamp on a single
## value rather than something that has to be repaired afterwards.

## Closest and furthest the camera may sit from the subject, in metres.
@export var min_distance: float = 3.0
@export var max_distance: float = 60.0
## Below this the camera is under the ground; above it, it is a map.
@export var min_elevation_deg: float = 5.0
@export var max_elevation_deg: float = 85.0
## Multiplier per wheel notch, and radians per pixel of drag.
@export var dolly_step: float = 1.35
@export var orbit_step: float = 0.006
## The elevation `frame()` looks from. A garden overview is a three-quarter view: too
## low and the picture is half lawn with a thin band of garden above it, too high and
## it is a plan rather than a picture.
@export var frame_elevation_deg: float = 38.0

var arm: Node3D
var elevation: Node3D
var boom: Node3D
var camera: Camera3D


func _ready() -> void:
	# Found by name rather than by an exported path, so the rig is only ever
	# described once: the four nodes this needs are the four nodes the scene names.
	arm = get_node_or_null(^"Arm")
	elevation = get_node_or_null(^"Arm/Elevation")
	boom = get_node_or_null(^"Arm/Elevation/Boom")
	camera = get_node_or_null(^"Arm/Elevation/Boom/Camera")
	if arm == null or elevation == null or boom == null or camera == null:
		push_error("OrbitCamera: the rig needs Arm/Elevation/Boom/Camera children.")


## Frame a box: put the pivot at its centre and pull back until it fits, leaving
## `margin` of the frame empty around it.
##
## The distance comes from the camera's own field of view and the viewport's
## aspect, not from a table of magic numbers, so changing the lens re-frames
## correctly instead of clipping something.
func frame(box: AABB, margin: float = 0.18) -> void:
	if box.size.length() <= 0.0 or camera == null or elevation == null:
		return
	# The pivot goes to the centre of the thing being framed, so the sight line passes
	# through the middle of it, and the elevation is set rather than left wherever the
	# camera happened to be. Fitting a garden by distance alone from an eye-level
	# camera gives a picture that is two-thirds lawn with a thin band of garden above
	# it: the box fits the frame, but along a sight line that passes through it rather
	# than looking at it.
	global_position = box.get_center()
	elevation.rotation.x = -clampf(
		deg_to_rad(frame_elevation_deg),
		deg_to_rad(min_elevation_deg), deg_to_rad(max_elevation_deg)
	)
	# Half the box's diagonal against the tangent of half the field of view: the
	# distance at which that diagonal exactly fills the frame. Using the diagonal
	# rather than the widest side means a tall object frames as well as a wide one,
	# whichever way the camera is pointed.
	var radius: float = box.size.length() * 0.5
	var half_vertical: float = deg_to_rad(camera.fov * 0.5)
	# A frame is usually wider than it is tall, so the vertical half-angle is the
	# one that runs out first. Taking the smaller of the two means neither edge is
	# clipped, whatever the aspect ratio is.
	var aspect: float = camera.get_viewport().get_visible_rect().size.aspect()
	var half_horizontal: float = atan(tan(half_vertical) * aspect)
	var half: float = minf(half_vertical, half_horizontal)
	set_distance(radius / tan(half) * (1.0 + margin))


## Set the boom length, clamped. One number to keep in range.
##
## The parameter is named for the length rather than for the distance, because
## `distance()` is the getter below and a parameter may not shadow it.
func set_distance(length_m: float) -> void:
	if boom == null:
		return
	boom.position.z = clampf(length_m, min_distance, max_distance)


func distance() -> float:
	return boom.position.z if boom != null else 0.0


## Yaw and pitch from a drag, in pixels. Both clamps live here, so no caller needs
## to know about them or remember to apply them.
##
## The sign is worth stating once, because it is where this rig can silently put the
## camera underground: the boom runs along its own **+Z**, so a positive rotation about
## X tips it *downward*, and the camera ends up below the pivot. This rig therefore
## talks in degrees **above the ground** and negates at the two places it touches the
## node. Keeping that conversion in one habit is what makes "5 to 85" mean what it says.
func orbit(delta_pixels: Vector2) -> void:
	if arm == null or elevation == null:
		return
	arm.rotate_y(-delta_pixels.x * orbit_step)
	# Dragging down raises the camera, the way a turntable behaves: the gesture pulls
	# the garden down the screen, which means looking at it from higher up.
	var above: float = -elevation.rotation.x + delta_pixels.y * orbit_step
	elevation.rotation.x = -clampf(
		above, deg_to_rad(min_elevation_deg), deg_to_rad(max_elevation_deg)
	)


## Dolly in and out. Proportional to the current distance, so one wheel notch is
## the same visual step at 3 m as at 30 m.
func dolly(notches: float) -> void:
	set_distance(distance() * pow(dolly_step, -notches))


## Swing the pivot across the ground, keeping the distance and the heading. This is
## what you want when the subject is off to one side: a pan, not a re-frame.
func truck(ground_delta: Vector2) -> void:
	if arm == null:
		return
	var yaw: float = arm.rotation.y
	var right := Vector2(cos(yaw), -sin(yaw))
	var forward := Vector2(-sin(yaw), -cos(yaw))
	var moved: Vector2 = right * ground_delta.x + forward * ground_delta.y
	global_position += Vector3(moved.x, 0.0, moved.y)


## Pitch and distance, for a status line or a saved view.
##
## The pitch is reported as degrees *above the ground*, which is the number this rig
## talks in, rather than as the node's rotation - which is its negation.
func state() -> Dictionary:
	return {
		"yaw_deg": rad_to_deg(arm.rotation.y) if arm != null else 0.0,
		"pitch_deg": -rad_to_deg(elevation.rotation.x) if elevation != null else 0.0,
		"distance_m": distance(),
		"eye": camera.global_position if camera != null else Vector3.ZERO,
	}