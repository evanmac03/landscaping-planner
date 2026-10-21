extends Node
## The sun and shadow study's page, driven off-tree.
##
## No director, no drawing, no HUD, no window server and no `popup_centered`: that split is what the
## page is for, and it is why the whole of what the page decides can be tested here. Every press goes
## through the caption a person reads, so a test cannot keep passing after a caption has been changed
## to something nobody would recognise.
##
## Two claims are worth more than the rest: **the page promises only the stills it can render** - the
## moments with the sun up, counted once and the same way in the hint, the button and what the render
## asks for - and **the status is not the guidance**, because a page whose status line is rewritten
## every time the study changes cannot say what it last did.

const SunWindowScript := preload("res://scripts/sun_window.gd")
const SunReportScript := preload("res://scripts/vis/sun_report.gd")
const SunStudyScript := preload("res://scripts/vis/sun_study.gd")
const UnitsScript := preload("res://scripts/draft/units.gd")

const SITE := {"latitude": 45.0, "longitude": -75.0, "utc_offset_hours": -5.0}

## What the page announced, in order. A member rather than a captured local, because a lambda
## captures what it is given rather than sharing it.
var _announced: Array[String] = []


# --- helpers --------------------------------------------------------------------------


func _page() -> SunWindow:
	var page := SunWindowScript.new()
	page.build()
	page.apply_requested.connect(func(moment: Dictionary) -> void:
		_announced.append("apply:%s" % SunReportScript.moment_words(moment)))
	page.render_requested.connect(func(moments: Array) -> void:
		_announced.append("render:%d" % moments.size()))
	page.closed.connect(func() -> void: _announced.append("close"))
	return page


## A page pointed at the Ottawa site with a June day on it, which is the state most of these tests
## start from.
func _studying() -> SunWindow:
	var page: SunWindow = _page()
	page.bind(SITE)
	page.use_preset(&"june_day")
	return page


## Press a button by the caption a person reads.
func _press(page: SunWindow, caption: String) -> bool:
	for found: Node in page.find_children("*", "Button", true, false):
		var button := found as Button
		if button.text == caption:
			button.pressed.emit()
			return true
	return false


## The one announcement a press made, or "" when the page carries no such button.
func _ask(page: SunWindow, caption: String) -> String:
	var before: int = _announced.size()
	if not _press(page, caption):
		return ""
	return _announced[_announced.size() - 1] if _announced.size() > before else ""


func _control(page: SunWindow, node_name: String) -> Node:
	var found: Node = page.find_child(node_name, true, false)
	return found


## The captions of every button on the page, so a test can press a preset by the words a person
## reads rather than by a name it made up.
func _preset_caption(preset_name: StringName) -> String:
	return "Study %s" % SunReportScript.preset_name(preset_name)


# --- the page itself ------------------------------------------------------------------


func test_the_page_has_the_controls_a_page_like_this_has() -> void:
	var page: SunWindow = _page()
	for node_name: String in [
		"Column", "Heading", "Explanation", "SiteLine", "HeightBox", "DayBox", "HourBox",
		"Moments", "Rows", "Summary", "Hint", "ApplyButton", "RenderButton", "CloseButton", "Status",
	]:
		assert(
			_control(page, node_name) != null,
			"the page carries a %s" % node_name
		)
	page.free()


func test_building_the_page_twice_builds_it_once() -> void:
	var page: SunWindow = SunWindowScript.new()
	page.build()
	page.build()
	assert(
		page.find_children("HeightBox", "SpinBox", true, false).size() == 1,
		"one height field, however many times the page is built"
	)
	page.free()


func test_building_the_page_takes_it_off_the_screen() -> void:
	var page: SunWindow = SunWindowScript.new()
	page.build()
	assert(not page.visible, "a page nobody has asked for is not over the drawing")
	page.free()


func test_a_page_with_no_site_says_what_it_is_waiting_for() -> void:
	var page: SunWindow = _page()
	assert(not page.has_site(), "there is no site yet")
	assert(page.hint() == SunWindowScript.NO_SITE, "and the page says so: %s" % page.hint())
	assert(page.row_count() == 0, "with no study in hand")
	assert(page.row_texts().is_empty(), "and no rows")
	page.bind({})
	assert(page.hint() == SunWindowScript.NO_SITE, "an empty site is no site")
	page.free()


