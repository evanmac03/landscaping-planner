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
const PhoneHudScript := preload("res://scripts/phone_hud.gd")
const TouchInputScript := preload("res://scripts/touch_input.gd")
const PageLayoutScript := preload("res://scripts/page_layout.gd")
const StartWindowScript := preload("res://scripts/start_window.gd")

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


## **A page that has outgrown the room says so where a scroll cannot take the words away.** The wiring half of
## `PageLayout.words_for_a_page_that_scrolls`: the function that decides a page needs a scroll is the function
## that tells the person, so there is one decision and one sentence.
##
## It says it **once**, which is the half a first version would miss: a page is landed again on every change of
## the room's shape, so the same question is asked repeatedly and a second sentence would stack up in the bar.
## What stops it is the scroll the page already has, not a mark kept beside it.
##
## No tree is needed, for the reason this file's head gives: the decision is made from the minimum sizes a
## `Container` reports, and those do not wait for a layout pass.
func test_a_page_that_is_given_a_scroll_says_so_in_its_title_and_only_once() -> void:
	var page: Window = _page()
	page.title = "The figures"
	var column := VBoxContainer.new()
	column.name = PageLayoutScript.CONTENT_NODE
	page.add_child(column)
	var taller := Control.new()
	taller.custom_minimum_size = Vector2(300.0, 900.0)
	column.add_child(taller)
	assert(
		PageChromeScript.scroll_if_it_does_not_fit(page, Vector2i(400, 200)),
		"a column taller than the room it landed in is given a scroll",
	)
	assert(column.get_parent() is ScrollContainer, "the column is inside the scroll rather than where it stood")
	assert(
		page.title.begins_with("The figures") and "scroll" in page.title,
		"and the page says so in its own title: %s" % page.title,
	)
	var said: String = page.title
	assert(
		not PageChromeScript.scroll_if_it_does_not_fit(page, Vector2i(400, 200)),
		"asking again finds the scroll it already has",
	)
	assert(page.title == said, "and the sentence is not written a second time: %s" % page.title)
	# **And a page that fits again stops saying it.** The wrapper is left standing, because it does no harm once it
	# is there - but the title has to tell the truth: a front door saying it is taller than the screen while it
	# stands whole in the middle of a 1600 x 900 desk is a caption that lies, which is worse than the silence this
	# sentence was written to end.
	#
	# The fitting page is built whole rather than shrunk from the first one: a control that has already been
	# measured does not report a `custom_minimum_size` changed a moment ago until a layout pass runs, and a headless
	# test never gives it one. The offsets below stand in for the rectangle a `ScrollContainer` wears on its child in
	# a live tree - and that rectangle is exactly what must not be counted as the page's own padding.
	var roomy: Window = _page()
	roomy.title = PageLayoutScript.words_for_a_page_that_scrolls("The figures")
	var scroll := ScrollContainer.new()
	roomy.add_child(scroll)
	var inner := VBoxContainer.new()
	inner.name = PageLayoutScript.CONTENT_NODE
	scroll.add_child(inner)
	var short_one := Control.new()
	short_one.custom_minimum_size = Vector2(300.0, 10.0)
	inner.add_child(short_one)
	inner.offset_bottom = -400.0
	assert(
		PageLayoutScript.wanted_size(inner).y > 400.0,
		"the column's offsets stand in for the rectangle a scroll gives it: the page's own height, counted twice",
	)
	assert(
		not PageChromeScript.scroll_if_it_does_not_fit(roomy, Vector2i(400, 200)),
		"a page whose children fit the room is not wrapped, however tall the rectangle it wears",
	)
	assert(roomy.title == "The figures", "and it says its own name and nothing more: %s" % roomy.title)
	_free_pages()


func test_every_page_title_is_the_same_size() -> void:
	# The drift this replaces: 15 on the ground page, 16 on the revision and sheet pages, 18 in the
	# manual, 20 on the field and status pages.
	assert(
		PageChromeScript.heading("Food garden").get_theme_font_size("font_size") == PageChromeScript.HEADING_SIZE,
		"a title is the one title size",
	)
	assert(
		PageChromeScript.subheading("Sections").get_theme_font_size("font_size") == PageChromeScript.SUBHEADING_SIZE,
		"and a section heading is the one section size",
	)
	assert(
		PageChromeScript.BODY_SIZE < PageChromeScript.SUBHEADING_SIZE,
		"a body sentence is smaller than a section heading",
	)


func test_the_body_text_a_desk_is_drawn_with_is_one_number() -> void:
	# `PhoneHud` measures legibility against the size this project draws body text at, and `PageChrome` lays
	# pages out with it, so the number lives in two files and is held to itself here.
	assert(
		PhoneHudScript.DESK_TEXT == PageChromeScript.BODY_SIZE,
		"the body text a desk is drawn with is the one number both files mean: %d and %d"
		% [PhoneHudScript.DESK_TEXT, PageChromeScript.BODY_SIZE],
	)


func test_a_button_made_here_does_not_take_the_keyboard_by_itself() -> void:
	assert(
		PageChromeScript.button("Close").focus_mode == Control.FOCUS_NONE,
		"the HUD's own rule: a page control is released, and whether it takes focus while the page is"
		+ " open is decided once by the shared show",
	)


func test_a_button_is_named_after_the_words_a_person_reads() -> void:
	assert(PageChromeScript.node_name_for("Close.") == "CloseButton", "a full stop is not part of a name")
	assert(
		PageChromeScript.node_name_for("What just happened...") == "WhatjusthappenedButton",
		"nor is an ellipsis, and the words run together",
	)
	assert(
		PageChromeScript.node_name_for("...") == "Button",
		"a caption of nothing but marks still leaves a node with a name",
	)


func test_the_content_root_is_named_the_word_the_page_measurement_looks_for() -> void:
	# The same literal is written in both files, so this is where the two are held to each other.
	assert(
		PageChromeScript.COLUMN_NAME == PageLayoutScript.CONTENT_NODE,
		"the shared column is the node PageLayout finds a page's contents by",
	)
	var page: Window = _page()
	var root: VBoxContainer = PageChromeScript.column(page)
	assert(String(root.name) == PageChromeScript.COLUMN_NAME, str(root.name))
	assert(
		PageLayoutScript.content_root(page) == root,
		"so a page built through this chrome is measurable without saying anything extra",
	)
	_free_pages()


func test_the_inset_a_page_asks_for_is_counted_as_room_its_contents_need() -> void:
	var page: Window = _page()
	var root: VBoxContainer = PageChromeScript.column(page, 8, Vector2(16.0, 12.0))
	var line: Label = PageChromeScript.heading("A heading")
	root.add_child(line)
	var wanted: Vector2 = PageLayoutScript.wanted_size(root)
	assert(
		wanted.x == line.get_combined_minimum_size().x + 32.0,
		"the 16 px either side are part of what the page declares for: %s" % str(wanted),
	)
	assert(
		wanted.y == line.get_combined_minimum_size().y + 24.0,
		"and so is the 12 px above and below: %s" % str(wanted),
	)
	_free_pages()


