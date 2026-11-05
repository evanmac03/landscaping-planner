extends Node
## The shared page chrome, held to the few decisions it makes for every page.
##
## Two of these are worth more than the rest: the content root's name is written in two files and must
## agree (this one and `PageLayout`), and a button made here must not take the keyboard, because that is
## the rule every page's own test asserts one page at a time.
##
## Nothing here needs a tree. Chrome is measured by reading what it built, and a page is freed in the
## test that made it - the runner fails a whole run over one leaked page.

const PageChromeScript := preload("res://scripts/page_chrome.gd")
const PhoneFilesScript := preload("res://scripts/phone_files.gd")
const PageLayoutScript := preload("res://scripts/page_layout.gd")

var _pages: Array[Window] = []


func _free_pages() -> void:
	for page: Window in _pages:
		page.free()
	_pages.clear()


func _page() -> Window:
	var page := Window.new()
	page.name = "ChromePage"
	_pages.append(page)
	return page


func test_every_page_title_is_the_same_size() -> void:
	# The drift this replaces: 15 on the ground page, 16 on the revision and sheet pages, 18 in the
	# manual, 20 on the field and status pages.
	assert(PageChromeScript.heading("Food garden").get_theme_font_size("font_size")
		== PageChromeScript.HEADING_SIZE, "a title is the one title size")
	assert(PageChromeScript.subheading("Sections").get_theme_font_size("font_size")
		== PageChromeScript.SUBHEADING_SIZE, "and a section heading is the one section size")
	assert(PageChromeScript.BODY_SIZE < PageChromeScript.SUBHEADING_SIZE,
		"a body sentence is smaller than a section heading")


func test_a_button_made_here_does_not_take_the_keyboard_by_itself() -> void:
	assert(PageChromeScript.button("Close").focus_mode == Control.FOCUS_NONE,
		"the HUD's own rule: a page control is released, and whether it takes focus while the page is"
		+ " open is decided once by the shared show")


func test_a_button_is_named_after_the_words_a_person_reads() -> void:
	assert(PageChromeScript.node_name_for("Close.") == "CloseButton", "a full stop is not part of a name")
	assert(PageChromeScript.node_name_for("What just happened...") == "WhatjusthappenedButton",
		"nor is an ellipsis, and the words run together")
	assert(PageChromeScript.node_name_for("...") == "Button",
		"a caption of nothing but marks still leaves a node with a name")


func test_the_content_root_is_named_the_word_the_page_measurement_looks_for() -> void:
	# The same literal is written in both files, so this is where the two are held to each other.
	assert(PageChromeScript.COLUMN_NAME == PageLayoutScript.CONTENT_NODE,
		"the shared column is the node PageLayout finds a page's contents by")
	var page: Window = _page()
	var root: VBoxContainer = PageChromeScript.column(page)
	assert(String(root.name) == PageChromeScript.COLUMN_NAME, str(root.name))
	assert(PageLayoutScript.content_root(page) == root,
		"so a page built through this chrome is measurable without saying anything extra")
	_free_pages()


func test_the_inset_a_page_asks_for_is_counted_as_room_its_contents_need() -> void:
	var page: Window = _page()
	var root: VBoxContainer = PageChromeScript.column(page, 8, Vector2(16.0, 12.0))
	var line: Label = PageChromeScript.heading("A heading")
	root.add_child(line)
	var wanted: Vector2 = PageLayoutScript.wanted_size(root)
	assert(wanted.x == line.get_combined_minimum_size().x + 32.0,
		"the 16 px either side are part of what the page declares for: %s" % str(wanted))
	assert(wanted.y == line.get_combined_minimum_size().y + 24.0,
		"and so is the 12 px above and below: %s" % str(wanted))
	_free_pages()


func test_a_sentence_that_explains_a_page_wraps_and_a_title_does_not() -> void:
	assert(PageChromeScript.note("A long sentence about what this page is for.").autowrap_mode
		!= TextServer.AUTOWRAP_OFF, "a note wraps to the page it is on")
	assert(PageChromeScript.heading("Food garden").autowrap_mode == TextServer.AUTOWRAP_OFF,
		"a title is short enough to be read as one line, and wrapping it would only make it two")


