class_name DxfWriter
extends RefCounted

## Writing the drawing out as an ASCII DXF: the inverse of `DxfFile`.
##
## ## Why this is the reader's mirror and not a second dialect
##
## `DxfFile` and this writer speak the **same shape table** - `kind`, `layer`, `points`, `bulges`,
## `closed`, `words`, `height`, `arc`, `radius` - and that is what makes the strongest test available:
## read a file, write it out, read it again, and the shapes come back equal. A writer that invented its
## own model of a DXF could be right about the specification and still disagree with the reader about
## every arc in the drawing, and nothing would notice.
##
## Two of those keys are worth knowing the units of, because the table is the reader's and it keeps the
## file's own conventions rather than converting them: `arc` is a start angle and a sweep **in
## degrees** (group 50 and 51 are degrees, and the reader takes them as they are), and `radius` is in
## model metres. `height` is model metres too, and `points` are placed model metres.
##
## ## The three inversions, each in exactly one place
##
## **Y is up.** A DXF is drawn north-up; the model is east +X and *south* +Y, so the reader reflects
## every point with `Vector2(x, -y)` and this reflects it back in `_to_dxf`.
##
## **A reflection reverses handedness.** Because of that same reflection the reader negates a
## polyline bulge and rewrites an arc's running order, so this negates the bulge again and turns the
## model's `(start, sweep)` back into the file's `(start, end)`. A curved bed stays curved and an arc
## that left going clockwise comes back going clockwise.
##
## **Every length divides by the unit's factor**, the one the reader multiplied by. The model is
## always in metres, so the output unit is a *choice* rather than something to be discovered - it
## defaults to metres and is written into `$INSUNITS`, because a DXF that does not say what its
## numbers mean is a file this program has to stop and ask about when it reads one back.
##
## ## What is not written
##
## **A dimension.** A dimension is an annotation whose text height and arrow size are *paper*
## properties - `DimensionStyle` at a plot scale - so it has no size until somebody says how big the
## sheet is. Its linework could be sampled and written as a polyline, but a reader would then find a
## pile of disconnected strokes where the dimension stood, with the measurement baked into them and
## no way left to re-measure it. So a dimension is **counted and named**, which is the reader's own
## rule for a shape it cannot draw, rather than silently turned into linework.
##
## **Text is written**, and it needs a scale for the same reason: a `TEXT` entity stores a position
## and some words, and its height comes from the drawing's standard rather than from itself. The
## height is not recoverable from the model, so `options["scale"]` states a plot scale to assume and
## the report says which was assumed.
##
## ## What a round trip through this pair cannot keep
##
## A text's turn. A DXF carries it (code 50) and `DxfFile` drops it on import, so the model never
## holds one. The writer still emits it when a caller supplies it, so a file this program wrote opens
## in CAD with its text the right way round; it simply cannot be compared through a round trip,
## because the reader is what loses it.

const DxfFileScript := preload("res://scripts/draft/dxf_file.gd")
const EntityScript := preload("res://scripts/draft/draft_entity.gd")
const LineStyleScript := preload("res://scripts/draft/line_style.gd")

## The plot scale assumed for text height when nobody states one: 1:100, the scale a garden plan is
## usually drawn at, and the one `PlotScale` suggests for a typical yard.
const DEFAULT_SCALE := 100.0

## AutoCAD 2000: the plainest version that carries both `LWPOLYLINE` and a unit-bearing header.
const ACADVER := "AC1015"

## The decimals every number is written to. Six is finer than a metal rule and finer than the reader's
## own `DEFAULT_TOLERANCE` of two millimetres, so nothing is lost to formatting.
const DECIMALS := 6

