extends Node

## The picture read as numbers: where each colour starts and ends down a column, the run of a colour around a
## row, a region handed back doubled, and the two ways a file can be missing without being an error.
##
## The picture is built here rather than loaded, because every question this module is asked is about rows and
## colours and a small picture made in the test states them exactly.

const ScreenshotReaderScript := preload("res://scripts/screenshot_reader.gd")

## The two colours the picture is made of, stated as the byte over 255 that an `Image` will actually keep: a
## picture quantises every colour to eight bits a channel, so a test that compared against `Color(0.157, ...)`
## would be comparing against a number the picture never held.
const DARK := Color(40.0 / 255.0, 40.0 / 255.0, 40.0 / 255.0)
const LIGHT := Color(242.0 / 255.0, 242.0 / 255.0, 242.0 / 255.0)


## A 4 by 10 picture: 3 rows of `DARK`, 4 of `LIGHT`, then 3 of `DARK` again.
func _a_picture() -> Image:
	var image := Image.create_empty(4, 10, false, Image.FORMAT_RGBA8)
	image.fill_rect(Rect2i(0, 0, 4, 10), DARK)
	image.fill_rect(Rect2i(0, 3, 4, 4), LIGHT)
	return image


## A blank picture of any size, in the one colour, so that what a drawn number inks can be read off it.
func _a_blank(w: int, h: int) -> Image:
	var image := Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
	image.fill_rect(Rect2i(0, 0, w, h), DARK)
	return image


## **A number is laid above the rectangle's corner where there is room, and on the corner where there is not** - the
## one rule the two tools that draw numbers share, and it lives here because this is the module that draws them. A
## number laid over a caption covers the words a person is matching it to; a number above a control standing in the
## screen's own top rows would be off the picture entirely.
func test_a_number_is_laid_above_the_corner_or_on_it_when_there_is_no_room() -> void:
	var plate := Color(0.0, 0.0, 0.0, 1.0)
	var ink := Color(1.0, 1.0, 1.0, 1.0)
	var no_room := _a_blank(60, 40)
	ScreenshotReaderScript.numbered(no_room, Rect2i(10, 4, 40, 20), 7, plate, ink, 2)
	assert(no_room.get_pixel(10, 4) != DARK, "with nothing above it, the number is laid on the corner itself")

	var roomy := _a_blank(60, 40)
	ScreenshotReaderScript.numbered(roomy, Rect2i(10, 30, 40, 20), 7, plate, ink, 2)
	var plate_height: int = ScreenshotReaderScript.GLYPH_DOWN * 2 + 2
	assert(
		roomy.get_pixel(10, 30 - plate_height) != DARK,
		"and with room above it, the number stands above the corner rather than over the caption"
	)
	assert(roomy.get_pixel(10, 30) == DARK, "so the control's own words are left alone")

	var untouched: PackedByteArray = roomy.get_data()
	ScreenshotReaderScript.numbered(null, Rect2i(0, 0, 10, 10), 3, plate, ink, 2)
	assert(roomy.get_data() == untouched, "and no picture at all is not a reason to fail")


## **A digit is five by seven and the width says so**, which is the whole of the label's vocabulary - the table's
## own shape, stated once in the module so that the drawer and the measurer cannot disagree about it.
func test_a_number_is_five_by_seven_a_digit_and_its_width_says_so() -> void:
	assert(ScreenshotReaderScript.label_width("12", 2) == 20, "two digits at twice the size, twenty pixels")
	assert(ScreenshotReaderScript.label_width("123", 1) == 15, "and at their own size, five pixels each")
	assert(
		ScreenshotReaderScript.label_width("#12", 2) == 30,
		"a character the table does not have still takes its room, so what follows is not drawn over it"
	)


## **An `8` comes out the way the table has it, at the size it was asked for** - and nothing outside that box. The
## pixel assertions are the ones that would catch a table transcribed sideways or a scale applied to one axis only,
## which a count of inked pixels could not tell apart.
func test_a_digit_is_drawn_as_the_table_has_it_and_only_inside_its_own_box() -> void:
	var image := _a_blank(24, 20)
	ScreenshotReaderScript.label(image, Vector2i(2, 2), "8", LIGHT, 2)
	# An `8` is `01110` on its top row: at scale 2 its first column is x 2..3 and its third is x 6..7.
	assert(image.get_pixel(2, 2).is_equal_approx(DARK), "the first column of an 8's top row is a gap")
	assert(image.get_pixel(3, 2).is_equal_approx(DARK), "and the whole of that gap, not one pixel of it")
	assert(not image.get_pixel(6, 2).is_equal_approx(DARK), "while the third column of the top row is drawn")
	assert(image.get_pixel(20, 2).is_equal_approx(DARK), "nothing is drawn past the number's own width")
	assert(image.get_pixel(2, 18).is_equal_approx(DARK), "nor past its own height")


