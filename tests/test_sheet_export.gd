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
const DimensionStyle := preload("res://scripts/draft/dimension_style.gd")
const SampleSheets := preload("res://tools/sample_sheets.gd")


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
	# The block lies along the foot of the sheet in its bottom-right corner. Paper y
	# runs up the page, so the foot is the smaller y.
	return Rect2(Vector2(area.end.x - size.x, area.position.y), size)


func test_the_title_block_lands_in_the_corner_of_the_border() -> void:
	var plan := Exporter.plan_sheet(_document(), {"sheet": "A3"})
	var text := Exporter.export_pdf(_document(), {"sheet": "A3"}).get_string_from_utf8()
	var block := _title_block(plan)
	var area: Rect2 = plan["printable_pt"]
	# Flush into the corner, so it reads as part of the border rather than as
	# something floating inside the drawing. The corner is the bottom-right one:
	# the larger x and the smaller y, because paper y runs up the page.
	assert(block.end.x == area.end.x)
	assert(block.position.y == area.position.y)
	assert(block.position.x > area.get_center().x)
	assert(block.end.y < area.get_center().y)
	var found := false
	for rect in _rectangles(text):
		if rect.position.distance_to(block.position) < 0.01 \
				and rect.size.distance_to(block.size) < 0.01:
			found = true
	assert(found)


