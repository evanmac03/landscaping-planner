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
const Geom := preload("res://scripts/draft/geom2d.gd")

const POINTS_PER_MM := 72.0 / 25.4

## The border sits this far inside the printable margin, in paper millimetres, so
## a printer that cannot quite reach the margin still prints a whole border.
const BORDER_INSET_MM := 2.0

## Paper text heights in millimetres. Text in a plot is authored to be read on
## paper, so it is a fixed set rather than something that scales with the drawing.
const LABEL_TEXT_MM := 2.5
const TITLE_TEXT_MM := 4.5

const BORDER_WEIGHT_MM := 0.70


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

	var extent: Rect2 = document.bounds()
	var scale: float = float(options.get("scale", 0.0))
	if scale <= 0.0:
		scale = PlotScaleScript.suggest(extent.size, sheet_name, effective_margin, imperial)["scale"]
	scale = maxf(scale, 0.0001)

	# Model metres to paper points. At 1:100 a metre is 10 mm, and a millimetre is
	# exactly 72/25.4 points, so a metre is 28.3465 points and a 10 m wall is
	# 283.465 points - which is 100 mm. This is the whole of the scale law.
	var pt_per_metre := 1000.0 / scale * POINTS_PER_MM
	var drawing_size := extent.size * pt_per_metre

	return {
		"sheet": sheet_name,
		"sheet_mm": sheet_mm,
		"margin_mm": effective_margin,
		"imperial": imperial,
		"show_border": show_border,
		"printable_pt": drawing_area,
		"extent": extent,
		"scale": scale,
		"pt_per_metre": pt_per_metre,
		"origin_pt": drawing_area.position + (drawing_area.size - drawing_size) * 0.5,
		"drawing_pt": drawing_size,
		"empty": document.count() == 0,
	}


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

	_emit_scale_label(writer, plan, String(options.get("title", "")))
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


static func _emit_scale_label(writer, plan: Dictionary, title: String) -> void:
	var label := PlotScaleScript.imperial_label(plan["scale"]) if bool(plan["imperial"]) \
		else PlotScaleScript.metric_label(plan["scale"])
	var text := "%s   %s   SCALE %s" % [title, plan["sheet"], label] if title != "" \
		else "%s   SCALE %s" % [plan["sheet"], label]
	var area: Rect2 = plan["printable_pt"]
	writer.save_state()
	writer.set_fill_colour(Color.BLACK)
	writer.draw_text(
		area.position + Vector2(LABEL_TEXT_MM, LABEL_TEXT_MM * 2.0) * POINTS_PER_MM,
		text, LABEL_TEXT_MM * POINTS_PER_MM
	)
	writer.restore_state()


static func _emit_entity(writer, document, entity: EntityScript, pen_table, plan: Dictionary) -> void:
	var layer = document.layers.get_layer(entity.layer)
	var style := _plot_style(entity, layer, pen_table)
	writer.set_line_width_points(style.width_points())
	writer.set_stroke_colour(style.plot_colour)
	writer.set_dash(_dash_points(style))

	if entity.kind == EntityScript.Kind.TEXT:
		var label := RenderScript.label_of(entity)
		if label != "":
			writer.save_state()
			writer.set_fill_colour(style.plot_colour)
			writer.draw_text(
				model_to_paper(RenderScript.label_position(entity), plan),
				label, LABEL_TEXT_MM * POINTS_PER_MM
			)
			writer.restore_state()
		return

	_emit_geometry(writer, entity, plan)


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


static func _emit_geometry(writer, entity: EntityScript, plan: Dictionary) -> void:
	if entity.kind == EntityScript.Kind.CIRCLE:
		_emit_arc(writer, entity.point(0), entity.params[2], 0.0, TAU, plan)
		return
	if entity.kind == EntityScript.Kind.ARC:
		_emit_arc(writer, entity.point(0), entity.params[2], entity.params[3], entity.params[4], plan)
		return

	# Everything else plots as its outline. Bulges are already sampled into that
	# outline at a two-millimetre tolerance, which is 0.02 mm on paper at 1:100:
	# far below anything a printer can put down, so there is nothing to gain from
	# treating a bulged corner as a curve of its own.
	var outline := entity.outline()
	if outline.size() < 2:
		return
	writer.move_to(model_to_paper(outline[0], plan))
	for index in range(1, outline.size()):
		writer.line_to(model_to_paper(outline[index], plan))
	writer.stroke()


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