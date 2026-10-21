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
const RasterUnderlayScript := preload("res://scripts/draft/raster_underlay.gd")

## The pictures this canvas has already read, by path. The plan repaints every frame, and a picture
## under it is read from the disk **once**: an entry of `null` is a file that could not be read, kept
## so the disk is not asked for it again either.
var _underlay_textures: Dictionary = {}

## The shapes a selection band caught, by id, handed over by the drafting controller.
var _selected: Array[int] = []
## How a selected shape is traced: the plan's own highlight, at least this many
## pixels wide whatever the layer's weight is, so a hairline still shows its pick.
const SELECTION_COLOUR := Color(1.0, 0.62, 0.15)
const SELECTION_MIN_PIXELS := 3.0
## The box drawn round a selected label, in pixels: a label has no linework to trace.
const SELECTION_LABEL_BOX := 14.0

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
## The plant size `SHADOW_OFFSET` is authored for - the base shrub. A smaller symbol takes a
## proportionally smaller offset, so its shadow stays under it.
const SHADOW_REFERENCE := 1.5

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
## Where the plant being placed would go, and what the plan's own conditions say about that spot:
## `{point, radius, colour, label, verdict, species}`. Empty when nothing is being planted.
##
## The colour is the whole feature - green where the plant suits the ground, red where it does not -
## and it is computed by the ViewController, which is where the species, the document and the cursor
## already are. This node is told a point, a size and a colour, and draws them.
var plant_ghost: Dictionary = {}
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
	# The pictures lie **over the ground and under everything else**: the yard's own lawn, house and
	# paving are scenery read off the 3D meshes and drawn flat, and a tracing aid has to be visible
	# over them or there is nothing to trace; every plant standing on the ground and every line the
	# designer draws stays on top of it.
	_draw_underlays()
	for node: Node3D in _placeables:
		_draw_placeable(node)
	_draw_document()
	var marked: Node3D = grabbed if grabbed != null else hovered
	if marked != null:
		_draw_selection(marked, grabbed != null)
	_draw_plant_ghost()
	_draw_status()


## Opaque paper, so the hidden 3D render behind is fully covered even while the
## view cross-fades.
##
## The rectangle is the two *corners* of the viewport in local metres. A `Rect2` built from two points
## would take the second as a *size*, which covers the top-left quarter of the screen and nothing
## else - a defect that hides in the app because the yard's own lawn covers the paper, and shows up
## the moment a plan is drawn with no ground under it.
func _draw_paper() -> void:
	var near_corner: Vector2 = _screen_to_local(Vector2.ZERO)
	var far_corner: Vector2 = _screen_to_local(_viewport_size)
	draw_rect(Rect2(near_corner, far_corner - near_corner), PAPER, true)


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
	_draw_symbol(
		Vector2(node.global_position.x, node.global_position.z),
		PlanStyle.footprint_size(node),
		PlanStyle.symbol_of(node)
	)


# --- plant symbols -------------------------------------------------------------------


## Every symbol is drawn from one figure (see `PlantSymbols`), which is what keeps the plan and the
## swatch in a plant list from disagreeing about what a plant looks like. The inks are the plan's own:
## foliage symbol, its outline, and the marks - a trunk, a bloom, a tuft.
##
## The stroke weight a figure states is *relative*, not a length: the plan draws with a pen of a
## constant screen weight whatever the plant's size, the way every other stroke on this plan does,
## and `PEN_REFERENCE` is the outline weight of a canopy that the others are read against.
const PEN_PIXELS := 1.6
const PEN_REFERENCE := 0.07

const SYMBOL_INKS := {
	&"canopy": {"fill": CANOPY, "edge": CANOPY_LINE, "mark": TRUNK},
	&"conifer": {"fill": CANOPY, "edge": CANOPY_LINE, "mark": TRUNK},
	&"shrub": {"fill": CANOPY, "edge": CANOPY_LINE, "mark": CANOPY_LINE},
	&"grass": {"fill": CANOPY, "edge": CANOPY_LINE, "mark": CANOPY},
	&"groundcover": {"fill": CANOPY, "edge": CANOPY_LINE, "mark": CANOPY_LINE},
	&"vine": {"fill": CANOPY, "edge": CANOPY_LINE, "mark": CANOPY_LINE},
	&"fern": {"fill": CANOPY, "edge": CANOPY_LINE, "mark": CANOPY},
	&"bed": {"fill": BED_SOIL, "edge": BED_EDGE, "mark": BED_BLOOM},
}

