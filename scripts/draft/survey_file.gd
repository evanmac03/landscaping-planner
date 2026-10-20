class_name SurveyFile
extends RefCounted
## Reading a surveyor's own file into the model geometry the survey engine
## already validates: metes and bounds (bearings and distances), or a coordinate
## point list.
##
## The format is a table, not a language. One leg or point to a line, fields
## separated by a tab, comma, semicolon or bar, `#` for comment, blank lines
## ignored, and an optional header of `key: value` lines - `units`, `kind`,
## `area`, `name` and `note`. A line with no separator at all is read as a
## bearing followed by its distance, which is how most surveyors write a leg by
## hand.
##
## Which kind of row a line is has to be decided before it is read, because a
## bare number is both a legal azimuth and a legal easting. A quadrantal bearing
## ("N 45 30 15 E") is a leg; a pair of bare numbers is a point; and a file whose
## azimuths are bare numbers says so once, with `kind: metes`. Guessing otherwise
## would put a lot's coordinates through a traverse and place a parcel of nothing
## at the origin - a mistake that looks like an empty drawing rather than an
## error.
##
## Every distance must be in a unit somebody stated: in the file's own header, on
## the line, or in the options. A survey that does not say whether it is in metres
## or feet is a survey that has to be asked about, not guessed at, because the
## difference between them is a plan that is wrong by a factor of three.
##
## There is no fit here and no transform. Metes and bounds are exact by
## definition (docs/drafting-subsystem-spec.md 6.1), so this is an adapter rather
## than an aligner: it hands the survey engine legs and points and hands back the
## engine's own validation report.

const SurveyScript := preload("res://scripts/draft/survey.gd")
const UnitsScript := preload("res://scripts/draft/units.gd")
const Geom := preload("res://scripts/draft/geom2d.gd")

## The two shapes a survey file comes in.
const METES := "metes"
const POINTS := "points"

## Header keys this reader reads - `units`, `area`, `name`, `note`. Any other
## `word: value` line is kept as a note rather than dropped, so nothing in a
## surveyor's file is silently lost; it is only a *data* line that cannot be read
## that refuses the file.
const LENGTH_UNITS := {
	"m": 1.0, "metre": 1.0, "meter": 1.0, "metres": 1.0, "meters": 1.0, "mtr": 1.0,
	"ft": UnitsScript.FOOT, "foot": UnitsScript.FOOT, "feet": UnitsScript.FOOT,
	"'": UnitsScript.FOOT, "feet (us)": UnitsScript.US_SURVEY_FOOT,
	"usft": UnitsScript.US_SURVEY_FOOT, "us-ft": UnitsScript.US_SURVEY_FOOT,
	"ftus": UnitsScript.US_SURVEY_FOOT, "us survey foot": UnitsScript.US_SURVEY_FOOT,
	"us survey feet": UnitsScript.US_SURVEY_FOOT, "survey foot": UnitsScript.US_SURVEY_FOOT,
	"in": UnitsScript.INCH, "inch": UnitsScript.INCH, "inches": UnitsScript.INCH,
	"yd": UnitsScript.YARD, "yard": UnitsScript.YARD, "yards": UnitsScript.YARD,
}

## Area units accepted in an `area:` header, and how many square metres one is.
const AREA_UNITS := {
	"m2": 1.0, "sqm": 1.0, "sq m": 1.0, "square metre": 1.0, "square metres": 1.0,
	"square meter": 1.0, "square meters": 1.0,
	"ha": UnitsScript.HECTARE, "hectare": UnitsScript.HECTARE, "hectares": UnitsScript.HECTARE,
	"ac": UnitsScript.ACRE, "acre": UnitsScript.ACRE, "acres": UnitsScript.ACRE,
	"ft2": UnitsScript.SQ_FOOT, "sqft": UnitsScript.SQ_FOOT, "sq ft": UnitsScript.SQ_FOOT,
	"square foot": UnitsScript.SQ_FOOT, "square feet": UnitsScript.SQ_FOOT,
}


