class_name OsmFile
extends RefCounted
## Reading an OpenStreetMap extract into the model geometry a designer can trace over.
##
## ## What this is for
##
## A site does not arrive empty. There is a street, a neighbour's house, a fence line, a row of
## maples, a ditch, a sidewalk - existing conditions a designer needs *before* drawing anything, and
## which today either come on a surveyor's DXF or get measured by hand. OpenStreetMap has most of it,
## freely, for anywhere on earth. This reader turns an extract of it into the same table of shapes
## `DxfFile` produces, on the same non-plotting underlay layer, so it is traced over exactly the way a
## surveyor's line work is.
##
## ## What an extract is
##
## The reader reads the JSON an Overpass API query answers with (the same JSON overpass-turbo exports):
## a top level `elements` array of `node`s, `way`s and `relation`s. A `node` carries a `lat` and a
## `lon`; a `way` carries a `geometry` array of `{lat, lon}` when the query asked for `out geom`. A
## `relation` is counted and skipped, for the same reason a DXF block is: following one is a second
## problem, and pretending it was read is worse than saying it was not.
##
## ## The projection, which is the whole of the arithmetic
##
## OSM coordinates are degrees on a sphere; the model is metres on a flat plan. Over the extent of a
## garden - a few hundred metres - the earth is flat enough that one local equirectangular projection
## about a stated centre is exact to well under a centimetre, and it is the *only* arithmetic here.
## One degree of latitude and one of longitude are each a stated length in metres that varies with
## latitude (WGS84), and every point is measured from the centre in those lengths.
##
## The sign convention is the drawing's own and is not invented here: model space is **east +X and
## north -Y** (`docs/drafting-subsystem-spec.md` 1.2.3), the same reflection the survey reader and the
## DXF reader apply. So a building north of the site centre lands at a negative Y, and north is up the
## page exactly as it is on every other drawing in this program.
##
## ## What the tags mean
##
## A way is not labelled with what it is; its *tags* say. `building=*` is a house, `highway=footway` is
## a path and `highway=residential` is a road, `natural=tree` is a tree, `barrier=*` is a wall or a
## fence. `feature_for` is that translation and it is the one table to change to teach this reader a
## new kind of thing. A way's geometry that closes on itself is a ring (an area); everything else is a
## line.
##
## ## Nothing is dropped in silence
##
## Every element in the extract is either drawn or counted under the reason it was not, and `report_lines`
## prints both. An OSM extract is somebody else's data and a person accepts an import by reading what
## came in and what did not.

const LayerSetScript := preload("res://scripts/draft/layer_set.gd")

## One degree of latitude, in metres, at a stated latitude. The standard WGS84 series: the meridian
## degree runs from 110 574 m at the equator to 111 694 m at the pole, and a site knows which of those
## it is near. Written out rather than taken as a mean because a mean is out by a kilometre of total
## error at either end of a country.
static func metres_per_degree_latitude(latitude: float) -> float:
	var phi := deg_to_rad(latitude)
	return (
		111132.92
		- 559.82 * cos(2.0 * phi)
		+ 1.175 * cos(4.0 * phi)
		- 0.0023 * cos(6.0 * phi)
	)


## One degree of longitude, in metres, at a stated latitude - which is the whole reason a projection
## needs a centre: a degree of longitude is 111 320 m at the equator and nothing at all at the pole.
static func metres_per_degree_longitude(latitude: float) -> float:
	var phi := deg_to_rad(latitude)
	return 111412.84 * cos(phi) - 93.5 * cos(3.0 * phi) + 0.118 * cos(5.0 * phi)


## Where a place on the earth lands in the model, in metres from the stated centre - east +X and north
## -Y, as every other reader in this program does it.
static func to_model(latitude: float, longitude: float, centre: Dictionary) -> Vector2:
	var centre_latitude := float(centre.get("latitude", 0.0))
	var centre_longitude := float(centre.get("longitude", 0.0))
	var east := (longitude - centre_longitude) * metres_per_degree_longitude(centre_latitude)
	var north := (latitude - centre_latitude) * metres_per_degree_latitude(centre_latitude)
	return Vector2(east, -north)