func test_a_sentence_that_explains_a_page_wraps_and_a_title_does_not() -> void:
	assert(
		PageChromeScript.note("A long sentence about what this page is for.").autowrap_mode != TextServer.AUTOWRAP_OFF,
		"a note wraps to the page it is on",
	)
	assert(
		PageChromeScript.heading("Food garden").autowrap_mode == TextServer.AUTOWRAP_OFF,
		"a title is short enough to be read as one line, and wrapping it would only make it two",
	)


func test_a_plain_line_a_page_says_is_a_body_sentence() -> void:
	# A page's count line and its summary line are its own words rather than one of the two dimmed kinds,
	# and they are still body sentences: the size comes from here rather than from the page.
	assert(
		PageChromeScript.text("3 answers").get_theme_font_size("font_size") == PageChromeScript.BODY_SIZE,
		"a plain line is the one body size",
	)
	assert(
		PageChromeScript.text("A sentence a page says in its own right.").autowrap_mode != TextServer.AUTOWRAP_OFF,
		"and it wraps like the other sentences a page says",
	)


func test_a_line_that_wraps_asks_for_the_width_it_wraps_into() -> void:
	# A row gives a child that does not ask for the spare room only its own minimum width, and a wrapped
	# `Label`'s minimum width is its longest *word*. The billing page's note beside its invoice button
	# wrapped to fifty lines and stood that page 1,217 px tall; the audit caught it, and no page's own
	# test could have, because every path and every caption on the page was still exactly where it was.
	assert(
		PageChromeScript.text("A sentence a page says.").size_flags_horizontal & Control.SIZE_EXPAND != 0,
		"a line that wraps takes the spare width of the row it is in",
	)
	assert(
		PageChromeScript.note("What this page is for.").size_flags_horizontal & Control.SIZE_EXPAND != 0,
		"and so does every other sentence a page says: a note, a hint and a status line",
	)
	assert(
		PageChromeScript.status("Nothing has been billed yet.").size_flags_horizontal & Control.SIZE_EXPAND != 0,
		"the status line included",
	)
	assert(
		PageChromeScript.text("a caption", false).size_flags_horizontal & Control.SIZE_EXPAND == 0,
		"a line that does not wrap keeps its own width, which is what keeps a row open",
	)


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
	assert(
		floor == Vector2i(560, 640),
		"a screen with room to spare must not make a page smaller than it meant to be: %s" % str(floor),
	)


func test_a_display_that_cannot_be_asked_leaves_the_page_its_own_floor() -> void:
	assert(
		PageChromeScript.clamped_minimum(Vector2i(1180, 850), Vector2i.ZERO) == Vector2i(1180, 850),
		"a display that answers nothing is not a display with no room",
	)
	assert(
		PageChromeScript.clamped_minimum(Vector2i(1180, 850), Vector2i(-1, -1)) == Vector2i(1180, 850),
		"and a nonsense answer is refused rather than obeyed",
	)


func test_the_room_is_the_viewport_the_page_lands_in() -> void:
	var page: Window = _page()
	add_child(page)
	var room: Vector2i = PageChromeScript.room_for(page)
	assert(
		room == Vector2i(get_viewport().get_visible_rect().size),
		"a page lands in the game window a person is looking at, not on the monitor behind it: %s" % str(room),
	)
	remove_child(page)
	_free_pages()


func test_a_page_may_be_taller_than_its_screen_and_scroll_its_length_but_never_its_width() -> void:
	# The nine pages that declare more than a 1366 x 768 screen holds land clamped on one. What scrolls is
	# the length, so their last row can still be reached; the width never does, because a row too wide is a
	# fault a person can see and making it scrollable would only hide it from the measurement.
	var page: Window = _page()
	var root: VBoxContainer = PageChromeScript.scrolling_column(page, 6)
	assert(
		String(root.name) == PageChromeScript.COLUMN_NAME,
		"the column keeps the one name the page measurement goes by: %s" % String(root.name),
	)
	var scroll: ScrollContainer = PageLayoutScript.scroll_of(root)
	assert(scroll != null, "and it sits inside a wrapper the measurement can see")
	assert(String(scroll.name) == PageChromeScript.SCROLL_NAME, str(scroll.name))
	assert(
		scroll.horizontal_scroll_mode == ScrollContainer.SCROLL_MODE_DISABLED,
		"a page never scrolls sideways, so a row too wide is still caught",
	)
	assert(
		scroll.vertical_scroll_mode == ScrollContainer.SCROLL_MODE_AUTO,
		"and its length scrolls only when there is more of it than the page shows",
	)
	assert(
		scroll.follow_focus,
		"a button below the fold comes into view when Tab reaches it, or the keyboard reaches a control"
		+ " nobody can see",
	)
	assert(
		PageLayoutScript.content_root(page) == root,
		"and the page is measured like any other, one level down from where it used to sit",
	)
	_free_pages()


func test_the_inset_a_scrolling_page_asks_for_is_counted_off_the_wrapper_that_carries_it() -> void:
	# A `ScrollContainer` positions the child it holds, so an offset written on the column inside would be
	# overwritten on the next layout pass: the inset has to live on the wrapper, and the measurement has to
	# read it there, or a page would be measured as wanting 32 px less room than it really spends.
	var page: Window = _page()
	var root: VBoxContainer = PageChromeScript.scrolling_column(page, 6, Vector2(16.0, 12.0))
	var padding: Vector2 = PageLayoutScript.padding_of(root, PageLayoutScript.scroll_of(root))
	assert(
		padding == Vector2(32.0, 24.0),
		"the 16 px either side and the 12 px above and below are part of what the page declares for: %s" % str(padding),
	)
	var line: Label = PageChromeScript.heading("A heading")
	root.add_child(line)
	var wanted: Vector2 = PageLayoutScript.wanted_contents(root) + padding
	assert(
		wanted.y == line.get_combined_minimum_size().y + 24.0,
		"and they are added to what the contents want, so a scrolling page declares room for the words"
		+ " and the space around them: %s" % str(wanted),
	)
	_free_pages()


## The phone's density and the scale this build draws the canvas at, for the tests below. The density is the
## A16W's own reading of its glass, and a test states it through `PhoneHud.force_density`.
const PHONE_DPI := 450.0
const PHONE_SCALE := 1.62


## A page's buttons are the things a thumb presses, so on a device answered with a finger they are made as
## tall as a thumb needs and their words are made legible. The scale and the density are stated rather than
## read, so what a phone would be told can be held without being one.
func test_a_phones_page_answers_at_a_thumbs_size() -> void:
	var page: Window = _page()
	var root: VBoxContainer = PageChromeScript.column(page)
	var close: Button = PageChromeScript.button("Close")
	root.add_child(close)

	var measured: int = PageChromeScript.size_buttons_for_a_finger(page, PHONE_SCALE, PHONE_DPI)
	assert(measured == 1, "the one button on the page was measured: %d" % measured)
	assert(
		close.custom_minimum_size.y > 29.0,
		"and it is taller than the row a desk was drawn with: %s" % str(close.custom_minimum_size),
	)
	assert(close.get_theme_font_size("font_size") > 12, "with words bigger than the twelve-pixel text a desk gets")
	_free_pages()


