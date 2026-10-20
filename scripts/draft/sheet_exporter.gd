class_name DraftSheetExporter
extends RefCounted
## Plots the document to a vector PDF sheet at an exact scale.
##
## This is the deliverable a designer hands to a client, so two things matter
## more than anything else. The first is that the drawing is genuinely true to
## scale: a 10 m wall at 1:100 must measure 100 mm on the paper, and the whole
## path from model metres to PDF points is arranged so that it does, by
## definition rather than by tuning. The second is that the conversion from
## paper millimetres to points is the only place a unit is chosen, so there is
## nowhere for a rounding error to hide.
##
## North is up. The model's y axis runs south, and PDF's y axis runs up, so the
## vertical axis is flipped as it is written. Getting that wrong produces a
## mirrored plan that still looks plausible, which is why it is one function with
## a test rather than arithmetic sprinkled through the emitter.

const PdfWriterScript := preload("res://scripts/draft/pdf_writer.gd")
const PlotScaleScript := preload("res://scripts/draft/plot_scale.gd")
const RenderScript := preload("res://scripts/draft/draft_render.gd")
const EntityScript := preload("res://scripts/draft/draft_entity.gd")
const LineStyleScript := preload("res://scripts/draft/line_style.gd")
const DimensionScript := preload("res://scripts/draft/dimension.gd")
const Geom := preload("res://scripts/draft/geom2d.gd")

const POINTS_PER_MM := 72.0 / 25.4

## The border sits this far inside the printable margin, in paper millimetres, so
## a printer that cannot quite reach the margin still prints a whole border.
const BORDER_INSET_MM := 2.0

## Paper text heights in millimetres. Text in a plot is authored to be read on
## paper, so it is a fixed set rather than something that scales with the drawing.
const LABEL_TEXT_MM := 2.5
const TITLE_TEXT_MM := 4.5
## The caption explaining a field is smaller than the field itself, because the
## value is the thing being read.
const CAPTION_TEXT_MM := LineStyleScript.TEXT_HEIGHTS[0]

const BORDER_WEIGHT_MM := 0.70
const HAIRLINE_WEIGHT_MM := 0.25

## The title block, in paper millimetres. Four rows: what the project is, what
## this sheet is, the numbering that identifies it, and the scale furniture.
const TITLE_BLOCK_WIDTH_MM := 170.0
const TITLE_BLOCK_HEIGHT_MM := 44.0
const TITLE_BLOCK_ROW_MM := 10.0
const TITLE_CELL_INSET_MM := 1.5
## Height of the strip reserved under the drawing so the block never lands on it.
const TITLE_BLOCK_CLEARANCE_MM := 3.0
## The square at the end of the last row holding the north point.
const NORTH_CELL_MM := 22.0
const SCALE_BAR_DIVISIONS := 4
const SCALE_BAR_HEIGHT_MM := 2.0

## Captions are grey so the authored values read as the content of the block.
const CAPTION_COLOUR := Color(0.35, 0.35, 0.35)


# --- layout -------------------------------------------------------------------------


