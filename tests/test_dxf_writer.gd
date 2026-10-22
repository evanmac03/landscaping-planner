extends Node
## Tests for writing an ASCII DXF: the inversions, the units, and that a file this program writes is
## one it can read back.
##
## The round trip is the strongest test here - read a file, write it out, read it again, compare - and
## the rest are the specific things a round trip would hide. A bulge that shifted one segment along
## still round-trips as *a* curved polyline; an arc that came back the other way round is still an arc;
## a rectangle sampled into ninety segments still has the right corners. Each of those has its own
## test because each of them is invisible to an equality check that is not careful enough.

const DxfScript := preload("res://scripts/draft/dxf_file.gd")
const Writer := preload("res://scripts/draft/dxf_writer.gd")
const DocumentScript := preload("res://scripts/draft/draft_document.gd")
const EntityScript := preload("res://scripts/draft/draft_entity.gd")
const LayerSetScript := preload("res://scripts/draft/layer_set.gd")


## A drawing with one of each thing the writer can write, on the layers they belong on.
func _drawing() -> DraftDocument:
	var document := DocumentScript.new()
	document.add(EntityScript.make_line(Vector2(0, 0), Vector2(10, 0)), LayerSetScript.NEW_HARDSCAPE)
	document.add(EntityScript.make_circle(Vector2(5, 5), 3.0), LayerSetScript.NEW_BED)
	document.add(EntityScript.make_arc(Vector2(4, 4), 5.0, deg_to_rad(30.0), deg_to_rad(60.0)),
		LayerSetScript.NEW_HARDSCAPE)
	var curved := EntityScript.make_polyline(
		PackedVector2Array([Vector2(0, 0), Vector2(10, 0), Vector2(10, 10)])
	)
	curved.bulges = PackedFloat64Array([0.0, 1.0, 0.0])
	document.add(curved, LayerSetScript.NEW_BED)
	document.add(EntityScript.make_text(Vector2(1, 2), "BED 1"), LayerSetScript.TEXT)
	return document


# --- the round trip --------------------------------------------------------------------


## A file that went through the reader and then through the writer reads back the same. This is what
## makes the writer the reader's inverse rather than a second opinion about the format.
func test_a_file_read_then_written_reads_back_the_same() -> void:
	var source := _fixture()
	var first := DxfScript.read_text(source)
	assert(first["ok"], String(first["reason"]))
	var written := Writer.write_text(first["shapes"])
	assert(written["ok"], String(written["reason"]))
	var second := DxfScript.read_text(String(written["text"]))
	assert(second["ok"], String(second["reason"]))
	var was_all: Array = first["shapes"]
	var now_all: Array = second["shapes"]
	assert(was_all.size() == now_all.size(), "the same number of shapes")
	assert(not was_all.is_empty(), "and there was something to compare")
	for at in was_all.size():
		var was: Dictionary = was_all[at]
		var now: Dictionary = now_all[at]
		assert(now["kind"] == was["kind"], "shape %d is the same kind" % at)
		assert(now["layer"] == was["layer"], "shape %d is on the same layer" % at)
		assert(bool(now["closed"]) == bool(was["closed"]), "shape %d is closed the same" % at)
		assert(String(now["words"]) == String(was["words"]), "shape %d says the same thing" % at)
		assert(is_equal_approx(float(now["height"]), float(was["height"])), "shape %d is the same size" % at)
		assert(is_equal_approx(float(now["radius"]), float(was["radius"])),
			"shape %d is the same radius" % at)
		var was_points: PackedVector2Array = was["points"]
		var now_points: PackedVector2Array = now["points"]
		assert(now_points.size() == was_points.size(), "shape %d has the same number of points" % at)
		for p in was_points.size():
			assert(now_points[p].is_equal_approx(was_points[p]),
				"shape %d point %d came back where it was: %s vs %s" % [at, p, now_points[p], was_points[p]])
		var was_bulges: PackedFloat64Array = was["bulges"]
		var now_bulges: PackedFloat64Array = now["bulges"]
		assert(now_bulges.size() == was_bulges.size(), "shape %d has the same bulges" % at)
		for b in was_bulges.size():
			assert(is_equal_approx(now_bulges[b], was_bulges[b]),
				"shape %d bulge %d came back the same: %f vs %f" % [at, b, now_bulges[b], was_bulges[b]])
		# An arc's own angles are the thing most likely to arrive the other way round.
		var was_arc: Vector2 = was["arc"]
		var now_arc: Vector2 = now["arc"]
		assert(is_equal_approx(now_arc.x, was_arc.x) and is_equal_approx(now_arc.y, was_arc.y),
			"shape %d's arc came back the way it went out: %s vs %s" % [at, now_arc, was_arc])


