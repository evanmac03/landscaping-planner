class_name LandXmlFile
extends RefCounted
## Reading a LandXML plat into the model geometry a designer can trace over.
##
## ## What a LandXML file is
##
## LandXML is what a civil engineer's or a surveyor's software writes when it wants to hand a *site*
## to somebody else's software: parcels, alignments, plan line work and a coordinate point database,
## all in one XML document. Where a DXF is a stream of code-and-value pairs and an Overpass response
## is a JSON tree of tags, this is an XML tree of *features*, and each feature carries the geometry it
## was drawn from.
##
## ## This is the third reader, and it speaks the same table
##
## `DxfFile` fills a table of shapes; `OsmFile` fills the same table; this fills it too, and
## `DraftController._entity_from_shape` is the one place any of the three becomes a drawing entity.
## That was a decision made twice and is now a claim under test (`tests/test_shape_table.gd`): a third
## format with a different *coordinate convention*, a different *closure rule* and a different
## *curve statement* still needs nothing new in the table. What is not shared is the units: a DXF
## states `$INSUNITS` as a code, LandXML names its linear unit in words, and a survey states its own -
## units are a fact about a file format, not about a shape, so each reader answers that question itself
## and the table is geometry in model metres by the time it is written.
##
## ## The three things that are easy to get wrong
##
## **The coordinate order is northing first.** A LandXML point is written `"north east"` or
## `"north east elev"` - the schema's own words for `PointType` - so a pair is *swapped* and not merely
## reflected. The model is east +X and north -Y (`docs/drafting-subsystem-spec.md` 1.2.3), so the
## mapping is `Vector2(easting, -northing)`, and a reader that takes the pair as (x, y) draws every
## plat correctly *turned a quarter turn*, which looks entirely plausible on screen. That is why there
## is a test with a northing and an easting an order of magnitude apart.
##
## **A point may be a reference, not a coordinate.** `<Start>1000 2000</Start>` and
## `<Start pntRef="31"/>` are both the same point, and the second one means "look up CgPoint 31". So
## the file is read in one pass into a table of points plus a list of segments that may still be
## references, and the references are resolved at the end - the same two-step the DXF reader would
## need for a block, done here because a parcel built out of `pntRef`s is the ordinary case rather
## than the exception.
##
## **A curve is a bulge.** A `Curve` states its own centre, and `rot` says which way round from the
## start to the end - which is exactly what a polyline bulge is: the same arc, expressed as the turn
## between two points. So an alignment arrives as *one* polyline whose curves are bulges, rather than
## as a fan of separate arcs, and a curve whose centre is missing cannot be reconstructed and is
## refused rather than guessed at.
##
## ## Nothing is dropped in silence
##
## Every feature is either drawn or counted under the reason it was not, and a *piece of geometry*
## this reader does not understand - a spiral, which is neither a line nor an arc - **breaks the line
## it is in and is named**, because joining the two sides of a spiral with a straight line would be
## drawing something the file does not say. `report_lines` prints all of it, and a person accepts an
## import by reading that and nothing else.

const UnitsScript := preload("res://scripts/draft/units.gd")
const LayerSetScript := preload("res://scripts/draft/layer_set.gd")

## What a LandXML `linearUnit` attribute means, as the exact factor to metres. LandXML names its units
## in words rather than by a code (`linearUnit="USSurveyFoot"`), so this table is keyed by the
## normalised name - case, spaces and underscores folded away - and it also holds the plain names a
## person may type when the file does not say. The US survey foot is its own length (1200/3937 m,
## exact) and is not the international foot: they differ by 2.0 ppm, which is immaterial for a
## planting layout and material for a legal boundary (REQ 6.6.3).
const LINEAR_UNITS := {
	"meter": UnitsScript.METRE, "meters": UnitsScript.METRE,
	"metre": UnitsScript.METRE, "metres": UnitsScript.METRE, "m": UnitsScript.METRE,
	"millimeter": UnitsScript.MILLIMETRE, "millimeters": UnitsScript.MILLIMETRE,
	"millimetre": UnitsScript.MILLIMETRE, "millimetres": UnitsScript.MILLIMETRE,
	"mm": UnitsScript.MILLIMETRE,
	"centimeter": UnitsScript.CENTIMETRE, "centimeters": UnitsScript.CENTIMETRE,
	"centimetre": UnitsScript.CENTIMETRE, "centimetres": UnitsScript.CENTIMETRE,
	"cm": UnitsScript.CENTIMETRE,
	"kilometer": UnitsScript.KILOMETRE, "kilometers": UnitsScript.KILOMETRE,
	"kilometre": UnitsScript.KILOMETRE, "kilometres": UnitsScript.KILOMETRE,
	"km": UnitsScript.KILOMETRE,
	"foot": UnitsScript.FOOT, "feet": UnitsScript.FOOT, "ft": UnitsScript.FOOT,
	"internationalfoot": UnitsScript.FOOT, "internationalfeet": UnitsScript.FOOT,
	"ussurveyfoot": UnitsScript.US_SURVEY_FOOT, "ussurveyfeet": UnitsScript.US_SURVEY_FOOT,
	"usfoot": UnitsScript.US_SURVEY_FOOT,
	"inch": UnitsScript.INCH, "inches": UnitsScript.INCH, "in": UnitsScript.INCH,
	"yard": UnitsScript.YARD, "yards": UnitsScript.YARD, "yd": UnitsScript.YARD,
	"mile": UnitsScript.MILE, "miles": UnitsScript.MILE, "mi": UnitsScript.MILE,
}