## A character the table does not have is **a blank and not a failure**: the block's own lines write `#` before a
## number, and a caller hands over what the line said, so the drawer takes that room and leaves the paper alone
## rather than stopping or inventing a shape.
func test_a_character_the_table_does_not_have_takes_its_room_and_draws_nothing() -> void:
	var image := _a_blank(30, 20)
	var before: PackedByteArray = image.get_data()
	ScreenshotReaderScript.label(image, Vector2i(1, 1), "#", LIGHT, 2)
	assert(image.get_data() == before, "nothing is drawn for it")
	assert(ScreenshotReaderScript.label_width("#", 2) == 10, "and it still takes a column's worth of room")


## **A number is only drawn where there is paper.** A control standing at the very edge of a phone's screen is
## exactly where this happens, and the capture a tool has just pulled off a device is the last picture that should
## be lost to a number drawn one block too far right - `Image` treats a pixel outside itself as an error rather
## than as nothing.
##
## The label is placed so that part of it is on the paper and part is not, and the part that is *drawn* is a block
## the table inks rather than the blank corner of a digit: a number whose only visible pixel is a gap would prove
## nothing about clamping.
func test_a_number_reaching_past_the_edge_is_drawn_as_far_as_there_is_picture() -> void:
	var image := _a_blank(12, 12)
	ScreenshotReaderScript.label(image, Vector2i(4, 4), "88", LIGHT, 2)
	var inked: bool = false
	for down: int in 12:
		for across: int in 12:
			if not image.get_pixel(across, down).is_equal_approx(DARK):
				inked = true
	assert(inked, "the part of the number that is on the picture is drawn")
	var before: PackedByteArray = image.get_data()
	ScreenshotReaderScript.label(image, Vector2i(-100, -100), "8", LIGHT, 2)
	ScreenshotReaderScript.label(image, Vector2i(200, 200), "8", LIGHT, 2)
	assert(image.get_data() == before, "and a number wholly off the picture draws nothing and breaks nothing")


func test_bands_down_says_the_rows_each_colour_runs_from_and_to() -> void:
	var bands: Array[Dictionary] = ScreenshotReaderScript.bands_down(_a_picture(), 1)
	assert(bands.size() == 3, "two changes of colour make three runs")
	assert(bands[0]["from"] == 0 and bands[0]["to"] == 2, "the first run is rows 0 to 2")
	assert(bands[1]["from"] == 3 and bands[1]["to"] == 6, "the light run is rows 3 to 6")
	assert(bands[2]["from"] == 7 and bands[2]["to"] == 9, "the last run reaches the last row")
	assert((bands[1]["colour"] as Color).is_equal_approx(LIGHT), "each run carries the colour it was made of")


func test_a_column_outside_the_picture_says_nothing_rather_than_failing() -> void:
	var image := _a_picture()
	assert(ScreenshotReaderScript.bands_down(image, 4).is_empty(), "one past the last column is not a column")
	assert(ScreenshotReaderScript.bands_down(image, -1).is_empty(), "and neither is one before the first")
	assert(ScreenshotReaderScript.bands_down(null, 0).is_empty(), "no picture at all is answered the same way")


func test_the_band_containing_a_row_is_the_whole_run_of_that_colour() -> void:
	var image := _a_picture()
	var band: Dictionary = ScreenshotReaderScript.band_containing(image, 1, 4)
	assert(band["from"] == 3 and band["to"] == 6, "from the middle of the light run the whole of it comes back")
	assert(ScreenshotReaderScript.rows(band) == 4, "four rows is 3 to 6, both ends included")


func test_a_band_that_reaches_the_edge_is_not_cut_short() -> void:
	var image := _a_picture()
	var first: Dictionary = ScreenshotReaderScript.band_containing(image, 1, 0)
	assert(first["from"] == 0, "a run that starts at the top edge starts at row 0")
	var last: Dictionary = ScreenshotReaderScript.band_containing(image, 1, 9)
	assert(last["to"] == 9, "and one that reaches the foot ends on the last row")


func test_a_row_outside_the_picture_is_not_a_band() -> void:
	assert(
		ScreenshotReaderScript.band_containing(_a_picture(), 1, 10).is_empty(),
		"a row the picture does not have is answered with nothing",
	)