## A place in degrees, the way a person writes one: "43.6532°N 79.3832°W".
static func place_words(centre: Dictionary) -> String:
	var latitude := float(centre.get("latitude", 0.0))
	var longitude := float(centre.get("longitude", 0.0))
	return "%.4f°%s %.4f°%s" % [
		absf(latitude), "N" if latitude >= 0.0 else "S",
		absf(longitude), "E" if longitude >= 0.0 else "W",
	]


# --- what the tags mean ---------------------------------------------------------------

## The `highway` values that are a way for people rather than for cars. A path is existing hardscape on
## a garden plan and a road is context, and the two are drawn and read differently, so they are told
## apart at the one place that reads the tags.
const PATH_HIGHWAYS: Array[String] = [
	"footway", "path", "steps", "pedestrian", "cycleway", "bridleway", "track",
]

## The `natural` values that are wooded or rough ground rather than water or a single tree.
const WOOD_NATURAL: Array[String] = ["wood", "scrub", "heath", "grassland"]

## What an element's tags say it is, and where its geometry belongs.
##
## The order of these tests is the table: the first thing an element *is* wins, so a building that also
## has a name is a building. `kind` empty means nothing here draws it and the element is counted as
## such. `area` means the geometry is a ring - a footprint or a region rather than a line.
##
## The layer each kind lands on matters only in the mode where the geometry is *kept* rather than
## traced over: OpenStreetMap's features are existing conditions, so they land on the existing
## conditions band. The default mode ignores this and puts everything on the underlay.
static func feature_for(tags: Dictionary) -> Dictionary:
	if tags.has("building"):
		return {"kind": "building", "area": true, "layer": LayerSetScript.EXISTING_STRUCTURE}
	if tags.has("highway"):
		if PATH_HIGHWAYS.has(String(tags.get("highway", ""))):
			return {"kind": "path", "area": false, "layer": LayerSetScript.EXISTING_HARDSCAPE}
		return {"kind": "road", "area": false, "layer": LayerSetScript.EXISTING_HARDSCAPE}
	if tags.has("railway"):
		return {"kind": "railway", "area": false, "layer": LayerSetScript.EXISTING_HARDSCAPE}
	if tags.has("waterway") or String(tags.get("natural", "")) == "water":
		# A river is a line; a pond is a ring. The tag says which.
		return {
			"kind": "water", "area": String(tags.get("natural", "")) == "water",
			"layer": LayerSetScript.EXISTING_HARDSCAPE,
		}
	if String(tags.get("natural", "")) == "tree":
		return {"kind": "tree", "area": false, "layer": LayerSetScript.EXISTING_PLANTING}
	if WOOD_NATURAL.has(String(tags.get("natural", ""))) or String(tags.get("landuse", "")) == "forest":
		return {"kind": "wood", "area": true, "layer": LayerSetScript.EXISTING_PLANTING}
	if tags.has("barrier") or tags.has("wall"):
		return {"kind": "wall", "area": false, "layer": LayerSetScript.EXISTING_HARDSCAPE}
	if tags.has("leisure"):
		return {"kind": "leisure", "area": true, "layer": LayerSetScript.EXISTING_HARDSCAPE}
	if tags.has("landuse"):
		return {"kind": "landuse", "area": true, "layer": LayerSetScript.EXISTING_HARDSCAPE}
	if tags.has("amenity"):
		return {"kind": "amenity", "area": true, "layer": LayerSetScript.EXISTING_HARDSCAPE}
	return {"kind": "", "area": false, "layer": LayerSetScript.UNDERLAY}


# --- reading --------------------------------------------------------------------------

## How far from the site centre a feature may reach and still be site *context*. A park boundary or a
## municipal boundary comes in whole however small the extract, because Overpass answers with a whole
## way if any part of it is in range, and a 5 km ring drawn round a 100 m garden is not context - it is
## a surprise. Anything reaching past this many radii is counted and left out rather than drawn.
const OUTLYING_FACTOR := 2.0

