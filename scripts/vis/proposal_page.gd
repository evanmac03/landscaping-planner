class_name VisProposalPage
extends RefCounted
## A still placed on a sheet with a title block: the two deliverable outputs, joined.
##
## §16.1 of `docs/visualization-subsystem-spec.md` says the most valuable single thing
## the still path can add is a **proposal page** - a picture on a titled sheet - and that
## this is why the still exporter and the sheet exporter should learn about each other.
## This is that join, and it is one-way on purpose: a proposal page *reads* the sheet's
## own furniture (the border inset, the title block's size and row height) rather than
## inventing a second set of numbers, so a plan and the proposal beside it are the same
## drawing on the same paper. Nothing about the plotted plan changes.
##
## Two shapes of output, because a proposal is filed as a PDF and looked at as an image:
## `build_pdf` writes a real single-page PDF with the still embedded (a PDF image
## XObject, the addition §11.5's note said the writer did not yet have), and
## `render_image` lays the same page out as a PNG, which is what a person previews in the
## dock. Both take the *same* layout, so a preview and the file cannot disagree.
##
## The printed words are the sheet path's job in the PDF and are described as data by
## `render_image`: drawing glyphs into an `Image` needs a canvas item and therefore a
## window server, so the image carries the layout and the frame and the PDF carries the
## text. A page whose title block is empty of words in the raster preview is the honest
## split, not a missing feature.

const SheetExporterScript := preload("res://scripts/draft/sheet_exporter.gd")
const PdfWriterScript := preload("res://scripts/draft/pdf_writer.gd")

## The sheet's own furniture, read rather than restated (§13, REQ-V13.1).
const BORDER_INSET_MM := SheetExporterScript.BORDER_INSET_MM
const BORDER_WEIGHT_MM := SheetExporterScript.BORDER_WEIGHT_MM
const TITLE_BLOCK_WIDTH_MM := SheetExporterScript.TITLE_BLOCK_WIDTH_MM
const TITLE_BLOCK_HEIGHT_MM := SheetExporterScript.TITLE_BLOCK_HEIGHT_MM
const TITLE_BLOCK_ROW_MM := SheetExporterScript.TITLE_BLOCK_ROW_MM
const TITLE_BLOCK_CLEARANCE_MM := SheetExporterScript.TITLE_BLOCK_CLEARANCE_MM

## Air left between the border and the picture, all round.
const MARGIN_MM := 8.0
## The frame drawn round the picture itself, and its weight in millimetres.
const PICTURE_FRAME_MM := 0.35
## Text sizes, in paper millimetres.
const TITLE_TEXT_MM := 5.0
const LABEL_TEXT_MM := 2.5
## The longest side an embedded still is allowed to be. A 4K still embedded raw makes a
## fifteen-megabyte page for a picture printed at 300 dpi on A3, and the extra pixels are
## pixels no printer can resolve.
const MAX_EMBED_PX := 2400
## Paper, and the ink the page's own furniture is drawn in.
const PAPER := Color(0.945, 0.937, 0.906)
const INK := Color(0.10, 0.10, 0.10)