## The marker's inks, and the answer for a symbol nobody has: the colour a prop the tables do not
## describe is drawn in, brought down for its own line. Built once at run time rather than written out
## as a constant, because a constant cannot be made by calling `darkened`.
static var _fallback_inks: Dictionary = {}


static func fallback_inks() -> Dictionary:
	if _fallback_inks.is_empty():
		_fallback_inks = {"fill": GENERIC, "edge": GENERIC.darkened(0.4), "mark": GENERIC.darkened(0.4)}
	return _fallback_inks


func _draw_symbol(centre: Vector2, size: Vector2, symbol: StringName) -> void:
	if size.x <= 0.0 or size.y <= 0.0:
		return
	var half: Vector2 = size * 0.5
	var parts: Array[Dictionary] = PlantSymbols.figure(symbol)
	var inks: Dictionary = SYMBOL_INKS.get(symbol, fallback_inks())
	# The shadow first, under everything: the fills again a little off their own centre, so a plant
	# reads as an object rather than a stain. An unknown prop is still drawn and still draggable,
	# just flagged as undescribed, so adding a new prop type never makes it vanish from the plan.
	#
	# The offset shrinks with the plant. It is authored for the 1.5 m shrub it grew up on, and at that
	# size it is a shadow; under a 30 cm groundcover the same 0.3 m puts the shadow in the next bed
	# along, where it reads as a second plant. `SHADOW_REFERENCE` is the size it is written for.
	var step: Vector2 = SHADOW_OFFSET * clampf(
		minf(size.x, size.y) / SHADOW_REFERENCE, 0.0, 1.0
	)
	for part: Dictionary in parts:
		if StringName(part["ink"]) == PlantSymbols.INK_FILL:
			_fill_part(part, centre + step, half, SHADOW)
	for part: Dictionary in parts:
		match StringName(part["ink"]):
			PlantSymbols.INK_FILL:
				_fill_part(part, centre, half, inks["fill"])
			PlantSymbols.INK_EDGE:
				_edge_part(part, centre, half, inks["edge"])
			_:
				_fill_part(part, centre, half, inks["mark"])


func _fill_part(part: Dictionary, centre: Vector2, half: Vector2, colour: Color) -> void:
	match StringName(part["kind"]):
		&"disc":
			draw_circle(_placed(part["c"], centre, half), float(part["r"]) * half.x, colour)
		&"rect":
			draw_rect(_box(part["half"], centre, half), colour, true)
		_:
			draw_colored_polygon(_placed_all(part["points"], centre, half), colour)


func _edge_part(part: Dictionary, centre: Vector2, half: Vector2, colour: Color) -> void:
	var width: float = maxf(PEN_PIXELS * float(part["w"]) / PEN_REFERENCE, 0.8) / pixels_per_metre
	match StringName(part["kind"]):
		&"disc":
			draw_arc(_placed(part["c"], centre, half), float(part["r"]) * half.x, 0.0, TAU, 48, colour, width)
		&"rect":
			draw_rect(_box(part["half"], centre, half), colour, false, width)
		_:
			draw_polyline(
				_placed_all(part["points"], centre, half), colour, width, bool(part["closed"])
			)


## One normalised point, as a position on the plan.
func _placed(point: Vector2, centre: Vector2, half: Vector2) -> Vector2:
	return centre + Vector2(point.x * half.x, point.y * half.y)


func _placed_all(points: PackedVector2Array, centre: Vector2, half: Vector2) -> PackedVector2Array:
	var out := PackedVector2Array()
	for point: Vector2 in points:
		out.append(_placed(point, centre, half))
	return out


