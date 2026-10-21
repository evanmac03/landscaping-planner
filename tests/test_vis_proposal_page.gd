extends Node
## Tests for the proposal page: a still laid on a titled sheet, as a PDF and as a preview
## image, and for the image-XObject support in the PDF writer that makes the PDF real.
##
## The facts worth pinning are geometric rather than visual: the picture keeps its aspect,
## it lands inside the sheet's own drawing area, the furniture is the sheet's own sizes,
## and a page with no picture is refused rather than written with a hole in it.

const Page := preload("res://scripts/vis/proposal_page.gd")
const Preset := preload("res://scripts/vis/still_preset.gd")
const PdfWriter := preload("res://scripts/draft/pdf_writer.gd")

const A3 := Vector2(420.0, 297.0)


func _still(width: int = 1600, height: int = 900, colour: Color = Color(0.4, 0.6, 0.3)) -> Image:
	var image := Image.create(width, height, false, Image.FORMAT_RGB8)
	image.fill(colour)
	return image


## Two colours the same to within a byte. An eight-bit image quantises a float colour, so
## a fill of 0.945 reads back as 0.941 - close enough to be the colour, too far for
## `is_equal_approx`, whose tolerance is a hundredth of a thousandth.
func _similar(a: Color, b: Color, eps: float = 0.01) -> bool:
	return absf(a.r - b.r) < eps and absf(a.g - b.g) < eps and absf(a.b - b.b) < eps


func test_a_page_keeps_the_pictures_aspect() -> void:
	var plan: Dictionary = Page.layout(A3, Vector2i(1600, 900))
	assert(bool(plan["fits"]), "a 16:9 still fits an A3 sheet")
	var size: Vector2 = plan["still_mm"].size
	# The picture is one scale on both axes, so the ratio it arrived with is the ratio it
	# is drawn at - stretching a garden to fill a box is a lie about the garden.
	assert(is_equal_approx(size.x / size.y, 1600.0 / 900.0), "the aspect moved: %s" % size)


func test_the_picture_lands_inside_the_drawing_area() -> void:
	var plan: Dictionary = Page.layout(A3, Vector2i(1600, 900))
	var area: Rect2 = plan["area_mm"]
	var still: Rect2 = plan["still_mm"]
	assert(area.encloses(still), "the picture sits inside the area: %s vs %s" % [still, area])
	# And centred in it, to within a rounding of a millimetre.
	var gap_left: float = still.position.x - area.position.x
	var gap_right: float = area.end.x - still.end.x
	assert(absf(gap_left - gap_right) < 0.5, "the picture is centred across the area")
	var gap_bottom: float = still.position.y - area.position.y
	var gap_top: float = area.end.y - still.end.y
	assert(absf(gap_bottom - gap_top) < 0.5, "the picture is centred up the area")


func test_the_furniture_is_the_sheets_own() -> void:
	var plan: Dictionary = Page.layout(A3, Vector2i(1600, 900))
	var border: Rect2 = plan["border_mm"]
	var title: Rect2 = plan["title_mm"]
	# The border is inset by the sheet's own margin, and the title block is the sheet's
	# own size, struck to the right edge along the foot.
	assert(is_equal_approx(border.position.x, Page.BORDER_INSET_MM), "the border is inset as the sheet insets it")
	assert(is_equal_approx(title.size.x, Page.TITLE_BLOCK_WIDTH_MM), "the title block is the sheet's width")
	assert(is_equal_approx(title.size.y, Page.TITLE_BLOCK_HEIGHT_MM), "and the sheet's height")
	assert(is_equal_approx(title.end.x, border.end.x), "struck to the right edge")
	assert(is_equal_approx(title.position.y, border.position.y), "lying along the foot")
	# The drawing sits above the title block, not over it.
	assert(plan["area_mm"].position.y > title.end.y, "the picture clears the title block")


func test_a_page_with_no_picture_still_lays_out_the_furniture() -> void:
	var plan: Dictionary = Page.layout(A3, Vector2i.ZERO)
	assert(not bool(plan["fits"]), "there is no picture, so it does not fit")
	assert(plan["border_mm"].size.x > 0.0, "the frame is still laid out so it can be drawn and explained")
	assert(Page.describe(plan).contains("no picture"), "and describe says so")


func test_a_sheet_of_no_size_defaults_to_a3_rather_than_nothing() -> void:
	var plan: Dictionary = Page.layout(Vector2.ZERO, Vector2i(100, 100))
	assert(is_equal_approx(plan["paper_mm"].x, A3.x), "a page of no size is A3")


func test_an_embedded_still_is_never_enlarged_and_never_over_the_cap() -> void:
	# Smaller than the cap: left exactly as it is.
	assert(Page.embedding_size(Vector2i(1600, 900)) == Vector2i(1600, 900), "a small still is kept")
	# Over the cap: scaled down on the long side, aspect kept.
	var capped: Vector2i = Page.embedding_size(Vector2i(4961, 3508))
	assert(maxi(capped.x, capped.y) == Page.MAX_EMBED_PX, "the long side is brought to the cap")
	# A pixel of rounding on the short side is the most the aspect can move, so the two
	# ratios agree to within a hundredth rather than exactly.
	var ratio: float = float(capped.x) / float(capped.y)
	assert(absf(ratio - 4961.0 / 3508.0) < 0.01, "the aspect is kept: %s" % capped)
	assert(Page.embedding_size(Vector2i.ZERO) == Vector2i.ZERO, "nothing stays nothing")


