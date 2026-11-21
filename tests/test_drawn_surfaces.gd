extends Node
## The surfaces that are drawn, held to the one rule that says which of them may share rows.
##
## Nothing here needs a tree or a screen: this module compares rectangles it is handed, and every one of them
## is measured somewhere else. The faults it is written for are the two that the suite, the audit and the page
## measurement all passed while a person could see them: a page's title bar over the menu titles, and two
## pages' titles in the same rows.

const DrawnSurfacesScript := preload("res://scripts/drawn_surfaces.gd")

## The foot line's own sentence, as the probe reads it back on the desk. It is one line of words on a plate, and
## the two tests below are about what it is drawn over.
const THE_FOOT_SENTENCE := (
	"Left-drag: move a plant     Right-drag: pan     Wheel: zoom     "
	+ "W A S D: pan     F: fit     Q: 2D plan     G: ground"
)


func test_two_pages_titles_may_not_share_rows() -> void:
	var surfaces: Array = [
		DrawnSurfacesScript.bar_of("the figures", Rect2i(210, 98, 1180, 802), 36),
		DrawnSurfacesScript.bar_of("the camera", Rect2i(210, 120, 1180, 600), 36),
	]
	var found: Array[Dictionary] = DrawnSurfacesScript.meetings(surfaces)
	assert(found.size() == 1, "two title bars in the same rows is the fault: %d found" % found.size())
	assert(
		(found[0]["covered"] as Rect2i) == Rect2i(210, 84, 1180, 14),
		"and the rectangle they both cover is worked out: %s" % str(found[0]["covered"]),
	)


func test_a_pages_title_may_not_be_drawn_over_words() -> void:
	# The menu titles are buttons at the top of the screen, and a page placed high enough draws its own title
	# over them - which is the fault this rule was written for. The page is at 43: what the probe recorded
	# before the strip was stated, with its own 36 px bar standing at 7..42, straight across titles at 12..62.
	var surfaces: Array = [
		DrawnSurfacesScript.bar_of("the figures", Rect2i(210, 43, 1180, 802), 36),
		DrawnSurfacesScript.words("Edit", Rect2i(500, 12, 80, 50)),
	]
	var found: Array[Dictionary] = DrawnSurfacesScript.meetings(surfaces)
	assert(found.size() == 1, "a title over words is a fault: %d found" % found.size())
	assert(
		String(found[0]["a"]["kind"]) == String(DrawnSurfacesScript.BAR)
		or String(found[0]["b"]["kind"]) == String(DrawnSurfacesScript.BAR),
		"and it is the title that is named as one of the two: %s" % str(found[0]),
	)


func test_a_page_drawn_over_the_furniture_it_covers_is_ordinary() -> void:
	# A page is over the board and over whatever the HUD keeps on it - that is what a page is. Only the bar
	# hanging off the top of the page is unmeasurable chrome, so only the bar is the offender.
	var surfaces: Array = [
		DrawnSurfacesScript.page("the figures", Rect2i(210, 98, 1180, 802)),
		DrawnSurfacesScript.words("Drawing (0)", Rect2i(45, 128, 570, 99)),
	]
	assert(
		DrawnSurfacesScript.meetings(surfaces).is_empty(),
		"a page over the palette is not a fault, however much of it the page covers",
	)


func test_a_page_over_a_page_is_ordinary() -> void:
	var surfaces: Array = [
		DrawnSurfacesScript.page("the door", Rect2i(540, 229, 520, 540)),
		DrawnSurfacesScript.page("the figures", Rect2i(210, 98, 1180, 802)),
	]
	assert(DrawnSurfacesScript.meetings(surfaces).is_empty(), "one page over another is how a page opens another")


## A page standing over the page beneath it hides the lower one's title with the rest of it, so a bar that a
## page covers is not a fault. The probe reported the front door under the figures page as one, which is how
## this test came to be written.
func test_a_page_over_the_title_of_the_page_beneath_it_is_ordinary() -> void:
	var surfaces: Array = [
		DrawnSurfacesScript.bar_of("the door", Rect2i(540, 229, 520, 540), 36),
		DrawnSurfacesScript.page("the figures", Rect2i(210, 98, 1180, 802)),
	]
	assert(
		DrawnSurfacesScript.meetings(surfaces).is_empty(),
		"the lower page's title is hidden with the whole of the lower page",
	)


