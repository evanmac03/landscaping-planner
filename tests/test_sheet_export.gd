extends Node
## Tests for the plotted sheet.
##
## The conformance test is the first one: a 10 m wall at 1:100 has to measure
## 100 mm on the paper, read back out of the actual bytes rather than out of the
## helper that wrote them. The rest check the things that make a PDF a PDF - the
## page box, the cross-reference table, escaping - and the things that make a
## landscape plan a plan - north up, the pen table's weights, real curves for
## circles.

const Exporter := preload("res://scripts/draft/sheet_exporter.gd")
const Document := preload("res://scripts/draft/draft_document.gd")
const Entity := preload("res://scripts/draft/draft_entity.gd")
const LayerSet := preload("res://scripts/draft/layer_set.gd")
const PenStyle := preload("res://scripts/draft/plot_style_table.gd")
const LineStyle := preload("res://scripts/draft/line_style.gd")


func _document():
	var document = Document.new()
	document.add(Entity.make_line(Vector2(0, 0), Vector2(10, 0)), LayerSet.NEW_HARDSCAPE)
	document.add(Entity.make_circle(Vector2(6, 5), 2.0), LayerSet.NEW_PLANTING)
	document.add(Entity.make_text(Vector2(1, 1), "Patio (new)"), LayerSet.TEXT)
	return document


# --- reading the file back out ------------------------------------------------------


## Every m/l/point pair in the file, so a test reads what was actually written.
func _moved_points(text: String) -> Array[Vector2]:
	var out: Array[Vector2] = []
	for line in text.split("\n"):
		var parts := line.strip_edges().split(" ", false)
		if parts.size() == 3 and (parts[2] == "m" or parts[2] == "l"):
			out.append(Vector2(float(parts[0]), float(parts[1])))
	return out


## The end point of each cubic curve.
func _curve_ends(text: String) -> Array[Vector2]:
	var out: Array[Vector2] = []
	for line in text.split("\n"):
		var parts := line.strip_edges().split(" ", false)
		if parts.size() == 7 and parts[6] == "c":
			out.append(Vector2(float(parts[4]), float(parts[5])))
	return out


func _first_move(text: String) -> Vector2:
	var moves := _moved_points(text)
	return moves[0] if not moves.is_empty() else Vector2.ZERO


# --- the thing that matters ---------------------------------------------------------


func test_ten_metres_at_one_to_one_hundred_measures_one_hundred_millimetres() -> void:
	var document = Document.new()
	document.add(Entity.make_line(Vector2(0, 0), Vector2(10, 0)), LayerSet.NEW_HARDSCAPE)
	var options := {"sheet": "A3", "scale": 100.0, "show_border": false}
	var text := Exporter.export_pdf(document, options).get_string_from_utf8()

	var points := _moved_points(text)
	assert(points.size() == 2)
	var paper_mm := points[0].distance_to(points[1]) / Exporter.POINTS_PER_MM
	# A fifth of a millimetre of slack. A printed sheet cannot resolve more, and
	# a contractor scaling off it cannot measure more.
	assert(absf(paper_mm - 100.0) < 0.2)


func test_the_layout_helper_agrees_with_the_file() -> void:
	var document = Document.new()
	document.add(Entity.make_line(Vector2(0, 0), Vector2(10, 0)), LayerSet.NEW_HARDSCAPE)
	var options := {"sheet": "A3", "scale": 100.0, "show_border": false}
	var plan := Exporter.plan_sheet(document, options)
	var points := _moved_points(Exporter.export_pdf(document, options).get_string_from_utf8())
	assert(points.size() == 2)
	var from_plan := Exporter.model_to_paper(Vector2.ZERO, plan)
	assert(from_plan.distance_to(points[0]) < 0.01)
	assert(
		Exporter.model_to_paper(Vector2(10, 0), plan).distance_to(points[1]) < 0.01
	)


func test_a_typical_yard_is_suggested_at_one_to_one_hundred() -> void:
	var document = Document.new()
	document.add(Entity.make_rectangle(Vector2(14, 10), Vector2(28, 20)), LayerSet.NEW_HARDSCAPE)
	var plan := Exporter.plan_sheet(document, {"sheet": "A3"})
	assert(is_equal_approx(plan["scale"], 100.0))
	var text := Exporter.export_pdf(document, {"sheet": "A3"}).get_string_from_utf8()
	assert(text.contains("SCALE 1:100"))


# --- a file that opens --------------------------------------------------------------


