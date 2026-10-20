extends Node
## Tests for reading an ASCII DXF: the pairs, the six shapes, the units, the reflection, and where
## each DXF layer's geometry lands.
##
## Two of these are the specification's own acceptance criteria: AC-14 (DXF Y up becomes model Z
## south, proved by a mirrored fixture, because a mirrored site is visually plausible and wrong) and
## AC-15 (`$INSUNITS = 2` produces metres at the right factor).
##
## The fixtures are built as strings by the helpers below rather than kept as files: a DXF's whole
## shape is "a code, then its value", and a test that writes one out in that form is readable in a way
## a checked-in 200-line file is not.

const DxfScript := preload("res://scripts/draft/dxf_file.gd")
const LayerSetScript := preload("res://scripts/draft/layer_set.gd")
const UnitsScript := preload("res://scripts/draft/units.gd")


## A whole DXF around a run of entity records, with the header the units come from.
func _dxf(entities: String, insunits: int = 6, header: String = "") -> String:
	var lines: Array[String] = [
		"0", "SECTION", "2", "HEADER",
		"9", "$INSUNITS", "70", str(insunits),
	]
	if not header.is_empty():
		lines.append_array([header, "", "", ""])
	lines.append_array([
		"0", "ENDSEC",
		"0", "SECTION", "2", "ENTITIES",
	])
	if not entities.is_empty():
		lines.append(entities)
	lines.append_array(["0", "ENDSEC", "0", "EOF", ""])
	return "\n".join(PackedStringArray(lines))


func _line(a: Vector2, b: Vector2, layer: String = "PROPERTY") -> String:
	return "\n".join(PackedStringArray([
		"0", "LINE", "8", layer,
		"10", str(a.x), "20", str(a.y),
		"11", str(b.x), "21", str(b.y),
	]))


func _lwpoly(points: Array, closed: bool = false, layer: String = "BOUNDARY", bulges: Array = []) -> String:
	var lines: Array[String] = ["0", "LWPOLYLINE", "8", layer, "90", str(points.size()), "70", "1" if closed else "0"]
	for index in points.size():
		var point: Vector2 = points[index]
		lines.append_array(["10", str(point.x), "20", str(point.y)])
		if index < bulges.size():
			lines.append_array(["42", str(float(bulges[index]))])
	return "\n".join(PackedStringArray(lines))


func _poly(vertices: Array, closed: bool = false, layer: String = "BOUNDARY") -> String:
	var lines: Array[String] = ["0", "POLYLINE", "8", layer, "70", "1" if closed else "0"]
	for vertex: Vector2 in vertices:
		lines.append_array(["0", "VERTEX", "10", str(vertex.x), "20", str(vertex.y)])
	lines.append_array(["0", "SEQEND", "8", layer])
	return "\n".join(PackedStringArray(lines))


func _circle(centre: Vector2, radius: float, layer: String = "HARD") -> String:
	return "\n".join(PackedStringArray([
		"0", "CIRCLE", "8", layer,
		"10", str(centre.x), "20", str(centre.y), "40", str(radius),
	]))


func _arc(centre: Vector2, radius: float, start: float, finish: float, layer: String = "HARD") -> String:
	return "\n".join(PackedStringArray([
		"0", "ARC", "8", layer,
		"10", str(centre.x), "20", str(centre.y), "40", str(radius),
		"50", str(start), "51", str(finish),
	]))


func _text(at: Vector2, words: String, height: float, layer: String = "ANNO") -> String:
	return "\n".join(PackedStringArray([
		"0", "TEXT", "8", layer,
		"10", str(at.x), "20", str(at.y), "40", str(height), "1", words,
	]))


func _shapes(plan: Dictionary) -> Array[Dictionary]:
	return plan["shapes"] as Array[Dictionary]


func _report(plan: Dictionary) -> String:
	return "\n".join(PackedStringArray(DxfScript.report_lines(plan)))


# --- the pairs, and refusing what is not a DXF ----------------------------------------


