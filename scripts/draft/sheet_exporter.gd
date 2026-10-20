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
##
## Paper y runs up the page, the way PDF has it, and that holds for the furniture
## as much as for the drawing: a box is placed by its own top edge and its rows
## are drawn downwards from there, and the title block sits along the foot of the
## sheet, which is its smaller y. The first version of this file laid the
## furniture out the other way round and still produced a plausible-looking
## sheet - a title block in the top corner, every caption under its value - which
## is why the convention is stated here rather than left to be inferred.

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
## The scale bar is inset from the block's own edges, so the filled end of its first
## division does not read as a thickening of the border.
const SCALE_BAR_INSET_MM := 1.5

## Captions are grey so the authored values read as the content of the block.
const CAPTION_COLOUR := Color(0.35, 0.35, 0.35)

## The layer key, in paper millimetres. It takes a column down the left edge of
## the sheet; the width is for the longest layer name in the preset set plus its
## pen sample and the count.
const LEGEND_WIDTH_MM := 62.0
const LEGEND_ROW_MM := 5.0
const LEGEND_HEADER_MM := 8.0
const LEGEND_PAD_MM := 2.0
const LEGEND_SAMPLE_MM := 11.0
const LEGEND_TITLE_MM := 3.5
const LEGEND_TEXT_GAP_MM := 2.0

## The planting schedule: the third table a planting plan carries, against the right edge where
## the key is against the left - the two read as one pair of columns around the drawing.
##
## Wider than the key because a species goes by two names at once, and a schedule that clipped
## half of every name would be a schedule nobody could order from.
const SCHEDULE_WIDTH_MM := 92.0
const SCHEDULE_ROW_MM := 4.6
const SCHEDULE_HEADER_MM := 8.0
const SCHEDULE_PAD_MM := 2.0
const SCHEDULE_TITLE_MM := 3.5
const SCHEDULE_TEXT_GAP_MM := 2.0


# --- layout -------------------------------------------------------------------------


