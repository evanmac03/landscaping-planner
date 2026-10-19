class_name PlanCanvas
extends Node2D
## The flat, schematic 2D overhead view of the design.
##
## This is a second *projection* of the one 3D world, not a second copy of it.
## The yard's static geometry is read straight off the 3D meshes and drawn as
## flat plan shapes, and every planted prop is drawn as a drafting symbol that
## tracks its 3D node. Nothing is duplicated, so there is no state to reconcile:
## moving an object in either view moves it in both, by construction.
##
## The node draws in *metres*. `scale` is the plan's pixels per metre and
## `position` is the pan offset, so local coordinates are simply world XZ. Stroke
## widths are divided by that scale so they stay a constant thickness on screen.

## Yard subtrees that are not part of the design and are skipped entirely.
const IGNORED := ["Fence", "FenceCollision", "Surroundings"]
## The yard subtree whose children are the movable design objects.
const PLANTS := "Plants"

const PAPER := Color(0.945, 0.937, 0.906)
const GRID := Color(0.16, 0.18, 0.14, 0.075)
const FENCE_LINE := Color(0.45, 0.36, 0.26, 0.9)
const CANOPY := Color(0.45, 0.64, 0.35)
const CANOPY_LINE := Color(0.27, 0.42, 0.21)
const TRUNK := Color(0.42, 0.32, 0.22)
const BED_SOIL := Color(0.63, 0.5, 0.37)
const BED_EDGE := Color(0.73, 0.71, 0.66)
const BED_BLOOM := Color(0.85, 0.45, 0.6)
const SHADOW := Color(0.33, 0.31, 0.26, 0.17)
const HOVER := Color(0.13, 0.4, 0.62, 0.8)
const GRAB := Color(0.94, 0.55, 0.1, 0.95)
const GENERIC := Color(0.55, 0.28, 0.55)

## Drop-shadow offset for symbols, in metres. Gives the flat drawing a little
## depth so a prop reads as an object rather than a stain.
const SHADOW_OFFSET := Vector2(-0.3, 0.36)

## Grid spacings to choose from, smallest first, so the grid stays legible at
## every zoom level.
const GRID_STEPS: Array[float] = [0.25, 0.5, 1.0, 2.0, 5.0, 10.0, 25.0]
const GRID_MIN_PIXELS := 24.0

## Current view state, pushed in from the ViewController.
var focus: Vector2 = Vector2.ZERO
var plan_size: float = 23.0
var pixels_per_metre: float = 39.0

## The design object under the cursor, and the one being dragged. The
## ViewController owns these; the canvas only draws them.
var hovered: Node3D = null
var grabbed: Node3D = null

var _viewport_size: Vector2 = Vector2(1600.0, 900.0)
var _context: Array[Dictionary] = []
var _placeables: Array[Node3D] = []
var _specs: Dictionary = {}
var _fence: Rect2 = Rect2()
var _has_fence: bool = false


func _process(_delta: float) -> void:
	# The plan is a projection of live 3D nodes, so simply repaint while it is on
	# screen. A few dozen flat shapes cost nothing, and it removes any chance of a
	# stale plan after an edit made in the 3D view.
	if is_visible_in_tree():
		queue_redraw()


## Re-read the yard: which meshes form the static backdrop, and which props are
## movable design objects. Call once the yard has entered the tree.
func rebind(yard: Node3D) -> void:
	_context.clear()
	_placeables.clear()
	_specs.clear()
	_has_fence = false
	if yard != null:
		_collect(yard)
		if yard.has_method("get_bounds"):
			_fence = yard.get_bounds()
			_has_fence = true
	# Big shapes first, so small ones sit on top of them the way a plan drawing
	# layers its elements.
	_context.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool: return a["extent"] > b["extent"]
	)
	_placeables.sort_custom(
		func(a: Node3D, b: Node3D) -> bool:
			return PlanStyle.footprint_radius(a) > PlanStyle.footprint_radius(b)
	)
	queue_redraw()


## Push the shared overhead view state in. Both the 2D plan and the 3D overhead
## camera are driven from the same focus and zoom, so switching between them
## keeps you looking at exactly the same patch of ground.
func apply_view(new_focus: Vector2, new_plan_size: float, viewport_size: Vector2) -> void:
	_viewport_size = viewport_size
	focus = new_focus
	plan_size = maxf(new_plan_size, 0.001)
	pixels_per_metre = maxf(viewport_size.y, 1.0) / plan_size
	scale = Vector2(pixels_per_metre, pixels_per_metre)
	position = viewport_size * 0.5 - focus * pixels_per_metre
	queue_redraw()