func test_doubling_a_region_gives_the_same_pixels_twice_as_big() -> void:
	var image := _a_picture()
	var big: Image = ScreenshotReaderScript.doubled(image, Rect2i(0, 3, 4, 4))
	assert(big.get_width() == 8 and big.get_height() == 8, "four by four doubled is eight by eight")
	assert(big.get_pixel(0, 0).is_equal_approx(LIGHT), "the top left of the region is where it was")
	assert(big.get_pixel(7, 7).is_equal_approx(LIGHT), "and the simplest enlargement keeps every pixel its own colour")


func test_a_region_that_runs_off_the_picture_is_clamped_not_refused() -> void:
	var image := _a_picture()
	var big: Image = ScreenshotReaderScript.doubled(image, Rect2i(2, 8, 8, 8))
	assert(big != null, "a region that hangs over the edge is still read")
	assert(big.get_width() == 4 and big.get_height() == 4, "two columns and two rows are what was there")


func test_a_region_entirely_off_the_picture_has_nothing_to_give() -> void:
	var image := _a_picture()
	assert(ScreenshotReaderScript.doubled(image, Rect2i(20, 20, 4, 4)) == null, "no picture of nothing")
	assert(ScreenshotReaderScript.doubled(null, Rect2i(0, 0, 4, 4)) == null, "and none from no picture")


func test_a_picture_that_is_not_there_is_answered_with_nothing() -> void:
	assert(
		ScreenshotReaderScript.read("user://a-picture-that-was-never-taken.png") == null,
		"a file that is not there is not an error, it is an empty answer",
	)


func test_a_write_goes_through_a_temporary_file_and_arrives() -> void:
	var to := "user://test-screenshot-reader.png"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(to))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(to + ".writing"))
	var failed: Error = ScreenshotReaderScript.write(_a_picture(), to)
	assert(failed == OK, "writing a picture that is there is OK")
	assert(FileAccess.file_exists(to), "and the picture is where it was asked for")
	assert(not FileAccess.file_exists(to + ".writing"), "with no leftover work in progress beside it")
	var back: Image = ScreenshotReaderScript.read(to)
	assert(back != null and back.get_width() == 4, "and reading it back gives the picture again")
	assert(ScreenshotReaderScript.write(null, to) == ERR_INVALID_PARAMETER, "no picture is not something to write")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(to))


## **A claim and the pixels it is a claim about, in one picture.** A rectangle on its own is a statement by the
## program about itself; drawing it on the framebuffer is what makes it checkable. So the edge is marked and what
## is inside is left alone - a mark that covered the rows it points at would be worse than none.
func test_a_rectangle_is_marked_on_the_edge_without_hiding_what_is_under_it() -> void:
	var image := _a_picture()
	ScreenshotReaderScript.outline(image, Rect2i(1, 4, 3, 3), Color(1.0, 0.0, 0.0, 0.5), 1)
	assert(
		not image.get_pixel(1, 4).is_equal_approx(LIGHT),
		"the rectangle's own corner is marked, where the picture had LIGHT",
	)
	assert(
		image.get_pixel(2, 5).is_equal_approx(LIGHT),
		"the middle of a 3 by 3 is a pixel beyond the 1 px edge, and is left as the picture had it",
	)
	assert(image.get_pixel(0, 0).is_equal_approx(DARK), "nothing outside the rectangle is touched")


## A rectangle reaching off the picture, one wholly off it, and one given no thickness: three ways of asking for a
## mark the picture has no room for, and none of them is an error.
func test_a_mark_the_picture_has_no_room_for_is_clamped_and_not_refused() -> void:
	var image := _a_picture()
	ScreenshotReaderScript.outline(image, Rect2i(3, 9, 8, 8), Color.RED, 1)
	assert(image.get_pixel(3, 9).is_equal_approx(Color.RED), "the part of it that is on the picture is drawn")
	ScreenshotReaderScript.outline(image, Rect2i(20, 20, 4, 4), Color.RED, 1)
	assert(
		ScreenshotReaderScript.doubled(image, Rect2i(20, 20, 4, 4)) == null,
		"the part that is not on the picture is not drawn, and cannot be read either",
	)
	ScreenshotReaderScript.outline(image, Rect2i(0, 0, 4, 4), Color.RED, 0)
	assert(image.get_pixel(0, 0).is_equal_approx(DARK), "a thickness of nothing leaves the picture as it was")
	# A rectangle handed to no picture at all is a call with nothing to draw on, and must not be an error.
	ScreenshotReaderScript.outline(null, Rect2i(0, 0, 4, 4), Color.RED, 1)
