extends Node
## The page over the drawing: choosing a picture, saying how it lies, and what is already underneath.
##
## The whole page is driven off-tree, with no drawing, no file dialog and no screen - which is what the
## split between the page and the HUD is for. Nothing here calls `popup_centered`, because a window
## server is not something a test has.
##
## The buttons are pressed by their **captions**, through the same `find_children` walk the live
## demonstration uses, so a test cannot go on passing after a caption has been changed to something a
## person would not recognise.

const UnderlayWindowScript := preload("res://scripts/underlay_window.gd")
const UnitsScript := preload("res://scripts/draft/units.gd")
const RasterUnderlayScript := preload("res://scripts/draft/raster_underlay.gd")

## What the page announced, in order. A member rather than a captured local, because a lambda captures
## what it is given rather than sharing it - and the tests ask for the *last* announcement rather than
## for a count, so one page's announcements cannot leak into the next test's.
var _announced: Array[String] = []


# --- helpers --------------------------------------------------------------------------


## A page with no window server, no drawing and no HUD - built by hand, the way every `Window` page in
## this app is tested.
func _page() -> UnderlayWindow:
	var window := UnderlayWindowScript.new()
	window.build()
	window.choose_file_requested.connect(func() -> void: _announced.append("choose"))
	window.place_requested.connect(func() -> void: _announced.append("place"))
	window.apply_requested.connect(func() -> void: _announced.append("apply"))
	window.remove_requested.connect(func() -> void: _announced.append("remove"))
	window.closed.connect(func() -> void: _announced.append("close"))
	return window


## Press a button by the caption a person reads, and say what the page announced. Returns "" when the
## page carries no such button or announced nothing, which is a failure worth seeing rather than a
## silent no-op.
func _ask(window: UnderlayWindow, caption: String) -> String:
	var before := _announced.size()
	if not _press(window, caption):
		return ""
	if _announced.size() != before + 1:
		return ""
	return _announced[before]


## Press a button by the caption a person reads.
func _press(window: UnderlayWindow, caption: String) -> bool:
	for found: Node in window.find_children("*", "Button", true, false):
		var button := found as Button
		if button.text == caption:
			button.pressed.emit()
			return true
	return false


## A picture already under the drawing, as the HUD describes one.
func _row(id: int, name: String, width_m: float) -> Dictionary:
	return {
		"id": id, "name": name, "text": "%s, %s m across" % [name, String.num(width_m, 0)],
		"width_m": width_m, "rotation_deg": 0.0, "opacity": 0.65, "visible": true, "usable": true,
	}


# --- what the page says ----------------------------------------------------------------


func test_a_page_that_has_read_nothing_offers_nothing_to_place() -> void:
	var window := _page()
	assert(window.file_text() == UnderlayWindowScript.NO_PICTURE, window.file_text())
	assert(window.report_text() == "", "and it has nothing to report yet")
	assert(not window.place_enabled(), "so the button that puts one under the drawing is off")
	assert(not window.apply_enabled() and not window.remove_enabled(), "and so are the two that change one")
	assert(window.underlay_texts() == [UnderlayWindowScript.NOTHING_UNDER], str(window.underlay_texts()))
	window.free()


func test_the_page_says_what_it_is_waiting_for() -> void:
	var window := _page()
	window.show_file("sunny-bed")
	assert(not window.place_enabled(), "a picture with no size on the ground cannot be laid at one")
	assert(
		window._place_button.tooltip_text.contains("how far it lies across the ground"),
		window._place_button.tooltip_text
	)
	window.set_across_text("12")
	assert(window.place_enabled(), "and with a width it can")
	assert(String(window._place_button.tooltip_text).contains("under everything"), window._place_button.tooltip_text)
	# What a person types that is not a length is not a length.
	for nonsense: String in ["", "   ", "wide", "-4", "0"]:
		window.set_across_text(nonsense)
		assert(not window.place_enabled(), "so %s is not a width" % nonsense)
	window.free()


func test_the_width_is_typed_in_the_drawings_own_units() -> void:
	var window := _page()
	var metric := UnitsScript.new()
	window.set_units(metric)
	assert(window._across_caption.text == "Across the ground (m)", window._across_caption.text)
	window.set_across_text("12")
	assert(is_equal_approx(window.width_m(), 12.0), str(window.width_m()))
	# An imperial drawing types feet, and the number reaches the model as metres so that nothing
	# downstream has to know which drawing it came from.
	var imperial := UnitsScript.new()
	imperial.system = UnitsScript.System.IMPERIAL
	window.set_units(imperial)
	assert(window._across_caption.text == "Across the ground (ft)", window._across_caption.text)
	window.set_across_text("12")
	assert(is_equal_approx(window.width_m(), 3.6576), str(window.width_m()))
	# What the drawing suggests comes back in the unit it was asked in.
	window.set_suggested_width(12.0)
	assert(window.across_text() == "39.37", window.across_text())
	window.free()