func test_a_file_that_is_not_a_dxf_is_refused_in_words() -> void:
	for source: String in ["", "   \n  ", "hello\nworld", "1\n2\n3\n4"]:
		var plan := DxfScript.read_text(source)
		assert(not bool(plan["ok"]), "should be refused: %s" % source)
		assert(not String(plan["reason"]).is_empty(), "and said why")
		assert(_shapes(plan).is_empty())
		assert(DxfScript.describe(plan) == String(plan["reason"]), "describe repeats the reason")
	assert(DxfScript.read_text("hello\nworld")["reason"].contains("DXF"), "names what it wanted")


func test_a_missing_file_is_refused_rather_than_raising() -> void:
	var plan := DxfScript.of_file("user://no-such-file-is-here.dxf")
	assert(not bool(plan["ok"]))
	assert(String(plan["reason"]).contains("no-such-file-is-here.dxf"), String(plan["reason"]))
	assert(not DxfScript.of_file("")["ok"])


# --- AC-14: Y is up ----------------------------------------------------------------


## The criterion, on purpose: a mirrored site is visually plausible and wrong.
func test_a_dxf_is_mirrored_into_the_model(insunits := 6) -> void:
	var plan := DxfScript.read_text(_dxf(_line(Vector2(0.0, 0.0), Vector2(10.0, 5.0))))
	assert(bool(plan["ok"]), String(plan["reason"]))
	var shape: Dictionary = _shapes(plan)[0]
	var points: PackedVector2Array = shape["points"]
	assert(points[0] == Vector2(0.0, 0.0))
	# DXF Y is north and the model's Y is south, so 5 north becomes 5 south: -5, not +5.
	assert(points[1] == Vector2(10.0, -5.0), "DXF north is model -Y: %s" % str(points[1]))
	assert(points[1].y < 0.0, "and the sign is the whole point of the test")


func test_an_arc_and_a_bulge_turn_the_other_way_after_the_mirror() -> void:
	var plan := DxfScript.read_text(
		_dxf(_arc(Vector2(0.0, 0.0), 10.0, 0.0, 90.0) + "\n" + _lwpoly(
			[Vector2(0.0, 0.0), Vector2(10.0, 0.0)], false, "BOUNDARY", [1.0]
		))
	)
	assert(bool(plan["ok"]), String(plan["reason"]))
	var arc: Dictionary = _shapes(plan)[0]
	var angles: PackedVector2Array = arc["points"]
	# A DXF arc runs counterclockwise from 50 to 51. Reflecting y reverses handedness, so the model
	# arc starts at -0 degrees and sweeps -90: the same quarter of the circle, the other way round.
	assert(angles[0] == Vector2.ZERO, "the centre")
	assert(angles[1] == Vector2(10.0, 0.0), "the radius on x")
	assert(angles.size() == 2, "an arc is a centre and a radius; its angles are angles")
	var arc_angles: Vector2 = arc["arc"]
	assert(arc_angles.x == 0.0, str(arc_angles))
	assert(arc_angles.y == -90.0, "start and sweep: %s" % str(arc_angles))
	var poly: Dictionary = _shapes(plan)[1]
	# A left-turning bulge turns right once the drawing is reflected.
	assert((poly["bulges"] as PackedFloat64Array)[0] == -1.0, str(poly["bulges"]))


func test_an_arc_that_crosses_north_maps_its_sweep_the_same_way() -> void:
	var plan := DxfScript.read_text(_dxf(_arc(Vector2(0.0, 0.0), 4.0, 350.0, 10.0)))
	var arc_angles: Vector2 = _shapes(plan)[0]["arc"]
	# 350 to 10 is 20 degrees counterclockwise across north, so the model runs from -350 - which is
	# +10 - back 20 degrees. Read as a bare pair of numbers this is where a mirrored arc goes wrong.
	assert(arc_angles.x == -350.0, str(arc_angles))
	assert(arc_angles.y == -20.0, str(arc_angles))
	assert(is_equal_approx(fposmod(arc_angles.x, 360.0), 10.0), "which is the same place as +10")


# --- AC-15: the units ---------------------------------------------------------------