## What each of those lengths is *called* in a report. A file names its unit in its own single word -
## `linearUnit="meter"`, `linearUnit="USSurveyFoot"` - and a person reads a sentence, so the words are
## this reader's and the file's own spelling is kept beside them in `declared_unit`. Every length
## `LINEAR_UNITS` can read has a word here, and a test says so: a length this reader can read and
## cannot name is half a reader.
const UNIT_WORDS := {
	"meter": "metres", "meters": "metres", "metre": "metres", "metres": "metres", "m": "metres",
	"millimeter": "millimetres", "millimeters": "millimetres",
	"millimetre": "millimetres", "millimetres": "millimetres", "mm": "millimetres",
	"centimeter": "centimetres", "centimeters": "centimetres",
	"centimetre": "centimetres", "centimetres": "centimetres", "cm": "centimetres",
	"kilometer": "kilometres", "kilometers": "kilometres",
	"kilometre": "kilometres", "kilometres": "kilometres", "km": "kilometres",
	"foot": "feet", "feet": "feet", "ft": "feet",
	"internationalfoot": "feet", "internationalfeet": "feet",
	"ussurveyfoot": "US survey feet", "ussurveyfeet": "US survey feet", "usfoot": "US survey feet",
	"inch": "inches", "inches": "inches", "in": "inches",
	"yard": "yards", "yards": "yards", "yd": "yards",
	"mile": "miles", "miles": "miles", "mi": "miles",
}

## The containers whose `CoordGeom` this reader draws, and where each kind goes in the mode where the
## geometry is *kept* rather than traced over. The element name is the key, because that is what
## LandXML names a feature by. A `Parcel` is a closed boundary, which is why it is the one `area` row:
## a parcel is a ring **by the format's own definition**, not because its first and last point
## coincide, so closure is taken from the container rather than inferred from the geometry - the
## opposite of how `OsmFile` has to do it.
const FEATURES := {
	"Parcel": {"kind": "parcel", "layer": LayerSetScript.SURVEY_PROPERTY, "area": true},
	"Alignment": {"kind": "alignment", "layer": LayerSetScript.EXISTING_HARDSCAPE, "area": false},
	"PlanFeature": {"kind": "plan feature", "layer": LayerSetScript.SURVEY_PROPERTY, "area": false},
}

## What a `CoordGeom` is made of. Anything else found inside one is counted, named, and made to *break*
## the line it is in - see the header.
const SEGMENTS: Array[String] = ["Line", "Curve", "IrregularLine"]

## Subtrees this reader does not follow, counted by name like a DXF block. A surface is a TIN of
## thousands of points, a pipe network is a graph of pipes: each is a whole problem of its own, and
## saying so is better than half-reading one.
const SKIP_TAGS: Array[String] = [
	"Surface", "PipeNetwork", "Roadway", "TypicalSection", "CrossSect", "GradeSurface",
	"CoordinateSystem", "Monuments",
]

## How many shapes one import will draw. A plat of a subdivision is tens; a corridor model's plan line
## work runs to thousands, and a drawing that takes a minute to open is not a drawing.
const MAX_SHAPES := 4000

## Two points closer than this are the same point. The coordinates here are the file's own units, so
## this is a hair at either metres or feet; a shape closes when its last point lands on its first.
const SAME_POINT := 1.0e-9


# --- reading --------------------------------------------------------------------------

