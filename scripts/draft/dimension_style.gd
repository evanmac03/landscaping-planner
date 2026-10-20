class_name DraftDimensionStyle
extends RefCounted
## How a dimension is drawn: the mark at each end, the sizes, and how the
## measurement is written.
##
## Every size here is a **paper** measurement in millimetres, for the same reason
## a line weight is: an arrowhead that grew with the drawing would be unreadable
## on a 1:500 sheet and absurd on a 1:20 detail. Converting them to model metres
## at the scale in force is the layout's job, not the style's.
##
## A practice's standard lives on the document and a single dimension may
## override it, which is exactly the shape an entity's line style already has, so
## there is one rule to remember rather than two.
##
## Sibling modules are reached by preload rather than by global class name: the
## global registry is rewritten by the editor's scan, so a reference to a newly
## added script resolves sometimes and not others.

const LineStyleScript := preload("res://scripts/draft/line_style.gd")

## What sits at each end of the dimension line. Ticks and dots are not
## decorations: which one a drawing uses is a regional and professional
## convention, and a surveyor reading a tick where they expect an arrowhead is
## reading the wrong drawing.
enum Mark {
	ARROW,
	TICK,
	DOT,
	NONE,
}

const MARK_NAMES := {
	Mark.ARROW: "arrow",
	Mark.TICK: "tick",
	Mark.DOT: "dot",
	Mark.NONE: "none",
}

## Half-width of an arrowhead as a fraction of its length. A drafting arrow is
## long and slim; a fat triangle reads as a road sign.
const DEFAULT_WIDTH_RATIO := 0.28
## How far a tick leans off the dimension line, in degrees.
const TICK_ANGLE_DEGREES := 45.0

var mark: Mark = Mark.ARROW
## Length of an arrowhead or tick, or the diameter of a dot, on the paper.
var mark_size_mm: float = 2.5
var mark_width_ratio: float = DEFAULT_WIDTH_RATIO

var text_height_mm: float = LineStyleScript.DEFAULT_TEXT_HEIGHT
## The gap between the dimension line and the text beside it.
var text_gap_mm: float = 1.0
## Put the text above the dimension line rather than below it. Above is the
## convention when the line is below the thing being measured, which is the
## usual case; the other way round suits a dimension set inside a building.
var text_above: bool = true
## Decimals the measurement is written to, or -1 to leave the precision to the
## drawing rather than to the style. It applies to the metric decimal form only:
## an imperial document writes feet and inches, where the fraction *is* the
## precision and a decimal count would mean something else.
var text_decimals: int = -1
## What "leave it to the drawing" means. A dimension can only be read as finely
## as it can be drawn - at 1:100 a hundredth of a metre is a tenth of a
## millimetre of pencil - so the shipped standards take their precision from the
## plot scale. Switch this off and the document's units decide instead, which is
## what an office whose standard is one fixed precision wants.
var scale_aware: bool = true

## Extension lines run from the measured point out past the dimension line, and
## a dimension without them has nothing tying it to what it measures.
var extension_lines: bool = true
## The clear gap between a measured point and the start of its extension line.
var extension_gap_mm: float = 1.5
## How far an extension line runs past the dimension line.
var extension_overshoot_mm: float = 1.5


static func _new() -> DraftDimensionStyle:
	return (load("res://scripts/draft/dimension_style.gd") as GDScript).new()


# --- the shipped standards ----------------------------------------------------------


## An arrowhead at each end and the measurement above the line: the default, and
## what a landscape plan almost always wants.
static func architectural() -> DraftDimensionStyle:
	return _new()


## Ticks instead of arrowheads, the surveying and engineering convention. An
## oblique stroke is easier to see where a mark has to crowd in between two
## measurements that nearly touch.
static func engineering() -> DraftDimensionStyle:
	var style := _new()
	style.mark = Mark.TICK
	style.extension_gap_mm = 1.0
	style.extension_overshoot_mm = 1.0
	return style


## No mark at the ends and no extension lines, for a busy plan where the
## decoration would be lost in the linework and only the value matters.
static func minimal() -> DraftDimensionStyle:
	var style := _new()
	style.mark = Mark.NONE
	style.extension_lines = false
	return style


