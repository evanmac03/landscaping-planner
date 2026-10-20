extends Node
## Tests for a DXF arriving on the drawing: the shapes the controller makes of it, the layers they
## land on, and the fact that it is one undo step.
##
## The controller is built with its parts but no scene tree, as the survey-import and sheet tests are.
## The DXF is read by the real reader, so what is under test is the join between the two.

const Ctrl := preload("res://scripts/draft/draft_controller.gd")
const Tool := preload("res://scripts/draft/draft_tool.gd")
const Document := preload("res://scripts/draft/draft_document.gd")
const SnapScript := preload("res://scripts/draft/snap_engine.gd")
const Entity := preload("res://scripts/draft/draft_entity.gd")
const LayerSet := preload("res://scripts/draft/layer_set.gd")
const DxfScript := preload("res://scripts/draft/dxf_file.gd")


func _controller():
	var controller = Ctrl.new()
	controller.document = Document.new()
	controller.snap = SnapScript.new()
	controller.tool = Tool.new()
	return controller


func _dxf(entities: String, insunits: int = 6) -> String:
	var lines: Array[String] = [
		"0", "SECTION", "2", "HEADER", "9", "$INSUNITS", "70", str(insunits),
		"0", "ENDSEC", "0", "SECTION", "2", "ENTITIES",
	]
	if not entities.is_empty():
		lines.append(entities)
	lines.append_array(["0", "ENDSEC", "0", "EOF", ""])
	return "\n".join(PackedStringArray(lines))


func _line(a: Vector2, b: Vector2, layer: String = "PROPERTY") -> String:
	return "\n".join(PackedStringArray([
		"0", "LINE", "8", layer, "10", str(a.x), "20", str(a.y), "11", str(b.x), "21", str(b.y),
	]))


func _on_layer(controller, layer_name: StringName) -> Array:
	var out: Array = []
	for entity: DraftEntity in controller.document.entities():
		if entity.layer == layer_name:
			out.append(entity)
	return out


# --- what arrives ----------------------------------------------------------------------


func test_a_dxf_lands_as_geometry_on_the_layer_that_does_not_plot() -> void:
	var controller = _controller()
	var plan := DxfScript.read_text(_dxf(_line(Vector2(0.0, 0.0), Vector2(10.0, 0.0))))
	var taken: Dictionary = controller.import_dxf(plan)
	assert(bool(taken["ok"]), String(taken["reason"]))
	assert(int(taken["added"]) == 1, str(taken))
	assert(controller.document.count() == 1)
	assert(controller.last_message.begins_with("placed 1 shape on the underlay"), controller.last_message)
	# On the underlay, which is the whole point of the default: a surveyor's line work is something to
	# trace over, and a tracing aid must not reach the client's sheet.
	var on_underlay: Array = _on_layer(controller, LayerSet.UNDERLAY)
	assert(on_underlay.size() == 1, "it is on %s" % LayerSet.UNDERLAY)
	assert(not LayerSet.default_set().plotting_names().has(LayerSet.UNDERLAY), "and that layer does not plot")
	controller.free()


func test_the_geometry_arrives_mirrored_and_in_metres() -> void:
	var controller = _controller()
	# Ten feet in a DXF, drawn north: ten feet becomes 3.048 m, and north becomes -Y.
	var plan := DxfScript.read_text(_dxf(_line(Vector2(0.0, 0.0), Vector2(10.0, 10.0)), 2))
	assert(bool(controller.import_dxf(plan)["ok"]))
	var entity: DraftEntity = controller.document.entities()[0]
	var ends: PackedVector2Array = entity.points()
	assert(ends[1].is_equal_approx(Vector2(3.048, -3.048)), str(ends[1]))
	controller.free()