func test_a_plain_line_a_page_says_is_a_body_sentence() -> void:
	# A page's count line and its summary line are its own words rather than one of the two dimmed kinds,
	# and they are still body sentences: the size comes from here rather than from the page.
	assert(PageChromeScript.text("3 answers").get_theme_font_size("font_size") == PageChromeScript.BODY_SIZE,
		"a plain line is the one body size")
	assert(PageChromeScript.text("A sentence a page says in its own right.").autowrap_mode
		!= TextServer.AUTOWRAP_OFF, "and it wraps like the other sentences a page says")


func test_a_line_that_wraps_asks_for_the_width_it_wraps_into() -> void:
	# A row gives a child that does not ask for the spare room only its own minimum width, and a wrapped
	# `Label`'s minimum width is its longest *word*. The billing page's note beside its invoice button
	# wrapped to fifty lines and stood that page 1,217 px tall; the audit caught it, and no page's own
	# test could have, because every path and every caption on the page was still exactly where it was.
	assert(PageChromeScript.text("A sentence a page says.").size_flags_horizontal & Control.SIZE_EXPAND != 0,
		"a line that wraps takes the spare width of the row it is in")
	assert(PageChromeScript.note("What this page is for.").size_flags_horizontal & Control.SIZE_EXPAND != 0,
		"and so does every other sentence a page says: a note, a hint and a status line")
	assert(PageChromeScript.status("Nothing has been billed yet.").size_flags_horizontal
		& Control.SIZE_EXPAND != 0, "the status line included")
	assert(PageChromeScript.text("a caption", false).size_flags_horizontal & Control.SIZE_EXPAND == 0,
		"a line that does not wrap keeps its own width, which is what keeps a row open")


func test_a_row_is_named_after_the_control_it_carries() -> void:
	var page: Window = _page()
	var field := LineEdit.new()
	field.name = "GridStep"
	page.add_child(field)
	var row: HBoxContainer = PageChromeScript.labelled("every", field)
	assert(String(row.name) == "GridStepRow", str(row.name))
	assert(row.get_child_count() == 2, "a caption and the control it names")
	_free_pages()


func test_a_page_bigger_than_the_screen_is_brought_down_to_the_screen() -> void:
	# A 1180 x 850 page - the analytics, billing and ledger pages - on a 1366 x 768 laptop: the 850
	# cannot land, and it was 850 that put the page's last row off the bottom of the screen.
	var floor: Vector2i = PageChromeScript.clamped_minimum(Vector2i(1180, 850), Vector2i(1366, 768))
	assert(floor == Vector2i(1180, 768), "the height comes down to the screen: %s" % str(floor))


func test_a_page_that_already_fits_keeps_the_floor_it_asked_for() -> void:
	var floor: Vector2i = PageChromeScript.clamped_minimum(Vector2i(560, 640), Vector2i(1366, 768))
	assert(floor == Vector2i(560, 640),
		"a screen with room to spare must not make a page smaller than it meant to be: %s" % str(floor))


func test_a_display_that_cannot_be_asked_leaves_the_page_its_own_floor() -> void:
	assert(PageChromeScript.clamped_minimum(Vector2i(1180, 850), Vector2i.ZERO)
		== Vector2i(1180, 850), "a display that answers nothing is not a display with no room")
	assert(PageChromeScript.clamped_minimum(Vector2i(1180, 850), Vector2i(-1, -1))
		== Vector2i(1180, 850), "and a nonsense answer is refused rather than obeyed")


func test_the_room_is_the_viewport_the_page_lands_in() -> void:
	var page: Window = _page()
	add_child(page)
	var room: Vector2i = PageChromeScript.room_for(page)
	assert(room == Vector2i(get_viewport().get_visible_rect().size),
		"a page lands in the game window a person is looking at, not on the monitor behind it: %s"
			% str(room))
	remove_child(page)
	_free_pages()


