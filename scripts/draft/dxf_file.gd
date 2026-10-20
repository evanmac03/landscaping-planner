class_name DxfFile
extends RefCounted
## Reading an ASCII DXF into the model geometry a designer can trace over.
##
## ## What a DXF is
##
## A DXF is not a language, it is a stream of *pairs*: a group code on one line and its value on the
## next. `0` opens a record and names its type; `2` names a layer, a section or a table; `8` names the
## layer an entity is on; `10`/`20` are an X and a Y; `70` is a flag whose low bit means "closed".
## Everything else in the file is somebody else's business, which is why this reader walks the pairs
## once and ignores every code it was not asked about.
##
## ## The three things that are easy to get wrong
##
## **Y is up.** A DXF is drawn north-up (REQ 1.2.3): DXF Y is north. The model is east +X and
## *south* +Y - `docs/drafting-subsystem-spec.md` 1.2.3 - so every point is reflected into
## `Vector2(x, -y)`. A mirrored site is visually plausible, which is exactly why REQ 6.7.3 demands a
## test for it rather than a comment. The reflection also reverses handedness, so an arc's sweep and a
## polyline bulge change sign with it.
##
## **Units are not optional.** `$INSUNITS` in the header says what the numbers mean (1 inch, 2 feet,
## 4 mm, 6 m, 21 US survey feet). When it is missing or says 0, a person is asked - `options["units"]`
## - and the file is *refused* if nobody says, because metres and feet differ by a factor of three and
## a design traced on the wrong one is wrong everywhere.
##
## **Nothing is dropped in silence.** Every entity record in the ENTITIES section is counted by type,
## including the ones this reader cannot draw (`INSERT`, `SPLINE`, `HATCH`, ...). The report names
## them, because "it looked like it all came in" is not something a person can check.
##
## ## What it does not do
##
## Blocks are read as a *count* and not followed (REQ 6.7.1 makes `INSERT` optional). A spline, a
## hatch, an ellipse or a 3D polyline is counted and skipped. The geometry arrives at scale and
## unregistered: the caller places it with the options below, and this reader never guesses a
## position.

const UnitsScript := preload("res://scripts/draft/units.gd")
const LayerSetScript := preload("res://scripts/draft/layer_set.gd")

## What `$INSUNITS` means, as the exact factor to metres. The US survey foot is its own length
## (1200/3937 m, exact) and is not the international foot - they differ by 2.0 ppm, which is
## immaterial for a planting layout and material for a legal boundary (REQ 6.6.3).
const UNITS := {
	1: ["inches", UnitsScript.INCH],
	2: ["feet", UnitsScript.FOOT],
	3: ["miles", UnitsScript.MILE],
	4: ["millimetres", UnitsScript.MILLIMETRE],
	5: ["centimetres", UnitsScript.CENTIMETRE],
	6: ["metres", UnitsScript.METRE],
	7: ["kilometres", UnitsScript.KILOMETRE],
	10: ["yards", UnitsScript.YARD],
	21: ["US survey feet", UnitsScript.US_SURVEY_FOOT],
}

## Unit names a person may name in `options["units"]`, for a file that does not say. Kept beside
## `UNITS` so the two cannot drift: a name a person can type is a name a file can state.
const UNIT_NAMES := {
	"metres": UnitsScript.METRE,
	"meters": UnitsScript.METRE,
	"m": UnitsScript.METRE,
	"millimetres": UnitsScript.MILLIMETRE,
	"millimeters": UnitsScript.MILLIMETRE,
	"mm": UnitsScript.MILLIMETRE,
	"centimetres": UnitsScript.CENTIMETRE,
	"centimeters": UnitsScript.CENTIMETRE,
	"cm": UnitsScript.CENTIMETRE,
	"inches": UnitsScript.INCH,
	"inch": UnitsScript.INCH,
	"in": UnitsScript.INCH,
	"feet": UnitsScript.FOOT,
	"foot": UnitsScript.FOOT,
	"ft": UnitsScript.FOOT,
	"US survey feet": UnitsScript.US_SURVEY_FOOT,
	"us-survey-feet": UnitsScript.US_SURVEY_FOOT,
	"yards": UnitsScript.YARD,
	"miles": UnitsScript.MILE,
}