## A drawing's own geometry goes out and comes back: the same kinds, at the same sizes, in the same
## places, with the words still on the text.
func test_a_drawing_goes_out_and_comes_back() -> void:
	var made := Writer.shapes_from_document(_drawing())
	assert(made["ok"], String(made["reason"]))
	assert((made["shapes"] as Array).size() == 5, "one record per shape on a plotting layer")
	var written := Writer.write_text(made["shapes"])
	assert(written["ok"], String(written["reason"]))
	var back := DxfScript.read_text(String(written["text"]))
	assert(back["ok"], String(back["reason"]))
	assert(back["units"] == "metres")
	var shapes: Array = back["shapes"]
	assert(shapes.size() == 5)
	# Compared as a set, not in order: the document hands its shapes out in layer-band order, which is
	# the order they are drawn in and not the order they were added.
	var kinds: Array[String] = []
	for shape: Dictionary in shapes:
		kinds.append(String(shape["kind"]))
	kinds.sort()
	assert(kinds == ["ARC", "CIRCLE", "LINE", "LWPOLYLINE", "TEXT"], str(kinds))
	# The circle is where it was and as big as it was.
	var circle: Dictionary = _of_kind(shapes, "CIRCLE")
	var circle_points: PackedVector2Array = circle["points"]
	assert(circle_points[0].is_equal_approx(Vector2(5, 5)), str(circle_points[0]))
	assert(is_equal_approx(float(circle["radius"]), 3.0), str(circle["radius"]))
	# And the text still says what it said, at a size that can be seen.
	var text: Dictionary = _of_kind(shapes, "TEXT")
	assert(String(text["words"]) == "BED 1")
	assert(float(text["height"]) > 0.0, "a text with no height is an invisible text")


# --- the things a careless writer gets wrong -------------------------------------------


## The bulges are paired to their points *by position*, so a straight segment has to write its zero
## rather than leave it out. If it did not, this curve would arrive one segment along.
func test_a_bulge_lands_on_the_segment_it_belongs_to() -> void:
	var document := DocumentScript.new()
	var curved := EntityScript.make_polyline(
		PackedVector2Array([Vector2(0, 0), Vector2(10, 0), Vector2(10, 10)])
	)
	curved.bulges = PackedFloat64Array([0.0, 1.0, 0.0])
	document.add(curved, LayerSetScript.NEW_BED)
	var back := _round_trip(document)
	var shape: Dictionary = (back["shapes"] as Array)[0]
	assert(shape["kind"] == "LWPOLYLINE")
	var bulges: PackedFloat64Array = shape["bulges"]
	assert(bulges.size() == 3, "one bulge per vertex, straight ones included")
	assert(is_zero_approx(bulges[0]), "the first segment is straight")
	assert(is_equal_approx(bulges[1], 1.0), "the curve is on the middle segment, where it was put")
	assert(is_zero_approx(bulges[2]), "the last segment is straight")


