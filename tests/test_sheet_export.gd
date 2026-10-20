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
const Dimension := preload("res://scripts/draft/dimension.gd")
const PlotScale := preload("res://scripts/draft/plot_scale.gd")
const Render := preload("res://scripts/draft/draft_render.gd")


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
	# The scale is a field in the title block now, not a banner across the sheet.
	assert(text.contains("(SCALE) Tj"))
	assert(text.contains("(1:100) Tj"))


# --- the sheet furniture -------------------------------------------------------------


## Every rectangle in the file, so a test can look for the block and the bar
## without depending on where in the stream they were written.
func _rectangles(text: String) -> Array[Rect2]:
	var out: Array[Rect2] = []
	for line in text.split("\n"):
		var parts := line.strip_edges().split(" ", false)
		if parts.size() == 5 and parts[4] == "re":
			out.append(Rect2(
				Vector2(float(parts[0]), float(parts[1])),
				Vector2(float(parts[2]), float(parts[3]))
			))
	return out


func _has_point(points: Array[Vector2], target: Vector2) -> bool:
	for point in points:
		if point.distance_to(target) < 0.01:
			return true
	return false


func _title_block(plan: Dictionary) -> Rect2:
	var area: Rect2 = plan["printable_pt"]
	var size := Vector2(
		Exporter.TITLE_BLOCK_WIDTH_MM, Exporter.TITLE_BLOCK_HEIGHT_MM
	) * Exporter.POINTS_PER_MM
	return Rect2(area.end - size, size)


func test_the_title_block_lands_in_the_corner_of_the_border() -> void:
	var plan := Exporter.plan_sheet(_document(), {"sheet": "A3"})
	var text := Exporter.export_pdf(_document(), {"sheet": "A3"}).get_string_from_utf8()
	var block := _title_block(plan)
	var area: Rect2 = plan["printable_pt"]
	# Flush into the corner, so it reads as part of the border rather than as
	# something floating inside the drawing.
	assert(block.end.x == area.end.x)
	assert(block.end.y == area.end.y)
	var found := false
	for rect in _rectangles(text):
		if rect.position.distance_to(block.position) < 0.01 \
				and rect.size.distance_to(block.size) < 0.01:
			found = true
	assert(found)


func test_every_title_block_field_reaches_the_sheet() -> void:
	var options := {
		"sheet": "A3",
		"project": "Riverbend",
		"drawing": "Planting Plan",
		"date": "2026-05-04",
		"revision": "C",
	}
	var text := Exporter.export_pdf(_document(), options).get_string_from_utf8()
	for caption in ["PROJECT", "DRAWING", "SCALE", "SHEET", "DATE", "REV"]:
		assert(text.contains("(%s) Tj" % caption))
	# The values the caller set, and the scale the sheet was actually laid out at
	# rather than a scale this test assumed.
	for value in ["Riverbend", "Planting Plan", "2026-05-04", "C"]:
		assert(text.contains("(%s) Tj" % value))
	var plan := Exporter.plan_sheet(_document(), options)
	assert(text.contains("(%s) Tj" % PlotScale.metric_label(plan["scale"])))


## The block is a field of the sheet, not an entity, so it must not appear when
## nobody asked for a border.
## The strip the block claims is charged to the choice of scale, not only to the
## placement. A sheet that picked a scale for the whole printable area and then
## centred the drawing under the title block would be inconsistent with itself.
func test_the_choice_of_scale_respects_the_title_block() -> void:
	var document = Document.new()
	document.add(Entity.make_rectangle(Vector2(30, 30), Vector2(60, 60)), LayerSet.NEW_HARDSCAPE)
	var bare := Exporter.plan_sheet(document, {"sheet": "A3", "show_border": false})
	var bordered := Exporter.plan_sheet(document, {"sheet": "A3"})
	assert(bordered["scale"] > bare["scale"])
	# Whatever scale comes out, the drawing fits the area the block leaves.
	var content: Rect2 = bordered["content_pt"]
	var drawn: Vector2 = bordered["drawing_pt"]
	assert(drawn.x <= content.size.x + 0.01)
	assert(drawn.y <= content.size.y + 0.01)


