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

const DraftEntityScript := preload("res://scripts/draft/draft_entity.gd")
const DraftRenderScript := preload("res://scripts/draft/draft_render.gd")
const DraftDimensionScript := preload("res://scripts/draft/dimension.gd")

## The smallest an annotation is allowed to draw on screen, in pixels. Annotation
## text is sized from its authored paper height, which is correct but vanishes at
## a working zoom, so it holds this floor and stays readable.
const MIN_TEXT_PIXELS := 8.0

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
## The snap indicator: a small box on the point the cursor has snapped to.
const SNAP := Color(0.98, 0.72, 0.12)
const SNAP_TEXT := Color(0.09, 0.1, 0.11, 0.9)

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

## The drafting document, if one is bound. Its linework draws on top of the yard,
## which is the right way round: the design sits over what was already there.
var document = null
## The plot scale the on-screen linework imitates. Weights are authored in paper
## millimetres, so they only become pixels once a sheet scale is chosen.
var display_scale: float = 100.0
## The shape being drawn, ghosted: {"entity": …, "layer": …}.
var ghost: Dictionary = {}
## Where the cursor snapped to, from the drafting controller.
var snap: Dictionary = {}
## What the drafting tools are waiting for, drawn on the plan itself.
var status_text: String = ""


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
	_draw_document()
	var marked: Node3D = grabbed if grabbed != null else hovered
	if marked != null:
		_draw_selection(marked, grabbed != null)
	_draw_status()


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


# --- the drafted document ---------------------------------------------------------


## Point the canvas at a drafting document. From here on its linework is part of
## the plan, and it is the same document the 3D overlay and the sheet exporter
## read, so all three show one design.
func bind_document(doc) -> void:
	document = doc
	queue_redraw()


func _draw_document() -> void:
	if document == null:
		return
	for entity in document.visible_entities():
		_draw_entity(entity, document.layers.get_layer(entity.layer), 1.0)
	if ghost.get("entity", null) != null:
		_draw_entity(ghost["entity"], ghost.get("layer", null), 0.45)
	_draw_snap_marker()


## One entity, in its layer's colour and at its layer's weight, drawn from the
## shared layout so a dimension arrives here exactly as it will on the sheet.
func _draw_entity(entity, layer, alpha: float) -> void:
	var colour: Color = DraftRenderScript.screen_colour(layer)
	colour.a *= alpha
	var parts: Dictionary = DraftRenderScript.layout(entity, layer, display_scale, _units())
	var style = parts["style"]
	# Godot's draw widths are in the canvas item's own units, which here are
	# metres, so a pixel width has to be divided back down by the zoom or the
	# stroke comes out `pixels_per_metre` times too thick.
	var width: float = style.width_pixels(display_scale, pixels_per_metre) / pixels_per_metre
	for stroke: PackedVector2Array in parts["lines"]:
		if stroke.size() < 2:
			continue
		draw_polyline(stroke, colour, width, true)
	# Arrowheads are filled solids, not strokes, so they are polygons of their
	# own rather than the ends of the dimension line.
	for arrow: Dictionary in parts["arrows"]:
		draw_colored_polygon(
			DraftDimensionScript.arrow_triangle(
				arrow["tip"], arrow["direction"], arrow["size"]
			),
			colour
		)
	_draw_labels(parts["labels"], colour)


## Dimension values and notes, which sit alongside the linework rather than on it.
##
## Text is drawn in screen space because the canvas works in metres, where a font
## size would be a fraction of a pixel and the fallback font would rasterise
## nothing at all. The size still comes from the authored paper height, so the
## plan and the sheet agree about how big a note is.
func _draw_labels(labels: Array, colour: Color) -> void:
	for label: Dictionary in labels:
		var text: String = String(label["text"])
		if text == "":
			continue
		var screen: Vector2 = position + Vector2(label["position"]) * pixels_per_metre
		var size: float = maxf(MIN_TEXT_PIXELS, float(label["height"]) * pixels_per_metre)
		_draw_screen_text(screen, text, int(size), colour)


## The document's units, so a dimension reads in the same system the plan was
## drawn in. Absent a document, a measurement falls back to plain metres.
func _units():
	return document.units if document != null else null


func _draw_snap_marker() -> void:
	if not snap.get("snapped", false):
		return
	var point: Vector2 = snap["point"]
	var half: float = 6.0 / pixels_per_metre
	draw_rect(
		Rect2(point - Vector2(half, half), Vector2(half, half) * 2.0),
		SNAP, false, 1.6 / pixels_per_metre
	)
	var label: String = String(snap.get("label", ""))
	if label == "":
		return
	var screen: Vector2 = position + point * pixels_per_metre
	_draw_screen_text(screen + Vector2(11.0, -11.0), label, 12, SNAP_TEXT)


func _draw_screen_text(screen: Vector2, text: String, size: int, colour: Color) -> void:
	const DARK := Color(0.98, 0.98, 0.96, 0.9)
	_begin_screen_space()
	# A light halo behind the glyphs, because a snap label can land on top of
	# dark planting and become unreadable exactly when it matters most.
	draw_string(
		ThemeDB.fallback_font, screen + Vector2(1.0, 1.0), text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, size, DARK
	)
	draw_string(
		ThemeDB.fallback_font, screen, text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, size, colour
	)
	_end_screen_space()


## Text and overlays are drawn in screen pixels, not metres.
##
## Godot's draw_set_transform *adds* to the canvas item's own transform rather
## than replacing it, so zeroing it is not enough: the node's own position and
## zoom still apply on top and send the result off the screen. The only way to
## reach true screen space is to cancel that transform out with its inverse.
func _begin_screen_space() -> void:
	draw_set_transform_matrix(_node_transform().affine_inverse())


func _end_screen_space() -> void:
	draw_set_transform_matrix(Transform2D.IDENTITY)


## This node's own transform, which is exactly pan plus zoom and no rotation.
func _node_transform() -> Transform2D:
	return Transform2D(
		Vector2(pixels_per_metre, 0.0),
		Vector2(0.0, pixels_per_metre),
		position
	)


## The drafting status, on the drawing surface rather than in the HUD: what the
## next pick will do is a property of the drawing, and the eye is already there.
func _draw_status() -> void:
	if status_text == "":
		return
	draw_set_transform_matrix(_node_transform().affine_inverse())
	var size: Vector2 = ThemeDB.fallback_font.get_string_size(
		status_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13
	)
	var origin := Vector2(14.0, 74.0)
	draw_rect(Rect2(origin - Vector2(8.0, 4.0), size + Vector2(16.0, 12.0)),
		Color(0.99, 0.98, 0.95, 0.9), true)
	draw_string(
		ThemeDB.fallback_font, origin + Vector2(0.0, 13.0), status_text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.12, 0.13, 0.15, 0.95)
	)
	draw_set_transform_matrix(Transform2D.IDENTITY)