func test_a_page_may_be_taller_than_its_screen_and_scroll_its_length_but_never_its_width() -> void:
	# The nine pages that declare more than a 1366 x 768 screen holds land clamped on one. What scrolls is
	# the length, so their last row can still be reached; the width never does, because a row too wide is a
	# fault a person can see and making it scrollable would only hide it from the measurement.
	var page: Window = _page()
	var root: VBoxContainer = PageChromeScript.scrolling_column(page, 6)
	assert(String(root.name) == PageChromeScript.COLUMN_NAME,
		"the column keeps the one name the page measurement goes by: %s" % String(root.name))
	var scroll: ScrollContainer = PageLayoutScript.scroll_of(root)
	assert(scroll != null, "and it sits inside a wrapper the measurement can see")
	assert(String(scroll.name) == PageChromeScript.SCROLL_NAME, str(scroll.name))
	assert(scroll.horizontal_scroll_mode == ScrollContainer.SCROLL_MODE_DISABLED,
		"a page never scrolls sideways, so a row too wide is still caught")
	assert(scroll.vertical_scroll_mode == ScrollContainer.SCROLL_MODE_AUTO,
		"and its length scrolls only when there is more of it than the page shows")
	assert(scroll.follow_focus,
		"a button below the fold comes into view when Tab reaches it, or the keyboard reaches a control"
		+ " nobody can see")
	assert(PageLayoutScript.content_root(page) == root,
		"and the page is measured like any other, one level down from where it used to sit")
	_free_pages()


func test_the_inset_a_scrolling_page_asks_for_is_counted_off_the_wrapper_that_carries_it() -> void:
	# A `ScrollContainer` positions the child it holds, so an offset written on the column inside would be
	# overwritten on the next layout pass: the inset has to live on the wrapper, and the measurement has to
	# read it there, or a page would be measured as wanting 32 px less room than it really spends.
	var page: Window = _page()
	var root: VBoxContainer = PageChromeScript.scrolling_column(page, 6, Vector2(16.0, 12.0))
	var padding: Vector2 = PageLayoutScript.padding_of(root, PageLayoutScript.scroll_of(root))
	assert(padding == Vector2(32.0, 24.0),
		"the 16 px either side and the 12 px above and below are part of what the page declares for: %s"
			% str(padding))
	var line: Label = PageChromeScript.heading("A heading")
	root.add_child(line)
	var wanted: Vector2 = PageLayoutScript.wanted_contents(root) + padding
	assert(wanted.y == line.get_combined_minimum_size().y + 24.0,
		"and they are added to what the contents want, so a scrolling page declares room for the words"
		+ " and the space around them: %s" % str(wanted))
	_free_pages()


## The phone's density and the scale this build draws the canvas at, for the tests below.
const PHONE_DPI := 384.6
const PHONE_SCALE := 1.62


## A page's buttons are the things a thumb presses, so on a phone they are made as tall as a thumb needs
## and their words are made legible - and on a computer the page is untouched.
func test_a_phones_page_answers_at_a_thumbs_size_and_a_computers_does_not() -> void:
	PhoneFilesScript.force(PhoneFilesScript.Device.PHONE)
	var page: Window = _page()
	var root: VBoxContainer = PageChromeScript.column(page)
	var close: Button = PageChromeScript.button("Close")
	root.add_child(close)

	var measured: int = PageChromeScript.size_buttons_for_a_finger(page, PHONE_SCALE, PHONE_DPI)
	assert(measured == 1, "the one button on the page was measured: %d" % measured)
	assert(close.custom_minimum_size.y > 29.0,
		"and it is taller than the row a desk was drawn with: %s" % str(close.custom_minimum_size))
	assert(close.get_theme_font_size("font_size") > 12,
		"with words bigger than the twelve-pixel text a desk gets")
	PhoneFilesScript.force(PhoneFilesScript.Device.AUTO)
	_free_pages()


## The same page on a computer is the page this project designed: nothing is imposed at all.
func test_a_computers_page_is_left_exactly_as_the_page_laid_it_out() -> void:
	var page: Window = _page()
	var root: VBoxContainer = PageChromeScript.column(page)
	var close: Button = PageChromeScript.button("Close")
	root.add_child(close)
	PhoneFilesScript.force(PhoneFilesScript.Device.COMPUTER)

	var measured: int = PageChromeScript.size_buttons_for_a_finger(page, PHONE_SCALE, PHONE_DPI)
	assert(measured == 0, "nothing to impose, so nothing is measured: %d" % measured)
	assert(close.custom_minimum_size == Vector2.ZERO, "and the button is as the page left it")
	assert(not close.has_theme_font_size_override("font_size"), "with no font of its own")
	PhoneFilesScript.force(PhoneFilesScript.Device.AUTO)
	_free_pages()