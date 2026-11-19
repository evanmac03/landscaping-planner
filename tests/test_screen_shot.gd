extends Node
## The screen shot's own rules, held down where there is no screen to take one with.
##
## The tool's job on a desk is to read a framebuffer, and the test runner has none - its display is a dummy,
## and the tool refuses that question in a sentence rather than making a picture of nothing. So what is held
## here is everything that decides **what the tool says**, which is the part that can be wrong silently: the
## grammar of its verbs and a refusal that names what was missing, the inclusive bounds of a rectangle, the
## colour runs down a column - including that a column too shaded to list says how many runs it left out - and
## the two things that keep a mark or a picture from being read as something they are not.
##
## The files these tests write are scratch under `user://` and each one is put away again. The runner reports
## resources still in use at exit, and a scratch file left behind is a file the next run can read and pass on
## for the wrong reason.

const Shot := preload("res://tools/screen_shot.gd")
const ScreenshotReaderScript := preload("res://scripts/screenshot_reader.gd")

const SCRATCH := "user://the-screen-shot-test.png"
const SCRATCH_CROP := "user://the-screen-shot-test-crop.png"
const SCRATCH_MARK := "user://the-screen-shot-test-mark.png"
const NOT_THERE := "user://there-is-no-picture-at-this-path.png"


## A rectangle is four numbers, and one that is short is refused in a sentence that says how many it got. The
## count is the point: "a rectangle is four numbers" on its own leaves a caller counting their own line.
func test_a_rectangle_is_four_numbers_and_a_short_one_is_refused_by_name() -> void:
	var short: Dictionary = Shot.asked_for(PackedStringArray(["--zoom", "10", "20", "30"]))
	assert(not String(short["complaint"]).is_empty(), "three numbers after --zoom is not a rectangle")
	assert(String(short["complaint"]).contains("3"), String(short["complaint"]))
	assert(String(short["complaint"]).contains("--zoom"), String(short["complaint"]))
	var whole: Dictionary = Shot.asked_for(PackedStringArray(["--zoom", "10", "20", "30", "40"]))
	assert(String(whole["complaint"]).is_empty(), String(whole["complaint"]))
	assert(whole["zoom"] == Rect2i(10, 20, 30, 40), str(whole["zoom"]))
	assert(bool(whole["zoom_asked"]), "a region was asked for, and the tool has to know it")


## A rectangle consumes exactly four numbers, so the fifth word on the line is read as a verb. Reading one
## number further would let `--zoom 1 2 3 4 5` pass as a rectangle and hide the mistake.
func test_a_rectangle_takes_four_numbers_and_the_fifth_word_is_a_verb() -> void:
	var asked: Dictionary = Shot.asked_for(PackedStringArray(["--zoom", "1", "2", "3", "4", "5"]))
	assert(not String(asked["complaint"]).is_empty(), "5 is not one of this tool's verbs")
	assert(String(asked["complaint"]).contains("5"), String(asked["complaint"]))


## Every verb is read where it is written, and a line of good verbs raises no complaint at all.
func test_the_verbs_are_read_off_the_line() -> void:
	var asked: Dictionary = Shot.asked_for(
		PackedStringArray(["--from", "res://build/x.png", "--page", "open_analytics_window"])
	)
	assert(String(asked["complaint"]).is_empty(), String(asked["complaint"]))
	assert(String(asked["from"]) == "res://build/x.png", String(asked["from"]))
	assert(String(asked["page"]) == "open_analytics_window", String(asked["page"]))
	assert(not bool(asked["zoom_asked"]), "nothing asked for a region")


## A verb this tool does not have is refused **and the ones it does have are named**, because a caller who
## mistyped wants the list rather than an argument about the word they used.
func test_a_verb_that_is_not_a_verb_is_refused_and_the_known_ones_named() -> void:
	var asked: Dictionary = Shot.asked_for(PackedStringArray(["--fly"]))
	assert(not String(asked["complaint"]).is_empty(), "--fly is not a verb here")
	assert(String(asked["complaint"]).contains("--fly"), String(asked["complaint"]))
	assert(String(asked["complaint"]).contains("--zoom"), String(asked["complaint"]))