## Work out the sheet without emitting anything, so a caller - or a test - can
## see the numbers the drawing will be plotted with.
static func plan_sheet(document, options: Dictionary = {}) -> Dictionary:
	var sheet_name: String = String(options.get("sheet", "A3"))
	var margin_mm: float = float(options.get("margin_mm", PlotScaleScript.DEFAULT_MARGIN_MM))
	var imperial: bool = bool(options.get("imperial", false))
	var show_border: bool = bool(options.get("show_border", true))
	var effective_margin := margin_mm + (BORDER_INSET_MM if show_border else 0.0)

	var sheet_mm: Vector2 = PlotScaleScript.sheet_size_mm(sheet_name)
	var sheet_pt := sheet_mm * POINTS_PER_MM
	var inset_pt := Vector2(effective_margin, effective_margin) * POINTS_PER_MM
	var drawing_area := Rect2(inset_pt, sheet_pt - inset_pt * 2.0)
	# The title block sits in the bottom-right corner, so the drawing is centred
	# in what is left above it rather than in the whole sheet: a drawing centred
	# over a block is a drawing with a block on top of it.
	var content := _content_area(drawing_area) if show_border else drawing_area

	var extent: Rect2 = _plot_extent(document)
	var scale: float = float(options.get("scale", 0.0))
	if scale <= 0.0:
		scale = PlotScaleScript.suggest(
			extent.size, sheet_name, effective_margin, imperial,
			Vector2(0.0, _reserved_mm(show_border))
		)["scale"]
	scale = maxf(scale, 0.0001)

	# Model metres to paper points. At 1:100 a metre is 10 mm, and a millimetre is
	# exactly 72/25.4 points, so a metre is 28.3465 points and a 10 m wall is
	# 283.465 points - which is 100 mm. This is the whole of the scale law.
	var pt_per_metre := 1000.0 / scale * POINTS_PER_MM
	var drawing_size := extent.size * pt_per_metre

	# A caller can override the scale, and then the drawing may not fit the area
	# the block leaves. It is then placed against the top of that area rather than
	# centred, so what it overruns is the clear space at the top of the sheet and
	# never the title block across the bottom.
	var origin := content.position + (content.size - drawing_size) * 0.5
	origin.y = content.position.y if drawing_size.y > content.size.y else origin.y

	return {
		"sheet": sheet_name,
		"sheet_mm": sheet_mm,
		"margin_mm": effective_margin,
		"imperial": imperial,
		"show_border": show_border,
		"printable_pt": drawing_area,
		"content_pt": content,
		"extent": extent,
		"scale": scale,
		"pt_per_metre": pt_per_metre,
		"origin_pt": origin,
		"drawing_pt": drawing_size,
		"empty": document.count() == 0,
	}


## The extent of what will actually be plotted.
##
## A dimension is set out from the points it measures rather than drawn between
## them, so it occupies space outside the box those points define. Laying the
## sheet out around that smaller box lets a dimension run off the border or under
## the title block, which is a defect that only shows up on paper.
##
## The plot scale is not known yet - it is chosen from this very extent - so the
## paper-sized parts of a dimension are measured at 1:1, where an arrowhead is a
## millimetre and a half. That is a millionth of the drawing and deliberately
## ignored: what matters here is the line the dimension is set out along.
static func _plot_extent(document) -> Rect2:
	var extent: Rect2 = document.bounds()
	for entity in document.plotting_entities():
		if entity.kind != EntityScript.Kind.DIMENSION:
			continue
		for stroke: PackedVector2Array in DimensionScript.layout(entity, 1.0, null)["lines"]:
			for point in stroke:
				extent = extent.expand(point)
	return extent


## The strip across the bottom of the sheet, in paper millimetres, that the title
## block claims. The scale is chosen against what is left, so a drawing cannot be
## fitted to a sheet and then placed under the block.
static func _reserved_mm(show_border: bool) -> float:
	if not show_border:
		return 0.0
	return TITLE_BLOCK_HEIGHT_MM + TITLE_BLOCK_CLEARANCE_MM


## The area left for the drawing once the title block has taken a strip across
## the bottom of the sheet. The strip is full width even though the block only
## occupies one end of it, because a drawing is placed by its centre and a
## centre that ignores the block puts the drawing under it.
static func _content_area(area: Rect2) -> Rect2:
	var reserved := _reserved_mm(true) * POINTS_PER_MM
	return Rect2(area.position, Vector2(area.size.x, maxf(area.size.y - reserved, area.size.y * 0.25)))


## Model XZ to paper points, centred on the sheet, north up.
static func model_to_paper(point: Vector2, plan: Dictionary) -> Vector2:
	var extent: Rect2 = plan["extent"]
	var per_metre: float = plan["pt_per_metre"]
	var origin: Vector2 = plan["origin_pt"]
	return Vector2(
		origin.x + (point.x - extent.position.x) * per_metre,
		origin.y + (extent.end.y - point.y) * per_metre
	)


