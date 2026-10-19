class_name DraftUnits
extends RefCounted
## Units for the drafting subsystem.
##
## The model is metres, stored as a double. Imperial exists only as a display
## and entry format, so no geometry is ever stored in feet: two entities held in
## different units could no longer be compared, offset or snapped without a
## conversion at every touch (drafting-module.md D2).
##
## Every constant here is exact by definition, so a parse/format round trip adds
## no error. Formatting is a pure read: nothing in this file writes its output
## back into the model (D3).

enum System {
	METRIC,
	IMPERIAL,
}

enum LengthStyle {
	DECIMAL,       ## 3.81 m, 12.50 ft
	ARCHITECTURAL, ## 12'-6"
	ENGINEERING,   ## 12.50 ft
}

const METRE := 1.0
const MILLIMETRE := 0.001
const CENTIMETRE := 0.01
const KILOMETRE := 1000.0

## Exact by definition.
const INCH := 0.0254
const FOOT := 0.3048
const YARD := 0.9144
const MILE := 1609.344
## The US survey foot is the exact rational 1200/3937 m, 2 ppm longer than the
## international foot. US plats predating 2023 are commonly in it, and the
## difference is material for legal boundary work even though it is 0.6 mm/km.
const US_SURVEY_FOOT := 1200.0 / 3937.0

const ACRE := 4840.0 * YARD * YARD          ## 4046.8564224 m2, exact
const HECTARE := 10000.0
const SQ_FOOT := FOOT * FOOT

## Smallest inch fraction accepted when formatting architectural lengths.
const DEFAULT_INCH_DENOMINATOR := 16

var system: System = System.METRIC
var length_style: LengthStyle = LengthStyle.DECIMAL
## Display only. Never written back into the model.
var display_precision: int = 3
var inch_denominator: int = DEFAULT_INCH_DENOMINATOR
var use_us_survey_foot: bool = false


# --- length: parsing ---------------------------------------------------------------


## Parse a length to metres. Returns NAN when the text cannot be read, so a
## caller can never mistake a failed parse for a zero.
static func parse_length(
	text: String,
	default_system: System = System.METRIC,
	us_survey_foot: bool = false
) -> float:
	var t := text.strip_edges().to_lower()
	if t.is_empty():
		return NAN

	var feet_inches := _try_feet_inches(t, us_survey_foot)
	if not is_nan(feet_inches):
		return feet_inches

	var pattern := RegEx.new()
	if pattern.compile("^([-+]?[0-9]*\\.?[0-9]+)\\s*([a-z\"']*)$") != OK:
		return NAN
	var match := pattern.search(t)
	if match == null:
		return NAN
	var value := _number(match.get_string(1))
	if is_nan(value):
		return NAN
	var suffix := match.get_string(2)
	var factor := _length_factor(suffix, default_system, us_survey_foot)
	if is_nan(factor):
		return NAN
	return value * factor


## The unit factor for a suffix, or NAN if the suffix is not a length unit.
static func _length_factor(suffix: String, default_system: System, us_survey_foot: bool) -> float:
	var foot := US_SURVEY_FOOT if us_survey_foot else FOOT
	match suffix:
		"", "m":
			return METRE if suffix == "m" or default_system == System.METRIC else foot
		"mm", "millimetre", "millimetres", "millimeter", "millimeters":
			return MILLIMETRE
		"cm", "centimetre", "centimetres", "centimeter", "centimeters":
			return CENTIMETRE
		"km", "kilometre", "kilometres", "kilometer", "kilometers":
			return KILOMETRE
		"in", "\"", "inch", "inches":
			return INCH
		"'", "ft", "foot", "feet":
			return foot
		"yd", "yard", "yards":
			return YARD
		"mi", "mile", "miles":
			return MILE
	return NAN


## Recognises 12'6", 12-6, 12 6, 10'6 1/2". Returns NAN when the text is not in
## a feet-and-inches form.
static func _try_feet_inches(t: String, us_survey_foot: bool) -> float:
	var foot := US_SURVEY_FOOT if us_survey_foot else FOOT
	if t.contains("'"):
		var index := t.find("'")
		var feet := _number(t.substr(0, index))
		if is_nan(feet):
			return NAN
		var rest := t.substr(index + 1).replace("\"", "").strip_edges()
		var inches := 0.0
		if not rest.is_empty():
			inches = _fraction(rest)
			if is_nan(inches):
				return NAN
		return feet * foot + inches * INCH

	# Two numbers with no unit marker at all: feet and inches.
	var pattern := RegEx.new()
	if pattern.compile("^([-+]?[0-9]+)\\s*[- ]\\s*([0-9]+(?:\\s*[0-9]+/[0-9]+|/[0-9]+)?)$") != OK:
		return NAN
	var match := pattern.search(t)
	if match == null:
		return NAN
	var feet := _number(match.get_string(1))
	var inches := _fraction(match.get_string(2))
	if is_nan(feet) or is_nan(inches):
		return NAN
	return feet * foot + inches * INCH


## Reads 6, 1/2, 6 1/2 or 6-1/2 as a decimal. NAN when malformed.
static func _fraction(text: String) -> float:
	var t := text.strip_edges().replace("-", " ").replace("\"", "").strip_edges()
	if t.is_empty():
		return 0.0
	if not t.contains("/"):
		return _number(t)
	var parts := t.split(" ", false)
	var pieces := parts[parts.size() - 1].split("/")
	if pieces.size() != 2:
		return NAN
	var numerator := _number(pieces[0])
	var denominator := _number(pieces[1])
	if is_nan(numerator) or is_nan(denominator) or is_zero_approx(denominator):
		return NAN
	var whole := 0.0
	if parts.size() > 1:
		whole = _number(parts[0])
		if is_nan(whole):
			return NAN
	return whole + numerator / denominator


