class_name HatchFill
extends RefCounted
## Region fills: the pattern that covers the ground under a designer's linework.
##
## A fill is not geometry in its own right. It is a *pattern over a region*, and the region is a
## closed shape somebody has already drawn, so this module takes one (or a set, when a shape has
## holes) and returns the linework: parallel hatch at an angle, a crosshatch, a dense solid, or a
## grid of point symbols. The controller writes those segments as ordinary lines on `600-HATCH`,
## which is what the plot, the key and the whole drawing already understand - there is no fill
## primitive in the entity model and there does not need to be one.
##
## Two things are worth stating because they are easy to get wrong:
##
## * **Spacing is a paper length, not a model one.** A mulch hatch is drawn 2 mm apart *on the
##   sheet*, whatever the scale, because it is a texture the eye reads rather than a measured
##   distance. The drawing stores its geometry in model metres, so the paper figure is converted by
##   the plot scale at the moment of filling (`model_spacing_m`). A drawing later plotted at a
##   different scale will show a different density: that is the honest consequence of hatching into
##   geometry, and the reason the number is quoted in millimetres.
## * **A hole must stay unfilled** (REQ 4.6.4). Hatch gets that for free: `Geometry2D`'s even-odd
##   pairing over the rings leaves a hole empty without a special case. A symbol grid gets it by
##   rejecting every point that falls inside an inner ring.
##
## The pattern set and the two hard requirements are docs/drafting-subsystem-spec.md §4.6.

const Geom := preload("res://scripts/draft/geom2d.gd")
const PlotScaleScript := preload("res://scripts/draft/plot_scale.gd")

const SOLID := &"solid"
const HATCH := &"hatch"
const CROSSHATCH := &"crosshatch"
const STIPPLE := &"stipple"

const SYMBOL_DOT := &"dot"
const SYMBOL_CROSS := &"cross"

## The patterns a fill may be, in the order a drop-down offers them.
const PATTERNS: Array[StringName] = [HATCH, CROSSHATCH, STIPPLE, SOLID]
## The point symbols a stipple may lay down.
const SYMBOLS: Array[StringName] = [SYMBOL_DOT, SYMBOL_CROSS]
## Spacing choices, in paper millimetres. A person picks a density, not a number: 1 mm is tight,
## 10 mm is sparse, and the ones between are the conventional textures a planting plan uses.
const SPACING_MM: Array[float] = [1.0, 1.5, 2.0, 3.0, 5.0, 10.0]
## Angle choices, in degrees.
const ANGLES_DEG: Array[float] = [0.0, 45.0, 90.0, 135.0]
## How dense a solid fill is, in paper millimetres: fine enough to read as a tone, not so fine that
## the sheet is a pen-per-line argument. It is crosshatched, so it looks solid whichever way it is
## turned.
const SOLID_MM := 0.6
## A point symbol's size as a fraction of the grid spacing.
const SYMBOL_FRACTION := 0.35
## The most segments one fill may write, so a bed hatched at a hair's spacing is refused in words
## rather than freezing the drawing.
const MAX_LINES := 4000
## Briefly, a dot is a small diamond and a cross is two strokes: both are linework, so both plot and
## both can be erased and selected like anything else.
const DOT_ARMS := 4


## The pattern names, for a drop-down.
static func pattern_words(pattern: StringName) -> String:
	match pattern:
		SOLID:
			return "Solid"
		CROSSHATCH:
			return "Crosshatch"
		STIPPLE:
			return "Symbol stipple"
		_:
			return "Line hatch"


static func is_pattern(pattern: StringName) -> bool:
	return PATTERNS.has(pattern)


static func symbol_words(symbol: StringName) -> String:
	return "Cross" if symbol == SYMBOL_CROSS else "Dot"


static func is_symbol(symbol: StringName) -> bool:
	return SYMBOLS.has(symbol)


## How many model metres a paper spacing is, at a plot scale. `scale` is the drawing's own ratio
## (100 means 1:100), read the same way the plotter reads it.
static func model_spacing_m(paper_mm: float, scale: float) -> float:
	return paper_mm * PlotScaleScript.model_metres_per_paper_mm(scale)


## The model spacing a solid fill uses, from its fixed paper density.
static func solid_spacing_m(scale: float) -> float:
	return model_spacing_m(SOLID_MM, scale)


static func spacing_words(paper_mm: float) -> String:
	return "%s mm" % _number_words(paper_mm)


static func angle_words(degrees: float) -> String:
	return "%s deg" % _number_words(degrees)


## A number without a trailing zero, so a whole millimetre does not read as "2.0".
static func _number_words(value: float) -> String:
	if absf(value - roundf(value)) < 1.0e-6:
		return "%d" % int(roundf(value))
	return "%.1f" % value