## How many shapes one import will draw. An extract of a city block is a few hundred; one of a
## downtown is tens of thousands, and a drawing that takes a minute to open is not a drawing.
const MAX_SHAPES := 4000

## Two ring points closer than this are the same point; an area's geometry repeats its first point at
## the end and that repeat is not a vertex.
const RING_EPS := 1.0e-9

## A tree in OpenStreetMap is a point: nobody records the canopy. So a tree node is drawn as a ring of
## this radius, which is a *drawing convention* and not data - it is the size a person would draw a
## young tree at, and it is stated here so it can be argued with. (The alternative, a bare point, is
## invisible at sheet scale and unselectable on the plan.)
const TREE_RING_M := 1.5


## Read an Overpass JSON response. `options` may carry:
##
## * `"centre"` - a dictionary of `latitude` and `longitude`: where the model's origin is. **Required.**
##   The projection has no meaning without it, so a response without a centre is refused rather than
##   placed at a guessed latitude - which is what a default would be.
## * `"radius"` - the radius the extract was asked for, in metres. Used to leave out an outlying
##   feature (see `OUTLYING_FACTOR`). Zero means "take the file as it comes".
## * `"underlay"` - true (the default) puts every feature on the non-plotting underlay layer, which is
##   what map context is usually wanted for: something to trace over. False keeps the geometry on the
##   existing conditions layers `feature_for` names.
## * `"labels"` - true (the default) writes a named element's name on the drawing as a text entity.
## * `"offset"` - a Vector2 in model metres added to every point, for registration.
## * `"rotation"` - degrees applied about the origin before the offset.
##
## Returns a table of shapes and a table of things to say about them, like `SurveyFile` and `DxfFile`,
## rather than an object: a class would only be a second set of names for the same two tables.
static func read_text(source: String, options: Dictionary = {}) -> Dictionary:
	if source.strip_edges().is_empty():
		return refused("the map is empty")
	# `JSON.parse_string` is the convenience form and it prints to the console on damage, which would
	# make "this file is not JSON" - an ordinary answer - look like a fault. The parser itself returns
	# the error instead, and the error is the refusal.
	var parser := JSON.new()
	if parser.parse(source) != OK:
		return refused("that is not an OpenStreetMap response: it is not JSON")
	var parsed: Variant = parser.data
	if not (parsed is Dictionary):
		return refused("that is not an OpenStreetMap response: it is not JSON")
	var document: Dictionary = parsed
	var elements: Variant = document.get("elements", null)
	if not (elements is Array):
		return refused("that JSON is not an OpenStreetMap response: it has no elements array")
	var centre: Variant = options.get("centre", null)
	if not (centre is Dictionary) or (centre as Dictionary).is_empty():
		return refused("the map has to be told where the drawing's origin is, in degrees")
	var plan := {
		"ok": true, "reason": "", "source": "",
		"generator": String(document.get("generator", "")),
		"centre": centre,
		"radius": float(options.get("radius", 0.0)),
		"underlay": bool(options.get("underlay", true)),
		"labels": bool(options.get("labels", true)),
		"offset": options.get("offset", Vector2.ZERO),
		"rotation": float(options.get("rotation", 0.0)),
		"elements": (elements as Array).size(),
		"counts": {},
		"skipped": {},
		"outlying": 0,
		"too_many": 0,
		"layers": [] as Array[String],
		"warnings": [] as Array[String],
		"shapes": [] as Array[Dictionary],
	}
	_finish(plan, elements, centre)
	return plan


## Read an extract from disk. A missing or unreadable file is refused with a reason rather than
## raising, because it is a path a person chose.
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