## The entity kinds this writer turns into a DXF record, and what each becomes.
##
## A model kind that a DXF has no word for (`RECT`, `REGULAR_POLY`) becomes the closed `LWPOLYLINE`
## of its own outline, which is what those shapes *are*: a rectangle is not a DXF object, it is four
## vertices, and writing them out loses nothing because the shape was straight-edged by construction.
const KINDS := {
	EntityScript.Kind.LINE: "LINE",
	EntityScript.Kind.CIRCLE: "CIRCLE",
	EntityScript.Kind.ARC: "ARC",
	EntityScript.Kind.POLYLINE: "LWPOLYLINE",
	EntityScript.Kind.POLYGON: "LWPOLYLINE",
	EntityScript.Kind.RECT: "LWPOLYLINE",
	EntityScript.Kind.REGULAR_POLY: "LWPOLYLINE",
	EntityScript.Kind.TEXT: "TEXT",
}


# --- from a drawing -------------------------------------------------------------------


## The shapes a document holds, in the shape table `DxfFile` reads into and `write_text` writes from.
##
## The two halves are separate on purpose: a caller can look at what would be written - and what would
## not - before anything reaches a file, which is the same reason reading is separate from placing.
##
## `options` may carry:
##
## * `"scale"` - the plot scale text height is worked out at (default `DEFAULT_SCALE`).
## * `"tolerance"` - the chord tolerance an outline is sampled at, in model metres. Only shapes a DXF
##   has no word for use it.
##
## Returns `{ok, reason, shapes, counts, not_written}`. `not_written` is one line per *kind* of thing
## left out, with how many there were - the reader's own rule, so a person never has to wonder whether
## the export was complete.
static func shapes_from_document(document, options: Dictionary = {}) -> Dictionary:
	if document == null:
		return {"ok": false, "reason": "there is no drawing to write", "shapes": [] as Array, "counts": {}, "not_written": [] as Array}
	var scale := float(options.get("scale", DEFAULT_SCALE))
	if scale <= 0.0:
		return {"ok": false, "reason": "a plot scale of nothing is not a scale", "shapes": [] as Array, "counts": {}, "not_written": [] as Array}
	var tolerance := float(options.get("tolerance", EntityScript.DEFAULT_TOLERANCE))
	var height := LineStyleScript.text_model_size(LineStyleScript.DEFAULT_TEXT_HEIGHT, scale)

	var shapes: Array = []
	var counts := {}
	var left_out := {}
	var not_written: Array[String] = []
	# Only what plots. A tracing aid, a sheet border and a viewport frame are things the program draws
	# for the person at the desk; writing them into a file that goes to somebody else would send them
	# geometry that was never part of the design.
	for entity: EntityScript in document.plotting_entities():
		var record := _record_for(entity, height, tolerance)
		if String(record.get("reason", "")).is_empty():
			shapes.append(record["shape"])
			var kind := String(record["shape"]["kind"])
			counts[kind] = int(counts.get(kind, 0)) + 1
		else:
			var what := String(record["what"])
			left_out[what] = int(left_out.get(what, 0)) + 1
	for what: Variant in left_out:
		var count := int(left_out[what])
		not_written.append("%d %s" % [count, String(what)])
	not_written.sort()
	return {"ok": true, "reason": "", "shapes": shapes, "counts": counts, "not_written": not_written}