# --- emission -----------------------------------------------------------------------


static func export_pdf(document, options: Dictionary = {}) -> PackedByteArray:
	var plan := plan_sheet(document, options)
	var sheet_mm: Vector2 = plan["sheet_mm"]
	var writer = PdfWriterScript.new()
	writer.begin_page(sheet_mm.x * POINTS_PER_MM, sheet_mm.y * POINTS_PER_MM)

	var pen_table = options.get("pen_table", null)

	if bool(plan["show_border"]):
		_emit_border(writer, plan)

	# Draw order is the document's own, which already sorts by the layer's
	# plotting band, so big things sit under small ones exactly as on screen.
	for entity in document.plotting_entities():
		_emit_entity(writer, document, entity, pen_table, plan)

	# The block goes on last, so nothing a user drew can end up under it.
	if bool(plan["show_border"]):
		_emit_title_block(writer, plan, options)
	return writer.build()


static func _emit_border(writer, plan: Dictionary) -> void:
	var area: Rect2 = plan["printable_pt"]
	writer.save_state()
	writer.set_line_width_points(BORDER_WEIGHT_MM * POINTS_PER_MM)
	writer.set_stroke_colour(Color.BLACK)
	writer.set_dash([])
	writer.rectangle(area)
	writer.stroke()
	writer.restore_state()


## The title block: what the sheet is, what it shows and how to read it.
##
## Four rows across the bottom-right corner. The first two carry the project and
## the drawing, the third the numbering that identifies the sheet, and the last
## the scale bar and the north point. None of it is authorable geometry, so it is
## drawn at fixed paper sizes and reads identically on every sheet.
static func _emit_title_block(writer, plan: Dictionary, options: Dictionary) -> void:
	var area: Rect2 = plan["printable_pt"]
	var block := Rect2(
		area.end - Vector2(TITLE_BLOCK_WIDTH_MM, TITLE_BLOCK_HEIGHT_MM) * POINTS_PER_MM,
		Vector2(TITLE_BLOCK_WIDTH_MM, TITLE_BLOCK_HEIGHT_MM) * POINTS_PER_MM
	)

	writer.save_state()
	writer.set_line_width_points(BORDER_WEIGHT_MM * POINTS_PER_MM)
	writer.set_stroke_colour(Color.BLACK)
	writer.set_dash([])
	writer.rectangle(block)
	writer.stroke()

	# Row dividers. The first three rows are one height each; the last takes what
	# is left, which is deeper because it holds the scale bar.
	var row := TITLE_BLOCK_ROW_MM * POINTS_PER_MM
	var numbering := block.end.y - (TITLE_BLOCK_HEIGHT_MM - TITLE_BLOCK_ROW_MM * 3.0) * POINTS_PER_MM
	writer.set_line_width_points(HAIRLINE_WEIGHT_MM * POINTS_PER_MM)
	for index in range(1, 4):
		var y := block.position.y + row * float(index)
		_rule(writer, Vector2(block.position.x, y), Vector2(block.end.x, y))

	# The four numbering cells, and the north point's square at the end.
	var edges: Array[float] = [0.42, 0.62, 0.82]
	for fraction: float in edges:
		var x := block.position.x + block.size.x * fraction
		_rule(writer, Vector2(x, numbering), Vector2(x, block.end.y))
	var north_x := block.end.x - NORTH_CELL_MM * POINTS_PER_MM
	_rule(writer, Vector2(north_x, numbering), Vector2(north_x, block.end.y))

	_field(writer, block.position, "PROJECT", _project_name(options), TITLE_TEXT_MM)
	_field(
		writer, Vector2(block.position.x, block.position.y + row),
		"DRAWING", String(options.get("drawing", "")), TITLE_TEXT_MM
	)

	var cells: Array = [
		["SCALE", _scale_label(plan)],
		["SHEET", String(plan["sheet"])],
		["DATE", String(options.get("date", Time.get_date_string_from_system()))],
		["REV", String(options.get("revision", "-"))],
	]
	var bounds: Array[float] = [0.0, 0.42, 0.62, 0.82]
	for index in cells.size():
		_field(
			writer,
			Vector2(block.position.x + block.size.x * bounds[index], numbering),
			String(cells[index][0]), String(cells[index][1]), LABEL_TEXT_MM
		)

	_emit_scale_bar(
		writer, plan,
		Rect2(Vector2(block.position.x, numbering), Vector2(north_x - block.position.x, block.end.y - numbering))
	)
	_emit_north_arrow(
		writer,
		Rect2(Vector2(north_x, numbering), Vector2(block.end.x - north_x, block.end.y - numbering))
	)
	writer.restore_state()


