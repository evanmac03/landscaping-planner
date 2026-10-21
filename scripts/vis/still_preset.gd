class_name VisStillPreset
extends RefCounted
## The named output sizes a still can be rendered at.
##
## A preset is a label, a pixel size, a paper size and a dot-per-inch figure, and
## nothing else: the renderer is told what size to make and this table is only the
## place a person picks "A3 at 300 dpi" instead of typing 4961 by 3508. Where a size
## is a rounded pixel count it is a rounded pixel count on purpose - a sheet is
## printed at its dots per inch and the pixel size is what that comes to.
##
## The sizes are the ones §10.2 of `docs/visualization-subsystem-spec.md` names, plus
## A4 at 300 dpi, because a proposal on A3 is a plan and a proposal on A4 is a letter.

## Every preset, keyed by a short name. `px` is the still's own size and `mm` is the
## paper it would print on at `dpi`; the two are consistent to within a pixel.
const SIZES := {
	&"hd": {
		"label": "HD 1080p", "px": Vector2i(1920, 1080),
		"dpi": 96.0, "mm": Vector2(507.9, 285.7),
	},
	&"4k": {
		"label": "4K UHD", "px": Vector2i(3840, 2160),
		"dpi": 96.0, "mm": Vector2(1015.9, 571.5),
	},
	&"a4_300": {
		"label": "A4 at 300 dpi", "px": Vector2i(3508, 2480),
		"dpi": 300.0, "mm": Vector2(297.0, 210.0),
	},
	&"a3_300": {
		"label": "A3 at 300 dpi", "px": Vector2i(4961, 3508),
		"dpi": 300.0, "mm": Vector2(420.0, 297.0),
	},
}

## The order a picker lists them in: biggest deliverable first, because that is the
## one a proposal is asked for.
const ORDER: Array[StringName] = [&"a3_300", &"a4_300", &"4k", &"hd"]

## The one a proposal page defaults to: A3 is the sheet a plan is drawn on.
const PROPOSAL_DEFAULT: StringName = &"a3_300"

## A dot is a pixel at the print resolution, and there are 25.4 millimetres to the
## inch, exactly.
const MM_PER_INCH := 25.4


## Every preset name, in the order a picker shows them.
static func names() -> Array[StringName]:
	return ORDER.duplicate()


## Whether a name is one of the presets. Accepts a string or a StringName.
static func has(name) -> bool:
	return SIZES.has(StringName(name))


## One preset, or {} for a name nobody has. The caller checks rather than getting a
## silent default, so "which size?" is a question that gets a real answer.
static func preset(name) -> Dictionary:
	return SIZES.get(StringName(name), {})


## The pixel size of a preset, or Vector2i.ZERO.
static func size(name) -> Vector2i:
	var entry := preset(name)
	return entry.get("px", Vector2i.ZERO) if not entry.is_empty() else Vector2i.ZERO


## The paper size of a preset in millimetres, or Vector2.ZERO.
static func paper_mm(name) -> Vector2:
	var entry := preset(name)
	return entry.get("mm", Vector2.ZERO) if not entry.is_empty() else Vector2.ZERO


## The label a person reads, or the name itself when the preset is unknown.
static func label(name) -> String:
	var entry := preset(name)
	return String(entry["label"]) if not entry.is_empty() else String(name)


## The dots per inch the paper would print at, or 0.0 when the preset is unknown.
static func dpi(name) -> float:
	var entry := preset(name)
	return float(entry["dpi"]) if not entry.is_empty() else 0.0


## How many pixels a preset's paper comes to at its own resolution, worked out from
## the millimetres rather than read off the table - the two agree, and this is the
## one that can be checked.
static func pixels_for_paper(paper: Vector2, dpi_value: float) -> Vector2i:
	if paper.x <= 0.0 or paper.y <= 0.0 or dpi_value <= 0.0:
		return Vector2i.ZERO
	return Vector2i(
		int(round(paper.x / MM_PER_INCH * dpi_value)),
		int(round(paper.y / MM_PER_INCH * dpi_value)),
	)


## The size the still is actually rendered at, which is above the output size by the
## supersample factor: there is no 2D MSAA on this renderer, so the supersample *is*
## the antialiasing (§10.2).
static func render_size(name, supersample: int) -> Vector2i:
	var output := size(name)
	if output == Vector2i.ZERO:
		return Vector2i.ZERO
	var factor: int = maxi(supersample, 1)
	return Vector2i(output.x * factor, output.y * factor)


## A preset in one line, for a picker's tooltip or a status bar.
static func describe(name) -> String:
	var entry := preset(name)
	if entry.is_empty():
		return "no such still size: %s" % String(name)
	var mm: Vector2 = entry["mm"]
	var px: Vector2i = entry["px"]
	return "%s - %d x %d px, %.0f x %.0f mm at %.0f dpi" % [
		String(entry["label"]),
		px.x, px.y, mm.x, mm.y, float(entry["dpi"]),
	]