# --- reading ------------------------------------------------------------------------
## Read survey text. `options` may carry "units" (a unit name every distance
## without one of its own is read in).
##
## The result is a dictionary rather than a class because the survey engine it
## feeds is a table of numbers and its report is a table of records, and a class
## here would only be a second set of field names for the same thing.
static func read_text(text: String, options: Dictionary = {}) -> Dictionary:
	var default_units := _unit_name(String(options.get("units", "")))
	var forced_kind := ""
	var stated_area := 0.0
	var kind := ""
	var legs: Array = []
	var raw_points: Array = []
	var points_unit := ""
	var leg_units: Array[String] = []
	var notes: Array[String] = []
	var header_name := ""

	var rows := _data_rows(text)
	for row: Dictionary in rows:
		var line_number := int(row["line"])
		var line := String(row["text"])

		# A header, before any data line: `key: value`.
		var header := _header(line)
		if not header.is_empty():
			var key := String(header["key"])
			var value := String(header["value"])
			if key == "units" or key == "unit":
				var named := _unit_name(value)
				if named == "":
					return _failed("line %d: \"%s\" is not a unit" % [line_number, value])
				default_units = named
			elif key == "area":
				stated_area = _area_m2(value)
				if stated_area <= 0.0:
					notes.append("line %d: the stated area could not be read" % line_number)
			elif key == "kind":
				var wanted := value.strip_edges().to_lower()
				if wanted != METES and wanted != POINTS:
					return _failed("line %d: \"%s\" is neither metes nor points" % [line_number, value])
				forced_kind = wanted
			elif key == "name":
				header_name = value
			elif key == "note" or key == "notes":
				notes.append(value)
			else:
				notes.append("%s: %s" % [key, value])
			continue

		# A data line. Which kind of row it is has to be decided before it is read,
		# because a bare number is both a legal azimuth and a legal easting. A
		# quadrantal bearing ("N 45 E") is a leg; a pair of bare numbers is a point
		# unless the file says `kind: metes`, which is how a machine's azimuth list
		# is read. Guessing the other way would put a lot's coordinates through a
		# traverse and place a parcel of nothing at the origin.
		var cells := _cells(line)
		var first := String(cells[0]) if cells.size() > 0 else ""
		var second := String(cells[1]) if cells.size() > 1 else ""
		var third := String(cells[2]) if cells.size() > 2 else ""
		var reads_as_metes := _quadrantal(first) or forced_kind == METES

		if reads_as_metes:
			if kind == POINTS:
				return _failed("line %d: a bearing after a coordinate list" % line_number)
			kind = METES
			var bearing := SurveyScript.parse_bearing(first)
			if is_nan(bearing) and first.is_valid_float():
				bearing = fposmod(first.to_float(), 360.0)
			if is_nan(bearing):
				return _failed("line %d: the bearing \"%s\" cannot be read" % [line_number, first])
			if not second.is_valid_float():
				return _failed("line %d: the distance \"%s\" cannot be read" % [line_number, second])
			var unit_name := default_units
			if third != "":
				unit_name = _unit_name(third)
				if unit_name == "":
					return _failed("line %d: \"%s\" is not a unit" % [line_number, third])
			if unit_name == "":
				return _failed(
					"line %d: say what unit the distances are in" % line_number
				)
			legs.append({
				"azimuth": bearing,
				"distance": second.to_float() * float(LENGTH_UNITS[unit_name]),
				"unit": unit_name,
				"line": line_number,
			})
			if not leg_units.has(unit_name):
				leg_units.append(unit_name)
			continue

		if first.is_valid_float() and second.is_valid_float():
			if kind == METES:
				return _failed("line %d: a coordinate after a list of bearings" % line_number)
			kind = POINTS
			var point_unit := default_units
			if third != "":
				var named := _unit_name(third)
				if named != "":
					point_unit = named
				elif not third.is_valid_float():
					notes.append(
						"line %d: \"%s\" is neither an elevation nor a unit, and is ignored"
						% [line_number, third]
					)
			if point_unit == "":
				return _failed("line %d: say what unit the coordinates are in" % line_number)
			if points_unit == "" or points_unit == point_unit:
				points_unit = point_unit
			else:
				points_unit = "mixed"
			raw_points.append({
				"east": first.to_float() * float(LENGTH_UNITS[point_unit]),
				"north": second.to_float() * float(LENGTH_UNITS[point_unit]),
				"line": line_number,
			})
			continue

		return _failed("line %d: \"%s\" is neither a bearing nor a coordinate" % [line_number, line])

	if kind == "":
		return _failed("the file has no bearings and no coordinates in it")

	var unit_text := default_units
	if kind == POINTS and points_unit != "":
		unit_text = points_unit
	elif kind == METES and not leg_units.is_empty():
		unit_text = leg_units[0] if leg_units.size() == 1 else "mixed"
	return _assemble(kind, legs, raw_points, unit_text, default_units, stated_area, notes, header_name)