## The same page on a device answered with a mouse is the page this project designed: the rule is asked
## once, in the one place a page is shown, and the answer there is no.
func test_a_computers_page_is_left_exactly_as_the_page_laid_it_out() -> void:
	var page: Window = _page()
	var root: VBoxContainer = PageChromeScript.column(page)
	var close: Button = PageChromeScript.button("Close")
	root.add_child(close)
	TouchInputScript.force(TouchInputScript.Answer.MOUSE)

	var measured: int = PageChromeScript.size_for_a_finger(page)
	assert(measured == 0, "nothing to impose, so nothing is measured: %d" % measured)
	assert(close.custom_minimum_size == Vector2.ZERO, "and the button is as the page left it")
	assert(not close.has_theme_font_size_override("font_size"), "with no font of its own")
	TouchInputScript.force(TouchInputScript.Answer.AUTO)
	_free_pages()


## The title bar is Godot's work rather than a page's - no page builds it, no page's layout counts it - and
## Godot draws it *above* the rectangle the window reports as its position and size. A page that ignores that
## opens with its own title and its close cross above the top of the screen, which is exactly what a phone
## showed and what the desk's own pages were quietly doing by eleven pixels.
func test_the_title_bar_is_taken_out_of_the_room_a_page_may_use() -> void:
	var page: Window = _page()
	add_child(page)
	var room: Vector2i = PageChromeScript.room_for(page)
	var bar: int = PageChromeScript.chrome_above(page)
	assert(bar > 0, "a page with a title bar has one to leave room for: %d" % bar)
	assert(
		PageChromeScript.content_room(page) == Vector2i(room.x, room.y - bar),
		"and the room its contents may use is the room less that bar: %s" % str(PageChromeScript.content_room(page)),
	)
	remove_child(page)
	_free_pages()


## A page is placed below the bar the HUD keeps at the top of the screen.
##
## A page's title bar is drawn *above* its rectangle, so a page is allowed to reach the top of the screen -
## and a page that did so drew its own title and its close cross over the menu titles, which is what the HUD's
## top bar is. The strip no page may use is stated once, in the one place every page is placed; this holds the
## arithmetic, and where a page really lands on the glass is what `tools/page_chrome_probe.tscn` measures.
func test_a_page_is_placed_below_the_bar_the_hud_keeps_at_the_top() -> void:
	var was: int = PageChromeScript.reserved_above
	var page: Window = _page()
	# Taller than any room, so the page takes the whole of what is left below the strip.
	page.min_size = Vector2i(600, 4000)
	add_child(page)
	PageChromeScript.reserved_above = 62
	var room: Vector2i = PageChromeScript.room_for(page)
	var bar: int = PageChromeScript.chrome_above(page)
	var content: Vector2i = PageChromeScript.content_room(page)
	var floor: Vector2i = PageChromeScript.show_centred(page)
	var stood_at: int = page.position.y
	# Put back before a word is asserted: `assert` ends the test it fails in, and a strip left stated on the
	# class would place every page in every test after this one low.
	PageChromeScript.reserved_above = was
	assert(
		content == Vector2i(room.x, room.y - bar - 62),
		"the room a page may use is the room less its own bar and the strip at the top: %s" % str(content),
	)
	assert(floor.y == room.y - bar - 62, "a page as tall as that room is given the whole of it: %s" % str(floor))
	assert(
		stood_at - bar >= 62,
		"and the bar hanging above the page stands at or below the strip rather than over it: %d" % (stood_at - bar),
	)
	remove_child(page)
	_free_pages()


## The three rooms this project is measured in, and what a page takes from each. This is the desk half of the
## phone work: a stated room lets the machine the suite runs on hold what a page lands in at a shape it is not
## being run at, so a change to the placement arithmetic is refused here rather than found on the glass.
##
## **The figures are measurements, not arithmetic**: 62, 70 and 562 are the tops of the HUD's own bar on a
## 1600 by 900 desk, on the SM-A166W lying (its bar 61 tall at y 9) and the same phone upright, where the
## chrome folds. Each was read off `page_chrome_probe` and must be updated with it if the chrome changes shape.
##
## The invariant every one of them holds: the page, its own bar and the strip are exactly the room - which is
## the whole point of the two numbers above.
func test_the_three_rooms_a_page_is_placed_in_are_pinned() -> void:
	var page: Window = _page()
	add_child(page)
	var bar: int = PageChromeScript.chrome_above(page)
	var was: int = PageChromeScript.reserved_above
	var measured: Array[Vector3i] = [Vector3i(1600, 900, 62), Vector3i(1444, 666, 70), Vector3i(1185, 2567, 562)]
	var rooms: Array[Vector2i] = []
	var floors: Array[Vector2i] = []
	for room: Vector3i in measured:
		PageChromeScript.reserved_above = room.z
		rooms.append(Vector2i(room.x, room.y))
		floors.append(PageChromeScript.content_room_in(page, Vector2i(room.x, room.y)))
	PageChromeScript.reserved_above = was
	assert(
		PageChromeScript.content_room_in(page, Vector2i.ZERO) == Vector2i.ZERO,
		"a room that cannot be answered is left as it is, strip and all",
	)
	for index: int in rooms.size():
		var room: Vector2i = rooms[index]
		var floor: Vector2i = floors[index]
		var strip: int = measured[index].z
		assert(
			floor == Vector2i(room.x, room.y - bar - strip),
			"the room less a page's own bar and the strip is what it may use: %s from %s" % [str(floor), str(room)],
		)
		assert(
			floor.y + bar + strip == room.y,
			"and the page, its bar and the strip are exactly the room: %d + %d + %d against %d"
			% [floor.y, bar, strip, room.y],
		)
	remove_child(page)
	_free_pages()


func test_a_page_with_no_title_bar_is_not_made_shorter_for_one() -> void:
	# `borderless` is a page saying it draws no bar, and taking room away for a bar that is not drawn would
	# make a short page smaller for nothing.
	var page: Window = _page()
	page.borderless = true
	add_child(page)
	assert(PageChromeScript.chrome_above(page) == 0, "a borderless page draws no bar")
	assert(
		PageChromeScript.content_room(page) == PageChromeScript.room_for(page),
		"so nothing is taken out of the room it lands in",
	)
	remove_child(page)
	_free_pages()


## A desk has no camera cutout to leave room for, so the room a page lands in is unchanged there - which is
## what keeps the other pages' tests, and the page-layout check, measuring the pages a desk was drawn for.
## The cutout is a fact about a display, so only a phone can exercise it; what is held down here is that a
## desk is left exactly as it was, and that a room with no top is not made negative.
func test_a_desk_leaves_no_room_for_a_camera_cutout() -> void:
	assert(
		PhoneHudScript.cutout_top(Vector2i(1185, 2567)) == 0,
		"a desk is not answered with a finger, so nothing hangs into the top of its screen",
	)
	assert(
		PhoneHudScript.cutout_top(Vector2i(100, 0)) == 0,
		"and a room with no height has no top for anything to hang into",
	)
	var page: Window = _page()
	add_child(page)
	var room: Vector2i = PageChromeScript.room_for(page)
	assert(
		PageChromeScript.content_room(page) == Vector2i(room.x, room.y - PageChromeScript.chrome_above(page)),
		"so the room a page's contents may use is the room less its title bar and nothing else",
	)
	remove_child(page)
	_free_pages()


