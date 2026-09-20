class_name Yard
extends Node3D
## The landscaping site: ground, lawn, house, paving and planting.
##
## The one-off geometry and every planted tree, shrub and bed live in yard.tscn,
## where they show up in the editor and are easy to nudge by hand. This script
## builds only the parts that are repetitive rather than designed -- the
## perimeter fence and the invisible barrier that keeps the player on the
## property -- and it gives both views a strong sense of scale.

const WOOD_MATERIAL = preload("res://resources/materials/fence_wood.tres")

## The fenced property boundary, in world XZ.
@export var bounds: Rect2 = Rect2(-14.0, -10.0, 28.0, 20.0)
## Distance between fence posts, in metres.
@export var post_spacing: float = 2.0
@export var post_size: Vector3 = Vector3(0.12, 1.75, 0.12)
## Rail heights above the ground, in metres.
@export var rail_low: float = 0.6
@export var rail_high: float = 1.35
@export var rail_thickness: float = 0.09
## Thickness of the invisible barrier along the fence line.
@export var barrier_thickness: float = 0.6

@onready var fence: Node3D = $Fence
@onready var barrier: StaticBody3D = $FenceCollision


func _ready() -> void:
	_build_fence()
	_build_barrier()


## Centre of the fenced property, in world XZ.
func centre() -> Vector2:
	return bounds.get_center()


func _build_fence() -> void:
	var post_mesh := BoxMesh.new()
	post_mesh.size = post_size

	# Walk the four sides, placing a post every post_spacing metres. Each side
	# lays posts up to but not including its end corner, so corners are shared
	# with the next side rather than doubled up.
	var corners: Array[Vector2] = [
		bounds.position,
		Vector2(bounds.end.x, bounds.position.y),
		bounds.end,
		Vector2(bounds.position.x, bounds.end.y),
	]
	for side in 4:
		var from: Vector2 = corners[side]
		var to: Vector2 = corners[(side + 1) % 4]
		var steps: int = maxi(1, int(round(from.distance_to(to) / post_spacing)))
		for step in steps:
			_place_post(from.lerp(to, float(step) / float(steps)), post_mesh)

	for level in [rail_low, rail_high]:
		_place_rails(float(level))


func _place_post(at: Vector2, mesh: BoxMesh) -> void:
	var post := MeshInstance3D.new()
	post.mesh = mesh
	post.material_override = WOOD_MATERIAL
	post.position = Vector3(at.x, post_size.y * 0.5, at.y)
	fence.add_child(post)


func _place_rails(height: float) -> void:
	var mid: Vector2 = centre()
	# One long rail per side per height rather than per segment: fewer nodes, and
	# a straight run of timber is what a real fence looks like anyway.
	var along_x := Vector3(bounds.size.x, rail_thickness, rail_thickness)
	var along_z := Vector3(rail_thickness, rail_thickness, bounds.size.y)
	_add_rail(along_x, Vector3(mid.x, height, bounds.position.y))
	_add_rail(along_x, Vector3(mid.x, height, bounds.end.y))
	_add_rail(along_z, Vector3(bounds.position.x, height, mid.y))
	_add_rail(along_z, Vector3(bounds.end.x, height, mid.y))


func _add_rail(mesh_size: Vector3, at: Vector3) -> void:
	var mesh := BoxMesh.new()
	mesh.size = mesh_size
	var rail := MeshInstance3D.new()
	rail.mesh = mesh
	rail.material_override = WOOD_MATERIAL
	rail.position = at
	fence.add_child(rail)


func _build_barrier() -> void:
	var mid: Vector2 = centre()
	var height: float = post_size.y
	var y: float = height * 0.5
	# Four walls, slightly overlapping at the corners so there is no gap to slip
	# through and no corner to catch on.
	var along_x := Vector3(bounds.size.x + barrier_thickness, height, barrier_thickness)
	var along_z := Vector3(barrier_thickness, height, bounds.size.y + barrier_thickness)
	_add_barrier(along_x, Vector3(mid.x, y, bounds.position.y))
	_add_barrier(along_x, Vector3(mid.x, y, bounds.end.y))
	_add_barrier(along_z, Vector3(bounds.position.x, y, mid.y))
	_add_barrier(along_z, Vector3(bounds.end.x, y, mid.y))


func _add_barrier(shape_size: Vector3, at: Vector3) -> void:
	var shape := BoxShape3D.new()
	shape.size = shape_size
	var collider := CollisionShape3D.new()
	collider.shape = shape
	collider.position = at
	barrier.add_child(collider)