## Read LandXML text. `options` may carry:
##
## * `"units"` - a unit name, for a file whose `<Units>` says nothing. A file that states its own
##   linear unit ignores this, for the reason the DXF reader ignores it: a file stating feet is not
##   asking to be told.
## * `"underlay"` - true (the default) puts everything on the non-plotting underlay layer, which is
##   what a surveyor's or a civil engineer's file is usually wanted for: something to trace over.
##   False keeps the geometry on the layers `FEATURES` names.
## * `"points"` - true writes a named `CgPoint` on the drawing as a text entity. False (the default)
##   leaves the point database out of the drawing: a point database is not line work, and a thousand
##   labelled shots over a garden plan is not a drawing.
## * `"offset"` - a Vector2 in model metres, added to every point (registration).
## * `"rotation"` - degrees, applied about the origin before the offset.
##
## Returns a dictionary rather than an object, as `SurveyFile`, `DxfFile` and `OsmFile` do: what comes
## out is a table of shapes and a table of things to say about them.
static func read_text(source: String, options: Dictionary = {}) -> Dictionary:
	if source.strip_edges().is_empty():
		return refused("the file is empty")
	var parser := XMLParser.new()
	if parser.open_buffer(source.to_utf8_buffer()) != OK:
		return refused("that file is not XML: it cannot even be opened as text")
	var found := _walk(parser)
	if not bool(found["ok"]):
		return refused(String(found["reason"]))
	if not bool(found["is_landxml"]):
		return refused("that file is not a LandXML plat: one begins with a LandXML element")
	# The units, before anything is scaled: the file's own answer first, then the one a person gave.
	var stated := units_for(String(found["declared_unit"]), String(options.get("units", "")))
	if float(stated["factor"]) <= 0.0:
		return refused(String(stated["reason"]))
	var plan := {
		"ok": true, "reason": "", "source": "",
		"units": String(stated["name"]), "unit_factor": float(stated["factor"]),
		"units_from": String(stated["source"]), "declared_unit": String(found["declared_unit"]),
		"underlay": bool(options.get("underlay", true)),
		"points": bool(options.get("points", false)),
		"offset": options.get("offset", Vector2.ZERO),
		"rotation": float(options.get("rotation", 0.0)),
		"raw": found["shapes"],
		"shapes": [] as Array[Dictionary],
		"counts": found["counts"], "skipped": found["skipped"],
		"layers": [] as Array[String],
		"cg_points": int(found["cg_points"]),
		"refs": int(found["refs"]),
		"curves": int(found["curves"]),
		"broken": int(found["broken"]),
		"too_many": int(found["too_many"]),
		"bad_refs": int(found["bad_refs"]),
		"bad_points": int(found["bad_points"]),
		"warnings": [] as Array[String],
	}
	_finish(plan)
	return plan


## Read a plat from disk. A missing or unreadable file is refused with a reason rather than raising,
## because it is a path a person chose.
static func of_file(path: String, options: Dictionary = {}) -> Dictionary:
	if path.is_empty():
		return refused("no file was named")
	if not FileAccess.file_exists(path):
		return refused("there is no file called %s" % path.get_file())
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return refused("cannot read %s" % path.get_file())
	var source := file.get_as_text()
	file.close()
	var plan := read_text(source, options)
	if bool(plan["ok"]):
		plan["source"] = path.get_file()
	return plan


## The normalised form of a unit name: case, spaces and underscores are not part of what a unit is,
## and a file that writes `USSurveyFoot` and a person who types `us survey feet` mean the same length.
static func _key(unit_name: String) -> String:
	return unit_name.strip_edges().to_lower().replace(" ", "").replace("_", "").replace("-", "")


## What a LandXML's numbers are in. The file's own `linearUnit` is believed when it says something;
## `asked` is what a person said when it does not. A file that says nothing and a caller that said
## nothing is refused with the sentence that asks, because this is the one question a plat cannot be
## read sensibly without.
static func units_for(declared: String, asked: String = "") -> Dictionary:
	var stated := _key(declared)
	if not stated.is_empty():
		if LINEAR_UNITS.has(stated):
			return {
				"name": String(UNIT_WORDS.get(stated, declared.strip_edges())),
				"factor": float(LINEAR_UNITS[stated]),
				"source": "the file's own linear unit", "reason": "",
			}
		return {
			"name": "", "factor": 0.0, "source": "",
			"reason": "the file says its linear unit is \"%s\", which is not a unit this reads" % declared,
		}
	var wanted := _key(asked)
	if not wanted.is_empty() and LINEAR_UNITS.has(wanted):
		return {
			"name": String(UNIT_WORDS.get(wanted, asked.strip_edges())),
			"factor": float(LINEAR_UNITS[wanted]),
			"source": "what was asked for", "reason": "",
		}
	return {
		"name": "", "factor": 0.0, "source": "",
		"reason": "the file does not say whether it is in metres or feet, so it has to be asked about",
	}