## Walk the elements once, drawing what can be drawn and counting the rest under the reason why.
static func _finish(plan: Dictionary, elements: Array, centre: Dictionary) -> void:
	var counts: Dictionary = plan["counts"]
	var skipped: Dictionary = plan["skipped"]
	var shapes: Array[Dictionary] = plan["shapes"]
	var layers: Array[String] = plan["layers"]
	var radius := float(plan["radius"])
	for entry: Variant in elements:
		if not (entry is Dictionary):
			_bump(skipped, "an element that is not an object")
			continue
		var element: Dictionary = entry
		var member_type := String(element.get("type", ""))
		if member_type == "relation":
			_bump(skipped, "a relation, which this does not follow")
			continue
		if member_type != "node" and member_type != "way":
			_bump(skipped, "a %s, which is not a node or a way" % (member_type if not member_type.is_empty() else "record with no type"))
			continue
		var tags: Dictionary = (element.get("tags", {}) as Dictionary) if element.get("tags") is Dictionary else {}
		if tags.is_empty():
			_bump(skipped, "an element with no tags, so nothing says what it is")
			continue
		var feature := feature_for(tags)
		if String(feature["kind"]).is_empty():
			_bump(skipped, "tags nothing here draws")
			continue
		var shape := _shape_for(element, member_type, feature, tags, centre, plan)
		if String(shape.get("reason", "")).is_empty() and not (shape["points"] as PackedVector2Array).is_empty():
			# The one geometry check that needs the extract's own size: a feature reaching far past
			# the area that was asked for is somebody else's property, not site context.
			if radius > 0.0 and _reach(shape["points"]) > radius * OUTLYING_FACTOR:
				plan["outlying"] = int(plan["outlying"]) + 1
				continue
			if shapes.size() >= MAX_SHAPES:
				plan["too_many"] = int(plan["too_many"]) + 1
				continue
			shapes.append(shape)
			_bump(counts, String(feature["kind"]))
			if not layers.has(String(shape["layer"])):
				layers.append(String(shape["layer"]))
		else:
			var reason := String(shape.get("reason", ""))
			_bump(skipped, reason if not reason.is_empty() else "a feature with nothing to draw")


## One element as a shape in the model, or a `reason` saying why it is not one.
##
## The shape's keys are `DxfFile`'s own - `kind`, `layer`, `points`, `bulges`, `closed`, `words`,
## `height`, `arc` - so the controller's one entity builder draws either, and there is one place where
## a shape becomes a drawing entity rather than two that can drift apart.
static func _shape_for(
	element: Dictionary, member_type: String, feature: Dictionary, tags: Dictionary,
	centre: Dictionary, plan: Dictionary
) -> Dictionary:
	var underlay := bool(plan["underlay"])
	var layer: StringName = LayerSetScript.UNDERLAY if underlay else feature["layer"]
	var kind := String(feature["kind"])
	var name := String(tags.get("name", ""))
	if member_type == "node":
		var latitude: Variant = element.get("lat", null)
		var longitude: Variant = element.get("lon", null)
		if latitude == null or longitude == null:
			return _no_points("a node with no position")
		var at := to_model(float(latitude), float(longitude), centre)
		if kind == "tree":
			# A tree is a point in the data and has to become something on a plan.
			return _shape("CIRCLE", layer, PackedVector2Array([at, Vector2(TREE_RING_M, 0.0)]), false, "", kind)
		if bool(plan["labels"]) and not name.is_empty():
			return _shape("TEXT", layer, PackedVector2Array([at]), false, name, kind)
		return _no_points("a point with nothing to draw at it")
	var geometry: Variant = element.get("geometry", null)
	if not (geometry is Array) or (geometry as Array).is_empty():
		return _no_points("a way with no geometry: the response was not asked for `out geom`")
	var points := PackedVector2Array()
	for point: Variant in (geometry as Array):
		if not (point is Dictionary):
			return _no_points("a way with a point that is not an object")
		var node: Dictionary = point
		var node_latitude: Variant = node.get("lat", null)
		var node_longitude: Variant = node.get("lon", null)
		if node_latitude == null or node_longitude == null:
			return _no_points("a way with a point that is not on the earth")
		points.append(to_model(float(node_latitude), float(node_longitude), centre))
	if points.size() < 2:
		return _no_points("a way with fewer than two points")
	# A shape is a ring when its geometry closes on itself, or when its tags say it is an area. An
	# area's geometry repeats its first point at the end; that repeat is where it closes, not a vertex.
	var ring := bool(feature["area"])
	var last := points.size() - 1
	if points[0].distance_squared_to(points[last]) <= RING_EPS:
		points.remove_at(last)
		ring = true
	if ring and points.size() < 3:
		return _no_points("an area with fewer than three corners")
	return _shape("LWPOLYLINE", layer, points, ring, "", kind)