## **A page's contents are held clear of the band the device keeps along its foot, which is the one reading of the
## four a display will not give.** `PhoneHud.KEPT_FEET` states it, and measured on the glass lying down the band is
## where the front door's own `Take a photograph` took a finger at its middle - 13 px above the screen's foot, so
## the press a person aimed at the middle of a button was inside the region the system answers for.
##
## **Lying is a shape of its own here**, and that is the half a first reading would miss: the table is keyed by the
## screen the display reports, and that follows the rotation, so the room a page may use lying down is a band
## smaller than the same page on a desk. A desk's readings are all zero and it keeps exactly the room it was drawn
## for, which is what leaves every other page test and the page-layout check measuring the pages a desk has.
func test_a_page_keeps_clear_of_the_band_the_device_states() -> void:
	PhoneHudScript.force_density(PHONE_DPI)
	# The A16W lying down exactly as the glass reports it: 100 px of a 2340 px display is its camera, and the safe
	# area runs to the foot of the screen - which is the whole of why the band along the foot has to be *stated*
	# rather than read, and why a page that asked only `cutout_here` kept none of it.
	PhoneHudScript.force_display(Vector2i(2340, 1080), Rect2i(100, 0, 2240, 1080))
	TouchInputScript.force(TouchInputScript.Answer.FINGER)
	var page: Window = _page()
	add_child(page)
	var room := Vector2i(1444, 666)
	var band: int = PhoneHudScript.kept_foot(room)
	assert(band > 0, "a phone lying down is told the band it keeps along its foot: %d" % band)
	var above: int = PageChromeScript.chrome_above(page) + PageChromeScript.reserved_above
	assert(
		PageChromeScript.content_room_in(page, room).y == room.y - above - band,
		"and the room a page's contents may use stops above that band: %s"
		% str(PageChromeScript.content_room_in(page, room)),
	)
	# The camera is along a *side*, so the width loses that and only that: a foot band taken off the width as well
	# would be a page narrower than the screen for a band no person could point at.
	assert(
		PageChromeScript.content_room_in(page, room).x == room.x - PhoneHudScript.share_of_the_room(100, 2340, room.x),
		"while the width loses the camera's own share and nothing else: %d"
		% PageChromeScript.content_room_in(page, room).x,
	)
	# And the desk this suite runs on keeps exactly the room it drew: nothing to state, nothing to take off.
	PhoneHudScript.force_display(Vector2i.ZERO, Rect2i())
	assert(
		PageChromeScript.content_room_in(page, room).y == room.y - above,
		"and a desk is given the room less its own chrome and nothing else: %s"
		% str(PageChromeScript.content_room_in(page, room)),
	)
	TouchInputScript.force(TouchInputScript.Answer.AUTO)
	PhoneHudScript.force_density(0.0)
	remove_child(page)
	_free_pages()


func test_a_page_as_tall_as_the_screen_still_keeps_its_title_bar() -> void:
	# The camera page's own case: it declares a floor as tall as the canvas it lands on, which is what a
	# phone did to its 720, and the floor is taken below the page's own title bar rather than to the canvas
	# itself - the bar is drawn above the contents, so a floor equal to the canvas puts the whole bar off the
	# top of the screen.
	var page: Window = _page()
	add_child(page)
	var room: Vector2i = PageChromeScript.room_for(page)
	var bar: int = PageChromeScript.chrome_above(page)
	var floor: Vector2i = PageChromeScript.clamped_minimum(Vector2i(880, room.y), PageChromeScript.content_room(page))
	assert(
		floor.y == room.y - bar,
		"a floor as tall as the canvas is brought below the page's own title bar: %s" % str(floor),
	)
	assert(floor.y + bar <= room.y, "so the page and its bar together fit the canvas")
	remove_child(page)
	_free_pages()


## Opening a page is a place and not an anchor: `show_centred` reads the room once, and a page left up
## through a turn of the phone stays exactly where it opened. The doorway is what made that reachable - the
## front door follows the phone - so the room is read again and the page is put back in the middle of it.
func test_a_page_put_back_again_is_given_the_size_it_declares_rather_than_the_clamp_it_was_left() -> void:
	var page: Window = StartWindowScript.new()
	# What a room smaller than the page left on it: `min_size` holds last time's clamp, and a page brought
	# down to a landscape phone's 630 would never grow back to the 720 it asked for.
	page.min_size = Vector2i(300, 200)
	_pages.append(page)
	add_child(page)
	var declared: Vector2i = PageLayoutScript.declared_size(page)
	assert(declared == StartWindowScript.SIZE, "the page's own answer is the size it declares: %s" % str(declared))
	var floor: Vector2i = PageChromeScript.placed_again(page)
	assert(
		floor == PageChromeScript.clamped_minimum(declared, PageChromeScript.content_room(page)),
		"put back, the page is given the size it declares and not the clamp it was left: %s" % str(floor),
	)
	assert(page.min_size == floor, "and the floor it stands on now is the one it was given")
	remove_child(page)
	_free_pages()


func test_a_page_put_back_stands_where_a_page_opened_stands() -> void:
	# One arithmetic for both doors, which is what keeps them from drifting apart: a page opened and a page
	# put back in the same room stand in the same place, at the same size.
	var opened: Window = StartWindowScript.new()
	opened.build()
	_pages.append(opened)
	add_child(opened)
	PageChromeScript.show_centred(opened)
	var put_back: Window = StartWindowScript.new()
	put_back.build()
	_pages.append(put_back)
	add_child(put_back)
	PageChromeScript.placed_again(put_back)
	assert(
		put_back.position == opened.position,
		"a page put back stands where a page opened stands: %s against %s"
		% [str(put_back.position), str(opened.position)],
	)
	assert(put_back.size == opened.size, "and at the size the other one was given")
	remove_child(opened)
	remove_child(put_back)
	_free_pages()


func test_putting_no_page_back_answers_nothing() -> void:
	# The list a change of shape is walked over holds the front door before the HUD has built it.
	assert(
		PageChromeScript.placed_again(null) == Vector2i.ZERO,
		"a page that is not there is answered with nothing rather than placed",
	)


## A page's own words are text a person reads, and the twelve-pixel body a desk was drawn with comes to
## about a millimetre of capital on a phone - which is the measurement `PhoneHud.TEXT_MM` exists to refuse.
## So a page answered with a finger has its own sentences drawn at the legible size, and a line the page
## drew bigger than its body stays bigger by the same proportion: a page keeps its shape when it is made
## readable, instead of every line collapsing onto the size of a button.
func test_a_phones_page_has_its_own_words_made_legible_and_keeps_their_shape() -> void:
	var page: Window = _page()
	var root: VBoxContainer = PageChromeScript.column(page)
	var title: Label = PageChromeScript.heading("Begin a drawing")
	var body: Label = PageChromeScript.note("Start with an empty sheet and draw the site from nothing.")
	root.add_child(title)
	root.add_child(body)

	var measured: int = PageChromeScript.size_the_words_for_a_finger(page, PHONE_SCALE, PHONE_DPI)
	assert(measured == 3, "the page's two sentences and its own title bar were measured: %d" % measured)
	var legible: int = PhoneHudScript.font_size(PHONE_SCALE, PHONE_DPI)
	assert(
		body.get_theme_font_size("font_size") == legible,
		"the body sentence is drawn at the size a TEXT_MM capital comes to: %d" % legible,
	)
	assert(
		title.get_theme_font_size("font_size") > legible,
		"and a line the page drew bigger is still the bigger of the two: %d against %d"
		% [title.get_theme_font_size("font_size"), legible],
	)
	assert(
		page.get_theme_font_size(&"title_font_size", &"Window") >= legible,
		"and the page's own title bar is grown with them, because a title is words too: %d"
		% page.get_theme_font_size(&"title_font_size", &"Window"),
	)
	_free_pages()