## The layer a DXF layer name maps to, in the mode where the geometry is *kept* rather than traced
## over (REQ 6.7.4). Matched on the upper-cased DXF name, first rule wins, and a name nothing
## recognises goes to the survey layer **with a warning** - never to a plotting layer by accident.
const LAYER_RULES := [
	[["PROPERTY", "BOUNDARY", "LOT", "PARCEL"], LayerSetScript.SURVEY_PROPERTY],
	[["EASEMENT", "SETBACK", "ZONING"], LayerSetScript.SETBACK_EASEMENT],
	[["CONTOUR", "GRADE", "SPOT"], LayerSetScript.GRADING_CONTOUR],
	[["STRUCT", "BLDG", "BUILDING", "HOUSE", "DECK"], LayerSetScript.EXISTING_STRUCTURE],
	[["HARD", "DRIVE", "WALK", "PAVE", "PATIO", "PATH"], LayerSetScript.EXISTING_HARDSCAPE],
	[["PLANT", "TREE", "SHRUB", "GARDEN"], LayerSetScript.EXISTING_PLANTING],
	[["ANNO", "TEXT", "DIM", "LABEL", "NOTE"], LayerSetScript.SURVEY_ANNOTATION],
]

## Where `$INSUNITS` sits in the header.
const INSUNITS_VAR := "$INSUNITS"

## The entity types this reader draws. `POLYLINE` is completed by its `VERTEX` records.
const SUPPORTED := ["LINE", "LWPOLYLINE", "POLYLINE", "CIRCLE", "ARC", "TEXT"]


# --- reading --------------------------------------------------------------------------


## Read DXF text. `options` may carry:
##
## * `"units"` - a unit name, for a file whose `$INSUNITS` is missing or 0 (REQ 6.7.2).
## * `"underlay"` - true (the default) puts everything on the non-plotting underlay layer, which is
##   what a surveyor's file is usually wanted for: something to trace over. False applies the
##   layer-mapping table instead, for a file that is being kept as the survey.
## * `"offset"` - a Vector2 in model metres, added to every point (registration, REQ 6.7.5).
## * `"rotation"` - degrees, applied about the origin before the offset.
##
## Returns a dictionary rather than an object, as `SurveyFile` does: what comes out of it is a table
## of shapes and a table of things to say about them, and a class would only be a second set of names
## for the same two tables.
static func read_text(source: String, options: Dictionary = {}) -> Dictionary:
	if source.strip_edges().is_empty():
		return _refused("the file is empty")
	var pairs := _pairs(source)
	var codes: PackedInt32Array = pairs[0]
	var values: PackedStringArray = pairs[1]
	if codes.size() < 2:
		return _refused("that file is not a DXF: there is not one code-and-value pair in it")
	if codes[0] != 0 or values[0].strip_edges().to_upper() != "SECTION":
		return _refused("that file is not an ASCII DXF: one begins with a 0/SECTION pair")
	var found := _walk(codes, values)
	if not bool(found["ok"]):
		return _refused(String(found["reason"]))

	# The units, before anything is scaled: the file's own answer first, then the one a person gave.
	var stated := units_for(int(found["insunits"]), String(options.get("units", "")))
	if float(stated["factor"]) <= 0.0:
		return _refused(String(stated["reason"]))

	var plan := {
		"ok": true, "reason": "", "source": "",
		"units": String(stated["name"]), "unit_factor": float(stated["factor"]),
		"units_from": String(stated["source"]), "insunits": int(found["insunits"]),
		"layer_names": found["layers"], "counts": found["counts"],
		"unsupported": found["unsupported"], "blocks": int(found["blocks"]),
		"bad_numbers": int(found["bad_numbers"]),
		"missing_layer": int(found["missing_layer"]),
		"underlay": bool(options.get("underlay", true)),
		"offset": options.get("offset", Vector2.ZERO),
		"rotation": float(options.get("rotation", 0.0)),
		"warnings": [] as Array[String],
		"shapes": [] as Array[Dictionary],
	}
	_finish(plan, found["raw"])
	return plan