## Work out the sheet without emitting anything, so a caller - or a test - can
## see the numbers the drawing will be plotted with.
static func plan_sheet(document, options: Dictionary = {}) -> Dictionary:
	var sheet_name: String = String(options.get("sheet", "A3"))
	var margin_mm: float = float(options.get("margin_mm", PlotScaleScript.DEFAULT_MARGIN_MM))
	var imperial: bool = bool(options.get("imperial", false))
	var show_border: bool = bool(options.get("show_border", true))
	# A portrait sheet is the same sheet turned a quarter turn, which is what a sheet whose subject is
	# a tall narrow garden - or one carrying more rows of schedule than drawing - is printed at.
	var portrait: bool = bool(options.get("portrait", false))
	# What the title block calls this sheet. A sheet of a set is identified by its *drawing number* -
	# L1.2 - and the paper size is not an identifier: two sheets of a set on A3 are two sheets. With no
	# number given the size stands in, which is the sheet this app plotted before sets existed.
	var number: String = String(options.get("number", "")).strip_edges()
	var legend: bool = bool(options.get("legend", false))
	var effective_margin := margin_mm + (BORDER_INSET_MM if show_border else 0.0)

	var sheet_mm: Vector2 = PlotScaleScript.sheet_size_mm(sheet_name, portrait)
	var sheet_pt := sheet_mm * POINTS_PER_MM
	var inset_pt := Vector2(effective_margin, effective_margin) * POINTS_PER_MM
	var drawing_area := Rect2(inset_pt, sheet_pt - inset_pt * 2.0)
	# The key takes a column and the title block a strip, so the drawing is
	# centred in what is left rather than in the whole sheet: a drawing centred
	# under a title block is a drawing with a title block on top of it.
	# The planting schedule is furniture of the key's kind: a table against an edge, only as tall
	# as its rows. It takes the right edge and the key the left, and only as many of its rows as
	# the column can hold are drawn - what is left out is counted in its own row, because a
	# schedule that silently stops at the foot of the page is a schedule somebody orders from.
	var block_mm: float = (TITLE_BLOCK_HEIGHT_MM + TITLE_BLOCK_CLEARANCE_MM) if show_border else 0.0
	var schedule: Array = []
	if show_border:
		schedule = fit_schedule(
			options.get("schedule", []), drawing_area.size.y / POINTS_PER_MM - block_mm
		)
	var schedule_rect := Rect2()
	if not schedule.is_empty():
		var schedule_mm := _schedule_height_mm(schedule.size())
		schedule_rect = Rect2(
			Vector2(
				drawing_area.end.x - SCHEDULE_WIDTH_MM * POINTS_PER_MM,
				drawing_area.end.y - schedule_mm * POINTS_PER_MM
			),
			Vector2(SCHEDULE_WIDTH_MM, schedule_mm) * POINTS_PER_MM
		)

	var reserved := _reserved_mm(show_border, legend, not schedule.is_empty())
	var content := _content_area(drawing_area, reserved) if show_border else drawing_area

	var extent: Rect2 = _plot_extent(document)
	# A viewport is a window onto the model at a locked scale, which is how a real
	# sheet is laid out: the drawing is not poured into whatever space is left, it
	# is framed, and the frame can be moved, resized and turned. With none given,
	# the sheet works one out and everything below is unchanged.
	var viewport: Dictionary = options.get("viewport", {})
	var rotation := deg_to_rad(float(viewport.get("rotation_degrees", 0.0)))
	var frame := content if viewport.is_empty() else _viewport_frame(viewport, content)

	# A viewport's own scale is a lock: it is the reason for setting one, so it
	# outranks a scale passed alongside it and is never re-suggested.
	var scale: float = float(viewport.get("scale", options.get("scale", 0.0)))
	if scale <= 0.0:
		# The scale is chosen for what the drawing will take on the paper, which a
		# turned viewport makes bigger: turning a drawing costs it a scale step or a
		# sheet size, and pretending otherwise would leave it hanging off the border.
		scale = PlotScaleScript.suggest(
			_footprint(extent.size, rotation), sheet_name, effective_margin, imperial, reserved
		)["scale"]
	scale = maxf(scale, 0.0001)

	# Model metres to paper points. At 1:100 a metre is 10 mm, and a millimetre is
	# exactly 72/25.4 points, so a metre is 28.3465 points and a 10 m wall is
	# 283.465 points - which is 100 mm. This is the whole of the scale law.
	var pt_per_metre := 1000.0 / scale * POINTS_PER_MM
	# Turned or not, it is the footprint on the paper that has to fit, and the box
	# around a rotated rectangle is larger than the rectangle.
	var footprint := _footprint(extent.size * pt_per_metre, rotation)

	# The drawing is centred in its frame. One that does not fit is set against the
	# edge furthest from the furniture instead: pushing the overflow towards a
	# corner nobody reads would be worse than not placing it at all. A drawing that
	# overruns the border wants re-scaling, which is what the overflow flag is for;
	# one that overruns its own title block is simply unreadable.
	#
	# The block lies along the foot of the sheet, so it is the foot the drawing is
	# set clear of. Paper y runs up the page, so the foot of the frame is its
	# smaller y and setting the drawing against it pushes the overflow upwards.
	var origin := frame.get_center()
	if footprint.x > frame.size.x:
		origin.x = frame.position.x + footprint.x * 0.5
	if footprint.y > frame.size.y:
		origin.y = frame.position.y + footprint.y * 0.5

	# The key's frame, flush into the top-left corner of the border and only as
	# tall as the rows it has to carry.
	var legend_rect := Rect2()
	if legend:
		var rows := legend_rows(document, options.get("pen_table", null))
		if not rows.is_empty():
			var legend_mm := _legend_height_mm(rows.size())
			legend_rect = Rect2(
				Vector2(
					drawing_area.position.x,
					drawing_area.end.y - legend_mm * POINTS_PER_MM
				),
				Vector2(LEGEND_WIDTH_MM, legend_mm) * POINTS_PER_MM
			)

	return {
		"sheet": sheet_name,
		"sheet_mm": sheet_mm,
		"margin_mm": effective_margin,
		"imperial": imperial,
		"show_border": show_border,
		"portrait": portrait,
		"sheet_label": number if not number.is_empty() else sheet_name,
		"printable_pt": drawing_area,
		"content_pt": content,
		"extent": extent,
		"scale": scale,
		"pt_per_metre": pt_per_metre,
		"origin_pt": origin,
		"drawing_pt": footprint,
		"viewport_pt": frame,
		"rotation": rotation,
		"model_centre": extent.get_center(),
		"overflow": footprint.x > frame.size.x + 0.01 or footprint.y > frame.size.y + 0.01,
		"legend": legend,
		"legend_pt": legend_rect,
		"schedule": schedule,
		"schedule_pt": schedule_rect,
		"empty": document.count() == 0,
	}