# --- walking the document -------------------------------------------------------------


## One pass over the document, into a table of points, a list of segments that may still be
## references, and the counts a report is made of.
##
## The tree is walked with the open elements kept as a stack, rather than by looking for a named
## section: what a `Start` means depends on whether the thing above it is a `Curve` or an
## `Alignment`, and a stack is the cheapest way to know that.
static func _walk(parser: XMLParser) -> Dictionary:
	var found := {
		"ok": true, "reason": "", "is_landxml": false, "declared_unit": "",
		"shapes": [] as Array[Dictionary], "counts": {}, "skipped": {},
		"cg_points": 0, "refs": 0, "curves": 0, "broken": 0, "too_many": 0,
		"bad_refs": 0, "bad_points": 0,
	}
	var state := {
		"found": found,
		"stack": [] as Array[String],
		"skip_depth": -1,
		"feature": {} as Dictionary,
		"coord": {} as Dictionary,
		"segment": {} as Dictionary,
		"cg_points": {} as Dictionary,
		"point_name": "",
	}
	while true:
		var error := parser.read()
		if error == ERR_FILE_EOF:
			break
		if error != OK:
			# A document that stops part way through is damaged, not empty: saying nothing about it
			# would look exactly like a plat with no features in it.
			found["ok"] = false
			found["reason"] = (
				"the file stops part way through: it is not well-formed XML (around line %d)"
				% (parser.get_current_line() + 1)
			)
			return found
		var kind: int = parser.get_node_type()
		if kind == XMLParser.NODE_ELEMENT:
			var element := parser.get_node_name()
			(state["stack"] as Array[String]).append(element)
			if (state["stack"] as Array).size() == 1:
				found["is_landxml"] = element == "LandXML"
			_open_element(element, parser, state)
			# An empty element - `<Start pntRef="31"/>`, which is the ordinary way a plat names a point
			# - is opened and closed by *one* node: the parser sends no end node for it, so a stack
			# that waited for one would be left standing a level too deep for the rest of the file.
			if parser.is_empty():
				_close_element(element, state)
				var opened: Array = state["stack"]
				opened.remove_at(opened.size() - 1)
		elif kind == XMLParser.NODE_ELEMENT_END:
			_close_element(parser.get_node_name(), state)
			var stack: Array = state["stack"]
			if not stack.is_empty():
				stack.remove_at(stack.size() - 1)
			if int(state["skip_depth"]) >= 0 and stack.size() < int(state["skip_depth"]):
				state["skip_depth"] = -1
		elif kind == XMLParser.NODE_TEXT or kind == XMLParser.NODE_CDATA:
			_text(parser.get_node_data(), state)
	# A document that stops part way through ends at end-of-file rather than in a parse error, so the
	# one thing that says it was cut short is an element still open when the text ran out.
	if not (state["stack"] as Array).is_empty():
		found["ok"] = false
		found["reason"] = (
			"the file stops part way through: it is not well-formed XML (around line %d)"
			% (parser.get_current_line() + 1)
		)
	return found