## Read a survey file from disk. A missing or unreadable file is refused with a
## reason rather than raising, because it is a path a person typed.
static func of_file(path: String, options: Dictionary = {}) -> Dictionary:
	if not FileAccess.file_exists(path):
		return _failed("there is no survey file at %s" % path)
	var handle := FileAccess.open(path, FileAccess.READ)
	if handle == null:
		return _failed("the survey file at %s could not be opened" % path)
	var text := handle.get_as_text()
	handle.close()
	var parsed := read_text(text, options)
	parsed["source"] = path
	return parsed


# --- the assembled result -----------------------------------------------------------


## Build the geometry and the report from whatever was read. Shared with
## `from_dict`, so a survey that came back out of a file is validated by exactly
## the code that validated it the first time.
static func _assemble(
	kind: String,
	legs: Array,
	raw_points: Array,
	unit_text: String,
	default_units: String,
	stated_area: float,
	notes: Array[String],
	header_name: String
) -> Dictionary:
	var points := PackedVector2Array()
	var ring := PackedVector2Array()
	var traverse: Dictionary = {}
	if kind == METES:
		var engine_legs: Array = []
		for entry: Dictionary in legs:
			engine_legs.append({
				"azimuth": float(entry["azimuth"]),
				"distance": float(entry["distance"]),
			})
		traverse = SurveyScript.traverse(engine_legs)
		points = traverse["points"]
		ring = traverse["ring"]
	else:
		for entry: Dictionary in raw_points:
			points.append(Vector2(float(entry["east"]), -float(entry["north"])))
		ring = points

	var area_m2 := Geom.polygon_area(ring)
	var checks: Array = []
	checks.append(SurveyScript.check_simple(ring))
	if kind == METES:
		checks.append(SurveyScript.check_closure(traverse))
	checks.append(SurveyScript.check_extent(Geom.points_aabb(ring)))
	checks.append(SurveyScript.check_area(area_m2, stated_area))

	return {
		"ok": true,
		"reason": "",
		"kind": kind,
		"legs": legs,
		"raw_points": raw_points,
		"units": unit_text,
		"default_units": default_units,
		"points": points,
		"ring": ring,
		"outline": _closed(ring),
		"traverse": traverse,
		"area_m2": area_m2,
		"perimeter_m": float(traverse.get("perimeter", 0.0)) if kind == METES else _perimeter(ring),
		"stated_area_m2": stated_area,
		"report": SurveyScript.summarise(checks),
		"notes": notes,
		"title": header_name,
		"source": "",
	}


static func _failed(reason: String) -> Dictionary:
	return {
		"ok": false,
		"reason": reason,
		"kind": "",
		"legs": [],
		"raw_points": [],
		"units": "",
		"default_units": "",
		"points": PackedVector2Array(),
		"ring": PackedVector2Array(),
		"outline": PackedVector2Array(),
		"traverse": {},
		"area_m2": 0.0,
		"perimeter_m": 0.0,
		"stated_area_m2": 0.0,
		"report": SurveyScript.summarise([]),
		"notes": [],
		"title": "",
		"source": "",
	}