## One straight rule, which is all a title block divider is. The caller owns the
## width, colour and dash, because they are the same for every rule in the block.
static func _rule(writer, from: Vector2, to: Vector2) -> void:
	writer.move_to(from)
	writer.line_to(to)
	writer.stroke()


## A caption above its value. The caption says what the value means, so it is the
## smaller and greyer of the two and the value is what the eye lands on.
static func _field(writer, at: Vector2, caption: String, value: String, value_mm: float) -> void:
	var inset := TITLE_CELL_INSET_MM * POINTS_PER_MM
	writer.set_fill_colour(CAPTION_COLOUR)
	writer.draw_text(
		at + Vector2(inset, (TITLE_CELL_INSET_MM + CAPTION_TEXT_MM) * POINTS_PER_MM),
		caption, CAPTION_TEXT_MM * POINTS_PER_MM
	)
	writer.set_fill_colour(Color.BLACK)
	writer.draw_text(
		at + Vector2(inset, (TITLE_CELL_INSET_MM + CAPTION_TEXT_MM + value_mm) * POINTS_PER_MM),
		value, value_mm * POINTS_PER_MM
	)


## The scale bar: a bar drawn at its true length, so it can be checked against a
## ruler laid on the printed sheet. The bar is the honest part - its length is the
## scale law applied to a round number of metres - and the divisions are what make
## it countable by eye.
static func _emit_scale_bar(writer, plan: Dictionary, strip: Rect2) -> void:
	var imperial: bool = plan["imperial"]
	var per_metre: float = plan["pt_per_metre"]
	var choice := PlotScaleScript.scale_bar_length(per_metre, strip.size.x * 0.62, imperial)
	var bar := float(choice["metres"]) * per_metre
	var step := bar / float(SCALE_BAR_DIVISIONS)
	var height := SCALE_BAR_HEIGHT_MM * POINTS_PER_MM
	var left := strip.position.x
	var base := strip.position.y + strip.size.y * 0.62

	writer.set_line_width_points(HAIRLINE_WEIGHT_MM * POINTS_PER_MM)
	writer.set_dash([])
	# Alternating filled and open divisions, which is what makes a scale bar
	# countable rather than merely long.
	for index in SCALE_BAR_DIVISIONS:
		var start := left + step * float(index)
		if index % 2 == 0:
			writer.set_fill_colour(Color.BLACK)
			writer.rectangle(Rect2(Vector2(start, base), Vector2(step, height)))
			writer.fill()
		writer.set_fill_colour(Color.BLACK)
		writer.draw_text(
			Vector2(start, base + height + POINTS_PER_MM),
			scale_bar_label(float(choice["label_value"]) * float(index) / float(SCALE_BAR_DIVISIONS), step),
			CAPTION_TEXT_MM * POINTS_PER_MM
		)

	writer.set_stroke_colour(Color.BLACK)
	writer.rectangle(Rect2(Vector2(left, base), Vector2(bar, height)))
	writer.stroke()
	writer.draw_text(
		Vector2(left + bar + POINTS_PER_MM, base + height + POINTS_PER_MM),
		"%s %s" % [scale_bar_label(float(choice["label_value"]), step), "ft" if imperial else "m"],
		CAPTION_TEXT_MM * POINTS_PER_MM
	)


