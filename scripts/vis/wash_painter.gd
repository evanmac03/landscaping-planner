class_name WashPainter
extends Node2D
## Paints the wash layer for one bake: the colours under the drawing (§4.4).
##
## Plain CanvasItem calls rather than a shader, because the mottle is a property of
## the *region* — three offset passes of one polygon — and not of the pixels. The
## compositor adds paper, grain, the wet edge and the ink on top (§3.5).
##
## The painter works in **model metres**, like every other view in this project, and
## the paper millimetres it is authored in (bleed, mottle) are converted by the same
## law the line weights use. Its transform is set by the baker, which owns the one
## framing both layers share (§3.4) — a painter that positioned itself would be a
## second opinion about where the drawing sits on the paper.

const WashTableScript := preload("res://scripts/vis/wash_table.gd")
const CadSolidScript := preload("res://scripts/vis/cad_solid.gd")
const PlanStyleScript := preload("res://scripts/plan_style.gd")
const LineStyleScript := preload("res://scripts/draft/line_style.gd")

## The three passes, as a share of the pigment and an offset in bleed units: the
## flood, then the body once the paper has taken most of the water, then the pool
## where it collected. Three is the number that reads as pigment; a fourth adds
## nothing a client can see.
const PASSES: Array = [
	{"alpha": 1.00, "offset": Vector2(0.25, -0.18)},
	{"alpha": 0.55, "offset": Vector2(-0.40, 0.30)},
	{"alpha": 0.30, "offset": Vector2(0.60, 0.60)},
]

## Points around a plant's canopy. Enough that the edge has something to wander
## along once it is wobbled, without the canopy reading as a polygon.
const CANOPY_POINTS := 28

var _document = null
var _plot_scale: float = 100.0
var _props: Array[Node3D] = []


func _init(document, plot_scale: float, props: Array[Node3D] = []) -> void:
	_document = document
	_plot_scale = plot_scale
	_props = props


func _draw() -> void:
	for region: Dictionary in regions():
		_paint_region(region["region"], region["wash"])


## Every region that washes, in the order it is painted: the drawing's own draw
## order first, then a canopy for every planted prop, so foliage stands over the
## beds it grows in rather than under them (REQ-V4.3).
##
## Separate from `_draw()` because this is the part with a promise in it. "A bed
## washes and a dimension does not" is a list, and a list can be asserted; what
## `draw_colored_polygon` did with it cannot be (REQ-V14.2).
func regions() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if _document != null:
		for entity in _document.plotting_entities():
			var layer = _document.layers.get_layer(entity.layer)
			if layer == null:
				continue
			var wash: Dictionary = WashTableScript.wash_for(layer.name)
			if wash.is_empty():
				continue
			var region: PackedVector2Array = CadSolidScript.outline_of(entity)
			if region.size() < CadSolidScript.MIN_RING_POINTS:
				continue
			out.append({
				"region": region,
				"wash": wash,
				"seed": int(entity.id),
				"what": String(layer.name),
			})
	# Canopies last and largest first, which is the order the working plan draws its
	# symbols in: a shrub sits in front of the tree behind it.
	for entry: Dictionary in canopies():
		out.append(entry)
	return out


## One entry per planted prop that has a wash colour, largest first.
##
## Props are 3D nodes rather than entities, so this is where the wash meets the
## model. A prop whose species the style table does not describe gets no entry at
## all — see `PlanStyle.wash_colour_for`.
func canopies() -> Array[Dictionary]:
	var sorted: Array[Node3D] = _props.duplicate()
	var by_radius := func(a: Node3D, b: Node3D) -> bool:
		return PlanStyleScript.footprint_radius(a) > PlanStyleScript.footprint_radius(b)
	sorted.sort_custom(by_radius)
	var out: Array[Dictionary] = []
	for node: Node3D in sorted:
		var colour: Color = PlanStyleScript.wash_colour_for(node)
		if colour.a <= 0.0:
			continue
		var wash: Dictionary = WashTableScript.wash_for(WashTableScript.PLANTING_PROPS)
		if wash.is_empty():
			continue
		# The species colour replaces the table's own: the table says how a canopy
		# behaves, the prop's style entry says what colour it is (REQ-V4.4).
		var canopy := wash.duplicate()
		canopy["colour"] = colour
		out.append({
			"region": _canopy_region(node),
			"wash": canopy,
			"seed": hash(node.name),
			"what": String(node.name),
		})
	return out