static func _shape(
	kind: String, layer: StringName, points: PackedVector2Array, closed: bool, words: String, feature: String
) -> Dictionary:
	# No `reason` on a shape that was drawn: a reason belongs to the refusal path (`_no_points`), and a
	# key that is always empty on everything a reader produced is a key a caller has to wonder about.
	return {
		"kind": kind, "layer": layer, "feature": feature,
		"points": points, "bulges": PackedFloat64Array(), "closed": closed,
		"words": words, "height": 0.0, "arc": Vector2.ZERO, "radius": 0.0,
	}


static func _no_points(reason: String) -> Dictionary:
	return {
		"kind": "", "layer": LayerSetScript.UNDERLAY, "feature": "",
		"points": PackedVector2Array(), "bulges": PackedFloat64Array(), "closed": false,
		"words": "", "height": 0.0, "arc": Vector2.ZERO, "radius": 0.0,
		"reason": reason,
	}


## How far the furthest point of a shape is from the model origin.
static func _reach(points: PackedVector2Array) -> float:
	var furthest := 0.0
	for point: Vector2 in points:
		furthest = maxf(furthest, point.length())
	return furthest


static func _bump(bucket: Dictionary, key: String) -> void:
	bucket[key] = int(bucket.get(key, 0)) + 1


static func refused(reason: String) -> Dictionary:
	return {
		"ok": false, "reason": reason, "source": "", "generator": "",
		"centre": {}, "radius": 0.0, "underlay": true, "labels": true,
		"offset": Vector2.ZERO, "rotation": 0.0, "elements": 0,
		"counts": {}, "skipped": {}, "outlying": 0, "too_many": 0,
		"layers": [] as Array[String], "warnings": [] as Array[String],
		"shapes": [] as Array[Dictionary],
	}


# --- saying what was read -------------------------------------------------------------

## One line saying what the map holds.
static func describe(plan: Dictionary) -> String:
	if not bool(plan.get("ok", false)):
		return String(plan.get("reason", "the map could not be read"))
	var drawn := (plan.get("shapes", []) as Array).size()
	return "%d feature%s from OpenStreetMap around %s" % [
		drawn, "" if drawn == 1 else "s", place_words(plan["centre"]),
	]


## Whether there is anything to put on the drawing.
static func is_usable(plan: Dictionary) -> bool:
	return bool(plan.get("ok", false)) and not (plan.get("shapes", []) as Array).is_empty()


## Everything the reader noticed, one line each: what came in, what did not, and where each kind of
## feature's geometry will land. A person accepts an import by reading this and nothing else.
static func report_lines(plan: Dictionary) -> Array[String]:
	var lines: Array[String] = []
	if not bool(plan.get("ok", false)):
		lines.append(String(plan.get("reason", "the map could not be read")))
		return lines
	lines.append("%s (%d element%s read)" % [
		describe(plan), int(plan["elements"]), "" if int(plan["elements"]) == 1 else "s",
	])
	lines.append(
		"placed at the origin: the site is the centre of the map"
		if Vector2(plan["offset"]) == Vector2.ZERO
		else "placed %.2f m east and %.2f m north of the origin" % [
			Vector2(plan["offset"]).x, -Vector2(plan["offset"]).y
		]
	)
	if not is_zero_approx(float(plan["rotation"])):
		lines.append("turned %.1f degrees" % float(plan["rotation"]))
	var counts: Dictionary = plan["counts"]
	if counts.is_empty():
		lines.append("nothing in it is something this draws")
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
	if int(plan["outlying"]) > 0:
		lines.append(
			"! %d feature(s) reach past the area that was asked for and were left out"
			% int(plan["outlying"])
		)
	if int(plan["too_many"]) > 0:
		lines.append(
			"! %d more feature(s) than one import draws were left out" % int(plan["too_many"])
		)
	for words: String in (plan["warnings"] as Array):
		lines.append("! " + words)
	return lines