## Read a DXF from disk. A missing or unreadable file is refused with a reason rather than raising,
## because it is a path a person typed.
static func of_file(path: String, options: Dictionary = {}) -> Dictionary:
	if path.is_empty():
		return _refused("no file was named")
	if not FileAccess.file_exists(path):
		return _refused("there is no file called %s" % path.get_file())
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return _refused("cannot read %s" % path.get_file())
	var source := file.get_as_text()
	file.close()
	var plan := read_text(source, options)
	if bool(plan["ok"]):
		plan["source"] = path.get_file()
	return plan


## Split the text into its code-and-value pairs.
##
## The pairs are two parallel arrays rather than an array of pairs, because that is how they are
## walked: a cursor over the codes with the values beside it. Codes are integers; a line that is not
## one is damage, and the pair is dropped rather than shifting every pair after it out of step.
static func _pairs(source: String) -> Array:
	var codes := PackedInt32Array()
	var values := PackedStringArray()
	var lines := source.replace("\r\n", "\n").replace("\r", "\n").split("\n")
	var index := 0
	while index + 1 < lines.size():
		var code_line := lines[index].strip_edges()
		if not code_line.is_valid_int():
			index += 1
			continue
		codes.append(code_line.to_int())
		values.append(lines[index + 1].strip_edges())
		index += 2
	return [codes, values]


## Walk the pairs once, collecting what the header, the tables and the entities say.
##
## A linear walk rather than a section-by-section one, because the header is what says the units and
## it comes before the geometry: reading it in one pass means the geometry never has to be held
## unscaled and then rescaled.
static func _walk(codes: PackedInt32Array, values: PackedStringArray) -> Dictionary:
	var out := {
		"ok": true, "reason": "", "insunits": 0, "layers": [] as Array[String],
		"raw": [] as Array[Dictionary], "counts": {},
		"unsupported": [] as Array[String], "blocks": 0, "bad_numbers": 0, "missing_layer": 0,
	}
	var section := ""
	var header_var := ""
	var count := codes.size()
	var index := 0
	while index < count:
		var code := codes[index]
		var value := values[index]
		# A record opens at code 0, and what it is depends on where the walk is.
		if code == 0:
			var record := value.to_upper()
			if record == "SECTION":
				section = _following(codes, values, index, 2)
				index += 2
				continue
			elif record == "ENDSEC":
				section = ""
				index += 1
				continue
			elif record == "VERTEX" or record == "SEQEND":
				# A `POLYLINE` reads its own vertices and leaves the walk standing on its `SEQEND`:
				# these records belong to an entity that has already been read, and counting them
				# would say the file holds shapes it does not.
				index += 1
				continue
			elif section == "TABLES" and record == "LAYER":
				var layer_name := _record_value(codes, values, index, 2)
				if not layer_name.is_empty() and not (out["layers"] as Array).has(layer_name):
					(out["layers"] as Array).append(layer_name)
				index = _next_record(codes, index)
				continue
			elif section == "ENTITIES":
				var taken := _entity(codes, values, index)
				var kind := String(taken["kind"])
				if not kind.is_empty():
					var kinds: Dictionary = out["counts"]
					kinds[kind] = int(kinds.get(kind, 0)) + 1
					if String(taken["reason"]).is_empty():
						(out["raw"] as Array).append(taken)
					else:
						out["bad_numbers"] = int(out["bad_numbers"]) + 1
					if not SUPPORTED.has(kind) and not (out["unsupported"] as Array).has(kind):
						(out["unsupported"] as Array).append(kind)
				index = int(taken["next"])
				continue
			elif section == "BLOCKS":
				# Counted rather than followed: nothing inside a block reaches the drawing yet. Only
				# the `BLOCK` record itself counts - the shapes between it and `ENDBLK` are not blocks.
				if record == "BLOCK":
					out["blocks"] = int(out["blocks"]) + 1
				index += 1
				continue
			index += 1
			continue
		# Not a record: a value inside one. The only values this reader wants are the header's, and
	# everything else is somebody else's business.
		if section == "HEADER":
			if code == 9:
				header_var = value
			elif header_var == INSUNITS_VAR and code == 70:
				out["insunits"] = value.strip_edges().to_int()
		index += 1
	return out


