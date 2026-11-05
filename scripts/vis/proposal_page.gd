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
## A proposal also has to answer "what is on site now?", so the page can carry photographs beneath the
## still: each one framed, each captioned in a person's words (`photo_bands`). The caller hands in loaded
## images and captions - this page reads no files and invents no words - and the photographs take a strip
## of paper that the still gives up, so nothing is ever pasted over the drawing.
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
## The depth of paper the photographs take along the foot of the drawing area, when the page carries any.
const PHOTO_STRIP_MM := 46.0
## Air between two photographs.
const PHOTO_GAP_MM := 4.0
## At most three photographs on one page. A fourth would be a postage stamp, and the page states how many
## it left out rather than shrinking them past being read - a proposal that quietly dropped a photograph
## someone took is worse than one that says it ran out of room.
const PHOTO_MAX := 3
## The band along the foot of each photograph that its caption is written in, and the caption's text size.
const PHOTO_CAPTION_MM := 7.0
const PHOTO_TEXT_MM := 2.4
## The widest a photograph's slot is allowed to be. Two bands across an A3 sheet are 188 mm each, and a
## strip-height picture fitted into one of those is a stamp in the middle of a field of paper - so the row
## is laid out in slots of a sane width and centred, and a page with one photograph has one slot and no
## pretend room for two more.
const PHOTO_SLOT_MAX_MM := 96.0
## The tint a proof sheet prints where words will go. The caption itself is the PDF's - drawing glyphs into
## an image needs a canvas - and a future reader who sees this tint knows a sentence belongs there.
const PHOTO_PLACEHOLDER := Color(0.86, 0.85, 0.82)
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
	# The picture sits above the title block strip, inside the border and the margin. Photographs, when
	# the page carries any, take a strip along the foot of that area: the still gives up the room rather
	# than the photographs being pasted over the plan, because the picture *is* the proposal.
	var strip: float = _strip_for(options)
	var foot: float = border.position.y + title_h + TITLE_BLOCK_CLEARANCE_MM
	var room: float = border.size.y - title_h - TITLE_BLOCK_CLEARANCE_MM - margin * 2.0
	var photos := Rect2()
	var lift := 0.0
	if strip > 0.0:
		# A strip that would eat the picture is not a strip: the still keeps at least half the area, and a
		# page with no room for photographs lays out none rather than squeezing the drawing to nothing.
		strip = minf(strip, maxf(room * 0.5 - PHOTO_GAP_MM, 0.0))
		if strip > 0.0:
			photos = Rect2(
				Vector2(border.position.x + margin, foot),
				Vector2(border.size.x - margin * 2.0, strip)
			)
			room -= strip + PHOTO_GAP_MM
			# The strip is carved out of the foot of the area, so the drawing begins *above* it: a picture
			# centred in a box that still includes the strip's paper would be drawn over the photographs.
			lift = strip + PHOTO_GAP_MM
	var area := Rect2(
		Vector2(border.position.x + margin, foot + lift),
		Vector2(border.size.x - margin * 2.0, room)
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
		"photos_mm": photos,
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
	_emit_photos(writer, plan["photos_mm"], options)

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
	_render_photos(page, plan["photos_mm"], scale, px.y, options)
	# The title block's rules, one line per row the block actually has - so the preview
	# shows the structure of the block the PDF will fill in.
	_emit_title_rules(page, plan["title_mm"], scale, px.y, title_rows(fields).size())
	return page


## How much paper the photographs need: what the caller asked for, or the page's own depth when it was
## handed photographs and did not say how deep to make them. One place, so the still, the preview and the
## PDF cannot disagree about how much room was given up.
static func _strip_for(options: Dictionary) -> float:
	var asked: float = float(options.get("photo_strip_mm", 0.0))
	if asked > 0.0:
		return asked
	var photos: Array = options.get("photos", [])
	return PHOTO_STRIP_MM if not photos.is_empty() else 0.0


## The bands the photographs are laid out in across a strip, left to right, and how many were left out.
##
## Returns `{bands: Array[Rect2], shown, dropped}`. Bands are equal width with a gutter between them, so a
## page with three photographs and a page with one are the same page with a different number of pictures.
## `dropped` is what the caller states in words: a page that cannot show them all says so.
static func photo_bands(count: int, strip_mm: Rect2, max_count: int = PHOTO_MAX) -> Dictionary:
	var bands: Array[Rect2] = []
	var wanted: int = maxi(count, 0)
	if wanted == 0 or strip_mm.size.x <= 0.0 or strip_mm.size.y <= 0.0:
		return {"bands": bands, "shown": 0, "dropped": wanted}
	var taken: int = mini(wanted, maxi(max_count, 0))
	if taken == 0:
		return {"bands": bands, "shown": 0, "dropped": wanted}
	# Narrow enough to be a photograph rather than a field of paper, and never so wide that a row of them
	# runs past the strip.
	var width: float = minf(
		(strip_mm.size.x - PHOTO_GAP_MM * float(taken - 1)) / float(taken), PHOTO_SLOT_MAX_MM
	)
	if width <= 0.0:
		return {"bands": bands, "shown": 0, "dropped": wanted}
	var row: float = width * float(taken) + PHOTO_GAP_MM * float(taken - 1)
	var left: float = strip_mm.position.x + (strip_mm.size.x - row) * 0.5
	for index in range(taken):
		bands.append(Rect2(
			Vector2(left + float(index) * (width + PHOTO_GAP_MM), strip_mm.position.y),
			Vector2(width, strip_mm.size.y)
		))
	return {"bands": bands, "shown": taken, "dropped": wanted - taken}


## The part of a band the picture itself goes in: the band less its caption, which lies along the foot.
static func photo_picture_rect(band_mm: Rect2) -> Rect2:
	return Rect2(
		band_mm.position,
		Vector2(band_mm.size.x, maxf(band_mm.size.y - PHOTO_CAPTION_MM, 0.0))
	)


## A photograph fitted inside a band, centred, at one scale on both axes - the same rule as the still,
## because a photograph stretched to fill a box is a lie about the thing in it.
static func _fit_rect(inside: Rect2, size_px: Vector2i) -> Rect2:
	if size_px.x <= 0 or size_px.y <= 0 or inside.size.x <= 0.0 or inside.size.y <= 0.0:
		return Rect2()
	var fit: float = minf(inside.size.x / float(size_px.x), inside.size.y / float(size_px.y))
	var size := Vector2(float(size_px.x) * fit, float(size_px.y) * fit)
	return Rect2(inside.position + (inside.size - size) * 0.5, size)


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


## The photographs into the PDF: each fitted inside its band at one scale, framed, and captioned along its
## foot in the page's own ink. `options["photos"]` is a list of `{image: Image, caption: String}` - loaded
## by the caller, because this page reads no files and would not know what a good caption is anyway.
static func _emit_photos(writer, strip: Rect2, options: Dictionary) -> void:
	var photos: Array = options.get("photos", [])
	var laid: Dictionary = photo_bands(photos.size(), strip, int(options.get("photo_max", PHOTO_MAX)))
	var bands: Array = laid["bands"]
	if bands.is_empty():
		return
	var per_mm: float = PdfWriterScript.POINTS_PER_MM
	var size: float = PHOTO_TEXT_MM * per_mm
	writer.set_line_width_points(maxf(PICTURE_FRAME_MM * per_mm, 0.1))
	writer.set_stroke_colour(INK)
	writer.set_fill_colour(INK)
	var index := 0
	for band: Rect2 in bands:
		var entry: Dictionary = {}
		if photos[index] is Dictionary:
			entry = photos[index]
		var image: Image = entry.get("image") as Image
		var picture: Rect2 = photo_picture_rect(band)
		if image != null and not image.is_empty():
			var placed: Rect2 = _fit_rect(picture, image.get_size())
			writer.place_image(image, _to_points(placed, per_mm))
			writer.rectangle(_to_points(placed, per_mm))
			writer.stroke()
		# The words go under their own photograph and never over its neighbour: a caption too long for its
		# band ends in dots, which is a page short of room rather than a sentence across the border.
		var words: String = SheetExporterScript.clipped_text(
			writer, String(entry.get("caption", "")), size, band.size.x * per_mm
		)
		if not words.is_empty():
			writer.draw_text(
				Vector2(band.position.x * per_mm, band.position.y * per_mm + size), words, size
			)
		index += 1


## The same bands in the raster preview: each photograph fitted and framed where the PDF puts it, and a box
## where its caption will be printed. The words themselves are the PDF's job - see the class note, drawing
## glyphs needs a canvas item - so the preview shows where the sentence lands and the file carries it.
static func _render_photos(
	page: Image, strip: Rect2, scale: float, page_height_px: int, options: Dictionary
) -> void:
	var photos: Array = options.get("photos", [])
	var laid: Dictionary = photo_bands(photos.size(), strip, int(options.get("photo_max", PHOTO_MAX)))
	var bands: Array = laid["bands"]
	if bands.is_empty():
		return
	var frame_w: int = maxi(1, int(round(PICTURE_FRAME_MM * scale)))
	var index := 0
	for band: Rect2 in bands:
		var entry: Dictionary = {}
		if photos[index] is Dictionary:
			entry = photos[index]
		var image: Image = entry.get("image") as Image
		var picture: Rect2 = photo_picture_rect(band)
		if image != null and not image.is_empty():
			# Fitted the same way the PDF fits it, so the preview and the file cannot disagree about where
			# a photograph sits or how much of its band it fills.
			var target: Rect2 = _to_pixels(_fit_rect(picture, image.get_size()), scale, page_height_px)
			var fitted: Image = _scaled_copy(
				image, Vector2i(maxi(1, int(target.size.x)), maxi(1, int(target.size.y)))
			)
			if fitted.get_format() != page.get_format():
				fitted.convert(page.get_format())
			page.blend_rect(
				fitted, Rect2i(Vector2i.ZERO, fitted.get_size()), Vector2i(target.position)
			)
			_frame(page, target, frame_w, INK)
		var caption: Rect2 = _to_pixels(
			Rect2(band.position, Vector2(band.size.x, PHOTO_CAPTION_MM)), scale, page_height_px
		)
		# A tint rather than an empty box: a proof of the page shows where the sentence will be printed, and
		# an outlined box with nothing in it reads as a mistake to anybody looking at the preview.
		if caption.size.x >= 1.0 and caption.size.y >= 1.0:
			page.fill_rect(
				Rect2i(Vector2i(caption.position), Vector2i(caption.size)), PHOTO_PLACEHOLDER
			)
		index += 1