func test_a_dxf_in_feet_comes_into_the_model_in_metres() -> void:
	var plan := DxfScript.read_text(_dxf(_line(Vector2(0.0, 0.0), Vector2(10.0, 0.0)), 2))
	assert(bool(plan["ok"]), String(plan["reason"]))
	assert(String(plan["units"]) == "feet", String(plan["units"]))
	assert(is_equal_approx(float(plan["unit_factor"]), UnitsScript.FOOT))
	var points: PackedVector2Array = _shapes(plan)[0]["points"]
	assert(is_equal_approx(points[1].x, 10.0 * UnitsScript.FOOT), str(points[1].x))
	assert(is_equal_approx(points[1].x, 3.048), "ten feet is 3.048 m exactly")


func test_every_unit_a_dxf_can_state_is_a_unit_this_reads() -> void:
	for code: int in DxfScript.UNITS:
		var plan := DxfScript.read_text(_dxf(_line(Vector2.ZERO, Vector2(1.0, 0.0)), code))
		assert(bool(plan["ok"]), "code %d: %s" % [code, plan["reason"]])
		assert(is_equal_approx(float(plan["unit_factor"]), float(DxfScript.UNITS[code][1])),
			"code %d wants %f" % [code, float(DxfScript.UNITS[code][1])])
	# The two feet are different lengths, and the US survey foot is the exact one (1200/3937 m).
	assert(DxfScript.UNITS[21][1] == UnitsScript.US_SURVEY_FOOT)
	# They differ by 2.0 ppm - which `is_equal_approx` calls *equal*, and that is exactly the point:
	# the table holds the exact constants and the reader multiplies by them, because a difference
	# this small is immaterial for a planting layout and material for a legal boundary.
	assert(DxfScript.UNITS[2][1] != DxfScript.UNITS[21][1])
	assert(is_equal_approx(float(DxfScript.UNITS[2][1]), float(DxfScript.UNITS[21][1])),
		"so near each other that only an exact comparison tells them apart")


func test_a_file_that_does_not_say_its_units_has_to_be_asked_about() -> void:
	# 0 is "unitless", which is the same as not saying. Guessing metres would put a plan drawn in feet
	# into the model at a third of its size, and the drawing would look plausible.
	var plan := DxfScript.read_text(_dxf(_line(Vector2.ZERO, Vector2(10.0, 0.0)), 0))
	assert(not bool(plan["ok"]))
	assert(String(plan["reason"]).contains("does not say"), String(plan["reason"]))
	# And when somebody is asked and answers, the file reads, and the report says where it came from.
	var answered := DxfScript.read_text(_dxf(_line(Vector2.ZERO, Vector2(10.0, 0.0)), 0), {"units": "feet"})
	assert(bool(answered["ok"]), String(answered["reason"]))
	assert(String(answered["units"]) == "feet")
	assert(String(answered["units_from"]) == "what was asked for")
	assert(_report(answered).contains("because the file does not say"), _report(answered))
	# An answer nobody knows is not an answer.
	var wrong := DxfScript.read_text(_dxf(_line(Vector2.ZERO, Vector2(1.0, 0.0)), 0), {"units": "furlongs"})
	assert(not bool(wrong["ok"]))
	assert(String(wrong["reason"]).contains("asked about"), String(wrong["reason"]))
	# A code the reader does not know is refused rather than assumed.
	var unknown := DxfScript.read_text(_dxf(_line(Vector2.ZERO, Vector2(1.0, 0.0)), 99))
	assert(not bool(unknown["ok"]))
	assert(String(unknown["reason"]).contains("code 99"), String(unknown["reason"]))


# --- the six shapes -----------------------------------------------------------------