## What an element is, as it opens. Attributes are read here rather than at the end, because a
## self-closing `<Start pntRef="31"/>` is over before any end node arrives - and it is the one form
## that carries no text at all.
static func _open_element(element: String, parser: XMLParser, state: Dictionary) -> void:
	var stack: Array = state["stack"]
	var depth: int = stack.size()
	# Inside a subtree this does not follow: nothing here is looked at until it ends.
	if int(state["skip_depth"]) >= 0:
		return
	if SKIP_TAGS.has(element):
		state["skip_depth"] = depth
		_bump(state["found"]["skipped"], "a %s, which is a whole problem of its own" % element.to_lower())
		return
	if element == "Metric" or element == "Imperial":
		if depth >= 2 and String(stack[depth - 2]) == "Units":
			state["found"]["declared_unit"] = parser.get_named_attribute_value_safe("linearUnit")
		return
	if element == "CgPoint":
		if depth >= 2 and String(stack[depth - 2]) == "CgPoints":
			state["point_name"] = parser.get_named_attribute_value_safe("name")
		return
	if FEATURES.has(element):
		state["feature"] = {
			"tag": element,
			"name": parser.get_named_attribute_value_safe("name"),
			"desc": parser.get_named_attribute_value_safe("desc"),
		}
		return
	if element == "CoordGeom":
		state["coord"] = {"segments": [] as Array[Dictionary], "owner": (state["feature"] as Dictionary).duplicate()}
		return
	if depth < 2:
		return
	var parent := String(stack[depth - 2])
	# The points of a segment, which may be a coordinate written in the file or the *name* of a
	# `CgPoint` it holds elsewhere. Read as the element opens, because a self-closing
	# `<Start pntRef="31"/>` is over before any text node arrives - and a coordinate written as text
	# overwrites the reference, which is the schema's own rule for a point that states both.
	if SEGMENTS.has(parent):
		var segment_ref := parser.get_named_attribute_value_safe("pntRef")
		if not segment_ref.is_empty():
			if element == "Start":
				state["segment"]["start"] = segment_ref
			elif element == "Center":
				state["segment"]["center"] = segment_ref
			elif element == "End":
				state["segment"]["end"] = segment_ref
		return
	# Everything else is one of the segment's own belongings - its `PI`, its `Feature`, a description -
	# and none of them is geometry.
	if parent != "CoordGeom":
		return
	# A `CoordGeom` is made of lines, curves and irregular lines and nothing else. Anything else -
	# a spiral, which is neither a line nor an arc, or a tag from a newer schema - breaks the line it
	# is in and is named: joining the two sides of something this reader cannot draw would draw
	# straight through it.
	if SEGMENTS.has(element):
		var segment := {
			"kind": element.to_lower(), "rot": parser.get_named_attribute_value_safe("rot"),
			"start": null, "center": null, "end": null, "list": PackedVector2Array(),
		}
		if element == "Curve":
			state["found"]["curves"] = int(state["found"]["curves"]) + 1
		((state["coord"] as Dictionary)["segments"] as Array).append(segment)
		state["segment"] = segment
		return
	_break_line(state, element)


## A piece of coordinate geometry this reader does not draw: the line it is in is broken here, and the
## tag is named so a person can see what the gap is.
##
## Not called `break`: that is a reserved word in GDScript.
static func _break_line(state: Dictionary, element: String) -> void:
	var coord: Dictionary = state["coord"]
	(coord["segments"] as Array).append({"kind": "break"})
	state["found"]["broken"] = int(state["found"]["broken"]) + 1
	_bump(state["found"]["skipped"], "a %s in a line, which broke it there" % element)


## What an element was, as it closes: a coordinate finishes a point, a segment or a whole feature.
static func _close_element(element: String, state: Dictionary) -> void:
	if int(state["skip_depth"]) >= 0:
		return
	if element == "CgPoint":
		state["point_name"] = ""
		return
	if SEGMENTS.has(element):
		state["segment"] = {}
		return
	if element != "CoordGeom":
		if FEATURES.has(element):
			state["feature"] = {}
		return
	var coord: Dictionary = state["coord"]
	state["coord"] = {}
	var owner: Dictionary = coord.get("owner", {})
	var segments: Array = coord.get("segments", [])
	if owner.is_empty():
		_bump(state["found"]["skipped"], "a line that is not inside a parcel, an alignment or a plan feature")
		return
	var made: Array[Dictionary] = _assemble(segments, state["cg_points"], owner, state["found"])
	var shapes: Array = state["found"]["shapes"]
	for shape: Dictionary in made:
		if shapes.size() >= MAX_SHAPES:
			state["found"]["too_many"] = int(state["found"]["too_many"]) + 1
			continue
		shapes.append(shape)
		_bump(state["found"]["counts"], String(shape["feature"]))


## A text node. Which element it sits inside is the whole of what it means.
static func _text(words: String, state: Dictionary) -> void:
	if int(state["skip_depth"]) >= 0:
		return
	var stack: Array = state["stack"]
	if stack.is_empty():
		return
	var trimmed := words.strip_edges()
	if trimmed.is_empty():
		return
	var holder := String(stack[stack.size() - 1])
	if holder == "CgPoint":
		if not String(state["point_name"]).is_empty():
			var point: Variant = point_from_text(trimmed)
			if point != null:
				(state["cg_points"] as Dictionary)[String(state["point_name"])] = point
				state["found"]["cg_points"] = int(state["found"]["cg_points"]) + 1
		return
	var segment: Dictionary = state["segment"]
	if segment.is_empty():
		return
	if holder == "PntList2D" or holder == "PntList3D":
		segment["list"] = points_from_text(trimmed, 2 if holder == "PntList2D" else 3)
		return
	# `Start`, `Center` and `End` also appear directly under an `Alignment`, where they say where an
	# alignment begins rather than anything about a segment: only the ones inside a segment count.
	if stack.size() < 2 or not SEGMENTS.has(String(stack[stack.size() - 2])):
		return
	if holder == "Start":
		segment["start"] = point_from_text(trimmed)
	elif holder == "Center":
		segment["center"] = point_from_text(trimmed)
	elif holder == "End":
		segment["end"] = point_from_text(trimmed)


