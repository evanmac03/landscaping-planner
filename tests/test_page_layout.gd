extends Node
## The page measure, held to the rules it states about itself.
##
## `PageLayout` is what a person trusts when it says a page has room for its own contents, so the
## cases that matter are the ones where it could be wrong in the direction that hides a bug: a page it
## could not read at all must come back `UNKNOWN` and never `FITS`, and a page too small for its own
## contents must be reported as overflowing rather than quietly described as fine.
##
## The pages here are built by hand and put in the tree, which is the only way any of this can be
## measured at all: a hidden page's wrapped labels report one line per word (the food page measures
## 12,499 px tall while it is hidden and 681 px once shown), so a measurement of a hidden page is
## meaningless rather than merely approximate.

const PageLayoutScript := preload("res://scripts/page_layout.gd")
const PageChromeScript := preload("res://scripts/page_chrome.gd")
const StatusWindowScript := preload("res://scripts/status_window.gd")

## Every page a test put in the tree, so each one is freed before the test ends. A page left standing
## is a leaked resource, and the runner fails the whole run for one of those.
var _pages: Array[Window] = []


func _free_pages() -> void:
	for page: Window in _pages:
		remove_child(page)
		page.free()
	_pages.clear()


## A page of plain lines, so a test can state exactly how much room the contents want without depending
## on any page in the project changing its wording: `lines` labels of 20 px each, 300 px wide.
func _plain_page(lines: int, declared: Vector2i) -> Window:
	var page := Window.new()
	page.name = "PlainPage"
	page.min_size = declared
	var column := VBoxContainer.new()
	column.name = "Column"
	page.add_child(column)
	for i: int in lines:
		var label := Label.new()
		label.text = "a line of text on a page"
		label.custom_minimum_size = Vector2(300.0, 20.0)
		column.add_child(label)
	return page


## Measure a page the way the check does: in the tree, freed afterwards.
func _measure(page: Window, viewport := Vector2i(1366, 768)) -> Dictionary:
	_pages.append(page)
	add_child(page)
	return await PageLayoutScript.measure(page, get_tree(), viewport)


## The same plain page with its column inside a `ScrollContainer`, which is what
## `PageChrome.scrolling_column` builds for the pages whose contents are longer than the screen they land
## on. `line_width` is a parameter because the width is the one fault a scrolling page must still report.
func _scrolling_page(lines: int, declared: Vector2i, line_width := 300.0) -> Window:
	var page := Window.new()
	page.name = "ScrollingPage"
	page.min_size = declared
	var column: VBoxContainer = PageChromeScript.scrolling_column(page)
	for i: int in lines:
		var label := Label.new()
		label.text = "a line of text on a page"
		label.custom_minimum_size = Vector2(line_width, 20.0)
		column.add_child(label)
	return page


func test_a_page_with_room_for_its_own_contents_is_measured_as_fitting() -> void:
	var row: Dictionary = await _measure(_plain_page(4, Vector2i(400, 300)))
	assert(bool(row["read"]), "the page was read: %s" % String(row["words"]))
	assert(bool(row["fits_declared"]),
		"four 20px lines fit 300px, and the measurement says so: %s" % String(row["words"]))
	assert(String(row["words"]).contains(PageLayoutScript.FITS),
		"and it says so in the one word a verdict counts: %s" % String(row["words"]))
	_free_pages()


func test_a_page_smaller_than_its_own_contents_is_reported_as_overflowing() -> void:
	# Twelve 20 px lines and the gaps between them need more than a declared 100 px of height, which is
	# the fault this whole measurement exists for: the page clips its own last rows.
	var row: Dictionary = await _measure(_plain_page(12, Vector2i(400, 100)))
	assert(bool(row["read"]), "the page was read: %s" % String(row["words"]))
	assert(not bool(row["fits_declared"]), "100px of page cannot hold twelve lines: %s" % String(row["words"]))
	assert(String(row["words"]).contains("OVERFLOWS BY"),
		"the overflow is named rather than the page merely failing a boolean: %s" % String(row["words"]))
	_free_pages()