func test_a_circle_and_a_text_come_in_with_their_size_and_words() -> void:
	var plan := DxfScript.read_text(
		_dxf(_circle(Vector2(3.0, 4.0), 2.5) + "\n" + _text(Vector2(1.0, 1.0), "P.L. 49.25", 0.4))
	)
	assert(bool(plan["ok"]), String(plan["reason"]))
	var circle: Dictionary = _shapes(plan)[0]
	assert(String(circle["kind"]) == "CIRCLE")
	var points: PackedVector2Array = circle["points"]
	assert(points[0] == Vector2(3.0, -4.0), "the centre, mirrored: %s" % str(points[0]))
	assert(points[1].x == 2.5, "and the radius")
	var label: Dictionary = _shapes(plan)[1]
	assert(String(label["kind"]) == "TEXT")
	assert(String(label["words"]) == "P.L. 49.25")
	# A `Vector2` holds 32-bit components, so a height that is exact in the file comes back
	# approximately: 0.4 is not representable in binary.
	assert(is_equal_approx((label["points"] as PackedVector2Array)[0].x, 1.0))
	assert(is_equal_approx(float(label["height"]), 0.4), str(label["height"]))
	assert(int(label["points"].size()) == 1, "a text is its insertion point: its height is a height")


func test_a_closed_light_polyline_keeps_its_points_its_flag_and_its_bulge() -> void:
	var plan := DxfScript.read_text(_dxf(_lwpoly(
		[Vector2(0.0, 0.0), Vector2(10.0, 0.0), Vector2(10.0, 6.0)],
		true, "BOUNDARY", [0.0, 0.5]
	)))
	var shape: Dictionary = _shapes(plan)[0]
	assert(String(shape["kind"]) == "LWPOLYLINE")
	assert(bool(shape["closed"]), "the 70 flag's low bit is the closed one")
	var points: PackedVector2Array = shape["points"]
	assert(points.size() == 3)
	assert(points[2] == Vector2(10.0, -6.0))
	assert((shape["bulges"] as PackedFloat64Array)[1] == -0.5, str(shape["bulges"]))
	assert((shape["bulges"] as PackedFloat64Array)[0] == 0.0, "a vertex with no bulge is a straight segment")


func test_a_heavy_polyline_reads_its_vertex_records_and_does_not_count_them_as_shapes() -> void:
	var plan := DxfScript.read_text(_dxf(_poly([Vector2(0.0, 0.0), Vector2(5.0, 0.0), Vector2(5.0, 5.0)], true)))
	assert(bool(plan["ok"]), String(plan["reason"]))
	assert(_shapes(plan).size() == 1, "one polyline, not one shape per vertex: %d" % _shapes(plan).size())
	var shape: Dictionary = _shapes(plan)[0]
	assert((shape["points"] as PackedVector2Array).size() == 3)
	assert(bool(shape["closed"]))
	var counts: Dictionary = plan["counts"]
	assert(int(counts.get("VERTEX", 0)) == 0, "a vertex is part of its polyline, not an entity of its own")
	assert(int(counts.get("SEQEND", 0)) == 0)
	assert(int(counts.get("POLYLINE", 0)) == 1)


# --- what is not read is still said --------------------------------------------------


func test_what_cannot_be_drawn_is_counted_and_named() -> void:
	var plan := DxfScript.read_text(_dxf(
		_line(Vector2.ZERO, Vector2(1.0, 0.0)) + "\n" + _circle(Vector2.ZERO, 1.0) + "\n"
		+ "\n".join(PackedStringArray(["0", "SPLINE", "8", "CONTOUR", "10", "1.0", "20", "2.0"])) + "\n"
		+ "\n".join(PackedStringArray(["0", "INSERT", "8", "TREE", "2", "A_TREE_BLOCK", "10", "3.0", "20", "4.0"]))
	))
	assert(bool(plan["ok"]), String(plan["reason"]))
	assert(_shapes(plan).size() == 2, "only the two it can draw")
	var counts: Dictionary = plan["counts"]
	assert(int(counts["SPLINE"]) == 1, "but every record is counted")
	assert(int(counts["INSERT"]) == 1)
	var unsupported: Array = plan["unsupported"]
	assert(unsupported.has("SPLINE") and unsupported.has("INSERT"), str(unsupported))
	# And the report says so in words, because "it all came in" is not something a person can check.
	var report := _report(plan)
	assert(report.contains("not read: "), report)
	assert(report.contains("SPLINE"), report)


