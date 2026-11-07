class_name InkPainter
extends Node2D
## Paints the ink layer for one bake: the drawing itself, wobbled and weighted (§3.3).
##
## Two passes, the whole drawing at a time rather than per entity. A pencil line is a
## light broad pass with a darker narrow one on top, and interleaving the passes entity
## by entity would let the next entity's light pass cover the previous entity's dark one
## — which is the difference between "blocked in and firmed up" and "mud".
##
## Text is the one thing here drawn in the bake's own pixels rather than in model
## metres, because a glyph is rasterised at an integer pixel size. Everything else is
## model metres, like every other view in this project.

const RenderScript := preload("res://scripts/draft/draft_render.gd")
const DimScript := preload("res://scripts/draft/dimension.gd")
const LineStyleScript := preload("res://scripts/draft/line_style.gd")
const LayerSetScript := preload("res://scripts/draft/layer_set.gd")
const SketchStrokeScript := preload("res://scripts/vis/sketch_stroke.gd")
const SketchStyleScript := preload("res://scripts/vis/sketch_style.gd")

## Below this many pixels a note is not a note. A glyph rasterised at three pixels is a
## smudge, and a smudge in a proposal is worse than a note that is quietly missing.
const MIN_TEXT_PIXELS := 6.0

var _document: DraftDocument = null
var _plot_scale: float = 100.0
var _style: SketchStyleScript = null
var _texels_per_mm: float = 6.0
## The props on the plan, so their symbols are inked as well as washed. A planting plan
## without its plant symbols is a colour study.
var _props: Array[Node3D] = []


func _init(
	document,
	plot_scale: float,
	style: SketchStyleScript,
	texels_per_mm: float = 6.0,
	props: Array[Node3D] = []
) -> void:
	_document = document
	_plot_scale = plot_scale
	_style = style if style != null else SketchStyleScript.new()
	_texels_per_mm = texels_per_mm
	_props = props


func _draw() -> void:
	var items: Array[Dictionary] = parts()
	# The light broad pass over the whole drawing...
	for item: Dictionary in items:
		_draw_strokes(item, true)
	# ...then the dark narrow one over all of it, and the solid marks with it.
	for item: Dictionary in items:
		_draw_strokes(item, false)
		_draw_marks(item)
	for item: Dictionary in items:
		_draw_labels(item)


## Everything the ink layer draws, entity by entity.
##
## Separate from `_draw()` because this is the part that can be held against the
## working path: the painted plan and the flat plan must draw the same geometry, and a
## list of strokes can be compared where a call to `draw_polyline` cannot (AC-V3).
##
## `wobble` off gives the drawing as the working view has it, which is what that
## comparison is made on.
func parts(wobble: bool = true) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if _document == null:
		return out
	for entity in _document.plotting_entities():
		var layer = _document.layers.get_layer(entity.layer)
		var laid: Dictionary = RenderScript.layout(
			entity, layer, _plot_scale, _document.units,
			DimScript.style_for(entity, _document)
		)
		var lines: Array[PackedVector2Array] = []
		for line: PackedVector2Array in laid["lines"]:
			lines.append(line)
		if wobble:
			lines = SketchStrokeScript.wobble_strokes(
				lines, int(entity.id), _plot_scale,
				_style.wobble_mm, _style.segment_mm
			)
		out.append({
			"what": String(entity.layer),
			"style": laid["style"],
			"strokes": lines,
			"marks": laid["marks"],
			"labels": laid["labels"],
		})
	# The plant symbols, whose outline is the rim of the same ring the wash filled.
	for entry: Dictionary in symbol_parts(wobble):
		out.append(entry)
	return out