## A verb whose value is missing is refused by name rather than read as an empty string, which would send the
## tool looking for a picture called nothing.
func test_a_verb_with_no_value_is_refused_by_name() -> void:
	var asked: Dictionary = Shot.asked_for(PackedStringArray(["--from"]))
	assert(not String(asked["complaint"]).is_empty(), "--from with nothing after it is not an answer")
	assert(String(asked["complaint"]).contains("--from"), String(asked["complaint"]))


## A region and a rectangle are two different pictures, and one `--to` cannot name two. Refused, rather than
## silently writing whichever the tool happens to test first.
func test_zooming_and_marking_in_one_run_is_refused() -> void:
	var asked: Dictionary = Shot.asked_for(
		PackedStringArray(["--zoom", "1", "2", "3", "4", "--mark", "1", "2", "3", "4"])
	)
	assert(not String(asked["complaint"]).is_empty(), "both in one run is not answered")
	assert(String(asked["complaint"]).contains("not both"), String(asked["complaint"]))


## The colours down a flat column, as the rows they run: three runs, every row accounted for once, and the
## inclusive row numbers a person compares against a rectangle.
func test_the_bands_down_a_flat_column_are_the_rows_they_run() -> void:
	var said := "\n".join(Shot.band_lines(_a_column_picture(), 1, Rect2i(0, 0, 4, 10)))
	assert(said.contains("rows 0..3 (4 px) of ff0000"), said)
	assert(said.contains("rows 4..6 (3 px) of 00ff00"), said)
	assert(said.contains("rows 7..9 (3 px) of 0000ff"), said)


## A column with more runs than the tool prints **says how many it left out**. A shaded surface - the plan
## canvas, a panel lit from one side - is hundreds of runs, and a list that stopped at the cap without saying
## so would be a list pretending to be the whole of the column. The runs are counted from the tool's own cap,
## so raising the cap can never quietly make this test pass for a different reason.
func test_a_column_too_shaded_to_list_says_how_many_runs_it_left_out() -> void:
	var runs: int = Shot.MOST_BANDS + 10
	var picture: Image = Image.create_empty(1, runs, false, Image.FORMAT_RGBA8)
	for y: int in runs:
		picture.set_pixel(0, y, Color(1, 0, 0) if y % 2 == 0 else Color(0, 1, 0))
	var lines: PackedStringArray = Shot.band_lines(picture, 0, Rect2i(0, 0, 1, runs))
	var listed: int = 0
	for line: String in lines:
		if line.begins_with("              rows"):
			listed += 1
	assert(listed == Shot.MOST_BANDS, "the tool prints its cap and not one run more: %d printed" % listed)
	assert("\n".join(lines).contains("10 further run(s)"), "\n".join(lines))


## A column that is not in the picture is refused by name. Reading a column outside it as a column of nothing
## would answer "no marks down here" about a column that does not exist.
func test_a_column_outside_the_picture_is_refused_by_name() -> void:
	var said := "\n".join(Shot.band_lines(_a_column_picture(), 4, Rect2i(0, 0, 4, 10)))
	assert(said.contains("x=4"), said)


## A region is cut out and doubled with every pixel kept square, and the rows printed beside it are the
## **picture's** rows rather than the crop's: the region starts at row 2 and the run above it is still reported
## from row 0, which is the number a rectangle a module states is measured in.
func test_a_region_is_doubled_and_its_rows_are_the_pictures_own() -> void:
	_remove(SCRATCH_CROP)
	var said := "\n".join(Shot.doubled_lines(_a_column_picture(), Rect2i(1, 2, 2, 4), SCRATCH_CROP))
	assert(said.contains("x 1 y 2, 2 x 4"), said)
	assert(said.contains("4 x 8, every pixel kept square"), said)
	assert(said.contains("rows 0..3"), said)
	assert(said.contains("rows 4..6"), said)
	var cut: Image = ScreenshotReaderScript.read(SCRATCH_CROP)
	assert(cut != null, "the region was written where it can be looked at")
	if cut != null:
		assert(cut.get_width() == 4 and cut.get_height() == 8, "%d x %d" % [cut.get_width(), cut.get_height()])
	_remove(SCRATCH_CROP)