## The value of the code that follows a record at `index`, expecting `code`. Used for the one two-code
## form the reader leans on: `0/SECTION` + `2/<name>`, which is how a DXF says where it is.
static func _following(codes: PackedInt32Array, values: PackedStringArray, index: int, code: int) -> String:
	var at := index + 1
	while at < codes.size() and codes[at] != 0:
		if codes[at] == code:
			return values[at]
		at += 1
	return ""


## The first value of one code inside the record that starts at `index`.
static func _record_value(codes: PackedInt32Array, values: PackedStringArray, index: int, code: int) -> String:
	var at := index + 1
	while at < codes.size() and codes[at] != 0:
		if codes[at] == code:
			return values[at]
		at += 1
	return ""


## Every value of one code inside the record that starts at `index`.
static func _record_values(codes: PackedInt32Array, values: PackedStringArray, index: int, code: int) -> PackedStringArray:
	var out := PackedStringArray()
	var at := index + 1
	while at < codes.size() and codes[at] != 0:
		if codes[at] == code:
			out.append(values[at])
		at += 1
	return out


## Where the next record begins, which is where the current one ends.
static func _next_record(codes: PackedInt32Array, index: int) -> int:
	var at := index + 1
	while at < codes.size() and codes[at] != 0:
		at += 1
	return at