func test_the_forms_three_numbers_are_the_ones_the_page_reports() -> void:
	var window := _page()
	window.set_across_text("20")
	window.set_turn(-15.0)
	window.set_see_through(30.0)
	assert(is_equal_approx(window.width_m(), 20.0), str(window.width_m()))
	assert(is_equal_approx(window.rotation_deg(), -15.0), str(window.rotation_deg()))
	assert(is_equal_approx(window.opacity(), 0.3), str(window.opacity()))
	# A new page starts at the module's own default rather than at some number written here twice.
	var fresh := _page()
	assert(
		is_equal_approx(fresh.opacity(), RasterUnderlayScript.DEFAULT_OPACITY),
		str(fresh.opacity())
	)
	assert(is_equal_approx(fresh.rotation_deg(), 0.0), str(fresh.rotation_deg()))
	window.free()
	fresh.free()


func test_the_report_and_the_status_line_are_the_pages_own_words() -> void:
	var window := _page()
	window.show_report("sunny-bed.png - PNG, 4000 x 3000 pixels")
	assert(window.report_text() == "sunny-bed.png - PNG, 4000 x 3000 pixels", window.report_text())
	window.say("the picture was not read")
	assert(window.said_text() == "the picture was not read", window.said_text())
	assert(window._status.text == "the picture was not read", window._status.text)
	window.free()


# --- what is already underneath ---------------------------------------------------------


func test_the_list_says_what_is_under_the_drawing() -> void:
	var window := _page()
	window.show_underlays([_row(4, "one", 10.0), _row(7, "two", 25.0)])
	var texts := window.underlay_texts()
	assert(texts.size() == 3, str(texts))
	assert(texts[0] == UnderlayWindowScript.NOTHING_CHOSEN, texts[0])
	assert(texts[1] == "one - one, 10 m across", texts[1])
	assert(texts[2] == "two - two, 25 m across", texts[2])
	assert(window.chosen_id() == 0, "and nothing is chosen to change yet")
	assert(not window.apply_enabled() and not window.remove_enabled(), "so neither button can act")
	window.free()


func test_choosing_a_picture_already_there_puts_its_own_numbers_in_the_form() -> void:
	var window := _page()
	window.show_underlays([_row(4, "one", 10.0), _row(7, "two", 25.0)])
	window.choose_underlay(2)
	assert(window.chosen_id() == 7, str(window.chosen_id()))
	assert(is_equal_approx(window.width_m(), 25.0), window.across_text())
	assert(is_equal_approx(window.opacity(), 0.65), str(window.opacity()))
	assert(window.apply_enabled() and window.remove_enabled(), "and now both buttons can act")
	# And refreshing the list under somebody's hand does not put their choice back to nothing.
	window.show_underlays([_row(4, "one", 10.0), _row(7, "two", 25.0)])
	assert(window.chosen_id() == 7, "the choice survives a refresh: %d" % window.chosen_id())
	# A picture that has gone from the drawing is not a choice any more.
	window.show_underlays([_row(4, "one", 10.0)])
	assert(window.chosen_id() == 0, "and a picture that is gone cannot stay chosen")
	assert(not window.apply_enabled(), "so the buttons go off again")
	window.free()


func test_a_choice_that_is_not_there_is_not_a_choice() -> void:
	var window := _page()
	window.show_underlays([_row(4, "one", 10.0)])
	window.choose_underlay(0)
	assert(window.chosen_id() == 0, "the first row is 'nothing chosen'")
	window.choose_underlay(99)
	assert(window.chosen_id() == 0, "and a row that does not exist is nothing either")
	window.free()


# --- the buttons ------------------------------------------------------------------------


func test_every_button_announces_what_a_person_asked_for() -> void:
	var window := _page()
	window.show_file("sunny-bed")
	window.set_across_text("12")
	assert(_ask(window, "Choose a picture...") == "choose", "the page carries the chooser")
	assert(_ask(window, "Put it under the drawing") == "place", "and the one that lays it down")
	window.show_underlays([_row(4, "one", 10.0)])
	window.choose_underlay(1)
	assert(_ask(window, "Apply these numbers") == "apply", "and the one that changes a picture already there")
	assert(_ask(window, "Take it off") == "remove", "and the one that takes it off")
	assert(
		_ask(window, "Close") == "close",
		"and closing the page is announced too, so the HUD can forget what was in hand"
	)
	# The captions above are every button the page carries, so a caption that changes to something a
	# person would not recognise fails a test rather than quietly going on working.
	assert(window.button_texts().size() == 5, str(window.button_texts()))
	assert(not _press(window, "Put it in the drawing"), "and a button that is not there is not there")
	window.free()