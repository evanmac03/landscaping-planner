class_name SketchStyle
extends Resource
## The look of the painted plan: how much wobble, how much grain, how wet (§13).
##
## A Resource rather than constants, because a designer will want two of these —
## "client presentation" and "council submission" — and the only honest way to ship two
## looks is to make the look a thing that can be saved, copied and compared (REQ-V13.2).
##
## Every length here is a **paper** length in millimetres, like every other authored
## length in this project, and every one of them is a paper length *rather than* a pixel
## count: the same look baked at twice the resolution must put the same grain on the
## paper (REQ-V3.7). `texels_per_mm` is the one field that is about pixels, and it says
## so.

# --- the wobble (§3.2) ----------------------------------------------------------------
## Sideways wander in paper millimetres. Zero gives a plotted line, which is a legitimate
# look and not a degenerate case.
@export var wobble_mm: float = 0.28
## Sampling step along a stroke, in paper millimetres. This is the setting that trades
## time for fidelity.
@export var segment_mm: float = 1.2

# --- paper and pigment ----------------------------------------------------------------
## Paper colour, under everything.
@export var paper: Color = Color(0.945, 0.937, 0.906)
## How far a wash bleeds past its own edge, in paper millimetres.
@export var bleed_mm: float = 1.8
## How dark a wash goes where it stops, which is what a wet edge does.
@export_range(0.0, 1.0) var edge_darkening: float = 0.30
## Paper grain strength.
@export_range(0.0, 1.0) var grain: float = 0.16
## Hatch strength in the wash's mid-tones.
@export_range(0.0, 1.0) var hatch: float = 0.22

# --- the ink pass (§3.3) --------------------------------------------------------------
## The under pass, as a multiple of the layer's own width.
@export var ink_under_width: float = 1.8
## The over pass, as a multiple of the layer's own width.
@export var ink_over_width: float = 1.0
## The under pass's opacity. A pencil line is a light broad pass with a darker narrow
## one on top; drawing only the dark one is what makes a digital line look plotted.
@export_range(0.0, 1.0) var ink_under_alpha: float = 0.28
## The over pass's opacity.
@export_range(0.0, 1.0) var ink_over_alpha: float = 0.92
## How far the under pass is lightened toward the paper.
@export_range(0.0, 1.0) var ink_lighten: float = 0.45
## Ink edge softness, as a share of full ink coverage. The one antialiasing the
## compositor has: it turns a threshold into a ramp, so a half-covered texel reads as a
## soft line rather than a hard one.
##
## Dimensionless on purpose. A ramp in *coverage* is not a length on the paper, and
## calling it millimetres is how a softness setting ends up being wrong at every
## resolution but the one it was tuned at.
@export_range(0.0, 1.0) var ink_softness: float = 0.45

# --- the bake -------------------------------------------------------------------------
## Texels per paper millimetre. Six gives 2520 x 1782 for an A3 sheet.
@export_range(1.0, 24.0) var texels_per_mm: float = 6.0
## Millimetres per repeat of the paper fibre. A repeat, not a count of repeats: the count
## is whatever fits on the sheet, which is why this is resolution-independent.
##
## Three millimetres rather than a quarter of one, which was the first attempt: a repeat
## that small puts the whole fibre texture inside two texels of the sheet, where the mip
## filter averages it into flat colour and the grain does nothing at all. The texture's
## size and this number are a pair - see `SketchCompositor.minification_for()`.
@export var grain_mm: float = 3.0
## Millimetres per repeat of the cross-hatch.
@export var hatch_mm: float = 1.6
## How many times the bake is rendered above its output size before being downsampled.
## This is the antialiasing: there is no 2D MSAA on this renderer (§1.2).
@export_range(1, 3) var supersample: int = 2


## A copy that can be changed without changing this one.
func copy() -> SketchStyle:
	var other := SketchStyle.new()
	for property: Dictionary in get_property_list():
		var name := String(property["name"])
		if property["usage"] & PROPERTY_USAGE_SCRIPT_VARIABLE:
			other.set(name, get(name))
	return other


## The look in one line, for a caption or a status bar.
func describe() -> String:
	return "wobble %.2f mm, grain %.2f, wet edge %.2f, %d texels/mm at %dx" % [
		wobble_mm, grain, edge_darkening, int(texels_per_mm), supersample,
	]