# --- points and segments --------------------------------------------------------------


## A LandXML point as the model's own pair, still in the file's units and its own frame: the value is
## `"north east"` or `"north east elev"`, so what comes back is `Vector2(northing, easting)`. The
## elevation is dropped, because a plan has no height - and it is dropped *here*, at the one place
## that reads a pair, rather than by a caller that would have to remember to.
static func point_from_text(words: String) -> Variant:
	var numbers := _numbers(words)
	if numbers.size() < 2:
		return null
	return Vector2(numbers[0], numbers[1])


## A whitespace-separated run of coordinate triples or pairs, as one vector per coordinate.
static func points_from_text(words: String, stride: int) -> PackedVector2Array:
	var numbers := _numbers(words)
	var out := PackedVector2Array()
	var at := 0
	while at + 1 < numbers.size():
		out.append(Vector2(numbers[at], numbers[at + 1]))
		at += stride
	return out


## Every number in a string of whitespace-separated values. Tabs and newlines separate as a space
## does, because a coordinate list is written across lines as often as it is on one.
static func _numbers(words: String) -> PackedFloat64Array:
	var out := PackedFloat64Array()
	var spaced := words.replace("\n", " ").replace("\r", " ").replace("\t", " ")
	for piece: String in spaced.split(" ", false):
		var value := piece.strip_edges()
		if value.is_empty():
			continue
		if not value.is_valid_float():
			return PackedFloat64Array()
		out.append(value.to_float())
	return out


## A segment's own points as one shape, or nothing when there is not a line in it.
##
## One `CoordGeom` is one shape however many lines and curves it holds: an alignment is one thing a
## person selects, and its curves are the bulges on it. A `break` ends the shape there and the rest
## begins another, which is how a spiral leaves the line it interrupted.
static func _assemble(
	segments: Array, cg_points: Dictionary, owner: Dictionary, found: Dictionary
) -> Array[Dictionary]:
	var made: Array[Dictionary] = []
	var points := PackedVector2Array()
	var bulges := PackedFloat64Array()
	for segment: Dictionary in segments:
		var kind := String(segment.get("kind", ""))
		if kind == "break":
			# The run of segments so far is one shape; the next one begins another.
			_add(made, points, bulges, owner)
			points = PackedVector2Array()
			bulges = PackedFloat64Array()
			continue
		if kind == "line":
			var a: Variant = _resolve(segment["start"], cg_points, found)
			var b: Variant = _resolve(segment["end"], cg_points, found)
			if a == null or b == null:
				continue
			_along(points, bulges, a)
			_turn_to(points, bulges, b, 0.0)
		elif kind == "curve":
			var start: Variant = _resolve(segment["start"], cg_points, found)
			var centre: Variant = _resolve(segment["center"], cg_points, found)
			var finish: Variant = _resolve(segment["end"], cg_points, found)
			if start == null or centre == null or finish == null:
				# An arc without its centre cannot be reconstructed: two points and no centre are a
				# chord, and the piece of missing geometry is a fact about the file rather than
				# something to guess.
				_bump(found["skipped"], "a curve with no centre, which cannot be drawn")
				continue
			# The bulge is the arc's own statement, in the file's frame: tan of a quarter of the sweep,
			# signed by the way round. `_finish` negates it with the reflection, exactly as the DXF
			# reader negates a DXF bulge, because turning north into -Y reverses handedness.
			_along(points, bulges, start)
			_turn_to(points, bulges, finish, tan(_sweep(start, centre, finish, String(segment["rot"])) / 4.0))
		elif kind == "irregularline":
			for point: Vector2 in (segment["list"] as PackedVector2Array):
				_along(points, bulges, point)
	_add(made, points, bulges, owner)
	return made