## The north point. North is up on the sheet by construction - the exporter flips
## the model's southward y as it writes - so the arrow is a fixed glyph rather
## than something derived from the drawing.
static func _emit_north_arrow(writer, cell: Rect2) -> void:
	var centre := cell.get_center()
	var reach := minf(cell.size.x, cell.size.y) * 0.30
	var tip := centre + Vector2(0.0, reach)
	var half := reach * 0.36
	writer.set_line_width_points(HAIRLINE_WEIGHT_MM * POINTS_PER_MM)
	writer.set_stroke_colour(Color.BLACK)
	writer.set_fill_colour(Color.BLACK)
	writer.set_dash([])
	# A shaft with a solid head: a slim drafting arrow rather than a broad
	# triangle, which would read as a road sign.
	_rule(writer, centre, tip)
	writer.move_to(tip)
	writer.line_to(tip + Vector2(-half, -reach * 1.3))
	writer.line_to(tip + Vector2(half, -reach * 1.3))
	writer.close_path()
	writer.fill()
	var size := CAPTION_TEXT_MM * POINTS_PER_MM
	writer.draw_text(
		tip + Vector2(-writer.text_width("N", size) * 0.5, POINTS_PER_MM), "N", size
	)


## A division is labelled to the precision it was divided by. Rounding a
## half-metre step to whole metres puts "0 1 1 2" under a two-metre bar, which is
## not a scale anything can be read off.
static func scale_bar_label(value: float, step: float) -> String:
	if absf(step - roundf(step)) < 1e-6:
		return "%d" % int(roundf(value))
	return "%.1f" % value


static func _project_name(options: Dictionary) -> String:
	return String(options.get("project", options.get("title", "")))


static func _scale_label(plan: Dictionary) -> String:
	if bool(plan["imperial"]):
		return PlotScaleScript.imperial_label(plan["scale"])
	return PlotScaleScript.metric_label(plan["scale"])


static func _emit_entity(writer, document, entity: EntityScript, pen_table, plan: Dictionary) -> void:
	var layer = document.layers.get_layer(entity.layer)
	var style := _plot_style(entity, layer, pen_table)

	writer.save_state()
	writer.set_line_width_points(style.width_points())
	writer.set_stroke_colour(style.plot_colour)
	writer.set_fill_colour(style.plot_colour)
	writer.set_dash(_dash_points(style))

	# A circle or an arc is emitted as real curves rather than sampled ones: it is
	# the shape most likely to be large on a sheet, so a client zooming into the
	# PDF must not be able to see facets, and a tree pit has to stay round.
	if entity.kind == EntityScript.Kind.CIRCLE:
		_emit_arc(writer, entity.point(0), entity.params[2], 0.0, TAU, plan)
	elif entity.kind == EntityScript.Kind.ARC:
		_emit_arc(writer, entity.point(0), entity.params[2], entity.params[3], entity.params[4], plan)
	else:
		_emit_layout(writer, entity, layer, document, plan)

	writer.restore_state()


## The pen a plotted entity draws with. The pen table wins when it has a pen for
## the entity's slot, and the layer's own style is the fallback, so an entity
## whose colour nobody assigned a pen to still plots.
static func _plot_style(entity: EntityScript, layer, pen_table) -> LineStyleScript:
	var fallback: LineStyleScript = RenderScript.style_for(entity, layer)
	if pen_table == null:
		return fallback
	return pen_table.resolve_for(RenderScript.screen_colour(layer), fallback)


## Dash lengths in paper points, which is what a PDF dash array takes. They are
## authored in paper millimetres, so the conversion is the same one the weights
## use and is independent of the plot scale: the geometry is already paper.
static func _dash_points(style: LineStyleScript) -> Array[float]:
	var out: Array[float] = []
	for millimetres: float in LineStyleScript.pattern_for(style.linetype):
		out.append(millimetres * POINTS_PER_MM)
	return out