func test_the_page_box_is_a_real_a3_sheet() -> void:
	var text := Exporter.export_pdf(_document(), {"sheet": "A3"}).get_string_from_utf8()
	var at := text.find("/MediaBox [")
	assert(at > 0)
	var body := text.substr(at + 11, text.find("]", at) - at - 11)
	var numbers := body.split(" ", false)
	assert(numbers.size() == 4)
	assert(float(numbers[0]) == 0.0)
	assert(float(numbers[1]) == 0.0)
	assert(absf(float(numbers[2]) - 420.0 * Exporter.POINTS_PER_MM) < 0.001)
	assert(absf(float(numbers[3]) - 297.0 * Exporter.POINTS_PER_MM) < 0.001)


## The cross-reference table holds byte offsets into the finished file. An offset
## that is one byte out gives a file some readers open and others refuse, so it
## is worth checking every one rather than trusting the arithmetic.
func test_the_cross_reference_table_points_at_the_objects() -> void:
	var text := Exporter.export_pdf(_document(), {}).get_string_from_utf8()
	var marker := text.find("\nxref\n")
	assert(marker > 0)
	var xref_at := marker + 1

	var header := text.find("0 6\n", xref_at)
	assert(header > xref_at)
	var entries := text.substr(header + 4).split("\n")
	for index in range(1, 6):
		var entry := entries[index]
		assert(entry.length() >= 18)
		var offset := int(entry.substr(0, 10))
		assert(offset > 0)
		var expected := "%d 0 obj\n" % index
		assert(text.substr(offset, expected.length()) == expected)
	# The free entry for object zero.
	assert(entries[0].begins_with("0000000000 65535 f"))

	var start := text.rfind("startxref\n")
	assert(start > 0)
	assert(int(text.substr(start + 10).split("\n")[0]) == xref_at)
	assert(text.ends_with("%%EOF\n"))


func test_an_empty_document_still_plots_a_sheet() -> void:
	var bytes := Exporter.export_pdf(Document.new(), {})
	assert(bytes.size() > 400)
	var text := bytes.get_string_from_utf8()
	assert(text.begins_with("%PDF-1.4\n"))
	assert(text.ends_with("%%EOF\n"))
	assert(text.contains("SCALE "))


func test_the_border_stays_inside_the_printable_area() -> void:
	var plan := Exporter.plan_sheet(_document(), {"sheet": "A3"})
	var text := Exporter.export_pdf(_document(), {"sheet": "A3"}).get_string_from_utf8()
	var area: Rect2 = plan["printable_pt"]
	# The border is drawn on the drawing area, so it cannot fall off the sheet.
	assert(text.contains("%s %s %s %s re" % [
		String.num(area.position.x, 4), String.num(area.position.y, 4),
		String.num(area.size.x, 4), String.num(area.size.y, 4),
	]))
	assert(area.position.x > 0.0)
	assert(area.end.x < 420.0 * Exporter.POINTS_PER_MM)


# --- orientation and placement ------------------------------------------------------


## Getting this backwards mirrors the whole plan while still looking like a plan,
## which is exactly the kind of mistake that reaches a client.
func test_north_is_up_on_the_sheet() -> void:
	var plan := Exporter.plan_sheet(_document(), {"sheet": "A3", "show_border": false})
	# Model y runs south, so a smaller y is further north and must sit higher.
	var north := Exporter.model_to_paper(Vector2(0, 0), plan)
	var south := Exporter.model_to_paper(Vector2(0, 10), plan)
	assert(north.y > south.y)
	assert(is_equal_approx(north.x, south.x))
	var west := Exporter.model_to_paper(Vector2(0, 0), plan)
	var east := Exporter.model_to_paper(Vector2(10, 0), plan)
	assert(east.x > west.x)


func test_the_drawing_is_centred_in_the_printable_area() -> void:
	var document = _document()
	var plan := Exporter.plan_sheet(document, {"sheet": "A3", "show_border": false})
	var area: Rect2 = plan["printable_pt"]
	var extent: Rect2 = plan["extent"]
	var north_west := Exporter.model_to_paper(extent.position, plan)
	var south_east := Exporter.model_to_paper(extent.end, plan)
	var centre := (north_west + south_east) * 0.5
	assert(centre.distance_to(area.get_center()) < 0.01)
	var drawn: Vector2 = plan["drawing_pt"]
	assert(drawn.x <= area.size.x + 0.01)
	assert(drawn.y <= area.size.y + 0.01)


# --- pens ---------------------------------------------------------------------------