## A region with no pixels of the picture in it is refused in a sentence that says which rectangle against
## which picture, and **nothing is written**: an empty file at the path would be read as a region of nothing.
func test_a_region_with_no_pixels_is_refused_and_writes_nothing() -> void:
	_remove(SCRATCH_CROP)
	var said := "\n".join(Shot.doubled_lines(_a_column_picture(), Rect2i(50, 50, 4, 4), SCRATCH_CROP))
	assert(said.contains("no pixels"), said)
	assert(not FileAccess.file_exists(SCRATCH_CROP), "a refused region is not written as an empty picture")


## A mark is an **outline**: it says where the rectangle is and leaves what is inside it readable. A fill would
## hide the very thing a person is looking at the picture to see.
func test_a_mark_is_an_outline_and_leaves_the_middle_alone() -> void:
	_remove(SCRATCH_MARK)
	var picture: Image = Image.create_empty(40, 40, false, Image.FORMAT_RGBA8)
	picture.fill(Color(0, 0, 1))
	var was: Color = picture.get_pixel(20, 20)
	var said := "\n".join(Shot.mark_lines(picture, Rect2i(0, 0, 40, 40), SCRATCH_MARK))
	assert(said.contains("means nothing"), said)
	var marked: Image = ScreenshotReaderScript.read(SCRATCH_MARK)
	assert(marked != null, "the marked picture was written")
	if marked != null:
		assert(marked.get_pixel(0, 0) != Color(0, 0, 1), "the rectangle's own edge is marked")
		assert(marked.get_pixel(20, 20) == was, "the middle is left alone")
	_remove(SCRATCH_MARK)


## A rectangle the picture cannot hold at all is refused by name. A picture written back unchanged would be
## read as "the rectangle is where you said", which is the one answer a mark must never give by accident.
func test_a_rectangle_the_picture_cannot_hold_is_refused_and_writes_nothing() -> void:
	_remove(SCRATCH_MARK)
	var said := "\n".join(Shot.mark_lines(_a_column_picture(), Rect2i(50, 50, 4, 4), SCRATCH_MARK))
	assert(said.contains("not on the picture"), said)
	assert(not FileAccess.file_exists(SCRATCH_MARK), "a mark drawn nowhere is not a fresh picture")


## A picture that is not there is refused by name rather than reported as a picture of nothing.
func test_a_picture_that_is_not_there_is_refused_by_name() -> void:
	var said := "\n".join(Shot.file_lines(NOT_THERE))
	assert(said.contains(NOT_THERE), said)
	assert(said.contains("no picture"), said)


## A picture on disk is reported with its own size and with **when it was written**, which is the line that
## keeps it from being taken for the screen now.
func test_a_picture_on_disk_is_reported_with_its_size_and_when_it_was_written() -> void:
	var picture: Image = Image.create_empty(7, 5, false, Image.FORMAT_RGBA8)
	assert(ScreenshotReaderScript.write(picture, SCRATCH) == OK, "the scratch picture was written")
	var said := "\n".join(Shot.file_lines(SCRATCH))
	assert(said.contains("7 x 5"), said)
	assert(said.contains("written"), said)
	assert(said.contains("ago"), said)
	assert(said.contains("answers"), "the file says out loud that it answers its own question: " + said)
	_remove(SCRATCH)