## Everything the shared layout asks for: the linework, the filled arrowheads and
## the annotation text, all in the one pen the entity plots with.
##
## The outline is what plots. Bulges are already sampled into it at a
## two-millimetre tolerance, which is 0.02 mm on paper at 1:100 - far below
## anything a printer can put down - so there is nothing to gain from treating a
## bulged corner as a curve of its own. Going through the layout rather than the
## outline directly is what puts dimensions on the sheet whole: their extension
## lines, their arrowheads and their measurement are derived in one place and
## arrive here the same way they arrive on screen.
static func _emit_layout(writer, entity: EntityScript, layer, document, plan: Dictionary) -> void:
	var parts: Dictionary = RenderScript.layout(entity, layer, plan["scale"], document.units)

	for stroke: PackedVector2Array in parts["lines"]:
		if stroke.size() < 2:
			continue
		writer.move_to(model_to_paper(stroke[0], plan))
		for index in range(1, stroke.size()):
			writer.line_to(model_to_paper(stroke[index], plan))
		writer.stroke()

	# An arrowhead is a solid, so it is filled rather than stroked, in the same
	# colour and at the same weight as the line it terminates.
	for arrow: Dictionary in parts["arrows"]:
		var triangle := DimensionScript.arrow_triangle(
			arrow["tip"], arrow["direction"], arrow["size"]
		)
		writer.move_to(model_to_paper(triangle[0], plan))
		writer.line_to(model_to_paper(triangle[1], plan))
		writer.line_to(model_to_paper(triangle[2], plan))
		writer.close_path()
		writer.fill()

	for label: Dictionary in parts["labels"]:
		var text := String(label["text"])
		if text == "":
			continue
		# The layout states a text height in model metres, and pt_per_metre turns
		# any model length into paper points: the same law the geometry follows, so
		# a note is the authored size on paper at whatever scale is in force.
		writer.draw_text_rotated(
			model_to_paper(label["position"], plan),
			text,
			float(label["height"]) * float(plan["pt_per_metre"]),
			float(label["angle"])
		)


## A circular arc as cubic Beziers.
##
## Circles and arcs are the shapes most likely to be large on a sheet, so they
## are emitted as real curves rather than sampled polylines: a client zooming
## into the PDF must not be able to see facets, and a tree pit has to stay round.
static func _emit_arc(
	writer,
	centre: Vector2,
	radius: float,
	start: float,
	sweep: float,
	plan: Dictionary
) -> void:
	if radius <= 0.0 or absf(sweep) < 1e-9:
		return
	var segments := maxi(int(ceil(absf(sweep) / (PI * 0.5))), 1)
	var step := sweep / float(segments)
	# The standard control-point length: a cubic with this tangent length matches
	# a circular arc of that sweep. For a quarter circle it is r * 0.5522847,
	# which is the constant every drawing library uses.
	var control := _bezier_control(radius, step)

	writer.move_to(model_to_paper(Geom.arc_point(centre, radius, start, sweep, 0.0), plan))
	for index in segments:
		var from_angle := start + step * float(index)
		var to_angle := from_angle + step
		var from_point := centre + Vector2(cos(from_angle), sin(from_angle)) * radius
		var to_point := centre + Vector2(cos(to_angle), sin(to_angle)) * radius
		# The tangent is the radius turned a quarter turn. tan carries the sign of
		# the sweep, so a clockwise arc works without a special case.
		var from_tangent := Vector2(-sin(from_angle), cos(from_angle)) * control
		var to_tangent := Vector2(-sin(to_angle), cos(to_angle)) * control
		writer.curve_to(
			model_to_paper(from_point + from_tangent, plan),
			model_to_paper(to_point - to_tangent, plan),
			model_to_paper(to_point, plan)
		)
	writer.stroke()


static func _bezier_control(radius: float, sweep: float) -> float:
	return radius * 4.0 / 3.0 * tan(sweep * 0.25)