## How tall the key is for a given number of rows: its title, its rows, and a
## little air under the last of them.
static func _legend_height_mm(rows: int) -> float:
	return LEGEND_HEADER_MM + LEGEND_ROW_MM * float(maxi(rows, 0)) + LEGEND_PAD_MM


## How tall the planting schedule is for a given number of rows: a title, the rows, and a little
## air under the last of them, exactly as the key is measured.
static func _schedule_height_mm(rows: int) -> float:
	return SCHEDULE_HEADER_MM + SCHEDULE_ROW_MM * float(maxi(rows, 0)) + SCHEDULE_PAD_MM


## One row of the planting schedule as it reads on the sheet: the name a nursery sends and the
## name a designer says, in the order the library writes them - `Acer rubrum 'Autumn Blaze' -
## Red maple` - so the schedule and the browser cannot name one plant two ways.
##
## A row that carries its own `name` is one of the two rows that are not a species: the count of
## plants the catalogue cannot name, and the count of species the column had no room for.
static func schedule_row_text(row: Dictionary) -> String:
	if row.has("name"):
		return String(row["name"])
	var words := String(row.get("botanical_name", ""))
	var cultivar := String(row.get("cultivar", ""))
	if not cultivar.is_empty():
		words = "%s '%s'" % [words, cultivar]
	var common := String(row.get("common_name", ""))
	if not common.is_empty():
		words = "%s - %s" % [words, common]
	return words


## A text that fits a column, shortened with a trailing `...` when it does not. A name that ran
## out of the box would print over the border or under the next table; a name that ends in dots
## says the sheet is short of room, which is a thing to fix rather than a thing to hide.
static func clipped_text(writer, text: String, size_points: float, room_points: float) -> String:
	if room_points <= 0.0:
		return ""
	if writer.text_width(text, size_points) <= room_points:
		return text
	var clipped := text
	while not clipped.is_empty() and writer.text_width(clipped + "...", size_points) > room_points:
		clipped = clipped.substr(0, clipped.length() - 1)
	return clipped + "..."


## The rows of the planting schedule that the sheet has room for.
##
## A row with no species on it is not a species: it is the line that says how many standing plants
## the catalogue cannot name, and it is the one line a planting schedule must not hide. It is kept
## whatever else is cut, one line is spent on the row that names what the cutting left out, and a
## sheet with room for neither gets no table rather than a table hanging off the border.
static func fit_schedule(rows: Array, available_mm: float) -> Array:
	var room := int(floor(
		(available_mm - SCHEDULE_HEADER_MM - SCHEDULE_PAD_MM) / SCHEDULE_ROW_MM
	))
	if rows.size() <= room:
		return rows
	if room < 1:
		return []
	var unnamed: Array = []
	var species: Array = []
	for row: Dictionary in rows:
		if StringName(row.get("id", &"")).is_empty():
			unnamed.append(row)
		else:
			species.append(row)
	# `room - unnamed.size() - 1`: the unnamed lines are kept, one line goes to saying what was
	# left out, and what remains is how many species can be listed.
	var listed := maxi(room - unnamed.size() - 1, 0)
	var kept: Array = []
	for index in mini(species.size(), listed):
		kept.append(species[index])
	var omitted := species.size() - kept.size()
	if omitted > 0:
		kept.append({"id": &"", "count": 0, "name": "%d species not shown" % omitted})
	kept.append_array(unnamed)
	return kept


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
		for stroke: PackedVector2Array in DimensionScript.layout(
			entity, 1.0, null, DimensionScript.style_for(entity, document)
		)["lines"]:
			for point in stroke:
				extent = extent.expand(point)
	return extent


