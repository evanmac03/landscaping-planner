extends Node

## Comparing two frames of one screen: the rows that moved grouped into bands, the columns they moved in, the
## pairs that are not the same screen at all, and the fraction of a screen that moved.

const StillnessScript := preload("res://scripts/stillness.gd")

const WIDTH := 8
const HEIGHT := 6


func test_two_frames_of_the_same_still_screen_have_nothing_to_report() -> void:
	var one := _screen()
	var other := _screen()
	assert(StillnessScript.same_shape(one, other), "two frames of one screen are the same shape")
	assert(StillnessScript.bands(one, other).is_empty(), "a screen holding still moved nowhere")


func test_one_pixel_moved_is_one_band_of_one_row() -> void:
	var one := _screen()
	var other := _screen()
	other.set_pixel(3, 2, Color(1, 0, 0))
	var bands: Array[Dictionary] = StillnessScript.bands(one, other)
	assert(bands.size() == 1, "one pixel is one band")
	assert(bands[0]["top"] == 2 and bands[0]["bottom"] == 2, "in the row it happened in")
	assert(bands[0]["left"] == 3 and bands[0]["right"] == 3, "and the column")
	assert(bands[0]["worst"] == 1, "and one pixel of that row moved")


func test_a_whole_row_moved_reports_the_whole_row() -> void:
	var one := _screen()
	var other := _screen()
	for x in WIDTH:
		other.set_pixel(x, 4, Color(0, 1, 0))
	var bands: Array[Dictionary] = StillnessScript.bands(one, other)
	assert(bands.size() == 1)
	assert(bands[0]["across"] == WIDTH, "the whole width moved")
	assert(bands[0]["worst"] == WIDTH, "and every pixel of the row with it")


func test_two_changes_apart_are_two_bands() -> void:
	var one := _screen()
	var other := _screen()
	other.set_pixel(1, 1, Color(1, 1, 1))
	other.set_pixel(1, 4, Color(1, 1, 1))
	var bands: Array[Dictionary] = StillnessScript.bands(one, other)
	assert(bands.size() == 2, "rows 1 and 4 are two places, not one")
	assert(bands[0]["top"] == 1, "the first is the higher row")
	assert(bands[1]["top"] == 4, "and the second is the lower")


func test_two_changes_side_by_side_are_one_band_of_two_rows() -> void:
	var one := _screen()
	var other := _screen()
	other.set_pixel(2, 2, Color(1, 1, 1))
	other.set_pixel(6, 3, Color(1, 1, 1))
	var bands: Array[Dictionary] = StillnessScript.bands(one, other)
	assert(bands.size() == 1, "adjacent rows are one thing moving, not two")
	assert(bands[0]["top"] == 2 and bands[0]["bottom"] == 3, "which covers both of them")
	assert(bands[0]["left"] == 2 and bands[0]["right"] == 6, "and reaches from one change to the other")
	assert(bands[0]["worst"] == 1, "while no single row moved more than one pixel")


func test_the_span_of_a_band_is_not_the_count_of_its_pixels() -> void:
	var one := _screen()
	var other := _screen()
	other.set_pixel(1, 3, Color(1, 1, 1))
	other.set_pixel(7, 3, Color(1, 1, 1))
	var bands: Array[Dictionary] = StillnessScript.bands(one, other)
	assert(bands[0]["worst"] == 2, "two pixels moved")
	assert(bands[0]["across"] == 7, "and they stand seven columns apart, which is what a reader needs")


func test_a_pair_that_is_not_one_screen_is_refused() -> void:
	var one := _screen()
	var other := Image.create(WIDTH + 1, HEIGHT, false, Image.FORMAT_RGBA8)
	assert(not StillnessScript.same_shape(one, other), "different shapes are different screens")
	assert(StillnessScript.bands(one, other).is_empty(), "and nothing is subtracted from them")


func test_an_image_that_is_not_there_is_refused() -> void:
	assert(not StillnessScript.same_shape(null, null), "nothing is not a screen")
	assert(StillnessScript.bands(null, Image.create(2, 2, false, Image.FORMAT_RGBA8)).is_empty())


func test_a_band_reads_as_the_rows_and_columns_it_moved_in() -> void:
	var one := _screen()
	var other := _screen()
	other.set_pixel(2, 2, Color(1, 1, 1))
	other.set_pixel(5, 3, Color(1, 1, 1))
	var bands: Array[Dictionary] = StillnessScript.bands(one, other)
	assert(
		StillnessScript.sentence(bands[0]) == "rows 2..3 moved, at columns 2..5, and at its widest 1 px in one row",
		StillnessScript.sentence(bands[0]),
	)
	assert(
		StillnessScript.sentence(_one_row_band()) == "row 2 moved, at columns 2..2, and at its widest 1 px in one row",
		StillnessScript.sentence(_one_row_band()),
	)


func test_the_share_of_a_screen_that_moved_is_in_rows() -> void:
	var one := _screen()
	var other := _screen()
	for y in 2:
		for x in WIDTH:
			other.set_pixel(x, y, Color(1, 1, 1))
	var bands: Array[Dictionary] = StillnessScript.bands(one, other)
	assert(bands.size() == 1, "two rows together are one band")
	assert(is_equal_approx(StillnessScript.moved_share(bands, HEIGHT), 2.0 / 6.0), "two rows of six")
	assert(
		is_equal_approx(StillnessScript.moved_share([], HEIGHT), 0.0),
		"and a screen that held still is nothing at all",
	)


## A screen of one colour, which is what a still frame is for the purpose of this arithmetic.
func _screen() -> Image:
	var image := Image.create(WIDTH, HEIGHT, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.2, 0.2, 0.25))
	return image


func _one_row_band() -> Dictionary:
	return { "top": 2, "bottom": 2, "left": 2, "right": 2, "across": 1, "worst": 1 }