## Handedness: a DXF arc always runs counterclockwise, so after the reflection every arc the reader
## produces has a *non-positive* sweep in the model. An arc a designer drew the other way round
## therefore cannot be written as it stands and is described from its other end instead - which is the
## same arc. So an arc is compared by the arc it covers, not by the end it happens to be written from.
func test_an_arc_comes_back_covering_the_same_arc() -> void:
	for sweep: float in [60.0, -60.0]:
		var document := DocumentScript.new()
		document.add(
			EntityScript.make_arc(Vector2(4, 4), 5.0, deg_to_rad(30.0), deg_to_rad(sweep)),
			LayerSetScript.NEW_HARDSCAPE
		)
		var back := _round_trip(document)
		var shape: Dictionary = (back["shapes"] as Array)[0]
		assert(shape["kind"] == "ARC", str(sweep))
		var radius := float(shape["radius"])
		assert(is_equal_approx(radius, 5.0), "the radius of an arc of %f degrees: %f" % [sweep, radius])
		var arc: Vector2 = shape["arc"]
		assert(arc.y <= 0.0 or is_zero_approx(arc.y),
			"a DXF arc runs counterclockwise, so a model arc never sweeps positively: %s" % str(arc))
		var was := _ends(Vector2(4, 4), 5.0, 30.0, sweep)
		# The table's `arc` is in degrees, the way the file states an angle: the reader takes group 50
		# and 51 as they are, so nothing here converts.
		var now := _ends(
			(shape["points"] as PackedVector2Array)[0], radius, arc.x, arc.y
		)
		assert(_same_ends(was, now),
			"an arc of %f degrees covers the same arc coming back: %s vs %s" % [sweep, str(now), str(was)])


## A rectangle has no DXF record of its own, so it goes out as its own four corners - and comes back
## as a closed polyline of the same size rather than as something else.
func test_a_rectangle_goes_out_as_its_own_corners() -> void:
	var document := DocumentScript.new()
	document.add(EntityScript.make_rectangle(Vector2(5, 5), Vector2(8, 4)), LayerSetScript.NEW_HARDSCAPE)
	var back := _round_trip(document)
	var shape: Dictionary = (back["shapes"] as Array)[0]
	assert(shape["kind"] == "LWPOLYLINE")
	assert(bool(shape["closed"]), "a rectangle is a closed shape")
	assert((shape["points"] as PackedVector2Array).size() == 4, "four corners, not a sampled outline")
	for bulge: float in (shape["bulges"] as PackedFloat64Array):
		assert(is_zero_approx(bulge), "a rectangle has no curves in it")


# --- units -----------------------------------------------------------------------------


## The model is always in metres, so the unit written is a choice - and the file has to say what it
## chose, because a DXF that does not say is one the reader refuses.
func test_the_file_says_what_its_numbers_mean() -> void:
	var written := Writer.write_text([])
	assert(written["ok"], String(written["reason"]))
	assert(String(written["units"]) == "metres")
	assert(int(written["unit_code"]) == 6)
	assert(String(written["text"]).contains("$INSUNITS"), "the header carries the units")
	# Godot's own unit codes: 2 is feet, 1 is inches.
	assert(int(Writer.write_text([], {"units": "feet"})["unit_code"]) == 2)
	assert(int(Writer.write_text([], {"units": "in"})["unit_code"]) == 1)


## A length in feet leaves the file as feet and reaches the model as metres again. Ten metres is
## 32.8084 feet, and the number in the file is the file's rather than the model's.
func test_a_length_is_written_in_the_unit_that_was_asked_for() -> void:
	var document := DocumentScript.new()
	document.add(EntityScript.make_line(Vector2(0, 0), Vector2(10, 0)), LayerSetScript.NEW_HARDSCAPE)
	var made := Writer.shapes_from_document(document)
	var written := Writer.write_text(made["shapes"], {"units": "feet"})
	assert(String(written["text"]).contains("32.808"),
		"ten metres is written as its length in feet")
	var back := DxfScript.read_text(String(written["text"]))
	assert(back["units"] == "feet")
	var points: PackedVector2Array = (back["shapes"] as Array)[0]["points"]
	assert(points[1].is_equal_approx(Vector2(10, 0)), "and it is ten metres again on the way back")


