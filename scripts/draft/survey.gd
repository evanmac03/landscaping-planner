class_name Survey
extends RefCounted
## Property survey import: bearings, metes and bounds, alignment, and validation.
##
## Alignment is a **similarity** transform (uniform scale, rotation, translation)
## and never a general affine fit. A similarity preserves shape; an affine fit
## with few points can shear and stretch a survey into *looking* aligned while
## every area and dimension in it is wrong
## (docs/drafting-subsystem-spec.md §6.4).
##
## Everything here is static and pure, so the whole import path is testable with
## no scene and no file.

const Geom := preload("res://scripts/draft/geom2d.gd")
const UnitsScript := preload("res://scripts/draft/units.gd")

## A fit looser than this is reported as a warning.
const RESIDUAL_TOLERANCE_M := 0.050
## A fit looser than this is a failure: the source is distorted, not merely
## imprecise, and a similarity fit cannot reduce it.
const RESIDUAL_FAIL_M := 0.250
## Closure looser than 1:10,000 is worth flagging on a surveyed boundary.
const CLOSURE_RATIO_WARN := 10000.0
## Area agreement demanded against the area stated on a plat.
const AREA_TOLERANCE := 0.005
## Plausible parcel extent, for catching a tracing error.
const MIN_LOT_AREA_M2 := 20.0
const MAX_LOT_AREA_M2 := 1000000.0


# --- bearings -----------------------------------------------------------------------


## Azimuth in degrees clockwise from north, from a quadrantal bearing.
static func bearing_to_azimuth(
	quadrant_first: String, degrees: float, minutes: float, seconds: float, quadrant_second: String
) -> float:
	var dms := degrees + minutes / 60.0 + seconds / 3600.0
	if quadrant_first == "S":
		if quadrant_second == "E":
			return 180.0 - dms
		return 180.0 + dms
	if quadrant_second == "W":
		return 360.0 - dms
	return dms


## Parse a survey bearing or azimuth. Accepts "N 45°30'15\" E",
## "N45-30-15E", "N 45 30 15 E" and a plain azimuth in degrees.
## Returns NAN when the text cannot be read, so a failure is never mistaken for
## due north.
static func parse_bearing(text: String) -> float:
	var cleaned := text.strip_edges().to_upper()
	for symbol in ["°", "\"", "'", "-", ",", "DEG", "MIN", "SEC"]:
		cleaned = cleaned.replace(symbol, " ")
	var tokens := _tokenise(cleaned)
	if tokens.is_empty():
		return NAN
	var first := String(tokens[0])
	if first == "N" or first == "S":
		var second := ""
		var numbers: Array[float] = []
		for index in range(1, tokens.size()):
			var token := String(tokens[index])
			if token == "E" or token == "W":
				second = token
			elif token.ends_with("E") or token.ends_with("W"):
				# Run together, as in "15E".
				var letter := token.substr(token.length() - 1, 1)
				var numeric := token.substr(0, token.length() - 1)
				second = letter
				if numeric.is_valid_float():
					numbers.append(numeric.to_float())
			elif token.is_valid_float():
				numbers.append(token.to_float())
		if second.is_empty() or numbers.is_empty():
			return NAN
		var minutes := numbers[1] if numbers.size() > 1 else 0.0
		var seconds := numbers[2] if numbers.size() > 2 else 0.0
		return bearing_to_azimuth(first, numbers[0], minutes, seconds, second)
	if first.is_valid_float():
		return fposmod(first.to_float(), 360.0)
	return NAN