## Fill one region.
##
## `rings` is the region's outline followed by any holes, each a closed ring (first point not
## repeated). `pattern`, `spacing_m` (model metres), the angle in radians and the stipple `symbol`
## are the whole of what a fill is. Returns:
##
##     {ok, reason, lines: Array[PackedVector2Array], marks: int, pattern}
##
## `lines` is the stroke linework, ready to become LINE entities; `marks` is how many point symbols
## were laid for a stipple (0 for the line patterns). A refusal carries `reason` and no lines.
static func fill(
	rings: Array, pattern: StringName, spacing_m: float, angle_rad: float,
	symbol: StringName = SYMBOL_DOT
) -> Dictionary:
	var region := _clean(rings)
	if region.is_empty():
		return _failed("there is no closed region to fill")
	if not is_pattern(pattern):
		return _failed("there is no such fill pattern")
	if spacing_m <= Geom.EPS:
		return _failed("the fill has no spacing")
	var lines: Array[PackedVector2Array] = []
	var marks := 0
	match pattern:
		HATCH:
			lines = Geom.hatch_lines(region, spacing_m, angle_rad)
		CROSSHATCH:
			lines = Geom.hatch_lines(region, spacing_m, angle_rad)
			lines.append_array(Geom.hatch_lines(region, spacing_m, angle_rad + PI * 0.5))
		SOLID:
			# Fixed perpendicular passes, so a solid area reads solid however it is drawn.
			lines = Geom.hatch_lines(region, spacing_m, 0.0)
			lines.append_array(Geom.hatch_lines(region, spacing_m, PI * 0.5))
		STIPPLE:
			for at: Vector2 in grid_points(region, spacing_m):
				marks += 1
				lines.append_array(symbol_marks(at, symbol, spacing_m))
	if lines.size() > MAX_LINES:
		return _failed("that spacing is finer than this region can carry: it would draw %d marks"
			% lines.size())
	if lines.is_empty():
		return _failed("that region is too small for a fill at this spacing")
	return {
		"ok": true, "reason": "", "lines": lines, "marks": marks,
		"pattern": pattern, "symbol": symbol,
	}


## The grid of symbol positions inside a region, at a model spacing. The outer ring sets the grid's
## extent and `Geometry2D.is_point_in_polygon` keeps only the points inside it (REQ 4.6.3); a point
## inside any inner ring is a hole and is dropped (REQ 4.6.4).
static func grid_points(region: Array, spacing_m: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	var rings := _clean(region)
	if rings.is_empty() or spacing_m <= Geom.EPS:
		return out
	for at: Vector2 in Geom.fill_grid(rings[0], spacing_m):
		if not _in_a_hole(rings, at):
			out.append(at)
	return out


## The strokes of one point symbol at a position, sized against the grid so two symbols never touch.
static func symbol_marks(
	at: Vector2, symbol: StringName, spacing_m: float
) -> Array[PackedVector2Array]:
	var half := maxf(spacing_m * SYMBOL_FRACTION, Geom.EPS) * 0.5
	var out: Array[PackedVector2Array] = []
	if symbol == SYMBOL_CROSS:
		out.append(PackedVector2Array([at + Vector2(-half, 0.0), at + Vector2(half, 0.0)]))
		out.append(PackedVector2Array([at + Vector2(0.0, -half), at + Vector2(0.0, half)]))
		return out
	# A dot: a small diamond, closed by repeating its first point.
	var corners := PackedVector2Array()
	for index in DOT_ARMS:
		var angle := TAU * float(index) / float(DOT_ARMS) - PI * 0.5
		corners.append(at + Vector2(cos(angle), sin(angle)) * half)
	corners.append(corners[0])
	out.append(corners)
	return out


## A filled area, in one line: "Crosshatch, 84 lines" or "Symbol stipple, 312 dots".
static func describe(result: Dictionary) -> String:
	if not bool(result.get("ok", false)):
		return String(result.get("reason", "the fill could not be made"))
	var pattern := StringName(result.get("pattern", HATCH))
	if pattern == STIPPLE:
		return "%s, %d %s" % [
			pattern_words(pattern), int(result.get("marks", 0)),
			"cross" if result.get("symbol", SYMBOL_DOT) == SYMBOL_CROSS else "dot",
		]
	return "%s, %d lines" % [pattern_words(pattern), (result.get("lines", []) as Array).size()]


static func _clean(rings: Array) -> Array[PackedVector2Array]:
	var out: Array[PackedVector2Array] = []
	for ring: Variant in rings:
		if ring is PackedVector2Array and (ring as PackedVector2Array).size() >= 3:
			out.append(ring as PackedVector2Array)
	return out


static func _in_a_hole(region: Array[PackedVector2Array], at: Vector2) -> bool:
	for index in range(1, region.size()):
		if Geom.point_in_polygon(at, region[index]):
			return true
	return false


static func _failed(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason, "lines": [], "marks": 0}