## Read one entity record into raw geometry: kinds and numbers, with no scaling and no flip. What a
## record means in the model is decided once, in `_finish`.
static func _entity(codes: PackedInt32Array, values: PackedStringArray, index: int) -> Dictionary:
	var kind := values[index].strip_edges().to_upper()
	var out := {"kind": kind, "reason": "", "next": _next_record(codes, index)}
	var layer := _record_value(codes, values, index, 8)
	var closed := (int(_record_value(codes, values, index, 70).to_int()) & 1) == 1
	var points := PackedVector2Array()
	var bulges := PackedFloat64Array()
	match kind:
		"LINE":
			var a: Variant = _point(codes, values, index, 10, 20)
			var b: Variant = _point(codes, values, index, 11, 21)
			if a == null or b == null:
				out["reason"] = "a line with a number that could not be read"
				return out
			points.append(a)
			points.append(b)
		"CIRCLE", "ARC":
			var centre: Variant = _point(codes, values, index, 10, 20)
			var radius := _number(codes, values, index, 40)
			if centre == null or is_nan(radius):
				out["reason"] = "a %s with a number that could not be read" % kind.to_lower()
				return out
			points.append(centre)
			points.append(Vector2(radius, 0.0))
			if kind == "ARC":
				var start := _number(codes, values, index, 50)
				var finish := _number(codes, values, index, 51)
				if is_nan(start) or is_nan(finish):
					out["reason"] = "an arc with an angle that could not be read"
					return out
				# Kept as the file's own degrees, not turned into a point: the reflection that makes
				# DXF north into model south also reverses which way round a circle is drawn, and
				# folding that into a pair of coordinates would hide it.
				out["dxf_arc"] = Vector2(start, finish)
		"TEXT":
			var at_point: Variant = _point(codes, values, index, 10, 20)
			var height := _number(codes, values, index, 40)
			if at_point == null:
				out["reason"] = "a text with a position that could not be read"
				return out
			points.append(at_point)
			out["dxf_height"] = 0.0 if is_nan(height) else height
			out["words"] = _record_value(codes, values, index, 1)
		"LWPOLYLINE":
			var xs := _numbers(codes, values, index, 10)
			var ys := _numbers(codes, values, index, 20)
			var bs := _numbers(codes, values, index, 42)
			if xs.size() != ys.size() or xs.is_empty():
				out["reason"] = "a polyline whose points do not pair up"
				return out
			for at in xs.size():
				if is_nan(xs[at]) or is_nan(ys[at]):
					out["reason"] = "a polyline with a number that could not be read"
					return out
				points.append(Vector2(xs[at], ys[at]))
				bulges.append(0.0 if at >= bs.size() or is_nan(bs[at]) else bs[at])
		"POLYLINE":
			# The vertices are separate records after this one, until SEQEND.
			var at: int = int(out["next"])
			while at < codes.size() and codes[at] == 0 and values[at].strip_edges().to_upper() == "VERTEX":
				var vertex: Variant = _point(codes, values, at, 10, 20)
				if vertex == null:
					out["reason"] = "a polyline with a vertex that could not be read"
					return out
				points.append(vertex)
				var bulge := _number(codes, values, at, 42)
				bulges.append(0.0 if is_nan(bulge) else bulge)
				at = _next_record(codes, at)
			out["next"] = at
		_:
			out["reason"] = ""
	var shape := {
		"kind": kind, "dxf_layer": layer, "closed": closed,
		"points": points, "bulges": bulges, "words": String(out.get("words", "")),
		"dxf_arc": out.get("dxf_arc", Vector2.ZERO),
		"dxf_height": float(out.get("dxf_height", 0.0)),
	}
	out["shape"] = shape
	return out


## A point from two codes, or null when either number could not be read.
static func _point(codes: PackedInt32Array, values: PackedStringArray, index: int, x_code: int, y_code: int) -> Variant:
	var x := _number(codes, values, index, x_code)
	var y := _number(codes, values, index, y_code)
	if is_nan(x) or is_nan(y):
		return null
	return Vector2(x, y)


## One number, or NAN when the value is there and cannot be read - which is the difference between a
## missing code (0) and a damaged one, and only the second is worth refusing.
static func _number(codes: PackedInt32Array, values: PackedStringArray, index: int, code: int) -> float:
	var found := _record_value(codes, values, index, code)
	if found.is_empty():
		return 0.0
	if not found.is_valid_float():
		return NAN
	return found.to_float()


## Every value of one code as numbers; a value that cannot be read becomes NAN and is caught by the
## caller, which refuses that entity rather than placing a point at the origin.
static func _numbers(codes: PackedInt32Array, values: PackedStringArray, index: int, code: int) -> PackedFloat64Array:
	var out := PackedFloat64Array()
	for raw: String in _record_values(codes, values, index, code):
		out.append(raw.to_float() if raw.is_valid_float() else NAN)
	return out


# --- units ----------------------------------------------------------------------------


## What a DXF's numbers are in. The file's own `$INSUNITS` is believed when it says something;
## `asked` is what a person said when it does not. A file that says nothing and a caller that said
## nothing is refused with the sentence that asks, because this is the one question the file cannot
## be read sensibly without.
static func units_for(insunits: int, asked: String = "") -> Dictionary:
	if insunits != 0 and UNITS.has(insunits):
		return {
			"name": String(UNITS[insunits][0]), "factor": float(UNITS[insunits][1]),
			"source": "the file's own $INSUNITS", "reason": "",
		}
	var wanted := asked.strip_edges().to_lower()
	if not wanted.is_empty() and UNIT_NAMES.has(wanted):
		return {
			"name": wanted, "factor": float(UNIT_NAMES[wanted]),
			"source": "what was asked for", "reason": "",
		}
	if insunits != 0:
		return {
			"name": "", "factor": 0.0, "source": "",
			"reason": "the file says its units are code %d, which is not a unit this reads" % insunits,
		}
	return {
		"name": "", "factor": 0.0, "source": "",
		"reason": "the file does not say whether it is in metres or feet, so it has to be asked about",
	}