func test_a_unit_nobody_has_is_refused() -> void:
	var written := Writer.write_text([], {"units": "furlongs"})
	assert(not bool(written["ok"]))
	assert(String(written["reason"]).contains("furlongs"), String(written["reason"]))


func test_a_plot_scale_of_nothing_is_not_a_scale() -> void:
	var written := Writer.write_text([], {"scale": 0.0})
	assert(not bool(written["ok"]))
	assert(String(written["reason"]).contains("scale"), String(written["reason"]))


# --- what is left out, and saying so ---------------------------------------------------


## A dimension is an annotation with no size until a plot scale is given it, so it is named rather than
## silently turned into a pile of strokes.
func test_a_dimension_is_named_rather_than_turned_into_linework() -> void:
	var document := DocumentScript.new()
	document.add(EntityScript.make_dimension(Vector2(0, 0), Vector2(5, 0)), LayerSetScript.DIMENSION)
	var made := Writer.shapes_from_document(document)
	assert((made["shapes"] as Array).is_empty(), "nothing of it is written")
	assert(made["not_written"].size() == 1)
	assert(String(made["not_written"][0]) == "1 dimension(s) left out", str(made["not_written"]))


## What the program draws for the person at the desk is not what goes to somebody else: a tracing aid
## does not plot, so it does not leave.
func test_only_what_plots_goes_out() -> void:
	var document := DocumentScript.new()
	document.add(EntityScript.make_line(Vector2(0, 0), Vector2(1, 0)), LayerSetScript.UNDERLAY)
	document.add(EntityScript.make_line(Vector2(0, 0), Vector2(2, 0)), LayerSetScript.NEW_HARDSCAPE)
	var made := Writer.shapes_from_document(document)
	assert((made["shapes"] as Array).size() == 1, "the plotting one only")


## A shape that was read from a file is written back onto the name it came from, so a file that was
## read and written re-reads onto the same layers it did the first time.
func test_a_shape_keeps_the_layer_name_it_was_read_from() -> void:
	var shapes: Array = [{
		"kind": "LINE", "layer": LayerSetScript.SURVEY_PROPERTY, "dxf_layer": "CONTOUR",
		"points": PackedVector2Array([Vector2(0, 0), Vector2(1, 1)]),
		"bulges": PackedFloat64Array(), "closed": false, "words": "", "height": 0.0,
		"arc": Vector2.ZERO,
	}]
	var written := Writer.write_text(shapes)
	assert(written["layers"] == ["CONTOUR"], str(written["layers"]))
	assert(String(written["text"]).contains("CONTOUR"))
	var back := DxfScript.read_text(String(written["text"]), {"underlay": false})
	assert((back["shapes"] as Array)[0]["layer"] == LayerSetScript.GRADING_CONTOUR,
		"and it maps where it mapped the first time")


## A drawing that has never been near a file has no name to keep, so its own layer is the DXF layer.
func test_a_drawn_shape_goes_out_on_its_own_layer() -> void:
	var document := DocumentScript.new()
	document.add(EntityScript.make_line(Vector2(0, 0), Vector2(1, 0)), LayerSetScript.NEW_PLANTING)
	var made := Writer.shapes_from_document(document)
	var written := Writer.write_text(made["shapes"])
	assert(written["layers"] == [String(LayerSetScript.NEW_PLANTING)], str(written["layers"]))


# --- saying what was written -----------------------------------------------------------


func test_describe_reads_as_one_line() -> void:
	var made := Writer.shapes_from_document(_drawing())
	var written := Writer.write_text(made["shapes"])
	var words := Writer.describe(written)
	assert(words.contains("5 records"), words)
	assert(words.contains("metres"), words)
	assert(words.contains("3 layers"), words)


func test_a_refusal_reads_as_its_reason() -> void:
	assert(String(Writer.describe(Writer.write_text([], {"units": "furlongs"}))).contains("furlongs"))