## World position to screen pixels. Screen +x is world +x (east) and screen +y is
## world +z (south), which is exactly how the 3D overhead camera is oriented, so
## the two views line up pixel for pixel.
func world_to_screen(world: Vector3) -> Vector2:
	return position + Vector2(world.x, world.z) * pixels_per_metre


## Screen pixels to world XZ.
func screen_to_world(screen: Vector2) -> Vector2:
	return (screen - position) / pixels_per_metre


# --- construction -----------------------------------------------------------------


func _collect(node: Node) -> void:
	for child in node.get_children():
		var child_name := String(child.name)
		if IGNORED.has(child_name):
			continue
		if child_name == PLANTS:
			for plant in child.get_children():
				if plant is Node3D:
					_placeables.append(plant)
					_specs[plant] = PlanStyle.spec_for((plant as Node3D).scene_file_path)
			continue
		if child is MeshInstance3D:
			_add_mesh(child)
		_collect(child)


## Records one 3D mesh as a flat plan shape, using the mesh's world-space
## bounding box so rotated and scaled parts are handled without special cases.
func _add_mesh(mesh_instance: MeshInstance3D) -> void:
	if mesh_instance.mesh == null:
		return
	var xform: Transform3D = mesh_instance.global_transform
	var bounds: AABB = mesh_instance.get_aabb()
	var low := Vector2(INF, INF)
	var high := Vector2(-INF, -INF)
	for corner in 8:
		var point: Vector3 = xform * bounds.get_endpoint(corner)
		low.x = minf(low.x, point.x)
		low.y = minf(low.y, point.z)
		high.x = maxf(high.x, point.x)
		high.y = maxf(high.y, point.z)
	var size: Vector2 = high - low
	if size.x <= 0.001 or size.y <= 0.001:
		return
	_context.append({
		"centre": (low + high) * 0.5,
		"size": size,
		"round": mesh_instance.mesh is CylinderMesh or mesh_instance.mesh is SphereMesh,
		"colour": PlanStyle.colour_for(mesh_instance),
		"extent": maxf(size.x, size.y),
	})


# --- drawing ----------------------------------------------------------------------


func _draw() -> void:
	if pixels_per_metre <= 0.0:
		return
	_draw_paper()
	_draw_grid()
	for shape: Dictionary in _context:
		_draw_context_shape(shape)
	_draw_fence()
	for node: Node3D in _placeables:
		_draw_placeable(node)
	var marked: Node3D = grabbed if grabbed != null else hovered
	if marked != null:
		_draw_selection(marked, grabbed != null)


## Opaque paper, so the hidden 3D render behind is fully covered even while the
## view cross-fades.
func _draw_paper() -> void:
	draw_rect(Rect2(_screen_to_local(Vector2.ZERO), _screen_to_local(_viewport_size)), PAPER, true)


func _draw_grid() -> void:
	var step: float = GRID_STEPS[GRID_STEPS.size() - 1]
	for candidate: float in GRID_STEPS:
		if candidate * pixels_per_metre >= GRID_MIN_PIXELS:
			step = candidate
			break
	var top_left: Vector2 = _screen_to_local(Vector2.ZERO)
	var bottom_right: Vector2 = _screen_to_local(_viewport_size)
	var width: float = 1.0 / pixels_per_metre
	var x: float = floorf(top_left.x / step) * step
	while x <= bottom_right.x:
		draw_line(Vector2(x, top_left.y), Vector2(x, bottom_right.y), GRID, width)
		x += step
	var y: float = floorf(top_left.y / step) * step
	while y <= bottom_right.y:
		draw_line(Vector2(top_left.x, y), Vector2(bottom_right.x, y), GRID, width)
		y += step


func _draw_context_shape(shape: Dictionary) -> void:
	var size: Vector2 = shape["size"]
	var colour: Color = shape["colour"]
	var line_width: float = 1.0 / pixels_per_metre
	if shape["round"]:
		var radius: float = size.x * 0.5
		draw_circle(shape["centre"], radius, colour)
		draw_arc(shape["centre"], radius, 0.0, TAU, 36, colour.darkened(0.35), line_width)
	else:
		var rect := Rect2(shape["centre"] - size * 0.5, size)
		draw_rect(rect, colour, true)
		draw_rect(rect, colour.darkened(0.35), false, line_width)