# --- what the geometry becomes --------------------------------------------------------


## Scale, reflect and register every raw shape, and map the DXF layer each one is on.
##
## One place, once: the reflection that makes DXF Y north into model *south* is
## `Vector2(x, -y)`, and applying it here rather than at each of the six shapes is what makes it a
## single test rather than six chances to forget it.
static func _finish(plan: Dictionary, raw: Array) -> void:
	var factor: float = float(plan["unit_factor"])
	var offset: Vector2 = plan["offset"] as Vector2
	var turn := deg_to_rad(float(plan["rotation"]))
	var unknown: Array[String] = []
	var shapes: Array[Dictionary] = []
	for entry: Dictionary in raw:
		var kind := String(entry["kind"])
		if not SUPPORTED.has(kind):
			continue
		var raw_shape: Dictionary = entry["shape"]
		var points := PackedVector2Array()
		for point: Vector2 in (raw_shape["points"] as PackedVector2Array):
			var model := Vector2(point.x, -point.y) * factor
			if not is_zero_approx(turn):
				model = model.rotated(turn)
			points.append(model + offset)
		var bulges := PackedFloat64Array()
		for bulge: float in (raw_shape["bulges"] as PackedFloat64Array):
			# The reflection reverses handedness, so a bulge that turned left now turns right.
			bulges.append(-bulge)
		var mapped := layer_for(String(raw_shape["dxf_layer"]), bool(plan["underlay"]))
		if not String(mapped["warning"]).is_empty() and not unknown.has(String(mapped["warning"])):
			unknown.append(String(mapped["warning"]))
		var shape := {
			"kind": kind,
			"layer": mapped["layer"],
			"dxf_layer": String(raw_shape["dxf_layer"]),
			"points": points,
			"bulges": bulges,
			"closed": bool(raw_shape["closed"]),
			"words": String(raw_shape["words"]),
			"height": float(raw_shape["dxf_height"]) * factor,
			"arc": Vector2.ZERO,
		}
		# An arc's angles, in the model's own frame. A DXF arc runs counterclockwise from 50 to 51,
		# and the reflection that sends north to -Y reverses handedness: a point at angle t lands at
		# -t, so the run from `a` up to `b` is the run from `-a` *down* to `-b`. Written as a start
		# and a sweep so the model has one way to say it.
		if kind == "ARC":
			var dxf_arc: Vector2 = raw_shape["dxf_arc"]
			shape["arc"] = Vector2(-dxf_arc.x, -fposmod(dxf_arc.y - dxf_arc.x, 360.0))
		shapes.append(shape)
	plan["shapes"] = shapes
	# The warnings last, so they read as what was noticed rather than as where the file started.
	var warnings: Array[String] = plan["warnings"]
	for words: String in unknown:
		warnings.append(words)
	if int(plan["bad_numbers"]) > 0:
		warnings.append(
			"%d shape(s) carried a number that could not be read and were left out"
			% int(plan["bad_numbers"])
		)
	if int(plan["blocks"]) > 0:
		warnings.append(
			"%d block(s) were not read: a block is a group of shapes this importer does not follow yet"
			% int(plan["blocks"])
		)