## A page opened a second time is the same page: its words are grown once, from the size the page laid them
## out at. Godot keeps only the answer that replaced that size, so what the page drew with is remembered -
## otherwise every open would grow the page again.
func test_a_page_opened_again_on_a_phone_is_grown_once() -> void:
	var page: Window = _page()
	var root: VBoxContainer = PageChromeScript.column(page)
	var title: Label = PageChromeScript.heading("Begin a drawing")
	root.add_child(title)

	PageChromeScript.size_the_words_for_a_finger(page, PHONE_SCALE, PHONE_DPI)
	var once: int = title.get_theme_font_size("font_size")
	PageChromeScript.size_the_words_for_a_finger(page, PHONE_SCALE, PHONE_DPI)
	assert(
		title.get_theme_font_size("font_size") == once,
		"a page whose words have been grown is left at the size they were grown to: %d, was %d"
		% [title.get_theme_font_size("font_size"), once],
	)
	_free_pages()


## And a computer's page is the page this project designed: the rule is asked once, in the one place a page
## is shown, and there the answer is no.
func test_a_computers_page_keeps_the_words_the_page_wrote() -> void:
	var page: Window = _page()
	var root: VBoxContainer = PageChromeScript.column(page)
	var body: Label = PageChromeScript.note("Start with an empty sheet.")
	root.add_child(body)
	TouchInputScript.force(TouchInputScript.Answer.MOUSE)

	PageChromeScript.size_for_a_finger(page)
	assert(
		body.get_theme_font_size("font_size") == PageChromeScript.BODY_SIZE,
		"a body line on a computer is drawn at the size the page gave it: %d, not %d"
		% [body.get_theme_font_size("font_size"), PageChromeScript.BODY_SIZE],
	)
	TouchInputScript.force(TouchInputScript.Answer.AUTO)
	_free_pages()


## A page whose words no longer fit the room it landed in is given a scroll as it is shown, so that its own
## bottom - nearly always its buttons - can still be reached rather than being cut off. This is what makes
## the words being made legible safe: on a phone they make every page taller, and a page that could not
## scroll would simply lose the row it ends with.
func test_a_page_too_tall_for_the_room_it_landed_in_is_given_a_scroll() -> void:
	var page: Window = _page()
	# The floor is stated so the test does not depend on the screen it runs on: the page asks for a short
	# page, and its contents want far more than that.
	page.min_size = Vector2i(400, 300)
	add_child(page)
	var root: VBoxContainer = PageChromeScript.column(page)
	var tall: Control = Control.new()
	tall.custom_minimum_size = Vector2(0.0, 4000.0)
	root.add_child(tall)

	PageChromeScript.show_centred(page)
	var wrapped: ScrollContainer = PageLayoutScript.scroll_of(root)
	assert(wrapped != null, "the page's own bottom can be scrolled to rather than cut off")
	assert(wrapped.get_parent() == page, "the wrapper stands where the column stood, in the page")
	assert(
		wrapped.vertical_scroll_mode != ScrollContainer.SCROLL_MODE_DISABLED,
		"and it really scrolls the length rather than merely holding it",
	)
	remove_child(page)
	_free_pages()


## A page that fits is left exactly as it was built: the wrapper is a repair for a page that does not fit, not
## something every page gets. A computer's page, whose room is bigger than every page this project declares,
## is never wrapped at all.
func test_a_page_that_fits_the_room_it_landed_in_keeps_the_column_it_built() -> void:
	var page: Window = _page()
	page.min_size = Vector2i(400, 800)
	add_child(page)
	var root: VBoxContainer = PageChromeScript.column(page)
	var line: Label = PageChromeScript.note("A short page.")
	root.add_child(line)

	PageChromeScript.show_centred(page)
	assert(PageLayoutScript.scroll_of(root) == null, "a page that fits keeps the column its page built")
	assert(root.get_parent() == page, "and its column is still the page's own child")
	remove_child(page)
	_free_pages()


## A page that was *built* to scroll already has a wrapper, and is left with the one it built - a page inside
## two scrolls is a page nobody can scroll.
func test_a_page_that_already_scrolls_is_not_wrapped_a_second_time() -> void:
	var page: Window = _page()
	page.min_size = Vector2i(400, 300)
	add_child(page)
	var root: VBoxContainer = PageChromeScript.scrolling_column(page)
	var tall: Control = Control.new()
	tall.custom_minimum_size = Vector2(0.0, 4000.0)
	root.add_child(tall)

	PageChromeScript.show_centred(page)
	var wrappers: Array[Node] = page.find_children("*", "ScrollContainer", true, false)
	assert(
		wrappers.size() == 1,
		"the page keeps the one scroll it built rather than gaining a second: %d" % wrappers.size(),
	)
	remove_child(page)
	_free_pages()


## **The floor a page lands on is the size it declares, not `min_size`.** A page that has never been placed has
## `min_size` zero, and a floor of zero is no floor at all: `clamped_minimum` answers zero, Godot's
## `popup_centered_clamped` falls back to what the page's contents want, and nothing is held against the room.
## Measured on a 1600 by 900 desk: the sun page declares 1020 by 820 where the room allows 802, landed 820 tall
## at y=89, and stood 9 px past the foot of the screen - a fault `gui_sweep` named and the arithmetic should have
## prevented.
##
## The width is the exception, and this holds that too: `_place` leaves the width a page was granted on
## `min_size.x`, so reading only what the page declares would undo the widening a phone gave it.
func test_the_floor_a_page_lands_on_is_the_size_it_declares_and_not_a_zero_minimum() -> void:
	var page: Window = _page()
	page.set_script(StartWindowScript)
	# A page whose `min_size` says nothing at all, which is what a page the HUD has just built reads - measured
	# on the desk: the sun page's own minimum was zero when the door was called.
	page.min_size = Vector2i.ZERO
	assert(
		PageChromeScript.the_floor_a_page_lands_on(page) == StartWindowScript.SIZE,
		"a page whose minimum says nothing still lands on the size it declares: %s"
		% str(PageChromeScript.the_floor_a_page_lands_on(page)),
	)
	page.min_size = Vector2i(StartWindowScript.SIZE.x + 200, 100)
	assert(
		PageChromeScript.the_floor_a_page_lands_on(page)
		== Vector2i(StartWindowScript.SIZE.x + 200, StartWindowScript.SIZE.y),
		"and a page already given a width keeps it, taking the height it declares: %s"
		% str(PageChromeScript.the_floor_a_page_lands_on(page)),
	)
	_free_pages()