## One entity as a DXF-shaped record, or the reason it is not written.
##
## The radius of a circle or an arc is recovered as the **distance between the shape's two points**,
## because that is how the reader stores it: a centre, and a second point one radius away. That
## distance is what survives the registration the reader applies to every point, which scaling a
## stored radius by hand would not.
static func _record_for(entity: EntityScript, height: float, tolerance: float) -> Dictionary:
	var kind := entity.kind
	if kind == EntityScript.Kind.DIMENSION:
		return {"reason": "a dimension has no size until a plot scale is given it", "what": "dimension(s) left out"}
	if not KINDS.has(kind):
		return {"reason": "there is no DXF record for this kind", "what": "%s left out" % entity.kind_name()}
	var dxf_kind := String(KINDS[kind])
	var points := PackedVector2Array()
	var bulges := PackedFloat64Array()
	var closed := false
	var words := ""
	var arc := Vector2.ZERO
	var radius := 0.0
	match kind:
		EntityScript.Kind.CIRCLE, EntityScript.Kind.ARC:
			var centre := entity.point(0)
			radius = entity.params[2]
			points.append(centre)
			if kind == EntityScript.Kind.ARC:
				# The model's own frame, in degrees: a start angle and a sweep. `write_text` turns
				# this back into the file's start-and-end run, which is the one place handedness is
				# dealt with.
				arc = Vector2(rad_to_deg(entity.params[3]), rad_to_deg(entity.params[4]))
		EntityScript.Kind.RECT, EntityScript.Kind.REGULAR_POLY:
			# Sampled, because a DXF has no rectangle and no regular polygon: they are their own
			# vertices, and sampling them loses nothing since both are straight-edged.
			points = entity.outline(tolerance)
			closed = true
		EntityScript.Kind.POLYLINE, EntityScript.Kind.POLYGON:
			# Vertices and bulges kept exactly rather than sampled, so a curved bed goes out curved
			# and comes back curved instead of arriving as a hundred short segments.
			points = entity.points()
			bulges = entity.bulges.duplicate()
			closed = entity.is_closed()
		EntityScript.Kind.TEXT:
			points.append(entity.point(0))
			words = String(entity.meta.get("text", ""))
		_:
			points = entity.points()
	return {
		"reason": "",
		"what": "",
		"shape": {
			# The model's own layer name is the DXF layer name: they are already written the way a
			# layer is named on a drawing, and it keeps one name for one thing.
			"kind": dxf_kind,
			"layer": String(entity.layer),
			"points": points,
			"bulges": bulges,
			"closed": closed,
			"words": words,
			"height": height,
			"arc": arc,
			# Stated outright rather than left to be measured off the points: a circle's radius is a
			# fact about the circle, and the reader says it the same way.
			"radius": radius,
			"rotation": entity.params[2] if kind == EntityScript.Kind.TEXT else 0.0,
		},
	}


# --- writing --------------------------------------------------------------------------


## The shapes as DXF text.
##
## `options` may carry:
##
## * `"units"` - the unit name to write in, by any of the names `DxfFile` accepts (default `metres`).
## * `"scale"` - the plot scale the shapes' text height was worked out at, for the report only.
## * `"offset"` - a Vector2 in model metres the reader was told to add, undone here.
## * `"rotation"` - degrees the reader was told to turn by, undone here.
##
## Returns `{ok, reason, text, counts, layers, units, unit_code, unit_factor, scale, scale_assumed}`.
static func write_text(shapes: Array, options: Dictionary = {}) -> Dictionary:
	var unit := _unit_for(String(options.get("units", "metres")))
	if not bool(unit["ok"]):
		return _refused("there is no unit called \"%s\" to write in" % String(options.get("units", "metres")))
	var scale := float(options.get("scale", DEFAULT_SCALE))
	if scale <= 0.0:
		return _refused("a plot scale of nothing is not a scale")
	var factor: float = unit["factor"]
	var offset: Vector2 = options.get("offset", Vector2.ZERO)
	var turn := deg_to_rad(float(options.get("rotation", 0.0)))

	var lines := PackedStringArray()
	_header(lines, int(unit["code"]))
	var counts := {}
	var layers: Array[String] = []
	var bodies := PackedStringArray()
	for shape: Dictionary in shapes:
		var layer := _layer_name(shape)
		if not layers.has(layer):
			layers.append(layer)
		var kind := String(shape["kind"]).to_upper()
		counts[kind] = int(counts.get(kind, 0)) + 1
		_entity(bodies, shape, kind, layer, factor, offset, turn)
	layers.sort()
	_tables(lines, layers)
	lines.append_array([_pair(0, "SECTION"), _pair(2, "ENTITIES")])
	lines.append_array(bodies)
	lines.append_array([_pair(0, "ENDSEC"), _pair(0, "EOF")])
	return {
		"ok": true, "reason": "", "text": "\n".join(lines) + "\n",
		"counts": counts, "layers": layers,
		"units": String(unit["name"]), "unit_code": int(unit["code"]), "unit_factor": factor,
		"scale": scale, "scale_assumed": not options.has("scale"),
	}