# --- derived settings ---------------------------------------------------------------


## A sensible precision for a plot scale. A dimension can only be read as finely
## as it can be drawn: at 1:100 a hundredth of a metre is a tenth of a
## millimetre on the paper, which is not a line anyone can draw or check.
static func decimals_for_scale(plot_scale: float) -> int:
	if plot_scale <= 20.0:
		return 3
	if plot_scale <= 100.0:
		return 2
	if plot_scale <= 500.0:
		return 1
	return 0


## The decimals this style writes a metric measurement to at a given plot scale,
## or -1 for "the document's units decide after all".
##
## Resolution order is the same as everywhere else in the drafting module: what
## the dimension says, then what the drawing's standard says, then what the units
## say. A style that names a count names it for every scale, which is what an
## office standard is.
func decimals_at(plot_scale: float) -> int:
	if text_decimals >= 0:
		return text_decimals
	return decimals_for_scale(plot_scale) if scale_aware else -1


## This style with its precision set for a plot scale.
func with_scale(plot_scale: float) -> DraftDimensionStyle:
	var scaled := copy()
	scaled.text_decimals = decimals_for_scale(plot_scale)
	return scaled


# --- copying and persistence --------------------------------------------------------


func copy() -> DraftDimensionStyle:
	var other := _new()
	other.mark = mark
	other.mark_size_mm = mark_size_mm
	other.mark_width_ratio = mark_width_ratio
	other.text_height_mm = text_height_mm
	other.text_gap_mm = text_gap_mm
	other.text_above = text_above
	other.text_decimals = text_decimals
	other.scale_aware = scale_aware
	other.extension_lines = extension_lines
	other.extension_gap_mm = extension_gap_mm
	other.extension_overshoot_mm = extension_overshoot_mm
	return other


func to_dict() -> Dictionary:
	return {
		"mark": int(mark),
		"mark_size_mm": mark_size_mm,
		"mark_width_ratio": mark_width_ratio,
		"text_height_mm": text_height_mm,
		"text_gap_mm": text_gap_mm,
		"text_above": text_above,
		"text_decimals": text_decimals,
		"scale_aware": scale_aware,
		"extension_lines": extension_lines,
		"extension_gap_mm": extension_gap_mm,
		"extension_overshoot_mm": extension_overshoot_mm,
	}


## Reading a style back is forgiving on purpose: a file written by an older
## version, or hand-edited, should load with sensible values rather than refuse.
static func from_dict(data: Dictionary) -> DraftDimensionStyle:
	var style := _new()
	var raw_mark := int(data.get("mark", Mark.ARROW))
	style.mark = Mark.ARROW if raw_mark < 0 or raw_mark >= Mark.values().size() else raw_mark
	style.mark_size_mm = float(data.get("mark_size_mm", 2.5))
	style.mark_width_ratio = float(data.get("mark_width_ratio", DEFAULT_WIDTH_RATIO))
	style.text_height_mm = float(data.get("text_height_mm", LineStyleScript.DEFAULT_TEXT_HEIGHT))
	style.text_gap_mm = float(data.get("text_gap_mm", 1.0))
	style.text_above = bool(data.get("text_above", true))
	style.text_decimals = int(data.get("text_decimals", -1))
	style.scale_aware = bool(data.get("scale_aware", true))
	style.extension_lines = bool(data.get("extension_lines", true))
	style.extension_gap_mm = float(data.get("extension_gap_mm", 1.5))
	style.extension_overshoot_mm = float(data.get("extension_overshoot_mm", 1.5))
	return style


func describe() -> String:
	return "dimension style: %s marks, %.2f mm, %s text, %s" % [
		MARK_NAMES.get(mark, "?"), mark_size_mm, "above" if text_above else "below",
		precision_description(),
	]


## How this style arrives at its precision, in words, for a status line. The
## scale itself is not named because the style does not hold one: it is handed
## the scale at the moment of drawing.
func precision_description() -> String:
	if text_decimals >= 0:
		return "%d decimal places" % text_decimals
	return "precision by scale" if scale_aware else "precision by units"