func _draw_fence() -> void:
	if _has_fence:
		draw_rect(_fence, FENCE_LINE, false, 1.8 / pixels_per_metre)


func _draw_placeable(node: Node3D) -> void:
	var spec: Dictionary = _specs.get(node, PlanStyle.PLACEHOLDER)
	var centre := Vector2(node.global_position.x, node.global_position.z)
	var instance_scale: float = node.global_transform.basis.get_scale().x
	var size: Vector2 = spec["size"] * instance_scale
	match int(spec["symbol"]):
		PlanStyle.Symbol.TREE:
			_draw_tree(centre, size)
		PlanStyle.Symbol.SHRUB:
			_draw_shrub(centre, size)
		PlanStyle.Symbol.BED:
			_draw_bed(centre, size)
		_:
			_draw_generic(centre, size)


func _draw_tree(centre: Vector2, size: Vector2) -> void:
	var radius: float = size.x * 0.5
	draw_circle(centre + SHADOW_OFFSET, radius, SHADOW)
	draw_circle(centre, radius, CANOPY)
	draw_arc(centre, radius, 0.0, TAU, 48, CANOPY_LINE, 1.4 / pixels_per_metre)
	# Trunk dot, so the symbol reads as a tree seen from directly above.
	draw_circle(centre, minf(radius * 0.18, 0.34), TRUNK)


func _draw_shrub(centre: Vector2, size: Vector2) -> void:
	var radius: float = size.x * 0.5
	var outline: PackedVector2Array = _blob(centre, radius)
	draw_circle(centre + SHADOW_OFFSET, radius * 0.94, SHADOW)
	draw_colored_polygon(outline, CANOPY)
	draw_polyline(outline, CANOPY_LINE, 1.3 / pixels_per_metre, true)


func _draw_bed(centre: Vector2, size: Vector2) -> void:
	var rect := Rect2(centre - size * 0.5, size)
	draw_rect(rect, BED_SOIL, true)
	draw_rect(rect, BED_EDGE, false, 3.0 / pixels_per_metre)
	draw_rect(rect.grow(-0.16), BED_EDGE, false, 1.0 / pixels_per_metre)
	# A row of blooms, so a bed reads as planting rather than a plain box.
	var spacing: float = size.x / 4.0
	for index in 4:
		var bloom := centre + Vector2(
			-size.x * 0.5 + spacing * (float(index) + 0.5),
			(size.y * 0.5 - 0.3) * (1.0 if index % 2 == 0 else -1.0) * 0.55
		)
		draw_circle(bloom, minf(size.y * 0.2, 0.22), BED_BLOOM)


func _draw_generic(centre: Vector2, size: Vector2) -> void:
	# An unknown prop is still drawn and still draggable, just flagged as
	# undescribed, so adding a new prop type never makes it vanish from the plan.
	var rect := Rect2(centre - size * 0.5, size)
	draw_rect(rect, GENERIC, true)
	draw_rect(rect, GENERIC.darkened(0.4), false, 1.4 / pixels_per_metre)
	draw_line(rect.position, rect.end, GENERIC.darkened(0.4), 1.2 / pixels_per_metre)
	draw_line(
		Vector2(rect.position.x, rect.end.y),
		Vector2(rect.end.x, rect.position.y),
		GENERIC.darkened(0.4),
		1.2 / pixels_per_metre
	)


func _draw_selection(node: Node3D, active: bool) -> void:
	var centre := Vector2(node.global_position.x, node.global_position.z)
	var radius: float = PlanStyle.footprint_radius(node) + 0.45
	draw_arc(
		centre, radius, 0.0, TAU, 48,
		GRAB if active else HOVER,
		(3.0 if active else 2.0) / pixels_per_metre
	)


## Points around a circle whose radius wobbles, so a shrub looks like foliage
## rather than a plain disc. The last point repeats the first to close the loop.
func _blob(centre: Vector2, radius: float) -> PackedVector2Array:
	const LOBES := 7
	const SEGMENTS := 40
	var points := PackedVector2Array()
	for index in SEGMENTS + 1:
		var theta: float = TAU * float(index) / float(SEGMENTS)
		var wobbled: float = radius * (1.0 + 0.13 * sin(LOBES * theta))
		points.append(centre + Vector2(cos(theta), sin(theta)) * wobbled)
	return points


func _screen_to_local(screen: Vector2) -> Vector2:
	return (screen - position) / pixels_per_metre