static func _number(text: String) -> float:
	var t := text.strip_edges()
	if t.is_empty() or not t.is_valid_float():
		return NAN
	return t.to_float()


## Convenience for surveyors: feet and inches to metres in one call.
static func feet_inches_to_metres(feet: float, inches: float, us_survey_foot: bool = false) -> float:
	var foot := US_SURVEY_FOOT if us_survey_foot else FOOT
	return feet * foot + inches * INCH


# --- length: formatting ------------------------------------------------------------


## Format a length in the active system. Read-only: the result is never stored.
func format_length(metres: float) -> String:
	match system:
		System.IMPERIAL:
			match length_style:
				LengthStyle.ARCHITECTURAL:
					return format_feet_inches(metres)
				_:
					return String.num(metres / _foot(), display_precision) + " ft"
		_:
			return String.num(metres, display_precision) + " m"


## 12'-6" or 12'-6 1/2", rounded to `inch_denominator`.
func format_feet_inches(metres: float) -> String:
	var foot := _foot()
	var negative := metres < 0.0
	var value := absf(metres)
	var feet := int(floor(value / foot))
	var rest := value - float(feet) * foot
	var units := int(round(rest / INCH * float(inch_denominator)))
	if units >= inch_denominator * 12:
		feet += 1
		units = 0
	var whole := units / inch_denominator
	var remainder := units % inch_denominator
	var text := "%d'-%d\"" % [feet, whole]
	if remainder != 0:
		var divisor := _gcd(remainder, inch_denominator)
		text = "%d'-%d %d/%d\"" % [feet, whole, remainder / divisor, inch_denominator / divisor]
	return ("-" if negative else "") + text


## A length formatted at a precision suited to the current zoom, so a readout at
## 1:200 does not claim micrometres. Display only.
func format_length_at_zoom(metres: float, pixels_per_metre: float) -> String:
	var decimals := display_decimals(pixels_per_metre)
	return String.num(metres, decimals) + (" m" if system == System.METRIC else " ft")


## Decimal places that are actually resolvable at a given zoom.
static func display_decimals(pixels_per_metre: float) -> int:
	if pixels_per_metre <= 0.0:
		return 0
	# Godot's log() is natural; a decade is what is wanted here.
	var decades := log(pixels_per_metre) / log(10.0)
	return clampi(int(ceil(decades)) + 1, 0, 6)


func _foot() -> float:
	return US_SURVEY_FOOT if use_us_survey_foot else FOOT


static func _gcd(a: int, b: int) -> int:
	var x := absi(a)
	var y := absi(b)
	while y != 0:
		var t := y
		y = x % y
		x = t
	return maxi(x, 1)


# --- area and volume ----------------------------------------------------------------


## Parse an area to square metres: 45m2, 450ft2, 5ac, 0.5ha, 5yd2.
static func parse_area(text: String, default_system: System = System.METRIC) -> float:
	var t := text.strip_edges().to_lower().replace("²", "2")
	if t.is_empty():
		return NAN
	var pattern := RegEx.new()
	if pattern.compile("^([-+]?[0-9]*\\.?[0-9]+)\\s*([a-z0-9]*)$") != OK:
		return NAN
	var match := pattern.search(t)
	if match == null:
		return NAN
	var value := _number(match.get_string(1))
	if is_nan(value):
		return NAN
	match match.get_string(2):
		"", "m2", "sqm":
			return value * (METRE * METRE if default_system == System.METRIC else SQ_FOOT)
		"mm2":
			return value * MILLIMETRE * MILLIMETRE
		"cm2":
			return value * CENTIMETRE * CENTIMETRE
		"ha", "hectare", "hectares":
			return value * HECTARE
		"km2":
			return value * KILOMETRE * KILOMETRE
		"ft2", "sqft":
			return value * SQ_FOOT
		"in2":
			return value * INCH * INCH
		"yd2", "sqyd":
			return value * YARD * YARD
		"ac", "acre", "acres":
			return value * ACRE
	return NAN


func format_area(square_metres: float) -> String:
	match system:
		System.IMPERIAL:
			var square_feet := square_metres / SQ_FOOT
			if absf(square_feet) >= ACRE / SQ_FOOT:
				return String.num(square_metres / ACRE, 4) + " ac"
			return String.num(square_feet, 1) + " ft2"
		_:
			if absf(square_metres) >= HECTARE:
				return String.num(square_metres / HECTARE, 4) + " ha"
			return String.num(square_metres, 2) + " m2"


## Cubic metres from an area at a depth, for takeoff quantities.
static func volume_from_area(square_metres: float, depth_metres: float) -> float:
	return square_metres * depth_metres


static func acres(square_metres: float) -> float:
	return square_metres / ACRE


static func hectares(square_metres: float) -> float:
	return square_metres / HECTARE


# --- descriptions -------------------------------------------------------------------


func system_name() -> String:
	return "metric" if system == System.METRIC else "imperial"


func length_unit_name() -> String:
	return "m" if system == System.METRIC else "ft"


## The suffix a bare number is interpreted with, for UI hints.
func default_suffix() -> String:
	match system:
		System.IMPERIAL:
			return "'" if length_style == LengthStyle.ARCHITECTURAL else "ft"
		_:
			return "m"