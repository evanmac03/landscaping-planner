class_name PlotScale
extends RefCounted
## Sheets, plot scales and the conversion between model metres, paper
## millimetres and PDF points.
##
## A drawing is true to scale when a stated ratio 1:S holds between a distance
## measured on the sheet and the real distance. Paper millimetres must therefore
## be *physical* millimetres, which is why every conversion here is exact and
## unrounded until final emission (docs/drafting-subsystem-spec.md §3).

## Sheet sizes in millimetres, landscape (width x height).
const SHEETS := {
	"ANSI A (8.5x11 in)": Vector2(279.0, 216.0),
	"ANSI B (11x17 in)": Vector2(432.0, 279.0),
	"ANSI C (17x22 in)": Vector2(559.0, 432.0),
	"ANSI D (22x34 in)": Vector2(864.0, 559.0),
	"ANSI E (34x44 in)": Vector2(1118.0, 864.0),
	"A4": Vector2(297.0, 210.0),
	"A3": Vector2(420.0, 297.0),
	"A2": Vector2(594.0, 420.0),
	"A1": Vector2(841.0, 594.0),
	"A0": Vector2(1189.0, 841.0),
	"ARCH C (24x18 in)": Vector2(610.0, 457.0),
	"ARCH D (36x24 in)": Vector2(914.0, 610.0),
	"ARCH E (36x48 in)": Vector2(1219.0, 914.0),
}

## Metric scale ladder, smallest ratio first.
const METRIC_LADDER: Array[float] = [20.0, 25.0, 50.0, 100.0, 125.0, 150.0, 200.0, 250.0, 500.0, 1000.0]

## Conventional imperial scales, reduced to the ratio they mean.
const IMPERIAL_SCALES := {
	"1/16 in = 1 ft": 192.0,
	"3/32 in = 1 ft": 128.0,
	"1/8 in = 1 ft": 96.0,
	"3/16 in = 1 ft": 64.0,
	"1/4 in = 1 ft": 48.0,
	"3/8 in = 1 ft": 32.0,
	"1/2 in = 1 ft": 24.0,
	"3/4 in = 1 ft": 16.0,
	"1 in = 1 ft": 12.0,
	"1 in = 10 ft": 120.0,
	"1 in = 20 ft": 240.0,
	"1 in = 30 ft": 360.0,
	"1 in = 40 ft": 480.0,
	"1 in = 50 ft": 600.0,
}

const DEFAULT_MARGIN_MM := 15.0

## Exact: one point is 1/72 inch.
const POINTS_PER_MM := 72.0 / 25.4


# --- sheets -------------------------------------------------------------------------


static func sheet_names() -> Array[String]:
	var out: Array[String] = []
	for key: String in SHEETS:
		out.append(key)
	return out


static func sheet_size_mm(sheet_name: String) -> Vector2:
	return SHEETS.get(sheet_name, Vector2(420.0, 297.0))


## The area inside the border, where a viewport may sit.
static func printable_size_mm(sheet_name: String, margin_mm: float = DEFAULT_MARGIN_MM) -> Vector2:
	var size := sheet_size_mm(sheet_name)
	return Vector2(maxf(size.x - margin_mm * 2.0, 1.0), maxf(size.y - margin_mm * 2.0, 1.0))


# --- scale --------------------------------------------------------------------------


## Model metres that one paper millimetre represents at a scale of 1:S.
static func model_metres_per_paper_mm(scale: float) -> float:
	return scale / 1000.0


## Model XZ extent a sheet covers at a scale of 1:S, in metres.
static func coverage_m(sheet_name: String, scale: float, margin_mm: float = DEFAULT_MARGIN_MM) -> Vector2:
	var printable := printable_size_mm(sheet_name, margin_mm)
	return printable * model_metres_per_paper_mm(scale)


## The smallest ratio at which a design of this extent fits the sheet.
static func required_scale(extent_m: Vector2, sheet_name: String, margin_mm: float = DEFAULT_MARGIN_MM) -> float:
	var printable := printable_size_mm(sheet_name, margin_mm)
	var width_need := absf(extent_m.x) * 1000.0 / printable.x
	var height_need := absf(extent_m.y) * 1000.0 / printable.y
	return maxf(maxf(width_need, height_need), 1.0)