## Write shapes to a path. A path that cannot be written is refused with a reason rather than
## raising, because it is a path a person typed.
static func write_file(path: String, shapes: Array, options: Dictionary = {}) -> Dictionary:
	var made := write_text(shapes, options)
	if not bool(made["ok"]):
		return made
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return _refused("that file could not be written: %s" % error_string(FileAccess.get_open_error()))
	file.store_string(String(made["text"]))
	file.close()
	made["path"] = path
	made.erase("text")
	return made


## Write a whole drawing out in one step: its plotting geometry, then the DXF.
static func export_document(document, options: Dictionary = {}) -> Dictionary:
	var made := shapes_from_document(document, options)
	if not bool(made["ok"]):
		return _refused(String(made["reason"]))
	var written := write_text(made["shapes"], options)
	if not bool(written["ok"]):
		return written
	written["not_written"] = made["not_written"]
	written["shape_count"] = (made["shapes"] as Array).size()
	return written


# --- the file's own parts -------------------------------------------------------------


## The header: what version this is, and what its numbers mean.
##
## `$INSUNITS` is the whole point of the header here. A file without it, or with a 0 in it, is one the
## reader refuses until a person says what it is - so writing a file that says is the difference
## between an export and a puzzle.
static func _header(lines: PackedStringArray, unit_code: int) -> void:
	lines.append_array([
		_pair(0, "SECTION"), _pair(2, "HEADER"),
		_pair(9, "$ACADVER"), _pair(1, ACADVER),
		_pair(9, DxfFileScript.INSUNITS_VAR), _pair(70, unit_code),
		_pair(0, "ENDSEC"),
	])


## The layer table: one record per layer the geometry is on, so the file opens in CAD with the layers
## the drawing actually has rather than with everything on layer 0.
static func _tables(lines: PackedStringArray, layers: Array[String]) -> void:
	lines.append_array([
		_pair(0, "SECTION"), _pair(2, "TABLES"),
		_pair(0, "TABLE"), _pair(2, "LAYER"), _pair(70, layers.size()),
	])
	for layer: String in layers:
		lines.append_array([
			_pair(0, "LAYER"), _pair(2, layer),
			_pair(70, 0), _pair(62, 7), _pair(6, "CONTINUOUS"),
		])
	lines.append_array([_pair(0, "ENDTAB"), _pair(0, "ENDSEC")])


