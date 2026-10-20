class_name DraftRender
extends RefCounted
## Turning document entities into something a view can draw.
##
## Shared by the flat plan and the 3D overlay on purpose. Line weights and dash
## phases are authored in paper millimetres and only become metres once a plot
## scale is chosen, so if the two views each did their own conversion they would
## drift apart. One implementation means they agree by construction.

const Geom := preload("res://scripts/draft/geom2d.gd")
const LineStyleScript := preload("res://scripts/draft/line_style.gd")
const EntityScript := preload("res://scripts/draft/draft_entity.gd")
const LayerScript := preload("res://scripts/draft/draft_layer.gd")
const DimensionScript := preload("res://scripts/draft/dimension.gd")

## Ink, for an entity whose layer cannot be resolved.
const INK := Color(0.13, 0.14, 0.16)

## Entities that annotate the sheet rather than describe the ground. They are
## drawn in the plan and plotted, but they have no business standing in the
## garden, so the 3D overlay passes over them.
const ANNOTATIONS: Array[int] = [EntityScript.Kind.DIMENSION, EntityScript.Kind.TEXT]


## Is this entity an annotation rather than a site feature?
static func is_annotation(entity: EntityScript) -> bool:
	return ANNOTATIONS.has(int(entity.kind))


## The style an entity draws with: its own override, else its layer's.
static func style_for(entity: EntityScript, layer: LayerScript) -> LineStyleScript:
	if entity.style != null:
		return entity.style
	if layer != null:
		return layer.style()
	return LineStyleScript.new()


## The style an entity's *own linework* is drawn in, which is not always a style that
## the entity or its layer chose.
##
## **A dimension's linework is continuous whatever its pen says.** The pen table gives
## each conventional colour a linetype, and 700-DIMENSION's slot carries the dashed pen
## that a property line legitimately uses — a pen is a good way of saying "this layer is
## drawn dashed", and the property boundary on the sample sheet proves it. It is not a
## good way of saying it about a dimension, whose line, extension lines and leader are
## *generated* geometry rather than something a person drew: every drafting standard
## draws them continuous, and a dashed dimension line is not a style choice, it is a
## mistake that reaches a client.
##
## This was found by looking at the plotted sheet — the first time in this project that
## the PDF was rasterised and read back — and it is the reason the rule lives here, where
## both the screen and the paper pass through, rather than in the exporter alone.
static func linework_style(entity: EntityScript, layer: LayerScript) -> LineStyleScript:
	return generated_linework_style(entity, style_for(entity, layer))


## A style with the linetype that generated linework must have, whatever it was given.
##
## Separate from `linework_style` because the exporter has already resolved a pen by the
## time it knows the entity, and both callers must end up with the same answer.
static func generated_linework_style(entity: EntityScript, style: LineStyleScript) -> LineStyleScript:
	if entity == null or style == null:
		return style
	if int(entity.kind) != EntityScript.Kind.DIMENSION:
		return style
	var continuous: LineStyleScript = style.copy()
	continuous.linetype = &"continuous"
	return continuous


## The entity's linework as drawable polylines, with the dash pattern for the
## layer's linetype applied at a plot scale of 1:`plot_scale`.
##
## Empty for a text entity, which has a position but no outline.
static func strokes(entity: EntityScript, layer: LayerScript, plot_scale: float) -> Array[PackedVector2Array]:
	var outline := entity.outline()
	if outline.size() < 2:
		return []
	var style := style_for(entity, layer)
	# pattern_at_scale answers in model metres, the same units as the outline, so
	# the two go into the dash walker together with no conversion. Getting this
	# wrong in either direction is quiet: a thousand times too long looks like a
	# solid line, and a thousand times too short looks like a solid line too.
	var pattern := style.pattern_at_scale(plot_scale)
	if pattern.is_empty():
		var single: Array[PackedVector2Array] = []
		single.append(outline)
		return single
	return Geom.dash_polyline(outline, pattern)


## What the layer draws in on screen.
static func screen_colour(layer: LayerScript) -> Color:
	if layer == null:
		return INK
	return layer.screen_colour


## What the layer draws in on paper, which is not the same thing: screen drawings
## are colour-coded to be readable, plotted sheets are usually monochrome.
static func plot_colour(layer: LayerScript) -> Color:
	if layer == null:
		return Color.BLACK
	return layer.plot_colour


## On-screen stroke width for a style, in pixels. Clamped to a hairline by the
## style itself so nothing disappears.
static func width_pixels(style: LineStyleScript, plot_scale: float, pixels_per_metre: float) -> float:
	return style.width_pixels(plot_scale, pixels_per_metre)


## Everything a view needs to draw one entity: the lines to stroke, the marks to
## fill, the labels to place, and the style to do it in a single colour and
## weight.
##
## This is the one entry point the plan, the sheet and the 3D overlay share, so a
## dimension reaches the paper by the same route it reaches the screen. `strokes`
## is the linework-only view of the same entity and stays because the 3D overlay
## has no way to draw filled triangles or text.
static func layout(
	entity: EntityScript,
	layer: LayerScript,
	plot_scale: float,
	units = null,
	dimension_style = null
) -> Dictionary:
	var lines: Array[PackedVector2Array] = []
	var marks: Array[Dictionary] = []
	var labels: Array[Dictionary] = []

	match entity.kind:
		EntityScript.Kind.DIMENSION:
			# Copied element by element rather than assigned across: a Dictionary
			# value loses its static array type, so the assignment would be
			# rejected and the caller's typing contract would be broken.
			var parts: Dictionary = DimensionScript.layout(
				entity, plot_scale, units, dimension_style
			)
			for part: PackedVector2Array in parts["lines"]:
				lines.append(part)
			for part: Dictionary in parts["marks"]:
				marks.append(part)
			for part: Dictionary in parts["labels"]:
				labels.append(part)
		EntityScript.Kind.TEXT:
			labels.append({
				"text": label_of(entity),
				"position": label_position(entity),
				"angle": text_rotation(entity),
				"height": text_model_height(entity, plot_scale),
			})
		_:
			lines = strokes(entity, layer, plot_scale)

	return {
		"lines": lines,
		"marks": marks,
		"labels": labels,
		# The linework style rather than the raw layer style, so a dimension's
		# generated line is continuous on the screen as well as on the paper.
		"style": linework_style(entity, layer),
	}


## A text entity's height as model metres. The height is authored in paper
## millimetres, like a line weight, so it prints the same size at any scale.
static func text_model_height(entity: EntityScript, plot_scale: float) -> float:
	var paper_mm := float(entity.meta.get("height", LineStyleScript.DEFAULT_TEXT_HEIGHT))
	return LineStyleScript.model_width_m(paper_mm, plot_scale)


## A text entity's rotation, in radians.
static func text_rotation(entity: EntityScript) -> float:
	return entity.params[2] if entity.params.size() > 2 else 0.0


## The text of a text entity, or an empty string.
static func label_of(entity: EntityScript) -> String:
	return String(entity.meta.get("text", ""))


## Model-space position of a text entity.
static func label_position(entity: EntityScript) -> Vector2:
	return Vector2(entity.params[0], entity.params[1])