## A plant's footprint as a closed ring in model metres, in the shape the working
## plan draws it.
##
## A circle is right for a trunk and a canopy and wrong for a bed: the working view
## draws a bed as a rectangle 2.6 m by 1.4 m, and a wash that came out round would
## put a disc under an oblong symbol. So the shape follows the same table as the
## colour, which is the one entry that describes the prop in the plan.
func _canopy_region(node: Node3D) -> PackedVector2Array:
	var size: Vector2 = PlanStyleScript.footprint_size(node)
	var centre := Vector2(node.global_position.x, node.global_position.z)
	if size.x <= 0.0 or size.y <= 0.0:
		return PackedVector2Array()
	var symbol: int = int(PlanStyleScript.spec_for(node.scene_file_path)["symbol"])
	if symbol in [PlanStyleScript.Symbol.TREE, PlanStyleScript.Symbol.SHRUB]:
		return _disc(centre, size.x * 0.5)
	return _rectangle(centre, size)


## A ring around a disc.
func _disc(centre: Vector2, radius: float) -> PackedVector2Array:
	var ring_points := PackedVector2Array()
	for step in CANOPY_POINTS:
		var angle: float = TAU * float(step) / float(CANOPY_POINTS)
		ring_points.append(centre + Vector2(cos(angle), sin(angle)) * radius)
	return ring_points


## A ring around a rectangle, as its four corners.
func _rectangle(centre: Vector2, size: Vector2) -> PackedVector2Array:
	var half := size * 0.5
	return PackedVector2Array([
		centre + Vector2(-half.x, -half.y),
		centre + Vector2(half.x, -half.y),
		centre + Vector2(half.x, half.y),
		centre + Vector2(-half.x, half.y),
	])


## A wash's bleed in model metres, by the same law the line weights use.
##
## Public because it is the one place the wash converts a paper length, and a
## conversion that can be asserted is a conversion that cannot quietly be a thousand
## times too big in one direction or too small in the other.
func bleed_m(wash: Dictionary) -> float:
	return LineStyleScript.model_width_m(float(wash["bleed_mm"]), _plot_scale)


## One region, painted as three offset passes.
##
## Every length the wash is authored in is a paper length, so it is converted here
## and nowhere else: `model_width_m` is the same law the line weights use, which is
## what stops the wash and the ink disagreeing about how big a millimetre is.
##
## The region's seed arrives in `regions()` and is not used here yet: the wobble that
## makes a wash edge wander is the ink pass's geometry (§3.2, phase 2), and until
## there is one, the three offset passes are the whole of the mottle.
func _paint_region(region: PackedVector2Array, wash: Dictionary) -> void:
	var colour: Color = wash["colour"]
	var opacity: float = float(wash["opacity"])
	var bleed: float = bleed_m(wash)
	for pass_index in PASSES.size():
		var pass_data: Dictionary = PASSES[pass_index]
		var offset: Vector2 = pass_data["offset"] * bleed
		var shifted := PackedVector2Array()
		for point: Vector2 in region:
			shifted.append(point + offset)
		# Each pass carries its own share of the pigment, so the overlap darkens the
		# way a second wash over a damp one does.
		draw_colored_polygon(
			shifted, Color(colour, opacity * float(pass_data["alpha"]))
		)


## The seed a region's edge wanders from. Derived from the entity's id or the
## prop's name, never from the frame or the camera, so the same drawing wobbles the
## same way in every frame and every render (REQ-V3.1).
static func seed_of(entry: Dictionary) -> int:
	return int(entry.get("seed", 0))