func test_titles_that_stand_clear_of_each_other_are_not_a_fault() -> void:
	# The desk's own answer, after the strip was stated: the figures page's bar ends at 98 and the menu titles
	# begin at 12 and end at 62, so the two do not meet at all.
	var surfaces: Array = [
		DrawnSurfacesScript.bar_of("the figures", Rect2i(210, 98, 1180, 802), 36),
		DrawnSurfacesScript.words("Edit", Rect2i(500, 12, 80, 50)),
		DrawnSurfacesScript.page("the figures", Rect2i(210, 98, 1180, 802)),
	]
	assert(
		DrawnSurfacesScript.meetings(surfaces).is_empty(),
		"a title that stands below the words is the clean answer this project is meant to give",
	)


func test_a_row_says_what_met_what_and_where() -> void:
	var surfaces: Array = [
		DrawnSurfacesScript.bar_of("the figures", Rect2i(210, 43, 1180, 802), 36),
		DrawnSurfacesScript.words("Edit", Rect2i(500, 12, 80, 50)),
	]
	var found: Array[Dictionary] = DrawnSurfacesScript.meetings(surfaces)
	var said: String = DrawnSurfacesScript.sentence(found[0])
	assert(said.contains("the figures"), "the page is named: %s" % said)
	assert(said.contains("Edit"), "and so are the words it was drawn over: %s" % said)
	assert(said.contains("rows 12..42"), "with the rows they share, one-based and inclusive: %s" % said)


## Two controls that both say something may not be drawn over each other either - the same fault as a title bar
## over words, with no title bar in it. It was **measured**, not reasoned, and `tools/gui_overlap_show` is what
## caught it: on the desk with the front door put away, the foot line's own sentence was drawn across the plant
## list's caption and the two buttons beneath it, and no instrument had ever named any of the three, because the
## rule only asked about a title bar. The rectangles are the ones the probe's own `tap` lines report, and the
## rows they share are the ones its `overlap` lines measured.
##
## The foot line's rectangle is stated the way the probe has it: its rows are the measurement (857..876, the
## top of every overlap it takes part in), and its width is as wide as the words it holds, which the probe does
## not report - it is wider than either of the two things beneath it, and that is all these answer depend on.
func test_two_controls_that_both_say_something_may_not_share_rows() -> void:
	# The list's caption sits at rows 857..866 under the foot line's words: ten rows in which one set of words
	# is drawn in the middle of another.
	var surfaces: Array = [
		DrawnSurfacesScript.words(THE_FOOT_SENTENCE, Rect2i(28, 857, 720, 20)),
		DrawnSurfacesScript.words("130 species.", Rect2i(28, 857, 352, 10)),
	]
	var found: Array[Dictionary] = DrawnSurfacesScript.meetings(surfaces)
	assert(found.size() == 1, "one control's words under another's is a fault: %d found" % found.size())
	assert(
		(found[0]["covered"] as Rect2i) == Rect2i(28, 857, 352, 10),
		"and the rows they share are the ones the probe measured: %s" % str(found[0]["covered"]),
	)


func test_and_the_same_happens_to_a_button_under_the_foot_line() -> void:
	# `Place` is at the rectangle the probe reports for it - rows 872..902 - and the foot line's words cover its
	# first five rows. It is a `Button`, so it says its own sentence where the caption says a count, and the rule
	# does not care which of the two kinds a control is: both are words.
	var surfaces: Array = [
		DrawnSurfacesScript.words(THE_FOOT_SENTENCE, Rect2i(28, 857, 720, 20)),
		DrawnSurfacesScript.words("Place", Rect2i(28, 872, 209, 31)),
	]
	var found: Array[Dictionary] = DrawnSurfacesScript.meetings(surfaces)
	assert(found.size() == 1, "a button's words under the foot line is the same fault: %d found" % found.size())
	assert(
		(found[0]["covered"] as Rect2i) == Rect2i(28, 872, 209, 5),
		"five rows of the button are covered, exactly as the probe measured: %s" % str(found[0]["covered"]),
	)