## **A page's contents can outgrow it after it has landed**, which one reading at landing time cannot see: a
## `Container` works out what it needs on the frame *after* its width changes. Measured on the desk: the sowing
## page's column reported 750 when it landed and 801 four frames later, so no wrap was made and its `Column` and
## `Status` stood 13 px past the foot of the room - words a person could not reach at all.
func test_a_column_that_outgrows_its_page_after_landing_is_wrapped_in_a_scroll() -> void:
	var page: Window = _page()
	page.min_size = Vector2i(400, 300)
	add_child(page)
	var root: VBoxContainer = PageChromeScript.column(page)
	var row: Control = Control.new()
	row.custom_minimum_size = Vector2(0.0, 100.0)
	root.add_child(row)

	PageChromeScript.show_centred(page)
	assert(PageLayoutScript.scroll_of(root) == null, "a page whose contents fit it is left exactly as it was built")
	row.custom_minimum_size = Vector2(0.0, 4000.0)
	await get_tree().process_frame
	await get_tree().process_frame
	assert(
		PageLayoutScript.scroll_of(root) != null,
		"and a column that grows past its page is wrapped the moment it says its size has changed",
	)
	remove_child(page)
	_free_pages()


## **The wrapper stands exactly where the column stood.** A page's column is anchored to the page's four edges and
## its offsets are the padding - but a column given a rectangle of its own carries that rectangle in the same four
## numbers, and a wrapper anchored to the page's edges reads them as padding instead. Measured on the desk: the
## plant library's page 1080 px wide inside a 1600 px room, its new scroll drawn 808 px past the right edge and
## 607 px past the foot - a control nobody could reach, named by the very next sweep.
func test_the_scroll_a_page_is_given_stands_where_the_column_stood() -> void:
	var page: Window = _page()
	page.min_size = Vector2i(400, 300)
	add_child(page)
	var root: VBoxContainer = PageChromeScript.column(page)
	# A column with a rectangle of its own rather than the page's edges, which is the plant library's shape.
	root.set_anchors_preset(Control.PRESET_TOP_LEFT)
	root.offset_left = 24.0
	root.offset_top = 24.0
	root.offset_right = 224.0
	root.offset_bottom = 124.0
	var stood_at: Rect2 = root.get_rect()
	var tall: Control = Control.new()
	tall.custom_minimum_size = Vector2(0.0, 4000.0)
	root.add_child(tall)

	PageChromeScript.show_centred(page)
	var scroll: ScrollContainer = PageLayoutScript.scroll_of(root)
	assert(scroll != null, "a column too tall for its page is wrapped")
	assert(
		scroll.get_rect() == stood_at,
		"and the wrapper stands where the column stood: %s against %s" % [str(scroll.get_rect()), str(stood_at)],
	)
	remove_child(page)
	_free_pages()


## A page whose contents want more height than the room it landed in is given **the room** - across and down -
## before it is given a scroll. On a phone a page is laid out for a desk and comes out a band in the middle of
## the screen with its buttons below the fold: the width is what makes its sentences short enough to read, and
## the height is what puts its last row on the glass at all. What even the room cannot hold still scrolls.
func test_a_page_too_tall_on_a_phone_is_given_the_room() -> void:
	PhoneHudScript.force_density(PHONE_DPI)
	TouchInputScript.force(TouchInputScript.Answer.FINGER)
	var page: Window = _page()
	page.min_size = Vector2i(400, 300)
	add_child(page)
	var root: VBoxContainer = PageChromeScript.column(page)
	var tall: Control = Control.new()
	tall.custom_minimum_size = Vector2(0.0, 4000.0)
	root.add_child(tall)

	var landed_at: Vector2i = PageChromeScript.show_centred(page)
	assert(landed_at.x > 400, "the page is given more than the width it asked for: %d" % landed_at.x)
	assert(
		landed_at == PageChromeScript.content_room(page),
		"and it is the whole room, both ways: %s against %s"
		% [str(landed_at), str(PageChromeScript.content_room(page))],
	)
	# Four thousand pixels of rows cannot be made to fit by any room, so the second cure follows the first
	# rather than replacing it.
	assert(PageLayoutScript.scroll_of(root) != null, "and what the room cannot hold still scrolls")
	remove_child(page)
	_free_pages()
	PhoneHudScript.force_density(0.0)
	TouchInputScript.force(TouchInputScript.Answer.AUTO)


## On a computer nothing is given the room. The first of the three questions `fit_the_room_to_the_page` asks is
## "is this a device answered with a finger", and a desk answers no to it - which is what keeps every page a
## desk sees the page this project designed, and keeps the page layout check measuring those.
func test_a_page_too_tall_on_a_computer_keeps_the_size_its_page_declared() -> void:
	PhoneHudScript.force_density(144.0)
	TouchInputScript.force(TouchInputScript.Answer.MOUSE)
	var page: Window = _page()
	page.min_size = Vector2i(400, 300)
	add_child(page)
	var root: VBoxContainer = PageChromeScript.column(page)
	var tall: Control = Control.new()
	tall.custom_minimum_size = Vector2(0.0, 4000.0)
	root.add_child(tall)

	var landed_at: Vector2i = PageChromeScript.show_centred(page)
	assert(landed_at.x == 400, "a desk's page keeps the width its page declared: %d" % landed_at.x)
	assert(landed_at.y <= 300, "and the height it declared, brought down to the room: %d" % landed_at.y)
	remove_child(page)
	_free_pages()
	PhoneHudScript.force_density(0.0)
	TouchInputScript.force(TouchInputScript.Answer.AUTO)


## The width is the repair for a page that has outgrown its own, not something every page on a phone gets: a
## page with room to spare keeps the shape its own author chose for it.
func test_a_phones_page_that_fits_keeps_the_width_its_page_declared() -> void:
	PhoneHudScript.force_density(PHONE_DPI)
	TouchInputScript.force(TouchInputScript.Answer.FINGER)
	var page: Window = _page()
	page.min_size = Vector2i(400, 800)
	add_child(page)
	var root: VBoxContainer = PageChromeScript.column(page)
	root.add_child(PageChromeScript.note("A short page."))

	var landed_at: Vector2i = PageChromeScript.show_centred(page)
	assert(landed_at.x == 400, "a phone's page that fits keeps its own width: %d" % landed_at.x)
	remove_child(page)
	_free_pages()
	PhoneHudScript.force_density(0.0)
	TouchInputScript.force(TouchInputScript.Answer.AUTO)


## The page this was written for. The door's own comment records that its first version declared 520 by 320
## and, on the SM-A166W, its Close button fell off the bottom edge - so the height was raised and the width
## was never questioned. The bigger words made both matter: at 520 a phone wraps the opening sentence onto
## most of the page, and the door came out a card **45.1% of the screen's width and 24.1% of its height**,
## centred, with its buttons below the fold. Measured off two screenshots of that phone.
func test_the_front_door_uses_the_room_on_a_phone() -> void:
	PhoneHudScript.force_density(PHONE_DPI)
	TouchInputScript.force(TouchInputScript.Answer.FINGER)
	var door := StartWindowScript.new()
	door.build()
	_pages.append(door)
	add_child(door)

	var landed_at: Vector2i = PageChromeScript.show_centred(door)
	assert(landed_at.x > StartWindowScript.SIZE.x, "the door is wider than the 520 it declares: %d" % landed_at.x)
	assert(landed_at.y >= StartWindowScript.SIZE.y, "and as tall as it declared, at least: %d" % landed_at.y)
	assert(
		landed_at == PageChromeScript.content_room(door),
		"because it is given the whole room it landed in: %s against %s"
		% [str(landed_at), str(PageChromeScript.content_room(door))],
	)
	remove_child(door)
	_free_pages()
	PhoneHudScript.force_density(0.0)
	TouchInputScript.force(TouchInputScript.Answer.AUTO)