## One entity's records.
static func _entity(out: PackedStringArray, shape: Dictionary, kind: String, layer: String, factor: float, offset: Vector2, turn: float) -> void:
	var points: PackedVector2Array = shape["points"]
	out.append_array([_pair(0, kind), _pair(8, layer)])
	match kind:
		"LINE":
			if points.size() < 2:
				return
			var a := _to_dxf(points[0], factor, offset, turn)
			var b := _to_dxf(points[1], factor, offset, turn)
			out.append_array([
				_pair(10, a.x), _pair(20, a.y),
				_pair(11, b.x), _pair(21, b.y),
			])
		"CIRCLE", "ARC":
			if points.is_empty():
				return
			var centre := _to_dxf(points[0], factor, offset, turn)
			# The radius is stated by the shape and only divided by the unit factor. It is a length,
			# so it is the one thing here that does not turn or move with the points and must not be
			# put through the registration.
			var radius := float(shape.get("radius", 0.0)) / factor
			out.append_array([
				_pair(10, centre.x), _pair(20, centre.y), _pair(40, radius),
			])
			if kind == "ARC":
				var run := _arc_run(shape)
				out.append_array([_pair(50, run.x), _pair(51, run.y)])
		"TEXT":
			if points.is_empty():
				return
			var at := _to_dxf(points[0], factor, offset, turn)
			# The reflection mirrors an angle as well as a point, so a text's turn is written negated
			# the way an arc's running order is.
			var words := String(shape["words"])
			out.append_array([
				_pair(10, at.x), _pair(20, at.y),
				_pair(40, float(shape["height"]) / factor),
				_pair(50, _wrap_degrees(-rad_to_deg(float(shape.get("rotation", 0.0))))),
				_pair(1, words),
			])
		"LWPOLYLINE":
			if points.is_empty():
				return
			var bulges: PackedFloat64Array = shape["bulges"]
			out.append_array([
				_pair(90, points.size()), _pair(70, 1 if bool(shape["closed"]) else 0),
			])
			for at in points.size():
				var vertex := _to_dxf(points[at], factor, offset, turn)
				out.append_array([_pair(10, vertex.x), _pair(20, vertex.y)])
				# A `42` on *every* vertex, even a straight one. The reader pairs the bulges it finds
				# to the points by position, so leaving a zero out would shift every bulge after it
				# onto the wrong segment and quietly put a curve in the wrong place.
				var bulge := 0.0
				if at < bulges.size():
					bulge = bulges[at]
				out.append(_pair(42, -bulge))
		_:
			return


# --- the coordinate system ------------------------------------------------------------


## A model point as a DXF point: registration undone, units divided out, and Y reflected back up the
## page. The one place the reader's three coordinate changes are undone.
static func _to_dxf(point: Vector2, factor: float, offset: Vector2, turn: float) -> Vector2:
	var q := (point - offset).rotated(-turn) / factor
	return Vector2(q.x, -q.y)


## An angle folded into `[0, 360)`, which is the range a DXF names an arc's angles in.
static func _wrap_degrees(degrees: float) -> float:
	return fposmod(degrees, 360.0)


## The file-frame start and end angles of a model arc.
##
## A DXF arc always runs **counterclockwise** from its start angle to its end angle, and the reflection
## that makes DXF north into model south reverses handedness - so every arc the reader produces has a
## *non-positive* sweep in the model. An arc a designer drew the other way round therefore cannot be
## written as it stands, and is described from its other end instead: an arc from 30 sweeping +60 is
## the same arc as one from 90 sweeping -60. That identity is why this is a function with a test of its
## own rather than two lines inside `_entity`.
static func _arc_run(shape: Dictionary) -> Vector2:
	var arc: Vector2 = shape["arc"]
	var start := float(arc.x)
	var sweep := float(arc.y)
	if sweep > 0.0:
		start += sweep
		sweep = -sweep
	var from := _wrap_degrees(-start)
	var to := _wrap_degrees(from - sweep)
	return Vector2(from, to)


## The DXF layer name a shape is written on.
##
## A shape that carries the layer name it was *read* from is written back onto that name, so a file
## that was read and written keeps its provenance and re-reads onto the same layers as it did the
## first time. A shape built from a drawing has no such name, so its model layer name is used - and
## those are already written the way a layer is named on a drawing.
static func _layer_name(shape: Dictionary) -> String:
	var from_file := String(shape.get("dxf_layer", ""))
	if not from_file.strip_edges().is_empty():
		return from_file
	var layer := String(shape.get("layer", ""))
	return layer if not layer.strip_edges().is_empty() else "0"


# --- units ----------------------------------------------------------------------------