## Text height is an assumption - the model does not hold one - so the report says so, and stops
## saying it once somebody states the scale.
func test_the_report_admits_the_scale_it_assumed() -> void:
	var made := Writer.shapes_from_document(_drawing())
	var guessed := Writer.write_text(made["shapes"])
	assert(bool(guessed["scale_assumed"]))
	assert(_joined(Writer.report_lines(guessed)).contains("assumed"))
	var stated := Writer.write_text(made["shapes"], {"scale": 50.0})
	assert(not bool(stated["scale_assumed"]))
	assert(not _joined(Writer.report_lines(stated)).contains("assumed"))


func test_the_report_names_the_layers_that_went_out() -> void:
	var made := Writer.shapes_from_document(_drawing())
	var written := Writer.write_text(made["shapes"])
	var text := _joined(Writer.report_lines(written))
	assert(text.contains(String(LayerSetScript.NEW_HARDSCAPE)), text)
	assert(text.contains(String(LayerSetScript.NEW_BED)), text)


func _joined(lines: Array[String]) -> String:
	return "\n".join(lines)


## The one shape of a kind, however the document chose to order them.
func _of_kind(shapes: Array, kind: String) -> Dictionary:
	for shape: Dictionary in shapes:
		if String(shape["kind"]) == kind:
			return shape
	assert(false, "there is no %s among them" % kind)
	return {}


## The two ends of an arc, in model metres.
func _ends(centre: Vector2, radius: float, start_degrees: float, sweep_degrees: float) -> Array[Vector2]:
	var out: Array[Vector2] = []
	for at: float in [start_degrees, start_degrees + sweep_degrees]:
		var turn := deg_to_rad(at)
		out.append(centre + Vector2(cos(turn), sin(turn)) * radius)
	return out


## Whether two arcs are the same arc, whichever of its two ends each was written from.
func _same_ends(one: Array[Vector2], other: Array[Vector2]) -> bool:
	var same_way := one[0].is_equal_approx(other[0]) and one[1].is_equal_approx(other[1])
	var other_way := one[0].is_equal_approx(other[1]) and one[1].is_equal_approx(other[0])
	return same_way or other_way


# --- helpers ---------------------------------------------------------------------------


## One drawing round the whole way: from a document, out as text, and back in through the reader.
func _round_trip(document: DraftDocument) -> Dictionary:
	var made := Writer.shapes_from_document(document)
	assert(made["ok"], String(made["reason"]))
	var written := Writer.write_text(made["shapes"])
	assert(written["ok"], String(written["reason"]))
	var back := DxfScript.read_text(String(written["text"]))
	assert(back["ok"], String(back["reason"]))
	return back


## A whole DXF around a run of entity records, in metres, the way `test_dxf_file` builds them.
func _fixture() -> String:
	var lines: Array[String] = [
		"0", "SECTION", "2", "HEADER",
		"9", "$INSUNITS", "70", "6",
		"0", "ENDSEC",
		"0", "SECTION", "2", "ENTITIES",
		"0", "LINE", "8", "PROPERTY",
		"10", "0", "20", "0", "11", "10", "21", "0",
		"0", "CIRCLE", "8", "HARD",
		"10", "5", "20", "5", "40", "3",
		"0", "ARC", "8", "HARD",
		"10", "4", "20", "4", "40", "5", "50", "30", "51", "90",
		# A polyline whose middle segment is curved: the bulge has to survive on that segment.
		"0", "LWPOLYLINE", "8", "PLANT", "70", "1",
		"10", "0", "20", "0", "42", "0",
		"10", "10", "20", "0", "42", "0.5",
		"10", "10", "20", "10", "42", "0",
		"0", "TEXT", "8", "ANNO",
		"10", "1", "20", "2", "40", "0.25", "1", "BED 1",
		"0", "ENDSEC", "0", "EOF", "",
	]
	return "\n".join(PackedStringArray(lines))