## A caller can override the scale. If the drawing then does not fit, it is set
## against the top of the content area so what it overruns is clear paper rather
## than the title block.
func test_an_over_large_drawing_is_kept_off_the_title_block() -> void:
	var document = Document.new()
	document.add(Entity.make_rectangle(Vector2(60, 55), Vector2(120, 110)), LayerSet.NEW_HARDSCAPE)
	var plan := Exporter.plan_sheet(document, {"sheet": "A3", "scale": 100.0})
	var content: Rect2 = plan["content_pt"]
	assert(plan["drawing_pt"].y > content.size.y)
	# Placed from the top, so it grows downwards into the drawing area only.
	assert(absf(Vector2(plan["origin_pt"]).y - content.position.y) < 0.01)
	assert(_title_block(plan).position.y >= content.end.y)


func test_a_borderless_plot_has_no_title_block() -> void:
	var text := Exporter.export_pdf(_document(), {"sheet": "A3", "show_border": false}) \
		.get_string_from_utf8()
	assert(not text.contains("(PROJECT) Tj"))
	assert(not text.contains("(SCALE) Tj"))


## The drawing is centred in what is left above the block, so the two cannot
## collide however large the design is.
func test_the_drawing_is_centred_clear_of_the_title_block() -> void:
	var plan := Exporter.plan_sheet(_document(), {"sheet": "A3"})
	var area: Rect2 = plan["printable_pt"]
	var content: Rect2 = plan["content_pt"]
	assert(content.size.y < area.size.y)
	assert(content.position.y == area.position.y)

	var extent: Rect2 = plan["extent"]
	var centre := (
		Exporter.model_to_paper(extent.position, plan)
		+ Exporter.model_to_paper(extent.end, plan)
	) * 0.5
	assert(centre.distance_to(content.get_center()) < 0.01)
	assert(_title_block(plan).position.y > content.end.y)


func test_the_north_point_carries_its_letter() -> void:
	var text := Exporter.export_pdf(_document(), {"sheet": "A3"}).get_string_from_utf8()
	assert(text.contains("(N) Tj"))


## The scale bar is the honest part of the furniture: a length of paper that can
## be checked against a ruler. It is drawn at the length the scale law gives for a
## round number of metres.
func test_the_scale_bar_is_drawn_at_its_true_length() -> void:
	var plan := Exporter.plan_sheet(_document(), {"sheet": "A3"})
	var text := Exporter.export_pdf(_document(), {"sheet": "A3"}).get_string_from_utf8()
	var strip := (
		Exporter.TITLE_BLOCK_WIDTH_MM - Exporter.NORTH_CELL_MM
	) * Exporter.POINTS_PER_MM
	var choice := PlotScale.scale_bar_length(plan["pt_per_metre"], strip * 0.62, false)
	var bar := float(choice["metres"]) * float(plan["pt_per_metre"])
	var step := bar / float(Exporter.SCALE_BAR_DIVISIONS)

	var found := false
	for rect in _rectangles(text):
		if absf(rect.size.x - bar) < 0.01:
			found = true
	assert(found)
	# Every division labelled, and the far end carrying the unit.
	assert(text.contains("(%s) Tj" % Exporter.scale_bar_label(0.0, step)))
	assert(text.contains("(%s m) Tj" % Exporter.scale_bar_label(float(choice["label_value"]), step)))


## Rounding a half-metre division to whole metres would put "0 1 1 2" under a
## two-metre bar, which is not a scale anything can be read off.
func test_a_scale_bar_division_is_labelled_to_its_own_precision() -> void:
	assert(Exporter.scale_bar_label(0.0, 0.5) == "0.0")
	assert(Exporter.scale_bar_label(1.5, 0.5) == "1.5")
	assert(Exporter.scale_bar_label(2.0, 0.5) == "2.0")
	assert(Exporter.scale_bar_label(5.0, 5.0) == "5")
	assert(Exporter.scale_bar_label(0.0, 5.0) == "0")


func test_the_scale_bar_switches_to_feet() -> void:
	var plan := Exporter.plan_sheet(_document(), {"sheet": "A3", "imperial": true})
	var text := Exporter.export_pdf(_document(), {"sheet": "A3", "imperial": true}) \
		.get_string_from_utf8()
	var strip := (
		Exporter.TITLE_BLOCK_WIDTH_MM - Exporter.NORTH_CELL_MM
	) * Exporter.POINTS_PER_MM
	var choice := PlotScale.scale_bar_length(plan["pt_per_metre"], strip * 0.62, true)
	var step := float(choice["metres"]) * float(plan["pt_per_metre"]) \
		/ float(Exporter.SCALE_BAR_DIVISIONS)
	assert(text.contains("(%s ft) Tj" % Exporter.scale_bar_label(float(choice["label_value"]), step)))