## Split a bearing into tokens, breaking a quadrant letter off an adjacent digit
## in either order, so "N45-30-15E" reads exactly like "N 45 30 15 E".
static func _tokenise(cleaned: String) -> PackedStringArray:
	var spaced := ""
	for index in cleaned.length():
		var character := cleaned[index]
		var is_digit := character >= "0" and character <= "9"
		if not spaced.is_empty():
			var previous := spaced[spaced.length() - 1]
			var previous_is_digit := previous >= "0" and previous <= "9"
			if is_digit != previous_is_digit:
				var previous_is_letter := previous == "N" or previous == "S" or previous == "E" or previous == "W"
				var character_is_letter := character == "N" or character == "S" or character == "E" or character == "W"
				if previous_is_letter or character_is_letter:
					spaced += " "
		spaced += character
	return spaced.split(" ", false)


static func format_dms(degrees: float) -> String:
	var value := absf(degrees)
	var whole := int(floor(value))
	var remainder := (value - float(whole)) * 60.0
	var minutes := int(floor(remainder))
	var seconds := (remainder - float(minutes)) * 60.0
	return "%d°%s'%s\"" % [whole, _pad(minutes, 2), _pad(seconds, 2)]


static func azimuth_to_bearing(azimuth: float) -> String:
	var value := fposmod(azimuth, 360.0)
	if value <= 90.0:
		return "N %s E" % format_dms(value)
	if value <= 180.0:
		return "S %s E" % format_dms(180.0 - value)
	if value <= 270.0:
		return "S %s W" % format_dms(value - 180.0)
	return "N %s W" % format_dms(360.0 - value)


static func _pad(value: float, digits: int) -> String:
	var text := String.num(value, 2)
	while text.length() < digits + 3:   # digits + "." + 2 decimals
		text = "0" + text
	return text


## A leg from a bearing string and a distance, converted to metres.
static func leg(bearing_text: String, distance: float, us_survey_foot: bool = false) -> Dictionary:
	return {
		"azimuth": parse_bearing(bearing_text),
		"distance": distance * (UnitsScript.US_SURVEY_FOOT if us_survey_foot else UnitsScript.FOOT),
	}


# --- traverse -----------------------------------------------------------------------


## Walk a set of legs from the origin.
##
## Legs are dictionaries of "azimuth" (degrees clockwise from north) and
## "distance" (metres). The result carries the geometry in model XZ, the closure
## in east/north, the closure ratio, perimeter and area — the numbers the
## validation checks need (REQ 6.5.1).
static func traverse(legs: Array) -> Dictionary:
	var east_north := PackedVector2Array()
	var east := 0.0
	var north := 0.0
	var perimeter := 0.0
	east_north.append(Vector2.ZERO)
	for entry in legs:
		var leg_data: Dictionary = entry
		var azimuth := float(leg_data.get("azimuth", 0.0))
		var distance := float(leg_data.get("distance", 0.0))
		var radians := deg_to_rad(azimuth)
		east += sin(radians) * distance
		north += cos(radians) * distance
		perimeter += distance
		east_north.append(Vector2(east, north))

	# Model space is east +X and north -Z, so survey data does not need a flip
	# at every call site.
	var model := PackedVector2Array()
	for point: Vector2 in east_north:
		model.append(Vector2(point.x, -point.y))

	# The last point repeats the first when the traverse closes; drop it for the
	# area, which expects a simple ring.
	var ring := PackedVector2Array()
	for index in maxi(east_north.size() - 1, 0):
		ring.append(east_north[index])

	var misclosure := Vector2(east, north).length()
	return {
		"points": model,
		"ring": ring,
		"east": east,
		"north": north,
		"misclosure": misclosure,
		"closure_ratio": INF if misclosure <= Geom.EPS else perimeter / misclosure,
		"perimeter": perimeter,
		"area_m2": Geom.polygon_area(ring),
		"closed": misclosure <= Geom.EPS,
	}