func test_every_shape_the_reader_hands_over_becomes_a_drawing_entity() -> void:
	var controller = _controller()
	var entities := "\n".join(PackedStringArray([
		"0", "LINE", "8", "PROPERTY", "10", "0.0", "20", "0.0", "11", "6.0", "21", "0.0",
		"0", "LWPOLYLINE", "8", "BOUNDARY", "90", "3", "70", "1",
		"10", "0.0", "20", "0.0", "10", "6.0", "20", "0.0", "10", "6.0", "20", "4.0",
		"0", "CIRCLE", "8", "HARD", "10", "2.0", "20", "2.0", "40", "1.5",
		"0", "ARC", "8", "HARD", "10", "8.0", "20", "0.0", "40", "2.0", "50", "0.0", "51", "90.0",
		"0", "TEXT", "8", "ANNO", "10", "1.0", "20", "1.0", "40", "0.4", "1", "P.L. 49.25",
	]))
	# The heavy polyline, whose vertices are separate records.
	entities += "\n" + "\n".join(PackedStringArray([
		"0", "POLYLINE", "8", "BOUNDARY", "70", "0",
		"0", "VERTEX", "10", "0.0", "20", "8.0", "0", "VERTEX", "10", "6.0", "20", "8.0", "0", "SEQEND",
	]))
	var plan := DxfScript.read_text(_dxf(entities))
	assert(bool(plan["ok"]), String(plan["reason"]))
	var taken: Dictionary = controller.import_dxf(plan)
	assert(bool(taken["ok"]), String(taken["reason"]))
	assert(int(taken["added"]) == 6, "all six: %s" % str(taken))
	assert(int(taken["refused"]) == 0, str(taken))
	var kinds := {}
	for entity: DraftEntity in controller.document.entities():
		kinds[int(entity.kind)] = int(kinds.get(int(entity.kind), 0)) + 1
	# One line, one polygon (the light polyline was closed), one polyline (the heavy one was not), a
	# circle, an arc and a text.
	assert(kinds.size() == 6, str(kinds))
	assert(int(kinds[DraftEntity.Kind.LINE]) == 1)
	assert(int(kinds[DraftEntity.Kind.POLYGON]) == 1, "a closed polyline is a polygon")
	assert(int(kinds[DraftEntity.Kind.POLYLINE]) == 1)
	assert(int(kinds[DraftEntity.Kind.CIRCLE]) == 1)
	assert(int(kinds[DraftEntity.Kind.ARC]) == 1)
	assert(int(kinds[DraftEntity.Kind.TEXT]) == 1)
	# The arc's quarter turn is the model's own: from 0 degrees sweeping -90, which in the model is
	# the quarter of the circle south of the centre.
	var arcs: Array = _on_layer(controller, LayerSet.UNDERLAY)
	var arc: DraftEntity = null
	for entity: DraftEntity in arcs:
		if entity.kind == DraftEntity.Kind.ARC:
			arc = entity
	assert(arc != null, "the arc came in")
	var arc_points: PackedVector2Array = arc.points()
	assert(arc_points[0].is_equal_approx(Vector2(8.0, 0.0)), "its centre")
	assert(arc_points.size() > 2, "and it is a real curve")
	controller.free()


func test_a_polyline_carries_its_bulges_so_a_curved_bed_stays_curved() -> void:
	var controller = _controller()
	var plan := DxfScript.read_text(_dxf("\n".join(PackedStringArray([
		"0", "LWPOLYLINE", "8", "BOUNDARY", "90", "2", "70", "0",
		"10", "0.0", "20", "0.0", "42", "1.0", "10", "6.0", "20", "0.0",
	]))))
	assert(bool(controller.import_dxf(plan)["ok"]))
	var entity: DraftEntity = controller.document.entities()[0]
	assert(entity.bulges.size() == 2, "one bulge per vertex: %d" % entity.bulges.size())
	assert(entity.bulges[0] == -1.0, "and the bulge turned round with the mirror: %s" % str(entity.bulges))
	# A bulge of -1 is a quarter turn: the *outline* is sampled round the arc, while the vertices stay
	# the two the file stated - which is what keeps the curve editable as a curve.
	var outline: PackedVector2Array = entity.outline()
	assert(outline.size() > 2, "the bulge is a curve with a point count: %d" % outline.size())
	assert(entity.points().size() == 2, "and the polyline is still two vertices")
	controller.free()