func test_a_page_with_nothing_to_read_is_unknown_and_never_a_pass() -> void:
	# A window with no contents at all. This is the case that must never come back green: a page the
	# measurement could not look at has not been cleared, it has only been looked past.
	var page := Window.new()
	page.name = "EmptyPage"
	page.min_size = Vector2i(400, 300)
	var row: Dictionary = await _measure(page)
	assert(not bool(row["read"]), "nothing was read: %s" % String(row["words"]))
	assert(not bool(row["fits_declared"]), "and it is not called a fit: %s" % String(row["words"]))
	assert(String(row["words"]).begins_with(PageLayoutScript.UNKNOWN),
		"it is refused by name, as UNKNOWN: %s" % String(row["words"]))
	_free_pages()


func test_the_measurement_is_held_to_the_size_the_page_declares_for_itself() -> void:
	var page: Window = StatusWindowScript.new()
	var declared: Vector2i = PageLayoutScript.declared_size(page)
	var named: Variant = page.get_script().get_script_constant_map().get("SIZE", null)
	assert(named is Vector2i, "the page names its own size as a constant")
	assert(declared == named,
		"and the measurement holds the page to that number, not to one of its own: %s" % str(declared))
	page.free()


func test_a_real_page_of_the_project_has_room_for_its_own_contents() -> void:
	var page: Window = StatusWindowScript.new()
	page.build()
	var row: Dictionary = await _measure(page)
	assert(bool(row["read"]), "the status page was read: %s" % String(row["words"]))
	assert(bool(row["fits_declared"]),
		"and its declared size holds what it builds: %s" % String(row["words"]))
	assert(String(row["name"]) == "status_window",
		"the measurement is reported against the page's own name: %s" % String(row["name"]))
	_free_pages()


func test_a_page_whose_contents_scroll_is_not_called_a_page_that_clips_them() -> void:
	# Twelve 20 px lines against a declared 100 px of height is the same overflow the test above calls a
	# fault - and it stops being one the moment the column can scroll. It matters because nine pages of
	# this project declare more than a 1366 x 768 screen holds and land clamped on one: this is the
	# difference between a page somebody can finish with and a page whose buttons fell off the bottom.
	var page: Window = _scrolling_page(12, Vector2i(400, 100))
	var row: Dictionary = await _measure(page)
	assert(bool(row["read"]), "the page was read: %s" % String(row["words"]))
	assert(bool(row["scrolls"]), "its column scrolls: %s" % String(row["words"]))
	assert(not bool(row["fits_height"]), "the contents are longer than the page declares: %s"
		% String(row["words"]))
	assert(bool(row["fits_declared"]), "and the page is still sound: %s" % String(row["words"]))
	assert(String(row["words"]).contains(PageLayoutScript.SCROLLS),
		"it says which of the two it does, rather than calling it a fit: %s" % String(row["words"]))
	_free_pages()


func test_a_page_that_scrolls_is_still_a_fault_when_one_of_its_rows_is_too_wide() -> void:
	# Sideways is never scrollable, so a row wider than the page runs off the edge where nothing can reach
	# it. A scrolling column must not turn that into a pass, or the check would go quiet on exactly the
	# fault it was built for the moment a page was made scrollable.
	var page: Window = _scrolling_page(4, Vector2i(200, 300))
	var row: Dictionary = await _measure(page)
	assert(bool(row["scrolls"]), "its column scrolls: %s" % String(row["words"]))
	assert(not bool(row["fits_width"]), "a 300 px line in a 200 px page is too wide: %s" % String(row["words"]))
	assert(not bool(row["fits_declared"]), "so the page is not sound: %s" % String(row["words"]))
	assert(String(row["words"]).contains("too wide"),
		"and the width is what is named: %s" % String(row["words"]))
	_free_pages()