func test_a_block_is_counted_rather_than_followed() -> void:
	var block := "\n".join(PackedStringArray([
		"0", "SECTION", "2", "BLOCKS",
		"0", "BLOCK", "8", "0", "2", "A_TREE_BLOCK",
		"0", "LINE", "8", "0", "10", "0.0", "20", "0.0", "11", "1.0", "21", "1.0",
		"0", "ENDBLK",
		"0", "ENDSEC",
	]))
	var source := _dxf(_line(Vector2.ZERO, Vector2(1.0, 0.0)))
	# The BLOCKS section goes before ENTITIES, as it does in a real file.
	source = source.replace("0\nSECTION\n2\nENTITIES", block + "\n0\nSECTION\n2\nENTITIES")
	var plan := DxfScript.read_text(source)
	assert(bool(plan["ok"]), String(plan["reason"]))
	assert(int(plan["blocks"]) == 1, "the block is counted: %d" % int(plan["blocks"]))
	assert(_shapes(plan).size() == 1, "and the line inside it did not also become a shape")
	assert(_report(plan).contains("block"), _report(plan))


func test_a_shape_with_a_damaged_number_is_left_out_and_counted() -> void:
	var broken := "\n".join(PackedStringArray([
		"0", "LINE", "8", "PROPERTY",
		"10", "not a number", "20", "0.0",
		"11", "10.0", "21", "0.0",
	]))
	var plan := DxfScript.read_text(_dxf(broken + "\n" + _line(Vector2.ZERO, Vector2(1.0, 0.0))))
	assert(bool(plan["ok"]), "one bad shape does not lose the file")
	assert(_shapes(plan).size() == 1, "and it does not become a point at the origin")
	assert(int(plan["bad_numbers"]) == 1)
	assert(_report(plan).contains("could not be read"), _report(plan))


# --- REQ 6.7.4: where each layer lands ------------------------------------------------


func test_an_underlay_carries_every_layer_to_the_layer_that_does_not_plot() -> void:
	var plan := DxfScript.read_text(_dxf(
		_line(Vector2.ZERO, Vector2(1.0, 0.0), "PROPERTY") + "\n"
		+ _circle(Vector2.ZERO, 1.0, "RANDOM-LAYER-37")
	))
	assert(bool(plan["underlay"]), "the underlay is what a surveyor's file is usually wanted for")
	for shape: Dictionary in _shapes(plan):
		assert(shape["layer"] == LayerSetScript.UNDERLAY, String(shape["layer"]))
	# The layer it does not plot on is the point: an underlay is something to trace over, and a
	# tracing aid on the sheet would be a surveyor's line work in the client's drawing.
	var plotting: Array[StringName] = LayerSetScript.default_set().plotting_names()
	assert(not plotting.has(LayerSetScript.UNDERLAY), "the underlay layer must not plot")
	for shape: Dictionary in _shapes(plan):
		assert(shape["layer"] == LayerSetScript.UNDERLAY, String(shape["layer"]))
		assert(not plotting.has(StringName(shape["layer"])), "nothing that plots was used")


func test_a_kept_import_maps_its_layers_and_warns_about_the_rest() -> void:
	var plan := DxfScript.read_text(_dxf(
		_line(Vector2.ZERO, Vector2(1.0, 0.0), "PROPERTY") + "\n"
		+ _line(Vector2.ZERO, Vector2(1.0, 0.0), "EASEMENT") + "\n"
		+ _line(Vector2.ZERO, Vector2(1.0, 0.0), "TREE-CANOPY") + "\n"
		+ _line(Vector2.ZERO, Vector2(1.0, 0.0), "LAYER-37")
	), {"underlay": false})
	assert(bool(plan["ok"]), String(plan["reason"]))
	var shapes := _shapes(plan)
	assert(shapes[0]["layer"] == LayerSetScript.SURVEY_PROPERTY)
	assert(shapes[1]["layer"] == LayerSetScript.SETBACK_EASEMENT)
	assert(shapes[2]["layer"] == LayerSetScript.EXISTING_PLANTING)
	# An unknown layer goes to the survey layer with a warning - never to a plotting layer by accident.
	assert(shapes[3]["layer"] == LayerSetScript.SURVEY_PROPERTY)
	var warnings: Array = plan["warnings"]
	assert(warnings.size() == 1, str(warnings))
	assert(String(warnings[0]).contains("LAYER-37"), String(warnings[0]))
	assert(_report(plan).contains("-37"), _report(plan))
	# The report says where each layer's geometry went, which is the thing nobody can see on the plan.
	assert(_report(plan).contains("PROPERTY -> %s" % LayerSetScript.SURVEY_PROPERTY), _report(plan))


