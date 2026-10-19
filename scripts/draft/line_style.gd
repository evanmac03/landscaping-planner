class_name LineStyle
extends RefCounted
## Line weight, dash pattern and colour for the drafting subsystem.
##
## Weight is a **plotted** property: a 0.35 mm line is 0.35 mm on every sheet at
## every scale, and what it covers in the model varies with the scale. It is
## therefore authored in paper millimetres and converted by one equation
## (docs/drafting-subsystem-spec.md REQ 4.2):
##
##     model_width_m = plot_weight_mm * S / 1000
##     screen_px     = model_width_m * pixels_per_metre
##
## At true sheet zoom that reduces exactly to `plot_weight_mm *
## pixels_per_paper_mm`, so the screen shows what the plot will produce.

## ISO 128 weight series, doubling every three steps (ratio sqrt(2)).
const WEIGHTS: Array[float] = [0.13, 0.18, 0.25, 0.35, 0.50, 0.70, 1.00, 1.40, 2.00]
const HAIRLINE := 0.13

## ISO 3098 text heights, in paper millimetres.
const TEXT_HEIGHTS: Array[float] = [1.8, 2.5, 3.5, 5.0, 7.0]
const DEFAULT_TEXT_HEIGHT := 2.5

## Dash patterns in **paper millimetres**, alternating on and off starting on.
const PATTERNS := {
	&"continuous": [],
	&"dashed": [6.0, 2.0],
	&"hidden": [3.0, 1.5],
	&"centre": [12.0, 2.0, 2.0, 2.0],
	&"dotted": [0.25, 1.5],
	&"phantom": [12.0, 2.0, 4.0, 2.0],
}

## The drafting hierarchy: weight encodes importance, so the drawing reads at a
## glance and stays legible when reproduced. Layer defaults are drawn from this
## table so a conventional drawing needs no per-entity weight (REQ 4.4.1).
const HIERARCHY := {
	&"sheet_border": 0.70,
	&"structure_cut": 0.50,
	&"hardscape_edge": 0.50,
	&"property_line": 0.35,
	&"bed_edge": 0.35,
	&"existing_hardscape": 0.25,
	&"turf": 0.25,
	&"easement": 0.18,
	&"annotation": 0.18,
	&"plant_symbol": 0.13,
	&"hatch": 0.13,
	&"guide": 0.13,
}

## Exact: one point is 1/72 inch.
const POINTS_PER_MM := 72.0 / 25.4

var plot_weight_mm: float = 0.25
var linetype: StringName = &"continuous"
var plot_colour: Color = Color.BLACK
var screen_colour: Color = Color.BLACK
## Off renders every weight as 1 px, which is what a designer wants when tracing
## dense detail (REQ 4.2.3).
var display_lineweights: bool = true


# --- the weight law -----------------------------------------------------------------


## Width this weight covers in the model, in metres, at a plot scale of 1:S.
static func model_width_m(plot_weight_mm: float, scale: float) -> float:
	return plot_weight_mm * scale / 1000.0


## Dash pattern converted to model units at a plot scale of 1:S.
static func pattern_model_mm(pattern_mm: Array[float], scale: float) -> Array[float]:
	var out: Array[float] = []
	for length: float in pattern_mm:
		out.append(length * scale / 1000.0)
	return out


## Text height converted to model units at a plot scale of 1:S.
static func text_model_size(text_height_mm: float, scale: float) -> float:
	return text_height_mm * scale / 1000.0


## Width to draw at, in pixels. Clamped to 1 px so hairlines stay visible.
func width_pixels(scale: float, pixels_per_metre: float) -> float:
	if not display_lineweights:
		return 1.0
	return maxf(1.0, model_width_m(plot_weight_mm, scale) * pixels_per_metre)


## Width to emit when writing a vector sheet, in PDF points.
func width_points() -> float:
	return plot_weight_mm * POINTS_PER_MM


## The dash pattern for this style at a plot scale of 1:S, in model units.
func pattern_at_scale(scale: float) -> Array[float]:
	return pattern_model_mm(pattern_for(linetype), scale)


## Instantiate this script by path.
##
## `LineStyle.new()` cannot be used here: the global class registry is rewritten
## by the editor's file-system scan, so a class_name that has not been registered
## yet is not resolvable as a *value* (type annotations are fine). On a fresh
## clone .godot/ is absent entirely, so a headless run hits the same wall.
## Resolving by path always works.
static func _new() -> LineStyle:
	return (load("res://scripts/draft/line_style.gd") as GDScript).new()


func copy() -> LineStyle:
	var other := _new()
	other.plot_weight_mm = plot_weight_mm
	other.linetype = linetype
	other.plot_colour = plot_colour
	other.screen_colour = screen_colour
	other.display_lineweights = display_lineweights
	return other


# --- lookups ------------------------------------------------------------------------


## A properly typed pattern array for a linetype, so callers do not have to deal
## with the untyped arrays held in the const table.
static func pattern_for(linetype: StringName) -> Array[float]:
	var raw: Array = PATTERNS.get(linetype, [])
	var out: Array[float] = []
	for value in raw:
		out.append(float(value))
	return out


static func has_linetype(linetype: StringName) -> bool:
	return PATTERNS.has(linetype)


static func linetype_names() -> Array[StringName]:
	var out: Array[StringName] = []
	for key: StringName in PATTERNS:
		out.append(key)
	return out


## The nearest standard weight to an arbitrary value, for importing styles.
## A tie resolves toward the lighter weight, so an ambiguous import never
## thickens a drawing unexpectedly.
static func nearest_weight(weight_mm: float) -> float:
	var best := WEIGHTS[0]
	var best_distance := absf(weight_mm - best)
	for candidate: float in WEIGHTS:
		var distance := absf(weight_mm - candidate)
		if distance < best_distance:
			best = candidate
			best_distance = distance
	return best


static func hierarchy_weight(role: StringName) -> float:
	return HIERARCHY.get(role, 0.25)


static func hierarchy_roles() -> Array[StringName]:
	var out: Array[StringName] = []
	for key: StringName in HIERARCHY:
		out.append(key)
	return out