func test_binding_a_site_fills_the_page_from_the_study() -> void:
	var page: SunWindow = _studying()
	assert(page.has_site(), "the page holds the site it was given")
	assert(int(page.site()["latitude"]) == 45, "and it is the site it was told")
	assert(page.moment_count() == 6, "a June day is six moments")
	assert(page.row_count() == 6, "one row a moment")
	assert(page.row_texts().size() == 6, "and the rows are written")
	assert(
		page.report_summary().contains("6 moments"),
		"the summary is the study's own sentence: %s" % page.report_summary()
	)
	assert(
		page.hint() == SunWindowScript.NO_CHOICE,
		"and with a study in hand the page asks for a moment to aim at: %s" % page.hint()
	)
	page.choose_moment(0)
	assert(
		page.hint().contains("45.0°N"),
		"once one is chosen the guidance names the place being studied: %s" % page.hint()
	)
	page.free()


func test_the_rows_are_the_studys_own_rows() -> void:
	var page: SunWindow = _studying()
	var by_hand: Array[String] = SunReportScript.row_texts(
		page.site(), page.moments(), page.height_m(), page.units_in_hand()
	)
	var on_page: Array[String] = page.row_texts()
	assert(on_page.size() == by_hand.size(), "the page shows one row a moment")
	for index in by_hand.size():
		assert(
			on_page[index] == by_hand[index],
			"and the row is the module's own: %s" % on_page[index]
		)
	page.free()


func test_the_rows_are_only_written_when_the_study_changes() -> void:
	var page: SunWindow = _studying()
	assert(
		not page.show_rows(page.study_rows()),
		"a second writing of the study already on the page writes nothing"
	)
	page.set_height(3.6)
	assert(
		not page.show_rows(page.study_rows()),
		"and a change writes its own rows through the refresh, not twice"
	)
	# A study the page has not shown - the same moments at another height - is a different list and
	# is written.
	var at_two_five: Array = SunReportScript.rows(
		page.site(), page.moments(), 2.5, page.units_in_hand()
	)
	assert(page.show_rows(at_two_five), "a study the page has not shown is written")
	assert(not page.show_rows(at_two_five), "and written once")
	page.free()


func test_the_day_lines_are_one_a_day_the_study_covers() -> void:
	var page: SunWindow = _studying()
	assert(page.day_lines().size() == 1, "a June day is one day")
	assert(
		String(page.day_lines()[0]).contains("sunrise"),
		"and the day's own light is stated: %s" % String(page.day_lines()[0])
	)
	page.use_preset(&"solstices")
	assert(page.day_lines().size() == 2, "the two solstices are two days")
	page.free()


func test_the_lists_cannot_take_the_keyboard_and_the_number_fields_can() -> void:
	var page: SunWindow = _studying()
	assert(page.lists_are_keyboard_free(), "neither list takes a key from the drawing")
	for found: Node in page.find_children("*", "Button", true, false):
		assert(
			(found as Button).focus_mode == Control.FOCUS_NONE,
			"and no button on the page does either: %s" % found.name
		)
	page.free()


# --- choosing the moments -------------------------------------------------------------


func test_a_preset_replaces_the_list_and_an_unknown_one_is_refused() -> void:
	var page: SunWindow = _page()
	page.bind(SITE)
	assert(page.use_preset(&"june_day"), "a June day is a study the page has")
	assert(page.moment_count() == 6, "and it is six moments")
	assert(page.use_preset(&"a sunny tuesday") == false, "a study nobody has is refused")
	assert(page.moment_count() == 6, "and the study in hand is left alone")
	assert(
		page.said().contains("no study called"),
		"the refusal is said on the page: %s" % page.said()
	)
	page.free()


func test_the_fields_add_the_moment_a_person_describes() -> void:
	var page: SunWindow = _studying()
	page.clear_moments()
	assert(page.moment_count() == 0, "the list is empty")
	page.set_day(172)
	page.set_hour(14.0)
	assert(_ask(page, "Add the moment") == "", "the button acts rather than asking for anything")
	assert(page.moment_count() == 1, "the moment the fields describe is added")
	assert(
		page.said().contains("21 June 14:00"),
		"and the page says which moment: %s" % page.said()
	)
	page.free()


func test_the_same_moment_twice_is_one_moment() -> void:
	var page: SunWindow = _studying()
	page.clear_moments()
	page.set_day(172)
	page.set_hour(14.0)
	page._on_add_pressed()
	assert(page.moment_count() == 1, "the moment is on the list")
	page._on_add_pressed()
	assert(page.moment_count() == 1, "and adding it again adds nothing")
	assert(
		page.said().contains("already"),
		"because two rows would be one moment studied twice: %s" % page.said()
	)
	page.free()