## A normalised rectangle as a plan box.
func _box(part_half: Vector2, centre: Vector2, half: Vector2) -> Rect2:
	var extent := Vector2(part_half.x * half.x, part_half.y * half.y)
	return Rect2(centre - extent, extent * 2.0)


func _draw_selection(node: Node3D, active: bool) -> void:
	var centre := Vector2(node.global_position.x, node.global_position.z)
	var radius: float = PlanStyle.footprint_radius(node) + 0.45
	draw_arc(
		centre, radius, 0.0, TAU, 48,
		GRAB if active else HOVER,
		(3.0 if active else 2.0) / pixels_per_metre
	)


## The plant about to be placed, ringed in the colour of what the plan says about the spot.
##
## The same shape the selection ring uses, deliberately: a designer already reads a circle around a
## plant as "this is the object the click will hit", so the plant in hand is ringed the same way and
## only the colour is new. The wash under it is the **mature spread** - the room the plant will want,
## not a dot - because "there is no space for this" is one of the things the ground cannot tell you
## and the ring should not pretend otherwise.
##
## A ring's thickness is divided by the zoom for the same reason every other stroke here is: it is a
## mark on the plan, and it must stay the same weight on screen at every scale.
func _draw_plant_ghost() -> void:
	if plant_ghost.is_empty():
		return
	var point: Vector2 = plant_ghost.get("point", Vector2.ZERO)
	var radius: float = maxf(float(plant_ghost.get("radius", 0.4)), 2.5 / pixels_per_metre)
	var colour: Color = plant_ghost.get("colour", Color.WHITE)
	var wash := colour
	wash.a = 0.2
	draw_circle(point, radius, wash)
	draw_arc(point, radius, 0.0, TAU, 48, colour, 3.0 / pixels_per_metre)
	# A cross at the exact spot: a radius is a size, and the plant goes at a point.
	var tick: float = 5.0 / pixels_per_metre
	draw_line(point - Vector2(tick, 0.0), point + Vector2(tick, 0.0), colour, 1.5 / pixels_per_metre)
	draw_line(point - Vector2(0.0, tick), point + Vector2(0.0, tick), colour, 1.5 / pixels_per_metre)
	var label: String = String(plant_ghost.get("label", ""))
	if not label.is_empty():
		var screen: Vector2 = position + point * pixels_per_metre
		_draw_screen_text(
			screen + Vector2(radius * pixels_per_metre + 8.0, 4.0), label, 13, colour.darkened(0.3)
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
	# A new drawing has its own pictures: whatever the last one had read stays cached only as long as
	# the drawing that referred to it is the one on screen. Never a correctness problem - the cache is
	# keyed by path - but a drawing that has been closed should not hold somebody else's scan in memory.
	_underlay_textures.clear()
	queue_redraw()


## The pictures lying under the drawing: over the yard's own flat ground and structures, under every
## plant standing on that ground and under every line the designer draws. A tracing aid you cannot see
## through is not a tracing aid, which is why they start part-transparent and why one that has been put
## away is not drawn at all.
##
## A picture is not linework, so nothing here plots, snaps or measures it: this is a picture on the
## plan and the sheet exporter never sees it.
func _draw_underlays() -> void:
	if document == null:
		return
	for record: Dictionary in document.underlays:
		if not bool(record.get("visible", true)):
			continue
		var width := float(record.get("width_m", 0.0))
		if width <= 0.0:
			continue
		var texture := _underlay_texture(String(record.get("path", "")))
		if texture == null:
			continue
		var height := RasterUnderlayScript.height_of(record)
		# The picture is drawn in its own frame and turned about its own centre, so `width_m` and the
		# picture's own proportion are the only two numbers its size needs.
		draw_set_transform(
			RasterUnderlayScript.centre_of(record),
			deg_to_rad(float(record.get("rotation_deg", 0.0))),
			Vector2.ONE,
		)
		draw_texture_rect(
			texture,
			Rect2(Vector2(-width * 0.5, -height * 0.5), Vector2(width, height)),
			false,
			Color(1.0, 1.0, 1.0, clampf(float(record.get("opacity", 1.0)), 0.0, 1.0)),
		)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## The texture for a kept picture, read once and then remembered - including as nothing when the file
## is gone or cannot be read, because a plan that repaints goes on asking.
func _underlay_texture(path: String) -> Texture2D:
	if _underlay_textures.has(path):
		var read: Texture2D = _underlay_textures[path]
		return read
	var texture: Texture2D = RasterUnderlayScript.texture_of(path)
	_underlay_textures[path] = texture
	return texture


func _draw_document() -> void:
	if document == null:
		return
	for entity in document.visible_entities():
		_draw_entity(entity, document.layers.get_layer(entity.layer), 1.0)
	# What a selection band caught, drawn over the top rather than instead: the shape
	# is still the shape, and a highlight that replaced its own colour would make a
	# copy look like a different pen.
	for entity in document.visible_entities():
		if _selected.has(int(entity.id)):
			_draw_marked(entity, document.layers.get_layer(entity.layer))
	if ghost.get("entity", null) != null:
		_draw_entity(ghost["entity"], ghost.get("layer", null), 0.45)
	_draw_snap_marker()


## Point the canvas at the shapes a selection band caught.
func set_selection(ids: Array) -> void:
	var out: Array[int] = []
	for id in ids:
		out.append(int(id))
	if out == _selected:
		return
	_selected = out
	queue_redraw()


func selected_ids() -> Array[int]:
	return _selected.duplicate()


## A selected shape, traced over itself in the highlight colour and a little wider,
## so a thin line on a busy plan still says it has been picked.
func _draw_marked(entity, layer) -> void:
	var colour: Color = SELECTION_COLOUR
	var parts: Dictionary = DraftRenderScript.layout(
		entity, layer, display_scale, _units(), DraftDimensionScript.style_for(entity, document)
	)
	var style = parts["style"]
	var width: float = style.width_pixels(display_scale, pixels_per_metre) / pixels_per_metre
	width = maxf(width, SELECTION_MIN_PIXELS / pixels_per_metre)
	for stroke: PackedVector2Array in parts["lines"]:
		if stroke.size() < 2:
			continue
		draw_polyline(stroke, colour, width, true)
	# A shape with no linework at all - a label - is marked by a box at its anchor, so
	# a selection of labels is not a selection of nothing.
	if parts["lines"].is_empty() and entity.kind == DraftEntityScript.Kind.TEXT:
		var at: Vector2 = entity.point(0)
		var size := SELECTION_LABEL_BOX / pixels_per_metre
		draw_rect(Rect2(at - Vector2(size, size) * 0.5, Vector2(size, size)), colour, false, width)


## One entity, in its layer's colour and at its layer's weight, drawn from the
## shared layout so a dimension arrives here exactly as it will on the sheet.
func _draw_entity(entity, layer, alpha: float) -> void:
	var colour: Color = DraftRenderScript.screen_colour(layer)
	colour.a *= alpha
	var parts: Dictionary = DraftRenderScript.layout(
		entity, layer, display_scale, _units(), DraftDimensionScript.style_for(entity, document)
	)
	var style = parts["style"]
	# Godot's draw widths are in the canvas item's own units, which here are
	# metres, so a pixel width has to be divided back down by the zoom or the
	# stroke comes out `pixels_per_metre` times too thick.
	var width: float = style.width_pixels(display_scale, pixels_per_metre) / pixels_per_metre
	for stroke: PackedVector2Array in parts["lines"]:
		if stroke.size() < 2:
			continue
		draw_polyline(stroke, colour, width, true)
	# Marks are filled solids rather than strokes, so they are drawn as shapes of
	# their own: an arrowhead a triangle, a dot a small disc.
	for mark: Dictionary in parts["marks"]:
		if mark["kind"] == &"arrow":
			draw_colored_polygon(
				DraftDimensionScript.arrow_triangle(
					mark["tip"], mark["direction"], mark["size"], mark["width_ratio"]
				),
				colour
			)
		elif mark["kind"] == &"dot":
			draw_circle(Vector2(mark["at"]), float(mark["size"]) * 0.5, colour)
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