## The part of the sheet, in paper millimetres, that the furniture claims: a
## column down the left edge for the layer key and a strip across the bottom for
## the title block.
##
## The choice of scale is made against what is left, not against the whole page.
## A sheet that picked a scale for the full printable area and then laid its
## furniture over the drawing would be inconsistent with itself, and the
## inconsistency would only show up on paper.
static func _reserved_mm(show_border: bool, legend: bool, schedule: bool = false) -> Vector2:
	if not show_border:
		return Vector2.ZERO
	var columns := 0.0
	if legend:
		columns += LEGEND_WIDTH_MM
	if schedule:
		columns += SCHEDULE_WIDTH_MM
	return Vector2(columns, TITLE_BLOCK_HEIGHT_MM + TITLE_BLOCK_CLEARANCE_MM)


## The area left for the drawing once the furniture has taken its columns and its
## strip. All three are reserved as full-length bands even though the legend is
## only as tall as its rows and the block only reaches part way across, because a
## drawing is placed by its centre and a centre that ignored them would put the
## drawing under them.
##
## The columns come off the sides and the block's strip off the foot of the sheet,
## which on paper - where y runs up the page - moves the content's own foot up
## while its top stays where the border put it.
static func _content_area(area: Rect2, reserved: Vector2) -> Rect2:
	var claimed := reserved * POINTS_PER_MM
	return Rect2(
		area.position + claimed,
		Vector2(
			maxf(area.size.x - claimed.x, area.size.x * 0.25),
			maxf(area.size.y - claimed.y, area.size.y * 0.25)
		)
	)


## Model XZ to paper points: placed at the drawing's centre on the sheet and
## turned for its viewport, north up until something says otherwise.
##
## The model's y runs south and the paper's runs north, so the flip is part of the
## transform rather than a correction sprinkled through the emitters. Getting it
## backwards produces a mirrored plan that still looks plausible, which is why it
## is one function with a test rather than arithmetic in five places.
static func model_to_paper(point: Vector2, plan: Dictionary) -> Vector2:
	var per_metre: float = plan["pt_per_metre"]
	var centre: Vector2 = plan["model_centre"]
	var offset := (point - centre) * per_metre
	offset.y = -offset.y
	return Vector2(plan["origin_pt"]) + offset.rotated(plan["rotation"])


## Which way north points on the paper. North is up until a viewport is turned,
## and then the north point has to turn with it or it lies about the drawing.
static func north_direction(plan: Dictionary) -> Vector2:
	return Vector2(0.0, 1.0).rotated(plan["rotation"])


## The rectangle a drawing covers on the paper once turned. A rotated rectangle's
## axis-aligned box is larger than the rectangle, and it is the box that has to
## fit the sheet.
static func _footprint(size: Vector2, rotation: float) -> Vector2:
	var across := absf(cos(rotation))
	var down := absf(sin(rotation))
	return Vector2(
		across * size.x + down * size.y,
		down * size.x + across * size.y
	)


## The frame a caller's viewport describes, in paper points. Anything left out
## falls back to the area the furniture left, so a viewport may be given as little
## as a scale, or a rotation, or a whole window.
static func _viewport_frame(viewport: Dictionary, content: Rect2) -> Rect2:
	var origin_mm := Vector2(viewport.get("origin_mm", content.position / POINTS_PER_MM))
	var size_mm := Vector2(viewport.get("size_mm", content.size / POINTS_PER_MM))
	return Rect2(origin_mm * POINTS_PER_MM, size_mm * POINTS_PER_MM)


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

	# The furniture goes on last, so nothing a user drew can end up under it.
	if bool(plan["show_border"]):
		_emit_legend(writer, document, pen_table, plan, options)
		_emit_schedule(writer, plan, options)
		_emit_title_block(writer, plan, options)
	return writer.build()