## Where the picture and the furniture go on a sheet, in paper millimetres with the
## origin at the bottom-left and y up the page - the plotted sheet's own axes, and PDF's.
##
## Returns `{paper_mm, border_mm, title_mm, area_mm, still_mm, scale, fits}`. `fits` is
## false when there is no picture or no room, and everything else is still filled in, so
## a caller can lay out the frame and say what is wrong rather than draw nothing.
static func layout(paper_mm: Vector2, still_px: Vector2i, options: Dictionary = {}) -> Dictionary:
	var page := paper_mm
	if page.x <= 0.0 or page.y <= 0.0:
		# A page of no size is not a page; A3 landscape is the one a plan is drawn on.
		page = Vector2(420.0, 297.0)
	var inset: float = float(options.get("border_inset_mm", BORDER_INSET_MM))
	var title_w: float = float(options.get("title_width_mm", TITLE_BLOCK_WIDTH_MM))
	var title_h: float = float(options.get("title_height_mm", TITLE_BLOCK_HEIGHT_MM))
	var margin: float = float(options.get("margin_mm", MARGIN_MM))
	var border := Rect2(Vector2(inset, inset), Vector2(page.x - inset * 2.0, page.y - inset * 2.0))
	# The title block lies along the foot, struck to the right edge inside the border.
	var title := Rect2(
		Vector2(border.position.x + border.size.x - title_w, border.position.y),
		Vector2(title_w, title_h)
	)
	# The picture sits above the title block strip, inside the border and the margin.
	var area := Rect2(
		Vector2(border.position.x + margin, border.position.y + title_h + TITLE_BLOCK_CLEARANCE_MM),
		Vector2(
			border.size.x - margin * 2.0,
			border.size.y - title_h - TITLE_BLOCK_CLEARANCE_MM - margin * 2.0
		)
	)
	var still := Rect2()
	var scale := 0.0
	var fits := false
	if still_px.x > 0 and still_px.y > 0 and area.size.x > 0.0 and area.size.y > 0.0:
		# One scale for both axes: a picture stretched to fill a box is a lie about the
		# garden, which is the one thing a proposal must not tell.
		scale = minf(area.size.x / float(still_px.x), area.size.y / float(still_px.y))
		var size := Vector2(float(still_px.x) * scale, float(still_px.y) * scale)
		still = Rect2(area.position + (area.size - size) * 0.5, size)
		fits = true
	return {
		"paper_mm": page,
		"border_mm": border,
		"title_mm": title,
		"area_mm": area,
		"still_mm": still,
		"scale": scale,
		"fits": fits,
	}


## The pixel size the laid-out page comes to at a given resolution.
static func page_pixels(plan: Dictionary, dpi_value: float) -> Vector2i:
	var page: Vector2 = plan["paper_mm"]
	return VisStillPreset.pixels_for_paper(page, dpi_value)


## The still, resized for embedding: never enlarged, and never longer than
## `MAX_EMBED_PX` on its long side.
static func embedding_size(still_px: Vector2i, max_px: int = MAX_EMBED_PX) -> Vector2i:
	if still_px.x <= 0 or still_px.y <= 0:
		return Vector2i.ZERO
	var longest: int = maxi(still_px.x, still_px.y)
	if longest <= max_px:
		return still_px
	var factor := float(max_px) / float(longest)
	return Vector2i(maxi(1, int(round(still_px.x * factor))), maxi(1, int(round(still_px.y * factor))))


## The title block's rows, as `{caption, value}` pairs, from what the caller knows. A row
## with no value is left in with an em dash rather than dropped, so the block a person
## reads has the same shape whatever was filled in.
static func title_rows(fields: Dictionary) -> Array[Dictionary]:
	var pairs: Array[Dictionary] = [
		{"caption": "PROJECT", "value": _or_dash(fields.get("project", ""))},
		{"caption": "VIEW", "value": _or_dash(fields.get("view", ""))},
		{"caption": "SHEET", "value": _or_dash(fields.get("sheet", ""))},
		{"caption": "SCALE / DATE", "value": "%s  %s" % [
			_or_dash(fields.get("scale", "")), _or_dash(fields.get("date", "")),
		]},
	]
	return pairs