func test_removing_needs_a_chosen_moment() -> void:
	var page: SunWindow = _studying()
	assert(not page.remove_selected(), "with nothing chosen there is nothing to take off")
	page._on_remove_pressed()
	assert(
		page.said().contains("choose a moment"),
		"and the page says so: %s" % page.said()
	)
	page._on_moment_selected(0)
	assert(page.selected_index() == 0, "choosing the first moment")
	page._on_remove_pressed()
	assert(page.moment_count() == 5, "and taking it off leaves the rest")
	assert(
		page.said().contains("took moment 1 off"),
		"and the status says what was taken off: %s" % page.said()
	)
	page.free()


func test_choosing_a_moment_says_which_one_it_is() -> void:
	var page: SunWindow = _studying()
	# Through the signal the list emits when a person clicks a row, which is the only way choosing
	# says anything about itself.
	page._on_moment_selected(2)
	assert(page.selected_index() == 2, "the chosen row is the chosen row")
	assert(
		SunReportScript.day_of(page.selected_moment()) == SunReportScript.JUNE_SOLSTICE,
		"and it is a moment of the study"
	)
	assert(
		page.said().contains("21 June 12:00"),
		"and the page names it: %s" % page.said()
	)
	page._on_moment_selected(9)
	assert(
		page.selected_index() == 2,
		"and a click on a row that is not there leaves the choice alone"
	)
	page.free()


func test_a_preset_button_installs_the_study_its_caption_names() -> void:
	var page: SunWindow = _page()
	page.bind(SITE)
	assert(
		_press(page, _preset_caption(&"december_day")),
		"the page carries a button captioned for a December day"
	)
	assert(page.moment_count() == 6, "and it installs six moments")
	assert(
		SunReportScript.day_of(page.moments()[0]) == SunReportScript.DECEMBER_SOLSTICE,
		"of the day the caption names"
	)
	page.free()


# --- aiming the sun -------------------------------------------------------------------


func test_pressing_aim_asks_for_the_chosen_moment() -> void:
	var page: SunWindow = _studying()
	assert(not page.apply_enabled(), "with nothing chosen there is nothing to aim at")
	page.choose_moment(0)
	assert(page.apply_enabled(), "a moment in the sun can be aimed at")
	assert(
		_ask(page, "Aim the sun at it") == "apply:21 June 08:00",
		"and pressing it asks for that moment"
	)
	page.free()


func test_aiming_with_nothing_chosen_says_which_thing_is_missing() -> void:
	var page: SunWindow = _studying()
	assert(_press(page, "Aim the sun at it"), "the button is there")
	assert(_announced.is_empty(), "but the page asks for nothing")
	assert(
		page.said() == SunWindowScript.NO_CHOICE,
		"and says what to do instead: %s" % page.said()
	)
	page.free()


func test_a_moment_after_dark_cannot_be_aimed_at_and_says_why() -> void:
	var page: SunWindow = _page()
	page.bind(SITE)
	page.use_preset(&"december_day")
	page.choose_moment(5)
	assert(
		SunReportScript.time_text(page.selected_moment()) == "18:00",
		"the last moment of a December day is six in the evening"
	)
	assert(not page.apply_enabled(), "and there is no sun to aim at then")
	assert(_press(page, "Aim the sun at it"), "the button is there")
	assert(
		page.said() == SunWindowScript.NO_SUN,
		"and the page says which fact is missing: %s" % page.said()
	)
	page.free()


# --- rendering the stills --------------------------------------------------------------


func test_pressing_render_asks_only_for_the_moments_the_sun_is_up_at() -> void:
	var page: SunWindow = _page()
	page.bind(SITE)
	page.use_preset(&"december_day")
	assert(page.moment_count() == 6, "six moments are studied")
	assert(page.renderable_moments().size() == 5, "five of them have a sun")
	assert(page.dark_moments().size() == 1, "and the sixth is after dark")
	assert(
		_ask(page, "Render the stills") == "render:5",
		"so the render asks for the five, not the six"
	)
	page.free()


func test_the_page_promises_only_the_stills_it_can_render() -> void:
	var page: SunWindow = _studying()
	assert(
		page.still_names().size() == page.renderable_moments().size(),
		"the names it offers are the moments it can render"
	)
	for name: String in page.still_names():
		assert(name.begins_with("sun-study-"), "named for the moment: %s" % name)
	page.free()