# --- the layer key ------------------------------------------------------------------


## One row per layer that actually puts something on this sheet, in the layer
## set's own order, so the key reads from the survey down to the annotations.
##
## Keyed by layer rather than by plant species because the document knows its
## layers and does not know its species: a key that claimed to tell a maple from
## an oak would be guessing. The count is of the entities that plot, so a layer
## switched off is absent from the key rather than listed with nothing against it.
static func legend_rows(document, pen_table) -> Array[Dictionary]:
	var counts: Dictionary = {}
	for entity in document.plotting_entities():
		counts[entity.layer] = int(counts.get(entity.layer, 0)) + 1
	var rows: Array[Dictionary] = []
	for layer in document.layers.layers():
		var count := int(counts.get(layer.name, 0))
		if count <= 0:
			continue
		rows.append({
			"name": String(layer.name),
			"count": count,
			"style": layer_pen(layer, pen_table),
		})
	return rows


## The pen a layer plots with. This is what the key's sample line is drawn in, so
## the key explains the drawing rather than merely naming it.
static func layer_pen(layer, pen_table) -> LineStyleScript:
	var fallback: LineStyleScript = layer.style()
	if pen_table == null:
		return fallback
	return pen_table.resolve_for(layer.screen_colour, fallback)


static func _emit_legend(
	writer,
	document,
	pen_table,
	plan: Dictionary,
	options: Dictionary
) -> void:
	var rect: Rect2 = plan["legend_pt"]
	if rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return
	var rows := legend_rows(document, pen_table)
	if rows.is_empty():
		return

	writer.save_state()
	writer.set_line_width_points(BORDER_WEIGHT_MM * POINTS_PER_MM)
	writer.set_stroke_colour(Color.BLACK)
	writer.set_dash([])
	writer.rectangle(rect)
	writer.stroke()

	var pad := LEGEND_PAD_MM * POINTS_PER_MM
	# The key is anchored at the top of its frame and read downwards: a title under
	# its own rows is a title nobody reads, and paper y runs up the page.
	var title_y := rect.end.y - pad - LEGEND_TITLE_MM * POINTS_PER_MM
	writer.set_fill_colour(Color.BLACK)
	writer.draw_text(
		Vector2(rect.position.x + pad, title_y),
		String(options.get("legend_title", "KEY")), LEGEND_TITLE_MM * POINTS_PER_MM
	)
	writer.set_line_width_points(HAIRLINE_WEIGHT_MM * POINTS_PER_MM)
	var header := rect.end.y - LEGEND_HEADER_MM * POINTS_PER_MM
	_rule(writer, Vector2(rect.position.x, header), Vector2(rect.end.x, header))

	var size := CAPTION_TEXT_MM * POINTS_PER_MM
	var row := LEGEND_ROW_MM * POINTS_PER_MM
	var baseline := header - row + pad * 0.5
	for entry: Dictionary in rows:
		var style: LineStyleScript = entry["style"]
		writer.set_line_width_points(style.width_points())
		writer.set_stroke_colour(style.plot_colour)
		writer.set_dash(_dash_points(style))
		# The sample is drawn in the layer's own pen, weight and linetype: the
		# whole point of a key is that its line looks like the drawing's.
		var sample_y := baseline + row * 0.35
		writer.move_to(Vector2(rect.position.x + pad, sample_y))
		writer.line_to(
			Vector2(rect.position.x + pad + LEGEND_SAMPLE_MM * POINTS_PER_MM, sample_y)
		)
		writer.stroke()
		writer.set_dash([])

		writer.set_fill_colour(Color.BLACK)
		writer.draw_text(
			Vector2(
				rect.position.x + pad + (LEGEND_SAMPLE_MM + LEGEND_TEXT_GAP_MM) * POINTS_PER_MM,
				baseline
			),
			String(entry["name"]), size
		)
		var count := "%d" % int(entry["count"])
		writer.draw_text(
			Vector2(rect.end.x - pad - writer.text_width(count, size), baseline), count, size
		)
		baseline -= row
	writer.restore_state()


# --- the planting schedule ----------------------------------------------------------