## Every string the plot draws, with the baseline it was drawn at and the size it
## was drawn at. A test that only asks whether a caption is somewhere in the file
## cannot tell a sheet that reads from a sheet that has every word in the wrong
## place, so the furniture tests below ask where.
func _drawn_text(text: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for line in text.split("\n"):
		var drawn := line.strip_edges()
		if not drawn.begins_with("BT /F1 ") or not drawn.ends_with(") Tj ET"):
			continue
		var open_paren := drawn.find("(")
		if open_paren < 0:
			continue
		var head := drawn.substr(0, open_paren).strip_edges().split(" ", false)
		# BT /F1 <size> Tf <x> <y> Td (
		if head.size() != 7:
			continue
		out.append({
			"text": drawn.substr(open_paren + 1, drawn.length() - 7 - open_paren - 1),
			"at": Vector2(float(head[4]), float(head[5])),
			"size": float(head[2]),
		})
	return out


## Which band of a table a baseline falls in, or -1 for none of them.
func _band_of(y: float, bands: Array[Vector2]) -> int:
	for index in bands.size():
		if y > bands[index].x - 0.01 and y <= bands[index].y + 0.01:
			return index
	return -1


## The title block reads top to bottom: the project, the drawing, the numbering, and
## the foot. Each field's caption and its value belong to the same band and the bands
## are not shared, which is what catches a field drawn into the wrong row - the
## mistake that quietly left the drawing's own row empty and put DRAWING in the
## numbering row beside SCALE.
func test_the_title_block_reads_one_row_at_a_time() -> void:
	var options := {"sheet": "A3", "project": "Riverbend", "drawing": "Planting Plan"}
	var plan := Exporter.plan_sheet(_document(), options)
	var block := _title_block(plan)
	var row := Exporter.TITLE_BLOCK_ROW_MM * Exporter.POINTS_PER_MM
	var foot := block.end.y - row * 3.0
	var bands: Array[Vector2] = [
		Vector2(foot + row * 2.0, block.end.y),
		Vector2(foot + row, foot + row * 2.0),
		Vector2(foot, foot + row),
		Vector2(block.position.y, foot),
	]

	var text := Exporter.export_pdf(_document(), options).get_string_from_utf8()
	var where := {}
	for entry: Dictionary in _drawn_text(text):
		var at: Vector2 = entry["at"]
		if at.x < block.position.x - 0.01 or at.x > block.end.x + 0.01:
			continue
		var band := _band_of(at.y, bands)
		if band >= 0:
			where[String(entry["text"])] = band

	assert(where.get("PROJECT", -1) == 0)
	assert(where.get("Riverbend", -1) == 0)
	assert(where.get("DRAWING", -1) == 1)
	assert(where.get("Planting Plan", -1) == 1)
	for numbered in ["SCALE", "SHEET", "DATE", "REV"]:
		assert(where.get(numbered, -1) == 2)
	# The foot carries the scale bar and the north point, and nothing else.
	assert(where.get("N", -1) == 3)
	var bars := 0
	for rect in _rectangles(text):
		if rect.size.x >= block.size.x - 1.0 or rect.size.x <= 0.0:
			# The block's own outline spans all four rows, so it is not a row's.
			continue
		if rect.position.x < block.position.x - 0.01 or rect.end.x > block.end.x + 0.01:
			continue
		if rect.position.y < block.position.y - 0.01 or rect.end.y > block.end.y + 0.01:
			continue
		assert(_band_of(rect.position.y, bands) == 3)
		bars += 1
	# Two filled divisions and the bar drawn round them.
	assert(bars == 3)


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
## against the foot of the content area so what it overruns is clear paper rather
## than the title block.
func test_an_over_large_drawing_is_kept_off_the_title_block() -> void:
	var document = Document.new()
	document.add(Entity.make_rectangle(Vector2(60, 55), Vector2(120, 110)), LayerSet.NEW_HARDSCAPE)
	var plan := Exporter.plan_sheet(document, {"sheet": "A3", "scale": 100.0})
	var content: Rect2 = plan["content_pt"]
	var drawn: Vector2 = plan["drawing_pt"]
	assert(drawn.y > content.size.y)
	# Set against the foot of the area, so what it overruns is clear paper above
	# and never the title block below. The placement is the drawing's centre, so its
	# foot is half a height below it - and paper y runs up the page, so "below" is
	# the smaller y.
	var centre: Vector2 = plan["origin_pt"]
	assert(absf(centre.y - drawn.y * 0.5 - content.position.y) < 0.01)
	assert(_title_block(plan).end.y < centre.y - drawn.y * 0.5)


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
	# The block's strip comes off the foot of the sheet and leaves the top of the
	# border where it was: paper y runs up the page, so the content's foot is the
	# larger y and the strip is charged there.
	assert(content.position.y > area.position.y)
	assert(content.end.y == area.end.y)

	var extent: Rect2 = plan["extent"]
	var centre := (
		Exporter.model_to_paper(extent.position, plan)
		+ Exporter.model_to_paper(extent.end, plan)
	) * 0.5
	assert(centre.distance_to(content.get_center()) < 0.01)
	assert(_title_block(plan).end.y < content.position.y)


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
		- Exporter.SCALE_BAR_INSET_MM * 2.0
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
		- Exporter.SCALE_BAR_INSET_MM * 2.0
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
	# The drawing's own precision, which at 1:100 is hundredths of a metre: a
	# dimension on a sheet can only be read as finely as it can be drawn.
	assert(text.contains("(10.00 m) Tj"))


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
	for end: Dictionary in layout["marks"]:
		var triangle := Dimension.arrow_triangle(
			end["tip"], end["direction"], end["size"], end["width_ratio"]
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
	assert(text.contains("(6.00 m) Tj"))
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


# --- the layer key ------------------------------------------------------------------


## Keyed by layer and in the layer set's own order, so the key reads the way the
## layers are named rather than in whatever order the entities went in.
func test_the_key_lists_the_layers_that_plot() -> void:
	var rows := Exporter.legend_rows(_document(), null)
	var names: Array = []
	var counts: Array = []
	for row in rows:
		names.append(String(row["name"]))
		counts.append(int(row["count"]))
	assert(names == ["300-NEW-HARD", "401-NEW-PLANT", "710-TEXT"])
	assert(counts == [1, 1, 1])


func test_a_layer_with_nothing_on_it_is_absent_from_the_key() -> void:
	var document = Document.new()
	document.add(Entity.make_line(Vector2(0, 0), Vector2(10, 0)), LayerSet.LIGHTING)
	var rows := Exporter.legend_rows(document, null)
	assert(rows.size() == 1)
	assert(String(rows[0]["name"]) == "501-LIGHTING")


## A layer switched off for plotting is absent from the key rather than listed
## with nothing against it: the key describes the sheet, not the layers.
func test_a_layer_switched_off_plots_and_leaves_the_key() -> void:
	var document = Document.new()
	document.layers.get_layer(LayerSet.NEW_HARDSCAPE).plots = false
	document.add(Entity.make_line(Vector2(0, 0), Vector2(10, 0)), LayerSet.NEW_HARDSCAPE)
	assert(Exporter.legend_rows(document, null).is_empty())


func test_the_key_counts_each_layer() -> void:
	var document = Document.new()
	for index in 3:
		document.add(
			Entity.make_circle(Vector2(index * 3, 0), 1.0), LayerSet.NEW_PLANTING
		)
	document.add(Entity.make_line(Vector2(0, 0), Vector2(1, 1)), LayerSet.NEW_HARDSCAPE)
	var rows := Exporter.legend_rows(document, null)
	assert(rows.size() == 2)
	assert(int(rows[0]["count"]) == 1)
	assert(int(rows[1]["count"]) == 3)


## The sample is drawn in the layer's plotted pen - its plotted colour, weight and
## linetype - because a key whose line does not look like the drawing's is a key
## that explains nothing.
func test_the_key_draws_its_sample_in_the_layer_pen() -> void:
	var document = Document.new()
	document.add(Entity.make_line(Vector2(0, 0), Vector2(10, 0)), LayerSet.NEW_HARDSCAPE)
	var table = PenStyle.default_table()
	var options := {"sheet": "A3", "legend": true, "pen_table": table}
	var plan := Exporter.plan_sheet(document, options)
	var text := Exporter.export_pdf(document, options).get_string_from_utf8()

	var rect: Rect2 = plan["legend_pt"]
	var row := Exporter.LEGEND_ROW_MM * Exporter.POINTS_PER_MM
	# The key is read downwards from its top edge, so the first row's sample sits a
	# row below the rule under the title.
	var header := rect.end.y - Exporter.LEGEND_HEADER_MM * Exporter.POINTS_PER_MM
	var baseline := (
		header - row + Exporter.LEGEND_PAD_MM * Exporter.POINTS_PER_MM * 0.5
	)
	var sample_y := baseline + row * 0.35
	assert(text.contains("%s %s m" % [
		String.num(rect.position.x + Exporter.LEGEND_PAD_MM * Exporter.POINTS_PER_MM, 4),
		String.num(sample_y, 4),
	]))

	var style = Exporter.layer_pen(document.layers.get_layer(LayerSet.NEW_HARDSCAPE), table)
	assert(text.contains("%s %s %s RG" % [
		String.num(style.plot_colour.r, 4), String.num(style.plot_colour.g, 4),
		String.num(style.plot_colour.b, 4),
	]))
	assert(text.contains("(KEY) Tj"))
	assert(text.contains("(300-NEW-HARD) Tj"))
	assert(text.contains("(1) Tj"))


func test_without_a_key_the_sheet_has_none() -> void:
	var text := Exporter.export_pdf(_document(), {"sheet": "A3"}).get_string_from_utf8()
	assert(not text.contains("(KEY) Tj"))
	assert(not text.contains("(300-NEW-HARD) Tj"))


func test_the_key_can_be_retitled() -> void:
	var text := Exporter.export_pdf(
		_document(), {"sheet": "A3", "legend": true, "legend_title": "LEGEND"}
	).get_string_from_utf8()
	assert(text.contains("(LEGEND) Tj"))


## The key sits in the top-left corner of the border and grows downwards only, so
## it can never reach the title block however many layers the drawing uses.
func test_the_key_stays_in_its_corner() -> void:
	var plan := Exporter.plan_sheet(_document(), {"sheet": "A3", "legend": true})
	var area: Rect2 = plan["printable_pt"]
	var rect: Rect2 = plan["legend_pt"]
	# Paper y runs up the page, so the top-left corner is the smaller x and the
	# larger y, and "grows downwards" means the key's own foot is its smaller y.
	assert(rect.position.x == area.position.x)
	assert(rect.end.y == area.end.y)
	assert(rect.end.x < area.end.x)
	assert(rect.position.y > _title_block(plan).end.y)


## The key claims a column, so the drawing is centred in what is left and the
## scale is chosen against that: the width gives way, the height does not.
func test_the_key_narrows_the_area_the_scale_is_chosen_for() -> void:
	var document = _document()
	var without := Exporter.plan_sheet(document, {"sheet": "A3"})
	var with_key := Exporter.plan_sheet(document, {"sheet": "A3", "legend": true})
	var bare: Rect2 = without["content_pt"]
	var claimed: Rect2 = with_key["content_pt"]
	assert(claimed.size.x < bare.size.x)
	assert(is_equal_approx(claimed.size.y, bare.size.y))
	var drawn: Vector2 = with_key["drawing_pt"]
	assert(drawn.x <= claimed.size.x + 0.01)
	assert(drawn.y <= claimed.size.y + 0.01)


# --- the viewport -------------------------------------------------------------------


## A drawing 10 m wide and 2 m deep, which is the shape that makes a turned
## viewport's footprint visibly different from its sides.
func _wide_document():
	var document = Document.new()
	document.add(Entity.make_rectangle(Vector2(5, 1), Vector2(10, 2)), LayerSet.NEW_HARDSCAPE)
	return document


func _wide_options(extra: Dictionary = {}) -> Dictionary:
	var options := {"sheet": "A3", "scale": 100.0}
	for key in extra:
		options[key] = extra[key]
	return options


## A viewport's own scale is a lock, which is the only reason for setting one.
func test_a_viewport_locks_the_scale() -> void:
	var locked := Exporter.plan_sheet(
		_wide_document(), {"viewport": {"scale": 200.0}}
	)
	assert(is_equal_approx(locked["scale"], 200.0))
	var suggested := Exporter.plan_sheet(_wide_document(), {})
	assert(not is_equal_approx(suggested["scale"], 200.0))


func test_a_viewport_frames_the_drawing_where_it_says() -> void:
	var frame := Rect2(
		Vector2(100.0, 200.0) * Exporter.POINTS_PER_MM,
		Vector2(120.0, 80.0) * Exporter.POINTS_PER_MM
	)
	var plan := Exporter.plan_sheet(_wide_document(), _wide_options({
		"viewport": {"origin_mm": Vector2(100.0, 200.0), "size_mm": Vector2(120.0, 80.0)},
	}))
	var claimed: Rect2 = plan["viewport_pt"]
	assert(claimed.position.is_equal_approx(frame.position))
	assert(claimed.size.is_equal_approx(frame.size))
	# And the drawing is centred in its frame.
	assert(Vector2(plan["origin_pt"]).distance_to(frame.get_center()) < 0.01)


## A rotated rectangle covers more of the sheet than its sides suggest, and it is
## that box which has to fit.
func test_a_turned_drawing_takes_more_of_the_sheet() -> void:
	var straight := Exporter.plan_sheet(_wide_document(), _wide_options())
	var turned := Exporter.plan_sheet(_wide_document(), _wide_options({
		"viewport": {"rotation_degrees": 90.0},
	}))
	assert(turned["drawing_pt"].x < straight["drawing_pt"].x)
	assert(turned["drawing_pt"].y > straight["drawing_pt"].y)


## Turning is a rotation of the sheet, not a re-scaling of it: a known length
## still measures what it measured. This is the scale law's own conformance test
## run through a turned viewport.
func test_a_known_length_still_measures_the_same_when_turned() -> void:
	var document = Document.new()
	document.add(Entity.make_line(Vector2(0, 0), Vector2(10, 0)), LayerSet.NEW_HARDSCAPE)
	var plan := Exporter.plan_sheet(document, _wide_options({
		"viewport": {"rotation_degrees": 90.0},
	}))
	var from := Exporter.model_to_paper(Vector2(0, 0), plan)
	var to := Exporter.model_to_paper(Vector2(10, 0), plan)
	assert(absf(from.distance_to(to) - 100.0 * Exporter.POINTS_PER_MM) < 0.001)
	# East now runs up the page.
	assert(absf(to.x - from.x) < 0.001)
	assert(to.y > from.y)


## An arrow still pointing up the page on a turned drawing would be a lie about
## it, so north turns with the viewport.
func test_north_turns_with_the_viewport() -> void:
	assert(Exporter.north_direction(Exporter.plan_sheet(_wide_document(), {})) \
		.is_equal_approx(Vector2(0, 1)))
	assert(Exporter.north_direction(Exporter.plan_sheet(_wide_document(), _wide_options({
		"viewport": {"rotation_degrees": 90.0},
	}))).is_equal_approx(Vector2(-1, 0)))
	assert(Exporter.north_direction(Exporter.plan_sheet(_wide_document(), _wide_options({
		"viewport": {"rotation_degrees": 180.0},
	}))).is_equal_approx(Vector2(0, -1)))


## The scale is chosen for what the drawing will take on the paper, which a turned
## viewport makes bigger. Turning a drawing costs it a scale step rather than
## leaving the sheet to hand off the border with an overflow flag nobody asked for.
func test_a_turned_viewport_is_given_a_scale_that_accounts_for_the_turn() -> void:
	var document = Document.new()
	document.add(
		Entity.make_rectangle(Vector2(22.5, 22.5), Vector2(45, 45)), LayerSet.NEW_HARDSCAPE
	)
	var straight := Exporter.plan_sheet(document, {"sheet": "A3"})
	var turned := Exporter.plan_sheet(
		document, {"sheet": "A3", "viewport": {"rotation_degrees": 45.0}}
	)
	# A square turned 45 degrees needs half again as much room, which is a step on
	# the scale ladder.
	assert(straight["scale"] < turned["scale"])
	var content: Rect2 = turned["content_pt"]
	var drawn: Vector2 = turned["drawing_pt"]
	assert(drawn.x <= content.size.x + 0.01)
	assert(drawn.y <= content.size.y + 0.01)
	assert(not turned["overflow"])


## A drawing too big for its viewport is reported rather than silently cropped or
## silently re-scaled: the caller asked for that scale and that frame.
func test_a_drawing_that_does_not_fit_its_viewport_says_so() -> void:
	var tight := Exporter.plan_sheet(_wide_document(), _wide_options({
		"viewport": {"origin_mm": Vector2(50, 50), "size_mm": Vector2(60, 40)},
	}))
	assert(tight["overflow"])
	var roomy := Exporter.plan_sheet(_wide_document(), _wide_options({
		"viewport": {"origin_mm": Vector2(50, 50), "size_mm": Vector2(400, 300)},
	}))
	assert(not roomy["overflow"])
	assert(not Exporter.plan_sheet(_wide_document(), _wide_options())["overflow"])


## Turning the viewport turns the labels with the drawing, so a dimension still
## reads along the line it measures rather than across it.
func test_a_dimension_reads_along_its_line_when_the_viewport_is_turned() -> void:
	var document = Document.new()
	document.add(
		Entity.make_dimension(Vector2(0, 0), Vector2(10, 0), 1.0), LayerSet.DIMENSION
	)
	var options := _wide_options({"viewport": {"rotation_degrees": 90.0}})
	var plan := Exporter.plan_sheet(document, options)
	var text := Exporter.export_pdf(document, options).get_string_from_utf8()
	# The dimension runs up the page, so its text carries a rotation.
	assert(text.contains(" Tm "))
	assert(text.contains("(10.00 m) Tj"))
	# And the measurement still measures.
	var from := Exporter.model_to_paper(Vector2(0, 0), plan)
	var to := Exporter.model_to_paper(Vector2(10, 0), plan)
	assert(absf(from.distance_to(to) - 100.0 * Exporter.POINTS_PER_MM) < 0.001)


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


func test_a_dimension_plots_continuous_whatever_pen_its_layer_resolves_to() -> void:
	# The premise, so this test cannot pass by the pen happening to be solid: the
	# dimensions layer shares the *magenta* slot with the setback/easement layer, and the
	# magenta pen is dashed. That is exactly right for a setback line, which is what a
	# dashed pen is for, and wrong for a dimension.
	var pen_table = PenStyle.default_table()
	var layer = Document.new().layers.get_layer(LayerSet.DIMENSION)
	assert(layer != null)
	var pen: LineStyle = pen_table.resolve_for(Render.screen_colour(layer), LineStyle.new())
	assert(pen.linetype == &"dashed", "the dimensions pen is %s" % pen.linetype)
	# And the setback line, on the same slot, is the case that must keep it. Two single
	# entity sheets rather than one, because one stream with two dashed-or-not paths is
	# a test that guesses which path is which.
	var setback := Document.new()
	setback.add(
		Entity.make_line(Vector2(3, 0), Vector2(3, 12)), LayerSet.SETBACK_EASEMENT
	)
	var setback_text := Exporter.export_pdf(
		setback, {"show_border": false, "pen_table": pen_table}
	).get_string_from_utf8()
	assert(
		setback_text.contains("[17.0079 5.6693] 0 d"),
		"a setback line is exactly what the dashed pen is for"
	)

	# A dimension's own linework — its line, its extension lines and its leader — is
	# *generated* geometry rather than something a person drew, and a dashed dimension
	# line is not a drafting standard: it is a mistake that reaches a client.
	var entity = Entity.make_dimension(Vector2(0, 0), Vector2(10, 0), 1.0)
	assert(entity.style == null, "the test must not be an entity override")
	var dimensions := Document.new()
	dimensions.add(entity, LayerSet.DIMENSION)
	var text := Exporter.export_pdf(
		dimensions, {"show_border": false, "pen_table": pen_table}
	).get_string_from_utf8()
	assert(
		not text.contains("[17.0079"),
		"a dimension is still plotting with the dashed pen"
	)


func test_the_screen_draws_a_dimension_continuous_too() -> void:
	# The same rule on the other side of the export, so the plan and the sheet cannot
	# disagree about what a dimension looks like: both read this style.
	var document = Document.new()
	var entity = Entity.make_dimension(Vector2(0, 0), Vector2(10, 0), 1.0)
	document.add(entity, LayerSet.DIMENSION)
	var layer = document.layers.get_layer(LayerSet.DIMENSION)
	var layout: Dictionary = Render.layout(entity, layer, 100.0)
	var style: LineStyle = layout["style"]
	assert(style.linetype == &"continuous")
	# And an ordinary entity is left alone, so the rule is about dimensions and not
	# about switching every dash off.
	var line = Entity.make_line(Vector2(0, 0), Vector2(10, 0))
	var dashed := LineStyle.new()
	dashed.linetype = &"dashed"
	line.style = dashed
	var line_layout: Dictionary = Render.layout(line, layer, 100.0)
	assert((line_layout["style"] as LineStyle).linetype == &"dashed")


# --- the sample sheets -----------------------------------------------------------------


## The samples are the only place several dimensions, a layer key and the furniture are
## all on one page at once, and they are what a person looks at to judge the plotting.
## They live in the repository so that a change to the exporter or to the pen table cannot
## quietly leave them describing a sheet the program no longer draws — and this is the
## test that would notice.
func test_the_sample_sheets_say_what_they_are_supposed_to() -> void:
	var plan = SampleSheets.make_document()
	var a3 := Exporter.export_pdf(plan, SampleSheets.sheet_options()).get_string_from_utf8()
	for phrase in [
		"20.00 m", "12.00 m", "6.00 m", "4.72 m", "R1.50 m",
		"PATIO \\(NEW\\)", "1:100", "A3", "Riverbend Residence",
		"Planting & Hardscape Plan", "020-SETBACK-EASE", "710-TEXT",
	]:
		assert(a3.contains(phrase), "the sample sheet does not say %s" % phrase)
	# The turned sheet is the same design on a bigger page, so the pair covers the
	# viewport, the scale it is given, and the other dimension standard.
	var turned = SampleSheets.make_document()
	turned.dimension_style = DimensionStyle.engineering()
	var a2 := Exporter.export_pdf(turned, SampleSheets.turned_options()).get_string_from_utf8()
	assert(a2.contains("A2"), "the turned sheet should be on A2")
	assert(a2.contains("1:100"))
	assert(a2.contains("Riverbend Residence"))
	# Two sheets, two page sizes: if the turned options stopped reaching the page box the
	# pair would be one sheet written twice.
	assert(a3 != a2)


func test_the_sample_sheet_keeps_the_dashed_pen_and_loses_it_on_dimensions() -> void:
	# Both are on the sample sheet on purpose: the magenta slot the dimension layer shares
	# with the setback layer is the dashed pen, so the sheet shows a dashed line and five
	# dimensions that are not, and a reader can see the rule working.
	var pen_table = PenStyle.default_table()
	var plan = SampleSheets.make_document()
	var text := Exporter.export_pdf(plan, SampleSheets.sheet_options()).get_string_from_utf8()
	# The setback line, the key's sample of it, and the key's sample of the pen the
	# dimension layer *resolves to*. Three, and the count is the assertion: a fourth would
	# mean a dimension had gone back to plotting dashed.
	assert(
		text.count("[17.0079 5.6693] 0 d") == 3,
		"expected the setback line and two key samples to be dashed, got %d"
		% text.count("[17.0079 5.6693] 0 d")
	)
	assert(pen_table.enabled)


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


# --- the planting schedule ----------------------------------------------------------


## The rows `PlantPlacement.schedule()` hands a sheet: two species and, last, the line that counts
## the standing plants the catalogue cannot name.
func _schedule() -> Array:
	return [
		{
			"id": &"buxus-sempervirens", "count": 12,
			"botanical_name": "Buxus sempervirens", "common_name": "Common boxwood",
			"cultivar": "", "category_name": "Shrub", "spread_cm": 90, "height_cm": 120,
		},
		{
			"id": &"acer-rubrum-autumn-blaze", "count": 3,
			"botanical_name": "Acer rubrum", "common_name": "Red maple",
			"cultivar": "Autumn Blaze", "category_name": "Tree", "spread_cm": 900,
			"height_cm": 1500,
		},
		{
			"id": &"", "count": 30, "botanical_name": "no species recorded", "common_name": "",
			"cultivar": "", "category_name": "", "spread_cm": 0, "height_cm": 0,
		},
	]


func _many_species(count: int) -> Array:
	var rows: Array = []
	for index in count:
		rows.append({
			"id": StringName("species-%03d" % index), "count": index + 1,
			"botanical_name": "Botanica %03d" % index, "common_name": "Common %03d" % index,
			"cultivar": "",
		})
	return rows


func test_the_schedule_lists_the_plants_and_how_many_of_each() -> void:
	var options := {"sheet": "A3", "schedule": _schedule()}
	var plan := Exporter.plan_sheet(_document(), options)
	var text := Exporter.export_pdf(_document(), options).get_string_from_utf8()
	assert(text.contains("(PLANTING SCHEDULE) Tj"))
	# The count in a column of its own and the name in the library's own words.
	assert(text.contains("(12) Tj"))
	assert(text.contains("(Buxus sempervirens - Common boxwood) Tj"))
	assert(text.contains("(3) Tj"))
	assert(text.contains("(Acer rubrum 'Autumn Blaze' - Red maple) Tj"))
	assert((plan["schedule"] as Array).size() == 3)


## The one line a planting schedule must not hide: the standing plants the catalogue cannot name.
func test_a_plant_the_catalogue_cannot_name_is_named_rather_than_dropped() -> void:
	var options := {"sheet": "A3", "schedule": _schedule()}
	var text := Exporter.export_pdf(_document(), options).get_string_from_utf8()
	assert(text.contains("(no species recorded) Tj"))
	assert(text.contains("(30) Tj"))


func test_without_a_schedule_the_sheet_has_none() -> void:
	var plan := Exporter.plan_sheet(_document(), {"sheet": "A3"})
	var text := Exporter.export_pdf(_document(), {"sheet": "A3"}).get_string_from_utf8()
	assert(not text.contains("PLANTING SCHEDULE"))
	assert((plan["schedule_pt"] as Rect2).size == Vector2.ZERO)
	assert((plan["schedule"] as Array).is_empty())


func test_a_schedule_needs_the_border_it_sits_in() -> void:
	var options := {"show_border": false, "schedule": _schedule()}
	var plan := Exporter.plan_sheet(_document(), options)
	var text := Exporter.export_pdf(_document(), options).get_string_from_utf8()
	assert((plan["schedule_pt"] as Rect2).size == Vector2.ZERO)
	assert(not text.contains("PLANTING SCHEDULE"))


## The schedule mirrors the key: against the right edge of the border, hanging from the top edge and
## growing downwards only, so it can never reach the title block however long the planting list is.
func test_the_schedule_sits_against_the_right_edge_out_of_the_title_block() -> void:
	var plan := Exporter.plan_sheet(_document(), {"sheet": "A3", "schedule": _schedule()})
	var area: Rect2 = plan["printable_pt"]
	var rect: Rect2 = plan["schedule_pt"]
	assert(is_equal_approx(rect.end.x, area.end.x))
	assert(is_equal_approx(rect.end.y, area.end.y))
	assert(rect.position.x > area.position.x)
	assert(rect.position.y > _title_block(plan).end.y)


## Both columns are reserved as full-length bands, because the drawing is placed by its centre and
## a centre that ignored them would put the drawing under them.
func test_the_schedule_and_the_key_claim_a_column_each() -> void:
	var document = _document()
	var bare: Rect2 = Exporter.plan_sheet(document, {"sheet": "A3"})["content_pt"]
	var keyed: Rect2 = Exporter.plan_sheet(document, {"sheet": "A3", "legend": true})["content_pt"]
	var scheduled: Rect2 = Exporter.plan_sheet(
		document, {"sheet": "A3", "schedule": _schedule()}
	)["content_pt"]
	var both := Exporter.plan_sheet(
		document, {"sheet": "A3", "legend": true, "schedule": _schedule()}
	)
	assert(scheduled.size.x < bare.size.x)
	assert((both["content_pt"] as Rect2).size.x < keyed.size.x)
	assert((both["content_pt"] as Rect2).size.x < scheduled.size.x)
	assert(is_equal_approx((both["content_pt"] as Rect2).size.y, bare.size.y))
	assert(float(both["drawing_pt"].x) <= (both["content_pt"] as Rect2).size.x + 0.01)


## The law of the column: what fits is listed, the lines that are not a species are kept whatever
## else is cut, and what was left out is counted rather than silently dropped.
func test_a_schedule_too_long_for_the_sheet_is_cut_and_says_how_much() -> void:
	var rows := _many_species(200)
	rows.append({
		"id": &"", "count": 30, "botanical_name": "no species recorded", "common_name": "",
	})
	var fitted := Exporter.fit_schedule(rows, 100.0)
	assert(fitted.size() < rows.size(), "the column cuts the list")
	# room = floor((100 - 8 - 2) / 4.6) = 19; one line is the unnamed plants and one says what the
	# cutting left out, so 17 species are listed.
	assert(fitted.size() == 19, "19 lines fit: %d" % fitted.size())
	var last: Dictionary = fitted[fitted.size() - 1]
	assert(String(last["botanical_name"]) == "no species recorded", "the unnamed plants are still there")
	var notice: Dictionary = fitted[fitted.size() - 2]
	assert(String(notice["name"]) == "183 species not shown", String(notice.get("name", "")))
	for row: Dictionary in fitted:
		assert(
			not StringName(row.get("id", &"")).is_empty() or String(row.get("name", "")).contains("not shown") \
				or String(row["botanical_name"]) == "no species recorded",
			"the lines that are not a species are the only ones without an id"
		)


func test_a_schedule_that_fits_is_left_alone() -> void:
	var rows := _schedule()
	assert(Exporter.fit_schedule(rows, 200.0) == rows)
	assert(
		Exporter.fit_schedule(rows, 1.0).is_empty(),
		"a column with no room for a table gets no table"
	)


func test_a_name_too_long_for_the_column_is_shortened_rather_than_run_on() -> void:
	var rows: Array = [{
		"id": &"long-name", "count": 1,
		"botanical_name": "Chamaecyparis lawsoniana 'Columnaris Glauca Variegata Elegantissima'",
		"common_name": "Lawson cypress under a name no column could carry", "cultivar": "",
	}]
	var text := Exporter.export_pdf(
		_document(), {"sheet": "A3", "schedule": rows}
	).get_string_from_utf8()
	assert(text.contains("...) Tj"), "the name ends in dots")
	assert(
		not text.contains("no column could carry"),
		"the whole name is not printed over the border"
	)
	assert(text.contains("(1) Tj"), "the count is still there")


## The schedule names a plant the way the library does, so the sheet and the browser cannot
## disagree about what a plant is called.
func test_a_schedule_row_reads_the_way_the_library_writes_it() -> void:
	assert(Exporter.schedule_row_text({
		"botanical_name": "Acer rubrum", "cultivar": "Autumn Blaze", "common_name": "Red maple",
	}) == "Acer rubrum 'Autumn Blaze' - Red maple")
	assert(Exporter.schedule_row_text({
		"botanical_name": "Thymus serpyllum", "cultivar": "", "common_name": "",
	}) == "Thymus serpyllum")
	assert(Exporter.schedule_row_text({
		"botanical_name": "no species recorded", "cultivar": "", "common_name": "",
	}) == "no species recorded")
	assert(Exporter.schedule_row_text({"name": "183 species not shown"}) == "183 species not shown")