## How long ago something was written, said coarsely, and a file whose clock is ahead of this machine's named
## as the disagreement it is rather than reported as a negative age.
func test_how_long_ago_is_said_coarsely_and_a_clock_that_disagrees_is_named() -> void:
	var now: int = int(Time.get_unix_time_from_system())
	assert(Shot._ago_from_now(now) == "under a minute ago", Shot._ago_from_now(now))
	assert(Shot._ago_from_now(now - 300) == "5 minute(s) ago", Shot._ago_from_now(now - 300))
	assert(Shot._ago_from_now(now - 7200) == "2 hour(s) ago", Shot._ago_from_now(now - 7200))
	assert(Shot._ago_from_now(now - 172800) == "2 day(s) ago", Shot._ago_from_now(now - 172800))
	assert(Shot._ago_from_now(now + 600).contains("disagree"), Shot._ago_from_now(now + 600))


## The bounds of a rectangle, both ways a person says them. 200 across from x=16 covers x=16 to 215, and 215 is
## the number that has to be compared against the edge it may be past - the off-by-one every reader of a region
## gets wrong once.
func test_a_rectangles_bounds_are_stated_inclusively() -> void:
	var said: String = Shot.rect_words(Rect2i(16, 0, 200, 120))
	assert(said.contains("x 16..215"), said)
	assert(said.contains("y 0..119"), said)


## The picture of a live moment, with the moment named: its size, the room it counts in, and every page that is
## up, each in the probe's own words for it.
func test_the_live_line_names_the_picture_the_room_and_the_pages_that_are_up() -> void:
	var picture: Image = Image.create_empty(100, 60, false, Image.FORMAT_RGBA8)
	var up := PackedStringArray(["page     AnalyticsWindow  \"Analytics\"  at (12, 9) size (474, 700)"])
	var said := "\n".join(
		Shot.live_lines(picture, Vector2i(1600, 900), up, "res://build/the_screen.png", OK)
	)
	assert(said.contains("100 x 60"), said)
	assert(said.contains("1600 x 900"), said)
	assert(said.contains("1 up"), said)
	assert(said.contains("AnalyticsWindow"), said)
	assert(said.contains("res://build/the_screen.png"), said)


## No page up is a reading and is said out loud, because a blank where the pages go reads as a question this
## tool forgot to ask.
func test_no_page_up_is_said_rather_than_left_blank() -> void:
	var picture: Image = Image.create_empty(100, 60, false, Image.FORMAT_RGBA8)
	var said := "\n".join(
		Shot.live_lines(picture, Vector2i(1600, 900), PackedStringArray(), "res://build/the_screen.png", OK)
	)
	assert(said.contains("none is up"), said)


## A picture that could not be written says so and names what refused it, in place of a cheerful line claiming
## a file that is not there.
func test_a_picture_that_could_not_be_written_says_what_refused_it() -> void:
	var picture: Image = Image.create_empty(100, 60, false, Image.FORMAT_RGBA8)
	var said := "\n".join(
		Shot.live_lines(
			picture, Vector2i(1600, 900), PackedStringArray(), "res://nowhere/x.png", ERR_CANT_CREATE
		)
	)
	assert(said.contains("could not be written"), said)
	assert(said.contains("res://nowhere/x.png"), said)
	assert(said.contains(error_string(ERR_CANT_CREATE)), said)


## A four-by-ten picture whose rows are three flat runs: red from row 0 to 3, green to 6, blue to 9. Flat plates
## are what this tool reads - a bar, a rule, the edge of a panel - and the runs of a flat column are the rows a
## rectangle has to be compared against.
func _a_column_picture() -> Image:
	var picture: Image = Image.create_empty(4, 10, false, Image.FORMAT_RGBA8)
	for y: int in 10:
		var colour := Color(1, 0, 0)
		if y >= 4 and y <= 6:
			colour = Color(0, 1, 0)
		elif y >= 7:
			colour = Color(0, 0, 1)
		for x: int in 4:
			picture.set_pixel(x, y, colour)
	return picture


## A scratch file put away again, so nothing here is left for the next run to read.
func _remove(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