func test_a_pen_decides_the_plotted_weight_and_colour() -> void:
	var table = PenStyle.empty_table()
	var pen := LineStyle.new()
	pen.plot_weight_mm = 3.0
	pen.plot_colour = Color(0, 0, 1)
	table.set_entry(PenStyle.SLOT_RED, pen)

	var document = Document.new()
	document.add(Entity.make_line(Vector2(0, 0), Vector2(10, 0)), LayerSet.NEW_HARDSCAPE)
	var text := Exporter.export_pdf(
		document, {"pen_table": table, "show_border": false}
	).get_string_from_utf8()

	# 3 mm of pen is 8.5039 points, and the pen's blue replaces the layer's red.
	assert(text.contains("8.5039 w"))
	assert(text.contains("0.0 0.0 1.0 RG"))


func test_without_a_pen_table_the_layer_plots_itself() -> void:
	var document = Document.new()
	document.add(Entity.make_line(Vector2(0, 0), Vector2(10, 0)), LayerSet.NEW_HARDSCAPE)
	var text := Exporter.export_pdf(document, {"show_border": false}).get_string_from_utf8()
	# The preset layer weight for paving is 0.50 mm, which is 1.4173 points.
	assert(text.contains("1.4173 w"))


func test_a_dashed_linetype_becomes_a_dash_array_in_points() -> void:
	var entity = Entity.make_line(Vector2(0, 0), Vector2(10, 0))
	var override := LineStyle.new()
	override.linetype = &"dashed"
	override.plot_weight_mm = 0.25
	entity.style = override
	var document = Document.new()
	document.add(entity, LayerSet.NEW_HARDSCAPE)

	var text := Exporter.export_pdf(document, {"show_border": false}).get_string_from_utf8()
	# A dash is authored in paper millimetres and a PDF dash array is in points:
	# 6 mm and 2 mm are 17.0079 and 5.6693 points.
	assert(text.contains("[17.0079 5.6693] 0 d"))


func test_a_solid_linetype_clears_the_dash_array() -> void:
	var document = Document.new()
	document.add(Entity.make_line(Vector2(0, 0), Vector2(10, 0)), LayerSet.NEW_HARDSCAPE)
	var text := Exporter.export_pdf(document, {"show_border": false}).get_string_from_utf8()
	assert(text.contains("[] 0 d"))


# --- curves and text -----------------------------------------------------------------


## A client zooming into the PDF must not be able to see facets, and a tree pit
## has to stay round.
func test_a_circle_plots_as_four_real_arcs() -> void:
	var document = Document.new()
	document.add(Entity.make_circle(Vector2(0, 0), 5.0), LayerSet.NEW_PLANTING)
	var options := {"show_border": false}
	var text := Exporter.export_pdf(document, options).get_string_from_utf8()

	assert(text.count(" c\n") == 4)
	assert(text.count(" l\n") == 0)

	var plan := Exporter.plan_sheet(document, options)
	var centre := Exporter.model_to_paper(Vector2.ZERO, plan)
	var expected: float = 5.0 * plan["pt_per_metre"]
	var ends := _curve_ends(text)
	assert(ends.size() == 4)
	for point: Vector2 in ends:
		# Every quarter ends exactly on the circle.
		assert(absf(point.distance_to(centre) - expected) < 0.01)
	# And the last quarter returns to where the first began, so the circle closes.
	assert(ends[ends.size() - 1].distance_to(_first_move(text)) < 0.01)


func test_an_arc_plots_only_its_sweep() -> void:
	var document = Document.new()
	document.add(Entity.make_arc(Vector2.ZERO, 5.0, 0.0, PI * 0.5), LayerSet.NEW_PLANTING)
	var text := Exporter.export_pdf(document, {"show_border": false}).get_string_from_utf8()
	# A quarter turn is one cubic, and it must not close the gap back to the start.
	assert(text.count(" c\n") == 1)
	assert(not text.contains("h\n"))


func test_a_text_entity_plots_its_label_escaped() -> void:
	var document = Document.new()
	document.add(Entity.make_text(Vector2(0, 0), "Patio (new)"), LayerSet.TEXT)
	var text := Exporter.export_pdf(document, {"show_border": false}).get_string_from_utf8()
	# The parentheses have to be escaped, or the string ends early and the whole
	# file becomes unreadable.
	assert(text.contains("(Patio \\(new\\)) Tj"))


func test_the_title_reaches_the_sheet() -> void:
	var text := Exporter.export_pdf(
		_document(), {"title": "Backyard Design"}
	).get_string_from_utf8()
	assert(text.contains("Backyard Design"))