## The angle from the start round to the end, in radians, turning the way `rot` says.
##
## The centre is what makes this unambiguous: two points and a centre give two arcs between them, and
## `rot` is the file's own answer to which one it means. A file that states no rotation this
## understands gets the short way round, which is what `wrapf` gives.
static func _sweep(start: Vector2, centre: Vector2, finish: Vector2, rot: String) -> float:
	var from := (start - centre).angle()
	var to := (finish - centre).angle()
	var sweep := wrapf(to - from, -PI, PI)
	var stated := rot.strip_edges().to_lower()
	if stated == "cw" and sweep > 0.0:
		sweep -= TAU
	elif stated == "ccw" and sweep < 0.0:
		sweep += TAU
	return sweep


## A segment's point, which may be a coordinate in the file or the name of a `CgPoint` elsewhere in it.
## The schema's own rule is that a coordinate wins when both are present, which is what the caller
## having already read the text gives us: a reference is only looked up when there is no coordinate.
static func _resolve(value: Variant, cg_points: Dictionary, found: Dictionary) -> Variant:
	if value is Vector2:
		return value
	if not (value is String):
		return null
	var wanted := String(value)
	if cg_points.has(wanted):
		found["refs"] = int(found["refs"]) + 1
		return cg_points[wanted]
	found["bad_refs"] = int(found["bad_refs"]) + 1
	return null


## Add a point to a shape, unless it is the one already there: a repeated corner is one corner, not a
## segment of no length.
static func _along(points: PackedVector2Array, bulges: PackedFloat64Array, point: Vector2) -> void:
	if not points.is_empty() and points[points.size() - 1].distance_squared_to(point) <= SAME_POINT:
		return
	points.append(point)
	# One bulge per point, because that is what the shape table's `bulges` is: the entry belongs to the
	# segment that *leaves* this point, and a point nothing leaves yet carries a straight one.
	bulges.append(0.0)


## Come to `point` from the point already there, turning by `bulge` on the way. The bulge belongs to
## the segment, and a segment belongs to the point it leaves, so it is written onto the point already
## in the shape rather than onto the one being added.
static func _turn_to(
	points: PackedVector2Array, bulges: PackedFloat64Array, point: Vector2, bulge: float
) -> void:
	if points.is_empty():
		_along(points, bulges, point)
		return
	if points[points.size() - 1].distance_squared_to(point) <= SAME_POINT:
		return
	bulges[bulges.size() - 1] = bulge
	points.append(point)
	bulges.append(0.0)


## A finished run of segments as a shape in the table, or nothing when there is not a shape in it.
static func _add(
	made: Array[Dictionary], points: PackedVector2Array, bulges: PackedFloat64Array, owner: Dictionary
) -> void:
	if points.size() < 2:
		# A run of one point is not a line: nothing is dropped in silence, so it is the caller's
		# `skipped` table that has to say so, and the caller is the one that knows why.
		return
	var row: Dictionary = FEATURES[String(owner["tag"])]
	var closed := bool(row["area"])
	if closed and points[points.size() - 1].distance_squared_to(points[0]) <= SAME_POINT:
		# A parcel that writes its first point twice is stating the same ring twice: the repeated point
		# is where it closes, not a corner, and its bulge entry goes with it.
		points.remove_at(points.size() - 1)
		bulges.remove_at(bulges.size() - 1)
	made.append({
		"kind": "LWPOLYLINE", "layer": row["layer"], "feature": String(row["kind"]),
		"name": String(owner.get("name", "")),
		"points": points, "bulges": bulges, "closed": closed,
		"words": "", "height": 0.0, "arc": Vector2.ZERO, "radius": 0.0, "reason": "",
	})


static func _bump(bucket: Dictionary, key: String) -> void:
	bucket[key] = int(bucket.get(key, 0)) + 1


# --- what the geometry becomes --------------------------------------------------------


