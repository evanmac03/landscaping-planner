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

## Ink, for an entity whose layer cannot be resolved.
const INK := Color(0.13, 0.14, 0.16)


## The style an entity draws with: its own override, else its layer's.
static func style_for(entity: EntityScript, layer: LayerScript) -> LineStyleScript:
	if entity.style != null:
		return entity.style
	if layer != null:
		return layer.style()
	return LineStyleScript.new()


## The entity's linework as drawable polylines, with the dash pattern for the
## layer's linetype applied at a plot scale of 1:`plot_scale`.
##
## Empty for a text entity, which has a position but no outline.
static func strokes(entity: EntityScript, layer: LayerScript, plot_scale: float) -> Array[PackedVector2Array]:
	var outline := entity.outline()
	if outline.size() < 2:
		return []
	var style := style_for(entity, layer)
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


## The text of a text entity, or an empty string.
static func label_of(entity: EntityScript) -> String:
	return String(entity.meta.get("text", ""))


## Model-space position of a text entity.
static func label_position(entity: EntityScript) -> Vector2:
	return Vector2(entity.params[0], entity.params[1])