## A real single-page PDF: the sheet, the border, the picture embedded as an image, and
## the title block. Returns an empty array when there is nothing to place, so the caller
## names the refusal rather than writing a page with a hole in it.
static func build_pdf(still: Image, paper_mm: Vector2, fields: Dictionary, options: Dictionary = {}) -> PackedByteArray:
	if still == null or still.is_empty():
		return PackedByteArray()
	var plan := layout(paper_mm, still.get_size(), options)
	if not bool(plan["fits"]):
		return PackedByteArray()
	var writer = PdfWriterScript.new()
	var page: Vector2 = plan["paper_mm"]
	var per_mm: float = PdfWriterScript.POINTS_PER_MM
	writer.begin_page(page.x * per_mm, page.y * per_mm)

	# The picture first, so the furniture draws over it rather than under.
	var embedded: Image = _scaled_copy(still, embedding_size(still.get_size()))
	writer.place_image(embedded, _to_points(plan["still_mm"], per_mm))
	# A thin frame round the picture: a photograph on a sheet needs an edge, and the
	# picture's own edge is whatever colour the render happened to end at.
	writer.set_line_width_points(maxf(PICTURE_FRAME_MM * per_mm, 0.1))
	writer.set_stroke_colour(INK)
	writer.rectangle(_to_points(plan["still_mm"], per_mm))
	writer.stroke()

	# The border and the title block, at the sheet's own weights.
	writer.set_line_width_points(BORDER_WEIGHT_MM * per_mm)
	writer.rectangle(_to_points(plan["border_mm"], per_mm))
	writer.stroke()
	writer.rectangle(_to_points(plan["title_mm"], per_mm))
	writer.stroke()
	_emit_title(writer, plan["title_mm"], title_rows(fields))
	return writer.build()


## The laid-out page as an image at the given resolution: paper, the border, the title
## block's frame, and the picture pasted where `layout` put it. The words are not drawn
## - see the class note - so this is the preview and the PDF is the deliverable.
##
## Pure image work, so it runs anywhere and can be tested against a synthetic still.
static func render_image(
	still: Image,
	paper_mm: Vector2,
	fields: Dictionary,
	dpi_value: float = 150.0,
	options: Dictionary = {}
) -> Image:
	var plan := layout(paper_mm, still.get_size() if still != null else Vector2i.ZERO, options)
	var px := page_pixels(plan, dpi_value)
	if px == Vector2i.ZERO:
		return null
	var page_mm: Vector2 = plan["paper_mm"]
	var scale: float = float(px.x) / page_mm.x
	var page := Image.create(px.x, px.y, false, Image.FORMAT_RGB8)
	page.fill(PAPER)
	var border: Rect2 = _to_pixels(plan["border_mm"], scale, px.y)
	var title: Rect2 = _to_pixels(plan["title_mm"], scale, px.y)
	var border_w: int = maxi(1, int(round(BORDER_WEIGHT_MM * scale)))
	_frame(page, border, border_w, INK)
	_frame(page, title, border_w, INK)
	if bool(plan["fits"]) and still != null and not still.is_empty():
		var target: Rect2 = _to_pixels(plan["still_mm"], scale, px.y)
		var fitted: Image = _scaled_copy(
			still, Vector2i(maxi(1, int(target.size.x)), maxi(1, int(target.size.y)))
		)
		# A rendered still may arrive with an alpha channel the page has not got, and
		# `blend_rect` refuses a source whose format differs from its own.
		if fitted.get_format() != page.get_format():
			fitted.convert(page.get_format())
		page.blend_rect(fitted, Rect2i(Vector2i.ZERO, fitted.get_size()), Vector2i(target.position))
		_frame(page, target, maxi(1, int(round(PICTURE_FRAME_MM * scale))), INK)
	# The title block's rules, one line per row the block actually has - so the preview
	# shows the structure of the block the PDF will fill in.
	_emit_title_rules(page, plan["title_mm"], scale, px.y, title_rows(fields).size())
	return page


## The page in one line, for a status bar.
static func describe(plan: Dictionary) -> String:
	var page: Vector2 = plan["paper_mm"]
	var still: Rect2 = plan["still_mm"]
	if not bool(plan["fits"]):
		return "a %.0f x %.0f mm sheet with no picture placed" % [page.x, page.y]
	return "a %.0f x %.0f mm sheet with a %.0f x %.0f mm picture (%.2f mm per pixel)" % [
		page.x, page.y, still.size.x, still.size.y, float(plan["scale"]),
	]