## The ring as an outline that closes itself, which is what a polyline wants.
static func _closed(ring: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for point: Vector2 in ring:
		out.append(point)
	if ring.size() >= 3:
		out.append(ring[0])
	return out


static func _perimeter(ring: PackedVector2Array) -> float:
	var total := 0.0
	for index in ring.size():
		total += ring[index].distance_to(ring[(index + 1) % ring.size()])
	return total


# --- lines --------------------------------------------------------------------------


## The lines of the file that carry data, with comments and blanks dropped and
## the original line numbers kept, so a refusal can name the line to fix.
static func _data_rows(text: String) -> Array:
	var out: Array = []
	var number := 0
	for raw in text.split("\n"):
		number += 1
		var line := raw.strip_edges()
		if line.is_empty() or line.begins_with("#") or line.begins_with("//"):
			continue
		out.append({"line": number, "text": line})
	return out


## `key: value`, when the key is a bare word. Empty when the line is data.
static func _header(line: String) -> Dictionary:
	var cut := line.find(":")
	if cut <= 0:
		return {}
	var key := line.substr(0, cut).strip_edges().to_lower()
	if key.is_empty() or key.contains(" ") or key.contains(",") or key.contains("\t"):
		return {}
	for index in key.length():
		var character := key[index]
		var is_letter := (character >= "a" and character <= "z") or character == "_"
		if not is_letter:
			return {}
	return {"key": key, "value": line.substr(cut + 1).strip_edges()}


static func _cells(line: String) -> PackedStringArray:
	var separators := ["\t", ",", ";", "|"]
	for separator: String in separators:
		if line.contains(separator):
			return _trimmed(line.split(separator, false))
	# No separator: a bearing followed by its distance, as a person writes it.
	var tokens := _trimmed(line.split(" ", false))
	if tokens.size() >= 2:
		if not is_nan(SurveyScript.parse_bearing(tokens[0])):
			return tokens
		# A bearing written with spaces inside it - "N 45 30 15 E 100.00" - so the
		# line is split where the bearing stops reading and the distance starts.
		for cut in range(2, tokens.size()):
			var head := PackedStringArray()
			for index in cut:
				head.append(tokens[index])
			var tail := PackedStringArray()
			for index in range(cut, tokens.size()):
				tail.append(tokens[index])
			if not is_nan(SurveyScript.parse_bearing(" ".join(head))) and String(tail[0]).is_valid_float():
				var joined := PackedStringArray([" ".join(head)])
				joined.append_array(tail)
				return joined
		return tokens
	return _trimmed(PackedStringArray([line]))


## Whether a bearing was written quadrantally - "N 45 30 15 E", "S 12 W" - which
## is the one form that cannot be mistaken for a coordinate.
static func _quadrantal(text: String) -> bool:
	var cleaned := text.strip_edges().to_upper()
	if cleaned.is_empty():
		return false
	var first := cleaned.substr(0, 1)
	return first == "N" or first == "S"


static func _trimmed(cells: PackedStringArray) -> PackedStringArray:
	var out := PackedStringArray()
	for cell: String in cells:
		out.append(cell.strip_edges())
	return out


## The canonical unit name for whatever a person wrote, or "" when it is not a
## unit this reader knows. Case and surrounding punctuation are forgiven.
static func _unit_name(text: String) -> String:
	var cleaned := text.strip_edges().to_lower().replace("\"", "").replace(".", "")
	if cleaned.is_empty():
		return ""
	if LENGTH_UNITS.has(cleaned):
		return cleaned
	return ""


## A stated area, with its unit, in square metres. Zero when it cannot be read,
## which is reported as "no stated area to compare" rather than as agreement.
static func _area_m2(text: String) -> float:
	var cleaned := text.strip_edges().to_lower()
	var tokens := cleaned.split(" ", false)
	if tokens.is_empty():
		return 0.0
	var number_text := String(tokens[0]).replace(",", "")
	if not number_text.is_valid_float():
		return 0.0
	var unit_text := ""
	if tokens.size() > 1:
		unit_text = String(tokens[1]).replace(".", "")
		if unit_text == "sq" and tokens.size() > 2:
			unit_text = "sq " + String(tokens[2])
	if unit_text.is_empty():
		return 0.0
	if not AREA_UNITS.has(unit_text):
		return 0.0
	return number_text.to_float() * float(AREA_UNITS[unit_text])


# --- words --------------------------------------------------------------------------


## One line describing what was read. The report lines say whether it is sound;
## this says what it is, which is the other half of a person's question.
static func describe(parsed: Dictionary) -> String:
	if not bool(parsed.get("ok", false)):
		return String(parsed.get("reason", "the survey could not be read"))
	var kind := String(parsed["kind"])
	var count: int = (parsed["legs"] as Array).size() if kind == METES \
		else (parsed["raw_points"] as Array).size()
	var noun := "leg" if kind == METES else "point"
	var words := "%d %s%s, %s around, %s" % [
		count, noun, "" if count == 1 else "s",
		String.num(float(parsed.get("perimeter_m", 0.0)), 3),
		String.num(float(parsed.get("area_m2", 0.0)), 2),
	]
	return words + " m2"


## Every check the survey engine made, as lines a person reads.
static func report_lines(parsed: Dictionary) -> Array[String]:
	var out: Array[String] = []
	if not bool(parsed.get("ok", false)):
		out.append(String(parsed.get("reason", "the survey could not be read")))
		return out
	var report: Dictionary = parsed["report"]
	for entry: Dictionary in report["records"]:
		out.append("%s: %s - %s" % [
			String(entry.get("status", "pass")).to_upper(),
			String(entry.get("name", "")),
			String(entry.get("message", "")),
		])
	for note: String in parsed["notes"]:
		out.append("NOTE: " + note)
	return out


## Whether the survey may be put on the drawing: a failure blocks it, a warning
## does not. The engine's own rule, read back rather than restated.
static func is_sound(parsed: Dictionary) -> bool:
	if not bool(parsed.get("ok", false)):
		return false
	return bool((parsed["report"] as Dictionary).get("passed", false))


# --- persistence --------------------------------------------------------------------


## What has to survive a file for the survey to be re-read: the source rows, and
## nothing derived. The geometry and the report are recomputed on the way back in,
## so a file cannot carry a stale area or a check that no longer holds.
static func to_dict(parsed: Dictionary) -> Dictionary:
	return {
		"kind": String(parsed.get("kind", "")),
		"units": String(parsed.get("units", "")),
		"title": String(parsed.get("title", "")),
		"source": String(parsed.get("source", "")),
		"stated_area_m2": float(parsed.get("stated_area_m2", 0.0)),
		"legs": parsed.get("legs", []).duplicate(true),
		"raw_points": parsed.get("raw_points", []).duplicate(true),
		"notes": (parsed.get("notes", []) as Array).duplicate(),
	}


static func from_dict(data: Dictionary) -> Dictionary:
	var kind := String(data.get("kind", ""))
	var legs: Array = []
	for entry: Dictionary in data.get("legs", []):
		legs.append({
			"azimuth": float(entry.get("azimuth", 0.0)),
			"distance": float(entry.get("distance", 0.0)),
			"unit": String(entry.get("unit", "")),
			"line": int(entry.get("line", 0)),
		})
	var raw_points: Array = []
	for entry: Dictionary in data.get("raw_points", []):
		raw_points.append({
			"east": float(entry.get("east", 0.0)),
			"north": float(entry.get("north", 0.0)),
			"line": int(entry.get("line", 0)),
		})
	var notes: Array[String] = []
	for note in data.get("notes", []):
		notes.append(String(note))
	if kind == "":
		return _failed("a survey with no bearings and no coordinates in it")
	var parsed := _assemble(
		kind, legs, raw_points, String(data.get("units", "")),
		String(data.get("units", "")), float(data.get("stated_area_m2", 0.0)),
		notes, String(data.get("title", ""))
	)
	parsed["source"] = String(data.get("source", ""))
	return parsed