## The DXF unit code and factor for a unit name, in either the full name or an abbreviation.
##
## The factor comes from `DxfFile.UNIT_NAMES`, which is the table of names a person and a file may
## both use, and the code is then found by that same factor in `DxfFile.UNITS`. Going through the
## factor rather than a second name table means an abbreviation this program accepts can never write
## a unit code that means something else.
static func _unit_for(name: String) -> Dictionary:
	var wanted := name.strip_edges().to_lower()
	if not DxfFileScript.UNIT_NAMES.has(wanted):
		return {"ok": false, "name": "", "code": 0, "factor": 0.0}
	var factor := float(DxfFileScript.UNIT_NAMES[wanted])
	for code: int in DxfFileScript.UNITS:
		var entry: Array = DxfFileScript.UNITS[code]
		if is_equal_approx(float(entry[1]), factor):
			return {"ok": true, "name": String(entry[0]), "code": code, "factor": factor}
	return {"ok": false, "name": "", "code": 0, "factor": 0.0}


## The unit names this can write in, for a menu or a message.
static func unit_names() -> Array[String]:
	var names: Array[String] = []
	for code: int in DxfFileScript.UNITS:
		names.append(String(DxfFileScript.UNITS[code][0]))
	return names


# --- the pairs ------------------------------------------------------------------------


## One group code and its value, each on its own line, which is what a DXF is.
##
## A flag or a count stays an integer. A file that said a closed polyline's flag was `1.000000` would
## still read back correctly, and it would still be wrong: those codes are whole numbers on a drawing,
## and a person opening the file should see the file a CAD program would have written.
static func _pair(code: int, value: Variant) -> String:
	var rendered := ""
	if value is String or value is int:
		# `str` rather than `String(...)`: Godot has no `String` constructor that takes a number.
		rendered = str(value)
	else:
		rendered = String.num(float(value), DECIMALS)
	return "%d\n%s" % [code, rendered]


static func _refused(reason: String) -> Dictionary:
	return {
		"ok": false, "reason": reason, "text": "", "counts": {}, "layers": [] as Array[String],
		"units": "", "unit_code": 0, "unit_factor": 0.0, "scale": 0.0, "scale_assumed": false,
		"not_written": [] as Array[String], "shape_count": 0,
	}


# --- saying what was written ----------------------------------------------------------


## One line saying what went out: how many records, in what units, on how many layers.
static func describe(report: Dictionary) -> String:
	if not bool(report.get("ok", false)):
		return String(report.get("reason", "the drawing could not be written"))
	var counts: Dictionary = report.get("counts", {})
	var total := 0
	for kind: Variant in counts:
		total += int(counts[kind])
	var layers: Array = report.get("layers", [])
	var words := "%d record%s in %s, on %d layer%s" % [
		total, "" if total == 1 else "s", String(report["units"]),
		layers.size(), "" if layers.size() == 1 else "s",
	]
	var left: Array = report.get("not_written", [])
	if not left.is_empty():
		words += "; left out: " + ", ".join(_as_strings(left))
	return words


## Everything a person needs to accept an export, one line each. The mirror of
## `DxfFile.report_lines`, and read the same way.
static func report_lines(report: Dictionary) -> Array[String]:
	var lines: Array[String] = []
	if not bool(report.get("ok", false)):
		lines.append(String(report.get("reason", "the drawing could not be written")))
		return lines
	lines.append(describe(report))
	var counts: Dictionary = report.get("counts", {})
	if counts.is_empty():
		lines.append("there is nothing on it that plots")
	else:
		var written: Array[String] = []
		for kind: Variant in counts:
			written.append("%s x%d" % [String(kind), int(counts[kind])])
		written.sort()
		lines.append("what went in it: " + ", ".join(written))
	var layers: Array = report.get("layers", [])
	if not layers.is_empty():
		lines.append("layers: " + ", ".join(_as_strings(layers)))
	if bool(report.get("scale_assumed", false)):
		lines.append("text height is at a 1:%d plot scale, which was assumed because nobody said"
			% int(round(float(report.get("scale", DEFAULT_SCALE)))))
	return lines


static func _as_strings(values: Array) -> Array[String]:
	var out: Array[String] = []
	for value: Variant in values:
		out.append(String(value))
	return out