# --- dimensions on the sheet --------------------------------------------------------


func _dimension_document():
	var document = Document.new()
	document.add(
		Entity.make_dimension(Vector2(0, 0), Vector2(10, 0), 1.0), LayerSet.DIMENSION
	)
	return document


func test_a_dimension_plots_its_measurement() -> void:
	var document = _dimension_document()
	var text := Exporter.export_pdf(document, {"sheet": "A3", "scale": 100.0}) \
		.get_string_from_utf8()
	# Written in the document's own units, so the sheet and the plan agree about
	# the measurement rather than each formatting it their own way.
	assert(text.contains("(%s) Tj" % document.units.format_length(10.0)))


## The arrowheads have to land where the shared layout says, or the sheet and the
## plan would disagree about the same dimension.
func test_a_dimension_plots_arrowheads_where_the_layout_puts_them() -> void:
	var document = _dimension_document()
	var entity = document.entities()[0]
	var plan := Exporter.plan_sheet(document, {"sheet": "A3", "scale": 100.0})
	var text := Exporter.export_pdf(document, {"sheet": "A3", "scale": 100.0}) \
		.get_string_from_utf8()
	var points := _moved_points(text)
	var layout: Dictionary = Dimension.layout(entity, 100.0)

	# Both ends of the dimension line, then the three corners of each arrowhead.
	for end: Dictionary in layout["arrows"]:
		var triangle := Dimension.arrow_triangle(
			end["tip"], end["direction"], end["size"]
		)
		for corner in triangle:
			assert(_has_point(points, Exporter.model_to_paper(corner, plan)))
	# And the extension lines, which start off the measured point, not on it.
	var first: PackedVector2Array = layout["lines"][0]
	assert(_has_point(points, Exporter.model_to_paper(first[0], plan)))
	assert(not _has_point(points, Exporter.model_to_paper(Vector2(0, 0), plan)))


## A dimension up the sheet has its value along the line, which needs a rotated
## text matrix rather than a plain offset.
func test_a_vertical_dimension_rotates_its_text() -> void:
	var document = Document.new()
	document.add(
		Entity.make_dimension(Vector2(0, 0), Vector2(0, 6), 2.0), LayerSet.DIMENSION
	)
	var text := Exporter.export_pdf(document, {"sheet": "A3", "scale": 100.0}) \
		.get_string_from_utf8()
	assert(text.contains("(%s) Tj" % document.units.format_length(6.0)))
	assert(text.contains(" Tm "))


func test_a_horizontal_dimension_needs_no_rotation() -> void:
	var text := Exporter.export_pdf(_dimension_document(), {"sheet": "A3", "scale": 100.0}) \
		.get_string_from_utf8()
	assert(not text.contains(" Tm "))


## A dimension is set out from the points it measures, so it draws outside the box
## those points define. The sheet has to be laid out around what is drawn, or a
## dimension runs off the border or under the title block - a defect that only
## shows up once it is on paper.
func test_the_plot_extent_includes_a_dimensions_set_out_line() -> void:
	var document = Document.new()
	document.add(Entity.make_line(Vector2(0, 0), Vector2(10, 0)), LayerSet.NEW_HARDSCAPE)
	var measured: Rect2 = Exporter.plan_sheet(document, {"sheet": "A3"})["extent"]
	document.add(
		Entity.make_dimension(Vector2(0, 0), Vector2(10, 0), -3.0), LayerSet.DIMENSION
	)
	var laid_out: Rect2 = Exporter.plan_sheet(document, {"sheet": "A3"})["extent"]
	# The dimension line sits three metres north of the wall it measures. The
	# tolerance is loose because the extent is measured with the paper-sized
	# overshoots taken at 1:1, where an extension line runs 1.5 mm past its line.
	assert(absf(laid_out.position.y - (measured.position.y - 3.0)) < 0.01)
	assert(is_equal_approx(laid_out.size.x, measured.size.x))


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
	# An empty drawing still gets its block: the sheet has to be identifiable even
	# when there is nothing on it yet.
	assert(text.contains("(PROJECT) Tj"))
	assert(text.contains("(SCALE) Tj"))


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