static func suggest(
	extent_m: Vector2,
	sheet_name: String,
	margin_mm: float = DEFAULT_MARGIN_MM,
	imperial: bool = false
) -> Dictionary:
	var need := required_scale(extent_m, sheet_name, margin_mm)
	var chosen := 0.0
	var label := ""
	if imperial:
		# Walk the imperial table in ratio order and take the first that fits.
		var ratios: Array[float] = []
		for key: String in IMPERIAL_SCALES:
			ratios.append(IMPERIAL_SCALES[key])
		ratios.sort()
		for ratio: float in ratios:
			if ratio >= need:
				chosen = ratio
				break
		if chosen == 0.0:
			chosen = ratios[ratios.size() - 1]
		label = imperial_label(chosen)
	else:
		for ratio: float in METRIC_LADDER:
			if ratio >= need:
				chosen = ratio
				break
		if chosen == 0.0:
			chosen = METRIC_LADDER[METRIC_LADDER.size() - 1]
		label = metric_label(chosen)
	return {
		"scale": chosen,
		"label": label,
		"required": need,
		"coverage_m": coverage_m(sheet_name, chosen, margin_mm),
		"fits": chosen >= need,
	}


static func metric_label(scale: float) -> String:
	return "1:%s" % String.num(scale, 0)


## The conventional name of a ratio, or the ratio itself when it is not standard.
static func imperial_label(scale: float) -> String:
	for key: String in IMPERIAL_SCALES:
		if is_equal_approx(IMPERIAL_SCALES[key], scale):
			return key
	return "1:%s" % String.num(scale, 0)


static func imperial_ratio(label: String) -> float:
	return IMPERIAL_SCALES.get(label, 0.0)


static func is_standard(scale: float) -> bool:
	for ratio: float in METRIC_LADDER:
		if is_equal_approx(ratio, scale):
			return true
	for key: String in IMPERIAL_SCALES:
		if is_equal_approx(IMPERIAL_SCALES[key], scale):
			return true
	return false


# --- points, for vector output -------------------------------------------------------


static func points_from_mm(millimetres: float) -> float:
	return millimetres * POINTS_PER_MM


static func mm_from_points(points: float) -> float:
	return points / POINTS_PER_MM


## A sheet's page box in PDF points. 1 pt = 1/72 in exactly, so these are not
## round numbers and must not be rounded before emission.
static func sheet_size_points(sheet_name: String) -> Vector2:
	var size := sheet_size_mm(sheet_name)
	return Vector2(points_from_mm(size.x), points_from_mm(size.y))


## How many points a model length occupies on the sheet at 1:S.
static func model_length_points(metres: float, scale: float) -> float:
	return points_from_mm(metres * 1000.0 / scale)


# --- scale bars ---------------------------------------------------------------------


## Round lengths a scale bar may be labelled with, in the active unit system.
const NICE_METRES: Array[float] = [1.0, 2.0, 5.0, 10.0, 20.0, 50.0, 100.0]
const NICE_FEET: Array[float] = [1.0, 2.0, 5.0, 10.0, 20.0, 50.0, 100.0]
const FEET_TO_METRES := 0.3048


## The largest round length whose bar fits the pixel budget, in metres. The bar is
## drawn at its true length; only the label is chosen here.
static func scale_bar_length(
	pixels_per_metre: float,
	max_pixels: float,
	imperial: bool = false
) -> Dictionary:
	var candidates := NICE_FEET if imperial else NICE_METRES
	var factor := FEET_TO_METRES if imperial else 1.0
	var best_metres := candidates[0] * factor
	var best_label := candidates[0]
	for value: float in candidates:
		var metres := value * factor
		if metres * pixels_per_metre <= max_pixels:
			best_metres = metres
			best_label = value
	return {
		"metres": best_metres,
		"label_value": best_label,
		"pixels": best_metres * pixels_per_metre,
	}