## The front door's first choice takes the keyboard whenever the door comes up.
##
## The fault this holds: a door opened with nothing in hand did nothing at all when Enter was pressed - measured
## with a real key delivered to the running game. A door shown by the **shared show** had its buttons promoted
## for it (`PageChrome` is the one place that does that), but a door shown by **its own route** - which is how
## the audit opens every page, and how a page's own `open()` shows it - had not, and grabbing a button with no
## keyboard of its own is an engine error, not a refusal. The audit reported exactly that on every page it
## opened. So the handler asks `PageChrome` for the promotion first, and this holds both halves.
func test_the_front_door_gives_its_first_choice_the_keyboard_even_shown_by_its_own_route() -> void:
	var door: Window = StartWindowScript.new()
	door.build()
	_pages.append(door)
	add_child(door)
	# Shown the way a page's own route shows it: no shared show, so nothing has promoted the buttons, which are
	# built with no keyboard of their own - the same as every other page's.
	door.visible = true

	var choices: Array[StringName] = door.choice_buttons()
	assert(choices.size() > 0, "the door offers a choice for the keyboard to land on")
	var first: Button = door.button_of(choices[0])
	assert(first != null, "and that choice is a button: %s" % str(choices[0]))
	assert(
		first.focus_mode == Control.FOCUS_NONE,
		"a page's button is built with no keyboard of its own, as the HUD's buttons are",
	)

	door._give_the_first_choice_the_keyboard()
	assert(
		first.focus_mode == Control.FOCUS_ALL,
		"the door's own handler gives it one, through the one place that decides it: %d" % first.focus_mode,
	)
	assert(first.has_focus(), "and the first choice is what is in hand when the door opens")

	remove_child(door)
	_free_pages()


## A page given the room keeps it when the room changes shape under it.
##
## `show_centred` and `placed_again` are two doors to one arithmetic, and the phone's cure - a page that has
## outgrown the size it declared is given the room, because a wider page is a shorter page - has to survive
## both. Measured on the A16W: a page standing 1080 screen px wide (the whole room) came back at 474 px, the
## 540 it declares, as soon as the room changed shape under it. That is also how the front door is left at
## 474 px of a 1080 px screen: it is shown during the HUD's `_ready` and the chrome pass that follows calls
## `_the_canvas_changed_shape()`, which puts every page that is up back through `placed_again`.
func test_a_page_given_the_room_keeps_it_when_the_room_changes_shape() -> void:
	PhoneHudScript.force_density(PHONE_DPI)
	TouchInputScript.force(TouchInputScript.Answer.FINGER)
	var door: Window = StartWindowScript.new()
	door.build()
	_pages.append(door)
	add_child(door)

	var opened_at: Vector2i = PageChromeScript.show_centred(door)
	assert(opened_at.x > StartWindowScript.SIZE.x, "the door opens wider than the 520 it declares: %d" % opened_at.x)
	var put_back_at: Vector2i = PageChromeScript.placed_again(door)
	assert(
		put_back_at.x == opened_at.x,
		"and a change of the room's shape under it keeps the width it was given: %s against %s"
		% [str(put_back_at), str(opened_at)],
	)

	remove_child(door)
	_free_pages()
	PhoneHudScript.force_density(0.0)
	TouchInputScript.force(TouchInputScript.Answer.AUTO)


## A page put back keeps the width it was given, however narrow the size it declares.
##
## `placed_again` starts from what a page declares so that a page clamped to a landscape phone grows back to the
## **height** it asked for - a reason about height, which is what its own comment gives. The width is the half a
## phone's cure depends on: a page that has outgrown what it declared is given the room, which is wider as well as
## taller, and `_place` leaves that width on `min_size.x`. Taking the width back therefore **undoes the widening**,
## which is what left the front door standing 474 px of a 1080 px screen with its title cut short and both choices
## below a scroll.
##
## Pinned here as the **rule** rather than through a simulation, because the simulation agrees with the fault:
## `test_a_page_given_the_room_keeps_it_when_the_room_changes_shape` passes against a `placed_again` that takes
## the width back, so it cannot hold this one down. A page whose own `min_size` is wider than it declares, put
## back again, keeps that width and takes the height it declares.
func test_a_page_put_back_keeps_the_width_it_was_given_rather_than_the_one_it_declares() -> void:
	var door: Window = StartWindowScript.new()
	door.build()
	_pages.append(door)
	add_child(door)

	# What a widening leaves behind: the width the page was given, wider than the 520 it declares.
	var given: int = StartWindowScript.SIZE.x + 100
	door.min_size = Vector2i(given, StartWindowScript.SIZE.y)
	var put_back_at: Vector2i = PageChromeScript.placed_again(door)
	assert(
		put_back_at.x == given,
		"the width it was given is kept: %d, against the %d it declares" % [put_back_at.x, StartWindowScript.SIZE.x],
	)
	assert(
		put_back_at.y == StartWindowScript.SIZE.y,
		"and the height is the one it declares, which is the half that floor is for: %d" % put_back_at.y,
	)

	remove_child(door)
	_free_pages()


## And the same door on a computer is exactly the page its author declared - 520 by 540 - which is the half of
## this that has to be provable rather than merely likely: the desk's rendering is unchanged by any of it.
func test_the_front_door_on_a_computer_is_the_size_it_declares() -> void:
	PhoneHudScript.force_density(144.0)
	TouchInputScript.force(TouchInputScript.Answer.MOUSE)
	var door := StartWindowScript.new()
	door.build()
	_pages.append(door)
	add_child(door)

	var landed_at: Vector2i = PageChromeScript.show_centred(door)
	var room: Vector2i = PageChromeScript.content_room(door)
	assert(
		landed_at == PageChromeScript.clamped_minimum(StartWindowScript.SIZE, room),
		"a desk's door is the size it declares, or the room if the room is smaller: %s" % str(landed_at),
	)
	assert(landed_at.x == StartWindowScript.SIZE.x, "which is its own 520 across: %d" % landed_at.x)
	remove_child(door)
	_free_pages()
	PhoneHudScript.force_density(0.0)
	TouchInputScript.force(TouchInputScript.Answer.AUTO)


func test_a_phones_page_has_its_menus_made_legible_and_its_fields_left_alone() -> void:
	var page: Window = _page()
	var root: VBoxContainer = PageChromeScript.column(page)
	var picker: OptionButton = OptionButton.new()
	root.add_child(picker)
	var field: LineEdit = LineEdit.new()
	root.add_child(field)

	var measured: int = PageChromeScript.size_the_words_for_a_finger(page, PHONE_SCALE, PHONE_DPI)
	assert(measured == 2, "the menu the picker opens and the title bar were measured: %d" % measured)
	assert(
		picker.get_popup().get_theme_font_size("font_size") > 12,
		"so the menu opens at a size a thumb can read: %d" % picker.get_popup().get_theme_font_size("font_size"),
	)
	assert(
		not field.has_theme_font_size_override("font_size"),
		"while a field inside the page keeps the size the page's own layout gave it",
	)
	_free_pages()