## Scale, swap, reflect and register every shape, and map the feature each one came from.
##
## One place, once: the pair is written north-first and the model is east +X and north -Y, so this is
## `Vector2(easting, -northing)` - a swap *and* a reflection - and doing it here rather than at each
## of the shapes is what makes it a single test rather than four chances to forget it.
static func _finish(plan: Dictionary) -> void:
	var factor: float = float(plan["unit_factor"])
	var offset: Vector2 = plan["offset"] as Vector2
	var turn := deg_to_rad(float(plan["rotation"]))
	var shapes: Array[Dictionary] = plan["shapes"]
	var layers: Array[String] = plan["layers"]
	for entry: Dictionary in (plan["raw"] as Array):
		var points := PackedVector2Array()
		for point: Vector2 in (entry["points"] as PackedVector2Array):
			var model := Vector2(point.y, -point.x) * factor
			if not is_zero_approx(turn):
				model = model.rotated(turn)
			points.append(model + offset)
		var bulges := PackedFloat64Array()
		for bulge: float in (entry["bulges"] as PackedFloat64Array):
			# The reflection reverses handedness, so a bulge that turned left now turns right.
			bulges.append(-bulge)
		var layer: StringName = (LayerSetScript.UNDERLAY if bool(plan["underlay"])
			else entry["layer"])
		var shape: Dictionary = {
			"kind": String(entry["kind"]), "layer": layer,
			"feature": String(entry["feature"]), "name": String(entry.get("name", "")),
			"points": points, "bulges": bulges, "closed": bool(entry["closed"]),
			"words": "", "height": 0.0, "arc": Vector2.ZERO, "radius": 0.0,
		}
		shapes.append(shape)
		if not layers.has(String(layer)):
			layers.append(String(layer))
	plan.erase("raw")
	# The warnings last, so they read as what was noticed rather than as where the file started.
	var warnings: Array[String] = plan["warnings"]
	if int(plan["bad_refs"]) > 0:
		warnings.append(
			"%d line(s) point at a CgPoint the file does not hold, and were left out"
			% int(plan["bad_refs"])
		)
	if int(plan["too_many"]) > 0:
		warnings.append(
			"! %d more shape(s) than one import draws were left out" % int(plan["too_many"])
		)


static func refused(reason: String) -> Dictionary:
	return {
		"ok": false, "reason": reason, "source": "", "units": "", "unit_factor": 0.0,
		"units_from": "", "declared_unit": "", "underlay": true, "points": false,
		"offset": Vector2.ZERO, "rotation": 0.0,
		"shapes": [] as Array[Dictionary], "counts": {}, "skipped": {},
		"layers": [] as Array[String], "cg_points": 0, "refs": 0, "curves": 0, "broken": 0,
		"too_many": 0, "bad_refs": 0, "bad_points": 0, "warnings": [] as Array[String],
	}


# --- saying what was read -------------------------------------------------------------


## One line saying what the plat holds: how many shapes, and what units they are in.
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


## Everything the reader noticed, one line each: what came in, what did not, and where each kind of
## feature's geometry will land. A person accepts an import by reading this and nothing else.
static func report_lines(plan: Dictionary) -> Array[String]:
	var lines: Array[String] = []
	if not bool(plan.get("ok", false)):
		lines.append(String(plan.get("reason", "the file could not be read")))
		return lines
	lines.append("%s, read as %s (x%s)" % [
		describe(plan), String(plan["units_from"]), String.num(float(plan["unit_factor"]), 6)
	])
	if int(plan["cg_points"]) > 0:
		lines.append("the file's point database holds %d point%s, %d of them used by a line" % [
			int(plan["cg_points"]), "" if int(plan["cg_points"]) == 1 else "s", int(plan["refs"]),
		])
	if int(plan["curves"]) > 0:
		lines.append("%d curve%s read, as the bulge on the line they are part of" % [
			int(plan["curves"]), "" if int(plan["curves"]) == 1 else "s",
		])
	var counts: Dictionary = plan["counts"]
	if counts.is_empty():
		lines.append("there is nothing in it that this draws")
	else:
		var drawn: Array[String] = []
		var kinds: Array = counts.keys()
		kinds.sort()
		for kind: Variant in kinds:
			drawn.append("%s x%d" % [String(kind), int(counts[kind])])
		lines.append("what came in: " + ", ".join(drawn))
	var skipped: Dictionary = plan["skipped"]
	if not skipped.is_empty():
		var left: Array[String] = []
		var reasons: Array = skipped.keys()
		reasons.sort()
		for reason: Variant in reasons:
			left.append("%s x%d" % [String(reason), int(skipped[reason])])
		lines.append("not drawn: " + ", ".join(left))
	# Where each kind's geometry went, which is the thing a person cannot see from the drawing.
	var where := {}
	for shape: Dictionary in (plan["shapes"] as Array):
		where[String(shape["feature"])] = String(shape["layer"])
	var names: Array = where.keys()
	names.sort()
	for feature: Variant in names:
		lines.append("  %s -> %s" % [String(feature), String(where[feature])])
	lines.append("placed at the origin, at scale" if Vector2(plan["offset"]) == Vector2.ZERO
		else "placed %.2f m east and %.2f m north of the origin" % [
			Vector2(plan["offset"]).x, -Vector2(plan["offset"]).y
		])
	if not is_zero_approx(float(plan["rotation"])):
		lines.append("turned %.1f degrees" % float(plan["rotation"]))
	for words: String in (plan["warnings"] as Array):
		lines.append("! " + words)
	return lines