func test_a_page_with_no_moments_cannot_render_and_says_so() -> void:
	var page: SunWindow = _studying()
	page.clear_moments()
	assert(not page.render_enabled(), "there is nothing to render")
	assert(_press(page, "Render the stills"), "the button is there")
	assert(
		page.said() == SunWindowScript.NO_MOMENTS,
		"and the page says why: %s" % page.said()
	)
	page.free()


func test_a_moment_after_dark_is_still_a_row_of_the_study() -> void:
	var page: SunWindow = _page()
	page.bind(SITE)
	page.use_preset(&"december_day")
	assert(page.row_count() == 6, "all six moments are rows")
	var texts: Array[String] = page.row_texts()
	assert(
		texts[5].contains("no shadow"),
		"and the one after dark says so rather than leaving a hole: %s" % texts[5]
	)
	page.free()


# --- the height, and what the page says ------------------------------------------------


func test_the_height_is_stated_in_the_drawings_own_units() -> void:
	var page: SunWindow = _studying()
	assert(
		absf(page.height_m() - SunReportScript.DEFAULT_HEIGHT_M) < 1e-6,
		"a study starts with the fence a client's question is usually about"
	)
	var feet := UnitsScript.new()
	feet.system = UnitsScript.System.IMPERIAL
	page.set_units(feet)
	assert(page.height_in_hand() > 5.0, "an imperial drawing's field reads feet")
	assert(
		absf(page.height_m() - SunReportScript.DEFAULT_HEIGHT_M) < 0.02,
		"and the height in hand is the same height: %f m" % page.height_m()
	)
	assert(
		page.height_words().ends_with("ft"),
		"and the words are the drawing's own: %s" % page.height_words()
	)
	assert(
		page.row_texts()[0].contains("ft"),
		"so the rows read in feet too: %s" % page.row_texts()[0]
	)
	page.free()


func test_the_height_changes_what_the_study_says() -> void:
	var page: SunWindow = _studying()
	var before: String = page.row_texts()[0]
	page.set_height(3.6)
	assert(page.height_m() > 3.5, "the study casts a taller thing")
	assert(
		page.row_texts()[0] != before,
		"so the same moment casts a longer shadow: %s" % page.row_texts()[0]
	)
	assert(
		page.height_words().begins_with("3.6"),
		"and the guidance names the new height: %s" % page.height_words()
	)
	page.free()


func test_the_status_is_not_the_guidance() -> void:
	var page: SunWindow = _studying()
	page.set_day(200)
	page.set_hour(13.0)
	page._on_add_pressed()
	var said: String = page.said()
	assert(said.contains("added"), "the status says what the page last did: %s" % said)
	var guidance: String = page.hint()
	assert(guidance != "", "the guidance says what the study is, or what is missing")
	page.choose_moment(0)
	assert(
		page.hint().contains("45.0°N"),
		"and with all of it in hand the guidance is the study: %s" % page.hint()
	)
	# Everything under the sun changes the study, and none of it may rewrite the status: a status
	# rewritten by a refresh says nothing about what was done.
	page.set_height(2.5)
	page.use_preset(&"june_day")
	page.set_units(UnitsScript.new())
	assert(
		page.said() == said,
		"and refreshing never touches it: %s" % page.said()
	)
	page.free()


func test_the_guidance_says_what_is_missing_in_the_order_it_goes_missing() -> void:
	var page: SunWindow = _page()
	assert(page.hint() == SunWindowScript.NO_SITE, "no site is the first thing missing")
	page.bind(SITE)
	assert(page.hint() == SunWindowScript.NO_MOMENTS, "then no moments")
	page.use_preset(&"june_day")
	assert(page.hint() == SunWindowScript.NO_CHOICE, "then no moment chosen to aim at")
	page.choose_moment(0)
	assert(
		page.hint().contains("45.0°N"),
		"and with all of it in hand the guidance is the study: %s" % page.hint()
	)
	page.free()


func test_closing_the_page_by_the_button_or_by_the_x_announces_the_same_thing() -> void:
	var page: SunWindow = _studying()
	assert(_ask(page, "Close") == "close", "the close button announces itself")
	assert(not page.visible, "and takes the page off the screen")
	page.request_close()
	assert(_announced[_announced.size() - 1] == "close", "and so does the window's own x")
	page.free()