## One entry per planted prop: its symbol's outline, in the plant's own colour
## darkened.
##
## There is no layer to take an ink colour from, because a plant is not on a layer: it
## is a prop that happens to sit on one. So its ink is a dark version of its own wash
## colour, which is what a pencil over watercolour does.
func symbol_parts(wobble: bool = true) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var weight: float = LineStyleScript.new().plot_weight_mm
	var planting_layer = null
	if _document != null:
		planting_layer = _document.layers.get_layer(LayerSetScript.NEW_PLANTING)
		if planting_layer != null:
			weight = planting_layer.plot_weight_mm
	for node: Node3D in _props:
		var colour: Color = PlanStyle.wash_colour_for(node)
		if colour.a <= 0.0:
			# The same rule as the wash: a prop the style table does not describe is
			# left out rather than drawn in a guessed colour. It is still in the 3D
			# view and still in the flat plan, which is where it is finished.
			continue
		var ring: PackedVector2Array = PlanStyle.footprint_ring(node)
		if ring.size() < 3:
			continue
		var closed := ring.duplicate()
		closed.append(ring[0])
		var strokes: Array[PackedVector2Array] = []
		strokes.append(closed)
		if wobble:
			strokes = SketchStrokeScript.wobble_strokes(
				strokes, hash(node.name), _plot_scale,
				_style.wobble_mm, _style.segment_mm
			)
		var style := LineStyleScript.new()
		style.plot_weight_mm = weight
		style.screen_colour = colour.darkened(0.55)
		style.plot_colour = colour.darkened(0.55)
		out.append({
			"what": String(node.name),
			"style": style,
			"strokes": strokes,
			"marks": [],
			"labels": [],
		})
	return out


## One entity's linework. `under` draws the light broad pass instead of the dark one.
func _draw_strokes(item: Dictionary, under: bool) -> void:
	var style: LineStyleScript = item["style"]
	# The weight is a paper length, so it is converted by the one law the line weights
	# use and comes out the same width on the paper at any plot scale.
	var width_m: float = LineStyleScript.model_width_m(style.plot_weight_mm, _plot_scale)
	if under:
		width_m *= _style.ink_under_width
	else:
		width_m *= _style.ink_over_width
	var ink: Color = _ink_colour(item, under)
	for stroke: PackedVector2Array in item["strokes"]:
		if stroke.size() < 2:
			continue
		draw_polyline(stroke, ink, width_m, true)


## Arrowheads and dots, which are filled marks rather than strokes, so they belong to
## the dark pass.
func _draw_marks(item: Dictionary) -> void:
	var ink: Color = _ink_colour(item, false)
	for mark: Dictionary in item["marks"]:
		if mark["kind"] == &"arrow":
			draw_colored_polygon(
				DimScript.arrow_triangle(
					mark["tip"], mark["direction"], mark["size"], mark["width_ratio"]
				),
				ink
			)
		elif mark["kind"] == &"dot":
			draw_circle(Vector2(mark["at"]), float(mark["size"]) * 0.5, ink)


## Notes and dimension values, at the size their authored paper height asks for.
##
## Drawn in the bake's pixels because a glyph is rasterised at an integer pixel size: a
## note authored at 2.5 mm is 15 pixels tall at six texels per millimetre, and 0.0025 of
## a canvas unit would rasterise as nothing at all. The painter's own transform is
## cancelled with its inverse, exactly as the working plan reaches the screen, so the
## note lands where the geometry says and stays upright in paper terms.
func _draw_labels(item: Dictionary) -> void:
	var ink: Color = _ink_colour(item, false)
	var to_pixels: Transform2D = get_global_transform()
	var from_pixels: Transform2D = to_pixels.affine_inverse()
	for label: Dictionary in item["labels"]:
		var text := String(label["text"])
		if text.is_empty():
			continue
		# The height arrives in model metres, because that is the unit the rest of the
		# layout is in; as pixels it is the same paper millimetres at a texel density.
		var height_px: float = maxf(
			MIN_TEXT_PIXELS,
			float(label["height"]) * 1000.0 / _plot_scale * _texels_per_mm
		)
		var at: Vector2 = to_pixels * Vector2(label["position"])
		var angle: float = float(label["angle"])
		draw_set_transform_matrix(from_pixels * Transform2D(angle, at))
		draw_string(
			ThemeDB.fallback_font, Vector2.ZERO, text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, int(height_px), ink
		)
	draw_set_transform_matrix(Transform2D.IDENTITY)


## The colour a layer's ink is drawn in.
##
## The layer's *plotted* colour, not its screen colour: a painted plan that used screen
## colours would be a diagram of the layer table rather than a drawing. The under pass is
## lightened toward the paper, which is what makes it read as a broad light stroke
## underneath rather than as a second line beside the first.
func _ink_colour(item: Dictionary, under: bool) -> Color:
	var style: LineStyleScript = item["style"]
	var ink: Color = style.plot_colour
	if not under:
		return Color(ink, _style.ink_over_alpha)
	return Color(ink.lerp(_style.paper, _style.ink_lighten), _style.ink_under_alpha)