func test_a_layer_nothing_recognises_is_named_once_however_many_shapes_it_has() -> void:
	var run := _line(Vector2.ZERO, Vector2(1.0, 0.0), "MYSTERY") + "\n" + _line(Vector2(1.0, 0.0), Vector2(2.0, 0.0), "MYSTERY")
	var plan := DxfScript.read_text(_dxf(run), {"underlay": false})
	assert((plan["warnings"] as Array).size() == 1, "one warning per layer, not per shape")


# --- registration (REQ 6.7.5) ---------------------------------------------------------


func test_a_placed_import_is_moved_and_turned_where_it_was_asked_to_be() -> void:
	var straight := DxfScript.read_text(_dxf(_line(Vector2.ZERO, Vector2(10.0, 0.0))))
	var placed := DxfScript.read_text(_dxf(_line(Vector2.ZERO, Vector2(10.0, 0.0))), {
		"offset": Vector2(100.0, -25.0), "rotation": 90.0,
	})
	assert(bool(placed["ok"]), String(placed["reason"]))
	var before: PackedVector2Array = _shapes(straight)[0]["points"]
	var after: PackedVector2Array = _shapes(placed)[0]["points"]
	assert(before[1] == Vector2(10.0, 0.0))
	# Turned a quarter turn about the origin, then moved.
	assert(after[1].is_equal_approx(Vector2(100.0, -25.0 + 10.0)), str(after[1]))
	assert(is_equal_approx((after[1] - after[0]).length(), 10.0), "the length is untouched by a registration")
	assert(_report(placed).contains("turned 90.0 degrees"), _report(placed))
	assert(_report(straight).contains("placed at the origin"), _report(straight))


# --- the report -----------------------------------------------------------------------


func test_the_report_reads_the_way_a_person_accepts_an_import() -> void:
	var plan := DxfScript.read_text(_dxf(
		_line(Vector2.ZERO, Vector2(10.0, 0.0), "PROPERTY") + "\n" + _circle(Vector2.ZERO, 1.0, "HARD"),
		2
	))
	var report := _report(plan)
	assert(String(plan["source"]).is_empty(), "a string has no file name of its own")
	assert(DxfScript.describe(plan) == "2 shapes in feet", DxfScript.describe(plan))
	assert(report.begins_with("2 shapes in feet"), report)
	assert(report.contains("the file's own $INSUNITS"), report)
	assert(report.contains("CIRCLE x1") and report.contains("LINE x1"), report)
	assert(report.contains("millimetres") or report.contains("x0.3048"), report)
	assert(DxfScript.is_usable(plan))
	# A file with entity records but nothing drawable is read, and is not usable.
	var nothing := DxfScript.read_text(_dxf("\n".join(PackedStringArray(["0", "SPLINE", "10", "1.0", "20", "1.0"]))))
	assert(bool(nothing["ok"]))
	assert(not DxfScript.is_usable(nothing))
	# And a refused file reports its reason rather than a count of nothing.
	assert(DxfScript.report_lines(DxfScript.read_text(""))[0] == "the file is empty")


func test_a_file_with_no_entities_at_all_says_so() -> void:
	var plan := DxfScript.read_text(_dxf(""))
	assert(bool(plan["ok"]), String(plan["reason"]))
	assert(_shapes(plan).is_empty())
	assert(int(plan["unit_factor"]) > 0.0, "it still has units")
	assert(_report(plan).contains("no entity records"), _report(plan))
	assert(not DxfScript.is_usable(plan))