static func _or_dash(value: Variant) -> String:
	var text := String(value).strip_edges()
	return text if text != "" else "-"


## A paper-millimetre rectangle in PDF points.
static func _to_points(rect: Rect2, per_mm: float) -> Rect2:
	return Rect2(rect.position * per_mm, rect.size * per_mm)


## A paper-millimetre rectangle in image pixels, flipping y: the sheet's axes go up the
## page and an image's go down it, and this is the one place the two meet.
static func _to_pixels(rect: Rect2, scale: float, page_height_px: int) -> Rect2:
	var x := rect.position.x * scale
	var top_from_top := (page_height_px / scale - rect.position.y - rect.size.y) * scale
	return Rect2(Vector2(round(x), round(top_from_top)), Vector2(round(rect.size.x * scale), round(rect.size.y * scale)))


## A copy of an image scaled to an exact size. A copy rather than a resize in place,
## because the image handed in belongs to the caller.
static func _scaled_copy(image: Image, size: Vector2i) -> Image:
	var out := Image.new()
	out.copy_from(image)
	if out.get_size() != size and size.x > 0 and size.y > 0:
		out.resize(size.x, size.y, Image.INTERPOLATE_LANCZOS)
	return out


## Draw a rectangle outline, `weight` pixels thick, by filling its four edges.
static func _frame(image: Image, rect: Rect2, weight: int, colour: Color) -> void:
	var r := Rect2i(
		int(round(rect.position.x)), int(round(rect.position.y)),
		int(round(rect.size.x)), int(round(rect.size.y))
	)
	if r.size.x <= 0 or r.size.y <= 0:
		return
	var w: int = maxi(weight, 1)
	image.fill_rect(Rect2i(r.position, Vector2i(r.size.x, w)), colour)
	image.fill_rect(Rect2i(Vector2i(r.position.x, r.position.y + r.size.y - w), Vector2i(r.size.x, w)), colour)
	image.fill_rect(Rect2i(r.position, Vector2i(w, r.size.y)), colour)
	image.fill_rect(Rect2i(Vector2i(r.position.x + r.size.x - w, r.position.y), Vector2i(w, r.size.y)), colour)


## The title block's rows into the PDF, caption above value, one row per band.
static func _emit_title(writer, title: Rect2, rows: Array[Dictionary]) -> void:
	var inset: float = 2.0
	var row_h: float = TITLE_BLOCK_ROW_MM
	var x := (title.position.x + inset) * PdfWriterScript.POINTS_PER_MM
	var top := (title.position.y + title.size.y - inset) * PdfWriterScript.POINTS_PER_MM
	var index := 0
	writer.set_fill_colour(INK)
	for row: Dictionary in rows:
		var baseline := top - float(index + 1) * row_h * PdfWriterScript.POINTS_PER_MM
		var label_size: float = LABEL_TEXT_MM * PdfWriterScript.POINTS_PER_MM
		var value_size: float = TITLE_TEXT_MM * PdfWriterScript.POINTS_PER_MM
		writer.draw_text(Vector2(x, baseline + value_size * 1.25), String(row["caption"]), label_size)
		writer.draw_text(Vector2(x, baseline), String(row["value"]), value_size)
		index += 1


## The same rows as rules in the raster preview, one line per row boundary.
static func _emit_title_rules(page: Image, title: Rect2, scale: float, page_height_px: int, rows: int) -> void:
	var rect := _to_pixels(title, scale, page_height_px)
	var bands: int = maxi(rows, 1)
	var w: int = maxi(1, int(round(BORDER_WEIGHT_MM * scale)))
	for index in range(1, bands):
		var y := int(round(rect.position.y + rect.size.y / float(bands) * float(index)))
		page.fill_rect(
			Rect2i(Vector2i(int(rect.position.x), y), Vector2i(int(rect.size.x), w)), INK
		)