func test_a_text_keeps_the_size_it_was_drawn_at_on_paper() -> void:
	var controller = _controller()
	controller.plot_scale = 100.0
	var plan := DxfScript.read_text(_dxf("\n".join(PackedStringArray([
		"0", "TEXT", "8", "ANNO", "10", "0.0", "20", "0.0", "40", "0.4", "1", "P.L.",
	]))))
	assert(bool(controller.import_dxf(plan)["ok"]))
	var label: DraftEntity = controller.document.entities()[0]
	assert(String(label.meta.get("text", "")) == "P.L.")
	# 0.4 m at 1:100 is 4 mm of paper, which is what a text entity states - a paper height, not a
	# model one, because that is what the drawing's own dimensions do.
	assert(is_equal_approx(float(label.meta.get("height", 0.0)), 4.0), str(label.meta.get("height")))
	controller.free()


# --- the rules around it ---------------------------------------------------------------


func test_an_import_is_one_undo_step_however_many_shapes_it_holds() -> void:
	var controller = _controller()
	var run := _line(Vector2(0.0, 0.0), Vector2(1.0, 0.0))
	for index in 5:
		run += "\n" + _line(Vector2(0.0, float(index)), Vector2(5.0, float(index)))
	var plan := DxfScript.read_text(_dxf(run))
	assert(bool(controller.import_dxf(plan)["ok"]))
	assert(controller.document.count() == 6)
	assert(controller.dirty, "an import leaves the drawing unsaved")
	assert(controller.document.undo_last(), "one undo puts the drawing back")
	assert(controller.document.count() == 0, "all of it, not one shape")
	controller.free()


func test_a_file_it_cannot_draw_is_refused_in_words() -> void:
	var controller = _controller()
	# Nothing drawable at all.
	var nothing := DxfScript.read_text(_dxf("\n".join(PackedStringArray(["0", "SPLINE", "10", "1.0", "20", "1.0"]))))
	var taken: Dictionary = controller.import_dxf(nothing)
	assert(not bool(taken["ok"]))
	assert(controller.last_message.contains("nothing in it"), controller.last_message)
	assert(controller.document.count() == 0)
	assert(not controller.dirty)
	# And one that could not be read keeps the reader's own sentence.
	var refused := controller.import_dxf(DxfScript.read_text("not a dxf at all"))
	assert(not bool(refused["ok"]))
	assert(controller.last_message.contains("DXF"), controller.last_message)
	controller.free()


func test_a_drawing_that_is_not_there_is_refused_rather_than_a_crash() -> void:
	var controller = Ctrl.new()
	var plan := DxfScript.read_text(_dxf(_line(Vector2.ZERO, Vector2(1.0, 0.0))))
	var taken: Dictionary = controller.import_dxf(plan)
	assert(not bool(taken["ok"]))
	assert(controller.last_message == "there is no drawing to import it into", controller.last_message)
	controller.free()


func test_a_kept_import_lands_on_the_layers_its_layer_names_map_to() -> void:
	var controller = _controller()
	var plan := DxfScript.read_text(_dxf(
		_line(Vector2.ZERO, Vector2(1.0, 0.0), "PROPERTY") + "\n"
		+ _line(Vector2.ZERO, Vector2(1.0, 0.0), "EASEMENT")
	), {"underlay": false})
	var taken: Dictionary = controller.import_dxf(plan)
	assert(bool(taken["ok"]), String(taken["reason"]))
	assert(_on_layer(controller, LayerSet.SURVEY_PROPERTY).size() == 1)
	assert(_on_layer(controller, LayerSet.SETBACK_EASEMENT).size() == 1)
	assert(controller.last_message.contains("layers it maps to"), controller.last_message)
	controller.free()


func test_a_damaged_shape_cost_the_file_a_shape_and_not_the_import() -> void:
	var controller = _controller()
	var run := "\n".join(PackedStringArray([
		"0", "LINE", "8", "PROPERTY", "10", "junk", "20", "0.0", "11", "1.0", "21", "0.0",
	])) + "\n" + _line(Vector2(0.0, 4.0), Vector2(4.0, 4.0))
	var plan := DxfScript.read_text(_dxf(run))
	var taken: Dictionary = controller.import_dxf(plan)
	assert(bool(taken["ok"]), String(taken["reason"]))
	assert(int(taken["added"]) == 1)
	assert(controller.document.count() == 1, "and nothing was placed at the origin")
	controller.free()