## On a phone the page **is** the screen, so a page's contents are held off the sides of it: a window has a
## frame between its words and the edge, and a phone has none. Measured on the SM-A166W, 2026-11: the front
## door's own opening sentence ran to within three pixels of the glass and its two choices ran the whole
## width of it. **Across only** - a margin taken off the length would push a page's last row below the fold,
## which is the fault the room and the scroll are there to answer.
func test_a_phones_page_keeps_a_margin_from_the_sides_of_the_screen() -> void:
	var page: Window = _page()
	var root: VBoxContainer = PageChromeScript.column(page)
	root.add_child(PageChromeScript.note("A sentence."))

	var margin: int = PhoneHudScript.edge_margin(PHONE_SCALE, PHONE_DPI)
	assert(margin > 0, "half a thumb is a margin at all: %d" % margin)
	assert(
		PageChromeScript.inset_the_contents_for_a_finger(page, PHONE_SCALE, PHONE_DPI) == 1,
		"so the page's contents were inset",
	)
	assert(
		root.offset_left == float(margin) and root.offset_right == float(-margin),
		"held off both edges: %s" % str([root.offset_left, root.offset_right]),
	)
	assert(
		root.offset_top == 0.0 and root.offset_bottom == 0.0,
		"and off neither end, because a page made taller loses its own last row",
	)
	# Fitting twice is fitting once: a page shown again must not walk its contents inwards a second time.
	PageChromeScript.inset_the_contents_for_a_finger(page, PHONE_SCALE, PHONE_DPI)
	assert(root.offset_left == float(margin), "a page inset twice is inset once: %f" % root.offset_left)
	_free_pages()


## And the margin is **added to** the padding a page chose for itself rather than written over it: the front
## door insets nothing and the field and food pages inset 16 by 12, and both keep what they asked for.
func test_a_phones_margin_is_added_to_the_padding_the_page_chose() -> void:
	var page: Window = _page()
	var root: VBoxContainer = PageChromeScript.column(page, 8, Vector2(16.0, 12.0))
	root.add_child(PageChromeScript.note("A sentence."))
	var margin: int = PhoneHudScript.edge_margin(PHONE_SCALE, PHONE_DPI)

	PageChromeScript.inset_the_contents_for_a_finger(page, PHONE_SCALE, PHONE_DPI)
	assert(
		root.offset_left == 16.0 + float(margin),
		"the page's own left padding and the margin: %f" % root.offset_left,
	)
	assert(
		root.offset_right == -16.0 - float(margin),
		"and its own right padding and the margin: %f" % root.offset_right,
	)
	assert(
		root.offset_top == 12.0 and root.offset_bottom == -12.0,
		"while the padding it chose down its length is left exactly as it was",
	)
	_free_pages()


## A computer's page is the page this project designed, to the pixel: the device question is asked once, in
## the one place a page is shown, and a desk answers no to it before reading anything.
func test_a_computers_page_is_not_inset_for_a_finger() -> void:
	TouchInputScript.force(TouchInputScript.Answer.MOUSE)
	var page: Window = _page()
	var root: VBoxContainer = PageChromeScript.column(page)
	root.add_child(PageChromeScript.note("A sentence."))

	assert(PageChromeScript.size_for_a_finger(page) == 0, "nothing is fitted for a mouse")
	assert(
		root.offset_left == 0.0 and root.offset_right == 0.0,
		"and the page's contents keep the whole page: %s" % str([root.offset_left, root.offset_right]),
	)
	TouchInputScript.force(TouchInputScript.Answer.AUTO)
	_free_pages()

# --- the one door a page is shown by -----------------------------------------------------------


## Every `.gd` under `res://scripts`, subfolders and all, read with `DirAccess`'s own two listings.
func _every_script_here() -> PackedStringArray:
	var found: PackedStringArray = PackedStringArray()
	var folders: Array[String] = ["res://scripts"]
	while not folders.is_empty():
		var folder: String = folders.pop_back()
		for name: String in DirAccess.get_files_at(folder):
			if name.ends_with(".gd"):
				found.append(folder.path_join(name))
		for name: String in DirAccess.get_directories_at(folder):
			folders.append(folder.path_join(name))
	return found


## **A page is shown by `PageChrome`'s door and by nothing else.**
##
## Three doors showed a page themselves until 2026-11-14 - the plant library, the command palette and the
## manual - each keeping its own floor and calling `popup_centered` on itself, and all three were therefore
## pages a phone drew in the desk's type: 67 short controls and 74 unreadable lines on the first, three short
## on the second, five unreadable on the third. Read by `tools/phone_touch_sweep.gd` at a phone's own 450 dpi,
## and cured by one line each.
##
## Two shapes are caught, and both need only the shape of the code, so this runs with no screen:
##
## - a window that **shows itself** - the line begins with the call. A page that pops its own frame has kept
##   its own floor, its own clamp and its own place, which is what `PageChrome` exists to be the one author
##   of.
## - a window **shown from outside** by any file but `page_chrome.gd`. The receivers allowed are named,
##   because a rule that cannot tell a page from the engine's own furniture names a word rather than a fault:
##   every `FileDialog` here is held in a variable ending `_dialog`, and the one `ConfirmationDialog` is
##   `question` in `Hud._ask`, whose own comment says, with its measurements, why a question places itself.
##
## What a page that has been through the door looks like on the glass is not tested here - that needs a
## screen, and `tools/phone_touch_sweep.gd` is the instrument for it.
func test_a_page_is_shown_by_the_one_door_and_by_no_other() -> void:
	var offenders: Array[String] = []
	var the_door_itself: bool = false
	for path: String in _every_script_here():
		var lines: PackedStringArray = FileAccess.get_file_as_string(path).split("\n")
		for at: int in lines.size():
			# The comment is dropped before the line is read: this program names the call in prose now, to say
			# why it no longer makes it, and a rule that read the prose would name the explanation as the fault.
			var code: String = lines[at].split("#")[0].strip_edges()
			if not code.contains("popup_centered"):
				continue
			if path.get_file() == "page_chrome.gd":
				the_door_itself = true
				continue
			if code.begins_with("popup_centered"):
				offenders.append("%s:%d %s" % [path.trim_prefix("res://scripts/"), at + 1, code])
				continue
			# Shown from outside: the receiver is the last name before the call, so a page held as
			# `node._my_page` is judged by `_my_page` rather than by the node it hangs off.
			var shown: String = code.split(".popup_centered")[0].strip_edges()
			shown = shown.substr(shown.rfind(".") + 1)
			if shown == "question" or shown.ends_with("dialog"):
				continue
			offenders.append("%s:%d %s" % [path.trim_prefix("res://scripts/"), at + 1, code])
	assert(the_door_itself, "the door is still the thing that shows a page")
	assert(
		offenders.is_empty(),
		"a page is shown by PageChrome.show_centred and by nothing else; these show one themselves: %s" % str(offenders),
	)