func test_the_title_block_is_four_rows_and_a_missing_value_is_a_dash() -> void:
	var rows: Array[Dictionary] = Page.title_rows({"project": "Maple Street", "scale": "1:100"})
	assert(rows.size() == 4, "the block is four rows")
	assert(String(rows[0]["value"]) == "Maple Street")
	assert(String(rows[1]["value"]) == "-", "a value nobody gave reads as a dash, not as nothing")
	var last := String(rows[3]["value"])
	assert(last.contains("1:100"), "the last row carries the scale: %s" % last)


func test_the_page_image_is_the_paper_at_the_resolution() -> void:
	var plan: Dictionary = Page.layout(A3, Vector2i(1600, 900))
	var image: Image = Page.render_image(_still(), A3, {}, 60.0)
	assert(image != null, "a page was drawn")
	assert(image.get_size() == Page.page_pixels(plan, 60.0), "the page is its own size: %s" % image.get_size())
	# The corner is bare paper; the middle carries the picture.
	assert(_similar(image.get_pixel(1, 1), Page.PAPER), "the corner is paper")
	var found := false
	for y in range(0, image.get_height(), 4):
		for x in range(0, image.get_width(), 4):
			if _similar(image.get_pixel(x, y), Color(0.4, 0.6, 0.3)):
				found = true
				break
		if found:
			break
	assert(found, "the picture is on the page")


func test_a_pdf_page_embeds_the_picture_for_real() -> void:
	var pdf: PackedByteArray = Page.build_pdf(_still(), A3, {"project": "Maple Street", "view": "3D presentation"})
	assert(not pdf.is_empty(), "a page was written")
	var text := pdf.get_string_from_utf8()
	assert(text.begins_with("%PDF-1.4"), "it is a PDF")
	assert(text.contains("/Subtype /Image"), "the picture is an image XObject")
	assert(text.contains("/ColorSpace /DeviceRGB"), "in RGB")
	assert(text.contains("/Filter /FlateDecode"), "deflated")
	assert(text.contains("/XObject << /Im1 6 0 R >>"), "the page names the image it draws")
	assert(text.contains("/Im1 Do"), "and the content stream draws it")
	# The typed-in words really reach the file.
	assert(text.contains("Maple Street"), "the project reached the sheet")
	assert(text.contains("3D presentation"), "and so did the view")
	# The trailer comes *after* the image's deflated samples, which contain a NUL byte and
	# so truncate `get_string_from_utf8` at the image. The end of the file is read from its
	# own bytes, which is the only honest way to look at a file with binary in it.
	var tail := pdf.slice(pdf.size() - 32, pdf.size()).get_string_from_utf8()
	assert(tail.contains("startxref"), "the cross-reference is there: %s" % tail)
	assert(tail.contains("%%EOF"), "and the file is closed properly")


func test_a_pdf_with_no_picture_is_refused_rather_than_written_with_a_hole() -> void:
	assert(Page.build_pdf(null, A3, {}).is_empty(), "no image, no page")
	assert(Page.build_pdf(Image.new(), A3, {}).is_empty(), "an empty image is no page")


func test_the_writer_leaves_a_page_with_no_image_exactly_as_it_was() -> void:
	# The image support must not disturb the plotted sheet: a page that places nothing
	# still says nothing about XObjects.
	var writer = PdfWriter.new()
	writer.begin_page(100.0, 50.0)
	var pdf: PackedByteArray = writer.build()
	var text := pdf.get_string_from_utf8()
	assert(not text.contains("/XObject"), "a page with no picture names no XObjects")
	assert(text.contains("/Resources << /Font << /F1 5 0 R >> >>"), "and the resources are as they were")


func test_the_writer_registers_a_placed_image_under_a_name_and_draws_it() -> void:
	var writer = PdfWriter.new()
	writer.begin_page(100.0, 50.0)
	var name: String = writer.place_image(_still(8, 4), Rect2(10.0, 20.0, 40.0, 15.0))
	assert(name == "/Im1", "the first image is the first name")
	assert(writer.images().size() == 1, "it is held for the build")
	var stream: String = writer.content()
	assert(stream.contains("40.0 0 0 15.0 10.0 20.0 cm /Im1 Do"), "the image fills the rectangle: %s" % stream)
	# A second image is a second name.
	assert(writer.place_image(_still(8, 4), Rect2(0.0, 0.0, 5.0, 5.0)) == "/Im2", "the second image is the second name")
	# Nothing to place is refused rather than named.
	assert(writer.place_image(null, Rect2(0.0, 0.0, 5.0, 5.0)) == "", "a missing image is not placed")
	assert(writer.place_image(_still(4, 4), Rect2(0.0, 0.0, 0.0, 5.0)) == "", "a rectangle of no width is not placed")


func test_an_image_object_is_the_samples_it_was_given() -> void:
	var image := _still(4, 3, Color(0.2, 0.4, 0.6))
	var object: PackedByteArray = PdfWriter.image_object(image)
	var text := object.get_string_from_utf8()
	assert(text.contains("/Width 4 /Height 3"), "the object states its size")
	assert(text.contains("/BitsPerComponent 8"), "at eight bits a channel")
	assert(text.contains("stream"), "and carries a stream")


func test_the_page_and_the_still_agree_about_the_sheet() -> void:
	# A page laid out for a preset's paper takes that preset's paper, so a proposal page
	# and the still it holds are the same deliverable.
	var paper: Vector2 = Preset.paper_mm(Preset.PROPOSAL_DEFAULT)
	var plan: Dictionary = Page.layout(paper, Preset.size(Preset.PROPOSAL_DEFAULT))
	assert(bool(plan["fits"]), "an A3 still fits an A3 page")
	assert(Page.page_pixels(plan, Preset.dpi(Preset.PROPOSAL_DEFAULT)) == Preset.size(Preset.PROPOSAL_DEFAULT),
		"the page comes to the still's own pixel size")