## The planting schedule, drawn against the right edge: the count in a column of its own, then the
## name. The count is on the right, as it is in the key, so a reader who has learnt one table has
## learnt the other.
##
## The rows are handed in rather than read off the drawing, for the reason the key is keyed by
## layer: a document knows its layers and does not know its species. `PlantPlacement.schedule()`
## is where they come from and where the count of unnamed plants comes from too.
static func _emit_schedule(writer, plan: Dictionary, options: Dictionary) -> void:
	var rect: Rect2 = plan["schedule_pt"]
	if rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return
	var rows: Array = plan.get("schedule", [])
	if rows.is_empty():
		return

	writer.save_state()
	writer.set_line_width_points(BORDER_WEIGHT_MM * POINTS_PER_MM)
	writer.set_stroke_colour(Color.BLACK)
	writer.set_dash([])
	writer.rectangle(rect)
	writer.stroke()

	var pad := SCHEDULE_PAD_MM * POINTS_PER_MM
	# Read from the top down, as the key is.
	var title_y := rect.end.y - pad - SCHEDULE_TITLE_MM * POINTS_PER_MM
	writer.set_fill_colour(Color.BLACK)
	writer.draw_text(
		Vector2(rect.position.x + pad, title_y),
		String(options.get("schedule_title", "PLANTING SCHEDULE")),
		SCHEDULE_TITLE_MM * POINTS_PER_MM
	)
	writer.set_line_width_points(HAIRLINE_WEIGHT_MM * POINTS_PER_MM)
	var header := rect.end.y - SCHEDULE_HEADER_MM * POINTS_PER_MM
	_rule(writer, Vector2(rect.position.x, header), Vector2(rect.end.x, header))

	var size := CAPTION_TEXT_MM * POINTS_PER_MM
	var row_height := SCHEDULE_ROW_MM * POINTS_PER_MM
	var baseline := header - row_height + pad * 0.5
	for row: Dictionary in rows:
		var count := int(row.get("count", 0))
		# A row of nothing is not a row: the two lines that are not a species carry their number
		# inside their own words rather than in the column of plants.
		var counted := "" if count <= 0 else "%d" % count
		var count_room: float = writer.text_width(counted, size)
		var name_room: float = rect.size.x - pad * 2.0 - count_room
		if count > 0:
			name_room -= SCHEDULE_TEXT_GAP_MM * POINTS_PER_MM
		writer.set_fill_colour(Color.BLACK)
		writer.draw_text(
			Vector2(rect.position.x + pad, baseline),
			clipped_text(writer, schedule_row_text(row), size, name_room), size
		)
		if not counted.is_empty():
			writer.draw_text(Vector2(rect.end.x - pad - count_room, baseline), counted, size)
		baseline -= row_height
	writer.restore_state()


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
## Four rows across the bottom-right corner, read from the top down. The first two
## carry the project and the drawing, the third the numbering that identifies the
## sheet, and the foot the scale bar and the north point. None of it is authorable
## geometry, so it is drawn at fixed paper sizes and reads identically on every
## sheet.
static func _emit_title_block(writer, plan: Dictionary, options: Dictionary) -> void:
	var area: Rect2 = plan["printable_pt"]
	var block := Rect2(
		Vector2(area.end.x - TITLE_BLOCK_WIDTH_MM * POINTS_PER_MM, area.position.y),
		Vector2(TITLE_BLOCK_WIDTH_MM, TITLE_BLOCK_HEIGHT_MM) * POINTS_PER_MM
	)

	writer.save_state()
	writer.set_line_width_points(BORDER_WEIGHT_MM * POINTS_PER_MM)
	writer.set_stroke_colour(Color.BLACK)
	writer.set_dash([])
	writer.rectangle(block)
	writer.stroke()

	# Row dividers, measured down from the top of the block. The first three rows
	# are one height each; the foot takes what is left, which is deeper because it
	# holds the scale bar.
	var row := TITLE_BLOCK_ROW_MM * POINTS_PER_MM
	var numbering := block.end.y - row * 2.0
	var foot := block.end.y - row * 3.0
	writer.set_line_width_points(HAIRLINE_WEIGHT_MM * POINTS_PER_MM)
	for index in range(1, 4):
		var y := block.end.y - row * float(index)
		_rule(writer, Vector2(block.position.x, y), Vector2(block.end.x, y))

	# The four numbering cells, and the north point's square at the end. They span
	# the numbering row, not the whole block.
	var edges: Array[float] = [0.42, 0.62, 0.82]
	for fraction: float in edges:
		var x := block.position.x + block.size.x * fraction
		_rule(writer, Vector2(x, foot), Vector2(x, numbering))
	var north_x := block.end.x - NORTH_CELL_MM * POINTS_PER_MM
	_rule(writer, Vector2(north_x, foot), Vector2(north_x, numbering))

	_field(writer, Vector2(block.position.x, block.end.y), "PROJECT", _project_name(options), TITLE_TEXT_MM)
	_field(
		writer, Vector2(block.position.x, block.end.y - row),
		"DRAWING", String(options.get("drawing", "")), TITLE_TEXT_MM
	)

	var cells: Array = [
		["SCALE", _scale_label(plan)],
		["SHEET", String(plan["sheet_label"])],
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
		Rect2(
			Vector2(
				block.position.x + SCALE_BAR_INSET_MM * POINTS_PER_MM,
				block.position.y
			),
			Vector2(
				north_x - block.position.x - SCALE_BAR_INSET_MM * 2.0 * POINTS_PER_MM,
				foot - block.position.y
			)
		)
	)
	_emit_north_arrow(
		writer,
		Rect2(Vector2(north_x, block.position.y), Vector2(block.end.x - north_x, foot - block.position.y)),
		north_direction(plan)
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
##
## `at` is the top-left corner of the cell and both lines hang below it: paper y
## runs up the page, so a caption "above" its value is the larger y.
static func _field(writer, at: Vector2, caption: String, value: String, value_mm: float) -> void:
	var inset := TITLE_CELL_INSET_MM * POINTS_PER_MM
	var caption_y := at.y - (TITLE_CELL_INSET_MM + CAPTION_TEXT_MM) * POINTS_PER_MM
	writer.set_fill_colour(CAPTION_COLOUR)
	writer.draw_text(Vector2(at.x + inset, caption_y), caption, CAPTION_TEXT_MM * POINTS_PER_MM)
	writer.set_fill_colour(Color.BLACK)
	writer.draw_text(
		Vector2(at.x + inset, caption_y - value_mm * POINTS_PER_MM),
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
	# The bar rides low in its cell with the divisions numbered above it, which is
	# how a scale bar is read off paper and which keeps the numbers clear of the
	# heavy border along the foot of the sheet.
	var base := strip.position.y + strip.size.y * 0.26

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


## The north point, turned to match the viewport. North is up on a sheet laid out
## north up - the exporter flips the model's southward y as it writes - but a
## turned viewport turns north with it, and an arrow still pointing up the page
## would be a lie about the drawing.
static func _emit_north_arrow(writer, cell: Rect2, north: Vector2) -> void:
	var centre := cell.get_center()
	var reach := minf(cell.size.x, cell.size.y) * 0.30
	var tip := centre + north * reach
	var flare := Vector2(-north.y, north.x) * (reach * 0.36)
	writer.set_line_width_points(HAIRLINE_WEIGHT_MM * POINTS_PER_MM)
	writer.set_stroke_colour(Color.BLACK)
	writer.set_fill_colour(Color.BLACK)
	writer.set_dash([])
	# A shaft with a solid head: a slim drafting arrow rather than a broad
	# triangle, which would read as a road sign.
	_rule(writer, centre, tip)
	writer.move_to(tip)
	writer.line_to(tip - north * (reach * 1.3) + flare)
	writer.line_to(tip - north * (reach * 1.3) - flare)
	writer.close_path()
	writer.fill()
	# The letter stays upright whatever the arrow does: a turning letter is a
	# letter nobody reads.
	var size := CAPTION_TEXT_MM * POINTS_PER_MM
	writer.draw_text(
		tip + north * POINTS_PER_MM - Vector2(writer.text_width("N", size) * 0.5, size * 0.5),
		"N", size
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
##
## The pen's linetype is then constrained: a dimension's generated linework is
## continuous whatever pen its layer resolves to, because a dashed dimension line is
## not a drafting standard (see `DraftRender.linework_style`).
static func _plot_style(entity: EntityScript, layer, pen_table) -> LineStyleScript:
	var fallback: LineStyleScript = RenderScript.style_for(entity, layer)
	if pen_table == null:
		return RenderScript.generated_linework_style(entity, fallback)
	return RenderScript.generated_linework_style(
		entity, pen_table.resolve_for(RenderScript.screen_colour(layer), fallback)
	)


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
	var parts: Dictionary = RenderScript.layout(
		entity, layer, plan["scale"], document.units,
		DimensionScript.style_for(entity, document)
	)

	for stroke: PackedVector2Array in parts["lines"]:
		if stroke.size() < 2:
			continue
		writer.move_to(model_to_paper(stroke[0], plan))
		for index in range(1, stroke.size()):
			writer.line_to(model_to_paper(stroke[index], plan))
		writer.stroke()

	# A mark is a solid, so it is filled rather than stroked, in the same colour
	# and at the same weight as the line it terminates. A dot is emitted as real
	# curves: it is the one shape where a polygon would show even at a millimetre
	# across, and a printed dot has to be round.
	for mark: Dictionary in parts["marks"]:
		if mark["kind"] == &"arrow":
			var triangle := DimensionScript.arrow_triangle(
				mark["tip"], mark["direction"], mark["size"], mark["width_ratio"]
			)
			writer.move_to(model_to_paper(triangle[0], plan))
			writer.line_to(model_to_paper(triangle[1], plan))
			writer.line_to(model_to_paper(triangle[2], plan))
			writer.close_path()
			writer.fill()
		elif mark["kind"] == &"dot":
			var centre := model_to_paper(Vector2(mark["at"]), plan)
			_emit_circle_path_pt(
				writer, centre,
				float(mark["size"]) * 0.5 * float(plan["pt_per_metre"])
			)
			writer.fill()

	for label: Dictionary in parts["labels"]:
		var text := String(label["text"])
		if text == "":
			continue
		# The layout states a text height in model metres, and pt_per_metre turns
		# any model length into paper points: the same law the geometry follows, so
		# a note is the authored size on paper at whatever scale is in force.
		# The label carries a model-space angle. On the paper the vertical flip
		# turns it the other way and the viewport's rotation is added on top, so
		# the two cancel and compose rather than needing a third convention.
		writer.draw_text_rotated(
			model_to_paper(label["position"], plan),
			text,
			float(label["height"]) * float(plan["pt_per_metre"]),
			float(plan["rotation"]) - float(label["angle"])
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


## A full circle in paper points, as four cubic Beziers, left as a path for the
## caller to fill or stroke. Used for the round mark a dimension style may put at
## its ends.
static func _emit_circle_path_pt(writer, centre: Vector2, radius: float) -> void:
	if radius <= 0.0:
		return
	var control := _bezier_control(radius, PI * 0.5)
	var right := Vector2(radius, 0.0)
	var up := Vector2(0.0, radius)
	writer.move_to(centre + right)
	_circle_quarter(writer, centre, right, up, control)
	_circle_quarter(writer, centre, up, -right, control)
	_circle_quarter(writer, centre, -right, -up, control)
	_circle_quarter(writer, centre, -up, right, control)
	writer.close_path()


## One quarter of that circle, from one radius vector to the next going
## anticlockwise. Each control point sits off its own radius along the tangent, so
## the same control length serves all four quarters.
static func _circle_quarter(
	writer,
	centre: Vector2,
	from_vector: Vector2,
	to_vector: Vector2,
	control: float
) -> void:
	writer.curve_to(
		centre + from_vector + Vector2(-from_vector.y, from_vector.x).normalized() * control,
		centre + to_vector + Vector2(to_vector.y, -to_vector.x).normalized() * control,
		centre + to_vector
	)