## The compass (Bowditch) rule: distribute the closure error among the legs in
## proportion to their length. Offered, never applied by default, because
## adjusting a survey is a professional decision (REQ 6.5.2).
static func bowditch_adjust(legs: Array, misclosure_east: float, misclosure_north: float) -> Array:
	var perimeter := 0.0
	for entry in legs:
		perimeter += float((entry as Dictionary).get("distance", 0.0))
	var out: Array = []
	if perimeter <= Geom.EPS:
		for entry in legs:
			out.append((entry as Dictionary).duplicate())
		return out
	for entry in legs:
		var leg_data: Dictionary = entry
		var distance := float(leg_data.get("distance", 0.0))
		var share := distance / perimeter
		var radians := deg_to_rad(float(leg_data.get("azimuth", 0.0)))
		var adjusted_east := sin(radians) * distance - misclosure_east * share
		var adjusted_north := cos(radians) * distance - misclosure_north * share
		out.append({
			"azimuth": fposmod(rad_to_deg(atan2(adjusted_east, adjusted_north)), 360.0),
			"distance": sqrt(adjusted_east * adjusted_east + adjusted_north * adjusted_north),
			"adjusted": true,
			"was_azimuth": float(leg_data.get("azimuth", 0.0)),
			"was_distance": distance,
		})
	return out


# --- alignment ----------------------------------------------------------------------


## Least-squares similarity fit from source points to target points.
##
## The closed form solves for the matrix [a -b; b a], which is exactly "scale,
## then rotate". Two correspondences determine it exactly; three or more make it
## least-squares, so one misclicked point degrades the fit instead of breaking it.
static func similarity_fit(source: PackedVector2Array, target: PackedVector2Array) -> Dictionary:
	var count := source.size()
	if count < 2 or target.size() != count:
		return {"ok": false, "reason": "need at least two corresponding points"}
	var source_centre := Vector2.ZERO
	var target_centre := Vector2.ZERO
	for index in count:
		source_centre += source[index]
		target_centre += target[index]
	source_centre /= float(count)
	target_centre /= float(count)

	var a := 0.0
	var b := 0.0
	var norm := 0.0
	for index in count:
		var u := source[index] - source_centre
		var v := target[index] - target_centre
		norm += float(u.x) * float(u.x) + float(u.y) * float(u.y)
		a += float(u.x) * float(v.x) + float(u.y) * float(v.y)
		b += float(u.x) * float(v.y) - float(u.y) * float(v.x)
	if norm <= Geom.EPS:
		return {"ok": false, "reason": "source points coincide"}
	a /= norm
	b /= norm

	var total := 0.0
	for index in count:
		var predicted := _transform(source[index], source_centre, target_centre, a, b)
		total += predicted.distance_squared_to(target[index])

	return {
		"ok": true,
		"a": a,
		"b": b,
		"scale": sqrt(a * a + b * b),
		"rotation": atan2(b, a),
		"rotation_deg": rad_to_deg(atan2(b, a)),
		"source_centre": source_centre,
		"target_centre": target_centre,
		"rms": sqrt(total / float(count)),
		"count": count,
	}


static func _transform(point: Vector2, source_centre: Vector2, target_centre: Vector2, a: float, b: float) -> Vector2:
	var u := point - source_centre
	return Vector2(
		target_centre.x + a * float(u.x) - b * float(u.y),
		target_centre.y + b * float(u.x) + a * float(u.y)
	)


## Map a source point through a solved fit.
static func apply_fit(fit: Dictionary, point: Vector2) -> Vector2:
	if not fit.get("ok", false):
		return point
	return _transform(point, fit["source_centre"], fit["target_centre"], fit["a"], fit["b"])