## Where a DXF layer's geometry goes.
##
## In the underlay mode - the default, and what this app mostly wants a surveyor's file for - all of
## it goes to `950-UNDERLAY`, which does not plot: a tracing aid that cannot reach the sheet. In the
## kept mode the mapping table applies, and a layer nothing recognises goes to the survey layer
## **with a warning** rather than to a layer that plots by accident (REQ 6.7.4).
static func layer_for(dxf_layer: String, underlay: bool = true) -> Dictionary:
	if underlay:
		return {"layer": LayerSetScript.UNDERLAY, "warning": ""}
	var upper := dxf_layer.strip_edges().to_upper()
	for rule: Array in LAYER_RULES:
		for word: String in (rule[0] as Array):
			if upper.contains(word):
				return {"layer": rule[1], "warning": ""}
	return {
		"layer": LayerSetScript.SURVEY_PROPERTY,
		"warning": "layer \"%s\" is not one this recognises, so it went to the survey layer" % dxf_layer,
	}


static func _refused(reason: String) -> Dictionary:
	return {
		"ok": false, "reason": reason, "source": "", "shapes": [] as Array[Dictionary],
		"units": "", "unit_factor": 0.0, "units_from": "", "insunits": 0,
		"layer_names": [] as Array[String], "counts": {}, "unsupported": [] as Array[String],
		"blocks": 0, "bad_numbers": 0, "missing_layer": 0, "warnings": [] as Array[String],
		"underlay": true, "offset": Vector2.ZERO, "rotation": 0.0,
	}


# --- saying what was read -------------------------------------------------------------


## One line saying what the file holds: how many shapes, and what units they are in.
static func describe(plan: Dictionary) -> String:
	if not bool(plan.get("ok", false)):
		return String(plan.get("reason", "the file could not be read"))
	var shapes: Array = plan.get("shapes", [])
	var words := "%d shape%s in %s" % [
		shapes.size(), "" if shapes.size() == 1 else "s", String(plan["units"])
	]
	if String(plan["units_from"]) == "what was asked for":
		words += ", because the file does not say"
	return words


## Whether there is anything to put on the drawing.
static func is_usable(plan: Dictionary) -> bool:
	return bool(plan.get("ok", false)) and not (plan.get("shapes", []) as Array).is_empty()


## Everything the reader noticed, one line each: what it read, what it skipped, and where each DXF
## layer's geometry went. A person accepts an import by reading this and nothing else.
static func report_lines(plan: Dictionary) -> Array[String]:
	var lines: Array[String] = []
	if not bool(plan.get("ok", false)):
		lines.append(String(plan.get("reason", "the file could not be read")))
		return lines
	lines.append("%s, read as %s (x%s)" % [
		describe(plan), String(plan["units_from"]), String.num(float(plan["unit_factor"]), 6)
	])
	var counts: Dictionary = plan["counts"]
	if counts.is_empty():
		lines.append("there are no entity records in it")
	else:
		var read: Array[String] = []
		for kind: Variant in counts:
			read.append("%s x%d" % [String(kind), int(counts[kind])])
		read.sort()
		lines.append("what is in it: " + ", ".join(read))
	var unsupported: Array = plan["unsupported"]
	if not unsupported.is_empty():
		var named: Array[String] = []
		for kind: Variant in unsupported:
			named.append(String(kind))
		lines.append("not read: " + ", ".join(named))
	# Where each layer's geometry went, which is the thing a person cannot see from the drawing.
	var where := {}
	for shape: Dictionary in (plan["shapes"] as Array):
		var from := String(shape["dxf_layer"])
		if from.is_empty():
			from = "(no layer)"
		where[from] = String(shape["layer"])
	var names: Array = where.keys()
	names.sort()
	for from: Variant in names:
		lines.append("  %s -> %s" % [String(from), String(where[from])])
	lines.append("placed at the origin, at scale" if Vector2(plan["offset"]) == Vector2.ZERO
		else "placed %.2f m east and %.2f m north of the origin" % [
			Vector2(plan["offset"]).x, -Vector2(plan["offset"]).y
		])
	if not is_zero_approx(float(plan["rotation"])):
		lines.append("turned %.1f degrees" % float(plan["rotation"]))
	for words: String in (plan["warnings"] as Array):
		lines.append("! " + words)
	return lines