## Map a whole point set, as a raster underlay's traced points would be.
static func apply_fit_points(fit: Dictionary, points: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for point: Vector2 in points:
		out.append(apply_fit(fit, point))
	return out


# --- validation ---------------------------------------------------------------------


## The residual is the user's only measure of fit quality (REQ 6.4.4), and a fit
## beyond the fail threshold means the source is distorted and must be reported
## rather than absorbed (REQ 6.4.5).
static func check_alignment(
	fit: Dictionary,
	tolerance: float = RESIDUAL_TOLERANCE_M,
	fail_above: float = RESIDUAL_FAIL_M
) -> Dictionary:
	if not fit.get("ok", false):
		return {
			"name": "Alignment", "value": NAN, "tolerance": tolerance,
			"status": "fail", "unit": "m",
			"message": String(fit.get("reason", "the fit could not be solved")),
		}
	var rms: float = fit["rms"]
	var status := "pass"
	var message := "fit is tight"
	if rms > fail_above:
		status = "fail"
		message = "source is distorted; a similarity fit cannot absorb this"
	elif rms > tolerance:
		status = "warn"
		message = "fit is looser than " + String.num(tolerance * 1000.0, 0) + " mm"
	return {
		"name": "Alignment residual", "value": rms, "tolerance": tolerance,
		"status": status, "unit": "m", "message": message,
	}


## Traverse closure. Reported before any adjustment is offered (REQ 6.5.1).
static func check_closure(result: Dictionary, ratio_warn: float = CLOSURE_RATIO_WARN) -> Dictionary:
	var misclosure := float(result.get("misclosure", 0.0))
	var ratio := float(result.get("closure_ratio", INF))
	if misclosure <= Geom.EPS:
		return {
			"name": "Traverse closure", "value": 0.0, "tolerance": 0.0,
			"status": "pass", "unit": "m", "message": "closed exactly",
		}
	var status := "pass"
	var message := "closure ratio 1:" + String.num(ratio, 0)
	if ratio < ratio_warn:
		status = "warn"
		message += ", looser than 1:" + String.num(ratio_warn, 0)
	return {
		"name": "Traverse closure", "value": misclosure, "tolerance": 0.0,
		"status": status, "unit": "m", "message": message,
	}


## The strongest independent verification of scale available: what the geometry
## computes against what the plat states (REQ 6.5.3).
static func check_area(
	computed_m2: float,
	stated_m2: float,
	tolerance: float = AREA_TOLERANCE
) -> Dictionary:
	if stated_m2 <= 0.0:
		return {
			"name": "Area cross-check", "value": computed_m2, "tolerance": tolerance,
			"status": "pass", "unit": "m2", "message": "no stated area to compare",
		}
	var difference := absf(computed_m2 / stated_m2 - 1.0)
	return {
		"name": "Area cross-check", "value": difference, "tolerance": tolerance,
		"status": "pass" if difference <= tolerance else "warn",
		"unit": "ratio",
		"message": "computed " + String.num(computed_m2, 2) + " m2 vs stated "
			+ String.num(stated_m2, 2) + " m2",
	}


## A self-intersecting parcel is a tracing error, not a survey: this blocks.
static func check_simple(polygon: PackedVector2Array) -> Dictionary:
	var simple := Geom.polygon_is_simple(polygon)
	return {
		"name": "Parcel self-intersection", "value": 0.0, "tolerance": 0.0,
		"status": "pass" if simple else "fail",
		"unit": "", "message": "parcel outline is simple" if simple
			else "parcel outline crosses itself; re-trace it",
	}


static func check_extent(
	bounds: Rect2,
	minimum: float = MIN_LOT_AREA_M2,
	maximum: float = MAX_LOT_AREA_M2
) -> Dictionary:
	var area := absf(bounds.size.x * bounds.size.y)
	return {
		"name": "Parcel extent", "value": area, "tolerance": maximum,
		"status": "pass" if area >= minimum and area <= maximum else "warn",
		"unit": "m2",
		"message": "parcel covers about " + String.num(area, 0) + " m2",
	}


## Roll a set of check records into a report. Any failure blocks the commit.
static func summarise(records: Array) -> Dictionary:
	var failures := 0
	var warnings := 0
	for entry in records:
		var record: Dictionary = entry
		match String(record.get("status", "pass")):
			"fail":
				failures += 1
			"warn":
				warnings += 1
	return {
		"records": records,
		"failures": failures,
		"warnings": warnings,
		"passed": failures == 0,
	}